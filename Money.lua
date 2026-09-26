-- Alts Forever money: tracks each character's gold and lists it when you hover the
-- money shown in your bags or bank.
local _, ns = ...

local pairs, select, sort, type, wipe, GetMoney = pairs, select, table.sort, type, wipe, GetMoney
local floor, time, date = math.floor, time, date
local issecretvalue = issecretvalue or function() return false end
local GetCoinTextureString = C_CurrencyInfo.GetCoinTextureString

-- Gold/silver/copper buttons of the combined backpack, the single-bag view and the bank.
local BUTTONS = {
    "ContainerFrameCombinedBagsGoldButton", "ContainerFrameCombinedBagsSilverButton",
    "ContainerFrameCombinedBagsCopperButton",
    "ContainerFrame1MoneyFrameGoldButton", "ContainerFrame1MoneyFrameSilverButton",
    "ContainerFrame1MoneyFrameCopperButton",
    "BankPanelGoldButton", "BankPanelSilverButton", "BankPanelCopperButton",
}

local order, chars = {}, nil
local function ByMoney(a, b) return chars[a].money > chars[b].money end

-- Coin icons sized to the tooltip's text; set once the UI has loaded.
local iconSize = 12
local function Coins(copper) return GetCoinTextureString(copper, iconSize) end

---------------------------------------------------------------------------
-- Gold over time. db.goldDays[day] = total gold across all characters, the latest
-- reading that day (days counted in local time), kept for about a year: one number a
-- day. Recorded whether or not session stats are shown, so the history is there if a
-- player turns them on later. The day only changes at midnight, so recording costs a
-- sum over the characters and nothing else.
---------------------------------------------------------------------------
local DAY = 86400
local KEEP_DAYS = 400
local dayOffset, today, nextDay = 0, nil, 0
local sessionStart -- this character's gold at login

-- For keeping the session across /reload (Character.lua).
function ns.SessionGold() return sessionStart end
function ns.SetSessionGold(copper) sessionStart = copper end

local function AccountTotal()
    local total = 0
    for _, c in pairs(ns.db.chars) do
        if c.money then total = total + c.money end
    end
    return total
end

local function RecordDay()
    local now = time()
    local days = ns.db.goldDays
    if not today or now >= nextDay then
        today = floor((now + dayOffset) / DAY)
        nextDay = (today + 1) * DAY - dayOffset
        for day in pairs(days) do
            if day < today - KEEP_DAYS then days[day] = nil end
        end
    end
    days[today] = AccountTotal()
end

-- The change in total gold since the latest day at least `back` days before today
-- (1: today; 7: this week), or nil if there's no such day yet.
local function ChangeSince(back)
    local days, best = ns.db.goldDays, nil
    for day in pairs(days) do
        if day <= today - back and (not best or day > best) then best = day end
    end
    return best and AccountTotal() - days[best]
end

-- A change in gold: green gained, red lost, white none.
local function Signed(copper)
    if copper < 0 then return "|cffff4040-" .. GetCoinTextureString(-copper, iconSize) .. "|r" end
    if copper > 0 then return "|cff20ff20+" .. GetCoinTextureString(copper, iconSize) .. "|r" end
    return GetCoinTextureString(0, iconSize)
end

-- This session (this character), today and this week (all characters).
local function AddStats(tt)
    tt:AddLine(" ")
    if sessionStart and ns.char.money then
        tt:AddDoubleLine("This session", Signed(ns.char.money - sessionStart), 1, 0.82, 0, 1, 1, 1)
    end
    local day, week = ChangeSince(1), ChangeSince(7)
    if day then tt:AddDoubleLine("Today, all characters", Signed(day), 1, 1, 1, 1, 1, 1) end
    if week then tt:AddDoubleLine("This week, all characters", Signed(week), 1, 1, 1, 1, 1, 1) end
end

-- A "Gold" title, then the same layout as item tooltips: total (only when more
-- than one character has gold), the current character, then others by amount; then
-- gold over time if session stats are on.
function ns.AddMoneyLines(tt)
    chars = ns.db.chars
    wipe(order)
    local n, total = 0, 0
    for key, c in pairs(chars) do
        local m = c.money
        if m and m > 0 and key ~= ns.charKey then
            n = n + 1
            order[n] = key
            total = total + m
        end
    end
    sort(order, ByMoney)

    local mine = ns.char.money or 0
    tt:AddLine("Gold", 1, 0.82, 0)
    if n > 0 then
        tt:AddDoubleLine("Total", Coins(total + mine), 1, 0.82, 0, 1, 1, 1)
    end
    tt:AddDoubleLine(ns.ColoredName(ns.charKey, ns.char), Coins(mine), 1, 1, 1, 1, 1, 1)
    for i = 1, n do
        local key = order[i]
        tt:AddDoubleLine(ns.ColoredName(key, chars[key]), Coins(chars[key].money), 1, 1, 1, 1, 1, 1)
    end
    if ns.StatsOn() then AddStats(tt) end
end

local function OnEnter(self)
    local tt = GameTooltip
    local owner = tt:IsShown() and tt:GetOwner()
    -- If the game already shows a tooltip here, add to it; otherwise open our own.
    local frame = self:GetParent() or self
    if owner == self or (owner and owner == frame) then
        tt:AddLine(" ")
    else
        -- Sit above the whole money display, right edges lined up, so the tooltip
        -- doesn't shift between the gold, silver and copper buttons.
        tt:SetOwner(self, "ANCHOR_NONE")
        tt:ClearAllPoints()
        tt:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 2)
    end
    ns.AddMoneyLines(tt)
    tt:Show()
end

local function OnLeave(self)
    if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
end

-- Hooks whichever money buttons exist yet, each only once. The bank window may
-- not exist until the bank is first opened, so this runs again then.
local hooked = {}
local function HookButtons()
    for i = 1, #BUTTONS do
        local button = _G[BUTTONS[i]]
        if button and not hooked[button] then
            hooked[button] = true
            button:HookScript("OnEnter", OnEnter)
            button:HookScript("OnLeave", OnLeave)
        end
    end
end

-- EllesmereUIBags replaces the bags with its own, whose money display (EUI_BagMoneyFrame)
-- has an invisible hover area on top showing EllesmereUI's own gold summary. That's the
-- player's choice, so ours shows there only when they've turned EllesmereUI's gold
-- tracking off (its summary then shows nothing). The setting is read on every hover, so
-- switching it applies straight away.
local function EllesmereGoldOff()
    local db = EllesmereUI and EllesmereUI._bagsDB
    local profile = type(db) == "table" and db.profile
    return type(profile) == "table" and profile.enableGoldTracking == false
end

-- Our gold tooltip just above a bag addon's money display.
local function ShowAbove(self)
    local tt = GameTooltip
    tt:SetOwner(self, "ANCHOR_NONE")
    tt:ClearAllPoints()
    tt:SetPoint("BOTTOMRIGHT", self, "TOPRIGHT", 0, 2)
    ns.AddMoneyLines(tt)
    tt:Show()
end

local function EllesmereEnter(self)
    if EllesmereGoldOff() then ShowAbove(self) end
end

-- The hover area is an unnamed frame beside the money display, anchored to it. Found
-- and hooked once, the first time the bags are shown.
local function HookEllesmereBags()
    local money = EUI_BagMoneyFrame
    local footer = money and money.GetParent and money:GetParent()
    if not footer or hooked[money] then return end
    for i = 1, select("#", footer:GetChildren()) do
        local child = select(i, footer:GetChildren())
        local anchor
        if child.GetPoint then anchor = select(2, child:GetPoint(1)) end
        if child ~= money and anchor == money and child.HookScript and not hooked[child] then
            hooked[money], hooked[child] = true, true
            child:HookScript("OnEnter", EllesmereEnter)
            child:HookScript("OnLeave", OnLeave)
            return
        end
    end
end

-- ElvUI's bags: the gold text has a click area (pickupGold) but no tooltip, so ours
-- shows there. ElvUI's own gold across characters is on its Gold datatext, left alone.
local function HookElvUIBags()
    local bags = ElvUI_ContainerFrame
    local area = bags and bags.pickupGold
    if not area or hooked[area] or not area.HookScript then return end
    hooked[area] = true
    area:HookScript("OnEnter", ShowAbove)
    area:HookScript("OnLeave", OnLeave)
end

function ns.StartMoney()
    local char = ns.char

    -- Local time's offset from UTC, so days start at local midnight.
    local now = time()
    dayOffset = now - time(date("!*t", now))
    ns.db.goldDays = ns.db.goldDays or {}

    local function Update()
        local m = GetMoney()
        if not issecretvalue(m) then
            char.money = m
            sessionStart = sessionStart or m
            RecordDay()
        end
    end
    ns.On("PLAYER_MONEY", Update)
    Update()

    local _, height = GameTooltipText:GetFont()
    if height then iconSize = height end

    HookButtons()
    ns.On("BANKFRAME_OPENED", HookButtons)
    if EUI_Bags and EUI_Bags.HookScript then EUI_Bags:HookScript("OnShow", HookEllesmereBags) end
    -- ElvUI builds its bags during its own login setup; this runs after every addon's.
    ns.On("PLAYER_ENTERING_WORLD", HookElvUIBags)
end
