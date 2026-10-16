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
    -- @owned, @mine and @craft narrow it (any start of the word). With @craft, who can make
    -- it comes first.
    searchType("@craft l")
    eq(searchRows(), "Linked Gloves = can craft: [PALADIN]Smith (Blacksmithing) · none owned\nBolt of Linen Cloth (3) = can craft: [PALADIN]Smith (Tailoring) · [DRUID]Tarn 3",
        "starts with it, then a later word")
    searchType("@own linen")
    eq(searchRows(), "Linen Cloth (25) = [DRUID]Tarn 20, [MAGE]Aldric 5\nBolt of Linen Cloth (3) = [DRUID]Tarn 3 · can craft: [PALADIN]Smith (Tailoring)",
        "any of your characters")
    -- @mine: only what the character you're on has; they come first, and the number is theirs.
    searchType("@mine linen")
    eq(searchRows(), "Linen Cloth (5) = [MAGE]Aldric 5, [DRUID]Tarn 20")
    searchType("@m silk")
    eq(searchRows(), "", "Tarn's, not yours")
    -- Nothing typed yet: what it does and the three words; nothing found: it says so.
    searchType("")
    eq(searchRows(), "")
    eq(AltsForeverSearchFrame.hint:IsShown(), true)
    local hint = AltsForeverSearchFrame.hint.text
    assert(hint:find("@owned", 1, true) and hint:find("@mine", 1, true) and hint:find("@craft", 1, true), hint)
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

test("Enter opens the bags of whoever has it, lit up (you first); arrows move; Shift+Enter or nobody owning it links it", function()
    local ns = searchStart()
    SlashCmdList.ALTSFOREVERSEARCH("linen")
    local box = AltsForeverSearchBox
    -- Aldric (you) has 5 in the bank: that's what opens, with the linen lit up.
    box.scripts.OnEnterPressed(box)
    eq(AltsForeverSearchFrame:IsShown(), false, "the search closes")
    eq(AltsForeverBagsFrame:IsShown(), true)
    eq(ns.BagsHighlight(), 2589)
    eq(AltsForeverBagsFrame.who.text:find("Aldric", 1, true) ~= nil, true)
    -- Another character's bags: switching view clears the highlight.
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
    eq(AltsForeverBagsFrame.info:IsShown(), false)
    clear.scripts.OnClick(clear)
    eq(ns.BagsHighlight(), nil)
    eq(clear:IsShown(), false)
    eq(AltsForeverBagsFrame.info:IsShown(), true)
    for _, slot in ipairs({ AltsForeverBagsFrame.content:GetChildren() }) do
        if slot.id and slot:IsShown() then eq(slot.icon:GetAlpha(), 1, "every slot back") end
    end
    -- The bags window's own search button.
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
    -- Nobody has it: Enter links it, into the chat box being typed in.
    wow.chatOpen = true
    searchType("linked")
    box.scripts.OnEnterPressed(box)
    assert(wow.chatLinks[#wow.chatLinks]:find("Linked Gloves", 1, true))
    -- Only in the mail: said so.
    searchType("silk")
    box.scripts.OnEnterPressed(box)
    assert(wow.printed[#wow.printed]:find("has it in the mail", 1, true), wow.printed[#wow.printed])
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
    eq(wow.menu.items[2].enabled, false, "mail can't be opened")
    searchType("linen")
    row.scripts.OnClick(row, "RightButton")
    eq(menuTexts(), "Linen Cloth | [DRUID]Tarn Moon: 20 in bags | [MAGE]Aldric: 5 in the bank | Link in chat")
    wow.menu.items[2].fn()
    eq(AltsForeverSearchFrame:IsShown(), false)
    assert(f.who.text:find("Tarn Moon", 1, true))
    eq(ns.BagsHighlight(), 2589)
end)
