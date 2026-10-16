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
            Tailoring = { [6006] = "woolen cape" } } }),
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
    eq(hands.point[1], "LEFT", "outside the right-hand column")
    eq(back.point[1], "RIGHT", "outside the left-hand column")
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
    -- Upgrades off: the anvils go.
    ns.SetUpgrades(false)
    eq(hands:IsShown(), false, "upgrades off")
end)
