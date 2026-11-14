-- Tests: mail rules (MailRules.lua). Loaded by tests/run.lua, which provides test, eq, wow,
-- FILES and the other shared helpers; helpers defined here are shared with the other files too.
-- The alts are 11_send_to_alt.lua's mailAlts(): Tarn Moon and Brak Stone (Alliance, both
-- know Linen Bandage, which takes Linen Cloth 2589), Horde Guy (Horde), and you, Aldric.
---------------------------------------------------------------------------
local LINEN, SILK, COPPER, SHIRT = 2589, 4306, 2770, 45

function ruleItems()
    wow.itemNames[LINEN], wow.itemNames[SILK], wow.itemNames[COPPER], wow.itemNames[SHIRT] =
        "Linen Cloth", "Silk Cloth", "Copper Ore", "Squire's Shirt"
    wow.itemClass[LINEN], wow.itemClass[SILK], wow.itemClass[COPPER], wow.itemClass[SHIRT] = 7, 7, 7, 4
    wow.items[LINEN], wow.items[SILK], wow.items[COPPER], wow.items[SHIRT] = { sub = 5, stack = 20 }, { sub = 5, stack = 20 }, { sub = 7, stack = 20 }, { sub = 1, stack = 1 }
end

-- Logged in with the mailbox open on the send tab.
function atMailbox(rules)
    mailNS = wow.load(FILES)
    ruleItems()
    local saved = mailAlts()
    saved.mailRules = rules
    wow.login(saved)
    wow.fire("MAIL_SHOW")
end

function attach(slot, id, count)
    wow.outbox[slot] = id and { id, count or 1 } or nil
    wow.fire("MAIL_SEND_INFO_UPDATE")
end

function mailNote()
    for _, f in ipairs(wow.frames) do
        if f.mailNote then return f end
    end
end

function packButton()
    for _, f in ipairs(wow.frames) do
        if f.mailPack then return f end
    end
end

function noteText()
    local n = mailNote()
    return n and n:IsShown() and n.text:GetText() or nil
end

function openArrow()
    local b = altsButton()
    b.scripts.OnClick(b)
    return wow.menu
end

function mailMenuTexts()
    local texts = {}
    for _, item in ipairs(wow.menu.items) do texts[#texts + 1] = item.text or "--" end
    return texts
end

test("mail rules: an item's own rule beats its category's, and only characters you can mail count", function()
    atMailbox({ ["c:7:5"] = { ["Tarn Moon"] = LINEN }, ["i:4306"] = { ["Brak Stone"] = SILK } })
    local ns = mailNS
    eq(ns.MailCategoryRule(LINEN), "c:7:5")
    eq(ns.MailRuleFor(LINEN), "Tarn Moon", "linen by the Cloth rule")
    eq(ns.MailRuleFor(SILK), "Brak Stone", "silk has a rule of its own")
    eq(ns.MailRuleFor(COPPER), nil, "no rule for ore")
    ns.SetMailRule("i:4306", "Horde Guy", true, SILK)
    eq(ns.MailRuleFor(SILK), "Brak Stone", "Horde Guy can't be mailed from here, so Brak stays")
    eq(AltsForeverDB.mailRules["i:4306"]["Horde Guy"], SILK, "but the rule keeps both, one per faction")
    ns.SetMailRule("c:7:5", "Brak Stone", true, LINEN)
    eq(AltsForeverDB.mailRules["c:7:5"]["Tarn Moon"], nil, "a new name you can mail replaces the old one")
    eq(ns.MailRuleFor(LINEN), "Brak Stone")
    ns.SetMailRule("i:4306", "Brak Stone", false)
    eq(ns.MailRuleFor(SILK), "Brak Stone", "the item rule gone, the Cloth rule takes silk too")
    eq(ns.ForgetCharacter("Brak Stone"), true)
    eq(AltsForeverDB.mailRules["c:7:5"], nil, "forgetting a character drops their rules")
    eq(AltsForeverDB.mailRules["i:4306"]["Horde Guy"], SILK, "others' stay")
end)

test("mail rules: your own character is skipped, so on Clarissa her cloth rule does nothing", function()
    atMailbox({ ["c:7:5"] = { ["Aldric"] = LINEN } })
    attach(1, LINEN, 20)
    eq(SendMailNameEditBox:GetText() or "", "", "never fills in yourself")
end)

test("mail rules: the first item attached fills in an empty To box, and the line says which rule", function()
    atMailbox({ ["c:7:5"] = { ["Tarn Moon"] = LINEN }, ["c:7:7"] = { ["Brak Stone"] = COPPER } })
    eq(noteText(), nil, "nothing attached, nothing said")
    attach(1, LINEN, 20)
    eq(SendMailNameEditBox:GetText(), "Tarn Moon")
    eq(noteText(), "|cffc0c0c0Filled in by your Cloth rule (click to undo)|r")
    attach(2, COPPER, 10)
    eq(SendMailNameEditBox:GetText(), "Tarn Moon", "the first item decides")
    eq(noteText(), "|cffc0c0c0Filled in by your Cloth rule (click to undo) · Copper Ore has its own rule: [WARRIOR]Brak|cffc0c0c0|r")
    attach(1, nil)
    eq(SendMailNameEditBox:GetText(), "Brak Stone", "the linen taken off: the ore is first now, and we filled the box, so it follows")
    attach(2, nil)
    eq(SendMailNameEditBox:GetText(), "", "nothing left: the name we put in goes too")
end)

test("mail rules: a name you typed or picked is never replaced", function()
    atMailbox({ ["c:7:5"] = { ["Tarn Moon"] = LINEN } })
    wow.type("Somebody Else")
    attach(1, LINEN, 20)
    eq(SendMailNameEditBox:GetText(), "Somebody Else", "typed")
    eq(noteText(), "|cffc0c0c0Linen Cloth has its own rule: [DRUID]Tarn|cffc0c0c0|r", "but it says where linen usually goes")
    attach(1, nil)
    wow.type("")
    openArrow()
    wow.menuItem("[WARRIOR]Brak Stone").fn()
    attach(1, LINEN, 20)
    eq(SendMailNameEditBox:GetText(), "Brak Stone", "picked from the arrow")
end)

test("mail rules: undoing or clearing what was filled in keeps it clear until the attachments are emptied", function()
    atMailbox({ ["c:7:5"] = { ["Tarn Moon"] = LINEN } })
    attach(1, LINEN, 20)
    mailNote().scripts.OnClick(mailNote())
    eq(SendMailNameEditBox:GetText(), "", "undone")
    attach(2, SILK, 5)
    eq(SendMailNameEditBox:GetText(), "", "stays clear while you keep attaching")
    attach(1, nil) attach(2, nil)
    attach(1, SILK, 5)
    eq(SendMailNameEditBox:GetText(), "Tarn Moon", "a fresh mail fills in again")
    wow.type("")
    attach(2, LINEN, 1)
    eq(SendMailNameEditBox:GetText(), "", "cleared by hand counts as undo too")
end)

test("mail rules: filling in can be turned off", function()
    atMailbox({ ["c:7:5"] = { ["Tarn Moon"] = LINEN } })
    mailNS.SetMailFill(false)
    attach(1, LINEN, 20)
    eq(SendMailNameEditBox:GetText() or "", "")
    eq(AltsForeverDB.mailFillOff, true)
end)

test("mail rules: the arrow suggests who uses the first item, as a category rule for trade goods", function()
    atMailbox(nil)
    attach(1, LINEN, 20)
    openArrow()
    local texts = mailMenuTexts()
    eq(texts[5], "Suggested rules", table.concat(texts, " | "))
    eq(texts[6], "Always send all Cloth to [WARRIOR]Brak|cffc0c0c0 · uses Linen Cloth in 1 known recipe|r")
    wow.menuItem(texts[7]).fn()
    eq(AltsForeverDB.mailRules["c:7:5"]["Tarn Moon"], LINEN, "a Cloth rule for Tarn")
    eq(SendMailNameEditBox:GetText(), "Tarn Moon", "and the To box follows it")
    openArrow()
    eq(wow.menuItem("Suggested rules"), nil, "no suggestions once it has a rule")
end)

test("mail rules: the arrow remembers what's attached for the character in the To box", function()
    atMailbox({ ["i:2589"] = { ["Brak Stone"] = LINEN } })
    wow.type("Tarn Moon")
    attach(1, LINEN, 20)
    attach(2, SILK, 5)
    openArrow()
    local texts = mailMenuTexts()
    local from = 0
    for i, t in ipairs(texts) do if t == "Remember for [DRUID]Tarn" then from = i end end
    assert(from > 0, table.concat(texts, " | "))
    eq(texts[from + 1], "Always send Linen Cloth here|cff9d9d9d (now Brak Stone)|r")
    eq(texts[from + 2], "Always send all Cloth here")
    eq(texts[from + 3], "Always send Silk Cloth here", "Cloth listed once")
    eq(texts[#texts], "Mail rules...")
    local cloth = wow.menuItem("Always send all Cloth here")
    eq(cloth.isSelected(), false)
    cloth.setSelected()
    eq(cloth.isSelected(), true)
    eq(mailNS.MailRuleFor(SILK), "Tarn Moon")
    eq(mailNS.MailRuleFor(LINEN), "Brak Stone", "linen's own rule still wins")
    local linen = wow.menuItem("Always send Linen Cloth here|cff9d9d9d (now Brak Stone)|r")
    linen.setSelected()
    eq(mailNS.MailRuleFor(LINEN), "Tarn Moon", "moved to Tarn")
    linen.setSelected()
    eq(AltsForeverDB.mailRules["i:2589"], nil, "unticked: gone")
end)

test("mail rules: Pack attaches what the rules send to that character, never bound or already attached items", function()
    atMailbox({ ["c:7:5"] = { ["Tarn Moon"] = LINEN }, ["c:7:7"] = { ["Brak Stone"] = COPPER } })
    wow.setBag(0, 16, { { LINEN, 20 }, { SILK, 5 }, { COPPER, 10 }, { LINEN, 7 }, { SHIRT, 1 } })
    wow.bags[0][4].bound = true
    wow.setBag(1, 8, { [3] = { SILK, 2 }, [4] = { COPPER, 5 } })
    wow.fire("BAG_UPDATE_DELAYED")
    local p = packButton()
    eq(p:IsShown(), true)
    eq(p:GetText(), "Pack 3 for [DRUID]Tarn", "most stacks: Tarn's 3 (the bound linen left out) over Brak's 2")
    p.scripts.OnClick(p)
    eq(SendMailNameEditBox:GetText(), "Tarn Moon", "filled in")
    eq(wow.attachClicks, 3)
    eq(wow.outbox[1][1], LINEN) eq(wow.outbox[2][1], SILK) eq(wow.outbox[3][1], SILK)
    eq(wow.cursor, nil, "nothing left on the cursor")
    wow.fire("MAIL_SEND_INFO_UPDATE")
    eq(p:IsShown(), false, "nothing more for Tarn")
    wow.type("Brak Stone")
    eq(p:GetText(), "Pack 2 for [WARRIOR]Brak", "follows the To box")
    wow.type("Somebody Else")
    eq(p:IsShown(), false, "not one of yours")
end)

test("mail rules: Pack fills only the free attachment slots, and can be turned off", function()
    atMailbox({ ["c:7:5"] = { ["Tarn Moon"] = LINEN } })
    for i = 1, 11 do wow.outbox[i] = { SHIRT, 1 } end
    wow.setBag(0, 16, { { LINEN, 20 }, { LINEN, 20 }, { LINEN, 20 } })
    wow.fire("MAIL_SEND_INFO_UPDATE")
    local p = packButton()
    eq(p:GetText(), "Pack 1 for [DRUID]Tarn")
    p.scripts.OnClick(p)
    eq(wow.outbox[12][1], LINEN)
    eq(wow.attachClicks, 1)
    wow.outbox = {}
    mailNS.SetMailPack(false)
    eq(p:IsShown(), false)
    eq(AltsForeverDB.mailPackOff, true)
end)

test("mail rules: turning off Send mail to alts turns the rules off too, and keeps them", function()
    atMailbox({ ["c:7:5"] = { ["Tarn Moon"] = LINEN } })
    wow.setBag(0, 16, { { LINEN, 20 } })
    mailNS.SetSendToAlt(false)
    attach(1, SILK, 5)
    eq(SendMailNameEditBox:GetText() or "", "", "not filled in")
    eq(noteText(), nil)
    eq(packButton():IsShown(), false)
    eq(mailNS.MailPackPlan(), nil)
    mailNS.SetSendToAlt(true)
    eq(SendMailNameEditBox:GetText(), "Tarn Moon", "back on, at once")
    eq(packButton():IsShown(), true)
    eq(AltsForeverDB.mailRules["c:7:5"]["Tarn Moon"], LINEN)
end)

test("mail rules: shift-click Pack attaches full stacks only, and says so when there are none", function()
    atMailbox({ ["c:7:5"] = { ["Tarn Moon"] = LINEN } })
    wow.setBag(0, 16, { { LINEN, 7 }, { LINEN, 20 }, { SILK, 3 } })
    wow.fire("BAG_UPDATE_DELAYED")
    local p = packButton()
    eq(p:GetText(), "Pack 3 for [DRUID]Tarn")
    wow.shift = true
    p.scripts.OnClick(p)
    eq(wow.attachClicks, 1)
    eq(wow.outbox[1][1], LINEN) eq(wow.outbox[1][2], 20)
    eq(wow.bags[0][1].locked, nil, "the part stack stays in the bag")
    eq(SendMailNameEditBox:GetText(), "Tarn Moon")
    -- Only part stacks left: nothing attached, the To box untouched, a line in chat.
    wow.outbox = {}
    SendMailNameEditBox:SetText("")
    wow.setBag(0, 16, { { LINEN, 7 }, { SILK, 3 } })
    wow.fire("BAG_UPDATE_DELAYED")
    wow.printed = {}
    p.scripts.OnClick(p)
    wow.shift = false
    eq(wow.attachClicks, 1)
    eq(SendMailNameEditBox:GetText(), "")
    assert(table.concat(wow.printed, "\n"):find("No full stacks to pack", 1, true))
    -- A plain click still takes them all.
    p.scripts.OnClick(p)
    eq(wow.attachClicks, 3)
end)

test("mail rules: the note and Pack sit above the letter's text box, which overlaps them", function()
    atMailbox({ ["c:7:5"] = { ["Tarn Moon"] = LINEN } })
    SendMailScrollFrame = CreateFrame("ScrollFrame", "SendMailScrollFrame", SendMailFrame)
    SendMailBodyEditBox = CreateFrame("EditBox", "SendMailBodyEditBox", SendMailScrollFrame)
    SendMailScrollFrame:SetFrameLevel(8)
    SendMailBodyEditBox:SetFrameLevel(9)
    wow.fire("MAIL_SHOW")
    local ok1 = packButton():GetFrameLevel() > 9
    local ok2 = mailNote():GetFrameLevel() > 9
    SendMailScrollFrame, SendMailBodyEditBox = nil, nil
    eq(ok1, true)
    eq(ok2, true)
end)

test("mail rules window: lists every rule, removes one, and holds the two settings", function()
    atMailbox({ ["c:7:5"] = { ["Tarn Moon"] = LINEN, ["Horde Guy"] = SILK }, ["i:2770"] = { ["Brak Stone"] = COPPER } })
    SlashCmdList.ALTSFOREVER("mailrules")
    local f = AltsForeverMailRulesFrame
    eq(f:IsShown(), true)
    local rows = f.rows
    eq(rows[1].label:GetText(), "All Cloth") eq(rows[1].who:GetText(), "|cff9d9d9dHorde Guy|r", "greyed: can't mail them from here")
    eq(rows[2].label:GetText(), "All Cloth") eq(rows[2].who:GetText(), "[DRUID]Tarn Moon")
    eq(rows[3].label:GetText(), "Copper Ore")
    eq(rows[3].icon.texture, "Interface\\Icons\\INV_Misc_QuestionMark", "no icon known in the fake")
    eq(f.empty:IsShown(), false)
    rows[2].remove.scripts.OnClick(rows[2].remove)
    eq(AltsForeverDB.mailRules["c:7:5"]["Tarn Moon"], nil)
    eq(rows[2].label:GetText(), "Copper Ore", "refilled")
    eq(rows[3]:IsShown(), false)
    eq(f.fill:GetChecked(), true)
    f.fill:SetChecked(false) f.fill.scripts.OnClick(f.fill)
    eq(AltsForeverDB.mailFillOff, true)
    f.pack:SetChecked(false) f.pack.scripts.OnClick(f.pack)
    eq(AltsForeverDB.mailPackOff, true)
    SlashCmdList.ALTSFOREVER("mailrules")
    eq(f:IsShown(), false, "again closes it")
end)

test("mail rules window: empty, it says how to make one; the arrow's Mail rules... opens it", function()
    atMailbox(nil)
    openArrow()
    wow.menuItem("Mail rules...").fn()
    local f = AltsForeverMailRulesFrame
    eq(f:IsShown(), true)
    eq(f.empty:IsShown(), true)
    wow.menuItem("Mail rules...").fn()
    eq(f:IsShown(), true, "the menu only opens it")
end)

test("mail rules: damaged rules are dropped at load", function()
    wow.load(FILES)
    local saved = mailAlts()
    saved.mailRules = { ["c:7:5"] = { ["Tarn Moon"] = LINEN, [3] = 1, ["Brak Stone"] = "x" }, ["i:1"] = "bad", [5] = {}, ["i:2"] = {} }
    wow.login(saved)
    eq(AltsForeverDB.mailRules["c:7:5"]["Tarn Moon"], LINEN)
    eq(AltsForeverDB.mailRules["c:7:5"]["Brak Stone"], nil)
    eq(AltsForeverDB.mailRules["c:7:5"][3], nil)
    eq(AltsForeverDB.mailRules["i:1"], nil)
    eq(AltsForeverDB.mailRules[5], nil)
    eq(AltsForeverDB.mailRules["i:2"], nil, "an empty rule goes")
end)
