-- Alts Forever: upgrades your characters can craft, on the character sheet.
--  * Under the game's equipment flyout (hold Alt over a slot): the flyout lists what's in
--    your bags; below it, a row of what you or your alts can craft that would be an
--    upgrade in that slot (Upgrades.lua picks them). A frame of our own anchored to the
--    flyout: nothing is added to Blizzard's flyout, whose buttons equip items.
--  * On the slots themselves: a small anvil where one can be crafted that you can wear now
--    and that binds when equipped (so whoever makes it can mail it), and hovering the slot
--    lists the best few (owner, 2026-10-16).
local _, ns = ...
if ns.disabled then return end -- another copy of Alts Forever is running (Core.lua)
local L = ns.L

local floor, min, max = math.floor, math.min, math.max
local issecretvalue = issecretvalue or function() return false end

local MAX = 10     -- items shown
local PER_ROW = 5  -- as many as a row of the game's flyout
local SIZE, GAP, PAD, TITLE = 37, 4, 6, 18
local BORDER = "Interface\\Common\\WhiteIconFrame"

local strip
local buttons = {}
local list = {}
local shownKey -- what the strip shows now (slot and everything the list depends on)
local retrying = false

local function Enter(b)
    local e = b.entry
    if not e then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(e.link)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Crafted by %s (%s)"]:format(ns.ListName(e.key, ns.db.chars[e.key]), e.prof), 1, 0.82, 0)
    GameTooltip:Show()
end

local function Click(b)
    -- Shift-click links the item in chat, like the game's own buttons.
    if b.entry and IsModifiedClick() then HandleModifiedItemClick(b.entry.link) end
end

local function Button(i)
    local b = buttons[i]
    if b then return b end
    b = CreateFrame("Button", nil, strip)
    b:SetSize(SIZE, SIZE)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetAllPoints()
    b.border:SetTexture(BORDER)
    b.gain = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.gain:SetPoint("BOTTOMRIGHT", -2, 2)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)
    b:SetScript("OnEnter", Enter)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", Click)
    ns.SkinSlot(b)
    buttons[i] = b
    return b
end

local function Build()
    strip = CreateFrame("Frame", "AltsForeverCraftFlyout", UIParent)
    strip:SetFrameStrata(EquipmentFlyoutFrame:GetFrameStrata() or "HIGH")
    strip:SetFrameLevel((EquipmentFlyoutFrame:GetFrameLevel() or 0) + 5)
    local bg = strip:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.8)
    strip.title = strip:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    strip.title:SetPoint("TOPLEFT", PAD, -PAD + 1)
    strip.title:SetText(L["Your characters can craft"])
    ns.SkinText(strip.title)
    strip:Hide()
end

local function Hide()
    shownKey = nil
    if strip then strip:Hide() end
end

local function Fill(slot)
    if not ns.UpgradesOn() then return Hide() end
    -- The flyout can be shown again and again while it's open: work the list out only
    -- when the slot, your gear, recipes or level changed.
    local key = slot .. ":" .. ns.UpgradesVersion() .. ":" .. (ns.craftVersion or 0) .. ":" .. (ns.char.level or 0)
    if key == shownKey and strip and strip:IsShown() then return end
    local pending
    list, pending = ns.CraftableUpgrades(slot, list)
    shownKey = not pending and key or nil
    if pending and not retrying and C_Timer and C_Timer.After then
        -- Item data on its way: once more in a second.
        retrying = true
        C_Timer.After(1, function()
            retrying = false
            if EquipmentFlyoutFrame:IsShown() and strip and strip.slot == slot then Fill(slot) end
        end)
    end
    local n = min(#list, MAX)
    if n == 0 then return Hide() end
    if not strip then Build() end
    strip.slot = slot
    for i = 1, n do
        local e, b = list[i], Button(i)
        b.entry = e
        b.icon:SetTexture(C_Item.GetItemIconByID(e.id))
        b.icon:SetDesaturated(e.at ~= nil) -- not until a level or few from now
        local q = C_Item.GetItemQualityByID(e.id)
        local color = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
        if color then b.border:SetVertexColor(color.r, color.g, color.b) end
        b.border:SetShown(color ~= nil)
        b.gain:SetText(e.gain ~= math.huge and "+" .. floor(e.gain + 0.5) .. "%" or "")
        b:ClearAllPoints()
        local col, row = (i - 1) % PER_ROW, floor((i - 1) / PER_ROW)
        b:SetPoint("TOPLEFT", PAD + col * (SIZE + GAP), -(PAD + TITLE + row * (SIZE + GAP)))
        b:Show()
    end
    for i = n + 1, #buttons do
        buttons[i].entry = nil
        buttons[i]:Hide()
    end
    local cols, rows = min(n, PER_ROW), floor((n - 1) / PER_ROW) + 1
    local titleWidth = strip.title:GetStringWidth()
    if type(titleWidth) ~= "number" or issecretvalue(titleWidth) then titleWidth = 0 end
    strip:SetSize(max(PAD * 2 + cols * (SIZE + GAP) - GAP, titleWidth + PAD * 2),
        PAD * 2 + TITLE + rows * (SIZE + GAP) - GAP)
    strip:ClearAllPoints()
    strip:SetPoint("TOPLEFT", EquipmentFlyoutFrame.buttonFrame or EquipmentFlyoutFrame, "BOTTOMLEFT", 0, -2)
    strip:Show()
end

-- The flyout opened (or was refreshed) for a slot button: its ID is the inventory slot.
local function OnFlyout(itemButton)
    local slot = type(itemButton) == "table" and itemButton.GetID and itemButton:GetID()
    if issecretvalue(slot) then return end
    if type(slot) ~= "number" or slot < 1 or slot > 19 or not ns.char then return Hide() end
    Fill(slot)
end

---------------------------------------------------------------------------
-- The slots on the character sheet
---------------------------------------------------------------------------
local SLOT_NAMES = { "Head", "Neck", "Shoulder", "Back", "Chest", "Wrist", "Hands", "Waist", "Legs", "Feet",
    "Finger0", "Finger1", "Trinket0", "Trinket1", "MainHand", "SecondaryHand", "Ranged" }
local MARK = "Interface\\Minimap\\Tracking\\Repair" -- the anvil
local SHOWN_IN_TOOLTIP = 3
local marks = {}  -- our anvil texture per slot button
local bySlot = {} -- slot -> wearable, bind-on-equip craftable upgrades, best first
local all = {}
local dollKey, dollRetry = nil, false

local function Mark(b)
    local m = b:CreateTexture(nil, "OVERLAY", nil, 7)
    m:SetSize(16, 16)
    m:SetPoint("TOPRIGHT", b, "TOPRIGHT", 3, 3)
    m:SetTexture(MARK)
    marks[b] = m
    return m
end

local function RefreshDoll()
    if not (ns.char and PaperDollFrame and PaperDollFrame:IsVisible()) then return end
    local on = ns.UpgradesOn()
    local key = ns.UpgradesVersion() .. ":" .. (ns.craftVersion or 0) .. ":" .. (ns.char.level or 0) .. ":" .. tostring(on)
    if key == dollKey then return end
    local pending = false
    wipe(bySlot)
    if on then
        all, pending = ns.CraftableUpgrades(nil, all)
        for _, e in ipairs(all) do
            if e.boe and not e.at and e.slot then
                local t = bySlot[e.slot]
                if not t then
                    t = {}
                    bySlot[e.slot] = t
                end
                t[#t + 1] = e
            end
        end
    end
    dollKey = not pending and key or nil
    for _, name in ipairs(SLOT_NAMES) do
        local b = _G["Character" .. name .. "Slot"]
        local slot = b and b.GetID and b:GetID()
        if type(slot) == "number" then
            local has = bySlot[slot] ~= nil
            local m = marks[b] or (has and Mark(b))
            if m then m:SetShown(has) end
        end
    end
    if pending and not dollRetry and C_Timer and C_Timer.After then
        dollRetry = true
        C_Timer.After(1, function()
            dollRetry = false
            RefreshDoll()
        end)
    end
end
ns.CharacterSheetChanged = RefreshDoll

-- Hovering a marked slot: the best few under the game's own tooltip.
local function SlotEnter(b)
    local slot = b:GetID()
    local list = type(slot) == "number" and bySlot[slot]
    if not list or not ns.UpgradesOn() or GameTooltip:GetOwner() ~= b then return end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Your characters can craft"], 1, 0.82, 0)
    for i = 1, min(#list, SHOWN_IN_TOOLTIP) do
        local e = list[i]
        local gain = e.gain ~= math.huge and "+" .. floor(e.gain + 0.5) .. "%" or (e.empty and L["empty slot"] or L["big upgrade"])
        GameTooltip:AddDoubleLine(e.link, "|cff20ff20" .. gain .. "|r · " .. ns.ListName(e.key, ns.db.chars[e.key]), 1, 1, 1, 1, 1, 1)
    end
    GameTooltip:Show()
end

function ns.StartFlyout()
    if type(EquipmentFlyout_Show) == "function" and EquipmentFlyoutFrame then
        hooksecurefunc("EquipmentFlyout_Show", OnFlyout)
        EquipmentFlyoutFrame:HookScript("OnHide", Hide)
    end
    if PaperDollFrame then
        PaperDollFrame:HookScript("OnShow", RefreshDoll)
        -- The slots' own OnEnter scripts were set before we loaded, so hook each button.
        for _, name in ipairs(SLOT_NAMES) do
            local b = _G["Character" .. name .. "Slot"]
            if b and b.HookScript then b:HookScript("OnEnter", SlotEnter) end
        end
    end
end
