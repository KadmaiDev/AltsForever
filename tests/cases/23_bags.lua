-- Tests: each bag's and bank tab's slots, and the bags window. Loaded by tests/run.lua.

-- The slots on show in the bags window, as "id x count" or "-" for an empty slot.
function bagsGrid()
    local out = {}
    local ids, counts, n = wow.ns.BagsShown()
    for i = 1, n do out[i] = ids[i] and (ids[i] .. "x" .. counts[i]) or "-" end
    return table.concat(out, " ")
end

test("scans record each bag's and bank tab's slots, reusing the same tables", function()
    local ns = wow.load(FILES)
    wow.setBag(0, 4, { [1] = { 100, 20 }, [3] = { 200, 1 } })
    wow.setBag(1, 2, { [2] = { 100, 5 } })
    wow.inventory[31] = 4245
    wow.login(nil)
    local layout = ns.char.layout
    eq(table.concat(layout[0], ","), "100020,0,200001,0", "item * 1000 + count, 0 for empty")
    eq(table.concat(layout[1], ","), "0,100005")
    eq(layout[1][0], 4245, "the bag item itself, for its name")
    eq(layout[0][0], nil, "the backpack isn't an item")
    eq(layout[2], nil, "no bag in that slot: nothing stored")
    eq(ns.char.bags[100], 25, "the counts tooltips use are unchanged")
    eq(ns.char.bank, nil); eq(ns.char.bankAt, nil)
    local backpack = layout[0]
    -- A smaller bag, and a bag taken off.
    wow.setBag(0, 2, { [2] = { 300, 1 } })
    wow.setBag(1, 0, {})
    bagsChanged(0)
    eq(layout[0], backpack, "the same table, refilled")
    eq(table.concat(layout[0], ","), "0,300001")
    eq(layout[1], nil)
    -- The bank: each tab, when the bank is open.
    wow.now = 1000000
    wow.setBag(6, 3, { [1] = { 400, 2 } })
    wow.setBag(7, 2, {})
    wow.fire("BANKFRAME_OPENED")
    eq(table.concat(layout[6], ","), "400002,0,0")
    eq(table.concat(layout[7], ","), "0,0")
    eq(layout[8], nil, "a tab not bought")
    eq(ns.char.bankAt, 1000000)
    eq(ns.SlotValue(100, 1500), 100999, "a stack over 999 is capped rather than spilling into the ID")
    wow.now = nil
end)

test("the bags window shows a character's bags slot by slot, with free slots and a quality border", function()
    local ns = wow.load(FILES)
    wow.ns = ns
    wow.setBag(0, 4, { [1] = { 100, 20 }, [3] = { 200, 1 } })
    wow.itemQuality[200] = 3
    wow.itemQuality[100] = 1
    wow.login(nil)
    SlashCmdList.ALTSFOREVER("bags")
    local f = AltsForeverBagsFrame
    eq(f:IsShown(), true)
    eq(bagsGrid(), "100x20 - 200x1 -")
    eq(f.info.text, "2 of 4 slots free")
    eq(f.who.text, ns.ColoredName(ns.charKey, ns.char))
    eq(f.empty:IsShown(), false)
    -- Rare gets a blue border; common none.
    local rare, linen = f.slots[3], f.slots[1]
    eq(rare.border:IsShown(), true); eq(linen.border:IsShown(), false)
    eq(linen.count.text, 20); eq(rare.count.text, "")
    -- Hover: the item's own tooltip; shift-click links it.
    rare.scripts.OnEnter(rare)
    eq(GameTooltip.itemID, 200)
    wow.itemLinks = { [200] = "|Hitem:200|h[Rare]|h" }
    wow.modified = true
    rare.scripts.OnClick(rare)
    eq(wow.chatLinks[#wow.chatLinks], "|Hitem:200|h[Rare]|h")
    wow.modified = nil
    -- Bags change while it's open: it follows.
    wow.setBag(0, 4, { [2] = { 100, 3 } })
    bagsChanged(0)
    eq(bagsGrid(), "- 100x3 - -")
    -- The same again closes it.
    SlashCmdList.ALTSFOREVER("bags")
    eq(f:IsShown(), false)
end)

-- The section headings on show.
function bagsHeadings()
    local out = {}
    for _, h in ipairs(AltsForeverBagsFrame.headers) do
        if h:IsShown() then out[#out + 1] = h.text end
    end
    return table.concat(out, " | ")
end

test("all in one or by bag (remembered), bank tabs as sections, and money at the bottom", function()
    local ns = wow.load(FILES)
    wow.ns = ns
    wow.login({ v = 2, chars = {
        ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { level = 20, bank = { [500] = 40 }, bags = { [600] = 1 }, money = 12345 }),
        ["Old Timer"] = alt("Old Timer", "MAGE", { level = 10, bags = {} }),
    } })
    wow.setBag(0, 2, { [1] = { 100, 1 } })
    wow.setBag(1, 2, { [2] = { 101, 1 } })
    wow.inventory[31] = 4245
    wow.itemNames[4245] = "Red Linen Bag"
    wow.setBag(6, 2, { [1] = { 400, 2 } })
    wow.setBag(7, 3, { [3] = { 401, 1 } })
    bagsChanged(0)
    wow.fire("BANKFRAME_OPENED")
    SlashCmdList.ALTSFOREVER("bags")
    local f = AltsForeverBagsFrame
    eq(f.split:GetChecked(), false, "all in one by default")
    eq(bagsHeadings(), "Bags|cff9d9d9d  (2 / 4)|r")
    eq(bagsGrid(), "100x1 - - 101x1")
    f.split:SetChecked(true)
    f.split.scripts.OnClick(f.split)
    eq(AltsForeverDB.bagsSplit, true, "remembered")
    eq(bagsHeadings(), "Backpack|cff9d9d9d  (1 / 2)|r | Red Linen Bag|cff9d9d9d  (1 / 2)|r")
    f.bank.scripts.OnClick(f.bank)
    eq(bagsHeadings(), "Tab 1|cff9d9d9d  (1 / 2)|r | Tab 2|cff9d9d9d  (1 / 3)|r")
    eq(bagsGrid(), "400x2 - - - 401x1")
    eq(f.info.text, "3 of 5 slots free")
    assert(f.seen.text:find("Bank last visited", 1, true), f.seen.text)
    eq(f.money.text, ns.char.money .. "c")
    -- The dropdown lists every character; an alt seen before slots were recorded shows totals.
    f.who.scripts.OnClick(f.who)
    eq(#wow.menu.items, 3)
    local tarn = wow.menuItem("[DRUID]Tarn Moon")
    eq(tarn.isSelected(tarn.data), false)
    tarn.setSelected(tarn.data)
    eq(bagsGrid(), "500x40", "one slot per item, with its total")
    eq(bagsHeadings(), "Bank|cff9d9d9d   Totals only: visit the bank on this character to see its slots.|r",
        "the note beside the heading, not in the bottom row where it ran into Last seen")
    eq(f.info.text, "")
    eq(f.money.text, "12345c")
    f.bags.scripts.OnClick(f.bags)
    eq(bagsGrid(), "600x1")
    -- Nothing recorded: says what to do.
    ns.ShowBags("Old Timer", "bank")
    eq(f.empty:IsShown(), true)
    assert(f.empty.text:find("Visit the bank", 1, true), f.empty.text)
    eq(f.info.text, "")
    eq(f.money.text, "")
end)

test("a tall bank scrolls instead of growing past the screen", function()
    local ns = wow.load(FILES)
    wow.ns = ns
    for bag = 6, 8 do wow.setBag(bag, 98, {}) end
    wow.login(nil)
    wow.fire("BANKFRAME_OPENED")
    ns.ShowBags(nil, "bank")
    local f = AltsForeverBagsFrame
    local before = f.content.point
    assert(f.holder:GetHeight() <= 560, f.holder:GetHeight())
    f.scripts.OnMouseWheel(f, -1)
    assert(f.content.point[5] > 0, "scrolled down")
    f.scripts.OnMouseWheel(f, 100)
    eq(f.content.point[5], 0, "not past the top")
end)

test("the bags window opens from the overview's button, a character's menu and /af bank Name", function()
    local ns = wow.load(FILES)
    wow.ns = ns
    wow.login({ v = 2, chars = { ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { level = 20, bank = { [500] = 40 } }) } })
    ns.ToggleOverview(true)
    local o = AltsForeverFrame
    o.bagsButton.scripts.OnClick(o.bagsButton)
    eq(AltsForeverBagsFrame:IsShown(), true)
    AltsForeverBagsFrame:Hide()
    ns.ShowCharacterMenu(o, "Tarn Moon")
    wow.menuItem("Bank").fn()
    eq(bagsGrid(), "500x40")
    SlashCmdList.ALTSFOREVER("bank nobody")
    eq(wow.printed[#wow.printed]:find("No character named 'nobody'", 1, true) ~= nil, true)
    SlashCmdList.ALTSFOREVER("bags tarn moon")
    eq(AltsForeverBagsFrame.bags ~= nil, true)
end)

test("an item whose quality isn't loaded yet is requested and the window fills again", function()
    local ns = wow.load(FILES)
    wow.ns = ns
    wow.setBag(0, 1, { [1] = { 700, 1 } })
    wow.login(nil)
    wow.itemLoads = {}
    ns.ShowBags(nil, "bags")
    eq(wow.itemLoads[1], 700)
end)

-- Opens one of Blizzard's menus that addons add to (by its tag) and returns it.
function openBlizzardMenu(tag)
    return MenuUtil.CreateContextMenu(nil, function(owner, root) wow.menuMods[tag](owner, root) end)
end

test("shortcuts: Blizzard's bag menus get an entry; the bank, ElvUI and EllesmereUI a button in their header", function()
    local ns = wow.load(FILES)
    wow.ns = ns
    -- EllesmereUI's bags header: its bags button (internal field) sits left of sort and search.
    local eui = CreateFrame("Frame", "EUI_MainBagFrame")
    local header = CreateFrame("Frame", nil, eui)
    eui._bagsBtn = CreateFrame("Button", nil, header)
    CreateFrame("Frame", "ElvUI_ContainerFrame")
    wow.login(nil)
    wow.fire("PLAYER_ENTERING_WORLD")
    -- Blizzard's bags, combined and separate: an entry in the portrait menu, no button.
    for _, tag in ipairs({ "MENU_CONTAINER_FRAME_COMBINED", "MENU_CONTAINER_FRAME" }) do
        openBlizzardMenu(tag)
        local entry = wow.menuItem("Alts Forever: every character's bags")
        assert(entry, tag)
        eq(entry.fn(), nil, "returns nothing, so the menu closes")
        eq(AltsForeverBagsFrame:IsShown(), true)
        eq(AltsForeverBagsFrame.bags.highlightLocked, true, "on the bags")
    end
    local s = ns.BagShortcuts()
    local e = s.EUI_MainBagFrame
    eq(e.parent, header, "in EllesmereUI's header")
    eq(e.point[1], "RIGHT"); eq(e.point[2], eui._bagsBtn); eq(e.point[3], "LEFT")
    eq(e.icon.texture, "Interface\\AddOns\\AltsForever\\media\\logo.tga", "the logo with its gold ring, like EllesmereUI's buttons")
    eq(e.icon.alpha, 0.9)
    e.scripts.OnEnter(e)
    eq(e.icon.alpha, 1, "brightens on hover")
    e.scripts.OnLeave(e)
    eq(e.icon.alpha, 0.9)
    local elv = s.ElvUI_ContainerFrame
    eq(elv.parent, ElvUI_ContainerFrame)
    eq(elv.icon.texture, "Interface\\AddOns\\AltsForever\\media\\icon.tga", "square elsewhere: the ringless logo")
    eq(elv.point[1], "TOPLEFT", "inside ElvUI's top-left corner")
    eq(elv.point[4] > 0 and elv.point[5] < 0, true)
    elv.scripts.OnEnter(elv)
    eq(GameTooltip.lines[2][1], "Every character's bags")
    eq(s.BankFrame, nil, "no bank window yet")
    -- Blizzard's bank, made on the first visit: left of its search box.
    CreateFrame("Frame", "BankFrame")
    CreateFrame("EditBox", "BankItemSearchBox", BankFrame)
    wow.fire("BANKFRAME_OPENED")
    local bank = s.BankFrame
    assert(bank, "attached when the bank opens")
    eq(bank.point[2], BankItemSearchBox)
    AltsForeverBagsFrame:Hide()
    bank.scripts.OnClick(bank)
    eq(AltsForeverBagsFrame:IsShown(), true)
    eq(AltsForeverBagsFrame.bank.highlightLocked, true, "opened on the bank")
    bank.scripts.OnClick(bank)
    eq(AltsForeverBagsFrame:IsShown(), true, "a second click leaves it open")
    -- EllesmereUI's bank, found later (opening bags checks again): left of its sort button.
    local euiBank = CreateFrame("Frame", "EUI_BankFrame")
    euiBank._searchBox = CreateFrame("EditBox", nil, CreateFrame("Frame", nil, euiBank))
    ToggleAllBags()
    eq(s.EUI_BankFrame.point[2], euiBank._searchBox)
    eq(s.ContainerFrameCombinedBags, nil, "never a button outside a window")
end)

test("the bags window resizes: width sets the columns, height how tall before it scrolls; both remembered", function()
    local ns = wow.load(FILES)
    wow.ns = ns
    wow.setBag(0, 20, {})
    for bag = 6, 8 do wow.setBag(bag, 98, {}) end
    wow.login(nil)
    ns.ShowBags(nil, "bags")
    local f = AltsForeverBagsFrame
    local function place(i) return f.slots[i].point[4], f.slots[i].point[5] end
    eq(f:GetWidth(), 12 * 2 + 14 * 39 - 3, "14 columns to start")
    eq(select(2, place(15)), -20 - 39, "slot 15 starts the second row")
    -- Drag the grip narrower: the grid reflows as soon as fewer columns fit.
    f.grip.scripts.OnMouseDown(f.grip)
    f:SetWidth(12 * 2 + 10 * 39 - 3 + 5)
    f:SetHeight(300)
    f.scripts.OnSizeChanged(f, f:GetWidth(), 300)
    eq(select(2, place(11)), -20 - 39, "10 columns: slot 11 starts the second row")
    eq(f:GetHeight(), 300, "the height follows the drag")
    f.grip.scripts.OnMouseUp(f.grip)
    eq(AltsForeverDB.bagsCols, 10)
    eq(AltsForeverDB.bagsHeight, 300 - 60 - 34)
    eq(f:GetWidth(), 12 * 2 + 10 * 39 - 3, "snapped to whole slots")
    eq(f:GetHeight(), 60 + 3 * 39 + 34, "20 slots fit: the window shrinks to them (never below 3 rows)")
    -- The bank is taller than the chosen height: it scrolls at that height.
    wow.fire("BANKFRAME_OPENED")
    ns.ShowBags(nil, "bank")
    eq(f.holder:GetHeight(), 300 - 60 - 34)
    -- Remembered after a reload.
    local saved = AltsForeverDB
    ns = wow.load(FILES)
    wow.ns = ns
    wow.login(saved)
    ns.ShowBags(nil, "bags")
    eq(AltsForeverBagsFrame:GetWidth(), 12 * 2 + 10 * 39 - 3)
    -- Dragging back to 14 forgets the setting.
    f = AltsForeverBagsFrame
    f.grip.scripts.OnMouseDown(f.grip)
    f:SetWidth(12 * 2 + 14 * 39 - 3)
    f.scripts.OnSizeChanged(f, f:GetWidth(), f:GetHeight())
    f.grip.scripts.OnMouseUp(f.grip)
    eq(AltsForeverDB.bagsCols, nil)
end)

test("our windows come to the front when opened or clicked, so they never draw through each other", function()
    local ns = wow.load(FILES)
    wow.ns = ns
    wow.login({ v = 2, chars = { ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { level = 20, reps = {} }) } })
    ns.ToggleOverview(true)
    ns.ShowBags(nil, "bags")
    ns.ToggleReputation()
    ns.ShowGear("Tarn Moon")
    for _, name in ipairs({ "AltsForeverFrame", "AltsForeverBagsFrame", "AltsForeverRepFrame", "AltsForeverGearFrame" }) do
        local f = _G[name]
        eq(f.toplevel, true, name .. ": raised when clicked")
        assert((f.raised or 0) > 0, name .. ": raised when opened")
    end
end)
