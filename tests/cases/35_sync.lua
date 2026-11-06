-- Tests: swapping characters with another game account by addon whispers (Sync.lua).
-- Loaded by tests/run.lua. The other side is played by hand: its messages are built with
-- the addon's own encoder and fired as CHAT_MSG_ADDON.

-- Every payload sent to `target` (or anyone), decoded, in order.
function syncSent(ns, target)
    local list, buf = {}, {}
    for _, m in ipairs(wow.sent) do
        eq(m[1], "AltsForever"); eq(m[3], "WHISPER")
        if not target or m[4] == target then
            local mark, body = m[2]:sub(1, 1), m[2]:sub(2)
            local who = m[4]
            if mark == "a" then
                list[#list + 1] = assert(ns.SyncDecode(body), body)
            elseif mark == "b" then
                buf[who] = body
            else
                buf[who] = buf[who] .. body
                if mark == "d" then list[#list + 1] = assert(ns.SyncDecode(buf[who])) end
            end
        end
    end
    return list
end

function syncKinds(list)
    local t = {}
    for i, msg in ipairs(list) do t[i] = msg.k end
    return table.concat(t, ",")
end

-- The other side sends a payload, in pieces as the addon would.
function syncFrom(ns, sender, payload)
    local pieces = ns.SyncPieces(ns.SyncEncode(payload))
    for i, piece in ipairs(pieces) do
        local mark = #pieces == 1 and "a" or i == 1 and "b" or i == #pieces and "d" or "c"
        wow.fire("CHAT_MSG_ADDON", "AltsForever", mark .. piece, "WHISPER", sender)
    end
end

-- Sends everything queued (each message waits on a timer after the first). The checks on a
-- running swap and the 10 minute check are left waiting: with the clock stopped they'd run
-- for ever.
function syncPump()
    for _ = 1, 1000 do
        local due, later = {}, {}
        for _, fn in ipairs(wow.timers) do
            local list = wow.delays[fn] >= 100 and later or due
            list[#list + 1] = fn
        end
        if #due == 0 then return end
        wow.timers = later
        for _, fn in ipairs(due) do fn() end
    end
    error("never finished")
end

function syncPrinted() return table.concat(wow.printed, "\n") end

local function deepEq(a, b, path)
    path = path or "value"
    if type(a) ~= "table" or type(b) ~= "table" then return eq(a, b, path) end
    for k, v in pairs(a) do deepEq(v, b[k], path .. "." .. tostring(k)) end
    for k in pairs(b) do assert(a[k] ~= nil, path .. "." .. tostring(k) .. " is extra") end
end

-- You (Aldric) with Tarn Moon on this account, and one character forgotten yesterday.
local function syncStart()
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.login({ v = 2, forgotten = { ["Gone Away"] = NOW - DAY }, chars = {
        ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { updated = NOW - DAY, bags = { [118] = 2 } }) } })
    runTimers()
    wow.printed, wow.sent = {}, {}
    return ns
end

test("sync messages encode and decode every kind of value the saved data holds", function()
    local ns = wow.load(FILES)
    local v = { k = "char", n = -3.25, big = 1792713600, t = true, f = false, empty = "",
        s = "a|b;c~d\n\t\1é中~41$#{}:!?",
        link = "|cff1eff00|Hitem:2589::::::::|h[Linen Cloth]|h|r",
        arr = { 1, 0, 0, 2589020 }, map = { [2589] = 20, [118] = 5, [-2] = 1 },
        mixed = { "x", "y", key = "z", [10] = 4 }, nested = { a = { b = { c = {} } } } }
    local text = ns.SyncEncode(v)
    assert(not text:find("[%c|]"), "no control characters or pipes on the wire: " .. text)
    deepEq(ns.SyncDecode(text), v)
    deepEq(ns.SyncDecode(ns.SyncEncode({ a = print, b = 1, [print] = 2, 3, print, 4 })), { b = 1, 3, [3] = 4 },
        "what can't be sent is left out")
    eq(ns.SyncEncode(0 / 0), nil); eq(ns.SyncEncode(math.huge), nil)
end)

test("malformed or hostile sync messages decode to nothing", function()
    local ns = wow.load(FILES)
    for _, bad in ipairs({ "", "{", "$abc", "#", "#1#2", "{:#1}", "{:#1#2", "x", "{#1:{}#2}",
        "#1e999", "#nan", "{" .. ("{"):rep(20) .. ("}"):rep(21) }) do
        eq(ns.SyncDecode(bad), nil, bad)
    end
    eq(ns.SyncDecode(nil), nil); eq(ns.SyncDecode(5), nil)
end)

test("sync pieces stay within the game's 255 bytes and never cut a character in two", function()
    local ns = wow.load(FILES)
    local s = ("a中é"):rep(200)
    local pieces = ns.SyncPieces(s)
    assert(#pieces >= 5)
    for _, p in ipairs(pieces) do
        assert(#p <= 250, #p)
        local first = p:byte(1)
        assert(first < 0x80 or first >= 0xC0, "starts inside a character")
    end
    eq(table.concat(pieces), s)
end)

test("/af sync: hello, then each side asks for what it lacks or has older, and they swap", function()
    local ns = syncStart()
    SlashCmdList.ALTSFOREVER("sync Bob Smith")
    assert(syncPrinted():find("Asking Bob Smith to swap characters", 1, true))
    local hello = syncSent(ns, "Bob Smith")[1]
    eq(hello.k, "hello"); eq(hello.reply, nil); eq(hello.v, 1)
    eq(hello.have["Aldric"], NOW, "the character you're on is as of now")
    eq(hello.have["Tarn Moon"], NOW - DAY)

    -- Their answer (the game names them with a realm): what they have.
    syncFrom(ns, "Bob Smith-Realm", { k = "hello", v = 1, reply = true, have = {
        ["Bob Smith"] = NOW, ["New Alt"] = NOW - HOUR, ["Tarn Moon"] = NOW - 2 * DAY,
        ["Aldric"] = NOW + DAY, ["Gone Away"] = NOW - 2 * DAY } })
    syncPump()
    local sent = syncSent(ns, "Bob Smith-Realm")
    eq(syncKinds(sent), "want")
    eq(table.concat(sent[1].keys, ","), "Bob Smith,New Alt",
        "not an older Tarn Moon, never you, nor one forgotten here and not played since")
    eq(ns.db.syncWith["Bob Smith"], true, "remembered once they answered")

    -- They ask for ours.
    wow.now = NOW + 60
    syncFrom(ns, "Bob Smith-Realm", { k = "want", keys = { "Aldric", "Tarn Moon", "Nobody" } })
    syncPump()
    sent = syncSent(ns, "Bob Smith-Realm")
    eq(syncKinds(sent), "want,plan,char,char,done")
    eq(sent[3].key, "Aldric"); eq(sent[3].c.updated, NOW + 60, "you, as of now")
    eq(sent[4].key, "Tarn Moon"); eq(sent[4].c.bags[118], 2)
    eq(sent[5].n, 2)
    assert(syncPrinted():find("Sent 2 characters to Bob Smith.", 1, true))

    -- Theirs arrive.
    local link = "|cff1eff00|Hitem:2589::::::::|h[Linen Cloth]|h|r"
    syncFrom(ns, "Bob Smith-Realm", { k = "char", key = "Bob Smith",
        c = alt("Bob Smith", "WARRIOR", { updated = NOW, bags = { [2589] = 3 },
            gear = { [1] = link }, recipes = { Tailoring = { ["bolt of linen cloth"] = true } } }),
        ri = { Tailoring = { ["bolt of linen cloth"] = "75;Bolt of Linen Cloth;2996,2589:2" } }, fn = { [72] = "Stormwind" } })
    syncFrom(ns, "Bob Smith-Realm", { k = "char", key = "New Alt", rs = "pvp",
        c = alt("New Alt", "MAGE", { realm = "Other", faction = "Horde", updated = NOW - HOUR }) })
    syncFrom(ns, "Bob Smith-Realm", { k = "char", key = "Aldric", c = alt("Aldric", "MAGE", { updated = NOW + DAY, money = 1 }) })
    syncFrom(ns, "Bob Smith-Realm", { k = "char", key = "Tarn Moon", c = alt("Tarn Moon", "DRUID", { updated = NOW - 2 * DAY }) })
    syncFrom(ns, "Bob Smith-Realm", { k = "done", n = 4 })
    assert(syncPrinted():find("Got 2 characters from Bob Smith.", 1, true), syncPrinted())
    local bob = ns.db.chars["Bob Smith"]
    eq(bob.bags[2589], 3); eq(bob.gear[1], link)
    eq(ns.db.chars["New Alt"].class, "MAGE")
    eq(ns.char.money, wow.money, "the character you're on is never overwritten")
    eq(ns.db.chars["Tarn Moon"].bags[118], 2, "an older copy is ignored")
    eq(ns.db.recipeInfo.Tailoring["bolt of linen cloth"], "75;Bolt of Linen Cloth;2996,2589:2")
    eq(ns.db.factions[72], "Stormwind")
    eq(ns.db.rulesets["Other"], "pvp")

    -- Item tooltips count them now.
    local text = textOf(wow.hover(GameTooltip, 2589))
    assert(text:find("Bob Smith", 1, true), text)
end)

test("a stranger's hello asks the player first; accepting swaps, declining says no", function()
    local ns = syncStart()
    syncFrom(ns, "Cara Lin", { k = "hello", v = 1, have = { ["Cara Lin"] = NOW, ["Tarn Moon"] = NOW } })
    eq(wow.popup.which, "ALTSFOREVER_SYNC"); eq(wow.popup.text, "Cara Lin")
    eq(syncKinds(syncSent(ns, "Cara Lin")), "asking")
    -- Someone else meanwhile: busy.
    syncFrom(ns, "Dee Vo", { k = "hello", v = 1, have = {} })
    syncPump()
    eq(syncKinds(syncSent(ns, "Dee Vo")), "busy")
    -- Nothing is taken from them before the player agrees.
    syncFrom(ns, "Cara Lin", { k = "char", key = "Cara Lin", c = alt("Cara Lin", "PRIEST", { updated = NOW }) })
    eq(ns.db.chars["Cara Lin"], nil)

    StaticPopupDialogs.ALTSFOREVER_SYNC.OnAccept(nil, wow.popup.data)
    eq(AltsForeverSyncFrame:IsShown(), true, "the player agreed, so the window shows how it goes")
    AltsForeverSyncFrame:Hide()
    syncPump()
    local sent = syncSent(ns, "Cara Lin")
    eq(syncKinds(sent), "asking,hello,want")
    eq(sent[2].reply, true); eq(sent[2].have["Tarn Moon"], NOW - DAY)
    eq(table.concat(sent[3].keys, ","), "Cara Lin,Tarn Moon")
    eq(ns.db.syncWith["Cara Lin"], true)
    syncFrom(ns, "Cara Lin", { k = "char", key = "Cara Lin", c = alt("Cara Lin", "PRIEST", { updated = NOW }) })
    eq(ns.db.chars["Cara Lin"].class, "PRIEST")

    -- Declined: no, and no second pop-up this session.
    ns = syncStart()
    syncFrom(ns, "Cara Lin", { k = "hello", v = 1, have = {} })
    StaticPopupDialogs.ALTSFOREVER_SYNC.OnCancel(nil, wow.popup.data)
    StaticPopupDialogs.ALTSFOREVER_SYNC.OnHide()
    wow.popup = nil
    syncFrom(ns, "Cara Lin", { k = "hello", v = 1, have = {} })
    eq(wow.popup, nil)
    syncPump()
    eq(syncKinds(syncSent(ns, "Cara Lin")), "asking,no,no")
    eq(ns.db.syncWith, nil)
end)

test("a character already known from an earlier sync is answered without asking", function()
    local ns = syncStart()
    syncFrom(ns, "Tarn Moon", { k = "hello", v = 1, have = { ["Tarn Moon"] = NOW } })
    eq(wow.popup, nil)
    syncPump()
    eq(syncKinds(syncSent(ns, "Tarn Moon")), "hello,want")
    -- In combat, they're told to wait instead.
    ns = syncStart()
    wow.inCombat = true
    syncFrom(ns, "Tarn Moon", { k = "hello", v = 1, have = {} })
    eq(syncKinds(syncSent(ns, "Tarn Moon")), "busy")
    wow.inCombat = nil
end)

test("a first name alone is matched only to the character you asked, never to one of yours", function()
    local ns = syncStart()
    SlashCmdList.ALTSFOREVER("sync Bob Smith")
    syncFrom(ns, "Bob", { k = "hello", v = 1, reply = true, have = { ["Bob Smith"] = NOW } })
    syncPump()
    eq(syncKinds(syncSent(ns, "Bob")), "want")
    eq(syncSent(ns, "Bob")[1].keys[1], "Bob Smith")
    -- "Tarn" isn't your Tarn Moon: a stranger, so the player is asked.
    syncFrom(ns, "Tarn", { k = "hello", v = 1, have = {} })
    eq(wow.popup.text, "Tarn")
end)

test("asking with no answer gives up; while their player reads the pop-up it waits", function()
    local ns = syncStart()
    SlashCmdList.ALTSFOREVER("sync Bob Smith")
    syncPump()
    assert(syncPrinted():find("No answer from Bob Smith", 1, true))

    ns = syncStart()
    SlashCmdList.ALTSFOREVER("sync Bob Smith")
    syncFrom(ns, "Bob Smith", { k = "asking" })
    assert(syncPrinted():find("Waiting for Bob Smith to accept", 1, true))
    runTimers()
    eq(syncPrinted():find("No answer", 1, true), nil, "still waiting")
    syncPump()
    assert(syncPrinted():find("No answer from Bob Smith", 1, true))

    ns = syncStart()
    SlashCmdList.ALTSFOREVER("sync Bob Smith")
    syncFrom(ns, "Bob Smith", { k = "no" })
    assert(syncPrinted():find("Bob Smith declined.", 1, true))
end)

test("sync slows down when the game says so, waits out chat lockdown, and stops if they're offline", function()
    local ns = syncStart()
    wow.sendResults = { 3 } -- AddonMessageThrottle
    SlashCmdList.ALTSFOREVER("sync Bob Smith")
    eq(#wow.sent, 1)
    runTimers()
    eq(#wow.sent, 2, "sent again after a wait")
    eq(wow.sent[1][2], wow.sent[2][2])

    ns = syncStart()
    wow.sendResults = { 11 } -- AddOnMessageLockdown
    SlashCmdList.ALTSFOREVER("sync Bob Smith")
    eq(#wow.sent, 1)
    runTimers()
    eq(#wow.sent, 2, "sent again once the lockdown passed")
    eq(wow.sent[1][2], wow.sent[2][2])

    ns = syncStart()
    wow.chatLockdown = true
    SlashCmdList.ALTSFOREVER("sync Bob Smith")
    eq(#wow.sent, 0)
    wow.chatLockdown = nil
    runTimers()
    eq(#wow.sent, 1)

    ns = syncStart()
    wow.sendResults = { 12 } -- TargetOffline
    SlashCmdList.ALTSFOREVER("sync Bob Smith")
    assert(syncPrinted():find("Sync with Bob Smith stopped: they're not online.", 1, true), syncPrinted())
    syncPump()
    eq(syncPrinted():find("No answer", 1, true), nil, "already over")
end)

test("a forgotten character comes back from a sync only if played since", function()
    local ns = syncStart()
    ns.ForgetCharacter("Tarn Moon")
    eq(ns.db.forgotten["Tarn Moon"], NOW)
    syncFrom(ns, "Tarn Moon", { k = "hello", v = 1, have = {} }) -- no longer trusted: forgotten
    eq(wow.popup.text, "Tarn Moon")
    StaticPopupDialogs.ALTSFOREVER_SYNC.OnAccept(nil, wow.popup.data)
    syncFrom(ns, "Tarn Moon", { k = "char", key = "Tarn Moon", c = alt("Tarn Moon", "DRUID", { updated = NOW - HOUR }) })
    eq(ns.db.chars["Tarn Moon"], nil, "not played since it was forgotten")
    syncFrom(ns, "Tarn Moon", { k = "char", key = "Gone Away", c = alt("Gone Away", "DRUID", { updated = NOW }) })
    eq(ns.db.chars["Gone Away"].class, "DRUID", "played since")
    eq(ns.db.forgotten["Gone Away"], nil)
end)

test("other addons' messages, other channels and broken pieces are ignored", function()
    local ns = syncStart()
    wow.fire("CHAT_MSG_ADDON", "DBMv4-Ver", "ahello", "WHISPER", "Cara Lin")
    wow.fire("CHAT_MSG_ADDON", "AltsForever", "a" .. ns.SyncEncode({ k = "hello", have = {} }), "GUILD", "Cara Lin")
    wow.fire("CHAT_MSG_ADDON", "AltsForever", "dnonsense", "WHISPER", "Cara Lin")
    wow.fire("CHAT_MSG_ADDON", "AltsForever", "a{{{", "WHISPER", "Cara Lin")
    eq(wow.popup, nil)
    eq(#wow.sent, 0)
    -- A stranger can't make us hold more than a hello's worth.
    wow.fire("CHAT_MSG_ADDON", "AltsForever", "b{:$k;$hello;$pad;$" .. ("x"):rep(249), "WHISPER", "Cara Lin")
    for _ = 1, 20 do wow.fire("CHAT_MSG_ADDON", "AltsForever", "c" .. ("x"):rep(250), "WHISPER", "Cara Lin") end
    wow.fire("CHAT_MSG_ADDON", "AltsForever", "d;$have;{}}", "WHISPER", "Cara Lin")
    eq(wow.popup, nil, "dropped once it grew past a hello's size")
    -- The same hello, small, is read.
    wow.fire("CHAT_MSG_ADDON", "AltsForever", "b{:$k;$hello;$pad;$" .. ("x"):rep(249), "WHISPER", "Cara Lin")
    wow.fire("CHAT_MSG_ADDON", "AltsForever", "d;$have;{}}", "WHISPER", "Cara Lin")
    eq(wow.popup.text, "Cara Lin")
end)

-- Sync's progress as a table, for reading in tests.
local function progress(ns)
    local fill, text, status, going = ns.SyncProgress()
    return { fill = fill, text = text, status = status, going = going }
end

-- How many messages a payload takes.
local function piecesOf(ns, payload) return #ns.SyncPieces(ns.SyncEncode(payload)) end

test("sync progress counts what's sent and received, and fills when both sides are done", function()
    local ns = syncStart()
    eq(ns.SyncProgress(), nil, "no sync yet")
    SlashCmdList.ALTSFOREVER("sync Bob Smith")
    local p = progress(ns)
    eq(p.fill, 0); eq(p.text, ""); eq(p.going, true)
    assert(p.status:find("Asking Bob Smith", 1, true), p.status)
    syncFrom(ns, "Bob Smith", { k = "asking" })
    assert(progress(ns).status:find("Waiting for Bob Smith", 1, true))

    syncFrom(ns, "Bob Smith", { k = "hello", v = 1, reply = true, have = { ["Bob Smith"] = NOW } })
    assert(progress(ns).status:find("Swapping characters with Bob Smith", 1, true))

    -- They want both of ours: told how many messages to expect, and counted out as they go.
    syncFrom(ns, "Bob Smith", { k = "want", keys = { "Aldric", "Tarn Moon" } })
    local plan
    for _, msg in ipairs(syncSent(ns, "Bob Smith")) do if msg.k == "plan" then plan = msg end end
    while not plan do
        runTimers()
        for _, msg in ipairs(syncSent(ns, "Bob Smith")) do if msg.k == "plan" then plan = msg end end
    end
    assert(plan.n >= 3, "two characters and the closing message")
    p = progress(ns)
    eq(p.text, ("Sending 0 of %d"):format(plan.n))
    runTimers()
    eq(progress(ns).text, ("Sending 1 of %d"):format(plan.n))
    assert(progress(ns).fill > 0)
    syncPump()
    p = progress(ns)
    eq(p.text, ("Sending %d of %d"):format(plan.n, plan.n)); eq(p.going, true, "theirs still to come")
    eq(p.fill, 1, "all that's known of is done")

    -- Theirs: the bar takes them in, and goes back to part way until they arrive.
    local char = { k = "char", key = "Bob Smith", c = alt("Bob Smith", "WARRIOR", { updated = NOW }) }
    local n = piecesOf(ns, char) + 1
    syncFrom(ns, "Bob Smith", { k = "plan", n = n })
    p = progress(ns)
    eq(p.text, ("Sending %d of %d · Receiving 0 of %d"):format(plan.n, plan.n, n))
    eq(p.fill, plan.n / (plan.n + n))
    syncFrom(ns, "Bob Smith", char)
    eq(progress(ns).text, ("Sending %d of %d · Receiving %d of %d"):format(plan.n, plan.n, n - 1, n))
    syncFrom(ns, "Bob Smith", { k = "done", n = 1 })
    p = progress(ns)
    eq(p.fill, 1); eq(p.going, false)
    eq(p.status, "Got 1 characters from Bob Smith. Sent 2 characters to Bob Smith.")
end)

test("a plan from someone with no sync going is ignored, and a bad one changes nothing", function()
    local ns = syncStart()
    syncFrom(ns, "Cara Lin", { k = "plan", n = 5 })
    eq(ns.SyncProgress(), nil)
    SlashCmdList.ALTSFOREVER("sync Bob Smith")
    syncFrom(ns, "Bob Smith", { k = "hello", v = 1, reply = true, have = {} })
    syncFrom(ns, "Bob Smith", { k = "plan", n = "lots" })
    syncFrom(ns, "Bob Smith", { k = "plan", n = 0 })
    eq(progress(ns).text, "")
end)

test("the sync window shows why a sync ended, and a stalled one ends", function()
    local ns = syncStart()
    SlashCmdList.ALTSFOREVER("sync Bob Smith")
    syncFrom(ns, "Bob Smith", { k = "no" })
    local p = progress(ns)
    eq(p.status, "Bob Smith declined."); eq(p.going, false)
    eq(p.fill, 0, "a sync that failed doesn't read as finished")

    ns = syncStart()
    wow.sendResults = { 12 } -- TargetOffline
    SlashCmdList.ALTSFOREVER("sync Bob Smith")
    eq(progress(ns).status, "Sync with Bob Smith stopped: they're not online.")

    -- They vanish part way, with the window open: its check notices, without any message.
    ns = syncStart()
    ns.ToggleSync(true)
    SlashCmdList.ALTSFOREVER("sync Bob Smith")
    syncFrom(ns, "Bob Smith", { k = "hello", v = 1, reply = true, have = {} })
    syncFrom(ns, "Bob Smith", { k = "plan", n = 40 })
    runTimers()
    eq(AltsForeverSyncFrame.start:IsEnabled(), false, "one at a time")
    wow.now = NOW + 121
    runTimers()
    eq(AltsForeverSyncFrame.status:GetText(), "Sync with Bob Smith stopped: nothing heard for two minutes.")
    eq(AltsForeverSyncFrame.start:IsEnabled(), true, "free to try again")
    runTimers()
    eq(#wow.timers, 0, "and the window stops checking")
end)

test("sending keeps a sync alive when the other side has nothing to send", function()
    local ns = syncStart()
    SlashCmdList.ALTSFOREVER("sync Bob Smith")
    syncFrom(ns, "Bob Smith", { k = "hello", v = 1, reply = true, have = {} })
    syncFrom(ns, "Bob Smith", { k = "want", keys = { "Aldric" } })
    for _ = 1, 3 do
        wow.now = wow.now + 100
        runTimers()
        eq(progress(ns).going, true, "not taken for a stall")
    end
end)

test("the overview's sync button opens the window, which remembers who you synced with", function()
    local ns = syncStart()
    ns.db.syncWith = { ["Old Friend"] = true, ["Tarn Moon"] = true, ["Bob Smith"] = true }
    ns.db.chars["Bob Smith"] = alt("Bob Smith", "WARRIOR", { updated = NOW - HOUR })
    eq(table.concat(ns.SyncPartners(), ","), "Bob Smith,Tarn Moon,Old Friend", "most recently played first")

    ns.ToggleOverview()
    local button = AltsForeverFrame.syncButton
    button.scripts.OnClick(button)
    local f = AltsForeverSyncFrame
    eq(f:IsShown(), true)
    eq(f.box:GetText(), "Bob Smith", "ready to go again")
    eq(f.pick:IsShown(), true)

    f.pick.scripts.OnClick(f.pick)
    eq(wow.menu.items[2].text, "Tarn Moon")
    wow.menu.items[2].fn()
    eq(f.box:GetText(), "Tarn Moon")

    f.start.scripts.OnClick(f.start)
    eq(syncSent(ns, "Tarn Moon")[1].k, "hello")
    eq(f.start:IsEnabled(), false)
    assert(f.status:GetText():find("Asking Tarn Moon", 1, true), f.status:GetText())
    f:Hide()

    button.scripts.OnClick(button)
    eq(f:IsShown(), true)
    button.scripts.OnClick(button)
    eq(f:IsShown(), false, "the button closes it again")
end)

test("the sync window needs a name, and /af sync alone opens it", function()
    local ns = syncStart()
    SlashCmdList.ALTSFOREVER("sync")
    local f = AltsForeverSyncFrame
    eq(f:IsShown(), true)
    eq(f.box:GetText(), "")
    eq(f.pick:IsShown(), false, "nobody to list yet")
    f.box:SetText("   ")
    f.start.scripts.OnClick(f.start)
    eq(#wow.sent, 0)
    f.box:SetText("Bob Smith")
    f.box.scripts.OnEnterPressed(f.box)
    eq(syncSent(ns, "Bob Smith")[1].k, "hello", "Enter works too")
end)

-- You (Aldric), having synced with Bob Smith and New Alt before; both on your ruleset and faction.
local function autoStart(saved)
    local ns = wow.load(FILES)
    wow.now = NOW
    local db = { v = 2, syncWith = { ["Bob Smith"] = true, ["New Alt"] = true }, chars = {
        ["Bob Smith"] = alt("Bob Smith", "WARRIOR", { updated = NOW - HOUR }),
        ["New Alt"] = alt("New Alt", "MAGE", { updated = NOW - DAY }),
        ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { updated = NOW - DAY }) } }
    for k, v in pairs(saved or {}) do db[k] = v end
    wow.login(db)
    wow.printed, wow.sent = {}, {}
    return ns
end

-- The other side's whole answer to our quiet hello, with nothing of theirs to send.
local function autoAnswer(ns, name)
    syncFrom(ns, name, { k = "hello", v = 1, reply = true, auto = true, have = { [name] = NOW } })
    syncFrom(ns, name, { k = "want", keys = {} })
    syncFrom(ns, name, { k = "done", n = 0 })
    syncPump()
end

test("at login the characters from your other accounts are tried, most recently played first", function()
    local ns = autoStart()
    syncPump()
    eq(syncKinds(syncSent(ns, "Bob Smith")), "ping")
    eq(syncKinds(syncSent(ns, "New Alt")), "ping")
    eq(wow.sent[1][4], "Bob Smith")
    eq(#syncSent(ns, "Tarn Moon"), 0, "one of this account's own")
    eq(syncPrinted():find("Bob Smith", 1, true), nil, "nothing said in chat")
end)

test("nothing is sent at login with no one synced before, with it off, or out of reach", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.login({ v = 2, chars = { ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { updated = NOW }) } })
    wow.sent = {}
    syncPump()
    eq(#wow.sent, 0, "a player who never synced sends nothing")

    ns = autoStart({ syncAutoOff = true })
    syncPump()
    eq(#wow.sent, 0)

    ns = autoStart()
    ns.db.chars["Bob Smith"].faction = "Horde"
    ns.db.chars["New Alt"].realm = "ElsewhereRealm"
    ns.char.realm = "HomeRealm"
    syncPump()
    eq(#wow.sent, 0, "whispers don't cross rulesets or factions")
end)

test("at most ten characters are tried, and the one you're on never", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    local with, chars = {}, {}
    for i = 1, 15 do
        local key = "Alt Number" .. i
        with[key] = true
        chars[key] = alt(key, "MAGE", { updated = NOW - i })
    end
    with["Aldric"] = true
    wow.login({ v = 2, syncWith = with, chars = chars })
    eq(ns.db.syncWith["Aldric"], nil, "you logged in here, so it's ours")
    wow.sent = {}
    syncPump()
    eq(#wow.sent, 10)
    eq(wow.sent[1][4], "Alt Number1"); eq(wow.sent[10][4], "Alt Number10")
end)

test("a ping from a character you trust starts a quiet swap, never a pop-up", function()
    local ns = syncStart()
    ns.db.syncWith = { ["Bob Smith"] = true }
    syncFrom(ns, "Bob Smith", { k = "ping" })
    local hello = syncSent(ns, "Bob Smith")[1]
    eq(hello.k, "hello"); eq(hello.auto, true)
    eq(ns.SyncProgress(), nil, "not in the window until they answer")
    autoAnswer(ns, "Bob Smith")
    eq(wow.printed[1]:match(": (.*)$"), "Synced with Bob Smith.")
    eq(#wow.printed, 1, "one line, nothing else")
    assert(progress(ns).status:find("Got 0 characters", 1, true))
    eq(wow.popup, nil)

    -- And once a session: later swaps say nothing.
    wow.printed = {}
    syncFrom(ns, "Bob Smith", { k = "ping" })
    autoAnswer(ns, "Bob Smith")
    eq(syncPrinted(), "")
end)

test("an automatic hello is answered quietly if trusted, refused without asking if not", function()
    local ns = syncStart()
    ns.db.syncWith = { ["Bob Smith"] = true }
    syncFrom(ns, "Bob Smith", { k = "hello", v = 1, auto = true, have = { ["Bob Smith"] = NOW } })
    syncPump()
    eq(syncKinds(syncSent(ns, "Bob Smith")), "hello,want")
    eq(syncSent(ns, "Bob Smith")[1].auto, true)
    eq(syncPrinted(), "", "nobody asked, so nothing said")

    ns = syncStart()
    syncFrom(ns, "Cara Lin", { k = "hello", v = 1, auto = true, have = {} })
    syncPump()
    eq(wow.popup, nil, "a stranger can't raise the pop-up this way")
    eq(syncKinds(syncSent(ns, "Cara Lin")), "no")
    eq(ns.db.syncWith, nil)

    ns = autoStart({ syncAutoOff = true })
    syncFrom(ns, "Bob Smith", { k = "hello", v = 1, auto = true, have = {} })
    syncPump()
    eq(syncKinds(syncSent(ns, "Bob Smith")), "no", "turned off here")
end)

test("a ping is ignored from strangers, with it off, and during a swap", function()
    local ns = syncStart()
    syncFrom(ns, "Cara Lin", { k = "ping" })
    eq(#wow.sent, 0); eq(wow.popup, nil)

    ns = autoStart({ syncAutoOff = true })
    syncFrom(ns, "Bob Smith", { k = "ping" })
    eq(#wow.sent, 0)

    ns = syncStart()
    ns.db.syncWith = { ["Bob Smith"] = true }
    SlashCmdList.ALTSFOREVER("sync Bob Smith")
    wow.sent = {}
    syncFrom(ns, "Bob Smith", { k = "ping" })
    eq(#wow.sent, 0, "already swapping")
end)

test("a ping in combat swaps as soon as the fight ends", function()
    local ns = syncStart()
    ns.db.syncWith = { ["Bob Smith"] = true }
    wow.inCombat = true
    syncFrom(ns, "Bob Smith", { k = "ping" })
    eq(#wow.sent, 0)
    wow.inCombat = nil
    wow.fire("PLAYER_REGEN_ENABLED")
    eq(syncSent(ns, "Bob Smith")[1].auto, true)

    -- Once: the next fight ending has nothing to do.
    autoAnswer(ns, "Bob Smith")
    wow.sent = {}
    wow.fire("PLAYER_REGEN_ENABLED")
    eq(#wow.sent, 0)
end)

test("a fight ending does nothing with no swap due, or with it turned off since", function()
    local ns = syncStart()
    ns.db.syncWith = { ["Bob Smith"] = true }
    wow.fire("PLAYER_REGEN_ENABLED")
    eq(#wow.sent, 0)

    wow.inCombat = true
    syncFrom(ns, "Bob Smith", { k = "ping" })
    wow.inCombat = nil
    ns.SetSyncAuto(false)
    wow.fire("PLAYER_REGEN_ENABLED")
    eq(#wow.sent, 0)
end)

test("the 10 minute swap falling in combat runs when the fight ends, and the checks go on", function()
    local ns = syncStart()
    ns.db.syncWith = { ["Bob Smith"] = true }
    syncFrom(ns, "Bob Smith", { k = "ping" })
    autoAnswer(ns, "Bob Smith")
    wow.sent = {}
    wow.inCombat = true
    wow.now = NOW + 600
    runTimers()
    eq(#wow.sent, 0, "not in a fight")
    wow.inCombat = nil
    wow.fire("PLAYER_REGEN_ENABLED")
    eq(syncSent(ns, "Bob Smith")[1].auto, true)
    autoAnswer(ns, "Bob Smith")
    wow.sent = {}
    wow.now = NOW + 1200
    runTimers()
    eq(syncSent(ns, "Bob Smith")[1].auto, true, "still every 10 minutes")
end)

test("a swap for another reason moves the next one back, with no whole extra wait", function()
    -- As seen in game: a check that came 7 minutes after a login's swap skipped, and the next
    -- swap took 20 minutes.
    local ns = syncStart()
    ns.db.syncWith = { ["Bob Smith"] = true }
    syncFrom(ns, "Bob Smith", { k = "ping" })
    autoAnswer(ns, "Bob Smith") -- the check is set for 10 minutes from now
    wow.now = NOW + 180
    syncFrom(ns, "Bob Smith", { k = "ping" }) -- they logged in again
    autoAnswer(ns, "Bob Smith")

    wow.sent = {}
    wow.now = NOW + 600
    runTimers()
    eq(#wow.sent, 0, "seven minutes since that swap")
    eq(#wow.timers, 1)
    eq(wow.delays[wow.timers[1]], 180, "the three minutes left, not another ten")
    wow.now = NOW + 780
    runTimers()
    eq(syncSent(ns, "Bob Smith")[1].auto, true)
end)

test("while both stay online they swap every 10 minutes; once they go it stops", function()
    local ns = syncStart()
    ns.db.syncWith = { ["Bob Smith"] = true }
    syncFrom(ns, "Bob Smith", { k = "ping" })
    autoAnswer(ns, "Bob Smith")

    -- Their check came first: ours finds it was just done.
    wow.sent = {}
    wow.now = NOW + 300
    syncFrom(ns, "Bob Smith", { k = "hello", v = 1, auto = true, have = {} })
    syncFrom(ns, "Bob Smith", { k = "want", keys = {} })
    syncFrom(ns, "Bob Smith", { k = "done", n = 0 })
    syncPump()
    wow.sent = {}
    wow.now = NOW + 310
    runTimers()
    eq(#wow.sent, 0, "swapped ten seconds ago")

    wow.now = NOW + 1000
    runTimers()
    eq(syncSent(ns, "Bob Smith")[1].auto, true, "time for another")
    assert(wow.delays[wow.timers[1]] ~= nil)

    -- No answer: they've logged out. Nothing in chat, and the checks stop.
    wow.printed = {}
    syncPump()
    eq(syncPrinted(), "")
    runTimers() -- the 10 minute check, finding no one
    wow.sent = {}
    wow.now = NOW + 2000
    syncPump()
    eq(#wow.timers, 0, "no timers left running")
    eq(#wow.sent, 0)
end)

test("a sync you started by hand keeps going by itself afterwards", function()
    local ns = syncStart()
    SlashCmdList.ALTSFOREVER("sync Bob Smith")
    autoAnswer(ns, "Bob Smith")
    wow.sent = {}
    wow.now = NOW + 600
    runTimers()
    eq(syncSent(ns, "Bob Smith")[1].auto, true)
end)

test("characters a sync brings in are remembered, so any of them can be found next time", function()
    local ns = syncStart()
    SlashCmdList.ALTSFOREVER("sync Bob Smith")
    syncFrom(ns, "Bob Smith", { k = "hello", v = 1, reply = true, have = {} })
    syncFrom(ns, "Bob Smith", { k = "char", key = "New Alt", c = alt("New Alt", "MAGE", { updated = NOW }) })
    eq(ns.db.syncWith["New Alt"], true)
    eq(ns.db.syncWith["Tarn Moon"], nil, "not this account's own")
    ns.ForgetCharacter("New Alt")
    eq(ns.db.syncWith["New Alt"], nil)
end)

test("the \"no such player\" line is hidden only for the character just tried, and only briefly", function()
    local ns = autoStart()
    local line = "No player named '%s' is currently playing."
    runTimers() -- the wait after login: the pings go out
    eq(wow.chatFilter("CHAT_MSG_SYSTEM", line:format("Bob Smith")), true)
    eq(wow.chatFilter("CHAT_MSG_SYSTEM", line:format("Bob")), true, "if the game prints the first name")
    eq(wow.chatFilter("CHAT_MSG_SYSTEM", line:format("Bob Smith-Realm")), true)
    eq(wow.chatFilter("CHAT_MSG_SYSTEM", line:format("Someone Else")), false, "your own typo still shows")
    eq(wow.chatFilter("CHAT_MSG_SYSTEM", "Bob Smith has come online."), false)
    eq(wow.chatFilter("CHAT_MSG_SYSTEM", wow.SECRET), false)
    syncPump()
    eq(wow.chatFilter("CHAT_MSG_SYSTEM", line:format("Bob Smith")), false, "over after a few seconds")
    eq(#(wow.filters.CHAT_MSG_SYSTEM or {}), 0, "the filter is gone")
end)

test("the tick box and /af sync auto turn it off and on; on looks straight away", function()
    local ns = autoStart()
    syncPump()
    wow.sent = {}
    ns.ToggleSync(true)
    local f = AltsForeverSyncFrame
    eq(f.auto:GetChecked(), true, "on by default")
    f.auto:SetChecked(false)
    f.auto.scripts.OnClick(f.auto)
    eq(ns.db.syncAutoOff, true)
    syncFrom(ns, "Bob Smith", { k = "ping" })
    eq(#wow.sent, 0)

    SlashCmdList.ALTSFOREVER("sync auto")
    assert(syncPrinted():find("Automatic sync on.", 1, true))
    eq(ns.db.syncAutoOff, nil, "saves stay small")
    eq(f.auto:GetChecked(), true)
    syncPump()
    eq(syncKinds(syncSent(ns, "Bob Smith")), "ping")

    SlashCmdList.ALTSFOREVER("sync auto")
    assert(syncPrinted():find("Automatic sync off.", 1, true))
    eq(f.auto:GetChecked(), false)
end)

test("a damaged automatic sync setting is dropped at load", function()
    local ns = autoStart({ syncAutoOff = "yes" })
    eq(ns.db.syncAutoOff, nil)
end)

-- A swap with Bob Smith that has started, with everything sent and theirs still to come.
local function midSwap(ns, quiet)
    if quiet then
        ns.db.syncWith = { ["Bob Smith"] = true }
        syncFrom(ns, "Bob Smith", { k = "ping" })
    else
        SlashCmdList.ALTSFOREVER("sync Bob Smith")
    end
    syncFrom(ns, "Bob Smith", { k = "hello", v = 1, reply = true, have = {} })
    syncFrom(ns, "Bob Smith", { k = "plan", n = 40 })
    syncPump()
end

test("a swap that stalls with the window closed ends by itself, and the next check tries again", function()
    local ns = syncStart()
    midSwap(ns, true)
    wow.now = NOW + 121
    wow.sent, wow.printed = {}, {}
    runTimers() -- the check on the swap; the window was never opened
    eq(progress(ns).going, false)
    eq(syncPrinted(), "", "an automatic sync says nothing")

    wow.now = NOW + 700
    runTimers() -- the 10 minute check isn't blocked by the dead swap
    eq(syncSent(ns, "Bob Smith")[1].auto, true)
    autoAnswer(ns, "Bob Smith")
    assert(progress(ns).status:find("Got 0 characters", 1, true), progress(ns).status)
end)

test("a sync you started says so if it stalls with the window closed", function()
    local ns = syncStart()
    midSwap(ns)
    wow.now = NOW + 121
    runTimers()
    assert(syncPrinted():find("Sync with Bob Smith stopped: nothing heard for two minutes.", 1, true), syncPrinted())
    SlashCmdList.ALTSFOREVER("sync Bob Smith")
    assert(not syncPrinted():find("Already swapping", 1, true), "free to try again")
end)

test("a stalled swap doesn't swallow the other side's return, even before any check has run", function()
    local ns = syncStart()
    midSwap(ns, true)
    wow.now = NOW + 121
    wow.sent, wow.timers = {}, {} -- no check has noticed yet
    syncFrom(ns, "Bob Smith", { k = "hello", v = 1, auto = true, have = { ["Bob Smith"] = NOW + 121 } })
    syncPump()
    eq(syncKinds(syncSent(ns, "Bob Smith")), "hello,want", "answered as a new swap")
    eq(syncSent(ns, "Bob Smith")[2].keys[1], "Bob Smith")
end)

test("a swap held up for over two minutes carries on if the messages start again", function()
    local ns = syncStart()
    midSwap(ns)
    wow.now = NOW + 130 -- their chat lockdown ended before any check here came round
    syncFrom(ns, "Bob Smith", { k = "char", key = "New Alt", c = alt("New Alt", "MAGE", { updated = NOW }) })
    eq(ns.db.chars["New Alt"].class, "MAGE")
    eq(progress(ns).going, true)
end)

test("a reload on the other side part way through starts a new swap", function()
    -- They came back well inside the two minutes: their half of the old swap is gone.
    local ns = syncStart()
    midSwap(ns, true)
    wow.sent = {}
    syncFrom(ns, "Bob Smith", { k = "hello", v = 1, auto = true, have = {} })
    syncPump()
    eq(syncKinds(syncSent(ns, "Bob Smith")), "hello,want")

    ns = syncStart()
    midSwap(ns, true)
    wow.sent = {}
    syncFrom(ns, "Bob Smith", { k = "ping" })
    eq(syncSent(ns, "Bob Smith")[1].k, "hello", "their login ping does the same")
    eq(syncSent(ns, "Bob Smith")[1].reply, nil)
end)

test("the wait for an answer starts when the hello goes, however long it was held up", function()
    local ns = syncStart()
    wow.chatLockdown = true
    SlashCmdList.ALTSFOREVER("sync Bob Smith")
    eq(#wow.sent, 0)
    wow.now = NOW + 30 -- past the 20 s wait, still locked down
    runTimers()
    eq(syncPrinted():find("No answer", 1, true), nil, "nothing has gone out yet")
    eq(#wow.sent, 0)

    wow.chatLockdown = nil
    runTimers()
    eq(syncSent(ns, "Bob Smith")[1].k, "hello")
    syncFrom(ns, "Bob Smith", { k = "hello", v = 1, reply = true, have = { ["Bob Smith"] = NOW + 30 } })
    syncFrom(ns, "Bob Smith", { k = "char", key = "Bob Smith", c = alt("Bob Smith", "WARRIOR", { updated = NOW + 30 }) })
    syncFrom(ns, "Bob Smith", { k = "want", keys = {} })
    syncFrom(ns, "Bob Smith", { k = "done", n = 1 })
    syncPump()
    eq(ns.db.chars["Bob Smith"].class, "WARRIOR", "the swap finished")
    assert(syncPrinted():find("Got 1 characters from Bob Smith.", 1, true), syncPrinted())
end)

test("a sync that ends sends nothing more", function()
    local ns = syncStart()
    SlashCmdList.ALTSFOREVER("sync Bob Smith")
    syncFrom(ns, "Bob Smith", { k = "hello", v = 1, reply = true, have = {} })
    syncFrom(ns, "Bob Smith", { k = "want", keys = { "Aldric", "Tarn Moon" } })
    local before = #wow.sent
    syncFrom(ns, "Bob Smith", { k = "no" })
    syncPump()
    eq(#wow.sent, before, "what was queued for them went with it")
end)

test("a held-up hello given up on never goes out late", function()
    local ns = syncStart()
    wow.chatLockdown = true
    SlashCmdList.ALTSFOREVER("sync Bob Smith")
    wow.now = NOW + 121
    for _ = 1, 3 do runTimers() end
    assert(syncPrinted():find("Sync with Bob Smith stopped", 1, true), syncPrinted())
    wow.chatLockdown = nil
    syncPump()
    eq(#wow.sent, 0)
end)

-- The message that carried this character to the other side.
local function sent(ns, key)
    for _, msg in ipairs(syncSent(ns)) do
        if msg.k == "char" and msg.key == key then return msg end
    end
end

test("mail sent to an offline character leaves the time the rested XP estimate counts from", function()
    local ns = syncStart()
    local tarn = ns.db.chars["Tarn Moon"]
    local updated, seen = tarn.updated, tarn.seen
    wow.outbox = { { 100, 20 } }
    wow.now = NOW + 60
    SendMail("Tarn Moon", "subject", "")
    wow.fire("MAIL_SEND_SUCCESS")
    eq(tarn.updated, updated)
    eq(tarn.seen, seen)
    eq(tarn.changed, NOW + 60)
end)

test("the next sync takes in an offline character's new mail from the other account", function()
    local ns = syncStart()
    local stamp = NOW + 60
    SlashCmdList.ALTSFOREVER("sync Bob Smith")
    syncFrom(ns, "Bob Smith", { k = "hello", v = 1, reply = true, have = { ["Tarn Moon"] = stamp } })
    syncPump()
    local keys = syncSent(ns)[2].keys
    eq(keys[1], "Tarn Moon", "theirs is newer: asked for")

    syncFrom(ns, "Bob Smith", { k = "char", key = "Tarn Moon", c = alt("Tarn Moon", "DRUID",
        { updated = NOW - DAY, changed = stamp, mail = { [100] = 20 } }) })
    eq(ns.db.chars["Tarn Moon"].mail[100], 20)
    eq(ns.db.chars["Tarn Moon"].changed, stamp)
end)

test("what you change on an offline character is offered to the other account", function()
    local ns = syncStart()
    wow.outbox = { { 100, 20 } }
    wow.now = NOW + 60
    SendMail("Tarn Moon", "subject", "")
    wow.fire("MAIL_SEND_SUCCESS")
    SlashCmdList.ALTSFOREVER("sync Bob Smith")
    eq(syncSent(ns, "Bob Smith")[1].have["Tarn Moon"], NOW + 60, "mail")
    syncFrom(ns, "Bob Smith", { k = "hello", v = 1, reply = true, have = {} })
    syncFrom(ns, "Bob Smith", { k = "want", keys = { "Tarn Moon" } })
    syncPump()
    eq(sent(ns, "Tarn Moon").c.mail[100], 20, "and it travels with the character")

    ns = syncStart()
    wow.now = NOW + 90
    assert(ns.SetRole("Tarn Moon", "healer"))
    SlashCmdList.ALTSFOREVER("sync Bob Smith")
    eq(syncSent(ns, "Bob Smith")[1].have["Tarn Moon"], NOW + 90, "a role chosen for them")
end)

test("a damaged offline change time is dropped at load", function()
    local ns = wow.load(FILES)
    wow.now = NOW
    wow.login({ v = 2, chars = { ["Tarn Moon"] = alt("Tarn Moon", "DRUID", { changed = "soon" }) } })
    eq(ns.db.chars["Tarn Moon"].changed, nil)
end)
