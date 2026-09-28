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
    wow.login(nil)
    local layout = ns.char.layout
    eq(table.concat(layout[0], ","), "100020,0,200001,0", "item * 1000 + count, 0 for empty")
    eq(table.concat(layout[1], ","), "0,100005")
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

test("the bank view has a button per tab, and the dropdown switches character", function()
    local ns = wow.load(FILES)
    wow.ns = ns
    wow.login({ v = 2, chars = {
        ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { level = 20, bank = { [500] = 40 }, bags = { [600] = 1 } }),
        ["Old Timer"] = alt("Old Timer", "MAGE", { level = 10, bags = {} }),
    } })
    wow.setBag(6, 2, { [1] = { 400, 2 } })
    wow.setBag(7, 3, { [3] = { 401, 1 } })
    wow.fire("BANKFRAME_OPENED")
    SlashCmdList.ALTSFOREVER("bank")
    local f = AltsForeverBagsFrame
    eq(bagsGrid(), "400x2 -")
    local tabs = f.tabs
    eq(tabs[1].text, "Tab 1")
    eq(tabs[1]:IsShown(), true); eq(tabs[2]:IsShown(), true); eq(tabs[3]:IsShown(), false)
    tabs[2].scripts.OnClick(tabs[2])
    eq(bagsGrid(), "- - 401x1")
    eq(f.info.text, "2 of 3 slots free")
    assert(f.seen.text:find("Bank last visited", 1, true), f.seen.text)
    -- The dropdown lists every character; an alt seen before slots were recorded shows totals.
    f.who.scripts.OnClick(f.who)
    eq(#wow.menu.items, 3)
    local tarn = wow.menuItem("[DRUID]Tarn Moon")
    eq(tarn.isSelected(tarn.data), false)
    tarn.setSelected(tarn.data)
    eq(bagsGrid(), "500x40", "one slot per item, with its total")
    assert(f.info.text:find("Totals only", 1, true), f.info.text)
    eq(tabs[1]:IsShown(), false, "no tabs without slots")
    f.bags.scripts.OnClick(f.bags)
    eq(bagsGrid(), "600x1")
    -- Nothing recorded: says what to do.
    ns.ShowBags("Old Timer", "bank")
    eq(f.empty:IsShown(), true)
    assert(f.empty.text:find("Visit the bank", 1, true), f.empty.text)
    eq(f.info.text, "")
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
