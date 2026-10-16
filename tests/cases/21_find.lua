-- Tests: /af find (the search window) and turning item counts off. Loaded by tests/run.lua.

function findAlts()
    return { v = 2, chars = {
        ["Aldric"] = alt("Aldric", "MAGE", {}),
        ["Vespera Ashward"] = alt("Vespera Ashward", "PALADIN", { bags = { [2589] = 3 }, mail = { [2589] = 159 } }),
        ["Evelyne Ashborne"] = alt("Evelyne Ashborne", "PRIEST", { bags = { [2589] = 17, [2996] = 2 }, bank = { [2589] = 40 } }),
        ["Kadmai Moonwhisper"] = alt("Kadmai Moonwhisper", "HUNTER", { bank = { [4306] = 5 }, equip = { [6125] = 1 } }),
    } }
end

test("/af find opens the search, as /af search does", function()
    local ns = wow.load(FILES)
    wow.item(2589, "Linen Cloth", {})
    wow.login(findAlts())
    SlashCmdList.ALTSFOREVER("find linen")
    eq(AltsForeverSearchFrame:IsShown(), true)
    eq(AltsForeverSearchBox.text, "linen")
    local found = ns.SearchMatches("linen")
    eq(found[1].id, 2589)
    eq(found[1].total, 219, "3 + 159 in the mail + 17 + 40 in the bank")
end)

test("item counts in tooltips can be turned off (another addon shows them); the rest of the tooltip stays", function()
    local ns = wow.load(FILES)
    wow.setBag(0, 16, { { 2589, 3 } })
    wow.login({ v = 2, chars = { ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { bags = { [2589] = 7 } }) } })
    assert(textOf(wow.hover(GameTooltip, 2589)):find("Total = 10", 1, true))
    SlashCmdList.ALTSFOREVER("counts")
    eq(AltsForeverDB.countsOff, true)
    local text = textOf(wow.hover(GameTooltip, 2589))
    assert(not text:find("Total", 1, true) and not text:find("Tarn", 1, true), "no counts\n" .. text)
    -- Crate lines aren't counts: they stay.
    wow.itemNames[2589] = "Linen Cloth"
    text = textOf(wow.hover(GameTooltip, 248690, { "Waylaid Crate: Apprentice Textiles",
        "Use: Fill the crate with any bundle from the following list:\n- 20 Linen Cloth", "Requires Level 10" }))
    assert(text:find("Materials on your characters", 1, true), text)
    ns.ShowOptionsMenu(UIParent)
    pageBox("Show item counts").setSelected()
    eq(AltsForeverDB.countsOff, nil)
    assert(textOf(wow.hover(GameTooltip, 2589)):find("Total = 10", 1, true), "back on")
end)
