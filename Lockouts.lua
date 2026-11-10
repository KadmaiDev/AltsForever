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
local tonumber, format, ceil, floor, random = tonumber, string.format, math.ceil, math.floor, math.random
local tremove, sort, concat = table.remove, table.sort, table.concat
local issecretvalue = issecretvalue or function() return false end

local GREY, ORANGE = "|cff9d9d9d", "|cffff8000"
local EMPTY = {}
local panel, FillPanel -- the Lockouts window (below), once opened

local function PanelChanged()
    if panel and panel:IsShown() then FillPanel() end
end
-- For changes made elsewhere: a character forgotten (Options.lua), a sync (Sync.lua).
function ns.LockoutsChanged()
    PanelChanged()
end

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
    PanelChanged()
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

-- "Molten Core  3/10 · 2d 5h" (bosses killed, if the game says, and time to the reset).
function ns.SaveLine(save, now)
    local left = ns.ExpiryText(save[2] - now)
    return save[1], save[3] and (save[3] .. " · " .. left) or left
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
-- shows the counts, the Lockouts window lists them.
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
    PanelChanged()
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

-- "3/10"; at the limit in orange, with the wait until one frees if `free` is given.
local function CountText(n, free, now)
    local text = n .. "/" .. LIMIT
    if n < LIMIT then return text end
    if free then text = text .. " (" .. Minutes(free - now) .. ")" end
    return ORANGE .. text .. "|r"
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
            local text = CountText(a.n, a.free, now)
            if #list > 1 then text = FirstName(a.main) .. " " .. text end
            parts[#parts + 1] = text
        end
    end
    if #parts == 0 then return nil end
    return L["Instances this hour: %s"]:format(concat(parts, ", "))
end

-- /af lockouts was a chat list until the window replaced it (owner, 2026-11-08).

---------------------------------------------------------------------------
-- The Lockouts window (owner's request, 2026-11-08): the instances each account has entered
-- this hour, each visit still counting under its account, then raid lockouts with raids down
-- and characters across, as the Reputation panel. Opened from the overview's key button and
-- /af lockouts; built on first open, filled only while shown.
---------------------------------------------------------------------------
local ROW_HEIGHT, NAME_WIDTH, CHAR_WIDTH, WHEN_WIDTH, CELL_WIDTH = 16, 170, 150, 110, 80
local MIN_WIDTH = 8 + NAME_WIDTH + CHAR_WIDTH + WHEN_WIDTH + 24
local MIN_ROWS = 8 -- shown however small the screen
local lines = {}
local offset = 0 -- rows scrolled past, when they don't all fit on screen
local tick = 0 -- the pending refresh's number: an older one does nothing

-- While open, the window refills itself when the next "frees in" minute ticks over (or a
-- visit or save runs out), at least once a minute (peer review: it stood still otherwise).
local function Refresh(delay)
    if not (C_Timer and C_Timer.After) then return end
    tick = tick + 1
    local mine = tick
    C_Timer.After(delay, function()
        if mine == tick and panel and panel:IsShown() then FillPanel() end
    end)
end

-- Seconds until a time ends or the minute it shows ("frees in 3 min", rounded up) changes.
local function NextChange(delay, ends, now)
    local d = (ends - now) % 60
    if d == 0 then d = 60 end
    return d < delay and d or delay
end

local function BySoonest2(a, b)
    if a.ends ~= b.ends then return a.ends < b.ends end
    return a.key < b.key
end

-- An account's visits counting now, each { key, run, ends }, soonest free first.
local function Visits(now, account)
    local out = {}
    for key, c in pairs(ns.db.chars) do
        if c.account == account then
            for _, run in ipairs(c.runs or EMPTY) do
                local ends = RunEnds(run, now)
                if ends > now and not Shadowed(run, ends, key, account, now) then
                    out[#out + 1] = { key = key, run = run, ends = ends }
                end
            end
        end
    end
    sort(out, BySoonest2)
    return out
end

---------------------------------------------------------------------------
-- The overview's Lockouts column (owner, 2026-11-10: "should the lockouts column show 2/10"):
-- the character's account's instances this hour, the same on each of its characters, so the
-- column says who can still go in; then the character's raid saves after the Lockouts
-- window's key. "2/10 <key>1"; blank when neither; "?" when either is unknown and nothing
-- shows (saves not read since 1.2.0, or the account not known: never counted as free).
-- Reads the counts made by the latest ns.InstanceCounts(now): the overview counts once per
-- refresh, before its rows.
---------------------------------------------------------------------------
local KEY = "|TInterface\\Icons\\INV_Misc_Key_03:0:0:0:0:64:64:5:59:5:59|t"

function ns.LockoutText(c, now)
    local a = c.account and by[c.account]
    local hourly = a and a.n > 0 and CountText(a.n)
    local list = ns.ActiveSaves(c, now)
    local saves = list and #list > 0 and (KEY .. #list)
    if hourly and saves then return hourly .. "  " .. saves end
    if hourly or saves then return hourly or saves end
    if not list or not c.account then return GREY .. "?|r" end
    return ""
end

-- Seconds until the overview's instance counts next change, from the latest
-- ns.InstanceCounts(now): an account's soonest visit stops counting, or, at the limit, the
-- footer's "(12 min)" wait ticks over. nil when no account has any counting.
function ns.InstancesChangeIn(now)
    local wait
    for _, a in ipairs(list) do
        if a.n > 0 then
            local d = a.free - now
            if a.n >= LIMIT then d = NextChange(d, a.free, now) end
            if not wait or d < wait then wait = d end
        end
    end
    return wait
end

-- The row tooltip's lines (Overview.lua): the account's visits counting now, then the
-- character's saves.
function ns.AddLockoutLines(tt, c, now)
    local visits = c.account and Visits(now, c.account) or EMPTY
    if #visits > 0 then
        tt:AddLine(" ")
        tt:AddLine(L["Instances this hour: %s"]:format(CountText(#visits, visits[1].ends, now)))
        for _, v in ipairs(visits) do
            local when = v.run == current and L["inside now"] or L["frees in %s"]:format(Minutes(v.ends - now))
            tt:AddDoubleLine(v.run.name or "?", FirstName(v.key) .. " · " .. when, 1, 1, 1, 1, 1, 1)
        end
    end
    local list = ns.ActiveSaves(c, now)
    if not list or #list == 0 then return end
    tt:AddLine(" ")
    tt:AddLine(L["Lockouts"])
    for _, save in ipairs(list) do
        local name, right = ns.SaveLine(save, now)
        tt:AddDoubleLine(name, right, 1, 1, 1, 1, 1, 1)
    end
end

local function LineTooltip(row)
    local now = time()
    if row.raid then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:AddLine(row.raid)
        for _, key in ipairs(row.keys) do
            local c = ns.db.chars[key] -- nil if forgotten since (it's refilled then too)
            local at = c and c.saves and c.saves[row.raid]
            if at then
                local kills = c.saveKills and c.saveKills[row.raid]
                local left = ns.ExpiryText(at - now)
                GameTooltip:AddDoubleLine(ns.ColoredName(key, c), kills and (kills .. " · " .. left) or left, 1, 1, 1, 1, 1, 1)
            end
        end
        GameTooltip:Show()
    elseif row.visit then
        local run = row.visit.run
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:AddLine(run.name or "?")
        GameTooltip:AddLine(L["Entered %s"]:format(date("%H:%M", run.at)), 1, 1, 1)
        if run == current then
            GameTooltip:AddLine(L["inside now"], 1, 1, 1)
        elseif run.left then
            GameTooltip:AddLine(L["Left %s"]:format(date("%H:%M", run.left)), 1, 1, 1)
        end
        GameTooltip:Show()
    end
end

local function Text(row)
    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ns.SkinText(fs)
    fs:SetWordWrap(false)
    return fs
end

local function Place(fs, row, x, width, text, justify)
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", row, "LEFT", x, 0)
    fs:SetWidth(width - 6)
    fs:SetJustifyH(justify or "LEFT")
    fs:SetText(text)
    fs:Show()
end

local function Line(i)
    local row = lines[i]
    if row then return row end
    row = CreateFrame("Frame", nil, panel)
    row:SetHeight(ROW_HEIGHT)
    row:EnableMouse(true)
    row:SetScript("OnEnter", LineTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ns.GamepadFocusable(row) -- its tooltip shows when the D-pad reaches it
    row.heading = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ns.SkinText(row.heading)
    row.heading:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.a, row.b, row.c = Text(row), Text(row), Text(row)
    row.cells = {}
    lines[i] = row
    return row
end

function FillPanel()
    local now = time()
    ns.PruneSaves(now)
    -- The screen in the window's units: it never grows past it (peer review). Too many
    -- characters to fit across: the raid grid repeats in blocks of what fits; too many rows:
    -- it scrolls (mouse wheel or the page buttons). A window size so big that even its
    -- narrowest layout or fewest rows don't fit (300% on a small screen): it's drawn smaller,
    -- just enough to fit. 0 = not known, no limit.
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local most = math.huge
    if w > 0 then most = w / MIN_WIDTH end
    if h > 0 then most = math.min(most, h / (30 + MIN_ROWS * ROW_HEIGHT + 16 + 66)) end -- title, rows, two gaps, footer
    panel.maxScale = most < ns.WindowScale() and floor(most * 100) / 100 or nil
    ns.FitWindow(panel)
    local scale = math.min(ns.WindowScale(), panel.maxScale or math.huge)
    local sw, sh = w / scale, h / scale
    local delay = 60
    local n, y = 0, -30
    local function Next(gap)
        y = y - (gap or 0)
        n = n + 1
        local row = Line(n)
        row.top = y
        y = y - ROW_HEIGHT
        row.heading:Hide()
        row.a:Hide()
        row.b:Hide()
        row.c:Hide()
        for _, cell in ipairs(row.cells) do cell:Hide() end
        row.raid, row.keys, row.visit = nil, nil, nil
        row:Show()
        return row
    end
    local whenX = NAME_WIDTH + CHAR_WIDTH

    -- Instances this hour, by account.
    local row = Next()
    row.heading:SetText(L["Instances this hour (%d per game account)"]:format(LIMIT))
    row.heading:Show()
    local any = false
    for _, a in ipairs(ns.InstanceCounts(now)) do
        if a.n > 0 then
            any = true
            row = Next()
            Place(row.a, row, 4, whenX, L["%s's account"]:format(FirstName(a.main)))
            Place(row.c, row, whenX, WHEN_WIDTH, CountText(a.n), "RIGHT")
            for _, visit in ipairs(Visits(now, a.id)) do
                delay = NextChange(delay, visit.ends, now)
                row = Next()
                row.visit = visit
                Place(row.a, row, 16, NAME_WIDTH - 12, visit.run.name or (GREY .. "?|r"))
                Place(row.b, row, NAME_WIDTH, CHAR_WIDTH, ns.ColoredName(visit.key, ns.db.chars[visit.key]))
                Place(row.c, row, whenX, WHEN_WIDTH, visit.run == current and L["inside now"]
                    or L["frees in %s"]:format(Minutes(visit.ends - now)), "RIGHT")
            end
        end
    end
    if not any then
        row = Next()
        Place(row.a, row, 16, MIN_WIDTH - 32, GREY .. L["None entered this hour."] .. "|r")
    end

    -- Raid lockouts: raids down, characters with any across.
    row = Next(8)
    row.heading:SetText(L["Raid lockouts"])
    row.heading:Show()
    local keys, raids, resets = {}, {}, {}
    for _, key in ipairs(ns.OverviewOrder()) do
        local list = ns.ActiveSaves(ns.db.chars[key], now)
        if list and #list > 0 then
            keys[#keys + 1] = key
            for _, save in ipairs(list) do
                local name, at = save[1], save[2]
                if not resets[name] then raids[#raids + 1] = name end
                if not resets[name] or at < resets[name] then resets[name] = at end
            end
        end
    end
    sort(raids, function(x, z)
        if resets[x] ~= resets[z] then return resets[x] < resets[z] end
        return x < z
    end)
    for _, at in pairs(resets) do delay = NextChange(delay, at, now) end
    local across = #keys
    if sw > 0 then across = math.max(1, math.min(across, floor((sw - 8 - NAME_WIDTH - 32) / CELL_WIDTH))) end
    if #raids == 0 then
        row = Next()
        Place(row.a, row, 16, MIN_WIDTH - 32, GREY .. L["No lockouts on record. They're read each time you log in on a character."] .. "|r")
    else
        for from = 1, #keys, across do
            local to = math.min(#keys, from + across - 1)
            row = Next(from > 1 and 8 or 0)
            for j = from, to do
                local key = keys[j]
                row.cells[j - from + 1] = row.cells[j - from + 1] or Text(row)
                Place(row.cells[j - from + 1], row, NAME_WIDTH + (j - from) * CELL_WIDTH, CELL_WIDTH, ns.ShortName(key, ns.db.chars[key]), "CENTER")
            end
            for _, name in ipairs(raids) do
                row = Next()
                row.raid, row.keys = name, keys
                Place(row.a, row, 4, NAME_WIDTH, name)
                for j = from, to do
                    local c = ns.db.chars[keys[j]]
                    local at = c.saves and c.saves[name]
                    local text = GREY .. "-|r"
                    if at then text = c.saveKills and c.saveKills[name] or L["Saved"] end
                    row.cells[j - from + 1] = row.cells[j - from + 1] or Text(row)
                    Place(row.cells[j - from + 1], row, NAME_WIDTH + (j - from) * CELL_WIDTH, CELL_WIDTH, text, "CENTER")
                end
            end
        end
    end

    -- The rows that fit, from the offset; the rest hidden. Measured by where they sit, as
    -- the gaps between sections take room too. The title above, the footer below.
    local room = sh > 0 and sh - 30 - 50 or math.huge
    local function Fits(from, to) return lines[from].top - (lines[to].top - ROW_HEIGHT) <= room end
    local function LastFrom(from)
        local i = from
        while i < n and Fits(from, i + 1) do i = i + 1 end
        return math.max(i, math.min(n, from + MIN_ROWS - 1))
    end
    local paging = LastFrom(1) < n
    if paging then
        local lowest = n -- the first row of the last page
        while lowest > 1 and Fits(lowest - 1, n) do lowest = lowest - 1 end
        offset = math.max(0, math.min(offset, lowest - 1))
    else
        offset = 0
    end
    local first = offset + 1
    local last = LastFrom(first)
    local fit = last - first + 1
    local shift = lines[first].top + 30 -- the first shown row at the top
    for i = 1, #lines do
        local r = lines[i]
        if i < first or i > last then
            r:Hide()
        else
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, r.top - shift)
            r:SetPoint("RIGHT", panel, "RIGHT", -8, 0)
        end
    end
    panel.pageRows = fit
    panel.footer:SetText(paging and (GREY .. first .. "-" .. last .. " " .. L["of %d (scroll for more)"]:format(n) .. "|r") or "")
    panel.up:SetShown(paging)
    panel.down:SetShown(paging)
    panel.up:SetEnabled(offset > 0)
    panel.down:SetEnabled(last < n)
    local width = 8 + NAME_WIDTH + across * CELL_WIDTH + 16
    panel:SetWidth(width > MIN_WIDTH and width or MIN_WIDTH)
    panel:SetHeight(-(lines[last].top - shift - ROW_HEIGHT) + 14 + (paging and 22 or 0))
    Refresh(delay)
end

local function Scroll(rows)
    offset = math.max(0, offset + rows)
    FillPanel()
end

local function CreatePanel()
    local ok, f = pcall(CreateFrame, "Frame", "AltsForeverLockoutsFrame", UIParent, "BasicFrameTemplateWithInset")
    if not ok then f = CreateFrame("Frame", "AltsForeverLockoutsFrame", UIParent, "BackdropTemplate") end
    panel = f
    f.lines = lines
    f:SetFrameStrata("HIGH")
    -- Comes to the front when clicked or opened, so our windows never draw through each other.
    f:SetToplevel(true)
    f:HookScript("OnShow", f.Raise)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta) Scroll(-delta * 3) end)
    local title = f.TitleText or f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if not f.TitleText then title:SetPoint("TOP", 0, -6) end
    title:SetText(L["Lockouts"])
    f.footer = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.footer:SetPoint("BOTTOM", f, "BOTTOM", 0, 10)
    ns.SkinText(f.footer)
    -- Page buttons when it doesn't all fit (a controller has no mouse wheel).
    f.down = ns.PageButton(f, false, function() Scroll(f.pageRows or MIN_ROWS) end)
    f.down:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 6)
    f.up = ns.PageButton(f, true, function() Scroll(-(f.pageRows or MIN_ROWS)) end)
    f.up:SetPoint("RIGHT", f.down, "LEFT", -2, 0)
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "AltsForeverLockoutsFrame" end
    ns.SkinWindow(f)
    f:Hide()
    ns.GamepadWindow(f)
    ns.ScaleWindow(f)
end

-- Opens the window beside the overview if it's open (ns.DockToOverview); again closes it.
function ns.ToggleLockouts()
    if not panel then CreatePanel() end
    if panel:IsShown() then return panel:Hide() end
    offset = 0
    FillPanel()
    ns.DockToOverview(panel)
    panel:Show()
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
