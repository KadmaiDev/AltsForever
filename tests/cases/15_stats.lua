-- Tests: stats. Loaded by tests/run.lua, which provides test, eq, wow, FILES and the
-- other shared helpers; helpers defined here are shared with the other files too.
---------------------------------------------------------------------------
-- Session stats (off by default)
test("session stats are off by default: no pace on the XP bar, no gold over time", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    local bar = blizzardXPBar()
    wow.money = 500
    wow.login(overviewAlts())
    wow.fire("PLAYER_ENTERING_WORLD")
    bar.scripts.OnEnter(bar)
    eq(lineTexts(GameTooltip):find("This session", 1, true), nil)
    local tt = wow.tooltip()
    ns.AddMoneyLines(tt)
    for _, l in ipairs(tt.lines) do assert(l[1] ~= "This session", "no gold stats") end
end)

test("session stats: XP this session across a level-up, and about how long to level", function()
    wow.load(FILES)
    wow.now = NOW
    local bar = blizzardXPBar()
    wow.stats.level, wow.stats.xp, wow.stats.xpMax = 24, 5700, 10000
    wow.login(overviewAlts())
    wow.fire("PLAYER_ENTERING_WORLD")
    SlashCmdList.ALTSFOREVER("stats")
    eq(AltsForeverDB.statsOn, true)
    wow.stats.xp = 7700
    wow.fire("PLAYER_XP_UPDATE", "player")
    wow.stats.level, wow.stats.xp, wow.stats.xpMax = 25, 500, 12000
    wow.fire("PLAYER_LEVEL_UP", 25)
    wow.fire("PLAYER_XP_UPDATE", "player")
    wow.now = NOW + 3600
    bar.scripts.OnEnter(bar)
    local lines = {}
    for _, l in ipairs(GameTooltip.lines) do lines[#lines + 1] = l[1] .. "=" .. tostring(l[2]) end
    local text = table.concat(lines, " | ")
    assert(text:find("This session=1h 0m", 1, true), text)
    assert(text:find("XP gained=4800", 1, true) or text:find("XP gained=4,800", 1, true), text)
    -- 11,500 XP to go at 4,800 an hour: about 2h 23m.
    assert(text:find("Time to level=about 2h 23m", 1, true), text)
    assert(text:find("Your characters", 1, true), "alts still listed after")
    SlashCmdList.ALTSFOREVER("stats")
    eq(AltsForeverDB.statsOn, nil)
end)

test("session stats: gold this session, today and this week across characters", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.money = 1000
    wow.login({ v = 2, chars = { ["Brak Stone"] = alt("Brak Stone", "WARRIOR", { money = 5000 }) } })
    local days = AltsForeverDB.goldDays
    local today
    for day in pairs(days) do today = day end
    eq(days[today], 6000, "today's total recorded at login")
    days[today - 1] = 4000 -- yesterday
    days[today - 9] = 1000 -- over a week ago
    wow.money = 1500
    wow.fire("PLAYER_MONEY")
    eq(days[today], 6500)
    SlashCmdList.ALTSFOREVER("stats")
    local tt = wow.tooltip()
    ns.AddMoneyLines(tt)
    local got = {}
    for _, l in ipairs(tt.lines) do got[l[1]] = l[2] end
    eq(got["This session"], "|cff20ff20+500c|r", "gains in green")
    eq(got["Today, all characters"], "|cff20ff20+2500c|r")
    eq(got["This week, all characters"], "|cff20ff20+5500c|r")
    wow.money = 100
    wow.fire("PLAYER_MONEY")
    tt = wow.tooltip()
    ns.AddMoneyLines(tt)
    got = {}
    for _, l in ipairs(tt.lines) do got[l[1]] = l[2] end
    eq(got["This session"], "|cffff4040-900c|r", "losses in red")
    wow.money = 1000
    wow.fire("PLAYER_MONEY")
    tt = wow.tooltip()
    ns.AddMoneyLines(tt)
    got = {}
    for _, l in ipairs(tt.lines) do got[l[1]] = l[2] end
    eq(got["This session"], "0c", "no change: plain")
    -- Days over a year old are dropped when a new day starts.
    days[today - 500] = 1
    wow.now = NOW + 86400
    wow.fire("PLAYER_MONEY")
    eq(days[today - 500], nil)
end)

test("session stats carry over a /reload, but start again on a real login", function()
    wow.load(FILES)
    wow.now = NOW
    wow.money = 1000
    wow.stats.level, wow.stats.xp, wow.stats.xpMax = 24, 5700, 10000
    wow.login({ v = 2, chars = {}, statsOn = true })
    wow.fire("PLAYER_ENTERING_WORLD", true, false)
    wow.stats.xp = 6700
    wow.fire("PLAYER_XP_UPDATE", "player")
    wow.money = 1500
    wow.fire("PLAYER_MONEY")
    wow.now = NOW + 1800
    wow.fire("PLAYER_LOGOUT") -- /reload
    local saved = AltsForeverDB

    local function reloaded(isInitialLogin, isReloadingUi, at)
        local ns = wow.load(FILES)
        wow.now, wow.money = at, 1500
        wow.stats.level, wow.stats.xp, wow.stats.xpMax = 24, 6700, 10000
        wow.login(saved)
        wow.fire("PLAYER_ENTERING_WORLD", isInitialLogin, isReloadingUi)
        local seconds, xp = ns.SessionXP(at + 600)
        local tt = wow.tooltip()
        ns.AddMoneyLines(tt)
        local gold
        for _, l in ipairs(tt.lines) do if l[1] == "This session" then gold = l[2] end end
        return seconds, xp, gold
    end
    local seconds, xp, gold = reloaded(false, true, NOW + 1810)
    eq(seconds, 2410, "counted from the first login"); eq(xp, 1000); eq(gold, "|cff20ff20+500c|r")
    eq(AltsForeverDB.session, nil, "used up")

    wow.fire("PLAYER_LOGOUT")
    saved = AltsForeverDB
    seconds, xp, gold = reloaded(true, false, NOW + 1820)
    eq(seconds, 600, "a real login starts again"); eq(xp, 0); eq(gold, "0c")
end)
