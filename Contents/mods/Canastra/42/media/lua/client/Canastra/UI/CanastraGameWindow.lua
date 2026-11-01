require "ISUI/ISCollapsableWindow"
require "Canastra/CanastraClient"
require "Canastra/UI/CanastraDraw"
require "Canastra/UI/CanastraRulesWindow"

CanastraGameWindow = ISCollapsableWindow:derive("CanastraGameWindow")
local W = CanastraGameWindow
local D = CanastraDraw
local C = Canastra.Cards
local M = Canastra.Melds
local CC = CanastraClient

local PAD = 8
local GAP = 8
local WIDTH = math.floor(840 * D.S)
local THEM_ROWS = 2
local US_ROWS = 3
local LEAVE_CONFIRM_MS = 3000
local DOUBLE_CLICK_MS = 350

function W.open()
    if W.instance then
        W.instance:setVisible(true)
        W.instance:bringToTop()
        W.instance:refresh()
        return W.instance
    end
    local win = W:new(0, 0, WIDTH, W.computeHeight())
    win:initialise()
    win:addToUIManager()
    D.centerOnScreen(win)
    W.instance = win
    win:refresh()
    return win
end

function W.computeHeight()
    local th = ISCollapsableWindow.TitleBarHeight()
    local meldRow = D.MINI_H + 6
    return th + PAD
        + D.FH + 6                     -- score strip
        + D.FH + 8                     -- players strip
        + D.FH + THEM_ROWS * meldRow   -- their melds
        + D.HAND_H + D.FH + 10         -- table centre
        + D.FH + US_ROWS * meldRow     -- our melds
        + D.ICON + 8                   -- status + actions
        + D.HAND_H + 14 + PAD          -- hand
end

function W:new(x, y, w, h)
    local o = ISCollapsableWindow.new(self, x, y, w, h)
    o.title = CC.text("GameTitle")
    o.resizable = false
    o.backgroundColor = { r = 0.04, g = 0.2, b = 0.1, a = 0.97 }
    o.order = {}
    o.selected = {}
    o.staged = {}
    o.targetMeld = nil
    D.loadSettings()
    o.sortMode = D.sortMode
    o.leaveArmed = 0
    o.lastClick = { id = nil, t = 0 }
    return o
end

function W:close()
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    if W.instance == self then W.instance = nil end
end

-- ------------------------------------------------------------------ state

local function stagedSet(self)
    local set = {}
    for _, m in ipairs(self.staged) do
        for _, id in ipairs(m) do set[id] = true end
    end
    return set
end

function W:selectedList()
    local list = {}
    for _, id in ipairs(self.order) do
        if self.selected[id] then list[#list + 1] = id end
    end
    return list
end

function W:clearSelection()
    self.selected = {}
    self.staged = {}
    self.targetMeld = nil
end

function W:refresh()
    local v = CC.view
    if not v then return end
    local inHand = {}
    for _, id in ipairs(v.hand) do inHand[id] = true end
    local order, seen = {}, {}
    for _, id in ipairs(self.order) do
        if inHand[id] then
            order[#order + 1] = id
            seen[id] = true
        end
    end
    local fresh = {}
    for _, id in ipairs(v.hand) do
        if not seen[id] then fresh[#fresh + 1] = id end
    end
    local firstDeal = #order == 0
    for _, id in ipairs(fresh) do order[#order + 1] = id end
    if self.sortMode == "rank" then C.sortByRank(order) else C.sortBySuit(order) end
    self.order = order
    local myTurn = v.turn == v.you and (v.phase == "draw" or v.phase == "play")
    -- Cards gained this turn stay highlighted until the turn ends.
    local previous = myTurn and self.fresh or {}
    self.fresh = {}
    for id in pairs(previous) do
        if inHand[id] then self.fresh[id] = true end
    end
    if not firstDeal then
        for _, id in ipairs(fresh) do self.fresh[id] = true end
    end
    for id in pairs(self.selected) do
        if not inHand[id] then self.selected[id] = nil end
    end
    if not myTurn then
        self.staged = {}
        self.targetMeld = nil
    end
    if v.phase ~= "draw" then self.targetMeld = nil end
    for i = #self.staged, 1, -1 do
        for _, id in ipairs(self.staged[i]) do
            if not inHand[id] then
                table.remove(self.staged, i)
                break
            end
        end
    end
end

function W:sort(mode)
    self.sortMode = mode
    D.setSortMode(mode)
    if mode == "rank" then C.sortByRank(self.order) else C.sortBySuit(self.order) end
end

local function myTeam(v)
    return v.teamOf[v.you]
end

local function isMyTurn(v)
    return v and v.turn == v.you and (v.phase == "draw" or v.phase == "play")
end

local function hint(key, ...)
    CC.showMessage(CC.text(key, ...), false)
end

-- ------------------------------------------------------------------ actions

function W:toggleCard(id)
    local now = getTimestampMs()
    local v = CC.view
    if self.lastClick.id == id and now - self.lastClick.t < DOUBLE_CLICK_MS then
        self.lastClick.id = nil
        if isMyTurn(v) and v.phase == "play" then
            self.selected = {}
            CC.action({ type = "discard", card = id })
            return
        end
    end
    self.lastClick.id, self.lastClick.t = id, now
    self.selected[id] = not self.selected[id] or nil
end

function W:clickStock()
    local v = CC.view
    if not isMyTurn(v) then return hint("Hint_NotYourTurn") end
    if v.phase ~= "draw" then return hint("Hint_AlreadyDrew") end
    CC.action({ type = "draw" })
end

function W:clickPile()
    local v = CC.view
    if not isMyTurn(v) then return hint("Hint_NotYourTurn") end
    local sel = self:selectedList()
    if v.phase == "play" then
        if #sel == 1 then
            self.selected = {}
            CC.action({ type = "discard", card = sel[1] })
        else
            hint("Hint_SelectOneDiscard")
        end
        return
    end
    local rules = v.rules
    if rules.pileTake == "free" and not rules.pileFreeze then
        self:clearSelection()
        CC.action({ type = "takePile" })
        return
    end
    if self.targetMeld then
        CC.action({ type = "takePile", addTo = self.targetMeld, cards = sel })
    elseif #sel >= 1 then
        local melds = { { cards = sel } }
        for _, m in ipairs(self.staged) do melds[#melds + 1] = { cards = m } end
        CC.action({ type = "takePile", melds = melds })
    else
        return hint("Hint_PileNeedsMeld")
    end
    self:clearSelection()
end

function W:clickOwnMeld(meldId)
    local v = CC.view
    if not isMyTurn(v) then return end
    if v.phase == "draw" then
        if v.rules.pileTake ~= "free" or v.rules.pileFreeze then
            self.targetMeld = self.targetMeld ~= meldId and meldId or nil
        end
        return
    end
    local sel = self:selectedList()
    if #sel == 0 then return hint("Hint_SelectCards") end
    self.selected = {}
    CC.action({ type = "meld", adds = { { meld = meldId, cards = sel } } })
end

local function stagedPoints(self, rules)
    local pts = 0
    for _, m in ipairs(self.staged) do pts = pts + M.points(m, rules) end
    return pts
end

function W:newMeld()
    local v = CC.view
    if not isMyTurn(v) then return hint("Hint_NotYourTurn") end
    if v.phase ~= "play" then return hint("Hint_DrawFirst") end
    local sel = self:selectedList()
    if #sel < 3 then return hint("Hint_SelectThree") end
    if not M.analyze(sel, v.rules) then return CC.showMessage(CC.text("Err_InvalidMeld"), true) end
    local min = v.initialMin or 0
    if min > 0 then
        self.staged[#self.staged + 1] = sel
        self.selected = {}
        local pts = stagedPoints(self, v.rules)
        if pts >= min then
            self:confirmStaged()
        else
            hint("Hint_Staged", tostring(pts), tostring(min))
        end
        return
    end
    self.selected = {}
    CC.action({ type = "meld", melds = { { cards = sel } } })
end

function W:confirmStaged()
    if #self.staged == 0 then return end
    local melds = {}
    for _, m in ipairs(self.staged) do melds[#melds + 1] = { cards = m } end
    self.staged = {}
    CC.action({ type = "meld", melds = melds })
end

function W:discardSelected()
    local v = CC.view
    if not isMyTurn(v) or v.phase ~= "play" then return hint("Hint_NotYourTurn") end
    local sel = self:selectedList()
    if #sel ~= 1 then return hint("Hint_SelectOneDiscard") end
    self.selected = {}
    CC.action({ type = "discard", card = sel[1] })
end

function W:redraw()
    self.selected = {}
    CC.action({ type = "redraw" })
end

function W:leave()
    local now = getTimestampMs()
    if now - self.leaveArmed < LEAVE_CONFIRM_MS then
        CC.send("leave")
        self:close()
    else
        self.leaveArmed = now
        hint("Hint_ConfirmLeave")
    end
end

-- ------------------------------------------------------------------ layout helpers

-- Flow layout for a team's melds; shrinks the card step until everything fits in maxRows.
local function layoutMelds(melds, x0, y0, width, maxRows)
    local rowH = D.MINI_H + 6
    local steps = { D.MINI_STEP, math.floor(D.MINI_STEP * 0.8), math.floor(D.MINI_STEP * 0.65) }
    local placed
    for _, step in ipairs(steps) do
        placed = {}
        local x, row = x0, 0
        for _, m in ipairs(melds) do
            local w = D.MINI_W + (#m.cards - 1) * step
            if x > x0 and x + w > x0 + width then
                row = row + 1
                x = x0
            end
            placed[#placed + 1] = { meld = m, x = x, y = y0 + row * rowH, w = w, step = step }
            x = x + w + GAP
        end
        if row < maxRows then return placed end
    end
    return placed
end

local function meldTooltip(m)
    local kind = m.kind == "seq" and CC.text("Seq") or CC.text("Set")
    local s = kind .. " (" .. #m.cards .. ")"
    if m.canasta then
        s = s .. " - " .. CC.text(m.clean and "CleanCanasta" or "DirtyCanasta")
    end
    return s
end

function W:drawMeldArea(team, x, y, width, rows, label, isOurs)
    local v = CC.view
    local col = isOurs and D.COLOR_US or D.COLOR_THEM
    self:drawText(label, x, y, col.r, col.g, col.b, 0.8, D.FONT)
    local r3 = v.rules.redThrees and v.red3[team] or {}
    if #r3 > 0 then
        local s = D.FH - 2
        local tw = D.textW("3")
        local r3Label = CC.text("Res_Red3") .. ":"
        local lw = D.textW(r3Label)
        local rw = lw + 4 + #r3 * (tw + s + 4)
        local rx = x + width - rw
        self:drawText(r3Label, rx, y, 0.8, 0.8, 0.8, 0.9, D.FONT)
        rx = rx + lw + 4
        for _, id in ipairs(r3) do
            self:drawText("3", rx, y, 0.95, 0.35, 0.35, 1, D.FONT)
            D.drawSuit(self, id, rx + tw + 1, y + 1, s)
            rx = rx + tw + s + 4
        end
        D.addHit(self, x + width - rw, y, rw, D.FH, nil, nil, getText("IGUI_Canastra_RuleTip_redThrees"))
    end
    y = y + D.FH
    local areaH = rows * (D.MINI_H + 6)
    self:drawRect(x, y, width, areaH, 0.18, 0, 0, 0)
    local canAct = isOurs and isMyTurn(v)
    if canAct and v.phase == "play" then
        D.addHit(self, x, y, width, areaH, W.newMeld, nil, CC.text("NewMeldTip"))
    end
    local placed = layoutMelds(v.melds[team] or {}, x + 4, y + 3, width - 8, rows)
    for _, p in ipairs(placed) do
        local m = p.meld
        local target = isOurs and self.targetMeld == m.id
        local hover = D.isHover(self, p.x - 2, p.y - 2, p.w + 4, D.MINI_H + 4)
        if target or (hover and canAct) then
            self:drawRect(p.x - 2, p.y - 2, p.w + 4, D.MINI_H + 4, 0.5, 0.9, 0.8, 0.2)
        end
        for i, id in ipairs(m.cards) do
            D.drawCard(self, id, p.x + (i - 1) * p.step, p.y, D.MINI_W, D.MINI_H, { mini = true })
        end
        if m.canasta then
            local c = m.clean and D.COLOR_GOLD or D.COLOR_DIM
            self:drawRect(p.x, p.y + D.MINI_H + 1, p.w, 3, 1, c.r, c.g, c.b)
        end
        D.addHit(self, p.x - 2, p.y - 2, p.w + 4, D.MINI_H + 4,
            isOurs and canAct and W.clickOwnMeld or nil, m.id, meldTooltip(m))
    end
    return y + areaH
end

local function badge(self, x, y, seat)
    local v = CC.view
    local team = v.teamOf[seat]
    local col = team == myTeam(v) and D.COLOR_US or D.COLOR_THEM
    local name = CC.seatName(seat)
    local isBot = CC.info.seats[seat] and CC.info.seats[seat].kind == "bot"
    local text = name .. "  " .. tostring(v.counts[seat] or 0)
    local w = D.textW(text) + D.FH + 14 + (isBot and D.FH + 2 or 0)
    local h = D.FH + 4
    local turn = v.turn == seat and (v.phase == "draw" or v.phase == "play")
    self:drawRect(x, y, w, h, turn and 0.85 or 0.4, turn and 0.45 or 0, turn and 0.38 or 0, turn and 0.05 or 0)
    self:drawRectBorder(x, y, w, h, turn and 1 or 0.3, 1, turn and 0.85 or 1, turn and 0.3 or 1)
    local tx = x + 4
    if isBot then
        self:drawTextureScaled(D.tex("icon_bot"), tx, y + 2, D.FH, D.FH, 0.9, 1, 1, 1)
        tx = tx + D.FH + 2
    end
    self:drawText(name, tx, y + 2, col.r, col.g, col.b, 1, D.FONT)
    tx = tx + D.textW(name) + 6
    self:drawTextureScaled(D.cardBackTex(D.FH), tx, y + 2, math.floor(D.FH * 0.7), D.FH, 1, 1, 1, 1)
    self:drawText(tostring(v.counts[seat] or 0), tx + math.floor(D.FH * 0.7) + 3, y + 2, 1, 1, 1, 1, D.FONT)
    return w
end

-- ------------------------------------------------------------------ render sections

function W:renderScores(y)
    local v = CC.view
    local us, them = myTeam(v), myTeam(v) == 1 and 2 or 1
    local x = PAD
    local text = CC.text("Us") .. " " .. tostring(v.scores[us])
    self:drawText(text, x, y, D.COLOR_US.r, D.COLOR_US.g, D.COLOR_US.b, 1, D.FONT)
    x = x + D.textW(text) + 14
    text = CC.text("Them") .. " " .. tostring(v.scores[them])
    self:drawText(text, x, y, D.COLOR_THEM.r, D.COLOR_THEM.g, D.COLOR_THEM.b, 1, D.FONT)
    x = x + D.textW(text) + 14
    text = CC.text("ScoreInfo", tostring(v.rules.targetScore), tostring(v.round), CC.presetName(v.rules.preset))
    self:drawText(text, x, y, 0.75, 0.75, 0.75, 1, D.FONT)

    local bx = self.width - PAD - D.ICON
    D.iconButton(self, bx, y - 2, "leave", CC.text("LeaveTip"), W.leave)
    bx = bx - D.ICON - 4
    D.iconButton(self, bx, y - 2, "rules", CC.text("ViewRules"), function()
        CanastraRulesWindow.open(Canastra.Rules.sanitize(v.rules), false, nil)
    end)
    bx = bx - D.ICON - 4
    D.loadSettings()
    D.iconButton(self, bx, y - 2, "colors", CC.text(D.fourColor and "FourColorOn" or "FourColorOff"), function()
        D.setFourColor(not D.fourColor)
    end)
    if D.fourColor then
        self:drawRectBorder(bx, y - 2, D.ICON, D.ICON, 1, D.COLOR_GOLD.r, D.COLOR_GOLD.g, D.COLOR_GOLD.b)
    end
    return y + D.FH + 6
end

function W:renderPlayers(y)
    local v = CC.view
    local x = PAD
    for k = 1, v.n do
        local seat = ((v.you - 1 + k) % v.n) + 1
        x = x + badge(self, x, y, seat) + 6
    end
    return y + D.FH + 8
end

function W:renderCentre(y)
    local v = CC.view
    local x = PAD
    local h = D.HAND_H
    local myT = isMyTurn(v)

    -- stock
    if v.stock > 0 then
        local hover = myT and v.phase == "draw" and D.isHover(self, x, y, D.HAND_W, h)
        D.drawCard(self, nil, x, y, D.HAND_W, h, { back = true })
        if hover then self:drawRectBorder(x, y, D.HAND_W, h, 1, 0.3, 0.9, 0.3) end
    else
        self:drawRectBorder(x, y, D.HAND_W, h, 0.4, 1, 1, 1)
    end
    self:drawTextCentre(CC.text("Stock", tostring(v.stock)), x + D.HAND_W / 2, y + h + 1, 0.8, 0.8, 0.8, 1, D.FONT)
    D.addHit(self, x, y, D.HAND_W, h, W.clickStock, nil, CC.text("StockTip"))
    x = x + D.HAND_W + GAP * 2

    -- discard pile: fanned when visible, otherwise only the top card
    local pile = v.pile or {}
    local maxShow = 10
    local first = math.max(1, #pile - maxShow + 1)
    local step = D.MINI_STEP
    local pileW = D.HAND_W + math.max(0, (#pile - first)) * step
    if #pile == 0 then
        self:drawRectBorder(x, y, D.HAND_W, h, 0.4, 1, 1, 1)
        pileW = D.HAND_W
    else
        for i = first, #pile do
            D.drawCard(self, pile[i], x + (i - first) * step, y, D.HAND_W, h, { mini = i < #pile })
        end
    end
    if v.pileLocked then
        self:drawRectBorder(x - 2, y - 2, pileW + 4, h + 4, 1, 0.95, 0.3, 0.3)
    elseif v.pileFrozen then
        self:drawRectBorder(x - 2, y - 2, pileW + 4, h + 4, 1, 0.4, 0.7, 1)
    end
    local pileHover = myT and D.isHover(self, x, y, pileW, h)
    if pileHover then self:drawRectBorder(x, y, pileW, h, 1, 0.3, 0.9, 0.3) end
    local pileLabel = CC.text("Pile", tostring(v.pileCount))
    if v.pileLocked then pileLabel = pileLabel .. " " .. CC.text("Locked")
    elseif v.pileFrozen then pileLabel = pileLabel .. " " .. CC.text("Frozen") end
    self:drawText(pileLabel, x, y + h + 1, 0.8, 0.8, 0.8, 1, D.FONT)
    local tip = v.phase == "play" and CC.text("PileDiscardTip") or CC.text("PileTakeTip_" .. v.rules.pileTake)
    D.addHit(self, x, y, pileW, h, W.clickPile, nil, tip)
    x = x + math.max(pileW, D.textW(pileLabel)) + GAP * 2

    -- dead piles
    local dx = x
    for i, d in ipairs(v.dead or {}) do
        local label
        if d.owner == 0 then label = CC.text("DeadShared")
        elseif d.owner == myTeam(v) then label = CC.text("DeadOurs")
        else label = CC.text("DeadTheirs") end
        local state = CC.text("DeadState_" .. d.state)
        local cy = y + (i - 1) * (D.FH * 2 + 4)
        if d.state == "open" then
            self:drawTextureScaled(D.cardBackTex(D.FH * 1.3), dx, cy, math.floor(D.FH * 1.3), math.floor(D.FH * 1.8), 1, 1, 1, 1)
        else
            self:drawRectBorder(dx, cy, math.floor(D.FH * 1.3), math.floor(D.FH * 1.8), 0.4, 1, 1, 1)
        end
        self:drawText(label, dx + D.FH * 1.3 + 4, cy, 0.9, 0.9, 0.9, 1, D.FONT)
        self:drawText(state, dx + D.FH * 1.3 + 4, cy + D.FH, 0.65, 0.65, 0.65, 1, D.FONT)
    end
    x = dx + math.floor(150 * D.S)

    -- action log
    local logW = self.width - PAD - x
    self:drawRect(x, y, logW, h + D.FH, 0.25, 0, 0, 0)
    local lines = math.floor((h + D.FH - 4) / (D.FH + 1))
    local log = v.log or {}
    local start = math.max(1, #log - lines + 1)
    local ly = y + 2
    for i = start, #log do
        local a = i == #log and 1 or 0.7
        self:drawText(CC.formatLog(log[i]), x + 4, ly, a, a, a, 1, D.FONT)
        ly = ly + D.FH + 1
    end
    return y + h + D.FH + 10
end

function W:statusText()
    local v = CC.view
    local m = CC.currentMessage()
    if m then return m.text, m.error end
    if v.phase == "roundOver" or v.phase == "matchOver" then return CC.text("Status_RoundOver"), false end
    if not isMyTurn(v) then return CC.text("Status_Waiting", CC.seatName(v.turn)), false end
    if v.phase == "draw" then
        if v.rules.pileTake == "free" and not v.rules.pileFreeze then return CC.text("Status_DrawFree"), false end
        return CC.text("Status_DrawClosed"), false
    end
    local s = CC.text("Status_Play")
    if (v.initialMin or 0) > 0 then s = s .. " " .. CC.text("Status_InitialMin", tostring(v.initialMin)) end
    return s, false
end

function W:renderActions(y)
    local v = CC.view
    local myT = isMyTurn(v)
    local play = myT and v.phase == "play"
    local sel = self:selectedList()
    local x = PAD
    x = x + D.iconButton(self, x, y, "meld", CC.text("NewMeldTip"), W.newMeld, nil, play and #sel >= 3) + 4
    x = x + D.iconButton(self, x, y, "discard", CC.text("DiscardTip"), W.discardSelected, nil, play and #sel == 1) + 4
    x = x + D.iconButton(self, x, y, "clear", CC.text("ClearTip"), W.clearSelection, nil, #sel > 0 or #self.staged > 0 or self.targetMeld ~= nil) + 10
    for _, mode in ipairs({ "suit", "rank" }) do
        D.iconButton(self, x, y, "sort" .. mode, CC.text(mode == "suit" and "SortSuitTip" or "SortRankTip"),
            function(s) s:sort(mode) end)
        if self.sortMode == mode then
            self:drawRectBorder(x, y, D.ICON, D.ICON, 1, D.COLOR_GOLD.r, D.COLOR_GOLD.g, D.COLOR_GOLD.b)
        end
        x = x + D.ICON + (mode == "suit" and 4 or 10)
    end
    if play and v.redrawCard then
        x = x + D.labelButton(self, x, y, "swap", CC.text("Redraw"), CC.text("RedrawTip", CC.cardName(v.redrawCard)), W.redraw) + 10
    end
    if #self.staged > 0 then
        local pts = stagedPoints(self, v.rules)
        local label = CC.text("Staged", tostring(#self.staged), tostring(pts), tostring(v.initialMin or 0))
        x = x + D.labelButton(self, x, y, "confirm", label, CC.text("StagedTip"), W.confirmStaged, nil, play) + 10
    end
    local text, isErr = self:statusText()
    text = D.fitText(text, self.width - PAD - x)
    if isErr then
        self:drawText(text, x, y + (D.ICON - D.FH) / 2, 1, 0.45, 0.4, 1, D.FONT)
    else
        self:drawText(text, x, y + (D.ICON - D.FH) / 2, 0.95, 0.95, 0.8, 1, D.FONT)
    end
    return y + D.ICON + 8
end

function W:renderHand(y)
    local v = CC.view
    local staged = stagedSet(self)
    local cards = {}
    for _, id in ipairs(self.order) do
        if not staged[id] then cards[#cards + 1] = id end
    end
    local n = #cards
    local avail = self.width - PAD * 2
    local step = D.HAND_W + 4
    if n > 1 and (n - 1) * step + D.HAND_W > avail then
        step = math.floor((avail - D.HAND_W) / (n - 1))
    end
    local raise = math.floor(10 * D.S)
    local baseY = y + raise
    for i, id in ipairs(cards) do
        local x = PAD + (i - 1) * step
        local sel = self.selected[id]
        local fresh = self.fresh and self.fresh[id]
        local cy = baseY
        if sel then cy = y elseif fresh then cy = baseY - math.floor(raise / 2) end
        D.drawCard(self, id, x, cy, D.HAND_W, D.HAND_H, { selected = sel, fresh = fresh })
        if fresh then
            local barW = i == n and D.HAND_W or math.min(step, D.HAND_W)
            self:drawRect(x, cy - 4, barW, 3, 1, 0.35, 0.95, 0.35)
        end
        local hitW = i == n and D.HAND_W or math.min(step, D.HAND_W)
        D.addHit(self, x, cy, hitW, D.HAND_H, function(s, cid) s:toggleCard(cid) end, id, nil)
    end
    return y + D.HAND_H + raise + 4
end

function W:renderResult()
    local v = CC.view
    local res = v.result
    if not res then return end
    local us, them = myTeam(v), myTeam(v) == 1 and 2 or 1
    local rows = {
        { "Res_Melds", "melds" }, { "Res_Canastas", "bonus" }, { "Res_GoOut", "goOut" },
        { "Res_Hand", "hand" }, { "Res_Dead", "dead" },
    }
    if v.rules.redThrees then rows[#rows + 1] = { "Res_Red3", "red3" } end
    rows[#rows + 1] = { "Res_Total", "total" }
    local lineH = D.FH + 2
    local w = math.floor(360 * D.S)
    local h = PAD * 2 + lineH * (#rows + 4) + D.ICON + 6
    local x = (self.width - w) / 2
    local y = (self.height - h) / 2
    self:drawRect(x, y, w, h, 0.95, 0.03, 0.08, 0.05)
    self:drawRectBorder(x, y, w, h, 0.8, D.COLOR_GOLD.r, D.COLOR_GOLD.g, D.COLOR_GOLD.b)
    D.addHit(self, x, y, w, h, nil, nil, nil)
    local cy = y + PAD
    local title
    if v.phase == "matchOver" then
        title = CC.text(v.winner == us and "MatchWon" or "MatchLost")
    elseif res.goOutTeam == us then
        title = CC.text("RoundWentOutUs")
    elseif res.goOutTeam == them then
        title = CC.text("RoundWentOutThem")
    else
        title = CC.text("RoundStockEnded")
    end
    self:drawTextCentre(title, x + w / 2, cy, D.COLOR_GOLD.r, D.COLOR_GOLD.g, D.COLOR_GOLD.b, 1, D.FONT)
    cy = cy + lineH + 4
    local c1, c2 = x + w * 0.62, x + w - PAD
    self:drawTextRight(CC.text("Us"), c1, cy, D.COLOR_US.r, D.COLOR_US.g, D.COLOR_US.b, 1, D.FONT)
    self:drawTextRight(CC.text("Them"), c2, cy, D.COLOR_THEM.r, D.COLOR_THEM.g, D.COLOR_THEM.b, 1, D.FONT)
    cy = cy + lineH
    for _, r in ipairs(rows) do
        local isTotal = r[2] == "total"
        if isTotal then self:drawRect(x + PAD, cy - 1, w - PAD * 2, 1, 0.4, 1, 1, 1) end
        local a = isTotal and 1 or 0.85
        self:drawText(CC.text(r[1]), x + PAD, cy, a, a, a, 1, D.FONT)
        self:drawTextRight(tostring(res.teams[us][r[2]] or 0), c1, cy, a, a, a, 1, D.FONT)
        self:drawTextRight(tostring(res.teams[them][r[2]] or 0), c2, cy, a, a, a, 1, D.FONT)
        cy = cy + lineH
    end
    self:drawText(CC.text("Res_Score"), x + PAD, cy + 2, 1, 1, 1, 1, D.FONT)
    self:drawTextRight(tostring(v.scores[us]), c1, cy + 2, D.COLOR_US.r, D.COLOR_US.g, D.COLOR_US.b, 1, D.FONT)
    self:drawTextRight(tostring(v.scores[them]), c2, cy + 2, D.COLOR_THEM.r, D.COLOR_THEM.g, D.COLOR_THEM.b, 1, D.FONT)
    cy = cy + lineH + 8

    if CC.isHost() then
        local label = CC.text(v.phase == "matchOver" and "NewMatch" or "NextRound")
        local bw = D.ICON + D.textW(label) + 6
        local bx = x + w - PAD - bw
        D.labelButton(self, bx, cy, "nextround", label, nil, function() CC.send("nextRound") end)
        if v.phase == "matchOver" then
            D.labelButton(self, x + PAD, cy, "back", CC.text("BackToLobby"), nil, function() CC.send("backToLobby") end)
        end
    else
        self:drawTextCentre(CC.text("WaitingHost"), x + w / 2, cy + (D.ICON - D.FH) / 2, 0.7, 0.7, 0.7, 1, D.FONT)
    end
end

function W:render()
    ISCollapsableWindow.render(self)
    if self.isCollapsed then return end
    D.beginHits(self)
    local v = CC.view
    if not v or not CC.info then
        self:drawText(CC.text("NoGame"), PAD, self:titleBarHeight() + PAD, 1, 1, 1, 1, D.FONT)
        return
    end
    local width = self.width - PAD * 2
    local y = self:titleBarHeight() + PAD
    local us, them = myTeam(v), myTeam(v) == 1 and 2 or 1
    y = self:renderScores(y)
    y = self:renderPlayers(y)
    y = self:drawMeldArea(them, PAD, y, width, THEM_ROWS, CC.text("TheirMelds"), false) + 4
    y = self:renderCentre(y)
    y = self:drawMeldArea(us, PAD, y, width, US_ROWS, CC.text("OurMelds"), true) + 4
    y = self:renderActions(y)
    self:renderHand(y)
    if v.phase == "roundOver" or v.phase == "matchOver" then self:renderResult() end
    D.drawTooltip(self)
end

function W:onMouseDown(x, y)
    if D.click(self, x, y) then return true end
    return ISCollapsableWindow.onMouseDown(self, x, y)
end
