-- Memory and garbage measurements, run outside the game against the fake API.
-- From the addon folder:  luajit tests/perf.lua [path to a saved AltsForever.lua]
-- LuaJIT's numbers are close to, not the same as, WoW's Lua 5.1; use /af mem in game
-- for the real figure.
package.path = "tests/?.lua;" .. package.path
local wow = require("wow")
local SAVED = arg[1] or "tests/fixtures/AltsForever.lua"
local FILES = { "Core.lua", "Scanner.lua", "Mail.lua", "Money.lua", "Professions.lua", "Character.lua", "Overview.lua", "Gear.lua", "Tooltip.lua", "Options.lua", "Reputation.lua" }

local function out(fmt, ...) io.write(fmt:format(...), "\n") end
local function settle()
    collectgarbage("collect")
    collectgarbage("collect")
    return collectgarbage("count")
end

-- Bytes of garbage per call of fn, averaged over n calls, with the collector stopped.
local function garbage(name, n, fn)
    fn(1) -- warm caches
    settle()
    collectgarbage("stop")
    local before = collectgarbage("count")
    for i = 1, n do fn(i) end
    local used = (collectgarbage("count") - before) * 1024 / n
    collectgarbage("restart")
    out("  %-44s %6.0f bytes/call", name, used)
end

local function count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end

-- A full backpack: 5 bags of 16 slots, 80 different items.
local function backpack()
    for bag = 0, 4 do
        local contents = {}
        for slot = 1, 16 do contents[slot] = { 2000 + bag * 16 + slot, slot } end
        wow.setBag(bag, 16, contents)
    end
end

-- Loads the addon into an already set-up fake API and returns the memory it added.
-- Measuring inside one load keeps the fake API's own leftovers out of the numbers.
local function measure(withSaved)
    wow.load({})
    backpack()
    local before = settle()
    local ns = {}
    if withSaved then assert(loadfile(SAVED))() end
    for _, file in ipairs(FILES) do assert(loadfile(file))("AltsForever", ns) end
    local anyone = withSaved and next(AltsForeverDB.chars)
    wow.player.name = anyone and (AltsForeverDB.chars[anyone].name or anyone:gsub("%-.*$", "")) or "Aldric"
    wow.fire("ADDON_LOADED", "AltsForever")
    wow.fire("PLAYER_LOGIN")
    return settle() - before, ns
end

-- LuaJIT grows its internal tables in big steps, so single readings jump by 10-30 KB.
-- Take several and report the median and range.
local function median(list)
    table.sort(list)
    return list[(#list + 1) / 2 - ((#list + 1) / 2) % 1], list[1], list[#list]
end
local codes, totals = {}, {}
measure(true) -- warm up
for i = 1, 9 do
    codes[i] = measure(false)
    totals[i] = measure(true)
end
local _, ns = measure(true)
local f = assert(io.open(SAVED, "rb"))
local fileSize = #f:read("*a")
f:close()

out("Memory (median of 9, with range; /af mem in game is the real figure)")
out("  addon, logged in with a full backpack:  %6.1f KB  (%.0f-%.0f)", median(codes))
out("  addon plus the saved data:              %6.1f KB  (%.0f-%.0f)  %d characters, %.1f KB on disk",
    select(1, median(totals)), select(2, median(totals)), select(3, median(totals)),
    count(AltsForeverDB.chars), fileSize / 1024)

out("")
out("Garbage per call (only allocations by the addon itself)")
-- The fake API allocates in places the real one may not; make those free first.
C_Item.GetItemInfoInstant = function(id) return id, nil, nil, nil, 1, wow.itemClass[id] end
local nop = { AddLine = function() end, AddDoubleLine = function() end, NumLines = function() return 0 end }
local item = 2017
garbage("tooltip: item already hovered", 5000, function()
    ns.AddRecipeLines(nop, item) ns.AddCraftLines(nop, item) ns.AddSkillupLines(nop, item) ns.AddLines(nop, item)
end)
local ids = {}
for id in pairs(ns.char.bags) do ids[#ids + 1] = id end
garbage("tooltip: item hovered for the first time", #ids, function(i) ns.AddLines(nop, ids[i]) end)
garbage("bag scan, 80 slots", 500, function() wow.fire("BAG_UPDATE", 0) wow.fire("BAG_UPDATE_DELAYED") end)
garbage("XP gained (stats update)", 5000, function() wow.fire("PLAYER_XP_UPDATE") end)
garbage("durability changed (gear scan)", 5000, function() wow.fire("UPDATE_INVENTORY_DURABILITY") end)
garbage("money changed, overview closed", 5000, function() wow.fire("PLAYER_MONEY") end)
SlashCmdList.ALTSFOREVER("")
garbage("money changed, overview open", 500, function() wow.fire("PLAYER_MONEY") end)
