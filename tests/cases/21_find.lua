-- Tests: /af find. Loaded by tests/run.lua.

function findAlts()
    return { v = 2, chars = {
        ["Aldric"] = alt("Aldric", "MAGE", {}),
        ["Vespera Ashward"] = alt("Vespera Ashward", "PALADIN", { bags = { [2589] = 3 }, mail = { [2589] = 159 } }),
        ["Evelyne Ashborne"] = alt("Evelyne Ashborne", "PRIEST", { bags = { [2589] = 17, [2996] = 2 }, bank = { [2589] = 40 } }),
        ["Kadmai Moonwhisper"] = alt("Kadmai Moonwhisper", "HUNTER", { bank = { [4306] = 5 }, equip = { [6125] = 1 } }),
    } }
end

test("/af find lists every matching item, biggest first, with who has how many", function()
    wow.load(FILES)
    wow.itemNames[2589], wow.itemNames[2996], wow.itemNames[4306], wow.itemNames[6125] =
        "Linen Cloth", "Bolt of Linen Cloth", "Silk Cloth", "Brawler's Harness"
    wow.itemLinks = { [2589] = "|cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r" }
    wow.login(findAlts())
    SlashCmdList.ALTSFOREVER("find LINEN")
    local out = table.concat(wow.printed, "\n")
    assert(out:find("Items matching 'LINEN':", 1, true), out)
    local linen = out:find("[Linen Cloth]|h|r 219: [PALADIN]Vespera 162, [PRIEST]Evelyne 57", 1, true)
    local bolt = out:find("[Bolt of Linen Cloth] 2: [PRIEST]Evelyne 2", 1, true)
    assert(linen and bolt and linen < bolt, "linen (clickable) first, then the bolt\n" .. out)
    assert(not out:find("Silk", 1, true), "only matches")
    wow.itemLinks = nil
end)

test("/af find with no match, or nothing typed, says so", function()
    wow.load(FILES)
    wow.itemNames[2589] = "Linen Cloth"
    wow.login(findAlts())
    wow.itemNames[2996], wow.itemNames[4306], wow.itemNames[6125] = "Bolt of Linen Cloth", "Silk Cloth", "Brawler's Harness"
    SlashCmdList.ALTSFOREVER("find mithril")
    assert(wow.printed[#wow.printed]:find("Nothing matching 'mithril'", 1, true), wow.printed[#wow.printed])
    SlashCmdList.ALTSFOREVER("find")
    assert(wow.printed[#wow.printed]:find("/af find linen", 1, true))
end)

test("/af find asks the game for names it hasn't loaded, and searches again a moment later", function()
    wow.load(FILES)
    wow.itemNames[2589] = "Linen Cloth"
    wow.login(findAlts())
    wow.itemLoads = {}
    local before = #wow.printed
    SlashCmdList.ALTSFOREVER("find cloth")
    eq(#wow.printed, before, "nothing printed yet: waiting for names")
    assert(#wow.itemLoads == 3, "asked for the three unknown names")
    wow.itemNames[2996], wow.itemNames[4306] = "Bolt of Linen Cloth", "Silk Cloth" -- 6125 never loads
    wow.timers[#wow.timers]()
    local out = table.concat(wow.printed, "\n")
    assert(out:find("Silk Cloth", 1, true) and out:find("Bolt of Linen Cloth", 1, true), out)
    assert(out:find("still loading", 1, true), "says some names were still missing\n" .. out)
end)

test("/af find shows at most 10 items", function()
    wow.load(FILES)
    local bags = {}
    for i = 1, 14 do
        bags[1000 + i] = i
        wow.itemNames[1000 + i] = "Rough Stone " .. i
    end
    wow.login({ v = 2, chars = { ["Aldric"] = alt("Aldric", "MAGE", {}), ["Stoner"] = alt("Stoner", "WARRIOR", { bags = bags }) } })
    SlashCmdList.ALTSFOREVER("find stone")
    local items = 0
    for _, line in ipairs(wow.printed) do if line:find("^  %[Rough Stone") then items = items + 1 end end
    eq(items, 10)
    assert(wow.printed[#wow.printed]:find("and 4 more", 1, true), wow.printed[#wow.printed])
end)
