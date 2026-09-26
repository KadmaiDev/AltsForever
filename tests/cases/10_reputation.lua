-- Tests: reputation. Loaded by tests/run.lua, which provides test, eq, wow, FILES and the
-- other shared helpers; helpers defined here are shared with the other files too.
---------------------------------------------------------------------------
-- Reputation across characters
function repWindow()
    wow.factions = {
        { 1, "Horde", 0, true },
        { 530, "Darkspear Trolls", 2150 },
        { 76, "Orgrimmar", 9500 },
        { 2, "Other", 0, true },
        { 87, "Bloodsail Buccaneers", -4000 },
    }
end

test("reputation is recorded shortly after login, headers skipped", function()
    local ns = wow.load(FILES)
    repWindow()
    wow.login(nil)
    eq(ns.char.reps, nil, "not during the login rush")
    for _, fn in ipairs(wow.timers) do fn() end
    eq(ns.char.reps[530], 2150); eq(ns.char.reps[76], 9500); eq(ns.char.reps[87], -4000)
    eq(ns.char.reps[1], nil, "headers aren't factions")
    eq(AltsForeverDB.factions[530], "Darkspear Trolls")
end)

test("reputation changes are batched: one scan per burst, 10 seconds later", function()
    local ns = wow.load(FILES)
    repWindow()
    wow.login(nil)
    runTimers()
    wow.timers = {}
    wow.factions[2][3] = 2200
    for _ = 1, 20 do wow.fire("UPDATE_FACTION") end -- a kill streak
    eq(#wow.timers, 1, "one scan scheduled for the whole burst")
    eq(ns.char.reps[530], 2150, "not yet")
    runTimers()
    eq(ns.char.reps[530], 2200)
    wow.fire("UPDATE_FACTION")
    eq(#wow.timers, 1, "the next burst schedules again")
end)

test("factions under a collapsed header stay current, without touching the player's window", function()
    local ns = wow.load(FILES)
    repWindow()
    wow.login({ v = 2, chars = { ["Aldric"] = alt("Aldric", "MAGE", { reps = { [69] = 3000, [530] = 100 } }) } })
    wow.hiddenFactions = { { 69, "Darnassus", 3500 } } -- its header is collapsed now
    runTimers()
    eq(ns.char.reps[69], 3500, "re-read by ID")
    eq(ns.char.reps[530], 2150)
    eq(wow.expanded, nil, "headers are never expanded")
end)

test("standing levels and text", function()
    local ns = wow.load(FILES)
    eq((ns.Standing(2150)), 4); eq((ns.Standing(3000)), 5); eq((ns.Standing(-1)), 3); eq((ns.Standing(42999)), 8)
    eq(ns.StandingText(2150), "|cffffff00Neutral 71%|r")
    eq(ns.StandingText(12000), "|cff00ff88Honored 25%|r")
    eq(ns.StandingText(42500), "|cff00ffffExalted|r")
    eq(ns.StandingText(-42000), "|cffcc2222Hated 0%|r")
end)

test("reputation panel: factions down, characters across, you first", function()
    wow.load(FILES)
    repWindow()
    wow.login({ v = 2, factions = { [530] = "Darkspear Trolls", [76] = "Orgrimmar", [69] = "Darnassus" }, chars = {
        ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { level = 30, reps = { [530] = 9000, [69] = 3000 } }),
    } })
    runTimers()
    SlashCmdList.ALTSFOREVER("")
    AltsForeverFrame.repButton.scripts.OnClick(AltsForeverFrame.repButton)
    local f = AltsForeverRepFrame
    eq(f:IsShown(), true)
    -- Rows are the panel's frames with a faction; read their text.
    local lines = {}
    for _, row in ipairs(wow.frames) do
        if row.faction then
            local t = { row.name.text }
            for j, cell in ipairs(row.cells) do t[j + 1] = cell.text end
            lines[#lines + 1] = table.concat(t, " | ")
        end
    end
    table.sort(lines)
    eq(lines[1], "Bloodsail Buccaneers | |cffff0000Hostile 66%|r | " .. G .. "-|r")
    eq(lines[2], "Darkspear Trolls | |cffffff00Neutral 71%|r | |cff00ff88Honored 0%|r", "you, then Tarn")
    eq(lines[3], "Darnassus | " .. G .. "-|r | |cff00ff00Friendly 0%|r")
    eq(lines[4], "Orgrimmar | |cff00ff88Honored 4%|r | " .. G .. "-|r")
    AltsForeverFrame:Hide()
    eq(f:IsShown(), false, "closing the overview closes it")
end)
