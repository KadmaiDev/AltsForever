-- Alts Forever character: level, XP, rested XP, location, item level and time played,
-- plus an estimate of the rested XP a character has gained since logging out.
local _, ns = ...

local floor, min, time, type = math.floor, math.min, time, type
local issecretvalue = issecretvalue or function() return false end
local UnitLevel, UnitXP, UnitXPMax = UnitLevel, UnitXP, UnitXPMax
local GetXPExhaustion, IsResting = GetXPExhaustion, IsResting
local GetZoneText, GetBindLocation, GetAverageItemLevel = GetZoneText, GetBindLocation, GetAverageItemLevel

-- Rested XP builds at 5% of a level per 8 hours logged out in an inn or city, a
-- quarter of that anywhere else, up to 150% of a level. The inn rate was measured on
-- Forever (about 4.9%); the rate elsewhere is the classic rule, not yet measured.
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
-- Played time: c.played is total seconds as of c.playedAt.
---------------------------------------------------------------------------
function ns.PlayedNow(c, now)
    if not c.played then return nil end
    if c == ns.char and c.playedAt then return c.played + (now - c.playedAt) end
    return c.played
end

function ns.RecordPlayed(c, total, now)
    if issecretvalue(total) or type(total) ~= "number" then return end
    c.played, c.playedAt = total, now
end

-- The game answers RequestTimePlayed with TIME_PLAYED_MSG, and every chat window
-- listening for that event prints "Total time played". To keep our login request out
-- of chat, those windows stop listening until the answer has arrived. (Wrapping the
-- global ChatFrame_DisplayTimePlayed didn't hide it on build 70009.) A /played typed
-- by the player still prints, and is recorded too.
local muted = {}

local function MuteChat()
    for i = 1, NUM_CHAT_WINDOWS or 10 do
        local frame = _G["ChatFrame" .. i]
        if frame and frame:IsEventRegistered("TIME_PLAYED_MSG") then
            frame:UnregisterEvent("TIME_PLAYED_MSG")
            muted[#muted + 1] = frame
        end
    end
end

local function UnmuteChat()
    for i = #muted, 1, -1 do
        muted[i]:RegisterEvent("TIME_PLAYED_MSG")
        muted[i] = nil
    end
end

local function StartPlayed(char)
    ns.On("TIME_PLAYED_MSG", function(total)
        ns.RecordPlayed(char, total, time())
        -- Listen again a moment later, once every window has had its turn at the event.
        if #muted > 0 then C_Timer.After(1, UnmuteChat) end
    end)
    ns.On("PLAYER_LOGOUT", function()
        local total = ns.PlayedNow(char, time())
        if total then char.played, char.playedAt = total, time() end
    end)
    if not (RequestTimePlayed and C_Timer) then return end
    C_Timer.After(3, function()
        MuteChat()
        RequestTimePlayed()
        C_Timer.After(10, UnmuteChat) -- in case no answer comes
    end)
end

function ns.StartCharacter()
    local char = ns.char
    local function Scan() ns.ScanCharacter(char) end
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
    StartPlayed(char)
end
