-- Tests: Waylaid Crates. Loaded by tests/run.lua.
-- The crate lists its bundles in its own tooltip (checked in game 2026-10-12, item 248689).

CRATE = 248689
CRATE_TEXT = { "Waylaid Crate: Journeyman Curiosities",
    "Use: Fill the crate with any bundle from the following list:\n- 20 Soul Dust\n- 4 Greater Astral Essence\n- 6 Small Glowing Shard\n- 2 Large Glowing Shard",
    "Requires Level 10" }
CD, CW, CG = "|cff9d9d9d", "|cffe0e0e0", "|cff20ff20"

function crateAlts()
    return { v = 2, chars = {
        ["Vespera Ashward"] = alt("Vespera Ashward", "PALADIN", { bags = { [9001] = 12, [9003] = 2 } }),
        ["Tarnia Moonwhisper"] = alt("Tarnia Moonwhisper", "DRUID", { bank = { [9001] = 14 }, mail = { [9003] = 1 } }),
    } }
end

function crateStart()
    local ns = wow.load(FILES)
    wow.itemNames[9001], wow.itemNames[9003] = "Soul Dust", "Small Glowing Shard"
    wow.itemIcons = { [9001] = 111, [9002] = 222, [9003] = 333 }
    wow.setBag(0, 16, { { 9003, 4 } })
    wow.login(crateAlts())
    return ns
end

-- A grid cell list as the plain text shows it: cells two spaces apart.
function crateCells(...) return table.concat({ ... }, "  ") end
function crateIcon(id) return "|T" .. id .. ":16:16:0:0:64:64:5:59:5:59|t" end
CRATE_UNKNOWN = crateIcon("Interface\\Icons\\INV_Misc_QuestionMark")
function crateNum(n) return CW .. n .. "|r" end
function crateNone() return CD .. "-|r" end

test("a Waylaid Crate shows a grid: a column per material, a row per character who has any, and totals", function()
    crateStart()
    local text = textOf(wow.hover(GameTooltip, CRATE, CRATE_TEXT))
    local want = table.concat({
        "Materials on your characters = " .. crateCells(crateIcon(111), CRATE_UNKNOWN, crateIcon(333), CRATE_UNKNOWN),
        CD .. "Needed|r = " .. crateCells(CD .. "20|r", CD .. "4|r", CD .. "6|r", CD .. "2|r"),
        "[MAGE]Aldric = " .. crateCells(crateNone(), crateNone(), crateNum(4), crateNone()),
        "[DRUID]Tarnia = " .. crateCells(crateNum(14), crateNone(), crateNum(1), crateNone()),
        "[PALADIN]Vespera = " .. crateCells(crateNum(12), crateNone(), crateNum(2), crateNone()),
        "Total = " .. crateCells(CG .. "26|r", CD .. "0|r", CG .. "7|r", CD .. "0|r"),
    }, "\n")
    assert(text:find(want, 1, true), "you first, then most; green where there's enough; a question mark for a material nobody has\n" .. text)
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
    wow.itemNames[9003] = nil -- not loaded yet
    local text = textOf(wow.hover(GameTooltip, CRATE, CRATE_TEXT))
    assert(text:find("Total = " .. crateCells(CG .. "26|r", CD .. "0|r", CD .. "0|r", CD .. "0|r"), 1, true), text)
    wow.itemNames[9003] = "Small Glowing Shard"
    text = textOf(wow.hover(GameTooltip, CRATE, CRATE_TEXT))
    assert(text:find("Total = " .. crateCells(CG .. "26|r", CD .. "0|r", CG .. "7|r", CD .. "0|r"), 1, true),
        "looked up again once loaded\n" .. text)
    wow.setBag(0, 16, { { 9003, 4 }, { 9002, 3 } })
    wow.itemNames[9002] = "Large Glowing Shard"
    wow.fire("BAG_UPDATE", 0)
    wow.fire("BAG_UPDATE_DELAYED")
    text = textOf(wow.hover(GameTooltip, CRATE, CRATE_TEXT))
    assert(text:find("[MAGE]Aldric = " .. crateCells(crateNone(), crateNone(), crateNum(4), CG .. "3|r"), 1, true),
        "3 of the 2 needed: green, Aldric can fill it alone\n" .. text)
    assert(text:find("Total = " .. crateCells(CG .. "26|r", CD .. "0|r", CG .. "7|r", CG .. "3|r"), 1, true), text)
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

test("crates list up to 10 characters, then how many more; the totals count everyone", function()
    wow.load(FILES)
    wow.itemNames[9001] = "Soul Dust"
    local chars = {}
    for i = 1, 12 do
        local name = ("Alt%02d Test"):format(i)
        chars[name] = alt(name, "WARRIOR", { bags = { [9001] = i } })
    end
    wow.login({ v = 2, chars = chars })
    local text = textOf(wow.hover(GameTooltip, CRATE, CRATE_TEXT))
    assert(text:find("[WARRIOR]Alt12 = " .. crateNum(12), 1, true), "most first\n" .. text)
    assert(not text:find("[WARRIOR]Alt02 =", 1, true), "the 11th and 12th are left out\n" .. text)
    assert(text:find(CD .. "+2 more|r = ", 1, true), text)
    assert(text:find("Total = " .. CG .. "78|r", 1, true), "1 + 2 + ... + 12\n" .. text)
end)

test("the crate grid is lined up in columns, alongside the crate's own counts", function()
    wow.load(FILES)
    local rights = columnTooltip()
    wow.itemNames[9001] = "Soul Dust"
    wow.setBag(0, 16, { { CRATE, 1 }, { 9001, 5 } })
    wow.login({ v = 2, chars = {
        ["Vespera Ashward"] = alt("Vespera Ashward", "PALADIN", { bags = { [9001] = 12, [CRATE] = 2 } }),
    } })
    local lines = wow.hover(GameTooltip, CRATE, CRATE_TEXT)
    local grid, counts
    for i, l in ipairs(lines) do
        if l[1] == "[PALADIN]Vespera" then grid = grid or i end
        if l[1] == "[PALADIN]Vespera Ashward" then counts = i end
    end
    assert(grid and counts and grid < counts, textOf(lines))
    local function check()
        local cells = cellsOn(rights[grid])
        eq(#cells, 4, "a cell per material on the crate's grid")
        eq(cells[4].text, "|cffe0e0e012|r", "Soul Dust, the first column, furthest from the edge")
        assert(#cellsOn(rights[counts]) > 0, "the crate's own counts keep their columns too")
    end
    check()
    GameTooltip.hooks.OnShow(GameTooltip) -- shown in its final font: both placed again
    check()
end)

test("hovering the same crate again places its grid without measuring it again", function()
    local ns = wow.load(FILES)
    local rights = columnTooltip()
    wow.itemNames[9001], wow.itemNames[CRATE] = "Soul Dust", CRATE_TEXT[1]
    wow.setBag(0, 16, { { CRATE, 1 }, { 9001, 5 } })
    wow.login({ v = 2, chars = {
        ["Vespera Ashward"] = alt("Vespera Ashward", "PALADIN", { bags = { [9001] = 12, [CRATE] = 2 } }),
    } })
    local measured, real = 0, ns.MeasureColumns
    ns.MeasureColumns = function(...) measured = measured + 1 return real(...) end
    local function grid()
        local lines = wow.hover(GameTooltip, CRATE, CRATE_TEXT)
        for i, l in ipairs(lines) do
            if l[1] == "[PALADIN]Vespera" then return cellsOn(rights[i]) end
        end
    end
    local first = grid()
    local once = measured
    assert(once > 0 and #first == 4, "measured and placed on the first hover")
    local again = grid()
    eq(measured, once, "nothing measured again")
    eq(#again, 4, "the same grid")
    for i = 1, 4 do
        eq(again[i].x, first[i].x) eq(again[i].width, first[i].width) eq(again[i].text, first[i].text)
    end
    -- Your bags change: the grid is worked out afresh.
    wow.setBag(0, 16, { { CRATE, 1 }, { 9001, 7 } })
    wow.fire("BAG_UPDATE", 0)
    wow.fire("BAG_UPDATE_DELAYED")
    local after = grid()
    assert(measured > once, "measured again after a change")
    eq(after[4].text, "|cffe0e0e012|r", "Vespera's own count still in its column")
end)
