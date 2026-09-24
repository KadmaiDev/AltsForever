-- Alts Forever gear: records what each character is wearing (item links per slot, so
-- suffixes and enchants survive) and durability, and shows it in a character-sheet
-- style panel opened by clicking a character in the overview.
local _, ns = ...

local floor, pairs, wipe = math.floor, pairs, wipe
local issecretvalue = issecretvalue or function() return false end
local GetInventoryItemLink, GetInventoryItemDurability = GetInventoryItemLink, GetInventoryItemDurability
local GetInventoryItemID = GetInventoryItemID
local GetItemInfoInstant = C_Item.GetItemInfoInstant

local GREY = "|cff9d9d9d"
local LOW_DURABILITY = 20
local PANEL_WIDTH = 440

-- Slot IDs with the names GetInventorySlotInfo knows them by (for the empty-slot art),
-- laid out like the game's character panel.
local SLOT_NAMES = {
    [1] = "HeadSlot", [2] = "NeckSlot", [3] = "ShoulderSlot", [4] = "ShirtSlot", [5] = "ChestSlot",
    [6] = "WaistSlot", [7] = "LegsSlot", [8] = "FeetSlot", [9] = "WristSlot", [10] = "HandsSlot",
    [11] = "Finger0Slot", [12] = "Finger1Slot", [13] = "Trinket0Slot", [14] = "Trinket1Slot",
    [15] = "BackSlot", [16] = "MainHandSlot", [17] = "SecondaryHandSlot", [18] = "RangedSlot", [19] = "TabardSlot",
}
local LEFT = { 1, 2, 3, 15, 5, 4, 19, 9 }
local RIGHT = { 10, 6, 7, 8, 11, 12, 13, 14 }
local BOTTOM = { 16, 17, 18 }

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------
-- c.gear = { [slot] = itemLink }, c.dura = lowest durability % of anything worn,
-- c.duraSlots = { [slot] = % } for items below 100% only.
--
-- Just after login the game may know an item is in a slot (GetInventoryItemID) before
-- it can give its link, or know nothing about the equipment yet at all. Neither may
-- wipe what was recorded before, so those slots keep their old link and this returns
-- true to ask for another try shortly.
function ns.ScanGear(c)
    local gear = c.gear or {}
    local incomplete, anything = false, false
    for slot in pairs(SLOT_NAMES) do
        if GetInventoryItemID("player", slot) then anything = true break end
    end
    if not anything and next(gear) then return true end

    for slot in pairs(SLOT_NAMES) do
        local link = GetInventoryItemLink("player", slot)
        if link and not issecretvalue(link) then
            gear[slot] = link
        elseif GetInventoryItemID("player", slot) then
            incomplete = true -- item there, link not ready: keep the old one
        else
            gear[slot] = nil
        end
    end
    c.gear = gear

    local low = c.duraSlots or {}
    wipe(low)
    local lowest
    for slot in pairs(SLOT_NAMES) do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 and not issecretvalue(cur) then
            local pct = floor(cur * 100 / max)
            if pct < 100 then low[slot] = pct end
            if not lowest or pct < lowest then lowest = pct end
        end
    end
    c.duraSlots = low
    if lowest or not incomplete then c.dura = lowest end
    return incomplete
end

-- An item link's name in its quality colour, without the [brackets].
function ns.LinkName(link)
    local color, name = link:match("^(.-)|H.-|h%[(.-)%]|h")
    if not name then return link end
    return color .. name .. "|r"
end

function ns.DurabilityText(pct)
    if not pct then return GREY .. "-|r" end
    local color = pct < LOW_DURABILITY and "|cffff2020" or pct < 50 and "|cffff8000" or "|cffffffff"
    return color .. pct .. "%|r"
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
local panel, buttons, shownKey

local function Hover(button)
    if not button.link then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(button.link)
    GameTooltip:Show()
end

local function Click(button)
    -- Shift-click links the item in chat, like the game's own panels.
    if button.link and IsModifiedClick() then HandleModifiedItemClick(button.link) end
end

local function CreateSlot(slot, x, y, nameSide)
    local b = CreateFrame("Button", nil, panel)
    b:SetSize(36, 36)
    b:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)
    if nameSide then
        b.name = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.name:SetWidth(150)
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
    b.empty = ok and emptyTexture or nil
    b.slot = slot
    b:SetScript("OnEnter", Hover)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", Click)
    buttons[slot] = b
end

local function CreatePanel()
    local ok, f = pcall(CreateFrame, "Frame", "AltsForeverGearFrame", UIParent, "BasicFrameTemplateWithInset")
    if not ok then f = CreateFrame("Frame", "AltsForeverGearFrame", UIParent, "BackdropTemplate") end
    panel = f
    buttons = {}
    f:SetSize(PANEL_WIDTH, 450)
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f.title = f.TitleText or f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if not f.TitleText then f.title:SetPoint("TOP", 0, -6) end

    for i, slot in ipairs(LEFT) do CreateSlot(slot, 14, -34 - (i - 1) * 42, "RIGHT") end
    for i, slot in ipairs(RIGHT) do CreateSlot(slot, PANEL_WIDTH - 14 - 36, -34 - (i - 1) * 42, "LEFT") end
    for i, slot in ipairs(BOTTOM) do CreateSlot(slot, PANEL_WIDTH / 2 - 64 + (i - 1) * 46, -34 - 8 * 42 - 4) end

    f.footer = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.footer:SetPoint("BOTTOM", f, "BOTTOM", 0, 14)
    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.empty:SetPoint("CENTER")
    f.empty:SetText(GREY .. "No gear recorded yet.\nLog in on this character once.|r")

    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "AltsForeverGearFrame" end
    f:Hide()
end

local function Fill()
    local c = ns.db.chars[shownKey]
    if not c then return panel:Hide() end
    local gear = c.gear
    panel.title:SetText(ns.ColoredName(shownKey, c) .. (c.ilvl and (GREY .. "  ilvl " .. c.ilvl .. "|r") or ""))
    panel.empty:SetShown(not gear)
    for slot, b in pairs(buttons) do
        local link = gear and gear[slot]
        b.link = link
        local icon = link and select(5, GetItemInfoInstant(link))
        b.icon:SetTexture(icon or b.empty)
        local pct = c.duraSlots and c.duraSlots[slot]
        -- Nearly broken items are tinted red, as on the game's own panel.
        if pct and pct < LOW_DURABILITY then b.icon:SetVertexColor(1, 0.3, 0.3) else b.icon:SetVertexColor(1, 1, 1) end
        if b.name then b.name:SetText(link and ns.LinkName(link) or "") end
    end
    panel.footer:SetText(gear and ("Lowest durability: " .. ns.DurabilityText(c.dura)) or "")
end

-- Opens the gear panel for a character, beside the overview if it's open; clicking
-- the same character again closes it.
function ns.ShowGear(key)
    if not panel then CreatePanel() end
    if panel:IsShown() and shownKey == key then return panel:Hide() end
    shownKey = key
    panel:ClearAllPoints()
    if AltsForeverFrame and AltsForeverFrame:IsShown() then
        panel:SetPoint("TOPLEFT", AltsForeverFrame, "TOPRIGHT", 4, 0)
    else
        panel:SetPoint("CENTER")
    end
    Fill()
    panel:Show()
end

function ns.StartGear()
    local char = ns.char
    local retries = 0
    local function Scan()
        -- Retry every 2 seconds, up to 5 times, while item links are still loading.
        if ns.ScanGear(char) and retries < 5 and C_Timer then
            retries = retries + 1
            C_Timer.After(2, Scan)
        end
        if panel and panel:IsShown() and shownKey == ns.charKey then Fill() end
    end
    -- Not at logout: by then the game may already report empty slots.
    ns.On("PLAYER_EQUIPMENT_CHANGED", Scan)
    ns.On("UPDATE_INVENTORY_DURABILITY", Scan)
    Scan()
end
