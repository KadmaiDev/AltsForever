-- Alts Forever bars: hovering the experience or reputation bar lists your other
-- characters (Blizzard's bars, ElvUI's and EllesmereUI's).
local _, ns = ...

local floor, ipairs, pairs, type, time = math.floor, ipairs, pairs, type, time
local GREY = "|cff9d9d9d"

---------------------------------------------------------------------------
-- Status bar tooltips: hovering the experience bar adds your other characters still
-- levelling (level, XP, rested); hovering the reputation bar adds your other characters'
-- standing with the watched faction. You're left out: the bar already shows you. The
-- lines are built only on hover.
---------------------------------------------------------------------------

-- The last rows added, so a tooltip we open ourselves can line them up again once shown.
local lastRows = {}

-- Adds a "Your characters" section; returns false, adding nothing, if there are no rows.
-- `title` starts a tooltip we opened ourselves; otherwise a gap follows the bar's own.
function ns.AddCharacterRows(tt, rows, labels, title, noGap)
    if #rows == 0 then return false end
    if title then tt:AddLine(title, 1, 1, 1) elseif not noGap then tt:AddLine(" ") end
    tt:AddLine("Your characters", 1, 0.82, 0)
    local first = tt.NumLines and tt:NumLines() + 1
    for _, row in ipairs(rows) do
        local text = ""
        for col = 2, #row do
            text = text .. (col > 2 and "  " or "") .. (labels[col - 1] or "") .. row[col]
        end
        tt:AddDoubleLine(row[1], text, 1, 1, 1, 1, 1, 1)
    end
    if first then
        ns.AlignColumns(tt, first, rows, labels)
        lastRows.tt, lastRows.first, lastRows.rows, lastRows.labels = tt, first, rows, labels
    end
    return true
end

local XP_LABELS = { nil, nil, GREY .. "rested|r " }

local BigNumber = BreakUpLargeNumbers or tostring

-- This session: time, XP gained and, once there's a pace, about how long to level.
local function AddSession(tt)
    local seconds, xp, toLevel = ns.SessionXP(time())
    tt:AddDoubleLine("This session", ns.FormatPlayed(seconds), 1, 0.82, 0, 1, 1, 1)
    tt:AddDoubleLine("XP gained", BigNumber(xp), 1, 1, 1, 1, 1, 1)
    if toLevel then tt:AddDoubleLine("Time to level", "about " .. ns.FormatPlayed(toLevel), 1, 1, 1, 1, 1, 1) end
end

-- This session's stats (when turned on), then your other characters still levelling:
-- level, XP and rested XP.
function ns.AddXPLines(tt, fresh)
    local chars, maxLevel, now = ns.db.chars, ns.MaxLevel(), time()
    local rows = {}
    for _, key in ipairs(ns.OverviewOrder()) do
        local c = chars[key]
        if key ~= ns.charKey and c.level and c.level < maxLevel then
            local xp = (c.xpMax and c.xpMax > 0) and (GREY .. floor(c.xp * 100 / c.xpMax) .. "%|r") or ""
            rows[#rows + 1] = { ns.ColoredName(key, c), tostring(c.level), xp, ns.RestedText(c, now) }
        end
    end
    local me = ns.char
    local stats = ns.StatsOn() and me.level and me.level < maxLevel
    if #rows == 0 and not stats then return false end
    if fresh then tt:AddLine("Experience", 1, 1, 1) else tt:AddLine(" ") end
    if stats then
        AddSession(tt)
        if #rows > 0 then tt:AddLine(" ") end
    end
    ns.AddCharacterRows(tt, rows, XP_LABELS, nil, true)
    return true
end

-- Blizzard's bars show a tooltip only sometimes, so we open one if none is showing;
-- ElvUI's and EllesmereUI's show theirs (unless the player made the bar click-through,
-- or it has nothing to show), and we add to it.
local function HookBar(bar, ownTooltip, add)
    if not bar or bar.altsForeverHooked or not bar.HookScript then return end
    bar.altsForeverHooked = true
    bar:HookScript("OnEnter", function(self)
        local tt = GameTooltip
        if tt:IsForbidden() then return end
        if tt:IsShown() then
            if add(tt) then tt:Show() end
        elseif ownTooltip then
            tt:SetOwner(self, "ANCHOR_TOP")
            lastRows.tt = nil
            if add(tt, true) then
                tt:Show()
                -- Shown now, in its final font (a UI addon such as EllesmereUI sets its
                -- own on show): line up again and show again to fit.
                if lastRows.tt == tt then
                    ns.AlignColumns(tt, lastRows.first, lastRows.rows, lastRows.labels)
                    tt:Show()
                end
            else
                tt:Hide()
            end
        end
    end)
    if ownTooltip then
        bar:HookScript("OnLeave", function(self)
            if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        end)
    end
end

local function AddRep(tt, fresh)
    return ns.AddRepLines and ns.AddRepLines(tt, fresh) or false
end

-- Blizzard's bars sit in status tracking containers, in `bars` by kind (checked in game:
-- 6 bars, experience 4th). The experience bar is the one with a rested (exhaustion)
-- marker; reputation is the first kind, as in retail.
local function HookBlizzardBars(container)
    if not (container and type(container.bars) == "table") then return end
    for _, bar in pairs(container.bars) do
        if type(bar) == "table" and bar.ExhaustionTick then HookBar(bar, true, ns.AddXPLines) end
    end
    local enum = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum
    local rep = container.bars[enum and enum.Reputation or 1]
    if type(rep) == "table" and not rep.ExhaustionTick then HookBar(rep, true, AddRep) end
end

-- Hooks each bar once. Other UIs make theirs during their own login setup, so this runs
-- on entering the world (after every addon's login) and again after each loading screen,
-- which costs nothing once hooked.
local function HookBars()
    HookBlizzardBars(MainStatusTrackingBarContainer)
    HookBlizzardBars(SecondaryStatusTrackingBarContainer)
    HookBar(ElvUI_ExperienceBarHolder, false, ns.AddXPLines)
    HookBar(EllesmereEAB_XPBar, false, ns.AddXPLines)
    HookBar(ElvUI_ReputationBarHolder, false, AddRep)
    HookBar(EllesmereEAB_RepBar, false, AddRep)
end

function ns.StartBars()
    ns.On("PLAYER_ENTERING_WORLD", HookBars)
end
