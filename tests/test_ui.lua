-- Singleplayer integration test: server + client + UI windows driven through their own handlers.
require "Canastra/CanastraServer"
require "Canastra/CanastraClient"
require "Canastra/UI/CanastraLobbyWindow"
require "Canastra/UI/CanastraGameWindow"
require "Canastra/CanastraContextMenu"

local C = Canastra.Cards
local R = Canastra.Rules
local B = Canastra.Bot
local S = CanastraServer
local CC = CanastraClient
local D = CanastraDraw

local failures, passes = 0, 0
local function check(cond, msg)
    if cond then passes = passes + 1 else failures = failures + 1 print("FAIL: " .. msg) end
end

local function advance(ms) MOCK_NOW = MOCK_NOW + ms end

local function renderAll()
    for _, win in ipairs({ CanastraLobbyWindow.instance, CanastraGameWindow.instance, CanastraRulesWindow.instance }) do
        if win then
            win.mouseOver = math.random() < 0.7
            win.mouseX = math.random(0, math.floor(win.width))
            win.mouseY = math.random(0, math.floor(win.height))
            win:render()
        end
    end
end

local function clickHit(win, pred)
    win:render()
    for i = #win.hits, 1, -1 do
        local r = win.hits[i]
        if pred(r) then
            win:onMouseDown(r.x + math.min(r.w, 6) / 2, r.y + r.h / 2)
            return true
        end
    end
    return false
end

local function selectCards(win, ids)
    win.selected = {}
    for _, id in ipairs(ids) do
        advance(400)
        win:toggleCard(id)
    end
end

-- Performs the bot's suggestion for the human seat through the game window's UI paths.
local function humanStep(win, g, seat)
    local a = B.nextAction(g, seat)
    if not a then return false, "no action" end
    local before = #g.log + g.round * 1000 + (g.turn * 7) + #g.hands[seat] * 13 + #g.pile * 17
    if a.type == "draw" then
        if not clickHit(win, function(r) return r.fn == CanastraGameWindow.clickStock end) then return false, "stock hit" end
    elseif a.type == "takePile" then
        if a.addTo then
            clickHit(win, function(r) return r.fn == CanastraGameWindow.clickOwnMeld and r.arg == a.addTo end)
            selectCards(win, a.cards or {})
        elseif a.melds then
            selectCards(win, a.melds[1].cards)
            win.staged = {}
            for i = 2, #a.melds do win.staged[#win.staged + 1] = a.melds[i].cards end
        end
        if not clickHit(win, function(r) return r.fn == CanastraGameWindow.clickPile end) then return false, "pile hit" end
    elseif a.type == "meld" then
        if a.adds and #a.adds > 0 then
            selectCards(win, a.adds[1].cards)
            if not clickHit(win, function(r) return r.fn == CanastraGameWindow.clickOwnMeld and r.arg == a.adds[1].meld end) then
                return false, "meld hit"
            end
        else
            for _, m in ipairs(a.melds) do
                selectCards(win, m.cards)
                win:newMeld()
            end
            if #win.staged > 0 then win:confirmStaged() end
        end
    elseif a.type == "discard" then
        if math.random() < 0.5 then
            advance(1000)
            win:toggleCard(a.card)
            win:toggleCard(a.card)
        else
            selectCards(win, { a.card })
            if not clickHit(win, function(r) return r.fn == CanastraGameWindow.clickPile end) then return false, "pile hit" end
        end
    end
    local after = #g.log + g.round * 1000 + (g.turn * 7) + #g.hands[seat] * 13 + #g.pile * 17
    local m = CC.currentMessage()
    if m and m.error then return false, "UI action " .. a.type .. " rejected: " .. m.text end
    if before == after and g.phase ~= "roundOver" then return false, "UI action " .. a.type .. " had no effect" end
    return true
end

local function playMatch(preset, n, rounds)
    CC.message = nil
    CanastraLobbyWindow.open()
    renderAll()
    CanastraLobbyWindow.pending.n = n
    CanastraLobbyWindow.pending.fillBots = true
    CanastraLobbyWindow.pending.rules = R.fromPreset(preset)
    if not clickHit(CanastraLobbyWindow.instance, function(r) return r.fn == CanastraLobbyWindow.create end) then
        check(false, preset .. ": create button not found")
        return
    end
    check(CC.info and CC.info.status == "lobby", preset .. ": table created via lobby button")
    renderAll()
    CanastraLobbyWindow.instance:openRules()
    renderAll()
    CanastraRulesWindow.instance:close()
    CC.send("start", { decks = 2 })
    check(CC.info and CC.info.status == "playing" and CanastraGameWindow.instance, preset .. ": game started")
    local win = CanastraGameWindow.instance
    local t = S.tables[CC.info.id]
    if preset == "canastra_brasileira" then
        local tip = CC.text("FourColorOff")
        check(clickHit(win, function(r) return r.tooltip == tip end), "four-colour toggle found")
        check(CanastraDraw.fourColor and (MOCK_FILES["Canastra_settings.txt"] or ""):find("fourColor=true", 1, true),
            "four-colour deck enabled and saved")
        win:sort("rank")
        check((MOCK_FILES["Canastra_settings.txt"] or ""):find("sortMode=rank", 1, true), "sort mode saved")
    end
    local played, steps, unsorted = 0, 0, 0
    while played < rounds and steps < 5000 do
        steps = steps + 1
        renderAll()
        local expected = C.copyList(win.order)
        if win.sortMode == "rank" then C.sortByRank(expected) else C.sortBySuit(expected) end
        for i = 1, #expected do
            if expected[i] ~= win.order[i] then unsorted = unsorted + 1 break end
        end
        local g = t.game
        if g.phase == "roundOver" or g.phase == "matchOver" then
            played = played + 1
            CC.send("nextRound")
            g = t.game
            check(g.phase == "draw", preset .. ": next round started")
        elseif g.turn == CC.seat then
            local ok, err = humanStep(win, g, CC.seat)
            if not ok then
                check(false, preset .. ": " .. tostring(err))
                break
            end
        else
            advance(1100)
            triggerEvent("OnTick")
        end
        if steps % 40 == 0 then triggerEvent("EveryOneMinute") end
    end
    check(played >= rounds, preset .. ": played " .. played .. " rounds in " .. steps .. " steps")
    check(unsorted == 0, preset .. ": hand stayed sorted after every draw (" .. unsorted .. " unsorted frames)")
    print(string.format("  %-20s %dp: %d rounds through the UI (%d steps)", preset, n, played, steps))
    win:leave()
    win:leave()
    check(CC.info == nil, preset .. ": left the table")
    local count = 0
    for _ in pairs(S.tables) do count = count + 1 end
    check(count == 0, preset .. ": table removed after last human left")
end

triggerEvent("OnGameStart")

-- context menu on a card deck opens the lobby
local deck = { __class = "InventoryItem", getFullType = function() return "Base.CardDeck" end }
local ctx = newMockContext()
triggerEvent("OnFillInventoryObjectContextMenu", 0, ctx, { deck })
check(#ctx.options == 1, "deck context option added")
if ctx.options[1] then ctx.options[1].onSelect() end
check(CanastraLobbyWindow.instance ~= nil, "context option opens lobby")
renderAll()

-- creating without decks is refused
MOCK_DECKS = 1
CanastraLobbyWindow.instance:create()
check(CC.info == nil and CC.currentMessage() and CC.currentMessage().error, "table refused without 2 decks")
MOCK_DECKS = 2

print("UI integration:")
playMatch("buraco_aberto", 4, 3)
playMatch("buraco_fechado", 2, 3)
playMatch("canastra_classica", 4, 2)
playMatch("stbl", 2, 2)
playMatch("buraco_1morto", 4, 2)
playMatch("canastra_brasileira", 4, 2)

check(MOCK_STATS.BOREDOM < 50 and MOCK_STATS.STRESS < 0.5, "playing reduced boredom and stress")

for _, e in ipairs(MOCK_ERRORS) do
    failures = failures + 1
    print("MOCK ERROR: " .. e)
end
local missing = {}
for k in pairs(MISSING_TEXT) do missing[#missing + 1] = k end
table.sort(missing)
for _, k in ipairs(missing) do
    failures = failures + 1
    print("MISSING TRANSLATION: " .. k)
end

print(string.format("\n%d passed, %d failed", passes, failures))
return failures
