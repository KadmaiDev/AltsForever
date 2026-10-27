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
-- Saved data
---------------------------------------------------------------------------
-- Version 1 keyed characters "Name-Realm". Forever has no realms (a full name is
-- unique in its region), so version 2 keys them by full name alone. If two entries
-- share a name, the most recently updated one is kept.
local function Upgrade(saved)
    if saved.v ~= 1 or type(saved.chars) ~= "table" then return end
    local chars = {}
    for key, c in pairs(saved.chars) do
        if type(c) == "table" then
            local name = c.name or key:match("^(.*)%-[^%-]*$") or key
            c.name, c.realm = name, nil
            local old = chars[name]
            if not old or (c.updated or c.seen or 0) > (old.updated or old.seen or 0) then chars[name] = c end
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
    hearth = "string", prof1 = "string", prof2 = "string", role = "string",
    money = "number", level = "number", xp = "number", xpMax = "number", rested = "number",
    seen = "number", updated = "number", ilvl = "number", dura = "number", played = "number",
    playedAt = "number", mailExpires = "number", spec = "number", wellRested = "number",
    legacySpent = "number", bankAt = "number",
    bags = "table", bank = "table", mail = "table", equip = "table", gear = "table",
    layout = "table", profs = "table", profMax = "table", recipes = "table", crafts = "table",
    reps = "table", duraSlots = "table",
}
local DB_FIELDS = {
    icons = "table", goldDays = "table", goldDaysBy = "table", factions = "table",
    recipeInfo = "table", collapsedGroups = "table", session = "table", itemNames = "table",
    itemQuality = "table", rulesets = "table",
    legacyPool = "number", scale = "number", minimapAngle = "number", bagsCols = "number",
    bagsHeight = "number", wellRested = "number", exportFormat = "string", goldGroup = "string",
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
    if saved.goldDays then KeepOnly(saved.goldDays, "number", "number") end
    if saved.rulesets then KeepOnly(saved.rulesets, "string", "string") end
    if saved.goldDaysBy then
        KeepOnly(saved.goldDaysBy, "string", "table")
        for _, days in pairs(saved.goldDaysBy) do KeepOnly(days, "number", "number") end
    end
    if saved.recipeInfo then
        KeepOnly(saved.recipeInfo, "string", "table")
        for _, recipes in pairs(saved.recipeInfo) do KeepOnly(recipes, "string", "string") end
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

function ns.InitDB(saved)
    if type(saved) == "table" then Upgrade(saved) end
    if type(saved) ~= "table" or saved.v ~= DB_VERSION or type(saved.chars) ~= "table" then
        saved = { v = DB_VERSION, chars = {} }
    end
    Repair(saved)
    FoldFirstNames(saved.chars)
    return saved
end

-- The logged-in character's full name. Build 70009 returns it as UnitName's two values
-- ("Mira", "Dawnfield"); earlier builds returned "Mira Dawnfield" as the first value.
function ns.PlayerName()
    local first, surname = UnitName("player")
    if surname and not issecretvalue(surname) and surname ~= "" then
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
-- Hardcore) is its own world with its own auction house and mail, and the client reports
-- one realm name for it (the owner's Normal characters: "ClassicBetaPvE2"). Characters on
-- different rulesets can't mail or trade, so each character's realm name is recorded at
-- login and characters are grouped by it. A character not logged in since (no realm yet)
-- counts as being on yours, so nothing disappears until they log in once. Mail never
-- crosses factions either, on any ruleset, so the other faction is treated the same way.
---------------------------------------------------------------------------
function ns.PlayerRealm()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if type(realm) == "string" and not issecretvalue(realm) and realm ~= "" then return realm end
end

-- Out of mail's reach from the character you're on: another ruleset or the other faction
-- (each known for both).
function ns.Elsewhere(c)
    local me = ns.char
    if not me or c == me then return false end
    if c.realm and me.realm and c.realm ~= me.realm then return true end
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

-- Which ruleset the game says it's running ("pvp", "rp", "hardcore", "normal"), as Nova
-- Instance Tracker asks it on Forever; nil if it can't be asked. Recorded per realm name at
-- login (db.rulesets), so live realm names that don't say their ruleset still get one.
local RULES = { { "HardcoreRuleset", "hardcore" }, { "RPRuleset", "rp" }, { "PvPRuleset", "pvp" } }
function ns.PlayerRuleset()
    local rules = Enum and Enum.GameRule
    local active = C_GameRules and C_GameRules.IsGameRuleActive
    if not rules or not active then return end
    local asked
    for _, rule in ipairs(RULES) do
        if rules[rule[1]] ~= nil then
            local ok, on = pcall(active, rules[rule[1]])
            if ok and not issecretvalue(on) then
                if on then return rule[2] end
                asked = true
            end
        end
    end
    return asked and "normal" or nil
end

local RULESET_NAMES = { normal = "Normal", pvp = "PvP", rp = "Roleplaying", hardcore = "Hardcore" }

-- The ruleset's name, in the player's language: as the game told us for that realm, else
-- from the realm name; a realm name that doesn't say is shown as it is.
local function RulesetBase(realm)
    local known = ns.db.rulesets and RULESET_NAMES[ns.db.rulesets[realm]]
    if known then return L[known] end
    local r = realm:lower()
    if r:find("hardcore", 1, true) then return L["Hardcore"] end
    if r:find("pvp%d*$") then return L["PvP"] end
    if r:find("rp%d*$") or r:find("roleplay", 1, true) then return L["Roleplaying"] end
    if r:find("pve%d*$") or r:find("normal", 1, true) then return L["Normal"] end
    return realm
end

-- Two realms with the same ruleset (the beta has "ClassicBetaPvE" and "...PvE2") are
-- told apart by their realm names.
function ns.RulesetLabel(realm)
    if not realm then return L["Not sorted yet (log in on them once)"] end
    local base = RulesetBase(realm)
    if base == realm then return realm end
    for _, c in pairs(ns.db.chars) do
        if c.realm and c.realm ~= realm and RulesetBase(c.realm) == base then
            return base .. " (" .. realm .. ")"
        end
    end
    return base
end

-- What tells your characters' groups apart: rulesets once two are known, factions once
-- both are played. Neither: one group, no headings.
function ns.GroupParts()
    local realm, faction, byRealm, byFaction
    for _, c in pairs(ns.db.chars) do
        if c.realm then
            if realm and realm ~= c.realm then byRealm = true end
            realm = c.realm
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
    return (byRealm and (c.realm or "?") or "") .. "|" .. (byFaction and (c.faction or "?") or "")
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

-- On a live realm: forgets every character from the beta, before this one is set up (a
-- namesake from the beta is a different character, so you start fresh), with the beta's gold
-- history and Legacy points (the saved pool never shrinks, so every live character would be
-- told it had the beta's points to spend). Characters not logged in since realms were recorded
-- (0.12.0) go too once the file shows it's from the beta: they were on it. Settings stay.
-- Returns how many went; after the first live login there are none, so it's one pass at login.
function ns.LeaveBeta(db, realm)
    if not realm or ns.BetaRealm(realm) then return 0 end
    local chars, unknown, gone = db.chars, {}, 0
    for key, c in pairs(chars) do
        if ns.BetaRealm(c.realm) then
            chars[key], gone = nil, gone + 1
        elseif c.realm == nil then
            unknown[#unknown + 1] = key
        end
    end
    if gone == 0 then return 0 end
    for _, key in ipairs(unknown) do chars[key] = nil end
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
    return gone + #unknown
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
    c.name, c.class, c.faction = name, class, faction
    if realm then
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
    -- Before login, so EllesmereUI's minimap finds it when it collects addon buttons.
    ns.CreateMinimapButton()
end)

ns.On("PLAYER_LOGIN", function()
    ns.Off("PLAYER_LOGIN")
    local _, class = UnitClass("player")
    local name = ns.PlayerName()
    ns.AdoptFirstName(ns.db.chars, name, class)
    local betaGone = ns.LeaveBeta(ns.db, ns.PlayerRealm())
    local newChar = ns.db.chars[name] == nil
    ns.charKey, ns.char = ns.InitChar(ns.db, name, class, UnitFactionGroup("player"), ns.PlayerRealm())
    ns.StartScanner()
    ns.StartMail()
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
    ns.StartOptions()
    ns.StartBroker()
    ns.StartGamepad()
    ns.StartItemNames()
    ns.Welcome(newChar, betaGone)
end)

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

function commands.counts()
    ns.SetCounts(not ns.CountsOn())
    Print(ns.CountsOn() and L["Item counts in tooltips on."] or L["Item counts in tooltips off."])
end

function commands.skillups()
    ns.SetSkillups(not ns.SkillupsOn())
    Print(ns.db.skillupsOff and L["Skill-up details in tooltips off."] or L["Skill-up details in tooltips on."])
end

function commands.rulesets()
    ns.SetOtherRulesets(not ns.OtherRulesetsOn())
    Print(ns.OtherRulesetsOn() and L["Characters on other rulesets or factions are shown in tooltips."]
        or L["Characters on other rulesets or factions are hidden in tooltips."])
end

-- /af itemnames: item names and qualities in the saved file, for reading it outside the game.
function commands.itemnames()
    ns.SetItemNames(not ns.ItemNamesOn())
    Print(ns.ItemNamesOn() and L["Item names will be saved in Alts Forever's saved file when you log out. They're only for reading the file outside the game: Alts Forever doesn't need them."]
        or L["Item names are no longer saved."])
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
    Print(ns.UpgradesOn() and L["Upgrades in item tooltips on."] or L["Upgrades in item tooltips off."])
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
    if not key then return Print(L["Type /af role, a character's name and a role: melee, ranged, caster, healer, tank, feral, or auto to follow their talents."]) end
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

function commands.minimap()
    ns.SetMinimapButton(not ns.MinimapButtonOn())
    Print(ns.MinimapButtonOn() and L["Minimap button shown."] or L["Minimap button hidden. /af minimap brings it back."])
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

function commands.rep()
    ns.ToggleReputation()
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
    Print(L["/af search (or /afs), with or without a name, finds an item on any of your characters, or who can craft it."])
    Print(L["/af counts turns the item counts in tooltips on or off (if another addon, such as Baganator, already shows them)."])
    Print(L["/af bags or /af bank, with a name for another character, shows their bags or bank slot by slot."])
    Print(L["/af icons picks the icons item tooltips use for bags, bank, mail and worn items."])
    Print(L["/af upgrades turns upgrade hints in item tooltips on or off. /af role Name role sets what a character's upgrades are judged by (melee, ranged, caster, healer, tank, feral or auto)."])
    Print(L["/af itemnames turns saving item names in Alts Forever's saved file on or off (only for reading it outside the game)."])
    Print(L["/af anvils shows or hides the anvils on your character sheet that mark upgrades you or your alts can craft."])
    Print(L["/af scale 150 makes Alts Forever's windows one and a half times their size (any size from 50 to 300), on top of the game's UI scale."])
    if ns.HasEllesmereScale() then Print(L["/af scale eui makes them follow EllesmereUI's Window Scale again (the default)."]) end
    Print(L["/af legacy lists each character's Legacy points to spend and Well Rested rank; /af legacy on or off turns the reminders on or off."])
    Print(L["/af rulesets shows or hides your characters on other rulesets (Normal, PvP...) or the other faction in tooltips; they can't trade with this one."])
    Print(L["Or use the minimap button (right-click for options)."])
end
ns.ShowHelp = commands.help

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
