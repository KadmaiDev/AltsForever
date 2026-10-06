-- Tests: Forever's Gamepad UI (controller). Loaded by tests/run.lua.

-- The focus manager calls recorded since the last check, as "shown Name" / "hidden Name".
function focusCalls()
    local out = {}
    for _, call in ipairs(wow.focus) do out[#out + 1] = call[1] .. " " .. (call[2]:GetName() or "?") end
    wow.focus = {}
    return table.concat(out, ", ")
end

test("with the Gamepad UI on, our windows report to Blizzard's focus manager, and B closes them", function()
    local ns = wow.load(FILES)
    wow.login({ v = 2, chars = { ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { level = 20, reps = {}, bags = {} }) } })
    wow.gamepadUI = true
    wow.focus = {}
    ns.ToggleOverview()
    ns.ShowBags(nil, "bags")
    ns.ToggleReputation()
    ns.ShowGear("Tarn Moon")
    ns.OpenIconPicker("bags")
    eq(focusCalls(), "shown AltsForeverFrame, shown AltsForeverBagsFrame, shown AltsForeverRepFrame, shown AltsForeverGearFrame, shown AltsForeverIconPicker")
    -- B: Blizzard calls the window's close handler.
    local bags = AltsForeverBagsFrame
    eq(bags:SmartNavigationCloseHandler(), true, "handled")
    eq(bags:IsShown(), false)
    eq(focusCalls(), "hidden AltsForeverBagsFrame")
end)

test("mouse and keyboard players: nothing reports to the focus manager", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    wow.focus = {}
    ns.ToggleOverview()
    ns.ShowBags(nil, "bags")
    AltsForeverFrame:Hide()
    eq(focusCalls(), "")
end)

test("in combat a window opens without focus (Blizzard's bindings can't be changed then)", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    wow.gamepadUI, wow.inCombat = true, true
    wow.focus = {}
    ns.ToggleOverview()
    eq(AltsForeverFrame:IsShown(), true)
    AltsForeverFrame:Hide()
    eq(focusCalls(), "", "never reported, so never un-reported")
    wow.inCombat = nil
end)

test("A on an overview row opens that character's menu: Gear, Bags, Bank, Upgrade role, Forget", function()
    local ns = wow.load(FILES)
    wow.login({ v = 2, chars = { ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { level = 20, bags = {} }) } })
    ns.ToggleOverview()
    local row = overviewRows()[2]
    eq(row.key, "Tarn Moon")
    row:OnSmartNavClick()
    local texts = {}
    for _, item in ipairs(wow.menu.items) do texts[#texts + 1] = item.text end
    eq(table.concat(texts, " | "), "[DRUID]Tarn Moon | Gear | Bags | Bank | Upgrade role | Forget Tarn Moon...")
    wow.menuItem("Gear").fn()
    eq(AltsForeverGearFrame:IsShown(), true)
end)

test("lists a controller can't scroll get page buttons; hover-only rows can be reached", function()
    local ns = wow.load(FILES)
    local reps, names = {}, {}
    for id = 1, 25 do reps[id], names[id] = 100, "Faction " .. id end
    wow.login({ v = 2, factions = names, chars = { ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { level = 20, reps = reps }) } })
    ns.ToggleReputation()
    local f = AltsForeverRepFrame
    eq(f.up:IsShown(), true); eq(f.down:IsShown(), true)
    eq(f.up.enabled, false, "at the top")
    f.down.scripts.OnClick(f.down)
    assert(f.footer.text:find("6-25 of 25", 1, true), f.footer.text) -- the last full page
    eq(f.up.enabled, true)
    eq(f.down.enabled, false, "at the end")
    eq(ns.GamepadFocusable ~= nil, true)
    local row
    for _, child in ipairs(wow.frames) do if child.parent == f and child.name and child.faction ~= nil then row = child break end end
    eq(row.smartNavigationCanFocus, true, "a row with only a tooltip can be focused")
    -- The icon picker pages too.
    ns.OpenIconPicker("bank")
    local p = AltsForeverIconPicker
    p.itemTab.scripts.OnClick(p.itemTab)
    eq(p.grid[1].value, 133001)
    p.pageDown.scripts.OnClick(p.pageDown)
    eq(p.grid[1].value, 133085, "a page of 7 rows of 12")
    p.pageUp.scripts.OnClick(p.pageUp)
    eq(p.grid[1].value, 133001)
end)

test("the bags window: focus moving onto a slot scrolls it into view; the resize grip is skipped", function()
    local ns = wow.load(FILES)
    for bag = 6, 8 do wow.setBag(bag, 98, {}) end
    wow.login(nil)
    wow.fire("BANKFRAME_OPENED")
    ns.ShowBags(nil, "bank")
    local f = AltsForeverBagsFrame
    eq(f.grip.smartNavigationIgnored, true)
    local last = f.slots[294]
    last.scripts.OnEnter(last)
    eq(f.content.point[5], 0, "mouse: hovering doesn't scroll")
    wow.gamepadUI = true
    last.scripts.OnEnter(last)
    local visible = f.holder:GetHeight()
    eq(f.content.point[5], last.top + 36 - visible, "scrolled so the last slot is just in view")
    local first = f.slots[1]
    first.scripts.OnEnter(first)
    eq(f.content.point[5], 0, "back to the top, heading included")
end)

test("key bindings: open the overview and the bags window (for a controller button or macro)", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    local xml = assert(io.open("Bindings.xml")):read("*a")
    assert(xml:find('AltsForever_Binding("overview")', 1, true) and xml:find('AltsForever_Binding("bags")', 1, true))
    eq(BINDING_HEADER_ALTSFOREVER, "Alts Forever")
    eq(BINDING_NAME_ALTSFOREVER_OVERVIEW, "Open overview")
    AltsForever_Binding("overview")
    eq(AltsForeverFrame:IsShown(), true)
    AltsForever_Binding("bags")
    eq(AltsForeverBagsFrame:IsShown(), true)
    local release = assert(io.open("tools/release.py")):read("*a")
    assert(release:find('"Bindings.xml"', 1, true), "shipped in the release zip")
end)

test("with the Gamepad UI on at login (or switched on), the Options page is built while closed", function()
    local ns = wow.load(FILES)
    wow.gamepadUI = true
    wow.login(nil)
    eq(ns.OptionsPanel().built, true, "built at login")
    ns = wow.load(FILES)
    wow.gamepadUI = false
    wow.login(nil)
    eq(ns.OptionsPanel().built, nil, "mouse: built when first shown, as before")
    wow.gamepadUI = true
    wow.fire("INPUT_DEVICE_INTERFACE_TRANSITION", 1, 0)
    eq(ns.OptionsPanel().built, true, "switched on: built then")
end)
