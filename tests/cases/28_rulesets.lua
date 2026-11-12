-- Tests: rulesets. Loaded by tests/run.lua.
-- Each ruleset (Normal, PvP, Roleplaying, Hardcore) is its own world with its own auction
-- house and mail; the client reports a realm name, and a ruleset can have several.

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

test("ruleset names: from the realm name, the same for two realms of one ruleset", function()
    local ns = rulesetStart()
    eq(ns.RulesetLabel(PVP), "PvP")
    eq(ns.RulesetLabel(PVE), "Normal")
    eq(ns.RulesetLabel("ClassicBetaRP"), "Roleplaying")
    eq(ns.RulesetLabel("ForeverHardcore"), "Hardcore")
    eq(ns.RulesetLabel("Somewhere"), "Somewhere", "a name that doesn't say is shown as it is")
    eq(ns.RulesetLabel(nil), "Not sorted yet (log in on them once)")
    AltsForeverDB.chars["Tarn Moon"].realm = "ClassicBetaPvE"
    eq(ns.RulesetLabel(PVE), "Normal")
end)

test("ruleset names: the game's own answer, recorded per realm, beats the realm name", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.player.realm, wow.player.ruleset = "Forever-3", "PvPRuleset"
    local saved = rulesetAlts()
    saved.chars["Tarn Moon"].realm = "Forever-1"
    wow.login(saved)
    eq(AltsForeverDB.rulesets["Forever-3"], "pvp")
    eq(AltsForeverDB.rulesets["Forever-1"], nil, "only realms logged in on")
    eq(ns.RulesetLabel("Forever-3"), "PvP")
    eq(ns.RulesetLabel("Forever-1"), "Forever-1", "not asked yet: the realm name as it is")
    eq(ns.RulesetLabel("SomeRP"), "Roleplaying", "still read from the name")
    eq(ns.RulesetLabel(PVP), "PvP", "the same name as the game's PvP")
    -- Logging in on Tarn's realm, a Normal one, whose name says nothing.
    saved = AltsForeverDB
    wow.load(FILES)
    wow.player.name, wow.player.realm, wow.player.ruleset = "Tarn Moon", "Forever-1", nil
    wow.login(saved)
    eq(AltsForeverDB.rulesets["Forever-1"], "normal")
    eq(AltsForeverDB.rulesets["Forever-3"], "pvp", "others kept")
    -- The game's answer wins over a name that seems to say otherwise.
    saved = AltsForeverDB
    wow.load(FILES)
    wow.player.realm, wow.player.ruleset = "OddPvE", "RPRuleset"
    wow.login(saved)
    eq(AltsForeverDB.rulesets["OddPvE"], "rp")
end)

test("ruleset from the game: a secret or missing answer records nothing", function()
    wow.load(FILES)
    wow.player.realm, wow.player.ruleset = "Forever-3", wow.SECRET
    wow.login(rulesetAlts())
    eq(AltsForeverDB.rulesets, nil, "secret")
    wow.load(FILES)
    C_GameRules = nil
    wow.player.realm = "Forever-3"
    wow.login(rulesetAlts())
    eq(AltsForeverDB.rulesets, nil, "no C_GameRules")
    wow.load(FILES)
    Enum.GameRule = { PvPRuleset = 103 }
    wow.player.realm = "Forever-3"
    wow.login(rulesetAlts())
    eq(AltsForeverDB.rulesets["Forever-3"], "normal", "the rules it knows are asked")
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
    local pvp, grim = text:find("\nPvP = 7", 1, true), text:find("\n  |cff808080Grim Tusk|r", 1, true)
    assert(pvp and grim and pvp < grim, "PvP heading with its total, then Grim in grey (can't trade)\n" .. text)
    assert(text:find("Old", 1, true) < pvp, "your ruleset first")
    assert(text:find("\n \nPvP = 7", 1, true), "a blank line before the other rulesets\n" .. text)
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
    assert(text:find("\n \nPvP = 500c\n  Grim Tusk = 500c", 1, true), "after a blank line; grey, not class coloured\n" .. text)
end)

test("gold over time is kept per ruleset", function()
    local ns = rulesetStart()
    local days = AltsForeverDB.goldDays
    local today
    for day in pairs(days) do today = day end
    eq(days[today], 4200, "your ruleset's total")
    eq(AltsForeverDB.goldGroup, PVE .. "|Alliance", "the history from before belongs to the first group seen")
    -- Logging in on the PvP character: its own history.
    local saved = AltsForeverDB
    wow.load(FILES)
    wow.now = NOW
    wow.player.name, wow.player.realm, wow.player.class = "Grim Tusk", PVP, "WARRIOR"
    wow.money = 800
    wow.login(saved)
    eq(AltsForeverDB.goldDays[today], 4200, "Normal's history untouched")
    eq(AltsForeverDB.goldDaysBy[PVP .. "|Alliance"][today], 1000, "Grim 800, and Old (not sorted yet) 200")
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
    eq(craftLine(wow.hover(GameTooltip, 4401)), "|cff808080Grim Tusk|r", "grey: can't trade with you")
end)

test("crates count only your ruleset's materials, even with other rulesets shown", function()
    local ns = rulesetStart()
    ns.SetOtherRulesets(true)
    wow.itemNames[9001] = "Soul Dust"
    local text = rulesetHover(CRATE, CRATE_TEXT)
    assert(text:find("[DRUID]Tarn = |cff20ff2020|r", 1, true), "enough alone: green\n" .. text)
    assert(text:find("Total = |cff20ff2020|r", 1, true), text)
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
    eq(table.concat(heads, " | "), "Normal 4000c | PvP  | Not sorted yet (log in on them once) ", "a total only for two or more")
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
    wow.menuItem("Show other rulesets and factions").setSelected()
    eq(AltsForeverDB.otherRulesets, true)
end)

-- Mail never crosses factions either: the other faction is kept apart the same way.
function factionAlts()
    return { v = 2, chars = {
        ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { realm = PVE, faction = "Alliance", level = 20, money = 3000,
            bags = { [2589] = 10, [9001] = 20 } }),
        ["Zug Zug"] = alt("Zug Zug", "SHAMAN", { realm = PVE, faction = "Horde", level = 25, money = 700,
            bags = { [2589] = 6, [9001] = 40 } }),
    } }
end

function factionStart()
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.player.realm = PVE
    wow.money = 1000
    wow.login(factionAlts())
    return ns
end

test("the other faction is left out of tooltips, or under its own heading when shown", function()
    local ns = factionStart()
    local text = rulesetHover(2589)
    assert(text:find("Tarn", 1, true) and not text:find("Zug", 1, true), text)
    ns.SetOtherRulesets(true)
    text = rulesetHover(2589)
    assert(text:find("Horde = 6\n  |cff808080Zug Zug|r", 1, true), "headed by faction only: one ruleset; grey\n" .. text)
    wow.itemNames[9001] = "Soul Dust"
    text = rulesetHover(CRATE, CRATE_TEXT)
    assert(not text:find("Zug", 1, true), "crates: only characters you can mail\n" .. text)
    local keys = {}
    for _, e in ipairs(ns.SendToAltEntries()) do keys[#keys + 1] = e.key end
    eq(table.concat(keys, ","), "Tarn Moon")
end)

test("the overview heads each faction; with two rulesets too, both are named", function()
    local ns = factionStart()
    SlashCmdList.ALTSFOREVER("")
    local heads = {}
    for _, f in ipairs(wow.frames) do
        if rawget(f, "label") and rawget(f, "gold") and f.shown then heads[#heads + 1] = f.label.text .. " " .. f.gold.text end
    end
    eq(table.concat(heads, " | "), "Alliance 4000c | Horde ")
    AltsForeverDB.chars["Grim Tusk"] = alt("Grim Tusk", "WARRIOR", { realm = PVP, faction = "Horde", level = 18, money = 500 })
    ns.RefreshOverview()
    heads = {}
    for _, f in ipairs(wow.frames) do
        if rawget(f, "label") and rawget(f, "gold") and f.shown then heads[#heads + 1] = f.label.text .. " " .. f.gold.text end
    end
    eq(table.concat(heads, " | "), "Normal · Alliance 4000c | Normal · Horde  | PvP · Horde ")
end)

-- The overview's group headings, shown, in order.
function overviewHeads()
    local list = {}
    for _, f in ipairs(wow.frames) do
        if rawget(f, "label") and rawget(f, "gold") and f.shown then list[#list + 1] = f end
    end
    return list
end

test("clicking a group heading collapses it to the heading, and opens it again", function()
    rulesetStart()
    SlashCmdList.ALTSFOREVER("")
    eq(#overviewRows(), 4)
    local normal = overviewHeads()[1]
    eq(normal.icon.texture, "Interface\\Buttons\\UI-MinusButton-Up")
    normal.scripts.OnClick(normal)
    local rows = overviewRows()
    eq(#rows, 2, "Aldric and Tarn hidden")
    eq(cell(rows[1], 1), "[WARRIOR]Grim Tusk")
    local heads = overviewHeads()
    eq(heads[1].label.text, "Normal  |cff9d9d9d(2)|r")
    eq(heads[1].icon.texture, "Interface\\Buttons\\UI-PlusButton-Up")
    eq(heads[2].gold.text, "", "an open group of one: no total")
    heads[2].scripts.OnClick(heads[2])
    eq(overviewHeads()[2].gold.text, "500c", "collapsed: its total, as its row is hidden")
    eq(AltsForeverDB.collapsedGroups[heads[1].group], true, "kept between sessions")
    heads[1].scripts.OnEnter(heads[1])
    assert(textOf(GameTooltip.lines):find("Click to show these characters.", 1, true))
    heads[1].scripts.OnClick(heads[1])
    heads[2].scripts.OnClick(heads[2])
    eq(#overviewRows(), 4)
    eq(AltsForeverDB.collapsedGroups, nil, "nothing left collapsed: nothing saved")
end)

test("with other rulesets shown, the columns still land on the right lines, none on the gap", function()
    wow.load(FILES)
    local rights = columnTooltip()
    wow.now = NOW
    wow.player.realm = PVE
    wow.setBag(0, 16, { { 2589, 1 } })
    wow.login(rulesetAlts())

    SlashCmdList.ALTSFOREVER("rulesets")
    local lines = wow.hover(GameTooltip, 2589)
    local gap, grim
    for i, l in ipairs(lines) do
        if l[1] == " " and i > 2 then gap = i end
        if l[1] == "  |cff808080Grim Tusk|r" then grim = i end
    end
    assert(gap and grim and gap < grim, textOf(lines))
    eq(#cellsOn(rights[gap]), 0, "nothing on the blank line")
    local cells = cellsOn(rights[grim])
    eq(cells[1].text, "|cff8080807|r", "Grim's count, in grey, on Grim's line")
    eq(cellsOn(rights[grim - 1])[1].text, "|cffbf9e407|r", "the heading's total, in muted gold")
end)

test("the bags window's character list is headed by group, like the overview", function()
    rulesetStart()
    SlashCmdList.ALTSFOREVER("bags")
    AltsForeverBagsFrame.who.scripts.OnClick(AltsForeverBagsFrame.who)
    local items = {}
    for _, item in ipairs(wow.menu.items) do items[#items + 1] = item.kind == "divider" and "--" or item.text end
    eq(table.concat(items, " | "), "Normal | [MAGE]Aldric | [DRUID]Tarn Moon | -- | PvP | [WARRIOR]Grim Tusk | -- | "
        .. "Not sorted yet (log in on them once) | [PRIEST]Old Timer")
end)

test("the gold history from before goes to the group with the most gold, whoever logs in first", function()
    wow.load(FILES)
    wow.now = NOW
    wow.player.realm = PVP -- you: Aldric, a small PvP Alliance character
    wow.money = 100
    local yesterday = math.floor(NOW / 86400) - 1
    local history = { [yesterday] = 5000 }
    wow.login({ v = 2, goldDays = history, chars = {
        ["Rich Main"] = alt("Rich Main", "WARRIOR", { faction = "Horde", money = 90000 }),
    } })
    eq(AltsForeverDB.goldGroup, nil, "Horde has more gold: the history waits for them")
    eq(AltsForeverDB.goldDays[yesterday], 5000)
    local mine
    for day, total in pairs(AltsForeverDB.goldDaysBy[PVP .. "|Alliance"]) do mine = total end
    eq(mine, 100, "your own group's history starts fresh")
    -- The Horde main logs in: their group takes the history.
    local saved = AltsForeverDB
    wow.load(FILES)
    wow.now = NOW
    wow.player.name, wow.player.realm, wow.player.class, wow.player.faction = "Rich Main", PVE, "WARRIOR", "Horde"
    wow.money = 90000
    wow.login(saved)
    eq(AltsForeverDB.goldGroup, PVE .. "|Horde")
    eq(AltsForeverDB.goldDays[yesterday], 5000, "the old days kept")
end)

test("claiming the history from before, a group keeps its own days too", function()
    wow.load(FILES)
    wow.now = NOW
    local yesterday = math.floor(NOW / 86400) - 1
    wow.player.name, wow.player.realm, wow.player.class, wow.player.faction = "Rich Main", PVE, "WARRIOR", "Horde"
    wow.money = 90000
    wow.login({ v = 2, goldDays = { [yesterday - 1] = 5000, [yesterday] = 6000 },
        goldDaysBy = { [PVE .. "|Horde"] = { [yesterday] = 9000 }, [PVP .. "|Alliance"] = { [yesterday] = 100 } },
        chars = { ["Rich Main"] = alt("Rich Main", "WARRIOR", { faction = "Horde", realm = PVE, money = 90000 }) } })
    eq(AltsForeverDB.goldGroup, PVE .. "|Horde")
    eq(AltsForeverDB.goldDays[yesterday - 1], 5000, "the old days kept")
    eq(AltsForeverDB.goldDays[yesterday], 9000, "its own reading wins")
    eq(AltsForeverDB.goldDaysBy[PVE .. "|Horde"], nil, "no longer kept apart")
    eq(AltsForeverDB.goldDaysBy[PVP .. "|Alliance"][yesterday], 100, "other groups untouched")
end)

-- As a player reported (2026-11-07): one ruleset, two realm names. Five Alliance characters
-- on one, two on the other, each saw only their own realm's.
RP10, RP11 = "CAMWOWUS2Realm10RP", "CAMWOWUS2Realm11RP"

function twoRealmsStart(extra)
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.player.realm = RP10
    wow.money = 1000
    wow.setBag(0, 16, { { 2589, 1 } })
    local saved = { v = 2, chars = {
        ["Near Alt"] = alt("Near Alt", "DRUID", { realm = RP10, faction = "Alliance", money = 300,
            bags = { [2589] = 10 } }),
        ["Far Alt"] = alt("Far Alt", "MAGE", { realm = RP11, faction = "Alliance", money = 200,
            bags = { [2589] = 7 } }),
        ["Red Alt"] = alt("Red Alt", "ROGUE", { realm = RP11, faction = "Horde", money = 50,
            bags = { [2589] = 3 } }),
        ["Pve Alt"] = alt("Pve Alt", "PRIEST", { realm = "CAMWOWUS2Realm1PvE", faction = "Alliance",
            money = 70, bags = { [2589] = 5 } }),
    } }
    for k, v in pairs(extra or {}) do saved[k] = v end
    wow.login(saved)
    return ns
end

function mailKeys(ns)
    local keys = {}
    for _, e in ipairs(ns.SendToAltEntries()) do keys[#keys + 1] = e.key end
    table.sort(keys)
    return table.concat(keys, ",")
end

test("two realm names of one ruleset are one world: mail, tooltips and gold", function()
    local ns = twoRealmsStart()
    eq(ns.RulesetOf(RP10), "rp")
    eq(ns.RulesetOf(RP11), "rp")
    eq(ns.Elsewhere(AltsForeverDB.chars["Far Alt"]), false)
    eq(ns.Elsewhere(AltsForeverDB.chars["Red Alt"]), true, "the other faction")
    eq(ns.Elsewhere(AltsForeverDB.chars["Pve Alt"]), true, "another ruleset")
    eq(mailKeys(ns), "Far Alt,Near Alt")
    local text = rulesetHover(2589)
    assert(text:find("Total = 18", 1, true), "you 1 + Near 10 + Far 7\n" .. text)
    assert(not text:find("Red", 1, true) and not text:find("Pve", 1, true), text)
end)

test("logged in on the smaller realm, the list is the same world", function()
    local ns = twoRealmsStart()
    local saved = AltsForeverDB
    ns = wow.load(FILES)
    wow.player.name, wow.player.realm = "Far Alt", RP11
    wow.login(saved)
    eq(mailKeys(ns), "Aldric,Near Alt")
end)

test("two realm names of one ruleset share one group and heading", function()
    local ns = twoRealmsStart()
    local chars = AltsForeverDB.chars
    local byRealm, byFaction = ns.GroupParts()
    eq(byRealm, true, "RP and Normal")
    eq(ns.GroupKey(chars["Near Alt"], byRealm, byFaction), ns.GroupKey(chars["Far Alt"], byRealm, byFaction))
    assert(ns.GroupKey(chars["Far Alt"], byRealm, byFaction) ~= ns.GroupKey(chars["Pve Alt"], byRealm, byFaction))
    eq(ns.GroupLabel(chars["Far Alt"], byRealm, byFaction), "Roleplaying · Alliance")
    eq(ns.GroupLabel(chars["Near Alt"], byRealm, byFaction), "Roleplaying · Alliance")

    -- Only those two realms: no ruleset headings at all.
    chars["Pve Alt"], chars["Red Alt"] = nil, nil
    byRealm, byFaction = ns.GroupParts()
    eq(byRealm, false)
    eq(byFaction, false)
end)

test("the game's normal doesn't override a realm name that says otherwise", function()
    -- "normal" means no rule it asked about was on, not that it knows the ruleset.
    local ns = twoRealmsStart({ rulesets = { [RP11] = "normal" } })
    eq(ns.RulesetOf(RP11), "rp")
    eq(ns.RulesetOf("Forever-1"), "Forever-1", "says nothing, not asked")
    AltsForeverDB.rulesets["Forever-1"] = "normal"
    eq(ns.RulesetOf("Forever-1"), "normal", "says nothing: the game's answer stands")
    AltsForeverDB.rulesets["OddPvE"] = "pvp"
    eq(ns.RulesetOf("OddPvE"), "pvp", "any other answer beats the name")
    AltsForeverDB.rulesets["OddRP"] = "junk"
    eq(ns.RulesetOf("OddRP"), "rp", "a damaged answer is no answer")
end)

test("realms that don't say stay apart, whatever their names", function()
    local ns = twoRealmsStart()
    AltsForeverDB.chars["Near Alt"].realm = "Forever-2"
    AltsForeverDB.chars["Far Alt"].realm = "Forever-3"
    ns.char.realm = "Forever-2"
    eq(ns.Elsewhere(AltsForeverDB.chars["Near Alt"]), false)
    eq(ns.Elsewhere(AltsForeverDB.chars["Far Alt"]), true)
    eq(ns.RulesetLabel("Forever-3"), "Forever-3")
end)

test("gold history kept per realm name folds into its ruleset's, in place", function()
    local today = math.floor(NOW / 86400)
    local d1, d2, d3 = today - 3, today - 2, today - 1
    twoRealmsStart({ goldGroup = RP10 .. "|Alliance", goldDays = { [d1] = 500, [d2] = 600 },
        goldDaysBy = {
            [RP11 .. "|Alliance"] = { [d2] = 900, [d3] = 40 },
            [RP11 .. "|Horde"] = { [d1] = 7 },
            ["CAMWOWUS2Realm1PvE|Alliance"] = { [d1] = 8 },
        } })
    local db = AltsForeverDB
    eq(db.goldGroup, "rp|Alliance")
    eq(db.goldDays[d1], 500, "the main history kept")
    eq(db.goldDays[d2], 900, "the other realm's reading joins it, and its own wins as before")
    eq(db.goldDays[d3], 40)
    eq(db.goldDaysBy["rp|Alliance"], nil, "no longer kept apart")
    eq(db.goldDaysBy[RP11 .. "|Alliance"], nil)
    eq(db.goldDaysBy["rp|Horde"][d1], 7, "the other faction keeps its own")
    eq(db.goldDaysBy["normal|Alliance"][d1], 8, "the other ruleset too")
end)

test("two realms' history kept apart from the main one becomes one, the larger reading kept", function()
    local today = math.floor(NOW / 86400)
    twoRealmsStart({ goldGroup = "CAMWOWUS2Realm1PvE|Alliance", goldDays = { [today - 3] = 1 },
        goldDaysBy = {
            ["CAMWOWUS9Realm1RP|Horde"] = { [today - 2] = 30, [today - 3] = 5, [today - 4] = 11 },
            ["CAMWOWUS9Realm2RP|Horde"] = { [today - 2] = 20, [today - 1] = 9, [today - 4] = 44 },
        } })
    local db = AltsForeverDB
    eq(db.goldGroup, "normal|Alliance")
    local h = db.goldDaysBy["rp|Horde"]
    eq(h[today - 3], 5)
    eq(h[today - 2], 30, "the larger, from the first realm")
    eq(h[today - 4], 44, "the larger, from the second: whichever is folded first")
    eq(h[today - 1], 9)
    eq(db.goldDaysBy["CAMWOWUS9Realm1RP|Horde"], nil)
    eq(db.goldDaysBy["CAMWOWUS9Realm2RP|Horde"], nil)
end)

test("a realm folding into the main history never lowers it, whoever logs in first", function()
    local today = math.floor(NOW / 86400)
    local y, y2 = today - 1, today - 2
    local function saved()
        return { goldGroup = RP10 .. "|Alliance", goldDays = { [y] = 900 },
            goldDaysBy = { [RP11 .. "|Alliance"] = { [y] = 40, [y2] = 70 } } }
    end

    -- Logged in on that group.
    twoRealmsStart(saved())
    eq(AltsForeverDB.goldDays[y], 900, "the main reading is the larger: it stays")
    eq(AltsForeverDB.goldDays[y2], 70, "a day only the other realm had joins it")
    eq(AltsForeverDB.goldDaysBy, nil)

    -- Updated on a character of another group, then back.
    twoRealmsStart(saved())
    local db = AltsForeverDB
    db.goldGroup, db.goldDays = RP10 .. "|Alliance", { [y] = 900 }
    db.goldDaysBy = { [RP11 .. "|Alliance"] = { [y] = 40, [y2] = 70 } }
    wow.load(FILES)
    wow.player.name, wow.player.realm, wow.player.faction = "Red Alt", RP11, "Horde"
    wow.login(db)
    db = AltsForeverDB
    eq(db.goldGroup, "rp|Alliance")
    eq(db.goldDays[y], 900)
    eq(db.goldDays[y2], 70)
    eq(db.goldDaysBy["rp|Alliance"], nil, "folded at once, not left for that group's next login")
    wow.load(FILES)
    wow.player.name, wow.player.realm, wow.player.faction = "Far Alt", RP11, "Alliance"
    wow.login(db)
    eq(AltsForeverDB.goldDays[y], 900, "still, back on that group")
end)

test("the richest group counts a ruleset's realms together", function()
    local ns = twoRealmsStart()
    local chars = AltsForeverDB.chars
    chars["Near Alt"].money, chars["Far Alt"].money, chars["Pve Alt"].money = 300, 300, 500
    ns.char.money = 0
    eq(ns.RichestGroup(ns.char), true, "RP 600 across two realms beats Normal's 500")
end)

test("a chosen order sorts inside each group; the groups stay where they were", function()
    rulesetStart()
    SlashCmdList.ALTSFOREVER("")
    eq(overviewNames(), "Aldric, Tarn Moon, Grim Tusk, Old Timer")
    local heads = #overviewHeads()
    local b = AltsForeverFrame.sorts.gold
    b.scripts.OnClick(b)
    eq(overviewNames(), "Tarn Moon, Aldric, Grim Tusk, Old Timer", "Tarn has more gold than you")
    eq(#overviewHeads(), heads)
end)
