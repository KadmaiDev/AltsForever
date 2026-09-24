-- Alts Forever professions: records each character's profession skill levels and
-- learned recipes, shows on recipe items which characters know or can learn them,
-- and on craftable items which characters can make them.
local _, ns = ...

local pairs, ipairs, wipe, tonumber, type = pairs, ipairs, wipe, tonumber, type
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

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------
-- c.profs = { [professionName] = skillLevel }; c.prof1/c.prof2 name the two main
-- professions (GetProfessions lists those first, then the secondary ones).
function ns.ScanSkills(c)
    local profs = c.profs or {}
    c.profs = profs
    wipe(profs)
    local function Add(index)
        if not index then return end
        local name, _, skill = GetProfessionInfo(index)
        if name and not issecretvalue(skill) and skill then
            profs[name] = skill
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
local function OutputItem(recipeID)
    local s = TS.GetRecipeSchematic and TS.GetRecipeSchematic(recipeID, false)
    local id = s and s.outputItemID
    if not id and TS.GetRecipeItemLink then
        local link = TS.GetRecipeItemLink(recipeID)
        id = type(link) == "string" and not issecretvalue(link) and tonumber(link:match("|Hitem:(%d+)"))
    end
    if id and not issecretvalue(id) and id > 0 then return id end
end

-- c.recipes = { [professionName] = { [lowercase recipe name] = true } } and
-- c.crafts = { [professionName] = { [itemID] = true } }. A profession only has an
-- entry once its window has been opened, so "missing" means "not scanned".
function ns.ScanRecipes(c)
    if not TS.IsTradeSkillReady() or TS.IsTradeSkillLinked() or TS.IsTradeSkillGuild() then return false end
    local prof = ProfessionName(TS.GetBaseProfessionInfo())
    if not prof then return false end
    c.recipes, c.crafts = c.recipes or {}, c.crafts or {}
    local learned, crafts = c.recipes[prof] or {}, c.crafts[prof] or {}
    wipe(learned)
    wipe(crafts)
    for _, id in ipairs(TS.GetAllRecipeIDs()) do
        local r = TS.GetRecipeInfo(id)
        if r and r.learned and r.name then
            learned[r.name:lower()] = true
            local item = OutputItem(id)
            if item then crafts[item] = true end
        end
    end
    c.recipes[prof], c.crafts[prof] = learned, crafts
    ns.craftVersion = ns.craftVersion + 1
    return true
end

function ns.RecipeLearned(c, recipeID)
    local r = TS.GetRecipeInfo(recipeID)
    local prof = ProfessionName(TS.GetProfessionInfoByRecipeID(recipeID))
    local learned = prof and c.recipes and c.recipes[prof]
    -- Only add to a profession we've scanned; a partial list would read as "not learned".
    if not (learned and r and r.name) then return end
    learned[r.name:lower()] = true
    local crafts = c.crafts and c.crafts[prof]
    local item = crafts and OutputItem(recipeID)
    if item then
        crafts[item] = true
        ns.craftVersion = ns.craftVersion + 1
    end
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

-- Rows are reused between hovers: keys, statuses and skills in parallel arrays.
local rowKey, rowStatus, rowSkill = {}, {}, {}
local lastId, lastVer, rows = nil, nil, 0

local function Before(i, j)
    if rowStatus[i] ~= rowStatus[j] then return rowStatus[i] < rowStatus[j] end
    return rowKey[i] < rowKey[j]
end

local function BuildRows(p)
    rows = 0
    local db = ns.db
    local function Add(key, c)
        local status, skill = Status(c, p)
        if not status then return end
        rows = rows + 1
        rowKey[rows], rowStatus[rows], rowSkill[rows] = key, status, skill
    end
    Add(ns.charKey, ns.char)
    local first = rows -- the current character stays on top
    for key, c in pairs(db.chars) do
        if key ~= ns.charKey and (not db.realmOnly or c.realm == ns.realm) then Add(key, c) end
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
        local key, status = rowKey[i], rowStatus[i]
        local text = STATUS_TEXT[status]
            or ("|cffff2020Needs " .. p.req .. " (" .. rowSkill[i] .. ")|r")
        tt:AddDoubleLine(ns.ColoredName(key, chars[key]), text, 1, 1, 1, 1, 1, 1)
    end
end

---------------------------------------------------------------------------
-- "Can craft" on item tooltips
---------------------------------------------------------------------------
-- itemID -> list of coloured names of everyone who can make it, built in one pass
-- over all characters the first time an item is hovered after crafts change.
-- lastKey remembers who was added last, so a character whose two professions make
-- the same item is listed once.
local crafters, lastKey, craftersVer = {}, {}, nil
local sortedKeys = {}

local function AddCrafter(key, c)
    if not c.crafts then return end
    local name = ns.ColoredName(key, c)
    for _, items in pairs(c.crafts) do
        for id in pairs(items) do
            if lastKey[id] ~= key then
                lastKey[id] = key
                local list = crafters[id]
                if list then list[#list + 1] = name else crafters[id] = { name } end
            end
        end
    end
end

local function BuildCrafters()
    wipe(crafters)
    wipe(lastKey)
    wipe(sortedKeys)
    local db = ns.db
    for key, c in pairs(db.chars) do
        if key ~= ns.charKey and (not db.realmOnly or c.realm == ns.realm) then sortedKeys[#sortedKeys + 1] = key end
    end
    table.sort(sortedKeys)
    AddCrafter(ns.charKey, ns.char) -- you first, then by name
    for _, key in ipairs(sortedKeys) do AddCrafter(key, db.chars[key]) end
end

-- A heading, then one character per line, so the tooltip never gets wide.
function ns.AddCraftLines(tt, id)
    if craftersVer ~= ns.craftVersion then
        craftersVer = ns.craftVersion
        BuildCrafters()
    end
    local list = crafters[id]
    if not list then return end
    tt:AddLine(" ")
    tt:AddLine("Can craft", 1, 0.82, 0)
    for i = 1, #list do tt:AddLine("  " .. list[i], 1, 1, 1) end
end
