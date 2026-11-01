require "ISUI/ISCollapsableWindow"
require "Canastra/CanastraClient"
require "Canastra/UI/CanastraDraw"
require "Canastra/UI/CanastraRulesWindow"

CanastraLobbyWindow = ISCollapsableWindow:derive("CanastraLobbyWindow")
local W = CanastraLobbyWindow
local D = CanastraDraw
local R = Canastra.Rules
local N = Canastra.Net
local CC = CanastraClient

local PAD = 8
local ROW_H = math.max(D.ICON, D.FH) + 4
local WIDTH = math.floor(400 * D.S)
local HEIGHT = math.floor(330 * D.S)

W.pending = { n = 4, fillBots = true, rules = R.fromPreset("buraco_aberto") }

function W.open()
    if W.instance then
        W.instance:setVisible(true)
        W.instance:bringToTop()
        W.instance:refresh()
        return W.instance
    end
    local win = W:new(0, 0, WIDTH, HEIGHT)
    win:initialise()
    win:addToUIManager()
    D.centerOnScreen(win)
    W.instance = win
    CC.send("list")
    return win
end

function W:new(x, y, w, h)
    local o = ISCollapsableWindow.new(self, x, y, w, h)
    o.title = CC.text("LobbyTitle")
    o.resizable = false
    o.backgroundColor = { r = 0.05, g = 0.12, b = 0.07, a = 0.95 }
    return o
end

function W:close()
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    if W.instance == self then W.instance = nil end
    if CanastraRulesWindow.instance then CanastraRulesWindow.instance:close() end
end

function W:refresh()
end

-- ------------------------------------------------------------------ actions

function W:join(t)
    CC.send("join", { id = t.id, seat = CC.seatArgs() })
end

function W:create()
    CC.send("create", {
        n = W.pending.n, rules = W.pending.rules, fillBots = W.pending.fillBots,
        decks = N.countDecks(getPlayer()), seat = CC.seatArgs(),
    })
end

function W:openRules()
    if CC.info then
        local rules = R.sanitize(CC.info.rules)
        CanastraRulesWindow.open(rules, CC.isHost(), function(r)
            CC.send("setRules", { rules = r, n = CC.info.n })
        end)
    else
        CanastraRulesWindow.open(W.pending.rules, true, nil)
    end
end

function W:cyclePreset(dir)
    local idx = 1
    for i, p in ipairs(R.PRESET_ORDER) do
        if p == W.pending.rules.preset then idx = i end
    end
    idx = idx + dir
    if idx > #R.PRESET_ORDER then idx = 1 end
    if idx < 1 then idx = #R.PRESET_ORDER end
    W.pending.rules = R.fromPreset(R.PRESET_ORDER[idx])
end

-- ------------------------------------------------------------------ rendering

local function drawHeader(self, y, text)
    self:drawText(text, PAD, y, D.COLOR_GOLD.r, D.COLOR_GOLD.g, D.COLOR_GOLD.b, 1, D.FONT)
    self:drawRect(PAD, y + D.FH + 1, self.width - PAD * 2, 1, 0.3, 1, 1, 1)
    return y + D.FH + 5
end

local function modeLabel(n)
    return n == 4 and "2x2" or "1x1"
end

function W:renderBrowse(y)
    y = drawHeader(self, y, CC.text("NearbyTables"))
    local tables = CC.nearbyTables()
    if #tables == 0 then
        self:drawText(CC.text("NoTables"), PAD, y + 2, 0.7, 0.7, 0.7, 1, D.FONT)
        y = y + ROW_H
    end
    for i, t in ipairs(tables) do
        if i > 5 then break end
        local hover = D.isHover(self, PAD, y, self.width - PAD * 2, ROW_H)
        if hover then self:drawRect(PAD, y, self.width - PAD * 2, ROW_H, 0.2, 1, 1, 1) end
        local status = t.status == "lobby" and CC.text("Waiting") or CC.text("Playing")
        local line = string.format("%s  %s  %d/%d  %s", t.hostName, modeLabel(t.n), t.filled, t.n, CC.presetName(t.preset))
        self:drawText(line, PAD + 4, y + (ROW_H - D.FH) / 2, 1, 1, 1, 1, D.FONT)
        self:drawTextRight(status, self.width - PAD - D.ICON - 8, y + (ROW_H - D.FH) / 2, 0.7, 0.7, 0.7, 1, D.FONT)
        local blocker = t.open and CC.joinBlocker(t)
        local tip = blocker and CC.text("Err_" .. blocker) or CC.text("Join")
        D.iconButton(self, self.width - PAD - D.ICON, y + 2, "sit", tip, W.join, t, t.open and not blocker)
        y = y + ROW_H
    end
    D.iconButton(self, self.width - PAD - D.ICON, y + 2, "refresh", CC.text("Refresh"), function() CC.send("list") end)
    y = y + ROW_H + 6

    y = drawHeader(self, y, CC.text("NewTable"))
    local x = PAD
    self:drawText(CC.text("Mode"), x, y + (D.ICON - D.FH) / 2, 0.85, 0.85, 0.85, 1, D.FONT)
    x = x + D.textW(CC.text("Mode")) + 8
    for _, n in ipairs({ 2, 4 }) do
        local label = modeLabel(n)
        local w = D.textW(label) + 12
        local sel = W.pending.n == n
        local hover = D.isHover(self, x, y, w, D.ICON)
        self:drawRect(x, y, w, D.ICON, sel and 0.9 or (hover and 0.6 or 0.35), sel and 0.25 or 0, sel and 0.5 or 0, sel and 0.3 or 0)
        self:drawRectBorder(x, y, w, D.ICON, 0.45, 1, 1, 1)
        self:drawTextCentre(label, x + w / 2, y + (D.ICON - D.FH) / 2, 1, 1, 1, 1, D.FONT)
        D.addHit(self, x, y, w, D.ICON, function() W.pending.n = n end, nil, CC.text("Mode_" .. n))
        x = x + w + 4
    end
    x = x + 12
    local tickHover = D.isHover(self, x, y, D.ICON, D.ICON)
    self:drawRect(x, y, D.ICON, D.ICON, tickHover and 0.6 or 0.35, 0, 0, 0)
    self:drawRectBorder(x, y, D.ICON, D.ICON, 0.45, 1, 1, 1)
    if W.pending.fillBots then
        self:drawTextureScaled(D.tex("icon_confirm"), x + 2, y + 2, D.ICON - 4, D.ICON - 4, 1, 0.5, 1, 0.5)
    end
    D.addHit(self, x, y, D.ICON + D.textW(CC.text("FillBots")) + 6, D.ICON,
        function() W.pending.fillBots = not W.pending.fillBots end, nil, CC.text("FillBotsTip"))
    self:drawText(CC.text("FillBots"), x + D.ICON + 4, y + (D.ICON - D.FH) / 2, 0.85, 0.85, 0.85, 1, D.FONT)
    y = y + D.ICON + 6

    x = PAD
    self:drawText(CC.text("Preset"), x, y + (D.ICON - D.FH) / 2, 0.85, 0.85, 0.85, 1, D.FONT)
    x = x + D.textW(CC.text("Preset")) + 8
    x = x + D.iconButton(self, x, y, "prev", CC.text("PresetTip"), function(s) s:cyclePreset(-1) end) + 4
    local pw = math.floor(170 * D.S)
    self:drawTextCentre(CC.presetName(W.pending.rules.preset), x + pw / 2, y + (D.ICON - D.FH) / 2, 1, 0.9, 0.5, 1, D.FONT)
    x = x + pw + 4
    x = x + D.iconButton(self, x, y, "next", CC.text("PresetTip"), function(s) s:cyclePreset(1) end) + 4
    D.iconButton(self, x, y, "rules", CC.text("EditRules"), W.openRules)
    y = y + D.ICON + 8

    local need = N.sandbox("RequiredDecks", 2)
    local have = N.countDecks(getPlayer())
    local enough = have >= need
    local decks = CC.text("Decks", tostring(have), tostring(need))
    local ty = y + (D.ICON - D.FH) / 2
    if enough then
        self:drawText(decks, PAD, ty, 0.6, 0.9, 0.6, 1, D.FONT)
    else
        self:drawText(decks, PAD, ty, 0.95, 0.5, 0.45, 1, D.FONT)
    end
    local seatErr
    if Canastra.Seating.required() then
        local seat, reason = CC.mySeat()
        seatErr = not seat and reason or nil
        local sx = PAD + D.textW(decks) + 12
        local text = CC.text(seat and "SeatOk" or ("Seat_" .. reason))
        local icon = D.FH
        self:drawTextureScaled(D.tex("icon_sit"), sx, ty, icon, icon, 1, seat and 0.6 or 0.95, seat and 0.9 or 0.5, seat and 0.6 or 0.45)
        D.addHit(self, sx, ty, icon, icon, nil, nil, CC.text("SeatTip"))
        self:drawText(text, sx + icon + 3, ty, seat and 0.6 or 0.95, seat and 0.9 or 0.5, seat and 0.6 or 0.45, 1, D.FONT)
    end
    local ok = enough and not seatErr
    local tip = not enough and CC.text("Err_NeedDecks") or (seatErr and CC.text("Err_" .. seatErr)) or ""
    local label = CC.text("Create")
    local bw = D.ICON + D.textW(label) + 6
    D.labelButton(self, self.width - PAD - bw, y, "meld", label, tip, W.create, nil, ok)
    return y + D.ICON + 6
end

function W:renderSeated(y)
    local info = CC.info
    local isHost = CC.isHost()
    y = drawHeader(self, y, CC.text("TableOf", info.hostName) .. "  " .. modeLabel(info.n) .. "  " .. CC.presetName(info.rules.preset))
    for i = 1, info.n do
        local seat = info.seats[i]
        local team = ((i - 1) % 2) + 1
        local col = team == 1 and D.COLOR_US or D.COLOR_THEM
        local hover = D.isHover(self, PAD, y, self.width - PAD * 2, ROW_H)
        if hover then self:drawRect(PAD, y, self.width - PAD * 2, ROW_H, 0.15, 1, 1, 1) end
        local teamLabel = info.n == 4 and CC.text("Team_" .. team) or ""
        self:drawText(tostring(i) .. ".", PAD + 2, y + (ROW_H - D.FH) / 2, 0.7, 0.7, 0.7, 1, D.FONT)
        local name
        if seat.kind == "empty" then
            name = CC.text("EmptySeat")
        else
            name = seat.name
            if seat.key ~= "" and seat.key == info.hostKey then name = name .. " " .. CC.text("HostMark") end
        end
        local alpha = seat.kind == "empty" and 0.5 or 1
        self:drawText(name, PAD + 24, y + (ROW_H - D.FH) / 2, col.r, col.g, col.b, alpha, D.FONT)
        if seat.kind == "bot" then
            self:drawTextureScaled(D.tex("icon_bot"), PAD + 28 + D.textW(name), y + (ROW_H - D.FH) / 2, D.FH, D.FH, 0.8, 1, 1, 1)
        end
        self:drawText(teamLabel, math.floor(self.width * 0.55), y + (ROW_H - D.FH) / 2, col.r, col.g, col.b, 0.7, D.FONT)

        local bx = self.width - PAD - D.ICON
        local by = y + 2
        if seat.kind == "empty" then
            if isHost and N.sandbox("AllowBots", true) then
                D.iconButton(self, bx, by, "bot", CC.text("AddBot"), function() CC.send("addBot", { seat = i }) end)
                bx = bx - D.ICON - 4
            end
            D.iconButton(self, bx, by, "swap", CC.text("MoveHere"), function() CC.send("moveSeat", { seat = i }) end)
        elseif isHost and seat.key ~= info.hostKey then
            D.iconButton(self, bx, by, "remove", CC.text("Kick"), function() CC.send("kick", { seat = i }) end)
            if seat.kind == "bot" then
                bx = bx - D.ICON - 4
                D.iconButton(self, bx, by, "swap", CC.text("MoveHere"), function() CC.send("moveSeat", { seat = i }) end)
            end
        end
        y = y + ROW_H
    end
    y = y + 4

    y = drawHeader(self, y, CC.text("RulesSummary"))
    local rules = info.rules
    local lines = {
        CC.ruleLabel("pileTake") .. ": " .. CC.ruleValue("pileTake", rules.pileTake),
        CC.ruleLabel("deadPiles") .. ": " .. CC.ruleValue("deadPiles", rules.deadPiles)
            .. "   " .. CC.ruleLabel("goOutRequires") .. ": " .. CC.ruleValue("goOutRequires", rules.goOutRequires),
        CC.ruleLabel("targetScore") .. ": " .. CC.ruleValue("targetScore", rules.targetScore),
    }
    for _, l in ipairs(lines) do
        self:drawText(l, PAD + 4, y, 0.85, 0.85, 0.85, 1, D.FONT)
        y = y + D.FH + 1
    end
    y = y + 6

    local by = y
    local x = PAD
    x = x + D.labelButton(self, x, by, "leave", CC.text("Leave"), nil, function() CC.send("leave") end) + 6
    x = x + D.labelButton(self, x, by, "rules", CC.text(isHost and "EditRules" or "ViewRules"), nil, W.openRules) + 6
    if isHost then
        local full = true
        for i = 1, info.n do
            if info.seats[i].kind == "empty" then full = false end
        end
        local label = CC.text("Start")
        local bw = D.ICON + D.textW(label) + 6
        D.labelButton(self, self.width - PAD - bw, by, "start", label, full and "" or CC.text("Err_SeatsEmpty"),
            function() CC.send("start", { decks = N.countDecks(getPlayer()) }) end, nil, full)
    else
        self:drawTextRight(CC.text("WaitingHost"), self.width - PAD, by + (D.ICON - D.FH) / 2, 0.7, 0.7, 0.7, 1, D.FONT)
    end
    return by + D.ICON + 6
end

function W:render()
    ISCollapsableWindow.render(self)
    if self.isCollapsed then return end
    D.beginHits(self)
    local y = self:titleBarHeight() + PAD
    if CC.info and CC.info.status == "lobby" then
        y = self:renderSeated(y)
    elseif CC.info then
        self:drawText(CC.text("InGame"), PAD, y, 1, 1, 1, 1, D.FONT)
        D.labelButton(self, PAD, y + D.FH + 8, "start", CC.text("OpenTable"), nil, function(s)
            CanastraGameWindow.open()
            s:close()
        end)
        y = y + D.FH + 8 + D.ICON + 6
    else
        y = self:renderBrowse(y)
    end
    local m = CC.currentMessage()
    if m then
        self:drawText(m.text, PAD, y, m.error and 1 or 0.8, m.error and 0.45 or 0.9, m.error and 0.4 or 0.6, 1, D.FONT)
    end
    local needed = math.floor(y + D.FH + PAD)
    if math.abs(self.height - needed) > 1 then self:setHeight(needed) end
    D.drawTooltip(self)
end

function W:onMouseDown(x, y)
    if D.click(self, x, y) then return true end
    return ISCollapsableWindow.onMouseDown(self, x, y)
end
