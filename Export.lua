-- Alts Forever export: the overview's characters as plain text to copy (a player's request,
-- 2026-10-17, for their own planning page outside the game). An addon can't write a file or
-- the clipboard, so the text sits selected in a box for Ctrl+C. Readable lines by default;
-- with "For spreadsheets" ticked (db.exportTabs) a header row and tab-separated columns,
-- which paste into Google Sheets or Excel as columns. The text is made when the window
-- opens and let go when it closes.
local _, ns = ...
if ns.disabled then return end -- another copy of Alts Forever is running (Core.lua)
local L = ns.L

local floor, ipairs, tostring, type = math.floor, ipairs, tostring, type
local concat = table.concat

local WIDTH, HEIGHT = 680, 440
local SEP = " · "
local TAB = "\t"

local frame, box, scroll, check
local text -- what the box holds while open: typing in it puts this back

-- Colour codes and icons out: the text leaves the game.
function ns.PlainText(s)
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""))
end
local Plain = ns.PlainText

-- "1,234g 5s 7c" in the game's own symbols (the letters differ by language).
function ns.PlainMoney(copper)
    local g, s, c = floor(copper / 10000), floor(copper % 10000 / 100), copper % 100
    local big = BreakUpLargeNumbers or tostring
    local parts = {}
    if g > 0 then parts[#parts + 1] = big(g) .. (GOLD_AMOUNT_SYMBOL or "g") end
    if s > 0 then parts[#parts + 1] = s .. (SILVER_AMOUNT_SYMBOL or "s") end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. (COPPER_AMOUNT_SYMBOL or "c") end
    return concat(parts, " ")
end

local function ClassName(c)
    local names = LOCALIZED_CLASS_NAMES_MALE
    return type(names) == "table" and names[c.class] or c.class
end

-- Rested as "45%", or nil when unknown or at max level.
local function Rested(c, now)
    local r = Plain(ns.RestedText(c, now))
    return r:find("%%$") and r or nil
end

-- The professions as name and skill pairs, or nil when unknown or none.
local function Profs(c)
    local n1, s1, n2, s2 = ns.ProfCells(c)
    n1, n2 = Plain(n1), Plain(n2)
    if n1 == "?" or n1 == "-" then return nil end
    return n1, s1, n2, s2
end

-- One readable line: only what's known, with words saying what each number is.
local function Line(key, c, now)
    local out = { key }
    local class = ClassName(c)
    if class then out[#out + 1] = class end
    if c.level then
        local _, pct = ns.LevelParts(c)
        pct = Plain(pct)
        out[#out + 1] = L["Level %d"]:format(c.level) .. (pct ~= "" and (" (" .. pct .. ")") or "")
    end
    local rested = Rested(c, now)
    if rested then out[#out + 1] = L["Rested %s"]:format(rested) end
    if c.wellRested then out[#out + 1] = L["Well Rested %s"]:format(c.wellRested .. "/5") end
    if ns.LegacyUnspent(c) then
        out[#out + 1] = L["Legacy %s"]:format(Plain((ns.LegacyCells(c))))
    end
    if c.money then out[#out + 1] = ns.PlainMoney(c.money) end
    local n1, s1, n2, s2 = Profs(c)
    if n1 then
        local p = n1 ~= "" and (n1 .. " " .. s1) or ""
        if n2 ~= "" then p = (p ~= "" and (p .. ", ") or "") .. n2 .. " " .. s2 end
        if p ~= "" then out[#out + 1] = p end
    end
    if c.mail and c.mailExpires then
        local left = c.mailExpires - now
        out[#out + 1] = left > 0 and L["Mail expires in %s"]:format(ns.ExpiryText(left)) or L["Mail has expired"]
    end
    if c.zone then out[#out + 1] = c.zone end
    local played = ns.PlayedNow(c, now)
    if played then out[#out + 1] = L["Played %s"]:format(ns.FormatPlayed(played)) end
    if key == ns.charKey then
        out[#out + 1] = L["Playing now"]
    elseif c.updated or c.seen then
        out[#out + 1] = L["Last seen %s"]:format(ns.FormatAgo(now - (c.updated or c.seen)))
    end
    return concat(out, SEP)
end

local function Cell(v)
    if v == nil then return "" end
    return (tostring(v):gsub("[\t\r\n]", " "))
end

local function When(t) return t and date("%Y-%m-%d %H:%M", t) or nil end

-- Gold as a number to the silver ("312.10"), with the decimal mark of the game's language,
-- which is likely the spreadsheet's too ("312,10" in German).
local function GoldNumber(copper)
    return floor(copper / 10000) .. (DECIMAL_SEPERATOR or ".") .. ("%02d"):format(floor(copper % 10000 / 100))
end

local function Header(groups)
    local cols = { L["Character"], L["Class"], L["Level"], L["XP"], L["Rested"], L["Well Rested"],
        L["Legacy spent"], L["Legacy to spend"], L["Gold"], L["Profession"], L["Skill"],
        L["Profession"], L["Skill"], L["Mail expires"], L["Zone"], L["Played (hours)"], L["Last seen"] }
    if groups then table.insert(cols, 1, L["Group"]) end
    return concat(cols, TAB)
end

-- One spreadsheet row: numbers as plain numbers (gold, hours), times as dates, so a
-- spreadsheet can sort and add them; a blank cell where it isn't known.
local function Row(key, c, now, group)
    local _, pct = ns.LevelParts(c)
    local unspent = ns.LegacyUnspent(c)
    local n1, s1, n2, s2 = Profs(c)
    local played = ns.PlayedNow(c, now)
    local cells = {
        key, ClassName(c), c.level, Plain(pct), Rested(c, now), c.wellRested,
        unspent and c.legacySpent, unspent,
        c.money and GoldNumber(c.money),
        n1, n1 and s1 ~= "" and s1 or nil, n2, n2 and s2 ~= "" and s2 or nil,
        c.mail and When(c.mailExpires), c.zone, played and floor(played / 3600),
        When(key == ns.charKey and now or c.updated or c.seen),
    }
    local out = {}
    if group then out[1] = Cell(group) end
    for i = 1, 17 do out[#out + 1] = Cell(cells[i]) end
    return concat(out, TAB)
end

-- Every character, in the overview's order and groups (rulesets and factions).
function ns.ExportText(tabs)
    local now = time()
    local chars = ns.db.chars
    local keys = ns.OverviewOrder()
    local byRealm, byFaction = ns.GroupParts()
    local split = byRealm or byFaction
    local lines = {}
    if tabs then
        lines[1] = Header(split)
        for _, key in ipairs(keys) do
            local c = chars[key]
            lines[#lines + 1] = Row(key, c, now, split and ns.GroupLabel(c, byRealm, byFaction))
        end
        return concat(lines, "\n")
    end
    lines[1] = "Alts Forever" .. SEP .. When(now)
    -- Each group headed by its name and gold: gold can't move between them.
    local gold, group = {}, nil
    if split then
        for _, key in ipairs(keys) do
            local g = ns.GroupKey(chars[key], byRealm, byFaction)
            gold[g] = (gold[g] or 0) + (chars[key].money or 0)
        end
    end
    local total, played, anyPlayed = 0, 0, false
    for _, key in ipairs(keys) do
        local c = chars[key]
        if split and ns.GroupKey(c, byRealm, byFaction) ~= group then
            group = ns.GroupKey(c, byRealm, byFaction)
            lines[#lines + 1] = ""
            lines[#lines + 1] = ns.GroupLabel(c, byRealm, byFaction) .. " (" .. ns.PlainMoney(gold[group]) .. ")"
        elseif #lines == 1 then
            lines[#lines + 1] = ""
        end
        lines[#lines + 1] = Line(key, c, now)
        total = total + (c.money or 0)
        local p = ns.PlayedNow(c, now)
        if p then played, anyPlayed = played + p, true end
    end
    lines[#lines + 1] = ""
    if not split then lines[#lines + 1] = L["Total gold: %s"]:format(ns.PlainMoney(total)) end
    if anyPlayed then lines[#lines + 1] = L["Total played: %s"]:format(ns.FormatPlayed(played)) end
    return concat(lines, "\n")
end

local function Fill()
    text = ns.ExportText(ns.db.exportTabs)
    box:SetText(text)
    box:SetFocus()
    box:HighlightText()
    if scroll.SetVerticalScroll then scroll:SetVerticalScroll(0) end
end

local function CreateWindow()
    local ok, f = pcall(CreateFrame, "Frame", "AltsForeverExportFrame", UIParent, "BasicFrameTemplateWithInset")
    if not ok then f = CreateFrame("Frame", "AltsForeverExportFrame", UIParent, "BackdropTemplate") end
    frame = f
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f.title = f.TitleText or f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if not f.TitleText then f.title:SetPoint("TOP", 0, -6) end
    f.title:SetText(L["Export your characters"])

    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.hint:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -38)
    f.hint:SetText(L["Press Ctrl+C to copy, then paste it wherever you like."])

    -- Readable lines, or columns for a spreadsheet: remembered for next time.
    local okCheck, c = pcall(CreateFrame, "CheckButton", nil, f, "UICheckButtonTemplate")
    if not okCheck then c = CreateFrame("CheckButton", nil, f) end
    check = c
    f.check = c
    c:SetSize(24, 24)
    c.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    c.label:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -38)
    c.label:SetText(L["For spreadsheets"])
    c:SetPoint("RIGHT", c.label, "LEFT", -2, 0)
    c:SetScript("OnClick", function(self)
        ns.db.exportTabs = self:GetChecked() and true or nil
        Fill()
    end)
    c:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Columns separated by tabs: they paste into Google Sheets or Excel as columns."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    c:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local okScroll, s = pcall(CreateFrame, "ScrollFrame", "AltsForeverExportScroll", f, "UIPanelScrollFrameTemplate")
    if not okScroll then s = CreateFrame("ScrollFrame", "AltsForeverExportScroll", f) end
    scroll = s
    s:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -66)
    s:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, 14)

    local b = CreateFrame("EditBox", "AltsForeverExportBox", s)
    box = b
    b:SetMultiLine(true)
    b:SetAutoFocus(false)
    b:SetFontObject("ChatFontNormal")
    b:SetWidth(WIDTH - 18 - 34)
    -- Read only: anything typed is put back, still selected for copying.
    b:SetScript("OnTextChanged", function(self, userInput)
        if userInput and text then
            self:SetText(text)
            self:HighlightText()
        end
    end)
    b:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    b:SetScript("OnEscapePressed", function() f:Hide() end)
    s:SetScrollChild(b)
    -- Clicking anywhere in the text area puts the cursor in the box.
    s:EnableMouse(true)
    s:SetScript("OnMouseDown", function() b:SetFocus() end)

    ns.SkinWindow(f)
    ns.SkinCheck(c)
    f:SetScript("OnShow", function(self)
        self:Raise()
        check:SetChecked(ns.db.exportTabs == true)
        Fill()
    end)
    f:SetScript("OnHide", function()
        box:ClearFocus()
        text = nil
        box:SetText("")
        GameTooltip:Hide()
    end)
    -- Escape closes it, like Blizzard's own windows.
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "AltsForeverExportFrame" end
    f:Hide()
    ns.GamepadWindow(f)
    ns.ScaleWindow(f)
end

function ns.ToggleExport()
    if not frame then CreateWindow() end
    if frame:IsShown() then return frame:Hide() end
    frame:Show()
end
