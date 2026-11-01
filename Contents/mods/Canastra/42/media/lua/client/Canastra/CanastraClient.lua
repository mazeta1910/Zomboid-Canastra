require "Canastra/CanastraEngine"
require "Canastra/CanastraNet"
require "Canastra/CanastraSeating"

CanastraClient = {
    tables = {},
    info = nil,
    seat = nil,
    view = nil,
    message = nil,
}
local CC = CanastraClient
local C = Canastra.Cards
local N = Canastra.Net
local St = Canastra.Seating

local ERROR_MS = 4500
local LOCATE_MS = 500
local REPORT_MS = 1000
local RESEND_MS = 10000

function CC.text(key, ...)
    return getText("IGUI_Canastra_" .. key, ...)
end

function CC.ruleLabel(key)
    return getText("IGUI_Canastra_Rule_" .. key)
end

function CC.ruleValue(key, value)
    local tkey = "IGUI_Canastra_Val_" .. key .. "_" .. tostring(value)
    if type(value) == "number" then
        return getTextOrNull(tkey) or tostring(value)
    end
    return getText(tkey)
end

function CC.presetName(preset)
    return getText("IGUI_Canastra_Preset_" .. tostring(preset or "custom"))
end

function CC.cardName(id)
    if C.isJoker(id) then return CC.text("Joker") end
    local suits = { "Spades", "Hearts", "Clubs", "Diamonds" }
    return CC.text("CardFmt", C.rankLabel(id), CC.text("Suit_" .. suits[C.suit(id)]))
end

function CC.seatName(i)
    local s = CC.info and CC.info.seats and CC.info.seats[i]
    if not s then return "?" end
    if i == CC.seat then return CC.text("You") end
    return s.name ~= "" and s.name or CC.text("EmptySeat")
end

function CC.isHost()
    return CC.info ~= nil and CC.info.hostKey == N.playerKey(getPlayer())
end

function CC.formatLog(e)
    local who = e.s and CC.seatName(e.s) or ""
    if e.k == "Discard" or e.k == "Redraw" then return CC.text("Log_" .. e.k, who, CC.cardName(e.c)) end
    if e.k == "RoundStart" then return CC.text("Log_RoundStart", tostring(e.r)) end
    return CC.text("Log_" .. e.k, who, tostring(e.n or ""))
end

function CC.showMessage(text, isError)
    CC.message = { text = text, error = isError, until_ = getTimestampMs() + ERROR_MS }
end

function CC.currentMessage()
    local m = CC.message
    if m and getTimestampMs() < m.until_ then return m end
    return nil
end

function CC.send(command, args)
    N.toServer(command, args or {})
end

function CC.action(action)
    CC.send("action", { action = action })
end

local function refreshWindows()
    if CanastraLobbyWindow and CanastraLobbyWindow.instance then
        CanastraLobbyWindow.instance:refresh()
    end
    if CanastraGameWindow and CanastraGameWindow.instance then
        CanastraGameWindow.instance:refresh()
    end
end

function CC.onCommand(command, args)
    if command == "list" then
        CC.tables = args.tables or {}
        refreshWindows()
    elseif command == "table" then
        local wasPlaying = CC.info and CC.info.status == "playing"
        CC.info, CC.seat, CC.view = args.info, args.seat, args.view
        -- Updates refresh open windows in place; open() would raise them over the rules window.
        if CC.info.status == "playing" then
            if not CanastraGameWindow.instance then CanastraGameWindow.open() end
            if CanastraLobbyWindow.instance then CanastraLobbyWindow.instance:close() end
        else
            if wasPlaying and CanastraGameWindow.instance then CanastraGameWindow.instance:close() end
            if not CanastraLobbyWindow.instance then CanastraLobbyWindow.open() end
        end
        refreshWindows()
    elseif command == "left" then
        CC.info, CC.seat, CC.view = nil, nil, nil
        if CanastraGameWindow.instance then CanastraGameWindow.instance:close() end
        if args.kicked then CC.showMessage(CC.text("Err_Kicked"), true) end
        if args.away then CC.showMessage(CC.text("Err_AwayTimeout"), true) end
        refreshWindows()
    elseif command == "error" then
        CC.showMessage(CC.text("Err_" .. tostring(args.key)), true)
    end
end

-- Where the local player sits (Canastra.Seating.locate), cached briefly since the UI asks every frame.
local located = { at = -LOCATE_MS }
function CC.mySeat()
    local ts = getTimestampMs()
    if ts - located.at >= LOCATE_MS then
        local p = getPlayer()
        located.at = ts
        if p then
            located.seat, located.reason = St.locate(p)
        else
            located.seat, located.reason = nil, "NotSeated"
        end
    end
    return located.seat, located.reason
end

function CC.resetSeatCache()
    located.at = -LOCATE_MS
end

function CC.seatArgs()
    if not St.required() then return nil end
    return (CC.mySeat())
end

-- nil when the player may join table t, otherwise the error key explaining why not.
function CC.joinBlocker(t)
    if not t.tableKey then return nil end
    local seat, reason = CC.mySeat()
    if not seat then return reason end
    if seat.table ~= t.tableKey then return "WrongTable" end
    return nil
end

function CC.nearbyTables()
    local p = getPlayer()
    if not p then return {} end
    local maxD = N.sandbox("MaxDistance", 8)
    local mine = St.required() and CC.mySeat()
    local out = {}
    for _, t in ipairs(CC.tables) do
        local dx, dy = p:getX() - t.x, p:getY() - t.y
        local near = math.abs(p:getZ() - t.z) < 1 and dx * dx + dy * dy <= maxD * maxD
        if near or (mine and t.tableKey == mine.table) then out[#out + 1] = t end
    end
    return out
end

-- Keeps the server informed of whether we are still sitting at the match table.
local report = { at = 0, sentAt = 0, last = nil }
function CC.reportSeat()
    if not (CC.info and CC.info.tableKey) then
        report.last = nil
        return
    end
    local ts = getTimestampMs()
    if ts - report.at < REPORT_MS then return end
    report.at = ts
    CC.resetSeatCache()
    local seat = CC.mySeat()
    local sig = seat and (seat.table .. "@" .. seat.sx .. "," .. seat.sy) or "none"
    if sig ~= report.last or ts - report.sentAt >= RESEND_MS then
        report.last, report.sentAt = sig, ts
        CC.send("seated", seat or {})
    end
end

function CC.myAway()
    local s = CC.info and CC.seat and CC.info.seats and CC.info.seats[CC.seat]
    return s ~= nil and s.away == true
end

-- First seat (other than ours) whose player stood up, or nil.
function CC.awaySeat()
    if not (CC.info and CC.info.seats) then return nil end
    for i = 1, CC.info.n do
        if i ~= CC.seat and CC.info.seats[i].away then return i end
    end
    return nil
end

Events.OnServerCommand.Add(function(module, command, args)
    if module == N.MODULE then CC.onCommand(command, args or {}) end
end)

Events.OnTick.Add(function()
    CC.reportSeat()
end)

Events.OnGameStart.Add(function()
    CC.send("list")
    CC.send("sync")
end)
