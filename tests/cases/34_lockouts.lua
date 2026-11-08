-- Tests: raid and dungeon lockouts (Lockouts.lua). Loaded by tests/run.lua.

test("saves are asked for after login and after a boss dies, and read when the game answers", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.login(overviewAlts())
    eq(ns.char.saves, nil, "not read yet")
    runTimers()
    eq(wow.raidInfoRequests, 1, "asked a few seconds after login")
    wow.saves = {
        { "Molten Core", 3 * DAY, true, false, "40 Player", 10, 3 },
        { "Onyxia's Lair", 5 * HOUR, true, false, "40 Player", 1, 1 },
        { "Zul'Gurub", 0, true, false, "20 Player", 10, 10 }, -- expired: listed only to extend
        { "Blackwing Lair", 2 * DAY, false, true, "40 Player", 8, 0 }, -- extended
    }
    wow.fire("UPDATE_INSTANCE_INFO")
    local c = ns.char
    eq(c.saves["Molten Core"], NOW + 3 * DAY)
    eq(c.saves["Onyxia's Lair"], NOW + 5 * HOUR)
    eq(c.saves["Zul'Gurub"], nil, "an expired save isn't kept")
    eq(c.saves["Blackwing Lair"], NOW + 2 * DAY, "an extended save is")
    eq(c.saveKills["Molten Core"], "3/10")
    eq(c.saveKills["Blackwing Lair"], "0/8")

    wow.fire("ENCOUNTER_END", 663, "Lucifron", 9, 40, 0)
    eq(wow.raidInfoRequests, 1, "a wipe saves nobody")
    wow.fire("ENCOUNTER_END", 663, "Lucifron", 9, 40, 1)
    eq(wow.raidInfoRequests, 2, "a kill: ask again")

    -- Read again: the same tables, refilled.
    local saves = c.saves
    wow.saves = {}
    wow.fire("UPDATE_INSTANCE_INFO")
    eq(c.saves, saves)
    eq(next(c.saves), nil, "saved nowhere now")
    eq(c.saveKills, nil)
end)

test("two saves to one place are told apart by difficulty", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.login(nil)
    wow.saves = { { "Ragefire Chasm", DAY, true, false, "Normal" }, { "Ragefire Chasm", 2 * DAY, true, false, "Heroic" } }
    wow.fire("UPDATE_INSTANCE_INFO")
    eq(ns.char.saves["Ragefire Chasm"], NOW + DAY)
    eq(ns.char.saves["Ragefire Chasm (Heroic)"], NOW + 2 * DAY)
end)

test("a secret answer from the game is left alone", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.login(nil)
    wow.saves = { { wow.SECRET, DAY, true, false, "Normal" }, { "Molten Core", wow.SECRET, true, false, "40 Player" } }
    wow.fire("UPDATE_INSTANCE_INFO")
    eq(next(ns.char.saves), nil)
end)

local function lockoutAlts()
    local saved = overviewAlts()
    saved.chars["High"].saves = { ["Molten Core"] = NOW + 3 * DAY + HOUR, ["Onyxia's Lair"] = NOW + 5 * HOUR,
        ["Zul'Gurub"] = NOW - HOUR }
    saved.chars["High"].saveKills = { ["Molten Core"] = "3/10", ["Zul'Gurub"] = "4/10" }
    saved.chars["Low"].saves = {}
    return saved
end

test("the overview counts each character's saves; the row tooltip lists them, soonest reset first", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.login(lockoutAlts())
    SlashCmdList.ALTSFOREVER("")
    local rows = overviewRows()
    eq(cell(rows[1], 12), G .. "?|r", "you: never read")
    eq(cell(rows[3], 1), "[PRIEST]High"); eq(cell(rows[3], 12), "2")
    eq(cell(rows[4], 1), "[ROGUE]Low"); eq(cell(rows[4], 12), "", "saved nowhere")
    eq(ns.db.chars["High"].saves["Zul'Gurub"], nil, "a save past its reset is forgotten when the overview opens")
    eq(ns.db.chars["High"].saveKills["Zul'Gurub"], nil)
    rows[3].scripts.OnEnter(rows[3])
    local text = textOf(GameTooltip.lines)
    assert(text:find("Lockouts\nOnyxia's Lair = 5h\nMolten Core = 3/10 · 3d 1h", 1, true), text)
end)

test("/af lockouts lists every character with saves", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.login(lockoutAlts())
    SlashCmdList.ALTSFOREVER("lockouts")
    local text = table.concat(wow.printed, "\n")
    assert(text:find("[PRIEST]High: Onyxia's Lair (5h), Molten Core (3/10 · 3d 1h)", 1, true), text)
    assert(not text:find("Low", 1, true), text)

    wow.load(FILES)
    wow.login(nil)
    SlashCmdList.ALTSFOREVER("lockouts")
    assert(table.concat(wow.printed, "\n"):find("No lockouts on record", 1, true))
end)

test("damaged saves are repaired at load", function()
    local ns = wow.load(FILES)
    local saved = overviewAlts()
    saved.chars["High"].saves = { ["Molten Core"] = "soon", [3] = NOW, ["Onyxia's Lair"] = NOW + DAY }
    saved.chars["High"].saveKills = { ["Molten Core"] = 3 }
    saved.chars["Low"].saves = "broken"
    wow.login(saved)
    local high = ns.db.chars["High"]
    eq(high.saves["Molten Core"], nil); eq(high.saves[3], nil); eq(high.saves["Onyxia's Lair"], NOW + DAY)
    eq(high.saveKills["Molten Core"], nil)
    eq(ns.db.chars["Low"].saves, nil)
end)
