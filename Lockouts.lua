-- Alts Forever lockouts: the raids and dungeons each character is saved to, and when each
-- save resets (a player's request, 2026-10-27, held until the live game had lockouts to try).
-- Read as Nova Instance Tracker does on Forever: RequestRaidInfo() after login and after a boss
-- dies, then GetSavedInstanceInfo(i) when UPDATE_INSTANCE_INFO answers. Stored per character
-- as c.saves = { [instance name] = time it resets } and c.saveKills = { [name] = "3/10" };
-- c.saves stays nil until read, so "never read" differs from "saved nowhere".
local _, ns = ...
if ns.disabled then return end -- another copy of Alts Forever is running (Core.lua)
local L = ns.L

local pairs, ipairs, type, pcall, time = pairs, ipairs, type, pcall, time
local issecretvalue = issecretvalue or function() return false end

local GREY = "|cff9d9d9d"

-- A value from the game, or nil if it's secret.
local function Plain(v)
    if issecretvalue(v) then return nil end
    return v
end

-- Reads the logged-in character's saves. An expired save is still listed by the game (so it
-- can be extended) with 0 seconds left: left out.
local function Scan()
    local c = ns.char
    if not c or not GetNumSavedInstances or not GetSavedInstanceInfo then return end
    local ok, count = pcall(GetNumSavedInstances)
    count = ok and Plain(count)
    if type(count) ~= "number" then return end
    local now = time()
    local saves, kills = c.saves or {}, c.saveKills or {}
    wipe(saves)
    wipe(kills)
    for i = 1, count do
        local read, name, _, reset, _, locked, extended, _, _, _, difficulty, bosses, killed = pcall(GetSavedInstanceInfo, i)
        name, reset = read and Plain(name), read and Plain(reset)
        if type(name) == "string" and type(reset) == "number" and reset > 0
            and (Plain(locked) or Plain(extended)) then
            -- Two saves to one place (two difficulties) are told apart by the difficulty.
            difficulty = Plain(difficulty)
            if saves[name] and type(difficulty) == "string" then name = name .. " (" .. difficulty .. ")" end
            saves[name] = now + reset
            bosses, killed = Plain(bosses), Plain(killed)
            if type(bosses) == "number" and bosses > 0 and type(killed) == "number" then
                kills[name] = killed .. "/" .. bosses
            end
        end
    end
    c.saves, c.saveKills = saves, next(kills) and kills or nil
    if ns.RefreshOverview then ns.RefreshOverview() end
end
ns.ScanLockouts = Scan

local function Request()
    if RequestRaidInfo then pcall(RequestRaidInfo) end
end

-- Forgets saves whose reset has passed, for every character. Run when the overview opens
-- (costs nothing in play), so the saved file doesn't keep last week's raids.
function ns.PruneSaves(now)
    for _, c in pairs(ns.db.chars) do
        local saves = c.saves
        if saves then
            for name, at in pairs(saves) do
                if at <= now then
                    saves[name] = nil
                    if c.saveKills then c.saveKills[name] = nil end
                end
            end
            if c.saveKills and next(c.saveKills) == nil then c.saveKills = nil end
        end
    end
end

local function BySoonest(a, b)
    if a[2] ~= b[2] then return a[2] < b[2] end
    return a[1] < b[1]
end

-- A character's saves still running: { { name, resets at, "3/10" or nil }, ... }, soonest
-- reset first; nil if never read.
function ns.ActiveSaves(c, now)
    if not c.saves then return nil end
    local list = {}
    for name, at in pairs(c.saves) do
        if at > now then list[#list + 1] = { name, at, c.saveKills and c.saveKills[name] } end
    end
    table.sort(list, BySoonest)
    return list
end

-- The overview's cell: how many saves are running, blank for none, "?" if never read.
function ns.LockoutText(c, now)
    local list = ns.ActiveSaves(c, now)
    if not list then return GREY .. "?|r" end
    return #list > 0 and tostring(#list) or ""
end

-- "Molten Core  3/10 · 2d 5h" (bosses killed, if the game says, and time to the reset).
function ns.SaveLine(save, now)
    local left = ns.ExpiryText(save[2] - now)
    return save[1], save[3] and (save[3] .. " · " .. left) or left
end

-- The row tooltip's lines (Overview.lua).
function ns.AddLockoutLines(tt, c, now)
    local list = ns.ActiveSaves(c, now)
    if not list or #list == 0 then return end
    tt:AddLine(" ")
    tt:AddLine(L["Lockouts"])
    for _, save in ipairs(list) do
        local name, right = ns.SaveLine(save, now)
        tt:AddDoubleLine(name, right, 1, 1, 1, 1, 1, 1)
    end
end

-- /af lockouts: one line per character with saves running, in the overview's order.
function ns.LockoutLines(now)
    local lines = {}
    for _, key in ipairs(ns.OverviewOrder()) do
        local list = ns.ActiveSaves(ns.db.chars[key], now)
        if list and #list > 0 then
            local parts = {}
            for i, save in ipairs(list) do
                local name, right = ns.SaveLine(save, now)
                parts[i] = name .. " (" .. right .. ")"
            end
            lines[#lines + 1] = ns.ColoredName(key, ns.db.chars[key]) .. ": " .. table.concat(parts, ", ")
        end
    end
    return lines
end

function ns.StartLockouts()
    ns.On("UPDATE_INSTANCE_INFO", Scan)
    -- A boss kill is what saves you: ask again (the answer is UPDATE_INSTANCE_INFO).
    ns.On("ENCOUNTER_END", function(_, _, _, _, success)
        if not issecretvalue(success) and success == 1 then Request() end
    end)
    ns.On("BOSS_KILL", Request)
    if C_Timer and C_Timer.After then C_Timer.After(4, Request) else Request() end
end
