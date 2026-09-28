-- Alts Forever bags window: any character's bags or bank, slot by slot, as last seen,
-- either all in one grid or split by bag (bank: by tab), with their money at the bottom.
-- Opened from the overview's title bar, a character's right-click menu, /af bags and
-- /af bank. The slots come from the scanner (char.layout); for characters not scanned
-- since this was added, the window falls back to one slot per item with its total.
-- Built on first open, and only refreshed while it's showing.
local _, ns = ...
if ns.disabled then return end -- another copy of Alts Forever is running (Core.lua)
local L = ns.L

local floor, ceil, max, min, ipairs, pairs, sort, time = math.floor, math.ceil, math.max, math.min, ipairs, pairs, table.sort, time
local C_Item = C_Item
local GetItemIconByID = C_Item.GetItemIconByID
local GetCoinTextureString = C_CurrencyInfo.GetCoinTextureString

local GREY = "|cff9d9d9d"
local COLS, SIZE, GAP, PAD = 14, 36, 3, 12
local TOP, BOTTOM, HEADER, SECTION_GAP = 60, 34, 20, 8
local EMPTY_SLOT = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"
local BORDER = "Interface\\Common\\WhiteIconFrame"
local BagIndex = Enum.BagIndex

local frame
local slots, headers = {}, {}
local shownKey, view = nil, "bags"
local scroll, contentHeight = 0, 0
local loadRetry = false

---------------------------------------------------------------------------
-- What to show (no UI, so tests can check it)
---------------------------------------------------------------------------
-- The slots, reused between fills: item IDs (false for an empty slot) and counts, and
-- the sections they're grouped in: { bag = bag index or false, from, to, used }.
local ids, counts, sections = {}, {}, {}
local shown, nSections = 0, 0

local function NewSection(bag)
    nSections = nSections + 1
    local s = sections[nSections] or {}
    sections[nSections] = s
    s.bag, s.from, s.to, s.used = bag, shown + 1, shown, 0
    return s
end

local function Add(section, id, count)
    shown = shown + 1
    ids[shown], counts[shown] = id or false, count or 0
    section.to = shown
    if id then section.used = section.used + 1 end
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
    local section = NewSection(false)
    for i = 1, n do Add(section, byId[i], totals[byId[i]]) end
end

-- Fills the slots for a character's bags or bank, one section per bag if split, else one
-- for all; returns how it was recorded: "slots", "counts" (no layout yet) or nil.
function ns.BagsContents(c, which, split)
    shown, nSections = 0, 0
    local layout = c.layout
    local how
    local section
    for _, bag in ipairs(which == "bank" and ns.BANK_TABS or ns.CARRIED_BAGS) do
        local values = layout and layout[bag]
        if values then
            if split or not section then section = NewSection(split and bag or false) end
            for i = 1, #values do
                local id, count = ns.SlotItem(values[i])
                Add(section, id, count)
            end
            how = "slots"
        end
    end
    if not how then
        local totals = which == "bank" and c.bank or c.bags
        if totals and next(totals) then
            AddCounts(totals)
            how = "counts"
        end
    end
    for i = #ids, shown + 1, -1 do ids[i], counts[i] = nil, nil end
    return how
end

function ns.BagsShown() return ids, counts, shown, sections, nSections end

-- A section's title: the bag's name (or bank tab), or the whole place's.
local function SectionName(c, bag)
    if not bag then return view == "bank" and L["Bank"] or L["Bags"] end
    if bag == BagIndex.Backpack then return BACKPACK_TOOLTIP or L["Backpack"] end
    if bag == BagIndex.Keyring then return KEYRING or L["Keyring"] end
    for i, tab in ipairs(ns.BANK_TABS) do
        if tab == bag then return L["Tab %d"]:format(i) end
    end
    local item = c.layout[bag][0]
    local name = item and C_Item.GetItemNameByID(item)
    if not name and item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(item) end
    return name or L["Bag %d"]:format(bag)
end
ns.BagsSectionName = SectionName

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
    b = CreateFrame("Button", nil, frame.content)
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

-- A section heading with a faint line after it, as in EllesmereUI's bags.
local function Header(i)
    local h = headers[i]
    if h then return h end
    h = frame.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ns.SkinText(h)
    h.line = frame.content:CreateTexture(nil, "ARTWORK")
    h.line:SetHeight(1)
    h.line:SetColorTexture(1, 1, 1, 0.12)
    h.line:SetPoint("LEFT", h, "RIGHT", 8, 0)
    h.line:SetPoint("RIGHT", frame.content, "RIGHT", 0, 0)
    headers[i] = h
    return h
end

-- Item quality and names aren't known until the game has loaded the item: ask for it,
-- and fill again a second later (once per fill, however many items were missing).
local function RetryLater()
    if loadRetry or not C_Timer then return end
    loadRetry = true
    C_Timer.After(1, function()
        if frame:IsShown() then Fill() end
    end)
end

local function Quality(id)
    local q = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
    if q == nil and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(id)
        RetryLater()
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

-- The tallest the slot area gets before it scrolls.
local function MaxView()
    local h = UIParent and UIParent:GetHeight() or 0
    return max(h > 0 and floor(h * 0.7) - TOP - BOTTOM or 560, 4 * (SIZE + GAP))
end

local function Place()
    local visible = min(contentHeight, MaxView())
    scroll = max(0, min(scroll, contentHeight - visible))
    frame.content:ClearAllPoints()
    frame.content:SetPoint("TOPLEFT", frame.holder, "TOPLEFT", 0, scroll)
    frame.content:SetPoint("TOPRIGHT", frame.holder, "TOPRIGHT", 0, scroll)
    frame.content:SetHeight(max(contentHeight, 1))
    frame.holder:SetHeight(max(visible, 3 * (SIZE + GAP)))
    frame:SetHeight(TOP + frame.holder:GetHeight() + BOTTOM)
end

function Fill()
    local c = shownKey and ns.db.chars[shownKey]
    if not c then return frame:Hide() end
    loadRetry = false
    local split = ns.db.bagsSplit and true or false
    local how = ns.BagsContents(c, view, split)
    frame.who:SetText(ns.ColoredName(shownKey, c))
    for _, v in ipairs({ "bags", "bank" }) do
        if v == view then frame[v]:LockHighlight() else frame[v]:UnlockHighlight() end
    end
    frame.split:SetChecked(split)

    local y, free = 0, 0
    for n = 1, nSections do
        local s = sections[n]
        local h = Header(n)
        local title = SectionName(c, s.bag)
        if how == "slots" then
            h:SetText(title .. GREY .. "  (" .. s.used .. " / " .. (s.to - s.from + 1) .. ")|r")
        else
            -- Totals only: say so beside the heading (too long for the bottom row).
            h:SetText(title .. GREY .. "   " .. (view == "bank" and L["Totals only: visit the bank on this character to see its slots."]
                or L["Totals only: log in on this character to see its slots."]) .. "|r")
        end
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -y)
        h:Show()
        h.line:SetShown(how == "slots")
        y = y + HEADER
        for i = s.from, s.to do
            local k = i - s.from
            local b = Slot(i)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", frame.content, "TOPLEFT", k % COLS * (SIZE + GAP), -y - floor(k / COLS) * (SIZE + GAP))
            ShowSlot(b, ids[i], counts[i])
            if not ids[i] then free = free + 1 end
            b:Show()
        end
        y = y + ceil((s.to - s.from + 1) / COLS) * (SIZE + GAP) + SECTION_GAP
    end
    for n = nSections + 1, #headers do
        headers[n]:Hide()
        headers[n].line:Hide()
    end
    for i = shown + 1, #slots do slots[i]:Hide() end
    contentHeight = y
    Place()

    if not how then
        frame.empty:SetText(GREY .. (view == "bank" and L["Bank not seen yet.\nVisit the bank on this character once."]
            or L["No bags recorded yet.\nLog in on this character once."]) .. "|r")
    end
    frame.empty:SetShown(not how)
    if how == "slots" then
        frame.info:SetText(L["%d of %d slots free"]:format(free, shown))
    else
        frame.info:SetText("")
    end
    frame.seen:SetText(how and (GREY .. Seen(c, time()) .. "|r") or "")
    frame.money:SetText(c.money and GetCoinTextureString(c.money) or "")
end

local function PickCharacter(owner)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        for _, key in ipairs(ns.OverviewOrder()) do
            root:CreateRadio(ns.ColoredName(key, ns.db.chars[key]),
                function(k) return k == shownKey end,
                function(k)
                    shownKey, scroll = k, 0
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
        view, scroll = name, 0
        Fill()
    end)
    ns.SkinButton(b)
    frame[name] = b
end

local function CreateWindow()
    local ok, f = pcall(CreateFrame, "Frame", "AltsForeverBagsFrame", UIParent, "BasicFrameTemplateWithInset")
    if not ok then f = CreateFrame("Frame", "AltsForeverBagsFrame", UIParent, "BackdropTemplate") end
    frame = f
    f.slots, f.headers = slots, headers
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

    -- All in one grid, or a section per bag (the choice is kept for every character).
    local split = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    split:SetSize(24, 24)
    split:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 384, -29)
    split.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    split.label:SetPoint("LEFT", split, "RIGHT", 2, 0)
    split.label:SetText(L["By bag"])
    split:SetScript("OnClick", function(self)
        ns.db.bagsSplit = self:GetChecked() and true or nil
        scroll = 0
        Fill()
    end)
    split:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["By bag"])
        GameTooltip:AddLine(L["Show each bag (or bank tab) separately, or everything in one grid."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    split:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ns.SkinCheck(split)
    ns.SkinText(split.label)
    f.split = split

    -- The slots scroll inside a clipped holder when they're taller than the screen allows.
    local holder = CreateFrame("Frame", nil, f)
    holder:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -TOP)
    holder:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -TOP)
    holder:SetClipsChildren(true)
    f.holder = holder
    f.content = CreateFrame("Frame", nil, holder)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        scroll = scroll - delta * 2 * (SIZE + GAP)
        Place()
    end)

    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.empty:SetPoint("CENTER", holder, "CENTER")
    f.info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.info:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD + 2, 12)
    f.seen = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.money = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.money:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD - 2, 11)
    f.seen:SetPoint("RIGHT", f.money, "LEFT", -20, 0)
    for _, fs in ipairs({ f.empty, f.info, f.seen, f.money }) do ns.SkinText(fs) end

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
    if shownKey ~= key or view ~= which then scroll = 0 end
    shownKey, view = key, which
    Fill()
    frame:Show()
end

function ns.BagsWindow() return frame end

-- The scanner calls this after each bags or bank scan; money changes too.
function ns.BagsWindowChanged()
    if frame and frame:IsShown() and shownKey == ns.charKey then Fill() end
end


---------------------------------------------------------------------------
-- Shortcuts from the player's own bags and bank to this window, inside each UI:
-- Blizzard's bags get an entry in their portrait menu; Blizzard's bank, ElvUI's and
-- EllesmereUI's windows get a small button in their header, next to their own
-- buttons. Each is added the first time its window is found; the checks stop once
-- all are.
---------------------------------------------------------------------------
local ICON = "Interface\\AddOns\\" .. (...) .. "\\media\\icon.tga"

-- Opens this window on your own bags or bank (left open if it already shows them).
local function OpenFromShortcut(which)
    if not (frame and frame:IsShown() and view == which) then ns.ShowBags(ns.charKey, which) end
end

local function ShortcutEnter(b)
    GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Alts Forever")
    GameTooltip:AddLine(b.which == "bank" and L["Every character's bank"] or L["Every character's bags"], 1, 1, 1)
    GameTooltip:Show()
end

local function Shortcut(parent, which, size)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexture(ICON)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)
    b.which = which
    b:SetScript("OnClick", function(self) OpenFromShortcut(self.which) end)
    b:SetScript("OnEnter", ShortcutEnter)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- Where each window gets its button. Each returns the button, or nil if the window
-- (or the part it's placed beside) isn't there yet. EllesmereUI's fields are not its
-- official API: they're checked before use.
local PLACES = {
    -- Blizzard's bank: in the title area, left of the search box.
    BankFrame = function()
        local search = _G.BankItemSearchBox
        if not (_G.BankFrame and search) then return end
        local b = Shortcut(_G.BankFrame, "bank", 22)
        b:SetPoint("RIGHT", search, "LEFT", -10, 0)
        return b
    end,
    -- ElvUI: its header buttons are all on the right; the top-left corner is free.
    ElvUI_ContainerFrame = function()
        local f = _G.ElvUI_ContainerFrame
        if not f then return end
        local b = Shortcut(f, "bags", 20)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -6)
        ns.SkinSlot(b)
        return b
    end,
    ElvUI_BankContainerFrame = function()
        local f = _G.ElvUI_BankContainerFrame
        if not f then return end
        local b = Shortcut(f, "bank", 20)
        b:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -6)
        ns.SkinSlot(b)
        return b
    end,
    -- EllesmereUI's bags: left of its bags button (which is left of sort and search).
    EUI_MainBagFrame = function()
        local f = _G.EUI_MainBagFrame
        local anchor = f and f._bagsBtn
        if not (anchor and anchor.GetParent) then return end
        local b = Shortcut(anchor:GetParent(), "bags", 24)
        b:SetPoint("RIGHT", anchor, "LEFT", -6, 0)
        return b
    end,
    -- EllesmereUI's bank: left of its sort button, which sits 13 px left of the search box.
    EUI_BankFrame = function()
        local f = _G.EUI_BankFrame
        local search = f and f._searchBox
        if not (search and search.GetParent) then return end
        local b = Shortcut(search:GetParent(), "bank", 24)
        b:SetPoint("RIGHT", search, "LEFT", -13 - 24 - 6, 0)
        return b
    end,
}
local shortcuts, missing = {}, 0
for _ in pairs(PLACES) do missing = missing + 1 end

local function AttachShortcuts()
    if missing == 0 then return end
    for name, place in pairs(PLACES) do
        if not shortcuts[name] then
            local b = place()
            if b then
                shortcuts[name] = b
                missing = missing - 1
            end
        end
    end
end

function ns.BagShortcuts() return shortcuts end

-- Blizzard's bags: an entry at the bottom of the portrait button's menu (combined and
-- separate bags; tags checked in game 2026-09-28).
local function AddMenuEntry(_, root)
    root:CreateDivider()
    root:CreateButton(L["Alts Forever: every character's bags"], function() OpenFromShortcut("bags") end)
end

function ns.StartBags()
    if Menu and Menu.ModifyMenu then
        Menu.ModifyMenu("MENU_CONTAINER_FRAME_COMBINED", AddMenuEntry)
        Menu.ModifyMenu("MENU_CONTAINER_FRAME", AddMenuEntry)
    end
    ns.On("PLAYER_ENTERING_WORLD", AttachShortcuts)
    -- The bank windows may be made on the first visit.
    ns.On("BANKFRAME_OPENED", function()
        AttachShortcuts()
        if C_Timer then C_Timer.After(0, AttachShortcuts) end
    end)
    for _, name in ipairs({ "ToggleAllBags", "OpenAllBags", "ToggleBackpack", "OpenBackpack" }) do
        if _G[name] then hooksecurefunc(name, AttachShortcuts) end
    end
end
