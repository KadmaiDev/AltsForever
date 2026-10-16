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
    wow.player.class = "WARRIOR"
    -- The game's flyout: a frame and the function that opens it for a slot button.
    EquipmentFlyoutFrame = CreateFrame("Frame")
    EquipmentFlyout_Show = function() EquipmentFlyoutFrame:Show() end
    wow.login({ v = 2, chars = {
        ["Aldric"] = alt("Aldric", "WARRIOR", { level = 24, gear = {}, realm = "Realm",
            crafts = { Blacksmithing = { [6004] = "my bound gauntlets" } } }),
        ["Smith"] = alt("Smith", "PALADIN", { realm = "Realm", crafts = { Blacksmithing = {
            [6001] = "linked gloves", [6002] = "leather gloves", [6003] = "bound mail gloves", [6007] = "plate gloves" },
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
    eq(#ns.CraftableUpgrades(1), 0, "nothing for the head")
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
    EquipmentFlyout_Show(flySlot(1))
    eq(strip:IsShown(), false, "nothing to craft for the head: nothing shown")
    ns.SetUpgrades(false)
    EquipmentFlyout_Show(flySlot(10))
    eq(strip:IsShown(), false, "upgrades off")
end)
