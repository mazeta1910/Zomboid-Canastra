require "ISUI/ISCollapsableWindow"
require "Canastra/CanastraClient"
require "Canastra/UI/CanastraDraw"

CanastraRulesWindow = ISCollapsableWindow:derive("CanastraRulesWindow")
local W = CanastraRulesWindow
local D = CanastraDraw
local R = Canastra.Rules
local CC = CanastraClient

local COLS = 2
local ROW_H = math.max(D.ICON, D.FH) + 4
local COL_W = math.floor(330 * D.S)
local PAD = 8

-- rules: table edited in place; editable: bool; onChange(rules) called after each edit.
function W.open(rules, editable, onChange)
    if W.instance then W.instance:close() end
    local rows = math.ceil((#R.SCHEMA + 1) / COLS)
    local th = ISCollapsableWindow.TitleBarHeight()
    local w = COLS * COL_W + PAD * (COLS + 1)
    local h = th + PAD + rows * ROW_H + PAD + D.ICON + PAD
    local win = W:new(0, 0, w, h)
    win.rules = rules
    win.editable = editable
    win.onChange = onChange
    win:initialise()
    win:addToUIManager()
    win:bringToTop()
    win.raiseFrames = 2
    D.centerOnScreen(win)
    W.instance = win
    return win
end

function W:new(x, y, w, h)
    local o = ISCollapsableWindow.new(self, x, y, w, h)
    o.title = CC.text("RulesTitle")
    o.resizable = false
    o.backgroundColor = { r = 0.05, g = 0.12, b = 0.07, a = 0.95 }
    return o
end

function W:close()
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    if W.instance == self then W.instance = nil end
end

function W:changed()
    if self.onChange then self.onChange(self.rules) end
end

function W:cycle(arg)
    R.cycle(self.rules, arg.key, arg.dir)
    self:changed()
end

function W:cyclePreset(dir)
    local idx = 1
    for i, p in ipairs(R.PRESET_ORDER) do
        if p == self.rules.preset then idx = i end
    end
    idx = idx + dir
    if idx > #R.PRESET_ORDER then idx = 1 end
    if idx < 1 then idx = #R.PRESET_ORDER end
    local fresh = R.fromPreset(R.PRESET_ORDER[idx])
    for k in pairs(self.rules) do self.rules[k] = nil end
    for k, v in pairs(fresh) do self.rules[k] = v end
    self:changed()
end

local function drawRow(self, x, y, label, value, tooltip, onPrev, onNext, arg)
    local hover = D.isHover(self, x, y, COL_W, ROW_H)
    if hover then self:drawRect(x, y, COL_W, ROW_H, 0.25, 1, 1, 1) end
    self:drawText(label, x + 4, y + (ROW_H - D.FH) / 2, 0.85, 0.85, 0.85, 1, D.FONT)
    local vw = math.floor(COL_W * 0.42)
    local vx = x + COL_W - vw
    self:drawTextCentre(value, vx + vw / 2, y + (ROW_H - D.FH) / 2, 1, 0.9, 0.5, 1, D.FONT)
    D.addHit(self, x, y, COL_W - vw, ROW_H, nil, nil, tooltip)
    if self.editable then
        local s = D.ICON
        local iy = y + (ROW_H - s) / 2
        D.iconButton(self, vx - 2, iy, "prev", tooltip, onPrev, arg)
        D.iconButton(self, x + COL_W - s, iy, "next", tooltip, onNext, arg)
    end
end

-- Opened from a click on another window, which the UI manager raises after the click;
-- keep raising this one until the button is released.
function W:prerender()
    if self.raiseFrames then
        self:bringToTop()
        if isMouseButtonDown and isMouseButtonDown(0) then
            self.raiseFrames = 2
        else
            self.raiseFrames = self.raiseFrames - 1
            if self.raiseFrames <= 0 then self.raiseFrames = nil end
        end
    end
    ISCollapsableWindow.prerender(self)
end

function W:render()
    ISCollapsableWindow.render(self)
    if self.isCollapsed then return end
    D.beginHits(self)
    local th = self:titleBarHeight()
    local rules = self.rules

    local function cellPos(i)
        local col = (i - 1) % COLS
        local row = math.floor((i - 1) / COLS)
        return PAD + col * (COL_W + PAD), th + PAD + row * ROW_H
    end

    local x, y = cellPos(1)
    drawRow(self, x, y, CC.text("Preset"), CC.presetName(rules.preset), CC.text("PresetTip"),
        function(s) s:cyclePreset(-1) end, function(s) s:cyclePreset(1) end)

    for i, opt in ipairs(R.SCHEMA) do
        x, y = cellPos(i + 1)
        drawRow(self, x, y, CC.ruleLabel(opt.key), CC.ruleValue(opt.key, rules[opt.key]),
            getText("IGUI_Canastra_RuleTip_" .. opt.key),
            function(s, a) s:cycle({ key = a, dir = -1 }) end,
            function(s, a) s:cycle({ key = a, dir = 1 }) end, opt.key)
    end

    local by = self.height - PAD - D.ICON
    D.labelButton(self, self.width - PAD - D.textW(CC.text("Close")) - D.ICON - 6, by, "confirm", CC.text("Close"), nil,
        function(s) s:close() end)
    if not self.editable then
        self:drawText(CC.text("RulesReadOnly"), PAD, by + (D.ICON - D.FH) / 2, 0.7, 0.7, 0.7, 1, D.FONT)
    end
    D.drawTooltip(self)
end

function W:onMouseDown(x, y)
    if D.click(self, x, y) then return true end
    return ISCollapsableWindow.onMouseDown(self, x, y)
end
