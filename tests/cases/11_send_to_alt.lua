-- Tests: send to alt. Loaded by tests/run.lua, which provides test, eq, wow, FILES and the
-- other shared helpers; helpers defined here are shared with the other files too.
---------------------------------------------------------------------------
-- "Send to alt" at the mailbox
-- Your alts: Tarn (First Aid 40, knows Linen Bandage, grey 80), Brak (First Aid 100, past
-- grey), Ally (other faction), plus you.
function mailAlts()
    return { v = 2, recipeInfo = { ["First Aid"] = { ["linen bandage"] = "80;Linen Bandage;,2589:1" } }, chars = {
        ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { faction = "Alliance", level = 20, profs = { ["First Aid"] = 40 },
            recipes = { ["First Aid"] = { ["linen bandage"] = true } } }),
        ["Brak Stone"] = alt("Brak Stone", "WARRIOR", { faction = "Alliance", level = 30, profs = { ["First Aid"] = 100 },
            recipes = { ["First Aid"] = { ["linen bandage"] = true } } }),
        ["Horde Guy"] = alt("Horde Guy", "ROGUE", { faction = "Horde", level = 40 }),
    } }
end

function altsButton()
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
