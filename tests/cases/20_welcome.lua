-- Tests: the settings page and the first-run experience. Loaded by tests/run.lua.

test("Options > AddOns > Alts Forever: the four settings, and an Open overview button", function()
    wow.load(FILES)
    wow.login(nil)
    local page = wow.settings
    assert(page and page.registered, "the page is registered")
    eq(page.name, "Alts Forever")
    local names = {}
    for _, box in ipairs(page.checkboxes) do names[#names + 1] = box.name end
    eq(table.concat(names, " | "), "Show skill-up details | Send mail to alts | Show session stats | Show minimap button")
    for _, box in ipairs(page.checkboxes) do assert(box.tooltip and box.tooltip ~= "", box.name .. " explains itself") end
    -- The tick boxes change the same settings as the menu and commands.
    local stats = page.checkboxes[3]
    eq(stats.get(), false, "session stats off by default")
    stats.set(true)
    eq(AltsForeverDB.statsOn, true)
    eq(stats.get(), true)
    local minimap = page.checkboxes[4]
    minimap.set(false)
    eq(AltsForeverMinimapButton:IsShown(), false)
    eq(minimap.get(), false)
    page.button.click()
    eq(AltsForeverFrame:IsShown(), true, "the button opens the overview")
end)

test("the options menu has Settings..., which opens the page", function()
    wow.load(FILES)
    wow.login(nil)
    AltsForever_OnAddonCompartmentClick("AltsForever", "RightButton", UIParent)
    wow.menuItem("Settings...").fn()
    eq(wow.settingsOpened, 77)
end)

test("without Blizzard's settings API the addon still works, with no Settings... entry", function()
    wow.load(FILES)
    Settings = nil
    wow.login(nil)
    AltsForever_OnAddonCompartmentClick("AltsForever", "RightButton", UIParent)
    for _, item in ipairs(wow.menu.items) do assert(item.text ~= "Settings...", "no entry") end
end)

local function runTimers() for _, fn in ipairs(wow.timers) do fn() end end

test("a fresh install says how to use Alts Forever, once", function()
    wow.load(FILES)
    wow.login(nil)
    runTimers()
    local text = table.concat(wow.printed, "\n")
    assert(text:find("Welcome!", 1, true), text)
    assert(text:find("Options > AddOns > Alts Forever", 1, true), text)
    assert(text:find("bank, mailbox and profession windows", 1, true), text)
    eq(AltsForeverDB.welcomed, true)
    -- Next session: nothing.
    local saved = AltsForeverDB
    wow.load(FILES)
    wow.login(saved)
    runTimers()
    eq(#wow.printed, 0)
end)

test("existing players never see the welcome; a new character gets one line", function()
    wow.load(FILES)
    wow.login({ v = 2, chars = { ["Aldric"] = alt("Aldric", "MAGE", {}) } })
    runTimers()
    eq(#wow.printed, 0, "an existing player on a known character: nothing")
    eq(AltsForeverDB.welcomed, true, "and they never will")
    local saved = AltsForeverDB
    wow.load(FILES)
    wow.player.name = "Tarn Moon"
    wow.login(saved)
    runTimers()
    eq(#wow.printed, 1)
    assert(wow.printed[1]:find("Now tracking Tarn Moon", 1, true), wow.printed[1])
end)

test("with only one character the overview says how to add the others", function()
    wow.load(FILES)
    wow.login(nil)
    SlashCmdList.ALTSFOREVER("")
    assert(AltsForeverFrame.credit.text:find("Log in on your other characters once", 1, true))
    local saved = AltsForeverDB
    saved.chars["Brak Stone"] = alt("Brak Stone", "WARRIOR", {})
    wow.load(FILES)
    wow.login(saved)
    SlashCmdList.ALTSFOREVER("")
    eq(AltsForeverFrame.credit.text, "Alts Forever by Kadmai")
end)
