require "Canastra/CanastraNet"

-- Physical seating: which chair a character sits on, which table that chair faces, and where
-- the other chairs are around it (left / across / right of the viewer).
Canastra = Canastra or {}
Canastra.Seating = {}
local St = Canastra.Seating
local N = Canastra.Net

local MAX_TABLE_TILES = 12
local EXCLUDE = { "bedside", "night", "saw", "dresser" }

function St.required()
    return N.sandbox("RequireSeat", true) == true
end

local function hasWord(s, word)
    return type(s) == "string" and s:lower():find(word, 1, true) ~= nil
end

local function isTableName(s)
    if not hasWord(s, "table") then return false end
    for _, w in ipairs(EXCLUDE) do
        if hasWord(s, w) then return false end
    end
    return true
end

-- Tables carry the game's "IsTable" flag; the sprite or furniture name is a fallback for modded tiles.
function St.isTable(obj)
    local sprite = obj and obj.getSprite and obj:getSprite()
    if not sprite then return false end
    local name = sprite:getName()
    for _, w in ipairs(EXCLUDE) do
        if hasWord(name, w) then return false end
    end
    if isTableName(name) then return true end
    local props = sprite:getProperties()
    if not props then return false end
    local ok, found = pcall(function()
        if props:has("IsTable") then return true end
        for _, key in ipairs({ "CustomName", "GroupName" }) do
            if props:has(key) and isTableName(props:get(key)) then return true end
        end
        return false
    end)
    return ok and found or false
end

local function squareHasTable(sq)
    if not sq then return false end
    local objects = sq:getObjects()
    for i = 0, objects:size() - 1 do
        if St.isTable(objects:get(i)) then return true end
    end
    return false
end

local NEIGHBOURS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }

-- All contiguous table tiles starting at (x, y, z); a multi-tile table counts as one table.
local function tableCluster(cell, x, y, z)
    local seen, queue, tiles = {}, { { x, y } }, {}
    seen[x .. "," .. y] = true
    while #queue > 0 and #tiles < MAX_TABLE_TILES do
        local p = table.remove(queue, 1)
        tiles[#tiles + 1] = p
        for k = 1, 4 do
            local nx, ny = p[1] + NEIGHBOURS[k][1], p[2] + NEIGHBOURS[k][2]
            local key = nx .. "," .. ny
            if not seen[key] then
                seen[key] = true
                if squareHasTable(cell:getGridSquare(nx, ny, z)) then queue[#queue + 1] = { nx, ny } end
            end
        end
    end
    return tiles
end

-- Where the character sits: { table = key, sx, sy, cx, cy, z } or nil plus "NotSeated"/"ChairNoTable".
function St.locate(player)
    local ok, chair = pcall(function()
        if not player:isSittingOnFurniture() then return nil end
        return player:getSitOnFurnitureObject()
    end)
    if not ok or not chair then return nil, "NotSeated" end
    local sq = chair:getSquare()
    if not sq then return nil, "NotSeated" end
    local cell = getCell()
    local sx, sy, z = sq:getX(), sq:getY(), sq:getZ()
    for _, d in ipairs(NEIGHBOURS) do
        local tx, ty = sx + d[1], sy + d[2]
        if squareHasTable(cell:getGridSquare(tx, ty, z)) then
            local tiles = tableCluster(cell, tx, ty, z)
            local minX, minY, sumX, sumY = math.huge, math.huge, 0, 0
            for _, t in ipairs(tiles) do
                if t[1] < minX or (t[1] == minX and t[2] < minY) then minX, minY = t[1], t[2] end
                sumX, sumY = sumX + t[1], sumY + t[2]
            end
            return {
                table = minX .. "," .. minY .. "," .. z, sx = sx, sy = sy, z = z,
                cx = sumX / #tiles + 0.5, cy = sumY / #tiles + 0.5,
            }
        end
    end
    return nil, "ChairNoTable"
end

-- Angle (degrees) around the table centre c between chair o and the spot across from chair s:
-- 0 = across, <0 left, >0 right of someone on s facing the table.
function St.angle(s, o, c)
    local fx, fy = c.x - s.x, c.y - s.y
    local ox, oy = o.x - c.x, o.y - c.y
    local cross = fx * oy - fy * ox
    local dot = fx * ox + fy * oy
    if dot == 0 and cross == 0 then return 0 end
    local a
    if dot > 0 then a = math.atan(cross / dot)
    elseif dot < 0 then a = math.atan(cross / dot) + (cross >= 0 and math.pi or -math.pi)
    else a = cross > 0 and math.pi / 2 or -math.pi / 2 end
    return math.deg(a)
end

local TARGETS = { left = -90, across = 0, right = 90 }

-- Assigns seats to the positions around the viewer. chairs[seat] = {x, y} for seated humans;
-- seats without a chair (bots) fill the free positions in turn order.
function St.positions(n, you, chairs, centre)
    local order = {}
    for k = 1, n - 1 do order[#order + 1] = ((you - 1 + k) % n) + 1 end
    local names = n == 4 and { "left", "across", "right" } or { "across" }
    local out = {}
    local mine = chairs and chairs[you]
    if mine and centre then
        local placed = {}
        local candidates = {}
        for _, seat in ipairs(order) do
            if chairs[seat] then candidates[#candidates + 1] = seat end
        end
        -- best assignment of the seated players to free positions (at most 3! permutations)
        local best, bestCost
        local function try(i, used, assign, cost)
            if bestCost and cost >= bestCost then return end
            if i > #candidates then
                best, bestCost = {}, cost
                for k, v in pairs(assign) do best[k] = v end
                return
            end
            local seat = candidates[i]
            local a = St.angle({ x = mine.x + 0.5, y = mine.y + 0.5 },
                { x = chairs[seat].x + 0.5, y = chairs[seat].y + 0.5 }, centre)
            for _, pos in ipairs(names) do
                if not used[pos] then
                    used[pos] = true
                    assign[pos] = seat
                    try(i + 1, used, assign, cost + math.abs(a - TARGETS[pos]))
                    used[pos] = nil
                    assign[pos] = nil
                end
            end
        end
        if #candidates <= #names then try(1, {}, {}, 0) end
        for pos, seat in pairs(best or {}) do
            out[pos] = seat
            placed[seat] = true
        end
        for _, seat in ipairs(order) do
            if not placed[seat] then
                for _, pos in ipairs(names) do
                    if not out[pos] then out[pos] = seat break end
                end
            end
        end
        return out
    end
    for i, pos in ipairs(names) do out[pos] = order[i] end
    return out
end

return St
