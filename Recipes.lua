-- Alts Forever recipes: browse any character's professions in a window made to look like the
-- game's own profession window (owner's request, 2026-11-10; the game's window opens another
-- character's profession only while they're online). Built from what the profession scan
-- stores (Professions.lua): each character's known recipes with the colour they had for them
-- (c.recipes), the skill that was read at (c.recipesAt), and account-wide recipe facts
-- (db.recipeInfo: grey point, name, reagents, recipe ID, category, icon, how many one craft
-- makes) and category names (db.recipeCategories).
local _, ns = ...
if ns.disabled then return end -- another copy of Alts Forever is running (Core.lua)
local L = ns.L

local pairs, ipairs, type, tonumber, floor, huge = pairs, ipairs, type, tonumber, math.floor, math.huge
local sort, wipe = table.sort, wipe
local GetItemIconByID, GetItemNameByID = C_Item.GetItemIconByID, C_Item.GetItemNameByID

local QUESTION = 134400 -- INV_Misc_QuestionMark
local TRIVIAL = 3        -- Enum.TradeskillRelativeDifficulty.Trivial

---------------------------------------------------------------------------
-- What the window shows (no UI, so it can be tested)
---------------------------------------------------------------------------

-- A character's professions: their two main ones first (as the game lists them), then the
-- rest by name. Each { name, skill, max, scanned (its window has been opened) }.
function ns.AltProfessions(c)
    local list = {}
    for name, skill in pairs(c.profs or {}) do
        list[#list + 1] = { name = name, skill = skill, max = c.profMax and c.profMax[name],
            scanned = c.recipes and c.recipes[name] ~= nil }
    end
    local rank = { [c.prof1 or ""] = 1, [c.prof2 or ""] = 2 }
    sort(list, function(a, b)
        local ra, rb = rank[a.name] or 3, rank[b.name] or 3
        if ra ~= rb then return ra < rb end
        return a.name < b.name
    end)
    return list
end

-- How many of an item the character has to craft with: bags and bank.
local function Have(c, id)
    return (c.bags and c.bags[id] or 0) + (c.bank and c.bank[id] or 0)
end
ns.RecipeHave = Have

-- ",2835:1,2840:1" as { { itemID, qty }, ... }.
local function ReagentList(text)
    local list = {}
    for id, qty in (text or ""):gmatch(",(%d+):(%d+)") do
        list[#list + 1] = { tonumber(id), tonumber(qty) }
    end
    return list
end

-- How many times the character could make it from their bags and bank (0 if not at all, nil
-- with no reagents known).
local function Craftable(c, reagents)
    if #reagents == 0 then return nil end
    local n = huge
    for _, r in ipairs(reagents) do
        local can = floor(Have(c, r[1]) / r[2])
        if can < n then n = can end
    end
    return n
end

-- The recipe's colour for the character: the one the game gave when they last opened the
-- profession (0 orange, 1 yellow, 2 green, 3 grey); grey once their skill has reached the
-- grey point; nil if neither is known (saved before the colours were).
local function Colour(c, prof, value, grey)
    local skill = c.profs and c.profs[prof]
    if grey and skill and skill >= grey then return TRIVIAL end
    if type(value) == "number" and value >= 0 and value <= TRIVIAL then return value end
    return nil
end

local function ByName(a, b)
    if a.lname ~= b.lname then return a.lname < b.lname end
    return a.name < b.name
end

local function ByOrder(a, b)
    if a.order ~= b.order then return a.order < b.order end
    return a.name < b.name
end

-- The character's recipes in a profession, as the window lists them: categories in the
-- game's order, recipes by name. `search` (lower case) narrows by recipe name; `filters`:
-- { craftable = only ones they have the materials for, skillups = only ones not grey }.
-- Returns the categories, or nil if the profession hasn't been scanned, and true as a second
-- value if any recipe was read before categories were recorded. Each category:
-- { name, order, recipes = { { lname, name, colour, count, item, icon, made, recipeID,
-- reagents = { { itemID, qty } }, grey } } }.
function ns.RecipeBook(c, prof, search, filters)
    local known = c.recipes and c.recipes[prof]
    if not known then return nil end
    local info = ns.db.recipeInfo and ns.db.recipeInfo[prof] or {}
    local cats = ns.db.recipeCategories or {}
    local items = {}
    for id, lname in pairs(c.crafts and c.crafts[prof] or {}) do
        if type(lname) == "string" then items[lname] = id end
    end
    local byCat, list, old = {}, {}, false
    for lname, value in pairs(known) do
        if not search or search == "" or lname:find(search, 1, true) then
            local grey, name, reagentText, recipeID, catID, icon, made = ns.ParseRecipeInfo(info[lname])
            if not catID then old = true end
            local reagents = ReagentList(reagentText)
            local item = items[lname]
            local r = { lname = lname, name = name or lname, colour = Colour(c, prof, value, grey),
                count = Craftable(c, reagents), item = item, recipeID = recipeID, made = made,
                icon = icon or (item and GetItemIconByID(item)) or QUESTION, reagents = reagents, grey = grey }
            local keep = not (filters and filters.craftable and not (r.count and r.count > 0))
                and not (filters and filters.skillups and r.colour == TRIVIAL)
            if keep then
                -- Filed under the game's category; with none known yet, under "Other", last.
                local key = catID and cats[catID] and catID or 0
                local cat = byCat[key]
                if not cat then
                    local order, catName = (cats[key] or ""):match("^(%-?%d+);(.+)$")
                    cat = { name = catName or L["Other"], order = tonumber(order) or huge, recipes = {} }
                    byCat[key] = cat
                    list[#list + 1] = cat
                end
                cat.recipes[#cat.recipes + 1] = r
            end
        end
    end
    sort(list, ByOrder)
    for _, cat in ipairs(list) do sort(cat.recipes, ByName) end
    return list, old
end

-- Gathering professions have no recipe window (Mining has smelting): no tab for them unless
-- something was read. By skill line, so it works in every language.
local GATHERING = { [182] = true, [393] = true, [356] = true }

-- Every profession's skill line (classic IDs, as GetProfessionInfo gives them) and its icon,
-- for a profession whose character hasn't logged in since its icon was first recorded.
local ICONS = { [129] = "Spell_Holy_SealOfSacrifice", [164] = "Trade_BlackSmithing", [165] = "Trade_LeatherWorking",
    [171] = "Trade_Alchemy", [182] = "Trade_Herbalism", [185] = "INV_Misc_Food_15", [186] = "Trade_Mining",
    [197] = "Trade_Tailoring", [202] = "Trade_Engineering", [333] = "Trade_Engraving", [356] = "Trade_Fishing",
    [393] = "INV_Misc_Pelt_Wolf_01" }

-- Profession names in the player's language to skill lines, from the game (kept once every
-- name is known: profession data may not be loaded at first).
local lines
local function LineOf(prof)
    if lines then return lines[prof] end
    local map, complete = {}, true
    local ts = C_TradeSkillUI
    for line in pairs(ICONS) do
        local name = ts and ts.GetTradeSkillDisplayName and ts.GetTradeSkillDisplayName(line)
        if not issecretvalue(name) and type(name) == "string" and name ~= "" then
            map[name] = line
        else
            complete = false
        end
    end
    if complete then lines = map end
    return map[prof]
end

-- A profession's skill line and icon: as the skill scan recorded them, else from the game's
-- names and the icons above.
local function Art(prof)
    local line, icon = (ns.db.profArt and ns.db.profArt[prof] or ""):match("^(%d+);(.*)$")
    line, icon = tonumber(line), tonumber(icon) or (icon ~= "" and icon) or nil
    line = line or LineOf(prof)
    return line, icon or (line and ICONS[line] and "Interface\\Icons\\" .. ICONS[line]) or nil
end
ns.ProfessionArt = Art

-- The professions the window shows tabs for.
function ns.RecipeTabs(c)
    local list = {}
    for _, p in ipairs(ns.AltProfessions(c)) do
        if not GATHERING[Art(p.name) or 0] or (p.scanned and next(c.recipes[p.name])) then list[#list + 1] = p end
    end
    return list
end

---------------------------------------------------------------------------
-- The window, laid out as the game's profession window (Forever's own build: 673x594, a
-- rank bar, the recipe list on the left, the recipe on the right, a tab per profession down
-- the right edge) and drawn with the same art. The game's profession templates load only
-- with its window, so those pieces are rebuilt here from the same textures; the frame,
-- search box, filter button and side tabs are shared templates that are always loaded. Any
-- art a client lacks is checked for first. With EllesmereUI the art is faded for flat
-- panels, as EllesmereUI does to the game's window.
---------------------------------------------------------------------------
local CreateFrame, GameTooltip = CreateFrame, GameTooltip
local GetAtlasInfo = C_Texture and C_Texture.GetAtlasInfo
local GetItemQualityByID, GetItemInfo = C_Item.GetItemQualityByID, C_Item.GetItemInfo
local RequestLoad = C_Item.RequestLoadItemDataByID
local max, min = math.max, math.min

local WIDTH, HEIGHT = 673, 594
local LIST_W, LIST_TOP = 304, -72
local ROW_H, CAT_H, SPACING, INDENT = 20, 25, 1, 10
local AREA_H = HEIGHT + LIST_TOP - 5 - 35 - 5 -- the list's scrolling area
local ROWS = floor(AREA_H / (ROW_H + SPACING)) + 1
local BAR_W, BAR_FRAME_W = 441, 453
local SLOTS, SLOT_ROWS = 8, 4
local NAME_TRIES = 5

-- The profession art's texture kit, by skill line (the game's Enum.Profession names).
local KITS = { [129] = "FirstAid", [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy",
    [182] = "Herbalism", [185] = "Cooking", [186] = "Mining", [197] = "Tailoring", [202] = "Engineering",
    [333] = "Enchanting", [356] = "Fishing", [393] = "Skinning" }

-- A recipe's colour: the game's skill-up arrows, the classic colours, and what they mean.
local SKILL_ATLAS = { [0] = "Professions-Icon-Skill-High", [1] = "Professions-Icon-Skill-Medium",
    [2] = "Professions-Icon-Skill-Low" }
local HEX = { [0] = "ff8040", [1] = "ffff00", [2] = "40bf40", [3] = "808080" }
local MEANING = { [0] = L["Always a skill-up"], [1] = L["Usually a skill-up"], [2] = L["Sometimes a skill-up"],
    [3] = L["No skill-up"] }

local frame
local shownKey, shownProf, selected
local searchText = ""
local filters = {}
local collapsed = {} -- category names folded away (this session)
local entries = {}   -- what the list shows: categories, each followed by its recipes unless folded
local offset = 0     -- the first entry shown
local nameTries = 0
local Fill

local function HasAtlas(name)
    return GetAtlasInfo ~= nil and name ~= nil and GetAtlasInfo(name) ~= nil
end

local function Atlas(tex, name, size)
    if not HasAtlas(name) then return false end
    tex:SetAtlas(name, size)
    return true
end

local function Flat() return ns.SkinFlat and ns.SkinFlat() or false end

local kitNames
local function KitOf(prof)
    local line = Art(prof)
    if not line then return nil end
    local ts = C_TradeSkillUI
    local ok, info = pcall(ts and ts.GetProfessionInfoBySkillLineID or error, line)
    if ok and type(info) == "table" and type(info.profession) == "number" and type(Enum.Profession) == "table" then
        if not kitNames then
            kitNames = {}
            for name, value in pairs(Enum.Profession) do kitNames[value] = name end
        end
        if kitNames[info.profession] then return kitNames[info.profession] end
    end
    return KITS[line]
end

local function InColour(text, colour)
    return colour and HEX[colour] and ("|cff" .. HEX[colour] .. text .. "|r") or text
end

-- What a recipe's colour means for the character, and when it turns grey.
local function ColourLines(tt, r)
    if r.colour then tt:AddLine(InColour(MEANING[r.colour], r.colour)) end
    if r.grey and r.colour ~= 3 then tt:AddLine(L["Grey at %d"]:format(r.grey), 0.5, 0.5, 0.5) end
end

---------------------------------------------------------------------------
-- Rank bar: the game's frame and trough, and its fill as the game draws it: the profession's
-- fill art played once as a flipbook (2 columns, rows of 34, 2 seconds) and shown through a
-- mask cut to the skill, so it comes to rest exactly where the game's own bar does. The
-- animation is the game's (no script runs while it plays); it plays when the bar changes.
---------------------------------------------------------------------------
local function SetRank(bar, prof, skill, maxSkill, c)
    local frac = (skill and maxSkill and maxSkill > 0) and min(1, max(0, skill / maxSkill)) or 0
    local t = bar.fill
    local name = "Skillbar_Fill_Flipbook_" .. (KitOf(prof) or "")
    if not HasAtlas(name) then name = "Skillbar_Fill_Flipbook_DefaultBlue" end
    local info = HasAtlas(name) and GetAtlasInfo(name)
    local anim = bar.anim
    if info and anim then
        if bar.fillAtlas ~= name then
            bar.fillAtlas = name
            t:SetAtlas(name, false)
            local rows = max(1, floor((info.height or 34) / 34 + 0.5))
            anim.flipbook:SetFlipBookRows(rows)
            anim.flipbook:SetFlipBookColumns(2)
            anim.flipbook:SetFlipBookFrames(rows * 2)
        end
        t:SetWidth(BAR_W)
        bar.mask:SetWidth(max(1, BAR_FRAME_W * frac)) -- the game's: the bar's width x the share
        if bar.shownSkill ~= skill or bar.shownProf ~= prof then
            bar.shownSkill, bar.shownProf = skill, prof
            anim:Stop()
            anim:Play()
        end
    else
        -- Without the art (or animations): a plain fill.
        bar.fillAtlas = nil
        t:SetColorTexture(0.25, 0.5, 0.9, 0.9)
        t:SetWidth(max(1, BAR_W * frac))
    end
    t:SetShown(frac > 0)
    local text = skill and maxSkill and (TRADESKILL_NAME_RANK or "%s (%d/%d)"):format(prof, skill, maxSkill) or prof
    bar.text:SetText(text)
    bar.prof, bar.c = prof, c
end

local function RankTooltip(bar)
    local c = bar.c
    if not c then return end
    local at = c.recipesAt and c.recipesAt[bar.prof]
    local now = c.profs and c.profs[bar.prof]
    GameTooltip:SetOwner(bar, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(bar.text:GetText() or "")
    if at and now and at ~= now then
        GameTooltip:AddLine(L["Recipe colours are from when %s last opened it, at skill %d."]:format(c.name or shownKey, at), 1, 1, 1, true)
    end
    GameTooltip:Show()
end

local function MakeRankBar(f)
    local bar = CreateFrame("Frame", nil, f)
    bar:SetSize(453, 18)
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", 110, -40)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetPoint("TOPLEFT")
    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetPoint("TOPLEFT", 5, -3)
    bar.fill:SetHeight(18)
    -- The mask that shows the skill's share of the fill (the game's, else a plain one).
    if type(bar.CreateMaskTexture) == "function" and type(bar.CreateAnimationGroup) == "function" then
        -- The game's mask is 512x512 (seen in game 2026-11-10) and stays that tall: only its
        -- width follows the skill. Squeezed to the bar's height, its dark parts hid the fill.
        -- Black past its edges, as the game's XML sets it (hWrapMode/vWrapMode): set from code
        -- the art's edge repeats outwards instead, and the whole bar showed (owner, 2026-11-10).
        local mask = bar:CreateMaskTexture()
        if HasAtlas("Professions-skillbar-mask") then
            mask:SetAtlas("Professions-skillbar-mask", true, nil, nil, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        else
            mask:SetTexture("Interface\\Buttons\\WHITE8X8", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetHeight(18)
        end
        mask:SetPoint("LEFT", bar.fill, "LEFT", 1, 0)
        bar.fill:AddMaskTexture(mask)
        bar.mask = mask
        local anim = bar.fill:CreateAnimationGroup()
        anim:SetToFinalAlpha(true)
        local flipbook = anim:CreateAnimation("FlipBook")
        flipbook:SetDuration(2)
        flipbook:SetFlipBookFrameWidth(0)
        flipbook:SetFlipBookFrameHeight(0)
        anim.flipbook = flipbook
        bar.anim = anim
    end
    bar.border = bar:CreateTexture(nil, "OVERLAY")
    bar.border:SetPoint("TOPLEFT")
    bar.text = bar:CreateFontString(nil, "OVERLAY", "Number12FontOutline")
    bar.text:SetPoint("CENTER", 0, -3)
    if Flat() then
        -- EllesmereUI's flat bar: a dark trough with its thin border, white text.
        local trough = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
        trough:SetColorTexture(0.12, 0.12, 0.12, 0.85)
        trough:SetPoint("TOPLEFT", 5, -3)
        trough:SetSize(BAR_W, 18)
        local edge = CreateFrame("Frame", nil, bar)
        edge:SetAllPoints(trough)
        ns.SkinPanel(edge, { noBg = true })
        bar.text:SetTextColor(1, 1, 1)
    else
        if not Atlas(bar.bg, "Professions-skillbar-bg", true) then
            bar.bg:SetColorTexture(0, 0, 0, 0.5)
            bar.bg:SetAllPoints()
        end
        if Atlas(bar.border, "Professions-skillbar-frame", false) then bar.border:SetSize(451, 29) end
    end
    bar:EnableMouse(true)
    bar:SetScript("OnEnter", RankTooltip)
    bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ns.SkinText(bar.text)
    f.rank = bar
end

---------------------------------------------------------------------------
-- The recipe list: category headers (the game's collapsible list header) and recipe rows
-- (skill-up arrow, name, how many they could make " [n] "), drawn from a pool of rows as
-- far as the list's height allows; the mouse wheel, the slider and the page arrows scroll.
---------------------------------------------------------------------------
local AREA_W = LIST_W - 8 - 20

local function TextWidth(fs)
    local w = fs:GetStringWidth()
    return type(w) == "number" and not issecretvalue(w) and w or 0
end

local function LabelColour(fs)
    local c = PROFESSION_RECIPE_COLOR
    if c and c.GetRGB then fs:SetTextColor(c:GetRGB()) else fs:SetTextColor(1, 1, 1) end
end

local function LinkItem(id)
    local _, link = GetItemInfo(id)
    if type(link) ~= "string" or issecretvalue(link) then return end
    if not (ChatEdit_InsertLink and ChatEdit_InsertLink(link)) and ChatFrame_OpenChat then ChatFrame_OpenChat(link) end
end

local function RowEnter(row)
    local e = row.entry
    if not e or e.recipes then return end
    row.label:SetTextColor(1, 1, 1)
    row.count:SetTextColor(1, 1, 1)
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(e.name, 1, 1, 1)
    ColourLines(GameTooltip, e)
    GameTooltip:Show()
end

local function RowLeave(row)
    LabelColour(row.label)
    LabelColour(row.count)
    GameTooltip:Hide()
end

local function RowClick(row)
    local e = row.entry
    if not e then return end
    if e.recipes then
        collapsed[e.name] = not collapsed[e.name] or nil
    elseif IsModifiedClick and IsModifiedClick("CHATLINK") and e.item then
        return LinkItem(e.item)
    else
        selected = e.lname
    end
    Fill()
end

local function MakeRow(area)
    local row = CreateFrame("Button", nil, area)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- A category: the game's list header, its hover, a gold name and a +/- at the right.
    row.catBg = row:CreateTexture(nil, "BACKGROUND")
    row.catBg:SetAllPoints()
    if not Atlas(row.catBg, "common-button-list-collapseExpand") then row.catBg:SetColorTexture(1, 1, 1, 0.08) end
    row.catHover = row:CreateTexture(nil, "HIGHLIGHT")
    row.catHover:SetAllPoints()
    if Atlas(row.catHover, "common-button-list-collapseExpand") then
        row.catHover:SetBlendMode("ADD")
        row.catHover:SetAlpha(0.4)
    else
        row.catHover:SetColorTexture(1, 1, 1, 0.08)
    end
    row.catText = row:CreateFontString(nil, "OVERLAY", "Game15Font_Shadow")
    row.catText:SetPoint("LEFT", 8, 0)
    row.catText:SetTextColor(1, 0.82, 0)
    row.toggle = row:CreateTexture(nil, "OVERLAY")
    row.toggle:SetPoint("RIGHT", -6, 0)
    -- A recipe: its skill-up arrow, name and count; the game's selected and hover art.
    row.skill = row:CreateTexture(nil, "OVERLAY")
    row.skill:SetPoint("RIGHT", row, "LEFT", 17, -1)
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight_NoShadow")
    row.label:SetPoint("LEFT", 21, 0)
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight_NoShadow")
    row.count:SetPoint("LEFT", row.label, "RIGHT")
    LabelColour(row.label)
    LabelColour(row.count)
    row.selectedTex = row:CreateTexture(nil, "OVERLAY", nil, 2)
    if Atlas(row.selectedTex, "Professions_Recipe_Active", true) then
        row.selectedTex:SetPoint("CENTER", 0, -1)
    else
        row.selectedTex:SetAllPoints()
        row.selectedTex:SetColorTexture(1, 0.82, 0, 0.15)
    end
    row.hoverTex = row:CreateTexture(nil, "HIGHLIGHT")
    if Atlas(row.hoverTex, "Professions_Recipe_Hover", true) then
        row.hoverTex:SetPoint("CENTER", 0, -1)
        row.hoverTex:SetAlpha(0.5)
    else
        row.hoverTex:SetAllPoints()
        row.hoverTex:SetColorTexture(1, 1, 1, 0.08)
    end
    row:SetScript("OnClick", RowClick)
    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", RowLeave)
    for _, fs in ipairs({ row.catText, row.label, row.count }) do ns.SkinText(fs) end
    return row
end

local function SetRow(row, e)
    row.entry = e
    local cat = e.recipes ~= nil
    for _, part in ipairs({ row.catBg, row.catHover, row.catText, row.toggle }) do part:SetShown(cat) end
    for _, part in ipairs({ row.label, row.count }) do part:SetShown(not cat) end
    if cat then
        row.catText:SetText(e.name)
        row.skill:Hide()
        row.selectedTex:Hide()
        row.hoverTex:Hide()
        local folded = collapsed[e.name]
        if not Atlas(row.toggle, folded and "common-button-list-plus" or "common-button-list-minus", true) then
            row.toggle:SetSize(16, 16)
            row.toggle:SetTexture(folded and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
        end
        return
    end
    row.label:SetText(e.name)
    row.count:SetText(e.count and e.count > 0 and (" [%d] "):format(e.count) or "")
    -- The name stops short of the row's end, so a long one is cut rather than overlapping.
    row.label:SetWidth(0)
    local room = AREA_W - INDENT - 21 - 10 - TextWidth(row.count)
    if TextWidth(row.label) > room then row.label:SetWidth(room) end
    local atlas = SKILL_ATLAS[e.colour]
    row.skill:SetShown(atlas ~= nil and Atlas(row.skill, atlas, true))
    row.selectedTex:SetShown(e.lname == selected)
    row.hoverTex:SetShown(e.lname ~= selected)
end

-- The furthest the list can scroll: the last entries just fill it.
local function MaxOffset()
    local used, k = 1, #entries
    while k >= 1 do
        local h = entries[k].recipes and CAT_H or ROW_H
        if used + h > AREA_H then break end
        used = used + h + SPACING
        k = k - 1
    end
    return k
end

local function ShowRows()
    local rows, y, n = frame.rows, -1, 0
    for i = offset + 1, #entries do
        local e = entries[i]
        local h = e.recipes and CAT_H or ROW_H
        if -y + h > AREA_H or n == #rows then break end
        n = n + 1
        local row = rows[n]
        local x = e.recipes and 0 or INDENT
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame.area, "TOPLEFT", x, y)
        row:SetSize(AREA_W - x, h)
        SetRow(row, e)
        row:Show()
        y = y - h - SPACING
    end
    for i = n + 1, #rows do rows[i]:Hide() end
    local most = MaxOffset()
    local slider = frame.slider
    slider.updating = true
    slider:SetMinMaxValues(0, max(0, most))
    slider:SetValue(offset)
    slider.updating = nil
    local scrolls = most > 0
    slider:SetShown(scrolls)
    frame.pageUp:SetShown(scrolls)
    frame.pageDown:SetShown(scrolls)
end

local function Scroll(by)
    offset = max(0, min(MaxOffset(), offset + by))
    ShowRows()
end

local function FilterMenu(_, root)
    local function Toggle(key)
        return function()
            filters[key] = not filters[key] or nil
            offset = 0
            Fill()
        end
    end
    root:CreateCheckbox(CRAFT_IS_MAKEABLE or L["Have materials"], function() return filters.craftable == true end, Toggle("craftable"))
    root:CreateCheckbox(TRADESKILL_FILTER_HAS_SKILL_UP or L["Has skill-up"], function() return filters.skillups == true end, Toggle("skillups"))
end

local function MakeList(f)
    local list = CreateFrame("Frame", nil, f)
    list:SetPoint("TOPLEFT", f, "TOPLEFT", 5, LIST_TOP)
    list:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 5, 5)
    list:SetWidth(LIST_W)
    list.bg = list:CreateTexture(nil, "BACKGROUND")
    list.bg:SetAllPoints()
    if Flat() then
        list.bg:SetColorTexture(0, 0, 0, 0.25)
    elseif not Atlas(list.bg, "Professions-background-summarylist") then
        list.bg:SetColorTexture(0, 0, 0, 0.3)
    end
    f.list = list

    -- The game's filter button (its reset cross clears the filters), the search box beside it.
    f.filterMenu = FilterMenu
    local ok, filter = pcall(CreateFrame, "DropdownButton", nil, list, "WowStyle1FilterDropdownTemplate")
    if ok and filter and type(filter.SetupMenu) == "function" and type(filter.SetDefaultCallback) == "function" then
        filter:SetupMenu(FilterMenu)
        pcall(filter.SetIsDefaultCallback, filter, function() return not (filters.craftable or filters.skillups) end)
        pcall(filter.SetDefaultCallback, filter, function()
            wipe(filters)
            offset = 0
            Fill()
        end)
        ns.SkinDropdown(filter)
    else
        filter = CreateFrame("Button", nil, list, "UIPanelButtonTemplate")
        filter:SetSize(93, 22)
        filter:SetText(FILTER or L["Filter"])
        filter:SetScript("OnClick", function(self) MenuUtil.CreateContextMenu(self, FilterMenu) end)
        ns.SkinButton(filter)
    end
    filter:SetPoint("TOPRIGHT", list, "TOPRIGHT", -8, -9)
    f.filter = filter

    local okBox, box = pcall(CreateFrame, "EditBox", "AltsForeverRecipesSearchBox", list, "SearchBoxTemplate")
    if not okBox then box = CreateFrame("EditBox", "AltsForeverRecipesSearchBox", list, "InputBoxTemplate") end
    box:SetHeight(20)
    box:SetPoint("TOPLEFT", list, "TOPLEFT", 13, -8)
    box:SetPoint("RIGHT", filter, "LEFT", -4, 0)
    box:SetAutoFocus(false)
    box:HookScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        if issecretvalue(text) then return end
        searchText = text:lower()
        offset = 0
        Fill()
    end)
    ns.SkinEditBox(box)
    f.search = box

    local area = CreateFrame("Frame", nil, list)
    area:SetPoint("TOPLEFT", list, "TOPLEFT", 8, -35)
    area:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -20, 5)
    area:EnableMouseWheel(true)
    area:SetScript("OnMouseWheel", function(_, delta) Scroll(-delta * 3) end)
    f.area = area
    f.rows = {}
    for i = 1, ROWS do f.rows[i] = MakeRow(area) end

    -- A thin slider in the gap at the right, with page arrows at either end for a controller.
    f.pageUp = ns.PageButton(list, true, function() Scroll(-(ROWS - 2)) end)
    f.pageUp:SetSize(16, 16)
    f.pageUp:SetPoint("TOPRIGHT", list, "TOPRIGHT", -2, -35)
    f.pageDown = ns.PageButton(list, false, function() Scroll(ROWS - 2) end)
    f.pageDown:SetSize(16, 16)
    f.pageDown:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -2, 5)
    local slider = CreateFrame("Slider", nil, list)
    slider:SetOrientation("VERTICAL")
    slider:SetWidth(12)
    slider:SetPoint("TOP", f.pageUp, "BOTTOM", 0, -2)
    slider:SetPoint("BOTTOM", f.pageDown, "TOP", 0, 2)
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("TOP")
    track:SetPoint("BOTTOM")
    track:SetWidth(4)
    track:SetColorTexture(1, 1, 1, 0.12)
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(8, 28)
    if Flat() then thumb:SetColorTexture(1, 1, 1, 0.6) else thumb:SetColorTexture(1, 0.82, 0, 0.8) end
    slider:SetThumbTexture(thumb)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    slider:EnableMouseWheel(true)
    slider:SetScript("OnMouseWheel", function(_, delta) Scroll(-delta * 3) end)
    slider:SetScript("OnValueChanged", function(self, value)
        if self.updating then return end
        offset = floor(value + 0.5)
        ShowRows()
    end)
    f.slider = slider
end

---------------------------------------------------------------------------
-- The recipe: its item in the game's round frame with a quality ring, its name in the
-- item's quality colour, what its colour means for the character, and the reagents as the
-- game's slots, "have/need Name" from the character's bags and bank.
---------------------------------------------------------------------------
local RING = { [0] = "gray", [1] = "white", [2] = "green", [3] = "blue", [4] = "purple", [5] = "orange",
    [6] = "artifact", [7] = "account" }

local function SlotEnter(slot)
    if not slot.item then return end
    GameTooltip:SetOwner(slot, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(slot.item)
    GameTooltip:Show()
end

local function SlotClick(slot)
    if slot.item and IsModifiedClick and IsModifiedClick("CHATLINK") then LinkItem(slot.item) end
end

local function MakeSlot(parent)
    local s = CreateFrame("Frame", nil, parent)
    s:SetSize(160, 50)
    local b = CreateFrame("Button", nil, s)
    b:SetSize(39, 39)
    b:SetPoint("LEFT", 0, 0)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    if not Atlas(b.bg, "Professions-Slot-bg") then b.bg:SetColorTexture(0, 0, 0, 0.5) end
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.frameTex = b:CreateTexture(nil, "OVERLAY")
    if Atlas(b.frameTex, "Professions-Slot-Frame", true) then b.frameTex:SetPoint("CENTER") else b.frameTex:Hide() end
    b:SetScript("OnEnter", SlotEnter)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", SlotClick)
    s.button = b
    s.name = s:CreateFontString(nil, "OVERLAY", "GameFontHighlight_NoShadow")
    s.name:SetPoint("LEFT", b, "RIGHT", 7, 0)
    s.name:SetWidth(108)
    s.name:SetJustifyH("LEFT")
    s.name:SetMaxLines(2)
    ns.SkinText(s.name)
    ns.SkinItemSlot(b)
    return s
end

local function OutputEnter(b)
    local r = b.recipe
    if not r then return end
    GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
    if r.item then
        GameTooltip:SetItemByID(r.item)
    else
        GameTooltip:AddLine(r.name, 1, 1, 1)
    end
    GameTooltip:Show()
end

local function MakeDetails(f)
    local d = CreateFrame("Frame", nil, f)
    d:SetWidth(360)
    d:SetPoint("TOPLEFT", f.list, "TOPRIGHT", 2, 0)
    d:SetPoint("BOTTOMLEFT", f.list, "BOTTOMRIGHT", 2, 0)
    d.bg = d:CreateTexture(nil, "BACKGROUND")
    d.bg:SetAllPoints()
    f.details = d

    local out = CreateFrame("Button", nil, d)
    out:SetSize(47, 47)
    out:SetPoint("TOPLEFT", d, "TOPLEFT", 28, -28)
    out.icon = out:CreateTexture(nil, "ARTWORK")
    out.icon:SetSize(53, 53)
    out.icon:SetPoint("CENTER")
    if out.CreateMaskTexture then
        local mask = out:CreateMaskTexture()
        mask:SetAllPoints(out.icon)
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        out.icon:AddMaskTexture(mask)
    end
    out.ring = out:CreateTexture(nil, "OVERLAY")
    out.ring:SetSize(68, 68)
    out.ring:SetPoint("CENTER")
    out.count = out:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
    out.count:SetPoint("BOTTOMRIGHT", -2, 2)
    out:SetScript("OnEnter", OutputEnter)
    out:SetScript("OnLeave", function() GameTooltip:Hide() end)
    out:SetScript("OnClick", function(self)
        if self.recipe and self.recipe.item and IsModifiedClick and IsModifiedClick("CHATLINK") then LinkItem(self.recipe.item) end
    end)
    d.output = out

    d.name = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightMed2")
    d.name:SetPoint("TOPLEFT", out, "RIGHT", 14, 17)
    d.name:SetWidth(225)
    d.name:SetJustifyH("LEFT")
    d.desc = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall2")
    d.desc:SetPoint("TOPLEFT", out, "BOTTOMLEFT", -1, -12)
    d.desc:SetWidth(305)
    d.desc:SetJustifyH("LEFT")
    d.reagentsLabel = d:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    d.reagentsLabel:SetPoint("TOPLEFT", d.desc, "BOTTOMLEFT", 0, -20)
    d.reagentsLabel:SetText(PROFESSIONS_REAGENT_CONTAINER_LABEL or L["Reagents:"])
    d.slots = {}
    for i = 1, SLOTS do
        local s = MakeSlot(d)
        local col, row = floor((i - 1) / SLOT_ROWS), (i - 1) % SLOT_ROWS
        s:SetPoint("TOPLEFT", d.reagentsLabel, "BOTTOMLEFT", 1 + col * 165, -8 - row * 54)
        d.slots[i] = s
    end
    -- What there's nothing to show: not opened yet, no recipes, a search that found none.
    d.empty = d:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    d.empty:SetPoint("CENTER", 0, 20)
    d.empty:SetWidth(300)
    d.note = d:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    d.note:SetPoint("BOTTOMLEFT", 20, 14)
    d.note:SetWidth(320)
    d.note:SetJustifyH("LEFT")
    for _, fs in ipairs({ d.name, d.desc, d.reagentsLabel, d.empty, d.note }) do ns.SkinText(fs) end
end

-- Fills the recipe panel; returns true if an item name was still loading.
local function ShowRecipe(c, r)
    local d = frame.details
    local parts = { d.output, d.name, d.desc, d.reagentsLabel }
    for _, p in ipairs(parts) do p:SetShown(r ~= nil) end
    if not r then
        for _, s in ipairs(d.slots) do s:Hide() end
        return false
    end
    d.empty:Hide()
    local out = d.output
    out.recipe = r
    out.icon:SetTexture(r.item and GetItemIconByID(r.item) or r.icon)
    out.count:SetText(r.made and r.made > 1 and r.made or "")
    local quality = r.item and GetItemQualityByID(r.item)
    if issecretvalue(quality) then quality = nil end
    out.ring:SetShown(quality ~= nil and Atlas(out.ring, "auctionhouse-itemicon-border-" .. (RING[quality] or "white")))
    d.name:SetText(r.name)
    local qc = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if qc then d.name:SetTextColor(qc.r, qc.g, qc.b) else d.name:SetTextColor(1, 1, 1) end
    local desc = r.colour and InColour(MEANING[r.colour], r.colour) or ""
    if r.grey and r.colour ~= 3 then
        desc = desc .. (desc ~= "" and "|cff808080 · |r" or "") .. "|cff808080" .. L["Grey at %d"]:format(r.grey) .. "|r"
    end
    d.desc:SetText(desc)
    local loading = false
    for i, s in ipairs(d.slots) do
        local x = r.reagents[i]
        if x then
            local id, need = x[1], x[2]
            local have = Have(c, id)
            local name = GetItemNameByID(id)
            if issecretvalue(name) then name = nil end
            if not name then
                loading = true
                if RequestLoad then RequestLoad(id) end
            end
            s.button.item = id
            s.button.icon:SetTexture(GetItemIconByID(id) or QUESTION)
            s.name:SetText(((TRADESKILL_REAGENT_COUNT or "%d/%d"):format(have, need)) .. " " .. (name or ""))
            if have >= need then
                s.name:SetTextColor(1, 1, 1)
            else
                local grey = DISABLED_REAGENT_COLOR
                if grey and grey.GetRGB then s.name:SetTextColor(grey:GetRGB()) else s.name:SetTextColor(0.5, 0.5, 0.5) end
            end
            s:Show()
        else
            s.button.item = nil
            s:Hide()
        end
    end
    if #r.reagents == 0 then
        d.reagentsLabel:SetText(L["Reagents aren't known yet: open this profession on %s once."]:format(c.name or shownKey))
    else
        d.reagentsLabel:SetText(PROFESSIONS_REAGENT_CONTAINER_LABEL or L["Reagents:"])
    end
    return loading
end

---------------------------------------------------------------------------
-- Profession tabs down the right edge (the game's side tabs), and the character picker.
---------------------------------------------------------------------------
local function TabClick(tab, button, upInside)
    if upInside == false or (button and button ~= "LeftButton") then return end
    if tab.prof and tab.prof ~= shownProf then
        shownProf, selected, offset = tab.prof, nil, 0
        Fill()
    end
end

local function TabEnter(tab)
    if not tab.prof then return end
    GameTooltip:SetOwner(tab, "ANCHOR_RIGHT", -4, -4)
    GameTooltip:AddLine(tab.prof)
    GameTooltip:Show()
end

local function MakeTab(f, i)
    local ok, tab = pcall(CreateFrame, "Frame", nil, f, "LargeSideTabButtonTemplate")
    if ok and tab and type(tab.Icon) == "table" and type(tab.SetCustomOnMouseUpHandler) == "function" then
        tab:SetCustomOnMouseUpHandler(TabClick)
        if tab.SetFillToInterior then tab:SetFillToInterior(true) end
        tab:SetScript("OnEnter", TabEnter)
        tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
        tab.icon = tab.Icon
    else
        -- Without the shared template: a plain icon button in its place.
        tab = CreateFrame("Button", nil, f)
        tab:SetSize(44, 44)
        tab.icon = tab:CreateTexture(nil, "ARTWORK")
        tab.icon:SetPoint("TOPLEFT", 4, -4)
        tab.icon:SetPoint("BOTTOMRIGHT", -4, 4)
        tab.selectedTex = tab:CreateTexture(nil, "OVERLAY")
        tab.selectedTex:SetAllPoints()
        tab.selectedTex:SetColorTexture(1, 0.82, 0, 0.25)
        tab.SetChecked = function(self, on) self.selectedTex:SetShown(on) end
        tab:SetScript("OnClick", function(self) TabClick(self, "LeftButton", true) end)
        tab:SetScript("OnEnter", TabEnter)
        tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    if i == 1 then
        tab:SetPoint("TOPLEFT", f, "TOPRIGHT", 0, -60)
    else
        tab:SetPoint("TOPLEFT", f.tabs[i - 1], "BOTTOMLEFT", 0, -2)
    end
    f.tabs[i] = tab
    return tab
end

local function ShowTabs(c)
    local list = ns.RecipeTabs(c)
    for i, p in ipairs(list) do
        local tab = frame.tabs[i] or MakeTab(frame, i)
        local _, icon = Art(p.name)
        tab.prof = p.name
        tab.icon:SetTexture(icon or QUESTION)
        tab:SetChecked(p.name == shownProf)
        tab:Show()
    end
    for i = #list + 1, #frame.tabs do frame.tabs[i]:Hide() end
    return list
end

-- Characters with any profession, in the overview's order and, as there, headed by
-- ruleset and faction when you have more than one group.
local function HasProfessions(c) return c.profs and next(c.profs) ~= nil end

local function PickCharacter(owner)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        local chars = ns.db.chars
        local byRealm, byFaction = ns.GroupParts()
        local group
        for _, key in ipairs(ns.OverviewOrder()) do
            local c = chars[key]
            if HasProfessions(c) then
                if ns.overviewSplit and ns.GroupKey(c, byRealm, byFaction) ~= group then
                    if group then root:CreateDivider() end
                    group = ns.GroupKey(c, byRealm, byFaction)
                    root:CreateTitle(ns.GroupLabel(c, byRealm, byFaction))
                end
                root:CreateRadio(ns.ColoredName(key, c), function(k) return k == shownKey end,
                    function(k) ns.ShowRecipes(k, shownProf, true) end, key)
            end
        end
    end)
end

---------------------------------------------------------------------------
-- Filling it
---------------------------------------------------------------------------
local function SetTitle(text)
    frame.titleText = text
    if frame.TitleText then frame.TitleText:SetText(text) end
end

local function SetPortrait(icon)
    if frame.portraitShown and frame.SetPortraitToAsset then pcall(frame.SetPortraitToAsset, frame, icon or QUESTION) end
end

-- The profession's card behind the recipe (or the plain one), and the page art.
local function SetArt(prof)
    local d = frame.details
    if Flat() then
        d.bg:SetColorTexture(0, 0, 0, 0.25)
        return
    end
    local kit = KitOf(prof)
    if not (kit and Atlas(d.bg, "Profession-background-card-" .. kit))
        and not Atlas(d.bg, "Professions-Recipe-Background") then
        d.bg:SetColorTexture(0, 0, 0, 0.2)
    end
end

function Fill()
    if not frame then return end
    local c = shownKey and ns.db.chars[shownKey]
    if not c then return frame:Hide() end
    frame.who:SetText(ns.ShortName(shownKey, c))
    local tabs = ShowTabs(c)
    local found
    for _, p in ipairs(tabs) do if p.name == shownProf then found = p end end
    if not found then
        found = tabs[1]
        shownProf, selected, offset = found and found.name, nil, 0
        if found then
            for _, tab in ipairs(frame.tabs) do tab:SetChecked(tab.prof == shownProf) end
        end
    end
    local d = frame.details
    wipe(entries)
    local book, old
    if found then book, old = ns.RecipeBook(c, found.name, searchText, filters) end
    if found then
        SetTitle(found.name)
        SetPortrait(select(2, Art(found.name)))
        SetRank(frame.rank, found.name, found.skill, found.max, c)
        frame.rank:Show()
    else
        SetTitle(L["Professions"])
        SetPortrait(nil)
        frame.rank:Hide()
    end
    SetArt(shownProf)
    local first, chosen
    for _, cat in ipairs(book or {}) do
        entries[#entries + 1] = cat
        for _, r in ipairs(cat.recipes) do
            first = first or r
            if r.lname == selected then chosen = r end
            if not collapsed[cat.name] then entries[#entries + 1] = r end
        end
    end
    if not chosen then
        chosen = first
        selected = first and first.lname
    end
    offset = min(offset, MaxOffset())
    ShowRows()
    -- The filter button's reset cross shows while a filter is on.
    local filter = frame.filter
    if type(filter.ValidateResetState) == "function" then pcall(filter.ValidateResetState, filter) end
    local loading = ShowRecipe(c, chosen)
    local who = c.name or shownKey
    if not found then
        d.empty:SetText(L["%s has no professions."]:format(who))
    elseif not book then
        d.empty:SetText(L["%s hasn't opened %s with Alts Forever on. Open it on them once to see their recipes here."]:format(who, found.name))
    elseif not chosen then
        d.empty:SetText((searchText ~= "" or filters.craftable or filters.skillups) and L["No recipes match."]
            or L["%s knows no %s recipes."]:format(who, found.name))
    end
    d.empty:SetShown(chosen == nil)
    d.note:SetText(old and L["Open %s on %s once to sort these recipes into the game's categories and show their skill-up arrows."]:format(found.name, who) or "")
    -- Reagent names still loading: once more a second later, a few times at most.
    if loading and nameTries < NAME_TRIES and C_Timer then
        nameTries = nameTries + 1
        C_Timer.After(1, function() if frame:IsShown() then Fill() end end)
    elseif not loading then
        nameTries = 0
    end
end

local function CreateWindow()
    local ok, f = pcall(CreateFrame, "Frame", "AltsForeverRecipesFrame", UIParent, "PortraitFrameTemplate")
    if ok and type(f.TitleContainer) == "table" then
        f.TitleText = f.TitleContainer.TitleText
        f.portraitShown = true
    else
        ok, f = pcall(CreateFrame, "Frame", "AltsForeverRecipesFrame", UIParent, "BasicFrameTemplateWithInset")
        if not ok then f = CreateFrame("Frame", "AltsForeverRecipesFrame", UIParent, "BackdropTemplate") end
    end
    frame = f
    f:SetSize(WIDTH, HEIGHT)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:HookScript("OnShow", f.Raise)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    ns.TrackWindow(f, "professions", true, ns.DockToOverview)
    f:SetClampedToScreen(true)
    if not f.TitleText then
        f.TitleText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.TitleText:SetPoint("TOP", 0, -6)
    end
    -- The page behind everything, as the game's window draws it.
    if not Flat() then
        f.pageBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
        if Atlas(f.pageBg, "Profession-Background-Overview") then
            f.pageBg:SetPoint("TOPLEFT", 2, -21)
            f.pageBg:SetPoint("BOTTOMRIGHT", -2, 2)
        end
        f.page = f:CreateTexture(nil, "BACKGROUND", nil, 2)
        if Atlas(f.page, "Profession-Background-Template2", true) then f.page:SetPoint("TOPLEFT", 3, -21) end
    end
    MakeRankBar(f)
    MakeList(f)
    MakeDetails(f)
    f.tabs = {}

    -- Whose professions: the character, right of the rank bar.
    local who = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    who:SetSize(96, 22)
    who:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -38)
    who:SetScript("OnClick", PickCharacter)
    who:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Choose a character"])
        GameTooltip:Show()
    end)
    who:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ns.SkinButton(who)
    f.who = who

    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "AltsForeverRecipesFrame" end
    ns.SkinWindow(f)
    -- EllesmereUI's look has no portrait, as on the game's window with it.
    if Flat() and f.portraitShown then
        f.portraitShown = nil
        if type(f.PortraitContainer) == "table" then f.PortraitContainer:Hide() end
        if f.TitleText then f.TitleText:SetTextColor(1, 1, 1) end
    end
    f:Hide()
    f:SetPoint("CENTER")
    local sounds = SOUNDKIT or {}
    f:HookScript("OnShow", function()
        if sounds.UI_PROFESSIONS_WINDOW_OPEN then PlaySound(sounds.UI_PROFESSIONS_WINDOW_OPEN) end
        -- The rank bar's fill animation: one started while the window was hidden never runs.
        local anim = f.rank.anim
        if anim and f.rank.fillAtlas then
            anim:Stop()
            anim:Play()
        end
    end)
    f:HookScript("OnHide", function() if sounds.UI_PROFESSIONS_WINDOW_CLOSE then PlaySound(sounds.UI_PROFESSIONS_WINDOW_CLOSE) end end)
    ns.GamepadWindow(f)
    ns.ScaleWindow(f)
end

-- Opens a character's professions (at `prof`, else the one shown before or their first);
-- the same again closes it. `keep`: switch to them without closing (the character picker).
function ns.ShowRecipes(key, prof, keep)
    local c = key and ns.db.chars[key]
    if not c then return end
    if not frame then CreateWindow() end
    if frame:IsShown() and key == shownKey and (prof == nil or prof == shownProf) and not keep then
        return frame:Hide()
    end
    if key ~= shownKey then selected, offset = nil, 0 end
    shownKey = key
    if prof and prof ~= shownProf then shownProf, selected, offset = prof, nil, 0 end
    nameTries = 0
    Fill()
    if not frame:IsShown() then
        ns.PlaceWindow(frame)
        frame:Show()
    end
end

-- The overview's button: the window on the character you're on, or if they have no
-- professions the first character who has; again closes it.
function ns.ToggleRecipes()
    if frame and frame:IsShown() then return frame:Hide() end
    local chars = ns.db.chars
    local key = ns.charKey
    if not (chars[key] and HasProfessions(chars[key])) then
        key = nil
        for _, k in ipairs(ns.OverviewOrder()) do
            if HasProfessions(chars[k]) then
                key = k
                break
            end
        end
    end
    ns.ShowRecipes(key or ns.charKey)
end

-- A profession scan, bag change or sync while it's open: shown again.
function ns.RecipesChanged()
    if frame and frame:IsShown() then Fill() end
end

-- For tests: the window, if made.
function ns.RecipesWindow() return frame end
