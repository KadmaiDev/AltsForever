-- Alts Forever columns: lines up tooltip rows in columns. Used by the item tooltip
-- (Tooltip.lua), the XP and reputation bar tooltips (Bars.lua) and the overview's
-- character tooltip (Overview.lua).
local ADDON, ns = ...

local floor, ipairs, type = math.floor, ipairs, type


-- Columns in tooltips. Tooltip text isn't monospaced, so columns are laid out with font
-- strings of our own on the tooltip: each cell is a font string set to its column's
-- width, justified in it, and anchored a measured distance from the right edge of its
-- line. The game positions them, so they line up exactly in any font. The line's own
-- right-hand text becomes a transparent spacer that makes the tooltip wide enough.
--  * Padding the text with spacers was tried first and couldn't be made exact: the
--    tooltip draws spacers at a width that depends on the font (84-90% of what any
--    font string measures), and rows came out up to 7 units apart (2026-09-26).
--  * Text widths are measured in a hidden font string of our own on the tooltip; they
--    agree with the tooltip's lines. The lines' own widths can read as secret values
--    while Blizzard's secure code builds a tooltip, so they're never used.
--  * Every width and font read is checked with issecretvalue first; if anything can't
--    be read, the plain text stays.
--  * Cells are made once per tooltip and reused, and hidden when the tooltip is cleared
--    or hidden.
local BLANK = "Interface\\AddOns\\" .. ADDON .. "\\media\\blank.tga"
local GAP = 10
local RESERVE = 1.25 -- spacers draw at 84-100% of their width: reserve enough room

local function Spacer(width)
    width = floor(width + 0.5)
    if width < 1 then return "" end
    return "|T" .. BLANK .. ":1:" .. width .. "|t"
end
ns.Spacer = Spacer

local issecretvalue = issecretvalue or function() return false end
local measurers = {} -- [tooltip] = hidden font string for measuring
local pools = {}     -- [tooltip] = { used = n, [i] = cell font string }
local lineTexts = {} -- [tooltip] = { TextLeft = { [line] = fs }, TextRight = { ... } }

-- A tooltip line's font string (e.g. GameTooltipTextRight12), remembered so repeat
-- hovers don't build its name again. Lines are made as the tooltip first needs them, so
-- a missing one isn't remembered.
function ns.LineText(tt, side, line)
    local byTip = lineTexts[tt]
    if not byTip then
        byTip = { TextLeft = {}, TextRight = {} }
        lineTexts[tt] = byTip
    end
    local fs = byTip[side][line]
    if not fs then
        local name = tt.GetName and tt:GetName()
        fs = name and _G[name .. side .. line]
        byTip[side][line] = fs
    end
    return fs
end

-- A font as read from a font string, if it can be used (not secret).
function ns.UsableFont(font, size, flags)
    return font and not issecretvalue(font) and not issecretvalue(size) and not issecretvalue(flags)
end

local function Width(m, s)
    m:SetText(s)
    local w = m:GetStringWidth()
    if issecretvalue(w) or type(w) ~= "number" then return nil end
    return w
end

-- Measures rows of cells (rows[i][col], nil or "" for an empty cell) for a column spec
-- (spec[col] = { gap = space before the column, justify = "LEFT" or "RIGHT" }). Returns
-- a layout { widths, right (each column's distance from the line's right edge), reserve
-- (the spacer that makes room), font, size, flags }, or nil if it can't be measured.
function ns.MeasureColumns(tt, rows, spec, font, size, flags)
    if not (ns.UsableFont(font, size, flags) and tt.CreateFontString) then return nil end
    local m = measurers[tt]
    if not m then
        m = tt:CreateFontString(nil, "BACKGROUND")
        m:SetPoint("TOPLEFT")
        m:SetAlpha(0)
        measurers[tt] = m
    end
    m:SetFont(font, size, flags)
    local columns, widths = #spec, {}
    for col = 1, columns do widths[col] = 0 end
    for _, cells in ipairs(rows) do
        for col = 1, columns do
            local s = cells[col]
            if s and s ~= "" then
                local w = Width(m, s)
                if not w then
                    m:SetText("")
                    return nil
                end
                if w > widths[col] then widths[col] = w end
            end
        end
    end
    m:SetText("")
    local right, x = {}, 0
    for col = columns, 1, -1 do
        right[col] = x
        x = x + widths[col] + (col > 1 and spec[col].gap or 0)
    end
    return { widths = widths, right = right, reserve = Spacer(x * RESERVE + 1),
        font = font, size = size, flags = flags }
end

-- Hides a tooltip's cells.
function ns.ClearColumns(tt)
    local pool = pools[tt]
    if not pool then return end
    for i = 1, pool.used do pool[i]:Hide() end
    pool.used = 0
end

local function ClearOnHide(tt) ns.ClearColumns(tt) end

-- Places rows' cells on lines first, first + 1, ... with a layout from MeasureColumns,
-- replacing whatever cells the tooltip had. Returns true if a line's text changed (the
-- tooltip then needs a Show to fit it).
function ns.PlaceColumns(tt, first, rows, spec, layout)
    local pool = pools[tt]
    if not pool then
        pool = { used = 0 }
        pools[tt] = pool
        if tt.HookScript then
            tt:HookScript("OnTooltipCleared", ClearOnHide)
            tt:HookScript("OnHide", ClearOnHide)
        end
    end
    ns.ClearColumns(tt)
    local used, changed = 0, false
    local widths, right = layout.widths, layout.right
    for i, cells in ipairs(rows) do
        local line = ns.LineText(tt, "TextRight", first + i - 1)
        if not line then break end
        local current = line:GetText()
        if issecretvalue(current) or current ~= layout.reserve then
            line:SetText(layout.reserve)
            changed = true
        end
        for col = 1, #spec do
            local s = cells[col]
            if s and s ~= "" then
                used = used + 1
                local fs = pool[used]
                if not fs then
                    fs = tt:CreateFontString(nil, "ARTWORK")
                    fs:SetWordWrap(false)
                    fs:SetTextColor(1, 1, 1)
                    pool[used] = fs
                end
                fs:SetFont(layout.font, layout.size, layout.flags)
                fs:SetWidth(widths[col] + 1)
                fs:SetJustifyH(spec[col].justify or "RIGHT")
                fs:ClearAllPoints()
                fs:SetPoint("RIGHT", line, "RIGHT", -right[col], 0)
                fs:SetText(s)
                fs:Show()
            end
        end
    end
    pool.used = used
    return changed
end

-- Lines up the right-hand columns of the rows added from line `first` on; leaves the
-- plain text if the tooltip's text can't be measured. Each row is { name, value... };
-- labels[col] is text shown before that column's value (e.g. "rested"). Columns are
-- right-aligned, except those marked in `lefts` (e.g. notes of different lengths).
-- Our lines take the font of the tooltip's second line (its body text): a line the
-- tooltip hasn't needed before gets a new font string, which a UI addon that restyled
-- the existing ones (EllesmereUI) hasn't reached, so it would show in the game's font.
local function Align(tt, first, rows, labels, lefts)
    local body = ns.LineText(tt, "TextLeft", 2)
    local font, size, flags
    if body and body.GetFont then font, size, flags = body:GetFont() end
    if not ns.UsableFont(font, size, flags) then return end
    for line = first - 1, first + #rows - 1 do
        for _, side in ipairs({ "TextLeft", "TextRight" }) do
            local text = ns.LineText(tt, side, line)
            if text and text.SetFont then text:SetFont(font, size, flags) end
        end
    end
    -- A label becomes its own column just before its value.
    local spec, cellRows = {}, {}
    local columns = #rows[1] - 1
    for col = 1, columns do
        local justify = lefts and lefts[col] and "LEFT" or "RIGHT"
        if labels[col] then
            spec[#spec + 1] = { gap = GAP, justify = "RIGHT" }
            spec[#spec + 1] = { gap = 0, justify = justify }
        else
            spec[#spec + 1] = { gap = GAP, justify = justify }
        end
    end
    for i, row in ipairs(rows) do
        local cells = {}
        for col = 1, columns do
            if labels[col] then cells[#cells + 1] = labels[col] end
            cells[#cells + 1] = row[col + 1]
        end
        cellRows[i] = cells
    end
    local layout = ns.MeasureColumns(tt, cellRows, spec, font, size, flags)
    if layout then ns.PlaceColumns(tt, first, cellRows, spec, layout) end
end

ns.AlignColumns = Align
