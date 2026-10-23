-- Tests: the move from the beta to the live game (Core.lua ns.BetaRealm / ns.SetAsideBeta,
-- Options.lua ns.CheckBeta / ns.ForgetBeta). Loaded by tests/run.lua.

-- A save from the beta: you (Aldric) and Tarn on its Normal realm, Rook on its PvP realm,
-- Old not logged in since realms were recorded; gold history for two beta groups.
function betaSave()
    return { v = 2, goldGroup = "ClassicBetaPvE2|Alliance", goldDays = { [100] = 5000 },
        goldDaysBy = { ["ClassicBetaPvP|Horde"] = { [100] = 70 } },
        collapsedGroups = { ["ClassicBetaPvP|Horde"] = true },
        chars = {
            ["Aldric"] = alt("Aldric", "MAGE", { realm = "ClassicBetaPvE2", faction = "Alliance",
                bags = { [2589] = 20 }, bank = { [2318] = 5 }, money = 5000 }),
            ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { realm = "ClassicBetaPvE2", faction = "Alliance", money = 300 }),
            ["Rook Vale"] = alt("Rook Vale", "ROGUE", { realm = "ClassicBetaPvP", faction = "Horde", money = 70 }),
            ["Old"] = alt("Old", "WARRIOR", { bank = { [1] = 1 } }),
        } }
end

local function betaPopups()
    return wow.popup and wow.popup.which == "ALTSFOREVER_BETA" and wow.popup or nil
end

test("during the beta nothing changes: no question, nobody set aside", function()
    local ns = wow.load(FILES)
    wow.player.realm = "ClassicBetaPvE2"
    wow.popup = nil
    wow.login(betaSave())
    runTimers()
    eq(betaPopups(), nil)
    eq(ns.char.bank[2318], 5, "your saved bank is still yours")
    eq(AltsForeverDB.chars["Aldric (beta)"], nil)
    eq(AltsForeverDB.betaAsked, nil)
    SlashCmdList.ALTSFOREVER("forgetbeta")
    assert(wow.printed[#wow.printed]:find("on the beta", 1, true))
    eq(type(AltsForeverDB.chars["Tarn Moon"]), "table", "the command does nothing on the beta")
end)

test("first login on a live realm: your beta namesake is set aside, then you're asked once", function()
    local ns = wow.load(FILES)
    wow.popup = nil
    wow.login(betaSave())
    local chars = AltsForeverDB.chars
    eq(ns.char.realm, "Realm")
    eq(ns.char.bank, nil, "a new character: their bank isn't known yet")
    eq(ns.char.bags[2589], nil, "nor the beta's bags")
    eq(chars["Aldric (beta)"].bank[2318], 5, "the beta's Aldric is kept aside")
    eq(chars["Aldric (beta)"].name, "Aldric (beta)")
    eq(betaPopups(), nil, "asked a few seconds in")
    runTimers()
    local popup = betaPopups()
    eq(popup.text, "4", "Tarn, Rook, Old and the beta's Aldric")
    eq(type(chars["Tarn Moon"]), "table", "nothing goes until the player says so")
    StaticPopupDialogs.ALTSFOREVER_BETA.OnAccept()
    local left = {}
    for key in pairs(chars) do left[#left + 1] = key end
    eq(table.concat(left, ","), "Aldric")
    eq(AltsForeverDB.betaAsked, true)
    eq(AltsForeverDB.goldGroup, "Realm|Alliance", "this group's history is the main one now")
    eq(AltsForeverDB.goldDays[100], nil, "the beta's gold history is gone")
    eq(AltsForeverDB.goldDaysBy, nil)
    eq(AltsForeverDB.collapsedGroups, nil)
    assert(wow.printed[#wow.printed]:find("(4)", 1, true))
    -- Asked only once.
    wow.load(FILES)
    wow.popup = nil
    wow.login(AltsForeverDB)
    runTimers()
    eq(betaPopups(), nil)
end)

test("keeping the beta's characters: not asked again, and /af forgetbeta forgets them later", function()
    local ns = wow.load(FILES)
    wow.popup = nil
    wow.login(betaSave())
    runTimers()
    StaticPopupDialogs.ALTSFOREVER_BETA.OnCancel()
    eq(AltsForeverDB.betaAsked, true)
    eq(type(AltsForeverDB.chars["Tarn Moon"]), "table")
    assert(wow.printed[#wow.printed]:find("/af forgetbeta", 1, true))
    eq(ns.Elsewhere(AltsForeverDB.chars["Tarn Moon"]), true, "kept, they're out of reach like another ruleset")
    SlashCmdList.ALTSFOREVER("forgetbeta")
    eq(AltsForeverDB.chars["Tarn Moon"], nil)
    eq(AltsForeverDB.chars["Old"], nil)
    eq(type(AltsForeverDB.chars["Aldric"]), "table")
    SlashCmdList.ALTSFOREVER("forgetbeta")
    assert(wow.printed[#wow.printed]:find("No characters from the beta", 1, true))
end)

test("a live save with no beta characters is never asked about; unknown realms alone aren't the beta", function()
    wow.load(FILES)
    wow.popup = nil
    wow.login({ v = 2, chars = { ["Old"] = alt("Old", "WARRIOR", { bank = { [1] = 1 } }) } })
    runTimers()
    eq(betaPopups(), nil)
    eq(AltsForeverDB.betaAsked, true)
    eq(type(AltsForeverDB.chars["Old"]), "table")
end)

test("first login on a live realm: the beta's Legacy points are read afresh", function()
    local saved = betaSave()
    saved.legacyPool, saved.wellRested = 16, 5
    saved.chars["Tarn Moon"].legacySpent = 3
    local ns = legacyStart(saved, { 0, 0 }, 0, true)
    eq(AltsForeverDB.legacyPool, 0, "the live account has earned none yet")
    eq(AltsForeverDB.wellRested, nil)
    assert(not legacyPrinted():find("Legacy point", 1, true), "no points to spend\n" .. legacyPrinted())
    eq(ns.LegacyUnspent(AltsForeverDB.chars["Tarn Moon"]), 0)

    -- Read afresh at each login until the question is answered; then left alone again.
    StaticPopupDialogs.ALTSFOREVER_BETA.OnCancel()
    eq(AltsForeverDB.betaAsked, true, "kept them")
    AltsForeverDB.legacyPool = 4
    legacyStart(AltsForeverDB, { 0, 0 }, 0)
    eq(AltsForeverDB.legacyPool, 4)

    -- On the beta itself, nothing changes.
    local beta = betaSave()
    beta.legacyPool = 16
    wow.load(FILES)
    wow.player.realm = "ClassicBetaPvE2"
    wow.login(beta)
    eq(AltsForeverDB.legacyPool, 16)
end)

test("on a live realm, mail left on the beta raises no warnings", function()
    local saved = betaSave()
    saved.chars["Tarn Moon"].mailExpires = NOW - DAY
    saved.chars["Old"].mailExpires = NOW + HOUR
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.login(saved)
    local lines = table.concat(ns.MailWarnings(NOW, 3 * DAY), "\n")
    eq(lines:find("Tarn Moon", 1, true), nil, "a beta character's mail")
    assert(lines:find("Old", 1, true), "a character of unknown realm still warns")
    wow.player.realm = "ClassicBetaPvE2"
    assert(table.concat(ns.MailWarnings(NOW, 3 * DAY), "\n"):find("Tarn Moon", 1, true), "on the beta it warns")
end)
