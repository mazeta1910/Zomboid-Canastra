require "Canastra/CanastraClient"
require "Canastra/UI/CanastraLobbyWindow"
require "Canastra/UI/CanastraGameWindow"

local CC = CanastraClient
local N = Canastra.Net

local function openTable()
    if CC.info and CC.info.status == "playing" then
        CanastraGameWindow.open()
    else
        CanastraLobbyWindow.open()
    end
end

local function addOption(context, playerNum)
    local label
    if CC.info then
        label = getText("ContextMenu_Canastra_OpenTable")
    else
        label = getText("ContextMenu_Canastra_Play")
    end
    local option = context:addOption(label, nil, openTable)
    local tooltip = ISInventoryPaneContextMenu.addToolTip()
    local need = N.sandbox("RequiredDecks", 2)
    local have = N.countDecks(getSpecificPlayer(playerNum))
    tooltip.description = getText("Tooltip_Canastra_Decks", tostring(have), tostring(need))
    option.toolTip = tooltip
    return option
end

local function isDeck(item)
    return item and item:getFullType() == "Base.CardDeck"
end

Events.OnFillInventoryObjectContextMenu.Add(function(playerNum, context, items)
    for _, v in ipairs(items) do
        local item = v
        if not instanceof(v, "InventoryItem") then item = v.items and v.items[1] end
        if isDeck(item) then
            addOption(context, playerNum)
            return
        end
    end
end)

Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldobjects, test)
    if test then return end
    if CC.info or #CC.nearbyTables() > 0 then
        addOption(context, playerNum)
    end
end)
