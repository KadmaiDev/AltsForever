-- Tests: craft. Loaded by tests/run.lua, which provides test, eq, wow, FILES and the
-- other shared helpers; helpers defined here are shared with the other files too.
---------------------------------------------------------------------------
---------------------------------------------------------------------------
SQUIRREL_ITEM, DYNAMITE_ITEM, GOGGLES_ITEM = 4401, 4378, 4368

-- Engineering window where recipes make items: squirrel and goggles via the
-- schematic, dynamite only via its item link, and one with no item at all.
function craftingWindow(learned)
    wow.tradeskill.prof = "Engineering"
    wow.tradeskill.recipes = {
        [1001] = { name = "Mechanical Squirrel", learned = learned.squirrel or false, item = SQUIRREL_ITEM },
        [1002] = { name = "Rough Dynamite", learned = learned.dynamite or false,
            link = "|cffffffff|Hitem:" .. DYNAMITE_ITEM .. "::::::::60:::::|h[Rough Dynamite]|h|r" },
        [1003] = { name = "Shadow Goggles", learned = learned.goggles or false, item = GOGGLES_ITEM },
        [1004] = { name = "Enchant Something", learned = true },
    }
    wow.fire("TRADE_SKILL_SHOW")
end

-- The names under the "Can craft" heading, joined with ", ", or nil if there's none.
function craftLine(lines)
    for i, l in ipairs(lines) do
        if l[1] == "Can craft" and not l[2] then
            local names = {}
            for j = i + 1, #lines do
                local name = lines[j][1] and lines[j][1]:match("^  (.+)$")
                if not name then break end
                names[#names + 1] = name
            end
            return table.concat(names, ", ")
        end
    end
end

test("opening a profession window records which items each learned recipe makes", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    craftingWindow({ squirrel = true, dynamite = true })
    local crafts = ns.char.crafts.Engineering
    eq(crafts[SQUIRREL_ITEM], "mechanical squirrel", "the recipe that makes it")
    eq(crafts[DYNAMITE_ITEM], "rough dynamite", "read from the item link when the schematic has none")
    eq(crafts[GOGGLES_ITEM], nil, "not learned")
    local n = 0
    for _ in pairs(crafts) do n = n + 1 end
    eq(n, 2, "recipes that make no item are skipped")
end)

test("item tooltip lists who can craft it: you first, then by name", function()
    wow.load(FILES)
    wow.login({ v = 2, chars = {
        ["Brakka"] = alt("Brakka", "HUNTER", { crafts = { Engineering = { [SQUIRREL_ITEM] = true } } }),
        ["Far"] = alt("Far", "MAGE", { crafts = { Engineering = { [SQUIRREL_ITEM] = true } } }),
        ["Veyla"] = alt("Veyla", "PALADIN", { crafts = { Tailoring = { [2580] = true } } }),
    } })
    craftingWindow({ squirrel = true })
    local lines = wow.hover(GameTooltip, SQUIRREL_ITEM)
    eq(craftLine(lines), "[MAGE]Aldric, [HUNTER]Brakka, [MAGE]Far", "you first, then by name, one per line")
    eq(craftLine(wow.hover(GameTooltip, 9999)), nil, "nobody makes it: no line")
end)

test("a character is listed once even if two professions make the item", function()
    wow.load(FILES)
    wow.login({ v = 2, chars = {
        ["Brakka"] = alt("Brakka", "HUNTER",
            { crafts = { Engineering = { [100] = true }, Blacksmithing = { [100] = true } } }),
    } })
    eq(craftLine(wow.hover(GameTooltip, 100)), "[HUNTER]Brakka")
end)

test("can-craft line updates when you learn a recipe", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    craftingWindow({})
    wow.fire("TRADE_SKILL_CLOSE")
    eq(craftLine(wow.hover(GameTooltip, GOGGLES_ITEM)), nil)
    wow.tradeskill.recipes[1003].learned = true
    wow.fire("NEW_RECIPE_LEARNED", 1003)
    eq(ns.char.crafts.Engineering[GOGGLES_ITEM], "shadow goggles")
    eq(craftLine(wow.hover(GameTooltip, GOGGLES_ITEM)), "[MAGE]Aldric")
end)

---------------------------------------------------------------------------
test("time played is requested quietly after login and recorded", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.login({ v = 2, chars = {} })
    eq(wow.playedRequests, 0, "not during the login spam")
    runTimers()
    eq(wow.playedRequests, 1)
    wow.timePlayed(5 * DAY)
    eq(#wow.playedShown, 0, "the chat message for our request is hidden")
    eq(ns.char.played, 5 * DAY); eq(ns.char.playedAt, NOW)
    table.remove(wow.timers)() -- the answer's own timer, a second later
    eq(ChatFrame1:IsEventRegistered("TIME_PLAYED_MSG"), true, "listening again once the answer is in")
    runTimers()
    wow.timePlayed(5 * DAY + 60) -- the player types /played
    eq(#wow.playedShown, 1, "the player's own /played still prints")
    eq(ns.char.played, 5 * DAY + 60)
    eq(ChatFrame1:IsEventRegistered("TIME_PLAYED_MSG"), true)
    eq(ChatFrame2:IsEventRegistered("TIME_PLAYED_MSG"), false, "a window that wasn't listening stays that way")
end)

test("chat listens for time played again even if no answer comes", function()
    wow.load(FILES)
    wow.login({ v = 2, chars = {} })
    runTimers() -- the request: chat stops listening
    eq(ChatFrame1:IsEventRegistered("TIME_PLAYED_MSG"), false)
    runTimers() -- 10 seconds later, no answer
    eq(ChatFrame1:IsEventRegistered("TIME_PLAYED_MSG"), true)
end)

test("time played keeps counting while online and is saved at logout", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.login(nil)
    wow.timePlayed(2 * HOUR)
    eq(ns.PlayedNow(ns.char, NOW + HOUR), 3 * HOUR)
    wow.now = NOW + HOUR
    wow.fire("PLAYER_LOGOUT")
    eq(ns.char.played, 3 * HOUR); eq(ns.char.playedAt, NOW + HOUR)
    eq(ns.PlayedNow({ played = 100, playedAt = NOW }, NOW + DAY), 100, "logged-out characters don't count up")
end)

test("secret time played is never stored", function()
    local ns = wow.load(FILES)
    wow.login(nil)
    wow.SECRET = 12345 -- a secret number still looks like a number
    wow.timePlayed(12345)
    eq(ns.char.played, nil)
end)

test("overview shows time played per character and in total", function()
    local ns = wow.load(FILES)
    eq(ns.FormatPlayed(20 * 60), "20m"); eq(ns.FormatPlayed(5 * HOUR + 20 * 60), "5h 20m")
    eq(ns.FormatPlayed(12 * DAY + 5 * HOUR + 59), "12d 5h")
    wow.now = NOW
    local saved = overviewAlts()
    saved.chars["High"].played = 3 * DAY
    wow.login(saved)
    wow.timePlayed(2 * HOUR)
    SlashCmdList.ALTSFOREVER("")
    local rows = overviewRows()
    eq(cell(rows[1], 11), "2h 0m")
    eq(cell(rows[3], 1), "[PRIEST]High"); eq(cell(rows[3], 11), "3d 0h")
    eq(cell(rows[4], 11), G .. "?|r", "not recorded yet")
    eq(AltsForeverFrame.footer.text, "Total played: 3d 2h     Total gold: 10507c")
end)
