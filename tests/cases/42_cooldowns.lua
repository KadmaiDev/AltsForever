-- Tests: profession cooldowns (Professions.lua), read from the profession window and shown
-- in the overview's row tooltip and /af cooldowns. Loaded by tests/run.lua.

local DAY, HOUR = 86400, 3600

local function cooldownStart()
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.profs = { { "Tailoring", 250 }, { "Alchemy", 250 } }
    wow.login(overviewAlts())
    return ns, ns.char
end

local function tailoring(cd)
    wow.tradeskill.prof = "Tailoring"
    wow.tradeskill.recipes = {
        [2001] = { name = "Mooncloth", learned = true, cd = cd },
        [2002] = { name = "Bolt of Silk Cloth", learned = true },
        [2003] = { name = "Mooncloth Robe", learned = false, cd = 5 * DAY }, -- not known: never kept
    }
    wow.fire("TRADE_SKILL_SHOW")
end

local function rowLines(ns)
    SlashCmdList.ALTSFOREVER("")
    local you
    for _, r in ipairs(overviewRows()) do
        if r.key == ns.charKey then you = r end
    end
    you.scripts.OnEnter(you)
    local lines = {}
    for _, l in ipairs(GameTooltip.lines) do lines[#lines + 1] = table.concat(l, " = ") end
    return table.concat(lines, " | ")
end

test("profession cooldowns: read when the window opens, only recipes on cooldown kept", function()
    local ns, c = cooldownStart()
    eq(c.cooldowns, nil, "nothing until a profession window is opened")
    tailoring(3 * DAY + HOUR)
    eq(c.cooldowns.Tailoring.Mooncloth, NOW + 3 * DAY + HOUR)
    eq(c.cooldowns.Tailoring["Bolt of Silk Cloth"], nil, "no cooldown: not kept")
    eq(c.cooldowns.Tailoring["Mooncloth Robe"], nil, "not learned: not kept")
    -- The text, rounded up to the minute.
    eq(ns.CooldownText(NOW + 3 * DAY + HOUR, NOW), "ready in 3d 1h")
    eq(ns.CooldownText(NOW + HOUR + 20 * 60, NOW), "ready in 1h 20m")
    eq(ns.CooldownText(NOW + 9 * 60 + 1, NOW), "ready in 10 min")
    eq(ns.CooldownText(NOW, NOW), "|cff20ff20ready|r")
    eq(ns.CooldownText(NOW - DAY, NOW), "|cff20ff20ready|r", "long since: still ready")
    -- Shown in the row tooltip and /af cooldowns.
    local all = rowLines(ns)
    assert(all:find("Mooncloth = ready in 3d 1h", 1, true), all)
    wow.printed = {}
    SlashCmdList.ALTSFOREVER("cooldowns")
    local chat = table.concat(wow.printed, "\n")
    assert(chat:find("Profession cooldowns:", 1, true), chat)
    assert(chat:find("Mooncloth ready in 3d 1h", 1, true), chat)
    -- Later, offline or not, it reads as ready; the entry stays (it's a cooldown recipe).
    eq(ns.CooldownRows(c, NOW + 4 * DAY)[1][2], NOW + 4 * DAY)
end)

test("profession cooldowns: a craft with the window open starts one; a shared cooldown is one row", function()
    local ns, c = cooldownStart()
    wow.tradeskill.prof = "Alchemy"
    wow.tradeskill.recipes = {
        [3001] = { name = "Transmute: Arcanite", learned = true },
        [3002] = { name = "Transmute: Iron to Gold", learned = true },
        [3003] = { name = "Elixir of Fortitude", learned = true },
    }
    wow.fire("TRADE_SKILL_SHOW")
    eq(c.cooldowns, nil, "none on cooldown yet")
    -- A transmute made: the shared cooldown starts, the bar lands in the bags.
    wow.tradeskill.recipes[3001].cd, wow.tradeskill.recipes[3002].cd = DAY, DAY - 1
    local v = ns.version
    wow.fire("BAG_UPDATE_DELAYED")
    eq(c.cooldowns.Alchemy["Transmute: Arcanite"], NOW + DAY)
    eq(c.cooldowns.Alchemy["Transmute: Iron to Gold"], NOW + DAY - 1)
    assert(ns.version > v, "the overview and tooltips refresh")
    local rows = ns.CooldownRows(c, NOW)
    eq(#rows, 1, "one shared cooldown, one row")
    eq(ns.CooldownName(rows[1]), "Transmute: Iron to Gold +1 more", "named after the soonest")
    -- A steady reading a moment later changes nothing.
    v = ns.version
    wow.now = NOW + 5
    wow.tradeskill.recipes[3001].cd = DAY - 5
    wow.fire("BAG_UPDATE_DELAYED")
    eq(ns.version, v, "the same cooldown read again: no refresh")
    -- Window closed: bag updates read nothing.
    wow.fire("TRADE_SKILL_CLOSE")
    wow.tradeskill.recipes[3001].cd = nil
    wow.fire("BAG_UPDATE_DELAYED")
    eq(c.cooldowns.Alchemy["Transmute: Arcanite"], NOW + DAY, "kept while the window is shut")
    -- Opened again with the cooldown over early: ready now.
    wow.tradeskill.recipes[3002].cd = nil
    wow.fire("TRADE_SKILL_SHOW")
    eq(c.cooldowns.Alchemy["Transmute: Arcanite"], NOW + 5, "ready")
    eq(ns.CooldownName(ns.CooldownRows(c, NOW + 5)[1]), "Transmute: Arcanite +1 more", "both ready: one row")
    -- Two professions: soonest first, one row each.
    tailoring(2 * HOUR)
    rows = ns.CooldownRows(c, NOW + 5)
    eq(#rows, 2)
    eq(rows[1][1], "Transmute: Arcanite"); eq(rows[2][1], "Mooncloth")
end)

test("profession cooldowns: forgotten with the recipe or profession; secret answers ignored; repaired at load", function()
    local ns, c = cooldownStart()
    tailoring(DAY)
    eq(c.cooldowns.Tailoring.Mooncloth, NOW + DAY)
    -- Unlearned (or renamed): gone at the next scan.
    wow.tradeskill.recipes[2001].learned = false
    wow.fire("TRADE_SKILL_SHOW")
    eq(c.cooldowns, nil, "nothing left: no table kept")
    -- A secret answer stores nothing and breaks nothing.
    wow.tradeskill.recipes[2001].learned, wow.tradeskill.recipes[2001].cd = true, wow.SECRET
    wow.fire("TRADE_SKILL_SHOW")
    eq(c.cooldowns, nil)
    -- A profession dropped takes its cooldowns with it.
    tailoring(DAY)
    eq(c.cooldowns.Tailoring.Mooncloth, NOW + DAY)
    wow.profs = { { "Alchemy", 250 } }
    wow.fire("SKILL_LINES_CHANGED")
    eq(c.cooldowns, nil)
    -- /af cooldowns with none at all.
    wow.printed = {}
    SlashCmdList.ALTSFOREVER("cooldowns")
    assert(table.concat(wow.printed, "\n"):find("No profession cooldowns seen yet", 1, true))
    -- Damaged saves: wrong types dropped, good entries kept.
    local saved = overviewAlts()
    local key = next(saved.chars)
    saved.chars[key].cooldowns = { Tailoring = { Mooncloth = NOW, bad = "x" }, [3] = {}, Alchemy = "no", Empty = { bad = true } }
    wow.load(FILES)
    wow.login(saved)
    local cd = saved.chars[key].cooldowns
    eq(cd.Tailoring.Mooncloth, NOW); eq(cd.Tailoring.bad, nil)
    eq(cd[3], nil); eq(cd.Alchemy, nil); eq(cd.Empty, nil, "emptied by the repair: dropped")
end)
