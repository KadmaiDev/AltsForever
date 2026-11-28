-- Alts Forever upgrades: on an item you could give to one of your characters (binds when
-- equipped, not yet bound), or a recipe that makes one, which of your characters it would
-- be an upgrade for, in which slot and by about how much. An item that's yours alone (bind
-- on pickup or soulbound) shows your own row only; a recipe whose item binds on pickup,
-- only the characters who know the recipe or can learn it. A profession trainer's recipe
-- (its tooltip is the spell's, checked in game 2026-10-15) is judged on the item it makes,
-- like a recipe item; one that binds on pickup shows only you, the one learning it.
--
-- An item's score is its stats (C_Item.GetItemStats) times what each stat is worth to the
-- character's role. It's an upgrade when it beats what they wear in that slot (their gear
-- as last recorded); rings and trinkets against the weaker of the two, a two-hander
-- against main and off hand together. The role is the player's choice for that character,
-- else their talents' (Talents.lua), else their class's levelling default.
--
-- Scores are cached per item link and role (numbers only); the rows for the last item are
-- kept, so the tooltip refreshing while you hover rebuilds nothing.
local ADDON, ns = ...
if ns.disabled then return end -- another copy of Alts Forever is running (Core.lua)
local L = ns.L

local pairs, ipairs, next, type, wipe, floor, max = pairs, ipairs, next, type, wipe, math.floor, math.max
local issecretvalue = issecretvalue or function() return false end
local GetItemInfoInstant, GetItemInfo, GetItemStats = C_Item.GetItemInfoInstant, C_Item.GetItemInfo, C_Item.GetItemStats

local RECIPE_CLASS, WEAPON_CLASS, ARMOR_CLASS = 9, 2, 4
local BIND_ON_EQUIP = 2
local MAX_ROWS = 5
local LEVEL_AHEAD = 5   -- characters up to this many levels short show as "at level N"
local MAX_SCORES = 2000 -- cached scores before the cache starts again
local NEW = math.huge   -- the gain when nothing the character wears scores yet
local GREEN, GREY = "|cff20ff20", "|cff9d9d9d"

-- Stats as GetItemStats names them (checked in game 2026-10-05 for strength, spirit, spell
-- power, armour and dps; the rest follow retail's names).
local STATS = {
    ITEM_MOD_STRENGTH_SHORT = "str", ITEM_MOD_AGILITY_SHORT = "agi", ITEM_MOD_STAMINA_SHORT = "sta",
    ITEM_MOD_INTELLECT_SHORT = "int", ITEM_MOD_SPIRIT_SHORT = "spi",
    ITEM_MOD_ATTACK_POWER_SHORT = "ap", ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "rap",
    ITEM_MOD_SPELL_POWER_SHORT = "sp", ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "sp", -- the second unchecked;
    -- "damage and healing ... by up to 11" is SPELL_POWER 11 alone, no healing entry (Crusader's
    -- Silvered Chain Helm, owner's probe 2026-11-19)
    ITEM_MOD_SPELL_HEALING_DONE_SHORT = "heal",
    ITEM_MOD_POWER_REGEN0_SHORT = "mp5", ITEM_MOD_MANA_REGENERATION_SHORT = "mp5",
    ITEM_MOD_CRIT_RATING_SHORT = "crit", ITEM_MOD_CRIT_MELEE_RATING_SHORT = "crit",
    ITEM_MOD_CRIT_RANGED_RATING_SHORT = "crit", ITEM_MOD_HIT_RATING_SHORT = "hit",
    ITEM_MOD_HIT_MELEE_RATING_SHORT = "hit", ITEM_MOD_HIT_RANGED_RATING_SHORT = "hit",
    ITEM_MOD_CRIT_SPELL_RATING_SHORT = "spellcrit", ITEM_MOD_HIT_SPELL_RATING_SHORT = "spellhit",
    ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "def", ITEM_MOD_DODGE_RATING_SHORT = "dodge",
    ITEM_MOD_PARRY_RATING_SHORT = "parry", ITEM_MOD_BLOCK_RATING_SHORT = "block",
    ITEM_MOD_BLOCK_VALUE_SHORT = "blockvalue",
    -- Names listed in game by the owner, 2026-11-19 (every ITEM_MOD_*_SHORT global): haste,
    -- expertise and one spell damage per school ("+17 Arcane Damage" is
    -- ITEM_MOD_ARCANE_DAMAGE_DONE_SHORT 17, Arcane Remnant Leggings).
    ITEM_MOD_HASTE_RATING_SHORT = "haste", ITEM_MOD_EXPERTISE_RATING_SHORT = "expertise",
    ITEM_MOD_ARCANE_DAMAGE_DONE_SHORT = "arcane", ITEM_MOD_FIRE_DAMAGE_DONE_SHORT = "fire",
    ITEM_MOD_FROST_DAMAGE_DONE_SHORT = "frost", ITEM_MOD_NATURE_DAMAGE_DONE_SHORT = "nature",
    ITEM_MOD_SHADOW_DAMAGE_DONE_SHORT = "shadow", ITEM_MOD_HOLY_DAMAGE_DONE_SHORT = "holy",
    RESISTANCE0_NAME = "armor", ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "dps",
}

-- Crit and hit come from GetItemStats as ratings, not percentages: Mugger's Belt says
-- "critical strike by 1.0%" and reports ITEM_MOD_CRIT_RATING_SHORT = 14 (checked in game
-- 2026-11-11, seen from a low-level character, so the tooltip's figure isn't scaled to the
-- viewer). Until then 14 rating was scored as 14%. Hit is 10 per 1%: Observer's Shield, "chance
-- to hit by 1.0%", ITEM_MOD_HIT_RATING_SHORT = 10 (same day). Block is 5 per 1%: Boar
-- Signet, "chance to Block attacks with a shield by 1.0%", ITEM_MOD_BLOCK_RATING_SHORT = 5
-- (owner's probe 2026-11-19; read as 5% until then, so it showed as a big upgrade for
-- Vespera). Dodge and parry are unchecked and left as they were. A shield's own "38 Block"
-- isn't in GetItemStats at all; Block Value is ITEM_MOD_BLOCK_VALUE_SHORT (checked the same
-- day on the Twilight Lord Girdle). Defense is skill points, 1 to 1 ("Increased Defense
-- +9" = ITEM_MOD_DEFENSE_SKILL_RATING_SHORT 9, Unbridled Leggings, same day).
-- The three measured (crit 14, hit 10, block 5) are exactly the Burning Crusade rating table
-- at level 60, so haste (10 per 1%) is taken from the same table (inferred, not yet seen on
-- an item). Expertise, dodge and parry were predicted from it and then checked (owner's
-- probes, the same day): Defias Enforcer's Mask, "Dodged or Parried by 1.0%" =
-- ITEM_MOD_EXPERTISE_RATING_SHORT 10; Boots of Avoidance, "dodge an attack by 1.5%" =
-- ITEM_MOD_DODGE_RATING_SHORT 18; Krol'dok Warplate Gauntlets, "Parry an attack by 1.0%" =
-- ITEM_MOD_PARRY_RATING_SHORT 15. Until 2026-11-19 dodge and parry were
-- read as whole percents, twelve and fifteen times too much.
local PER_PERCENT = { crit = 14, spellcrit = 14, hit = 10, spellhit = 10, block = 5,
    dodge = 12, parry = 15, haste = 10, expertise = 10 }

-- What a point of each stat is worth, per role, for levelling (crit and hit per 1%).
-- Reviewed 2026-11-11 against Forever's reworked trees (talentsforever.com's data and
-- Blizzard's class posts, all from the beta; none of it checked in game): crit and hit are
-- one stat for melee, ranged and spells, so casters and healers weigh the plain ones as
-- their spell ones; healing power counts as spell damage at a third; druid forms hit with
-- the weapon's dps; Enhancement gets attack power and spell damage from Intellect. A weapon's dps counts as `dps`, or `rdps` in the ranged slot. The hunter
-- weights are the ones Upgrade Trail checked against real items.
-- Moved partway towards Pawn 2.14's Forever weights (curated by HawsJon) on 2026-11-18,
-- after a player's priest was offered +2 Stamina over +1 Spirit: casters and healers value
-- Spirit and Intellect more and Stamina less, rogues Strength more, tanks armour less and
-- their weapon more, protection paladins spell damage less (Pawn: 0.44 of Stamina) and
-- Intellect and crit a little, Survival hunters their melee weapon more. Hunters' other
-- weights are left as Upgrade Trail checked them; Pawn's are for level 60, ours for levelling.
-- These are the shipped weights; players can change any of them per role (the Upgrade
-- weights window, db.weights; owner, 2026-11-19), so the ones in use are WEIGHTS, below.
local BASE = {
    -- Haste per 1% as about two thirds of crit for physical roles and nine tenths for spells,
    -- expertise about four fifths of hit for melee, as in Pawn's Forever weights.
    hunter = { agi = 2.4, ap = 1, rap = 1, sta = 0.4, int = 0.3, spi = 0.05, crit = 22, hit = 16,
        haste = 13, armor = 0.02, dps = 0.5, rdps = 14 },
    rogue = { agi = 2, str = 1.4, ap = 1, sta = 0.4, crit = 20, hit = 18, haste = 14, expertise = 14,
        armor = 0.02, dps = 10, rdps = 1 },
    warrior = { str = 2, agi = 1.4, ap = 1, sta = 0.5, crit = 20, hit = 18, haste = 13, expertise = 14,
        armor = 0.02, dps = 12, rdps = 1 },
    -- Retribution's Champion of the Light turns Intellect into spell damage for its Holy hits.
    paladin = { str = 2, agi = 1, ap = 1, sta = 0.5, int = 0.6, sp = 0.4, crit = 18, hit = 16, haste = 6,
        expertise = 12, armor = 0.02, dps = 12 },
    enhancement = { str = 2, agi = 1.2, ap = 1, sta = 0.5, int = 1, sp = 0.3, crit = 18, hit = 16, haste = 11,
        expertise = 12, armor = 0.02, dps = 12 },
    feral = { str = 2, agi = 1.6, ap = 1, sta = 0.8, crit = 18, hit = 16, haste = 12, expertise = 12,
        armor = 0.05, def = 0.5, dodge = 6, dps = 10 },
    tank = { sta = 1.5, str = 1, agi = 1, armor = 0.05, def = 1.5, dodge = 12, parry = 10, block = 6,
        blockvalue = 0.5, ap = 0.3, hit = 8, haste = 2, expertise = 6, dps = 6, rdps = 0.5 },
    caster = { sp = 1, heal = 0.33, int = 0.55, spi = 0.6, sta = 0.2, mp5 = 1.5, spellcrit = 10, spellhit = 12,
        crit = 10, hit = 12, haste = 9, rdps = 3 },
    healer = { heal = 1, sp = 0.9, int = 1, spi = 0.9, sta = 0.15, mp5 = 2, spellcrit = 8, crit = 8, haste = 7,
        rdps = 1 },
}
-- A protection paladin tanks as a tank, but most of their threat is holy damage (seals,
-- Consecration, Retribution Aura), so spell damage counts (two thirds of Stamina; Pawn has
-- 0.44), and Intellect, crit and MP5 a little, as Pawn does.
-- Their own weights first (haste), the tank's for the rest (peer review, 2026-11-19): see PARENT.
BASE.paladintank = { sp = 1, heal = 0.3, int = 0.4, crit = 4, mp5 = 0.5, haste = 6 }
-- Beast Mastery and Marksmanship hunters carry melee weapons for their stats, so a point
-- of melee dps is worth little (0.5: enough to split two equal weapons, not to make an
-- upgrade of one). Survival is the melee tree (owner, 2026-11-11), though Blizzard describes
-- it as supporting melee builds beside the bow, with an off-hand damage talent: its melee
-- weapons count for five times what every hunter's did (Pawn: as much as its bow), and its bow for less than the
-- ranged trees', without leaving it behind. Third tab, as talentsforever.com lists them.
BASE.survival = { dps = 10, rdps = 8, expertise = 6 }
-- Marksmanship turns Intellect into attack power (Careful Aim, up to 100%).
BASE.marksman = { int = 1 }
-- A role that takes every stat it doesn't set itself from another, as it is in use: a change
-- to the tank's Stamina counts for protection paladins too, unless theirs was changed.
local PARENT = { paladintank = "tank", survival = "hunter", marksman = "hunter" }

-- The weights in use, by role: BASE with the player's changes (db.weights[role][stat]),
-- filled from the PARENT. Spell crit and hit follow crit and hit wherever a role has them
-- (casters and healers: one stat on Forever). ScoreRole adds keys "role:CLASS:spec" here,
-- made again after a change. Rebuilt only at login and when a weight changes.
local WEIGHTS = {}
local MAX_WEIGHT = 1000
local SPELL_ROLES = { caster = true, healer = true }

-- A changed weight that can be used: a number from 0 to MAX_WEIGHT (not NaN).
local function Usable(v)
    return type(v) == "number" and v >= 0 and v <= MAX_WEIGHT
end

local function BuildWeights()
    for key in pairs(WEIGHTS) do WEIGHTS[key] = nil end
    local edits = ns.db and ns.db.weights
    local function Make(role)
        if WEIGHTS[role] then return WEIGHTS[role] end
        local w = {}
        for stat, weight in pairs(BASE[role]) do w[stat] = weight end
        local mine = edits and edits[role]
        if type(mine) == "table" then
            for stat, weight in pairs(mine) do
                if type(stat) == "string" and Usable(weight) then w[stat] = weight end
            end
        end
        local parent = PARENT[role] and Make(PARENT[role])
        if parent then
            for stat, weight in pairs(parent) do
                if w[stat] == nil then w[stat] = weight end
            end
        end
        -- Casters and healers: spell crit and hit are crit and hit, even where the shipped
        -- weights had neither (a healer given a Hit weight values spell hit rating too).
        local spells = SPELL_ROLES[role]
        if w.spellcrit ~= nil or (spells and w.crit ~= nil) then w.spellcrit = w.crit or 0 end
        if w.spellhit ~= nil or (spells and w.hit ~= nil) then w.spellhit = w.hit or 0 end
        WEIGHTS[role] = w
        return w
    end
    for role in pairs(BASE) do Make(role) end
end
BuildWeights()

-- The word for each role, in menus and in /af role.
local ROLE_NAMES = {
    hunter = L["Ranged"], marksman = L["Marksman"], survival = L["Melee"], rogue = L["Melee"], warrior = L["Melee"], paladin = L["Melee"],
    enhancement = L["Melee"], feral = L["Feral"], tank = L["Tank"], paladintank = L["Tank"],
    caster = L["Caster"], healer = L["Healer"],
}
local ROLE_WORDS = {
    hunter = "ranged", marksman = "marksman", survival = "melee", rogue = "melee", warrior = "melee", paladin = "melee", enhancement = "melee",
    feral = "feral", tank = "tank", paladintank = "tank", caster = "caster", healer = "healer",
}

-- Per class (Classic's rules): the role of each talent tab, the levelling default, armour
-- by subclass (the level it can be worn from: mail and plate come at 40), weapon
-- subclasses it can learn, and the level dual wield comes at.
local CLASSES = {
    WARRIOR = { tabs = { "warrior", "warrior", "tank" }, default = "warrior", dualWield = 20,
        armor = { [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1 },
        weapons = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 } },
    PALADIN = { tabs = { "healer", "paladintank", "paladin" }, default = "paladin",
        aliases = { tank = "paladintank" }, -- a paladin's role saved before they had their own
        armor = { [1] = 1, [2] = 1, [3] = 1, [4] = 40, [6] = 1, [7] = 1 },
        weapons = { 0, 1, 4, 5, 6, 7, 8 } },
    HUNTER = { tabs = { "hunter", "marksman", "survival" }, default = "hunter", dualWield = 20,
        armor = { [1] = 1, [2] = 1, [3] = 40 },
        weapons = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 } },
    ROGUE = { tabs = { "rogue", "rogue", "rogue" }, default = "rogue", dualWield = 10,
        armor = { [1] = 1, [2] = 1 },
        weapons = { 0, 2, 3, 4, 7, 13, 15, 16, 18 } }, -- one-handed axes too on Forever
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

-- Spell damage of one school, as a share of plain spell damage, by class and talent tree
-- ([0] = under 10 talent points: about the trees' average; also a healing or feral tree's
-- character the player set to a damage or tank role, peer review 2026-11-19). From Pawn 2.14's Forever
-- weights (HawsJon), 2026-11-19. Applied as the role's spell damage weight times the share,
-- so a role that doesn't value spell damage gets nothing, and healers never do (it doesn't
-- heal). Priests under 10 points smite as much as they shadow bolt.
local SCHOOLS = {
    MAGE = { [0] = { arcane = 0.4, fire = 0.4, frost = 0.45 },
        { arcane = 0.95, fire = 0.1, frost = 0.1 }, { fire = 0.95, frost = 0.3, arcane = 0.15 },
        { frost = 0.95, fire = 0.1, arcane = 0.15 } },
    WARLOCK = { [0] = { shadow = 0.85, fire = 0.6 },
        { shadow = 0.9, fire = 0.35 }, { shadow = 0.8, fire = 0.8 }, { shadow = 0.8, fire = 0.6 } },
    PRIEST = { [0] = { shadow = 0.7, holy = 0.3 }, [3] = { shadow = 1 } },
    DRUID = { [0] = { arcane = 0.6, nature = 0.45 }, { arcane = 0.64, nature = 0.43 } },
    SHAMAN = { [0] = { nature = 1 }, { nature = 1 }, { nature = 1 } },
    PALADIN = { [0] = { holy = 1 }, [2] = { holy = 1 }, [3] = { holy = 1 } },
}

-- The weights an item is scored by for a character: their role's, plus spell damage of the
-- schools their class and tree use. Made once per role, class and tree.
local function ScoreRole(c, role)
    local trees = SCHOOLS[c.class]
    local shares = trees and role ~= "healer" and (trees[c.spec or 0] or trees[0])
    local sp = WEIGHTS[role] and WEIGHTS[role].sp
    if not (shares and sp) then return role end
    local key = role .. ":" .. c.class .. ":" .. (c.spec or 0)
    if not WEIGHTS[key] then
        local w = {}
        for stat, weight in pairs(WEIGHTS[role]) do w[stat] = weight end
        for school, share in pairs(shares) do w[school] = sp * share end
        WEIGHTS[key] = w
    end
    return key
end
ns.ScoreRole = ScoreRole

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
-- Weapon and armour skills
---------------------------------------------------------------------------
-- What each character has trained (a player's request, 2026-11-25: a mage was offered a
-- sword she can learn but hadn't). Forever has Classic's skills list (C_SkillInfo):
-- GetSkillLineInfoByID(id) gives { name, rank, maxRank } for a trained skill and nil for one
-- that isn't (probed on a level 6 mage 2026-11-25: Staves 136 20/30, Wands 228 1/30,
-- Unarmed 162 1/30, Defense 95 21/30, Cloth 415 1/1; Swords 43, Two-Handed Swords 55 and
-- Daggers 173 nil). The other IDs are Classic's, assumed the same.
-- c.skills = { [skillID] = rank * 1000 + maxRank }, nil until read.
local WEAPON_SKILL = { [0] = 44, [1] = 172, [2] = 45, [3] = 46, [4] = 54, [5] = 160, [6] = 229,
    [7] = 43, [8] = 55, [10] = 136, [13] = 473, [15] = 173, [16] = 176, [18] = 226, [19] = 228 }
local ARMOR_SKILL = { [1] = 415, [2] = 414, [3] = 413, [4] = 293, [6] = 433 }
local DEFENSE_SKILL, UNARMED_SKILL = 95, 162
-- The order they're listed in (weapon subclass order, then Unarmed and Defense).
local WEAPON_ORDER = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18, 19 }
local ARMOR_ORDER = { 1, 2, 3, 4, 6 }
local readSkills = {} -- reused
local skillsSoon = false -- a read is queued (StartUpgrades)

local function ReadSkill(id)
    local s = C_SkillInfo.GetSkillLineInfoByID(id)
    if type(s) ~= "table" then return end
    local rank, most = s.rank, s.maxRank
    if issecretvalue(rank) or issecretvalue(most) or type(rank) ~= "number" or type(most) ~= "number" then return end
    readSkills[id] = rank * 1000 + most
end

-- Reads the character you're on. Every character has Defense, so without it the list isn't
-- ready and nothing changes. Returns true when which skills are trained changed (ranks
-- alone don't change any upgrade).
function ns.ScanCombatSkills(c)
    if not (C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID and c) then return false end
    wipe(readSkills)
    ReadSkill(DEFENSE_SKILL)
    if not readSkills[DEFENSE_SKILL] then return false end
    ReadSkill(UNARMED_SKILL)
    for _, id in pairs(WEAPON_SKILL) do ReadSkill(id) end
    for _, id in pairs(ARMOR_SKILL) do ReadSkill(id) end
    local skills = c.skills
    local changed = not skills
    if skills then
        for id in pairs(skills) do if not readSkills[id] then changed = true end end
        for id in pairs(readSkills) do if not skills[id] then changed = true end end
        wipe(skills)
    else
        skills = {}
        c.skills = skills
    end
    for id, v in pairs(readSkills) do skills[id] = v end
    return changed
end

-- Whether a character hasn't trained the skill an item needs. False when their skills
-- aren't known (not logged in since this was added): the class table alone decides then.
local function Missing(c, id)
    local skills = c.skills
    return id ~= nil and skills ~= nil and skills[DEFENSE_SKILL] ~= nil and not skills[id]
end

local function Untrained(c, info)
    if info.class == WEAPON_CLASS then return Missing(c, WEAPON_SKILL[info.sub]) end
    if info.class == ARMOR_CLASS then return Missing(c, ARMOR_SKILL[info.sub]) end
    return false
end

local function SubName(class, sub, fallback)
    local name = C_Item.GetItemSubClassInfo and C_Item.GetItemSubClassInfo(class, sub)
    return type(name) == "string" and name ~= "" and name or fallback
end

-- Defense and Unarmed have no item category: their names come from the skills list of the
-- character you're on (every character has both), remembered for the session.
local skillNames = {}
local function SkillName(id, fallback)
    if not skillNames[id] and C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID then
        local s = C_SkillInfo.GetSkillLineInfoByID(id)
        local name = type(s) == "table" and s.name
        if type(name) == "string" and not issecretvalue(name) and name ~= "" then skillNames[id] = name end
    end
    return skillNames[id] or fallback
end

-- A character's weapon skills and armour, for the character window's Skills tab: two lists
-- of { name, rank, max, weapon, untrained, at }, each sorted by name as the game's own
-- Skills tab is, trained first. Weapons hold Defense and Unarmed too, then the weapons
-- their class can learn but hasn't (untrained, no rank); `weapon` marks a real weapon
-- skill (Defense and Unarmed aren't). Armour: what's trained (1/1), then what the class
-- wears but hasn't trained, with `at` the level it comes at if that's above theirs.
-- nil when their skills haven't been read. Fresh tables: only for a window being filled.
local function ByName(a, b)
    if (a.untrained or false) ~= (b.untrained or false) then return not a.untrained end
    return a.name < b.name
end

function ns.CombatSkills(c)
    local skills = c and c.skills
    if not (skills and skills[DEFENSE_SKILL]) then return nil end
    local cls = CLASSES[c.class]
    local weapons, armour = {}, {}
    local function Add(list, id, name, weapon)
        if not name then return end
        local v = skills[id]
        if v then
            list[#list + 1] = { name = name, rank = floor(v / 1000), max = v % 1000, weapon = weapon }
        end
        return v ~= nil
    end
    for _, sub in ipairs(WEAPON_ORDER) do
        local name = SubName(WEAPON_CLASS, sub)
        if not Add(weapons, WEAPON_SKILL[sub], name, true) and name and cls and cls.weapons[sub] then
            weapons[#weapons + 1] = { name = name, weapon = true, untrained = true }
        end
    end
    Add(weapons, UNARMED_SKILL, SkillName(UNARMED_SKILL, L["Unarmed"]))
    Add(weapons, DEFENSE_SKILL, SkillName(DEFENSE_SKILL, L["Defense"]))
    for _, sub in ipairs(ARMOR_ORDER) do
        local name = SubName(ARMOR_CLASS, sub)
        local from = cls and cls.armor[sub]
        if not Add(armour, ARMOR_SKILL[sub], name) and name and from then
            armour[#armour + 1] = { name = name, untrained = true, at = c.level and from > c.level and from or nil }
        end
    end
    table.sort(weapons, ByName)
    table.sort(armour, ByName)
    return weapons, armour
end

---------------------------------------------------------------------------
-- Settings and roles
---------------------------------------------------------------------------
local version = 0 -- bumped when anything an upgrade depends on changes

function ns.UpgradesChanged()
    version = version + 1
    if ns.CharacterSheetChanged then ns.CharacterSheetChanged() end
end

function ns.UpgradesOn() return not ns.db.upgradesOff end
function ns.UpgradesVersion() return version end

function ns.SetUpgrades(on)
    ns.db.upgradesOff = not on or nil
    ns.UpgradesChanged()
end

-- The role a character's upgrades are judged by: their own choice, their talents', or
-- their class's default (nil for a class we don't know).
function ns.RoleOf(c)
    local cls = CLASSES[c.class]
    if not cls then return nil end
    local chosen = ns.ChosenRole(c)
    if chosen and WEIGHTS[chosen] then
        for _, r in ipairs(cls.choices) do if r == chosen then return r end end
    end
    return c.spec and cls.tabs[c.spec] or cls.default
end

-- The role the player chose for a character (nil = automatic), under its current name.
function ns.ChosenRole(c)
    local cls = CLASSES[c.class]
    local aliases = cls and cls.aliases
    return aliases and aliases[c.role] or c.role
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
    c.changed = time() -- so a sync with another account picks it up
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
    if not issecretvalue(v) and v ~= nil then return v end
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
        if weight and type(value) == "number" and not issecretvalue(value) then
            score = score + value * weight / (PER_PERCENT[key] or 1)
        end
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
-- Changing the weights (the Upgrade weights window, Weights.lua; /af weights)
---------------------------------------------------------------------------
-- The roles and stats the window shows, in order. Spell crit and hit aren't listed (they
-- follow crit and hit), nor the spell schools (a share of spell damage, by class and tree).
local ROLE_ORDER = { "hunter", "marksman", "survival", "rogue", "warrior", "paladin", "enhancement",
    "feral", "tank", "paladintank", "caster", "healer" }
local STAT_ORDER = { "str", "agi", "sta", "int", "spi", "ap", "rap", "sp", "heal", "mp5", "crit", "hit",
    "haste", "expertise", "armor", "def", "dodge", "parry", "block", "blockvalue", "dps", "rdps" }
-- The game's own word for a stat (translated by the game), as GetItemStats names it.
local STAT_WORDS = {
    str = "ITEM_MOD_STRENGTH_SHORT", agi = "ITEM_MOD_AGILITY_SHORT", sta = "ITEM_MOD_STAMINA_SHORT",
    int = "ITEM_MOD_INTELLECT_SHORT", spi = "ITEM_MOD_SPIRIT_SHORT", ap = "ITEM_MOD_ATTACK_POWER_SHORT",
    rap = "ITEM_MOD_RANGED_ATTACK_POWER_SHORT", sp = "ITEM_MOD_SPELL_POWER_SHORT",
    heal = "ITEM_MOD_SPELL_HEALING_DONE_SHORT", mp5 = "ITEM_MOD_MANA_REGENERATION_SHORT",
    crit = "ITEM_MOD_CRIT_RATING_SHORT", hit = "ITEM_MOD_HIT_RATING_SHORT", haste = "ITEM_MOD_HASTE_RATING_SHORT",
    expertise = "ITEM_MOD_EXPERTISE_RATING_SHORT", armor = "RESISTANCE0_NAME",
    def = "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT", dodge = "ITEM_MOD_DODGE_RATING_SHORT",
    parry = "ITEM_MOD_PARRY_RATING_SHORT", block = "ITEM_MOD_BLOCK_RATING_SHORT",
    blockvalue = "ITEM_MOD_BLOCK_VALUE_SHORT",
}
local CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local weightsListeners = {}

function ns.WeightRoles() return ROLE_ORDER end
function ns.WeightStats() return STAT_ORDER end

-- "Strength", "Critical Strike (per 1%)", "Melee weapon DPS".
function ns.WeightStatLabel(stat)
    local text
    if stat == "dps" then
        text = L["Melee weapon DPS"]
    elseif stat == "rdps" then
        text = L["Ranged weapon DPS"]
    else
        text = STAT_WORDS[stat] and _G[STAT_WORDS[stat]]
        if issecretvalue(text) or type(text) ~= "string" or text == "" then text = stat end
    end
    if PER_PERCENT[stat] then text = L["%s (per 1%%)"]:format(text) end
    return text
end

-- "Melee · Rogue", "Tank · Paladin", "Caster · Priest, Shaman, Mage, Warlock, Druid": the
-- role's word and the classes that can be judged by it.
function ns.WeightRoleLabel(role)
    local names = {}
    for _, class in ipairs(CLASS_ORDER) do
        local cls = CLASSES[class]
        local uses = cls.default == role
        for _, r in ipairs(cls.choices) do if r == role then uses = true end end
        if uses then
            local name = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]
            names[#names + 1] = type(name) == "string" and name or class
        end
    end
    return ns.RoleName(role) .. " · " .. table.concat(names, ", ")
end

-- A weight in use (0 for a stat the role doesn't count).
function ns.Weight(role, stat)
    local w = WEIGHTS[role]
    return w and w[stat] or 0
end

-- What a weight goes back to on reset: the shipped one, else the parent role's in use.
function ns.DefaultWeight(role, stat)
    local base = BASE[role] and BASE[role][stat]
    if base then return base end
    return PARENT[role] and ns.Weight(PARENT[role], stat) or 0
end

-- The role whose weights this one follows for the stats it doesn't set (nil if none).
function ns.WeightParent(role) return PARENT[role] end

-- Whether the player changed this weight.
function ns.WeightChanged(role, stat)
    local edits = ns.db.weights
    return edits ~= nil and edits[role] ~= nil and edits[role][stat] ~= nil
end

-- Whether any of a role's weights were changed.
function ns.RoleWeightsChanged(role)
    local edits = ns.db.weights
    return edits ~= nil and edits[role] ~= nil
end

-- Called when the weights change (the window refreshes itself).
function ns.OnWeightsChanged(fn) weightsListeners[#weightsListeners + 1] = fn end

local function WeightsChanged()
    BuildWeights()
    for _, t in pairs(scores) do wipe(t) end
    scoreCount = 0
    ns.UpgradesChanged()
    for _, fn in ipairs(weightsListeners) do fn() end
end
ns.ApplyWeights = WeightsChanged

-- Sets one weight (nil, or the default, puts it back); false for a role or stat the window
-- doesn't offer, or a value that isn't a number from 0 to 1000.
function ns.SetWeight(role, stat, value)
    if not BASE[role] then return false end
    local known = false
    for _, s in ipairs(STAT_ORDER) do if s == stat then known = true end end
    if not known then return false end
    if value ~= nil and not Usable(value) then return false end
    local db = ns.db
    if value == nil or value == ns.DefaultWeight(role, stat) then
        local mine = db.weights and db.weights[role]
        if mine then
            mine[stat] = nil
            if not next(mine) then db.weights[role] = nil end
            if not next(db.weights) then db.weights = nil end
        end
    else
        db.weights = db.weights or {}
        db.weights[role] = db.weights[role] or {}
        db.weights[role][stat] = value
    end
    WeightsChanged()
    return true
end

-- Puts every weight of a role back.
function ns.ResetWeights(role)
    local db = ns.db
    if not (db.weights and db.weights[role]) then return end
    db.weights[role] = nil
    if not next(db.weights) then db.weights = nil end
    WeightsChanged()
end

---------------------------------------------------------------------------
-- Who can use an item
---------------------------------------------------------------------------
-- "Requires %s (%d)" and "Classes: %s" as patterns, in the client's language. Numbered
-- placeholders (German: "Benötigt %1$s (%2$d)") are read as "%s" and "%d".
local function Pattern(fmt)
    return "^" .. fmt:gsub("%%%d+%$", "%%"):gsub("[%%%(%)%.%-%+%[%]%^%$%?%*]", "%%%0"):gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)") .. "$"
end
local REQUIRES = Pattern(ITEM_MIN_SKILL or "Requires %s (%d)")
local CLASSES_LINE = Pattern(ITEM_CLASSES_ALLOWED or "Classes: %s")
-- "Unique", "Unique-Equipped", "Unique (2)": all start with the game's word for it.
local UNIQUE = type(ITEM_UNIQUE) == "string" and ITEM_UNIQUE ~= "" and ITEM_UNIQUE or "Unique"

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
    -- Taken as unique unless its lines say otherwise: then a second one is never suggested.
    info.unique = type(lines) ~= "table"
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
                if text:sub(1, #UNIQUE) == UNIQUE then info.unique = true end
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

-- For one character: the gain, as a % of the score of everything they wear (NEW if nothing
-- they wear scores yet), whether the slot is empty, the level they can wear it from if
-- that's above theirs, the slot it does best in, and true if they haven't trained its
-- weapon or armour skill; nil if it's no upgrade for them, false
-- if some of their gear isn't loaded yet. Against the whole gear score, not the item it
-- replaces: low-level gear often has only armour, which scores next to nothing, so +1
-- Agility over it read as +583% (the owner's report, 2026-10-16).
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
        local skill = c.profs and c.profs[ns.ProfKey(c, r[1])]
        if not (skill and skill >= r[2]) then return nil end
    end
    local role = ns.RoleOf(c)
    role = role and ScoreRole(c, role)
    local new = role and ns.ItemScore(link, role)
    if new == nil then return false end
    if new <= 0 then return nil end
    local loc, slots = info.loc, SLOTS[info.loc]
    -- Already wearing one with this item ID (the same, or another random suffix such as "of
    -- the Owl"): the scores decide whether it's better where it's worn (the same one gains
    -- nothing). A unique one can't be worn twice, so it's weighed only in that slot.
    local onlySlot
    if info.unique then
        for _, slot in ipairs(slots) do
            local worn = gear[slot]
            if worn and GetItemInfoInstant(worn) == info.id then onlySlot = slot end
        end
    end
    local total = 0
    for slot, worn in pairs(gear) do
        if slot ~= 4 and slot ~= 19 then -- shirt and tabard
            local score = ns.ItemScore(worn, role)
            if score == nil then return false end
            total = total + score
        end
    end
    local mainLoc = WornLoc(gear[16])
    -- Weapons only against the kind wielded now (owner, 2026-10-16): with a sword and shield
    -- (or two one-handers) the one-handers show, not two-handers against both together.
    if loc == "INVTYPE_2HWEAPON" and mainLoc and mainLoc ~= "INVTYPE_2HWEAPON" then return nil end
    local best, empty, bestSlot
    for _, slot in ipairs(slots) do
        local ok = not onlySlot or slot == onlySlot
        if slot == 17 and (loc == "INVTYPE_WEAPON" or loc == "INVTYPE_WEAPONOFFHAND") then
            -- A weapon in the off hand: only for dual wielders not using a shield.
            ok = ok and cls.dualWield and level >= cls.dualWield and not OFF_HAND_ITEMS[WornLoc(gear[17])]
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
            local gain = total > 0 and (new - worn) * 100 / total or NEW
            if not best or gain > best then
                best, empty, bestSlot = gain, not gear[slot], slot
            end
        end
    end
    -- Any real gain shows, the small ones as one arrow (a 1% cut-off hid valid boots and
    -- capes on a level 16 alt, the owner's report 2026-10-16).
    if not best or (best <= 0 and not empty) then return nil end -- anything beats an empty slot
    -- Still listed when it needs training first (the owner, 2026-11-25), greyed like a level
    -- they haven't reached; a level not reached is said instead (they can't train it yet).
    local at = need > level and need or nil
    return best, empty, at, bestSlot, not at and Untrained(c, info) or nil
end

---------------------------------------------------------------------------
-- Tooltip lines
---------------------------------------------------------------------------
-- The last item's rows, in reused arrays: character key, gain, right-hand text.
local rowKey, rowGain, rowText = {}, {}, {}
local rows = 0
local lastLink, lastId, lastKind, lastOnly, lastVer, lastCraft, lastLevel, lastHeader

local function Before(i, j)
    local me = ns.charKey
    if (rowKey[i] == me) ~= (rowKey[j] == me) then return rowKey[i] == me end
    if rowGain[i] ~= rowGain[j] then return rowGain[i] > rowGain[j] end
    return rowKey[i] < rowKey[j]
end

-- How big an upgrade is, shown as one to three green arrows rather than a % (the owner's
-- idea, 2026-10-16: a % was hard to judge): minor under 4% of the character's whole gear
-- score, decent under 10%, major from 10% (or when nothing they wear scores yet).
local DECENT, MAJOR = 4, 10

function ns.GainTier(gain)
    if gain >= MAJOR then return 3 end
    if gain >= DECENT then return 2 end
    return 1
end

-- One to three green chevrons stacked like rank stripes (media/up1-3.tga, drawn by
-- tools/make_chevrons.py; the owner's idea, 2026-10-16): the picture, and as text.
local CHEVRONS, CHEVRON_TEXT = {}, {}
for tier = 1, 3 do
    CHEVRONS[tier] = "Interface\\AddOns\\" .. ADDON .. "\\media\\up" .. tier .. ".tga"
    CHEVRON_TEXT[tier] = "|T" .. CHEVRONS[tier] .. ":16:16|t"
end

function ns.GainTexture(gain) return CHEVRONS[ns.GainTier(gain)] end
function ns.GainArrows(gain) return CHEVRON_TEXT[ns.GainTier(gain)] end

-- The arrows, and "· empty slot" when there's nothing in it.
function ns.GainLabel(gain, empty)
    local arrows = ns.GainArrows(gain)
    return empty and arrows .. " · " .. L["empty slot"] or arrows
end

local function SlotName(loc)
    local name = _G[loc]
    return type(name) == "string" and name or ""
end

local function Build(info, link, onlyYou, recipeID, tt, data)
    rows = 0
    if not info then return end
    for key, c in pairs(ns.db.chars) do
        local ok = (not onlyYou or key == ns.charKey) and not ns.TipHidden(c)
        if ok and recipeID then ok = ns.RecipeOpenTo(c, tt, recipeID, data) end
        if ok then
            local gain, empty, at, _, train = Compare(c, info, link)
            if gain then
                rows = rows + 1
                rowKey[rows], rowGain[rows] = key, gain
                local text = SlotName(info.loc) .. " · " .. ns.GainLabel(gain, empty)
                if at then
                    text = GREY .. text .. " · " .. L["at level %d"]:format(at) .. "|r"
                elseif train then
                    text = GREY .. text .. " · " .. L["needs training"] .. "|r"
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

-- The rows for an item link, and the lines. kind: "item" (the item itself), "recipe" (a
-- recipe item, id; link = what it makes) or "trainer" (a trainer's recipe; link = what it
-- makes).
local function AddRows(tt, id, link, data, kind)
    local onlyYou = kind == "item" and Soulbound(data)
    local me = ns.char
    if link ~= lastLink or id ~= lastId or kind ~= lastKind or onlyYou ~= lastOnly or version ~= lastVer
        or ns.craftVersion ~= lastCraft or me.level ~= lastLevel then
        lastLink, lastId, lastKind, lastOnly, lastVer, lastCraft, lastLevel = link, id, kind, onlyYou, version, ns.craftVersion, me.level
        local info = Describe(link, data, kind == "recipe")
        local recipeID
        if info then
            if info.bind ~= BIND_ON_EQUIP then
                if kind == "recipe" then recipeID = id else onlyYou = true end
            end
            lastHeader = kind == "item" and L["Upgrade for"] or L["Makes an upgrade for"]
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
        tt:AddDoubleLine(ns.ListName(key, chars[key]), rowText[i], 1, 1, 1, 1, 1, 1)
    end
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
    AddRows(tt, id, link, data, recipe and "recipe" or "item")
end

-- A trainer's recipe: a spell tooltip built by C_TooltipInfo.GetTrainerService(index)
-- (the tooltip's processingInfo names the getter and its index), whose item
-- GetTrainerServiceItemLink(index) links (checked in game 2026-10-15, Copper Dagger).
local function OnSpell(tt, data)
    if tt ~= GameTooltip or not (ns.TooltipsOn() and ns.TipShows("upgrades")) or tt:IsForbidden() then return end
    ns.SyncTipShift()
    local info = tt.processingInfo
    if type(info) ~= "table" or info.getterName ~= "GetTrainerService" or not GetTrainerServiceItemLink then return end
    local index = type(info.getterArgs) == "table" and info.getterArgs[1]
    if issecretvalue(index) or type(index) ~= "number" then return end
    local link = GetTrainerServiceItemLink(index)
    if issecretvalue(link) or type(link) ~= "string" then return end
    local id, _, _, _, _, class = GetItemInfoInstant(link)
    if not id or not (class == WEAPON_CLASS or class == ARMOR_CLASS) then return end
    AddRows(tt, id, link, data, "trainer")
end

---------------------------------------------------------------------------
-- Craftable upgrades (the equipment flyout, Flyout.lua)
---------------------------------------------------------------------------
-- Items any of your characters can craft (their learned recipes, c.crafts) that would be
-- an upgrade for you in one inventory slot. Armour other than cloaks only of the heaviest
-- type you wear now (no leather for a warrior: the owner's rule, 2026-10-16); an item that
-- binds on pickup only if you craft it yourself, as it can't be mailed. Only characters
-- you can mail make things for you (another ruleset or faction can't).
local ARMOR_TYPES = { 1, 2, 3, 4 } -- cloth, leather, mail, plate

-- With the character's skills known, a type they haven't trained doesn't count (plate at
-- 40 needs a visit to the trainer).
local function Heaviest(cls, level, c)
    local best
    for _, sub in ipairs(ARMOR_TYPES) do
        local from = cls.armor[sub]
        if from and from <= level and not Missing(c, ARMOR_SKILL[sub]) then best = sub end
    end
    return best
end

local function InSlot(loc, slot)
    for _, s in ipairs(SLOTS[loc] or {}) do
        if s == slot then return true end
    end
    return false
end

-- The profession an item is really crafted with: crafts from before 0.3.0 hold `true`, and
-- 0.2.x filed some under every profession the character has (the owner's save, 2026-10-16:
-- Leatherworking items also under Cooking, Skinning, Fishing and First Aid), so the entry
-- with the recipe's name wins; a lone `true` stands.
local function CraftProf(crafts, prof, id)
    if type(crafts[prof][id]) == "string" then return prof end
    for other, items in pairs(crafts) do
        if type(items[id]) == "string" then return other end
    end
    return prof
end
ns.CraftProf = CraftProf

local function Better(a, b)
    if a.gain ~= b.gain then return a.gain > b.gain end
    return a.id < b.id
end

-- Fills `out` with { id, link, gain, empty, at, slot (where it does best), train (its skill
-- isn't trained), boe, key (who
-- crafts it), prof }, best gain first, and returns it and whether some item data is still
-- loading (ask again shortly). slot nil: every slot. Runs when the flyout or character
-- sheet opens, never per frame. With `who` ({ class, level, gear, spec }: a player being
-- inspected, Flyout.lua) it's judged for them: only what binds when equipped, as nothing
-- else can be handed over, and nothing that needs a profession (theirs aren't known).
-- `who`: someone other than you (an inspected player, or with `whoKey` one of your other
-- characters, whose crafters are then the characters who can mail them).
function ns.CraftableUpgrades(slot, out, who, whoKey)
    out = out or {}
    wipe(out)
    local me, myKey = who or ns.char, ns.charKey
    local cls = me and CLASSES[me.class]
    if not (cls and me.level and me.gear) then return out, false end
    local heaviest = Heaviest(cls, me.level, me)
    local keys = {}
    for key, c in pairs(ns.db.chars) do
        if whoKey then
            if c.crafts and ns.SameWorld(c, me) then keys[#keys + 1] = key end
        elseif key == myKey or (c.crafts and not ns.Elsewhere(c)) then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys, function(a, b)
        if (a == myKey) ~= (b == myKey) then return a == myKey end -- your own recipes first
        return a < b
    end)
    local done, pending = {}, false
    for _, key in ipairs(keys) do
        local crafts = ns.db.chars[key].crafts or {}
        for prof, items in pairs(crafts) do
            for id in pairs(items) do
                if CraftProf(crafts, prof, id) ~= prof then id = nil end -- counted under its own
                if id then
                local _, _, _, loc, _, class, sub = GetItemInfoInstant(id)
                local armour = class == ARMOR_CLASS and sub and sub >= 1 and sub <= 4 and loc ~= "INVTYPE_CLOAK"
                if not done[id] and (class == ARMOR_CLASS or class == WEAPON_CLASS) and (not slot and SLOTS[loc] or InSlot(loc, slot))
                    and not (armour and sub ~= heaviest) then
                    local _, link = GetItemInfo(id)
                    if not link then
                        Request(id)
                        pending = true
                    else
                        local data = C_TooltipInfo and C_TooltipInfo.GetHyperlink and C_TooltipInfo.GetHyperlink(link)
                        local info = Describe(link, data, false)
                        if info == nil then
                            pending = true
                        elseif info and (info.bind == BIND_ON_EQUIP or (key == myKey and not who)) then
                            done[id] = true
                            local gain, empty, at, best, train = Compare(me, info, link)
                            if gain == false then
                                pending = true
                            elseif gain then
                                out[#out + 1] = { id = id, link = link, gain = gain, empty = empty, at = at, slot = best,
                                    train = train, boe = info.bind == BIND_ON_EQUIP, key = key, prof = prof }
                            end
                        end
                    end
                end
                end
            end
        end
    end
    table.sort(out, Better)
    return out, pending
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------
-- Item data the game sends back after a request: if we were waiting, work upgrades out
-- again. A while after login, the gear every character wore last is asked for, so their
-- scores are ready by the time items are hovered.
-- The character sheet's anvils are worked out once per burst of arrivals, not once per item:
-- 60 crafted items still loading meant 60 full passes over every crafter's items.
local sheetSoon = false
local function SheetChanged()
    sheetSoon = false
    if ns.CharacterSheetChanged then ns.CharacterSheetChanged() end
end

-- A failed load (success false) brings nothing new, and working the anvils out again would
-- only ask for the same item again: an item that never loads would keep that going for ever,
-- past the character sheet's own retry cap (Flyout.lua). Still waiting for a real arrival.
local function ItemArrived(_, success)
    if issecretvalue(success) or success == false then return end
    if waiting then
        waiting = false
        version = version + 1
        if not (C_Timer and C_Timer.After) then return SheetChanged() end
        if not sheetSoon then
            sheetSoon = true
            C_Timer.After(0.5, SheetChanged)
        end
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
    BuildWeights() -- the player's changed weights, now the saved data has loaded
    ns.On("GET_ITEM_INFO_RECEIVED", ItemArrived)
    local spell = Enum.TooltipDataType and Enum.TooltipDataType.Spell
    if spell and TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
        TooltipDataProcessor.AddTooltipPostCall(spell, OnSpell)
    end
    if C_Timer and C_Timer.After then C_Timer.After(10, Prewarm) end
    -- Weapon skills: at login (again 5 s later, in case the list wasn't ready) and once per
    -- burst of SKILL_LINES_CHANGED, which fires at every weapon skill-up in a fight.
    local function Skills()
        skillsSoon = false
        if ns.ScanCombatSkills(ns.char) then ns.UpgradesChanged() end
        if ns.CharacterWindowChanged then ns.CharacterWindowChanged() end -- ranks on the Skills page
    end
    Skills()
    if C_Timer and C_Timer.After then
        C_Timer.After(5, Skills)
        ns.On("SKILL_LINES_CHANGED", function()
            if skillsSoon then return end
            skillsSoon = true
            C_Timer.After(5, Skills)
        end)
    end
end
