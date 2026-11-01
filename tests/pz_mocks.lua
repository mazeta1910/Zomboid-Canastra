-- Minimal stand-ins for the Project Zomboid Lua API used by the mod (singleplayer mode).
-- Every draw call validates its arguments so render bugs surface as test failures.

MOCK_ERRORS = {}
MISSING_TEXT = {}
local function fail(msg)
    if #MOCK_ERRORS < 50 then MOCK_ERRORS[#MOCK_ERRORS + 1] = msg .. "\n" .. debug.traceback("", 2) end
end

for _, m in ipairs({ "ISUI/ISCollapsableWindow", "ISUI/ISButton", "ISUI/ISPanel", "ISUI/ISUI3DModel" }) do
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
        RequiredDecks = 2, MaxDistance = 8, RequireSeat = true, SeatReturnTime = 120, AllowBots = true, BotDelay = 1.0,
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

-- ------------------------------------------------------------------ world: chairs and tables
-- MOCK_GRID["x,y,z"] = list of sprite names on that square.
MOCK_GRID = {}
local function mockList(items)
    return { size = function() return #items end, get = function(_, i) return items[i + 1] end }
end
local function mockSquare(x, y, z)
    local names = MOCK_GRID[x .. "," .. y .. "," .. z]
    if not names then return nil end
    local objects = {}
    local sq = { getX = function() return x end, getY = function() return y end, getZ = function() return z end }
    for _, name in ipairs(names) do
        local props = {
            has = function(_, k) return k == "IsTable" and name:find("table", 1, true) ~= nil end,
            get = function() return nil end,
        }
        local sprite = { getName = function() return name end, getProperties = function() return props end }
        objects[#objects + 1] = { getSprite = function() return sprite end, getSquare = function() return sq end }
    end
    sq.getObjects = function() return mockList(objects) end
    return sq
end
function getCell()
    return { getGridSquare = function(_, x, y, z) return mockSquare(x, y, z) end }
end
function mockPlaceTable(x, y, z, w, h)
    for dx = 0, (w or 1) - 1 do
        for dy = 0, (h or 1) - 1 do
            MOCK_GRID[(x + dx) .. "," .. (y + dy) .. "," .. z] = { "furniture_tables_high_01_0" }
        end
    end
end
-- Puts a character on a chair at (x, y, z); nil x makes them stand up.
function mockSit(player, x, y, z)
    if not x then
        player.chairAt = nil
        return
    end
    MOCK_GRID[x .. "," .. y .. "," .. z] = { "furniture_seating_indoor_01_0" }
    player.chairAt = { x, y, z }
end
local function sitMethods(player)
    player.isSittingOnFurniture = function(self) return self.chairAt ~= nil end
    player.getSitOnFurnitureObject = function(self)
        local c = self.chairAt
        if not c then return nil end
        local sq = mockSquare(c[1], c[2], c[3])
        return sq and sq:getObjects():get(0)
    end
end
MOCK_SIT_METHODS = sitMethods
sitMethods(MOCK_PLAYER)
mockPlaceTable(100, 199, 0, 2, 1)
mockSit(MOCK_PLAYER, 100, 200, 0)
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
MOCK_Z = 0
function Base:bringToTop() MOCK_Z = MOCK_Z + 1 self.z = MOCK_Z end
function Base:prerender() end
function Base:setX(x) if not isNum(x) then fail("setX") end self.x = x end
function Base:setY(y) if not isNum(y) then fail("setY") end self.y = y end
function Base:setHeight(h) if not isNum(h) then fail("setHeight") end self.height = h end
function Base:setWidth(w) if not isNum(w) then fail("setWidth") end self.width = w end
function Base:addChild(child)
    self.children = self.children or {}
    self.children[#self.children + 1] = child
    child.parent = self
end
function Base:getX() return self.x end
function Base:getY() return self.y end
function Base:getWidth() return self.width end
function Base:getHeight() return self.height end
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

IsoDirections = { N = "N", S = "S", E = "E", W = "W" }
function getPlayerFromUsername(name) return nil end
ISUI3DModel = Base:derive("ISUI3DModel")
function ISUI3DModel:new(x, y, w, h)
    local o = Base.new(self, x, y, w, h)
    o.javaObject = { setConsumeMouseEvents = function(_, v) o.consumesMouse = v end }
    return o
end
-- cfg.order lists the calls, so tests can check the anim set is chosen before the character
local function record(self, field)
    self.cfg = self.cfg or { order = {} }
    self.cfg.order[#self.cfg.order + 1] = field
end
local function setter(field)
    return function(self, value) record(self, field) self.cfg[field] = value end
end
for _, f in ipairs({ "setAnimSetName", "setState", "setIsometric", "setDoRandomExtAnimations", "setDirection",
    "setZoom", "setYOffset", "setXOffset", "setCharacter" }) do
    ISUI3DModel[f] = setter(f)
end
-- In game a bare setOutfitName leaves the model without a body and the renderer throws every frame.
function ISUI3DModel:setOutfitName(name, female, zombie)
    fail("setOutfitName crashes the UI3DModel renderer; use setSurvivorDesc")
end
function ISUI3DModel:setSurvivorDesc(desc)
    if type(desc) ~= "table" or not desc.outfit then fail("setSurvivorDesc needs a dressed SurvivorDesc") end
    record(self, "setSurvivorDesc")
    self.cfg.outfit = desc and desc.outfit
end
SurvivorType = { Neutral = "Neutral" }
SurvivorFactory = {
    CreateSurvivor = function(kind, female)
        if kind ~= SurvivorType.Neutral or type(female) ~= "boolean" then fail("CreateSurvivor args") end
        return { female = female, dressInNamedOutfit = function(self, name)
            if type(name) ~= "string" then fail("dressInNamedOutfit name") end
            self.outfit = name
        end }
    end,
}
function ISUI3DModel:reportEvent(event)
    if type(event) ~= "string" then fail("reportEvent name") end
    record(self, "reportEvent")
    self.cfg["event_" .. event] = true
end
function ISUI3DModel:setVariable(key, value)
    record(self, "setVariable")
    self.cfg["var_" .. key] = value
end

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
