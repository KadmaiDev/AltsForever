-- Alts Forever crates: Waylaid Crates (Merchant's Favor) list the bundles that fill them
-- in their own tooltip, one "- 20 Soul Dust" per line under the Use: line (checked in
-- game 2026-10-12, item 248689: all in one tooltip line, separated by line breaks). Under
-- them, a grid: one column per material (headed by its icon, in the crate's order),
-- the amount needed, a row per character who has any, and the total, in green when your
-- characters have enough between them. Only characters you can mail are counted.
--
-- Only item IDs are stored, so the materials are matched by name: the names of items
-- your characters own are looked up when a crate is first hovered and kept (lower-case
-- name -> item ID), and only items not looked up yet are checked after that. A material
-- nobody owns doesn't need an ID: its total is 0.
local _, ns = ...
if ns.disabled then return end -- another copy of Alts Forever is running (Core.lua)
local L = ns.L

local pairs, ipairs, type, wipe, tonumber, sort, pcall = pairs, ipairs, type, wipe, tonumber, table.sort, pcall
local issecretvalue = issecretvalue or function() return false end
local GetItemNameByID = C_Item.GetItemNameByID

local LOCS = { "bags", "bank", "mail", "equip" }
local USE = ITEM_SPELL_TRIGGER_ONUSE or "Use:"
local MAX_ROWS = 10 -- characters; more are counted in the totals and a "+n more" row
local GREY, DIM, ENOUGH = "|cffe0e0e0", "|cff9d9d9d", "|cff20ff20"
local NO_LABELS = {}
local CROP = ":0:0:0:0:64:64:5:59:5:59|t"

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
-- The grid: rows of { left, cell per material }, and each row's plain text (shown as it
-- is if the columns can't be measured). Rebuilt when the item, the counts (ns.version)
-- or a newly loaded name change; otherwise repeat hovers reuse it.
---------------------------------------------------------------------------
local rows, plain = {}, {}
local lastId, lastVer, lastMissing = nil, nil, false

local function ByCount(a, b)
    if a.you ~= b.you then return a.you end
    if a.sum ~= b.sum then return a.sum > b.sum end
    return a.key < b.key
end

local function Icon(id)
    local icon = id and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
    if icon and not issecretvalue(icon) then return "|T" .. icon .. CROP end
    return DIM .. "?|r"
end

local function Build(p)
    local chars, n = ns.db.chars, #p
    local header, need, totals = { L["Materials on your characters"] }, { DIM .. L["Needed"] .. "|r" }, { L["Total"] }
    local by, list = {}, {}
    for i, b in ipairs(p) do
        header[i + 1] = Icon(b.id)
        need[i + 1] = DIM .. b.qty .. "|r"
        local total = 0
        if b.id then
            for key, c in pairs(chars) do
                -- Only characters you can mail: another ruleset or faction can't help.
                local have = not ns.Elsewhere(c) and ns.Describe(c, b.id) or 0
                if have > 0 then
                    local e = by[key]
                    if not e then
                        e = { key = key, c = c, sum = 0, you = key == ns.charKey }
                        by[key] = e
                        list[#list + 1] = e
                    end
                    e[i], e.sum = have, e.sum + have
                    total = total + have
                end
            end
        end
        totals[i + 1] = total == 0 and (DIM .. "0|r") or total >= b.qty and (ENOUGH .. total .. "|r") or tostring(total)
    end
    sort(list, ByCount)
    -- New tables: a tooltip still showing the previous grid keeps its own.
    rows, plain = { header, need }, {}
    for j = 1, math.min(#list, MAX_ROWS) do
        local e = list[j]
        local row = { ns.ShortName(e.key, e.c) }
        for i = 1, n do row[i + 1] = e[i] and (GREY .. e[i] .. "|r") or (DIM .. "-|r") end
        rows[#rows + 1] = row
    end
    if #list > MAX_ROWS then
        local row = { DIM .. L["+%d more"]:format(#list - MAX_ROWS) .. "|r" }
        for i = 1, n do row[i + 1] = "" end
        rows[#rows + 1] = row
    end
    rows[#rows + 1] = totals
    for r, row in ipairs(rows) do
        local text = ""
        for i = 2, #row do text = text .. (i > 2 and "  " or "") .. row[i] end
        plain[r] = text
    end
end

-- Where each tooltip's grid is, so it can be lined up again once the tooltip is shown in
-- its final font (UI addons such as EllesmereUI set theirs on show).
local shownFirst, shownRows, hooked, reshowing = {}, {}, {}, {}

local function OnShow(tt)
    local first = shownFirst[tt]
    if not first or reshowing[tt] or tt:IsForbidden() then return end
    if ns.AlignColumns(tt, first, shownRows[tt], NO_LABELS, nil, "crate") then
        reshowing[tt] = true
        pcall(tt.Show, tt)
        reshowing[tt] = nil
    end
end

local function OnCleared(tt) shownFirst[tt], shownRows[tt] = nil, nil end

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
    local first = tt.NumLines and tt:NumLines() + 1
    for r, row in ipairs(rows) do
        if r == 1 then
            tt:AddDoubleLine(row[1], plain[r], 1, 0.82, 0, 1, 1, 1)
        else
            tt:AddDoubleLine(row[1], plain[r], 1, 1, 1, 1, 1, 1)
        end
    end
    if not first then return end
    if not hooked[tt] and tt.HookScript then
        hooked[tt] = true
        tt:HookScript("OnShow", OnShow)
        tt:HookScript("OnTooltipCleared", OnCleared)
    end
    shownFirst[tt], shownRows[tt] = first, rows
    ns.AlignColumns(tt, first, rows, NO_LABELS, nil, "crate")
end
