-- Tests: skillups. Loaded by tests/run.lua, which provides test, eq, wow, FILES and the
-- other shared helpers; helpers defined here are shared with the other files too.
---------------------------------------------------------------------------
-- Skill-ups across alts (0.3.0): grey points and reagents from the live game
L = "|cffe0e0e0"
LINEN, COPPER_TUBE, BOLT = 2589, 4361, 4359
function to(n) return L .. " · to " .. n .. "|r" end
function skillupsTo(n) return L .. " · skill-ups to " .. n .. "|r" end

-- Engineering recipes with grey points and reagents, as a profession window lists them.
function greyWindow(learned)
    wow.tradeskill.prof = "Engineering"
    wow.tradeskill.recipes = {
        [1001] = { name = "Mechanical Squirrel", learned = learned.squirrel or false, item = SQUIRREL_ITEM,
            grey = 100, reagents = { { COPPER_TUBE, 1 }, { LINEN, 2 } } },
        [1002] = { name = "Rough Dynamite", learned = learned.dynamite or false, item = DYNAMITE_ITEM,
            grey = 60, reagents = { { LINEN, 1 } } },
        [1003] = { name = "Shadow Goggles", learned = learned.goggles or false, item = GOGGLES_ITEM,
            grey = 150, reagents = { { BOLT, 4 } } },
    }
    wow.fire("TRADE_SKILL_SHOW")
end

function textOf(lines)
    local t = {}
    for _, l in ipairs(lines) do t[#t + 1] = table.concat(l, " = ") end
    return table.concat(t, "\n")
end

test("a profession scan records grey points, and reagents of known recipes, account-wide", function()
    wow.load(FILES)
    wow.profs = { { "Engineering", 55 } }
    wow.login({ v = 2, recipeInfo = { Engineering = { ["shadow goggles"] = "140;Shadow Goggles;,4359:4" } }, chars = {
        ["Tink Gear"] = alt("Tink Gear", "WARRIOR", { recipes = { Engineering = { ["shadow goggles"] = true } } }) } })
    wow.schematics = 0
    greyWindow({ squirrel = true })
    local info = AltsForeverDB.recipeInfo.Engineering
    eq(info["mechanical squirrel"], "100;Mechanical Squirrel;,4361:1,2589:2")
    eq(info["rough dynamite"], nil, "nobody knows it: not stored")
    eq(info["shadow goggles"], "150;Shadow Goggles;,4359:4", "known by another character: grey refreshed, reagents kept")
    eq(wow.schematics, 1, "schematics are read only for learned recipes")
end)

test("learning a recipe records its reagents and what it makes", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    greyWindow({})
    wow.fire("TRADE_SKILL_CLOSE")
    wow.tradeskill.recipes[1003].learned = true
    wow.fire("NEW_RECIPE_LEARNED", 1003)
    eq(AltsForeverDB.recipeInfo.Engineering["shadow goggles"], "150;Shadow Goggles;,4359:4")
    eq(ns.char.crafts.Engineering[GOGGLES_ITEM], "shadow goggles")
end)

test("recipe item tooltips don't show skill-up levels", function()
    wow.load(FILES)
    wow.profs = { { "Engineering", 80 } }
    local text = wow.recipeItem(SQUIRREL, "Schematic: Mechanical Squirrel", "Engineering", 75)
    local saved = recipeAlts()
    saved.recipeInfo = { Engineering = { ["mechanical squirrel"] = "100;Mechanical Squirrel;" } }
    wow.login(saved)
    local lines = wow.hover(GameTooltip, SQUIRREL, text)
    eq(lines[3][2], "|cff9d9d9dNot scanned|r")
    eq(lines[4][2], "|cff20ff20Known|r")
    eq(lines[5][2], "|cffffd100Can learn|r")
    eq(lines[6][2], "|cffff2020Needs 75 (60)|r")
end)

test("/af skillups turns every skill-up detail off and on", function()
    wow.load(FILES)
    wow.profs = { { "Engineering", 80 } }
    local text = wow.recipeItem(SQUIRREL, "Schematic: Mechanical Squirrel", "Engineering", 75)
    local saved = recipeAlts()
    saved.recipeInfo = { Engineering = { ["mechanical squirrel"] = "100;Mechanical Squirrel;,2589:2" } }
    saved.chars["Brakka"].crafts = { Engineering = { [SQUIRREL_ITEM] = "mechanical squirrel" } }
    saved.chars["Brakka"].profs.Engineering = 90
    wow.login(saved)
    SlashCmdList.ALTSFOREVER("skillups")
    eq(AltsForeverDB.skillupsOff, true)
    eq(craftLine(wow.hover(GameTooltip, SQUIRREL_ITEM)), "[HUNTER]Brakka", "can craft as in 0.2")
    assert(not textOf(wow.hover(GameTooltip, LINEN)):find("Skill-ups", 1, true), "no reagent section")
    SlashCmdList.ALTSFOREVER("skillups")
    eq(AltsForeverDB.skillupsOff, nil)
    eq(craftLine(wow.hover(GameTooltip, SQUIRREL_ITEM)), "[HUNTER]Brakka" .. skillupsTo(100))
    assert(textOf(wow.hover(GameTooltip, LINEN)):find("Skill-ups", 1, true), "reagent section back")
end)

test("can craft: characters who'd still get a skill-up are marked", function()
    wow.load(FILES)
    wow.login({ v = 2, recipeInfo = { Engineering = { ["mechanical squirrel"] = "100;Mechanical Squirrel;" } }, chars = {
        ["Brakka"] = alt("Brakka", "HUNTER", { profs = { Engineering = 90 },
            crafts = { Engineering = { [SQUIRREL_ITEM] = "mechanical squirrel" } } }),
        ["Far"] = alt("Far", "MAGE", { profs = { Engineering = 120 },
            crafts = { Engineering = { [SQUIRREL_ITEM] = "mechanical squirrel" } } }),
        ["Old"] = alt("Old", "ROGUE", { profs = { Engineering = 10 }, crafts = { Engineering = { [SQUIRREL_ITEM] = true } } }),
    } })
    eq(craftLine(wow.hover(GameTooltip, SQUIRREL_ITEM)),
        "[HUNTER]Brakka" .. skillupsTo(100) .. ", [MAGE]Far, [ROGUE]Old", "past grey, or saved before 0.3: unmarked")
end)

-- Aldric (you) and two alts, with recipes that use Linen Cloth.
function reagentAlts()
    return { v = 2, recipeInfo = {
        Engineering = {
            ["mechanical squirrel"] = "100;Mechanical Squirrel;,4361:1,2589:2",
            ["rough dynamite"] = "60;Rough Dynamite;,2589:1",
        },
        ["First Aid"] = { ["linen bandage"] = "80;Linen Bandage;,2589:1", ["heavy linen bandage"] = "115;Heavy Linen Bandage;,2589:2" },
    }, chars = {
        ["Brakka Stone"] = alt("Brakka Stone", "HUNTER", { profs = { Engineering = 107 },
            recipes = { Engineering = { ["mechanical squirrel"] = true } } }),
        ["Tarnia Moon"] = alt("Tarnia Moon", "DRUID", { profs = { ["First Aid"] = 40 },
            recipes = { ["First Aid"] = { ["linen bandage"] = true } } }),
    } }
end

test("reagent tooltip lists the recipes that still give each character a skill-up", function()
    local ns = wow.load(FILES)
    wow.profs = { { "Engineering", 55 } }
    local saved = reagentAlts()
    saved.chars["Aldric"] = alt("Aldric", "MAGE", { recipes = { Engineering = { ["mechanical squirrel"] = true, ["rough dynamite"] = true } } })
    wow.login(saved)
    local lines = wow.hover(GameTooltip, LINEN)
    eq(lines[1][1], " "); eq(lines[2][1], "Skill-ups")
    eq(lines[3][1], "  Mechanical Squirrel"); eq(lines[3][2], "[MAGE]Aldric" .. to(100))
    eq(lines[4][1], "  Rough Dynamite"); eq(lines[4][2], "[MAGE]Aldric" .. to(60))
    eq(lines[5][1], "  Linen Bandage"); eq(lines[5][2], "[DRUID]Tarnia" .. to(80))
    eq(#lines, 5, "Brakka is past grey; nobody knows Heavy Linen Bandage")
    eq(textOf(wow.hover(GameTooltip, 9999)):find("Skill-ups", 1, true), nil, "unused item: no section")
    -- Skill goes up: Rough Dynamite (grey 60) stops counting.
    wow.profs = { { "Engineering", 60 } }
    wow.fire("SKILL_LINES_CHANGED")
    lines = wow.hover(GameTooltip, LINEN)
    eq(lines[4][1], "  Linen Bandage", "updated when skill changes")
    eq(ns.SkillupCount(ns.char, "Engineering"), 1)
end)

test("reagent tooltip: 2 recipes per character with the most skill-ups left", function()
    wow.load(FILES)
    wow.profs = { { "Tailoring", 50 } }
    -- Your recipes: 7 shirts, skill-ups left 10, 20, ... 70.
    local info, mine = {}, {}
    for i = 1, 7 do
        info["shirt " .. i] = (50 + i * 10) .. ";Shirt " .. i .. ";,2589:1"
        mine["shirt " .. i] = true
    end
    info["bag"] = "200;Bag;,2589:2"
    info["cap"] = "70;Cap;,2589:1"
    info["vest"] = "95;Vest;,2589:1"
    wow.login({ v = 2, recipeInfo = { Tailoring = info }, chars = {
        ["Aldric"] = alt("Aldric", "MAGE", { recipes = { Tailoring = mine } }),
        -- Zed's best: Bag, 200 - 60 = 140 left (more than any of yours). Amy's: Vest, 55 left.
        ["Zed Moor"] = alt("Zed Moor", "ROGUE", { profs = { Tailoring = 60 }, recipes = { Tailoring = { bag = true, cap = true } } }),
        ["Amy Ash"] = alt("Amy Ash", "DRUID", { profs = { Tailoring = 40 }, recipes = { Tailoring = { vest = true, cap = true } } }),
        ["Old Timer"] = alt("Old Timer", "WARRIOR", { profs = { Tailoring = 300 }, recipes = { Tailoring = { bag = true } } }),
    } })
    local lines = wow.hover(GameTooltip, LINEN)
    eq(lines[2][1], "Skill-ups")
    eq(lines[3][1], "  Shirt 7"); eq(lines[3][2], "[MAGE]Aldric" .. to(120), "you first even though Zed has more left")
    eq(lines[4][1], "  Shirt 6"); eq(lines[4][2], "[MAGE]Aldric" .. to(110))
    eq(lines[5][1], "  Bag"); eq(lines[5][2], "[ROGUE]Zed" .. to(200), "then the alt with the most left, though Z")
    eq(lines[6][1], "  Cap"); eq(lines[6][2], "[ROGUE]Zed" .. to(70))
    eq(lines[7][1], "  Vest"); eq(lines[7][2], "[DRUID]Amy" .. to(95))
    eq(lines[8][1], "  Cap"); eq(lines[8][2], "[DRUID]Amy" .. to(70))
    eq(lines[9][1], "  +5 more", "your 5 other shirts; Old Timer is past grey")
end)

test("reagent tooltip: never more than 6 recipe lines", function()
    wow.load(FILES)
    local info, chars = { ["cap"] = "70;Cap;,2589:1", ["hat"] = "80;Hat;,2589:1" }, {}
    for _, name in ipairs({ "Ann Bee", "Bo Cee", "Cy Dee", "Di Eff" }) do
        chars[name] = alt(name, "PRIEST", { profs = { Tailoring = 10 }, recipes = { Tailoring = { cap = true, hat = true } } })
    end
    wow.login({ v = 2, recipeInfo = { Tailoring = info }, chars = chars })
    local lines = wow.hover(GameTooltip, LINEN)
    eq(lines[7][2], "[PRIEST]Cy" .. to(80)); eq(lines[8][2], "[PRIEST]Cy" .. to(70), "three alts fill the 6 lines")
    eq(lines[9][1], "  +2 more"); eq(#lines, 9)
end)

test("overview row tooltip counts recipes still giving skill-ups", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    local saved = overviewAlts()
    saved.recipeInfo = { Tailoring = { a = "250;A;", b = "150;B;", c = "210;C;,1:1" } }
    saved.chars["High"].recipes = { Tailoring = { a = true, b = true, c = true }, Fishing = { ["fish bowl"] = true }, Mining = { smelt = true } }
    saved.chars["High"].profs.Fishing = 50
    saved.chars["High"].profs.Mining = 150
    -- Fish Bowl is grey at 25; smelting too at 125: gathering professions say nothing at 0,
    -- others still do.
    saved.recipeInfo.Fishing = { ["fish bowl"] = "25;Fish Bowl;" }
    saved.recipeInfo.Mining = { smelt = "125;Smelt;" }
    wow.login(saved)
    eq(ns.SkillupCount(saved.chars["High"], "Tailoring"), 2, "skill 200: a and c")
    eq(ns.SkillupCount(saved.chars["High"], "Enchanting"), nil, "never scanned")
    SlashCmdList.ALTSFOREVER("")
    local row = overviewRows()[3] -- High
    row.scripts.OnEnter(row)
    local text = textOf(GameTooltip.lines)
    assert(text:find("Tailoring = 200  " .. G .. "(2 skill-up recipes)|r", 1, true), text)
    assert(text:find("Enchanting = 180\n", 1, true) or text:find("Enchanting = 180$"), text)
    assert(text:find("Fishing = 50\n", 1, true) or text:find("Fishing = 50$"), "gathering, nothing left: no note\n" .. text)
    assert(text:find("Mining = 150  " .. G .. "(0 skill-up recipes)|r", 1, true), "crafting: 0 still shown\n" .. text)
    SlashCmdList.ALTSFOREVER("skillups")
    row.scripts.OnEnter(row)
    text = textOf(GameTooltip.lines)
    assert(text:find("Tailoring = 200\n", 1, true) or text:find("Tailoring = 200$"), "toggle off: plain skill\n" .. text)
end)

test("each profession's rank maximum is recorded", function()
    local ns = wow.load(FILES)
    wow.profs = { { "Engineering", 75, 75 }, { "Mining", 99, 150 } }
    wow.login(nil)
    eq(ns.char.profMax.Engineering, 75); eq(ns.char.profMax.Mining, 150)
    eq(ns.AtRankCap(ns.char, "Engineering"), true)
    eq(ns.AtRankCap(ns.char, "Mining"), false)
    eq(ns.AtRankCap({ profs = { Mining = 75 } }, "Mining"), false, "saved before 0.3.0: no maximum, not capped")
end)

test("a character at their rank cap gets no skill-up lines", function()
    wow.load(FILES)
    wow.login({ v = 2, recipeInfo = { Tailoring = { cap = "100;Cap;,2589:1" } }, chars = {
        ["Ann Bee"] = alt("Ann Bee", "PRIEST", { profs = { Tailoring = 75 }, profMax = { Tailoring = 75 },
            recipes = { Tailoring = { cap = true } }, crafts = { Tailoring = { [777] = "cap" } } }),
        ["Bo Cee"] = alt("Bo Cee", "ROGUE", { profs = { Tailoring = 75 }, profMax = { Tailoring = 150 },
            recipes = { Tailoring = { cap = true } }, crafts = { Tailoring = { [777] = "cap" } } }),
    } })
    local lines = wow.hover(GameTooltip, LINEN)
    eq(lines[3][2], "[ROGUE]Bo" .. to(100)); eq(#lines, 3, "Ann at 75/75 can't skill up")
    eq(craftLine(wow.hover(GameTooltip, 777)), "[PRIEST]Ann Bee, [ROGUE]Bo Cee" .. skillupsTo(100))
end)

test("overview: at a rank cap it says to train; at 300 it says nothing extra", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    local saved = overviewAlts()
    saved.recipeInfo = { Tailoring = { a = "250;A;" }, Enchanting = { b = "300;B;" } }
    saved.chars["High"].profs = { Tailoring = 225, Enchanting = 300 }
    saved.chars["High"].profMax = { Tailoring = 225, Enchanting = 300 }
    saved.chars["High"].recipes = { Tailoring = { a = true }, Enchanting = { b = true } }
    wow.login(saved)
    eq(ns.SkillupCount(saved.chars["High"], "Tailoring"), 0)
    SlashCmdList.ALTSFOREVER("")
    local row = overviewRows()[3] -- High
    row.scripts.OnEnter(row)
    local text = textOf(GameTooltip.lines)
    assert(text:find("Tailoring = 225  " .. G .. "(train to skill up)|r", 1, true), text)
    assert(text:find("Enchanting = 300\n", 1, true) or text:find("Enchanting = 300$"), text)
end)

---------------------------------------------------------------------------
-- The game's recipe list can hold other professions' recipes (build 70009)
VEST, WOLF_MEAT = 2847, 2679

-- A Blacksmithing window whose list also holds Cooking recipes, plus unlearned filler.
function mixedWindow(extra)
    wow.tradeskill.prof = "Blacksmithing"
    local recipes = {
        [3001] = { name = "Rough Copper Vest", learned = true, item = VEST, grey = 55, reagents = { { 2840, 4 } } },
        [3002] = { name = "Charred Wolf Meat", learned = true, prof = "Cooking", item = WOLF_MEAT, grey = 85,
            reagents = { { 2672, 1 } } },
        [3003] = { name = "Copper Bracers", learned = false, grey = 60 },
    }
    for i = 1, (extra or 0) do recipes[4000 + i] = { name = "Filler " .. i, learned = false, grey = 100 } end
    wow.tradeskill.recipes = recipes
    wow.fire("TRADE_SKILL_SHOW")
end

test("a scan only records recipes of the window's profession", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    mixedWindow()
    eq(ns.char.recipes.Blacksmithing["rough copper vest"], true)
    eq(ns.char.recipes.Blacksmithing["charred wolf meat"], nil, "a Cooking recipe in the list")
    eq(ns.char.crafts.Blacksmithing[WOLF_MEAT], nil)
    eq(AltsForeverDB.recipeInfo.Blacksmithing["charred wolf meat"], nil)
    eq(AltsForeverDB.recipeInfo.Blacksmithing["rough copper vest"], "55;Rough Copper Vest;,2840:4")
end)

test("strays saved by 0.2.x are removed from every character, keeping the rest", function()
    local ns = wow.load(FILES)
    wow.login({ v = 2, recipeInfo = { Blacksmithing = {
        ["rough copper vest"] = "50;Rough Copper Vest;,2840:4",
        ["charred wolf meat"] = "85;Charred Wolf Meat;,2672:1",
        ["herb baked egg"] = "85;Herb Baked Egg;,6889:1",
    }, Leatherworking = {
        ["light leather"] = "60;Light Leather;,2934:3",
        ["pincer bites"] = "85;Pincer Bites;,2675:1", -- a stray nobody knows as Leatherworking
    } }, chars = {
        ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { recipes = { Leatherworking = { ["light leather"] = true } } }),
        ["Vesp Ash"] = alt("Vesp Ash", "PALADIN", { profs = { Blacksmithing = 40 },
            recipes = { Blacksmithing = { ["rough copper vest"] = true, ["charred wolf meat"] = true, ["herb baked egg"] = true } },
            crafts = { Blacksmithing = { [VEST] = "rough copper vest", [WOLF_MEAT] = "charred wolf meat", [777] = true } } }),
    } })
    mixedWindow()
    local v = AltsForeverDB.chars["Vesp Ash"]
    eq(v.recipes.Blacksmithing["rough copper vest"], true, "their real recipe stays: still Known")
    eq(v.recipes.Blacksmithing["charred wolf meat"], nil, "listed, but as Cooking")
    eq(v.recipes.Blacksmithing["herb baked egg"], nil, "not in Blacksmithing's list at all")
    eq(v.crafts.Blacksmithing[VEST], "rough copper vest")
    eq(v.crafts.Blacksmithing[WOLF_MEAT], nil)
    eq(v.crafts.Blacksmithing[777], true, "saved before 0.3.0: can't be checked, kept")
    local info = AltsForeverDB.recipeInfo.Blacksmithing
    eq(info["rough copper vest"], "55;Rough Copper Vest;,2840:4", "grey refreshed")
    eq(info["charred wolf meat"], nil); eq(info["herb baked egg"], nil)
    local lw = AltsForeverDB.recipeInfo.Leatherworking
    eq(lw["pincer bites"], nil, "strays under professions nobody opened are cleared too")
    eq(lw["light leather"], "60;Light Leather;,2934:3", "Tarn's real recipe stays")
end)

test("a list without the window's profession changes nothing", function()
    local ns = wow.load(FILES)
    wow.login({ v = 2, chars = { ["Aldric"] = alt("Aldric", "MAGE", {
        recipes = { Blacksmithing = { ["rough copper vest"] = true } } }) } })
    wow.tradeskill.prof = "Blacksmithing"
    wow.tradeskill.recipes = {
        [3002] = { name = "Charred Wolf Meat", learned = true, prof = "Cooking", item = WOLF_MEAT, grey = 85 },
        [3004] = { name = "Herb Baked Egg", learned = false, prof = "Cooking", grey = 85 },
    }
    wow.fire("TRADE_SKILL_SHOW")
    eq(ns.char.recipes.Blacksmithing["rough copper vest"], true, "not wiped")
    eq(ns.char.recipes.Blacksmithing["charred wolf meat"], nil)
    -- The right list arrives with the next update.
    mixedWindow()
    wow.fire("TRADE_SKILL_LIST_UPDATE")
    eq(ns.char.recipes.Blacksmithing["rough copper vest"], true)
end)

test("a new profession with nothing learned yet is still recorded as scanned", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    wow.tradeskill.prof = "Blacksmithing"
    wow.tradeskill.recipes = { [3003] = { name = "Copper Bracers", learned = false, grey = 60 } }
    wow.fire("TRADE_SKILL_SHOW")
    eq(type(ns.char.recipes.Blacksmithing), "table", "scanned, just empty")
end)

test("the profession check stays cheap: only learned and stored recipes", function()
    wow.load(FILES)
    wow.login(nil)
    wow.profLookups = 0
    mixedWindow(300) -- 303 recipes listed, 2 learned
    assert(wow.profLookups <= 3, "checked " .. wow.profLookups .. " of 303")
end)

test("/af delete also forgets recipes nobody else knows", function()
    wow.load(FILES)
    wow.login({ v = 2, recipeInfo = { Blacksmithing = {
        ["rough copper vest"] = "55;Rough Copper Vest;", ["copper bracers"] = "60;Copper Bracers;" } }, chars = {
        ["Mid"] = alt("Mid", "DRUID", { recipes = { Blacksmithing = { ["rough copper vest"] = true, ["copper bracers"] = true } } }),
        ["Aldric"] = alt("Aldric", "MAGE", { recipes = { Blacksmithing = { ["copper bracers"] = true } } }),
    } })
    SlashCmdList.ALTSFOREVER("delete mid")
    local info = AltsForeverDB.recipeInfo.Blacksmithing
    eq(info["rough copper vest"], nil, "only Mid knew it")
    eq(info["copper bracers"], "60;Copper Bracers;", "Aldric still knows it")
end)
