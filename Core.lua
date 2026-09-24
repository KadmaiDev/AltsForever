-- Alts Forever core: saved data, character identity, event dispatch, slash commands.
local ADDON, ns = ...

local DB_VERSION = 1

local pcall, type, pairs, print, time = pcall, type, pairs, print, time
local UnitName, UnitClass, UnitFactionGroup = UnitName, UnitClass, UnitFactionGroup
local GetNormalizedRealmName, GetRealmName = GetNormalizedRealmName, GetRealmName

-- Bumped whenever the current character's data changes; the tooltip uses it to
-- know when its cached line for the current character is stale.
ns.version = 0

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
function ns.InitDB(saved)
    if type(saved) ~= "table" or saved.v ~= DB_VERSION or type(saved.chars) ~= "table" then
        saved = { v = DB_VERSION, chars = {} }
    end
    return saved
end

-- Bank and mail stay nil until first seen, so "never scanned" differs from "empty".
function ns.InitChar(db, name, realm, class, faction)
    local key = name .. "-" .. realm
    local c = db.chars[key]
    if type(c) ~= "table" then
        c = {}
        db.chars[key] = c
    end
    c.name, c.realm, c.class, c.faction = name, realm, class, faction
    c.bags = c.bags or {}
    c.equip = c.equip or {}
    return key, c
end

ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    ns.Off("ADDON_LOADED")
    -- On the Forever beta the client never loads this; the .toc loads it from the
    -- SavedData link instead (see tools\link-saved-data.ps1).
    AltsForeverDB = ns.InitDB(AltsForeverDB)
    ns.db = AltsForeverDB
end)

ns.On("PLAYER_LOGIN", function()
    ns.Off("PLAYER_LOGIN")
    local _, class = UnitClass("player")
    ns.realm = GetNormalizedRealmName() or GetRealmName():gsub("[%s%-]", "")
    ns.charKey, ns.char = ns.InitChar(ns.db, UnitName("player"), ns.realm, class, UnitFactionGroup("player"))
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

-- Finds a stored character by "Name-Realm", ignoring case.
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

function commands.realm()
    ns.db.realmOnly = not ns.db.realmOnly or nil
    ns.InvalidateCache()
    Print(ns.db.realmOnly and "Showing characters on this realm only." or "Showing characters on all realms.")
end

function commands.mail()
    -- Everyone with mail on record, however far off it expires.
    if not ns.PrintMailWarnings(math.huge) then Print("No mail with items or gold on record.") end
end

function commands.restcheck()
    ns.db.restCheckOff = not ns.db.restCheckOff or nil
    Print(ns.db.restCheckOff and "Rested XP check messages off (results are still saved)."
        or "Rested XP check messages on.")
end

function commands.mem()
    UpdateAddOnMemoryUsage()
    Print(("Memory: %.1f KB"):format(GetAddOnMemoryUsage(ADDON)))
end

function commands.help()
    Print("by Kadmai. /af opens the overview. Also: /af mail | list | delete Name-Realm | realm | mem")
end

commands[""] = function() ns.ToggleOverview() end

-- /it is kept from when the addon was called ItemTracker.
SLASH_ALTSFOREVER1, SLASH_ALTSFOREVER2, SLASH_ALTSFOREVER3 = "/af", "/altsforever", "/it"
SlashCmdList.ALTSFOREVER = function(msg)
    local cmd, arg = msg:match("^%s*(%S*)%s*(.-)%s*$")
    local fn = commands[cmd:lower()] or commands.help
    fn(arg)
end
