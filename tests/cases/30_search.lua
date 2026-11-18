-- Tests: the search window (Search.lua): items your characters have or can craft.
-- Loaded by tests/run.lua.

-- Logs in as Aldric with Tarn Moon (has linen), Smith (makes gloves) and Far Away (another
-- ruleset: hidden, as in tooltips).
function searchStart()
    local ns = wow.load(FILES)
    wow.item(2589, "Linen Cloth", {})
    wow.item(2996, "Bolt of Linen Cloth", {})
    wow.item(6001, "Linked Gloves", { sub = 3, loc = "INVTYPE_HAND" })
    wow.item(6005, "Far Gloves", { sub = 3, loc = "INVTYPE_HAND" })
    wow.item(4306, "Silk Cloth", {})
    wow.login({ v = 2, chars = {
        ["Aldric"] = alt("Aldric", "MAGE", { realm = "Realm", bags = {}, bank = { [2589] = 5 } }),
        ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { realm = "Realm", bags = { [2589] = 20, [2996] = 3 }, mail = { [4306] = 2 } }),
        ["Smith"] = alt("Smith", "PALADIN", { realm = "Realm", bags = {},
            crafts = { Blacksmithing = { [6001] = "linked gloves" }, Tailoring = { [2996] = "bolt of linen cloth" } } }),
        ["Far Away"] = alt("Far Away", "WARRIOR", { realm = "Elsewhere", bags = { [6005] = 1, [2589] = 99 } }),
    } })
    return ns
end

-- The item of the search row marked as picked (Enter's target), or nil.
function searchRowLit()
    for _, row in ipairs({ AltsForeverSearchFrame:GetChildren() }) do
        if row.entry and row:IsShown() and row.lit:IsShown() then return row.entry.id end
    end
end

-- Types into the search box, as the player would.
function searchType(text)
    AltsForeverSearchBox:SetText(text)
    AltsForeverSearchBox.scripts.OnTextChanged(AltsForeverSearchBox, true)
end

local function plain(s) return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end

-- The rows shown, as "Name (total) = detail", colour codes removed.
function searchRows()
    local out = {}
    for _, row in ipairs({ AltsForeverSearchFrame:GetChildren() }) do
        if row.entry and row:IsShown() then
            local total = row.total.text ~= "" and " (" .. row.total.text .. ")" or ""
            out[#out + 1] = row.name.text .. total .. " = " .. plain(row.detail.text)
        end
    end
    return table.concat(out, "\n")
end

test("search finds items your characters have or can craft: best matches first, who has them and who makes them", function()
    searchStart()
    SlashCmdList.ALTSFOREVERSEARCH("linen")
    eq(AltsForeverSearchFrame:IsShown(), true)
    -- The name's start before a later word; Far Away's 99 aren't counted (another ruleset).
    eq(searchRows(), "Linen Cloth (25) = [DRUID]Tarn 20, [MAGE]Aldric 5\n"
        .. "Bolt of Linen Cloth (3) = [DRUID]Tarn 3 · can craft: [PALADIN]Smith (Tailoring)")
    -- Made by a recipe, owned by nobody.
    searchType("glo")
    eq(searchRows(), "Linked Gloves = none owned · can craft: [PALADIN]Smith (Blacksmithing)", "not Far Away's gloves")
    -- Anywhere in the name; every word, in any order.
    searchType("nen")
    eq(searchRows(), "Linen Cloth (25) = [DRUID]Tarn 20, [MAGE]Aldric 5\nBolt of Linen Cloth (3) = [DRUID]Tarn 3 · can craft: [PALADIN]Smith (Tailoring)")
    searchType("cloth bolt")
    eq(searchRows(), "Bolt of Linen Cloth (3) = [DRUID]Tarn 3 · can craft: [PALADIN]Smith (Tailoring)")
    -- @owned and @craft narrow it (any start of the word). With @craft, who can make
    -- it comes first.
    searchType("@craft l")
    eq(searchRows(), "Linked Gloves = can craft: [PALADIN]Smith (Blacksmithing) · none owned\nBolt of Linen Cloth (3) = can craft: [PALADIN]Smith (Tailoring) · [DRUID]Tarn 3",
        "starts with it, then a later word")
    searchType("@own linen")
    eq(searchRows(), "Linen Cloth (25) = [DRUID]Tarn 20, [MAGE]Aldric 5\nBolt of Linen Cloth (3) = [DRUID]Tarn 3 · can craft: [PALADIN]Smith (Tailoring)",
        "any of your characters")
    -- An @ word it doesn't know (@mine was dropped) is left out of the search.
    searchType("@mine linen")
    eq(searchRows(), "Linen Cloth (25) = [DRUID]Tarn 20, [MAGE]Aldric 5\nBolt of Linen Cloth (3) = [DRUID]Tarn 3 · can craft: [PALADIN]Smith (Tailoring)")
    -- Nothing typed yet: what it does and the two words; nothing found: it says so.
    searchType("")
    eq(searchRows(), "")
    eq(AltsForeverSearchFrame.hint:IsShown(), true)
    local hint = AltsForeverSearchFrame.hint.text
    assert(hint:find("@owned", 1, true) and hint:find("@craft", 1, true), hint)
    assert(not hint:find("@mine", 1, true), hint)
    searchType("@craft")
    eq(AltsForeverSearchFrame.hint:IsShown(), true, "a word but nothing to look for yet")
    searchType("zzz")
    eq(AltsForeverSearchFrame.hint:IsShown(), false)
    assert(AltsForeverSearchFrame.status.text:find("Nothing matching 'zzz'", 1, true))
    -- With other rulesets shown, as in tooltips.
    SlashCmdList.ALTSFOREVER("rulesets")
    AltsForeverSearchFrame:Hide()
    SlashCmdList.ALTSFOREVERSEARCH("far")
    eq(searchRows(), "Far Gloves (1) = Far 1")
end)

test("Enter opens the bags of whoever has it, lit up (you first); arrows move; only Shift+Enter links it", function()
    local ns = searchStart()
    SlashCmdList.ALTSFOREVERSEARCH("linen")
    local box = AltsForeverSearchBox
    -- Aldric (you) has 5 in the bank: that's what opens, with the linen lit up.
    box.scripts.OnEnterPressed(box)
    eq(AltsForeverSearchFrame:IsShown(), true, "the search stays open")
    eq(AltsForeverBagsFrame:IsShown(), true)
    eq(AltsForeverSearchFrame.point[2], AltsForeverBagsFrame, "beside the bags window it opened")
    eq(ns.BagsHighlight(), 2589)
    eq(AltsForeverBagsFrame.who.text:find("Aldric", 1, true) ~= nil, true)
    -- With the bags window closed, the search is everyone's again: the bolt is in Tarn's bags.
    AltsForeverBagsFrame:Hide()
    SlashCmdList.ALTSFOREVERSEARCH("linen")
    box.scripts.OnArrowPressed(box, "DOWN")
    box.scripts.OnEnterPressed(box)
    eq(ns.BagsHighlight(), 2996, "the bolt, in Tarn's bags")
    assert(AltsForeverBagsFrame.who.text:find("Tarn Moon", 1, true))
    local alpha = {}
    for _, slot in ipairs({ AltsForeverBagsFrame.content:GetChildren() }) do
        if slot.id and slot:IsShown() then alpha[slot.id] = slot.icon:GetAlpha() end
    end
    eq(alpha[2996], 1, "lit")
    eq(alpha[2589], 0.25, "the rest dimmed")
    -- Bottom left says what's lit, in place of the free slots; clicking it shows every slot again.
    local clear = AltsForeverBagsFrame.clear
    eq(clear:IsShown(), true)
    eq(clear.text.text, "Showing: Bolt of Linen Cloth")
    -- The item in its quality colour (the game's colours carry a hex code).
    ITEM_QUALITY_COLORS[1] = { r = 1, g = 1, b = 1, hex = "|cffffffff" }
    ns.ShowBags("Tarn Moon", "bags", 2996)
    eq(clear.text.text, "Showing: |cffffffffBolt of Linen Cloth|r")
    ITEM_QUALITY_COLORS[1] = nil
    eq(AltsForeverBagsFrame.info:IsShown(), false)
    clear.scripts.OnClick(clear)
    eq(ns.BagsHighlight(), nil)
    eq(clear:IsShown(), false)
    eq(AltsForeverBagsFrame.info:IsShown(), true)
    for _, slot in ipairs({ AltsForeverBagsFrame.content:GetChildren() }) do
        if slot.id and slot:IsShown() then eq(slot.icon:GetAlpha(), 1, "every slot back") end
    end
    -- The bags window's own search button (it closes an open search, as the binding does).
    AltsForeverSearchFrame:Hide()
    local search = AltsForeverBagsFrame.searchButton
    search.scripts.OnClick(search)
    eq(AltsForeverSearchFrame:IsShown(), true)
    AltsForeverSearchFrame:Hide()
    ns.ShowBags("Tarn Moon", "bags", 2996)
    AltsForeverBagsFrame:Hide()
    eq(ns.BagsHighlight(), nil, "closed: gone")
    -- Shift+Enter: linked (chat closed: one opens with it).
    SlashCmdList.ALTSFOREVERSEARCH("linen")
    wow.shift = true
    box.scripts.OnEnterPressed(box)
    wow.shift = false
    assert(wow.openedChat[1]:find("Linen Cloth", 1, true), "linked")
    eq(AltsForeverSearchFrame:IsShown(), true, "linking leaves it open")
    -- Nobody has it (only craftable): Enter doesn't link it (the owner found a plain click
    -- putting it in chat confusing, 2026-11-18). With the bags window closed, nothing happens.
    wow.chatOpen = true
    local links = #wow.chatLinks + #wow.openedChat
    searchType("linked")
    box.scripts.OnEnterPressed(box)
    eq(#wow.chatLinks + #wow.openedChat, links, "not linked")
    eq(AltsForeverBagsFrame:IsShown(), false, "nothing to open")
    -- With it open: lit there as "not here"; a click doesn't link it either; Shift+Enter does.
    ns.ShowBags("Tarn Moon", "bags")
    searchType("linked")
    box.scripts.OnEnterPressed(box)
    eq(#wow.chatLinks + #wow.openedChat, links, "still not linked")
    eq(ns.BagsHighlight(), 6001, "lit in the bags window")
    eq(AltsForeverBagsFrame.stop.text, "not here")
    local rows = {}
    for _, r in ipairs({ AltsForeverSearchFrame:GetChildren() }) do
        if r.index then rows[r.index] = r end
    end
    rows[1].scripts.OnClick(rows[1], "LeftButton")
    eq(#wow.chatLinks + #wow.openedChat, links, "a click doesn't link it either")
    wow.shift = true
    box.scripts.OnEnterPressed(box)
    wow.shift = false
    assert(wow.chatLinks[#wow.chatLinks]:find("Linked Gloves", 1, true), "Shift+Enter links it")
    -- Only in the mail: their mail, lit up.
    searchType("silk")
    box.scripts.OnEnterPressed(box)
    eq(ns.BagsHighlight(), 4306)
    eq(select(2, ns.BagsState()), "mail", "the bags window's Mail view")
end)

test("the search opens from /afs, /af search, the binding, the menu and the overview; Escape closes it and lets the names go", function()
    local ns = searchStart()
    AltsForever_Binding("search")
    eq(AltsForeverSearchFrame:IsShown(), true)
    AltsForever_Binding("search")
    eq(AltsForeverSearchFrame:IsShown(), false, "the binding again closes it")
    SlashCmdList.ALTSFOREVER("search silk")
    eq(AltsForeverSearchBox.text, "silk")
    eq(searchRows(), "Silk Cloth (2) = [DRUID]Tarn 2")
    AltsForeverSearchBox.scripts.OnEscapePressed(AltsForeverSearchBox)
    eq(AltsForeverSearchFrame:IsShown(), false)
    eq(#ns.SearchMatches("linen"), 0, "names let go while closed")
    ns.ShowOptionsMenu(UIParent)
    wow.menuItem("Search...").fn()
    eq(AltsForeverSearchFrame:IsShown(), true)
    AltsForeverSearchFrame:Hide()
    SlashCmdList.ALTSFOREVER("")
    AltsForeverFrame.searchButton.scripts.OnClick(AltsForeverFrame.searchButton)
    eq(AltsForeverSearchFrame:IsShown(), true)
    -- In Escape's list, and joined to the controller's navigator, as our other windows.
    local listed = false
    for _, name in ipairs(UISpecialFrames) do listed = listed or name == "AltsForeverSearchFrame" end
    eq(listed, true)
    eq(type(AltsForeverSearchFrame.SmartNavigationCloseHandler), "function")
end)

test("a name still loading is asked for, and the search runs again a second later", function()
    local ns = searchStart()
    wow.item(7001, "Late Cloth", {})
    local late = wow.itemNames[7001]
    wow.itemNames[7001] = nil
    AltsForeverDB.chars["Tarn Moon"].bags[7001] = 4
    wow.timers = {}
    SlashCmdList.ALTSFOREVERSEARCH("late")
    eq(searchRows(), "")
    local asked = false
    for _, id in ipairs(wow.itemLoads or {}) do asked = asked or id == 7001 end
    eq(asked, true)
    wow.itemNames[7001] = late
    for _, fn in ipairs(wow.timers) do fn() end
    eq(searchRows(), "Late Cloth (4) = [DRUID]Tarn 4")
end)

-- The rows of the last menu, by text.
-- Opens the search's character menu and clicks the entry whose text contains `text`.
function searchTick(text)
    local f = AltsForeverSearchFrame
    f.chars.scripts.OnClick(f.chars)
    for _, item in ipairs(wow.menu.items) do
        if item.kind == "checkbox" and tostring(item.text):find(text, 1, true) then return item.setSelected() end
    end
    error("no tick box " .. text)
end

function menuTexts()
    local out = {}
    for _, item in ipairs(wow.menu.items) do out[#out + 1] = tostring(item.text) end
    return table.concat(out, " | ")
end

test("the highlight stays as you switch; the arrows step through everyone who has it; the menus show who", function()
    local ns = searchStart()
    SlashCmdList.ALTSFOREVERSEARCH("linen")
    AltsForeverSearchBox.scripts.OnEnterPressed(AltsForeverSearchBox)
    local f = AltsForeverBagsFrame
    -- Opened on Aldric's bank (you); Tarn has the most, so Tarn's bags come first.
    eq(f.stop.text, "2 of 2")
    eq(f.prev:IsShown(), true)
    f.next.scripts.OnClick(f.next)
    assert(f.who.text:find("Tarn Moon", 1, true), f.who.text)
    eq(f.stop.text, "1 of 2")
    eq(ns.BagsHighlight(), 2589, "still lit")
    -- Switching view keeps it lit, and says when it isn't there.
    f.bank.scripts.OnClick(f.bank)
    eq(ns.BagsHighlight(), 2589)
    eq(f.stop.text, "not here")
    f.next.scripts.OnClick(f.next)
    eq(f.stop.text, "1 of 2", "back to the first who has it")
    -- The character dropdown: how many each has.
    f.who.scripts.OnClick(f.who)
    local texts = plain(menuTexts())
    assert(texts:find("Tarn Moon (20)", 1, true) and texts:find("Aldric (5)", 1, true), texts)
    assert(not texts:find("Smith (", 1, true), "nothing for Smith")
    for _, item in ipairs(wow.menu.items) do
        if tostring(item.text):find("Aldric", 1, true) then item.setSelected(item.data) end
    end
    eq(ns.BagsHighlight(), 2589, "picking a character keeps it lit")
    f:Hide()
    -- Right-click a search result: everyone who has it, and where; picking one opens it.
    SlashCmdList.ALTSFOREVERSEARCH("silk")
    local row
    for _, r in ipairs({ AltsForeverSearchFrame:GetChildren() }) do
        if r.entry and r:IsShown() then row = row or r end
    end
    row.scripts.OnClick(row, "RightButton")
    eq(menuTexts(), "Silk Cloth | [DRUID]Tarn Moon: 2 in the mail | Link in chat")
    wow.menu.items[2].fn()
    eq(ns.BagsHighlight(), 4306, "picking the mail opens it, lit")
    eq(select(2, ns.BagsState()), "mail")
    searchType("linen")
    row.scripts.OnClick(row, "RightButton")
    eq(menuTexts(), "Linen Cloth | [DRUID]Tarn Moon: 20 in bags | [MAGE]Aldric: 5 in the bank | Link in chat")
    wow.menu.items[2].fn()
    eq(AltsForeverSearchFrame:IsShown(), true)
    assert(f.who.text:find("Tarn Moon", 1, true))
    eq(ns.BagsHighlight(), 2589)
end)

test("stepping through who has it keeps the bags window one height, so the arrows stay put", function()
    local ns = searchStart()
    -- Tarn's bags hold 30 different things (three rows), Aldric's bank one.
    local bags = AltsForeverDB.chars["Tarn Moon"].bags
    for id = 8001, 8030 do
        wow.item(id, "Thing " .. id, {})
        bags[id] = 1
    end
    ns.ShowBags("Aldric", "bank", 2589)
    local f = AltsForeverBagsFrame
    local height = f:GetHeight()
    f.next.scripts.OnClick(f.next)
    assert(f.who.text:find("Tarn Moon", 1, true))
    eq(f:GetHeight(), height, "Tarn's three rows: same height")
    f.next.scripts.OnClick(f.next)
    eq(f:GetHeight(), height, "back on Aldric's one slot: same height")
    -- Cleared: sized to what it shows again.
    f.clear.scripts.OnClick(f.clear)
    assert(f:GetHeight() < height, "shrinks to Aldric's bank")
end)

test("after the arrow keys scroll the list, a click picks the item it's on (hovering only shows it), and the tooltip follows the keys", function()
    local ns = searchStart()
    for id = 8101, 8112 do
        wow.item(id, "Rag " .. id, {})
        AltsForeverDB.chars["Tarn Moon"].bags[id] = 1
    end
    SlashCmdList.ALTSFOREVERSEARCH("rag")
    local box = AltsForeverSearchBox
    for _ = 1, 10 do box.scripts.OnArrowPressed(box, "DOWN") end
    -- The 11th of 12 is selected, so the list has scrolled: the first row shows the 4th.
    local rows = {}
    for _, r in ipairs({ AltsForeverSearchFrame:GetChildren() }) do
        if r.index then rows[r.index] = r end
    end
    eq(rows[1].entry.id, 8104)
    rows[1].scripts.OnEnter(rows[1])
    eq(GameTooltip.itemID, 8104, "the tooltip of the row under the mouse")
    eq(rows[1].lit:IsShown(), false, "hovering doesn't pick it")
    rows[1].scripts.OnClick(rows[1], "LeftButton")
    eq(rows[1].lit:IsShown(), true, "clicked: picked, by its place in the list, not on screen")
    eq(ns.BagsHighlight(), 8104, "and that one opens")
    -- With a row's tooltip open, the keys take it along. The bags window is open now, so
    -- nothing is picked until Down picks the first.
    SlashCmdList.ALTSFOREVERSEARCH("rag")
    rows[1].scripts.OnEnter(rows[1])
    eq(GameTooltip.itemID, 8101)
    box.scripts.OnArrowPressed(box, "DOWN")
    eq(GameTooltip.itemID, 8101, "Down picks the first")
    box.scripts.OnArrowPressed(box, "DOWN")
    eq(GameTooltip.itemID, 8102, "the tooltip follows the selection")
    eq(GameTooltip:GetOwner(), rows[2])
end)

test("with the bags window open the search works on it: that character only, beside it, lit as you go; closing it clears what's lit", function()
    local ns = searchStart()
    wow.item(2592, "Wool Cloth", {})
    AltsForeverDB.chars["Tarn Moon"].bank = { [2592] = 4 }
    -- A bank much taller than the bags, to see the window keep one height.
    for i = 1, 70 do
        wow.item(40000 + i, "Junk " .. i, {})
        AltsForeverDB.chars["Tarn Moon"].bank[40000 + i] = 1
    end
    ns.ShowBags("Tarn Moon", "bags")
    local bags = AltsForeverBagsFrame
    bags.searchButton.scripts.OnClick(bags.searchButton)
    local f, box = AltsForeverSearchFrame, AltsForeverSearchBox
    eq(f:IsShown(), true)
    assert(f.title.text:find("Tarn Moon", 1, true), f.title.text)
    eq(f.chars.text, "[DRUID]Tarn Moon", "the character menu says whose")
    eq(f.point[2], bags, "docked beside the bags window")
    -- Only what Tarn has (or can make), Tarn's numbers: not Aldric's, not Smith's crafts.
    searchType("cloth")
    eq(searchRows(), "Linen Cloth (20) = [DRUID]Tarn 20\n"
        .. "Wool Cloth (4) = [DRUID]Tarn 4\n"
        .. "Bolt of Linen Cloth (3) = [DRUID]Tarn 3\n"
        .. "Silk Cloth (2) = [DRUID]Tarn 2")
    -- Nothing picked yet: every match lit on Tarn, the buttons count them all, and the footer
    -- says what was searched for (the owner's idea, 2026-11-18).
    eq(ns.BagsHighlight(), nil, "no one item picked")
    local _, shownView, set = ns.BagsState()
    eq(shownView, "bags")
    eq(set[2589] and set[2592] and set[2996] and set[4306], true, "every match lit")
    eq(bags.clear.text.text, "Showing everything matching 'cloth'")
    eq(bags.bags.text .. " | " .. bags.bank.text .. " | " .. bags.mail.text, "Bags (23) | Bank (4) | Mail (2)")
    local alpha = {}
    for _, slot in ipairs({ bags.content:GetChildren() }) do
        if slot.id and slot:IsShown() then alpha[slot.id] = slot.icon:GetAlpha() end
    end
    eq(alpha[2589], 1, "linen lit")
    eq(alpha[2996], 1, "the bolt lit too")
    assert(f.status.text:find("click to keep it", 1, true), f.status.text)
    eq(searchRowLit(), nil, "no row picked")
    -- Picked (Down, then the next): that one alone, on Tarn, switching to the bank for the
    -- wool. The window is already as tall as Tarn's bank needs: it won't jump.
    local first = bags:GetHeight()
    box.scripts.OnArrowPressed(box, "DOWN")
    eq(ns.BagsHighlight(), 2589, "Down picks the first")
    eq(searchRowLit(), 2589)
    eq(bags.bags.text, "Bags (20)", "its own count now")
    box.scripts.OnArrowPressed(box, "DOWN")
    eq(bags:GetHeight(), first, "as tall as the bank from the start")
    eq(ns.BagsHighlight(), 2592)
    eq(select(2, ns.BagsState()), "bank")
    assert(bags.who.text:find("Tarn Moon", 1, true), "never another character")
    -- One height while the search is beside it, whichever of the two it shows.
    local tall = bags:GetHeight()
    box.scripts.OnArrowPressed(box, "UP")
    eq(select(2, ns.BagsState()), "bags")
    eq(bags:GetHeight(), tall, "doesn't jump between bags and bank")
    assert(f.status.text:find("Escape", 1, true), "says what Enter and Escape do here")
    -- Escape: the bags as they were.
    box.scripts.OnEscapePressed(box)
    eq(f:IsShown(), false)
    eq(ns.BagsHighlight(), nil)
    eq(select(2, ns.BagsState()), "bags")
    -- Opened again: the last search, selected so typing replaces it. Enter with nothing picked
    -- keeps every match lit.
    bags.searchButton.scripts.OnClick(bags.searchButton)
    eq(box.text, "cloth")
    box.scripts.OnEnterPressed(box)
    eq(f:IsShown(), true, "still open for the next one")
    eq(ns.BagsLighting(), true, "kept")
    eq(select(3, ns.BagsState())[2589], true)
    -- Looking at another (in the bank), then closing: nothing lit, back in the bags of the pick.
    box.scripts.OnArrowPressed(box, "DOWN")
    box.scripts.OnArrowPressed(box, "DOWN")
    eq(ns.BagsHighlight(), 2592)
    box.scripts.OnEscapePressed(box)
    eq(ns.BagsHighlight(), nil, "closing the search clears it")
    eq(ns.BagsLighting(), false)
    eq(bags:IsShown(), true, "the bags window stays")
    eq(select(2, ns.BagsState()), "bags")
    assert(bags.who.text:find("Tarn Moon", 1, true))
    -- All characters: Aldric's linen too; an item Tarn hasn't got is lit all the same, not here.
    bags.searchButton.scripts.OnClick(bags.searchButton)
    searchTick("All characters")
    eq(f.title.text, "Search your characters")
    eq(f.chars.text, "All characters", "still there to narrow it again")
    searchType("linen")
    box.scripts.OnEnterPressed(box)
    searchType("silk")
    eq(select(3, ns.BagsState())[4306], true, "Tarn's silk is in the mail: lit there")
    eq(select(2, ns.BagsState()), "mail", "switched to the Mail view")
    eq(bags.stop.text, "1 of 1")
    assert(bags.who.text:find("Tarn Moon", 1, true), "still Tarn")
    -- Nothing matching: back to what Enter kept (every linen match).
    searchType("zzz")
    local kept = select(3, ns.BagsState())
    eq(kept and kept[2589] and kept[2996], true)
    eq(select(2, ns.BagsState()), "bags")
    -- @craft: what the ticked characters can make. Tarn makes no gloves; ticking Smith too does.
    f:Hide()
    bags.searchButton.scripts.OnClick(bags.searchButton)
    assert(f.title.text:find("Tarn Moon", 1, true))
    searchType("@craft gloves")
    eq(searchRows(), "")
    searchTick("Smith")
    eq(f.chars.text, "2 characters")
    eq(searchRows(), "Linked Gloves = can craft: [PALADIN]Smith (Blacksmithing) · none owned")
    -- Bags window closed: opens in the middle again, for everyone.
    f:Hide()
    bags:Hide()
    SlashCmdList.ALTSFOREVERSEARCH("")
    eq(f.point[2], UIParent)
    eq(f.title.text, "Search your characters")
end)

test("with the bags window open, every match is lit; hovering one shows it, clicking keeps it; typing again lights them all", function()
    local ns = searchStart()
    AltsForeverDB.chars["Tarn Moon"].bags[6005] = 1 -- gloves: no match for "linen"
    ns.ShowBags("Tarn Moon", "bags")
    local bags = AltsForeverBagsFrame
    bags.searchButton.scripts.OnClick(bags.searchButton)
    local f = AltsForeverSearchFrame
    searchType("linen")
    eq(ns.BagsHighlight(), nil)
    local set = select(3, ns.BagsState())
    eq(set[2589] and set[2996], true, "linen and the bolt")
    local alpha = {}
    for _, slot in ipairs({ bags.content:GetChildren() }) do
        if slot.id and slot:IsShown() then alpha[slot.id] = slot.icon:GetAlpha() end
    end
    eq(alpha[2589], 1); eq(alpha[2996], 1)
    eq(alpha[6005], 0.25, "everything else dimmed")
    eq(bags.bags.text, "Bags (23)", "both counted")
    -- Hovering a row changes nothing in the bags window.
    local rows = {}
    for _, r in ipairs({ f:GetChildren() }) do
        if r.index then rows[r.index] = r end
    end
    -- Hovering a row shows its item alone while the mouse is on it, without picking it.
    rows[2].scripts.OnEnter(rows[2])
    eq(ns.BagsHighlight(), 2996, "hovering shows the bolt alone")
    eq(searchRowLit(), nil, "but doesn't pick it")
    eq(bags.bags.text, "Bags (3)")
    rows[2].scripts.OnLeave(rows[2])
    eq(ns.BagsHighlight(), nil, "off it: every match again")
    eq(select(3, ns.BagsState())[2589], true)
    eq(bags.bags.text, "Bags (23)")
    -- Clicked: only that one, kept, and nothing put in chat.
    rows[2].scripts.OnEnter(rows[2])
    rows[2].scripts.OnClick(rows[2], "LeftButton")
    eq(#wow.chatLinks + #wow.openedChat, 0, "a plain click links nothing")
    eq(ns.BagsHighlight(), 2996, "the bolt alone")
    eq(searchRowLit(), 2996)
    eq(bags.bags.text, "Bags (3)")
    eq(bags.clear.text.text, "Showing: Bolt of Linen Cloth")
    eq(f:IsShown(), true, "the search stays open")
    -- Hovering another shows it; off it, back to the one picked.
    rows[2].scripts.OnLeave(rows[2])
    rows[1].scripts.OnEnter(rows[1])
    eq(ns.BagsHighlight(), 2589, "hovering the linen shows it")
    eq(searchRowLit(), 2996, "the bolt still picked")
    rows[1].scripts.OnLeave(rows[1])
    eq(ns.BagsHighlight(), 2996, "off it: the bolt again")
    -- Shift-click links it in chat and changes nothing else.
    local modified = IsModifiedClick
    IsModifiedClick = function() return true end
    rows[1].scripts.OnClick(rows[1], "LeftButton")
    rows[2].scripts.OnClick(rows[2], "LeftButton")
    IsModifiedClick = modified
    eq(#wow.chatLinks + #wow.openedChat, 2, "each shift-click linked it")
    eq(searchRowLit(), 2996, "shift-click: the bolt still picked")
    eq(ns.BagsHighlight(), 2996, "and still lit")
    -- Clicking the picked one again unpicks it: every match lit again, though the mouse is on it.
    rows[2].scripts.OnEnter(rows[2])
    rows[2].scripts.OnClick(rows[2], "LeftButton")
    eq(#wow.chatLinks + #wow.openedChat, 2, "unpicking links nothing")
    eq(searchRowLit(), nil, "unpicked")
    eq(ns.BagsHighlight(), nil)
    eq(select(3, ns.BagsState())[2589], true, "every match lit")
    eq(bags.bags.text, "Bags (23)")
    -- Shift-click with nothing picked: still nothing picked.
    IsModifiedClick = function() return true end
    rows[2].scripts.OnClick(rows[2], "LeftButton")
    IsModifiedClick = modified
    eq(searchRowLit(), nil, "shift-click picks nothing")
    eq(select(3, ns.BagsState())[2589], true, "every match still lit")
    rows[2].scripts.OnLeave(rows[2])
    -- Picked again, then the bags window's "Showing" line: every slot there, nothing picked here.
    rows[2].scripts.OnClick(rows[2], "LeftButton")
    eq(searchRowLit(), 2996)
    bags.clear.scripts.OnClick(bags.clear)
    eq(ns.BagsLighting(), false, "every slot shown")
    eq(searchRowLit(), nil, "the search unpicked too")
    eq(bags.bags.text, "Bags")
    -- Typing again (the mouse left resting on a row): nothing picked, every match lit again.
    rows[1].scripts.OnEnter(rows[1])
    searchType("linen c")
    eq(ns.BagsHighlight(), nil)
    eq(select(3, ns.BagsState())[2589], true)
    eq(searchRowLit(), nil)
    -- Clearing the "Showing" line in the bags window shows every slot.
    bags.clear.scripts.OnClick(bags.clear)
    eq(ns.BagsLighting(), false)
    eq(bags.bags.text, "Bags")
    -- Without the bags window, the first result is Enter's, as before.
    f:Hide()
    bags:Hide()
    SlashCmdList.ALTSFOREVERSEARCH("linen")
    eq(searchRowLit(), 2589, "the first row marked")
end)

test("the arrow keys take over from the row under the mouse; choosing from the right-click menu picks that result", function()
    local ns = searchStart()
    ns.ShowBags("Tarn Moon", "bags")
    local bags = AltsForeverBagsFrame
    bags.searchButton.scripts.OnClick(bags.searchButton)
    local f, box = AltsForeverSearchFrame, AltsForeverSearchBox
    searchType("linen")
    local rows = {}
    for _, r in ipairs({ f:GetChildren() }) do
        if r.index then rows[r.index] = r end
    end
    eq(rows[1].entry.id, 2589); eq(rows[2].entry.id, 2996)
    -- The mouse on the bolt, then Down: the keys pick the linen, and everything follows them.
    rows[2].scripts.OnEnter(rows[2])
    eq(ns.BagsHighlight(), 2996, "hovering the bolt")
    box.scripts.OnArrowPressed(box, "DOWN")
    eq(searchRowLit(), 2589, "Down picks the linen")
    eq(GameTooltip.itemID, 2589, "the tooltip follows")
    eq(ns.BagsHighlight(), 2589, "and so does the bags window, though the mouse is on the bolt")
    eq(bags.bags.text, "Bags (20)")
    rows[2].scripts.OnLeave(rows[2])
    eq(ns.BagsHighlight(), 2589)
    -- Right-click the bolt: the menu alone changes nothing.
    rows[2].scripts.OnClick(rows[2], "RightButton")
    eq(searchRowLit(), 2589, "a menu closed without a choice picks nothing")
    -- Choosing Tarn's bags from it picks the bolt, so hovering and leaving comes back to it.
    wow.menuItem("[DRUID]Tarn Moon: 3 in bags").fn()
    eq(searchRowLit(), 2996, "chosen: the bolt picked")
    eq(ns.BagsHighlight(), 2996)
    rows[1].scripts.OnEnter(rows[1])
    eq(ns.BagsHighlight(), 2589, "hovering the linen")
    rows[1].scripts.OnLeave(rows[1])
    eq(ns.BagsHighlight(), 2996, "off it: back to the bolt just chosen")
    -- Link in chat from the menu picks nothing.
    rows[1].scripts.OnClick(rows[1], "RightButton")
    wow.menuItem("Link in chat").fn()
    eq(searchRowLit(), 2996, "linking leaves the pick alone")
end)

test("every match is lit, not only the 50 listed", function()
    local ns = searchStart()
    -- 55 rags, all Tarn's: the last (one, so it sorts last) isn't among the 50 rows.
    for i = 1, 55 do
        local id = 8200 + i
        wow.item(id, "Rag " .. (100 + i), {})
        AltsForeverDB.chars["Tarn Moon"].bags[id] = i == 55 and 1 or 2
    end
    ns.ShowBags("Tarn Moon", "bags")
    local bags = AltsForeverBagsFrame
    bags.searchButton.scripts.OnClick(bags.searchButton)
    searchType("rag")
    eq(#ns.SearchMatches("rag"), 50, "50 rows listed")
    searchType("rag")
    local set = select(3, ns.BagsState())
    eq(set[8255], true, "the 55th lit too")
    eq(bags.bags.text, "Bags (" .. (54 * 2 + 1) .. ")", "and counted")
    local alpha
    for _, slot in ipairs({ bags.content:GetChildren() }) do
        if slot.id == 8255 and slot:IsShown() then alpha = slot.icon:GetAlpha() end
    end
    eq(alpha, 1, "not dimmed")
end)

test("a worn item opens their gear on the far side of the search from the bags window, and the search stays open", function()
    local ns = searchStart()
    AltsForeverDB.chars["Smith"].equip = { [6001] = 1 }
    ns.ShowBags("Tarn Moon", "bags")
    local bags = AltsForeverBagsFrame
    bags.searchButton.scripts.OnClick(bags.searchButton)
    local f, box = AltsForeverSearchFrame, AltsForeverSearchBox
    searchTick("All characters")
    local screen = UIParent.width
    UIParent.width = 2560
    -- The search right of the bags window: the gear goes right of the search.
    bags.GetLeft = function() return 100 end
    f.GetLeft, f.GetRight = function() return 800 end, function() return 1280 end
    searchType("linked")
    box.scripts.OnEnterPressed(box)
    local gear = AltsForeverGearFrame
    eq(gear:IsShown(), true)
    eq(f:IsShown(), true, "the search stays open")
    eq(gear.point[1], "TOPLEFT")
    eq(gear.point[2], f)
    eq(gear.point[3], "TOPRIGHT")
    box.scripts.OnEnterPressed(box)
    eq(gear:IsShown(), true, "picking it again doesn't close it")
    -- The search left of the bags window: the gear goes left of it.
    bags.GetLeft = function() return 1300 end
    box.scripts.OnEnterPressed(box)
    eq(gear.point[1], "TOPRIGHT")
    eq(gear.point[3], "TOPLEFT")
    -- No room right of the search on the screen: left of it.
    bags.GetLeft = function() return 100 end
    UIParent.width = 1400
    gear.width = 440
    box.scripts.OnEnterPressed(box)
    eq(gear.point[1], "TOPRIGHT")
    gear:Hide()
    f:Hide()
    bags:Hide()
    bags.GetLeft, f.GetLeft, f.GetRight = nil, nil, nil
    UIParent.width = screen
end)

test("the character menu: all, or any you tick; one ticked names them, several count them", function()
    local ns = searchStart()
    SlashCmdList.ALTSFOREVERSEARCH("linen")
    local f = AltsForeverSearchFrame
    eq(f.chars.text, "All characters")
    f.chars.scripts.OnClick(f.chars)
    -- Only characters tooltips show (Far Away is on another ruleset); the game says yours
    -- is Normal.
    eq(menuTexts(), "All characters | nil | Normal | [MAGE]Aldric | [PALADIN]Smith | [DRUID]Tarn Moon")
    eq(wow.menu.items[1].isSelected(), true)
    -- Ticking one while all are searched: just them.
    searchTick("Aldric")
    eq(f.chars.text, "[MAGE]Aldric")
    assert(f.title.text:find("Aldric", 1, true))
    eq(searchRows(), "Linen Cloth (5) = [MAGE]Aldric 5")
    f.chars.scripts.OnClick(f.chars)
    eq(wow.menu.items[1].isSelected(), false)
    eq(wow.menu.items[4].isSelected(), true)
    searchTick("Tarn")
    eq(f.chars.text, "2 characters")
    eq(f.title.text, "Search your characters")
    eq(searchRows(), "Linen Cloth (25) = [DRUID]Tarn 20, [MAGE]Aldric 5\n"
        .. "Bolt of Linen Cloth (3) = [DRUID]Tarn 3")
    -- Unticking both: all of them again.
    searchTick("Aldric")
    searchTick("Tarn")
    eq(f.chars.text, "All characters")
    assert(searchRows():find("can craft: [PALADIN]Smith", 1, true), "Smith's crafts back")
    f:Hide()
end)

test("opened from the bags window of a character on another ruleset, the search finds their items", function()
    local ns = searchStart()
    ns.ShowBags("Far Away", "bags")
    AltsForeverBagsFrame.searchButton.scripts.OnClick(AltsForeverBagsFrame.searchButton)
    searchType("gloves")
    assert(searchRows():find("Far Gloves", 1, true), searchRows())
    searchType("linen")
    assert(searchRows():find("99", 1, true), searchRows())
    -- Searching everyone again: they're hidden from tooltips, so out of it as before.
    AltsForeverSearchFrame:Hide()
    AltsForeverBagsFrame:Hide()
    ns.ToggleSearch("gloves")
    eq(searchRows():find("Far Gloves", 1, true), nil, searchRows())
end)

test("the search running again for late names keeps the selected item and the scroll; typing starts at the top", function()
    searchStart()
    for id = 8101, 8112 do
        wow.item(id, "Rag " .. id, {})
        AltsForeverDB.chars["Tarn Moon"].bags[id] = 1
    end
    wow.item(7002, "Gone Rag", {})
    wow.itemNames[7002] = nil -- never loads, so it keeps trying
    AltsForeverDB.chars["Tarn Moon"].bags[7002] = 1
    wow.timers = {}
    SlashCmdList.ALTSFOREVERSEARCH("rag")
    local box = AltsForeverSearchBox
    for _ = 1, 10 do box.scripts.OnArrowPressed(box, "DOWN") end
    local rows = {}
    for _, r in ipairs({ AltsForeverSearchFrame:GetChildren() }) do
        if r.index then rows[r.index] = r end
    end
    local function lit()
        for _, r in ipairs(rows) do if r.lit:IsShown() then return r.entry.id end end
    end
    eq(rows[1].entry.id, 8104); eq(lit(), 8111)
    runTimers() -- the second's search again
    eq(#wow.timers, 1, "still waiting for the name")
    eq(rows[1].entry.id, 8104, "scrolled where it was")
    eq(lit(), 8111, "the same item selected")
    searchType("rag")
    eq(rows[1].entry.id, 8101, "typing: back to the top")
    eq(lit(), 8101)
end)

test("names slower than a second are still waited for, a few times, then no more", function()
    searchStart()
    wow.item(7001, "Late Cloth", {})
    wow.item(7002, "Gone Cloth", {})
    local late = wow.itemNames[7001]
    wow.itemNames[7001], wow.itemNames[7002] = nil, nil
    AltsForeverDB.chars["Tarn Moon"].bags[7001] = 4
    AltsForeverDB.chars["Tarn Moon"].bags[7002] = 1 -- never loads
    wow.timers = {}
    SlashCmdList.ALTSFOREVERSEARCH("late")
    runTimers()
    eq(searchRows(), "", "not yet after a second")
    wow.itemNames[7001] = late
    runTimers()
    eq(searchRows(), "Late Cloth (4) = [DRUID]Tarn 4", "two seconds in")
    local tries = 0
    while #wow.timers > 0 and tries < 20 do tries = tries + 1 runTimers() end
    eq(#wow.timers, 0, "stopped")
    assert(tries <= 3, tries)
end)

test("a search the player has put somewhere stays there when a result opens the bags", function()
    local ns = searchStart()
    SlashCmdList.ALTSFOREVER("")
    SlashCmdList.ALTSFOREVERSEARCH("linen")
    local search, box = AltsForeverSearchFrame, AltsForeverSearchBox
    -- Dragged to the side of the screen.
    search.rect = { 1500, 1900, 1000, 600 }
    search.scripts.OnDragStop(search)
    search.point = { "TOPLEFT", UIParent, "BOTTOMLEFT", 1500, 1000 } -- where the drag left it
    box.scripts.OnEnterPressed(box)
    eq(AltsForeverBagsFrame:IsShown(), true, "the bags window opens")
    eq(search.point[2], UIParent, "the search hasn't moved")
    eq(search.point[4], 1500)
    -- Closed and opened again with the bags window still open: where it was left.
    ns.ToggleSearch()
    search.point = nil
    ns.ToggleSearch()
    eq(search.point[2], UIParent); eq(search.point[4], 1500)
    -- Positions reset: beside the bags window again, as before it was moved.
    ns.ToggleSearch()
    SlashCmdList.ALTSFOREVER("resetwindows")
    ns.ToggleSearch()
    eq(search.point[2], AltsForeverBagsFrame)
end)
