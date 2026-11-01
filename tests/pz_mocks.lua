-- Minimal stand-ins for the Project Zomboid Lua API used by the mod (singleplayer mode).
-- Every draw call validates its arguments so render bugs surface as test failures.

MOCK_ERRORS = {}
MISSING_TEXT = {}
local function fail(msg)
    if #MOCK_ERRORS < 50 then MOCK_ERRORS[#MOCK_ERRORS + 1] = msg .. "\n" .. debug.traceback("", 2) end
end

for _, m in ipairs({ "ISUI/ISCollapsableWindow", "ISUI/ISButton", "ISUI/ISPanel" }) do
    MOCK_MODULES[m] = true
end

-- ------------------------------------------------------------------ clock / env
MOCK_NOW = 1000000
function getTimestampMs() return MOCK_NOW end
function isClient() return false end
function isServer() return false end
function ZombRand(n) return math.random(n) - 1 end
function instanceof(o, cls) return type(o) == "table" and o.__class == cls end

UIFont = { Small = "Small", Medium = "Medium", Large = "Large" }
CharacterStat = { BOREDOM = "BOREDOM", UNHAPPINESS = "UNHAPPINESS", STRESS = "STRESS" }
SandboxVars = {
    Canastra = {
        RequiredDecks = 2, MaxDistance = 8, AllowBots = true, BotDelay = 1.0,
        BoredomPerMinute = 0.3, UnhappinessPerMinute = 0.1, StressPerMinute = 0.002, WinUnhappinessBonus = 10,
    },
}

local handlers = {}
Events = setmetatable({}, {
    __index = function(t, name)
        local e = { Add = function(f)
            handlers[name] = handlers[name] or {}
            table.insert(handlers[name], f)
        end }
        rawset(t, name, e)
        return e
    end,
})
function triggerEvent(name, ...)
    for _, f in ipairs(handlers[name] or {}) do f(...) end
end

-- ------------------------------------------------------------------ text / textures
local function isNum(v) return type(v) == "number" and v == v end

function getText(key, ...)
    if type(key) ~= "string" then fail("getText with non-string key") return "?" end
    local s = TRANSLATIONS[key]
    if not s then
        MISSING_TEXT[key] = true
        return key
    end
    local args = { ... }
    for i = 1, select("#", ...) do
        if type(args[i]) ~= "string" and type(args[i]) ~= "number" then fail("getText arg " .. i .. " for " .. key .. " is " .. type(args[i])) end
        s = s:gsub("%%" .. i, tostring(args[i]))
    end
    return s
end

local textManager = {
    getFontHeight = function(self, font) return font == UIFont.Medium and 20 or 16 end,
    MeasureStringX = function(self, font, text)
        if type(text) ~= "string" then fail("MeasureStringX with " .. type(text)) return 0 end
        return #text * 7
    end,
    MeasureStringY = function(self, font, text) return 16 end,
}
function getTextOrNull(key)
    if TRANSLATIONS[key] then return getText(key) end
    return nil
end

function getTextManager() return textManager end

function getTexture(path)
    local f = io.open(MEDIA_DIR .. "/" .. path:gsub("^media/", ""), "rb")
    if not f then
        fail("missing texture " .. path)
        return nil
    end
    f:close()
    return { path = path }
end

function getCore()
    return { getScreenWidth = function() return 1920 end, getScreenHeight = function() return 1080 end }
end
function getSoundManager() return { playUISound = function() end } end

-- ------------------------------------------------------------------ player
local stats = { BOREDOM = 50, UNHAPPINESS = 50, STRESS = 0.5 }
MOCK_STATS = stats
local inventory = {
    getCountTypeRecurse = function(self, t) return t == "Base.CardDeck" and MOCK_DECKS or 0 end,
}
MOCK_DECKS = 2
MOCK_PLAYER = {
    getUsername = function() return "tester" end,
    getPlayerNum = function() return 0 end,
    getX = function() return 100.5 end, getY = function() return 200.5 end, getZ = function() return 0 end,
    getInventory = function() return inventory end,
    getDescriptor = function()
        return { getForename = function() return "Kate" end, getSurname = function() return "Smith" end }
    end,
    getStats = function()
        return { remove = function(self, stat, v)
            if not isNum(v) then fail("stats:remove non-number") end
            stats[stat] = math.max(0, stats[stat] - v)
        end }
    end,
}
function getPlayer() return MOCK_PLAYER end
function getSpecificPlayer(i) return i == 0 and MOCK_PLAYER or nil end
function getNumActivePlayers() return 1 end

-- ------------------------------------------------------------------ UI base class
local Base = {}
Base.__index = Base

function Base:derive(name)
    local cls = {}
    cls.__index = cls
    cls.Type = name
    setmetatable(cls, { __index = self })
    return cls
end

function Base:new(x, y, w, h)
    local o = { x = x, y = y, width = w, height = h, visible = true, mouseX = -1, mouseY = -1, mouseOver = false }
    setmetatable(o, self)
    return o
end

function Base:initialise() end
function Base:addToUIManager() self.inUI = true end
function Base:removeFromUIManager() self.inUI = false end
function Base:setVisible(v) self.visible = v end
function Base:bringToTop() end
function Base:setX(x) if not isNum(x) then fail("setX") end self.x = x end
function Base:setY(y) if not isNum(y) then fail("setY") end self.y = y end
function Base:setHeight(h) if not isNum(h) then fail("setHeight") end self.height = h end
function Base:close() self.visible = false end
function Base:render() end
function Base:onMouseDown(x, y) return false end
function Base:titleBarHeight() return 20 end
function Base:isMouseOver() return self.mouseOver end
function Base:getMouseX() return self.mouseX end
function Base:getMouseY() return self.mouseY end

local function checkNums(name, ...)
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if not isNum(v) then fail(name .. " arg " .. i .. " is " .. tostring(v)) return end
    end
end

MOCK_TEXT_DRAWN = {}
local function textCall(name)
    return function(self, str, x, y, r, g, b, a, font)
        if type(str) ~= "string" then fail(name .. " with " .. type(str)) end
        checkNums(name, x, y, r, g, b, a)
        MOCK_TEXT_DRAWN[#MOCK_TEXT_DRAWN + 1] = str
    end
end
Base.drawText = textCall("drawText")
Base.drawTextCentre = textCall("drawTextCentre")
Base.drawTextRight = textCall("drawTextRight")
function Base:drawRect(x, y, w, h, a, r, g, b) checkNums("drawRect", x, y, w, h, a, r, g, b) end
function Base:drawRectBorder(x, y, w, h, a, r, g, b) checkNums("drawRectBorder", x, y, w, h, a, r, g, b) end
function Base:drawTextureScaled(tex, x, y, w, h, a, r, g, b)
    if type(tex) ~= "table" then fail("drawTextureScaled with nil texture") end
    checkNums("drawTextureScaled", x, y, w, h, a, r, g, b)
end

MOCK_FILES = {}

function getFileWriter(name, create, append)
    local buf = append and (MOCK_FILES[name] or "") or ""
    return {
        write = function(self, s) buf = buf .. s end,
        close = function(self) MOCK_FILES[name] = buf end,
    }
end

function getFileReader(name, create)
    local content = MOCK_FILES[name]
    if not content then return nil end
    local lines = {}
    for line in content:gmatch("[^\n]+") do lines[#lines + 1] = line end
    local i = 0
    return {
        readLine = function(self) i = i + 1 return lines[i] end,
        close = function(self) end,
    }
end

ISCollapsableWindow = Base:derive("ISCollapsableWindow")
function ISCollapsableWindow.TitleBarHeight() return 20 end
ISCollapsableWindow.new = Base.new

-- ------------------------------------------------------------------ context menu
ISInventoryPaneContextMenu = { addToolTip = function() return {} end }
function newMockContext()
    local ctx = { options = {} }
    function ctx:addOption(name, target, fn)
        if type(name) ~= "string" then fail("context option name") end
        local o = { name = name, target = target, onSelect = fn }
        table.insert(self.options, o)
        return o
    end
    return ctx
end
