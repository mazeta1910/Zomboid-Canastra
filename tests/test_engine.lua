require "Canastra/CanastraBot"

local C = Canastra.Cards
local R = Canastra.Rules
local M = Canastra.Melds
local E = Canastra.Engine
local B = Canastra.Bot

local failures, passes = 0, 0
local function check(cond, msg)
    if cond then
        passes = passes + 1
    else
        failures = failures + 1
        print("FAIL: " .. msg)
    end
end

local SUITS = { S = 1, H = 2, C = 3, D = 4 }
local RANKS = { A = 1, J = 11, Q = 12, K = 13 }
-- c("10H"), c("AS", 2) (second deck copy), c("JK")
local function c(s, copy)
    copy = copy or 1
    if s == "JK" then return C.make(copy, C.JOKER, 1) end
    local suit = SUITS[s:sub(-1)]
    local r = s:sub(1, -2)
    local rank = RANKS[r] or tonumber(r)
    return C.make(copy, suit, rank)
end
local function cards(list)
    local t = {}
    for w in list:gmatch("%S+") do
        local name, copy = w:match("^(.-)/(%d)$")
        if name then t[#t + 1] = c(name, tonumber(copy)) else t[#t + 1] = c(w) end
    end
    return t
end

-- ------------------------------------------------------------ meld analysis
local buraco = R.fromPreset("buraco_aberto")
local stbl = R.fromPreset("stbl")
local canasta = R.fromPreset("canastra_classica")

local res = M.analyze(cards("5H 6H 7H"), buraco)
check(res and res.kind == "seq" and res.clean, "natural run is clean sequence")
check(M.analyze(cards("5H 6S 7H"), buraco) == nil, "mixed suits are not a run")
res = M.analyze(cards("5H 2C 7H"), buraco)
check(res and res.kind == "seq" and not res.clean and res.cards[2] == c("2C"), "two fills gap as wild")
res = M.analyze(cards("AH 2H 3H"), buraco)
check(res and res.clean, "same-suit two in natural place keeps run clean")
res = M.analyze(cards("QH KH AH"), buraco)
check(res and res.hi == 14, "ace can close a run high")
check(M.analyze(cards("KH AH 2S"), buraco) == nil or M.analyze(cards("KH AH 2S"), buraco).lo >= 12, "no wrap-around runs")
check(M.analyze(cards("5H 2C 7H 2D"), buraco) == nil, "buraco allows only one wild")
res = M.analyze(cards("AH 2H 3H 4H 5H 6H 7H 8H 9H 10H JH QH KH AH/2"), buraco)
check(res and #res.cards == 14 and res.clean, "ace-to-ace run with two decks")
res = M.analyze(cards("7H 7S 7D"), buraco)
check(res and res.kind == "set", "trinca is a set in buraco")
check(M.analyze(cards("7H 7S 7D"), stbl) == nil, "STBL forbids sets")
res = M.analyze(cards("7H 7S 2D"), buraco)
check(res and res.kind == "set" and res.wilds == 1, "set with one wild")
check(M.analyze(cards("7H 2S 2D"), buraco) == nil, "set needs two naturals")
res = M.analyze(cards("7H 7S JK 2D"), canasta)
check(res and res.kind == "set" and res.wilds == 2, "canasta allows several wilds")
check(M.analyze(cards("7H 7S JK 2D 2C"), canasta) ~= nil, "canasta allows 3 wilds")
check(M.analyze(cards("7H 7S JK 2D 2C JK/2"), canasta) == nil, "canasta forbids 4 wilds")
check(M.analyze(cards("5H 6H 7H"), canasta) == nil, "classic canasta has no runs")
check(M.analyze(cards("3S 3C 3S/2"), canasta) ~= nil, "black threes can form a natural set")
check(M.analyze(cards("3S 3C JK"), canasta) == nil, "black threes cannot take wilds")
res = M.analyze(cards("5H 6H 7H 8H 9H 10H 2S"), buraco)
check(res and #res.cards == 7 and not res.clean, "dirty canastra")

-- ------------------------------------------------------------ scripted engine scenarios
local function scenario(preset, n)
    local g = E.newMatch(R.fromPreset(preset), n or 2)
    E.startRound(g)
    return g
end

do
    local g = scenario("buraco_aberto")
    g.turn = 1
    g.phase = "draw"
    g.hands[1] = cards("5H 6H 7H 9S 9C")
    g.pile = cards("KD")
    check(E.check(g, 1, { type = "meld", melds = { { cards = cards("5H 6H 7H") } } }) == false, "cannot meld during draw phase")
    check(E.apply(g, 1, { type = "takePile" }), "free pile take")
    check(#g.hands[1] == 6 and g.phase == "play", "pile went to hand")
    local ok, err = E.apply(g, 1, { type = "meld", melds = { { cards = cards("5H 6H 7H") } } })
    check(ok, "meld run: " .. tostring(err))
    check(#g.melds[1] == 1, "meld registered")
    ok, err = E.apply(g, 1, { type = "meld", melds = { { cards = cards("9S 9C KD") } } })
    check(not ok and err == "InvalidMeld", "invalid set rejected")
    ok, err = E.apply(g, 1, { type = "discard", card = c("KD") })
    check(not ok and err == "DiscardTaken", "cannot discard the single card just taken from the pile")
    ok = E.apply(g, 1, { type = "discard", card = c("9S") })
    check(ok and g.turn == 2 and g.phase == "draw", "discard passes turn")
end

do
    -- Emptying the hand by melding takes the dead pile directly and the turn continues.
    local g = scenario("buraco_aberto")
    g.turn, g.phase = 1, "play"
    g.hands[1] = cards("5H 6H 7H")
    local ok, err = E.apply(g, 1, { type = "meld", melds = { { cards = cards("5H 6H 7H") } } })
    check(ok, "meld all cards into dead pile: " .. tostring(err))
    check(#g.hands[1] == 11 and g.phase == "play" and g.turn == 1, "dead pile taken directly")
    check(g.dead[1].state == "taken" and g.deadTakenBy[1], "dead pile marked taken")
end

do
    -- Keeping a single card that cannot be discarded is illegal once the dead pile is gone.
    local g = scenario("buraco_aberto")
    g.turn, g.phase = 1, "play"
    g.dead[1].state = "taken"
    g.deadTakenBy[1] = true
    g.hands[1] = cards("5H 6H 7H 9C")
    local ok, err = E.apply(g, 1, { type = "meld", melds = { { cards = cards("5H 6H 7H") } } })
    check(not ok and err == "KeepDiscard", "must keep a discardable card")
end

do
    -- Going out needs a clean canastra in buraco.
    local g = scenario("buraco_aberto")
    g.turn, g.phase = 1, "play"
    g.dead[1].state = "taken"
    g.deadTakenBy[1] = true
    g.melds[1] = { M.analyze(cards("5S 6S 7S 8S 9S 10S 2C"), buraco) }
    g.melds[1][1].id = 99
    g.hasMelded[1] = true
    g.hands[1] = cards("KD")
    local ok, err = E.apply(g, 1, { type = "discard", card = c("KD") })
    check(not ok and err == "CannotGoOut", "dirty canastra does not allow going out in buraco")
    g.melds[1][2] = M.analyze(cards("5H 6H 7H 8H 9H 10H JH"), buraco)
    g.melds[1][2].id = 100
    ok, err = E.apply(g, 1, { type = "discard", card = c("KD") })
    check(ok and g.phase ~= "draw" and g.roundResult and g.roundResult.goOutTeam == 1, "go out with clean canastra")
    local t = g.roundResult.teams[1]
    check(t.bonus == 300 and t.goOut == 100, "canastra bonuses and go-out bonus scored")
end

do
    -- Closed buraco: the pile's top card must be melded immediately.
    local g = scenario("buraco_fechado")
    g.turn, g.phase = 1, "draw"
    g.hands[1] = cards("5H 6H 9C 9D")
    g.pile = cards("KS 7H")
    local ok, err = E.apply(g, 1, { type = "takePile" })
    check(not ok and err == "PileNeedsMeld", "closed pile needs a meld")
    ok, err = E.apply(g, 1, { type = "takePile", melds = { { cards = cards("9C 9D") } } })
    check(not ok, "top card must fit the meld")
    ok, err = E.apply(g, 1, { type = "takePile", melds = { { cards = cards("5H 6H") } } })
    check(ok, "closed pile take with top card: " .. tostring(err))
    check(#g.melds[1] == 1 and #g.melds[1][1].cards == 3, "top card melded")
    check(C.indexOf(g.hands[1], c("KS")) ~= nil and #g.pile == 0, "rest of pile to hand")
end

do
    -- Classic canasta: initial meld minimum and frozen pile.
    local g = scenario("canastra_classica")
    g.turn, g.phase = 1, "play"
    g.hands[1] = cards("4H 4S 4D 9C KD QD")
    local ok, err = E.apply(g, 1, { type = "meld", melds = { { cards = cards("4H 4S 4D") } } })
    check(not ok and err == "InitialMin", "initial meld minimum enforced (15 < 50)")
    g.hands[1] = cards("KH KS KD AH AS AD 9C 9D")
    ok, err = E.apply(g, 1, { type = "meld", melds = { { cards = cards("KH KS KD") }, { cards = cards("AH AS AD") } } })
    check(ok, "initial meld reaching 90 points: " .. tostring(err))
    g.phase = "draw"
    g.pile = cards("5S JK 9S")
    ok, err = E.apply(g, 1, { type = "takePile", melds = { { cards = cards("9C 2D") } } })
    check(not ok and err == "PileFrozen", "frozen pile requires natural pair")
    g.hands[1] = cards("9C 9D 7S 8S")
    ok, err = E.apply(g, 1, { type = "takePile", melds = { { cards = cards("9C 9D") } } })
    check(ok, "frozen pile taken with natural pair: " .. tostring(err))
end

do
    -- Red threes are laid aside and replaced.
    local g = scenario("canastra_classica")
    g.hands[1] = cards("3H 5S 6S")
    E.processRedThrees(g, 1)
    check(#g.redThrees[1] >= 1 and #g.hands[1] == 3 and C.indexOf(g.hands[1], c("3H")) == nil, "red three replaced")

    -- Red threes are only laid down on their owner's turn.
    g = scenario("canastra_brasileira")
    g.turn, g.phase = 1, "play"
    g.redThrees = { {}, {} }
    g.hands[1] = cards("9C KD 5S")
    g.hands[2] = cards("3D 5H 6H")
    g.noDiscard = nil
    local before = #g.redThrees[2]
    E.apply(g, 1, { type = "discard", card = c("KD") })
    check(before == 0 and g.turn == 2 and #g.redThrees[2] == 1 and C.indexOf(g.hands[2], c("3D")) == nil,
        "red three laid down when its owner's turn starts")
    for _ = 1, 20 do
        local fresh = E.newMatch(R.fromPreset("canastra_brasileira"), 4)
        E.startRound(fresh)
        local waiting = fresh.teamOf[fresh.turn] == 1 and 2 or 1
        if #fresh.redThrees[waiting] > 0 then
            check(false, "team that has not played yet laid red threes at the deal")
            break
        end
    end
end

do
    -- Brazilian canasta: sets only of A, 4 and K; runs still allowed.
    local br = R.fromPreset("canastra_brasileira")
    check(M.analyze(cards("AH AS AD"), br) ~= nil, "set of aces allowed")
    check(M.analyze(cards("4H 4S 2D"), br) ~= nil, "set of fours allowed")
    check(M.analyze(cards("KH KS KD"), br) ~= nil, "set of kings allowed")
    check(M.analyze(cards("7H 7S 7D"), br) == nil, "set of sevens forbidden")
    check(M.analyze(cards("3S 4S 5S"), br) == nil, "black three cannot join a run")
    check(M.analyze(cards("3C 3S 3C/2"), br) == nil, "black threes cannot form a set")
    check(M.analyze(cards("2S 4S 5S"), br) ~= nil, "a wild may stand in the three's place")
    check(M.analyze(cards("3S 4S 5S"), canasta) == nil and M.analyze(cards("3S 4S 5S"), buraco) ~= nil,
        "black three restriction only applies with red-three rules")

    -- The first player may swap the first drawn card once; nobody else can.
    do
        local g = scenario("canastra_brasileira", 4)
        local first = g.turn
        local ok, err = E.apply(g, first, { type = "redraw" })
        check(not ok and err == "NoRedraw", "no swap before drawing")
        E.apply(g, first, { type = "draw" })
        local drawn = g.redrawCard
        local handSize, pileSize = #g.hands[first], #g.pile
        ok, err = E.apply(g, first, { type = "redraw" })
        check(ok and drawn and g.pile[#g.pile] == drawn and #g.hands[first] >= handSize and #g.pile == pileSize + 1
            and C.indexOf(g.hands[first], drawn) == nil and g.phase == "play" and g.turn == first,
            "first player swaps the drawn card and keeps playing: " .. tostring(err))
        ok, err = E.apply(g, first, { type = "redraw" })
        check(not ok and err == "NoRedraw", "the swap only happens once")
        local discard = g.hands[first][1]
        E.apply(g, first, { type = "discard", card = discard })
        local second = g.turn
        E.apply(g, second, { type = "draw" })
        ok, err = E.apply(g, second, { type = "redraw" })
        check(second ~= first and not ok and err == "NoRedraw", "the next player cannot swap")

        g = scenario("canastra_brasileira", 4)
        first = g.turn
        E.apply(g, first, { type = "draw" })
        E.apply(g, first, { type = "discard", card = g.hands[first][1] })
        check(g.redrawCard == nil, "swap expires when the first turn ends")
        check(scenario("buraco_aberto", 4).redrawOpen == false, "swap disabled outside its rule")
    end

    -- One shared dead pile in 1x1, one per team in 2x2.
    local g2 = scenario("canastra_brasileira", 2)
    check(#g2.dead == 1 and g2.dead[1].owner == 0 and #g2.dead[1].cards == 11, "1x1: a single shared dead pile")
    local g4 = scenario("canastra_brasileira", 4)
    check(#g4.dead == 2 and g4.dead[1].owner == 1 and g4.dead[2].owner == 2, "2x2: one dead pile per team")

    -- Black threes and wilds on top lock the pile.
    local g = scenario("canastra_brasileira")
    g.turn, g.phase = 1, "draw"
    g.hands[1] = cards("5H 6H 9C")
    g.pile = cards("KD 3S")
    local ok, err = E.apply(g, 1, { type = "takePile" })
    check(not ok and err == "PileBlocked", "black three locks the pile")
    check(E.view(g, 1).pileLocked == true, "view reports locked pile")
    g.pile = cards("KD 2C")
    ok, err = E.apply(g, 1, { type = "takePile" })
    check(not ok and err == "PileTopWild", "wild locks the pile")
    g.pile = cards("3S 2C 9D")
    check(E.view(g, 1).pileLocked == false, "covered lock no longer reported")
    ok, err = E.apply(g, 1, { type = "takePile" })
    check(not ok and err == "PileNeedsMeld", "brazilian canasta: the pile needs the top card in a meld")
    g.hands[1] = cards("7D 8D 5H")
    ok, err = E.apply(g, 1, { type = "takePile", melds = { { cards = cards("7D 8D") } } })
    check(ok, "covered black three no longer locks: " .. tostring(err))
    check(#g.melds[1] == 1 and #g.melds[1][1].cards == 3 and C.indexOf(g.hands[1], c("3S")) ~= nil,
        "top card melded, rest of the pile to the hand")

    -- Red threes: 100 each, negative for a team without canasta; any canasta goes out.
    g = scenario("canastra_brasileira")
    g.turn, g.phase = 1, "play"
    for _, d in ipairs(g.dead) do d.state = "taken" end
    g.deadTakenBy = { true, true }
    g.melds = { { M.analyze(cards("5S 6S 7S 8S 9S 10S 2C"), br) }, {} }
    g.melds[1][1].id = 1
    g.hasMelded = { true, false }
    g.hands[1] = cards("KD")
    g.redThrees = { cards("3H 3D"), cards("3H/2") }
    ok, err = E.apply(g, 1, { type = "discard", card = c("KD") })
    check(ok and g.roundResult and g.roundResult.goOutTeam == 1, "go out with a dirty canasta: " .. tostring(err))
    check(g.roundResult.teams[1].red3 == 200, "red threes count 100 each with a canasta")
    check(g.roundResult.teams[2].red3 == -100, "red threes negative without a canasta")
end

do
    -- Bots extend existing melds with groups of cards instead of opening a parallel meld.
    local function botAddsTo(meldCards, handCards)
        local g = scenario("buraco_aberto", 4)
        g.turn, g.phase = 2, "play"
        local team = g.teamOf[2]
        local res = M.analyze(cards(meldCards), g.rules)
        res.id = 1
        g.melds[team] = { res }
        g.hasMelded[team] = true
        g.hands[2] = cards(handCards)
        local action = B.nextAction(g, 2)
        local ok = action and action.adds and E.apply(g, 2, action)
        return ok and g.melds[team][1], action
    end
    local m = botAddsTo("3S 2D 5S 6S", "AS 2S 3S/2 4S AH 9C KD 10H JH 7D QC")
    check(m and #m.cards == 7, "bot adds A, 2 and 4 together to complete the canasta")
    m = botAddsTo("AS 2S 3S 4S", "3S/2 2D 5S 6S AH 9C KD 10H JH 7D QC")
    check(m and #m.cards == 6 and m.wilds == 0, "bot adds 5 and 6 together without spending the wild")
    m = botAddsTo("7H 7S 7D", "7C 7H/2 9C KD 10H JH")
    check(m and #m.cards == 5, "bot adds several cards to a set at once")
end

-- ------------------------------------------------------------ full bot simulations
local function totalCards(g)
    local n = #g.stock + #g.pile
    for s = 1, g.n do n = n + #g.hands[s] end
    for t = 1, 2 do
        for _, m in ipairs(g.melds[t]) do n = n + #m.cards end
        n = n + #g.redThrees[t]
    end
    for _, d in ipairs(g.dead) do n = n + #d.cards end
    return n
end

local function simulate(preset, n, rounds)
    local g = E.newMatch(R.fromPreset(preset), n)
    local expected = g.rules.jokers and 108 or 104
    local roundsPlayed, goOuts, steps = 0, 0, 0
    E.startRound(g)
    while roundsPlayed < rounds do
        if g.phase == "roundOver" or g.phase == "matchOver" then
            roundsPlayed = roundsPlayed + 1
            if g.roundResult.goOutTeam > 0 then goOuts = goOuts + 1 end
            if g.phase == "matchOver" then
                g = E.newMatch(g.rules, n)
            end
            E.startRound(g)
        else
            local seat = g.turn
            local action = B.nextAction(g, seat)
            if not action then
                check(false, preset .. ": bot found no action in phase " .. g.phase)
                return
            end
            local ok, err = E.apply(g, seat, action)
            if not ok then
                check(false, preset .. ": bot action " .. action.type .. " rejected: " .. tostring(err))
                return
            end
            local tc = totalCards(g)
            if tc ~= expected then
                check(false, preset .. ": card count " .. tc .. " ~= " .. expected .. " after " .. action.type)
                return
            end
            steps = steps + 1
            if steps > 20000 * rounds then
                check(false, preset .. ": simulation did not finish")
                return
            end
        end
    end
    check(true, preset)
    print(string.format("  %-20s %dp: %d rounds, %d went out, %d actions", preset, n, roundsPlayed, goOuts, steps))
end

do
    -- The pile must not cycle back to the same bot (it used to grab any pile of 4+ cards,
    -- which in 4-player games is exactly when its turn comes back).
    local g = E.newMatch(R.fromPreset("buraco_aberto"), 4)
    E.startRound(g)
    local takes, repeats, last, played = 0, 0, nil, 0
    while played < 20 do
        if g.phase == "roundOver" or g.phase == "matchOver" then
            played = played + 1
            if g.phase == "matchOver" then g = E.newMatch(g.rules, 4) end
            E.startRound(g)
            last = nil
        else
            local seat = g.turn
            local action = B.nextAction(g, seat)
            if action.type == "takePile" then
                takes = takes + 1
                if last == seat then repeats = repeats + 1 end
                last = seat
            end
            E.apply(g, seat, action)
        end
    end
    check(takes > 0 and repeats / takes < 0.35,
        string.format("pile takes spread across seats (%d of %d by the previous taker)", repeats, takes))
end

print("Simulations:")
for _, preset in ipairs(R.PRESET_ORDER) do
    simulate(preset, 2, 25)
    simulate(preset, 4, 25)
end

print(string.format("\n%d passed, %d failed", passes, failures))
return failures
