-- A small fake of the WoW client API, just enough to load Alts Forever outside the game.
-- It checks the addon's logic and wiring, not how anything looks on screen.
local M = {}

-- A secret value. Tests may swap in a plain number; load() puts this back.
local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
M.SECRET = SECRET

-- Events this fake client knows; registering anything else throws, like Forever does.
local KNOWN_EVENTS = {
    ADDON_LOADED = true, PLAYER_LOGIN = true, PLAYER_LOGOUT = true,
    BAG_UPDATE = true, BAG_UPDATE_DELAYED = true, BAG_CONTAINER_UPDATE = true,
    PLAYER_EQUIPMENT_CHANGED = true,
    BANKFRAME_OPENED = true, BANKFRAME_CLOSED = true,
    MAIL_SHOW = true, MAIL_CLOSED = true, MAIL_INBOX_UPDATE = true,
    MAIL_SEND_SUCCESS = true, MAIL_FAILED = true,
    PLAYER_MONEY = true,
    PLAYER_XP_UPDATE = true, UPDATE_EXHAUSTION = true, PLAYER_LEVEL_UP = true, PLAYER_UPDATE_RESTING = true,
    ZONE_CHANGED_NEW_AREA = true, HEARTHSTONE_BOUND = true, PLAYER_AVG_ITEM_LEVEL_UPDATE = true,
    PLAYER_ENTERING_WORLD = true, UPDATE_INVENTORY_DURABILITY = true,
    SKILL_LINES_CHANGED = true, TRADE_SKILL_SHOW = true, TRADE_SKILL_LIST_UPDATE = true,
    TRADE_SKILL_DATA_SOURCE_CHANGED = true, TRADE_SKILL_CLOSE = true, NEW_RECIPE_LEARNED = true,
    TIME_PLAYED_MSG = true, UNIT_NAME_UPDATE = true,
}

-- Resets every global and loads the addon files fresh. Returns the addon namespace.
function M.load(files)
    M.bags = {}        -- [bagID] = { size = n, [slot] = { id = itemID, count = n } }
    M.inventory = {}   -- [invSlot] = itemID
    M.inbox = {}       -- [mailIndex] = { { itemID, count }, ... } (attachments by slot)
    M.outbox = {}      -- [attachSlot] = { itemID, count }
    M.money = 0        -- copper
    M.profs = {}       -- { { name, skill }, ... } in GetProfessions() order
    M.itemClass = {}   -- [itemID] = classID (9 = recipe)
    M.itemNames = {}   -- [itemID] = name
    -- The open profession window: which profession, and every recipe in it. A recipe
    -- is { name, learned, prof?, item? (what the schematic says it makes), link? }.
    M.tradeskill = { ready = true, linked = false, guild = false, prof = nil, recipes = {} }
    M.frames = {}
    M.printed = {}
    M.postCalls = {}
    M.player = { name = "Aldric", realm = "Realm", class = "MAGE" }

    wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    M.SECRET = SECRET
    issecretvalue = function(v) return v == M.SECRET end
    M.now = nil -- set to freeze the clock
    time = function() return M.now or os.time() end
    print = function(msg) M.printed[#M.printed + 1] = msg end
    SlashCmdList = {}
    INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED = 1, 19

    Enum = {
        BagIndex = { Keyring = -2, Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4, ReagentBag = 5,
            CharacterBankTab_1 = 6, CharacterBankTab_2 = 7, CharacterBankTab_3 = 8 },
        TooltipDataType = { Item = 0 },
        ItemClass = { Recipe = 9 },
    }
    ITEM_MIN_SKILL = "Requires %s (%d)"

    GetProfessions = function()
        local idx = {}
        for i = 1, #M.profs do idx[i] = i end
        return unpack(idx)
    end
    GetProfessionInfo = function(i)
        local p = M.profs[i]
        return p[1], 136243, p[2], 150
    end
    local ts = function() return M.tradeskill end
    C_TradeSkillUI = {
        IsTradeSkillReady = function() return ts().ready end,
        IsTradeSkillLinked = function() return ts().linked end,
        IsTradeSkillGuild = function() return ts().guild end,
        GetBaseProfessionInfo = function() return ts().prof and { professionName = ts().prof } end,
        GetAllRecipeIDs = function()
            local ids = {}
            for id in pairs(ts().recipes) do ids[#ids + 1] = id end
            return ids
        end,
        GetRecipeInfo = function(id)
            local r = ts().recipes[id]
            return r and { recipeID = id, name = r.name, learned = r.learned }
        end,
        GetProfessionInfoByRecipeID = function(id)
            local r = ts().recipes[id]
            return r and { professionName = r.prof or ts().prof }
        end,
        GetRecipeSchematic = function(id)
            local r = ts().recipes[id]
            return { recipeID = id, outputItemID = r and r.item }
        end,
        GetRecipeItemLink = function(id)
            local r = ts().recipes[id]
            return r and r.link
        end,
    }

    -- /played: requests are counted. Chat windows are made below, once frames exist.
    M.playedRequests, M.playedShown = 0, {}
    RequestTimePlayed = function() M.playedRequests = M.playedRequests + 1 end

    -- Frames: real behaviour for events, scripts, text and visibility; any other
    -- widget method (sizing, anchoring, fonts...) is accepted and ignored.
    local frameMethods = {}
    local function ignored(self) return self end
    -- Child elements a template may or may not provide are nil unless set.
    local CHILDREN = { TitleText = true, CloseButton = true, Inset = true }
    -- Widget methods are capitalised (SetText, Show); lower-case names are our own
    -- fields, which are nil unless set, as in the game.
    local frameMeta = { __index = function(_, k)
        if CHILDREN[k] or type(k) ~= "string" or not k:match("^%u") then return nil end
        return frameMethods[k] or ignored
    end }
    local function newObject(kind, name)
        local f = setmetatable({ kind = kind, events = {}, scripts = {}, shown = true }, frameMeta)
        if name then _G[name] = f end
        return f
    end
    function frameMethods:RegisterEvent(event)
        if not KNOWN_EVENTS[event] then error("Attempt to register unknown event \"" .. event .. "\"") end
        self.events[event] = true
    end
    function frameMethods:UnregisterEvent(event) self.events[event] = nil end
    function frameMethods:IsEventRegistered(event) return self.events[event] == true end
    function frameMethods:SetScript(script, fn)
        self.scripts[script] = fn
        if script == "OnEvent" then self.onEvent = fn end
    end
    function frameMethods:Show()
        local was = self.shown
        self.shown = true
        if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
    end
    function frameMethods:Hide()
        local was = self.shown
        self.shown = false
        if was and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function frameMethods:SetShown(v) if v then self:Show() else self:Hide() end end
    function frameMethods:SetTexture(t) self.texture = t end
    function frameMethods:SetVertexColor(r, g, b) self.tint = { r, g, b } end
    function frameMethods:IsShown() return self.shown end
    function frameMethods:SetText(text) self.text = text end
    function frameMethods:GetText() return self.text end
    function frameMethods:CreateFontString() return newObject("FontString") end
    function frameMethods:CreateTexture() return newObject("Texture") end
    CreateFrame = function(kind, name, parent, template)
        if template and M.missingTemplates[template] then error("Couldn't find inherited node \"" .. template .. "\"") end
        local f = newObject(kind, name)
        f.template = template
        M.frames[#M.frames + 1] = f
        return f
    end
    M.missingTemplates = {}

    -- Chat windows: ChatFrame1 prints "Total time played" (recorded in playedShown)
    -- when it gets TIME_PLAYED_MSG; ChatFrame2 doesn't listen for it.
    local chat = CreateFrame("ScrollingMessageFrame", "ChatFrame1")
    chat:RegisterEvent("TIME_PLAYED_MSG")
    chat:SetScript("OnEvent", function(_, _, total) M.playedShown[#M.playedShown + 1] = total end)
    CreateFrame("ScrollingMessageFrame", "ChatFrame2")
    UIParent = newObject("Frame")
    UISpecialFrames = {}

    -- The logged-in character's level, XP and whereabouts.
    M.stats = { level = 24, xp = 5700, xpMax = 10000, rested = nil, resting = false,
        zone = "Durotar", hearth = "Razor Hill", ilvl = 21.6 }
    UnitLevel = function() return M.stats.level end
    UnitXP = function() return M.stats.xp end
    UnitXPMax = function() return M.stats.xpMax end
    GetXPExhaustion = function() return M.stats.rested end
    IsResting = function() return M.stats.resting end
    GetZoneText = function() return M.stats.zone end
    GetBindLocation = function() return M.stats.hearth end
    GetAverageItemLevel = function() return M.stats.ilvl + 1, M.stats.ilvl end
    GetMaxPlayerLevel = function() return 60 end

    -- Equipped item links and durability by inventory slot.
    M.gearLinks = {}
    M.durability = {} -- [slot] = { current, max }
    GetInventoryItemLink = function(_, slot) return M.gearLinks[slot] end
    GetInventoryItemDurability = function(slot)
        local d = M.durability[slot]
        if d then return d[1], d[2] end
    end
    GetInventorySlotInfo = function(name) return 0, "empty:" .. name end
    M.modified, M.chatLinks = false, {}
    IsModifiedClick = function() return M.modified end
    HandleModifiedItemClick = function(link) M.chatLinks[#M.chatLinks + 1] = link end

    -- Like build 70009: first name and surname as two values. oneValueNames gives the
    -- older behaviour, the full name as one value.
    M.oneValueNames = false
    UnitName = function()
        local first, surname = M.player.name:match("^(%S+) (.+)$")
        if first and not M.oneValueNames then return first, surname end
        return M.player.name
    end
    UnitClass = function() return "Mage", M.player.class end
    UnitFactionGroup = function() return "Alliance" end
    GetNormalizedRealmName = function() return M.player.realm end
    GetRealmName = function() return M.player.realm end
    UpdateAddOnMemoryUsage = function() end
    GetAddOnMemoryUsage = function() return 12.5 end

    local function slotData(bag, slot) return M.bags[bag] and M.bags[bag][slot] end
    C_Container = {
        GetContainerNumSlots = function(bag) return M.bags[bag] and M.bags[bag].size or 0 end,
        GetContainerItemID = function(bag, slot) local s = slotData(bag, slot) return s and s.id end,
        GetContainerItemInfo = function(bag, slot)
            local s = slotData(bag, slot)
            return s and { itemID = s.id, stackCount = s.count }
        end,
        ContainerIDToInventoryID = function(bag)
            if bag >= 1 and bag <= 5 then return 30 + bag end
            error("invalid bag")
        end,
    }

    local locMethods = {}
    function locMethods:SetBagAndSlot(bag, slot) self.bag, self.slot = bag, slot end
    ItemLocation = { CreateEmpty = function() return setmetatable({}, { __index = locMethods }) end }

    C_Item = {
        GetStackCount = function(loc) return slotData(loc.bag, loc.slot).count end,
        GetItemInfoInstant = function(item)
            local id = type(item) == "number" and item or tonumber(item:match("item:(%d+)"))
            return id, nil, nil, nil, "icon:" .. id, M.itemClass[id]
        end,
        GetItemNameByID = function(id) return M.itemNames[id] end,
        GetItemIconByID = function(id) return id == 5762 and 133652 or nil end,
    }
    GetInventoryItemID = function(_, slot) return M.inventory[slot] end

    GetInboxNumItems = function() return #M.inbox, #M.inbox end
    -- A mail is its attachments by slot, plus optional money, days (left), returned
    -- and canReply (false for auction house / NPC mail).
    GetInboxHeaderInfo = function(i)
        local mail, n = M.inbox[i], 0
        for k in pairs(mail) do if type(k) == "number" then n = n + 1 end end
        return nil, nil, "Sender", "Subject", mail.money or 0, 0, mail.days or 30, n,
            nil, mail.returned, nil, mail.canReply ~= false
    end
    GetInboxItem = function(i, a)
        local item = M.inbox[i][a]
        if item then return "Item", item[1], nil, item[2] end
    end
    GetSendMailItem = function(i)
        local item = M.outbox[i]
        if item then return "Item", item[1], nil, item[2] end
    end
    SendMail = function() end
    M.outboxMoney = 0
    GetSendMailMoney = function() return M.outboxMoney end
    M.timers = {}
    C_Timer = { After = function(_, fn) M.timers[#M.timers + 1] = fn end }
    GetMoney = function() return M.money end
    C_CurrencyInfo = {
        GetCoinTextureString = function(copper, height)
            M.coinHeight = height
            return copper .. "c"
        end,
    }
    GameTooltipText = { GetFont = function() return "font", 13 end }

    -- The money buttons at the bottom of the bags, which can be hovered.
    local buttonMethods = {}
    function buttonMethods:HookScript(script, fn)
        local prev = self.scripts[script]
        self.scripts[script] = function(...)
            if prev then prev(...) end
            fn(...)
        end
    end
    function buttonMethods:GetParent() return self.parent end
    function buttonMethods:Enter() if self.scripts.OnEnter then self.scripts.OnEnter(self) end end
    function buttonMethods:Leave() if self.scripts.OnLeave then self.scripts.OnLeave(self) end end
    function M.button(name)
        _G[name] = setmetatable({ scripts = {}, parent = { name = name .. "Parent" } }, { __index = buttonMethods })
        return _G[name]
    end
    M.button("ContainerFrameCombinedBagsGoldButton")
    M.button("ContainerFrame1MoneyFrameCopperButton")
    BankPanelGoldButton = nil
    hooksecurefunc = function(name, hook)
        local orig = _G[name]
        _G[name] = function(...)
            orig(...)
            hook(...)
        end
    end

    C_ClassColor = {
        GetClassColor = function(class)
            return { WrapTextInColorCode = function(_, s) return "[" .. class .. "]" .. s end }
        end,
    }

    TooltipDataProcessor = {
        AddTooltipPostCall = function(kind, fn) M.postCalls[#M.postCalls + 1] = { kind = kind, fn = fn } end,
    }
    GameTooltip = M.tooltip()
    ItemRefTooltip = M.tooltip()

    AltsForeverDB = nil
    AltsForeverFrame = nil
    local ns = {}
    for _, file in ipairs(files) do
        assert(loadfile(file))("AltsForever", ns)
    end
    return ns
end

function M.tooltip()
    return {
        lines = {},
        link = nil,
        AddDoubleLine = function(self, l, r) self.lines[#self.lines + 1] = { l, r } end,
        AddLine = function(self, text) self.lines[#self.lines + 1] = { text } end,
        IsForbidden = function() return false end,
        SetOwner = function(self, owner) self.owner, self.lines, self.shown = owner, {}, false end,
        GetOwner = function(self) return self.owner end,
        SetHyperlink = function(self, link) self.hyperlink = link end,
        IsShown = function(self) return self.shown end,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown, self.owner = false, nil end,
        ClearAllPoints = function(self) self.point = nil end,
        SetPoint = function(self, point, rel, relPoint) self.point = { point, rel, relPoint } end,
        AddLine = function(self, text) self.lines[#self.lines + 1] = { text } end,
        GetItem = function(self) return nil, self.link end,
    }
end

function M.fire(event, ...)
    for _, f in ipairs(M.frames) do
        if f.events[event] and f.onEvent then f.onEvent(f, event, ...) end
    end
end

-- Shows an item tooltip the way TooltipDataProcessor would. `text` is the item's
-- own tooltip lines (strings), which recipe parsing reads.
function M.hover(tt, itemID, text)
    tt.lines = {}
    local data = { id = itemID }
    if text then
        data.lines = {}
        for i, t in ipairs(text) do data.lines[i] = { leftText = t } end
    end
    for _, pc in ipairs(M.postCalls) do pc.fn(tt, data) end
    return tt.lines
end

-- Registers a recipe item and returns its tooltip text. craftedReq adds the
-- crafted item's own "Requires" line, which comes first in real tooltips.
function M.recipeItem(itemID, name, prof, req, craftedReq)
    M.itemClass[itemID] = 9
    M.itemNames[itemID] = name
    local text = { name }
    if craftedReq then text[#text + 1] = "Requires " .. prof .. " (" .. craftedReq .. ")" end
    text[#text + 1] = "Use: Teaches you how to make it."
    text[#text + 1] = "Requires " .. prof .. " (" .. req .. ")"
    return text
end

function M.login(saved)
    AltsForeverDB = saved
    M.fire("ADDON_LOADED", "AltsForever")
    M.fire("PLAYER_LOGIN")
end

function M.setBag(bag, size, contents)
    local b = { size = size }
    for slot, item in pairs(contents or {}) do b[slot] = { id = item[1], count = item[2] } end
    M.bags[bag] = b
end

-- Time played arriving from the server: every frame listening for it gets the event,
-- chat windows first (they exist before any addon).
function M.timePlayed(total, thisLevel)
    M.fire("TIME_PLAYED_MSG", total, thisLevel or 0)
end

return M
