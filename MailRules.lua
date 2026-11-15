-- Alts Forever mail rules (owner's request, 2026-11-14: "cloth always goes to Clarissa").
-- A rule sends one item, or a whole category of items (Cloth, Herb, Metal & Stone...), to
-- one of your characters. At the mailbox:
--   * the first item you attach fills in the To box from its rule, never over a name you
--     typed or picked; clearing what it filled in keeps it clear until the attachments are
--     emptied or the mail goes;
--   * a line above the attachments says which rule filled it in (click it to undo), or that
--     another attachment has a rule of its own;
--   * a Pack button attaches from your bags what your rules send to that character.
-- Rules are made from the arrow beside the To box (Mail.lua's menu: "Remember for ...",
-- and suggestions from who uses the item in their known recipes) and listed in the Mail
-- rules window (`/af mailrules`), where they're removed.
--
-- db.mailRules = { [rule] = { [full name] = example item ID } }: rule "i:<itemID>" for one
-- item, "c:<classID>:<subclassID>" for a category (C_Item.GetItemInfoInstant; Silk Cloth is
-- 7, 5 on Forever, seen in game 2026-11-14). A rule can name one character per place you
-- mail from (ruleset and faction): setting one replaces only a name you could mail from
-- here, so Horde and Alliance characters can each have their own. The example item gives a
-- category its icon in the window. db.mailFillOff / db.mailPackOff turn the two parts off.
local _, ns = ...
if ns.disabled then return end -- another copy of Alts Forever is running (Core.lua)
local L = ns.L

local pairs, ipairs, next, wipe, type, tonumber, min, max = pairs, ipairs, next, wipe, type, tonumber, math.min, math.max
local tremove, sort = table.remove, table.sort
local issecretvalue = issecretvalue or function() return false end
local GetSendMailItem = GetSendMailItem

local MAX_SEND = ATTACHMENTS_MAX_SEND or 12
local TRADE_GOODS = 7 -- Enum.ItemClass.Tradegoods
local OTHER_GOODS = 11 -- Trade Goods: Other, too vague to name on its own
local GREY, LIGHT = "|cff9d9d9d", "|cffc0c0c0"

---------------------------------------------------------------------------
-- Rules
---------------------------------------------------------------------------
local itemRules, categoryRules = {}, {} -- [itemID] = rule key (false: no category); per session

local function ItemRule(id)
    local rule = itemRules[id]
    if not rule then
        rule = "i:" .. id
        itemRules[id] = rule
    end
    return rule
end
ns.MailItemRule = ItemRule

local function CategoryRule(id)
    local rule = categoryRules[id]
    if rule == nil then
        local _, _, _, _, _, class, sub = C_Item.GetItemInfoInstant(id)
        if issecretvalue(class) or issecretvalue(sub) or type(class) ~= "number" or type(sub) ~= "number" then
            rule = false
        else
            rule = "c:" .. class .. ":" .. sub
        end
        categoryRules[id] = rule
    end
    return rule or nil
end
ns.MailCategoryRule = CategoryRule

-- The character a rule sends to from here, or nil (none, or none you can mail from here).
local function TargetOf(rule)
    local names = ns.db.mailRules and ns.db.mailRules[rule]
    if not names then return nil end
    local best
    for key in pairs(names) do
        if ns.CanMailTo(key) and (not best or key < best) then best = key end
    end
    return best
end
ns.MailRuleTarget = TargetOf

-- Who an item goes to, and by which rule: its own rule first, then its category's.
function ns.MailRuleFor(id)
    local rule = ItemRule(id)
    local key = TargetOf(rule)
    if key then return key, rule end
    rule = CategoryRule(id)
    key = rule and TargetOf(rule)
    if key then return key, rule end
end

-- What a category rule is called: "Cloth" for trade goods, else "Armor: Cloth".
local function CategoryName(rule)
    local class, sub = rule:match("^c:(%d+):(%d+)$")
    class, sub = tonumber(class), tonumber(sub)
    if not class then return rule end
    local subName = C_Item.GetItemSubClassInfo and C_Item.GetItemSubClassInfo(class, sub)
    if issecretvalue(subName) or subName == "" then subName = nil end
    if subName and class == TRADE_GOODS and sub ~= OTHER_GOODS then return subName end
    local className = C_Item.GetItemClassInfo and C_Item.GetItemClassInfo(class)
    if issecretvalue(className) or className == "" then className = nil end
    if className and subName then return L["%s: %s"]:format(className, subName) end
    return subName or className or rule
end

-- The item or category a rule is for, as words ("Silk Cloth", "Cloth"), and whether it's
-- a category. An item whose name isn't loaded yet is asked for and reads "Item 4306".
function ns.MailRuleName(rule)
    local id = tonumber(rule:match("^i:(%d+)$"))
    if not id then return CategoryName(rule), true end
    local name = C_Item.GetItemNameByID(id)
    if issecretvalue(name) or not name then
        if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        return L["Item %d"]:format(id), false, true
    end
    return name, false
end

-- The window's label: "All Cloth" or "Silk Cloth".
function ns.MailRuleLabel(rule)
    local name, category, missing = ns.MailRuleName(rule)
    return category and L["All %s"]:format(name) or name, missing
end

local Changed -- below: refreshes the mailbox and the window

-- Whether two characters share a mailbox world: the same ruleset and faction (unknown
-- counts as the same, as ns.Elsewhere does).
local function SameWorld(a, b)
    if a.realm and b.realm and a.realm ~= b.realm and ns.RulesetOf(a.realm) ~= ns.RulesetOf(b.realm) then
        return false
    end
    return not (a.faction and b.faction and a.faction ~= b.faction)
end

-- Sends a rule's items to `key` (on) or stops sending them to `key` (off). `example` is an
-- item the rule covers, for a category's icon. Turning it on replaces the name in key's
-- world (ruleset and faction) and keeps the others'.
function ns.SetMailRule(rule, key, on, example)
    local db = ns.db
    local names = db.mailRules and db.mailRules[rule]
    if on then
        db.mailRules = db.mailRules or {}
        names = names or {}
        db.mailRules[rule] = names
        local chars, mine = db.chars, db.chars[key]
        for other in pairs(names) do
            if other ~= key and (not chars[other] or not mine or SameWorld(chars[other], mine)) then
                names[other] = nil
            end
        end
        names[key] = example or names[key] or tonumber(rule:match("^i:(%d+)$")) or 0
    elseif names then
        names[key] = nil
        if not next(names) then db.mailRules[rule] = nil end
        if not next(db.mailRules) then db.mailRules = nil end
    end
    Changed()
end

-- A forgotten character's rules go with them (Options.lua's ns.ForgetCharacter).
function ns.ForgetMailRules(key)
    local rules = ns.db.mailRules
    if not rules then return end
    for rule, names in pairs(rules) do
        names[key] = nil
        if not next(names) then rules[rule] = nil end
    end
    if not next(rules) then ns.db.mailRules = nil end
    Changed()
end

-- Every rule and character, by label: { rule, key, example, label }.
function ns.MailRuleList()
    local list, missing = {}, false
    for rule, names in pairs(ns.db.mailRules or {}) do
        local label, gap = ns.MailRuleLabel(rule)
        missing = missing or gap
        for key, example in pairs(names) do
            list[#list + 1] = { rule = rule, key = key, example = example, label = label }
        end
    end
    sort(list, function(a, b)
        if a.label ~= b.label then return a.label < b.label end
        return a.key < b.key
    end)
    return list, missing
end

-- How many of a character's known recipes use an item.
function ns.RecipesUsing(c, id)
    local info = ns.db.recipeInfo
    if not (info and c.recipes) then return 0 end
    local needle, n = "," .. id .. ":", 0
    for prof, known in pairs(c.recipes) do
        local recipes = info[prof]
        if recipes then
            for lname in pairs(known) do
                local v = recipes[lname]
                if type(v) == "string" and v:find(needle, 1, true) then n = n + 1 end
            end
        end
    end
    return n
end

-- Characters you can mail who use an item in their known recipes, most recipes first:
-- { { key, n } }.
function ns.MailSuggestions(id)
    local list, chars = {}, ns.db.chars
    for i, key in ipairs(ns.OverviewOrder()) do
        if ns.CanMailTo(key) then
            local n = ns.RecipesUsing(chars[key], id)
            if n > 0 then list[#list + 1] = { key = key, n = n, i = i } end
        end
    end
    sort(list, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.i < b.i
    end)
    return list
end

-- What a suggestion makes: a category rule for trade goods (all the cloth), else one item.
function ns.SuggestedRule(id)
    local rule = CategoryRule(id)
    local class, sub = rule and rule:match("^c:(%d+):(%d+)$")
    if tonumber(class) == TRADE_GOODS and tonumber(sub) ~= OTHER_GOODS then return rule end
    return ItemRule(id)
end

function ns.MailFillOn() return not ns.db.mailFillOff end
function ns.MailPackOn() return not ns.db.mailPackOff end
function ns.SetMailFill(on)
    ns.db.mailFillOff = not on or nil
    Changed()
end
function ns.SetMailPack(on)
    ns.db.mailPackOff = not on or nil
    Changed()
end

---------------------------------------------------------------------------
-- At the mailbox
---------------------------------------------------------------------------
local order, inOrder = {}, {} -- attached item IDs, in the order they were first attached
local nowList, nowSet, names = {}, {}, {} -- scratch; names[itemID] = name from the attachment
local filled -- the name our rules put in the To box (nil once it says something else)
local manual -- the player changed what we filled in; cleared when the attachments empty
local note, pack, busy
-- Posty Forever's "Autofill last person mailed" (on by default) puts the last name sent to
-- in the To box after each send and on switching to Send Mail. That name is its guess, not
-- the player's choice, so a rule may replace it (owner, 2026-11-15): `auto` = the name it
-- filled in, `restore` = the one our fill replaced (put back by undo, or when its item goes).
local auto, restore, replying

local function ToText()
    local text = SendMailNameEditBox and SendMailNameEditBox:GetText()
    if issecretvalue(text) or type(text) ~= "string" then return "" end
    return text
end

-- Reads the attachments into `order`; returns how many slots are used.
local function ReadAttachments()
    wipe(nowList)
    wipe(nowSet)
    local used = 0
    for i = 1, MAX_SEND do
        local name, id = GetSendMailItem(i)
        if not issecretvalue(id) and id then
            used = used + 1
            if not nowSet[id] then
                nowSet[id] = true
                nowList[#nowList + 1] = id
            end
            if not issecretvalue(name) and name then names[id] = name end
        end
    end
    for i = #order, 1, -1 do
        local id = order[i]
        if not nowSet[id] then
            tremove(order, i)
            inOrder[id] = nil
        end
    end
    for _, id in ipairs(nowList) do
        if not inOrder[id] then
            order[#order + 1] = id
            inOrder[id] = true
        end
    end
    return used
end

-- The item that decides who the mail goes to: the first one attached.
function ns.MailFirstItem()
    ReadAttachments()
    return order[1]
end

local function ItemName(id)
    local name = C_Item.GetItemNameByID(id)
    if issecretvalue(name) or not name then name = names[id] end
    if issecretvalue(name) or not name then return L["Item %d"]:format(id) end
    return name
end

-- The name Posty Forever's autofill would put in the To box now, or nil (BlackBook.lua:
-- the first of its recent recipients, "name|realm|faction", on this realm and faction who
-- isn't you). Its saved settings are read only, never changed.
local function PostyAutoName()
    local posty = _G.PostyForever
    local db = type(posty) == "table" and type(posty.db) == "table" and type(posty.db.profile) == "table"
        and posty.db.profile.BlackBook
    if type(db) ~= "table" or not db.AutoFill or type(db.recent) ~= "table" then return nil end
    local realm, faction = GetRealmName(), UnitFactionGroup("player")
    if issecretvalue(realm) or issecretvalue(faction) then return nil end
    local me = ns.char and ns.char.name
    for _, entry in ipairs(db.recent) do
        if type(entry) == "string" then
            local p, r, f = entry:match("^([^|]*)|([^|]*)|([^|]*)$")
            if p and r == realm and f == faction and p ~= me and p ~= ns.charKey then return p end
        end
    end
end

-- A frame after a send or switching to Send Mail (Posty fills the box inside both, after
-- our hooks run), a name it put there is its guess. Never after Reply, which fills in the
-- sender through the same tab switch.
local function CatchAutoFill()
    if not C_Timer then return end
    C_Timer.After(0, function()
        local reply = replying
        replying = nil
        if reply or not (SendMailFrame and SendMailFrame:IsVisible()) then return end
        local text = ToText()
        if text ~= "" and text == PostyAutoName() and ReadAttachments() == 0 then auto = text end
    end)
end

-- An attachment whose rule sends it to someone other than `recipient`: its ID and who.
local function Conflict(recipient)
    for _, id in ipairs(order) do
        local key = ns.MailRuleFor(id)
        if key and key ~= recipient then return id, key end
    end
end

local function UpdateNote(text, rule)
    if not note then return end
    local parts = {}
    note.undo = nil
    -- Only about what a rule did: a name the player typed or picked is theirs, and mail to
    -- anyone else says nothing (owner, 2026-11-15: "their actions should always prevail").
    if not (rule and filled and text == filled) then return note:Hide() end
    parts[#parts + 1] = L["Filled in by your %s rule (click to undo)"]:format(ns.MailRuleName(rule))
    note.undo = true
    local id, key = Conflict(ns.RecipientKey(text))
    if id then
        parts[#parts + 1] = L["%s has its own rule: %s"]:format(ItemName(id), ns.ShortName(key, ns.db.chars[key]) .. LIGHT)
    end
    note.text:SetText(LIGHT .. table.concat(parts, " · ") .. "|r")
    note:Show()
end

-- Bag slots holding items a rule sends somewhere (parallel arrays, reused).
local BAGS = {}
do
    local BagIndex = Enum and Enum.BagIndex or {}
    for _, name in ipairs({ "Backpack", "Bag_1", "Bag_2", "Bag_3", "Bag_4", "ReagentBag" }) do
        if BagIndex[name] then BAGS[#BAGS + 1] = BagIndex[name] end
    end
    if #BAGS == 0 then BAGS = { 0, 1, 2, 3, 4 } end
end
local matchBag, matchSlot, matchKey, matchN = {}, {}, {}, 0
local packBag, packSlot = {}, {} -- Pack's own copy of one character's stacks
local counts, ruleOf = {}, {}
local location

-- Finds what could be packed. With `recipient`, only what goes to them.
local function FindPackable(recipient)
    matchN = 0
    wipe(counts)
    wipe(ruleOf)
    location = location or (ItemLocation and ItemLocation:CreateEmpty())
    for _, bag in ipairs(BAGS) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local id = C_Container.GetContainerItemID(bag, slot)
            if not issecretvalue(id) and id then
                local key = ruleOf[id]
                if key == nil then
                    key = ns.MailRuleFor(id) or false
                    ruleOf[id] = key
                end
                if key and (not recipient or key == recipient) then
                    local usable = true
                    if location then
                        location:SetBagAndSlot(bag, slot)
                        local locked = C_Item.IsLocked and C_Item.IsLocked(location)
                        local bound = C_Item.IsBound and C_Item.IsBound(location)
                        if issecretvalue(locked) or issecretvalue(bound) or locked or bound then usable = false end
                    end
                    if usable then
                        matchN = matchN + 1
                        matchBag[matchN], matchSlot[matchN], matchKey[matchN] = bag, slot, key
                        counts[key] = (counts[key] or 0) + 1
                    end
                end
            end
        end
    end
end

-- Who the Pack button packs for, and how many stacks (nil if nothing to pack).
function ns.MailPackPlan()
    if not (ns.MailPackOn() and ns.SendToAltOn() and ns.db.mailRules) then return nil end
    local used = ReadAttachments()
    local free = MAX_SEND - used
    if free <= 0 then return nil end
    local text = ToText()
    local recipient
    if text ~= "" then
        recipient = ns.RecipientKey(text)
        if not (recipient and ns.CanMailTo(recipient)) then return nil end
    end
    FindPackable(recipient)
    local who = recipient
    if not who then
        local best = 0
        for key, n in pairs(counts) do
            if n > best or (n == best and who and key < who) then who, best = key, n end
        end
    end
    local n = who and counts[who] or 0
    if n == 0 then return nil end
    return who, min(n, free)
end

local function UpdatePack()
    if not pack then return end
    local who, n = ns.MailPackPlan()
    pack.who = who
    if not who then return pack:Hide() end
    pack:SetText(L["Pack %d for %s"]:format(n, ns.ShortName(who, ns.db.chars[who])))
    local w = pack:GetFontString() and pack:GetFontString():GetStringWidth()
    if type(w) == "number" and not issecretvalue(w) then pack:SetWidth(max(80, w + 24)) end
    pack:Show()
end

-- Re-reads the attachments; with `fill`, fills in or clears the To box by the rules.
local function Refresh(fill)
    if busy or not SendMailNameEditBox then return end
    -- "Send mail to alts" off (Mail.lua) turns the rules off too; they're kept (owner, 2026-11-15:
    -- one setting for the mailbox, none of its own).
    if not ns.SendToAltOn() then
        filled = nil
        if note then note:Hide() pack:Hide() end
        return
    end
    busy = true
    local used = ReadAttachments()
    if used == 0 then manual = nil end
    local first = order[1]
    local target, rule
    if first then target, rule = ns.MailRuleFor(first) end
    local text = ToText()
    if fill and ns.MailFillOn() and not manual then
        if target then
            local name = ns.db.chars[target].name or target
            if text ~= name and (text == "" or text == filled or (auto and text == auto)) then
                if auto and text == auto then restore, auto = auto, nil end
                filled = name
                SendMailNameEditBox:SetText(name)
                text = name
            end
        elseif filled and text == filled then
            -- Its item is gone: back to what was there before (Posty's guess) or empty.
            text, auto, restore = restore or "", restore, nil
            filled = nil
            SendMailNameEditBox:SetText(text)
        end
    end
    if filled and text ~= filled then filled, restore = nil, nil end
    if auto and text ~= auto then auto = nil end
    UpdateNote(text, target and rule)
    UpdatePack()
    busy = false
end
ns.RefreshMailRules = Refresh

-- Undo: the note's click empties the To box we filled in, and it stays empty.
local function Undo()
    if not (note and note.undo) then return end
    manual = true
    filled, auto = nil, nil
    local back = restore or ""
    restore = nil
    SendMailNameEditBox:SetText(back)
    Refresh(false)
end

-- A full stack: as many as the item stacks to (so any item that doesn't stack). Unknown = no.
local function IsFull(bag, slot)
    if not location then return false end
    local id = C_Container.GetContainerItemID(bag, slot)
    if issecretvalue(id) or not id then return false end
    local most = C_Item.GetItemMaxStackSizeByID and C_Item.GetItemMaxStackSizeByID(id)
    location:SetBagAndSlot(bag, slot)
    local count = C_Item.GetStackCount(location)
    if issecretvalue(most) or issecretvalue(count) or type(most) ~= "number" or type(count) ~= "number" then
        return false
    end
    return count >= most
end

-- Attaches what the rules send to the Pack button's character, into empty slots, through
-- the cursor (the game's own attach), never by using an item: an item is picked up and
-- dropped on a free attachment slot, and anything left on the cursor is put back.
-- Shift-click attaches full stacks only (owner, 2026-11-15: rather than a setting or a
-- choice per rule, as it's wanted for some items now and then).
local function Pack()
    if not (SendMailFrame and SendMailFrame:IsVisible()) then return end
    local who = ns.MailPackPlan()
    if not who then return end
    local fullOnly = IsShiftKeyDown and IsShiftKeyDown()
    -- Copy the stacks first: each attach can fire MAIL_SEND_INFO_UPDATE at once, which
    -- rebuilds the match lists under this loop (owner, 2026-11-14: "Pack 5" attached 3).
    local n = 0
    for m = 1, matchN do
        if matchKey[m] == who and (not fullOnly or IsFull(matchBag[m], matchSlot[m])) then
            n = n + 1
            packBag[n], packSlot[n] = matchBag[m], matchSlot[m]
        end
    end
    if n == 0 then
        return ns.Print(L["No full stacks to pack. The game doesn't join part stacks: stack your bags first."])
    end
    if ToText() == "" then
        filled = ns.db.chars[who].name or who
        SendMailNameEditBox:SetText(filled)
    end
    local free = {}
    for i = 1, MAX_SEND do
        local has
        if HasSendMailItem then has = HasSendMailItem(i) else has = GetSendMailItem(i) ~= nil end
        if not has then free[#free + 1] = i end
    end
    local done = 0
    if CursorHasItem and CursorHasItem() then ClearCursor() end
    for m = 1, n do
        local slot = free[done + 1]
        if not slot then break end
        C_Container.PickupContainerItem(packBag[m], packSlot[m])
        if not CursorHasItem() then break end
        ClickSendMailItemButton(slot)
        if CursorHasItem() then
            ClearCursor()
            break
        end
        done = done + 1
    end
    Refresh(false)
end
ns.PackMail = Pack

local function PackTooltip(self)
    if not self.who then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(L["Pack for %s"]:format(ns.ColoredName(self.who, ns.db.chars[self.who])))
    GameTooltip:AddLine(L["Attaches the items your mail rules send to this character from your bags."], 1, 1, 1, true)
    local shown, seen = 0, {}
    for m = 1, matchN do
        if matchKey[m] == self.who then
            local id = C_Container.GetContainerItemID(matchBag[m], matchSlot[m])
            if not issecretvalue(id) and id and not seen[id] and shown < 10 then
                seen[id] = true
                shown = shown + 1
                GameTooltip:AddLine("  " .. ItemName(id), 0.75, 0.75, 0.75)
            end
        end
    end
    GameTooltip:AddLine(L["Shift-click: full stacks only."], 0.5, 0.8, 1, true)
    GameTooltip:Show()
end

-- The letter's scroll frame and its text box overlap the line above the attachments and,
-- drawn above our parts, took their clicks (owner, 2026-11-14: Pack clicked only below the
-- parchment). Put ours above both; run again at each MAIL_SHOW, as skins may restack them.
local function RaiseMailParts()
    if not note then return end
    local level = SendMailFrame:GetFrameLevel() or 0
    for _, f in ipairs({ SendMailScrollFrame or false, SendMailBodyEditBox or false }) do
        local l = f and f:GetFrameLevel()
        if l and l > level then level = l end
    end
    note:SetFrameLevel(level + 5)
    pack:SetFrameLevel(level + 5)
end

local function CreateMailParts()
    if note or not (SendMailFrame and SendMailNameEditBox) then return end
    local bar = SendMailHorizontalBarLeft2 -- the line above the attachments (Blizzard_MailFrame)
    note = CreateFrame("Button", nil, SendMailFrame)
    note:SetSize(200, 16)
    note.text = note:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    note.text:SetPoint("LEFT", note, "LEFT", 0, 0)
    note.text:SetPoint("RIGHT", note, "RIGHT", 0, 0)
    note.text:SetJustifyH("LEFT")
    if note.text.SetWordWrap then note.text:SetWordWrap(false) end
    ns.SkinText(note.text)
    note:SetScript("OnClick", Undo)
    note:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Mail rules"])
        GameTooltip:AddLine(note.text:GetText() or "", 1, 1, 1, true)
        if self.undo then GameTooltip:AddLine(L["Click to empty the To box."], 0.5, 0.8, 1, true) end
        GameTooltip:Show()
    end)
    note:SetScript("OnLeave", function() GameTooltip:Hide() end)
    note.mailNote = true
    note:Hide()

    pack = CreateFrame("Button", nil, SendMailFrame, "UIPanelButtonTemplate")
    pack:SetSize(110, 20)
    pack:SetScript("OnClick", Pack)
    pack:SetScript("OnEnter", PackTooltip)
    pack:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pack.mailPack = true
    ns.SkinButton(pack)
    pack:Hide()

    if bar then
        note:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 12, 1)
        pack:SetPoint("BOTTOMRIGHT", bar, "TOPLEFT", 323, 1)
    else
        note:SetPoint("BOTTOMLEFT", SendMailFrame, "BOTTOMLEFT", 16, 150)
        pack:SetPoint("BOTTOMRIGHT", SendMailFrame, "BOTTOMRIGHT", -14, 150)
    end
    note:SetPoint("RIGHT", pack, "LEFT", -6, 0)

    -- Typing in the To box (or picking from its autocomplete) is the player's choice.
    SendMailNameEditBox:HookScript("OnTextChanged", function(_, userInput)
        if userInput then manual, auto, restore = true, nil, nil end
        Refresh(false)
    end)
    -- Switching to Send Mail, and Reply, which switches too (see CatchAutoFill).
    if type(MailFrameTab_OnClick) == "function" then hooksecurefunc("MailFrameTab_OnClick", CatchAutoFill) end
    if type(OpenMail_Reply) == "function" then hooksecurefunc("OpenMail_Reply", function() replying = true end) end
end

---------------------------------------------------------------------------
-- The arrow's menu (Mail.lua's AltsMenu calls this after the characters)
---------------------------------------------------------------------------
local function RuleCheckbox(root, text, rule, recipient, example)
    local other = TargetOf(rule)
    if other and other ~= recipient then
        text = text .. GREY .. " (" .. L["now %s"]:format(ns.db.chars[other].name or other) .. ")|r"
    end
    root:CreateCheckbox(text, function() return TargetOf(rule) == recipient end, function()
        ns.SetMailRule(rule, recipient, TargetOf(rule) ~= recipient, example)
    end)
end

function ns.AddMailRuleMenu(root)
    ReadAttachments()
    local chars = ns.db.chars
    local first = order[1]
    -- Suggestions while the first item has no rule: who uses it in their known recipes.
    if first and not ns.MailRuleFor(first) then
        local list = ns.MailSuggestions(first)
        if #list > 0 then
            local rule = ns.SuggestedRule(first)
            local name, category = ns.MailRuleName(rule)
            root:CreateDivider()
            root:CreateTitle(L["Suggested rules"])
            for i = 1, min(2, #list) do
                local s = list[i]
                local who = ns.ShortName(s.key, chars[s.key])
                local text = (category and L["Always send all %s to %s"] or L["Always send %s to %s"]):format(name, who)
                    .. LIGHT .. " · " .. (s.n == 1 and L["uses %s in %d known recipe"] or L["uses %s in %d known recipes"]):format(ItemName(first), s.n) .. "|r"
                root:CreateButton(text, function()
                    ns.SetMailRule(rule, s.key, true, first)
                    Refresh(true)
                end)
            end
        end
    end
    -- Remember: rules for what's attached, for the character in the To box.
    local text = ToText()
    local recipient = text ~= "" and ns.RecipientKey(text)
    if first and recipient and ns.CanMailTo(recipient) then
        root:CreateDivider()
        root:CreateTitle(L["Remember for %s"]:format(ns.ShortName(recipient, chars[recipient])))
        local seen = {}
        for _, id in ipairs(order) do
            RuleCheckbox(root, L["Always send %s here"]:format(ItemName(id)), ItemRule(id), recipient, id)
            local rule = CategoryRule(id)
            if rule and not seen[rule] then
                seen[rule] = true
                RuleCheckbox(root, L["Always send all %s here"]:format((ns.MailRuleName(rule))), rule, recipient, id)
            end
        end
    end
    root:CreateDivider()
    root:CreateButton(L["Mail rules..."], function() ns.ToggleMailRules(true) end)
end

---------------------------------------------------------------------------
-- The Mail rules window
---------------------------------------------------------------------------
local win
local rows = {}
local offset, tries = 0, 0
local ROW_H, MAX_ROWS, WIDTH = 20, 12, 360
local FillWindow

local function MakeRow(i)
    local row = CreateFrame("Button", nil, win)
    row:SetSize(WIDTH - 32, ROW_H)
    row:SetPoint("TOPLEFT", win, "TOPLEFT", 16, -34 - (i - 1) * ROW_H)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.label:SetWidth(150)
    row.label:SetJustifyH("LEFT")
    if row.label.SetWordWrap then row.label:SetWordWrap(false) end
    ns.SkinText(row.label)
    row.who = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.who:SetPoint("LEFT", row.label, "RIGHT", 8, 0)
    row.who:SetWidth(120)
    row.who:SetJustifyH("LEFT")
    if row.who.SetWordWrap then row.who:SetWordWrap(false) end
    ns.SkinText(row.who)
    row.remove = CreateFrame("Button", nil, row)
    row.remove:SetSize(16, 16)
    row.remove:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.remove:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
    row.remove:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    row.remove:SetScript("OnClick", function() ns.SetMailRule(row.rule, row.key, false) end)
    row.remove:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Remove this rule"])
        GameTooltip:Show()
    end)
    row.remove:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local id = tonumber(self.rule:match("^i:(%d+)$"))
        if id and GameTooltip.SetItemByID then
            GameTooltip:SetItemByID(id)
        else
            GameTooltip:AddLine(self.label:GetText() or "")
        end
        local c = ns.db.chars[self.key]
        GameTooltip:AddLine(L["Goes to %s"]:format(c and ns.ColoredName(self.key, c) or self.key), 1, 1, 1)
        if not ns.CanMailTo(self.key) then
            GameTooltip:AddLine(L["Not used on this character: you can't mail them from here."], 0.6, 0.6, 0.6, true)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = row
    return row
end

FillWindow = function()
    if not win then return end
    local list, missing = ns.MailRuleList()
    offset = max(0, min(offset, #list - MAX_ROWS))
    local chars = ns.db.chars
    local shown = 0
    for i = 1, MAX_ROWS do
        local e = list[i + offset]
        local row = rows[i]
        if e then
            row = row or MakeRow(i)
            row.rule, row.key = e.rule, e.key
            local id = tonumber(e.rule:match("^i:(%d+)$")) or (e.example ~= 0 and e.example) or nil
            row.icon:SetTexture(id and C_Item.GetItemIconByID(id) or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.label:SetText(e.label)
            local c = chars[e.key]
            local name = c and ns.ColoredName(e.key, c) or (GREY .. e.key .. "|r")
            if c and not ns.CanMailTo(e.key) then name = GREY .. (c.name or e.key) .. "|r" end
            row.who:SetText(name)
            row:Show()
            shown = shown + 1
        elseif row then
            row:Hide()
        end
    end
    win.empty:SetShown(#list == 0)
    win.more:SetShown(#list > MAX_ROWS)
    if #list > MAX_ROWS then
        win.more:SetText(L["%d-%d of %d (scroll for more)"]:format(offset + 1, offset + shown, #list))
    end
    win.fill:SetChecked(ns.MailFillOn())
    win.pack:SetChecked(ns.MailPackOn())
    local off = not ns.SendToAltOn()
    win.off:SetShown(off)
    local body = max(shown, 4) * ROW_H + (#list > MAX_ROWS and 18 or 0)
    win:SetHeight(34 + body + 70 + (off and 30 or 0))
    -- Item names still loading: look again shortly (a few times at most).
    if missing and tries < 5 and C_Timer then
        tries = tries + 1
        C_Timer.After(1, function() if win:IsShown() then FillWindow() end end)
    elseif not missing then
        tries = 0
    end
end

-- Opens beside the mailbox when it's open, else in the middle (or where the player put it);
-- past Posty Forever's Quick Attach buttons, a column against the mailbox's right edge.
local function BesideMail(f)
    f:ClearAllPoints()
    if MailFrame and MailFrame:IsShown() then
        local qa, x = _G.Postal_QuickAttachButton1, 12
        if qa and qa:IsVisible() then
            local w = qa:GetWidth()
            if type(w) == "number" and not issecretvalue(w) then x = x + w end
        end
        f:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", x, 0)
    else
        f:SetPoint("CENTER")
    end
end

local function Check(f, y, text, tip, onClick)
    local box = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    box:SetSize(26, 26)
    box:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, y)
    box:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
    box:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(text)
        GameTooltip:AddLine(tip, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    box:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ns.SkinCheck(box)
    box.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    box.label:SetPoint("LEFT", box, "RIGHT", 4, 0)
    box.label:SetText(text)
    ns.SkinText(box.label)
    return box
end

local function CreateWindow()
    local f = ns.NewWindow("AltsForeverMailRulesFrame")
    win = f
    f.rows = rows
    f:SetSize(WIDTH, 200)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:HookScript("OnShow", f.Raise)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    ns.TrackWindow(f, "mailrules", false, BesideMail)
    f:SetClampedToScreen(true)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        offset = max(0, offset - delta * 3)
        FillWindow()
    end)
    local title = f.TitleText or f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if not f.TitleText then title:SetPoint("TOP", 0, -6) end
    title:SetText(L["Mail rules"])
    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.empty:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -38)
    f.empty:SetWidth(WIDTH - 36)
    f.empty:SetJustifyH("LEFT")
    f.empty:SetText(L["No mail rules yet.\n\nAt the mailbox, attach an item, pick one of your characters from the arrow beside the To box, then open the arrow again and tick what they should always get."])
    ns.SkinText(f.empty)
    f.more = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.more:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -34 - MAX_ROWS * ROW_H - 2)
    ns.SkinText(f.more)
    f.fill = Check(f, 36, L["Fill in the To box from these rules"],
        L["When the first item you attach has a rule, its character goes in the To box, unless you've typed or picked a name."], ns.SetMailFill)
    f.pack = Check(f, 10, L["Show the Pack button at the mailbox"],
        L["A button above the attachments that attaches from your bags what your rules send to that character."], ns.SetMailPack)
    -- "Send mail to alts" off stops the rules at the mailbox (Refresh): say so, as the ticks stay.
    f.off = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.off:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 18, 66)
    f.off:SetWidth(WIDTH - 36)
    f.off:SetJustifyH("LEFT")
    f.off:SetTextColor(0.6, 0.6, 0.6)
    f.off:SetText(L["Send mail to alts is off in the options, so these rules aren't used at the mailbox."])
    ns.SkinText(f.off)
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "AltsForeverMailRulesFrame" end
    ns.SkinWindow(f)
    f:Hide()
    ns.GamepadWindow(f)
    ns.ScaleWindow(f)
end

-- Toggles the window; with `open`, only opens it (and raises it if already open).
function ns.ToggleMailRules(open)
    if not win then CreateWindow() end
    if win:IsShown() then
        if open then return win:Raise() end
        return win:Hide()
    end
    offset, tries = 0, 0
    FillWindow()
    ns.PlaceWindow(win)
    win:Show()
end

Changed = function()
    if win and win:IsShown() then FillWindow() end
    if SendMailFrame and SendMailFrame:IsVisible() then Refresh(true) end
end
ns.MailRulesChanged = Changed

function ns.StartMailRules()
    ns.On("MAIL_SHOW", function()
        wipe(order)
        wipe(inOrder)
        filled, manual, auto, restore, replying = nil, nil, nil, nil, nil
        CreateMailParts()
        RaiseMailParts()
        Refresh(true)
    end)
    ns.On("MAIL_SEND_INFO_UPDATE", function() Refresh(true) end)
    ns.On("MAIL_SEND_SUCCESS", function()
        filled, manual, auto, restore = nil, nil, nil, nil
        CatchAutoFill()
    end)
    ns.On("BAG_UPDATE_DELAYED", function()
        if pack and SendMailFrame and SendMailFrame:IsVisible() then UpdatePack() end
    end)
end
