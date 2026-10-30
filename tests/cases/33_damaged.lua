-- Tests: a damaged saved file (hand-edited, or written by an older or other copy) is
-- repaired in place at load, never reset, and nothing breaks. Loaded by tests/run.lua.

function damagedSave()
    return { v = 2, icons = "junk", goldDays = 5, goldDaysBy = { x = 3 }, factions = "x",
        recipeInfo = { Tailoring = "x", [5] = {} }, collapsedGroups = 7, legacyPool = "16",
        itemNamesOn = true, itemNames = "x", itemQuality = 3,
        chars = {
            ["Junk"] = "not a character",
            [42] = { name = "Numbered" },
            ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { bags = "x", bank = 5, mail = true,
                equip = { [2589] = "two" }, gear = "x", layout = { [0] = "x", [1] = { 1, "y" } },
                profs = 3, profMax = "x", recipes = { Tailoring = "x" }, crafts = 4, reps = "x",
                duraSlots = 1, money = "lots", level = "ten", xp = {}, xpMax = "x", rested = true,
                played = "x", playedAt = {}, seen = "x", updated = "x", mailExpires = "x",
                spec = "x", legacySpent = "x", wellRested = "x", realm = 5, faction = 6, class = 7 }),
            ["Good Alt"] = alt("Good Alt", "ROGUE", { bags = { [2589] = 3 }, money = 1000, level = 20 }),
        } }
end

test("a damaged saved file is repaired in place: good characters and values kept, nothing breaks", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.itemNames[2589] = "Linen Cloth"
    local errors = {}
    local function try(what, fn, ...)
        local ok, err = pcall(fn, ...)
        if not ok then errors[#errors + 1] = what .. ": " .. tostring(err) end
    end
    try("login", wow.login, damagedSave())
    try("timers", runTimers)
    try("hover", wow.hover, GameTooltip, 2589)
    try("overview", SlashCmdList.ALTSFOREVER, "")
    try("bags", ns.ShowBags, "Tarn Moon", "bags")
    try("bank", ns.ShowBags, "Tarn Moon", "bank")
    try("gear", ns.ShowGear, "Tarn Moon")
    try("search", ns.ToggleSearch, "linen")
    try("export text", ns.ExportText, "text")
    try("export tabs", ns.ExportText, "tabs")
    try("export md", ns.ExportText, "markdown")
    try("rep", ns.ToggleReputation)
    try("mail", SlashCmdList.ALTSFOREVER, "mail")
    try("legacy", SlashCmdList.ALTSFOREVER, "legacy")
    try("options", showOptionsPage)
    try("logout", wow.fire, "PLAYER_LOGOUT")
    eq(#errors, 0, table.concat(errors, "\n"))
    eq(AltsForeverDB.chars["Good Alt"].bags[2589], 3, "good data kept")
    eq(AltsForeverDB.chars["Good Alt"].money, 1000)
    local chars = AltsForeverDB.chars
    eq(chars["Junk"], nil, "not a character: dropped")
    eq(chars[42], nil)
    eq(type(chars["Numbered"]), "table", "a character under a number moves to its name")
    local tarn = chars["Tarn Moon"]
    eq(tarn.name, "Tarn Moon"); eq(tarn.class, "DRUID", "valid values kept")
    eq(tarn.bags, nil, "a wrong type reads as not known yet")
    eq(tarn.money, nil); eq(tarn.realm, nil)
    eq(next(tarn.equip), nil, "a count that isn't a number is dropped")
    eq(tarn.layout[1][1], 1); eq(tarn.layout[1][2], 0, "a slot that isn't a number reads as empty")
    eq(tarn.layout[0], nil)
    eq(AltsForeverDB.recipeInfo.Tailoring, nil)
    eq(AltsForeverDB.icons, nil)
end)

test("a damaged version marker or character list costs only what's damaged", function()
    wow.load(FILES)
    wow.login({ v = "2", countsOff = true, chars = { ["Good Alt"] = alt("Good Alt", "ROGUE", { money = 1000 }) } })
    eq(AltsForeverDB.v, 2)
    eq(AltsForeverDB.chars["Good Alt"].money, 1000, "characters kept")
    eq(AltsForeverDB.countsOff, true, "settings kept")
    wow.load(FILES)
    wow.login({ v = 2, countsOff = true, chars = "junk" })
    eq(type(AltsForeverDB.chars), "table")
    eq(AltsForeverDB.countsOff, true, "settings kept")
end)

test("a damaged version 1 save loads, keeping its good characters", function()
    wow.load(FILES)
    local ok, err = pcall(wow.login, { v = 1, chars = {
        [42] = { class = "MAGE" },
        ["Kadra-Realm"] = { class = "MAGE", updated = "x", bags = { [100] = 1 } },
        ["Kadra-Other"] = { class = "MAGE", updated = 50, bags = { [100] = 2 } },
        ["Tarn Moon-Realm"] = { class = "DRUID", bags = { [200] = 3 } } } })
    assert(ok, err)
    eq(AltsForeverDB.chars["Tarn Moon"].bags[200], 3)
    eq(AltsForeverDB.chars["Kadra"].bags[100], 2, "the newer one kept")
end)

test("a damaged icon choice falls back to the default; good ones are kept", function()
    wow.load(FILES)
    local ok, err = pcall(wow.login, { v = 2, icons = { bags = true, bank = {}, mail = "words", [5] = "x" }, chars = {} })
    assert(ok, err)
    eq(AltsForeverDB.icons.bags, nil); eq(AltsForeverDB.icons.bank, nil)
    eq(AltsForeverDB.icons.mail, "words")
    eq(AltsForeverDB.icons[5], nil)
end)

test("one damaged XP value: level kept, XP unknown, nothing breaks", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.login({ v = 2, chars = { ["Low Alt"] = alt("Low Alt", "ROGUE", { level = 20, xp = "bad", xpMax = 10000 }) } })
    local c = AltsForeverDB.chars["Low Alt"]
    eq(c.xp, nil); eq(c.level, 20)
    eq(ns.LevelText(c), "20")
    local ok, err = pcall(function()
        SlashCmdList.ALTSFOREVER("")
        for _, row in ipairs(overviewRows()) do row.scripts.OnEnter(row) end
        ns.AddXPLines(GameTooltip, true)
        ns.ExportText("tabs")
    end)
    assert(ok, err)
end)
