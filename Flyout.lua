-- Alts Forever: upgrades your characters can craft, under the game's equipment flyout
-- (hold Alt over a slot on the character sheet). The flyout lists what's in your bags;
-- below it, a row of what you or your alts can craft that would be an upgrade in that
-- slot (Upgrades.lua picks them). It's a frame of our own anchored to the flyout: nothing
-- is added to Blizzard's flyout, whose buttons equip items.
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

function ns.StartFlyout()
    if type(EquipmentFlyout_Show) ~= "function" or not EquipmentFlyoutFrame then return end
    hooksecurefunc("EquipmentFlyout_Show", OnFlyout)
    EquipmentFlyoutFrame:HookScript("OnHide", Hide)
end
