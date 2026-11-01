require "ISUI/ISUI3DModel"
require "Canastra/CanastraClient"
require "Canastra/UI/CanastraDraw"

-- 3D models of the seated players (table scene) and their face portraits (score strip).
-- Each window keeps one model per slot; slots not placed during a frame are hidden.
CanastraAvatars = {}
local A = CanastraAvatars
local D = CanastraDraw

-- Face framing taken from the game's make-up screen (square panel).
A.PORTRAIT = { dir = "S", zoom = 20, y = -0.87 }

local OUTFITS = {
    "Generic01", "Generic02", "Generic03", "Generic04", "Generic05", "Tourist", "Farmer",
    "Fisherman", "Student", "Teacher", "Classy", "Golfer", "Young", "Mechanic", "Hunter", "Chef",
}
local FEMALE = { Ana = true, Duda = true, Fabi = true, Helena = true }

CanastraAvatar = ISUI3DModel:derive("CanastraAvatar")

-- No drag-to-rotate: the models are part of the scenery.
function CanastraAvatar:onMouseDown(x, y) return false end
function CanastraAvatar:onMouseUp(x, y) return false end
function CanastraAvatar:onMouseMove(dx, dy) return false end
function CanastraAvatar:onMouseMoveOutside(dx, dy) return false end
function CanastraAvatar:onMouseUpOutside(x, y) return false end

local function findPlayer(key)
    if type(key) ~= "string" or key == "" then return nil end
    local localNum = key:match("^local(%d+)$")
    if localNum then return getSpecificPlayer(tonumber(localNum)) end
    if getPlayerFromUsername then
        local p = getPlayerFromUsername(key)
        if p then return p end
    end
    local list = getOnlinePlayers and getOnlinePlayers()
    if list then
        for i = 0, list:size() - 1 do
            local p = list:get(i)
            if p:getUsername() == key then return p end
        end
    end
    return nil
end

local function nameHash(s)
    local h = 0
    for i = 1, #s do h = (h * 31 + s:byte(i)) % 65536 end
    return h
end

-- One look per bot name for the session. A bare setOutfitName leaves the model without a body
-- (the Java renderer then throws every frame and the whole window stops drawing).
local botDescs = {}
local function botDesc(name)
    local short = (name or ""):gsub("^Bot ", "")
    local desc = botDescs[short]
    if not desc then
        desc = SurvivorFactory.CreateSurvivor(SurvivorType.Neutral, FEMALE[short] or false)
        desc:dressInNamedOutfit(OUTFITS[nameHash(short) % #OUTFITS + 1])
        botDescs[short] = desc
    end
    return desc
end

-- setState alone only swaps the animation: the model's action context stays in "idle" and its first
-- transition stands the character back up. The event moves the action context itself into
-- "sitonfurniture" (actiongroups/player/idle/to_sitonfurniture.xml), which only leaves when moving.
local function setPose(panel, view)
    if view.seated then
        panel:setVariable("SitOnFurnitureAnim", "Idle")
        panel:setState("sitonfurniture")
        panel:reportEvent("EventSitOnFurniture")
    else
        panel:setState("idle")
    end
end
local SIT_REFRESH_MS = 2000

-- Returns true once the model shows the seat's character. The anim set and state must be chosen
-- before the character is assigned (as the game's own avatar panels do); afterwards they are ignored.
local function dress(panel, seatInfo, view)
    local player
    if seatInfo.kind == "human" then
        player = findPlayer(seatInfo.key)
        if not player then return false end
    elseif seatInfo.kind ~= "bot" then
        return false
    end
    panel:setAnimSetName(view.seated and "player" or "player-avatar")
    setPose(panel, view)
    if player then
        panel:setCharacter(player)
    else
        panel:setSurvivorDesc(botDesc(seatInfo.name))
    end
    setPose(panel, view)
    panel:setIsometric(false)
    panel:setDoRandomExtAnimations(false)
    panel:setDirection(IsoDirections[view.dir])
    panel:setZoom(view.zoom)
    panel:setYOffset(view.y)
    return true
end

function A.beginFrame(win)
    win.avatarsUsed = {}
end

-- Shows the seat's model in rect r. Returns false when no model can be shown (draw a fallback).
function A.place(win, slot, seatInfo, r, view)
    win.avatars = win.avatars or {}
    local a = win.avatars[slot]
    if not a then
        local panel = CanastraAvatar:new(r.x, r.y, r.w, r.h)
        panel:initialise()
        win:addChild(panel)
        -- clicks go through to the cards drawn over the model's lower part
        if panel.javaObject then panel.javaObject:setConsumeMouseEvents(false) end
        a = { panel = panel }
        win.avatars[slot] = a
    end
    local who = tostring(seatInfo.kind) .. ":" .. tostring(seatInfo.key ~= "" and seatInfo.key or seatInfo.name)
    if a.who ~= who and not a.broken then
        local now = getTimestampMs()
        if a.pendingWho ~= who or now >= (a.retryAt or 0) then
            a.pendingWho = who
            local ok, shown = pcall(dress, a.panel, seatInfo, view)
            if not ok then
                a.broken = true
                print("[Canastra] 3D avatar unavailable: " .. tostring(shown))
            elseif shown then
                a.who = who
                a.sitAt = now
            else
                a.retryAt = now + 2000
            end
        end
    elseif a.who == who and view.seated and not a.broken then
        local now = getTimestampMs()
        if now - (a.sitAt or 0) >= SIT_REFRESH_MS then
            a.sitAt = now
            pcall(setPose, a.panel, view)
        end
    end
    local p = a.panel
    if p.x ~= r.x or p.y ~= r.y or p.width ~= r.w or p.height ~= r.h then
        p:setX(r.x)
        p:setY(r.y)
        p:setWidth(r.w)
        p:setHeight(r.h)
    end
    local shown = a.who == who and not a.broken
    p:setVisible(shown)
    if shown and win.avatarsUsed then win.avatarsUsed[slot] = true end
    return shown
end

function A.endFrame(win)
    local used = win.avatarsUsed or {}
    for slot, a in pairs(win.avatars or {}) do
        if not used[slot] then a.panel:setVisible(false) end
    end
end

function A.hideAll(win)
    win.avatarsUsed = {}
    A.endFrame(win)
end

-- Grey silhouette with the name's initial, used when the 3D model is unavailable.
function A.drawSilhouette(win, r, name)
    local s = math.min(r.w, r.h)
    local x, y = r.x + (r.w - s) / 2, r.y + r.h - s
    win:drawTextureScaled(D.tex("silhouette"), x, y, s, s, 0.55, 0.75, 0.75, 0.75)
    local initial = (name or "?"):gsub("^Bot ", ""):sub(1, 1):upper()
    win:drawTextCentre(initial, x + s / 2, y + s * 0.62 - D.FH / 2, 0.15, 0.15, 0.15, 1, D.FONT)
end

return A
