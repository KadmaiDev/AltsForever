-- Tests: the character window (Recipes.lua's frame with Sheets.lua's pages): Character,
-- Reputation and Skills tabs, then one per profession. Loaded by tests/run.lua.

-- The list rows of a Skills or Reputation page as text: "# Heading", "Name = bar text".
-- A row bar's colour: the game's bar tints its fill; the plain one is a StatusBar.
function barTint(bar)
    return bar.game and bar.Fill.tint or bar.barColour
end

function sheetRows(page)
    local out = {}
    for _, row in ipairs(page.list.rows) do
        if row:IsShown() then
            if row.headText:IsShown() then
                out[#out + 1] = "# " .. row.headText:GetText()
            else
                local text = row.label:GetText()
                if row.bar:IsShown() then text = text .. " = " .. tostring(row.bar.text:GetText()) end
                out[#out + 1] = text
            end
        end
    end
    return table.concat(out, " | ")
end

-- Whether a side tab is the one picked (the shared template, or our stand-in for it).
function tabOn(tab)
    if tab.selectedTex then return tab.selectedTex:IsShown() == true end
    return tab:GetChecked() == true
end

function cwChars()
    return {
        ["Vesp Ash"] = alt("Vesp Ash", "PALADIN", { level = 44, xp = 500, xpMax = 1000, money = 123456,
            profs = { Blacksmithing = 210, Mining = 197, Cooking = 75 }, profMax = { Blacksmithing = 225, Mining = 225, Cooking = 150 },
            prof1 = "Blacksmithing", prof2 = "Mining", reps = { [68] = 3500, [76] = 42999, [530] = -4000 },
            skills = { [95] = 200220, [54] = 180220, [160] = 210220, [415] = 1001, [414] = 1001, [413] = 1001, [433] = 1001 },
            ilvl = 35, dura = 80, zone = "Undercity", updated = 1000 }),
        ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { level = 12 }),
    }
end

function cwStart()
    local ns = wow.load(FILES)
    wow.skills = skMage()
    local saved = { v = 2, chars = cwChars(), factions = { [68] = "Undercity", [76] = "Orgrimmar", [530] = "Darkspear Trolls" } }
    wow.login(saved)
    return ns
end

test("the Skills page lists professions, weapon skills and armour as the game's Skills tab does", function()
    local ns = cwStart()
    local sections = ns.SkillSections(ns.db.chars["Vesp Ash"])
    local names = {}
    for _, s in ipairs(sections) do names[#names + 1] = s.name .. " (" .. #s.rows .. ")" end
    eq(table.concat(names, ", "), "Professions (2), Secondary professions (1), Weapon skills (8), Armor proficiencies (5)")
    local f
    ns.ShowCharacter("Vesp Ash", "skills")
    f = AltsForeverCharacterFrame
    eq(f:IsShown(), true)
    eq(f.titleText, "Skills")
    local page = ns.CharacterPage("skills")
    eq(page:IsShown(), true)
    eq(f.profPage:IsShown(), false, "the professions page is out of the way")
    eq(sheetRows(page), "# Professions | Blacksmithing = 210 / 225 | Mining = 197 / 225 | # Secondary professions | Cooking = 75 / 150"
        .. " | # Weapon skills | Defense = 200 / 220 | One-Handed Maces = 180 / 220 | Two-Handed Maces = 210 / 220"
        .. " | One-Handed Axes = |cff9d9d9dNot trained|r | One-Handed Swords = |cff9d9d9dNot trained|r"
        .. " | Polearms = |cff9d9d9dNot trained|r | Two-Handed Axes = |cff9d9d9dNot trained|r | Two-Handed Swords = |cff9d9d9dNot trained|r"
        .. " | # Armor proficiencies", "15 rows fit; the armour comes on the next page")
end)

test("the Skills page: headings fold away, the list scrolls, untrained armour says when it comes", function()
    local ns = cwStart()
    ns.db.chars["Vesp Ash"].level = 38
    ns.ShowCharacter("Vesp Ash", "skills")
    local page = ns.CharacterPage("skills")
    local list = page.list
    local first = list.rows[1]
    first.scripts.OnClick(first) -- fold Professions
    assert(sheetRows(page):find("^# Professions | # Secondary professions"), sheetRows(page))
    list.scripts.OnMouseWheel(list, -1)
    assert(sheetRows(page):find("Plate = |cff9d9d9dat level 40|r", 1, true), sheetRows(page))
    list.scripts.OnMouseWheel(list, 1) -- back to the top
    first.scripts.OnClick(first)
    ns.db.chars["Vesp Ash"].level = 44
    ns.ShowCharacter("Vesp Ash", "skills", nil, true)
    eq(list.down:IsShown(), true, "more rows than fit: the page arrows show")
    list.scripts.OnMouseWheel(list, -1)
    list.scripts.OnMouseWheel(list, -1)
    eq(list.offset, 5, "as far as the last row")
    assert(sheetRows(page):find("Plate = |cff9d9d9dNot trained|r$"), sheetRows(page))
    -- Hovering a weapon skill says how far behind it is; an untrained one, where to learn it.
    for _, row in ipairs(list.rows) do
        if row:IsShown() and row.label:GetText() == "One-Handed Maces" then row.scripts.OnEnter(row) end
    end
    local lines = {}
    for _, l in ipairs(GameTooltip.lines) do lines[#lines + 1] = l[1] end
    eq(table.concat(lines, " | "), "One-Handed Maces | 180 / 220 | 40 below the most for their level")
end)

-- A player's request (2026-11-28): a profession not being levelled, left out of skill-up hints.
function skillRow(page, name)
    for _, row in ipairs(page.list.rows) do
        if row:IsShown() and row.label:IsShown() and row.label:GetText() == name then return row end
    end
end

test("the Skills page has a levelling tick on each profession, the same as the character menu's", function()
    local ns = cwStart()
    ns.ShowCharacter("Vesp Ash", "skills")
    local page = ns.CharacterPage("skills")
    local cooking = skillRow(page, "Cooking")
    eq(cooking.check:IsShown(), true); eq(cooking.check:GetChecked(), true)
    eq(skillRow(page, "Defense").check:IsShown(), false, "weapon skills have none")
    eq(page.list.rows[1].check:IsShown(), false, "nor headings")
    cooking.check.scripts.OnEnter(cooking.check)
    eq(GameTooltip.lines[2][1], "Being levelled: shown in skill-up hints. Untick to leave it out.")
    -- Unticked (the game ticks the box before OnClick).
    cooking.check:SetChecked(false)
    cooking.check.scripts.OnClick(cooking.check)
    local c = ns.db.chars["Vesp Ash"]
    eq(c.notLevelling.Cooking, true)
    assert(sheetRows(page):find("Cooking = 75 / 150  (not levelling)", 1, true), sheetRows(page))
    cooking = skillRow(page, "Cooking")
    eq(cooking.check:GetChecked(), false, "the page was filled again")
    eq(barTint(cooking.bar)[1], 0.35, "greyed")
    cooking.check.scripts.OnEnter(cooking.check)
    eq(GameTooltip.lines[2][1], "Not being levelled: left out of skill-up hints. Tick to bring it back.")
    -- The character menu agrees, and ticking there shows here.
    ns.ShowCharacterMenu(UIParent, "Vesp Ash")
    local item
    for _, it in ipairs(wow.menuItem("Skill-ups").items) do if it.text == "Cooking" then item = it end end
    eq(item.isSelected(), false)
    item.setSelected()
    eq(c.notLevelling, nil)
    eq(skillRow(page, "Cooking").check:GetChecked(), true)
    assert(sheetRows(page):find("Cooking = 75 / 150 |", 1, true), sheetRows(page))
end)

-- Owner's screenshots, 2026-11-28: the bars as the game's own Reputation window draws them.
test("Skills and Reputation bars are the game's own, the fill cut to the share; without it, plain ones", function()
    local ns = cwStart()
    ns.ShowCharacter("Vesp Ash", "reputation")
    local page = ns.CharacterPage("reputation")
    local bar
    for _, row in ipairs(page.list.rows) do
        if row:IsShown() and row.label:GetText() == "Undercity" then bar = row.bar end
    end
    eq(bar.template, "ColoredProgressBarTemplate")
    eq(bar.game, true)
    eq(bar.fillPercent, 500 / 6000, "Friendly 500 of 6000")
    eq(bar.text.point[5], 1, "its text a pixel up")
    eq(bar.Text:GetText(), "Friendly  500 / 6000")
    -- A client without the template: our plain bar.
    ns = wow.load(FILES)
    wow.missingTemplates["ColoredProgressBarTemplate"] = true
    wow.skills = skMage()
    wow.login({ v = 2, chars = cwChars(), factions = { [68] = "Undercity" } })
    ns.ShowCharacter("Vesp Ash", "reputation")
    page = ns.CharacterPage("reputation")
    bar = page.list.rows[1].bar
    eq(bar.game, nil); eq(bar.kind, "StatusBar")
    assert(sheetRows(page):find("Undercity = Friendly  500 / 6000", 1, true), sheetRows(page))
    eq(bar.text.font[3], "OUTLINE", "the plain bar's text is outlined")
    wow.missingTemplates["ColoredProgressBarTemplate"] = nil
end)

test("the Skills page for a character whose weapon skills haven't been read says so", function()
    local ns = cwStart()
    ns.ShowCharacter("Tarn Moon", "skills")
    eq(sheetRows(ns.CharacterPage("skills")), "# Weapon skills | |cff9d9d9dNot read yet: log in on Tarn Moon once.|r")
end)

test("the Reputation page lists the character's standings by name, coloured by standing", function()
    local ns = cwStart()
    ns.ShowCharacter("Vesp Ash", "reputation")
    local f = AltsForeverCharacterFrame
    eq(f.titleText, "Reputation")
    local page = ns.CharacterPage("reputation")
    eq(sheetRows(page), "Darkspear Trolls = Hostile  2000 / 3000 | Orgrimmar = Exalted | Undercity = Friendly  500 / 6000")
    ns.ShowCharacter("Tarn Moon", "reputation", nil, true)
    eq(page.list.empty:IsShown(), true)
    eq(page.list.empty:GetText(), "Tarn Moon has no reputation recorded yet.")
end)

test("Reputation bars take the game's darker bar colours; the game's bar text isn't outlined, as the game's", function()
    local ns = cwStart()
    ns.ShowCharacter("Vesp Ash", "reputation")
    local rows = {}
    for _, row in ipairs(ns.CharacterPage("reputation").list.rows) do
        if row:IsShown() and row.bar:IsShown() then rows[row.label:GetText()] = row.bar end
    end
    -- No FACTION_BAR_COLORS in the fake: retail's values.
    eq(table.concat(barTint(rows["Darkspear Trolls"]), ","), "0.8,0.3,0.22")
    eq(table.concat(barTint(rows["Undercity"]), ","), "0,0.6,0.1")
    eq(rows["Undercity"].text.font[3], nil)
    -- The game's own table wins when it's there.
    FACTION_BAR_COLORS = { [4] = { r = 0.5, g = 0.4, b = 0.1 } }
    eq(table.concat({ ns.StandingBarColour(4) }, ","), "0.5,0.4,0.1")
    eq(table.concat({ ns.StandingBarColour(5) }, ","), "0,0.6,0.1")
    FACTION_BAR_COLORS = nil
end)

test("the Character page: gear in the game's layout, and what's known about them between", function()
    local ns = cwStart()
    ns.ShowCharacter("Vesp Ash")
    local f = AltsForeverCharacterFrame
    eq(f.titleText, "[PALADIN]Vesp Ash")
    eq(f.tabs[1].icon.texture, "Interface\\Icons\\ClassIcon_Paladin")
    eq(tabOn(f.tabs[1]), true)
    local facts = characterFacts(ns)
    assert(facts:find("Level = 44  |cff9d9d9d50%|r", 1, true), facts)
    assert(facts:find("Item level = 35", 1, true), facts)
    assert(facts:find("Zone = Undercity", 1, true), facts)
    assert(facts:find("Gold = ", 1, true), facts)
    assert(not facts:find("Bank", 1, true), "nothing unknown is listed")
end)

test("the side tabs: the three pages, then each profession; the picker keeps the page", function()
    local ns = cwStart()
    ns.ShowCharacter("Vesp Ash", "reputation")
    local f = AltsForeverCharacterFrame
    local labels = {}
    for _, tab in ipairs(f.tabs) do if tab:IsShown() then labels[#labels + 1] = tab.label end end
    eq(table.concat(labels, ", "), "Character, Reputation, Skills, Blacksmithing, Mining, Cooking")
    eq(tabOn(f.tabs[2]), true)
    -- A profession tab: the professions page with its rank bar.
    f.tabs[4].scripts.OnClick(f.tabs[4])
    eq(f.titleText, "Blacksmithing")
    eq(f.profPage:IsShown(), true)
    eq(ns.CharacterPage("reputation"):IsShown(), false)
    eq(tabOn(f.tabs[4]), true); eq(tabOn(f.tabs[2]), false)
    -- The skills tab, then another character from the picker: still on Skills.
    f.tabs[3].scripts.OnClick(f.tabs[3])
    f.who.scripts.OnClick(f.who)
    local pick = wow.menuItem("[DRUID]Tarn Moon")
    pick.setSelected(pick.data)
    eq(f.titleText, "Skills")
    eq(select(2, ns.CharacterWindowShown()), "Tarn Moon")
    local shown = 0
    for _, tab in ipairs(f.tabs) do if tab:IsShown() then shown = shown + 1 end end
    eq(shown, 3, "no professions: just the three pages")
end)

test("the character pages are narrow, as the game's character window; professions keep their width", function()
    local ns = cwStart()
    ns.ShowCharacter("Vesp Ash", "skills")
    local f = AltsForeverCharacterFrame
    eq(f:GetWidth(), 440); eq(f:GetHeight(), 484)
    f.tabs[4].scripts.OnClick(f.tabs[4])
    eq(f:GetWidth(), 673, "a profession: the full professions window"); eq(f:GetHeight(), 594)
    f.tabs[1].scripts.OnClick(f.tabs[1])
    eq(f:GetWidth(), 440); eq(f:GetHeight(), 484)
    -- Six professions: nine side tabs reach past 484, so the window grows to hold them.
    local c = ns.db.chars["Vesp Ash"]
    c.profs.Tailoring, c.profs["First Aid"], c.profs.Alchemy = 50, 60, 70
    ns.ShowCharacter("Vesp Ash", "character", nil, true)
    local shown = 0
    for _, tab in ipairs(f.tabs) do if tab:IsShown() then shown = shown + 1 end end
    eq(shown, 9)
    eq(f:GetHeight(), 60 + 9 * 44 + 7 * 2 + 14 + 12, "the tabs' bottom and a margin")
    -- The lists fill the taller window: (496 - 78) / 26 = 16 rows, not 15.
    ns.ShowCharacter("Vesp Ash", "skills", nil, true)
    local rows = 0
    for _, row in ipairs(ns.CharacterPage("skills").list.rows) do if row:IsShown() then rows = rows + 1 end end
    eq(rows, 16)
end)

test("the character menu opens each page; the same page again from a row closes it", function()
    local ns = cwStart()
    SlashCmdList.ALTSFOREVER("")
    ns.ShowCharacterMenu(UIParent, "Vesp Ash")
    wow.menuItem("Reputation").fn()
    eq(ns.CharacterWindowShown(), "reputation")
    ns.ShowCharacterMenu(UIParent, "Vesp Ash")
    wow.menuItem("Reputation").fn()
    eq(ns.CharacterWindowShown(), "reputation", "the menu never closes it")
    ns.ShowCharacterMenu(UIParent, "Vesp Ash")
    wow.menuItem("Skills").fn()
    eq(ns.CharacterWindowShown(), "skills")
    clickRow("Vesp Ash")
    eq(ns.CharacterWindowShown(), "character", "a row opens the Character page")
    clickRow("Vesp Ash")
    eq(AltsForeverCharacterFrame:IsShown(), false, "again: closed")
end)

test("an open Character page follows your money, XP and zone, and its times each minute", function()
    local ns = wow.load(FILES)
    wow.money = 10000
    wow.login(nil)
    runTimers()
    ns.ShowCharacter(ns.charKey)
    local before = characterFacts(ns)
    wow.money = 987654
    wow.fire("PLAYER_MONEY")
    local after = characterFacts(ns)
    assert(after ~= before and after:find("98", 1, true), after)
    wow.stats.xp = 9100
    wow.fire("PLAYER_XP_UPDATE", "player")
    assert(characterFacts(ns):find("|cff9d9d9d91%|r", 1, true), characterFacts(ns))
    wow.stats.zone = "Ironforge"
    wow.fire("ZONE_CHANGED_NEW_AREA")
    assert(characterFacts(ns):find("Zone = Ironforge", 1, true), characterFacts(ns))
    -- A bag scan tells the overview; the page hears it too (its Bags line).
    ns.RefreshOverview()
    -- One minute timer at a time while it shows; none left running once it's closed.
    local ticks = 0
    for _, fn in ipairs(wow.timers) do if wow.delays[fn] == 60 then ticks = ticks + 1 end end
    eq(ticks, 1, "one refill timer, however many fills")
    AltsForeverCharacterFrame:Hide()
    runTimers()
    ticks = 0
    for _, fn in ipairs(wow.timers) do if wow.delays[fn] == 60 then ticks = ticks + 1 end end
    eq(ticks, 0, "closed: the timer isn't renewed")
end)

test("a Character page fact too long for its space is cut short, and shows whole on hover", function()
    local ns = cwStart()
    ns.ShowCharacter("Vesp Ash")
    local line = ns.CharacterPage("character").facts[1]
    line.hover.scripts.OnEnter(line.hover)
    eq(#GameTooltip.lines, 0, "nothing cut: no tooltip")
    line[2].truncated = true
    line.hover.scripts.OnEnter(line.hover)
    eq(GameTooltip.lines[1][1], "Level")
    eq(GameTooltip.lines[2][1], line[2]:GetText())
end)
