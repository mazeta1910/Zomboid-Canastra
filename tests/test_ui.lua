-- Singleplayer integration test: server + client + UI windows driven through their own handlers.
require "Canastra/CanastraServer"
require "Canastra/CanastraClient"
require "Canastra/UI/CanastraLobbyWindow"
require "Canastra/UI/CanastraGameWindow"
require "Canastra/CanastraContextMenu"

local C = Canastra.Cards
local R = Canastra.Rules
local B = Canastra.Bot
local S = CanastraServer
local CC = CanastraClient
local D = CanastraDraw

local failures, passes = 0, 0
local function check(cond, msg)
    if cond then passes = passes + 1 else failures = failures + 1 print("FAIL: " .. msg) end
end

local function advance(ms) MOCK_NOW = MOCK_NOW + ms end

local function renderAll()
    local wins = { CanastraLobbyWindow.instance, CanastraGameWindow.instance, CanastraRulesWindow.instance,
        CanastraResultWindow.instance }
    for i = 1, 4 do
        local win = wins[i]
        if win then
            win.mouseOver = math.random() < 0.7
            win.mouseX = math.random(0, math.floor(win.width))
            win.mouseY = math.random(0, math.floor(win.height))
            win:prerender()
            win:render()
        end
    end
end

local function clickHit(win, pred)
    win:prerender()
    win:render()
    for i = #win.hits, 1, -1 do
        local r = win.hits[i]
        if pred(r) then
            win:onMouseDown(r.x + math.min(r.w, 6) / 2, r.y + r.h / 2)
            return true
        end
    end
    return false
end

local function selectCards(win, ids)
    win.selected = {}
    for _, id in ipairs(ids) do
        advance(400)
        win:toggleCard(id)
    end
end

-- Performs the bot's suggestion for the human seat through the game window's UI paths.
local function humanStep(win, g, seat)
    local a = B.nextAction(g, seat)
    if not a then return false, "no action" end
    local before = #g.log + g.round * 1000 + (g.turn * 7) + #g.hands[seat] * 13 + #g.pile * 17
    if a.type == "draw" then
        local had = {}
        for _, id in ipairs(g.hands[seat]) do had[id] = true end
        if not clickHit(win, function(r) return r.fn == CanastraGameWindow.clickStock end) then return false, "stock hit" end
        drawnThisTurn = {}
        for _, id in ipairs(g.hands[seat]) do
            if not had[id] then drawnThisTurn[#drawnThisTurn + 1] = id end
        end
    elseif a.type == "takePile" then
        if a.addTo then
            clickHit(win, function(r) return r.fn == CanastraGameWindow.clickOwnMeld and r.arg == a.addTo end)
            selectCards(win, a.cards or {})
        elseif a.melds then
            selectCards(win, a.melds[1].cards)
            win.staged = {}
            for i = 2, #a.melds do win.staged[#win.staged + 1] = a.melds[i].cards end
        end
        if not clickHit(win, function(r) return r.fn == CanastraGameWindow.clickPile end) then return false, "pile hit" end
    elseif a.type == "meld" then
        if a.adds and #a.adds > 0 then
            selectCards(win, a.adds[1].cards)
            if not clickHit(win, function(r) return r.fn == CanastraGameWindow.clickOwnMeld and r.arg == a.adds[1].meld end) then
                return false, "meld hit"
            end
        else
            for _, m in ipairs(a.melds) do
                selectCards(win, m.cards)
                win:newMeld()
            end
            if #win.staged > 0 then win:confirmStaged() end
        end
    elseif a.type == "redraw" then
        if not clickHit(win, function(r) return r.fn == CanastraGameWindow.redraw end) then return false, "redraw hit" end
        redrawsByUI = (redrawsByUI or 0) + 1
    elseif a.type == "discard" then
        if math.random() < 0.5 then
            advance(1000)
            win:toggleCard(a.card)
            win:toggleCard(a.card)
        else
            selectCards(win, { a.card })
            if not clickHit(win, function(r) return r.fn == CanastraGameWindow.clickPile end) then return false, "pile hit" end
        end
    end
    local after = #g.log + g.round * 1000 + (g.turn * 7) + #g.hands[seat] * 13 + #g.pile * 17
    local m = CC.currentMessage()
    if m and m.error then return false, "UI action " .. a.type .. " rejected: " .. m.text end
    if before == after and g.phase ~= "roundOver" then return false, "UI action " .. a.type .. " had no effect" end
    return true
end

local function playMatch(preset, n, rounds)
    CC.message = nil
    CanastraLobbyWindow.open()
    renderAll()
    CanastraLobbyWindow.pending.n = n
    CanastraLobbyWindow.pending.fillBots = true
    CanastraLobbyWindow.pending.rules = R.fromPreset(preset)
    if not clickHit(CanastraLobbyWindow.instance, function(r) return r.fn == CanastraLobbyWindow.create end) then
        check(false, preset .. ": create button not found")
        return
    end
    check(CC.info and CC.info.status == "lobby", preset .. ": table created via lobby button")
    renderAll()
    CanastraLobbyWindow.instance:openRules()
    renderAll()
    CanastraRulesWindow.instance:close()
    CC.send("start", { decks = 2 })
    check(CC.info and CC.info.status == "playing" and CanastraGameWindow.instance, preset .. ": game started")
    local win = CanastraGameWindow.instance
    local t = S.tables[CC.info.id]
    if preset == "canastra_brasileira" and not D.fourColor then
        local tip = CC.text("FourColorOff")
        check(clickHit(win, function(r) return r.tooltip == tip end), "four-colour toggle found")
        check(CanastraDraw.fourColor and (MOCK_FILES["Canastra_settings.txt"] or ""):find("fourColor=true", 1, true),
            "four-colour deck enabled and saved")
        win:sort("rank")
        check((MOCK_FILES["Canastra_settings.txt"] or ""):find("sortMode=rank", 1, true), "sort mode saved")
    end
    do
        renderAll()
        local v = CC.view
        local expected = v.n == 4 and { "left", "across", "right" } or { "across" }
        for seat = 1, v.n do
            local a = win.avatars and win.avatars["portrait_" .. seat]
            local cfg = a and a.panel.cfg or {}
            check(a and a.panel.visible and cfg.setState == "idle" and cfg.setZoom == CanastraAvatars.PORTRAIT.zoom,
                preset .. ": portrait of seat " .. seat .. " shown")
        end
        for _, pos in ipairs(expected) do
            local a = win.avatars and win.avatars["scene_" .. pos]
            local cfg = a and a.panel.cfg or {}
            check(a and a.panel.visible, preset .. ": " .. pos .. " avatar shown")
            check(cfg.setState == "sitonfurniture" and cfg.var_SitOnFurnitureAnim == "Idle" and cfg.event_EventSitOnFurniture,
                preset .. ": " .. pos .. " avatar is seated")
            check(cfg.outfit ~= nil or cfg.setCharacter ~= nil, preset .. ": " .. pos .. " avatar dressed")
            local first = {}
            for i, f in ipairs(cfg.order or {}) do first[f] = first[f] or i end
            local body = first.setSurvivorDesc or first.setCharacter
            check(body and first.setAnimSetName and first.setState and first.setAnimSetName < body and first.setState < body,
                preset .. ": " .. pos .. " anim set and pose chosen before the character")
            local p = a and a.panel
            if p then
                check(p.x >= 0 and p.x + p.width <= win.width and p.y + p.height <= win.height,
                    preset .. ": " .. pos .. " avatar inside the window")
                check(p.consumesMouse == false, preset .. ": " .. pos .. " avatar lets clicks through to the table")
            end
        end
        local g = win.centreLayout
        check(g and g.logW > D.FH * 4 and g.tableX + g.tableW <= win.width, preset .. ": table scene fits the window")
        -- render runs after the child avatars: it may only paint the table over their lower part
        local covered = {}
        local function hit(x, y, w, h)
            for slot, a in pairs(win.avatars or {}) do
                local p = a.panel
                if p.visible then
                    local top, bottom = p.y, p.y + p.height
                    local left, right = p.x, p.x + p.width
                    if slot == "scene_across" then
                        bottom = g.tableY
                        left, right = p.x + p.width / 2 - g.unitPx * 0.3, p.x + p.width / 2 + g.unitPx * 0.3
                    end
                    if x < right and left < x + w and y < bottom and top < y + h then covered[slot] = true end
                end
            end
        end
        local origTex, origRect = win.drawTextureScaled, win.drawRect
        win.drawTextureScaled = function(self, tex, x, y, w, h) hit(x, y, w, h) end
        win.drawRect = function(self, x, y, w, h) hit(x, y, w, h) end
        win.mouseOver = false
        win:render()
        win.drawTextureScaled, win.drawRect = origTex, origRect
        for slot in pairs(covered) do
            check(false, preset .. ": " .. slot .. " is painted over after it renders")
        end
    end
    if preset == "canastra_brasileira" then
        local tip = CC.text("ViewRules")
        check(clickHit(win, function(r) return r.tooltip == tip end), "table rules button found")
        local rw = CanastraRulesWindow.instance
        win:bringToTop()
        renderAll()
        check(rw and rw.z > win.z, "rules window opened from the table stays in front of it")
        local z = rw.z
        S.pushState(t)
        check(win.z < z, "table updates do not raise the table over the rules window")
        rw:close()
    end
    local played, steps, unsorted = 0, 0, 0
    while played < rounds and steps < 5000 do
        steps = steps + 1
        renderAll()
        local expected = C.copyList(win.order)
        if win.sortMode == "rank" then C.sortByRank(expected) else C.sortBySuit(expected) end
        for i = 1, #expected do
            if expected[i] ~= win.order[i] then unsorted = unsorted + 1 break end
        end
        if t.game.turn == CC.seat and t.game.phase == "play" then
            for _, id in ipairs(drawnThisTurn or {}) do
                if C.indexOf(t.game.hands[CC.seat], id) and not (win.fresh and win.fresh[id]) then
                    notHighlighted = (notHighlighted or 0) + 1
                end
            end
        else
            drawnThisTurn = nil
        end
        local g = t.game
        if g.phase == "roundOver" or g.phase == "matchOver" then
            played = played + 1
            local rw = CanastraResultWindow.instance
            check(rw ~= nil, preset .. ": result window opens when the round ends")
            renderAll()
            check(rw and rw.title ~= "", preset .. ": result window shows the headline as its title")
            rw:close()
            check(CanastraResultWindow.lastX ~= nil, "result window remembers its position")
            win:refresh()
            check(CanastraResultWindow.instance == nil, preset .. ": closed result window stays closed on updates")
            check(clickHit(win, function(r) return r.fn == CanastraGameWindow.showResult end),
                preset .. ": result reopened from the table")
            rw = CanastraResultWindow.instance
            check(rw and clickHit(rw, function(r) return r.fn == CanastraResultWindow.nextRound end),
                preset .. ": next round button clicked in the result window")
            g = t.game
            check(g.phase == "draw", preset .. ": next round started")
            check(CanastraResultWindow.instance == nil, preset .. ": result window closes when the next round starts")
        elseif g.turn == CC.seat then
            local ok, err = humanStep(win, g, CC.seat)
            if not ok then
                check(false, preset .. ": " .. tostring(err))
                break
            end
        else
            advance(1100)
            triggerEvent("OnTick")
        end
        if steps % 40 == 0 then triggerEvent("EveryOneMinute") end
    end
    check(played >= rounds, preset .. ": played " .. played .. " rounds in " .. steps .. " steps")
    check(unsorted == 0, preset .. ": hand stayed sorted after every draw (" .. unsorted .. " unsorted frames)")
    print(string.format("  %-20s %dp: %d rounds through the UI (%d steps)", preset, n, played, steps))
    win:leave()
    win:leave()
    check(CC.info == nil, preset .. ": left the table")
    local count = 0
    for _ in pairs(S.tables) do count = count + 1 end
    check(count == 0, preset .. ": table removed after last human left")
end

triggerEvent("OnGameStart")

-- context menu on a card deck opens the lobby
local deck = { __class = "InventoryItem", getFullType = function() return "Base.CardDeck" end }
local ctx = newMockContext()
triggerEvent("OnFillInventoryObjectContextMenu", 0, ctx, { deck })
check(#ctx.options == 1, "deck context option added")
if ctx.options[1] then ctx.options[1].onSelect() end
check(CanastraLobbyWindow.instance ~= nil, "context option opens lobby")
renderAll()

-- creating without decks is refused
MOCK_DECKS = 1
CanastraLobbyWindow.instance:create()
check(CC.info == nil and CC.currentMessage() and CC.currentMessage().error, "table refused without 2 decks")
MOCK_DECKS = 2

print("UI integration:")
playMatch("buraco_aberto", 4, 3)
playMatch("buraco_fechado", 2, 3)
playMatch("canastra_classica", 4, 2)
playMatch("stbl", 2, 2)
playMatch("buraco_1morto", 4, 2)
playMatch("canastra_brasileira", 4, 2)
playMatch("canastra_brasileira", 2, 2)

-- ------------------------------------------------------------------ seating at a physical table
print("Seating:")
local St = Canastra.Seating
local where = St.locate(MOCK_PLAYER)
check(where and where.table == "100,199,0" and where.sx == 100 and where.sy == 200, "locate finds the chair and its table")
check(where and where.cx == 101 and where.cy == 199.5, "a two-tile table counts as one, centred between its tiles")
check(CC.joinBlocker({ tableKey = "100,199,0" }) == nil and CC.joinBlocker({ tableKey = "5,5,0" }) == "WrongTable",
    "joining requires the same table")

local P = function(chairs, n) return St.positions(n or 4, 1, chairs, { x = 10.5, y = 10.5 }) end
local pos = P({ [1] = { x = 10, y = 11 }, [2] = { x = 11, y = 10 }, [3] = { x = 10, y = 9 }, [4] = { x = 9, y = 10 } })
check(pos.left == 4 and pos.across == 3 and pos.right == 2, "players are placed where their chairs really are")
pos = P({ [1] = { x = 10, y = 11 }, [3] = { x = 11, y = 10 } })
check(pos.right == 3 and pos.left and pos.across and pos.left ~= pos.across, "bots fill the chairs nobody sits on")
pos = St.positions(4, 1, { [1] = { x = 10, y = 11 }, [2] = { x = 11, y = 9 }, [3] = { x = 11, y = 11 }, [4] = { x = 10, y = 9 } },
    { x = 11, y = 10.5 })
check(pos.right == 3 and pos.across == 2 and pos.left == 4, "long table: neighbour on my side is on my right, diagonal is across")
pos = P({ [1] = { x = 10, y = 11 }, [2] = { x = 10, y = 9 } }, 2)
check(pos.across == 2 and pos.left == nil, "1x1 shows the opponent across")

mockSit(MOCK_PLAYER, nil)
CC.resetSeatCache()
CanastraLobbyWindow.open()
renderAll()
check(not clickHit(CanastraLobbyWindow.instance, function(r) return r.fn == CanastraLobbyWindow.create end),
    "create is disabled while standing")
CanastraLobbyWindow.instance:create()
check(CC.info == nil and CC.currentMessage() and CC.currentMessage().text == CC.text("Err_NotSeated"), "server refuses a standing host")
mockSit(MOCK_PLAYER, 120, 220, 0)
CC.resetSeatCache()
check(select(2, St.locate(MOCK_PLAYER)) == "ChairNoTable", "a chair away from any table is not enough")
mockSit(MOCK_PLAYER, 100, 200, 0)
CC.resetSeatCache()

CC.message = nil
CanastraLobbyWindow.pending.n = 2
CanastraLobbyWindow.pending.fillBots = true
CanastraLobbyWindow.instance:create()
CC.send("start", { decks = 2 })
local seatT = CC.info and S.tables[CC.info.id]
check(seatT and seatT.tableKey == "100,199,0" and CC.info.seats[CC.seat].chair ~= nil, "match remembers the table and the chair")
if seatT then
    local g = seatT.game
    g.turn = CC.seat
    g.phase = "draw"
    mockSit(MOCK_PLAYER, nil)
    for _ = 1, 3 do advance(1100) triggerEvent("OnTick") end
    check(CC.myAway(), "standing up marks the player away")
    check(CanastraGameWindow.instance:statusText() == CC.text("Status_ReturnToTable"), "status asks to return to the table")
    local hand = #g.hands[CC.seat]
    CC.action({ type = "draw" })
    check(#g.hands[CC.seat] == hand and CC.currentMessage().text == CC.text("Err_Away"), "actions are refused while away")
    g.turn = CC.seat % 2 + 1
    seatT.botAt = nil
    for _ = 1, 5 do advance(1100) triggerEvent("OnTick") end
    check(g.turn ~= CC.seat and seatT.botAt == nil, "bots wait while a player is away")
    mockSit(MOCK_PLAYER, 100, 200, 0)
    for _ = 1, 3 do advance(1100) triggerEvent("OnTick") end
    check(not CC.myAway(), "sitting back down resumes the match")
    mockSit(MOCK_PLAYER, nil)
    for _ = 1, 130 do
        advance(1100)
        triggerEvent("OnTick")
        if not CC.info then break end
    end
    check(CC.info == nil and CC.currentMessage() and CC.currentMessage().text == CC.text("Err_AwayTimeout"),
        "leaving the table for too long gives up the seat")
    mockSit(MOCK_PLAYER, 100, 200, 0)
end
if CanastraGameWindow.instance then CanastraGameWindow.instance:close() end
CC.message = nil

-- ------------------------------------------------------------------ pile first, then the hand cards
print("Pile first:")
CC.message = nil
CanastraLobbyWindow.open()
CanastraLobbyWindow.pending.n = 2
CanastraLobbyWindow.pending.fillBots = true
CanastraLobbyWindow.pending.rules = R.fromPreset("canastra_brasileira")
CanastraLobbyWindow.instance:create()
CC.send("start", { decks = 2 })
local pt = CC.info and S.tables[CC.info.id]
if pt then
    local g, me = pt.game, CC.seat
    g.hasMelded[g.teamOf[me]] = true
    g.turn, g.phase = me, "draw"
    local aceS, aceH, aceD = C.make(1, 1, 1), C.make(1, 2, 1), C.make(2, 4, 1)
    g.hands[me] = { aceS, aceH, C.make(1, 3, 5), C.make(1, 4, 7), C.make(1, 1, 9), C.make(1, 2, 12) }
    g.pile = { C.make(2, 3, 6), aceD }
    S.pushState(pt)
    local win = CanastraGameWindow.instance
    renderAll()
    check(clickHit(win, function(r) return r.fn == CanastraGameWindow.clickPile end), "pile clicked first")
    check(win.pileArmed and g.phase == "draw", "clicking the pile with nothing selected sets its top card aside")
    advance(600)
    win:toggleCard(aceS)
    check(g.phase == "draw", "one card is not a meld yet")
    advance(600)
    win:toggleCard(aceH)
    check(g.phase == "play" and #g.pile == 0, "the second ace takes the pile at once")
    local found = false
    for _, m in ipairs(g.melds[g.teamOf[me]]) do
        if #m.cards == 3 and C.rank(m.cards[1]) == 1 then found = true end
    end
    check(found, "the three aces were melded")
    check(not win.pileArmed, "pile no longer set aside after taking it")

    -- clicking the pile again cancels
    g.turn, g.phase = me, "draw"
    g.pile = { C.make(2, 1, 9) }
    S.pushState(pt)
    win:clickPile()
    win:clickPile()
    check(not win.pileArmed, "clicking the pile again cancels")
    win:leave()
    win:leave()
end
CC.message = nil

print("  first-draw swaps clicked through the UI: " .. tostring(redrawsByUI or 0))
check((notHighlighted or 0) == 0, "drawn cards stay highlighted for the whole turn (" .. tostring(notHighlighted or 0) .. " misses)")
check(MOCK_STATS.BOREDOM < 50 and MOCK_STATS.STRESS < 0.5, "playing reduced boredom and stress")

for _, e in ipairs(MOCK_ERRORS) do
    failures = failures + 1
    print("MOCK ERROR: " .. e)
end
local missing = {}
for k in pairs(MISSING_TEXT) do missing[#missing + 1] = k end
table.sort(missing)
for _, k in ipairs(missing) do
    failures = failures + 1
    print("MISSING TRANSLATION: " .. k)
end

print(string.format("\n%d passed, %d failed", passes, failures))
return failures
