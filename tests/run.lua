-- Test runner. From the addon folder: luajit tests/run.lua
package.path = "tests/?.lua;" .. package.path
wow = require("wow")

FILES = { "Core.lua", "Scanner.lua", "Mail.lua", "Money.lua", "Professions.lua", "Character.lua", "Columns.lua", "Overview.lua", "Bars.lua", "Gear.lua", "Tooltip.lua", "Options.lua", "Reputation.lua", "Skin.lua" }
tests, passed, failed = {}, 0, 0

function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

function eq(actual, expected, msg)
    if actual ~= expected then
        error((msg or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

-- Right-hand text as the tooltip builds it: grey breakdown, then the count.
-- Tests write "Bags 12 · Bank 40"; the words are swapped for the real icons.
ICON = {
    Bags = "|T133652:0:0:0:0:64:64:5:59:5:59|t",
    Bank = "|TInterface\\Minimap\\Tracking\\Banker:0|t",
    Mail = "|TInterface\\Minimap\\Tracking\\Mailbox:0|t",
    Wearing = "|TInterface\\Icons\\INV_Shirt_White_01:0:0:0:0:64:64:5:59:5:59|t",
}
function R(breakdown, n)
    breakdown = breakdown:gsub("(%a+) ", function(word) return assert(ICON[word], word) .. " " end)
    return "|cffe0e0e0" .. breakdown .. "|r    " .. n
end

-- A saved character, in the stored shape.
function alt(name, class, data)
    data.name, data.class = name, class
    return data
end


-- The tests themselves, by area. Top-level helpers are shared between files, so no name
-- may be defined in two of them: checked before loading.
CASES = {
    "01_data.lua",
    "02_professions.lua",
    "03_overview.lua",
    "04_mail.lua",
    "05_gear.lua",
    "06_craft.lua",
    "07_names.lua",
    "08_skillups.lua",
    "09_options.lua",
    "10_reputation.lua",
    "11_send_to_alt.lua",
    "12_skins.lua",
    "13_bars.lua",
    "14_bags.lua",
    "15_stats.lua",
    "16_columns.lua",
    "17_minimap.lua",
    "18_toc.lua",
}
do
    local where = {}
    for _, file in ipairs(CASES) do
        for line in io.lines("tests/cases/" .. file) do
            local name = line:match("^function ([%w_]+)") or line:match("^([%a_][%w_]*) =")
            if name then
                assert(not where[name] or where[name] == file,
                    "helper '" .. name .. "' is defined in both " .. tostring(where[name]) .. " and " .. file)
                where[name] = file
            end
        end
    end
end
for _, file in ipairs(CASES) do
    assert(loadfile("tests/cases/" .. file))()
end

---------------------------------------------------------------------------
for _, t in ipairs(tests) do
    local ok, err = pcall(t.fn)
    if ok then
        passed = passed + 1
        io.write("  ok    ", t.name, "\n")
    else
        failed = failed + 1
        io.write("  FAIL  ", t.name, "\n        ", tostring(err), "\n")
    end
end
io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
