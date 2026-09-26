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
