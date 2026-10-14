-- Tests: rulesets. Loaded by tests/run.lua.
-- Each ruleset (Normal, PvP, Roleplaying, Hardcore) is its own world with its own auction
-- house and mail; the client reports one realm name per ruleset.

PVE, PVP = "ClassicBetaPvE2", "ClassicBetaPvP"

-- You (Aldric, Normal), Tarn on Normal, Grim on PvP, Old not logged in since rulesets
-- were recorded.
function rulesetAlts()
    return { v = 2, chars = {
        ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { realm = PVE, level = 20, money = 3000,
            bags = { [2589] = 10, [9001] = 20 } }),
        ["Grim Tusk"] = alt("Grim Tusk", "WARRIOR", { realm = PVP, level = 18, money = 500,
            bags = { [2589] = 7, [9001] = 30 }, crafts = { Engineering = { [4401] = true } } }),
        ["Old Timer"] = alt("Old Timer", "PRIEST", { level = 12, money = 200, bank = { [2589] = 4 } }),
    } }
end

function rulesetStart()
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.player.realm = PVE
    wow.money = 1000
    wow.setBag(0, 16, { { 2589, 1 } })
    wow.login(rulesetAlts())
    return ns
end

-- The tooltip's lines as "left = right", one per line.
function rulesetHover(id, text)
    return textOf(wow.hover(GameTooltip, id, text))
end

test("each character's ruleset is recorded at login; a secret or empty one is ignored", function()
    local ns = rulesetStart()
    eq(ns.char.realm, PVE)
    wow.load(FILES)
    wow.player.realm = wow.SECRET
    wow.login({ v = 2, chars = { ["Aldric"] = alt("Aldric", "MAGE", { realm = PVE }) } })
    eq(AltsForeverDB.chars["Aldric"].realm, PVE, "kept")
    wow.load(FILES)
    wow.player.realm = ""
    wow.login(nil)
    eq(AltsForeverDB.chars["Aldric"].realm, nil)
end)

test("ruleset names: from the realm name, told apart when two share a ruleset", function()
    local ns = rulesetStart()
    eq(ns.RulesetLabel(PVP), "PvP")
    eq(ns.RulesetLabel(PVE), "Normal")
    eq(ns.RulesetLabel("ClassicBetaRP"), "Roleplaying")
    eq(ns.RulesetLabel("ForeverHardcore"), "Hardcore")
    eq(ns.RulesetLabel("Somewhere"), "Somewhere", "a name that doesn't say is shown as it is")
    eq(ns.RulesetLabel(nil), "Not sorted yet (log in on them once)")
    AltsForeverDB.chars["Tarn Moon"].realm = "ClassicBetaPvE"
    eq(ns.RulesetLabel(PVE), "Normal (ClassicBetaPvE2)")
end)

test("item tooltips leave out other rulesets by default; not-yet-sorted characters stay", function()
    rulesetStart()
    local text = rulesetHover(2589)
    assert(text:find("Total = 15", 1, true), "you 1 + Tarn 10 + Old 4, not Grim's 7\n" .. text)
    assert(text:find("Tarn", 1, true) and text:find("Old", 1, true), text)
    assert(not text:find("Grim", 1, true), text)
    text = rulesetHover(9001)
    assert(text:find("Tarn", 1, true) and not text:find("Grim", 1, true), "only Tarn has it here\n" .. text)
end)

test("with other rulesets shown, they come under their own heading and total", function()
    rulesetStart()
    SlashCmdList.ALTSFOREVER("rulesets")
    eq(AltsForeverDB.otherRulesets, true)
    local text = rulesetHover(2589)
    assert(text:find("Total = 15", 1, true), "your ruleset's total only\n" .. text)
    local pvp, grim = text:find("\nPvP = 7", 1, true), text:find("Grim", 1, true)
    assert(pvp and grim and pvp < grim, "PvP heading with its total, then Grim\n" .. text)
    assert(text:find("Old", 1, true) < pvp, "your ruleset first")
    -- Only another ruleset has it: just their heading.
    AltsForeverDB.chars["Tarn Moon"].bags[2589] = nil
    AltsForeverDB.chars["Old Timer"].bank[2589] = nil
    wow.setBag(0, 16, {})
    wow.fire("BAG_UPDATE", 0)
    wow.fire("BAG_UPDATE_DELAYED")
    SlashCmdList.ALTSFOREVER("rulesets")
    SlashCmdList.ALTSFOREVER("rulesets")
    text = rulesetHover(2589)
    assert(not text:find("Total", 1, true), text)
    assert(text:find("PvP = 7", 1, true), text)
    SlashCmdList.ALTSFOREVER("rulesets")
    eq(AltsForeverDB.otherRulesets, nil)
    eq(rulesetHover(2589):find("Grim", 1, true), nil, "hidden again")
end)

test("the gold tooltip totals your ruleset; others only when shown, under their heading", function()
    local ns = rulesetStart()
    local tt = wow.tooltip()
    ns.AddMoneyLines(tt)
    local text = textOf(tt.lines)
    assert(text:find("Total = 4200c", 1, true), "1000 + 3000 + 200\n" .. text)
    assert(not text:find("Grim", 1, true), text)
    ns.SetOtherRulesets(true)
    tt = wow.tooltip()
    ns.AddMoneyLines(tt)
    text = textOf(tt.lines)
    assert(text:find("Total = 4200c", 1, true), text)
    assert(text:find("PvP = 500c\n[WARRIOR]Grim Tusk = 500c", 1, true), text)
end)

test("gold over time is kept per ruleset", function()
    local ns = rulesetStart()
    local days = AltsForeverDB.goldDays
    local today
    for day in pairs(days) do today = day end
    eq(days[today], 4200, "your ruleset's total")
    eq(AltsForeverDB.goldRealm, PVE, "the history from before belongs to the first ruleset seen")
    -- Logging in on the PvP character: its own history.
    local saved = AltsForeverDB
    wow.load(FILES)
    wow.now = NOW
    wow.player.name, wow.player.realm, wow.player.class = "Grim Tusk", PVP, "WARRIOR"
    wow.money = 800
    wow.login(saved)
    eq(AltsForeverDB.goldDays[today], 4200, "Normal's history untouched")
    eq(AltsForeverDB.goldDaysBy[PVP][today], 1000, "Grim 800, and Old (not sorted yet) 200")
end)

test("send to alt never offers characters on another ruleset", function()
    local ns = rulesetStart()
    ns.SetOtherRulesets(true)
    local keys = {}
    for _, e in ipairs(ns.SendToAltEntries()) do keys[#keys + 1] = e.key end
    eq(table.concat(keys, ","), "Tarn Moon,Old Timer")
end)

test("Can craft leaves out other rulesets unless shown", function()
    local ns = rulesetStart()
    eq(craftLine(wow.hover(GameTooltip, 4401)), nil)
    ns.SetOtherRulesets(true)
    eq(craftLine(wow.hover(GameTooltip, 4401)), "[WARRIOR]Grim Tusk")
end)

test("crates count only your ruleset's materials, even with other rulesets shown", function()
    local ns = rulesetStart()
    ns.SetOtherRulesets(true)
    wow.itemNames[9001] = "Soul Dust"
    local text = rulesetHover(CRATE, CRATE_TEXT)
    assert(text:find("20 Soul Dust = [DRUID]Tarn |cffe0e0e020|r    |cff20ff2020|r", 1, true), text)
    assert(not text:find("Grim", 1, true), text)
end)

test("the overview heads each ruleset with its gold; one ruleset, no headings", function()
    rulesetStart()
    SlashCmdList.ALTSFOREVER("")
    local rows = overviewRows()
    eq(cell(rows[1], 1), "[MAGE]Aldric")
    eq(cell(rows[2], 1), "[DRUID]Tarn Moon")
    eq(cell(rows[3], 1), "[WARRIOR]Grim Tusk", "the other ruleset next")
    eq(cell(rows[4], 1), "[PRIEST]Old Timer", "not sorted yet, last")
    local heads = {}
    for _, f in ipairs(wow.frames) do
        if rawget(f, "label") and rawget(f, "gold") and f.shown then heads[#heads + 1] = f.label.text .. " " .. f.gold.text end
    end
    eq(table.concat(heads, " | "), "Normal 4000c | PvP 500c | Not sorted yet (log in on them once) 200c")
    assert(not AltsForeverFrame.footer.text:find("gold", 1, true), "no mixed gold total")
    -- One ruleset only: as before.
    wow.load(FILES)
    wow.now = NOW
    wow.player.realm = PVE
    local saved = rulesetAlts()
    saved.chars["Grim Tusk"] = nil
    wow.login(saved)
    SlashCmdList.ALTSFOREVER("")
    for _, f in ipairs(wow.frames) do
        assert(not (rawget(f, "label") and rawget(f, "gold") and f.shown), "no headings")
    end
    assert(AltsForeverFrame.footer.text:find("Total gold", 1, true))
end)

test("the setting is in the options menu", function()
    local ns = rulesetStart()
    ns.ShowOptionsMenu(UIParent)
    wow.menuItem("Show other rulesets").setSelected()
    eq(AltsForeverDB.otherRulesets, true)
end)
