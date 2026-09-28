-- Tests: toc. Loaded by tests/run.lua, which provides test, eq, wow, FILES and the
-- other shared helpers; helpers defined here are shared with the other files too.
---------------------------------------------------------------------------
function tocFiles(path)
    local files = {}
    for line in io.lines(path) do
        line = line:gsub("\r$", "")
        if line ~= "" and not line:match("^#") then
            files[#files + 1] = line
        end
    end
    return files
end

test("both .toc files list exactly the files the tests load", function()
    for _, toc in ipairs({ "AltsForever.toc", "AltsForever_Camelot.toc" }) do
        local files = tocFiles(toc)
        eq(table.concat(files, ","), table.concat(FILES, ","), toc)
    end
end)

test("both .toc files are identical", function()
    local a = assert(io.open("AltsForever.toc")):read("*a")
    local b = assert(io.open("AltsForever_Camelot.toc")):read("*a")
    eq(a, b)
end)

test("only one copy runs: a second copy stays off, and the running copy keeps its own data", function()
    local ns1 = wow.load(FILES)
    AltsForeverDB = { v = 2, chars = { ["Real Char"] = alt("Real Char", "MAGE", {}) } }
    wow.fire("ADDON_LOADED", "AltsForever")
    local mine = AltsForeverDB
    eq(mine, ns1.db)
    local slash, click = SlashCmdList.ALTSFOREVER, AltsForever_OnAddonCompartmentClick
    local hooks = #wow.postCalls
    -- A dev copy loads next: its files, then its saved data (into the same global), then
    -- its ADDON_LOADED.
    local ns2 = {}
    for _, file in ipairs(FILES) do assert(loadfile(file))("AltsForeverDev", ns2) end
    eq(ns2.disabled, true, "the second copy stays off")
    eq(SlashCmdList.ALTSFOREVER, slash, "/af still belongs to the running copy")
    eq(AltsForever_OnAddonCompartmentClick, click, "so does the minimap menu")
    AltsForeverDB = { v = 2, chars = { ["Dev Char"] = alt("Dev Char", "MAGE", {}) } }
    wow.fire("ADDON_LOADED", "AltsForeverDev")
    eq(AltsForeverDB, mine, "the running copy's data is what gets saved")
    wow.fire("PLAYER_LOGIN")
    eq(#wow.postCalls, hooks + 1, "one set of tooltip hooks: the running copy's")
    assert(table.concat(wow.printed, "\n"):find("two copies are enabled (AltsForever and AltsForeverDev)", 1, true),
        table.concat(wow.printed, "\n"))
end)

test("every addon file stops at once in a copy that isn't running", function()
    for _, file in ipairs(FILES) do
        if file ~= "Core.lua" then
            local text = assert(io.open(file)):read("*a")
            local after = text:match("\nlocal [%w_]+, ns = %.%.%.\n([^\n]*)")
            assert(after and after:find("^if ns%.disabled then return end"), file .. ": the guard must follow the ns line")
        end
    end
end)
