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
