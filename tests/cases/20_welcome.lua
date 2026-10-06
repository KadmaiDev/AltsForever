-- Tests: the settings page and the first-run experience. Loaded by tests/run.lua.

-- Shows our Options page as Blizzard's panel would, and returns it.
function showOptionsPage()
    local page = wow.settings
    assert(page and page.registered, "the page is registered")
    page.frame.scripts.OnShow(page.frame)
    return page.frame
end

test("the Options page is built the first time the Options window shows it", function()
    wow.load(FILES)
    wow.login(nil)
    local f = wow.settings.frame
    eq(f:IsShown(), false, "starts hidden, so the window's Show() fires OnShow")
    f:Show() -- what the Options window does when you pick Alts Forever
    assert(f.built and f.logo, "not blank on the first visit")
end)

test("Options > AddOns > Alts Forever: logo, Open overview, and the five settings as tick boxes", function()
    wow.load(FILES)
    wow.login(nil)
    eq(wow.settings.name, "Alts Forever")
    local f = showOptionsPage()
    eq(f.logo.texture, "Interface\\AddOns\\AltsForever\\media\\logo.tga", "the full logo")
    local names = {}
    for _, check in ipairs(f.checks) do names[#names + 1] = check.label.text end
    eq(table.concat(names, " | "), "Show skill-up details | Show upgrades | Send mail to alts | Show session stats | Show minimap button")
    -- The tick boxes show and change the same settings as the menu and commands.
    local stats, minimap = f.checks[4], f.checks[5]
    eq(stats:GetChecked(), false, "session stats off by default")
    eq(minimap:GetChecked(), true)
    stats:SetChecked(true)
    stats.scripts.OnClick(stats)
    eq(AltsForeverDB.statsOn, true)
    minimap:SetChecked(false)
    minimap.scripts.OnClick(minimap)
    eq(AltsForeverMinimapButton:IsShown(), false)
    SlashCmdList.ALTSFOREVER("minimap") -- changed elsewhere: the page shows it next time
    f.scripts.OnShow(f)
    eq(minimap:GetChecked(), true)
    -- Hovering explains each one.
    stats.scripts.OnEnter(stats)
    assert(GameTooltip.lines[2][1]:find("Off by default", 1, true))
    -- Open overview: the panel closes first, the overview opens a moment later.
    wow.settingsShown = true
    f.open.scripts.OnClick(f.open)
    eq(wow.settingsShown, false, "Options closed first")
    for _, fn in ipairs(wow.timers) do fn() end
    eq(AltsForeverFrame:IsShown(), true)
end)

test("the Options page uses none of Blizzard's setting objects (they run through Blizzard's settings code)", function()
    local text = assert(io.open("Options.lua")):read("*a"):gsub("%-%-[^\n]*", "")
    for _, name in ipairs({ "RegisterProxySetting", "RegisterAddOnSetting", "RegisterVerticalLayoutCategory",
        "Settings.CreateCheckbox", "CreateSettingsButtonInitializer" }) do
        assert(not text:find(name, 1, true), "Options.lua uses " .. name)
    end
end)

test("the options menu has Settings..., which opens the page", function()
    wow.load(FILES)
    wow.login(nil)
    AltsForever_OnAddonCompartmentClick("AltsForever", "RightButton", UIParent)
    local timers = #wow.timers
    eq(wow.menuItem("Settings...").fn(), nil, "returns nothing, so the menu closes (a return value is a MenuResponse)")
    eq(wow.settingsOpened, 77, "straight from the click: the game blocks opening the Options window from a timer")
    eq(#wow.timers, timers, "no timer")
    -- In combat the game blocks it: say so instead.
    wow.settingsOpened = nil
    wow.inCombat = true
    wow.printed = {}
    AltsForever_OnAddonCompartmentClick("AltsForever", "RightButton", UIParent)
    wow.menuItem("Settings...").fn()
    eq(wow.settingsOpened, nil)
    assert(wow.printed[1]:find("during combat", 1, true), wow.printed[1])
    wow.inCombat = nil
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
