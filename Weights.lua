-- Alts Forever upgrade weights window (owner, 2026-11-19, after a player asked whether the
-- weights can be configured like Pawn's): pick a role, see what each stat is worth to it,
-- and change any of them. Changes are saved for the account (db.weights[role][stat],
-- Upgrades.lua) and count for every character judged by that role; "Reset" puts a role's
-- back. Opened from a character's menu (Upgrade weights...) and /af weights [name].
local _, ns = ...
if ns.disabled then return end -- another copy of Alts Forever is running (Core.lua)
local L = ns.L

local ipairs, type, tonumber = ipairs, type, tonumber
local issecretvalue = issecretvalue or function() return false end

local WIDTH, ROW_H, COL_W, PER_COL = 540, 24, 252, 11
local GREEN = { 0.25, 1, 0.25 }
local WHITE = { 1, 1, 1 }

local win
local role -- the role shown

-- 0.55, 22, 1.5, 0.333: up to three decimals, no trailing zeros.
local function Format(v)
    local text = ("%.3f"):format(v):gsub("0+$", ""):gsub("%.$", "")
    return text
end
ns.FormatWeight = Format

-- What was typed as a number ("0,5" too, as some languages write it); nil if it isn't one.
local function Parse(text)
    text = text:gsub("^%s+", ""):gsub("%s+$", ""):gsub(",", ".")
    return tonumber(text)
end
ns.ParseWeight = Parse

local Fill

-- Takes what's in a row's box: empty puts the default back, a number from 0 to 1000 is
-- saved, anything else is put back as it was. Not while Escape is cancelling it (its
-- focus is lost on the way).
local function Commit(box)
    local stat = box.stat
    if box.cancel or not (win and role and stat) then return end
    local text = box:GetText()
    if issecretvalue(text) or type(text) ~= "string" then return Fill() end
    if text:match("^%s*$") then
        if ns.WeightChanged(role, stat) then return ns.SetWeight(role, stat, nil) end
        return Fill()
    end
    local value = Parse(text)
    if value == nil or value == ns.Weight(role, stat) or not ns.SetWeight(role, stat, value) then
        Fill() -- unchanged or refused: show what's in use
    end
end

local function RowTooltip(self)
    local row = self.row or self
    if not row.stat then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(row.label:GetText() or "")
    GameTooltip:AddLine(L["Default: %s"]:format(Format(ns.DefaultWeight(role, row.stat))), 1, 1, 1)
    if ns.WeightChanged(role, row.stat) then
        GameTooltip:AddLine(L["Changed by you. Empty the box to put the default back."], 0.25, 1, 0.25, true)
    end
    GameTooltip:Show()
end

local function MakeRow(i, stat)
    local col, line = math.floor((i - 1) / PER_COL), (i - 1) % PER_COL
    local row = CreateFrame("Frame", nil, win)
    row:SetSize(COL_W - 8, ROW_H)
    row:SetPoint("TOPLEFT", win, "TOPLEFT", 18 + col * COL_W, -72 - line * ROW_H)
    row:EnableMouse(true)
    row.stat = stat
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.label:SetWidth(COL_W - 80)
    row.label:SetJustifyH("LEFT")
    if row.label.SetWordWrap then row.label:SetWordWrap(false) end
    row.label:SetText(ns.WeightStatLabel(stat))
    ns.SkinText(row.label)
    local okBox, box = pcall(CreateFrame, "EditBox", nil, row, "InputBoxTemplate")
    if not okBox then box = CreateFrame("EditBox", nil, row) end
    box:SetSize(56, 20)
    box:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    box:SetAutoFocus(false)
    if box.SetMaxLetters then box:SetMaxLetters(8) end
    box:SetJustifyH("RIGHT")
    box.stat, box.row = stat, row
    box:SetScript("OnEnterPressed", function(self)
        Commit(self)
        self:ClearFocus()
    end)
    box:SetScript("OnEditFocusLost", Commit)
    box:SetScript("OnEscapePressed", function(self)
        self.cancel = true
        self:ClearFocus()
        self.cancel = nil
        Fill()
    end)
    -- Tab and Shift-Tab move along the boxes, so a role can be typed in one go.
    box:SetScript("OnTabPressed", function(self)
        local step = IsShiftKeyDown and IsShiftKeyDown() and -1 or 1
        local boxes = win.boxes
        local nextBox = boxes[(i - 1 + step) % #boxes + 1]
        Commit(self)
        nextBox:SetFocus()
        if nextBox.HighlightText then nextBox:HighlightText() end
    end)
    box:SetScript("OnEnter", RowTooltip)
    box:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ns.SkinEditBox(box)
    row.box = box
    return row, box
end

Fill = function()
    if not win then return end
    win.roleButton:SetText(ns.WeightRoleLabel(role))
    for _, row in ipairs(win.rows) do
        local changed = ns.WeightChanged(role, row.stat)
        local box = row.box
        box:SetText(Format(ns.Weight(role, row.stat)))
        if box.SetCursorPosition then box:SetCursorPosition(0) end
        local c = changed and GREEN or WHITE
        box:SetTextColor(c[1], c[2], c[3])
        row.label:SetTextColor(c[1], c[2], c[3])
    end
    local parent = ns.WeightParent(role)
    win.follows:SetShown(parent ~= nil)
    if parent then
        win.follows:SetText(L["Weights you haven't changed here follow %s."]:format(ns.WeightRoleLabel(parent)))
    end
    win.reset:SetEnabled(ns.RoleWeightsChanged(role))
end

local function PickRole(owner)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        for _, r in ipairs(ns.WeightRoles()) do
            local text = ns.WeightRoleLabel(r)
            if ns.RoleWeightsChanged(r) then text = text .. " |cff40ff40*|r" end
            root:CreateRadio(text, function() return r == role end, function()
                role = r
                Fill()
            end)
        end
    end)
end

local function CreateWindow()
    local f = ns.NewWindow("AltsForeverWeightsFrame")
    win = f
    f:SetSize(WIDTH, 72 + PER_COL * ROW_H + 96)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:HookScript("OnShow", f.Raise)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    ns.TrackWindow(f, "weights", false)
    f:SetClampedToScreen(true)
    local title = f.TitleText or f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if not f.TitleText then title:SetPoint("TOP", 0, -6) end
    title:SetText(L["Upgrade weights"])

    f.roleLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.roleLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -40)
    f.roleLabel:SetText(L["Role"])
    ns.SkinText(f.roleLabel)
    local pick = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    pick:SetSize(380, 22)
    pick:SetPoint("LEFT", f.roleLabel, "RIGHT", 10, 0)
    pick:SetScript("OnClick", PickRole)
    pick:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Role"])
        GameTooltip:AddLine(L["Each character is judged by one role: from their talents, or the one you chose in their menu (Upgrade role)."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    pick:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ns.SkinButton(pick)
    f.roleButton = pick

    f.rows, f.boxes = {}, {}
    for i, stat in ipairs(ns.WeightStats()) do
        local row, box = MakeRow(i, stat)
        f.rows[i], f.boxes[i] = row, box
    end

    local bottom = -72 - PER_COL * ROW_H - 6
    f.follows = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.follows:SetPoint("TOPLEFT", f, "TOPLEFT", 18, bottom)
    f.follows:SetWidth(WIDTH - 36)
    f.follows:SetJustifyH("LEFT")
    f.follows:SetTextColor(0.75, 0.75, 0.75)
    ns.SkinText(f.follows)
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.hint:SetPoint("TOPLEFT", f, "TOPLEFT", 18, bottom - 16)
    f.hint:SetWidth(WIDTH - 36)
    f.hint:SetJustifyH("LEFT")
    f.hint:SetTextColor(0.75, 0.75, 0.75)
    f.hint:SetText(L["What one point of each stat is worth (ratings per 1%, as item tooltips show them); an item's score is the total. Spell damage of one school counts as a share of spell power, by class and talents. Changes count for every character judged by this role."])
    ns.SkinText(f.hint)

    local reset = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    reset:SetSize(180, 22)
    reset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 12)
    reset:SetText(L["Reset this role"])
    reset:SetScript("OnClick", function() ns.ResetWeights(role) end)
    reset:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Reset this role"])
        GameTooltip:AddLine(L["Puts every weight of this role back to Alts Forever's own."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    reset:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ns.SkinButton(reset)
    f.reset = reset

    f:SetScript("OnHide", function()
        for _, box in ipairs(f.boxes) do box:ClearFocus() end
        GameTooltip:Hide()
    end)
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "AltsForeverWeightsFrame" end
    ns.SkinWindow(f)
    f:Hide()
    ns.GamepadWindow(f)
    ns.ScaleWindow(f)
    ns.OnWeightsChanged(function() if win:IsShown() then Fill() end end)
end

-- Opens the window on a role (else the one shown last, else your own), or raises it.
function ns.ShowWeights(which)
    if not win then CreateWindow() end
    if which then
        role = which
    elseif not role then
        role = ns.char and ns.RoleOf(ns.char) or ns.WeightRoles()[1]
    end
    Fill()
    if win:IsShown() then return win:Raise() end
    ns.PlaceWindow(win)
    win:Show()
end

function ns.HideWeights()
    if win then win:Hide() end
end
