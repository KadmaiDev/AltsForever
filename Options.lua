-- Alts Forever options: everything the slash commands do, by clicking. The minimap's
-- addon compartment entry (click: overview, right-click: options menu), the same menu
-- from the overview's cog button, and "Forget" on a character row's right-click menu.
-- Menus and pop-ups are only built when clicked. (An Options > AddOns page was tried and
-- removed: it was the likely source of a one-off taint error on Esc, see AGENTS.md.)
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
