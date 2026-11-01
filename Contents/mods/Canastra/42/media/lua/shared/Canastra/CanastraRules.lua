Canastra = Canastra or {}

local R = {}
Canastra.Rules = R

-- Every configurable rule, with its allowed values. The first value is the default.
-- Labels are translated on the client through IGUI_Canastra_Rule_<key> / IGUI_Canastra_Val_<key>_<value>.
R.SCHEMA = {
    { key = "pileTake",          values = { "free", "topMeld" } },
    { key = "pileVisible",       values = { true, false } },
    { key = "meldSequences",     values = { true, false } },
    { key = "meldSets",          values = { true, false } },
    { key = "setRanks",          values = { "all", "A4K" } },
    { key = "twosWild",          values = { true, false } },
    { key = "jokers",            values = { false, true } },
    { key = "wildRule",          values = { "one", "canasta" } },
    { key = "handSize",          values = { 11, 9, 13, 15, 0 } },
    { key = "drawCount",         values = { 1, 2 } },
    { key = "deadPiles",         values = { 2, 1, 0 } },
    { key = "deadSize",          values = { 11, 9, 13 } },
    { key = "goOutRequires",     values = { "clean", "any", "none" } },
    { key = "goOutNeedsDiscard", values = { false, true } },
    { key = "openCard",          values = { false, true } },
    { key = "pileFreeze",        values = { false, true } },
    { key = "pileLock",          values = { false, true } },
    { key = "redThrees",         values = { false, "classic", "canasta" } },
    { key = "minInitialMeld",    values = { 0, 50, 75, 100, -1 } },
    { key = "cardValues",        values = { "buraco", "canasta" } },
    { key = "bonusClean",        values = { 200, 100, 300, 500 } },
    { key = "bonusDirty",        values = { 100, 50, 200, 300 } },
    { key = "bonusGoOut",        values = { 100, 0, 50, 200 } },
    { key = "penaltyNoDead",     values = { 100, 0, 50, 200 } },
    { key = "targetScore",       values = { 3000, 1000, 1500, 2000, 5000 } },
}

R.CANASTA_SIZE = 7

local function defaults()
    local d = {}
    for _, opt in ipairs(R.SCHEMA) do
        d[opt.key] = opt.values[1]
    end
    return d
end

R.PRESET_ORDER = {
    "buraco_aberto", "buraco_fechado", "stbl", "buraco_1morto",
    "buraco_semmorto", "buraco_coringa", "canastra_classica", "canastra_brasileira", "custom",
}

R.PRESETS = {
    buraco_aberto = {},
    buraco_fechado = { pileTake = "topMeld", pileVisible = false },
    stbl = { meldSets = false, goOutRequires = "clean" },
    buraco_1morto = { deadPiles = 1 },
    buraco_semmorto = { deadPiles = 0 },
    buraco_coringa = { jokers = true },
    canastra_classica = {
        jokers = true, meldSequences = false, meldSets = true, wildRule = "canasta",
        handSize = 0, drawCount = 2, deadPiles = 0, goOutRequires = "any",
        pileTake = "topMeld", pileVisible = true, pileFreeze = true, pileLock = true,
        redThrees = "classic", openCard = true, minInitialMeld = -1, cardValues = "canasta",
        bonusClean = 500, bonusDirty = 300, bonusGoOut = 100, penaltyNoDead = 0,
        targetScore = 5000,
    },
    canastra_brasileira = {
        setRanks = "A4K", pileTake = "topMeld", pileLock = true, redThrees = "canasta", goOutRequires = "any",
    },
    custom = {},
}

function R.fromPreset(name)
    local r = defaults()
    local p = R.PRESETS[name] or R.PRESETS.buraco_aberto
    for k, v in pairs(p) do r[k] = v end
    r.preset = R.PRESETS[name] and name or "buraco_aberto"
    return r
end

function R.optionFor(key)
    for _, opt in ipairs(R.SCHEMA) do
        if opt.key == key then return opt end
    end
    return nil
end

local function allowed(opt, v)
    for _, a in ipairs(opt.values) do
        if a == v then return true end
    end
    return false
end

-- Returns a clean copy containing only known keys with allowed values.
function R.sanitize(rules)
    local out = defaults()
    if type(rules) == "table" then
        for _, opt in ipairs(R.SCHEMA) do
            local v = rules[opt.key]
            if type(opt.values[1]) == "number" and type(v) == "string" then v = tonumber(v) end
            if opt.key == "redThrees" and v == true then v = "classic" end
            if v ~= nil and allowed(opt, v) then out[opt.key] = v end
        end
        if type(rules.preset) == "string" and R.PRESETS[rules.preset] then
            out.preset = rules.preset
        end
    end
    out.preset = out.preset or "custom"
    if not out.meldSequences and not out.meldSets then
        out.meldSequences = true
    end
    return out
end

function R.cycle(rules, key, dir)
    local opt = R.optionFor(key)
    if not opt then return end
    local idx = 1
    for i, v in ipairs(opt.values) do
        if v == rules[key] then idx = i end
    end
    idx = idx + (dir or 1)
    if idx > #opt.values then idx = 1 end
    if idx < 1 then idx = #opt.values end
    rules[key] = opt.values[idx]
    rules.preset = "custom"
end

function R.handSize(rules, numPlayers)
    if rules.handSize == 0 then
        return numPlayers == 2 and 15 or 11
    end
    return rules.handSize
end

return R
