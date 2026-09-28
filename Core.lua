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

-- Bank and mail stay nil until first seen, so "never scanned" differs from "empty".
-- Characters are keyed by full name ("First Last"), which is unique in a region.
function ns.InitChar(db, name, class, faction)
    local key = name
    local c = db.chars[key]
    if type(c) ~= "table" then
        c = {}
        db.chars[key] = c
    end
    c.name, c.class, c.faction = name, class, faction
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
    local newChar = ns.db.chars[name] == nil
    ns.charKey, ns.char = ns.InitChar(ns.db, name, class, UnitFactionGroup("player"))
    ns.StartScanner()
    ns.StartMail()
    ns.StartMoney()
    ns.StartProfessions()
    ns.StartCharacter()
    ns.StartOverview()
    ns.StartBars()
    ns.StartGear()
    ns.StartBags()
    ns.StartTooltip()
    ns.StartReputation()
    ns.StartOptions()
    ns.Welcome(newChar)
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

function commands.mail()
    -- Everyone with mail on record, however far off it expires.
    if not ns.PrintMailWarnings(math.huge) then Print(L["No mail with items or gold on record."]) end
end

function commands.skillups()
    ns.SetSkillups(not ns.SkillupsOn())
    Print(ns.db.skillupsOff and L["Skill-up details in tooltips off."] or L["Skill-up details in tooltips on."])
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

function commands.find(arg)
    ns.FindItems(arg)
end

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

function commands.mem()
    UpdateAddOnMemoryUsage()
    Print(L["Memory: %.1f KB"]:format(GetAddOnMemoryUsage(ADDON)))
end

function commands.help()
    Print(L["by Kadmai. /af opens the overview. Also: /af rep | mail | list | delete Name | skillups | sendmail | minimap | stats | mem"])
    Print(L["/af find <text> searches every character's items by name."])
    Print(L["/af bags or /af bank, with a name for another character, shows their bags or bank slot by slot."])
    Print(L["/af icons picks the icons item tooltips use for bags, bank, mail and worn items."])
    Print(L["Or use the minimap button (right-click for options)."])
end
ns.ShowHelp = commands.help

-- For the menus: runs a slash command by name.
function ns.RunCommand(name, arg)
    commands[name](arg or "")
end

commands[""] = function() ns.ToggleOverview() end

SLASH_ALTSFOREVER1, SLASH_ALTSFOREVER2 = "/af", "/altsforever"
SlashCmdList.ALTSFOREVER = function(msg)
    local cmd, arg = msg:match("^%s*(%S*)%s*(.-)%s*$")
    local fn = commands[cmd:lower()] or commands.help
    fn(arg)
end
