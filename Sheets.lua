-- Alts Forever character window pages: Character (gear and what's known about them),
-- Reputation and Skills. The window itself is the professions window's frame (Recipes.lua):
-- its side tabs are these three pages, then one per profession, as the game's own
-- character window has Character, Reputation and Skills tabs down its right edge (the
-- owner's idea, 2026-11-25: one window per character instead of a window per thing).
-- Pages are built the first time they're shown; the lists are worked out by functions
-- without UI (tested).
local _, ns = ...
if ns.disabled then return end -- another copy of Alts Forever is running (Core.lua)
local L = ns.L

local CreateFrame, GameTooltip = CreateFrame, GameTooltip
local max, min, ipairs, pairs, type, sort, tostring, tonumber = math.max, math.min, ipairs, pairs, type, table.sort, tostring, tonumber
local issecretvalue = issecretvalue or function() return false end
local GetItemInfoInstant = C_Item.GetItemInfoInstant
local GetCoinTextureString = C_CurrencyInfo.GetCoinTextureString

local GREY, ATTENTION = "|cff9d9d9d", "|cffff8000"
local WIDTH = 673                       -- the window's (Recipes.lua)
local TOP = -64                         -- where a page's content starts, under the title bar
local QUESTION = 134400                 -- INV_Misc_QuestionMark

---------------------------------------------------------------------------
-- What the pages show (no UI)
---------------------------------------------------------------------------
-- The Character page's facts as { label, value } pairs; anything not known is left out.
-- Your own facts changed (money, XP, zone, a bag or bank scan...): an open Character page
-- showing you is filled again. Called wherever the overview is told, and costs nothing
-- with the window closed or on another page or character.
function ns.CharacterFactsChanged()
    if ns.CharacterWindowShown() == "character" then ns.CharacterWindowChanged() end
end

function ns.CharacterFacts(key, c, now)
    local rows = {}
    local function Add(label, value)
        if value and value ~= "" then rows[#rows + 1] = { label, value } end
    end
    Add(L["Level"], c.level and ns.LevelText(c))
    if c.level and c.level < ns.MaxLevel() then
        Add(L["Rested"], ns.RestedText(c, now))
        Add(L["Full in"], ns.RestedFullText(c, now))
    end
    Add(ns.WellRestedName(), c.wellRested and (c.wellRested .. "/5"))
    local unspent = ns.LegacyUnspent(c)
    if unspent then
        Add(L["Legacy points"], unspent > 0 and (ATTENTION .. L["%d to spend"]:format(unspent) .. "|r") or L["all spent"])
    end
    Add(L["Gold"], c.money and GetCoinTextureString(c.money))
    Add(L["Played"], c.played and ns.PlayedText(c, now))
    Add(L["Item level"], c.ilvl and tostring(c.ilvl))
    Add(L["Lowest durability"], c.dura and ns.DurabilityText(c.dura))
    Add(L["Zone"], c.zone)
    Add(L["Hearthstone"], ns.HearthText(c, now))
    local free, total = ns.BagSpace(c, "bags")
    Add(L["Bags"], free and L["%d of %d free"]:format(free, total))
    free, total = ns.BagSpace(c, "bank")
    Add(L["Bank"], free and L["%d of %d free"]:format(free, total))
    if c.mailExpires then
        local left = c.mailExpires - now
        Add(L["Mail expires"], ns.ExpiryColor(left) .. ns.ExpiryText(left) .. "|r")
    end
    Add(L["Last seen"], ns.SeenText(key, c, now))
    return rows
end

local function ByName(a, b) return a.name < b.name end

-- The Skills page, as the game's own Skills tab: sections { name, rows }, a row
-- { name, rank, max, untrained, at, weapon }. Main professions, then secondary ones, then
-- weapon skills and armour (Upgrades.lua's ns.CombatSkills). The second value is true
-- when the weapon skills haven't been read yet (not logged in since they were added).
function ns.SkillSections(c)
    local out = {}
    local main, second = {}, {}
    for name, skill in pairs(c.profs or {}) do
        local row = { name = name, rank = skill, max = c.profMax and c.profMax[name] }
        if name == c.prof1 or name == c.prof2 then main[#main + 1] = row else second[#second + 1] = row end
    end
    sort(main, ByName)
    sort(second, ByName)
    if main[1] then out[#out + 1] = { name = L["Professions"], rows = main } end
    if second[1] then out[#out + 1] = { name = L["Secondary professions"], rows = second } end
    local weapons, armour = ns.CombatSkills(c)
    if weapons then
        out[#out + 1] = { name = L["Weapon skills"], rows = weapons }
        if armour[1] then out[#out + 1] = { name = L["Armor proficiencies"], rows = armour } end
    end
    return out, weapons == nil
end

-- The Reputation page: every faction the character has a standing with, by name.
function ns.ReputationRows(c)
    local names = ns.db.factions or {}
    local rows = {}
    for id, value in pairs(c.reps or {}) do
        local level, low, high = ns.Standing(value)
        local label, colour = ns.StandingLabel(level)
        local name = names[id]
        rows[#rows + 1] = { name = type(name) == "string" and name or ("#" .. id), id = id, value = value,
            level = level, low = low, high = high, label = label, colour = colour }
    end
    sort(rows, ByName)
    return rows
end

---------------------------------------------------------------------------
-- A list of bars under collapsible headings (Skills and Reputation), drawn from a pool of
-- rows as far as the page allows; the mouse wheel and the page arrows scroll it.
---------------------------------------------------------------------------
local ROW_H, HEAD_H, GAP = 24, 25, 2
local PER_PAGE = 19 -- rows that fit: (594 - 64 - 14) / (ROW_H + GAP)
local BAR_W = 260

local function HasAtlas(name)
    return C_Texture and C_Texture.GetAtlasInfo and name and C_Texture.GetAtlasInfo(name) ~= nil
end

local function Flat() return ns.SkinFlat and ns.SkinFlat() or false end

local function ListRows(list)
    local shown, n = list.shown, 0
    for i = list.offset + 1, #shown do
        if n == PER_PAGE then break end
        n = n + 1
        local row, e = list.rows[n], shown[i]
        row.entry = e
        local head = e.head ~= nil
        for _, part in ipairs({ row.headBg, row.headText, row.toggle }) do part:SetShown(head) end
        row.label:SetShown(not head)
        row.bar:SetShown(not head and not e.none)
        row:SetHeight(head and HEAD_H or ROW_H)
        if head then
            row.headText:SetText(e.head)
            local folded = list.collapsed[e.head]
            if HasAtlas("common-button-list-plus") then
                row.toggle:SetAtlas(folded and "common-button-list-plus" or "common-button-list-minus", true)
            else
                row.toggle:SetSize(16, 16)
                row.toggle:SetTexture(folded and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
            end
        else
            row.label:SetText(e.label)
            if e.grey then row.label:SetTextColor(0.5, 0.5, 0.5) else row.label:SetTextColor(1, 1, 1) end
            if not e.none then
                local bar = row.bar
                bar:SetMinMaxValues(0, e.max and e.max > 0 and e.max or 1)
                bar:SetValue(e.value or 0)
                bar:SetStatusBarColor(e.r or 0.15, e.g or 0.4, e.b or 0.9)
                bar.text:SetText(e.text or "")
            end
        end
        row:Show()
    end
    for i = n + 1, PER_PAGE do list.rows[i]:Hide() end
    local more = #shown > PER_PAGE
    list.up:SetShown(more)
    list.down:SetShown(more)
end

-- What's shown: each heading, then its rows unless folded away.
local function Flatten(list)
    local shown = list.shown
    for i = #shown, 1, -1 do shown[i] = nil end
    local folded
    for _, e in ipairs(list.entries) do
        if e.head then
            folded = list.collapsed[e.head]
            shown[#shown + 1] = e
        elseif not folded then
            shown[#shown + 1] = e
        end
    end
    list.offset = max(0, min(list.offset, #shown - PER_PAGE))
    ListRows(list)
end

local function Scroll(list, by)
    list.offset = max(0, min(#list.shown - PER_PAGE, list.offset + by))
    ListRows(list)
end

local function RowClick(row)
    local e, list = row.entry, row.list
    if e and e.head then
        list.collapsed[e.head] = not list.collapsed[e.head] or nil
        Flatten(list)
    end
end

local function RowEnter(row)
    local e = row.entry
    if not (e and e.tip) then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    e.tip(GameTooltip, e)
    GameTooltip:Show()
end

local function MakeRow(list)
    local row = CreateFrame("Button", nil, list)
    row:SetWidth(WIDTH - 16 - 44)
    row.list = list
    row.headBg = row:CreateTexture(nil, "BACKGROUND")
    row.headBg:SetAllPoints()
    if HasAtlas("common-button-list-collapseExpand") and not Flat() then
        row.headBg:SetAtlas("common-button-list-collapseExpand")
    else
        row.headBg:SetColorTexture(1, 1, 1, 0.08)
    end
    row.headText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.headText:SetPoint("LEFT", 10, 0)
    row.toggle = row:CreateTexture(nil, "OVERLAY")
    row.toggle:SetPoint("RIGHT", -8, 0)
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.label:SetPoint("LEFT", 12, 0)
    row.label:SetPoint("RIGHT", row, "RIGHT", -BAR_W - 20, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    local bar = CreateFrame("StatusBar", nil, row)
    bar:SetSize(BAR_W, 18)
    bar:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    bar:SetStatusBarTexture(Flat() and "Interface\\Buttons\\WHITE8X8" or "Interface\\TargetingFrame\\UI-StatusBar")
    local trough = bar:CreateTexture(nil, "BACKGROUND")
    trough:SetAllPoints()
    trough:SetColorTexture(0, 0, 0, 0.6)
    for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" } }) do
        local t = bar:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(0.45, 0.45, 0.45, 0.9)
        t:SetPoint(edge[1])
        t:SetPoint(edge[2])
        t:SetHeight(1)
    end
    for _, edge in ipairs({ { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local t = bar:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(0.45, 0.45, 0.45, 0.9)
        t:SetPoint(edge[1])
        t:SetPoint(edge[2])
        t:SetWidth(1)
    end
    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.text:SetPoint("CENTER")
    row.bar = bar
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.05)
    row:SetScript("OnClick", RowClick)
    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    for _, fs in ipairs({ row.headText, row.label, bar.text }) do ns.SkinText(fs) end
    return row
end

local function MakeList(page)
    local list = CreateFrame("Frame", nil, page)
    list:SetPoint("TOPLEFT", page, "TOPLEFT", 16, TOP)
    list:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -28, 14)
    list.entries, list.shown, list.collapsed, list.offset, list.rows = {}, {}, {}, 0, {}
    for i = 1, PER_PAGE do
        local row = MakeRow(list)
        if i == 1 then
            row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
        else
            row:SetPoint("TOPLEFT", list.rows[i - 1], "BOTTOMLEFT", 0, -GAP)
        end
        list.rows[i] = row
    end
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(self, delta) Scroll(self, -delta * 3) end)
    list.up = ns.PageButton(page, true, function() Scroll(list, -(PER_PAGE - 2)) end)
    list.up:SetSize(16, 16)
    list.up:SetPoint("TOPRIGHT", page, "TOPRIGHT", -8, TOP)
    list.down = ns.PageButton(page, false, function() Scroll(list, PER_PAGE - 2) end)
    list.down:SetSize(16, 16)
    list.down:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -8, 14)
    list.empty = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    list.empty:SetPoint("CENTER", page, "CENTER", 0, 20)
    list.empty:SetWidth(420)
    ns.SkinText(list.empty)
    page.list = list
    return list
end

-- New entries for the list; folded headings stay folded (for the session).
local function SetEntries(list, entries, emptyText, keepOffset)
    list.entries = entries
    if not keepOffset then list.offset = 0 end
    list.empty:SetText(emptyText or "")
    list.empty:SetShown(entries[1] == nil and emptyText ~= nil)
    Flatten(list)
end

---------------------------------------------------------------------------
-- Skills
---------------------------------------------------------------------------
local function SkillTip(tt, e)
    local r = e.row
    tt:AddLine(r.name, 1, 1, 1)
    if r.untrained then
        tt:AddLine(r.at and L["at level %d"]:format(r.at) or L["Not trained"], 0.5, 0.5, 0.5)
        if r.weapon then tt:AddLine(L["A weapon master can teach it."], 1, 0.82, 0, true) end
    elseif r.max then
        tt:AddLine(r.rank .. " / " .. r.max, 1, 1, 1)
        if r.weapon and r.rank < r.max then
            tt:AddLine(L["%d below the most for their level"]:format(r.max - r.rank), 1, 0.82, 0)
        end
    end
end

local function FillSkills(page, key, c)
    local sections, unread = ns.SkillSections(c)
    local entries = {}
    for _, s in ipairs(sections) do
        entries[#entries + 1] = { head = s.name }
        for _, r in ipairs(s.rows) do
            local e = { label = r.name, row = r, tip = SkillTip }
            if r.untrained then
                e.grey, e.value, e.max = true, 0, 1
                e.text = GREY .. (r.at and L["at level %d"]:format(r.at) or L["Not trained"]) .. "|r"
            else
                e.value, e.max = r.rank, r.max or r.rank
                e.text = r.max and (r.rank .. " / " .. r.max) or tostring(r.rank)
            end
            entries[#entries + 1] = e
        end
    end
    if unread then
        entries[#entries + 1] = { head = L["Weapon skills"] }
        entries[#entries + 1] = { label = GREY .. L["Not read yet: log in on %s once."]:format(c.name or key) .. "|r", none = true }
    end
    SetEntries(page.list, entries, L["%s has no skills recorded yet."]:format(c.name or key), page.key == key)
    page.key = key
end

---------------------------------------------------------------------------
-- Reputation
---------------------------------------------------------------------------
local function RepTip(tt, e)
    local r = e.row
    tt:AddLine(r.name, 1, 1, 1)
    local label = "|cff" .. r.colour .. r.label .. "|r"
    tt:AddLine(label)
    if r.level < 8 then tt:AddLine((r.value - r.low) .. " / " .. (r.high - r.low), 1, 1, 1) end
end

local function Hex(hex, from)
    return tonumber(hex:sub(from, from + 1), 16) / 255
end

local function FillReputation(page, key, c)
    local entries = {}
    for _, r in ipairs(ns.ReputationRows(c)) do
        local e = { label = r.name, row = r, tip = RepTip, r = Hex(r.colour, 1), g = Hex(r.colour, 3), b = Hex(r.colour, 5) }
        if r.level < 8 then
            e.value, e.max = r.value - r.low, r.high - r.low
            e.text = r.label .. "  " .. (r.value - r.low) .. " / " .. (r.high - r.low)
        else
            e.value, e.max, e.text = 1, 1, r.label
        end
        entries[#entries + 1] = e
    end
    SetEntries(page.list, entries, L["%s has no reputation recorded yet."]:format(c.name or key), page.key == key)
    page.key = key
end

---------------------------------------------------------------------------
-- Character: what they wear, as the game's character page lays it out, and the facts
-- between the two columns of slots.
---------------------------------------------------------------------------
local LOW_DURABILITY = 20
local SLOT_NAMES = {
    [1] = "HeadSlot", [2] = "NeckSlot", [3] = "ShoulderSlot", [4] = "ShirtSlot", [5] = "ChestSlot",
    [6] = "WaistSlot", [7] = "LegsSlot", [8] = "FeetSlot", [9] = "WristSlot", [10] = "HandsSlot",
    [11] = "Finger0Slot", [12] = "Finger1Slot", [13] = "Trinket0Slot", [14] = "Trinket1Slot",
    [15] = "BackSlot", [16] = "MainHandSlot", [17] = "SecondaryHandSlot", [18] = "RangedSlot", [19] = "TabardSlot",
}
local LEFT = { 1, 2, 3, 15, 5, 4, 19, 9 }
local RIGHT = { 10, 6, 7, 8, 11, 12, 13, 14 }
local BOTTOM = { 16, 17, 18 }
local SLOT, SLOT_GAP, NAME_W = 36, 44, 140
local FACT_LINES = 18
local LABEL_W = 104 -- a fact's label; its value has the rest of the line
local TICK = 60     -- seconds between refills of an open Character page

-- A fact cut short shows whole on hover.
local function FactEnter(self)
    if not (self.value:IsTruncated() or self.label:IsTruncated()) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.label:GetText())
    GameTooltip:AddLine(self.value:GetText(), 1, 1, 1, true)
    GameTooltip:Show()
end

local function SlotEnter(b)
    if not b.link then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(b.link)
    GameTooltip:Show()
end

local function SlotClick(b)
    -- Shift-click links the item in chat, as the game's own panels do.
    if b.link and IsModifiedClick() then HandleModifiedItemClick(b.link) end
end

local function MakeSlot(page, slot, x, y, nameSide)
    local b = CreateFrame("Button", nil, page)
    b:SetSize(SLOT, SLOT)
    b:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)
    ns.SkinItemSlot(b)
    if nameSide then
        b.name = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        ns.SkinText(b.name)
        b.name:SetWidth(NAME_W)
        b.name:SetWordWrap(false)
        if nameSide == "RIGHT" then
            b.name:SetPoint("LEFT", b, "RIGHT", 6, 0)
            b.name:SetJustifyH("LEFT")
        else
            b.name:SetPoint("RIGHT", b, "LEFT", -6, 0)
            b.name:SetJustifyH("RIGHT")
        end
    end
    local ok, _, emptyTexture = pcall(GetInventorySlotInfo, SLOT_NAMES[slot])
    b.emptyArt = ok and emptyTexture or nil
    b.slot = slot
    b:SetScript("OnEnter", SlotEnter)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", SlotClick)
    page.slots[slot] = b
end

local function BuildCharacter(page)
    page.slots = {}
    local top = TOP - 6
    for i, slot in ipairs(LEFT) do MakeSlot(page, slot, 16, top - (i - 1) * SLOT_GAP, "RIGHT") end
    for i, slot in ipairs(RIGHT) do MakeSlot(page, slot, WIDTH - 16 - SLOT, top - (i - 1) * SLOT_GAP, "LEFT") end
    for i, slot in ipairs(BOTTOM) do
        MakeSlot(page, slot, WIDTH / 2 - (SLOT * 3 + 10 * 2) / 2 + (i - 1) * (SLOT + 10), top - 8 * SLOT_GAP - 6)
    end
    -- The facts: a label and its value per line, between the two columns of names, each in
    -- a space of its own so a long value (a hearthstone place in another language) is cut
    -- short rather than running into the label or the gear names; hovering shows it whole.
    local left = 16 + SLOT + 6 + NAME_W + 14
    local right = WIDTH - left
    page.facts = {}
    for i = 1, FACT_LINES do
        local y = top - 4 - (i - 1) * 19
        local label = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", page, "TOPLEFT", left, y)
        label:SetWidth(LABEL_W)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        local value = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        value:SetPoint("TOPRIGHT", page, "TOPLEFT", right, y)
        value:SetWidth(right - left - LABEL_W - 4)
        value:SetJustifyH("RIGHT")
        value:SetWordWrap(false)
        ns.SkinText(label)
        ns.SkinText(value)
        local hover = CreateFrame("Frame", nil, page)
        hover:SetPoint("TOPLEFT", page, "TOPLEFT", left, y + 2)
        hover:SetSize(right - left, 17)
        hover:SetScript("OnEnter", FactEnter)
        hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
        hover.label, hover.value = label, value
        page.facts[i] = { label, value, hover = hover }
    end
    page.empty = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    page.empty:SetPoint("BOTTOM", page, "BOTTOM", 0, 24)
    page.empty:SetText(GREY .. L["No gear recorded yet.\nLog in on this character once."] .. "|r")
    ns.SkinText(page.empty)
end

-- While the Character page shows, its times (rested, hearthstone, played, last seen) move
-- on: refilled each minute, one timer at a time, none once it's closed or left.
local ticking = false
local function Tick()
    ticking = false
    if ns.CharacterWindowShown() == "character" then ns.CharacterWindowChanged() end
end

local function FillCharacter(page, key, c)
    if not ticking and C_Timer then
        ticking = true
        C_Timer.After(TICK, Tick)
    end
    local gear = c.gear
    page.empty:SetShown(not gear)
    for slot, b in pairs(page.slots) do
        local link = gear and gear[slot]
        b.link = link
        local id, icon, _
        if link then id, _, _, _, icon = GetItemInfoInstant(link) end
        if icon then
            b.icon:SetTexture(icon)
            ns.SlotQuality(b, id and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id))
        elseif not ns.SlotEmpty(b, b.emptyArt) then
            b.icon:SetTexture(b.emptyArt)
        end
        local pct = c.duraSlots and c.duraSlots[slot]
        -- Nearly broken items are tinted red, as on the game's own panel.
        if pct and pct < LOW_DURABILITY then b.icon:SetVertexColor(1, 0.3, 0.3) else b.icon:SetVertexColor(1, 1, 1) end
        if b.name then b.name:SetText(link and ns.LinkName(link) or "") end
    end
    local facts = ns.CharacterFacts(key, c, time())
    for i, line in ipairs(page.facts) do
        local f = facts[i]
        line[1]:SetText(f and f[1] or "")
        line[2]:SetText(f and f[2] or "")
    end
end

---------------------------------------------------------------------------
-- The pages, in tab order, for Recipes.lua's window.
---------------------------------------------------------------------------
local function ClassIcon(c)
    local class = type(c.class) == "string" and c.class or ""
    if class == "" then return QUESTION end
    return "Interface\\Icons\\ClassIcon_" .. class:sub(1, 1) .. class:sub(2):lower()
end

ns.SHEETS = {
    { id = "character", label = L["Character"], icon = ClassIcon,
        title = function(key, c) return ns.ColoredName(key, c) end,
        build = BuildCharacter, fill = FillCharacter },
    { id = "reputation", label = L["Reputation"], icon = function() return "Interface\\Icons\\Achievement_Reputation_01" end,
        title = function() return L["Reputation"] end,
        build = function(page) MakeList(page) end, fill = FillReputation },
    { id = "skills", label = L["Skills"], icon = function() return "Interface\\Icons\\INV_Sword_04" end,
        title = function() return L["Skills"] end,
        build = function(page) MakeList(page) end, fill = FillSkills },
}
