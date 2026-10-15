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
    eq(wow.menu.owner, UIParent, "owned by UIParent: EllesmereUI's tray hides the button on a click, which closed the menu")
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

test("held by a button collector (EllesmereUI's tray, MinimapButtonButton...), the button can't be dragged round the minimap", function()
    wow.load(FILES)
    wow.login(nil)
    local b = AltsForeverMinimapButton
    eq(b:GetParent(), Minimap)
    b.scripts.OnDragStart(b)
    assert(b.scripts.OnUpdate, "on the minimap itself: dragging works")
    b.scripts.OnDragStop(b)
    -- MinimapButtonButton moves collected buttons into a container under its own button,
    -- and lays its grid out again when the button's own Show or Hide runs.
    local main = CreateFrame("Frame", "MinimapButtonButtonButton", UIParent)
    b:SetParent(CreateFrame("Frame", nil, main))
    local layouts = 0
    hooksecurefunc(b, "Show", function() layouts = layouts + 1 end)
    hooksecurefunc(b, "Hide", function() layouts = layouts + 1 end)
    b.scripts.OnDragStart(b)
    eq(b.scripts.OnUpdate, nil, "not dragged: the collector places it")
    b.scripts.OnEnter(b)
    for _, line in ipairs(GameTooltip.lines) do assert(not tostring(line[1]):find("Drag", 1, true), "no drag hint") end
    SlashCmdList.ALTSFOREVER("minimap")
    eq(b:IsShown(), false)
    eq(layouts, 1, "hidden through Hide, so its grid follows")
    SlashCmdList.ALTSFOREVER("minimap")
    eq(b:IsShown(), true)
    eq(layouts, 2)
end)

test("with a data broker display (Bazooka...) loaded, a launcher opens the overview and options; hiding the minimap button leaves it", function()
    -- A display addon's copy of LibStub and LibDataBroker-1.1; we embed neither.
    local objects = {}
    local ldb = {
        GetDataObjectByName = function(_, name) return objects[name] end,
        NewDataObject = function(_, name, obj) objects[name] = obj return obj end,
    }
    LibStub = { GetLibrary = function(_, major, silent) return major == "LibDataBroker-1.1" and ldb or nil end }
    wow.load(FILES)
    wow.login({ v = 2, chars = {}, minimapHidden = true })
    LibStub = nil
    local o = objects["Alts Forever"]
    assert(o, "launcher made")
    eq(o.type, "launcher")
    assert(o.icon:find("minimap.tga", 1, true), o.icon)
    eq(AltsForeverMinimapButton, nil, "the minimap button stays hidden (never made)")
    o.OnClick(nil, "LeftButton")
    eq(AltsForeverFrame:IsShown(), true)
    o.OnClick(nil, "RightButton")
    eq(wow.menu.items[1].text, "Alts Forever", "right-click: options menu")
    GameTooltip.lines = {}
    o.OnTooltipShow(GameTooltip)
    eq(GameTooltip.lines[1][1], "Alts Forever")
end)

test("without a data broker library, nothing is made and nothing breaks", function()
    LibStub = { GetLibrary = function() return nil end }
    wow.load(FILES)
    wow.login(nil)
    LibStub = nil
    assert(AltsForeverMinimapButton, "the rest of login ran: the minimap button is there")
end)

test("turning a hidden minimap button on after login says to reload so a collector (EllesmereUI...) can gather it", function()
    wow.load(FILES)
    wow.login({ v = 2, chars = {}, minimapHidden = true })
    eq(AltsForeverMinimapButton, nil)
    wow.printed = {}
    SlashCmdList.ALTSFOREVER("minimap")
    assert(AltsForeverMinimapButton, "made now")
    eq(#wow.printed, 1, table.concat(wow.printed, "\n"))
    assert(wow.printed[1]:find("/reload", 1, true), wow.printed[1])
    -- Hidden and shown again: the button already exists, so no reload is needed.
    SlashCmdList.ALTSFOREVER("minimap")
    wow.printed = {}
    SlashCmdList.ALTSFOREVER("minimap")
    eq(#wow.printed, 1)
    assert(wow.printed[1]:find("Minimap button shown.", 1, true) and not wow.printed[1]:find("/reload", 1, true), wow.printed[1])
end)
