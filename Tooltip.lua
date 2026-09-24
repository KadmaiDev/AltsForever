-- Alts Forever tooltip: adds a total and a per-character breakdown to item tooltips.
--
-- Other characters' data can't change during a session, so their lines are built
-- once per itemID and cached. The current character's line is memoised for the
-- last item shown, which covers the tooltip refreshing while you hover.
local _, ns = ...

local pairs, wipe = pairs, wipe
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
local names = {}
local lastId, lastVer, curCount, curText

local function ColoredName(key, c)
    local s = names[key]
    if not s then
        s = c.name or key
        if c.realm ~= ns.realm then s = s .. "-" .. (c.realm or "?") end
        local color = c.class and C_ClassColor.GetClassColor(c.class)
        if color then s = color:WrapTextInColorCode(s) end
        names[key] = s
    end
    return s
end

ns.ColoredName = ColoredName

-- Returns the character's total for an item and the right-hand text: a grey
-- breakdown then the count, so counts line up at the tooltip's right edge.
-- e.g. "[bag] 12 · [bank] 40    52"
function ns.Describe(c, id)
    local total, text = 0, nil
    for i = 1, #LOCS do
        local t = c[LOCS[i]]
        local n = t and t[id]
        if n then
            total = total + n
            local part = LABELS[i] .. " " .. n
            text = text and (text .. SEP .. part) or part
        end
    end
    if text then text = GREY .. text .. "|r    " .. total end
    return total, text
end

-- Rows are stored flat as count, left, right and kept sorted highest count first.
local function BuildOthers(id)
    local e, n, total
    local realmOnly = ns.db.realmOnly
    for key, c in pairs(ns.db.chars) do
        if key ~= ns.charKey and (not realmOnly or c.realm == ns.realm) then
            local count, text = ns.Describe(c, id)
            if count > 0 then
                if not e then e, n, total = {}, 0, 0 end
                total = total + count
                local i = n
                while i > 0 and e[i * 3 - 2] < count do
                    e[i * 3 + 1], e[i * 3 + 2], e[i * 3 + 3] = e[i * 3 - 2], e[i * 3 - 1], e[i * 3]
                    i = i - 1
                end
                e[i * 3 + 1], e[i * 3 + 2], e[i * 3 + 3] = count, ColoredName(key, c), text
                n = n + 1
            end
        end
    end
    if not e then return EMPTY end
    e.n, e.total = n, total
    return e
end

function ns.InvalidateCache()
    wipe(cache)
    wipe(names)
    cacheSize = 0
    lastId = nil
    ns.version = ns.version + 1 -- also refreshes memoised recipe lines
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
        curCount, curText = ns.Describe(ns.char, id)
    end

    local rows = e.n + (curCount > 0 and 1 or 0)
    if rows == 0 then return end
    tt:AddLine(" ")
    -- With one character the total would just repeat their count.
    if rows > 1 then
        tt:AddDoubleLine(TOTAL, e.total + curCount, 1, 0.82, 0, 1, 1, 1)
    end
    if curCount > 0 then
        tt:AddDoubleLine(ColoredName(ns.charKey, ns.char), curText, 1, 1, 1, 1, 1, 1)
    end
    for i = 1, e.n * 3, 3 do
        tt:AddDoubleLine(e[i + 1], e[i + 2], 1, 1, 1, 1, 1, 1)
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
