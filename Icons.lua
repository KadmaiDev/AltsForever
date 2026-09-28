-- Alts Forever icons: the icons item tooltips use for bags, bank, mail and worn items,
-- chosen by the player from a picker (Options > AddOns > Alts Forever > Change...).
-- Choices are saved in db.icons[place] as an icon (a file ID from the game's icon lists,
-- or a texture path), or "words" for text instead of an icon; nil means the default.
-- The picker offers a recommended row per place, a search, and every spell and item icon
-- in the game to browse (about 27,000 on Forever). Forever doesn't expose icon file names
-- (GetFilenameFromFileDataID answers "FileData ID <n>"), so the search matches what icons
-- belong to instead: items on any character, items their recipes make, and the current
-- character's spells, by name in the player's language. The lists and the search pool are
-- built only while the picker is open.
local _, ns = ...
if ns.disabled then return end -- another copy of Alts Forever is running (Core.lua)
local L = ns.L

local floor, max, min, ipairs, pairs, type, pcall = math.floor, math.max, math.min, ipairs, pairs, type, pcall
local issecretvalue = issecretvalue or function() return false end

ns.ICON_PLACES = { "bags", "bank", "mail", "equip" }
local PLACE_NAMES = { bags = L["Bags"], bank = L["Bank"], mail = L["Mail"], equip = L["Worn"] }
function ns.PlaceName(place) return PLACE_NAMES[place] end

-- Defaults and suggestions. Bags default to a bag item's icon, looked up from the item.
local BAG_ICON_ITEM = 5762 -- Red Linen Bag
local DEFAULTS = {
    bags = C_Item.GetItemIconByID(BAG_ICON_ITEM) or "Interface\\Icons\\INV_Misc_Bag_08",
    bank = "Interface\\Minimap\\Tracking\\Banker",
    mail = "Interface\\Minimap\\Tracking\\Mailbox",
    equip = "Interface\\Icons\\INV_Shirt_White_01",
}
local RECOMMENDED = {
    bags = { DEFAULTS.bags, "Interface\\Icons\\INV_Misc_Bag_01", "Interface\\Icons\\INV_Misc_Bag_07", "Interface\\Icons\\INV_Misc_Bag_08",
        "Interface\\Icons\\INV_Misc_Bag_09", "Interface\\Icons\\INV_Misc_Bag_10" },
    bank = { "Interface\\Minimap\\Tracking\\Banker", "Interface\\Icons\\INV_Box_01", "Interface\\Icons\\INV_Box_02",
        "Interface\\Icons\\INV_Misc_Coin_01", "Interface\\Icons\\INV_Misc_Key_03", "Interface\\Icons\\INV_Misc_Bag_10" },
    mail = { "Interface\\Minimap\\Tracking\\Mailbox", "Interface\\Icons\\INV_Letter_01", "Interface\\Icons\\INV_Letter_02",
        "Interface\\Icons\\INV_Misc_Note_01", "Interface\\Icons\\INV_Scroll_03", "Interface\\Icons\\INV_Letter_03" },
    equip = { "Interface\\Icons\\INV_Shirt_White_01", "Interface\\Icons\\INV_Chest_Chain_05", "Interface\\Icons\\INV_Helmet_03",
        "Interface\\Icons\\INV_Shield_06", "Interface\\Icons\\INV_Sword_04", "Interface\\Icons\\INV_Boots_01" },
}
-- Icons with the game's built-in border get it cropped off; the minimap tracking art has none.
local function Cropped(icon)
    return not (type(icon) == "string" and icon:find("Minimap", 1, true))
end

function ns.IconChoice(place)
    local chosen = ns.db and ns.db.icons and ns.db.icons[place]
    return chosen or DEFAULTS[place]
end

-- The text an item tooltip shows for a place: an icon sized to the text, or the word.
function ns.PlaceMarkup(place)
    local icon = ns.IconChoice(place)
    if icon == "words" then return PLACE_NAMES[place] end
    return "|T" .. icon .. (Cropped(icon) and ":0:0:0:0:64:64:5:59:5:59|t" or ":0|t")
end

-- Saves a choice (an icon, "words", or nil for the default) and refreshes the tooltips.
function ns.SetPlaceIcon(place, icon)
    ns.db.icons = ns.db.icons or {}
    ns.db.icons[place] = icon
    if next(ns.db.icons) == nil then ns.db.icons = nil end
    if ns.RefreshPlaceLabels then ns.RefreshPlaceLabels() end
    if ns.RefreshIconChoices then ns.RefreshIconChoices() end
end

---------------------------------------------------------------------------
-- The picker
---------------------------------------------------------------------------
local COLS, ROWS, SIZE, GAP = 12, 7, 32, 4
local picker

local function SetButtonIcon(b, icon)
    b.value = icon
    b.icon:SetTexture(icon)
    if Cropped(icon) then b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) else b.icon:SetTexCoord(0, 1, 0, 1) end
end

local function Selected(b)
    local chosen = ns.IconChoice(picker.place)
    b.selected:SetShown(b.value ~= nil and b.value == chosen)
end

local function IconButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(SIZE, SIZE)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.25)
    b.selected = b:CreateTexture(nil, "OVERLAY")
    b.selected:SetPoint("TOPLEFT", -3, 3)
    b.selected:SetPoint("BOTTOMRIGHT", 3, -3)
    b.selected:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    b.selected:SetBlendMode("ADD")
    b.selected:Hide()
    b:SetScript("OnClick", function(self)
        if self.value then ns.SetPlaceIcon(picker.place, self.value) end
    end)
    return b
end

local function Render()
    local list, total = picker.list, picker.list and #picker.list or 0
    local rows = floor((total + COLS - 1) / COLS)
    local maxOffset = max(0, rows - ROWS)
    picker.offset = min(max(picker.offset, 0), maxOffset)
    for i, b in ipairs(picker.grid) do
        local icon = list and list[picker.offset * COLS + i]
        if icon then
            SetButtonIcon(b, icon)
            b:Show()
            Selected(b)
        else
            b.value = nil
            b:Hide()
        end
    end
    local first = picker.offset * COLS + 1
    picker.counter:SetText(total > 0 and L["%d-%d of %d"]:format(first, min(total, first + COLS * ROWS - 1), total) or "")
    picker.slider.updating = true
    picker.slider:SetMinMaxValues(0, maxOffset)
    picker.slider:SetValue(picker.offset)
    picker.slider.updating = nil
end

-- Named things with icons, for the search: items on any character and items their
-- recipes make (names from the game's item cache), and the current character's spells.
local function SearchPool()
    if picker.pool then return picker.pool end
    local pool, seen = {}, {}
    local function Add(name, icon)
        if type(name) == "string" and name ~= "" and icon and not issecretvalue(name) and not issecretvalue(icon) then
            local key = name:lower()
            if not seen[key] then
                seen[key] = true
                pool[#pool + 1] = { key, icon }
            end
        end
    end
    local function AddItem(id)
        if type(id) == "number" then Add(C_Item.GetItemNameByID(id), C_Item.GetItemIconByID(id)) end
    end
    for _, c in pairs(ns.db.chars) do
        for _, loc in ipairs({ "bags", "bank", "mail", "equip" }) do
            if type(c[loc]) == "table" then for id in pairs(c[loc]) do AddItem(id) end end
        end
        if type(c.crafts) == "table" then
            for _, made in pairs(c.crafts) do
                if type(made) == "table" then for id in pairs(made) do AddItem(id) end end
            end
        end
    end
    local SB = C_SpellBook
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    if SB and SB.GetNumSpellBookSkillLines and SB.GetSpellBookSkillLineInfo and SB.GetSpellBookItemInfo and bank then
        pcall(function()
            for line = 1, SB.GetNumSpellBookSkillLines() do
                local info = SB.GetSpellBookSkillLineInfo(line)
                if info then
                    for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                        local item = SB.GetSpellBookItemInfo(slot, bank)
                        if item then Add(item.name, item.iconID) end
                    end
                end
            end
        end)
    end
    picker.pool = pool
    return pool
end

-- Fills the grid with the icons of things whose names contain the text.
local function Search(text)
    text = (text or ""):match("^%s*(.-)%s*$"):lower()
    if text == "" then
        if picker.listKind == "search" then picker.listKind = nil end
        picker.list, picker.offset = picker.browse, 0
        Render()
        return
    end
    local results, icons = {}, {}
    for _, entry in ipairs(SearchPool()) do
        if entry[1]:find(text, 1, true) and not icons[entry[2]] then
            icons[entry[2]] = true
            results[#results + 1] = entry[2]
        end
    end
    picker.list, picker.offset = results, 0
    Render()
    picker.counter:SetText(#results == 0 and L["Nothing found; try Spell icons or Item icons."] or picker.counter:GetText())
end
ns.SearchIcons = function(text) return Search(text) end

-- Loads one of the game's icon lists (only while the picker is open).
local function ShowList(kind)
    picker.listKind = kind
    local list = {}
    if kind == "spell" then
        if GetMacroIcons then GetMacroIcons(list) end
    elseif GetMacroItemIcons then
        GetMacroItemIcons(list)
    end
    picker.list, picker.browse, picker.offset = list, list, 0
    if picker.search then picker.search:SetText("") end
    if kind == "spell" then picker.spellTab:LockHighlight() else picker.spellTab:UnlockHighlight() end
    if kind == "item" then picker.itemTab:LockHighlight() else picker.itemTab:UnlockHighlight() end
    Render()
end

local function RefreshPicker()
    if not (picker and picker:IsShown()) then return end
    local place = picker.place
    picker.title:SetText(L["Icon for %s"]:format(PLACE_NAMES[place]))
    picker.preview:SetText(L["In tooltips: %s"]:format(ns.PlaceMarkup(place) .. " 23"))
    for i, b in ipairs(picker.recommended) do
        SetButtonIcon(b, RECOMMENDED[place][i])
        Selected(b)
    end
    for _, b in ipairs(picker.grid) do if b:IsShown() then Selected(b) end end
    picker.words:SetEnabled(ns.IconChoice(place) ~= "words")
end

local function PanelButton(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    ns.SkinButton(b)
    return b
end

local function CreatePicker()
    local ok, f = pcall(CreateFrame, "Frame", "AltsForeverIconPicker", UIParent, "BasicFrameTemplateWithInset")
    if not ok then f = CreateFrame("Frame", "AltsForeverIconPicker", UIParent, "BackdropTemplate") end
    picker = f
    local width = COLS * (SIZE + GAP) + 60
    f:SetSize(width, 190 + ROWS * (SIZE + GAP) + 50)
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

    f.preview = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.preview:SetPoint("TOPLEFT", 16, -34)

    local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", f.preview, "BOTTOMLEFT", 0, -12)
    label:SetText(L["Recommended"])
    f.recommended = {}
    for i = 1, 6 do
        local b = IconButton(f)
        b:SetPoint("TOPLEFT", label, "BOTTOMLEFT", (i - 1) * (SIZE + GAP), -6)
        f.recommended[i] = b
    end
    -- Top right, on the preview's line, anchored to the window's edge so they stay inside it.
    f.reset = PanelButton(f, L["Reset to default"], 130)
    f.reset:SetPoint("TOPRIGHT", -16, -28)
    f.words = PanelButton(f, L["Use words instead"], 150)
    f.words:SetPoint("RIGHT", f.reset, "LEFT", -6, 0)
    f.words:SetScript("OnClick", function() ns.SetPlaceIcon(picker.place, "words") end)
    f.reset:SetScript("OnClick", function() ns.SetPlaceIcon(picker.place, nil) end)

    local ok2, search = pcall(CreateFrame, "EditBox", nil, f, "InputBoxTemplate")
    if not ok2 then search = CreateFrame("EditBox", nil, f) end
    search:SetSize(200, 22)
    search:SetPoint("TOPLEFT", f.recommended[1], "BOTTOMLEFT", 6, -16)
    search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function(self, userInput)
        if userInput then Search(self:GetText()) end
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search.hint = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    search.hint:SetPoint("LEFT", 4, 0)
    search.hint:SetText(L["Search: an item or spell name"])
    search:HookScript("OnTextChanged", function(self) self.hint:SetShown(self:GetText() == "") end)
    f.search = search
    if ns.SkinEditBox then ns.SkinEditBox(search) end
    local browse = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    browse:SetPoint("LEFT", search, "RIGHT", 16, 0)
    browse:SetText(L["or browse:"])
    f.spellTab = PanelButton(f, L["Spell icons"], 110)
    f.spellTab:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -6, -10)
    f.spellTab:SetScript("OnClick", function() ShowList("spell") end)
    f.itemTab = PanelButton(f, L["Item icons"], 110)
    f.itemTab:SetPoint("LEFT", f.spellTab, "RIGHT", 6, 0)
    f.itemTab:SetScript("OnClick", function() ShowList("item") end)
    f.counter = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.counter:SetPoint("LEFT", f.itemTab, "RIGHT", 12, 0)

    local grid = CreateFrame("Frame", nil, f)
    grid:SetPoint("TOPLEFT", f.spellTab, "BOTTOMLEFT", 0, -8)
    grid:SetSize(COLS * (SIZE + GAP), ROWS * (SIZE + GAP))
    grid:EnableMouseWheel(true)
    grid:SetScript("OnMouseWheel", function(_, delta)
        picker.offset = picker.offset - delta * 2
        Render()
    end)
    f.gridFrame = grid
    f.grid = {}
    for r = 0, ROWS - 1 do
        for c = 0, COLS - 1 do
            local b = IconButton(grid)
            b:SetPoint("TOPLEFT", c * (SIZE + GAP), -r * (SIZE + GAP))
            f.grid[#f.grid + 1] = b
        end
    end
    local slider = CreateFrame("Slider", nil, f)
    slider:SetOrientation("VERTICAL")
    slider:SetPoint("TOPLEFT", grid, "TOPRIGHT", 8, 0)
    slider:SetPoint("BOTTOMLEFT", grid, "BOTTOMRIGHT", 8, 0)
    slider:SetWidth(16)
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("TOP", 0, 0)
    track:SetPoint("BOTTOM", 0, 0)
    track:SetWidth(6)
    track:SetColorTexture(1, 1, 1, 0.12)
    slider.track = track
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(12, 28)
    thumb:SetColorTexture(1, 0.82, 0, 0.8)
    slider:SetThumbTexture(thumb)
    slider:EnableMouseWheel(true)
    slider:SetScript("OnMouseWheel", function(_, delta)
        picker.offset = picker.offset - delta * 2
        Render()
    end)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    slider:SetScript("OnValueChanged", function(self, value)
        if self.updating then return end
        picker.offset = floor(value + 0.5)
        Render()
    end)
    f.slider = slider

    -- The icon lists are big: let them go when the picker closes.
    f:SetScript("OnHide", function(self) self.list, self.browse, self.pool = nil, nil, nil end)
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "AltsForeverIconPicker" end
    ns.SkinWindow(f)
    f:Hide()
end

-- Opens the picker for a place ("bags", "bank", "mail" or "equip").
function ns.OpenIconPicker(place)
    if not picker then CreatePicker() end
    picker.place = place
    picker:Show()
    ShowList(picker.listKind or "spell")
    RefreshPicker()
end

function ns.RefreshIconChoices()
    RefreshPicker()
    if ns.RefreshOptionsIcons then ns.RefreshOptionsIcons() end
end

function ns.IconPicker() return picker end
