-- Tests: columns. Loaded by tests/run.lua, which provides test, eq, wow, FILES and the
-- other shared helpers; helpers defined here are shared with the other files too.
---------------------------------------------------------------------------
-- Tooltip columns: cells of our own placed on the tooltip, a measured distance from
-- each line's right edge.
-- The fake font: size / 2 per visible character, icons 12 wide.
function textWidth(t, size)
    local w = 0
    t = t:gsub("|T.-|t", function() w = w + 12 return "" end)
    t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return w + #t * (size or 12) / 2
end

-- GameTooltip with named line font strings, hooks, and cells it can make. Returns its
-- right-hand line font strings. wow.secretWidths makes widths read as secret (a number
-- only issecretvalue can tell), as in game while Blizzard's code builds a tooltip.
function columnTooltip()
    local tt = GameTooltip
    tt.GetName = function() return "GameTooltip" end
    tt.NumLines = function(self) return #self.lines end
    tt.hooks = {}
    tt.HookScript = function(self, script, fn)
        local prev = self.hooks[script]
        self.hooks[script] = prev and function(...) prev(...) fn(...) end or fn
    end
    tt.cells = {}
    wow.measured = 0
    tt.CreateFontString = function(self)
        local fs = { shown = true, size = 12,
            SetFont = function(f, _, s) f.size = s end,
            SetText = function(f, t) f.text = t end,
            GetStringWidth = function(f)
                wow.measured = wow.measured + 1
                if wow.secretWidths then
                    wow.SECRET = 4242.5
                    return 4242.5
                end
                return textWidth(f.text or "", f.size)
            end,
            SetPoint = function(f, p, rel, rp, x) f.point = { p, rel, rp, x } end,
            ClearAllPoints = function(f) f.point = nil end,
            SetWidth = function(f, w) f.width = w end,
            SetJustifyH = function(f, j) f.justify = j end,
            SetWordWrap = function() end, SetTextColor = function() end, SetAlpha = function() end,
            Show = function(f) f.shown = true end, Hide = function(f) f.shown = false end }
        self.cells[#self.cells + 1] = fs
        return fs
    end
    local rights = {}
    for i = 1, 20 do
        local function line()
            return { size = 12, GetFont = function(f) return "font", f.size, "" end,
                SetFont = function(f, _, s) f.size = s end,
                SetText = function(f, t) f.text = t end, GetText = function(f) return f.text end }
        end
        _G["GameTooltipTextLeft" .. i] = line()
        rights[i] = line()
        _G["GameTooltipTextRight" .. i] = rights[i]
    end
    return rights
end

function clearTooltipLines()
    for i = 1, 20 do _G["GameTooltipTextLeft" .. i], _G["GameTooltipTextRight" .. i] = nil, nil end
    GameTooltip.CreateFontString, GameTooltip.GetName = nil, nil
end

-- The visible cells on a line, nearest the right edge first: { x = distance of the
-- cell's right edge from the line's right edge, width, justify, text }.
function cellsOn(line)
    local found = {}
    for _, c in ipairs(GameTooltip.cells) do
        if c.shown and c.point and c.point[2] == line then
            found[#found + 1] = { x = -c.point[4], width = c.width, justify = c.justify, text = c.text, size = c.size }
        end
    end
    table.sort(found, function(a, b) return a.x < b.x end)
    return found
end

-- Checks rows line up: cells at the same place (distance from the right edge) have the
-- same width and alignment in every row. Returns the number of columns used.
function checkColumns(lines)
    local columns, n = {}, 0
    for i, line in ipairs(lines) do
        for _, c in ipairs(cellsOn(line)) do
            local col = columns[c.x]
            if col then
                eq(c.width, col.width, "row " .. i .. ", cell at " .. c.x .. ": width")
                eq(c.justify, col.justify, "row " .. i .. ", cell at " .. c.x .. ": justified")
            else
                columns[c.x] = c
                n = n + 1
            end
        end
    end
    return n
end

function columnAlts()
    wow.setBag(0, 16, { [1] = { 100, 23 } })
    wow.login({ v = 2, chars = {
        ["Big"] = alt("Big", "PRIEST", { bags = { [100] = 30 }, mail = { [100] = 1000 } }),
        ["Mid"] = alt("Mid", "DRUID", { bank = { [100] = 5 } }),
        ["Three"] = alt("Three", "ROGUE", { bags = { [100] = 4 }, bank = { [100] = 6 }, mail = { [100] = 7 } }),
    } })
end

test("item tooltip: icons, numbers and counts in columns, placed from the right edge", function()
    wow.load(FILES)
    local rights = columnTooltip()
    columnAlts()
    local lines = wow.hover(GameTooltip, 100)
    eq(lines[2][1], "Total"); eq(lines[2][2], 1075)
    local rows = {}
    for i = 3, #lines do rows[#rows + 1] = rights[i] end
    eq(#rows, 4)
    -- 3 places (icon + number each) and the count: 7 columns.
    eq(checkColumns(rows), 7)
    -- You (Aldric: bags 23): one place, in the columns nearest the count.
    local mine = cellsOn(rights[3])
    eq(#mine, 3); eq(mine[1].text, "23"); eq(mine[1].x, 0, "count at the edge")
    eq(mine[2].justify, "RIGHT", "number right-aligned"); eq(mine[3].justify, "LEFT", "icon")
    -- Each line's own right text only makes room.
    for _, r in ipairs(rows) do assert(r.text:find("blank.tga", 1, true), "room for the cells") end
    -- Cleared (the tooltip shows something else): every cell hidden.
    GameTooltip.hooks.OnTooltipCleared(GameTooltip)
    for _, c in ipairs(GameTooltip.cells) do
        if c.point and c.point[1] == "RIGHT" then eq(c.shown, false) end -- not the measuring one
    end
    clearTooltipLines()
end)

test("item tooltip columns are placed again in the font a UI addon shows them in", function()
    wow.load(FILES)
    local rights = columnTooltip()
    columnAlts()
    local lines = wow.hover(GameTooltip, 100)
    local before = cellsOn(rights[5])
    -- EllesmereUI sets its own font on every line when the tooltip is shown.
    for i = 1, #lines do
        rights[i].size = 16
        _G["GameTooltipTextLeft" .. i].size = 16
    end
    local shows = 0
    GameTooltip.Show = function(self) shows = shows + 1 self.shown = true end
    GameTooltip.hooks.OnShow(GameTooltip)
    local after = cellsOn(rights[5])
    eq(after[1].size, 16, "cells in the new font")
    assert(after[2].x > before[2].x, "measured again: wider columns")
    local rows = {}
    for i = 3, #lines do rows[#rows + 1] = rights[i] end
    eq(checkColumns(rows), 7)
    eq(shows, 1, "shown again so it resizes")
    GameTooltip.hooks.OnShow(GameTooltip)
    eq(shows, 1, "nothing changes the next time it's shown in that font")
    clearTooltipLines()
end)

test("item tooltip columns are measured once per item and font, then reused", function()
    wow.load(FILES)
    columnTooltip()
    wow.login({ v = 2, chars = {
        ["Big"] = alt("Big", "PRIEST", { bags = { [100] = 30 } }),
        ["Mid"] = alt("Mid", "DRUID", { bank = { [100] = 5 }, bags = { [101] = 2 } }),
    } })
    wow.hover(GameTooltip, 100)
    assert(wow.measured > 0, "measured the first time")
    local first = wow.measured
    wow.hover(GameTooltip, 100)
    eq(wow.measured, first, "same item: not measured again")
    wow.hover(GameTooltip, 101)
    local afterOther = wow.measured
    wow.hover(GameTooltip, 100)
    eq(wow.measured, afterOther, "back to the first item: still cached")
    clearTooltipLines()
end)

test("secret widths (while Blizzard builds a tooltip): the plain text stays, no error", function()
    wow.load(FILES)
    local rights = columnTooltip()
    wow.secretWidths = true
    columnAlts()
    local lines = wow.hover(GameTooltip, 100)
    eq(lines[3][2]:find("·", 1, true) ~= nil or lines[3][2]:find("23", 1, true) ~= nil, true, "plain text")
    for i = 3, #lines do eq(#cellsOn(rights[i]), 0, "no cells on line " .. i) end
    -- Readable again: the next hover places them.
    wow.secretWidths = nil
    wow.hover(GameTooltip, 100)
    eq(#cellsOn(rights[3]), 3)
    -- A secret font is left alone.
    _G["GameTooltipTextLeft3"].GetFont = function() return wow.SECRET, 12, "" end
    GameTooltip.hooks.OnShow(GameTooltip)
    clearTooltipLines()
end)

test("the XP bar's alts are in columns: level, XP, and rested with its label", function()
    wow.load(FILES)
    wow.now = NOW
    local bar = blizzardXPBar()
    local rights = columnTooltip()
    wow.login(overviewAlts())
    wow.fire("PLAYER_ENTERING_WORLD")
    GameTooltip.Show = function(self) self.shown = true end
    bar.scripts.OnEnter(bar)
    -- Experience, Your characters, High, Low.
    eq(GameTooltip.lines[3][1], "[PRIEST]High")
    eq(checkColumns({ rights[3], rights[4] }), 4, "level, XP, 'rested', rested")
    local high = cellsOn(rights[3])
    assert(high[2].text:find("rested", 1, true), "the label is its own column")
    eq(high[4].text, "40")
    -- Lines added after the tooltip was shown take its body font (line 2's).
    eq(_G["GameTooltipTextLeft3"].size, 12)
    clearTooltipLines()
end)

test("overview row tooltip: professions in columns, skill right-aligned and notes left", function()
    wow.load(FILES)
    wow.now = NOW
    local rights = columnTooltip()
    GameTooltip.Show = function(self) self.shown = true end
    local saved = overviewAlts()
    saved.recipeInfo = { Tailoring = { a = "250;A;", b = "150;B;", c = "210;C;,1:1" } }
    saved.chars["High"].recipes = { Tailoring = { a = true, b = true, c = true } }
    saved.chars["High"].profs = { Tailoring = 200, Enchanting = 80, Cooking = 1 }
    wow.login(saved)
    SlashCmdList.ALTSFOREVER("")
    local row = overviewRows()[3] -- High
    row.scripts.OnEnter(row)
    local profLines = {}
    for i, l in ipairs(GameTooltip.lines) do
        if l[1] == "Cooking" or l[1] == "Enchanting" or l[1] == "Tailoring" then profLines[#profLines + 1] = rights[i] end
    end
    eq(#profLines, 3, "sorted by name: Cooking, Enchanting, Tailoring")
    eq(checkColumns(profLines), 2)
    local tailoring = cellsOn(profLines[3])
    eq(tailoring[1].justify, "LEFT", "note left-aligned"); eq(tailoring[2].justify, "RIGHT", "skill right-aligned")
    assert(tailoring[1].text:find("(2 skill-up recipes)", 1, true), tailoring[1].text)
    clearTooltipLines()
end)
