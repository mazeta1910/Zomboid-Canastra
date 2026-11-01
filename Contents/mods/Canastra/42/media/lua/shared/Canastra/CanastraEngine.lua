require "Canastra/CanastraCards"
require "Canastra/CanastraRules"
require "Canastra/CanastraMelds"

local C = Canastra.Cards
local R = Canastra.Rules
local M = Canastra.Melds

local E = {}
Canastra.Engine = E

local LOG_SIZE = 10

local function log(g, entry)
    g.log[#g.log + 1] = entry
    while #g.log > LOG_SIZE do table.remove(g.log, 1) end
end

local function take(list, count)
    local out = {}
    for _ = 1, count do
        if #list == 0 then break end
        out[#out + 1] = table.remove(list)
    end
    return out
end

function E.newMatch(rules, numPlayers)
    local g = {
        rules = R.sanitize(rules),
        n = numPlayers == 4 and 4 or 2,
        teamOf = {},
        scores = { 0, 0 },
        round = 0,
        dealer = 0,
        phase = "idle",
        log = {},
        melds = { {}, {} },
        hands = {},
    }
    for s = 1, g.n do g.teamOf[s] = ((s - 1) % 2) + 1 end
    g.dealer = C.random(g.n)
    return g
end

function E.teamSeats(g, team)
    local t = {}
    for s = 1, g.n do
        if g.teamOf[s] == team then t[#t + 1] = s end
    end
    return t
end

-- Red threes (classic canasta) are laid aside as bonus cards and replaced from the stock.
function E.processRedThrees(g, seat)
    if not g.rules.redThrees then return end
    local team = g.teamOf[seat]
    local found = true
    while found do
        found = false
        local hand = g.hands[seat]
        for i = #hand, 1, -1 do
            if C.isRedThree(hand[i]) then
                local id = table.remove(hand, i)
                local r3 = g.redThrees[team]
                r3[#r3 + 1] = id
                log(g, { k = "Red3", s = seat })
                if #g.stock > 0 then
                    hand[#hand + 1] = table.remove(g.stock)
                    found = true
                end
            end
        end
    end
end

function E.startRound(g)
    local r = g.rules
    g.round = g.round + 1
    g.dealer = (g.dealer % g.n) + 1
    g.stock = C.shuffle(C.newShoe(2, r.jokers))
    g.hands = {}
    local hs = R.handSize(r, g.n)
    for s = 1, g.n do g.hands[s] = take(g.stock, hs) end
    g.dead = {}
    local deadPiles = R.deadPiles(r, g.n)
    if deadPiles == 2 then
        g.dead[1] = { cards = take(g.stock, r.deadSize), owner = 1, state = "open" }
        g.dead[2] = { cards = take(g.stock, r.deadSize), owner = 2, state = "open" }
    elseif deadPiles == 1 then
        g.dead[1] = { cards = take(g.stock, r.deadSize), owner = 0, state = "open" }
    end
    g.deadTakenBy = { false, false }
    g.pile = {}
    if r.openCard then
        local guard = 0
        while #g.stock > 0 and guard < 20 do
            guard = guard + 1
            local id = table.remove(g.stock)
            if r.redThrees and C.isRedThree(id) then
                table.insert(g.stock, C.random(#g.stock + 1), id)
            else
                g.pile[1] = id
                break
            end
        end
    end
    g.melds = { {}, {} }
    g.redThrees = { {}, {} }
    g.hasMelded = { false, false }
    g.nextMeldId = 1
    g.turn = (g.dealer % g.n) + 1
    g.phase = "draw"
    g.roundResult = nil
    g.winner = nil
    g.noDiscard = nil
    g.redrawOpen = r.firstRedraw and r.drawCount == 1 or false
    g.redrawCard = nil
    g.log = {}
    log(g, { k = "RoundStart", r = g.round })
    E.processRedThrees(g, g.turn)
end

function E.claimableDead(g, team)
    if not g.dead then return nil end
    for i, d in ipairs(g.dead) do
        if d.state == "open" and (d.owner == team or d.owner == 0) then return i end
    end
    return nil
end

function E.initialMin(g, team)
    if g.hasMelded[team] then return 0 end
    local v = g.rules.minInitialMeld or 0
    if v == -1 then
        local s = g.scores[team]
        if s < 0 then return 15 end
        if s < 1500 then return 50 end
        if s < 3000 then return 90 end
        return 120
    end
    return v
end

function E.findMeld(g, team, meldId)
    for i, m in ipairs(g.melds[team]) do
        if m.id == meldId then return m, i end
    end
    return nil
end

function E.isPileFrozen(g, team)
    if not g.rules.pileFreeze then return false end
    if not g.hasMelded[team] then return true end
    for _, id in ipairs(g.pile) do
        if M.isWild(id, g.rules) then return true end
    end
    return false
end

-- Checks the go-out requirement against the team's melds, replaced/extended by a pending plan.
local function meetsGoOut(g, team, plan)
    local req = g.rules.goOutRequires
    if req == "none" then return true end
    local function ok(res)
        if #res.cards < R.CANASTA_SIZE then return false end
        return req == "any" or res.clean
    end
    local updated = {}
    if plan then
        for _, u in ipairs(plan.updates) do
            updated[u.meldId] = true
            if ok(u.res) then return true end
        end
        for _, res in ipairs(plan.newMelds) do
            if ok(res) then return true end
        end
    end
    for _, m in ipairs(g.melds[team]) do
        if not updated[m.id] and ok(m) then return true end
    end
    return false
end

function E.canGoOut(g, team)
    return meetsGoOut(g, team, nil) and not E.claimableDead(g, team)
end

local function inHandSet(hand)
    local set = {}
    for _, id in ipairs(hand) do set[id] = true end
    return set
end

-- Builds a plan for laying new melds and extending existing ones.
-- spec.melds = { {cards = {...}}, ... }, spec.adds = { {meld = id, cards = {...}}, ... }
-- extraNew / extraRemaining support the take-pile path where the top card joins the hand cards.
local function buildPlan(g, seat, spec, opts)
    opts = opts or {}
    local rules = g.rules
    local team = g.teamOf[seat]
    local hand = g.hands[seat]
    local handSet = inHandSet(hand)
    local used, usedList = {}, {}
    local function use(id)
        if type(id) ~= "number" or not handSet[id] or used[id] then return false end
        used[id] = true
        usedList[#usedList + 1] = id
        return true
    end

    local plan = { team = team, newMelds = {}, updates = {}, used = usedList, blackThree = false }
    for mi, m in ipairs(spec.melds or {}) do
        local cards = {}
        for _, id in ipairs(m.cards or {}) do
            if not use(id) then return nil, "NotInHand" end
            cards[#cards + 1] = id
        end
        if mi == 1 and opts.topCard then cards[#cards + 1] = opts.topCard end
        local res = M.analyze(cards, rules)
        if not res then return nil, "InvalidMeld" end
        plan.newMelds[#plan.newMelds + 1] = res
    end

    local pending = {}
    for _, a in ipairs(spec.adds or {}) do
        local meld = E.findMeld(g, team, a.meld)
        if not meld then return nil, "NoSuchMeld" end
        local entry = pending[meld.id]
        if not entry then
            entry = { meld = meld, cards = C.copyList(meld.cards) }
            pending[meld.id] = entry
            pending[#pending + 1] = entry
        end
        for _, id in ipairs(a.cards or {}) do
            if not use(id) then return nil, "NotInHand" end
            entry.cards[#entry.cards + 1] = id
        end
        if a.withTop and opts.topCard then entry.cards[#entry.cards + 1] = opts.topCard end
    end
    for _, entry in ipairs(pending) do
        local res = M.analyze(entry.cards, rules, entry.meld.kind)
        if not res then return nil, "InvalidAdd" end
        plan.updates[#plan.updates + 1] = { meldId = entry.meld.id, res = res }
    end

    if #plan.newMelds == 0 and #plan.updates == 0 then return nil, "NothingToMeld" end

    local min = E.initialMin(g, team)
    if min > 0 then
        local pts = 0
        for _, res in ipairs(plan.newMelds) do pts = pts + M.points(res.cards, rules) end
        if pts < min then return nil, "InitialMin" end
    end

    if rules.redThrees == "classic" then
        for _, id in ipairs(usedList) do
            if C.isBlackThree(id) then plan.blackThree = true end
        end
    end

    local remaining = #hand - #usedList + (opts.extraCards or 0)
    plan.remaining = remaining
    local claim = E.claimableDead(g, team)
    local canOut = not claim and meetsGoOut(g, team, plan)
    if remaining == 0 then
        if claim then
            plan.after = "dead"
        elseif canOut and not rules.goOutNeedsDiscard then
            plan.after = "goOut"
        else
            return nil, "KeepOneCard"
        end
    elseif remaining == 1 and not claim and not canOut then
        return nil, "KeepDiscard"
    end
    if plan.blackThree and not (canOut and remaining <= 1) then
        return nil, "BlackThree"
    end
    return plan
end

local function applyPlan(g, seat, plan)
    local team = plan.team
    g.hands[seat] = C.removeIds(g.hands[seat], plan.used)
    for _, res in ipairs(plan.newMelds) do
        res.id = g.nextMeldId
        res.team = team
        g.nextMeldId = g.nextMeldId + 1
        local list = g.melds[team]
        list[#list + 1] = res
    end
    for _, u in ipairs(plan.updates) do
        local meld, idx = E.findMeld(g, team, u.meldId)
        u.res.id = meld.id
        u.res.team = team
        g.melds[team][idx] = u.res
    end
    g.hasMelded[team] = true
end

local function takeDead(g, seat, direct)
    local team = g.teamOf[seat]
    local idx = E.claimableDead(g, team)
    local d = g.dead[idx]
    d.state = "taken"
    g.deadTakenBy[team] = true
    local hand = g.hands[seat]
    for _, id in ipairs(d.cards) do hand[#hand + 1] = id end
    d.cards = {}
    log(g, { k = direct and "DeadDirect" or "DeadIndirect", s = seat })
    E.processRedThrees(g, seat)
end

local function scoreRound(g, goOutTeam)
    local rules = g.rules
    local result = { goOutTeam = goOutTeam or 0, teams = {} }
    for team = 1, 2 do
        local t = { melds = 0, clean = 0, dirty = 0, bonus = 0, goOut = 0, hand = 0, dead = 0, red3 = 0, black3 = 0 }
        for _, m in ipairs(g.melds[team]) do
            t.melds = t.melds + M.points(m.cards, rules)
            if M.isCanasta(m) then
                if m.clean then
                    t.clean = t.clean + 1
                    t.bonus = t.bonus + rules.bonusClean
                else
                    t.dirty = t.dirty + 1
                    t.bonus = t.bonus + rules.bonusDirty
                end
            end
        end
        if goOutTeam == team then t.goOut = rules.bonusGoOut end
        local penalty = rules.blackThreePenalty or 0
        for _, s in ipairs(E.teamSeats(g, team)) do
            local rest = {}
            for _, id in ipairs(g.hands[s]) do
                if penalty > 0 and C.isBlackThree(id) then
                    t.black3 = t.black3 - penalty
                else
                    rest[#rest + 1] = id
                end
            end
            t.hand = t.hand - M.points(rest, rules)
        end
        if R.deadPiles(rules, g.n) == 2 and not g.deadTakenBy[team] then
            t.dead = -rules.penaltyNoDead
        end
        local n3 = #g.redThrees[team]
        if n3 > 0 then
            if rules.redThrees == "canasta" then
                t.red3 = n3 * 100
                if t.clean + t.dirty == 0 then t.red3 = -t.red3 end
            else
                t.red3 = (n3 == 4) and 800 or n3 * 100
                if #g.melds[team] == 0 then t.red3 = -t.red3 end
            end
        end
        t.total = t.melds + t.bonus + t.goOut + t.hand + t.dead + t.red3 + t.black3
        result.teams[team] = t
    end
    return result
end

local function endRound(g, goOutTeam, seat)
    if goOutTeam then log(g, { k = "GoOut", s = seat }) end
    local result = scoreRound(g, goOutTeam)
    for team = 1, 2 do
        g.scores[team] = g.scores[team] + result.teams[team].total
    end
    g.roundResult = result
    g.phase = "roundOver"
    local target = g.rules.targetScore
    if (g.scores[1] >= target or g.scores[2] >= target) and g.scores[1] ~= g.scores[2] then
        g.phase = "matchOver"
        g.winner = g.scores[1] > g.scores[2] and 1 or 2
    end
end

local function nextTurn(g)
    if #g.stock == 0 then
        for _, d in ipairs(g.dead or {}) do
            if d.state == "open" then
                d.state = "stock"
                g.stock = d.cards
                d.cards = {}
                log(g, { k = "DeadToStock" })
                break
            end
        end
    end
    if #g.stock == 0 then
        log(g, { k = "StockEmpty" })
        endRound(g, nil, nil)
        return
    end
    g.turn = (g.turn % g.n) + 1
    g.phase = "draw"
    g.redrawOpen = false
    g.redrawCard = nil
    E.processRedThrees(g, g.turn)
end

local function afterPlan(g, seat, plan)
    if plan.after == "dead" then
        takeDead(g, seat, true)
    elseif plan.after == "goOut" then
        endRound(g, plan.team, seat)
    end
end

-- ---------------------------------------------------------------- actions

local handlers = {}

handlers.draw = function(g, seat, action, dry)
    if g.phase ~= "draw" then return false, "NotDrawPhase" end
    if dry then return true end
    local cards = take(g.stock, g.rules.drawCount)
    local hand = g.hands[seat]
    for _, id in ipairs(cards) do hand[#hand + 1] = id end
    log(g, { k = "Draw", s = seat, n = #cards })
    E.processRedThrees(g, seat)
    g.phase = "play"
    -- The round's first player may swap the first card drawn once (red-three replacements land last).
    if g.redrawOpen and #cards == 1 then g.redrawCard = hand[#hand] end
    g.redrawOpen = false
    return true
end

handlers.redraw = function(g, seat, action, dry)
    if g.phase ~= "play" or not g.redrawCard then return false, "NoRedraw" end
    local hand = g.hands[seat]
    local idx = C.indexOf(hand, g.redrawCard)
    if not idx then return false, "NoRedraw" end
    if #g.stock == 0 then return false, "NoRedraw" end
    if dry then return true end
    local card = table.remove(hand, idx)
    g.pile[#g.pile + 1] = card
    g.redrawCard = nil
    log(g, { k = "Redraw", s = seat, c = card })
    hand[#hand + 1] = table.remove(g.stock)
    E.processRedThrees(g, seat)
    return true
end

handlers.takePile = function(g, seat, action, dry)
    if g.phase ~= "draw" then return false, "NotDrawPhase" end
    local rules = g.rules
    local team = g.teamOf[seat]
    local n = #g.pile
    if n == 0 then return false, "PileEmpty" end
    local top = g.pile[n]

    if rules.pileLock then
        if M.isWild(top, rules) then return false, "PileTopWild" end
        if C.isBlackThree(top) then return false, "PileBlocked" end
    end

    if rules.pileTake == "free" and not rules.pileFreeze then
        if dry then return true end
        local hand = g.hands[seat]
        for _, id in ipairs(g.pile) do hand[#hand + 1] = id end
        g.pile = {}
        if n == 1 then g.noDiscard = top end
        log(g, { k = "TakePile", s = seat, n = n })
        E.processRedThrees(g, seat)
        g.phase = "play"
        return true
    end

    local frozen = E.isPileFrozen(g, team)
    local spec = { melds = action.melds or {}, adds = {} }
    if action.addTo then
        if frozen then return false, "PileFrozen" end
        spec.adds[1] = { meld = action.addTo, cards = action.cards or {}, withTop = true }
        spec.melds = action.melds or {}
        if #spec.melds > 0 then return false, "InvalidMeld" end
    elseif #spec.melds == 0 then
        return false, "PileNeedsMeld"
    end
    if frozen then
        local naturals = 0
        local topRank = C.rank(top)
        for _, id in ipairs(spec.melds[1].cards or {}) do
            if not M.isWild(id, rules) and C.rank(id) == topRank then naturals = naturals + 1 end
        end
        if naturals < 2 then return false, "PileFrozen" end
    end
    local plan, err = buildPlan(g, seat, spec, { topCard = top, extraCards = n - 1 })
    if not plan then return false, err end
    if dry then return true end

    table.remove(g.pile)
    local rest = g.pile
    g.pile = {}
    applyPlan(g, seat, plan)
    local hand = g.hands[seat]
    for _, id in ipairs(rest) do hand[#hand + 1] = id end
    log(g, { k = "TakePile", s = seat, n = n })
    g.phase = "play"
    E.processRedThrees(g, seat)
    afterPlan(g, seat, plan)
    return true
end

handlers.meld = function(g, seat, action, dry)
    if g.phase ~= "play" then return false, "NotPlayPhase" end
    local plan, err = buildPlan(g, seat, { melds = action.melds, adds = action.adds })
    if not plan then return false, err end
    if dry then return true end
    applyPlan(g, seat, plan)
    local count = #plan.used
    log(g, { k = "Meld", s = seat, n = count })
    afterPlan(g, seat, plan)
    return true
end

handlers.discard = function(g, seat, action, dry)
    if g.phase ~= "play" then return false, "NotPlayPhase" end
    local hand = g.hands[seat]
    local idx = C.indexOf(hand, action.card)
    if not idx then return false, "NotInHand" end
    if g.noDiscard == action.card and #hand > 1 then return false, "DiscardTaken" end
    local team = g.teamOf[seat]
    local after
    if #hand == 1 then
        if E.claimableDead(g, team) then
            after = "dead"
        elseif E.canGoOut(g, team) then
            after = "goOut"
        else
            return false, "CannotGoOut"
        end
    end
    if dry then return true end
    table.remove(hand, idx)
    g.pile[#g.pile + 1] = action.card
    g.noDiscard = nil
    log(g, { k = "Discard", s = seat, c = action.card })
    if after == "goOut" then
        endRound(g, team, seat)
        return true
    end
    if after == "dead" then takeDead(g, seat, false) end
    nextTurn(g)
    return true
end

-- Validates and (unless dry) applies an action. Returns ok, errorKey.
function E.apply(g, seat, action, dry)
    if type(action) ~= "table" then return false, "BadAction" end
    if g.phase ~= "draw" and g.phase ~= "play" then return false, "RoundNotActive" end
    if g.turn ~= seat then return false, "NotYourTurn" end
    local h = handlers[action.type]
    if not h then return false, "BadAction" end
    local ok, err = h(g, seat, action, dry)
    if ok and not dry and action.type ~= "draw" and action.type ~= "redraw" then
        g.redrawOpen = false
        g.redrawCard = nil
    end
    return ok, err
end

function E.check(g, seat, action)
    return E.apply(g, seat, action, true)
end

-- ---------------------------------------------------------------- views

local function copyMeld(m)
    return {
        id = m.id, kind = m.kind, cards = C.copyList(m.cards), clean = m.clean,
        canasta = M.isCanasta(m), wilds = m.wilds, suit = m.suit, rank = m.rank,
    }
end

-- Personalised snapshot for one seat: other hands, stock and dead piles are hidden.
function E.view(g, seat)
    local rules = g.rules
    local v = {
        n = g.n, you = seat, round = g.round, turn = g.turn, phase = g.phase, dealer = g.dealer,
        teamOf = C.copyList(g.teamOf), scores = C.copyList(g.scores),
        hand = C.copyList(g.hands[seat]), counts = {},
        stock = g.stock and #g.stock or 0,
        pileCount = g.pile and #g.pile or 0,
        melds = { {}, {} }, red3 = { {}, {} }, dead = {},
        hasMelded = { g.hasMelded and g.hasMelded[1] or false, g.hasMelded and g.hasMelded[2] or false },
        log = {}, rules = R.sanitize(rules), winner = g.winner,
    }
    for s = 1, g.n do v.counts[s] = g.hands[s] and #g.hands[s] or 0 end
    if g.pile then
        if rules.pileVisible then
            v.pile = C.copyList(g.pile)
        elseif #g.pile > 0 then
            v.pile = { g.pile[#g.pile] }
        else
            v.pile = {}
        end
    else
        v.pile = {}
    end
    for team = 1, 2 do
        for _, m in ipairs(g.melds[team] or {}) do v.melds[team][#v.melds[team] + 1] = copyMeld(m) end
        if g.redThrees then v.red3[team] = C.copyList(g.redThrees[team]) end
    end
    for i, d in ipairs(g.dead or {}) do
        v.dead[i] = { owner = d.owner, state = d.state, count = #d.cards }
    end
    for i, e in ipairs(g.log) do
        v.log[i] = { k = e.k, s = e.s, n = e.n, c = e.c, r = e.r }
    end
    local myTeam = g.teamOf[seat]
    if myTeam and g.hasMelded then
        v.initialMin = E.initialMin(g, myTeam)
        v.pileFrozen = E.isPileFrozen(g, myTeam)
        if g.turn == seat and g.redrawCard then v.redrawCard = g.redrawCard end
        local top = g.pile and g.pile[#g.pile]
        v.pileLocked = (rules.pileLock and top and (M.isWild(top, rules) or C.isBlackThree(top))) or false
        v.canGoOut = E.canGoOut(g, myTeam)
    end
    if g.roundResult then
        v.result = { goOutTeam = g.roundResult.goOutTeam, teams = {} }
        for team = 1, 2 do
            local t = {}
            for k, val in pairs(g.roundResult.teams[team]) do t[k] = val end
            v.result.teams[team] = t
        end
    end
    return v
end

return E
