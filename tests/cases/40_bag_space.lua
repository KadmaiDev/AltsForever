-- The overview's Bags and Bank columns: free slots of all slots per character, each bag
-- or bank tab on hover, sums per group and a summary under the titles.

local TRAVELER, HERB = 4500, 22250

-- A bag's slots as the scanner saves them: `free` empty ones, the rest holding something;
-- [0] = the bag's own item.
function bagSlots(size, free, item)
    local t = { [0] = item }
    for i = 1, size do t[i] = i <= free and 0 or 2589001 end
    return t
end

function spaceAlts()
    local saved = overviewAlts()
    local high, low = saved.chars.High, saved.chars.Low
    high.layout = {
        [0] = bagSlots(16, 2),
        [1] = bagSlots(16, 5, TRAVELER),
        [2] = bagSlots(12, 12, HERB),
        [-1] = bagSlots(32, 32), -- the keyring: only keys go in, so not counted
        [6] = bagSlots(28, 10),
        [7] = bagSlots(28, 0),
    }
    high.bank, high.bankAt = {}, NOW - 2 * DAY
    low.layout = { [0] = bagSlots(16, 0), [-1] = bagSlots(32, 31) }
    return saved
end

function spaceStart(saved)
    return sortStart(saved or spaceAlts(), function()
        wow.itemNames[TRAVELER], wow.itemClass[TRAVELER] = "Traveler's Backpack", 1
        wow.items[TRAVELER] = { sub = 0, subName = "Bag" }
        wow.itemNames[HERB], wow.itemClass[HERB] = "Cenarian Herb Bag", 1
        wow.items[HERB] = { sub = 2, subName = "Herb Bag" } -- Classic's subclass 2
        wow.itemQuality[HERB] = 2
    end)
end

function spaceRow(name)
    for _, r in ipairs(overviewRows()) do
        if cell(r, 1):find(name, 1, true) then return r end
    end
end

function tipLines()
    local out = {}
    for _, l in ipairs(GameTooltip.lines) do out[#out + 1] = table.concat(l, " = ") end
    return out
end

function hasLine(lines, text)
    for _, l in ipairs(lines) do
        if l:find(text, 1, true) then return true end
    end
    return false
end

local ORANGE = "|cffff8000"
local AMMO, SOUL, PROFESSION, REAGENT_BLUE = "|cffc79c6e", "|cff9482c9", "|cff6fcf6f", "|cff66b2ff"

test("the overview's Bags and Bank columns: free slots of all, the keyring left out", function()
    spaceStart()
    local high, low, far = spaceRow("High"), spaceRow("Low"), spaceRow("Far")
    eq(cell(high, 12), "7" .. G .. "/32|r", "2 + 5 free of 16 + 16; the herb bag's 12 and the keyring's 32 not counted")
    eq(cell(high, 13), "10" .. G .. "/56|r", "both bank tabs")
    eq(cell(low, 12), ORANGE .. "0|r" .. G .. "/16|r", "full: orange, the overview's attention colour")
    eq(cell(low, 13), G .. "?|r", "bank never visited")
    eq(cell(far, 12), G .. "?|r", "no slots recorded")
    -- A tenth or less free is orange too; more is plain.
    local _, ns = sortStart()
    eq(ns.SpaceCell(4, 40), ORANGE .. "4|r" .. G .. "/40|r")
    eq(ns.SpaceCell(5, 40), "5" .. G .. "/40|r")
end)

test("pointing at a Bags cell lists each bag, its kind and empty bag slots; a click opens their bags", function()
    local _, ns = spaceStart()
    local row = spaceRow("High")
    local bags, bank = row.spaces[1], row.spaces[2]
    eq(bags.which, "bags"); eq(bank.which, "bank")
    bags.scripts.OnEnter(bags)
    eq(row.highlightLocked, true, "the row stays lit while its cell is pointed at")
    local lines = GameTooltip.lines
    assert(lines[2][1]:find("|t Backpack$"), "the backpack first, with its picture: " .. lines[2][1])
    eq(lines[2][2], "2" .. G .. "/16|r")
    eq(lines[3][1], "Traveler's Backpack", "a plain bag: no kind")
    eq(lines[3][2], "5" .. G .. "/16|r")
    eq(lines[4][1], "Cenarian Herb Bag" .. PROFESSION .. "  Herb Bag|r", "a bag that holds only some things says which, in its colour")
    eq(lines[4][2], "12" .. G .. "/12|r", "empty: nothing in it yet")
    assert(lines[5][1]:find("|t Empty bag slot$")); eq(lines[5][2], "-")
    assert(lines[6][1]:find("|t Empty bag slot$"), "bag slots 3 and 4")
    assert(lines[7][1]:find("|t Empty reagent bag slot$"), "and the reagent bag slot"); eq(lines[7][2], "-")
    eq(lines[8][1], "Total"); eq(lines[8][2], "7 of 32 free", "the herb bag left out")
    eq(lines[9][1], G .. "Not counted as free space: " .. PROFESSION .. "Profession bag|r" .. G .. "|r")
    assert(not hasLine(tipLines(), "Keyring"), "no keyring")
    assert(hasLine(tipLines(), "Click to open their bags"))
    bags.scripts.OnLeave(bags)
    eq(row.highlightLocked, false)

    bank.scripts.OnEnter(bank)
    lines = GameTooltip.lines
    eq(lines[2][1], "Bank"); eq(lines[2][2], "10" .. G .. "/28|r")
    eq(lines[3][1], "Tab 2"); eq(lines[3][2], ORANGE .. "0|r" .. G .. "/28|r")
    eq(lines[4][2], "10 of 56 free")
    assert(hasLine(tipLines(), "Bank last visited: 2d ago"), table.concat(tipLines(), " | "))

    local low = spaceRow("Low").spaces[2]
    low.scripts.OnEnter(low)
    assert(hasLine(tipLines(), "Bank not scanned yet - visit a banker"))

    local opened
    ns.ShowBags = function(key, which) opened = key .. " " .. which end
    bags.scripts.OnClick(bags, "LeftButton")
    eq(opened, "High bags")
    bank.scripts.OnClick(bank, "LeftButton")
    eq(opened, "High bank")
    wow.menu = nil
    bank.scripts.OnClick(bank, "RightButton")
    assert(wow.menu, "a right-click opens the character's menu, as on the rest of the row")
    eq(opened, "High bank", "and opens nothing else")
end)

test("Bags and Bank sort fewest free first; their titles add up every character", function()
    local click = spaceStart()
    click("bags")
    local names = overviewNames()
    eq(names:sub(1, 9), "Low, High", "fewest free first, unknown last")
    local f = AltsForeverFrame
    f.sorts.bags.scripts.OnEnter(f.sorts.bags)
    local lines = tipLines()
    assert(hasLine(lines, "All characters = 7 of 48 free"), table.concat(lines, " | "))
    assert(hasLine(lines, "Bag slots with no bag: [ROGUE]Low 5, [PRIEST]High 3"), "in the overview's order: " .. table.concat(lines, " | "))
    assert(hasLine(lines, "Click to sort by this column"))
    f.sorts.bank.scripts.OnEnter(f.sorts.bank)
    lines = tipLines()
    assert(hasLine(lines, "All characters = 10 of 56 free"), table.concat(lines, " | "))
    assert(hasLine(lines, "Bank not visited yet: "), table.concat(lines, " | "))
    assert(hasLine(lines, "Low") and hasLine(lines, "Far"))
end)

test("Bags and Bank: the row tooltip says both; group headings add them up; the columns can be hidden", function()
    local saved = spaceAlts()
    saved.chars.High.faction, saved.chars.Low.faction, saved.chars.Far.faction = "Horde", "Horde", "Alliance"
    spaceStart(saved)
    local row = spaceRow("High")
    row.scripts.OnEnter(row)
    assert(hasLine(tipLines(), "Bags = 7 of 32 free"), table.concat(tipLines(), " | "))
    assert(hasLine(tipLines(), "Bank = 10 of 56 free"))
    local horde
    for _, f in ipairs(wow.frames) do
        if rawget(f, "texts") and f.shown and f.label.text:find("Horde", 1, true) then horde = f end
    end
    assert(horde, "a Horde heading")
    eq(horde.texts[12].text, "7" .. G .. "/48|r", "the group's bags")
    eq(horde.texts[13].text, "10" .. G .. "/56|r", "the bank of those who visited it")

    columnsMenu("Bags").setSelected()
    eq(row.cells[12].shown, false)
    eq(row.spaces[1].shown, false, "nothing to point at in a hidden column")
    eq(row.spaces[2].shown, true)
    columnsMenu("Show all columns").fn()
    eq(row.spaces[1].shown, true)
end)

test("an open overview's Bags and Bank cells follow bag and bank scans", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.setBag(0, 16, { [1] = { 100, 20 } })
    wow.setBag(6, 28, { [1] = { 100, 5 } })
    wow.login(overviewAlts())
    SlashCmdList.ALTSFOREVER("")
    eq(cell(spaceRow("Aldric"), 12), "15" .. G .. "/16|r")
    eq(cell(spaceRow("Aldric"), 13), G .. "?|r", "bank not visited")
    wow.setBag(0, 16, { [1] = { 100, 20 }, [2] = { 200, 1 } })
    wow.fire("BAG_UPDATE", 0)
    wow.fire("BAG_UPDATE_DELAYED")
    eq(cell(spaceRow("Aldric"), 12), "14" .. G .. "/16|r", "an item looted")
    wow.fire("BANKFRAME_OPENED")
    eq(cell(spaceRow("Aldric"), 13), "27" .. G .. "/28|r", "the bank visited")
    wow.setBag(6, 28, {})
    wow.setBag(0, 16, { [1] = { 100, 20 }, [2] = { 200, 1 }, [3] = { 100, 5 } })
    wow.fire("BAG_UPDATE", 6)
    wow.fire("BAG_UPDATE", 0)
    wow.fire("BAG_UPDATE_DELAYED")
    eq(cell(spaceRow("Aldric"), 12), "13" .. G .. "/16|r", "moved from the bank")
    eq(cell(spaceRow("Aldric"), 13), "28" .. G .. "/28|r")
    wow.setBag(1, 10, {})
    wow.fire("BAG_CONTAINER_UPDATE")
    eq(cell(spaceRow("Aldric"), 12), "23" .. G .. "/26|r", "a bag put in")
end)

test("the Bags and Bank titles list every character's bags in a grid: each bag's slots, '-' for none, then free", function()
    spaceStart()
    local f = AltsForeverFrame
    f.sorts.bags.scripts.OnEnter(f.sorts.bags)
    local lines = tipLines()
    assert(hasLine(lines, "Slots in each bag, then free of all"), table.concat(lines, " | "))
    assert(hasLine(lines, "[ROGUE]Low = -/-/-/-/-   " .. ORANGE .. "0|r" .. G .. "/16|r"), "four bag slots and the reagent slot; the backpack left out")
    assert(hasLine(lines, "[PRIEST]High = 16/" .. PROFESSION .. "12|r/-/-/-   7" .. G .. "/32|r"), table.concat(lines, " | "))
    assert(hasLine(lines, G .. "Not counted as free space: " .. PROFESSION .. "Profession bag|r" .. G .. "|r"), "the legend")
    assert(not hasLine(lines, "Far ="), "nothing recorded: left out")
    f.sorts.bank.scripts.OnEnter(f.sorts.bank)
    lines = tipLines()
    assert(hasLine(lines, "Slots in each bank bag, then free of all"))
    assert(hasLine(lines, "[PRIEST]High = 28   10" .. G .. "/56|r"), table.concat(lines, " | "))
    assert(not hasLine(lines, "Low ="), "bank never visited: only in the not-visited line")
    assert(not hasLine(lines, "Not counted as free space"), "no special bags in any bank: no legend")
end)

test("a bank visit records each bank bag and how many bank bag slots are bought; the Bank cell names them", function()
    local MOONCLOTH = 14155
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.itemNames[MOONCLOTH] = "Mooncloth Bag"
    wow.setBag(0, 16, {})
    wow.setBag(6, 28, { [1] = { 100, 5 } }) -- tab 1: the bank itself
    wow.setBag(7, 10, {}) -- tab 2: a bag in the first bank bag slot
    -- tab 3 bought but no bag in it: no slots
    wow.setBag(Enum.BagIndex.Characterbanktab, 9, { [2] = { MOONCLOTH, 1 } })
    wow.bankBought, wow.bankMax = 3, 7
    wow.login(overviewAlts())
    wow.fire("BANKFRAME_OPENED")
    local c = AltsForeverDB.chars.Aldric
    eq(c.layout[7][0], MOONCLOTH, "the bag in bank bag slot 1")
    eq(c.layout[6][0], nil, "tab 1 is the bank, not a bag")
    eq(c.bankBought, 3)
    SlashCmdList.ALTSFOREVER("")
    local bank = spaceRow("Aldric").spaces[2]
    bank.scripts.OnEnter(bank)
    local lines = GameTooltip.lines
    eq(lines[2][1], "Bank"); eq(lines[2][2], "27" .. G .. "/28|r")
    eq(lines[3][1], "Mooncloth Bag"); eq(lines[3][2], "10" .. G .. "/10|r")
    assert(lines[4][1]:find("|t Empty bank bag slot$"), "bought, no bag: " .. lines[4][1]); eq(lines[4][2], "-")
    eq(lines[5][2], "37 of 38 free")
    assert(hasLine(tipLines(), "Bank bag slots not bought yet: 4"), table.concat(tipLines(), " | "))
    local f = AltsForeverFrame
    f.sorts.bank.scripts.OnEnter(f.sorts.bank)
    assert(hasLine(tipLines(), "Aldric = 10/-   37" .. G .. "/38|r"), table.concat(tipLines(), " | "))
    eq(ns.BagsSectionName(c, 7), "Mooncloth Bag", "the bags window's By bag heading")
    eq(ns.BagsSectionName(c, 6), "Bank")

    -- Buying another bank bag slot, with the bank still open: no contents change, only the tabs.
    GameTooltip:Hide()
    wow.bankBought = 4
    wow.fire("BANK_TABS_CHANGED", 0)
    eq(c.bankBought, 4, "the new slot is counted")
    bank.scripts.OnEnter(bank)
    lines = GameTooltip.lines
    assert(lines[5][1]:find("|t Empty bank bag slot$"), "a second empty bought slot: " .. tostring(lines[5][1]))
    assert(hasLine(tipLines(), "Bank bag slots not bought yet: 3"), table.concat(tipLines(), " | "))
    -- Closed, a tab change isn't read (the bank can't be read then).
    wow.fire("BANKFRAME_CLOSED")
    wow.bankBought = 5
    wow.fire("BANK_TABS_CHANGED", 0)
    eq(c.bankBought, 4)
end)

test("the bank grid under the title lines up: bag columns and free/total in the same place for rows of different lengths", function()
    local saved = spaceAlts()
    saved.chars.Low.layout[6] = bagSlots(28, 3)
    saved.chars.Low.bankBought = 4 -- the bank and three bank bag slots, none with a bag
    saved.chars.Low.bank = {}
    spaceStart(saved)
    local rights = columnTooltip()
    local f = AltsForeverFrame
    f.sorts.bank.scripts.OnEnter(f.sorts.bank)
    local byName = {}
    for i, l in ipairs(GameTooltip.lines) do
        local name = tostring(l[1])
        if name:find("Low", 1, true) then byName.low = rights[i] end
        if name:find("High", 1, true) then byName.high = rights[i] end
    end
    assert(byName.low and byName.high, "a row each")
    eq(checkColumns({ byName.low, byName.high }) >= 3, true, "free/total plus bag columns")
    local low, high = cellsOn(byName.low), cellsOn(byName.high)
    eq(low[1].text, "3" .. G .. "/28|r"); eq(high[1].text, "10" .. G .. "/56|r")
    eq(low[1].x, high[1].x, "free/total in one column")
    local function texts(cells)
        local t = {}
        for i = #cells, 1, -1 do if cells[i].text ~= "" then t[#t + 1] = cells[i].text end end
        return table.concat(t, " ")
    end
    eq(texts(low), "- - - 3" .. G .. "/28|r", "three bought slots with no bag; the bank's own 28 left out")
    eq(texts(high), "28 10" .. G .. "/56|r")
    local function at(cells, text)
        for _, c in ipairs(cells) do if c.text == text then return c.x end end
    end
    local function farthest(cells, text)
        local far
        for _, c in ipairs(cells) do if c.text == text and (not far or c.x > far) then far = c.x end end
        return far
    end
    eq(farthest(low, "-"), at(high, "28"), "the first bank bag slot in the same column for both")
    clearTooltipLines()
end)

test("quivers, ammo pouches and soul bags aren't free space: left out of the counts, coloured, and named in the legend; the reagent bag coloured but counted", function()
    local QUIVER, POUCH, SOUL_BAG, REAGENT = 2662, 2663, 21340, 222
    local saved = spaceAlts()
    local low = saved.chars.Low
    low.layout[1] = bagSlots(16, 16, QUIVER)
    low.layout[2] = bagSlots(10, 4, SOUL_BAG)
    low.layout[5] = bagSlots(6, 6, REAGENT) -- the reagent bag: counted (trade goods)
    low.layout[6] = bagSlots(28, 3)
    low.layout[7] = bagSlots(8, 8, POUCH) -- a bank bag slot holding an ammo pouch
    low.bank, low.bankBought = {}, 2
    spaceStart(saved)
    wow.itemClass[QUIVER], wow.items[QUIVER] = 11, { sub = 2, subName = "Quiver" }
    wow.itemClass[POUCH], wow.items[POUCH] = 11, { sub = 3, subName = "Ammo Pouch" }
    wow.itemClass[SOUL_BAG], wow.items[SOUL_BAG] = 1, { sub = 1, subName = "Soul Bag" }
    wow.itemClass[REAGENT], wow.items[REAGENT] = 1, { sub = 11, subName = "Reagent Bag" }
    wow.itemNames[QUIVER], wow.itemNames[POUCH], wow.itemNames[SOUL_BAG] = "Light Quiver", "Small Ammo Pouch", "Felcloth Bag"
    wow.itemNames[REAGENT] = "Reagent Pouch"
    SlashCmdList.ALTSFOREVER("")
    SlashCmdList.ALTSFOREVER("")
    local row = spaceRow("Low")
    eq(cell(row, 12), "6" .. G .. "/22|r", "backpack 0 of 16 and the reagent bag's 6; not the quiver's or soul bag's")
    eq(cell(row, 13), "3" .. G .. "/28|r", "the bank's own slots; not the ammo pouch's")
    local bags = row.spaces[1]
    bags.scripts.OnEnter(bags)
    local lines = tipLines()
    assert(hasLine(lines, "Light Quiver" .. AMMO .. "  Quiver|r = 16"), table.concat(lines, " | "))
    assert(hasLine(lines, "Felcloth Bag" .. SOUL .. "  Soul Bag|r = 4"), "each still listed with its own free slots")
    assert(hasLine(lines, "Reagent Pouch" .. REAGENT_BLUE .. "  Reagent Bag|r"), "the reagent bag: its kind in its colour")
    assert(hasLine(lines, "Total = 6 of 22 free"))
    assert(hasLine(lines, G .. "Not counted as free space: " .. AMMO .. "Quiver or ammo pouch|r, " .. SOUL .. "Soul bag|r" .. G .. "|r"),
        table.concat(lines, " | "))
    assert(hasLine(lines, G .. "Counted as free space: " .. REAGENT_BLUE .. "Reagent bag|r" .. G .. "|r"), table.concat(lines, " | "))
    local f = AltsForeverFrame
    f.sorts.bags.scripts.OnEnter(f.sorts.bags)
    lines = tipLines()
    assert(hasLine(lines, "[ROGUE]Low = " .. AMMO .. "16|r/" .. SOUL .. "10|r/-/-/" .. REAGENT_BLUE .. "6|r   6" .. G .. "/22|r"), table.concat(lines, " | "))
    assert(hasLine(lines, G .. "Not counted as free space: " .. AMMO .. "Quiver or ammo pouch|r, " .. SOUL .. "Soul bag|r, "
        .. PROFESSION .. "Profession bag|r" .. G .. "|r"), "every family in the grid, in one order: " .. table.concat(lines, " | "))
    assert(hasLine(lines, G .. "Counted as free space: " .. REAGENT_BLUE .. "Reagent bag|r" .. G .. "|r"), "the reagent bag's key")
    f.sorts.bank.scripts.OnEnter(f.sorts.bank)
    lines = tipLines()
    assert(hasLine(lines, "[ROGUE]Low = " .. AMMO .. "8|r   3" .. G .. "/28|r"), table.concat(lines, " | "))
    assert(not hasLine(lines, "Counted as free space"), "no reagent bag in the bank: no key for it")
end)
