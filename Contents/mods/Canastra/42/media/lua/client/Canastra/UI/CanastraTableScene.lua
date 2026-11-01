require "Canastra/CanastraClient"
require "Canastra/UI/CanastraDraw"
require "Canastra/UI/CanastraAvatars"

-- Centre of the game window: an illustrated table holding the stock, pile and dead piles, with the
-- other players seated around it as 3D models (partner/opponent across, side players in 4p).
CanastraTableScene = {}
local T = CanastraTableScene
local D = CanastraDraw
local CC = CanastraClient
local A = CanastraAvatars

-- Keep in sync with tools/generate_textures.py (table_pieces).
T.TABLE = { rim = 0.06, apron = 0.2, ends = 0.3 }

local GAP = 8
local PILE_SHOWN = 10
local DEAD_W = math.floor(150 * D.S)

-- Camera framing per seat position. With zoom 11 / y -0.52 the panel shows the character from the
-- floor (bottom edge) up to about FRAME_UNITS metres, whatever the panel's pixel size.
T.VIEW = {
    across = { dir = "S", zoom = 11, y = -0.52, seated = true },
    left = { dir = "E", zoom = 11, y = -0.52, seated = true },
    right = { dir = "W", zoom = 11, y = -0.52, seated = true },
}
local FRAME_UNITS = 1.67
-- Height of the table edge in the same units; the table is drawn over everything below it.
local TABLE_EDGE = 0.68

-- ------------------------------------------------------------------ geometry

function T.bandH()
    return math.floor(D.HAND_H * 1.2)
end

function T.tableH()
    local content = D.HAND_H + D.FH + 8
    return math.ceil(content / (1 - T.TABLE.rim * 2 - T.TABLE.apron))
end

function T.height()
    return T.bandH() + T.tableH()
end

local function tagH()
    return D.FH * 2 + 4
end

-- Room for the stock and its label ("Monte (104)") before the pile starts.
local function stockW()
    return math.max(D.HAND_W + GAP * 2, D.textW(CC.text("Stock", "104")) + GAP * 2)
end

local function pileW()
    return D.HAND_W + (PILE_SHOWN - 1) * D.MINI_STEP + GAP * 2
end

local function innerW()
    return stockW() + pileW() + DEAD_W
end

-- Seats around the table relative to the viewer, from the real chairs when players sit at a table;
-- otherwise next player on the left, then across, then right.
function T.positions(v)
    local info = CC.info or {}
    local chairs = {}
    for i, s in pairs(info.seats or {}) do
        if s.chair then chairs[i] = s.chair end
    end
    return Canastra.Seating.positions(v.n, v.you, chairs, info.centre)
end

function T.layout(v, x0, y, width)
    local g = { y = y, h = T.height(), band = T.bandH(), tableH = T.tableH() }
    g.sideW = v.n == 4 and math.floor(D.HAND_H * 1.3) or 0
    g.endW = math.floor(g.tableH * T.TABLE.ends)
    g.tableW = g.endW * 2 + innerW()
    g.tableX = x0 + g.sideW
    g.tableY = y + g.band
    g.cardX = g.tableX + g.endW
    g.cardY = g.tableY + math.floor(g.tableH * T.TABLE.rim) + 4
    g.pileX = g.cardX + stockW()
    g.deadX = g.pileX + pileW()
    g.apronY = g.tableY + math.floor(g.tableH * (1 - T.TABLE.apron))
    g.logX = g.tableX + g.tableW + g.sideW + GAP
    g.logW = x0 + width - g.logX
    -- across: the band above the table shows the part of the body above the table edge
    local ah = math.floor(g.band * FRAME_UNITS / (FRAME_UNITS - TABLE_EDGE))
    local aw = math.floor(ah * 0.9)
    g.rects = {
        across = { x = math.floor(g.tableX + (g.tableW - aw) / 2), y = y, w = aw, h = ah },
    }
    g.unitPx = ah / FRAME_UNITS
    if g.sideW > 0 then
        local h = g.h - tagH() - 2
        g.rects.left = { x = x0, y = y, w = g.sideW, h = h }
        g.rects.right = { x = g.tableX + g.tableW, y = y, w = g.sideW, h = h }
    end
    return g
end

-- ------------------------------------------------------------------ drawing

local function drawTable(win, g)
    local h = g.tableH
    win:drawTextureScaled(D.tex("table_l"), g.tableX, g.tableY, g.endW, h, 1, 1, 1, 1)
    win:drawTextureScaled(D.tex("table_m"), g.tableX + g.endW, g.tableY, g.tableW - g.endW * 2, h, 1, 1, 1, 1)
    win:drawTextureScaled(D.tex("table_r"), g.tableX + g.tableW - g.endW, g.tableY, g.endW, h, 1, 1, 1, 1)
end

-- Name and card count of one seat; gold when it is that seat's turn. x is the centre unless leftAligned.
local function seatTag(win, v, seat, x, y, maxW, twoLines, leftAligned)
    local team = v.teamOf[seat]
    local col = team == v.teamOf[v.you] and D.COLOR_US or D.COLOR_THEM
    local turn = v.turn == seat and (v.phase == "draw" or v.phase == "play")
    local info = CC.info.seats[seat] or {}
    local isBot = info.kind == "bot"
    local count = tostring(v.counts[seat] or 0)
    local away = info.away and ("  " .. CC.text("AwayShort")) or ""
    local cw = math.floor(D.FH * 0.7)
    local name = CC.seatName(seat)
    local iconW = isBot and D.FH + 2 or 0
    local countW = cw + 3 + D.textW(count) + D.textW(away)
    local nameMax = twoLines and (maxW - 8 - iconW) or (maxW - 14 - iconW - countW)
    name = D.fitText(name, math.max(D.FH, nameMax))
    local w, h
    if twoLines then
        w = math.max(iconW + D.textW(name), countW) + 8
        h = tagH()
    else
        w = iconW + D.textW(name) + 6 + countW + 8
        h = D.FH + 4
    end
    x = math.floor(leftAligned and x or x - w / 2)
    win:drawRect(x, y, w, h, turn and 0.85 or 0.55, turn and 0.45 or 0, turn and 0.38 or 0, turn and 0.05 or 0)
    win:drawRectBorder(x, y, w, h, turn and 1 or 0.3, 1, turn and 0.85 or 1, turn and 0.3 or 1)
    local tx = x + 4
    if isBot then
        win:drawTextureScaled(D.tex("icon_bot"), tx, y + 2, D.FH, D.FH, 0.9, 1, 1, 1)
        tx = tx + iconW
    end
    win:drawText(name, tx, y + 2, col.r, col.g, col.b, 1, D.FONT)
    local cx, cy = tx + D.textW(name) + 6, y + 2
    if twoLines then cx, cy = x + 4, y + D.FH + 2 end
    win:drawTextureScaled(D.cardBackTex(D.FH), cx, cy, cw, D.FH, 1, 1, 1, 1)
    win:drawText(count, cx + cw + 3, cy, 1, 1, 1, 1, D.FONT)
    if away ~= "" then
        win:drawText(away, cx + cw + 3 + D.textW(count), cy, 1, 0.6, 0.25, 1, D.FONT)
    end
    return w
end

-- Back layer (window prerender, under the 3D models): chairs and the avatars themselves.
function T.renderBack(win, v, x0, y, width)
    local g = T.layout(v, x0, y, width)
    g.seats = T.positions(v)
    for pos, seat in pairs(g.seats) do
        local r = g.rects[pos]
        local info = CC.info.seats[seat] or {}
        if pos == "across" then
            local ch = math.floor(g.unitPx * 1.0)
            local cw = math.floor(ch * 0.6)
            win:drawTextureScaled(D.tex("chair_back"), r.x + (r.w - cw) / 2, r.y + r.h - ch, cw, ch, 1, 1, 1, 1)
        else
            local cs = math.floor(r.w * 0.8)
            local cx = pos == "left" and r.x or r.x + r.w - cs
            win:drawTextureScaled(D.tex("chair_side_" .. (pos == "left" and "l" or "r")), cx, r.y + r.h - cs, cs, cs, 1, 1, 1, 1)
        end
        if not A.place(win, "scene_" .. pos, info, r, T.VIEW[pos]) then
            local sil = pos == "across" and { x = r.x, y = r.y, w = r.w, h = g.band } or r
            A.drawSilhouette(win, sil, CC.seatName(seat))
        end
    end
    return g
end

-- Front layer (window render, over the 3D models): the table hides the seated players' legs.
function T.renderFront(win, v, g)
    drawTable(win, g)
    for pos, seat in pairs(g.seats) do
        local r = g.rects[pos]
        if pos == "across" then
            local tx = math.floor(r.x + r.w / 2 + g.unitPx * 0.45)
            seatTag(win, v, seat, tx, g.y + math.floor((g.band - D.FH - 4) / 2), g.tableX + g.tableW - tx, false, true)
        else
            seatTag(win, v, seat, r.x + r.w / 2, r.y + r.h + 2, g.sideW + GAP, true)
        end
    end
    local apronH = g.tableY + g.tableH - g.apronY
    seatTag(win, v, v.you, g.tableX + g.tableW / 2, g.apronY + math.floor((apronH - D.FH - 4) / 2), g.tableW / 2, false)
end

return T
