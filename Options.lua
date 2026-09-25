-- Alts Forever options: everything the slash commands do, by clicking. A minimap button
-- and the minimap's addon compartment entry (click: overview, right-click: options menu),
-- the same menu from the overview's cog button, and "Forget" on a character row's
-- right-click menu.
-- Menus and pop-ups are only built when clicked. (An Options > AddOns page was tried and
-- removed: it was the likely source of a one-off taint error on Esc, see AGENTS.md.)
local ADDON, ns = ...

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
    if not ns.db.chars[key] then return false, "No character named '" .. tostring(key) .. "'." end
    if key == ns.charKey then return false, "You can't forget the character you're logged in on." end
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
        text = "Forget %s?\n\nAlts Forever removes their items, gold, gear and recipes. They're recorded again next time you log in on them.",
        button1 = YES or "Yes",
        button2 = NO or "No",
        OnAccept = function(_, key)
            local ok, why = ns.ForgetCharacter(key)
            ns.Print(ok and ("Forgot " .. key .. ".") or why)
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
local function MinimapSelected() return ns.MinimapButtonOn() end
local function ToggleMinimap() ns.SetMinimapButton(not ns.MinimapButtonOn()) end

-- The options menu: from the compartment's right-click and the overview's cog button.
function ns.ShowOptionsMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return ns.ShowHelp() end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Alts Forever")
        -- Not when it's already open (e.g. from the overview's own cog button).
        if not ns.OverviewShown() then
            root:CreateButton("Open overview", function() ns.ToggleOverview(true) end)
        end
        root:CreateCheckbox("Show skill-up details", SkillupsSelected, ToggleSkillups)
        root:CreateCheckbox("Send mail to alts", SendToAltSelected, ToggleSendToAlt)
        root:CreateCheckbox("Show minimap button", MinimapSelected, ToggleMinimap)
        root:CreateButton("Memory use", function() ns.RunCommand("mem") end)
    end)
end

-- A character row's right-click menu in the overview.
function ns.ShowCharacterMenu(owner, key)
    local c = ns.db.chars[key]
    if not (c and MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(ns.ColoredName(key, c))
        local forget = root:CreateButton("Forget " .. (c.name or key) .. "...", function()
            ForgetDialog()
            StaticPopup_Show("ALTSFOREVER_FORGET", c.name or key, nil, key)
        end)
        if key == ns.charKey then
            forget:SetEnabled(false)
            root:CreateTitle(GREY .. "(the character you're on)|r")
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
    GameTooltip:AddLine("Click: open the overview", 1, 1, 1)
    GameTooltip:AddLine("Right-click: options", 1, 1, 1)
    GameTooltip:AddLine("Drag: move around the minimap", 1, 1, 1)
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
    GameTooltip:AddLine("Click: open the overview", 1, 1, 1)
    GameTooltip:AddLine("Right-click: options", 1, 1, 1)
    GameTooltip:Show()
end

function AltsForever_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
