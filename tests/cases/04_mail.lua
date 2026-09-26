-- Tests: mail. Loaded by tests/run.lua, which provides test, eq, wow, FILES and the
-- other shared helpers; helpers defined here are shared with the other files too.
---------------------------------------------------------------------------
-- Mail expiry

function printedText()
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
