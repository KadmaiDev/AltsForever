-- Alts Forever professions: records each character's profession skill levels and
-- learned recipes, shows on recipe items which characters know or can learn them,
-- on craftable items which characters can make them, and on reagents which of your
-- characters can still skill up with them.
local _, ns = ...
if ns.disabled then return end -- another copy of Alts Forever is running (Core.lua)
local L = ns.L

local pairs, ipairs, next, wipe, tonumber, type, sort = pairs, ipairs, next, wipe, tonumber, type, table.sort
local pcall, floor = pcall, math.floor
local issecretvalue = issecretvalue or function() return false end
local GetProfessions, GetProfessionInfo = GetProfessions, GetProfessionInfo
local GetItemInfoInstant, GetItemNameByID = C_Item.GetItemInfoInstant, C_Item.GetItemNameByID
local TS = C_TradeSkillUI

local RECIPE_CLASS = Enum.ItemClass and Enum.ItemClass.Recipe or 9

-- Turns the game's "Requires %s (%d)" into a pattern capturing profession and skill,
-- so it works in every language.
local REQUIRES = "^" .. (ITEM_MIN_SKILL or "Requires %s (%d)")
    :gsub("[%%%(%)%.%-%+%[%]%^%$%?%*]", "%%%0")
    :gsub("%%%%s", "(.+)")
    :gsub("%%%%d", "(%%d+)") .. "$"

-- Statuses, in the order they're listed.
local KNOWN, CAN_LEARN, NEEDS_SKILL, NOT_SCANNED = 1, 2, 3, 4
local STATUS_TEXT = {
    "|cff20ff20" .. L["Known"] .. "|r",
    "|cffffd100" .. L["Can learn"] .. "|r",
    nil, -- built per row: "Needs 120 (107)"
    "|cff9d9d9d" .. L["Not scanned"] .. "|r",
}
local LIGHT = "|cffe0e0e0" -- matches the item breakdown (Tooltip.lua)
local MAX_SKILLUP_LINES = 6 -- reagent tooltip; each character shows at most 2

-- Skill-up details (grey points) in tooltips; /af skillups turns them off.
function ns.SkillupsOn()
    return not ns.db.skillupsOff
end

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------
-- c.profs = { [professionName] = skillLevel }, c.profMax = { [professionName] = the
-- current rank's maximum (75, 150, 225 or 300) }; c.prof1/c.prof2 name the two main
-- professions (GetProfessions lists those first, then the secondary ones).
-- `live`: a skill change while playing (SKILL_LINES_CHANGED). A profession gone then was
-- abandoned, and the game took its recipes with it, so they're forgotten here too:
-- relearned, it reads "Not scanned" until its window is opened. A read that may be
-- incomplete changes nothing: one with a profession that couldn't be read, or one that
-- finds none at all while some were known, at login or live (a live read that finds even
-- one still drops the others). Returns true if a profession was dropped. The price: a
-- character who really unlearns their only profession keeps it listed until a read finds
-- another, the safer side of wiping every recipe on one empty read.
local read, readMax = {}, {} -- reused
-- Each profession's icon and skill line, account-wide, for showing another character's
-- profession (Recipes.lua): db.profArt[name] = "skillLine;icon". The game only tells the
-- character you're on.
local function Art(name, icon, line)
    if issecretvalue(icon) or issecretvalue(line) or type(line) ~= "number" then return end
    local art = line .. ";" .. ((type(icon) == "number" or type(icon) == "string") and icon or "")
    local db = ns.db
    if db.profArt and db.profArt[name] == art then return end
    db.profArt = db.profArt or {}
    db.profArt[name] = art
end

function ns.ScanSkills(c, live)
    local a, b, c3, d, e, f = GetProfessions()
    local profs, maxes = c.profs or {}, c.profMax or {}
    c.profs, c.profMax = profs, maxes
    if not (a or b or c3 or d or e or f) and next(profs) then return false end
    wipe(read)
    wipe(readMax)
    local unread = false
    local function Add(index)
        if not index then return end
        local name, icon, skill, max, _, _, line = GetProfessionInfo(index)
        if not issecretvalue(name) and not issecretvalue(skill) and name and skill then
            read[name] = skill
            Art(name, icon, line)
            if not issecretvalue(max) and max and max > 0 then readMax[name] = max end
            return name
        end
        unread = true
    end
    local prof1, prof2 = Add(a), Add(b)
    Add(c3) Add(d) Add(e) Add(f)
    if unread and next(profs) then return false end
    local dropped = false
    if live then
        for name in pairs(profs) do
            if not read[name] then
                if c.recipes then c.recipes[name] = nil end
                if c.crafts then c.crafts[name] = nil end
                if c.cooldowns then
                    c.cooldowns[name] = nil
                    if next(c.cooldowns) == nil then c.cooldowns = nil end
                end
                dropped = true
            end
        end
    end
    wipe(profs)
    wipe(maxes)
    for name, skill in pairs(read) do profs[name] = skill end
    for name, max in pairs(readMax) do maxes[name] = max end
    c.prof1, c.prof2 = prof1, prof2
    if dropped then ns.PruneRecipeInfo() end
    return dropped
end

local function ProfessionName(info)
    return info and (info.professionName or info.parentProfessionName)
end

-- Some clients name one profession two ways: on a Spanish client (a player's report,
-- 2026-11-25) the skill list (GetProfessionInfo, whose names every record here is kept under)
-- says "Costura" while the profession window and its recipes say "Sastrería". Names are
-- matched by skill line, the same in every language: db.profArt (the skill list's names, and
-- any other name found on the same line), else the game's name for each line (Recipes.lua).
local function LineOfName(name)
    if not ns.ProfessionArt then return nil end
    return (ns.ProfessionArt(name))
end

-- The name a character's records use for a profession the game called `name`: the same,
-- unless they have none by that name but one on the same skill line.
function ns.ProfKey(c, name)
    local profs = c and c.profs
    if name == nil or not profs or profs[name] then return name end
    local line = LineOfName(name)
    if line then
        for own in pairs(profs) do
            if LineOfName(own) == line then return own end
        end
    end
    return name
end

-- Whether the game calls skill line `line` `name`, by either of its names for a line.
local function LineCalled(line, name)
    local ok, n = pcall(TS.GetTradeSkillDisplayName or error, line)
    if ok and not issecretvalue(n) and n == name then return true end
    local info
    ok, info = pcall(TS.GetProfessionInfoBySkillLineID or error, line)
    n = ok and type(info) == "table" and ProfessionName(info)
    if issecretvalue(n) then return false end
    return n == name
end

-- The open window's profession: the name the character's records use for it, then the name
-- the window and its recipes go by. When they differ, the window's name joins db.profArt on
-- the same line, so recipe tooltips that use it find the profession too.
local function WindowProfession(c)
    local base = TS.GetBaseProfessionInfo()
    local name = ProfessionName(base)
    if issecretvalue(name) or type(name) ~= "string" then return nil end
    local profs = c.profs
    if not profs or profs[name] then return name, name end
    local line = base.professionID
    if issecretvalue(line) or type(line) ~= "number" then line = nil end
    for own in pairs(profs) do
        local ownLine = LineOfName(own)
        if ownLine and (ownLine == line or LineCalled(ownLine, name)) then
            local art = ns.db.profArt
            if not (art and art[name]) then
                ns.db.profArt = art or {}
                ns.db.profArt[name] = art and art[own] or (ownLine .. ";")
            end
            return own, name
        end
    end
    return name, name
end

-- The item a recipe makes, or nil (enchants make none). The schematic's field name
-- is the retail one, undocumented on Forever, so the recipe's item link is the fallback.
local function OutputItem(recipeID, s)
    local id = s and s.outputItemID
    if not id and TS.GetRecipeItemLink then
        local link = TS.GetRecipeItemLink(recipeID)
        id = type(link) == "string" and not issecretvalue(link) and tonumber(link:match("|Hitem:(%d+)"))
    end
    if not issecretvalue(id) and id and id > 0 then return id end
end

-- A recipe's reagents as ",itemID:qty,itemID:qty" from its schematic. The leading comma
-- lets a plain find(",<itemID>:") check whether a recipe uses an item.
local function Reagents(s)
    local slots = s and s.reagentSlotSchematics
    if type(slots) ~= "table" then return "" end
    local out
    for i = 1, #slots do
        local slot = slots[i]
        local r = slot.reagents and slot.reagents[1]
        local id, qty = r and r.itemID, slot.quantityRequired
        if not issecretvalue(id) and not issecretvalue(qty) and id and qty then
            out = (out or "") .. "," .. id .. ":" .. qty
        end
    end
    return out or ""
end

-- Account-wide facts about recipes any of your characters knows, gathered when they open
-- a profession: db.recipeInfo[profession][lowercase name] = "grey;Name;,itemID:qty,...".
-- The grey point (maxTrivialLevel) is where a recipe stops giving skill-ups. Recipes
-- nobody knows aren't stored: their names alone would cost ~50 KB across professions.
local function InfoTable(prof)
    local all = ns.db.recipeInfo
    if not all then
        all = {}
        ns.db.recipeInfo = all
    end
    local t = all[prof]
    if not t then
        t = {}
        all[prof] = t
    end
    return t
end

-- Since the alts' profession window (Recipes.lua, 2026-11-10) a value also carries, after the
-- reagents, ";recipeID;categoryID;icon;made" (the game's recipe and category IDs, its icon file,
-- how many one craft makes when more than one), each blank if not known; values saved before
-- end at the reagents. Reagent strings never hold a ";".
local INFO = "^(%d*);([^;]*);([^;]*);?(%d*);?(%d*);?(%d*);?(%d*)$"

-- grey (number or nil), display name, reagents string, then recipeID, categoryID, icon and
-- made (numbers or nil).
local function ParseInfo(v)
    if type(v) ~= "string" then return nil, nil, "" end
    local grey, name, reagents, id, cat, icon, made = v:match(INFO)
    if not name then
        -- Not in the expected shape: whatever follows the name counts as reagents, as before.
        grey, name, reagents = v:match("^(%d*);([^;]*);(.*)$")
    end
    return tonumber(grey), name, reagents or "", tonumber(id), tonumber(cat), tonumber(icon), tonumber(made)
end
ns.ParseRecipeInfo = ParseInfo

-- The stored form of a recipe's fields: the added ones without empty ones at the end (none:
-- the old three-field form).
local function JoinInfo(grey, name, reagents, id, cat, icon, made)
    local extra = (";" .. (id or "") .. ";" .. (cat or "") .. ";" .. (icon or "") .. ";"
        .. (made and made > 1 and made or "")):gsub(";+$", "")
    return (grey or "") .. ";" .. name .. ";" .. reagents .. extra
end

-- Two records of one recipe as one: each field from `main` where it has it, else from
-- `other`, so neither side's knowledge is lost (a reading without reagents, as when the game
-- gives no schematic, never wipes the reagents already known). Peer review, 2026-11-10.
local function MergeInfo(main, other)
    local g1, n1, r1, i1, c1, ic1, m1 = ParseInfo(main)
    local g2, n2, r2, i2, c2, ic2, m2 = ParseInfo(other)
    if not n1 or n1 == "" then return n2 and other or main end
    if not n2 then return main end
    return JoinInfo(g1 or g2, n1, r1 ~= "" and r1 or r2, i1 or i2, c1 or c2, ic1 or ic2, m1 or m2)
end
ns.MergeRecipeInfo = MergeInfo

function ns.RecipeGrey(prof, lname)
    local all = ns.db.recipeInfo
    local t = all and all[prof]
    return t and (ParseInfo(t[lname]))
end

-- A number from the game, or nil if it's secret or not a positive number.
local function Count(v)
    if issecretvalue(v) or type(v) ~= "number" or v <= 0 then return nil end
    return v
end

-- `made`: how many one craft makes, from the schematic (nil keeps what was recorded).
local function Record(info, r, lname, known, made)
    local grey = Count(r.maxTrivialLevel)
    local old = info[lname]
    -- Known here, or by another character (then keep the reagents they recorded).
    if known or old then
        -- What this reading says, over what was known: a field it lacks keeps its old value.
        local new = JoinInfo(grey, r.name, known or "", Count(r.recipeID), Count(r.categoryID), Count(r.icon), Count(made))
        local merged = old and MergeInfo(new, old) or new
        -- A schematic that says one is made per craft says so, though one is stored as nothing.
        if old and Count(made) == 1 then
            local g, n, reagents, id, cat, icon = ParseInfo(merged)
            merged = JoinInfo(g, n, reagents, id, cat, icon, nil)
        end
        info[lname] = merged
    end
end

-- The categories recipes are filed under, account-wide: db.recipeCategories[categoryID] =
-- "uiOrder;name" (the game's display order, then its name), for the alts' profession window.
-- Read once per category per scan.
local function RecordCategory(seen, id)
    id = Count(id)
    if not id or seen[id] or not TS.GetCategoryInfo then return end
    seen[id] = true
    local ok, cat = pcall(TS.GetCategoryInfo, id)
    local name = ok and type(cat) == "table" and cat.name
    if issecretvalue(name) or type(name) ~= "string" or name == "" or name:find(";", 1, true) then return end
    local order = cat.uiOrder
    if issecretvalue(order) or type(order) ~= "number" then order = 0 end
    ns.db.recipeCategories = ns.db.recipeCategories or {}
    ns.db.recipeCategories[id] = floor(order) .. ";" .. name
end

-- A recipe's colour for the character scanning it: Enum.TradeskillRelativeDifficulty
-- (0 orange, 1 yellow, 2 green, 3 grey), stored where `true` (known) was; true if not given.
local function Difficulty(r)
    local d = r.relativeDifficulty
    if issecretvalue(d) or type(d) ~= "number" or d < 0 or d > 3 then return true end
    return d
end

-- Every recipe name stored anywhere for a profession: any character's list or recipeInfo.
local function StoredNames(prof)
    local names = {}
    for _, c in pairs(ns.db.chars) do
        local known = c.recipes and c.recipes[prof]
        if known then
            for lname in pairs(known) do names[lname] = true end
        end
    end
    local info = ns.db.recipeInfo and ns.db.recipeInfo[prof]
    if info then
        for lname in pairs(info) do names[lname] = true end
    end
    return names
end

-- Removes recipes that don't belong to the profession from every character's lists and
-- from recipeInfo. `mine` is authoritative for every stored name (all were checked).
-- Old `true` craft values can't be checked and are left alone.
local function Repair(prof, mine)
    for _, c in pairs(ns.db.chars) do
        local known = c.recipes and c.recipes[prof]
        if known then
            for lname in pairs(known) do
                if not mine[lname] then known[lname] = nil end
            end
        end
        local crafts = c.crafts and c.crafts[prof]
        if crafts then
            for id, lname in pairs(crafts) do
                if type(lname) == "string" and not mine[lname] then crafts[id] = nil end
            end
        end
    end
    local info = ns.db.recipeInfo and ns.db.recipeInfo[prof]
    if info then
        for lname in pairs(info) do
            if not mine[lname] then info[lname] = nil end
        end
    end
end

-- c.recipes = { [professionName] = { [lowercase recipe name] = true } } and
-- c.crafts = { [professionName] = { [itemID] = lowercase recipe name } }. A profession
-- only has an entry once its window has been opened, so "missing" means "not scanned".
--
-- The game's recipe list sometimes holds other professions' recipes too (seen on build
-- 70009, after switching professions in the window), so each recipe that matters is
-- checked with GetProfessionInfoByRecipeID: learned ones, and ones already stored
-- somewhere (so strays saved by 0.2.x can be removed). Unlearned recipes nobody has are
-- skipped, which keeps this to tens of calls instead of the list's hundreds.
function ns.ScanRecipes(c)
    if not TS.IsTradeSkillReady() or TS.IsTradeSkillLinked() or TS.IsTradeSkillGuild() then return false end
    -- Stored under `prof`; the window's recipes name it `window` (usually the same).
    local prof, window = WindowProfession(c)
    if not prof then return false end
    local function Mine(id)
        local n = ProfessionName(TS.GetProfessionInfoByRecipeID(id))
        return n ~= nil and (n == window or n == prof)
    end
    local stored = StoredNames(prof)
    local ids = TS.GetAllRecipeIDs()
    local mine, found = {}, false
    local learned, crafts, reagentsOf, madeOf, learnedIDs = {}, {}, {}, {}, {}
    local unchecked, cats = nil, {}
    for _, id in ipairs(ids) do
        local r = TS.GetRecipeInfo(id)
        if r and r.name then
            local lname = r.name:lower()
            if r.learned or stored[lname] then
                if Mine(id) then
                    found, mine[lname] = true, true
                    RecordCategory(cats, r.categoryID)
                    if r.learned then
                        learned[lname], learnedIDs[id] = r, r.name
                        local s = TS.GetRecipeSchematic and TS.GetRecipeSchematic(id, false)
                        local item = OutputItem(id, s)
                        if item then crafts[item] = lname end
                        reagentsOf[lname], madeOf[lname] = Reagents(s), s and s.quantityMin
                    else
                        Record(InfoTable(prof), r, lname, nil) -- refresh the grey point
                    end
                end
            elseif not found and not unchecked then
                unchecked = id
            end
        end
    end
    -- Nothing of this profession checked yet (nothing learned or stored): make sure the
    -- list really is this profession's before recording it as empty.
    if not found and unchecked and Mine(unchecked) then
        found = true
    end
    if not found then return false end -- the wrong list: try again on the next update

    c.recipes, c.crafts = c.recipes or {}, c.crafts or {}
    local known, made = c.recipes[prof] or {}, c.crafts[prof] or {}
    wipe(known)
    wipe(made)
    local info = InfoTable(prof)
    for lname, r in pairs(learned) do
        known[lname] = Difficulty(r)
        Record(info, r, lname, reagentsOf[lname], madeOf[lname])
    end
    for item, lname in pairs(crafts) do made[item] = lname end
    c.recipes[prof], c.crafts[prof] = known, made
    -- Read under the window's own name before (1.12.0 and earlier, where the names differ):
    -- that copy goes, as the profession now has its recipes under the character's name.
    if window ~= prof and not (c.profs and c.profs[window]) then
        c.recipes[window], c.crafts[window] = nil, nil
        if c.recipesAt then c.recipesAt[window] = nil end
        -- Cooldowns move rather than go: a recorded one that's ready, or one the game can't
        -- read right now, would not come back from a fresh reading (peer review).
        local old = c.cooldowns and c.cooldowns[window]
        if old then
            local t = c.cooldowns[prof] or {}
            for name, at in pairs(old) do
                if t[name] == nil then t[name] = at end
            end
            c.cooldowns[prof], c.cooldowns[window] = t, nil
        end
    end
    -- The skill the colours above were read at: once it moves on, they may be out of date.
    -- Read now (a skill-up from crafting may not have been picked up yet).
    ns.ScanSkills(c)
    c.recipesAt = c.recipesAt or {}
    c.recipesAt[prof] = c.profs and c.profs[prof]
    Repair(prof, mine)
    ns.PruneRecipeInfo() -- other professions' strays too (a few hundred lookups, window open only)
    ns.WatchCooldowns(c, prof, learnedIDs)
    ns.craftVersion = ns.craftVersion + 1
    return true
end

function ns.RecipeLearned(c, recipeID)
    local r = TS.GetRecipeInfo(recipeID)
    local prof = ns.ProfKey(c, ProfessionName(TS.GetProfessionInfoByRecipeID(recipeID)))
    local learned = prof and c.recipes and c.recipes[prof]
    -- Only add to a profession we've scanned; a partial list would read as "not learned".
    if not (learned and r and r.name) then return end
    local lname = r.name:lower()
    learned[lname] = Difficulty(r)
    RecordCategory({}, r.categoryID)
    local s = TS.GetRecipeSchematic and TS.GetRecipeSchematic(recipeID, false)
    Record(InfoTable(prof), r, lname, Reagents(s), s and s.quantityMin)
    local crafts = c.crafts and c.crafts[prof]
    local item = crafts and OutputItem(recipeID, s)
    if item then crafts[item] = lname end
    ns.craftVersion = ns.craftVersion + 1
end

-- True when a character is at their rank's maximum (e.g. 75/75): nothing gives a
-- skill-up until they train the next rank. Saves from before 0.3.0 have no maximum.
function ns.AtRankCap(c, prof)
    local skill, max = c.profs and c.profs[prof], c.profMax and c.profMax[prof]
    return skill and max and skill >= max or false
end

-- A profession the player isn't levelling on this character (Cooking kept at 20 on every
-- alt but one; a player's request, 2026-11-28): no skill-up hints for it anywhere.
-- c.notLevelling = { [the character's own profession name] = true }, nil when none;
-- c.notLevellingAt = when the player last changed it, so a sync keeps the later choice
-- (Sync.lua Merge), even against a newer copy of the character from the other account.
function ns.NotLevelling(c, prof)
    local t = c and c.notLevelling
    return t ~= nil and prof ~= nil and t[prof] == true
end

-- Marks a character's profession as levelled (on) or not; the overview's character menu.
function ns.SetLevelling(key, prof, on)
    local c = ns.db.chars[key]
    if not (c and type(prof) == "string") then return end
    if on then
        if not (c.notLevelling and c.notLevelling[prof]) then return end
        c.notLevelling[prof] = nil
        if next(c.notLevelling) == nil then c.notLevelling = nil end
    else
        c.notLevelling = c.notLevelling or {}
        c.notLevelling[prof] = true
    end
    -- Not c.changed: that would make this whole copy of the character look newer to a sync,
    -- and a stale copy could replace the other account's newer one (Codex review,
    -- 2026-11-28). The choice goes with every sync hello on its own (Sync.lua Levelling).
    c.notLevellingAt = time()
    ns.craftVersion = ns.craftVersion + 1 -- Can craft and Skill-ups are kept per version
    if ns.InvalidateCache then ns.InvalidateCache() end
    if ns.RefreshOverview then ns.RefreshOverview() end
    if ns.CharacterWindowChanged then ns.CharacterWindowChanged() end -- its Skills page
end

-- The skill a character would gain from, or nil if nothing can give them a skill-up now.
local function SkillFor(c, prof)
    local skill = c.profs and c.profs[prof]
    if skill and not ns.AtRankCap(c, prof) and not ns.NotLevelling(c, prof) then return skill end
end

-- True if one of the character's known recipes uses the item and still gives them a
-- skill-up (not at their rank's maximum). For "Send to alt"; runs when its menu opens.
function ns.CanSkillUpWith(c, itemID)
    local info = ns.db.recipeInfo
    if not (info and c.recipes and ns.SkillupsOn()) then return false end
    local needle = "," .. itemID .. ":"
    for prof, known in pairs(c.recipes) do
        local skill, recipes = SkillFor(c, prof), info[prof]
        if skill and recipes then
            for lname in pairs(known) do
                local v = recipes[lname]
                if type(v) == "string" and v:find(needle, 1, true) then
                    local grey = ParseInfo(v)
                    if grey and skill < grey then return true end
                end
            end
        end
    end
    return false
end

-- How many of a character's known recipes in a profession still give skill-ups, or nil
-- if the profession hasn't been scanned.
function ns.SkillupCount(c, prof)
    local known = c.recipes and c.recipes[prof]
    local skill = c.profs and c.profs[prof]
    if not known or not skill then return nil end
    if ns.AtRankCap(c, prof) or ns.NotLevelling(c, prof) then return 0 end
    local n = 0
    for lname in pairs(known) do
        local grey = ns.RecipeGrey(prof, lname)
        if grey and skill < grey then n = n + 1 end
    end
    return n
end

---------------------------------------------------------------------------
-- Profession cooldowns (Mooncloth, transmutes, salt...; a player asked 2026-11-22).
-- C_TradeSkillUI.GetRecipeCooldown(recipeID) is undocumented on Forever; on retail it
-- returns the seconds left (then isDayCooldown, charges, maxCharges), and DataStore_Crafts
-- (Altoholic) reads it the same way on Forever. Read for every learned recipe while the
-- character's own profession window is open: at each recipe scan, and after each craft
-- (what it made lands in the bags: BAG_UPDATE_DELAYED). Only recipes seen on cooldown are
-- kept, c.cooldowns[profession][recipe name] = clock time it's ready (past = ready), so a
-- recipe shows only once it has been on cooldown. Not yet seen in game.

local cdChar, cdProf, cdIDs = nil, nil, {} -- whose window is open: recipe ID -> name

-- Items with a cooldown of their own that goes with a profession's (a player's request,
-- 2026-11-27): the Salt Shaker, Leatherworking, about 3 days. Not a recipe, so
-- GetRecipeCooldown can't see it: read as the hearthstone is (C_Container.GetItemCooldown,
-- Character.lua) and kept with the profession's recipe cooldowns under the item's name.
-- Item ID -> skill line.
local ITEM_COOLDOWNS = { [15846] = 165 }
local itemAsked = {} -- item ID -> true: its name was requested; read again when it arrives

-- The character's own name for the profession on skill line `line`, nil without it.
local function ProfOnLine(c, line)
    if type(c.profs) ~= "table" then return nil end
    for own in pairs(c.profs) do
        if LineOfName(own) == line then return own end
    end
    return nil
end

-- Whether `name` under c.cooldowns[prof] is an item's rather than a recipe's, so the
-- profession window's reading leaves it alone. True too while such an item's name can't be
-- read, so nothing is dropped on a guess.
local function ItemCooldownName(c, prof, name)
    for id, line in pairs(ITEM_COOLDOWNS) do
        if ProfOnLine(c, line) == prof then
            local n = GetItemNameByID(id)
            if issecretvalue(n) or n == nil or n == name then return true end
        end
    end
    return false
end

-- Reads the open window's cooldowns into the character's record; true if anything changed.
local function ReadCooldowns()
    local get, c, prof = TS.GetRecipeCooldown, cdChar, cdProf
    if not (get and c and prof) then return false end
    local now = time()
    local t = c.cooldowns and c.cooldowns[prof]
    local changed = false
    for id, name in pairs(cdIDs) do
        local ok, left = pcall(get, id)
        local had = t and t[name]
        -- A failed call, a secret or anything but a number or nil says nothing: what's
        -- stored stays.
        if not ok or issecretvalue(left) or (left ~= nil and type(left) ~= "number") then
            -- unreadable
        elseif left and left > 0 then
            local ready = floor(now + left + 0.5)
            -- Steady readings drift by a second or so: only a real change is recorded.
            if not had or had < ready - 60 or had > ready + 60 then
                if not t then
                    c.cooldowns = c.cooldowns or {}
                    t = {}
                    c.cooldowns[prof] = t
                end
                t[name], changed = ready, true
            end
        elseif had and had > now then
            t[name], changed = now, true -- no cooldown: ready early (a reset, or the game says so)
        end
    end
    -- Recipes no longer known (unlearned or renamed) go.
    if t then
        for name in pairs(t) do
            local still = false
            for _, n in pairs(cdIDs) do
                if n == name then still = true break end
            end
            if not still then still = ItemCooldownName(c, prof, name) end
            if not still then t[name], changed = nil, true end
        end
        if next(t) == nil then
            c.cooldowns[prof] = nil
            if next(c.cooldowns) == nil then c.cooldowns = nil end
        end
    end
    return changed
end

-- A cooldown recorded, ended or forgotten: an open overview shows it (its Cooldowns
-- column may appear or go). The caller bumps ns.version as for any profession change.
local function CooldownsRead()
    if ReadCooldowns() and ns.RefreshOverview then ns.RefreshOverview() end
end

-- Called by a recipe scan with its learned recipes (ID -> name); reads them at once.
function ns.WatchCooldowns(c, prof, ids)
    cdChar, cdProf = c, prof
    wipe(cdIDs)
    for id, name in pairs(ids) do cdIDs[id] = name end
    CooldownsRead()
end

-- A recipe learned with its profession's window open (from a recipe item or the trainer):
-- watched from now on, so making it at once records its cooldown.
local function WatchLearned(recipeID)
    if not cdProf then return end
    local r = TS.GetRecipeInfo(recipeID)
    if not (r and r.name and r.learned ~= false) then return end
    if ns.ProfKey(cdChar, ProfessionName(TS.GetProfessionInfoByRecipeID(recipeID))) ~= cdProf then return end
    cdIDs[recipeID] = r.name
    CooldownsRead()
end

local function StopCooldowns()
    cdChar, cdProf = nil, nil
    wipe(cdIDs)
end

-- Reads the item cooldowns (ITEM_COOLDOWNS) of a character with the profession; true if
-- anything changed. As with recipes, an item shows only once it has been on cooldown. The
-- game counts in GetTime() seconds, turned into a clock time to keep; 2 seconds or less is
-- the global cooldown. A reading of none says it's ready only with the item in the bags (one
-- in the bank may read as none).
function ns.ScanItemCooldowns(c)
    local get = C_Container and C_Container.GetItemCooldown
    if not (get and GetTime and c) then return false end
    local now, changed = time(), false
    for id, line in pairs(ITEM_COOLDOWNS) do
        local prof = ProfOnLine(c, line)
        local name = prof and GetItemNameByID(id)
        if issecretvalue(name) or type(name) ~= "string" or name == "" then
            name = nil
            if prof and C_Item.RequestLoadItemDataByID then
                itemAsked[id] = true
                C_Item.RequestLoadItemDataByID(id)
            end
        end
        local ok, start, duration = false, nil, nil
        if name then ok, start, duration = pcall(get, id) end
        if ok and not issecretvalue(start) and not issecretvalue(duration)
            and type(start) == "number" and type(duration) == "number" then
            local t = c.cooldowns and c.cooldowns[prof]
            local had = t and t[name]
            local ready = 0
            if start > 0 and duration > 2 then ready = floor(now + start + duration - GetTime() + 0.5) end
            if ready > now then
                if not had or had < ready - 60 or had > ready + 60 then
                    if not t then
                        c.cooldowns = c.cooldowns or {}
                        t = {}
                        c.cooldowns[prof] = t
                    end
                    t[name], changed = ready, true
                end
            elseif had and had > now and type(c.bags) == "table" and c.bags[id] then
                t[name], changed = now, true
            end
        end
    end
    return changed
end

local DAY, HOUR = 86400, 3600
local READY = "|cff20ff20"

-- How long until ready: "2d 4h" / "3h 20m" / "15 min" (minutes rounded up).
local function TimeLeft(left)
    local d, h, m = floor(left / DAY), floor(left % DAY / HOUR), math.ceil(left % HOUR / 60)
    if m == 60 then h, m = h + 1, 0 end
    if h == 24 then d, h = d + 1, 0 end
    local text
    if d > 0 then
        text = L["%dd %dh"]:format(d, h)
    elseif h > 0 then
        text = L["%dh %dm"]:format(h, m)
    else
        text = L["%d min"]:format(m)
    end
    return text
end

-- "ready" (green) or "ready in 2d 4h" / "3h 20m" / "15 min".
function ns.CooldownText(ready, now)
    if ready <= now then return READY .. L["ready"] .. "|r" end
    return L["ready in %s"]:format(TimeLeft(ready - now))
end

-- For the overview's Cooldowns column, without building rows: how many cooldowns are
-- ready (one per profession with any ready, as CooldownRows makes them one row), and when
-- the soonest of the rest is. nil, nil when the character has none.
local function Soonest(c, now)
    local t = c.cooldowns
    if type(t) ~= "table" or next(t) == nil then return nil, nil end
    local ready, soon = 0, nil
    for _, recipes in pairs(t) do
        local any = false
        for _, at in pairs(recipes) do
            if at <= now then
                any = true
            elseif not soon or at < soon then
                soon = at
            end
        end
        if any then ready = ready + 1 end
    end
    return ready, soon
end

-- Whether any character has a cooldown recorded: the overview's Cooldowns column shows
-- itself only then (unless the player chose).
function ns.AnyCooldowns()
    for _, c in pairs(ns.db.chars) do
        if type(c.cooldowns) == "table" and next(c.cooldowns) ~= nil then return true end
    end
    return false
end

-- The cell: green "Ready" / "2 ready" when any are, else how long until the soonest;
-- blank for a character with none.
function ns.CooldownCell(c, now)
    local ready, soon = Soonest(c, now)
    if not ready then return "" end
    if ready == 1 then return READY .. L["Ready"] .. "|r" end
    if ready > 1 then return READY .. L["%d ready"]:format(ready) .. "|r" end
    return soon and TimeLeft(soon - now) or ""
end

-- What the column sorts by (smallest first): the most ready first, then the soonest.
function ns.CooldownSortValue(c, now)
    local ready, soon = Soonest(c, now)
    if not ready then return nil end
    if ready > 0 then return now - ready end
    return soon
end

-- Seconds until some character's Cooldowns cell next changes (at most a minute, as the
-- cell counts minutes), nil when none is waiting. The overview's timed refresh.
function ns.CooldownsChangeIn(now)
    local wait
    for _, c in pairs(ns.db.chars) do
        local _, soon = Soonest(c, now)
        if soon and (not wait or soon - now < wait) then wait = soon - now end
    end
    return wait and (wait < 60 and wait or 60) or nil
end

local function ByReady(a, b)
    if a[2] ~= b[2] then return a[2] < b[2] end
    if a[4] ~= b[4] then return a[4] < b[4] end
    return a[1] < b[1]
end

-- A character's cooldowns, soonest ready first, as { name, ready at, more, profession }:
-- recipes of one profession ready together (a shared cooldown, as Classic's transmutes, or
-- all of them ready) make one row named after the first, with how many more. nil when none.
-- Built only when asked for (a tooltip or /af cooldowns).
function ns.CooldownRows(c, now)
    if type(c.cooldowns) ~= "table" then return nil end
    local all = {}
    for prof, t in pairs(c.cooldowns) do
        for name, ready in pairs(t) do
            all[#all + 1] = { name, ready > now and ready or now, 0, prof }
        end
    end
    if not all[1] then return nil end
    sort(all, ByReady)
    local rows, last = {}, nil
    for _, e in ipairs(all) do
        if last and last[4] == e[4] and e[2] - last[2] <= 60 then
            last[3] = last[3] + 1
        else
            rows[#rows + 1] = e
            last = e
        end
    end
    return rows
end

-- "Transmute: Arcanite Bar +5 more"
function ns.CooldownName(row)
    return row[3] > 0 and (row[1] .. " " .. L["+%d more"]:format(row[3])) or row[1]
end

function ns.StartProfessions()
    local char = ns.char
    local pending = false

    local function Changed()
        ns.version = ns.version + 1
        if ns.RecipesChanged then ns.RecipesChanged() end -- an open profession window showing this character
    end

    local function TryScan()
        if pending and ns.ScanRecipes(char) then
            pending = false
            Changed()
        end
    end

    -- Item cooldowns (the Salt Shaker): read when the game says a cooldown in the bags
    -- changed, at each loading screen, and with the skills (the profession may come later).
    local function ItemCooldowns()
        if ns.ScanItemCooldowns(char) then
            Changed()
            if ns.RefreshOverview then ns.RefreshOverview() end
        end
    end
    ns.On("BAG_UPDATE_COOLDOWN", ItemCooldowns)
    ns.On("PLAYER_ENTERING_WORLD", ItemCooldowns)
    -- A name requested by the scan has arrived: read again (peer review). The event is
    -- shared with other files, so this stays registered and returns at once otherwise.
    ns.On("GET_ITEM_INFO_RECEIVED", function(id, ok)
        if issecretvalue(id) or not itemAsked[id] then return end
        itemAsked[id] = nil
        if ok then ItemCooldowns() end
    end)

    ns.On("SKILL_LINES_CHANGED", function()
        ns.ScanSkills(char, true)
        ItemCooldowns()
        ns.craftVersion = ns.craftVersion + 1 -- skill-up lines depend on skill levels
        Changed()
    end)
    -- The recipe list may not be ready when the window opens; LIST_UPDATE follows.
    ns.On("TRADE_SKILL_SHOW", function() StopCooldowns() pending = true TryScan() end)
    ns.On("TRADE_SKILL_DATA_SOURCE_CHANGED", function() StopCooldowns() pending = true TryScan() end)
    ns.On("TRADE_SKILL_LIST_UPDATE", TryScan)
    ns.On("TRADE_SKILL_CLOSE", function() pending = false StopCooldowns() end)
    -- A craft started a cooldown: its item has landed in the bags. Only while the window is
    -- open and scanned (a few hundred number reads at most, no tables).
    -- Ours runs after the scanner's (registered first), so the overview is refreshed again
    -- once the cooldown is in.
    ns.On("BAG_UPDATE_DELAYED", function()
        if cdProf and ReadCooldowns() then
            Changed()
            if ns.RefreshOverview then ns.RefreshOverview() end
        end
    end)
    ns.On("NEW_RECIPE_LEARNED", function(recipeID)
        ns.RecipeLearned(char, recipeID)
        WatchLearned(recipeID)
        Changed()
    end)

    ns.ScanSkills(char)
    ns.ScanItemCooldowns(char)
end

---------------------------------------------------------------------------
-- Recipe tooltips
---------------------------------------------------------------------------
-- Profession, required skill and recipe name for a recipe item, parsed once per item.
local parsed, parsedCount = {}, 0

local function LineText(tt, data, i)
    local line = data and data.lines and data.lines[i]
    if line then return line.leftText end
    if not data or not data.lines then
        local fs = tt.GetName and tt:GetName() and _G[tt:GetName() .. "TextLeft" .. i]
        return fs and fs:GetText()
    end
end

-- The recipe's name: the item name after "Pattern: ", "Schematic: " etc., cut at the first
-- colon, ASCII or full-width ("：", bytes EF BC 9A, which Chinese clients are believed to
-- use; unverified in game). Lua patterns work on bytes, so the full-width colon is matched
-- as its three bytes in a row, never in a character class.
local FULL_COLON = "\239\188\154"
local ASCII_PREFIX = "^(.-):%s*(.+)$"
local FULL_PREFIX = "^(.-)" .. FULL_COLON .. "%s*(.+)$"
local function RecipeName(name)
    local before, after = name:match(ASCII_PREFIX)
    local beforeFull, afterFull = name:match(FULL_PREFIX)
    if afterFull and (not before or #beforeFull < #before) then return afterFull end
    return after or name
end

local function ParseRecipe(tt, id, data)
    local p = parsed[id]
    if p ~= nil then return p end
    local prof, req
    local n = data and data.lines and #data.lines or tt:NumLines()
    -- The last "Requires X (N)" is the recipe's own; earlier ones belong to the
    -- crafted item shown inside the tooltip.
    for i = 1, n do
        local text = LineText(tt, data, i)
        if not issecretvalue(text) and text then
            local pr, lv = text:match(REQUIRES)
            if pr then prof, req = pr, tonumber(lv) end
        end
    end
    local name = GetItemNameByID(id) or LineText(tt, data, 1)
    -- Only recipe items come here, so one without its "Requires" line isn't complete yet
    -- ("Retrieving item information", or lines still arriving, as in the auction house):
    -- nothing is remembered, and the next hover reads it again.
    if issecretvalue(name) or not (prof and name) then return false end
    p = { prof = prof, req = req, name = RecipeName(name):lower() }
    if parsedCount >= 200 then
        wipe(parsed)
        parsedCount = 0
    end
    parsed[id] = p
    parsedCount = parsedCount + 1
    return p
end

local function Status(c, p)
    local prof = ns.ProfKey(c, p.prof)
    local skill = c.profs and c.profs[prof]
    if not skill then return nil end
    local known = c.recipes and c.recipes[prof]
    if known and known[p.name] then return KNOWN end
    if skill < p.req then return NEEDS_SKILL, skill end
    if not known then return NOT_SCANNED end
    return CAN_LEARN
end

-- Whether a character knows a recipe item or can learn it now (Upgrades.lua: an item it
-- makes that binds on pickup only reaches those who can craft it).
function ns.RecipeOpenTo(c, tt, id, data)
    local p = ParseRecipe(tt, id, data)
    local status = p and Status(c, p)
    return status == KNOWN or status == CAN_LEARN
end

-- Rows are reused between hovers: keys, statuses, skills and texts in parallel arrays.
local rowKey, rowStatus, rowSkill, rowText = {}, {}, {}, {}
local lastId, lastVer, rows = nil, nil, 0

local function Before(i, j)
    if rowStatus[i] ~= rowStatus[j] then return rowStatus[i] < rowStatus[j] end
    return rowKey[i] < rowKey[j]
end

local function BuildRows(p)
    rows = 0
    local function Add(key, c)
        local status, skill = Status(c, p)
        if not status then return end
        rows = rows + 1
        rowKey[rows], rowStatus[rows], rowSkill[rows] = key, status, skill
    end
    Add(ns.charKey, ns.char)
    local first = rows -- the current character stays on top
    for key, c in pairs(ns.db.chars) do
        if key ~= ns.charKey and not ns.TipHidden(c) then Add(key, c) end
    end
    -- Insertion sort of everyone after the current character.
    for i = first + 2, rows do
        local k, s, sk = rowKey[i], rowStatus[i], rowSkill[i]
        local j = i - 1
        rowKey[0], rowStatus[0] = k, s
        while j > first and Before(0, j) do
            rowKey[j + 1], rowStatus[j + 1], rowSkill[j + 1] = rowKey[j], rowStatus[j], rowSkill[j]
            j = j - 1
        end
        rowKey[j + 1], rowStatus[j + 1], rowSkill[j + 1] = k, s, sk
    end
    -- Texts are built here, once per item, so hovering again allocates nothing. (No
    -- skill-up levels here: the owner found them confusing on recipe items.)
    for i = 1, rows do
        rowText[i] = STATUS_TEXT[rowStatus[i]] or ("|cffff2020" .. L["Needs %s (%s)"]:format(p.req, rowSkill[i]) .. "|r")
    end
end

function ns.AddRecipeLines(tt, id, data)
    local _, _, _, _, _, classID = GetItemInfoInstant(id)
    if classID ~= RECIPE_CLASS then return end
    local p = ParseRecipe(tt, id, data)
    if not p then return end
    if id ~= lastId or ns.version ~= lastVer then
        lastId, lastVer = id, ns.version
        BuildRows(p)
    end
    if rows == 0 then return end
    tt:AddLine(" ")
    tt:AddLine(p.prof .. " (" .. p.req .. ")", 1, 0.82, 0)
    local chars = ns.db.chars
    for i = 1, rows do
        local key = rowKey[i]
        tt:AddDoubleLine(ns.ListName(key, chars[key]), rowText[i], 1, 1, 1, 1, 1, 1)
    end
end

---------------------------------------------------------------------------
-- Character order for the item tooltips below: you first, then by name. Rebuilt only
-- when recipes, skills or settings change (ns.craftVersion).
---------------------------------------------------------------------------
local order, orderVer = {}, nil

local function Order()
    if orderVer == ns.craftVersion then return order end
    orderVer = ns.craftVersion
    wipe(order)
    for key, c in pairs(ns.db.chars) do
        if key ~= ns.charKey and not ns.TipHidden(c) then order[#order + 1] = key end
    end
    sort(order)
    table.insert(order, 1, ns.charKey)
    return order
end

---------------------------------------------------------------------------
-- "Can craft" on item tooltips
---------------------------------------------------------------------------
-- Everyone who can make the hovered item, looked up directly (one table lookup per
-- character and profession, ~0.1 us), with only the last item's lines kept. An index of
-- every craftable item was slower overall: it cost ~14 us and ~20 KB of garbage each
-- time any skill changed.
local lastCraft, lastCraftId, lastCraftVer = false, nil, nil

local function FindCrafters(id)
    local chars, skillups = ns.db.chars, ns.SkillupsOn()
    local list = false
    for _, key in ipairs(Order()) do
        local c = chars[key]
        if c and c.crafts then
            for prof, items in pairs(c.crafts) do
                if items[id] then
                    -- 0.2.x filed some items under other professions too (as true): the
                    -- entry holding the recipe's name is the one it's made with.
                    prof = ns.CraftProf(c.crafts, prof, id)
                    local lname = c.crafts[prof][id]
                    local text = ns.ListName(key, c)
                    -- Saves from before 0.3.0 hold true here, so the grey point is unknown.
                    local grey = skillups and type(lname) == "string" and ns.RecipeGrey(prof, lname)
                    local skill = grey and SkillFor(c, prof)
                    if skill and skill < grey then text = text .. LIGHT .. " · " .. L["skill-ups to %s"]:format(grey) .. "|r" end
                    list = list or {}
                    list[#list + 1] = "  " .. text
                    break -- once per character, even if two professions make it
                end
            end
        end
    end
    return list
end

-- A heading, then one character per line, so the tooltip never gets wide.
function ns.AddCraftLines(tt, id)
    if id ~= lastCraftId or lastCraftVer ~= ns.craftVersion then
        lastCraftId, lastCraftVer, lastCraft = id, ns.craftVersion, FindCrafters(id)
    end
    local list = lastCraft
    if not list then return end
    tt:AddLine(" ")
    tt:AddLine(L["Can craft"], 1, 0.82, 0)
    for i = 1, #list do tt:AddLine(list[i], 1, 1, 1) end
end

-- recipeInfo entries no character knows under that profession: after /af delete, and
-- after each profession scan (which also clears strays saved by 0.2.x under professions
-- nobody has opened since).
function ns.PruneRecipeInfo()
    local info = ns.db.recipeInfo
    if not info then return end
    for prof, recipes in pairs(info) do
        for lname in pairs(recipes) do
            local known = false
            for _, c in pairs(ns.db.chars) do
                if c.recipes and c.recipes[prof] and c.recipes[prof][lname] then known = true break end
            end
            if not known then recipes[lname] = nil end
        end
    end
end

---------------------------------------------------------------------------
-- "Skill-ups" on reagent tooltips
---------------------------------------------------------------------------
-- For the hovered item: the known recipes that use it and still give their character a
-- skill-up, as { recipe, who, recipe, who, ..., n = lines, more = "+N more" } (false if
-- none). Each character shows their 2 recipes with the most skill-ups left (grey point
-- minus skill); you come first, then the others by their best recipe, up to 6 lines.
-- Found by searching the known recipes' reagent strings (about 0.02 ms), so there's no
-- index in memory; only the last item's result is kept, which covers the tooltip
-- refreshing while you hover.
local lastUse, lastUseId, usesVer = false, nil, nil

-- More skill-ups left first; the same number, by recipe name.
local function Better(left, name, otherLeft, otherName)
    return left > otherLeft or (left == otherLeft and name < otherName)
end

local function ByBest(a, b)
    if a.best ~= b.best then return a.best > b.best end
    return a.key < b.key
end

local function FindUses(id)
    local info, chars = ns.db.recipeInfo, ns.db.chars
    local needle = "," .. id .. ":"
    local blocks, total = nil, 0
    for _, key in ipairs(Order()) do
        local c = chars[key]
        if c and c.recipes then
            -- This character's two best recipes: left (skill-ups left), name, grey.
            local l1, n1, g1, l2, n2, g2
            for prof, known in pairs(c.recipes) do
                local skill = SkillFor(c, prof)
                local recipes = info[prof]
                if skill and recipes then
                    for lname in pairs(known) do
                        local v = recipes[lname]
                        if type(v) == "string" and v:find(needle, 1, true) then
                            local grey, name = ParseInfo(v)
                            if grey and skill < grey then
                                total = total + 1
                                local left = grey - skill
                                if not l1 or Better(left, name, l1, n1) then
                                    l2, n2, g2 = l1, n1, g1
                                    l1, n1, g1 = left, name, grey
                                elseif not l2 or Better(left, name, l2, n2) then
                                    l2, n2, g2 = left, name, grey
                                end
                            end
                        end
                    end
                end
            end
            if l1 then
                local who = ns.ListShortName(key, c) .. LIGHT .. " · "
                local block = { key = key, best = l1, "  " .. n1, who .. L["to %s"]:format(g1) .. "|r" }
                if l2 then block[3], block[4] = "  " .. n2, who .. L["to %s"]:format(g2) .. "|r" end
                blocks = blocks or {}
                blocks[#blocks + 1] = block
            end
        end
    end
    if not blocks then return false end
    -- You stay first; everyone else by their best recipe.
    local first = blocks[1].key == ns.charKey and 2 or 1
    if #blocks > first then
        local rest = {}
        for i = first, #blocks do rest[#rest + 1] = blocks[i] end
        sort(rest, ByBest)
        for i, block in ipairs(rest) do blocks[first + i - 1] = block end
    end
    local list = { n = 0 }
    for _, block in ipairs(blocks) do
        for i = 1, #block, 2 do
            if list.n == MAX_SKILLUP_LINES then break end
            list.n = list.n + 1
            list[list.n * 2 - 1], list[list.n * 2] = block[i], block[i + 1]
        end
    end
    if total > list.n then list.more = "  " .. L["+%d more"]:format(total - list.n) end
    return list
end

function ns.AddSkillupLines(tt, id)
    if not ns.SkillupsOn() or not ns.db.recipeInfo then return end
    if usesVer ~= ns.craftVersion then
        usesVer, lastUseId = ns.craftVersion, nil
    end
    if id ~= lastUseId then
        lastUseId, lastUse = id, FindUses(id)
    end
    local list = lastUse
    if not list then return end
    tt:AddLine(" ")
    tt:AddLine(L["Skill-ups"], 1, 0.82, 0)
    for i = 1, list.n do
        tt:AddDoubleLine(list[i * 2 - 1], list[i * 2], 1, 1, 1, 1, 1, 1)
    end
    if list.more then tt:AddLine(list.more, 0.75, 0.75, 0.75) end
end
