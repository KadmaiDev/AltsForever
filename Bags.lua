-- Alts Forever bags window: any character's bags or bank, slot by slot, as last seen.
-- Opened from the overview's title bar, a character's right-click menu, /af bags and
-- /af bank. The slots come from the scanner (char.layout); for characters not scanned
-- since this was added, the window falls back to one slot per item with its total.
-- Built on first open, and only refreshed while it's showing.
local _, ns = ...
if ns.disabled then return end -- another copy of Alts Forever is running (Core.lua)
local L = ns.L

local floor, ceil, max, ipairs, pairs, sort, time = math.floor, math.ceil, math.max, ipairs, pairs, table.sort, time
local C_Item = C_Item
local GetItemIconByID = C_Item.GetItemIconByID

local GREY = "|cff9d9d9d"
local COLS, SIZE, GAP, PAD = 14, 36, 3, 12
local TOP, TAB_ROW, BOTTOM = 62, 26, 34
local EMPTY_SLOT = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"
local BORDER = "Interface\\Common\\WhiteIconFrame"
local MAX_TABS = 9

local frame
local slots, tabButtons = {}, {}
local shownKey, view, tab = nil, "bags", 1
-- What's shown, reused between fills: item IDs (false for an empty slot) and counts.
local ids, counts, bankTabs = {}, {}, {}
local shown = 0
local loadRetry = false

---------------------------------------------------------------------------
-- What to show (no UI, so tests can check it)
---------------------------------------------------------------------------
local function Add(id, count)
    shown = shown + 1
    ids[shown], counts[shown] = id or false, count or 0
end

local function AddLayout(values)
    for i = 1, #values do
        local id, count = ns.SlotItem(values[i])
        Add(id, count)
    end
end

-- One slot per item, with its total: for bags or a bank seen before slots were recorded.
local byId = {}
local function AddCounts(totals)
    local n = 0
    for id in pairs(totals) do
        n = n + 1
        byId[n] = id
    end
    for i = #byId, n + 1, -1 do byId[i] = nil end
    sort(byId)
    for i = 1, n do Add(byId[i], totals[byId[i]]) end
end

-- Fills ids/counts for a character's view; returns how it was recorded: "slots",
-- "counts" (no layout yet) or nil (nothing recorded), and for the bank, its tabs.
function ns.BagsContents(c, which, tabIndex)
    shown = 0
    local layout = c.layout
    local how
    if which == "bank" then
        local n = 0
        for _, bag in ipairs(ns.BANK_TABS) do
            if layout and layout[bag] then
                n = n + 1
                bankTabs[n] = bag
            end
        end
        for i = #bankTabs, n + 1, -1 do bankTabs[i] = nil end
        if n > 0 then
            AddLayout(layout[bankTabs[math.min(tabIndex or 1, n)]])
            how = "slots"
        elseif c.bank then
            AddCounts(c.bank)
            how = "counts"
        end
    else
        for i = #bankTabs, 1, -1 do bankTabs[i] = nil end
        for _, bag in ipairs(ns.CARRIED_BAGS) do
            if layout and layout[bag] then
                AddLayout(layout[bag])
                how = "slots"
            end
        end
        if not how and c.bags and next(c.bags) then
            AddCounts(c.bags)
            how = "counts"
        end
    end
    for i = #ids, shown + 1, -1 do ids[i], counts[i] = nil, nil end
    return how, bankTabs
end

function ns.BagsShown() return ids, counts, shown end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local Fill

local function SlotEnter(b)
    if not b.id then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(b.id)
    GameTooltip:Show()
end

local function SlotClick(b)
    -- Shift-click links the item in chat, like the game's own bags.
    if not (b.id and IsModifiedClick()) then return end
    local _, link = C_Item.GetItemInfo(b.id)
    if link then HandleModifiedItemClick(link) end
end

local function Slot(i)
    local b = slots[i]
    if b then return b end
    b = CreateFrame("Button", nil, frame)
    b:SetSize(SIZE, SIZE)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetAllPoints()
    b.border:SetTexture(BORDER)
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)
    b:SetScript("OnEnter", SlotEnter)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", SlotClick)
    ns.SkinSlot(b)
    slots[i] = b
    return b
end

-- Item quality isn't known until the game has loaded the item: ask for it, and fill
-- again once a second later (once per fill, however many items were missing).
local function Quality(id)
    local q = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
    if q == nil and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(id)
        if not loadRetry and C_Timer then
            loadRetry = true
            C_Timer.After(1, function()
                if frame:IsShown() then Fill() end
            end)
        end
    end
    return q
end

local function ShowSlot(b, id, count)
    b.id = id or nil
    if not id then
        b.icon:SetTexture(EMPTY_SLOT)
        b.count:SetText("")
        b.border:Hide()
        return
    end
    b.icon:SetTexture(GetItemIconByID(id) or 134400)
    b.count:SetText(count > 1 and count or "")
    local q = Quality(id)
    local color = q and q >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if color then
        b.border:SetVertexColor(color.r, color.g, color.b)
        b.border:Show()
    else
        b.border:Hide()
    end
end

local function Seen(c, now)
    if view == "bank" then
        return c.bankAt and L["Bank last visited: %s"]:format(ns.FormatAgo(now - c.bankAt)) or ""
    end
    return L["Last seen: %s"]:format(ns.SeenText(shownKey, c, now))
end

function Fill()
    local c = shownKey and ns.db.chars[shownKey]
    if not c then return frame:Hide() end
    loadRetry = false
    local how, tabs = ns.BagsContents(c, view, tab)
    if #tabs > 0 and tab > #tabs then tab = #tabs end
    frame.who:SetText(ns.ColoredName(shownKey, c))
    for _, v in ipairs({ "bags", "bank" }) do
        if v == view then frame[v]:LockHighlight() else frame[v]:UnlockHighlight() end
    end
    -- Bank tab buttons, only with more than one tab.
    local tabRow = #tabs > 1 and TAB_ROW or 0
    for i = 1, MAX_TABS do
        local t = tabButtons[i]
        if i <= #tabs and #tabs > 1 then
            t:Show()
            if i == tab then t:LockHighlight() else t:UnlockHighlight() end
        elseif t then
            t:Hide()
        end
    end
    local top = TOP + tabRow
    local free = 0
    for i = 1, shown do
        local b = Slot(i)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + (i - 1) % COLS * (SIZE + GAP), -top - floor((i - 1) / COLS) * (SIZE + GAP))
        ShowSlot(b, ids[i], counts[i])
        if not ids[i] then free = free + 1 end
        b:Show()
    end
    for i = shown + 1, #slots do slots[i]:Hide() end
    local rows = max(ceil(shown / COLS), 3)
    frame:SetHeight(top + rows * (SIZE + GAP) - GAP + BOTTOM)

    if not how then
        frame.empty:SetText(GREY .. (view == "bank" and L["Bank not seen yet.\nVisit the bank on this character once."]
            or L["No bags recorded yet.\nLog in on this character once."]) .. "|r")
    end
    frame.empty:SetShown(not how)
    if how == "counts" then
        frame.info:SetText(GREY .. (view == "bank" and L["Totals only: visit the bank on this character to see its slots."]
            or L["Totals only: log in on this character to see its slots."]) .. "|r")
    elseif how == "slots" then
        frame.info:SetText(L["%d of %d slots free"]:format(free, shown))
    else
        frame.info:SetText("")
    end
    frame.seen:SetText(how and (GREY .. Seen(c, time()) .. "|r") or "")
end

local function PickCharacter(owner)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        for _, key in ipairs(ns.OverviewOrder()) do
            root:CreateRadio(ns.ColoredName(key, ns.db.chars[key]),
                function(k) return k == shownKey end,
                function(k)
                    shownKey, tab = k, 1
                    Fill()
                end, key)
        end
    end)
end

local function ViewButton(name, text, x)
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(80, 22)
    b:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -30)
    b:SetText(text)
    b:SetScript("OnClick", function()
        view, tab = name, 1
        Fill()
    end)
    ns.SkinButton(b)
    frame[name] = b
end

local function CreateWindow()
    local ok, f = pcall(CreateFrame, "Frame", "AltsForeverBagsFrame", UIParent, "BasicFrameTemplateWithInset")
    if not ok then f = CreateFrame("Frame", "AltsForeverBagsFrame", UIParent, "BackdropTemplate") end
    frame = f
    f.slots, f.tabs = slots, tabButtons
    f:SetWidth(PAD * 2 + COLS * (SIZE + GAP) - GAP)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    local title = f.TitleText or f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if not f.TitleText then title:SetPoint("TOP", 0, -6) end
    title:SetText(L["Bags and bank"])

    -- The character dropdown.
    local who = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    who:SetSize(200, 22)
    who:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -30)
    who:SetScript("OnClick", PickCharacter)
    who:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Choose a character"])
        GameTooltip:Show()
    end)
    who:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ns.SkinButton(who)
    f.who = who
    ViewButton("bags", L["Bags"], PAD + 210)
    ViewButton("bank", L["Bank"], PAD + 294)

    for i = 1, MAX_TABS do
        local t = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        t:SetSize(56, 20)
        t:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + (i - 1) * 60, -TOP + 2)
        t:SetText(L["Tab %d"]:format(i))
        t:SetScript("OnClick", function()
            tab = i
            Fill()
        end)
        ns.SkinButton(t)
        t:Hide()
        tabButtons[i] = t
    end

    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.empty:SetPoint("CENTER", 0, -10)
    f.info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.info:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD + 2, 12)
    f.seen = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.seen:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD - 2, 12)
    for _, fs in ipairs({ f.empty, f.info, f.seen }) do ns.SkinText(fs) end

    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "AltsForeverBagsFrame" end
    ns.SkinWindow(f)
    f:Hide()
    f:SetPoint("CENTER")
end

-- Opens the window on a character's bags or bank; the same again closes it.
function ns.ShowBags(key, which)
    if not frame then CreateWindow() end
    key, which = key or ns.charKey, which or "bags"
    if frame:IsShown() and shownKey == key and view == which then return frame:Hide() end
    if shownKey ~= key or view ~= which then tab = 1 end
    shownKey, view = key, which
    Fill()
    frame:Show()
end

function ns.BagsWindow() return frame end

-- The scanner calls this after each bags or bank scan.
function ns.BagsWindowChanged()
    if frame and frame:IsShown() and shownKey == ns.charKey then Fill() end
end
