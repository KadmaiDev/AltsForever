-- Tests: the export window (Export.lua): every character as text to copy. Loaded by
-- tests/run.lua.

-- Logs in as Aldric (level 24, Engineering and Mining, 12s 34c) with Tarn Moon (everything
-- known) and Low (hardly anything known).
function exportStart(realms)
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.money = 1234
    wow.profs = { { "Engineering", 107 }, { "Mining", 99 } }
    if realms then wow.player.realm = "ClassicBetaPvE2" end
    wow.login({ v = 2, legacyPool = 16, chars = {
        ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { level = 30, xp = 2500, xpMax = 10000, rested = 16800,
            resting = true, updated = NOW - 3 * HOUR, money = 3121005, zone = "Moonglade",
            profs = { Herbalism = 160, Alchemy = 155 }, prof1 = "Herbalism", prof2 = "Alchemy",
            mail = {}, mailExpires = NOW + 2 * DAY + 4 * HOUR, played = 2 * DAY + 5 * HOUR,
            wellRested = 3, legacySpent = 3, realm = realms and "ClassicBetaPvP" or nil }),
        ["Low"] = alt("Low", "ROGUE", { level = 12, money = 500, updated = NOW - 2 * DAY,
            realm = realms and "ClassicBetaPvE2" or nil }),
    } })
    return ns
end

local function When(t) return os.date("%Y-%m-%d %H:%M", t) end

test("the export lists every character as readable lines: only what's known, no colours or icons", function()
    local ns = exportStart()
    local text = ns.ExportText(false)
    eq(text, "Alts Forever · " .. When(NOW) .. "\n"
        .. "\n"
        .. "Aldric · Mage · Level 24 (57%) · Rested 0% · 12s 34c · Engineering 107, Mining 99 · Durotar · Playing now\n"
        .. "Tarn Moon · Druid · Level 30 (25%) · Rested 168% · Well Rested 3/5 · Legacy 3/16 · 312g 10s 5c"
        .. " · Herbalism 160, Alchemy 155 · Mail expires in 2d 4h · Moonglade · Played 2d 5h · Last seen 3h ago\n"
        .. "Low · Rogue · Level 12 · 5s · Last seen 2d ago\n"
        .. "\n"
        .. "Total gold: 312g 27s 39c\n"
        .. "Total played: 2d 5h")
    assert(not text:find("|", 1, true), "no colour codes or icons")
end)

test("for spreadsheets: a header row and tab-separated columns, numbers as numbers and times as dates", function()
    local ns = exportStart()
    local lines = {}
    for line in (ns.ExportText(true) .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
    eq(#lines, 4)
    eq(lines[1], table.concat({ "Character", "Class", "Level", "XP", "Rested", "Well Rested", "Legacy spent",
        "Legacy to spend", "Gold", "Profession", "Skill", "Profession", "Skill", "Mail expires", "Zone",
        "Played (hours)", "Last seen" }, "\t"))
    eq(lines[2], table.concat({ "Aldric", "Mage", "24", "57%", "0%", "", "", "", "0.12", "Engineering", "107",
        "Mining", "99", "", "Durotar", "", When(NOW) }, "\t"))
    eq(lines[3], table.concat({ "Tarn Moon", "Druid", "30", "25%", "168%", "3", "3", "13", "312.10", "Herbalism",
        "160", "Alchemy", "155", When(NOW + 2 * DAY + 4 * HOUR), "Moonglade", "53", When(NOW - 3 * HOUR) }, "\t"))
    eq(lines[4], table.concat({ "Low", "Rogue", "12", "", "", "", "", "", "0.05", "", "", "", "", "", "", "",
        When(NOW - 2 * DAY) }, "\t"), "a blank cell for anything not known")
end)

test("characters on other rulesets are grouped as in the overview, each heading with its own gold", function()
    local ns = exportStart(true)
    local text = ns.ExportText(false)
    assert(text:find("\n\nNormal (17s 34c)\nAldric · Mage", 1, true), text)
    assert(text:find("\nLow · Rogue · Level 12 · 5s · Last seen 2d ago\n\nPvP (312g 10s 5c)\nTarn Moon · ", 1, true), text)
    assert(not text:find("Total gold", 1, true), "no total mixing gold that can't be traded")
    local tabs = ns.ExportText(true)
    assert(tabs:find("^Group\tCharacter\t"), tabs)
    assert(tabs:find("\nNormal\tAldric\t", 1, true), tabs)
    assert(tabs:find("\nPvP\tTarn Moon\t", 1, true), tabs)
end)

test("/af export and the overview's button open the export with the text selected; it can't be typed over", function()
    local ns = exportStart()
    SlashCmdList.ALTSFOREVER("export")
    local f, box = AltsForeverExportFrame, AltsForeverExportBox
    eq(f:IsShown(), true)
    eq(box:GetText(), ns.ExportText(false))
    -- Typing puts the text back.
    box:SetText("oops")
    box.scripts.OnTextChanged(box, true)
    eq(box:GetText(), ns.ExportText(false))
    -- For spreadsheets, remembered for next time.
    f.check:SetChecked(true)
    f.check.scripts.OnClick(f.check)
    eq(AltsForeverDB.exportTabs, true)
    assert(box:GetText():find("^Character\t"), box:GetText())
    box.scripts.OnEscapePressed(box)
    eq(f:IsShown(), false, "Escape closes it")
    eq(box:GetText(), "", "the text is let go when it closes")
    SlashCmdList.ALTSFOREVER("")
    AltsForeverFrame.exportButton.scripts.OnClick(AltsForeverFrame.exportButton)
    eq(f:IsShown(), true)
    eq(f.check:GetChecked(), true)
    assert(box:GetText():find("^Character\t"), "still for spreadsheets")
    SlashCmdList.ALTSFOREVER("export")
    eq(f:IsShown(), false, "/af export again closes it")
end)
