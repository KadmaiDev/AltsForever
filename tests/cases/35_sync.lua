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

-- Sends everything queued (each message waits on a timer after the first).
function syncPump()
    for _ = 1, 1000 do
        if #wow.timers == 0 then return end
        runTimers()
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
    eq(syncKinds(sent), "want,char,char,done")
    eq(sent[2].key, "Aldric"); eq(sent[2].c.updated, NOW + 60, "you, as of now")
    eq(sent[3].key, "Tarn Moon"); eq(sent[3].c.bags[118], 2)
    eq(sent[4].n, 2)
    assert(syncPrinted():find("Sent 2 characters to Bob Smith.", 1, true))

    -- Theirs arrive.
    local link = "|cff1eff00|Hitem:2589::::::::|h[Linen Cloth]|h|r"
    syncFrom(ns, "Bob Smith-Realm", { k = "char", key = "Bob Smith",
        c = alt("Bob Smith", "WARRIOR", { updated = NOW, bags = { [2589] = 3 },
            gear = { [1] = link }, saves = { ["Molten Core"] = NOW + DAY }, recipes = { Tailoring = { ["bolt of linen cloth"] = true } } }),
        ri = { Tailoring = { ["bolt of linen cloth"] = "75;Bolt of Linen Cloth;2996,2589:2" } }, fn = { [72] = "Stormwind" } })
    syncFrom(ns, "Bob Smith-Realm", { k = "char", key = "New Alt", rs = "pvp",
        c = alt("New Alt", "MAGE", { realm = "Other", faction = "Horde", updated = NOW - HOUR }) })
    syncFrom(ns, "Bob Smith-Realm", { k = "char", key = "Aldric", c = alt("Aldric", "MAGE", { updated = NOW + DAY, money = 1 }) })
    syncFrom(ns, "Bob Smith-Realm", { k = "char", key = "Tarn Moon", c = alt("Tarn Moon", "DRUID", { updated = NOW - 2 * DAY }) })
    syncFrom(ns, "Bob Smith-Realm", { k = "done", n = 4 })
    assert(syncPrinted():find("Got 2 characters from Bob Smith.", 1, true), syncPrinted())
    local bob = ns.db.chars["Bob Smith"]
    eq(bob.bags[2589], 3); eq(bob.gear[1], link); eq(bob.saves["Molten Core"], NOW + DAY)
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
