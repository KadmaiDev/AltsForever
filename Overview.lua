-- Alts Forever overview: a window (/af) listing every character with level, rested
-- XP, gold, professions, location, time played and when they were last played. It's
-- only built the first time it's opened, and only refreshes while it's showing.
local ADDON, ns = ...

local floor, max, pairs, time = math.floor, math.max, pairs, time
local ipairs, select, type = ipairs, select, type
local GetCoinTextureString = C_CurrencyInfo.GetCoinTextureString

local GREY = "|cff9d9d9d"
local MAX_PROFESSION = 300 -- the last rank's maximum on Forever (Classic ruleset)
local ROW_HEIGHT = 20
local COLUMNS = {
    { title = "Character", width = 180 },
    { title = "Level", width = 80 },
    { title = "Rested", width = 70 },
    { title = "Gold", width = 120, right = true },
    -- Each main profession gets a name column and a right-aligned skill column, so
    -- the skill numbers line up. The gap separates it from the right-aligned gold.
    { title = "Professions", width = 104, gap = 16 },
    { title = "", width = 34, right = true },
    { title = "", width = 104, gap = 16 },
    { title = "", width = 34, right = true },
    { title = "Mail", width = 60, gap = 16 },
    { title = "Zone", width = 140 },
    { title = "Played", width = 70, right = true },
    { title = "Last seen", width = 80, right = true },
}
local LIGHT = "|cffc0c0c0"

---------------------------------------------------------------------------
-- Text helpers (no UI, so they can be tested)
---------------------------------------------------------------------------
function ns.FormatAgo(seconds)
    if seconds < 3600 then return "<1h" end
    if seconds < 86400 then return floor(seconds / 3600) .. "h ago" end
    return floor(seconds / 86400) .. "d ago"
end

local function Duration(seconds)
    local d, h = floor(seconds / 86400), floor(seconds % 86400 / 3600)
    if d > 0 then return d .. "d " .. h .. "h" end
    return max(h, 1) .. "h"
end

function ns.LevelText(c)
    if not c.level then return GREY .. "?|r" end
    if c.level >= ns.MaxLevel() or not c.xpMax or c.xpMax == 0 then return tostring(c.level) end
    -- Multiply first: 5700 / 10000 * 100 is 56.99... in floating point.
    return c.level .. "  " .. GREY .. floor(c.xp * 100 / c.xpMax) .. "%|r"
end

-- Rested as a share of a level; blue when full, "-" at max level, "?" if not recorded yet.
function ns.RestedText(c, now)
    if not c.level then return GREY .. "?|r" end
    local rested, cap = ns.RestedNow(c, now)
    if not rested then return GREY .. "-|r" end
    local pct = floor(rested / c.xpMax * 100 + 0.5)
    if rested >= cap then return "|cff4da6ff" .. pct .. "%|r" end
    return pct .. "%"
end

-- The four profession cells: name, skill, name, skill.
function ns.ProfCells(c)
    local p = c.profs
    if not p then return GREY .. "?|r", "", "", "" end
    if not c.prof1 and not c.prof2 then return GREY .. "-|r", "", "", "" end
    local function Cell(name)
        if not name then return "", "" end
        return LIGHT .. name .. "|r", tostring(p[name] or "?")
    end
    local n1, s1 = Cell(c.prof1)
    local n2, s2 = Cell(c.prof2)
    return n1, s1, n2, s2
end

-- Time until the soonest valuable mail expires; blank if none, "?" if the mailbox
-- has never been opened on that character.
function ns.MailText(c, now)
    if not c.mail then return GREY .. "?|r" end
    if not c.mailExpires then return "" end
    local left = c.mailExpires - now
    return ns.ExpiryColor(left) .. ns.ExpiryText(left) .. "|r"
end

-- Time played as "12d 5h", "5h 20m" or "20m"; "?" if not recorded yet.
function ns.FormatPlayed(seconds)
    local d, h, m = floor(seconds / 86400), floor(seconds % 86400 / 3600), floor(seconds % 3600 / 60)
    if d > 0 then return d .. "d " .. h .. "h" end
    if h > 0 then return h .. "h " .. m .. "m" end
    return m .. "m"
end

function ns.PlayedText(c, now)
    local played = ns.PlayedNow(c, now)
    return played and ns.FormatPlayed(played) or (GREY .. "?|r")
end

function ns.SeenText(key, c, now)
    if key == ns.charKey then return "|cff20ff20Online|r" end
    local t = c.updated or c.seen
    return t and ns.FormatAgo(now - t) or (GREY .. "?|r")
end

-- Character keys in display order: you first, then by level, then by name.
local order = {}
function ns.OverviewOrder()
    local chars = ns.db.chars
    for i = #order, 1, -1 do order[i] = nil end
    for key, c in pairs(chars) do
        if key ~= ns.charKey then order[#order + 1] = key end
    end
    table.sort(order, function(a, b)
        local la, lb = chars[a].level or 0, chars[b].level or 0
        if la ~= lb then return la > lb end
        return a < b
    end)
    table.insert(order, 1, ns.charKey)
    return order
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local frame, rows, footer

local NO_LABELS, NOTE_LEFT = {}, { [2] = true }
local function ByFirst(a, b) return a[1] < b[1] end

local function RowTooltip(row)
    local key = row.key
    local c = key and ns.db.chars[key]
    if not c then return end
    local now = time()
    local tt = GameTooltip
    tt:SetOwner(row, "ANCHOR_RIGHT")
    tt:AddLine(ns.ColoredName(key, c))
    if c.level then
        local line = "Level " .. c.level
        if c.xpMax and c.xpMax > 0 and c.level < ns.MaxLevel() then
            line = line .. "  " .. GREY .. "(" .. c.xp .. " / " .. c.xpMax .. " XP)|r"
        end
        tt:AddLine(line, 1, 1, 1)
    end
    local rested, cap, toFull = ns.RestedNow(c, now)
    if rested then
        local where = c.resting and "in an inn or city" or "out in the world"
        tt:AddDoubleLine("Rested", floor(rested) .. " XP (" .. ns.RestedText(c, now) .. ")", 1, 0.82, 0, 1, 1, 1)
        if rested < cap then
            tt:AddLine(GREY .. "Full in " .. Duration(toFull) .. ", logged out " .. where .. "|r")
        end
    end
    if c.mailExpires then
        local left = c.mailExpires - now
        tt:AddDoubleLine("Mail expires", ns.ExpiryColor(left) .. ns.ExpiryText(left) .. "|r", 1, 0.82, 0, 1, 1, 1)
        tt:AddLine(GREY .. (c.mailDeletes and "The soonest will be deleted, not returned" or "The soonest goes back to its sender") .. "|r")
    end
    if c.hearth then tt:AddDoubleLine("Hearthstone", c.hearth, 1, 0.82, 0, 1, 1, 1) end
    if c.played then tt:AddDoubleLine("Played", ns.PlayedText(c, now), 1, 0.82, 0, 1, 1, 1) end
    if c.ilvl then tt:AddDoubleLine("Item level", c.ilvl, 1, 0.82, 0, 1, 1, 1) end
    if c.money then tt:AddDoubleLine("Gold", GetCoinTextureString(c.money), 1, 0.82, 0, 1, 1, 1) end
    -- Professions: name, skill and a note, in columns (lined up once shown, below).
    local profRows, profFirst
    if c.profs and next(c.profs) then
        tt:AddLine(" ")
        local skillups = ns.SkillupsOn()
        profRows = {}
        for name, skill in pairs(c.profs) do
            local note = ""
            if skillups then
                local n = ns.SkillupCount(c, name)
                if ns.AtRankCap(c, name) then
                    -- At the final maximum there's nothing to train, so say nothing.
                    if skill < MAX_PROFESSION then note = GREY .. "(train to skill up)|r" end
                elseif n then
                    note = GREY .. "(" .. n .. " skill-up recipe" .. (n == 1 and "" or "s") .. ")|r"
                end
            end
            profRows[#profRows + 1] = { name, tostring(skill), note }
        end
        table.sort(profRows, ByFirst)
        profFirst = tt.NumLines and tt:NumLines() + 1
        for _, r in ipairs(profRows) do
            tt:AddDoubleLine(r[1], r[3] ~= "" and (r[2] .. "  " .. r[3]) or r[2], 1, 1, 1, 1, 1, 1)
        end
    end
    tt:AddLine(" ")
    tt:AddLine(GREY .. (c.bank and "Bank scanned" or "Bank not scanned yet - visit a banker") .. "|r")
    if c.dura then tt:AddDoubleLine("Lowest durability", ns.DurabilityText(c.dura), 1, 0.82, 0, 1, 1, 1) end
    if key == ns.charKey then
        tt:AddLine("|cff66ccffClick to see gear|r")
    else
        tt:AddLine("|cff66ccffClick to see gear · Right-click to forget this character|r")
    end
    tt:Show()
    -- Line up the professions in the font the tooltip is shown in (a UI addon such as
    -- EllesmereUI sets its own when it's shown), then show again to fit the new text.
    if profFirst then
        ns.AlignColumns(tt, profFirst, profRows, NO_LABELS, NOTE_LEFT)
        tt:Show()
    end
end

local function CreateCells(parent, font)
    local cells, x = {}, 12
    for i, col in ipairs(COLUMNS) do
        x = x + (col.gap or 0)
        local fs = parent:CreateFontString(nil, "OVERLAY", font)
        ns.SkinText(fs)
        fs:SetPoint("LEFT", parent, "LEFT", x, 0)
        fs:SetWidth(col.width - 8)
        fs:SetJustifyH(col.right and "RIGHT" or "LEFT")
        fs:SetWordWrap(false)
        cells[i] = fs
        x = x + col.width
    end
    return cells
end

local function CreateRow(i)
    local row = CreateFrame("Button", nil, frame)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -54 - (i - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    row.cells = CreateCells(row, "GameFontHighlightSmall")
    row:SetScript("OnEnter", RowTooltip)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- Left: gear. Right: the character's menu (Forget...).
    row:SetScript("OnClick", function(self, button)
        if button == "RightButton" then ns.ShowCharacterMenu(self, self.key) else ns.ShowGear(self.key) end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = row
    return row
end

local function Refresh()
    local now = time()
    local chars = ns.db.chars
    local keys = ns.OverviewOrder()
    local total, played = 0, 0
    for i, key in ipairs(keys) do
        local c = chars[key]
        local row = rows[i] or CreateRow(i)
        local cells = row.cells
        row.key = key
        cells[1]:SetText(ns.ColoredName(key, c))
        cells[2]:SetText(ns.LevelText(c))
        cells[3]:SetText(ns.RestedText(c, now))
        cells[4]:SetText(c.money and GetCoinTextureString(c.money) or (GREY .. "?|r"))
        local n1, s1, n2, s2 = ns.ProfCells(c)
        cells[5]:SetText(n1)
        cells[6]:SetText(s1)
        cells[7]:SetText(n2)
        cells[8]:SetText(s2)
        cells[9]:SetText(ns.MailText(c, now))
        cells[10]:SetText(c.zone or (GREY .. "?|r"))
        cells[11]:SetText(ns.PlayedText(c, now))
        cells[12]:SetText(ns.SeenText(key, c, now))
        total = total + (c.money or 0)
        played = played + (ns.PlayedNow(c, now) or 0)
        row:Show()
    end
    for i = #keys + 1, #rows do rows[i]:Hide() end
    footer:SetText("Total played: " .. ns.FormatPlayed(played) .. "     Total gold: " .. GetCoinTextureString(total))
    frame:SetHeight(54 + #keys * ROW_HEIGHT + 32)
end

local function CreateWindow()
    -- Room for the left inset, every column, and the right border.
    local width = 12 + 20
    for _, col in ipairs(COLUMNS) do width = width + col.width + (col.gap or 0) end

    local ok, f = pcall(CreateFrame, "Frame", "AltsForeverFrame", UIParent, "BasicFrameTemplateWithInset")
    if not ok then
        -- Plain fallback if this client lacks the template: a dialog backdrop and a close button.
        f = CreateFrame("Frame", "AltsForeverFrame", UIParent, "BackdropTemplate")
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        })
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
    end
    frame = f
    rows = {}
    f:SetSize(width, 200)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)

    local title = f.TitleText or f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if not f.TitleText then title:SetPoint("TOP", 0, -6) end
    title:SetText("Alts Forever")

    local header = CreateFrame("Frame", nil, f)
    header:SetHeight(ROW_HEIGHT)
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -32)
    header:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    for i, fs in ipairs(CreateCells(header, "GameFontNormalSmall")) do fs:SetText(COLUMNS[i].title) end

    footer = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.footer = footer
    footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 12)
    -- Options (cog) button in the title bar, left of the close button.
    local cog = CreateFrame("Button", nil, f)
    cog:SetSize(16, 16)
    cog:SetPoint("TOPRIGHT", f, "TOPRIGHT", -28, -4)
    cog:SetNormalTexture("Interface\\Icons\\INV_Misc_Gear_01")
    cog:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    cog:SetScript("OnClick", function(self) ns.ShowOptionsMenu(self) end)
    cog:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Options")
        GameTooltip:Show()
    end)
    cog:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.cog = cog
    -- Reputation panel button, left of the options button.
    local rep = CreateFrame("Button", nil, f)
    rep:SetSize(16, 16)
    rep:SetPoint("RIGHT", cog, "LEFT", -6, 0)
    rep:SetNormalTexture("Interface\\Icons\\Achievement_Reputation_01")
    rep:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    rep:SetScript("OnClick", function() ns.ToggleReputation() end)
    rep:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Reputation")
        GameTooltip:AddLine("Every character's standing with each faction", 1, 1, 1)
        GameTooltip:Show()
    end)
    rep:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.repButton = rep
    f.credit = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.credit:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 12)
    f.credit:SetText("Alts Forever by Kadmai")

    ns.SkinWindow(f)
    f:SetScript("OnShow", Refresh)
    f:SetScript("OnHide", function()
        if AltsForeverGearFrame then AltsForeverGearFrame:Hide() end
        if AltsForeverRepFrame then AltsForeverRepFrame:Hide() end
    end)
    -- Escape closes it, like Blizzard's own windows.
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "AltsForeverFrame" end
    f:Hide()
end

-- Opens or closes the overview; `open` only ever opens it (menus, settings page).
function ns.ToggleOverview(open)
    if not frame then CreateWindow() end
    if frame:IsShown() and not open then frame:Hide() else frame:Show() end
end

function ns.OverviewShown()
    return frame and frame:IsShown() or false
end

function ns.RefreshOverview()
    if frame and frame:IsShown() then Refresh() end
end

---------------------------------------------------------------------------
-- Status bar tooltips: hovering the experience bar adds your other characters still
-- levelling (level, XP, rested); hovering the reputation bar adds your other characters'
-- standing with the watched faction. You're left out: the bar already shows you. The
-- lines are built only on hover.
---------------------------------------------------------------------------

-- Tooltip text isn't monospaced, so columns are lined up by measuring each value and
-- padding with a transparent texture (a spacer) of the missing width. Shared with the
-- item tooltip (Tooltip.lua).
--  * Measuring happens in the tooltip's own line (ns.MeasureIn), which is exact. Other
--    font strings, even our own on the tooltip, disagree about spacers: in game the
--    tooltip drew them at about 87% of what those measured (rows came out up to 7 units
--    apart), while text widths agreed (checked 2026-09-26).
--  * While Blizzard's secure code builds a tooltip, its lines' widths read as secret
--    values. Then the text is measured in our own font string on the tooltip, with the
--    spacer scale learned from a real line earlier (remembered per font and size). With
--    none learned yet, the plain text stays and a later hover lines it up.
--  * Every width and font read is checked with issecretvalue first.
--  * Spacers are calibrated: a 100-unit one is measured first and every spacer scaled.
--  * Spacers are whole units; each one's rounding is carried into the next one to its
--    left (rows are right-aligned, so build them from the right: ns.StartRow, then ns.Pad
--    right to left), keeping everything within half a unit of its place.
local BLANK = "Interface\\AddOns\\" .. ADDON .. "\\media\\blank.tga"
local GAP = 10

local function Spacer(width)
    width = floor(width + 0.5)
    if width < 1 then return "" end
    return "|T" .. BLANK .. ":1:" .. width .. "|t"
end
ns.Spacer = Spacer

local issecretvalue = issecretvalue or function() return false end
local measuring, spacerScale, carry = nil, 1, 0
local measurers = {} -- [tooltip] = our measuring font string on it
local scales = {}    -- [font][size] = spacer scale learned from a real tooltip line
local restoreLine, restoreText -- a tooltip line being measured in, and its text

-- The width of s in the font string being measured in, or nil if it can't be measured.
function ns.TextWidth(s)
    measuring:SetText(s)
    local w = measuring:GetStringWidth()
    if issecretvalue(w) or type(w) ~= "number" then return nil end
    return w
end

-- A font as read from a font string, if it can be used (not secret).
function ns.UsableFont(font, size, flags)
    return font and not issecretvalue(font) and not issecretvalue(size) and not issecretvalue(flags)
end

-- Starts measuring on tooltip tt in the given font: in `line` (one of its lines, whose
-- text the caller sets afterwards) if its widths can be read, otherwise in our own font
-- string with a spacer scale learned earlier. Returns false if it can't measure.
function ns.MeasureIn(tt, font, size, flags, line)
    if not ns.UsableFont(font, size, flags) then return false end
    local bySize = scales[font]
    restoreLine = nil
    if line and line.GetStringWidth and line.GetText then
        local text = line:GetText()
        if not issecretvalue(text) then restoreLine, restoreText = line, text end
    end
    if restoreLine then
        measuring = line
        local unit = ns.TextWidth(Spacer(100))
        if unit and unit > 0 then
            spacerScale = unit / 100
            if not bySize then
                bySize = {}
                scales[font] = bySize
            end
            bySize[size] = spacerScale
            return true
        end
        line:SetText(restoreText)
        restoreLine = nil
    end
    local known = bySize and bySize[size]
    if not known then return false end
    local m = measurers[tt]
    if not m then
        if not tt.CreateFontString then return false end
        m = tt:CreateFontString(nil, "BACKGROUND")
        m:SetPoint("TOPLEFT")
        m:SetAlpha(0)
        measurers[tt] = m
    end
    m:SetFont(font, size, flags)
    measuring, spacerScale = m, known
    return true
end

-- Done measuring: our own font string is cleared, and a tooltip line measured in gets
-- its text back unless `keep` (the caller is about to set it).
function ns.MeasureDone(keep)
    for _, m in pairs(measurers) do
        if measuring == m then m:SetText("") end
    end
    if restoreLine and not keep then restoreLine:SetText(restoreText) end
    restoreLine = nil
end

function ns.StartRow() carry = 0 end

-- A spacer that draws `width` wide, carrying its rounding to the next one on its left.
function ns.Pad(width)
    width = width + carry
    local n = floor(width / spacerScale + 0.5)
    if n < 1 then
        carry = width
        return ""
    end
    carry = width - n * spacerScale
    return Spacer(n)
end

-- Lines up the right-hand columns of the rows added from line `first` on; leaves the
-- plain text if the tooltip's text can't be measured. Each row is { name, value... };
-- labels[col] is text shown before that column's value (e.g. "rested"). Columns are
-- right-aligned, except those marked in `lefts` (e.g. notes of different lengths).
-- Our lines take the font of the tooltip's second line (its body text): a line the
-- tooltip hasn't needed before gets a new font string, which a UI addon that restyled
-- the existing ones (EllesmereUI) hasn't reached, so it would show in the game's font.
local function Align(tt, first, rows, labels, lefts)
    local name = tt.GetName and tt:GetName()
    local fs = name and _G[name .. "TextLeft2"]
    local font, size, flags
    if fs and fs.GetFont then font, size, flags = fs:GetFont() end
    if not ns.UsableFont(font, size, flags) then return end
    for line = first - 1, first + #rows - 1 do
        for _, side in ipairs({ "TextLeft", "TextRight" }) do
            local text = _G[name .. side .. line]
            if text and text.SetFont then text:SetFont(font, size, flags) end
        end
    end
    if not ns.MeasureIn(tt, font, size, flags, _G[name .. "TextRight" .. first]) then return end
    local columns, widths, measured = #rows[1] - 1, {}, {}
    for col = 1, columns do widths[col] = 0 end
    for i, row in ipairs(rows) do
        measured[i] = {}
        for col = 1, columns do
            local w = ns.TextWidth(row[col + 1])
            if not w then return ns.MeasureDone() end
            measured[i][col] = w
            if w > widths[col] then widths[col] = w end
        end
    end
    local texts = {}
    for i, row in ipairs(rows) do
        ns.StartRow()
        local text = ""
        -- Spacers are made right to left (each carries its rounding to the next on its left).
        for col = columns, 1, -1 do
            local gap = col > 1 and GAP or 0
            local spare = widths[col] - measured[i][col]
            if lefts and lefts[col] then
                local after = ns.Pad(spare)
                text = (labels[col] or "") .. row[col + 1] .. after .. text
                text = ns.Pad(gap) .. text
            elseif labels[col] then
                local fill = ns.Pad(spare)
                text = labels[col] .. fill .. row[col + 1] .. text
                text = ns.Pad(gap) .. text
            else
                text = ns.Pad(gap + spare) .. row[col + 1] .. text
            end
        end
        texts[i] = text
    end
    ns.MeasureDone(true)
    for i, text in ipairs(texts) do
        local right = _G[name .. "TextRight" .. (first + i - 1)]
        if right then right:SetText(text) end
    end
end

ns.AlignColumns = Align

-- The last rows added, so a tooltip we open ourselves can line them up again once shown.
local lastRows = {}

-- Adds a "Your characters" section; returns false, adding nothing, if there are no rows.
-- `title` starts a tooltip we opened ourselves; otherwise a gap follows the bar's own.
function ns.AddCharacterRows(tt, rows, labels, title, noGap)
    if #rows == 0 then return false end
    if title then tt:AddLine(title, 1, 1, 1) elseif not noGap then tt:AddLine(" ") end
    tt:AddLine("Your characters", 1, 0.82, 0)
    local first = tt.NumLines and tt:NumLines() + 1
    for _, row in ipairs(rows) do
        local text = ""
        for col = 2, #row do
            text = text .. (col > 2 and "  " or "") .. (labels[col - 1] or "") .. row[col]
        end
        tt:AddDoubleLine(row[1], text, 1, 1, 1, 1, 1, 1)
    end
    if first then
        Align(tt, first, rows, labels)
        lastRows.tt, lastRows.first, lastRows.rows, lastRows.labels = tt, first, rows, labels
    end
    return true
end

local XP_LABELS = { nil, nil, GREY .. "rested|r " }

local BigNumber = BreakUpLargeNumbers or tostring

-- This session: time, XP gained and, once there's a pace, about how long to level.
local function AddSession(tt)
    local seconds, xp, toLevel = ns.SessionXP(time())
    tt:AddDoubleLine("This session", ns.FormatPlayed(seconds), 1, 0.82, 0, 1, 1, 1)
    tt:AddDoubleLine("XP gained", BigNumber(xp), 1, 1, 1, 1, 1, 1)
    if toLevel then tt:AddDoubleLine("Time to level", "about " .. ns.FormatPlayed(toLevel), 1, 1, 1, 1, 1, 1) end
end

-- This session's stats (when turned on), then your other characters still levelling:
-- level, XP and rested XP.
function ns.AddXPLines(tt, fresh)
    local chars, maxLevel, now = ns.db.chars, ns.MaxLevel(), time()
    local rows = {}
    for _, key in ipairs(ns.OverviewOrder()) do
        local c = chars[key]
        if key ~= ns.charKey and c.level and c.level < maxLevel then
            local xp = (c.xpMax and c.xpMax > 0) and (GREY .. floor(c.xp * 100 / c.xpMax) .. "%|r") or ""
            rows[#rows + 1] = { ns.ColoredName(key, c), tostring(c.level), xp, ns.RestedText(c, now) }
        end
    end
    local me = ns.char
    local stats = ns.StatsOn() and me.level and me.level < maxLevel
    if #rows == 0 and not stats then return false end
    if fresh then tt:AddLine("Experience", 1, 1, 1) else tt:AddLine(" ") end
    if stats then
        AddSession(tt)
        if #rows > 0 then tt:AddLine(" ") end
    end
    ns.AddCharacterRows(tt, rows, XP_LABELS, nil, true)
    return true
end

-- Blizzard's bars show a tooltip only sometimes, so we open one if none is showing;
-- ElvUI's and EllesmereUI's show theirs (unless the player made the bar click-through,
-- or it has nothing to show), and we add to it.
local function HookBar(bar, ownTooltip, add)
    if not bar or bar.altsForeverHooked or not bar.HookScript then return end
    bar.altsForeverHooked = true
    bar:HookScript("OnEnter", function(self)
        local tt = GameTooltip
        if tt:IsForbidden() then return end
        if tt:IsShown() then
            if add(tt) then tt:Show() end
        elseif ownTooltip then
            tt:SetOwner(self, "ANCHOR_TOP")
            lastRows.tt = nil
            if add(tt, true) then
                tt:Show()
                -- Shown now, in its final font (a UI addon such as EllesmereUI sets its
                -- own on show): line up again and show again to fit.
                if lastRows.tt == tt then
                    Align(tt, lastRows.first, lastRows.rows, lastRows.labels)
                    tt:Show()
                end
            else
                tt:Hide()
            end
        end
    end)
    if ownTooltip then
        bar:HookScript("OnLeave", function(self)
            if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        end)
    end
end

local function AddRep(tt, fresh)
    return ns.AddRepLines and ns.AddRepLines(tt, fresh) or false
end

-- Blizzard's bars sit in status tracking containers, in `bars` by kind (checked in game:
-- 6 bars, experience 4th). The experience bar is the one with a rested (exhaustion)
-- marker; reputation is the first kind, as in retail.
local function HookBlizzardBars(container)
    if not (container and type(container.bars) == "table") then return end
    for _, bar in pairs(container.bars) do
        if type(bar) == "table" and bar.ExhaustionTick then HookBar(bar, true, ns.AddXPLines) end
    end
    local enum = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum
    local rep = container.bars[enum and enum.Reputation or 1]
    if type(rep) == "table" and not rep.ExhaustionTick then HookBar(rep, true, AddRep) end
end

-- Hooks each bar once. Other UIs make theirs during their own login setup, so this runs
-- on entering the world (after every addon's login) and again after each loading screen,
-- which costs nothing once hooked.
local function HookBars()
    HookBlizzardBars(MainStatusTrackingBarContainer)
    HookBlizzardBars(SecondaryStatusTrackingBarContainer)
    HookBar(ElvUI_ExperienceBarHolder, false, ns.AddXPLines)
    HookBar(EllesmereEAB_XPBar, false, ns.AddXPLines)
    HookBar(ElvUI_ReputationBarHolder, false, AddRep)
    HookBar(EllesmereEAB_RepBar, false, AddRep)
end

function ns.StartOverview()
    -- Keep an open window current; a closed or never-opened one costs nothing.
    local function Update()
        if frame and frame:IsShown() then Refresh() end
    end
    for _, event in ipairs({ "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_MONEY", "ZONE_CHANGED_NEW_AREA", "SKILL_LINES_CHANGED" }) do
        ns.On(event, Update)
    end
    ns.On("PLAYER_ENTERING_WORLD", HookBars)
end
