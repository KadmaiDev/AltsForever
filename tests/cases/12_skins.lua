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

test("with EllesmereUI, the bags window's slots look like its bags: square icons, a quality edge, faded empty slots", function()
    wow.withEllesmere = true
    local ns = wow.load(FILES)
    wow.setBag(0, 4, { [1] = { 100, 20 }, [3] = { 200, 1 } })
    wow.itemQuality[200] = 3
    wow.login(nil)
    wow.skinCallback(wow.skinFacade)
    ns.ShowBags(ns.charKey, "bags")
    local byId, empty = {}, nil
    for _, b in ipairs({ AltsForeverBagsFrame.content:GetChildren() }) do
        if b:IsShown() and b.icon then
            if b.id then byId[b.id] = b else empty = empty or b end
        end
    end
    local rare, unknown = byId[200], byId[100]
    assert(skinnedWith("SquareIcon", rare.icon), "the icon squared by EllesmereUI")
    eq(rare.border:IsShown(), false, "not Blizzard's round frame")
    eq(table.concat(rare.edges[1].tint, ","), "0,0.44,0.87", "edge in the item's quality colour")
    eq(table.concat(unknown.edges[1].tint, ","), "0.25,0.25,0.25", "grey while its quality isn't known")
    eq(rare.emptyTex:IsShown(), false)
    eq(empty.emptyTex:IsShown(), true, "an empty slot: the empty-slot art, faded")
    eq(empty.emptyTex.texture, "Interface\\PaperDoll\\UI-Backpack-EmptySlot")
    eq(empty.emptyTex:GetAlpha(), 0.35)
    eq(table.concat(empty.emptyTex.tint, ","), "0.27,0.27,0.27", "tinted down to EllesmereUI's dark copy")
    eq(empty.icon.texture, nil, "not at full strength in the icon")
    eq(table.concat(empty.edges[1].tint, ","), "0,0,0")
    eq(AltsForeverBagsFrame.euiBg, nil, "EllesmereUI's bags not in use: the standard window")
    for _, call in ipairs(wow.skinned) do
        if call[1] == "Shell" and call[2] == AltsForeverBagsFrame then eq(call[3], nil, "with its frame") end
    end
end)

test("with EllesmereUI's bags in use, the bags window has their background", function()
    wow.withEllesmere = true
    local ns = wow.load(FILES)
    EUI_MainBagFrame = CreateFrame("Frame", "EUI_MainBagFrame", UIParent)
    wow.login(nil)
    wow.skinCallback(wow.skinFacade)
    ns.ShowBags(ns.charKey, "bags")
    local bg = AltsForeverBagsFrame.euiBg
    assert(bg, "drawn")
    eq(bg.texture, "Interface\\AddOns\\EllesmereUI\\media\\modern_blizz.png")
    eq(table.concat(bg.tint, ","), "0.75,0.75,0.75", "their bags' 25% black")
    -- The shell without its shadowed frame (its title strip stays), and a thin line instead.
    local opts
    for _, call in ipairs(wow.skinned) do
        if call[1] == "Shell" and call[2] == AltsForeverBagsFrame then opts = call[3] end
    end
    eq(opts and opts.noBorder, true)
    eq(#AltsForeverBagsFrame.euiLine, 4)
    EUI_MainBagFrame = nil
end)

test("without EllesmereUI the bags window keeps Blizzard's slot art", function()
    local ns = wow.load(FILES)
    wow.setBag(0, 2, { [1] = { 200, 1 } })
    wow.itemQuality[200] = 3
    wow.login(nil)
    ns.ShowBags(ns.charKey, "bags")
    for _, b in ipairs({ AltsForeverBagsFrame.content:GetChildren() }) do
        if b:IsShown() and b.icon then
            eq(b.edges, nil)
            if not b.id then eq(b.icon.texture, "Interface\\PaperDoll\\UI-Backpack-EmptySlot") end
        end
    end
end)

test("with EllesmereUI, window titles sit in the middle of its title strip and text boxes get room before the edge", function()
    wow.withEllesmere = true
    local ns = wow.load(FILES)
    wow.login(nil)
    wow.skinCallback(wow.skinFacade)
    local f = CreateFrame("Frame", nil, UIParent)
    f.TitleText = f:CreateFontString()
    ns.SkinWindow(f)
    eq(f.TitleText.point[1], "CENTER")
    eq(f.TitleText.point[2], f)
    eq(f.TitleText.point[3], "TOP")
    eq(f.TitleText.point[5], -14)
    SlashCmdList.ALTSFOREVERSEARCH("")
    local opts
    for _, call in ipairs(wow.skinned) do
        if call[1] == "EditBox" and call[2] == AltsForeverSearchBox then opts = call[3] end
    end
    eq(opts and opts.padInput, true, "the search box's text has room before the border")
    AltsForeverSearchFrame:Hide()
end)

test("with EllesmereUI, the gear panel's slots get the same look as its bags: quality edge, faded slot art", function()
    wow.withEllesmere = true
    local ns = wow.load(FILES)
    wow.itemQuality[3000] = 2
    wow.login({ v = 2, chars = {
        ["Brakka"] = alt("Brakka", "HUNTER", { level = 20, gear = { [1] = itemLink(3000, "Hunting Cap") } }),
    } })
    wow.skinCallback(wow.skinFacade)
    ns.ShowGear("Brakka")
    local slots = gearPanelSlots()
    assert(skinnedWith("SquareIcon", slots[1].icon))
    eq(slots[1].icon.texture, "icon:3000")
    eq(table.concat(slots[1].edges[1].tint, ","), "0.1,1,0.1", "edge in the item's quality colour")
    eq(slots[1].emptyTex:IsShown(), false)
    eq(slots[5].icon.texture, nil)
    eq(slots[5].emptyTex.texture, "empty:ChestSlot", "an empty slot: its own art, faded")
    eq(slots[5].emptyTex:GetAlpha(), 0.6)
    eq(table.concat(slots[5].edges[1].tint, ","), "0,0,0")
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
