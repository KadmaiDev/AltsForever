-- Alts Forever professions: records each character's profession skill levels and
-- learned recipes, shows on recipe items which characters know or can learn them,
-- on craftable items which characters can make them, and on reagents which of your
-- characters can still skill up with them.
local _, ns = ...

local pairs, ipairs, wipe, tonumber, type, sort = pairs, ipairs, wipe, tonumber, type, table.sort
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
    "|cff20ff20Known|r",
    "|cffffd100Can learn|r",
    nil, -- built per row: "Needs 120 (107)"
    "|cff9d9d9dNot scanned|r",
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
function ns.ScanSkills(c)
    local profs, maxes = c.profs or {}, c.profMax or {}
    c.profs, c.profMax = profs, maxes
    wipe(profs)
    wipe(maxes)
    local function Add(index)
        if not index then return end
        local name, _, skill, max = GetProfessionInfo(index)
        if name and not issecretvalue(skill) and skill then
            profs[name] = skill
            if max and not issecretvalue(max) and max > 0 then maxes[name] = max end
            return name
        end
    end
    local a, b, c3, d, e, f = GetProfessions()
    c.prof1, c.prof2 = Add(a), Add(b)
    Add(c3) Add(d) Add(e) Add(f)
end

local function ProfessionName(info)
    return info and (info.professionName or info.parentProfessionName)
end

-- The item a recipe makes, or nil (enchants make none). The schematic's field name
-- is the retail one, undocumented on Forever, so the recipe's item link is the fallback.
local function OutputItem(recipeID, s)
    local id = s and s.outputItemID
    if not id and TS.GetRecipeItemLink then
        local link = TS.GetRecipeItemLink(recipeID)
        id = type(link) == "string" and not issecretvalue(link) and tonumber(link:match("|Hitem:(%d+)"))
    end
    if id and not issecretvalue(id) and id > 0 then return id end
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
        if id and qty and not issecretvalue(id) and not issecretvalue(qty) then
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

-- grey (number or nil), display name, reagents string.
local function ParseInfo(v)
    if type(v) ~= "string" then return nil, nil, "" end
    local grey, name, reagents = v:match("^(%d*);([^;]*);(.*)$")
    return tonumber(grey), name, reagents or ""
end

function ns.RecipeGrey(prof, lname)
    local all = ns.db.recipeInfo
    local t = all and all[prof]
    return t and (ParseInfo(t[lname]))
end

local function Record(info, r, lname, known)
    local grey = r.maxTrivialLevel
    if issecretvalue(grey) or type(grey) ~= "number" or grey <= 0 then grey = nil end
    local old = info[lname]
    -- Known here, or by another character (then keep the reagents they recorded).
    if known or old then
        local _, _, reagents = ParseInfo(old)
        info[lname] = (grey or "") .. ";" .. r.name .. ";" .. (known or reagents)
    end
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
    local prof = ProfessionName(TS.GetBaseProfessionInfo())
    if not prof then return false end
    local stored = StoredNames(prof)
    local ids = TS.GetAllRecipeIDs()
    local mine, found = {}, false
    local learned, crafts, reagentsOf = {}, {}, {}
    local unchecked
    for _, id in ipairs(ids) do
        local r = TS.GetRecipeInfo(id)
        if r and r.name then
            local lname = r.name:lower()
            if r.learned or stored[lname] then
                if ProfessionName(TS.GetProfessionInfoByRecipeID(id)) == prof then
                    found, mine[lname] = true, true
                    if r.learned then
                        learned[lname] = r
                        local s = TS.GetRecipeSchematic and TS.GetRecipeSchematic(id, false)
                        local item = OutputItem(id, s)
                        if item then crafts[item] = lname end
                        reagentsOf[lname] = Reagents(s)
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
    if not found and unchecked and ProfessionName(TS.GetProfessionInfoByRecipeID(unchecked)) == prof then
        found = true
    end
    if not found then return false end -- the wrong list: try again on the next update

    c.recipes, c.crafts = c.recipes or {}, c.crafts or {}
    local known, made = c.recipes[prof] or {}, c.crafts[prof] or {}
    wipe(known)
    wipe(made)
    local info = InfoTable(prof)
    for lname, r in pairs(learned) do
        known[lname] = true
        Record(info, r, lname, reagentsOf[lname])
    end
    for item, lname in pairs(crafts) do made[item] = lname end
    c.recipes[prof], c.crafts[prof] = known, made
    Repair(prof, mine)
    ns.PruneRecipeInfo() -- other professions' strays too (a few hundred lookups, window open only)
    ns.craftVersion = ns.craftVersion + 1
    return true
end

function ns.RecipeLearned(c, recipeID)
    local r = TS.GetRecipeInfo(recipeID)
    local prof = ProfessionName(TS.GetProfessionInfoByRecipeID(recipeID))
    local learned = prof and c.recipes and c.recipes[prof]
    -- Only add to a profession we've scanned; a partial list would read as "not learned".
    if not (learned and r and r.name) then return end
    local lname = r.name:lower()
    learned[lname] = true
    local s = TS.GetRecipeSchematic and TS.GetRecipeSchematic(recipeID, false)
    Record(InfoTable(prof), r, lname, Reagents(s))
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

-- The skill a character would gain from, or nil if nothing can give them a skill-up now.
local function SkillFor(c, prof)
    local skill = c.profs and c.profs[prof]
    if skill and not ns.AtRankCap(c, prof) then return skill end
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
    if ns.AtRankCap(c, prof) then return 0 end
    local n = 0
    for lname in pairs(known) do
        local grey = ns.RecipeGrey(prof, lname)
        if grey and skill < grey then n = n + 1 end
    end
    return n
end

function ns.StartProfessions()
    local char = ns.char
    local pending = false

    local function Changed()
        ns.version = ns.version + 1
    end

    local function TryScan()
        if pending and ns.ScanRecipes(char) then
            pending = false
            Changed()
        end
    end

    ns.On("SKILL_LINES_CHANGED", function()
        ns.ScanSkills(char)
        ns.craftVersion = ns.craftVersion + 1 -- skill-up lines depend on skill levels
        Changed()
    end)
    -- The recipe list may not be ready when the window opens; LIST_UPDATE follows.
    ns.On("TRADE_SKILL_SHOW", function() pending = true TryScan() end)
    ns.On("TRADE_SKILL_DATA_SOURCE_CHANGED", function() pending = true TryScan() end)
    ns.On("TRADE_SKILL_LIST_UPDATE", TryScan)
    ns.On("TRADE_SKILL_CLOSE", function() pending = false end)
    ns.On("NEW_RECIPE_LEARNED", function(recipeID)
        ns.RecipeLearned(char, recipeID)
        Changed()
    end)

    ns.ScanSkills(char)
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

local function ParseRecipe(tt, id, data)
    local p = parsed[id]
    if p ~= nil then return p end
    local prof, req
    local n = data and data.lines and #data.lines or tt:NumLines()
    -- The last "Requires X (N)" is the recipe's own; earlier ones belong to the
    -- crafted item shown inside the tooltip.
    for i = 1, n do
        local text = LineText(tt, data, i)
        if text and not issecretvalue(text) then
            local pr, lv = text:match(REQUIRES)
            if pr then prof, req = pr, tonumber(lv) end
        end
    end
    local name = GetItemNameByID(id) or LineText(tt, data, 1)
    p = false
    if prof and name then
        p = { prof = prof, req = req, name = (name:match("^.-:%s*(.+)$") or name):lower() }
    end
    if parsedCount >= 200 then
        wipe(parsed)
        parsedCount = 0
    end
    parsed[id] = p
    parsedCount = parsedCount + 1
    return p
end

local function Status(c, p)
    local skill = c.profs and c.profs[p.prof]
    if not skill then return nil end
    local known = c.recipes and c.recipes[p.prof]
    if known and known[p.name] then return KNOWN end
    if skill < p.req then return NEEDS_SKILL, skill end
    if not known then return NOT_SCANNED end
    return CAN_LEARN
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
        if key ~= ns.charKey then Add(key, c) end
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
        rowText[i] = STATUS_TEXT[rowStatus[i]] or ("|cffff2020Needs " .. p.req .. " (" .. rowSkill[i] .. ")|r")
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
        tt:AddDoubleLine(ns.ColoredName(key, chars[key]), rowText[i], 1, 1, 1, 1, 1, 1)
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
    for key in pairs(ns.db.chars) do
        if key ~= ns.charKey then order[#order + 1] = key end
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
                local lname = items[id]
                if lname then
                    local text = ns.ColoredName(key, c)
                    -- Saves from before 0.3.0 hold true here, so the grey point is unknown.
                    local grey = skillups and type(lname) == "string" and ns.RecipeGrey(prof, lname)
                    local skill = grey and SkillFor(c, prof)
                    if skill and skill < grey then text = text .. LIGHT .. " · skill-ups to " .. grey .. "|r" end
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
    tt:AddLine("Can craft", 1, 0.82, 0)
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
                local who = ns.ShortName(key, c) .. LIGHT .. " · to "
                local block = { key = key, best = l1, "  " .. n1, who .. g1 .. "|r" }
                if l2 then block[3], block[4] = "  " .. n2, who .. g2 .. "|r" end
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
    if total > list.n then list.more = "  +" .. (total - list.n) .. " more" end
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
    tt:AddLine("Skill-ups", 1, 0.82, 0)
    for i = 1, list.n do
        tt:AddDoubleLine(list[i * 2 - 1], list[i * 2], 1, 1, 1, 1, 1, 1)
    end
    if list.more then tt:AddLine(list.more, 0.75, 0.75, 0.75) end
end
