-- Alts Forever: upgrades your characters can craft, on the character sheet. A small anvil
-- button sits just outside a slot (left of the left column, right of the right column,
-- below the weapons; the inner sides can hold a UI addon's stat text) when you or one of
-- your characters who can mail you can craft an upgrade for it that you can wear now and
-- that binds when equipped (owner, 2026-10-16), with the best one's chevrons on its corner
-- (minor, decent, major). Hover it for the best few; click it for
-- all of them as item buttons beside it. Upgrades.lua picks them (ns.CraftableUpgrades).
-- (Before, the list sat under the game's Alt-hover equipment flyout; the owner preferred
-- a button to click.)
local _, ns = ...
if ns.disabled then return end -- another copy of Alts Forever is running (Core.lua)
local L = ns.L

local floor, min, max = math.floor, math.min, math.max
local issecretvalue = issecretvalue or function() return false end

local MAX = 10     -- items in the panel
local PER_ROW = 5
local SIZE, GAP, PAD, TITLE = 37, 4, 6, 18
local BORDER = "Interface\\Common\\WhiteIconFrame"
local ANVIL = "Interface\\Minimap\\Tracking\\Repair"
local GLYPH = 18
local SHOWN_IN_TOOLTIP = 3

-- The character sheet's slot buttons, by the side of the sheet they're on.
local SIDES = {
    left = { "Head", "Neck", "Shoulder", "Back", "Chest", "Wrist" },
    right = { "Hands", "Waist", "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1" },
    bottom = { "MainHand", "SecondaryHand", "Ranged" },
}

local glyphs = {}  -- slot button -> our anvil button
local bySlot = {}  -- slot -> wearable, bind-on-equip craftable upgrades, best first
local all = {}
local dollKey, dollRetry = nil, false
local panel
local buttons = {}

local function GainText(e) return ns.GainLabel(e.gain, e.empty) end

---------------------------------------------------------------------------
-- The panel of item buttons
---------------------------------------------------------------------------
local function ItemEnter(b)
    local e = b.entry
    if not e then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(e.link)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Crafted by %s (%s)"]:format(ns.ListName(e.key, ns.db.chars[e.key]), e.prof), 1, 0.82, 0)
    GameTooltip:Show()
end

local function ItemClick(b)
    -- Shift-click links the item in chat, like the game's own buttons.
    if b.entry and IsModifiedClick() then HandleModifiedItemClick(b.entry.link) end
end

local function ItemButton(i)
    local b = buttons[i]
    if b then return b end
    b = CreateFrame("Button", nil, panel)
    b:SetSize(SIZE, SIZE)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetAllPoints()
    b.border:SetTexture(BORDER)
    b.tier = b:CreateTexture(nil, "OVERLAY", nil, 2)
    b.tier:SetSize(20, 20)
    b.tier:SetPoint("BOTTOMRIGHT", 3, -2)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)
    b:SetScript("OnEnter", ItemEnter)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", ItemClick)
    ns.SkinSlot(b)
    buttons[i] = b
    return b
end

local function BuildPanel()
    panel = CreateFrame("Frame", "AltsForeverCraftPanel", UIParent)
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.85)
    panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.title:SetPoint("TOPLEFT", PAD, -PAD + 1)
    panel.title:SetText(L["Your characters can craft"])
    ns.SkinText(panel.title)
    panel:Hide()
end

local function HidePanel()
    if panel then
        panel:Hide()
        panel.glyph = nil
    end
end

-- Shows the panel beside a glyph, outwards from the sheet; false if there's nothing.
local function ShowPanel(glyph)
    local list = bySlot[glyph.slot]
    local n = list and min(#list, MAX) or 0
    if n == 0 then return HidePanel() end
    if not panel then BuildPanel() end
    panel.glyph = glyph
    for i = 1, n do
        local e, b = list[i], ItemButton(i)
        b.entry = e
        b.icon:SetTexture(C_Item.GetItemIconByID(e.id))
        local q = C_Item.GetItemQualityByID(e.id)
        local color = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
        if color then b.border:SetVertexColor(color.r, color.g, color.b) end
        b.border:SetShown(color ~= nil)
        b.tier:SetTexture(ns.GainTexture(e.gain))
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
    local titleWidth = panel.title:GetStringWidth()
    if type(titleWidth) ~= "number" or issecretvalue(titleWidth) then titleWidth = 0 end
    panel:SetSize(max(PAD * 2 + cols * (SIZE + GAP) - GAP, titleWidth + PAD * 2),
        PAD * 2 + TITLE + rows * (SIZE + GAP) - GAP)
    panel:ClearAllPoints()
    if glyph.side == "left" then
        panel:SetPoint("TOPRIGHT", glyph, "TOPLEFT", -2, 0)
    elseif glyph.side == "right" then
        panel:SetPoint("TOPLEFT", glyph, "TOPRIGHT", 2, 0)
    else
        panel:SetPoint("TOP", glyph, "BOTTOM", 0, -2)
    end
    panel:Show()
end

---------------------------------------------------------------------------
-- The anvil buttons
---------------------------------------------------------------------------
local function GlyphEnter(g)
    local list = bySlot[g.slot]
    if not list then return end
    GameTooltip:SetOwner(g, g.side == "left" and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
    GameTooltip:AddLine(L["Your characters can craft"], 1, 0.82, 0)
    for i = 1, min(#list, SHOWN_IN_TOOLTIP) do
        local e = list[i]
        GameTooltip:AddDoubleLine(e.link, GainText(e) .. " · " .. ns.ListName(e.key, ns.db.chars[e.key]), 1, 1, 1, 1, 1, 1)
    end
    GameTooltip:AddLine(L["Click: show them"], 1, 1, 1)
    GameTooltip:Show()
end

local function GlyphClick(g)
    GameTooltip:Hide()
    if panel and panel:IsShown() and panel.glyph == g then return HidePanel() end
    ShowPanel(g)
end

local function Glyph(b, side)
    local g = glyphs[b]
    if g then return g end
    g = CreateFrame("Button", nil, b)
    g:SetSize(GLYPH, GLYPH)
    g:SetFrameLevel((b:GetFrameLevel() or 1) + 5)
    -- Beside a side column the anvil sits at the slot's top, with its chevrons under it:
    -- there's only an anvil's width between the left column and the window's edge.
    if side == "left" then
        g:SetPoint("TOPRIGHT", b, "TOPLEFT", -2, 1)
    elseif side == "right" then
        g:SetPoint("TOPLEFT", b, "TOPRIGHT", 2, 1)
    else
        g:SetPoint("TOP", b, "BOTTOM", 0, -2)
    end
    g.icon = g:CreateTexture(nil, "ARTWORK")
    g.icon:SetAllPoints()
    g.icon:SetTexture(ANVIL)
    -- The best upgrade's chevrons on the anvil's corner, so each slot can be judged at a glance.
    g.tier = g:CreateTexture(nil, "OVERLAY")
    g.tier:SetSize(18, 18)
    -- Under the anvil beside the side columns (on its corner they covered the item icon;
    -- beside it, they went past the window's edge); beside it under the weapons.
    if side == "bottom" then
        g.tier:SetPoint("LEFT", g, "RIGHT", -3, -2)
    else
        g.tier:SetPoint("TOP", g, "BOTTOM", 0, 3)
    end
    local hl = g:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture(ANVIL)
    hl:SetBlendMode("ADD")
    g.side = side
    g:SetScript("OnEnter", GlyphEnter)
    g:SetScript("OnLeave", function() GameTooltip:Hide() end)
    g:SetScript("OnClick", GlyphClick)
    glyphs[b] = g
    return g
end

---------------------------------------------------------------------------
-- Working out which slots get one
---------------------------------------------------------------------------
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
    for side, names in pairs(SIDES) do
        for _, name in ipairs(names) do
            local b = _G["Character" .. name .. "Slot"]
            local slot = b and b.GetID and b:GetID()
            if type(slot) == "number" and not issecretvalue(slot) then
                local has = bySlot[slot] ~= nil
                local g = glyphs[b] or (has and Glyph(b, side))
                if g then
                    g.slot = slot
                    g:SetShown(has)
                    if has then g.tier:SetTexture(ns.GainTexture(bySlot[slot][1].gain)) end -- best first
                end
            end
        end
    end
    -- The panel follows: its slot's list changed, or there's none now.
    if panel and panel:IsShown() then
        local g = panel.glyph
        if g and g:IsShown() then ShowPanel(g) else HidePanel() end
    end
    if pending and not dollRetry and C_Timer and C_Timer.After then
        -- Item data on its way: once more in a second.
        dollRetry = true
        C_Timer.After(1, function()
            dollRetry = false
            RefreshDoll()
        end)
    end
end
ns.CharacterSheetChanged = RefreshDoll

function ns.StartFlyout()
    if not PaperDollFrame then return end
    PaperDollFrame:HookScript("OnShow", RefreshDoll)
    PaperDollFrame:HookScript("OnHide", HidePanel)
end

-- For tests: the anvil button beside a slot button, if it has one.
function ns.CraftGlyph(b) return glyphs[b] end
