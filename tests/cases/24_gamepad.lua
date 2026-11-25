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
    eq(focusCalls(), "shown AltsForeverFrame, shown AltsForeverBagsFrame, shown AltsForeverRepFrame, shown AltsForeverCharacterFrame, shown AltsForeverIconPicker")
    -- B: Blizzard calls the window's close handler.
    local bags = AltsForeverBagsFrame
    eq(bags:SmartNavigationCloseHandler(), true, "handled")
    eq(bags:IsShown(), false)
    eq(focusCalls(), "hidden AltsForeverBagsFrame")
end)

test("with the Gamepad UI on, the search reports to the focus manager, B closes it, and it pages without a wheel", function()
    local ns = wow.load(FILES)
    wow.login({ v = 2, chars = { ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { level = 20, bags = {} }) } })
    wow.gamepadUI = true
    wow.focus = {}
    ns.ToggleSearch()
    local f = AltsForeverSearchFrame
    eq(focusCalls(), "shown AltsForeverSearchFrame")
    assert(f.up and f.down, "page buttons for a controller")
    eq(f:SmartNavigationCloseHandler(), true, "handled")
    eq(f:IsShown(), false)
    eq(focusCalls(), "hidden AltsForeverSearchFrame")
end)

test("with the Gamepad UI on, the export reports to the focus manager and B closes it", function()
    local ns = wow.load(FILES)
    wow.login({ v = 2, chars = { ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { level = 20, bags = {} }) } })
    wow.gamepadUI = true
    wow.focus = {}
    ns.ToggleExport()
    local f = AltsForeverExportFrame
    eq(focusCalls(), "shown AltsForeverExportFrame")
    eq(f:SmartNavigationCloseHandler(), true, "handled")
    eq(f:IsShown(), false)
    eq(focusCalls(), "hidden AltsForeverExportFrame")
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

test("A on an overview row opens that character's menu: Gear, Bags, Bank, Professions, Upgrade role, Forget", function()
    local ns = wow.load(FILES)
    wow.login({ v = 2, chars = { ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { level = 20, bags = {} }) } })
    ns.ToggleOverview()
    local row = overviewRows()[2]
    eq(row.key, "Tarn Moon")
    row:OnSmartNavClick()
    local texts = {}
    for _, item in ipairs(wow.menu.items) do texts[#texts + 1] = item.text end
    eq(table.concat(texts, " | "), "[DRUID]Tarn Moon | Character | Reputation | Skills | Bags | Bank | Mail | Professions | Upgrade role | Upgrade weights... | Pin to top | Forget Tarn Moon...")
    wow.menuItem("Character").fn()
    eq(AltsForeverCharacterFrame:IsShown(), true)
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

test("key bindings: the overview, bags window and search, in their own Alts Forever section", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    local xml = assert(io.open("Bindings.xml")):read("*a")
    for _, which in ipairs({ "overview", "bags", "search" }) do
        assert(xml:find('AltsForever_Binding("' .. which .. '")', 1, true), which)
    end
    -- Every binding in our own section, not untitled under AddOns.
    local bindings, ours = 0, 0
    for attrs in xml:gmatch("<Binding (.-)>") do
        bindings = bindings + 1
        if attrs:find('category="Alts Forever"', 1, true) then ours = ours + 1 end
    end
    eq(bindings, 3)
    eq(ours, 3)
    eq(BINDING_NAME_ALTSFOREVER_OVERVIEW, "Open overview")
    eq(BINDING_NAME_ALTSFOREVER_SEARCH, "Search your characters")
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

-- The controller menu's entries from the top: { text, row (nil for a title) }.
function padMenu(ns)
    local m, items = ns.GamepadMenu(), {}
    for _, r in ipairs(m.rows) do
        if r.shown then items[#items + 1] = { y = r.point[5], text = r.text:GetText(), row = r } end
    end
    for _, l in ipairs(m.labels) do
        if l.shown then items[#items + 1] = { y = l.point[5], text = l:GetText() } end
    end
    table.sort(items, function(a, b) return a.y > b.y end)
    return items
end

function padRow(ns, text)
    for _, it in ipairs(padMenu(ns)) do
        if it.row and it.text:find(text, 1, true) then return it.row end
    end
end

test("with the Gamepad UI on, a menu of ours is our own window, never the game's", function()
    local ns = wow.load(FILES)
    wow.gamepadUI = true
    wow.login({ v = 2, chars = { ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { level = 20, bags = {} }) } })
    ns.ToggleOverview()
    local row = overviewRows()[2]
    wow.menu = nil
    row:OnSmartNavClick()
    eq(wow.menu, nil, "the game's menu never opens: it would carry our entries into Blizzard's controller code")
    local m = ns.GamepadMenu()
    eq(m:IsShown(), true)
    eq(m.TitleText:GetText(), "Alts Forever", "the first list's title")
    local items = padMenu(ns)
    eq(items[1].text, "[DRUID]Tarn Moon", "the title first")
    eq(items[1].row, nil, "a title can't be pressed")
    eq(items[2].text, "Character")
    eq(padRow(ns, "Professions"):IsEnabled(), false, "no professions: greyed out")
    assert(padRow(ns, "Upgrade role").text:GetText():find("ChatFrameExpandArrow", 1, true), "a sub-list is marked")

    -- A sub-list: Back first; B steps back out of it, then closes the menu.
    padRow(ns, "Upgrade role").scripts.OnClick(padRow(ns, "Upgrade role"))
    eq(m.TitleText:GetText(), "Upgrade role")
    assert(padMenu(ns)[1].row.back, "Back first")
    assert(padRow(ns, "Automatic").text:GetText():find("UI-RadioButton", 1, true), "radio choices")
    eq(m:SmartNavigationCloseHandler(), true)
    eq(m:IsShown(), true, "B: back to the first list")
    assert(padRow(ns, "Character"))
    padRow(ns, "Upgrade role").scripts.OnClick(padRow(ns, "Upgrade role"))
    local tank = padRow(ns, "Healer")
    tank.scripts.OnClick(tank)
    eq(m:IsShown(), false, "a radio choice closes it")
    eq(AltsForeverDB.chars["Tarn Moon"].role, "healer", "and was chosen")

    row:OnSmartNavClick()
    m:SmartNavigationCloseHandler()
    eq(m:IsShown(), false, "B on the first list closes it")
    row:OnSmartNavClick()
    padRow(ns, "Character").scripts.OnClick(padRow(ns, "Character"))
    eq(m:IsShown(), false)
    eq(AltsForeverCharacterFrame:IsShown(), true, "a button does its job")

    -- Tick boxes stay open and show the change; mouse players get the game's menu as ever.
    ns.ShowOptionsMenu(nil, true)
    local sub = padRow(ns, "Other rulesets and factions")
    sub.scripts.OnClick(sub)
    local tick = padRow(ns, "Show in tooltips")
    assert(tick.text:GetText():find("UI-CheckBox-Up", 1, true), "not ticked")
    tick.scripts.OnClick(tick)
    eq(AltsForeverDB.otherRulesets, true)
    eq(m:IsShown(), true, "a tick box leaves the menu open")
    assert(padRow(ns, "Show in tooltips").text:GetText():find("UI-CheckBox-Check", 1, true), "now ticked")
    m:Hide()
    wow.gamepadUI = false
    ns.ShowOptionsMenu(nil, true)
    assert(wow.menu, "mouse and keyboard: the game's menu")
    eq(m:IsShown(), false)
end)

test("menus: every one goes through ns.OpenMenu (the game's menu only for mouse and keyboard)", function()
    for _, file in ipairs(FILES) do
        if file:match("%.lua$") and file ~= "Gamepad.lua" then
            local text = assert(io.open(file)):read("*a")
            assert(not text:find("MenuUtil.CreateContextMenu(", 1, true), file .. " opens the game's menu itself")
            assert(not text:find("[^%w_]SetupMenu%(FilterMenu%)"), file .. " hands a dropdown our menu directly")
        end
    end
end)

test("with the Gamepad UI on, the professions window's filter is a plain button opening our menu", function()
    local ns = wow.load(FILES)
    wow.gamepadUI = true
    wow.login({ v = 2, chars = { ["Vesp Ash"] = alt("Vesp Ash", "PALADIN", { profs = { Cooking = 50 }, recipes = { Cooking = {} } }) } })
    ns.ShowRecipes("Vesp Ash")
    local f = AltsForeverCharacterFrame
    eq(f:IsShown(), true)
    eq(f.padFilter:IsShown(), true, "our button")
    eq(f.filter:IsShown(), false, "not the game's dropdown")
    wow.menu = nil
    f.padFilter.scripts.OnClick(f.padFilter)
    eq(wow.menu, nil)
    eq(ns.GamepadMenu():IsShown(), true)
    eq(#padMenu(ns), 2, "its two tick boxes")
    wow.menu = nil
    MenuUtil.CreateContextMenu(f.filter, f.filter.menuGenerator)
    eq(#wow.menu.items, 0, "the game's dropdown gets nothing of ours, should it be opened anyway")
    ns.GamepadMenu():Hide()
    f:Hide()
    wow.gamepadUI = false
    ns.ShowRecipes("Vesp Ash")
    eq(f.filter:IsShown(), true, "mouse: the game's dropdown")
    MenuUtil.CreateContextMenu(f.filter, f.filter.menuGenerator)
    eq(#wow.menu.items, 2, "with its two tick boxes")
    -- Switched with the window open: the buttons follow at once.
    wow.gamepadUI = true
    wow.fire("INPUT_DEVICE_INTERFACE_TRANSITION", 1, 0)
    eq(f:IsShown(), true)
    eq(f.padFilter:IsShown(), true, "open window, Gamepad UI on: our button")
    eq(f.filter:IsShown(), false)
    wow.gamepadUI = false
    wow.fire("INPUT_DEVICE_INTERFACE_TRANSITION", 0, 1)
    eq(f.filter:IsShown(), true, "and back")
    eq(f.padFilter:IsShown(), false)
    eq(f.padFilter:IsShown(), false)
end)

test("with the Gamepad UI on, our parts of the mailbox are made at login, not inside the open mailbox", function()
    local ns = wow.load(FILES)
    wow.gamepadUI = true
    SendMailFrame:Hide() -- the mailbox closed, as at login
    wow.login(nil)
    local arrow = altsButton()
    assert(arrow, "the arrow beside the To box, made at login")
    eq(arrow:IsShown(), true)
    assert(mailNote() and packButton(), "the rule note and Pack too")
    eq(mailNote():IsShown(), false); eq(packButton():IsShown(), false)
    local frames = #wow.frames
    SendMailFrame:Show()
    wow.fire("MAIL_SHOW")
    eq(#wow.frames, frames, "opening the mailbox makes no frame")
    eq(altsButton(), arrow)

    -- "Send mail to alts" off: made all the same, hidden until it's turned on.
    local saved = { v = 2, chars = {}, sendToAltOff = true }
    ns = wow.load(FILES)
    wow.gamepadUI = true
    SendMailFrame:Hide()
    wow.login(saved)
    eq(altsButton():IsShown(), false)
    ns.SetSendToAlt(true)
    eq(altsButton():IsShown(), true)

    -- Mouse and keyboard: made at the first MAIL_SHOW, as before.
    wow.load(FILES)
    wow.gamepadUI = false
    wow.login(nil)
    eq(altsButton(), nil)
    wow.fire("MAIL_SHOW")
    assert(altsButton())
end)

test("with the Gamepad UI on, a login in combat builds the mailbox parts once the fight ends", function()
    wow.load(FILES)
    wow.gamepadUI, wow.inCombat = true, true
    SendMailFrame:Hide()
    wow.login(nil)
    eq(altsButton(), nil, "nothing made in combat")
    wow.inCombat = nil
    wow.fire("PLAYER_REGEN_ENABLED")
    assert(altsButton() and mailNote() and packButton(), "made as combat ends, with no input change")
    local frames = #wow.frames
    SendMailFrame:Show()
    wow.fire("MAIL_SHOW")
    eq(#wow.frames, frames, "the mailbox then opens without making any")
end)

test("with the Gamepad UI on, the bank's Alts Forever button is never made inside the open bank", function()
    local ns = wow.load(FILES)
    wow.gamepadUI = true
    wow.login(nil)
    CreateFrame("Frame", "BankFrame")
    CreateFrame("EditBox", "BankItemSearchBox", BankFrame)
    BankFrame:Show()
    wow.fire("BANKFRAME_OPENED")
    for _, fn in ipairs(wow.timers) do fn() end
    eq(ns.BagShortcuts().BankFrame, nil, "the bank is open: not now")
    BankFrame:Hide()
    if ToggleAllBags then ToggleAllBags() else wow.fire("PLAYER_ENTERING_WORLD") end
    assert(ns.BagShortcuts().BankFrame, "made once the bank has closed")
end)

test("Blizzard's bags get no Alts Forever button, with or without the Gamepad UI (the binding opens ours)", function()
    for _, pad in ipairs({ true, false }) do
        local ns = wow.load(FILES)
        wow.gamepadUI = pad
        local bags = CreateFrame("Frame", "ContainerFrameCombinedBags")
        bags.CloseButton = CreateFrame("Button", nil, bags)
        bags:Hide()
        local one = CreateFrame("Frame", "ContainerFrame1")
        one.CloseButton = CreateFrame("Button", nil, one)
        one:Hide()
        local frames = #wow.frames
        wow.login(nil)
        wow.fire("PLAYER_ENTERING_WORLD")
        if ToggleAllBags then ToggleAllBags() end
        wow.fire("INPUT_DEVICE_INTERFACE_TRANSITION", pad and 1 or 0, pad and 0 or 1)
        eq(ns.BagShortcuts().ContainerFrameCombinedBags, nil)
        eq(ns.BagShortcuts().ContainerFrame1, nil)
        for i = frames + 1, #wow.frames do
            local f = wow.frames[i]
            assert(f.parent ~= bags and f.parent ~= one, "nothing of ours inside Blizzard's bags")
        end
        AltsForever_Binding("bags")
        eq(AltsForeverBagsFrame:IsShown(), true, "the binding opens every character's bags")
    end
end)

test("the Options page's window size: - and + buttons step it 5% (a D-pad can't drag the slider)", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    local page = ns.OptionsPanel()
    page:Show()
    page.bigger.scripts.OnClick(page.bigger)
    eq(AltsForeverDB.scale, 1.05)
    eq(page.slider:GetValue(), 105)
    eq(page.scaleText.text, "105%")
    page.smaller.scripts.OnClick(page.smaller)
    page.smaller.scripts.OnClick(page.smaller)
    eq(AltsForeverDB.scale, 0.95)
    eq(page.scaleText.text, "95%")
end)
