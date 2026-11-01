Canastra = Canastra or {}

local C = {}
Canastra.Cards = C

-- Card ids are integers: copy * 1000 + suit * 100 + rank.
-- Suits: 1 spades, 2 hearts, 3 clubs, 4 diamonds, 9 joker. Ranks: 1 (ace) .. 13 (king).
C.SPADES = 1
C.HEARTS = 2
C.CLUBS = 3
C.DIAMONDS = 4
C.JOKER = 9

function C.make(copy, suit, rank)
    return copy * 1000 + suit * 100 + rank
end

function C.suit(id)
    return math.floor(id / 100) % 10
end

function C.rank(id)
    if C.suit(id) == C.JOKER then return 0 end
    return id % 100
end

function C.isJoker(id)
    return C.suit(id) == C.JOKER
end

function C.isRed(id)
    local s = C.suit(id)
    return s == C.HEARTS or s == C.DIAMONDS
end

function C.isRedThree(id)
    return C.rank(id) == 3 and C.isRed(id)
end

function C.isBlackThree(id)
    return C.rank(id) == 3 and not C.isRed(id) and not C.isJoker(id)
end

function C.random(n)
    if ZombRand then
        return ZombRand(n) + 1
    end
    return math.random(n)
end

function C.newShoe(decks, jokers)
    local t = {}
    for copy = 1, decks do
        for suit = 1, 4 do
            for rank = 1, 13 do
                t[#t + 1] = C.make(copy, suit, rank)
            end
        end
        if jokers then
            t[#t + 1] = C.make(copy, C.JOKER, 1)
            t[#t + 1] = C.make(copy, C.JOKER, 2)
        end
    end
    return t
end

function C.shuffle(t)
    for i = #t, 2, -1 do
        local j = C.random(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

C.RANK_LABELS = { "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K" }

function C.rankLabel(id)
    if C.isJoker(id) then return "JK" end
    return C.RANK_LABELS[C.rank(id)]
end

-- Value tables used for scoring; "buraco" and "canasta" are the two traditions.
local VALUES = {
    buraco = { joker = 20, ace = 15, two = 10, low = 5, high = 10, blackThree = 5 },
    canasta = { joker = 50, ace = 20, two = 20, low = 5, high = 10, blackThree = 5 },
}

function C.value(id, rules)
    local v = VALUES[rules and rules.cardValues or "buraco"] or VALUES.buraco
    if C.isJoker(id) then return v.joker end
    local r = C.rank(id)
    if r == 1 then return v.ace end
    if r == 2 then return v.two end
    if r == 3 then
        if rules and rules.redThrees then
            if C.isRed(id) then return 0 end
            return v.blackThree
        end
        return v.low
    end
    if r >= 8 then return v.high end
    return v.low
end

function C.copyList(t)
    local r = {}
    if t then
        for i = 1, #t do r[i] = t[i] end
    end
    return r
end

function C.indexOf(t, id)
    for i = 1, #t do
        if t[i] == id then return i end
    end
    return nil
end

function C.removeIds(list, ids)
    local drop = {}
    for _, id in ipairs(ids) do drop[id] = true end
    local r = {}
    for _, id in ipairs(list) do
        if not drop[id] then r[#r + 1] = id end
    end
    return r
end

local function sortKeySuit(id)
    local s = C.suit(id)
    if s == C.JOKER then return 9000 + id % 100 end
    return s * 100 + C.rank(id)
end

local function sortKeyRank(id)
    if C.isJoker(id) then return 9000 + id % 100 end
    local r = C.rank(id)
    if r == 1 then r = 14 end
    return r * 10 + C.suit(id)
end

function C.sortBySuit(t)
    table.sort(t, function(a, b)
        local ka, kb = sortKeySuit(a), sortKeySuit(b)
        if ka == kb then return a < b end
        return ka < kb
    end)
    return t
end

function C.sortByRank(t)
    table.sort(t, function(a, b)
        local ka, kb = sortKeyRank(a), sortKeyRank(b)
        if ka == kb then return a < b end
        return ka < kb
    end)
    return t
end

return C
