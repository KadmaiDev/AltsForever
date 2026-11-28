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
    eq(cell(rowOf("Aldric"), 19), "", "none seen: blank")
    eq(cell(rowOf("High"), 19), READY .. "Ready|r", "Mooncloth ready, the transmutes not")
    eq(cell(rowOf("Low"), 19), READY .. "2 ready|r", "one per profession")
    eq(cell(rowOf("Far"), 19), "2d 4h", "none ready: the soonest")
    eq(cell(rowOf("High"), 20), "Orgrimmar", "Zone after it")
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
    eq(AltsForeverCharacterFrame:IsShown(), true)
    eq(AltsForeverCharacterFrame.titleText, "Tailoring", "the profession of the first one listed")
    -- A character with none: the row's own tooltip and click.
    b = cooldownButton(rowOf("Aldric"))
    b.scripts.OnEnter(b)
    tip = tipText()
    assert(tip:find("Level 24", 1, true) and not tip:find("Click to open their professions", 1, true), tip)
    b.scripts.OnClick(b, "LeftButton")
    eq(AltsForeverCharacterFrame:IsShown(), true, "their gear, as the row's click")
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
    eq(cell(rowOf("Low"), 19), "1 min")
    local fn = countdown()
    assert(fn, "a refresh when it's ready")
    wow.now = NOW + 30
    fn()
    eq(cell(rowOf("Low"), 19), "|cff20ff20Ready|r")
    -- Column hidden: nothing to keep current.
    saved = overviewAlts()
    saved.chars.Low.cooldowns = { Tailoring = { Mooncloth = NOW + 30 } }
    saved.hiddenColumns = { cooldowns = true }
    wow.now = NOW
    sortStart(saved)
    eq(countdown(), nil)
end)

test("the Cooldowns column shows itself once someone has a cooldown, unless the player chose", function()
    local ns = cooldownStart()
    SlashCmdList.ALTSFOREVER("")
    local f = AltsForeverFrame
    local narrow = f.width
    eq(ns.ColumnShown("cooldowns"), false, "nobody has one: hidden")
    eq(overviewRows()[1].cells[19].shown, false)
    eq(AltsForeverDB.hiddenColumns, nil, "nothing saved for it")
    -- The first one seen: the open overview makes room for it.
    tailoring(DAY)
    eq(ns.ColumnShown("cooldowns"), true)
    eq(overviewRows()[1].cells[19].shown, true)
    eq(f.width, narrow + 70)
    eq(AltsForeverDB.hiddenColumns, nil, "still the player's default")
    -- The last one forgotten: gone again.
    wow.tradeskill.recipes[2001].learned = false
    wow.fire("TRADE_SKILL_SHOW")
    eq(ns.ColumnShown("cooldowns"), false)
    eq(f.width, narrow)
    -- Shown by the player: stays with none.
    ns.SetColumnShown("cooldowns", true)
    eq(AltsForeverDB.hiddenColumns.cooldowns, false)
    eq(ns.ColumnShown("cooldowns"), true)
    -- Hidden by the player: stays hidden with one.
    ns.SetColumnShown("cooldowns", false)
    wow.tradeskill.recipes[2001].learned = true
    wow.fire("TRADE_SKILL_SHOW")
    eq(AltsForeverDB.hiddenColumns.cooldowns, true)
    eq(ns.ColumnShown("cooldowns"), false)
    eq(overviewRows()[1].cells[19].shown, false)
    -- A damaged choice counts as none.
    AltsForeverDB.hiddenColumns.cooldowns = "yes"
    eq(ns.ColumnShown("cooldowns"), true, "someone has one")
end)

test("profession cooldowns: an unreadable answer keeps a running cooldown; the open overview follows a craft", function()
    local ns, c = cooldownStart()
    SlashCmdList.ALTSFOREVER("")
    tailoring(3 * DAY)
    eq(c.cooldowns.Tailoring.Mooncloth, NOW + 3 * DAY)
    -- The call failing, or a secret answer: nothing known, the running cooldown stays.
    local real = C_TradeSkillUI.GetRecipeCooldown
    C_TradeSkillUI.GetRecipeCooldown = function() error("not now") end
    wow.fire("BAG_UPDATE_DELAYED")
    C_TradeSkillUI.GetRecipeCooldown = real
    eq(c.cooldowns.Tailoring.Mooncloth, NOW + 3 * DAY, "a failed call")
    wow.tradeskill.recipes[2001].cd = wow.SECRET
    wow.fire("BAG_UPDATE_DELAYED")
    eq(c.cooldowns.Tailoring.Mooncloth, NOW + 3 * DAY, "a secret")
    wow.tradeskill.recipes[2001].cd = "soon"
    wow.fire("BAG_UPDATE_DELAYED")
    eq(c.cooldowns.Tailoring.Mooncloth, NOW + 3 * DAY, "not a number")
    -- Only a readable "no cooldown" means ready.
    wow.tradeskill.recipes[2001].cd = 0
    wow.fire("BAG_UPDATE_DELAYED")
    eq(c.cooldowns.Tailoring.Mooncloth, NOW, "0: ready")
    local you = overviewRows()[1]
    eq(cell(you, 19), "|cff20ff20Ready|r", "the open overview shows it")
    -- Made again with the window open: the cell follows the craft, no other refresh.
    wow.tradeskill.recipes[2001].cd = DAY
    wow.fire("BAG_UPDATE_DELAYED")
    eq(cell(you, 19), "1d 0h")
end)

test("profession cooldowns: a recipe learned with the window open is watched at once", function()
    local ns, c = cooldownStart()
    tailoring(nil)
    wow.tradeskill.recipes[2001].learned = false
    wow.fire("TRADE_SKILL_SHOW")
    -- Learned (from the pattern) and made without closing the window.
    wow.tradeskill.recipes[2001].learned = true
    wow.fire("NEW_RECIPE_LEARNED", 2001)
    wow.tradeskill.recipes[2001].cd = 4 * DAY
    wow.fire("BAG_UPDATE_DELAYED")
    eq(c.cooldowns and c.cooldowns.Tailoring.Mooncloth, NOW + 4 * DAY)
    -- Another profession's recipe isn't added.
    wow.tradeskill.recipes[9001] = { name = "Transmute: Arcanite", learned = true, cd = DAY, prof = "Alchemy" }
    wow.fire("NEW_RECIPE_LEARNED", 9001)
    eq(c.cooldowns.Alchemy, nil)
end)

-- The Salt Shaker (a player's request, 2026-11-27): an item's cooldown, kept with
-- Leatherworking's.
local SHAKER = 15846

local function shakerStart(profs)
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.profs = profs or { { "Leatherworking", 250, 300, line = 165 }, { "Skinning", 250, 300, line = 393 } }
    wow.itemNames[SHAKER] = "Salt Shaker"
    return ns
end

test("the Salt Shaker's cooldown: read like the hearthstone, kept with Leatherworking's", function()
    local ns = shakerStart()
    -- Used 10 minutes ago (game seconds), 3 days' cooldown.
    wow.cooldowns[SHAKER] = { wow.gameTime - 600, 3 * DAY }
    wow.login(overviewAlts())
    local c = ns.char
    eq(c.cooldowns.Leatherworking["Salt Shaker"], NOW + 3 * DAY - 600)
    eq(ns.CooldownCell(c, NOW), "2d 23h")
    local all = rowLines(ns)
    assert(all:find("Salt Shaker = ready in 2d 23h", 1, true), all)
    wow.printed = {}
    SlashCmdList.ALTSFOREVER("cooldowns")
    assert(table.concat(wow.printed, "\n"):find("Salt Shaker ready in 2d 23h", 1, true), table.concat(wow.printed, "\n"))
    -- Opening Leatherworking: its recipes are read, the shaker isn't one of them but stays.
    wow.tradeskill.prof, wow.tradeskill.line = "Leatherworking", 165
    wow.tradeskill.recipes = { [4001] = { name = "Rugged Armor Kit", learned = true } }
    wow.fire("TRADE_SKILL_SHOW")
    eq(c.cooldowns.Leatherworking["Salt Shaker"], NOW + 3 * DAY - 600, "kept by the window's reading")
    -- Still kept when its name can't be read for the moment.
    wow.itemNames[SHAKER] = nil
    wow.fire("TRADE_SKILL_SHOW")
    eq(c.cooldowns.Leatherworking["Salt Shaker"], NOW + 3 * DAY - 600, "not dropped on a guess")
    wow.itemNames[SHAKER] = "Salt Shaker"
end)

test("the Salt Shaker: used again, the global cooldown, ready, in the bank, secret answers", function()
    local ns = shakerStart()
    wow.login(overviewAlts())
    local c = ns.char
    eq(c.cooldowns, nil, "never on cooldown: nothing")
    -- Used: the game says so with BAG_UPDATE_COOLDOWN.
    wow.cooldowns[SHAKER] = { wow.gameTime, 3 * DAY }
    local v = ns.version
    wow.fire("BAG_UPDATE_COOLDOWN")
    eq(c.cooldowns.Leatherworking["Salt Shaker"], NOW + 3 * DAY)
    assert(ns.version > v, "tooltips and the overview refresh")
    -- The global cooldown after another item isn't the shaker's.
    wow.cooldowns[SHAKER] = { wow.gameTime, 1.5 }
    wow.fire("BAG_UPDATE_COOLDOWN")
    eq(c.cooldowns.Leatherworking["Salt Shaker"], NOW + 3 * DAY, "not in the bags: may be the bank's reading, kept")
    -- No cooldown with the shaker in the bags: ready early.
    c.bags = c.bags or {}
    c.bags[SHAKER] = 1
    wow.cooldowns[SHAKER] = nil
    wow.fire("BAG_UPDATE_COOLDOWN")
    eq(c.cooldowns.Leatherworking["Salt Shaker"], NOW, "ready")
    -- A secret answer is left alone.
    wow.cooldowns[SHAKER] = { wow.gameTime, 3 * DAY }
    wow.fire("BAG_UPDATE_COOLDOWN")
    local get = C_Container.GetItemCooldown
    C_Container.GetItemCooldown = function() return wow.SECRET, wow.SECRET, 1 end
    wow.now = NOW + HOUR
    wow.fire("BAG_UPDATE_COOLDOWN")
    eq(c.cooldowns.Leatherworking["Salt Shaker"], NOW + 3 * DAY, "kept")
    C_Container.GetItemCooldown = get
end)

test("the Salt Shaker: nothing without Leatherworking, or before its name loads", function()
    local ns = shakerStart({ { "Tailoring", 250, 300, line = 197 } })
    wow.cooldowns[SHAKER] = { wow.gameTime, 3 * DAY }
    wow.login(overviewAlts())
    eq(ns.char.cooldowns, nil, "not a leatherworker")
    ns = shakerStart()
    wow.itemNames[SHAKER] = nil
    wow.cooldowns[SHAKER] = { wow.gameTime, 3 * DAY }
    wow.login(overviewAlts())
    eq(ns.char.cooldowns, nil, "no name yet")
    local asked = false
    for _, id in ipairs(wow.itemLoads or {}) do asked = asked or id == SHAKER end
    assert(asked, "its name is requested")
    -- A failed load reads nothing; the name arriving later reads it, with no other event.
    wow.fire("GET_ITEM_INFO_RECEIVED", SHAKER, false)
    eq(ns.char.cooldowns, nil, "failed")
    wow.itemNames[SHAKER] = "Salt Shaker"
    wow.fire("GET_ITEM_INFO_RECEIVED", SHAKER, true)
    eq(ns.char.cooldowns, nil, "the failed request was let go: not asked again until the next scan")
    wow.itemNames[SHAKER] = nil
    wow.fire("BAG_UPDATE_COOLDOWN")
    wow.itemNames[SHAKER] = "Salt Shaker"
    local v = ns.version
    wow.fire("GET_ITEM_INFO_RECEIVED", SHAKER, true)
    eq(ns.char.cooldowns.Leatherworking["Salt Shaker"], NOW + 3 * DAY, "read once it loads")
    assert(ns.version > v, "and shown")
    -- Another item arriving does nothing.
    wow.fire("GET_ITEM_INFO_RECEIVED", 2589, true)
end)

-- Dedicated Study (a Legacy talent; a player's comment, 2026-11-28): a 23 h spell cooldown,
-- kept apart from the professions' and shown only once seen on cooldown.
local STUDY = 1225469

local function studyStart()
    local ns, c = cooldownStart()
    wow.spellNames[STUDY] = "Dedicated Study"
    wow.playerSpells[STUDY] = true
    return ns, c
end

local function cast(id)
    wow.spellCooldowns[id] = { wow.gameTime, 23 * HOUR }
    wow.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-guid", id)
end

test("Dedicated Study: shown once cast, counting down, ready after a respec, gone with the talent", function()
    local ns, c = studyStart()
    eq(c.cooldowns, nil, "never cast: nothing")
    wow.timers = {}
    cast(12345)
    eq(#wow.timers, 0, "another spell: nothing read")
    cast(STUDY)
    eq(c.cooldowns, nil, "read a moment later")
    runTimers()
    eq(c.cooldowns.Legacy["Dedicated Study"], NOW + 23 * HOUR)
    eq(ns.CooldownCell(c, NOW), "23h 0m")
    local all = rowLines(ns)
    assert(all:find("Dedicated Study = ready in 23h 0m", 1, true), all)
    -- With a profession's cooldown too: the cell's click opens the profession, not "Legacy".
    tailoring(3 * DAY)
    wow.fire("TRADE_SKILL_CLOSE")
    c.cooldowns.Alchemy = { ["Transmute: Arcanite"] = NOW + 2 * DAY } -- after Study, before Mooncloth
    local b = cooldownButton(rowOf("Aldric"))
    b.scripts.OnClick(b, "LeftButton")
    eq(AltsForeverCharacterFrame.titleText, "Alchemy", "the first profession's cooldown")
    c.cooldowns.Alchemy = nil
    -- The profession window's reading and a skill change leave it alone.
    wow.tradeskill.recipes[2001].learned = false
    wow.fire("TRADE_SKILL_SHOW")
    wow.profs = { { "Alchemy", 250 } }
    wow.fire("SKILL_LINES_CHANGED")
    eq(c.cooldowns.Legacy["Dedicated Study"], NOW + 23 * HOUR, "not a profession's")
    -- A respec resets it (Forever bug tracker #342): ready.
    wow.spellCooldowns[STUDY] = nil
    wow.fire("TRADE_SKILL_CLOSE")
    wow.fire("TRAIT_CONFIG_UPDATED", 1)
    eq(c.cooldowns.Legacy["Dedicated Study"], NOW)
    eq(ns.CooldownCell(c, NOW), "|cff20ff20Ready|r")
    -- Still ready at the next loading screen; the talent given up: gone.
    wow.fire("PLAYER_ENTERING_WORLD")
    eq(c.cooldowns.Legacy["Dedicated Study"], NOW)
    wow.playerSpells[STUDY] = false
    wow.fire("TRAIT_CONFIG_UPDATED", 1)
    eq(c.cooldowns, nil)
end)

test("Dedicated Study: nothing from the global cooldown, a secret, or before its name is known", function()
    local ns, c = studyStart()
    wow.gameTime = 100000
    wow.spellCooldowns[STUDY] = { wow.gameTime, 1.5 }
    wow.fire("PLAYER_ENTERING_WORLD")
    eq(c.cooldowns, nil, "the global cooldown")
    wow.spellCooldowns[STUDY] = { wow.SECRET, 23 * HOUR }
    wow.fire("PLAYER_ENTERING_WORLD")
    eq(c.cooldowns, nil, "a secret")
    wow.spellNames[STUDY] = nil
    wow.spellCooldowns[STUDY] = { wow.gameTime - 3600, 23 * HOUR }
    wow.fire("PLAYER_ENTERING_WORLD")
    eq(c.cooldowns, nil, "no name yet")
    -- Read at the loading screen once it's known: an hour in.
    wow.spellNames[STUDY] = "Dedicated Study"
    wow.fire("PLAYER_ENTERING_WORLD")
    eq(c.cooldowns.Legacy["Dedicated Study"], NOW + 22 * HOUR)
    -- A reading a few seconds off changes nothing; an unknown talent with no cooldown never adds one.
    wow.gameTime = wow.gameTime + 5
    wow.fire("PLAYER_ENTERING_WORLD")
    eq(c.cooldowns.Legacy["Dedicated Study"], NOW + 22 * HOUR)
end)
