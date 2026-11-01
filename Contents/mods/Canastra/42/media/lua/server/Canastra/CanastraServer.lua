if isClient() then return end

require "Canastra/CanastraBot"
require "Canastra/CanastraNet"

local N = Canastra.Net
local E = Canastra.Engine
local B = Canastra.Bot
local R = Canastra.Rules

CanastraServer = {}
local S = CanastraServer

S.tables = {}
S.byPlayer = {}
S.nextId = 1

local PRESENCE_INTERVAL = 5000
local MISSING_TIMEOUT = 30000

local function now()
    return getTimestampMs()
end

-- ------------------------------------------------------------------ helpers

function S.findPlayer(seat)
    if not seat or seat.kind ~= "human" then return nil end
    if isServer() then
        local list = getOnlinePlayers()
        for i = 0, list:size() - 1 do
            local p = list:get(i)
            if p:getUsername() == seat.key then return p end
        end
        return nil
    end
    for i = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(i)
        if p and N.playerKey(p) == seat.key then return p end
    end
    return nil
end

local function isNear(player, t, mult)
    local maxD = N.sandbox("MaxDistance", 8) * (mult or 1)
    if math.abs(player:getZ() - t.z) >= 1 then return false end
    local dx, dy = player:getX() - t.x, player:getY() - t.y
    return dx * dx + dy * dy <= maxD * maxD
end

local function humans(t)
    local list = {}
    for i = 1, t.n do
        if t.seats[i].kind == "human" then list[#list + 1] = i end
    end
    return list
end

local function botName(t)
    local used = {}
    for _, seat in pairs(t.seats) do
        if seat.name then used[seat.name] = true end
    end
    for _, n in ipairs(B.NAMES) do
        local name = "Bot " .. n
        if not used[name] then return name end
    end
    return "Bot"
end

local function newBotSeat(t)
    return { kind = "bot", name = botName(t) }
end

local function info(t)
    local seats = {}
    for i = 1, t.n do
        local s = t.seats[i]
        seats[i] = { kind = s.kind, name = s.name or "", key = s.key or "" }
    end
    return {
        id = t.id, n = t.n, status = t.status, hostKey = t.hostKey, hostName = t.hostName,
        rules = R.sanitize(t.rules), seats = seats, x = t.x, y = t.y, z = t.z,
    }
end

local function summary(t)
    local filled, open = 0, false
    for i = 1, t.n do
        local k = t.seats[i].kind
        if k ~= "empty" then filled = filled + 1 end
        if k == "empty" or (t.status == "playing" and k == "bot") then open = true end
    end
    return {
        id = t.id, n = t.n, status = t.status, hostName = t.hostName, x = t.x, y = t.y, z = t.z,
        filled = filled, open = open, preset = t.rules.preset or "custom",
    }
end

function S.listPayload()
    local list = {}
    for _, t in pairs(S.tables) do list[#list + 1] = summary(t) end
    return { tables = list }
end

function S.broadcastList()
    N.toAll("list", S.listPayload())
end

local function sendError(player, key)
    N.toClient(player, "error", { key = key })
end

function S.pushState(t, onlyKey)
    for i = 1, t.n do
        local seat = t.seats[i]
        if seat.kind == "human" and (not onlyKey or seat.key == onlyKey) then
            local p = S.findPlayer(seat)
            if p then
                local args = { info = info(t), seat = i }
                if t.game then args.view = E.view(t.game, i) end
                N.toClient(p, "table", args)
            end
        end
    end
end

local function scheduleBot(t)
    t.botAt = nil
    local g = t.game
    if t.status ~= "playing" or not g then return end
    if g.phase ~= "draw" and g.phase ~= "play" then return end
    if t.seats[g.turn].kind == "bot" then
        t.botAt = now() + math.floor(N.sandbox("BotDelay", 1.0) * 1000)
    end
end

local function relax(player, boredom, unhappiness, stress)
    pcall(function()
        local stats = player:getStats()
        if boredom > 0 then stats:remove(CharacterStat.BOREDOM, boredom) end
        if unhappiness > 0 then stats:remove(CharacterStat.UNHAPPINESS, unhappiness) end
        if stress > 0 then stats:remove(CharacterStat.STRESS, stress) end
    end)
end

local function rewardWinners(t)
    local g = t.game
    if not g or g.phase ~= "matchOver" or t.rewarded then return end
    t.rewarded = true
    local bonus = N.sandbox("WinUnhappinessBonus", 10)
    for _, i in ipairs(humans(t)) do
        if g.teamOf[i] == g.winner then
            local p = S.findPlayer(t.seats[i])
            if p then relax(p, bonus, bonus, 0) end
        end
    end
end

local function afterChange(t)
    rewardWinners(t)
    S.pushState(t)
    scheduleBot(t)
end

local function removeTable(t)
    for i = 1, t.n do
        local seat = t.seats[i]
        if seat.key then S.byPlayer[seat.key] = nil end
    end
    S.tables[t.id] = nil
end

local function vacate(t, i)
    local seat = t.seats[i]
    if seat.key then S.byPlayer[seat.key] = nil end
    if t.status == "lobby" then
        t.seats[i] = { kind = "empty" }
    else
        t.seats[i] = newBotSeat(t)
    end
    local hs = humans(t)
    if #hs == 0 then
        removeTable(t)
        return
    end
    if seat.key == t.hostKey then
        local h = t.seats[hs[1]]
        t.hostKey, t.hostName = h.key, h.name
    end
    S.pushState(t)
    scheduleBot(t)
end

function S.seatOf(player)
    local key = N.playerKey(player)
    local id = S.byPlayer[key]
    local t = id and S.tables[id]
    if not t then return nil end
    for i = 1, t.n do
        if t.seats[i].key == key then return t, i end
    end
    return nil
end

local function hasDecks(player, args)
    local need = N.sandbox("RequiredDecks", 2)
    if need <= 0 then return true end
    local count = N.countDecks(player)
    -- Dedicated servers may lag behind the client's inventory; accept the client's count too.
    if isServer() and args and tonumber(args.decks) then
        count = math.max(count, tonumber(args.decks))
    end
    return count >= need
end

local function sanitizeAction(a)
    if type(a) ~= "table" then return nil end
    local function ids(list)
        local out = {}
        if type(list) == "table" then
            for _, v in ipairs(list) do
                local n = tonumber(v)
                if n then out[#out + 1] = n end
            end
        end
        return out
    end
    local function melds(list)
        local out = {}
        if type(list) == "table" then
            for _, m in ipairs(list) do
                if type(m) == "table" then out[#out + 1] = { cards = ids(m.cards) } end
            end
        end
        return out
    end
    local out = { type = tostring(a.type) }
    out.card = tonumber(a.card)
    out.addTo = tonumber(a.addTo)
    out.cards = ids(a.cards)
    out.melds = melds(a.melds)
    out.adds = {}
    if type(a.adds) == "table" then
        for _, ad in ipairs(a.adds) do
            if type(ad) == "table" and tonumber(ad.meld) then
                out.adds[#out.adds + 1] = { meld = tonumber(ad.meld), cards = ids(ad.cards) }
            end
        end
    end
    return out
end

-- ------------------------------------------------------------------ commands

local Cmd = {}

function Cmd.list(player, args)
    N.toClient(player, "list", S.listPayload())
end

function Cmd.sync(player, args)
    local t = S.seatOf(player)
    if t then
        S.pushState(t, N.playerKey(player))
    else
        N.toClient(player, "left", {})
    end
end

function Cmd.create(player, args)
    local key = N.playerKey(player)
    if S.seatOf(player) then return sendError(player, "AlreadySeated") end
    if not hasDecks(player, args) then return sendError(player, "NeedDecks") end
    local n = tonumber(args.n) == 4 and 4 or 2
    local t = {
        id = S.nextId, n = n, status = "lobby", rules = R.sanitize(args.rules),
        hostKey = key, hostName = N.playerName(player),
        x = math.floor(player:getX()), y = math.floor(player:getY()), z = math.floor(player:getZ()),
        seats = {},
    }
    S.nextId = S.nextId + 1
    t.seats[1] = { kind = "human", key = key, name = t.hostName }
    for i = 2, n do
        if args.fillBots and N.sandbox("AllowBots", true) then
            t.seats[i] = newBotSeat(t)
        else
            t.seats[i] = { kind = "empty" }
        end
    end
    S.tables[t.id] = t
    S.byPlayer[key] = t.id
    S.pushState(t)
    S.broadcastList()
end

function Cmd.join(player, args)
    local t = S.tables[tonumber(args.id) or -1]
    if not t then return sendError(player, "NoTable") end
    local key = N.playerKey(player)
    local current = S.seatOf(player)
    if current == t then return S.pushState(t, key) end
    if current then return sendError(player, "AlreadySeated") end
    if not isNear(player, t) then return sendError(player, "TooFar") end
    local wanted = t.status == "lobby" and "empty" or "bot"
    local seatIdx = tonumber(args.seat)
    if not seatIdx or not t.seats[seatIdx] or t.seats[seatIdx].kind ~= wanted then
        seatIdx = nil
        for i = 1, t.n do
            if t.seats[i].kind == wanted then seatIdx = i break end
        end
    end
    if not seatIdx then return sendError(player, "TableFull") end
    t.seats[seatIdx] = { kind = "human", key = key, name = N.playerName(player) }
    S.byPlayer[key] = t.id
    S.pushState(t)
    scheduleBot(t)
    S.broadcastList()
end

function Cmd.leave(player, args)
    local t, i = S.seatOf(player)
    N.toClient(player, "left", {})
    if not t then return end
    vacate(t, i)
    S.broadcastList()
end

local function hostTable(player, needLobby)
    local t = S.seatOf(player)
    if not t then return nil end
    if t.hostKey ~= N.playerKey(player) then
        sendError(player, "NotHost")
        return nil
    end
    if needLobby and t.status ~= "lobby" then return nil end
    return t
end

function Cmd.addBot(player, args)
    local t = hostTable(player, true)
    if not t then return end
    if not N.sandbox("AllowBots", true) then return sendError(player, "BotsDisabled") end
    local i = tonumber(args.seat)
    if i and t.seats[i] and t.seats[i].kind == "empty" then
        t.seats[i] = newBotSeat(t)
        S.pushState(t)
        S.broadcastList()
    end
end

function Cmd.kick(player, args)
    local t = hostTable(player, true)
    if not t then return end
    local i = tonumber(args.seat)
    local seat = i and t.seats[i]
    if not seat or seat.kind == "empty" or seat.key == t.hostKey then return end
    if seat.kind == "human" then
        local p = S.findPlayer(seat)
        S.byPlayer[seat.key] = nil
        if p then N.toClient(p, "left", { kicked = true }) end
    end
    t.seats[i] = { kind = "empty" }
    S.pushState(t)
    S.broadcastList()
end

function Cmd.moveSeat(player, args)
    local t, from = S.seatOf(player)
    if not t or t.status ~= "lobby" then return end
    local to = tonumber(args.seat)
    if not to or not t.seats[to] or t.seats[to].kind == "human" then return end
    t.seats[from], t.seats[to] = t.seats[to], t.seats[from]
    S.pushState(t)
end

function Cmd.setRules(player, args)
    local t = hostTable(player, true)
    if not t then return end
    t.rules = R.sanitize(args.rules)
    local n = tonumber(args.n)
    if n == 2 or n == 4 then
        if n == 2 and t.n == 4 then
            for i = 3, 4 do
                if t.seats[i].kind == "human" then return sendError(player, "SeatsTaken") end
            end
            t.seats[3], t.seats[4] = nil, nil
        elseif n == 4 and t.n == 2 then
            t.seats[3] = { kind = "empty" }
            t.seats[4] = { kind = "empty" }
        end
        t.n = n
    end
    S.pushState(t)
    S.broadcastList()
end

function Cmd.start(player, args)
    local t = hostTable(player, true)
    if not t then return end
    for i = 1, t.n do
        if t.seats[i].kind == "empty" then return sendError(player, "SeatsEmpty") end
    end
    if not hasDecks(player, args) then return sendError(player, "NeedDecks") end
    t.game = E.newMatch(t.rules, t.n)
    E.startRound(t.game)
    t.status = "playing"
    t.rewarded = false
    afterChange(t)
    S.broadcastList()
end

function Cmd.action(player, args)
    local t, i = S.seatOf(player)
    if not t or t.status ~= "playing" or not t.game then return end
    local action = sanitizeAction(args.action)
    if not action then return end
    local ok, err = E.apply(t.game, i, action)
    if not ok then
        sendError(player, err or "BadAction")
        S.pushState(t, N.playerKey(player))
        return
    end
    afterChange(t)
end

function Cmd.nextRound(player, args)
    local t = hostTable(player, false)
    if not t or t.status ~= "playing" or not t.game then return end
    local g = t.game
    if g.phase == "roundOver" then
        E.startRound(g)
    elseif g.phase == "matchOver" then
        t.game = E.newMatch(t.rules, t.n)
        E.startRound(t.game)
        t.rewarded = false
    else
        return
    end
    afterChange(t)
end

function Cmd.backToLobby(player, args)
    local t = hostTable(player, false)
    if not t or t.status ~= "playing" then return end
    if t.game and t.game.phase ~= "matchOver" and t.game.phase ~= "roundOver" then return end
    t.status = "lobby"
    t.game = nil
    t.botAt = nil
    S.pushState(t)
    S.broadcastList()
end

function S.onCommand(player, command, args)
    local f = Cmd[command]
    if f and player then f(player, args or {}) end
end

-- ------------------------------------------------------------------ timers

local function botStep(t)
    local g = t.game
    local seat = g.turn
    local action = B.nextAction(g, seat)
    local ok = action and E.apply(g, seat, action)
    if not ok then
        if g.phase == "draw" then
            E.apply(g, seat, { type = "draw" })
        else
            for _, id in ipairs(g.hands[seat]) do
                if E.apply(g, seat, { type = "discard", card = id }) then break end
            end
        end
    end
    afterChange(t)
end

local lastPresence = 0

local function checkPresence()
    for _, t in pairs(S.tables) do
        for i = 1, t.n do
            local seat = t.seats[i]
            if seat.kind == "human" then
                if S.findPlayer(seat) then
                    seat.missingSince = nil
                elseif not seat.missingSince then
                    seat.missingSince = now()
                elseif now() - seat.missingSince > MISSING_TIMEOUT then
                    vacate(t, i)
                    S.broadcastList()
                    break
                end
            end
        end
    end
end

function S.onTick()
    local ts = now()
    for _, t in pairs(S.tables) do
        if t.botAt and ts >= t.botAt then
            t.botAt = nil
            botStep(t)
        end
    end
    if ts - lastPresence > PRESENCE_INTERVAL then
        lastPresence = ts
        checkPresence()
    end
end

function S.everyMinute()
    local boredom = N.sandbox("BoredomPerMinute", 0.3)
    local unhappiness = N.sandbox("UnhappinessPerMinute", 0.1)
    local stress = N.sandbox("StressPerMinute", 0.002)
    for _, t in pairs(S.tables) do
        if t.status == "playing" then
            for _, i in ipairs(humans(t)) do
                local p = S.findPlayer(t.seats[i])
                if p and isNear(p, t, 2) then relax(p, boredom, unhappiness, stress) end
            end
        end
    end
end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module == N.MODULE then S.onCommand(player, command, args) end
end)
Events.OnTick.Add(S.onTick)
Events.EveryOneMinute.Add(S.everyMinute)
