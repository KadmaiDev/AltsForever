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

-- A Spanish client (a player's report, 2026-11-25): the skill list says "Costura", the
-- profession window and its recipes "Sastrería". Matched by skill line (197).
local function sastreria()
    wow.tradeskill.prof = "Sastrería"
    wow.tradeskill.recipes = {
        [3001] = { name = "Madeja de paño de seda", learned = true, item = 4305 },
        [3002] = { name = "Rueca", learned = false },
    }
    wow.fire("TRADE_SKILL_SHOW")
end

test("a profession the window names differently from the skill list is read under the skill list's name", function()
    local ns = wow.load(FILES)
    wow.profs = { { "Costura", 218, 225, line = 197 }, { "Encantamiento", 100, line = 333 } }
    wow.login(nil)
    local c = ns.char
    wow.tradeskill.line = 197 -- the window's skill line
    sastreria()
    eq(c.recipes["Sastrería"], nil, "not under the window's name")
    eq(c.recipes.Costura["madeja de paño de seda"], true)
    eq(c.crafts.Costura[4305], "madeja de paño de seda")
    eq(c.recipesAt.Costura, 218)
    assert(ns.db.recipeInfo.Costura["madeja de paño de seda"], "recipe facts under the same name")
    eq(ns.ProfKey(c, "Sastrería"), "Costura")
    eq(ns.ProfKey(c, "Encantamiento"), "Encantamiento")
    for _, p in ipairs(ns.AltProfessions(c)) do
        if p.name == "Costura" then eq(p.scanned, true, "the character window's tab has its recipes") end
    end
    -- Learning one, named by the window's name, goes to the same list.
    wow.tradeskill.recipes[3002].learned = true
    wow.fire("NEW_RECIPE_LEARNED", 3002)
    eq(c.recipes.Costura.rueca, true)
end)

test("a differently named profession found by the game's name for its skill line; old copy dropped; tooltips match", function()
    local ns = wow.load(FILES)
    wow.profs = { { "Costura", 218, 225, line = 197 } }
    wow.skillLineNames[197] = "Sastrería" -- no skill line from the window: the game's name for the line
    local text = wow.recipeItem(6000, "Patrón: Rueca", "Sastrería", 200)
    wow.login(nil)
    local c = ns.char
    -- Read under the window's name by 1.12.0.
    c.recipes = { ["Sastrería"] = { ["madeja de paño de seda"] = true } }
    c.crafts = { ["Sastrería"] = { [4305] = "madeja de paño de seda" } }
    c.recipesAt = { ["Sastrería"] = 210 }
    sastreria()
    eq(c.recipes["Sastrería"], nil, "the old copy goes")
    eq(c.crafts["Sastrería"], nil)
    eq(c.recipesAt["Sastrería"], nil)
    eq(c.recipes.Costura["madeja de paño de seda"], true)
    -- The recipe's tooltip says "Requires Sastrería (200)": the character's Costura answers.
    local lines = wow.hover(GameTooltip, 6000, text)
    eq(lines[2][1], "Sastrería (200)")
    eq(lines[3][2], "|cffffd100Can learn|r")
end)

test("cooldowns recorded under the window's name move to the skill list's name, ready or unreadable", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.profs = { { "Costura", 260, 300, line = 197 } }
    wow.login(nil)
    local c = ns.char
    c.recipes = { ["Sastrería"] = { ["paño lunar"] = true, ["tela de hechizo"] = true } }
    c.cooldowns = { ["Sastrería"] = { ["Paño lunar"] = NOW - 3600, ["Tela de hechizo"] = NOW + 7200 } }
    wow.tradeskill.prof, wow.tradeskill.line = "Sastrería", 197
    wow.tradeskill.recipes = {
        [3101] = { name = "Paño lunar", learned = true }, -- ready: the game gives no cooldown
        [3102] = { name = "Tela de hechizo", learned = true, cd = "?" }, -- unreadable now
    }
    wow.fire("TRADE_SKILL_SHOW")
    eq(c.cooldowns["Sastrería"], nil, "nothing left under the window's name")
    eq(c.cooldowns.Costura["Paño lunar"], NOW - 3600, "still ready")
    eq(c.cooldowns.Costura["Tela de hechizo"], NOW + 7200, "kept while unreadable")
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

test("recipe tooltip: a recipe first hovered before it loads gets its lines once it has", function()
    wow.load(FILES)
    wow.profs = { { "Engineering", 107 } }
    local text = wow.recipeItem(5000, "Schematic: Shadow Goggles", "Engineering", 120, 115)
    wow.login(nil)
    wow.uncached[5000] = true
    eq(#wow.hover(GameTooltip, 5000, { "Retrieving item information" }), 0)
    wow.uncached[5000] = nil
    local lines = wow.hover(GameTooltip, 5000, text)
    eq(lines[2] and lines[2][1], "Engineering (120)", "not remembered as no recipe")
end)

test("recipe tooltip: a loaded recipe whose lines are still arriving is read again once they have", function()
    wow.load(FILES)
    wow.profs = { { "Engineering", 107 } }
    local text = wow.recipeItem(5000, "Schematic: Shadow Goggles", "Engineering", 120, 115)
    wow.login(nil)
    -- The item is cached, but only its name line has come so far.
    eq(#wow.hover(GameTooltip, 5000, { "Schematic: Shadow Goggles" }), 0)
    local lines = wow.hover(GameTooltip, 5000, text)
    eq(lines[2] and lines[2][1], "Engineering (120)", "not remembered as no recipe")
end)

test("recipe tooltip: names match regardless of capitalisation", function()
    wow.load(FILES)
    wow.profs = { { "Engineering", 107 } }
    local text = wow.recipeItem(5001, "Schematic: Ez-Thro Dynamite", "Engineering", 100)
    wow.login(nil)
    engineeringWindow({ ["EZ-Thro Dynamite"] = true })
    eq(wow.hover(GameTooltip, 5001, text)[3][2], "|cff20ff20Known|r")
end)

test("recipe tooltip: the name is cut at the first colon, ASCII or full-width (Chinese clients)", function()
    local ns = wow.load(FILES)
    wow.profs = { { "Engineering", 107 } }
    local FW = "\239\188\154" -- "："
    local SCHEMATIC = "\229\155\190\231\186\184" -- a Chinese word for the prefix
    local a = wow.recipeItem(5101, SCHEMATIC .. FW .. "Mechanical Squirrel", "Engineering", 100)
    local b = wow.recipeItem(5102, SCHEMATIC .. FW .. "Gnome: Mk II", "Engineering", 100)
    local c = wow.recipeItem(5103, "Schematic: Arc" .. FW .. "Light", "Engineering", 100)
    wow.login(nil)
    ns.char.recipes = { Engineering = { ["mechanical squirrel"] = true, ["gnome: mk ii"] = true, ["arc" .. FW .. "light"] = true } }
    eq(wow.hover(GameTooltip, 5101, a)[3][2], "|cff20ff20Known|r", "full-width colon")
    eq(wow.hover(GameTooltip, 5102, b)[3][2], "|cff20ff20Known|r", "the full-width one comes first")
    eq(wow.hover(GameTooltip, 5103, c)[3][2], "|cff20ff20Known|r", "the ASCII one comes first")
end)

test("recipe tooltip: works on clients that number the placeholders (German)", function()
    wow.strings = { ITEM_MIN_SKILL = "Benötigt %1$s (%2$d)" }
    local ns = wow.load(FILES)
    wow.profs = { { "Engineering", 107 } }
    local text = wow.recipeItem(5104, "Bauplan: Mechanical Squirrel", "Engineering", 100)
    text[#text] = "Benötigt Engineering (100)"
    wow.login(nil)
    ns.char.recipes = { Engineering = { ["mechanical squirrel"] = true } }
    eq(wow.hover(GameTooltip, 5104, text)[3][2], "|cff20ff20Known|r")
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
