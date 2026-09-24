-- Alts Forever character: level, XP, rested XP, location and item level, plus an
-- estimate of the rested XP a character has gained since logging out.
local _, ns = ...

local floor, min, time = math.floor, math.min, time
local issecretvalue = issecretvalue or function() return false end
local UnitLevel, UnitXP, UnitXPMax = UnitLevel, UnitXP, UnitXPMax
local GetXPExhaustion, IsResting = GetXPExhaustion, IsResting
local GetZoneText, GetBindLocation, GetAverageItemLevel = GetZoneText, GetBindLocation, GetAverageItemLevel

-- Rested XP builds at 5% of a level per 8 hours logged out in an inn or city, a
-- quarter of that anywhere else, up to 150% of a level.
local RESTED_CAP = 1.5
local RESTED_PER_SECOND = 0.05 / (8 * 3600)
local AWAY_RATE = 0.25

local function Plain(v)
    if v ~= nil and not issecretvalue(v) then return v end
end

function ns.MaxLevel()
    return GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
end

-- While logging out the game already reports XP, max XP and item level as 0 and
-- the character as not resting, so a reading with max XP 0 is ignored rather than
-- stored (it would wipe the real values).
function ns.ScanCharacter(c)
    local level, xp, xpMax = Plain(UnitLevel("player")), Plain(UnitXP("player")), Plain(UnitXPMax("player"))
    if level and level > 0 then c.level = level end
    if xp and xpMax and xpMax > 0 then
        c.xp, c.xpMax = xp, xpMax
        c.rested = Plain(GetXPExhaustion()) or 0
        c.resting = IsResting() and true or nil
    end
    local zone = GetZoneText()
    if zone and zone ~= "" and not issecretvalue(zone) then c.zone = zone end
    local hearth = GetBindLocation()
    if hearth and hearth ~= "" then c.hearth = hearth end
    local _, equipped = GetAverageItemLevel()
    if Plain(equipped) and equipped > 0 then c.ilvl = floor(equipped + 0.5) end
    c.updated = time()
end

-- Returns rested XP now, the cap, and seconds until full, or nil at max level.
-- For characters that are logged out it adds what they've gained since.
function ns.RestedNow(c, now)
    local xpMax = c.xpMax
    if not xpMax or xpMax == 0 or not c.rested then return nil end
    if c.level and c.level >= ns.MaxLevel() then return nil end
    local cap = xpMax * RESTED_CAP
    local rate = xpMax * RESTED_PER_SECOND * (c.resting and 1 or AWAY_RATE)
    local elapsed = (c ~= ns.char and c.updated) and (now - c.updated) or 0
    local rested = min(cap, c.rested + elapsed * rate)
    return rested, cap, rested < cap and (cap - rested) / rate or 0
end

---------------------------------------------------------------------------
-- Rested XP check: compares what was saved at logout with the real rested XP after
-- logging back in, to test the assumed rates on this client.
---------------------------------------------------------------------------
local MIN_AWAY = 30 * 60
local MAX_CHECKS = 20

-- Returns nil when there's nothing reliable to measure, otherwise a result:
-- seconds away, resting, observed and expected % of a level per 8 hours, capped.
function ns.CheckRested(before, c, now)
    if not (before.updated and before.rested and before.xpMax and before.xpMax > 0) then return nil end
    if before.level ~= c.level or before.xpMax ~= c.xpMax or not c.rested then return nil end
    if c.level >= ns.MaxLevel() then return nil end
    local away = now - before.updated
    if away < MIN_AWAY then return nil end
    local cap = c.xpMax * RESTED_CAP
    if before.rested >= cap - 1 then return nil end -- already full: nothing to measure
    local blocks = away / (8 * 3600)
    local expected = 5 * (before.resting and 1 or AWAY_RATE)
    local observed = (c.rested - before.rested) / c.xpMax * 100 / blocks
    return {
        t = now, away = away, resting = before.resting and true or nil,
        observed = floor(observed * 100 + 0.5) / 100, expected = expected,
        capped = c.rested >= cap - 1 or nil,
    }
end

-- Within 10% of the assumption counts as a match; a capped result matches as long
-- as the assumed rate would also have reached the cap.
function ns.RestedCheckMatches(r)
    if r.capped then return r.observed <= r.expected * 1.1 end
    return math.abs(r.observed - r.expected) <= r.expected * 0.1
end

function ns.RestedCheckText(r)
    local h, m = floor(r.away / 3600), floor(r.away % 3600 / 60)
    local where = r.resting and "in an inn or city" or "out in the world"
    local ok = ns.RestedCheckMatches(r)
    local rate = r.capped and ("reached the cap (at least " .. r.observed .. "%)") or ("+" .. r.observed .. "%")
    return "Rested XP check: " .. h .. "h " .. m .. "m logged out " .. where .. ": " .. rate
        .. " of a level per 8h (assumed " .. r.expected .. "%) "
        .. (ok and "|cff20ff20matches|r" or "|cffff2020differs - please report|r")
end

function ns.StartCharacter()
    local char = ns.char
    local function Scan() ns.ScanCharacter(char) end
    -- What was saved at the last logout, before this session's scans replace it.
    local before = { rested = char.rested, resting = char.resting, updated = char.updated,
        level = char.level, xpMax = char.xpMax }
    for _, event in ipairs({
        "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "PLAYER_UPDATE_RESTING",
        "ZONE_CHANGED_NEW_AREA", "HEARTHSTONE_BOUND", "PLAYER_AVG_ITEM_LEVEL_UPDATE",
        "PLAYER_ENTERING_WORLD",
    }) do
        ns.On(event, Scan)
    end
    -- Don't read stats at logout (they're already zeroed); just note the time, which
    -- is where the offline rested XP estimate starts from.
    ns.On("PLAYER_LOGOUT", function() char.updated = time() end)
    Scan()

    -- Give the game a moment to report rested XP, then compare.
    if C_Timer then
        C_Timer.After(10, function()
            Scan()
            local r = ns.CheckRested(before, char, time())
            if not r then return end
            local db = ns.db
            db.restedChecks = db.restedChecks or {}
            r.who = ns.charKey
            table.insert(db.restedChecks, 1, r)
            db.restedChecks[MAX_CHECKS + 1] = nil
            if not db.restCheckOff then ns.Print(ns.RestedCheckText(r)) end
        end)
    end
end
