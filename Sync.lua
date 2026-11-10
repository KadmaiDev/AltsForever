-- Alts Forever sync: swaps characters with Alts Forever on another game account (a player with
-- three game accounts under one Battle.net account asked, 2026-10-30). Saved data is per game
-- account, so the only way across is addon whispers between two characters online at once,
-- which the game allows only on the same ruleset and faction. Each side sends every character
-- it knows that the other lacks or has older, so one pair carries every ruleset and faction.
--
-- /af sync First Last, or the window, starts it. The other side asks its player first, unless
-- the sender is already one of its characters (from an earlier sync) or one it agreed to before
-- (db.syncWith). Nothing is ever read from a stranger beyond a small hello.
--
-- After that it runs by itself unless turned off (db.syncAutoOff): 15 s after login a small
-- ping goes to the characters most recently seen in db.syncWith, which holds everyone a sync
-- brought in. A trusted character online answers with a quiet hello, then the two swap again
-- every 10 minutes while both stay online. A ping or an automatic hello never asks the player.
--
-- Messages (addon prefix "AltsForever", WHISPER): a payload is a table serialised by Encode
-- (no loadstring: a parser that only builds tables) and sent in pieces of up to 250 bytes,
-- each led by a marker: "a" whole, "b" first, "c" middle, "d" last.
--   ping   { k = "ping" }                           anyone there? (at login; see above)
--   hello  { k = "hello", v = PROTOCOL, reply = true|nil, auto = true|nil, have = { [key] = stamp } }
--   want   { k = "want", keys = { key, ... } }      the other side's characters we lack or have older
--   plan   { k = "plan", n = messages }             how many messages follow, for the progress bar
--   char   { k = "char", key, c = character, ri = recipe info, fn = faction names, rs = ruleset,
--            rc = recipe categories, pa = profession icons }
--   done   { k = "done", n = characters sent }
--   asking                                         their player is being asked
--   no / busy                                      declined / in combat or asking about another
-- A character's stamp is its newest seen/updated time; the one logged in is now.
--
-- Worked in game between two accounts on 2026-11-06 (Brak Ironhorn and Vespera Ashward): the
-- sender came as "First Last", every send was Success, though
-- AreOutgoingAddonChatMessagesRestricted() said true. "First Last-Realm" and a first name that
-- matches one known character are handled too. /af sync debug prints each step.
local _, ns = ...
if ns.disabled then return end -- another copy of Alts Forever is running (Core.lua)
local L = ns.L

local pairs, ipairs, type, tostring, tonumber, pcall, next = pairs, ipairs, type, tostring, tonumber, pcall, next
local format, byte, char, sub, find, concat = string.format, string.byte, string.char, string.sub, string.find, table.concat
local floor, huge = math.floor, math.huge
local time = time
local issecretvalue = issecretvalue or function() return false end

local PREFIX = "AltsForever"
local PROTOCOL = 1
local PIECE = 250           -- payload bytes per message (the game allows 255 with the marker)
local PACE = 0.3            -- seconds between messages: ~850 bytes a second, ChatThrottleLib's rate
local WAIT = 1              -- seconds before trying again when the game says to slow down
local TRIES = 60            -- tries at one message before giving up
local ANSWER_WITHIN = 20    -- seconds to wait for the other side's hello
local ASK_WITHIN = 65       -- once they say their player is being asked (the pop-up waits 60)
local QUIET = 120           -- a session with nothing heard for this long is over
local TICK = 5              -- seconds between checks on a stalled sync, only with the window open
local AUTO_DELAY = 15       -- seconds after login before looking for your other accounts
local AUTO_EVERY = 600      -- seconds between swaps while both stay online
local AUTO_MOST = 10        -- characters tried at login
local HIDE_FOR = 10         -- seconds "no such player" lines stay out of chat after trying someone
local STRANGER_LIMIT = 4096 -- the most buffered from someone not agreed to yet (a hello)
local LIMIT = 1048576       -- the most buffered for one payload from anyone
local MAX_DEPTH = 8
local MAX_ITEMS = 200000    -- values in one payload

local verbose = false
local DEBUG = "|cff9d9d9dsync: " -- /af sync debug: steps for testing, in English
local function Debug(text, ...)
    if verbose then ns.Print(DEBUG .. format(text, ...) .. "|r") end
end

---------------------------------------------------------------------------
-- Encoding. Numbers "#123", strings "$text;" (control characters, ~ ; and | as ~XX),
-- true "!", false "?", tables "{" array values ":" key value ... "}" (":" only with keys).
---------------------------------------------------------------------------
local function Escape(c) return format("~%02X", byte(c)) end

local function EncodeValue(v, out, depth)
    local kind = type(v)
    if kind == "number" then
        if v ~= v or v == huge or v == -huge then return false end
        out[#out + 1] = (v == floor(v) and v > -2 ^ 53 and v < 2 ^ 53) and format("#%d", v) or format("#%.17g", v)
    elseif kind == "string" then
        out[#out + 1] = "$" .. v:gsub("[%c~;|]", Escape) .. ";"
    elseif kind == "boolean" then
        out[#out + 1] = v and "!" or "?"
    elseif kind == "table" then
        if depth >= MAX_DEPTH then return false end
        out[#out + 1] = "{"
        local n = 0
        while v[n + 1] ~= nil and EncodeValue(v[n + 1], out, depth + 1) do n = n + 1 end
        local keyed
        for k, value in pairs(v) do
            local kk = type(k)
            if not (kk == "number" and k >= 1 and k <= n and k == floor(k)) and (kk == "number" or kk == "string") then
                local mark = #out
                if not keyed then out[#out + 1] = ":" end
                if EncodeValue(k, out, depth + 1) and EncodeValue(value, out, depth + 1) then
                    keyed = true
                else
                    for i = #out, mark + 1, -1 do out[i] = nil end
                end
            end
        end
        out[#out + 1] = "}"
    else
        return false
    end
    return true
end

function ns.SyncEncode(v)
    local out = {}
    if not EncodeValue(v, out, 0) then return nil end
    return concat(out)
end

local function Unescape(h) return char(tonumber(h, 16)) end

-- Builds only tables, numbers, strings and booleans; nil for anything malformed.
function ns.SyncDecode(s)
    if type(s) ~= "string" then return nil end
    local pos, items = 1, 0
    local Value
    local function Table(depth)
        if depth > MAX_DEPTH then return nil end
        local t, n = {}, 0
        while true do
            local c = sub(s, pos, pos)
            if c == "}" then pos = pos + 1 return t end
            if c == ":" then pos = pos + 1 break end
            local ok, v = Value(depth + 1)
            if not ok then return nil end
            n = n + 1
            t[n] = v
        end
        while true do
            if sub(s, pos, pos) == "}" then pos = pos + 1 return t end
            local ok, k = Value(depth + 1)
            if not ok or (type(k) ~= "number" and type(k) ~= "string") then return nil end
            local ok2, v = Value(depth + 1)
            if not ok2 then return nil end
            t[k] = v
        end
    end
    function Value(depth)
        items = items + 1
        if items > MAX_ITEMS then return false end
        local c = sub(s, pos, pos)
        if c == "#" then
            local a, b = find(s, "^[%d%.eE+%-]+", pos + 1)
            local v = a and tonumber(sub(s, a, b))
            if not v or v ~= v or v == huge or v == -huge then return false end
            pos = b + 1
            return true, v
        elseif c == "$" then
            local e = find(s, ";", pos + 1, true)
            if not e then return false end
            local v = sub(s, pos + 1, e - 1):gsub("~(%x%x)", Unescape)
            pos = e + 1
            return true, v
        elseif c == "!" or c == "?" then
            pos = pos + 1
            return true, c == "!"
        elseif c == "{" then
            pos = pos + 1
            local t = Table(depth)
            return t ~= nil, t
        end
        return false
    end
    local ok, v = Value(0)
    if not ok or pos ~= #s + 1 then return nil end
    return v
end

-- Pieces of at most PIECE bytes, never cutting a UTF-8 character (each message must be
-- valid text on its own).
function ns.SyncPieces(s)
    local list, i, n = {}, 1, #s
    while i <= n do
        local j = i + PIECE - 1
        if j >= n then
            j = n
        else
            local b = byte(s, j + 1)
            while j > i and b >= 0x80 and b < 0xC0 do
                j = j - 1
                b = byte(s, j + 1)
            end
        end
        list[#list + 1] = sub(s, i, j)
        i = j + 1
    end
    return list
end

---------------------------------------------------------------------------
-- Sending: one queue for everyone, one message at a time, PACE apart.
---------------------------------------------------------------------------
local queue, head, pumping = {}, 1, false
local sessions = {} -- [full name] = { target = name to whisper, ours = we started it, ... }
local current       -- the latest session, kept after it ends so the window can show how it went
local Pump, Refresh -- Refresh: the window's, set when it's made
local Keep          -- remembers who to swap with again
local partner       -- { name, target }: who we last swapped with; nil once they've gone
local lastSwap = 0
local afterCombat = false -- a swap fell due in combat: it runs as soon as the fight ends
local told = {}     -- [name] = said in chat that it's syncing, once a session

local function After(seconds, fn)
    if C_Timer and C_Timer.After then C_Timer.After(seconds, fn) end
end

-- The game's answers (Enum.SendAddonMessageResult; older clients returned a boolean).
local function Result(name, fallback)
    local e = Enum and Enum.SendAddonMessageResult
    local v = e and e[name]
    if v == nil then return fallback end
    return v
end

local function ResultName(result)
    local e = Enum and Enum.SendAddonMessageResult
    for name, v in pairs(e or {}) do
        if v == result then return name end
    end
    return tostring(result)
end

local function Lockdown()
    local f = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
    if not f then return false end
    local ok, on = pcall(f)
    return ok and not issecretvalue(on) and on == true
end

local function Notify()
    if Refresh then Refresh() end
end

-- `why` is what went wrong, as told to the player; nil for a swap that finished.
local function Ended(name, why)
    local s = sessions[name]
    if s then
        s.over, s.why = true, why
        if not why then
            lastSwap = time()
            Keep(name, s.target)
            if s.quiet and not told[name] then
                told[name] = true
                ns.Print(L["Synced with %s."]:format(name))
            end
        elseif s.quiet and not s.keep and partner and partner.name == name then
            partner = nil -- they've gone: their next login finds us again
        end
    end
    sessions[name] = nil
    Notify()
end

-- Drops everything still queued for this name.
local function Drop(name)
    local kept = {}
    for i = head, #queue do
        if queue[i].name ~= name then kept[#kept + 1] = queue[i] end
    end
    queue, head = kept, 1
end

-- Tells the player how it ended, in chat and in the window; an automatic sync says nothing.
-- Nothing more goes to them: an answer to it would find no session to land in.
local function Over(name, why)
    local s = sessions[name]
    Drop(name)
    if not (s and s.quiet) then ns.Print(why) end
    Ended(name, why)
end

local function Fresh(s)
    return s and time() - s.at < QUIET
end

-- Gives up on this name, saying why if a swap was running.
local function Stop(name, why)
    if sessions[name] then
        Over(name, L["Sync with %s stopped: %s."]:format(name, why))
    else
        Drop(name)
    end
end

-- Ends a swap that has gone quiet. They may still be there, so the 10 minute check tries again.
local function Stalled(name, s)
    s.keep = true
    Stop(name, L["nothing heard for two minutes"])
end

-- Runs for as long as a swap does, so one that stalls can't block the next, window open or not.
local function Watch(name, s)
    if sessions[name] ~= s then return end
    if not Fresh(s) then return Stalled(name, s) end
    After(QUIET, function() Watch(name, s) end)
end

function Pump()
    local m = queue[head]
    if not m then
        queue, head, pumping = {}, 1, false
        return
    end
    pumping = true
    if Lockdown() then
        Debug("chat lockdown, waiting")
        return After(WAIT, Pump)
    end
    local send = C_ChatInfo and C_ChatInfo.SendAddonMessage
    local ok, result = false, "no SendAddonMessage"
    if send then ok, result = pcall(send, PREFIX, m.text, "WHISPER", m.target) end
    if issecretvalue(result) then result = nil end
    Debug("send %d bytes to %s: %s", #m.text, m.target, ok and ResultName(result) or tostring(result))
    if ok and (result == nil or result == true or result == Result("Success", 0)) then
        head = head + 1
        local s = sessions[m.name]
        if s then
            s.at = time() -- still going, even if they have nothing to send us
            if m.counted then
                s.outDone = s.outDone + 1
                Notify()
            end
        end
        if m.after then m.after() end
        return After(PACE, Pump)
    end
    m.tries = (m.tries or 0) + 1
    if ok and m.tries < TRIES and (result == Result("AddonMessageThrottle", 3) or result == Result("ChannelThrottle", 8)
        or result == Result("AddOnMessageLockdown", 11)) then
        return After(WAIT, Pump)
    end
    if ok and result == Result("TargetOffline", 12) then
        Stop(m.name, L["they're not online"])
    else
        Stop(m.name, ok and ResultName(result) or tostring(result))
    end
    return Pump()
end

-- Queues a payload's pieces for the session's name; `after` runs once the last has gone.
-- `counted` pieces move the progress bar.
local function Queue(name, target, pieces, after, counted)
    for i, piece in ipairs(pieces) do
        local mark = #pieces == 1 and "a" or i == 1 and "b" or i == #pieces and "d" or "c"
        queue[#queue + 1] = { name = name, target = target, text = mark .. piece, counted = counted,
            after = i == #pieces and after or nil }
    end
    if not pumping then Pump() end
end

local function Send(name, target, payload, after)
    local text = ns.SyncEncode(payload)
    if text then Queue(name, target, ns.SyncPieces(text), after) end
end

---------------------------------------------------------------------------
-- Trying a character who may be offline: the game may answer with a "no such player" line in
-- chat. Only that line, about the name just tried, is held back, and only for a few seconds.
---------------------------------------------------------------------------
local tried     -- [name as the game may print it] = true, while the filter is on
local notFound  -- the game's line as a pattern, capturing the name
local hiding = 0

local function HideNotFound(_, _, text)
    if not tried or issecretvalue(text) or type(text) ~= "string" then return false end
    local name = text:match(notFound)
    if not name then return false end
    return tried[name:match("^(.-)%-[^%-]+$") or name] == true
end

local function StopHiding()
    hiding = hiding - 1
    if hiding > 0 then return end
    tried = nil
    local remove = ChatFrame_RemoveMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.RemoveMessageEventFilter)
    if remove then remove("CHAT_MSG_SYSTEM", HideNotFound) end
end

local function HideOffline(name)
    local add = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
    if not add or type(ERR_CHAT_PLAYER_NOT_FOUND_S) ~= "string" then return end
    if not tried then
        tried = {}
        notFound = notFound or ("^" .. ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("%p", "%%%0"):gsub("%%%%s", "(.+)") .. "$")
        add("CHAT_MSG_SYSTEM", HideNotFound)
    end
    tried[name] = true
    tried[name:match("^(%S+)") or name] = true
    hiding = hiding + 1
    After(HIDE_FOR, StopHiding)
end

---------------------------------------------------------------------------
-- Characters
---------------------------------------------------------------------------
-- `changed` is for changes made while the character is offline, such as mail sent to them:
-- `updated` can't say so, as the rested XP estimate counts from it.
local function Stamp(c)
    if c == ns.char then return time() end
    local seen, updated, changed = c.seen, c.updated, c.changed
    local t = type(seen) == "number" and seen or 0
    if type(updated) == "number" and updated > t then t = updated end
    if type(changed) == "number" and changed > t then t = changed end
    return t
end

local function Stamps()
    local have = {}
    for key, c in pairs(ns.db.chars) do have[key] = Stamp(c) end
    return have
end

-- Whether a character the other side has at this stamp is newer than ours. Never the one
-- logged in here, nor one forgotten here unless played since.
local function Wanted(key, stamp)
    if key == ns.charKey then return false end
    local gone = ns.db.forgotten and ns.db.forgotten[key]
    if gone and stamp <= gone then return false end
    local c = ns.db.chars[key]
    return not c or stamp > Stamp(c)
end

local function Package(key, c)
    local copy = {}
    for k, v in pairs(c) do copy[k] = v end
    if c == ns.char then
        copy.updated = time()
        if ns.TouchRun then ns.TouchRun() end -- runs is shared with the copy: sent as of now
    end
    local db, ri, fn, rc = ns.db, nil, nil, nil
    for prof, list in pairs(c.recipes or {}) do
        local info = db.recipeInfo and db.recipeInfo[prof]
        for name in pairs(info and list or {}) do
            if info[name] then
                ri = ri or {}
                ri[prof] = ri[prof] or {}
                ri[prof][name] = info[name]
                -- The category it's filed under, for the alts' profession window.
                local cat = select(5, ns.ParseRecipeInfo(info[name]))
                local catInfo = cat and db.recipeCategories and db.recipeCategories[cat]
                if catInfo then
                    rc = rc or {}
                    rc[cat] = catInfo
                end
            end
        end
    end
    -- Their professions' icons, for the same window.
    local pa
    for prof in pairs(c.profs or {}) do
        local art = db.profArt and db.profArt[prof]
        if art then
            pa = pa or {}
            pa[prof] = art
        end
    end
    for id in pairs(c.reps or {}) do
        local name = db.factions and db.factions[id]
        if name then
            fn = fn or {}
            fn[id] = name
        end
    end
    return { k = "char", key = key, c = copy, ri = ri, fn = fn, rc = rc, pa = pa, rs = c.realm and db.rulesets and db.rulesets[c.realm] }
end

local RULESETS = { normal = true, pvp = true, rp = true, hardcore = true }

-- How many fields a recipeInfo value has (more since the alts' profession window).
local function Fields(info)
    local _, n = info:gsub(";", "")
    return n
end

local function Remember(name)
    ns.db.syncWith = ns.db.syncWith or {}
    ns.db.syncWith[name] = true
end

local function Changed()
    ns.InvalidateCache()
    if ns.UpgradesChanged then ns.UpgradesChanged() end -- and the character sheet's anvils
    if ns.RefreshOverview then ns.RefreshOverview() end
    if ns.LockoutsChanged then ns.LockoutsChanged() end -- their saves and visits this hour
    if ns.RecipesChanged then ns.RecipesChanged() end -- their professions
end

-- Takes in a character the other side sent, if it's newer than ours; returns true if so.
local function Merge(msg)
    local key, inc = msg.key, msg.c
    if type(key) ~= "string" or type(inc) ~= "table" or not Wanted(key, Stamp(inc)) then return false end
    ns.RepairChar(inc)
    inc.name = key
    if type(inc.class) ~= "string" or ns.BetaRealm(inc.realm) and not ns.BetaRealm(ns.char.realm) then return false end
    local db = ns.db
    local c = db.chars[key]
    if c then
        wipe(c)
        for k, v in pairs(inc) do c[k] = v end
    else
        db.chars[key] = inc
    end
    if db.forgotten then
        db.forgotten[key] = nil
        if next(db.forgotten) == nil then db.forgotten = nil end
    end
    Remember(key) -- theirs, so it's worth trying next time, whichever alt they're on
    -- What tooltips need to read their recipes, reputations and ruleset, where we lack it.
    if type(msg.ri) == "table" then
        for prof, list in pairs(msg.ri) do
            if type(prof) == "string" and type(list) == "table" then
                db.recipeInfo = db.recipeInfo or {}
                local mine = db.recipeInfo[prof] or {}
                for name, info in pairs(list) do
                    -- Theirs where we have none, or where it says more (recorded since the
                    -- alts' profession window: recipe ID, category, icon).
                    if type(name) == "string" and type(info) == "string"
                        and (mine[name] == nil or Fields(info) > Fields(mine[name])) then
                        mine[name] = info
                    end
                end
                if next(mine) then db.recipeInfo[prof] = mine end
            end
        end
    end
    if type(msg.rc) == "table" then
        for id, info in pairs(msg.rc) do
            if type(id) == "number" and type(info) == "string" and info:match("^%-?%d+;[^;]+$") then
                db.recipeCategories = db.recipeCategories or {}
                db.recipeCategories[id] = db.recipeCategories[id] or info
            end
        end
    end
    if type(msg.pa) == "table" then
        for prof, art in pairs(msg.pa) do
            if type(prof) == "string" and type(art) == "string" and art:match("^%d+;[^;]*$") then
                db.profArt = db.profArt or {}
                db.profArt[prof] = db.profArt[prof] or art
            end
        end
    end
    if type(msg.fn) == "table" then
        for id, name in pairs(msg.fn) do
            if type(id) == "number" and type(name) == "string" then
                db.factions = db.factions or {}
                if db.factions[id] == nil then db.factions[id] = name end
            end
        end
    end
    if type(inc.realm) == "string" and RULESETS[msg.rs] then
        db.rulesets = db.rulesets or {}
        if db.rulesets[inc.realm] == nil then db.rulesets[inc.realm] = msg.rs end
    end
    Changed()
    return true
end

---------------------------------------------------------------------------
-- Who's talking. The game may give "First Last", "First Last-Realm" or perhaps the first name
-- alone; a first name counts only if it matches exactly one character we know or talk to.
---------------------------------------------------------------------------
-- A first name is matched only against characters the player chose to sync with, never
-- against every character we know (a stranger called Bob isn't your Bob Smith).
local function FullName(sender)
    local name = sender:match("^(.-)%-[^%-]+$") or sender
    if find(name, " ", 1, true) or ns.db.chars[name] or sessions[name] then return name end
    local first, match = name:lower() .. " ", nil
    local function Try(key)
        if key:lower():sub(1, #first) == first then
            if match and match ~= key then return false end
            match = key
        end
        return true
    end
    for key in pairs(ns.db.syncWith or {}) do if not Try(key) then return name end end
    for key in pairs(sessions) do if not Try(key) then return name end end
    return match or name
end

-- Agreed to: one of our characters (it came from an earlier sync: our own account's can't be
-- online with us), or one the player synced with or accepted before.
local function Trusted(name)
    return name ~= ns.charKey and (ns.db.chars[name] ~= nil or (ns.db.syncWith and ns.db.syncWith[name]) == true)
end

---------------------------------------------------------------------------
-- The conversation
---------------------------------------------------------------------------
local function SendWant(s, name, have)
    local keys = {}
    if type(have) == "table" then
        for key, stamp in pairs(have) do
            if type(key) == "string" and type(stamp) == "number" and Wanted(key, stamp) then keys[#keys + 1] = key end
        end
    end
    table.sort(keys)
    Debug("want %d from %s", #keys, name)
    Send(name, s.target, { k = "want", keys = keys })
end

local function Finish(name)
    local s = sessions[name]
    if s and s.sent and s.received then Ended(name) end
end

-- An automatic hello that may go unanswered doesn't take over the window until it's answered.
local function NewSession(name, s)
    s.name, s.got, s.at = name, 0, time()
    sessions[name] = s
    if not (s.quiet and s.ours) then current = s end
    After(QUIET, function() Watch(name, s) end)
    return s
end

local function Hello(reply, auto)
    return { k = "hello", v = PROTOCOL, reply = reply, auto = auto, have = Stamps() }
end

-- Every character is cut into pieces first, so the other side can be told how many to expect.
local function SendChars(s, name, keys)
    local batches, n = {}, 0
    for _, key in ipairs(type(keys) == "table" and keys or {}) do
        local c = type(key) == "string" and ns.db.chars[key]
        local text = c and ns.SyncEncode(Package(key, c))
        if text then
            batches[#batches + 1] = ns.SyncPieces(text)
            n = n + 1
        end
    end
    local closing = ns.SyncPieces(ns.SyncEncode({ k = "done", n = n }))
    local total = #closing
    for _, pieces in ipairs(batches) do total = total + #pieces end
    s.outDone, s.outTotal = 0, total
    Send(name, s.target, { k = "plan", n = total })
    for _, pieces in ipairs(batches) do Queue(name, s.target, pieces, nil, true) end
    Queue(name, s.target, closing, function()
        if not s.quiet then ns.Print(L["Sent %d characters to %s."]:format(n, name)) end
        s.sent, s.sentChars = true, n
        Finish(name)
        Notify()
    end, true)
    Notify()
end

-- They asked, and we agreed (or had before): our hello back, and what we want of theirs.
local function Accept(sender, name, have, quiet)
    Remember(name)
    local s = NewSession(name, { target = sender, quiet = quiet })
    if not quiet then ns.Print(L["Swapping characters with %s..."]:format(name)) end
    Notify()
    Send(name, sender, Hello(true, quiet))
    SendWant(s, name, have)
end

-- Starts a swap from this side. `quiet`: nobody asked for it, so nothing is said in chat, and
-- no answer just means they're not there.
local function Begin(name, target, quiet)
    local s = NewSession(name, { target = target, ours = true, quiet = quiet })
    if quiet then
        HideOffline(name)
    else
        ns.Print(L["Asking %s to swap characters..."]:format(name))
        Notify()
    end
    local function Check()
        if sessions[name] ~= s or s.answered then return end
        -- Their player is reading the pop-up: wait as long as it stays up.
        if s.asking and not s.waited then
            s.waited = true
            return After(ASK_WITHIN, Check)
        end
        Over(name, L["No answer from %s. Both characters need this version of Alts Forever or later, online at the same time on the same ruleset and faction."]:format(name))
    end
    -- The wait starts when the hello really goes: it can sit behind a lockdown or another swap.
    Send(name, target, Hello(nil, quiet), function() After(ANSWER_WITHIN, Check) end)
end

-- A ping or a hello while a swap runs means they've started over (a reload, say), so the
-- swap on their side is gone and ours can't finish.
local function StartedOver(name)
    local s = sessions[name]
    if not s or (s.ours and not s.answered) then return false end
    s.keep = true
    Drop(name)
    Ended(name, L["Sync with %s stopped: %s."]:format(name, L["they started again"]))
    return true
end

local pending -- the hello waiting on the player's answer
local declined = {}

local function Decline(sender, name)
    declined[name] = true
    Send(name, sender, { k = "no" })
end

local function AskDialog()
    if StaticPopupDialogs.ALTSFOREVER_SYNC then return end
    StaticPopupDialogs.ALTSFOREVER_SYNC = {
        text = L["%s wants to swap Alts Forever characters with you.\n\nAccept only if it's your own character on another game account: each side gets everything Alts Forever knows about the other's characters."],
        button1 = ACCEPT or "Accept",
        button2 = DECLINE or "Decline",
        OnAccept = function(_, data)
            pending = nil
            Accept(data.sender, data.name, data.have)
            ns.ToggleSync(true) -- the player just agreed: show them how it's going
        end,
        OnCancel = function(_, data)
            pending = nil
            Decline(data.sender, data.name)
        end,
        OnHide = function() pending = nil end,
        timeout = 60,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

local handle = {}

function handle.hello(msg, sender, name)
    if msg.reply then
        local s = sessions[name]
        if not s or not s.ours or s.answered then return end
        s.answered, s.target, current = true, sender, s
        Remember(name)
        Notify()
        return SendWant(s, name, msg.have)
    end
    local s = sessions[name]
    if StartedOver(name) then s = nil end
    if s then
        -- Both asked at once: take theirs as the answer to ours.
        if s.ours and not s.answered then
            s.answered, s.target, current = true, sender, s
            Remember(name)
            Notify()
            Send(name, sender, Hello(true, s.quiet))
            SendWant(s, name, msg.have)
        end
        return
    end
    -- Nobody is here to ask about an automatic hello, so it's never put to the player.
    if msg.auto and not (Trusted(name) and ns.SyncAutoOn()) then return Send(name, sender, { k = "no" }) end
    if Trusted(name) and not InCombatLockdown() then return Accept(sender, name, msg.have, msg.auto == true) end
    if msg.auto then -- trusted, so what stopped it is a fight: it's on us to swap after
        Keep(name, sender)
        afterCombat = true
        return Send(name, sender, { k = "busy" })
    end
    if declined[name] then return Send(name, sender, { k = "no" }) end
    if pending or InCombatLockdown() then return Send(name, sender, { k = "busy" }) end
    pending = { sender = sender, name = name, have = msg.have }
    AskDialog()
    StaticPopup_Show("ALTSFOREVER_SYNC", name, nil, pending)
    Send(name, sender, { k = "asking" })
end

-- A character of theirs logged in. From a stranger it's nothing at all.
function handle.ping(msg, sender, name)
    if not Trusted(name) or not ns.SyncAutoOn() then return end
    Keep(name, sender)
    StartedOver(name)
    if sessions[name] then return end
    if InCombatLockdown() then
        afterCombat = true
        return
    end
    Begin(name, sender, true)
end

function handle.asking(msg, sender, name)
    local s = sessions[name]
    if not s or not s.ours or s.answered or s.asking then return end
    s.asking = true
    ns.Print(L["Waiting for %s to accept..."]:format(name))
    Notify()
end

function handle.want(msg, sender, name)
    local s = sessions[name]
    if not s or s.wanted then return end
    s.wanted = true
    SendChars(s, name, msg.keys)
end

function handle.plan(msg, sender, name)
    local s = sessions[name]
    if not s or type(msg.n) ~= "number" or msg.n < 1 then return end
    s.inDone, s.inTotal = 0, floor(msg.n)
    Notify()
end

function handle.char(msg, sender, name)
    local s = sessions[name]
    if s and Merge(msg) then s.got = s.got + 1 end
end

function handle.done(msg, sender, name)
    local s = sessions[name]
    if not s then return end
    if not s.quiet then ns.Print(L["Got %d characters from %s."]:format(s.got, name)) end
    s.received = true
    if s.inTotal then s.inDone = s.inTotal end
    Finish(name)
    Notify()
end

function handle.no(msg, sender, name)
    if not sessions[name] then return end
    Over(name, L["%s declined."]:format(name))
end

function handle.busy(msg, sender, name)
    local s = sessions[name]
    if not s then return end
    s.keep = true -- they're there: try again at the next check
    Over(name, L["%s is busy (in combat, or answering another request). Try again in a moment."]:format(name))
end

local buffers = {} -- [sender] = { pieces, bytes }

local function OnMessage(prefix, text, channel, sender)
    if prefix ~= PREFIX or channel ~= "WHISPER" then return end
    if issecretvalue(text) or issecretvalue(sender) or type(text) ~= "string" or type(sender) ~= "string" then return end
    local name = FullName(sender)
    Debug("%d bytes from %s (%s)", #text, sender, name)
    local s = sessions[name]
    if s then
        s.at = time()
        if s.inTotal and s.inDone < s.inTotal then
            s.inDone = s.inDone + 1
            Notify()
        end
    end
    local limit = (Trusted(name) or s) and LIMIT or STRANGER_LIMIT
    local mark, body = sub(text, 1, 1), sub(text, 2)
    local payload
    if mark == "a" then
        buffers[sender] = nil
        payload = body
    elseif mark == "b" then
        buffers[sender] = { body, n = #body }
    else
        local b = buffers[sender]
        if not b then return end
        b[#b + 1] = body
        b.n = b.n + #body
        if mark == "d" then
            buffers[sender] = nil
            payload = concat(b)
        end
    end
    local b = buffers[sender]
    if b and b.n > limit then buffers[sender] = nil end
    if not payload or #payload > limit then return end
    local msg = ns.SyncDecode(payload)
    local fn = type(msg) == "table" and type(msg.k) == "string" and handle[msg.k]
    if fn then fn(msg, sender, name) end
end

---------------------------------------------------------------------------
-- /af sync
---------------------------------------------------------------------------
function ns.SyncWith(target)
    target = target:gsub("^%s+", ""):gsub("%s+$", "")
    if target:lower() == "debug" then
        verbose = not verbose
        return ns.Print(verbose and L["Sync details on."] or L["Sync details off."])
    end
    if target:lower() == "auto" then
        ns.SetSyncAuto(not ns.SyncAutoOn())
        return ns.Print(ns.SyncAutoOn() and L["Automatic sync on."] or L["Automatic sync off."])
    end
    if target == "" then return ns.ToggleSync(true) end
    local name = target:match("^(.-)%-[^%-]+$") or target
    if name:lower() == (ns.charKey or ""):lower() then return ns.Print(L["That's the character you're on."]) end
    if Fresh(sessions[name]) then return ns.Print(L["Already swapping characters with %s."]:format(name)) end
    local restricted = C_ChatInfo and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted
    if restricted then
        local ok, on = pcall(restricted)
        Debug("outgoing addon messages restricted: %s", ok and tostring(on) or "?")
    end
    Begin(name, target)
end

---------------------------------------------------------------------------
-- Keeping in sync by itself
---------------------------------------------------------------------------
function ns.SyncAutoOn() return not ns.db.syncAutoOff end

local autoTicking = false

local function SwapNow()
    if partner and not sessions[partner.name] then Begin(partner.name, partner.target, true) end
end

-- While they stay online, AUTO_EVERY after the last swap. Whoever's check comes first swaps;
-- the other's then finds it was just done and waits out the rest, so a swap for any reason
-- (a login, say) moves the next one back rather than costing a whole extra wait.
local function AutoTick()
    autoTicking = false
    if not partner or not ns.SyncAutoOn() then return end
    autoTicking = true
    local left = lastSwap + AUTO_EVERY - time()
    if left > 0 then return After(left, AutoTick) end
    After(AUTO_EVERY, AutoTick)
    if InCombatLockdown() then
        afterCombat = true
    else
        SwapNow()
    end
end

local function CombatOver()
    if not afterCombat then return end
    afterCombat = false
    SwapNow() -- turning it off clears the partner, so this does nothing then
end

function Keep(name, target)
    if not ns.SyncAutoOn() then return end
    partner = { name = name, target = target }
    if not autoTicking then
        autoTicking = true
        After(AUTO_EVERY, AutoTick)
    end
end

-- Asks the characters most likely to be online on your other accounts. Only those on this
-- ruleset and faction: whispers don't reach the rest.
local function FindOthers()
    if not ns.SyncAutoOn() then return end
    local n = 0
    for _, key in ipairs(ns.SyncPartners()) do
        local c = ns.db.chars[key]
        if key ~= ns.charKey and not (c and ns.Elsewhere(c)) and n < AUTO_MOST then
            n = n + 1
            HideOffline(key)
            Send(key, key, { k = "ping" })
        end
    end
end

function ns.SetSyncAuto(on)
    ns.db.syncAutoOff = not on and true or nil
    if on then FindOthers() else partner = nil end
    Notify()
end

---------------------------------------------------------------------------
-- The window: a name, a button and a progress bar. Everything above works without it.
---------------------------------------------------------------------------
-- Characters synced with before, the most recently played first.
function ns.SyncPartners()
    local list, stamps = {}, {}
    for key in pairs(ns.db.syncWith or {}) do
        list[#list + 1] = key
        local c = ns.db.chars[key]
        stamps[key] = c and Stamp(c) or 0
    end
    table.sort(list, function(a, b)
        if stamps[a] ~= stamps[b] then return stamps[a] > stamps[b] end
        return a < b
    end)
    return list
end

-- How the latest sync stands: the bar's fill (0 to 1), its text, the line under it, and
-- whether one is still going. Nothing at all if there hasn't been one.
function ns.SyncProgress()
    local s = current
    if not s then return nil end
    if not s.over and not Fresh(s) then Stop(s.name, L["nothing heard for two minutes"]) end
    local outDone, outTotal, inDone, inTotal = s.outDone or 0, s.outTotal or 0, s.inDone or 0, s.inTotal or 0
    local fill = outTotal + inTotal > 0 and (outDone + inDone) / (outTotal + inTotal) or 0
    if s.over and not s.why then fill = 1 end
    local text = ""
    if s.outTotal then text = L["Sending %d of %d"]:format(outDone, outTotal) end
    if s.inTotal then
        local receiving = L["Receiving %d of %d"]:format(inDone, inTotal)
        text = text == "" and receiving or text .. " · " .. receiving
    end
    local status
    if s.why then
        status = s.why
    elseif s.over then
        status = L["Got %d characters from %s."]:format(s.got, s.name) .. " "
            .. L["Sent %d characters to %s."]:format(s.sentChars or 0, s.name)
    elseif s.ours and not s.answered then
        status = (s.asking and L["Waiting for %s to accept..."] or L["Asking %s to swap characters..."]):format(s.name)
    else
        status = L["Swapping characters with %s..."]:format(s.name)
    end
    return fill, text, status, not s.over
end

local WIDTH, HEIGHT = 380, 228
local frame
local ticking = false

-- A sync that stalls sends no messages to wake the window, so it checks while it's open.
local function Tick()
    ticking = false
    if frame and frame:IsShown() and current and not current.over then Refresh() end
end

function Refresh()
    if not frame or not frame:IsShown() then return end
    local fill, text, status, going = ns.SyncProgress()
    frame.bar:SetValue(fill or 0)
    frame.barText:SetText(text or "")
    frame.status:SetText(status or "")
    frame.start:SetEnabled(not going)
    frame.pick:SetShown(next(ns.db.syncWith or {}) ~= nil)
    frame.auto:SetChecked(ns.SyncAutoOn())
    if going and not ticking then
        ticking = true
        After(TICK, Tick)
    end
end

local function Start()
    local name = frame.box:GetText() or ""
    if not name:find("%S") then return frame.box:SetFocus() end
    frame.box:ClearFocus()
    ns.SyncWith(name)
end

local function PickPartner(owner)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        for _, key in ipairs(ns.SyncPartners()) do
            root:CreateButton(key, function() frame.box:SetText(key) end)
        end
    end)
end

local function CreateWindow()
    local ok, f = pcall(CreateFrame, "Frame", "AltsForeverSyncFrame", UIParent, "BasicFrameTemplateWithInset")
    if not ok then f = CreateFrame("Frame", "AltsForeverSyncFrame", UIParent, "BackdropTemplate") end
    frame = f
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f.title = f.TitleText or f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if not f.TitleText then f.title:SetPoint("TOP", 0, -6) end
    f.title:SetText(L["Sync with another account"])

    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.hint:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -36)
    f.hint:SetPoint("RIGHT", f, "RIGHT", -18, 0)
    f.hint:SetJustifyH("LEFT")
    f.hint:SetText(L["Log in on both accounts at once, on the same ruleset and faction, then enter the full name of your character on the other account."])

    -- Sync button on the right, the list of earlier characters left of it, the name in the rest.
    local start = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    start:SetSize(80, 22)
    start:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -86)
    start:SetText(L["Sync"])
    start:SetScript("OnClick", Start)
    ns.SkinButton(start)
    f.start = start

    local pick = CreateFrame("Button", nil, f)
    pick:SetSize(22, 22)
    pick:SetPoint("RIGHT", start, "LEFT", -6, 0)
    pick:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    pick:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    pick:SetScript("OnClick", PickPartner)
    pick:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Characters you've synced with"])
        GameTooltip:Show()
    end)
    pick:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.pick = pick

    local okBox, box = pcall(CreateFrame, "EditBox", "AltsForeverSyncBox", f, "InputBoxTemplate")
    if not okBox then box = CreateFrame("EditBox", "AltsForeverSyncBox", f) end
    box:SetHeight(22)
    box:SetPoint("LEFT", f, "LEFT", 24, 0)
    box:SetPoint("TOP", start, "TOP", 0, 0)
    box:SetPoint("RIGHT", pick, "LEFT", -8, 0)
    box:SetAutoFocus(false)
    box:SetScript("OnEnterPressed", Start)
    box:SetScript("OnEscapePressed", function() f:Hide() end)
    ns.SkinEditBox(box)
    f.box = box

    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetHeight(20)
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -118)
    bar:SetPoint("RIGHT", f, "RIGHT", -18, 0)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.2, 0.7, 0.3)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    local back = bar:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints()
    back:SetColorTexture(0, 0, 0, 0.5)
    f.bar = bar
    f.barText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.barText:SetPoint("CENTER")

    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.status:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -8)
    f.status:SetPoint("RIGHT", f, "RIGHT", -18, 0)
    f.status:SetJustifyH("LEFT")

    local auto = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    auto:SetSize(26, 26)
    auto:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 8)
    auto:SetScript("OnClick", function(self) ns.SetSyncAuto(self:GetChecked() and true or false) end)
    auto:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Sync by itself when both are online"])
        GameTooltip:AddLine(L["Once you've synced, your accounts swap changes by themselves whenever both are online: when either logs in, then every 10 minutes. Same as /af sync auto."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    auto:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ns.SkinCheck(auto)
    f.auto = auto
    f.autoLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.autoLabel:SetPoint("LEFT", auto, "RIGHT", 4, 0)
    f.autoLabel:SetText(L["Sync by itself when both are online"])
    ns.SkinText(f.autoLabel)

    ns.SkinWindow(f)
    f:SetScript("OnShow", function(self)
        self:Raise()
        if (box:GetText() or "") == "" then
            box:SetText(current and current.name or ns.SyncPartners()[1] or "")
        end
        Refresh()
    end)
    f:SetScript("OnHide", function()
        box:ClearFocus()
        GameTooltip:Hide()
    end)
    -- Escape closes it, like Blizzard's own windows.
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "AltsForeverSyncFrame" end
    f:Hide()
    ns.GamepadWindow(f)
    ns.ScaleWindow(f)
end

-- Opens or closes the window; `open` only ever opens it.
function ns.ToggleSync(open)
    if not frame then CreateWindow() end
    if frame:IsShown() and not open then return frame:Hide() end
    frame:Show()
    frame:Raise()
end

function ns.StartSync()
    local register = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix
    if register then pcall(register, PREFIX) end
    ns.On("CHAT_MSG_ADDON", OnMessage)
    ns.On("PLAYER_REGEN_ENABLED", CombatOver)
    -- Logged in here, so it's ours: nothing to look for on another account.
    if ns.db.syncWith then
        ns.db.syncWith[ns.charKey] = nil
        if next(ns.db.syncWith) == nil then ns.db.syncWith = nil end
    end
    After(AUTO_DELAY, FindOthers)
end
