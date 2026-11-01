require "Canastra/CanastraEngine"

local C = Canastra.Cards
local M = Canastra.Melds
local E = Canastra.Engine

local B = {}
Canastra.Bot = B

B.NAMES = { "Ana", "Beto", "Caio", "Duda", "Edu", "Fabi", "Gil", "Helena" }

-- Candidate melds (lists of card ids) that can be formed from a set of cards.
function B.candidateMelds(cards, rules, allowWild)
    local res = {}
    local wilds, bySuit, byRank = {}, {}, {}
    for _, id in ipairs(cards) do
        if M.isWild(id, rules) then
            wilds[#wilds + 1] = id
        else
            local s, r = C.suit(id), C.rank(id)
            bySuit[s] = bySuit[s] or {}
            table.insert(bySuit[s], id)
            byRank[r] = byRank[r] or {}
            table.insert(byRank[r], id)
        end
    end

    if rules.meldSets then
        for r, ids in pairs(byRank) do
            local skip = (rules.redThrees and r == 3) or not M.setRankAllowed(r, rules)
            if not skip then
                if #ids >= 3 then
                    res[#res + 1] = C.copyList(ids)
                elseif #ids == 2 and allowWild and #wilds > 0 then
                    res[#res + 1] = { ids[1], ids[2], wilds[1] }
                end
            end
        end
    end

    if rules.meldSequences then
        for _, ids in pairs(bySuit) do
            local byR = {}
            for _, id in ipairs(ids) do
                local r = C.rank(id)
                if not byR[r] then byR[r] = id end
                if r == 1 and not byR[14] then byR[14] = id end
            end
            -- natural runs
            local r = 1
            while r <= 14 do
                if byR[r] then
                    local run = {}
                    local seen = {}
                    local k = r
                    while k <= 14 and byR[k] and not seen[byR[k]] do
                        seen[byR[k]] = true
                        run[#run + 1] = byR[k]
                        k = k + 1
                    end
                    if #run >= 3 then res[#res + 1] = run end
                    r = k
                else
                    r = r + 1
                end
            end
            -- runs bridging a single gap with a wild
            if allowWild and #wilds > 0 then
                for start = 1, 12 do
                    local cardsRun, missing, seen = {}, 0, {}
                    for k = start, math.min(14, start + 3) do
                        local id = byR[k]
                        if id and not seen[id] then
                            seen[id] = true
                            cardsRun[#cardsRun + 1] = id
                        else
                            missing = missing + 1
                        end
                    end
                    if missing == 1 and #cardsRun >= 2 then
                        cardsRun[#cardsRun + 1] = wilds[1]
                        res[#res + 1] = cardsRun
                    end
                end
                for start = 1, 13 do
                    local a, b = byR[start], byR[start + 1]
                    if a and b and a ~= b then
                        res[#res + 1] = { a, b, wilds[1] }
                    end
                end
            end
        end
    end
    return res
end

local function contains(list, id)
    return C.indexOf(list, id) ~= nil
end

local function meldScore(res)
    local s = #res.cards * 10
    if res.clean then s = s + 15 end
    return s
end

-- --------------------------------------------------------------- draw phase

local function topMeldSpec(g, seat, top)
    local rules = g.rules
    local team = g.teamOf[seat]
    local hand = g.hands[seat]
    for _, m in ipairs(g.melds[team]) do
        local action = { type = "takePile", addTo = m.id, cards = {} }
        if E.check(g, seat, action) then return action end
    end
    local pool = C.copyList(hand)
    pool[#pool + 1] = top
    local best, bestScore
    for _, allowWild in ipairs({ false, true }) do
        for _, cand in ipairs(B.candidateMelds(pool, rules, allowWild)) do
            if contains(cand, top) then
                local handPart = C.removeIds(cand, { top })
                local action = { type = "takePile", melds = { { cards = handPart } } }
                if E.check(g, seat, action) then
                    local res = M.analyze(cand, rules)
                    local sc = res and meldScore(res) or 0
                    if not best or sc > bestScore then best, bestScore = action, sc end
                end
            end
        end
        if best then return best end
    end
    -- Initial-meld minimums may require extra melds alongside the top-card meld.
    if E.initialMin(g, team) > 0 then
        for _, cand in ipairs(B.candidateMelds(pool, rules, true)) do
            if contains(cand, top) then
                local handPart = C.removeIds(cand, { top })
                local action = { type = "takePile", melds = { { cards = handPart } } }
                local rest = C.removeIds(hand, handPart)
                for _, extra in ipairs(B.candidateMelds(rest, rules, false)) do
                    action.melds[#action.melds + 1] = { cards = extra }
                    rest = C.removeIds(rest, extra)
                    if E.check(g, seat, action) then return action end
                end
            end
        end
    end
    return nil
end

local function cardIsUseful(g, seat, id)
    local rules = g.rules
    local team = g.teamOf[seat]
    for _, m in ipairs(g.melds[team]) do
        local cards = C.copyList(m.cards)
        cards[#cards + 1] = id
        if M.analyze(cards, rules, m.kind) then return true end
    end
    local pool = C.copyList(g.hands[seat])
    pool[#pool + 1] = id
    for _, cand in ipairs(B.candidateMelds(pool, rules, false)) do
        if contains(cand, id) then return true end
    end
    return false
end

-- How many pile cards the seat could actually use: wilds, cards extending the team's melds,
-- and cards forming new melds together with the hand.
local function pileUsefulCount(g, seat)
    local rules = g.rules
    local team = g.teamOf[seat]
    local useful = {}
    for _, id in ipairs(g.pile) do
        if M.isWild(id, rules) then
            useful[id] = true
        else
            for _, m in ipairs(g.melds[team]) do
                local cards = C.copyList(m.cards)
                cards[#cards + 1] = id
                if M.analyze(cards, rules, m.kind) then useful[id] = true break end
            end
        end
    end
    local pool = C.copyList(g.hands[seat])
    for _, id in ipairs(g.pile) do pool[#pool + 1] = id end
    for _, cand in ipairs(B.candidateMelds(pool, rules, false)) do
        for _, id in ipairs(cand) do
            if contains(g.pile, id) then useful[id] = true end
        end
    end
    local count = 0
    for _ in pairs(useful) do count = count + 1 end
    return count
end

function B.drawAction(g, seat)
    local rules = g.rules
    local n = #g.pile
    if n > 0 then
        local top = g.pile[n]
        if rules.pileTake == "free" and not rules.pileFreeze then
            if cardIsUseful(g, seat, top) and (#g.hands[seat] >= 3 or pileUsefulCount(g, seat) >= 2) then
                local action = { type = "takePile" }
                if E.check(g, seat, action) then return action end
            end
        else
            local action = topMeldSpec(g, seat, top)
            if action then return action end
        end
    end
    return { type = "draw" }
end

-- --------------------------------------------------------------- play phase

local MAX_POOL = 8

-- Calls fn(subset) for every k-sized subset of list until fn returns a value.
local function eachCombo(list, k, fn)
    local picked = {}
    local function rec(start, depth)
        if depth > k then return fn(C.copyList(picked)) end
        for i = start, #list - (k - depth) do
            picked[depth] = list[i]
            local r = rec(i + 1, depth + 1)
            if r then return r end
        end
        return nil
    end
    return rec(1, 1)
end

-- Hand cards that could naturally extend a meld (same suit for runs, same rank for sets).
local function extensionPool(g, seat, m)
    local rules = g.rules
    local pool = {}
    for _, id in ipairs(g.hands[seat]) do
        local fits
        if C.isJoker(id) then
            fits = false
        elseif m.kind == "seq" then
            local naturalTwo = rules.twosWild and rules.naturalTwo and C.rank(id) == 2
            fits = C.suit(id) == m.suit and (naturalTwo or not M.isWild(id, rules))
        else
            fits = not M.isWild(id, rules) and C.rank(id) == m.rank
        end
        if fits and #pool < MAX_POOL then pool[#pool + 1] = id end
    end
    return pool
end

-- Largest group of hand cards that extends one of the team's melds without spending a new wild.
local function findExtension(g, seat)
    local rules = g.rules
    local team = g.teamOf[seat]
    for _, m in ipairs(g.melds[team]) do
        local pool = extensionPool(g, seat, m)
        for k = #pool, 1, -1 do
            local action = eachCombo(pool, k, function(subset)
                local cards = C.copyList(m.cards)
                for _, id in ipairs(subset) do cards[#cards + 1] = id end
                local res = M.analyze(cards, rules, m.kind)
                if res and res.wilds <= (m.wilds or 0) then
                    local a = { type = "meld", adds = { { meld = m.id, cards = subset } } }
                    if E.check(g, seat, a) then return a end
                end
                return nil
            end)
            if action then return action end
        end
    end
    return nil
end

local function findAdd(g, seat, allowWild)
    local rules = g.rules
    local team = g.teamOf[seat]
    local hand = g.hands[seat]
    for _, id in ipairs(hand) do
        local wild = M.isWild(id, rules)
        if not wild or allowWild then
            for _, m in ipairs(g.melds[team]) do
                -- Wilds are only spent to complete a canasta or to empty a small hand.
                local worth = not wild or #m.cards + 1 >= Canastra.Rules.CANASTA_SIZE or #hand <= 3
                if worth then
                    local cards = C.copyList(m.cards)
                    cards[#cards + 1] = id
                    if M.analyze(cards, rules, m.kind) then
                        local action = { type = "meld", adds = { { meld = m.id, cards = { id } } } }
                        if E.check(g, seat, action) then return action end
                    end
                end
            end
        end
    end
    return nil
end

local function findNewMeld(g, seat)
    local rules = g.rules
    local hand = g.hands[seat]
    local team = g.teamOf[seat]
    local min = E.initialMin(g, team)
    local useWild = #hand <= 8 or g.hasMelded[team]
    for _, allowWild in ipairs({ false, useWild }) do
        local cands = B.candidateMelds(hand, rules, allowWild)
        local scored = {}
        for _, cand in ipairs(cands) do
            local res = M.analyze(cand, rules)
            if res then scored[#scored + 1] = { cards = cand, score = meldScore(res), pts = M.points(cand, rules) } end
        end
        table.sort(scored, function(a, b) return a.score > b.score end)
        if min > 0 then
            local action = { type = "meld", melds = {} }
            local usedSet = {}
            for _, s in ipairs(scored) do
                local overlap = false
                for _, id in ipairs(s.cards) do
                    if usedSet[id] then overlap = true end
                end
                if not overlap then
                    action.melds[#action.melds + 1] = { cards = s.cards }
                    for _, id in ipairs(s.cards) do usedSet[id] = true end
                    if E.check(g, seat, action) then return action end
                end
            end
        else
            for _, s in ipairs(scored) do
                local action = { type = "meld", melds = { { cards = s.cards } } }
                if E.check(g, seat, action) then return action end
            end
        end
    end
    return nil
end

local function opponentCanUse(g, seat, id)
    local rules = g.rules
    local other = g.teamOf[seat] == 1 and 2 or 1
    for _, m in ipairs(g.melds[other]) do
        local cards = C.copyList(m.cards)
        cards[#cards + 1] = id
        if M.analyze(cards, rules, m.kind) then return true end
    end
    return false
end

function B.discardAction(g, seat)
    local rules = g.rules
    local hand = g.hands[seat]
    local scored = {}
    for _, id in ipairs(hand) do
        local keep = 0
        if M.isWild(id, rules) then
            keep = keep + 1000
        else
            local s, r = C.suit(id), C.rank(id)
            for _, other in ipairs(hand) do
                if other ~= id and not M.isWild(other, rules) then
                    local os, orank = C.suit(other), C.rank(other)
                    if rules.meldSets and orank == r then keep = keep + 25 end
                    if rules.meldSequences and os == s then
                        local d = math.abs(orank - r)
                        if r == 1 or orank == 1 then
                            d = math.min(d, math.abs((orank == 1 and 14 or orank) - (r == 1 and 14 or r)))
                        end
                        if d == 1 then keep = keep + 20 elseif d == 2 then keep = keep + 10 end
                    end
                end
            end
            if opponentCanUse(g, seat, id) then keep = keep + 60 end
            if rules.redThrees and C.isBlackThree(id) then
                keep = keep - (rules.redThrees == "canasta" and 200 or 50)
            end
            keep = keep - C.value(id, rules) * 0.5
        end
        scored[#scored + 1] = { id = id, keep = keep }
    end
    table.sort(scored, function(a, b) return a.keep < b.keep end)
    for _, s in ipairs(scored) do
        local action = { type = "discard", card = s.id }
        if E.check(g, seat, action) then return action end
    end
    return nil
end

function B.nextAction(g, seat)
    if g.phase == "draw" then
        return B.drawAction(g, seat)
    elseif g.phase == "play" then
        if g.redrawCard and not cardIsUseful(g, seat, g.redrawCard) and not M.isWild(g.redrawCard, g.rules) then
            local action = { type = "redraw" }
            if E.check(g, seat, action) then return action end
        end
        return findExtension(g, seat)
            or findAdd(g, seat, false)
            or findNewMeld(g, seat)
            or findAdd(g, seat, true)
            or B.discardAction(g, seat)
    end
    return nil
end

return B
