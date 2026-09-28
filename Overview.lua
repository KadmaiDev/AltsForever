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
local MAX_PROFESSION = 300 -- the last rank's maximum on Forever (Classic ruleset)
local ROW_HEIGHT = 20
local COLUMNS = {
    { title = L["Character"], width = 180 },
    { title = L["Level"], width = 80 },
    { title = L["Rested"], width = 70 },
    { title = L["Gold"], width = 120, right = true },
    -- Each main profession gets a name column and a right-aligned skill column, so
    -- the skill numbers line up. The gap separates it from the right-aligned gold.
    { title = L["Professions"], width = 104, gap = 16 },
    { title = "", width = 34, right = true },
    { title = "", width = 104, gap = 16 },
    { title = "", width = 34, right = true },
    { title = L["Mail"], width = 60, gap = 16 },
    { title = L["Zone"], width = 140 },
    { title = L["Played"], width = 70, right = true },
    { title = L["Last seen"], width = 80, right = true },
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

-- The level and, below max level, how far into it: the overview shows them in two
-- cells so the percentages line up.
function ns.LevelParts(c)
    if not c.level then return GREY .. "?|r", "" end
    if c.level >= ns.MaxLevel() or not c.xpMax or c.xpMax == 0 then return tostring(c.level), "" end
    -- Multiply first: 5700 / 10000 * 100 is 56.99... in floating point.
    return tostring(c.level), GREY .. floor(c.xp * 100 / c.xpMax) .. "%|r"
end

function ns.LevelText(c)
    local level, pct = ns.LevelParts(c)
    return pct == "" and level or (level .. "  " .. pct)
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
    if d > 0 then return L["%dd %dh"]:format(d, h) end
    if h > 0 then return L["%dh %dm"]:format(h, m) end
    return L["%dm"]:format(m)
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
        if type(name) == "string" and name ~= "" and not issecretvalue(name) then
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
        if c.xpMax and c.xpMax > 0 and c.level < ns.MaxLevel() then
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
    tt:AddLine(" ")
    tt:AddLine(GREY .. (c.bank and L["Bank scanned"] or L["Bank not scanned yet - visit a banker"]) .. "|r")
    if c.dura then tt:AddDoubleLine(L["Lowest durability"], ns.DurabilityText(c.dura), 1, 0.82, 0, 1, 1, 1) end
    if key == ns.charKey then
        tt:AddLine("|cff66ccff" .. L["Click to see gear"] .. "|r")
    else
        tt:AddLine("|cff66ccff" .. L["Click to see gear"] .. " · " .. L["Right-click to forget this character"] .. "|r")
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
        local level, pct = ns.LevelParts(c)
        cells[2]:SetText(level)
        row.pct:SetText(pct)
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
    -- With only one character there's nothing to compare yet: say how to add the others.
    frame.credit:SetText(#keys == 1 and (GREY .. L["Log in on your other characters once to add them here."] .. "|r")
        or L["Alts Forever by Kadmai"])
    footer:SetText(L["Total played: %s"]:format(ns.FormatPlayed(played)) .. "     " .. L["Total gold: %s"]:format(GetCoinTextureString(total)))
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
    -- Bags and bank window button, left of the reputation button.
    local bags = CreateFrame("Button", nil, f)
    bags:SetSize(16, 16)
    bags:SetPoint("RIGHT", rep, "LEFT", -6, 0)
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
    f.credit = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.credit:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 12)
    f.credit:SetText(L["Alts Forever by Kadmai"])

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

function ns.StartOverview()
    -- Keep an open window current; a closed or never-opened one costs nothing.
    local function Update()
        if frame and frame:IsShown() then Refresh() end
    end
    for _, event in ipairs({ "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_MONEY", "ZONE_CHANGED_NEW_AREA", "SKILL_LINES_CHANGED" }) do
        ns.On(event, Update)
    end
end
