-- Tests: raid and dungeon lockouts (Lockouts.lua). Loaded by tests/run.lua.

test("saves are asked for after login and after a boss dies, and read when the game answers", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.login(overviewAlts())
    eq(ns.char.saves, nil, "not read yet")
    runTimers()
    eq(wow.raidInfoRequests, 1, "asked a few seconds after login")
    wow.saves = {
        { "Molten Core", 3 * DAY, true, false, "40 Player", 10, 3 },
        { "Onyxia's Lair", 5 * HOUR, true, false, "40 Player", 1, 1 },
        { "Zul'Gurub", 0, true, false, "20 Player", 10, 10 }, -- expired: listed only to extend
        { "Blackwing Lair", 2 * DAY, false, true, "40 Player", 8, 0 }, -- extended
    }
    wow.fire("UPDATE_INSTANCE_INFO")
    local c = ns.char
    eq(c.saves["Molten Core"], NOW + 3 * DAY)
    eq(c.saves["Onyxia's Lair"], NOW + 5 * HOUR)
    eq(c.saves["Zul'Gurub"], nil, "an expired save isn't kept")
    eq(c.saves["Blackwing Lair"], NOW + 2 * DAY, "an extended save is")
    eq(c.saveKills["Molten Core"], "3/10")
    eq(c.saveKills["Blackwing Lair"], "0/8")

    wow.fire("ENCOUNTER_END", 663, "Lucifron", 9, 40, 0)
    eq(wow.raidInfoRequests, 1, "a wipe saves nobody")
    wow.fire("ENCOUNTER_END", 663, "Lucifron", 9, 40, 1)
    eq(wow.raidInfoRequests, 2, "a kill: ask again")

    -- Read again: the same tables, refilled.
    local saves = c.saves
    wow.saves = {}
    wow.fire("UPDATE_INSTANCE_INFO")
    eq(c.saves, saves)
    eq(next(c.saves), nil, "saved nowhere now")
    eq(c.saveKills, nil)
end)

test("two saves to one place are told apart by difficulty", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.login(nil)
    wow.saves = { { "Ragefire Chasm", DAY, true, false, "Normal" }, { "Ragefire Chasm", 2 * DAY, true, false, "Heroic" } }
    wow.fire("UPDATE_INSTANCE_INFO")
    eq(ns.char.saves["Ragefire Chasm"], NOW + DAY)
    eq(ns.char.saves["Ragefire Chasm (Heroic)"], NOW + 2 * DAY)
end)

test("a secret answer from the game is left alone", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.login(nil)
    wow.saves = { { wow.SECRET, DAY, true, false, "Normal" }, { "Molten Core", wow.SECRET, true, false, "40 Player" } }
    wow.fire("UPDATE_INSTANCE_INFO")
    eq(next(ns.char.saves), nil)
end)

local function lockoutAlts()
    local saved = overviewAlts()
    saved.chars["High"].saves = { ["Molten Core"] = NOW + 3 * DAY + HOUR, ["Onyxia's Lair"] = NOW + 5 * HOUR,
        ["Zul'Gurub"] = NOW - HOUR }
    saved.chars["High"].saveKills = { ["Molten Core"] = "3/10", ["Zul'Gurub"] = "4/10" }
    saved.chars["Low"].saves = {}
    return saved
end

test("the overview counts each character's saves; the row tooltip lists them, soonest reset first", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.login(lockoutAlts())
    SlashCmdList.ALTSFOREVER("")
    local rows = overviewRows()
    eq(cell(rows[1], 12), G .. "?|r", "you: never read")
    eq(cell(rows[3], 1), "[PRIEST]High"); eq(cell(rows[3], 12), "2")
    eq(cell(rows[4], 1), "[ROGUE]Low"); eq(cell(rows[4], 12), "", "saved nowhere")
    eq(ns.db.chars["High"].saves["Zul'Gurub"], nil, "a save past its reset is forgotten when the overview opens")
    eq(ns.db.chars["High"].saveKills["Zul'Gurub"], nil)
    rows[3].scripts.OnEnter(rows[3])
    local text = textOf(GameTooltip.lines)
    assert(text:find("Lockouts\nOnyxia's Lair = 5h\nMolten Core = 3/10 · 3d 1h", 1, true), text)
end)

-- The Lockouts window's shown rows, one line each: its texts joined by " | ".
function lockoutWindow()
    local out = {}
    for _, row in ipairs(AltsForeverLockoutsFrame.lines) do
        if row.shown then
            local parts = {}
            for _, fs in ipairs({ row.heading, row.a, row.b, row.c, unpack(row.cells) }) do
                if fs.shown and fs.text and fs.text ~= "" then parts[#parts + 1] = fs.text end
            end
            out[#out + 1] = table.concat(parts, " | ")
        end
    end
    return table.concat(out, "\n")
end

test("the Lockouts window lists raids down and characters with saves across", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    local saved = lockoutAlts()
    saved.chars["Far"].saves = { ["Molten Core"] = NOW + 3 * DAY + HOUR }
    wow.login(saved)
    SlashCmdList.ALTSFOREVER("lockouts")
    local f = AltsForeverLockoutsFrame
    eq(f.shown, true)
    eq(lockoutWindow(), table.concat({
        "Instances this hour (10 per game account)",
        G .. "None entered this hour.|r",
        "Raid lockouts",
        "[MAGE]Far | [PRIEST]High",
        "Onyxia's Lair | " .. G .. "-|r | Saved",
        "Molten Core | Saved | 3/10",
    }, "\n"))
    local row = f.lines[6]
    row.scripts.OnEnter(row)
    eq(textOf(GameTooltip.lines), "Molten Core\n[MAGE]Far = 3d 1h\n[PRIEST]High = 3/10 · 3d 1h")
    SlashCmdList.ALTSFOREVER("lockouts")
    eq(f.shown, false, "again closes it")

    -- The overview's key button opens it too.
    SlashCmdList.ALTSFOREVER("")
    AltsForeverFrame.lockoutsButton.scripts.OnClick(AltsForeverFrame.lockoutsButton)
    eq(f.shown, true)
    eq(f.point[2], AltsForeverFrame, "below the overview")

    -- A save read while it's open shows at once.
    wow.saves = { { "Zul'Gurub", 2 * DAY, true, false, "20 Player", 10, 2 } }
    wow.fire("UPDATE_INSTANCE_INFO")
    assert(lockoutWindow():find("Zul'Gurub | 2/10", 1, true), lockoutWindow())

    wow.load(FILES)
    wow.login(nil)
    SlashCmdList.ALTSFOREVER("lockouts")
    assert(lockoutWindow():find("No lockouts on record", 1, true), lockoutWindow())
end)

test("forgetting a character while the Lockouts window is open takes them out of it", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    local saved = lockoutAlts()
    saved.chars["Far"].saves = { ["Molten Core"] = NOW + 3 * DAY + HOUR }
    wow.login(saved)
    SlashCmdList.ALTSFOREVER("lockouts")
    local f = AltsForeverLockoutsFrame
    local row = f.lines[6] -- Molten Core
    SlashCmdList.ALTSFOREVER("delete Far")
    assert(not lockoutWindow():find("Far", 1, true), lockoutWindow())
    row.scripts.OnEnter(row)
    eq(textOf(GameTooltip.lines), "Molten Core\n[PRIEST]High = 3/10 · 3d 1h")
    -- A row still listing them (no refill) doesn't break its tooltip.
    row.keys = { "Far", "High" }
    row.scripts.OnEnter(row)
    eq(textOf(GameTooltip.lines), "Molten Core\n[PRIEST]High = 3/10 · 3d 1h")
end)

test("a Lockouts window too big for the screen repeats the grid in blocks and scrolls", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    local saved = { v = 2, chars = {} }
    for i = 1, 20 do
        local name = ("Alt%02d"):format(i)
        saved.chars[name] = alt(name, "MAGE", { level = 60 - i, saves = { ["Molten Core"] = NOW + DAY, ["Onyxia's Lair"] = NOW + 2 * DAY } })
    end
    for i = 1, 6 do saved.chars["Alt01"].saves["Raid " .. i] = NOW + 3 * DAY + i end
    wow.login(saved)
    UIParent.width, UIParent.height = 1280, 720
    ns.SetWindowScale(1.5) -- 853 x 480 in the window's units
    SlashCmdList.ALTSFOREVER("lockouts")
    local f = AltsForeverLockoutsFrame
    eq(f.width <= 853, true, "fits across: " .. f.width)
    eq(f.width, 8 + 170 + 8 * 80 + 16, "8 characters across")
    eq(f.height <= 480, true, "fits down: " .. f.height)
    local n = 0
    for _, row in ipairs(f.lines) do if row.shown then n = n + 1 end end
    eq(n, 23, "the rows that fit (the gaps between sections take room)")
    assert(f.footer.text:find("1-23 of 30", 1, true), f.footer.text) -- 2 + 1 + 3 blocks (8, 8, 4 characters) of 1 + 8 rows
    eq(f.up.shown, true); eq(f.up:IsEnabled(), false); eq(f.down:IsEnabled(), true)
    -- Every character is there, in blocks of 8.
    f.scripts.OnMouseWheel(f, -1)
    f.down.scripts.OnClick(f.down)
    local all = lockoutWindow()
    assert(f.footer.text:find("7-30 of 30", 1, true), f.footer.text)
    assert(all:find("[MAGE]Alt17 | [MAGE]Alt18 | [MAGE]Alt19 | [MAGE]Alt20", 1, true), all)
    eq(f.down:IsEnabled(), false, "at the end")
    f.up.scripts.OnClick(f.up)
    assert(f.footer.text:find("1-23 of 30", 1, true), f.footer.text)
    assert(lockoutWindow():find("[MAGE]Alt01 | [MAGE]Alt02 | [MAGE]Alt03 | [MAGE]Alt04 | [MAGE]Alt05 | [MAGE]Alt06 | [MAGE]Alt07 | [MAGE]Alt08\n", 1, true), lockoutWindow())
    -- A big screen: all in one, no paging.
    UIParent.width, UIParent.height = 3840, 2160
    ns.SetWindowScale(1)
    SlashCmdList.ALTSFOREVER("lockouts"); SlashCmdList.ALTSFOREVER("lockouts")
    eq(f.width, 8 + 170 + 20 * 80 + 16)
    eq(f.footer.text, ""); eq(f.down.shown, false)
end)

test("Reputation and Lockouts open where they cover neither the overview nor each other", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.login(lockoutAlts())
    UIParent.width, UIParent.height = 1920, 1080
    SlashCmdList.ALTSFOREVER("")
    local ov = AltsForeverFrame
    local function anchor(f) return f.point[1] .. " " .. (f.point[2] == ov and "overview" or f.point[2] == UIParent and "screen"
        or f.point[2] and f.point[2].frameName or tostring(f.point[2])) .. " " .. tostring(f.point[3]) end
    -- Lays a window out where its anchor puts it (the fake has no layout engine).
    local function lay(f)
        local p, rel, relPoint, dx, dy = unpack(f.point)
        local r = rel.rect
        local x = relPoint:find("LEFT") and r[1] or r[2]
        local y = relPoint:find("TOP") and r[3] or r[4]
        x, y = x + (dx or 0), y + (dy or 0)
        local w, h = f.width, f.height
        local left = p:find("LEFT") and x or x - w
        local top = p:find("TOP") and y or y + h
        f.rect = { left, left + w, top, top - h }
    end
    local function open(cmd, name)
        SlashCmdList.ALTSFOREVER(cmd)
        lay(_G[name])
    end
    local lock, rep

    -- Room below: the first goes there, the second beside it.
    ov.rect = { 100, 1100, 1000, 600 }
    open("lockouts", "AltsForeverLockoutsFrame")
    lock = AltsForeverLockoutsFrame
    eq(anchor(lock), "TOPLEFT overview BOTTOMLEFT")
    open("rep", "AltsForeverRepFrame")
    rep = AltsForeverRepFrame
    eq(anchor(rep), "TOPLEFT AltsForeverLockoutsFrame TOPRIGHT", "beside it, not on top of it")
    SlashCmdList.ALTSFOREVER("rep")

    -- No room beside it: below it.
    UIParent.width = 700
    ov.rect = { 10, 690, 1070, 700 }
    SlashCmdList.ALTSFOREVER("lockouts"); open("lockouts", "AltsForeverLockoutsFrame")
    eq(anchor(lock), "TOPLEFT overview BOTTOMLEFT")
    open("rep", "AltsForeverRepFrame")
    eq(anchor(rep), "TOPLEFT AltsForeverLockoutsFrame BOTTOMLEFT")
    SlashCmdList.ALTSFOREVER("rep")
    SlashCmdList.ALTSFOREVER("lockouts")
    UIParent.width = 1920

    -- The overview low on the screen: above it.
    ov.rect = { 100, 1100, 400, 50 }
    open("lockouts", "AltsForeverLockoutsFrame")
    eq(anchor(lock), "BOTTOMLEFT overview TOPLEFT")
    SlashCmdList.ALTSFOREVER("lockouts")
    -- As tall as the screen: to its right; at the right edge: to its left.
    ov.rect = { 100, 1100, 1075, 5 }
    open("lockouts", "AltsForeverLockoutsFrame")
    eq(anchor(lock), "TOPLEFT overview TOPRIGHT")
    SlashCmdList.ALTSFOREVER("lockouts")
    ov.rect = { 800, 1915, 1075, 5 }
    open("lockouts", "AltsForeverLockoutsFrame")
    eq(anchor(lock), "TOPRIGHT overview TOPLEFT")
    SlashCmdList.ALTSFOREVER("lockouts")
    -- Nowhere free: below it, as before.
    ov.rect = { 0, 1920, 1080, 0 }
    open("lockouts", "AltsForeverLockoutsFrame")
    eq(anchor(lock), "TOPLEFT overview BOTTOMLEFT")
    SlashCmdList.ALTSFOREVER("lockouts")

    -- Without the overview: the middle of the screen.
    ov:Hide()
    SlashCmdList.ALTSFOREVER("lockouts")
    eq(anchor(lock), "CENTER nil nil")
end)

test("damaged saves are repaired at load", function()
    local ns = wow.load(FILES)
    local saved = overviewAlts()
    saved.chars["High"].saves = { ["Molten Core"] = "soon", [3] = NOW, ["Onyxia's Lair"] = NOW + DAY }
    saved.chars["High"].saveKills = { ["Molten Core"] = 3 }
    saved.chars["Low"].saves = "broken"
    wow.login(saved)
    local high = ns.db.chars["High"]
    eq(high.saves["Molten Core"], nil); eq(high.saves[3], nil); eq(high.saves["Onyxia's Lair"], NOW + DAY)
    eq(high.saveKills["Molten Core"], nil)
    eq(ns.db.chars["Low"].saves, nil)
end)
