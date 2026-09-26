-- Tests: gear. Loaded by tests/run.lua, which provides test, eq, wow, FILES and the
-- other shared helpers; helpers defined here are shared with the other files too.
---------------------------------------------------------------------------
-- Gear

function itemLink(id, name, color)
    return (color or "|cff1eff00") .. "|Hitem:" .. id .. "::::::|h[" .. name .. "]|h|r"
end

function gearPanelSlots()
    local slots = {}
    for _, f in ipairs(wow.frames) do
        local slot = rawget(f, "slot")
        if slot then slots[slot] = f end
    end
    return slots
end

function clickRow(name)
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
