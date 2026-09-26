-- Alts Forever tooltip: adds a total and a per-character breakdown to item tooltips.
--
-- Other characters' data can't change during a session, so their lines are built
-- once per itemID and cached. The current character's line is memoised for the
-- last item shown, which covers the tooltip refreshing while you hover.
--
-- The breakdown is lined up in columns (see Align): measured once per item and kept
-- with the cached lines, so hovering an item again costs nothing extra.
local _, ns = ...

local pairs, wipe, type, pcall, floor, max = pairs, wipe, type, pcall, math.floor, math.max
local issecretvalue = issecretvalue or function() return false end
local GetItemInfoInstant = C_Item.GetItemInfoInstant

local MAX_CACHE = 500
local LOCS = { "bags", "bank", "mail", "equip" }
-- Inline icons sized to the text (":0"). Item icons have a built-in border, so
-- it's cropped off (texcoords 5-59 of 64). Bags use a bag item's icon, looked
-- up from the item so we don't depend on its file name.
local BAG_ICON_ITEM = 5762 -- Red Linen Bag
local bagIcon = C_Item.GetItemIconByID(BAG_ICON_ITEM) or "Interface\\Icons\\INV_Misc_Bag_08"
local LABELS = {
    "|T" .. bagIcon .. ":0:0:0:0:64:64:5:59:5:59|t",
    "|TInterface\\Minimap\\Tracking\\Banker:0|t",
    "|TInterface\\Minimap\\Tracking\\Mailbox:0|t",
    "|TInterface\\Icons\\INV_Shirt_White_01:0:0:0:0:64:64:5:59:5:59|t",
}
local TOTAL = "Total"
local GREY = "|cffc0c0c0"
local SEP = " · "
local EMPTY = { n = 0, total = 0 }

local cache, cacheSize = {}, 0
local names, shortNames = {}, {}
local lastId, lastVer, curCount, curText, curParts

-- An { r, g, b } colour from another addon, if it's usable.
local function Usable(c)
    return type(c) == "table" and type(c.r) == "number" and type(c.g) == "number" and type(c.b) == "number"
        and not issecretvalue(c.r)
end

local function Hex(v)
    v = v < 0 and 0 or v > 1 and 1 or v
    return ("%02x"):format(floor(v * 255 + 0.5))
end

-- A name in its class colour: the player's own class colours where their UI provides
-- them, otherwise Blizzard's.
--  1. EllesmereUI keeps its custom class colours to itself; EllesmereUI.GetClassColor is
--     how its own frames read them. It isn't part of its official skinning API, so it's
--     called guarded, and anything unexpected (an error, not a colour, or the plain white
--     it gives for unknown classes) falls through.
--  2. CUSTOM_CLASS_COLORS, the community standard (e.g. !ClassColors).
--  3. Blizzard's class colours.
local function InClassColor(class, s)
    if not class then return s end
    local eui = EllesmereUI and EllesmereUI.GetClassColor
    if eui then
        local ok, c = pcall(eui, class)
        if ok and Usable(c) and c ~= EllesmereUI._COLOR_WHITE then
            return "|cff" .. Hex(c.r) .. Hex(c.g) .. Hex(c.b) .. s .. "|r"
        end
    end
    local custom = type(CUSTOM_CLASS_COLORS) == "table" and CUSTOM_CLASS_COLORS[class]
    if Usable(custom) then
        return "|cff" .. Hex(custom.r) .. Hex(custom.g) .. Hex(custom.b) .. s .. "|r"
    end
    local color = C_ClassColor.GetClassColor(class)
    return color and color:WrapTextInColorCode(s) or s
end

local function ColoredName(key, c)
    local s = names[key]
    if not s then
        s = InClassColor(c.class, c.name or key)
        names[key] = s
    end
    return s
end

ns.ColoredName = ColoredName

-- First name only, in class colour, for narrow columns.
function ns.ShortName(key, c)
    local s = shortNames[key]
    if not s then
        s = InClassColor(c.class, (c.name or key):match("^(%S+)") or key)
        shortNames[key] = s
    end
    return s
end

-- Returns the character's total for an item, the right-hand text (a grey breakdown
-- then the count, e.g. "[bag] 12 · [bank] 40    52"), and the breakdown's parts
-- ("[bag] 12", "[bank] 40") for lining up in columns.
function ns.Describe(c, id)
    local total, text, parts = 0, nil, nil
    for i = 1, #LOCS do
        local t = c[LOCS[i]]
        local n = t and t[id]
        if n then
            total = total + n
            local part = LABELS[i] .. " " .. n
            text = text and (text .. SEP .. part) or part
            parts = parts or {}
            parts[#parts + 1] = part
        end
    end
    if text then text = GREY .. text .. "|r    " .. total end
    return total, text, parts
end

-- Rows are stored flat as count, left, right, parts and kept sorted highest count first.
local function BuildOthers(id)
    local e, n, total
    for key, c in pairs(ns.db.chars) do
        if key ~= ns.charKey then
            local count, text, parts = ns.Describe(c, id)
            if count > 0 then
                if not e then e, n, total = {}, 0, 0 end
                total = total + count
                local i = n
                while i > 0 and e[i * 4 - 3] < count do
                    e[i * 4 + 1], e[i * 4 + 2], e[i * 4 + 3], e[i * 4 + 4] = e[i * 4 - 3], e[i * 4 - 2], e[i * 4 - 1], e[i * 4]
                    i = i - 1
                end
                e[i * 4 + 1], e[i * 4 + 2], e[i * 4 + 3], e[i * 4 + 4] = count, ColoredName(key, c), text, parts
                n = n + 1
            end
        end
    end
    if not e then return EMPTY end
    e.n, e.total = n, total
    return e
end

---------------------------------------------------------------------------
-- Columns. Tooltip text isn't monospaced, so each row's breakdown is lined up by
-- measuring it in the tooltip's font and padding with transparent spacers. Columns fill
-- from the right: the count at the edge, the place before it next, and so on, so the
-- numbers and icons line up down the list even when characters keep an item in a
-- different number of places. The result is kept with the cached rows and redone only
-- when the current character's line or the font changes.
---------------------------------------------------------------------------
local GAP = 8
local fontStrings = {} -- [tooltip] = { TextLeft = { [line] = fs }, TextRight = { ... } }

-- A tooltip line's font string (e.g. GameTooltipTextLeft2), remembered so repeat hovers
-- don't build its name again. Lines are made as the tooltip first needs them, so a
-- missing one isn't remembered.
local function LineText(tt, side, line)
    local fs = fontStrings[tt]
    if not fs then
        fs = { TextLeft = {}, TextRight = {} }
        fontStrings[tt] = fs
    end
    local t = fs[side][line]
    if not t then
        local name = tt.GetName and tt:GetName()
        t = name and _G[name .. side .. line]
        fs[side][line] = t
    end
    return t
end

-- One row's right-hand text: every column padded to its widest entry.
local function Row(parts, count, font, size, flags, widths, columns, countWidth)
    local text, pending = "", 0
    local offset = columns - (parts and #parts or 0)
    for col = 1, columns do
        local pad = col > 1 and GAP or 0
        local part = col > offset and parts[col - offset]
        if part then
            local w = ns.TextWidth(font, size, flags, part)
            if not w then return nil end
            text = text .. ns.Spacer(pending + pad + widths[col] - w) .. GREY .. part .. "|r"
            pending = 0
        else
            pending = pending + pad + widths[col]
        end
    end
    local w = ns.TextWidth(font, size, flags, tostring(count))
    if not w then return nil end
    return text .. ns.Spacer(pending + GAP * 2 + countWidth - w) .. count
end

-- Measures the rows (yours included) and stores their aligned text in e.aligned (others)
-- and e.alignedCur. Returns false if the text can't be measured.
local function Align(e, curParts, font, size, flags)
    -- Columns counted from the right; a row with fewer places leaves the left ones empty.
    local columns = curParts and #curParts or 0
    for i = 1, e.n * 4, 4 do columns = max(columns, #e[i + 3]) end
    local widths, countWidth = {}, 0
    for col = 1, columns do widths[col] = 0 end
    local function Measure(parts, count)
        local offset = columns - #parts
        for i = 1, #parts do
            local w = ns.TextWidth(font, size, flags, parts[i])
            if not w then return false end
            if w > widths[offset + i] then widths[offset + i] = w end
        end
        local w = ns.TextWidth(font, size, flags, tostring(count))
        if not w then return false end
        countWidth = max(countWidth, w)
        return true
    end
    if curParts and not Measure(curParts, curCount) then return false end
    for i = 1, e.n * 4, 4 do
        if not Measure(e[i + 3], e[i]) then return false end
    end
    e.aligned = e.aligned or {}
    e.alignedCur = curParts and Row(curParts, curCount, font, size, flags, widths, columns, countWidth)
    for i = 1, e.n * 4, 4 do
        e.aligned[i] = Row(e[i + 3], e[i], font, size, flags, widths, columns, countWidth)
        if not e.aligned[i] then return false end
    end
    e.font, e.size, e.flags, e.alignVer = font, size, flags, ns.version
    return true
end

function ns.InvalidateCache()
    wipe(cache)
    wipe(names)
    wipe(shortNames)
    cacheSize = 0
    lastId = nil
    ns.version = ns.version + 1 -- also refreshes memoised recipe lines
    ns.craftVersion = ns.craftVersion + 1
end

function ns.AddLines(tt, id)
    local e = cache[id]
    if not e then
        if cacheSize >= MAX_CACHE then
            wipe(cache)
            cacheSize = 0
        end
        e = BuildOthers(id)
        cache[id] = e
        cacheSize = cacheSize + 1
    end

    if id ~= lastId or ns.version ~= lastVer then
        lastId, lastVer = id, ns.version
        curCount, curText, curParts = ns.Describe(ns.char, id)
    end

    local rows = e.n + (curCount > 0 and 1 or 0)
    if rows == 0 then return end

    -- Our lines use the tooltip's body font (its second line): lines the tooltip hasn't
    -- needed before are new font strings, which a UI addon that restyled the existing
    -- ones (EllesmereUI) hasn't reached. The columns are measured in that font.
    local body = LineText(tt, "TextLeft", 2)
    local font, size, flags
    if body and body.GetFont then font, size, flags = body:GetFont() end
    -- Lined up only when others have it too (on your own there's nothing to line up).
    -- Your line depends only on the item and ns.version, so this item's cached alignment
    -- holds until either the version or the font changes.
    local aligned = false
    if font and e ~= EMPTY then
        aligned = e.alignVer == ns.version and e.font == font and e.size == size and e.flags == flags
        if not aligned then aligned = Align(e, curCount > 0 and curParts, font, size, flags) end
    end

    tt:AddLine(" ")
    local first = tt.NumLines and tt:NumLines() + 1
    -- With one character the total would just repeat their count.
    if rows > 1 then
        tt:AddDoubleLine(TOTAL, e.total + curCount, 1, 0.82, 0, 1, 1, 1)
    end
    if curCount > 0 then
        tt:AddDoubleLine(ColoredName(ns.charKey, ns.char), aligned and e.alignedCur or curText, 1, 1, 1, 1, 1, 1)
    end
    for i = 1, e.n * 4, 4 do
        tt:AddDoubleLine(e[i + 1], aligned and e.aligned[i] or e[i + 2], 1, 1, 1, 1, 1, 1)
    end
    if font and first then
        for line = first, first + rows - (rows > 1 and 0 or 1) do
            local l, r = LineText(tt, "TextLeft", line), LineText(tt, "TextRight", line)
            if l and l.SetFont then l:SetFont(font, size, flags) end
            if r and r.SetFont then r:SetFont(font, size, flags) end
        end
    end
end

local function OnItem(tt, data)
    if (tt ~= GameTooltip and tt ~= ItemRefTooltip) or tt:IsForbidden() then return end
    local id = data and data.id
    if issecretvalue(id) then return end
    if not id then
        local _, link = tt:GetItem()
        id = link and GetItemInfoInstant(link)
    end
    if id then
        ns.AddRecipeLines(tt, id, data)
        ns.AddCraftLines(tt, id)
        ns.AddSkillupLines(tt, id)
        ns.AddLines(tt, id)
    end
end

function ns.StartTooltip()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItem)
    else
        GameTooltip:HookScript("OnTooltipSetItem", OnItem)
        ItemRefTooltip:HookScript("OnTooltipSetItem", OnItem)
    end
end
