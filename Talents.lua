-- Alts Forever talents: which talent tab each character has most points in (their spec,
-- used to pick the stats that matter for upgrades), and each character's Legacy: their
-- rank in Well Rested (faster rested XP and a higher cap, for the rested estimate) and
-- the Legacy points they have left to spend.
--
-- Forever's talents run on retail's trait system (checked in game 2026-10-05):
--  * Class talents are the trait config of type CamelotCombat (4), named after the class,
--    with one tree for all three tabs: no sub-trees and one point pool. The tabs sit side
--    by side, so a talent's tab comes from its column (posX): columns are 600 apart within
--    a tab and about 2200 apart between tabs. One hunter talent (Lightning Reflexes) sits
--    at 102800, past every other column, apparently a slip for 10280, so anything right of
--    the third group counts as the third tab. Left to right is Classic's tab order.
--  * The Legacy trees are the config of type Generic (3). Points are earned by the account
--    but each character spends them separately (Blizzard), up to a cap (16 at launch). The
--    trees share one currency (4225); GetTreeCurrencyInfo gives this character's unspent
--    points (quantity) and spent ones (checked in game 2026-10-12: 13 and 3, cap 16).
-- Read on entering the world and whenever a trait config changes; not a hot path.
local _, ns = ...
if ns.disabled then return end -- another copy of Alts Forever is running (Core.lua)

local L = ns.L

local ipairs, pairs, pcall, sort, type = ipairs, pairs, pcall, table.sort, type
local issecretvalue = issecretvalue or function() return false end

local CLASS_CONFIG, LEGACY_CONFIG = 4, 3
local TAB_GAP = 1500   -- a jump in posX bigger than this starts the next tab
local MIN_POINTS = 10  -- fewer talent points than this: no spec yet
-- Legacy's Well Rested (Adventure tree, 5 ranks): its trait node (tree 1188, spell
-- 1225478; checked in game 2026-10-05).
ns.WELL_RESTED_NODE = 110301
ns.WELL_RESTED_SPELL = 1225478

local function Plain(v)
    if v ~= nil and not issecretvalue(v) then return v end
end

local function ConfigType(name, fallback)
    local t = Enum.TraitConfigType
    return t and t[name] or fallback
end

-- The first config of a type, if the trait system knows any.
local function Config(kind)
    local T = C_Traits
    if not (T and T.GetConfigsByType) then return nil end
    local ok, list = pcall(T.GetConfigsByType, kind)
    return ok and type(list) == "table" and Plain(list[1]) or nil
end

-- Points per tab from a list of { posX, rank }: tabs are the groups of columns.
function ns.TabPoints(nodes)
    local xs, seen = {}, {}
    for _, n in ipairs(nodes) do
        if not seen[n[1]] then
            seen[n[1]] = true
            xs[#xs + 1] = n[1]
        end
    end
    sort(xs)
    local tabOf, tab = {}, 1
    for i, x in ipairs(xs) do
        if i > 1 and x - xs[i - 1] > TAB_GAP then tab = tab + 1 end
        tabOf[x] = tab > 3 and 3 or tab
    end
    local points = { 0, 0, 0 }
    for _, n in ipairs(nodes) do
        local t = tabOf[n[1]]
        points[t] = points[t] + n[2]
    end
    return points
end

-- The tab with the most points, or nil below MIN_POINTS or on a tie for the most.
function ns.SpecFromPoints(points)
    local best, total, tie = 1, 0, false
    for t = 1, 3 do
        total = total + points[t]
        if t > 1 then
            if points[t] > points[best] then best, tie = t, false
            elseif points[t] == points[best] then tie = true end
        end
    end
    if total < MIN_POINTS or tie then return nil end
    return best
end

-- c.spec = the tab with most points (1-3), or nil. Left alone if talents can't be read.
function ns.ScanTalents(c)
    local T = C_Traits
    local config = Config(ConfigType("CamelotCombat", CLASS_CONFIG))
    if not config then return end
    local info = T.GetConfigInfo(config)
    local tree = info and type(info.treeIDs) == "table" and Plain(info.treeIDs[1])
    if not tree then return end
    local nodes = {}
    for _, id in ipairs(T.GetTreeNodes(tree) or {}) do
        local node = T.GetNodeInfo(config, id)
        local x, rank = node and Plain(node.posX), node and Plain(node.currentRank)
        if x and rank then nodes[#nodes + 1] = { x, rank } end
    end
    if #nodes == 0 then return end
    local spec = ns.SpecFromPoints(ns.TabPoints(nodes))
    if spec ~= c.spec then
        c.spec = spec
        if ns.UpgradesChanged then ns.UpgradesChanged() end
    end
end

-- c.wellRested = this character's Well Rested rank (0-5); c.legacySpent = the Legacy points
-- it has spent; db.legacyPool = the points each character can spend in all (the account's
-- earned points, up to the cap). The pool never shrinks: points aren't taken away, and a
-- reading made before the client has the data mustn't lower it. Left alone if unreadable.
-- Returns true if the pool grew (a point was earned).
function ns.ScanLegacy(c, db)
    local T = C_Traits
    local node = ns.WELL_RESTED_NODE
    local config = node and Config(ConfigType("Generic", LEGACY_CONFIG))
    if not config then return end
    local info = T.GetNodeInfo(config, node)
    local rank = info and Plain(info.ID) == node and Plain(info.currentRank)
    if type(rank) == "number" then c.wellRested = rank end
    -- The points are the first currency any of the trees reports: the first of the four
    -- trees (1118) has none, the other three share it (checked in game 2026-10-12).
    local cinfo = T.GetConfigInfo and T.GetConfigInfo(config)
    local trees = cinfo and type(cinfo.treeIDs) == "table" and cinfo.treeIDs
    if not (trees and T.GetTreeCurrencyInfo) then return end
    local left, spent
    for _, tree in ipairs(trees) do
        local ok, list = pcall(T.GetTreeCurrencyInfo, config, Plain(tree), false)
        local cur = ok and type(list) == "table" and list[1]
        if type(cur) == "table" then
            left, spent = Plain(cur.quantity), Plain(cur.spent)
            if type(left) == "number" and type(spent) == "number" then break end
        end
    end
    if type(left) ~= "number" or type(spent) ~= "number" then return end
    c.legacySpent = spent
    local pool, old = left + spent, db.legacyPool
    if old and pool <= old then return end
    db.legacyPool = pool
    return old ~= nil
end

-- Legacy points a character has left to spend, or nil if never read. For a character
-- that's logged out it counts the points the account has earned since.
function ns.LegacyUnspent(c)
    local pool, spent = ns.db.legacyPool, c.legacySpent
    if not (pool and spent) then return nil end
    return pool > spent and pool - spent or 0
end

-- Well Rested's rank for the rested estimate: the character's own, else the account-wide
-- value saved before 0.11.0 (read from whoever logged out last), else none.
function ns.WellRestedRank(c)
    return c.wellRested or ns.db.wellRested or 0
end

-- Well Rested's name in the player's language (the Legacy talent's spell).
function ns.WellRestedName()
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(ns.WELL_RESTED_SPELL)
    if type(name) == "string" and name ~= "" and not issecretvalue(name) then return name end
    return L["Well Rested"]
end

---------------------------------------------------------------------------
-- Reminders in chat: when this character has Legacy points to spend, and when a point is
-- earned. On unless turned off (db.legacyRemindOff).
---------------------------------------------------------------------------
function ns.LegacyRemindersOn() return not ns.db.legacyRemindOff end

function ns.SetLegacyReminders(on)
    ns.db.legacyRemindOff = not on or nil
end

-- At login: this character's unspent points, and Well Rested if it's still levelling.
function ns.RemindLegacy(c)
    local n = ns.LegacyUnspent(c)
    if not (n and n > 0 and ns.LegacyRemindersOn()) then return false end
    ns.Print((n == 1 and L["You have %d Legacy point to spend on this character."]
        or L["You have %d Legacy points to spend on this character."]):format(n))
    local rank = c.wellRested
    if rank and rank < 5 and c.level and c.level < ns.MaxLevel() then
        ns.Print(L["%s is at %d/5 here: each rank builds rested XP faster, up to a higher cap."]:format(ns.WellRestedName(), rank))
    end
    return true
end

-- A point earned: how many characters now have points to spend.
function ns.AnnounceLegacyPoint()
    if not ns.LegacyRemindersOn() then return end
    local count = 0
    for _, c in pairs(ns.db.chars) do
        local n = ns.LegacyUnspent(c)
        if n and n > 0 then count = count + 1 end
    end
    ns.Print(L["Legacy point earned! %d of your characters can spend it (/af legacy lists them)."]:format(count))
end

-- /af legacy: everyone's unspent points and Well Rested rank, most to spend first.
function ns.LegacyLines()
    local list, chars = {}, ns.db.chars
    for key, c in pairs(chars) do
        if ns.LegacyUnspent(c) or c.wellRested then list[#list + 1] = key end
    end
    sort(list, function(a, b)
        local na, nb = ns.LegacyUnspent(chars[a]) or -1, ns.LegacyUnspent(chars[b]) or -1
        if na ~= nb then return na > nb end
        return a < b
    end)
    local wr = ns.WellRestedName()
    for i, key in ipairs(list) do
        local c = chars[key]
        local n = ns.LegacyUnspent(c)
        local parts = {}
        if n then parts[#parts + 1] = n > 0 and ("|cffffd100" .. L["%d to spend"]:format(n) .. "|r") or L["all spent"] end
        if c.wellRested then parts[#parts + 1] = wr .. " " .. c.wellRested .. "/5" end
        list[i] = ns.ColoredName(key, c) .. ": " .. table.concat(parts, " · ")
    end
    return list
end

function ns.StartTalents()
    local char, db = ns.char, ns.db
    local function Legacy()
        if ns.ScanLegacy(char, db) then ns.AnnounceLegacyPoint() end
        if ns.RefreshOverview then ns.RefreshOverview() end
    end
    local first = true
    ns.On("PLAYER_ENTERING_WORLD", function()
        if not first then return end
        first = false
        ns.ScanTalents(char)
        ns.ScanLegacy(char, db)
        -- Remind once the login chat has passed, reading again in case the Legacy data
        -- wasn't in yet. A point earned while logged out needs no announcement of its own.
        local function Remind()
            ns.ScanLegacy(char, db)
            ns.RemindLegacy(char)
        end
        if C_Timer and C_Timer.After then C_Timer.After(6, Remind) else Remind() end
    end)
    ns.On("TRAIT_CONFIG_UPDATED", function()
        ns.ScanTalents(char)
        Legacy()
    end)
    -- Should fire when Legacy points are earned or spent (not yet seen in game).
    ns.On("TRAIT_TREE_CURRENCY_INFO_UPDATED", Legacy)
end
