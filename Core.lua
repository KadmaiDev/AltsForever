-- Alts Forever core: saved data, character identity, event dispatch, slash commands.
local ADDON, ns = ...

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
    if name ~= ADDON then return end
    ns.Off("ADDON_LOADED")
    AltsForeverDB = ns.InitDB(AltsForeverDB)
    ns.db = AltsForeverDB
    -- Left over from the rested XP rate check, which has been removed.
    ns.db.restedChecks, ns.db.restCheckOff = nil, nil
end)

ns.On("PLAYER_LOGIN", function()
    ns.Off("PLAYER_LOGIN")
    local _, class = UnitClass("player")
    local name = ns.PlayerName()
    ns.AdoptFirstName(ns.db.chars, name, class)
    ns.charKey, ns.char = ns.InitChar(ns.db, name, class, UnitFactionGroup("player"))
    ns.StartScanner()
    ns.StartMail()
    ns.StartMoney()
    ns.StartProfessions()
    ns.StartCharacter()
    ns.StartOverview()
    ns.StartGear()
    ns.StartTooltip()
end)

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
        Print(key .. (c.bank and "" or "  (bank not scanned)"))
    end
end

function commands.delete(arg)
    local key = arg ~= "" and FindChar(arg)
    if not key then return Print("No character named '" .. arg .. "'. Use /af list.") end
    if key == ns.charKey then return Print("You can't delete the character you're logged in on.") end
    ns.db.chars[key] = nil
    ns.InvalidateCache()
    Print("Deleted " .. key .. ".")
end

function commands.mail()
    -- Everyone with mail on record, however far off it expires.
    if not ns.PrintMailWarnings(math.huge) then Print("No mail with items or gold on record.") end
end

function commands.skillups()
    ns.db.skillupsOff = not ns.db.skillupsOff or nil
    ns.InvalidateCache()
    Print(ns.db.skillupsOff and "Skill-up details in tooltips off." or "Skill-up details in tooltips on.")
end

function commands.mem()
    UpdateAddOnMemoryUsage()
    Print(("Memory: %.1f KB"):format(GetAddOnMemoryUsage(ADDON)))
end

function commands.help()
    Print("by Kadmai. /af opens the overview. Also: /af mail | list | delete Name | skillups | mem")
end

commands[""] = function() ns.ToggleOverview() end

SLASH_ALTSFOREVER1, SLASH_ALTSFOREVER2 = "/af", "/altsforever"
SlashCmdList.ALTSFOREVER = function(msg)
    local cmd, arg = msg:match("^%s*(%S*)%s*(.-)%s*$")
    local fn = commands[cmd:lower()] or commands.help
    fn(arg)
end
