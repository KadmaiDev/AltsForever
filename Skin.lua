-- Alts Forever skin: with EllesmereUI installed (and its third-party skinning on for us),
-- our windows take the player's EllesmereUI look through its public skinning API
-- (EllesmereUI/SKINNING_API.md): backdrop, border, close button and the player's font,
-- kept in sync by EllesmereUI if they change their theme. Without it nothing here runs
-- and the classic look stays. Each window is skinned once, when it's first created.
local ADDON, ns = ...

local ipairs, select = ipairs, select

local skin -- EllesmereUI's skinning facade, once it hands it to us

-- Text in the player's chosen font. Every call is a no-op without EllesmereUI.
function ns.SkinText(fs)
    if skin and fs then skin.Font(fs) end
end

local function SkinRegions(frame)
    for i = 1, select("#", frame:GetRegions()) do
        local region = select(i, frame:GetRegions())
        if region and region.GetObjectType and region:GetObjectType() == "FontString" then skin.Font(region) end
    end
end

-- A whole window: themed backdrop and border, its close button and inset, and the text
-- it already has. Rows and cells made later call ns.SkinText themselves.
function ns.SkinWindow(f)
    if not (skin and f) then return end
    skin.Shell(f)
    if f.CloseButton then skin.CloseButton(f.CloseButton) end
    if f.Inset then skin.Inset(f.Inset) end
    SkinRegions(f)
end

if EllesmereUI and EllesmereUI.RegisterSkin then
    EllesmereUI.RegisterSkin(ADDON, function(S)
        skin = S
        -- Runs at login, before our windows exist; skin any that are already open.
        for _, name in ipairs({ "AltsForeverFrame", "AltsForeverGearFrame", "AltsForeverRepFrame" }) do
            if _G[name] then ns.SkinWindow(_G[name]) end
        end
    end)
end
