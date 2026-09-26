-- Tests: names. Loaded by tests/run.lua, which provides test, eq, wow, FILES and the
-- other shared helpers; helpers defined here are shared with the other files too.
---------------------------------------------------------------------------
-- Names on build 70009: UnitName returns the first name and surname separately
test("the full name is built from UnitName's first name and surname", function()
    local ns = wow.load(FILES)
    wow.player.name = "Nyx Emberfall"
    wow.login(nil)
    eq(ns.charKey, "Nyx Emberfall")
    eq(ns.char.name, "Nyx Emberfall")
end)

test("older builds that return the full name as one value still work", function()
    local ns = wow.load(FILES)
    wow.player.name, wow.oneValueNames = "Nyx Emberfall", true
    wow.login(nil)
    eq(ns.charKey, "Nyx Emberfall")
end)

test("an entry saved under the first name alone takes the full name at login", function()
    local ns = wow.load(FILES)
    wow.player.name, wow.player.class = "Mira Dawnfield", "PALADIN"
    wow.login({ v = 2, chars = {
        ["Mira"] = alt("Mira", "PALADIN", { bank = { [100] = 4 }, played = 500 }),
        ["Rook"] = alt("Rook", "ROGUE", {}),
    } })
    eq(ns.charKey, "Mira Dawnfield")
    eq(AltsForeverDB.chars["Mira"], nil)
    eq(ns.char.name, "Mira Dawnfield"); eq(ns.char.bank[100], 4); eq(ns.char.played, 500)
    eq(type(AltsForeverDB.chars["Rook"]), "table", "someone else's first-name entry is left alone")
end)

test("a first-name entry of another class isn't taken", function()
    local ns = wow.load(FILES)
    wow.player.name, wow.player.class = "Mira Dawnfield", "PALADIN"
    wow.login({ v = 2, chars = { ["Mira"] = alt("Mira", "DRUID", { played = 500 }) } })
    eq(type(AltsForeverDB.chars["Mira"]), "table")
    eq(ns.char.played, nil)
end)

test("a first-name entry already saved is folded into the full name, newer data first", function()
    wow.load(FILES)
    wow.login({ v = 2, chars = {
        ["Mira"] = alt("Mira", "PALADIN", { updated = 200, played = 500, bags = { [100] = 2 } }),
        ["Mira Dawnfield"] = alt("Mira Dawnfield", "PALADIN", { updated = 100, played = 400,
            bags = { [100] = 9 }, bank = { [200] = 5 }, recipes = { Cooking = {} } }),
        ["Sorrel"] = alt("Sorrel", "WARLOCK", { updated = 50, played = 10, mail = { [300] = 1 } }),
        ["Sorrel Nightbloom"] = alt("Sorrel Nightbloom", "WARLOCK", { updated = 90, played = 20 }),
    } })
    eq(AltsForeverDB.chars["Mira"], nil)
    local c = AltsForeverDB.chars["Mira Dawnfield"]
    eq(c.name, "Mira Dawnfield")
    eq(c.played, 500); eq(c.bags[100], 2, "newer entry's data wins")
    eq(c.bank[200], 5); eq(type(c.recipes.Cooking), "table", "gaps filled from the older entry")
    local sorrel = AltsForeverDB.chars["Sorrel Nightbloom"]
    eq(AltsForeverDB.chars["Sorrel"], nil)
    eq(sorrel.played, 20, "the full-name entry is newer here, so it wins")
    eq(sorrel.mail[300], 1); eq(sorrel.name, "Sorrel Nightbloom")
end)

test("one-word names are left alone when the match isn't certain", function()
    wow.load(FILES)
    wow.login({ v = 2, chars = {
        ["Ash"] = alt("Ash", "MAGE", {}),
        ["Ash Fire"] = alt("Ash Fire", "MAGE", {}),
        ["Ash Wood"] = alt("Ash Wood", "MAGE", {}),
        ["Rook"] = alt("Rook", "ROGUE", {}),
        ["Rook Hollow"] = alt("Rook Hollow", "PRIEST", {}),
    } })
    local chars = AltsForeverDB.chars
    assert(chars["Ash"] and chars["Ash Fire"] and chars["Ash Wood"], "two candidates: nothing merged")
    assert(chars["Rook"] and chars["Rook Hollow"], "different class: nothing merged")
end)

test("the slash commands are /af and /altsforever; the old /it is gone", function()
    wow.load(FILES)
    eq(SLASH_ALTSFOREVER1, "/af"); eq(SLASH_ALTSFOREVER2, "/altsforever")
    eq(SLASH_ALTSFOREVER3, nil)
end)
