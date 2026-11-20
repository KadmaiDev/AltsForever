-- Alts Forever bags window: any character's bags or bank, slot by slot, as last seen,
-- either all in one grid or split by bag (bank: by tab), with their money at the bottom.
-- Also their mail: what was in the mailbox when they last opened it (a player's request,
-- 2026-11-18), one slot per item with its total, saying plainly that newer mail isn't known.
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
local NOTE = 30 -- the Mail view's note above its slots (two lines of small text)
local VIEWS = { "bags", "bank", "mail" }
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
-- Or, while the search has nothing picked, every item it matches (`litSet`, a set of item
-- IDs, with the text searched for in `litText`; the owner's idea, 2026-11-18): picking one
-- narrows it to that.
local lit
local litSet, litText

local function Lighting() return lit ~= nil or litSet ~= nil end

local function IsLit(id)
    if id == nil then return false end
    return id == lit or (litSet ~= nil and litSet[id] == true)
end

-- How many of what's lit a counts table (c.bags, c.bank, c.mail) holds.
local function LitIn(t)
    if not t then return 0 end
    if lit then return t[lit] or 0 end
    local n = 0
    if litSet then
        for id in pairs(litSet) do n = n + (t[id] or 0) end
    end
    return n
end
local loadRetry = false
-- Fills in a row from that timer: an item that never loads (one removed from the game)
-- stops it after a few, rather than refilling every second while the window is open.
local retries, retrying = 0, false
local MAX_RETRIES = 5

---------------------------------------------------------------------------
-- What to show (no UI, so tests can check it)
---------------------------------------------------------------------------
-- The slots, reused between fills: item IDs (false for an empty slot), counts, full links
-- (false unless the item has a random bonus or enchant, Scanner.lua), and the sections
-- they're grouped in: { bag = bag index or false, from, to, used }.
local ids, counts, links, sections = {}, {}, {}, {}
local shown, nSections = 0, 0
local keys = 0 -- of the slots shown, how many are the keyring's

local function NewSection(bag)
    nSections = nSections + 1
    local s = sections[nSections] or {}
    sections[nSections] = s
    s.bag, s.from, s.to, s.used = bag, shown + 1, shown, 0
    return s
end

local function Add(section, id, count, link)
    shown = shown + 1
    ids[shown], counts[shown], links[shown] = id or false, count or 0, link or false
    section.to = shown
    if id then section.used = section.used + 1 end
end

-- One slot per item, with its total: for bags or a bank seen before slots were recorded,
-- and for mail.
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

local function HasItem(values)
    for i = 1, #values do
        if values[i] ~= 0 then return true end
    end
    return false
end

local function Trim()
    for i = #ids, shown + 1, -1 do ids[i], counts[i], links[i] = nil, nil, nil end
end

-- Fills the slots for a character's bags, bank or mail, one section per bag if split, else
-- one for all; returns how it was recorded: "slots", "counts" (no layout yet), "mail" or nil
-- (nothing: never seen, or an empty mailbox).
function ns.BagsContents(c, which, split)
    shown, nSections, keys = 0, 0, 0
    if which == "mail" then
        local how = c.mail and next(c.mail) and "mail" or nil
        if how then AddCounts(c.mail) end
        Trim()
        return how
    end
    local layout, kept = c.layout, c.links
    local how
    local section
    for _, bag in ipairs(which == "bank" and ns.BANK_TABS or ns.CARRIED_BAGS) do
        local values = layout and layout[bag]
        -- The keyring holds only keys: its 32 slots aren't room for anything else, so just
        -- its keys are shown, and a character with none has no keyring here at all.
        local ring = bag == BagIndex.Keyring
        if values and (not ring or HasItem(values)) then
            if split or not section then section = NewSection(split and bag or false) end
            local bagLinks = kept and kept[bag]
            for i = 1, #values do
                local id, count = ns.SlotItem(values[i])
                if id or not ring then
                    Add(section, id, count, id and bagLinks and bagLinks[i])
                    if ring then keys = keys + 1 end
                end
            end
            how = "slots"
        end
    end
    if not how then
        local totals = c.bags
        if which == "bank" then totals = c.bank end -- a bank not seen yet stays unknown
        if totals and next(totals) then
            AddCounts(totals)
            how = "counts"
        end
    end
    Trim()
    return how
end

function ns.BagsShown() return ids, counts, shown, sections, nSections, links end

local RetryLater

-- A section's title: the bag's name (or bank tab), or the whole place's.
local function SectionName(c, bag)
    if not bag then return view == "bank" and L["Bank"] or view == "mail" and L["Mail"] or L["Bags"] end
    if bag == BagIndex.Backpack then return BACKPACK_TOOLTIP or L["Backpack"] end
    if bag == BagIndex.Keyring then return KEYRING or L["Keyring"] end
    for i, tab in ipairs(ns.BANK_TABS) do
        if tab == bag then return L["Tab %d"]:format(i) end
    end
    local item = c.layout[bag][0]
    local name = item and C_Item.GetItemNameByID(item)
    if not name and item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(item)
        if RetryLater then RetryLater() end -- its name, once loaded
    end
    return name or L["Bag %d"]:format(bag)
end
ns.BagsSectionName = SectionName

---------------------------------------------------------------------------
-- Bag space (the overview's Bags and Bank columns; a player who'd used Altoholic's,
-- 2026-11-19): free and all slots per character from the saved layout, and each bag or
-- tab for the cell's tooltip. No UI here, so tests can check it.
---------------------------------------------------------------------------

-- Bags 1-4 can be empty (no bag bought yet): the tooltip says so. The backpack is always
-- there; the reagent bag and keyring aren't listed when missing.
local BAG_SLOTS = {}
for _, name in ipairs({ "Bag_1", "Bag_2", "Bag_3", "Bag_4" }) do
    if BagIndex[name] then BAG_SLOTS[BagIndex[name]] = true end
end

local function Places(which)
    return which == "bank" and ns.BANK_TABS or ns.CARRIED_BAGS
end

-- Free and all slots in a character's bags (keyring left out: it holds only keys) or bank
-- tabs; nil when not known (bags: no layout yet; bank: never visited, or visited before
-- slot layouts were saved).
function ns.BagSpace(c, which)
    local layout = c and c.layout
    if type(layout) ~= "table" then return nil end
    local free, total = 0, 0
    for _, bag in ipairs(Places(which)) do
        local values = bag ~= BagIndex.Keyring and layout[bag]
        if values then
            local n = #values
            total = total + n
            for i = 1, n do
                if values[i] == 0 then free = free + 1 end
            end
        end
    end
    if total == 0 then return nil end
    return free, total
end

-- Bag slots 1-4 with no bag in them, for a character whose bags are known.
function ns.EmptyBagSlots(c)
    local layout = c and c.layout
    if type(layout) ~= "table" then return 0 end
    local n = 0
    for bag in pairs(BAG_SLOTS) do
        if not layout[bag] then n = n + 1 end
    end
    return n
end

-- What kind of bag an item is, in the game's words, when it holds only some things (Herb
-- Bag, Soul Bag, Quiver, Ammo Pouch); nil for a plain bag.
local function BagKind(item)
    if not item or item == 0 or not C_Item.GetItemInfoInstant then return nil end
    local _, _, sub, _, _, class, subclass = C_Item.GetItemInfoInstant(item)
    if issecretvalue(sub) or issecretvalue(class) or issecretvalue(subclass) then return nil end
    if type(sub) ~= "string" or sub == "" then return nil end
    if (class == 1 and subclass ~= 0) or class == 11 then return sub end
    return nil
end

-- Each bag (or bank tab) in order, for the tooltip: { name, icon, quality, kind, free,
-- size }, size 0 for an empty bag slot. Names not loaded yet are requested and read as
-- "Bag n" until they are.
local spaceList = {}
function ns.BagSpaceList(c, which)
    wipe(spaceList)
    local layout = c and c.layout
    if type(layout) ~= "table" then return spaceList end
    for _, bag in ipairs(Places(which)) do
        local values = bag ~= BagIndex.Keyring and layout[bag]
        if values or BAG_SLOTS[bag] then
            local e = { free = 0, size = values and #values or 0 }
            for i = 1, e.size do
                if values[i] == 0 then e.free = e.free + 1 end
            end
            local item = values and values[0]
            if not values then
                e.name, e.icon = L["Empty bag slot"], "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"
            elseif item and item ~= 0 then
                local name = C_Item.GetItemNameByID(item)
                if issecretvalue(name) or type(name) ~= "string" then
                    name = nil
                    if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(item) end
                end
                e.name = name or L["Bag %d"]:format(bag)
                e.icon = GetItemIconByID(item)
                local q = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(item)
                if not issecretvalue(q) then e.quality = q end
                e.kind = BagKind(item)
            else -- the backpack, a bank tab, or a bag whose item wasn't recorded
                e.name = SectionName(c, bag)
                e.icon = bag == BagIndex.Backpack and "Interface\\Buttons\\Button-Backpack-Up" or nil
            end
            spaceList[#spaceList + 1] = e
        end
    end
    return spaceList
end

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
    -- Its own link when it has a bonus or enchant ("of Intellect"); the item ID alone
    -- would show the plain item.
    if b.link then GameTooltip:SetHyperlink(b.link) else GameTooltip:SetItemByID(b.id) end
    GameTooltip:Show()
end

local function SlotClick(b)
    -- Shift-click links the item in chat, like the game's own bags.
    if not (b.id and IsModifiedClick()) then return end
    local link = b.link
    if not link then link = select(2, C_Item.GetItemInfo(b.id)) end
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
    ns.SkinItemSlot(b)
    slots[i] = b
    return b
end

-- A section heading with a faint line after it, as in EllesmereUI's bags.
local function Header(i)
    local h = headers[i]
    if h then return h end
    h = frame.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ns.SkinHeading(h)
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
function RetryLater()
    if loadRetry or not C_Timer or retries >= MAX_RETRIES then return end
    loadRetry, retries = true, retries + 1
    C_Timer.After(1, function()
        if frame and frame:IsShown() then
            retrying = true
            Fill()
            retrying = false
        end
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

local function ShowSlot(b, id, count, link)
    b.id, b.link = id or nil, id and link or nil
    local dim = Lighting() and not IsLit(id) and 0.25 or 1
    b.icon:SetAlpha(dim)
    b.border:SetAlpha(dim)
    b.count:SetAlpha(dim)
    if not id then
        b.count:SetText("")
        b.border:Hide()
        if not ns.SlotEmpty(b, nil, dim) then b.icon:SetTexture(EMPTY_SLOT) end
        return
    end
    b.icon:SetTexture(GetItemIconByID(id) or 134400)
    b.count:SetText(count > 1 and count or "")
    local q = Quality(id)
    if ns.SlotQuality(b, q, dim) then return end
    local qc = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    local color = q and q >= 2 and qc
    if color then
        b.border:SetVertexColor(color.r, color.g, color.b)
        b.border:Show()
    else
        b.border:Hide()
    end
end

-- Where the lit item (or any lit item) is: each character's bags, bank and mail holding it,
-- the character with most first. What the arrows beside "Showing: ..." step through.
local stops = {}

local function ByMost(a, b)
    if a.n ~= b.n then return a.n > b.n end
    return a.key < b.key
end

local function Stops()
    wipe(stops)
    if not Lighting() then return stops end
    local list = {}
    for key, c in pairs(ns.db.chars) do
        if not ns.Hidden(c) then
            local inBags, inBank, inMail = LitIn(c.bags), LitIn(c.bank), LitIn(c.mail)
            local n = inBags + inBank + inMail
            if n > 0 then list[#list + 1] = { key = key, n = n, bags = inBags, bank = inBank, mail = inMail } end
        end
    end
    sort(list, ByMost)
    for _, h in ipairs(list) do
        if h.bags > 0 then stops[#stops + 1] = { key = h.key, view = "bags" } end
        if h.bank > 0 then stops[#stops + 1] = { key = h.key, view = "bank" } end
        if h.mail > 0 then stops[#stops + 1] = { key = h.key, view = "mail" } end
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
        if IsLit(ids[i]) and slots[i] and slots[i].top then
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
    if view == "mail" then
        return c.mailAt and L["Mailbox last opened: %s"]:format(ns.FormatAgo(now - c.mailAt)) or ""
    end
    return L["Last seen: %s"]:format(ns.SeenText(shownKey, c, now))
end

local MIN_VIEW = 3 * (SIZE + GAP)
local function WidthFor(n) return PAD * 2 + n * (SIZE + GAP) - GAP end
local function ColsFor(width)
    return max(MIN_COLS, min(MAX_COLS, floor((width - PAD * 2 + GAP) / (SIZE + GAP) + 0.5)))
end

-- The top row: the character button, Bags, Bank, Mail, the "By bag" tick box and its words.
local WHO_WIDTH, WHO_MIN, BUTTON_MIN, TICK = 140, 80, 48, 24
local TICK_GAP = 6 -- between the tick box and "By bag" (2 looked snug, owner 2026-11-18)

local function TextWidth(fs, fallback)
    local w = fs and fs.GetStringWidth and fs:GetStringWidth()
    if type(w) ~= "number" or issecretvalue(w) or w <= 0 then return fallback end
    return w
end

-- The view buttons' words, with how many of the lit item the shown character has there
-- ("Bank (40)", as the tooltip counts it; with every match lit, all of them together;
-- the owner's idea, 2026-11-18), each button
-- sized to its text. The row must fit the window at its narrowest in every language: if
-- it wouldn't, "By bag" loses its words (the tick box and its tooltip stay), then the
-- character button gives up width, down to WHO_MIN (its name cut short).
local function Tabs(c)
    local need = 0
    for _, v in ipairs(VIEWS) do
        local b = frame[v]
        local n = LitIn(c[v])
        local word = v == "bank" and L["Bank"] or v == "mail" and L["Mail"] or L["Bags"]
        b:SetText(n > 0 and (word .. " (" .. n .. ")") or word)
        local w = max(BUTTON_MIN, floor(TextWidth(b.GetFontString and b:GetFontString(), 36) + 20))
        b:SetWidth(w)
        need = need + 4 + w
    end
    need = need + 4 + TICK
    local room = WidthFor(cols) - PAD * 2
    local label = frame.split.label
    local words = WHO_WIDTH + need + TICK_GAP + TextWidth(label, 40) <= room
    label:SetShown(words)
    local whoWidth = words and WHO_WIDTH or max(WHO_MIN, min(WHO_WIDTH, room - need))
    frame.who:SetWidth(whoWidth)
    local fs = frame.who.GetFontString and frame.who:GetFontString()
    if fs and fs.SetWidth then fs:SetWidth(whoWidth - 16) end
end

-- The tallest the slot area gets before it scrolls: as the player sized it, or by
-- default 70% of the screen (in the window's own units: it may be scaled, Options.lua).
local function MaxView()
    if ns.db.bagsHeight then return max(ns.db.bagsHeight, MIN_VIEW) end
    local h = UIParent and UIParent:GetHeight() / ns.WindowScale() or 0
    return max(h > 0 and floor(h * 0.7) - TOP - BOTTOM or 560, MIN_VIEW)
end

-- The slot area's height for a character's bags or bank (fills the shared lists, so only
-- before Fill reads them).
local function ContentHeight(c, which, split)
    local how = ns.BagsContents(c, which, split)
    local y = how == "mail" and NOTE or 0
    for n = 1, nSections do
        local s = sections[n]
        y = y + HEADER + ceil((s.to - s.from + 1) / cols) * (SIZE + GAP) + SECTION_GAP
    end
    return y
end

-- One height while you look around: while an item is lit or the search is docked beside
-- the window, it's the tallest of everywhere you might go next (each bags or bank with the
-- lit item; with the search, the shown character's bags and bank), and never less than
-- before, so nothing under the mouse moves (owner, 2026-10-16: the resizing made the arrows
-- hard to click, and the window jumped as the search lit one item after another). It fits
-- its contents again once neither.
local steady, searchDocked

Place = function()
    -- While the player drags the grip, the window keeps the height they're dragging to.
    local want = max(contentHeight, steady or 0)
    local visible = sizing and max(frame:GetHeight() - TOP - BOTTOM, MIN_VIEW) or max(min(want, MaxView()), MIN_VIEW)
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
    if not retrying then retries = 0 end
    if not sizing then
        cols = ns.db.bagsCols or DEFAULT_COLS
        frame:SetWidth(WidthFor(cols))
    end
    local split = ns.db.bagsSplit and true or false
    if Lighting() or searchDocked then
        local h = steady or 0
        if Lighting() then
            for _, s in ipairs(Stops()) do
                local sc = ns.db.chars[s.key]
                if sc then h = max(h, ContentHeight(sc, s.view, split)) end
            end
        end
        if searchDocked then h = max(h, ContentHeight(c, "bags", split), ContentHeight(c, "bank", split)) end
        steady = h
    else
        steady = nil
    end
    local how = ns.BagsContents(c, view, split)
    frame.who:SetText(ns.ColoredName(shownKey, c))
    Tabs(c)
    for _, v in ipairs(VIEWS) do
        if v == view then frame[v]:LockHighlight() else frame[v]:UnlockHighlight() end
    end
    frame.split:SetChecked(split)
    -- Mail is a list, not slots: one grid whatever "By bag" says.
    frame.split:SetEnabled(view ~= "mail")

    -- Mail: say plainly that this is the mailbox as it was, not what's there now.
    local y, free = 0, 0
    local mailNote = how == "mail"
    frame.note:SetShown(mailNote)
    if mailNote then
        frame.note:SetWidth(cols * (SIZE + GAP) - GAP)
        frame.note:SetText(GREY .. L["What was in the mailbox when this character last opened it, plus anything your characters have mailed them since. Newer mail isn't shown."] .. "|r")
        y = NOTE
    end
    for n = 1, nSections do
        local s = sections[n]
        local h = Header(n)
        local title = SectionName(c, s.bag)
        if how == "slots" then
            local size = s.bag == BagIndex.Keyring and "" or (" / " .. (s.to - s.from + 1))
            h:SetText(title .. GREY .. "  (" .. s.used .. size .. ")|r")
        elseif how == "mail" then
            h:SetText(title .. GREY .. "  (" .. s.used .. ")|r")
        else
            -- Totals only: say so beside the heading (too long for the bottom row).
            h:SetText(title .. GREY .. "   " .. (view == "bank" and L["Totals only: visit the bank on this character to see its slots."]
                or L["Totals only: log in on this character to see its slots."]) .. "|r")
        end
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -y)
        h:Show()
        h.line:SetShown(how == "slots" or how == "mail")
        y = y + HEADER
        for i = s.from, s.to do
            local k = i - s.from
            local b = Slot(i)
            b.top = y + floor(k / cols) * (SIZE + GAP)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", frame.content, "TOPLEFT", k % cols * (SIZE + GAP), -y - floor(k / cols) * (SIZE + GAP))
            ShowSlot(b, ids[i], counts[i], links[i])
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
        local text
        if view == "bank" then
            text = L["Bank not seen yet.\nVisit the bank on this character once."]
        elseif view == "mail" then
            text = c.mail and L["The mailbox was empty when this character last opened it.\nNewer mail isn't shown."]
                or L["Mailbox not seen yet.\nOpen the mailbox on this character once."]
        else
            text = L["No bags recorded yet.\nLog in on this character once."]
        end
        frame.empty:SetText(GREY .. text .. "|r")
    end
    frame.empty:SetShown(not how)
    if how == "slots" then
        frame.info:SetText(L["%d of %d slots free"]:format(free, shown - keys))
    else
        frame.info:SetText("")
    end
    local lighting = Lighting()
    if lit then
        local name = C_Item.GetItemNameByID(lit)
        if type(name) ~= "string" or issecretvalue(name) then name = "?" end
        -- White like the rest of the footer, the item in its quality colour.
        local qc = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[Quality(lit) or 1]
        if qc and type(qc.hex) == "string" then name = qc.hex .. name .. "|r" end
        frame.clear.text:SetText(L["Showing: %s"]:format(name))
    elseif litSet then
        frame.clear.text:SetText(L["Showing everything matching '%s'"]:format(litText or ""))
    end
    if lighting then
        local w = frame.clear.text:GetStringWidth()
        if type(w) == "number" and not issecretvalue(w) then frame.clear:SetWidth(w + 20) end
    end
    frame.clear:SetShown(lighting)
    frame.info:SetShown(not lighting)
    local n = #Stops()
    local i = StopIndex()
    frame.stop:SetText(lighting and (i > 0 and L["%d of %d"]:format(i, n) or L["not here"]) or "")
    -- Arrows when there's somewhere else to go.
    local arrows = lighting and (n > 1 or (n == 1 and i == 0))
    frame.prev:SetShown(arrows)
    frame.next:SetShown(arrows)
    frame.stop:SetShown(lighting)
    local seen = how or (view == "mail" and c.mail)
    seen = seen and Seen(c, time()) or ""
    frame.seen:SetText(seen ~= "" and (GREY .. seen .. "|r") or "")
    frame.money:SetText(c.money and GetCoinTextureString(c.money) or "")
end

-- Every character, in the overview's order and, as there, headed by ruleset and faction
-- when you have more than one group.
local function PickCharacter(owner)
    ns.OpenMenu(owner, function(_, root)
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
            -- With an item lit: how many each character has of it (bags, bank and mail).
            local n = Lighting() and (LitIn(c.bags) + LitIn(c.bank) + LitIn(c.mail)) or 0
            root:CreateRadio(ns.ColoredName(key, c) .. (n > 0 and " |cffffffff(" .. n .. ")|r" or ""),
                function(k) return k == shownKey end,
                function(k)
                    shownKey, scroll = k, 0
                    Fill()
                end, key)
        end
    end)
end

-- Bags, Bank, Mail: one after another from `after`, each sized to its text by Tabs.
local function ViewButton(name, text, after)
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetText(text)
    b:SetSize(BUTTON_MIN, 22)
    b:SetPoint("LEFT", after, "RIGHT", 4, 0)
    b:SetScript("OnClick", function()
        view, scroll = name, 0
        Fill()
    end)
    ns.SkinButton(b)
    frame[name] = b
end

local function CreateWindow()
    local f = ns.NewWindow("AltsForeverBagsFrame")
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
    ns.TrackWindow(f, "bags", true, ns.DockIfOverview)
    f:SetClampedToScreen(true)
    local title = f.TitleText or f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if not f.TitleText then title:SetPoint("TOP", 0, -6) end
    title:SetText(L["Bags and bank"])

    -- The character dropdown.
    local who = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    who:SetSize(WHO_WIDTH, 22)
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
    ViewButton("bags", L["Bags"], who)
    ViewButton("bank", L["Bank"], f.bags)
    ViewButton("mail", L["Mail"], f.bank)
    f.mail:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Mail"])
        GameTooltip:AddLine(L["What was in the mailbox when this character last opened it. Newer mail isn't shown."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f.mail:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- All in one grid, or a section per bag (the choice is kept for every character).
    local split = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    split:SetSize(TICK, TICK)
    split:SetPoint("LEFT", f.mail, "RIGHT", 4, 0)
    split.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    split.label:SetPoint("LEFT", split, "RIGHT", TICK_GAP, 0)
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
    -- The Mail view's note, above its slots (scrolls with them).
    f.note = f.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.note:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, 0)
    f.note:SetJustifyH("LEFT")
    f.note:SetJustifyV("TOP")
    f.note:SetHeight(NOTE - 4)
    f.note:SetWordWrap(true)
    f.note:Hide()
    ns.SkinText(f.note)
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
    clear.text = clear:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    clear.text:SetPoint("LEFT")
    clear.x = clear:CreateTexture(nil, "ARTWORK")
    clear.x:SetSize(14, 14)
    clear.x:SetPoint("LEFT", clear.text, "RIGHT", 4, 0)
    clear.x:SetTexture("Interface\\Buttons\\UI-StopButton")
    clear:SetScript("OnClick", function()
        lit, litSet, litText = nil, nil, nil
        Fill()
        if ns.SearchUnpick then ns.SearchUnpick() end
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
    ns.OverTitle(f, search)
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

    ns.EscapeCloses(f)
    ns.SkinWindow(f, ns.BagsShellOpts())
    ns.SkinBagsWindow(f)
    f:Hide()
    f:SetPoint("CENTER")
    -- The game's own bag sounds, however the window is opened or closed (Esc too); hooked
    -- after the Hide above, so creating the window makes no sound.
    local sounds = SOUNDKIT or {}
    f:HookScript("OnShow", function() if sounds.IG_BACKPACK_OPEN then PlaySound(sounds.IG_BACKPACK_OPEN) end end)
    f:HookScript("OnHide", function()
        lit, litSet, litText = nil, nil, nil
        steady = nil
        if sounds.IG_BACKPACK_CLOSE then PlaySound(sounds.IG_BACKPACK_CLOSE) end
    end)
    ns.GamepadWindow(f)
    ns.ScaleWindow(f)
end

-- Opens a character's bags, bank or mail; the same again closes it. With `highlight` (an item
-- ID, from the search) it stays open, lights that item up and scrolls to it.
function ns.ShowBags(key, which, highlight)
    if not frame then CreateWindow() end
    key, which = key or ns.charKey, which or "bags"
    if not highlight and frame:IsShown() and shownKey == key and view == which then return frame:Hide() end
    if shownKey ~= key or view ~= which then scroll = 0 end
    shownKey, view, lit, litSet, litText = key, which, highlight, nil, nil
    Fill()
    if highlight then ScrollToLit() end
    -- Where it was left, else beside the overview if that's open (once it's sized).
    if not frame:IsShown() then ns.PlaceWindow(frame) end
    frame:Show()
end

function ns.BagsHighlight() return lit end

-- For the search (Search.lua), while this window is open: whose bags it shows, and what's
-- lit and in which view, to put back if the search is closed without picking.
function ns.BagsShownKey() return frame and frame:IsShown() and shownKey or nil end
function ns.BagsState() return lit, view, litSet, litText end

-- Anything lit: one item, or the search's matches.
function ns.BagsLighting() return frame ~= nil and Lighting() end

-- The view on the shown character holding what's lit: the one shown if it does, else the
-- first that does, else nil.
local function ViewWithLit(c)
    if LitIn(c[view]) > 0 then return view end
    for _, v in ipairs(VIEWS) do
        if LitIn(c[v]) > 0 then return v end
    end
end

-- Lights an item up on the character shown, in place: their bags, bank or mail, wherever it
-- is (switching between them, never to another character). If they haven't got it there it's
-- lit all the same, "not here" with the arrows to whoever has (the owner saw an item in the
-- mail bring back the one picked before, 2026-10-16), and it returns false.
function ns.BagsPreview(id)
    local c = frame and frame:IsShown() and ns.db.chars[shownKey]
    if not c then return false end
    local here = c[view] and c[view][id]
    local there
    if not here then
        for _, v in ipairs(VIEWS) do
            if c[v] and c[v][id] then
                there = v
                break
            end
        end
    end
    local has = (here or there) and true or false
    if lit == id and not litSet and (here or not has) then return has end
    if there then view = there end
    lit, litSet, litText, scroll = id, nil, nil, 0
    Fill()
    ScrollToLit()
    return has
end

-- Lights every item in `set` (item ID -> true) on the character shown, in place, as
-- BagsPreview does one: the view switches to one holding some if this one holds none.
-- `text` is what was searched for, for the footer. Returns whether they have any.
function ns.BagsPreviewAll(set, text)
    local c = frame and frame:IsShown() and ns.db.chars[shownKey]
    if not c then return false end
    lit, litSet, litText, scroll = nil, set, text, 0
    local v = ViewWithLit(c)
    if v then view = v end
    Fill()
    ScrollToLit()
    return v ~= nil
end

function ns.BagsRestore(oldLit, oldView, oldSet, oldText)
    if not (frame and frame:IsShown()) then return end
    lit, view, scroll = oldLit, oldView or view, 0
    litSet = not oldLit and oldSet or nil
    litText = litSet and oldText or nil
    Fill()
    if Lighting() then ScrollToLit() end
end

function ns.BagsWindow() return frame end

-- The search docked beside the window (true) or gone (false): one height while it's there.
function ns.BagsHold(on)
    on = on and true or false
    if searchDocked == on then return end
    searchDocked = on
    if frame and frame:IsShown() then Fill() end
end

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
-- `skip` is our own button, so it can be placed again without finding itself.
local function Chained(current, skip, ...)
    local found
    for n = 1, select("#", ...) do
        local child = select(n, ...)
        if child ~= current and child ~= skip and child:IsShown() and child.GetPoint then
            for i = 1, (child.GetNumPoints and child:GetNumPoints() or 1) do
                local point, rel, relPoint = child:GetPoint(i)
                if point == "RIGHT" and rel == current and relPoint == "LEFT" then found = child end
            end
        end
    end
    return found
end

local function RowEnd(start, skip)
    local parent, current = start:GetParent(), start
    for _ = 1, 20 do
        local found = Chained(current, skip, parent:GetChildren())
        if not found then return current end
        current = found
    end
    return current
end
ns.HeaderRowEnd = RowEnd

-- Puts our button at the left end of EllesmereUI's row. In its Forever look the search
-- box is on the left instead, stretched up to the row's leftmost icon: ours then goes
-- between the two, and the search box ends at ours.
local function PlaceInRow(b, search)
    local inner
    for i = 1, (search.GetNumPoints and search:GetNumPoints() or 1) do
        local point, rel, relPoint = search:GetPoint(i)
        if point == "RIGHT" and relPoint == "LEFT" and type(rel) == "table" then inner = rel end
    end
    if inner == b then return true end -- still between them
    b:ClearAllPoints()
    if inner then
        b:SetPoint("RIGHT", inner, "LEFT", -6, 0)
        search:SetPoint("RIGHT", b, "LEFT", -6, 0)
        return true
    end
    b:SetPoint("RIGHT", RowEnd(search, b), "LEFT", -6, 0)
end

-- Where a piece of header text ends, or nil if it isn't showing or can't be read.
local function TextEnd(t)
    if not (type(t) == "table" and t.GetRight and t:IsShown()) or t:GetAlpha() == 0 then return nil end
    local right = t:GetRight()
    if issecretvalue(right) then return nil end
    return right
end

-- EllesmereUI's flat look has the title and slot count in the same row and fits them
-- up to its own leftmost icon, so on a narrow window with Sell Junk showing ours would
-- cover the count (owner's screenshot, 2026-11-11). Ours then moves to the footer's left
-- end (owner's choice), or hides if tracked currencies are listed there. Read only.
local function ClearOfText(f, b)
    b:Show()
    local hdr = f.Header
    local left = b:GetLeft()
    if not (type(hdr) == "table" and hdr.title and left) or issecretvalue(left) then return end
    local last = TextEnd(hdr.title) or 0
    local count = TextEnd(hdr.itemCount)
    if count and count > last then last = count end
    for i = 1, hdr.slotLines and 2 or 0 do -- the count on two lines
        local line = TextEnd(hdr.slotLines[i])
        if line and line > last then last = line end
    end
    if left >= last + 4 then return end
    local footer, pool = f.Footer, f._currencyPool
    local first = type(pool) == "table" and type(pool.displays) == "table" and pool.displays[1]
    if type(footer) ~= "table" or first and first:IsShown() then b:Hide() return end
    b:ClearAllPoints()
    b:SetPoint("LEFT", footer, "LEFT", 6, 0)
end

-- EllesmereUI lays its row out again when a setting changes or a merchant opens (the
-- junk coin, Sell Junk; 9.8.4 covered ours, 2026-11-11), so ours is placed again after
-- each layout, each fitting of the header text (resizing) and whenever the window opens.
local function FollowRow(f, b, search)
    local function Again()
        if not PlaceInRow(b, search) then ClearOfText(f, b) end
    end
    if f.HookScript then f:HookScript("OnShow", Again) end
    if type(f.SyncHeaderIcons) == "function" then hooksecurefunc(f, "SyncHeaderIcons", Again) end
    if type(f.FitHeaderText) == "function" then hooksecurefunc(f, "FitHeaderText", Again) end
    Again()
end

-- Where each window gets its button. Each returns the button, or nil if the window
-- (or the part it's placed beside) isn't there yet. EllesmereUI's fields are not its
-- official API: they're checked before use.
local PLACES = {
    -- Blizzard's bank: in the title area, left of the search box.
    BankFrame = function()
        local search = _G.BankItemSearchBox
        if not (_G.BankFrame and search) then return end
        -- Not made inside the open bank with the Gamepad UI on: Blizzard's navigator would
        -- rebuild it from our code (see ns.PrebuildMail); the next login or bag toggle does it.
        if ns.GamepadUI() and _G.BankFrame:IsVisible() then return end
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
        FollowRow(f, b, search)
        return b
    end,
    -- EllesmereUI's bank: the same, left of its sort and Show Bags buttons.
    EUI_BankFrame = function()
        local f = _G.EUI_BankFrame
        local search = f and f._searchBox
        if not (search and search.GetParent) then return end
        local b = Shortcut(search:GetParent(), "bank", 24, true)
        FollowRow(f, b, search)
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
-- separate bags; tags checked in game 2026-09-28). None with the Gamepad UI on: the
-- navigator takes the menu in as a window, and our entry left its bindings tainted, so
-- closing the bags afterwards raised ADDON_ACTION_FORBIDDEN on
-- SetPreferredGamepadInteractTarget() (a player's report; reproduced by the owner,
-- 2026-11-20: only after opening ours from this menu, never from /af bags). Asked each time
-- the menu opens, as the Gamepad UI can be switched on and off while playing.
local function AddMenuEntry(_, root)
    if ns.GamepadUI() then return end
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
