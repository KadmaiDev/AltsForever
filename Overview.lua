-- Alts Forever overview: a window (/af) listing every character with level, rested
-- XP, gold, professions, location, time played and when they were last played. It's
-- only built the first time it's opened, and only refreshes while it's showing.
local _, ns = ...

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
    if c.profs and next(c.profs) then
        tt:AddLine(" ")
        local skillups = ns.SkillupsOn()
        for name, skill in pairs(c.profs) do
            local right = skill
            if skillups then
                local n = ns.SkillupCount(c, name)
                if ns.AtRankCap(c, name) then
                    -- At the final maximum there's nothing to train, so say nothing.
                    if skill < MAX_PROFESSION then right = skill .. GREY .. "  (train to skill up)|r" end
                elseif n then
                    right = skill .. GREY .. "  (" .. n .. " skill-up recipe" .. (n == 1 and "" or "s") .. ")|r"
                end
            end
            tt:AddDoubleLine(name, right, 1, 1, 1, 1, 1, 1)
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
-- XP bar tooltip: hovering the experience bar adds every character still levelling
-- (you first, then by level) with their level, XP and rested XP. Built only on hover.
---------------------------------------------------------------------------

-- Adds the lines; returns false (adding nothing) unless another character is levelling
-- too: the bar's own tooltip already covers you.
function ns.AddXPLines(tt, now)
    local chars, maxLevel = ns.db.chars, ns.MaxLevel()
    local n = 0
    for _, key in ipairs(ns.OverviewOrder()) do
        local c = chars[key]
        if c.level and c.level < maxLevel and key ~= ns.charKey then n = n + 1 end
    end
    if n == 0 then return false end
    tt:AddLine(" ")
    tt:AddLine("Your characters", 1, 0.82, 0)
    for _, key in ipairs(ns.OverviewOrder()) do
        local c = chars[key]
        if c.level and c.level < maxLevel then
            tt:AddDoubleLine(ns.ColoredName(key, c),
                ns.LevelText(c) .. "   " .. GREY .. "rested|r " .. ns.RestedText(c, now), 1, 1, 1, 1, 1, 1)
        end
    end
    return true
end

-- Blizzard's bar has no tooltip of its own, so we open one; ElvUI's and EllesmereUI's
-- show theirs (unless the player made the bar click-through, or is at max level), and
-- we add to it.
local function HookXPBar(bar, ownTooltip)
    if not bar or bar.altsForeverXP or not bar.HookScript then return end
    bar.altsForeverXP = true
    bar:HookScript("OnEnter", function(self)
        local tt = GameTooltip
        if tt:IsForbidden() then return end
        if tt:IsShown() then
            if ns.AddXPLines(tt, time()) then tt:Show() end
        elseif ownTooltip then
            tt:SetOwner(self, "ANCHOR_TOP")
            if ns.AddXPLines(tt, time()) then tt:Show() else tt:Hide() end
        end
    end)
    if ownTooltip then
        bar:HookScript("OnLeave", function(self)
            if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        end)
    end
end

-- Blizzard's experience bar sits in a status tracking container (with reputation etc.);
-- it's the one with a rested (exhaustion) marker.
local function BlizzardXPBars(container, found)
    if not container then return end
    if type(container.bars) == "table" then
        for _, bar in pairs(container.bars) do
            if type(bar) == "table" and bar.ExhaustionTick then found[#found + 1] = bar end
        end
    end
    for i = 1, select("#", container:GetChildren()) do
        local bar = select(i, container:GetChildren())
        if bar and bar.ExhaustionTick then found[#found + 1] = bar end
    end
end

-- Hooks each XP bar once. Other UIs make theirs during their own login setup, so this
-- runs on entering the world (after every addon's login) and again after each loading
-- screen, which costs nothing once hooked.
local function HookXPBars()
    local found = {}
    BlizzardXPBars(MainStatusTrackingBarContainer, found)
    BlizzardXPBars(SecondaryStatusTrackingBarContainer, found)
    for _, bar in ipairs(found) do HookXPBar(bar, true) end
    HookXPBar(ElvUI_ExperienceBarHolder, false)
    HookXPBar(EllesmereEAB_XPBar, false)
end

function ns.StartOverview()
    -- Keep an open window current; a closed or never-opened one costs nothing.
    local function Update()
        if frame and frame:IsShown() then Refresh() end
    end
    for _, event in ipairs({ "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_MONEY", "ZONE_CHANGED_NEW_AREA", "SKILL_LINES_CHANGED" }) do
        ns.On(event, Update)
    end
    ns.On("PLAYER_ENTERING_WORLD", HookXPBars)
end
