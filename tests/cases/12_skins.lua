-- Tests: skins. Loaded by tests/run.lua, which provides test, eq, wow, FILES and the
-- other shared helpers; helpers defined here are shared with the other files too.
---------------------------------------------------------------------------
-- EllesmereUI look (its public skinning API)
function skinnedWith(fname, obj)
    for _, call in ipairs(wow.skinned) do
        if call[1] == fname and call[2] == obj then return true end
    end
    return false
end

test("without EllesmereUI nothing is skinned: the classic look stays", function()
    wow.load(FILES)
    wow.login(nil)
    SlashCmdList.ALTSFOREVER("")
    eq(#wow.skinned, 0); eq(EllesmereUI, nil)
end)

test("with EllesmereUI, every window takes its look when first created", function()
    wow.withEllesmere = true
    wow.load(FILES)
    wow.now = NOW
    eq(wow.skinName, "AltsForever", "registered under the addon's folder name")
    wow.login(overviewAlts())
    wow.skinCallback(wow.skinFacade) -- EllesmereUI calls this at login
    SlashCmdList.ALTSFOREVER("")
    local f = AltsForeverFrame
    assert(skinnedWith("Shell", f), "overview backdrop")
    local row = overviewRows()[1]
    assert(skinnedWith("Font", row.cells[1]), "row text in the player's font")
    row.scripts.OnClick(row) -- gear panel
    assert(skinnedWith("Shell", AltsForeverGearFrame), "gear panel")
    AltsForeverFrame.repButton.scripts.OnClick(AltsForeverFrame.repButton)
    assert(skinnedWith("Shell", AltsForeverRepFrame), "reputation panel")
end)

test("a window opened before EllesmereUI's callback is skinned when it arrives", function()
    wow.withEllesmere = true
    wow.load(FILES)
    wow.login(nil)
    SlashCmdList.ALTSFOREVER("")
    eq(#wow.skinned, 0, "nothing until EllesmereUI hands over its style")
    wow.skinCallback(wow.skinFacade)
    assert(skinnedWith("Shell", AltsForeverFrame))
end)

test("if the player turned our skinning off in EllesmereUI, nothing is skinned", function()
    wow.withEllesmere = true
    wow.load(FILES)
    wow.login(nil)
    -- EllesmereUI never calls back when its third-party skinning is off for us.
    SlashCmdList.ALTSFOREVER("")
    eq(#wow.skinned, 0)
end)

---------------------------------------------------------------------------
-- Class colours: EllesmereUI's, then CUSTOM_CLASS_COLORS, then Blizzard's
-- With one character there's no Total line: the name is on line 2.
function tooltipName(itemID)
    return wow.hover(GameTooltip, itemID)[2][1]
end

test("names use EllesmereUI's class colours when it's installed", function()
    wow.withEllesmere = true
    wow.load(FILES)
    EllesmereUI.GetClassColor = function(class) return class == "MAGE" and { r = 1, g = 0.5, b = 0 } or EllesmereUI._COLOR_WHITE end
    EllesmereUI._COLOR_WHITE = { r = 1, g = 1, b = 1 }
    wow.setBag(0, 16, { [1] = { 100, 2 } })
    wow.login(nil)
    eq(tooltipName(100), "|cffff8000Aldric|r")
end)

test("anything unexpected from EllesmereUI falls back to Blizzard's colour", function()
    for _, bad in ipairs({
        function() error("changed API") end,
        function() return "not a colour" end,
        function() return EllesmereUI._COLOR_WHITE end, -- its "unknown class"
    }) do
        wow.withEllesmere = true
        wow.load(FILES)
        EllesmereUI._COLOR_WHITE = { r = 1, g = 1, b = 1 }
        EllesmereUI.GetClassColor = bad
        wow.setBag(0, 16, { [1] = { 100, 2 } })
        wow.login(nil)
        eq(tooltipName(100), "[MAGE]Aldric")
    end
end)

test("names use CUSTOM_CLASS_COLORS (e.g. !ClassColors) when present", function()
    wow.load(FILES)
    CUSTOM_CLASS_COLORS = { MAGE = { r = 0, g = 1, b = 0 } }
    wow.setBag(0, 16, { [1] = { 100, 2 } })
    wow.login(nil)
    eq(tooltipName(100), "|cff00ff00Aldric|r")
end)

test("a live EllesmereUI look change recolours names", function()
    wow.withEllesmere = true
    wow.load(FILES)
    EllesmereUI._COLOR_WHITE = { r = 1, g = 1, b = 1 }
    local colour = { r = 1, g = 0, b = 0 }
    EllesmereUI.GetClassColor = function() return colour end
    wow.setBag(0, 16, { [1] = { 100, 2 } })
    wow.login(nil)
    wow.skinCallback(wow.skinFacade)
    eq(tooltipName(100), "|cffff0000Aldric|r")
    colour = { r = 0, g = 0, b = 1 }
    eq(tooltipName(100), "|cffff0000Aldric|r", "cached until told")
    wow.looksChanged()
    eq(tooltipName(100), "|cff0000ffAldric|r")
end)

---------------------------------------------------------------------------
-- ElvUI look (its Skins module)
test("with ElvUI, every window takes its look when first created", function()
    wow.withElvUI = true
    wow.load(FILES)
    wow.now = NOW
    wow.login(overviewAlts())
    SlashCmdList.ALTSFOREVER("")
    local f = AltsForeverFrame
    assert(skinnedWith("HandleFrame", f), "overview: backdrop, inset, close button")
    assert(skinnedWith("CreateBackdrop", f.cog) and skinnedWith("CreateBackdrop", f.repButton), "icon buttons")
    assert(skinnedWith("SetTexCoords", f.cog:GetNormalTexture()), "icon edges cropped")
    assert(skinnedWith("FontTemplate", overviewRows()[1].cells[1]), "row text in ElvUI's font")
    assert(skinnedWith("FontTemplate", f.credit), "text the window already had")
    local row = overviewRows()[1]
    row.scripts.OnClick(row)
    assert(skinnedWith("HandleFrame", AltsForeverGearFrame), "gear panel")
    local slots = 0
    for _, call in ipairs(wow.skinned) do
        if call[1] == "CreateBackdrop" and call[2] ~= f.cog and call[2] ~= f.repButton then slots = slots + 1 end
    end
    eq(slots, 19, "every gear slot")
    f.repButton.scripts.OnClick(f.repButton)
    assert(skinnedWith("HandleFrame", AltsForeverRepFrame), "reputation panel")
end)

test("with ElvUI, the mail window's Alts arrow gets its arrow style, clear of the To box", function()
    wow.withElvUI = true
    wow.load(FILES)
    wow.login(mailAlts())
    wow.fire("MAIL_SHOW")
    local b = altsButton()
    assert(skinnedWith("HandleNextPrevButton", b))
    eq(b.point[1], "LEFT"); eq(b.point[2], SendMailNameEditBox); eq(b.point[4], 3)
end)

test("before ElvUI has initialised nothing is skinned; afterwards it is", function()
    wow.withElvUI = true
    wow.load(FILES)
    wow.elv.Initialized = nil
    wow.setBag(0, 16, { [1] = { 100, 2 } })
    wow.login(nil)
    wow.hover(GameTooltip, 100)
    eq(#wow.skinned, 0)
    wow.elv.Initialized = true
    SlashCmdList.ALTSFOREVER("")
    assert(skinnedWith("HandleFrame", AltsForeverFrame))
end)

test("an error inside ElvUI's skinning never stops our windows opening", function()
    wow.withElvUI = true
    wow.load(FILES)
    wow.elvSkins.HandleFrame = function() error("changed API") end
    wow.elvSkins.HandleNextPrevButton = function() error("changed API") end
    wow.login(mailAlts())
    SlashCmdList.ALTSFOREVER("")
    eq(AltsForeverFrame:IsShown(), true)
    wow.fire("MAIL_SHOW")
    assert(altsButton(), "Alts arrow still made")
end)

test("with both EllesmereUI and ElvUI installed, EllesmereUI's look wins", function()
    wow.withEllesmere, wow.withElvUI = true, true
    wow.load(FILES)
    wow.login(nil)
    wow.skinCallback(wow.skinFacade)
    SlashCmdList.ALTSFOREVER("")
    assert(skinnedWith("Shell", AltsForeverFrame))
    eq(skinnedWith("HandleFrame", AltsForeverFrame), false)
end)

test("a live change to CUSTOM_CLASS_COLORS (ElvUI, !ClassColors) recolours names", function()
    wow.load(FILES)
    local listeners = {}
    CUSTOM_CLASS_COLORS = { MAGE = { r = 0, g = 1, b = 0 },
        RegisterCallback = function(self, fn) listeners[#listeners + 1] = fn end }
    wow.setBag(0, 16, { [1] = { 100, 2 } })
    wow.login(nil)
    eq(tooltipName(100), "|cff00ff00Aldric|r")
    CUSTOM_CLASS_COLORS.MAGE = { r = 1, g = 0, b = 0 }
    eq(tooltipName(100), "|cff00ff00Aldric|r", "cached until told")
    eq(#listeners, 1)
    listeners[1]()
    eq(tooltipName(100), "|cffff0000Aldric|r")
end)
