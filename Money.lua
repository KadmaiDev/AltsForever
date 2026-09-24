-- Alts Forever money: tracks each character's gold and lists it when you hover the
-- money shown in your bags or bank.
local _, ns = ...

local pairs, sort, wipe, GetMoney = pairs, table.sort, wipe, GetMoney
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

-- A "Gold" title, then the same layout as item tooltips: total (only when more
-- than one character has gold), the current character, then others by amount.
function ns.AddMoneyLines(tt)
    local db = ns.db
    chars = db.chars
    wipe(order)
    local n, total = 0, 0
    for key, c in pairs(chars) do
        local m = c.money
        if m and m > 0 and key ~= ns.charKey and (not db.realmOnly or c.realm == ns.realm) then
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

function ns.StartMoney()
    local char = ns.char

    local function Update()
        local m = GetMoney()
        if not issecretvalue(m) then char.money = m end
    end
    ns.On("PLAYER_MONEY", Update)
    Update()

    local _, height = GameTooltipText:GetFont()
    if height then iconSize = height end

    HookButtons()
    ns.On("BANKFRAME_OPENED", HookButtons)
end
