-- Tests: upgrades your characters can craft, on the character sheet (an anvil button
-- beside a slot). Loaded by tests/run.lua.

-- Logs in as Aldric, a level 24 warrior (mail is the heaviest armour he wears), with Smith
-- (a paladin who can mail him things) and Far Away (another ruleset, who can't).
function flyStart()
    local ns = wow.load(FILES)
    local mail = { sub = 3, loc = "INVTYPE_HAND", stats = { ITEM_MOD_STRENGTH_SHORT = 5 } }
    wow.item(6001, "Linked Gloves", mail)
    wow.item(6002, "Leather Gloves", { sub = 2, loc = "INVTYPE_HAND", stats = { ITEM_MOD_STRENGTH_SHORT = 9 } })
    wow.item(6003, "Bound Mail Gloves", { sub = 3, loc = "INVTYPE_HAND", bind = 1, stats = { ITEM_MOD_STRENGTH_SHORT = 5 } })
    wow.item(6004, "My Bound Gauntlets", { sub = 3, loc = "INVTYPE_HAND", bind = 1, stats = { ITEM_MOD_STRENGTH_SHORT = 5 } })
    wow.item(6005, "Far Gloves", mail)
    wow.item(6006, "Woolen Cape", { sub = 1, loc = "INVTYPE_CLOAK", stats = { ITEM_MOD_STAMINA_SHORT = 2 } })
    wow.item(6007, "Plate Gloves", { sub = 4, loc = "INVTYPE_HAND", stats = { ITEM_MOD_STRENGTH_SHORT = 9 } })
    wow.item(6008, "Future Helm", { sub = 3, loc = "INVTYPE_HEAD", level = 28, stats = { ITEM_MOD_STRENGTH_SHORT = 9 } })
    wow.player.class = "WARRIOR"
    -- The character sheet and three of its slot buttons.
    PaperDollFrame = CreateFrame("Frame")
    for name, id in pairs({ Head = 1, Back = 15, Hands = 10 }) do
        local b = CreateFrame("Button", "Character" .. name .. "Slot")
        b.GetID = function() return id end
    end
    wow.login({ v = 2, chars = {
        ["Aldric"] = alt("Aldric", "WARRIOR", { level = 24, gear = {}, realm = "Realm",
            crafts = { Blacksmithing = { [6004] = "my bound gauntlets" } } }),
        ["Smith"] = alt("Smith", "PALADIN", { realm = "Realm", crafts = { Blacksmithing = {
            [6001] = "linked gloves", [6002] = "leather gloves", [6003] = "bound mail gloves", [6007] = "plate gloves",
            [6008] = "future helm" },
            Tailoring = { [6006] = "woolen cape" },
            -- Left over from 0.2.x: the same items, as `true`, under a profession that doesn't make them.
            Cooking = { [6001] = true, [6006] = true } } }),
        ["Far Away"] = alt("Far Away", "WARRIOR", { realm = "Elsewhere", crafts = { Blacksmithing = { [6005] = "far gloves" } } }),
    } })
    return ns
end

test("craftable upgrades: the heaviest armour you wear, bind on pickup only your own, only from characters you can mail", function()
    local ns = flyStart()
    local list = ns.CraftableUpgrades(10)
    local got = {}
    for _, e in ipairs(list) do got[#got + 1] = e.id .. " " .. e.key .. " " .. e.prof end
    -- Not leather (a warrior wears mail) or plate (not until 40), not Smith's bind-on-pickup
    -- gloves (can't be mailed), not Far Away's (another ruleset).
    eq(table.concat(got, ", "), "6001 Smith Blacksmithing, 6004 Aldric Blacksmithing")
    eq(list[1].gain, math.huge, "nothing worn there")
    -- A cloak is cloth for everyone: not held to the heaviest type.
    eq(ns.CraftableUpgrades(15)[1].id, 6006)
    eq(ns.CraftableUpgrades(15)[1].prof, "Tailoring", "not the leftover Cooking entry")
    local crafts = { Cooking = { [1] = true, [2] = true }, Leatherworking = { [1] = "embossed leather cloak" } }
    eq(ns.CraftProf(crafts, "Cooking", 1), "Leatherworking", "the entry with the recipe's name wins")
    eq(ns.CraftProf(crafts, "Leatherworking", 1), "Leatherworking")
    eq(ns.CraftProf(crafts, "Cooking", 2), "Cooking", "a lone old entry stands")
    local head = ns.CraftableUpgrades(1)
    eq(#head, 1)
    eq(head[1].at, 28, "the helm, from level 28")
    eq(#ns.CraftableUpgrades(2), 0, "nothing for the neck")
end)

test("the character sheet puts an anvil beside slots with a craftable upgrade you can wear now that binds when equipped", function()
    local ns = flyStart()
    PaperDollFrame.scripts.OnShow(PaperDollFrame)
    local hands, back, head = ns.CraftGlyph(CharacterHandsSlot), ns.CraftGlyph(CharacterBackSlot), ns.CraftGlyph(CharacterHeadSlot)
    eq(hands and hands:IsShown(), true, "the mail gloves Smith makes")
    eq(back and back:IsShown(), true, "the cape: cloth for everyone")
    eq(head, nil, "the helm needs level 28: not wearable yet")
    eq(hands.point[1], "TOPLEFT", "outside the right-hand column")
    eq(back.point[1], "TOPRIGHT", "outside the left-hand column")
    -- The best upgrade's chevrons on the anvil: nothing worn in the hands, so major.
    eq(hands.tier.texture, "Interface\\AddOns\\AltsForever\\media\\up3.tga")
    -- Shipped with the addon, and drawn.
    local release = assert(io.open("tools/release.py")):read("*a")
    for n = 1, 3 do
        assert(release:find('"media/up' .. n .. '.tga"', 1, true), "up" .. n .. ".tga ships")
        local f = assert(io.open("media/up" .. n .. ".tga", "rb"), "up" .. n .. ".tga exists")
        f:close()
    end
    -- Hovering the anvil: the best few, and who makes them.
    hands.scripts.OnEnter(hands)
    local text = {}
    for _, line in ipairs(GameTooltip.lines) do text[#text + 1] = tostring(line[1]) .. " | " .. tostring(line[2]) end
    text = table.concat(text, "\n")
    assert(text:find("Your characters can craft", 1, true), text)
    assert(text:find("Linked Gloves", 1, true) and text:find("Smith", 1, true), text)
    assert(not text:find("My Bound Gauntlets", 1, true), "binds on pickup: left out\n" .. text)
    -- Clicking it: the items beside it; again: closed.
    hands.scripts.OnClick(hands)
    local panel = AltsForeverCraftPanel
    eq(panel:IsShown(), true)
    local items = {}
    for _, child in ipairs({ panel:GetChildren() }) do
        if child:IsShown() and child.entry then items[#items + 1] = child end
    end
    eq(#items, 1)
    items[1].scripts.OnEnter(items[1])
    local tip = {}
    for _, line in ipairs(GameTooltip.lines) do tip[#tip + 1] = tostring(line[1]) end
    assert(table.concat(tip, "\n"):find("Crafted by [PALADIN]Smith (Blacksmithing)", 1, true), table.concat(tip, "\n"))
    hands.scripts.OnClick(hands)
    eq(panel:IsShown(), false, "click again closes it")
    hands.scripts.OnClick(hands)
    PaperDollFrame:Hide()
    eq(panel:IsShown(), false, "closes with the character sheet")
    PaperDollFrame:Show()
    -- Their own setting: /af anvils, the menu. Show upgrades (the tooltips) doesn't touch them.
    ns.SetUpgrades(false)
    eq(hands:IsShown(), true, "tooltips' upgrades off: the anvils stay")
    ns.SetUpgrades(true)
    SlashCmdList.ALTSFOREVER("anvils")
    eq(AltsForeverDB.anvilsOff, true)
    eq(hands:IsShown(), false, "anvils off")
    ns.ShowOptionsMenu(UIParent)
    pageBox("Show craftable upgrades on the character sheet").setSelected()
    eq(AltsForeverDB.anvilsOff, nil)
    eq(hands:IsShown(), true, "back on")
end)

test("with the Gamepad UI on, the character sheet's anvils and their panel are built while it's closed; the panel takes focus", function()
    local ns = flyStart()
    PaperDollFrame:Hide()
    wow.gamepadUI = true
    wow.fire("INPUT_DEVICE_INTERFACE_TRANSITION", 1, 0)
    local hands = ns.CraftGlyph(CharacterHandsSlot)
    assert(hands, "made")
    eq(ns.CraftGlyph(CharacterHeadSlot):IsShown(), false)
    local panel = AltsForeverCraftPanel
    local made = 0
    for _, child in ipairs({ panel:GetChildren() }) do
        if child.icon then made = made + 1 end
    end
    eq(made, 10, "every item button")
    -- Opening the sheet makes nothing new, and shows the anvils that have upgrades.
    local frames = #wow.frames
    PaperDollFrame:Show()
    eq(#wow.frames, frames, "nothing created with the sheet open")
    eq(hands:IsShown(), true)
    eq(ns.CraftGlyph(CharacterHeadSlot):IsShown(), false, "the helm: not wearable yet")
    -- A on the anvil: the panel opens and reports to the focus manager; B closes it.
    wow.focus = {}
    hands.scripts.OnClick(hands)
    eq(focusCalls(), "shown AltsForeverCraftPanel")
    eq(panel:SmartNavigationCloseHandler(), true)
    eq(panel:IsShown(), false)
    eq(focusCalls(), "hidden AltsForeverCraftPanel")
    wow.gamepadUI = false
end)

test("items arriving while the character sheet is open: its anvils are worked out once per burst", function()
    local ns = wow.load(FILES)
    local crafts = {}
    for i = 1, 30 do
        local id = 7000 + i
        wow.item(id, "Gloves " .. i, { sub = 3, loc = "INVTYPE_HAND", stats = { ITEM_MOD_STRENGTH_SHORT = i } })
        crafts[id] = "gloves " .. i
        wow.uncached[id] = true
    end
    wow.player.class = "WARRIOR"
    PaperDollFrame = CreateFrame("Frame")
    local b = CreateFrame("Button", "CharacterHandsSlot")
    b.GetID = function() return 10 end
    wow.login({ v = 2, chars = {
        ["Aldric"] = alt("Aldric", "WARRIOR", { level = 24, gear = {}, realm = "Realm" }),
        ["Smith"] = alt("Smith", "PALADIN", { realm = "Realm", crafts = { Blacksmithing = crafts } }),
    } })
    wow.timers = {}
    local runs, real = 0, ns.CraftableUpgrades
    ns.CraftableUpgrades = function(...) runs = runs + 1 return real(...) end
    PaperDollFrame:Show()
    PaperDollFrame.scripts.OnShow(PaperDollFrame)
    eq(runs, 1)
    for i = 1, 30 do
        wow.uncached[7000 + i] = nil
        wow.fire("GET_ITEM_INFO_RECEIVED", 7000 + i, true)
    end
    eq(runs, 1, "nothing worked out per item")
    runTimers()
    assert(runs <= 3, "once for the burst (plus the sheet's own retry), not 30 times: " .. runs)
    eq(ns.CraftGlyph(b):IsShown(), true, "the anvil is there once the items have come")
end)

test("an item that never loads: the open character sheet tries again at most 5 times in a row", function()
    local ns = wow.load(FILES)
    wow.item(7101, "Lost Gloves", { sub = 3, loc = "INVTYPE_HAND", stats = { ITEM_MOD_STRENGTH_SHORT = 3 } })
    wow.uncached[7101] = true
    wow.player.class = "WARRIOR"
    PaperDollFrame = CreateFrame("Frame")
    PaperDollFrame:Hide()
    local b = CreateFrame("Button", "CharacterHandsSlot")
    b.GetID = function() return 10 end
    wow.login({ v = 2, chars = {
        ["Aldric"] = alt("Aldric", "WARRIOR", { level = 24, gear = {}, realm = "Realm" }),
        ["Smith"] = alt("Smith", "PALADIN", { realm = "Realm", crafts = { Blacksmithing = { [7101] = "lost gloves" } } }),
    } })
    for _ = 1, 5 do runTimers() end -- the login's own, with the sheet closed
    local runs, real = 0, ns.CraftableUpgrades
    ns.CraftableUpgrades = function(...) runs = runs + 1 return real(...) end
    -- The game answers every request for it, and the load fails each time.
    local answered = 0
    local function step()
        local loads = wow.itemLoads or {}
        for i = answered + 1, #loads do wow.fire("GET_ITEM_INFO_RECEIVED", loads[i], false) end
        answered = #loads
        runTimers()
    end
    PaperDollFrame:Show()
    eq(runs, 1)
    for _ = 1, 20 do step() end
    eq(runs, 6, "the first pass and 5 retries, failed loads or not")
    eq(#wow.timers, 0, "then no more timers")
    -- Opened afresh: it tries again, as many times.
    PaperDollFrame:Hide()
    PaperDollFrame:Show()
    for _ = 1, 20 do step() end
    eq(runs, 12)
    eq(#wow.timers, 0)
    -- Once the item comes, the anvil shows.
    wow.uncached[7101] = nil
    wow.fire("GET_ITEM_INFO_RECEIVED", 7101, true)
    runTimers()
    eq(ns.CraftGlyph(b):IsShown(), true)
end)

test("forgetting a crafter with the character sheet open: their anvil goes, and hovering never errors", function()
    local ns = flyStart()
    PaperDollFrame:Show()
    PaperDollFrame.scripts.OnShow(PaperDollFrame)
    local g = ns.CraftGlyph(CharacterHandsSlot)
    eq(g:IsShown(), true)
    SlashCmdList.ALTSFOREVER("delete Smith")
    eq(AltsForeverDB.chars["Smith"], nil)
    eq(g:IsShown(), false, "Smith's gloves were the only upgrade")
    local ok, err = pcall(g.scripts.OnEnter, g)
    assert(ok, err)
end)

-- The inspect window on another player: a level 24 warrior with 12 points in their third
-- talent tab (Protection), wearing nothing, on your faction. Returns ns and the tables the
-- test changes: links[slot], ids[slot] (worn items), and `their` (class, level, faction, guid,
-- talents as { posX, rank }, valid).
function inspectStart()
    local ns = flyStart()
    local links, ids = {}, {}
    local their = { class = "WARRIOR", level = 24, faction = "Alliance", guid = "Player-1-THEM", valid = true,
        talents = { { 0, 0 }, { 3000, 0 }, { 6000, 12 } } }
    InspectFrame = CreateFrame("Frame")
    InspectFrame.unit = "target"
    for name, id in pairs({ Head = 1, Back = 15, Hands = 10 }) do
        local b = CreateFrame("Button", "Inspect" .. name .. "Slot")
        b.GetID = function() return id end
    end
    local class, level, faction = UnitClass, UnitLevel, UnitFactionGroup
    local link, item = GetInventoryItemLink, GetInventoryItemID
    UnitClass = function(unit) if unit == "target" then return "Warrior", their.class end return class(unit) end
    UnitLevel = function(unit) if unit == "target" then return their.level end return level(unit) end
    UnitFactionGroup = function(unit) if unit == "target" then return their.faction end return faction(unit) end
    UnitGUID = function(unit) return unit == "target" and their.guid or "Player-1-ME" end
    GetInventoryItemLink = function(unit, slot) if unit == "target" then return links[slot] end return link(unit, slot) end
    GetInventoryItemID = function(unit, slot) if unit == "target" then return ids[slot] end return item(unit, slot) end
    -- The inspect config, as the game gave it (2026-11-11): -1, with its own tree.
    Constants = { TraitConsts = { INSPECT_TRAIT_CONFIG_ID = -1 } }
    local T = C_Traits
    local info, nodes, node = T.GetConfigInfo, T.GetTreeNodes, T.GetNodeInfo
    T.HasValidInspectData = function() return their.valid end
    T.GetConfigInfo = function(config) if config == -1 then return { ID = -1, type = 4, treeIDs = { 1100 } } end return info(config) end
    T.GetTreeNodes = function(tree)
        if tree ~= 1100 then return nodes(tree) end
        local list = {}
        for i in ipairs(their.talents) do list[i] = i end
        return list
    end
    T.GetNodeInfo = function(config, id)
        if config ~= -1 then return node(config, id) end
        local n = their.talents[id]
        return { ID = id, posX = n[1], currentRank = 0, ranksPurchased = n[2] }
    end
    return ns, links, ids, their
end

-- The game says an inspected player's data is in; our work follows a frame later.
function inspectReady(guid)
    wow.fire("INSPECT_READY", guid)
    local fns = wow.timers
    wow.timers = {}
    for i, fn in ipairs(fns) do
        if i == #fns then fn() else wow.timers[#wow.timers + 1] = fn end -- only ours: the last queued
    end
end

test("inspecting a player: anvils beside their slots for what your characters could craft for them", function()
    local ns, links, _, their = inspectStart()
    inspectReady(their.guid)
    local hands, back, head = ns.CraftGlyph(InspectHandsSlot), ns.CraftGlyph(InspectBackSlot), ns.CraftGlyph(InspectHeadSlot)
    eq(hands and hands:IsShown(), true, "the mail gloves Smith makes")
    eq(back and back:IsShown(), true, "the cape")
    eq(head, nil, "the helm needs level 28")
    eq(ns.CraftGlyph(CharacterHandsSlot), nil, "your own sheet isn't open: nothing there")
    -- Inside the columns: the inspect window's slots sit against its edges.
    eq(hands.point[1], "TOPRIGHT"); eq(hands.point[2], InspectHandsSlot); eq(hands.point[3], "TOPLEFT")
    eq(back.point[1], "TOPLEFT"); eq(back.point[3], "TOPRIGHT")
    eq(back.point[4], 5, "close by without EllesmereUI's item levels there")
    -- The chevrons beside the anvil, further in: the row below can hold an enchant's text.
    eq(back.tier.point[1], "LEFT"); eq(back.tier.point[3], "RIGHT")
    eq(hands.tier.point[1], "RIGHT"); eq(hands.tier.point[3], "LEFT")
    -- Only what can be handed over: your own bind-on-pickup gauntlets are for you alone.
    local got = {}
    for _, e in ipairs(hands.lists[10]) do got[#got + 1] = e.id .. " " .. e.key end
    eq(table.concat(got, ", "), "6001 Smith")
    local forThem = ns.CraftableUpgrades(10, nil, { class = "WARRIOR", level = 24, gear = {} })
    eq(#forThem, 1, "not listed for them at all")
    eq(forThem[1].id, 6001)
    eq(#ns.CraftableUpgrades(10), 2, "while yours still lists your own")
    -- The hover says what they were judged as: 12 points in the third tab, a tank.
    hands.scripts.OnEnter(hands)
    local seen = false
    for _, line in ipairs(GameTooltip.lines) do if line[1] == "Judged as Tank" then seen = true end end
    eq(seen, true, "judged by their talents")
    -- Clicking lists them, and closing the inspect window closes the list.
    hands.scripts.OnClick(hands)
    eq(AltsForeverCraftPanel:IsShown(), true)
    eq(AltsForeverCraftPanel.point[2], InspectHandsSlot, "the list opens beyond the slot, not over it")
    InspectFrame:Hide()
    eq(AltsForeverCraftPanel:IsShown(), false)
    InspectFrame:Show()
    -- The game's window shows itself from the same event, which can reach us first: still
    -- hidden when the event comes, open a frame later.
    hands:Hide()
    InspectFrame:Hide()
    wow.fire("INSPECT_READY", their.guid)
    eq(hands:IsShown(), false)
    InspectFrame:Show()
    runTimers()
    eq(hands:IsShown(), true, "worked out once the window is up")
    -- Another addon inspecting someone else raises the event too: nothing is worked out.
    local runs, real = 0, ns.CraftableUpgrades
    ns.CraftableUpgrades = function(...) runs = runs + 1 return real(...) end
    inspectReady("Player-1-OTHER")
    eq(runs, 0)
    -- That inspect put the other player's talents in the game's one inspect config (theirs
    -- are in the first tab: melee). A later pass must still judge this one by their own.
    their.talents = { { 0, 12 }, { 3000, 0 }, { 6000, 0 } }
    eq(ns.InspectSpec(), 1, "the config is the other player's now")
    ns.CharacterSheetChanged()
    assert(runs >= 1, "worked out again")
    runs = 0
    local function judged(g)
        g.scripts.OnEnter(g)
        for _, line in ipairs(GameTooltip.lines) do
            local role = type(line[1]) == "string" and line[1]:match("^Judged as (.+)$")
            if role then return role end
        end
    end
    eq(judged(hands), "Tank", "still their own talents, from when they were inspected")
    SlashCmdList.ALTSFOREVER("inspect")
    SlashCmdList.ALTSFOREVER("inspect")
    eq(judged(hands), "Tank", "after the setting is switched off and on too")
    runs = 0
    their.talents = { { 0, 0 }, { 3000, 0 }, { 6000, 12 } }
    -- They put on better gloves: no anvil for the hands any more.
    wow.item(6009, "Great Gloves", { sub = 3, loc = "INVTYPE_HAND", stats = { ITEM_MOD_STRENGTH_SHORT = 30, ITEM_MOD_STAMINA_SHORT = 30 } })
    links[10] = select(2, C_Item.GetItemInfo(6009))
    inspectReady(their.guid)
    eq(runs, 1)
    eq(hands:IsShown(), false)
    eq(back:IsShown(), true)
    -- Nothing about them is saved.
    for key in pairs(AltsForeverDB.chars) do assert(key == "Aldric" or key == "Smith" or key == "Far Away", key) end
end)

test("inspecting a player: their class, faction and the setting decide; a closed window does nothing", function()
    local ns, _, _, their = inspectStart()
    -- A rogue wears leather: Smith's leather gloves, not the mail ones.
    their.class, their.talents = "ROGUE", { { 0, 0 } }
    inspectReady(their.guid)
    local hands = ns.CraftGlyph(InspectHandsSlot)
    eq(hands.lists[10][1].id, 6002)
    eq(#hands.lists[10], 1)
    -- The other faction can't be handed anything.
    their.faction = "Horde"
    inspectReady(their.guid)
    eq(hands:IsShown(), false)
    their.faction = "Alliance"
    inspectReady(their.guid)
    eq(hands:IsShown(), true)
    -- Its own setting, apart from the character sheet's.
    SlashCmdList.ALTSFOREVER("inspect")
    eq(AltsForeverDB.inspectAnvilsOff, true)
    eq(hands:IsShown(), false)
    eq(ns.AnvilsOn(), true, "the character sheet's is untouched")
    SlashCmdList.ALTSFOREVER("inspect")
    eq(AltsForeverDB.inspectAnvilsOff, nil)
    eq(hands:IsShown(), true)
    -- With the Gamepad UI on there are none (a frame made in an open window).
    wow.gamepadUI = true
    inspectReady(their.guid)
    eq(hands:IsShown(), false)
    wow.gamepadUI = false
    -- The window closed: the event (other addons inspect too) works nothing out.
    InspectFrame:Hide()
    local runs, real = 0, ns.CraftableUpgrades
    ns.CraftableUpgrades = function(...) runs = runs + 1 return real(...) end
    inspectReady(their.guid)
    eq(runs, 0)
    -- A level or class the game won't say (secret, or not there yet): no error, no anvils.
    InspectFrame:Show()
    their.class = nil
    inspectReady(their.guid)
    eq(hands:IsShown(), false)
end)

test("inspecting a player: links or talents still on their way are tried again, at most 5 times", function()
    local ns, links, ids, their = inspectStart()
    for _ = 1, 5 do runTimers() end
    wow.timers = {}
    local runs, real = 0, ns.CraftableUpgrades
    ns.CraftableUpgrades = function(...) runs = runs + 1 return real(...) end
    -- Their gloves are known by ID, the link not yet; their talents aren't in either.
    wow.item(6009, "Great Gloves", { sub = 3, loc = "INVTYPE_HAND", stats = { ITEM_MOD_STRENGTH_SHORT = 30 } })
    ids[10] = 6009
    their.valid = false
    inspectReady(their.guid)
    eq(runs, 0, "not judged while a worn item's link is missing")
    eq(ns.CraftGlyph(InspectHandsSlot), nil, "no anvil: their gloves aren't an empty slot")
    eq(ns.CraftGlyph(InspectBackSlot), nil, "nor anywhere else: the whole gear score isn't known")
    eq(#wow.timers, 1, "one retry waiting")
    -- The link arrives, their talents not yet: judged now, by the class's default meanwhile.
    links[10] = select(2, C_Item.GetItemInfo(6009))
    runTimers()
    eq(runs, 1)
    eq(ns.CraftGlyph(InspectHandsSlot), nil, "they already wear better")
    local back = ns.CraftGlyph(InspectBackSlot)
    eq(back:IsShown(), true)
    back.scripts.OnEnter(back)
    local seen
    for _, line in ipairs(GameTooltip.lines) do if line[1] == "Judged as Melee" then seen = true end end
    eq(seen, true, "the class's default until their talents are in")
    eq(#wow.timers, 1, "still trying for the talents")
    -- The talents arrive: the retry settles it, and no timer is left.
    their.valid = true
    runTimers()
    eq(runs, 2)
    back.scripts.OnEnter(back)
    seen = false
    for _, line in ipairs(GameTooltip.lines) do if line[1] == "Judged as Tank" then seen = true end end
    eq(seen, true)
    eq(#wow.timers, 0)
    -- A link that never arrives: 5 retries, then it stops, and still no anvil anywhere.
    links[10] = nil
    runs = 0
    inspectReady(their.guid)
    eq(back:IsShown(), false, "the earlier anvils go while it's unknown")
    local tries = 0
    for _ = 1, 20 do
        if #wow.timers > 0 then tries = tries + 1 end
        runTimers()
    end
    eq(tries, 5)
    eq(#wow.timers, 0)
    eq(runs, 0, "never judged with a slot unknown")
    eq(ns.CraftGlyph(InspectHandsSlot), nil, "and never an empty-slot anvil for the gloves they wear")
    eq(back:IsShown(), false)
end)

test("an inspected player's spec comes from the inspect config's points per tab", function()
    local ns, _, _, their = inspectStart()
    eq(select(2, ns.InspectSpec()), true)
    eq(ns.InspectSpec(), 3)
    their.talents = { { 0, 7 }, { 3000, 2 }, { 6000, 0 } }
    eq(ns.InspectSpec(), nil, "under 10 points: no spec yet")
    eq(select(2, ns.InspectSpec()), true, "but read")
    their.talents = { { 0, 11 }, { 3000, 2 }, { 6000, 0 } }
    eq(ns.InspectSpec(), 1)
    their.valid = false
    eq(select(2, ns.InspectSpec()), false, "not in yet")
    C_Traits.HasValidInspectData = nil
    eq(select(2, ns.InspectSpec()), false, "a client without it")
end)
