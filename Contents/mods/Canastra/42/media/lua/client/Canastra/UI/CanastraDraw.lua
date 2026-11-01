require "Canastra/CanastraCards"

CanastraDraw = {}
local D = CanastraDraw
local C = Canastra.Cards

local TM = getTextManager()
D.FONT = UIFont.Small
D.FH = TM:getFontHeight(UIFont.Small)
D.FH_MED = TM:getFontHeight(UIFont.Medium)
D.S = math.max(1, math.min(2, D.FH / 16))

D.ICON = math.floor(20 * D.S)
D.HAND_W = math.floor(math.max(40, D.FH * 2.5))
D.HAND_H = math.floor(D.HAND_W * 1.4)
D.MINI_W = math.floor(math.max(28, D.FH * 1.8))
D.MINI_H = math.floor(D.MINI_W * 1.38)
D.MINI_STEP = TM:MeasureStringX(UIFont.Small, "10") + 6

D.COLOR_US = { r = 0.55, g = 0.9, b = 0.55 }
D.COLOR_THEM = { r = 0.95, g = 0.55, b = 0.5 }
D.COLOR_DIM = { r = 0.7, g = 0.7, b = 0.7 }
D.COLOR_GOLD = { r = 1, g = 0.82, b = 0.25 }

local SUIT_TEX = { [1] = "suit_spade", [2] = "suit_heart", [3] = "suit_club", [4] = "suit_diamond" }
-- Pixel sizes exported by tools/generate_textures.py.
local SUIT_SIZES = { 12, 14, 16, 20, 24, 28, 32, 40, 48, 64, 96, 128 }
local EMBLEM_SIZES = { 16, 24, 32, 48, 64, 96 }
local CARD_WIDTHS = { 32, 48, 64, 96 }
local EMBLEMS = { [11] = "emblem_jack", [12] = "emblem_queen", [13] = "emblem_king" }

local INK = { r = 0.09, g = 0.09, b = 0.11 }
local RED = { r = 0.78, g = 0.09, b = 0.14 }
D.SUIT_COLORS = {
    [1] = INK, [2] = RED, [3] = INK, [4] = RED,
}
D.SUIT_COLORS4 = {
    [1] = INK, [2] = RED, [3] = { r = 0.07, g = 0.49, b = 0.22 }, [4] = { r = 0.1, g = 0.35, b = 0.78 },
}
local JOKER_COLOR = { r = 0.43, g = 0.2, b = 0.63 }

local cache = {}

function D.tex(name)
    local t = cache[name]
    if t == nil then
        t = getTexture("media/ui/Canastra/" .. name .. ".png") or false
        cache[name] = t
    end
    return t or nil
end

function D.textW(text, font)
    return TM:MeasureStringX(font or D.FONT, text)
end

-- Cuts text with "..." so it fits in maxW pixels.
function D.fitText(text, maxW, font)
    if D.textW(text, font) <= maxW then return text end
    local cut = #text
    while cut > 0 and D.textW(text:sub(1, cut) .. "...", font) > maxW do cut = cut - 1 end
    -- avoid splitting a multi-byte UTF-8 character
    while cut > 0 and text:byte(cut + 1) and text:byte(cut + 1) >= 128 and text:byte(cut + 1) < 192 do cut = cut - 1 end
    return text:sub(1, cut) .. "..."
end

-- Name of the smallest exported variant that is at least px wide.
local function sized(base, sizes, px)
    for _, s in ipairs(sizes) do
        if s >= px then return base .. "_" .. s end
    end
    return base .. "_" .. sizes[#sizes]
end

-- ------------------------------------------------------------------ client settings

local SETTINGS_FILE = "Canastra_settings.txt"
D.fourColor = false
D.sortMode = "suit"
local settingsLoaded = false

function D.loadSettings()
    if settingsLoaded then return end
    settingsLoaded = true
    pcall(function()
        local reader = getFileReader(SETTINGS_FILE, false)
        if not reader then return end
        local line = reader:readLine()
        while line do
            if line == "fourColor=true" then D.fourColor = true end
            if line == "sortMode=rank" then D.sortMode = "rank" end
            line = reader:readLine()
        end
        reader:close()
    end)
end

local function saveSettings()
    pcall(function()
        local writer = getFileWriter(SETTINGS_FILE, true, false)
        writer:write("fourColor=" .. tostring(D.fourColor) .. "\n")
        writer:write("sortMode=" .. D.sortMode .. "\n")
        writer:close()
    end)
end

function D.setFourColor(on)
    D.fourColor = on and true or false
    saveSettings()
end

function D.setSortMode(mode)
    D.sortMode = mode == "rank" and "rank" or "suit"
    saveSettings()
end

function D.suitColor(id)
    if C.isJoker(id) then return JOKER_COLOR end
    D.loadSettings()
    return (D.fourColor and D.SUIT_COLORS4 or D.SUIT_COLORS)[C.suit(id)]
end

function D.suitTex(id, px)
    return D.tex(sized(SUIT_TEX[C.suit(id)], SUIT_SIZES, px or 64))
end

-- Suit symbol (or joker hat) in the card's colour.
function D.drawSuit(ui, id, x, y, s, tint)
    tint = tint or 1
    if C.isJoker(id) then
        ui:drawTextureScaled(D.tex(sized("joker", EMBLEM_SIZES, s)), x, y, s, s, 1, tint, tint, tint)
        return
    end
    local col = D.suitColor(id)
    ui:drawTextureScaled(D.suitTex(id, s), x, y, s, s, 1, col.r * tint, col.g * tint, col.b * tint)
end

function D.cardBackTex(w)
    return D.tex(sized("card_back", CARD_WIDTHS, w))
end

-- Centre art of a full-size card: big suit, court figure, or the joker hat.
local function drawCardArt(ui, id, x, y, w, h, pad, col, tint)
    if C.isJoker(id) then
        local s = math.floor(w * 0.62)
        D.drawSuit(ui, id, x + w - s - pad, y + h - s - pad, s, tint)
    elseif EMBLEMS[C.rank(id)] then
        local s = math.floor(w * 0.6)
        ui:drawTextureScaled(D.tex(sized(EMBLEMS[C.rank(id)], EMBLEM_SIZES, s)),
            x + w - s - pad + 1, y + h - s - pad + 1, s, s, 1, col.r * tint, col.g * tint, col.b * tint)
    else
        local s = math.floor(w * (C.rank(id) == 1 and 0.62 or 0.5))
        D.drawSuit(ui, id, x + w - s - pad, y + h - s - pad, s, tint)
    end
end

-- opts: back, mini, selected, fresh, warn, highlight, dim
function D.drawCard(ui, id, x, y, w, h, opts)
    opts = opts or {}
    ui:drawRect(x + 1, y + 2, w, h, 0.35, 0, 0, 0)
    if opts.back then
        ui:drawTextureScaled(D.cardBackTex(w), x, y, w, h, 1, 1, 1, 1)
        return
    end
    local tint = opts.dim and 0.55 or 1
    ui:drawTextureScaled(D.tex(sized("card_face", CARD_WIDTHS, w)), x, y, w, h, 1, tint, tint, tint)

    local col = D.suitColor(id)
    local pad = math.max(2, math.floor(w * 0.08))
    local font, fh = D.FONT, D.FH
    if not opts.mini and D.FH_MED <= h * 0.36 then font, fh = UIFont.Medium, D.FH_MED end
    local label = C.isJoker(id) and "JK" or C.rankLabel(id)
    ui:drawText(label, x + pad, y, col.r * tint, col.g * tint, col.b * tint, 1, font)

    local isz = math.floor(w * (opts.mini and 0.42 or 0.3))
    D.drawSuit(ui, id, x + pad, y + fh - 1, isz, tint)
    -- Overlapped mini cards only show their left strip, so they carry the corner index alone.
    if not opts.mini then drawCardArt(ui, id, x, y, w, h, pad, col, tint) end
    if opts.selected then
        ui:drawRectBorder(x, y, w, h, 1, 1, 0.8, 0.1)
        ui:drawRectBorder(x + 1, y + 1, w - 2, h - 2, 1, 1, 0.8, 0.1)
    elseif opts.fresh then
        ui:drawRectBorder(x - 2, y - 2, w + 4, h + 4, 0.35, 0.35, 0.95, 0.35)
        ui:drawRectBorder(x - 1, y - 1, w + 2, h + 2, 0.7, 0.35, 0.95, 0.35)
        for i = 0, 2 do
            ui:drawRectBorder(x + i, y + i, w - i * 2, h - i * 2, 1, 0.25, 0.85, 0.25)
        end
    elseif opts.warn then
        for i = 0, 1 do
            ui:drawRectBorder(x + i, y + i, w - i * 2, h - i * 2, 1, 0.9, 0.2, 0.2)
        end
    elseif opts.highlight then
        ui:drawRectBorder(x, y, w, h, 1, 0.3, 0.9, 0.3)
        ui:drawRectBorder(x + 1, y + 1, w - 2, h - 2, 1, 0.3, 0.9, 0.3)
    end
end

-- ------------------------------------------------------------------ hit regions
-- Windows rebuild self.hits every frame; the last region drawn wins (cards overlap left to right).

function D.beginHits(ui)
    ui.hits = {}
end

function D.addHit(ui, x, y, w, h, fn, arg, tooltip)
    local list = ui.hits
    list[#list + 1] = { x = x, y = y, w = w, h = h, fn = fn, arg = arg, tooltip = tooltip }
end

function D.hitAt(ui, x, y)
    local list = ui.hits or {}
    for i = #list, 1, -1 do
        local r = list[i]
        if x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h then return r end
    end
    return nil
end

function D.isHover(ui, x, y, w, h)
    if not ui:isMouseOver() then return false end
    local mx, my = ui:getMouseX(), ui:getMouseY()
    return mx >= x and mx < x + w and my >= y and my < y + h
end

-- Small square icon button. Returns its width.
function D.iconButton(ui, x, y, icon, tooltip, fn, arg, enabled)
    local s = D.ICON
    if enabled == nil then enabled = true end
    local hover = enabled and D.isHover(ui, x, y, s, s)
    ui:drawRect(x, y, s, s, hover and 0.85 or 0.45, hover and 0.2 or 0, hover and 0.45 or 0, hover and 0.25 or 0)
    ui:drawRectBorder(x, y, s, s, enabled and 0.45 or 0.2, 1, 1, 1)
    local a = enabled and 1 or 0.3
    ui:drawTextureScaled(D.tex("icon_" .. icon), x + 2, y + 2, s - 4, s - 4, a, 1, 1, 1)
    D.addHit(ui, x, y, s, s, enabled and fn or nil, arg, tooltip)
    return s
end

-- Compact icon + short label button. Returns its width.
function D.labelButton(ui, x, y, icon, label, tooltip, fn, arg, enabled)
    local s = D.ICON
    if enabled == nil then enabled = true end
    local w = s + D.textW(label) + 6
    local hover = enabled and D.isHover(ui, x, y, w, s)
    ui:drawRect(x, y, w, s, hover and 0.85 or 0.45, hover and 0.2 or 0, hover and 0.45 or 0, hover and 0.25 or 0)
    ui:drawRectBorder(x, y, w, s, enabled and 0.45 or 0.2, 1, 1, 1)
    local a = enabled and 1 or 0.35
    ui:drawTextureScaled(D.tex("icon_" .. icon), x + 2, y + 2, s - 4, s - 4, a, 1, 1, 1)
    ui:drawText(label, x + s + 1, y + (s - D.FH) / 2, a, a, a, 1, D.FONT)
    D.addHit(ui, x, y, w, s, enabled and fn or nil, arg, tooltip)
    return w
end

function D.drawTooltip(ui)
    if not ui:isMouseOver() or not ui.hits then return end
    local mx, my = ui:getMouseX(), ui:getMouseY()
    local r = D.hitAt(ui, mx, my)
    if not r or not r.tooltip or r.tooltip == "" then return end
    local w = D.textW(r.tooltip) + 10
    local x = math.min(mx + 14, ui.width - w - 2)
    local y = my + 18
    if y + D.FH + 6 > ui.height then y = my - D.FH - 10 end
    ui:drawRect(x, y, w, D.FH + 6, 0.92, 0.08, 0.08, 0.08)
    ui:drawRectBorder(x, y, w, D.FH + 6, 0.6, 1, 1, 1)
    ui:drawText(r.tooltip, x + 5, y + 3, 1, 1, 1, 1, D.FONT)
end

-- Fires the region under the mouse. Returns true when a region consumed the click.
function D.click(ui, x, y)
    local r = D.hitAt(ui, x, y)
    if not r then return false end
    if r.fn then
        getSoundManager():playUISound("UIActivateButton")
        r.fn(ui, r.arg)
    end
    return true
end

function D.centerOnScreen(win)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    win:setX(math.max(0, (sw - win.width) / 2))
    win:setY(math.max(0, (sh - win.height) / 2))
end

-- A window opened from a click on another window gets covered when the UI manager raises
-- the clicked one; D.keepRaised (called from prerender) re-raises it until the button is released.
function D.raiseOverClicked(win)
    win:bringToTop()
    win.raiseFrames = 2
end

function D.keepRaised(win)
    if not win.raiseFrames then return end
    win:bringToTop()
    if isMouseButtonDown and isMouseButtonDown(0) then
        win.raiseFrames = 2
    else
        win.raiseFrames = win.raiseFrames - 1
        if win.raiseFrames <= 0 then win.raiseFrames = nil end
    end
end

return D
