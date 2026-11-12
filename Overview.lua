-- Alts Forever overview: a window (/af) listing every character with level, rested
-- XP, gold, professions, location, time played and when they were last played. It's
-- only built the first time it's opened, and only refreshes while it's showing.
local _, ns = ...
if ns.disabled then return end -- another copy of Alts Forever is running (Core.lua)
local L = ns.L

local floor, max, pairs, time = math.floor, math.max, pairs, time
local issecretvalue = issecretvalue or function() return false end
local ipairs = ipairs
local GetCoinTextureString = C_CurrencyInfo.GetCoinTextureString

local GREY = "|cff9d9d9d"
-- Something to do on that character: rested filling slowly, Legacy points to spend.
local ATTENTION = "|cffff8000"
local MAX_PROFESSION = 300 -- the last rank's maximum on Forever (Classic ruleset)
local ROW_HEIGHT = 20
local COLUMNS = {
    -- `sort`: clicking the title orders the characters by it (SORTS, below).
    { title = L["Character"], width = 180, sort = "name" },
    { title = L["Level"], width = 80, sort = "level" },
    { title = L["Rested"], width = 70, sort = "rested" },
    -- Well Rested's rank beside Rested, then Legacy points spent of the total: short
    -- values under wider titles, so both are centred.
    { title = L["Well Rested"], width = 84, center = true, sort = "wellRested" },
    { title = L["Legacy"], width = 60, center = true, sort = "legacy" },
    { title = L["Gold"], width = 120, right = true, sort = "gold" },
    -- Each main profession gets a name column and a right-aligned skill column, so
    -- the skill numbers line up. The gap separates it from the right-aligned gold.
    { title = L["Professions"], width = 104, gap = 16 },
    { title = "", width = 34, right = true },
    { title = "", width = 104, gap = 16 },
    { title = "", width = 34, right = true },
    { title = L["Mail"], width = 60, gap = 16, sort = "mail" },
    -- The account's instances this hour, then raid and dungeon saves running (the row
    -- tooltip lists both): "2/10 <key>1".
    { title = L["Lockouts"], width = 76, center = true },
    { title = L["Zone"], width = 140, sort = "zone" },
    { title = L["Played"], width = 70, right = true, sort = "played" },
    { title = L["Last seen"], width = 80, right = true, sort = "seen" },
}
local LIGHT = "|cffc0c0c0"

---------------------------------------------------------------------------
-- Text helpers (no UI, so they can be tested)
---------------------------------------------------------------------------
function ns.FormatAgo(seconds)
    if seconds < 3600 then return L["<1h"] end
    if seconds < 86400 then return L["%dh ago"]:format(floor(seconds / 3600)) end
    return L["%dd ago"]:format(floor(seconds / 86400))
end

local function Duration(seconds)
    local d, h = floor(seconds / 86400), floor(seconds % 86400 / 3600)
    if d > 0 then return L["%dd %dh"]:format(d, h) end
    return L["%dh"]:format(max(h, 1))
end

-- Legacy points spent of the total they can spend ("3/16", orange while some are left) and
-- Well Rested's rank; "?" if not read yet.
function ns.LegacyCells(c)
    local n = ns.LegacyUnspent(c)
    local points = GREY .. "?|r"
    if n then
        local text = c.legacySpent .. "/" .. ns.db.legacyPool
        points = n > 0 and (ATTENTION .. text .. "|r") or text
    end
    local rank = c.wellRested
    return points, rank and (rank .. "/5") or (GREY .. "?|r")
end

-- The level and, below max level, how far into it: the overview shows them in two
-- cells so the percentages line up.
function ns.LevelParts(c)
    if not c.level then return GREY .. "?|r", "" end
    if c.level >= ns.MaxLevel() or not c.xp or not c.xpMax or c.xpMax == 0 then return tostring(c.level), "" end
    -- Multiply first: 5700 / 10000 * 100 is 56.99... in floating point.
    return tostring(c.level), GREY .. floor(c.xp * 100 / c.xpMax) .. "%|r"
end

function ns.LevelText(c)
    local level, pct = ns.LevelParts(c)
    return pct == "" and level or (level .. "  " .. pct)
end

-- Rested as a share of a level: blue when full, orange while filling outside an inn or city
-- (a quarter of the speed), "-" at max level, "?" if not recorded yet.
function ns.RestedText(c, now)
    if not c.level then return GREY .. "?|r" end
    local rested, cap = ns.RestedNow(c, now)
    if not rested then return GREY .. "-|r" end
    local pct = floor(rested / c.xpMax * 100 + 0.5)
    if rested >= cap then return "|cff4da6ff" .. pct .. "%|r" end
    if not c.resting then return ATTENTION .. pct .. "%|r" end
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
    if d > 0 then return L["%dd %dh"]:format(d, h) end
    if h > 0 then return L["%dh %dm"]:format(h, m) end
    return L["%dm"]:format(m)
end

function ns.PlayedText(c, now)
    local played = ns.PlayedNow(c, now)
    return played and ns.FormatPlayed(played) or (GREY .. "?|r")
end

function ns.SeenText(key, c, now)
    if key == ns.charKey then return "|cff20ff20" .. L["Online"] .. "|r" end
    local t = c.updated or c.seen
    return t and ns.FormatAgo(now - t) or (GREY .. "?|r")
end

-- What the overview can be ordered by (a column's `sort`): the value compared, nil when
-- it isn't known (those go last either way), and `up` when the natural order is smallest
-- first (names, zones, the mail expiring soonest); the rest start with the most.
local SORTS = {
    name = { up = true, value = function(key) return key end },
    level = { value = function(_, c)
        if not c.level then return nil end
        local into = (c.xp and c.xpMax and c.xpMax > 0) and c.xp / c.xpMax or 0
        return c.level + (into < 1 and into or 0)
    end },
    rested = { value = function(_, c, now)
        local rested = ns.RestedNow(c, now)
        return rested and rested / c.xpMax or nil
    end },
    wellRested = { value = function(_, c) return c.wellRested end },
    legacy = { value = function(_, c) return ns.LegacyUnspent(c) end }, -- points left to spend
    gold = { value = function(_, c) return c.money end },
    mail = { up = true, value = function(_, c) return c.mailExpires end },
    zone = { up = true, value = function(_, c) return c.zone end },
    played = { value = function(_, c, now) return ns.PlayedNow(c, now) end },
    seen = { value = function(key, c, now) return key == ns.charKey and now or c.updated or c.seen end },
}

-- The order chosen by clicking a column title: db.overviewSort (a SORTS key; nil = Level)
-- and db.overviewSortRev (true = the other way round). Level in its natural order is the
-- default, which also keeps you first, and saves nothing.
function ns.OverviewSort()
    local db = ns.db
    local name = SORTS[db.overviewSort] and db.overviewSort or "level"
    return name, db.overviewSortRev == true
end

-- A click on a column title: that column in its natural order, or the other way round
-- if it's already the one.
function ns.SortOverview(name)
    if not SORTS[name] then return end
    local db = ns.db
    local current, rev = ns.OverviewSort()
    db.overviewSort = name ~= "level" and name or nil
    db.overviewSortRev = (name == current and not rev) or nil
    ns.RefreshOverview(true)
end

-- Character keys in display order: you first, then by level, then by name; or, with
-- another order chosen (ns.OverviewSort), everyone by that, you among them, ties by level
-- and name. Once two rulesets or both factions are known, your group's characters come
-- first, then each other group's, then any whose ruleset isn't known yet, each group in
-- that order; ns.overviewSplit says so (the overview then heads each group).
local order = {}
local parts = {}
local values = {}
local function Group(c) return ns.GroupKey(c, parts[1], parts[2]) end

-- The comparison reads these, set by ns.OverviewOrder for each sort: nothing is created
-- per call.
local sChars, sSplit, sMine, sBy, sAsc

local function Rank(g)
    if g == sMine then return 0 end
    return g:sub(1, 2) == "?|" and 2 or 1
end

local function Before(a, b)
    local ca, cb = sChars[a], sChars[b]
    if sSplit then
        local ga, gb = Group(ca), Group(cb)
        if ga ~= gb then
            local ra, rb = Rank(ga), Rank(gb)
            if ra ~= rb then return ra < rb end
            return ga < gb
        end
    end
    if sBy then
        local va, vb = values[a], values[b]
        if va ~= vb then
            if va == nil then return false end
            if vb == nil then return true end
            if sAsc then return va < vb end
            return va > vb
        end
    end
    local la, lb = ca.level or 0, cb.level or 0
    if la ~= lb then return la > lb end
    return a < b
end

function ns.OverviewOrder()
    local chars = ns.db.chars
    local name, rev = ns.OverviewSort()
    local by = (name ~= "level" or rev) and SORTS[name] or nil
    for i = #order, 1, -1 do order[i] = nil end
    for key in pairs(chars) do
        if by or key ~= ns.charKey then order[#order + 1] = key end
    end
    if by then
        local now = time()
        for key in pairs(values) do values[key] = nil end
        for _, key in ipairs(order) do values[key] = by.value(key, chars[key], now) end
    end
    parts[1], parts[2] = ns.GroupParts()
    local split = parts[1] or parts[2]
    ns.overviewSplit = split
    sChars, sSplit, sMine, sBy = chars, split, Group(ns.char), by
    sAsc = by and (by.up == true) ~= rev
    table.sort(order, Before)
    sChars = nil
    if not by then table.insert(order, 1, ns.charKey) end
    return order
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local frame, rows, heads, footer

local NO_LABELS, NOTE_LEFT = {}, { [2] = true }
-- Gathering professions by their game IDs (Fishing 356, Herbalism 182, Skinning 393), so
-- the check works in every language: the game names them in the player's language. The
-- set is kept once every name is known (profession data may not be loaded at first).
local GATHERING_IDS = { 356, 182, 393 }
local gathering
local function Gathering()
    if gathering then return gathering end
    local set, complete = {}, true
    local ts = C_TradeSkillUI
    for _, id in ipairs(GATHERING_IDS) do
        local name = ts and ts.GetTradeSkillDisplayName and ts.GetTradeSkillDisplayName(id)
        if not issecretvalue(name) and type(name) == "string" and name ~= "" then
            set[name] = true
        else
            complete = false
        end
    end
    if complete then gathering = set end
    return set
end
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
        local line = L["Level %d"]:format(c.level)
        if c.xp and c.xpMax and c.xpMax > 0 and c.level < ns.MaxLevel() then
            line = line .. "  " .. GREY .. L["(%d / %d XP)"]:format(c.xp, c.xpMax) .. "|r"
        end
        tt:AddLine(line, 1, 1, 1)
    end
    local rested, cap, toFull = ns.RestedNow(c, now)
    if rested then
        local where = c.resting and L["logged out in an inn or city"] or L["logged out in the world"]
        tt:AddDoubleLine(L["Rested"], L["%d XP (%s)"]:format(floor(rested), ns.RestedText(c, now)), 1, 0.82, 0, 1, 1, 1)
        if rested < cap then
            tt:AddLine(GREY .. L["Full in %s, %s"]:format(Duration(toFull), where) .. "|r")
        end
    end
    if c.wellRested then tt:AddDoubleLine(ns.WellRestedName(), c.wellRested .. "/5", 1, 0.82, 0, 1, 1, 1) end
    local unspent = ns.LegacyUnspent(c)
    if unspent then
        tt:AddDoubleLine(L["Legacy points"], unspent > 0 and (ATTENTION .. L["%d to spend"]:format(unspent) .. "|r")
            or L["all spent"], 1, 0.82, 0, 1, 1, 1)
    end
    if c.mailExpires then
        local left = c.mailExpires - now
        tt:AddDoubleLine(L["Mail expires"], ns.ExpiryColor(left) .. ns.ExpiryText(left) .. "|r", 1, 0.82, 0, 1, 1, 1)
        tt:AddLine(GREY .. (c.mailDeletes and L["The soonest will be deleted, not returned"] or L["The soonest goes back to its sender"]) .. "|r")
    end
    if c.hearth then tt:AddDoubleLine(L["Hearthstone"], c.hearth, 1, 0.82, 0, 1, 1, 1) end
    if c.played then tt:AddDoubleLine(L["Played"], ns.PlayedText(c, now), 1, 0.82, 0, 1, 1, 1) end
    if c.ilvl then tt:AddDoubleLine(L["Item level"], c.ilvl, 1, 0.82, 0, 1, 1, 1) end
    if c.money then tt:AddDoubleLine(L["Gold"], GetCoinTextureString(c.money), 1, 0.82, 0, 1, 1, 1) end
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
                    if skill < MAX_PROFESSION then note = GREY .. L["(train to skill up)"] .. "|r" end
                elseif n and (n > 0 or not Gathering()[name]) and next(c.recipes[name]) then
                    -- Gathering professions level by gathering; their few recipes (Fish
                    -- Bowl, Camp Chair) are novelties, so "0" there is noise.
                    note = GREY .. (n == 1 and L["(%d skill-up recipe)"] or L["(%d skill-up recipes)"]):format(n) .. "|r"
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
    ns.AddLockoutLines(tt, c, now)
    tt:AddLine(" ")
    tt:AddLine(GREY .. (c.bank and L["Bank scanned"] or L["Bank not scanned yet - visit a banker"]) .. "|r")
    if c.dura then tt:AddDoubleLine(L["Lowest durability"], ns.DurabilityText(c.dura), 1, 0.82, 0, 1, 1, 1) end
    if key == ns.charKey then
        tt:AddLine("|cff66ccff" .. L["Click to see gear"] .. "|r")
    else
        tt:AddLine("|cff66ccff" .. L["Click to see gear"] .. " · " .. L["Right-click for bags, professions and more"] .. "|r")
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
        fs:SetJustifyH(col.right and "RIGHT" or col.center and "CENTER" or "LEFT")
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
    -- The Level column: the level right-aligned in a narrow cell, then how far into it,
    -- so the percentages line up whatever the level's width.
    local level = row.cells[2]
    level:SetWidth(18)
    level:SetJustifyH("RIGHT")
    row.pct = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ns.SkinText(row.pct)
    row.pct:SetPoint("LEFT", level, "RIGHT", 6, 0)
    row.pct:SetWidth(COLUMNS[2].width - 32)
    row.pct:SetJustifyH("LEFT")
    row.pct:SetWordWrap(false)
    row:SetScript("OnEnter", RowTooltip)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- Left: gear. Right: the character's menu (Forget...).
    row:SetScript("OnClick", function(self, button)
        if button == "RightButton" then ns.ShowCharacterMenu(self, self.key) else ns.ShowGear(self.key) end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- A on a controller: the character's menu (Gear, Bags, Bank, Forget), since a
    -- controller has no right-click.
    row.OnSmartNavClick = function(self) ns.ShowCharacterMenu(self, self.key) end
    rows[i] = row
    return row
end

-- A group's heading row: its name, and its gold total under the Gold column, with a faint
-- line above it and some space (SECTION_GAP) before every group but the first. Clicking
-- it collapses the group to just the heading, or opens it again (db.collapsedGroups,
-- by group key, kept between sessions).
local SECTION_GAP = 10
local PLUS, MINUS = "Interface\\Buttons\\UI-PlusButton-Up", "Interface\\Buttons\\UI-MinusButton-Up"

local function ToggleGroup(head)
    local db = ns.db
    db.collapsedGroups = db.collapsedGroups or {}
    db.collapsedGroups[head.group] = not db.collapsedGroups[head.group] or nil
    if next(db.collapsedGroups) == nil then db.collapsedGroups = nil end
    ns.RefreshOverview()
end

local function HeadTooltip(head)
    GameTooltip:SetOwner(head, "ANCHOR_TOPLEFT")
    GameTooltip:AddLine(head.label:GetText())
    GameTooltip:AddLine(head.collapsed and L["Click to show these characters."] or L["Click to hide these characters."], 1, 1, 1)
    GameTooltip:Show()
end

local function CreateHead(i)
    local head = CreateFrame("Button", nil, frame)
    head:SetHeight(ROW_HEIGHT)
    local hl = head:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    head:RegisterForClicks("LeftButtonUp")
    head:SetScript("OnClick", ToggleGroup)
    head:SetScript("OnEnter", HeadTooltip)
    head:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local icon = head:CreateTexture(nil, "ARTWORK")
    icon:SetSize(12, 12)
    icon:SetPoint("LEFT", head, "LEFT", -1, 0)
    head.icon = icon
    local line = head:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.12)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", head, "TOPLEFT", 8, 0)
    line:SetPoint("TOPRIGHT", head, "TOPRIGHT", -8, 0)
    head.line = line
    local texts = CreateCells(head, "GameFontNormalSmall")
    -- The name may run on past the narrow columns before Gold (empty in a heading).
    local width = -8
    for c = 1, 5 do width = width + COLUMNS[c].width + (COLUMNS[c + 1].gap or 0) end
    texts[1]:SetWidth(width)
    head.label, head.gold = texts[1], texts[6]
    heads[i] = head
    return head
end

-- Places a row or heading y below the column titles.
local function Place(f, y)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -54 - y)
    f:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
end

-- While open, the overview refreshes itself when its instance counts change (a visit stops
-- counting, or the wait at the limit ticks over), so an account at 10/10 shows free again
-- without some other event. One timer at a time: a new one only for a sooner change, and a
-- numbered `dueTick` so only the latest acts.
local dueAt, dueTick = nil, 0
local Refresh

local function Due(now)
    if not (C_Timer and C_Timer.After) then return end
    local wait = ns.InstancesChangeIn(now)
    if not wait or (dueAt and now + wait >= dueAt) then return end
    dueTick, dueAt = dueTick + 1, now + wait
    local mine = dueTick
    C_Timer.After(wait, function()
        if mine ~= dueTick then return end
        dueAt = nil
        if frame and frame:IsShown() then Refresh() end
    end)
end

-- The column titles: a small arrow beside the one the characters are ordered by, pointing
-- up when the smallest is first; placed when the window opens and when the order changes. It sits just past the title's text, on the side the
-- column isn't aligned to (the far end of the cell if the text's width can't be read).
local UP, DOWN = "Interface\\Buttons\\Arrow-Up-Up", "Interface\\Buttons\\Arrow-Down-Up"

local function MarkSort()
    local name, rev = ns.OverviewSort()
    local b, arrow = frame.sorts[name], frame.sortArrow
    arrow:SetTexture(((SORTS[name].up == true) ~= rev) and UP or DOWN)
    local fs, col = b.title, b.col
    local w = fs:GetStringWidth()
    if issecretvalue(w) or type(w) ~= "number" then w = nil end
    arrow:ClearAllPoints()
    if col.right then
        if w then arrow:SetPoint("RIGHT", fs, "RIGHT", -w - 1, -1) else arrow:SetPoint("LEFT", fs, "LEFT", 0, -1) end
    elseif col.center then
        if w then arrow:SetPoint("LEFT", fs, "CENTER", w / 2 + 1, -1) else arrow:SetPoint("RIGHT", fs, "RIGHT", 0, -1) end
    else
        if w then arrow:SetPoint("LEFT", fs, "LEFT", w + 1, -1) else arrow:SetPoint("RIGHT", fs, "RIGHT", 0, -1) end
    end
end

local function SortClick(b) ns.SortOverview(b.sort) end

local function SortTooltip(b)
    GameTooltip:SetOwner(b, "ANCHOR_TOPLEFT")
    GameTooltip:AddLine(b.col.title)
    GameTooltip:AddLine(L["Click to sort by this column, and again to reverse it."], 1, 1, 1)
    GameTooltip:Show()
end

function Refresh()
    local now = time()
    local chars = ns.db.chars
    local keys = ns.OverviewOrder()
    local split = ns.overviewSplit
    local total, played = 0, 0
    -- Gold and characters per group, for the headings.
    local gold, count = {}, {}
    if split then
        for _, key in ipairs(keys) do
            local g = Group(chars[key])
            gold[g] = (gold[g] or 0) + (chars[key].money or 0)
            count[g] = (count[g] or 0) + 1
        end
    end
    -- Counts each account's instances this hour, for the footer and each row's Lockouts cell.
    local instances = ns.InstanceText(now)
    Due(now)
    local collapsed = ns.db.collapsedGroups or {}
    local y, nHeads, group, hidden = 0, 0, nil, false
    for i, key in ipairs(keys) do
        local c = chars[key]
        if split and Group(c) ~= group then
            group = Group(c)
            hidden = collapsed[group] == true
            if nHeads > 0 then y = y + SECTION_GAP end
            nHeads = nHeads + 1
            local head = heads[nHeads] or CreateHead(nHeads)
            Place(head, y)
            head.group, head.collapsed = group, hidden
            head.icon:SetTexture(hidden and PLUS or MINUS)
            head.line:SetShown(nHeads > 1)
            local label = ns.GroupLabel(c, parts[1], parts[2])
            head.label:SetText(hidden and (label .. "  " .. GREY .. "(" .. count[group] .. ")|r") or label)
            -- A total only when there's something to add up: one character's is on their row,
            -- unless the group is collapsed.
            head.gold:SetText((hidden or count[group] > 1) and GetCoinTextureString(gold[group]) or "")
            head:Show()
            y = y + ROW_HEIGHT
        end
        local row = rows[i] or CreateRow(i)
        if not hidden then
            Place(row, y)
            y = y + ROW_HEIGHT
        end
        local cells = row.cells
        row.key = key
        cells[1]:SetText(ns.ColoredName(key, c))
        local level, pct = ns.LevelParts(c)
        cells[2]:SetText(level)
        row.pct:SetText(pct)
        cells[3]:SetText(ns.RestedText(c, now))
        local points, rank = ns.LegacyCells(c)
        cells[4]:SetText(rank)
        cells[5]:SetText(points)
        cells[6]:SetText(c.money and GetCoinTextureString(c.money) or (GREY .. "?|r"))
        local n1, s1, n2, s2 = ns.ProfCells(c)
        cells[7]:SetText(n1)
        cells[8]:SetText(s1)
        cells[9]:SetText(n2)
        cells[10]:SetText(s2)
        cells[11]:SetText(ns.MailText(c, now))
        cells[12]:SetText(ns.LockoutText(c, now))
        cells[13]:SetText(c.zone or (GREY .. "?|r"))
        cells[14]:SetText(ns.PlayedText(c, now))
        cells[15]:SetText(ns.SeenText(key, c, now))
        total = total + (c.money or 0)
        played = played + (ns.PlayedNow(c, now) or 0)
        row:SetShown(not hidden)
    end
    for i = #keys + 1, #rows do rows[i]:Hide() end
    for i = nHeads + 1, #heads do heads[i]:Hide() end
    -- With only one character there's nothing to compare yet: say how to add the others.
    frame.credit:SetText(#keys == 1 and (GREY .. L["Log in on your other characters once to add them here."] .. "|r")
        or L["Alts Forever by Kadmai"])
    -- Split by ruleset, each heading has its gold: one total would mix what can't be traded.
    footer:SetText((instances and (instances .. "     ") or "")
        .. L["Total played: %s"]:format(ns.FormatPlayed(played))
        .. (split and "" or ("     " .. L["Total gold: %s"]:format(GetCoinTextureString(total)))))
    frame:SetHeight(54 + y + 32)
end

---------------------------------------------------------------------------
-- Panels opened beside the overview (Reputation, Lockouts): each goes where it covers
-- neither the overview nor another of them that's open, as far as the screen allows
-- (owner, 2026-11-08: one placed below a low overview was pushed up over it by the screen
-- edge, and the two opened in the same spot). Tried in turn: below the overview, beside or
-- below another open panel, above the overview, right of it, left of it, left of another;
-- the first that fits on screen covering nothing wins, else below the overview as before.
-- Anchored to the overview (or that panel), so they follow it when it's dragged. Our windows
-- share one scale, so their edges compare directly. Placed when opened, after it's sized.
---------------------------------------------------------------------------
local GAP = 4
local dockable = {}

-- A window's edges, or nil if the game hasn't laid it out.
local function Edges(f)
    local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
    if issecretvalue(l) or issecretvalue(r) or issecretvalue(t) or issecretvalue(b) then return nil end
    if type(l) ~= "number" or type(r) ~= "number" or type(t) ~= "number" or type(b) ~= "number" then return nil end
    return { f, l, r, t, b }
end

function ns.DockToOverview(panel)
    dockable[panel] = true
    panel:ClearAllPoints()
    local overview = AltsForeverFrame
    if not (overview and overview:IsShown()) then return panel:SetPoint("CENTER") end
    local ov = Edges(overview)
    local w, h = panel:GetWidth(), panel:GetHeight()
    local scale = ns.WindowScale()
    local sw, sh = UIParent:GetWidth() / scale, UIParent:GetHeight() / scale
    if ov and w > 0 and h > 0 and sw > 0 and sh > 0 then
        local taken, others = { ov }, {}
        for other in pairs(dockable) do
            if other ~= panel and other:IsShown() then
                local e = Edges(other)
                if e then taken[#taken + 1], others[#others + 1] = e, e end
            end
        end
        local function Fits(x, top)
            local right, bottom = x + w, top - h
            if x < 0 or right > sw or bottom < 0 or top > sh then return false end
            for _, e in ipairs(taken) do
                if x < e[3] and right > e[2] and top > e[5] and bottom < e[4] then return false end
            end
            return true
        end
        local function Try(x, top, point, rel, relPoint, dx, dy)
            if not Fits(x, top) then return false end
            panel:SetPoint(point, rel, relPoint, dx, dy)
            return true
        end
        local l, r, t, b = ov[2], ov[3], ov[4], ov[5]
        if Try(l, b - GAP, "TOPLEFT", overview, "BOTTOMLEFT", 0, -GAP) then return end
        for _, e in ipairs(others) do
            if Try(e[3] + GAP, e[4], "TOPLEFT", e[1], "TOPRIGHT", GAP, 0) then return end
            if Try(e[2], e[5] - GAP, "TOPLEFT", e[1], "BOTTOMLEFT", 0, -GAP) then return end
        end
        if Try(l, t + GAP + h, "BOTTOMLEFT", overview, "TOPLEFT", 0, GAP) then return end
        if Try(r + GAP, t, "TOPLEFT", overview, "TOPRIGHT", GAP, 0) then return end
        if Try(l - GAP - w, t, "TOPRIGHT", overview, "TOPLEFT", -GAP, 0) then return end
        for _, e in ipairs(others) do
            if Try(e[2] - GAP - w, e[4], "TOPRIGHT", e[1], "TOPLEFT", -GAP, 0) then return end
        end
    end
    panel:SetPoint("TOPLEFT", overview, "BOTTOMLEFT", 0, -GAP)
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
    rows, heads = {}, {}
    f:SetSize(width, 200)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    -- Comes to the front when clicked or opened, so our windows never draw through each other.
    f:SetToplevel(true)
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
    f.sorts = {}
    local arrow = header:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(12, 12)
    f.sortArrow = arrow
    for i, fs in ipairs(CreateCells(header, "GameFontNormalSmall")) do
        local col = COLUMNS[i]
        fs:SetText(col.title)
        if col.sort then
            -- The title is a button: click to order by this column, again to turn it round.
            local b = CreateFrame("Button", nil, header)
            b:SetPoint("LEFT", fs, "LEFT", -4, 0)
            b:SetSize(col.width - 2, ROW_HEIGHT)
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.08)
            b.sort, b.title, b.col = col.sort, fs, col
            b:SetScript("OnClick", SortClick)
            b:SetScript("OnEnter", SortTooltip)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            f.sorts[col.sort] = b
        end
    end

    footer = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.footer = footer
    footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 12)
    -- Options (cog) button in the title bar, left of the close button.
    local cog = CreateFrame("Button", nil, f)
    cog:SetSize(16, 16)
    cog:SetPoint("TOPRIGHT", f, "TOPRIGHT", -28, -4)
    cog:SetNormalTexture("Interface\\Icons\\INV_Misc_Gear_01")
    cog:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    cog:SetScript("OnClick", function(self) ns.ShowOptionsMenu(self, true) end)
    cog:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Options"])
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
        GameTooltip:AddLine(L["Reputation"])
        GameTooltip:AddLine(L["Every character's standing with each faction"], 1, 1, 1)
        GameTooltip:Show()
    end)
    rep:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.repButton = rep
    -- Lockouts window button, left of the reputation button.
    local lockouts = CreateFrame("Button", nil, f)
    lockouts:SetSize(16, 16)
    lockouts:SetPoint("RIGHT", rep, "LEFT", -6, 0)
    lockouts:SetNormalTexture("Interface\\Icons\\INV_Misc_Key_03")
    lockouts:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    lockouts:SetScript("OnClick", function() ns.ToggleLockouts() end)
    lockouts:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Lockouts"])
        GameTooltip:AddLine(L["Your characters' raid lockouts, and the instances each game account has entered this hour"], 1, 1, 1)
        GameTooltip:Show()
    end)
    lockouts:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.lockoutsButton = lockouts
    -- Professions window button, left of the lockouts button (Recipes.lua).
    local profs = CreateFrame("Button", nil, f)
    profs:SetSize(16, 16)
    profs:SetPoint("RIGHT", lockouts, "LEFT", -6, 0)
    profs:SetNormalTexture("Interface\\Icons\\Trade_BlackSmithing")
    profs:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    profs:SetScript("OnClick", function() ns.ToggleRecipes() end)
    profs:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Professions"])
        GameTooltip:AddLine(L["Any character's professions and recipes, even while they're offline"], 1, 1, 1)
        GameTooltip:Show()
    end)
    profs:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.profsButton = profs
    -- Bags and bank window button, left of the professions button.
    local bags = CreateFrame("Button", nil, f)
    bags:SetSize(16, 16)
    bags:SetPoint("RIGHT", profs, "LEFT", -6, 0)
    bags:SetNormalTexture("Interface\\Icons\\INV_Misc_Bag_08")
    bags:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    bags:SetScript("OnClick", function() ns.ShowBags(ns.charKey, "bags") end)
    bags:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Bags and bank"])
        GameTooltip:AddLine(L["Any character's bags and bank, slot by slot"], 1, 1, 1)
        GameTooltip:Show()
    end)
    bags:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.bagsButton = bags
    -- Search button, left of the bags button.
    local search = CreateFrame("Button", nil, f)
    search:SetSize(16, 16)
    search:SetPoint("RIGHT", bags, "LEFT", -6, 0)
    search:SetNormalTexture("Interface\\Icons\\INV_Misc_Spyglass_02")
    search:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    search:SetScript("OnClick", function() ns.ToggleSearch() end)
    search:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Search your characters"])
        GameTooltip:AddLine(L["Find an item on any character, or who can craft it. Same as /afs."], 1, 1, 1)
        GameTooltip:Show()
    end)
    search:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.searchButton = search
    -- Export button, left of the search button.
    local export = CreateFrame("Button", nil, f)
    export:SetSize(16, 16)
    export:SetPoint("RIGHT", search, "LEFT", -6, 0)
    export:SetNormalTexture("Interface\\Icons\\INV_Misc_Note_01")
    export:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    export:SetScript("OnClick", function() ns.ToggleExport() end)
    export:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Export your characters"])
        GameTooltip:AddLine(L["Your characters as text, to copy into notes or a spreadsheet. Same as /af export."], 1, 1, 1)
        GameTooltip:Show()
    end)
    export:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.exportButton = export
    -- Sync button, left of the export button.
    local sync = CreateFrame("Button", nil, f)
    sync:SetSize(16, 16)
    sync:SetPoint("RIGHT", export, "LEFT", -6, 0)
    sync:SetNormalTexture("Interface\\Buttons\\UI-RefreshButton")
    sync:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    sync:SetScript("OnClick", function() ns.ToggleSync() end)
    sync:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Sync with another account"])
        GameTooltip:AddLine(L["Swap characters with Alts Forever on your other game account. Same as /af sync."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    sync:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.syncButton = sync
    f.credit = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.credit:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 12)
    f.credit:SetText(L["Alts Forever by Kadmai"])

    ns.SkinWindow(f)
    f:SetScript("OnShow", function(self)
        self:Raise()
        ns.PruneSaves(time())
        MarkSort()
        Refresh()
    end)
    f:SetScript("OnHide", function()
        if AltsForeverGearFrame then AltsForeverGearFrame:Hide() end
        if AltsForeverRepFrame then AltsForeverRepFrame:Hide() end
    end)
    -- Escape closes it, like Blizzard's own windows.
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "AltsForeverFrame" end
    f:Hide()
    ns.GamepadWindow(f)
    ns.ScaleWindow(f)
end

-- Opens or closes the overview; `open` only ever opens it (menus, settings page).
function ns.ToggleOverview(open)
    if not frame then CreateWindow() end
    if frame:IsShown() and not open then return frame:Hide() end
    frame:Show()
    frame:Raise() -- already open: to the front, over other windows
end

function ns.OverviewShown()
    return frame and frame:IsShown() or false
end

-- `sorted`: the order was changed, so the arrow beside the column titles moves too.
function ns.RefreshOverview(sorted)
    if not (frame and frame:IsShown()) then return end
    if sorted then MarkSort() end
    Refresh()
end

function ns.StartOverview()
    -- Keep an open window current; a closed or never-opened one costs nothing.
    local function Update()
        if frame and frame:IsShown() then Refresh() end
    end
    for _, event in ipairs({ "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_MONEY", "ZONE_CHANGED_NEW_AREA", "SKILL_LINES_CHANGED" }) do
        ns.On(event, Update)
    end
end
