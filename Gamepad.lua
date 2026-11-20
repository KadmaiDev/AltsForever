-- Alts Forever and WoW: Forever's Gamepad UI (Options > Gameplay > Gamepad (Alpha)). Blizzard's
-- navigator (SmartNavigation) moves focus with the D-pad, A clicks the focused button, B
-- closes, LT/RT switch between open windows, and focusing a widget runs its OnEnter, so our
-- tooltips show. This joins our windows to it. All of it is undocumented Blizzard internals
-- of an Alpha feature, so every name is checked before use; for mouse and keyboard players
-- nothing here runs beyond a field or two set on our own frames.
local _, ns = ...
if ns.disabled then return end -- another copy of Alts Forever is running (Core.lua)
local L = ns.L

local pcall, type = pcall, type

-- True while the player has the Gamepad UI on (not merely a controller connected).
function ns.GamepadUI()
    local style, types = C_InputInterfaceStyle, Enum and Enum.InputDeviceInterfaceType
    if not (style and style.GetCurrentStyle and types and types.Gamepad) then return false end
    return style.GetCurrentStyle() == types.Gamepad
end

local function Manager()
    local mode = _G.GamepadMode
    return type(mode) == "table" and mode.FrameControlsManager or nil
end

local function Report(ok, err)
    if not ok and geterrorhandler then geterrorhandler()(err) end
end

-- A window of ours tells Blizzard's focus manager when it opens and closes (as Blizzard's
-- own floating windows do), so focus jumps into it and B closes it. Only out of combat:
-- focusing a window activates Blizzard's button bindings, which our code can't do then.
local function Shown(self)
    local fcm = Manager()
    if not (fcm and fcm.FrameShown and ns.GamepadUI()) or InCombatLockdown() then return end
    self.gamepadTracked = true
    Report(pcall(fcm.FrameShown, fcm, self))
end

local function Hidden(self)
    if not self.gamepadTracked then return end
    self.gamepadTracked = nil
    local fcm = Manager()
    if fcm and fcm.FrameHidden then Report(pcall(fcm.FrameHidden, fcm, self)) end
end

-- B: close this window (Blizzard calls this before looking for a close button).
local function CloseHandler(self)
    self:Hide()
    return true
end

-- Call once per window, after its last SetScript("OnShow"/"OnHide") and its first Hide.
function ns.GamepadWindow(f)
    f.SmartNavigationCloseHandler = CloseHandler
    f:HookScript("OnShow", Shown)
    f:HookScript("OnHide", Hidden)
end

-- A frame with only a hover tooltip (no click) that the D-pad should still reach.
function ns.GamepadFocusable(f)
    if SmartNavigation_MarkFrameFocusable then SmartNavigation_MarkFrameFocusable(f) end
end

-- A mouse-only control the D-pad should skip (the resize grip).
function ns.GamepadIgnore(f)
    if SmartNavigation_MarkFrameIgnored then SmartNavigation_MarkFrameIgnored(f) end
end

-- Up or down arrow for paging a list: the D-pad can't turn a mouse wheel or drag a
-- slider, but it can press a button. The game's own scroll bar arrows.
function ns.PageButton(parent, up, onClick)
    local art = "Interface\\Buttons\\UI-ScrollBar-Scroll" .. (up and "Up" or "Down") .. "Button-"
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(20, 20)
    b:SetNormalTexture(art .. "Up")
    b:SetPushedTexture(art .. "Down")
    b:SetDisabledTexture(art .. "Disabled")
    b:SetHighlightTexture(art .. "Highlight", "ADD")
    b:SetScript("OnClick", onClick)
    return b
end

-- Menus. With the Gamepad UI on, the game's menus (MenuUtil) can't carry anything of ours:
-- when one opens, Blizzard's controller code (FrameControlsManager's MenuProxy.OnShow) records
-- its state while reading the menu's entries, which our code made, so the game later blames
-- us for SetPreferredGamepadInteractTarget() (ADDON_ACTION_FORBIDDEN) when the navigator
-- switches off: closing the bags, clicking the world, closing a window. A player's report and
-- the owner's tests, 2026-11-20: the bag portrait entry, then the overview's cog menu. So every
-- menu of ours goes through ns.OpenMenu: the game's menu for mouse and keyboard, and with the
-- Gamepad UI on a small window of our own with the same entries, which the D-pad moves through.
-- The generator is the same function either way: it's handed a stand-in for the menu's root
-- with the calls our menus use (buttons, tick boxes, radio choices, titles, dividers,
-- SetEnabled, entries under a button for a sub-list).
local ROW_H, MENU_W, DIVIDER_H, MENU_MAX_H = 20, 280, 8, 420
local CHECK_ON = "|TInterface\\Buttons\\UI-CheckBox-Check:16:16|t "
local CHECK_OFF = "|TInterface\\Buttons\\UI-CheckBox-Up:16:16|t "
local RADIO_ON = "|TInterface\\Buttons\\UI-RadioButton:14:14:0:0:64:16:18:30:2:14|t "
local RADIO_OFF = "|TInterface\\Buttons\\UI-RadioButton:14:14:0:0:64:16:2:14:2:14|t "
local MORE = " |TInterface\\ChatFrame\\ChatFrameExpandArrow:12:12|t"
local BACK_ICON = "|TInterface\\Buttons\\UI-SpellbookIcon-PrevPage-Up:16:16|t "

local function Noop() end
local Entry = {}
-- Methods our menus don't use (tooltips, responses...) do nothing rather than fail. Only
-- capitalised names, as the game's: our own fields (text, data...) stay nil when unset.
local EntryMeta = { __index = function(_, k)
    if Entry[k] then return Entry[k] end
    if type(k) == "string" and k:find("^%u") then return Noop end
end }

local function NewEntry(kind, text, a, b, data)
    return setmetatable({ kind = kind, text = text, a = a, b = b, data = data, enabled = true, children = {} }, EntryMeta)
end

local function Add(list, e)
    list.children[#list.children + 1] = e
    return e
end

function Entry:CreateButton(text, fn, data) return Add(self, NewEntry("button", text, fn, nil, data)) end
function Entry:CreateCheckbox(text, isSelected, setSelected, data) return Add(self, NewEntry("check", text, isSelected, setSelected, data)) end
function Entry:CreateRadio(text, isSelected, setSelected, data) return Add(self, NewEntry("radio", text, isSelected, setSelected, data)) end
function Entry:CreateTitle(text) return Add(self, NewEntry("title", text)) end
function Entry:CreateDivider() return Add(self, NewEntry("divider")) end
function Entry:CreateSpacer() return Add(self, NewEntry("divider")) end
function Entry:SetEnabled(on) self.enabled = on end

local function IsEnabled(e)
    if type(e.enabled) == "function" then return e.enabled(e.data) and true or false end
    return e.enabled ~= false and e.enabled ~= nil
end

local function IsSelected(e) return type(e.a) == "function" and e.a(e.data) and true or false end

local menu -- the window, made on first use
local stack, list, offset = {}, nil, 0 -- lists above the one shown (sub-lists), the one shown, first entry shown
local Render

local function Back()
    list, offset = table.remove(stack), 0
    Render()
end

local function EntryClick(row)
    local e = row.entry
    if row.back then return Back() end
    if not (e and IsEnabled(e)) then return end
    if e.kind == "check" then
        if e.b then e.b(e.data) end
        return Render() -- the menu stays, as the game's does for tick boxes
    end
    if e.kind == "button" and #e.children > 0 then
        stack[#stack + 1] = list
        list, offset = e, 0
        return Render()
    end
    local fn = e.kind == "radio" and e.b or e.a
    menu:Hide() -- first, so a window the choice opens gets the focus
    if fn then fn(e.data) end
end

local function MenuRow(i)
    local row = menu.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, menu)
    row:SetSize(MENU_W - 24, ROW_H)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.text:SetJustifyH("LEFT")
    if row.text.SetWordWrap then row.text:SetWordWrap(false) end
    ns.SkinText(row.text)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.12)
    row:SetScript("OnClick", EntryClick)
    menu.rows[i] = row
    return row
end

local function MenuLabel(i)
    local label = menu.labels[i]
    if label then return label end
    label = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetJustifyH("LEFT")
    label:SetWidth(MENU_W - 32)
    if label.SetWordWrap then label:SetWordWrap(false) end
    ns.SkinText(label)
    menu.labels[i] = label
    return label
end

local function MenuLine(i)
    local line = menu.lines[i]
    if line then return line end
    line = menu:CreateTexture(nil, "ARTWORK")
    line:SetSize(MENU_W - 32, 1)
    line:SetColorTexture(1, 1, 1, 0.2)
    menu.lines[i] = line
    return line
end

local function EntryText(e)
    local text = e.text or ""
    if e.kind == "check" then
        text = (IsSelected(e) and CHECK_ON or CHECK_OFF) .. text
    elseif e.kind == "radio" then
        text = (IsSelected(e) and RADIO_ON or RADIO_OFF) .. text
    elseif #e.children > 0 then
        text = text .. MORE
    end
    return text
end

Render = function()
    local entries = list.children
    local nRow, nLabel, nLine = 0, 0, 0
    local top, y = -30, -30
    local function Place(region, height)
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", menu, "TOPLEFT", 12, y)
        region:Show()
        y = y - height
    end
    if #stack > 0 then
        nRow = 1
        local row = MenuRow(1)
        row.back, row.entry = true, nil
        row.text:SetText(BACK_ICON .. (_G.BACK or ""))
        row.text:SetTextColor(1, 1, 1)
        row:Enable()
        Place(row, ROW_H)
    end
    local shown, last = 0, offset
    for i = offset + 1, #entries do
        local e = entries[i]
        local height = e.kind == "divider" and DIVIDER_H or ROW_H
        if top - y + height > MENU_MAX_H and shown > 0 then break end
        shown, last = shown + 1, i
        if e.kind == "divider" then
            nLine = nLine + 1
            local line = MenuLine(nLine)
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", menu, "TOPLEFT", 16, y - DIVIDER_H / 2)
            line:Show()
            y = y - DIVIDER_H
        elseif e.kind == "title" then
            nLabel = nLabel + 1
            local label = MenuLabel(nLabel)
            label:SetText(e.text or "")
            label:SetHeight(ROW_H)
            Place(label, ROW_H)
        else
            nRow = nRow + 1
            local row = MenuRow(nRow)
            row.back, row.entry = nil, e
            row.text:SetText(EntryText(e))
            local on = IsEnabled(e)
            row:SetEnabled(on)
            if on then row.text:SetTextColor(1, 1, 1) else row.text:SetTextColor(0.5, 0.5, 0.5) end
            Place(row, ROW_H)
        end
    end
    for i = nRow + 1, #menu.rows do menu.rows[i]:Hide(); menu.rows[i].entry = nil end
    for i = nLabel + 1, #menu.labels do menu.labels[i]:Hide() end
    for i = nLine + 1, #menu.lines do menu.lines[i]:Hide() end
    local paged = offset > 0 or last < #entries
    menu.up:SetShown(paged)
    menu.down:SetShown(paged)
    menu.up:SetEnabled(offset > 0)
    menu.down:SetEnabled(last < #entries)
    menu.shownLast = last
    menu:SetHeight(-y + (paged and 34 or 12))
    menu.TitleText:SetText(list.text or "Alts Forever")
end

local function BuildMenu()
    menu = ns.NewWindow("AltsForeverMenuFrame")
    if not menu.TitleText then
        menu.TitleText = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        menu.TitleText:SetPoint("TOP", 0, -6)
    end
    menu:SetWidth(MENU_W)
    menu:SetFrameStrata("DIALOG")
    menu:SetToplevel(true)
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu.rows, menu.labels, menu.lines = {}, {}, {}
    menu.up = ns.PageButton(menu, true, function()
        offset = math.max(0, offset - 8)
        Render()
    end)
    menu.up:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -34, 8)
    menu.down = ns.PageButton(menu, false, function()
        offset = math.min(menu.shownLast or offset, #list.children - 1)
        Render()
    end)
    menu.down:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -12, 8)
    menu:SetScript("OnHide", function()
        wipe(stack)
        list, offset = nil, 0
        for _, row in ipairs(menu.rows) do row.entry = nil end
    end)
    ns.EscapeCloses(menu)
    ns.SkinWindow(menu)
    menu:Hide()
    ns.GamepadWindow(menu)
    -- B steps back out of a sub-list first.
    menu.SmartNavigationCloseHandler = function(self)
        if #stack > 0 then Back() else self:Hide() end
        return true
    end
    ns.ScaleWindow(menu)
end

-- Opens a menu of ours. `generator(owner, root)` fills it, as MenuUtil.CreateContextMenu's.
function ns.OpenMenu(owner, generator)
    if not ns.GamepadUI() then
        if MenuUtil and MenuUtil.CreateContextMenu then MenuUtil.CreateContextMenu(owner, generator) end
        return
    end
    local root = NewEntry("root")
    generator(owner, root)
    if #root.children == 0 then return end
    if not menu then BuildMenu() end
    menu:Hide() -- one at a time: a menu opened from a menu replaces it
    wipe(stack)
    list, offset = root, 0
    menu:ClearAllPoints()
    if type(owner) == "table" and owner.GetBottom and owner:GetBottom() then
        menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    else
        menu:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    Render()
    menu:Show()
    menu:Raise()
end

-- For tests: the controller menu's window, if made.
function ns.GamepadMenu() return menu end

-- Key bindings (Bindings.xml): put on a controller button, or reach them with a macro of
-- /af, /af bags or /afs on a gamepad action bar. They have their own "Alts Forever" section
-- in Key Bindings (category="Alts Forever", as EllesmereUI and Dungeon Journal do); under
-- category="ADDONS" they sat untitled among other addons' (owner, 2026-10-16).
BINDING_NAME_ALTSFOREVER_OVERVIEW = L["Open overview"]
BINDING_NAME_ALTSFOREVER_BAGS = L["Bags and bank"]
BINDING_NAME_ALTSFOREVER_SEARCH = L["Search your characters"]
function AltsForever_Binding(which)
    if which == "bags" then
        ns.ShowBags(ns.charKey, "bags")
    elseif which == "search" then
        ns.ToggleSearch()
    else
        ns.ToggleOverview()
    end
end

function ns.StartGamepad()
    -- With the Gamepad UI on, the Options page, the character sheet's anvils and our parts
    -- of the mailbox are built now, while those windows are closed: Blizzard's navigator rebuilds an open window
    -- whenever a frame is created in it, from the creating addon's code, which can leave its
    -- bindings tainted.
    local function Prepare()
        if ns.GamepadUI() and not InCombatLockdown() then
            ns.PrebuildOptions()
            ns.PrebuildAnvils()
            ns.PrebuildMail()
        end
    end
    ns.On("INPUT_DEVICE_INTERFACE_TRANSITION", Prepare)
    -- Skipped in combat (a reload mid-fight, or the Gamepad UI switched on in one): done as
    -- it ends. Each part is made once, so later fights' ends cost a few checks.
    ns.On("PLAYER_REGEN_ENABLED", Prepare)
    Prepare()
end
