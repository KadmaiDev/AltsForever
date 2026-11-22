-- Tests: the public functions other addons call (API.lua). Loaded by tests/run.lua.

test("AltsForever.Count: before login nil; a non-number item is the caller's mistake", function()
    wow.load(FILES)
    eq(AltsForever.API_VERSION, 1)
    eq(AltsForever.Count(2589), nil, "saved data not loaded yet")
    local ok, err = pcall(AltsForever.Count, "2589")
    eq(ok, false)
    assert(tostring(err):find("itemID must be a number", 1, true), tostring(err))
end)

test("AltsForever.Count: your characters within mail's reach, you first then most, by place", function()
    local saved = rulesetAlts()
    saved.chars["Tarn Moon"].mail = { [2589] = 3 }
    saved.chars["Tarn Moon"].equip = { [2589] = 1 }
    saved.chars["Horde Side"] = alt("Horde Side", "ROGUE", { realm = PVE, faction = "Horde", bags = { [2589] = 50 } })
    saved.chars["None Here"] = alt("None Here", "MAGE", { realm = PVE, bags = { [9001] = 2 } })
    wow.load(FILES)
    wow.now = NOW
    wow.player.realm = PVE
    wow.setBag(0, 16, { { 2589, 1 } })
    wow.login(saved)
    local total, list = AltsForever.Count(2589)
    eq(total, 1 + 14 + 4, "you, Tarn (10 bags, 3 mail, 1 worn) and Old Timer (ruleset unknown: counted); not Grim (PvP) or Horde Side")
    eq(#list, 3, "only characters with any")
    eq(list[1].name, "Aldric"); eq(list[1].you, true); eq(list[1].count, 1); eq(list[1].bags, 1)
    eq(list[2].name, "Tarn Moon"); eq(list[2].you, nil); eq(list[2].count, 14)
    eq(list[2].bags, 10); eq(list[2].bank, 0); eq(list[2].mail, 3); eq(list[2].equip, 1)
    eq(list[3].name, "Old Timer"); eq(list[3].bank, 4); eq(list[3].count, 4)
    -- Nobody has it: 0 and an empty list.
    local none, empty = AltsForever.Count(123456)
    eq(none, 0); eq(#empty, 0)
    -- The caller's to keep: changing it changes nothing of ours.
    list[2].count, list[2].name = 999, "x"
    local again, list2 = AltsForever.Count(2589)
    eq(again, 19); eq(list2[2].name, "Tarn Moon"); eq(list2[2].count, 14)
end)

test("AltsForever.DataVersion changes when counts may have, so callers can cache", function()
    rulesetStart()
    local v = AltsForever.DataVersion()
    eq(AltsForever.DataVersion(), v, "steady while nothing happens")
    wow.setBag(0, 16, { { 2589, 6 } })
    wow.fire("BAG_UPDATE", 0)
    wow.fire("BAG_UPDATE_DELAYED")
    assert(AltsForever.DataVersion() ~= v, "a bag scan")
    eq((AltsForever.Count(2589)), 6 + 10 + 4)
end)
