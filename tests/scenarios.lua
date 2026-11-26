-- Plays the addon through situations it will meet in the game, against the
-- pretend client in wow_mock.lua. Run with: python3 tests/run_tests.py

local Mock = dofile(REPO_ROOT .. "/tests/wow_mock.lua")

local tests = {}

local function test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

local function eq(actual, expected, what)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", what or "value", tostring(expected), tostring(actual)), 2)
    end
end

local function check(condition, what)
    if not condition then
        error(what or "check failed", 2)
    end
end

--------------------------------------------------------------------------------
-- A small spellbook
--------------------------------------------------------------------------------

local REND, HEROIC, SHOUT, BLOODTHIRST, STOMP, MARK, MORTAL, FROSTBOLT, CORRUPTION, WITHER, CLAP =
    100, 101, 102, 104, 105, 106, 107, 108, 109, 110, 6343

local function World(options)
    local w = Mock.new(options)
    w:addSpell(REND, {
        name = "Rend", harmful = true,
        description = "Wounds the target, causing 147 damage over 21 sec.",
        effect = { duration = 21 },
    })
    w:addSpell(HEROIC, {
        name = "Heroic Strike", harmful = true,
        description = "A strong attack that increases melee damage by 44.",
    })
    w:addSpell(SHOUT, {
        name = "Battle Shout", helpful = true,
        description = "Increases the attack power of party members by 185 for 2 min.",
    })
    w:addSpell(BLOODTHIRST, {
        name = "Bloodthirst", harmful = true,
        description = "Instantly attack the target. Your next 5 melee attacks restore health. Lasts 8 sec.",
    })
    w:addSpell(STOMP, {
        name = "Ground Stomp", harmful = false, helpful = false,
        description = "Stomps the ground, dazing every enemy around you.",
        effect = { area = true, duration = 6 },
    })
    w:addSpell(MARK, {
        name = "Hunter's Mark", harmful = true,
        description = "Places the Hunter's Mark on the target for 2 min.",
        effect = { duration = 120 },
    })
    w:addSpell(MORTAL, {
        name = "Mortal Strike", harmful = true,
        description = "A vicious strike that wounds the target, reducing healing by 50% for 10 sec.",
        effect = { name = "Mortal Wounds", duration = 10 },
    })
    w:addSpell(FROSTBOLT, {
        name = "Frostbolt", harmful = true,
        description = "Launches a bolt of frost, causing 500 damage and slowing movement by 50% for 8 sec.",
        effect = { duration = 8 },
    })
    w:addSpell(CORRUPTION, {
        name = "Corruption", harmful = true, override = WITHER,
        description = "Corrupts the target, causing 800 damage over 18 sec.",
    })
    w:addSpell(WITHER, {
        name = "Wither", harmful = true,
        description = "Withers the target, causing 900 damage over 18 sec.",
        effect = { duration = 18 },
    })
    w:addSpell(CLAP, {
        name = "Thunder Clap", harmful = false, helpful = false,
        description = "Blasts nearby enemies, slowing their attacks by 10% for 30 sec.",
        effect = { area = true, duration = 30 },
    })
    return w
end

--- A world with Rend, Heroic Strike and Battle Shout on the first three buttons
--- and one boar targeted, nameplate showing.
local function Simple(options)
    local w = World(options)
    w:addButton("ActionButton1", 1, REND)
    w:addButton("ActionButton2", 2, HEROIC)
    w:addButton("ActionButton3", 3, SHOUT)
    local ns = w:load()
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:advance(0.3)
    return w, ns, boar
end

--- Fails the scenario if the addon threw anywhere, loudly or quietly.
local function Clean(w)
    eq(#w.leaks, 0, "secret values that got past Compat.lua (" .. tostring(w.leaks[1]) .. ")")
    eq(#w.errors, 0, "errors reaching the client (" .. tostring(w.errors[1]) .. ")")
    eq(w.ns.lastError, nil, "errors the addon caught")
    check(not w:drain():find("hit a problem", 1, true), "the addon reported a problem in chat")
end

--------------------------------------------------------------------------------
-- Out of combat
--------------------------------------------------------------------------------

test("icons appear only on status spells, and only with an enemy targeted", function()
    local w = World()
    w:addButton("ActionButton1", 1, REND)
    w:addButton("ActionButton2", 2, HEROIC)
    w:addButton("ActionButton3", 3, SHOUT)
    w:load()
    eq(w:icon("ActionButton1"), nil, "Rend with no target")

    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "Rend on a clean enemy")
    eq(w:icon("ActionButton2"), nil, "Heroic Strike applies nothing")
    eq(w:icon("ActionButton3"), nil, "Battle Shout is a buff")

    local friend = w:addMob("Guard", { hostile = false })
    w:target(friend)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "Rend with a friendly target")

    w:target(nil)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "Rend after clearing the target")
    Clean(w)
end)

test("a debuff read off an enemy out of combat is exact", function()
    local w = World()
    w:addButton("ActionButton1", 1, MARK)
    local ns = w:load()
    local boar = w:addMob("Boar")
    w:target(boar)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "before the mark")

    w:cast(MARK, { quiet = true })
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "after the mark")
    eq(ns.db.learned["Hunter's Mark"].exact, true, "learned that the debuff carries the spell's name")
    eq(ns.db.learned["Hunter's Mark"].duration, 120, "learned duration")

    w:removeAura(boar, "Hunter's Mark")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "after the mark is removed")
    Clean(w)
end)

test("a dead target shows nothing", function()
    local w, _, boar = Simple()
    eq(w:icon("ActionButton1"), "check")
    w:kill(boar)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil)
    Clean(w)
end)

--------------------------------------------------------------------------------
-- In combat, when the client still shows aura instance ids
--------------------------------------------------------------------------------

test("ids: a cast turns the icon red until the debuff really ends", function()
    local w = Simple({ combatAuras = "ids" })
    w:cast(REND)
    w:advance(0.1)
    eq(w:icon("ActionButton1"), "cross", "right after the cast")
    w:advance(20)
    eq(w:icon("ActionButton1"), "cross", "20 seconds in")
    w:advance(1.5)
    eq(w:icon("ActionButton1"), "check", "after it expired")
    Clean(w)
end)

test("ids: a debuff that drops off early is noticed", function()
    local w, _, boar = Simple({ combatAuras = "ids" })
    w:cast(REND)
    w:advance(5)
    eq(w:icon("ActionButton1"), "cross")
    w:removeAura(boar, "Rend")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "after it was removed")
    Clean(w)
end)

test("ids: a debuff that outlives its tooltip stays red", function()
    local w, _, boar = Simple({ combatAuras = "ids" })
    w.spells[REND].effect.duration = 40 -- talents made it longer than the tooltip says
    w:cast(REND)
    w:advance(30)
    eq(w:icon("ActionButton1"), "cross", "past the tooltip duration")
    w:advance(11)
    eq(w:icon("ActionButton1"), "check", "after it really expired")
    check(boar ~= nil)
    Clean(w)
end)

test("ids: a miss goes back to green after a moment", function()
    local w, ns, boar = Simple({ combatAuras = "ids" })
    w:cast(REND)
    w:advance(3)
    w:removeAura(boar, "Rend")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "clean again")

    w:cast(REND, { miss = true })
    w:advance(0.1)
    eq(w:icon("ActionButton1"), "cross", "assumed to land at first")
    w:advance(2.3)
    eq(w:icon("ActionButton1"), "check", "once nothing showed up")
    eq(ns.db.learned.Rend.casts, 2, "casts counted")
    eq(ns.db.learned.Rend.hits, 1, "hits counted")
    Clean(w)
end)

test("ids: the first cast of a fight is given the benefit of the doubt", function()
    -- Until a debuff of yours has been seen this fight, "nothing there" is not
    -- proof of a miss: the client could simply be hiding it.
    local w, ns = Simple({ combatAuras = "ids" })
    w:cast(REND, { miss = true })
    w:advance(3)
    eq(w:icon("ActionButton1"), "cross", "kept as an assumption")
    eq(ns.db.learned.Rend, nil, "and not counted as evidence")
    w:advance(19)
    eq(w:icon("ActionButton1"), "check", "until its timer ends")
    Clean(w)
end)

test("an empty answer in combat is never mistaken for a clean enemy", function()
    -- A client that answers the count with an empty list instead of refusing.
    local w, ns = Simple({ combatAuras = "empty" })
    for _ = 1, 6 do
        w:cast(REND)
        w:advance(1)
        eq(w:icon("ActionButton1"), "cross", "after each cast")
        w:advance(21)
    end
    eq(ns.db.learned.Rend, nil, "nothing was unlearned")
    eq(w:icon("ActionButton1"), "check", "timers still run")
    Clean(w)
end)

test("ids: recasting on top refreshes without counting as a miss", function()
    local w, ns = Simple({ combatAuras = "ids" })
    w:cast(REND)
    w:advance(10)
    w:cast(REND)
    w:advance(15)
    eq(w:icon("ActionButton1"), "cross", "25s in, refreshed at 10s")
    w:advance(7)
    eq(w:icon("ActionButton1"), "check", "after the refreshed one expired")
    eq(ns.db.learned.Rend.casts, 1, "only the first cast counts as evidence")
    eq(ns.db.learned.Rend.hits, 1)
    Clean(w)
end)

test("ids: a refresh that replaces the aura instance is followed", function()
    local w = Simple({ combatAuras = "ids", refreshReplaces = true })
    w:cast(REND)
    w:advance(10)
    w:cast(REND)
    w:advance(15)
    eq(w:icon("ActionButton1"), "cross", "25s in, refreshed at 10s")
    w:advance(7)
    eq(w:icon("ActionButton1"), "check")
    Clean(w)
end)

test("ids: a debuff with a different name than its spell is tracked", function()
    local w = World({ combatAuras = "ids" })
    w:addButton("ActionButton1", 1, MORTAL)
    w:load()
    local boar = w:addMob("Boar")
    w:target(boar)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check")
    w:cast(MORTAL)
    w:advance(5)
    eq(w:icon("ActionButton1"), "cross")
    w:advance(6)
    eq(w:icon("ActionButton1"), "check")
    Clean(w)
end)

test("ids: a slow projectile is still credited", function()
    local w = World({ combatAuras = "ids" })
    w:addButton("ActionButton1", 1, FROSTBOLT)
    local ns = w:load()
    local boar = w:addMob("Boar")
    w:target(boar)
    w:advance(0.3)
    w:cast(FROSTBOLT, { travel = 1.5 })
    w:advance(0.2)
    eq(w:icon("ActionButton1"), "cross", "in flight")
    w:advance(3)
    eq(w:icon("ActionButton1"), "cross", "landed")
    eq(ns.db.learned.Frostbolt.hits, 1)
    w:advance(7)
    eq(w:icon("ActionButton1"), "check", "expired")
    Clean(w)
end)

test("ids: switching targets keeps each enemy's own state", function()
    local w, _, boar = Simple({ combatAuras = "ids" })
    local wolf = w:addMob("Wolf")
    w:showPlate(wolf)
    w:cast(REND)
    w:target(wolf) -- before the cast is even confirmed
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "check", "the wolf is clean")
    w:target(boar)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "the boar still bleeds")
    w:advance(3)
    eq(w:icon("ActionButton1"), "cross", "and stays that way once the cast is judged")
    Clean(w)
end)

--------------------------------------------------------------------------------
-- In combat, when only the number of debuffs can be read
--------------------------------------------------------------------------------

test("count: hit, early drop and miss are all told apart", function()
    local w, ns, boar = Simple({ combatAuras = "count" })
    w:cast(REND)
    w:advance(3)
    eq(w:icon("ActionButton1"), "cross", "after a hit")
    w:removeAura(boar, "Rend")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "after it dropped")

    w:cast(REND, { miss = true })
    w:advance(0.1)
    eq(w:icon("ActionButton1"), "cross", "assumed at first")
    w:advance(2.3)
    eq(w:icon("ActionButton1"), "check", "after a miss")
    eq(ns.db.learned.Rend.casts, 2)
    eq(ns.db.learned.Rend.hits, 1)
    Clean(w)
end)

test("count: the timer still ends a debuff nobody saw drop", function()
    local w = Simple({ combatAuras = "count" })
    w:cast(REND)
    w:advance(20.5)
    eq(w:icon("ActionButton1"), "cross")
    w:advance(1)
    eq(w:icon("ActionButton1"), "check")
    Clean(w)
end)

--------------------------------------------------------------------------------
-- In combat, when nothing about auras can be read
--------------------------------------------------------------------------------

test("blind: the spell's own duration is used", function()
    local w = Simple({ combatAuras = "none" })
    w:cast(REND)
    w:advance(0.1)
    eq(w:icon("ActionButton1"), "cross", "right after the cast")
    w:advance(20)
    eq(w:icon("ActionButton1"), "cross", "20 seconds in")
    w:advance(1.5)
    eq(w:icon("ActionButton1"), "check", "after the timer ran out")
    Clean(w)
end)

test("blind: no aura API at all still works on timers", function()
    local w = Simple({ noAuraAPI = true })
    eq(w:icon("ActionButton1"), "check")
    w:cast(REND)
    w:advance(10)
    eq(w:icon("ActionButton1"), "cross")
    w:advance(12)
    eq(w:icon("ActionButton1"), "check")
    Clean(w)
end)

test("blind: refused calls are not retried every pass", function()
    local w = Simple({ combatAuras = "none" })
    w:cast(REND)
    w:advance(1)
    local before = w.ns.probe.hidden.sample
    eq(before, "none", "what the addon noted about counting in combat")
    Clean(w)
end)

test("a debuff the client still shows by name in combat is read exactly", function()
    local w, ns, boar = Simple({ combatAuras = "none", byName = { Rend = true } })
    w:cast(REND)
    w:advance(3)
    eq(w:icon("ActionButton1"), "cross")
    eq(ns.db.learned.Rend.exact, true)
    w:removeAura(boar, "Rend")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "seen dropping off by name")

    w:cast(REND, { miss = true })
    w:advance(0.1)
    eq(w:icon("ActionButton1"), "cross", "assumed at first")
    w:advance(2.4)
    eq(w:icon("ActionButton1"), "check", "the miss is caught by name")
    Clean(w)
end)

--------------------------------------------------------------------------------
-- Area spells
--------------------------------------------------------------------------------

local function Pack(options)
    local w = World(options)
    w:addButton("ActionButton1", 1, CLAP)
    w:addButton("ActionButton2", 2, REND)
    local ns = w:load()
    local mobs = {}
    for i = 1, 3 do
        mobs[i] = w:addMob("Kobold " .. i)
        w:showPlate(mobs[i])
    end
    w:target(mobs[1])
    w:advance(0.5)
    return w, ns, mobs
end

test("area: green, yellow and red follow how many enemies have it", function()
    local w, _, mobs = Pack({ combatAuras = "ids" })
    eq(w:icon("ActionButton1"), "check", "before the pull, judged on the target")

    for i = 1, 3 do
        mobs[i].engaged = true
    end
    w:enterCombat()
    w:cast(REND) -- a first debuff, so the client's counts can be believed
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "check", "three enemies without Thunder Clap")

    w:cast(CLAP, { hits = { mobs[1], mobs[2] } })
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "partial", "two of three hit")

    w:cast(CLAP, { hits = { mobs[1], mobs[2], mobs[3] } })
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross", "all three hit")

    w:removeAura(mobs[3], "Thunder Clap")
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "partial", "one dropped off")
    eq(w:icon("ActionButton2"), "cross", "Rend is still on the target")

    w:advance(31)
    eq(w:icon("ActionButton1"), "check", "all expired")

    w:kill(mobs[2])
    w:kill(mobs[3])
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "check", "only the target left")
    w:kill(mobs[1])
    w:leaveCombat()
    w:advance(0.5)
    eq(w:icon("ActionButton1"), nil, "nobody left")
    Clean(w)
end)

test("area: enemies outside the fight are not counted", function()
    local w, _, mobs = Pack({ combatAuras = "ids" })
    mobs[1].engaged = true
    mobs[2].engaged = true
    w:enterCombat()
    w:advance(0.5)
    w:cast(CLAP, { hits = { mobs[1], mobs[2] } })
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross", "the third kobold is not fighting")
    Clean(w)
end)

test("area, blind: everyone in the fight is assumed hit", function()
    local w, _, mobs = Pack({ combatAuras = "none" })
    for i = 1, 3 do
        mobs[i].engaged = true
    end
    w:enterCombat()
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "check")
    w:cast(CLAP)
    w:advance(0.1)
    eq(w:icon("ActionButton1"), "cross", "straight away")
    w:advance(29)
    eq(w:icon("ActionButton1"), "cross", "29 seconds in")
    w:advance(1.5)
    eq(w:icon("ActionButton1"), "check", "after the timer")
    Clean(w)
end)

test("area: an opening cast is assumed to land, then corrected", function()
    local w, _, mobs = Pack({ combatAuras = "ids" })
    for i = 1, 3 do
        mobs[i].engaged = true
    end
    w:enterCombat()
    w:advance(0.5)
    w:cast(CLAP, { hits = { mobs[1], mobs[2] } })
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "nothing to compare with yet, so everyone is assumed hit")
    w:advance(2.5)
    eq(w:icon("ActionButton1"), "partial", "the count on the third kobold says otherwise")
    Clean(w)
end)

test("area, blind: a pull from out of combat catches the enemies that join", function()
    local w, _, mobs = Pack({ combatAuras = "none" })
    eq(w:icon("ActionButton1"), "check")
    w:cast(CLAP, { hits = { mobs[1], mobs[2], mobs[3] } })
    w:advance(2.5)
    eq(w:icon("ActionButton1"), "cross", "once the cast has been judged")
    Clean(w)
end)

test("area: a targeted debuff next to an area one is judged separately", function()
    local w, _, mobs = Pack({ combatAuras = "ids" })
    for i = 1, 3 do
        mobs[i].engaged = true
    end
    w:enterCombat()
    w:cast(REND)
    w:advance(0.5)
    eq(w:icon("ActionButton2"), "cross", "Rend on the target")
    eq(w:icon("ActionButton1"), "check", "Thunder Clap on nobody")
    w:target(mobs[2])
    w:advance(0.3)
    eq(w:icon("ActionButton2"), "check", "Rend on the next kobold")
    Clean(w)
end)

--------------------------------------------------------------------------------
-- Learning
--------------------------------------------------------------------------------

test("an unknown area spell earns an icon once it keeps leaving debuffs", function()
    local w = World({ combatAuras = "ids" })
    w:addButton("ActionButton1", 1, STOMP)
    local ns = w:load()
    local mobs = {}
    for i = 1, 2 do
        mobs[i] = w:addMob("Kobold " .. i)
        w:showPlate(mobs[i])
        mobs[i].engaged = true
    end
    w:target(mobs[1])
    w:enterCombat()
    w:applyAura(mobs[1], "Deep Wounds", 600) -- some other debuff of yours, from a proc
    w:advance(0.5)
    eq(w:icon("ActionButton1"), nil, "not known as a status spell yet")

    for _ = 1, 5 do
        w:cast(STOMP)
        w:advance(8)
    end
    eq(w:icon("ActionButton1"), nil, "five casts are not enough")
    w:cast(STOMP)
    w:advance(8)
    eq(ns.db.learned["Ground Stomp"].hits, 6, "hits recorded")
    eq(w:icon("ActionButton1"), "check", "tracked after six")

    w:cast(STOMP)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross", "and judged like any area spell")
    Clean(w)
end)

test("a spell whose tooltip misleads loses its icon", function()
    local w = World({ combatAuras = "ids" })
    w:addButton("ActionButton1", 1, BLOODTHIRST)
    w:addButton("ActionButton2", 2, MARK)
    local ns = w:load()
    local boar = w:addMob("Boar")
    w:target(boar)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "trusted at first: it has a duration in its tooltip")
    w:cast(MARK) -- a real debuff, so the client's counts can be believed
    w:advance(1)
    for _ = 1, 3 do
        w:cast(BLOODTHIRST)
        w:advance(3)
    end
    eq(w:icon("ActionButton1"), "check", "three empty casts are not enough")
    w:cast(BLOODTHIRST)
    w:advance(3)
    eq(ns.db.learned.Bloodthirst.casts, 4)
    eq(w:icon("ActionButton1"), nil, "dropped after four")
    Clean(w)
end)

test("blind casts teach nothing, so nothing is unlearned by mistake", function()
    local w, ns = Simple({ combatAuras = "none" })
    for _ = 1, 6 do
        w:cast(REND, { miss = true })
        w:advance(3)
    end
    eq(ns.db.learned.Rend, nil, "no evidence recorded")
    eq(w:icon("ActionButton1"), "cross", "still tracked, still assumed")
    Clean(w)
end)

--------------------------------------------------------------------------------
-- What the client hides
--------------------------------------------------------------------------------

test("hidden enemy identity: nameplates keep enemies apart", function()
    local w, _, boar = Simple({ combatAuras = "ids", combatIdentity = false })
    local wolf = w:addMob("Wolf")
    w:showPlate(wolf)
    w:advance(0.3)
    w:cast(REND)
    w:advance(1)
    eq(w:icon("ActionButton1"), "cross", "boar")
    w:target(wolf)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "wolf")
    w:target(boar)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "back on the boar")
    Clean(w)
end)

test("hidden enemy identity with no nameplates: no errors, target-scoped state", function()
    local w = World({ combatAuras = "none", combatIdentity = false })
    w:addButton("ActionButton1", 1, REND)
    w:load()
    local boar = w:addMob("Boar")
    local wolf = w:addMob("Wolf")
    w:target(boar)
    w:advance(0.3)
    w:cast(REND)
    w:advance(1)
    eq(w:icon("ActionButton1"), "cross", "boar")
    w:target(wolf)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "wolf")
    Clean(w)
end)

test("a nameplate reused for another enemy does not inherit the old one's state", function()
    local w, _, boar = Simple({ combatAuras = "none", combatIdentity = false })
    w:cast(REND)
    w:advance(1)
    eq(w:icon("ActionButton1"), "cross")
    local wolf = w:addMob("Wolf")
    w:hidePlate(boar)
    w:showPlate(wolf) -- gets the nameplate the boar just gave up
    eq(wolf.plate, "nameplate1")
    w:target(wolf)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "the wolf took over the boar's nameplate")
    Clean(w)
end)

test("secret yes/no answers in combat do not break anything", function()
    local w = Simple({ combatAuras = "ids", secretFlags = true })
    w:cast(REND)
    w:advance(1)
    eq(w:icon("ActionButton1"), "cross")
    w:advance(21)
    eq(w:icon("ActionButton1"), "check")
    Clean(w)
end)

test("secret answers with hidden identity and no aura access", function()
    local w, _, boar = Simple({ combatAuras = "none", secretFlags = true, combatIdentity = false })
    w:cast(REND)
    w:advance(1)
    eq(w:icon("ActionButton1"), "cross")
    w:kill(boar)
    w:leaveCombat()
    w:advance(0.5)
    eq(w:icon("ActionButton1"), nil)
    Clean(w)
end)

test("an older client without secret values reads everything directly", function()
    local w, ns, boar = Simple({ secrets = false })
    eq(ns.hasSecretValues, false)
    w:cast(REND)
    w:advance(1)
    eq(w:icon("ActionButton1"), "cross")
    w:removeAura(boar, "Rend")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check")
    Clean(w)
end)

test("a client without C_Secrets falls back to the combat flag", function()
    local w = Simple({ noCSecrets = true, combatAuras = "none" })
    w:cast(REND)
    w:advance(1)
    eq(w:icon("ActionButton1"), "cross")
    eq(w.ns.AurasSecret(), true)
    Clean(w)
end)

--------------------------------------------------------------------------------
-- Casting details
--------------------------------------------------------------------------------

test("a cast that fails leaves nothing behind", function()
    local w = Simple({ combatAuras = "none" })
    w:cast(REND, { fail = true })
    w:advance(1)
    eq(w:icon("ActionButton1"), "check")
    Clean(w)
end)

test("a cast with a cast time is judged from when it was sent", function()
    local w, ns = Simple({ combatAuras = "ids" })
    w:cast(REND, { castTime = 2 })
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross")
    w:advance(3)
    eq(ns.db.learned.Rend.hits, 1)
    Clean(w)
end)

test("a success with no sent event is assumed, not judged", function()
    local w, ns = Simple({ combatAuras = "ids" })
    w:cast(REND, { noSent = true })
    w:advance(3)
    eq(w:icon("ActionButton1"), "cross")
    eq(ns.db.learned.Rend, nil, "no before-picture, so no evidence")
    Clean(w)
end)

test("a spell that is not on the bars is ignored", function()
    local w, ns = Simple({ combatAuras = "ids" })
    w:cast(MORTAL)
    w:advance(3)
    eq(ns.db.learned["Mortal Strike"], nil)
    Clean(w)
end)

--------------------------------------------------------------------------------
-- Bars
--------------------------------------------------------------------------------

test("macros that cast a status spell get the icon", function()
    for _, style in ipairs({ "index", "spell" }) do
        local w = World({ macroStyle = style })
        w:addButton("ActionButton1", 1, REND, "macro")
        w:load()
        local boar = w:addMob("Boar")
        w:target(boar)
        w:advance(0.3)
        eq(w:icon("ActionButton1"), "check", "macro style " .. style)
        Clean(w)
    end
end)

test("a talent that swaps the spell is followed on both sides", function()
    for _, castAs in ipairs({ WITHER, CORRUPTION }) do
        local w = World({ combatAuras = "none" })
        w:addButton("ActionButton1", 1, CORRUPTION)
        w:load()
        local boar = w:addMob("Boar")
        w:target(boar)
        w:advance(0.3)
        eq(w:icon("ActionButton1"), "check")
        w.spells[castAs].effect = { name = "Wither", duration = 18 }
        w.spells[castAs].harmful = true
        w:cast(castAs)
        w:advance(1)
        eq(w:icon("ActionButton1"), "cross", "cast reported as spell " .. castAs)
        Clean(w)
    end
end)

test("moving spells around the bar moves the icon", function()
    local w = Simple()
    eq(w:icon("ActionButton1"), "check")
    w:addButton("ActionButton1", 1, HEROIC)
    w:addButton("ActionButton2", 2, REND)
    w:fire("ACTIONBAR_SLOT_CHANGED", 1)
    w:fire("ACTIONBAR_SLOT_CHANGED", 2)
    w:advance(0.6)
    eq(w:icon("ActionButton1"), nil)
    eq(w:icon("ActionButton2"), "check")
    Clean(w)
end)

test("a hidden bar gets no icon work", function()
    local w = Simple()
    w.env.ActionButton1:Hide()
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil)
    w.env.ActionButton1:Show()
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check")
    Clean(w)
end)

test("spell text that arrives late is picked up", function()
    local w = World()
    w.spells[REND].unloaded = true
    w.spells[REND].textPending = 2
    w:addButton("ActionButton1", 1, REND)
    w:load()
    local boar = w:addMob("Boar")
    w:target(boar)
    w:advance(6)
    eq(w:icon("ActionButton1"), "check")
    Clean(w)
end)

test("bar addon buttons are found too", function()
    local w = World()
    local button = w.env.CreateFrame("CheckButton", "BT4Button7", nil)
    button.width = 36
    button._state_action = 7
    w.actions[7] = { kind = "spell", id = REND }
    w:load()
    local boar = w:addMob("Boar")
    w:target(boar)
    w:advance(0.3)
    eq(w:icon("BT4Button7"), "check")
    Clean(w)
end)

--------------------------------------------------------------------------------
-- Slash commands and settings
--------------------------------------------------------------------------------

test("/se track, ignore and auto", function()
    local w, ns = Simple({ combatAuras = "ids" })
    w:slash("ignore rend")
    w:advance(0.5)
    eq(w:icon("ActionButton1"), nil, "ignored")
    w:slash("auto Rend")
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "check", "automatic again")

    w:slash("track heroic")
    w:advance(0.5)
    eq(w:icon("ActionButton2"), "check", "forced on, matched by the start of its name")
    w:cast(HEROIC)
    w:advance(5)
    eq(w:icon("ActionButton2"), "cross", "forced spells are trusted even with nothing to see")
    w:advance(8)
    eq(w:icon("ActionButton2"), "check", "until the default timer ends")

    w:slash("duration heroic strike 4")
    w:cast(HEROIC)
    w:advance(3)
    eq(w:icon("ActionButton2"), "cross")
    w:advance(1.5)
    eq(w:icon("ActionButton2"), "check", "the duration you set is used")
    eq(ns.db.spells["Heroic Strike"].duration, 4)

    w:slash("track nonsense spell")
    check(w:drain():find("No spell called", 1, true), "an unknown spell is refused politely")
    eq(#w.errors, 0)
    eq(ns.lastError, nil)
end)

test("/se aoe makes a targeted spell count every enemy in the fight", function()
    local w, _, mobs = Pack({ combatAuras = "ids" })
    for i = 1, 3 do
        mobs[i].engaged = true
    end
    w:enterCombat()
    w:applyAura(mobs[2], "Deep Wounds", 600) -- so the client's counts can be believed
    w:slash("aoe rend")
    w:advance(0.5)
    eq(w:icon("ActionButton2"), "check")
    w:cast(REND)
    w:advance(0.5)
    eq(w:icon("ActionButton2"), "partial", "one of three")
    w:slash("single rend")
    w:advance(0.5)
    eq(w:icon("ActionButton2"), "cross", "target only again")
    Clean(w)
end)

test("/se size and corner move the icon", function()
    local w = Simple()
    local overlay = w:overlay("ActionButton1")
    eq(overlay.width, 16, "about a third of a 45 pixel button")
    eq(overlay.point[1], "TOPLEFT")
    w:slash("size 30")
    w:slash("corner br")
    eq(overlay.width, 30)
    eq(overlay.height, 30)
    eq(overlay.point[1], "BOTTOMRIGHT")
    w:slash("size auto")
    eq(overlay.width, 16)

    w:drain()
    w:slash("size 4")
    check(w:drain():find("Usage: /se size <8 to 128 | auto>", 1, true), "too small is refused with the usage line")
    w:slash("size huge")
    eq(w.ns.db.size, 0, "and changes nothing")
    Clean(w)
end)

test("with no size chosen the icon follows the size of its button", function()
    local w = World()
    w:addButton("ActionButton1", 1, REND)
    local small = w.env.CreateFrame("CheckButton", "BT4Button7", nil)
    small.width = 36
    small._state_action = 7
    w.actions[7] = { kind = "spell", id = REND }
    local tiny = w.env.CreateFrame("CheckButton", "BT4Button8", nil)
    tiny.width = 20
    tiny._state_action = 8
    w.actions[8] = { kind = "spell", id = REND }
    local ns = w:load()
    local boar = w:addMob("Boar")
    w:target(boar)
    w:advance(0.3)
    eq(w:overlay("ActionButton1").width, 16, "standard button")
    eq(w:overlay("BT4Button7").width, 13, "smaller button, smaller icon")
    eq(w:overlay("BT4Button8").width, 10, "but never too small to read")
    eq(ns.AutoIconSize(), 16, "the size quoted for auto is the first button's")

    w:slash("size 22")
    eq(w:overlay("ActionButton1").width, 22)
    eq(w:overlay("BT4Button7").width, 22, "a chosen size is the same on every button")
    Clean(w)
end)

test("/se off and on", function()
    local w = Simple()
    w:slash("off")
    w:advance(0.5)
    eq(w:icon("ActionButton1"), nil)
    w:slash("on")
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "check")
    Clean(w)
end)

test("/se help, list and debug print something sensible", function()
    local w = Simple({ combatAuras = "count" })
    w:drain()
    w:slash("")
    check(w:drain():find("/se list", 1, true), "help mentions /se list")
    w:slash("list")
    local list = w:drain()
    check(list:find("Rend", 1, true), "list shows Rend")
    check(list:find("2 other spells", 1, true), "list counts the rest: " .. list)
    w:cast(REND)
    w:advance(1)
    w:slash("debug")
    local debug = w:drain()
    check(debug:find("interface 16001", 1, true), "debug shows the interface number: " .. debug)
    check(debug:find("the count only", 1, true), "debug shows what counting gives: " .. debug)
    check(debug:find("Rend, ", 1, true), "debug lists the tracked effect: " .. debug)
    check(debug:find("Options window: yes", 1, true), "debug says the settings panel was added: " .. debug)
    eq(#w.errors, 0)
    eq(w.ns.lastError, nil)
end)

test("/se reset forgets settings and what was learned", function()
    local w, ns = Simple({ combatAuras = "ids" })
    w:slash("track heroic strike")
    w:cast(REND)
    w:advance(3)
    check(ns.db.learned.Rend ~= nil)
    w:slash("reset")
    eq(next(ns.db.spells), nil)
    eq(next(ns.db.learned), nil)
    eq(ns.db.enabled, true)
    eq(w.env.StatusEfficiencyDB, ns.db, "still the saved table")
    Clean(w)
end)

test("saved settings are loaded, and damaged ones repaired", function()
    local w = World()
    w:addButton("ActionButton1", 1, REND)
    local ns = w:load({ enabled = "yes", corner = "SIDEWAYS", size = 24, spells = { Rend = { track = false } } })
    eq(ns.db.enabled, true, "wrong type replaced")
    eq(ns.db.corner, "TOPLEFT", "unknown corner replaced")
    eq(ns.db.size, 24, "good value kept")
    local boar = w:addMob("Boar")
    w:target(boar)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "saved choice honoured")
    Clean(w)
end)

test("a saved icon size that makes no sense goes back to following the button", function()
    for _, bad in ipairs({ 3, 500, -4 }) do
        local w = World()
        w:addButton("ActionButton1", 1, REND)
        local ns = w:load({ size = bad })
        eq(ns.db.size, 0, "saved size " .. bad)
        local boar = w:addMob("Boar")
        w:target(boar)
        w:advance(0.3)
        eq(w:overlay("ActionButton1").width, 16)
        Clean(w)
    end
end)

--------------------------------------------------------------------------------
-- The settings panel
--------------------------------------------------------------------------------

local SKULL = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"

local function Art(w, button)
    return w:overlay(button).textures[1].path
end

test("settings: the panel is added to the game's Options window", function()
    local w = Simple()
    eq(#w.settings.addons, 1, "panels registered under AddOns")
    eq(w.settings.addons[1].name, "Status Efficiency")
    local canvas = w:openSettings()
    check(canvas.view ~= nil, "the panel is built when it is first shown")
    Clean(w)
end)

test("settings: clicking a spot moves the icon on every button", function()
    local w, ns = Simple()
    local view = w:openSettings().view
    eq(w:overlay("ActionButton1").point[1], "TOPLEFT", "starts in the top left")
    eq(view.zones.TOPLEFT.art.shown, true, "the preview shows it there")

    w:click(view.zones.BOTTOMRIGHT)
    eq(ns.db.corner, "BOTTOMRIGHT")
    eq(w:overlay("ActionButton1").point[1], "BOTTOMRIGHT", "the real icon moved")
    eq(view.zones.BOTTOMRIGHT.art.shown, true, "the preview moved")
    eq(view.zones.TOPLEFT.art.shown, false)
    eq(view.zones.TOPLEFT.ghost.shown, true)

    w:click(view.zones.TOP)
    eq(w:overlay("ActionButton1").point[1], "TOP", "edges work as well as corners")
    Clean(w)
end)

test("settings: the size buttons make the icon smaller and larger", function()
    local w, ns = Simple()
    local view = w:openSettings().view
    local overlay = w:overlay("ActionButton1")
    eq(view.size.readout:GetText(), "Auto (16)", "starts out following the button")

    w:click(view.size.smaller)
    eq(ns.db.size, 14, "one step down from what auto gives")
    eq(overlay.width, 14, "the real icon shrinks straight away")
    eq(view.size.readout:GetText(), "14")

    w:click(view.size.smaller)
    w:click(view.size.smaller)
    w:click(view.size.smaller)
    w:click(view.size.smaller)
    eq(ns.db.size, 8, "and stops at the smallest size")
    eq(overlay.width, 8)

    w:click(view.size.larger)
    w:click(view.size.larger)
    eq(ns.db.size, 12)
    eq(overlay.width, 12)

    w:click(view.size.auto)
    eq(ns.db.size, 0)
    eq(overlay.width, 16, "auto follows the button again")
    eq(view.size.readout:GetText(), "Auto (16)")

    w:click(view.size.larger)
    eq(ns.db.size, 18, "one step up from what auto gives")

    ns.db.size = 127
    w:click(view.size.larger)
    w:click(view.size.larger)
    eq(ns.db.size, 128, "and stops at the largest size")
    Clean(w)
end)

test("settings: the size shown follows /se size, in both copies of the panel", function()
    local w, ns = Simple()
    w:slash("options")
    local window = w.env.StatusEfficiencyOptions.view
    local inOptions = w:openSettings().view
    w:slash("size 24")
    eq(window.size.readout:GetText(), "24")
    eq(inOptions.size.readout:GetText(), "24")
    w:click(window.size.smaller)
    eq(inOptions.size.readout:GetText(), "22", "a click in one copy shows in the other")
    w:slash("size auto")
    eq(window.size.readout:GetText(), "Auto (16)")
    eq(ns.db.size, 0)
    Clean(w)
end)

test("settings: picking an icon changes what the buttons show", function()
    local w, ns = Simple({ combatAuras = "none" })
    local view = w:openSettings().view
    eq(w:icon("ActionButton1"), "check")
    eq(view.swatches.none.check.ring.shown, true, "the icon in use is framed")

    w:click(view.swatches.none.greendot)
    eq(ns.db.icons.none, "greendot")
    check(Art(w, "ActionButton1"):find("DotGreen.tga", 1, true), "the button shows the green dot straight away")
    eq(view.swatches.none.greendot.ring.shown, true)
    eq(view.swatches.none.check.ring.shown, false)
    eq(view.swatches.all.cross.ring.shown, true, "the other indications are untouched")

    w:click(view.swatches.all.skull)
    w:cast(REND)
    w:advance(0.5)
    eq(Art(w, "ActionButton1"), SKULL, "the skull now means every enemy has it")
    Clean(w)
end)

test("settings: every icon on offer is a swatch for each indication", function()
    local w, ns = Simple()
    local view = w:openSettings().view
    local count = 0
    for _, choice in ipairs(ns.Icons.CHOICES) do
        count = count + 1
        for _, state in ipairs(ns.Icons.STATES) do
            local swatch = view.swatches[state.key][choice.key]
            check(swatch, "missing swatch " .. choice.key .. " for " .. state.key)
            eq(swatch.art.path, choice.texture)
        end
    end
    eq(count, 21, "icons on offer")
    for _, state in ipairs(ns.Icons.STATES) do
        check(ns.Icons.Choice(state.default), "default for " .. state.key .. " exists")
    end
    Clean(w)
end)

test("settings: your own texture, by file ID or by path", function()
    local w, ns = Simple()
    local view = w:openSettings().view
    w:type(view.inputs.none, "136243")
    eq(ns.db.icons.none, "custom")
    eq(ns.db.custom.none, 136243)
    eq(Art(w, "ActionButton1"), 136243, "the button shows the file ID")
    eq(view.swatches.none.check.ring.shown, false, "no stock icon is framed")
    eq(view.inputs.none:GetText(), "136243")

    w:type(view.inputs.none, " Interface/Icons/Spell_Nature_Slow ")
    eq(Art(w, "ActionButton1"), "Interface\\Icons\\Spell_Nature_Slow", "a path with either kind of slash")

    w:drain()
    w:type(view.inputs.none, "nonsense")
    check(w:drain():find("not a texture", 1, true), "a bad entry is explained")
    eq(ns.db.custom.none, "Interface\\Icons\\Spell_Nature_Slow", "and changes nothing")

    w:type(view.inputs.none, "")
    eq(ns.db.icons.none, nil, "emptying the box goes back to the usual icon")
    eq(w:icon("ActionButton1"), "check")
    eq(view.swatches.none.check.ring.shown, true)
    eq(#w.errors, 0)
    eq(ns.lastError, nil)
end)

test("settings: the reset button restores position, size and icons only", function()
    local w, ns = Simple()
    local view = w:openSettings().view
    w:slash("track heroic strike")
    w:click(view.zones.CENTER)
    w:click(view.size.larger)
    w:click(view.swatches.some.ring)
    w:type(view.inputs.all, "136243")
    w:click(view.reset)
    eq(ns.db.corner, "TOPLEFT")
    eq(ns.db.size, 0)
    eq(w:overlay("ActionButton1").width, 16)
    eq(view.size.readout:GetText(), "Auto (16)")
    eq(next(ns.db.icons), nil)
    eq(next(ns.db.custom), nil)
    eq(w:icon("ActionButton1"), "check")
    eq(view.inputs.all:GetText(), "")
    check(ns.db.spells["Heroic Strike"] ~= nil, "spell choices are left alone")
    Clean(w)
end)

test("/se options opens a window of its own, and both copies stay in step", function()
    local w = Simple()
    w:slash("options")
    local window = w.env.StatusEfficiencyOptions
    check(window and window:IsShown(), "the window is showing")
    eq(w.env.UISpecialFrames[1], "StatusEfficiencyOptions", "Escape closes it")

    local inOptions = w:openSettings().view
    w:click(window.view.swatches.some.exclaim)
    eq(inOptions.swatches.some.exclaim.ring.shown, true, "the copy in the Options window follows")
    w:click(inOptions.zones.LEFT)
    eq(window.view.zones.LEFT.art.shown, true, "and the other way round")

    w:slash("options")
    eq(window:IsShown(), false, "the command closes it again")
    w:slash("config")
    eq(window:IsShown(), true, "/se config is the same command")
    Clean(w)
end)

test("/se icon, /se icons and /se corner do the same from the chat box", function()
    local w, ns = Simple()
    w:slash("icon red skull")
    eq(ns.db.icons.all, "skull")
    w:slash("icon green 136243")
    eq(ns.db.icons.none, "custom")
    eq(Art(w, "ActionButton1"), 136243)
    w:slash("icon yellow Interface\\Icons\\INV_Misc_QuestionMark")
    eq(ns.db.custom.some, "Interface\\Icons\\INV_Misc_QuestionMark")
    w:slash("icon green default")
    eq(ns.db.icons.none, nil)
    eq(w:icon("ActionButton1"), "check")

    w:drain()
    w:slash("icon purple skull")
    check(w:drain():find("Usage: /se icon", 1, true), "an unknown indication gets the usage line")
    w:slash("icon red nonsense")
    check(w:drain():find("is not an icon name", 1, true), "an unknown icon is explained")
    eq(ns.db.icons.all, "skull", "and changes nothing")

    w:slash("icons")
    local listing = w:drain()
    check(listing:find("skull", 1, true) and listing:find("greendot", 1, true), "the names are listed: " .. listing)
    check(listing:find("Every enemy has it: skull", 1, true), "with what each indication uses now: " .. listing)

    w:slash("corner bottom right")
    eq(ns.db.corner, "BOTTOMRIGHT")
    eq(w:overlay("ActionButton1").point[1], "BOTTOMRIGHT")
    w:slash("corner top")
    eq(ns.db.corner, "TOP")
    w:slash("corner sideways")
    eq(ns.db.corner, "TOP", "a bad position changes nothing")
    eq(#w.errors, 0)
    eq(ns.lastError, nil)
end)

test("saved icon choices are used after a reload, and broken ones fall back", function()
    local w = World()
    w:addButton("ActionButton1", 1, REND)
    local ns = w:load({
        corner = "BOTTOM",
        icons = { none = "skull", some = "no-such-icon", all = "custom" },
        custom = { all = 136243 },
    })
    local boar = w:addMob("Boar")
    w:target(boar)
    w:advance(0.3)
    eq(Art(w, "ActionButton1"), SKULL, "saved choice")
    eq(w:overlay("ActionButton1").point[1], "BOTTOM", "saved position")
    check(ns.Icons.Texture("some"):find("Partial.tga", 1, true), "unknown name falls back to the default")
    eq(ns.Icons.Texture("all"), 136243, "saved texture of your own")
    Clean(w)
end)

test("a client without the Options window API still gets /se options", function()
    local w = Simple({ noSettings = true })
    eq(#w.settings.addons, 0)
    w:slash("options")
    check(w.env.StatusEfficiencyOptions:IsShown(), "the window opens")
    w:click(w.env.StatusEfficiencyOptions.view.zones.RIGHT)
    eq(w.ns.db.corner, "RIGHT")
    Clean(w)
end)

test("if the settings window cannot be built, the commands still work", function()
    local w, ns = Simple()
    w.env.GameFontNormal = nil -- CreateFontString fails without the font the panel wants
    local real = w.env.CreateFrame
    w.env.CreateFrame = function(kind, name, parent, template)
        local frame = real(kind, name, parent, template)
        local create = frame.CreateFontString
        frame.CreateFontString = function()
            error("fonts are not available")
        end
        check(create ~= nil)
        return frame
    end
    w:drain()
    w:slash("options")
    check(w:drain():find("could not be built", 1, true), "the failure is explained")
    w:slash("corner br")
    eq(ns.db.corner, "BOTTOMRIGHT")
    eq(#w.errors, 0, "nothing reaches the client's error handler")
end)

test("if the panel cannot be drawn in the Options window, it says so once and does not try again", function()
    local w, ns = Simple()
    local real = w.env.CreateFrame
    w.env.CreateFrame = function(kind, name, parent, template)
        local frame = real(kind, name, parent, template)
        frame.CreateFontString = function()
            error("fonts are not available")
        end
        return frame
    end
    w:drain()
    local canvas = w:openSettings()
    check(w:drain():find("could not be drawn here", 1, true), "the failure is explained")
    eq(canvas.view, nil)

    local frames = #w.frames
    w:openSettings()
    eq(w:drain(), "", "nothing more is said the second time")
    eq(#w.frames, frames + 1, "and nothing more is built (the one new frame is the Options window's own)")

    w:slash("debug")
    check(w:drain():find("fonts are not available", 1, true), "/se debug keeps the reason")
    w:slash("corner br")
    eq(ns.db.corner, "BOTTOMRIGHT", "the commands still work")
    eq(#w.errors, 0, "nothing reaches the client's error handler")
end)

test("a failure while clicking in the panel is reported by the addon, not thrown at the game", function()
    local w, ns = Simple()
    local view = w:openSettings().view
    ns.Relayout = function()
        error("simulated bug")
    end
    w:drain()
    w:click(view.zones.RIGHT)
    eq(#w.errors, 0, "nothing reaches the client's error handler")
    check(w:drain():find("hit a problem", 1, true), "the addon reports it in chat")
    check(tostring(ns.lastError):find("simulated bug", 1, true), "and keeps it for /se debug")
end)

--------------------------------------------------------------------------------
-- Things going wrong around the addon
--------------------------------------------------------------------------------

test("events this client does not have do not stop the addon loading", function()
    local w = World({ unknownEvents = { PLAYER_SOFT_ENEMY_CHANGED = true, UNIT_SPELLCAST_FAILED_QUIET = true } })
    w:addButton("ActionButton1", 1, REND)
    w:load()
    local boar = w:addMob("Boar")
    w:target(boar)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check")
    Clean(w)
end)

test("if icons cannot be created the addon stays quiet", function()
    local w = World({ failCreateFrameWithParent = true })
    w:addButton("ActionButton1", 1, REND)
    w:load()
    local boar = w:addMob("Boar")
    w:target(boar)
    w:advance(3)
    eq(w:icon("ActionButton1"), nil)
    Clean(w)
end)

test("a broken game function is reported once and does not spam", function()
    local w = Simple()
    w.env.C_NamePlate.GetNamePlateForUnit = function()
        error("boom")
    end
    w.env.UnitGUID = function()
        error("boom")
    end
    w:advance(5)
    eq(#w.errors, 0, "nothing reaches the client's error handler")
    Clean(w)
end)

test("an internal failure is caught, reported a few times, then the addon stops itself", function()
    local w = Simple()
    w.ns.Tracker.Update = function()
        error("simulated bug")
    end
    w:drain()
    w:advance(10)
    eq(#w.errors, 0, "nothing reaches the client's error handler")
    local text = w:drain()
    local _, reports = text:gsub("hit a problem", "")
    eq(reports, 1, "one report for one distinct problem")
    check(text:find("stopped after repeated problems", 1, true), "it says it stopped")
    eq(w.ns.halted, true)
end)

test("idle costs nothing", function()
    local w = World()
    w:addButton("ActionButton1", 1, REND)
    w:load()
    w.sampleCalls = 0
    w:advance(30)
    eq(w.sampleCalls, 0, "aura queries with no enemy around")
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:advance(10)
    check(w.sampleCalls <= 60, "aura queries with one target for 10s: " .. w.sampleCalls)
    Clean(w)
end)

test("the addon keeps its hands off the global namespace", function()
    local w, _, boar = Simple({ combatAuras = "count" })
    w:cast(REND)
    w:advance(3)
    w:slash("debug")
    w:slash("list")
    w:slash("options")
    w:click(w.env.StatusEfficiencyOptions.view.swatches.none.plus)
    w:openSettings()
    w:kill(boar)
    w:leaveCombat()
    w:advance(1)

    local allowedWrites = { StatusEfficiencyDB = true, SLASH_STATUSEFFICIENCY1 = true, SLASH_STATUSEFFICIENCY2 = true }
    for name in pairs(w.globalWrites) do
        check(allowedWrites[name], "unexpected global written: " .. name)
    end
    -- Reading a global that does not exist is fine for optional game functions
    -- and for buttons of bar addons that are not installed; anything else is a typo.
    local optional = {
        GetSpellInfo = true, GetSpellDescription = true, IsHarmfulSpell = true, IsHelpfulSpell = true,
        IsPassiveSpell = true, FindSpellOverrideByID = true, StatusEfficiencyDB = true,
    }
    for name in pairs(w.globalMisses) do
        local button = name:find("^ActionButton%d+$") or name:find("^MultiBar%w+Button%d+$")
            or name:find("^BT4Button%d+$") or name:find("^DominosActionButton%d+$")
            or name:find("^ElvUI_Bar%d+Button%d+$")
        check(optional[name] or button, "unexpected global read: " .. name)
    end
    Clean(w)
end)

return tests
