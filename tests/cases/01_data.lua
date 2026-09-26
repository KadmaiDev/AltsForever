-- Tests: data. Loaded by tests/run.lua, which provides test, eq, wow, FILES and the
-- other shared helpers; helpers defined here are shared with the other files too.
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
function bagsChanged(bag)
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
function moneyChars()
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
