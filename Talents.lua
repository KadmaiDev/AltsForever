-- Alts Forever talents: which talent tab each character has most points in (their spec,
-- used to pick the stats that matter for upgrades), and the account's rank in Legacy's
-- Well Rested (faster rested XP and a higher cap, for the rested estimate).
--
-- Forever's talents run on retail's trait system (checked in game 2026-10-05):
--  * Class talents are the trait config of type CamelotCombat (4), named after the class,
--    with one tree for all three tabs: no sub-trees and one point pool. The tabs sit side
--    by side, so a talent's tab comes from its column (posX): columns are 600 apart within
--    a tab and about 2200 apart between tabs. One hunter talent (Lightning Reflexes) sits
--    at 102800, past every other column, apparently a slip for 10280, so anything right of
--    the third group counts as the third tab. Left to right is Classic's tab order.
--  * The Legacy tree is the account-wide config of type Generic (3).
-- Read on entering the world and whenever a trait config changes; not a hot path.
local _, ns = ...
if ns.disabled then return end -- another copy of Alts Forever is running (Core.lua)

local ipairs, pcall, sort, type = ipairs, pcall, table.sort, type
local issecretvalue = issecretvalue or function() return false end

local CLASS_CONFIG, LEGACY_CONFIG = 4, 3
local TAB_GAP = 1500   -- a jump in posX bigger than this starts the next tab
local MIN_POINTS = 10  -- fewer talent points than this: no spec yet
-- Legacy's Well Rested (Adventure tree, 5 ranks): its trait node (tree 1188, spell
-- 1225478; checked in game 2026-10-05).
ns.WELL_RESTED_NODE = 110301

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

-- db.wellRested = the account's Well Rested rank (0-5). Left alone if it can't be read.
function ns.ScanLegacy(db)
    local node = ns.WELL_RESTED_NODE
    local config = node and Config(ConfigType("Generic", LEGACY_CONFIG))
    if not config then return end
    local info = C_Traits.GetNodeInfo(config, node)
    local rank = info and Plain(info.ID) == node and Plain(info.currentRank)
    if type(rank) == "number" then db.wellRested = rank end
end

function ns.StartTalents()
    local char, db = ns.char, ns.db
    local function Scan()
        ns.ScanTalents(char)
        ns.ScanLegacy(db)
    end
    local first = true
    ns.On("PLAYER_ENTERING_WORLD", function()
        if not first then return end
        first = false
        Scan()
    end)
    ns.On("TRAIT_CONFIG_UPDATED", Scan)
end
