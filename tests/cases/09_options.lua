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
    eq(table.concat(texts, " | "), "Alts Forever | Open overview | Bags and bank | Search... | Show other rulesets and factions | Settings...")
    wow.menuItem("Open overview").fn()
    eq(AltsForeverFrame:IsShown(), true)
    wow.menuItem("Open overview").fn()
    eq(AltsForeverFrame:IsShown(), true, "the menu only opens it")
    -- Still offered while it's open (it may be behind other windows): brings it to the front.
    AltsForever_OnAddonCompartmentClick("AltsForever", "RightButton", UIParent)
    local raised = AltsForeverFrame.raised or 0
    wow.menuItem("Open overview").fn()
    eq(AltsForeverFrame:IsShown(), true)
    assert(AltsForeverFrame.raised > raised, "already open: brought to the front")
    AltsForeverFrame.cog.scripts.OnClick(AltsForeverFrame.cog)
    eq(wow.menuItem("Open overview"), nil, "not from the overview's own cog")
    wow.menuItem("Bags and bank").fn()
    eq(AltsForeverBagsFrame:IsShown(), true, "Bags and bank opens the bags window")
    AltsForever_OnAddonCompartmentEnter("AltsForever", UIParent)
    eq(GameTooltip.lines[1][1], "Alts Forever")
    assert(GameTooltip.lines[3][1]:find("Right-click", 1, true))
end)

test("options menu: only what's switched while playing, then Settings...; without an Options page, every setting", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    SlashCmdList.ALTSFOREVER("")
    AltsForeverFrame.cog.scripts.OnClick(AltsForeverFrame.cog)
    eq(wow.menuItem("Show skill-up details"), nil, "set once: on the Options page")
    local box = wow.menuItem("Show other rulesets and factions")
    eq(box.kind, "checkbox"); eq(box.isSelected(), false)
    box.setSelected()
    eq(AltsForeverDB.otherRulesets, true)
    -- The Options page couldn't be registered: the menu offers every setting itself.
    ns = wow.load(FILES)
    Settings.RegisterCanvasLayoutCategory = nil
    wow.login(nil)
    ns.ShowOptionsMenu(UIParent)
    eq(wow.menuItem("Settings..."), nil)
    box = wow.menuItem("Show skill-up details")
    eq(box.kind, "checkbox"); eq(box.isSelected(), true)
    box.setSelected()
    eq(AltsForeverDB.skillupsOff, true); eq(box.isSelected(), false)
    eq(#wow.menu.items, 4 + 9, "the title, Open overview, Bags and bank, Search..., the nine settings")
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

test("window size: /af scale and the Options slider scale every window of ours, kept on screen", function()
    local ns = wow.load(FILES)
    wow.login({ v = 2, chars = { ["Tarn Moon"] = alt("Tarn Moon", "DRUID", {}) } })
    ns.ToggleOverview(true)
    local f = AltsForeverFrame
    eq(f:GetScale(), 1)
    -- Moved somewhere: its centre on screen stays put when the size changes.
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 100, 700)
    f.center = { 400, 500 }
    SlashCmdList.ALTSFOREVER("scale 150")
    eq(AltsForeverDB.scale, 1.5)
    eq(f:GetScale(), 1.5)
    eq(table.concat({ f:GetPoint() }, " ", 3, 5), "BOTTOMLEFT " .. 400 / 1.5 .. " " .. 500 / 1.5)
    assert(wow.printed[#wow.printed]:find("Window size: 150%.", 1, true), wow.printed[#wow.printed])
    -- Windows opened later start at that size.
    ns.ShowBags(ns.charKey, "bags")
    eq(AltsForeverBagsFrame:GetScale(), 1.5)
    -- Kept between 50% and 300%; nonsense changes nothing.
    SlashCmdList.ALTSFOREVER("scale 1000")
    eq(AltsForeverDB.scale, 3)
    SlashCmdList.ALTSFOREVER("scale big")
    eq(AltsForeverDB.scale, 3)
    SlashCmdList.ALTSFOREVER("scale 100")
    eq(AltsForeverDB.scale, 1, "chosen, so kept even if EllesmereUI turns up")
    eq(f:GetScale(), 1)
    eq(AltsForeverBagsFrame:GetScale(), 1)
    -- The Options page: a slider in %, showing the size.
    local page = ns.OptionsPanel()
    page:Show()
    eq(page.slider:GetValue(), 100)
    eq(page.scaleText.text, "100%")
    page.slider:SetValue(125)
    eq(AltsForeverDB.scale, 1.25)
    eq(f:GetScale(), 1.25)
    eq(page.scaleText.text, "125%")
end)

test("window size follows EllesmereUI's Window Scale until you choose your own", function()
    local ns = wow.load(FILES)
    wow.login({ v = 2, chars = { ["Tarn Moon"] = alt("Tarn Moon", "DRUID", {}) } })
    -- EllesmereUI's slider: its saved value, and the function it calls (made with its panel).
    EllesmereUI = {}
    EllesmereUIDB = { panelScale = 1.5 }
    ns.ToggleOverview(true)
    local f = AltsForeverFrame
    eq(f:GetScale(), 1.5, "the default follows it")
    eq(ns.FollowsEllesmere(), true)
    -- Changed while our window was closed: it catches up when it opens.
    ns.ToggleOverview()
    EllesmereUIDB.panelScale = 1.25
    ns.ToggleOverview(true)
    eq(f:GetScale(), 1.25)
    -- Changed with ours open: live, once its panel has made SetPanelScale.
    function EllesmereUI:SetPanelScale(v) EllesmereUIDB.panelScale = v end
    ns.ToggleOverview()
    ns.ToggleOverview(true)
    EllesmereUI:SetPanelScale(1.75)
    eq(f:GetScale(), 1.75, "follows its slider")
    -- Our own size wins, even when EllesmereUI's changes.
    SlashCmdList.ALTSFOREVER("scale 120")
    eq(f:GetScale(), 1.2)
    eq(ns.FollowsEllesmere(), false)
    EllesmereUI:SetPanelScale(2)
    eq(f:GetScale(), 1.2, "ours stays")
    -- The Options page: the tick box shows which, and ticking it follows again.
    local page = ns.OptionsPanel()
    page:Show()
    eq(page.followEui:IsShown(), true)
    eq(page.followEui:GetChecked(), false)
    eq(page.slider:GetValue(), 120)
    page.followEui:SetChecked(true)
    page.followEui.scripts.OnClick(page.followEui)
    eq(AltsForeverDB.scale, nil)
    eq(f:GetScale(), 2)
    eq(page.slider:GetValue(), 200)
    -- Moving the slider unticks it.
    page.slider:SetValue(150)
    eq(page.followEui:GetChecked(), false)
    eq(AltsForeverDB.scale, 1.5)
    -- /af scale eui: following again.
    SlashCmdList.ALTSFOREVER("scale eui")
    eq(AltsForeverDB.scale, nil)
    assert(wow.printed[#wow.printed]:find("200%, the same as EllesmereUI", 1, true), wow.printed[#wow.printed])
    EllesmereUI, EllesmereUIDB = nil, nil
end)
