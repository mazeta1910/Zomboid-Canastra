require "Canastra/CanastraCards"
require "Canastra/CanastraRules"

local C = Canastra.Cards
local M = {}
Canastra.Melds = M

function M.isWild(id, rules)
    if C.isJoker(id) then return true end
    return rules.twosWild and C.rank(id) == 2
end

local function wildsAllowed(naturals, wilds, rules)
    if naturals < 2 then return false end
    if wilds == 0 then return true end
    if rules.wildRule == "canasta" then return wilds <= 3 end
    return wilds <= 1
end

local SET_RANKS = { A4K = { [1] = true, [4] = true, [13] = true } }

function M.setRankAllowed(rank, rules)
    local only = SET_RANKS[rules.setRanks]
    return not only or only[rank] == true
end

function M.analyzeSet(cards, rules)
    if not rules.meldSets or #cards < 3 then return nil end
    local rank
    local naturals, wilds = {}, {}
    for _, id in ipairs(cards) do
        if M.isWild(id, rules) then
            wilds[#wilds + 1] = id
        else
            local r = C.rank(id)
            if rank and r ~= rank then return nil end
            rank = r
            naturals[#naturals + 1] = id
        end
    end
    if not rank or not M.setRankAllowed(rank, rules) then return nil end
    if rules.redThrees and rank == 3 then
        if rules.redThrees == "canasta" or #wilds > 0 then return nil end
        for _, id in ipairs(naturals) do
            if C.isRed(id) then return nil end
        end
    end
    if not wildsAllowed(#naturals, #wilds, rules) then return nil end
    table.sort(naturals, function(a, b)
        if C.suit(a) == C.suit(b) then return a < b end
        return C.suit(a) < C.suit(b)
    end)
    local ordered = C.copyList(naturals)
    for _, id in ipairs(wilds) do ordered[#ordered + 1] = id end
    return { kind = "set", rank = rank, cards = ordered, wilds = #wilds, clean = #wilds == 0 }
end

-- Lays out naturals (with fixed ranks) and wild cards as a run. Returns nil if impossible.
local function layoutRun(entries, wildList, suit, rules)
    local n = #entries
    local w = #wildList
    if not wildsAllowed(n, w, rules) then return nil end
    if n + w > 14 then return nil end
    table.sort(entries, function(a, b) return a.r < b.r end)
    for i = 2, n do
        if entries[i].r == entries[i - 1].r then return nil end
    end
    local lo, hi = entries[1].r, entries[n].r
    local gaps = (hi - lo + 1) - n
    if gaps > w then return nil end
    local extras = w - gaps
    local slots = {}
    for _, e in ipairs(entries) do slots[e.r] = e.id end
    local wi = 1
    for r = lo, hi do
        if not slots[r] then
            slots[r] = wildList[wi]
            wi = wi + 1
        end
    end
    while extras > 0 do
        if hi < 14 then
            hi = hi + 1
            slots[hi] = wildList[wi]
        else
            lo = lo - 1
            slots[lo] = wildList[wi]
        end
        wi = wi + 1
        extras = extras - 1
    end
    if lo < 1 then return nil end
    local ordered = {}
    for r = lo, hi do ordered[#ordered + 1] = slots[r] end
    return { kind = "seq", suit = suit, lo = lo, hi = hi, cards = ordered, wilds = w, clean = w == 0, gaps = gaps }
end

local function tryRun(naturals, wildList, suit, rules)
    local aces, others = {}, {}
    for _, id in ipairs(naturals) do
        if C.rank(id) == 1 then aces[#aces + 1] = id else others[#others + 1] = { id = id, r = C.rank(id) } end
    end
    if #aces > 2 then return nil end
    local options = {}
    if #aces == 0 then
        options[1] = {}
    elseif #aces == 1 then
        options[1] = { { id = aces[1], r = 1 } }
        options[2] = { { id = aces[1], r = 14 } }
    else
        options[1] = { { id = aces[1], r = 1 }, { id = aces[2], r = 14 } }
    end
    local best
    for _, aceEntries in ipairs(options) do
        local entries = {}
        for _, e in ipairs(others) do entries[#entries + 1] = { id = e.id, r = e.r } end
        for _, e in ipairs(aceEntries) do entries[#entries + 1] = { id = e.id, r = e.r } end
        local res = layoutRun(entries, wildList, suit, rules)
        if res and (not best or res.gaps < best.gaps) then best = res end
    end
    return best
end

function M.analyzeSeq(cards, rules)
    if not rules.meldSequences then return nil end
    local n = #cards
    if n < 3 or n > 14 then return nil end
    local suit
    local fixed, twos, jokers = {}, {}, {}
    for _, id in ipairs(cards) do
        if C.isJoker(id) then
            jokers[#jokers + 1] = id
        elseif rules.twosWild and C.rank(id) == 2 then
            twos[#twos + 1] = id
        else
            local s = C.suit(id)
            if suit and s ~= suit then return nil end
            suit = s
            fixed[#fixed + 1] = id
        end
    end
    if not suit then return nil end
    if rules.redThrees then
        for _, id in ipairs(fixed) do
            if C.isRedThree(id) then return nil end
            if rules.redThrees == "canasta" and C.isBlackThree(id) then return nil end
        end
    end

    local best
    -- A two of the run's own suit may stand in its natural place instead of acting as a wild.
    local naturalTwo
    if rules.naturalTwo then
        for i, id in ipairs(twos) do
            if C.suit(id) == suit then naturalTwo = i break end
        end
    end
    for opt = 0, 1 do
        if opt == 0 or naturalTwo then
            local naturals = C.copyList(fixed)
            local wildList = C.copyList(jokers)
            for i, id in ipairs(twos) do
                if opt == 1 and i == naturalTwo then
                    naturals[#naturals + 1] = id
                else
                    wildList[#wildList + 1] = id
                end
            end
            local res = tryRun(naturals, wildList, suit, rules)
            if res and (not best or res.wilds < best.wilds) then best = res end
        end
    end
    return best
end

-- kind: "seq", "set" or nil (auto-detect).
function M.analyze(cards, rules, kind)
    if kind == "seq" then return M.analyzeSeq(cards, rules) end
    if kind == "set" then return M.analyzeSet(cards, rules) end
    return M.analyzeSeq(cards, rules) or M.analyzeSet(cards, rules)
end

function M.points(cards, rules)
    local p = 0
    for _, id in ipairs(cards) do p = p + C.value(id, rules) end
    return p
end

function M.isCanasta(meld)
    return #meld.cards >= Canastra.Rules.CANASTA_SIZE
end

return M
