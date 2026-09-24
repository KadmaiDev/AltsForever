-- Alts Forever scanner: keeps the current character's bags, bank and equipped items up to date.
-- Stores only itemID -> count, and refills the same tables so scans allocate nothing.
local _, ns = ...

local wipe, pcall = wipe, pcall
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
for slot = INVSLOT_FIRST_EQUIPPED or 1, INVSLOT_LAST_EQUIPPED or 19 do
    EQUIP_SLOTS[#EQUIP_SLOTS + 1] = slot
end
for _, name in ipairs({ "Bag_1", "Bag_2", "Bag_3", "Bag_4", "ReagentBag" }) do
    local bag = BagIndex[name]
    local ok, invSlot = pcall(C_Container.ContainerIDToInventoryID, bag)
    if bag and ok and invSlot then EQUIP_SLOTS[#EQUIP_SLOTS + 1] = invSlot end
end

function ns.ScanContainers(bags, out)
    wipe(out)
    for i = 1, #bags do
        local bag = bags[i]
        for slot = 1, GetContainerNumSlots(bag) or 0 do
            local id, count = ReadSlot(bag, slot)
            -- A secret value would break the whole SavedVariables write, and even
            -- testing one for truth throws, so check before anything else.
            if id and not issecretvalue(count) and count then
                out[id] = (out[id] or 0) + count
            end
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

function ns.StartScanner()
    local char = ns.char
    local bagsDirty, bankDirty, bankOpen = false, false, false

    local function ScanBags()
        bagsDirty = false
        ns.ScanContainers(BAGS, char.bags)
        ns.version = ns.version + 1
    end

    -- Bank contents can only be read while the bank is open; outside that the tabs
    -- can report as empty, which must not overwrite what we saw last time.
    local function ScanBank()
        bankDirty = false
        char.bank = char.bank or {}
        ns.ScanContainers(BANK_BAGS, char.bank)
        ns.version = ns.version + 1
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
