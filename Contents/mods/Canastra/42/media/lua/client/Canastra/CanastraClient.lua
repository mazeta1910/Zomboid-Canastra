require "Canastra/CanastraEngine"
require "Canastra/CanastraNet"

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

local ERROR_MS = 4500

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
    if e.k == "Discard" then return CC.text("Log_Discard", who, CC.cardName(e.c)) end
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
        if CC.info.status == "playing" then
            CanastraGameWindow.open()
            if CanastraLobbyWindow.instance then CanastraLobbyWindow.instance:close() end
        else
            if wasPlaying and CanastraGameWindow.instance then CanastraGameWindow.instance:close() end
            CanastraLobbyWindow.open()
        end
        refreshWindows()
    elseif command == "left" then
        CC.info, CC.seat, CC.view = nil, nil, nil
        if CanastraGameWindow.instance then CanastraGameWindow.instance:close() end
        if args.kicked then CC.showMessage(CC.text("Err_Kicked"), true) end
        refreshWindows()
    elseif command == "error" then
        CC.showMessage(CC.text("Err_" .. tostring(args.key)), true)
    end
end

function CC.nearbyTables()
    local p = getPlayer()
    if not p then return {} end
    local maxD = N.sandbox("MaxDistance", 8)
    local out = {}
    for _, t in ipairs(CC.tables) do
        local dx, dy = p:getX() - t.x, p:getY() - t.y
        if math.abs(p:getZ() - t.z) < 1 and dx * dx + dy * dy <= maxD * maxD then out[#out + 1] = t end
    end
    return out
end

Events.OnServerCommand.Add(function(module, command, args)
    if module == N.MODULE then CC.onCommand(command, args or {}) end
end)

Events.OnGameStart.Add(function()
    CC.send("list")
    CC.send("sync")
end)
