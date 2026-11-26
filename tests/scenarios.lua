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

--- The runner plays every scenario twice: once with a client whose change
--- reports say whether effects were added, renewed or removed (the mock's
--- "lists" payload, which is what build 71139 was seen to send), and once
--- with one whose reports say nothing ("sealed"). True in the first. A
--- scenario that is about one of the two names it in its options instead.
local function KindsTold()
    return (DEFAULT_AURA_PAYLOAD or "lists") == "lists"
end

-- What Compat makes of the details that come with a report, for each of the
-- two, when an effect was added.
local SHAPE_LISTS = "hidden, table: full secret, added secret, updated nil, removed nil"
local SHAPE_SEALED = "hidden, sealed table: full secret, added secret, updated secret, removed secret"

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
    issecretvalue = true, issecrettable = true, canaccesstable = true, C_Secrets = true, C_UnitAuras = true,
    Settings = true,
    InterfaceOptions_AddCategory = true, GetSpellTexture = true, SOUNDKIT = true, PlaySound = true,
    IsUsableAction = true, IsActionInRange = true, C_Texture = true,
    -- Fonts, which the settings panel looks for before it borrows one.
    GameFontNormal = true, GameFontNormalLarge = true, GameFontNormalSmall = true, GameFontHighlight = true,
    GameFontHighlightSmall = true, GameFontHighlightHuge = true, GameFontDisable = true,
    GameFontDisableSmall = true,
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

test("ids, no reports: a miss never turns the icon red", function()
    -- A client that never says when a unit's effects change, but lets your
    -- effects be counted: nothing is assumed, and the count says what landed.
    local w, ns, boar = Simple({ combatAuras = "ids", auraEvents = false })
    w:cast(REND)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "the count went up")
    w:advance(2.7)
    w:removeAura(boar, "Rend")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "clean again")

    w:cast(REND, { miss = true })
    w:advance(0.1)
    eq(w:icon("ActionButton1"), "check", "nothing is assumed")
    w:advance(2.3)
    eq(w:icon("ActionButton1"), "check", "and nothing showed up")
    eq(ns.db.learned.Rend.casts, 2, "casts counted")
    eq(ns.db.learned.Rend.hits, 1, "hits counted")
    Clean(w)
end)

test("ids: a first cast that nothing is seen of leaves the icon green, and is not held against the spell", function()
    -- Until a debuff of yours has been seen this fight, "nothing there" is not
    -- proof of a miss: the client could simply be hiding it. And until the
    -- enemy has been heard from, its silence is no proof either. So nothing
    -- is shown, and nothing is learned.
    local w, ns = Simple({ combatAuras = "ids" })
    w:cast(REND, { miss = true })
    w:advance(3)
    eq(w:icon("ActionButton1"), "check", "nothing is assumed")
    eq(ns.db.learned.Rend, nil, "and not counted as evidence")
    w:cast(REND)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "one that lands shows")
    Clean(w)
end)

test("an empty answer in combat is never mistaken for a clean enemy", function()
    -- A client that answers the count with an empty list instead of refusing,
    -- with and without reports of a unit's effects changing. Without them the
    -- addon waits three casts for a report before it goes back to assuming.
    for _, events in ipairs({ true, false }) do
        local w, ns = Simple({ combatAuras = "empty", auraEvents = events })
        for i = 1, 6 do
            w:cast(REND)
            w:advance(1)
            if events or i > 3 then
                eq(w:icon("ActionButton1"), "cross", "after cast " .. i)
            else
                eq(w:icon("ActionButton1"), "check", "nothing heard and nothing assumed, cast " .. i)
            end
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
    eq(w:icon("ActionButton1"), "check", "in flight: nothing is on the boar yet, and nothing is assumed")
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

test("a debuff shown by name in combat, no reports: a cast is judged by name", function()
    local w = Simple({ combatAuras = "none", byName = { Rend = true }, auraEvents = false })
    w:cast(REND)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "read by name")
    w:advance(21.7)
    eq(w:icon("ActionButton1"), "check", "the first one ran out")
    w:cast(REND, { miss = true })
    w:advance(0.1)
    eq(w:icon("ActionButton1"), "check", "nothing is assumed")
    w:advance(2.4)
    eq(w:icon("ActionButton1"), "check", "and no Rend turned up")
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

test("reports: nothing is assumed, from the very first cast", function()
    -- Nothing is known about this client yet. A cast still counts for nothing
    -- until the enemy reports a change.
    local w, ns = Simple()
    local wolf = w:addMob("Wolf")
    w:showPlate(wolf)
    w:advance(0.3)
    w:drain()
    eq(ns.Trusted("target"), true, "reports are what a cast is judged by from the start")

    w:cast(REND, { miss = true })
    w:advance(0.15)
    eq(w:icon("ActionButton1"), "check", "the very first cast missed, and the icon stays green")

    w:cast(HEROIC) -- nothing changes on the boar
    w:advance(0.5)
    w:removeAura(w.player, "nothing") -- and nothing on you
    w:advance(3)
    eq(w:icon("ActionButton1"), "check", "still green")
    eq(ns.db.learned.Rend, nil, "silence from an enemy that has never been heard from is not held against the spell")
    eq(ns.db.proof and ns.db.proof.target, nil, "and nothing has been proven yet")

    w:cast(REND)
    w:advance(0.15)
    eq(w:icon("ActionButton1"), "cross", "one that lands shows at once")
    eq(ns.signals.target.heard > 0, true, "the boar's effects were reported changing in combat")
    eq(ns.signals.plate.heard > 0, true, "through its nameplate too")
    eq(ns.db.proof.target, BUILD, "which is remembered for the next session")
    w:advance(22)

    w:cast(REND, { miss = true })
    w:advance(4)
    eq(w:icon("ActionButton1"), "check", "a later miss")
    eq(ns.db.learned.Rend.casts, 2, "and now that the boar has been heard from, its silence counts against the cast")
    eq(ns.db.learned.Rend.hits, 1)
    eq(w:drain(), "", "none of which needed a word in chat")
    Clean(w)
end)

test("reports: what is heard about you says nothing about what is reported for a target", function()
    local w, ns = Simple()
    w:cast(REND, { miss = true })
    w:advance(0.15)
    w:applyBuff("Blessing", 60, false) -- someone buffs you in the fight
    w:advance(3)
    eq(ns.signals.player.heard > 0, true, "you have been heard from")
    eq(ns.signals.target.heard, 0, "the boar has not")
    eq(w:icon("ActionButton1"), "check", "nothing was reported for the boar, so nothing is shown")
    eq(ns.db.learned.Rend, nil, "and its silence is not held against the spell yet")
    Clean(w)
end)

test("reports, area: the very first cast is judged by who reported", function()
    local w, ns, mobs = Pack()
    for i = 1, 3 do
        mobs[i].engaged = true
    end
    w:enterCombat()
    w:advance(0.5)
    w:cast(CLAP, { hits = { mobs[1], mobs[2] } })
    w:advance(0.05)
    eq(w:icon("ActionButton1"), "partial", "two of them reported a change, and nobody is assumed hit")
    w:advance(2.5)
    eq(w:icon("ActionButton1"), "partial", "the third one's silence is believed")
    eq(ns.signals.plate.heard > 0, true)
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
    eq(ns.signals.plate.heard, 0, "nameplates have never been heard from")
    Clean(w)
end)

test("reports: a client that stops reporting is found out, and casts are assumed to land again", function()
    -- An earlier session heard this build report, so it is given six casts
    -- before the addon stops waiting. Each of them stays green meanwhile.
    local w, ns = Simple({ auraEvents = "calm", saved = Proven() })
    for i = 1, 6 do
        w:cast(REND)
        w:advance(0.5)
        eq(w:icon("ActionButton1"), "check", "cast " .. i .. " landed, but no report came")
        eq(ns.Trusted("target"), true, "still waited for before cast " .. (i + 1))
        w:advance(3)
    end
    eq(ns.db.proof.target, nil, "six casts in a row with no report at all: the proof is dropped")
    eq(ns.db.doubt.target, BUILD, "and this build is on record as not reporting")
    eq(ns.Trusted("target"), false)
    local said = w:drain()
    check(said:find("the game has said nothing about your target changing after several casts in a row", 1, true),
        "it says so in chat: " .. said)
    w:cast(REND)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross", "and casts are assumed to land again")
    check(ns.db.report.notes[1]:find("taken to land there until a change is reported", 1, true),
        "the report says so: " .. ns.db.report.notes[1])
    w:advance(25)
    for _ = 1, 4 do
        w:cast(REND, { miss = true })
        w:advance(25)
    end
    eq(w:drain(), "", "it is said once")
    Clean(w)
end)

test("reports: a client nothing is known about is given three casts to report", function()
    local w, ns = Simple({ auraEvents = false })
    for i = 1, 3 do
        w:cast(REND)
        w:advance(0.5)
        eq(w:icon("ActionButton1"), "check", "cast " .. i .. ": nothing heard, nothing assumed")
        w:advance(3)
    end
    eq(ns.db.doubt.target, BUILD)
    w:cast(REND, { miss = true })
    w:advance(3)
    eq(w:icon("ActionButton1"), "cross", "assumed, with nothing to say otherwise")
    w:advance(18.5)
    eq(w:icon("ActionButton1"), "check", "until the timer ends")
    eq(ns.db.learned.Rend, nil, "nothing is learned from any of it")
    Clean(w)

    -- The next session does not wait again: this build is known not to report.
    local saved = w.env.StatusEfficiencyDB
    local w2 = World({ auraEvents = false })
    w2:addButton("ActionButton1", 1, REND)
    local ns2 = w2:load(saved)
    local boar = w2:addMob("Boar")
    w2:target(boar)
    w2:advance(0.3)
    eq(ns2.Trusted("target"), false)
    w2:drain()
    w2:cast(REND)
    w2:advance(4)
    eq(w2:icon("ActionButton1"), "cross", "assumed from the first cast")
    eq(w2:drain(), "", "and not said again")
    w2:slash("debug")
    local debug = w2:drain()
    check(debug:find("your target: 0 (silent after several casts, so a cast there is taken to land)", 1, true),
        "debug says which reports are not counted on: " .. debug)
    check(not debug:find("about you: 0 (", 1, true), "and only those: " .. debug)
    Clean(w2)
end)

test("reports: a client that was written off is relied on again the moment it reports", function()
    local saved = { doubt = { player = BUILD, target = BUILD, softenemy = BUILD, plate = BUILD } }
    local w, ns = Simple({ saved = saved })
    eq(ns.Trusted("target"), false, "an earlier session heard nothing from this build")
    w:cast(REND)
    w:advance(0.15)
    eq(w:icon("ActionButton1"), "cross")
    eq(ns.Trusted("target"), true, "it reported the change")
    eq(ns.db.doubt.target, nil, "so the doubt is gone")
    eq(ns.db.proof.target, BUILD)
    w:advance(22)
    w:cast(REND, { miss = true })
    w:advance(0.15)
    eq(w:icon("ActionButton1"), "check", "and a miss is a miss again")
    Clean(w)
end)

test("reports: what an earlier build did says nothing about this one", function()
    -- Neither its proof nor its silence carries over: nothing is assumed, and
    -- the new build is given its own casts to report.
    for _, field in ipairs({ "proof", "doubt" }) do
        local old = { player = BUILD, target = BUILD, softenemy = BUILD, plate = BUILD }
        local w, ns = Simple({ clientBuild = "70999", saved = { [field] = old } })
        eq(ns.Trusted("target"), true, "judged by reports, after an old build's " .. field)
        w:cast(REND, { miss = true })
        w:advance(0.15)
        eq(w:icon("ActionButton1"), "check", "a miss is a miss")
        w:advance(4)
        w:cast(REND)
        w:advance(0.15)
        eq(w:icon("ActionButton1"), "cross", "and a hit is a hit")
        eq(ns.db.proof.target, "1.60.1.70999")
        Clean(w)
    end
end)

--------------------------------------------------------------------------------
-- A change on a unit just as one of your own effects there was due to run out
--------------------------------------------------------------------------------

--- What the addon saves once it has cast Rend a few times and heard its ending
--- reported on time each time, on top of what Proven() gives.
local function Timed(spell)
    local saved = Proven()
    saved.learned = { [spell or "Rend"] = { casts = 4, hits = 4, due = 4, late = 0 } }
    return saved
end

test("reports: a change that comes just as one of your own effects was due to run out is not taken for a hit", function()
    -- Nothing is saved about how Rend's endings are reported: this holds from
    -- the first fight on.
    local w, ns = Bar({ saved = Proven() }, REND, MORTAL)
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:advance(0.3)
    w:cast(REND)
    w:advance(20.5)
    w:cast(MORTAL, { miss = true }) -- still waiting to be judged when the Rend runs out
    w:advance(1)
    eq(w:icon("ActionButton1"), "check", "the Rend is over")
    eq(w:icon("ActionButton2"), "check", "and the change on the boar was that, not the Mortal Strike landing")
    w:advance(3)
    eq(w:icon("ActionButton2"), "check")
    eq(ns.db.learned["Mortal Strike"].casts, 1)
    eq(ns.db.learned["Mortal Strike"].hits, 0, "the miss is counted as one")
    eq(ns.db.report.reports.ended, 2, "put down to the ending, once for each name the boar goes by")
    local heard = 0
    if KindsTold() then
        heard = 1
        eq(ns.db.learned.Rend.due, 1, "the game said an effect went, so the ending was heard on time")
    else
        eq(ns.db.learned.Rend.due, nil, "with a cast waiting it proves nothing about endings, so it is not counted")
    end

    -- An ending with nothing else going on is counted, to keep an eye on
    -- whether this client reports them when they are due.
    w:cast(REND)
    w:advance(22)
    eq(ns.db.learned.Rend.due, heard + 1, "reported when it was due")
    eq(ns.db.learned.Rend.late, 0)
    Clean(w)
end)

test("reports: a spell whose endings mostly go unreported is no longer judged by them", function()
    -- What is saved about how often Rend was reported ending when it was due,
    -- and whether a change at that moment is still put down to it. Where it is
    -- not, the limit that is left shows: the report goes to the cast waiting.
    -- This is how it goes where a report does not say what kind of change it
    -- was. Where it does, none of this is needed: see "kinds:" further down.
    local cases = {
        { late = 1, relied = true }, -- one that went unreported is not held against it
        { late = 2, relied = false },
        { due = 2, late = 3, relied = false },
        { due = 3, late = 2, relied = false },
        { due = 4, late = 2, relied = true }, -- two in three were on time
    }
    for _, case in ipairs(cases) do
        local saved = Proven()
        saved.learned = { Rend = { casts = 5, hits = 5, due = case.due, late = case.late } }
        local w = Bar({ saved = saved, auraPayload = "sealed" }, REND, MORTAL)
        local boar = w:addMob("Boar")
        w:showPlate(boar)
        w:target(boar)
        w:advance(0.3)
        w:cast(REND)
        w:advance(20.5)
        w:cast(MORTAL, { miss = true })
        w:advance(1)
        eq(w:icon("ActionButton2"), case.relied and "check" or "cross",
            (case.due or 0) .. " endings heard on time, " .. case.late .. " not")
        Clean(w)
    end
end)

test("reports: an ending reported a moment early is still known for what it is", function()
    local w, ns, boar = Simple({ saved = Timed() })
    w:addButton("ActionButton2", 2, MORTAL)
    w:advance(2.5)
    w:cast(REND)
    w:advance(20.5)
    w:cast(MORTAL, { miss = true })
    w:advance(0.45)
    w:removeAura(boar, "Rend") -- a twentieth of a second before the books expect it
    w:advance(1)
    eq(w:icon("ActionButton2"), "check", "not the Mortal Strike landing")
    eq(w:icon("ActionButton1"), "check")
    Clean(w)
end)

test("reports: one ending answers for one change, even in the same frame", function()
    -- A Hunter's Mark in flight lands in the very frame the Rend runs out.
    local w, ns = Bar({ saved = Timed() }, REND, MARK)
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:advance(0.3)
    w:cast(REND)
    w:advance(20)
    w:cast(MARK, { miss = true }) -- on its way: the scenario lands it by hand
    w:advance(0.95)
    w:removeAura(boar, "Rend")
    w:applyAura(boar, "Hunter's Mark", 120)
    w:advance(0.3)
    eq(w:icon("ActionButton2"), "cross", "the second change in that frame is the Mark")
    eq(w:icon("ActionButton1"), "check", "and the first was the Rend ending")
    w:advance(4)
    eq(ns.db.learned["Hunter's Mark"].hits, 1)
    Clean(w)
end)

test("reports: a renewed effect running out is known for what it is, and proves nothing either way", function()
    local w, ns = Bar({ saved = Timed() }, REND, MORTAL)
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:advance(0.3)
    w:cast(REND)
    w:advance(10)
    w:cast(REND) -- renewed: 21 seconds from here
    w:advance(20.5)
    eq(w:icon("ActionButton1"), "cross", "still on, 31 seconds after the first cast")
    w:cast(MORTAL, { miss = true }) -- still waiting to be judged when the Rend runs out
    w:advance(1)
    eq(w:icon("ActionButton1"), "check", "the Rend is over")
    eq(w:icon("ActionButton2"), "check", "and the change on the boar was that, not the Mortal Strike landing")
    w:advance(3)

    -- Once more with nothing else going on.
    w:cast(REND)
    w:advance(10)
    w:cast(REND)
    w:advance(22)
    eq(w:icon("ActionButton1"), "check")
    eq(ns.db.learned.Rend.due, 4, "reported when it was due, and still not counted as proof of anything")

    -- The game may give a renewed effect extra time. Then its ending comes
    -- later than its length says, which is not held against the spell.
    w:cast(REND)
    w:advance(10)
    w:cast(REND, { miss = true })
    w:applyAura(boar, "Rend", 26) -- renewed, and given five seconds on top
    w:advance(30)
    eq(w:icon("ActionButton1"), "check")
    eq(ns.db.learned.Rend.due, 4, "neither ending was counted as one heard on time")
    eq(ns.db.learned.Rend.late, 0, "nor as one that went unreported")
    Clean(w)
end)

test("reports: a recast right after the old effect ran out still lands", function()
    local w, ns = Simple({ saved = Timed() })
    w:cast(REND)
    w:advance(21.05)
    eq(w:icon("ActionButton1"), "check", "it has just run out")
    w:cast(REND) -- within the moment in which the ending is expected to be reported
    w:advance(0.15)
    eq(w:icon("ActionButton1"), "cross", "each ending answers for one change, and this one is the new Rend")
    w:advance(20)
    eq(w:icon("ActionButton1"), "cross", "20 seconds into the new one")
    eq(ns.db.learned.Rend.hits, 6)
    Clean(w)
end)

test("reports: renewing an effect a moment before it was due to end is not mistaken for its ending", function()
    -- The renewal is reported within the moment the ending was expected in:
    -- once with the cast announced before the change, and once after it in
    -- the same frame.
    for _, early in ipairs({ false, 0 }) do
        local w, ns = Simple({ saved = Proven() })
        w:cast(REND)
        w:advance(20.95)
        w:cast(REND, { early = early or nil })
        w:advance(0.5)
        eq(w:icon("ActionButton1"), "cross", "still there")
        w:advance(19)
        eq(w:icon("ActionButton1"), "cross", "for another 21 seconds from the renewal")
        w:advance(3)
        eq(w:icon("ActionButton1"), "check", "and then it ran out")
        eq(ns.db.learned.Rend.hits, 2, "both casts landed")
        eq(ns.db.learned.Rend.due, nil, "and neither end was counted as one heard on time")
        eq(ns.db.learned.Rend.late, nil, "or as one that went unreported")
        Clean(w)
    end
end)

test("reports: a renewal reported a frame before its cast, in the old effect's last moment, passes for its ending", function()
    -- The price of never taking an ending for a hit, where a report does not
    -- say what kind of change it was. Where the game reports a landing, it
    -- does so in the frame of the cast, so a change a frame earlier that fits
    -- the old effect running out is put down to that.
    local w, ns = Simple({ saved = Proven(), auraPayload = "sealed" })
    w:cast(REND)
    w:advance(20.95)
    w:cast(REND, { early = 0.05 })
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "check", "taken for the old Rend ending, though it was renewed")
    eq(ns.db.learned.Rend.due, nil, "with a cast on its way it proves nothing about endings, so it is not counted")
    w:advance(1)
    w:cast(REND)
    w:advance(0.15)
    eq(w:icon("ActionButton1"), "cross", "the next cast puts it right")
    Clean(w)
end)

test("reports: a recast that misses while the old effect's ending is on its way is not taken for a renewal", function()
    -- Sent a moment before the old Rend runs out, announced a moment after,
    -- and dodged. The ending is reported in between, a little early.
    local w, ns, boar = Simple({ saved = Proven() })
    w:cast(REND)
    w:advance(20.9)
    w.effects[#w.effects + 1] = { at = w.clock + 0.05, run = function()
        w:removeAura(boar, "Rend")
    end }
    w:cast(REND, { castTime = 0.1, miss = true })
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "check", "the old Rend ran out, and nothing took its place")
    w:advance(3)
    eq(w:icon("ActionButton1"), "check")
    eq(ns.db.learned.Rend.hits, 1, "the miss is counted as one")
    Clean(w)
end)

test("reports: a recast that misses just before the old effect runs out is not taken for a hit", function()
    local w, ns = Simple({ saved = Timed() })
    w:cast(REND)
    w:advance(20.5)
    w:cast(REND, { miss = true })
    w:advance(1)
    eq(w:icon("ActionButton1"), "check", "the old Rend ran out, and the change the boar reported then was that")
    w:advance(3)
    eq(w:icon("ActionButton1"), "check")
    eq(ns.db.learned.Rend.casts, 6)
    eq(ns.db.learned.Rend.hits, 5, "the miss is counted as one")
    Clean(w)
end)

test("reports: a cast that lands in the very frame another effect of yours ends is still seen", function()
    -- The game may send one report for both changes. A change in the frame a
    -- cast is announced goes to the cast, whichever of the two comes first.
    for _, early in ipairs({ false, 0 }) do
        local w, ns = Bar({ saved = Timed() }, REND, MORTAL)
        local boar = w:addMob("Boar")
        w:showPlate(boar)
        w:target(boar)
        w:advance(0.3)
        w:cast(REND)
        w:advance(20.95)
        -- The Rend goes without a report of its own: it is part of the next one.
        for i = #boar.auras, 1, -1 do
            if boar.auras[i].name == "Rend" then
                table.remove(boar.auras, i)
            end
        end
        boar.owed = "removed"
        w:cast(MORTAL, { early = early or nil })
        w:advance(0.3)
        eq(w:icon("ActionButton2"), "cross", "the Mortal Strike landed, and shows")
        eq(w:icon("ActionButton1"), "check", "and the Rend is over")
        w:advance(4)
        eq(ns.db.learned["Mortal Strike"].hits, 1)
        if KindsTold() then
            eq(ns.db.learned.Rend.due, 5, "the report said an effect went as well, so the Rend's ending was heard")
        else
            eq(ns.db.learned.Rend.due, 4, "whether the Rend's ending was reported is left open: not counted as heard")
        end
        eq(ns.db.learned.Rend.late, 0, "and not as missed")
        Clean(w)
    end
end)

--------------------------------------------------------------------------------
-- A client whose reports say what kind of change they are
--
-- Build 71139 hides what is in a report, but not whether effects were added,
-- renewed or removed. A report that only took effects away cannot be a cast
-- landing, whatever the timing. Each scenario here names the way the client
-- reports, and several play both to show what telling the kinds apart changes.
--------------------------------------------------------------------------------

test("kinds: an effect going from the enemy while a cast waits is not the cast landing", function()
    -- Somebody else's curse runs out on the boar a moment after a Mortal
    -- Strike was dodged. Where the game says that an effect went, that cannot
    -- pass for the strike landing. Where it does not say, it still does.
    for payload, icon in pairs({ lists = "check", sealed = "cross" }) do
        local w, ns = Bar({ saved = Proven(), auraPayload = payload }, MORTAL, MARK)
        local boar = w:addMob("Boar")
        w:showPlate(boar)
        w:target(boar)
        w:advance(0.3)
        w:applyAura(boar, "Thorns", 600, false, nil, true) -- before the fight: not among the reports counted below
        w:advance(0.3)
        w:cast(MARK) -- the boar is heard from
        w:advance(1)
        w:applyAura(boar, "Curse of Agony", 5, false)
        w:advance(4.8)
        w:cast(MORTAL, { miss = true })
        w:advance(0.5) -- the curse ran out 0.2 seconds after the cast
        eq(w:icon("ActionButton1"), icon, payload .. ": the Mortal Strike was dodged")
        w:advance(4)
        eq(w:icon("ActionButton1"), icon, payload)
        eq(ns.db.learned["Mortal Strike"].casts, 1)
        eq(ns.db.learned["Mortal Strike"].hits, payload == "lists" and 0 or 1, payload .. ": what is learned of the spell")
        w:removeAura(boar, "Hunter's Mark") -- taken off early, with no cast waiting
        w:advance(0.1)
        local counts = ns.db.report.reports
        eq(counts.ended, 0, payload .. ": none of your own effects was due")
        eq(counts.gone, payload == "lists" and 4 or 0, payload .. ": once for each name the boar goes by")
        eq(counts.spared, payload == "lists" and 1 or 0, payload .. ": one change that a cast was waiting on")
        eq(counts.kinds.went, payload == "lists" and 4 or 0)
        eq(counts.kinds.came, payload == "lists" and 4 or 0, payload .. ": the Mark and the curse arriving")
        eq(counts.kinds.unsaid, payload == "lists" and 0 or 8)
        w:slash("debug")
        local debug = w:drain()
        check(debug:find(payload == "lists" and "an effect arriving 4, one going 4, both 0, not said 0."
            or "an effect arriving 0, one going 0, both 0, not said 8.", 1, true), payload .. ": " .. debug)
        check(debug:find("and not taken for it landing: " .. (payload == "lists" and 1 or 0) .. ".", 1, true),
            payload .. ": " .. debug)
        Clean(w)
    end
end)

test("kinds: an effect going is never a hit, whatever is known about how the spell's endings are reported", function()
    -- The cases in which timing alone gives the report to the cast waiting
    -- (see "a spell whose endings mostly go unreported"). None of them matter
    -- where the game says that an effect went.
    for _, late in ipairs({ 1, 2, 5 }) do
        local saved = Proven()
        saved.learned = { Rend = { casts = 5, hits = 5, late = late } }
        local w, ns = Bar({ saved = saved, auraPayload = "lists" }, REND, MORTAL)
        local boar = w:addMob("Boar")
        w:showPlate(boar)
        w:target(boar)
        w:advance(0.3)
        w:cast(REND)
        w:advance(20.5)
        w:cast(MORTAL, { miss = true })
        w:advance(1)
        eq(w:icon("ActionButton2"), "check", late .. " endings went unreported before: the Mortal Strike was dodged")
        eq(w:icon("ActionButton1"), "check", "and the Rend is over")
        eq(ns.db.learned.Rend.due, 1, "its ending was heard when it was due, with the cast waiting or not")
        eq(ns.db.report.reports.ended, 2, "once for each name the boar goes by")
        eq(ns.db.report.reports.spared, 0, "put down to the Rend, which is another count")
        Clean(w)
    end
end)

test("kinds: one report of effects going answers for every effect of yours that was due", function()
    -- A Rend and the wound from a Mortal Strike run out in the same frame, and
    -- the game sends one report for the two. Timing alone lets one ending
    -- answer for one change, and counts the other as never reported.
    for payload, late in pairs({ lists = 0, sealed = 1 }) do
        local w, ns = Bar({ saved = Proven(), auraPayload = payload }, REND, MORTAL)
        local boar = w:addMob("Boar")
        w:showPlate(boar)
        w:target(boar)
        w:advance(0.3)
        w:cast(REND) -- 21 seconds
        w:advance(11)
        w:cast(MORTAL) -- 10 seconds
        w:advance(9.5)
        eq(w:icon("ActionButton1"), "cross", payload .. ": half a second before both run out")
        eq(w:icon("ActionButton2"), "cross", payload)
        w:advance(2)
        eq(w:icon("ActionButton1"), "check", payload .. ": both over")
        eq(w:icon("ActionButton2"), "check", payload)
        local rend, mortal = ns.db.learned.Rend, ns.db.learned["Mortal Strike"]
        eq((rend.due or 0) + (mortal.due or 0), 2 - late, payload .. ": endings heard on time")
        eq((rend.late or 0) + (mortal.late or 0), late, payload .. ": endings taken to have gone unreported")
        Clean(w)
    end
end)

test("kinds: a recast that misses in the very frame the old effect ends stays green", function()
    -- The old Rend goes in the frame the new one is dodged. Timing alone gives
    -- a change in the frame of a cast to the cast, which is wrong here and
    -- right far more often. Where the game says an effect went, it is right
    -- both times: once with the cast announced first, once with the report.
    for payload, icon in pairs({ lists = "check", sealed = "cross" }) do
        for _, first in ipairs({ "cast", "report" }) do
            local w, ns, boar = Simple({ saved = Timed(), auraPayload = payload })
            w:cast(REND)
            w:advance(20.95)
            if first == "report" then
                w:removeAura(boar, "Rend")
            end
            w:cast(REND, { miss = true })
            if first == "cast" then
                w:removeAura(boar, "Rend")
            end
            w:advance(0.3)
            eq(w:icon("ActionButton1"), icon, payload .. ", the " .. first .. " first: nothing took the old Rend's place")
            w:advance(4)
            eq(ns.db.learned.Rend.hits, payload == "lists" and 5 or 6, payload .. ", the " .. first .. " first")
            if payload == "lists" then
                eq(ns.db.learned.Rend.due, 5, "the " .. first .. " first: and the old Rend's ending was heard on time")
            end
            Clean(w)
        end
    end
end)

test("kinds: a renewal reported a frame before its cast, in the old effect's last moment, is known for one", function()
    -- Timing alone takes this for the old effect ending (see the scenario of
    -- nearly the same name). The game may report a renewal as the same effect
    -- renewed, or as one going and another arriving.
    for _, replaces in ipairs({ false, true }) do
        local how = replaces and "replaced" or "renewed"
        local w, ns = Simple({ saved = Proven(), auraPayload = "lists", refreshReplaces = replaces })
        w:cast(REND)
        w:advance(20.95)
        w:cast(REND, { early = 0.05 })
        w:advance(0.5)
        eq(w:icon("ActionButton1"), "cross", how .. ": the report said an effect arrived")
        w:advance(19)
        eq(w:icon("ActionButton1"), "cross", how .. ": for another 21 seconds from the renewal")
        w:advance(3)
        eq(w:icon("ActionButton1"), "check", how .. ": and then it ran out")
        eq(ns.db.learned.Rend.hits, 2, how .. ": both casts landed")
        eq(ns.db.learned.Rend.late or 0, 0, how .. ": and no ending went unreported")
        local kinds = ns.db.report.reports.kinds
        eq(kinds.both, replaces and 2 or 0, how .. ": once for each name the boar goes by")
        Clean(w)
    end
end)

test("kinds: an effect arriving on the enemy at the instant of a miss still passes for the cast landing", function()
    -- The limit that is left: the game says an effect arrived, never whose.
    local w, ns, boar = Simple({ saved = Proven(), auraPayload = "lists" })
    w:cast(REND, { miss = true })
    w:advance(0.1)
    w:applyAura(boar, "Curse of Agony", 24, false)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "nothing says the effect that arrived was somebody else's")
    eq(ns.db.report.reports.spared, 0)
    Clean(w)
end)

test("kinds: a report that says nothing, or everything, is judged by its timing as before", function()
    -- A Rend is dodged, and a moment later the boar reports a change.
    local cases = {
        { what = "removed", icon = "check", said = "went" },
        { what = "updated", icon = "cross", said = "came" },
        { what = { "updated", "removed" }, icon = "cross", said = "both" },
        { what = { "added", "removed" }, icon = "cross", said = "both" },
        { what = { "added", "updated" }, icon = "cross", said = "came" },
        { what = {}, icon = "cross", said = "unsaid" }, -- no list at all
        { what = "full", icon = "cross", said = "unsaid" }, -- everything may have changed
        { what = { "added", "updated", "removed" }, icon = "cross", said = "unsaid" }, -- every list: says nothing
    }
    for i, case in ipairs(cases) do
        local w, ns, boar = Simple({ saved = Proven(), auraPayload = "lists" })
        w:cast(REND, { miss = true })
        w:advance(0.1)
        w:auraChanged(boar, case.what)
        w:advance(0.3)
        eq(w:icon("ActionButton1"), case.icon, "case " .. i .. ", taken as " .. case.said)
        local kinds = ns.db.report.reports.kinds
        for _, said in ipairs({ "came", "went", "both", "unsaid" }) do
            eq(kinds[said], said == case.said and 2 or 0, "case " .. i .. ": reports counted as " .. said)
        end
        Clean(w)
    end

    -- One that says nothing, at the moment an effect of yours was due to run
    -- out, is put down to that by its timing.
    local w, ns = Bar({ saved = Timed(), auraPayload = "lists" }, REND, MORTAL)
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:advance(0.3)
    w:cast(REND)
    w:advance(20.5)
    w:cast(MORTAL, { miss = true })
    w:advance(0.45)
    for i = #boar.auras, 1, -1 do
        table.remove(boar.auras, i) -- the Rend goes, and the report does not say what kind of change that is
    end
    w:auraChanged(boar, "full")
    w:advance(0.5)
    eq(w:icon("ActionButton2"), "check", "not the Mortal Strike landing")
    eq(w:icon("ActionButton1"), "check")
    eq(ns.db.report.reports.ended, 2)
    eq(ns.db.report.reports.kinds.unsaid, 2)
    Clean(w)
end)

test("kinds: details are read for what they show, whatever their make", function()
    -- A Rend is dodged, and a moment later the boar reports a change with
    -- details made by hand: readable lists, empty ones, values that are not
    -- lists at all. Only a report that plainly took effects away and added
    -- none is kept from the cast.
    local cases = {
        { said = "went", make = function() -- readable, with empty lists where nothing happened
            return { isFullUpdate = false, addedAuras = {}, updatedAuraInstanceIDs = {}, removedAuraInstanceIDs = { 7 } }
        end },
        { said = "came", make = function()
            return { isFullUpdate = false, addedAuras = { { auraInstanceID = 9 } }, removedAuraInstanceIDs = {} }
        end },
        { said = "went", make = function(w) -- as build 71139 sends it
            return { isFullUpdate = w.Secret(false), removedAuraInstanceIDs = w.Secret({ 7 }) }
        end },
        { said = "unsaid", make = function() -- says everything may have changed
            return { isFullUpdate = true, removedAuraInstanceIDs = { 7 } }
        end },
        { said = "unsaid", make = function() -- a number where a list belongs
            return { isFullUpdate = false, removedAuraInstanceIDs = 7 }
        end },
        { said = "unsaid", make = function(w) -- a list that may not be looked into
            return { isFullUpdate = false, removedAuraInstanceIDs = w.Locked() }
        end },
        { said = "unsaid", make = function(w) -- every field hidden
            return w.Sealed({ isFullUpdate = false, removedAuraInstanceIDs = { 7 } })
        end },
        { said = "unsaid", make = function(w) -- a table that may not be touched
            return w.Locked()
        end },
        { said = "unsaid", make = function() -- not a table
            return 5
        end },
    }
    for i, case in ipairs(cases) do
        local w, ns, boar = Simple({ saved = Proven() })
        w:cast(REND, { miss = true })
        w:advance(0.1)
        w:auraChanged(boar, { details = case.make(w) })
        w:advance(0.3)
        eq(w:icon("ActionButton1"), case.said == "went" and "check" or "cross", "case " .. i .. ", taken as " .. case.said)
        local kinds = ns.db.report.reports.kinds
        for _, said in ipairs({ "came", "went", "both", "unsaid" }) do
            eq(kinds[said], said == case.said and 2 or 0, "case " .. i .. ": reports counted as " .. said)
        end
        Clean(w)
    end
end)

test("reports: an enemy dying to a skill without an icon does not make it look like a status skill", function()
    -- A finishing blow, and the dead enemy's effects go a moment later. Where
    -- the game says an effect went, that is never the skill leaving
    -- something. Where it does not say, the change is put down to the cast as
    -- any other would be, but an enemy that died in that moment teaches
    -- nothing about the skill: six kills in a row do not earn it an icon.
    for _, payload in ipairs({ "lists", "sealed" }) do
        local w = World({ auraPayload = payload })
        w:addSpell(903, {
            name = "Finishing Blow", harmful = true,
            description = "Attempts to finish off a wounded foe, causing 600 damage.",
        })
        w:addButton("ActionButton1", 1, 903)
        w:addButton("ActionButton2", 2, MARK)
        local ns = w:load(Proven())
        for i = 1, 6 do
            local boar = w:addMob("Boar " .. i)
            w:showPlate(boar)
            w:target(boar)
            w:advance(0.3)
            w:cast(MARK)
            w:advance(2)
            w:cast(903)
            w:advance(0.1)
            w:kill(boar)
            w:advance(4)
            w:hidePlate(boar)
        end
        local learned = ns.db.learned["Finishing Blow"]
        eq(learned and learned.hits or 0, 0, payload .. ": casts counted as having left something")
        local boar = w:addMob("Boar 7")
        w:showPlate(boar)
        w:target(boar)
        w:advance(0.3)
        eq(w:icon("ActionButton1"), nil, payload .. ": it has no icon")
        eq(ns.db.report.learning["Finishing Blow"].changed, payload == "sealed" and 6 or 0,
            payload .. ": what the report says the enemies did after it")
        eq(ns.db.report.reports.spared, 0, payload .. ": a skill that is only listened to is not a cast waiting to be judged")

        -- An enemy that lives through it and reports nothing is counted, as before.
        w:cast(903)
        w:advance(4)
        eq(ns.db.learned["Finishing Blow"].casts, 1, payload .. ": one cast that left nothing")
        eq(ns.db.learned["Finishing Blow"].hits, 0, payload)
        Clean(w)
    end
end)

test("reports: what an enemy's death taught an earlier version does not earn a skill an icon", function()
    -- Saved by 0.3.5: a finishing move that twelve kills in fifteen casts had
    -- made look like a status skill, a real one that earned its icon by what
    -- the enemy reported, and one that has its icon from its tooltip.
    local function Saved(version)
        local saved = Proven()
        saved.version = version
        saved.learned = {
            ["Finishing Blow"] = { casts = 15, hits = 12 },
            ["Gouge Armor"] = { casts = 8, hits = 8 },
            Rend = { casts = 13, hits = 13 },
        }
        return saved
    end
    local function Play(version)
        local w = World()
        w:addSpell(903, {
            name = "Finishing Blow", harmful = true,
            description = "Attempts to finish off a wounded foe, causing 600 damage.",
        })
        w:addSpell(902, {
            name = "Gouge Armor", harmful = true,
            description = "Tears at the target's armor until it gives way.",
            effect = { duration = 12 },
        })
        w:addButton("ActionButton1", 1, 903)
        w:addButton("ActionButton2", 2, 902)
        w:addButton("ActionButton3", 3, REND)
        local ns = w:load(Saved(version))
        local boar = w:addMob("Boar")
        w:showPlate(boar)
        w:target(boar)
        w:advance(0.3)
        return w, ns
    end

    local w, ns = Play(1)
    eq(ns.db.version, 2, "the saved settings are brought up to date")
    eq(w:icon("ActionButton1"), nil, "the finishing move is without its icon")
    eq(ns.db.learned["Finishing Blow"].casts, 15)
    eq(ns.db.learned["Finishing Blow"].hits, 11, "its count is taken down to short of earning one")
    eq(w:icon("ActionButton3"), "check", "Rend has its icon from its tooltip, whatever was counted")
    eq(w:icon("ActionButton2"), nil, "the skill that earned its icon has to be seen leaving something again")
    w:cast(902)
    w:advance(13)
    eq(w:icon("ActionButton2"), nil, "once is not enough: 7 of 9")
    w:cast(902)
    w:advance(0.8)
    eq(w:icon("ActionButton2"), "cross", "twice is: 8 of 10")
    for _ = 1, 3 do
        w:advance(4)
        w:cast(903)
    end
    w:advance(4)
    eq(w:icon("ActionButton1"), nil, "and the finishing move leaves nothing, so it stays without")
    Clean(w)

    -- Loaded a second time, nothing is taken down again.
    local again = World()
    again:addButton("ActionButton1", 1, REND)
    local kept = { version = 2, learned = { Rend = { casts = 13, hits = 13 }, ["Finishing Blow"] = { casts = 15, hits = 12 } } }
    local ns2 = again:load(kept)
    eq(ns2.db.learned.Rend.hits, 13, "counts of this version are left alone")
    eq(ns2.db.learned["Finishing Blow"].hits, 12)
    Clean(again)

    -- A spell whose effect has been read by its own name is never in doubt.
    local seen = World()
    seen:addButton("ActionButton1", 1, REND)
    local ns3 = seen:load({ version = 1, learned = { Rend = { casts = 13, hits = 13, exact = true, duration = 21 } } })
    eq(ns3.db.learned.Rend.hits, 13, "nothing to take down for a spell that has been seen")
    Clean(seen)
end)

test("kinds, buffs: a buff of yours running out is not another buff landing", function()
    -- Shield Block is used and leaves nothing, in the moment a buff somebody
    -- else gave you runs out. Nothing is known about when that was due, so
    -- only the kind of change tells that no buff arrived.
    for payload, icon in pairs({ lists = "check", sealed = "cross" }) do
        local w, ns = Bar({ saved = Proven(), auraPayload = payload }, BLOCK, REND)
        Fight(w)
        w:applyBuff("Mark of the Wild", 5, false)
        w:advance(4.8)
        w:cast(BLOCK, { miss = true })
        w:advance(0.5)
        eq(w:icon("ActionButton1"), icon, payload .. ": the Shield Block left nothing")
        Clean(w)
    end
end)

test("reports: silence after a spell without an icon says nothing about the client", function()
    local w, ns = Simple()
    for _ = 1, 5 do
        w:cast(HEROIC)
        w:advance(4)
    end
    eq(ns.Trusted("target"), true, "Heroic Strike was never expected to change anything on the boar")
    w:cast(REND, { miss = true })
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "so nothing is assumed about a Rend yet")
    Clean(w)
end)

test("reports, buffs: a buff you told the addon to track is taken to land from its first cast", function()
    -- A buff cannot miss, and this client says nothing about your own effects
    -- in a fight: waiting for a report would only keep the icon green.
    local w, ns = Bar({ auraTokens = { target = true, plate = true } }, COMMAND, HAWK, REND)
    w:slash("buff commanding shout")
    Fight(w)
    w:cast(COMMAND)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "taken to land, as you asked")
    w:advance(3.5)
    eq(w:icon("ActionButton1"), "cross", "and silence does not take that away")
    eq(ns.Trusted("player"), true, "nor is it held against the client")

    w:cast(HAWK) -- it has no icon: nothing has shown that it leaves a buff
    w:advance(4)
    eq(ns.db.report.learning["Aspect of the Hawk"], nil,
        "and a buff is not learned from reports: your own effects change too often for that")
    Clean(w)
end)

test("reports: a change at the moment a buff of yours was due to run out is not taken for a cast landing", function()
    local saved = Timed("Shield Block")
    saved.learned["Shield Block"].buff = true
    saved.learned["Shield Block"].duration = 10
    local w, ns = Bar({ saved = saved }, BLOCK, WARD, REND)
    Fight(w)
    w:cast(BLOCK)
    w:advance(9.5)
    eq(w:icon("ActionButton1"), "cross")
    w:cast(WARD, { miss = true }) -- leaves nothing on you
    w:advance(1)
    eq(w:icon("ActionButton1"), "check", "the Shield Block ran out")
    eq(w:icon("ActionButton2"), "check", "and that is the change you reported, not a Stone Ward")
    Clean(w)
end)

test("reports: an effect that does not end when its length says is soon no longer counted on to", function()
    -- The tooltip says 30 seconds and the effect lasts 20.
    local w = World()
    w:addSpell(901, {
        name = "Shatter Armor", harmful = true,
        description = "Shatters the target's armor for 30 sec.",
        effect = { duration = 20 },
    })
    w:addButton("ActionButton1", 1, 901)
    w:addButton("ActionButton2", 2, MORTAL)
    local ns = w:load(Proven())
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:advance(0.3)
    for _ = 1, 2 do
        w:cast(901)
        w:advance(32)
    end
    local learned = ns.db.learned["Shatter Armor"]
    eq(learned.due, 0, "no change was reported when the books said it should end")
    eq(learned.late, 2)
    w:cast(901)
    w:advance(29.5)
    w:cast(MORTAL, { miss = true })
    w:advance(0.45)
    w:applyAura(boar, "Sunder Armor", 30, false) -- someone else's, just when the books say the armor effect ends
    w:advance(0.3)
    eq(w:icon("ActionButton2"), "cross", "which is no longer put down to that ending: the limit that is left")
    Clean(w)
end)

test("reports: an ending is only held against a unit that was there to report it", function()
    local w, ns, boar = Simple({ saved = Proven() })
    w:cast(REND)
    w:advance(5)
    w:kill(boar)
    w:advance(20)
    eq(ns.db.learned.Rend.due, nil, "the boar died with the Rend on it")
    eq(ns.db.learned.Rend.late, nil, "and its silence when the Rend was due says nothing about the client")
    Clean(w)
end)

--------------------------------------------------------------------------------
-- Spells without an icon are listened for all the same
--------------------------------------------------------------------------------

test("reports: a spell that lost its icon earns it back by landing", function()
    local w, ns = Bar({ saved = Proven() }, MORTAL)
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:advance(0.3)
    w:cast(MORTAL)
    w:advance(11)
    w:drain()
    for _ = 1, 5 do
        w:cast(MORTAL, { miss = true })
        w:advance(3.5)
    end
    eq(w:icon("ActionButton1"), nil, "one cast in six left something: not a status spell, as far as anyone can tell")
    local said = w:drain()
    check(said:find("Mortal Strike left no status effect behind after 5 of 6 casts", 1, true), said)
    check(said:find("gets the icon back by itself", 1, true), "and it says that this is not for good: " .. said)

    for landed = 1, 2 do
        w:cast(MORTAL)
        w:advance(11)
        eq(w:icon("ActionButton1"), nil, "not back yet after " .. landed .. " more that landed")
    end
    eq(ns.db.learned["Mortal Strike"].hits, 3)
    eq(ns.db.learned["Mortal Strike"].casts, 8)
    eq(w:drain(), "", "nothing is said meanwhile")

    w:cast(MORTAL)
    w:advance(0.8)
    eq(w:icon("ActionButton1"), "cross", "4 of 9: the icon is back, and knows about the cast that earned it")
    said = w:drain()
    check(said:find("Mortal Strike does leave a status effect behind: 4 of its last 9 casts did. Its icon is back.", 1, true),
        said)
    eq(ns.db.learned["Mortal Strike"].told, nil, "so the next time it is dropped will be told as well")
    w:advance(9.5)
    eq(w:icon("ActionButton1"), "check", "and it runs out like any other")
    for _ = 1, 2 do
        w:cast(MORTAL, { miss = true })
        w:advance(3.5)
    end
    eq(w:icon("ActionButton1"), "check", "4 of 11: back to being a status spell, it is not dropped again over two misses")
    eq(w:drain(), "")
    Clean(w)
end)

test("reports: a status spell whose first three casts all miss has its icon back after two that land", function()
    local w, ns = Bar({ saved = Proven() }, MORTAL, MARK)
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:advance(0.3)
    w:cast(MARK) -- a real debuff, which lasts the whole scenario: the client is heard reporting it
    w:advance(1)
    w:drain()
    for _ = 1, 3 do
        w:cast(MORTAL, { miss = true })
        w:advance(3.5)
    end
    eq(w:icon("ActionButton1"), nil, "three misses to begin with look just like a skill that leaves nothing")
    check(w:drain():find("Mortal Strike left no status effect behind after 3 of 3 casts", 1, true), "said in chat")

    w:cast(MORTAL)
    w:advance(11)
    eq(w:icon("ActionButton1"), nil, "1 of 4: one that lands is not enough")
    eq(w:drain(), "")
    w:cast(MORTAL)
    w:advance(0.8)
    eq(ns.db.learned["Mortal Strike"].hits, 2)
    eq(ns.db.learned["Mortal Strike"].casts, 5)
    eq(w:icon("ActionButton1"), "cross", "2 of 5: the icon is back, and knows about the cast that earned it")
    check(w:drain():find("Mortal Strike does leave a status effect behind: 2 of its last 5 casts did. Its icon is back.",
        1, true), "said in chat as well")
    w:advance(9.5)
    eq(w:icon("ActionButton1"), "check", "and it runs out like any other")
    w:cast(MORTAL, { miss = true })
    w:advance(3.5)
    eq(w:icon("ActionButton1"), "check", "2 of 6: a miss now does not take it away again")
    eq(w:drain(), "")
    Clean(w)
end)

test("reports: a spell near the line does not keep losing and regaining its icon", function()
    local w, ns = Bar({ saved = Proven() }, BLOODTHIRST, MARK)
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:advance(0.3)
    w:cast(MARK)
    w:advance(1)
    for _ = 1, 6 do
        w:cast(BLOODTHIRST)
        w:advance(3.5)
    end
    eq(w:icon("ActionButton1"), nil, "dropped: six silent casts")
    w:drain()
    -- Now and then something else changes on the boar just as it is used.
    for _ = 1, 2 do
        w:cast(BLOODTHIRST)
        w:advance(0.1)
        w:auraChanged(boar)
        w:advance(3.5)
        w:cast(BLOODTHIRST)
        w:advance(3.5)
    end
    eq(ns.db.learned.Bloodthirst.hits, 2)
    eq(ns.db.learned.Bloodthirst.casts, 10)
    eq(w:icon("ActionButton1"), nil, "2 of 10 is more than it was dropped at, and still not enough to come back")
    eq(w:drain(), "", "so there is nothing new to say")
    local books = ns.Tracker:Describe(ns.Now())
    eq(#books, 1, "nothing is entered in the books for a spell without an icon")
    eq(books[1].name, "Hunter's Mark")
    Clean(w)
end)

test("reports: a spell nobody took for a status spell earns an icon by what the enemy reports", function()
    local w = World()
    w:addSpell(902, {
        -- Castable on enemies, but its tooltip mentions no duration.
        name = "Gouge Armor", harmful = true,
        description = "Tears at the target's armor until it gives way.",
        effect = { duration = 12 },
    })
    w:addButton("ActionButton1", 1, 902)
    w:addButton("ActionButton2", 2, HEROIC)
    local ns = w:load(Proven())
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:advance(0.3)
    for cast = 1, 5 do
        eq(w:icon("ActionButton1"), nil, "no icon before cast " .. cast)
        w:cast(902)
        w:advance(1)
        w:cast(HEROIC)
        w:advance(12)
    end
    w:cast(902)
    w:advance(0.8)
    eq(w:icon("ActionButton1"), "cross", "six casts were each followed by a change on the boar: it has an icon now")
    eq(w:icon("ActionButton2"), nil, "Heroic Strike changed nothing on the boar, and has none")
    eq(ns.db.learned["Heroic Strike"].hits, 0)
    eq(ns.db.learned["Heroic Strike"].casts, 5)
    local learning = ns.db.report.learning
    eq(learning["Gouge Armor"].casts, 6, "the report counts the casts of a spell without an icon")
    eq(learning["Gouge Armor"].changed, 6)
    eq(learning["Heroic Strike"].changed, 0)
    w:advance(12)
    eq(w:icon("ActionButton1"), "check", "and its effect runs out on the 12 seconds nothing better is known than")
    Clean(w)
end)

test("reports: a change reported a frame before its cast goes to that cast, not to a spell that only listens", function()
    local w, ns = Simple({ saved = Proven() })
    w:cast(HEROIC) -- no icon, listened for
    w:advance(0.1)
    w:cast(REND, { early = 0.05 }) -- the boar's change is reported before the Rend is announced
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "the change is the Rend's")
    w:advance(4)
    eq(ns.db.learned.Rend.hits, 1)
    eq(ns.db.learned["Heroic Strike"].hits, 0, "and the Heroic Strike gave it back")
    eq(ns.db.learned["Heroic Strike"].casts, 1)
    Clean(w)
end)

test("reports: whatever comes with a report, it is only described and a cast is judged all the same", function()
    local shapes = {
        lists = SHAPE_LISTS,
        sealed = SHAPE_SEALED,
        secret = "hidden, secret",
        none = "hidden, nothing",
        forbidden = "hidden, a table addons may not touch",
        open = "hidden, table: full boolean, added list [id number, mine boolean, harmful boolean, spell secret], "
            .. "updated list [number], removed nil",
        full = "hidden, table: full boolean, added nil, updated nil, removed nil",
    }
    for payload, text in pairs(shapes) do
        local w, ns = Simple({ auraPayload = payload })
        w:cast(REND)
        w:advance(0.3)
        eq(w:icon("ActionButton1"), "cross", payload .. ": the report is what the cast is judged by")
        w:advance(22)
        w:cast(REND, { miss = true })
        w:advance(4)
        eq(w:icon("ActionButton1"), "check", payload .. ": and a miss stays green")
        local seen = {}
        for shape, count in pairs(ns.db.report.payload) do
            seen[#seen + 1] = shape .. " x" .. count
        end
        check(ns.db.report.payload[text], payload .. ": the saved report says what came: " .. table.concat(seen, "; "))
        eq(ns.db.report.reports.target.readable, payload == "secret" and 0 or ns.db.report.reports.target.hidden,
            payload .. ": and whether it was one secret value")
        Clean(w)
    end
end)

test("reports: only the first reports of a session are described", function()
    local w, ns, boar = Simple({ saved = Proven() })
    w:enterCombat()
    for _ = 1, 80 do
        w:auraChanged(boar)
        w:advance(0.05)
    end
    local payload = ns.db.report.payload
    eq(payload[KindsTold() and SHAPE_LISTS or SHAPE_SEALED], 60)
    eq(payload["hidden, unread"], 100, "the rest are counted and left alone")
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
    -- are waited for at first. After three casts with nothing ever heard
    -- through a nameplate they are assumed hit, as on any unit nobody reports on.
    local w, ns, mobs = Pack({ auraTokens = { player = true, target = true } })
    for i = 1, 3 do
        mobs[i].engaged = true
    end
    w:enterCombat()
    w:cast(REND)
    w:advance(0.5)
    eq(ns.signals.target.heard > 0, true)
    eq(ns.signals.plate.heard, 0)
    for i = 1, 3 do
        eq(ns.Trusted("plate"), true, "still waited for before cast " .. i)
        w:cast(CLAP, { hits = { mobs[2], mobs[3] } })
        w:advance(0.3)
        eq(w:icon("ActionButton1"), "check", "nobody reported anything, and nobody is assumed hit: cast " .. i)
        w:advance(3)
    end
    eq(ns.Trusted("plate"), false, "three casts with nothing heard through a nameplate")
    eq(ns.Trusted("target"), true, "the target is still judged by what it reports")
    eq(ns.db.learned["Thunder Clap"], nil,
        "and the target's silence is not held against the spell: it may have reached the others unreported")
    check(w:drain():find("the game has said nothing about the enemies around your target changing", 1, true),
        "it says so in chat")
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

test("reports: a spell you told the addon to track is taken to land once reports have shown nothing of it", function()
    local w, ns = Simple({ saved = Proven() })
    w:slash("track heroic strike")
    w:cast(REND) -- the boar is heard from
    w:advance(0.5)
    for i = 1, 2 do
        w:cast(HEROIC)
        w:advance(0.3)
        eq(w:icon("ActionButton2"), "check", "judged by what the boar reports, which is nothing: cast " .. i)
        w:advance(3.5)
    end
    eq(ns.db.learned["Heroic Strike"].casts, 2)
    eq(ns.db.learned["Heroic Strike"].hits, 0)
    w:cast(HEROIC)
    w:advance(0.3)
    eq(w:icon("ActionButton2"), "cross", "reports cannot see what it leaves, and you asked for it to be tracked")
    w:advance(3.5)
    eq(w:icon("ActionButton2"), "cross", "and silence does not take that away")
    check(ns.db.report.casts[#ns.db.report.casts]:find("taken to land on your say-so", 1, true),
        "the report says how it was judged: " .. ns.db.report.casts[#ns.db.report.casts])
    Clean(w)
end)

test("reports: a debuff you told the addon to track is judged by reports from its first cast", function()
    local w, ns = Simple({ saved = Proven() })
    w:slash("track rend")
    w:cast(REND, { miss = true })
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "a miss is a miss, although you asked for the spell to be tracked")
    w:advance(3.5)
    eq(w:icon("ActionButton1"), "check")

    for _ = 1, 3 do
        w:cast(REND)
        w:advance(0.3)
        eq(w:icon("ActionButton1"), "cross", "and a hit is a hit")
        w:advance(22)
    end
    eq(ns.db.learned.Rend.hits, 3, "three casts were each followed by a change on the boar")

    w:cast(REND, { miss = true })
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "a later miss")
    w:advance(3.5)
    eq(w:icon("ActionButton1"), "check")
    check(ns.db.report.casts[1]:find("waited for a report", 1, true), "the report says how the first one was judged: "
        .. ns.db.report.casts[1])
    Clean(w)
end)

test("reports: a debuff you told the addon to track gets through a bad start", function()
    -- Two misses in a row, and reports look as if they cannot see the spell:
    -- it is taken to land for a while. The casts are listened for all the
    -- same, and two that are seen to land put it back to being judged.
    local w, ns = Simple({ saved = Proven() })
    w:slash("track rend")
    w:cast(HEROIC)
    w:advance(0.5)
    w:auraChanged(w.mobs[1]) -- the boar is heard from
    w:advance(3)
    for _ = 1, 2 do
        w:cast(REND, { miss = true })
        w:advance(4)
        eq(w:icon("ActionButton1"), "check")
    end
    w:cast(REND, { miss = true })
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "taken to land now, as you asked")
    w:advance(22)
    for _ = 1, 2 do
        w:cast(REND)
        w:advance(22)
    end
    eq(ns.db.learned.Rend.hits, 2)
    eq(ns.db.learned.Rend.casts, 5)
    w:cast(REND)
    w:advance(22)
    w:cast(REND, { miss = true })
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "three of six landed where the boar could be heard: a miss is a miss again")
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
    w:cast(REND)
    w:advance(22)
    for _ = 1, 2 do
        w:cast(HEROIC) -- reports show nothing of it, so from here on it is taken to land
        w:advance(4)
    end
    w:cast(REND, { travel = 0.2 })
    w:advance(0.1)
    w:cast(HEROIC) -- goes off before the boar has shown the Rend
    w:advance(0.4)
    eq(w:icon("ActionButton1"), "cross", "the change on the boar is the Rend's")
    w:advance(3)
    eq(w:icon("ActionButton1"), "cross")
    eq(ns.db.learned.Rend.hits, 2)
    eq(ns.db.learned["Heroic Strike"].hits, 0, "and is not put down to the spell that is taken to land anyway")
    Clean(w)
end)

test("reports: a spell with no icon does not take the credit from a cast waiting for it either", function()
    -- Heroic Strike has no icon, but is listened for in case it leaves
    -- something after all. That must not cost the Rend its landing.
    local w, ns = Simple({ saved = Proven() })
    w:cast(REND, { travel = 0.2 })
    w:advance(0.1)
    w:cast(HEROIC)
    w:advance(0.4)
    eq(w:icon("ActionButton1"), "cross", "the change on the boar is the Rend's")
    w:advance(3)
    eq(ns.db.learned.Rend.hits, 1)
    eq(ns.db.learned["Heroic Strike"].hits, 0)
    eq(ns.db.learned["Heroic Strike"].casts, 1, "nothing was left over for it")
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

test("reports, area: on a client known to report nothing, enemies pulled in by the spell are assumed hit", function()
    local quiet = { doubt = { player = BUILD, target = BUILD, softenemy = BUILD, plate = BUILD } }
    local w, ns, mobs = Pack({ auraEvents = false, saved = quiet })
    w:cast(CLAP, { hits = mobs }) -- none of them was in the fight when it was sent
    w:advance(0.05)
    eq(w:icon("ActionButton1"), "check", "nothing to go on yet")
    w:advance(2.5)
    eq(w:icon("ActionButton1"), "cross", "all three are in the fight now and nothing says otherwise")
    eq(ns.Trusted("plate"), false)
    Clean(w)
end)

test("reports, area: a client nothing is known about is given three casts, then everyone in the fight is assumed hit", function()
    local w, ns, mobs = Pack({ auraEvents = false })
    for i = 1, 3 do
        w:cast(CLAP, { hits = mobs })
        w:advance(3.5)
        eq(w:icon("ActionButton1"), "check", "nothing heard, nobody assumed hit: cast " .. i)
    end
    local said = w:drain()
    check(said:find("about the enemies around your target or your target changing", 1, true), "one line for both: " .. said)
    w:cast(CLAP, { hits = mobs })
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "all three are in the fight and nothing says otherwise")
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
    for cast = 1, 3 do
        eq(w:icon("ActionButton1"), "check", "still there before cast " .. cast)
        w:cast(BLOODTHIRST)
        w:advance(0.3)
        eq(w:icon("ActionButton1"), "check", "never red: nothing changed on the boar")
        w:advance(3.5)
    end
    eq(ns.db.learned.Bloodthirst.casts, 3)
    eq(ns.db.learned.Bloodthirst.hits, 0)
    eq(w:icon("ActionButton1"), nil, "dropped: its first three casts all left nothing")
    local said = w:drain()
    check(said:find("Bloodthirst left no status effect behind after 3 of 3 casts", 1, true),
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
    eq(report.reports.target.readable, report.reports.target.hidden, "each with a table, not one secret value")
    eq(report.payload[KindsTold() and SHAPE_LISTS or SHAPE_SEALED], 2,
        "what came with them is described, field by field")
    local kinds = report.reports.kinds
    eq(kinds.came, KindsTold() and 2 or 0, "and counted by the kind of change it said it was")
    eq(kinds.unsaid, KindsTold() and 0 or 2, "or as one that did not say")
    eq(kinds.went + kinds.both, 0)
    eq(#report.casts, 2, "one line for each cast")
    check(report.casts[1]:find("Rend (debuff, hidden, waited for a report): changed, 0.00s after the cast", 1, true),
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
    check(debug:find("your target: 1, your soft target: 0, nameplates: 1", 1, true),
        "debug counts the reports: " .. debug)
    check(debug:find("put down to an effect of yours running out just then: 0.", 1, true),
        "and those that were only an effect ending: " .. debug)
    check(debug:find(KindsTold() and "an effect arriving 2, one going 0, both 0, not said 0."
        or "an effect arriving 0, one going 0, both 0, not said 2.", 1, true),
        "and what kind of change the game said each was: " .. debug)
    check(debug:find("and not taken for it landing: 0.", 1, true), "and the endings a cast was not credited with: " .. debug)
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

test("area: an opening cast is judged by who shows it", function()
    local w, _, mobs = Pack({ combatAuras = "ids" })
    for i = 1, 3 do
        mobs[i].engaged = true
    end
    w:enterCombat()
    w:advance(0.5)
    w:cast(CLAP, { hits = { mobs[1], mobs[2] } })
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "partial", "two of them changed, and nobody is assumed hit")
    w:advance(2.5)
    eq(w:icon("ActionButton1"), "partial", "the third kobold never showed it")
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
    for _ = 1, 2 do
        w:cast(BLOODTHIRST)
        w:advance(3.5)
    end
    eq(w:icon("ActionButton1"), "check", "two empty casts are not enough")
    w:cast(BLOODTHIRST)
    w:advance(3.5)
    eq(ns.db.learned.Bloodthirst.casts, 3)
    eq(w:icon("ActionButton1"), nil, "dropped after three that left nothing")
    Clean(w)
end)

--------------------------------------------------------------------------------
-- Times in a tooltip that are not how long an effect lasts
--------------------------------------------------------------------------------

local VICTORY = 402927
local VICTORY_TEXT = "Instantly attack the target causing 180 damage and healing you for 10% of your maximum "
    .. "health. Can only be used within 20 sec after you kill an enemy that yields experience or honor."

test("a skill whose tooltip only says how soon it has to be used gets no icon", function()
    local w = World()
    w:addSpell(VICTORY, { name = "Victory Rush", harmful = true, description = VICTORY_TEXT })
    w:addButton("ActionButton1", 1, VICTORY)
    w:addButton("ActionButton2", 2, REND)
    local ns = w:load(Proven())
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "20 sec is how long it can be used for, not how long anything lasts")
    eq(w:icon("ActionButton2"), "check", "the skill next to it, which does leave an effect, has its icon")
    w:drain()
    local info = ns.Spells:Get(VICTORY, ns.Now())
    eq(info.tooltipDuration, nil)
    eq(info.tooltipPassed, "can only be used within 20 sec", "what was passed over, and why, is kept")

    -- It is listened for like any skill without an icon, and nothing is said.
    w:cast(REND)
    w:advance(1)
    for _ = 1, 4 do
        w:cast(VICTORY)
        w:advance(2)
        eq(w:icon("ActionButton1"), nil)
    end
    eq(ns.db.learned["Victory Rush"].casts, 4)
    eq(ns.db.learned["Victory Rush"].hits, 0)
    eq(w:drain(), "", "it never had an icon to lose")
    local noted = ns.db.report.spells
    eq(noted["Victory Rush"].why, "none", "the saved report says it was not taken for a status skill")
    eq(noted["Victory Rush"].passed, "can only be used within 20 sec", "and which words made the difference")
    eq(noted["Victory Rush"].lasts, nil)
    eq(noted.Rend.lasts, "causing 147 damage over 21 sec", "as it says where a length was read from")
    eq(noted.Rend.passed, nil)
    Clean(w)
end)

test("a skill whose casts were already seen to leave nothing has no icon after an update", function()
    -- Saved by a version that still gave it an icon: four casts, and nothing
    -- followed any of them. Its tooltip here would still fool the reader.
    local saved = Proven()
    saved.learned = { ["Victory Rush"] = { casts = 4, hits = 0 } }
    local w = World()
    w:addSpell(VICTORY, {
        name = "Victory Rush", harmful = true,
        description = "Instantly attack the target. Your victory is yours to claim for 20 sec.",
    })
    w:addButton("ActionButton1", 1, VICTORY)
    local ns = w:load(saved)
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:advance(0.3)
    eq(ns.Spells:Get(VICTORY, ns.Now()).tooltipDuration, 20, "this wording reads like an effect")
    eq(w:icon("ActionButton1"), nil, "but four casts that left nothing say otherwise, from the first moment")
    check(w:drain():find("Victory Rush left no status effect behind after 4 of 4 casts", 1, true),
        "and that is said once, since the icon was there before")
    Clean(w)
end)

test("tooltip times are read by the words around them", function()
    local w, ns = Bar(nil, REND)
    local Parse = ns.Spells.ParseDuration
    local lengths = {
        -- What is on a warrior's bars.
        { "Wounds the target causing them to bleed for 147 damage over 21 sec.", 21 },
        { "Charge an enemy, generate 9 rage, and stun it for 1 sec. Cannot be used in combat.", 1 },
        { "Maims the enemy, causing 18 damage and slowing the enemy's movement by 40% for 15 sec.", 15 },
        { "Sunders the target's armor, reducing it by 180 per Sunder Armor and causes a high amount of threat. "
            .. "Can be applied up to 5 times. Lasts 30 sec.", 30 },
        { "The warrior shouts, increasing the melee attack power of all party members within 20 yards by 55. "
            .. "Lasts 2 min.", 120 },
        { "Blasts nearby enemies increasing the time between their attacks by 10% for 30 sec and doing 23 damage "
            .. "to them. Will affect up to 4 targets.", 30 },
        { "Generates 10 rage at the cost of health, and then generates an additional 10 rage over 10 sec. The "
            .. "warrior is considered in combat for the duration.", 10 },
        { "Instantly counterattack any enemy that strikes you in melee for 15 sec. Melee attacks made from "
            .. "behind cannot be counterattacked. A maximum of 30 attacks will cause retaliation.", 15 },
        { "A mocking attack that causes 23 damage, a moderate amount of threat and forces the target to focus "
            .. "attacks on you for 6 sec.", 6 },
        { "The warrior shouts, causing up to 5 enemies within 10 yards to cower in fear. The targeted enemy "
            .. "will be unable to move while cowering. Lasts 8 sec.", 8 },
        -- Other ways of saying how long.
        { "Causes 12 damage every 3 sec for 15 sec.", 15 },
        { "Strikes fear into the target, causing it to flee for up to 20 sec.", 20 },
        { "Increases your attack speed for the next 15 sec.", 15 },
        { "Slows the target by 50%. Lasts 12s.", 12 },
        { "Marks the target. The mark has a duration of 5 min.", 300 },
        { "Poisons the enemy for 1.5 sec.", 1.5 },
        -- A time that might be something else, and is as likely an effect of that length.
        { "Plants a charge on the target that goes off after 4 sec.", 4 },
        { "Blasts the target. If it dies within 5 sec, you gain a Soul Shard.", 5 },
        { "Charges an enemy, immobilizing it and interrupting any spell being cast for 4 sec.", 4 },
        -- A length next to a time that is something else: the length is what counts.
        { "Causes the target to bleed for 60 damage over 12 sec. Can only be used within 6 sec after a dodge.", 12 },
        { "Deals 40 damage and slows the target for 8 sec. 1 min cooldown.", 8 },
        { "Burns the enemy for 30 damage every 2 sec. Lasts 10 sec, or 20 sec after a critical strike.", 20 },
    }
    for i = 1, #lengths do
        eq(Parse(lengths[i][1]), lengths[i][2], lengths[i][1])
    end

    local others = {
        { VICTORY_TEXT, "can only be used within 20 sec" },
        { "Overpowers the enemy, causing weapon damage. Usable for 5 sec after the target dodges.",
            "weapon damage. usable for 5 sec" },
        { "Strikes the target. Can be used for up to 6 sec after you parry.", "can be used for up to 6 sec" },
        { "Pummel the target for 20 damage. It also interrupts spellcasting and prevents any spell in that school "
            .. "from being cast for 4 sec.", "school from being cast for 4 sec" },
        { "Deals 30 damage. This attack can be used once every 6 sec.", "can be used once every 6 sec" },
        { "Reduces the remaining cooldown of your shouts by 30 sec.", "cooldown of your shouts by 30 sec" },
        { "Reduces the remaining cooldown of your shouts by up to 30 sec.", "of your shouts by up to 30 sec" },
        { "Strikes for 50 damage. Has a 30 sec cooldown.", "strikes for 50 damage. has a 30 sec cooldown" },
        { "Deals 100 damage. 2 sec cast.", "deals 100 damage. 2 sec cast" },
        { "Strikes for 50 damage. This skill has a cooldown of 1 min.", "skill has a cooldown of 1 min" },
        { "Heals you for 20% of all damage taken in the last 5 sec.", "damage taken in the last 5 sec" },
        { "Your next spell with a casting time of less than 10 sec becomes instant.",
            "a casting time of less than 10 sec" },
        { "Strikes hard. Only usable within the next 4 sec after a parry.", "only usable within the next 4 sec" },
        { "Strikes hard. Usable only within 8 sec of a kill.", "hard. usable only within 8 sec" },
        { "Restores 5 mana per 5 sec.", "restores 5 mana per 5 sec" },
    }
    for i = 1, #others do
        local length, read, passed = Parse(others[i][1])
        eq(length, nil, others[i][1])
        eq(read, nil, others[i][1])
        eq(passed, others[i][2], others[i][1])
    end

    -- Words that only happen to end like one of the telling ones change nothing.
    eq(Parse("Thereafter 5 sec of silence follow."), 5)
    eq(Parse("Stuns all enemies nearby 4 sec."), 4)
    -- Only English words are read this way. Elsewhere every time still counts.
    eq(Parse("Kann nur innerhalb von 20 Sek. nach dem Sieg benutzt werden."), 20)
    eq(Parse("Inflige 147 points de dégâts en 21 s."), 21)
    -- The words kept for the report are cut by bytes, and never begin with half a character.
    local _, read = Parse("目标受到流血效果的影响，在21秒内受到伤害。")
    check(read and not read:find("^[\128-\191]"), "begins with a whole character: " .. tostring(read))
    check(read:find("21秒", 1, true), "and still holds the time: " .. read)
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

test("buffs, ids: with no buff of yours seen yet this fight, a cast that leaves nothing is not held against the spell", function()
    local w, ns = Bar({ combatAuras = "ids" }, BLOCK, REND)
    Fight(w)
    w:cast(BLOCK, { miss = true })
    w:advance(3)
    eq(w:icon("ActionButton1"), "check", "nothing changed on you, so nothing is shown")
    eq(ns.db.learned["Shield Block"], nil, "and not counted as evidence: no buffs could be the client hiding them")
    w:cast(BLOCK)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "one that does leave its buff shows")
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
    for _ = 1, 2 do
        w:cast(MEND)
        w:advance(3)
    end
    eq(w:icon("ActionButton1"), "check", "two empty casts are not enough")
    w:drain()
    w:cast(MEND)
    w:advance(3)
    eq(ns.db.learned["Mending Touch"].buffCasts, 3)
    eq(ns.db.learned["Mending Touch"].buffHits, 0)
    eq(w:icon("ActionButton1"), nil, "dropped after three that left nothing")
    check(w:drain():find("Mending Touch left no status effect behind after 3 of 3 casts", 1, true), "and it says so")
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
    eq(w:icon("ActionButton2"), "check", "and nothing is assumed either: your effects did not change")
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

test("a success with no sent event and no reports is not judged", function()
    local w, ns = Simple({ combatAuras = "ids", auraEvents = false })
    w:cast(REND, { noSent = true })
    w:advance(3)
    eq(w:icon("ActionButton1"), "check", "nothing to go on, and nothing is assumed while reports may still come")
    eq(ns.db.learned.Rend, nil, "no before-picture, so no evidence")
    Clean(w)
end)

test("a success with no sent event on a client known not to report is assumed, not judged", function()
    local quiet = { doubt = { player = BUILD, target = BUILD, softenemy = BUILD, plate = BUILD } }
    local w, ns = Simple({ combatAuras = "ids", auraEvents = false, saved = quiet })
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
    w:cast(REND) -- the fight is on, and the boar has shown an effect of yours
    w:advance(22)

    w:slash("track heroic")
    w:advance(0.5)
    eq(w:icon("ActionButton2"), "check", "forced on, matched by the start of its name")
    for _ = 1, 2 do
        w:cast(HEROIC)
        w:advance(5)
        eq(w:icon("ActionButton2"), "check", "judged like any other spell at first: it left nothing")
    end
    w:cast(HEROIC)
    w:advance(5)
    eq(w:icon("ActionButton2"), "cross", "after that a forced spell is trusted even with nothing to see")
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
    w:drain()
    w:slash("debug")
    check(w:drain():find("Whether a skill can be used: told by the action bar. Whether its target is in reach: "
        .. "told by the action bar.", 1, true), "/se debug says who answers")

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
    -- Not of the action, not of the spell, and on a button with no colours to read.
    local w = Simple({ usableAPI = "reason secret", buttonLook = "none" })
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
    -- Not of the action, not of the spell, and on a button with no colours to read.
    for _, api in ipairs({ "none", "secret" }) do
        local w = Simple({ usableAPI = api, buttonLook = "none" })
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

--------------------------------------------------------------------------------
-- Other ways of finding out whether a skill can be used
--------------------------------------------------------------------------------

test("when the action bar will not say whether a skill can be used, the spell is asked", function()
    local w, ns = Simple({ usableAPI = "secret", spellAPI = "plain", buttonLook = "none" })
    eq(w:icon("ActionButton1"), "check")
    eq(w:icon("ActionButton3"), "check")

    w:setUsable(1, false)
    w:setUsable(3, false)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "the wrong stance for Rend, as the game says of the spell")
    eq(w:icon("ActionButton3"), nil, "and Battle Shout held back")
    w:setUsable(1, false, true)
    w:setUsable(3, true)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "only short of rage: that does not hide an icon")
    eq(w:icon("ActionButton3"), "check")

    w:setUsable(1, true)
    w:setRange(1, false)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "out of reach, as the game says of the spell")
    w:setRange(1, true)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check")

    w:drain()
    w:slash("usable")
    check(not w:drain():find("not telling", 1, true), "nothing to own up to: the setting does its work")
    w:slash("debug")
    local said = w:drain()
    check(said:find("Whether a skill can be used: not told by the action bar, so asked about the spell. Whether "
        .. "its target is in reach: not told by the action bar, so asked about the spell.", 1, true),
        "/se debug says who answers: " .. said)
    local from = ns.db.report.usableFrom
    check(from and from.calm["spell / spell"], "and so does the saved report, for Rend")
    check(from.calm["spell / -"], "and for Battle Shout, whose reach is not asked: it goes on you")
    eq(from.fight, nil, "nothing from a fight: there was none")
    Clean(w)
end)

test("when neither the action bar nor the spell will say, the button itself is looked at", function()
    local w = Simple({ usableAPI = "secret" })
    eq(w:icon("ActionButton1"), "check", "the game has painted the picture white: the skill can be used")
    eq(w:icon("ActionButton3"), "check")

    w:setUsable(1, false)
    w:setUsable(3, false)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "Rend is painted grey")
    eq(w:icon("ActionButton3"), nil, "and so is Battle Shout")
    w:setUsable(1, false, true)
    w:setUsable(3, true)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "blue is short of rage, which does not hide an icon")
    eq(w:icon("ActionButton3"), "check")

    w:setUsable(1, true)
    w:setRange(1, false)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "the key's name is red: out of reach")
    w:setRange(1, true)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check")

    w:drain()
    w:slash("usable")
    check(not w:drain():find("not telling", 1, true), "nothing to own up to")
    w:slash("debug")
    local said = w:drain()
    check(said:find("Whether a skill can be used: read off the button's own colours. Whether its target is in "
        .. "reach: read off the button's own colours.", 1, true), "/se debug says how it knows: " .. said)
    Clean(w)

    -- Some bar addons turn the whole picture red out of reach, not the key's name.
    w = Simple({ usableAPI = "secret", buttonLook = "red icon" })
    eq(w:icon("ActionButton1"), "check")
    w:setRange(1, false)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "a red picture is out of reach as well")
    w:setRange(1, true)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check")
    Clean(w)

    -- Colours an addon may not read say nothing, so the icons show.
    w = Simple({ usableAPI = "secret", buttonLook = "secret" })
    w:setRange(1, false)
    w:setUsable(3, false)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "secret colours: Rend")
    eq(w:icon("ActionButton3"), "check", "secret colours: Battle Shout")
    w:drain()
    w:slash("usable")
    check(w:drain():find("not telling the addon whether a skill can be used", 1, true), "and /se usable owns up")
    Clean(w)
end)

test("why a skill cannot be used is found out another way when the action bar keeps it back", function()
    -- Rend is short of rage and Battle Shout is held back for another reason. The
    -- action bar says of both that they cannot be used, and of neither why.
    local function Told(options, how)
        local w = Simple(options)
        w:setUsable(1, false, true)
        w:setUsable(3, false)
        w:advance(0.3)
        eq(w:icon("ActionButton1"), "check", how .. ": short of rage, so the icon stays")
        eq(w:icon("ActionButton3"), nil, how .. ": not rage, so it goes")
        w:setUsable(3, false, true)
        w:advance(0.3)
        eq(w:icon("ActionButton3"), "check", how .. ": and comes back when rage is all that is missing")
        Clean(w)
    end
    Told({ usableAPI = "reason secret", spellAPI = "plain", buttonLook = "none" }, "asked of the spell")
    Told({ usableAPI = "reason secret" }, "read off the button, blue for rage and grey for the rest")
end)

test("a skill does not lose its icon for good to a source that says no to everything", function()
    -- The game does not know the spells by the numbers the bar gives: asked
    -- about them, it says "cannot be used" every time.
    local w = Simple({ usableAPI = "secret", spellAPI = "strange", buttonLook = "none" })
    w:advance(2)
    eq(w:icon("ActionButton1"), "check", "a \"no\" from a source that has never said anything else is not believed")
    eq(w:icon("ActionButton3"), "check")
    w:drain()
    w:slash("usable")
    check(w:drain():find("not telling the addon whether a skill can be used", 1, true), "and /se usable owns up")
    Clean(w)

    -- The bars paint every picture dim, whatever the skill.
    w = Simple({ usableAPI = "none", buttonLook = "dim" })
    w:advance(2)
    eq(w:icon("ActionButton1"), "check", "a bar that is all grey says nothing")
    eq(w:icon("ActionButton3"), "check")
    Clean(w)

    -- Once a button has shown that it can be told apart, its grey counts.
    w = Simple({ usableAPI = "none" })
    eq(w:icon("ActionButton1"), "check")
    w:setUsable(1, false)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "white a moment ago, grey now")
    Clean(w)
end)

--- Rend, Thunder Clap and Battle Shout on the bar and a boar targeted, on a
--- client that answers about skills out of a fight and not in one.
local function QuietInFights(options)
    options = options or {}
    options.usableAPI = "combat secret"
    local w = World(options)
    w:addButton("ActionButton1", 1, REND)
    w:addButton("ActionButton2", 2, CLAP)
    w:addButton("ActionButton3", 3, SHOUT)
    return w
end

local function Pull(w)
    local ns = w:load()
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:advance(0.6)
    return ns
end

test("what a fight hides about skills is read off the buttons, which were checked while the game still answered", function()
    local w = QuietInFights()
    w:setUsable(1, false) -- the wrong stance for Rend, from the start
    local ns = Pull(w)
    eq(w:icon("ActionButton1"), nil, "out of a fight the action bar says so")
    eq(w:icon("ActionButton2"), "check")
    eq(w:icon("ActionButton3"), "check")

    w:enterCombat()
    w:advance(0.6)
    eq(w:icon("ActionButton1"), nil, "in the fight Rend's grey is believed, although Rend was never seen any "
        .. "other way: the other two buttons proved that these bars paint as the game does")
    eq(w:icon("ActionButton2"), "check")
    eq(w:icon("ActionButton3"), "check")
    w:setUsable(1, true)
    w:setUsable(2, false)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "the right stance at last")
    eq(w:icon("ActionButton2"), nil, "and Thunder Clap held back")

    local from = ns.db.report.usableFrom
    check(from.calm["bar / bar"], "the saved report: the action bar answered out of the fight")
    check(from.fight["look / look"] or from.fight["look / bar"], "and the buttons' colours in it")
    Clean(w)
end)

test("a button whose colours contradict the action bar is not believed once the bar falls silent", function()
    local w = QuietInFights({ spellAPI = "none" })
    -- A fourth skill, on a bar addon's button that is drawn dim whatever the skill.
    local odd = w:addButton("BT4Button1", 4, MARK)
    odd.icon.paint = function()
        return 0.4, 0.4, 0.4, 1
    end
    Pull(w)
    eq(w:icon("BT4Button1"), "check", "out of a fight the action bar says it can be used")

    w:enterCombat()
    w:advance(0.6)
    eq(w:icon("BT4Button1"), "check", "grey, and not believed: it was grey while the action bar said yes")
    w:setUsable(1, false)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "the game's own buttons are still read")
    w:drain()
    w:slash("usable")
    check(not w:drain():find("not telling", 1, true), "one button without an answer is not the client keeping quiet")
    Clean(w)
end)

test("a spell the game answers wrongly about is not believed once the action bar falls silent", function()
    local w = QuietInFights({ spellAPI = "plain", buttonLook = "none" })
    w:addButton("ActionButton4", 4, MARK)
    w.spells[MARK].strange = true -- it says "cannot be used" of this one whatever happens
    Pull(w)
    eq(w:icon("ActionButton4"), "check", "out of a fight the action bar says it can be used")

    w:enterCombat()
    w:advance(0.6)
    eq(w:icon("ActionButton4"), "check", "\"cannot be used\", and not believed: it said so while the action bar said yes")
    w:setUsable(1, false)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "what it says of the other spells still counts")
    Clean(w)
end)

test("the spell and the button are left alone once it is settled that they agree with the action bar", function()
    local w = Simple()
    w:advance(1)
    w.spellAsked, w.lookAsked = 0, 0
    w:setUsable(1, false)
    w:advance(1)
    w:setUsable(1, true)
    w:setRange(1, false)
    w:advance(1)
    eq(w.spellAsked, 0, "the action bar answers, so the spell is not asked")
    eq(w.lookAsked, 0, "and the button is not looked at")
    Clean(w)
end)

test("reach is judged to whoever the skill would go to", function()
    -- A buff that goes on you does not mind how far away your target is.
    local w = Simple()
    w:setRange(3, false)
    w:advance(0.3)
    eq(w:icon("ActionButton3"), "check", "Battle Shout, with the boar out of reach")
    Clean(w)

    -- An attack that leaves its effect on you still has to reach the enemy.
    w = Bar(nil, RAMPAGE)
    w:slash("buff Rampage") -- judged as a buff on you from here on
    local wolf = w:addMob("Wolf")
    w:showPlate(wolf)
    w:target(wolf)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "Rampage, with the wolf in reach")
    w:setRange(1, false)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "the wolf is out of reach, and Rampage strikes the wolf")
    Clean(w)

    -- A buff for a friend does mind how far the friend is.
    w = Bar(nil, FORT)
    local guard = w:addMob("Guard", { hostile = false })
    w:target(guard)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "Fortitude for the guard")
    w:setRange(1, false)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "the guard is out of reach")
    w:target(nil)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "with nobody targeted it goes on you, and you are always in reach")
    Clean(w)

    -- With nothing targeted, a debuff goes to the enemy the game picks by itself.
    w = Bar(nil, REND)
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:softTarget(boar)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "Rend for the boar the game picked")
    w:setRange(1, false, "softenemy")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "which is out of reach")
    check(w.rangeAsked.softenemy, "the game was asked about that boar by name")
    w:setRange(1, true, "softenemy")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check")
    Clean(w)

    -- A client whose call takes no unit is asked the plain way. (Nothing else
    -- to go by here: no call about the spell, no colours on the button.)
    w = Bar({ usableAPI = "no unit", spellAPI = "none", buttonLook = "none" }, REND)
    boar = w:addMob("Boar")
    w:showPlate(boar)
    w:softTarget(boar)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check")
    w:setRange(1, false)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "its own notion of who the skill goes to")
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

--------------------------------------------------------------------------------
-- The settings panel: looking after itself
--
-- Nobody should have to type a command, or even notice, when something of the
-- game's is missing or does not behave: the panel finds out and helps itself.
--------------------------------------------------------------------------------

--- Every label that has been made in this world, on screen or not.
local function Labels(w)
    local list = {}
    for i = 1, #w.frames do
        for _, label in ipairs(w.frames[i].strings) do
            list[#list + 1] = label
        end
    end
    return list
end

--- How many frames were made from one of the game's templates.
local function Made(w, template)
    local count = 0
    for i = 1, #w.frames do
        if w.frames[i].template == template then
            count = count + 1
        end
    end
    return count
end

local SLIDER, TICK, BUTTON = "MinimalSliderWithSteppersTemplate", "MinimalCheckboxTemplate", "UIPanelButtonTemplate"

test("settings: a control of the game's that fails its test is replaced without a word", function()
    -- What is wrong with it, which control that is, and how to try the replacement.
    local faults = {
        { SLIDER, "stuck", "slider" }, { SLIDER, "hollow", "slider" }, { SLIDER, "mute", "slider" },
        { TICK, "forgets", "tick" }, { TICK, "huge", "tick" }, { BUTTON, "wordless", "button" },
    }
    for _, fault in ipairs(faults) do
        local what = fault[2] .. " " .. fault[3]
        local w, ns = Simple({ brokenTemplates = { [fault[1]] = fault[2] } })
        w:drain()
        local view = w:openSettings().view
        check(view ~= nil, "the panel is built with a " .. what)
        eq(view.size.slider.native == true, fault[3] ~= "slider", "the slider, with a " .. what)
        eq(view.enable.native == true, fault[3] ~= "tick", "the tick box, with a " .. what)
        eq(view.size.auto.native == true, fault[3] ~= "tick", "the Auto tick box, with a " .. what)
        eq(view.reset.native == true, fault[3] ~= "button", "the reset button, with a " .. what)
        eq(Made(w, fault[1]), 1, "one that failed is not tried again for the next control, with a " .. what)

        -- Everything still works.
        w:slide(view.size.slider.widget, 26)
        eq(ns.db.size, 26, "the size slider works, with a " .. what)
        w:click(view.enable.frame)
        eq(ns.db.enabled, false, "the tick box works, with a " .. what)
        w:click(view.enable.frame)
        w:click(view.reset)
        w:click(view.confirm.yes)
        eq(ns.db.size, 0, "the reset button works, with a " .. what)

        -- The window of its own goes the same way, and nothing is said in chat.
        w:slash("options")
        local window = w.env.StatusEfficiencyOptions.view
        eq(window.size.slider.native == true, fault[3] ~= "slider", "the window's slider, with a " .. what)
        eq(Made(w, fault[1]), 1, "nor is it tried again for the window, with a " .. what)
        eq(w:drain(), "", "nothing is said, with a " .. what)

        -- Why is kept, and saved with the settings once the panel closes.
        check(ns.Options.notes.controls[fault[3]]:find("^own: "), "the reason is noted, with a " .. what)
        w:closeSettings()
        eq(ns.db.panel.controls[fault[3]], ns.Options.notes.controls[fault[3]], "and saved, with a " .. what)
        Clean(w)
    end
end)

test("settings: the game's slider is heard whichever way it tells of a move, and once", function()
    for _, fault in ipairs({ false, "no notice", "no hook" }) do
        local what = fault or "nothing wrong"
        local w, ns = Simple(fault and { brokenTemplates = { [SLIDER] = fault } } or nil)
        local view = w:openSettings().view
        eq(view.size.slider.native, true, "the game's slider is kept, with " .. what)

        local changes = 0
        local relayout = ns.Relayout
        ns.Relayout = function(...)
            changes = changes + 1
            return relayout(...)
        end
        w:slide(view.size.slider.widget, 26)
        eq(ns.db.size, 26, "a drag is heard, with " .. what)
        eq(changes, 1, "and acted on once, with " .. what)
        Step(w, view, 1)
        eq(ns.db.size, 27, "so is a step, with " .. what)
        eq(changes, 2, "once, with " .. what)
        eq(view.size.readout:GetText(), "27")
        Clean(w)
    end
end)

test("settings: a control whose art this client lacks is not used, since it would not be seen", function()
    local w = Simple({ missingAtlases = { ["checkmark-minimal"] = true } })
    local view = w:openSettings().view
    eq(view.enable.native, nil, "a tick box whose tick would not show")
    eq(view.size.slider.native, true, "the slider's art is all there")
    check(w.ns.Options.notes.controls.tick:find("art", 1, true), "and why is noted")
    Clean(w)

    w = Simple({ missingAtlases = { Minimal_SliderBar_Button = true } })
    view = w:openSettings().view
    eq(view.size.slider.native, nil, "a slider with no thumb to drag")
    eq(view.enable.native, true)
    Clean(w)

    w = Simple({ missingAtlases = { ["RedButton-Exit"] = true, Options_HorizontalDivider = true } })
    local canvas = w:openSettings()
    w:slash("options")
    eq(w.env.StatusEfficiencyOptions.close.template, nil, "a close button with no face")
    local line
    for _, texture in ipairs(canvas.host.textures) do
        line = line or texture.color
        eq(texture.wantedAtlas, nil, "the heading's rule is not left to art that is not there")
    end
    check(line, "the addon draws the rule under the heading itself")
    Clean(w)

    -- A client that cannot be asked about its art is taken at its word.
    w = Simple({ noAtlasQuery = true })
    view = w:openSettings().view
    eq(view.enable.native, true)
    eq(view.size.slider.native, true)
    Clean(w)
end)

test("settings: if the panel breaks while it is built with the game's controls, it is built again with its own", function()
    -- The game's button is made without complaint, and fails once it is given a click to act on.
    local w, ns = Simple({ brokenTemplates = { [BUTTON] = "late" } })
    w:drain()
    local canvas = w:openSettings()
    local view = canvas.view
    check(view ~= nil, "there is a panel all the same")
    eq(w:drain(), "", "and nothing is said about it")
    eq(view.reset.native, nil, "its buttons are the addon's own")
    eq(view.enable.native, nil, "and so is the rest, so that it is all of a piece")
    eq(view.size.slider.native, nil)
    eq(#ns.Options.views, 1, "the half-built copy is not kept")
    check(canvas.host:IsVisible(), "the copy that worked is the one on screen")
    local hidden = 0
    for _, child in ipairs(canvas.children) do
        if not child.shown then
            hidden = hidden + 1
        end
    end
    eq(hidden, 1, "and the half-built one is put away")

    w:click(view.previews.none.zones.RIGHT)
    eq(ns.db.corner, "RIGHT", "it works")
    w:click(view.reset)
    w:click(view.confirm.yes)
    eq(ns.db.corner, "TOPLEFT")

    -- Later copies do not try the game's controls again this session.
    local made = Made(w, BUTTON)
    w:slash("options")
    local window = w.env.StatusEfficiencyOptions
    check(window:IsShown(), "the window of its own opens")
    eq(window.view.reset.native, nil)
    eq(window.close.template, nil)
    eq(Made(w, BUTTON), made, "the game's button is not made again")
    eq(w:drain(), "")

    check(ns.Options.notes.rebuilt:find("click script", 1, true), "what went wrong is noted")
    w:closeSettings()
    check(ns.db.panel.rebuilt:find("click script", 1, true), "and saved with the settings")
    eq(ns.db.plain, false, "the player's own choice of drawing is left alone")
    Clean(w)

    -- The same when the window of its own is the first copy to be built.
    w, ns = Simple({ brokenTemplates = { [BUTTON] = "late" } })
    w:drain()
    w:slash("options")
    window = w.env.StatusEfficiencyOptions
    check(window:IsShown(), "the window opens")
    eq(w:drain(), "")
    eq(window.view.reset.native, nil)
    eq(#w.env.UISpecialFrames, 1, "Escape closes it, and only it")
    eq(#ns.Options.views, 1)
    w:click(window.close)
    eq(window:IsShown(), false)
    eq(w:openSettings().view.reset.native, nil, "and the Options window follows suit")
    Clean(w)
end)

test("settings: in the game's standard font no label is drawn smaller", function()
    local w = Bar(nil, REND, HEROIC, SHOUT, CLAP, MARK, HAWK)
    local view = w:openSettings().view
    w:click(view.swatches.some.check) -- two results share an icon, so the note at the far end is up
    w:click(view.tabs.spells)
    w:slash("options")
    local fitted = 0
    for _, label in ipairs(Labels(w)) do
        if label.fitRoom then
            fitted = fitted + 1
            eq(label.textScale or 1, 1, "the scale of \"" .. tostring(label.text) .. "\"")
            check(not label.fitCut, "\"" .. tostring(label.text) .. "\" is whole")
        end
    end
    check(fitted > 100, "the panel's labels are measured: " .. fitted)
    for _, preview in pairs(view.previews) do
        eq(preview.caption.textScale or 1, 1, "the captions under the preview")
    end
    eq(next(w.ns.Options.notes.fonts), nil, "no font had to be replaced")
    Clean(w)
end)

--- Fails unless every fitted label in the world is inside the room it has.
local function Fits(w, what)
    local smaller = 0
    for _, label in ipairs(Labels(w)) do
        local scale = label.textScale or 1
        check(scale >= 0.7 - 1e-9, "\"" .. tostring(label.text) .. "\" is too small to read, " .. what)
        if scale < 1 then
            smaller = smaller + 1
        end
        if label.fitLines then
            eq(label.maxLines, label.fitLines, "lines \"" .. tostring(label.text) .. "\" may take, " .. what)
        elseif label.fitRoom then
            check(label:GetStringWidth() <= label.fitRoom + 0.5, string.format("\"%s\" is %.0f wide in room for %.0f, %s",
                tostring(label.text), label:GetStringWidth(), label.fitRoom, what))
        end
    end
    return smaller
end

test("settings: in a wider font labels are drawn smaller, and none outgrows its room", function()
    for _, wider in ipairs({ 1.15, 1.4, 2.5 }) do
        local what = "letters " .. wider .. " times as wide"
        local w, ns = Bar({ fontWidth = wider }, REND, HEROIC, SHOUT, CLAP, MARK, HAWK)
        local view = w:openSettings().view
        w:click(view.swatches.some.check)
        w:click(view.tabs.spells)
        w:slash("options")
        check(Fits(w, what) > 0, "some labels had to shrink, with " .. what)

        -- The three captions under the pretend buttons keep clear of each other.
        local keys = { "none", "some", "all" }
        for i = 1, 2 do
            local left, right = view.previews[keys[i]].caption, view.previews[keys[i + 1]].caption
            check((left:GetStringWidth() + right:GetStringWidth()) / 2 + 4 <= 92.01,
                "captions " .. i .. " and " .. (i + 1) .. " keep a gap, with " .. what)
        end

        -- A sentence beside a heading gives way to the note at the far end.
        w:click(view.tabs.appearance)
        local page = view.pages.appearance
        for _, key in ipairs(keys) do
            local name, detail, clash = view.names[key], view.details[key], view.clashes[key]
            local ends = 38 + name:GetStringWidth() + 10 + detail:GetStringWidth()
            local starts = clash:IsShown() and 624 - clash:GetStringWidth() or 624
            check(ends <= starts + 0.5, "the sentence for " .. key .. " ends before the note, with " .. what)
        end
        check(page:IsVisible())

        -- A click on a tick box's words still lands on the box, and no further.
        local reach = -view.enable.frame.hitInsets[2] - 6
        near(reach, view.enable.label:GetStringWidth(), "how far the tick box reaches, with " .. what)

        -- What had to give is noted for later.
        w:closeSettings()
        check(next(ns.db.panel.tight) ~= nil, "tight labels are saved with the settings, with " .. what)
        Clean(w)
    end
end)

test("settings: a client whose labels cannot be drawn smaller still gets the whole panel", function()
    local w, ns = Bar({ fontWidth = 1.4, noTextScale = true }, REND, HEROIC, SHOUT)
    local view = w:openSettings().view
    check(view ~= nil, "the panel is built")
    for _, label in ipairs(Labels(w)) do
        eq(label.textScale, nil)
    end
    w:click(view.tabs.spells)
    eq(view.spells.rows[1].why.maxLines, 2, "what wraps is still kept to the lines it has room for")
    w:click(view.tabs.appearance)
    w:click(view.previews.none.zones.RIGHT)
    eq(ns.db.corner, "RIGHT")
    Clean(w)
end)

test("settings: a font this client lacks is replaced by its nearest neighbour", function()
    local w, ns = Simple({ missingFonts = { GameFontHighlightSmall = true, GameFontDisableSmall = true } })
    local view = w:openSettings().view
    eq(view.appear.buttons.always.label.font, "GameFontNormalSmall", "the font of a choice")
    eq(view.sampleNote.font, "GameFontNormalSmall", "the font of a note")
    eq(view.inputs.none.font, "GameFontNormalSmall", "the font of a box to type in")
    eq(ns.Options.notes.fonts.GameFontHighlightSmall, "GameFontNormalSmall", "it is noted")
    w:click(view.appear.buttons.combat)
    eq(ns.db.appear, "combat")
    Clean(w)

    -- Not one of the fonts: the game's everyday typeface, by its file.
    local all = {}
    for _, font in ipairs({ "GameFontNormal", "GameFontNormalLarge", "GameFontNormalSmall", "GameFontHighlight",
        "GameFontHighlightSmall", "GameFontHighlightHuge", "GameFontDisable", "GameFontDisableSmall" }) do
        all[font] = true
    end
    w, ns = Simple({ missingFonts = all, noTemplates = true })
    w:drain()
    view = w:openSettings().view
    check(view ~= nil, "the panel is built without a single font to borrow")
    eq(w:drain(), "")
    eq(view.sampleNote.fontFile, "Fonts\\FRIZQT__.TTF")
    eq(view.sampleNote.fontHeight, 10, "small text stays small")
    eq(view.tabs.spells.label.fontHeight, 12)
    eq(view.inputs.none.fontFile, "Fonts\\FRIZQT__.TTF", "boxes to type in too")
    eq(ns.Options.notes.fonts.GameFontNormal, "none")
    w:click(view.tabs.spells)
    eq(view.spells.rows[1].name:GetText(), "Battle Shout")
    w:slash("options")
    check(w.env.StatusEfficiencyOptions:IsShown())
    Clean(w)
end)

test("settings: on a smaller page of the Options window the whole panel is drawn smaller", function()
    local w, ns = Simple()
    local canvas = w:openSettings()
    eq(canvas.host.scale, nil, "the usual page: drawn as it is")
    eq(ns.Options.notes.page, "665 x 601", "the page it was given is noted")
    near(canvas.view.previews.none.button.width, 45, "the pretend buttons are life-size")
    local point, anchor, _, x = canvas.view.divider:GetPoint(1)
    check(point == "TOP" and anchor == canvas and x == 0,
        "the game's divider runs across the middle of the page, which is wider than the panel, as on the game's own pages")
    Clean(w)

    w, ns = Simple({ settingsPage = { 500, 450 } })
    canvas = w:openSettings()
    near(canvas.host.scale, 0.75, "three quarters as large, to fit 500 by 450")
    check(640 * canvas.host.scale <= 500 and 600 * canvas.host.scale <= 450, "all of it is on the page")
    near(canvas.view.previews.none.button.width, 60,
        "the pretend buttons grow in the panel's units, so that they stay life-size on screen")
    w:click(canvas.view.previews.none.zones.RIGHT)
    eq(ns.db.corner, "RIGHT")

    -- The Options window settles on another size while the panel is up.
    w.settingsCanvas:SetSize(320, 601)
    canvas.scripts.OnSizeChanged(canvas, 320, 601)
    near(canvas.host.scale, 0.5, "half as large, and no smaller than that")
    w.settingsCanvas:SetSize(900, 700)
    canvas.scripts.OnSizeChanged(canvas, 900, 700)
    near(canvas.host.scale, 1, "back to full size on a roomy page, and never larger")
    near(canvas.view.previews.none.button.width, 45)
    w:closeSettings()
    eq(ns.db.panel.page, "900 x 700")
    eq(ns.db.panel.scale, 1)
    Clean(w)

    -- A window of its own is not at the mercy of anybody's page.
    w:slash("options")
    eq(w.env.StatusEfficiencyOptions.scale, nil)
    Clean(w)
end)

test("settings: what the panel found out about this client is saved with the settings", function()
    local w, ns = Simple()
    eq(ns.db.panel, nil, "nothing until the panel has been built")
    w:openSettings()
    local saved = ns.db.panel
    eq(saved.version, ns.VERSION)
    eq(saved.build, BUILD)
    eq(saved.plain, false)
    eq(saved.controls.button, "game")
    eq(saved.controls.tick, "game")
    eq(saved.controls.slider, "game")
    eq(saved.rebuilt, nil)
    eq(saved.failed, nil)
    w:slash("options")
    eq(ns.db.panel.controls.close, "game", "the window adds its close button")
    Clean(w)

    w, ns = Simple({ noTemplates = true })
    w:openSettings()
    check(ns.db.panel.controls.tick:find("^own: .*MinimalCheckboxTemplate"), "a missing template is named")
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
    w:advance(0.1) -- a report in the very frame a target is picked is about the picking
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
