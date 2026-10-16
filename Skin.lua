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
if ns.disabled then return end -- another copy of Alts Forever is running (Core.lua)

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
-- it already has. Rows and cells made later call ns.SkinText themselves. `opts` goes to
-- EllesmereUI's Shell (e.g. noBorder).
function ns.SkinWindow(f, opts)
    if not f then return end
    if skin then
        skin.Shell(f, opts)
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

-- A button (e.g. on the Options page): EllesmereUI's flat button, or ElvUI's.
function ns.SkinButton(b)
    if not b then return end
    if skin then
        if skin.Button then pcall(skin.Button, b) end
    elseif Elv() then
        pcall(elvS.HandleButton, elvS, b)
    end
end

-- A text box: EllesmereUI's, or ElvUI's.
function ns.SkinEditBox(e)
    if not e then return end
    if skin then
        if skin.EditBox then pcall(skin.EditBox, e) end
    elseif Elv() then
        pcall(elvS.HandleEditBox, elvS, e)
    end
end

-- A tick box: EllesmereUI's, or ElvUI's.
function ns.SkinCheck(c)
    if not c then return end
    if skin then
        if skin.Checkbox then pcall(skin.Checkbox, c) end
    elseif Elv() then
        pcall(elvS.HandleCheckBox, elvS, c)
    end
end

-- An item slot in the gear panel (ElvUI only: EllesmereUI's API has no item button style).
function ns.SkinSlot(b)
    if not skin and Elv() then pcall(ElvIconButton, b, b.icon) end
end

-- A slot in the bags window. With EllesmereUI, the look of its bags beside it (owner,
-- 2026-10-16: the two windows looked different): the icon squared by its API, a 1 px edge we
-- colour by quality (ns.SlotEdge), an outlined count, and an empty slot as its bags draw
-- theirs: the empty-slot art, squared and faded (its bags use a darkened copy of it at 35%;
-- that file isn't part of the API, so ours is Blizzard's own; a flat square looked worse,
-- owner 2026-10-16). ElvUI: its icon button, as elsewhere.
local WHITE = "Interface\\Buttons\\WHITE8X8"
local EMPTY_ART = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"
local COUNT_SIZE = 11 -- EllesmereUI's bags' default count size

local function EuiSlot(b)
    if skin.SquareIcon then skin.SquareIcon(b.icon) end
    b.border:SetTexture(nil)
    b.border:Hide()
    b.empty = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    b.empty:SetAllPoints()
    b.empty:SetTexture(EMPTY_ART)
    b.empty:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- Theirs is a dark copy (brightness 12 of 255 on average, 48 at most): at 35% it mostly
    -- darkens the square, with only a hint of the bag. Blizzard's is several times brighter,
    -- so it's tinted down to match (the bags stood out, owner 2026-10-16).
    b.empty:SetVertexColor(0.27, 0.27, 0.27)
    b.emptyAlpha = 0.35
    b.empty:Hide()
    -- Its bags' edges are one screen pixel; they take it from their pixel helper (not part
    -- of the API: read only, else 1).
    local pp = EllesmereUI and EllesmereUI.PP
    local px = type(pp) == "table" and type(pp.mult) == "number" and pp.mult > 0 and pp.mult or 1
    local edges = {}
    for i = 1, 4 do
        local t = b:CreateTexture(nil, "OVERLAY", nil, 2)
        t:SetTexture(WHITE)
        edges[i] = t
    end
    edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT"); edges[1]:SetHeight(px)
    edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(px)
    edges[3]:SetPoint("TOPLEFT"); edges[3]:SetPoint("BOTTOMLEFT"); edges[3]:SetWidth(px)
    edges[4]:SetPoint("TOPRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(px)
    b.edges = edges
    skin.Font(b.count)
    local path = b.count:GetFont()
    if type(path) == "string" then b.count:SetFont(path, COUNT_SIZE, "OUTLINE") end
end

function ns.SkinBagSlot(b)
    if skin then
        pcall(EuiSlot, b)
    elseif Elv() then
        pcall(ElvIconButton, b, b.icon)
    end
end

-- Colours a bags-window slot's edge in EllesmereUI's look; false if it hasn't got that look.
function ns.SlotEdge(b, r, g, bl, a)
    local edges = b.edges
    if not edges then return false end
    for i = 1, 4 do edges[i]:SetVertexColor(r, g, bl, a) end
    return true
end

-- The bags window, with EllesmereUI's bags in use, framed as theirs (owner, 2026-10-16: the
-- two windows looked different side by side). EllesmereUI's window shell draws its panel
-- texture with 62% black over it (sublevels -8, -7), a half-black title strip (-5) and a
-- shadowed frame (a stretched map-border atlas); their bags draw the same texture with only
-- 25% black and a 1 px dark grey line. So: the shell without its frame (noBorder, part of
-- the API), the texture at their brightness between the shell's backdrop and its title strip
-- (one texture, tinted 0.75 = 25% black), and the line. The file isn't part of the API: if
-- it ever goes, the texture draws nothing and the shell's own backdrop shows through.
local BAGS_BG = "Interface\\AddOns\\EllesmereUI\\media\\modern_blizz.png"
local LINE = 0.1 -- their bags' border colour

local function EuiBags() return skin and _G.EUI_MainBagFrame and true or false end

function ns.BagsShellOpts()
    return EuiBags() and { noBorder = true } or nil
end

function ns.SkinBagsWindow(f)
    if not EuiBags() or f.euiBg then return end
    local bg = f:CreateTexture(nil, "BACKGROUND", nil, -6)
    bg:SetAllPoints()
    bg:SetTexture(BAGS_BG)
    bg:SetVertexColor(0.75, 0.75, 0.75)
    local pp = EllesmereUI and EllesmereUI.PP
    local px = type(pp) == "table" and type(pp.mult) == "number" and pp.mult > 0 and pp.mult or 1
    local edges = {}
    for i = 1, 4 do
        local t = f:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetColorTexture(LINE, LINE, LINE, 1)
        edges[i] = t
    end
    edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT"); edges[1]:SetHeight(px)
    edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(px)
    edges[3]:SetPoint("TOPLEFT"); edges[3]:SetPoint("BOTTOMLEFT"); edges[3]:SetWidth(px)
    edges[4]:SetPoint("TOPRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(px)
    f.euiBg, f.euiLine = bg, edges
end

-- A section heading in the bags window: EllesmereUI's are light grey, not gold.
function ns.SkinHeading(fs)
    if skin then skin.Font(fs, 0.9, 0.9, 0.9) else ns.SkinText(fs) end
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
