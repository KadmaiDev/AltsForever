-- Alts Forever gear: records what each character is wearing (item links per slot, so
-- suffixes and enchants survive) and durability, shown on the character window's
-- Character page (Sheets.lua), opened by clicking a character in the overview.
local _, ns = ...
if ns.disabled then return end -- another copy of Alts Forever is running (Core.lua)
local L = ns.L

local floor, pairs, wipe = math.floor, pairs, wipe
local issecretvalue = issecretvalue or function() return false end
local GetInventoryItemLink, GetInventoryItemDurability = GetInventoryItemLink, GetInventoryItemDurability
local GetInventoryItemID = GetInventoryItemID
local GetItemInfoInstant = C_Item.GetItemInfoInstant

local GREY = "|cff9d9d9d"
local LOW_DURABILITY = 20

-- The slots read (Sheets.lua lays them out, with the names GetInventorySlotInfo knows).
local SLOT_NAMES = {
    [1] = "HeadSlot", [2] = "NeckSlot", [3] = "ShoulderSlot", [4] = "ShirtSlot", [5] = "ChestSlot",
    [6] = "WaistSlot", [7] = "LegsSlot", [8] = "FeetSlot", [9] = "WristSlot", [10] = "HandsSlot",
    [11] = "Finger0Slot", [12] = "Finger1Slot", [13] = "Trinket0Slot", [14] = "Trinket1Slot",
    [15] = "BackSlot", [16] = "MainHandSlot", [17] = "SecondaryHandSlot", [18] = "RangedSlot", [19] = "TabardSlot",
}

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------
-- c.gear = { [slot] = itemLink }, c.dura = lowest durability % of anything worn,
-- c.duraSlots = { [slot] = % } for items below 100% only.
--
-- Just after login the game may know an item is in a slot (GetInventoryItemID) before
-- it can give its link, or know nothing about the equipment yet at all. Neither may
-- wipe what was recorded before, so those slots keep their old link and this returns
-- true to ask for another try shortly. The second value is true if any slot's link
-- changed (durability alone doesn't count), for upgrades, which depend only on the links.
function ns.ScanGear(c)
    local gear = c.gear or {}
    local incomplete, anything, changed = false, false, c.gear == nil
    for slot in pairs(SLOT_NAMES) do
        if GetInventoryItemID("player", slot) then anything = true break end
    end
    if not anything and next(gear) then return true, false end

    for slot in pairs(SLOT_NAMES) do
        local link = GetInventoryItemLink("player", slot)
        if not issecretvalue(link) and link then
            if gear[slot] ~= link then gear[slot], changed = link, true end
        elseif GetInventoryItemID("player", slot) then
            incomplete = true -- item there, link not ready: keep the old one
        elseif gear[slot] ~= nil then
            gear[slot], changed = nil, true
        end
    end
    c.gear = gear

    local low = c.duraSlots or {}
    wipe(low)
    local lowest
    for slot in pairs(SLOT_NAMES) do
        local cur, max = GetInventoryItemDurability(slot)
        if not issecretvalue(cur) and not issecretvalue(max) and cur and max and max > 0 then
            local pct = floor(cur * 100 / max)
            if pct < 100 then low[slot] = pct end
            if not lowest or pct < lowest then lowest = pct end
        end
    end
    c.duraSlots = low
    if lowest or not incomplete then c.dura = lowest end
    return incomplete, changed
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

-- The gear is shown on the character window's Character page (Sheets.lua). Clicking the
-- same character again closes it; with `beside` (the search), next to that window.
function ns.ShowGear(key, beside, side)
    return ns.ShowCharacter(key, "character", nil, false, beside, side)
end

function ns.StartGear()
    local char = ns.char
    -- Retries in a row while item links are still loading, and whether one is due: one
    -- timer at a time, however many equipment and durability events come meanwhile.
    local retries, waiting = 0, false
    local Retry
    local function Scan()
        -- Retry every 2 seconds, up to 5 times in a row, while item links are still loading.
        local incomplete, changed = ns.ScanGear(char)
        if not incomplete then
            retries = 0
        elseif not waiting and retries < 5 and C_Timer then
            retries, waiting = retries + 1, true
            C_Timer.After(2, Retry)
        end
        -- Upgrades depend on the links only, not on durability ticks.
        if changed and ns.UpgradesChanged then ns.UpgradesChanged() end
        if ns.CharacterWindowChanged then ns.CharacterWindowChanged() end
    end
    Retry = function()
        waiting = false
        Scan()
    end
    -- Not at logout: by then the game may already report empty slots.
    ns.On("PLAYER_EQUIPMENT_CHANGED", Scan)
    ns.On("UPDATE_INVENTORY_DURABILITY", Scan)
    Scan()
end
