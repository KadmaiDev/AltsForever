-- Alts Forever options: everything the slash commands do, by clicking. A page under
-- Options > AddOns, a minimap button and the minimap's addon compartment entry (click:
-- overview, right-click: options menu), the same menu from the overview's cog button, and
-- "Forget" on a character row's right-click menu. Menus and pop-ups are only built when
-- clicked.
local ADDON, ns = ...
if ns.disabled then return end -- another copy of Alts Forever is running (Core.lua)
local L = ns.L

local GREY = "|cff9d9d9d"

---------------------------------------------------------------------------
-- Actions shared by the slash commands, menus and settings page
---------------------------------------------------------------------------
function ns.SetSkillups(on)
    ns.db.skillupsOff = not on or nil
    ns.InvalidateCache()
end

-- Removes a character; returns false and a reason if it can't.
function ns.ForgetCharacter(key)
    if not ns.db.chars[key] then return false, L["No character named '%s'."]:format(tostring(key)) end
    if key == ns.charKey then return false, L["You can't forget the character you're logged in on."] end
    ns.db.chars[key] = nil
    ns.PruneRecipeInfo()
    ns.InvalidateCache()
    return true
end

-- The confirmation pop-up. Added to Blizzard's StaticPopupDialogs only the first time
-- it's needed, and never by assigning the global itself: writing a Blizzard global from
-- addon code taints every secure read of it, and Esc (ToggleGameMenu) reads this one
-- before SpellStopCasting, which then got blocked (ADDON_ACTION_FORBIDDEN).
local function ForgetDialog()
    if StaticPopupDialogs.ALTSFOREVER_FORGET then return end
    StaticPopupDialogs.ALTSFOREVER_FORGET = {
        text = L["Forget %s?\n\nAlts Forever removes their items, gold, gear and recipes. They're recorded again next time you log in on them."],
        button1 = YES or "Yes",
        button2 = NO or "No",
        OnAccept = function(_, key)
            local ok, why = ns.ForgetCharacter(key)
            ns.Print(ok and L["Forgot %s."]:format(key) or why)
            if ns.RefreshOverview then ns.RefreshOverview() end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

---------------------------------------------------------------------------
-- Menus
---------------------------------------------------------------------------
local function SkillupsSelected() return ns.SkillupsOn() end
local function ToggleSkillups() ns.SetSkillups(not ns.SkillupsOn()) end
local function SendToAltSelected() return ns.SendToAltOn() end
local function ToggleSendToAlt() ns.SetSendToAlt(not ns.SendToAltOn()) end
local function StatsSelected() return ns.StatsOn() end
local function ToggleStats() ns.SetStats(not ns.StatsOn()) end
local function MinimapSelected() return ns.MinimapButtonOn() end
local function ToggleMinimap() ns.SetMinimapButton(not ns.MinimapButtonOn()) end

---------------------------------------------------------------------------
-- Options > AddOns > Alts Forever
-- A "canvas" page (as Keystance, EllesmereUI and BugSack have): Blizzard's panel only
-- hosts our own frame, with the logo, an Open overview button and the settings as tick
-- boxes. None of Blizzard's setting objects (RegisterProxySetting and friends) are used,
-- so our values never run through Blizzard's settings code (a test keeps it that way).
-- The page is registered at login but only built the first time it's shown.
---------------------------------------------------------------------------
local category, canvas

-- Opens the overview from the page: Blizzard's panel closes first and the overview opens
-- a frame later (as EllesmereUI does), so nothing of ours runs inside its closing. In
-- combat the panel is left alone.
local function OpenOverviewFromOptions()
    if not InCombatLockdown() and SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then
        HideUIPanel(SettingsPanel)
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() ns.ToggleOverview(true) end)
    else
        ns.ToggleOverview(true)
    end
end

local function Tooltip(owner, title, text)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(title)
    GameTooltip:AddLine(text, 1, 1, 1, true)
    GameTooltip:Show()
end

local SETTINGS = {
    { L["Show skill-up details"], SkillupsSelected, function(on) ns.SetSkillups(on) end,
        L["Show which characters can still skill up: in Can craft, on materials (Skill-ups) and in the overview. Same as /af skillups."] },
    { L["Send mail to alts"], SendToAltSelected, function(on) ns.SetSendToAlt(on) end,
        L["An arrow next to the To box at the mailbox to pick one of your characters. Same as /af sendmail."] },
    { L["Show session stats"], StatsSelected, function(on) ns.SetStats(on) end,
        L["Off by default. Your XP bar shows this session's XP and time to level; your bag gold shows gold gained or lost this session, today and this week. Same as /af stats."] },
    { L["Show minimap button"], MinimapSelected, function(on) ns.SetMinimapButton(on) end,
        L["Same as /af minimap. Alts Forever is also in the minimap's addon menu."] },
}

local function RefreshCanvas(f)
    for i, check in ipairs(f.checks) do check:SetChecked(SETTINGS[i][2]() and true or false) end
    for place, label in pairs(f.icons or {}) do
        label:SetText(ns.PlaceName(place) .. ":  " .. ns.PlaceMarkup(place) .. " 23")
    end
end

function ns.RefreshOptionsIcons()
    if canvas and canvas.built then RefreshCanvas(canvas) end
end

local function BuildCanvas(f)
    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetSize(56, 56)
    logo:SetPoint("TOPLEFT", 16, -16)
    logo:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\media\\logo.tga") -- the full badge, big enough here
    f.logo = logo
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -6)
    title:SetText("Alts Forever")
    local by = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    by:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    by:SetText(L["All your alts at a glance, by Kadmai"])
    local open = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    open:SetSize(200, 24)
    open:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -16)
    open:SetText(L["Open overview"])
    open:SetScript("OnClick", OpenOverviewFromOptions)
    open:SetScript("OnEnter", function(self)
        Tooltip(self, L["Open overview"], L["Every character at a glance. Right-click a character there to forget them. Same as /af."])
    end)
    open:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.open = open
    ns.SkinButton(open)
    f.checks = {}
    local above = open
    for i, entry in ipairs(SETTINGS) do
        local check = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        check:SetSize(26, 26)
        check:SetPoint("TOPLEFT", above, "BOTTOMLEFT", i == 1 and -2 or 0, i == 1 and -14 or -4)
        local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", check, "RIGHT", 4, 0)
        label:SetText(entry[1])
        check.label = label
        check:SetScript("OnClick", function(self)
            entry[3](self:GetChecked() and true or false)
            RefreshCanvas(f)
        end)
        check:SetScript("OnEnter", function(self) Tooltip(self, entry[1], entry[4]) end)
        check:SetScript("OnLeave", function() GameTooltip:Hide() end)
        ns.SkinCheck(check)
        ns.SkinText(label)
        f.checks[i] = check
        above = check
    end
    -- Tooltip icons: each place's current icon (or word) and a Change... button.
    local heading = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    heading:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 2, -18)
    heading:SetText(L["Tooltip icons"])
    f.icons = {}
    local row = heading
    for i, place in ipairs(ns.ICON_PLACES) do
        local change = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        change:SetSize(100, 22)
        change:SetPoint("TOPLEFT", row, "BOTTOMLEFT", i == 1 and 0 or 0, i == 1 and -8 or -4)
        change:SetText(L["Change..."])
        change:SetScript("OnClick", function() ns.OpenIconPicker(place) end)
        ns.SkinButton(change)
        local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", change, "RIGHT", 10, 0)
        ns.SkinText(label)
        f.icons[place] = label
        row = change
    end
    above = row
    local help = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 2, -16)
    help:SetText(L["Type /af help for every command."])
    for _, fs in ipairs({ title, by, help }) do ns.SkinText(fs) end
end

local function RegisterSettings()
    local f = CreateFrame("Frame", "AltsForeverOptionsPanel")
    f:SetScript("OnShow", function(self)
        if not self.built then
            self.built = true
            BuildCanvas(self)
        end
        RefreshCanvas(self)
    end)
    local cat = Settings.RegisterCanvasLayoutCategory(f, "Alts Forever")
    Settings.RegisterAddOnCategory(cat)
    category, canvas = cat, f
end

function ns.StartOptions()
    if category or not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    -- The settings API isn't in Forever's documentation: report a failure, but keep going.
    local ok, err = pcall(RegisterSettings)
    if not ok then
        category, canvas = nil, nil
        if geterrorhandler then geterrorhandler()(err) end
    end
end

-- Opens Options > AddOns > Alts Forever; false if there's no page.
function ns.OpenSettings()
    if not (category and Settings.OpenToCategory) then return false end
    return pcall(Settings.OpenToCategory, category:GetID())
end

function ns.HasSettings() return category ~= nil end
function ns.OptionsPanel() return canvas end

-- The options menu: from the compartment's right-click and the overview's cog button.
function ns.ShowOptionsMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return ns.ShowHelp() end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Alts Forever")
        -- Not when it's already open (e.g. from the overview's own cog button).
        if not ns.OverviewShown() then
            root:CreateButton(L["Open overview"], function() ns.ToggleOverview(true) end)
        end
        root:CreateCheckbox(L["Show skill-up details"], SkillupsSelected, ToggleSkillups)
        root:CreateCheckbox(L["Send mail to alts"], SendToAltSelected, ToggleSendToAlt)
        root:CreateCheckbox(L["Show session stats"], StatsSelected, ToggleStats)
        root:CreateCheckbox(L["Show minimap button"], MinimapSelected, ToggleMinimap)
        root:CreateButton(L["Memory use"], function() ns.RunCommand("mem") end)
        if ns.HasSettings() then root:CreateButton(L["Settings..."], ns.OpenSettings) end
    end)
end

-- A character row's right-click menu in the overview.
function ns.ShowCharacterMenu(owner, key)
    local c = ns.db.chars[key]
    if not (c and MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(ns.ColoredName(key, c))
        local forget = root:CreateButton(L["Forget %s..."]:format(c.name or key), function()
            ForgetDialog()
            StaticPopup_Show("ALTSFOREVER_FORGET", c.name or key, nil, key)
        end)
        if key == ns.charKey then
            forget:SetEnabled(false)
            root:CreateTitle(GREY .. L["(the character you're on)"] .. "|r")
        end
    end)
end

---------------------------------------------------------------------------
-- Minimap button: a standard one (no library). EllesmereUI's minimap collects named
-- buttons on the minimap into its own button tray, so it needs to exist before that
-- scan at login: it's made as soon as our saved data loads. Dragging moves it around
-- the minimap's edge (the position is saved); the OnUpdate runs only while dragging.
---------------------------------------------------------------------------
-- Our logo without its outer gold ring (media/minimap.tga): the ring around the button
-- comes from the minimap border or EllesmereUI's tray, and two rings showed any small
-- misalignment between them. Built from the folder name, so a renamed test copy finds
-- its own. (The addon list uses the full logo, media/icon.tga, via the .toc.)
local ICON = "Interface\\AddOns\\" .. ADDON .. "\\media\\minimap.tga"
local DEFAULT_ANGLE = 220
local mmButton

function ns.MinimapButtonOn()
    return not ns.db.minimapHidden
end

local function Place(angle)
    local rad = math.rad(angle)
    local radius = Minimap:GetWidth() / 2 + 10
    mmButton:ClearAllPoints()
    mmButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * radius, math.sin(rad) * radius)
end

local function FollowCursor()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    ns.db.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
    Place(ns.db.minimapAngle)
end

local function ButtonTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Alts Forever")
    GameTooltip:AddLine(L["Click: open the overview"], 1, 1, 1)
    GameTooltip:AddLine(L["Right-click: options"], 1, 1, 1)
    GameTooltip:AddLine(L["Drag: move around the minimap"], 1, 1, 1)
    GameTooltip:Show()
end

function ns.CreateMinimapButton()
    if mmButton or not Minimap or not ns.MinimapButtonOn() then return end
    local b = CreateFrame("Button", "AltsForeverMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    -- Icon and background are pinned to all four edges with an even margin, so they stay
    -- centred when EllesmereUI's minimap tray resizes the button (a fixed top-left anchor
    -- left the logo off centre there).
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", b, "TOPLEFT", 4, -4)
    bg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -4, 4)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", b, "TOPLEFT", 5, -5)
    icon:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -5, 5)
    icon:SetTexture(ICON) -- round with transparent corners: no cropping needed
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b.icon = icon
    b:SetScript("OnClick", function(self, button)
        if button == "RightButton" then ns.ShowOptionsMenu(self) else ns.ToggleOverview() end
    end)
    b:SetScript("OnEnter", ButtonTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", FollowCursor) end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    mmButton = b
    Place(ns.db.minimapAngle or DEFAULT_ANGLE)
end

function ns.SetMinimapButton(on)
    ns.db.minimapHidden = not on or nil
    if on then ns.CreateMinimapButton() end
    if mmButton then mmButton:SetShown(on) end
end

---------------------------------------------------------------------------
-- Minimap addon compartment (functions named in the .toc)
---------------------------------------------------------------------------
function AltsForever_OnAddonCompartmentClick(_, button, frame)
    if button == "RightButton" then
        ns.ShowOptionsMenu(frame)
    else
        ns.ToggleOverview()
    end
end

function AltsForever_OnAddonCompartmentEnter(_, frame)
    GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
    GameTooltip:AddLine("Alts Forever")
    GameTooltip:AddLine(L["Click: open the overview"], 1, 1, 1)
    GameTooltip:AddLine(L["Right-click: options"], 1, 1, 1)
    GameTooltip:Show()
end

function AltsForever_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
