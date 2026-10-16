-- Tests: upgrades your characters can craft, on the character sheet (an anvil button
-- beside a slot). Loaded by tests/run.lua.

-- Logs in as Aldric, a level 24 warrior (mail is the heaviest armour he wears), with Smith
-- (a paladin who can mail him things) and Far Away (another ruleset, who can't).
function flyStart()
    local ns = wow.load(FILES)
    local mail = { sub = 3, loc = "INVTYPE_HAND", stats = { ITEM_MOD_STRENGTH_SHORT = 5 } }
    wow.item(6001, "Linked Gloves", mail)
    wow.item(6002, "Leather Gloves", { sub = 2, loc = "INVTYPE_HAND", stats = { ITEM_MOD_STRENGTH_SHORT = 9 } })
    wow.item(6003, "Bound Mail Gloves", { sub = 3, loc = "INVTYPE_HAND", bind = 1, stats = { ITEM_MOD_STRENGTH_SHORT = 5 } })
    wow.item(6004, "My Bound Gauntlets", { sub = 3, loc = "INVTYPE_HAND", bind = 1, stats = { ITEM_MOD_STRENGTH_SHORT = 5 } })
    wow.item(6005, "Far Gloves", mail)
    wow.item(6006, "Woolen Cape", { sub = 1, loc = "INVTYPE_CLOAK", stats = { ITEM_MOD_STAMINA_SHORT = 2 } })
    wow.item(6007, "Plate Gloves", { sub = 4, loc = "INVTYPE_HAND", stats = { ITEM_MOD_STRENGTH_SHORT = 9 } })
    wow.item(6008, "Future Helm", { sub = 3, loc = "INVTYPE_HEAD", level = 28, stats = { ITEM_MOD_STRENGTH_SHORT = 9 } })
    wow.player.class = "WARRIOR"
    -- The character sheet and three of its slot buttons.
    PaperDollFrame = CreateFrame("Frame")
    for name, id in pairs({ Head = 1, Back = 15, Hands = 10 }) do
        local b = CreateFrame("Button", "Character" .. name .. "Slot")
        b.GetID = function() return id end
    end
    wow.login({ v = 2, chars = {
        ["Aldric"] = alt("Aldric", "WARRIOR", { level = 24, gear = {}, realm = "Realm",
            crafts = { Blacksmithing = { [6004] = "my bound gauntlets" } } }),
        ["Smith"] = alt("Smith", "PALADIN", { realm = "Realm", crafts = { Blacksmithing = {
            [6001] = "linked gloves", [6002] = "leather gloves", [6003] = "bound mail gloves", [6007] = "plate gloves",
            [6008] = "future helm" },
            Tailoring = { [6006] = "woolen cape" },
            -- Left over from 0.2.x: the same items, as `true`, under a profession that doesn't make them.
            Cooking = { [6001] = true, [6006] = true } } }),
        ["Far Away"] = alt("Far Away", "WARRIOR", { realm = "Elsewhere", crafts = { Blacksmithing = { [6005] = "far gloves" } } }),
    } })
    return ns
end

test("craftable upgrades: the heaviest armour you wear, bind on pickup only your own, only from characters you can mail", function()
    local ns = flyStart()
    local list = ns.CraftableUpgrades(10)
    local got = {}
    for _, e in ipairs(list) do got[#got + 1] = e.id .. " " .. e.key .. " " .. e.prof end
    -- Not leather (a warrior wears mail) or plate (not until 40), not Smith's bind-on-pickup
    -- gloves (can't be mailed), not Far Away's (another ruleset).
    eq(table.concat(got, ", "), "6001 Smith Blacksmithing, 6004 Aldric Blacksmithing")
    eq(list[1].gain, math.huge, "nothing worn there")
    -- A cloak is cloth for everyone: not held to the heaviest type.
    eq(ns.CraftableUpgrades(15)[1].id, 6006)
    eq(ns.CraftableUpgrades(15)[1].prof, "Tailoring", "not the leftover Cooking entry")
    local crafts = { Cooking = { [1] = true, [2] = true }, Leatherworking = { [1] = "embossed leather cloak" } }
    eq(ns.CraftProf(crafts, "Cooking", 1), "Leatherworking", "the entry with the recipe's name wins")
    eq(ns.CraftProf(crafts, "Leatherworking", 1), "Leatherworking")
    eq(ns.CraftProf(crafts, "Cooking", 2), "Cooking", "a lone old entry stands")
    local head = ns.CraftableUpgrades(1)
    eq(#head, 1)
    eq(head[1].at, 28, "the helm, from level 28")
    eq(#ns.CraftableUpgrades(2), 0, "nothing for the neck")
end)

test("the character sheet puts an anvil beside slots with a craftable upgrade you can wear now that binds when equipped", function()
    local ns = flyStart()
    PaperDollFrame.scripts.OnShow(PaperDollFrame)
    local hands, back, head = ns.CraftGlyph(CharacterHandsSlot), ns.CraftGlyph(CharacterBackSlot), ns.CraftGlyph(CharacterHeadSlot)
    eq(hands and hands:IsShown(), true, "the mail gloves Smith makes")
    eq(back and back:IsShown(), true, "the cape: cloth for everyone")
    eq(head, nil, "the helm needs level 28: not wearable yet")
    eq(hands.point[1], "TOPLEFT", "outside the right-hand column")
    eq(back.point[1], "TOPRIGHT", "outside the left-hand column")
    -- The best upgrade's chevrons on the anvil: nothing worn in the hands, so major.
    eq(hands.tier.texture, "Interface\\AddOns\\AltsForever\\media\\up3.tga")
    -- Shipped with the addon, and drawn.
    local release = assert(io.open("tools/release.py")):read("*a")
    for n = 1, 3 do
        assert(release:find('"media/up' .. n .. '.tga"', 1, true), "up" .. n .. ".tga ships")
        local f = assert(io.open("media/up" .. n .. ".tga", "rb"), "up" .. n .. ".tga exists")
        f:close()
    end
    -- Hovering the anvil: the best few, and who makes them.
    hands.scripts.OnEnter(hands)
    local text = {}
    for _, line in ipairs(GameTooltip.lines) do text[#text + 1] = tostring(line[1]) .. " | " .. tostring(line[2]) end
    text = table.concat(text, "\n")
    assert(text:find("Your characters can craft", 1, true), text)
    assert(text:find("Linked Gloves", 1, true) and text:find("Smith", 1, true), text)
    assert(not text:find("My Bound Gauntlets", 1, true), "binds on pickup: left out\n" .. text)
    -- Clicking it: the items beside it; again: closed.
    hands.scripts.OnClick(hands)
    local panel = AltsForeverCraftPanel
    eq(panel:IsShown(), true)
    local items = {}
    for _, child in ipairs({ panel:GetChildren() }) do
        if child:IsShown() and child.entry then items[#items + 1] = child end
    end
    eq(#items, 1)
    items[1].scripts.OnEnter(items[1])
    local tip = {}
    for _, line in ipairs(GameTooltip.lines) do tip[#tip + 1] = tostring(line[1]) end
    assert(table.concat(tip, "\n"):find("Crafted by [PALADIN]Smith (Blacksmithing)", 1, true), table.concat(tip, "\n"))
    hands.scripts.OnClick(hands)
    eq(panel:IsShown(), false, "click again closes it")
    hands.scripts.OnClick(hands)
    PaperDollFrame:Hide()
    eq(panel:IsShown(), false, "closes with the character sheet")
    PaperDollFrame:Show()
    -- Their own setting: /af anvils, the menu. Show upgrades (the tooltips) doesn't touch them.
    ns.SetUpgrades(false)
    eq(hands:IsShown(), true, "tooltips' upgrades off: the anvils stay")
    ns.SetUpgrades(true)
    SlashCmdList.ALTSFOREVER("anvils")
    eq(AltsForeverDB.anvilsOff, true)
    eq(hands:IsShown(), false, "anvils off")
    ns.ShowOptionsMenu(UIParent)
    wow.menuItem("Show craftable upgrades on the character sheet").setSelected()
    eq(AltsForeverDB.anvilsOff, nil)
    eq(hands:IsShown(), true, "back on")
end)

test("with the Gamepad UI on, the character sheet's anvils and their panel are built while it's closed; the panel takes focus", function()
    local ns = flyStart()
    PaperDollFrame:Hide()
    wow.gamepadUI = true
    wow.fire("INPUT_DEVICE_INTERFACE_TRANSITION", 1, 0)
    local hands = ns.CraftGlyph(CharacterHandsSlot)
    assert(hands, "made")
    eq(ns.CraftGlyph(CharacterHeadSlot):IsShown(), false)
    local panel = AltsForeverCraftPanel
    local made = 0
    for _, child in ipairs({ panel:GetChildren() }) do
        if child.icon then made = made + 1 end
    end
    eq(made, 10, "every item button")
    -- Opening the sheet makes nothing new, and shows the anvils that have upgrades.
    local frames = #wow.frames
    PaperDollFrame:Show()
    eq(#wow.frames, frames, "nothing created with the sheet open")
    eq(hands:IsShown(), true)
    eq(ns.CraftGlyph(CharacterHeadSlot):IsShown(), false, "the helm: not wearable yet")
    -- A on the anvil: the panel opens and reports to the focus manager; B closes it.
    wow.focus = {}
    hands.scripts.OnClick(hands)
    eq(focusCalls(), "shown AltsForeverCraftPanel")
    eq(panel:SmartNavigationCloseHandler(), true)
    eq(panel:IsShown(), false)
    eq(focusCalls(), "hidden AltsForeverCraftPanel")
    wow.gamepadUI = false
end)
