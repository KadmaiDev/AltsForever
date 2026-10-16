-- Alts Forever search: every item any of your characters has, or can craft, by name
-- (the owner's idea, 2026-10-16, after trying EasyFind and Forever Spotlight; theirs search
-- the whole game, ours your characters). One row per item: how many, who has them, who can
-- make it. Enter opens the bags window on the character who has it (you first, else the
-- most), with it lit up, and the search stays open beside it; Shift+Enter links it in chat. Only item IDs are stored, so names
-- are looked up when the window opens and let go when it closes:
-- nothing is kept or runs while it's shut.
local _, ns = ...
if ns.disabled then return end -- another copy of Alts Forever is running (Core.lua)
local L = ns.L

local C_Item = C_Item
local issecretvalue = issecretvalue or function() return false end
local floor, min, max = math.floor, math.min, math.max
local sort, wipe = table.sort, wipe

local ROWS, ROW, WIDTH = 8, 36, 480
local MAX_MATCHES = 50
local SHOWN_HOLDERS = 3
local LOCS = { "bags", "bank", "mail", "equip" }
local GREY = "|cff9d9d9d"
local SEP = " · "

local frame, box
local rows = {}
local pool, names     -- every item's lower-case name, and its name, while the window is shown
local matches = {}
local selected, offset = 1, 0
local retried
-- With the bags window open, the search works on it (owner, 2026-10-16): only the character
-- it shows (scopeKey; "All characters" widens it), docked beside it, and the selected item
-- lit there as you go (previewed; with nothing selected, back to the last pick: savedLit,
-- savedView). Closing the search clears what's lit. The last search is kept for the next
-- opening (this session only).
local scopeKey, savedLit, savedView, previewed, docked
local lastText = ""
local ApplyScope, Dock

local function ItemName(id)
    local name = C_Item.GetItemNameByID(id)
    if type(name) == "string" and name ~= "" and not issecretvalue(name) then return name end
end

---------------------------------------------------------------------------
-- What there is to find
---------------------------------------------------------------------------
-- Every item ID on the characters tooltips show (your ruleset and faction, unless "Show
-- other rulesets and factions" is on): owned anywhere, or made by a recipe they know.
-- Returns true if some names are still loading (they've been asked for).
local function Build()
    local seen, loading = {}, false
    pool, names = {}, {}
    for _, c in pairs(ns.db.chars) do
        if not ns.Hidden(c) then
            for i = 1, #LOCS do
                local t = c[LOCS[i]]
                if t then for id in pairs(t) do seen[id] = true end end
            end
            for _, items in pairs(c.crafts or {}) do
                for id in pairs(items) do
                    if type(id) == "number" then seen[id] = true end
                end
            end
        end
    end
    for id in pairs(seen) do
        local name = ItemName(id)
        if name then
            names[id] = name
            pool[#pool + 1] = { id = id, low = name:lower() }
        else
            loading = true
            if C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        end
    end
    return loading
end

local function ByCount(a, b)
    if a.n ~= b.n then return a.n > b.n end
    return a.key < b.key
end

local function YouFirst(a, b)
    if (a.key == ns.charKey) ~= (b.key == ns.charKey) then return a.key == ns.charKey end
    return a.key < b.key
end

-- Who has the item, most first, and how many in all.
local function Holders(id)
    local list, total = {}, 0
    for key, c in pairs(ns.db.chars) do
        if not ns.Hidden(c) then
            local n = 0
            for i = 1, #LOCS do
                local t = c[LOCS[i]]
                n = n + (t and t[id] or 0)
            end
            if n > 0 then
                list[#list + 1] = { key = key, c = c, n = n }
                total = total + n
            end
        end
    end
    sort(list, ByCount)
    return list, total
end

-- Who can make it, and with which profession (the one whose entry is the recipe's).
local function Crafters(id)
    local list = {}
    for key, c in pairs(ns.db.chars) do
        local crafts = not ns.Hidden(c) and c.crafts
        if crafts then
            for prof, items in pairs(crafts) do
                if items[id] and ns.CraftProf(crafts, prof, id) == prof then
                    list[#list + 1] = { key = key, c = c, prof = prof }
                    break
                end
            end
        end
    end
    sort(list, YouFirst)
    return list
end

---------------------------------------------------------------------------
-- Matching
---------------------------------------------------------------------------
-- How well a name matches: 0 the whole name, 1 its start, 2 the start of a later word,
-- 3 anywhere, 4 every word typed somewhere in it; nil not at all.
local function Rank(low, text, words)
    if low == text then return 0 end
    local s = low:find(text, 1, true)
    if s == 1 then return 1 end
    if s then return low:sub(s - 1, s - 1):find("[%s%-%(:']") and 2 or 3 end
    if #words < 2 then return nil end
    for i = 1, #words do
        if not low:find(words[i], 1, true) then return nil end
    end
    return 4
end

local function Better(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    if a.total ~= b.total then return a.total > b.total end
    return a.low < b.low
end

-- "@owned linen", "@mine linen", "@craft sword": a word after @ narrows it to what any of
-- your characters has, what the one you're on has, or what one can make (@mine: the owner,
-- 2026-10-16, read @owned as "mine"). Any start of the word will do; the same words in every
-- language, as the hint says.
local FILTERS = { "owned", "mine", "craft" }
local filter -- the one in use, for the rows

local function Filter(word)
    if word == "" then return nil end
    for _, f in ipairs(FILTERS) do
        if f:find(word, 1, true) == 1 then return f end
    end
end

function ns.SearchMatches(text)
    wipe(matches)
    selected, offset = 1, 0
    text = (text or ""):lower():match("^%s*(.-)%s*$")
    filter = nil
    local word, rest = text:match("^@(%S*)%s*(.*)$")
    if word then
        filter = Filter(word)
        text = rest
    end
    -- What can be made isn't in one character's bags: @craft searches everyone.
    if filter == "craft" and scopeKey then
        scopeKey = nil
        if ApplyScope then ApplyScope() end
    end
    local scoped = scopeKey and ns.db.chars[scopeKey]
    if text == "" or not pool then return matches end
    local words = {}
    for w in text:gmatch("%S+") do words[#words + 1] = w end
    for _, e in ipairs(pool) do
        local rank = Rank(e.low, text, words)
        if rank then
            e.rank = rank
            e.holders, e.total = Holders(e.id)
            e.crafters = Crafters(e.id)
            -- How many the character you're on has; with @mine they come first, and the
            -- row's number is theirs.
            e.mine = 0
            for i, h in ipairs(e.holders) do
                if h.key == ns.charKey then
                    e.mine = h.n
                    if filter == "mine" then table.insert(e.holders, 1, table.remove(e.holders, i)) end
                    break
                end
            end
            e.count = filter == "mine" and e.mine or e.total
            -- One character's bags and bank: theirs only, them first, the number theirs.
            local here = 0
            if scoped then
                here = (scoped.bags and scoped.bags[e.id] or 0) + (scoped.bank and scoped.bank[e.id] or 0)
                e.count = here
                for i, h in ipairs(e.holders) do
                    if h.key == scopeKey then
                        table.insert(e.holders, 1, table.remove(e.holders, i))
                        break
                    end
                end
            end
            if (filter ~= "owned" or e.total > 0) and (filter ~= "mine" or e.mine > 0)
                and (filter ~= "craft" or #e.crafters > 0) and (not scoped or here > 0) then
                matches[#matches + 1] = e
            end
        end
    end
    sort(matches, Better)
    for i = #matches, MAX_MATCHES + 1, -1 do matches[i] = nil end
    return matches
end

-- The row's second line: who has how many, then who can make it. The total sits apart,
-- at the end of the name's line (owner, 2026-10-16: "1 Sabine 1" read as two numbers
-- around her name).
function ns.SearchDetail(e)
    local parts = {}
    local crafting -- with @craft, who can make it comes first, so it's never cut off
    if #e.crafters > 0 then
        local who = {}
        for i, cr in ipairs(e.crafters) do
            if i > SHOWN_HOLDERS then
                who[#who + 1] = L["+%d more"]:format(#e.crafters - SHOWN_HOLDERS)
                break
            end
            who[i] = ns.ListShortName(cr.key, cr.c) .. GREY .. " (" .. cr.prof .. ")|r"
        end
        crafting = GREY .. L["can craft:"] .. "|r " .. table.concat(who, ", ")
    end
    if crafting and filter == "craft" then parts[1] = crafting end
    if e.total > 0 then
        local who = {}
        for i = 1, min(#e.holders, SHOWN_HOLDERS) do
            local h = e.holders[i]
            who[i] = ns.ListShortName(h.key, h.c) .. " " .. h.n
        end
        if #e.holders > SHOWN_HOLDERS then who[#who + 1] = L["+%d more"]:format(#e.holders - SHOWN_HOLDERS) end
        parts[#parts + 1] = table.concat(who, ", ")
    else
        parts[#parts + 1] = GREY .. L["none owned"] .. "|r"
    end
    if crafting and filter ~= "craft" then parts[#parts + 1] = crafting end
    return table.concat(parts, GREY .. SEP .. "|r")
end

---------------------------------------------------------------------------
-- Picking one
---------------------------------------------------------------------------
local function Link(e)
    local _, link = C_Item.GetItemInfo(e.id)
    if type(link) ~= "string" or issecretvalue(link) then return end
    -- Into the chat box being typed in; if none is open, open one with it.
    if not (ChatEdit_InsertLink and ChatEdit_InsertLink(link)) and ChatFrame_OpenChat then ChatFrame_OpenChat(link) end
end

-- Enter or a click: the bags or bank of whoever has it (you first, else the most), with it
-- lit up; worn, their gear; only in the mail, said so. Nobody has it: link it.
-- The search stays open beside the bags window (owner, 2026-10-16), so the next one is a
-- click away; what's lit now is what closing it goes back to.
local function Kept()
    savedLit, savedView = ns.BagsState()
    previewed = savedLit
    box:SetFocus()
end

local function Open(key, view, id)
    local opening = not ns.BagsShownKey()
    ns.ShowBags(key, view, id)
    if opening then Dock() end
    Kept()
end

local function Num(x) return type(x) == "number" and not issecretvalue(x) and x end

-- Their gear: the panel opens on the far side of the search from the bags window, and the
-- search stays open (owner, 2026-10-16).
local function Gear(key)
    local side = "RIGHT"
    local bags = ns.BagsWindow()
    if docked and bags and bags:IsShown() then
        local left, bagsLeft = Num(frame:GetLeft()), Num(bags:GetLeft())
        if left and bagsLeft and left < bagsLeft then side = "LEFT" end
    end
    ns.ShowGear(key, frame, side)
    box:SetFocus()
end

local function Pick(e, link)
    if not e then return end
    if link then return Link(e) end
    -- The bags window open on someone who has it: lit up there, where you're looking.
    if ns.BagsShownKey() and ns.BagsPreview(e.id) then return Kept() end
    local h = e.holders[1]
    for _, x in ipairs(e.holders) do
        if x.key == ns.charKey then
            h = x
            break
        end
    end
    if not h then return Link(e) end
    local c = h.c
    if c.bags and c.bags[e.id] then
        Open(h.key, "bags", e.id)
    elseif c.bank and c.bank[e.id] then
        Open(h.key, "bank", e.id)
    elseif c.equip and c.equip[e.id] then
        Gear(h.key)
    else
        ns.Print(L["%s has it in the mail."]:format(ns.ListName(h.key, c)))
    end
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local Render

-- The item's own tooltip, with everything Alts Forever adds to it: who has it where,
-- Can craft, upgrades.
local function RowTip(row)
    if not row.entry then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(row.entry.id)
    GameTooltip:Show()
end

-- The mouse on a row selects what it shows: its place in the list, not on screen (the
-- list may have scrolled with the arrow keys; the owner saw the wrong one selected).
local function RowEnter(row)
    selected = offset + row.index
    Render()
    RowTip(row)
end

-- A tooltip open on one of the rows follows the selection when the keys move it.
local function FollowTip()
    local owner = GameTooltip:IsShown() and GameTooltip:GetOwner()
    if not (owner and owner.index and rows[owner.index] == owner) then return end
    local row = rows[selected - offset]
    if row and row.entry then RowTip(row) else GameTooltip:Hide() end
end

-- Right-click: every character who has it and where, to open exactly that one.
local function HolderMenu(row)
    local e = row.entry
    if not (e and MenuUtil and MenuUtil.CreateContextMenu) then return end
    local id, name = e.id, names[e.id] or ""
    MenuUtil.CreateContextMenu(row, function(_, root)
        root:CreateTitle(name)
        for _, h in ipairs(e.holders) do
            local key, c = h.key, h.c
            local who = ns.ListName(key, c)
            local inBags, inBank = c.bags and c.bags[id] or 0, c.bank and c.bank[id] or 0
            local inMail, worn = c.mail and c.mail[id] or 0, c.equip and c.equip[id] or 0
            if inBags > 0 then
                root:CreateButton(L["%s: %d in bags"]:format(who, inBags), function() Open(key, "bags", id) end)
            end
            if inBank > 0 then
                root:CreateButton(L["%s: %d in the bank"]:format(who, inBank), function() Open(key, "bank", id) end)
            end
            if worn > 0 then
                root:CreateButton(L["%s: wearing it"]:format(who), function() Gear(key) end)
            end
            if inMail > 0 then
                -- The bags window doesn't show mail: said, not opened.
                root:CreateButton(L["%s: %d in the mail"]:format(who, inMail)):SetEnabled(false)
            end
        end
        root:CreateButton(L["Link in chat"], function() Link(e) end)
    end)
end

local function RowClick(row, button)
    if button == "RightButton" then return HolderMenu(row) end
    Pick(row.entry, IsModifiedClick and IsModifiedClick())
end

local function Row(i)
    local row = CreateFrame("Button", nil, frame)
    row:SetHeight(ROW)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -64 - (i - 1) * ROW)
    row:SetPoint("RIGHT", frame, "RIGHT", -30, 0)
    row.lit = row:CreateTexture(nil, "BACKGROUND")
    row.lit:SetAllPoints()
    row.lit:SetColorTexture(1, 1, 1, 0.1)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.05)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(28, 28)
    row.icon:SetPoint("LEFT", 4, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    -- How many in all, at the right of the name's line.
    row.total = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.total:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -3)
    row.total:SetJustifyH("RIGHT")
    ns.SkinText(row.total)
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -1)
    row.name:SetPoint("RIGHT", row.total, "LEFT", -8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.detail:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 1)
    row.detail:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetWordWrap(false)
    ns.SkinText(row.name)
    ns.SkinText(row.detail)
    row.index = i
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", RowClick)
    rows[i] = row
    return row
end

local function QualityColor(id)
    local q = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    return c and c.r or 1, c and c.g or 1, c and c.b or 1
end

Render = function()
    local n = #matches
    selected = max(1, min(selected, n))
    if selected <= offset then offset = selected - 1 end
    if selected > offset + ROWS then offset = selected - ROWS end
    offset = max(0, min(offset, n - ROWS))
    for i = 1, ROWS do
        local row, e = rows[i], matches[offset + i]
        row.entry = e
        if e then
            row.icon:SetTexture(C_Item.GetItemIconByID(e.id) or 134400)
            row.name:SetText(names[e.id] or "")
            row.name:SetTextColor(QualityColor(e.id))
            row.total:SetText(e.count > 0 and e.count or "")
            row.detail:SetText(ns.SearchDetail(e))
            row.lit:SetShown(offset + i == selected)
            row:Show()
        else
            row:Hide()
        end
    end
    frame.up:SetEnabled(offset > 0)
    frame.down:SetEnabled(offset + ROWS < n)
    local text = box:GetText() or ""
    local typed = text:match("^%s*@?%S*%s*(.-)%s*$")
    local empty = text:match("^%s*$") or (text:match("^%s*@") and typed == "")
    frame.hint:SetShown(empty and true or false)
    if empty then
        frame.status:SetText("")
    elseif n == 0 then
        frame.status:SetText(GREY .. L["Nothing matching '%s'."]:format(text) .. "|r")
    elseif ns.BagsShownKey() then
        frame.status:SetText(GREY .. L["Enter: keep it lit · Escape: close and show every slot"] .. "|r")
    else
        frame.status:SetText(GREY .. L["Enter: open their bags · Right-click: choose whose · Shift+Enter: link in chat"] .. "|r")
    end
    -- The selected item lit in the open bags window, in place ("not here" if the character it
    -- shows hasn't got it); with nothing selected, the bags as they were.
    if ns.BagsShownKey() and frame:IsShown() then
        local id = matches[selected] and matches[selected].id
        if id ~= previewed then
            previewed = id
            if id then ns.BagsPreview(id) else ns.BagsRestore(savedLit, savedView) end
        end
    end
end

local function Update()
    ns.SearchMatches(box:GetText())
    Render()
end

local function Move(by)
    if #matches == 0 then return end
    selected = (selected - 1 + by) % #matches + 1
    Render()
    FollowTip()
end

local function Scroll(by)
    offset = max(0, min(offset + by, #matches - ROWS))
    selected = max(offset + 1, min(selected, offset + ROWS))
    -- Scrolled under the mouse (the wheel): the row it's on now shows another item, so that
    -- one is selected and its tooltip shown.
    local owner = GameTooltip:IsShown() and GameTooltip:GetOwner()
    if owner and owner.index and rows[owner.index] == owner and matches[offset + owner.index] then
        selected = offset + owner.index
        Render()
        return RowTip(owner)
    end
    Render()
end

local function CreateWindow()
    local ok, f = pcall(CreateFrame, "Frame", "AltsForeverSearchFrame", UIParent, "BasicFrameTemplateWithInset")
    if not ok then f = CreateFrame("Frame", "AltsForeverSearchFrame", UIParent, "BackdropTemplate") end
    frame = f
    f:SetSize(WIDTH, 64 + ROWS * ROW + 34)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
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
    f.title:SetText(L["Search your characters"])

    local okBox, b = pcall(CreateFrame, "EditBox", "AltsForeverSearchBox", f, "InputBoxTemplate")
    if not okBox then b = CreateFrame("EditBox", "AltsForeverSearchBox", f) end
    box = b
    b:SetHeight(24)
    b:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -32)
    b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -32)
    b:SetAutoFocus(false)
    b:SetFontObject("GameFontHighlight")
    b:SetScript("OnTextChanged", Update)
    b:SetScript("OnEscapePressed", function() f:Hide() end)
    b:SetScript("OnEnterPressed", function() Pick(matches[selected], IsShiftKeyDown and IsShiftKeyDown()) end)
    b:SetScript("OnArrowPressed", function(_, key)
        if key == "UP" then Move(-1) elseif key == "DOWN" then Move(1) end
    end)
    b:SetScript("OnTabPressed", function() Move(IsShiftKeyDown and IsShiftKeyDown() and -1 or 1) end)
    ns.SkinEditBox(b)

    -- Searching one character's bags: back to all your characters.
    local widen = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    widen:SetSize(112, 22)
    widen:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -33)
    widen:SetText(L["All characters"])
    widen:SetScript("OnClick", function()
        scopeKey = nil
        ApplyScope()
        Update()
        box:SetFocus()
    end)
    widen:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Search all your characters instead."])
        GameTooltip:Show()
    end)
    widen:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ns.SkinButton(widen)
    widen:Hide()
    f.widen = widen

    for i = 1, ROWS do Row(i) end
    -- Paging arrows (a controller can't turn the mouse wheel), and the wheel.
    f.up = ns.PageButton(f, true, function() Scroll(-ROWS) end)
    f.up:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -66)
    f.down = ns.PageButton(f, false, function() Scroll(ROWS) end)
    f.down:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -64 - ROWS * ROW + 20)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta) Scroll(-delta) end)

    -- Before anything's typed: what it searches, and the three words that narrow it.
    local function Word(word, what) return "|cffffd100" .. word .. "|r  " .. what end
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.hint:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -76)
    f.hint:SetPoint("RIGHT", f, "RIGHT", -36, 0)
    f.hint:SetJustifyH("LEFT")
    f.hint:SetSpacing(4)
    f.hint:SetText(L["Type part of an item's name to find everything your characters have or can craft."] .. "\n\n"
        .. L["Start with one of these to narrow it:"] .. "\n"
        .. Word("@owned", L["any of your characters has it"]) .. "\n"
        .. Word("@mine", L["the character you're on has it"]) .. "\n"
        .. Word("@craft", L["one of your characters can make it"]) .. "\n\n"
        .. GREY .. L["For example: %s"]:format("@craft linen") .. "|r")
    ns.SkinText(f.hint)

    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.status:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 12)
    f.status:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 12)
    f.status:SetJustifyH("LEFT")
    ns.SkinText(f.status)

    ns.SkinWindow(f)
    f:SetScript("OnShow", function(self)
        self:Raise()
        retried = false
        if Build() and C_Timer and C_Timer.After then
            -- Some names were still loading: once more in a second, if still open.
            C_Timer.After(1, function()
                if frame:IsShown() and not retried then
                    retried = true
                    Build()
                    Update()
                end
            end)
        end
        Update()
        -- A frame later: focused at once, the key that opened it (a binding) would be typed in.
        -- The last search is selected, so typing replaces it.
        local function Focus()
            box:SetFocus()
            box:HighlightText()
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() if frame:IsShown() then Focus() end end)
        else
            Focus()
        end
    end)
    f:SetScript("OnHide", function()
        lastText = box:GetText() or ""
        -- Closing the search ends it in the bags window too: nothing lit, every slot back
        -- (owner, 2026-10-16), on the bags or bank of the last pick (not one only hovered).
        if ns.BagsHighlight() then ns.BagsRestore(nil, savedView) end
        previewed = nil
        ns.BagsHold(false)
        box:ClearFocus()
        pool, names = nil, nil
        wipe(matches)
        for i = 1, ROWS do rows[i].entry = nil end
        GameTooltip:Hide()
    end)
    -- Escape closes it, like Blizzard's own windows.
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "AltsForeverSearchFrame" end
    f:Hide()
    ns.GamepadWindow(f)
    ns.ScaleWindow(f)
end

-- One character's bags (the bags window is open on them), or all your characters.
ApplyScope = function()
    local c = scopeKey and ns.db.chars[scopeKey]
    if c then
        frame.title:SetText(L["Search %s"]:format(ns.ColoredName(scopeKey, c)))
        box:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -136, -32)
        frame.widen:Show()
    else
        scopeKey = nil
        frame.title:SetText(L["Search your characters"])
        box:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -32)
        frame.widen:Hide()
    end
end

-- Beside the bags window when it's open (right of it if there's room, else left), so
-- neither covers the other; otherwise where it always opens.
Dock = function()
    local bags = ns.BagsWindow()
    if bags and bags:IsShown() then
        frame:ClearAllPoints()
        local right = bags:GetRight()
        if type(right) == "number" and not issecretvalue(right)
            and right + 4 + WIDTH > UIParent:GetWidth() / ns.WindowScale() then
            frame:SetPoint("TOPRIGHT", bags, "TOPLEFT", -4, 0)
        else
            frame:SetPoint("TOPLEFT", bags, "TOPRIGHT", 4, 0)
        end
        docked = true
        ns.BagsHold(true)
    elseif docked then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        docked = false
    end
end

-- Opens the search (with some text to start from; else the last search), or closes it if
-- open and none is given.
function ns.ToggleSearch(text)
    if not frame then CreateWindow() end
    text = text and text:match("^%s*(.-)%s*$") or ""
    if frame:IsShown() and text == "" then return frame:Hide() end
    if not frame:IsShown() then
        scopeKey = ns.BagsShownKey()
        savedLit, savedView = ns.BagsState()
        previewed = savedLit
        ApplyScope()
        Dock()
        if text == "" then text = lastText end
    end
    box:SetText(text)
    if frame:IsShown() then Update() else frame:Show() end
end

function ns.SearchWindow() return frame end
