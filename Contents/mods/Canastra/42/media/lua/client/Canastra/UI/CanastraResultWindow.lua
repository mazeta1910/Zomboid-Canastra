require "ISUI/ISCollapsableWindow"
require "Canastra/CanastraClient"
require "Canastra/UI/CanastraDraw"

CanastraResultWindow = ISCollapsableWindow:derive("CanastraResultWindow")
local W = CanastraResultWindow
local D = CanastraDraw
local CC = CanastraClient

local PAD = 8

local function myTeam(v)
    return v.teamOf[v.you] or 1
end

local function rowsFor(rules)
    local rows = {
        { "Res_Melds", "melds" }, { "Res_Canastas", "bonus" }, { "Res_GoOut", "goOut" },
        { "Res_Hand", "hand" }, { "Res_Dead", "dead" },
    }
    if rules.redThrees then rows[#rows + 1] = { "Res_Red3", "red3" } end
    if (rules.blackThreePenalty or 0) > 0 then rows[#rows + 1] = { "Res_Black3", "black3" } end
    rows[#rows + 1] = { "Res_Total", "total" }
    return rows
end

local function headline(v)
    local us = myTeam(v)
    local res = v.result
    if v.phase == "matchOver" then
        return CC.text(v.winner == us and "MatchWon" or "MatchLost")
    elseif res.goOutTeam == us then
        return CC.text("RoundWentOutUs")
    elseif res.goOutTeam ~= 0 then
        return CC.text("RoundWentOutThem")
    end
    return CC.text("RoundStockEnded")
end

-- Opens centred over `over` the first time; later rounds reuse the position the player left it at.
function W.open(over)
    local v = CC.view
    if not v or not v.result then return nil end
    if W.instance then W.instance:close() end
    local lineH = D.FH + 2
    local th = ISCollapsableWindow.TitleBarHeight()
    local w = math.floor(360 * D.S)
    local h = th + PAD + lineH * (#rowsFor(v.rules) + 2) + 10 + D.ICON + PAD
    local win = W:new(0, 0, w, h)
    win:initialise()
    win:addToUIManager()
    if W.lastX then
        win:setX(W.lastX)
        win:setY(W.lastY)
    elseif over then
        win:setX(math.floor(over:getX() + (over:getWidth() - w) / 2))
        win:setY(math.floor(over:getY() + (over:getHeight() - h) / 2))
    else
        D.centerOnScreen(win)
    end
    D.raiseOverClicked(win)
    W.instance = win
    return win
end

function W:new(x, y, w, h)
    local o = ISCollapsableWindow.new(self, x, y, w, h)
    o.title = ""
    o.resizable = false
    o.backgroundColor = { r = 0.03, g = 0.08, b = 0.05, a = 0.97 }
    o.borderColor = { r = D.COLOR_GOLD.r, g = D.COLOR_GOLD.g, b = D.COLOR_GOLD.b, a = 0.8 }
    return o
end

function W:close()
    W.lastX, W.lastY = self:getX(), self:getY()
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    if W.instance == self then W.instance = nil end
end

function W.nextRound()
    CC.send("nextRound")
end

function W.backToLobby()
    CC.send("backToLobby")
end

function W:prerender()
    D.keepRaised(self)
    ISCollapsableWindow.prerender(self)
end

function W:render()
    local v = CC.view
    if not v or not v.result then
        ISCollapsableWindow.render(self)
        return
    end
    self.title = headline(v)
    ISCollapsableWindow.render(self)
    if self.isCollapsed then return end
    D.beginHits(self)
    local res = v.result
    local us, them = myTeam(v), myTeam(v) == 1 and 2 or 1
    local lineH = D.FH + 2
    local w = self.width
    local cy = self:titleBarHeight() + PAD
    local c1, c2 = w * 0.62, w - PAD
    self:drawTextRight(CC.text("Us"), c1, cy, D.COLOR_US.r, D.COLOR_US.g, D.COLOR_US.b, 1, D.FONT)
    self:drawTextRight(CC.text("Them"), c2, cy, D.COLOR_THEM.r, D.COLOR_THEM.g, D.COLOR_THEM.b, 1, D.FONT)
    cy = cy + lineH
    for _, r in ipairs(rowsFor(v.rules)) do
        local isTotal = r[2] == "total"
        if isTotal then self:drawRect(PAD, cy - 1, w - PAD * 2, 1, 0.4, 1, 1, 1) end
        local a = isTotal and 1 or 0.85
        self:drawText(CC.text(r[1]), PAD, cy, a, a, a, 1, D.FONT)
        self:drawTextRight(tostring(res.teams[us][r[2]] or 0), c1, cy, a, a, a, 1, D.FONT)
        self:drawTextRight(tostring(res.teams[them][r[2]] or 0), c2, cy, a, a, a, 1, D.FONT)
        cy = cy + lineH
    end
    self:drawText(CC.text("Res_Score"), PAD, cy + 2, 1, 1, 1, 1, D.FONT)
    self:drawTextRight(tostring(v.scores[us]), c1, cy + 2, D.COLOR_US.r, D.COLOR_US.g, D.COLOR_US.b, 1, D.FONT)
    self:drawTextRight(tostring(v.scores[them]), c2, cy + 2, D.COLOR_THEM.r, D.COLOR_THEM.g, D.COLOR_THEM.b, 1, D.FONT)
    cy = cy + lineH + 8

    if CC.isHost() then
        local label = CC.text(v.phase == "matchOver" and "NewMatch" or "NextRound")
        local bw = D.ICON + D.textW(label) + 6
        D.labelButton(self, w - PAD - bw, cy, "nextround", label, nil, W.nextRound)
        if v.phase == "matchOver" then
            D.labelButton(self, PAD, cy, "back", CC.text("BackToLobby"), nil, W.backToLobby)
        end
    else
        self:drawTextCentre(CC.text("WaitingHost"), w / 2, cy + (D.ICON - D.FH) / 2, 0.7, 0.7, 0.7, 1, D.FONT)
    end
    D.drawTooltip(self)
end

function W:onMouseDown(x, y)
    if D.click(self, x, y) then return true end
    return ISCollapsableWindow.onMouseDown(self, x, y)
end
