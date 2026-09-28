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

test("a shortcut button on the game's bags and bank (and ElvUI's, EllesmereUI's) opens the window there", function()
    local ns = wow.load(FILES)
    wow.ns = ns
    CreateFrame("Frame", "ContainerFrameCombinedBags")
    CreateFrame("Frame", "EUI_MainBagFrame")
    wow.login(nil)
    wow.fire("PLAYER_ENTERING_WORLD")
    local s = ns.BagShortcuts()
    local bags = s.ContainerFrameCombinedBags
    assert(bags and s.EUI_MainBagFrame, "attached to the bag windows that exist")
    eq(bags.parent, ContainerFrameCombinedBags, "shows and hides with the bags")
    eq(bags.point[1], "TOPRIGHT", "outside the window's left edge, clear of its contents")
    eq(bags.point[3], "TOPLEFT")
    eq(s.BankFrame, nil, "no bank window yet")
    bags.scripts.OnEnter(bags)
    eq(GameTooltip.lines[2][1], "Every character's bags")
    bags.scripts.OnClick(bags)
    eq(AltsForeverBagsFrame:IsShown(), true)
    bags.scripts.OnClick(bags)
    eq(AltsForeverBagsFrame:IsShown(), true, "a second click leaves it open")
    -- The bank window appears on the first visit.
    CreateFrame("Frame", "BankFrame")
    wow.fire("BANKFRAME_OPENED")
    local bank = s.BankFrame
    assert(bank, "attached when the bank opens")
    bank.scripts.OnClick(bank)
    eq(AltsForeverBagsFrame.bank.highlightLocked, true, "opened on the bank")
    -- Opening the bags later catches windows made after login.
    CreateFrame("Frame", "ElvUI_ContainerFrame")
    ToggleAllBags()
    assert(s.ElvUI_ContainerFrame, "ElvUI's bags too")
end)
