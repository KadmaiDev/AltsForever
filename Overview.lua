-- Alts Forever overview: a window (/af) listing every character with level, rested
-- XP, gold, professions, location, time played and when they were last played. It's
-- only built the first time it's opened, and only refreshes while it's showing.
local _, ns = ...
if ns.disabled then return end -- another copy of Alts Forever is running (Core.lua)
local L = ns.L

local floor, max, pairs, time = math.floor, math.max, pairs, time
local issecretvalue = issecretvalue or function() return false end
local ipairs = ipairs
local GetCoinTextureString = C_CurrencyInfo.GetCoinTextureString

local GREY = "|cff9d9d9d"
-- Something to do on that character: rested filling slowly, Legacy points to spend.
local ATTENTION = "|cffff8000"
local MAX_PROFESSION = 300 -- the last rank's maximum on Forever (Classic ruleset)
local ROW_HEIGHT = 20
local COLUMNS = {
    -- `sort`: clicking the title orders the characters by it (SORTS, below). `id`: what the
    -- column is hidden by (db.hiddenColumns; the four profession cells go together, and
    -- the Character column, without one, always shows).
    { title = L["Character"], width = 180, sort = "name" },
    { title = L["Level"], width = 80, sort = "level", id = "level" },
    { title = L["Rested"], width = 70, sort = "rested", id = "rested" },
    -- How long until rested XP is full at the rate where they logged out (a player's
    -- request, 2026-11-23; the row tooltip already said it).
    { title = L["Full in"], width = 60, sort = "restedFull", id = "restedfull",
        tip = L["How long until each character's rested XP is full, at the rate where they logged out: orange outside an inn or city, where it fills four times slower."] },
    -- Well Rested's rank beside Rested, then Legacy points spent of the total: short
    -- values under wider titles, so both are centred.
    { title = L["Well Rested"], width = 84, center = true, sort = "wellRested", id = "wellrested" },
    { title = L["Legacy"], width = 60, center = true, sort = "legacy", id = "legacy" },
    -- Whole gold only (ns.GoldShort): the row tooltip has it to the copper.
    { title = L["Gold"], width = 70, right = true, sort = "gold", id = "gold" },
    -- Each main profession gets its icon and its skill (ns.ProfIconCells), so the skill
    -- numbers line up; the row tooltip names them. The gap separates it from the
    -- right-aligned gold. `cell`: the text's width where it isn't width - 8; `titleWidth`:
    -- the title runs over the cells after it, which have none.
    { title = L["Professions"], width = 20, cell = 16, titleWidth = 120, gap = 16, id = "professions" },
    { title = "", width = 30, id = "professions" },
    { title = "", width = 20, cell = 16, gap = 6, id = "professions" },
    { title = "", width = 30, id = "professions" },
    -- Secondary professions (a player's request, 2026-11-24): the same three for everyone,
    -- so the icon is the title and the cell just the skill. Found by skill line (`line`),
    -- so it works in every language; hidden and shown together under `menu`.
    { title = "|TInterface\\Icons\\INV_Misc_Food_15:14:14:0:0:64:64:5:59:5:59|t", width = 30, gap = 10,
        center = true, sort = "cooking", id = "secondary", line = 185, menu = L["Secondary professions"] },
    { title = "|TInterface\\Icons\\Spell_Holy_SealOfSacrifice:14:14:0:0:64:64:5:59:5:59|t", width = 30,
        center = true, sort = "firstaid", id = "secondary", line = 129 },
    { title = "|TInterface\\Icons\\Trade_Fishing:14:14:0:0:64:64:5:59:5:59|t", width = 30,
        center = true, sort = "fishing", id = "secondary", line = 356 },
    { title = L["Mail"], width = 60, gap = 16, sort = "mail", id = "mail" },
    -- Free slots of all slots (bags without the keyring; bank tabs as last visited), as
    -- Altoholic shows them; pointing at one lists each bag (a player's request, 2026-11-19).
    { title = L["Bags"], width = 58, center = true, sort = "bags", id = "bags", space = "bags",
        tip = L["Free slots / all slots in each character's bags (not the keyring). Point at one to see each bag; click it to open their bags."] },
    { title = L["Bank"], width = 58, center = true, sort = "bank", id = "bank", space = "bank",
        tip = L["Free slots / all slots in each character's bank, as it was last visited. Point at one to see each tab; click it to open their bank."] },
    -- The account's instances this hour, then raid and dungeon saves running (the row
    -- tooltip lists both): "2/10 <key>1".
    { title = L["Lockouts"], width = 76, center = true, id = "lockouts" },
    -- Profession cooldowns (Mooncloth, transmutes): "Ready", "2 ready" or the soonest
    -- "2d 4h"; pointing at one lists them (a player's request, 2026-11-22).
    -- `auto`: shown only once some character has one, unless the player chose (hiddenColumns
    -- false = shown, true = hidden), so most players never see an empty column.
    { title = L["Cooldowns"], width = 70, center = true, sort = "cooldowns", id = "cooldowns", hover = "cooldowns",
        auto = function() return ns.AnyCooldowns() end,
        tip = L["When each character's profession cooldowns (Mooncloth, transmutes...) are ready. Point at one to see each; click it to open their professions."] },
    { title = L["Zone"], width = 140, sort = "zone", id = "zone" },
    { title = L["Played"], width = 70, right = true, sort = "played", id = "played" },
    { title = L["Last seen"], width = 80, right = true, sort = "seen", id = "lastseen" },
}
-- The columns that can be hidden, in order, each once: { id, title }; AUTO = by id, the
-- columns that show themselves only when they have something to show.
local HIDEABLE, AUTO = {}, {}
do
    local listed = {}
    for _, col in ipairs(COLUMNS) do
        if col.id and col.title ~= "" and not listed[col.id] then
            listed[col.id] = true
            HIDEABLE[#HIDEABLE + 1] = { col.id, col.menu or col.title }
        end
        if col.auto then AUTO[col.id] = col.auto end
    end
end

-- Whether the column with this id shows: hidden by the player (true), shown by the player
-- (false, kept only for an `auto` column), else its `auto` answer, else shown.
local function Visible(id, hidden)
    local chosen = nil
    if id and type(hidden) == "table" then chosen = hidden[id] end
    if chosen == true then return false end
    if chosen == false or not (id and AUTO[id]) then return true end
    return AUTO[id]() == true
end
-- Never narrower than this, however many columns are hidden: the title bar's buttons and
-- the footer need the room.
local MIN_WIDTH = 560
local LIGHT = "|cffc0c0c0"
-- After a pinned character's name: the game's gold star.
local PIN = " |TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:0|t"

---------------------------------------------------------------------------
-- Text helpers (no UI, so they can be tested)
---------------------------------------------------------------------------
function ns.FormatAgo(seconds)
    if seconds < 3600 then return L["<1h"] end
    if seconds < 86400 then return L["%dh ago"]:format(floor(seconds / 3600)) end
    return L["%dd ago"]:format(floor(seconds / 86400))
end

local function Duration(seconds)
    local d, h = floor(seconds / 86400), floor(seconds % 86400 / 3600)
    if d > 0 then return L["%dd %dh"]:format(d, h) end
    return L["%dh"]:format(max(h, 1))
end

-- Time until rested XP is full: "2d 4h", orange while filling outside an inn or city (as
-- the Rested cell), blank when full or at max level, "?" when the level isn't known.
function ns.RestedFullText(c, now)
    if not c.level then return GREY .. "?|r" end
    local rested, cap, left = ns.RestedNow(c, now)
    if not rested or rested >= cap then return "" end
    local text = Duration(left)
    return c.resting and text or (ATTENTION .. text .. "|r")
end

-- Legacy points spent of the total they can spend ("3/16", orange while some are left) and
-- Well Rested's rank; "?" if not read yet.
function ns.LegacyCells(c)
    local n = ns.LegacyUnspent(c)
    local points = GREY .. "?|r"
    if n then
        local text = c.legacySpent .. "/" .. ns.db.legacyPool
        points = n > 0 and (ATTENTION .. text .. "|r") or text
    end
    local rank = c.wellRested
    return points, rank and (rank .. "/5") or (GREY .. "?|r")
end

-- The level and, below max level, how far into it: the overview shows them in two
-- cells so the percentages line up.
function ns.LevelParts(c)
    if not c.level then return GREY .. "?|r", "" end
    if c.level >= ns.MaxLevel() or not c.xp or not c.xpMax or c.xpMax == 0 then return tostring(c.level), "" end
    -- Multiply first: 5700 / 10000 * 100 is 56.99... in floating point.
    return tostring(c.level), GREY .. floor(c.xp * 100 / c.xpMax) .. "%|r"
end

function ns.LevelText(c)
    local level, pct = ns.LevelParts(c)
    return pct == "" and level or (level .. "  " .. pct)
end

-- Rested as a share of a level: blue when full, orange while filling outside an inn or city
-- (a quarter of the speed), "-" at max level, "?" if not recorded yet.
function ns.RestedText(c, now)
    if not c.level then return GREY .. "?|r" end
    local rested, cap = ns.RestedNow(c, now)
    if not rested then return GREY .. "-|r" end
    local pct = floor(rested / c.xpMax * 100 + 0.5)
    if rested >= cap then return "|cff4da6ff" .. pct .. "%|r" end
    if not c.resting then return ATTENTION .. pct .. "%|r" end
    return pct .. "%"
end

-- The four profession cells: name, skill, name, skill.
function ns.ProfCells(c)
    local p = c.profs
    if not p then return GREY .. "?|r", "", "", "" end
    if not c.prof1 and not c.prof2 then return GREY .. "-|r", "", "", "" end
    local function Cell(name)
        if not name then return "", "" end
        return LIGHT .. name .. "|r", tostring(p[name] or "?")
    end
    local n1, s1 = Cell(c.prof1)
    local n2, s2 = Cell(c.prof2)
    return n1, s1, n2, s2
end

-- The overview's four profession cells: icon, skill, icon, skill (the names take room the
-- other columns need; owner, 2026-11-24, after a player asked for a narrower window). An
-- icon's text is kept per profession, so a refresh builds none; a profession without one
-- (Recipes.lua's ns.ProfessionArt finds none) shows its first three letters.
local profIcons = {}
local function ProfIcon(name)
    local text = profIcons[name]
    if text then return text end
    local icon = ns.ProfessionArt and select(2, ns.ProfessionArt(name))
    if not icon then return LIGHT .. name:sub(1, 3) .. "|r" end
    text = "|T" .. icon .. ":14:14:0:0:64:64:5:59:5:59|t"
    profIcons[name] = text
    return text
end

function ns.ProfIconCells(c)
    local p = c.profs
    if not p then return GREY .. "?|r", "", "", "" end
    if not c.prof1 and not c.prof2 then return GREY .. "-|r", "", "", "" end
    local function Cell(name)
        if not name then return "", "" end
        return ProfIcon(name), tostring(p[name] or "?")
    end
    local i1, s1 = Cell(c.prof1)
    local i2, s2 = Cell(c.prof2)
    return i1, s1, i2, s2
end

-- A secondary profession's name in the player's language, from its skill line (Cooking 185,
-- First Aid 129, Fishing 356), as Gathering() below; kept once the game has given it.
local lineNames = {}
function ns.ProfessionLineName(line)
    local name = lineNames[line]
    if name then return name end
    local ts = C_TradeSkillUI
    name = ts and ts.GetTradeSkillDisplayName and ts.GetTradeSkillDisplayName(line)
    if issecretvalue(name) or type(name) ~= "string" or name == "" then return nil end
    lineNames[line] = name
    return name
end

-- A profession name's skill line, as Recipes.lua's ns.ProfessionArt knows it (the skill
-- scan's db.profArt, else the game's names in this language); kept once found.
local nameLines = {}
local function NameLine(name)
    local line = nameLines[name]
    if line then return line end
    line = ns.ProfessionArt and (ns.ProfessionArt(name))
    if line then nameLines[name] = line end
    return line
end

-- A character's skill in the profession with this skill line, or nil if they haven't
-- learned it (or it isn't known yet). By this client's name for it first; else by each of
-- their professions' skill line, as a character synced from a client in another language
-- keeps its names ("Kochkunst"), with db.profArt saying which line that is (peer review,
-- 2026-11-24).
function ns.LineSkill(c, line)
    local profs = c.profs
    if not profs then return nil end
    local name = ns.ProfessionLineName(line)
    local skill = name and profs[name]
    if type(skill) == "number" then return skill end
    for other, s in pairs(profs) do
        if type(s) == "number" and other ~= name and NameLine(other) == line then return s end
    end
    return nil
end

-- Gold in the overview's narrow column: whole gold with the coin ("1,234" and the gold
-- icon); under a gold, silver and copper as the game writes them.
local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local BigNumber = BreakUpLargeNumbers or tostring
function ns.GoldShort(copper)
    if copper >= 10000 then return BigNumber(floor(copper / 10000)) .. GOLD_ICON end
    return GetCoinTextureString(copper)
end

-- Time until the soonest valuable mail expires; blank if none, "?" if the mailbox
-- has never been opened on that character.
-- Free slots / all slots in a character's bags or bank: orange once a tenth or less is
-- free, "?" when not known (bank never visited).
function ns.SpaceCell(free, total)
    local n = free * 10 <= total and (ATTENTION .. free .. "|r") or tostring(free)
    return n .. GREY .. "/" .. total .. "|r"
end

function ns.SpaceText(c, which)
    local free, total = ns.BagSpace(c, which)
    if not free then return GREY .. "?|r" end
    return ns.SpaceCell(free, total)
end

function ns.MailText(c, now)
    if not c.mail then return GREY .. "?|r" end
    if not c.mailExpires then return "" end
    local left = c.mailExpires - now
    return ns.ExpiryColor(left) .. ns.ExpiryText(left) .. "|r"
end

-- Time played as "12d 5h", "5h 20m" or "20m"; "?" if not recorded yet.
function ns.FormatPlayed(seconds)
    local d, h, m = floor(seconds / 86400), floor(seconds % 86400 / 3600), floor(seconds % 3600 / 60)
    if d > 0 then return L["%dd %dh"]:format(d, h) end
    if h > 0 then return L["%dh %dm"]:format(h, m) end
    return L["%dm"]:format(m)
end

function ns.PlayedText(c, now)
    local played = ns.PlayedNow(c, now)
    return played and ns.FormatPlayed(played) or (GREY .. "?|r")
end

function ns.SeenText(key, c, now)
    if key == ns.charKey then return "|cff20ff20" .. L["Online"] .. "|r" end
    local t = c.updated or c.seen
    return t and ns.FormatAgo(now - t) or (GREY .. "?|r")
end

-- What the overview can be ordered by (a column's `sort`): the value compared, nil when
-- it isn't known (those go last either way), and `up` when the natural order is smallest
-- first (names, zones, the mail expiring soonest); the rest start with the most.
local SORTS = {
    name = { up = true, value = function(key) return key end },
    level = { value = function(_, c)
        if not c.level then return nil end
        local into = (c.xp and c.xpMax and c.xpMax > 0) and c.xp / c.xpMax or 0
        return c.level + (into < 1 and into or 0)
    end },
    rested = { value = function(_, c, now)
        local rested = ns.RestedNow(c, now)
        return rested and rested / c.xpMax or nil
    end },
    -- Soonest full first (full already = 0); max level and unknown last.
    restedFull = { up = true, value = function(_, c, now)
        local _, _, left = ns.RestedNow(c, now)
        return left
    end },
    wellRested = { value = function(_, c) return c.wellRested end },
    legacy = { value = function(_, c) return ns.LegacyUnspent(c) end }, -- points left to spend
    gold = { value = function(_, c) return c.money end },
    -- The highest skill first; those who haven't learned it last.
    cooking = { value = function(_, c) return ns.LineSkill(c, 185) end },
    firstaid = { value = function(_, c) return ns.LineSkill(c, 129) end },
    fishing = { value = function(_, c) return ns.LineSkill(c, 356) end },
    mail = { up = true, value = function(_, c) return c.mailExpires end },
    -- Fewest free slots first: who needs to clear out.
    bags = { up = true, value = function(_, c) return (ns.BagSpace(c, "bags")) end },
    bank = { up = true, value = function(_, c) return (ns.BagSpace(c, "bank")) end },
    -- The most cooldowns ready first, then the soonest ready.
    cooldowns = { up = true, value = function(_, c, now) return ns.CooldownSortValue(c, now) end },
    zone = { up = true, value = function(_, c) return c.zone end },
    played = { value = function(_, c, now) return ns.PlayedNow(c, now) end },
    seen = { value = function(key, c, now) return key == ns.charKey and now or c.updated or c.seen end },
}

-- The order chosen by clicking a column title: db.overviewSort (a SORTS key; nil = Level)
-- and db.overviewSortRev (true = the other way round). Level in its natural order is the
-- default, which also keeps you first, and saves nothing.
function ns.OverviewSort()
    local db = ns.db
    local name = SORTS[db.overviewSort] and db.overviewSort or "level"
    return name, db.overviewSortRev == true
end

-- A click on a column title: that column in its natural order, or the other way round
-- if it's already the one.
function ns.SortOverview(name)
    if not SORTS[name] then return end
    local db = ns.db
    local current, rev = ns.OverviewSort()
    db.overviewSort = name ~= "level" and name or nil
    db.overviewSortRev = (name == current and not rev) or nil
    ns.RefreshOverview(true)
end

-- Character keys in display order: you first, then by level, then by name; or, with
-- another order chosen (ns.OverviewSort), everyone by that, you among them, ties by level
-- and name. Once two rulesets or both factions are known, your group's characters come
-- first, then each other group's, then any whose ruleset isn't known yet, each group in
-- that order; ns.overviewSplit says so (the overview then heads each group).
local order = {}
local parts = {}
local values = {}
local function Group(c) return ns.GroupKey(c, parts[1], parts[2]) end

-- Pinned characters (a player's request, 2026-11-12): db.pinned lists full names in the
-- player's own order. They head their group in that order whatever the overview is sorted
-- by (the character you're on still comes first in the default order); sorting orders
-- only the rest. Names of characters no longer known are skipped, and dropped on the next
-- change. `pinRank` is each pinned character's place, read again for every ordering.
local pinRank = {}

local function ReadPins()
    for key in pairs(pinRank) do pinRank[key] = nil end
    local list, chars = ns.db.pinned, ns.db.chars
    if type(list) ~= "table" then return end
    local n = 0
    for _, key in ipairs(list) do
        if type(key) == "string" and chars[key] and not pinRank[key] then
            n = n + 1
            pinRank[key] = n
        end
    end
end

-- The saved list, tidied in place: known characters only, each once.
local function Pins()
    ReadPins()
    local list = type(ns.db.pinned) == "table" and ns.db.pinned or {}
    local n = 0
    for i = 1, #list do
        local key = list[i]
        if pinRank[key] == n + 1 then
            n = n + 1
            list[n] = key
        end
    end
    for i = #list, n + 1, -1 do list[i] = nil end
    return list
end

function ns.IsPinned(key)
    ReadPins()
    return pinRank[key] ~= nil
end

function ns.SetPinned(key, on)
    local list = Pins()
    for i, k in ipairs(list) do
        if k == key then
            table.remove(list, i)
            break
        end
    end
    if on and ns.db.chars[key] then list[#list + 1] = key end
    ns.db.pinned = #list > 0 and list or nil
    ns.RefreshOverview()
end

-- The pinned character a move up (-1) or down (1) would swap places with: the next one
-- that way in the same group (others' pins lie between them in the list); nil at the end.
local function Neighbour(list, key, dir)
    local chars = ns.db.chars
    parts[1], parts[2] = ns.GroupParts()
    local mine = Group(chars[key])
    local at
    for i, k in ipairs(list) do
        if k == key then at = i end
    end
    if not at then return nil end
    local i = at + dir
    while list[i] do
        if Group(chars[list[i]]) == mine then return at, i end
        i = i + dir
    end
    return nil
end

function ns.CanMovePin(key, dir)
    return Neighbour(Pins(), key, dir) ~= nil
end

function ns.MovePin(key, dir)
    local list = Pins()
    local at, other = Neighbour(list, key, dir)
    if not at then return end
    list[at], list[other] = list[other], list[at]
    ns.RefreshOverview()
end

-- The comparison reads these, set by ns.OverviewOrder for each sort: nothing is created
-- per call.
local sChars, sSplit, sMine, sBy, sAsc

local function Rank(g)
    if g == sMine then return 0 end
    return g:sub(1, 2) == "?|" and 2 or 1
end

local function Before(a, b)
    local ca, cb = sChars[a], sChars[b]
    if sSplit then
        local ga, gb = Group(ca), Group(cb)
        if ga ~= gb then
            local ra, rb = Rank(ga), Rank(gb)
            if ra ~= rb then return ra < rb end
            return ga < gb
        end
    end
    local pa, pb = pinRank[a], pinRank[b]
    if pa or pb then
        if pa and pb then return pa < pb end
        return pa ~= nil
    end
    if sBy then
        local va, vb = values[a], values[b]
        if va ~= vb then
            if va == nil then return false end
            if vb == nil then return true end
            if sAsc then return va < vb end
            return va > vb
        end
    end
    local la, lb = ca.level or 0, cb.level or 0
    if la ~= lb then return la > lb end
    return a < b
end

function ns.OverviewOrder()
    local chars = ns.db.chars
    local name, rev = ns.OverviewSort()
    local by = (name ~= "level" or rev) and SORTS[name] or nil
    for i = #order, 1, -1 do order[i] = nil end
    for key in pairs(chars) do
        if by or key ~= ns.charKey then order[#order + 1] = key end
    end
    if by then
        local now = time()
        for key in pairs(values) do values[key] = nil end
        for _, key in ipairs(order) do values[key] = by.value(key, chars[key], now) end
    end
    parts[1], parts[2] = ns.GroupParts()
    local split = parts[1] or parts[2]
    ns.overviewSplit = split
    ReadPins()
    sChars, sSplit, sMine, sBy = chars, split, Group(ns.char), by
    sAsc = by and (by.up == true) ~= rev
    table.sort(order, Before)
    sChars = nil
    if not by then table.insert(order, 1, ns.charKey) end
    return order
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local frame, rows, heads, footer

local NO_LABELS, NOTE_LEFT = {}, { [2] = true }
-- Gathering professions by their game IDs (Fishing 356, Herbalism 182, Skinning 393), so
-- the check works in every language: the game names them in the player's language. The
-- set is kept once every name is known (profession data may not be loaded at first).
local GATHERING_IDS = { 356, 182, 393 }
local gathering
local function Gathering()
    if gathering then return gathering end
    local set, complete = {}, true
    local ts = C_TradeSkillUI
    for _, id in ipairs(GATHERING_IDS) do
        local name = ts and ts.GetTradeSkillDisplayName and ts.GetTradeSkillDisplayName(id)
        if not issecretvalue(name) and type(name) == "string" and name ~= "" then
            set[name] = true
        else
            complete = false
        end
    end
    if complete then gathering = set end
    return set
end
local function ByFirst(a, b) return a[1] < b[1] end

local function RowTooltip(row)
    local key = row.key
    local c = key and ns.db.chars[key]
    if not c then return end
    local now = time()
    local tt = GameTooltip
    tt:SetOwner(row, "ANCHOR_RIGHT")
    tt:AddLine(ns.ColoredName(key, c))
    if c.level then
        local line = L["Level %d"]:format(c.level)
        if c.xp and c.xpMax and c.xpMax > 0 and c.level < ns.MaxLevel() then
            line = line .. "  " .. GREY .. L["(%d / %d XP)"]:format(c.xp, c.xpMax) .. "|r"
        end
        tt:AddLine(line, 1, 1, 1)
    end
    local rested, cap, toFull = ns.RestedNow(c, now)
    if rested then
        local where = c.resting and L["logged out in an inn or city"] or L["logged out in the world"]
        tt:AddDoubleLine(L["Rested"], L["%d XP (%s)"]:format(floor(rested), ns.RestedText(c, now)), 1, 0.82, 0, 1, 1, 1)
        if rested < cap then
            tt:AddLine(GREY .. L["Full in %s, %s"]:format(Duration(toFull), where) .. "|r")
        end
    end
    if c.wellRested then tt:AddDoubleLine(ns.WellRestedName(), c.wellRested .. "/5", 1, 0.82, 0, 1, 1, 1) end
    local unspent = ns.LegacyUnspent(c)
    if unspent then
        tt:AddDoubleLine(L["Legacy points"], unspent > 0 and (ATTENTION .. L["%d to spend"]:format(unspent) .. "|r")
            or L["all spent"], 1, 0.82, 0, 1, 1, 1)
    end
    if c.mailExpires then
        local left = c.mailExpires - now
        tt:AddDoubleLine(L["Mail expires"], ns.ExpiryColor(left) .. ns.ExpiryText(left) .. "|r", 1, 0.82, 0, 1, 1, 1)
        tt:AddLine(GREY .. (c.mailDeletes and L["The soonest will be deleted, not returned"] or L["The soonest goes back to its sender"]) .. "|r")
    end
    if c.hearth then tt:AddDoubleLine(L["Hearthstone"], ns.HearthText(c, now), 1, 0.82, 0, 1, 1, 1) end
    if c.played then tt:AddDoubleLine(L["Played"], ns.PlayedText(c, now), 1, 0.82, 0, 1, 1, 1) end
    if c.ilvl then tt:AddDoubleLine(L["Item level"], c.ilvl, 1, 0.82, 0, 1, 1, 1) end
    if c.money then tt:AddDoubleLine(L["Gold"], GetCoinTextureString(c.money), 1, 0.82, 0, 1, 1, 1) end
    -- Professions: name, skill and a note, in columns (lined up once shown, below).
    local profRows, profFirst
    if c.profs and next(c.profs) then
        tt:AddLine(" ")
        local skillups = ns.SkillupsOn()
        profRows = {}
        for name, skill in pairs(c.profs) do
            local note = ""
            if skillups then
                local n = ns.SkillupCount(c, name)
                if ns.AtRankCap(c, name) then
                    -- At the final maximum there's nothing to train, so say nothing.
                    if skill < MAX_PROFESSION then note = GREY .. L["(train to skill up)"] .. "|r" end
                elseif n and (n > 0 or not Gathering()[name]) and next(c.recipes[name]) then
                    -- Gathering professions level by gathering; their few recipes (Fish
                    -- Bowl, Camp Chair) are novelties, so "0" there is noise.
                    note = GREY .. (n == 1 and L["(%d skill-up recipe)"] or L["(%d skill-up recipes)"]):format(n) .. "|r"
                end
            end
            profRows[#profRows + 1] = { name, tostring(skill), note }
        end
        table.sort(profRows, ByFirst)
        profFirst = tt.NumLines and tt:NumLines() + 1
        for _, r in ipairs(profRows) do
            tt:AddDoubleLine(r[1], r[3] ~= "" and (r[2] .. "  " .. r[3]) or r[2], 1, 1, 1, 1, 1, 1)
        end
    end
    local cooldowns = ns.CooldownRows(c, now)
    if cooldowns then
        if not profRows then tt:AddLine(" ") end
        for _, r in ipairs(cooldowns) do
            tt:AddDoubleLine(ns.CooldownName(r), ns.CooldownText(r[2], now), 1, 0.82, 0, 1, 1, 1)
        end
    end
    ns.AddLockoutLines(tt, c, now)
    tt:AddLine(" ")
    local free, total = ns.BagSpace(c, "bags")
    if free then tt:AddDoubleLine(L["Bags"], L["%d of %d free"]:format(free, total), 1, 0.82, 0, 1, 1, 1) end
    free, total = ns.BagSpace(c, "bank")
    if free then
        tt:AddDoubleLine(L["Bank"], L["%d of %d free"]:format(free, total), 1, 0.82, 0, 1, 1, 1)
    else
        tt:AddLine(GREY .. (c.bank and L["Bank scanned"] or L["Bank not scanned yet - visit a banker"]) .. "|r")
    end
    if c.dura then tt:AddDoubleLine(L["Lowest durability"], ns.DurabilityText(c.dura), 1, 0.82, 0, 1, 1, 1) end
    if key == ns.charKey then
        tt:AddLine("|cff66ccff" .. L["Click to see gear"] .. "|r")
    else
        tt:AddLine("|cff66ccff" .. L["Click to see gear"] .. " · " .. L["Right-click for bags, professions and more"] .. "|r")
    end
    tt:Show()
    -- Line up the professions in the font the tooltip is shown in (a UI addon such as
    -- EllesmereUI sets its own when it's shown), then show again to fit the new text.
    if profFirst then
        ns.AlignColumns(tt, profFirst, profRows, NO_LABELS, NOTE_LEFT)
        tt:Show()
    end
end

-- Which columns show (db.hiddenColumns[id] = true hides one; a player's request,
-- 2026-11-12) and where each starts: worked out when the window is made and when a column
-- is hidden or shown, never per refresh. Returns the window's width.
local colX, colShown = {}, {}

local function Measure()
    local hidden = ns.db.hiddenColumns
    local x = 12
    for i, col in ipairs(COLUMNS) do
        local shown = Visible(col.id, hidden)
        colShown[i] = shown
        if shown then
            x = x + (col.gap or 0)
            colX[i] = x
            x = x + col.width
        end
    end
    return max(x + 20, MIN_WIDTH)
end

local function PlaceCells(cells, parent)
    for i, fs in ipairs(cells) do
        if colShown[i] then
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", parent, "LEFT", colX[i], 0)
            fs:Show()
        else
            fs:Hide()
        end
    end
end

local function CreateCells(parent, font)
    local cells = {}
    for i, col in ipairs(COLUMNS) do
        local fs = parent:CreateFontString(nil, "OVERLAY", font)
        ns.SkinText(fs)
        fs:SetWidth(col.cell or col.width - 8)
        fs:SetJustifyH(col.right and "RIGHT" or col.center and "CENTER" or "LEFT")
        fs:SetWordWrap(false)
        cells[i] = fs
    end
    PlaceCells(cells, parent)
    return cells
end

-- A group heading's name may run on past the columns before Gold (empty in a heading), or
-- to the window's edge when Gold is hidden.
local function HeadWidth(width)
    if colShown[7] then return colX[7] - colX[1] - 8 end
    return width - colX[1] - 28
end

-- The Bags and Bank cells: pointing at one lists each bag or bank tab with its free slots,
-- its kind if it holds only some things (Herb Bag, Quiver), and empty bag slots; a click
-- opens that character's bags or bank, a right-click their menu as the row's does.
local ITEM_CROP = ":0:0:0:0:64:64:5:59:5:59|t "

-- The colour key under a bag list or grid: special bags left out of free space, then the
-- reagent bag (coloured, counted).
local function AddBagLegend(tt, seen)
    local uncounted, counted = ns.BagFamilyLegend(seen)
    if uncounted then tt:AddLine(GREY .. L["Not counted as free space: %s"]:format(uncounted .. GREY) .. "|r", 1, 1, 1, true) end
    if counted then tt:AddLine(GREY .. L["Counted as free space: %s"]:format(counted .. GREY) .. "|r", 1, 1, 1, true) end
end

local function SpaceTooltip(self)
    local row = self.row
    local key = row.key
    local c = key and ns.db.chars[key]
    if not c then return end
    row:LockHighlight()
    local which = self.which
    local tt = GameTooltip
    tt:SetOwner(self, "ANCHOR_RIGHT")
    tt:AddDoubleLine(ns.ColoredName(key, c), which == "bank" and L["Bank"] or L["Bags"], 1, 1, 1, 1, 0.82, 0)
    local free, total = ns.BagSpace(c, which)
    if not free then
        tt:AddLine(which == "bank" and L["Bank not scanned yet - visit a banker"]
            or L["No bags recorded yet.\nLog in on this character once."], 0.62, 0.62, 0.62, true)
    else
        local seen
        for _, e in ipairs(ns.BagSpaceList(c, which)) do
            if e.family then
                seen = seen or {}
                seen[e.family] = true
            end
            local left = (e.icon and ("|T" .. e.icon .. ITEM_CROP) or "") .. e.name
                .. (e.kind and ((e.family and ns.BAG_FAMILY_COLOR[e.family] or GREY) .. "  " .. e.kind .. "|r") or "")
            local q = e.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[e.quality]
            if e.size == 0 then
                tt:AddDoubleLine(left, "-", 0.62, 0.62, 0.62, 0.62, 0.62, 0.62)
            else
                tt:AddDoubleLine(left, ns.SpaceCell(e.free, e.size), q and q.r or 1, q and q.g or 1, q and q.b or 1, 1, 1, 1)
            end
        end
        tt:AddDoubleLine(L["Total"], L["%d of %d free"]:format(free, total), 1, 0.82, 0, 1, 1, 1)
        if seen then AddBagLegend(tt, seen) end
        local unbought = which == "bank" and ns.BankBagsUnbought(c)
        if unbought then tt:AddLine(GREY .. L["Bank bag slots not bought yet: %d"]:format(unbought) .. "|r") end
        if which == "bank" and c.bankAt then
            tt:AddLine(GREY .. L["Bank last visited: %s"]:format(ns.FormatAgo(time() - c.bankAt)) .. "|r")
        end
    end
    tt:AddLine("|cff66ccff" .. (which == "bank" and L["Click to open their bank"] or L["Click to open their bags"]) .. "|r")
    tt:Show()
end

local function SpaceLeave(self)
    self.row:UnlockHighlight()
    GameTooltip:Hide()
end

local function SpaceClick(self, button)
    local key = self.row.key
    if not key then return end
    if button == "RightButton" then return ns.ShowCharacterMenu(self.row, key) end
    GameTooltip:Hide()
    ns.ShowBags(key, self.which)
end

-- The Cooldowns cell: each cooldown, soonest first; a click opens their professions on the
-- soonest one's. A character with none gets the row's tooltip and click.
local function CooldownTooltip(self)
    local row = self.row
    local key = row.key
    local c = key and ns.db.chars[key]
    if not c then return end
    local now = time()
    local rows = ns.CooldownRows(c, now)
    if not rows then return RowTooltip(row) end
    row:LockHighlight()
    local tt = GameTooltip
    tt:SetOwner(self, "ANCHOR_RIGHT")
    tt:AddDoubleLine(ns.ColoredName(key, c), L["Cooldowns"], 1, 1, 1, 1, 0.82, 0)
    for _, r in ipairs(rows) do
        tt:AddDoubleLine(ns.CooldownName(r), ns.CooldownText(r[2], now), 1, 0.82, 0, 1, 1, 1)
    end
    tt:AddLine("|cff66ccff" .. L["Click to open their professions"] .. "|r")
    tt:Show()
end

local function CooldownClick(self, button)
    local key = self.row.key
    if not key then return end
    if button == "RightButton" then return ns.ShowCharacterMenu(self.row, key) end
    GameTooltip:Hide()
    local c = ns.db.chars[key]
    local rows = c and ns.CooldownRows(c, time())
    if rows and ns.ShowRecipes then return ns.ShowRecipes(key, rows[1][4], true) end
    ns.ShowGear(key)
end

local function CreateSpaceButtons(row)
    row.spaces = {}
    for i, col in ipairs(COLUMNS) do
        if col.space or col.hover then
            local b = CreateFrame("Button", nil, row)
            b:SetPoint("LEFT", row.cells[i], "LEFT", -4, 0)
            b:SetSize(col.width - 2, ROW_HEIGHT)
            b.row, b.which, b.index = row, col.space or col.hover, i
            b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            b:SetScript("OnClick", col.hover and CooldownClick or SpaceClick)
            b:SetScript("OnEnter", col.hover and CooldownTooltip or SpaceTooltip)
            b:SetScript("OnLeave", SpaceLeave)
            b:SetShown(colShown[i])
            row.spaces[#row.spaces + 1] = b
        end
    end
end

local function CreateRow(i)
    local row = CreateFrame("Button", nil, frame)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -54 - (i - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    row.cells = CreateCells(row, "GameFontHighlightSmall")
    -- The Level column: the level right-aligned in a narrow cell, then how far into it,
    -- so the percentages line up whatever the level's width.
    local level = row.cells[2]
    level:SetWidth(18)
    level:SetJustifyH("RIGHT")
    row.pct = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ns.SkinText(row.pct)
    row.pct:SetPoint("LEFT", level, "RIGHT", 6, 0)
    row.pct:SetWidth(COLUMNS[2].width - 32)
    row.pct:SetJustifyH("LEFT")
    row.pct:SetWordWrap(false)
    row.pct:SetShown(colShown[2])
    row:SetScript("OnEnter", RowTooltip)
    CreateSpaceButtons(row)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- Left: gear. Right: the character's menu (Forget...).
    row:SetScript("OnClick", function(self, button)
        if button == "RightButton" then ns.ShowCharacterMenu(self, self.key) else ns.ShowGear(self.key) end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- A on a controller: the character's menu (Gear, Bags, Bank, Forget), since a
    -- controller has no right-click.
    row.OnSmartNavClick = function(self) ns.ShowCharacterMenu(self, self.key) end
    rows[i] = row
    return row
end

-- A group's heading row: its name, and its gold total under the Gold column, with a faint
-- line above it and some space (SECTION_GAP) before every group but the first. Clicking
-- it collapses the group to just the heading, or opens it again (db.collapsedGroups,
-- by group key, kept between sessions).
local SECTION_GAP = 10
local PLUS, MINUS = "Interface\\Buttons\\UI-PlusButton-Up", "Interface\\Buttons\\UI-MinusButton-Up"

local function ToggleGroup(head)
    local db = ns.db
    db.collapsedGroups = db.collapsedGroups or {}
    db.collapsedGroups[head.group] = not db.collapsedGroups[head.group] or nil
    if next(db.collapsedGroups) == nil then db.collapsedGroups = nil end
    ns.RefreshOverview()
end

local function HeadTooltip(head)
    GameTooltip:SetOwner(head, "ANCHOR_TOPLEFT")
    GameTooltip:AddLine(head.label:GetText())
    GameTooltip:AddLine(head.collapsed and L["Click to show these characters."] or L["Click to hide these characters."], 1, 1, 1)
    GameTooltip:Show()
end

local function CreateHead(i)
    local head = CreateFrame("Button", nil, frame)
    head:SetHeight(ROW_HEIGHT)
    local hl = head:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    head:RegisterForClicks("LeftButtonUp")
    head:SetScript("OnClick", ToggleGroup)
    head:SetScript("OnEnter", HeadTooltip)
    head:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local icon = head:CreateTexture(nil, "ARTWORK")
    icon:SetSize(12, 12)
    icon:SetPoint("LEFT", head, "LEFT", -1, 0)
    head.icon = icon
    local line = head:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.12)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", head, "TOPLEFT", 8, 0)
    line:SetPoint("TOPRIGHT", head, "TOPRIGHT", -8, 0)
    head.line = line
    local texts = CreateCells(head, "GameFontNormalSmall")
    texts[1]:SetWidth(HeadWidth(frame:GetWidth()))
    head.texts, head.label, head.gold = texts, texts[1], texts[7]
    heads[i] = head
    return head
end

-- Places a row or heading y below the column titles.
local function Place(f, y)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -54 - y)
    f:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
end

-- While open, the overview refreshes itself when its instance counts change (a visit stops
-- counting, or the wait at the limit ticks over), so an account at 10/10 shows free again
-- without some other event, and each minute while a profession cooldown is counting down. One timer at a time: a new one only for a sooner change, and a
-- numbered `dueTick` so only the latest acts.
local dueAt, dueTick = nil, 0
local Refresh, SumSpace, SpaceSum, ApplyColumns

-- An `auto` column whose answer has changed since the layout was worked out (a first
-- cooldown seen, or the last one forgotten). One check per such column per refresh.
local function AutoChanged()
    local hidden = ns.db.hiddenColumns
    for i, col in ipairs(COLUMNS) do
        if col.auto and Visible(col.id, hidden) ~= colShown[i] then return true end
    end
    return false
end

local function Due(now)
    if not (C_Timer and C_Timer.After) then return end
    local wait = ns.InstancesChangeIn(now)
    local cool = ns.ColumnShown("cooldowns") and ns.CooldownsChangeIn(now)
    if cool and (not wait or cool < wait) then wait = cool end
    if not wait or (dueAt and now + wait >= dueAt) then return end
    dueTick, dueAt = dueTick + 1, now + wait
    local mine = dueTick
    C_Timer.After(wait, function()
        if mine ~= dueTick then return end
        dueAt = nil
        if frame and frame:IsShown() then Refresh() end
    end)
end

-- The column titles: a small arrow beside the one the characters are ordered by, pointing
-- up when the smallest is first; placed when the window opens and when the order changes. It sits just past the title's text, on the side the
-- column isn't aligned to (the far end of the cell if the text's width can't be read).
local UP, DOWN = "Interface\\Buttons\\Arrow-Up-Up", "Interface\\Buttons\\Arrow-Down-Up"

local function MarkSort()
    local name, rev = ns.OverviewSort()
    local b, arrow = frame.sorts[name], frame.sortArrow
    -- Ordered by a hidden column: still so, with nothing to point at.
    arrow:SetShown(b:IsShown())
    arrow:SetTexture(((SORTS[name].up == true) ~= rev) and UP or DOWN)
    local fs, col = b.title, b.col
    local w = fs:GetStringWidth()
    if issecretvalue(w) or type(w) ~= "number" then w = nil end
    arrow:ClearAllPoints()
    if col.right then
        if w then arrow:SetPoint("RIGHT", fs, "RIGHT", -w - 1, -1) else arrow:SetPoint("LEFT", fs, "LEFT", 0, -1) end
    elseif col.center then
        if w then arrow:SetPoint("LEFT", fs, "CENTER", w / 2 + 1, -1) else arrow:SetPoint("RIGHT", fs, "RIGHT", 0, -1) end
    else
        if w then arrow:SetPoint("LEFT", fs, "LEFT", w + 1, -1) else arrow:SetPoint("RIGHT", fs, "RIGHT", 0, -1) end
    end
end

-- Whether some column isn't showing (the menu's Show all columns is greyed out otherwise).
local function AnyHidden()
    for _, col in ipairs(HIDEABLE) do
        if not ns.ColumnShown(col[1]) then return true end
    end
    return false
end

-- The columns to show: a tick each, and one entry to bring them all back. Filled into a
-- menu of its own (right-click on the column titles) or the cog menu's Columns entry.
function ns.FillColumnsMenu(menu)
    local all = menu:CreateButton(L["Show all columns"], function() ns.ShowAllColumns() end)
    if not AnyHidden() then all:SetEnabled(false) end
    for _, col in ipairs(HIDEABLE) do
        local id = col[1]
        menu:CreateCheckbox(col[2], function() return ns.ColumnShown(id) end,
            function() ns.SetColumnShown(id, not ns.ColumnShown(id)) end)
    end
end

-- A one-time hint that columns can be hidden (owner, 2026-11-25: players kept missing it).
-- Our own callout under the titles, not Blizzard's HelpTip, whose shared frames would run
-- our code in theirs. Shown the first time the overview opens after this was added, once
-- per saved file (db.columnsHintSeen is set as it shows); it goes when closed, when the
-- columns menu is used, or with the window.
local function HideHint()
    if frame and frame.hint then frame.hint:Hide() end
end

local function MakeHint(f)
    local h = CreateFrame("Frame", nil, f)
    h:SetFrameLevel(f:GetFrameLevel() + 40)
    h:SetWidth(270)
    h:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", 60, -6)
    h:EnableMouse(true)
    local bg = h:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.05, 0.95)
    -- A 1 px gold edge, and a small gold notch pointing up at the titles.
    local function Edge(a, b, w, hgt)
        local t = h:CreateTexture(nil, "BORDER")
        t:SetColorTexture(1, 0.82, 0, 0.9)
        t:SetPoint(a)
        t:SetPoint(b)
        if w then t:SetWidth(w) else t:SetHeight(hgt) end
    end
    Edge("TOPLEFT", "TOPRIGHT", nil, 1)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
    Edge("TOPLEFT", "BOTTOMLEFT", 1)
    Edge("TOPRIGHT", "BOTTOMRIGHT", 1)
    local notch = h:CreateTexture(nil, "BORDER")
    notch:SetColorTexture(1, 0.82, 0, 0.9)
    notch:SetSize(8, 6)
    notch:SetPoint("BOTTOMLEFT", h, "TOPLEFT", 20, 0)
    local text = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", 10, -9)
    text:SetPoint("RIGHT", h, "RIGHT", -26, 0)
    text:SetJustifyH("LEFT")
    text:SetText(L["Tip: right-click the column titles to choose which columns show."])
    ns.SkinText(text)
    h.text = text
    local close = CreateFrame("Button", nil, h, "UIPanelCloseButton")
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", HideHint)
    h.close = close
    local height = text:GetStringHeight()
    if type(height) ~= "number" or issecretvalue(height) or height <= 0 then height = 24 end
    h:SetHeight(height + 18)
    h:Hide()
    f.hint = h
end

local function MaybeHint(f)
    local db = ns.db
    if db.columnsHintSeen then return end
    db.columnsHintSeen = true
    if not f.hint then MakeHint(f) end
    f.hint:Show()
end

local function ColumnsMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    HideHint()
    ns.OpenMenu(owner, function(_, root)
        root:CreateTitle(L["Columns"])
        ns.FillColumnsMenu(root)
    end)
end

local function SortClick(b, button)
    if button == "RightButton" then return ColumnsMenu(b) end
    ns.SortOverview(b.sort)
end

-- Under the Bags or Bank title: every character's slots added up, and who has a bag slot
-- with no bag in it (bags) or whose bank isn't known yet (bank).
local MAX_NAMES = 4

local function Names(list)
    local n = #list
    if n > MAX_NAMES then
        list[MAX_NAMES + 1] = L["+%d more"]:format(n - MAX_NAMES)
        for i = MAX_NAMES + 2, n do list[i] = nil end
    end
    return table.concat(list, ", ")
end

-- Under the Bags or Bank title: every character's bags in a grid, one column per bag
-- slot ("-" with no bag) then free of all, as Altoholic's bag report (a player planning
-- bag upgrades and passing old bags on, 2026-11-22; owner chose the title tooltip). Made
-- only on hover, so its tables cost nothing in play. Returns the grid's rows and first
-- line, lined up by the caller once the tooltip is shown.
local function SpaceSummary(tt, which)
    local chars = ns.db.chars
    local free, total, missing, rows, widest, seen = 0, 0, {}, {}, 0, {}
    for _, key in ipairs(ns.OverviewOrder()) do
        local c = chars[key]
        local f, t = ns.BagSpace(c, which)
        if f then
            free, total = free + f, total + t
            local empty = which == "bags" and ns.EmptyBagSlots(c) or 0
            if empty > 0 then missing[#missing + 1] = ns.ShortName(key, c) .. " " .. empty end
            local sizes = ns.BagSizes(c, which, {}, seen)
            if #sizes > widest then widest = #sizes end
            rows[#rows + 1] = { ns.ShortName(key, c), sizes, ns.SpaceCell(f, t) }
        elseif which == "bank" then
            missing[#missing + 1] = ns.ShortName(key, c)
        end
    end
    tt:AddLine(" ")
    local first
    if #rows > 0 then
        tt:AddLine(which == "bags" and L["Slots in each bag, then free of all"]
            or L["Slots in each bank bag, then free of all"], 0.62, 0.62, 0.62)
        first = tt.NumLines and tt:NumLines() + 1
        -- One column per bag slot, short rows padded so the free column lines up.
        for i, r in ipairs(rows) do
            local sizes = r[2]
            tt:AddDoubleLine(r[1], (#sizes > 0 and table.concat(sizes, "/") .. "   " or "") .. r[3], 1, 1, 1, 1, 1, 1)
            local cells = { r[1] }
            for col = 1, widest do cells[col + 1] = sizes[col] or "" end
            cells[widest + 2] = r[3]
            rows[i] = cells
        end
        AddBagLegend(tt, seen)
    end
    if total > 0 then
        tt:AddDoubleLine(L["All characters"], L["%d of %d free"]:format(free, total), 1, 0.82, 0, 1, 1, 1)
    end
    if #missing > 0 then
        local text = which == "bags" and L["Bag slots with no bag: %s"] or L["Bank not visited yet: %s"]
        tt:AddLine(text:format(Names(missing)), 1, 0.5, 0, true)
    end
    tt:AddLine(" ")
    return first and rows, first
end

local function SortTooltip(b)
    local tt = GameTooltip
    tt:SetOwner(b, "ANCHOR_TOPLEFT")
    -- A secondary profession's title is its icon: the tooltip names it.
    local line = b.col.line
    tt:AddLine(line and (ns.ProfessionLineName(line) or L["Secondary professions"]) or b.col.title)
    if b.col.tip then tt:AddLine(b.col.tip, 1, 1, 1, true) end
    local rows, first
    if b.col.space then rows, first = SpaceSummary(tt, b.col.space) end
    tt:AddLine(L["Click to sort by this column, and again to reverse it."], 1, 1, 1)
    tt:AddLine(L["Right-click to choose which columns are shown."], 1, 1, 1)
    tt:Show()
    -- Lined up in the font the tooltip is shown in, as the row tooltip's professions.
    if rows and ns.AlignColumns(tt, first, rows, NO_LABELS) then tt:Show() end
end

-- Bag space added up per group, for the headings (when there's more than one character to
-- add up, as with gold). Reused tables.
local spaceFree = { bags = {}, bank = {} }
local spaceTotal = { bags = {}, bank = {} }

function SumSpace(keys, chars)
    for which, t in pairs(spaceFree) do
        wipe(t)
        wipe(spaceTotal[which])
    end
    for _, key in ipairs(keys) do
        local c = chars[key]
        local g = Group(c)
        for which, sums in pairs(spaceFree) do
            local free, total = ns.BagSpace(c, which)
            if free then
                sums[g] = (sums[g] or 0) + free
                spaceTotal[which][g] = (spaceTotal[which][g] or 0) + total
            end
        end
    end
end

function SpaceSum(which, group)
    local free = spaceFree[which][group]
    return free and ns.SpaceCell(free, spaceTotal[which][group]) or ""
end

function Refresh()
    if AutoChanged() then return ApplyColumns() end -- lays the window out again, then refreshes
    local now = time()
    local chars = ns.db.chars
    local keys = ns.OverviewOrder()
    local split = ns.overviewSplit
    local total, played = 0, 0
    -- Gold and characters per group, for the headings.
    local gold, count = {}, {}
    if split then
        for _, key in ipairs(keys) do
            local g = Group(chars[key])
            gold[g] = (gold[g] or 0) + (chars[key].money or 0)
            count[g] = (count[g] or 0) + 1
        end
        SumSpace(keys, chars)
    end
    -- Counts each account's instances this hour, for the footer and each row's Lockouts cell.
    local instances = ns.InstanceText(now)
    Due(now)
    local collapsed = ns.db.collapsedGroups or {}
    local y, nHeads, group, hidden = 0, 0, nil, false
    for i, key in ipairs(keys) do
        local c = chars[key]
        if split and Group(c) ~= group then
            group = Group(c)
            hidden = collapsed[group] == true
            if nHeads > 0 then y = y + SECTION_GAP end
            nHeads = nHeads + 1
            local head = heads[nHeads] or CreateHead(nHeads)
            Place(head, y)
            head.group, head.collapsed = group, hidden
            head.icon:SetTexture(hidden and PLUS or MINUS)
            head.line:SetShown(nHeads > 1)
            local label = ns.GroupLabel(c, parts[1], parts[2])
            head.label:SetText(hidden and (label .. "  " .. GREY .. "(" .. count[group] .. ")|r") or label)
            -- A total only when there's something to add up: one character's is on their row,
            -- unless the group is collapsed.
            local sum = hidden or count[group] > 1
            head.gold:SetText(sum and ns.GoldShort(gold[group]) or "")
            head.texts[16]:SetText(sum and SpaceSum("bags", group) or "")
            head.texts[17]:SetText(sum and SpaceSum("bank", group) or "")
            head:Show()
            y = y + ROW_HEIGHT
        end
        local row = rows[i] or CreateRow(i)
        if not hidden then
            Place(row, y)
            y = y + ROW_HEIGHT
        end
        local cells = row.cells
        row.key = key
        cells[1]:SetText(pinRank[key] and (ns.ColoredName(key, c) .. PIN) or ns.ColoredName(key, c))
        local level, pct = ns.LevelParts(c)
        cells[2]:SetText(level)
        row.pct:SetText(pct)
        cells[3]:SetText(ns.RestedText(c, now))
        cells[4]:SetText(ns.RestedFullText(c, now))
        local points, rank = ns.LegacyCells(c)
        cells[5]:SetText(rank)
        cells[6]:SetText(points)
        cells[7]:SetText(c.money and ns.GoldShort(c.money) or (GREY .. "?|r"))
        local n1, s1, n2, s2 = ns.ProfIconCells(c)
        cells[8]:SetText(n1)
        cells[9]:SetText(s1)
        cells[10]:SetText(n2)
        cells[11]:SetText(s2)
        cells[12]:SetText(ns.LineSkill(c, 185) or "")
        cells[13]:SetText(ns.LineSkill(c, 129) or "")
        cells[14]:SetText(ns.LineSkill(c, 356) or "")
        cells[15]:SetText(ns.MailText(c, now))
        cells[16]:SetText(ns.SpaceText(c, "bags"))
        cells[17]:SetText(ns.SpaceText(c, "bank"))
        cells[18]:SetText(ns.LockoutText(c, now))
        cells[19]:SetText(ns.CooldownCell(c, now))
        cells[20]:SetText(c.zone or (GREY .. "?|r"))
        cells[21]:SetText(ns.PlayedText(c, now))
        cells[22]:SetText(ns.SeenText(key, c, now))
        total = total + (c.money or 0)
        played = played + (ns.PlayedNow(c, now) or 0)
        row:SetShown(not hidden)
    end
    for i = #keys + 1, #rows do rows[i]:Hide() end
    for i = nHeads + 1, #heads do heads[i]:Hide() end
    -- With only one character there's nothing to compare yet: say how to add the others.
    frame.credit:SetText(#keys == 1 and (GREY .. L["Log in on your other characters once to add them here."] .. "|r")
        or L["Alts Forever by Kadmai"])
    -- Split by ruleset, each heading has its gold: one total would mix what can't be traded.
    footer:SetText((instances and (instances .. "     ") or "")
        .. L["Total played: %s"]:format(ns.FormatPlayed(played))
        .. (split and "" or ("     " .. L["Total gold: %s"]:format(GetCoinTextureString(total)))))
    frame:SetHeight(54 + y + 32)
end

---------------------------------------------------------------------------
-- Panels opened beside the overview (Reputation, Lockouts): each goes where it covers
-- neither the overview nor another of them that's open, as far as the screen allows
-- (owner, 2026-11-08: one placed below a low overview was pushed up over it by the screen
-- edge, and the two opened in the same spot). Tried in turn: below the overview, beside or
-- below another open panel, above the overview, right of it, left of it, left of another;
-- the first that fits on screen covering nothing wins, else below the overview as before.
-- Anchored to the overview (or that panel), so they follow it when it's dragged. Our windows
-- share one scale, so their edges compare directly. Placed when opened, after it's sized.
---------------------------------------------------------------------------
local GAP = 4
local dockable = {}

-- A window's edges, or nil if the game hasn't laid it out.
local function Edges(f)
    local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
    if issecretvalue(l) or issecretvalue(r) or issecretvalue(t) or issecretvalue(b) then return nil end
    if type(l) ~= "number" or type(r) ~= "number" or type(t) ~= "number" or type(b) ~= "number" then return nil end
    return { f, l, r, t, b }
end

-- Whether a window's place depends on `panel`: it is anchored to it, directly or through
-- others of ours. Anchoring `panel` to such a window would make a circle of anchors.
local function Follows(f, panel)
    for _ = 1, 8 do
        local _, rel = f:GetPoint()
        if rel == panel then return true end
        if type(rel) ~= "table" or rel == UIParent then return false end
        f = rel
    end
    return true -- deeper than our windows ever chain: don't risk it
end

-- A window others are never placed against, though they still keep clear of it: the
-- search, which itself moves beside the bags window whenever that opens.
local floating = {}
function ns.NeverDockTo(f) floating[f] = true end

function ns.DockToOverview(panel)
    dockable[panel] = true
    panel:ClearAllPoints()
    local overview = AltsForeverFrame
    if not (overview and overview:IsShown()) then return panel:SetPoint("CENTER") end
    local ov = Edges(overview)
    local w, h = panel:GetWidth(), panel:GetHeight()
    local scale = ns.WindowScale()
    local sw, sh = UIParent:GetWidth() / scale, UIParent:GetHeight() / scale
    if ov and w > 0 and h > 0 and sw > 0 and sh > 0 then
        local taken, others = { ov }, {}
        for other in pairs(dockable) do
            if other ~= panel and other:IsShown() then
                local e = Edges(other)
                if e then
                    taken[#taken + 1] = e
                    if not floating[other] and not Follows(other, panel) then others[#others + 1] = e end
                end
            end
        end
        local function Fits(x, top)
            local right, bottom = x + w, top - h
            if x < 0 or right > sw or bottom < 0 or top > sh then return false end
            for _, e in ipairs(taken) do
                if x < e[3] and right > e[2] and top > e[5] and bottom < e[4] then return false end
            end
            return true
        end
        local function Try(x, top, point, rel, relPoint, dx, dy)
            if not Fits(x, top) then return false end
            panel:SetPoint(point, rel, relPoint, dx, dy)
            return true
        end
        local l, r, t, b = ov[2], ov[3], ov[4], ov[5]
        if Try(l, b - GAP, "TOPLEFT", overview, "BOTTOMLEFT", 0, -GAP) then return end
        for _, e in ipairs(others) do
            if Try(e[3] + GAP, e[4], "TOPLEFT", e[1], "TOPRIGHT", GAP, 0) then return end
            if Try(e[2], e[5] - GAP, "TOPLEFT", e[1], "BOTTOMLEFT", 0, -GAP) then return end
        end
        if Try(l, t + GAP + h, "BOTTOMLEFT", overview, "TOPLEFT", 0, GAP) then return end
        if Try(r + GAP, t, "TOPLEFT", overview, "TOPRIGHT", GAP, 0) then return end
        if Try(l - GAP - w, t, "TOPRIGHT", overview, "TOPLEFT", -GAP, 0) then return end
        for _, e in ipairs(others) do
            if Try(e[2] - GAP - w, e[4], "TOPRIGHT", e[1], "TOPLEFT", -GAP, 0) then return end
        end
    end
    panel:SetPoint("TOPLEFT", overview, "BOTTOMLEFT", 0, -GAP)
end

---------------------------------------------------------------------------
-- Where our windows are (a player's request, 2026-11-12): db.windows[key] is where the
-- player left each one, account-wide, and it opens there again:
--   { x, y }      dropped freely: its top left corner from the screen's bottom left, in
--                 the screen's units (so it holds whatever the window size setting)
--   { dock, off } dropped against an edge of the overview ("below", "above", "right",
--                 "left"; within SNAP): it sits against that edge, `off` along it (in the
--                 screen's units too), and follows the overview. With the overview closed
--                 it opens as by default.
-- A window can be at a smaller scale than the overview (Lockouts, when it wouldn't fit),
-- and each reports its edges in its own units, so they are compared in the screen's.
-- Nothing saved: the window's own default (`fallback`: ns.DockToOverview for the panels
-- opened from the overview). Worked out only when a drag ends: nothing runs while dragging.
---------------------------------------------------------------------------
local SNAP = 12
local SIDES = { below = true, above = true, right = true, left = true }
local tracked = {}

local function Saved(key)
    local all = ns.db.windows
    local p = type(all) == "table" and all[key]
    return type(p) == "table" and p or nil
end

local function Store(key, p)
    local db = ns.db
    if p then
        if type(db.windows) ~= "table" then db.windows = {} end
        db.windows[key] = p
    elseif type(db.windows) == "table" then
        db.windows[key] = nil
        if next(db.windows) == nil then db.windows = nil end
    end
end

local function OwnScale(f)
    local s = f:GetScale()
    if issecretvalue(s) or type(s) ~= "number" or s <= 0 then return 1 end
    return s
end

-- A window's edges in the screen's units, or nil if the game hasn't laid it out.
local function ScreenEdges(f)
    local e = Edges(f)
    if not e then return nil end
    local s = OwnScale(f)
    e[2], e[3], e[4], e[5] = e[2] * s, e[3] * s, e[4] * s, e[5] * s
    return e
end

-- `off` in the screen's units; anchor offsets are in the window's own.
local function Against(f, side, off)
    local overview = AltsForeverFrame
    off = off / OwnScale(f)
    local down = off == 0 and 0 or -off
    f:ClearAllPoints()
    if side == "below" then
        f:SetPoint("TOPLEFT", overview, "BOTTOMLEFT", off, -GAP)
    elseif side == "above" then
        f:SetPoint("BOTTOMLEFT", overview, "TOPLEFT", off, GAP)
    elseif side == "right" then
        f:SetPoint("TOPLEFT", overview, "TOPRIGHT", GAP, down)
    else
        f:SetPoint("TOPRIGHT", overview, "TOPLEFT", -GAP, down)
    end
end

-- The overview's edge a dropped window is against, and how far along it; nil if none.
-- Its near corners line up with the overview's when they're within SNAP too.
local function Near(e, o)
    local l, r, t, b = e[2], e[3], e[4], e[5]
    local ol, orr, ot, ob = o[2], o[3], o[4], o[5]
    local function Along(start, finish, from, to)
        local off = start - from
        if math.abs(off) <= SNAP then return 0 end
        if math.abs(finish - to) <= SNAP then return to - (finish - start) - from end
        return off
    end
    if l < orr and r > ol then
        if math.abs(t - (ob - GAP)) <= SNAP then return "below", Along(l, r, ol, orr) end
        if math.abs(b - (ot + GAP)) <= SNAP then return "above", Along(l, r, ol, orr) end
    end
    if t > ob and b < ot then
        -- Down the side: measured from the overview's top.
        local off = ot - t
        if math.abs(off) <= SNAP then off = 0 elseif math.abs(b - ob) <= SNAP then off = ot - ob - (t - b) end
        if math.abs(l - (orr + GAP)) <= SNAP then return "right", off end
        if math.abs(r - (ol - GAP)) <= SNAP then return "left", off end
    end
    return nil
end

local function Dropped(f)
    f:StopMovingOrSizing()
    local info = tracked[f]
    local e = info and ScreenEdges(f)
    if not e then return end
    local overview = AltsForeverFrame
    if info.dock and overview and overview ~= f and overview:IsShown() then
        local o = ScreenEdges(overview)
        local side, off
        if o then side, off = Near(e, o) end
        if side then
            Against(f, side, off)
            return Store(info.key, { dock = side, off = off })
        end
    end
    Store(info.key, { x = e[2], y = e[4] })
end

-- The middle of the screen: where a window with no other default opens.
local function Centre(f)
    f:ClearAllPoints()
    f:SetPoint("CENTER")
end

-- A window whose place is remembered under `key`; `dock`: it can be dropped against the
-- overview; `fallback`: where it goes with nothing saved (the middle of the screen if not
-- given), so a reset really moves it. Called once, when the window is made (it sets the
-- window's OnDragStop).
function ns.TrackWindow(f, key, dock, fallback)
    tracked[f] = { key = key, dock = dock, fallback = fallback or Centre }
    f:SetScript("OnDragStop", Dropped)
end

-- Whether the player has put this window somewhere (free or against the overview).
function ns.WindowPlaced(f)
    local info = tracked[f]
    return info ~= nil and Saved(info.key) ~= nil
end

-- Puts a window where the player left it, else where it goes by default (its `fallback`).
-- Called as it opens, once it's sized.
function ns.PlaceWindow(f)
    local info = tracked[f]
    if not info then return false end
    local p = Saved(info.key)
    if p then
        if type(p.x) == "number" and type(p.y) == "number" then
            local s = OwnScale(f)
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.x / s, p.y / s)
            return true
        end
        local overview = AltsForeverFrame
        if info.dock and SIDES[p.dock] and type(p.off) == "number" and overview and overview:IsShown() then
            Against(f, p.dock, p.off)
            return true
        end
    end
    info.fallback(f)
    return false
end

-- Every window back to where it opens by default (the overview's cog menu,
-- /af resetwindows): the overview first, as the others may go beside it. A closed window
-- goes to its default when it next opens (ns.PlaceWindow), as nothing is saved for it.
function ns.ResetWindows()
    ns.db.windows = nil
    for f, info in pairs(tracked) do
        if info.key == "overview" then info.fallback(f) end
    end
    for f, info in pairs(tracked) do
        if info.key ~= "overview" and f:IsShown() then info.fallback(f) end
    end
end

-- Beside the overview if it's open, else the middle of the screen: the default for the
-- bags window.
function ns.DockIfOverview(f)
    local overview = AltsForeverFrame
    if overview and overview:IsShown() then return ns.DockToOverview(f) end
    Centre(f)
end

local function CreateWindow()
    -- Room for the left inset, every column shown, and the right border.
    local width = Measure()

    local f = ns.NewWindow("AltsForeverFrame")
    if f.plainFrame then
        -- Plain fallback if this client lacks the templates: a dialog backdrop and a close button.
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        })
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
    end
    frame = f
    rows, heads = {}, {}
    f:SetSize(width, 200)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    -- Comes to the front when clicked or opened, so our windows never draw through each other.
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)

    local title = f.TitleText or f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if not f.TitleText then title:SetPoint("TOP", 0, -6) end
    title:SetText("Alts Forever")

    local header = CreateFrame("Frame", nil, f)
    header:SetHeight(ROW_HEIGHT)
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -32)
    header:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    f.sorts = {}
    local arrow = header:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(12, 12)
    f.sortArrow = arrow
    -- Right-click anywhere on the titles: which columns to show.
    header:EnableMouse(true)
    header:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then ColumnsMenu(self) end
    end)
    f.header = header
    f.titles = CreateCells(header, "GameFontNormalSmall")
    for i, fs in ipairs(f.titles) do
        local col = COLUMNS[i]
        fs:SetText(col.title)
        if col.titleWidth then fs:SetWidth(col.titleWidth) end
        if col.sort then
            -- The title is a button: click to order by this column, again to turn it round.
            local b = CreateFrame("Button", nil, header)
            b:SetPoint("LEFT", fs, "LEFT", -4, 0)
            b:SetSize(col.width - 2, ROW_HEIGHT)
            local hl = b:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.08)
            b.sort, b.title, b.col, b.index = col.sort, fs, col, i
            b:SetShown(colShown[i])
            b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            b:SetScript("OnClick", SortClick)
            b:SetScript("OnEnter", SortTooltip)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            f.sorts[col.sort] = b
        end
    end

    footer = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.footer = footer
    footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 12)
    -- Options (cog) button in the title bar, left of the close button.
    local cog = CreateFrame("Button", nil, f)
    cog:SetSize(16, 16)
    cog:SetPoint("TOPRIGHT", f, "TOPRIGHT", -28, -4)
    cog:SetNormalTexture("Interface\\Icons\\INV_Misc_Gear_01")
    cog:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    cog:SetScript("OnClick", function(self) ns.ShowOptionsMenu(self, true) end)
    cog:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Options"])
        GameTooltip:Show()
    end)
    cog:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.cog = cog
    -- Reputation panel button, left of the options button.
    local rep = CreateFrame("Button", nil, f)
    rep:SetSize(16, 16)
    rep:SetPoint("RIGHT", cog, "LEFT", -6, 0)
    rep:SetNormalTexture("Interface\\Icons\\Achievement_Reputation_01")
    rep:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    rep:SetScript("OnClick", function() ns.ToggleReputation() end)
    rep:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Reputation"])
        GameTooltip:AddLine(L["Every character's standing with each faction"], 1, 1, 1)
        GameTooltip:Show()
    end)
    rep:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.repButton = rep
    -- Lockouts window button, left of the reputation button.
    local lockouts = CreateFrame("Button", nil, f)
    lockouts:SetSize(16, 16)
    lockouts:SetPoint("RIGHT", rep, "LEFT", -6, 0)
    lockouts:SetNormalTexture("Interface\\Icons\\INV_Misc_Key_03")
    lockouts:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    lockouts:SetScript("OnClick", function() ns.ToggleLockouts() end)
    lockouts:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Lockouts"])
        GameTooltip:AddLine(L["Your characters' raid lockouts, and the instances each game account has entered this hour"], 1, 1, 1)
        GameTooltip:Show()
    end)
    lockouts:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.lockoutsButton = lockouts
    -- Professions window button, left of the lockouts button (Recipes.lua).
    local profs = CreateFrame("Button", nil, f)
    profs:SetSize(16, 16)
    profs:SetPoint("RIGHT", lockouts, "LEFT", -6, 0)
    profs:SetNormalTexture("Interface\\Icons\\Trade_BlackSmithing")
    profs:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    profs:SetScript("OnClick", function() ns.ToggleRecipes() end)
    profs:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Professions"])
        GameTooltip:AddLine(L["Any character's professions and recipes, even while they're offline"], 1, 1, 1)
        GameTooltip:Show()
    end)
    profs:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.profsButton = profs
    -- Bags and bank window button, left of the professions button.
    local bags = CreateFrame("Button", nil, f)
    bags:SetSize(16, 16)
    bags:SetPoint("RIGHT", profs, "LEFT", -6, 0)
    bags:SetNormalTexture("Interface\\Icons\\INV_Misc_Bag_08")
    bags:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    bags:SetScript("OnClick", function() ns.ShowBags(ns.charKey, "bags") end)
    bags:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Bags and bank"])
        GameTooltip:AddLine(L["Any character's bags and bank, slot by slot"], 1, 1, 1)
        GameTooltip:Show()
    end)
    bags:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.bagsButton = bags
    -- Search button, left of the bags button.
    local search = CreateFrame("Button", nil, f)
    search:SetSize(16, 16)
    search:SetPoint("RIGHT", bags, "LEFT", -6, 0)
    search:SetNormalTexture("Interface\\Icons\\INV_Misc_Spyglass_02")
    search:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    search:SetScript("OnClick", function() ns.ToggleSearch() end)
    search:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Search your characters"])
        GameTooltip:AddLine(L["Find an item on any character, or who can craft it. Same as /afs."], 1, 1, 1)
        GameTooltip:Show()
    end)
    search:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.searchButton = search
    -- Export button, left of the search button.
    local export = CreateFrame("Button", nil, f)
    export:SetSize(16, 16)
    export:SetPoint("RIGHT", search, "LEFT", -6, 0)
    export:SetNormalTexture("Interface\\Icons\\INV_Misc_Note_01")
    export:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    export:SetScript("OnClick", function() ns.ToggleExport() end)
    export:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Export your characters"])
        GameTooltip:AddLine(L["Your characters as text, to copy into notes or a spreadsheet. Same as /af export."], 1, 1, 1)
        GameTooltip:Show()
    end)
    export:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.exportButton = export
    -- Sync button, left of the export button.
    local sync = CreateFrame("Button", nil, f)
    sync:SetSize(16, 16)
    sync:SetPoint("RIGHT", export, "LEFT", -6, 0)
    sync:SetNormalTexture("Interface\\Buttons\\UI-RefreshButton")
    sync:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    sync:SetScript("OnClick", function() ns.ToggleSync() end)
    sync:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Sync with another account"])
        GameTooltip:AddLine(L["Swap characters with Alts Forever on your other game account. Same as /af sync."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    sync:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.syncButton = sync
    ns.OverTitle(f, cog, rep, lockouts, profs, bags, search, export, sync)
    f.credit = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.credit:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 12)
    f.credit:SetText(L["Alts Forever by Kadmai"])

    ns.SkinWindow(f)
    f:SetScript("OnShow", function(self)
        self:Raise()
        ns.PruneSaves(time())
        MarkSort()
        Refresh()
        MaybeHint(self)
    end)
    f:SetScript("OnHide", function()
        HideHint()
        if AltsForeverRepFrame then AltsForeverRepFrame:Hide() end
    end)
    -- Escape closes it, like Blizzard's own windows.
    ns.EscapeCloses(f, true)
    f:Hide()
    ns.GamepadWindow(f)
    ns.ScaleWindow(f)
    -- Where it was left, now that its size is set; else the middle, as above.
    ns.TrackWindow(f, "overview")
    ns.PlaceWindow(f)
end

-- Lays the open window out again after a column is hidden or shown: its width, the
-- titles, every row and group heading made so far. No frame is created.
function ApplyColumns()
    if not frame then return end
    local width = Measure()
    frame:SetWidth(width)
    PlaceCells(frame.titles, frame.header)
    for _, b in pairs(frame.sorts) do b:SetShown(colShown[b.index]) end
    for _, row in ipairs(rows) do
        PlaceCells(row.cells, row)
        row.pct:SetShown(colShown[2])
        for _, b in ipairs(row.spaces) do b:SetShown(colShown[b.index]) end
    end
    for _, head in ipairs(heads) do
        PlaceCells(head.texts, head)
        head.label:SetWidth(HeadWidth(width))
    end
    MarkSort()
    ns.RefreshOverview()
end

function ns.ColumnShown(id)
    return Visible(id, ns.db.hiddenColumns)
end

-- The id of a column that can be hidden, from the word a player types; nil if none.
function ns.ColumnId(word)
    word = (word or ""):lower()
    for _, col in ipairs(HIDEABLE) do
        if col[1] == word then return col[1], col[2] end
    end
    return nil
end

function ns.SetColumnShown(id, on)
    if not ns.ColumnId(id) then return end
    local db = ns.db
    local hidden = type(db.hiddenColumns) == "table" and db.hiddenColumns or {}
    -- An `auto` column remembers either choice; the others only being hidden.
    if AUTO[id] then hidden[id] = not on else hidden[id] = not on or nil end
    db.hiddenColumns = next(hidden) ~= nil and hidden or nil
    ApplyColumns()
end

-- Every column, `auto` ones too, even with nothing in them.
function ns.ShowAllColumns()
    local shown
    for id, auto in pairs(AUTO) do
        if auto() ~= true then
            shown = shown or {}
            shown[id] = false
        end
    end
    ns.db.hiddenColumns = shown
    ApplyColumns()
end


-- Opens or closes the overview; `open` only ever opens it (menus, settings page).
function ns.ToggleOverview(open)
    if not frame then CreateWindow() end
    if frame:IsShown() and not open then return frame:Hide() end
    frame:Show()
    frame:Raise() -- already open: to the front, over other windows
end

function ns.OverviewShown()
    return frame and frame:IsShown() or false
end

-- `sorted`: the order was changed, so the arrow beside the column titles moves too.
function ns.RefreshOverview(sorted)
    if ns.CharacterFactsChanged then ns.CharacterFactsChanged() end -- the same facts, Sheets.lua
    if not (frame and frame:IsShown()) then return end
    if sorted then MarkSort() end
    Refresh()
end

function ns.StartOverview()
    -- Keep an open window current; a closed or never-opened one costs nothing.
    local function Update()
        if ns.CharacterFactsChanged then ns.CharacterFactsChanged() end
        if frame and frame:IsShown() then Refresh() end
    end
    for _, event in ipairs({ "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_MONEY", "ZONE_CHANGED_NEW_AREA", "SKILL_LINES_CHANGED" }) do
        ns.On(event, Update)
    end
end
