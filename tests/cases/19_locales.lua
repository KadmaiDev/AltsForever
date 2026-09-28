-- Tests: translations. Loaded by tests/run.lua.
LOCALE_FILES = { "Locale_deDE.lua", "Locale_esES.lua", "Locale_frFR.lua", "Locale_ptBR.lua", "Locale_zhCN.lua", "Locale_zhTW.lua" }

-- The %-placeholders in a string, in order ("%s", "%d", "%.1f").
function placeholders(s)
    local list = {}
    for p in s:gmatch("%%[%-%d%.]*[sdf]") do list[#list + 1] = p end
    return table.concat(list, " ")
end

test("every language translates every string, with the same placeholders in the same order", function()
    local used = {}
    for _, file in ipairs(FILES) do
        if not file:find("^Locale") then
            for key in assert(io.open(file)):read("*a"):gmatch('L%["(.-)"%]') do used[key] = true end
        end
    end
    for _, file in ipairs(LOCALE_FILES) do
        local have = {}
        for line in io.lines(file) do
            local key, value = line:match('^L%["(.-)"%] = "(.*)"$')
            if key then
                assert(used[key], file .. ": translates text the addon no longer uses: " .. key)
                eq(placeholders(value), placeholders(key), file .. ": placeholders for '" .. key .. "'")
                have[key] = true
            end
        end
        for key in pairs(used) do assert(have[key], file .. ": missing a translation for: " .. key) end
    end
end)

test("no English text reaches the player without going through the translation table", function()
    -- Text handed straight to a tooltip, label, menu or chat message must be L["..."].
    local sinks = { "AddLine%(", "AddDoubleLine%(", "SetText%(", "Print%(", "print%(",
        "CreateButton%(", "CreateCheckbox%(", "CreateTitle%(", "title = " }
    local allowed = { ["Alts Forever"] = true } -- the addon's name
    for _, file in ipairs(FILES) do
        if not file:find("^Locale") then
            local n = 0
            for line in io.lines(file) do
                n = n + 1
                local code = line:gsub("%-%-.*$", "")
                for _, sink in ipairs(sinks) do
                    for literal in code:gmatch(sink .. '%s*"([^"]*)"') do
                        local plain = literal:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[%s:]+$", "")
                        if plain:find("%a%a") and not allowed[plain] then
                            error(file .. ":" .. n .. ": untranslated text: " .. literal)
                        end
                    end
                end
            end
        end
    end
end)

test("on a German client the addon speaks German", function()
    wow.locale = "deDE"
    wow.load(FILES)
    wow.locale = nil -- the language files read it once, at load
    wow.now = NOW
    wow.login(overviewAlts())
    SlashCmdList.ALTSFOREVER("help")
    assert(table.concat(wow.printed, "\n"):find("öffnet die Übersicht", 1, true), "help in German")
    SlashCmdList.ALTSFOREVER("")
    local row = overviewRows()[3] -- High
    row.scripts.OnEnter(row)
    local text = textOf(GameTooltip.lines)
    assert(text:find("Stufe 40", 1, true), "row tooltip in German\n" .. text)
    assert(text:find("Ausgeruht", 1, true), text)
end)

test("on an English client nothing is translated", function()
    wow.load(FILES)
    wow.login(nil)
    SlashCmdList.ALTSFOREVER("help")
    assert(table.concat(wow.printed, "\n"):find("opens the overview", 1, true))
end)
