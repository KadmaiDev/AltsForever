-- Tests: upgrades your characters can craft, under the equipment flyout (Alt over a slot
-- on the character sheet). Loaded by tests/run.lua.

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
    -- The game's flyout: a frame and the function that opens it for a slot button.
    EquipmentFlyoutFrame = CreateFrame("Frame")
    EquipmentFlyout_Show = function() EquipmentFlyoutFrame:Show() end
    -- The character sheet and three of its slot buttons.
    PaperDollFrame = CreateFrame("Frame")
    for name, id in pairs({ Head = 1, Back = 15, Hands = 10 }) do
        local b = CreateFrame("Button", "Character" .. name .. "Slot")
        b.GetID = function() return id end
        b.CreateTexture = function(self) self.mark = CreateFrame("Frame") return self.mark end -- the anvil
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

function flySlot(id) return { GetID = function() return id end } end

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
    eq(head[1].at, 28, "the helm, from level 28 (shown greyed)")
    eq(#ns.CraftableUpgrades(2), 0, "nothing for the neck")
end)

test("holding Alt over a slot shows what your characters can craft under the flyout; hover says who", function()
    local ns = flyStart()
    EquipmentFlyout_Show(flySlot(10))
    local strip = AltsForeverCraftFlyout
    assert(strip and strip:IsShown(), "shown under the flyout")
    local shown = {}
    for _, child in ipairs({ strip:GetChildren() }) do
        if child:IsShown() and child.entry then shown[#shown + 1] = child end
    end
    eq(#shown, 2)
    GameTooltip.lines = {}
    shown[1].scripts.OnEnter(shown[1])
    local text = {}
    for _, line in ipairs(GameTooltip.lines) do text[#text + 1] = tostring(line[1]) end
    assert(table.concat(text, "\n"):find("Crafted by [PALADIN]Smith (Blacksmithing)", 1, true), table.concat(text, "\n"))
    EquipmentFlyoutFrame:Hide()
    eq(strip:IsShown(), false, "goes with the flyout")
    EquipmentFlyout_Show(flySlot(2))
    eq(strip:IsShown(), false, "nothing to craft for the neck: nothing shown")
    ns.SetUpgrades(false)
    EquipmentFlyout_Show(flySlot(10))
    eq(strip:IsShown(), false, "upgrades off")
end)

test("the character sheet marks slots with a craftable upgrade you can wear now that binds when equipped", function()
    local ns = flyStart()
    PaperDollFrame.scripts.OnShow(PaperDollFrame)
    local hands, back, head = CharacterHandsSlot, CharacterBackSlot, CharacterHeadSlot
    eq(hands.mark and hands.mark:IsShown(), true, "the mail gloves Smith makes")
    eq(back.mark and back.mark:IsShown(), true, "the cape: cloth for everyone")
    eq(head.mark, nil, "the helm needs level 28: not wearable yet")
    -- Hovering a marked slot lists the best few under the game's tooltip.
    GameTooltip:SetOwner(hands)
    hands.scripts.OnEnter(hands)
    local text = {}
    for _, line in ipairs(GameTooltip.lines) do text[#text + 1] = tostring(line[1]) .. " | " .. tostring(line[2]) end
    text = table.concat(text, "\n")
    assert(text:find("Your characters can craft", 1, true), text)
    assert(text:find("Linked Gloves", 1, true) and text:find("Smith", 1, true), text)
    assert(not text:find("My Bound Gauntlets", 1, true), "binds on pickup: not marked\n" .. text)
    GameTooltip:SetOwner(back)
    back.scripts.OnEnter(back)
    eq(#GameTooltip.lines, 3, "the cape")
    -- The helm needs level 28: not wearable yet, so no mark and nothing added.
    GameTooltip:SetOwner(head)
    if head.scripts.OnEnter then head.scripts.OnEnter(head) end
    eq(#GameTooltip.lines, 0, "not wearable yet")
    -- Upgrades off: nothing.
    ns.SetUpgrades(false)
    GameTooltip:SetOwner(hands)
    hands.scripts.OnEnter(hands)
    eq(#GameTooltip.lines, 0, "upgrades off")
end)
