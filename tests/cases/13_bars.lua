-- Tests: bars. Loaded by tests/run.lua, which provides test, eq, wow, FILES and the
-- other shared helpers; helpers defined here are shared with the other files too.
---------------------------------------------------------------------------
-- XP bar tooltip
function lineTexts(tt)
    local t = {}
    for _, l in ipairs(tt.lines) do t[#t + 1] = l[1] end
    return table.concat(t, " | ")
end

-- Blizzard's bars: in a status tracking container by kind, reputation first and
-- experience 4th (marked by its rested tick), as checked in game.
function blizzardBars()
    MainStatusTrackingBarContainer = CreateFrame("Frame")
    local bars = {}
    for i = 1, 6 do bars[i] = CreateFrame("Frame") end
    bars[4].ExhaustionTick = CreateFrame("Frame")
    MainStatusTrackingBarContainer.bars = bars
    return bars[4], bars[1]
end
function blizzardXPBar() return (blizzardBars()) end

test("hovering Blizzard's XP bar lists every character still levelling", function()
    wow.load(FILES)
    wow.now = NOW
    local bar = blizzardXPBar()
    wow.login(overviewAlts())
    wow.fire("PLAYER_ENTERING_WORLD")
    bar.scripts.OnEnter(bar)
    eq(GameTooltip:GetOwner(), bar); eq(GameTooltip:IsShown(), true)
    eq(lineTexts(GameTooltip), "Experience | Your characters | [PRIEST]High | [ROGUE]Low",
        "by level; not you (the bar shows you), not max level (Far)")
    local low = GameTooltip.lines[4][2]
    assert(low:find("^12  ") and low:find("10%%") and low:find("rested"), low)
    bar.scripts.OnLeave(bar)
    eq(GameTooltip:IsShown(), false)
    -- Hooked once, however many loading screens.
    wow.fire("PLAYER_ENTERING_WORLD")
    bar.scripts.OnEnter(bar)
    eq(#GameTooltip.lines, 4)
end)

test("the XP bar adds nothing when you're the only character levelling", function()
    wow.load(FILES)
    local bar = blizzardXPBar()
    wow.login({ v = 2, chars = { ["Far"] = alt("Far", "MAGE", { level = 60 }) } })
    wow.fire("PLAYER_ENTERING_WORLD")
    bar.scripts.OnEnter(bar)
    eq(GameTooltip:IsShown(), false)
end)

test("ElvUI's and EllesmereUI's XP bar tooltips get the lines added at the end", function()
    for _, name in ipairs({ "ElvUI_ExperienceBarHolder", "EllesmereEAB_XPBar" }) do
        wow.load(FILES)
        wow.now = NOW
        local bar = CreateFrame("Frame", name)
        local ownTooltip = true
        bar:SetScript("OnEnter", function(self)
            if not ownTooltip then return end -- click-through, or at max level
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:AddLine("Experience")
            GameTooltip:Show()
        end)
        wow.login(overviewAlts())
        wow.fire("PLAYER_ENTERING_WORLD")
        bar.scripts.OnEnter(bar)
        eq(lineTexts(GameTooltip), "Experience |   | Your characters | [PRIEST]High | [ROGUE]Low", name)
        GameTooltip:Hide()
        ownTooltip = false
        bar.scripts.OnEnter(bar)
        eq(GameTooltip:IsShown(), false, name .. ": no tooltip of our own where theirs is off")
    end
end)

function repAlts()
    return { v = 2, factions = { [530] = "Darkspear Trolls" }, chars = {
        ["Aldric"] = alt("Aldric", "MAGE", { level = 24, reps = { [530] = 100 } }),
        ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { level = 30, reps = { [530] = 3500 } }),
        ["Brak Stone"] = alt("Brak Stone", "WARRIOR", { level = 20, reps = { [530] = 42500 } }),
        ["Horde Guy"] = alt("Horde Guy", "ROGUE", { level = 10, reps = { [76] = 100 } }),
    } }
end

test("hovering the reputation bar lists your other characters' standing with that faction", function()
    wow.load(FILES)
    local _, bar = blizzardBars()
    wow.watched = { factionID = 530, name = "Darkspear Trolls" }
    wow.login(repAlts())
    wow.fire("PLAYER_ENTERING_WORLD")
    bar.scripts.OnEnter(bar)
    eq(GameTooltip:GetOwner(), bar)
    eq(lineTexts(GameTooltip), "Darkspear Trolls | Your characters | [DRUID]Tarn Moon | [WARRIOR]Brak Stone",
        "not you, not characters without it")
    local tarn, brak = GameTooltip.lines[3][2], GameTooltip.lines[4][2]
    assert(tarn:find("Friendly") and tarn:find("8%%") and tarn:find("500 / 6000"), tarn)
    assert(brak:find("Exalted") and not brak:find("%%"), brak)
    bar.scripts.OnLeave(bar)
    eq(GameTooltip:IsShown(), false)
end)

test("the reputation bar adds nothing without a watched faction or another character with it", function()
    wow.load(FILES)
    local _, bar = blizzardBars()
    wow.login(repAlts())
    wow.fire("PLAYER_ENTERING_WORLD")
    bar.scripts.OnEnter(bar)
    eq(GameTooltip:IsShown(), false, "nothing watched")
    wow.watched = { factionID = 999, name = "Nobody's" }
    bar.scripts.OnEnter(bar)
    eq(GameTooltip:IsShown(), false, "no one else has it")
end)

test("ElvUI's and EllesmereUI's reputation bar tooltips get the lines added at the end", function()
    for _, name in ipairs({ "ElvUI_ReputationBarHolder", "EllesmereEAB_RepBar" }) do
        wow.load(FILES)
        local bar = CreateFrame("Frame", name)
        bar:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:AddLine("Darkspear Trolls")
            GameTooltip:Show()
        end)
        wow.watched = { factionID = 530, name = "Darkspear Trolls" }
        wow.login(repAlts())
        wow.fire("PLAYER_ENTERING_WORLD")
        bar.scripts.OnEnter(bar)
        eq(lineTexts(GameTooltip), "Darkspear Trolls |   | Your characters | [DRUID]Tarn Moon | [WARRIOR]Brak Stone", name)
    end
end)

test("everything in the menus can also be done with a command", function()
    wow.load(FILES)
    wow.login(mailAlts())
    SlashCmdList.ALTSFOREVER("minimap")
    eq(AltsForeverMinimapButton:IsShown(), false); eq(AltsForeverDB.minimapHidden, true)
    assert(wow.printed[#wow.printed]:find("/af minimap brings it back", 1, true))
    SlashCmdList.ALTSFOREVER("minimap")
    eq(AltsForeverMinimapButton:IsShown(), true); eq(AltsForeverDB.minimapHidden, nil)
    SlashCmdList.ALTSFOREVER("sendmail")
    eq(AltsForeverDB.sendToAltOff, true)
    wow.fire("MAIL_SHOW")
    eq(altsButton(), nil, "no arrow while it's off")
    SlashCmdList.ALTSFOREVER("sendmail")
    eq(AltsForeverDB.sendToAltOff, nil)
    SlashCmdList.ALTSFOREVER("rep")
    eq(AltsForeverRepFrame:IsShown(), true)
    SlashCmdList.ALTSFOREVER("rep")
    eq(AltsForeverRepFrame:IsShown(), false)
    SlashCmdList.ALTSFOREVER("help")
    local help = table.concat(wow.printed, "\n")
    assert(help:find("rep | mail | list | delete Name | skillups | sendmail | minimap | stats | mem", 1, true), help)
end)
