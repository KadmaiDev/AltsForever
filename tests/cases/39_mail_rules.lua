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
    eq(noteText(), nil, "and nothing said: the name is the player's")
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

test("the subject is filled from the first attachment, as the game does when C.O.D. is on (it's off on live)", function()
    atMailbox({ ["c:7:5"] = { ["Tarn Moon"] = LINEN } })
    local subject = SendMailSubjectEditBox
    eq(subject:GetText(), nil, "nothing attached: nothing filled")
    attach(1, LINEN, 20)
    eq(subject:GetText(), "Linen Cloth (20)", "named after it, with the stack size")
    attach(2, SILK, 1)
    eq(subject:GetText(), "Linen Cloth (20)", "still the first")
    attach(1, nil)
    eq(subject:GetText(), "Silk Cloth", "the first went: the next one, no count for one")
    attach(2, nil)
    eq(subject:GetText(), "", "nothing attached: taken out again")
    -- A subject the player typed is never touched.
    subject:SetText("For the bandages")
    attach(1, LINEN, 20)
    eq(subject:GetText(), "For the bandages")
    attach(1, nil)
    eq(subject:GetText(), "For the bandages", "not cleared either")
    -- Pack fills it too.
    subject:SetText("")
    wow.setBag(0, 16, { { LINEN, 20 }, { LINEN, 7 } })
    wow.fire("BAG_UPDATE_DELAYED")
    packButton().scripts.OnClick(packButton())
    eq(subject:GetText(), "Linen Cloth (20)")
    -- Where the game fills it itself (C.O.D. on), it's left to the game.
    wow.outbox = {}
    wow.fire("MAIL_SEND_INFO_UPDATE")
    subject:SetText("")
    wow.cod = true
    attach(1, SILK, 2)
    eq(subject:GetText(), "", "the game's job there")
    -- "Send mail to alts" off: the mailbox is left as the game has it.
    wow.cod = false
    attach(1, nil)
    SlashCmdList.ALTSFOREVER("sendmail")
    eq(AltsForeverDB.sendToAltOff, true)
    attach(1, SILK, 2)
    eq(subject:GetText(), "", "off: untouched")
end)

test("an attachment whose name hasn't loaded yet: the subject is filled once it arrives, so Send isn't left greyed out", function()
    atMailbox({})
    local subject = SendMailSubjectEditBox
    wow.unloaded = { [SILK] = true }
    local names = wow.itemNames[SILK]
    wow.itemNames[SILK] = nil
    wow.itemLoads = nil
    attach(1, SILK, 4)
    eq(subject:GetText(), nil, "no name yet: nothing to fill")
    attach(2, SILK, 1)
    eq(wow.itemLoads and #wow.itemLoads, 1, "asked for once")
    attach(2, nil)
    eq(wow.itemLoads and wow.itemLoads[1], SILK, "its name is asked for")
    wow.unloaded, wow.itemNames[SILK] = nil, names
    wow.fire("GET_ITEM_INFO_RECEIVED", SILK, true)
    eq(subject:GetText(), "Silk Cloth (4)", "filled when it arrives")
    -- A name still loading never takes out the subject we filled.
    wow.unloaded = { [LINEN] = true }
    local linen = wow.itemNames[LINEN]
    wow.itemNames[LINEN] = nil
    attach(2, LINEN, 20)
    attach(1, nil)
    eq(subject:GetText(), "Silk Cloth (4)", "kept while the next one's name loads")
    wow.unloaded, wow.itemNames[LINEN] = nil, linen
    wow.fire("GET_ITEM_INFO_RECEIVED", LINEN, true)
    eq(subject:GetText(), "Linen Cloth (20)")
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
    wow.fire("MAIL_SEND_INFO_UPDATE")
    eq(SendMailNameEditBox:GetText(), "Tarn Moon", "Pack chose Tarn: kept, though the first attachment has no rule")
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
    -- The Mail rules window says so while it's off.
    mailNS.ToggleMailRules(true)
    local win = AltsForeverMailRulesFrame
    eq(win.off:IsShown(), false)
    mailNS.SetSendToAlt(false)
    eq(win.off:IsShown(), true, "updated while open")
    mailNS.SetSendToAlt(true)
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

test("Posty Forever: our arrow moves right of its address book button, the rules window past Quick Attach", function()
    mailNS = wow.load(FILES)
    wow.login(mailAlts())
    Postal_BlackBookButton = CreateFrame("Button", "Postal_BlackBookButton", SendMailFrame)
    Postal_QuickAttachButton1 = CreateFrame("Button", "Postal_QuickAttachButton1", SendMailFrame)
    Postal_QuickAttachButton1:SetWidth(37)
    MailFrame = CreateFrame("Frame", "MailFrame")
    MailFrame:Show()
    SendMailFrame:Show()
    wow.fire("MAIL_SHOW")
    local _, rel, _, x, y = altsButton():GetPoint()
    local besidePosty = rel == Postal_BlackBookButton and x == 0 and y == -2
    mailNS.ToggleMailRules(true)
    local _, rel2, _, x2 = AltsForeverMailRulesFrame:GetPoint()
    rel2 = rel2 == MailFrame and "MailFrame" or rel2
    -- Posty's module turned off: back beside the To box.
    Postal_BlackBookButton:Hide()
    wow.fire("MAIL_CLOSED") wow.fire("MAIL_SHOW")
    local _, rel3 = altsButton():GetPoint()
    Postal_BlackBookButton, Postal_QuickAttachButton1, MailFrame = nil, nil, nil
    eq(besidePosty, true)
    eq(rel2, "MailFrame") eq(x2, 12 + 37)
    eq(rel3, SendMailNameEditBox)
end)

-- Posty Forever's BlackBook autofill, as its saved settings and hooks would leave things.
function postyAutofill(recent)
    PostyForever = { db = { profile = { BlackBook = { AutoFill = true, recent = recent } } } }
end

test("Posty Forever: a rule replaces the name its autofill put in, and undo puts it back", function()
    MailFrameTab_OnClick = function() end
    OpenMail_Reply = function() SendMailNameEditBox:SetText("Somebody Else") end
    atMailbox({ ["c:7:5"] = { ["Tarn Moon"] = LINEN } })
    postyAutofill({ "Brak Stone|" .. tostring(GetRealmName()) .. "|Alliance" })
    -- Switching to Send Mail: Posty fills in Brak after Blizzard's tab code (and our hook).
    MailFrameTab_OnClick(nil, 2)
    SendMailNameEditBox:SetText("Brak Stone")
    runTimers()
    attach(1, LINEN, 20)
    eq(SendMailNameEditBox:GetText(), "Tarn Moon", "the rule wins over Posty's guess")
    eq(noteText(), "|cffc0c0c0Filled in by your Cloth rule (click to undo)|r")
    mailNote().scripts.OnClick(mailNote())
    eq(SendMailNameEditBox:GetText(), "Brak Stone", "undo: Posty's name back")
    attach(1, nil) attach(1, LINEN, 20)
    eq(SendMailNameEditBox:GetText(), "Brak Stone", "and now it's kept")
    -- After a send: Posty fills in the last name again; taking the item off puts it back.
    attach(1, nil)
    wow.fire("MAIL_SEND_SUCCESS")
    SendMailNameEditBox:SetText("Brak Stone")
    runTimers()
    attach(1, LINEN, 20)
    eq(SendMailNameEditBox:GetText(), "Tarn Moon")
    attach(1, nil)
    eq(SendMailNameEditBox:GetText(), "Brak Stone", "the item gone: Posty's name back")
    -- Reply fills in the sender through the same tab switch: never replaced.
    attach(1, nil)
    SendMailNameEditBox:SetText("")
    postyAutofill({ "Somebody Else|" .. tostring(GetRealmName()) .. "|Alliance" })
    OpenMail_Reply()
    MailFrameTab_OnClick(nil, 2)
    runTimers()
    attach(1, LINEN, 20)
    eq(SendMailNameEditBox:GetText(), "Somebody Else", "a reply's name is kept")
    -- A name Posty didn't fill in (picked, typed) is kept as always.
    attach(1, nil)
    SendMailNameEditBox:SetText("")
    postyAutofill({ "Brak Stone|" .. tostring(GetRealmName()) .. "|Alliance" })
    MailFrameTab_OnClick(nil, 2)
    SendMailNameEditBox:SetText("Somebody Else")
    runTimers()
    attach(1, LINEN, 20)
    eq(SendMailNameEditBox:GetText(), "Somebody Else")
    PostyForever, MailFrameTab_OnClick, OpenMail_Reply = nil, nil, nil
end)

test("mail rules: picking the name a rule filled in makes it yours", function()
    atMailbox({ ["c:7:5"] = { ["Tarn Moon"] = LINEN }, ["c:7:7"] = { ["Brak Stone"] = COPPER } })
    attach(1, LINEN, 20)
    attach(2, COPPER, 10)
    eq(SendMailNameEditBox:GetText(), "Tarn Moon", "filled in by the cloth rule")
    openArrow()
    local pick
    for _, item in ipairs(wow.menu.items) do
        if item.text and item.text:find("^%[DRUID%]Tarn Moon") then pick = item end
    end
    pick.fn()
    eq(noteText(), nil, "no longer ours to explain")
    attach(1, nil)
    eq(SendMailNameEditBox:GetText(), "Tarn Moon", "the ore is first now, but the player chose Tarn")
end)

test("mail rules: suggestions make a category rule for trade goods, but not for Trade Goods: Other", function()
    atMailbox()
    wow.itemClass[4470], wow.items[4470] = 7, { sub = 11 }
    eq(mailNS.SuggestedRule(4470), "i:4470", "Other is too vague for a rule of its own")
    eq(mailNS.SuggestedRule(LINEN), "c:7:5", "all cloth")
    eq(mailNS.SuggestedRule(SHIRT), "i:45", "not a trade good")
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

-- Bind-on-equip gear for the BoE rules: a mail helm, a cloth robe and a sword (bind on
-- equip), a leather cap that binds on pickup, boots that load late, a BoE bag (neither
-- weapon nor armour).
local BOE_HELM, BOE_ROBE, BOP_CAP, BOE_LATE, BOE_SWORD, BOE_BAG = 9001, 9002, 9003, 9004, 9005, 9006
function boeItems()
    for id, def in pairs({ [BOE_HELM] = { "Ringed Helm", 4, 3, 2 }, [BOE_ROBE] = { "Silk Robe", 4, 1, 2 },
        [BOP_CAP] = { "Bound Cap", 4, 2, 1 }, [BOE_LATE] = { "Late Boots", 4, 2, 2 },
        [BOE_SWORD] = { "Green Sword", 2, 7, 2 }, [BOE_BAG] = { "Red Bag", 1, 0, 2 } }) do
        wow.itemNames[id], wow.itemClass[id] = def[1], def[2]
        wow.items[id] = { sub = def[3], bind = def[4], stack = 1 }
    end
end

test("mail rules: the bind-on-equip rule sends every BoE item, after an item's or category's own rule", function()
    atMailbox({ ["b:equip"] = { ["Brak Stone"] = BOE_HELM }, ["c:4:1"] = { ["Tarn Moon"] = BOE_ROBE } })
    boeItems()
    local ns = mailNS
    local key, rule = ns.MailRuleFor(BOE_HELM)
    eq(key, "Brak Stone", "a BoE helm")
    eq(rule, "b:equip")
    eq(ns.MailRuleFor(BOE_ROBE), "Tarn Moon", "the Armor: Cloth rule comes first")
    eq(ns.MailRuleFor(BOE_SWORD), "Brak Stone", "a weapon too")
    eq(ns.MailRuleFor(BOE_BAG), "Brak Stone", "and a bag")
    eq(ns.MailRuleFor(BOP_CAP), nil, "binds on pickup")
    eq(ns.MailRuleFor(LINEN), nil, "trade goods don't bind")
    wow.uncached[BOE_LATE] = true
    wow.itemLoads = {}
    eq(ns.MailRuleFor(BOE_LATE), nil, "not loaded yet")
    eq(wow.itemLoads[1], BOE_LATE, "so it's asked for")
    wow.uncached[BOE_LATE] = nil
    eq(ns.MailRuleFor(BOE_LATE), "Brak Stone", "and found once it has loaded (not remembered as not BoE)")
    attach(1, BOE_HELM)
    eq(SendMailNameEditBox:GetText(), "Brak Stone")
    eq(noteText(), "|cffc0c0c0Filled in by your bind-on-equip rule (click to undo)|r")
end)

test("mail rules: a BoE item that loads after the mailbox opened is filled in and packed once it arrives", function()
    atMailbox({ ["b:equip"] = { ["Brak Stone"] = BOE_HELM } })
    boeItems()
    wow.uncached[BOE_LATE] = true
    wow.setBag(0, 16, { { BOE_LATE, 1 } })
    wow.fire("BAG_UPDATE_DELAYED")
    eq(packButton():IsShown(), false, "not loaded: no rule yet")
    attach(1, BOE_LATE)
    eq(SendMailNameEditBox:GetText() or "", "", "nor for the To box")
    wow.timers = {}
    wow.uncached[BOE_LATE] = nil
    wow.fire("GET_ITEM_INFO_RECEIVED", 9999, true)
    eq(#wow.timers, 0, "an item nobody asked about changes nothing")
    wow.fire("GET_ITEM_INFO_RECEIVED", BOE_LATE, true)
    wow.fire("GET_ITEM_INFO_RECEIVED", BOE_LATE, true)
    eq(#wow.timers, 1, "one look for the arrival")
    for _, fn in ipairs(wow.timers) do fn() end
    eq(SendMailNameEditBox:GetText(), "Brak Stone", "filled in once it arrived, with no other event")
    eq(packButton():IsShown(), true, "and Pack offers it")
    eq(noteText(), "|cffc0c0c0Filled in by your bind-on-equip rule (click to undo)|r")
end)

test("mail rules: a late BoE item never replaces a name the player typed, and a failed load is let go", function()
    atMailbox({ ["b:equip"] = { ["Brak Stone"] = BOE_HELM } })
    boeItems()
    wow.uncached[BOE_LATE] = true
    attach(1, BOE_LATE)
    wow.timers = {}
    wow.fire("GET_ITEM_INFO_RECEIVED", BOE_LATE, false)
    eq(#wow.timers, 0, "failed: nothing to look at")
    wow.fire("GET_ITEM_INFO_RECEIVED", BOE_LATE, true)
    eq(#wow.timers, 0, "and let go: not waited for any more")
    wow.type("Tarn Moon") -- looks it up again: asked for again
    wow.uncached[BOE_LATE] = nil
    wow.fire("GET_ITEM_INFO_RECEIVED", BOE_LATE, true)
    eq(#wow.timers, 1)
    for _, fn in ipairs(wow.timers) do fn() end
    eq(SendMailNameEditBox:GetText(), "Tarn Moon", "the player's name stays")
end)

test("mail rules: BoE weapons and BoE armor rules come before the all-BoE one", function()
    atMailbox({ ["b:equip"] = { ["Brak Stone"] = BOE_BAG }, ["b:weapon"] = { ["Tarn Moon"] = BOE_SWORD } })
    boeItems()
    local ns = mailNS
    local key, rule = ns.MailRuleFor(BOE_SWORD)
    eq(key, "Tarn Moon", "weapons to the seller")
    eq(rule, "b:weapon")
    eq(ns.MailRuleFor(BOE_HELM), "Brak Stone", "armour has no rule of its own: all BoE")
    ns.SetMailRule("b:armor", "Tarn Moon", true, BOE_HELM)
    key, rule = ns.MailRuleFor(BOE_HELM)
    eq(key, "Tarn Moon") eq(rule, "b:armor")
    eq(ns.MailRuleFor(BOE_BAG), "Brak Stone", "neither weapon nor armour")
    ns.SetMailRule("b:weapon", "Horde Guy", true, BOE_SWORD)
    eq(ns.MailRuleFor(BOE_SWORD), "Tarn Moon", "Horde Guy can't be mailed from here")
    ns.SetMailRule("b:weapon", "Tarn Moon", false)
    eq(ns.MailRuleFor(BOE_SWORD), "Brak Stone", "the weapon rule here gone: all BoE")
    attach(1, BOE_HELM)
    eq(noteText(), "|cffc0c0c0Filled in by your bind-on-equip armor rule (click to undo)|r")
end)

test("mail rules: Pack takes bind-on-equip items that aren't bound yet", function()
    atMailbox({ ["b:equip"] = { ["Brak Stone"] = BOE_HELM } })
    boeItems()
    wow.setBag(0, 16, { { BOE_HELM, 1 }, { BOE_HELM, 1 }, { BOP_CAP, 1 }, { LINEN, 20 }, { BOE_ROBE, 1 } })
    wow.bags[0][2].bound = true
    wow.fire("BAG_UPDATE_DELAYED")
    local p = packButton()
    eq(p:GetText(), "Pack 2 for [WARRIOR]Brak", "the helm and robe; the worn-once helm and the cap are bound")
    p.scripts.OnClick(p)
    eq(wow.outbox[1][1], BOE_HELM) eq(wow.outbox[2][1], BOE_ROBE)
end)

test("mail rules: the arrow offers the BoE rules for what's attached; the window lists them", function()
    atMailbox(nil)
    boeItems()
    wow.type("Brak Stone")
    attach(1, LINEN, 20)
    openArrow()
    local texts = table.concat(mailMenuTexts(), " | ")
    assert(not texts:find("bind-on-equip", 1, true), texts)
    attach(2, BOE_HELM)
    openArrow()
    texts = mailMenuTexts()
    eq(texts[#texts - 3], "Always send bind-on-equip armor here")
    eq(texts[#texts - 2], "Always send all bind-on-equip items here", "last of the Remember ticks")
    attach(3, BOE_SWORD)
    openArrow()
    texts = mailMenuTexts()
    eq(texts[#texts - 4], "Always send bind-on-equip weapons here")
    eq(texts[#texts - 3], "Always send bind-on-equip armor here")
    eq(texts[#texts - 2], "Always send all bind-on-equip items here")
    wow.menuItem("Always send all bind-on-equip items here").setSelected()
    eq(AltsForeverDB.mailRules["b:equip"]["Brak Stone"], BOE_HELM, "the first BoE item kept for its icon")
    wow.menuItem("Always send bind-on-equip weapons here").setSelected()
    eq(AltsForeverDB.mailRules["b:weapon"]["Brak Stone"], BOE_SWORD)
    eq(mailNS.MailRuleFor(BOE_ROBE), "Brak Stone")
    SlashCmdList.ALTSFOREVER("mailrules")
    local rows = AltsForeverMailRulesFrame.rows
    eq(rows[1].label:GetText(), "All bind-on-equip items")
    eq(rows[1].who:GetText(), "[WARRIOR]Brak Stone")
    eq(rows[2].label:GetText(), "All bind-on-equip weapons")
end)
