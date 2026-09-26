-- Tests: bags. Loaded by tests/run.lua, which provides test, eq, wow, FILES and the
-- other shared helpers; helpers defined here are shared with the other files too.
---------------------------------------------------------------------------
-- EllesmereUIBags: its money display shows its own gold summary unless its gold
-- tracking is off; then ours.
function ellesmereBags(trackingOff)
    wow.withEllesmere = true
    wow.load(FILES)
    local profile = {}
    if trackingOff then profile.enableGoldTracking = false end
    EllesmereUI._bagsDB = { profile = profile }
    EUI_Bags = CreateFrame("Frame", "EUI_MainBagFrame")
    local footer = CreateFrame("Frame")
    EUI_BagMoneyFrame = CreateFrame("Frame", "EUI_BagMoneyFrame")
    EUI_BagMoneyFrame.parent = footer
    local hitbox = CreateFrame("Frame")
    hitbox.parent = footer
    hitbox:SetPoint("BOTTOMRIGHT", EUI_BagMoneyFrame, "BOTTOMRIGHT", 5, -5)
    hitbox:SetScript("OnEnter", function() end) -- EllesmereUI's own summary
    footer.children = { EUI_BagMoneyFrame, hitbox }
    wow.login({ v = 2, chars = { ["Brak Stone"] = alt("Brak Stone", "WARRIOR", { money = 5000 }) } })
    EUI_Bags.scripts.OnShow(EUI_Bags)
    return hitbox
end

test("EllesmereUIBags' money shows its own gold summary while its gold tracking is on", function()
    local hitbox = ellesmereBags(false)
    hitbox.scripts.OnEnter(hitbox)
    eq(GameTooltip:IsShown() or false, false, "ours stays out of the way")
end)

test("with EllesmereUIBags' gold tracking off, its money shows our gold across characters", function()
    local hitbox = ellesmereBags(true)
    hitbox.scripts.OnEnter(hitbox)
    eq(GameTooltip:IsShown(), true); eq(GameTooltip:GetOwner(), hitbox)
    eq(GameTooltip.lines[1][1], "Gold")
    EllesmereUI._bagsDB.profile.enableGoldTracking = nil -- turned back on: theirs again
    GameTooltip:Hide()
    hitbox.scripts.OnEnter(hitbox)
    eq(GameTooltip:IsShown(), false)
    -- Hooked once, however often the bags open.
    EllesmereUI._bagsDB.profile.enableGoldTracking = false
    EUI_Bags.scripts.OnShow(EUI_Bags)
    hitbox.scripts.OnEnter(hitbox)
    local golds = 0
    for _, l in ipairs(GameTooltip.lines) do if l[1] == "Gold" then golds = golds + 1 end end
    eq(golds, 1)
    hitbox.scripts.OnLeave(hitbox)
    eq(GameTooltip:IsShown(), false)
end)

test("ElvUI's bags: hovering the gold shows our gold across characters", function()
    wow.load(FILES)
    ElvUI_ContainerFrame = CreateFrame("Frame", "ElvUI_ContainerFrame")
    local area = CreateFrame("Button")
    ElvUI_ContainerFrame.pickupGold = area
    wow.login({ v = 2, chars = { ["Brak Stone"] = alt("Brak Stone", "WARRIOR", { money = 5000 }) } })
    wow.fire("PLAYER_ENTERING_WORLD")
    wow.fire("PLAYER_ENTERING_WORLD") -- hooked once
    area.scripts.OnEnter(area)
    eq(GameTooltip:GetOwner(), area)
    local golds = 0
    for _, l in ipairs(GameTooltip.lines) do if l[1] == "Gold" then golds = golds + 1 end end
    eq(golds, 1)
    area.scripts.OnLeave(area)
    eq(GameTooltip:IsShown(), false)
end)
