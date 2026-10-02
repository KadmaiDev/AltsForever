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

-- Key bindings (Bindings.xml): put on a controller button, or reach them with a macro of
-- /af or /af bags on a gamepad action bar.
BINDING_HEADER_ALTSFOREVER = "Alts Forever"
BINDING_NAME_ALTSFOREVER_OVERVIEW = L["Open overview"]
BINDING_NAME_ALTSFOREVER_BAGS = L["Bags and bank"]
function AltsForever_Binding(which)
    if which == "bags" then ns.ShowBags(ns.charKey, "bags") else ns.ToggleOverview() end
end

function ns.StartGamepad()
    -- With the Gamepad UI on, the Options page is built now, while the Options window is
    -- closed: Blizzard's navigator rebuilds an open window whenever a frame is created in
    -- it, from the creating addon's code, which can leave its bindings tainted.
    local function Prepare()
        if ns.GamepadUI() and not InCombatLockdown() then ns.PrebuildOptions() end
    end
    ns.On("INPUT_DEVICE_INTERFACE_TRANSITION", Prepare)
    Prepare()
end
