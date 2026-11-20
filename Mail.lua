-- Alts Forever mail: reads the inbox while the mailbox is open, credits items you mail
-- to your own characters straight away, warns when mail with items or gold is about to
-- expire, and adds an "Alts" button to the send-mail screen.
local _, ns = ...
if ns.disabled then return end -- another copy of Alts Forever is running (Core.lua)
local L = ns.L

local wipe, pairs, next, floor, time = wipe, pairs, next, math.floor, time
local issecretvalue = issecretvalue or function() return false end
local GetInboxNumItems, GetInboxHeaderInfo, GetInboxItem = GetInboxNumItems, GetInboxHeaderInfo, GetInboxItem
local GetSendMailItem, GetSendMailMoney = GetSendMailItem, GetSendMailMoney
local type = type

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
    if seconds <= 0 then return L["expired"] end
    local d, h = floor(seconds / DAY), floor(seconds % DAY / 3600)
    if d > 0 then return L["%dd %dh"]:format(d, h) end
    if h > 0 then return L["%dh"]:format(h) end
    return L["<1h"]
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
            .. " " .. (c.mailDeletes and L["(will be |cffff2020deleted|r)"] or L["(returned to sender)"])
    end
    return list
end

function ns.PrintMailWarnings(within)
    local lines = ns.MailWarnings(time(), within or WARN_WITHIN)
    if #lines == 0 then return false end
    ns.Print(L["Mail with items or gold expiring soon:"])
    for _, line in ipairs(lines) do ns.Print("  " .. line) end
    return true
end

-- The full name typed in the To box. Forever has no realms; a "-Realm" suffix, in
-- case the client still accepts one, is ignored.
function ns.RecipientKey(recipient)
    local name = recipient:gsub("%-.*$", ""):match("^%s*(.-)%s*$")
    return ns.FindChar(name)
end

-- Whether you can mail a character from this one: not you, and your own faction on your
-- own ruleset (an unknown faction counts as yours).
function ns.CanMailTo(key)
    local c = key and ns.db.chars[key]
    if not c or key == ns.charKey then return false end
    local faction = ns.char.faction
    return (not c.faction or not faction or c.faction == faction) and not ns.Elsewhere(c)
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
        if not issecretvalue(id) and id then attached[#attached + 1] = id end
    end
    wipe(entries)
    local chars = ns.db.chars
    for i, key in ipairs(ns.OverviewOrder()) do
        local c = chars[key]
        if ns.CanMailTo(key) then
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
    ns.OpenMenu(owner, function(_, root)
        root:CreateTitle(L["Send to"])
        local list = ns.SendToAltEntries()
        if #list == 0 then root:CreateTitle("|cff9d9d9d" .. L["No other characters yet"] .. "|r") end
        for _, e in ipairs(list) do
            local c = ns.db.chars[e.key]
            local text = ns.ColoredName(e.key, c)
            if e.n > 0 then
                text = text .. LIGHT .. " · " .. (e.n == 1 and L["skill-ups with %d item"] or L["skill-ups with %d items"]):format(e.n) .. "|r"
            end
            root:CreateButton(text, function()
                SendMailNameEditBox:SetText(c.name or e.key)
                if ns.MailRecipientChosen then ns.MailRecipientChosen() end -- MailRules.lua
            end)
        end
        -- Mail rules (MailRules.lua): suggestions, "Remember for ...", the rules window.
        if ns.AddMailRuleMenu then ns.AddMailRuleMenu(root) end
    end)
end

-- The mailbox arrow can be turned off from the options menu ("Send mail to alts").
-- The subject, as the game would fill it. Forever's mail window names a mail after its
-- first attachment ("Linen Cloth (20)") only while C.O.D. can be used (Blizzard_MailFrame
-- SendMailFrame_Update, forever branch), and on live C_Mail.IsCODEnabled() is false (owner's
-- check, 2026-11-18), so attaching (by hand or with Pack) left it empty and Send greyed out
-- until one was typed. Done here the same way while the game doesn't: only into an empty
-- subject or one put there by us, and taken out again when the attachments go; a subject
-- the player typed is never touched. Part of "Send mail to alts", like the rest of the
-- mailbox help.
local subjectFilled -- the subject we put in, while it's still there
-- An attachment's name comes only once the game has loaded the item: GetSendMailItem gives
-- nil before (Blizzard's own SendMailFrame_Update allows for it). The owner once saw Send
-- greyed out after Pack (2026-11-20, not seen again: the second time the item was loaded),
-- so a missing name is asked for and the subject filled when it arrives.
local subjectWait = {} -- [itemID] = true while its name is asked for

function ns.ResetMailSubject() subjectFilled = nil end

local function AttachmentName(i)
    local name, id, _, count = GetSendMailItem(i)
    if issecretvalue(name) or issecretvalue(id) or issecretvalue(count) then return end
    if name == nil and type(id) == "number" then
        name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
        if issecretvalue(name) then name = nil end
        if name == nil and not subjectWait[id] and C_Item and C_Item.RequestLoadItemDataByID then
            subjectWait[id] = true
            C_Item.RequestLoadItemDataByID(id)
        end
    end
    return name, count, type(id) == "number"
end

function ns.FillMailSubject()
    local box = SendMailSubjectEditBox
    if not (box and C_Mail and C_Mail.IsCODEnabled) or not ns.SendToAltOn() then return end
    local cod = C_Mail.IsCODEnabled()
    if issecretvalue(cod) or cod ~= false then return end -- the game does it itself
    local title, attachedAny
    for i = 1, MAX_SEND do
        local name, count, isItem = AttachmentName(i)
        if name ~= nil then
            title = type(count) == "number" and count > 1 and (name .. " (" .. count .. ")") or name
            break
        end
        attachedAny = attachedAny or isItem
    end
    local text = box:GetText()
    if issecretvalue(text) then return end
    text = text or ""
    if title then
        if text == "" or text == subjectFilled then
            if text ~= title then box:SetText(title) end
            subjectFilled = title
        end
    elseif subjectFilled and not attachedAny then -- names still loading keep it
        if text == subjectFilled then box:SetText("") end
        subjectFilled = nil
    end
end

function ns.SendToAltOn()
    return not ns.db.sendToAltOff
end

local altsButton
function ns.SetSendToAlt(on)
    ns.db.sendToAltOff = not on or nil
    if altsButton then altsButton:SetShown(on) end
    if ns.MailRulesChanged then ns.MailRulesChanged() end -- the mailbox and the Mail rules window
end

-- Just right of the To box, or right of Posty Forever's address book button (Postal's
-- BlackBook, the same place: 25 px at the box's right edge, 2 px up), which would cover it.
-- Placed at each MAIL_SHOW, as Posty's module can be turned off and on.
local function PlaceAltsButton()
    if not altsButton then return end
    local posty = _G.Postal_BlackBookButton
    local anchor, y = SendMailNameEditBox, 0
    if posty and posty.IsShown and posty:IsShown() then anchor, y = posty, -2 end
    altsButton:ClearAllPoints()
    altsButton:SetPoint("LEFT", anchor, "RIGHT", altsButton.elvArrow and 3 or 0, y)
end

-- `early`: made before the mailbox opens (Gamepad UI, ns.PrebuildMail), so even with "Send
-- mail to alts" off; it's hidden then, and SetSendToAlt shows it.
local function CreateAltsButton(early)
    if altsButton or not (early or ns.SendToAltOn()) or not (SendMailFrame and SendMailNameEditBox) then return end
    -- A small dropdown arrow just right of the To box. It fits the gap before "Postage"
    -- (a 52 px button there covered it).
    local b = CreateFrame("Button", nil, SendMailFrame)
    b:SetSize(18, 18)
    b:SetPoint("LEFT", SendMailNameEditBox, "RIGHT", 0, 0)
    b:SetFrameLevel(SendMailNameEditBox:GetFrameLevel() + 2)
    b:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    b:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    b.alts = true
    b:SetScript("OnClick", AltsMenu)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Send to one of your characters"])
        GameTooltip:AddLine(L["Characters who can still skill up with what you've attached are marked."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ns.SkinArrow(b, SendMailNameEditBox)
    altsButton = b
    b:SetShown(ns.SendToAltOn())
end

-- With the Gamepad UI on (Gamepad.lua): our parts of the send tab are made while the mailbox
-- is closed. Made at the first MAIL_SHOW instead, inside the open window, Blizzard's navigator
-- rebuilds it from our code (its CreateFrame hook), which can taint its bindings: a player's
-- ADDON_ACTION_FORBIDDEN on SetPreferredGamepadInteractTarget() closing the bags (2026-11-20).
function ns.PrebuildMail()
    if (MailFrame and MailFrame:IsVisible()) or (SendMailFrame and SendMailFrame:IsVisible()) then return end
    CreateAltsButton(true)
    PlaceAltsButton()
    if ns.PrebuildMailParts then ns.PrebuildMailParts() end
end

function ns.StartMail()
    local char = ns.char
    local pendingKey, pending, pendingMoney = nil, {}, 0

    local function ScanInbox()
        char.mail = char.mail or {}
        char.mailExpires, char.mailDeletes = ns.ScanInbox(char.mail)
        char.mailAt = time() -- the bags window's Mail view says how old its list is
        ns.version = ns.version + 1
        if ns.RefreshOverview then ns.RefreshOverview() end -- its Mail column, if open
        if ns.BagsWindowChanged then ns.BagsWindowChanged() end -- its Mail view, if open
    end

    -- The inbox can only be read while the mailbox is open.
    local mailOpen = false
    ns.On("MAIL_SHOW", function()
        mailOpen = true
        ns.ResetMailSubject()
        CreateAltsButton()
        PlaceAltsButton()
    end)
    ns.On("MAIL_CLOSED", function() mailOpen = false end)
    ns.On("MAIL_SEND_INFO_UPDATE", function() ns.FillMailSubject() end)
    ns.On("GET_ITEM_INFO_RECEIVED", function(id)
        if not subjectWait[id] then return end
        subjectWait[id] = nil
        if SendMailFrame and SendMailFrame:IsVisible() then ns.FillMailSubject() end
    end)
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
        alt.changed = time() -- so a sync with another account picks it up
        wipe(pending)
        pendingMoney = 0
        ns.InvalidateCache()
        if ns.RefreshOverview then ns.RefreshOverview() end
    end)

    ns.On("MAIL_FAILED", function()
        pendingKey = nil
        wipe(pending)
        pendingMoney = 0
    end)

    -- Warn a few seconds after logging in, once the login chat spam has passed.
    if C_Timer then C_Timer.After(5, function() ns.PrintMailWarnings() end) end
end
