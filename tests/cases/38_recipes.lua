-- Tests: browsing an alt's professions (Recipes.lua) and what the profession scan stores for
-- it (Professions.lua): categories, each recipe's colour, recipe IDs and icons. Loaded by
-- tests/run.lua.

SHARPENING_WHEEL, ROUGH_STONE_ITEM, COPPER_BAR = 236001, 2835, 2840
ROUGH_SHARPENING, ROUGH_STONE_REAGENT = 2862, 2835

-- Blacksmithing as the game lists it: categories, colours (0 orange .. 3 grey), icons and
-- how many one craft makes.
function smithWindow(skill)
    wow.profs = { { "Blacksmithing", skill or 96 } }
    wow.tradeskill.prof = "Blacksmithing"
    wow.categories = { [10] = { "Camping", 5 }, [20] = { "Weapon Stones", 2 }, [30] = { "Mail Chestguards", 9 } }
    wow.tradeskill.recipes = {
        [5001] = { name = "Sharpening Wheel", learned = true, item = SHARPENING_WHEEL, grey = 90, cat = 10,
            icon = 900001, diff = 3, reagents = { { ROUGH_STONE_ITEM, 1 }, { COPPER_BAR, 1 } } },
        [5002] = { name = "Rough Sharpening Stone", learned = true, item = ROUGH_SHARPENING, grey = 65, cat = 20,
            icon = 900002, diff = 3, made = 2, reagents = { { ROUGH_STONE_ITEM, 1 } } },
        [5003] = { name = "Rough Bronze Cuirass", learned = true, item = 2866, grey = 145, cat = 30,
            icon = 900003, diff = 0, reagents = { { 2841, 7 } } },
        [5004] = { name = "Copper Chain Vest", learned = false, grey = 75, cat = 30 },
    }
    wow.fire("TRADE_SKILL_SHOW")
end

test("a profession scan stores each recipe's colour, category, ID and icon, and the skill they were read at", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    smithWindow(96)
    local c = ns.char
    eq(c.recipes.Blacksmithing["sharpening wheel"], 3, "grey for them")
    eq(c.recipes.Blacksmithing["rough bronze cuirass"], 0, "orange for them")
    eq(c.recipes.Blacksmithing["copper chain vest"], nil, "not learned")
    eq(c.recipesAt.Blacksmithing, 96)
    local info = AltsForeverDB.recipeInfo.Blacksmithing
    eq(info["rough sharpening stone"], "65;Rough Sharpening Stone;,2835:1;5002;20;900002;2", "makes two")
    eq(info["sharpening wheel"], "90;Sharpening Wheel;,2835:1,2840:1;5001;10;900001", "makes one: left off")
    eq(AltsForeverDB.recipeCategories[10], "5;Camping")
    eq(AltsForeverDB.recipeCategories[30], "9;Mail Chestguards")
    local grey, name, reagents, id, cat, icon, made = ns.ParseRecipeInfo(info["rough sharpening stone"])
    eq(grey, 65); eq(name, "Rough Sharpening Stone"); eq(reagents, ",2835:1"); eq(id, 5002); eq(cat, 20)
    eq(icon, 900002); eq(made, 2)
    -- Saved before: three fields, still read.
    grey, name, reagents, id = ns.ParseRecipeInfo("75;Bolt of Linen Cloth;,2589:2")
    eq(grey, 75); eq(name, "Bolt of Linen Cloth"); eq(reagents, ",2589:2"); eq(id, nil)
    -- A recipe whose colour the game didn't give stays plain known.
    wow.tradeskill.recipes[5001].diff = nil
    wow.fire("TRADE_SKILL_LIST_UPDATE")
    wow.fire("TRADE_SKILL_SHOW")
    eq(c.recipes.Blacksmithing["sharpening wheel"], true)
end)

test("damaged recipe colours, skills and categories are repaired at load", function()
    local ns = wow.load(FILES)
    wow.login({ v = 2, recipeCategories = { [10] = "5;Camping", [20] = 7, x = "1;Bad" }, chars = {
        ["Vesp Ash"] = alt("Vesp Ash", "PALADIN", { recipesAt = { Blacksmithing = 90, Mining = "x" } }),
        ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { recipesAt = "lots" }),
    } })
    eq(AltsForeverDB.recipeCategories[10], "5;Camping")
    eq(AltsForeverDB.recipeCategories[20], nil); eq(AltsForeverDB.recipeCategories.x, nil)
    eq(AltsForeverDB.chars["Vesp Ash"].recipesAt.Blacksmithing, 90)
    eq(AltsForeverDB.chars["Vesp Ash"].recipesAt.Mining, nil)
    eq(AltsForeverDB.chars["Tarn Moon"].recipesAt, nil)
end)

test("sync carries recipe categories, and a fuller recipe record replaces an older one", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.login({ v = 2, syncWith = { ["Bob Smith"] = true },
        recipeInfo = { Blacksmithing = { ["sharpening wheel"] = "90;Sharpening Wheel;,2835:1,2840:1",
            ["rough sharpening stone"] = "65;Rough Sharpening Stone;,2835:1;5002;20;900002;2" } },
        recipeCategories = { [20] = "2;Weapon Stones" },
        chars = { ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { updated = NOW - HOUR,
            recipes = { Blacksmithing = { ["rough sharpening stone"] = 2 } } }) } })
    -- Ours, sent with the categories its recipes are filed under.
    syncFrom(ns, "Bob Smith", { k = "hello", v = 1, have = {} })
    syncPump()
    syncFrom(ns, "Bob Smith", { k = "want", keys = { "Tarn Moon" } })
    syncPump()
    local sent
    for _, msg in ipairs(syncSent(ns, "Bob Smith")) do
        if msg.k == "char" then sent = msg end
    end
    eq(sent.ri.Blacksmithing["rough sharpening stone"], "65;Rough Sharpening Stone;,2835:1;5002;20;900002;2")
    eq(sent.rc[20], "2;Weapon Stones")
    -- Theirs: a fuller record of the wheel, and its category.
    syncFrom(ns, "Bob Smith", { k = "char", key = "Bob Smith", c = alt("Bob Smith", "WARRIOR", { updated = NOW,
            recipes = { Blacksmithing = { ["sharpening wheel"] = 3 } } }),
        ri = { Blacksmithing = { ["sharpening wheel"] = "90;Sharpening Wheel;,2835:1,2840:1;5001;10;900001",
            ["rough sharpening stone"] = "65;Rough Sharpening Stone;,2835:1" } },
        rc = { [10] = "5;Camping", [20] = "9;Renamed", [30] = "bad" } })
    local info = ns.db.recipeInfo.Blacksmithing
    eq(info["sharpening wheel"], "90;Sharpening Wheel;,2835:1,2840:1;5001;10;900001", "theirs says more")
    eq(info["rough sharpening stone"], "65;Rough Sharpening Stone;,2835:1;5002;20;900002;2", "ours says more: kept")
    eq(ns.db.recipeCategories[10], "5;Camping")
    eq(ns.db.recipeCategories[20], "2;Weapon Stones", "ours kept")
    eq(ns.db.recipeCategories[30], nil, "not in the expected shape")
    eq(ns.db.chars["Bob Smith"].recipes.Blacksmithing["sharpening wheel"], 3)
end)

-- A smith who last opened Blacksmithing at 96 and is 120 now: the wheel has gone grey since.
-- Bags and bank hold enough for one wheel, three stones and one cuirass.
function smithAlt(extra)
    local data = {
        level = 30, profs = { Blacksmithing = 120, Herbalism = 50, Cooking = 10 },
        profMax = { Blacksmithing = 150, Herbalism = 75, Cooking = 75 },
        prof1 = "Blacksmithing", prof2 = "Herbalism",
        recipes = { Blacksmithing = { ["sharpening wheel"] = 2, ["rough sharpening stone"] = 3,
            ["rough bronze cuirass"] = 0, ["old recipe"] = true } },
        recipesAt = { Blacksmithing = 96 },
        crafts = { Blacksmithing = { [SHARPENING_WHEEL] = "sharpening wheel", [ROUGH_SHARPENING] = "rough sharpening stone",
            [2866] = "rough bronze cuirass" } },
        bags = { [ROUGH_STONE_ITEM] = 3, [COPPER_BAR] = 1 }, bank = { [2841] = 7 },
    }
    for k, v in pairs(extra or {}) do data[k] = v end
    return {
        v = 2,
        recipeInfo = { Blacksmithing = {
            ["sharpening wheel"] = "90;Sharpening Wheel;,2835:1,2840:1;5001;10;900001",
            ["rough sharpening stone"] = "65;Rough Sharpening Stone;,2835:1;5002;20;900002;2",
            ["rough bronze cuirass"] = "145;Rough Bronze Cuirass;,2841:7;5003;30;900003" } },
        recipeCategories = { [10] = "5;Camping", [20] = "2;Weapon Stones", [30] = "9;Mail Chestguards" },
        profArt = { Blacksmithing = "164;136241", Herbalism = "182;136246", Cooking = "185;133971" },
        chars = { ["Vesp Ash"] = alt("Vesp Ash", "PALADIN", data) },
    }
end

-- The list as text: "# Category" for a heading, else "name [n] (colour)".
function recipeRows(f)
    local out = {}
    for _, row in ipairs(f.rows) do
        if row:IsShown() then
            if row.entry.recipes then
                out[#out + 1] = "# " .. row.catText:GetText()
            else
                out[#out + 1] = row.label:GetText() .. (row.count:GetText() or "") .. (row.skill:IsShown() and "^" or "")
            end
        end
    end
    return table.concat(out, " | ")
end

test("an alt's recipes: the game's categories in order, colours as of now, what they could make", function()
    local ns = wow.load(FILES)
    wow.login(smithAlt())
    local c = ns.db.chars["Vesp Ash"]
    local book = ns.RecipeBook(c, "Blacksmithing")
    eq(#book, 4)
    eq(book[1].name, "Weapon Stones"); eq(book[2].name, "Camping"); eq(book[3].name, "Mail Chestguards")
    eq(book[4].name, "Other", "a recipe saved before categories were")
    local wheel = book[2].recipes[1]
    eq(wheel.name, "Sharpening Wheel")
    eq(wheel.colour, 3, "green when read at 96, grey at 90: grey now at 120")
    eq(wheel.count, 1, "one copper bar")
    eq(wheel.item, SHARPENING_WHEEL); eq(wheel.recipeID, 5001); eq(wheel.icon, 900001)
    eq(book[1].recipes[1].made, 2)
    eq(book[1].recipes[1].count, 3)
    eq(book[3].recipes[1].colour, 0, "still orange")
    eq(book[3].recipes[1].count, 1, "seven bronze bars in the bank")
    eq(book[4].recipes[1].colour, nil, "no colour saved")
    eq(book[4].recipes[1].count, nil, "no reagents known")
    -- Filters and search.
    book = ns.RecipeBook(c, "Blacksmithing", nil, { skillups = true })
    eq(#book, 2); eq(book[1].name, "Mail Chestguards"); eq(book[2].name, "Other")
    book = ns.RecipeBook(c, "Blacksmithing", nil, { craftable = true })
    eq(#book, 3)
    c.bags[COPPER_BAR] = nil
    book = ns.RecipeBook(c, "Blacksmithing", nil, { craftable = true })
    eq(#book, 2, "no copper bar: the wheel can't be made")
    book = ns.RecipeBook(c, "Blacksmithing", "sharp")
    eq(#book, 2); eq(book[1].recipes[1].name, "Rough Sharpening Stone")
    eq(ns.RecipeBook(c, "Cooking"), nil, "never opened")
    local _, old = ns.RecipeBook(c, "Blacksmithing")
    eq(old, true, "one recipe read before categories were")
    c.recipes.Blacksmithing["old recipe"] = nil
    _, old = ns.RecipeBook(c, "Blacksmithing")
    eq(old, false)
    -- Tabs: no Herbalism (gathering, nothing read), Cooking though never opened.
    local tabs = ns.RecipeTabs(c)
    eq(#tabs, 2); eq(tabs[1].name, "Blacksmithing"); eq(tabs[2].name, "Cooking")
end)

test("the profession window shows an offline alt's recipes as the game's window would", function()
    local ns = wow.load(FILES)
    wow.ns = ns
    wow.itemNames[ROUGH_STONE_ITEM], wow.itemNames[COPPER_BAR] = "Rough Stone", "Copper Bar"
    wow.itemQuality[SHARPENING_WHEEL] = 2
    wow.atlases["Professions-Icon-Skill-High"] = { width = 13, height = 13 }
    wow.login(smithAlt())
    ns.ShowCharacterMenu(UIParent, "Vesp Ash")
    wow.menuItem("Professions").fn()
    local f = AltsForeverRecipesFrame
    eq(f:IsShown(), true)
    eq(f.titleText, "Blacksmithing")
    eq(f.rank.text:GetText():find("120", 1, true) ~= nil, true)
    eq(f.who:GetText(), "[PALADIN]Vesp", "first name only: a full one didn't fit")
    eq(f.tabs[1].prof, "Blacksmithing"); eq(f.tabs[2].prof, "Cooking"); eq(f.tabs[3], nil)
    eq(recipeRows(f), "# Weapon Stones | Rough Sharpening Stone [3]  | # Camping | Sharpening Wheel [1]  | "
        .. "# Mail Chestguards | Rough Bronze Cuirass [1] ^ | # Other | old recipe")
    -- The first recipe is shown: made two at a time, its reagent from the bags.
    local d = f.details
    eq(d.name:GetText(), "Rough Sharpening Stone")
    eq(d.output.count:GetText(), 2)
    eq(d.slots[1].name:GetText(), "3/1 Rough Stone")
    eq(d.slots[2]:IsShown(), false)
    eq(d.empty:IsShown(), false)
    eq(d.note:GetText(), "Open Blacksmithing on Vesp Ash once to sort these recipes into the game's categories and show their skill-up arrows.",
        "one recipe was read before categories were")
    -- Another recipe.
    f.rows[4].scripts.OnClick(f.rows[4])
    eq(d.name:GetText(), "Sharpening Wheel")
    eq(d.slots[2].name:GetText(), "1/1 Copper Bar")
    eq(d.desc:GetText():find("No skill-up", 1, true) ~= nil, true, "grey now")
    eq(f.rows[4].selectedTex:IsShown(), true)
    -- Folding a category away and back.
    f.rows[1].scripts.OnClick(f.rows[1])
    eq(recipeRows(f):sub(1, 46), "# Weapon Stones | # Camping | Sharpening Wheel")
    f.rows[1].scripts.OnClick(f.rows[1])
    -- The filter menu: skill-ups only.
    local menu = MenuUtil.CreateContextMenu(f.filter, f.filterMenu)
    menu.items[2].setSelected()
    eq(recipeRows(f), "# Mail Chestguards | Rough Bronze Cuirass [1] ^ | # Other | old recipe")
    eq(d.name:GetText(), "Rough Bronze Cuirass", "the shown recipe was filtered out: the first left")
    menu.items[2].setSelected()
    -- Searching.
    f.search:SetText("Bronze")
    f.search.scripts.OnTextChanged(f.search, true)
    eq(recipeRows(f), "# Mail Chestguards | Rough Bronze Cuirass [1] ^")
    f.search:SetText("zzz")
    f.search.scripts.OnTextChanged(f.search, true)
    eq(recipeRows(f), "")
    eq(d.empty:IsShown(), true)
    eq(d.empty:GetText(), "No recipes match.")
    f.search:SetText("")
    f.search.scripts.OnTextChanged(f.search, true)
    -- Cooking was never opened on them.
    f.tabs[2].scripts.OnClick(f.tabs[2])
    eq(f.titleText, "Cooking")
    eq(recipeRows(f), "")
    eq(d.empty:GetText():find("hasn't opened Cooking", 1, true) ~= nil, true)
    eq(d.output:IsShown(), false)
    -- The overview's button: the character you're on has none, so the first who has; again closes it.
    f:Hide()
    ns.ToggleOverview(true)
    AltsForeverFrame.profsButton.scripts.OnClick(AltsForeverFrame.profsButton)
    eq(f:IsShown(), true)
    eq(f.who:GetText(), "[PALADIN]Vesp")
    AltsForeverFrame.profsButton.scripts.OnClick(AltsForeverFrame.profsButton)
    eq(f:IsShown(), false)
    ns.ShowRecipes("Vesp Ash", "Cooking")
    -- The same again closes it; /af prof opens it.
    ns.ShowRecipes("Vesp Ash")
    eq(f:IsShown(), false)
    SlashCmdList.ALTSFOREVER("prof vesp ash")
    eq(f:IsShown(), true)
    eq(f.titleText, "Cooking", "the profession shown before")
end)

test("the profession window: reagent names still loading, a character without professions, forgetting", function()
    local ns = wow.load(FILES)
    wow.ns = ns
    local saved = smithAlt()
    saved.chars["Tarn Moon"] = alt("Tarn Moon", "DRUID", { level = 5 })
    wow.login(saved)
    wow.timers = {}
    ns.ShowRecipes("Vesp Ash")
    local f = AltsForeverRecipesFrame
    eq(f.details.slots[1].name:GetText(), "3/1 ", "name not loaded yet")
    eq(#wow.timers, 1, "filled again a second later")
    wow.itemNames[ROUGH_STONE_ITEM] = "Rough Stone"
    wow.timers[1]()
    eq(f.details.slots[1].name:GetText(), "3/1 Rough Stone")
    -- No professions: not in the character menu, nor the window's picker.
    ns.ShowCharacterMenu(UIParent, "Tarn Moon")
    eq(wow.menuItem("Professions").enabled, false)
    f.who.scripts.OnClick(f.who)
    local names = {}
    for _, item in ipairs(wow.menu.items) do if item.kind == "radio" then names[#names + 1] = item.text end end
    eq(#names, 1)
    eq(names[1]:find("Vesp Ash", 1, true) ~= nil, true)
    ns.ShowRecipes("Tarn Moon")
    eq(f.details.empty:GetText(), "Tarn Moon has no professions.")
    eq(f.rank:IsShown(), false)
    -- Forgetting the one shown closes it.
    ns.ShowRecipes("Vesp Ash")
    ns.ForgetCharacter("Vesp Ash")
    eq(f:IsShown(), false)
end)

test("professions whose icon wasn't recorded: icons and gathering told apart by the game's names", function()
    local ns = wow.load(FILES)
    wow.ns = ns
    wow.atlases["Skillbar_Fill_Flipbook_DefaultBlue"] = { width = 900, height = 68 }
    wow.atlases["Professions-skillbar-mask"] = { width = 512, height = 512 }
    local saved = smithAlt()
    saved.profArt = nil
    local c = saved.chars["Vesp Ash"]
    c.profs = { Blacksmithing = 120, Skinning = 40, Mining = 30 }
    c.prof1, c.prof2 = "Blacksmithing", "Skinning"
    wow.login(saved)
    local tabs = ns.RecipeTabs(ns.db.chars["Vesp Ash"])
    eq(#tabs, 2, "Skinning gathers: no tab")
    -- A gathering profession whose window was read (Fishing, in game) but has no recipes: none either.
    ns.db.chars["Vesp Ash"].recipes.Skinning = {}
    eq(#ns.RecipeTabs(ns.db.chars["Vesp Ash"]), 2)
    ns.db.chars["Vesp Ash"].recipes.Skinning = { ["cured hide"] = 1 }
    eq(#ns.RecipeTabs(ns.db.chars["Vesp Ash"]), 3, "with a recipe it has one")
    ns.db.chars["Vesp Ash"].recipes.Skinning = nil
    eq(tabs[1].name, "Blacksmithing"); eq(tabs[2].name, "Mining")
    local line, icon = ns.ProfessionArt("Mining")
    eq(line, 186); eq(icon, "Interface\\Icons\\Trade_Mining")
    ns.ShowRecipes("Vesp Ash")
    local f = AltsForeverRecipesFrame
    eq(f.tabs[2].icon.texture, "Interface\\Icons\\Trade_Mining")
    eq(f.tabs[1].icon.texture, 134400, "no name from the game for Blacksmithing here: the question mark")
    -- The rank bar: the fill played as the game's flipbook (2 columns, 2 rows of 34), shown
    -- through a mask at 120/150; played again only when the skill or profession changes.
    local bar = f.rank
    eq(bar.fill.atlas, "Skillbar_Fill_Flipbook_DefaultBlue")
    eq(bar.anim.flipbook.rows, 2); eq(bar.anim.flipbook.columns, 2); eq(bar.anim.flipbook.frames, 4)
    eq(bar.mask.width, 441 * 120 / 150)
    eq(bar.mask.height, nil, "the game's mask keeps its own height")
    eq(bar.anim.plays, 2, "once when filled while hidden, again when shown")
    ns.RecipesChanged()
    eq(bar.anim.plays, 2, "nothing changed")
    ns.db.chars["Vesp Ash"].profs.Blacksmithing = 121
    ns.RecipesChanged()
    eq(bar.anim.plays, 3)
    eq(bar.mask.width, 441 * 121 / 150)
end)

test("the skill scan records each profession's icon and skill line, and sync carries them", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.profs = { { "Blacksmithing", 50, line = 164, icon = 136241 }, { "Mining", 40, line = 186 } }
    wow.login({ v = 2, syncWith = { ["Bob Smith"] = true }, profArt = { Tailoring = "197;136249", Bad = 5 } })
    eq(ns.db.profArt.Blacksmithing, "164;136241")
    eq(ns.db.profArt.Mining, "186;136243")
    eq(ns.db.profArt.Bad, nil, "repaired at load")
    local line, icon = ns.ProfessionArt("Blacksmithing")
    eq(line, 164); eq(icon, 136241)
    -- Sent with the character...
    syncFrom(ns, "Bob Smith", { k = "hello", v = 1, have = {} })
    syncPump()
    syncFrom(ns, "Bob Smith", { k = "want", keys = { ns.charKey } })
    syncPump()
    local sent
    for _, msg in ipairs(syncSent(ns, "Bob Smith")) do
        if msg.k == "char" then sent = msg end
    end
    eq(sent.pa.Blacksmithing, "164;136241")
    eq(sent.pa.Tailoring, nil, "not one of theirs")
    -- ... and taken from theirs where we have none.
    syncFrom(ns, "Bob Smith", { k = "char", key = "Bob Smith", c = alt("Bob Smith", "WARRIOR", { updated = NOW,
        profs = { Tailoring = 10, Alchemy = 5 } }),
        pa = { Tailoring = "1;2", Alchemy = "171;136240", Leatherworking = "bad" } })
    eq(ns.db.profArt.Tailoring, "197;136249", "ours kept")
    eq(ns.db.profArt.Alchemy, "171;136240")
    eq(ns.db.profArt.Leatherworking, nil)
end)
