-- Alts Forever: upgrades your characters can craft, on the character sheet. A small anvil
-- button sits just outside a slot (left of the left column, right of the right column,
-- below the weapons; the inner sides can hold a UI addon's stat text) when you or one of
-- your characters who can mail you can craft an upgrade for it that you can wear now and
-- that binds when equipped (owner, 2026-10-16), with the best one's chevrons on its corner
-- (minor, decent, major). Hover it for the best few; click it for
-- all of them as item buttons beside it. Upgrades.lua picks them (ns.CraftableUpgrades).
-- (Before, the list sat under the game's Alt-hover equipment flyout; the owner preferred
-- a button to click.)
-- The same anvils sit beside the inspect window's slots for what your characters could
-- craft for the player you're inspecting (a player's suggestion, 2026-11-11).
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
-- The player being inspected, shaped like a saved character so the same scoring applies,
-- and their slots' lists. Nothing of theirs is stored.
local them = { gear = {} }
local theirSlots, theirAll = {}, {}
local inspectRetry, inspectTries, inspectHooked = false, 0, false
local dollKey, dollRetry = nil, false
-- Retries while item data loads, in a row; reset when a pass has everything or the sheet
-- opens again, so an item that never loads can't keep a timer going (as Bags.lua's).
local dollTries, MAX_RETRIES = 0, 5
local panel
local buttons = {}

local function GainText(e) return ns.GainLabel(e.gain, e.empty) end

---------------------------------------------------------------------------
-- The panel of item buttons
---------------------------------------------------------------------------
-- The crafter's name as lists show it (a character forgotten since: just the name).
local function Crafter(e)
    local c = ns.db.chars[e.key]
    return c and ns.ListName(e.key, c) or e.key
end

local function ItemEnter(b)
    local e = b.entry
    if not e then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(e.link)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Crafted by %s (%s)"]:format(Crafter(e), e.prof), 1, 0.82, 0)
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
    b.tier:SetPoint("BOTTOMRIGHT", 0, -2) -- the picture's own margin: about the same gap right and below
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)
    b:SetScript("OnEnter", ItemEnter)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", ItemClick)
    ns.SkinItemSlot(b)
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
    -- Every item button now: one made while the panel is open would have the controller's
    -- navigator rebuild it from our code.
    for i = 1, MAX do ItemButton(i):Hide() end
    panel:Hide()
    -- With a controller, A on an anvil opens it with focus inside, and B closes it.
    ns.GamepadWindow(panel)
    ns.ScaleWindow(panel)
end

local function HidePanel()
    if panel then
        panel:Hide()
        panel.glyph = nil
    end
end

-- Shows the panel beside a glyph, outwards from the sheet; false if there's nothing.
local function ShowPanel(glyph)
    local list = glyph.lists and glyph.lists[glyph.slot]
    local n = list and min(#list, MAX) or 0
    if n == 0 then return HidePanel() end
    if not panel then BuildPanel() end
    panel.glyph = glyph
    for i = 1, n do
        local e, b = list[i], ItemButton(i)
        b.entry = e
        b.icon:SetTexture(C_Item.GetItemIconByID(e.id))
        local q = C_Item.GetItemQualityByID(e.id)
        if not ns.SlotQuality(b, q) then
            local color = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
            if color then b.border:SetVertexColor(color.r, color.g, color.b) end
            b.border:SetShown(color ~= nil)
        end
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
    -- An inside anvil (the inspect window) has its slot between it and the edge: the panel
    -- goes beyond the slot, not over it.
    local from = glyph.inside and glyph:GetParent() or glyph
    if glyph.side == "left" then
        panel:SetPoint("TOPRIGHT", from, "TOPLEFT", -2, 0)
    elseif glyph.side == "right" then
        panel:SetPoint("TOPLEFT", from, "TOPRIGHT", 2, 0)
    else
        panel:SetPoint("TOP", from, "BOTTOM", 0, -2)
    end
    panel:Show()
end

---------------------------------------------------------------------------
-- The anvil buttons
---------------------------------------------------------------------------
local function GlyphEnter(g)
    local list = g.lists and g.lists[g.slot]
    if not list then return end
    GameTooltip:SetOwner(g, g.side == "left" and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
    GameTooltip:AddLine(L["Your characters can craft"], 1, 0.82, 0)
    for i = 1, min(#list, SHOWN_IN_TOOLTIP) do
        local e = list[i]
        GameTooltip:AddDoubleLine(e.link, GainText(e) .. " · " .. Crafter(e), 1, 1, 1, 1, 1, 1)
    end
    -- For an inspected player: what they were judged as, since it's read from their talents.
    local role = g.who and ns.RoleOf(g.who)
    if role then GameTooltip:AddLine(L["Judged as %s"]:format(ns.RoleName(role)), 0.6, 0.6, 0.6) end
    GameTooltip:AddLine(L["Click: show them"], 1, 1, 1)
    GameTooltip:Show()
end

local function GlyphClick(g)
    GameTooltip:Hide()
    if panel and panel:IsShown() and panel.glyph == g then return HidePanel() end
    ShowPanel(g)
end

-- `inside`: on the slot's inner side, for the inspect window, whose slots sit against its
-- edges (the outside anvils fell off the window or under its side tabs: owner's screenshot,
-- 2026-11-11). EllesmereUI writes each item's level there, so with it the anvil goes past
-- that number; weapons get theirs above the slot.
local function Glyph(b, side, inside)
    local g = glyphs[b]
    if g then return g end
    g = CreateFrame("Button", nil, b)
    g:SetSize(GLYPH, GLYPH)
    g:SetFrameLevel((b:GetFrameLevel() or 1) + 5)
    g.inside = inside
    -- Beside a side column the anvil sits at the slot's top, with its chevrons under it:
    -- there's only an anvil's width between the left column and the window's edge.
    if inside then
        local gap = _G.EllesmereUI and 24 or 5
        if side == "left" then
            g:SetPoint("TOPLEFT", b, "TOPRIGHT", gap, 1)
        elseif side == "right" then
            g:SetPoint("TOPRIGHT", b, "TOPLEFT", -gap, 1)
        else
            g:SetPoint("BOTTOM", b, "TOP", 0, 6) -- clear of the slot's frame
        end
    elseif side == "left" then
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
    -- Inside (the inspect window) always beside it, on the row of the item level: EllesmereUI
    -- writes the item's enchant on the row below (owner's screenshot, 2026-11-11).
    if side == "bottom" or (inside and side == "left") then
        g.tier:SetPoint("LEFT", g, "RIGHT", -3, -2)
    elseif inside then
        g.tier:SetPoint("RIGHT", g, "LEFT", 3, -2)
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
-- The anvils have their own setting ("Show craftable upgrades on the character sheet",
-- /af anvils; owner, 2026-10-16), apart from Show upgrades (the tooltips).
function ns.AnvilsOn() return not ns.db.anvilsOff end

-- Sorts a list from ns.CraftableUpgrades into `into` by slot: only what can be worn now
-- and binds when equipped.
local function Group(list, into)
    for _, e in ipairs(list) do
        if e.boe and not e.at and e.slot then
            local t = into[e.slot]
            if not t then
                t = {}
                into[e.slot] = t
            end
            t[#t + 1] = e
        end
    end
end

-- Shows or hides the anvil beside each slot button of a window ("Character" or "Inspect"
-- .. name .. "Slot"), then lets the open panel follow.
local function Mark(prefix, lists, who)
    local inside = prefix == "Inspect"
    for side, names in pairs(SIDES) do
        for _, name in ipairs(names) do
            local b = _G[prefix .. name .. "Slot"]
            local slot = b and b.GetID and b:GetID()
            if type(slot) == "number" and not issecretvalue(slot) then
                local has = lists[slot] ~= nil
                local g = glyphs[b] or (has and Glyph(b, side, inside))
                if g then
                    g.slot, g.lists, g.who = slot, lists, who
                    g:SetShown(has)
                    if has then g.tier:SetTexture(ns.GainTexture(lists[slot][1].gain)) end -- best first
                end
            end
        end
    end
    -- The panel follows: its slot's list changed, or there's none now.
    if panel and panel:IsShown() then
        local g = panel.glyph
        if g and g:IsShown() then ShowPanel(g) else HidePanel() end
    end
end

local function RefreshDoll()
    if not (ns.char and PaperDollFrame and PaperDollFrame:IsVisible()) then return end
    local on = ns.AnvilsOn()
    local key = ns.UpgradesVersion() .. ":" .. (ns.craftVersion or 0) .. ":" .. (ns.char.level or 0) .. ":" .. tostring(on)
    if key == dollKey then return end
    local pending = false
    wipe(bySlot)
    if on then
        all, pending = ns.CraftableUpgrades(nil, all)
        Group(all, bySlot)
    end
    dollKey = not pending and key or nil
    if not pending then dollTries = 0 end
    Mark("Character", bySlot)
    if pending and not dollRetry and dollTries < MAX_RETRIES and C_Timer and C_Timer.After then
        -- Item data on its way: once more in a second.
        dollRetry, dollTries = true, dollTries + 1
        C_Timer.After(1, function()
            dollRetry = false
            RefreshDoll()
        end)
    end
end

---------------------------------------------------------------------------
-- The inspect window
---------------------------------------------------------------------------
-- Its own setting ("Show craftable upgrades when inspecting a player", /af inspect).
function ns.InspectAnvilsOn() return not ns.db.inspectAnvilsOff end

local function Plain(v)
    if not issecretvalue(v) and v ~= nil then return v end
end

-- The inspected player's spec. The game keeps one inspect talent config, holding whoever
-- was inspected last, by any addon: so it's read only while the last INSPECT_READY was for
-- this player, and kept with their GUID. A later pass (a retry, item data arriving, a
-- setting) uses what was kept, never the config as it is by then (peer review, 2026-11-11).
local lastReady            -- the GUID of the last INSPECT_READY, whoever asked; false if unknown
local specGuid, specValue, specRead = nil, nil, false

local function TakeSpec(guid)
    if not specRead and guid == specGuid and guid == lastReady then
        local spec, read = ns.InspectSpec()
        if read then specValue, specRead = spec, true end
    end
end

-- Fills `them` from the unit: class, level, worn item links and the spec their talents
-- give. Returns whether they can be judged now, and whether something is still to come
-- (a worn item without its link yet, talents not in yet). While a worn item's link is
-- missing they aren't judged at all: the slot would count as empty, and worse gear show as
-- an upgrade for it (peer review). A player of the other faction can't be handed anything,
-- so isn't judged.
local function ReadThem(unit)
    local _, class = UnitClass(unit)
    class = Plain(class)
    local level = Plain(UnitLevel(unit))
    if type(class) ~= "string" or type(level) ~= "number" or level < 1 then return false, false end
    local faction = UnitFactionGroup and Plain((UnitFactionGroup(unit)))
    if faction and ns.char.faction and faction ~= ns.char.faction then return false, false end
    local gear, pending = them.gear, false
    wipe(gear)
    for slot = 1, 19 do
        local link = Plain(GetInventoryItemLink(unit, slot))
        if type(link) == "string" then
            gear[slot] = link
        elseif Plain(GetInventoryItemID(unit, slot)) then
            pending = true -- the item is known, its link isn't yet (as right after login)
        end
    end
    if pending then return false, true end
    local guid = Plain(UnitGUID(unit))
    local spec, waiting = nil, false
    if guid and guid == specGuid then
        TakeSpec(guid)
        spec = specValue
        waiting = not specRead and guid == lastReady -- still theirs to read: try again
    end
    them.class, them.level, them.spec = class, level, spec
    return true, waiting
end

-- Worked out when the game says an inspected player's data is in (INSPECT_READY for the
-- player the window shows), when item data arrives, and on retries: never otherwise.
-- With the Gamepad UI on there are none: an anvil made in an open window would have the
-- controller's navigator rebuild it from our code (see ns.PrebuildAnvils), and the inspect
-- window doesn't exist until it's first opened.
local function InspectUnit(f)
    local unit = Plain(f.unit)
    return type(unit) == "string" and unit or "target"
end

local function RefreshInspect(fresh)
    local f = InspectFrame
    if not (f and f.IsVisible and f:IsVisible() and ns.char) then return end
    if not inspectHooked then
        inspectHooked = true
        f:HookScript("OnHide", HidePanel)
    end
    local unit = InspectUnit(f)
    if fresh then inspectTries = 0 end
    local pending = false
    wipe(theirSlots)
    if ns.InspectAnvilsOn() and not ns.GamepadUI() then
        local ok
        ok, pending = ReadThem(unit)
        if ok then
            local more
            theirAll, more = ns.CraftableUpgrades(nil, theirAll, them)
            pending = pending or more
            Group(theirAll, theirSlots)
        end
    end
    if not pending then inspectTries = 0 end
    Mark("Inspect", theirSlots, them)
    if pending and not inspectRetry and inspectTries < MAX_RETRIES and C_Timer and C_Timer.After then
        inspectRetry, inspectTries = true, inspectTries + 1
        C_Timer.After(1, function()
            inspectRetry = false
            RefreshInspect()
        end)
    end
end

-- INSPECT_READY for the player the inspect window is on. The game's own window shows
-- itself from the same event, and ours can be handled first (anvils were missing on the
-- first inspect after a reload: owner, 2026-11-11), so the work waits a frame. Another
-- addon inspecting someone else raises the event too: those stop here, costing nothing.
local readySoon = false
local function ReadyNow()
    readySoon = false
    RefreshInspect(true)
end

local function InspectReady(guid)
    local secret = issecretvalue(guid)
    lastReady = not secret and guid or false
    local f = InspectFrame
    if secret or guid == nil or not f then return end
    if Plain(UnitGUID(InspectUnit(f))) ~= guid then return end
    -- Their talents now, while the config is certainly theirs (read again on a new inspect).
    specGuid, specValue, specRead = guid, nil, false
    TakeSpec(guid)
    if readySoon then return end
    if not (C_Timer and C_Timer.After) then return RefreshInspect(true) end
    readySoon = true
    C_Timer.After(0, ReadyNow)
end

function ns.CharacterSheetChanged()
    RefreshDoll()
    RefreshInspect()
end

function ns.SetAnvils(on)
    ns.db.anvilsOff = not on or nil
    RefreshDoll()
end

function ns.SetInspectAnvils(on)
    ns.db.inspectAnvilsOff = not on or nil
    RefreshInspect()
end

-- With the Gamepad UI on (Gamepad.lua): every anvil and the panel made while the character
-- sheet is closed. Blizzard's navigator rebuilds an open window whenever a frame is created
-- in it, from the creating addon's code, which can taint its bindings (as with the Options page).
function ns.PrebuildAnvils()
    if not PaperDollFrame or PaperDollFrame:IsVisible() then return end
    for side, names in pairs(SIDES) do
        for _, name in ipairs(names) do
            local b = _G["Character" .. name .. "Slot"]
            if b and not glyphs[b] then Glyph(b, side):Hide() end
        end
    end
    if not panel then BuildPanel() end
end

function ns.StartFlyout()
    ns.On("INSPECT_READY", InspectReady)
    if not PaperDollFrame then return end
    PaperDollFrame:HookScript("OnShow", function()
        dollTries = 0 -- opened afresh: retries start again
        RefreshDoll()
    end)
    PaperDollFrame:HookScript("OnHide", HidePanel)
end

-- For tests: the anvil button beside a slot button, if it has one.
function ns.CraftGlyph(b) return glyphs[b] end
