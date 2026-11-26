-- Tests: Alts Forever in tooltips, as a whole and by part. Loaded by tests/run.lua, which
-- provides test, eq, wow, FILES and the other shared helpers; helpers defined here are
-- shared with the other files too.
---------------------------------------------------------------------------

-- A character with something for every part: counts, a recipe they craft, crate
-- material, gold, still levelling. Returns ns and the XP bar.
function tipsStart()
    local ns = wow.load(FILES)
    wow.now = NOW
    local bar = blizzardXPBar()
    wow.profs = { { "Engineering", 107 } }
    wow.setBag(0, 16, { { 2589, 3 } })
    wow.itemNames[2589] = "Linen Cloth"
    wow.login({ v = 2, chars = { ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { bags = { [2589] = 7 }, money = 5000,
        level = 20, xp = 100, xpMax = 1000, crafts = { Engineering = { [SQUIRREL_ITEM] = true } } }) } })
    engineeringWindow({})
    wow.fire("PLAYER_ENTERING_WORLD")
    return ns, bar
end

-- Which of our parts each tooltip shows now, as "counts craft recipe crate gold bars".
function tipsShown(bar)
    local shown = {}
    local function has(lines, s) return textOf(lines):find(s, 1, true) ~= nil end
    if has(wow.hover(GameTooltip, 2589), "Total = 10") then shown[#shown + 1] = "counts" end
    if craftLine(wow.hover(GameTooltip, SQUIRREL_ITEM)) then shown[#shown + 1] = "craft" end
    local recipe = wow.recipeItem(SQUIRREL, "Schematic: Mechanical Squirrel", "Engineering", 75)
    if has(wow.hover(GameTooltip, SQUIRREL, recipe), "Can learn") then shown[#shown + 1] = "recipe" end
    local crate = { "Waylaid Crate: Apprentice Textiles",
        "Use: Fill the crate with any bundle from the following list:\n- 20 Linen Cloth", "Requires Level 10" }
    if has(wow.hover(GameTooltip, 248690, crate), "Materials on your characters") then shown[#shown + 1] = "crate" end
    GameTooltip:Hide()
    ContainerFrameCombinedBagsGoldButton:Enter()
    if GameTooltip:IsShown() then shown[#shown + 1] = "gold" end
    GameTooltip:Hide()
    bar.scripts.OnEnter(bar)
    if GameTooltip:IsShown() then shown[#shown + 1] = "bars" end
    GameTooltip:Hide()
    return table.concat(shown, " ")
end

test("Show Alts Forever in tooltips: off, nothing is added to any tooltip; on again, each part as it was set", function()
    local ns, bar = tipsStart()
    eq(tipsShown(bar), "counts craft recipe crate gold bars", "all on by default")
    SlashCmdList.ALTSFOREVER("crates")
    eq(AltsForeverDB.cratesOff, true)
    SlashCmdList.ALTSFOREVER("tooltips")
    eq(AltsForeverDB.tooltipsOff, true)
    eq(tipsShown(bar), "", "nothing at all")
    -- A part switched while it's all off says so.
    wow.printed = {}
    SlashCmdList.ALTSFOREVER("counts")
    assert(table.concat(wow.printed, "\n"):find("/af tooltips", 1, true), table.concat(wow.printed, "\n"))
    SlashCmdList.ALTSFOREVER("counts")
    SlashCmdList.ALTSFOREVER("tooltips")
    eq(AltsForeverDB.tooltipsOff, nil)
    eq(tipsShown(bar), "counts craft recipe gold bars", "crates kept off")
end)

test("each part of the tooltips turns off on its own", function()
    local ns, bar = tipsStart()
    for _, case in ipairs({
        { "counts", "countsOff", "craft recipe crate gold bars" },
        { "crafting", "canCraftOff", "counts recipe crate gold bars" },
        { "recipes", "recipeTipsOff", "counts craft crate gold bars" },
        { "crates", "cratesOff", "counts craft recipe gold bars" },
        { "gold", "goldTipOff", "counts craft recipe crate bars" },
        { "bars", "barsOff", "counts craft recipe crate gold" },
    }) do
        SlashCmdList.ALTSFOREVER(case[1])
        eq(AltsForeverDB[case[2]], true, case[1])
        eq(tipsShown(bar), case[3], case[1])
        SlashCmdList.ALTSFOREVER(case[1])
        eq(AltsForeverDB[case[2]], nil, case[1] .. " back on")
    end
    eq(tipsShown(bar), "counts craft recipe crate gold bars")
end)

test("Show Alts Forever in tooltips off: no upgrades on a trainer's recipes either", function()
    local items = upItems()
    local boe = upItem(5070, "Heavy Woolen Cloak", { sub = 1, loc = "INVTYPE_CLOAK", stats = { ITEM_MOD_STAMINA_SHORT = 3 } })
    upStart({ ["Tarn Moon"] = upHunter(items) })
    wow.trainerLinks = { [4] = boe }
    local text = { "Tailoring: Heavy Woolen Cloak", "Heavy Woolen Cloak" }
    assert(upRows(wow.hoverTrainer(GameTooltip, 4, 8880, text)) ~= "")
    SlashCmdList.ALTSFOREVER("tooltips")
    eq(upRows(wow.hoverTrainer(GameTooltip, 4, 8880, text)), "")
end)

-- The parts of item tooltips as a grid on the page, each Always, Shift or Never (the
-- owner's idea, 2026-11-26, from a player's request for Skill-ups and the Total on Shift).
local PARTS = "Item counts | Total line | Can craft | Skill-ups | Recipe status | Upgrades | Waylaid Crate materials | Other rulesets and factions"

function gridState(f)
    local out = {}
    for _, part in ipairs(f.modes and AltsForeverOptionsPanel and { "counts", "total", "crafting", "skillups", "recipes", "upgrades", "crates", "rulesets" } or {}) do
        local row, pick = f.modes[part], "-"
        for _, mode in ipairs({ "always", "shift", "never" }) do
            if row[mode]:GetChecked() then pick = pick == "-" and mode or pick .. "+" .. mode end
        end
        out[#out + 1] = pick
    end
    return table.concat(out, " ")
end

test("Options page: the tooltip parts are a grid under Show Alts Forever in tooltips, greyed while it's off", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    local f = showOptionsPage()
    local master = f.checks[1]
    eq(master.label.text, "Show Alts Forever in tooltips")
    local names = {}
    for _, part in ipairs(ns.TIP_PARTS) do names[#names + 1] = f.modes[part].label.text end
    eq(table.concat(names, " | "), PARTS)
    eq(f.modeHeads[1].text .. " " .. f.modeHeads[2].text .. " " .. f.modeHeads[3].text, "Always Shift Never")
    eq(gridState(f), "always always always always always always always never", "one choice each; other rulesets Never by default")
    local gold = f.checks[2]
    eq(gold.label.text, "Show alts' gold on bag money")
    -- Hovering a choice says what the part is and what the choices mean.
    local b = f.modes.total.shift
    b.scripts.OnEnter(b)
    eq(GameTooltip.lines[1][1], "Total line: Shift")
    assert(GameTooltip.lines[2][1]:find("only while you hold Shift", 1, true), GameTooltip.lines[2][1])
    -- A pick moves the one choice; the setting changes with it.
    pickMode("total", "shift")
    eq(AltsForeverDB.tipShift.total, true)
    pickMode("counts", "never")
    eq(AltsForeverDB.countsOff, true)
    eq(gridState(f), "never shift always always always always always never")
    -- Tooltips off: the grid and the boxes under it grey out, keeping their choices.
    master:SetChecked(false)
    master.scripts.OnClick(master)
    eq(AltsForeverDB.tooltipsOff, true)
    for _, part in ipairs(ns.TIP_PARTS) do
        for _, mode in ipairs({ "always", "shift", "never" }) do eq(f.modes[part][mode]:IsEnabled(), false, part) end
    end
    eq(gold:IsEnabled(), false)
    eq(gridState(f), "never shift always always always always always never")
    master:SetChecked(true)
    master.scripts.OnClick(master)
    eq(f.modes.counts.always:IsEnabled(), true)
    eq(gold:IsEnabled(), true)
    eq(f.checks[4]:IsEnabled(), true, "the extras are never greyed")
end)

test("Can craft and recipe status: the old single switch turns both off, then each turns on by itself and stays", function()
    local ns, bar = tipsStart()
    local saved = AltsForeverDB
    saved.craftTipsOff = true -- 1.9.1 and before: one switch for both
    wow.load(FILES)
    wow.login(saved)
    eq(AltsForeverDB.craftTipsOff, nil, "the old switch is folded in")
    eq(AltsForeverDB.canCraftOff, true); eq(AltsForeverDB.recipeTipsOff, true)
    SlashCmdList.ALTSFOREVER("recipes")
    eq(AltsForeverDB.recipeTipsOff, nil, "recipe status back on")
    saved = AltsForeverDB
    wow.load(FILES)
    wow.login(saved)
    eq(AltsForeverDB.canCraftOff, true, "Can craft stays off")
    eq(AltsForeverDB.recipeTipsOff, nil, "recipe status stays on after the next login")
end)

test("Can craft and recipe status are two rows on the Options page, each with its own setting", function()
    wow.load(FILES)
    wow.login(nil)
    showOptionsPage()
    pickMode("crafting", "never")
    eq(AltsForeverDB.canCraftOff, true); eq(AltsForeverDB.recipeTipsOff, nil)
    eq(pageMode("crafting", "never"):GetChecked(), true); eq(pageMode("recipes", "always"):GetChecked(), true)
    pickMode("recipes", "never")
    eq(AltsForeverDB.recipeTipsOff, true)
end)

-- Skill-ups and the Total line only while Shift is held (a player's request, 2026-11-26).
function shiftStart()
    local ns = wow.load(FILES)
    wow.profs = { { "Engineering", 80 } }
    local saved = recipeAlts()
    saved.recipeInfo = { Engineering = { ["mechanical squirrel"] = "100;Mechanical Squirrel;,2589:2" } }
    saved.chars["Brakka"].crafts = { Engineering = { [SQUIRREL_ITEM] = "mechanical squirrel" } }
    saved.chars["Brakka"].profs.Engineering = 90
    saved.chars["Brakka"].bags = { [LINEN] = 4 }
    -- On the other faction: shown only with "Other rulesets and factions".
    saved.chars["Zug Zug"] = alt("Zug Zug", "SHAMAN", { faction = "Horde", bags = { [LINEN] = 2 } })
    wow.setBag(0, 16, { { LINEN, 3 } })
    wow.login(saved)
    return ns
end

-- What the Linen Cloth tooltip shows now.
function shiftShown()
    local text = textOf(wow.hover(GameTooltip, LINEN))
    local out = {}
    if text:find("Brakka", 1, true) then out[#out + 1] = "counts" end
    if text:find("Total = 7", 1, true) then out[#out + 1] = "total" end
    if text:find("Skill-ups", 1, true) then out[#out + 1] = "skillups" end
    if text:find("Zug Zug", 1, true) then out[#out + 1] = "others" end
    return table.concat(out, " ")
end

test("tooltip parts on Shift: left out of item tooltips until Shift is held", function()
    shiftStart()
    eq(shiftShown(), "counts total skillups", "by default everything but other rulesets")
    pickMode("total", "shift")
    pickMode("skillups", "shift")
    eq(AltsForeverDB.tipShift.total, true); eq(AltsForeverDB.tipShift.skillups, true)
    eq(shiftShown(), "counts", "without Shift: no Total, no Skill-ups; each character's count stays")
    wow.shift = true
    eq(shiftShown(), "counts total skillups", "Shift held: all of it")
    wow.shift = false
    eq(shiftShown(), "counts")
    -- Counts themselves on Shift: nothing from the counts until it's held.
    pickMode("counts", "shift")
    eq(shiftShown(), "")
    wow.shift = true
    eq(shiftShown(), "counts total skillups")
    wow.shift = false
    pickMode("counts", "always")
    -- Never wins over Shift: back to Shift brings it back.
    pickMode("skillups", "never")
    eq(AltsForeverDB.skillupsOff, true); eq(AltsForeverDB.tipShift.skillups, nil)
    wow.shift = true
    eq(shiftShown(), "counts total")
    wow.shift = false
end)

test("other rulesets and factions on Shift: their characters join the tooltip while it's held", function()
    shiftStart()
    pickMode("rulesets", "always")
    eq(AltsForeverDB.otherRulesets, true)
    eq(shiftShown(), "counts total skillups others")
    pickMode("rulesets", "shift")
    eq(AltsForeverDB.otherRulesets, true, "counted by search and the bags window as before")
    eq(shiftShown(), "counts total skillups", "cached lines without them")
    wow.shift = true
    eq(shiftShown(), "counts total skillups others", "rebuilt once Shift is held")
    wow.shift = false
    eq(shiftShown(), "counts total skillups", "and again when let go")
    pickMode("rulesets", "never")
    eq(AltsForeverDB.otherRulesets, nil); eq(AltsForeverDB.tipShift, nil)
    wow.shift = true
    eq(shiftShown(), "counts total skillups")
    wow.shift = false
end)

test("/af shift lists every part's choice, and /af shift <part> puts one on Shift or back", function()
    shiftStart()
    SlashCmdList.ALTSFOREVER("shift")
    local text = table.concat(wow.printed, "\n")
    assert(text:find("Item counts: Always", 1, true), text)
    assert(text:find("Other rulesets and factions: Never", 1, true), text)
    SlashCmdList.ALTSFOREVER("shift total")
    eq(AltsForeverDB.tipShift.total, true)
    assert(wow.printed[#wow.printed]:find("Total line in item tooltips: Shift.", 1, true), wow.printed[#wow.printed])
    eq(shiftShown(), "counts skillups")
    SlashCmdList.ALTSFOREVER("shift total")
    eq(AltsForeverDB.tipShift, nil)
    assert(wow.printed[#wow.printed]:find("Total line in item tooltips: Always.", 1, true))
    -- A part that was Never goes to Shift.
    SlashCmdList.ALTSFOREVER("skillups")
    eq(AltsForeverDB.skillupsOff, true)
    SlashCmdList.ALTSFOREVER("shift skillups")
    eq(AltsForeverDB.skillupsOff, nil); eq(AltsForeverDB.tipShift.skillups, true)
end)

test("the dev builds' single Shift switch becomes Skill-ups and Total on Shift", function()
    shiftStart()
    local saved = AltsForeverDB
    saved.shiftDetails = true
    wow.load(FILES)
    wow.login(saved)
    eq(AltsForeverDB.shiftDetails, nil)
    eq(AltsForeverDB.tipShift.skillups, true); eq(AltsForeverDB.tipShift.total, true)
end)

test("Shift pressed over a slot in a window of ours redraws its tooltip; the game's own are left alone", function()
    local ns = wow.load(FILES)
    wow.setBag(0, 4, { [1] = { 100, 20 } })
    wow.login(nil)
    AltsForeverDB.tipShift = { total = true }
    SlashCmdList.ALTSFOREVER("bags")
    local slot = AltsForeverBagsFrame.slots[1]
    slot.scripts.OnEnter(slot)
    eq(GameTooltip.itemID, 100)
    GameTooltip.itemID = nil
    wow.fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
    eq(GameTooltip.itemID, 100, "hovered again: redrawn with Shift")
    GameTooltip.itemID = nil
    wow.fire("MODIFIER_STATE_CHANGED", "LCTRL", 1)
    eq(GameTooltip.itemID, nil, "other keys do nothing")

    -- A tooltip of the game's: nothing of ours runs.
    local theirs = CreateFrame("Button", "ContainerFrame1Item1", UIParent)
    local entered = 0
    theirs:SetScript("OnEnter", function() entered = entered + 1 end)
    GameTooltip:SetOwner(theirs)
    GameTooltip:Show()
    wow.fire("MODIFIER_STATE_CHANGED", "LSHIFT", 0)
    eq(entered, 0)

    -- Setting off: ours aren't redrawn either.
    AltsForeverDB.tipShift = nil
    slot.scripts.OnEnter(slot)
    GameTooltip.itemID = nil
    wow.fire("MODIFIER_STATE_CHANGED", "RSHIFT", 1)
    eq(GameTooltip.itemID, nil)
end)
