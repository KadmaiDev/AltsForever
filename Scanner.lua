-- Alts Forever scanner: keeps the current character's bags, bank and equipped items up to date.
-- Stores itemID -> count for tooltips, and each bag's and bank tab's slots for the bags
-- window (Bags.lua), refilling the same tables so scans allocate nothing.
local _, ns = ...
if ns.disabled then return end -- another copy of Alts Forever is running (Core.lua)

local wipe, pcall, time = wipe, pcall, time
local issecretvalue = issecretvalue or function() return false end
local C_Container, C_Item = C_Container, C_Item
local GetContainerNumSlots = C_Container.GetContainerNumSlots
local GetContainerItemID = C_Container.GetContainerItemID
local GetInventoryItemID = GetInventoryItemID

-- Returns itemID, stackCount for a bag slot. Prefers one reused ItemLocation over
-- GetContainerItemInfo, which builds a new table for every slot.
local ReadSlot
if ItemLocation and ItemLocation.CreateEmpty and C_Item.GetStackCount then
    local loc = ItemLocation:CreateEmpty()
    local GetStackCount = C_Item.GetStackCount
    ReadSlot = function(bag, slot)
        local id = GetContainerItemID(bag, slot)
        if id then
            loc:SetBagAndSlot(bag, slot)
            return id, GetStackCount(loc)
        end
    end
else
    local GetContainerItemInfo = C_Container.GetContainerItemInfo
    ReadSlot = function(bag, slot)
        local info = GetContainerItemInfo(bag, slot)
        if info then return info.itemID, info.stackCount end
    end
end

-- Bags carried on the character. Keyring and ReagentBag only if this client has them.
local BAGS, BAG_SET = {}, {}
local BagIndex = Enum.BagIndex
for _, name in ipairs({ "Backpack", "Bag_1", "Bag_2", "Bag_3", "Bag_4", "ReagentBag", "Keyring" }) do
    local bag = BagIndex[name]
    if bag then
        BAGS[#BAGS + 1] = bag
        BAG_SET[bag] = true
    end
end

-- Character bank tabs. Unpurchased tabs report 0 slots, so listing all of them is safe.
local BANK_BAGS, BANK_SET = {}, {}
for i = 1, 9 do
    local bag = BagIndex["CharacterBankTab_" .. i]
    if bag then
        BANK_BAGS[#BANK_BAGS + 1] = bag
        BANK_SET[bag] = true
    end
end

-- Equipped gear, plus the bags themselves (they sit in inventory slots too).
local EQUIP_SLOTS = {}
local BAG_INV = {} -- bag -> the inventory slot its bag item sits in
for slot = INVSLOT_FIRST_EQUIPPED or 1, INVSLOT_LAST_EQUIPPED or 19 do
    EQUIP_SLOTS[#EQUIP_SLOTS + 1] = slot
end
for _, name in ipairs({ "Bag_1", "Bag_2", "Bag_3", "Bag_4", "ReagentBag" }) do
    local bag = BagIndex[name]
    local ok, invSlot = pcall(C_Container.ContainerIDToInventoryID, bag)
    if bag and ok and invSlot then
        EQUIP_SLOTS[#EQUIP_SLOTS + 1] = invSlot
        BAG_INV[bag] = invSlot
    end
end

-- A slot in the saved layout: one number, itemID * 1000 + stack size (Classic stacks
-- stay under 1000), or 0 when empty. Numbers only, so a layout costs no strings.
local STACK = 1000
function ns.SlotValue(id, count)
    if count >= STACK then count = STACK - 1 end
    return id * STACK + count
end
function ns.SlotItem(value)
    if not value or value == 0 then return nil end
    return math.floor(value / STACK), value % STACK
end

-- Weapons and armour can carry what their item ID doesn't say: a random bonus ("Curved
-- Dagger of Intellect" is the plain Curved Dagger's ID; Forever links it as a bonus ID) or an
-- enchant. Their full link is kept for the bags window (a player's report, 2026-11-18: bank
-- items showed without their bonus). Only weapons and armour are read, and only links with
-- one of those are stored, so a scan of everything else costs what it did.
local GetContainerItemLink = C_Container.GetContainerItemLink
local GetItemInfoInstant = C_Item.GetItemInfoInstant
local WEAPON, ARMOR = 2, 4
local gear = {} -- itemID -> whether it's a weapon or armour (the answer never changes)
local function IsGear(id)
    local g = gear[id]
    if g == nil then
        local _, _, _, _, _, class = GetItemInfoInstant(id)
        if class == nil then return false end -- not known yet: asked again next scan
        g = class == WEAPON or class == ARMOR
        gear[id] = g
    end
    return g
end

-- The fields after "item:": the enchant (1st), the random suffix (6th) and how many bonus
-- IDs (12th). Seen in the owner's saves (2026-11-18): "item:6590::::::::36:1486:::1:12754"
-- (Battleforge Boots of the Defender: no suffix, one bonus ID), "item:9624:8486:..."
-- (enchanted), "item:6414::::::::37:1485::11:::" (plain).
local LINK_FIELDS = "item:%-?%d+:(%-?%d*):[^:]*:[^:]*:[^:]*:[^:]*:(%-?%d*):[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:(%d*)"
local function Set(v) return v ~= nil and v ~= "" and v ~= "0" end

-- The link if it says more than the item ID (an enchant, a random bonus), else nil.
function ns.SpecialLink(link)
    if issecretvalue(link) or type(link) ~= "string" then return nil end
    local enchant, suffix, bonuses = link:match(LINK_FIELDS)
    if Set(enchant) or Set(suffix) or Set(bonuses) then return link end
    return nil
end

-- Counts every item in the bags into out; with layout, also records each bag's slots
-- in layout[bag] (an array as long as the bag; a bag with no slots is removed), and
-- at index 0 the bag item itself, for its name in the bags window. With links, the full
-- link of each slot holding an item with a bonus or enchant: links[bag][slot] (a bag
-- without any has no table).
function ns.ScanContainers(bags, out, layout, links)
    wipe(out)
    for i = 1, #bags do
        local bag = bags[i]
        local size = GetContainerNumSlots(bag) or 0
        local slots
        if layout then
            slots = layout[bag]
            if size == 0 then
                layout[bag] = nil
            elseif not slots then
                slots = {}
                layout[bag] = slots
            end
        end
        local kept = links and links[bag]
        if kept then wipe(kept) end
        for slot = 1, size do
            local id, count = ReadSlot(bag, slot)
            -- A secret value would break the whole SavedVariables write, and even
            -- testing one for truth throws, so check before anything else.
            if id and not issecretvalue(count) and count then
                out[id] = (out[id] or 0) + count
                if slots then slots[slot] = ns.SlotValue(id, count) end
                if links and IsGear(id) then
                    local link = ns.SpecialLink(GetContainerItemLink(bag, slot))
                    if link then
                        kept = kept or links[bag] or {}
                        links[bag] = kept
                        kept[slot] = link
                    end
                end
            elseif slots then
                slots[slot] = 0
            end
        end
        if links and kept and next(kept) == nil then links[bag] = nil end
        -- The bag got smaller (swapped for a smaller one).
        if slots then
            local inv = BAG_INV[bag]
            if inv then slots[0] = GetInventoryItemID("player", inv) or slots[0] end
            for slot = #slots, size + 1, -1 do slots[slot] = nil end
        end
    end
end

function ns.ScanEquip(out)
    wipe(out)
    for i = 1, #EQUIP_SLOTS do
        local id = GetInventoryItemID("player", EQUIP_SLOTS[i])
        if id then out[id] = (out[id] or 0) + 1 end
    end
end

-- The bags window's lists, in display order (Bags.lua).
ns.CARRIED_BAGS, ns.BANK_TABS = BAGS, BANK_BAGS

function ns.StartScanner()
    local char = ns.char
    local bagsDirty, bankDirty, bankOpen = false, false, false

    -- Scans into the character's links table (one is only kept while it has any): an empty
    -- one waits here for the next scan, so scans with no links create nothing.
    local spareLinks = {}
    local function ScanInto(bags, out)
        local links = char.links or spareLinks
        ns.ScanContainers(bags, out, char.layout, links)
        if next(links) == nil then
            char.links, spareLinks = nil, links
        else
            char.links = links
            if links == spareLinks then spareLinks = {} end
        end
    end

    local function ScanBags()
        bagsDirty = false
        char.layout = char.layout or {}
        ScanInto(BAGS, char.bags)
        ns.version = ns.version + 1
        ns.BagsWindowChanged()
        if ns.RecipesChanged then ns.RecipesChanged() end -- how many they could make
        if ns.RefreshOverview then ns.RefreshOverview() end -- its Bags and Bank columns, if open
    end

    -- Bank contents can only be read while the bank is open; outside that the tabs
    -- can report as empty, which must not overwrite what we saw last time.
    local function ScanBank()
        bankDirty = false
        char.bank = char.bank or {}
        char.layout = char.layout or {}
        ScanInto(BANK_BAGS, char.bank)
        char.bankAt = time()
        ns.version = ns.version + 1
        ns.BagsWindowChanged()
        if ns.RecipesChanged then ns.RecipesChanged() end -- how many they could make
        if ns.RefreshOverview then ns.RefreshOverview() end -- its Bags and Bank columns, if open
    end

    local function BankOpened()
        if bankOpen then return end
        bankOpen = true
        ScanBank()
    end

    ns.On("BANKFRAME_OPENED", BankOpened)
    ns.On("BANKFRAME_CLOSED", function() bankOpen = false end)
    -- Newer clients announce the banker through the interaction manager too.
    local Banker = Enum.PlayerInteractionType and Enum.PlayerInteractionType.Banker
    if Banker then
        ns.On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(kind)
            if kind == Banker then BankOpened() end
        end)
        ns.On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(kind)
            if kind == Banker then bankOpen = false end
        end)
    end

    local function ScanEquip()
        ns.ScanEquip(char.equip)
        ns.version = ns.version + 1
    end

    -- BAG_UPDATE fires per bag, often many times at once; BAG_UPDATE_DELAYED fires
    -- once after the batch. Only rescan when one of our carried bags changed.
    ns.On("BAG_UPDATE", function(bag)
        if BAG_SET[bag] then
            bagsDirty = true
        elseif bankOpen and BANK_SET[bag] then
            bankDirty = true
        end
    end)
    ns.On("BAG_UPDATE_DELAYED", function()
        if bagsDirty then ScanBags() end
        if bankDirty and bankOpen then ScanBank() end
    end)
    ns.On("PLAYER_EQUIPMENT_CHANGED", ScanEquip)
    -- A bag was added, removed or swapped.
    ns.On("BAG_CONTAINER_UPDATE", function()
        ScanEquip()
        ScanBags()
    end)

    ScanBags()
    ScanEquip()
end
