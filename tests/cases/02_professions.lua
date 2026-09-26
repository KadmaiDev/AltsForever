-- Tests: professions. Loaded by tests/run.lua, which provides test, eq, wow, FILES and the
-- other shared helpers; helpers defined here are shared with the other files too.
---------------------------------------------------------------------------
-- Professions and recipes

SQUIRREL = 4408 -- Schematic: Mechanical Squirrel

function engineeringWindow(learnedNames)
    local recipes = {}
    local id = 1000
    for _, name in ipairs({ "Mechanical Squirrel", "EZ-Thro Dynamite", "Shadow Goggles", "Rough Dynamite" }) do
        id = id + 1
        recipes[id] = { name = name, learned = learnedNames[name] or false }
    end
    wow.tradeskill.prof, wow.tradeskill.recipes = "Engineering", recipes
    wow.fire("TRADE_SKILL_SHOW")
end

function recipeAlts()
    return { v = 2, chars = {
        ["Brakka"] = alt("Brakka", "HUNTER", { profs = { Engineering = 107 },
            recipes = { Engineering = { ["mechanical squirrel"] = true } } }),
        ["Elowen"] = alt("Elowen", "PRIEST", { profs = { Engineering = 110 },
            recipes = { Engineering = {} } }),
        ["Thessa"] = alt("Thessa", "DRUID", { profs = { Engineering = 60 } }),
        ["Sorrel"] = alt("Sorrel", "WARLOCK", { profs = { Engineering = 200 } }),
        ["Veyla"] = alt("Veyla", "PALADIN", { profs = { Tailoring = 150 } }),
    } }
end

test("profession skills are recorded at login and when they change", function()
    local ns = wow.load(FILES)
    wow.profs = { { "Engineering", 107 }, { "Mining", 99 } }
    wow.login(nil)
    eq(ns.char.profs.Engineering, 107)
    eq(ns.char.profs.Mining, 99)
    wow.profs = { { "Engineering", 108 } }
    wow.fire("SKILL_LINES_CHANGED")
    eq(ns.char.profs.Engineering, 108)
    eq(ns.char.profs.Mining, nil, "dropped professions are removed")
end)

test("opening a profession window records its learned recipes", function()
    local ns = wow.load(FILES)
    wow.profs = { { "Engineering", 107 } }
    wow.login(nil)
    eq(ns.char.recipes, nil, "nothing until a window opens")
    engineeringWindow({ ["Mechanical Squirrel"] = true, ["EZ-Thro Dynamite"] = true })
    local known = ns.char.recipes.Engineering
    eq(known["mechanical squirrel"], true)
    eq(known["ez-thro dynamite"], true, "stored lower-case")
    eq(known["shadow goggles"], nil, "unlearned recipes aren't stored")
end)

test("the recipe list is read once it's ready, not before", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    wow.tradeskill.ready = false
    engineeringWindow({ ["Mechanical Squirrel"] = true })
    eq(ns.char.recipes, nil)
    wow.tradeskill.ready = true
    wow.fire("TRADE_SKILL_LIST_UPDATE")
    eq(ns.char.recipes.Engineering["mechanical squirrel"], true)
end)

test("someone else's linked or guild profession is never recorded", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    wow.tradeskill.linked = true
    engineeringWindow({ ["Mechanical Squirrel"] = true })
    eq(ns.char.recipes, nil)
    wow.tradeskill.linked, wow.tradeskill.guild = false, true
    engineeringWindow({ ["Mechanical Squirrel"] = true })
    eq(ns.char.recipes, nil)
end)

test("learning a recipe adds it, but only to a profession already scanned", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    engineeringWindow({})
    wow.fire("TRADE_SKILL_CLOSE")
    wow.tradeskill.recipes[1003].learned = true -- Shadow Goggles
    wow.fire("NEW_RECIPE_LEARNED", 1003)
    eq(ns.char.recipes.Engineering["shadow goggles"], true)
    wow.tradeskill.recipes[2001] = { name = "Linen Robe", learned = true, prof = "Tailoring" }
    wow.fire("NEW_RECIPE_LEARNED", 2001)
    eq(ns.char.recipes.Tailoring, nil, "a partial list would wrongly say 'not learned'")
end)

test("recipe tooltip: only characters with the profession, you first, then by status", function()
    wow.load(FILES)
    wow.profs = { { "Engineering", 80 } }
    local text = wow.recipeItem(SQUIRREL, "Schematic: Mechanical Squirrel", "Engineering", 75)
    wow.login(recipeAlts())
    local lines = wow.hover(GameTooltip, SQUIRREL, text)
    eq(lines[1][1], " ")
    eq(lines[2][1], "Engineering (75)")
    eq(lines[3][1], "[MAGE]Aldric"); eq(lines[3][2], "|cff9d9d9dNot scanned|r")
    eq(lines[4][1], "[HUNTER]Brakka"); eq(lines[4][2], "|cff20ff20Known|r")
    eq(lines[5][1], "[PRIEST]Elowen"); eq(lines[5][2], "|cffffd100Can learn|r")
    eq(lines[6][1], "[DRUID]Thessa"); eq(lines[6][2], "|cffff2020Needs 75 (60)|r")
    eq(lines[7][1], "[WARLOCK]Sorrel"); eq(lines[7][2], "|cff9d9d9dNot scanned|r")
    eq(#lines, 7, "Veyla has no Engineering, so she is left out")
end)

test("recipe tooltip: reads the recipe's own requirement, not the crafted item's", function()
    wow.load(FILES)
    wow.profs = { { "Engineering", 107 } }
    local text = wow.recipeItem(5000, "Schematic: Shadow Goggles", "Engineering", 120, 115)
    wow.login(nil)
    local lines = wow.hover(GameTooltip, 5000, text)
    eq(lines[2][1], "Engineering (120)")
    eq(lines[3][2], "|cffff2020Needs 120 (107)|r")
end)

test("recipe tooltip: names match regardless of capitalisation", function()
    wow.load(FILES)
    wow.profs = { { "Engineering", 107 } }
    local text = wow.recipeItem(5001, "Schematic: Ez-Thro Dynamite", "Engineering", 100)
    wow.login(nil)
    engineeringWindow({ ["EZ-Thro Dynamite"] = true })
    eq(wow.hover(GameTooltip, 5001, text)[3][2], "|cff20ff20Known|r")
end)

test("recipe tooltip: updates when you learn the recipe", function()
    wow.load(FILES)
    wow.profs = { { "Engineering", 107 } }
    local text = wow.recipeItem(SQUIRREL, "Schematic: Mechanical Squirrel", "Engineering", 75)
    wow.login(nil)
    engineeringWindow({})
    eq(wow.hover(GameTooltip, SQUIRREL, text)[3][2], "|cffffd100Can learn|r")
    wow.tradeskill.recipes[1001].learned = true
    wow.fire("NEW_RECIPE_LEARNED", 1001)
    eq(wow.hover(GameTooltip, SQUIRREL, text)[3][2], "|cff20ff20Known|r")
end)

test("recipe tooltip: nothing for non-recipes or when nobody has the profession", function()
    wow.load(FILES)
    wow.login(nil)
    eq(#wow.hover(GameTooltip, 100, { "Linen Cloth" }), 0)
    local text = wow.recipeItem(SQUIRREL, "Schematic: Mechanical Squirrel", "Engineering", 75)
    eq(#wow.hover(GameTooltip, SQUIRREL, text), 0)
end)
