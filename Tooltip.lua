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
-- The breakdown: light grey, a step softer than the white totals but readable on
-- Blizzard's see-through tooltip as well as darker UI skins.
local GREY = "|cffe0e0e0"
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
-- then the count, e.g. "[bag] 12 · [bank] 40    52"), and the breakdown's parts as
-- icon, number pairs ([bag], 12, [bank], 40) for lining up in columns.
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
            parts[#parts + 1] = LABELS[i]
            parts[#parts + 1] = n
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
-- Columns. The breakdown is laid out in columns with ns.MeasureColumns/PlaceColumns
-- (Overview.lua): each place is an icon then its number (right-aligned), and the count
-- is last, at the edge. Columns fill from the right, so the icons and numbers line up
-- down the list even when characters keep an item in a different number of places. The
-- cells and their widths are kept with the cached rows (per font) and redone only when
-- the current character's line or the font changes, so repeat hovers only place them.
---------------------------------------------------------------------------
local GAP, ICON_GAP = 8, 3

-- The item's rows as cells, yours first (the order of the lines), and the column spec;
-- rebuilt when ns.version changes (your own line).
local function Grid(e)
    local grid = e.grid
    if grid and grid.ver == ns.version then return grid end
    local places = curCount > 0 and curParts and #curParts / 2 or 0
    for i = 1, e.n * 4, 4 do places = max(places, #e[i + 3] / 2) end
    local spec = {}
    for p = 1, places do
        spec[#spec + 1] = { gap = GAP, justify = "LEFT" }           -- icon
        spec[#spec + 1] = { gap = ICON_GAP, justify = "RIGHT" }     -- its number
    end
    spec[#spec + 1] = { gap = GAP * 2, justify = "RIGHT" }          -- the count
    local function Cells(parts, count)
        local cells, offset = {}, (places - #parts / 2) * 2
        for k = 1, #parts, 2 do
            cells[offset + k] = parts[k]
            cells[offset + k + 1] = GREY .. parts[k + 1] .. "|r"
        end
        cells[places * 2 + 1] = tostring(count)
        return cells
    end
    local rows = {}
    if curCount > 0 and curParts then rows[1] = Cells(curParts, curCount) end
    for i = 1, e.n * 4, 4 do rows[#rows + 1] = Cells(e[i + 3], e[i]) end
    grid = { ver = ns.version, spec = spec, rows = rows, layouts = {} }
    e.grid = grid
    return grid
end

-- The grid's layout for a font, measured once per font (a UI addon may show the tooltip
-- in a different font from the one its lines start with). Looked up without building a
-- key, so repeat hovers are free.
local function Layout(grid, tt, font, size, flags)
    local bySize = grid.layouts[font]
    if not bySize then
        bySize = {}
        grid.layouts[font] = bySize
    end
    local byFlags = bySize[size]
    if not byFlags then
        byFlags = {}
        bySize[size] = byFlags
    end
    local layout = byFlags[flags]
    if not layout then
        layout = ns.MeasureColumns(tt, grid.rows, grid.spec, font, size, flags)
        byFlags[flags] = layout -- nil (couldn't measure) is tried again next time
    end
    return layout
end

-- What our lines in each tooltip are, so they can be placed again once the tooltip is
-- shown: UI addons such as EllesmereUI set their own font on every line then, after our
-- lines were added.
local states = {}

-- Places our columns in the font the lines have now. Returns true if the tooltip needs
-- a Show to fit them.
local function Apply(tt)
    local st = states[tt]
    if not (st and st.e and st.id == lastId and st.row) then return false end
    local fs = ns.LineText(tt, "TextLeft", st.row)
    if not (fs and fs.GetFont) then return false end
    local font, size, flags = fs:GetFont()
    if not ns.UsableFont(font, size, flags) then return false end
    local grid = Grid(st.e)
    local layout = Layout(grid, tt, font, size, flags or "")
    if not layout then return false end
    return ns.PlaceColumns(tt, st.row, grid.rows, grid.spec, layout)
end

-- After the tooltip is shown (and restyled), place again in the final font; a change
-- needs another Show so the tooltip resizes.
local reshowing = {}
local function OnShow(tt)
    if reshowing[tt] or tt:IsForbidden() then return end
    if Apply(tt) then
        reshowing[tt] = true
        pcall(tt.Show, tt)
        reshowing[tt] = nil
    end
end

local function OnCleared(tt)
    local st = states[tt]
    if st then st.e = nil end
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

    tt:AddLine(" ")
    local first = tt.NumLines and tt:NumLines() + 1
    -- With one character the total would just repeat their count.
    if rows > 1 then
        tt:AddDoubleLine(TOTAL, e.total + curCount, 1, 0.82, 0, 1, 1, 1)
    end
    if curCount > 0 then
        tt:AddDoubleLine(ColoredName(ns.charKey, ns.char), curText, 1, 1, 1, 1, 1, 1)
    end
    for i = 1, e.n * 4, 4 do
        tt:AddDoubleLine(e[i + 1], e[i + 2], 1, 1, 1, 1, 1, 1)
    end

    -- Columns only when others have it too (on your own there's nothing to line up),
    -- and only in tooltips with named lines (the game's).
    if e == EMPTY or not first then return end
    local st = states[tt]
    if not st then
        st = {}
        states[tt] = st
        if tt.HookScript then
            tt:HookScript("OnShow", OnShow)
            tt:HookScript("OnTooltipCleared", OnCleared)
        end
    end
    st.e, st.id, st.cur = e, id, curCount > 0
    st.row = first + (rows > 1 and 1 or 0)
    Apply(tt)
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
