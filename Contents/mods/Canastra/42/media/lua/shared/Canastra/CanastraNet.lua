Canastra = Canastra or {}

local N = {}
Canastra.Net = N

N.MODULE = "Canastra"

local function isMP()
    return isClient() or isServer()
end

function N.playerKey(player)
    if isMP() then return player:getUsername() end
    return "local" .. tostring(player:getPlayerNum())
end

function N.playerName(player)
    if isMP() then return player:getUsername() end
    local ok, name = pcall(function()
        local desc = player:getDescriptor()
        return desc:getForename() .. " " .. desc:getSurname()
    end)
    if ok and name and name ~= " " then return name end
    return player:getUsername() or "?"
end

-- In singleplayer both sides live in the same Lua state, so commands are dispatched directly.
function N.toServer(command, args)
    local player = getPlayer()
    if isClient() then
        sendClientCommand(player, N.MODULE, command, args or {})
    elseif CanastraServer then
        CanastraServer.onCommand(player, command, args or {})
    end
end

function N.toClient(player, command, args)
    if isServer() then
        sendServerCommand(player, N.MODULE, command, args or {})
    elseif CanastraClient then
        CanastraClient.onCommand(command, args or {})
    end
end

function N.toAll(command, args)
    if isServer() then
        sendServerCommand(N.MODULE, command, args or {})
    elseif CanastraClient then
        CanastraClient.onCommand(command, args or {})
    end
end

function N.sandbox(key, default)
    local vars = SandboxVars and SandboxVars.Canastra
    if vars and vars[key] ~= nil then return vars[key] end
    return default
end

function N.countDecks(player)
    local inv = player and player:getInventory()
    if not inv then return 0 end
    local n = inv:getCountTypeRecurse("Base.CardDeck")
    if n == 0 then n = inv:getCountTypeRecurse("CardDeck") end
    return n
end

return N
