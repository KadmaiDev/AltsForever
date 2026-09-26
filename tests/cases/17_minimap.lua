-- Tests: minimap. Loaded by tests/run.lua, which provides test, eq, wow, FILES and the
-- other shared helpers; helpers defined here are shared with the other files too.
---------------------------------------------------------------------------
-- Minimap button
test("a minimap button is made as soon as saved data loads (before login)", function()
    wow.load(FILES)
    AltsForeverDB = { v = 2, chars = {} }
    wow.fire("ADDON_LOADED", "AltsForever")
    local b = AltsForeverMinimapButton
    assert(b, "made before PLAYER_LOGIN, so EllesmereUI's minimap can collect it")
    wow.fire("PLAYER_LOGIN")
    b.scripts.OnClick(b, "LeftButton")
    eq(AltsForeverFrame:IsShown(), true)
    b.scripts.OnClick(b, "RightButton")
    eq(wow.menu.items[1].text, "Alts Forever", "right-click: options menu")
    b.scripts.OnEnter(b)
    eq(GameTooltip.lines[1][1], "Alts Forever")
end)

test("dragging moves the button around the minimap edge, and the position is kept", function()
    wow.load(FILES)
    wow.login(nil)
    local b = AltsForeverMinimapButton
    b.scripts.OnDragStart(b)
    assert(b.scripts.OnUpdate, "follows the cursor while dragging")
    wow.cursor = { 1100, 600 } -- straight right of the minimap's centre
    b.scripts.OnUpdate(b)
    eq(AltsForeverDB.minimapAngle, 0)
    eq(b.point[4], 80); eq(b.point[5], 0, "on the edge: radius 70 + 10")
    b.scripts.OnDragStop(b)
    eq(b.scripts.OnUpdate, nil, "nothing runs once dropped")
end)

test("the minimap button can be hidden from the options menu, and stays hidden", function()
    wow.load(FILES)
    wow.login(nil)
    AltsForever_OnAddonCompartmentClick("AltsForever", "RightButton", UIParent)
    local box = wow.menuItem("Show minimap button")
    eq(box.isSelected(), true)
    box.setSelected()
    eq(AltsForeverMinimapButton:IsShown(), false)
    eq(AltsForeverDB.minimapHidden, true)
    -- Next session: not even made.
    local saved = AltsForeverDB
    wow.load(FILES)
    wow.login(saved)
    eq(AltsForeverMinimapButton, nil)
    AltsForever_OnAddonCompartmentClick("AltsForever", "RightButton", UIParent)
    wow.menuItem("Show minimap button").setSelected()
    eq(AltsForeverMinimapButton:IsShown(), true, "turned back on: made now")
end)

test("with EllesmereUI, the overview's icon buttons get its square style", function()
    wow.withEllesmere = true
    wow.load(FILES)
    wow.login(nil)
    wow.skinCallback(wow.skinFacade)
    SlashCmdList.ALTSFOREVER("")
    local squared = 0
    for _, call in ipairs(wow.skinned) do if call[1] == "SquareIcon" then squared = squared + 1 end end
    eq(squared, 2, "reputation and options buttons")
end)

test("the minimap button and addon list use our logo, shipped with the addon", function()
    wow.load(FILES)
    wow.login(nil)
    eq(AltsForeverMinimapButton.icon.texture, "Interface\\AddOns\\AltsForever\\media\\minimap.tga")
    local toc = assert(io.open("AltsForever.toc")):read("*a")
    assert(toc:find("## IconTexture: Interface\\AddOns\\AltsForever\\media\\icon.tga", 1, true), "addon list icon")
    for _, file in ipairs({ "media/icon.tga", "media/minimap.tga", "media/blank.tga" }) do
        local f = io.open(file, "rb")
        assert(f, file .. " exists")
        f:close()
    end
end)
