-- Tests: Waylaid Crates. Loaded by tests/run.lua.
-- The crate lists its bundles in its own tooltip (checked in game 2026-10-12, item 248689).

CRATE = 248689
CRATE_TEXT = { "Waylaid Crate: Journeyman Curiosities",
    "Use: Fill the crate with any bundle from the following list:\n- 20 Soul Dust\n- 4 Greater Astral Essence\n- 6 Small Glowing Shard\n- 2 Large Glowing Shard",
    "Requires Level 10" }

function crateAlts()
    return { v = 2, chars = {
        ["Vespera Ashward"] = alt("Vespera Ashward", "PALADIN", { bags = { [9001] = 12, [9003] = 2 } }),
        ["Tarnia Moonwhisper"] = alt("Tarnia Moonwhisper", "DRUID", { bank = { [9001] = 14 }, mail = { [9003] = 1 } }),
    } }
end

function crateStart()
    local ns = wow.load(FILES)
    wow.itemNames[9001], wow.itemNames[9003] = "Soul Dust", "Small Glowing Shard"
    wow.setBag(0, 16, { { 9003, 4 } })
    wow.login(crateAlts())
    return ns
end

test("a Waylaid Crate lists each bundle with who has the materials and the total", function()
    crateStart()
    local text = textOf(wow.hover(GameTooltip, CRATE, CRATE_TEXT))
    assert(text:find("Materials on your characters", 1, true), text)
    assert(text:find("20 Soul Dust = [DRUID]Tarnia |cffe0e0e014|r · [PALADIN]Vespera |cffe0e0e012|r    |cff20ff2026|r", 1, true),
        "enough between them: green total, most first\n" .. text)
    assert(text:find("|cffe0e0e04 Greater Astral Essence|r = |cff9d9d9d0|r", 1, true), "nobody has any\n" .. text)
    assert(text:find("6 Small Glowing Shard = [MAGE]Aldric |cffe0e0e04|r · [PALADIN]Vespera |cffe0e0e02|r    |cff20ff207|r", 1, true),
        "you first, then only who's needed to make 6: Tarnia's 1 isn't\n" .. text)
    assert(text:find("|cffe0e0e02 Large Glowing Shard|r = |cff9d9d9d0|r", 1, true), text)
    local soul = text:find("Soul Dust", 1, true)
    local astral = text:find("Astral", 1, true)
    assert(soul < astral, "in the crate's order")
end)

test("other items get no crate lines", function()
    crateStart()
    local text = textOf(wow.hover(GameTooltip, 9001, { "Soul Dust", "Use: Something.\n- not a bundle" }))
    assert(not text:find("Materials on your characters", 1, true), text)
    text = textOf(wow.hover(GameTooltip, 9002, { "A list", "- 20 Soul Dust" }))
    assert(not text:find("Materials on your characters", 1, true), "not under a Use: line\n" .. text)
end)

test("crate totals follow your bags, and names that load later", function()
    crateStart()
    wow.uncached = wow.uncached or {}
    wow.itemNames[9003] = nil -- not loaded yet
    local text = textOf(wow.hover(GameTooltip, CRATE, CRATE_TEXT))
    assert(text:find("6 Small Glowing Shard|r = |cff9d9d9d0|r", 1, true), text)
    wow.itemNames[9003] = "Small Glowing Shard"
    text = textOf(wow.hover(GameTooltip, CRATE, CRATE_TEXT))
    assert(text:find("|cff20ff207|r", 1, true), "looked up again once loaded\n" .. text)
    wow.setBag(0, 16, { { 9003, 4 }, { 9002, 3 } })
    wow.itemNames[9002] = "Large Glowing Shard"
    wow.fire("BAG_UPDATE", 0)
    wow.fire("BAG_UPDATE_DELAYED")
    text = textOf(wow.hover(GameTooltip, CRATE, CRATE_TEXT))
    assert(text:find("2 Large Glowing Shard = [MAGE]Aldric |cffe0e0e03|r    |cff20ff203|r", 1, true), text)
end)

test("a crate first seen half-loaded (auction house) gets its lines once the tooltip fills in", function()
    crateStart()
    wow.uncached[CRATE] = true
    local text = textOf(wow.hover(GameTooltip, CRATE, { "Retrieving item information" }))
    assert(not text:find("Materials on your characters", 1, true), text)
    wow.uncached[CRATE] = nil
    wow.itemSpell[CRATE] = 1302999
    text = textOf(wow.hover(GameTooltip, CRATE, { "Waylaid Crate: Journeyman Curiosities", "Requires Level 10" }))
    assert(not text:find("Materials on your characters", 1, true), "loaded, but its Use: line not yet")
    text = textOf(wow.hover(GameTooltip, CRATE, CRATE_TEXT))
    assert(text:find("Materials on your characters", 1, true), "read again, not remembered as empty\n" .. text)
end)

test("crates name only who's needed to fill a bundle, or everyone (up to 3) when it's short", function()
    wow.load(FILES)
    wow.itemNames[9001], wow.itemNames[9002], wow.itemNames[9003] = "Soul Dust", "Large Glowing Shard", "Small Glowing Shard"
    wow.login({ v = 2, chars = {
        ["Evelyne Ashborne"] = alt("Evelyne Ashborne", "PRIEST", { bags = { [9001] = 46, [9003] = 1 } }),
        ["Carissa Ashward"] = alt("Carissa Ashward", "MAGE", { bags = { [9001] = 26, [9003] = 1 } }),
        ["Brom Ironhorn"] = alt("Brom Ironhorn", "SHAMAN", { bags = { [9001] = 13, [9002] = 1 } }),
        ["Sabine Blackthorn"] = alt("Sabine Blackthorn", "WARLOCK", { bank = { [9002] = 1 } }),
        ["Zed Last"] = alt("Zed Last", "ROGUE", { mail = { [9002] = 1, [9003] = 1 } }),
        ["Yan Also"] = alt("Yan Also", "HUNTER", { bags = { [9002] = 1, [9003] = 1 } }),
    } })
    local text = textOf(wow.hover(GameTooltip, CRATE, CRATE_TEXT))
    assert(text:find("20 Soul Dust = [PRIEST]Evelyne |cffe0e0e046|r    |cff20ff2085|r", 1, true), "one is enough\n" .. text)
    assert(text:find("2 Large Glowing Shard = [SHAMAN]Brom |cffe0e0e01|r · [WARLOCK]Sabine |cffe0e0e01|r    |cff20ff204|r", 1, true),
        "enough after two\n" .. text)
    assert(text:find("|cffe0e0e06 Small Glowing Shard|r = [MAGE]Carissa |cffe0e0e01|r · [PRIEST]Evelyne |cffe0e0e01|r · [HUNTER]Yan |cffe0e0e01|r|cffe0e0e0 · +1 more|r    4", 1, true),
        "not enough: up to 3, then how many more\n" .. text)
    assert(text:find("|cffe0e0e04 Greater Astral Essence|r = |cff9d9d9d0|r", 1, true), text)
end)
