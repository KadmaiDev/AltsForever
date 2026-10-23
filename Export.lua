-- Alts Forever export: the overview's characters as text to copy (a player's request,
-- 2026-10-17, for their own planning page outside the game). An addon can't write a file or
-- the clipboard, so the text sits selected in a box for Ctrl+C. Three formats, picked from a
-- dropdown and remembered (db.exportFormat, nil = spreadsheet, the owner's default):
--  * "tabs": a header row and tab-separated columns, which paste into Google Sheets or
--    Excel as columns;
--  * "text": readable lines for notes or chat;
--  * "markdown": a table that Notion, Obsidian and the like turn into a real one.
-- The text is made when the window opens and let go when it closes.
local _, ns = ...
if ns.disabled then return end -- another copy of Alts Forever is running (Core.lua)
local L = ns.L

local floor, ipairs, pairs, tostring, type = math.floor, ipairs, pairs, tostring, type
local C_Item = C_Item
local concat = table.concat

local WIDTH, HEIGHT = 680, 440
local SEP = " · "
local TAB = "\t"

-- In the dropdown's order. CSV was considered and left out (owner, 2026-10-18): pasted, Excel
-- splits only on tabs, and a comma decimal mark would need every value quoted.
local FORMATS = { "tabs", "text", "markdown" }
local NAMES = { tabs = L["Spreadsheet"], text = L["Text"], markdown = L["Markdown table"] }
local CHOICES = {
    tabs = L["Spreadsheet (Excel, Google Sheets)"],
    text = L["Text (notes, chat, documents)"],
    markdown = L["Markdown table (Notion, Obsidian)"],
}

local frame, box, scroll
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

function ns.ExportFormat()
    local f = ns.db.exportFormat
    return NAMES[f] and f or "tabs"
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

local function When(t) return t and date("%Y-%m-%d %H:%M", t) or nil end

-- What the readable formats show of a character, as text; nil where it isn't known.
local function Readable(key, c, now)
    local _, pct = ns.LevelParts(c)
    pct = Plain(pct)
    local r = {
        class = ClassName(c),
        xp = pct ~= "" and pct or nil,
        rested = Rested(c, now),
        wellRested = c.wellRested and (c.wellRested .. "/5"),
        legacy = ns.LegacyUnspent(c) and Plain((ns.LegacyCells(c))),
        gold = c.money and ns.PlainMoney(c.money),
        zone = c.zone,
    }
    local n1, s1, n2, s2 = Profs(c)
    if n1 then
        local p = n1 ~= "" and (n1 .. " " .. s1) or ""
        if n2 ~= "" then p = (p ~= "" and (p .. ", ") or "") .. n2 .. " " .. s2 end
        if p ~= "" then r.profs = p end
    end
    if c.mail and c.mailExpires then r.mailLeft = c.mailExpires - now end
    local played = ns.PlayedNow(c, now)
    if played then r.played = ns.FormatPlayed(played) end
    if key == ns.charKey then
        r.seen = L["Playing now"]
    elseif c.updated or c.seen then
        r.ago = ns.FormatAgo(now - (c.updated or c.seen))
    end
    return r
end

-- One readable line: only what's known, with words saying what each number is.
local function Line(key, c, now)
    local r = Readable(key, c, now)
    local out = { key }
    local function Add(v) if v then out[#out + 1] = v end end
    Add(r.class)
    if c.level then Add(L["Level %d"]:format(c.level) .. (r.xp and (" (" .. r.xp .. ")") or "")) end
    Add(r.rested and L["Rested %s"]:format(r.rested))
    Add(r.wellRested and L["Well Rested %s"]:format(r.wellRested))
    Add(r.legacy and L["Legacy %s"]:format(r.legacy))
    Add(r.gold)
    Add(r.profs)
    if r.mailLeft then
        Add(r.mailLeft > 0 and L["Mail expires in %s"]:format(ns.ExpiryText(r.mailLeft)) or L["Mail has expired"])
    end
    Add(r.zone)
    Add(r.played and L["Played %s"]:format(r.played))
    Add(r.seen or (r.ago and L["Last seen %s"]:format(r.ago)))
    return concat(out, SEP)
end

-- A Markdown table: the header, then the line under it (numbers right-aligned).
local function MarkdownHeader()
    return "| " .. concat({ L["Character"], L["Class"], L["Level"], L["XP"], L["Rested"], L["Well Rested"],
        L["Legacy"], L["Gold"], L["Professions"], L["Mail expires"], L["Zone"], L["Played"], L["Last seen"] }, " | ")
        .. " |", "|---|---|--:|--:|--:|:-:|:-:|--:|---|---|---|--:|---|"
end

local function MarkdownRow(key, c, now)
    local r = Readable(key, c, now)
    local mail = r.mailLeft and ns.ExpiryText(r.mailLeft)
    local cells = { key, r.class, c.level, r.xp, r.rested, r.wellRested, r.legacy, r.gold, r.profs, mail,
        r.zone, r.played, r.seen or r.ago }
    local out = {}
    for i = 1, 13 do
        -- A | in a cell would end it.
        out[i] = cells[i] == nil and "" or (tostring(cells[i]):gsub("[\r\n]", " "):gsub("|", "\\|"))
    end
    return "| " .. concat(out, " | ") .. " |"
end

local function Cell(v)
    if v == nil then return "" end
    return (tostring(v):gsub("[\t\r\n]", " "))
end

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

-- Every character, in the overview's order and groups (rulesets and factions), in one of
-- the FORMATS (default: the saved choice).
function ns.ExportText(format)
    format = format or ns.ExportFormat()
    local now = time()
    local chars = ns.db.chars
    local keys = ns.OverviewOrder()
    local byRealm, byFaction = ns.GroupParts()
    local split = byRealm or byFaction
    local lines = {}
    if format == "tabs" then
        lines[1] = Header(split)
        for _, key in ipairs(keys) do
            local c = chars[key]
            lines[#lines + 1] = Row(key, c, now, split and ns.GroupLabel(c, byRealm, byFaction))
        end
        return concat(lines, "\n")
    end
    local md = format == "markdown"
    local function Table()
        if not md then return end
        local head, under = MarkdownHeader()
        lines[#lines + 1] = head
        lines[#lines + 1] = under
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
            lines[#lines + 1] = (md and "### " or "") .. ns.GroupLabel(c, byRealm, byFaction)
                .. " (" .. ns.PlainMoney(gold[group]) .. ")"
            if md then lines[#lines + 1] = "" end
            Table()
        elseif #lines == 1 then
            lines[#lines + 1] = ""
            Table()
        end
        lines[#lines + 1] = md and MarkdownRow(key, c, now) or Line(key, c, now)
        total = total + (c.money or 0)
        local p = ns.PlayedNow(c, now)
        if p then played, anyPlayed = played + p, true end
    end
    lines[#lines + 1] = ""
    if not split then lines[#lines + 1] = L["Total gold: %s"]:format(ns.PlainMoney(total)) end
    -- Two lines in Markdown are one paragraph unless a blank line parts them.
    if anyPlayed then
        if md and not split then lines[#lines + 1] = "" end
        lines[#lines + 1] = L["Total played: %s"]:format(ns.FormatPlayed(played))
    end
    return concat(lines, "\n")
end

local function Fill()
    frame.format:SetText(NAMES[ns.ExportFormat()])
    text = ns.ExportText()
    box:SetText(text)
    box:SetFocus()
    box:HighlightText()
    if scroll.SetVerticalScroll then scroll:SetVerticalScroll(0) end
end

local function PickFormat(owner)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        for _, f in ipairs(FORMATS) do
            root:CreateRadio(CHOICES[f], function(v) return v == ns.ExportFormat() end, function(v)
                -- nil for the default, so saves stay small.
                ns.db.exportFormat = v ~= "tabs" and v or nil
                Fill()
            end, f)
        end
    end)
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

    -- The format dropdown, top right; remembered for next time.
    local fmt = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    fmt:SetSize(150, 22)
    fmt:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -33)
    fmt:SetScript("OnClick", PickFormat)
    fmt:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Format"])
        GameTooltip:AddLine(L["Columns for a spreadsheet, readable lines for notes or chat, or a Markdown table for Notion or Obsidian."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    fmt:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ns.SkinButton(fmt)
    f.format = fmt
    f.formatLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.formatLabel:SetPoint("RIGHT", fmt, "LEFT", -6, 0)
    f.formatLabel:SetText(L["Format"])

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
    f:SetScript("OnShow", function(self)
        self:Raise()
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

---------------------------------------------------------------------------
-- Item names in the saved file (a player's request, 2026-10-23, for their own planning page:
-- bags, bank and mail keep only item ID -> count, so outside the game most items can't be
-- told apart). Off by default ("Save item names for use outside the game", /af itemnames): it
-- adds nothing in the game and costs memory (~60-80 KB for the owner's 534 items), so it's
-- only for players who read the file (owner, 2026-10-23). When on: db.itemNames =
-- { [itemID] = name } and db.itemQuality = { [itemID] = quality }, once per item any
-- character has (bags, bank, mail, worn), in the game's language. Filled at logout (and
-- /reload), where it costs nothing in play; items the game hasn't loaded this session are
-- requested 10 s after login, so they're known by then. Turning it off drops both tables.
local PLACES = { "bags", "bank", "mail", "equip" }
local NONE = {} -- a place not scanned yet
local issecretvalue = issecretvalue or function() return false end

local function Owned(chars, id)
    for _, c in pairs(chars) do
        for _, place in ipairs(PLACES) do
            local items = c[place]
            if items and items[id] then return true end
        end
    end
    return false
end

function ns.ItemNamesOn() return ns.db.itemNamesOn == true end

function ns.SetItemNames(on)
    local db = ns.db
    db.itemNamesOn = on or nil
    if on then
        ns.RequestItemNames()
    else
        db.itemNames, db.itemQuality = nil, nil
    end
end

-- Asks the game for every item a character has whose name isn't saved and isn't loaded.
function ns.RequestItemNames()
    local db = ns.db
    if not (db.itemNamesOn and C_Item.RequestLoadItemDataByID and C_Item.IsItemDataCachedByID) then return end
    local names = db.itemNames
    for _, c in pairs(db.chars) do
        for _, place in ipairs(PLACES) do
            for id in pairs(c[place] or NONE) do
                if not (names and names[id]) and not C_Item.IsItemDataCachedByID(id) then
                    C_Item.RequestLoadItemDataByID(id)
                end
            end
        end
    end
end

-- Saves the name and quality of every item a character has that the game knows by now,
-- and drops the items nobody has any more.
function ns.SaveItemNames()
    local db = ns.db
    local names, quality = db.itemNames or {}, db.itemQuality or {}
    db.itemNames, db.itemQuality = names, quality
    for id in pairs(names) do
        if not Owned(db.chars, id) then names[id], quality[id] = nil, nil end
    end
    for _, c in pairs(db.chars) do
        for _, place in ipairs(PLACES) do
            for id in pairs(c[place] or NONE) do
                if not names[id] then
                    local name = C_Item.GetItemNameByID(id)
                    if not issecretvalue(name) and type(name) == "string" and name ~= "" then names[id] = name end
                end
                if names[id] and not quality[id] then
                    local q = C_Item.GetItemQualityByID(id)
                    if not issecretvalue(q) and type(q) == "number" then quality[id] = q end
                end
            end
        end
    end
end

function ns.StartItemNames()
    if C_Timer and C_Timer.After then C_Timer.After(10, ns.RequestItemNames) end
    ns.On("PLAYER_LOGOUT", function()
        if ns.db.itemNamesOn then ns.SaveItemNames() end
    end)
end
