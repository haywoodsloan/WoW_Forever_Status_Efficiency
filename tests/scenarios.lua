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
local BLOCK, HAWK, MONKEY, COMMAND, FORT, MEND, WARD, RAMPAGE, PROWL = 111, 112, 113, 114, 115, 116, 117, 118, 119

local function World(options)
    local w = Mock.new(options)

    -- Most scenarios are about what an icon says, so they run with the icons
    -- appearing whenever there is something to judge: the "always" setting. The
    -- setting itself, and its default, have scenarios of their own, which load
    -- with w:install() or name the setting themselves.
    local load = w.load
    function w:load(saved)
        saved = saved or {}
        if saved.appear == nil then
            saved.appear = "always"
        end
        return load(self, saved)
    end
    --- Loads the addon as a new install does: nothing saved, every default.
    function w:install()
        return load(self, nil)
    end

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
        name = "Hunter's Mark", harmful = true, range = 100,
        description = "Places the Hunter's Mark on the target for 2 min.",
        effect = { duration = 120 },
    })
    w:addSpell(MORTAL, {
        name = "Mortal Strike", harmful = true,
        description = "A vicious strike that wounds the target, reducing healing by 50% for 10 sec.",
        effect = { name = "Mortal Wounds", duration = 10 },
    })
    w:addSpell(FROSTBOLT, {
        name = "Frostbolt", harmful = true, range = 30,
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

    -- Spells that leave a buff on you.
    w:addSpell(BLOCK, {
        name = "Shield Block", selfOnly = true,
        description = "Increases your chance to block by 75% for 10 sec.",
        effect = { buff = true, duration = 10 },
    })
    w:addSpell(HAWK, {
        name = "Aspect of the Hawk", selfOnly = true,
        description = "Take on the aspect of a hawk, increasing ranged attack power by 120. Only one Aspect at a time.",
        effect = { buff = true, duration = 0, replaces = "Aspect of the Monkey" },
    })
    w:addSpell(MONKEY, {
        name = "Aspect of the Monkey", selfOnly = true,
        description = "Take on the aspect of a monkey, increasing your chance to dodge by 8%. Only one Aspect at a time.",
        effect = { buff = true, duration = 0, replaces = "Aspect of the Hawk" },
    })
    w:addSpell(COMMAND, {
        -- No target, and the client does not call it helpful or a self buff.
        name = "Commanding Shout", harmful = false, helpful = false,
        description = "Increases the maximum health of all party members within 20 yards by 1080. Lasts 2 min.",
        effect = { buff = true, duration = 120 },
    })
    w:addSpell(FORT, {
        name = "Fortitude", helpful = true,
        description = "Increases the target's Stamina by 54 for 30 min.",
        effect = { buff = true, duration = 1800 },
    })
    w:addSpell(MEND, {
        name = "Mending Touch", helpful = true,
        description = "Heals a friendly target for 300. The target cannot be mended again for 20 sec.",
    })
    w:addSpell(WARD, {
        name = "Stone Ward", selfOnly = true,
        description = "Absorbs 500 damage. Lasts 30 sec.",
        effect = { buff = true, name = "Stoneskin", duration = 30 },
    })
    w:addSpell(PROWL, {
        name = "Prowl", selfOnly = true,
        description = "Allows you to stalk around unseen. Cast it again to stop.",
        effect = { buff = true, duration = 0, toggle = true },
    })
    w:addSpell(RAMPAGE, {
        -- An attack whose status effect lands on you, not on what it hits.
        name = "Rampage", harmful = true,
        description = "Strikes the target and enrages you, increasing your attack power by 100 for 12 sec.",
        effect = { buff = true, duration = 12 },
    })
    return w
end

-- What the addon saves once it has seen this client report, in combat, that a
-- unit's effects changed: from then on it waits for such a report after a cast
-- instead of assuming the cast landed.
local BUILD = "1.60.1.70888"

local function Proven()
    return { proof = { player = BUILD, target = BUILD, softenemy = BUILD, plate = BUILD } }
end

--- How long the addon would wait for a cast of this spell to show on its target.
local function Wait(ns, spellID)
    return ns.Spells:Wait(ns.Spells:Get(spellID, ns.Now()))
end

--- A world with Rend, Heroic Strike and Battle Shout on the first three buttons
--- and one boar targeted, nameplate showing.
---
--- For this helper and the next ones, `options.saved` is what the addon finds
--- saved from an earlier session.
local function Simple(options)
    local w = World(options)
    w:addButton("ActionButton1", 1, REND)
    w:addButton("ActionButton2", 2, HEROIC)
    w:addButton("ActionButton3", 3, SHOUT)
    local ns = w:load(options and options.saved)
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:advance(0.3)
    return w, ns, boar
end

--- A world with the given spells on the first buttons and nobody around.
local function Bar(options, ...)
    local w = World(options)
    for i = 1, select("#", ...) do
        w:addButton("ActionButton" .. i, i, (select(i, ...)))
    end
    local ns = w:load(options and options.saved)
    return w, ns
end

--- Targets a new boar and opens the fight on it with Rend.
local function Fight(w)
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:advance(0.3)
    w:cast(REND)
    w:advance(0.5)
    return boar
end

--- A world with Thunder Clap and Rend on the first two buttons and three
--- kobolds, nameplates showing, the first one targeted.
local function Pack(options)
    local w = World(options)
    w:addButton("ActionButton1", 1, CLAP)
    w:addButton("ActionButton2", 2, REND)
    local ns = w:load(options and options.saved)
    local mobs = {}
    for i = 1, 3 do
        mobs[i] = w:addMob("Kobold " .. i)
        w:showPlate(mobs[i])
    end
    w:target(mobs[1])
    w:advance(0.5)
    return w, ns, mobs
end

-- Globals the addon may create, and game functions it may look for and not find.
local ALLOWED_WRITES = { StatusEfficiencyDB = true, SLASH_STATUSEFFICIENCY1 = true, SLASH_STATUSEFFICIENCY2 = true }
local OPTIONAL_READS = {
    GetSpellInfo = true, GetSpellDescription = true, IsHarmfulSpell = true, IsHelpfulSpell = true,
    IsPassiveSpell = true, FindSpellOverrideByID = true, StatusEfficiencyDB = true,
    SpellIsSelfBuff = true,
    -- Whole parts of the API that some of the pretend clients leave out.
    issecretvalue = true, C_Secrets = true, C_UnitAuras = true, Settings = true,
    InterfaceOptions_AddCategory = true, GetSpellTexture = true, SOUNDKIT = true, PlaySound = true,
    IsUsableAction = true, IsActionInRange = true,
}

--- Fails the scenario if the addon wrote a global of its own, or read one that
--- does not exist. Reading a missing global is fine for optional game functions
--- and for buttons of bar addons that are not installed; anything else is a typo.
local function Tidy(w)
    for name in pairs(w.globalWrites) do
        check(ALLOWED_WRITES[name], "unexpected global written: " .. name)
    end
    for name in pairs(w.globalMisses) do
        local button = name:find("^ActionButton%d+$") or name:find("^MultiBar%w+Button%d+$")
            or name:find("^BT4Button%d+$") or name:find("^DominosActionButton%d+$")
            or name:find("^ElvUI_Bar%d+Button%d+$")
        check(OPTIONAL_READS[name] or button, "unexpected global read: " .. name)
    end
end

--- Fails the scenario if the addon threw anywhere, loudly or quietly, let a
--- secret value out, or touched a global it should not.
local function Clean(w)
    eq(#w.leaks, 0, "secret values that got past Compat.lua (" .. tostring(w.leaks[1]) .. ")")
    eq(#w.errors, 0, "errors reaching the client (" .. tostring(w.errors[1]) .. ")")
    eq(w.ns.lastError, nil, "errors the addon caught")
    check(not w:drain():find("hit a problem", 1, true), "the addon reported a problem in chat")
    Tidy(w)
end

--------------------------------------------------------------------------------
-- Out of combat
--------------------------------------------------------------------------------

test("debuff icons appear only on status spells, and only with an enemy targeted", function()
    local w = World()
    w:addButton("ActionButton1", 1, REND)
    w:addButton("ActionButton2", 2, HEROIC)
    w:addButton("ActionButton3", 3, SHOUT)
    w:load()
    eq(w:icon("ActionButton1"), nil, "Rend with no target")
    eq(w:icon("ActionButton2"), nil, "Heroic Strike with no target")
    eq(w:icon("ActionButton3"), "check", "Battle Shout is a buff you do not have, target or no target")

    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "Rend on a clean enemy")
    eq(w:icon("ActionButton2"), nil, "Heroic Strike applies nothing")
    eq(w:icon("ActionButton3"), "check", "Battle Shout does not depend on the enemy")

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

test("ids: a miss never turns the icon red", function()
    local w, ns, boar = Simple({ combatAuras = "ids" })
    w:cast(REND)
    w:advance(3)
    w:removeAura(boar, "Rend")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "clean again")

    w:cast(REND, { miss = true })
    w:advance(0.1)
    eq(w:icon("ActionButton1"), "check", "nothing changed on the boar, so nothing is assumed")
    w:advance(3.3)
    eq(w:icon("ActionButton1"), "check", "and nothing showed up")
    eq(ns.db.learned.Rend.casts, 2, "casts counted")
    eq(ns.db.learned.Rend.hits, 1, "hits counted")
    Clean(w)
end)

test("ids, no reports: a miss goes back to green after a moment", function()
    -- A client that never says when a unit's effects change: the cast is
    -- assumed to land, and the count corrects it.
    local w, ns, boar = Simple({ combatAuras = "ids", auraEvents = false })
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
    -- A client that answers the count with an empty list instead of refusing,
    -- with and without reports of a unit's effects changing.
    for _, events in ipairs({ true, false }) do
        local w, ns = Simple({ combatAuras = "empty", auraEvents = events })
        for _ = 1, 6 do
            w:cast(REND)
            w:advance(1)
            eq(w:icon("ActionButton1"), "cross", "after each cast")
            w:advance(21)
        end
        local learned = ns.db.learned.Rend
        if events then
            eq(learned.hits, learned.casts, "every cast was seen to land")
        else
            eq(learned, nil, "nothing was learned or unlearned")
        end
        eq(w:icon("ActionButton1"), "check", "timers still run")
        Clean(w)
    end
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
    eq(w:icon("ActionButton1"), "check", "a miss changes nothing on the boar")
    w:advance(3.3)
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
    eq(w:icon("ActionButton1"), "check", "a miss leaves it green")
    w:advance(2.4)
    eq(w:icon("ActionButton1"), "check")
    Clean(w)
end)

test("a debuff shown by name in combat, no reports: a miss is caught by name", function()
    local w = Simple({ combatAuras = "none", byName = { Rend = true }, auraEvents = false })
    w:cast(REND)
    w:advance(22)
    eq(w:icon("ActionButton1"), "check", "the first one ran out")
    w:cast(REND, { miss = true })
    w:advance(0.1)
    eq(w:icon("ActionButton1"), "cross", "assumed at first")
    w:advance(2.4)
    eq(w:icon("ActionButton1"), "check", "the miss is caught by name")
    Clean(w)
end)

--------------------------------------------------------------------------------
-- In combat on the client as it is documented: nothing about a unit's effects
-- can be read, but the client still says when they change
--------------------------------------------------------------------------------

test("reports: a cast turns the icon red when the enemy's effects change, for as long as the spell lasts", function()
    local w, ns = Simple({ saved = Proven() })
    w:cast(REND)
    w:advance(0.15)
    eq(w:icon("ActionButton1"), "cross", "as soon as the boar's effects changed")
    w:advance(20.5)
    eq(w:icon("ActionButton1"), "cross", "20 seconds in")
    w:advance(1)
    eq(w:icon("ActionButton1"), "check", "after its time ran out")
    eq(ns.db.learned.Rend.hits, 1, "and the cast counts as one that landed")
    Clean(w)
end)

test("reports: a miss, a dodge or a resist leaves the icon green", function()
    local w, ns = Simple({ saved = Proven() })
    w:cast(REND, { miss = true })
    w:advance(0.15)
    eq(w:icon("ActionButton1"), "check", "nothing changed on the boar")
    w:advance(4)
    eq(w:icon("ActionButton1"), "check", "and it stays that way")
    eq(ns.db.learned.Rend, nil, "with nothing reported yet this session, silence is not held against the spell")

    w:cast(REND)
    w:advance(0.15)
    eq(w:icon("ActionButton1"), "cross", "the next one lands")
    w:advance(22)
    eq(w:icon("ActionButton1"), "check", "and runs out")

    w:cast(REND, { miss = true })
    w:advance(4)
    eq(w:icon("ActionButton1"), "check", "a later miss")
    eq(ns.db.learned.Rend.casts, 2, "now that reports have been seen, a silent cast counts as one that left nothing")
    eq(ns.db.learned.Rend.hits, 1)
    Clean(w)
end)

test("reports: until the client has been seen to report in combat, a cast is assumed to land", function()
    local w, ns = Simple()
    local wolf = w:addMob("Wolf")
    w:showPlate(wolf)
    w:advance(0.3)
    eq(ns.Trusted("target"), false, "nothing to go on yet")

    w:cast(REND, { miss = true })
    w:advance(0.15)
    eq(w:icon("ActionButton1"), "cross", "so it is assumed to land, as it always was")
    eq(ns.Trusted("target"), false)

    w:cast(HEROIC) -- nothing changes on the boar
    w:advance(0.5)
    w:removeAura(w.player, "nothing") -- and nothing on you
    eq(w:icon("ActionButton1"), "cross", "still assumed")

    w:advance(21)
    eq(w:icon("ActionButton1"), "check", "until its timer ends")
    eq(ns.db.learned.Rend, nil, "and nothing is learned from it")

    w:cast(REND)
    w:advance(0.15)
    eq(w:icon("ActionButton1"), "cross")
    eq(ns.Trusted("target"), true, "the boar's effects were reported changing in combat")
    eq(ns.Trusted("plate"), true, "through its nameplate too")
    eq(ns.db.proof.target, BUILD, "which is remembered for the next session")
    w:advance(22)

    w:cast(REND, { miss = true })
    w:advance(0.15)
    eq(w:icon("ActionButton1"), "check", "from then on nothing is assumed")
    Clean(w)
end)

test("reports: what is heard about you says nothing about what is reported for a target", function()
    local w, ns = Simple()
    w:cast(REND, { miss = true })
    w:advance(0.15)
    w:applyBuff("Blessing", 60, false) -- someone buffs you in the fight
    w:advance(3)
    eq(ns.Trusted("player"), true)
    eq(ns.Trusted("target"), false)
    eq(w:icon("ActionButton1"), "cross", "the cast on the boar is still only assumed")
    Clean(w)
end)

test("reports, area: the very first cast is assumed to land on everyone, then corrected by who reported", function()
    local w, ns, mobs = Pack()
    for i = 1, 3 do
        mobs[i].engaged = true
    end
    w:enterCombat()
    w:advance(0.5)
    w:cast(CLAP, { hits = { mobs[1], mobs[2] } })
    w:advance(0.05)
    eq(w:icon("ActionButton1"), "cross", "nothing has ever been reported, so everyone is assumed hit")
    w:advance(2.5)
    eq(w:icon("ActionButton1"), "partial", "two nameplates reported a change, so the third one's silence is believed")
    eq(ns.Trusted("plate"), true)
    Clean(w)
end)

test("reports: switching target on a client whose nameplates do not report", function()
    -- Once the boar is no longer the target nothing reports on it any more,
    -- nameplate or not, so its silence is not taken for a miss.
    local w, ns, boar = Simple({ auraTokens = { player = true, target = true }, saved = { proof = { target = BUILD } } })
    local wolf = w:addMob("Wolf")
    w:showPlate(wolf)
    w:advance(0.3)
    w:cast(REND, { travel = 0.5 })
    w:target(wolf)
    w:advance(1)
    w:target(boar)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "taken to have landed")
    eq(ns.Trusted("plate"), false)
    Clean(w)
end)

test("reports: proof from an earlier session is dropped when the client stops reporting", function()
    local w, ns = Simple({ auraEvents = "calm", saved = Proven() })
    for i = 1, 3 do
        w:cast(REND)
        w:advance(0.5)
        eq(w:icon("ActionButton1"), "check", "cast " .. i .. " landed, but no report came")
        w:advance(3)
    end
    eq(ns.db.proof.target, nil, "three casts in a row with no report at all: the proof is dropped")
    eq(ns.Trusted("target"), false)
    w:cast(REND)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross", "and casts are assumed to land again")
    check(ns.db.report.notes[1]:find("taken to land there again", 1, true), "the report says so: " .. ns.db.report.notes[1])
    Clean(w)
end)

test("reports: a missed refresh keeps the old timer, and one that lands restarts it", function()
    local w = Simple({ saved = Proven() })
    w:cast(REND)
    w:advance(10)
    w:cast(REND, { miss = true })
    w:advance(8)
    eq(w:icon("ActionButton1"), "cross", "18 seconds after the one that landed")
    w:advance(4)
    eq(w:icon("ActionButton1"), "check", "it ran out on its own time, not the missed cast's")

    w:cast(REND)
    w:advance(10)
    w:cast(REND)
    w:advance(15)
    eq(w:icon("ActionButton1"), "cross", "25 seconds in, refreshed at 10")
    w:advance(7)
    eq(w:icon("ActionButton1"), "check", "the refreshed one ran out")
    Clean(w)
end)

test("reports: a spell cast from a distance turns red when it lands, however long it flies", function()
    local w, ns = Bar({ saved = Proven() }, FROSTBOLT, REND)
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:advance(0.3)
    eq(Wait(ns, FROSTBOLT), 3, "a spell that may have to fly is given three seconds")
    for i = 1, 3 do
        w:cast(FROSTBOLT, { travel = 0.2 }) -- from right next to the boar
        w:advance(0.4)
        eq(w:icon("ActionButton1"), "cross", "landed at once, cast " .. i)
        w:advance(9)
    end
    eq(Wait(ns, FROSTBOLT), 3, "and keeps them, however quickly it has landed so far")
    w:cast(FROSTBOLT, { travel = 1.5 }) -- from across the field
    w:advance(1.2)
    eq(w:icon("ActionButton1"), "check", "still in the air")
    w:advance(0.6)
    eq(w:icon("ActionButton1"), "cross", "landed")
    local lag = ns.db.learned.Frostbolt.lag
    check(lag >= 1.45 and lag <= 1.6, "how long it took to arrive: " .. tostring(lag))
    Clean(w)
end)

test("reports: a spell used at arm's length is given less time once it has been timed", function()
    local w, ns, boar = Simple({ saved = Proven() })
    eq(Wait(ns, REND), 1.5, "before it has been timed")
    for _ = 1, 3 do
        w:cast(REND)
        w:advance(22)
    end
    eq(Wait(ns, REND), 0.5, "it shows at once, so half a second is plenty")

    w:cast(REND, { miss = true })
    w:advance(0.8)
    w:applyAura(boar, "Sunder Armor", 30, false) -- something else, not a second after the miss
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "is no longer taken for the Rend")

    w:cast(REND, { travel = 0.3 }) -- a slow one
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross", "still in time")
    w:advance(22)
    check(Wait(ns, REND) >= 1.1 and Wait(ns, REND) <= 1.2, "and the wait grows to fit what was seen: " .. Wait(ns, REND))
    for _ = 1, 6 do
        w:cast(REND)
        w:advance(22)
    end
    check(Wait(ns, REND) < 0.7, "then shrinks again as casts show at once: " .. Wait(ns, REND))
    Clean(w)
end)

test("reports: a change reported a moment before the cast is announced still counts for it", function()
    local w = Simple({ saved = Proven() })
    w:cast(REND, { early = 0.1 })
    w:advance(0.15)
    eq(w:icon("ActionButton1"), "cross")
    Clean(w)
end)

test("reports: something else changing on the enemy at that moment passes for a hit", function()
    -- The client says that the boar's effects changed, not which effect or
    -- whose. This is the limit of what an addon can know in combat.
    local w, _, boar = Simple({ saved = Proven() })
    w:applyAura(boar, "Sunder Armor", 30, false) -- someone else's debuff, before the cast
    w:advance(0.4)
    w:cast(REND, { miss = true })
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "check", "a change from before the cast is not put down to it")

    w:applyAura(boar, "Sunder Armor", 30, false) -- and again, half a second after the miss
    w:advance(0.2)
    eq(w:icon("ActionButton1"), "cross", "this one is taken for the Rend")
    Clean(w)
end)

test("reports: a change after the wait is over is not put down to the cast", function()
    local w, _, boar = Simple({ saved = Proven() })
    w:cast(REND, { miss = true })
    w:advance(2)
    w:applyAura(boar, "Sunder Armor", 30, false)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "check")
    Clean(w)
end)

test("reports: two casts in a row are each judged on their own", function()
    local w = Bar({ saved = Proven() }, REND, MARK)
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:advance(0.3)
    w:cast(REND, { miss = true })
    w:advance(0.5)
    w:cast(MARK)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "the change belongs to the newer cast")
    eq(w:icon("ActionButton2"), "cross")
    w:advance(4)
    eq(w:icon("ActionButton1"), "check", "and the older one is not given it later")
    eq(w:icon("ActionButton2"), "cross")

    local wolf = w:addMob("Wolf")
    w:showPlate(wolf)
    w:target(wolf)
    w:advance(0.3)
    w:cast(REND)
    w:advance(0.5)
    w:cast(MARK, { miss = true })
    w:advance(4)
    eq(w:icon("ActionButton1"), "cross", "the other way round: the first landed")
    eq(w:icon("ActionButton2"), "check", "and the second did not")
    Clean(w)
end)

test("reports: switching target while a cast is still in the air", function()
    local w, _, boar = Simple({ saved = Proven() })
    local wolf = w:addMob("Wolf")
    w:showPlate(wolf)
    w:advance(0.3)
    w:cast(REND, { travel = 0.5 })
    w:target(wolf)
    w:advance(1)
    eq(w:icon("ActionButton1"), "check", "the wolf is clean")
    w:target(boar)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "the boar's nameplate reported the change")

    w:advance(22)
    w:cast(REND, { travel = 0.5, miss = true })
    w:target(wolf)
    w:advance(1)
    w:target(boar)
    w:advance(3)
    eq(w:icon("ActionButton1"), "check", "and a miss is still a miss")
    Clean(w)
end)

test("reports: an enemy that goes out of sight during the wait is given the benefit of the doubt", function()
    local w = Bar({ saved = Proven() }, REND)
    local boar = w:addMob("Boar") -- no nameplate: once it is not the target, nothing reports on it
    local wolf = w:addMob("Wolf")
    w:target(boar)
    w:advance(0.3)
    w:cast(REND, { travel = 0.5 })
    w:target(wolf)
    w:advance(1)
    eq(w:icon("ActionButton1"), "check", "the wolf is clean")
    w:target(boar)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "nobody was watching when it would have landed, so it is taken to have")
    Clean(w)
end)

test("reports: targeting an enemy and attacking it straight away is still judged", function()
    local w = Simple({ saved = Proven() })
    local wolf = w:addMob("Wolf")
    w:target(wolf)
    w:advance(0.05)
    w:cast(REND)
    w:advance(0.15)
    eq(w:icon("ActionButton1"), "cross", "a hit")

    local fox = w:addMob("Fox")
    w:target(fox)
    w:advance(0.05)
    w:cast(REND, { miss = true })
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "check", "a miss")
    Clean(w)
end)

test("reports: a token handed to another enemy is not mistaken for a change on it", function()
    for _, mode in ipairs({ "same", "late" }) do
        local w, ns, boar = Simple({ handover = mode, saved = Proven() })
        local wolf = w:addMob("Wolf")
        w:showPlate(wolf)
        w:advance(0.3)
        w:cast(REND) -- so that targets and nameplates are both known to report in combat
        w:advance(22)
        eq(w:icon("ActionButton1"), "check", "ran out")

        w:cast(REND, { miss = true })
        w:advance(0.2)
        w:target(wolf)
        w:advance(0.2)
        w:target(boar) -- back again: this client announces a change for "target" although nothing changed
        w:advance(0.5)
        eq(w:icon("ActionButton1"), "check", "handover " .. mode .. ": no effect changed on the boar")
        local reports = ns.db.report.reports
        check(reports.sameFrame + reports.handover >= 2, "both handovers were recognised: " .. mode)
        Clean(w)
    end
end)

test("reports, area: only the enemies whose effects changed count as hit", function()
    local w, _, mobs = Pack({ saved = Proven() })
    for i = 1, 3 do
        mobs[i].engaged = true
    end
    w:enterCombat()
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "check", "three enemies without Thunder Clap")

    w:cast(CLAP, { hits = { mobs[1], mobs[2] } })
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "partial", "two of the three reported a change")
    w:advance(4)
    eq(w:icon("ActionButton1"), "partial", "and the third never did")

    w:cast(CLAP, { hits = { mobs[1], mobs[2], mobs[3] } })
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "all three")

    w:cast(CLAP, { miss = true })
    w:advance(4)
    eq(w:icon("ActionButton1"), "cross", "a cast that reaches nobody changes nothing")
    w:advance(27)
    eq(w:icon("ActionButton1"), "check", "all ran out")
    Clean(w)
end)

test("reports, area: a client that reports on your target but not on nameplates", function()
    -- The target is judged by its reports. The enemies only a nameplate shows
    -- are assumed hit, as they were before, because nothing was ever heard
    -- through a nameplate.
    local w, ns, mobs = Pack({ auraTokens = { player = true, target = true } })
    for i = 1, 3 do
        mobs[i].engaged = true
    end
    w:enterCombat()
    w:cast(REND)
    w:advance(0.5)
    eq(ns.Trusted("target"), true)
    eq(ns.Trusted("plate"), false)
    w:cast(CLAP, { hits = { mobs[2], mobs[3] } })
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "partial", "the target reported nothing, the other two are assumed")
    w:cast(CLAP)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "now the target reported it too")
    Clean(w)
end)

test("reports, buffs: in combat your buff shows once your own effects change", function()
    local w, ns = Bar({ saved = Proven() }, BLOCK, REND)
    Fight(w)
    w:cast(BLOCK)
    w:advance(0.15)
    eq(w:icon("ActionButton1"), "cross", "your effects changed right after the cast")
    w:advance(9)
    eq(w:icon("ActionButton1"), "cross", "9 seconds in")
    w:advance(1.2)
    eq(w:icon("ActionButton1"), "check", "after it ran out")

    w:cast(BLOCK, { miss = true })
    w:advance(0.15)
    eq(w:icon("ActionButton1"), "check", "a cast that leaves nothing on you stays green")
    w:advance(4)
    eq(w:icon("ActionButton1"), "check")
    eq(ns.db.learned["Shield Block"].buffCasts, nil,
        "what is reported about you in a fight is not held for or against a buff spell")
    Clean(w)
end)

test("reports: a spell you told the addon to track is taken to land whatever is reported", function()
    local w = Simple({ saved = Proven() })
    w:slash("track heroic strike")
    w:advance(0.5)
    w:cast(HEROIC)
    w:advance(0.3)
    eq(w:icon("ActionButton2"), "cross", "it leaves nothing behind, but you asked for it to be tracked")
    w:advance(3.5)
    eq(w:icon("ActionButton2"), "cross", "and silence does not take that away")
    Clean(w)
end)

test("reports: a debuff you told the addon to track is judged by reports once they have borne it out", function()
    local w, ns = Simple({ saved = Proven() })
    w:slash("track rend")
    w:cast(REND, { miss = true })
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "taken to land at first, because you asked for it to be tracked")
    w:advance(22)
    eq(w:icon("ActionButton1"), "check", "for as long as it would have lasted")

    for _ = 1, 3 do
        w:cast(REND)
        w:advance(0.3)
        eq(w:icon("ActionButton1"), "cross")
        w:advance(22)
    end
    eq(ns.db.learned.Rend.hits, 3, "three casts were each followed by a change on the boar")

    w:cast(REND, { miss = true })
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "so there is no doubt left about it: a miss is a miss")
    w:advance(3.5)
    eq(w:icon("ActionButton1"), "check")
    w:cast(REND)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "and a hit is a hit")
    check(ns.db.report.casts[1]:find("taken to land on your say-so", 1, true), "the report says how the first one was judged: "
        .. ns.db.report.casts[1])
    Clean(w)
end)

test("reports: a tracked spell that leaves nothing stays as you asked, whatever else changes on the enemy", function()
    local w, ns, boar = Simple({ saved = Proven() })
    w:slash("track heroic strike")
    w:cast(REND)
    w:advance(1)
    for _ = 1, 6 do
        w:cast(HEROIC)
        w:advance(3)
    end
    for _ = 1, 3 do
        w:cast(HEROIC)
        w:advance(0.1)
        w:auraChanged(boar) -- something else, at just that moment
        w:advance(3)
    end
    eq(ns.db.learned["Heroic Strike"].hits, 3, "three casts looked as if they left something")
    eq(ns.db.learned["Heroic Strike"].casts, 9, "out of nine")
    w:advance(15)
    eq(w:icon("ActionButton2"), "check", "the last one has run out")
    w:cast(HEROIC)
    w:advance(0.3)
    eq(w:icon("ActionButton2"), "cross", "most of its casts changed nothing, so it is still taken to land as you asked")
    w:advance(3.5)
    eq(w:icon("ActionButton2"), "cross")
    Clean(w)
end)

test("reports: a tracked spell that leaves nothing does not take the credit from a cast waiting for it", function()
    local w, ns = Simple({ saved = Proven() })
    w:slash("track heroic strike")
    w:cast(REND, { travel = 0.2 })
    w:advance(0.1)
    w:cast(HEROIC) -- goes off before the boar has shown the Rend
    w:advance(0.4)
    eq(w:icon("ActionButton1"), "cross", "the change on the boar is the Rend's")
    w:advance(3)
    eq(w:icon("ActionButton1"), "cross")
    eq(ns.db.learned.Rend.hits, 1)
    eq(ns.db.learned["Heroic Strike"].hits, 0, "and is not put down to the spell that is taken to land anyway")
    Clean(w)
end)

test("reports: a spell set to always show is judged like any other when its effect has been read by name", function()
    local saved = Proven()
    saved.spells = { Rend = { track = true } }
    saved.learned = { Rend = { exact = true, casts = 0, hits = 0, duration = 21 } }
    local w = Simple({ saved = saved })
    w:cast(REND, { miss = true })
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "what it leaves is known, so nothing needs to be taken on trust")
    w:advance(3.5)
    eq(w:icon("ActionButton1"), "check")
    w:cast(REND)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross")
    Clean(w)
end)

test("reports, area: on a client that reports nothing, enemies pulled in by the spell are assumed hit", function()
    local w, ns, mobs = Pack({ auraEvents = false })
    w:cast(CLAP, { hits = mobs }) -- none of them was in the fight when it was sent
    w:advance(0.05)
    eq(w:icon("ActionButton1"), "check", "nothing to go on yet")
    w:advance(2.5)
    eq(w:icon("ActionButton1"), "cross", "all three are in the fight now and nothing says otherwise")
    eq(ns.Trusted("plate"), false)
    Clean(w)
end)

test("reports: a spell that keeps leaving nothing on the enemy loses its icon", function()
    local w, ns = Bar({ saved = Proven() }, BLOODTHIRST, MARK)
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "trusted at first: it has a duration in its tooltip")
    w:cast(MARK) -- a real debuff, which lasts the whole scenario: the client is heard reporting it
    w:advance(1)
    w:drain()
    for cast = 1, 6 do
        eq(w:icon("ActionButton1"), "check", "still there before cast " .. cast)
        w:cast(BLOODTHIRST)
        w:advance(0.3)
        eq(w:icon("ActionButton1"), "check", "never red: nothing changed on the boar")
        w:advance(3.5)
    end
    eq(ns.db.learned.Bloodthirst.casts, 6)
    eq(ns.db.learned.Bloodthirst.hits, 0)
    eq(w:icon("ActionButton1"), nil, "dropped after six silent casts")
    local said = w:drain()
    check(said:find("Bloodthirst left no status effect behind after 6 of 6 casts", 1, true),
        "and it says so, so that the icon does not just go missing: " .. said)
    check(said:find("/se track Bloodthirst", 1, true), "with the way to get it back")
    w:advance(5)
    eq(w:drain(), "", "said once")
    Clean(w)
end)

test("reports: a run of misses does not cost a real status spell its icon", function()
    local w, ns = Bar({ saved = Proven() }, MORTAL)
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:advance(0.3)
    w:cast(MORTAL)
    w:advance(11)
    w:drain()
    for _ = 1, 4 do
        w:cast(MORTAL, { miss = true })
        w:advance(3.5)
    end
    eq(ns.db.learned["Mortal Strike"].casts, 5)
    eq(ns.db.learned["Mortal Strike"].hits, 1)
    eq(w:icon("ActionButton1"), "check", "four misses in a row, and the icon is still there")
    eq(w:drain(), "")
    Clean(w)
end)

test("no reports: a client that never says when effects change runs on timers as before", function()
    local w, ns = Simple({ auraEvents = false })
    w:cast(REND, { miss = true })
    w:advance(3)
    eq(w:icon("ActionButton1"), "cross", "assumed, with nothing to say otherwise")
    w:advance(18.5)
    eq(w:icon("ActionButton1"), "check", "until the timer ends")
    eq(ns.db.learned.Rend, nil)
    eq(ns.Trusted("target"), false)
    Clean(w)
end)

test("reports: what the client sent is saved for troubleshooting, and kept over a reload", function()
    local w, ns = Simple()
    w:cast(REND)
    w:advance(1)
    w:cast(REND, { miss = true })
    w:advance(4)
    local report = ns.db.report
    eq(report.addon, ns.VERSION)
    eq(report.client, BUILD)
    check(report.reports.target.hidden >= 1, "changes reported for the target while details were hidden")
    check(report.reports.plate.hidden >= 1, "and for its nameplate")
    eq(report.reports.target.readable, 0, "with nothing an addon could read")
    eq(#report.casts, 2, "one line for each cast")
    check(report.casts[1]:find("Rend (debuff, hidden, reports not proven yet): changed, 0.00s after the cast", 1, true),
        report.casts[1])
    check(report.casts[2]:find("Rend (debuff, hidden, waited for a report): silent", 1, true), report.casts[2])
    eq(report.verdicts.changed, 1)
    eq(report.verdicts.silent, 1)
    eq(report.spells.Rend.secrecy, 2, "what the client says about hiding Rend's effect")
    eq(report.spells.Rend.why, "tooltip")
    check(report.refusals.GetUnitAuraInstanceIDs ~= nil, "the refusal to count effects is on record")
    eq(report.nameReads.Rend.found, 0)
    check(report.nameReads.Rend.nothing > 0, "asking for Rend by name gave nothing")
    Clean(w)

    w:slash("debug")
    local debug = w:drain()
    check(debug:find("your target: 1, your soft target: 0 (not relied on yet), nameplates: 1", 1, true),
        "debug counts the reports: " .. debug)
    check(debug:find("1 left something, 1 left nothing", 1, true), "and the casts judged by them: " .. debug)

    -- The next session starts a report of its own and keeps the old one.
    local saved = w.env.StatusEfficiencyDB
    local w2 = World()
    w2.clock = 5000
    w2:addButton("ActionButton1", 1, REND)
    local ns2 = w2:load(saved)
    local boar = w2:addMob("Boar")
    w2:target(boar)
    w2:advance(0.3)
    w2:cast(REND, { miss = true })
    w2:advance(0.15)
    eq(w2:icon("ActionButton1"), "check", "what was proven last session still holds")
    w2:advance(4)
    local second = ns2.db.report
    check(second ~= report, "a new report")
    eq(#second.casts, 1)
    eq(#second.earlier, 1, "the earlier session is kept")
    eq(second.earlier[1].casts[1], report.casts[1])
    eq(second.earlier[1].earlier, nil, "without nesting")
    Clean(w2)
end)

test("reports: a client build that changed is not trusted on the old build's word", function()
    local w, ns = Simple({ clientBuild = "70999", saved = Proven() })
    eq(ns.Trusted("target"), false)
    w:cast(REND, { miss = true })
    w:advance(0.15)
    eq(w:icon("ActionButton1"), "cross", "assumed until this build has been seen to report")
    Clean(w)
end)

--------------------------------------------------------------------------------
-- Area spells
--------------------------------------------------------------------------------

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
    for _ = 1, 5 do
        w:cast(BLOODTHIRST)
        w:advance(3.5)
    end
    eq(w:icon("ActionButton1"), "check", "five empty casts are not enough")
    w:cast(BLOODTHIRST)
    w:advance(3.5)
    eq(ns.db.learned.Bloodthirst.casts, 6)
    eq(w:icon("ActionButton1"), nil, "dropped after six")
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
-- Buffs on you
--------------------------------------------------------------------------------

test("buffs: a spell that only affects you shows whether you have its buff", function()
    local w, ns = Bar(nil, BLOCK)
    eq(w:icon("ActionButton1"), "check", "no buff yet, and no target needed")
    w:cast(BLOCK)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "the buff is up")
    eq(ns.db.learned["Shield Block"].buff, true, "learned that the buff carries the spell's name")
    eq(ns.db.learned["Shield Block"].duration, 10, "learned duration")
    w:advance(9)
    eq(w:icon("ActionButton1"), "cross", "9 seconds in")
    w:advance(1.2)
    eq(w:icon("ActionButton1"), "check", "after it ran out")

    w:cast(BLOCK)
    w:advance(3)
    w:removeAura(w.player, "Shield Block")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "after it was removed early")
    Clean(w)
end)

test("buffs: a buff you already had when the addon loaded is seen straight away", function()
    local w = World()
    w:applyBuff("Shield Block", 10)
    w:addButton("ActionButton1", 1, BLOCK)
    w:load()
    eq(w:icon("ActionButton1"), "cross")
    Clean(w)
end)

test("buffs: the enemy you have targeted makes no difference", function()
    local w = Bar(nil, BLOCK, REND)
    local boar = w:addMob("Boar")
    w:target(boar)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check")
    eq(w:icon("ActionButton2"), "check")
    w:cast(BLOCK)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "your buff")
    eq(w:icon("ActionButton2"), "check", "the boar's debuff is another matter")
    w:target(nil)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "still yours with nothing targeted")
    eq(w:icon("ActionButton2"), nil)
    Clean(w)
end)

test("buffs: one with no timer is learned on sight and followed until it is replaced", function()
    local w, ns = Bar(nil, HAWK, MONKEY)
    eq(w:icon("ActionButton1"), nil, "nothing says it leaves a buff yet")
    w:cast(HAWK)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross", "seen on you, so it is a buff")
    eq(w:icon("ActionButton2"), nil, "the other aspect is still unknown")
    eq(ns.db.learned["Aspect of the Hawk"].duration, 3600, "no timer")
    w:advance(600, 0.25)
    eq(w:icon("ActionButton1"), "cross", "ten minutes later")
    w:cast(MONKEY)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "check", "replaced")
    eq(w:icon("ActionButton2"), "cross")
    Clean(w)
end)

test("buffs: a spell that switches its own buff off is followed both ways", function()
    local w = Bar(nil, PROWL)
    w:cast(PROWL)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross", "on")
    w:cast(PROWL)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "off again, without waiting to see whether the cast lands")
    w:cast(PROWL)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "and on")
    Clean(w)
end)

test("buffs: a spell the client says nothing about is recognised once its buff is seen on you", function()
    local w, ns = Bar(nil, COMMAND)
    eq(w:icon("ActionButton1"), nil, "no target, and nothing says where its effect lands")
    w:cast(COMMAND)
    w:advance(0.6)
    eq(w:icon("ActionButton1"), "cross", "its buff turned up on you, and was looked for right after the cast")
    eq(ns.db.learned["Commanding Shout"].buff, true)
    w:advance(118, 0.25)
    eq(w:icon("ActionButton1"), "cross", "still up shortly before the two minutes are over")
    w:advance(2, 0.25)
    eq(w:icon("ActionButton1"), "check", "and gone once they are")
    w:cast(COMMAND)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "from then on it is known")
    Clean(w)
end)

test("buffs: a buff that turns up late, or was already there, is still learned from", function()
    local w, ns = Bar(nil, COMMAND, HAWK)
    w:cast(COMMAND, { travel = 1 })
    w:advance(0.6)
    eq(w:icon("ActionButton1"), nil, "nothing on you yet")
    w:advance(2.5)
    eq(w:icon("ActionButton1"), "cross", "found on a later look")

    -- Cast before the addon was watching: no cast to go by at all.
    w:applyBuff("Aspect of the Hawk", 0)
    w:advance(2.5)
    eq(w:icon("ActionButton2"), "cross", "seen on you without a cast")
    eq(ns.db.learned["Aspect of the Hawk"].buff, true)
    Clean(w)
end)

test("buffs: an attack that leaves its effect on you is judged on you once that has been seen", function()
    local w, ns = Bar({ combatAuras = "none" }, RAMPAGE)
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "taken for a debuff at first: it is cast on enemies")
    w:cast(RAMPAGE)
    w:advance(2)
    w:kill(boar)
    w:leaveCombat()
    w:advance(0.5)
    eq(ns.db.learned.Rampage.buff, true, "its buff was read off you once the fight was over")
    eq(w:icon("ActionButton1"), "cross", "so it is judged on you, with no enemy left to judge")
    w:advance(10)
    eq(w:icon("ActionButton1"), "check", "and goes green when the buff ends")

    local wolf = w:addMob("Wolf")
    w:target(wolf)
    w:advance(0.3)
    w:cast(RAMPAGE)
    w:advance(1)
    w:target(nil)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "in the next fight it is followed as a buff from the cast on")
    Clean(w)
end)

test("buffs: only a buff you put there yourself counts", function()
    local w = Bar(nil, FORT)
    w:applyBuff("Fortitude", 1800, false) -- from a passing priest
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "check", "theirs, not yours")
    w:cast(FORT)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross")
    Clean(w)
end)

test("buffs: a spell you can cast on others is judged on the friend you have targeted", function()
    local w = Bar(nil, FORT, BLOCK)
    local guard = w:addMob("Guard", { hostile = false })
    w:cast(FORT)
    w:cast(BLOCK)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross", "on you")
    eq(w:icon("ActionButton2"), "cross")

    w:target(guard)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "the guard does not have it")
    eq(w:icon("ActionButton2"), "cross", "a spell that only affects you is still judged on you")

    w:cast(FORT)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross", "now the guard has it too")
    eq(#guard.auras, 1, "it landed on the guard")

    local boar = w:addMob("Boar")
    w:target(boar)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "with an enemy targeted it would land on you, and you have it")
    w:removeAura(w.player, "Fortitude")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "yours is gone")
    w:target(guard)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "the guard still has it")
    w:target(w.player)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "targeting yourself")
    w:kill(guard)
    w:target(guard)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "a dead friend cannot take it, so it is judged on you")
    Clean(w)
end)

test("buffs, ids: in combat a buff is followed by its instance id", function()
    local w = Bar({ combatAuras = "ids" }, BLOCK, REND)
    w:applyBuff("Well Fed", 3600) -- a buff of yours, so the client's counts can be believed
    Fight(w)
    w.spells[BLOCK].effect.duration = 14 -- a talent made it longer than the tooltip says
    w:cast(BLOCK)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "right after the cast")
    w:advance(12)
    eq(w:icon("ActionButton1"), "cross", "past its tooltip duration and still there")
    w:advance(2)
    eq(w:icon("ActionButton1"), "check", "gone")

    w:cast(BLOCK)
    w:advance(3)
    w:removeAura(w.player, "Shield Block")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "removed early")
    Clean(w)
end)

test("buffs, ids: with no buff of yours seen yet this fight, the first cast runs on its timer", function()
    local w, ns = Bar({ combatAuras = "ids" }, BLOCK, REND)
    Fight(w)
    w:cast(BLOCK, { miss = true })
    w:advance(3)
    eq(w:icon("ActionButton1"), "cross", "kept as an assumption: no buffs could be the client hiding them")
    eq(ns.db.learned["Shield Block"], nil, "and not counted as evidence")
    w:advance(7.5)
    eq(w:icon("ActionButton1"), "check", "until its timer ends")
    Clean(w)
end)

test("buffs, ids: a buff named differently from its spell is followed, and an empty cast is noticed", function()
    local w, ns = Bar({ combatAuras = "ids" }, WARD, REND)
    eq(w:icon("ActionButton1"), "check", "tracked from the start: it only affects you and its tooltip has a duration")
    Fight(w)
    w:cast(WARD)
    w:advance(5)
    eq(w:icon("ActionButton1"), "cross")
    w:removeAura(w.player, "Stoneskin") -- the shield was used up
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "used up")

    w:cast(WARD, { miss = true })
    w:advance(0.1)
    eq(w:icon("ActionButton1"), "check", "nothing changed on you, so nothing is assumed")
    w:advance(3.3)
    eq(w:icon("ActionButton1"), "check", "and nothing turned up")

    w:cast(WARD)
    w:advance(25)
    eq(w:icon("ActionButton1"), "cross", "25 seconds in")
    w:advance(6)
    eq(w:icon("ActionButton1"), "check", "expired")
    eq(ns.db.learned["Stone Ward"].buffCasts, 2, "casts that could be judged")
    eq(ns.db.learned["Stone Ward"].buffHits, 1)
    Clean(w)
end)

test("buffs, count: a new buff, an early loss and an empty cast are told from the count", function()
    local w, ns = Bar({ combatAuras = "count" }, WARD, REND)
    Fight(w)
    w:cast(WARD)
    w:advance(5)
    eq(w:icon("ActionButton1"), "cross")
    w:removeAura(w.player, "Stoneskin")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "one buff fewer than the books say")

    w:cast(WARD)
    w:advance(3)
    eq(w:icon("ActionButton1"), "cross")
    eq(ns.db.learned["Stone Ward"].buffHits, 1, "the count went up, so the cast landed")
    w:advance(28)
    eq(w:icon("ActionButton1"), "check", "its timer ran out")

    w:cast(WARD, { miss = true })
    w:advance(3.5)
    eq(w:icon("ActionButton1"), "check", "the count did not move")
    eq(ns.db.learned["Stone Ward"].buffCasts, 2)
    Clean(w)
end)

test("buffs: dying clears what you were assumed to have", function()
    local w = Bar({ combatAuras = "none" }, FORT, REND)
    Fight(w)
    w:cast(FORT)
    w:advance(1)
    eq(w:icon("ActionButton1"), "cross", "assumed for half an hour")
    w:die()
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "gone with you")
    Clean(w)
end)

test("buffs, blind: in combat the spell's own duration is used", function()
    local w = Bar({ combatAuras = "none" }, BLOCK, REND)
    Fight(w)
    w:cast(BLOCK)
    w:advance(0.1)
    eq(w:icon("ActionButton1"), "cross", "right after the cast")
    w:advance(9)
    eq(w:icon("ActionButton1"), "cross", "9 seconds in")
    w:advance(1.5)
    eq(w:icon("ActionButton1"), "check", "after the timer ran out")
    Clean(w)
end)

test("buffs, blind: one you had before the fight keeps its real end time", function()
    local w = Bar({ combatAuras = "none" }, FORT, REND)
    w:cast(FORT)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross")
    Fight(w)
    w:advance(30)
    eq(w:icon("ActionButton1"), "cross", "still there half a minute into the fight")
    Clean(w)
end)

test("buffs: one the client still shows by name in combat is read exactly", function()
    local w, ns = Bar({ combatAuras = "none", byName = { ["Shield Block"] = true } }, BLOCK, REND)
    Fight(w)
    w:cast(BLOCK)
    w:advance(3)
    eq(w:icon("ActionButton1"), "cross")
    eq(ns.db.learned["Shield Block"].buff, true)
    w:removeAura(w.player, "Shield Block")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "seen dropping off by name")

    w:cast(BLOCK, { miss = true })
    w:advance(0.1)
    eq(w:icon("ActionButton1"), "check", "an empty cast leaves it green")
    w:advance(2.4)
    eq(w:icon("ActionButton1"), "check")
    Clean(w)
end)

test("buffs: a client that hides your buffs but not enemy debuffs is handled one kind at a time", function()
    local w = Bar({ combatAuras = "ids", combatBuffs = "empty" }, BLOCK, REND)
    w:applyBuff("Well Fed", 3600)
    local boar = Fight(w)
    w:cast(BLOCK)
    w:advance(5)
    eq(w:icon("ActionButton1"), "cross", "the empty answer about you is not believed")
    eq(w:icon("ActionButton2"), "cross")
    w:removeAura(boar, "Rend")
    w:advance(0.3)
    eq(w:icon("ActionButton2"), "check", "while the enemy's debuffs are still followed by id")
    w:advance(5.5)
    eq(w:icon("ActionButton1"), "check", "your buff ran on its timer")
    Clean(w)
end)

test("buffs: a helpful spell whose tooltip misleads loses its icon", function()
    local w, ns = Bar(nil, MEND)
    w:applyBuff("Well Fed", 3600) -- a buff of yours that no spell on the bars explains
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "trusted at first: it has a duration in its tooltip")
    for _ = 1, 5 do
        w:cast(MEND)
        w:advance(3)
    end
    eq(w:icon("ActionButton1"), "check", "five empty casts are not enough")
    w:drain()
    w:cast(MEND)
    w:advance(3)
    eq(ns.db.learned["Mending Touch"].buffCasts, 6)
    eq(ns.db.learned["Mending Touch"].buffHits, 0)
    eq(w:icon("ActionButton1"), nil, "dropped after six")
    check(w:drain():find("Mending Touch left no status effect behind after 6 of 6 casts", 1, true), "and it says so")
    Clean(w)
end)

test("buffs: what an earlier version learned about a spell as a debuff does not count against its buff", function()
    -- Before buffs were followed, every cast of a buff spell with an enemy
    -- targeted went down as "left no debuff".
    local w = World()
    w:addButton("ActionButton1", 1, WARD)
    w:load({ learned = { ["Stone Ward"] = { casts = 12, hits = 0 } } })
    eq(w:icon("ActionButton1"), "check", "still gets its icon")
    w:cast(WARD)
    w:advance(1)
    eq(w:icon("ActionButton1"), "cross")
    Clean(w)
end)

test("buffs: one buff the client keeps secret even out of combat does not hide the others", function()
    local w, ns = Bar({ alwaysSecret = { ["Sealed Blessing"] = true } }, BLOCK, MEND)
    w:applyBuff("Sealed Blessing", 3600)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check")
    w:cast(BLOCK)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "read by name all the same")
    eq(ns.db.learned["Shield Block"].buff, true)
    w:removeAura(w.player, "Shield Block")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check")

    -- With part of the list unreadable, a cast that adds nothing is not held
    -- against the spell: the secret buff could be its doing.
    for _ = 1, 5 do
        w:cast(MEND)
        w:advance(3)
    end
    eq(ns.db.learned["Mending Touch"], nil, "no evidence recorded")
    eq(w:icon("ActionButton2"), "cross", "kept as an assumption")
    Clean(w)
end)

test("buffs: secret answers and hidden identity in combat do not break anything", function()
    local w = Bar({ combatAuras = "count", secretFlags = true, combatIdentity = false }, FORT, BLOCK, REND)
    local guard = w:addMob("Guard", { hostile = false })
    w:showPlate(guard)
    w:applyBuff("Well Fed", 3600)
    local boar = Fight(w)
    w:cast(BLOCK)
    w:advance(1)
    eq(w:icon("ActionButton2"), "cross")
    w:target(guard)
    w:advance(0.5)
    w:cast(FORT)
    w:advance(1)
    w:target(w.player)
    w:advance(0.5)
    w:target(boar)
    w:advance(0.5)
    eq(w:icon("ActionButton2"), "cross", "still followed after all that")
    w:kill(boar)
    w:leaveCombat()
    w:advance(0.5)
    eq(w:icon("ActionButton2"), "cross", "and read outright once the fight is over")
    w:advance(9)
    eq(w:icon("ActionButton2"), "check")
    Clean(w)
end)

test("buffs: a client that cannot say which spells only affect you still learns them", function()
    local w, ns = Bar({ noSelfBuffAPI = true }, BLOCK)
    eq(w:icon("ActionButton1"), nil, "nothing to go on yet")
    w:cast(BLOCK)
    w:advance(2.5)
    eq(w:icon("ActionButton1"), "cross", "seen on you")
    eq(ns.db.learned["Shield Block"].buff, true)
    Clean(w)
end)

test("/se buff and /se debuff say where a spell's effect lands", function()
    local w, ns = Bar(nil, COMMAND)
    eq(w:icon("ActionButton1"), nil)
    w:drain()
    w:slash("track commanding")
    check(w:drain():find("as a debuff on every enemy in the fight", 1, true), "/se track says how it will be judged")
    w:advance(0.5)
    eq(w:icon("ActionButton1"), nil, "a debuff with no enemy around")

    w:slash("buff commanding")
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "check", "judged on you from now on")
    eq(ns.db.spells["Commanding Shout"].kind, "buff")
    w:cast(COMMAND)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross")
    w:slash("list")
    local list = w:drain()
    check(list:find("Commanding Shout|r: a buff on you, lasting 2 min. Tracked because you turned it on", 1, true),
        "the list says so: " .. list)

    w:slash("debuff commanding shout")
    w:advance(0.5)
    eq(w:icon("ActionButton1"), nil, "a debuff again, and no enemy around")
    eq(ns.db.spells["Commanding Shout"].kind, "debuff")

    w:slash("aoe commanding")
    w:slash("buff commanding")
    w:drain()
    w:slash("single commanding")
    check(w:drain():find("is tracked as a buff on you, so that changes nothing", 1, true),
        "/se single on a buff says it changes nothing")

    w:slash("auto commanding")
    w:advance(2.5)
    eq(ns.db.spells["Commanding Shout"], nil)
    eq(w:icon("ActionButton1"), "cross", "automatic again, and its buff is still on you to be seen")
    Clean(w)
end)

test("a saved choice of kind that makes no sense is ignored", function()
    local w = World()
    w:addButton("ActionButton1", 1, BLOCK)
    w:load({ spells = { ["Shield Block"] = { kind = "sideways" } } })
    eq(w:icon("ActionButton1"), "check", "still a buff on you")
    w:cast(BLOCK)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross")
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

test("a success with no sent event is judged by what the enemy shows afterwards", function()
    local w, ns = Simple({ combatAuras = "ids" })
    w:cast(REND, { noSent = true })
    w:advance(3)
    eq(w:icon("ActionButton1"), "cross")
    eq(ns.db.learned.Rend.hits, 1, "its effects changed right after the cast")
    Clean(w)
end)

test("a success with no sent event and no reports is assumed, not judged", function()
    local w, ns = Simple({ combatAuras = "ids", auraEvents = false })
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
    check(w:drain():find("Usage: /se size <8 to 48 | auto>", 1, true), "too small is refused with the usage line")
    w:slash("size 49")
    check(w:drain():find("Usage: /se size <8 to 48 | auto>", 1, true), "and so is too large")
    w:slash("size huge")
    eq(w.ns.db.size, 0, "and changes nothing")
    w:slash("size 48")
    eq(overlay.width, 48, "the largest size")
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
    check(list:find("a debuff on your target, lasting 21s", 1, true), "list says where Rend is looked for: " .. list)
    check(list:find("Battle Shout|r: a buff on you", 1, true), "list shows Battle Shout as a buff: " .. list)
    check(list:find("lasting 2 min", 1, true), "list gives long durations in minutes: " .. list)
    check(list:find("1 other spell does", 1, true), "list counts the rest: " .. list)
    w:cast(REND)
    w:advance(1)
    w:slash("debug")
    local debug = w:drain()
    check(debug:find("interface 16001", 1, true), "debug shows the interface number: " .. debug)
    check(debug:find("the count only", 1, true), "debug shows what counting gives: " .. debug)
    check(debug:find("Rend, ", 1, true), "debug lists the tracked effect: " .. debug)
    check(debug:find("You right now: your buffs countable", 1, true), "debug says what it can read about you: " .. debug)
    check(debug:find("Your buffs, out of combat (", 1, true), "debug says what it could read about you earlier: " .. debug)
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
-- When the icons appear
--------------------------------------------------------------------------------

test("a new install shows the icons only while an enemy is targeted", function()
    local w = World()
    w:addButton("ActionButton1", 1, REND)
    w:addButton("ActionButton2", 2, HEROIC)
    w:addButton("ActionButton3", 3, SHOUT)
    local ns = w:install()
    eq(ns.db.appear, "target", "the default")
    eq(w:icon("ActionButton1"), nil, "Rend with nothing targeted")
    eq(w:icon("ActionButton3"), nil, "Battle Shout waits for an enemy too")

    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "Rend on a clean enemy")
    eq(w:icon("ActionButton2"), nil, "Heroic Strike applies nothing")
    eq(w:icon("ActionButton3"), "check", "Battle Shout, now that an enemy is targeted")

    local guard = w:addMob("Guard", { hostile = false })
    w:target(guard)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "a friend is not an enemy")
    eq(w:icon("ActionButton3"), nil)

    w:target(boar)
    w:advance(0.3)
    eq(w:icon("ActionButton3"), "check")
    w:kill(boar)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "nor is a dead one")
    eq(w:icon("ActionButton3"), nil)
    Clean(w)
end)

test("what is not shown is still followed", function()
    local w = World({ combatAuras = "ids" })
    w:addButton("ActionButton1", 1, REND)
    w:addButton("ActionButton2", 2, BLOCK)
    w:install()
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:advance(0.3)
    w:cast(REND)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross")
    eq(w:icon("ActionButton2"), "check")

    w:target(nil)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "no enemy targeted, no icons")
    eq(w:icon("ActionButton2"), nil)
    w:cast(BLOCK)
    w:advance(0.5)
    eq(w:icon("ActionButton2"), nil, "still none")

    w:target(boar)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "Rend was followed all along")
    eq(w:icon("ActionButton2"), "cross", "and so was the buff cast while the icons were away")
    Clean(w)
end)

test("/se when always shows a buff at any time, and a debuff whenever there is an enemy to check", function()
    local w = World()
    w:addButton("ActionButton1", 1, REND)
    w:addButton("ActionButton3", 3, SHOUT)
    local ns = w:install()
    w:drain()
    w:slash("when always")
    check(w:drain():find("icons now appear always", 1, true), "it says so")
    eq(ns.db.appear, "always")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "nobody to judge Rend on")
    eq(w:icon("ActionButton3"), "check", "Battle Shout needs nobody")
    local boar = w:addMob("Boar")
    w:target(boar)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check")
    Clean(w)
end)

test("/se when combat shows the icons only during a fight", function()
    local w, ns = Simple({ combatAuras = "ids" })
    w:drain()
    w:slash("when combat")
    check(w:drain():find("icons now appear when in combat", 1, true), "it says so")
    eq(ns.db.appear, "combat")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "an enemy is targeted, but there is no fight yet")
    eq(w:icon("ActionButton3"), nil)

    w:cast(REND)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross", "the fight is on")
    eq(w:icon("ActionButton3"), "check")

    w:target(nil)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "nobody to judge Rend on")
    eq(w:icon("ActionButton3"), "check", "the buff does not need an enemy")

    w:leaveCombat()
    w:advance(0.3)
    eq(w:icon("ActionButton3"), nil, "the fight is over")
    Clean(w)
end)

test("/se when says and sets when the icons appear", function()
    local w, ns = Simple()
    w:drain()
    w:slash("when")
    local said = w:drain()
    check(said:find("icons appear always", 1, true), "with nothing after it, it says how things are: " .. said)
    check(said:find("/se when <always | target | combat>", 1, true), "and how to change them: " .. said)

    w:slash("when target")
    eq(ns.db.appear, "target")
    check(w:drain():find("icons now appear when targeting an enemy", 1, true))
    w:slash("when sometimes")
    eq(ns.db.appear, "target", "a word it does not know changes nothing")
    check(w:drain():find("/se when <always | target | combat>", 1, true))
    w:slash("when ALWAYS")
    eq(ns.db.appear, "always", "capitals do not matter")

    w:slash("off")
    w:drain()
    w:slash("on")
    check(w:drain():find("on. Icons appear always, only on skills you can use right now.", 1, true),
        "/se on says when to expect them")
    Clean(w)
end)

test("a saved choice of when that makes no sense goes back to the default", function()
    for _, bad in ipairs({ "sometimes", 7, false }) do
        local w = World()
        w:addButton("ActionButton1", 1, REND)
        local ns = w:load({ appear = bad })
        eq(ns.db.appear, "target", "saved as " .. tostring(bad))
        Clean(w)
    end
end)

--------------------------------------------------------------------------------
-- On which skills the icons appear
--------------------------------------------------------------------------------

test("an icon only shows on a skill that can be used right now", function()
    local w, ns = Simple()
    eq(ns.db.usableOnly, true, "the default")
    eq(w:icon("ActionButton1"), "check")
    eq(w:icon("ActionButton3"), "check")

    w:setRange(1, false)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "Rend with the boar out of reach: too far, or too close for a skill with a shortest range")
    eq(w:icon("ActionButton3"), "check", "Battle Shout does not mind")
    w:setRange(1, true)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "back in reach")

    w:setUsable(1, false)
    w:setUsable(3, false)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "the wrong stance for Rend")
    eq(w:icon("ActionButton3"), nil, "and Battle Shout held back by the game: buffs follow the same rule")
    w:setUsable(1, true)
    w:setUsable(3, true)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check")
    eq(w:icon("ActionButton3"), "check")
    Clean(w)
end)

test("being short of rage does not take an icon away", function()
    local w, ns = Simple()
    w:setUsable(1, false, true)
    w:setUsable(3, false, true)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "no rage for Rend: it is still worth pressing once there is")
    eq(w:icon("ActionButton3"), "check", "nor for Battle Shout: buffs follow the same rule")

    w:setRange(1, false)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "no rage and out of reach: out of reach still counts")
    w:setRange(1, true)
    w:setUsable(1, false)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "and so does the wrong stance")
    w:setUsable(1, false, true)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check")

    local said = ns.db.report.usable
    check(said.Rend.yes and said.Rend.short and said.Rend.no and said.Rend["short, far"],
        "what the game answered is kept for a look afterwards")
    eq(said.Rend.short, 2, "counted each time the answer turned to it, not each time it was asked")
    Clean(w)
end)

test("an icon stays through a fight in which every skill empties the rage bar", function()
    -- A warrior's fight: each skill is pressed the moment there is rage for it,
    -- and spends it, so the game dims every rage skill right after each press.
    local w = World({ combatAuras = "none" })
    w:addButton("ActionButton1", 1, REND)
    w:addButton("ActionButton2", 2, CLAP)
    w:addButton("ActionButton3", 3, BLOCK)
    w:install()
    local function Spend()
        for slot = 1, 3 do
            w:setUsable(slot, false, true)
        end
    end
    local function Regain()
        for slot = 1, 3 do
            w:setUsable(slot, true)
        end
    end
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    Spend() -- no rage before the pull
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "before the pull, with an empty rage bar")
    eq(w:icon("ActionButton3"), "check")

    w:enterCombat()
    Regain()
    w:advance(0.3)
    w:cast(REND)
    Spend()
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "Rend went on, and its red X is there although the rage is gone")
    eq(w:icon("ActionButton2"), "check", "Thunder Clap is still to come")
    eq(w:icon("ActionButton3"), "check")

    Regain()
    w:advance(1.5)
    w:cast(BLOCK)
    Spend()
    w:advance(0.3)
    eq(w:icon("ActionButton3"), "cross", "Shield Block too")
    eq(w:icon("ActionButton1"), "cross")
    eq(w:icon("ActionButton2"), "check")

    Regain()
    w:advance(1.5)
    w:cast(CLAP)
    Spend()
    for _ = 1, 20 do
        w:advance(0.1)
        eq(w:icon("ActionButton1"), "cross", "no blinking while the rage bar is empty")
        eq(w:icon("ActionButton2"), "cross")
        eq(w:icon("ActionButton3"), "cross")
    end
    Clean(w)
end)

test("when the game will not say why a skill cannot be used, the icon shows", function()
    local w = Simple({ usableAPI = "reason secret" })
    w:setUsable(1, false, true)
    w:setUsable(3, false)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "it could be rage, and rage must not hide an icon")
    eq(w:icon("ActionButton3"), "check", "so the doubt goes the icon's way here as well")
    w:setRange(1, false)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "out of reach is still told plainly")
    Clean(w)
end)

test("a skill that cannot be used loses its red X as well, and what it did is still known", function()
    local w = Simple({ combatAuras = "ids" })
    w:cast(REND)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross")
    w:setRange(1, false)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "nothing to say about a skill that cannot be used")
    w:setRange(1, true)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "Rend is still on the boar")
    Clean(w)
end)

test("the same skill on two buttons is judged button by button", function()
    local w = World()
    w:addButton("ActionButton1", 1, REND)
    w:addButton("ActionButton2", 2, REND, "macro") -- a macro that casts it on something else
    w:load()
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:setRange(2, false)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check")
    eq(w:icon("ActionButton2"), nil, "only the button that cannot be used goes bare")
    Clean(w)
end)

test("/se usable off shows the icon on every skill", function()
    local w, ns = Simple()
    w:setRange(1, false)
    w:setUsable(3, false)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil)
    eq(w:icon("ActionButton3"), nil)

    w:drain()
    w:slash("usable off")
    check(w:drain():find("icons now appear on every skill", 1, true), "it says so")
    eq(ns.db.usableOnly, false)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "out of reach, and shown all the same")
    eq(w:icon("ActionButton3"), "check")

    w.usableAsked = 0
    w:advance(2)
    eq(w.usableAsked, 0, "and the game is no longer asked")

    w:slash("usable on")
    check(w:drain():find("icons now appear only on skills you can use right now", 1, true))
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil)
    Clean(w)
end)

test("/se usable says and sets on which skills the icons appear", function()
    local w, ns = Simple()
    w:drain()
    w:slash("usable")
    local said = w:drain()
    check(said:find("icons appear only on skills you can use right now", 1, true),
        "with nothing after it, it says how things are: " .. said)
    check(said:find("/se usable <on | off>", 1, true), "and how to change them: " .. said)

    w:slash("usable maybe")
    eq(ns.db.usableOnly, true, "a word it does not know changes nothing")
    check(w:drain():find("/se usable <on | off>", 1, true))
    w:slash("usable OFF")
    eq(ns.db.usableOnly, false, "capitals do not matter")

    w:slash("off")
    w:drain()
    w:slash("on")
    check(w:drain():find("on. Icons appear always, on every skill.", 1, true), "/se on says what to expect")
    w:slash("help")
    check(w:drain():find("/se usable <on | off>", 1, true), "and /se lists the command")
    Clean(w)
end)

test("when the game will not say whether a skill can be used, the icon shows", function()
    for _, api in ipairs({ "none", "secret" }) do
        local w = Simple({ usableAPI = api })
        w:setRange(1, false)
        w:setUsable(3, false)
        w:advance(0.3)
        eq(w:icon("ActionButton1"), "check", api .. ": Rend")
        eq(w:icon("ActionButton3"), "check", api .. ": Battle Shout")
        w:drain()
        w:slash("usable")
        check(w:drain():find("not telling the addon whether a skill can be used", 1, true),
            api .. ": and /se usable owns up to it")
        Clean(w)
    end

    local w = Simple()
    w:drain()
    w:slash("usable")
    check(not w:drain():find("not telling", 1, true), "no such note on a client that answers")
    Clean(w)
end)

test("an older client's plain answers about using a skill are understood", function()
    local w = Simple({ usableAPI = "globals" })
    eq(w:icon("ActionButton1"), "check", "1 for usable, and no word on range")
    w:setRange(1, false)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "0 for out of reach")
    w:setRange(1, true)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "1 for in reach")
    w:setUsable(1, false)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "nothing at all for a skill that cannot be used")
    w:setUsable(1, false, true)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "nothing and then 1 for a skill there is no rage for")
    Clean(w)
end)

test("a saved choice about usable skills is kept, and one that makes no sense goes back to the default", function()
    for _, bad in ipairs({ "sometimes", 7 }) do
        local w = World()
        w:addButton("ActionButton1", 1, REND)
        local ns = w:load({ usableOnly = bad })
        eq(ns.db.usableOnly, true, "saved as " .. tostring(bad))
        Clean(w)
    end
    local w = World()
    w:addButton("ActionButton1", 1, REND)
    local ns = w:load({ usableOnly = false })
    eq(ns.db.usableOnly, false, "a real choice survives a reload")
    w:slash("reset")
    eq(ns.db.usableOnly, true, "/se reset goes back to usable skills only")
    Clean(w)
end)

--------------------------------------------------------------------------------
-- The settings panel
--------------------------------------------------------------------------------

local SKULL = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"

local function Art(w, button)
    return w:overlay(button).textures[1].path
end

local function near(actual, expected, what)
    if math.abs(actual - expected) > 0.01 then
        error(string.format("%s: expected about %s, got %s", what or "value", tostring(expected), tostring(actual)), 2)
    end
end

--- A scenario for the panel runs twice: on a client that has the game's own
--- buttons, tick boxes and sliders, and on one that has none of them, where the
--- panel draws its own. `fn` gets the options to make its world with.
local function panel(name, fn)
    test("settings: " .. name, function()
        fn({})
    end)
    test("settings, drawn by the addon: " .. name, function()
        fn({ noTemplates = true })
    end)
end

--- One step down (-1) or up (1) with the buttons at the ends of the size slider.
local function Step(w, view, direction)
    local slider = view.size.slider
    if slider.native then
        w:click(direction < 0 and slider.frame.Back or slider.frame.Forward)
    else
        w:click(direction < 0 and slider.less or slider.more)
    end
end

test("settings: the panel is added to the game's Options window", function()
    local w = Simple()
    eq(#w.settings.addons, 1, "panels registered under AddOns")
    eq(w.settings.addons[1].name, "Status Efficiency")
    local canvas = w:openSettings()
    check(canvas.view ~= nil, "the panel is built when it is first shown")
    eq(canvas.view.tab, "appearance", "and opens on the Appearance tab")
    eq(canvas.view.pages.appearance:IsVisible(), true)
    eq(canvas.view.pages.spells:IsVisible(), false)
    Clean(w)
end)

panel("the game's own controls are used where the client has them", function(options)
    local w = Simple(options)
    local view = w:openSettings().view
    local native = not options.noTemplates
    eq(view.enable.native == true, native, "the tick box")
    eq(view.size.slider.native == true, native, "the size slider")
    eq(view.size.auto.native == true, native, "the Auto tick box")
    eq(view.reset.native == true, native, "the reset button")
    eq(view.confirm.yes.native == true, native, "the buttons that confirm it")
    w:slash("options")
    local window = w.env.StatusEfficiencyOptions
    eq(window.close.template == "UIPanelCloseButtonNoScripts", native, "the window's close button")
    eq(window.view.enable.native == true, native, "and the same in the window of its own")
    Clean(w)
end)

test("/se plain makes the panel draw its own controls from the next reload", function()
    local w, ns = Simple()
    w:drain()
    w:slash("plain")
    eq(ns.db.plain, true)
    check(w:drain():find("/reload", 1, true), "it says a reload is needed")
    eq(w:openSettings().view.enable.native, nil, "panels built from then on are plain")

    local saved = ns.db
    w = Simple() -- the same client, after the reload
    w.ns.db.plain = saved.plain
    local view = w:openSettings().view
    eq(view.enable.native, nil, "no game tick box")
    eq(view.size.slider.native, nil, "no game slider")
    eq(view.reset.native, nil, "no game button")
    w:click(view.enable.frame)
    eq(w.ns.db.enabled, false, "and it all still works")
    w:drain()
    w:slash("plain")
    eq(w.ns.db.plain, false, "/se plain again goes back")
    check(w:drain():find("game's own buttons and sliders again", 1, true))
    Clean(w)
end)

test("settings: a control of the game's that does not work as expected is replaced, not left half made", function()
    local w, ns = Simple({ brokenTemplates = { MinimalSliderWithSteppersTemplate = true } })
    local view = w:openSettings().view
    eq(view.size.slider.native, nil, "the slider is the addon's own")
    eq(view.enable.native, true, "the other controls are still the game's")
    for i = 1, #w.frames do
        if w.frames[i].template == "MinimalSliderWithSteppersTemplate" then
            eq(w.frames[i].shown, false, "the game's slider that failed is hidden")
        end
    end
    w:slide(view.size.slider.widget, 26)
    eq(ns.db.size, 26, "and the replacement works")
    Clean(w)

    -- Only some of the templates exist.
    w, ns = Simple({ noTemplates = { MinimalCheckboxTemplate = true } })
    view = w:openSettings().view
    eq(view.enable.native, nil)
    eq(view.size.slider.native, true)
    w:click(view.enable.frame)
    eq(ns.db.enabled, false)
    Clean(w)
end)

test("settings: a client short of a font, an atlas, lines or sounds still gets the whole panel", function()
    local w, ns = Simple({
        missingFonts = { GameFontHighlightHuge = true }, noAtlas = true, noLines = true, noSounds = true,
        noSpellTexture = true,
    })
    local view = w:openSettings().view
    check(view ~= nil, "the panel is built")
    w:click(view.swatches.all.hidden)
    eq(ns.db.icons.all, "hidden", "the tile for no icon works without its stroke")
    w:click(view.tabs.spells)
    eq(view.spells.rows[1].icon.path, "Interface\\Icons\\INV_Misc_QuestionMark",
        "a spell whose picture cannot be asked for gets a question mark")
    w:slash("options")
    check(w.env.StatusEfficiencyOptions:IsShown())
    Clean(w)
end)

panel("the tick box turns the icons off and on, like /se off and /se on", function(options)
    local w, ns = Simple(options)
    local view = w:openSettings().view
    w:slash("options")
    local window = w.env.StatusEfficiencyOptions.view
    w:advance(0.2)
    eq(view.enable.ticked, true)
    eq(w:icon("ActionButton1"), "check")

    w:click(view.enable.frame)
    eq(ns.db.enabled, false)
    eq(view.enable.ticked, false)
    eq(window.enable.ticked, false, "the other copy follows")
    if view.enable.native then
        eq(window.enable.frame:GetChecked(), false, "the game's box is unticked too")
    end
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "no icons, not even samples")
    check(view.sampleNote:GetText():find("turned off", 1, true), "and the panel says why")

    w:slash("on")
    eq(view.enable.ticked, true, "/se on ticks it again")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check")
    w:slash("off")
    eq(view.enable.ticked, false, "/se off unticks it")

    w:click(window.enable.frame)
    eq(ns.db.enabled, true)
    eq(view.enable.ticked, true)
    if view.enable.native then
        eq(view.enable.frame:GetChecked(), true)
    end
    Clean(w)
end)

panel("picking when the icons appear", function(options)
    local w, ns = Simple(options)
    local view = w:openSettings().view
    eq(view.appear.picked, "always", "what these scenarios load with")
    eq(view.appear.buttons.always.picked, true)

    w:click(view.appear.buttons.combat)
    eq(ns.db.appear, "combat")
    eq(view.appear.picked, "combat")
    eq(view.appear.buttons.always.picked, false)
    w:slash("when target")
    eq(view.appear.picked, "target", "/se when moves it too")

    local title, lines = w:hover(view.appear.buttons.target)
    eq(title, "When targeting an enemy")
    check(lines[1]:find("enemy targeted", 1, true), "each choice explains itself: " .. tostring(lines[1]))
    w:unhover(view.appear.buttons.target)
    eq(w.tooltip, nil)

    w:click(view.enable.frame)
    near(view.appear.frame:GetAlpha(), 0.4, "dimmed while the icons are off")
    w:click(view.enable.frame)
    near(view.appear.frame:GetAlpha(), 1)

    w:closeSettings()
    w:advance(0.3)
    eq(w:icon("ActionButton3"), "check", "an enemy is targeted")
    w:target(nil)
    w:advance(0.3)
    eq(w:icon("ActionButton3"), nil, "and now none is")
    Clean(w)
end)

panel("picking on which skills the icons appear", function(options)
    local w, ns = Simple(options)
    local view = w:openSettings().view
    w:slash("options")
    local window = w.env.StatusEfficiencyOptions.view
    eq(view.usable.picked, "usable", "only on usable skills to begin with")
    eq(view.usable.buttons.usable.picked, true)

    w:click(view.usable.buttons.always)
    eq(ns.db.usableOnly, false)
    eq(view.usable.picked, "always")
    eq(window.usable.picked, "always", "the other copy follows")
    w:slash("usable on")
    eq(view.usable.picked, "usable", "/se usable moves it too")

    local title, lines = w:hover(view.usable.buttons.usable)
    eq(title, "Only when the skill is usable")
    check(lines[1]:find("too close", 1, true), "each choice explains itself: " .. tostring(lines[1]))
    check(lines[1]:find("cooldown", 1, true), "and says what does not count")
    w:unhover(view.usable.buttons.usable)

    w:click(view.enable.frame)
    near(view.usable.frame:GetAlpha(), 0.4, "dimmed while the icons are off")
    w:click(view.enable.frame)
    near(view.usable.frame:GetAlpha(), 1)

    -- Sample icons are for judging the look, so they show on every button.
    w:setUsable(1, false)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "a sample, on a skill that cannot be used")
    w:closeSettings()
    w.env.StatusEfficiencyOptions:Hide()
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "the real icon stays away")
    eq(w:icon("ActionButton3"), "check")
    Clean(w)
end)

panel("sample icons show on the real buttons while the Appearance tab is open", function(options)
    local w = World(options)
    w:addButton("ActionButton1", 1, REND)
    w:addButton("ActionButton2", 2, HEROIC)
    w:addButton("ActionButton3", 3, SHOUT)
    w:addButton("ActionButton4", 4, nil)
    w:install() -- icons only with an enemy targeted, and nothing is targeted
    eq(w:icon("ActionButton1"), nil)

    local view = w:openSettings().view
    w:advance(0.2)
    eq(w:icon("ActionButton1"), "check", "the three results in turn")
    eq(w:icon("ActionButton2"), "partial", "on every button that holds a spell, with an icon of its own or not")
    eq(w:icon("ActionButton3"), "cross")
    eq(w:icon("ActionButton4"), nil, "an empty button stays empty")
    check(view.sampleNote:GetText():find("sample icons", 1, true), "the panel says what they are")

    w:click(view.tabs.spells)
    w:advance(0.2)
    eq(w:icon("ActionButton1"), nil, "not while the Spells tab is up")
    w:click(view.tabs.appearance)
    w:advance(0.2)
    eq(w:icon("ActionButton2"), "partial")

    w:closeSettings()
    w:advance(0.2)
    eq(w:icon("ActionButton2"), nil, "gone when the Options window closes")
    w:openSettings()
    w:advance(0.2)
    eq(w:icon("ActionButton2"), "partial", "back when it opens again")
    w:leaveSettings()
    w:advance(0.2)
    eq(w:icon("ActionButton2"), nil, "gone when the Options window moves to another page")

    w:slash("options")
    w:advance(0.2)
    eq(w:icon("ActionButton2"), "partial", "the window of its own does the same")
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:cast(REND)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross", "in a fight the real icons take over")
    eq(w:icon("ActionButton2"), nil)
    w:leaveCombat()
    w:target(nil)
    w:advance(0.3)
    eq(w:icon("ActionButton2"), "partial", "and the samples come back after it")
    w:slash("options")
    w:advance(0.2)
    eq(w:icon("ActionButton2"), nil, "until the window closes")
    Clean(w)
end)

panel("the preview shows all three icons life-size, where and as large as on the bars", function(options)
    local w, ns = Simple(options)
    local view = w:openSettings().view
    for _, state in ipairs(ns.Icons.STATES) do
        local preview = view.previews[state.key]
        eq(preview.button.width, 45, "a pretend button as large as a real one")
        eq(preview.icon.path, ns.Icons.Texture(state.key), "with the icon for " .. state.key)
        eq(preview.icon.width, 16, "the size it is on the bars")
        eq(preview.icon.point[1], "TOPLEFT", "in the same spot")
        eq(preview.caption:GetText(), state.title, "and the result's name under it")
    end
    eq(view.previews.none.face.path, 130000 + SHOUT, "the pretend buttons wear spells from your own bars")
    eq(view.previews.some.face.path, 130000 + REND, "those with an icon first")
    eq(view.previews.all.face.path, 130000 + HEROIC)

    w:slash("size 30")
    w:slash("corner br")
    eq(view.previews.some.icon.width, 30)
    eq(view.previews.some.icon.point[1], "BOTTOMRIGHT")
    eq(view.previews.all.zones.BOTTOMRIGHT.ghost.shown, false, "no dot under the icon")
    eq(view.previews.all.zones.TOPLEFT.ghost.shown, true, "a dot on every other spot")
    Clean(w)
end)

test("settings: the preview follows the size the action buttons are really drawn at", function()
    local w = World()
    local button = w:addButton("ActionButton1", 1, REND)
    button.scale = 0.8 -- a bar that has been scaled down
    local ns = w:load()
    local view = w:openSettings().view
    near(view.previews.none.button.width, 36, "45 wide drawn at 0.8")
    near(view.previews.none.icon.width, 16 * 0.8, "and the icon scaled with it")

    button.scale, button.width = 1, 90 -- or a bar addon with very large buttons
    ns.Relayout()
    ns.Options.RefreshAll()
    eq(view.previews.none.button.width, 60, "a pretend button never outgrows its room")
    near(view.previews.none.icon.width, 32 * 60 / 90, "the icon keeps its share of the button")

    w:slash("size 48")
    eq(view.previews.none.slot.clips, true, "an icon set far too large is cut off at the edge of the room")
    Clean(w)

    -- Before any button has been found there is still something to show.
    w = World()
    w:load()
    view = w:openSettings().view
    eq(view.previews.none.button.width, 45, "a standard button")
    eq(view.previews.none.face.path, "Interface\\Icons\\INV_Misc_QuestionMark")
    Clean(w)
end)

panel("clicking a spot on any pretend button moves the icon on every button", function(options)
    local w, ns = Simple(options)
    local view = w:openSettings().view
    eq(w:overlay("ActionButton1").point[1], "TOPLEFT", "starts in the top left")

    w:click(view.previews.all.zones.BOTTOMRIGHT)
    eq(ns.db.corner, "BOTTOMRIGHT")
    eq(w:overlay("ActionButton1").point[1], "BOTTOMRIGHT", "the real icon moved")
    eq(view.previews.none.icon.point[1], "BOTTOMRIGHT", "and so did all three previews")
    eq(view.previews.some.icon.point[1], "BOTTOMRIGHT")

    w:click(view.previews.some.zones.TOP)
    eq(w:overlay("ActionButton1").point[1], "TOP", "edges work as well as corners")
    eq(w:hover(view.previews.some.zones.CENTER), "Middle", "each spot says where it is")
    Clean(w)
end)

panel("the size slider runs from 8 to 48, with a tick box to follow the button", function(options)
    local w, ns = Simple(options)
    local view = w:openSettings().view
    local overlay = w:overlay("ActionButton1")
    local slider = view.size.slider
    eq(view.size.auto.ticked, true, "starts out following the button")
    eq(view.size.readout:GetText(), "16")
    eq(slider.widget:GetValue(), 16, "the slider sits at the size in use")
    local low, high = slider.widget:GetMinMaxValues()
    eq(low, 8)
    eq(high, 48)

    w:slide(slider.widget, 30)
    eq(ns.db.size, 30)
    eq(overlay.width, 30, "the real icon follows straight away")
    eq(view.size.readout:GetText(), "30")
    eq(view.size.auto.ticked, false)

    Step(w, view, -1)
    eq(ns.db.size, 29, "the buttons at the ends go one at a time")
    Step(w, view, 1)
    Step(w, view, 1)
    eq(ns.db.size, 31)
    eq(slider.widget:GetValue(), 31)

    w:slide(slider.widget, 500)
    eq(ns.db.size, 48, "it stops at the largest size")
    Step(w, view, 1)
    eq(ns.db.size, 48)
    w:slide(slider.widget, 2)
    eq(ns.db.size, 8, "and at the smallest")
    Step(w, view, -1)
    eq(ns.db.size, 8)

    w:click(view.size.auto.frame)
    eq(ns.db.size, 0, "ticking Auto follows the button again")
    eq(overlay.width, 16)
    eq(slider.widget:GetValue(), 16)
    eq(view.size.readout:GetText(), "16")

    w:click(view.size.auto.frame)
    eq(ns.db.size, 16, "unticking keeps the icon the size it was, as a size of its own")
    eq(view.size.auto.ticked, false)
    eq(w:hover(view.size.auto.frame), "Auto")
    Clean(w)
end)

test("settings: both copies of the panel stay in step", function()
    local w, ns = Simple()
    w:slash("options")
    local window = w.env.StatusEfficiencyOptions.view
    local inOptions = w:openSettings().view
    w:slash("size 24")
    eq(window.size.readout:GetText(), "24")
    eq(inOptions.size.readout:GetText(), "24")
    Step(w, window, -1)
    eq(inOptions.size.readout:GetText(), "23", "a click in one copy shows in the other")
    eq(inOptions.size.slider.widget:GetValue(), 23)

    w:click(window.swatches.some.exclaim)
    eq(inOptions.swatches.some.exclaim.ring.shown, true)
    w:click(inOptions.previews.none.zones.LEFT)
    eq(window.previews.all.icon.point[1], "LEFT", "and the other way round")
    w:click(inOptions.appear.buttons.combat)
    eq(window.appear.picked, "combat")

    w:slash("size auto")
    eq(window.size.auto.ticked, true)
    eq(ns.db.size, 0)
    Clean(w)
end)

panel("picking an icon changes what the buttons show", function(options)
    options.combatAuras = "none"
    local w, ns = Simple(options)
    local view = w:openSettings().view
    w:advance(0.2)
    eq(w:icon("ActionButton1"), "check")
    eq(view.swatches.none.check.ring.shown, true, "the icon in use is framed")

    w:click(view.swatches.none.greendot)
    eq(ns.db.icons.none, "greendot")
    check(Art(w, "ActionButton1"):find("DotGreen.tga", 1, true), "the button shows the green dot straight away")
    eq(view.swatches.none.greendot.ring.shown, true)
    eq(view.swatches.none.check.ring.shown, false)
    eq(view.swatches.all.cross.ring.shown, true, "the other results are untouched")
    check(view.current.none.path:find("DotGreen.tga", 1, true), "the result's heading shows the icon in use")
    check(view.previews.none.icon.path:find("DotGreen.tga", 1, true), "and so does the preview")

    w:click(view.swatches.all.skull)
    w:closeSettings()
    w:cast(REND)
    w:advance(0.5)
    eq(Art(w, "ActionButton1"), SKULL, "the skull now means there is no need to cast")
    Clean(w)
end)

test("settings: the addon's ten icons are on one line and the game's eleven on the next", function()
    local w, ns = Simple()
    local view = w:openSettings().view
    local own, game = 0, 0
    for _, state in ipairs(ns.Icons.STATES) do
        local lineOne, lineTwo
        for _, choice in ipairs(ns.Icons.CHOICES) do
            local tile = view.swatches[state.key][choice.key]
            check(tile, "missing tile " .. choice.key .. " for " .. state.key)
            eq(tile.art.path, choice.texture)
            local _, _, _, _, y = tile:GetPoint(1)
            if choice.own then
                own = own + 1
                lineOne = lineOne or y
                eq(y, lineOne, choice.key .. " is on the first line")
            else
                game = game + 1
                lineTwo = lineTwo or y
                eq(y, lineTwo, choice.key .. " is on the second line")
            end
        end
        check(lineTwo < lineOne, "the game's icons sit under the addon's")
        check(ns.Icons.Choice(state.default), "default for " .. state.key .. " exists")
    end
    eq(own, 3 * 10, "the addon's own icons")
    eq(game, 3 * 11, "the game's icons")
    eq(w:hover(view.swatches.all.reddot), "Red dot", "each one says what it is")
    Clean(w)
end)

test("the three results are named for what they tell you to do", function()
    local w, ns = Simple()
    local view = w:openSettings().view
    eq(ns.Icons.State("none").title, "Worth casting")
    eq(ns.Icons.State("some").title, "Partly worth casting")
    eq(ns.Icons.State("all").title, "No need to cast")
    eq(view.previews.all.caption:GetText(), "No need to cast")
    w:drain()
    w:slash("icons")
    local listing = w:drain()
    check(listing:find("Worth casting: check", 1, true), "/se icons uses the same names: " .. listing)
    check(listing:find("No need to cast: cross", 1, true), listing)
    w:slash("icon worth plus")
    eq(ns.db.icons.none, "plus", "and /se icon takes them, as well as the colours")
    w:slash("icon noneed stop")
    eq(ns.db.icons.all, "stop")
    Clean(w)
end)

panel("an icon set changes all three icons, and the set in use is marked", function(options)
    local w, ns = Simple(options)
    local view = w:openSettings().view
    eq(view.sets.marks.picked, true, "starts on the check, half circle and X")
    eq(view.sets.dots.picked, false)

    w:click(view.sets.dots)
    eq(ns.db.icons.none, "greendot")
    eq(ns.db.icons.some, "yellowdot")
    eq(ns.db.icons.all, "reddot")
    eq(view.sets.dots.picked, true)
    eq(view.sets.marks.picked, false)
    w:advance(0.2)
    check(Art(w, "ActionButton3"):find("DotRed.tga", 1, true), "the sample on the third button is the red dot")

    w:click(view.swatches.some.star)
    eq(view.sets.dots.picked, false, "a mix is no set")
    w:click(view.sets.ready)
    eq(ns.db.icons.some, "waiting")
    eq(w:hover(view.sets.symbols), "Plus, exclamation mark and stop sign", "each set says what is in it")
    Clean(w)
end)

panel("two results that share an icon are pointed out", function(options)
    local w = Simple(options)
    local view = w:openSettings().view
    eq(view.clashes.some:IsShown(), false, "nothing to say to begin with")

    w:click(view.swatches.some.check)
    eq(view.clashes.some:IsShown(), true)
    eq(view.clashes.some:GetText(), "Same icon as \"Worth casting\"")
    eq(view.clashes.none:IsShown(), false, "only the later of the two says so")
    w:click(view.swatches.all.check)
    eq(view.clashes.all:GetText(), "Same icon as \"Worth casting\"")

    w:click(view.swatches.some.hidden)
    eq(view.clashes.some:IsShown(), false, "no icon clashes with nothing")
    w:click(view.swatches.none.hidden)
    eq(view.clashes.all:IsShown(), false)
    Clean(w)
end)

panel("a result can be given no icon at all", function(options)
    options.combatAuras = "none"
    local w, ns = Simple(options)
    local view = w:openSettings().view
    local title, lines = w:hover(view.swatches.all.hidden)
    eq(title, "No icon")
    check(lines[1]:find("stay bare", 1, true))

    w:click(view.swatches.all.hidden)
    eq(ns.db.icons.all, "hidden")
    eq(view.swatches.all.hidden.ring.shown, true, "the bare tile is framed")
    eq(view.swatches.all.cross.ring.shown, false)
    eq(view.previews.all.icon.shown, false, "the pretend button is bare")
    eq(view.current.all.shown, false)
    w:advance(0.2)
    eq(w:icon("ActionButton3"), nil, "and so is the sample for that result")
    eq(w:icon("ActionButton1"), "check", "the other results keep their icons")

    w:closeSettings()
    w:cast(REND)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), nil, "Rend is on the boar, and that result shows nothing")
    w:slash("icon red default")
    w:advance(0.2)
    eq(w:icon("ActionButton1"), "cross")

    w:drain()
    w:slash("icon red none")
    check(w:drain():find("now shows no icon", 1, true), "/se icon ... none does the same")
    eq(ns.db.icons.all, "hidden")
    w:advance(0.2)
    eq(w:icon("ActionButton1"), nil)
    eq(ns.Icons.CurrentName("all"), "No icon")
    w:slash("icons")
    check(w:drain():find("No need to cast: none", 1, true), "and /se icons lists it")
    Clean(w)
end)

panel("the icons to pick from line up in one grid", function(options)
    local w, ns = Simple(options)
    local view = w:openSettings().view
    for _, state in ipairs(ns.Icons.STATES) do
        local tiles = view.swatches[state.key]
        local first, last = tiles.check.point, tiles.skull.point
        local hidden, custom = tiles[ns.Icons.HIDDEN].point, tiles.custom.point
        eq(hidden[5], first[5], "\"no icon\" sits on the first line, with the addon's own icons")
        eq(hidden[4], last[4], "in the column the second line ends in")
        eq(custom[5], first[5], "your own texture comes after it")
        eq(custom[4] - hidden[4], tiles.ring.point[4] - tiles.stop.point[4], "one step along")
        local editor = view.editors[state.key]
        eq(editor.point[5], first[5], "and its box opens beside it")
        check(editor.point[4] >= custom[4] + tiles.custom.width, "clear of the tile")
        check(editor.point[4] + editor.width <= 624, "and inside the page")
    end
    Clean(w)
end)

panel("your own texture: the tile opens a box that explains itself", function(options)
    options.missingTextures = { [424242] = true }
    local w, ns = Simple(options)
    local view = w:openSettings().view
    local editor, box = view.editors.none, view.inputs.none
    eq(editor:IsShown(), false, "the box stays out of the way until it is asked for")

    w:click(view.swatches.none.custom)
    eq(editor:IsShown(), true)
    eq(box:HasFocus(), true, "ready to type into")
    eq(editor.note:GetText(), "A file ID or a path, then Enter.")

    w:drain()
    w:type(box, "nonsense")
    check(editor.note:GetText():find("Not a texture", 1, true), "a bad entry is explained next to the box")
    eq(w:drain(), "", "and not in the chat window")
    eq(ns.db.icons.none, nil, "it changes nothing")
    eq(box:HasFocus(), true, "and the box stays ready for another go")

    w:type(box, "136243")
    eq(ns.db.icons.none, "custom")
    eq(ns.db.custom.none, 136243)
    w:advance(0.2)
    eq(Art(w, "ActionButton1"), 136243, "the button shows the file ID")
    eq(view.swatches.none.check.ring.shown, false, "no stock icon is framed")
    eq(view.swatches.none.custom.ring.shown, true, "the tile for your own is")
    eq(view.swatches.none.custom.art.path, 136243, "and shows the texture")
    eq(box:GetText(), "136243")
    check(editor.note:GetText():find("In use", 1, true), "the box says how to undo it")

    w:type(box, " Interface/Icons/Spell_Nature_Slow ")
    eq(Art(w, "ActionButton1"), "Interface\\Icons\\Spell_Nature_Slow", "a path with either kind of slash")

    w:type(box, "424242")
    check(editor.note:GetText():find("The game has no texture there", 1, true),
        "a texture that does not exist is pointed out")
    w:closeSettings()
    w:openSettings()
    eq(editor:IsShown(), true, "the box stays open while the result uses it")

    w:type(box, "")
    eq(ns.db.icons.none, nil, "emptying the box goes back to the usual icon")
    eq(editor:IsShown(), false)
    eq(view.swatches.none.check.ring.shown, true)
    w:advance(0.2)
    eq(w:icon("ActionButton1"), "check")

    w:click(view.swatches.some.custom)
    eq(view.editors.some:IsShown(), true)
    w:escape(view.inputs.some)
    eq(view.editors.some:IsShown(), false, "Escape puts away a box that is not in use")
    w:click(view.swatches.some.custom)
    w:click(view.swatches.some.ring)
    eq(view.editors.some:IsShown(), false, "and so does picking another icon")
    Clean(w)
end)

test("settings: a client that does not say whether a texture exists is asked another way", function()
    local w = Simple({ quietTextures = true, missingTextures = { [424242] = true } })
    local view = w:openSettings().view
    w:click(view.swatches.none.custom)
    w:type(view.inputs.none, "136243")
    check(view.editors.none.note:GetText():find("In use", 1, true), "one that exists")
    w:type(view.inputs.none, "424242")
    check(view.editors.none.note:GetText():find("The game has no texture there", 1, true), "one that does not")
    Clean(w)
end)

panel("the reset button asks first, and restores position, size and icons only", function(options)
    local w, ns = Simple(options)
    local view = w:openSettings().view
    w:slash("track heroic strike")
    w:slash("when combat")
    w:click(view.previews.none.zones.CENTER)
    w:slide(view.size.slider.widget, 20)
    w:click(view.swatches.some.ring)
    w:click(view.swatches.all.custom)
    w:type(view.inputs.all, "136243")

    w:click(view.reset)
    eq(view.confirm.frame:IsShown(), true, "it asks first")
    eq(view.reset:IsShown(), false)
    eq(ns.db.corner, "CENTER", "and has changed nothing yet")
    w:click(view.confirm.no)
    eq(view.confirm.frame:IsShown(), false)
    eq(view.reset:IsShown(), true)
    eq(ns.db.size, 20, "Cancel leaves everything alone")

    w:click(view.reset)
    w:click(view.confirm.yes)
    eq(ns.db.corner, "TOPLEFT")
    eq(ns.db.size, 0)
    eq(view.size.auto.ticked, true)
    eq(next(ns.db.icons), nil)
    eq(next(ns.db.custom), nil)
    eq(view.editors.all:IsShown(), false)
    eq(view.confirm.frame:IsShown(), false)
    eq(view.reset:IsShown(), true)
    check(ns.db.spells["Heroic Strike"] ~= nil, "spell choices are left alone")
    eq(ns.db.appear, "combat", "and so is when the icons appear")
    eq(ns.db.enabled, true)

    w:click(view.reset)
    w:closeSettings()
    w:openSettings()
    eq(view.confirm.frame:IsShown(), false, "closing the panel puts the question away")
    w:click(view.reset)
    w:click(view.tabs.spells)
    w:click(view.tabs.appearance)
    eq(view.confirm.frame:IsShown(), false, "and so does leaving the tab")
    Clean(w)
end)

test("/se options opens a window of its own, on a tab if one is named", function()
    local w = Simple()
    w:slash("options")
    local window = w.env.StatusEfficiencyOptions
    check(window and window:IsShown(), "the window is showing")
    eq(w.env.UISpecialFrames[1], "StatusEfficiencyOptions", "Escape closes it")
    eq(window.view.tab, "appearance")

    w:slash("options")
    eq(window:IsShown(), false, "the command closes it again")
    w:slash("config")
    eq(window:IsShown(), true, "/se config is the same command")
    w:slash("options spells")
    eq(window:IsShown(), true, "naming a tab never closes it")
    eq(window.view.tab, "spells")
    eq(window.view.pages.spells:IsVisible(), true)
    eq(window.view.pages.appearance:IsVisible(), false)
    eq(window.view.spells.rows[1].name:GetText(), "Battle Shout", "and the tab is filled in")

    w:click(window.close)
    eq(window:IsShown(), false, "the X closes it")
    w:slash("options appearance")
    eq(window:IsShown(), true)
    eq(window.view.tab, "appearance")
    w:click(window.view.tabs.spells)
    eq(window.view.tabs.spells.picked, true)
    eq(window.view.tabs.appearance.picked, false)
    Clean(w)
end)

test("the settings window opens where it was last dragged to", function()
    local w, ns = Simple()
    w:slash("options")
    local window = w.env.StatusEfficiencyOptions
    eq(window.point[1], "CENTER", "in the middle to begin with")
    w:drag(window, "TOPLEFT", "TOPLEFT", 120, -80)
    eq(ns.db.window.point, "TOPLEFT")
    eq(ns.db.window.relative, "TOPLEFT")
    eq(ns.db.window.x, 120)
    eq(ns.db.window.y, -80)
    Clean(w)

    -- The next time the game is started.
    local saved = ns.db
    w = World()
    w:addButton("ActionButton1", 1, REND)
    w:load(saved)
    w:slash("options")
    window = w.env.StatusEfficiencyOptions
    local point, relativeTo, relative, x, y = window:GetPoint(1)
    eq(point, "TOPLEFT", "where it was left")
    eq(relativeTo, w.env.UIParent)
    eq(relative, "TOPLEFT")
    eq(x, 120)
    eq(y, -80)

    w:slash("reset")
    eq(window.point[1], "CENTER", "/se reset puts it back in the middle")
    eq(next(w.ns.db.window), nil)
    Clean(w)

    w = World()
    w:load({ window = { point = "SIDEWAYS", relative = "TOP", x = "far", y = 0 } })
    w:slash("options")
    eq(w.env.StatusEfficiencyOptions.point[1], "CENTER", "a saved place that makes no sense is ignored")
    Clean(w)
end)

--------------------------------------------------------------------------------
-- The settings panel: the Spells tab
--------------------------------------------------------------------------------

panel("the Spells tab lists every spell on the bars and how it is treated", function(options)
    local w = Simple(options)
    local view = w:openSettings().view
    w:click(view.tabs.spells)
    local rows = view.spells.rows
    eq(view.tab, "spells")
    eq(view.tabs.spells.picked, true)
    eq(rows[1].name:GetText(), "Battle Shout", "spells with an icon come first")
    eq(rows[2].name:GetText(), "Rend")
    eq(rows[3].name:GetText(), "Heroic Strike", "then the rest")
    eq(rows[4]:IsShown(), false, "and no more rows than spells")
    eq(view.spells.count:GetText(), "3 spells on your bars, 2 with an icon.")
    eq(view.spells.bar:IsShown(), false, "nothing to scroll")

    eq(rows[1].show.picked, "auto")
    eq(rows[1].on.picked, "self", "Battle Shout is judged on you")
    eq(rows[1].lasts:GetText(), "2 min")
    eq(rows[1].why:GetText(), "tooltip mentions a duration")
    eq(rows[1].icon.path, 130000 + SHOUT, "with the spell's own picture")
    eq(rows[2].on.picked, "target", "Rend on your target")
    eq(rows[2].lasts:GetText(), "21 s")
    eq(rows[3].show.picked, "auto")
    eq(rows[3].on.frame:IsShown(), false, "a spell with no icon has nobody to be judged on")
    eq(rows[3].lasts:IsShown(), false, "and no duration")
    eq(rows[3].why:GetText(), "not a status effect")
    eq(rows[3].icon.desaturated, true, "and is greyed out")

    local title, lines = w:hover(rows[3].whyArea)
    eq(title, "Heroic Strike")
    check(lines[1]:find("Pick Always if it does", 1, true), "the reason is spelled out on hover: " .. tostring(lines[1]))
    title, lines = w:hover(rows[2].on.buttons.all)
    eq(title, "A debuff on every enemy in the fight")
    Clean(w)
end)

panel("Spells tab: Auto, Always and Never", function(options)
    local w, ns = Simple(options)
    local view = w:openSettings().view
    w:click(view.tabs.spells)
    w:advance(0.3)
    local rows = view.spells.rows
    eq(w:icon("ActionButton2"), nil, "Heroic Strike has no icon")

    w:click(rows[3].show.buttons.always)
    eq(ns.db.spells["Heroic Strike"].track, true)
    w:advance(0.5)
    eq(w:icon("ActionButton2"), "check", "now it has")
    eq(rows[3].name:GetText(), "Heroic Strike", "the row stays where it is while the tab is open")
    eq(rows[3].show.picked, "always")
    eq(rows[3].on.picked, "target")
    eq(rows[3].why:GetText(), "you turned it on")
    eq(view.spells.count:GetText(), "3 spells on your bars, 3 with an icon.")

    w:click(rows[2].show.buttons.never)
    eq(ns.db.spells.Rend.track, false)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), nil, "Rend lost its icon")
    eq(rows[2].show.picked, "never")
    eq(rows[2].why:GetText(), "you turned it off")
    eq(rows[2].on.frame:IsShown(), false)

    w:click(rows[2].show.buttons.auto)
    eq(ns.db.spells.Rend, nil, "back to automatic leaves nothing behind")
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "check")

    w:slash("ignore battle shout")
    eq(rows[1].show.picked, "never", "/se ignore shows here straight away")
    w:slash("auto battle shout")
    eq(rows[1].show.picked, "auto")

    -- Opened again, the list is sorted afresh.
    w:click(rows[2].show.buttons.never)
    w:click(view.tabs.appearance)
    w:click(view.tabs.spells)
    eq(rows[1].name:GetText(), "Battle Shout")
    eq(rows[2].name:GetText(), "Heroic Strike", "the spell that gained an icon moved up")
    eq(rows[3].name:GetText(), "Rend", "and the one that lost its icon moved down")
    Clean(w)
end)

panel("Spells tab: who a spell is judged on, and how long its effect lasts", function(options)
    local w, ns = Simple(options)
    local view = w:openSettings().view
    w:click(view.tabs.spells)
    local rend = view.spells.rows[2]
    eq(rend.name:GetText(), "Rend")

    w:click(rend.on.buttons.all)
    eq(ns.db.spells.Rend.aoe, true, "every enemy in the fight")
    eq(rend.on.picked, "all")
    w:click(rend.on.buttons.target)
    eq(ns.db.spells.Rend.aoe, false, "your target only")
    w:click(rend.on.buttons.self)
    eq(ns.db.spells.Rend.kind, "buff", "the same as /se buff")
    eq(ns.db.spells.Rend.track, true)
    eq(rend.on.picked, "self")
    w:click(rend.on.buttons.target)
    eq(ns.db.spells.Rend.kind, "debuff", "and as /se debuff")
    eq(rend.on.picked, "target")

    eq(rend.lasts:GetText(), "21 s")
    rend.lasts:SetFocus()
    eq(rend.lasts:GetText(), "21", "typing starts from the bare number")
    w:type(rend.lasts, "30")
    eq(ns.db.spells.Rend.duration, 30)
    eq(rend.lasts:GetText(), "30 s")
    eq(rend.lasts:HasFocus(), false)
    w:type(rend.lasts, "2 min")
    eq(ns.db.spells.Rend.duration, 120, "minutes are understood")
    eq(rend.lasts:GetText(), "2 min")

    w:type(rend.lasts, "soon")
    check(rend.why:GetText():find("Type seconds", 1, true), "a bad entry is explained in the row")
    eq(ns.db.spells.Rend.duration, 120, "and changes nothing")
    w:type(rend.lasts, "99999")
    check(rend.why:GetText():find("from 1 to 3600", 1, true), "so is one that is out of range")
    w:escape(rend.lasts)
    eq(rend.why:GetText(), "you turned it on", "Escape drops the complaint")
    eq(rend.lasts:GetText(), "2 min", "and the typing")

    w:type(rend.lasts, "")
    eq(ns.db.spells.Rend.duration, nil, "emptying the box lets the addon work it out again")
    eq(rend.lasts:GetText(), "21 s")
    local title, lines = w:hover(rend.lasts)
    eq(title, "How long the effect lasts")
    check(lines[1]:find("tooltip", 1, true), "the box says where the duration comes from: " .. tostring(lines[1]))
    Clean(w)
end)

panel("Spells tab: a long list scrolls", function(options)
    local w = World(options)
    for i = 1, 20 do
        w:addSpell(500 + i, {
            name = string.format("Curse %02d", i), harmful = true,
            description = "Curses the target for 10 sec.", effect = { duration = 10 },
        })
        local name = i <= 12 and ("ActionButton" .. i) or ("MultiBarBottomLeftButton" .. (i - 12))
        w:addButton(name, i, 500 + i)
    end
    w:load()
    local view = w:openSettings().view
    w:click(view.tabs.spells)
    local list, page = view.spells, view.pages.spells
    eq(#list.items, 20)
    local shown = #list.rows
    eq(list.rows[1].name:GetText(), "Curse 01")
    eq(list.rows[shown].name:GetText(), string.format("Curse %02d", shown), "as many at a time as fit the page")
    eq(list.bar:IsShown(), true, "with a scroll bar once they do not all fit")
    eq(list.more:IsShown(), true)
    eq(list.count:GetText(), "20 spells on your bars, 20 with an icon.")

    w:wheel(page, -1)
    eq(list.rows[1].name:GetText(), "Curse 04", "the wheel moves three rows")
    eq(list.bar:GetValue(), 3, "and the bar with it")
    w:wheel(page, -1)
    w:wheel(page, -1)
    w:wheel(page, -1)
    eq(list.rows[shown].name:GetText(), "Curse 20", "it stops at the end")
    eq(list.rows[1].name:GetText(), string.format("Curse %02d", 21 - shown))
    w:wheel(page, 1)
    eq(list.rows[1].name:GetText(), string.format("Curse %02d", 18 - shown))
    w:slide(list.bar, 0)
    eq(list.rows[1].name:GetText(), "Curse 01", "dragging the bar works too")

    list.rows[2].lasts:SetFocus()
    w:wheel(page, -1)
    eq(list.rows[2].lasts:HasFocus(), false, "a row that scrolls away takes its typing with it")
    eq(list.rows[2].name:GetText(), "Curse 05")

    w:click(list.rows[2].show.buttons.never)
    eq(w.ns.db.spells["Curse 05"].track, false, "a click lands on the spell the row shows now")
    Clean(w)
end)

test("settings: the Spells tab keeps up with what the addon learns, without a click", function()
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
    w:applyAura(mobs[1], "Deep Wounds", 600)
    w:slash("options spells")
    local row = w.env.StatusEfficiencyOptions.view.spells.rows[1]
    w:advance(0.5)
    eq(row.name:GetText(), "Ground Stomp")
    eq(row.why:GetText(), "not a status effect")
    eq(row.on.frame:IsShown(), false)

    for _ = 1, 6 do
        w:cast(STOMP)
        w:advance(8)
    end
    eq(ns.db.learned["Ground Stomp"].hits, 6)
    eq(row.why:GetText(), "left an effect after 6 of 6 casts", "what was learned shows up by itself")
    eq(row.on.picked, "all", "judged on every enemy in the fight, as the area spell it turned out to be")
    eq(row.show.picked, "auto")
    eq(w.env.StatusEfficiencyOptions.view.spells.count:GetText(), "1 spell on your bars, 1 with an icon.")
    Clean(w)
end)

test("settings: with no spells on the bars the Spells tab says so", function()
    local w = World()
    w:load()
    local view = w:openSettings().view
    w:click(view.tabs.spells)
    eq(view.spells.empty:IsShown(), true)
    eq(view.spells.rows[1]:IsShown(), false)
    eq(view.spells.count:GetText(), "")
    Clean(w)
end)

panel("with the icons turned off the panel still reads the bars", function(options)
    local w = World(options)
    w:addButton("ActionButton1", 1, REND)
    w:addButton("ActionButton2", 2, HEROIC)
    local ns = w:load({ enabled = false })
    w:advance(3)
    eq(#ns.BarSpells(), 0, "switched off and with the panel shut, the addon reads nothing")

    local view = w:openSettings().view
    eq(view.previews.none.face.path, "Interface\\Icons\\INV_Misc_QuestionMark", "nothing has been read yet")
    w:advance(1)
    eq(view.previews.none.face.path, 130000 + REND, "the pretend buttons get their pictures a moment after it opens")
    w:click(view.tabs.spells)
    eq(view.spells.rows[1].name:GetText(), "Rend", "and the Spells tab has its list")
    eq(view.spells.rows[2].name:GetText(), "Heroic Strike")
    eq(view.spells.empty:IsShown(), false)
    eq(w:icon("ActionButton1"), nil, "still no icons on the bars")

    w:addButton("ActionButton3", 3, SHOUT)
    w:advance(6)
    eq(view.spells.count:GetText(), "3 spells on your bars, 2 with an icon.",
        "a spell put on the bars while the panel is open joins the list")

    w:closeSettings()
    w:addButton("ActionButton4", 4, MORTAL)
    w:advance(8)
    eq(#ns.BarSpells(), 3, "shut again, the addon goes back to reading nothing")
    eq(w:icon("ActionButton1"), nil)
    Clean(w)
end)

--------------------------------------------------------------------------------
-- The settings panel: commands, saved choices and things going wrong
--------------------------------------------------------------------------------

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
    check(w:drain():find("Usage: /se icon", 1, true), "an unknown result gets the usage line")
    w:slash("icon red nonsense")
    check(w:drain():find("is not an icon name", 1, true), "an unknown icon is explained")
    eq(ns.db.icons.all, "skull", "and changes nothing")

    w:slash("icons")
    local listing = w:drain()
    check(listing:find("skull", 1, true) and listing:find("greendot", 1, true), "the names are listed: " .. listing)
    check(listing:find("No need to cast: skull", 1, true), "with what each result uses now: " .. listing)

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
    w:addButton("ActionButton2", 2, MARK)
    local ns = w:load({
        corner = "BOTTOM",
        icons = { none = "skull", some = "no-such-icon", all = "hidden" },
        custom = { all = 136243 },
    })
    local boar = w:addMob("Boar")
    w:target(boar)
    w:advance(0.3)
    eq(Art(w, "ActionButton1"), SKULL, "saved choice")
    eq(w:overlay("ActionButton1").point[1], "BOTTOM", "saved position")
    check(ns.Icons.Texture("some"):find("Partial.tga", 1, true), "unknown name falls back to the default")
    eq(ns.Icons.Texture("all"), nil, "a result saved with no icon has none")
    w:cast(MARK, { quiet = true })
    w:advance(0.3)
    eq(w:icon("ActionButton2"), nil, "so nothing shows once the mark is on")
    Clean(w)

    w = World()
    w:addButton("ActionButton1", 1, REND)
    ns = w:load({ icons = { all = "custom" }, custom = { all = 136243 } })
    eq(ns.Icons.Texture("all"), 136243, "saved texture of your own")
    Clean(w)
end)

test("an icon size saved when sizes went further is kept as large as it can be", function()
    local w = World()
    w:addButton("ActionButton1", 1, REND)
    local ns = w:load({ size = 100 })
    eq(ns.db.size, 48)
    local boar = w:addMob("Boar")
    w:target(boar)
    w:advance(0.3)
    eq(w:overlay("ActionButton1").width, 48)
    Clean(w)
end)

test("a client without the Options window API still gets /se options", function()
    local w = Simple({ noSettings = true })
    eq(#w.settings.addons, 0)
    w:slash("options")
    check(w.env.StatusEfficiencyOptions:IsShown(), "the window opens")
    w:click(w.env.StatusEfficiencyOptions.view.previews.none.zones.RIGHT)
    eq(w.ns.db.corner, "RIGHT")
    Clean(w)
end)

test("if the settings window cannot be built, the commands still work", function()
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
    w:slash("options")
    local said = w:drain()
    check(said:find("could not be built", 1, true), "the failure is explained: " .. said)
    check(said:find("/se when", 1, true), "with the commands that do the same")
    w:slash("corner br")
    eq(ns.db.corner, "BOTTOMRIGHT")
    w:slash("when combat")
    eq(ns.db.appear, "combat")
    w:slash("off")
    eq(ns.db.enabled, false)
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
    w:closeSettings()
    w:openSettings()
    eq(w:drain(), "", "nothing more is said the second time")
    eq(#w.frames, frames, "and nothing more is built")

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
    w:click(view.previews.none.zones.RIGHT)
    eq(#w.errors, 0, "nothing reaches the client's error handler")
    check(w:drain():find("hit a problem", 1, true), "the addon reports it in chat")
    check(tostring(ns.lastError):find("simulated bug", 1, true), "and keeps it for /se debug")
    local kept = ns.db.report.problems
    check(kept and #kept == 1 and kept[1]:find("simulated bug", 1, true), "and in the saved report, for reading afterwards")
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

test("idle costs next to nothing", function()
    -- With no buff spell on the bars your buffs are only read now and then, to
    -- see whether a spell that is on them leaves one.
    local w = World()
    w:addButton("ActionButton1", 1, REND)
    w:load()
    w.sampleCalls = 0
    w:advance(30)
    check(w.sampleCalls >= 10 and w.sampleCalls <= 16, "aura queries in 30s with no enemy around: " .. w.sampleCalls)
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w.sampleCalls = 0
    w:advance(10)
    check(w.sampleCalls <= 60, "aura queries with one target for 10s: " .. w.sampleCalls)
    Clean(w)

    -- Nothing on the bars, nothing asked.
    w = World()
    w:load()
    w.sampleCalls = 0
    w:advance(30)
    eq(w.sampleCalls, 0, "aura queries with empty bars")
    Clean(w)

    -- A spell known to leave a buff has your buffs looked at every pass.
    w = Bar(nil, BLOCK)
    w.sampleCalls = 0
    w:advance(10)
    check(w.sampleCalls >= 40 and w.sampleCalls <= 60, "looks at you in 10s for a buff spell: " .. w.sampleCalls)
    Clean(w)
end)

test("the addon keeps its hands off the global namespace", function()
    -- Every scenario that ends in Clean checks this. This one walks through as
    -- much of the addon as it can first.
    local w = World({ combatAuras = "count", secretFlags = true })
    w:addButton("ActionButton1", 1, REND)
    w:addButton("ActionButton2", 2, FORT)
    w:addButton("ActionButton3", 3, COMMAND)
    w:addButton("ActionButton4", 4, CLAP)
    w:load()
    local guard = w:addMob("Guard", { hostile = false })
    w:target(guard)
    w:cast(FORT)
    w:advance(1)
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:advance(0.3)
    w:cast(REND)
    w:cast(COMMAND)
    w:cast(CLAP)
    w:advance(3)
    w:target(w.player)
    w:advance(0.3)
    w:target(boar)
    for _, command in ipairs({ "debug", "list", "log", "log", "buff commanding", "debuff commanding", "track fort",
        "aoe rend", "single rend", "duration rend 20", "duration rend auto", "ignore thunder", "auto thunder",
        "icons", "icon red skull", "icon yellow none", "corner top", "size 20", "when combat", "when", "plain", "plain",
        "options" }) do
        w:slash(command)
    end
    local window = w.env.StatusEfficiencyOptions
    w:click(window.view.swatches.none.plus)
    w:click(window.view.sets.dots)
    w:click(window.view.swatches.some.custom)
    w:type(window.view.inputs.some, "136243")
    w:slide(window.view.size.slider.widget, 22)
    w:click(window.view.size.auto.frame)
    w:click(window.view.enable.frame)
    w:click(window.view.enable.frame)
    w:click(window.view.appear.buttons.always)
    w:hover(window.view.swatches.all.hidden)
    w:click(window.view.reset)
    w:click(window.view.confirm.yes)
    w:drag(window, "TOP", "TOP", 0, -40)
    w:click(window.view.tabs.spells)
    w:click(window.view.spells.rows[1].show.buttons.always)
    w:type(window.view.spells.rows[1].lasts, "45")
    w:wheel(window.view.pages.spells, -1)
    w:click(window.close)
    local view = w:openSettings().view
    w:click(view.tabs.spells)
    w:advance(1.5)
    w:closeSettings()
    w:advance(1)
    w:die()
    w:kill(boar)
    w:advance(3)
    w:slash("debug")
    w:slash("reset")
    w:advance(1)
    Clean(w)
end)

return tests
