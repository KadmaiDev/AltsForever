-- Legacy: each character's Well Rested rank and the Legacy points they have left to spend.
-- Points are earned by the account but spent per character (checked in game 2026-10-12:
-- one character had 13 unspent and 3 spent, all in Well Rested, another had 5/5).

-- Logs in with Legacy data and enters the world; returns ns. timers: run the login reminder.
function legacyStart(saved, points, rank, timers)
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.legacy = { [ns.WELL_RESTED_NODE] = rank or 0 }
    wow.legacyPoints = points
    wow.login(saved)
    wow.fire("PLAYER_ENTERING_WORLD")
    if timers then
        for _, fn in ipairs(wow.timers) do fn() end
    end
    return ns
end

function legacyPrinted()
    return table.concat(wow.printed, "\n")
end

test("Well Rested: rested XP builds 4% faster with a 4% higher cap per rank", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    local inn = { level = 20, xpMax = 10000, rested = 1000, resting = true, updated = NOW - 8 * HOUR, wellRested = 5 }
    eq(ns.RestedNow(inn, NOW), 1600, "500 x 1.2 in 8 hours")
    local long = { level = 20, xpMax = 10000, rested = 0, resting = true, updated = NOW - 400 * DAY, wellRested = 5 }
    eq(select(2, ns.RestedNow(long, NOW)), 18000, "cap 150% x 1.2")
    inn.wellRested = nil
    eq(ns.RestedNow(inn, NOW), 1500, "never read: no bonus")
end)

test("Well Rested is each character's own; the old account-wide value only stands in until they log in", function()
    local ns = wow.load(FILES)
    wow.login({ v = 2, wellRested = 5, chars = {} })
    local inn = { level = 20, xpMax = 10000, rested = 1000, resting = true, updated = NOW - 8 * HOUR }
    eq(ns.RestedNow(inn, NOW), 1600, "not read yet: the value saved before 0.11.0")
    inn.wellRested = 0
    eq(ns.RestedNow(inn, NOW), 1500, "their own rank wins, even 0")
end)

test("Well Rested and Legacy points are read on entering the world and when they change", function()
    local ns = legacyStart(nil, { 13, 3 }, 3)
    local c = ns.char
    eq(c.wellRested, 3)
    eq(c.legacySpent, 3)
    eq(AltsForeverDB.legacyPool, 16)
    eq(ns.LegacyUnspent(c), 13)
    eq(AltsForeverDB.wellRested, nil, "nothing account-wide")
    wow.legacy[ns.WELL_RESTED_NODE] = 5
    wow.legacyPoints = { 11, 5 }
    wow.fire("TRAIT_CONFIG_UPDATED", 201)
    eq(c.wellRested, 5)
    eq(ns.LegacyUnspent(c), 11)
    wow.legacy = { [ns.WELL_RESTED_NODE + 1] = 4 } -- the node isn't in this config: left alone
    wow.fire("TRAIT_CONFIG_UPDATED", 201)
    eq(c.wellRested, 5)
end)

test("Legacy points: a logged-out character counts the points earned since", function()
    local saved = { v = 2, legacyPool = 4, chars = {
        ["Tarn Moon"] = alt("Tarn Moon", "HUNTER", { level = 20, legacySpent = 1 }),
        ["Old Timer"] = alt("Old Timer", "MAGE", { level = 20 }),
    } }
    local ns = legacyStart(saved, { 5, 0 }, 0)
    local chars = AltsForeverDB.chars
    eq(AltsForeverDB.legacyPool, 5, "a point earned since the last reading")
    eq(ns.LegacyUnspent(chars["Tarn Moon"]), 4)
    eq(ns.LegacyUnspent(chars["Old Timer"]), nil, "never read")
    eq(ns.LegacyUnspent(ns.char), 5)
end)

test("Legacy points: the pool never shrinks, and an unreadable reading changes nothing", function()
    local ns = legacyStart({ v = 2, legacyPool = 16, chars = {} }, { 0, 0 }, 0)
    eq(AltsForeverDB.legacyPool, 16, "a reading of 0 before the data arrives")
    wow.legacyPoints = nil
    ns.char.legacySpent = 3
    wow.fire("TRAIT_CONFIG_UPDATED", 201)
    eq(ns.char.legacySpent, 3, "no currency reported: left alone")
end)

test("Legacy reminder at login: points to spend, and Well Rested while levelling", function()
    legacyStart(nil, { 2, 3 }, 3, true)
    local text = legacyPrinted()
    assert(text:find("You have 2 Legacy points to spend on this character.", 1, true), text)
    assert(text:find("Well Rested is at 3/5 here", 1, true), text)
    legacyStart(nil, { 1, 5 }, 5, true)
    text = legacyPrinted()
    assert(text:find("You have 1 Legacy point to spend", 1, true), text)
    assert(not text:find("Well Rested is at", 1, true), "5/5: nothing to add\n" .. text)
    legacyStart(nil, { 0, 16 }, 5, true)
    assert(not legacyPrinted():find("Legacy point", 1, true), "all spent: no reminder")
end)

test("earning a Legacy point while playing says how many characters can spend it", function()
    local saved = { v = 2, legacyPool = 4, chars = {
        ["Tarn Moon"] = alt("Tarn Moon", "HUNTER", { level = 20, legacySpent = 4 }),
        ["Never Read"] = alt("Never Read", "MAGE", { level = 20 }),
    } }
    legacyStart(saved, { 0, 4 }, 4, true)
    eq(legacyPrinted():find("Legacy point", 1, true), nil, "nothing to spend yet")
    wow.legacyPoints = { 1, 4 }
    wow.fire("TRAIT_TREE_CURRENCY_INFO_UPDATED", 1187)
    local text = legacyPrinted()
    assert(text:find("Legacy point earned! 2 of your characters can spend it", 1, true), text)
    -- Spending it: no announcement.
    wow.printed = {}
    wow.legacyPoints = { 0, 5 }
    wow.fire("TRAIT_TREE_CURRENCY_INFO_UPDATED", 1187)
    eq(#wow.printed, 0)
end)

test("Legacy reminders can be turned off: /af legacy off, the menu and the Options page", function()
    local ns = legacyStart(nil, { 2, 0 }, 0)
    SlashCmdList.ALTSFOREVER("legacy off")
    eq(AltsForeverDB.legacyRemindOff, true)
    wow.printed = {}
    for _, fn in ipairs(wow.timers) do fn() end
    eq(legacyPrinted():find("to spend on this character", 1, true), nil, "no login reminder")
    wow.legacyPoints = { 3, 0 }
    wow.fire("TRAIT_TREE_CURRENCY_INFO_UPDATED", 1187)
    eq(legacyPrinted():find("earned", 1, true), nil, "no announcement")
    ns.ShowOptionsMenu(UIParent)
    wow.menuItem("Legacy reminders").setSelected()
    eq(AltsForeverDB.legacyRemindOff, nil)
    SlashCmdList.ALTSFOREVER("legacy off")
    SlashCmdList.ALTSFOREVER("legacy on")
    eq(AltsForeverDB.legacyRemindOff, nil)
end)

test("/af legacy lists everyone's points to spend and Well Rested, most to spend first", function()
    local saved = { v = 2, legacyPool = 16, chars = {
        ["Tarn Moon"] = alt("Tarn Moon", "HUNTER", { level = 20, legacySpent = 16, wellRested = 5 }),
        ["Eve Ash"] = alt("Eve Ash", "PRIEST", { level = 20, legacySpent = 6, wellRested = 2 }),
        ["Never Read"] = alt("Never Read", "MAGE", { level = 20 }),
    } }
    legacyStart(saved, { 13, 3 }, 3)
    wow.printed = {}
    SlashCmdList.ALTSFOREVER("legacy")
    local text = legacyPrinted()
    local mine = text:find("13 to spend", 1, true)
    local eve = text:find("Eve Ash", 1, true)
    local tarn = text:find("Tarn Moon", 1, true)
    assert(mine and eve and tarn and mine < eve and eve < tarn, text)
    assert(text:find("10 to spend|r · Well Rested 2/5", 1, true), text)
    assert(text:find("all spent · Well Rested 5/5", 1, true), text)
    eq(text:find("Never Read", 1, true), nil, "nothing known about them")
end)

test("the overview has Legacy and Well Rested columns; the row tooltip shows both", function()
    local saved = { v = 2, legacyPool = 16, chars = {
        ["Tarn Moon"] = alt("Tarn Moon", "HUNTER", { level = 20, xp = 0, xpMax = 1000, rested = 0,
            updated = NOW - HOUR, legacySpent = 16, wellRested = 5 }),
        ["Zed Never"] = alt("Zed Never", "MAGE", { level = 10 }),
    } }
    legacyStart(saved, { 13, 3 }, 3)
    SlashCmdList.ALTSFOREVER("")
    local rows = overviewRows()
    eq(cell(rows[1], 4), "|cffffd10013|r", "points to spend, in gold")
    eq(cell(rows[1], 5), "3/5")
    eq(cell(rows[2], 4), "|cff9d9d9d0|r", "all spent")
    eq(cell(rows[2], 5), "5/5")
    eq(cell(rows[3], 4), "|cff9d9d9d?|r", "never read")
    eq(cell(rows[3], 5), "|cff9d9d9d?|r")
    rows[2].scripts.OnEnter(rows[2])
    local text = textOf(GameTooltip.lines)
    assert(text:find("Well Rested = 5/5", 1, true), text)
    assert(text:find("Legacy points = all spent", 1, true), text)
end)
