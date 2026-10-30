-- Tests: the move from the beta to the live game (Core.lua ns.BetaRealm / ns.LeaveBeta).
-- Loaded by tests/run.lua.

-- A save from the beta: you (Aldric) and Tarn on its Normal realm, Rook on its PvP realm,
-- Old not logged in since realms were recorded; gold history for two beta groups, Legacy
-- points and a setting. Times as the beta left them (NOW is September 2026).
function betaSave()
    return { v = 2, goldGroup = "ClassicBetaPvE2|Alliance", goldDays = { [100] = 5000 },
        goldDaysBy = { ["ClassicBetaPvP|Horde"] = { [100] = 70 } },
        collapsedGroups = { ["ClassicBetaPvP|Horde"] = true },
        legacyPool = 16, wellRested = 5, countsOff = true,
        chars = {
            ["Aldric"] = alt("Aldric", "MAGE", { realm = "ClassicBetaPvE2", faction = "Alliance",
                bags = { [2589] = 20 }, bank = { [2318] = 5 }, money = 5000, legacySpent = 3 }),
            ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { realm = "ClassicBetaPvE2", faction = "Alliance",
                money = 300, mailExpires = NOW - DAY }),
            ["Rook Vale"] = alt("Rook Vale", "ROGUE", { realm = "ClassicBetaPvP", faction = "Horde", money = 70 }),
            ["Old"] = alt("Old", "WARRIOR", { bank = { [1] = 1 }, seen = NOW - 30 * DAY, updated = NOW - 30 * DAY }),
        } }
end

local function betaLine()
    for _, line in ipairs(wow.printed) do
        if line:find("characters from the beta", 1, true) then return line end
    end
end

local function keys()
    local list = {}
    for key in pairs(AltsForeverDB.chars) do list[#list + 1] = key end
    table.sort(list)
    return table.concat(list, ",")
end

-- The live game: 1.0.0 is out (BETA_ENDED), and it's later than that.
LIVE = 1792713600 + 7 * DAY

test("during the beta nothing changes", function()
    wow.betaEnded = true
    local ns = wow.load(FILES)
    wow.player.realm = "ClassicBetaPvE2"
    wow.login(betaSave())
    runTimers()
    eq(betaLine(), nil)
    eq(keys(), "Aldric,Old,Rook Vale,Tarn Moon")
    eq(ns.char.bank[2318], 5, "your saved bank is still yours")
    eq(AltsForeverDB.legacyPool, 16)
    eq(AltsForeverDB.goldGroup, "ClassicBetaPvE2|Alliance")
    eq(AltsForeverDB.goldDaysBy["ClassicBetaPvP|Horde"] ~= nil, true)
end)

test("first login on a live realm: the beta's characters are forgotten, settings kept", function()
    wow.betaEnded = true
    local ns = legacyStart(betaSave(), { 0, 0 }, 0, true)
    eq(keys(), "Aldric", "only you, and you're new")
    eq(ns.char.realm, "Realm")
    eq(ns.char.bank, nil, "a new character: the beta's bank isn't yours")
    eq(ns.char.bags[2589], nil, "nor its bags")
    eq(ns.char.money, wow.money)
    assert(betaLine():find("(4)", 1, true), betaLine())
    eq(AltsForeverDB.countsOff, true, "settings kept")
    eq(AltsForeverDB.goldDays[100], nil, "the beta's gold history is gone")
    eq(AltsForeverDB.goldGroup, "Realm|Alliance", "this group's history is the main one now")
    eq(AltsForeverDB.goldDaysBy, nil)
    eq(AltsForeverDB.collapsedGroups, nil)
    eq(AltsForeverDB.legacyPool, 0, "Legacy points read afresh: the live account has none yet")
    eq(AltsForeverDB.wellRested, nil)
    eq(legacyPrinted():find("Legacy point", 1, true), nil, "no reminder of the beta's points")
    eq(legacyPrinted():find("Tarn Moon", 1, true), nil, "no warning for mail left on the beta")

    -- Next login: nothing left to forget, nothing said.
    local saved = AltsForeverDB
    wow.betaEnded = true
    wow.load(FILES)
    wow.printed = {}
    wow.login(saved)
    runTimers()
    eq(betaLine(), nil)
    eq(keys(), "Aldric")
    eq(AltsForeverDB, saved)
end)

test("a live save without beta characters, or a fresh install, is left alone", function()
    wow.betaEnded = true
    local ns = wow.load(FILES)
    wow.now = LIVE
    wow.login({ v = 2, legacyPool = 4, chars = {
        ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { realm = "Realm", seen = LIVE - DAY }),
        ["Seen Live"] = alt("Seen Live", "MAGE", { seen = LIVE - DAY, updated = LIVE - DAY }),
        ["No Time"] = alt("No Time", "WARRIOR", {}) } })
    runTimers()
    eq(betaLine(), nil)
    eq(keys(), "Aldric,No Time,Seen Live,Tarn Moon",
        "of unknown realm: one seen since 1.0.0 came out, or with no time recorded, stays")
    eq(AltsForeverDB.legacyPool, 4)
    wow.now = nil

    wow.betaEnded = true
    wow.load(FILES)
    wow.login(nil)
    runTimers()
    eq(betaLine(), nil)
    assert(table.concat(wow.printed, "\n"):find("Welcome!", 1, true), "just the welcome")
end)

test("first live login with a save from before realms were recorded (0.11 or older): all of it was the beta", function()
    wow.betaEnded = true
    local ns = legacyStart({ v = 2, legacyPool = 16, goldDays = { [100] = 5000 }, chars = {
        ["Aldric"] = alt("Aldric", "MAGE", { bank = { [2318] = 5 }, legacySpent = 3, seen = NOW - 40 * DAY, updated = NOW - 40 * DAY }),
        ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { seen = NOW - 40 * DAY }) } }, { 0, 0 }, 0, true)
    eq(keys(), "Aldric")
    eq(ns.char.bank, nil, "you start fresh")
    assert(betaLine():find("(2)", 1, true), betaLine())
    eq(AltsForeverDB.legacyPool, 0)
    eq(legacyPrinted():find("Legacy point", 1, true), nil, "no reminder of the beta's points")
end)

test("first live login with a version 1 save (Name-Realm keys from the beta)", function()
    wow.betaEnded = true
    local ns = wow.load(FILES)
    wow.login({ v = 1, chars = {
        ["Aldric-ClassicBetaPvE2"] = alt("Aldric", "MAGE", { realm = "ClassicBetaPvE2", bank = { [2318] = 5 }, updated = NOW - 60 * DAY }),
        ["Tarn Moon-ClassicBetaPvE2"] = alt("Tarn Moon", "DRUID", { realm = "ClassicBetaPvE2", seen = NOW - 60 * DAY }) } })
    eq(keys(), "Aldric")
    eq(ns.char.bank, nil)
end)

test("a live character whose realm couldn't be read at its first login is kept at the next", function()
    -- A copied beta folder, then a live login where the game gave no realm name.
    wow.betaEnded = true
    local ns = wow.load(FILES)
    wow.now = LIVE
    wow.player.name, wow.player.realm = "Nova Brightwind", nil
    wow.login(betaSave())
    eq(ns.char.realm, nil)
    eq(keys(), "Aldric,Nova Brightwind,Old,Rook Vale,Tarn Moon", "no realm: nothing to go by yet")
    ns.char.bank = { [2318] = 7 }
    wow.fire("PLAYER_LOGOUT")
    -- Next login, the realm reads.
    local saved = AltsForeverDB
    wow.betaEnded = true
    ns = wow.load(FILES)
    wow.now = LIVE + DAY
    wow.player.name, wow.player.realm = "Nova Brightwind", "Realm"
    wow.login(saved)
    eq(keys(), "Nova Brightwind", "the beta's characters go; the live one stays")
    eq(ns.char.bank[2318], 7, "with what was recorded")
    eq(ns.char.realm, "Realm")
    wow.now = nil
end)
