-- Alts Forever upgrades: on an item you could give to one of your characters (binds when
-- equipped, not yet bound), or a recipe that makes one, which of your characters it would
-- be an upgrade for, in which slot and by about how much. An item that's yours alone (bind
-- on pickup or soulbound) shows your own row only; a recipe whose item binds on pickup,
-- only the characters who know the recipe or can learn it.
--
-- An item's score is its stats (C_Item.GetItemStats) times what each stat is worth to the
-- character's role. It's an upgrade when it beats what they wear in that slot (their gear
-- as last recorded); rings and trinkets against the weaker of the two, a two-hander
-- against main and off hand together. The role is the player's choice for that character,
-- else their talents' (Talents.lua), else their class's levelling default.
--
-- Scores are cached per item link and role (numbers only); the rows for the last item are
-- kept, so the tooltip refreshing while you hover rebuilds nothing.
local _, ns = ...
if ns.disabled then return end -- another copy of Alts Forever is running (Core.lua)
local L = ns.L

local pairs, ipairs, next, type, wipe, floor, max = pairs, ipairs, next, type, wipe, math.floor, math.max
local issecretvalue = issecretvalue or function() return false end
local GetItemInfoInstant, GetItemInfo, GetItemStats = C_Item.GetItemInfoInstant, C_Item.GetItemInfo, C_Item.GetItemStats

local RECIPE_CLASS, WEAPON_CLASS, ARMOR_CLASS = 9, 2, 4
local BIND_ON_EQUIP = 2
local MIN_GAIN = 3      -- % below which a gain is noise
local MAX_ROWS = 5
local LEVEL_AHEAD = 5   -- characters up to this many levels short show as "at level N"
local MAX_SCORES = 2000 -- cached scores before the cache starts again
local NEW = math.huge   -- the gain for an empty slot
local GREEN, GREY = "|cff20ff20", "|cff9d9d9d"

-- Stats as GetItemStats names them (checked in game 2026-10-05 for strength, spirit, spell
-- power, armour and dps; the rest follow retail's names).
local STATS = {
    ITEM_MOD_STRENGTH_SHORT = "str", ITEM_MOD_AGILITY_SHORT = "agi", ITEM_MOD_STAMINA_SHORT = "sta",
    ITEM_MOD_INTELLECT_SHORT = "int", ITEM_MOD_SPIRIT_SHORT = "spi",
    ITEM_MOD_ATTACK_POWER_SHORT = "ap", ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "rap",
    ITEM_MOD_SPELL_POWER_SHORT = "sp", ITEM_MOD_SPELL_HEALING_DONE_SHORT = "heal",
    ITEM_MOD_POWER_REGEN0_SHORT = "mp5", ITEM_MOD_MANA_REGENERATION_SHORT = "mp5",
    ITEM_MOD_CRIT_RATING_SHORT = "crit", ITEM_MOD_CRIT_MELEE_RATING_SHORT = "crit",
    ITEM_MOD_CRIT_RANGED_RATING_SHORT = "crit", ITEM_MOD_HIT_RATING_SHORT = "hit",
    ITEM_MOD_HIT_MELEE_RATING_SHORT = "hit", ITEM_MOD_HIT_RANGED_RATING_SHORT = "hit",
    ITEM_MOD_CRIT_SPELL_RATING_SHORT = "spellcrit", ITEM_MOD_HIT_SPELL_RATING_SHORT = "spellhit",
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "def", ITEM_MOD_DODGE_RATING_SHORT = "dodge",
    ITEM_MOD_PARRY_RATING_SHORT = "parry", ITEM_MOD_BLOCK_RATING_SHORT = "block",
    ITEM_MOD_BLOCK_VALUE_SHORT = "blockvalue",
    RESISTANCE0_NAME = "armor", ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "dps",
}

-- What a point of each stat is worth, per role, for levelling (Classic's rules: 1 crit or
-- hit = 1%). A weapon's dps counts as `dps`, or `rdps` in the ranged slot. The hunter
-- weights are the ones Upgrade Trail checked against real items.
local WEIGHTS = {
    hunter = { agi = 2.4, ap = 1, rap = 1, sta = 0.4, int = 0.3, spi = 0.05, crit = 22, hit = 16,
        armor = 0.02, dps = 2, rdps = 14 },
    rogue = { agi = 2, str = 1, ap = 1, sta = 0.4, crit = 20, hit = 18, armor = 0.02, dps = 10, rdps = 1 },
    warrior = { str = 2, agi = 1.4, ap = 1, sta = 0.5, crit = 20, hit = 18, armor = 0.02, dps = 12, rdps = 1 },
    paladin = { str = 2, agi = 1, ap = 1, sta = 0.5, int = 0.4, sp = 0.3, crit = 18, hit = 16,
        armor = 0.02, dps = 12 },
    enhancement = { str = 2, agi = 1.2, ap = 1, sta = 0.5, int = 0.4, crit = 18, hit = 16, armor = 0.02, dps = 12 },
    feral = { str = 2, agi = 1.6, ap = 1, sta = 0.8, crit = 18, hit = 16, armor = 0.05, def = 0.5, dodge = 6 },
    tank = { sta = 1.5, str = 1, agi = 1, armor = 0.1, def = 1.5, dodge = 12, parry = 10, block = 6,
        blockvalue = 0.5, ap = 0.3, hit = 8, dps = 4, rdps = 0.5 },
    caster = { sp = 1, int = 0.5, spi = 0.3, sta = 0.4, mp5 = 1.5, spellcrit = 10, spellhit = 12, rdps = 3 },
    healer = { heal = 1, sp = 0.9, int = 0.6, spi = 0.5, sta = 0.3, mp5 = 2, spellcrit = 8, rdps = 1 },
}

-- The word for each role, in menus and in /af role.
local ROLE_NAMES = {
    hunter = L["Ranged"], rogue = L["Melee"], warrior = L["Melee"], paladin = L["Melee"],
    enhancement = L["Melee"], feral = L["Feral"], tank = L["Tank"], caster = L["Caster"], healer = L["Healer"],
}
local ROLE_WORDS = {
    hunter = "ranged", rogue = "melee", warrior = "melee", paladin = "melee", enhancement = "melee",
    feral = "feral", tank = "tank", caster = "caster", healer = "healer",
}

-- Per class (Classic's rules): the role of each talent tab, the levelling default, armour
-- by subclass (the level it can be worn from: mail and plate come at 40), weapon
-- subclasses it can learn, and the level dual wield comes at.
local CLASSES = {
    WARRIOR = { tabs = { "warrior", "warrior", "tank" }, default = "warrior", dualWield = 20,
        armor = { [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1 },
        weapons = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 } },
    PALADIN = { tabs = { "healer", "tank", "paladin" }, default = "paladin",
        armor = { [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1, [7] = 1 },
        weapons = { 0, 1, 4, 5, 6, 7, 8 } },
    HUNTER = { tabs = { "hunter", "hunter", "hunter" }, default = "hunter", dualWield = 20,
        armor = { [1] = 1, [2] = 1, [3] = 40 },
        weapons = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 } },
    ROGUE = { tabs = { "rogue", "rogue", "rogue" }, default = "rogue", dualWield = 10,
        armor = { [1] = 1, [2] = 1 },
        weapons = { 2, 3, 4, 7, 13, 15, 16, 18 } },
    PRIEST = { tabs = { "healer", "healer", "caster" }, default = "caster",
        armor = { [1] = 1 }, weapons = { 4, 10, 15, 19 } },
    SHAMAN = { tabs = { "caster", "enhancement", "healer" }, default = "enhancement",
        armor = { [1] = 1, [2] = 1, [3] = 40, [6] = 1, [9] = 1 },
        weapons = { 0, 1, 4, 5, 10, 13, 15 } },
    MAGE = { tabs = { "caster", "caster", "caster" }, default = "caster",
        armor = { [1] = 1 }, weapons = { 7, 10, 15, 19 } },
    WARLOCK = { tabs = { "caster", "caster", "caster" }, default = "caster",
        armor = { [1] = 1 }, weapons = { 7, 10, 15, 19 } },
    DRUID = { tabs = { "caster", "feral", "healer" }, default = "feral",
        armor = { [1] = 1, [2] = 1, [8] = 1 }, weapons = { 4, 5, 10, 13, 15 } },
}
for _, cls in pairs(CLASSES) do
    local set = {}
    for _, sub in ipairs(cls.weapons) do set[sub] = true end
    cls.weapons = set
    cls.choices = {} -- the class's roles, tab order, once each
    for _, role in ipairs(cls.tabs) do
        local seen = false
        for _, r in ipairs(cls.choices) do if r == role then seen = true end end
        if not seen then cls.choices[#cls.choices + 1] = role end
    end
end

-- Inventory slots an item goes in, by its equip location.
local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 },
    INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 },
    INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 },
    INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
local RANGED = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }
local OFF_HAND_ITEMS = { INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true }

---------------------------------------------------------------------------
-- Settings and roles
---------------------------------------------------------------------------
local version = 0 -- bumped when anything an upgrade depends on changes

function ns.UpgradesChanged()
    version = version + 1
end

function ns.UpgradesOn() return not ns.db.upgradesOff end

function ns.SetUpgrades(on)
    ns.db.upgradesOff = not on or nil
    ns.UpgradesChanged()
end

-- The role a character's upgrades are judged by: their own choice, their talents', or
-- their class's default (nil for a class we don't know).
function ns.RoleOf(c)
    local cls = CLASSES[c.class]
    if not cls then return nil end
    if c.role and WEIGHTS[c.role] then
        for _, r in ipairs(cls.choices) do if r == c.role then return r end end
    end
    return c.spec and cls.tabs[c.spec] or cls.default
end

-- The role talents (or the class default) give, ignoring the player's choice.
function ns.AutoRole(c)
    local cls = CLASSES[c.class]
    return cls and (c.spec and cls.tabs[c.spec] or cls.default)
end

-- The roles a character can be given (nil if there's no choice to make).
function ns.RoleChoices(c)
    local cls = CLASSES[c.class]
    return cls and #cls.choices > 1 and cls.choices or nil
end

function ns.RoleName(role) return ROLE_NAMES[role] or "?" end
function ns.RoleWord(role) return ROLE_WORDS[role] end

-- Sets (or with nil clears) a character's role; returns false for a role their class
-- doesn't have.
function ns.SetRole(key, role)
    local c = ns.db.chars[key]
    if not c then return false end
    if role then
        local ok = false
        for _, r in ipairs(ns.RoleChoices(c) or {}) do if r == role then ok = true end end
        if not ok then return false end
    end
    c.role = role
    ns.UpgradesChanged()
    return true
end

-- A role from a /af role word (melee, ranged, caster, healer, tank, feral) for a class.
function ns.RoleFromWord(c, word)
    for _, r in ipairs(ns.RoleChoices(c) or {}) do
        if ROLE_WORDS[r] == word then return r end
    end
end

---------------------------------------------------------------------------
-- Scores
---------------------------------------------------------------------------
local scores, scoreCount = {}, 0 -- [role][link] = score
local waiting = false            -- some item data was asked for and hasn't come yet

local function Plain(v)
    if v ~= nil and not issecretvalue(v) then return v end
end

-- Asks the game for an item it hasn't loaded; upgrades are worked out again when it comes.
local function Request(id)
    waiting = true
    if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
end

local function Loaded(id)
    if not C_Item.IsItemDataCachedByID or C_Item.IsItemDataCachedByID(id) then return true end
    Request(id)
    return false
end

-- An item link's score for a role, or nil if the item isn't loaded yet.
function ns.ItemScore(link, role)
    local byRole = scores[role]
    if not byRole then
        byRole = {}
        scores[role] = byRole
    end
    local score = byRole[link]
    if score then return score end
    local id, _, _, loc = GetItemInfoInstant(link)
    if not id or not Loaded(id) then return nil end
    local stats = GetItemStats and GetItemStats(link)
    if type(stats) ~= "table" then return nil end
    local w = WEIGHTS[role]
    local dps = RANGED[loc] and "rdps" or "dps"
    score = 0
    for name, value in pairs(stats) do
        local key = STATS[name]
        if key == "dps" then key = dps end
        local weight = key and w[key]
        if weight and type(value) == "number" and not issecretvalue(value) then score = score + value * weight end
    end
    if scoreCount >= MAX_SCORES then
        for _, t in pairs(scores) do wipe(t) end
        scoreCount = 0
    end
    byRole[link] = score
    scoreCount = scoreCount + 1
    return score
end

---------------------------------------------------------------------------
-- Who can use an item
---------------------------------------------------------------------------
-- "Requires %s (%d)" and "Classes: %s" as patterns, in the client's language.
local function Pattern(fmt)
    return "^" .. fmt:gsub("[%%%(%)%.%-%+%[%]%^%$%?%*]", "%%%0"):gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)") .. "$"
end
local REQUIRES = Pattern(ITEM_MIN_SKILL or "Requires %s (%d)")
local CLASSES_LINE = Pattern(ITEM_CLASSES_ALLOWED or "Classes: %s")

-- What a hovered item is: equip location, item class and subclass, required level, bind
-- type, and from its tooltip lines any "Classes:" list and profession requirements. For a
-- recipe the lines are the crafted item's then the recipe's, whose own "Requires" is last.
local function Describe(link, data, recipe)
    local id, _, _, loc, _, class, sub = GetItemInfoInstant(link)
    if not (id and SLOTS[loc]) then return false end
    local name, _, _, _, minLevel, _, _, _, _, _, _, _, _, bind = GetItemInfo(link)
    if not name then
        Request(id)
        return nil
    end
    local info = { id = id, loc = loc, class = class, sub = sub, level = Plain(minLevel) or 1, bind = Plain(bind) }
    local lines = data and data.lines
    if type(lines) == "table" then
        local requires
        for _, line in ipairs(lines) do
            local text = Plain(line.leftText)
            if type(text) == "string" then
                local prof, skill = text:match(REQUIRES)
                if prof then
                    requires = requires or {}
                    requires[#requires + 1] = { prof, tonumber(skill) }
                end
                local classes = text:match(CLASSES_LINE)
                if classes then info.classes = classes end
            end
        end
        if requires and recipe then requires[#requires] = nil end
        if requires and requires[1] then info.requires = requires end
    end
    return info
end

-- Whether a class name is in a "Classes:" list (as the client writes class names).
local function ClassAllowed(list, class)
    for _, names in ipairs({ LOCALIZED_CLASS_NAMES_MALE, LOCALIZED_CLASS_NAMES_FEMALE }) do
        local name = type(names) == "table" and names[class]
        if name and list:find(name, 1, true) then return true end
    end
    return type(LOCALIZED_CLASS_NAMES_MALE) ~= "table" -- can't tell: let it through
end

-- The level a class can use the item from, or nil if it never can.
local function UsableFrom(info, cls)
    if info.class == ARMOR_CLASS then
        if info.sub == 0 then return 1 end -- rings, necks, trinkets, held in off hand
        return cls.armor[info.sub]
    elseif info.class == WEAPON_CLASS then
        if not cls.weapons[info.sub] then return nil end
        if info.loc == "INVTYPE_WEAPONOFFHAND" then return cls.dualWield end
        return 1
    end
end

-- The score of what's worn (0 for nothing), or nil if it isn't loaded yet.
local function WornScore(link, role)
    if not link then return 0 end
    return ns.ItemScore(link, role)
end

-- The equip location of what's worn in a slot.
local function WornLoc(link)
    if not link then return nil end
    local _, _, _, loc = GetItemInfoInstant(link)
    return loc
end

-- For one character: the gain (% or NEW: nothing worn there, or nothing that scores),
-- whether the slot is empty, and the level they can wear it from if that's above theirs;
-- nil if it's no upgrade for them, false if some of their gear isn't loaded yet.
local function Compare(c, info, link)
    local cls = CLASSES[c.class]
    local gear, level = c.gear, c.level
    if not (cls and gear and level) then return nil end
    local from = UsableFrom(info, cls)
    if not from then return nil end
    local need = max(info.level, from)
    if need > level + LEVEL_AHEAD then return nil end
    if info.classes and not ClassAllowed(info.classes, c.class) then return nil end
    for _, r in ipairs(info.requires or {}) do
        local skill = c.profs and c.profs[r[1]]
        if not (skill and skill >= r[2]) then return nil end
    end
    local role = ns.RoleOf(c)
    local new = role and ns.ItemScore(link, role)
    if new == nil then return false end
    if new <= 0 then return nil end
    local loc, slots = info.loc, SLOTS[info.loc]
    for _, slot in ipairs(slots) do
        local worn = gear[slot]
        if worn and GetItemInfoInstant(worn) == info.id then return nil end -- already wearing one
    end
    local mainLoc = WornLoc(gear[16])
    local best, empty
    for _, slot in ipairs(slots) do
        local ok = true
        if slot == 17 and loc == "INVTYPE_WEAPON" then
            -- A one-hander in the off hand: only for dual wielders not using a shield.
            ok = cls.dualWield and level >= cls.dualWield and not OFF_HAND_ITEMS[WornLoc(gear[17])]
        end
        if (slot == 16 or slot == 17) and loc ~= "INVTYPE_2HWEAPON" and mainLoc == "INVTYPE_2HWEAPON" then
            ok = false -- one hand against a two-hander isn't a fair comparison
        end
        if ok then
            local worn
            if loc == "INVTYPE_2HWEAPON" then
                local a, b = WornScore(gear[16], role), WornScore(gear[17], role)
                if a == nil or b == nil then return false end
                worn = a + b
            else
                worn = WornScore(gear[slot], role)
                if worn == nil then return false end
            end
            local gain = worn > 0 and (new - worn) * 100 / worn or NEW
            if not best or gain > best then
                best, empty = gain, not gear[slot]
            end
        end
    end
    if not best or best < MIN_GAIN then return nil end
    return best, empty, need > level and need or nil
end

---------------------------------------------------------------------------
-- Tooltip lines
---------------------------------------------------------------------------
-- The last item's rows, in reused arrays: character key, gain, right-hand text.
local rowKey, rowGain, rowText = {}, {}, {}
local rows = 0
local lastLink, lastId, lastOnly, lastVer, lastCraft, lastLevel, lastHeader

local function Before(i, j)
    local me = ns.charKey
    if (rowKey[i] == me) ~= (rowKey[j] == me) then return rowKey[i] == me end
    if rowGain[i] ~= rowGain[j] then return rowGain[i] > rowGain[j] end
    return rowKey[i] < rowKey[j]
end

local function SlotName(loc)
    local name = _G[loc]
    return type(name) == "string" and name or ""
end

local function Build(info, link, onlyYou, recipeID, tt, data)
    rows = 0
    if not info then return end
    for key, c in pairs(ns.db.chars) do
        local ok = not onlyYou or key == ns.charKey
        if ok and recipeID then ok = ns.RecipeOpenTo(c, tt, recipeID, data) end
        if ok then
            local gain, empty, at = Compare(c, info, link)
            if gain then
                rows = rows + 1
                rowKey[rows], rowGain[rows] = key, gain
                local text = SlotName(info.loc) .. " · "
                    .. (gain ~= NEW and ("+" .. floor(gain + 0.5) .. "%") or empty and L["empty slot"] or L["big upgrade"])
                if at then
                    text = GREY .. text .. " · " .. L["at level %d"]:format(at) .. "|r"
                else
                    text = GREEN .. text .. "|r"
                end
                rowText[rows] = text
            end
        end
    end
    -- Insertion sort: you first, then by gain.
    for i = 2, rows do
        local k, g, t = rowKey[i], rowGain[i], rowText[i]
        rowKey[0], rowGain[0] = k, g
        local j = i - 1
        while j > 0 and Before(0, j) do
            rowKey[j + 1], rowGain[j + 1], rowText[j + 1] = rowKey[j], rowGain[j], rowText[j]
            j = j - 1
        end
        rowKey[j + 1], rowGain[j + 1], rowText[j + 1] = k, g, t
    end
    if rows > MAX_ROWS then rows = MAX_ROWS end
end

-- Whether the hovered item says it's soulbound (the game's own line).
local function Soulbound(data)
    local lines = data and data.lines
    if type(lines) ~= "table" or not ITEM_SOULBOUND then return false end
    for i = 1, #lines do
        if Plain(lines[i].leftText) == ITEM_SOULBOUND then return true end
    end
    return false
end

function ns.AddUpgradeLines(tt, id, data)
    if not ns.UpgradesOn() then return end
    local _, _, _, _, _, class = GetItemInfoInstant(id)
    local recipe = class == RECIPE_CLASS
    if not (recipe or class == WEAPON_CLASS or class == ARMOR_CLASS) then return end
    local link = data and data.hyperlink
    if issecretvalue(link) then return end
    if recipe then
        -- A recipe's tooltip data links the item it makes (checked in game 2026-10-05).
        if type(link) ~= "string" or GetItemInfoInstant(link) == id then return end
    elseif type(link) ~= "string" then
        local _, l = tt:GetItem()
        link = Plain(l)
        if type(link) ~= "string" then return end
    end
    local onlyYou = not recipe and Soulbound(data)
    local me = ns.char
    if link ~= lastLink or id ~= lastId or onlyYou ~= lastOnly or version ~= lastVer
        or ns.craftVersion ~= lastCraft or me.level ~= lastLevel then
        lastLink, lastId, lastOnly, lastVer, lastCraft, lastLevel = link, id, onlyYou, version, ns.craftVersion, me.level
        local info = Describe(link, data, recipe)
        local recipeID
        if info then
            if info.bind ~= BIND_ON_EQUIP then
                if recipe then recipeID = id else onlyYou = true end
            end
            lastHeader = recipe and L["Makes an upgrade for"] or L["Upgrade for"]
        end
        Build(info, link, onlyYou, recipeID, tt, data)
        if info == nil then lastLink = nil end -- not loaded yet: try again next time
    end
    if rows == 0 then return end
    tt:AddLine(" ")
    tt:AddLine(lastHeader, 1, 0.82, 0)
    local chars = ns.db.chars
    for i = 1, rows do
        local key = rowKey[i]
        tt:AddDoubleLine(ns.ColoredName(key, chars[key]), rowText[i], 1, 1, 1, 1, 1, 1)
    end
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------
-- Item data the game sends back after a request: if we were waiting, work upgrades out
-- again. A while after login, the gear every character wore last is asked for, so their
-- scores are ready by the time items are hovered.
local function ItemArrived()
    if waiting then
        waiting = false
        ns.UpgradesChanged()
    end
end

local function Prewarm()
    if not C_Item.IsItemDataCachedByID then return end
    for _, c in pairs(ns.db.chars) do
        for _, link in pairs(c.gear or {}) do
            local id = type(link) == "string" and GetItemInfoInstant(link)
            if id and not C_Item.IsItemDataCachedByID(id) then Request(id) end
        end
    end
end

function ns.StartUpgrades()
    ns.On("GET_ITEM_INFO_RECEIVED", ItemArrived)
    if C_Timer and C_Timer.After then C_Timer.After(10, Prewarm) end
end
