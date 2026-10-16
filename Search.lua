-- Alts Forever search: every item any of your characters has, or can craft, by name
-- (the owner's idea, 2026-10-16, after trying EasyFind and Forever Spotlight; theirs search
-- the whole game, ours your characters). One row per item: how many, who has them, who can
-- make it. Enter opens the bags window on the character who has it (you first, else the
-- most), with it lit up; Shift+Enter links it in chat. Only item IDs are stored, so names
-- are looked up when the window opens and let go when it closes:
-- nothing is kept or runs while it's shut.
local _, ns = ...
if ns.disabled then return end -- another copy of Alts Forever is running (Core.lua)
local L = ns.L

local C_Item = C_Item
local issecretvalue = issecretvalue or function() return false end
local floor, min, max = math.floor, math.min, math.max
local sort, wipe = table.sort, wipe

local ROWS, ROW, WIDTH = 8, 36, 480
local MAX_MATCHES = 50
local SHOWN_HOLDERS = 3
local LOCS = { "bags", "bank", "mail", "equip" }
local GREY = "|cff9d9d9d"
local SEP = " · "

local frame, box
local rows = {}
local pool, names     -- every item's lower-case name, and its name, while the window is shown
local matches = {}
local selected, offset = 1, 0
local retried

local function ItemName(id)
    local name = C_Item.GetItemNameByID(id)
    if type(name) == "string" and name ~= "" and not issecretvalue(name) then return name end
end

---------------------------------------------------------------------------
-- What there is to find
---------------------------------------------------------------------------
-- Every item ID on the characters tooltips show (your ruleset and faction, unless "Show
-- other rulesets and factions" is on): owned anywhere, or made by a recipe they know.
-- Returns true if some names are still loading (they've been asked for).
local function Build()
    local seen, loading = {}, false
    pool, names = {}, {}
    for _, c in pairs(ns.db.chars) do
        if not ns.Hidden(c) then
            for i = 1, #LOCS do
                local t = c[LOCS[i]]
                if t then for id in pairs(t) do seen[id] = true end end
            end
            for _, items in pairs(c.crafts or {}) do
                for id in pairs(items) do
                    if type(id) == "number" then seen[id] = true end
                end
            end
        end
    end
    for id in pairs(seen) do
        local name = ItemName(id)
        if name then
            names[id] = name
            pool[#pool + 1] = { id = id, low = name:lower() }
        else
            loading = true
            if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        end
    end
    return loading
end

local function ByCount(a, b)
    if a.n ~= b.n then return a.n > b.n end
    return a.key < b.key
end

local function YouFirst(a, b)
    if (a.key == ns.charKey) ~= (b.key == ns.charKey) then return a.key == ns.charKey end
    return a.key < b.key
end

-- Who has the item, most first, and how many in all.
local function Holders(id)
    local list, total = {}, 0
    for key, c in pairs(ns.db.chars) do
        if not ns.Hidden(c) then
            local n = 0
            for i = 1, #LOCS do
                local t = c[LOCS[i]]
                n = n + (t and t[id] or 0)
            end
            if n > 0 then
                list[#list + 1] = { key = key, c = c, n = n }
                total = total + n
            end
        end
    end
    sort(list, ByCount)
    return list, total
end

-- Who can make it, and with which profession (the one whose entry is the recipe's).
local function Crafters(id)
    local list = {}
    for key, c in pairs(ns.db.chars) do
        local crafts = not ns.Hidden(c) and c.crafts
        if crafts then
            for prof, items in pairs(crafts) do
                if items[id] and ns.CraftProf(crafts, prof, id) == prof then
                    list[#list + 1] = { key = key, c = c, prof = prof }
                    break
                end
            end
        end
    end
    sort(list, YouFirst)
    return list
end

---------------------------------------------------------------------------
-- Matching
---------------------------------------------------------------------------
-- How well a name matches: 0 the whole name, 1 its start, 2 the start of a later word,
-- 3 anywhere, 4 every word typed somewhere in it; nil not at all.
local function Rank(low, text, words)
    if low == text then return 0 end
    local s = low:find(text, 1, true)
    if s == 1 then return 1 end
    if s then return low:sub(s - 1, s - 1):find("[%s%-%(:']") and 2 or 3 end
    if #words < 2 then return nil end
    for i = 1, #words do
        if not low:find(words[i], 1, true) then return nil end
    end
    return 4
end

local function Better(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    if a.total ~= b.total then return a.total > b.total end
    return a.low < b.low
end

-- "@owned linen", "@craft sword": a word after @ narrows to one side; any start of the
-- word will do. The same words in every language, as the hint says.
local FILTERS = { "owned", "craft" }

local function Filter(word)
    if word == "" then return nil end
    for _, f in ipairs(FILTERS) do
        if f:find(word, 1, true) == 1 then return f end
    end
end

function ns.SearchMatches(text)
    wipe(matches)
    selected, offset = 1, 0
    text = (text or ""):lower():match("^%s*(.-)%s*$")
    local filter
    local word, rest = text:match("^@(%S*)%s*(.*)$")
    if word then
        filter = Filter(word)
        text = rest
    end
    if text == "" or not pool then return matches end
    local words = {}
    for w in text:gmatch("%S+") do words[#words + 1] = w end
    for _, e in ipairs(pool) do
        local rank = Rank(e.low, text, words)
        if rank then
            e.rank = rank
            e.holders, e.total = Holders(e.id)
            e.crafters = Crafters(e.id)
            if (filter ~= "owned" or e.total > 0) and (filter ~= "craft" or #e.crafters > 0) then
                matches[#matches + 1] = e
            end
        end
    end
    sort(matches, Better)
    for i = #matches, MAX_MATCHES + 1, -1 do matches[i] = nil end
    return matches
end

-- The row's second line: who has how many, then who can make it. The total sits apart,
-- at the end of the name's line (owner, 2026-10-16: "1 Sabine 1" read as two numbers
-- around her name).
function ns.SearchDetail(e)
    local parts = {}
    if e.total > 0 then
        local who = {}
        for i = 1, min(#e.holders, SHOWN_HOLDERS) do
            local h = e.holders[i]
            who[i] = ns.ListShortName(h.key, h.c) .. " " .. h.n
        end
        if #e.holders > SHOWN_HOLDERS then who[#who + 1] = L["+%d more"]:format(#e.holders - SHOWN_HOLDERS) end
        parts[#parts + 1] = table.concat(who, ", ")
    else
        parts[#parts + 1] = GREY .. L["none owned"] .. "|r"
    end
    if #e.crafters > 0 then
        local who = {}
        for i, cr in ipairs(e.crafters) do
            if i > SHOWN_HOLDERS then
                who[#who + 1] = L["+%d more"]:format(#e.crafters - SHOWN_HOLDERS)
                break
            end
            who[i] = ns.ListShortName(cr.key, cr.c) .. GREY .. " (" .. cr.prof .. ")|r"
        end
        parts[#parts + 1] = GREY .. L["can craft:"] .. "|r " .. table.concat(who, ", ")
    end
    return table.concat(parts, GREY .. SEP .. "|r")
end

---------------------------------------------------------------------------
-- Picking one
---------------------------------------------------------------------------
local function Link(e)
    local _, link = C_Item.GetItemInfo(e.id)
    if type(link) ~= "string" or issecretvalue(link) then return end
    -- Into the chat box being typed in; if none is open, open one with it.
    if not (ChatEdit_InsertLink and ChatEdit_InsertLink(link)) and ChatFrame_OpenChat then ChatFrame_OpenChat(link) end
end

-- Enter or a click: the bags or bank of whoever has it (you first, else the most), with it
-- lit up; worn, their gear; only in the mail, said so. Nobody has it: link it.
local function Pick(e, link)
    if not e then return end
    if link then return Link(e) end
    local h = e.holders[1]
    for _, x in ipairs(e.holders) do
        if x.key == ns.charKey then
            h = x
            break
        end
    end
    if not h then return Link(e) end
    local c = h.c
    frame:Hide()
    if c.bags and c.bags[e.id] then
        ns.ShowBags(h.key, "bags", e.id)
    elseif c.bank and c.bank[e.id] then
        ns.ShowBags(h.key, "bank", e.id)
    elseif c.equip and c.equip[e.id] then
        ns.ShowGear(h.key)
    else
        ns.Print(L["%s has it in the mail."]:format(ns.ListName(h.key, c)))
    end
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local Render

local function RowEnter(row)
    selected = row.index
    Render()
    if not row.entry then return end
    -- The item's own tooltip, with everything Alts Forever adds to it: who has it where,
    -- Can craft, upgrades.
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(row.entry.id)
    GameTooltip:Show()
end

local function RowClick(row)
    Pick(row.entry, IsModifiedClick and IsModifiedClick())
end

local function Row(i)
    local row = CreateFrame("Button", nil, frame)
    row:SetHeight(ROW)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -64 - (i - 1) * ROW)
    row:SetPoint("RIGHT", frame, "RIGHT", -30, 0)
    row.lit = row:CreateTexture(nil, "BACKGROUND")
    row.lit:SetAllPoints()
    row.lit:SetColorTexture(1, 1, 1, 0.1)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.05)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(28, 28)
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    -- How many in all, at the right of the name's line.
    row.total = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.total:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -3)
    row.total:SetJustifyH("RIGHT")
    ns.SkinText(row.total)
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -1)
    row.name:SetPoint("RIGHT", row.total, "LEFT", -8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.detail:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 1)
    row.detail:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetWordWrap(false)
    ns.SkinText(row.name)
    ns.SkinText(row.detail)
    row.index = i
    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", RowClick)
    rows[i] = row
    return row
end

local function QualityColor(id)
    local q = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    return c and c.r or 1, c and c.g or 1, c and c.b or 1
end

Render = function()
    local n = #matches
    selected = max(1, min(selected, n))
    if selected <= offset then offset = selected - 1 end
    if selected > offset + ROWS then offset = selected - ROWS end
    offset = max(0, min(offset, n - ROWS))
    for i = 1, ROWS do
        local row, e = rows[i], matches[offset + i]
        row.entry = e
        if e then
            row.icon:SetTexture(C_Item.GetItemIconByID(e.id) or 134400)
            row.name:SetText(names[e.id] or "")
            row.name:SetTextColor(QualityColor(e.id))
            row.total:SetText(e.total > 0 and e.total or "")
            row.detail:SetText(ns.SearchDetail(e))
            row.lit:SetShown(offset + i == selected)
            row:Show()
        else
            row:Hide()
        end
    end
    frame.up:SetEnabled(offset > 0)
    frame.down:SetEnabled(offset + ROWS < n)
    local text = box:GetText() or ""
    local typed = text:match("^%s*@?%S*%s*(.-)%s*$")
    if text:match("^%s*$") or (text:match("^%s*@") and typed == "") then
        frame.status:SetText(GREY .. L["Type part of an item's name: everything your characters have or can craft. Start with @owned or @craft to narrow it."] .. "|r")
    elseif n == 0 then
        frame.status:SetText(GREY .. L["Nothing matching '%s'."]:format(text) .. "|r")
    else
        frame.status:SetText(GREY .. L["Enter: open their bags · Shift+Enter: link in chat"] .. "|r")
    end
end

local function Update()
    ns.SearchMatches(box:GetText())
    Render()
end

local function Move(by)
    if #matches == 0 then return end
    selected = (selected - 1 + by) % #matches + 1
    Render()
end

local function Scroll(by)
    offset = max(0, min(offset + by, #matches - ROWS))
    selected = max(offset + 1, min(selected, offset + ROWS))
    Render()
end

local function CreateWindow()
    local ok, f = pcall(CreateFrame, "Frame", "AltsForeverSearchFrame", UIParent, "BasicFrameTemplateWithInset")
    if not ok then f = CreateFrame("Frame", "AltsForeverSearchFrame", UIParent, "BackdropTemplate") end
    frame = f
    f:SetSize(WIDTH, 64 + ROWS * ROW + 34)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
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
    f.title:SetText(L["Search your characters"])

    local okBox, b = pcall(CreateFrame, "EditBox", "AltsForeverSearchBox", f, "InputBoxTemplate")
    if not okBox then b = CreateFrame("EditBox", "AltsForeverSearchBox", f) end
    box = b
    b:SetHeight(24)
    b:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -32)
    b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -32)
    b:SetAutoFocus(false)
    b:SetFontObject("GameFontHighlight")
    b:SetScript("OnTextChanged", Update)
    b:SetScript("OnEscapePressed", function() f:Hide() end)
    b:SetScript("OnEnterPressed", function() Pick(matches[selected], IsShiftKeyDown and IsShiftKeyDown()) end)
    b:SetScript("OnArrowPressed", function(_, key)
        if key == "UP" then Move(-1) elseif key == "DOWN" then Move(1) end
    end)
    b:SetScript("OnTabPressed", function() Move(IsShiftKeyDown and IsShiftKeyDown() and -1 or 1) end)
    ns.SkinEditBox(b)

    for i = 1, ROWS do Row(i) end
    -- Paging arrows (a controller can't turn the mouse wheel), and the wheel.
    f.up = ns.PageButton(f, true, function() Scroll(-ROWS) end)
    f.up:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -66)
    f.down = ns.PageButton(f, false, function() Scroll(ROWS) end)
    f.down:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -64 - ROWS * ROW + 20)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta) Scroll(-delta) end)

    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.status:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 12)
    f.status:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 12)
    f.status:SetJustifyH("LEFT")
    ns.SkinText(f.status)

    ns.SkinWindow(f)
    f:SetScript("OnShow", function(self)
        self:Raise()
        retried = false
        if Build() and C_Timer and C_Timer.After then
            -- Some names were still loading: once more in a second, if still open.
            C_Timer.After(1, function()
                if frame:IsShown() and not retried then
                    retried = true
                    Build()
                    Update()
                end
            end)
        end
        Update()
        -- A frame later: focused at once, the key that opened it (a binding) would be typed in.
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() if frame:IsShown() then box:SetFocus() end end)
        else
            box:SetFocus()
        end
    end)
    f:SetScript("OnHide", function()
        box:ClearFocus()
        pool, names = nil, nil
        wipe(matches)
        for i = 1, ROWS do rows[i].entry = nil end
        GameTooltip:Hide()
    end)
    -- Escape closes it, like Blizzard's own windows.
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "AltsForeverSearchFrame" end
    f:Hide()
    ns.GamepadWindow(f)
    ns.ScaleWindow(f)
end

-- Opens the search (with some text to start from), or closes it if open and none is given.
function ns.ToggleSearch(text)
    if not frame then CreateWindow() end
    text = text and text:match("^%s*(.-)%s*$") or ""
    if frame:IsShown() and text == "" then return frame:Hide() end
    box:SetText(text)
    if frame:IsShown() then Update() else frame:Show() end
end

function ns.SearchWindow() return frame end
