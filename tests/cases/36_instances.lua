-- Tests: the hourly instance limit, counted per game account (Lockouts.lua). Loaded by
-- tests/run.lua.

local RFC = { name = "Ragefire Chasm", kind = "party", map = 389 }

-- A loading screen: into `where` (nil = outside), as a login or reload if asked.
local function enter(where, isLogin, isReload)
    wow.instance = where
    wow.fire("PLAYER_ENTERING_WORLD", isLogin or false, isReload or false)
end

-- A spell of yours finishing in copy `zone` of Ragefire Chasm.
local function cast(zone, unit)
    wow.fire("UNIT_SPELLCAST_SUCCEEDED", unit or "player", ("Cast-3-7069-389-%d-433-0000A1B2C3"):format(zone), 433)
end

local function start(saved)
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.login(saved)
    enter(nil, true)
    return ns
end

-- A logout and login again (or /reload), into `where`, at `later` if given: the addon starts
-- from its saved data.
local function relog(ns, where, login, later)
    local db = ns.db
    wow.fire("PLAYER_LOGOUT")
    local now = later or wow.now
    ns = wow.load(FILES)
    wow.now = now
    wow.login(db)
    enter(where, login, not login)
    return ns
end

-- Bob Smith, a trusted character on another account, swaps with us and wants Aldric.
local function bobWantsYou(ns)
    ns.db.syncWith = { ["Bob Smith"] = true }
    syncFrom(ns, "Bob Smith", { k = "hello", v = 1, have = {} })
    syncPump()
    syncFrom(ns, "Bob Smith", { k = "want", keys = { "Aldric" } })
    syncPump()
end

local function count(ns)
    return ns.InstanceCounts(wow.now)[1].n
end

test("entering a dungeon counts for this account until an hour after you leave", function()
    local ns = start(nil)
    assert(type(ns.db.account) == "string" and #ns.db.account >= 8, tostring(ns.db.account))
    eq(ns.char.account, ns.db.account, "you're stamped with this account")
    eq(ns.InstanceText(NOW), nil, "none entered: nothing to show")

    wow.now = NOW + 60
    enter(RFC)
    local run = ns.char.runs[1]
    eq(run.at, NOW + 60); eq(run.map, 389); eq(run.name, "Ragefire Chasm"); eq(run.left, nil)
    eq(ns.InstanceText(wow.now), "Instances this hour: 1/10")
    enter(RFC)
    eq(#ns.char.runs, 1, "a loading screen inside it is still the same")

    wow.now = NOW + 2400
    enter(nil)
    eq(run.left, NOW + 2400)
    wow.now = NOW + 2400 + 3599
    eq(count(ns), 1, "still counting just under an hour after leaving")
    wow.now = NOW + 2400 + 3600
    eq(count(ns), 0)
    enter(nil)
    eq(ns.char.runs, nil, "forgotten at the next loading screen")

    enter({ name = "Warsong Gulch", kind = "pvp", map = 489 })
    eq(ns.char.runs, nil, "a battleground doesn't count")
end)

test("a corpse run, a reload or walking back into the same copy isn't a new instance", function()
    local ns = start(nil)
    enter(RFC)
    cast(53)
    eq(ns.char.runs[1].zone, 53, "the copy, from your first cast")

    -- Died, released, ran back.
    wow.now = NOW + 600
    wow.dead = true
    enter(nil)
    enter(RFC)
    wow.dead = nil
    eq(#ns.char.runs, 1); eq(ns.char.runs[1].left, nil, "reopened")

    ns = relog(ns, RFC)
    eq(#ns.char.runs, 1, "a /reload inside"); eq(ns.char.runs[1].left, nil)

    -- Out to the entrance and back in: new until a cast shows the copy.
    wow.now = NOW + 900
    enter(nil)
    enter(RFC)
    eq(count(ns), 2)
    cast(53)
    eq(#ns.char.runs, 2, "each visit kept"); eq(ns.char.runs[1].left, NOW + 900); eq(ns.char.runs[2].left, nil)
    eq(count(ns), 1, "the same copy counts once")
    eq(ns.InstanceCounts(wow.now)[1].free, wow.now + HOUR, "for as long as the later visit")

    -- Reset, then in again: another copy.
    wow.now = NOW + 1200
    enter(nil)
    enter(RFC)
    cast(54)
    eq(#ns.char.runs, 3)
    eq(ns.char.runs[2].left, NOW + 1200)
    cast(99)
    eq(ns.char.runs[3].zone, 54, "only the first cast is read")
    eq(count(ns), 2, "a new copy is a new instance")
    eq(ns.InstanceCounts(wow.now)[1].free, NOW + 1200 + HOUR)
end)

test("logging in inside a copy that was reset meanwhile counts it as new", function()
    local ns = start(nil)
    enter(RFC)
    cast(53)
    wow.now = NOW + 600
    ns = relog(ns, nil, true) -- logged out inside, back in later: the game moved you out
    eq(ns.char.runs[1].left, NOW + 600, "left when you logged out")

    ns = start(nil)
    enter(RFC)
    cast(53)
    wow.now = NOW + 600
    ns = relog(ns, RFC, true, NOW + 1800)
    eq(#ns.char.runs, 1, "the same instance until the copy is known"); eq(ns.char.runs[1].left, nil)
    cast(77)
    eq(#ns.char.runs, 2)
    eq(ns.char.runs[1].left, NOW + 600, "the old one keeps the time you left it")
    eq(ns.char.runs[2].at, NOW + 1800); eq(ns.char.runs[2].zone, 77)

    ns = start(nil)
    enter(RFC)
    cast(53)
    wow.now = NOW + 1800
    ns = relog(ns, RFC, true)
    cast(53)
    eq(#ns.char.runs, 1, "the same copy after all"); eq(ns.char.runs[1].left, nil)
end)

test("a copy another of your characters was in this hour counts once, while you're still tracked", function()
    -- Low was there until 50 minutes ago; you go in now.
    local saved = overviewAlts()
    saved.account = "mine"
    saved.chars["Low"].account = "mine"
    saved.chars["Low"].runs = { { at = NOW - 4000, left = NOW - 3000, map = 389, zone = 53 } }
    local ns = start(saved)
    enter(RFC)
    eq(count(ns), 2, "until the copy is known")
    cast(53)
    eq(count(ns), 1)
    eq(#ns.char.runs, 1, "your visit is kept"); eq(ns.db.chars["Low"].runs[1].left, NOW - 3000, "theirs as it was")
    SlashCmdList.ALTSFOREVER("lockouts")
    local window = lockoutWindow()
    assert(window:find("Aldric's account | 1/10\nRagefire Chasm | [MAGE]Aldric | inside now\nRaid lockouts", 1, true),
        "the copy listed once, by the visit that counts longest: " .. window)

    -- Past Low's hour, still inside: still counting.
    wow.now = NOW + 1200
    eq(count(ns), 1)
    eq(ns.InstanceCounts(wow.now)[1].free, wow.now + HOUR)
    wow.now = NOW + 1500
    enter(nil)
    eq(ns.char.runs[1].left, NOW + 1500, "your leaving is recorded")
    wow.now = NOW + 1500 + HOUR - 1
    eq(count(ns), 1)
    wow.now = NOW + 1500 + HOUR
    eq(count(ns), 0)
end)

test("another account in the same copy counts for that account, and yours for yours", function()
    local saved = overviewAlts()
    saved.account = "mine"
    saved.chars["High"].account = "other"
    saved.chars["High"].runs = { { at = NOW - 600, map = 389, zone = 53 } } -- grouped with you
    local ns = start(saved)
    enter(RFC)
    cast(53)
    eq(#ns.char.runs, 1)
    local mine, theirs = unpack(ns.InstanceCounts(wow.now))
    eq(mine.id, "mine"); eq(mine.n, 1)
    eq(theirs.id, "other"); eq(theirs.n, 1)

    -- Two hours on, still inside as of their last sync: still counting.
    wow.now = NOW + 2 * HOUR
    local run = ns.db.chars["High"].runs[1]
    run.last = NOW + 2 * HOUR - 300
    eq(ns.InstanceCounts(wow.now)[2].n, 1)
    eq(ns.InstanceCounts(wow.now)[2].free, NOW + 2 * HOUR - 300 + HOUR)
    ns.db.chars["High"].updated = NOW + 2 * HOUR
    run.last = NOW - 700
    eq(ns.InstanceCounts(wow.now)[2].n, 0, "an hour after they were last known inside, whatever else changed")
end)

test("a visit never closed ends when you were last known inside, however much happens after", function()
    local saved = { v = 2, chars = { ["Aldric"] = alt("Aldric", "MAGE", { updated = NOW - 3600,
        runs = { { at = NOW - 1800, map = 389, zone = 53 }, { at = NOW - 3000, last = NOW - 1200, map = 36 } } }) } }
    local ns = start(saved) -- logged in outdoors
    local runs = ns.char.runs -- oldest first
    eq(runs[2].left, NOW - 1800, "closed: never known inside after entering")
    eq(runs[1].left, NOW - 1200, "closed when last known inside")
    eq(count(ns), 2)
    -- Playing on: character updates and a sync don't move them.
    wow.now = NOW + 600
    wow.fire("PLAYER_XP_UPDATE", "player")
    bobWantsYou(ns)
    local sentRuns
    for _, msg in ipairs(syncSent(ns, "Bob Smith")) do
        if msg.k == "char" then sentRuns = msg.c.runs end
    end
    eq(sentRuns[2].left, NOW - 1800, "sent closed")
    wow.now = NOW - 1800 + HOUR
    eq(count(ns), 1)
    wow.now = NOW - 1200 + HOUR
    eq(count(ns), 0)
end)

test("sync sends the visit you're in as of now", function()
    local ns = start(nil)
    enter(RFC)
    cast(53)
    wow.now = NOW + 900
    wow.sent = {}
    bobWantsYou(ns)
    local sentChar
    for _, msg in ipairs(syncSent(ns, "Bob Smith")) do
        if msg.k == "char" then sentChar = msg.c end
    end
    assert(sentChar, "sent")
    eq(sentChar.account, ns.db.account)
    eq(sentChar.runs[1].last, NOW + 900); eq(sentChar.runs[1].left, nil); eq(sentChar.runs[1].zone, 53)
end)

test("secret answers from the game are never counted on", function()
    local ns = start(nil)
    enter({ name = "Ragefire Chasm", kind = "party", map = wow.SECRET })
    eq(ns.char.runs, nil, "no instance ID: not counted")
    enter(nil)
    enter(RFC)
    wow.fire("UNIT_SPELLCAST_SUCCEEDED", "player", wow.SECRET, 433)
    cast(60, "party1")
    eq(ns.char.runs[1].zone, nil, "a secret cast, and someone else's, are skipped")
    cast(53)
    eq(ns.char.runs[1].zone, 53)
    enter(nil)
    wow.dead = wow.SECRET
    enter(RFC)
    eq(#ns.char.runs, 2, "a secret answer to dead or alive reads as alive")
end)

test("each account's count shows in the overview and /af lockouts, by its most played character", function()
    local saved = overviewAlts()
    saved.chars["High"].account, saved.chars["High"].played = "other", 500
    saved.chars["Far"].account, saved.chars["Far"].played = "other", 9000
    local runs = {}
    -- Entered in turn, left in the other order: the last stops counting at NOW + 760, 13 minutes.
    for i = 1, 10 do runs[i] = { at = NOW - 4000 + i * 60, left = NOW - 2240 - i * 60, map = 389 } end
    saved.chars["Far"].runs = runs
    local ns = start(saved)
    enter(RFC)
    SlashCmdList.ALTSFOREVER("")
    local text = AltsForeverFrame.footer.text
    assert(text:find("Instances this hour: Aldric 1/10, Far |cffff800010/10 (13 min)|r     Total played:", 1, true), text)

    SlashCmdList.ALTSFOREVER("lockouts")
    local window = lockoutWindow()
    local far = {}
    for i = 1, 10 do far[i] = G .. "?|r | [MAGE]Far | frees in " .. (12 + i) .. " min" end
    eq(window, table.concat({
        "Instances this hour (10 per game account)",
        "Aldric's account | 1/10",
        "Ragefire Chasm | [MAGE]Aldric | inside now",
        "Far's account | |cffff800010/10|r",
        table.concat(far, "\n"),
        "Raid lockouts",
        G .. "No lockouts on record. They're read each time you log in on a character.|r",
    }, "\n"))

    -- A visit's tooltip: when it was entered and left.
    local row = AltsForeverLockoutsFrame.lines[5]
    row.scripts.OnEnter(row)
    eq(textOf(GameTooltip.lines), "?\nEntered " .. os.date("%H:%M", NOW - 3400) .. "\nLeft " .. os.date("%H:%M", NOW - 2840))
    row = AltsForeverLockoutsFrame.lines[3]
    row.scripts.OnEnter(row)
    eq(textOf(GameTooltip.lines), "Ragefire Chasm\nEntered " .. os.date("%H:%M", NOW) .. "\ninside now")

    -- Leaving while it's open updates it.
    wow.now = NOW + 60
    enter(nil)
    assert(lockoutWindow():find("Ragefire Chasm | [MAGE]Aldric | frees in 60 min", 1, true), lockoutWindow())

    eq(ns.InstanceText(NOW + 1400), "Instances this hour: Aldric 1/10", "an account with none counting is left out")
end)

test("the open Lockouts window counts down and drops visits as they run out, with no event", function()
    local saved = overviewAlts()
    saved.chars["Far"].account, saved.chars["Far"].played = "other", 9000
    -- Two visits: the first frees at NOW + 760 (13 min), the other at NOW + 1900.
    saved.chars["Far"].runs = { { at = NOW - 3000, left = NOW - 2840, map = 389 }, { at = NOW - 2000, left = NOW - 1700, map = 389 } }
    local ns = start(saved)
    SlashCmdList.ALTSFOREVER("lockouts")
    local function nextRefresh()
        local fn = wow.timers[#wow.timers]
        wow.timers[#wow.timers] = nil
        return fn, wow.delays[fn]
    end
    assert(lockoutWindow():find("Far's account | 2/10\n" .. G .. "?|r | [MAGE]Far | frees in 13 min", 1, true), lockoutWindow())
    local fn, delay = nextRefresh()
    eq(delay, 40, "when 13 min turns to 12")
    wow.now = NOW + 40
    fn()
    assert(lockoutWindow():find("frees in 12 min", 1, true), lockoutWindow())
    fn, delay = nextRefresh()
    eq(delay, 60)
    wow.now = NOW + 760
    fn()
    assert(lockoutWindow():find("Far's account | 1/10\n" .. G .. "?|r | [MAGE]Far | frees in 19 min", 1, true), lockoutWindow())
    -- Closed: a refresh still pending does nothing, and none follows.
    fn = nextRefresh()
    AltsForeverLockoutsFrame:Hide()
    local before = #wow.timers
    fn()
    eq(#wow.timers, before)
end)

test("damaged instance records are repaired at load", function()
    local ns = wow.load(FILES)
    local saved = overviewAlts()
    saved.account = 7
    saved.chars["High"].runs = { { at = NOW, map = 389 }, "x", { at = "soon", map = 389 },
        { at = NOW - 60, map = 36, left = "later" }, { at = NOW - 120, map = 36, zone = 5, name = "The Deadmines" },
        { at = NOW - 30, map = 36, last = "later" } }
    saved.chars["Low"].runs = { { map = 389 } }
    saved.chars["Far"].account = {}
    wow.now = NOW
    wow.login(saved)
    local runs = ns.db.chars["High"].runs
    eq(#runs, 2); eq(runs[1].at, NOW - 120, "oldest first"); eq(runs[2].at, NOW)
    eq(ns.db.chars["Low"].runs, nil)
    eq(ns.db.chars["Far"].account, nil)
    assert(type(ns.db.account) == "string", "a new one made")
end)

test("the overview's Lockouts column: each account's instances this hour on its characters, then their raid saves", function()
    local saved = overviewAlts()
    saved.account = "mine"
    saved.chars["Low"].account = "mine"
    saved.chars["Low"].saves = { ["Molten Core"] = NOW + DAY }
    saved.chars["High"].account, saved.chars["High"].saves = "other", {}
    saved.chars["Far"].saves = {} -- saved nowhere, but whose account it is isn't known
    local ns = start(saved)
    enter(RFC)
    cast(53)
    SlashCmdList.ALTSFOREVER("")
    local function row(name)
        for _, r in ipairs(overviewRows()) do
            if cell(r, 1):find(name, 1, true) then return r end
        end
    end
    eq(cell(row("Aldric"), 12), "1/10", "you: your account's count, though your saves aren't read yet")
    eq(cell(row("Low"), 12), "1/10  " .. LOCK_KEY .. "1", "the same count on the account's other characters, then their saves")
    eq(cell(row("High"), 12), "", "another account with none this hour, saved nowhere")
    eq(cell(row("Far"), 12), G .. "?|r", "account unknown: never shown as free")

    -- The other account reaches the limit: orange on its characters.
    local runs = {}
    for i = 1, 10 do runs[i] = { at = NOW - 1200, left = NOW - 600, map = 389, name = "Ragefire Chasm" } end
    ns.db.chars["High"].runs = runs
    ns.RefreshOverview()
    eq(cell(row("High"), 12), "|cffff800010/10|r")
    eq(cell(row("Low"), 12), "1/10  " .. LOCK_KEY .. "1", "yours unchanged")

    -- The row tooltip lists the account's visits, then the character's saves.
    local r = row("Low")
    r.scripts.OnEnter(r)
    local text = textOf(GameTooltip.lines)
    assert(text:find("Instances this hour: 1/10\nRagefire Chasm = Aldric · inside now\n \nLockouts\nMolten Core = ", 1, true), text)
    r = row("High")
    r.scripts.OnEnter(r)
    text = textOf(GameTooltip.lines)
    assert(text:find("Instances this hour: |cffff800010/10 (50 min)|r\nRagefire Chasm = High · frees in 50 min", 1, true), text)
    assert(not text:find("Lockouts", 1, true), text)
    r = row("Far")
    r.scripts.OnEnter(r)
    assert(not textOf(GameTooltip.lines):find("Instances this hour", 1, true))
end)
