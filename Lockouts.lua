-- Alts Forever lockouts: the raids and dungeons each character is saved to, and when each
-- save resets (a player's request, 2026-10-27, held until the live game had lockouts to try).
-- Read as Nova Instance Tracker does on Forever: RequestRaidInfo() after login and after a boss
-- dies, then GetSavedInstanceInfo(i) when UPDATE_INSTANCE_INFO answers. Stored per character
-- as c.saves = { [instance name] = time it resets } and c.saveKills = { [name] = "3/10" };
-- c.saves stays nil until read, so "never read" differs from "saved nowhere".
-- Also the hourly instance limit, per game account (below).
local _, ns = ...
if ns.disabled then return end -- another copy of Alts Forever is running (Core.lua)
local L = ns.L

local pairs, ipairs, type, pcall, time = pairs, ipairs, type, pcall, time
local tonumber, format, ceil, random = tonumber, string.format, math.ceil, math.random
local tremove, sort, concat = table.remove, table.sort, table.concat
local issecretvalue = issecretvalue or function() return false end

local GREY, ORANGE = "|cff9d9d9d", "|cffff8000"
local EMPTY = {}

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
local PruneRuns

function ns.PruneSaves(now)
    PruneRuns(now)
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

---------------------------------------------------------------------------
-- The hourly instance limit
---------------------------------------------------------------------------
-- Forever lets a game account enter 10 dungeons and raids an hour, all its characters together
-- (Nova Instance Tracker's figures; the game doesn't tell addons). Each character keeps the
-- instances it entered as c.runs = { { at = entered, left = time it left, last = the latest
-- time it was known to be inside while not left, map = instance ID, zone = the copy's ID,
-- name = "Ragefire Chasm" }, ... }, oldest first, and c.account says which game account it's
-- on (db.account: made once per saved file, and the saved file is per game account), so sync
-- brings another account's count along with its characters. A run counts until an hour after
-- it was left (Nova's rule; the game's may count from entering, so this errs on the safe
-- side); one still open that isn't yours now counts until an hour after `last`, so another
-- account's character still inside stays counted as long as syncs keep coming, and one that
-- can't be closed stops in time. Going back into the same copy isn't a new instance: a run is
-- reopened when the character comes back dead (a corpse run) or by logging in or reloading
-- there, and runs of one account into one copy count once (a character going out and back in,
-- or two characters of the account there), once a spell cast there gives the copy's ID, as
-- Nova does (a cast's GUID is Cast-type-server-instance-copy-spell-n). Each run stays its own
-- character's, so a character's own visit is always tracked to its end. The overview's footer
-- shows the counts, /af lockouts lists them.
local LIMIT, HOUR = 10, 3600
ns.INSTANCE_LIMIT = LIMIT
local current      -- the logged-in character's run while inside an instance
local reopenedLeft -- when the run just reopened had been left, until the copy is known
local castFrame

-- When a run stops counting.
local function RunEnds(run, now)
    if run == current then return now + HOUR end
    return (run.left or run.last or run.at) + HOUR
end

-- Forgets runs that have stopped counting. Where it costs nothing in play: a loading screen,
-- the overview opening.
function PruneRuns(now)
    for _, c in pairs(ns.db.chars) do
        local runs = c.runs
        if runs then
            for i = #runs, 1, -1 do
                if RunEnds(runs[i], now) <= now then tremove(runs, i) end
            end
            if #runs == 0 then c.runs = nil end
        end
    end
end

-- The logged-in character's runs still open that it isn't in (it logged in elsewhere, or the
-- game never said it left): ended when it was last known to be inside.
local function CloseOpen(c)
    for _, run in ipairs(c.runs or EMPTY) do
        if not run.left and run ~= current then run.left = run.last or run.at end
    end
end

-- Sync is about to send the character you're on: you're inside as of now.
function ns.TouchRun()
    if current then current.last = time() end
end

local function Changed()
    if ns.RefreshOverview then ns.RefreshOverview() end
end

-- The instance you're in, if it's a dungeon or raid: its ID and name.
local function Here()
    if not IsInInstance or not GetInstanceInfo then return nil end
    local inside, kind = IsInInstance()
    if issecretvalue(inside) or issecretvalue(kind) or not inside then return nil end
    if kind ~= "party" and kind ~= "raid" then return nil end
    local name, _, _, _, _, _, _, map = GetInstanceInfo()
    name, map = Plain(name), Plain(map)
    if type(map) ~= "number" then return nil end
    return map, type(name) == "string" and name or nil
end

local function WatchCasts(on)
    if not castFrame then return end
    if on then
        pcall(castFrame.RegisterUnitEvent, castFrame, "UNIT_SPELLCAST_SUCCEEDED", "player")
    else
        castFrame:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    end
end

-- Your first cast in an instance says which copy it is.
local function OnCast(unit, guid)
    if unit ~= "player" or not current or issecretvalue(guid) or type(guid) ~= "string" then return end
    local kind, _, _, _, zone = strsplit("-", guid)
    zone = tonumber(zone)
    if kind ~= "Cast" or not zone or zone <= 0 then return end
    WatchCasts(false)
    local c, now = ns.char, time()
    if current.zone and current.zone ~= zone then
        -- Reopened, but the copy is new (it was reset): a new instance after all.
        current.left, current.last = reopenedLeft or current.last or now, nil
        current = { at = now, map = current.map, name = current.name, zone = zone }
        c.runs[#c.runs + 1] = current
    else
        current.zone = zone
    end
    reopenedLeft = nil
    Changed()
end

-- Every loading screen: into an instance, out of one, or a login or reload.
local function Entered(isLogin, isReload)
    local c, now = ns.char, time()
    if not c then return end
    PruneRuns(now)
    local map, name = Here()
    if current and current.map ~= map then
        current.left = now
        current = nil
    end
    CloseOpen(c)
    if not map then
        WatchCasts(false)
        reopenedLeft = nil
        return Changed()
    end
    if current then return end -- a loading screen inside the same instance
    local last = c.runs and c.runs[#c.runs]
    local ghost = UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")
    local dead = not issecretvalue(ghost) and ghost
    if last and last.map == map and (isLogin or isReload or dead) then
        reopenedLeft, last.left = last.left, nil
        current = last
    else
        reopenedLeft = nil
        current = { at = now, map = map, name = name }
        c.runs = c.runs or {}
        c.runs[#c.runs + 1] = current
    end
    WatchCasts(true)
    Changed()
end

-- Whether another run of the same account into the same copy stands for this one (the one
-- that counts longest; on a tie the earlier, then the first by name), so the copy counts once.
local function Shadowed(run, ends, key, account, now)
    if not run.zone then return false end
    for key2, c2 in pairs(ns.db.chars) do
        if c2.account == account and c2.runs then
            for _, r in ipairs(c2.runs) do
                if r ~= run and r.zone == run.zone and r.map == run.map then
                    local e = RunEnds(r, now)
                    if e > ends or (e == ends and (r.at < run.at or (r.at == run.at and key2 < key))) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function FirstName(key)
    return key:match("^%S+") or key
end

local function Minutes(seconds)
    return L["%d min"]:format(ceil(seconds / 60))
end

local function ByAccount(a, b)
    local mine = ns.db.account
    if (a.id == mine) ~= (b.id == mine) then return a.id == mine end
    return a.main < b.main
end

-- Every known account (by its characters' c.account): { id, main = its most played
-- character, n = instances counting now, free = when the first of them stops }, this account
-- first. Built when asked (the overview refreshing, /af lockouts), into the same tables each
-- time, so a refresh of the open overview allocates nothing for it: the list is only good
-- until the next call.
local list, by, spare, parts = {}, {}, {}, {}

function ns.InstanceCounts(now)
    wipe(by)
    for i = #list, 1, -1 do
        spare[#spare + 1], list[i] = list[i], nil
    end
    for key, c in pairs(ns.db.chars) do
        local id = c.account
        if id then
            local a = by[id]
            if not a then
                a = tremove(spare) or {}
                a.id, a.n, a.main, a.played, a.free = id, 0, nil, nil, nil
                by[id], list[#list + 1] = a, a
            end
            local played = c.played or 0
            if not a.main or played > a.played or (played == a.played and key < a.main) then
                a.main, a.played = key, played
            end
            for _, run in ipairs(c.runs or EMPTY) do
                local ends = RunEnds(run, now)
                if ends > now and not Shadowed(run, ends, key, id, now) then
                    a.n = a.n + 1
                    if not a.free or ends < a.free then a.free = ends end
                end
            end
        end
    end
    sort(list, ByAccount)
    return list
end

-- The overview footer's part: "Instances this hour: 3/10", with each account's first name
-- once two are known ("Kadmai 3/10, Brak 10/10 (12 min)"); at the limit, orange with the wait.
-- nil when no account has entered one.
function ns.InstanceText(now)
    ns.InstanceCounts(now)
    wipe(parts)
    for _, a in ipairs(list) do
        if a.n > 0 then
            local text = a.n .. "/" .. LIMIT
            if a.n >= LIMIT then text = ORANGE .. text .. " (" .. Minutes(a.free - now) .. ")|r" end
            if #list > 1 then text = FirstName(a.main) .. " " .. text end
            parts[#parts + 1] = text
        end
    end
    if #parts == 0 then return nil end
    return L["Instances this hour: %s"]:format(concat(parts, ", "))
end

-- /af lockouts: a line per account that has entered any.
function ns.InstanceLines(now)
    local lines = {}
    for _, a in ipairs(ns.InstanceCounts(now)) do
        if a.n > 0 then
            lines[#lines + 1] = L["%s's account: %d, the next frees in %s"]:format(FirstName(a.main), a.n, Minutes(a.free - now))
        end
    end
    return lines
end

function ns.StartLockouts()
    local db = ns.db
    db.account = db.account or format("%x%06x", time(), random(0, 0xffffff))
    ns.char.account = db.account
    castFrame = CreateFrame("Frame")
    castFrame:SetScript("OnEvent", function(_, _, ...) OnCast(...) end)
    ns.On("PLAYER_ENTERING_WORLD", Entered)
    ns.On("PLAYER_LOGOUT", function()
        if current then current.left = time() end
    end)
    ns.On("UPDATE_INSTANCE_INFO", Scan)
    -- A boss kill is what saves you: ask again (the answer is UPDATE_INSTANCE_INFO).
    ns.On("ENCOUNTER_END", function(_, _, _, _, success)
        if not issecretvalue(success) and success == 1 then Request() end
    end)
    ns.On("BOSS_KILL", Request)
    if C_Timer and C_Timer.After then C_Timer.After(4, Request) else Request() end
end
