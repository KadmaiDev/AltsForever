-- Alts Forever crates: Waylaid Crates (Merchant's Favor) list the bundles that fill them
-- in their own tooltip, one "- 20 Soul Dust" per line under the Use: line (checked in
-- game 2026-10-12, item 248689: all in one tooltip line, separated by line breaks). Under
-- them we list how many of each material your characters have between them, and who to
-- get them from: just the characters needed to make up the bundle.
--
-- Only item IDs are stored, so the materials are matched by name: the names of items
-- your characters own are looked up when a crate is first hovered and kept (lower-case
-- name -> item ID), and only items not looked up yet are checked after that. A material
-- nobody owns doesn't need an ID: its total is 0.
local _, ns = ...
if ns.disabled then return end -- another copy of Alts Forever is running (Core.lua)
local L = ns.L

local pairs, ipairs, type, wipe, tonumber, sort = pairs, ipairs, type, wipe, tonumber, table.sort
local issecretvalue = issecretvalue or function() return false end
local GetItemNameByID = C_Item.GetItemNameByID

local LOCS = { "bags", "bank", "mail", "equip" }
local USE = ITEM_SPELL_TRIGGER_ONUSE or "Use:"
local MAX_NAMES = 3
local GREY, DIM, ENOUGH = "|cffe0e0e0", "|cff9d9d9d", "|cff20ff20"
local SEP = " · "

---------------------------------------------------------------------------
-- The crate's bundles, parsed once per item: { { qty, name, lname, id } ... } or false.
---------------------------------------------------------------------------
local parsed, parsedCount = {}, 0

local function LineText(tt, data, i)
    local line = data and data.lines and data.lines[i]
    local text
    if line then
        text = line.leftText
    elseif not (data and data.lines) then
        local fs = tt.GetName and tt:GetName() and _G[tt:GetName() .. "TextLeft" .. i]
        text = fs and fs:GetText()
    end
    if type(text) ~= "string" or issecretvalue(text) then return nil end
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Whether a tooltip without a bundle list is the whole story. An item the game hasn't
-- loaded (often the case in the auction house) first shows a partial tooltip, and its
-- Use: line can come a moment later; remembering "no list" then would hide the crate's
-- lines for the session.
local function Complete(id, sawUse)
    if C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(id) then return false end
    if sawUse then return true end
    return not (C_Item.GetItemSpell and C_Item.GetItemSpell(id))
end

local function Parse(tt, id, data)
    local p = parsed[id]
    if p ~= nil then return p end
    p = false
    local n = data and data.lines and #data.lines or (tt.NumLines and tt:NumLines()) or 0
    local inUse = false
    for i = 1, n do
        local text = LineText(tt, data, i)
        if text then
            if not inUse and text:find(USE, 1, true) == 1 then inUse = true end
            if inUse then
                local found = false
                for qty, name in ("\n" .. text):gmatch("\n%s*%-%s*(%d+)%s+([^\n]+)") do
                    name = name:match("^(.-)%s*$")
                    p = p or {}
                    p[#p + 1] = { qty = tonumber(qty), name = name, lname = name:lower() }
                    found = true
                end
                if p and not found then break end -- past the list
            end
        end
    end
    if not p and not Complete(id, inUse) then return false end -- read again next time
    if parsedCount >= 200 then
        wipe(parsed)
        parsedCount = 0
    end
    parsed[id] = p
    parsedCount = parsedCount + 1
    return p
end

---------------------------------------------------------------------------
-- Names of the items your characters own: lower-case name -> item ID.
---------------------------------------------------------------------------
local index, indexed = {}, {}
local indexVer, pending

local function Index()
    if indexVer == ns.version and not pending then return end
    indexVer, pending = ns.version, false
    for _, c in pairs(ns.db.chars) do
        for i = 1, #LOCS do
            local t = c[LOCS[i]]
            if t then
                for id in pairs(t) do
                    if not indexed[id] then
                        local name = GetItemNameByID(id)
                        if type(name) == "string" and name ~= "" and not issecretvalue(name) then
                            indexed[id] = true
                            index[name:lower()] = id
                        else
                            -- Not loaded yet: asked for, and looked up again next hover.
                            pending = true
                            if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
                        end
                    end
                end
            end
        end
    end
end

-- Fills in the bundles' item IDs; true if one is still unknown.
local function Resolve(p)
    local missing = false
    for _, b in ipairs(p) do
        if not b.id then
            b.id = index[b.lname]
            if not b.id then missing = true end
        end
    end
    return missing
end

---------------------------------------------------------------------------
-- The lines: one per bundle, rebuilt when the item, the counts (ns.version) or a newly
-- loaded name change; otherwise repeat hovers reuse them.
---------------------------------------------------------------------------
local lefts, rights = {}, {}
local lastId, lastVer, lastMissing, count = nil, nil, false, 0

local function ByCount(a, b)
    if a.you ~= b.you then return a.you end
    if a.n ~= b.n then return a.n > b.n end
    return a.key < b.key
end

local function Build(p)
    count = #p
    local chars = ns.db.chars
    for i, b in ipairs(p) do
        local list, total = {}, 0
        if b.id then
            for key, c in pairs(chars) do
                -- Only your ruleset: materials can't be mailed between rulesets.
                local n = not ns.Elsewhere(c) and ns.Describe(c, b.id) or 0
                if n > 0 then
                    list[#list + 1] = { key = key, c = c, n = n, you = key == ns.charKey }
                    total = total + n
                end
            end
            sort(list, ByCount)
        end
        -- Only the characters needed to fill it (who to mail from): you first, then the
        -- most, until there's enough; at most MAX_NAMES, then how many more have some.
        local who, have, shown = nil, 0, 0
        for j = 1, #list do
            if have >= b.qty or shown == MAX_NAMES then break end
            local e = list[j]
            local part = ns.ShortName(e.key, e.c) .. " " .. GREY .. e.n .. "|r"
            who = who and (who .. SEP .. part) or part
            have, shown = have + e.n, shown + 1
        end
        if have < b.qty and #list > shown then
            who = who .. GREY .. SEP .. L["+%d more"]:format(#list - shown) .. "|r"
        end
        local sum = total == 0 and (DIM .. "0|r") or total >= b.qty and (ENOUGH .. total .. "|r") or tostring(total)
        lefts[i] = (total >= b.qty and "" or GREY) .. b.qty .. " " .. b.name .. (total >= b.qty and "" or "|r")
        rights[i] = who and (who .. "    " .. sum) or sum
    end
end

function ns.AddCrateLines(tt, id, data)
    local p = Parse(tt, id, data)
    if not p then return end
    if id ~= lastId or ns.version ~= lastVer or lastMissing then
        local missing = Resolve(p)
        if missing then
            Index()
            missing = Resolve(p)
        end
        lastId, lastVer, lastMissing = id, ns.version, missing and pending
        Build(p)
    end
    tt:AddLine(" ")
    tt:AddLine(L["Materials on your characters"], 1, 0.82, 0)
    for i = 1, count do
        tt:AddDoubleLine(lefts[i], rights[i], 1, 1, 1, 1, 1, 1)
    end
end
