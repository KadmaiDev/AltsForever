-- Tests: options. Loaded by tests/run.lua, which provides test, eq, wow, FILES and the
-- other shared helpers; helpers defined here are shared with the other files too.
---------------------------------------------------------------------------
-- Options: minimap compartment, menus, forgetting a character
test("minimap compartment: click opens the overview, right-click the options menu", function()
    wow.load(FILES)
    wow.login(nil)
    AltsForever_OnAddonCompartmentClick("AltsForever", "LeftButton", UIParent)
    eq(AltsForeverFrame:IsShown(), true)
    AltsForever_OnAddonCompartmentClick("AltsForever", "LeftButton", UIParent)
    eq(AltsForeverFrame:IsShown(), false, "click again closes it")
    AltsForever_OnAddonCompartmentClick("AltsForever", "RightButton", UIParent)
    local texts = {}
    for _, item in ipairs(wow.menu.items) do texts[#texts + 1] = item.text end
    eq(table.concat(texts, " | "), "Alts Forever | Open overview | Show skill-up details | Send mail to alts | Show session stats | Show minimap button | Memory use")
    wow.menuItem("Open overview").fn()
    eq(AltsForeverFrame:IsShown(), true)
    wow.menuItem("Open overview").fn()
    eq(AltsForeverFrame:IsShown(), true, "the menu only opens it")
    AltsForever_OnAddonCompartmentClick("AltsForever", "RightButton", UIParent)
    eq(wow.menuItem("Open overview"), nil, "not offered while the overview is open")
    AltsForeverFrame.cog.scripts.OnClick(AltsForeverFrame.cog)
    eq(wow.menuItem("Open overview"), nil, "nor from the overview's own cog")
    AltsForever_OnAddonCompartmentEnter("AltsForever", UIParent)
    eq(GameTooltip.lines[1][1], "Alts Forever")
    assert(GameTooltip.lines[3][1]:find("Right-click", 1, true))
end)

test("options menu: skill-up details tick box and memory", function()
    wow.load(FILES)
    wow.login(nil)
    SlashCmdList.ALTSFOREVER("")
    AltsForeverFrame.cog.scripts.OnClick(AltsForeverFrame.cog)
    local box = wow.menuItem("Show skill-up details")
    eq(box.kind, "checkbox"); eq(box.isSelected(), true)
    box.setSelected()
    eq(AltsForeverDB.skillupsOff, true); eq(box.isSelected(), false)
    box.setSelected()
    eq(AltsForeverDB.skillupsOff, nil)
    wow.printed = {}
    wow.menuItem("Memory use").fn()
    assert(table.concat(wow.printed, "\n"):find("Memory", 1, true), "same as /af mem")
end)

test("right-click a character in the overview to forget them, after confirming", function()
    wow.load(FILES)
    wow.now = NOW
    wow.login(overviewAlts())
    SlashCmdList.ALTSFOREVER("")
    local low = overviewRows()[4]
    eq(low.key, "Low")
    low.scripts.OnClick(low, "RightButton")
    eq(wow.menu.items[1].text, "[ROGUE]Low")
    eq(StaticPopupDialogs.ALTSFOREVER_FORGET, nil, "Blizzard's pop-up table untouched until needed")
    wow.menuItem("Forget Low...").fn()
    eq(wow.popup.which, "ALTSFOREVER_FORGET"); eq(wow.popup.text, "Low")
    eq(type(AltsForeverDB.chars["Low"]), "table", "nothing happens until confirmed")
    StaticPopupDialogs.ALTSFOREVER_FORGET.OnAccept(nil, wow.popup.data)
    eq(AltsForeverDB.chars["Low"], nil)
    eq(#overviewRows(), 3, "gone from the open overview")
    -- Your own row can't be forgotten.
    local you = overviewRows()[1]
    you.scripts.OnClick(you, "RightButton")
    eq(wow.menuItem("Forget Aldric...").enabled, false)
end)

test("no addon file assigns one of Blizzard's globals (that taints Blizzard's code)", function()
    -- Writing e.g. StaticPopupDialogs = ... from addon code made Esc's SpellStopCasting
    -- fail with ADDON_ACTION_FORBIDDEN. Adding keys to such tables is fine; replacing is not.
    local blizzard = { "StaticPopupDialogs", "UISpecialFrames", "GameTooltip", "ItemRefTooltip", "SlashCmdList",
        "UIParent", "MenuUtil", "Settings", "ChatFrame_DisplayTimePlayed", "SpellStopCasting", "ToggleGameMenu" }
    for _, file in ipairs(FILES) do
        local n = 0
        for line in io.lines(file) do
            n = n + 1
            local code = line:gsub("%-%-.*$", "")
            for _, name in ipairs(blizzard) do
                assert(not code:match("^%s*" .. name .. "%s*="), file .. ":" .. n .. " assigns " .. name)
                assert(not code:match("[,%s]" .. name .. "%s*=[^=]") or code:match("local"), file .. ":" .. n .. " assigns " .. name)
            end
        end
    end
end)
