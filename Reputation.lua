-- Alts Forever reputation: records each character's standing with every faction, and
-- shows them side by side in a panel opened from the overview (factions down, your
-- characters across). The panel is only built the first time it's opened.
local _, ns = ...

local floor, pairs, ipairs, wipe, sort = math.floor, pairs, ipairs, wipe, table.sort
local issecretvalue = issecretvalue or function() return false end
local R = C_Reputation

local GREY = "|cff9d9d9d"
local SCAN_DELAY = 10 -- seconds: rep gains come in bursts (every kill), so batch them
local VISIBLE_ROWS = 20
local ROW_HEIGHT, NAME_WIDTH, CELL_WIDTH = 18, 170, 100

-- Classic standings: the lowest value of each level (Hated .. Exalted), then the cap.
local THRESHOLDS = { -42000, -6000, -3000, 0, 3000, 9000, 21000, 42000, 43000 }
local LABELS = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }
local COLORS = { "cc2222", "ff0000", "ee6622", "ffff00", "00ff00", "00ff88", "00ffcc", "00ffff" }

-- Level (1-8), and the level's lowest and next values.
function ns.Standing(value)
    for level = 8, 1, -1 do
        if value >= THRESHOLDS[level] then return level, THRESHOLDS[level], THRESHOLDS[level + 1] end
    end
    return 1, THRESHOLDS[1], THRESHOLDS[2]
end

-- "Honored 27%" in the level's colour; Exalted on its own.
function ns.StandingText(value)
    local level, low, high = ns.Standing(value)
    local label = _G["FACTION_STANDING_LABEL" .. level] or LABELS[level]
    local text = "|cff" .. COLORS[level] .. label
    if level < 8 then text = text .. " " .. floor((value - low) * 100 / (high - low)) .. "%" end
    return text .. "|r"
end

-- Your other characters' standing with the faction you're watching, for the
-- reputation bar's tooltip: standing, how far into it, and the numbers.
function ns.AddRepLines(tt, fresh)
    local d = R and R.GetWatchedFactionData and R.GetWatchedFactionData()
    local id = d and d.factionID
    if not id or issecretvalue(id) or id == 0 then return false end
    local rows = {}
    for _, key in ipairs(ns.OverviewOrder()) do
        local c = ns.db.chars[key]
        local value = key ~= ns.charKey and c.reps and c.reps[id]
        if value then
            local level, low, high = ns.Standing(value)
            local color = "|cff" .. COLORS[level]
            local label = color .. (_G["FACTION_STANDING_LABEL" .. level] or LABELS[level]) .. "|r"
            local pct, progress = "", ""
            if level < 8 then
                pct = color .. floor((value - low) * 100 / (high - low)) .. "%|r"
                progress = GREY .. (value - low) .. " / " .. (high - low) .. "|r"
            end
            rows[#rows + 1] = { ns.ColoredName(key, c), label, pct, progress }
        end
    end
    local title
    if fresh then
        title = ns.db.factions and ns.db.factions[id]
        if not title and d.name and not issecretvalue(d.name) then title = d.name end
    end
    return ns.AddCharacterRows(tt, rows, {}, title or (fresh and "Reputation"))
end

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------
-- c.reps = { [factionID] = standing }; db.factions = { [factionID] = name } (account-wide).
-- The visible list is read, and factions this character had before are re-read by ID, so
-- ones under a collapsed header stay current without touching the player's reputation
-- window (expanding headers would change it and fire UPDATE_FACTION again).
local seen = {}

local function Record(c, names, d)
    local standing = d and d.currentStanding
    if not d or not d.factionID or standing == nil or issecretvalue(standing) then return end
    c.reps[d.factionID] = standing
    if d.name and not issecretvalue(d.name) then names[d.factionID] = d.name end
    seen[d.factionID] = true
end

function ns.ScanReputation(c)
    if not (R and R.GetNumFactions) then return end
    c.reps = c.reps or {}
    local names = ns.db.factions or {}
    ns.db.factions = names
    wipe(seen)
    for i = 1, R.GetNumFactions() do
        local d = R.GetFactionDataByIndex(i)
        if d and (not d.isHeader or d.isHeaderWithRep) then Record(c, names, d) end
    end
    if R.GetFactionDataByID then
        for id in pairs(c.reps) do
            if not seen[id] then Record(c, names, R.GetFactionDataByID(id)) end
        end
    end
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
local panel, rows, header, keys, factions, offset = nil, {}, nil, {}, {}, 0

local function ByName(a, b)
    local names = ns.db.factions
    return (names[a] or "") < (names[b] or "")
end

-- Characters (you first, then by level) and every faction any of them has, by name.
local function Collect()
    wipe(keys)
    for _, key in ipairs(ns.OverviewOrder()) do keys[#keys + 1] = key end
    wipe(factions)
    local names, have = ns.db.factions or {}, {}
    for _, key in ipairs(keys) do
        local reps = ns.db.chars[key].reps
        if reps then
            for id in pairs(reps) do
                if names[id] and not have[id] then
                    have[id] = true
                    factions[#factions + 1] = id
                end
            end
        end
    end
    sort(factions, ByName)
end

local function RowTooltip(row)
    local id = row.faction
    if not id then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ns.db.factions[id])
    for _, key in ipairs(keys) do
        local c = ns.db.chars[key]
        local value = c.reps and c.reps[id]
        if value then
            local level, low, high = ns.Standing(value)
            local detail = level < 8 and (GREY .. "  " .. (value - low) .. " / " .. (high - low) .. "|r") or ""
            GameTooltip:AddDoubleLine(ns.ColoredName(key, c), ns.StandingText(value) .. detail, 1, 1, 1, 1, 1, 1)
        end
    end
    GameTooltip:Show()
end

local function Cell(parent, x, width, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ns.SkinText(fs)
    fs:SetPoint("LEFT", parent, "LEFT", x, 0)
    fs:SetWidth(width - 6)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function Row(i)
    local row = rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, panel)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -52 - (i - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", panel, "RIGHT", -8, 0)
    row:EnableMouse(true)
    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.name = Cell(row, 4, NAME_WIDTH)
    row.cells = {}
    rows[i] = row
    return row
end

local function Fill()
    Collect()
    local n = #keys
    panel:SetWidth(8 + NAME_WIDTH + n * CELL_WIDTH + 16)
    offset = math.max(0, math.min(offset, #factions - VISIBLE_ROWS))
    header.cells = header.cells or {}
    for j, key in ipairs(keys) do
        header.cells[j] = header.cells[j] or Cell(header, NAME_WIDTH + (j - 1) * CELL_WIDTH, CELL_WIDTH, "CENTER")
        header.cells[j]:SetText(ns.ShortName(key, ns.db.chars[key]))
        header.cells[j]:Show()
    end
    for j = n + 1, #header.cells do header.cells[j]:Hide() end
    for i = 1, VISIBLE_ROWS do
        local row, id = Row(i), factions[offset + i]
        row.faction = id
        if id then
            row.name:SetText(ns.db.factions[id])
            for j, key in ipairs(keys) do
                row.cells[j] = row.cells[j] or Cell(row, NAME_WIDTH + (j - 1) * CELL_WIDTH, CELL_WIDTH, "CENTER")
                local c = ns.db.chars[key]
                local value = c.reps and c.reps[id]
                row.cells[j]:SetText(value and ns.StandingText(value) or (GREY .. "-|r"))
                row.cells[j]:Show()
            end
            for j = n + 1, #row.cells do row.cells[j]:Hide() end
            row:Show()
        else
            row:Hide()
        end
    end
    panel.empty:SetShown(#factions == 0)
    local shown = math.min(VISIBLE_ROWS, #factions)
    panel.footer:SetText(#factions > VISIBLE_ROWS
        and (GREY .. (offset + 1) .. "-" .. (offset + shown) .. " of " .. #factions .. " (scroll for more)|r") or "")
    panel:SetHeight(52 + math.max(shown, 3) * ROW_HEIGHT + 30)
end

local function CreatePanel()
    local ok, f = pcall(CreateFrame, "Frame", "AltsForeverRepFrame", UIParent, "BasicFrameTemplateWithInset")
    if not ok then f = CreateFrame("Frame", "AltsForeverRepFrame", UIParent, "BackdropTemplate") end
    panel = f
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta * 3
        Fill()
    end)
    local title = f.TitleText or f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if not f.TitleText then title:SetPoint("TOP", 0, -6) end
    title:SetText("Reputation")
    header = CreateFrame("Frame", nil, f)
    header:SetHeight(ROW_HEIGHT)
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -30)
    header:SetPoint("RIGHT", f, "RIGHT", -8, 0)
    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.empty:SetPoint("CENTER")
    f.empty:SetText(GREY .. "No reputation recorded yet.\nLog in on each character once.|r")
    f.footer = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.footer:SetPoint("BOTTOM", f, "BOTTOM", 0, 10)
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "AltsForeverRepFrame" end
    ns.SkinWindow(f)
    f:Hide()
end

-- Opens the panel beside the overview if it's open; again closes it.
function ns.ToggleReputation()
    if not panel then CreatePanel() end
    if panel:IsShown() then return panel:Hide() end
    offset = 0
    panel:ClearAllPoints()
    if AltsForeverFrame and AltsForeverFrame:IsShown() then
        panel:SetPoint("TOPLEFT", AltsForeverFrame, "BOTTOMLEFT", 0, -4)
    else
        panel:SetPoint("CENTER")
    end
    Fill()
    panel:Show()
end

function ns.StartReputation()
    local char = ns.char
    local pending = false
    local function Scan()
        pending = false
        ns.ScanReputation(char)
        if panel and panel:IsShown() then Fill() end
    end
    ns.On("UPDATE_FACTION", function()
        if pending or not C_Timer then return end
        pending = true
        C_Timer.After(SCAN_DELAY, Scan)
    end)
    -- The list may not be ready the moment you log in.
    if C_Timer then C_Timer.After(3, Scan) else Scan() end
end
