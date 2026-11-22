-- Alts Forever's public functions, for other addons (2026-11-22: the owner's own addon
-- Waysplained wanted the materials on alts for Waylaid Crates). The one global of ours
-- besides AltsForeverRunning and the saved data. Reading AltsForeverDB from outside would
-- copy its format and our reach rules, which change; this stays the same.
--
-- Rules for changing it: only ever add (a new function or a new field), never rename,
-- remove or change what something returns; bump API_VERSION with each addition, so a
-- caller can check `AltsForever.API_VERSION >= n` before using something added in n.
--
--   AltsForever.API_VERSION                                 -- 1
--   local total, characters = AltsForever.Count(itemID)
--     total: how many of the item your characters within mail's reach have, you included
--       (same ruleset and faction as the character you're on; anyone whose ruleset isn't
--       known yet counts), in bags, bank, mailbox and worn, as last seen. nil until the
--       player has logged in (PLAYER_LOGIN).
--     characters: a new list each call, yours to keep or change; only characters with any,
--       you first, then most first: { name = "First Last", you = true|nil, count, bags,
--       bank, mail, equip } (each place 0 when none).
--   AltsForever.DataVersion()
--     A number that changes whenever any count may have changed (a scan, mail sent to an
--     alt, a sync, a character forgotten): cache Count's answers until it does.
local ADDON, ns = ...
if ns.disabled then return end

local type, ipairs, pairs, sort, error = type, ipairs, pairs, table.sort, error

local api = {}
api.API_VERSION = 1

local PLACES = { "bags", "bank", "mail", "equip" }

local function Before(a, b)
    if a.you ~= b.you then return a.you == true end
    if a.count ~= b.count then return a.count > b.count end
    return a.name < b.name
end

function api.Count(itemID)
    if type(itemID) ~= "number" then error("AltsForever.Count: itemID must be a number", 2) end
    local db = ns.db
    if not (db and db.chars and ns.char) then return nil end
    local total, list = 0, {}
    for key, c in pairs(db.chars) do
        if type(c) == "table" and not ns.Elsewhere(c) then
            local e
            for _, place in ipairs(PLACES) do
                local t = c[place]
                local n = type(t) == "table" and t[itemID]
                if type(n) == "number" and n > 0 then
                    e = e or { name = key, you = c == ns.char or nil, count = 0, bags = 0, bank = 0, mail = 0, equip = 0 }
                    e[place] = n
                    e.count = e.count + n
                end
            end
            if e then
                total = total + e.count
                list[#list + 1] = e
            end
        end
    end
    sort(list, Before)
    return total, list
end

function api.DataVersion() return ns.version end

AltsForever = api
