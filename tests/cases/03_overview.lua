-- Tests: overview. Loaded by tests/run.lua, which provides test, eq, wow, FILES and the
-- other shared helpers; helpers defined here are shared with the other files too.
---------------------------------------------------------------------------
-- Character info, rested XP and the overview window

HOUR, DAY = 3600, 86400
NOW = 1790000000
G = "|cff9d9d9d"

function overviewRows()
    local rows = {}
    for _, f in ipairs(wow.frames) do
        -- rawget: the fake frames answer any other name with a stand-in method.
        if rawget(f, "cells") and f.shown then rows[#rows + 1] = f end
    end
    return rows
end

function cell(row, i) return row.cells[i].text end

function overviewAlts()
    return { v = 2, chars = {
        ["Low"] = alt("Low", "ROGUE", { level = 12, xp = 100, xpMax = 1000, rested = 0,
            updated = NOW - 2 * DAY, money = 500 }),
        ["High"] = alt("High", "PRIEST", { level = 40, xp = 0, xpMax = 50000, rested = 75000,
            resting = true, updated = NOW - 3 * HOUR, money = 10000, zone = "Orgrimmar",
            profs = { Tailoring = 200, Enchanting = 180 }, prof1 = "Tailoring", prof2 = "Enchanting" }),
        ["Far"] = alt("Far", "MAGE", { level = 60, money = 7 }),
    } }
end

test("character info is recorded at login and kept current", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.stats.rested = 2000
    wow.stats.resting = true
    wow.login(nil)
    local c = ns.char
    eq(c.level, 24); eq(c.xp, 5700); eq(c.xpMax, 10000)
    eq(c.rested, 2000); eq(c.resting, true)
    eq(c.zone, "Durotar"); eq(c.hearth, "Razor Hill")
    eq(c.ilvl, 22, "equipped item level, rounded")
    eq(c.updated, NOW)
    wow.stats.xp, wow.stats.rested, wow.stats.resting = 6000, nil, false
    wow.fire("PLAYER_XP_UPDATE", "player")
    eq(c.xp, 6000)
    eq(c.rested, 0, "no rested XP is stored as 0")
    eq(c.resting, nil)
end)

test("logging out keeps the real stats, though the game reports zeros by then", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.stats.rested, wow.stats.resting = 2000, true
    wow.login(nil)
    -- What the game reports during logout:
    wow.stats.xp, wow.stats.xpMax, wow.stats.rested, wow.stats.resting, wow.stats.ilvl = 0, 0, nil, false, 0
    wow.now = NOW + 60
    wow.fire("PLAYER_LOGOUT")
    local c = ns.char
    eq(c.xp, 5700); eq(c.xpMax, 10000); eq(c.rested, 2000); eq(c.resting, true); eq(c.ilvl, 22)
    eq(c.updated, NOW + 60, "logout time is where the offline estimate starts")
end)

test("a zeroed reading at any other time is ignored too", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    wow.stats.xp, wow.stats.xpMax, wow.stats.ilvl = 0, 0, 0
    wow.fire("PLAYER_ENTERING_WORLD")
    eq(ns.char.xpMax, 10000)
    eq(ns.char.ilvl, 22)
end)

test("secret values are never stored as character info", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    wow.stats.level = wow.SECRET
    wow.fire("PLAYER_LEVEL_UP")
    eq(ns.char.level, 24)
end)

test("rested XP builds while logged out: full rate resting, a quarter elsewhere", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    local inn = { level = 20, xpMax = 10000, rested = 1000, resting = true, updated = NOW - 8 * HOUR }
    local field = { level = 20, xpMax = 10000, rested = 1000, resting = nil, updated = NOW - 8 * HOUR }
    eq(ns.RestedNow(inn, NOW), 1500, "5% of a level per 8 hours")
    eq(ns.RestedNow(field, NOW), 1125, "a quarter of that outside an inn or city")
end)

test("rested XP stops at 150% of a level and reports time until full", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    local long = { level = 20, xpMax = 10000, rested = 0, resting = true, updated = NOW - 400 * DAY }
    local rested, cap, toFull = ns.RestedNow(long, NOW)
    eq(rested, 15000); eq(cap, 15000); eq(toFull, 0)
    local fresh = { level = 20, xpMax = 10000, rested = 0, resting = true, updated = NOW }
    local _, _, secs = ns.RestedNow(fresh, NOW)
    eq(secs, 240 * HOUR, "30 blocks of 8 hours from empty")
end)

test("rested XP: none at max level, and no estimate for the character you're on", function()
    local ns = wow.load(FILES)
    wow.stats.rested = 3000
    wow.login(nil)
    eq(ns.RestedNow({ level = 60, xpMax = 10000, rested = 0 }, NOW), nil)
    ns.char.updated = NOW - 10 * DAY
    eq(ns.RestedNow(ns.char, NOW), 3000, "live value, not projected")
end)

function runTimers()
    local fns = wow.timers
    wow.timers = {}
    for _, fn in ipairs(fns) do fn() end
end

test("results of the removed rested XP check are cleared from saved data", function()
    wow.load(FILES)
    wow.login({ v = 2, chars = {}, restedChecks = { { observed = 5 } }, restCheckOff = true })
    eq(AltsForeverDB.restedChecks, nil)
    eq(AltsForeverDB.restCheckOff, nil)
    SlashCmdList.ALTSFOREVER("restcheck")
    assert(table.concat(wow.printed, "\n"):find("/af opens the overview", 1, true), "unknown command shows help")
end)

test("overview text: time since, level, rested and professions", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    eq(ns.FormatAgo(1800), "<1h"); eq(ns.FormatAgo(7200), "2h ago"); eq(ns.FormatAgo(3 * DAY), "3d ago")
    eq(ns.LevelText({ level = 24, xp = 5700, xpMax = 10000 }), "24  " .. G .. "57%|r")
    eq(ns.LevelText({ level = 60, xp = 0, xpMax = 0 }), "60")
    eq(ns.RestedText({ level = 20, xpMax = 10000, rested = 1500, updated = NOW }, NOW), "15%")
    eq(ns.RestedText({ level = 20, xpMax = 10000, rested = 15000, updated = NOW }, NOW), "|cff4da6ff150%|r")
    eq(ns.RestedText({ level = 60, xpMax = 10000, rested = 0 }, NOW), G .. "-|r")
    eq(ns.RestedText({}, NOW), G .. "?|r", "not recorded yet")
    local L = "|cffc0c0c0"
    local n1, s1, n2, s2 = ns.ProfCells({ profs = { Engineering = 107, Mining = 99, Cooking = 35 },
        prof1 = "Engineering", prof2 = "Mining" })
    eq(n1, L .. "Engineering|r"); eq(s1, "107"); eq(n2, L .. "Mining|r"); eq(s2, "99")
    eq((ns.ProfCells({})), G .. "?|r", "never recorded")
    eq((ns.ProfCells({ profs = { Cooking = 35 } })), G .. "-|r", "no main professions")
    n1, s1, n2, s2 = ns.ProfCells({ profs = { Mining = 99 }, prof1 = "Mining" })
    eq(s1, "99"); eq(n2, ""); eq(s2, "", "only one main profession")
end)

test("main professions are the first two the game lists", function()
    local ns = wow.load(FILES)
    wow.profs = { { "Engineering", 107 }, { "Mining", 99 }, { "Cooking", 35 } }
    wow.login(nil)
    eq(ns.char.prof1, "Engineering"); eq(ns.char.prof2, "Mining")
end)

test("the overview window isn't built until /af is used", function()
    wow.load(FILES)
    wow.login(nil)
    eq(AltsForeverFrame, nil)
    SlashCmdList.ALTSFOREVER("")
    eq(AltsForeverFrame:IsShown(), true)
    SlashCmdList.ALTSFOREVER("")
    eq(AltsForeverFrame:IsShown(), false, "/af again closes it")
    local found = false
    for _, name in ipairs(UISpecialFrames) do found = found or name == "AltsForeverFrame" end
    eq(found, true, "Escape closes it")
end)

test("overview rows: you first, then by level; totals gold", function()
    wow.load(FILES)
    wow.now = NOW
    wow.money = 1234
    wow.profs = { { "Engineering", 107 }, { "Mining", 99 } }
    wow.login(overviewAlts())
    SlashCmdList.ALTSFOREVER("")
    local rows = overviewRows()
    eq(#rows, 4)
    eq(cell(rows[1], 1), "[MAGE]Aldric"); eq(cell(rows[1], 12), "|cff20ff20Online|r")
    eq(cell(rows[1], 5), "|cffc0c0c0Engineering|r"); eq(cell(rows[1], 6), "107")
    eq(cell(rows[1], 7), "|cffc0c0c0Mining|r"); eq(cell(rows[1], 8), "99")
    eq(cell(rows[2], 1), "[MAGE]Far"); eq(cell(rows[2], 2), "60"); eq(cell(rows[2], 3), G .. "-|r")
    eq(cell(rows[3], 1), "[PRIEST]High")
    eq(cell(rows[3], 3), "|cff4da6ff150%|r", "was already full")
    eq(cell(rows[3], 10), "Orgrimmar"); eq(cell(rows[3], 12), "3h ago")
    eq(cell(rows[4], 1), "[ROGUE]Low"); eq(cell(rows[4], 2), "12  " .. G .. "10%|r")
    eq(cell(rows[4], 12), "2d ago")
end)

test("an open overview updates when your money changes", function()
    wow.load(FILES)
    wow.money = 100
    wow.login(nil)
    SlashCmdList.ALTSFOREVER("")
    eq(cell(overviewRows()[1], 4), "100c")
    wow.money = 250
    wow.fire("PLAYER_MONEY")
    eq(cell(overviewRows()[1], 4), "250c")
end)

test("hovering a row shows rested details, hearthstone and item level", function()
    wow.load(FILES)
    wow.now = NOW
    wow.login(overviewAlts())
    SlashCmdList.ALTSFOREVER("")
    local row = overviewRows()[4] -- Low: level 12, not resting, logged out 2 days ago
    row.scripts.OnEnter(row)
    local text = {}
    for _, l in ipairs(GameTooltip.lines) do text[#text + 1] = table.concat(l, " = ") end
    text = table.concat(text, "\n")
    assert(text:find("Level 12", 1, true), text)
    -- 2 days away, not resting: 6 blocks of 8h x 1.25% x 1000 XP = 75 XP (8% of the level)
    assert(text:find("Rested = 75 XP (8%)", 1, true), text)
    assert(text:find("out in the world", 1, true), text)
    assert(text:find("Right-click to forget this character", 1, true), "how to forget them is shown")
    local you = overviewRows()[1]
    you.scripts.OnEnter(you)
    local mine = {}
    for _, l in ipairs(GameTooltip.lines) do mine[#mine + 1] = table.concat(l, " = ") end
    assert(not table.concat(mine, "\n"):find("forget", 1, true), "not on your own row")
end)

test("the window still opens if the client lacks Blizzard's frame template", function()
    wow.load(FILES)
    wow.missingTemplates.BasicFrameTemplateWithInset = true
    wow.login(nil)
    SlashCmdList.ALTSFOREVER("")
    eq(AltsForeverFrame:IsShown(), true)
    eq(AltsForeverFrame.template, "BackdropTemplate")
end)
