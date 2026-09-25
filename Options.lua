-- Alts Forever options: everything the slash commands do, by clicking. The minimap's
-- addon compartment entry (click: overview, right-click: options menu), the same menu
-- from the overview's cog button, "Forget" on a character row's right-click menu, and a
-- page under Options > AddOns. Menus and pop-ups are only built when clicked.
local _, ns = ...

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

StaticPopupDialogs = StaticPopupDialogs or {}
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

---------------------------------------------------------------------------
-- Menus
---------------------------------------------------------------------------
local function SkillupsSelected() return ns.SkillupsOn() end
local function ToggleSkillups() ns.SetSkillups(not ns.SkillupsOn()) end

-- The options menu: from the compartment's right-click and the overview's cog button.
function ns.ShowOptionsMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return ns.ShowHelp() end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Alts Forever")
        root:CreateButton("Open overview", function() ns.ToggleOverview(true) end)
        root:CreateCheckbox("Show skill-up details", SkillupsSelected, ToggleSkillups)
        root:CreateButton("Show mail expiry in chat", function() ns.RunCommand("mail") end)
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
            StaticPopup_Show("ALTSFOREVER_FORGET", c.name or key, nil, key)
        end)
        if key == ns.charKey then
            forget:SetEnabled(false)
            root:CreateTitle(GREY .. "(the character you're on)|r")
        end
    end)
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

---------------------------------------------------------------------------
-- Options > AddOns page
---------------------------------------------------------------------------
local function RegisterSettings()
    local category = Settings.RegisterVerticalLayoutCategory("Alts Forever")
    local setting = Settings.RegisterProxySetting(category, "ALTSFOREVER_SKILLUPS", Settings.VarType.Boolean,
        "Show skill-up details", true, SkillupsSelected, ns.SetSkillups)
    Settings.CreateCheckbox(category, setting,
        "In Can craft, on materials (Skill-ups) and in the overview's row tooltips. Same as /af skillups.")
    if CreateSettingsButtonInitializer and SettingsPanel and SettingsPanel.GetLayout then
        SettingsPanel:GetLayout(category):AddInitializer(CreateSettingsButtonInitializer(
            "Overview", "Open overview", function() ns.ToggleOverview(true) end,
            "Every character at a glance. Right-click a character there to forget them. Same as /af.", true))
    end
    Settings.RegisterAddOnCategory(category)
end

function ns.StartOptions()
    if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
    -- The settings API is undocumented on Forever: report a failure, but keep the addon going.
    local ok, err = pcall(RegisterSettings)
    if not ok and geterrorhandler then geterrorhandler()(err) end
end
