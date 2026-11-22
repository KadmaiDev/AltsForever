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

local function cooldownSaved()
    local saved = overviewAlts()
    local chars = saved.chars
    chars.High.cooldowns = { Tailoring = { Mooncloth = NOW - 10 },
        Alchemy = { ["Transmute: Arcanite"] = NOW + 3 * HOUR, ["Transmute: Iron to Gold"] = NOW + 3 * HOUR } }
    chars.Far.cooldowns = { Alchemy = { ["Transmute: Arcanite"] = NOW + 2 * DAY + 4 * HOUR } }
    chars.Low.cooldowns = { Tailoring = { Mooncloth = NOW - 5 }, Alchemy = { ["Transmute: Arcanite"] = NOW - 1 } }
    return saved
end

local function rowOf(name)
    for _, r in ipairs(overviewRows()) do
        if cell(r, 1):find(name, 1, true) then return r end
    end
end

local function cooldownButton(row)
    for _, b in ipairs(row.spaces) do
        if b.which == "cooldowns" then return b end
    end
end

local function tipText()
    local lines = {}
    for _, l in ipairs(GameTooltip.lines) do lines[#lines + 1] = table.concat(l, " = ") end
    return table.concat(lines, " | ")
end

test("the overview's Cooldowns column: ready, how many, or the soonest; sorts; points and clicks", function()
    local click = sortStart(cooldownSaved())
    local READY = "|cff20ff20"
    eq(AltsForeverFrame.sorts.cooldowns.col.title, "Cooldowns")
    eq(cell(rowOf("Aldric"), 15), "", "none seen: blank")
    eq(cell(rowOf("High"), 15), READY .. "Ready|r", "Mooncloth ready, the transmutes not")
    eq(cell(rowOf("Low"), 15), READY .. "2 ready|r", "one per profession")
    eq(cell(rowOf("Far"), 15), "2d 4h", "none ready: the soonest")
    eq(cell(rowOf("High"), 16), "Orgrimmar", "Zone after it")
    -- Sorted: the most ready first, then the soonest; none last.
    click("cooldowns")
    eq(overviewNames(), "Low, High, Far, Aldric")
    -- Pointing at a cell lists them; a click opens their professions on the first.
    local b = cooldownButton(rowOf("High"))
    b.scripts.OnEnter(b)
    local tip = tipText()
    assert(tip:find("[PRIEST]High = Cooldowns", 1, true), tip)
    assert(tip:find("Mooncloth = " .. READY .. "ready|r", 1, true), tip)
    assert(tip:find("Transmute: Arcanite +1 more = ready in 3h 0m", 1, true), tip)
    assert(tip:find("Click to open their professions", 1, true), tip)
    b.scripts.OnLeave(b)
    b.scripts.OnClick(b, "LeftButton")
    eq(AltsForeverRecipesFrame:IsShown(), true)
    eq(AltsForeverRecipesFrame.titleText, "Tailoring", "the profession of the first one listed")
    -- A character with none: the row's own tooltip and click.
    b = cooldownButton(rowOf("Aldric"))
    b.scripts.OnEnter(b)
    tip = tipText()
    assert(tip:find("Level 24", 1, true) and not tip:find("Click to open their professions", 1, true), tip)
    b.scripts.OnClick(b, "LeftButton")
    eq(AltsForeverGearFrame:IsShown(), true, "their gear, as the row's click")
end)

test("the open overview turns a cooldown to Ready when its time comes, only while the column shows", function()
    local saved = overviewAlts()
    saved.chars.Low.cooldowns = { Tailoring = { Mooncloth = NOW + 30 } }
    local function countdown()
        for i = #wow.timers, 1, -1 do
            local fn = wow.timers[i]
            if wow.delays[fn] == 30 then return fn end
        end
    end
    sortStart(saved)
    eq(cell(rowOf("Low"), 15), "1 min")
    local fn = countdown()
    assert(fn, "a refresh when it's ready")
    wow.now = NOW + 30
    fn()
    eq(cell(rowOf("Low"), 15), "|cff20ff20Ready|r")
    -- Column hidden: nothing to keep current.
    saved = overviewAlts()
    saved.chars.Low.cooldowns = { Tailoring = { Mooncloth = NOW + 30 } }
    saved.hiddenColumns = { cooldowns = true }
    wow.now = NOW
    sortStart(saved)
    eq(countdown(), nil)
end)
