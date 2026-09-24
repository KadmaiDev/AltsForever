-- Alts Forever professions: records each character's profession skill levels and
-- learned recipes, and shows on recipe items which characters know or can learn them.
local _, ns = ...

local pairs, ipairs, wipe = pairs, ipairs, wipe
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

-- c.recipes = { [professionName] = { [lowercase recipe name] = true } }. A profession
-- only has an entry once its window has been opened, so "missing" means "not scanned".
function ns.ScanRecipes(c)
    if not TS.IsTradeSkillReady() or TS.IsTradeSkillLinked() or TS.IsTradeSkillGuild() then return false end
    local prof = ProfessionName(TS.GetBaseProfessionInfo())
    if not prof then return false end
    c.recipes = c.recipes or {}
    local learned = c.recipes[prof] or {}
    wipe(learned)
    for _, id in ipairs(TS.GetAllRecipeIDs()) do
        local r = TS.GetRecipeInfo(id)
        if r and r.learned and r.name then learned[r.name:lower()] = true end
    end
    c.recipes[prof] = learned
    return true
end

function ns.RecipeLearned(c, recipeID)
    local r = TS.GetRecipeInfo(recipeID)
    local prof = ProfessionName(TS.GetProfessionInfoByRecipeID(recipeID))
    local learned = prof and c.recipes and c.recipes[prof]
    -- Only add to a profession we've scanned; a partial list would read as "not learned".
    if learned and r and r.name then learned[r.name:lower()] = true end
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
