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
local issecretvalue = issecretvalue or function() return false end
local SIZE, GAP, PAD = 36, 3, 12
-- Columns: set by the window's width (resize grip), remembered in db.bagsCols.
local DEFAULT_COLS, MIN_COLS, MAX_COLS = 14, 10, 30
local cols = DEFAULT_COLS
local TOP, BOTTOM, HEADER, SECTION_GAP = 60, 34, 20, 8
local EMPTY_SLOT = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"
local BORDER = "Interface\\Common\\WhiteIconFrame"
local BagIndex = Enum.BagIndex

local frame
local slots, headers = {}, {}
local shownKey, view = nil, "bags"
local sizing = false
local scroll, contentHeight = 0, 0
-- An item the search (Search.lua) opened this window for: its slots lit, the rest dimmed,
-- on every character and view you switch to, until you clear it or close the window.
local lit
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
local Fill, Place

local function SlotEnter(b)
    -- With the Gamepad UI, focus moving onto a slot scrolls it into view (with its
    -- section's heading when scrolling up): the D-pad has no mouse wheel.
    if ns.GamepadUI() and b.top then
        local visible = frame.holder:GetHeight()
        if b.top < scroll then
            scroll = max(0, b.top - HEADER)
            Place()
        elseif b.top + SIZE > scroll + visible then
            scroll = b.top + SIZE - visible
            Place()
        end
    end
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
    local dim = lit and id ~= lit and 0.25 or 1
    b.icon:SetAlpha(dim)
    b.border:SetAlpha(dim)
    b.count:SetAlpha(dim)
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

-- Where the lit item is: each character's bags and bank holding it, the character with most
-- first. What the arrows beside "Showing: ..." step through.
local stops = {}

local function ByMost(a, b)
    if a.n ~= b.n then return a.n > b.n end
    return a.key < b.key
end

local function Stops()
    wipe(stops)
    if not lit then return stops end
    local list = {}
    for key, c in pairs(ns.db.chars) do
        if not ns.Hidden(c) then
            local inBags, inBank = c.bags and c.bags[lit] or 0, c.bank and c.bank[lit] or 0
            if inBags + inBank > 0 then list[#list + 1] = { key = key, n = inBags + inBank, bags = inBags, bank = inBank } end
        end
    end
    sort(list, ByMost)
    for _, h in ipairs(list) do
        if h.bags > 0 then stops[#stops + 1] = { key = h.key, view = "bags" } end
        if h.bank > 0 then stops[#stops + 1] = { key = h.key, view = "bank" } end
    end
    return stops
end

-- Which stop is showing (0 if this character or view hasn't got it).
local function StopIndex()
    for i, s in ipairs(stops) do
        if s.key == shownKey and s.view == view then return i end
    end
    return 0
end

local function ScrollToLit()
    for i = 1, shown do
        if ids[i] == lit and slots[i] and slots[i].top then
            scroll = max(0, slots[i].top - HEADER)
            Place()
            return
        end
    end
end

-- The next (1) or previous (-1) character's bags or bank with the lit item.
local function Step(dir)
    Stops()
    local n = #stops
    if n == 0 then return end
    local i = StopIndex()
    if i == 0 then i = dir > 0 and 1 or n else i = (i - 1 + dir) % n + 1 end
    shownKey, view, scroll = stops[i].key, stops[i].view, 0
    Fill()
    ScrollToLit()
end
ns.BagsStep = Step

local function Seen(c, now)
    if view == "bank" then
        return c.bankAt and L["Bank last visited: %s"]:format(ns.FormatAgo(now - c.bankAt)) or ""
    end
    return L["Last seen: %s"]:format(ns.SeenText(shownKey, c, now))
end

local MIN_VIEW = 3 * (SIZE + GAP)
local function WidthFor(n) return PAD * 2 + n * (SIZE + GAP) - GAP end
local function ColsFor(width)
    return max(MIN_COLS, min(MAX_COLS, floor((width - PAD * 2 + GAP) / (SIZE + GAP) + 0.5)))
end

-- The tallest the slot area gets before it scrolls: as the player sized it, or by
-- default 70% of the screen (in the window's own units: it may be scaled, Options.lua).
local function MaxView()
    if ns.db.bagsHeight then return max(ns.db.bagsHeight, MIN_VIEW) end
    local h = UIParent and UIParent:GetHeight() / ns.WindowScale() or 0
    return max(h > 0 and floor(h * 0.7) - TOP - BOTTOM or 560, MIN_VIEW)
end

Place = function()
    -- While the player drags the grip, the window keeps the height they're dragging to.
    local visible = sizing and max(frame:GetHeight() - TOP - BOTTOM, MIN_VIEW) or max(min(contentHeight, MaxView()), MIN_VIEW)
    scroll = max(0, min(scroll, contentHeight - visible))
    frame.content:ClearAllPoints()
    frame.content:SetPoint("TOPLEFT", frame.holder, "TOPLEFT", 0, scroll)
    frame.content:SetPoint("TOPRIGHT", frame.holder, "TOPRIGHT", 0, scroll)
    frame.content:SetHeight(max(contentHeight, 1))
    frame.holder:SetHeight(visible)
    if not sizing then frame:SetHeight(TOP + visible + BOTTOM) end
end

function Fill()
    local c = shownKey and ns.db.chars[shownKey]
    if not c then return frame:Hide() end
    loadRetry = false
    if not sizing then
        cols = ns.db.bagsCols or DEFAULT_COLS
        frame:SetWidth(WidthFor(cols))
    end
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
            b.top = y + floor(k / cols) * (SIZE + GAP)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", frame.content, "TOPLEFT", k % cols * (SIZE + GAP), -y - floor(k / cols) * (SIZE + GAP))
            ShowSlot(b, ids[i], counts[i])
            if not ids[i] then free = free + 1 end
            b:Show()
        end
        y = y + ceil((s.to - s.from + 1) / cols) * (SIZE + GAP) + SECTION_GAP
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
    local name = lit and C_Item.GetItemNameByID(lit)
    if lit then
        if type(name) ~= "string" or issecretvalue(name) then name = "?" end
        frame.clear.text:SetText(L["Showing: %s"]:format(name))
        local w = frame.clear.text:GetStringWidth()
        if type(w) == "number" and not issecretvalue(w) then frame.clear:SetWidth(w + 20) end
    end
    frame.clear:SetShown(lit ~= nil)
    frame.info:SetShown(not lit)
    local n = #Stops()
    local i = StopIndex()
    frame.stop:SetText(lit and (i > 0 and L["%d of %d"]:format(i, n) or L["not here"]) or "")
    -- Arrows when there's somewhere else to go.
    local arrows = lit ~= nil and (n > 1 or (n == 1 and i == 0))
    frame.prev:SetShown(arrows)
    frame.next:SetShown(arrows)
    frame.stop:SetShown(lit ~= nil)
    frame.seen:SetText(how and (GREY .. Seen(c, time()) .. "|r") or "")
    frame.money:SetText(c.money and GetCoinTextureString(c.money) or "")
end

-- Every character, in the overview's order and, as there, headed by ruleset and faction
-- when you have more than one group.
local function PickCharacter(owner)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        local chars, keys = ns.db.chars, ns.OverviewOrder()
        local byRealm, byFaction = ns.GroupParts()
        local group
        for _, key in ipairs(keys) do
            local c = chars[key]
            if ns.overviewSplit and ns.GroupKey(c, byRealm, byFaction) ~= group then
                if group then root:CreateDivider() end
                group = ns.GroupKey(c, byRealm, byFaction)
                root:CreateTitle(ns.GroupLabel(c, byRealm, byFaction))
            end
            -- With an item lit: how many each character has of it (bags and bank).
            local n = lit and ((c.bags and c.bags[lit] or 0) + (c.bank and c.bank[lit] or 0)) or 0
            root:CreateRadio(ns.ColoredName(key, c) .. (n > 0 and " |cffffffff(" .. n .. ")|r" or ""),
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
    b:SetSize(70, 22)
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
    f:SetWidth(WidthFor(cols))
    f:SetFrameStrata("HIGH")
    -- Comes to the front when clicked or opened, so our windows never draw through each other.
    f:SetToplevel(true)
    f:HookScript("OnShow", f.Raise)
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
    who:SetSize(160, 22)
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
    ViewButton("bags", L["Bags"], PAD + 166)
    ViewButton("bank", L["Bank"], PAD + 240)

    -- All in one grid, or a section per bag (the choice is kept for every character).
    local split = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    split:SetSize(24, 24)
    split:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 316, -29)
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
    f.money:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD - 14, 11)
    f.seen:SetPoint("RIGHT", f.money, "LEFT", -20, 0)
    for _, fs in ipairs({ f.empty, f.info, f.seen, f.money }) do ns.SkinText(fs) end

    -- While the search has lit an item up: which one, in place of the free slots, and a
    -- click back to every slot (owner, 2026-10-16: there was no way to clear it).
    local clear = CreateFrame("Button", nil, f)
    clear:SetSize(200, 16)
    clear:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD + 2, 10)
    clear.text = clear:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    clear.text:SetPoint("LEFT")
    clear.x = clear:CreateTexture(nil, "ARTWORK")
    clear.x:SetSize(14, 14)
    clear.x:SetPoint("LEFT", clear.text, "RIGHT", 4, 0)
    clear.x:SetTexture("Interface\\Buttons\\UI-StopButton")
    clear:SetScript("OnClick", function()
        lit = nil
        Fill()
    end)
    clear:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Click to show every slot again."])
        GameTooltip:Show()
    end)
    clear:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ns.SkinText(clear.text)
    clear:Hide()
    f.clear = clear
    -- Previous and next character with it, and where this one is in the list.
    local function Arrow(dir, art, tip)
        local b = CreateFrame("Button", nil, f)
        b:SetSize(20, 20)
        b:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. art .. "-Up")
        b:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. art .. "-Down")
        b:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. art .. "-Disabled")
        b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        b:SetScript("OnClick", function() Step(dir) end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(tip)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:Hide()
        return b
    end
    f.prev = Arrow(-1, "PrevPage", L["Previous character with it"])
    f.prev:SetPoint("LEFT", clear, "RIGHT", 4, 0)
    f.stop = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.stop:SetPoint("LEFT", f.prev, "RIGHT", 2, 0)
    ns.SkinText(f.stop)
    f.next = Arrow(1, "NextPage", L["Next character with it"])
    f.next:SetPoint("LEFT", f.stop, "RIGHT", 2, 0)

    -- Search button in the title bar, left of the close button (as the overview's).
    local search = CreateFrame("Button", nil, f)
    search:SetSize(16, 16)
    search:SetPoint("TOPRIGHT", f, "TOPRIGHT", -28, -4)
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

    -- Resize grip: width sets the columns (snapped to whole slots when let go), height
    -- how tall the window gets before it scrolls. Both are remembered.
    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(WidthFor(MIN_COLS), TOP + MIN_VIEW + BOTTOM, WidthFor(MAX_COLS), 2000)
    end
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -3, 3)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function()
        sizing = true
        f:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        sizing = false
        cols = ColsFor(f:GetWidth())
        ns.db.bagsCols = cols ~= DEFAULT_COLS and cols or nil
        ns.db.bagsHeight = max(floor(f:GetHeight() - TOP - BOTTOM), MIN_VIEW)
        Fill()
    end)
    ns.GamepadIgnore(grip) -- mouse only
    f.grip = grip
    -- While dragging, the grid reflows as soon as another column fits.
    f:SetScript("OnSizeChanged", function(self, width)
        if not sizing then return end
        local n = ColsFor(width)
        if n ~= cols then
            cols = n
            Fill()
        else
            Place()
        end
    end)

    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "AltsForeverBagsFrame" end
    ns.SkinWindow(f)
    f:Hide()
    f:SetPoint("CENTER")
    -- The game's own bag sounds, however the window is opened or closed (Esc too); hooked
    -- after the Hide above, so creating the window makes no sound.
    local sounds = SOUNDKIT or {}
    f:HookScript("OnShow", function() if sounds.IG_BACKPACK_OPEN then PlaySound(sounds.IG_BACKPACK_OPEN) end end)
    f:HookScript("OnHide", function()
        lit = nil
        if sounds.IG_BACKPACK_CLOSE then PlaySound(sounds.IG_BACKPACK_CLOSE) end
    end)
    ns.GamepadWindow(f)
    ns.ScaleWindow(f)
end

-- Opens the window on a character's bags or bank; the same again closes it.
-- Opens a character's bags or bank; the same again closes it. With `highlight` (an item ID,
-- from the search) it stays open, lights that item up and scrolls to it.
function ns.ShowBags(key, which, highlight)
    if not frame then CreateWindow() end
    key, which = key or ns.charKey, which or "bags"
    if not highlight and frame:IsShown() and shownKey == key and view == which then return frame:Hide() end
    if shownKey ~= key or view ~= which then scroll = 0 end
    shownKey, view, lit = key, which, highlight
    Fill()
    if highlight then ScrollToLit() end
    frame:Show()
end

function ns.BagsHighlight() return lit end

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
local MEDIA = "Interface\\AddOns\\" .. (...) .. "\\media\\"
local ICON = MEDIA .. "icon.tga"
-- The logo with its gold ring, like EllesmereUI's own round header buttons.
local RINGED = MEDIA .. "logo.tga"

-- Opens this window on your own bags or bank (left open if it already shows them).
local function OpenFromShortcut(which)
    if not (frame and frame:IsShown() and view == which) then ns.ShowBags(ns.charKey, which) end
end

local function ShortcutEnter(b)
    if b.rest then b.icon:SetAlpha(1) end
    GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Alts Forever")
    GameTooltip:AddLine(b.which == "bank" and L["Every character's bank"] or L["Every character's bags"], 1, 1, 1)
    GameTooltip:Show()
end

-- round: EllesmereUI's style, the ringed logo slightly dimmed, brightening on hover
-- (no square highlight on a round button).
local function Shortcut(parent, which, size, round)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexture(round and RINGED or ICON)
    if round then
        b.rest = 0.9
        b.icon:SetAlpha(b.rest)
    else
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.15)
    end
    b.which = which
    b:SetScript("OnClick", function(self) OpenFromShortcut(self.which) end)
    b:SetScript("OnEnter", ShortcutEnter)
    b:SetScript("OnLeave", function(self)
        if self.rest then self.icon:SetAlpha(self.rest) end
        GameTooltip:Hide()
    end)
    return b
end

-- The left end of a header's row of buttons: from `start` (the search box), each next
-- button is the shown one anchored by its RIGHT to the previous one's LEFT (EllesmereUI:
-- sort, then Show Bags, then anything another addon chained on). Following the anchors
-- rather than fixed offsets keeps working when EllesmereUI adds, hides or moves a button
-- (its bank's Show Bags button, not stored anywhere, was covered on 2026-09-29).
local function RowEnd(start)
    local parent, current = start:GetParent(), start
    for _ = 1, 20 do
        local found
        for _, child in ipairs({ parent:GetChildren() }) do
            if child ~= current and child:IsShown() and child.GetPoint then
                for i = 1, (child.GetNumPoints and child:GetNumPoints() or 1) do
                    local point, rel, relPoint = child:GetPoint(i)
                    if point == "RIGHT" and rel == current and relPoint == "LEFT" then found = child end
                end
            end
        end
        if not found then return current end
        current = found
    end
    return current
end
ns.HeaderRowEnd = RowEnd

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
    -- EllesmereUI's bags: at the left end of its header row (left of Show Bags and sort).
    EUI_MainBagFrame = function()
        local f = _G.EUI_MainBagFrame
        local search = f and f._searchBox
        if not (search and search.GetParent) then return end
        local b = Shortcut(search:GetParent(), "bags", 24, true)
        b:SetPoint("RIGHT", RowEnd(search), "LEFT", -6, 0)
        return b
    end,
    -- EllesmereUI's bank: the same, left of its sort and Show Bags buttons.
    EUI_BankFrame = function()
        local f = _G.EUI_BankFrame
        local search = f and f._searchBox
        if not (search and search.GetParent) then return end
        local b = Shortcut(search:GetParent(), "bank", 24, true)
        b:SetPoint("RIGHT", RowEnd(search), "LEFT", -6, 0)
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
