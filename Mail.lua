-- Alts Forever mail: reads the inbox while the mailbox is open, credits items you mail
-- to your own characters straight away, warns when mail with items or gold is about to
-- expire, and adds an "Alts" button to the send-mail screen.
local _, ns = ...

local wipe, pairs, next, floor, time = wipe, pairs, next, math.floor, time
local issecretvalue = issecretvalue or function() return false end
local GetInboxNumItems, GetInboxHeaderInfo, GetInboxItem = GetInboxNumItems, GetInboxHeaderInfo, GetInboxItem
local GetSendMailItem, GetSendMailMoney = GetSendMailItem, GetSendMailMoney

local MAX_RECEIVE = ATTACHMENTS_MAX_RECEIVE or 16
local MAX_SEND = ATTACHMENTS_MAX_SEND or 12
local DAY = 86400
local SENT_MAIL_DAYS = 30
local WARN_WITHIN = 3 * DAY

-- Fills `out` with itemID -> count, and returns when the soonest mail carrying items
-- or gold expires, and whether that mail will then be deleted rather than returned
-- (mail already returned once, or from the auction house or an NPC).
function ns.ScanInbox(out)
    wipe(out)
    local now, expires, deletes = time(), nil, nil
    for i = 1, GetInboxNumItems() do
        local _, _, _, _, money, _, daysLeft, attached, _, wasReturned, _, canReply = GetInboxHeaderInfo(i)
        if attached and attached ~= 0 then
            for a = 1, MAX_RECEIVE do
                local _, id, _, count = GetInboxItem(i, a)
                if id and not issecretvalue(count) and count then
                    out[id] = (out[id] or 0) + count
                end
            end
        end
        local valuable = (attached and attached ~= 0) or (money and money > 0)
        if valuable and daysLeft then
            local at = now + floor(daysLeft * DAY)
            if not expires or at < expires then
                expires, deletes = at, (wasReturned or not canReply) and true or nil
            end
        end
    end
    return expires, deletes
end

-- "2d 4h", "5h" or "<1h"; "expired" once the time has passed.
function ns.ExpiryText(seconds)
    if seconds <= 0 then return "expired" end
    local d, h = floor(seconds / DAY), floor(seconds % DAY / 3600)
    if d > 0 then return d .. "d " .. h .. "h" end
    if h > 0 then return h .. "h" end
    return "<1h"
end

-- Red under a day, orange under the warning window, plain otherwise.
function ns.ExpiryColor(seconds)
    if seconds < DAY then return "|cffff2020" end
    if seconds < WARN_WITHIN then return "|cffff8000" end
    return "|cffffffff"
end

-- One line per character whose mail expires within `within` seconds, soonest first.
function ns.MailWarnings(now, within)
    local list = {}
    for key, c in pairs(ns.db.chars) do
        if c.mailExpires and c.mailExpires - now < within then list[#list + 1] = key end
    end
    local chars = ns.db.chars
    table.sort(list, function(a, b) return chars[a].mailExpires < chars[b].mailExpires end)
    for i, key in ipairs(list) do
        local c = chars[key]
        local left = c.mailExpires - now
        list[i] = ns.ColoredName(key, c) .. ": " .. ns.ExpiryColor(left) .. ns.ExpiryText(left) .. "|r"
            .. (c.mailDeletes and " (will be |cffff2020deleted|r)" or " (returned to sender)")
    end
    return list
end

function ns.PrintMailWarnings(within)
    local lines = ns.MailWarnings(time(), within or WARN_WITHIN)
    if #lines == 0 then return false end
    ns.Print("Mail with items or gold expiring soon:")
    for _, line in ipairs(lines) do ns.Print("  " .. line) end
    return true
end

-- The full name typed in the To box. Forever has no realms; a "-Realm" suffix, in
-- case the client still accepts one, is ignored.
function ns.RecipientKey(recipient)
    local name = recipient:gsub("%-.*$", ""):match("^%s*(.-)%s*$")
    return ns.FindChar(name)
end

---------------------------------------------------------------------------
-- "Alts" button beside the To box on the send-mail screen: picking one of your characters
-- fills in their name (nothing is sent). Characters who can still skill up with an
-- attached item are marked and listed first. Created the first time the mailbox opens;
-- the menu is only built when clicked.
---------------------------------------------------------------------------
local LIGHT = "|cffc0c0c0"
local attached, entries = {}, {}

local function ByUse(a, b)
    if a.n ~= b.n then return a.n > b.n end
    return a.i < b.i
end

function ns.SendToAltEntries()
    wipe(attached)
    for i = 1, MAX_SEND do
        local _, id = GetSendMailItem(i)
        if id and not issecretvalue(id) then attached[#attached + 1] = id end
    end
    wipe(entries)
    local chars, faction = ns.db.chars, ns.char.faction
    for i, key in ipairs(ns.OverviewOrder()) do
        local c = chars[key]
        -- Mail only goes to your own faction.
        if key ~= ns.charKey and (not c.faction or not faction or c.faction == faction) then
            local n = 0
            for _, id in ipairs(attached) do
                if ns.CanSkillUpWith(c, id) then n = n + 1 end
            end
            entries[#entries + 1] = { key = key, n = n, i = i }
        end
    end
    table.sort(entries, ByUse)
    return entries
end

local function AltsMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Send to")
        local list = ns.SendToAltEntries()
        if #list == 0 then root:CreateTitle("|cff9d9d9dNo other characters yet|r") end
        for _, e in ipairs(list) do
            local c = ns.db.chars[e.key]
            local text = ns.ColoredName(e.key, c)
            if e.n > 0 then
                text = text .. LIGHT .. " · skill-ups with " .. e.n .. (e.n == 1 and " item" or " items") .. "|r"
            end
            root:CreateButton(text, function() SendMailNameEditBox:SetText(c.name or e.key) end)
        end
    end)
end

-- The mailbox arrow can be turned off from the options menu ("Send mail to alts").
function ns.SendToAltOn()
    return not ns.db.sendToAltOff
end

local altsButton
function ns.SetSendToAlt(on)
    ns.db.sendToAltOff = not on or nil
    if altsButton then altsButton:SetShown(on) end
end

local function CreateAltsButton()
    if altsButton or not ns.SendToAltOn() or not (SendMailFrame and SendMailNameEditBox) then return end
    -- A small dropdown arrow just right of the To box. It fits the gap before "Postage"
    -- (a 52 px button there covered it).
    local b = CreateFrame("Button", nil, SendMailFrame)
    b:SetSize(18, 18)
    b:SetPoint("LEFT", SendMailNameEditBox, "RIGHT", 4, 0)
    b:SetFrameLevel(SendMailNameEditBox:GetFrameLevel() + 2)
    b:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    b:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    b.alts = true
    b:SetScript("OnClick", AltsMenu)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Send to one of your characters")
        GameTooltip:AddLine("Characters who can still skill up with what you've attached are marked.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    altsButton = b
end

function ns.StartMail()
    local char = ns.char
    local pendingKey, pending, pendingMoney = nil, {}, 0

    local function ScanInbox()
        char.mail = char.mail or {}
        char.mailExpires, char.mailDeletes = ns.ScanInbox(char.mail)
        ns.version = ns.version + 1
    end

    -- The inbox can only be read while the mailbox is open.
    local mailOpen = false
    ns.On("MAIL_SHOW", function()
        mailOpen = true
        CreateAltsButton()
    end)
    ns.On("MAIL_CLOSED", function() mailOpen = false end)
    ns.On("MAIL_INBOX_UPDATE", function()
        if mailOpen then ScanInbox() end
    end)

    -- Remember what's attached when you press Send; the attachments are only
    -- credited to the alt once the server confirms the mail went.
    hooksecurefunc("SendMail", function(recipient)
        wipe(pending)
        pendingKey = recipient and ns.RecipientKey(recipient)
        if not pendingKey or pendingKey == ns.charKey then
            pendingKey = nil
            return
        end
        for i = 1, MAX_SEND do
            local _, id, _, count = GetSendMailItem(i)
            if id and not issecretvalue(count) and count then
                pending[id] = (pending[id] or 0) + count
            end
        end
        pendingMoney = GetSendMailMoney() or 0
    end)

    ns.On("MAIL_SEND_SUCCESS", function()
        local alt = pendingKey and ns.db.chars[pendingKey]
        pendingKey = nil
        if not alt or (next(pending) == nil and pendingMoney <= 0) then return end
        alt.mail = alt.mail or {}
        for id, count in pairs(pending) do
            alt.mail[id] = (alt.mail[id] or 0) + count
        end
        -- Mail you send lasts 30 days, then goes back to you.
        local at = time() + SENT_MAIL_DAYS * DAY
        if not alt.mailExpires or at < alt.mailExpires then alt.mailExpires, alt.mailDeletes = at, nil end
        wipe(pending)
        pendingMoney = 0
        ns.InvalidateCache()
    end)

    ns.On("MAIL_FAILED", function()
        pendingKey = nil
        wipe(pending)
        pendingMoney = 0
    end)

    -- Warn a few seconds after logging in, once the login chat spam has passed.
    if C_Timer then C_Timer.After(5, function() ns.PrintMailWarnings() end) end
end
