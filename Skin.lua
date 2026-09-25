-- Alts Forever skin: our windows take the look of the player's UI addon, if they run one.
--  * EllesmereUI (and its third-party skinning on for us): through its public skinning API
--    (EllesmereUI/SKINNING_API.md): backdrop, border, close button and the player's font,
--    kept in sync by EllesmereUI if they change their theme.
--  * ElvUI: through its Skins module, the same helpers ElvUI uses on Blizzard's windows
--    (HandleFrame, HandleNextPrevButton...) and its font. Fonts registered with it follow
--    the player's font changes.
-- If both are installed, EllesmereUI's look wins. Without either nothing here runs and the
-- classic look stays. Each window is skinned once, when it's first created.
local ADDON, ns = ...

local ipairs, select, pcall, type = ipairs, select, pcall, type

local skin -- EllesmereUI's skinning facade, once it hands it to us

-- ElvUI's engine and Skins module, once ElvUI has initialised (it does at login, before
-- any of our windows can be opened).
local elvE, elvS
local function Elv()
    if skin then return nil end
    if elvS then return elvE, elvS end
    local engine = _G.ElvUI
    local E = type(engine) == "table" and engine[1]
    if type(E) ~= "table" or not E.Initialized or type(E.GetModule) ~= "function" then return nil end
    local ok, S = pcall(E.GetModule, E, "Skins", true)
    if not (ok and type(S) == "table" and S.HandleFrame) then return nil end
    elvE, elvS = E, S
    return E, S
end

-- ElvUI's font and outline at the text's own size (our layout is sized for it).
local function ElvFont(fs)
    if not fs.FontTemplate then return end
    local size = fs.GetFont and select(2, fs:GetFont())
    fs:FontTemplate(nil, type(size) == "number" and size or nil)
end

-- Text in the player's chosen font. Every call is a no-op without a UI addon.
function ns.SkinText(fs)
    if not fs then return end
    if skin then
        skin.Font(fs)
    elseif Elv() then
        pcall(ElvFont, fs)
    end
end

local function SkinRegions(frame, font)
    for i = 1, select("#", frame:GetRegions()) do
        local region = select(i, frame:GetRegions())
        if region and region.GetObjectType and region:GetObjectType() == "FontString" then font(region) end
    end
end

-- ElvUI's look for an icon button: the icon's edge cropped, a thin bordered backdrop and
-- its flat hover.
local function ElvIconButton(b, icon)
    if icon and icon.SetTexCoords then icon:SetTexCoords() end
    if b.CreateBackdrop then b:CreateBackdrop() end
    if b.StyleButton then b:StyleButton(nil, true, true) end
end

local function ElvWindow(f)
    local _, S = Elv()
    -- Strips the template's art, hides the inset's border, skins the close button and
    -- gives the window ElvUI's transparent backdrop.
    S:HandleFrame(f)
    for _, b in ipairs({ f.cog, f.repButton }) do
        if b and b.GetNormalTexture then ElvIconButton(b, b:GetNormalTexture()) end
    end
    SkinRegions(f, ElvFont)
end

-- A whole window: themed backdrop and border, its close button and inset, and the text
-- it already has. Rows and cells made later call ns.SkinText themselves.
function ns.SkinWindow(f)
    if not f then return end
    if skin then
        skin.Shell(f)
        if f.CloseButton then skin.CloseButton(f.CloseButton) end
        if f.Inset then skin.Inset(f.Inset) end
        -- Icon buttons (the overview's reputation and options buttons): EllesmereUI's flat
        -- square icons with its thin border.
        for _, b in ipairs({ f.cog, f.repButton }) do
            if b and b.GetNormalTexture then skin.SquareIcon(b:GetNormalTexture(), b) end
        end
        SkinRegions(f, skin.Font)
    elseif Elv() then
        -- Guarded: a change in ElvUI must never stop our window from opening.
        pcall(ElvWindow, f)
    end
end

-- An item slot in the gear panel (ElvUI only: EllesmereUI's API has no item button style).
function ns.SkinSlot(b)
    if not skin and Elv() then pcall(ElvIconButton, b, b.icon) end
end

-- The mail window's "send to alt" arrow (ElvUI only: it restyles the mail window itself).
-- ElvUI gives the To box a bordered backdrop, so the arrow gets a small gap from it.
function ns.SkinArrow(b, anchor)
    if skin or not Elv() then return end
    pcall(function()
        elvS:HandleNextPrevButton(b, "down")
        b:ClearAllPoints()
        b:SetPoint("LEFT", anchor, "RIGHT", 3, 0)
    end)
end

-- Names are coloured once and cached; when the player's class colours change live, drop
-- the cache so names pick up the new colours.
local function Recolour()
    ns.InvalidateCache()
    if ns.RefreshOverview then ns.RefreshOverview() end
end

-- CUSTOM_CLASS_COLORS (ElvUI's custom class colours, !ClassColors) tells listeners when
-- its colours change. ElvUI creates the table during its own login setup, before ours.
ns.On("PLAYER_LOGIN", function()
    local colors = CUSTOM_CLASS_COLORS
    if type(colors) == "table" and type(colors.RegisterCallback) == "function" then
        pcall(colors.RegisterCallback, colors, Recolour)
    end
end)

if EllesmereUI and EllesmereUI.RegisterSkin then
    EllesmereUI.RegisterSkin(ADDON, function(S)
        skin = S
        if S.OnLooksChanged then S.OnLooksChanged(Recolour) end
        -- Runs at login, before our windows exist; skin any that are already open.
        for _, name in ipairs({ "AltsForeverFrame", "AltsForeverGearFrame", "AltsForeverRepFrame" }) do
            if _G[name] then ns.SkinWindow(_G[name]) end
        end
    end)
end
