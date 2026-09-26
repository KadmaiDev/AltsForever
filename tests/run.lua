-- Test runner. From the addon folder: lua tests/run.lua
package.path = "tests/?.lua;" .. package.path
local wow = require("wow")

local FILES = { "Core.lua", "Scanner.lua", "Mail.lua", "Money.lua", "Professions.lua", "Character.lua", "Overview.lua", "Gear.lua", "Tooltip.lua", "Options.lua", "Reputation.lua", "Skin.lua" }
local tests, passed, failed = {}, 0, 0

local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

local function eq(actual, expected, msg)
    if actual ~= expected then
        error((msg or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

-- Right-hand text as the tooltip builds it: grey breakdown, then the count.
-- Tests write "Bags 12 · Bank 40"; the words are swapped for the real icons.
local ICON = {
    Bags = "|T133652:0:0:0:0:64:64:5:59:5:59|t",
    Bank = "|TInterface\\Minimap\\Tracking\\Banker:0|t",
    Mail = "|TInterface\\Minimap\\Tracking\\Mailbox:0|t",
    Wearing = "|TInterface\\Icons\\INV_Shirt_White_01:0:0:0:0:64:64:5:59:5:59|t",
}
local function R(breakdown, n)
    breakdown = breakdown:gsub("(%a+) ", function(word) return assert(ICON[word], word) .. " " end)
    return "|cffe0e0e0" .. breakdown .. "|r    " .. n
end

-- A saved character, in the stored shape.
local function alt(name, class, data)
    data.name, data.class = name, class
    return data
end

---------------------------------------------------------------------------
test("fresh install creates an empty database", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    eq(AltsForeverDB.v, 2)
    eq(ns.db, AltsForeverDB)
    eq(ns.charKey, "Aldric")
    eq(type(AltsForeverDB.chars["Aldric"].bags), "table")
end)

test("saved data from an older format is replaced, not crashed on", function()
    wow.load(FILES)
    wow.login({ v = 0, chars = "junk" })
    eq(AltsForeverDB.v, 2)
    eq(type(AltsForeverDB.chars), "table")
end)

test("version 1 data (Name-Realm keys) is upgraded to full-name keys", function()
    local ns = wow.load(FILES)
    wow.player.name = "Kadra Stormfield"
    wow.login({ v = 1, realmOnly = true, chars = {
        ["Kadra Stormfield-BetaRealm1"] = { name = "Kadra Stormfield", realm = "BetaRealm1",
            class = "HUNTER", bank = { [100] = 3 }, played = 500 },
        ["Brakka-BetaRealm1"] = { realm = "BetaRealm1", class = "WARRIOR", bank = { [100] = 7 } },
    } })
    eq(AltsForeverDB.v, 2)
    eq(AltsForeverDB.realmOnly, nil)
    eq(ns.charKey, "Kadra Stormfield")
    local c = AltsForeverDB.chars["Kadra Stormfield"]
    eq(c, ns.char, "you are matched to your upgraded entry, not a new one")
    eq(c.bank[100], 3); eq(c.played, 500); eq(c.realm, nil); eq(c.class, "MAGE")
    eq(AltsForeverDB.chars["Brakka"].bank[100], 7, "a name missing from the entry comes from its key")
    eq(AltsForeverDB.chars["Brakka"].name, "Brakka")
    local n = 0
    for _ in pairs(AltsForeverDB.chars) do n = n + 1 end
    eq(n, 2)
end)

test("upgrading two entries with one name keeps the most recently updated", function()
    wow.load(FILES)
    wow.login({ v = 1, chars = {
        ["Brakka-OldRealm"] = { name = "Brakka", realm = "OldRealm", class = "WARRIOR", updated = 100, money = 1 },
        ["Brakka-NewRealm"] = { name = "Brakka", realm = "NewRealm", class = "WARRIOR", updated = 200, money = 2 },
        ["Sorrel-OldRealm"] = { name = "Sorrel", realm = "OldRealm", class = "WARLOCK", seen = 300, money = 3 },
        ["Sorrel-NewRealm"] = { name = "Sorrel", realm = "NewRealm", class = "WARLOCK", updated = 50, money = 4 },
    } })
    eq(AltsForeverDB.chars["Brakka"].money, 2)
    eq(AltsForeverDB.chars["Sorrel"].money, 3, "falls back to when last seen")
end)

test("existing characters are kept on login", function()
    wow.load(FILES)
    wow.login({ v = 2, chars = { ["Alt"] = alt("Alt", "WARRIOR", { bags = { [100] = 3 } }) } })
    eq(AltsForeverDB.chars["Alt"].bags[100], 3)
end)

test("saved data loaded by the game before the addon is picked up at login", function()
    wow.load({ "tests/fixtures/AltsForever.lua", unpack(FILES) })
    wow.player.name, wow.player.realm = "Thessa Oakenbrook", "TestRealm"
    wow.setBag(0, 16, { [1] = { 6948, 1 } })
    wow.fire("ADDON_LOADED", "AltsForever")
    wow.fire("PLAYER_LOGIN")
    local lines = wow.hover(GameTooltip, 6948)
    eq(lines[2][2], 2)
    eq(lines[3][1], "[MAGE]Thessa Oakenbrook")
    eq(lines[4][1], "[PALADIN]Veyla Dawnmere")
end)

test("registering an unknown event returns false instead of throwing", function()
    local ns = wow.load(FILES)
    eq(ns.On("NOT_A_REAL_EVENT", function() end), false)
end)

---------------------------------------------------------------------------
test("bag scan sums stacks across bags, keyring and reagent bag", function()
    local ns = wow.load(FILES)
    wow.setBag(0, 16, { [1] = { 100, 20 }, [2] = { 100, 5 }, [3] = { 200, 1 } })
    wow.setBag(1, 10, { [4] = { 100, 10 } })
    wow.setBag(5, 20, { [1] = { 300, 40 } })
    wow.setBag(-2, 12, { [1] = { 400, 1 } })
    wow.login(nil)
    local bags = ns.char.bags
    eq(bags[100], 35)
    eq(bags[200], 1)
    eq(bags[300], 40)
    eq(bags[400], 1)
end)

test("rescans reuse the same table and drop items that left", function()
    local ns = wow.load(FILES)
    wow.setBag(0, 16, { [1] = { 100, 20 } })
    wow.login(nil)
    local before = ns.char.bags
    wow.setBag(0, 16, { [1] = { 200, 2 } })
    wow.fire("BAG_UPDATE", 0)
    wow.fire("BAG_UPDATE_DELAYED")
    eq(ns.char.bags, before, "same table")
    eq(ns.char.bags[100], nil)
    eq(ns.char.bags[200], 2)
end)

test("changes to bags we don't track don't trigger a rescan", function()
    local ns = wow.load(FILES)
    wow.setBag(0, 16, { [1] = { 100, 20 } })
    wow.login(nil)
    local ver = ns.version
    wow.fire("BAG_UPDATE", 9)
    wow.fire("BAG_UPDATE_DELAYED")
    eq(ns.version, ver)
end)

test("secret stack counts are never stored", function()
    local ns = wow.load(FILES)
    wow.setBag(0, 16, { [1] = { 100, wow.SECRET }, [2] = { 200, 3 } })
    wow.login(nil)
    eq(ns.char.bags[100], nil)
    eq(ns.char.bags[200], 3)
end)

test("equipped scan counts gear and equipped bags; two of the same ring count 2", function()
    local ns = wow.load(FILES)
    wow.inventory[11], wow.inventory[12] = 500, 500
    wow.inventory[1] = 600
    wow.inventory[31] = 700 -- Bag_1's inventory slot
    wow.login(nil)
    eq(ns.char.equip[500], 2)
    eq(ns.char.equip[600], 1)
    eq(ns.char.equip[700], 1)
    wow.inventory[1] = nil
    wow.fire("PLAYER_EQUIPMENT_CHANGED", 1)
    eq(ns.char.equip[600], nil)
end)

---------------------------------------------------------------------------
test("describe: one location shows just that location", function()
    local ns = wow.load(FILES)
    local total, text = ns.Describe({ bags = { [1] = 3 } }, 1)
    eq(total, 3)
    eq(text, R("Bags 3", 3))
end)

test("describe: several locations show the breakdown in fixed order, then the total", function()
    local ns = wow.load(FILES)
    local total, text = ns.Describe({ equip = { [1] = 1 }, bank = { [1] = 40 }, bags = { [1] = 12 } }, 1)
    eq(total, 53)
    eq(text, R("Bags 12 · Bank 40 · Wearing 1", 53))
end)

test("tooltip: total first, current character next, others by count", function()
    wow.load(FILES)
    wow.setBag(0, 16, { [1] = { 100, 2 } })
    wow.login({ v = 2, chars = {
        ["Small"] = alt("Small", "ROGUE", { bags = { [100] = 1 } }),
        ["Big"] = alt("Big", "PRIEST", { bags = { [100] = 30 }, mail = { [100] = 10 } }),
        ["Mid"] = alt("Mid", "DRUID", { bank = { [100] = 5 } }),
        ["None"] = alt("None", "MAGE", { bags = { [999] = 1 } }),
    } })
    local lines = wow.hover(GameTooltip, 100)
    eq(#lines, 6)
    eq(lines[1][1], " ", "spacer above our lines"); eq(lines[1][2], nil)
    eq(lines[2][1], "Total"); eq(lines[2][2], 48)
    eq(lines[3][1], "[MAGE]Aldric"); eq(lines[3][2], R("Bags 2", 2))
    eq(lines[4][1], "[PRIEST]Big"); eq(lines[4][2], R("Bags 30 · Mail 10", 40))
    eq(lines[5][1], "[DRUID]Mid"); eq(lines[5][2], R("Bank 5", 5))
    eq(lines[6][1], "[ROGUE]Small")
end)

test("tooltip: no total line when only one character has the item", function()
    wow.load(FILES)
    wow.setBag(0, 16, { [1] = { 100, 2 } })
    wow.login(nil)
    local lines = wow.hover(GameTooltip, 100)
    eq(#lines, 2)
    eq(lines[2][1], "[MAGE]Aldric")
end)

test("tooltip: nothing is added for items nobody has", function()
    wow.load(FILES)
    wow.login(nil)
    eq(#wow.hover(GameTooltip, 12345), 0)
end)

test("tooltip: current character's line updates after a bag change", function()
    wow.load(FILES)
    wow.setBag(0, 16, { [1] = { 100, 2 } })
    wow.login(nil)
    eq(wow.hover(GameTooltip, 100)[2][2], R("Bags 2", 2))
    wow.setBag(0, 16, { [1] = { 100, 7 } })
    wow.fire("BAG_UPDATE", 0)
    wow.fire("BAG_UPDATE_DELAYED")
    eq(wow.hover(GameTooltip, 100)[2][2], R("Bags 7", 7))
end)

test("tooltip: only the game and item-link tooltips are touched", function()
    wow.load(FILES)
    wow.setBag(0, 16, { [1] = { 100, 2 } })
    wow.login(nil)
    eq(#wow.hover(wow.tooltip(), 100), 0)
    eq(#wow.hover(ItemRefTooltip, 100), 2)
end)

test("tooltip: falls back to the item link when data has no id", function()
    wow.load(FILES)
    wow.setBag(0, 16, { [1] = { 100, 2 } })
    wow.login(nil)
    GameTooltip.link = "|cffffffff|Hitem:100::::|h[Thing]|h|r"
    GameTooltip.lines = {}
    wow.postCalls[1].fn(GameTooltip, {})
    eq(#GameTooltip.lines, 2)
end)

---------------------------------------------------------------------------
local function bagsChanged(bag)
    wow.fire("BAG_UPDATE", bag)
    wow.fire("BAG_UPDATE_DELAYED")
end

test("bank stays 'not scanned' until the bank is opened", function()
    local ns = wow.load(FILES)
    wow.setBag(6, 98, { [1] = { 100, 20 } })
    wow.login(nil)
    eq(ns.char.bank, nil)
end)

test("opening the bank scans every bank tab, not the bags", function()
    local ns = wow.load(FILES)
    wow.setBag(0, 16, { [1] = { 100, 1 } })
    wow.setBag(6, 98, { [1] = { 100, 20 } })
    wow.setBag(8, 98, { [5] = { 100, 3 }, [6] = { 200, 1 } })
    wow.login(nil)
    wow.fire("BANKFRAME_OPENED")
    eq(ns.char.bank[100], 23)
    eq(ns.char.bank[200], 1)
    eq(ns.char.bags[100], 1)
end)

test("moving items while the bank is open updates bank and bags", function()
    local ns = wow.load(FILES)
    wow.setBag(0, 16, {})
    wow.setBag(6, 98, { [1] = { 100, 20 } })
    wow.login(nil)
    wow.fire("BANKFRAME_OPENED")
    wow.setBag(6, 98, {})
    wow.setBag(0, 16, { [1] = { 100, 20 } })
    wow.fire("BAG_UPDATE", 6)
    wow.fire("BAG_UPDATE", 0)
    wow.fire("BAG_UPDATE_DELAYED")
    eq(ns.char.bank[100], nil)
    eq(ns.char.bags[100], 20)
end)

test("bank updates after closing the bank don't wipe what we saw", function()
    local ns = wow.load(FILES)
    wow.setBag(6, 98, { [1] = { 100, 20 } })
    wow.login(nil)
    wow.fire("BANKFRAME_OPENED")
    wow.fire("BANKFRAME_CLOSED")
    wow.setBag(6, 0, {})
    bagsChanged(6)
    eq(ns.char.bank[100], 20)
end)

test("tooltip shows bank alongside bags", function()
    wow.load(FILES)
    wow.setBag(0, 16, { [1] = { 100, 2 } })
    wow.setBag(6, 98, { [1] = { 100, 40 } })
    wow.login(nil)
    wow.fire("BANKFRAME_OPENED")
    eq(wow.hover(GameTooltip, 100)[2][2], R("Bags 2 · Bank 40", 42))
end)

test("inbox scan sums attachments across mails while the mailbox is open", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    wow.inbox = { { { 100, 5 }, [3] = { 100, 2 } }, {}, { { 200, 1 } } }
    wow.fire("MAIL_INBOX_UPDATE")
    eq(ns.char.mail, nil, "ignored before the mailbox opens")
    wow.fire("MAIL_SHOW")
    wow.fire("MAIL_INBOX_UPDATE")
    eq(ns.char.mail[100], 7)
    eq(ns.char.mail[200], 1)
    wow.inbox = { { { 200, 1 } } }
    wow.fire("MAIL_INBOX_UPDATE")
    eq(ns.char.mail[100], nil, "taken out of the mail")
    wow.fire("MAIL_CLOSED")
    wow.inbox = {}
    wow.fire("MAIL_INBOX_UPDATE")
    eq(ns.char.mail[200], 1, "ignored after closing")
end)

test("mailing an alt credits their mail once the send succeeds", function()
    wow.load(FILES)
    wow.login({ v = 2, chars = {
        ["Alt"] = alt("Alt", "WARRIOR", { bags = { [100] = 1 } }),
        ["Mid Thornwood"] = alt("Mid Thornwood", "DRUID", {}),
    } })
    eq(#wow.hover(GameTooltip, 100), 2, "one character: spacer and their line, no total")
    wow.outbox = { { 100, 20 }, [3] = { 100, 5 } }
    SendMail("alt", "subject", "")
    eq(AltsForeverDB.chars["Alt"].mail, nil, "not before the server confirms")
    wow.fire("MAIL_SEND_SUCCESS")
    eq(AltsForeverDB.chars["Alt"].mail[100], 25)
    eq(wow.hover(GameTooltip, 100)[2][2], R("Bags 1 · Mail 25", 26), "tooltip cache was refreshed")
    SendMail("mid thornwood", "", "")
    wow.fire("MAIL_SEND_SUCCESS")
    eq(AltsForeverDB.chars["Mid Thornwood"].mail[100], 25, "full names with a space, any case")
    SendMail("Mid Thornwood-SomeRealm", "", "")
    wow.fire("MAIL_SEND_SUCCESS")
    eq(AltsForeverDB.chars["Mid Thornwood"].mail[100], 50, "a realm suffix is ignored")
end)

test("failed sends and mail to strangers credit nobody", function()
    wow.load(FILES)
    wow.login({ v = 2, chars = { ["Alt"] = alt("Alt", "WARRIOR", {}) } })
    wow.outbox = { { 100, 20 } }
    SendMail("Alt", "", "")
    wow.fire("MAIL_FAILED")
    wow.fire("MAIL_SEND_SUCCESS")
    eq(AltsForeverDB.chars["Alt"].mail, nil)
    SendMail("Stranger", "", "")
    wow.fire("MAIL_SEND_SUCCESS")
    eq(AltsForeverDB.chars["Stranger"], nil)
end)

---------------------------------------------------------------------------
local function moneyChars()
    return { v = 2, chars = {
        ["Rich"] = alt("Rich", "PRIEST", { money = 50000 }),
        ["Poor"] = alt("Poor", "ROGUE", { money = 20 }),
        ["Broke"] = alt("Broke", "DRUID", { money = 0 }),
        ["Far"] = alt("Far", "MAGE", { money = 700 }),
    } }
end

test("money is recorded at login and whenever it changes", function()
    local ns = wow.load(FILES)
    wow.money = 1234
    wow.login(nil)
    eq(ns.char.money, 1234)
    wow.money = 99
    wow.fire("PLAYER_MONEY")
    eq(ns.char.money, 99)
end)

test("secret money is never stored", function()
    local ns = wow.load(FILES)
    wow.money = 500
    wow.login(nil)
    wow.money = wow.SECRET
    wow.fire("PLAYER_MONEY")
    eq(ns.char.money, 500)
end)

test("hovering bag money lists total, you, then others by amount", function()
    wow.load(FILES)
    wow.money = 300
    wow.login(moneyChars())
    local button = ContainerFrameCombinedBagsGoldButton
    button:Enter()
    local lines = GameTooltip.lines
    eq(GameTooltip:GetOwner(), button)
    eq(GameTooltip:IsShown(), true)
    eq(#lines, 6, "characters with no money are left out")
    eq(lines[1][1], "Gold", "title line")
    eq(lines[2][1], "Total"); eq(lines[2][2], "51020c")
    eq(lines[3][1], "[MAGE]Aldric"); eq(lines[3][2], "300c")
    eq(lines[4][1], "[PRIEST]Rich")
    eq(lines[5][1], "[MAGE]Far")
    eq(lines[6][1], "[ROGUE]Poor")
    eq(wow.coinHeight, 13, "coin icons sized to the tooltip text")
    eq(GameTooltip.point[1], "BOTTOMRIGHT")
    eq(GameTooltip.point[2], button:GetParent(), "anchored to the whole money display")
    button:Leave()
    eq(GameTooltip:IsShown(), false)
end)

test("an existing game tooltip on the money is added to, not replaced", function()
    wow.load(FILES)
    wow.login(moneyChars())
    local button = ContainerFrameCombinedBagsGoldButton
    GameTooltip:SetOwner(button)
    GameTooltip:AddLine("Blizzard's own text")
    GameTooltip:Show()
    button:Enter()
    eq(GameTooltip.lines[1][1], "Blizzard's own text")
    eq(GameTooltip.lines[2][1], " ")
    eq(GameTooltip.lines[3][1], "Gold")
end)

test("money tooltip with only you: title and your line, no total", function()
    wow.load(FILES)
    wow.money = 3674
    wow.login(nil)
    ContainerFrameCombinedBagsGoldButton:Enter()
    eq(#GameTooltip.lines, 2)
    eq(GameTooltip.lines[1][1], "Gold")
    eq(GameTooltip.lines[2][1], "[MAGE]Aldric"); eq(GameTooltip.lines[2][2], "3674c")
end)

test("bank money shows the tooltip, even if the bank window is created late", function()
    wow.load(FILES)
    wow.money = 300
    wow.login(moneyChars())
    local button = wow.button("BankPanelGoldButton") -- appears on first bank visit
    wow.fire("BANKFRAME_OPENED")
    wow.fire("BANKFRAME_CLOSED")
    wow.fire("BANKFRAME_OPENED") -- a second visit must not hook it twice
    button:Enter()
    eq(GameTooltip:GetOwner(), button)
    eq(#GameTooltip.lines, 6, "one set of lines, not two")
end)

test("the bank opening still scans the bank when money also listens", function()
    local ns = wow.load(FILES)
    wow.setBag(6, 98, { [1] = { 100, 20 } })
    wow.login(nil)
    wow.fire("BANKFRAME_OPENED")
    eq(ns.char.bank[100], 20)
end)

test("leaving the money doesn't hide someone else's tooltip", function()
    wow.load(FILES)
    wow.login(moneyChars())
    GameTooltip:SetOwner("somewhere else")
    GameTooltip:Show()
    ContainerFrameCombinedBagsGoldButton:Leave()
    eq(GameTooltip:IsShown(), true)
end)

---------------------------------------------------------------------------
test("/af delete removes a character by name, case-insensitively, but never yourself", function()
    wow.load(FILES)
    wow.login({ v = 2, chars = { ["Mid"] = alt("Mid", "DRUID", { bank = { [100] = 5 } }) } })
    eq(#wow.hover(GameTooltip, 100), 2)
    SlashCmdList.ALTSFOREVER("delete mid")
    eq(AltsForeverDB.chars["Mid"], nil)
    eq(#wow.hover(GameTooltip, 100), 0, "cache was cleared")
    SlashCmdList.ALTSFOREVER("delete Aldric")
    eq(type(AltsForeverDB.chars["Aldric"]), "table")
    SlashCmdList.ALTSFOREVER("realm")
    assert(table.concat(wow.printed, "\n"):find("/af opens the overview", 1, true), "/af realm is gone: shows help")
end)

test("the help message and overview credit Kadmai", function()
    wow.load(FILES)
    wow.login(nil)
    SlashCmdList.ALTSFOREVER("help")
    assert(table.concat(wow.printed, "\n"):find("by Kadmai", 1, true))
    SlashCmdList.ALTSFOREVER("")
    eq(AltsForeverFrame.credit.text, "Alts Forever by Kadmai")
end)

test("logout stamps when the character was last seen", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    wow.fire("PLAYER_LOGOUT")
    eq(type(ns.char.seen), "number")
end)

---------------------------------------------------------------------------
-- Professions and recipes

local SQUIRREL = 4408 -- Schematic: Mechanical Squirrel

local function engineeringWindow(learnedNames)
    local recipes = {}
    local id = 1000
    for _, name in ipairs({ "Mechanical Squirrel", "EZ-Thro Dynamite", "Shadow Goggles", "Rough Dynamite" }) do
        id = id + 1
        recipes[id] = { name = name, learned = learnedNames[name] or false }
    end
    wow.tradeskill.prof, wow.tradeskill.recipes = "Engineering", recipes
    wow.fire("TRADE_SKILL_SHOW")
end

local function recipeAlts()
    return { v = 2, chars = {
        ["Brakka"] = alt("Brakka", "HUNTER", { profs = { Engineering = 107 },
            recipes = { Engineering = { ["mechanical squirrel"] = true } } }),
        ["Elowen"] = alt("Elowen", "PRIEST", { profs = { Engineering = 110 },
            recipes = { Engineering = {} } }),
        ["Thessa"] = alt("Thessa", "DRUID", { profs = { Engineering = 60 } }),
        ["Sorrel"] = alt("Sorrel", "WARLOCK", { profs = { Engineering = 200 } }),
        ["Veyla"] = alt("Veyla", "PALADIN", { profs = { Tailoring = 150 } }),
    } }
end

test("profession skills are recorded at login and when they change", function()
    local ns = wow.load(FILES)
    wow.profs = { { "Engineering", 107 }, { "Mining", 99 } }
    wow.login(nil)
    eq(ns.char.profs.Engineering, 107)
    eq(ns.char.profs.Mining, 99)
    wow.profs = { { "Engineering", 108 } }
    wow.fire("SKILL_LINES_CHANGED")
    eq(ns.char.profs.Engineering, 108)
    eq(ns.char.profs.Mining, nil, "dropped professions are removed")
end)

test("opening a profession window records its learned recipes", function()
    local ns = wow.load(FILES)
    wow.profs = { { "Engineering", 107 } }
    wow.login(nil)
    eq(ns.char.recipes, nil, "nothing until a window opens")
    engineeringWindow({ ["Mechanical Squirrel"] = true, ["EZ-Thro Dynamite"] = true })
    local known = ns.char.recipes.Engineering
    eq(known["mechanical squirrel"], true)
    eq(known["ez-thro dynamite"], true, "stored lower-case")
    eq(known["shadow goggles"], nil, "unlearned recipes aren't stored")
end)

test("the recipe list is read once it's ready, not before", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    wow.tradeskill.ready = false
    engineeringWindow({ ["Mechanical Squirrel"] = true })
    eq(ns.char.recipes, nil)
    wow.tradeskill.ready = true
    wow.fire("TRADE_SKILL_LIST_UPDATE")
    eq(ns.char.recipes.Engineering["mechanical squirrel"], true)
end)

test("someone else's linked or guild profession is never recorded", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    wow.tradeskill.linked = true
    engineeringWindow({ ["Mechanical Squirrel"] = true })
    eq(ns.char.recipes, nil)
    wow.tradeskill.linked, wow.tradeskill.guild = false, true
    engineeringWindow({ ["Mechanical Squirrel"] = true })
    eq(ns.char.recipes, nil)
end)

test("learning a recipe adds it, but only to a profession already scanned", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    engineeringWindow({})
    wow.fire("TRADE_SKILL_CLOSE")
    wow.tradeskill.recipes[1003].learned = true -- Shadow Goggles
    wow.fire("NEW_RECIPE_LEARNED", 1003)
    eq(ns.char.recipes.Engineering["shadow goggles"], true)
    wow.tradeskill.recipes[2001] = { name = "Linen Robe", learned = true, prof = "Tailoring" }
    wow.fire("NEW_RECIPE_LEARNED", 2001)
    eq(ns.char.recipes.Tailoring, nil, "a partial list would wrongly say 'not learned'")
end)

test("recipe tooltip: only characters with the profession, you first, then by status", function()
    wow.load(FILES)
    wow.profs = { { "Engineering", 80 } }
    local text = wow.recipeItem(SQUIRREL, "Schematic: Mechanical Squirrel", "Engineering", 75)
    wow.login(recipeAlts())
    local lines = wow.hover(GameTooltip, SQUIRREL, text)
    eq(lines[1][1], " ")
    eq(lines[2][1], "Engineering (75)")
    eq(lines[3][1], "[MAGE]Aldric"); eq(lines[3][2], "|cff9d9d9dNot scanned|r")
    eq(lines[4][1], "[HUNTER]Brakka"); eq(lines[4][2], "|cff20ff20Known|r")
    eq(lines[5][1], "[PRIEST]Elowen"); eq(lines[5][2], "|cffffd100Can learn|r")
    eq(lines[6][1], "[DRUID]Thessa"); eq(lines[6][2], "|cffff2020Needs 75 (60)|r")
    eq(lines[7][1], "[WARLOCK]Sorrel"); eq(lines[7][2], "|cff9d9d9dNot scanned|r")
    eq(#lines, 7, "Veyla has no Engineering, so she is left out")
end)

test("recipe tooltip: reads the recipe's own requirement, not the crafted item's", function()
    wow.load(FILES)
    wow.profs = { { "Engineering", 107 } }
    local text = wow.recipeItem(5000, "Schematic: Shadow Goggles", "Engineering", 120, 115)
    wow.login(nil)
    local lines = wow.hover(GameTooltip, 5000, text)
    eq(lines[2][1], "Engineering (120)")
    eq(lines[3][2], "|cffff2020Needs 120 (107)|r")
end)

test("recipe tooltip: names match regardless of capitalisation", function()
    wow.load(FILES)
    wow.profs = { { "Engineering", 107 } }
    local text = wow.recipeItem(5001, "Schematic: Ez-Thro Dynamite", "Engineering", 100)
    wow.login(nil)
    engineeringWindow({ ["EZ-Thro Dynamite"] = true })
    eq(wow.hover(GameTooltip, 5001, text)[3][2], "|cff20ff20Known|r")
end)

test("recipe tooltip: updates when you learn the recipe", function()
    wow.load(FILES)
    wow.profs = { { "Engineering", 107 } }
    local text = wow.recipeItem(SQUIRREL, "Schematic: Mechanical Squirrel", "Engineering", 75)
    wow.login(nil)
    engineeringWindow({})
    eq(wow.hover(GameTooltip, SQUIRREL, text)[3][2], "|cffffd100Can learn|r")
    wow.tradeskill.recipes[1001].learned = true
    wow.fire("NEW_RECIPE_LEARNED", 1001)
    eq(wow.hover(GameTooltip, SQUIRREL, text)[3][2], "|cff20ff20Known|r")
end)

test("recipe tooltip: nothing for non-recipes or when nobody has the profession", function()
    wow.load(FILES)
    wow.login(nil)
    eq(#wow.hover(GameTooltip, 100, { "Linen Cloth" }), 0)
    local text = wow.recipeItem(SQUIRREL, "Schematic: Mechanical Squirrel", "Engineering", 75)
    eq(#wow.hover(GameTooltip, SQUIRREL, text), 0)
end)

---------------------------------------------------------------------------
-- Character info, rested XP and the overview window

local HOUR, DAY = 3600, 86400
local NOW = 1790000000
local G = "|cff9d9d9d"

local function overviewRows()
    local rows = {}
    for _, f in ipairs(wow.frames) do
        -- rawget: the fake frames answer any other name with a stand-in method.
        if rawget(f, "cells") and f.shown then rows[#rows + 1] = f end
    end
    return rows
end

local function cell(row, i) return row.cells[i].text end

local function overviewAlts()
    return { v = 2, chars = {
        ["Low"] = alt("Low", "ROGUE", { level = 12, xp = 100, xpMax = 1000, rested = 0,
            updated = NOW - 2 * DAY, money = 500 }),
        ["High"] = alt("High", "PRIEST", { level = 40, xp = 0, xpMax = 50000, rested = 75000,
            resting = true, updated = NOW - 3 * HOUR, money = 10000, zone = "Orgrimmar",
            profs = { Tailoring = 200, Enchanting = 180 }, prof1 = "Tailoring", prof2 = "Enchanting" }),
        ["Far"] = alt("Far", "MAGE", { level = 60, money = 7 }),
    } }
end

test("character info is recorded at login and kept current", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.stats.rested = 2000
    wow.stats.resting = true
    wow.login(nil)
    local c = ns.char
    eq(c.level, 24); eq(c.xp, 5700); eq(c.xpMax, 10000)
    eq(c.rested, 2000); eq(c.resting, true)
    eq(c.zone, "Durotar"); eq(c.hearth, "Razor Hill")
    eq(c.ilvl, 22, "equipped item level, rounded")
    eq(c.updated, NOW)
    wow.stats.xp, wow.stats.rested, wow.stats.resting = 6000, nil, false
    wow.fire("PLAYER_XP_UPDATE", "player")
    eq(c.xp, 6000)
    eq(c.rested, 0, "no rested XP is stored as 0")
    eq(c.resting, nil)
end)

test("logging out keeps the real stats, though the game reports zeros by then", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.stats.rested, wow.stats.resting = 2000, true
    wow.login(nil)
    -- What the game reports during logout:
    wow.stats.xp, wow.stats.xpMax, wow.stats.rested, wow.stats.resting, wow.stats.ilvl = 0, 0, nil, false, 0
    wow.now = NOW + 60
    wow.fire("PLAYER_LOGOUT")
    local c = ns.char
    eq(c.xp, 5700); eq(c.xpMax, 10000); eq(c.rested, 2000); eq(c.resting, true); eq(c.ilvl, 22)
    eq(c.updated, NOW + 60, "logout time is where the offline estimate starts")
end)

test("a zeroed reading at any other time is ignored too", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    wow.stats.xp, wow.stats.xpMax, wow.stats.ilvl = 0, 0, 0
    wow.fire("PLAYER_ENTERING_WORLD")
    eq(ns.char.xpMax, 10000)
    eq(ns.char.ilvl, 22)
end)

test("secret values are never stored as character info", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    wow.stats.level = wow.SECRET
    wow.fire("PLAYER_LEVEL_UP")
    eq(ns.char.level, 24)
end)

test("rested XP builds while logged out: full rate resting, a quarter elsewhere", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    local inn = { level = 20, xpMax = 10000, rested = 1000, resting = true, updated = NOW - 8 * HOUR }
    local field = { level = 20, xpMax = 10000, rested = 1000, resting = nil, updated = NOW - 8 * HOUR }
    eq(ns.RestedNow(inn, NOW), 1500, "5% of a level per 8 hours")
    eq(ns.RestedNow(field, NOW), 1125, "a quarter of that outside an inn or city")
end)

test("rested XP stops at 150% of a level and reports time until full", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    local long = { level = 20, xpMax = 10000, rested = 0, resting = true, updated = NOW - 400 * DAY }
    local rested, cap, toFull = ns.RestedNow(long, NOW)
    eq(rested, 15000); eq(cap, 15000); eq(toFull, 0)
    local fresh = { level = 20, xpMax = 10000, rested = 0, resting = true, updated = NOW }
    local _, _, secs = ns.RestedNow(fresh, NOW)
    eq(secs, 240 * HOUR, "30 blocks of 8 hours from empty")
end)

test("rested XP: none at max level, and no estimate for the character you're on", function()
    local ns = wow.load(FILES)
    wow.stats.rested = 3000
    wow.login(nil)
    eq(ns.RestedNow({ level = 60, xpMax = 10000, rested = 0 }, NOW), nil)
    ns.char.updated = NOW - 10 * DAY
    eq(ns.RestedNow(ns.char, NOW), 3000, "live value, not projected")
end)

local function runTimers()
    local fns = wow.timers
    wow.timers = {}
    for _, fn in ipairs(fns) do fn() end
end

test("results of the removed rested XP check are cleared from saved data", function()
    wow.load(FILES)
    wow.login({ v = 2, chars = {}, restedChecks = { { observed = 5 } }, restCheckOff = true })
    eq(AltsForeverDB.restedChecks, nil)
    eq(AltsForeverDB.restCheckOff, nil)
    SlashCmdList.ALTSFOREVER("restcheck")
    assert(table.concat(wow.printed, "\n"):find("/af opens the overview", 1, true), "unknown command shows help")
end)

test("overview text: time since, level, rested and professions", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    eq(ns.FormatAgo(1800), "<1h"); eq(ns.FormatAgo(7200), "2h ago"); eq(ns.FormatAgo(3 * DAY), "3d ago")
    eq(ns.LevelText({ level = 24, xp = 5700, xpMax = 10000 }), "24  " .. G .. "57%|r")
    eq(ns.LevelText({ level = 60, xp = 0, xpMax = 0 }), "60")
    eq(ns.RestedText({ level = 20, xpMax = 10000, rested = 1500, updated = NOW }, NOW), "15%")
    eq(ns.RestedText({ level = 20, xpMax = 10000, rested = 15000, updated = NOW }, NOW), "|cff4da6ff150%|r")
    eq(ns.RestedText({ level = 60, xpMax = 10000, rested = 0 }, NOW), G .. "-|r")
    eq(ns.RestedText({}, NOW), G .. "?|r", "not recorded yet")
    local L = "|cffc0c0c0"
    local n1, s1, n2, s2 = ns.ProfCells({ profs = { Engineering = 107, Mining = 99, Cooking = 35 },
        prof1 = "Engineering", prof2 = "Mining" })
    eq(n1, L .. "Engineering|r"); eq(s1, "107"); eq(n2, L .. "Mining|r"); eq(s2, "99")
    eq((ns.ProfCells({})), G .. "?|r", "never recorded")
    eq((ns.ProfCells({ profs = { Cooking = 35 } })), G .. "-|r", "no main professions")
    n1, s1, n2, s2 = ns.ProfCells({ profs = { Mining = 99 }, prof1 = "Mining" })
    eq(s1, "99"); eq(n2, ""); eq(s2, "", "only one main profession")
end)

test("main professions are the first two the game lists", function()
    local ns = wow.load(FILES)
    wow.profs = { { "Engineering", 107 }, { "Mining", 99 }, { "Cooking", 35 } }
    wow.login(nil)
    eq(ns.char.prof1, "Engineering"); eq(ns.char.prof2, "Mining")
end)

test("the overview window isn't built until /af is used", function()
    wow.load(FILES)
    wow.login(nil)
    eq(AltsForeverFrame, nil)
    SlashCmdList.ALTSFOREVER("")
    eq(AltsForeverFrame:IsShown(), true)
    SlashCmdList.ALTSFOREVER("")
    eq(AltsForeverFrame:IsShown(), false, "/af again closes it")
    local found = false
    for _, name in ipairs(UISpecialFrames) do found = found or name == "AltsForeverFrame" end
    eq(found, true, "Escape closes it")
end)

test("overview rows: you first, then by level; totals gold", function()
    wow.load(FILES)
    wow.now = NOW
    wow.money = 1234
    wow.profs = { { "Engineering", 107 }, { "Mining", 99 } }
    wow.login(overviewAlts())
    SlashCmdList.ALTSFOREVER("")
    local rows = overviewRows()
    eq(#rows, 4)
    eq(cell(rows[1], 1), "[MAGE]Aldric"); eq(cell(rows[1], 12), "|cff20ff20Online|r")
    eq(cell(rows[1], 5), "|cffc0c0c0Engineering|r"); eq(cell(rows[1], 6), "107")
    eq(cell(rows[1], 7), "|cffc0c0c0Mining|r"); eq(cell(rows[1], 8), "99")
    eq(cell(rows[2], 1), "[MAGE]Far"); eq(cell(rows[2], 2), "60"); eq(cell(rows[2], 3), G .. "-|r")
    eq(cell(rows[3], 1), "[PRIEST]High")
    eq(cell(rows[3], 3), "|cff4da6ff150%|r", "was already full")
    eq(cell(rows[3], 10), "Orgrimmar"); eq(cell(rows[3], 12), "3h ago")
    eq(cell(rows[4], 1), "[ROGUE]Low"); eq(cell(rows[4], 2), "12  " .. G .. "10%|r")
    eq(cell(rows[4], 12), "2d ago")
end)

test("an open overview updates when your money changes", function()
    wow.load(FILES)
    wow.money = 100
    wow.login(nil)
    SlashCmdList.ALTSFOREVER("")
    eq(cell(overviewRows()[1], 4), "100c")
    wow.money = 250
    wow.fire("PLAYER_MONEY")
    eq(cell(overviewRows()[1], 4), "250c")
end)

test("hovering a row shows rested details, hearthstone and item level", function()
    wow.load(FILES)
    wow.now = NOW
    wow.login(overviewAlts())
    SlashCmdList.ALTSFOREVER("")
    local row = overviewRows()[4] -- Low: level 12, not resting, logged out 2 days ago
    row.scripts.OnEnter(row)
    local text = {}
    for _, l in ipairs(GameTooltip.lines) do text[#text + 1] = table.concat(l, " = ") end
    text = table.concat(text, "\n")
    assert(text:find("Level 12", 1, true), text)
    -- 2 days away, not resting: 6 blocks of 8h x 1.25% x 1000 XP = 75 XP (8% of the level)
    assert(text:find("Rested = 75 XP (8%)", 1, true), text)
    assert(text:find("out in the world", 1, true), text)
    assert(text:find("Right-click to forget this character", 1, true), "how to forget them is shown")
    local you = overviewRows()[1]
    you.scripts.OnEnter(you)
    local mine = {}
    for _, l in ipairs(GameTooltip.lines) do mine[#mine + 1] = table.concat(l, " = ") end
    assert(not table.concat(mine, "\n"):find("forget", 1, true), "not on your own row")
end)

test("the window still opens if the client lacks Blizzard's frame template", function()
    wow.load(FILES)
    wow.missingTemplates.BasicFrameTemplateWithInset = true
    wow.login(nil)
    SlashCmdList.ALTSFOREVER("")
    eq(AltsForeverFrame:IsShown(), true)
    eq(AltsForeverFrame.template, "BackdropTemplate")
end)

---------------------------------------------------------------------------
-- Mail expiry

local function printedText()
    return table.concat(wow.printed, "\n")
end

test("reading the inbox records the soonest mail with items or gold", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.login(nil)
    wow.inbox = {
        { { 100, 1 }, days = 20 },
        {},                                    -- text only: ignored
        { money = 500, days = 2.5 },           -- gold counts
        { { 200, 1 }, days = 10, returned = true },
    }
    wow.fire("MAIL_SHOW")
    wow.fire("MAIL_INBOX_UPDATE")
    eq(ns.char.mailExpires, NOW + 2.5 * DAY)
    eq(ns.char.mailDeletes, nil, "from a player, not yet returned: goes back")
    wow.inbox = { { { 100, 1 }, days = 20 } }
    wow.fire("MAIL_INBOX_UPDATE")
    eq(ns.char.mailExpires, NOW + 20 * DAY, "moves on once the soonest is collected")
    wow.inbox = {}
    wow.fire("MAIL_INBOX_UPDATE")
    eq(ns.char.mailExpires, nil)
end)

test("mail already returned once, or from the auction house, gets deleted", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.login(nil)
    wow.fire("MAIL_SHOW")
    wow.inbox = { { { 100, 1 }, days = 1, returned = true } }
    wow.fire("MAIL_INBOX_UPDATE")
    eq(ns.char.mailDeletes, true)
    wow.inbox = { { money = 900, days = 1, canReply = false } }
    wow.fire("MAIL_INBOX_UPDATE")
    eq(ns.char.mailDeletes, true)
end)

test("mail sent to an alt expires in 30 days, unless they have sooner mail", function()
    wow.load(FILES)
    wow.now = NOW
    wow.login({ v = 2, chars = {
        ["Alt"] = alt("Alt", "WARRIOR", {}),
        ["Busy"] = alt("Busy", "ROGUE", { mail = {}, mailExpires = NOW + DAY, mailDeletes = true }),
    } })
    wow.outbox = { { 100, 5 } }
    SendMail("Alt", "", "")
    wow.fire("MAIL_SEND_SUCCESS")
    eq(AltsForeverDB.chars["Alt"].mailExpires, NOW + 30 * DAY)
    SendMail("Busy", "", "")
    wow.fire("MAIL_SEND_SUCCESS")
    eq(AltsForeverDB.chars["Busy"].mailExpires, NOW + DAY, "the sooner one still counts")
    eq(AltsForeverDB.chars["Busy"].mailDeletes, true)
end)

test("gold alone mailed to an alt counts as mail", function()
    wow.load(FILES)
    wow.now = NOW
    wow.login({ v = 2, chars = { ["Alt"] = alt("Alt", "WARRIOR", {}) } })
    wow.outbox, wow.outboxMoney = {}, 10000
    SendMail("Alt", "", "")
    wow.fire("MAIL_SEND_SUCCESS")
    eq(AltsForeverDB.chars["Alt"].mailExpires, NOW + 30 * DAY)
end)

test("login warns about mail expiring within 3 days, soonest first", function()
    wow.load(FILES)
    wow.now = NOW
    wow.login({ v = 2, chars = {
        ["Later"] = alt("Later", "PRIEST", { mail = {}, mailExpires = NOW + 10 * DAY }),
        ["Soon"] = alt("Soon", "ROGUE", { mail = {}, mailExpires = NOW + 2 * DAY + 4 * HOUR }),
        ["Urgent"] = alt("Urgent", "DRUID", { mail = {}, mailExpires = NOW + 5 * HOUR, mailDeletes = true }),
    } })
    eq(#wow.printed, 0, "nothing until the login spam has passed")
    for _, fn in ipairs(wow.timers) do fn() end
    local text = printedText()
    local urgent = text:find("[DRUID]Urgent: |cffff20205h|r (will be |cffff2020deleted|r)", 1, true)
    local soon = text:find("[ROGUE]Soon: |cffff80002d 4h|r (returned to sender)", 1, true)
    assert(urgent and soon and urgent < soon, text)
    assert(not text:find("Later", 1, true), text)
end)

test("no login warning when nothing expires soon", function()
    wow.load(FILES)
    wow.now = NOW
    wow.login({ v = 2, chars = { ["Later"] = alt("Later", "PRIEST", { mail = {}, mailExpires = NOW + 10 * DAY }) } })
    for _, fn in ipairs(wow.timers) do fn() end
    eq(#wow.printed, 0)
end)

test("/af mail lists everyone with mail, however far off", function()
    wow.load(FILES)
    wow.now = NOW
    wow.login({ v = 2, chars = { ["Later"] = alt("Later", "PRIEST", { mail = {}, mailExpires = NOW + 10 * DAY }) } })
    SlashCmdList.ALTSFOREVER("mail")
    assert(printedText():find("[PRIEST]Later: |cffffffff10d 0h|r", 1, true), printedText())
    wow.load(FILES)
    wow.login(nil)
    SlashCmdList.ALTSFOREVER("mail")
    assert(printedText():find("No mail with items or gold on record.", 1, true), printedText())
end)

test("expiry text and the overview's mail column", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    eq(ns.ExpiryText(2 * DAY + 4 * HOUR), "2d 4h"); eq(ns.ExpiryText(5 * HOUR), "5h")
    eq(ns.ExpiryText(600), "<1h"); eq(ns.ExpiryText(-5), "expired")
    eq(ns.MailText({}, NOW), G .. "?|r", "mailbox never opened")
    eq(ns.MailText({ mail = {} }, NOW), "", "no valuable mail")
    eq(ns.MailText({ mail = {}, mailExpires = NOW + 5 * HOUR }, NOW), "|cffff20205h|r")
end)

---------------------------------------------------------------------------
-- Gear

local function itemLink(id, name, color)
    return (color or "|cff1eff00") .. "|Hitem:" .. id .. "::::::|h[" .. name .. "]|h|r"
end

local function gearPanelSlots()
    local slots = {}
    for _, f in ipairs(wow.frames) do
        local slot = rawget(f, "slot")
        if slot then slots[slot] = f end
    end
    return slots
end

local function clickRow(name)
    for _, row in ipairs(overviewRows()) do
        if cell(row, 1):find(name, 1, true) then return row.scripts.OnClick(row) end
    end
    error("no row for " .. name)
end

test("gear is recorded per slot with lowest durability", function()
    local ns = wow.load(FILES)
    wow.gearLinks[1] = itemLink(3000, "Hunting Cap")
    wow.gearLinks[16] = itemLink(3001, "Copper Claymore", "|cffffffff")
    wow.gearLinks[2] = itemLink(3002, "Amulet") -- no durability
    wow.inventory[1], wow.inventory[16], wow.inventory[2] = 3000, 3001, 3002
    wow.durability[1] = { 40, 50 }
    wow.durability[16] = { 9, 45 }
    wow.login(nil)
    local c = ns.char
    eq(c.gear[1], wow.gearLinks[1]); eq(c.gear[16], wow.gearLinks[16]); eq(c.gear[5], nil)
    eq(c.dura, 20, "lowest of 80% and 20%")
    eq(c.duraSlots[1], 80); eq(c.duraSlots[16], 20); eq(c.duraSlots[2], nil)
    wow.durability[16] = { 45, 45 }
    wow.fire("UPDATE_INVENTORY_DURABILITY")
    eq(c.dura, 80); eq(c.duraSlots[16], nil, "full items aren't listed")
    wow.gearLinks[1] = nil
    wow.inventory[1] = nil
    wow.fire("PLAYER_EQUIPMENT_CHANGED", 1)
    eq(c.gear[1], nil, "a slot that's really emptied is cleared")
end)

test("gear still loading at login doesn't wipe what was recorded, and is retried", function()
    local ns = wow.load(FILES)
    local saved = { v = 2, chars = { ["Aldric"] = alt("Aldric", "MAGE", {
        gear = { [1] = itemLink(3000, "Hunting Cap"), [5] = itemLink(3003, "Wolfmane Vest") }, dura = 60 }) } }
    -- The game knows what's worn (item IDs) but can't give links yet.
    wow.inventory[1], wow.inventory[5] = 3000, 3003
    wow.login(saved)
    eq(ns.char.gear[1], itemLink(3000, "Hunting Cap"), "kept, not wiped")
    eq(ns.char.gear[5], itemLink(3003, "Wolfmane Vest"))
    eq(ns.char.dura, 60, "durability isn't blanked either")
    eq(#wow.timers >= 1, true, "a retry is scheduled")
    -- Links arrive, with a new hat.
    wow.gearLinks[1], wow.gearLinks[5] = itemLink(3009, "New Hat"), itemLink(3003, "Wolfmane Vest")
    wow.inventory[1] = 3009
    for _, fn in ipairs(wow.timers) do fn() end
    eq(ns.char.gear[1], itemLink(3009, "New Hat"))
end)

test("equipment not loaded at all at login keeps the recorded gear", function()
    local ns = wow.load(FILES)
    local saved = { v = 2, chars = { ["Aldric"] = alt("Aldric", "MAGE", {
        gear = { [1] = itemLink(3000, "Hunting Cap") } }) } }
    wow.login(saved) -- no item IDs, no links
    eq(ns.char.gear[1], itemLink(3000, "Hunting Cap"))
end)

test("retries stop after five tries", function()
    wow.load(FILES)
    wow.inventory[1] = 3000 -- link never arrives
    wow.player.name = "Aldric Vane" -- a full name, so only gear retries are scheduled
    wow.login(nil)
    local runs = 0
    while #wow.timers > 0 and runs < 20 do
        local fns = wow.timers
        wow.timers = {}
        for _, fn in ipairs(fns) do fn() end
        runs = runs + 1
    end
    eq(runs, 5)
end)

test("logging out doesn't wipe the recorded gear", function()
    local ns = wow.load(FILES)
    wow.gearLinks[1] = itemLink(3000, "Hunting Cap")
    wow.login(nil)
    wow.gearLinks = {}
    wow.fire("PLAYER_LOGOUT")
    eq(ns.char.gear[1] ~= nil, true)
end)

test("item link names keep their quality colour but lose the brackets", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    eq(ns.LinkName(itemLink(1, "Hunting Cap")), "|cff1eff00Hunting Cap|r")
    eq(ns.LinkName("|cnIQ3:|Hitem:5::|h[Blue Thing]|h|r"), "|cnIQ3:Blue Thing|r", "newer colour format")
    eq(ns.LinkName("not a link"), "not a link")
    eq(ns.DurabilityText(15), "|cffff202015%|r"); eq(ns.DurabilityText(45), "|cffff800045%|r")
    eq(ns.DurabilityText(nil), "|cff9d9d9d-|r")
end)

test("clicking a character in the overview opens their gear", function()
    wow.load(FILES)
    local saved = { v = 2, chars = {
        ["Brakka"] = alt("Brakka", "HUNTER", { level = 20, ilvl = 11,
            gear = { [1] = itemLink(3000, "Hunting Cap"), [16] = itemLink(3001, "Copper Claymore") },
            duraSlots = { [16] = 10 }, dura = 10 }),
    } }
    wow.login(saved)
    SlashCmdList.ALTSFOREVER("")
    clickRow("Brakka")
    local panel = AltsForeverGearFrame
    eq(panel:IsShown(), true)
    eq(panel.title.text, "[HUNTER]Brakka|cff9d9d9d  ilvl 11|r")
    local slots = gearPanelSlots()
    eq(slots[1].icon.texture, "icon:3000"); eq(slots[1].name.text, "|cff1eff00Hunting Cap|r")
    eq(slots[5].icon.texture, "empty:ChestSlot", "empty slots show the slot art")
    eq(slots[16].icon.tint[2], 0.3, "nearly broken items are tinted red")
    eq(slots[1].icon.tint[2], 1)
    eq(panel.footer.text, "Lowest durability: |cffff202010%|r")
    eq(panel.empty.shown, false)
    clickRow("Brakka")
    eq(panel:IsShown(), false, "clicking the same character again closes it")
end)

test("gear panel for a character with nothing recorded says so", function()
    wow.load(FILES)
    wow.login({ v = 2, chars = { ["New"] = alt("New", "ROGUE", { level = 5 }) } })
    SlashCmdList.ALTSFOREVER("")
    clickRow("New")
    eq(AltsForeverGearFrame.empty.shown, true)
    eq(gearPanelSlots()[1].icon.texture, "empty:HeadSlot")
end)

test("hovering a slot shows the item, shift-click links it, closing the overview closes gear", function()
    wow.load(FILES)
    wow.gearLinks[1] = itemLink(3000, "Hunting Cap")
    wow.login(nil)
    SlashCmdList.ALTSFOREVER("")
    clickRow("Aldric")
    local head = gearPanelSlots()[1]
    head.scripts.OnEnter(head)
    eq(GameTooltip.hyperlink, wow.gearLinks[1])
    head.scripts.OnClick(head)
    eq(#wow.chatLinks, 0, "plain click does nothing")
    wow.modified = true
    head.scripts.OnClick(head)
    eq(wow.chatLinks[1], wow.gearLinks[1])
    SlashCmdList.ALTSFOREVER("")
    eq(AltsForeverGearFrame:IsShown(), false)
end)

test("an open gear panel for you updates when you change gear", function()
    wow.load(FILES)
    wow.gearLinks[1], wow.inventory[1] = itemLink(3000, "Hunting Cap"), 3000
    wow.login(nil)
    SlashCmdList.ALTSFOREVER("")
    clickRow("Aldric")
    wow.gearLinks[1], wow.inventory[1] = itemLink(3005, "Better Hat"), 3005
    wow.fire("PLAYER_EQUIPMENT_CHANGED", 1)
    eq(gearPanelSlots()[1].name.text, "|cff1eff00Better Hat|r")
end)

---------------------------------------------------------------------------
---------------------------------------------------------------------------
local SQUIRREL_ITEM, DYNAMITE_ITEM, GOGGLES_ITEM = 4401, 4378, 4368

-- Engineering window where recipes make items: squirrel and goggles via the
-- schematic, dynamite only via its item link, and one with no item at all.
local function craftingWindow(learned)
    wow.tradeskill.prof = "Engineering"
    wow.tradeskill.recipes = {
        [1001] = { name = "Mechanical Squirrel", learned = learned.squirrel or false, item = SQUIRREL_ITEM },
        [1002] = { name = "Rough Dynamite", learned = learned.dynamite or false,
            link = "|cffffffff|Hitem:" .. DYNAMITE_ITEM .. "::::::::60:::::|h[Rough Dynamite]|h|r" },
        [1003] = { name = "Shadow Goggles", learned = learned.goggles or false, item = GOGGLES_ITEM },
        [1004] = { name = "Enchant Something", learned = true },
    }
    wow.fire("TRADE_SKILL_SHOW")
end

-- The names under the "Can craft" heading, joined with ", ", or nil if there's none.
local function craftLine(lines)
    for i, l in ipairs(lines) do
        if l[1] == "Can craft" and not l[2] then
            local names = {}
            for j = i + 1, #lines do
                local name = lines[j][1] and lines[j][1]:match("^  (.+)$")
                if not name then break end
                names[#names + 1] = name
            end
            return table.concat(names, ", ")
        end
    end
end

test("opening a profession window records which items each learned recipe makes", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    craftingWindow({ squirrel = true, dynamite = true })
    local crafts = ns.char.crafts.Engineering
    eq(crafts[SQUIRREL_ITEM], "mechanical squirrel", "the recipe that makes it")
    eq(crafts[DYNAMITE_ITEM], "rough dynamite", "read from the item link when the schematic has none")
    eq(crafts[GOGGLES_ITEM], nil, "not learned")
    local n = 0
    for _ in pairs(crafts) do n = n + 1 end
    eq(n, 2, "recipes that make no item are skipped")
end)

test("item tooltip lists who can craft it: you first, then by name", function()
    wow.load(FILES)
    wow.login({ v = 2, chars = {
        ["Brakka"] = alt("Brakka", "HUNTER", { crafts = { Engineering = { [SQUIRREL_ITEM] = true } } }),
        ["Far"] = alt("Far", "MAGE", { crafts = { Engineering = { [SQUIRREL_ITEM] = true } } }),
        ["Veyla"] = alt("Veyla", "PALADIN", { crafts = { Tailoring = { [2580] = true } } }),
    } })
    craftingWindow({ squirrel = true })
    local lines = wow.hover(GameTooltip, SQUIRREL_ITEM)
    eq(craftLine(lines), "[MAGE]Aldric, [HUNTER]Brakka, [MAGE]Far", "you first, then by name, one per line")
    eq(craftLine(wow.hover(GameTooltip, 9999)), nil, "nobody makes it: no line")
end)

test("a character is listed once even if two professions make the item", function()
    wow.load(FILES)
    wow.login({ v = 2, chars = {
        ["Brakka"] = alt("Brakka", "HUNTER",
            { crafts = { Engineering = { [100] = true }, Blacksmithing = { [100] = true } } }),
    } })
    eq(craftLine(wow.hover(GameTooltip, 100)), "[HUNTER]Brakka")
end)

test("can-craft line updates when you learn a recipe", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    craftingWindow({})
    wow.fire("TRADE_SKILL_CLOSE")
    eq(craftLine(wow.hover(GameTooltip, GOGGLES_ITEM)), nil)
    wow.tradeskill.recipes[1003].learned = true
    wow.fire("NEW_RECIPE_LEARNED", 1003)
    eq(ns.char.crafts.Engineering[GOGGLES_ITEM], "shadow goggles")
    eq(craftLine(wow.hover(GameTooltip, GOGGLES_ITEM)), "[MAGE]Aldric")
end)

---------------------------------------------------------------------------
test("time played is requested quietly after login and recorded", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.login({ v = 2, chars = {} })
    eq(wow.playedRequests, 0, "not during the login spam")
    runTimers()
    eq(wow.playedRequests, 1)
    wow.timePlayed(5 * DAY)
    eq(#wow.playedShown, 0, "the chat message for our request is hidden")
    eq(ns.char.played, 5 * DAY); eq(ns.char.playedAt, NOW)
    table.remove(wow.timers)() -- the answer's own timer, a second later
    eq(ChatFrame1:IsEventRegistered("TIME_PLAYED_MSG"), true, "listening again once the answer is in")
    runTimers()
    wow.timePlayed(5 * DAY + 60) -- the player types /played
    eq(#wow.playedShown, 1, "the player's own /played still prints")
    eq(ns.char.played, 5 * DAY + 60)
    eq(ChatFrame1:IsEventRegistered("TIME_PLAYED_MSG"), true)
    eq(ChatFrame2:IsEventRegistered("TIME_PLAYED_MSG"), false, "a window that wasn't listening stays that way")
end)

test("chat listens for time played again even if no answer comes", function()
    wow.load(FILES)
    wow.login({ v = 2, chars = {} })
    runTimers() -- the request: chat stops listening
    eq(ChatFrame1:IsEventRegistered("TIME_PLAYED_MSG"), false)
    runTimers() -- 10 seconds later, no answer
    eq(ChatFrame1:IsEventRegistered("TIME_PLAYED_MSG"), true)
end)

test("time played keeps counting while online and is saved at logout", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.login(nil)
    wow.timePlayed(2 * HOUR)
    eq(ns.PlayedNow(ns.char, NOW + HOUR), 3 * HOUR)
    wow.now = NOW + HOUR
    wow.fire("PLAYER_LOGOUT")
    eq(ns.char.played, 3 * HOUR); eq(ns.char.playedAt, NOW + HOUR)
    eq(ns.PlayedNow({ played = 100, playedAt = NOW }, NOW + DAY), 100, "logged-out characters don't count up")
end)

test("secret time played is never stored", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    wow.SECRET = 12345 -- a secret number still looks like a number
    wow.timePlayed(12345)
    eq(ns.char.played, nil)
end)

test("overview shows time played per character and in total", function()
    local ns = wow.load(FILES)
    eq(ns.FormatPlayed(20 * 60), "20m"); eq(ns.FormatPlayed(5 * HOUR + 20 * 60), "5h 20m")
    eq(ns.FormatPlayed(12 * DAY + 5 * HOUR + 59), "12d 5h")
    wow.now = NOW
    local saved = overviewAlts()
    saved.chars["High"].played = 3 * DAY
    wow.login(saved)
    wow.timePlayed(2 * HOUR)
    SlashCmdList.ALTSFOREVER("")
    local rows = overviewRows()
    eq(cell(rows[1], 11), "2h 0m")
    eq(cell(rows[3], 1), "[PRIEST]High"); eq(cell(rows[3], 11), "3d 0h")
    eq(cell(rows[4], 11), G .. "?|r", "not recorded yet")
    eq(AltsForeverFrame.footer.text, "Total played: 3d 2h     Total gold: 10507c")
end)

---------------------------------------------------------------------------
-- Names on build 70009: UnitName returns the first name and surname separately
test("the full name is built from UnitName's first name and surname", function()
    local ns = wow.load(FILES)
    wow.player.name = "Nyx Emberfall"
    wow.login(nil)
    eq(ns.charKey, "Nyx Emberfall")
    eq(ns.char.name, "Nyx Emberfall")
end)

test("older builds that return the full name as one value still work", function()
    local ns = wow.load(FILES)
    wow.player.name, wow.oneValueNames = "Nyx Emberfall", true
    wow.login(nil)
    eq(ns.charKey, "Nyx Emberfall")
end)

test("an entry saved under the first name alone takes the full name at login", function()
    local ns = wow.load(FILES)
    wow.player.name, wow.player.class = "Mira Dawnfield", "PALADIN"
    wow.login({ v = 2, chars = {
        ["Mira"] = alt("Mira", "PALADIN", { bank = { [100] = 4 }, played = 500 }),
        ["Rook"] = alt("Rook", "ROGUE", {}),
    } })
    eq(ns.charKey, "Mira Dawnfield")
    eq(AltsForeverDB.chars["Mira"], nil)
    eq(ns.char.name, "Mira Dawnfield"); eq(ns.char.bank[100], 4); eq(ns.char.played, 500)
    eq(type(AltsForeverDB.chars["Rook"]), "table", "someone else's first-name entry is left alone")
end)

test("a first-name entry of another class isn't taken", function()
    local ns = wow.load(FILES)
    wow.player.name, wow.player.class = "Mira Dawnfield", "PALADIN"
    wow.login({ v = 2, chars = { ["Mira"] = alt("Mira", "DRUID", { played = 500 }) } })
    eq(type(AltsForeverDB.chars["Mira"]), "table")
    eq(ns.char.played, nil)
end)

test("a first-name entry already saved is folded into the full name, newer data first", function()
    wow.load(FILES)
    wow.login({ v = 2, chars = {
        ["Mira"] = alt("Mira", "PALADIN", { updated = 200, played = 500, bags = { [100] = 2 } }),
        ["Mira Dawnfield"] = alt("Mira Dawnfield", "PALADIN", { updated = 100, played = 400,
            bags = { [100] = 9 }, bank = { [200] = 5 }, recipes = { Cooking = {} } }),
        ["Sorrel"] = alt("Sorrel", "WARLOCK", { updated = 50, played = 10, mail = { [300] = 1 } }),
        ["Sorrel Nightbloom"] = alt("Sorrel Nightbloom", "WARLOCK", { updated = 90, played = 20 }),
    } })
    eq(AltsForeverDB.chars["Mira"], nil)
    local c = AltsForeverDB.chars["Mira Dawnfield"]
    eq(c.name, "Mira Dawnfield")
    eq(c.played, 500); eq(c.bags[100], 2, "newer entry's data wins")
    eq(c.bank[200], 5); eq(type(c.recipes.Cooking), "table", "gaps filled from the older entry")
    local sorrel = AltsForeverDB.chars["Sorrel Nightbloom"]
    eq(AltsForeverDB.chars["Sorrel"], nil)
    eq(sorrel.played, 20, "the full-name entry is newer here, so it wins")
    eq(sorrel.mail[300], 1); eq(sorrel.name, "Sorrel Nightbloom")
end)

test("one-word names are left alone when the match isn't certain", function()
    wow.load(FILES)
    wow.login({ v = 2, chars = {
        ["Ash"] = alt("Ash", "MAGE", {}),
        ["Ash Fire"] = alt("Ash Fire", "MAGE", {}),
        ["Ash Wood"] = alt("Ash Wood", "MAGE", {}),
        ["Rook"] = alt("Rook", "ROGUE", {}),
        ["Rook Hollow"] = alt("Rook Hollow", "PRIEST", {}),
    } })
    local chars = AltsForeverDB.chars
    assert(chars["Ash"] and chars["Ash Fire"] and chars["Ash Wood"], "two candidates: nothing merged")
    assert(chars["Rook"] and chars["Rook Hollow"], "different class: nothing merged")
end)

test("the slash commands are /af and /altsforever; the old /it is gone", function()
    wow.load(FILES)
    eq(SLASH_ALTSFOREVER1, "/af"); eq(SLASH_ALTSFOREVER2, "/altsforever")
    eq(SLASH_ALTSFOREVER3, nil)
end)

---------------------------------------------------------------------------
-- Skill-ups across alts (0.3.0): grey points and reagents from the live game
local L = "|cffe0e0e0"
local LINEN, COPPER_TUBE, BOLT = 2589, 4361, 4359
local function to(n) return L .. " · to " .. n .. "|r" end
local function skillupsTo(n) return L .. " · skill-ups to " .. n .. "|r" end

-- Engineering recipes with grey points and reagents, as a profession window lists them.
local function greyWindow(learned)
    wow.tradeskill.prof = "Engineering"
    wow.tradeskill.recipes = {
        [1001] = { name = "Mechanical Squirrel", learned = learned.squirrel or false, item = SQUIRREL_ITEM,
            grey = 100, reagents = { { COPPER_TUBE, 1 }, { LINEN, 2 } } },
        [1002] = { name = "Rough Dynamite", learned = learned.dynamite or false, item = DYNAMITE_ITEM,
            grey = 60, reagents = { { LINEN, 1 } } },
        [1003] = { name = "Shadow Goggles", learned = learned.goggles or false, item = GOGGLES_ITEM,
            grey = 150, reagents = { { BOLT, 4 } } },
    }
    wow.fire("TRADE_SKILL_SHOW")
end

local function textOf(lines)
    local t = {}
    for _, l in ipairs(lines) do t[#t + 1] = table.concat(l, " = ") end
    return table.concat(t, "\n")
end

test("a profession scan records grey points, and reagents of known recipes, account-wide", function()
    wow.load(FILES)
    wow.profs = { { "Engineering", 55 } }
    wow.login({ v = 2, recipeInfo = { Engineering = { ["shadow goggles"] = "140;Shadow Goggles;,4359:4" } }, chars = {
        ["Tink Gear"] = alt("Tink Gear", "WARRIOR", { recipes = { Engineering = { ["shadow goggles"] = true } } }) } })
    wow.schematics = 0
    greyWindow({ squirrel = true })
    local info = AltsForeverDB.recipeInfo.Engineering
    eq(info["mechanical squirrel"], "100;Mechanical Squirrel;,4361:1,2589:2")
    eq(info["rough dynamite"], nil, "nobody knows it: not stored")
    eq(info["shadow goggles"], "150;Shadow Goggles;,4359:4", "known by another character: grey refreshed, reagents kept")
    eq(wow.schematics, 1, "schematics are read only for learned recipes")
end)

test("learning a recipe records its reagents and what it makes", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    greyWindow({})
    wow.fire("TRADE_SKILL_CLOSE")
    wow.tradeskill.recipes[1003].learned = true
    wow.fire("NEW_RECIPE_LEARNED", 1003)
    eq(AltsForeverDB.recipeInfo.Engineering["shadow goggles"], "150;Shadow Goggles;,4359:4")
    eq(ns.char.crafts.Engineering[GOGGLES_ITEM], "shadow goggles")
end)

test("recipe item tooltips don't show skill-up levels", function()
    wow.load(FILES)
    wow.profs = { { "Engineering", 80 } }
    local text = wow.recipeItem(SQUIRREL, "Schematic: Mechanical Squirrel", "Engineering", 75)
    local saved = recipeAlts()
    saved.recipeInfo = { Engineering = { ["mechanical squirrel"] = "100;Mechanical Squirrel;" } }
    wow.login(saved)
    local lines = wow.hover(GameTooltip, SQUIRREL, text)
    eq(lines[3][2], "|cff9d9d9dNot scanned|r")
    eq(lines[4][2], "|cff20ff20Known|r")
    eq(lines[5][2], "|cffffd100Can learn|r")
    eq(lines[6][2], "|cffff2020Needs 75 (60)|r")
end)

test("/af skillups turns every skill-up detail off and on", function()
    wow.load(FILES)
    wow.profs = { { "Engineering", 80 } }
    local text = wow.recipeItem(SQUIRREL, "Schematic: Mechanical Squirrel", "Engineering", 75)
    local saved = recipeAlts()
    saved.recipeInfo = { Engineering = { ["mechanical squirrel"] = "100;Mechanical Squirrel;,2589:2" } }
    saved.chars["Brakka"].crafts = { Engineering = { [SQUIRREL_ITEM] = "mechanical squirrel" } }
    saved.chars["Brakka"].profs.Engineering = 90
    wow.login(saved)
    SlashCmdList.ALTSFOREVER("skillups")
    eq(AltsForeverDB.skillupsOff, true)
    eq(craftLine(wow.hover(GameTooltip, SQUIRREL_ITEM)), "[HUNTER]Brakka", "can craft as in 0.2")
    assert(not textOf(wow.hover(GameTooltip, LINEN)):find("Skill-ups", 1, true), "no reagent section")
    SlashCmdList.ALTSFOREVER("skillups")
    eq(AltsForeverDB.skillupsOff, nil)
    eq(craftLine(wow.hover(GameTooltip, SQUIRREL_ITEM)), "[HUNTER]Brakka" .. skillupsTo(100))
    assert(textOf(wow.hover(GameTooltip, LINEN)):find("Skill-ups", 1, true), "reagent section back")
end)

test("can craft: characters who'd still get a skill-up are marked", function()
    wow.load(FILES)
    wow.login({ v = 2, recipeInfo = { Engineering = { ["mechanical squirrel"] = "100;Mechanical Squirrel;" } }, chars = {
        ["Brakka"] = alt("Brakka", "HUNTER", { profs = { Engineering = 90 },
            crafts = { Engineering = { [SQUIRREL_ITEM] = "mechanical squirrel" } } }),
        ["Far"] = alt("Far", "MAGE", { profs = { Engineering = 120 },
            crafts = { Engineering = { [SQUIRREL_ITEM] = "mechanical squirrel" } } }),
        ["Old"] = alt("Old", "ROGUE", { profs = { Engineering = 10 }, crafts = { Engineering = { [SQUIRREL_ITEM] = true } } }),
    } })
    eq(craftLine(wow.hover(GameTooltip, SQUIRREL_ITEM)),
        "[HUNTER]Brakka" .. skillupsTo(100) .. ", [MAGE]Far, [ROGUE]Old", "past grey, or saved before 0.3: unmarked")
end)

-- Aldric (you) and two alts, with recipes that use Linen Cloth.
local function reagentAlts()
    return { v = 2, recipeInfo = {
        Engineering = {
            ["mechanical squirrel"] = "100;Mechanical Squirrel;,4361:1,2589:2",
            ["rough dynamite"] = "60;Rough Dynamite;,2589:1",
        },
        ["First Aid"] = { ["linen bandage"] = "80;Linen Bandage;,2589:1", ["heavy linen bandage"] = "115;Heavy Linen Bandage;,2589:2" },
    }, chars = {
        ["Brakka Stone"] = alt("Brakka Stone", "HUNTER", { profs = { Engineering = 107 },
            recipes = { Engineering = { ["mechanical squirrel"] = true } } }),
        ["Tarnia Moon"] = alt("Tarnia Moon", "DRUID", { profs = { ["First Aid"] = 40 },
            recipes = { ["First Aid"] = { ["linen bandage"] = true } } }),
    } }
end

test("reagent tooltip lists the recipes that still give each character a skill-up", function()
    local ns = wow.load(FILES)
    wow.profs = { { "Engineering", 55 } }
    local saved = reagentAlts()
    saved.chars["Aldric"] = alt("Aldric", "MAGE", { recipes = { Engineering = { ["mechanical squirrel"] = true, ["rough dynamite"] = true } } })
    wow.login(saved)
    local lines = wow.hover(GameTooltip, LINEN)
    eq(lines[1][1], " "); eq(lines[2][1], "Skill-ups")
    eq(lines[3][1], "  Mechanical Squirrel"); eq(lines[3][2], "[MAGE]Aldric" .. to(100))
    eq(lines[4][1], "  Rough Dynamite"); eq(lines[4][2], "[MAGE]Aldric" .. to(60))
    eq(lines[5][1], "  Linen Bandage"); eq(lines[5][2], "[DRUID]Tarnia" .. to(80))
    eq(#lines, 5, "Brakka is past grey; nobody knows Heavy Linen Bandage")
    eq(textOf(wow.hover(GameTooltip, 9999)):find("Skill-ups", 1, true), nil, "unused item: no section")
    -- Skill goes up: Rough Dynamite (grey 60) stops counting.
    wow.profs = { { "Engineering", 60 } }
    wow.fire("SKILL_LINES_CHANGED")
    lines = wow.hover(GameTooltip, LINEN)
    eq(lines[4][1], "  Linen Bandage", "updated when skill changes")
    eq(ns.SkillupCount(ns.char, "Engineering"), 1)
end)

test("reagent tooltip: 2 recipes per character with the most skill-ups left", function()
    wow.load(FILES)
    wow.profs = { { "Tailoring", 50 } }
    -- Your recipes: 7 shirts, skill-ups left 10, 20, ... 70.
    local info, mine = {}, {}
    for i = 1, 7 do
        info["shirt " .. i] = (50 + i * 10) .. ";Shirt " .. i .. ";,2589:1"
        mine["shirt " .. i] = true
    end
    info["bag"] = "200;Bag;,2589:2"
    info["cap"] = "70;Cap;,2589:1"
    info["vest"] = "95;Vest;,2589:1"
    wow.login({ v = 2, recipeInfo = { Tailoring = info }, chars = {
        ["Aldric"] = alt("Aldric", "MAGE", { recipes = { Tailoring = mine } }),
        -- Zed's best: Bag, 200 - 60 = 140 left (more than any of yours). Amy's: Vest, 55 left.
        ["Zed Moor"] = alt("Zed Moor", "ROGUE", { profs = { Tailoring = 60 }, recipes = { Tailoring = { bag = true, cap = true } } }),
        ["Amy Ash"] = alt("Amy Ash", "DRUID", { profs = { Tailoring = 40 }, recipes = { Tailoring = { vest = true, cap = true } } }),
        ["Old Timer"] = alt("Old Timer", "WARRIOR", { profs = { Tailoring = 300 }, recipes = { Tailoring = { bag = true } } }),
    } })
    local lines = wow.hover(GameTooltip, LINEN)
    eq(lines[2][1], "Skill-ups")
    eq(lines[3][1], "  Shirt 7"); eq(lines[3][2], "[MAGE]Aldric" .. to(120), "you first even though Zed has more left")
    eq(lines[4][1], "  Shirt 6"); eq(lines[4][2], "[MAGE]Aldric" .. to(110))
    eq(lines[5][1], "  Bag"); eq(lines[5][2], "[ROGUE]Zed" .. to(200), "then the alt with the most left, though Z")
    eq(lines[6][1], "  Cap"); eq(lines[6][2], "[ROGUE]Zed" .. to(70))
    eq(lines[7][1], "  Vest"); eq(lines[7][2], "[DRUID]Amy" .. to(95))
    eq(lines[8][1], "  Cap"); eq(lines[8][2], "[DRUID]Amy" .. to(70))
    eq(lines[9][1], "  +5 more", "your 5 other shirts; Old Timer is past grey")
end)

test("reagent tooltip: never more than 6 recipe lines", function()
    wow.load(FILES)
    local info, chars = { ["cap"] = "70;Cap;,2589:1", ["hat"] = "80;Hat;,2589:1" }, {}
    for _, name in ipairs({ "Ann Bee", "Bo Cee", "Cy Dee", "Di Eff" }) do
        chars[name] = alt(name, "PRIEST", { profs = { Tailoring = 10 }, recipes = { Tailoring = { cap = true, hat = true } } })
    end
    wow.login({ v = 2, recipeInfo = { Tailoring = info }, chars = chars })
    local lines = wow.hover(GameTooltip, LINEN)
    eq(lines[7][2], "[PRIEST]Cy" .. to(80)); eq(lines[8][2], "[PRIEST]Cy" .. to(70), "three alts fill the 6 lines")
    eq(lines[9][1], "  +2 more"); eq(#lines, 9)
end)

test("overview row tooltip counts recipes still giving skill-ups", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    local saved = overviewAlts()
    saved.recipeInfo = { Tailoring = { a = "250;A;", b = "150;B;", c = "210;C;,1:1" } }
    saved.chars["High"].recipes = { Tailoring = { a = true, b = true, c = true } }
    wow.login(saved)
    eq(ns.SkillupCount(saved.chars["High"], "Tailoring"), 2, "skill 200: a and c")
    eq(ns.SkillupCount(saved.chars["High"], "Enchanting"), nil, "never scanned")
    SlashCmdList.ALTSFOREVER("")
    local row = overviewRows()[3] -- High
    row.scripts.OnEnter(row)
    local text = textOf(GameTooltip.lines)
    assert(text:find("Tailoring = 200  " .. G .. "(2 skill-up recipes)|r", 1, true), text)
    assert(text:find("Enchanting = 180\n", 1, true) or text:find("Enchanting = 180$"), text)
    SlashCmdList.ALTSFOREVER("skillups")
    row.scripts.OnEnter(row)
    text = textOf(GameTooltip.lines)
    assert(text:find("Tailoring = 200\n", 1, true) or text:find("Tailoring = 200$"), "toggle off: plain skill\n" .. text)
end)

test("each profession's rank maximum is recorded", function()
    local ns = wow.load(FILES)
    wow.profs = { { "Engineering", 75, 75 }, { "Mining", 99, 150 } }
    wow.login(nil)
    eq(ns.char.profMax.Engineering, 75); eq(ns.char.profMax.Mining, 150)
    eq(ns.AtRankCap(ns.char, "Engineering"), true)
    eq(ns.AtRankCap(ns.char, "Mining"), false)
    eq(ns.AtRankCap({ profs = { Mining = 75 } }, "Mining"), false, "saved before 0.3.0: no maximum, not capped")
end)

test("a character at their rank cap gets no skill-up lines", function()
    wow.load(FILES)
    wow.login({ v = 2, recipeInfo = { Tailoring = { cap = "100;Cap;,2589:1" } }, chars = {
        ["Ann Bee"] = alt("Ann Bee", "PRIEST", { profs = { Tailoring = 75 }, profMax = { Tailoring = 75 },
            recipes = { Tailoring = { cap = true } }, crafts = { Tailoring = { [777] = "cap" } } }),
        ["Bo Cee"] = alt("Bo Cee", "ROGUE", { profs = { Tailoring = 75 }, profMax = { Tailoring = 150 },
            recipes = { Tailoring = { cap = true } }, crafts = { Tailoring = { [777] = "cap" } } }),
    } })
    local lines = wow.hover(GameTooltip, LINEN)
    eq(lines[3][2], "[ROGUE]Bo" .. to(100)); eq(#lines, 3, "Ann at 75/75 can't skill up")
    eq(craftLine(wow.hover(GameTooltip, 777)), "[PRIEST]Ann Bee, [ROGUE]Bo Cee" .. skillupsTo(100))
end)

test("overview: at a rank cap it says to train; at 300 it says nothing extra", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    local saved = overviewAlts()
    saved.recipeInfo = { Tailoring = { a = "250;A;" }, Enchanting = { b = "300;B;" } }
    saved.chars["High"].profs = { Tailoring = 225, Enchanting = 300 }
    saved.chars["High"].profMax = { Tailoring = 225, Enchanting = 300 }
    saved.chars["High"].recipes = { Tailoring = { a = true }, Enchanting = { b = true } }
    wow.login(saved)
    eq(ns.SkillupCount(saved.chars["High"], "Tailoring"), 0)
    SlashCmdList.ALTSFOREVER("")
    local row = overviewRows()[3] -- High
    row.scripts.OnEnter(row)
    local text = textOf(GameTooltip.lines)
    assert(text:find("Tailoring = 225  " .. G .. "(train to skill up)|r", 1, true), text)
    assert(text:find("Enchanting = 300\n", 1, true) or text:find("Enchanting = 300$"), text)
end)

---------------------------------------------------------------------------
-- The game's recipe list can hold other professions' recipes (build 70009)
local VEST, WOLF_MEAT = 2847, 2679

-- A Blacksmithing window whose list also holds Cooking recipes, plus unlearned filler.
local function mixedWindow(extra)
    wow.tradeskill.prof = "Blacksmithing"
    local recipes = {
        [3001] = { name = "Rough Copper Vest", learned = true, item = VEST, grey = 55, reagents = { { 2840, 4 } } },
        [3002] = { name = "Charred Wolf Meat", learned = true, prof = "Cooking", item = WOLF_MEAT, grey = 85,
            reagents = { { 2672, 1 } } },
        [3003] = { name = "Copper Bracers", learned = false, grey = 60 },
    }
    for i = 1, (extra or 0) do recipes[4000 + i] = { name = "Filler " .. i, learned = false, grey = 100 } end
    wow.tradeskill.recipes = recipes
    wow.fire("TRADE_SKILL_SHOW")
end

test("a scan only records recipes of the window's profession", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    mixedWindow()
    eq(ns.char.recipes.Blacksmithing["rough copper vest"], true)
    eq(ns.char.recipes.Blacksmithing["charred wolf meat"], nil, "a Cooking recipe in the list")
    eq(ns.char.crafts.Blacksmithing[WOLF_MEAT], nil)
    eq(AltsForeverDB.recipeInfo.Blacksmithing["charred wolf meat"], nil)
    eq(AltsForeverDB.recipeInfo.Blacksmithing["rough copper vest"], "55;Rough Copper Vest;,2840:4")
end)

test("strays saved by 0.2.x are removed from every character, keeping the rest", function()
    local ns = wow.load(FILES)
    wow.login({ v = 2, recipeInfo = { Blacksmithing = {
        ["rough copper vest"] = "50;Rough Copper Vest;,2840:4",
        ["charred wolf meat"] = "85;Charred Wolf Meat;,2672:1",
        ["herb baked egg"] = "85;Herb Baked Egg;,6889:1",
    }, Leatherworking = {
        ["light leather"] = "60;Light Leather;,2934:3",
        ["pincer bites"] = "85;Pincer Bites;,2675:1", -- a stray nobody knows as Leatherworking
    } }, chars = {
        ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { recipes = { Leatherworking = { ["light leather"] = true } } }),
        ["Vesp Ash"] = alt("Vesp Ash", "PALADIN", { profs = { Blacksmithing = 40 },
            recipes = { Blacksmithing = { ["rough copper vest"] = true, ["charred wolf meat"] = true, ["herb baked egg"] = true } },
            crafts = { Blacksmithing = { [VEST] = "rough copper vest", [WOLF_MEAT] = "charred wolf meat", [777] = true } } }),
    } })
    mixedWindow()
    local v = AltsForeverDB.chars["Vesp Ash"]
    eq(v.recipes.Blacksmithing["rough copper vest"], true, "their real recipe stays: still Known")
    eq(v.recipes.Blacksmithing["charred wolf meat"], nil, "listed, but as Cooking")
    eq(v.recipes.Blacksmithing["herb baked egg"], nil, "not in Blacksmithing's list at all")
    eq(v.crafts.Blacksmithing[VEST], "rough copper vest")
    eq(v.crafts.Blacksmithing[WOLF_MEAT], nil)
    eq(v.crafts.Blacksmithing[777], true, "saved before 0.3.0: can't be checked, kept")
    local info = AltsForeverDB.recipeInfo.Blacksmithing
    eq(info["rough copper vest"], "55;Rough Copper Vest;,2840:4", "grey refreshed")
    eq(info["charred wolf meat"], nil); eq(info["herb baked egg"], nil)
    local lw = AltsForeverDB.recipeInfo.Leatherworking
    eq(lw["pincer bites"], nil, "strays under professions nobody opened are cleared too")
    eq(lw["light leather"], "60;Light Leather;,2934:3", "Tarn's real recipe stays")
end)

test("a list without the window's profession changes nothing", function()
    local ns = wow.load(FILES)
    wow.login({ v = 2, chars = { ["Aldric"] = alt("Aldric", "MAGE", {
        recipes = { Blacksmithing = { ["rough copper vest"] = true } } }) } })
    wow.tradeskill.prof = "Blacksmithing"
    wow.tradeskill.recipes = {
        [3002] = { name = "Charred Wolf Meat", learned = true, prof = "Cooking", item = WOLF_MEAT, grey = 85 },
        [3004] = { name = "Herb Baked Egg", learned = false, prof = "Cooking", grey = 85 },
    }
    wow.fire("TRADE_SKILL_SHOW")
    eq(ns.char.recipes.Blacksmithing["rough copper vest"], true, "not wiped")
    eq(ns.char.recipes.Blacksmithing["charred wolf meat"], nil)
    -- The right list arrives with the next update.
    mixedWindow()
    wow.fire("TRADE_SKILL_LIST_UPDATE")
    eq(ns.char.recipes.Blacksmithing["rough copper vest"], true)
end)

test("a new profession with nothing learned yet is still recorded as scanned", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    wow.tradeskill.prof = "Blacksmithing"
    wow.tradeskill.recipes = { [3003] = { name = "Copper Bracers", learned = false, grey = 60 } }
    wow.fire("TRADE_SKILL_SHOW")
    eq(type(ns.char.recipes.Blacksmithing), "table", "scanned, just empty")
end)

test("the profession check stays cheap: only learned and stored recipes", function()
    wow.load(FILES)
    wow.login(nil)
    wow.profLookups = 0
    mixedWindow(300) -- 303 recipes listed, 2 learned
    assert(wow.profLookups <= 3, "checked " .. wow.profLookups .. " of 303")
end)

test("/af delete also forgets recipes nobody else knows", function()
    wow.load(FILES)
    wow.login({ v = 2, recipeInfo = { Blacksmithing = {
        ["rough copper vest"] = "55;Rough Copper Vest;", ["copper bracers"] = "60;Copper Bracers;" } }, chars = {
        ["Mid"] = alt("Mid", "DRUID", { recipes = { Blacksmithing = { ["rough copper vest"] = true, ["copper bracers"] = true } } }),
        ["Aldric"] = alt("Aldric", "MAGE", { recipes = { Blacksmithing = { ["copper bracers"] = true } } }),
    } })
    SlashCmdList.ALTSFOREVER("delete mid")
    local info = AltsForeverDB.recipeInfo.Blacksmithing
    eq(info["rough copper vest"], nil, "only Mid knew it")
    eq(info["copper bracers"], "60;Copper Bracers;", "Aldric still knows it")
end)

---------------------------------------------------------------------------
-- Options: minimap compartment, menus, forgetting a character
test("minimap compartment: click opens the overview, right-click the options menu", function()
    wow.load(FILES)
    wow.login(nil)
    AltsForever_OnAddonCompartmentClick("AltsForever", "LeftButton", UIParent)
    eq(AltsForeverFrame:IsShown(), true)
    AltsForever_OnAddonCompartmentClick("AltsForever", "LeftButton", UIParent)
    eq(AltsForeverFrame:IsShown(), false, "click again closes it")
    AltsForever_OnAddonCompartmentClick("AltsForever", "RightButton", UIParent)
    local texts = {}
    for _, item in ipairs(wow.menu.items) do texts[#texts + 1] = item.text end
    eq(table.concat(texts, " | "), "Alts Forever | Open overview | Show skill-up details | Send mail to alts | Show session stats | Show minimap button | Memory use")
    wow.menuItem("Open overview").fn()
    eq(AltsForeverFrame:IsShown(), true)
    wow.menuItem("Open overview").fn()
    eq(AltsForeverFrame:IsShown(), true, "the menu only opens it")
    AltsForever_OnAddonCompartmentClick("AltsForever", "RightButton", UIParent)
    eq(wow.menuItem("Open overview"), nil, "not offered while the overview is open")
    AltsForeverFrame.cog.scripts.OnClick(AltsForeverFrame.cog)
    eq(wow.menuItem("Open overview"), nil, "nor from the overview's own cog")
    AltsForever_OnAddonCompartmentEnter("AltsForever", UIParent)
    eq(GameTooltip.lines[1][1], "Alts Forever")
    assert(GameTooltip.lines[3][1]:find("Right-click", 1, true))
end)

test("options menu: skill-up details tick box and memory", function()
    wow.load(FILES)
    wow.login(nil)
    SlashCmdList.ALTSFOREVER("")
    AltsForeverFrame.cog.scripts.OnClick(AltsForeverFrame.cog)
    local box = wow.menuItem("Show skill-up details")
    eq(box.kind, "checkbox"); eq(box.isSelected(), true)
    box.setSelected()
    eq(AltsForeverDB.skillupsOff, true); eq(box.isSelected(), false)
    box.setSelected()
    eq(AltsForeverDB.skillupsOff, nil)
    wow.printed = {}
    wow.menuItem("Memory use").fn()
    assert(table.concat(wow.printed, "\n"):find("Memory", 1, true), "same as /af mem")
end)

test("right-click a character in the overview to forget them, after confirming", function()
    wow.load(FILES)
    wow.now = NOW
    wow.login(overviewAlts())
    SlashCmdList.ALTSFOREVER("")
    local low = overviewRows()[4]
    eq(low.key, "Low")
    low.scripts.OnClick(low, "RightButton")
    eq(wow.menu.items[1].text, "[ROGUE]Low")
    eq(StaticPopupDialogs.ALTSFOREVER_FORGET, nil, "Blizzard's pop-up table untouched until needed")
    wow.menuItem("Forget Low...").fn()
    eq(wow.popup.which, "ALTSFOREVER_FORGET"); eq(wow.popup.text, "Low")
    eq(type(AltsForeverDB.chars["Low"]), "table", "nothing happens until confirmed")
    StaticPopupDialogs.ALTSFOREVER_FORGET.OnAccept(nil, wow.popup.data)
    eq(AltsForeverDB.chars["Low"], nil)
    eq(#overviewRows(), 3, "gone from the open overview")
    -- Your own row can't be forgotten.
    local you = overviewRows()[1]
    you.scripts.OnClick(you, "RightButton")
    eq(wow.menuItem("Forget Aldric...").enabled, false)
end)

test("no addon file assigns one of Blizzard's globals (that taints Blizzard's code)", function()
    -- Writing e.g. StaticPopupDialogs = ... from addon code made Esc's SpellStopCasting
    -- fail with ADDON_ACTION_FORBIDDEN. Adding keys to such tables is fine; replacing is not.
    local blizzard = { "StaticPopupDialogs", "UISpecialFrames", "GameTooltip", "ItemRefTooltip", "SlashCmdList",
        "UIParent", "MenuUtil", "Settings", "ChatFrame_DisplayTimePlayed", "SpellStopCasting", "ToggleGameMenu" }
    for _, file in ipairs(FILES) do
        local n = 0
        for line in io.lines(file) do
            n = n + 1
            local code = line:gsub("%-%-.*$", "")
            for _, name in ipairs(blizzard) do
                assert(not code:match("^%s*" .. name .. "%s*="), file .. ":" .. n .. " assigns " .. name)
                assert(not code:match("[,%s]" .. name .. "%s*=[^=]") or code:match("local"), file .. ":" .. n .. " assigns " .. name)
            end
        end
    end
end)

---------------------------------------------------------------------------
-- Reputation across characters
local function repWindow()
    wow.factions = {
        { 1, "Horde", 0, true },
        { 530, "Darkspear Trolls", 2150 },
        { 76, "Orgrimmar", 9500 },
        { 2, "Other", 0, true },
        { 87, "Bloodsail Buccaneers", -4000 },
    }
end

test("reputation is recorded shortly after login, headers skipped", function()
    local ns = wow.load(FILES)
    repWindow()
    wow.login(nil)
    eq(ns.char.reps, nil, "not during the login rush")
    for _, fn in ipairs(wow.timers) do fn() end
    eq(ns.char.reps[530], 2150); eq(ns.char.reps[76], 9500); eq(ns.char.reps[87], -4000)
    eq(ns.char.reps[1], nil, "headers aren't factions")
    eq(AltsForeverDB.factions[530], "Darkspear Trolls")
end)

test("reputation changes are batched: one scan per burst, 10 seconds later", function()
    local ns = wow.load(FILES)
    repWindow()
    wow.login(nil)
    runTimers()
    wow.timers = {}
    wow.factions[2][3] = 2200
    for _ = 1, 20 do wow.fire("UPDATE_FACTION") end -- a kill streak
    eq(#wow.timers, 1, "one scan scheduled for the whole burst")
    eq(ns.char.reps[530], 2150, "not yet")
    runTimers()
    eq(ns.char.reps[530], 2200)
    wow.fire("UPDATE_FACTION")
    eq(#wow.timers, 1, "the next burst schedules again")
end)

test("factions under a collapsed header stay current, without touching the player's window", function()
    local ns = wow.load(FILES)
    repWindow()
    wow.login({ v = 2, chars = { ["Aldric"] = alt("Aldric", "MAGE", { reps = { [69] = 3000, [530] = 100 } }) } })
    wow.hiddenFactions = { { 69, "Darnassus", 3500 } } -- its header is collapsed now
    runTimers()
    eq(ns.char.reps[69], 3500, "re-read by ID")
    eq(ns.char.reps[530], 2150)
    eq(wow.expanded, nil, "headers are never expanded")
end)

test("standing levels and text", function()
    local ns = wow.load(FILES)
    eq((ns.Standing(2150)), 4); eq((ns.Standing(3000)), 5); eq((ns.Standing(-1)), 3); eq((ns.Standing(42999)), 8)
    eq(ns.StandingText(2150), "|cffffff00Neutral 71%|r")
    eq(ns.StandingText(12000), "|cff00ff88Honored 25%|r")
    eq(ns.StandingText(42500), "|cff00ffffExalted|r")
    eq(ns.StandingText(-42000), "|cffcc2222Hated 0%|r")
end)

test("reputation panel: factions down, characters across, you first", function()
    wow.load(FILES)
    repWindow()
    wow.login({ v = 2, factions = { [530] = "Darkspear Trolls", [76] = "Orgrimmar", [69] = "Darnassus" }, chars = {
        ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { level = 30, reps = { [530] = 9000, [69] = 3000 } }),
    } })
    runTimers()
    SlashCmdList.ALTSFOREVER("")
    AltsForeverFrame.repButton.scripts.OnClick(AltsForeverFrame.repButton)
    local f = AltsForeverRepFrame
    eq(f:IsShown(), true)
    -- Rows are the panel's frames with a faction; read their text.
    local lines = {}
    for _, row in ipairs(wow.frames) do
        if row.faction then
            local t = { row.name.text }
            for j, cell in ipairs(row.cells) do t[j + 1] = cell.text end
            lines[#lines + 1] = table.concat(t, " | ")
        end
    end
    table.sort(lines)
    eq(lines[1], "Bloodsail Buccaneers | |cffff0000Hostile 66%|r | " .. G .. "-|r")
    eq(lines[2], "Darkspear Trolls | |cffffff00Neutral 71%|r | |cff00ff88Honored 0%|r", "you, then Tarn")
    eq(lines[3], "Darnassus | " .. G .. "-|r | |cff00ff00Friendly 0%|r")
    eq(lines[4], "Orgrimmar | |cff00ff88Honored 4%|r | " .. G .. "-|r")
    AltsForeverFrame:Hide()
    eq(f:IsShown(), false, "closing the overview closes it")
end)

---------------------------------------------------------------------------
-- "Send to alt" at the mailbox
-- Your alts: Tarn (First Aid 40, knows Linen Bandage, grey 80), Brak (First Aid 100, past
-- grey), Ally (other faction), plus you.
local function mailAlts()
    return { v = 2, recipeInfo = { ["First Aid"] = { ["linen bandage"] = "80;Linen Bandage;,2589:1" } }, chars = {
        ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { faction = "Alliance", level = 20, profs = { ["First Aid"] = 40 },
            recipes = { ["First Aid"] = { ["linen bandage"] = true } } }),
        ["Brak Stone"] = alt("Brak Stone", "WARRIOR", { faction = "Alliance", level = 30, profs = { ["First Aid"] = 100 },
            recipes = { ["First Aid"] = { ["linen bandage"] = true } } }),
        ["Horde Guy"] = alt("Horde Guy", "ROGUE", { faction = "Horde", level = 40 }),
    } }
end

local function altsButton()
    for _, f in ipairs(wow.frames) do
        if f.kind == "Button" and f.alts then return f end
    end
end

test("send to alt: an Alts button appears beside the To box when the mailbox opens", function()
    wow.load(FILES)
    wow.login(mailAlts())
    eq(altsButton(), nil, "not before the mailbox opens")
    wow.fire("MAIL_SHOW")
    local b = altsButton()
    assert(b, "button made")
    wow.fire("MAIL_CLOSED") wow.fire("MAIL_SHOW")
    local n = 0
    for _, f in ipairs(wow.frames) do if f.alts then n = n + 1 end end
    eq(n, 1, "made once")
end)

test("send to alt: picking a character fills in the To box; own faction only", function()
    wow.load(FILES)
    wow.login(mailAlts())
    wow.fire("MAIL_SHOW")
    local b = altsButton()
    b.scripts.OnClick(b)
    local texts = {}
    for _, item in ipairs(wow.menu.items) do texts[#texts + 1] = item.text end
    eq(table.concat(texts, " | "), "Send to | [WARRIOR]Brak Stone | [DRUID]Tarn Moon", "no Horde, not you")
    wow.menuItem("[DRUID]Tarn Moon").fn()
    eq(SendMailNameEditBox:GetText(), "Tarn Moon")
end)

test("send to alt: characters who can skill up with the attachments are marked and first", function()
    wow.load(FILES)
    wow.login(mailAlts())
    wow.outbox = { { 2589, 20 }, [3] = { 4306, 5 } } -- Linen Cloth, Silk Cloth
    wow.fire("MAIL_SHOW")
    local b = altsButton()
    b.scripts.OnClick(b)
    eq(wow.menu.items[2].text, "[DRUID]Tarn Moon|cffc0c0c0 · skill-ups with 1 item|r", "Tarn first: can use the linen")
    eq(wow.menu.items[3].text, "[WARRIOR]Brak Stone", "Brak is past grey 80")
    SlashCmdList.ALTSFOREVER("skillups")
    b.scripts.OnClick(b)
    eq(wow.menu.items[2].text, "[WARRIOR]Brak Stone", "skill-up details off: plain list, by level")
end)
test("send to alt can be turned off and on from the options menu", function()
    wow.load(FILES)
    wow.login(mailAlts())
    AltsForever_OnAddonCompartmentClick("AltsForever", "RightButton", UIParent)
    local box = wow.menuItem("Send mail to alts")
    eq(box.kind, "checkbox"); eq(box.isSelected(), true)
    box.setSelected()
    eq(AltsForeverDB.sendToAltOff, true)
    wow.fire("MAIL_SHOW")
    eq(altsButton(), nil, "off: no arrow at the mailbox")
    box.setSelected()
    wow.fire("MAIL_CLOSED") wow.fire("MAIL_SHOW")
    local b = altsButton()
    eq(b:IsShown(), true, "on again")
    box.setSelected()
    eq(b:IsShown(), false, "turning it off hides an existing arrow")
    box.setSelected()
    eq(b:IsShown(), true)
end)

---------------------------------------------------------------------------
-- EllesmereUI look (its public skinning API)
local function skinnedWith(fname, obj)
    for _, call in ipairs(wow.skinned) do
        if call[1] == fname and call[2] == obj then return true end
    end
    return false
end

test("without EllesmereUI nothing is skinned: the classic look stays", function()
    wow.load(FILES)
    wow.login(nil)
    SlashCmdList.ALTSFOREVER("")
    eq(#wow.skinned, 0); eq(EllesmereUI, nil)
end)

test("with EllesmereUI, every window takes its look when first created", function()
    wow.withEllesmere = true
    wow.load(FILES)
    wow.now = NOW
    eq(wow.skinName, "AltsForever", "registered under the addon's folder name")
    wow.login(overviewAlts())
    wow.skinCallback(wow.skinFacade) -- EllesmereUI calls this at login
    SlashCmdList.ALTSFOREVER("")
    local f = AltsForeverFrame
    assert(skinnedWith("Shell", f), "overview backdrop")
    local row = overviewRows()[1]
    assert(skinnedWith("Font", row.cells[1]), "row text in the player's font")
    row.scripts.OnClick(row) -- gear panel
    assert(skinnedWith("Shell", AltsForeverGearFrame), "gear panel")
    AltsForeverFrame.repButton.scripts.OnClick(AltsForeverFrame.repButton)
    assert(skinnedWith("Shell", AltsForeverRepFrame), "reputation panel")
end)

test("a window opened before EllesmereUI's callback is skinned when it arrives", function()
    wow.withEllesmere = true
    wow.load(FILES)
    wow.login(nil)
    SlashCmdList.ALTSFOREVER("")
    eq(#wow.skinned, 0, "nothing until EllesmereUI hands over its style")
    wow.skinCallback(wow.skinFacade)
    assert(skinnedWith("Shell", AltsForeverFrame))
end)

test("if the player turned our skinning off in EllesmereUI, nothing is skinned", function()
    wow.withEllesmere = true
    wow.load(FILES)
    wow.login(nil)
    -- EllesmereUI never calls back when its third-party skinning is off for us.
    SlashCmdList.ALTSFOREVER("")
    eq(#wow.skinned, 0)
end)

---------------------------------------------------------------------------
-- Class colours: EllesmereUI's, then CUSTOM_CLASS_COLORS, then Blizzard's
-- With one character there's no Total line: the name is on line 2.
local function tooltipName(itemID)
    return wow.hover(GameTooltip, itemID)[2][1]
end

test("names use EllesmereUI's class colours when it's installed", function()
    wow.withEllesmere = true
    wow.load(FILES)
    EllesmereUI.GetClassColor = function(class) return class == "MAGE" and { r = 1, g = 0.5, b = 0 } or EllesmereUI._COLOR_WHITE end
    EllesmereUI._COLOR_WHITE = { r = 1, g = 1, b = 1 }
    wow.setBag(0, 16, { [1] = { 100, 2 } })
    wow.login(nil)
    eq(tooltipName(100), "|cffff8000Aldric|r")
end)

test("anything unexpected from EllesmereUI falls back to Blizzard's colour", function()
    for _, bad in ipairs({
        function() error("changed API") end,
        function() return "not a colour" end,
        function() return EllesmereUI._COLOR_WHITE end, -- its "unknown class"
    }) do
        wow.withEllesmere = true
        wow.load(FILES)
        EllesmereUI._COLOR_WHITE = { r = 1, g = 1, b = 1 }
        EllesmereUI.GetClassColor = bad
        wow.setBag(0, 16, { [1] = { 100, 2 } })
        wow.login(nil)
        eq(tooltipName(100), "[MAGE]Aldric")
    end
end)

test("names use CUSTOM_CLASS_COLORS (e.g. !ClassColors) when present", function()
    wow.load(FILES)
    CUSTOM_CLASS_COLORS = { MAGE = { r = 0, g = 1, b = 0 } }
    wow.setBag(0, 16, { [1] = { 100, 2 } })
    wow.login(nil)
    eq(tooltipName(100), "|cff00ff00Aldric|r")
end)

test("a live EllesmereUI look change recolours names", function()
    wow.withEllesmere = true
    wow.load(FILES)
    EllesmereUI._COLOR_WHITE = { r = 1, g = 1, b = 1 }
    local colour = { r = 1, g = 0, b = 0 }
    EllesmereUI.GetClassColor = function() return colour end
    wow.setBag(0, 16, { [1] = { 100, 2 } })
    wow.login(nil)
    wow.skinCallback(wow.skinFacade)
    eq(tooltipName(100), "|cffff0000Aldric|r")
    colour = { r = 0, g = 0, b = 1 }
    eq(tooltipName(100), "|cffff0000Aldric|r", "cached until told")
    wow.looksChanged()
    eq(tooltipName(100), "|cff0000ffAldric|r")
end)

---------------------------------------------------------------------------
-- ElvUI look (its Skins module)
test("with ElvUI, every window takes its look when first created", function()
    wow.withElvUI = true
    wow.load(FILES)
    wow.now = NOW
    wow.login(overviewAlts())
    SlashCmdList.ALTSFOREVER("")
    local f = AltsForeverFrame
    assert(skinnedWith("HandleFrame", f), "overview: backdrop, inset, close button")
    assert(skinnedWith("CreateBackdrop", f.cog) and skinnedWith("CreateBackdrop", f.repButton), "icon buttons")
    assert(skinnedWith("SetTexCoords", f.cog:GetNormalTexture()), "icon edges cropped")
    assert(skinnedWith("FontTemplate", overviewRows()[1].cells[1]), "row text in ElvUI's font")
    assert(skinnedWith("FontTemplate", f.credit), "text the window already had")
    local row = overviewRows()[1]
    row.scripts.OnClick(row)
    assert(skinnedWith("HandleFrame", AltsForeverGearFrame), "gear panel")
    local slots = 0
    for _, call in ipairs(wow.skinned) do
        if call[1] == "CreateBackdrop" and call[2] ~= f.cog and call[2] ~= f.repButton then slots = slots + 1 end
    end
    eq(slots, 19, "every gear slot")
    f.repButton.scripts.OnClick(f.repButton)
    assert(skinnedWith("HandleFrame", AltsForeverRepFrame), "reputation panel")
end)

test("with ElvUI, the mail window's Alts arrow gets its arrow style, clear of the To box", function()
    wow.withElvUI = true
    wow.load(FILES)
    wow.login(mailAlts())
    wow.fire("MAIL_SHOW")
    local b = altsButton()
    assert(skinnedWith("HandleNextPrevButton", b))
    eq(b.point[1], "LEFT"); eq(b.point[2], SendMailNameEditBox); eq(b.point[4], 3)
end)

test("before ElvUI has initialised nothing is skinned; afterwards it is", function()
    wow.withElvUI = true
    wow.load(FILES)
    wow.elv.Initialized = nil
    wow.setBag(0, 16, { [1] = { 100, 2 } })
    wow.login(nil)
    wow.hover(GameTooltip, 100)
    eq(#wow.skinned, 0)
    wow.elv.Initialized = true
    SlashCmdList.ALTSFOREVER("")
    assert(skinnedWith("HandleFrame", AltsForeverFrame))
end)

test("an error inside ElvUI's skinning never stops our windows opening", function()
    wow.withElvUI = true
    wow.load(FILES)
    wow.elvSkins.HandleFrame = function() error("changed API") end
    wow.elvSkins.HandleNextPrevButton = function() error("changed API") end
    wow.login(mailAlts())
    SlashCmdList.ALTSFOREVER("")
    eq(AltsForeverFrame:IsShown(), true)
    wow.fire("MAIL_SHOW")
    assert(altsButton(), "Alts arrow still made")
end)

test("with both EllesmereUI and ElvUI installed, EllesmereUI's look wins", function()
    wow.withEllesmere, wow.withElvUI = true, true
    wow.load(FILES)
    wow.login(nil)
    wow.skinCallback(wow.skinFacade)
    SlashCmdList.ALTSFOREVER("")
    assert(skinnedWith("Shell", AltsForeverFrame))
    eq(skinnedWith("HandleFrame", AltsForeverFrame), false)
end)

test("a live change to CUSTOM_CLASS_COLORS (ElvUI, !ClassColors) recolours names", function()
    wow.load(FILES)
    local listeners = {}
    CUSTOM_CLASS_COLORS = { MAGE = { r = 0, g = 1, b = 0 },
        RegisterCallback = function(self, fn) listeners[#listeners + 1] = fn end }
    wow.setBag(0, 16, { [1] = { 100, 2 } })
    wow.login(nil)
    eq(tooltipName(100), "|cff00ff00Aldric|r")
    CUSTOM_CLASS_COLORS.MAGE = { r = 1, g = 0, b = 0 }
    eq(tooltipName(100), "|cff00ff00Aldric|r", "cached until told")
    eq(#listeners, 1)
    listeners[1]()
    eq(tooltipName(100), "|cffff0000Aldric|r")
end)

---------------------------------------------------------------------------
-- XP bar tooltip
local function lineTexts(tt)
    local t = {}
    for _, l in ipairs(tt.lines) do t[#t + 1] = l[1] end
    return table.concat(t, " | ")
end

-- Blizzard's bars: in a status tracking container by kind, reputation first and
-- experience 4th (marked by its rested tick), as checked in game.
local function blizzardBars()
    MainStatusTrackingBarContainer = CreateFrame("Frame")
    local bars = {}
    for i = 1, 6 do bars[i] = CreateFrame("Frame") end
    bars[4].ExhaustionTick = CreateFrame("Frame")
    MainStatusTrackingBarContainer.bars = bars
    return bars[4], bars[1]
end
local function blizzardXPBar() return (blizzardBars()) end

test("hovering Blizzard's XP bar lists every character still levelling", function()
    wow.load(FILES)
    wow.now = NOW
    local bar = blizzardXPBar()
    wow.login(overviewAlts())
    wow.fire("PLAYER_ENTERING_WORLD")
    bar.scripts.OnEnter(bar)
    eq(GameTooltip:GetOwner(), bar); eq(GameTooltip:IsShown(), true)
    eq(lineTexts(GameTooltip), "Experience | Your characters | [PRIEST]High | [ROGUE]Low",
        "by level; not you (the bar shows you), not max level (Far)")
    local low = GameTooltip.lines[4][2]
    assert(low:find("^12  ") and low:find("10%%") and low:find("rested"), low)
    bar.scripts.OnLeave(bar)
    eq(GameTooltip:IsShown(), false)
    -- Hooked once, however many loading screens.
    wow.fire("PLAYER_ENTERING_WORLD")
    bar.scripts.OnEnter(bar)
    eq(#GameTooltip.lines, 4)
end)

test("the XP bar's columns are lined up by measuring them in the tooltip's font", function()
    wow.load(FILES)
    wow.now = NOW
    local bar = blizzardXPBar()
    -- A tooltip whose lines have font strings, and text 6 units per visible character.
    GameTooltip.GetName = function() return "GameTooltip" end
    GameTooltip.NumLines = function(self) return #self.lines end
    local function spacers(t)
        local w = {}
        for n in t:gmatch("blank%.tga:1:(%d+)|t") do w[#w + 1] = tonumber(n) end
        return w
    end
    -- Width as drawn: 6 per visible character, spacers their width.
    local function width(t)
        local visible = t:gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        local sum = #visible * 6
        for _, n in ipairs(spacers(t)) do sum = sum + n end
        return sum
    end
    -- Line 2 has the tooltip's body font; lines 3 on are new lines in the game's default.
    local rights, lefts = {}, {}
    local function fontString(i)
        local size = i <= 2 and 12 or 14
        return { GetFont = function(self) return self.font or "font", self.size or size, "" end,
            SetFont = function(self, f, s) self.font, self.size = f, s end,
            SetText = function(self, t) self.text = t end, GetText = function(self) return self.text end,
            GetStringWidth = function(self) return width(self.text or "") end }
    end
    for i = 1, 10 do
        rights[i], lefts[i] = fontString(i), fontString(i)
        _G["GameTooltipTextRight" .. i], _G["GameTooltipTextLeft" .. i] = rights[i], lefts[i]
    end
    GameTooltip.CreateFontString = function()
        return { SetPoint = function() end, SetAlpha = function() end, SetFont = function() end,
            SetText = function(self, t) self.text = t end,
            GetStringWidth = function(self) return width(self.text or "") end }
    end
    wow.login(overviewAlts())
    wow.fire("PLAYER_ENTERING_WORLD")
    bar.scripts.OnEnter(bar)
    -- High: level 40, 0%, rested 150% (full); Low: 12, 10%, rested ...
    local high, low = rights[3].text, rights[4].text
    assert(high and low, "rows 3 and 4 rewritten")
    -- Same total width per row: each column padded to its widest value.
    eq(width(high), width(low), "rows end up the same width")
    for i = 2, 4 do
        eq(select(2, lefts[i]:GetFont()), 12, "left text of line " .. i .. " in the body font")
        eq(select(2, rights[i]:GetFont()), 12, "right text of line " .. i)
    end
    assert(high:find("Interface\\AddOns\\AltsForever\\media\\blank.tga", 1, true), "our spacer texture")
    for i = 1, 10 do _G["GameTooltipTextRight" .. i], _G["GameTooltipTextLeft" .. i] = nil, nil end
end)

test("the XP bar adds nothing when you're the only character levelling", function()
    wow.load(FILES)
    local bar = blizzardXPBar()
    wow.login({ v = 2, chars = { ["Far"] = alt("Far", "MAGE", { level = 60 }) } })
    wow.fire("PLAYER_ENTERING_WORLD")
    bar.scripts.OnEnter(bar)
    eq(GameTooltip:IsShown(), false)
end)

test("ElvUI's and EllesmereUI's XP bar tooltips get the lines added at the end", function()
    for _, name in ipairs({ "ElvUI_ExperienceBarHolder", "EllesmereEAB_XPBar" }) do
        wow.load(FILES)
        wow.now = NOW
        local bar = CreateFrame("Frame", name)
        local ownTooltip = true
        bar:SetScript("OnEnter", function(self)
            if not ownTooltip then return end -- click-through, or at max level
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:AddLine("Experience")
            GameTooltip:Show()
        end)
        wow.login(overviewAlts())
        wow.fire("PLAYER_ENTERING_WORLD")
        bar.scripts.OnEnter(bar)
        eq(lineTexts(GameTooltip), "Experience |   | Your characters | [PRIEST]High | [ROGUE]Low", name)
        GameTooltip:Hide()
        ownTooltip = false
        bar.scripts.OnEnter(bar)
        eq(GameTooltip:IsShown(), false, name .. ": no tooltip of our own where theirs is off")
    end
end)

local function repAlts()
    return { v = 2, factions = { [530] = "Darkspear Trolls" }, chars = {
        ["Aldric"] = alt("Aldric", "MAGE", { level = 24, reps = { [530] = 100 } }),
        ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { level = 30, reps = { [530] = 3500 } }),
        ["Brak Stone"] = alt("Brak Stone", "WARRIOR", { level = 20, reps = { [530] = 42500 } }),
        ["Horde Guy"] = alt("Horde Guy", "ROGUE", { level = 10, reps = { [76] = 100 } }),
    } }
end

test("hovering the reputation bar lists your other characters' standing with that faction", function()
    wow.load(FILES)
    local _, bar = blizzardBars()
    wow.watched = { factionID = 530, name = "Darkspear Trolls" }
    wow.login(repAlts())
    wow.fire("PLAYER_ENTERING_WORLD")
    bar.scripts.OnEnter(bar)
    eq(GameTooltip:GetOwner(), bar)
    eq(lineTexts(GameTooltip), "Darkspear Trolls | Your characters | [DRUID]Tarn Moon | [WARRIOR]Brak Stone",
        "not you, not characters without it")
    local tarn, brak = GameTooltip.lines[3][2], GameTooltip.lines[4][2]
    assert(tarn:find("Friendly") and tarn:find("8%%") and tarn:find("500 / 6000"), tarn)
    assert(brak:find("Exalted") and not brak:find("%%"), brak)
    bar.scripts.OnLeave(bar)
    eq(GameTooltip:IsShown(), false)
end)

test("the reputation bar adds nothing without a watched faction or another character with it", function()
    wow.load(FILES)
    local _, bar = blizzardBars()
    wow.login(repAlts())
    wow.fire("PLAYER_ENTERING_WORLD")
    bar.scripts.OnEnter(bar)
    eq(GameTooltip:IsShown(), false, "nothing watched")
    wow.watched = { factionID = 999, name = "Nobody's" }
    bar.scripts.OnEnter(bar)
    eq(GameTooltip:IsShown(), false, "no one else has it")
end)

test("ElvUI's and EllesmereUI's reputation bar tooltips get the lines added at the end", function()
    for _, name in ipairs({ "ElvUI_ReputationBarHolder", "EllesmereEAB_RepBar" }) do
        wow.load(FILES)
        local bar = CreateFrame("Frame", name)
        bar:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:AddLine("Darkspear Trolls")
            GameTooltip:Show()
        end)
        wow.watched = { factionID = 530, name = "Darkspear Trolls" }
        wow.login(repAlts())
        wow.fire("PLAYER_ENTERING_WORLD")
        bar.scripts.OnEnter(bar)
        eq(lineTexts(GameTooltip), "Darkspear Trolls |   | Your characters | [DRUID]Tarn Moon | [WARRIOR]Brak Stone", name)
    end
end)

test("everything in the menus can also be done with a command", function()
    wow.load(FILES)
    wow.login(mailAlts())
    SlashCmdList.ALTSFOREVER("minimap")
    eq(AltsForeverMinimapButton:IsShown(), false); eq(AltsForeverDB.minimapHidden, true)
    assert(wow.printed[#wow.printed]:find("/af minimap brings it back", 1, true))
    SlashCmdList.ALTSFOREVER("minimap")
    eq(AltsForeverMinimapButton:IsShown(), true); eq(AltsForeverDB.minimapHidden, nil)
    SlashCmdList.ALTSFOREVER("sendmail")
    eq(AltsForeverDB.sendToAltOff, true)
    wow.fire("MAIL_SHOW")
    eq(altsButton(), nil, "no arrow while it's off")
    SlashCmdList.ALTSFOREVER("sendmail")
    eq(AltsForeverDB.sendToAltOff, nil)
    SlashCmdList.ALTSFOREVER("rep")
    eq(AltsForeverRepFrame:IsShown(), true)
    SlashCmdList.ALTSFOREVER("rep")
    eq(AltsForeverRepFrame:IsShown(), false)
    SlashCmdList.ALTSFOREVER("help")
    local help = table.concat(wow.printed, "\n")
    assert(help:find("rep | mail | list | delete Name | skillups | sendmail | minimap | stats | mem", 1, true), help)
end)

---------------------------------------------------------------------------
-- EllesmereUIBags: its money display shows its own gold summary unless its gold
-- tracking is off; then ours.
local function ellesmereBags(trackingOff)
    wow.withEllesmere = true
    wow.load(FILES)
    local profile = {}
    if trackingOff then profile.enableGoldTracking = false end
    EllesmereUI._bagsDB = { profile = profile }
    EUI_Bags = CreateFrame("Frame", "EUI_MainBagFrame")
    local footer = CreateFrame("Frame")
    EUI_BagMoneyFrame = CreateFrame("Frame", "EUI_BagMoneyFrame")
    EUI_BagMoneyFrame.parent = footer
    local hitbox = CreateFrame("Frame")
    hitbox.parent = footer
    hitbox:SetPoint("BOTTOMRIGHT", EUI_BagMoneyFrame, "BOTTOMRIGHT", 5, -5)
    hitbox:SetScript("OnEnter", function() end) -- EllesmereUI's own summary
    footer.children = { EUI_BagMoneyFrame, hitbox }
    wow.login({ v = 2, chars = { ["Brak Stone"] = alt("Brak Stone", "WARRIOR", { money = 5000 }) } })
    EUI_Bags.scripts.OnShow(EUI_Bags)
    return hitbox
end

test("EllesmereUIBags' money shows its own gold summary while its gold tracking is on", function()
    local hitbox = ellesmereBags(false)
    hitbox.scripts.OnEnter(hitbox)
    eq(GameTooltip:IsShown() or false, false, "ours stays out of the way")
end)

test("with EllesmereUIBags' gold tracking off, its money shows our gold across characters", function()
    local hitbox = ellesmereBags(true)
    hitbox.scripts.OnEnter(hitbox)
    eq(GameTooltip:IsShown(), true); eq(GameTooltip:GetOwner(), hitbox)
    eq(GameTooltip.lines[1][1], "Gold")
    EllesmereUI._bagsDB.profile.enableGoldTracking = nil -- turned back on: theirs again
    GameTooltip:Hide()
    hitbox.scripts.OnEnter(hitbox)
    eq(GameTooltip:IsShown(), false)
    -- Hooked once, however often the bags open.
    EllesmereUI._bagsDB.profile.enableGoldTracking = false
    EUI_Bags.scripts.OnShow(EUI_Bags)
    hitbox.scripts.OnEnter(hitbox)
    local golds = 0
    for _, l in ipairs(GameTooltip.lines) do if l[1] == "Gold" then golds = golds + 1 end end
    eq(golds, 1)
    hitbox.scripts.OnLeave(hitbox)
    eq(GameTooltip:IsShown(), false)
end)

test("ElvUI's bags: hovering the gold shows our gold across characters", function()
    wow.load(FILES)
    ElvUI_ContainerFrame = CreateFrame("Frame", "ElvUI_ContainerFrame")
    local area = CreateFrame("Button")
    ElvUI_ContainerFrame.pickupGold = area
    wow.login({ v = 2, chars = { ["Brak Stone"] = alt("Brak Stone", "WARRIOR", { money = 5000 }) } })
    wow.fire("PLAYER_ENTERING_WORLD")
    wow.fire("PLAYER_ENTERING_WORLD") -- hooked once
    area.scripts.OnEnter(area)
    eq(GameTooltip:GetOwner(), area)
    local golds = 0
    for _, l in ipairs(GameTooltip.lines) do if l[1] == "Gold" then golds = golds + 1 end end
    eq(golds, 1)
    area.scripts.OnLeave(area)
    eq(GameTooltip:IsShown(), false)
end)

---------------------------------------------------------------------------
-- Item tooltip columns
-- A tooltip whose lines have font strings, in a font whose characters are size / 2 wide
-- (icons 12, our blank spacers their given width times spacerDraw), so a font change
-- changes widths. In game the tooltip drew spacers at about 87% of the width asked for.
local spacerDraw = 1
local function visibleWidth(t, size)
    local w = 0
    t = t:gsub("|T[^|]-blank%.tga:1:(%d+)|t", function(n) w = w + tonumber(n) * spacerDraw return "" end)
    t = t:gsub("|T.-|t", function() w = w + 12 return "" end)
    t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return w + #t * (size or 12) / 2
end

local function measurableTooltip()
    wow.ownDraw = 1
    GameTooltip.GetName = function() return "GameTooltip" end
    GameTooltip.NumLines = function(self) return #self.lines end
    GameTooltip.hooks = {}
    GameTooltip.HookScript = function(self, script, fn) self.hooks[script] = fn end
    local rights = {}
    for i = 1, 20 do
        local function fontString()
            return { size = 12, GetFont = function(self) return "font", self.size, "" end,
                SetFont = function(self, _, s) self.size = s end,
                SetText = function(self, t) self.text = t end, GetText = function(self) return self.text end,
                GetStringWidth = function(self)
                    wow.measured = (wow.measured or 0) + 1
                    -- In game a secret width is still a number; only issecretvalue tells.
                    if wow.secretWidths then
                        wow.SECRET = 4242.5
                        return 4242.5
                    end
                    return visibleWidth(self.text or "", self.size)
                end }
        end
        _G["GameTooltipTextLeft" .. i] = fontString()
        rights[i] = fontString()
        _G["GameTooltipTextRight" .. i] = rights[i]
    end
    -- Our measuring font string on the tooltip: text widths as the lines, but it gets
    -- spacers wrong (wow.ownDraw scales everything it measures when set below 1 to show
    -- that only text is measured there), as in game.
    GameTooltip.CreateFontString = function()
        return { SetPoint = function() end, SetAlpha = function() end,
            SetFont = function(self, _, s) self.size = s end,
            SetText = function(self, t) self.text = t end,
            GetStringWidth = function(self)
                wow.measured = (wow.measured or 0) + 1
                return visibleWidth(self.text or "", self.size) * wow.ownDraw
            end }
    end
    return rights
end

local function clearTooltipLines()
    for i = 1, 20 do _G["GameTooltipTextLeft" .. i], _G["GameTooltipTextRight" .. i] = nil, nil end
end

-- The width of a row's text up to where its count starts (the last spacer).
local function beforeCount(t, size)
    return visibleWidth(t:match("^(.*)|T[^|]-blank%.tga:1:%d+|t%d+$") or "", size)
end

-- Each place's icon: its distance from the right edge, nearest the count first.
local function iconsFromEnd(t, size)
    local total, found = visibleWidth(t, size), {}
    local pos = 1
    while true do
        local a, b = t:find("|T.-|t", pos)
        if not a then break end
        if not t:sub(a, b):find("blank.tga", 1, true) then
            table.insert(found, 1, total - visibleWidth(t:sub(1, a - 1), size))
        end
        pos = b + 1
    end
    return found
end

-- Checks the rows line up in a font of the given size.
local function checkColumns(rows, size)
    local width = visibleWidth(rows[1], size)
    -- Spacers are whole units, so allow up to half a unit.
    local function near(a, b, msg) assert(math.abs(a - b) <= 0.5, msg .. ": " .. a .. " vs " .. b) end
    -- Whole rows may differ by up to a unit of rounding: right-aligned, that only moves
    -- the (empty) left edge.
    for i, t in ipairs(rows) do assert(math.abs(visibleWidth(t, size) - width) <= 1, "row " .. i .. " width") end
    -- Where the last place ends, counted from the right edge.
    local function lastPlace(t) return visibleWidth(t, size) - beforeCount(t, size) end
    assert(beforeCount(rows[1], size) > 0, rows[1])
    local edge = lastPlace(rows[1])
    for i, t in ipairs(rows) do near(lastPlace(t), edge, "row " .. i .. " last place") end
    local columns = {}
    for i, t in ipairs(rows) do
        for col, x in ipairs(iconsFromEnd(t, size)) do
            if columns[col] then near(x, columns[col], "row " .. i .. ", icon " .. col .. " from the right")
            else columns[col] = x end
        end
    end
    return #columns
end

local function columnAlts()
    wow.setBag(0, 16, { [1] = { 100, 23 } })
    wow.login({ v = 2, chars = {
        ["Big"] = alt("Big", "PRIEST", { bags = { [100] = 30 }, mail = { [100] = 1000 } }),
        ["Mid"] = alt("Mid", "DRUID", { bank = { [100] = 5 } }),
        ["Three"] = alt("Three", "ROGUE", { bags = { [100] = 4 }, bank = { [100] = 6 }, mail = { [100] = 7 } }),
    } })
end

local function rowTexts(rights, lines)
    local rows = {}
    for i = 3, #lines do rows[#rows + 1] = rights[i].text end
    return rows
end

test("item tooltip: places and counts line up in columns, from the right", function()
    wow.load(FILES)
    local rights = measurableTooltip()
    columnAlts()
    local lines = wow.hover(GameTooltip, 100)
    eq(lines[2][1], "Total"); eq(lines[2][2], 1075)
    local rows = rowTexts(rights, lines)
    eq(#rows, 4)
    eq(checkColumns(rows, 12), 3, "three place columns")
    assert(rows[1]:find("Interface\\AddOns\\AltsForever\\media\\blank.tga", 1, true), "our spacer")
    clearTooltipLines()
end)

test("item tooltip columns are lined up again in the font a UI addon shows them in", function()
    wow.load(FILES)
    local rights = measurableTooltip()
    columnAlts()
    local lines = wow.hover(GameTooltip, 100)
    -- EllesmereUI sets its own font on every line when the tooltip is shown.
    for i = 1, #lines do rights[i].size = 16 end
    local shows = 0
    GameTooltip.Show = function(self) shows = shows + 1 self.shown = true end
    GameTooltip.hooks.OnShow(GameTooltip)
    eq(shows, 1, "shown again so it resizes to the new text")
    eq(checkColumns(rowTexts(rights, lines), 16), 3)
    -- Nothing to do the next time it's shown in that font.
    GameTooltip.hooks.OnShow(GameTooltip)
    eq(shows, 1)
    -- A cleared tooltip (now showing something else) is left alone.
    GameTooltip.hooks.OnTooltipCleared(GameTooltip)
    for i = 1, #lines do rights[i].size = 12 end
    GameTooltip.hooks.OnShow(GameTooltip)
    eq(shows, 1)
    clearTooltipLines()
end)

test("item tooltip: spacers are calibrated to how wide the tooltip really draws them", function()
    wow.load(FILES)
    local rights = measurableTooltip()
    spacerDraw = 0.87
    columnAlts()
    local lines = wow.hover(GameTooltip, 100)
    eq(checkColumns(rowTexts(rights, lines), 12), 3)
    spacerDraw = 1
    clearTooltipLines()
end)

test("item tooltip columns are measured once per item and font, then reused", function()
    wow.load(FILES)
    measurableTooltip()
    wow.measured = 0
    wow.login({ v = 2, chars = {
        ["Big"] = alt("Big", "PRIEST", { bags = { [100] = 30 } }),
        ["Mid"] = alt("Mid", "DRUID", { bank = { [100] = 5 }, bags = { [101] = 2 } }),
    } })
    wow.hover(GameTooltip, 100)
    assert(wow.measured > 0, "measured the first time")
    wow.hover(GameTooltip, 100)
    wow.hover(GameTooltip, 101)
    local afterOther = wow.measured
    wow.hover(GameTooltip, 100)
    eq(wow.measured, afterOther, "back to the first item: its columns are still cached")
    clearTooltipLines()
end)

---------------------------------------------------------------------------
-- Session stats (off by default)
test("session stats are off by default: no pace on the XP bar, no gold over time", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    local bar = blizzardXPBar()
    wow.money = 500
    wow.login(overviewAlts())
    wow.fire("PLAYER_ENTERING_WORLD")
    bar.scripts.OnEnter(bar)
    eq(lineTexts(GameTooltip):find("This session", 1, true), nil)
    local tt = wow.tooltip()
    ns.AddMoneyLines(tt)
    for _, l in ipairs(tt.lines) do assert(l[1] ~= "This session", "no gold stats") end
end)

test("session stats: XP this session across a level-up, and about how long to level", function()
    wow.load(FILES)
    wow.now = NOW
    local bar = blizzardXPBar()
    wow.stats.level, wow.stats.xp, wow.stats.xpMax = 24, 5700, 10000
    wow.login(overviewAlts())
    wow.fire("PLAYER_ENTERING_WORLD")
    SlashCmdList.ALTSFOREVER("stats")
    eq(AltsForeverDB.statsOn, true)
    wow.stats.xp = 7700
    wow.fire("PLAYER_XP_UPDATE", "player")
    wow.stats.level, wow.stats.xp, wow.stats.xpMax = 25, 500, 12000
    wow.fire("PLAYER_LEVEL_UP", 25)
    wow.fire("PLAYER_XP_UPDATE", "player")
    wow.now = NOW + 3600
    bar.scripts.OnEnter(bar)
    local lines = {}
    for _, l in ipairs(GameTooltip.lines) do lines[#lines + 1] = l[1] .. "=" .. tostring(l[2]) end
    local text = table.concat(lines, " | ")
    assert(text:find("This session=1h 0m", 1, true), text)
    assert(text:find("XP gained=4800", 1, true) or text:find("XP gained=4,800", 1, true), text)
    -- 11,500 XP to go at 4,800 an hour: about 2h 23m.
    assert(text:find("Time to level=about 2h 23m", 1, true), text)
    assert(text:find("Your characters", 1, true), "alts still listed after")
    SlashCmdList.ALTSFOREVER("stats")
    eq(AltsForeverDB.statsOn, nil)
end)

test("session stats: gold this session, today and this week across characters", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.money = 1000
    wow.login({ v = 2, chars = { ["Brak Stone"] = alt("Brak Stone", "WARRIOR", { money = 5000 }) } })
    local days = AltsForeverDB.goldDays
    local today
    for day in pairs(days) do today = day end
    eq(days[today], 6000, "today's total recorded at login")
    days[today - 1] = 4000 -- yesterday
    days[today - 9] = 1000 -- over a week ago
    wow.money = 1500
    wow.fire("PLAYER_MONEY")
    eq(days[today], 6500)
    SlashCmdList.ALTSFOREVER("stats")
    local tt = wow.tooltip()
    ns.AddMoneyLines(tt)
    local got = {}
    for _, l in ipairs(tt.lines) do got[l[1]] = l[2] end
    eq(got["This session"], "|cff20ff20+500c|r", "gains in green")
    eq(got["Today, all characters"], "|cff20ff20+2500c|r")
    eq(got["This week, all characters"], "|cff20ff20+5500c|r")
    wow.money = 100
    wow.fire("PLAYER_MONEY")
    tt = wow.tooltip()
    ns.AddMoneyLines(tt)
    got = {}
    for _, l in ipairs(tt.lines) do got[l[1]] = l[2] end
    eq(got["This session"], "|cffff4040-900c|r", "losses in red")
    wow.money = 1000
    wow.fire("PLAYER_MONEY")
    tt = wow.tooltip()
    ns.AddMoneyLines(tt)
    got = {}
    for _, l in ipairs(tt.lines) do got[l[1]] = l[2] end
    eq(got["This session"], "0c", "no change: plain")
    -- Days over a year old are dropped when a new day starts.
    days[today - 500] = 1
    wow.now = NOW + 86400
    wow.fire("PLAYER_MONEY")
    eq(days[today - 500], nil)
end)

test("session stats carry over a /reload, but start again on a real login", function()
    wow.load(FILES)
    wow.now = NOW
    wow.money = 1000
    wow.stats.level, wow.stats.xp, wow.stats.xpMax = 24, 5700, 10000
    wow.login({ v = 2, chars = {}, statsOn = true })
    wow.fire("PLAYER_ENTERING_WORLD", true, false)
    wow.stats.xp = 6700
    wow.fire("PLAYER_XP_UPDATE", "player")
    wow.money = 1500
    wow.fire("PLAYER_MONEY")
    wow.now = NOW + 1800
    wow.fire("PLAYER_LOGOUT") -- /reload
    local saved = AltsForeverDB

    local function reloaded(isInitialLogin, isReloadingUi, at)
        local ns = wow.load(FILES)
        wow.now, wow.money = at, 1500
        wow.stats.level, wow.stats.xp, wow.stats.xpMax = 24, 6700, 10000
        wow.login(saved)
        wow.fire("PLAYER_ENTERING_WORLD", isInitialLogin, isReloadingUi)
        local seconds, xp = ns.SessionXP(at + 600)
        local tt = wow.tooltip()
        ns.AddMoneyLines(tt)
        local gold
        for _, l in ipairs(tt.lines) do if l[1] == "This session" then gold = l[2] end end
        return seconds, xp, gold
    end
    local seconds, xp, gold = reloaded(false, true, NOW + 1810)
    eq(seconds, 2410, "counted from the first login"); eq(xp, 1000); eq(gold, "|cff20ff20+500c|r")
    eq(AltsForeverDB.session, nil, "used up")

    wow.fire("PLAYER_LOGOUT")
    saved = AltsForeverDB
    seconds, xp, gold = reloaded(true, false, NOW + 1820)
    eq(seconds, 600, "a real login starts again"); eq(xp, 0); eq(gold, "0c")
end)

test("overview row tooltip: professions line up, skill right-aligned and notes after it", function()
    wow.load(FILES)
    wow.now = NOW
    local rights = measurableTooltip()
    GameTooltip.Show = function(self) self.shown = true end
    local saved = overviewAlts()
    saved.recipeInfo = { Tailoring = { a = "250;A;", b = "150;B;", c = "210;C;,1:1" } }
    saved.chars["High"].recipes = { Tailoring = { a = true, b = true, c = true } }
    saved.chars["High"].profs = { Tailoring = 200, Enchanting = 80, Cooking = 1 }
    wow.login(saved)
    SlashCmdList.ALTSFOREVER("")
    local row = overviewRows()[3] -- High
    row.scripts.OnEnter(row)
    local texts = {}
    for i, l in ipairs(GameTooltip.lines) do
        if l[1] == "Cooking" or l[1] == "Enchanting" or l[1] == "Tailoring" then texts[#texts + 1] = rights[i].text end
    end
    eq(#texts, 3, "sorted by name: Cooking, Enchanting, Tailoring")
    local width = visibleWidth(texts[1], 12)
    local function skillEnd(t) -- width up to the end of the skill number
        local lead, rest = t:match("^(|T[^|]-blank%.tga:1:%d+|t)(.*)$")
        local digits = (rest or t):match("^(%d+)")
        return visibleWidth((lead or "") .. digits, 12)
    end
    local edge = skillEnd(texts[1])
    for i, t in ipairs(texts) do
        assert(math.abs(visibleWidth(t, 12) - width) <= 0.5, "row " .. i .. " width: " .. t)
        assert(math.abs(skillEnd(t) - edge) <= 0.5, "row " .. i .. " skill right edge: " .. t)
    end
    assert(texts[3]:find("(2 skill-up recipes)", 1, true), texts[3])
    clearTooltipLines()
end)

test("secret widths (while Blizzard builds a tooltip): plain text until a spacer scale is known", function()
    wow.load(FILES)
    wow.ownDraw = 1
    local rights = measurableTooltip()
    spacerDraw = 0.87
    wow.setBag(0, 16, { [1] = { 100, 23 }, [2] = { 101, 4 } })
    wow.login({ v = 2, chars = {
        ["Big"] = alt("Big", "PRIEST", { bags = { [100] = 30, [101] = 12 }, mail = { [100] = 1000, [101] = 3 } }),
        ["Mid"] = alt("Mid", "DRUID", { bank = { [100] = 5, [101] = 150 } }),
    } })
    -- Nothing learned yet: the lines' widths are secret, so the plain text stays.
    wow.secretWidths = true
    local lines = wow.hover(GameTooltip, 100)
    for i = 3, #lines do eq(rights[i].text, nil, "line " .. i .. " left as added") end
    -- A readable hover lines it up and learns how wide spacers are drawn.
    wow.secretWidths = nil
    lines = wow.hover(GameTooltip, 100)
    eq(checkColumns(rowTexts(rights, lines), 12), 2)
    -- Secret again, another item: measured in our own font string with the learned scale.
    wow.secretWidths = true
    for i = 1, 20 do rights[i].text = nil end
    lines = wow.hover(GameTooltip, 101)
    local rows = rowTexts(rights, lines)
    eq(#rows, 3, "lined up")
    wow.secretWidths = nil
    eq(checkColumns(rows, 12), 2)
    -- A secret font is left alone.
    rights[3].GetFont = function() return wow.SECRET, 12, "" end
    GameTooltip.hooks.OnShow(GameTooltip)
    spacerDraw = 1
    clearTooltipLines()
end)

---------------------------------------------------------------------------
-- Minimap button
test("a minimap button is made as soon as saved data loads (before login)", function()
    wow.load(FILES)
    AltsForeverDB = { v = 2, chars = {} }
    wow.fire("ADDON_LOADED", "AltsForever")
    local b = AltsForeverMinimapButton
    assert(b, "made before PLAYER_LOGIN, so EllesmereUI's minimap can collect it")
    wow.fire("PLAYER_LOGIN")
    b.scripts.OnClick(b, "LeftButton")
    eq(AltsForeverFrame:IsShown(), true)
    b.scripts.OnClick(b, "RightButton")
    eq(wow.menu.items[1].text, "Alts Forever", "right-click: options menu")
    b.scripts.OnEnter(b)
    eq(GameTooltip.lines[1][1], "Alts Forever")
end)

test("dragging moves the button around the minimap edge, and the position is kept", function()
    wow.load(FILES)
    wow.login(nil)
    local b = AltsForeverMinimapButton
    b.scripts.OnDragStart(b)
    assert(b.scripts.OnUpdate, "follows the cursor while dragging")
    wow.cursor = { 1100, 600 } -- straight right of the minimap's centre
    b.scripts.OnUpdate(b)
    eq(AltsForeverDB.minimapAngle, 0)
    eq(b.point[4], 80); eq(b.point[5], 0, "on the edge: radius 70 + 10")
    b.scripts.OnDragStop(b)
    eq(b.scripts.OnUpdate, nil, "nothing runs once dropped")
end)

test("the minimap button can be hidden from the options menu, and stays hidden", function()
    wow.load(FILES)
    wow.login(nil)
    AltsForever_OnAddonCompartmentClick("AltsForever", "RightButton", UIParent)
    local box = wow.menuItem("Show minimap button")
    eq(box.isSelected(), true)
    box.setSelected()
    eq(AltsForeverMinimapButton:IsShown(), false)
    eq(AltsForeverDB.minimapHidden, true)
    -- Next session: not even made.
    local saved = AltsForeverDB
    wow.load(FILES)
    wow.login(saved)
    eq(AltsForeverMinimapButton, nil)
    AltsForever_OnAddonCompartmentClick("AltsForever", "RightButton", UIParent)
    wow.menuItem("Show minimap button").setSelected()
    eq(AltsForeverMinimapButton:IsShown(), true, "turned back on: made now")
end)

test("with EllesmereUI, the overview's icon buttons get its square style", function()
    wow.withEllesmere = true
    wow.load(FILES)
    wow.login(nil)
    wow.skinCallback(wow.skinFacade)
    SlashCmdList.ALTSFOREVER("")
    local squared = 0
    for _, call in ipairs(wow.skinned) do if call[1] == "SquareIcon" then squared = squared + 1 end end
    eq(squared, 2, "reputation and options buttons")
end)

test("the minimap button and addon list use our logo, shipped with the addon", function()
    wow.load(FILES)
    wow.login(nil)
    eq(AltsForeverMinimapButton.icon.texture, "Interface\\AddOns\\AltsForever\\media\\minimap.tga")
    local toc = assert(io.open("AltsForever.toc")):read("*a")
    assert(toc:find("## IconTexture: Interface\\AddOns\\AltsForever\\media\\icon.tga", 1, true), "addon list icon")
    for _, file in ipairs({ "media/icon.tga", "media/minimap.tga", "media/blank.tga" }) do
        local f = io.open(file, "rb")
        assert(f, file .. " exists")
        f:close()
    end
end)

---------------------------------------------------------------------------
local function tocFiles(path)
    local files = {}
    for line in io.lines(path) do
        line = line:gsub("\r$", "")
        if line ~= "" and not line:match("^#") then
            files[#files + 1] = line
        end
    end
    return files
end

test("both .toc files list exactly the files the tests load", function()
    for _, toc in ipairs({ "AltsForever.toc", "AltsForever_Camelot.toc" }) do
        local files = tocFiles(toc)
        eq(table.concat(files, ","), table.concat(FILES, ","), toc)
    end
end)

test("both .toc files are identical", function()
    local a = assert(io.open("AltsForever.toc")):read("*a")
    local b = assert(io.open("AltsForever_Camelot.toc")):read("*a")
    eq(a, b)
end)

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
