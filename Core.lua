-- Alts Forever core: saved data, character identity, event dispatch, slash commands.
local ADDON, ns = ...
local L = ns.L

-- Only one copy of Alts Forever may run (e.g. the CurseForge copy and a dev copy both
-- enabled). Addons load one at a time, so a copy that finds another already running stays
-- off: every file stops here, before touching any global, event or hook, and it says so at
-- login. Both copies keep their data in the same global, AltsForeverDB, so the running copy
-- also puts its own data back when the other copy's saved data replaces it (below).
if AltsForeverRunning then
    ns.disabled = true
    local running = AltsForeverRunning
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function()
        print("|cff66ccffAlts Forever|r: " .. L["two copies are enabled (%s and %s). Only %s is running; disable one of them in the AddOns list."]
            :format(running, ADDON, running))
    end)
    return
end
AltsForeverRunning = ADDON

local DB_VERSION = 2

local pcall, type, pairs, ipairs, print, time = pcall, type, pairs, ipairs, print, time
local issecretvalue = issecretvalue or function() return false end
local UnitName, UnitClass, UnitFactionGroup = UnitName, UnitClass, UnitFactionGroup

-- Bumped whenever the current character's data changes; the tooltip uses it to
-- know when its cached line for the current character is stale.
ns.version = 0
-- Bumped when anyone's craftable items may have changed, including /af delete.
ns.craftVersion = 0

---------------------------------------------------------------------------
-- Events: one frame dispatches to every handler registered for an event
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers = {}

-- Registering an event this client doesn't know throws on Forever, so guard it.
-- Several handlers can listen to one event; they run in the order added.
function ns.On(event, fn)
    if not pcall(frame.RegisterEvent, frame, event) then return false end
    local prev = handlers[event]
    handlers[event] = prev and function(...)
        prev(...)
        fn(...)
    end or fn
    return true
end

-- Removes every handler for the event.
function ns.Off(event)
    handlers[event] = nil
    frame:UnregisterEvent(event)
end

frame:SetScript("OnEvent", function(_, event, ...)
    local fn = handlers[event]
    if fn then fn(...) end
end)

---------------------------------------------------------------------------
-- Escape
---------------------------------------------------------------------------
-- The game's Escape hides every shown window named in UISpecialFrames at once, so with the
-- overview listed too, a window opened from it took the overview down with it (the owner,
-- 2026-11-20: and windows whose box had the keyboard closed alone, so it varied). Now Escape
-- closes our other windows first and the overview only on a later press: the overview isn't
-- listed itself; a stand-in frame of ours is, shown only while the overview is open and no other
-- window of ours is, and Escape hiding it closes the overview.
local escapeWindows, overviewWindow, escapeStandIn, escapeDue = {}, nil, nil, false

local function OthersOpen()
    for _, f in ipairs(escapeWindows) do
        if f:IsShown() then return true end
    end
    return false
end

local function UpdateEscape()
    escapeDue = false
    if not escapeStandIn then return end
    if overviewWindow and overviewWindow:IsShown() and not OthersOpen() then
        escapeStandIn:Show()
    elseif escapeStandIn:IsShown() then
        escapeStandIn:Hide()
    end
end

-- Shown a frame later: the press that closes our last other window must not also reach the
-- stand-in, as the game goes through the whole list in one go.
local function UpdateEscapeLater()
    if escapeDue or not escapeStandIn or escapeStandIn:IsShown() then return end
    if not (overviewWindow and overviewWindow:IsShown()) or OthersOpen() then return end
    if not C_Timer then return UpdateEscape() end
    escapeDue = true
    C_Timer.After(0, UpdateEscape)
end

-- Combat closes every window of ours, as EllesmereUI closes its options (owner, 2026-11-26).
-- Registered with the first window, so nothing listens until one exists.
local closesInCombat = false
local combatOnly = {} -- closed in combat, but not by Escape (the anvils' crafting list)
local function CloseForCombat()
    for _, f in ipairs(escapeWindows) do
        if f:IsShown() then f:Hide() end
    end
    for _, f in ipairs(combatOnly) do
        if f:IsShown() then f:Hide() end
    end
    if overviewWindow and overviewWindow:IsShown() then overviewWindow:Hide() end
end

local function ListenForCombat()
    if closesInCombat then return end
    closesInCombat = true
    ns.On("PLAYER_REGEN_DISABLED", CloseForCombat)
end

-- A panel of ours that a fight should close but Escape needn't, once, when it's made: the
-- character sheet's crafting list, which may be the only one of ours ever made (Codex
-- review, 2026-11-26).
function ns.ClosesInCombat(f)
    ListenForCombat()
    combatOnly[#combatOnly + 1] = f
end

-- Each window of ours that Escape should close, once, when it's created; `overview` for the
-- overview, which closes only once the others have. Starting a fight closes them all.
function ns.EscapeCloses(f, overview)
    ListenForCombat()
    if not UISpecialFrames then
        if overview then overviewWindow = f else escapeWindows[#escapeWindows + 1] = f end
        return
    end
    if overview then
        overviewWindow = f
        if not escapeStandIn then
            escapeStandIn = CreateFrame("Frame", "AltsForeverEscape")
            escapeStandIn:Hide()
            -- Judged by what's open when it runs, never by a flag set around our own Hide: in
            -- game, opening any window from the overview closed it (owner, 2026-11-20), so the
            -- handler can't be relied on to run inside that Hide.
            escapeStandIn:SetScript("OnHide", function()
                if overviewWindow and overviewWindow:IsShown() and not OthersOpen() then overviewWindow:Hide() end
            end)
            UISpecialFrames[#UISpecialFrames + 1] = "AltsForeverEscape"
        end
        f:HookScript("OnShow", UpdateEscape)
        f:HookScript("OnHide", UpdateEscape)
        return
    end
    escapeWindows[#escapeWindows + 1] = f
    UISpecialFrames[#UISpecialFrames + 1] = f:GetName()
    f:HookScript("OnShow", UpdateEscape)
    f:HookScript("OnHide", UpdateEscapeLater)
end

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------
-- Version 1 keyed characters "Name-Realm". Forever has no realms (a full name is
-- unique in its region), so version 2 keys them by full name alone. If two entries
-- share a name, the most recently updated one is kept.
local function Upgrade(saved)
    if saved.v ~= 1 or type(saved.chars) ~= "table" then return end
    local chars = {}
    local function When(c)
        local t = c.updated or c.seen
        return type(t) == "number" and t or 0
    end
    for key, c in pairs(saved.chars) do
        local name = type(c) == "table" and (type(c.name) == "string" and c.name
            or type(key) == "string" and (key:match("^(.*)%-[^%-]*$") or key))
        if name then
            -- A beta realm is kept: it's how ns.LeaveBeta knows the character was the beta's.
            local realm = type(key) == "string" and key:match("%-([^%-]*)$")
            if not ns.BetaRealm(c.realm) then c.realm = nil end
            if c.realm == nil and ns.BetaRealm(realm) then c.realm = realm end
            c.name = name
            local old = chars[name]
            if not old or When(c) > When(old) then chars[name] = c end
        end
    end
    saved.chars, saved.realmOnly, saved.v = chars, nil, 2
end

-- Since build 70009, UnitName returns the first name and the surname as two values, and
-- versions 0.2.0 and 0.2.1 saved characters under the first name alone ("Mira" for "Mira
-- Dawnfield"). Forever names are always two words, so a one-word entry with exactly one
-- "First Last" entry of the same class is that character.
local function FullNameMatch(chars, first, class)
    local match
    for key, c in pairs(chars) do
        if key:sub(1, #first + 1) == first .. " " and type(c) == "table" and c.class == class then
            if match then return nil end -- two candidates: don't guess
            match = key
        end
    end
    return match
end

local function Newer(a, b)
    return (a.updated or a.seen or 0) >= (b.updated or b.seen or 0)
end

-- Keeps everything in `keep` and fills in what it lacks (bank, mail, recipes...) from `other`.
local function Merge(keep, other)
    for k, v in pairs(other) do
        if keep[k] == nil then keep[k] = v end
    end
end

-- Folds entries saved under a first name only back into the full name, newer data first.
local function FoldFirstNames(chars)
    local short = {}
    for key in pairs(chars) do
        if not key:find(" ", 1, true) then short[#short + 1] = key end
    end
    for _, key in ipairs(short) do
        local c = chars[key]
        local full = type(c) == "table" and FullNameMatch(chars, key, c.class)
        if full then
            local keep, old = c, chars[full]
            if not Newer(keep, old) then keep, old = old, keep end
            Merge(keep, old)
            keep.name = full
            chars[full], chars[key] = keep, nil
        end
    end
end

-- Repairs a damaged save in place (hand-edited, or from an older or another copy): a value of
-- the wrong type is dropped, which reads as "not known yet" and is recorded again in play,
-- and everything valid is kept (never reset saved data: owner, 2026-09-25). Once, at load;
-- one type check per stored value.
local CHAR_FIELDS = {
    name = "string", class = "string", faction = "string", realm = "string", zone = "string",
    hearth = "string", hearthReady = "number", prof1 = "string", prof2 = "string", role = "string",
    money = "number", level = "number", xp = "number", xpMax = "number", rested = "number",
    seen = "number", updated = "number", ilvl = "number", dura = "number", played = "number",
    playedAt = "number", mailExpires = "number", spec = "number", wellRested = "number",
    legacySpent = "number", bankAt = "number", bankBought = "number", changed = "number", mailAt = "number",
    bags = "table", bank = "table", mail = "table", equip = "table", gear = "table",
    layout = "table", profs = "table", profMax = "table", recipes = "table", crafts = "table",
    reps = "table", duraSlots = "table", saves = "table", saveKills = "table",
    account = "string", runs = "table", recipesAt = "table", links = "table", cooldowns = "table",
    skills = "table", notLevelling = "table", notLevellingAt = "number",
}
local DB_FIELDS = {
    icons = "table", goldDays = "table", goldDaysBy = "table", factions = "table",
    recipeInfo = "table", collapsedGroups = "table", session = "table", itemNames = "table",
    itemQuality = "table", rulesets = "table", syncWith = "table", forgotten = "table", syncAutoOff = "boolean",
    legacyPool = "number", scale = "number", minimapAngle = "number", bagsCols = "number",
    bagsHeight = "number", wellRested = "number", exportFormat = "string", goldGroup = "string",
    account = "string", tooltipsOff = "boolean", countsOff = "boolean", craftTipsOff = "boolean",
    canCraftOff = "boolean", recipeTipsOff = "boolean",
    cratesOff = "boolean", totalOff = "boolean", tipShift = "table", goldTipOff = "boolean", barsOff = "boolean", recipeCategories = "table", profArt = "table",
    inspectAnvilsOff = "boolean", overviewSort = "string", overviewSortRev = "boolean",
    windows = "table", pinned = "table", hiddenColumns = "table",
    mailRules = "table", mailFillOff = "boolean", mailPackOff = "boolean", weights = "table",
    columnsHintSeen = "boolean", otherCharsOff = "boolean", otherGold = "boolean",
    factionGroups = "table", factionHeadings = "table",
}

-- Keeps only entries whose key and value are of these types (value nil = any).
local function KeepOnly(t, keyType, valueType)
    for k, v in pairs(t) do
        if type(k) ~= keyType or (valueType and type(v) ~= valueType) then t[k] = nil end
    end
end

local function RepairChar(c)
    for field, kind in pairs(CHAR_FIELDS) do
        if c[field] ~= nil and type(c[field]) ~= kind then c[field] = nil end
    end
    for _, place in ipairs({ "bags", "bank", "mail", "equip" }) do
        if c[place] then KeepOnly(c[place], "number", "number") end
    end
    if c.gear then KeepOnly(c.gear, "number", "string") end
    if c.duraSlots then KeepOnly(c.duraSlots, "number", "number") end
    if c.reps then KeepOnly(c.reps, "number", "number") end
    if c.profs then KeepOnly(c.profs, "string", "number") end
    if c.profMax then KeepOnly(c.profMax, "string", "number") end
    if c.recipes then KeepOnly(c.recipes, "string", "table") end
    if c.crafts then KeepOnly(c.crafts, "string", "table") end
    if c.recipesAt then KeepOnly(c.recipesAt, "string", "number") end
    if c.skills then KeepOnly(c.skills, "number", "number") end
    if c.notLevelling then
        KeepOnly(c.notLevelling, "string", "boolean")
        for prof, v in pairs(c.notLevelling) do if v ~= true then c.notLevelling[prof] = nil end end
        if next(c.notLevelling) == nil then c.notLevelling = nil end
    end
    if c.cooldowns then
        KeepOnly(c.cooldowns, "string", "table")
        for prof, t in pairs(c.cooldowns) do
            KeepOnly(t, "string", "number")
            if next(t) == nil then c.cooldowns[prof] = nil end
        end
        if next(c.cooldowns) == nil then c.cooldowns = nil end
    end
    if c.saves then KeepOnly(c.saves, "string", "number") end
    if c.saveKills then KeepOnly(c.saveKills, "string", "string") end
    if c.runs then
        local kept = {}
        for _, r in pairs(c.runs) do
            if type(r) == "table" and type(r.at) == "number" and type(r.map) == "number"
                and (r.left == nil or type(r.left) == "number") and (r.zone == nil or type(r.zone) == "number")
                and (r.last == nil or type(r.last) == "number")
                and (r.name == nil or type(r.name) == "string") then
                kept[#kept + 1] = r
            end
        end
        table.sort(kept, function(a, b) return a.at < b.at end)
        c.runs = kept[1] and kept or nil
    end
    if c.links then
        KeepOnly(c.links, "number", "table")
        for bag, slots in pairs(c.links) do
            KeepOnly(slots, "number", "string")
            if next(slots) == nil then c.links[bag] = nil end
        end
        if next(c.links) == nil then c.links = nil end
    end
    if c.layout then
        KeepOnly(c.layout, "number", "table")
        for _, slots in pairs(c.layout) do
            for i, v in pairs(slots) do
                if type(i) ~= "number" then slots[i] = nil elseif type(v) ~= "number" then slots[i] = 0 end
            end
        end
    end
end

local function Repair(saved)
    for field, kind in pairs(DB_FIELDS) do
        if saved[field] ~= nil and type(saved[field]) ~= kind then saved[field] = nil end
    end
    if saved.icons then
        for place, icon in pairs(saved.icons) do
            if type(place) ~= "string" or (type(icon) ~= "string" and type(icon) ~= "number") then
                saved.icons[place] = nil
            end
        end
    end
    if saved.goldDays then KeepOnly(saved.goldDays, "number", "number") end
    if saved.rulesets then KeepOnly(saved.rulesets, "string", "string") end
    if saved.syncWith then KeepOnly(saved.syncWith, "string", "boolean") end
    if saved.forgotten then KeepOnly(saved.forgotten, "string", "number") end
    if saved.factionGroups then KeepOnly(saved.factionGroups, "number", "number") end
    if saved.factionHeadings then KeepOnly(saved.factionHeadings, "number", "number") end
    if saved.goldDaysBy then
        KeepOnly(saved.goldDaysBy, "string", "table")
        for _, days in pairs(saved.goldDaysBy) do KeepOnly(days, "number", "number") end
    end
    if saved.recipeInfo then
        KeepOnly(saved.recipeInfo, "string", "table")
        for _, recipes in pairs(saved.recipeInfo) do KeepOnly(recipes, "string", "string") end
    end
    if saved.recipeCategories then KeepOnly(saved.recipeCategories, "number", "string") end
    if saved.profArt then KeepOnly(saved.profArt, "string", "string") end
    if saved.mailRules then
        KeepOnly(saved.mailRules, "string", "table")
        for rule, names in pairs(saved.mailRules) do
            KeepOnly(names, "string", "number")
            if next(names) == nil then saved.mailRules[rule] = nil end
        end
    end
    -- Changed upgrade weights: { [role] = { [stat] = number } } (Upgrades.lua; values out of
    -- range are skipped there).
    if saved.weights then
        KeepOnly(saved.weights, "string", "table")
        for role, stats in pairs(saved.weights) do
            KeepOnly(stats, "string", "number")
            if next(stats) == nil then saved.weights[role] = nil end
        end
        if next(saved.weights) == nil then saved.weights = nil end
    end
    local chars = saved.chars
    -- A character under a key that isn't a name moves to its own name if that's free.
    local moved = {}
    for key, c in pairs(chars) do
        if type(key) ~= "string" or type(c) ~= "table" then
            chars[key] = nil
            if type(c) == "table" and type(c.name) == "string" then moved[#moved + 1] = c end
        end
    end
    for _, c in ipairs(moved) do
        if chars[c.name] == nil then chars[c.name] = c end
    end
    for key, c in pairs(chars) do
        RepairChar(c)
        if not c.name then c.name = key end
    end
end
-- Characters from another account (Sync.lua) get the same checks.
ns.RepairChar = RepairChar

function ns.InitDB(saved)
    if type(saved) ~= "table" then saved = { v = DB_VERSION, chars = {} } end
    Upgrade(saved)
    -- A damaged or unknown version marker, or a damaged character list, costs only what's
    -- damaged: the rest is repaired below, never thrown away (owner: repair, never reset).
    saved.v = DB_VERSION
    if type(saved.chars) ~= "table" then saved.chars = {} end
    Repair(saved)
    FoldFirstNames(saved.chars)
    return saved
end

-- The logged-in character's full name. Build 70009 returns it as UnitName's two values
-- ("Mira", "Dawnfield"); earlier builds returned "Mira Dawnfield" as the first value.
function ns.PlayerName()
    local first, surname = UnitName("player")
    if not issecretvalue(surname) and surname and surname ~= "" then
        return first .. " " .. surname
    end
    return first
end

-- An entry saved under this character's first name alone (by 0.2.0 or 0.2.1) takes the
-- full name. Where both exist, InitDB has already folded them together.
function ns.AdoptFirstName(chars, name, class)
    local first = name:match("^(%S+) ")
    local old = first and chars[first]
    if type(old) == "table" and old.class == class and chars[name] == nil then
        chars[name], chars[first] = old, nil
        old.name = name
    end
end

---------------------------------------------------------------------------
-- Rulesets. Forever has no realm list, but each ruleset (Normal, PvP, Roleplaying,
-- Hardcore) is its own world with its own auction house and mail. The client reports a realm
-- name, and one ruleset can have several ("CAMWOWUS2Realm10RP", "CAMWOWUS2Realm11RP": a
-- player's characters on the same ruleset, 2026-11-07), so a realm name says which ruleset
-- a character is on and no more. Characters on different rulesets can't mail or trade, so
-- each character's realm name is recorded at login and characters are grouped by its
-- ruleset. A character not logged in since (no realm yet) counts as being on yours, so
-- nothing disappears until they log in once. Mail never crosses factions either, on any
-- ruleset, so the other faction is treated the same way.
---------------------------------------------------------------------------
-- Else the realm's display name without its spaces and hyphens, as the game makes the
-- normalized one ("CAMWOW AU1 Realm 1 PvE" -> "CAMWOWAU1Realm1PvE"); nil if neither answers.
local function Readable(text)
    if issecretvalue(text) then return nil end
    if type(text) == "string" and text ~= "" then return text end
end

-- The realm's name as the game gives it; nil if it gives none.
function ns.RealmName()
    local realm = Readable(GetNormalizedRealmName and GetNormalizedRealmName())
    if realm then return realm end
    local shown = Readable(GetRealmName and GetRealmName())
    realm = shown and shown:gsub("[%s%-]", "")
    if realm and realm ~= "" then return realm end
end

-- Since a game update (seen 2026-11-27, by the owner and a player) the game names no realm
-- at all: both names are empty and GetRealmID() is 0, on new characters and old. A character
-- is then filed under a stand-in for its ruleset, as the game's rule check reports it; realm
-- names only ever told rulesets apart, and these say theirs (NamedRuleset).
local STAND_IN = { normal = "PvE", pvp = "PvP", rp = "RP", rppvp = "RPPvP", hardcore = "Hardcore" }
local STAND_INS = {}
for _, name in pairs(STAND_IN) do STAND_INS[name] = true end

function ns.PlayerRealm()
    local realm = ns.RealmName()
    if realm then return realm end
    local ruleset = ns.PlayerRuleset()
    return ruleset and STAND_IN[ruleset]
end

local RULESET_NAMES = { normal = L["Normal"], pvp = L["PvP"], rp = L["Roleplaying"],
    rppvp = L["RP-PvP"], hardcore = L["Hardcore"] }

-- What a realm name says about its ruleset, false if nothing. Kept per name: this is asked
-- for every character in a tooltip's list.
local named = {}
local function NamedRuleset(realm)
    local ruleset = named[realm]
    if ruleset == nil then
        local r = realm:lower()
        ruleset = r:find("hardcore", 1, true) and "hardcore"
            or (r:find("rp%-?pvp%d*$") or r:find("roleplay%-?pvp")) and "rppvp"
            or r:find("pvp%d*$") and "pvp"
            or (r:find("rp%d*$") or r:find("roleplay", 1, true)) and "rp"
            or (r:find("pve%d*$") or r:find("normal", 1, true)) and "normal"
            or false
        named[realm] = ruleset
    end
    return ruleset
end

-- A realm's ruleset ("normal", "pvp", "rp", "hardcore"): as the game told us, else from the
-- name; a realm that doesn't say counts as a world of its own, under its own name. The
-- game's "normal" only means no rule it was asked about was on, so the name beats that.
-- RP-PvP: before 1.13.1 the game's answer for it was recorded as "rp" (both rules are on), so
-- a name that says RP-PvP beats it.
function ns.RulesetOf(realm)
    local named = NamedRuleset(realm)
    if named == "rppvp" then return named end
    local told = ns.db.rulesets and ns.db.rulesets[realm]
    if not RULESET_NAMES[told] then told = nil end
    if told and told ~= "normal" then return told end
    return named or told or realm
end

-- Out of mail's reach from the character you're on: another ruleset or the other faction
-- (each known for both).
-- Whether two characters share a world: mail and trade reach each other (the same ruleset
-- when both realms are known, and the same faction when both are known).
function ns.SameWorld(a, b)
    if a.realm and b.realm and a.realm ~= b.realm and ns.RulesetOf(a.realm) ~= ns.RulesetOf(b.realm) then
        return false
    end
    return not (a.faction and b.faction and a.faction ~= b.faction)
end

function ns.Elsewhere(c)
    local me = ns.char
    if not me or c == me then return false end
    if c.realm and me.realm and c.realm ~= me.realm
        and ns.RulesetOf(c.realm) ~= ns.RulesetOf(me.realm) then
        return true
    end
    return c.faction ~= nil and me.faction ~= nil and c.faction ~= me.faction
end

-- Characters out of reach are left out of tooltips unless the player shows them.
function ns.OtherRulesetsOn() return ns.db.otherRulesets == true end
function ns.Hidden(c) return not ns.db.otherRulesets and ns.Elsewhere(c) end

function ns.SetOtherRulesets(on)
    ns.db.otherRulesets = on and true or nil
    ns.InvalidateCache()
    if ns.UpgradesChanged then ns.UpgradesChanged() end
end

-- The overview has its own two (a player's request, 2026-11-25: gold from characters you
-- can't trade with made the totals wrong): their rows (shown unless db.otherCharsOff) and
-- their gold in totals (counted only with db.otherGold).
function ns.OtherCharsShown() return not ns.db.otherCharsOff end
function ns.OtherGoldCounted() return ns.db.otherGold == true end

function ns.SetOtherChars(on)
    ns.db.otherCharsOff = not on or nil
    if ns.RefreshOverview then ns.RefreshOverview() end
end

function ns.SetOtherGold(on)
    ns.db.otherGold = on and true or nil
    if ns.RefreshOverview then ns.RefreshOverview() end
end

-- One game rule: true or false, nil if its answer can't be read (an error or a secret). A rule
-- this client doesn't list can't be on, so it's false.
local function RuleOn(rules, active, name)
    if rules[name] == nil then return false end
    local ok, on = pcall(active, rules[name])
    if not ok or issecretvalue(on) then return nil end
    return on and true or false
end

-- Which ruleset the game says it's running ("pvp", "rp", "rppvp", "hardcore", "normal"), as
-- Nova Instance Tracker asks it on Forever; nil if it can't be asked. RP-PvP has both the RP
-- and the PvP rule on (the owner's RP-PvP character, 2026-11-27; a Normal one has neither).
-- Recorded per realm name at login (db.rulesets), and the stand-in realm when there's no name.
function ns.PlayerRuleset()
    local rules = Enum and Enum.GameRule
    local active = C_GameRules and C_GameRules.IsGameRuleActive
    if not rules or not active then return end
    if rules.HardcoreRuleset == nil and rules.RPRuleset == nil and rules.PvPRuleset == nil then return end
    local hardcore = RuleOn(rules, active, "HardcoreRuleset")
    if hardcore then return "hardcore" end
    local rp, pvp = RuleOn(rules, active, "RPRuleset"), RuleOn(rules, active, "PvPRuleset")
    -- Only answers that settle it: RP with PvP unreadable could be RP or RP-PvP, and nothing on
    -- but one rule unreadable could be anything. Then nil, so nothing is filed on a guess and
    -- the world is asked again (Codex review, 2026-11-27).
    if hardcore == nil or rp == nil or pvp == nil then return end
    if rp and pvp then return "rppvp" end
    if rp then return "rp" end
    if pvp then return "pvp" end
    return "normal"
end

-- The ruleset's name, in the player's language; a realm name that doesn't say is shown as
-- it is.
function ns.RulesetLabel(realm)
    if not realm then return L["Not sorted yet (log in on them once)"] end
    return RULESET_NAMES[ns.RulesetOf(realm)] or realm
end

-- What tells your characters' groups apart: rulesets once two are known, factions once
-- both are played. Neither: one group, no headings.
function ns.GroupParts()
    local ruleset, faction, byRealm, byFaction
    for _, c in pairs(ns.db.chars) do
        if c.realm then
            local r = ns.RulesetOf(c.realm)
            if ruleset and ruleset ~= r then byRealm = true end
            ruleset = r
        end
        if c.faction then
            if faction and faction ~= c.faction then byFaction = true end
            faction = c.faction
        end
    end
    return byRealm or false, byFaction or false
end

-- A character's group for the parts in use (from GroupParts), and its heading, e.g.
-- "PvP · Horde". A realm not known yet is "?".
function ns.GroupKey(c, byRealm, byFaction)
    local ruleset = byRealm and (c.realm and ns.RulesetOf(c.realm) or "?") or ""
    return ruleset .. "|" .. (byFaction and (c.faction or "?") or "")
end

local function FactionName(f)
    local name = type(f) == "string" and _G["FACTION_" .. f:upper()]
    return type(name) == "string" and name or f or "?"
end

function ns.GroupLabel(c, byRealm, byFaction)
    local ruleset = byRealm and ns.RulesetLabel(c.realm)
    local faction = byFaction and FactionName(c.faction)
    if ruleset and faction then return ruleset .. " · " .. faction end
    return ruleset or faction or ""
end

---------------------------------------------------------------------------
-- The beta. Its realms are "ClassicBetaPvE", "ClassicBetaPvE2", "ClassicBetaPvP"..., and its
-- characters don't carry over to the live game. A saved file from the beta still lists them
-- (the same file, or a WTF folder copied over), so the first login on a live realm forgets
-- them; nobody would want to keep them (owner, 2026-10-23).
---------------------------------------------------------------------------
function ns.BetaRealm(realm)
    return type(realm) == "string" and realm:lower():find("^classicbeta") ~= nil
end

-- A character with no realm (realms were recorded only from 0.12.0, and a version 1 save
-- loses them in Upgrade) is from the beta if it was last seen before 1.0.0 came out, ahead
-- of the live game (2026-10-23). One seen since, or with no time recorded, is kept: a live
-- character whose realm couldn't be read once must never be taken for the beta's.
ns.BETA_ENDED = 1792713600

local function FromBeta(c)
    if ns.BetaRealm(c.realm) then return true end
    if c.realm ~= nil then return false end
    local seen, updated = c.seen, c.updated
    local last = type(seen) == "number" and seen or nil
    if type(updated) == "number" and (not last or updated > last) then last = updated end
    return last ~= nil and last < ns.BETA_ENDED
end

-- On a live realm: forgets every character from the beta, before this one is set up (a
-- namesake from the beta is a different character, so you start fresh), with the beta's gold
-- history and Legacy points (the saved pool never shrinks, so every live character would be
-- told it had the beta's points to spend). Settings stay. Returns how many went.
function ns.LeaveBeta(db, realm)
    if not realm or ns.BetaRealm(realm) then return 0 end
    local chars, gone = db.chars, 0
    for key, c in pairs(chars) do
        if FromBeta(c) then chars[key], gone = nil, gone + 1 end
    end
    if gone == 0 then return 0 end
    for group in pairs(db.goldDaysBy or {}) do
        local r = group:match("^(.-)|")
        if r == "" or ns.BetaRealm(r) then db.goldDaysBy[group] = nil end
    end
    if db.goldDaysBy and next(db.goldDaysBy) == nil then db.goldDaysBy = nil end
    -- The main history was the beta's (or from before groups): Money.lua starts it afresh.
    local main = db.goldGroup and db.goldGroup:match("^(.-)|")
    if main == nil or main == "" or ns.BetaRealm(main) then db.goldDays, db.goldGroup = nil, nil end
    for r in pairs(db.rulesets or {}) do
        if ns.BetaRealm(r) then db.rulesets[r] = nil end
    end
    db.collapsedGroups = nil -- their keys named the beta's groups
    db.legacyPool, db.wellRested = nil, nil
    ns.PruneRecipeInfo()
    return gone
end

-- Bank and mail stay nil until first seen, so "never scanned" differs from "empty".
-- Characters are keyed by full name ("First Last"), which is unique in a region.
function ns.InitChar(db, name, class, faction, realm)
    local key = name
    local c = db.chars[key]
    if type(c) ~= "table" then
        c = {}
        db.chars[key] = c
    end
    c.name, c.class = name, class
    -- An empty or secret faction is unknown, not a faction (kept unknown, it's asked again:
    -- ns.WatchWorld). One saved as "" before 1.12.2 is dropped here too (Codex review).
    c.faction = Readable(faction) or Readable(c.faction)
    if realm and STAND_INS[realm] then
        -- A stand-in keeps a real name saved earlier on the same ruleset; it replaces one the
        -- game now says is another (an RP-PvP realm recorded as RP).
        if not (c.realm and ns.RulesetOf(c.realm) == ns.RulesetOf(realm)) then c.realm = realm end
    elseif realm then
        c.realm = realm
        local ruleset = ns.PlayerRuleset()
        if ruleset then
            db.rulesets = db.rulesets or {}
            db.rulesets[realm] = ruleset
        end
    end
    c.bags = c.bags or {}
    c.equip = c.equip or {}
    return key, c
end

ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON then
        -- Another copy's saved data just loaded into the shared global: keep ours.
        if ns.db and AltsForeverDB ~= ns.db then AltsForeverDB = ns.db end
        return
    end
    -- A fresh install: no saved data, or no characters yet (then the welcome is shown).
    local saved = AltsForeverDB
    ns.freshInstall = type(saved) ~= "table" or type(saved.chars) ~= "table" or next(saved.chars) == nil
    AltsForeverDB = ns.InitDB(AltsForeverDB)
    ns.db = AltsForeverDB
    -- Left over from the rested XP rate check, which has been removed.
    ns.db.restedChecks, ns.db.restCheckOff = nil, nil
    -- Until 1.9.1 one switch turned off both Can craft and recipe status: now two.
    if ns.db.craftTipsOff then ns.db.canCraftOff, ns.db.recipeTipsOff = true, true end
    ns.db.craftTipsOff = nil
    -- The dev builds' single Shift switch (2026-11-26, never released): Skill-ups and Total.
    if ns.db.shiftDetails == true then ns.db.tipShift = { skillups = true, total = true } end
    ns.db.shiftDetails = nil
    -- Before login, so EllesmereUI's minimap finds it when it collects addon buttons.
    ns.CreateMinimapButton()
end)

ns.On("PLAYER_LOGIN", function()
    ns.Off("PLAYER_LOGIN")
    local _, class = UnitClass("player")
    local name = ns.PlayerName()
    ns.AdoptFirstName(ns.db.chars, name, class)
    local betaGone = ns.LeaveBeta(ns.db, ns.RealmName())
    local newChar = ns.db.chars[name] == nil
    ns.charKey, ns.char = ns.InitChar(ns.db, name, class, UnitFactionGroup("player"), ns.PlayerRealm())
    ns.StartScanner()
    ns.StartMail()
    ns.StartMailRules()
    ns.StartMoney()
    ns.StartProfessions()
    ns.StartCharacter()
    ns.StartTalents()
    ns.StartOverview()
    ns.StartBars()
    ns.StartGear()
    ns.StartBags()
    ns.StartTooltip()
    ns.StartUpgrades()
    ns.StartFlyout()
    ns.StartReputation()
    ns.StartLockouts()
    ns.StartSync()
    ns.StartOptions()
    ns.StartBroker()
    ns.StartGamepad()
    ns.StartItemNames()
    ns.Welcome(newChar, betaGone)
    ns.WatchWorld()
end)

-- The realm (and faction) may not be readable yet at login: a player's new characters
-- stayed "Not sorted yet" in the overview across sessions, with no realm in the saved file
-- (2026-11-25; not seen by us). Until both are known they're asked again as each loading
-- screen ends and a few times in the first minute; once known, everything that groups
-- characters is told.
local worldTries = 0
local function WorldKnown()
    local c = ns.char
    if not c or c.realm and c.faction then return true end
    local realm, faction = ns.PlayerRealm(), Readable(UnitFactionGroup("player"))
    if not (realm and not c.realm or faction and not c.faction) then return false end
    ns.InitChar(ns.db, ns.charKey, c.class, faction, realm)
    if ns.InvalidateCache then ns.InvalidateCache() end
    if ns.MoneyWorldKnown then ns.MoneyWorldKnown() end
    if ns.UpgradesChanged then ns.UpgradesChanged() end
    if ns.RefreshOverview then ns.RefreshOverview() end
    return c.realm and c.faction and true or false
end

-- Stays registered once done (ns.Off would drop every handler of the event): returns at once.
local worldDone
local function TryWorld()
    if worldDone then return end
    if WorldKnown() then worldDone = true return end
    worldTries = worldTries + 1
    if worldTries <= 4 and C_Timer and C_Timer.After then C_Timer.After(worldTries * 5, TryWorld) end
end

function ns.WatchWorld()
    if ns.char.realm and ns.char.faction then return end
    ns.On("PLAYER_ENTERING_WORLD", TryWorld)
    if C_Timer and C_Timer.After then C_Timer.After(2, TryWorld) end
end

-- A few seconds after login (after the game's own login messages): on a fresh install,
-- how to use Alts Forever, once; on a character seen for the first time, that it's now
-- tracked; on the first live login, that the beta's characters were forgotten. Existing
-- players never see the welcome (db.welcomed is set quietly).
function ns.Welcome(newChar, betaGone)
    local db = ns.db
    local lines
    if not db.welcomed and ns.freshInstall then
        lines = {
            L["Welcome! Hover any item to see how many your characters have, and where."],
            L["Type /af or click the minimap button for all your characters at a glance. Settings are under Options > AddOns > Alts Forever."],
            L["Log in on each character once, and open their bank, mailbox and profession windows once, so Alts Forever knows what they have."],
        }
    elseif newChar then
        lines = { L["Now tracking %s. Open the bank and mailbox once on this character so they're included too."]:format(ns.charKey) }
    end
    db.welcomed = true
    if betaGone and betaGone > 0 then
        lines = lines or {}
        table.insert(lines, 1, L["Welcome to the live game! Alts Forever has forgotten your characters from the beta (%d), which don't carry over. Your settings are kept."]:format(betaGone))
    end
    if not lines then return end
    local function Show()
        for i = 1, #lines do ns.Print(lines[i]) end
    end
    if C_Timer and C_Timer.After then C_Timer.After(5, Show) else Show() end
end

ns.On("PLAYER_LOGOUT", function()
    if ns.char then ns.char.seen = time() end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function Print(msg)
    print("|cff66ccffAlts Forever|r: " .. msg)
end
ns.Print = Print

-- Finds a stored character by full name, ignoring case.
function ns.FindChar(input)
    input = input:lower()
    for key in pairs(ns.db.chars) do
        if key:lower() == input then return key end
    end
end
local FindChar = ns.FindChar

local commands = {}

function commands.list()
    for key, c in pairs(ns.db.chars) do
        Print(key .. (c.bank and "" or "  " .. L["(bank not scanned)"]))
    end
end

function commands.delete(arg)
    local key = arg ~= "" and FindChar(arg)
    if not key then return Print(L["No character named '%s'. Use /af list."]:format(arg)) end
    if key == ns.charKey then return Print(L["You can't delete the character you're logged in on."]) end
    ns.ForgetCharacter(key)
    Print(L["Deleted %s."]:format(key))
end

function commands.mail()
    -- Everyone with mail on record, however far off it expires.
    if not ns.PrintMailWarnings(math.huge) then Print(L["No mail with items or gold on record."]) end
end

-- A tooltip part's switch: says it's on or off, and that nothing shows while all of
-- Alts Forever is off in tooltips (/af tooltips).
local function TipPrint(msg)
    Print(msg)
    if not ns.TooltipsOn() then Print(L["Alts Forever adds nothing to tooltips until you turn it back on with /af tooltips."]) end
end

function commands.tooltips()
    ns.SetTooltips(not ns.TooltipsOn())
    Print(ns.TooltipsOn() and L["Alts Forever in tooltips on."] or L["Alts Forever in tooltips off. /af tooltips turns it back on."])
end

function commands.counts()
    ns.SetCounts(not ns.CountsOn())
    TipPrint(ns.CountsOn() and L["Item counts in tooltips on."] or L["Item counts in tooltips off."])
end

function commands.crafting()
    ns.SetCraftTips(not ns.CraftTipsOn())
    TipPrint(ns.CraftTipsOn() and L["Can craft in tooltips on."] or L["Can craft in tooltips off."])
end

function commands.recipes()
    ns.SetRecipeTips(not ns.RecipeTipsOn())
    TipPrint(ns.RecipeTipsOn() and L["Recipe status in tooltips on."] or L["Recipe status in tooltips off."])
end

function commands.crates()
    ns.SetCrates(not ns.CratesOn())
    TipPrint(ns.CratesOn() and L["Waylaid Crate materials in tooltips on."] or L["Waylaid Crate materials in tooltips off."])
end

-- /af shift lists each part of item tooltips with its choice (Always, Shift, Never);
-- /af shift <part> puts that part on Shift, or back to Always.
local SHIFT_WORDS = { counts = "counts", total = "total", crafting = "crafting", craft = "crafting",
    skillups = "skillups", recipes = "recipes", upgrades = "upgrades", crates = "crates", rulesets = "rulesets" }
function commands.shift(arg)
    local part = SHIFT_WORDS[(arg or ""):lower():match("^%s*(%a*)") or ""]
    if part then
        ns.SetTipMode(part, ns.TipMode(part) == "shift" and "always" or "shift")
        return TipPrint(L["%s in item tooltips: %s."]:format(ns.TipPartName(part), ns.TipModeName(ns.TipMode(part))))
    end
    Print(L["Item tooltips (Always, Shift or Never):"])
    for _, p in ipairs(ns.TIP_PARTS) do
        Print("  " .. L["%s: %s"]:format(ns.TipPartName(p), ns.TipModeName(ns.TipMode(p))))
    end
    Print(L["/af shift <part> puts a part on Shift, or back to Always: counts, total, crafting, skillups, recipes, upgrades, crates, rulesets."])
end

function commands.gold()
    ns.SetGoldTip(not ns.GoldTipOn())
    TipPrint(ns.GoldTipOn() and L["Your characters' gold on your bag money on."] or L["Your characters' gold on your bag money off."])
end

function commands.bars()
    ns.SetBars(not ns.BarsOn())
    TipPrint(ns.BarsOn() and L["Your characters on the XP and reputation bars on."] or L["Your characters on the XP and reputation bars off."])
end

function commands.skillups()
    ns.SetSkillups(not ns.SkillupsOn())
    TipPrint(ns.db.skillupsOff and L["Skill-up details in tooltips off."] or L["Skill-up details in tooltips on."])
end

-- /af rulesets: in tooltips; /af rulesets overview: their rows; /af rulesets gold: their
-- gold in totals.
function commands.rulesets(arg)
    arg = (arg or ""):lower():match("^%s*(%a*)") or ""
    if arg == "overview" then
        ns.SetOtherChars(not ns.OtherCharsShown())
        return Print(ns.OtherCharsShown() and L["Characters on other rulesets or factions are shown in the overview."]
            or L["Characters on other rulesets or factions are hidden in the overview."])
    elseif arg == "gold" then
        ns.SetOtherGold(not ns.OtherGoldCounted())
        return Print(ns.OtherGoldCounted() and L["Gold totals include characters on other rulesets or factions."]
            or L["Gold totals count only characters you can mail from here."])
    end
    ns.SetOtherRulesets(not ns.OtherRulesetsOn())
    TipPrint(ns.OtherRulesetsOn() and L["Characters on other rulesets or factions are shown in tooltips."]
        or L["Characters on other rulesets or factions are hidden in tooltips."])
end

-- /af itemnames: item names and qualities in the saved file, for reading it outside the game.
function commands.itemnames()
    ns.SetItemNames(not ns.ItemNamesOn())
    Print(ns.ItemNamesOn() and L["Item names will be saved in Alts Forever's saved file when you log out. They're only for reading the file outside the game: Alts Forever doesn't need them."]
        or L["Item names are no longer saved."])
end

function commands.inspect()
    ns.SetInspectAnvils(not ns.InspectAnvilsOn())
    Print(ns.InspectAnvilsOn() and L["Craftable upgrades in the inspect window on."] or L["Craftable upgrades in the inspect window off."])
end

-- /af pin First Last: pins a character to the top of the overview, or unpins them.
function commands.pin(arg)
    local key = FindChar(arg or "")
    if not key then return Print(L["/af pin and a character's name pins them to the top of the overview, or unpins them."]) end
    local on = not ns.IsPinned(key)
    ns.SetPinned(key, on)
    Print((on and L["%s is pinned to the top of the overview."] or L["%s is no longer pinned."]):format(key))
end

-- /af columns: every overview column back. /af columns gold: hides or shows that one
-- (the words are English in every language, like the role words).
function commands.columns(arg)
    local word = (arg or ""):match("^%s*(.-)%s*$")
    if word == "" then
        ns.ShowAllColumns()
        return Print(L["Every overview column is shown."])
    end
    local id, title = ns.ColumnId(word)
    if not id then
        return Print(L["/af columns shows every overview column again; /af columns and one of level, rested, restedfull, wellrested, legacy, gold, professions, secondary, mail, bags, bank, lockouts, cooldowns, zone, played or lastseen hides or shows that column."])
    end
    local on = not ns.ColumnShown(id)
    ns.SetColumnShown(id, on)
    Print((on and L["The %s column is shown."] or L["The %s column is hidden. /af columns brings every column back."]):format(title))
end

function commands.resetwindows()
    ns.ResetWindows()
    Print(L["Alts Forever's windows are back where they open by default."])
end

function commands.anvils()
    ns.SetAnvils(not ns.AnvilsOn())
    Print(ns.AnvilsOn() and L["Craftable upgrades on the character sheet on."] or L["Craftable upgrades on the character sheet off."])
end

-- /af scale 150: our windows' size in % (Options.lua); on its own, says what it is.
-- /af scale eui: back to following EllesmereUI's Window Scale.
function commands.scale(arg)
    arg = (arg or ""):lower()
    local n = tonumber(arg:match("^%s*(%d+%.?%d*)%%?%s*$"))
    if n and n > 0 then
        ns.SetWindowScale(n / 100)
    elseif arg:match("^%s*eui%s*$") or arg:match("^%s*ellesmere") then
        ns.FollowEllesmere()
    end
    if ns.FollowsEllesmere() then
        Print(L["Window size: %s, the same as EllesmereUI's Window Scale. /af scale and a size from 50 to 300 sets your own."]:format(ns.ScaleText()))
    else
        Print(L["Window size: %s. /af scale and a size from 50 to 300 changes it."]:format(ns.ScaleText()))
    end
end

function commands.upgrades()
    ns.SetUpgrades(not ns.UpgradesOn())
    TipPrint(ns.UpgradesOn() and L["Upgrades in item tooltips on."] or L["Upgrades in item tooltips off."])
end

-- /af legacy lists Legacy points to spend and Well Rested ranks; on/off sets the reminders.
function commands.legacy(arg)
    arg = arg:lower()
    if arg == "on" or arg == "off" then
        ns.SetLegacyReminders(arg == "on")
        return Print(ns.LegacyRemindersOn() and L["Legacy reminders on."] or L["Legacy reminders off."])
    end
    local lines = ns.LegacyLines()
    if #lines == 0 then return Print(L["No Legacy points read yet: log in on each character once."]) end
    Print(L["Legacy points to spend:"])
    for _, line in ipairs(lines) do Print("  " .. line) end
end

-- /af role First Last melee|ranged|caster|healer|tank|feral|auto: the stats a character's
-- upgrades are judged by; auto follows their talents.
function commands.role(arg)
    local name, word = arg:match("^(.-)%s+(%S+)$")
    local key = name and FindChar(name)
    if not key then return Print(L["Type /af role, a character's name and a role: melee, ranged, marksman, caster, healer, tank, feral, or auto to follow their talents."]) end
    local c = ns.db.chars[key]
    local choices = ns.RoleChoices(c)
    if not choices then return Print(L["%s has only one role, so there's nothing to choose."]:format(key)) end
    word = word:lower()
    if word == "auto" then
        ns.SetRole(key, nil)
        return Print(L["Upgrades for %s now follow their talents (%s)."]:format(key, ns.RoleName(ns.AutoRole(c))))
    end
    local role = ns.RoleFromWord(c, word)
    if not role then
        local words = {}
        for i, r in ipairs(choices) do words[i] = ns.RoleWord(r) end
        return Print(L["%s has no role '%s'. Choose from: %s, or auto."]:format(key, word, table.concat(words, ", ")))
    end
    ns.SetRole(key, role)
    Print(L["Upgrades for %s are now judged as %s."]:format(key, ns.RoleName(role)))
end

-- /af weights [First Last]: the Upgrade weights window (Weights.lua), on that character's
-- role, else yours.
function commands.weights(arg)
    local key = ns.charKey
    if arg ~= "" then
        key = FindChar(arg)
        if not key then return Print(L["No character named '%s'. Use /af list."]:format(arg)) end
    end
    local c = ns.db.chars[key]
    ns.ShowWeights(c and ns.RoleOf(c))
end

function commands.minimap()
    ns.SetMinimapButton(not ns.MinimapButtonOn())
    Print(ns.MinimapButtonOn() and L["Minimap button shown."] or L["Minimap button hidden. /af minimap brings it back."])
end

-- /af mailrules: the Mail rules window (MailRules.lua).
function commands.mailrules()
    ns.ToggleMailRules()
end

function commands.sendmail()
    ns.SetSendToAlt(not ns.SendToAltOn())
    Print(ns.SendToAltOn() and L["Send to alt arrow at the mailbox on."] or L["Send to alt arrow at the mailbox off."])
end

function commands.stats()
    ns.SetStats(not ns.StatsOn())
    Print(ns.StatsOn() and L["Session stats on: XP this session on the XP bar, gold over time on your bag gold."]
        or L["Session stats off."])
end

function commands.icons()
    if not ns.OpenSettings() then ns.OpenIconPicker("bags") end
end

-- /af search [text], /af find [text] or /afs: the search window (Search.lua). /af find
-- listed matches in chat until the window came (owner, 2026-10-16: both do the same now).
function commands.search(arg)
    ns.ToggleSearch(arg)
end
commands.find = commands.search

-- /af bags [name], /af bank [name]: a character's bags or bank, slot by slot.
local function ShowBags(arg, which)
    local key = arg == "" and ns.charKey or FindChar(arg)
    if not key then return Print(L["No character named '%s'. Use /af list."]:format(arg)) end
    ns.ShowBags(key, which)
end
function commands.bags(arg) ShowBags(arg, "bags") end
function commands.bank(arg) ShowBags(arg, "bank") end

-- /af prof [name]: a character's professions, as the game's profession window shows them.
function commands.prof(arg)
    local key = arg == "" and ns.charKey or FindChar(arg)
    if not key then return Print(L["No character named '%s'. Use /af list."]:format(arg)) end
    ns.ShowRecipes(key)
end
commands.professions = commands.prof

function commands.rep()
    ns.ToggleReputation()
end

-- /af cooldowns: every character's profession cooldowns (Professions.lua), in the
-- overview's order.
function commands.cooldowns()
    local now, any = time(), false
    for _, key in ipairs(ns.OverviewOrder()) do
        local rows = ns.CooldownRows(ns.db.chars[key], now)
        if rows then
            if not any then Print(L["Profession cooldowns:"]) end
            any = true
            local parts = {}
            for i, r in ipairs(rows) do parts[i] = ns.CooldownName(r) .. " " .. ns.CooldownText(r[2], now) end
            Print("  " .. ns.ColoredName(key, ns.db.chars[key]) .. ": " .. table.concat(parts, ", "))
        end
    end
    if not any then
        Print(L["No profession cooldowns seen yet. One shows once a character has crafted something with a cooldown (Mooncloth, a transmute...) with their profession window open."])
    end
end
commands.cooldown, commands.cd = commands.cooldowns, commands.cooldowns

-- /af lockouts: the Lockouts window (Lockouts.lua).
function commands.lockouts()
    ns.ToggleLockouts()
end

-- /af sync First Last: swaps characters with your character on another game account (Sync.lua).
function commands.sync(arg)
    ns.SyncWith(arg)
end

-- /af export: every character as text to copy (Export.lua).
function commands.export()
    ns.ToggleExport()
end

function commands.mem()
    UpdateAddOnMemoryUsage()
    Print(L["Memory: %.1f KB"]:format(GetAddOnMemoryUsage(ADDON)))
end

function commands.help()
    Print(L["by Kadmai. /af opens the overview. Also: /af rep | export | mail | list | delete Name | skillups | sendmail | minimap | stats | mem"])
    Print(L["/af settings opens the Options page; /af help lists every command."])
    Print(L["/af search (or /afs), with or without a name, finds an item on any of your characters, or who can craft it."])
    Print(L["/af tooltips turns everything Alts Forever adds to tooltips on or off. /af crafting, recipes, crates, gold and bars turn one part on or off."])
    Print(L["/af counts turns the item counts in tooltips on or off (if another addon, such as Baganator, already shows them)."])
    Print(L["/af shift <part> puts a part on Shift, or back to Always: counts, total, crafting, skillups, recipes, upgrades, crates, rulesets."])
    Print(L["/af bags or /af bank, with a name for another character, shows their bags or bank slot by slot."])
    Print(L["/af prof, with a name for another character, shows their professions and recipes."])
    Print(L["/af icons picks the icons item tooltips use for bags, bank, mail and worn items."])
    Print(L["/af upgrades turns upgrade hints in item tooltips on or off. /af role Name role sets what a character's upgrades are judged by (melee, ranged, marksman, caster, healer, tank, feral or auto)."])
    Print(L["/af weights, with or without a name, opens the upgrade weights: what each stat is worth to each role, which you can change."])
    Print(L["/af itemnames turns saving item names in Alts Forever's saved file on or off (only for reading it outside the game)."])
    Print(L["/af anvils shows or hides the anvils on your character sheet that mark upgrades you or your alts can craft."])
    Print(L["/af inspect shows or hides the anvils in the inspect window that mark upgrades you or your alts can craft for that player."])
    Print(L["/af scale 150 makes Alts Forever's windows one and a half times their size (any size from 50 to 300), on top of the game's UI scale."])
    Print(L["/af pin and a character's name pins them to the top of the overview, or unpins them."])
    Print(L["/af columns shows every overview column again; /af columns and one of level, rested, restedfull, wellrested, legacy, gold, professions, secondary, mail, bags, bank, lockouts, cooldowns, zone, played or lastseen hides or shows that column."])
    Print(L["/af resetwindows puts Alts Forever's windows back where they open by default."])
    if ns.HasEllesmereScale() then Print(L["/af scale eui makes them follow EllesmereUI's Window Scale again (the default)."]) end
    Print(L["/af legacy lists each character's Legacy points to spend and Well Rested rank; /af legacy on or off turns the reminders on or off."])
    Print(L["/af mailrules lists which items always go to which character by mail; make rules from the arrow beside the To box at the mailbox."])
    Print(L["/af lockouts opens your characters' raid lockouts and the instances each game account has entered this hour."])
    Print(L["/af cooldowns lists your characters' profession cooldowns (Mooncloth, transmutes...) and when each is ready."])
    Print(L["/af sync and the name of your character on another game account swaps characters with it, so both accounts see all of them. Both need to be online at the same time, on the same ruleset and faction."])
    Print(L["/af sync auto turns syncing by itself on or off."])
    Print(L["/af rulesets shows or hides your characters on other rulesets (Normal, PvP...) or the other faction in tooltips; they can't trade with this one."])
    Print(L["Or use the minimap button (right-click for options)."])
end
ns.ShowHelp = commands.help

-- Opens the Options page (Options.lua); without one (it failed to register), the help.
function commands.settings()
    if not ns.OpenSettings() then commands.help() end
end
commands.options, commands.config = commands.settings, commands.settings

-- For the menus: runs a slash command by name.
function ns.RunCommand(name, arg)
    commands[name](arg or "")
end

commands[""] = function() ns.ToggleOverview() end

SLASH_ALTSFOREVERSEARCH1 = "/afs"
SlashCmdList.ALTSFOREVERSEARCH = function(msg) ns.ToggleSearch(msg) end

SLASH_ALTSFOREVER1, SLASH_ALTSFOREVER2 = "/af", "/altsforever"
SlashCmdList.ALTSFOREVER = function(msg)
    local cmd, arg = msg:match("^%s*(%S*)%s*(.-)%s*$")
    local fn = commands[cmd:lower()] or commands.help
    fn(arg)
end
