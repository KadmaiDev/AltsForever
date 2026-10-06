-- Tests: upgrades in item tooltips, talent specs and Legacy's Well Rested. Loaded by
-- tests/run.lua.

-- Items used below (wow.item registers them and returns their links).
function upItems()
    return {
        gloves = upItem(5001, "Supple Gloves", { sub = 2, loc = "INVTYPE_HAND", level = 20,
            stats = { ITEM_MOD_AGILITY_SHORT = 6, ITEM_MOD_STAMINA_SHORT = 3 } }),
        oldGloves = upItem(5002, "Worn Gloves", { sub = 2, loc = "INVTYPE_HAND", bind = 1,
            stats = { ITEM_MOD_AGILITY_SHORT = 2 } }),
        mailGloves = upItem(5003, "Ringed Gloves", { sub = 3, loc = "INVTYPE_HAND", bind = 1,
            stats = { ITEM_MOD_STRENGTH_SHORT = 4 } }),
    }
end

-- The upgrade rows of a tooltip as "left = right", colour codes removed, and the header.
function upRows(lines)
    local out, header, inBlock = {}, nil, false
    for _, line in ipairs(lines) do
        local left = line[1]
        if left == "Upgrade for" or left == "Makes an upgrade for" then
            header, inBlock = left, true
        elseif inBlock then
            if left == " " then break end
            out[#out + 1] = left .. " = " .. tostring(line[2]):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        end
    end
    return table.concat(out, "\n"), header
end

-- Items registered with upItem, kept so upStart can register them again: loading the
-- addon starts the fake client afresh.
UP_ITEMS = {}

function upItem(id, name, opts)
    UP_ITEMS[id] = { name, opts }
    return wow.item(id, name, opts)
end

-- Logs in as Aldric (a level 24 mage) with these characters saved.
function upStart(chars)
    local ns = wow.load(FILES)
    for id, def in pairs(UP_ITEMS) do wow.item(id, def[1], def[2]) end
    local items = upItems()
    wow.login({ v = 2, chars = chars or {} })
    return ns, items
end

function upHover(id, link, text)
    return upRows(wow.hover(GameTooltip, id, text, link))
end

function upHunter(items, data)
    data = data or {}
    data.level = data.level or 25
    data.gear = data.gear or { [10] = items.oldGloves }
    return alt("Tarn Moon", "HUNTER", data)
end

test("a BoE item lists who it's an upgrade for, best gain first, with the slot and gain", function()
    local items = upItems()
    local ns = upStart({
        ["Tarn Moon"] = upHunter(items),
        ["Vesp Ash"] = alt("Vesp Ash", "WARRIOR", { level = 20, gear = { [10] = items.mailGloves } }),
        ["Low Rogue"] = alt("Low Rogue", "ROGUE", { level = 10, gear = {} }),
    })
    local rows, header = upHover(5001, items.gloves)
    eq(header, "Upgrade for")
    -- Hunter: 6 agi x 2.4 + 3 sta x 0.4 = 15.6 against 2 agi x 2.4 = 4.8. Warrior: 9.9
    -- against 4 str x 2 = 8. The rogue is 10 levels short; the mage can't wear leather.
    eq(rows, "[HUNTER]Tarn Moon = Hands · +225%\n[WARRIOR]Vesp Ash = Hands · +24%")
end)

test("an empty slot, and an alt up to 5 levels short as 'at level N'; further off, nothing", function()
    local items = upItems()
    upStart({
        ["Tarn Moon"] = upHunter(items, { level = 16, gear = {} }),
        ["Vesp Ash"] = alt("Vesp Ash", "WARRIOR", { level = 14, gear = {} }),
    })
    eq(upHover(5001, items.gloves), "[HUNTER]Tarn Moon = Hands · empty slot · at level 20")
end)

test("mail and plate wait for level 40; armour a class never wears shows nothing", function()
    upItems()
    local plate = upItem(5010, "Iron Breastplate", { sub = 4, loc = "INVTYPE_CHEST", level = 35,
        stats = { ITEM_MOD_STRENGTH_SHORT = 10 } })
    upStart({
        ["Vesp Ash"] = alt("Vesp Ash", "WARRIOR", { level = 36, gear = {} }),
        ["Old Guard"] = alt("Old Guard", "WARRIOR", { level = 40, gear = {} }),
        ["Young Guard"] = alt("Young Guard", "WARRIOR", { level = 34, gear = {} }),
        ["Sly"] = alt("Sly", "ROGUE", { level = 40, gear = {} }),
    })
    eq(upHover(5010, plate), "[WARRIOR]Old Guard = Chest · empty slot\n[WARRIOR]Vesp Ash = Chest · empty slot · at level 40")
end)

test("a ring is compared with the weaker of the two worn", function()
    local items = upItems()
    local ring = upItem(5020, "Jade Ring", { loc = "INVTYPE_FINGER", stats = { ITEM_MOD_AGILITY_SHORT = 5 } })
    local strong = upItem(5021, "Strong Ring", { loc = "INVTYPE_FINGER", bind = 1, stats = { ITEM_MOD_AGILITY_SHORT = 10 } })
    local weak = upItem(5022, "Weak Ring", { loc = "INVTYPE_FINGER", bind = 1, stats = { ITEM_MOD_AGILITY_SHORT = 4 } })
    upStart({ ["Tarn Moon"] = upHunter(items, { gear = { [11] = strong, [12] = weak } }) })
    eq(upHover(5020, ring), "[HUNTER]Tarn Moon = Finger · +25%")
    upStart({ ["Tarn Moon"] = upHunter(items, { gear = { [11] = ring, [12] = weak } }) })
    eq(upHover(5020, ring), "", "already wearing one")
end)

test("already wearing one, or a gain under 3%: no row", function()
    local items = upItems()
    local same = upItem(5030, "Agile Gloves", { sub = 2, loc = "INVTYPE_HAND", stats = { ITEM_MOD_AGILITY_SHORT = 2.05 } })
    upStart({ ["Tarn Moon"] = upHunter(items) })
    eq(upHover(5030, same), "", "2.5% better")
    eq(upHover(5002, items.oldGloves), "", "the same gloves")
end)

test("a two-hander is compared with main and off hand together; a one-hander never with a two-hander", function()
    local items = upItems()
    local staff = upItem(5040, "Long Staff", { class = 2, sub = 10, loc = "INVTYPE_2HWEAPON",
        stats = { ITEM_MOD_AGILITY_SHORT = 10 } })
    local sword = upItem(5041, "Short Sword", { class = 2, sub = 7, loc = "INVTYPE_WEAPON", bind = 1,
        stats = { ITEM_MOD_AGILITY_SHORT = 3 } })
    local dagger = upItem(5042, "Dagger", { class = 2, sub = 15, loc = "INVTYPE_WEAPON",
        stats = { ITEM_MOD_AGILITY_SHORT = 5 } })
    upStart({ ["Tarn Moon"] = upHunter(items, { gear = { [16] = sword, [17] = sword } }) })
    eq(upHover(5040, staff), "[HUNTER]Tarn Moon = Two-Hand · +67%", "10 agi against 3 + 3")
    eq(upHover(5042, dagger), "[HUNTER]Tarn Moon = One-Hand · +67%", "a dual wielder: either hand")
    upStart({ ["Tarn Moon"] = upHunter(items, { gear = { [16] = staff } }) })
    eq(upHover(5042, dagger), "", "against a two-hander")
end)

test("bind on pickup and soulbound items show only you", function()
    local items = upItems()
    local robe = upItem(5050, "Silk Robe", { sub = 1, loc = "INVTYPE_CHEST", bind = 1,
        stats = { ITEM_MOD_INTELLECT_SHORT = 5 } })
    local cloak = upItem(5051, "Wool Cloak", { sub = 1, loc = "INVTYPE_CLOAK",
        stats = { ITEM_MOD_STAMINA_SHORT = 4 } })
    upStart({ ["Tarn Moon"] = upHunter(items), ["Abe"] = alt("Abe", "WARRIOR", { level = 20, gear = {} }) })
    eq(upHover(5050, robe), "[MAGE]Aldric = Chest · empty slot", "bind on pickup")
    eq(upHover(5051, cloak), "[MAGE]Aldric = Back · empty slot\n[WARRIOR]Abe = Back · empty slot\n[HUNTER]Tarn Moon = Back · empty slot",
        "a cloak anyone can wear: you first, then by gain and name")
    eq(upHover(5051, cloak, { "Wool Cloak", "Soulbound" }), "[MAGE]Aldric = Back · empty slot", "soulbound")
end)

test("a 'Classes:' line and a profession requirement are respected", function()
    local items = upItems()
    local hunterOnly = upItem(5060, "Tracker's Gloves", { sub = 2, loc = "INVTYPE_HAND",
        stats = { ITEM_MOD_AGILITY_SHORT = 8 } })
    local goggles = upItem(5061, "Goggles", { sub = 1, loc = "INVTYPE_HEAD",
        stats = { ITEM_MOD_AGILITY_SHORT = 8 } })
    upStart({
        ["Tarn Moon"] = upHunter(items, { profs = { Engineering = 120 } }),
        ["Sly"] = alt("Sly", "ROGUE", { level = 25, gear = {} }),
    })
    eq(upHover(5060, hunterOnly, { "Tracker's Gloves", "Classes: Hunter" }), "[HUNTER]Tarn Moon = Hands · +300%")
    eq(upHover(5061, goggles, { "Goggles", "Requires Engineering (100)" }), "[HUNTER]Tarn Moon = Head · empty slot")
end)

test("a recipe is judged on the item it makes; one that binds on pickup lists only who can learn it", function()
    local items = upItems()
    local boe = upItem(5070, "Heavy Woolen Cloak", { sub = 1, loc = "INVTYPE_CLOAK", stats = { ITEM_MOD_STAMINA_SHORT = 3 } })
    local bop = upItem(5071, "Bound Cloak", { sub = 1, loc = "INVTYPE_CLOAK", bind = 1, stats = { ITEM_MOD_STAMINA_SHORT = 3 } })
    upStart({
        ["Tarn Moon"] = upHunter(items),
        ["Tailor"] = alt("Tailor", "WARLOCK", { level = 20, gear = {}, profs = { Tailoring = 90 },
            recipes = { Tailoring = {} } }),
    })
    local text = wow.recipeItem(4346, "Pattern: Heavy Woolen Cloak", "Tailoring", 75)
    local rows, header = upHover(4346, boe, text)
    eq(header, "Makes an upgrade for")
    eq(rows, "[MAGE]Aldric = Back · empty slot\n[WARLOCK]Tailor = Back · empty slot\n[HUNTER]Tarn Moon = Back · empty slot")
    text = wow.recipeItem(4347, "Pattern: Bound Cloak", "Tailoring", 75)
    eq(upHover(4347, bop, text), "[WARLOCK]Tailor = Back · empty slot", "only the tailor can make it")
    eq(upHover(4348, nil, wow.recipeItem(4348, "Pattern: Nothing", "Tailoring", 75)), "", "no item linked")
end)

test("talents pick the role, a choice from the menu or /af role overrides it", function()
    local items = upItems()
    local healRing = upItem(5080, "Healing Ring", { loc = "INVTYPE_FINGER", stats = { ITEM_MOD_SPELL_HEALING_DONE_SHORT = 10 } })
    local ns = upStart({ ["Pria"] = alt("Pria", "PRIEST", { level = 25, gear = {} }) })
    local c = ns.db.chars.Pria
    eq(ns.RoleOf(c), "caster", "class default")
    eq(upHover(5080, healRing), "", "healing only: nothing for a caster")
    c.spec = 2
    ns.UpgradesChanged()
    eq(ns.RoleOf(c), "healer", "Holy tab")
    eq(upHover(5080, healRing), "[PRIEST]Pria = Finger · empty slot")
    SlashCmdList.ALTSFOREVER("role pria caster")
    eq(c.role, "caster")
    eq(upHover(5080, healRing), "", "the choice wins over talents")
    SlashCmdList.ALTSFOREVER("role Pria auto")
    eq(c.role, nil)
    assert(wow.printed[#wow.printed]:find("follow their talents (Healer)", 1, true), wow.printed[#wow.printed])
    SlashCmdList.ALTSFOREVER("role Pria tank")
    assert(wow.printed[#wow.printed]:find("Choose from: healer, caster, or auto", 1, true), wow.printed[#wow.printed])
    -- The overview's character menu: Upgrade role, Automatic first.
    ns.ShowCharacterMenu(UIParent, "Pria")
    local roles = wow.menuItem("Upgrade role")
    local texts = {}
    for _, item in ipairs(roles.items) do texts[#texts + 1] = item.text end
    eq(table.concat(texts, " | "), "Automatic (Healer) | Healer | Caster")
    roles.items[3].setSelected()
    eq(c.role, "caster")
    eq(roles.items[3].isSelected(), true)
    -- A hunter has nothing to choose.
    ns.db.chars["Tarn Moon"] = upHunter(items)
    ns.ShowCharacterMenu(UIParent, "Tarn Moon")
    eq(wow.menuItem("Upgrade role"), nil)
end)

test("talent tabs are the groups of columns; the stray far column counts as the third", function()
    local ns = wow.load(FILES)
    -- Kadmai's ranked talents (checked in game) among the hunter tree's columns.
    local nodes = { { 1620, 5 }, { 2820, 1 }, { 2820, 1 }, { 2220, 4 }, { 2220, 5 }, { 2220, 2 }, { 1020, 2 }, { 2220, 1 } }
    for _, x in ipairs({ 5020, 5620, 6220, 6820, 9080, 9680, 10280, 10880, 102800 }) do nodes[#nodes + 1] = { x, 0 } end
    local points = ns.TabPoints(nodes)
    eq(points[1] .. "/" .. points[2] .. "/" .. points[3], "21/0/0")
    eq(ns.SpecFromPoints(points), 1)
    nodes[#nodes] = { 102800, 3 } -- Lightning Reflexes
    eq(ns.TabPoints(nodes)[3], 3)
    eq(ns.SpecFromPoints({ 5, 4, 0 }), nil, "under 10 points")
    eq(ns.SpecFromPoints({ 8, 8, 0 }), nil, "a tie")
    eq(ns.SpecFromPoints({ 2, 9, 1 }), 2)
end)

test("the spec is read on entering the world and again when talents change", function()
    local ns = wow.load(FILES)
    wow.talents = { { 1020, 5 }, { 1620, 5 }, { 5020, 0 }, { 9080, 1 } }
    wow.login(nil)
    wow.fire("PLAYER_ENTERING_WORLD")
    eq(ns.char.spec, 1)
    wow.talents[3] = { 5020, 12 }
    wow.fire("TRAIT_CONFIG_UPDATED", 101)
    eq(ns.char.spec, 2)
end)

test("Well Rested: rested XP builds 4% faster with a 4% higher cap per rank", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    ns.db.wellRested = 5
    local inn = { level = 20, xpMax = 10000, rested = 1000, resting = true, updated = NOW - 8 * HOUR }
    eq(ns.RestedNow(inn, NOW), 1600, "500 x 1.2 in 8 hours")
    local long = { level = 20, xpMax = 10000, rested = 0, resting = true, updated = NOW - 400 * DAY }
    eq(select(2, ns.RestedNow(long, NOW)), 18000, "cap 150% x 1.2")
    ns.db.wellRested = nil
    eq(ns.RestedNow(inn, NOW), 1500, "never read: no bonus")
end)

test("Well Rested: the rank is read from the Legacy tree on entering the world and when it changes", function()
    local ns = wow.load(FILES)
    local node = assert(ns.WELL_RESTED_NODE, "Well Rested's trait node is known")
    wow.legacy = { [node] = 5 }
    wow.login(nil)
    wow.fire("PLAYER_ENTERING_WORLD")
    eq(ns.db.wellRested, 5)
    wow.legacy[node] = 2
    wow.fire("TRAIT_CONFIG_UPDATED", 201)
    eq(ns.db.wellRested, 2)
    wow.legacy = { [node + 1] = 4 } -- the node isn't in this config: left alone
    wow.fire("TRAIT_CONFIG_UPDATED", 201)
    eq(ns.db.wellRested, 2)
end)

test("gear that isn't loaded yet is asked for; the alt shows once it arrives", function()
    local items = upItems()
    upStart({ ["Tarn Moon"] = upHunter(items) })
    wow.uncached[5002] = true
    wow.itemLoads = {}
    eq(upHover(5001, items.gloves), "")
    eq(wow.itemLoads[1], 5002)
    wow.uncached[5002] = nil
    wow.fire("GET_ITEM_INFO_RECEIVED", 5002, true)
    eq(upHover(5001, items.gloves), "[HUNTER]Tarn Moon = Hands · +225%")
end)

test("hovering the same item again works nothing out again; your new gear does", function()
    local items = upItems()
    local ns = upStart({ ["Tarn Moon"] = upHunter(items) })
    upHover(5001, items.gloves)
    local first = wow.itemInfoReads
    upHover(5001, items.gloves)
    upHover(5001, items.gloves)
    eq(wow.itemInfoReads, first, "nothing looked up again")
    local cloak = upItem(5051, "Wool Cloak", { sub = 1, loc = "INVTYPE_CLOAK", stats = { ITEM_MOD_STAMINA_SHORT = 4 } })
    eq(upHover(5051, cloak), "[MAGE]Aldric = Back · empty slot\n[HUNTER]Tarn Moon = Back · empty slot")
    wow.gearLinks[15], wow.inventory[15] = cloak, 5051
    wow.fire("PLAYER_EQUIPMENT_CHANGED", 15)
    eq(upHover(5051, cloak), "[HUNTER]Tarn Moon = Back · empty slot", "you wear one now")
end)

test("the setting turns upgrades off and on: /af upgrades, the menu and the Options page", function()
    local items = upItems()
    local ns = upStart({ ["Tarn Moon"] = upHunter(items) })
    SlashCmdList.ALTSFOREVER("upgrades")
    eq(AltsForeverDB.upgradesOff, true)
    eq(upHover(5001, items.gloves), "")
    ns.ShowOptionsMenu(UIParent)
    wow.menuItem("Show upgrades").setSelected()
    eq(AltsForeverDB.upgradesOff, nil)
    eq(upHover(5001, items.gloves), "[HUNTER]Tarn Moon = Hands · +225%")
end)
