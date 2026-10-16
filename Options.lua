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

-- Window size (a player's request, 2026-10-16: they play at UI scale 0.53): our own
-- windows scaled together, on top of the game's UI scale. Tooltips follow the game's.
-- With EllesmereUI and no size of our own chosen (db.scale nil), they follow its Window
-- Scale (the owner's wish, same day): EllesmereUIDB.panelScale, read only, not part of its
-- official API. Its options panel is pinned to screen pixels times that; with its
-- pixel-perfect UI scale (0.53 is 1440p's) UIParent is too, so the two match exactly.
local MIN_SCALE, MAX_SCALE = 0.5, 3
local windows = {}

local function Clamp(scale)
    return math.max(MIN_SCALE, math.min(MAX_SCALE, math.floor(scale * 100 + 0.5) / 100))
end

-- EllesmereUI's Window Scale, or nil without EllesmereUI (1 if it hasn't set one).
local function EllesmereScale()
    if type(EllesmereUI) ~= "table" then return nil end
    local v = type(EllesmereUIDB) == "table" and EllesmereUIDB.panelScale
    if type(v) == "number" and v == v and v > 0 then return Clamp(v) end
    return 1
end

function ns.HasEllesmereScale() return EllesmereScale() ~= nil end
function ns.FollowsEllesmere() return ns.db.scale == nil and EllesmereScale() ~= nil end
function ns.WindowScale() return ns.db.scale or EllesmereScale() or 1 end

-- Positions are in a window's own scaled units: one placed against the screen keeps its
-- centre where it was. One anchored to another of ours (gear, reputation) follows that.
local function Rescale(f, scale)
    local old = f:GetScale() or 1
    if old == scale then return end
    local x, y = f:GetCenter()
    local _, rel = f:GetPoint()
    f:SetScale(scale)
    if x and y and (rel == nil or rel == UIParent) then
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x * old / scale, y * old / scale)
    end
end

local function ApplyScale()
    local scale = ns.WindowScale()
    for _, f in ipairs(windows) do Rescale(f, scale) end
    if ns.BagsWindowChanged then ns.BagsWindowChanged() end -- its default height is a share of the screen
end

-- EllesmereUI's slider calls SetPanelScale (its panel creates it when first opened): once
-- it exists, our open windows follow its slider live. Hooked once, guarded.
local hookedEllesmere
local function HookEllesmere()
    if hookedEllesmere or type(EllesmereUI) ~= "table" or type(EllesmereUI.SetPanelScale) ~= "function" then return end
    hookedEllesmere = true
    pcall(hooksecurefunc, EllesmereUI, "SetPanelScale", function()
        if ns.FollowsEllesmere() then ApplyScale() end
    end)
end

-- Each window, once, when it's created. Checked again each time it opens: EllesmereUI's
-- Window Scale may have changed while it was closed.
function ns.ScaleWindow(f)
    windows[#windows + 1] = f
    f:SetScale(ns.WindowScale())
    f:HookScript("OnShow", function(self)
        HookEllesmere()
        local scale = ns.WindowScale()
        if self:GetScale() ~= scale then Rescale(self, scale) end
    end)
end

-- Sets our own size (1 = 100%), kept between 50% and 300%; returns what it was set to.
function ns.SetWindowScale(scale)
    scale = Clamp(scale)
    ns.db.scale = scale
    ApplyScale()
    return scale
end

-- Back to the default: EllesmereUI's Window Scale if it's installed, else 100%.
function ns.FollowEllesmere()
    ns.db.scale = nil
    ApplyScale()
end

function ns.ScaleText(scale) return ("%d%%"):format(math.floor((scale or ns.WindowScale()) * 100 + 0.5)) end

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
local function CountsSelected() return ns.CountsOn() end
local function SkillupsSelected() return ns.SkillupsOn() end
local function UpgradesSelected() return ns.UpgradesOn() end
local function AnvilsSelected() return ns.AnvilsOn() end
local function SendToAltSelected() return ns.SendToAltOn() end
local function StatsSelected() return ns.StatsOn() end
local function LegacySelected() return ns.LegacyRemindersOn() end
local function RulesetsSelected() return ns.OtherRulesetsOn() end
local function ToggleRulesets() ns.SetOtherRulesets(not ns.OtherRulesetsOn()) end
local function MinimapSelected() return ns.MinimapButtonOn() end

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

-- The tick boxes, in this order in f.checks; `section` is where the page puts each one.
local SETTINGS = {
    { L["Show item counts"], CountsSelected, function(on) ns.SetCounts(on) end,
        L["Item tooltips list how many of the item each of your characters has, and where. Turn this off if another addon, such as Baganator, already shows them; Can craft, skill-ups, upgrades and crates stay. Same as /af counts."], section = "tooltips" },
    { L["Show skill-up details"], SkillupsSelected, function(on) ns.SetSkillups(on) end,
        L["Show which characters can still skill up: in Can craft, on materials (Skill-ups) and in the overview. Same as /af skillups."], section = "tooltips" },
    { L["Show upgrades"], UpgradesSelected, function(on) ns.SetUpgrades(on) end,
        L["Item tooltips name which of your characters an item would be an upgrade for, judged by their talents. Right-click a character in the overview to change their role. Same as /af upgrades."], section = "tooltips" },
    { L["Show craftable upgrades on the character sheet"], AnvilsSelected, function(on) ns.SetAnvils(on) end,
        L["An anvil beside a slot on your character sheet means you or an alt can craft an upgrade for it that you can wear now and that binds when equipped. Hover or click it to see which. Same as /af anvils."], section = "extras" },
    { L["Send mail to alts"], SendToAltSelected, function(on) ns.SetSendToAlt(on) end,
        L["An arrow next to the To box at the mailbox to pick one of your characters. Same as /af sendmail."], section = "extras" },
    { L["Show session stats"], StatsSelected, function(on) ns.SetStats(on) end,
        L["Off by default. Your XP bar shows this session's XP and time to level; your bag gold shows gold gained or lost this session, today and this week. Same as /af stats."], section = "extras" },
    { L["Legacy reminders"], LegacySelected, function(on) ns.SetLegacyReminders(on) end,
        L["Says in chat when the character you log in on has Legacy points to spend, and when you earn one. Same as /af legacy on or off."], section = "extras" },
    { L["Show other rulesets and factions"], RulesetsSelected, function(on) ns.SetOtherRulesets(on) end,
        L["Tooltips also list your characters on other rulesets (Normal, PvP...) and the other faction, under their own heading. They can't trade or mail with this one, so they're hidden by default; the overview always shows everyone. Same as /af rulesets."], section = "tooltips" },
    { L["Show minimap button"], MinimapSelected, function(on) ns.SetMinimapButton(on) end,
        L["Same as /af minimap. Alts Forever is also in the minimap's addon menu."], section = "display" },
}

local function RefreshCanvas(f)
    for i, check in ipairs(f.checks) do check:SetChecked(SETTINGS[i][2]() and true or false) end
    if f.slider then
        f.filling = true -- setting it isn't the player moving it
        f.slider:SetValue(ns.WindowScale() * 100)
        f.filling = nil
        f.scaleText:SetText(ns.ScaleText())
        f.followEui:SetShown(ns.HasEllesmereScale())
        f.followEui:SetChecked(ns.FollowsEllesmere())
    end
    for place, label in pairs(f.icons or {}) do
        label:SetText(ns.PlaceName(place) .. ":  " .. ns.PlaceMarkup(place) .. " 23")
    end
end

function ns.RefreshOptionsIcons()
    if canvas and canvas.built then RefreshCanvas(canvas) end
end

-- A section's gold heading, at a point on the page.
local function Heading(f, text, ...)
    local h = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h:SetPoint(...)
    h:SetText(text)
    ns.SkinText(h)
    return h
end

-- The section's tick boxes under its heading; returns the last one.
local function Checks(f, section, above)
    local first = true -- under the heading, rather than under another tick box
    for i, entry in ipairs(SETTINGS) do
        if entry.section == section then
            local check = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
            check:SetSize(26, 26)
            check:SetPoint("TOPLEFT", above, "BOTTOMLEFT", first and -2 or 0, first and -6 or -2)
            first = false
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
    end
    return above
end

-- The page (the owner's redesign, 2026-10-16: one column had run off the bottom): the
-- logo, title and Open overview across the top, then two columns. Left: what tooltips
-- show and their icons. Right: the extras, then the minimap button and window size.
local TOP, GAP = -100, 20

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
    local help = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", by, "BOTTOMLEFT", 0, -4)
    help:SetText(L["Type /af help for every command."])
    for _, fs in ipairs({ title, by, help }) do ns.SkinText(fs) end
    local open = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    open:SetSize(180, 24)
    open:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -32)
    open:SetText(L["Open overview"])
    open:SetScript("OnClick", OpenOverviewFromOptions)
    open:SetScript("OnEnter", function(self)
        Tooltip(self, L["Open overview"], L["Every character at a glance. Right-click a character there to forget them. Same as /af."])
    end)
    open:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.open = open
    ns.SkinButton(open)
    f.checks = {}

    -- Left column: tooltips, then their icons.
    local tips = Heading(f, L["Tooltips"], "TOPLEFT", f, "TOPLEFT", 18, TOP)
    local above = Checks(f, "tooltips", tips)
    local heading = Heading(f, L["Tooltip icons"], "TOPLEFT", above, "BOTTOMLEFT", 2, -GAP)
    f.icons = {}
    local row = heading
    for i, place in ipairs(ns.ICON_PLACES) do
        local change = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        change:SetSize(100, 22)
        change:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 0, i == 1 and -8 or -4)
        change:SetText(L["Change..."])
        change:SetScript("OnClick", function() ns.OpenIconPicker(place) end)
        ns.SkinButton(change)
        local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", change, "RIGHT", 10, 0)
        ns.SkinText(label)
        f.icons[place] = label
        row = change
    end

    -- Right column, from the page's middle: extras, then the minimap button and window size.
    local extras = Heading(f, L["Extras"], "TOPLEFT", f, "TOP", 10, TOP)
    above = Checks(f, "extras", extras)
    local display = Heading(f, L["Minimap and windows"], "TOPLEFT", above, "BOTTOMLEFT", 2, -GAP)
    above = Checks(f, "display", display)
    -- Window size: a slider in 5% steps with the size beside it (as EllesmereUI's Window
    -- Scale), plain (no template, as Advanced Graphics Tuner's) so it looks the same in any skin.
    local sizeLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sizeLabel:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 4, -8)
    sizeLabel:SetText(L["Window size"])
    ns.SkinText(sizeLabel)
    local slider = CreateFrame("Slider", nil, f)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(160, 16)
    slider:SetHitRectInsets(0, 0, -4, -4)
    -- - and + either side, a step each: a controller's D-pad can't drag a slider.
    local smaller = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    smaller:SetSize(24, 22)
    smaller:SetPoint("TOPLEFT", sizeLabel, "BOTTOMLEFT", 0, -6)
    smaller:SetText("-")
    slider:SetPoint("LEFT", smaller, "RIGHT", 8, 0)
    local bigger = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    bigger:SetSize(24, 22)
    bigger:SetPoint("LEFT", slider, "RIGHT", 8, 0)
    bigger:SetText("+")
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(4)
    track:SetColorTexture(1, 1, 1, 0.18)
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(10, 16)
    thumb:SetColorTexture(1, 0.82, 0, 0.95)
    slider:SetThumbTexture(thumb)
    slider:SetMinMaxValues(MIN_SCALE * 100, MAX_SCALE * 100)
    slider:SetValueStep(5)
    slider:SetObeyStepOnDrag(true)
    local scaleText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    scaleText:SetPoint("LEFT", bigger, "RIGHT", 10, 0)
    ns.SkinText(scaleText)
    slider:SetScript("OnValueChanged", function(_, value)
        if f.filling then return end
        scaleText:SetText(ns.ScaleText(ns.SetWindowScale(value / 100)))
        f.followEui:SetChecked(false)
    end)
    local function SizeTooltip(self)
        Tooltip(self, L["Window size"], L["Makes Alts Forever's windows (overview, bags, reputation, gear, icons, craftable upgrades) bigger or smaller, on top of the game's UI scale. Tooltips follow the game's. Same as /af scale."])
    end
    for _, b in ipairs({ slider, smaller, bigger }) do
        b:SetScript("OnEnter", SizeTooltip)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    for b, step in pairs({ [smaller] = -0.05, [bigger] = 0.05 }) do
        b:SetScript("OnClick", function()
            ns.SetWindowScale(ns.WindowScale() + step)
            RefreshCanvas(f)
        end)
        ns.SkinButton(b)
    end
    -- With EllesmereUI: follow its Window Scale (the default) or not. Moving the slider
    -- chooses our own size, which unticks it. Hidden without EllesmereUI.
    local follow = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    follow:SetSize(26, 26)
    follow:SetPoint("TOPLEFT", smaller, "BOTTOMLEFT", -2, -6)
    local followLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    followLabel:SetPoint("LEFT", follow, "RIGHT", 4, 0)
    followLabel:SetText(L["Same as EllesmereUI's Window Scale"])
    follow:SetScript("OnClick", function(self)
        if self:GetChecked() then ns.FollowEllesmere() else ns.SetWindowScale(ns.WindowScale()) end
        RefreshCanvas(f)
    end)
    follow:SetScript("OnEnter", function(self)
        Tooltip(self, L["Same as EllesmereUI's Window Scale"], L["Your Alts Forever windows take the Window Scale set in EllesmereUI's options. Move the slider to choose a size of your own instead. Same as /af scale eui."])
    end)
    follow:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ns.SkinCheck(follow)
    ns.SkinText(followLabel)
    f.slider, f.scaleText, f.followEui, f.smaller, f.bigger = slider, scaleText, follow, smaller, bigger
end

local function RegisterSettings()
    local f = CreateFrame("Frame", "AltsForeverOptionsPanel")
    -- Hidden until the Options window shows it: a new frame starts shown, so its Show()
    -- there fired no OnShow and the page came up blank until you left it and came back.
    f:Hide()
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

-- Opens Options > AddOns > Alts Forever; false if there's no page. It must run straight
-- from the player's click or command: the game blocks opening the Options window from a
-- timer (ADDON_ACTION_BLOCKED on OpenSettingsPanel, seen 2026-09-28 when this waited a
-- frame) and during combat, where it says so in chat instead. A failure is reported.
function ns.OpenSettings()
    if not (category and Settings.OpenToCategory) then return false end
    if InCombatLockdown() then
        ns.Print(L["The options can't be opened during combat."])
        return true
    end
    local ok, err = pcall(Settings.OpenToCategory, category:GetID())
    if not ok and geterrorhandler then geterrorhandler()(err) end
    return true
end

-- Builds the Options page ahead of its first showing (Gamepad.lua: with the Gamepad UI on).
function ns.PrebuildOptions()
    if canvas and not canvas.built then
        canvas.built = true
        BuildCanvas(canvas)
    end
end

function ns.HasSettings() return category ~= nil end
function ns.OptionsPanel() return canvas end

-- The options menu: from the minimap button's and compartment's right-click, and the
-- overview's cog button (fromOverview: it leaves out Open overview there).
function ns.ShowOptionsMenu(owner, fromOverview)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return ns.ShowHelp() end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Alts Forever")
        -- Always there from the minimap: if the overview is already open behind other
        -- windows, this brings it to the front.
        if not fromOverview then
            root:CreateButton(L["Open overview"], function() ns.ToggleOverview(true) end)
        end
        root:CreateButton(L["Bags and bank"], function() ns.ShowBags(ns.charKey, "bags") end)
        -- Only what's switched back and forth while playing; the set-once settings are on
        -- the Options page (the owner's call, 2026-10-16: the menu had grown to 15 entries).
        -- Without a page (its registration failed), the menu has them all instead.
        root:CreateCheckbox(L["Show other rulesets and factions"], RulesetsSelected, ToggleRulesets)
        if ns.HasSettings() then
            -- Wrapped: a menu button's return value is read as a MenuResponse, and
            -- OpenSettings' true kept the menu open.
            root:CreateButton(L["Settings..."], function() ns.OpenSettings() end)
        else
            for _, entry in ipairs(SETTINGS) do
                if entry[2] ~= RulesetsSelected then
                    root:CreateCheckbox(entry[1], entry[2], function() entry[3](not entry[2]()) end)
                end
            end
        end
    end)
end

-- A character row's right-click menu in the overview.
function ns.ShowCharacterMenu(owner, key)
    local c = ns.db.chars[key]
    if not (c and MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(ns.ColoredName(key, c))
        root:CreateButton(L["Gear"], function() ns.ShowGear(key) end)
        root:CreateButton(L["Bags"], function() ns.ShowBags(key, "bags") end)
        root:CreateButton(L["Bank"], function() ns.ShowBags(key, "bank") end)
        -- The stats their upgrades are judged by: from talents, or the player's choice.
        local choices = ns.RoleChoices(c)
        if choices then
            local roles = root:CreateButton(L["Upgrade role"])
            roles:CreateRadio(L["Automatic (%s)"]:format(ns.RoleName(ns.AutoRole(c))),
                function() return not c.role end, function() ns.SetRole(key, nil) end)
            for _, role in ipairs(choices) do
                roles:CreateRadio(ns.RoleName(role), function() return c.role == role end,
                    function() ns.SetRole(key, role) end)
            end
        end
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

-- True while a button collector holds the button (EllesmereUI's tray, MinimapButtonButton
-- or any other that moved it off the minimap): it places the button itself, so dragging it
-- round the minimap edge would fight it (the owner's report, 2026-09-29; as in Keystance).
local function Collected()
    return mmButton ~= nil and mmButton:GetParent() ~= Minimap
end
ns.MinimapButtonCollected = Collected

local function ButtonTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Alts Forever")
    GameTooltip:AddLine(L["Click: open the overview"], 1, 1, 1)
    GameTooltip:AddLine(L["Right-click: options"], 1, 1, 1)
    if not Collected() then GameTooltip:AddLine(L["Drag: move around the minimap"], 1, 1, 1) end
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
        -- The menu belongs to UIParent, not the button: EllesmereUI's minimap tray hides
        -- itself (and this button) on any left press outside it, and a menu closes with
        -- its owner, so every click on the menu only closed it. It opens at the cursor.
        if button == "RightButton" then ns.ShowOptionsMenu(UIParent) else ns.ToggleOverview() end
    end)
    b:SetScript("OnEnter", ButtonTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnDragStart", function(self)
        if not Collected() then self:SetScript("OnUpdate", FollowCursor) end
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    mmButton = b
    Place(ns.db.minimapAngle or DEFAULT_ANGLE)
end

function ns.SetMinimapButton(on)
    ns.db.minimapHidden = not on or nil
    if on then ns.CreateMinimapButton() end
    -- Show and Hide rather than SetShown: MinimapButtonButton hooks those two to lay its
    -- grid out again, so hiding the button doesn't leave a gap there.
    if mmButton then
        if on then mmButton:Show() else mmButton:Hide() end
    end
end

---------------------------------------------------------------------------
-- Data broker: a launcher for display addons such as Bazooka, Titan Panel or ChocolateBar
-- (a player's request, 2026-10-15), with the minimap button's clicks and tooltip. We
-- embed no libraries: the launcher is made only if a display addon has loaded
-- LibDataBroker-1.1, checked at PLAYER_LOGIN, when every addon has loaded. Hiding the
-- minimap button doesn't touch it.
---------------------------------------------------------------------------
local BROKER = "Alts Forever"

function ns.StartBroker()
    local ldb = type(LibStub) == "table" and LibStub.GetLibrary and LibStub:GetLibrary("LibDataBroker-1.1", true)
    if not ldb or ldb:GetDataObjectByName(BROKER) then return end
    ldb:NewDataObject(BROKER, {
        type = "launcher",
        label = BROKER,
        icon = ICON,
        OnClick = function(_, button)
            if button == "RightButton" then ns.ShowOptionsMenu(UIParent) else ns.ToggleOverview() end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("Alts Forever")
            tt:AddLine(L["Click: open the overview"], 1, 1, 1)
            tt:AddLine(L["Right-click: options"], 1, 1, 1)
        end,
    })
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
