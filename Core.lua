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

function ns.InitDB(saved)
    if type(saved) == "table" then Upgrade(saved) end
    if type(saved) ~= "table" or saved.v ~= DB_VERSION or type(saved.chars) ~= "table" then
        saved = { v = DB_VERSION, chars = {} }
    end
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

-- The ruleset's name from the realm name the client reports, in the player's language;
-- a realm name that doesn't say is shown as it is.
local function RulesetBase(realm)
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
-- characters don't carry over to the live game (owner, 2026-10-23: aiming 1.0.0 at launch).
-- A saved file from the beta still lists them, so the first login on a live realm offers to
-- forget them (Options.lua, ns.CheckBeta); nothing goes without the player's say-so.
---------------------------------------------------------------------------
function ns.BetaRealm(realm)
    return type(realm) == "string" and realm:lower():find("^classicbeta") ~= nil
end

-- Logged in on a live realm as a character whose saved entry is from the beta: the same name,
-- but a new character, so it starts fresh. The beta one is kept aside as "Name (beta)" with
-- the other beta characters, until the player forgets them.
function ns.SetAsideBeta(chars, name, realm)
    local old = chars[name]
    if not realm or ns.BetaRealm(realm) or type(old) ~= "table" or not ns.BetaRealm(old.realm) then return end
    local aside = name .. " (beta)"
    old.name = aside
    chars[aside], chars[name] = old, nil
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
    if realm then c.realm = realm end
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
    ns.SetAsideBeta(ns.db.chars, name, ns.PlayerRealm())
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
    ns.Welcome(newChar)
    ns.CheckBeta()
end)

-- A few seconds after login (after the game's own login messages): on a fresh install,
-- how to use Alts Forever, once; on a character seen for the first time, that it's now
-- tracked. Existing players never see the welcome (db.welcomed is set quietly).
function ns.Welcome(newChar)
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

-- /af forgetbeta: forgets the characters from the beta (only from a live realm).
function commands.forgetbeta()
    if ns.BetaRealm(ns.char.realm) then return Print(L["You're on the beta, so there's nothing to forget yet."]) end
    local n = ns.ForgetBeta()
    Print(n > 0 and L["Forgot your characters from the beta (%d)."]:format(n) or L["No characters from the beta to forget."])
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

-- /af names: item names and qualities in the saved file, for reading it outside the game.
function commands.names()
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
    Print(L["/af names turns saving item names in Alts Forever's saved file on or off (only for reading it outside the game)."])
    Print(L["/af anvils shows or hides the anvils on your character sheet that mark upgrades you or your alts can craft."])
    Print(L["/af scale 150 makes Alts Forever's windows one and a half times their size (any size from 50 to 300), on top of the game's UI scale."])
    if ns.HasEllesmereScale() then Print(L["/af scale eui makes them follow EllesmereUI's Window Scale again (the default)."]) end
    Print(L["/af legacy lists each character's Legacy points to spend and Well Rested rank; /af legacy on or off turns the reminders on or off."])
    Print(L["/af forgetbeta forgets your characters from the beta, which aren't in the live game."])
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
