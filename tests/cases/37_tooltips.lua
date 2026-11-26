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

test("Options page: the tooltip parts sit indented under Show Alts Forever in tooltips, greyed while it's off", function()
    wow.load(FILES)
    wow.login(nil)
    local f = showOptionsPage()
    local master = f.checks[1]
    eq(master.label.text, "Show Alts Forever in tooltips")
    local subs = {}
    for i = 2, 10 do subs[#subs + 1] = f.checks[i] end
    eq(master.point[4], -2)
    eq(subs[1].point[4], 20, "indented under it")
    eq(subs[2].point[4], 0, "then in line with the one above")
    local rulesets
    for _, check in ipairs(f.checks) do
        if check.label.text == "Show other rulesets and factions" then rulesets = check end
    end
    subs[#subs + 1] = rulesets
    for _, check in ipairs(subs) do eq(check:IsEnabled(), true) end
    master:SetChecked(false)
    master.scripts.OnClick(master)
    eq(AltsForeverDB.tooltipsOff, true)
    for _, check in ipairs(subs) do
        eq(check:IsEnabled(), false, check.label.text)
        local offByDefault = check == rulesets or check.label.text == "Skill-ups and totals only while Shift is held"
        eq(check:GetChecked(), not offByDefault, "keeps its tick (other rulesets and Shift only are off by default)")
    end
    master:SetChecked(true)
    master.scripts.OnClick(master)
    for _, check in ipairs(subs) do eq(check:IsEnabled(), true) end
    eq(f.checks[11]:IsEnabled(), true, "the extras are never greyed")
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

test("Can craft and recipe status are two boxes on the Options page, each with its own setting", function()
    wow.load(FILES)
    wow.login(nil)
    showOptionsPage()
    local craft, recipe = pageBox("Show Can craft"), pageBox("Show recipe status")
    craft.setSelected()
    eq(AltsForeverDB.canCraftOff, true); eq(AltsForeverDB.recipeTipsOff, nil)
    eq(craft.isSelected(), false); eq(recipe.isSelected(), true)
    recipe.setSelected()
    eq(AltsForeverDB.recipeTipsOff, true)
end)

-- Skill-ups and the Total line only while Shift is held (a player's request, 2026-11-26).
test("Skill-ups and totals only while Shift is held: shorter item tooltips, the full ones with Shift", function()
    wow.load(FILES)
    wow.profs = { { "Engineering", 80 } }
    local saved = recipeAlts()
    saved.recipeInfo = { Engineering = { ["mechanical squirrel"] = "100;Mechanical Squirrel;,2589:2" } }
    saved.chars["Brakka"].crafts = { Engineering = { [SQUIRREL_ITEM] = "mechanical squirrel" } }
    saved.chars["Brakka"].profs.Engineering = 90
    saved.chars["Brakka"].bags = { [LINEN] = 4 }
    wow.setBag(0, 16, { { LINEN, 3 } })
    wow.login(saved)
    local function shown()
        local text = textOf(wow.hover(GameTooltip, LINEN))
        return (text:find("Total = 7", 1, true) and "total" or "-") .. " "
            .. (text:find("Skill-ups", 1, true) and "skillups" or "-") .. " "
            .. (text:find("Brakka", 1, true) and "counts" or "-")
    end
    eq(shown(), "total skillups counts", "off by default: everything shows")
    eq(pageBox("Skill-ups and totals only while Shift is held").isSelected(), false)

    pageBox("Skill-ups and totals only while Shift is held").setSelected()
    eq(AltsForeverDB.shiftDetails, true)
    eq(shown(), "- - counts", "without Shift: no Total, no Skill-ups; each character's count stays")
    wow.shift = true
    eq(shown(), "total skillups counts", "Shift held: all of it")
    wow.shift = false
    eq(shown(), "- - counts")

    -- The columns still line up under the names when the Total line is left out.
    local lines = wow.hover(GameTooltip, LINEN)
    assert(not textOf(lines):find("Total", 1, true))

    SlashCmdList.ALTSFOREVER("shift")
    eq(AltsForeverDB.shiftDetails, nil, "/af shift turns it off")
    assert(wow.printed[#wow.printed]:find("always shown", 1, true), wow.printed[#wow.printed])
    eq(shown(), "total skillups counts")
    SlashCmdList.ALTSFOREVER("shift")
    eq(AltsForeverDB.shiftDetails, true)
    assert(wow.printed[#wow.printed]:find("only while Shift is held", 1, true))
end)

test("Shift pressed over a slot in a window of ours redraws its tooltip; the game's own are left alone", function()
    local ns = wow.load(FILES)
    wow.setBag(0, 4, { [1] = { 100, 20 } })
    wow.login(nil)
    AltsForeverDB.shiftDetails = true
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
    AltsForeverDB.shiftDetails = nil
    slot.scripts.OnEnter(slot)
    GameTooltip.itemID = nil
    wow.fire("MODIFIER_STATE_CHANGED", "RSHIFT", 1)
    eq(GameTooltip.itemID, nil)
end)
