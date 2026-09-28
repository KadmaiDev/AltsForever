-- Tests: choosing the tooltip icons. Loaded by tests/run.lua.
ICON_CROP = ":0:0:0:0:64:64:5:59:5:59|t"

test("an icon picked for a place shows in item tooltips, words too, and reset brings back the default", function()
    local ns = wow.load(FILES)
    wow.setBag(0, 16, { [1] = { 100, 12 } })
    wow.login(nil)
    local function line() return wow.hover(GameTooltip, 100)[2][2] end
    eq(line(), R("Bags 12", 12), "the default bag icon")
    ns.SetPlaceIcon("bags", 134400)
    eq(line(), "|cffe0e0e0|T134400" .. ICON_CROP .. " 12|r    12", "the chosen icon, cropped")
    eq(AltsForeverDB.icons.bags, 134400, "saved")
    ns.SetPlaceIcon("bags", "words")
    eq(line(), "|cffe0e0e0Bags 12|r    12", "words instead")
    ns.SetPlaceIcon("bags", nil)
    eq(line(), R("Bags 12", 12))
    eq(AltsForeverDB.icons, nil, "nothing saved once everything is back to default")
end)

test("the picker: recommended icons, then every spell or item icon in a scrolling grid", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    ns.OpenIconPicker("bank")
    local p = ns.IconPicker()
    eq(p.title.text, "Icon for Bank")
    eq(#p.recommended, 6)
    eq(p.recommended[1].value, "Interface\\Minimap\\Tracking\\Banker", "the default is recommended first")
    eq(p.recommended[1].selected:IsShown(), true, "and marked as the current one")
    ns.OpenIconPicker("bags")
    eq(p.recommended[1].value, 133652, "bags: the default bag's icon first")
    eq(p.recommended[1].selected:IsShown(), true)
    ns.OpenIconPicker("bank")
    eq(p.grid[1].value, 136001, "spell icons first")
    eq(p.counter.text, "1-30 of 30")
    p.itemTab.scripts.OnClick(p.itemTab)
    eq(p.grid[1].value, 133001, "item icons")
    eq(p.counter.text, "1-84 of 200")
    p.gridFrame.scripts.OnMouseWheel(p.gridFrame, -1)
    eq(p.grid[1].value, 133025, "scrolled two rows of 12")
    p.slider.scripts.OnValueChanged(p.slider, 5)
    eq(p.grid[1].value, 133061, "the scroll bar")
    p.grid[3].scripts.OnClick(p.grid[3])
    eq(AltsForeverDB.icons.bank, 133063, "a click picks it")
    eq(p.grid[3].selected:IsShown(), true)
    assert(p.preview.text:find("133063", 1, true), "the preview shows it")
    p.words.scripts.OnClick(p.words)
    eq(AltsForeverDB.icons.bank, "words")
    p.reset.scripts.OnClick(p.reset)
    eq(AltsForeverDB.icons, nil)
    -- Closing lets the big lists go.
    p:Hide()
    p.scripts.OnHide(p)
    eq(p.list, nil); eq(p.browse, nil); eq(p.pool, nil)
end)

test("the picker's search finds icons by item and spell name", function()
    local ns = wow.load(FILES)
    wow.itemNames[4238], wow.itemIcons[4238] = "Linen Bag", 133639
    wow.itemNames[2589], wow.itemIcons[2589] = "Linen Cloth", 132889
    wow.itemNames[2775], wow.itemIcons[2775] = "Silver Ore", 134579
    C_SpellBook = {
        GetNumSpellBookSkillLines = function() return 1 end,
        GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = 1 } end,
        GetSpellBookItemInfo = function() return { name = "Linen Blessing", iconID = 135920 } end,
    }
    Enum.SpellBookSpellBank = { Player = 0 }
    wow.login({ v = 2, chars = { ["Aldric"] = alt("Aldric", "MAGE", {}),
        ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { bank = { [4238] = 1, [2775] = 3 }, crafts = { Tailoring = { [2589] = "linen cloth" } } }) } })
    ns.OpenIconPicker("bags")
    local p = ns.IconPicker()
    p.search:SetText("LINEN")
    p.search.scripts.OnTextChanged(p.search, true)
    local found = {}
    for _, b in ipairs(p.grid) do if b.value then found[#found + 1] = b.value end end
    table.sort(found)
    eq(table.concat(found, ","), "132889,133639,135920", "a bag, a crafted item and a spell; not the ore")
    p.search:SetText("mithril")
    p.search.scripts.OnTextChanged(p.search, true)
    assert(p.counter.text:find("Nothing found", 1, true), p.counter.text)
    p.search:SetText("")
    p.search.scripts.OnTextChanged(p.search, true)
    eq(p.grid[1].value, 136001, "cleared: back to browsing")
    C_SpellBook, Enum.SpellBookSpellBank = nil, nil
end)

test("the Options page lists each place's icon, and Change... opens the picker for it", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    local f = showOptionsPage()
    assert(f.icons.mail.text:find("Mail:", 1, true) and f.icons.mail.text:find("Mailbox", 1, true), f.icons.mail.text)
    ns.SetPlaceIcon("mail", "words")
    eq(f.icons.mail.text, "Mail:  Mail 23", "updates straight away")
    SlashCmdList.ALTSFOREVER("icons")
    eq(wow.settingsOpened, 77, "/af icons opens this page")
end)
