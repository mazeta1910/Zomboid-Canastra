require "ISUI/ISCollapsableWindow"
require "Canastra/CanastraClient"
require "Canastra/UI/CanastraDraw"
require "Canastra/UI/CanastraRulesWindow"
require "Canastra/UI/CanastraResultWindow"
require "Canastra/UI/CanastraTableScene"

CanastraGameWindow = ISCollapsableWindow:derive("CanastraGameWindow")
local W = CanastraGameWindow
local D = CanastraDraw
local C = Canastra.Cards
local M = Canastra.Melds
local CC = CanastraClient
local Scene = CanastraTableScene
local Avatars = CanastraAvatars

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
        + W.portraitSize() + 6         -- score strip
        + D.FH + THEM_ROWS * meldRow   -- their melds
        + Scene.height() + 10          -- table scene
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
    if CanastraResultWindow.instance then CanastraResultWindow.instance:close() end
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    if W.instance == self then W.instance = nil end
end

local function isOver(v)
    return v.result ~= nil and (v.phase == "roundOver" or v.phase == "matchOver")
end

-- The result window opens once per finished round; closing it keeps it closed until reopened.
function W:syncResult()
    local v = CC.view
    if v and isOver(v) then
        local key = tostring(v.round) .. ":" .. v.phase
        if self.resultKey ~= key then
            self.resultKey = key
            CanastraResultWindow.open(self)
        end
    else
        self.resultKey = nil
        if CanastraResultWindow.instance then CanastraResultWindow.instance:close() end
    end
end

function W:showResult()
    CanastraResultWindow.open(self)
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
    self.pileArmed = nil
    self.joinable = nil
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
    -- A single card gained this turn stays highlighted until the turn ends; taking several
    -- (the pile, a two-card draw) highlights nothing.
    local previous = myTurn and self.fresh or {}
    self.fresh = {}
    local gained = 0
    for id in pairs(previous) do
        if inHand[id] then
            self.fresh[id] = true
            gained = gained + 1
        end
    end
    if not firstDeal then
        for _, id in ipairs(fresh) do
            self.fresh[id] = true
            gained = gained + 1
        end
    end
    if gained > 1 then self.fresh = {} end
    for id in pairs(self.selected) do
        if not inHand[id] then self.selected[id] = nil end
    end
    if not myTurn then
        self.staged = {}
        self.targetMeld = nil
    end
    if v.phase ~= "draw" then self.targetMeld = nil end
    if not myTurn or v.phase ~= "draw" or #(v.pile or {}) == 0 then self.pileArmed = nil end
    if not self.pileArmed then self.joinable = nil end
    for i = #self.staged, 1, -1 do
        for _, id in ipairs(self.staged[i]) do
            if not inHand[id] then
                table.remove(self.staged, i)
                break
            end
        end
    end
    self:syncResult()
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

-- Discarding the hand's first drawn card while its swap is still open swaps it for another.
local function discard(v, id)
    if v.redrawCard == id then
        CC.action({ type = "redraw" })
    else
        CC.action({ type = "discard", card = id })
    end
end

function W:toggleCard(id)
    local now = getTimestampMs()
    local v = CC.view
    if self.lastClick.id == id and now - self.lastClick.t < DOUBLE_CLICK_MS then
        self.lastClick.id = nil
        if isMyTurn(v) and v.phase == "play" then
            self.selected = {}
            discard(v, id)
            return
        end
    end
    self.lastClick.id, self.lastClick.t = id, now
    self.selected[id] = not self.selected[id] or nil
    if self.pileArmed then self:tryArmedTake() end
end

-- Own melds that these cards would extend; the server refuses joining alongside staged melds
-- or onto a frozen pile.
local function joinableMelds(self, v, cards)
    if #self.staged > 0 or v.rules.pileFreeze then return nil end
    local found
    for _, m in ipairs(v.melds[myTeam(v)] or {}) do
        local all = C.copyList(m.cards)
        for _, id in ipairs(cards) do all[#all + 1] = id end
        if M.analyze(all, v.rules, m.kind) then
            found = found or {}
            found[m.id] = true
        end
    end
    return found
end

-- After clicking the pile first: takes it as soon as the selected hand cards form a meld with its top,
-- unless they could also join an existing meld, in which case the player picks the meld or the pile.
function W:tryArmedTake()
    local v = CC.view
    local top = v and v.pile and v.pile[#v.pile]
    self.joinable = nil
    if not (isMyTurn(v) and v.phase == "draw" and top) then
        self.pileArmed = nil
        return
    end
    local sel = self:selectedList()
    if #sel == 0 then return end
    local cards = { top }
    for _, id in ipairs(sel) do cards[#cards + 1] = id end
    self.joinable = joinableMelds(self, v, cards)
    if self.joinable then return hint("Hint_PileJoinOrNew") end
    if #sel < 2 or not M.analyze(cards, v.rules) then return end
    local melds = { { cards = sel } }
    for _, m in ipairs(self.staged) do melds[#melds + 1] = { cards = m } end
    self:clearSelection()
    CC.action({ type = "takePile", melds = melds })
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
            discard(v, sel[1])
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
        local top = v.pile and v.pile[#v.pile]
        if not top then return hint("Hint_PileNeedsMeld") end
        self.pileArmed = not self.pileArmed or nil
        if self.pileArmed then hint("Hint_PileArmed", CC.cardName(top)) end
        return
    end
    self:clearSelection()
end

function W:clickOwnMeld(meldId)
    local v = CC.view
    if not isMyTurn(v) then return end
    if v.phase == "draw" then
        if v.rules.pileTake ~= "free" or v.rules.pileFreeze then
            if self.pileArmed then
                local sel = self:selectedList()
                self:clearSelection()
                CC.action({ type = "takePile", addTo = meldId, cards = sel })
                return
            end
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
    discard(v, sel[1])
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
    local r3W = #r3 > 0 and D.MINI_W + 8 or 0
    local headerY = y
    y = y + D.FH
    local areaH = rows * (D.MINI_H + 6)
    self:drawRect(x, y, width, areaH, 0.18, 0, 0, 0)
    local canAct = isOurs and isMyTurn(v)
    if canAct and v.phase == "play" then
        D.addHit(self, x, y, width, areaH, W.newMeld, nil, CC.text("NewMeldTip"))
    end
    if #r3 > 0 then
        -- Stacked from the header line down so each card's corner index stays visible.
        local cx = x + width - D.MINI_W - 4
        local top = headerY + 1
        local step = 0
        if #r3 > 1 then
            local fit = math.floor((y + areaH - 3 - top - D.MINI_H) / (#r3 - 1))
            step = math.min(D.FH + math.floor(D.MINI_W * 0.42), fit)
        end
        for i, id in ipairs(r3) do
            D.drawCard(self, id, cx, top + (i - 1) * step, D.MINI_W, D.MINI_H, { mini = true })
        end
        D.addHit(self, cx, top, D.MINI_W, (#r3 - 1) * step + D.MINI_H, nil, nil,
            CC.text("Res_Red3") .. " (" .. #r3 .. ")")
    end
    local placed = layoutMelds(v.melds[team] or {}, x + 4, y + 3, width - 8 - r3W, rows)
    for _, p in ipairs(placed) do
        local m = p.meld
        local target = isOurs and self.targetMeld == m.id
        local joinable = isOurs and self.joinable and self.joinable[m.id]
        local hover = D.isHover(self, p.x - 2, p.y - 2, p.w + 4, D.MINI_H + 4)
        if target or (hover and canAct) then
            self:drawRect(p.x - 2, p.y - 2, p.w + 4, D.MINI_H + 4, 0.5, 0.9, 0.8, 0.2)
        elseif joinable then
            self:drawRect(p.x - 2, p.y - 2, p.w + 4, D.MINI_H + 4, 0.45, 0.3, 0.9, 0.3)
        end
        for i, id in ipairs(m.cards) do
            D.drawCard(self, id, p.x + (i - 1) * p.step, p.y, D.MINI_W, D.MINI_H, { mini = true })
        end
        -- card count over the bottom-right corner of the last card
        local count = tostring(#m.cards)
        local cw, ch = D.textW(count) + 6, D.FH
        local cx = p.x + (#m.cards - 1) * p.step + D.MINI_W - cw - 1
        local cy = p.y + D.MINI_H - ch - 1
        local cc = m.canasta and (m.clean and D.COLOR_GOLD or D.COLOR_DIM) or { r = 1, g = 1, b = 1 }
        self:drawRect(cx, cy, cw, ch, 0.55, 0, 0, 0)
        self:drawTextCentre(count, cx + cw / 2, cy, cc.r, cc.g, cc.b, 0.9, D.FONT)
        if m.canasta then
            local c = m.clean and D.COLOR_GOLD or D.COLOR_DIM
            self:drawRect(p.x, p.y + D.MINI_H + 1, p.w, 3, 1, c.r, c.g, c.b)
        end
        D.addHit(self, p.x - 2, p.y - 2, p.w + 4, D.MINI_H + 4,
            isOurs and canAct and W.clickOwnMeld or nil, m.id, meldTooltip(m))
    end
    return y + areaH
end

-- ------------------------------------------------------------------ render sections

function W.portraitSize()
    return D.FH + 10
end

-- Face portraits of a team's seats (the viewer first). Returns the width used.
function W:drawPortraits(team, x, y)
    local v = CC.view
    local p = W.portraitSize()
    local seats = {}
    if v.teamOf[v.you] == team then seats[1] = v.you end
    for s = 1, v.n do
        if v.teamOf[s] == team and s ~= v.you then seats[#seats + 1] = s end
    end
    local col = team == myTeam(v) and D.COLOR_US or D.COLOR_THEM
    local step = p + 3
    for i, seat in ipairs(seats) do
        local px = x + (i - 1) * step
        local turn = v.turn == seat and (v.phase == "draw" or v.phase == "play")
        local c = turn and D.COLOR_GOLD or col
        self:drawRect(px - 1, y - 1, p + 2, p + 2, 1, c.r, c.g, c.b)
        self:drawRect(px, y, p, p, 1, 0.1, 0.12, 0.1)
        local r = { x = px, y = y, w = p, h = p }
        if not Avatars.place(self, "portrait_" .. seat, CC.info.seats[seat] or {}, r, Avatars.PORTRAIT) then
            Avatars.drawSilhouette(self, r, CC.seatName(seat))
        end
        D.addHit(self, px, y, p, p, nil, nil, CC.seatName(seat))
    end
    return #seats > 0 and (#seats - 1) * step + p or 0
end

-- Whose turn it is, centred in the score strip (kept between minX and maxX). Pulses gold on our turn.
-- Returns the badge's right edge.
function W:drawTurnBadge(v, minX, y, h, maxX)
    local playing = v.phase == "draw" or v.phase == "play"
    local mine = playing and v.turn == v.you
    local text, font, fh
    if not playing then
        text, font, fh = CC.text("Turn_RoundOver"), D.FONT, D.FH
    elseif mine then
        text, font, fh = CC.text("Turn_Yours"), UIFont.Medium, D.FH_MED
    else
        text, font, fh = CC.text("Turn_Of", CC.seatName(v.turn)), D.FONT, D.FH
    end
    local w = D.textW(text, font) + 24
    if w > maxX - minX then
        font, fh = D.FONT, D.FH
        text = D.fitText(text, maxX - minX - 24)
        w = D.textW(text, font) + 24
    end
    local x = math.floor(math.max(minX, math.min(maxX - w, (self.width - w) / 2)))
    if mine then
        local pulse = 0.5 + 0.5 * math.sin(getTimestampMs() / 180)
        self:drawRect(x - 3, y - 2, w + 6, h + 4, 0.25 + 0.35 * pulse, 1, 0.8, 0.15)
        self:drawRect(x, y, w, h, 0.95, 0.85, 0.6, 0.08)
        self:drawRectBorder(x, y, w, h, 1, 1, 0.92, 0.45)
        self:drawTextCentre(text, x + w / 2, y + (h - fh) / 2, 0.12, 0.07, 0, 1, font)
    else
        local col = D.COLOR_GOLD
        if playing then col = v.teamOf[v.turn] == myTeam(v) and D.COLOR_US or D.COLOR_THEM end
        self:drawRect(x, y, w, h, 0.6, 0, 0, 0)
        self:drawRectBorder(x, y, w, h, 0.9, col.r, col.g, col.b)
        self:drawTextCentre(text, x + w / 2, y + (h - fh) / 2, col.r, col.g, col.b, 1, font)
    end
    return x + w
end

function W:renderScores(y)
    local v = CC.view
    local us, them = myTeam(v), myTeam(v) == 1 and 2 or 1
    local p = W.portraitSize()
    local ty = y + math.floor((p - D.FH) / 2)
    local x = PAD
    x = x + self:drawPortraits(us, x, y) + 5
    local text = CC.text("Us") .. " " .. tostring(v.scores[us])
    self:drawText(text, x, ty, D.COLOR_US.r, D.COLOR_US.g, D.COLOR_US.b, 1, D.FONT)
    x = x + D.textW(text) + 16
    x = x + self:drawPortraits(them, x, y) + 5
    text = CC.text("Them") .. " " .. tostring(v.scores[them])
    self:drawText(text, x, ty, D.COLOR_THEM.r, D.COLOR_THEM.g, D.COLOR_THEM.b, 1, D.FONT)
    x = x + D.textW(text) + 16
    local bx = self.width - PAD - D.ICON
    local iconsLeft = bx - (D.ICON + 4) * 2 - 8
    local badgeR = self:drawTurnBadge(v, x, y, p, iconsLeft)
    text = CC.text("ScoreInfo", tostring(v.rules.targetScore), tostring(v.round), CC.presetName(v.rules.preset))
    local infoW = iconsLeft - badgeR - 12
    if infoW > D.FH * 3 then
        text = D.fitText(text, infoW)
        self:drawTextRight(text, iconsLeft, ty, 0.75, 0.75, 0.75, 1, D.FONT)
    end

    local iy = y + math.floor((p - D.ICON) / 2)
    D.iconButton(self, bx, iy, "leave", CC.text("LeaveTip"), W.leave)
    bx = bx - D.ICON - 4
    D.iconButton(self, bx, iy, "rules", CC.text("ViewRules"), function()
        CanastraRulesWindow.open(Canastra.Rules.sanitize(v.rules), false, nil)
    end)
    bx = bx - D.ICON - 4
    D.loadSettings()
    D.iconButton(self, bx, iy, "colors", CC.text(D.fourColor and "FourColorOn" or "FourColorOff"), function()
        D.setFourColor(not D.fourColor)
    end)
    if D.fourColor then
        self:drawRectBorder(bx, iy, D.ICON, D.ICON, 1, D.COLOR_GOLD.r, D.COLOR_GOLD.g, D.COLOR_GOLD.b)
    end
    return y + p + 6
end

-- The table scene is split around the 3D models: chairs and models here (prerender), the table and
-- everything on it in renderCentreFront (render), so the table hides the seated players' legs.
function W:renderCentre(y)
    local g = Scene.renderBack(self, CC.view, PAD, y, self.width - PAD * 2)
    self.centreLayout = g
    return g.y + g.h + 10
end

function W:renderCentreFront(g)
    local v = CC.view
    Scene.renderFront(self, v, g)
    local x, y = g.cardX, g.cardY
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
    self:drawText(CC.text("Stock", tostring(v.stock)), x, y + h + 1, 0.8, 0.8, 0.8, 1, D.FONT)
    D.addHit(self, x, y, D.HAND_W, h, W.clickStock, nil, CC.text("StockTip"))
    x = g.pileX

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
            D.drawCard(self, pile[i], x + (i - first) * step, y, D.HAND_W, h,
                { mini = i < #pile, selected = i == #pile and self.pileArmed })
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

    -- dead piles
    local dx = g.deadX
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

    -- action log
    if g.logW > D.FH * 4 then
        self:drawRect(g.logX, g.y, g.logW, g.h, 0.3, 0, 0, 0)
        local lines = math.floor((g.h - 4) / (D.FH + 1))
        local log = v.log or {}
        local start = math.max(1, #log - lines + 1)
        local ly = g.y + 2
        for i = start, #log do
            local a = i == #log and 1 or 0.7
            self:drawText(D.fitText(CC.formatLog(log[i]), g.logW - 8), g.logX + 4, ly, a, a, a, 1, D.FONT)
            ly = ly + D.FH + 1
        end
    end
end

function W:statusText()
    local v = CC.view
    local m = CC.currentMessage()
    if m then return m.text, m.error end
    if v.phase == "roundOver" or v.phase == "matchOver" then return CC.text("Status_RoundOver"), false end
    if CC.myAway() then return CC.text("Status_ReturnToTable"), true end
    if self.pileArmed and v.pile and #v.pile > 0 then
        if self.joinable then return CC.text("Hint_PileJoinOrNew"), false end
        return CC.text("Hint_PileArmed", CC.cardName(v.pile[#v.pile])), false
    end
    local away = CC.awaySeat()
    if away then return CC.text("Status_WaitingReturn", CC.seatName(away)), false end
    if not isMyTurn(v) then return CC.text("Status_Waiting", CC.seatName(v.turn)), false end
    if v.phase == "draw" then
        if v.rules.pileTake == "free" and not v.rules.pileFreeze then return CC.text("Status_DrawFree"), false end
        return CC.text("Status_DrawClosed"), false
    end
    if v.redrawCard then return CC.text("Status_Redraw", CC.cardName(v.redrawCard)), false end
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
    if isOver(v) and not CanastraResultWindow.instance then
        x = x + D.labelButton(self, x, y, "info", CC.text("ShowResult"), nil, W.showResult) + 10
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
        local warn = v.rules.redThrees and C.isBlackThree(id)
        D.drawCard(self, id, x, cy, D.HAND_W, D.HAND_H, { selected = sel, fresh = fresh, warn = warn })
        if fresh then
            local barW = i == n and D.HAND_W or math.min(step, D.HAND_W)
            self:drawRect(x, cy - 4, barW, 3, 1, 0.35, 0.95, 0.35)
        end
        local hitW = i == n and D.HAND_W or math.min(step, D.HAND_W)
        D.addHit(self, x, cy, hitW, D.HAND_H, function(s, cid) s:toggleCard(cid) end, id, nil)
    end
    return y + D.HAND_H + raise + 4
end

-- Felt cloth with a wooden frame, drawn flat.
function W:drawBackdrop()
    local th = self:titleBarHeight()
    local w, h = self.width, self.height - th
    local f = math.max(4, math.floor(5 * D.S))
    self:drawTextureScaled(D.tex("bg_felt"), 0, th, w, h, 1, 1, 1, 1)
    self:drawTextureScaled(D.tex("wood_h"), 0, th, w, f, 1, 1, 1, 1)
    self:drawTextureScaled(D.tex("wood_h"), 0, self.height - f, w, f, 1, 1, 1, 1)
    self:drawTextureScaled(D.tex("wood_v"), 0, th, f, h, 1, 1, 1, 1)
    self:drawTextureScaled(D.tex("wood_v"), w - f, th, f, h, 1, 1, 1, 1)
end

-- Child elements (the 3D avatars) are drawn between prerender and render: the window content goes
-- in prerender, underneath them; render adds the table over their legs, then the tooltip.
function W:prerender()
    ISCollapsableWindow.prerender(self)
    self.centreLayout = nil
    if self.isCollapsed then
        Avatars.hideAll(self)
        return
    end
    self:drawContent()
end

function W:render()
    if not self.isCollapsed and self.centreLayout and CC.view then
        self:renderCentreFront(self.centreLayout)
    end
    ISCollapsableWindow.render(self)
    if not self.isCollapsed then D.drawTooltip(self) end
end

function W:drawContent()
    D.beginHits(self)
    self:drawBackdrop()
    local v = CC.view
    if not v or not CC.info then
        Avatars.hideAll(self)
        self:drawText(CC.text("NoGame"), PAD, self:titleBarHeight() + PAD, 1, 1, 1, 1, D.FONT)
        return
    end
    local width = self.width - PAD * 2
    local y = self:titleBarHeight() + PAD
    local us, them = myTeam(v), myTeam(v) == 1 and 2 or 1
    Avatars.beginFrame(self)
    y = self:renderScores(y)
    y = self:drawMeldArea(them, PAD, y, width, THEM_ROWS, CC.text("TheirMelds"), false) + 4
    y = self:renderCentre(y)
    y = self:drawMeldArea(us, PAD, y, width, US_ROWS, CC.text("OurMelds"), true) + 4
    y = self:renderActions(y)
    self:renderHand(y)
    Avatars.endFrame(self)
end

function W:onMouseDown(x, y)
    if D.click(self, x, y) then return true end
    return ISCollapsableWindow.onMouseDown(self, x, y)
end
