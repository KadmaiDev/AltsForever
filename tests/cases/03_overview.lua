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
    eq(ns.RestedText({ level = 20, xpMax = 10000, rested = 1500, resting = true, updated = NOW }, NOW), "15%")
    eq(ns.RestedText({ level = 20, xpMax = 10000, rested = 1500, updated = NOW }, NOW), "|cffff800015%|r",
        "orange: filling outside an inn or city")
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
    eq(cell(rows[1], 1), "[MAGE]Aldric"); eq(cell(rows[1], 15), "|cff20ff20Online|r")
    eq(cell(rows[1], 7), "|cffc0c0c0Engineering|r"); eq(cell(rows[1], 8), "107")
    eq(cell(rows[1], 9), "|cffc0c0c0Mining|r"); eq(cell(rows[1], 10), "99")
    eq(cell(rows[2], 1), "[MAGE]Far"); eq(cell(rows[2], 2), "60"); eq(cell(rows[2], 3), G .. "-|r")
    eq(cell(rows[3], 1), "[PRIEST]High")
    eq(cell(rows[3], 3), "|cff4da6ff150%|r", "was already full")
    eq(cell(rows[3], 13), "Orgrimmar"); eq(cell(rows[3], 15), "3h ago")
    eq(cell(rows[4], 1), "[ROGUE]Low"); eq(cell(rows[4], 2), "12")
    eq(rows[4].pct.text, G .. "10%|r", "the percentage in its own cell, so they line up")
    eq(rows[2].pct.text, "", "none at max level")
    eq(cell(rows[4], 15), "2d ago")
end)

test("an open overview updates when your money changes", function()
    wow.load(FILES)
    wow.money = 100
    wow.login(nil)
    SlashCmdList.ALTSFOREVER("")
    eq(cell(overviewRows()[1], 6), "100c")
    wow.money = 250
    wow.fire("PLAYER_MONEY")
    eq(cell(overviewRows()[1], 6), "250c")
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
    assert(text:find("Rested = 75 XP (|cffff80008%|r)", 1, true), text)
    assert(text:find("out in the world", 1, true), text)
    assert(text:find("Right-click for bags, professions and more", 1, true), "the menu is mentioned")
    local you = overviewRows()[1]
    you.scripts.OnEnter(you)
    local mine = {}
    for _, l in ipairs(GameTooltip.lines) do mine[#mine + 1] = table.concat(l, " = ") end
    assert(not table.concat(mine, "\n"):find("forget", 1, true), "not on your own row")
end)

test("the window still opens if the client lacks Blizzard's frame templates", function()
    wow.load(FILES)
    wow.missingTemplates.DefaultPanelTemplate = true
    wow.login(nil)
    SlashCmdList.ALTSFOREVER("")
    eq(AltsForeverFrame:IsShown(), true)
    eq(AltsForeverFrame.template, "BasicFrameTemplateWithInset", "the older frame")
    wow.load(FILES)
    wow.missingTemplates.DefaultPanelTemplate = true
    wow.missingTemplates.BasicFrameTemplateWithInset = true
    wow.login(nil)
    SlashCmdList.ALTSFOREVER("")
    eq(AltsForeverFrame:IsShown(), true)
    eq(AltsForeverFrame.template, "BackdropTemplate")
end)

test("our windows use the game's current frame, with a close button, an inset and their title", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    SlashCmdList.ALTSFOREVER("")
    local f = AltsForeverFrame
    eq(f.template, "DefaultPanelTemplate")
    eq(f.TitleText, f.TitleContainer.TitleText)
    eq(f.TitleText.text, "Alts Forever")
    eq(f.CloseButton.template, "UIPanelCloseButtonDefaultAnchors")
    eq(f.Inset.template, "InsetFrameTemplate")
    -- The border and title bar are drawn by a child frame at level 500: the buttons on the
    -- title bar must be above it, or they can't be seen or clicked.
    for _, name in ipairs({ "cog", "repButton", "lockoutsButton", "profsButton", "bagsButton", "searchButton", "exportButton", "syncButton" }) do
        assert(f[name].level > 500, name .. " is over the title bar")
    end
    assert(f.CloseButton.level > 500, "the close button too")
    -- Every other window is made the same way.
    ns.ShowBags(ns.charKey, "bags")
    eq(AltsForeverBagsFrame.template, "DefaultPanelTemplate")
    assert(AltsForeverBagsFrame.searchButton.level > 500, "the bags window's search button")
    for _, name in ipairs({ "Export", "Search", "Sync", "Lockouts", "Reputation" }) do
        ns["Toggle" .. name]()
        local frame = _G["AltsForever" .. (name == "Reputation" and "Rep" or name) .. "Frame"]
        eq(frame.template, "DefaultPanelTemplate", name)
    end
    -- A client where the close button's template is missing still gets one.
    wow.load(FILES)
    wow.missingTemplates.UIPanelCloseButtonDefaultAnchors = true
    wow.missingTemplates.InsetFrameTemplate = true
    wow.login(nil)
    SlashCmdList.ALTSFOREVER("")
    eq(AltsForeverFrame.CloseButton.template, "UIPanelCloseButton")
    eq(rawget(AltsForeverFrame, "Inset"), nil)
end)

---------------------------------------------------------------------------
-- Ordering the overview by a column

-- The names down the overview, first to last.
function overviewNames()
    local names = {}
    -- Without a pinned character's star.
    for i, row in ipairs(overviewRows()) do names[i] = cell(row, 1):match("%](.+)$"):gsub(" |T.-|t$", "") end
    return table.concat(names, ", ")
end

-- Opens the overview on Aldric (24, 300c, Durotar) with Far (60, 7c), High (40, 1g,
-- Orgrimmar) and Low (12, 5s); returns a function clicking a column's title.
function sortStart(saved)
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.money = 300
    wow.login(saved or overviewAlts())
    SlashCmdList.ALTSFOREVER("")
    return function(name)
        local b = AltsForeverFrame.sorts[name]
        b.scripts.OnClick(b)
    end, ns
end

test("the overview starts by level with you first, the arrow on Level, nothing saved", function()
    sortStart()
    eq(overviewNames(), "Aldric, Far, High, Low")
    local f = AltsForeverFrame
    eq(f.sortArrow.texture, "Interface\\Buttons\\Arrow-Down-Up")
    eq(f.sortArrow.point[2], f.sorts.level.title, "beside the Level title")
    eq(AltsForeverDB.overviewSort, nil); eq(AltsForeverDB.overviewSortRev, nil)
    for _, name in ipairs({ "name", "level", "rested", "wellRested", "legacy", "gold", "mail", "zone", "played", "seen" }) do
        assert(f.sorts[name], name .. " can be clicked")
    end
    local n = 0
    for _ in pairs(f.sorts) do n = n + 1 end
    eq(n, 10, "professions and lockouts can't")
end)

test("clicking a column title orders by it, you among the rest; again turns it round", function()
    local click = sortStart()
    click("gold")
    eq(overviewNames(), "High, Low, Aldric, Far", "most gold first")
    eq(AltsForeverDB.overviewSort, "gold"); eq(AltsForeverDB.overviewSortRev, nil)
    local f = AltsForeverFrame
    eq(f.sortArrow.texture, "Interface\\Buttons\\Arrow-Down-Up")
    eq(f.sortArrow.point[2], f.sorts.gold.title)
    click("gold")
    eq(overviewNames(), "Far, Aldric, Low, High")
    eq(AltsForeverDB.overviewSortRev, true)
    eq(f.sortArrow.texture, "Interface\\Buttons\\Arrow-Up-Up")
    click("name")
    eq(overviewNames(), "Aldric, Far, High, Low", "a new column starts in its own natural order")
    eq(AltsForeverDB.overviewSort, "name"); eq(AltsForeverDB.overviewSortRev, nil)
    eq(f.sortArrow.texture, "Interface\\Buttons\\Arrow-Up-Up", "A first")
    click("name")
    eq(overviewNames(), "Low, High, Far, Aldric")
end)

test("Level puts the default back, and saves nothing; again is lowest first", function()
    local click = sortStart()
    click("gold")
    click("level")
    eq(overviewNames(), "Aldric, Far, High, Low", "you first again")
    eq(AltsForeverDB.overviewSort, nil); eq(AltsForeverDB.overviewSortRev, nil)
    click("level")
    eq(overviewNames(), "Low, Aldric, High, Far")
    eq(AltsForeverDB.overviewSort, nil); eq(AltsForeverDB.overviewSortRev, true)
    click("level")
    eq(overviewNames(), "Aldric, Far, High, Low")
    eq(AltsForeverDB.overviewSortRev, nil)
end)

test("characters without a value go last either way, by level", function()
    local click = sortStart()
    click("zone")
    eq(overviewNames(), "Aldric, High, Far, Low", "Durotar, Orgrimmar, then the unknown")
    click("zone")
    eq(overviewNames(), "High, Aldric, Far, Low")
    click("seen")
    eq(overviewNames(), "Aldric, High, Low, Far", "online, 3 hours, 2 days, never")
    click("rested")
    eq(overviewNames(), "High, Low, Aldric, Far", "150%, 8%, none; max level has none")
end)

test("the order is kept between sessions, and the other lists follow it", function()
    local click = sortStart()
    click("gold")
    click("gold")
    local saved = AltsForeverDB
    local _, ns = sortStart(saved)
    eq(overviewNames(), "Far, Aldric, Low, High")
    eq(AltsForeverFrame.sortArrow.texture, "Interface\\Buttons\\Arrow-Up-Up")
    eq(table.concat(ns.OverviewOrder(), ", "), "Far, Aldric, Low, High")
end)

test("a saved order that isn't one of ours is the default", function()
    local saved = overviewAlts()
    saved.overviewSort, saved.overviewSortRev = "nonsense", "yes"
    sortStart(saved)
    eq(overviewNames(), "Aldric, Far, High, Low")
    eq(AltsForeverDB.overviewSortRev, nil, "a damaged value is dropped at load")
    saved = overviewAlts()
    saved.overviewSort = 7
    sortStart(saved)
    eq(overviewNames(), "Aldric, Far, High, Low")
    eq(AltsForeverDB.overviewSort, nil)
end)

test("hovering a column title says it can be clicked", function()
    sortStart()
    local b = AltsForeverFrame.sorts.gold
    b.scripts.OnEnter(b)
    local text = {}
    for _, l in ipairs(GameTooltip.lines) do text[#text + 1] = table.concat(l, " = ") end
    text = table.concat(text, "\n")
    assert(text:find("Gold", 1, true), text)
    assert(text:find("Click to sort by this column, and again to reverse it.", 1, true), text)
end)

---------------------------------------------------------------------------
-- Where the windows are left

-- A window's anchor as "POINT relative RELPOINT x y" (the overview and the screen by name).
function placed(f)
    local p, rel, relPoint, x, y = unpack(f.point)
    local name = rel ~= nil and rel == AltsForeverFrame and "overview" or rel == UIParent and "screen" or tostring(rel)
    return ("%s %s %s %s %s"):format(p, name, tostring(relPoint), tostring(x), tostring(y))
end

-- Drops a window with its edges at left, right, top, bottom (as a drag ending there).
function drop(f, left, right, top, bottom)
    f.rect = { left, right, top, bottom }
    f.scripts.OnDragStop(f)
end

test("the overview opens where it was left, at any window size", function()
    wow.load(FILES)
    wow.login(nil)
    SlashCmdList.ALTSFOREVER("")
    local f = AltsForeverFrame
    eq(placed(f), "CENTER nil nil nil nil", "the middle until it's moved")
    eq(AltsForeverDB.windows, nil)
    drop(f, 100, 1100, 900, 700)
    eq(AltsForeverDB.windows.overview.x, 100); eq(AltsForeverDB.windows.overview.y, 900)
    local saved = AltsForeverDB
    wow.load(FILES)
    wow.login(saved)
    SlashCmdList.ALTSFOREVER("")
    eq(placed(AltsForeverFrame), "TOPLEFT screen BOTTOMLEFT 100 900")
    -- Twice the window size: the same spot on the screen, in the window's own units.
    saved = AltsForeverDB
    saved.scale = 2
    wow.load(FILES)
    wow.login(saved)
    SlashCmdList.ALTSFOREVER("")
    eq(placed(AltsForeverFrame), "TOPLEFT screen BOTTOMLEFT 50 450")
    drop(AltsForeverFrame, 60, 560, 400, 300)
    eq(AltsForeverDB.windows.overview.x, 120, "saved in the screen's units")
end)

test("a window dropped against the overview docks there; dropped elsewhere it stays", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    SlashCmdList.ALTSFOREVER("")
    local ov = AltsForeverFrame
    ov.rect = { 100, 1100, 900, 700 }
    SlashCmdList.ALTSFOREVER("lockouts")
    local lock = AltsForeverLockoutsFrame
    eq(lock.point[2], ov, "beside the overview by default")
    eq(AltsForeverDB.windows, nil, "nothing saved until it's dragged")

    -- Just under the overview, its left edge a little off: below, lined up.
    drop(lock, 108, 408, 690, 500)
    eq(placed(lock), "TOPLEFT overview BOTTOMLEFT 0 -4")
    eq(AltsForeverDB.windows.lockouts.dock, "below"); eq(AltsForeverDB.windows.lockouts.off, 0)
    -- Further along the bottom edge: kept where it was dropped.
    drop(lock, 400, 700, 700, 510)
    eq(placed(lock), "TOPLEFT overview BOTTOMLEFT 300 -4")
    -- Its right edge near the overview's: lined up on the right.
    drop(lock, 795, 1095, 700, 510)
    eq(placed(lock), "TOPLEFT overview BOTTOMLEFT 700 -4")
    -- Above, right and left of it.
    drop(lock, 100, 400, 1100, 910)
    eq(placed(lock), "BOTTOMLEFT overview TOPLEFT 0 4")
    drop(lock, 1110, 1410, 895, 705)
    eq(placed(lock), "TOPLEFT overview TOPRIGHT 4 0")
    eq(AltsForeverDB.windows.lockouts.dock, "right")
    drop(lock, 1100, 1400, 800, 610)
    eq(placed(lock), "TOPLEFT overview TOPRIGHT 4 -100")
    drop(lock, -210, 90, 800, 610)
    eq(placed(lock), "TOPRIGHT overview TOPLEFT -4 -100")
    eq(AltsForeverDB.windows.lockouts.dock, "left")

    -- Closed and opened again: against the same edge.
    SlashCmdList.ALTSFOREVER("lockouts")
    lock.point = nil
    SlashCmdList.ALTSFOREVER("lockouts")
    eq(placed(lock), "TOPRIGHT overview TOPLEFT -4 -100")

    -- Well away from the overview: free, and it opens there again.
    drop(lock, 1300, 1600, 400, 210)
    eq(AltsForeverDB.windows.lockouts.dock, nil)
    eq(AltsForeverDB.windows.lockouts.x, 1300); eq(AltsForeverDB.windows.lockouts.y, 400)
    SlashCmdList.ALTSFOREVER("lockouts")
    lock.point = nil
    SlashCmdList.ALTSFOREVER("lockouts")
    eq(placed(lock), "TOPLEFT screen BOTTOMLEFT 1300 400")
    -- Near the overview's corner but not against an edge it shares: still free.
    drop(lock, 1110, 1410, 690, 500)
    eq(AltsForeverDB.windows.lockouts.dock, nil)

    -- The overview itself never docks; with it closed a docked window opens as by default.
    drop(lock, 108, 408, 690, 500)
    eq(AltsForeverDB.windows.lockouts.dock, "below")
    SlashCmdList.ALTSFOREVER("lockouts")
    ns.ToggleOverview()
    SlashCmdList.ALTSFOREVER("lockouts")
    eq(placed(lock), "CENTER nil nil nil nil")
    eq(AltsForeverDB.windows.lockouts.dock, "below", "still docked next time")
end)

test("the bags window and the search go beside an open overview, or where they were left", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    ns.ShowBags(ns.charKey, "bags")
    local bags = AltsForeverBagsFrame
    eq(placed(bags), "CENTER nil nil nil nil", "no overview: where it always opened")
    ns.ShowBags(ns.charKey, "bags")
    SlashCmdList.ALTSFOREVER("")
    AltsForeverFrame.rect = { 100, 1100, 900, 700 }
    ns.ShowBags(ns.charKey, "bags")
    eq(bags.point[2], AltsForeverFrame, "beside the overview")
    drop(bags, 1300, 1700, 500, 100)
    ns.ShowBags(ns.charKey, "bags")
    bags.point = nil
    ns.ShowBags(ns.charKey, "bags")
    eq(placed(bags), "TOPLEFT screen BOTTOMLEFT 1300 500")
    ns.ShowBags(ns.charKey, "bags")
    -- The search: beside the overview, and beside the bags window when that's open.
    ns.ToggleSearch()
    local search = AltsForeverSearchFrame
    eq(search.point[2], AltsForeverFrame)
    ns.ToggleSearch()
    ns.ShowBags(ns.charKey, "bags")
    ns.ToggleSearch()
    eq(search.point[2], bags, "the bags window comes first")
    ns.ToggleSearch()
    ns.ShowBags(ns.charKey, "bags")
    ns.ToggleOverview()
    ns.ToggleSearch()
    eq(placed(search), "CENTER screen CENTER 0 120", "neither open: where it always opened")
end)

test("window positions can be reset, and a damaged one is ignored", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    SlashCmdList.ALTSFOREVER("")
    local ov = AltsForeverFrame
    drop(ov, 100, 1100, 900, 700)
    SlashCmdList.ALTSFOREVER("lockouts")
    local lock = AltsForeverLockoutsFrame
    drop(lock, 1300, 1600, 400, 210)
    SlashCmdList.ALTSFOREVER("resetwindows")
    eq(AltsForeverDB.windows, nil)
    eq(placed(ov), "CENTER nil nil nil nil")
    eq(lock.point[2], ov, "an open window goes back beside the overview")
    assert(table.concat(wow.printed, " "):find("back where they open by default", 1, true))
    -- The cog menu has it too.
    drop(ov, 100, 1100, 900, 700)
    ns.ShowOptionsMenu(ov.cog, true)
    wow.menuItem("Reset window positions").fn()
    eq(AltsForeverDB.windows, nil)
    -- Damaged saves.
    for _, bad in ipairs({ "x", { overview = 5 }, { overview = { x = "a", y = 3 } }, { overview = { dock = "below", off = 0 } } }) do
        wow.load(FILES)
        wow.login({ v = 2, chars = {}, windows = bad })
        SlashCmdList.ALTSFOREVER("")
        eq(placed(AltsForeverFrame), "CENTER nil nil nil nil")
    end
end)

---------------------------------------------------------------------------
-- Pinned characters

-- Opens a character's menu from their overview row and returns the entry with this text.
function rowMenu(name, text)
    for _, row in ipairs(overviewRows()) do
        if row.key == name then row.scripts.OnClick(row, "RightButton") end
    end
    return wow.menuItem(text)
end

test("pinned characters head the overview in your order, whatever it's sorted by", function()
    local click, ns = sortStart()
    eq(overviewNames(), "Aldric, Far, High, Low")
    eq(rowMenu("Low", "Unpin"), nil)
    rowMenu("Low", "Pin to top").fn()
    eq(overviewNames(), "Aldric, Low, Far, High", "under the character you're on")
    eq(AltsForeverDB.pinned[1], "Low")
    local star = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:0|t"
    assert(cell(overviewRows()[2], 1):find(star, 1, true), "marked with a star")
    assert(not cell(overviewRows()[3], 1):find(star, 1, true))
    rowMenu("High", "Pin to top").fn()
    eq(overviewNames(), "Aldric, Low, High, Far", "in the order they were pinned")
    eq(rowMenu("High", "Pin to top"), nil, "already pinned")

    -- Moving a pinned character among the pinned ones.
    eq(rowMenu("High", "Move down").enabled, false, "already the last")
    eq(rowMenu("Low", "Move up").enabled, false, "already the first")
    rowMenu("High", "Move up").fn()
    eq(overviewNames(), "Aldric, High, Low, Far")
    rowMenu("High", "Move down").fn()
    eq(overviewNames(), "Aldric, Low, High, Far")

    -- A chosen order sorts only the rest; you're sorted in with them.
    click("gold")
    eq(overviewNames(), "Low, High, Aldric, Far", "Low and High stay first, in pin order")
    click("gold")
    eq(overviewNames(), "Low, High, Far, Aldric")
    eq(table.concat(ns.OverviewOrder(), ", "), "Low, High, Far, Aldric", "the other lists follow")
    click("level")

    -- Unpinning; the last one leaves nothing saved.
    rowMenu("Low", "Unpin").fn()
    eq(overviewNames(), "Aldric, High, Far, Low")
    rowMenu("High", "Unpin").fn()
    eq(overviewNames(), "Aldric, Far, High, Low")
    eq(AltsForeverDB.pinned, nil)
end)

test("pins are kept between sessions; forgetting a character unpins them; /af pin", function()
    local _, ns = sortStart()
    SlashCmdList.ALTSFOREVER("pin Low")
    SlashCmdList.ALTSFOREVER("pin Far")
    assert(table.concat(wow.printed, " "):find("Low is pinned to the top of the overview.", 1, true))
    eq(overviewNames(), "Aldric, Low, Far, High")
    local saved = AltsForeverDB
    _, ns = sortStart(saved)
    eq(overviewNames(), "Aldric, Low, Far, High")
    ns.ForgetCharacter("Low")
    eq(#AltsForeverDB.pinned, 1); eq(AltsForeverDB.pinned[1], "Far")
    SlashCmdList.ALTSFOREVER("pin Far")
    assert(table.concat(wow.printed, " "):find("Far is no longer pinned.", 1, true))
    eq(AltsForeverDB.pinned, nil)
    SlashCmdList.ALTSFOREVER("pin Nobody")
    assert(table.concat(wow.printed, " "):find("/af pin and a character's name", 1, true))
    -- You can be pinned too: it shows once another order sorts you in.
    SlashCmdList.ALTSFOREVER("pin Aldric")
    eq(overviewNames(), "Aldric, Far, High")
    local b = AltsForeverFrame.sorts.name
    b.scripts.OnClick(b); b.scripts.OnClick(b)
    eq(overviewNames(), "Aldric, High, Far", "pinned first, the rest Z to A")
end)

test("a damaged pin list is ignored: unknown names, repeats and junk", function()
    local saved = overviewAlts()
    saved.pinned = { "Gone", 7, "Low", "Low", false, "Far" }
    local _, ns = sortStart(saved)
    eq(overviewNames(), "Aldric, Low, Far, High")
    ns.SetPinned("High", true)
    eq(table.concat(AltsForeverDB.pinned, ", "), "Low, Far, High", "tidied on the next change")
    saved = overviewAlts()
    saved.pinned = "Low"
    sortStart(saved)
    eq(overviewNames(), "Aldric, Far, High, Low")
    eq(AltsForeverDB.pinned, nil)
end)

---------------------------------------------------------------------------
-- Hiding overview columns

-- The entry with this text in the menu last opened, looking inside submenus too.
function menuEntry(text, items)
    for _, item in ipairs(items or wow.menu.items) do
        if item.text == text then return item end
        local found = menuEntry(text, item.items)
        if found then return found end
    end
end

-- Right-clicks the overview's column titles and returns the menu entry with this text.
function columnsMenu(text)
    local header = AltsForeverFrame.header
    header.scripts.OnMouseUp(header, "RightButton")
    return menuEntry(text)
end

test("columns can be hidden from the titles' right-click menu, and brought back", function()
    sortStart()
    local f = AltsForeverFrame
    local full = f.width
    local row = overviewRows()[2]
    local goldX, profX = row.cells[6].point[4], row.cells[7].point[4]
    eq(columnsMenu("Character"), nil, "the names can't be hidden")
    eq(columnsMenu("Show all columns").enabled, false, "nothing hidden yet")
    local gold = columnsMenu("Gold")
    eq(gold.kind, "checkbox"); eq(gold.isSelected(), true)
    gold.setSelected()
    eq(gold.isSelected(), false)
    eq(AltsForeverDB.hiddenColumns.gold, true)
    eq(row.cells[6].shown, false, "the cell")
    eq(f.titles[6].shown, false, "its title")
    eq(f.sorts.gold.shown, false, "and the button on it")
    eq(row.cells[7].point[4], profX - 120, "the columns after it close up")
    eq(row.cells[5].point[4], goldX - 60, "those before stay")
    eq(f.width, full - 120, "and the window is that much narrower")

    -- Professions is four cells; Level takes its percentage with it.
    columnsMenu("Professions").setSelected()
    for i = 7, 10 do eq(row.cells[i].shown, false, "profession cell " .. i) end
    columnsMenu("Level").setSelected()
    eq(row.cells[2].shown, false); eq(row.pct.shown, false)
    eq(f.sortArrow.shown, false, "sorted by a hidden column: no arrow")

    -- Any way back: the entry at the top of the list, or ticking the column again.
    local all = columnsMenu("Show all columns")
    eq(all.enabled, true)
    columnsMenu("Level").setSelected()
    eq(row.cells[2].shown, true); eq(row.pct.shown, true); eq(f.sortArrow.shown, true)
    all.fn()
    eq(AltsForeverDB.hiddenColumns, nil)
    eq(f.width, full)
    eq(row.cells[6].shown, true); eq(row.cells[7].point[4], profX)
    eq(f.sorts.gold.shown, true)

    -- A title that sorts opens the same menu on a right-click, and doesn't sort.
    local b = f.sorts.gold
    b.scripts.OnClick(b, "RightButton")
    assert(menuEntry("Show all columns"), "the columns menu")
    eq(AltsForeverDB.overviewSort, nil)
    b.scripts.OnEnter(b)
    local text = {}
    for _, l in ipairs(GameTooltip.lines) do text[#text + 1] = table.concat(l, " = ") end
    assert(table.concat(text, " "):find("Right-click to choose which columns are shown.", 1, true))
end)

test("hidden columns are kept between sessions; the window never gets too narrow", function()
    sortStart()
    for _, name in ipairs({ "Level", "Rested", "Well Rested", "Legacy", "Gold", "Professions", "Mail", "Lockouts", "Zone", "Played", "Last seen" }) do
        columnsMenu(name).setSelected()
    end
    local f = AltsForeverFrame
    eq(f.width, 560, "room for the title bar's buttons and the footer")
    local saved = AltsForeverDB
    local _, ns = sortStart(saved)
    f = AltsForeverFrame
    eq(f.width, 560)
    for _, row in ipairs(overviewRows()) do
        eq(row.cells[1].shown, true)
        for i = 2, 15 do eq(row.cells[i].shown, false, "cell " .. i) end
    end
    eq(ns.ColumnShown("gold"), false)
    -- The cog menu has the list too; the minimap's menu doesn't.
    ns.ShowOptionsMenu(f.cog, true)
    local columns = wow.menuItem("Columns")
    eq(columns.items[1].text, "Show all columns")
    eq(#columns.items, 12, "the eleven columns and Show all")
    ns.ShowOptionsMenu(UIParent)
    eq(wow.menuItem("Columns"), nil)
    -- /af columns: one column, or all of them back.
    SlashCmdList.ALTSFOREVER("columns Gold")
    eq(ns.ColumnShown("gold"), true)
    assert(table.concat(wow.printed, " "):find("The Gold column is shown.", 1, true))
    SlashCmdList.ALTSFOREVER("columns gold")
    assert(table.concat(wow.printed, " "):find("The Gold column is hidden. /af columns brings every column back.", 1, true))
    SlashCmdList.ALTSFOREVER("columns nothing")
    assert(table.concat(wow.printed, " "):find("/af columns shows every overview column again", 1, true))
    eq(ns.ColumnShown("gold"), false)
    SlashCmdList.ALTSFOREVER("columns")
    eq(AltsForeverDB.hiddenColumns, nil)
    for i = 1, 15 do eq(overviewRows()[1].cells[i].shown, true, "cell " .. i) end
end)

test("damaged hidden columns hide nothing; the Character column can't be hidden", function()
    for _, bad in ipairs({ "gold", { gold = "yes", name = true, [3] = true } }) do
        local saved = overviewAlts()
        saved.hiddenColumns = bad
        local _, ns = sortStart(saved)
        for i = 1, 15 do eq(overviewRows()[1].cells[i].shown, true, "cell " .. i) end
        ns.SetColumnShown("name", false)
        ns.SetColumnShown("character", false)
        eq(overviewRows()[1].cells[1].shown, true)
    end
end)

-- Gives a window the edges its anchor implies (the fake lays nothing out): `w` by `h`
-- against the window it's anchored to, which must have edges already.
function layOut(f, w, h)
    local p, rel, relPoint, dx, dy = unpack(f.point)
    local r = rel.rect
    local x = (relPoint:find("LEFT") and r[1] or r[2]) + (dx or 0)
    local y = (relPoint:find("TOP") and r[3] or r[4]) + (dy or 0)
    local left = p:find("LEFT") and x or x - w
    local top = p:find("TOP") and y or y + h
    f.rect = { left, left + w, top, top - h }
end

-- Whether following anchors from a window ever comes back to it.
function anchorLoop(f)
    local seen, at = {}, f
    while type(at) == "table" and at.point do
        if seen[at] then return true end
        seen[at] = true
        at = at.point[2]
    end
    return false
end

test("opening the bags from the search never anchors the two to each other", function()
    local ns = wow.load(FILES)
    wow.setBag(0, 16, { { 2589, 5 } })
    wow.login(nil)
    SlashCmdList.ALTSFOREVER("")
    UIParent.width, UIParent.height = 1920, 1080
    local ov = AltsForeverFrame
    -- The overview near the top: the search goes below it, where the bags would go too,
    -- and there is room for the bags beside the search.
    ov.rect = { 100, 1100, 1000, 800 }
    ns.ToggleSearch()
    local search = AltsForeverSearchFrame
    eq(search.point[2], ov, "the search is beside the overview")
    layOut(search, 400, 300)
    -- The bags window opens (as picking a search result does), then the search moves
    -- beside it.
    ns.ShowBags(ns.charKey, "bags")
    local bags = AltsForeverBagsFrame
    assert(bags.point[2] ~= search, "the bags window isn't placed against the search")
    eq(placed(bags), "TOPLEFT overview TOPRIGHT 4 0", "but clear of it: right of the overview")
    ns.ToggleSearch(); ns.ToggleSearch()
    eq(search.point[2], bags, "the search follows the bags window")
    eq(anchorLoop(bags), false); eq(anchorLoop(search), false)
end)

test("a panel is never placed against one that follows it", function()
    wow.load(FILES)
    wow.login(nil)
    SlashCmdList.ALTSFOREVER("")
    UIParent.width, UIParent.height = 1920, 1080
    local ov = AltsForeverFrame
    ov.rect = { 100, 1100, 1000, 600 }
    SlashCmdList.ALTSFOREVER("lockouts")
    local lock = AltsForeverLockoutsFrame
    layOut(lock, 300, 200)
    SlashCmdList.ALTSFOREVER("rep")
    local rep = AltsForeverRepFrame
    -- Reputation beside Lockouts, anchored to it (as it opens when there's room).
    rep.width, rep.height = 300, 200
    rep.point = { "TOPLEFT", lock, "TOPRIGHT", 4, 0 }
    layOut(rep, 300, 200)
    -- Lockouts closed and opened again with no room left under the overview: the only
    -- other panel is Reputation, which is anchored to it.
    SlashCmdList.ALTSFOREVER("lockouts")
    ov.rect = { 100, 1100, 700, 50 }
    rep.rect = { 1200, 1500, 500, 300 } -- with room under it
    SlashCmdList.ALTSFOREVER("lockouts")
    assert(lock.point[2] ~= rep, "not against the panel that follows it")
    eq(lock.point[2], ov, "above the overview")
    eq(anchorLoop(lock), false); eq(anchorLoop(rep), false)
end)

test("resetting window positions also moves closed windows, and the bags without the overview", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    -- Export and Sync: moved, closed, reset, opened again.
    for _, name in ipairs({ "Export", "Sync" }) do
        ns["Toggle" .. name]()
        local f = _G["AltsForever" .. name .. "Frame"]
        drop(f, 1300, 1700, 500, 100)
        eq(placed(f), "CENTER nil nil nil nil", "the fake doesn't move it: it was dropped there")
        f.point = { "TOPLEFT", UIParent, "BOTTOMLEFT", 1300, 500 } -- where the drag left it
        ns["Toggle" .. name]()
        SlashCmdList.ALTSFOREVER("resetwindows")
        ns["Toggle" .. name]()
        eq(placed(f), "CENTER nil nil nil nil", name .. " opens in the middle again")
        ns["Toggle" .. name]()
    end
    -- The bags window, open, with the overview closed.
    ns.ShowBags(ns.charKey, "bags")
    local bags = AltsForeverBagsFrame
    drop(bags, 1300, 1700, 500, 100)
    bags.point = { "TOPLEFT", UIParent, "BOTTOMLEFT", 1300, 500 }
    SlashCmdList.ALTSFOREVER("resetwindows")
    eq(placed(bags), "CENTER nil nil nil nil", "back to the middle at once")
    eq(AltsForeverDB.windows, nil)
    -- The search, closed.
    ns.ShowBags(ns.charKey, "bags")
    ns.ToggleSearch()
    local search = AltsForeverSearchFrame
    drop(search, 1300, 1700, 500, 100)
    search.point = { "TOPLEFT", UIParent, "BOTTOMLEFT", 1300, 500 }
    ns.ToggleSearch()
    SlashCmdList.ALTSFOREVER("resetwindows")
    ns.ToggleSearch()
    eq(placed(search), "CENTER screen CENTER 0 120")
end)

test("a window at a smaller scale than the overview docks by where it is on screen", function()
    wow.load(FILES)
    wow.login(nil)
    SlashCmdList.ALTSFOREVER("")
    local ov = AltsForeverFrame
    ov.rect = { 100, 1100, 900, 700 }
    SlashCmdList.ALTSFOREVER("lockouts")
    local lock = AltsForeverLockoutsFrame
    -- Half size (as when it wouldn't fit on screen): its own edges read twice as far out.
    lock.scale = 0.5
    -- On screen: just under the overview, 300 along it.
    drop(lock, 800, 1400, 1380, 1000)
    eq(AltsForeverDB.windows.lockouts.dock, "below")
    eq(AltsForeverDB.windows.lockouts.off, 300, "saved in the screen's units")
    eq(placed(lock), "TOPLEFT overview BOTTOMLEFT 600 -4", "anchored in its own")
    -- The same numbers at the overview's scale would be far from it: not docked.
    lock.scale = 1
    drop(lock, 800, 1400, 1380, 1000)
    eq(AltsForeverDB.windows.lockouts.dock, nil)
    -- On screen far from the overview, though its own numbers look docked: free.
    lock.scale = 0.5
    drop(lock, 108, 408, 690, 500)
    eq(AltsForeverDB.windows.lockouts.dock, nil)
    eq(AltsForeverDB.windows.lockouts.x, 54)
    -- Down the side, and opened again at that scale.
    drop(lock, 2208, 2808, 1600, 1200)
    eq(AltsForeverDB.windows.lockouts.dock, "right"); eq(AltsForeverDB.windows.lockouts.off, 100)
    eq(placed(lock), "TOPLEFT overview TOPRIGHT 4 -200")
end)
