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
-- Skills whose effect stacks, and ones that more than one player in a group has.
local SUNDER, RAGING, RENEW, FRENZY, DEMO, ROAR = 130, 131, 132, 133, 1160, 12323

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

    -- An effect that stacks, and that an enemy carries only once however many
    -- warriors put it there.
    w:addSpell(SUNDER, {
        name = "Sunder Armor", harmful = true,
        description = "Sunders the target's armor, reducing it by 180 per Sunder Armor and causes a high amount "
            .. "of threat. Can be applied up to 5 times. Lasts 30 sec.",
        effect = { duration = 30, shared = true, stacks = 5 },
    })
    w:addSpell(DEMO, {
        -- One of the well known area debuffs, by its id.
        name = "Demoralizing Shout", harmful = false, helpful = false,
        description = "Reduces the melee attack power of all enemies within 10 yards by 86 for 45 sec.",
        effect = { area = true, duration = 45, shared = true },
    })
    w:addSpell(ROAR, {
        -- An area debuff that stacks. It borrows the id of a well known one.
        name = "Searing Roar", harmful = false, helpful = false,
        description = "Scorches every enemy around you, increasing the damage they take by 2% for 20 sec. "
            .. "Stacks up to 2 times.",
        effect = { area = true, duration = 20, shared = true, stacks = 2 },
    })
    w:addSpell(RAGING, {
        -- A shout that every warrior in the party has, and that lands on all of them.
        name = "Raging Shout", helpful = true,
        description = "The warrior shouts, increasing the attack power of all party members within 20 yards "
            .. "by 35. Lasts 3 min.",
        effect = { buff = true, duration = 180, shared = true, party = true },
    })
    w:addSpell(RENEW, {
        -- Healing over time: every caster's is their own.
        name = "Renew", helpful = true,
        description = "Heals the target for 300 over 15 sec.",
        effect = { buff = true, duration = 15 },
    })
    w:addSpell(FRENZY, {
        name = "Battle Frenzy", selfOnly = true,
        description = "Increases your attack speed by 10% for 15 sec. Stacks up to 3 times.",
        effect = { buff = true, duration = 15, stacks = 3 },
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
    IsUsableAction = true, IsActionInRange = true, C_Texture = true, UnitIsVisible = true,
    UnitCreatureID = true,
    -- Fonts, which the settings panel looks for before it borrows one.
    GameFontNormal = true, GameFontNormalLarge = true, GameFontNormalSmall = true, GameFontHighlight = true,
    GameFontHighlightSmall = true, GameFontHighlightHuge = true, GameFontHighlightLarge = true,
    GameFontDisable = true, GameFontDisableSmall = true,
    -- The picture on an action slot, which stands in for a spell's own picture.
    GetActionTexture = true,
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
    check(said:find("The game has not reported any change to the effects on your target after several of your casts "
        .. "in a row. Until it does, the addon assumes that such a cast has landed.", 1, true),
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

test("reports: the line in chat about a client that stopped reporting says whose effects it is silent about", function()
    -- About yours: a buff, six casts of it in a fight, and nothing reported.
    local w, ns = Bar({ auraEvents = "calm", saved = Proven() }, BLOCK)
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:enterCombat()
    w:advance(0.3)
    for _ = 1, 5 do
        w:cast(BLOCK)
        w:advance(11)
    end
    eq(w:drain(), "", "five casts are waited for in silence")
    w:cast(BLOCK)
    w:advance(11)
    eq(ns.db.doubt.player, BUILD)
    eq(w:drain(), "|cff66ccffStatus Efficiency|r: The game has not reported any change to the effects on you after "
        .. "several of your casts in a row. Until it does, the addon assumes that such a cast has landed.")
    Clean(w)

    -- About the enemy the game targets for you while you have none targeted.
    local w2, ns2 = Bar({ auraEvents = false }, REND)
    local wolf = w2:addMob("Wolf")
    w2:softTarget(wolf)
    w2:advance(0.3)
    for _ = 1, 3 do
        w2:cast(REND)
        w2:advance(3.5)
    end
    eq(ns2.db.doubt.softenemy, BUILD)
    eq(w2:drain(), "|cff66ccffStatus Efficiency|r: The game has not reported any change to the effects on the enemy "
        .. "that is targeted for you after several of your casts in a row. Until it does, the addon assumes that "
        .. "such a cast has landed.")
    Clean(w2)
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
    check(said:find("Mortal Strike lost its icon because 5 of your 6 casts left no effect behind.", 1, true), said)
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
    check(said:find("Mortal Strike does leave an effect behind: 4 of your last 9 casts did. It has its icon back.", 1, true),
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
    check(w:drain():find("Mortal Strike lost its icon because 3 of your 3 casts left no effect behind.", 1, true),
        "said in chat")

    w:cast(MORTAL)
    w:advance(11)
    eq(w:icon("ActionButton1"), nil, "1 of 4: one that lands is not enough")
    eq(w:drain(), "")
    w:cast(MORTAL)
    w:advance(0.8)
    eq(ns.db.learned["Mortal Strike"].hits, 2)
    eq(ns.db.learned["Mortal Strike"].casts, 5)
    eq(w:icon("ActionButton1"), "cross", "2 of 5: the icon is back, and knows about the cast that earned it")
    check(w:drain():find("Mortal Strike does leave an effect behind: 2 of your last 5 casts did. It has its icon back.",
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
    w:drain()
    w:slash("list")
    local list = w:drain()
    check(list:find("Gouge Armor|r puts a debuff that lasts 12 seconds on your target. It has an icon because 6 of your "
        .. "6 casts left an effect behind.", 1, true), "/se list says what it earned its icon by: " .. list)
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
    -- A client on which a landing takes a moment to show.
    local w, ns, boar = Simple({ saved = Proven() })
    eq(Wait(ns, REND), 1.5, "before it has been timed")
    for _ = 1, 3 do
        w:cast(REND, { travel = 0.2 })
        w:advance(22)
    end
    check(Wait(ns, REND) >= 0.85 and Wait(ns, REND) <= 1.05, "twice what it took and half a second: " .. Wait(ns, REND))

    w:cast(REND, { miss = true })
    w:advance(1.2)
    w:applyAura(boar, "Sunder Armor", 30, false) -- something else, a good second after the miss
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "is no longer taken for the Rend")

    w:cast(REND, { travel = 0.6 }) -- a slow one
    w:advance(0.8)
    eq(w:icon("ActionButton1"), "cross", "still in time")
    w:advance(22)
    check(Wait(ns, REND) >= 1.6 and Wait(ns, REND) <= 1.9, "and the wait grows to fit what was seen: " .. Wait(ns, REND))
    for _ = 1, 6 do
        w:cast(REND, { travel = 0.2 })
        w:advance(22)
    end
    check(Wait(ns, REND) < 1.3, "then shrinks again as casts show sooner: " .. Wait(ns, REND))
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

--- True when a spell is held to the frame of its cast (see Spells:Wait).
local function Sharp(ns, spellID)
    local _, sharp = ns.Spells:Wait(ns.Spells:Get(spellID, ns.Now()))
    return sharp == true
end

test("reports: a skill whose casts show in the very frame they are announced is held to that frame", function()
    local w, ns, boar = Simple({ saved = Proven() })
    for _ = 1, 2 do
        w:cast(REND)
        w:advance(22)
    end
    eq(Wait(ns, REND), 1.5, "two casts that showed in their frame: not held to it yet")
    check(not Sharp(ns, REND))
    w:cast(REND)
    w:advance(22)
    eq(Wait(ns, REND), 0.05, "three")
    check(Sharp(ns, REND))
    for _ = 1, 7 do
        w:cast(REND)
        w:advance(22)
    end

    -- What used to pass for a hit: something else changing on the boar a
    -- moment after a miss.
    w:cast(REND, { miss = true })
    w:advance(0.1)
    w:applyAura(boar, "Thorns", 30, false)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "a tenth of a second after the miss is no longer taken for the Rend")

    -- Nor is something that changed while the cast was on its way to the
    -- server, before it was announced.
    w:advance(2)
    w.effects[#w.effects + 1] = { at = w.clock + 0.1, run = function()
        w:applyAura(boar, "Thorns", 30, false)
    end }
    w:cast(REND, { miss = true, castTime = 0.3 })
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "nor is two tenths before the cast was announced")
    eq(ns.db.learned.Rend.instant, 10)
    eq(ns.db.learned.Rend.prompt, 10, "neither was counted as a landing")

    -- A landing reported a frame apart from its cast is still in time, on
    -- either side of it.
    w:advance(2)
    w:cast(REND, { travel = 0.05 })
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "a frame after")
    w:advance(22)
    check(Sharp(ns, REND), "ten in eleven in the frame itself")
    w:cast(REND, { early = 0.05 })
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "a frame before")
    w:advance(22)
    eq(ns.db.learned.Rend.instant, 10, "neither of those was in the frame itself")
    eq(ns.db.learned.Rend.prompt, 12)
    check(not Sharp(ns, REND), "ten in twelve: it does not keep to its frame after all")
    eq(Wait(ns, REND), 0.25, "and is given a quarter of a second again")
    Clean(w)
end)

test("reports: what came too late for a skill held to its frame is kept in the saved report", function()
    local w, ns, boar = Simple({ saved = Proven() })
    for _ = 1, 3 do
        w:cast(REND)
        w:advance(22)
    end
    check(Sharp(ns, REND))
    local late = ns.db.report.late
    eq(#late, 0, "nothing while every cast shows in its frame")

    w:cast(REND, { miss = true })
    w:advance(0.4)
    w:applyAura(boar, "Thorns", 30, false)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check")
    eq(#late, 1)
    check(late[1]:find("Rend: nothing in the moment of the cast, then a change 0.40s after it", 1, true), late[1])
    check((late[1]:find("(an effect added)", 1, true) ~= nil) == KindsTold(), "what kind of change it was, where that is told: "
        .. late[1])

    -- Not a change that comes when the cast is long over.
    w:advance(2)
    w:cast(REND, { miss = true })
    w:advance(0.8)
    w:applyAura(boar, "Thorns", 30, false)
    w:advance(0.3)
    eq(#late, 1, "more than half a second after it")

    -- Nor one after a cast that did show in its frame.
    w:advance(2)
    w:cast(REND)
    w:advance(0.2)
    w:applyAura(boar, "Thorns", 30, false)
    w:advance(0.3)
    eq(#late, 1, "the cast had landed")

    -- Only the last twenty are kept.
    for _ = 1, 22 do
        w:advance(22)
        w:cast(REND)
        w:advance(22)
        w:cast(REND, { miss = true })
        w:advance(0.2)
        w:applyAura(boar, "Thorns", 30, false)
        w:advance(0.3)
    end
    eq(#late, 20)
    check(late[20]:find("then a change 0.20s after it", 1, true), late[20])
    check(Sharp(ns, REND), "and none of it is held against the skill")
    local landings = ns.db.learned.Rend.prompt + ns.db.learned.Rend.tardy
    check(landings > 10 and landings <= 20, "the tally of its landings is halved past twenty, so old ones fade: "
        .. landings)
    Clean(w)
end)

test("reports: only the first change after a cast held to its frame is kept, and only one on its own target", function()
    local saved = Proven()
    -- Heroic Strike has no icon, and has been seen to go with a change on the
    -- enemy in the frame of its cast: it is held to that frame like Rend.
    saved.learned = { ["Heroic Strike"] = { prompt = 5, tardy = 0, instant = 5, lag = 0, timed = 3 } }
    local w = World({ saved = saved })
    w:addButton("ActionButton1", 1, REND)
    w:addButton("ActionButton2", 2, HEROIC)
    w:addButton("ActionButton3", 3, SUNDER)
    local ns = w:load(saved)
    local boar, wolf = w:addMob("Boar"), w:addMob("Wolf")
    w:showPlate(boar)
    w:showPlate(wolf)
    w:target(boar)
    w:advance(0.3)
    for _ = 1, 3 do
        w:cast(REND)
        w:advance(22)
    end
    check(Sharp(ns, REND))
    check(Sharp(ns, HEROIC))
    local late = ns.db.report.late
    eq(#late, 0)
    -- The icons are looked at every frame here, so that each change reaches
    -- the books by itself, in the order it came.
    ns.db.interval = 0.01

    -- A change on another enemy says nothing of the cast, and does not use up
    -- the one line it can leave. Then two changes on the boar: one line.
    w:cast(REND, { miss = true })
    w:advance(0.2)
    w:applyAura(wolf, "Thorns", 30, false)
    w:advance(0.1)
    eq(#late, 0, "a change on the wolf")
    check(ns.Tracker:HasEchoes(), "the boar is still listened to")
    w:applyAura(boar, "Thorns", 30, false)
    w:advance(0.1)
    w:applyAura(boar, "Curse of Recklessness", 120, false)
    w:advance(0.3)
    eq(#late, 1, "the first change on the boar after the cast, and that one only")
    check(late[1]:find("Rend: nothing in the moment of the cast, then a change 0.30s after it", 1, true), late[1])

    -- A skill with no icon is not kept an eye on that way: most of them leave
    -- nothing, and every change after one would be noted.
    w:advance(2)
    w:cast(HEROIC)
    w:advance(0.2)
    w:applyAura(boar, "Thorns", 30, false)
    w:advance(0.3)
    eq(#late, 1, "Heroic Strike has no icon")

    -- A change inside the wait is not late, whichever cast it goes to. Rend
    -- misses, and Sunder Armor, used a moment after it, lands a moment later.
    w:advance(2)
    w:cast(REND, { miss = true })
    w:advance(0.02, 0.02)
    w:cast(SUNDER, { travel = 0.02 })
    w:advance(0.02, 0.02)
    w:advance(0.3)
    eq(w:icon("ActionButton3"), "check", "the change went to Sunder Armor")
    check(ns.Tracker:Has(ns.KeyOf("target", "debuff"), "Sunder Armor", ns.Now()), "and is in the books for it")
    eq(w:icon("ActionButton1"), "check")
    eq(#late, 1, "and came four hundredths after Rend: inside its wait, so not too late for it")

    -- A cast is listened for a little longer than its wait, and no longer.
    w:advance(2)
    w:cast(REND, { miss = true })
    w:advance(0.3)
    check(ns.Tracker:HasEchoes(), "three tenths of a second after the miss")
    w:advance(0.7)
    check(not ns.Tracker:HasEchoes(), "and not a second after it")

    -- Nor is a change that comes after that kept, even where the icons are
    -- looked at so seldom that the cast is still listened for by then. (The
    -- bars are read first: reading them brings on a look at the icons, and
    -- this way that does not fall in between.)
    w:advance(2)
    ns.MarkBarsDirty()
    w:advance(0.3)
    w:cast(REND, { miss = true })
    w:advance(0.2)
    ns.db.interval = 5
    w:advance(0.7)
    check(ns.Tracker:HasEchoes(), "nothing has looked since")
    w:applyAura(boar, "Thorns", 30, false)
    w:advance(6)
    eq(#late, 1, "nine tenths of a second after the cast")
    check(not ns.Tracker:HasEchoes())
    Clean(w)
end)

test("reports: a skill whose casts keep showing a moment after they are announced is given a quarter of a second", function()
    -- A client on which a landing is reported a frame after its cast.
    local w, ns, boar = Simple({ saved = Proven() })
    for _ = 1, 4 do
        w:cast(REND, { travel = 0.05 })
        w:advance(22)
    end
    check(Wait(ns, REND) >= 0.5 and Wait(ns, REND) <= 0.7, "four casts that showed at once: not held to it yet: "
        .. Wait(ns, REND))
    w:cast(REND, { travel = 0.05 })
    w:advance(22)
    eq(Wait(ns, REND), 0.25, "five")
    eq(ns.db.learned.Rend.instant, 0, "none of them in the frame of its cast")
    check(not Sharp(ns, REND))

    -- Something else changing on the boar less than half a second after a miss.
    w:cast(REND, { miss = true })
    w:advance(0.4)
    w:applyAura(boar, "Thorns", 30, false)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "is no longer taken for the Rend")

    -- A cast that shows a few frames late is still in time.
    w:advance(2)
    w:cast(REND, { travel = 0.1 })
    w:advance(0.4)
    eq(w:icon("ActionButton1"), "cross")
    w:advance(22)
    eq(Wait(ns, REND), 0.25, "and still counts as showing at once")
    eq(ns.db.learned.Rend.prompt, 6)
    eq(ns.db.learned.Rend.tardy, 0)

    -- A change while the cast was on its way to the server still counts for
    -- it: only a skill that keeps to its frame is held to that before the
    -- cast as well.
    w.effects[#w.effects + 1] = { at = w.clock + 0.1, run = function()
        w:applyAura(boar, "Thorns", 30, false)
    end }
    w:cast(REND, { miss = true, castTime = 0.3 })
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "this is the limit of what can be told")
    Clean(w)
end)

test("reports: a skill that sometimes shows late is not held to showing at once", function()
    for _, travel in ipairs({ 0, 0.05 }) do
        local w, ns = Simple({ saved = Proven() })
        local opts = travel > 0 and { travel = travel } or nil
        for i = 1, 7 do
            w:cast(REND, (i == 3 or i == 6) and { travel = 0.3 } or opts)
            w:advance(22)
        end
        eq(ns.db.learned.Rend.prompt, 5)
        eq(ns.db.learned.Rend.tardy, 2)
        eq(ns.db.learned.Rend.instant, travel == 0 and 5 or 0)
        check(Wait(ns, REND) >= 0.5, "five at once and two late: it keeps the time its slowest took: " .. Wait(ns, REND))
        check(not Sharp(ns, REND))
        for _ = 1, 3 do
            w:cast(REND, opts)
            w:advance(22)
        end
        eq(Wait(ns, REND), 0.25, "eight in ten at once")
        check(not Sharp(ns, REND), "which is not often enough to hold it to the frame of its cast")
        Clean(w)
    end

    -- A spell cast from a distance is never held to it, however often it has
    -- shown at once.
    local far = Bar({ saved = Proven() }, FROSTBOLT)
    local boar = far:addMob("Boar")
    far:target(boar)
    far:advance(0.3)
    for _ = 1, 8 do
        far:cast(FROSTBOLT)
        far:advance(10)
    end
    eq(Wait(far.ns, FROSTBOLT), 3)
    check(not Sharp(far.ns, FROSTBOLT))
    Clean(far)
end)

test("reports: a change that comes when the wait is over counts for nothing, even before the cast is looked at again", function()
    local w, ns, boar = Simple({ saved = Proven() })
    for _ = 1, 5 do
        w:cast(REND, { travel = 0.05 })
        w:advance(22)
    end
    eq(Wait(ns, REND), 0.25)
    w:cast(REND, { miss = true })
    -- One long frame: the addon does not get to look at the cast between the
    -- end of its wait and the change.
    w.effects[#w.effects + 1] = { at = w.clock + 0.3, run = function()
        w:applyAura(boar, "Thorns", 30, false)
    end }
    w:advance(0.3, 0.3)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "the wait was over when it came")
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
    check(w:drain():find("The game has not reported any change to the effects on the enemies around your target after",
        1, true),
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
    check(said:find("to the effects on your target or the enemies around your target after", 1, true),
        "one line for both: " .. said)
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
    check(said:find("Bloodthirst lost its icon because 3 of your 3 casts left no effect behind.", 1, true),
        "and it says so, so that the icon does not just go missing: " .. said)
    check(said:find("/se track Bloodthirst", 1, true), "with the way to get it back")
    w:advance(5)
    eq(w:drain(), "", "said once")
    w:slash("list")
    local list = w:drain()
    check(list:find("  |cff999999Bloodthirst|r lost its icon because 3 of your 3 casts left no effect behind.", 1, true),
        "and /se list gives the same reason: " .. list)
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
    check(w:drain():find("Victory Rush lost its icon because 4 of your 4 casts left no effect behind.", 1, true),
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

test("buffs: another player's buff counts when it is one you carry only once, and not when it is each caster's own", function()
    local w, ns = Bar(nil, FORT, RENEW)
    w:applyBuff("Fortitude", 3600, false) -- from a passing priest, who has a talent for it
    w:applyBuff("Renew", 15, false) -- and their healing over time, which yours would add to
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross", "their Fortitude does what yours would")
    eq(w:icon("ActionButton2"), "check", "their Renew is theirs, and yours is still worth casting")
    eq(ns.db.learned.Fortitude.buff, true, "the buff carries the spell's name, whoever cast it")
    eq(ns.db.learned.Fortitude.duration, nil, "how long theirs lasts says nothing of yours")
    eq(ns.db.learned.Renew, nil, "and nothing is learned from an effect that does not count")
    w:cast(RENEW)
    w:advance(0.5)
    eq(w:icon("ActionButton2"), "cross", "your own")
    w:cast(FORT)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross")
    eq(ns.db.learned.Fortitude.duration, 1800, "yours is what its length is learned from")
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
    check(w:drain():find("Mending Touch lost its icon because 3 of your 3 casts left no effect behind.", 1, true),
        "and it says so")
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
    check(w:drain():find("Commanding Shout is now on Always, so it has an icon. The icon checks every enemy in the "
        .. "fight for its debuff. If Commanding Shout gives you a buff instead, type /se buff Commanding Shout.", 1, true),
        "/se track says how it will be judged")
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
    check(list:find("Commanding Shout|r gives you a buff that lasts 2 minutes. You chose Always, so it has an icon.",
        1, true),
        "the list says so: " .. list)

    w:slash("debuff commanding shout")
    w:advance(0.5)
    eq(w:icon("ActionButton1"), nil, "a debuff again, and no enemy around")
    eq(ns.db.spells["Commanding Shout"].kind, "debuff")

    w:slash("aoe commanding")
    w:slash("buff commanding")
    w:drain()
    w:slash("single commanding")
    check(w:drain():find("The effect of Commanding Shout is treated as a buff, so this changes nothing for now.", 1, true),
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
    check(w:drain():find("No skill called \"nonsense spell\" is on your action bars.", 1, true),
        "an unknown spell is refused politely")
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
    check(w:drain():find("Type a size from 8 to 48 pixels, as in /se size 24, or type /se size auto to let the icons "
        .. "follow the size of the button.", 1, true), "too small is refused with how to say it")
    w:slash("size 49")
    check(w:drain():find("Type a size from 8 to 48 pixels, as in /se size 24", 1, true), "and so is too large")
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
    check(list:find("Rend|r puts a debuff that lasts 21 seconds on your target.", 1, true),
        "list says where Rend is looked for: " .. list)
    check(list:find("Battle Shout|r gives you, or the friend you have targeted, a buff", 1, true),
        "list shows Battle Shout as a buff: " .. list)
    check(list:find("a buff that lasts 2 minutes.", 1, true), "list gives long durations in minutes: " .. list)
    check(list:find("1 other skill has no icon because it does not seem to leave a buff or a debuff behind. To give it "
        .. "an icon anyway, type /se track <skill>", 1, true), "list counts the rest: " .. list)
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

--------------------------------------------------------------------------------
-- What the commands answer
--
-- Every line the addon says in chat is a whole sentence in plain words. It
-- names the skill, the icon and who decided, and it does not lean on the
-- addon's name in front of it to be its subject, as "Status Efficiency: on."
-- did.
--------------------------------------------------------------------------------

local SAID = "|cff66ccffStatus Efficiency|r: "

--- Types a command and returns what the addon answered, having checked that
--- it did answer, and that every line it began is a sentence: a capital letter
--- or a quoted name to begin with, and a full stop, or the colon before a
--- list, to end with.
local function Answer(w, command)
    w:slash(command)
    local text = w:drain()
    check(text:sub(1, #SAID) == SAID, "/se " .. command .. " answers in chat: " .. text)
    for line in text:gmatch("[^\n]+") do
        if line:sub(1, #SAID) == SAID then
            local words = line:sub(#SAID + 1)
            check(words:find("^[%u\"]"), "/se " .. command .. " begins like a sentence: " .. line)
            check(words:find("[%.:]$"), "/se " .. command .. " ends like one: " .. line)
        end
    end
    return text
end

--- Types a command that answers with one line, which has to be this.
local function Replies(w, command, sentence)
    eq(Answer(w, command), SAID .. sentence, "/se " .. command)
end

--- A world with a skill of every sort on the bars, and a boar targeted: a
--- debuff on one enemy, a skill that leaves nothing, a buff for the party, a
--- buff for you alone, a debuff on every enemy, and a debuff that stacks.
--- Mortal Strike is known to the game and on no button.
local function Talkative(options)
    local w = World(options)
    w:addButton("ActionButton1", 1, REND)
    w:addButton("ActionButton2", 2, HEROIC)
    w:addButton("ActionButton3", 3, SHOUT)
    w:addButton("ActionButton4", 4, BLOCK)
    w:addButton("ActionButton5", 5, CLAP)
    w:addButton("ActionButton6", 6, SUNDER)
    local ns = w:load(options and options.saved)
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:advance(0.3)
    w:drain()
    return w, ns, boar
end

test("every command answers in whole sentences", function()
    local w = Talkative()
    local commands = {
        "", "help", "off", "on", "when", "when sometimes", "when combat", "when always",
        "usable", "usable maybe", "usable off", "usable on",
        "track", "track nonsense", "track s", "track rend", "track battle", "track shield", "track thunder",
        "track mortal strike", "buff shield", "buff battle", "buff mortal strike", "debuff heroic", "debuff thunder",
        "debuff mortal strike", "ignore heroic", "auto heroic", "auto mortal strike", "aoe rend", "single rend",
        "single shield", "duration", "duration rend lots", "duration rend 1", "duration rend 18", "duration rend auto",
        "stacks", "stacks sunder lots", "stacks sunder 3", "stacks sunder 1", "stacks sunder auto",
        "anyone rend", "mine rend",
        "immune", "immune rend", "immune", "immune forget rend", "immune forget rend", "immune sunder",
        "immune forget", "immune forget",
        "size", "size 24", "size auto", "corner", "corner tr", "corner center",
        "icons", "icon", "icon green plus", "icon green none", "icon green default", "icon red 136243",
        "icon red nonsense", "icon red default",
        "log", "log", "plain", "plain", "list", "debug", "reset",
    }
    for i = 1, #commands do
        Answer(w, commands[i])
    end
    -- With no enemy targeted, and with a player.
    w:target(nil)
    Answer(w, "immune rend")
    Clean(w)
end)

test("/se track, buff and debuff say what the icon will check", function()
    local w, ns = Talkative()
    -- The three choices go by the names the settings give them: Always, Never and Auto.
    Replies(w, "track rend", "Rend is now on Always, so it has an icon. The icon checks the enemy you have targeted for "
        .. "its debuff. If Rend hits every enemy in the fight, type /se aoe Rend. If it gives you a buff instead, type "
        .. "/se buff Rend.")
    Replies(w, "track thunder", "Thunder Clap is now on Always, so it has an icon. The icon checks every enemy in the "
        .. "fight for its debuff. If Thunder Clap gives you a buff instead, type /se buff Thunder Clap.")
    Replies(w, "track shield", "Shield Block is now on Always, so it has an icon. The icon checks you for its buff. If "
        .. "Shield Block puts a debuff on enemies instead, type /se debuff Shield Block.")
    Replies(w, "track battle", "Battle Shout is now on Always, so it has an icon. The icon checks you, or the friend "
        .. "you have targeted, for its buff. If Battle Shout puts a debuff on enemies instead, type /se debuff Battle "
        .. "Shout.")
    -- A skill the game knows that is on no button: nothing to show yet.
    Replies(w, "track mortal strike", "Mortal Strike is now on Always, but it is not on your action bars right now. It "
        .. "will have an icon as soon as it is. If the addon then gets its effect wrong, type /se buff Mortal Strike "
        .. "for a buff on you, or /se debuff Mortal Strike for a debuff on enemies.")
    eq(ns.db.spells["Mortal Strike"].track, true, "the choice is kept for when it is")

    Replies(w, "buff shield", "Shield Block is now on Always, so it has an icon, and its effect is treated as a buff. "
        .. "The icon checks you for it.")
    Replies(w, "buff battle", "Battle Shout is now on Always, so it has an icon, and its effect is treated as a buff. "
        .. "The icon checks you, or the friend you have targeted, for it.")
    Replies(w, "buff mortal strike", "Mortal Strike is now on Always, and its effect is treated as a buff, but it is "
        .. "not on your action bars right now. It will have an icon as soon as it is.")
    Replies(w, "debuff heroic", "Heroic Strike is now on Always, so it has an icon, and its effect is treated as a "
        .. "debuff. The icon checks the enemy you have targeted for it. If Heroic Strike hits every enemy in the fight, "
        .. "type /se aoe Heroic Strike.")
    Replies(w, "debuff thunder", "Thunder Clap is now on Always, so it has an icon, and its effect is treated as a "
        .. "debuff. The icon checks every enemy in the fight for it. If Thunder Clap only hits your target, type /se "
        .. "single Thunder Clap.")
    Replies(w, "debuff mortal strike", "Mortal Strike is now on Always, and its effect is treated as a debuff on "
        .. "enemies, but it is not on your action bars right now. It will have an icon as soon as it is.")
    eq(ns.db.spells["Mortal Strike"].kind, "debuff")

    Replies(w, "track", "Which skill? Type its name after the command, as in /se track Thunder Clap.")
    Replies(w, "track s", "More than one skill on your action bars starts with \"s\". Type more of the name.")
    Clean(w)
end)

test("/se ignore, auto, aoe, single and duration say what they did", function()
    local w, ns = Talkative()
    Replies(w, "ignore heroic", "Heroic Strike is now on Never, so it has no icon. Type /se track Heroic Strike to "
        .. "give it one again.")
    eq(ns.db.spells["Heroic Strike"].track, false)
    Replies(w, "auto heroic", "Heroic Strike is back on Auto, so the addon decides everything about it by itself "
        .. "again. Your own choices for it are cleared, and so is what the addon had learned about it.")
    eq(ns.db.spells["Heroic Strike"], nil)
    Replies(w, "aoe rend", "The icon for Rend now checks every enemy in the fight.")
    Replies(w, "single rend", "The icon for Rend now checks only the enemy you have targeted.")
    Replies(w, "aoe shield", "The effect of Shield Block is treated as a buff, so this changes nothing for now. It would "
        .. "only matter if you made it a debuff with /se debuff Shield Block.")

    Replies(w, "duration", "Type the skill's name and then how long its effect lasts in seconds. For example: /se "
        .. "duration Thunder Clap 30, or /se duration Thunder Clap auto to let the addon work it out.")
    Replies(w, "duration rend lots", "Type how long the effect lasts in seconds, from 1 to 3600, or type auto to let the "
        .. "addon work it out.")
    Replies(w, "duration rend 0", "Type how long the effect lasts in seconds, from 1 to 3600, or type auto to let the "
        .. "addon work it out.")
    eq(ns.db.spells.Rend.duration, nil, "neither of which set anything")
    Replies(w, "duration rend 1", "The effect of Rend is now set to last 1 second.")
    Replies(w, "duration rend 18", "The effect of Rend is now set to last 18 seconds.")
    eq(ns.db.spells.Rend.duration, 18)
    Replies(w, "duration rend auto", "The addon works out by itself again how long the effect of Rend lasts.")
    eq(ns.db.spells.Rend.duration, nil)

    -- Clearing a list of immune enemies that holds nothing says so, and does not speak of none as "0 kinds".
    Replies(w, "immune forget rend", "No enemy was on the list as immune to Rend.")
    Replies(w, "immune forget", "The list of immune enemies was already empty.")
    Clean(w)
end)

test("/se off, size, corner, icons, log, plain and reset say what they did", function()
    local w, ns = Talkative()
    Replies(w, "off", "The icons are off. Type /se on to turn them back on.")
    Replies(w, "on", "The icons are on. They appear always, and only on skills you can use right now.")
    Replies(w, "size 24", "The icon size is now 24 pixels.")
    Replies(w, "size auto", "The icon size follows the size of the button again.")
    Replies(w, "corner tr", "The icons have moved to the top right of each button.")
    Replies(w, "corner center", "The icons have moved to the middle of each button.")
    Replies(w, "corner nowhere", "Type where the icon goes on the button: tl, top, tr, left, center, right, bl, bottom or "
        .. "br. For example: /se corner tr puts it at the top right.")
    eq(ns.db.corner, "CENTER", "which moved nothing")

    local icons = Answer(w, "icons")
    check(icons:find(SAID .. "These are the icons you can pick with /se icon <green | yellow | red> <name>:\n", 1, true),
        icons)
    check(icons:find("\n  In place of a name you can type the file ID of a picture such as 136243, its path such as\n"
        .. "  Interface\\Icons\\INV_Misc_QuestionMark, none for no icon at all, or default for the usual one.\n", 1, true),
        icons)
    check(icons:find("\n  What the three results show now:\n    Worth casting: check\n    Partly worth casting: partial\n"
        .. "    No need to cast: cross", 1, true), "and what is picked now: " .. icons)
    Replies(w, "icon", "Type which result, green, yellow or red, and then the icon for it. For example: /se icon green "
        .. "plus, or /se icon green default for the usual one. /se icons lists the names.")
    Replies(w, "icon green plus", "\"Worth casting\" now shows the green plus.")
    eq(ns.db.icons.none, "plus", "the example in that line is one that works")
    Replies(w, "icon green default", "\"Worth casting\" is back to its usual icon.")
    -- A picture of your own goes by the name the Icons tab gives it.
    Replies(w, "icon red 136243", "\"No need to cast\" now shows your own picture, 136243.")
    Replies(w, "icon red nonsense", "\"nonsense\" is not an icon name, and not the file ID or the path of a picture the "
        .. "game knows. /se icons lists the names.")
    eq(ns.db.icons.all, "custom", "which changed nothing")
    Replies(w, "icon red default", "\"No need to cast\" is back to its usual icon.")
    -- The way back is given in the words the command takes: not by the name the code has for a result.
    Replies(w, "icon yellow none", "\"Partly worth casting\" now shows no icon. Type /se icon yellow default to bring "
        .. "its icon back.")
    Replies(w, "icon green none", "\"Worth casting\" now shows no icon. Type /se icon green default to bring its icon "
        .. "back.")
    Replies(w, "icon green default", "\"Worth casting\" is back to its usual icon.")
    Replies(w, "icon yellow default", "\"Partly worth casting\" is back to its usual icon.")

    Replies(w, "log", "The log is on: the addon now says in chat what it notices. Type /se log again to turn it off.")
    Replies(w, "log", "The log is off.")
    Replies(w, "plain", "The settings window will draw its own buttons and sliders. Type /reload to see it. Type /se "
        .. "plain again to go back to the game's own.")
    Replies(w, "plain", "The settings window will use the game's own buttons and sliders again, wherever they work. Type "
        .. "/reload to see it.")
    Replies(w, "reset", "Every setting is back to how it started, and everything the addon had learned is cleared.")
    Clean(w)
end)

test("/se list says of every skill what its icon is for, or why it has none", function()
    local w = Talkative()
    w:slash("ignore heroic")
    w:drain()
    local list = Answer(w, "list")
    check(list:find(SAID .. "The skills on your action bars:\n", 1, true), list)
    check(list:find("\n  |cff40d040Thunder Clap|r puts a debuff that lasts 30 seconds on every enemy in the fight. It has "
        .. "an icon because it is a well-known debuff that hits every enemy around you.", 1, true), list)
    check(list:find("\n  |cff40d040Shield Block|r gives you a buff that lasts 10 seconds. It has an icon because its "
        .. "tooltip describes a buff that lasts for a while.", 1, true), list)
    check(list:find("\n  |cff999999Heroic Strike|r is on Never, so it has no icon.", 1, true), list)
    check(not list:find("other skill", 1, true), "every skill on these bars has been spoken for: " .. list)
    -- A length of time is written out: seconds below two minutes, minutes from there, and no figure from an hour on.
    for _, length in ipairs({ { 1, "1 second" }, { 119, "119 seconds" }, { 120, "2 minutes" }, { 3599, "60 minutes" },
        { 3600, "an hour or more" } }) do
        w:slash("duration rend " .. length[1])
        w:drain()
        local again = Answer(w, "list")
        check(again:find("Rend|r puts a debuff that lasts " .. length[2] .. " on your target.", 1, true),
            length[1] .. " seconds: " .. again)
    end
    -- Every line of it is a sentence.
    for line in list:gmatch("[^\n]+") do
        check(line:sub(1, #SAID) == SAID or line:find("^  |cff%x%x%x%x%x%x%u.*%.$"), line)
    end
    Clean(w)

    -- Skills that leave nothing behind are counted, not listed.
    local quiet = Bar(nil, HEROIC, PROWL)
    eq(Answer(quiet, "list"), SAID .. "The skills on your action bars:\n  2 other skills have no icon because they do "
        .. "not seem to leave a buff or a debuff behind. To give one of them an icon anyway, type /se track <skill>, or "
        .. "/se buff <skill> if its effect is a buff on you. The Skills tab of /se options does the same with clicks.")
    Clean(quiet)

    local bare = Bar(nil)
    Replies(bare, "list", "No skills were found on your action bars yet.")
    Clean(bare)
end)

test("a command that fails says so in a sentence, and nothing reaches the game", function()
    local w, ns = Simple()
    ns.Options.RefreshAll = function()
        error("simulated bug")
    end
    w:drain()
    w:slash("on")
    local said = w:drain()
    check(said:find(SAID .. "That command ran into a problem: ", 1, true), said)
    check(said:find("simulated bug", 1, true), "with what went wrong: " .. said)
    eq(#w.errors, 0, "nothing reaches the client's error handler")
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

test("nothing is said in chat when the addon loads", function()
    -- A first login with nothing saved.
    local w = World()
    w:addButton("ActionButton1", 1, REND)
    w:addButton("ActionButton2", 2, HEROIC)
    w:addButton("ActionButton3", 3, SHOUT)
    w:install()
    w:advance(2)
    eq(w:drain(), "", "chat after a first login")
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:advance(0.3)
    w:cast(REND)
    w:advance(1)
    eq(w:icon("ActionButton1"), "cross", "and it is at work all the same")
    eq(w:drain(), "", "chat after the first cast")

    -- A later login, with what that session saved.
    local saved = w.env.StatusEfficiencyDB
    local w2 = World()
    w2:addButton("ActionButton1", 1, REND)
    w2:addButton("ActionButton2", 2, HEROIC)
    w2:addButton("ActionButton3", 3, SHOUT)
    local ns2 = w2:load(saved)
    w2:advance(2)
    eq(w2:drain(), "", "chat after a later login")

    -- The first login after an update, with settings an earlier version saved.
    local w3 = World()
    w3:addButton("ActionButton1", 1, REND)
    w3:addButton("ActionButton2", 2, HEROIC)
    local ns3 = w3:load({ version = 1, learned = {
        Rend = { exact = true, casts = 27, hits = 22, duration = 21 },
        ["Heroic Strike"] = { casts = 9, hits = 8 },
    } })
    w3:advance(2)
    eq(ns3.db.version, 2, "the settings were brought up to date")
    eq(w3:drain(), "", "chat after the first login with a new version")

    -- The version is there for the asking.
    w2:slash("")
    local help = w2:drain()
    check(help:find("Version " .. ns2.VERSION .. ".", 1, true), "/se gives the version: " .. help)
    Clean(w)
    Clean(w2)
    Clean(w3)
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

test("a new install shows the icons only during a fight, yours or your group's", function()
    local w = World()
    w:addButton("ActionButton1", 1, REND)
    w:addButton("ActionButton2", 2, HEROIC)
    w:addButton("ActionButton3", 3, SHOUT)
    local ns = w:install()
    eq(ns.db.appear, "group", "the default")
    eq(w:icon("ActionButton1"), nil, "Rend with nothing targeted")
    eq(w:icon("ActionButton3"), nil, "Battle Shout waits for a fight too")

    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "an enemy is targeted, but there is no fight yet")
    eq(w:icon("ActionButton3"), nil)

    w:cast(REND)
    w:advance(0.5)
    eq(w.combat, true, "the first blow starts the fight")
    eq(w:icon("ActionButton1"), "cross", "Rend is on the boar")
    eq(w:icon("ActionButton2"), nil, "Heroic Strike applies nothing")
    eq(w:icon("ActionButton3"), "check", "Battle Shout, now that you are fighting")

    local guard = w:addMob("Guard", { hostile = false })
    w:target(guard)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "a friend is not an enemy: nobody you have picked has Rend")
    eq(w:icon("ActionButton3"), "check", "and the fight keeps the icons on")

    w:kill(boar)
    w:leaveCombat()
    w:target(boar)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "the fight is over")
    eq(w:icon("ActionButton3"), nil)

    -- Someone in your party picks a fight close by.
    local healer = w:addPartyMember("Healer", { engaged = true })
    w:advance(0.3)
    eq(w.combat, false, "you are not in combat yourself")
    eq(w:icon("ActionButton3"), "check", "their fight brings the icons up as well")
    healer.engaged = false
    w:advance(0.3)
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

    -- You walk away from the fight and let go of the boar.
    w:leaveCombat()
    w:target(nil)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "no enemy targeted and no fight, no icons")
    eq(w:icon("ActionButton2"), nil)
    w:cast(BLOCK)
    w:advance(0.5)
    eq(w:icon("ActionButton2"), nil, "still none")

    w:target(boar)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "an enemy alone does not bring them back")
    w:enterCombat()
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
    check(w:drain():find("The icons now appear always.", 1, true), "it says so")
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

test("/se when combat shows the icons only while you are in combat yourself", function()
    local w, ns = Simple({ combatAuras = "ids" })
    w:drain()
    w:slash("when combat")
    check(w:drain():find("The icons now appear when you are in combat.", 1, true), "it says so")
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
    eq(w:icon("ActionButton1"), "check", "nobody to judge Rend on, in the middle of a fight")
    eq(w:icon("ActionButton3"), "check", "the buff does not need an enemy")

    w:leaveCombat()
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "the fight is over")
    eq(w:icon("ActionButton3"), nil)

    -- A fight that is somebody else's does not count.
    w:addPartyMember("Healer", { engaged = true })
    w:advance(0.3)
    eq(ns.GroupState(), "fighting", "someone in your party is fighting close by")
    eq(w:icon("ActionButton1"), nil, "but you are not")
    eq(w:icon("ActionButton3"), nil)
    Clean(w)
end)

--------------------------------------------------------------------------------
-- Through a fight
--
-- A fight keeps the icons on from its first moment to its last, whatever is
-- targeted: your own fight, and where the setting says so, one that someone
-- in your party or raid is in close by.
--------------------------------------------------------------------------------

test("fight: the icons stay on when your target dies in the middle of a fight", function()
    local w = World()
    w:addButton("ActionButton1", 1, REND)
    w:addButton("ActionButton2", 2, HEROIC)
    w:addButton("ActionButton3", 3, SHOUT)
    w:addButton("ActionButton4", 4, CLAP)
    local ns = w:install()
    eq(ns.db.appear, "group", "the default: icons while you or your group are in combat")
    local boar, wolf = w:addMob("Boar"), w:addMob("Wolf")
    w:showPlate(boar)
    w:showPlate(wolf)
    w:target(boar)
    w:advance(0.3)
    w:cast(REND)
    wolf.engaged = true -- the wolf joins in
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross", "Rend is on the boar")
    eq(w:icon("ActionButton3"), "check")

    -- The boar dies. Its corpse stays targeted, and the wolf fights on.
    w:kill(boar)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "Rend: nobody you have picked has it")
    eq(w:icon("ActionButton2"), nil, "Heroic Strike still applies nothing")
    eq(w:icon("ActionButton3"), "check", "Battle Shout stays where it was")
    eq(w:icon("ActionButton4"), "check", "Thunder Clap is judged on the wolf")

    -- Letting go of the corpse changes nothing.
    w:target(nil)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check")
    eq(w:icon("ActionButton3"), "check")

    -- The next enemy is judged for what it carries.
    w:target(wolf)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "the wolf has no Rend")
    w:cast(REND)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross", "now it has")

    -- The wolf dies and the fight is over: nothing targeted, nothing shown.
    w:kill(wolf)
    w:leaveCombat()
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "no fight and no enemy")
    eq(w:icon("ActionButton3"), nil)
    eq(w:icon("ActionButton4"), nil)
    Clean(w)
end)

test("fight: someone in your party fighting close by keeps the icons on", function()
    local w = World()
    w:addButton("ActionButton1", 1, REND)
    w:addButton("ActionButton3", 3, SHOUT)
    local ns = w:install()
    local healer = w:addPartyMember("Healer")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "nobody is fighting and nothing is targeted")
    eq(w:icon("ActionButton3"), nil)

    healer.engaged = true
    w:advance(0.3)
    eq(w.combat, false, "you are not in combat yourself")
    eq(w:icon("ActionButton1"), "check", "Rend, with nobody to judge it on yet")
    eq(w:icon("ActionButton3"), "check", "Battle Shout, which you do not have")

    healer.distance = 300
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "a fight far away is not yours")
    eq(w:icon("ActionButton3"), nil)

    healer.distance = 60
    w:advance(0.3)
    eq(w:icon("ActionButton3"), "check", "sixty yards is close by: the game still shows them to you")

    healer.engaged = false
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "their fight is over")
    eq(w:icon("ActionButton3"), nil)

    -- What the game said of the group is kept for troubleshooting: how often
    -- the answer turned to each word.
    local group = ns.db.report.group
    eq(group.alone, 1, "before anyone joined")
    eq(group.quiet, 2)
    eq(group.fighting, 2)
    eq(group.far, 1)
    eq(group.unsaid, nil)
    Clean(w)
end)

test("fight: a fight of someone in your group counts where the setting says so, and only there", function()
    local w = World()
    w:addButton("ActionButton1", 1, REND)
    w:addButton("ActionButton3", 3, SHOUT)
    local ns = w:load({ appear = "group" })
    local tank = w:addPartyMember("Tank", { engaged = true })
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:advance(0.3)
    eq(w.combat, false, "you are not in combat yourself")
    eq(w:icon("ActionButton1"), "check", "nobody picked yet")
    eq(w:icon("ActionButton3"), "check")

    w:target(boar)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "the boar has no Rend")
    w:applyAura(boar, "Rend", 21, true)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "and now it has: an enemy you picked is judged for what it carries")

    -- Set to your own combat only, the tank's fight is not enough.
    w:slash("when combat")
    w:advance(0.3)
    eq(ns.db.appear, "combat")
    eq(ns.GroupState(), "fighting")
    eq(w:icon("ActionButton1"), nil, "the tank is fighting and you are not")
    eq(w:icon("ActionButton3"), nil)
    w:enterCombat()
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "your own fight brings them up")
    eq(w:icon("ActionButton3"), "check")
    w:leaveCombat()
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "and they go when it ends, though the tank fights on")
    eq(w:icon("ActionButton3"), nil)

    w:slash("when group")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "back to counting the tank's fight")
    eq(w:icon("ActionButton3"), "check")
    tank.engaged = false
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "nobody is fighting any more")
    eq(w:icon("ActionButton3"), nil)
    Clean(w)
end)

test("fight: in a raid, someone fighting close by counts and your own name does not", function()
    local w = World({ raid = true })
    w:addButton("ActionButton1", 1, REND)
    w:addButton("ActionButton3", 3, SHOUT)
    local ns = w:install()
    local mage = w:addPartyMember("Mage")
    eq(mage.token, "raid2", "raid1 is you")
    w:advance(0.3)
    eq(w:icon("ActionButton3"), nil)

    -- Your own fight shows under your raid name too. It is yours all the same.
    local boar = w:addMob("Boar")
    w:target(boar)
    w:advance(0.3)
    w:cast(REND)
    w:advance(0.5)
    eq(w:icon("ActionButton3"), "check", "your fight keeps the icons on")
    eq(ns.GroupState(), "quiet", "and is not taken for somebody else's")
    w:kill(boar)
    w:leaveCombat()
    w:target(nil)
    w:advance(0.3)
    eq(w:icon("ActionButton3"), nil)

    mage.engaged = true
    w:advance(0.3)
    eq(ns.GroupState(), "fighting")
    eq(w:icon("ActionButton1"), "check", "the mage's fight keeps them on")
    eq(w:icon("ActionButton3"), "check")
    eq(ns.db.report.group.fighting, 1, "counted once, for the mage")
    Clean(w)
end)

test("fight: a client that will not say what your group is doing leaves it at your own fight", function()
    local w = World({ groupFlags = "secret" })
    w:addButton("ActionButton1", 1, REND)
    w:addButton("ActionButton3", 3, SHOUT)
    local ns = w:install()
    w:addPartyMember("Healer", { engaged = true })
    w:advance(0.3)
    eq(ns.GroupState(), "unsaid")
    eq(w:icon("ActionButton3"), nil, "nothing is made of what cannot be read")

    local boar = w:addMob("Boar")
    w:target(boar)
    w:advance(0.3)
    w:cast(REND)
    w:advance(0.5)
    w:kill(boar)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "your own fight still keeps the icons on")
    eq(w:icon("ActionButton3"), "check")
    eq(ns.db.report.group.unsaid, 1, "and the saved report says what the client kept back")
    Clean(w)

    -- Kept back only whether they are in combat: being close by is not enough.
    w = World({ groupFlags = "combat" })
    w:addButton("ActionButton3", 3, SHOUT)
    ns = w:install()
    w:addPartyMember("Healer", { engaged = true })
    w:advance(0.3)
    eq(ns.GroupState(), "unsaid", "nobody is taken to be fighting on no word of the game's")
    eq(w:icon("ActionButton3"), nil)
    Clean(w)
end)

test("fight: where the game will not say whether it shows someone to you, its range test is asked", function()
    local w = World({ noVisible = true })
    w:addButton("ActionButton1", 1, REND)
    w:addButton("ActionButton3", 3, SHOUT)
    local ns = w:install()
    local healer = w:addPartyMember("Healer", { engaged = true, distance = 30 })
    w:advance(0.3)
    eq(ns.GroupState(), "fighting", "thirty yards is in range")
    eq(w:icon("ActionButton3"), "check")
    healer.distance = 60
    w:advance(0.3)
    eq(ns.GroupState(), "far", "sixty is not")
    eq(w:icon("ActionButton3"), nil)

    -- A test the game did not make says nothing, whatever comes with it.
    healer.unchecked = true
    w:advance(0.3)
    eq(ns.GroupState(), "unsaid", "not far: unknown")
    eq(w:icon("ActionButton3"), nil)
    healer.unchecked = nil

    -- In a fight of your own that test answers with secret values. By then
    -- the answer no longer matters: your fight keeps the icons on by itself.
    healer.distance = 30
    local boar = w:addMob("Boar")
    w:target(boar)
    w:advance(0.3)
    w:cast(REND)
    w:advance(0.5)
    eq(ns.GroupState(), "unsaid")
    eq(w:icon("ActionButton3"), "check")
    Clean(w)
end)

test("fight: with nobody to go to, a skill's reach is asked of no one", function()
    -- A client that calls whatever is targeted out of reach, a corpse included,
    -- must not take the icon away with it.
    local w = World()
    w:addButton("ActionButton1", 1, REND)
    local ns = w:install()
    eq(ns.db.usableOnly, true, "the default: an icon only on a skill that can be used")
    local boar, wolf = w:addMob("Boar"), w:addMob("Wolf")
    w:showPlate(boar)
    w:showPlate(wolf)
    w:target(boar)
    w:advance(0.3)
    w:cast(REND)
    wolf.engaged = true
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross")

    w:kill(boar)
    w:setRange(1, false)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "the corpse is out of reach, and nobody asked")

    w:target(wolf)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "a living enemy out of reach hides it as before")
    w:setRange(1, true)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check")
    Clean(w)
end)

test("fight: set to always, a debuff with nobody to judge it on shows the green check only during a fight", function()
    local w = World()
    w:addButton("ActionButton1", 1, REND)
    w:addButton("ActionButton4", 4, CLAP)
    local ns = w:load()
    eq(ns.db.appear, "always")
    eq(w:icon("ActionButton1"), nil, "out of a fight there is nobody to judge Rend on")
    eq(w:icon("ActionButton4"), nil, "nor Thunder Clap")

    local boar = w:addMob("Boar")
    w:target(boar)
    w:advance(0.3)
    w:cast(REND)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross")
    w:kill(boar)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "in the middle of a fight")
    eq(w:icon("ActionButton4"), "check", "and an area debuff with no enemy in sight likewise")

    w:leaveCombat()
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "and not after it")
    eq(w:icon("ActionButton4"), nil)
    Clean(w)
end)

test("fight: /se debug says what your group is doing", function()
    local w = World()
    w:addButton("ActionButton1", 1, REND)
    w:install()
    w:drain()
    w:slash("debug")
    local debug = w:drain()
    check(debug:find("Your group: you are in no party or raid.", 1, true), "alone: " .. debug)

    local healer = w:addPartyMember("Healer")
    w:slash("debug")
    debug = w:drain()
    check(debug:find("Your group: nobody in it is in combat.", 1, true), "quiet: " .. debug)

    healer.engaged = true
    w:slash("debug")
    debug = w:drain()
    check(debug:find("Your group: someone close by is in combat, which keeps the icons on like a fight of your own.",
        1, true), "fighting: " .. debug)

    -- What their fight does for the icons goes by the setting.
    w:slash("when combat")
    w:slash("debug")
    debug = w:drain()
    check(debug:find("Your group: someone close by is in combat, which does not bring the icons up", 1, true),
        "fighting, with the icons set to your own combat: " .. debug)
    w:slash("when always")
    w:slash("debug")
    debug = w:drain()
    check(debug:find("Your group: someone close by is in combat.", 1, true),
        "fighting, with the icons always on: " .. debug)
    w:slash("when group")
    w:drain()

    healer.distance = 300
    w:slash("debug")
    debug = w:drain()
    check(debug:find("Your group: someone in it is in combat, but nobody close by.", 1, true), "far: " .. debug)
    Clean(w)
end)

--------------------------------------------------------------------------------
-- Stacks
--
-- An effect that stacks is worth casting again until the last stack is on: the
-- green check until then, the red X only then. Out of a fight the stacks are
-- read off the unit. In a fight they are counted, one for each cast that is
-- seen to land.
--------------------------------------------------------------------------------

--- A world with Sunder Armor and Rend on the first two buttons, a boar
--- targeted with its nameplate showing, and reports known to arrive.
local function Sundering(options)
    options = options or {}
    options.saved = options.saved or Proven()
    local w, ns = Bar(options, SUNDER, REND)
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:advance(0.3)
    return w, ns, boar
end

--- How many times over the addon takes a spell's effect to be on your target.
local function Stacks(ns, name)
    return ns.Tracker:Stacks(ns.KeyOf("target", "debuff"), name, ns.Now())
end

--- What the addon has on its books for an effect by this name, as /se debug
--- lists it: { key, name, how, stacks, left }.
local function Booked(ns, name)
    for _, effect in ipairs(ns.Tracker:Describe(ns.Now())) do
        if effect.name == name then
            return effect
        end
    end
    return nil
end

-- How Sunder Armor behaves, for an effect put on a unit by hand.
local SUNDERED = { shared = true, stacks = 5 }

--- A world with the given spells on the first buttons, a boar targeted with
--- its nameplate showing, a second warrior in the party who has the boar
--- targeted too, and reports known to arrive.
local function Party(options, ...)
    options = options or {}
    options.saved = options.saved or Proven()
    local w, ns = Bar(options, ...)
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    local warrior = w:addPartyMember("Warrior", { target = boar })
    w:advance(0.3)
    return w, ns, boar, warrior
end

--- Starts the fight without leaving anything on the boar.
local function Open(w)
    w:cast(REND, { miss = true })
    w:advance(2)
end

test("stacks: a skill whose effect stacks shows the green check until the last stack is on", function()
    local w, ns = Sundering()
    eq(w:icon("ActionButton1"), "check", "no Sunder Armor on the boar yet")
    w:cast(SUNDER)
    w:advance(1.5)
    eq(w:icon("ActionButton1"), "check", "one of five: another one still does something")
    eq(Stacks(ns, "Sunder Armor"), 1)
    eq(w:icon("ActionButton2"), "check", "Rend has nothing to do with it")
    w:cast(SUNDER)
    w:advance(1.5)
    w:cast(SUNDER, { miss = true })
    w:advance(1.5)
    eq(Stacks(ns, "Sunder Armor"), 2, "a cast that missed adds no stack")
    for stack = 3, 4 do
        w:cast(SUNDER)
        w:advance(1.5)
        eq(w:icon("ActionButton1"), "check", stack .. " of five")
        eq(Stacks(ns, "Sunder Armor"), stack)
    end
    w:cast(SUNDER)
    w:advance(1.5)
    eq(w:icon("ActionButton1"), "cross", "five of five: nothing left to add")
    w:cast(SUNDER)
    w:advance(1.5)
    eq(w:icon("ActionButton1"), "cross", "and one more leaves it there")
    eq(Stacks(ns, "Sunder Armor"), 5, "never more than it goes")
    w:advance(27)
    eq(w:icon("ActionButton1"), "cross", "28 seconds after the last one")
    w:advance(3)
    eq(w:icon("ActionButton1"), "check", "the stacks ran out together")
    eq(Stacks(ns, "Sunder Armor"), 0)

    w:cast(SUNDER)
    w:advance(1.5)
    eq(w:icon("ActionButton1"), "check", "and the count starts over")
    eq(Stacks(ns, "Sunder Armor"), 1)
    Clean(w)
end)

test("stacks: out of a fight the stacks are read off the enemy, and counted on from there", function()
    local w, ns, boar = Sundering()
    w:applyAura(boar, "Sunder Armor", 30, true, nil, nil, SUNDERED)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "one stack")
    eq(Stacks(ns, "Sunder Armor"), 1)
    eq((ns.db.learned["Sunder Armor"] or {}).stacks, nil, "once on a unit is no sign of an effect that stacks")
    w:applyAura(boar, "Sunder Armor", 30, true, nil, nil, SUNDERED)
    w:applyAura(boar, "Sunder Armor", 30, true, nil, nil, SUNDERED)
    w:advance(0.3)
    eq(Stacks(ns, "Sunder Armor"), 3, "read, not counted: nothing was cast")
    eq(w:icon("ActionButton1"), "check")
    eq(ns.db.learned["Sunder Armor"].stacks, 3, "three times over is, and is kept as the most it was seen to go")

    w:cast(SUNDER) -- the fight starts: from here on a stack is a cast that landed
    w:advance(1.5)
    eq(Stacks(ns, "Sunder Armor"), 4)
    eq(w:icon("ActionButton1"), "check")
    w:cast(SUNDER)
    w:advance(1.5)
    eq(w:icon("ActionButton1"), "cross", "five, three of them read and two counted")

    -- After the fight what is read replaces what was counted.
    w:leaveCombat()
    w:removeAura(boar, "Sunder Armor")
    w:applyAura(boar, "Sunder Armor", 30, true, nil, nil, SUNDERED)
    w:advance(0.3)
    eq(Stacks(ns, "Sunder Armor"), 1)
    eq(w:icon("ActionButton1"), "check")
    Clean(w)
end)

test("stacks: a landing that only renewed the effect found it there, and one that added it found none", function()
    local w, ns, boar = Sundering()
    w:cast(REND)
    w:advance(1)
    -- Another warrior's Sunder Armor, three times over, in the middle of the
    -- fight. Nothing tells the addon whose effect it was that changed.
    for _ = 1, 3 do
        w:applyAura(boar, "Sunder Armor", 30, false, nil, nil, SUNDERED)
        w:advance(1)
    end
    eq(w:icon("ActionButton1"), "check", "nothing is known of theirs")

    w:cast(SUNDER)
    w:advance(1.5)
    eq(w:icon("ActionButton1"), "check")
    if KindsTold() then
        eq(Stacks(ns, "Sunder Armor"), 2, "the report renewed an effect and added none: it was there, so two at least")
    else
        eq(Stacks(ns, "Sunder Armor"), 1, "nothing to tell it from a first stack")
    end
    w:cast(SUNDER)
    w:advance(1.5)
    eq(w:icon("ActionButton1"), "check", "counted low rather than high: five are on it, and it could be fewer")

    -- The effect is taken off the boar, which only shows as an effect going.
    -- The next cast puts it on afresh.
    w:removeAura(boar, "Sunder Armor")
    w:advance(1)
    w:cast(SUNDER)
    w:advance(1.5)
    if KindsTold() then
        eq(Stacks(ns, "Sunder Armor"), 1, "the report only added an effect: there was none, whatever the books said")
    else
        check(Stacks(ns, "Sunder Armor") > 1, "nothing to tell it from one more stack")
    end
    eq(w:icon("ActionButton1"), "check")
    Clean(w)
end)

test("stacks: a buff that stacks is counted the same way", function()
    local w, ns = Bar({ saved = Proven() }, FRENZY, BLOCK)
    eq(w:icon("ActionButton1"), "check")
    w:cast(FRENZY)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "check", "one of three, read off you")
    eq(ns.Tracker:Stacks(ns.KeyOf("player", "buff"), "Battle Frenzy", ns.Now()), 1)
    w:cast(BLOCK)
    w:advance(0.5)
    eq(w:icon("ActionButton2"), "cross", "a buff that does not stack is there or not")

    local boar = w:addMob("Boar")
    w:target(boar)
    w:enterCombat()
    w:advance(0.3)
    w:cast(FRENZY)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "check", "two of three, counted in the fight")
    eq(ns.Tracker:Stacks(ns.KeyOf("player", "buff"), "Battle Frenzy", ns.Now()), 2)
    w:cast(FRENZY)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross", "three of three")
    w:advance(16)
    eq(w:icon("ActionButton1"), "check", "and gone")
    Clean(w)
end)

test("stacks, area: the half circle when some enemies carry every stack, the red X when all do", function()
    local w, ns = Bar({ saved = Proven() }, ROAR)
    local mobs = {}
    for i = 1, 2 do
        mobs[i] = w:addMob("Kobold " .. i)
        w:showPlate(mobs[i])
    end
    w:target(mobs[1])
    w:advance(0.5)
    w:cast(ROAR, { hits = mobs })
    w:advance(1.5)
    eq(w:icon("ActionButton1"), "check", "one of two on each of them: room for another on both")
    w:cast(ROAR, { hits = { mobs[1] } })
    w:advance(1.5)
    eq(w:icon("ActionButton1"), "partial", "full on one, and one short on the other: some are full")
    w:cast(ROAR, { hits = { mobs[2] } })
    w:advance(1.5)
    eq(w:icon("ActionButton1"), "cross", "full on both")
    Clean(w)
end)

test("stacks: a client that does not say how many times an effect is on a unit leaves it at what was counted", function()
    local w, ns, boar = Sundering({ noApplications = true })
    for _ = 1, 3 do
        w:applyAura(boar, "Sunder Armor", 30, true, nil, nil, SUNDERED)
    end
    w:advance(0.3)
    eq(Stacks(ns, "Sunder Armor"), 1, "there, and nothing says how often")
    eq(w:icon("ActionButton1"), "check")
    w:cast(SUNDER, { quiet = true })
    w:advance(0.5)
    eq(Stacks(ns, "Sunder Armor"), 2, "a cast seen to land is still counted")
    Clean(w)
end)

test("stacks: how often an effect stacks is read from the tooltip by the words around the number", function()
    local w, ns = Bar(nil, REND)
    local read = ns.Spells.ParseStacks
    local cases = {
        { "Sunders the target's armor. Can be applied up to 5 times. Lasts 30 sec.", 5, "can be applied up to 5 times" },
        { "Burns the enemy for 10 Fire damage. Stacks up to 5 times. Lasts 12 sec.", 5 },
        { "Reduces armor by 5% for 20 sec, stacking up to 3 times.", 3 },
        { "Increases your attack speed by 10% for 15 sec. This effect stacks up to 3 times.", 3 },
        { "Increases damage taken by 2%. Up to 4 stacks.", 4, "up to 4 stacks" },
        { "Stuns the target for 4 sec. Max 2 stacks.", 2 },
        { "Poisons the target. Maximum of 5 applications.", 5 },
        { "Increases damage by 3. Stacks to 10.", 10 },
        { "|cffffffffRends|r the target. Can be applied|nup to 5 times.", 5 },
        -- Numbers that count something else.
        { "Strikes the target up to 3 times for 20 damage.", nil },
        { "Fires 5 times in 1.5 sec.", nil },
        { "Applies a slow for 8 sec. Hits 3 times.", nil },
        { "Reduces the melee attack power of all enemies within 10 yards by 86 for 45 sec.", nil },
        { "Can be applied up to 1 times.", nil }, -- once is not stacking
        { "Stacks up to 2.5 times.", nil },
        { "", nil },
    }
    for i = 1, #cases do
        local text, most, words = cases[i][1], cases[i][2], cases[i][3]
        local got, from = read(text)
        eq(got, most, "stacks in \"" .. text .. "\"")
        if words then
            eq(from, words, "the words they were read from")
        end
    end
    eq(read(nil), nil, "no text at all")

    -- And whose effect it is: one that works bit by bit is each caster's own.
    local own = ns.Spells.ParseOwn
    eq(own("Wounds the target causing them to bleed for 66 damage over 18 sec."), "over 18 sec")
    eq(own("Poisons the enemy for 13 Nature damage every 3 sec for 12 sec."), "every 3 sec")
    eq(own("Deals 5 damage per sec for 10 sec."), "per sec")
    eq(own("Causes damage over time."), "damage over")
    eq(own("Heals the target for 300 over 15 sec."), "over 15 sec")
    eq(own("A mocking attack that forces the target to focus attacks on you for 6 sec."), "attacks on you")
    eq(own("Taunts the target to attack you."), "attack you")
    eq(own("Reduces the melee attack power of all enemies within 10 yards by 86 for 45 sec."), nil)
    eq(own("Sunders the target's armor, reducing it by 180 per Sunder Armor. Can be applied up to 5 times."), nil)
    eq(own("Increases the attack power of all party members by 35. Lasts 3 min."), nil)
    eq(own("Knocks the enemy over 9 yards away and stuns it for 2 sec."), nil, "a distance is not a time")
    eq(own(""), nil)
    eq(own(nil), nil)
    Clean(w)
end)

-- A skill whose tooltip says nothing of how often its effect stacks, though
-- the game's own data has it at five times.
local CORRODE = 134

--- A world with Corrode and Rend on the first two buttons, a boar targeted
--- with its nameplate showing, and reports known to arrive. `fighting` has
--- you in combat before the addon loads, as after a /reload in a fight.
local function Corroding(options, fighting)
    options = options or {}
    options.saved = options.saved or Proven()
    local w = World(options)
    w:addSpell(CORRODE, {
        name = "Corrode", harmful = true, cumulative = 5,
        description = "Eats into the target's armor, reducing it by 90. Lasts 30 sec.",
        effect = { duration = 30, shared = true, stacks = 5 },
    })
    w:addButton("ActionButton1", 1, CORRODE)
    w:addButton("ActionButton2", 2, REND)
    if fighting then
        w:enterCombat()
    end
    local ns = w:load(options.saved)
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:advance(0.3)
    return w, ns, boar
end

test("stacks: the game itself is asked how often an effect stacks, for a tooltip that does not say", function()
    local w, ns = Corroding()
    eq(ns.Spells.ParseStacks("Eats into the target's armor, reducing it by 90. Lasts 30 sec."), nil,
        "nothing in the tooltip says it stacks")
    eq(w:icon("ActionButton1"), "check")
    for stack = 1, 4 do
        w:cast(CORRODE)
        w:advance(1.5)
        eq(w:icon("ActionButton1"), "check", stack .. " of the five the game's own data gives it")
        eq(Stacks(ns, "Corrode"), stack)
    end
    w:cast(CORRODE)
    w:advance(1.5)
    eq(w:icon("ActionButton1"), "cross", "five of five")
    eq(Stacks(ns, "Corrode"), 5)

    local asked = w.maxStackCalls
    check(asked >= 1, "the game was asked")
    w:cast(REND)
    w:advance(5)
    eq(w.maxStackCalls, asked, "and having answered for a skill, it is not asked about it again")
    eq(w:icon("ActionButton2"), "cross", "Rend goes on once, and that is all of it")

    w:drain()
    w:slash("list")
    local list = w:drain()
    check(list:find("Corrode|r puts a debuff that lasts 30 seconds on your target. It has an icon because", 1, true),
        list)
    check(list:find(" Its effect can have up to 5 stacks. The game gives this number for the skill.", 1, true), list)
    check(list:match("Corrode|r[^\n]*stacks") and not list:match("Rend|r[^\n]*stacks"),
        "Rend is not said to stack: " .. list)
    local spells = ns.db.report.spells
    eq(spells["Corrode"].gameStacks, 5, "what the game said is kept for troubleshooting")
    eq(spells["Corrode"].stacks, nil, "next to what the tooltip said, which was nothing")
    eq(spells["Rend"].gameStacks, false, "as is its saying that an effect goes on once")
    Clean(w)
end)

test("stacks: the larger of what the game says and what the tooltip says is how often an effect stacks", function()
    local w, ns = World({ saved = Proven() }), nil
    -- The tooltip has it higher than the game's data: a talent, say.
    w:addSpell(CORRODE, {
        name = "Corrode", harmful = true, cumulative = 3,
        description = "Eats into the target's armor, reducing it by 90. Stacks up to 5 times. Lasts 30 sec.",
        effect = { duration = 30, shared = true, stacks = 5 },
    })
    -- And the other way round.
    w:addSpell(CORRODE + 1, {
        name = "Gnaw", harmful = true, cumulative = 4,
        description = "Gnaws at the target, reducing its armor by 20. Stacks up to 2 times. Lasts 30 sec.",
        effect = { duration = 30, shared = true, stacks = 4 },
    })
    -- Numbers that are no count of stacks are not taken for one.
    w:addSpell(CORRODE + 2, {
        name = "Scratch", harmful = true, cumulative = 1,
        description = "Scratches the target, reducing its armor by 5. Lasts 30 sec.",
        effect = { duration = 30 },
    })
    w:addSpell(CORRODE + 3, {
        name = "Maul", harmful = true, cumulative = 255,
        description = "Mauls the target, reducing its armor by 50. Lasts 30 sec.",
        effect = { duration = 30 },
    })
    for i = 0, 3 do
        w:addButton("ActionButton" .. (i + 1), i + 1, CORRODE + i)
    end
    ns = w:load(Proven())
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:advance(0.3)
    local Spells = ns.Spells
    local function Most(id)
        return Spells:Stacking(Spells:Get(id, ns.Now()))
    end
    eq(Most(CORRODE), 5, "the tooltip's five over the game's three")
    eq(Spells:StackingSource(Spells:Get(CORRODE, ns.Now())), "tooltip")
    eq(Most(CORRODE + 1), 4, "the game's four over the tooltip's two")
    eq(Spells:StackingSource(Spells:Get(CORRODE + 1, ns.Now())), "game")
    eq(Most(CORRODE + 2), nil, "once is not stacking")
    eq(Spells:StackingSource(Spells:Get(CORRODE + 2, ns.Now())), nil)
    eq(Most(CORRODE + 3), nil, "and 255 is no count of stacks")
    eq(Spells:Get(CORRODE + 3, ns.Now()).gameStacks, false)

    -- What you said goes before both, and what was read off a unit only
    -- counts where it is more than either.
    w:slash("stacks Gnaw 3")
    eq(Most(CORRODE + 1), 3)
    eq(Spells:StackingSource(Spells:Get(CORRODE + 1, ns.Now())), "you")
    w:slash("stacks Gnaw auto")
    eq(Most(CORRODE + 1), 4)
    Spells:LearnStacks("Gnaw", 3)
    eq(Most(CORRODE + 1), 4, "three were seen, and the game has it at four")
    Spells:LearnStacks("Gnaw", 6)
    eq(Most(CORRODE + 1), 6, "six were seen: more than anything said of it")
    eq(Spells:StackingSource(Spells:Get(CORRODE + 1, ns.Now())), "seen")
    Spells:LearnStacks("Gnaw", 2)
    eq(Most(CORRODE + 1), 6, "seeing it fewer times over later takes nothing back")
    w:drain()
    w:slash("list")
    local list = w:drain()
    check(list:match("Gnaw|r puts a debuff that lasts 30 seconds on your target%. [^\n]* The addon has seen its effect "
        .. "reach 6 stacks so far, and takes that as the most it can have%. If it can go higher, type /se stacks Gnaw "
        .. "<number>%."), list)
    check(list:match("Corrode|r puts a debuff that lasts 30 seconds on your target%. [^\n]* Its effect can have up to 5 "
        .. "stacks%. The addon read this from the skill's tooltip%."), list)
    w:slash("stacks Corrode 2")
    w:drain()
    w:slash("list")
    list = w:drain()
    check(list:match("Corrode|r puts a debuff that lasts 30 seconds on your target%. [^\n]* Its effect can have up to 2 "
        .. "stacks%. You set this yourself%."), list)
    Clean(w)
end)

test("stacks: a client that keeps how often an effect stacks to itself in a fight is asked again after it", function()
    -- The addon loads in the middle of a fight, as after a /reload there.
    local w, ns, boar = Corroding({ maxStacks = "secret" }, true)
    local info = ns.Spells:Get(CORRODE, ns.Now())
    eq(info.gameStacks, nil, "asked, and not answered")
    local asked = w.maxStackCalls
    check(asked >= 1, "it was asked")
    w:cast(CORRODE)
    w:advance(1.5)
    eq(w:icon("ActionButton1"), "cross", "nothing says it stacks yet: there, and that is all that is known")
    eq(ns.db.report.spells["Corrode"].gameStacks, nil, "nothing to keep of it yet")
    w:cast(CORRODE)
    w:advance(1.5)
    check(w.maxStackCalls > asked, "asked again while the answer is owed")
    eq(info.gameStacks, nil)

    w:leaveCombat()
    w:advance(0.5)
    eq(info.gameStacks, 5, "out of the fight the game answers")
    eq(w:icon("ActionButton1"), "check", "two of five, read off the boar")
    eq(Stacks(ns, "Corrode"), 2)
    asked = w.maxStackCalls
    w:advance(5)
    eq(w.maxStackCalls, asked, "and is asked no more")

    w:cast(CORRODE)
    w:advance(1.5)
    eq(w:icon("ActionButton1"), "check", "three of five, counted in the next fight")
    eq(Stacks(ns, "Corrode"), 3)
    eq(ns.db.report.spells["Corrode"].gameStacks, 5, "the answer is kept once it has come")
    Clean(w)
end)

test("stacks: an answer from the game that is no number is no answer", function()
    local w, ns = Corroding({ maxStacks = "words" })
    local Spells = ns.Spells
    eq(Spells:Stacking(Spells:Get(CORRODE, ns.Now())), nil, "\"5\" is not five")
    eq(Spells:Get(CORRODE, ns.Now()).gameStacks, false)
    w:cast(CORRODE)
    w:advance(1.5)
    eq(w:icon("ActionButton1"), "cross")
    Clean(w)
end)

test("stacks: a client that cannot be asked how often an effect stacks leaves it to the tooltip and to what is seen", function()
    local w, ns, boar = Corroding({ maxStacks = "none" })
    local Spells = ns.Spells
    local info = Spells:Get(CORRODE, ns.Now())
    eq(info.gameStacks, false, "nothing to ask: settled the first time, out of a fight")
    eq(Spells:Stacking(info), nil)
    eq(Spells:Stacking(Spells:Get(SUNDER, ns.Now())), 5, "a tooltip that says so is still read")
    w:cast(CORRODE)
    w:advance(1.5)
    eq(w:icon("ActionButton1"), "cross", "nothing says it stacks")
    eq(ns.db.report.spells["Corrode"].gameStacks, false)

    -- Out of the fight it is seen twice over on the boar: it stacks, then,
    -- and that often at the least.
    w:cast(CORRODE)
    w:advance(1.5)
    w:leaveCombat()
    w:advance(0.5)
    eq(Spells:Stacking(info), 2)
    eq(Spells:StackingSource(info), "seen")
    w:applyAura(boar, "Corrode", 30, true, nil, nil, { shared = true, stacks = 5 })
    w:advance(0.5)
    eq(Spells:Stacking(info), 3, "and a third time")
    eq(w:icon("ActionButton1"), "cross", "as far as it has been seen to go")
    w:slash("stacks Corrode 5")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "until you say how far it goes")
    eq(Stacks(ns, "Corrode"), 3)
    Clean(w)
end)

test("stacks: a cast is counted once, however many signs of its landing come in", function()
    -- A client that lets your effects on the enemy be counted in a fight: the
    -- cast shows in the count as well as in the report.
    local w, ns = Sundering({ combatAuras = "ids" })
    w:cast(REND)
    w:advance(1)
    w:cast(SUNDER)
    w:advance(1.5)
    eq(Stacks(ns, "Sunder Armor"), 1, "seen twice over, and one stack all the same")
    w:cast(SUNDER)
    w:advance(1.5)
    eq(Stacks(ns, "Sunder Armor"), 2)
    Clean(w)
end)

test("stacks: a client that swaps an effect for a new one each time it is renewed is counted all the same", function()
    local w, ns = Sundering({ refreshReplaces = true })
    for stack = 1, 4 do
        w:cast(SUNDER)
        w:advance(1.5)
        eq(Stacks(ns, "Sunder Armor"), stack, "an effect going and one coming in the same report is no first stack")
        eq(w:icon("ActionButton1"), "check")
    end
    w:cast(SUNDER)
    w:advance(1.5)
    eq(w:icon("ActionButton1"), "cross")
    Clean(w)
end)

test("stacks: a renewal reported as one effect going and one coming, in two reports, is no first stack either", function()
    for _, how in ipairs({ "twice", "new first" }) do
        for order = 1, 2 do
            local w, ns = Sundering({ refreshReplaces = how })
            for stack = 1, 5 do
                -- The cast is announced before the reports, or after them.
                w:cast(SUNDER, order == 2 and { early = 0 } or nil)
                w:advance(1.5)
                eq(Stacks(ns, "Sunder Armor"), stack, how .. ", order " .. order)
            end
            eq(w:icon("ActionButton1"), "cross")
            Clean(w)
        end
    end
end)

test("stacks: another effect going as the first stack goes on does not make it more than one", function()
    for order = 1, 2 do
        local w, ns, boar = Sundering()
        w:applyAura(boar, "Curse of Recklessness", 120, false)
        w:advance(0.3)
        w:cast(REND)
        w:advance(1)
        -- The curse is taken off in the very frame Sunder Armor lands.
        if order == 1 then
            w:cast(SUNDER)
            w:removeAura(boar, "Curse of Recklessness")
        else
            w:removeAura(boar, "Curse of Recklessness")
            w:cast(SUNDER)
        end
        w:advance(1.5)
        eq(Stacks(ns, "Sunder Armor"), 1, "order " .. order)
        eq(w:icon("ActionButton1"), "check")
        Clean(w)
    end
end)

test("stacks: something else changing on the enemy a moment after a miss adds no stack", function()
    local w, ns, boar = Sundering()
    for _ = 1, 2 do
        w:cast(SUNDER)
        w:advance(1.5)
    end
    eq(Stacks(ns, "Sunder Armor"), 2)
    -- A miss, and three tenths of a second later another player's effect
    -- arrives. Sunder Armor has not been cast often enough yet to be held to
    -- the moment of its cast, so the change still passes for it landing.
    w:cast(SUNDER, { miss = true })
    w:advance(0.3)
    w:applyAura(boar, "Thorns", 30, false)
    w:advance(1.2)
    local casts = ns.db.report.casts
    check(casts[#casts]:find("Sunder Armor", 1, true) and casts[#casts]:find("changed, 0.30s after the cast", 1, true),
        casts[#casts])
    eq(Stacks(ns, "Sunder Armor"), 2, "but a stack is only counted for a landing in the moment of the cast")
    w:cast(SUNDER)
    w:advance(1.5)
    eq(Stacks(ns, "Sunder Armor"), 3, "like this one")
    Clean(w)
end)

test("stacks: a skill whose landings mostly show in the frame of its cast is not one that shows late", function()
    local w, ns, boar = Sundering()
    -- Two landings in the frame of the cast and one a moment after it: three
    -- landings, and not enough of them in the frame to hold the skill to it.
    for cast = 1, 3 do
        w:cast(SUNDER, cast == 3 and { travel = 0.1 } or nil)
        w:advance(1.5)
    end
    check(not Sharp(ns, SUNDER))
    check(not ns.Spells:ShowsLate("Sunder Armor"), "two in three showed in the frame")
    local before = Stacks(ns, "Sunder Armor")
    -- A miss, and something else changing on the boar three tenths later.
    w:cast(SUNDER, { miss = true })
    w:advance(0.3)
    w:applyAura(boar, "Thorns", 30, false)
    w:advance(1.2)
    eq(Stacks(ns, "Sunder Armor"), before, "which adds no stack: this skill's landings are not known to show late")
    Clean(w)
end)

test("stacks: where the game shows a landing late, stacks are counted once the skill is known for it", function()
    local w, ns = Sundering()
    for cast = 1, 3 do
        w:cast(SUNDER, { travel = 0.1 })
        w:advance(1.5)
        eq(Stacks(ns, "Sunder Armor"), 1, "there, and not counted on yet: cast " .. cast)
        eq(w:icon("ActionButton1"), "check")
    end
    -- Three landings, none of them in the moment of its cast: that is how
    -- this skill shows here, and from now on each one counts.
    for stack = 2, 3 do
        w:cast(SUNDER, { travel = 0.1 })
        w:advance(1.5)
        eq(Stacks(ns, "Sunder Armor"), stack)
    end
    eq(w:icon("ActionButton1"), "check", "five on it and three counted: low rather than high")
    for _ = 1, 2 do
        w:cast(SUNDER, { travel = 0.1 })
        w:advance(1.5)
    end
    eq(w:icon("ActionButton1"), "cross")
    Clean(w)
end)

test("stacks: two reports in one moment that differ are not read for what kind of landing it was", function()
    for order = 1, 4 do
        local w, ns, boar, warrior = Party(nil, SUNDER, REND)
        w:cast(SUNDER)
        w:advance(1.5)
        w:cast(SUNDER)
        w:advance(1.5)
        eq(Stacks(ns, "Sunder Armor"), 2)
        -- Your third Sunder Armor renews the effect, and in that same moment
        -- the other warrior's Rend arrives on the boar.
        if order == 1 then
            w:cast(SUNDER)
            w:partyCast(warrior, REND)
        elseif order == 2 then
            w:partyCast(warrior, REND, { first = "effect" })
            w:cast(SUNDER)
        elseif order == 3 then
            -- Both reports are in before your cast is announced.
            w:partyCast(warrior, REND, { first = "effect" })
            w:cast(SUNDER, { early = 0 })
        else
            -- The same, with the two reports handed to the tracker one after
            -- the other, as they are when something else is announced between them.
            local key, now = ns.KeyOf("target", "debuff"), ns.Now()
            ns.Tracker:Changed(key, now, true)
            ns.Tracker:Changed(key, now, false)
            w:cast(SUNDER, { miss = true }) -- nothing more is reported: those two are all there is
        end
        w:advance(1.5)
        eq(Stacks(ns, "Sunder Armor"), 3, "three, whichever report came first: order " .. order)
        Clean(w)
    end
end)

test("stacks: where nothing is reported, each cast that is taken to land is taken to add its stack", function()
    -- A client that never says when a unit's effects change, and is known for it.
    local quiet = { doubt = { player = BUILD, target = BUILD, softenemy = BUILD, plate = BUILD } }
    local w, ns = Sundering({ auraEvents = false, saved = quiet })
    for stack = 1, 4 do
        w:cast(SUNDER)
        w:advance(2.5)
        eq(Stacks(ns, "Sunder Armor"), stack)
        eq(w:icon("ActionButton1"), "check")
    end
    w:cast(SUNDER)
    w:advance(2.5)
    eq(w:icon("ActionButton1"), "cross", "five casts, with nothing to say that one of them missed")
    Clean(w)
end)

test("stacks: a first cast that is taken to land and then seen to is one stack", function()
    -- A client that was written off for saying nothing, and says something
    -- after all: the cast is taken on trust, and the report of its landing
    -- comes in on top of that.
    local quiet = { doubt = { player = BUILD, target = BUILD, softenemy = BUILD, plate = BUILD } }
    local w, ns = Sundering({ saved = quiet })
    w:cast(SUNDER)
    eq(Stacks(ns, "Sunder Armor"), 1, "taken on trust")
    w:advance(2.5)
    eq(Stacks(ns, "Sunder Armor"), 1, "and seen: one cast all the same")
    w:cast(SUNDER)
    w:advance(2.5)
    eq(Stacks(ns, "Sunder Armor"), 2)
    Clean(w)
end)

test("stacks: a landing that showed late and is then counted among your effects adds its stack, once", function()
    -- A client that lets your effects on the enemy be counted in a fight, and
    -- that puts a new effect in the place of one that is renewed.
    local w, ns = Sundering({ combatAuras = "ids", refreshReplaces = true })
    w:cast(REND)
    w:advance(1)
    w:cast(SUNDER, { travel = 0.2 })
    w:advance(1.5)
    eq(Stacks(ns, "Sunder Armor"), 1, "the late report put the first stack down, and the count shows that same one")
    w:cast(SUNDER, { travel = 0.2 })
    w:advance(1.5)
    eq(Stacks(ns, "Sunder Armor"), 2, "too late to be counted on by the report alone, but a new effect of yours "
        .. "is there: that is a landing")
    w:cast(SUNDER, { miss = true })
    w:advance(1.5)
    eq(Stacks(ns, "Sunder Armor"), 2, "and a miss is still a miss")
    Clean(w)
end)

test("stacks: a landing reported a frame after its cast is counted on, and a change well before it is not", function()
    local w, ns = Sundering()
    w:cast(SUNDER)
    w:advance(1.5)
    w:cast(SUNDER, { travel = 0.02 })
    w:advance(0.02, 0.02)
    w:advance(1.5)
    eq(Stacks(ns, "Sunder Armor"), 2, "two hundredths of a second after the cast was announced")

    -- The boar's effects change two tenths of a second before the cast is
    -- announced. That passes for the cast landing, as it has to, but it is
    -- too far from it to add a stack.
    w:cast(SUNDER, { early = 0.2 })
    w:advance(1.5)
    eq(w:icon("ActionButton1"), "check")
    eq(Stacks(ns, "Sunder Armor"), 2)
    local casts = ns.db.report.casts
    check(casts[#casts]:find("Sunder Armor", 1, true) and casts[#casts]:find("changed", 1, true), casts[#casts])
    Clean(w)
end)

test("stacks: a skill you said does not stack keeps no count", function()
    local w, ns = Sundering()
    for _ = 1, 2 do
        w:cast(SUNDER)
        w:advance(1.5)
    end
    eq(Booked(ns, "Sunder Armor").stacks, 2)
    w:slash("stacks Sunder Armor 1")
    w:cast(SUNDER)
    w:advance(1.5)
    eq(w:icon("ActionButton1"), "cross", "there, and that is all it can be")
    eq(Booked(ns, "Sunder Armor").stacks, nil, "nothing is counted for it")
    w:slash("stacks Sunder Armor auto")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "and when it stacks again the count starts low")
    eq(Stacks(ns, "Sunder Armor"), 1)
    Clean(w)
end)

test("stacks: an enemy that goes out of sight during the wait is given no stack on trust", function()
    local w, ns = Bar({ saved = Proven() }, SUNDER)
    local boar = w:addMob("Boar") -- no nameplate: once it is not the target, nothing reports on it
    local wolf = w:addMob("Wolf")
    w:target(boar)
    w:advance(0.3)
    w:cast(SUNDER)
    w:advance(1.5)
    eq(Stacks(ns, "Sunder Armor"), 1)
    w:cast(SUNDER, { travel = 0.5 })
    w:target(wolf)
    w:advance(1)
    eq(w:icon("ActionButton1"), "check", "the wolf is clean")
    w:target(boar)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check")
    eq(Stacks(ns, "Sunder Armor"), 1, "there, and no more times over than it was seen to be")

    -- The same for one that had none: it is taken to be there, once.
    local fox = w:addMob("Fox")
    w:target(fox)
    w:advance(0.3)
    w:cast(SUNDER, { travel = 0.5 })
    w:target(wolf)
    w:advance(1)
    w:target(fox)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check")
    eq(Stacks(ns, "Sunder Armor"), 1)
    Clean(w)
end)

test("stacks: what a report shows of a landing is read for a buff on you as well", function()
    local w, ns = Bar({ saved = Proven() }, FRENZY, BLOCK)
    local function Frenzied()
        return ns.Tracker:Stacks(ns.KeyOf("player", "buff"), "Battle Frenzy", ns.Now())
    end
    local boar = w:addMob("Boar")
    w:target(boar)
    w:enterCombat()
    w:advance(0.3)
    w:cast(FRENZY)
    w:advance(0.5)
    w:cast(FRENZY)
    w:advance(0.5)
    eq(Frenzied(), 2)
    -- The books lose it while it is still on you.
    w:slash("ignore Battle Frenzy")
    w:slash("auto Battle Frenzy")
    w:advance(0.3)
    eq(Frenzied(), 0)
    w:cast(FRENZY)
    w:advance(0.5)
    if KindsTold() then
        eq(Frenzied(), 2, "the report renewed an effect and added none: it was there, so two at least")
    else
        eq(Frenzied(), 1, "nothing to tell it from a first stack")
    end
    Clean(w)
end)

test("stacks: a report that both added an effect and renewed one is not read as either", function()
    local w, ns, boar = Sundering()
    w:applyAura(boar, "Thorns", 30, false)
    w:advance(0.3)
    w:cast(REND)
    w:advance(1)
    -- Someone's Thorns is renewed on the boar in the very frame your first
    -- Sunder Armor lands, and one report tells of both.
    boar.owed = "updated"
    w:cast(SUNDER)
    w:advance(1.5)
    eq(Stacks(ns, "Sunder Armor"), 1, "nothing on the books, and nothing to say it was there: a first stack")
    eq(w:icon("ActionButton1"), "check")
    Clean(w)
end)

test("stacks: what was read off a unit stands, whatever is reported of that moment afterwards", function()
    local w, ns = Sundering()
    w:cast(SUNDER)
    w:advance(0.05)
    local key, now = ns.KeyOf("target", "debuff"), ns.Now()
    eq(Stacks(ns, "Sunder Armor"), 1, "counted from the report of its landing")
    -- It is read off the boar, four times over, and then a second report of
    -- the moment it landed comes in that shows another kind of change.
    ns.Tracker:Observe(key, "Sunder Armor", { duration = 30, expires = now + 30, stacks = 4 }, now)
    eq(Stacks(ns, "Sunder Armor"), 4)
    ns.Tracker:Changed(key, now - 0.05, nil)
    ns.Tracker:Changed(key, now - 0.05, true)
    ns.Tracker:Changed(key, now - 0.05, false)
    eq(Stacks(ns, "Sunder Armor"), 4, "no count is made again from a report once the effect has been read")
    Clean(w)
end)

test("stacks: what the game said of each change, and what was read from the tooltips, is saved for troubleshooting", function()
    local w, ns = Sundering()
    w:cast(REND)
    w:advance(1)
    for _ = 1, 3 do
        w:cast(SUNDER)
        w:advance(1.5)
    end
    local kinds = ns.db.report.reports.kinds
    if KindsTold() then
        -- Each change is reported twice: by your target, and by its nameplate.
        eq(kinds.added, 4, "Rend, and the first Sunder Armor")
        eq(kinds.renewed, 4, "the second and the third")
    else
        eq(kinds.added, 0)
        eq(kinds.renewed, 0)
    end
    local spells = ns.db.report.spells
    eq(spells["Sunder Armor"].stacks, "can be applied up to 5 times", "the words its stacks were read from")
    eq(spells["Sunder Armor"].own, nil, "nothing says its effect is each caster's own")
    eq(spells.Rend.own, "over 21 sec", "the words that make Rend each caster's own")
    eq(spells.Rend.stacks, nil)
    w:slash("debug")
    local debug = w:drain()
    check(debug:find(KindsTold() and "Of the ones arriving, only added: 4, only renewed: 4." or
        "Of the ones arriving, only added: 0, only renewed: 0.", 1, true), debug)
    check(debug:find("Sunder Armor x3, ", 1, true), debug)
    Clean(w)
end)

--------------------------------------------------------------------------------
-- Other players' effects
--
-- An effect that a unit carries only once, whoever put it there, counts when
-- it is another player's: a second warrior's Demoralizing Shout does what
-- yours would. Out of a fight it is read off the unit. In a fight it can only
-- be followed through that player's cast, where the game says what they cast.
--------------------------------------------------------------------------------

test("others: another player's debuff counts when it is one an enemy carries only once", function()
    local w, ns, boar = Party(nil, DEMO, REND, SUNDER)
    eq(w:icon("ActionButton1"), "check")
    w:applyAura(boar, "Demoralizing Shout", 60, false) -- another warrior's, with a talent that makes it last longer
    w:applyAura(boar, "Rend", 21, false) -- and their Rend
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "their shout does what yours would")
    eq(w:icon("ActionButton2"), "check", "their bleed is theirs: yours would add to it")
    eq(ns.db.learned["Demoralizing Shout"].exact, true, "the effect carries the spell's name, whoever cast it")
    eq(ns.db.learned["Demoralizing Shout"].duration, nil, "how long theirs lasts says nothing of yours")
    eq(ns.db.learned.Rend, nil, "and nothing is learned from an effect that does not count")

    w:removeAura(boar, "Demoralizing Shout")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "gone again")

    for _ = 1, 5 do
        w:applyAura(boar, "Sunder Armor", 30, false, nil, nil, { shared = true, stacks = 5 })
    end
    w:advance(0.3)
    eq(w:icon("ActionButton3"), "cross", "five stacks, none of them yours")

    w:slash("debug")
    check(w:drain():find("Sunder Armor x5, 30s left (another player's)", 1, true), "/se debug says whose it is")
    Clean(w)
end)

test("others: your own effect is the one that counts while both are there", function()
    -- A client on which every player's Demoralizing Shout is an effect of its
    -- own on the enemy, though only one of them does anything.
    local w, ns, boar = Party(nil, DEMO)
    w:applyAura(boar, "Demoralizing Shout", 45, false)
    w:advance(10)
    w:applyAura(boar, "Demoralizing Shout", 45, true)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross")
    eq(ns.db.learned["Demoralizing Shout"].duration, 45, "yours is what its length is learned from")
    w:advance(36)
    eq(w:icon("ActionButton1"), "cross", "theirs has run out and yours has not")
    w:advance(10)
    eq(w:icon("ActionButton1"), "check")
    Clean(w)
end)

test("others: in a fight, a group member's cast of a skill you both have is followed by what the enemy reports", function()
    local w, ns, boar, warrior = Party(nil, DEMO, REND)
    Open(w)
    eq(w:icon("ActionButton1"), "check")

    w:partyCast(warrior, DEMO)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "their shout landed on the boar")
    w:partyCast(warrior, REND)
    w:advance(0.3)
    eq(w:icon("ActionButton2"), "check", "their Rend is theirs: yours is still worth casting")
    w:advance(29)
    eq(w:icon("ActionButton1"), "cross", "theirs is given two thirds of the time yours lasts")
    w:advance(1.5)
    eq(w:icon("ActionButton1"), "check")

    w:partyCast(warrior, DEMO, { miss = true })
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "nothing changed on the boar, so theirs left nothing: no cast of theirs is taken on trust")

    w:partyCast(warrior, DEMO, { first = "effect" })
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "the change may be reported just before the cast, in the same moment")

    local others = ns.db.report.others
    eq(others.casts, 4, "every cast of theirs that was heard")
    eq(others.named, 4, "with a spell that could be read, during the fight")
    eq(others.unnamed, 0)
    eq(others.calm, 0)
    eq(others.followed, 3, "the shouts: a spell of yours that another player's copy counts for")
    eq(others.landed, 2)
    Clean(w)
end)

test("others: a group member's shout is not given the time yours lasts, which a talent may have made longer", function()
    -- Yours lasts 45 seconds. Theirs, without the talent, lasts 30.
    local w, ns, boar, warrior = Party(nil, DEMO, REND)
    warrior.lasts = { ["Demoralizing Shout"] = 30 }
    Open(w)
    w:partyCast(warrior, DEMO)
    w:advance(29.5)
    eq(w:icon("ActionButton1"), "cross")
    w:advance(1)
    eq(w:icon("ActionButton1"), "check", "theirs has run out, and the cross does not stay on after it")

    -- An effect that stacks is one effect that every caster adds to and
    -- renews, so theirs keeps the whole time.
    w, ns, boar, warrior = Party(nil, SUNDER, REND)
    Open(w)
    w:partyCast(warrior, SUNDER)
    w:advance(0.3)
    local left = Booked(ns, "Sunder Armor").left
    check(left > 29 and left < 30, "all of its 30 seconds: " .. tostring(left))
    Clean(w)
end)

test("others: once a member's own copy has been read, their casts are given what theirs lasts", function()
    for _, lasts in ipairs({ 45, 20 }) do
        local w, ns, boar, warrior = Party(nil, DEMO, REND)
        warrior.lasts = { ["Demoralizing Shout"] = lasts }
        -- Before the fight their shout is on the boar, and the game says who put it there.
        w:partyCast(warrior, DEMO)
        w:advance(0.3)
        eq(w:icon("ActionButton1"), "cross")
        local others = ns.db.report.others
        eq(others.read, 1, "how long theirs lasts was read once")
        eq(others.sourced, 1, "with who put it there")
        w:removeAura(boar, "Demoralizing Shout")
        w:advance(0.3)
        eq(w:icon("ActionButton1"), "check")

        Open(w)
        w:partyCast(warrior, DEMO)
        w:advance(lasts - 0.5)
        eq(w:icon("ActionButton1"), "cross", "theirs lasts " .. lasts .. " seconds, and that is what it is given")
        w:advance(1)
        eq(w:icon("ActionButton1"), "check")
        w:slash("debug")
        check(w:drain():find("Another player's copy read for how long it lasts: 1, and with who put it there: 1.", 1,
            true), "/se debug says what was read")
        Clean(w)
    end

    -- A member whose copies were read to last different times is given the
    -- shortest of them, whichever was read last.
    local w, ns, boar, warrior = Party(nil, DEMO, REND)
    for _, lasts in ipairs({ 20, 45 }) do
        w:partyCast(warrior, DEMO, { lasts = lasts })
        w:advance(0.3)
        w:removeAura(boar, "Demoralizing Shout")
        w:advance(0.3)
    end
    eq(ns.db.report.others.sourced, 1, "the longer one told nothing new")
    Open(w)
    w:partyCast(warrior, DEMO, { lasts = 20 })
    w:advance(20.5)
    eq(w:icon("ActionButton1"), "check")
    Clean(w)
end)

test("others: a copy that nobody is named for can make their casts shorter, and never longer", function()
    local w, ns, boar, warrior = Party({ noSource = true }, DEMO, REND)
    w:partyCast(warrior, DEMO) -- theirs lasts 45 seconds, as yours does
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "read off the boar while nothing is hidden")
    eq(ns.db.report.others.read, 1)
    eq(ns.db.report.others.sourced, 0, "the game did not say whose it was")
    w:removeAura(boar, "Demoralizing Shout")
    w:advance(0.3)
    Open(w)
    w:partyCast(warrior, DEMO)
    w:advance(29.5)
    eq(w:icon("ActionButton1"), "cross")
    w:advance(1)
    eq(w:icon("ActionButton1"), "check", "it may have been someone else's: two thirds of yours is all theirs is given")

    -- One that was read to last less than that is as long as any of theirs is given.
    w:leaveCombat()
    w:removeAura(boar, "Demoralizing Shout")
    w:advance(0.3)
    w:partyCast(warrior, DEMO, { lasts = 20 })
    w:advance(0.3)
    w:removeAura(boar, "Demoralizing Shout")
    w:advance(0.3)
    eq(ns.db.report.others.read, 2)
    -- A longer one read after it changes nothing: the shortest stands.
    w:partyCast(warrior, DEMO)
    w:advance(0.3)
    w:removeAura(boar, "Demoralizing Shout")
    w:advance(0.3)
    eq(ns.db.report.others.read, 2, "which told nothing new")
    w:enterCombat()
    w:partyCast(warrior, DEMO, { lasts = 20 })
    w:advance(19.5)
    eq(w:icon("ActionButton1"), "cross")
    w:advance(1)
    eq(w:icon("ActionButton1"), "check", "twenty seconds, like the shortest that was read")

    -- Someone joins the group: whoever that copy was from may be gone.
    w:addPartyMember("Healer")
    w:advance(2)
    w:partyCast(warrior, DEMO)
    w:advance(29.5)
    eq(w:icon("ActionButton1"), "cross", "two thirds of yours again")
    w:advance(1)
    eq(w:icon("ActionButton1"), "check")
    Clean(w)
end)

test("others: what was read of a member is forgotten when the group changes", function()
    local w, ns, boar, warrior = Party(nil, DEMO, REND)
    w:partyCast(warrior, DEMO) -- theirs lasts 45 seconds
    w:advance(0.3)
    w:removeAura(boar, "Demoralizing Shout")
    w:removePartyMember(warrior)
    local fighter = w:addPartyMember("Fighter", { target = boar, lasts = { ["Demoralizing Shout"] = 30 } })
    eq(fighter.token, "party1", "the name the one who left went by")
    w:advance(0.3)
    Open(w)
    w:partyCast(fighter, DEMO)
    w:advance(29.5)
    eq(w:icon("ActionButton1"), "cross")
    w:advance(1)
    eq(w:icon("ActionButton1"), "check", "what the first one's lasted says nothing of this one's")
    Clean(w)

    -- A client that does not tell when the group changes: then nothing is
    -- kept of who put a copy there, since a name may have changed hands.
    w, ns, boar, warrior = Party({ unknownEvents = { GROUP_ROSTER_UPDATE = true } }, DEMO, REND)
    w:partyCast(warrior, DEMO)
    w:advance(0.3)
    eq(ns.db.report.others.read, 1)
    eq(ns.db.report.others.sourced, 0)
    w:removeAura(boar, "Demoralizing Shout")
    w:advance(0.3)
    Open(w)
    w:partyCast(warrior, DEMO)
    w:advance(30.5)
    eq(w:icon("ActionButton1"), "check", "two thirds of yours, though theirs was read to last as long")
    Clean(w)
end)

test("others: in a raid, a copy named by a member's party name is put down to the raid name their casts are heard under", function()
    local w, ns = Bar({ saved = Proven(), raid = true }, DEMO, REND)
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    local warrior = w:addPartyMember("Warrior", { target = boar, subgroup = true })
    w:advance(0.3)
    w:partyCast(warrior, DEMO)
    w:advance(0.3)
    eq(boar.auras[1].source, warrior)
    eq(ns.db.report.others.sourced, 1)
    w:removeAura(boar, "Demoralizing Shout")
    w:advance(0.3)
    Open(w)
    w:partyCast(warrior, DEMO)
    w:advance(44.5)
    eq(w:icon("ActionButton1"), "cross", "theirs was read to last 45 seconds")
    w:advance(1)
    eq(w:icon("ActionButton1"), "check")

    -- Your own copy, read under everyone's effects, is not another player's.
    eq(ns.GroupToken("raid1"), nil, "raid1 is you")
    eq(ns.GroupToken("player"), nil)
    eq(ns.GroupToken("party1"), "raid2")
    eq(ns.GroupToken("raid2"), "raid2")
    eq(ns.GroupToken("target"), nil, "the boar is in nobody's group")
    Clean(w)
end)

test("others: a group member's lower rank of a spell goes by its name, and is given no longer than that rank lasts", function()
    local w, ns, boar, warrior = Party(nil, DEMO, REND)
    local LOWER = 11551
    w:addSpell(LOWER, {
        name = "Demoralizing Shout", harmful = false, helpful = false,
        description = "Reduces the melee attack power of all enemies within 10 yards by 30 for 21 sec.",
        effect = { area = true, duration = 14, shared = true },
    })
    Open(w)
    w:partyCast(warrior, LOWER)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "their shout, whatever rank of it they have")
    w:advance(13.2)
    eq(w:icon("ActionButton1"), "cross")
    w:advance(1)
    eq(w:icon("ActionButton1"), "check", "two thirds of the 21 seconds their rank lasts for you, not of your 45")
    Clean(w)
end)

test("others: their shout taking the place of yours is theirs from then on", function()
    -- A client that lets your effects on the enemy be counted in a fight.
    local w, ns, boar, warrior = Party({ combatAuras = "ids" }, DEMO, REND)
    w:cast(DEMO)
    w:advance(1)
    w:cast(REND)
    w:advance(10)
    eq(w:icon("ActionButton1"), "cross")
    eq(w:icon("ActionButton2"), "cross")
    w:partyCast(warrior, DEMO)
    w:advance(0.5)
    eq(#boar.auras, 2, "the boar carries the shout once")
    eq(w:icon("ActionButton1"), "cross")
    eq(Booked(ns, "Demoralizing Shout").how, "another player's")
    local left = Booked(ns, "Demoralizing Shout").left
    check(left > 29 and left < 30, "and it is given what theirs is, from their cast: " .. tostring(left))
    eq(w:icon("ActionButton2"), "cross", "one effect of yours fewer on the boar is the shout, and not Rend")
    w:advance(8)
    eq(w:icon("ActionButton2"), "cross", "Rend has two seconds left")
    w:advance(3)
    eq(w:icon("ActionButton2"), "check")
    eq(w:icon("ActionButton1"), "cross")
    Clean(w)
end)

test("others: a change that comes in another moment than their cast is not put down to it", function()
    local w, ns, boar, warrior = Party(nil, DEMO, REND)
    Open(w)
    w:partyCast(warrior, DEMO, { travel = 0.2 })
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "check", "so much changes on an enemy in a group that only the very moment counts")
    eq(ns.db.report.others.landed, 0)

    -- And a change in the moment of their cast is theirs, not that of a cast
    -- of yours that has been waiting.
    w:advance(30)
    w:cast(REND, { miss = true })
    w:advance(0.2)
    w:partyCast(warrior, DEMO)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "their shout")
    eq(w:icon("ActionButton2"), "check", "your Rend missed, and their shout does not pass for it")
    Clean(w)
end)

test("others: where the game keeps a group member's spell secret, their copy shows once your own cast renews it", function()
    local w, ns, boar, warrior = Party({ groupCasts = "secret" }, DEMO, REND)
    w:partyCast(warrior, REND) -- before the fight their spells can be read
    Open(w)
    w:partyCast(warrior, DEMO)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "which spell they cast could not be read")
    local others = ns.db.report.others
    eq(others.casts, 2)
    eq(others.calm, 1, "the one before the fight")
    eq(others.unnamed, 1, "and the saved report says what the game kept back")
    eq(others.named, 0)
    eq(others.followed, 0)

    w:cast(DEMO)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross", "your own cast is followed as ever")
    Clean(w)

    -- A client that sends nothing for anyone but you.
    w, ns, boar, warrior = Party({ groupCasts = "none" }, DEMO, REND)
    Open(w)
    w:partyCast(warrior, DEMO)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check")
    eq(ns.db.report.others, nil, "nothing was heard")
    w:slash("debug")
    check(w:drain():find("Casts heard from your group: none yet.", 1, true))
    Clean(w)
end)

test("others: another warrior's Sunder Armor adds to the stacks", function()
    local w, ns, boar, warrior = Party(nil, SUNDER, REND)
    local wolf = w:addMob("Wolf")
    w:showPlate(wolf)
    w:cast(SUNDER)
    w:advance(1.5)
    w:partyCast(warrior, SUNDER)
    w:advance(0.5)
    w:partyCast(warrior, SUNDER)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "check", "three of five: one of yours and two of theirs")
    eq(Stacks(ns, "Sunder Armor"), 3)
    w:cast(SUNDER)
    w:advance(1.5)
    w:partyCast(warrior, SUNDER, { miss = true })
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "check", "four of five: their last one missed")
    eq(Stacks(ns, "Sunder Armor"), 4)
    w:partyCast(warrior, SUNDER)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross", "five between the two of you")

    -- They turn to the wolf. What they cast there is no longer on the boar.
    warrior.target = wolf
    w:partyCast(warrior, SUNDER)
    w:advance(0.5)
    w:target(wolf)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "one of five on the wolf, and it is theirs")
    eq(Stacks(ns, "Sunder Armor"), 1)
    w:slash("debug")
    local debug = w:drain()
    check(debug:find("Sunder Armor x1, ", 1, true) and debug:find("(another player's)", 1, true), debug)
    check(debug:find("Casts heard from your group: 5. With details hidden, the spell could be read for 5 and was "
        .. "kept secret for 0. Of a spell of yours: 5, seen to land: 4.", 1, true), debug)
    Clean(w)
end)

test("others: one report for two casts in the same moment goes to yours", function()
    local w, ns, boar, warrior = Party(nil, SUNDER, REND)
    w:cast(SUNDER)
    w:partyCast(warrior, SUNDER)
    w:advance(1.5)
    eq(ns.Tracker:Stacks(ns.KeyOf("target", "debuff"), "Sunder Armor", ns.Now()), 1,
        "counted low rather than high: two are on it")
    eq(w:icon("ActionButton1"), "check")
    Clean(w)
end)

test("others: a second warrior's shout on you in a fight", function()
    local w, ns, boar, warrior = Party(nil, RAGING, BLOCK, REND)
    eq(w:icon("ActionButton1"), "check")
    Open(w)
    w:partyCast(warrior, RAGING)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "their shout is on you, and yours would add nothing")

    -- A skill that only ever lands on its caster cannot have come from them,
    -- whatever changes on you in the moment they use it.
    w:partyCast(warrior, BLOCK)
    w:applyBuff("Mark of the Wild", 1800, false)
    w:advance(0.3)
    eq(w:icon("ActionButton2"), "check", "their Shield Block is on them")
    Clean(w)
end)

test("others: in a raid a member's cast is heard once, and your own is not taken for someone else's", function()
    local w, ns = Bar({ saved = Proven(), raid = true }, SUNDER, REND)
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    local warrior = w:addPartyMember("Warrior", { target = boar, subgroup = true })
    eq(warrior.token, "raid2", "raid1 is you")
    eq(warrior.partyToken, "party1", "and they are in your own party of five as well")
    w:advance(0.3)
    Open(w)
    w:partyCast(warrior, SUNDER)
    w:advance(0.5)
    eq(w.groupCastsSent, 2, "the game announces it under both of their names")
    eq(ns.db.report.others.casts, 1, "one cast")
    eq(ns.Tracker:Stacks(ns.KeyOf("target", "debuff"), "Sunder Armor", ns.Now()), 1, "and one stack")

    -- Your own casts are announced under your raid name too.
    w:partyCast(w.player, SUNDER, { miss = true })
    w:advance(0.5)
    eq(ns.db.report.others.casts, 1, "which is nobody else's cast")
    Clean(w)
end)

test("others: a client that only lists your own effects leaves another player's where it was put", function()
    local w, ns, boar, warrior = Party({ othersHidden = true }, DEMO, REND)
    w:applyAura(boar, "Demoralizing Shout", 45, false)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "theirs cannot be read")
    w:cast(DEMO, { quiet = true })
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross", "yours can")
    w:removeAura(boar, "Demoralizing Shout")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check")

    -- One of theirs that was followed through their cast in a fight stays in
    -- the books after it, until its time is up: nothing says it has gone.
    Open(w)
    w:partyCast(warrior, DEMO)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross")
    w:leaveCombat()
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross", "it cannot be read, and is not taken to be gone for that")
    Clean(w)

    -- Where theirs can be read, the books follow what is read.
    w, ns, boar, warrior = Party(nil, DEMO, REND)
    w:cast(DEMO, { quiet = true })
    w:advance(46)
    eq(w:icon("ActionButton1"), "check", "yours was read by its name, and has run out")
    Open(w)
    w:partyCast(warrior, DEMO)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross")
    w:removeAura(boar, "Demoralizing Shout")
    w:leaveCombat()
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "check", "read, and gone")
    Clean(w)
end)

test("others: an effect the client still shows by name in a fight is read whoever put it there", function()
    local w, ns, boar, warrior = Party({ byName = { ["Demoralizing Shout"] = true, Rend = true }, groupCasts = "none" },
        DEMO, REND)
    Open(w)
    w:partyCast(warrior, DEMO)
    w:partyCast(warrior, REND)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "their shout, read by its name")
    eq(w:icon("ActionButton2"), "check", "their Rend is not asked after: only yours counts")
    eq(ns.db.learned["Demoralizing Shout"].duration, nil, "how long theirs lasts says nothing of yours")
    eq(ns.db.report.others.read, 1, "it is kept for their casts, though")
    eq(ns.db.report.others.sourced, 1, "with who put it there")
    local reads = ns.db.report.nameReads
    check(reads["Demoralizing Shout, anyone's"].found > 0, "what asking after everyone's gave is kept apart")
    eq(reads["Demoralizing Shout"].found, 0)
    eq(reads["Rend, anyone's"], nil)
    w:removeAura(boar, "Demoralizing Shout")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "and seen to go")
    Clean(w)
end)

test("others: your own cast landing where theirs was makes the effect yours again", function()
    local w, ns, boar, warrior = Party(nil, DEMO, REND)
    Open(w)
    w:partyCast(warrior, DEMO)
    w:advance(5)
    eq(Booked(ns, "Demoralizing Shout").how, "another player's")
    w:cast(DEMO)
    w:advance(1.5)
    local booked = Booked(ns, "Demoralizing Shout")
    eq(booked.how, "the unit's effects changed when it was cast", "yours is on it now, whoever's it was")
    check(booked.left > 43 and booked.left < 44, "for as long as yours lasts: " .. booked.left)
    Clean(w)
end)

test("others: you and a group member shouting in the same moment leaves the shorter time of the two", function()
    for order = 1, 2 do
        local w, ns, boar, warrior = Party(nil, DEMO, REND)
        Open(w)
        if order == 1 then
            w:cast(DEMO)
            w:partyCast(warrior, DEMO)
        else
            w:partyCast(warrior, DEMO, { first = "effect" })
            w:cast(DEMO)
        end
        w:advance(1.5)
        eq(w:icon("ActionButton1"), "cross")
        local booked = Booked(ns, "Demoralizing Shout")
        -- Your cast is judged first by a change in its own frame: it landed.
        eq(booked.how, "the unit's effects changed when it was cast", "order " .. order)
        local casts = ns.db.report.casts
        check(casts[#casts]:find("Demoralizing Shout", 1, true) and casts[#casts]:find("changed, 0.00s after the cast",
            1, true), casts[#casts])
        -- Which of the two shouts is on the boar now is not told, and theirs
        -- may not last as long as yours.
        check(booked.left > 28 and booked.left < 29, "order " .. order .. ": " .. booked.left)
        w:advance(27)
        eq(w:icon("ActionButton1"), "cross")
        w:advance(2)
        eq(w:icon("ActionButton1"), "check", "thirty seconds after the two casts")
        w:advance(2)
        eq(ns.db.learned["Demoralizing Shout"].late, nil, "and that nothing was reported just then is not held "
            .. "against the spell: it was not known to end then")
        Clean(w)
    end

    -- A moment apart, each is judged by the change in its own frame, and the
    -- later one is the one on the boar.
    local w, ns, boar, warrior = Party(nil, DEMO, REND)
    Open(w)
    w:partyCast(warrior, DEMO)
    w:advance(0.1)
    w:cast(DEMO)
    w:advance(1.5)
    local booked = Booked(ns, "Demoralizing Shout")
    eq(booked.how, "the unit's effects changed when it was cast")
    check(booked.left > 43 and booked.left < 44, "yours, for all of its time: " .. booked.left)
    Clean(w)

    -- Theirs is known to last longer than yours: yours is still the shorter
    -- of the two, and the one the books go by.
    w, ns, boar, warrior = Party(nil, DEMO, REND)
    warrior.lasts = { ["Demoralizing Shout"] = 60 }
    w:partyCast(warrior, DEMO)
    w:advance(0.3)
    w:removeAura(boar, "Demoralizing Shout")
    w:advance(0.3)
    Open(w)
    w:cast(DEMO)
    w:partyCast(warrior, DEMO)
    w:advance(1.5)
    booked = Booked(ns, "Demoralizing Shout")
    check(booked.left > 43 and booked.left < 44, "45 seconds of yours, not 60 of theirs: " .. booked.left)
    Clean(w)

    -- And a different skill of theirs in the same moment takes nothing from yours.
    w, ns, boar, warrior = Party(nil, DEMO, SUNDER)
    Open(w)
    w:cast(DEMO)
    w:partyCast(warrior, SUNDER)
    w:advance(1.5)
    booked = Booked(ns, "Demoralizing Shout")
    eq(booked.how, "the unit's effects changed when it was cast")
    check(booked.left > 43 and booked.left < 44, "their Sunder Armor is not your shout: " .. booked.left)
    Clean(w)
end)

test("others: when another player's copy runs out is not held against the spell", function()
    local w, ns, boar, warrior = Party(nil, DEMO, REND)
    Open(w)
    w:partyCast(warrior, DEMO) -- theirs lasts 45 seconds, and is given 30
    w:advance(29.5)
    eq(w:icon("ActionButton1"), "cross")
    w:advance(3)
    eq(w:icon("ActionButton1"), "check")
    local learned = ns.db.learned["Demoralizing Shout"] or {}
    eq(learned.late, nil, "nothing was reported when the books had it ending, and nothing was owed")
    eq(learned.due, nil)
    Clean(w)
end)

test("others: an effect of another kind that happens to share a skill's name is not taken for its copy", function()
    local w, ns, boar, warrior = Party(nil, DEMO, REND, BLOCK)
    -- Someone's buff on you, by the name of your debuff, lasting ten seconds.
    w:applyAura(w.player, "Demoralizing Shout", 10, false, nil, true)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "check", "the boar has no Demoralizing Shout")
    local others = ns.db.report.others
    eq(others and others.read or 0, 0, "and that buff says nothing of how long the debuff lasts")
    Open(w)
    w:partyCast(warrior, DEMO)
    w:advance(12)
    eq(w:icon("ActionButton1"), "cross", "their shout is still given two thirds of yours")
    Clean(w)
end)

test("/se stacks, /se anyone and /se mine set by hand what the tooltip is read for", function()
    local w, ns, boar = Party(nil, SUNDER, REND)
    w:drain()
    w:slash("list")
    local list = w:drain()
    check(list:find("Sunder Armor|r puts a debuff that lasts 30 seconds on your target. It has an icon because its "
        .. "tooltip describes a debuff that lasts for a while. Its effect can have up to 5 stacks. The addon read this "
        .. "from the skill's tooltip. The icon treats another player's Sunder Armor like your own.", 1, true), list)
    local rend = "Rend|r puts a debuff that lasts 21 seconds on your target. It has an icon because its tooltip "
        .. "describes a debuff that lasts for a while."
    check(list:find(rend .. "\n", 1, true) or list:sub(-#rend) == rend,
        "Rend is your own, and does not stack: " .. list)

    w:slash("stacks Sunder Armor 3")
    check(w:drain():find("The effect of Sunder Armor can now have up to 3 stacks. The icon shows the green check "
        .. "until all 3 are there.", 1, true))
    eq(ns.db.spells["Sunder Armor"].stacks, 3)
    for _ = 1, 3 do
        w:applyAura(boar, "Sunder Armor", 30, true, nil, nil, { shared = true, stacks = 5 })
    end
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "three is all of it now")
    w:slash("stacks sunder armor auto")
    check(w:drain():find("The addon works out by itself again how many stacks the effect of Sunder Armor can have, "
        .. "from the game and from the skill's tooltip.", 1, true))
    eq(ns.db.spells["Sunder Armor"], nil, "nothing is left of the choice")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "three of five")
    eq(Stacks(ns, "Sunder Armor"), 3)
    w:slash("stacks Sunder Armor 1")
    check(w:drain():find("The effect of Sunder Armor is now set as one that does not stack.", 1, true))
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "there, and that is all it can be")
    w:slash("list")
    list = w:drain()
    check(list:find("Sunder Armor|r puts a debuff that lasts 30 seconds on your target.", 1, true)
        and not list:match("Sunder Armor|r[^\n]*stacks"), "and /se list no longer says it stacks: " .. list)
    w:slash("stacks Rend 4")
    w:applyAura(boar, "Rend", 21, true)
    w:advance(0.3)
    eq(w:icon("ActionButton2"), "check", "a skill whose tooltip says nothing of stacks can be given some")
    eq(Stacks(ns, "Rend"), 1, "one of the four it was given")

    w:slash("stacks Sunder Armor lots")
    check(w:drain():find("Type the most stacks the effect can have as a whole number from 1 to 100", 1, true))
    w:slash("stacks Sunder Armor 2.5")
    check(w:drain():find("Type the most stacks the effect can have as a whole number", 1, true))
    w:slash("stacks Sunder Armor 0")
    check(w:drain():find("Type the most stacks the effect can have as a whole number", 1, true))
    w:slash("stacks")
    check(w:drain():find("Type the skill's name and then the most stacks its effect can have. For example: /se stacks "
        .. "Sunder Armor 5", 1, true))
    eq(ns.db.spells["Sunder Armor"].stacks, 1, "none of which changed anything")

    -- Whose effect counts.
    w:removeAura(boar, "Rend")
    w:applyAura(boar, "Rend", 21, false)
    w:advance(0.3)
    eq(w:icon("ActionButton2"), "check", "another warrior's Rend does not count by itself")
    w:slash("anyone Rend")
    check(w:drain():find("The icon for Rend now treats another player's Rend like your own.", 1, true))
    w:advance(0.3)
    check(Booked(ns, "Rend") and Booked(ns, "Rend").how == "another player's", "now it does: it is in the books as theirs")
    eq(w:icon("ActionButton2"), "check", "one of the four stacks it was given")
    w:slash("mine Rend")
    check(w:drain():find("The icon for Rend now only looks for your own Rend. Another player's is ignored.", 1, true))
    w:advance(0.3)
    eq(w:icon("ActionButton2"), "check", "and now it does not again")
    w:slash("mine Sunder Armor")
    w:drain()
    eq(ns.db.spells["Sunder Armor"].shared, false)
    w:removeAura(boar, "Sunder Armor")
    for _ = 1, 5 do
        w:applyAura(boar, "Sunder Armor", 30, false, nil, nil, { shared = true, stacks = 5 })
    end
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "the other way round: theirs no longer counts for Sunder Armor")
    w:slash("auto Sunder Armor")
    w:drain()
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "back to what the tooltip says: theirs counts, and it is five of five")

    w:slash("help")
    local help = w:drain()
    check(help:find("/se stacks <skill> <number | auto> - sets the most stacks a skill's effect can have", 1, true), help)
    check(help:find("/se anyone <skill> | mine <skill> - counts another player's effect like your own, or ignores it",
        1, true), help)
    Clean(w)
end)

test("/se mine in the middle of a fight drops another player's effect from the books", function()
    local w, ns, boar, warrior = Party(nil, DEMO, REND)
    Open(w)
    w:partyCast(warrior, DEMO)
    w:advance(0.3)
    w:cast(REND)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross", "their shout")
    eq(w:icon("ActionButton2"), "cross", "your Rend")
    w:slash("mine Demoralizing Shout")
    w:drain()
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "theirs no longer counts, and nothing can be read to say so")
    eq(w:icon("ActionButton2"), "cross", "what is yours stays")
    w:partyCast(warrior, DEMO)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "and their next one is not followed")
    w:cast(DEMO)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross", "your own is")
    w:slash("mine Demoralizing Shout")
    w:drain()
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "and saying it again takes nothing of yours away")
    Clean(w)
end)

test("others: two other players' copies of one effect: the one that lasts longest counts", function()
    for order = 1, 2 do
        local w, ns, boar = Party(nil, DEMO)
        local first, second = order == 1 and 12 or 40, order == 1 and 40 or 12
        w:applyAura(boar, "Demoralizing Shout", first, false, nil, nil, { caster = "one warrior" })
        w:applyAura(boar, "Demoralizing Shout", second, false, nil, nil, { caster = "another" })
        w:advance(0.3)
        eq(w:icon("ActionButton1"), "cross")
        local left
        for _, effect in ipairs(ns.Tracker:Describe(ns.Now())) do
            left = effect.left
        end
        check(left and left > 39 and left < 40, "it is the longer one that is followed: " .. tostring(left))
        Clean(w)
    end
end)

test("others: when another player's copy ends says nothing about your spell", function()
    local w, ns, boar = Party(nil, DEMO, REND)
    w:applyAura(boar, "Demoralizing Shout", 20, false)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross")
    Open(w)
    w:advance(20)
    eq(w:icon("ActionButton1"), "check", "theirs ran out when the game said it would")
    eq(ns.db.learned["Demoralizing Shout"].due, nil, "which is not put down as your spell's effect ending on time")

    -- They renew it unseen, so it does not end when it was read to.
    w:leaveCombat()
    w:applyAura(boar, "Demoralizing Shout", 20, false)
    w:advance(0.3)
    Open(w)
    boar.auras[1].expirationTime = boar.auras[1].expirationTime + 30
    w:advance(22)
    eq(ns.db.learned["Demoralizing Shout"].late, nil, "nor as one that went unreported")
    Clean(w)
end)

test("others: where the game reports no changes, a group member's cast is not taken to have landed, though yours is", function()
    local doubt = { doubt = { player = BUILD, target = BUILD, softenemy = BUILD, plate = BUILD } }
    local w, ns, boar, warrior = Party({ saved = doubt, auraEvents = "calm" }, DEMO, REND)
    Open(w)
    w:partyCast(warrior, DEMO)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "check", "nothing is taken on trust for a cast that is not yours")
    eq(ns.db.report.others.followed, 0, "there was no unit to wait for")
    w:cast(DEMO)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross", "your own is taken to land where nothing can be seen")
    Clean(w)
end)

test("others: a change that went to a group member's cast is not taken back by a cast of yours announced after it", function()
    local w, ns, boar, warrior = Party(nil, DEMO, REND)
    Open(w)
    -- Rend is sent, their shout lands a moment later, and then Rend is
    -- announced, and has missed.
    w.effects[#w.effects + 1] = { at = w.clock + 0.1, run = function()
        w:partyCast(warrior, DEMO)
    end }
    w:cast(REND, { miss = true, castTime = 0.2 })
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross", "their shout")
    eq(w:icon("ActionButton2"), "check", "which does not pass for your Rend")
    Clean(w)
end)

test("others: a skill with no tooltip to read counts as your own until you say otherwise", function()
    local w = World()
    w:addSpell(900, { name = "Mystery Mark", harmful = true })
    w:addButton("ActionButton1", 1, 900)
    local ns = w:load()
    local boar = w:addMob("Boar")
    w:target(boar)
    w:advance(0.3)
    w:slash("track Mystery Mark")
    w:applyAura(boar, "Mystery Mark", 30, false)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "another player's, and nothing says a unit carries it only once")
    w:slash("anyone Mystery Mark")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross")
    w:drain()
    Clean(w)
end)

test("others: an effect of yours that is not on the books is still told from another player's when casts are counted", function()
    -- A client that lets your effects on the enemy be counted in a fight. The
    -- boar carries your Rend, a bleed of yours that no skill on the bars
    -- stands for, and another warrior's shout.
    local w, ns, boar = Party({ combatAuras = "ids" }, DEMO, REND, MARK)
    w:applyAura(boar, "Demoralizing Shout", 45, false)
    w:advance(0.3)
    w:cast(REND)
    w:advance(1)
    w:applyAura(boar, "Deep Wounds", 12, true)
    w:advance(1)
    w:cast(MARK, { miss = true })
    w:advance(3.5)
    local casts = ns.db.report.casts
    check(casts[#casts]:find("Hunter's Mark", 1, true) and casts[#casts]:find("unclear", 1, true),
        "two effects of yours and one on the books: the count cannot say the Mark missed. " .. casts[#casts])
    Clean(w)
end)

test("/se when says and sets when the icons appear", function()
    local w, ns = Simple()
    w:drain()
    w:slash("when")
    local said = w:drain()
    check(said:find("The icons appear always.", 1, true), "with nothing after it, it says how things are: " .. said)
    check(said:find("To change that, type /se when always, /se when combat", 1, true), "and how to change them: " .. said)
    check(said:find("/se when combat (when you are in combat) or /se when group (when you or your group are in combat).",
        1, true), "in the words on the buttons of the settings: " .. said)

    w:slash("when group")
    eq(ns.db.appear, "group")
    check(w:drain():find("The icons now appear when you or your group are in combat.", 1, true))
    w:slash("when combat")
    eq(ns.db.appear, "combat")
    check(w:drain():find("The icons now appear when you are in combat.", 1, true))
    w:slash("when party")
    eq(ns.db.appear, "group", "party is another word for the group")
    w:slash("when combat")
    w:slash("when raid")
    eq(ns.db.appear, "group", "and so is raid")
    w:drain()

    w:slash("when sometimes")
    eq(ns.db.appear, "group", "a word it does not know changes nothing")
    check(w:drain():find("type /se when always, /se when combat (when you are in combat) or /se when group", 1, true))
    w:slash("when target")
    eq(ns.db.appear, "group", "nor does the choice that earlier versions had")
    check(w:drain():find("type /se when always, /se when combat (when you are in combat) or /se when group", 1, true),
        "it is told the three there are")
    eq(ns.SetAppear("target"), false, "and nothing else in the addon can set that choice either")
    eq(ns.db.appear, "group")
    w:slash("")
    local help = w:drain()
    check(help:find("/se when <always | combat | group> - sets when the icons appear", 1, true),
        "the list of commands names the same three: " .. help)
    w:slash("when ALWAYS")
    eq(ns.db.appear, "always", "capitals do not matter")

    w:slash("off")
    w:drain()
    w:slash("on")
    check(w:drain():find("The icons are on. They appear always, and only on skills you can use right now.", 1, true),
        "/se on says when to expect them")
    Clean(w)
end)

test("a saved choice of when that makes no sense goes back to the default", function()
    for _, bad in ipairs({ "sometimes", 7, false }) do
        local w = World()
        w:addButton("ActionButton1", 1, REND)
        local ns = w:load({ appear = bad })
        eq(ns.db.appear, "group", "saved as " .. tostring(bad))
        Clean(w)
    end
end)

test("icons that an earlier version showed when targeting an enemy now show when you or your group are in combat", function()
    -- "When targeting an enemy" was the default until 0.3.8, so this is what
    -- most saved settings hold.
    local w = World()
    w:addButton("ActionButton1", 1, REND)
    w:addButton("ActionButton3", 3, SHOUT)
    local ns = w:load({ appear = "target", version = 2, corner = "BOTTOM" })
    eq(ns.db.appear, "group", "the part of the old choice that is kept: all through a fight")
    eq(ns.db.corner, "BOTTOM", "the other settings are left alone")
    eq(w:drain(), "", "and nothing is said about it in chat")

    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil, "an enemy targeted before the fight no longer brings the icons up")
    eq(w:icon("ActionButton3"), nil)
    w:cast(REND)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross", "the fight does")
    eq(w:icon("ActionButton3"), "check")

    -- The settings show the choice it became.
    local view = w:openSettings().view
    eq(view.appear.picked, "group")
    eq(view.appear.buttons.target, nil, "and no longer offer the old one")
    Clean(w)
end)

--------------------------------------------------------------------------------
-- Immune enemies
--
-- An enemy that is immune to a skill's effect is no reason to use the skill:
-- it is left out when the skill is judged, and with nobody else to judge it
-- on that is the red X. An enemy is only taken to be immune on the game's own
-- word, said of it in the very moment a cast of yours went to it.
--------------------------------------------------------------------------------

--- A world with Rend, Sunder Armor and Demoralizing Shout on the first three
--- buttons, a fire elemental that is immune to Rend targeted with its
--- nameplate showing, and reports known to arrive.
local function Elemental(options)
    options = options or {}
    options.saved = options.saved or Proven()
    local w, ns = Bar(options, REND, SUNDER, DEMO)
    local elemental = w:addMob("Fire Elemental", { immune = { Rend = true } })
    w:showPlate(elemental)
    w:target(elemental)
    w:advance(0.3)
    return w, ns, elemental
end

--- What a session finds saved when reports are known to arrive and the
--- skills on these bars have long been seen to leave their effects: a cast
--- or two that leave nothing do not cost one of them its icon.
local function Seasoned()
    local saved = Proven()
    saved.learned = {
        Rend = { casts = 12, hits = 12 },
        ["Sunder Armor"] = { casts = 12, hits = 12 },
        ["Thunder Clap"] = { casts = 12, hits = 12 },
    }
    return saved
end

--- What the addon keeps of a kind of creature being immune to a spell.
local function Kept(ns, spell, mob)
    local kinds = ns.db.immune[spell]
    return kinds and kinds["#" .. mob.kind] or nil
end

--- The last line of a list in the saved report, or "".
local function Last(lines)
    return lines and lines[#lines] or ""
end

--- Another creature walks up: in sight, and targeted.
local function Meet(w, name, fields)
    local mob = w:addMob(name, fields)
    w:showPlate(mob)
    w:target(mob)
    w:advance(0.3)
    return mob
end

test("immune: an enemy the game calls immune to a skill gets the red X on it, and its kind after the second time", function()
    local w, ns, elemental = Elemental()
    eq(w:icon("ActionButton1"), "check", "nothing is known of it yet")
    w:cast(REND)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "the game said it is immune: casting Rend again changes nothing")
    eq(w:icon("ActionButton2"), "check", "which says nothing of Sunder Armor")
    eq(w:icon("ActionButton3"), "check")
    eq(Booked(ns, "Rend"), nil, "no Rend is on it")
    local report = ns.db.report
    check(Last(report.casts):find("Rend (debuff, hidden, waited for a report): immune; the game said IMMUNE", 1, true),
        Last(report.casts))
    eq(report.verdicts.immune, 1)
    check(Last(report.combat.immune):find("in the moment of Rend, said just after the cast was announced: taken as its "
        .. "answer", 1, true), Last(report.combat.immune))
    check(Last(report.combat.learned):find("Rend on Fire Elemental: immune for now, and for good once it is said of "
        .. "its kind again", 1, true), Last(report.combat.learned))
    eq(Kept(ns, "Rend", elemental).seen, 1)
    eq(Kept(ns, "Rend", elemental).name, "Fire Elemental")
    eq(report.combat.target.heard, 1)
    eq(report.combat.plate.heard, 1, "said once for each name the enemy goes by")
    eq(report.combat.words.IMMUNE, 2)
    check(report.combat.listening > 40, "listened for on your target, your soft target and the nameplates")
    eq(report.combat.kinds.calm.number, 1, "and the game named the elemental's kind by its number")

    -- One word is not counted on for long: an immunity can pass.
    w:advance(11)
    eq(w:icon("ActionButton1"), "cross", "eleven seconds on")
    w:advance(1.5)
    eq(w:icon("ActionButton1"), "check", "and after twelve the skill is worth a try again")

    w:cast(REND)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross")
    eq(Kept(ns, "Rend", elemental).seen, 2, "said again after that while: that is its kind")
    check(Last(report.combat.learned):find("its kind is counted on as immune from now on (said 2 times)", 1, true),
        Last(report.combat.learned))
    w:advance(60)
    eq(w:icon("ActionButton1"), "cross", "and it stays")

    -- The next one of its kind is known for it before the first cast.
    Meet(w, "Fire Elemental", { immune = { Rend = true } })
    eq(w:icon("ActionButton1"), "cross", "another fire elemental")
    eq(w:icon("ActionButton2"), "check")
    Meet(w, "Boar")
    eq(w:icon("ActionButton1"), "check", "a boar is another kind of creature")
    w:cast(REND)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross", "and bleeds")
    check(Booked(ns, "Rend"), "Rend is on the boar")
    Clean(w)
end)

test("immune: two creatures of a kind, each called immune once, make it their kind", function()
    local w, ns, first = Elemental()
    w:cast(REND)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross")
    local second = Meet(w, "Fire Elemental", { immune = { Rend = true } })
    eq(w:icon("ActionButton1"), "check", "one word about the first is not counted on for the second")
    w:cast(REND)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross")
    eq(Kept(ns, "Rend", second).seen, 2)
    w:advance(20)
    eq(w:icon("ActionButton1"), "cross", "long after the one word about it: its kind is known now")
    w:target(first)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "and so is the first one's")
    Clean(w)
end)

test("immune: said again of the same enemy within the first while, it is one occasion and not two", function()
    local w, ns, elemental = Elemental()
    w:cast(REND)
    w:advance(5)
    w:cast(REND) -- through the red X
    w:advance(0.3)
    eq(Kept(ns, "Rend", elemental).seen, 1, "the same shield could be up both times")
    check(Last(ns.db.report.combat.learned):find("Rend on Fire Elemental: said again of the same enemy", 1, true),
        Last(ns.db.report.combat.learned))
    w:advance(11)
    eq(w:icon("ActionButton1"), "cross", "the while starts over with the second word")
    w:advance(1.5)
    eq(w:icon("ActionButton1"), "check")
    Clean(w)
end)

test("immune: a cast that leaves nothing is not taken for immunity without the game's word", function()
    -- A client that does not say what a cast did to an enemy.
    local w, ns = Elemental({ saved = Seasoned(), combatWords = "none" })
    for cast = 1, 5 do
        w:cast(REND)
        w:advance(2)
        eq(w:icon("ActionButton1"), "check", "cast " .. cast .. " showed nothing, as a miss does")
    end
    eq(next(ns.db.immune), nil, "nothing is kept of it")
    eq(#ns.Tracker:Immunities(ns.Now()), 0)
    local report = ns.db.report
    eq(report.verdicts.immune, nil)
    check(report.combat.listening > 40, "the addon was listening")
    eq(report.combat.target.heard, 0, "and heard nothing")
    Clean(w)
end)

test("immune: a miss, a dodge or a resist is the game's word for a cast that left nothing, and not immunity", function()
    local w, ns = Simple({ saved = Seasoned() })
    w:cast(REND)
    w:advance(22)
    local report
    for _, word in ipairs({ "MISS", "DODGE", "PARRY", "RESIST", "EVADE", "DEFLECT" }) do
        w:cast(REND, { miss = true, word = word })
        w:advance(2)
        eq(w:icon("ActionButton1"), "check", word)
        report = ns.db.report
        check(Last(report.casts):find("Rend (debuff, hidden, waited for a report): silent; the game said " .. word,
            1, true), Last(report.casts))
    end
    eq(next(ns.db.immune), nil)
    eq(report.combat.words.DODGE, 2, "heard under both of the boar's names")
    eq(#report.combat.immune, 0)
    eq(#report.combat.learned, 0)

    -- A hit says nothing either way, and is not passed on at all.
    w:cast(REND)
    w:said(w.tokens.target, "WOUND", "CRITICAL")
    w:advance(0.5)
    check(Last(report.casts):find("Rend (debuff, hidden, waited for a report): changed, 0.00s after the cast", 1, true),
        Last(report.casts))
    check(not Last(report.casts):find("the game said", 1, true), Last(report.casts))
    eq(report.combat.words.WOUND, 2)
    Clean(w)
end)

test("immune: an enemy seen to carry the effect after all is not immune, and its kind is never counted as immune again", function()
    local w, ns, elemental = Elemental()
    w:cast(REND)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross")
    eq(Kept(ns, "Rend", elemental).seen, 1)

    -- It was a shield, and the shield is gone.
    elemental.immune = nil
    w:advance(12.5)
    eq(w:icon("ActionButton1"), "check")
    w:cast(REND)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross", "Rend is on it now")
    check(Booked(ns, "Rend"), "in the books")
    eq(Kept(ns, "Rend", elemental).passes, true, "what was kept of its kind now says that its immunity comes and goes")
    eq(Kept(ns, "Rend", elemental).seen, nil)
    local report = ns.db.report
    check(Last(report.combat.learned):find("Rend on Fire Elemental: seen to carry it after all, so its kind is not "
        .. "counted as immune", 1, true), Last(report.combat.learned))
    w:advance(21.5)
    eq(w:icon("ActionButton1"), "check", "Rend has run out")

    -- The shield is up again. Of an enemy that has carried the effect, nothing is kept.
    elemental.immune = { Rend = true }
    w:cast(REND)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "this will pass, so the skill stays worth a try")
    check(Last(report.combat.learned):find("Rend on Fire Elemental: it has carried the effect before, so this will "
        .. "pass: nothing kept", 1, true), Last(report.combat.learned))
    eq(#ns.Tracker:Immunities(ns.Now()), 0)

    -- Nor of another one of its kind, shielded from the first cast on.
    Meet(w, "Fire Elemental", { immune = { Rend = true } })
    for cast = 1, 2 do
        w:cast(REND)
        w:advance(0.3)
        eq(w:icon("ActionButton1"), "check", "cast " .. cast .. " at the second one")
        check(Last(report.combat.learned):find("Rend on Fire Elemental: its kind has carried the effect before, so "
            .. "this will pass: nothing kept", 1, true), Last(report.combat.learned))
        w:advance(13)
    end
    eq(#ns.Tracker:Immunities(ns.Now()), 0)
    w:slash("immune")
    check(w:drain():find("No enemy has been found immune to one of your skills yet.", 1, true),
        "/se immune does not list a kind whose immunity comes and goes")
    Clean(w)

    -- And that is kept for the sessions after this one.
    local saved = w.env.StatusEfficiencyDB
    local w2, ns2, later = Elemental({ saved = saved })
    for cast = 1, 2 do
        w2:cast(REND)
        w2:advance(0.3)
        eq(w2:icon("ActionButton1"), "check", "next session, cast " .. cast)
        w2:advance(13)
    end
    eq(Kept(ns2, "Rend", later).passes, true)
    Clean(w2)
end)

test("immune: a kind counted on as immune is given up the moment the skill is seen to land on one", function()
    local saved = Proven()
    saved.immune = { Rend = { ["#1001"] = { seen = 2, name = "Fire Elemental" } } }
    local w, ns, elemental = Elemental({ saved = saved })
    eq(elemental.kind, 1001)
    elemental.immune = nil -- these do bleed after all
    eq(w:icon("ActionButton1"), "cross", "known for it from an earlier session")
    w:cast(REND) -- through the red X
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross", "now because Rend is on it")
    check(Booked(ns, "Rend"), "in the books")
    eq(Kept(ns, "Rend", elemental).passes, true)
    w:advance(21.5)
    eq(w:icon("ActionButton1"), "check", "and when it has run out the skill is worth casting again")
    Meet(w, "Fire Elemental")
    eq(w:icon("ActionButton1"), "check", "on the next one of its kind as well")
    Clean(w)
end)

test("immune: an enemy with the effect on it, whoever put it there, is not immune to it", function()
    local w, ns, elemental = Elemental()
    ns.SetAppear("always")
    elemental.immune = nil
    -- Not in a fight, where effects can be read: a Rend of yours is on the
    -- elemental that no cast was seen to leave there.
    w:applyAura(elemental, "Rend", 21, true)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross", "read off the elemental")
    w:advance(21.5)
    eq(w:icon("ActionButton1"), "check", "and gone again")

    -- So when the game calls it immune to Rend later, that will pass.
    elemental.immune = { Rend = true }
    w:cast(REND)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check")
    eq(#ns.Tracker:Immunities(ns.Now()), 0)
    eq(Kept(ns, "Rend", elemental).passes, true)
    check(Last(ns.db.report.combat.learned):find("Rend on Fire Elemental: it has carried the effect before, so this "
        .. "will pass: nothing kept", 1, true), Last(ns.db.report.combat.learned))

    -- A kind like that is not one of the immune ones /se immune forget counts.
    w:slash("immune forget")
    check(w:drain():find("The list of immune enemies was already empty.", 1, true), "none was kept as immune")
    eq(next(ns.db.immune), nil, "though what was kept of it is gone with the rest")
    Clean(w)
end)

test("immune: someone else's cast of the skill seen to land on an enemy shows that it is not immune", function()
    local w, ns, boar, warrior = Party(nil, REND, SUNDER)
    boar.immune = { ["Sunder Armor"] = true }
    w:cast(SUNDER)
    w:advance(0.3)
    eq(w:icon("ActionButton2"), "cross", "the game called the boar immune to your Sunder Armor")
    eq(#ns.Tracker:Immunities(ns.Now()), 1)

    -- Whatever shielded it is gone, and the other warrior's Sunder Armor lands.
    boar.immune = nil
    w:advance(2)
    w:partyCast(warrior, SUNDER)
    w:advance(0.3)
    check(Booked(ns, "Sunder Armor"), "theirs is on the boar")
    eq(#ns.Tracker:Immunities(ns.Now()), 0, "so the boar is not immune to it")
    eq(w:icon("ActionButton2"), "check", "one of five: yours would add a stack")
    eq(Kept(ns, "Sunder Armor", boar).passes, true, "and its kind is known for an immunity that comes and goes")
    Clean(w)
end)

test("immune: a change on an enemy that died in the moment of the cast does not show that its kind takes the effect", function()
    local w, ns, first = Elemental({ saved = Seasoned() })
    first.immune = nil
    -- Somebody else's effect is on the elemental. Rend leaves nothing, and
    -- the elemental dies in that frame: all its effects go, which a client
    -- that does not say what changed reports like a cast landing.
    w:applyAura(first, "Corruption", 18, false)
    w:advance(1)
    w:cast(REND, { miss = true, word = false })
    w:kill(first)
    w:advance(2)
    w:hidePlate(first)

    -- The next one of its kind is immune, and the game's word for that counts.
    local second = Meet(w, "Fire Elemental", { immune = { Rend = true } })
    eq(w:icon("ActionButton1"), "check")
    w:cast(REND)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross")
    eq(Kept(ns, "Rend", second).seen, 1)
    eq(Kept(ns, "Rend", second).passes, nil)
    Clean(w)
end)

test("immune: a kind seen to carry the effect is not learned as immune from one of its kind that is called immune", function()
    local w, ns, first = Elemental()
    first.immune = nil
    w:cast(REND)
    w:advance(0.5)
    check(Booked(ns, "Rend"), "Rend is on the first fire elemental")
    eq(next(ns.db.immune), nil, "nothing to keep yet: nobody called one of them immune")

    -- Another of its kind has a shield up.
    local second = Meet(w, "Fire Elemental", { immune = { Rend = true } })
    local report = ns.db.report
    for cast = 1, 2 do
        w:cast(REND)
        w:advance(0.3)
        eq(w:icon("ActionButton1"), "check", "cast " .. cast .. ": its kind takes Rend, so this will pass")
        check(Last(report.combat.learned):find("Rend on Fire Elemental: its kind has carried the effect before, so "
            .. "this will pass: nothing kept", 1, true), Last(report.combat.learned))
        w:advance(13)
    end
    eq(#ns.Tracker:Immunities(ns.Now()), 0)
    eq(Kept(ns, "Rend", second).passes, true, "and that is kept for later sessions")
    Clean(w)
end)

test("immune: /se debug names six of the enemies taken to be immune and counts the rest", function()
    local w, ns = Bar({ saved = Proven() }, CLAP)
    local all = {}
    for i = 1, 8 do
        all[i] = w:addMob("Stone Elemental", { immune = { ["Thunder Clap"] = true } })
        w:showPlate(all[i])
    end
    w:target(all[1])
    w:advance(0.5)
    w:cast(CLAP, { hits = all })
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "nobody here will ever have it")
    eq(#ns.Tracker:Immunities(ns.Now()), 8)
    w:slash("debug")
    local debug = w:drain()
    local _, named = debug:gsub("Thunder Clap: Stone Elemental is taken to be immune", "")
    eq(named, 6)
    check(debug:find("    and 2 more", 1, true), debug)
    Clean(w)
end)

test("immune: a skill that hits every enemy leaves the immune ones out", function()
    local w, ns = Bar({ saved = Proven() }, CLAP, REND)
    local kobolds = { w:addMob("Kobold"), w:addMob("Kobold") }
    local elemental = w:addMob("Stone Elemental", { immune = { ["Thunder Clap"] = true } })
    local all = { kobolds[1], kobolds[2], elemental }
    for i = 1, #all do
        w:showPlate(all[i])
    end
    w:target(kobolds[1])
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "check")

    w:cast(CLAP, { hits = all })
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "both kobolds have it, and the elemental was called immune")
    local report = ns.db.report
    check(Last(report.casts):find("Thunder Clap (debuff, hidden, waited for a report): changed x2, immune, 0.00s after "
        .. "the cast; the game said IMMUNE", 1, true), Last(report.casts))
    eq(Kept(ns, "Thunder Clap", elemental).seen, 1)

    -- One word is not counted on for long, and then one enemy of three is without it.
    w:advance(12.5)
    eq(w:icon("ActionButton1"), "partial", "the elemental is worth a try again")
    w:cast(CLAP, { hits = all })
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross")
    eq(Kept(ns, "Thunder Clap", elemental).seen, 2, "said again: that is its kind")
    w:advance(29)
    eq(w:icon("ActionButton1"), "cross", "for as long as the kobolds carry it")
    w:advance(1.5)
    eq(w:icon("ActionButton1"), "check", "it has run out on the kobolds: worth casting for them")

    -- Another of its kind joins the fight, and is left out from the start.
    local second = w:addMob("Stone Elemental", { immune = { ["Thunder Clap"] = true } })
    second.engaged = true
    w:showPlate(second)
    all[#all + 1] = second
    w:cast(CLAP, { hits = all })
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "two kobolds with it, two elementals that never will have it")
    eq(#report.combat.learned, 2, "said of a kind that is counted on already: nothing new to note")

    -- With only immune enemies left, there is nobody to cast it for.
    w:kill(kobolds[2])
    w:kill(kobolds[1])
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "only the elementals are left")
    w:target(elemental)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross")
    eq(w:icon("ActionButton2"), "check", "Rend is another matter: nothing was said of it")
    Clean(w)
end)

test("immune: an effect that stacks shows the red X on an immune enemy, not the check of a stack to add", function()
    local w, ns = Bar({ saved = Proven() }, SUNDER, ROAR)
    local golem = Meet(w, "Iron Golem", { immune = { ["Sunder Armor"] = true, ["Searing Roar"] = true } })
    eq(w:icon("ActionButton1"), "check")
    w:cast(SUNDER)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "no stack will ever be on it")
    eq(Stacks(ns, "Sunder Armor"), 0)

    -- An area skill that stacks: the golem is left out, and the kobold decides.
    local kobold = w:addMob("Kobold")
    w:showPlate(kobold)
    w:advance(0.3)
    local both = { golem, kobold }
    w:cast(ROAR, { hits = both })
    w:advance(0.3)
    eq(w:icon("ActionButton2"), "check", "one of two on the kobold: another cast adds a stack there")
    w:cast(ROAR, { hits = both })
    w:advance(0.3)
    eq(w:icon("ActionButton2"), "cross", "two of two on the kobold, and the golem never will have any")
    Clean(w)
end)

test("immune: the game's word counts only in the moment of a cast of yours at that enemy", function()
    local w, ns, boar, warrior = Party({ saved = Seasoned() }, REND, SUNDER)
    Open(w)
    local report = ns.db.report

    -- Someone else's attack is called immune, a while after a cast of yours.
    w:said(boar, "IMMUNE")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check")
    check(Last(report.combat.immune):find("2.00s after Rend, too far from it to be its answer", 1, true),
        Last(report.combat.immune))

    -- And with no cast of yours anywhere near.
    w:advance(6)
    w:said(boar, "IMMUNE")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check")
    check(Last(report.combat.immune):find("with no cast of yours at that enemy", 1, true), Last(report.combat.immune))

    -- Two frames after a cast of yours that showed nothing is too late to be its answer.
    w:cast(REND, { miss = true, word = false })
    w:advance(0.1)
    w:said(boar, "IMMUNE")
    w:advance(2)
    eq(w:icon("ActionButton1"), "check")
    check(Last(report.combat.immune):find("0.10s after Rend, too far from it to be its answer", 1, true),
        Last(report.combat.immune))

    -- And two frames before one is too early.
    w:said(boar, "IMMUNE")
    w:advance(0.1)
    w:cast(REND, { miss = true, word = false })
    w:advance(2)
    eq(w:icon("ActionButton1"), "check")
    check(Last(report.combat.immune):find("0.10s before Rend, too far from it to be its answer", 1, true),
        Last(report.combat.immune))

    -- The other warrior's Rend is refused by an enemy that is immune to it. Yours was not cast.
    local elemental = Meet(w, "Fire Elemental", { immune = { Rend = true } })
    warrior.target = elemental
    w:advance(6)
    w:partyCast(warrior, REND)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "the game did not say that of a cast of yours")
    check(Last(report.combat.immune):find("with no cast of yours at that enemy", 1, true), Last(report.combat.immune))

    eq(next(ns.db.immune), nil, "nothing was learned from any of it")
    eq(#ns.Tracker:Immunities(ns.Now()), 0)
    eq(#report.combat.learned, 0)
    eq(report.verdicts.immune, nil)
    Clean(w)
end)

test("immune: an enemy that changed in the moment it was called immune leaves open what your cast did", function()
    for _, first in ipairs({ "cast", "word" }) do
        local w, ns, boar = Party(nil, REND, SUNDER)
        -- Your Rend lands in the very moment someone else's attack is called immune.
        if first == "word" then
            w:said(boar, "IMMUNE")
        end
        w:cast(REND)
        if first == "cast" then
            w:said(boar, "IMMUNE")
        end
        w:advance(0.3)
        eq(w:icon("ActionButton1"), "cross", "the landing stands, " .. first .. " first")
        check(Booked(ns, "Rend"), "Rend is taken to be on the boar")
        eq(next(ns.db.immune), nil, "and nothing is learned from the word")
        eq(#ns.Tracker:Immunities(ns.Now()), 0)
        local report = ns.db.report
        check(Last(report.combat.immune):find("in the moment of Rend, which was seen to land there just then: left open",
            1, true), Last(report.combat.immune))
        check(Last(report.casts):find("Rend (debuff, hidden, waited for a report): changed, 0.00s after the cast; the "
            .. "game said IMMUNE", 1, true), Last(report.casts))
        eq(report.verdicts.immune, nil)
        local learned = ns.db.learned.Rend
        eq(learned and learned.casts or 0, 0, "nor is the cast counted for Rend or against it, " .. first .. " first")

        -- Nor does that landing prove that the boar takes Rend: the game's
        -- word, said again with nothing to show for the cast, is its answer.
        w:advance(21.5)
        eq(w:icon("ActionButton1"), "check", "Rend ran out")
        boar.immune = { Rend = true }
        w:cast(REND)
        w:advance(0.3)
        eq(w:icon("ActionButton1"), "cross")
        eq(Kept(ns, "Rend", boar).seen, 1)
        Clean(w)
    end
end)

test("immune: a change a frame after the cast still leaves it open, and one after that is too late to", function()
    local w, ns, boar = Party(nil, REND, SUNDER)
    -- Called immune in the frame of the cast, and its effects change in the next.
    boar.immune = { Rend = true }
    w:cast(REND)
    w:advance(0.05)
    w:applyAura(boar, "Mortal Wounds", 10, false)
    w:advance(0.3)
    local report = ns.db.report
    check(Last(report.combat.immune):find("in the moment of Rend, which was seen to land there just then: left open",
        1, true), Last(report.combat.immune))
    eq(next(ns.db.immune), nil, "nothing is learned")
    eq(w:icon("ActionButton1"), "cross", "and the change passes for the landing, as it would without the word")
    Clean(w)

    -- Two frames after: the game's word was the answer, and this is something else.
    w, ns, boar = Party(nil, REND, SUNDER)
    boar.immune = { Rend = true }
    w:cast(REND)
    w:advance(0.1)
    w:applyAura(boar, "Mortal Wounds", 10, false)
    w:advance(0.3)
    report = ns.db.report
    check(Last(report.combat.immune):find("in the moment of Rend, said just after the cast was announced: taken as its "
        .. "answer", 1, true), Last(report.combat.immune))
    eq(Kept(ns, "Rend", boar).seen, 1)
    eq(Booked(ns, "Rend"), nil, "no Rend in the books")
    eq(w:icon("ActionButton1"), "cross", "by the game's word")
    Clean(w)
end)

test("immune: called immune a frame after its effects changed with your cast, an enemy leaves open what the cast did", function()
    local w, ns, boar = Party(nil, REND, SUNDER)
    -- The icons are looked at every frame here, and the frames come faster
    -- than the game's word does: the cast is looked at between the change on
    -- the boar and the word. A cast at an enemy is not judged that soon,
    -- however plainly it showed.
    ns.db.interval = 0.01
    w:cast(REND)
    w:advance(0.04, 0.02)
    w:said(boar, "IMMUNE")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "the landing stands")
    check(Booked(ns, "Rend"), "Rend is taken to be on the boar")
    local report = ns.db.report
    check(Last(report.combat.immune):find("in the moment of Rend, which was seen to land there just then: left open",
        1, true), Last(report.combat.immune))
    check(Last(report.casts):find("Rend (debuff, hidden, waited for a report): changed, 0.00s after the cast; the "
        .. "game said IMMUNE", 1, true), Last(report.casts))
    eq(next(ns.db.immune), nil, "nothing is learned from the word")
    eq(report.verdicts.immune, nil)

    -- Nor from the change: the boar is not known to take Rend. Called immune
    -- again with nothing to show for the cast, that is the cast's answer.
    w:advance(21.5)
    eq(w:icon("ActionButton1"), "check", "Rend ran out")
    boar.immune = { Rend = true }
    w:cast(REND)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross")
    eq(Kept(ns, "Rend", boar).seen, 1)
    Clean(w)
end)

test("immune: where your effects can be counted in a fight, a change that was not yours leaves the game's word standing", function()
    local w, ns, elemental = Elemental({ combatAuras = "ids" })
    -- A count of none is only believed once the fight has shown an effect of
    -- yours through it: Sunder Armor is on the elemental.
    w:cast(SUNDER)
    w:advance(2.5)
    check(Booked(ns, "Sunder Armor"), "Sunder Armor is on it")
    -- Rend is called immune as someone else's effect lands on the elemental.
    -- Counted before and after, it has no new effect of yours: the change
    -- was not the cast landing, and the game said why the cast left nothing.
    w:cast(REND)
    w:applyAura(elemental, "Mortal Wounds", 10, false)
    w:advance(2.5)
    eq(w:icon("ActionButton1"), "cross")
    eq(Booked(ns, "Rend"), nil, "no Rend in the books")
    eq(Kept(ns, "Rend", elemental).seen, 1)
    local report = ns.db.report
    check(Last(report.casts):find("immune", 1, true), Last(report.casts))
    check(Last(report.combat.immune):find("in the moment of Rend, said just after the cast was announced: taken as its "
        .. "answer", 1, true), Last(report.combat.immune))
    local learned = ns.db.learned.Rend
    eq(learned and learned.casts or 0, 0, "and it is not held against Rend as a cast that left nothing")
    Clean(w)
end)

test("immune: called immune in the moment another attack on the enemy missed says nothing of your cast", function()
    for _, first in ipairs({ "cast", "words" }) do
        local w, ns, boar = Party({ saved = Seasoned() }, REND, SUNDER)
        w:cast(REND)
        w:advance(22)
        -- Your Rend is dodged in the very moment someone else's attack is called immune.
        if first == "words" then
            w:said(boar, "IMMUNE")
            w:cast(REND, { miss = true, word = "DODGE", said = "first" })
        else
            w:cast(REND, { miss = true, word = "DODGE" })
            w:said(boar, "IMMUNE")
        end
        w:advance(2)
        eq(w:icon("ActionButton1"), "check", "which of the two words was for the cast is not told, " .. first .. " first")
        eq(next(ns.db.immune), nil)
        eq(#ns.Tracker:Immunities(ns.Now()), 0)
        local report = ns.db.report
        check(Last(report.combat.immune):find("in the moment of Rend, when another attack was turned away there too: "
            .. "left open", 1, true), Last(report.combat.immune))
        check(Last(report.casts):find("Rend (debuff, hidden, waited for a report): silent; the game said DODGE, IMMUNE",
            1, true), Last(report.casts))
        eq(report.verdicts.immune, nil)
        Clean(w)
    end

    -- Whatever the other word was, the two are written on the cast's line in the same order every time.
    for _, word in ipairs({ "MISS", "PARRY", "RESIST", "BLOCK", "ABSORB", "EVADE", "DEFLECT", "REFLECT" }) do
        local w, ns, boar = Party({ saved = Seasoned() }, REND, SUNDER)
        w:cast(REND, { miss = true, word = word })
        w:said(boar, "IMMUNE")
        w:advance(2)
        local both = word < "IMMUNE" and (word .. ", IMMUNE") or ("IMMUNE, " .. word)
        check(Last(ns.db.report.casts):find("; the game said " .. both, 1, true), Last(ns.db.report.casts))
        eq(next(ns.db.immune), nil, word)
        Clean(w)
    end
end)

test("immune: with two casts of yours at an enemy in one moment, neither is taken to be the one that was meant", function()
    for _, order in ipairs({ "both casts, then the word", "the word between the casts", "the word first" }) do
        local w, ns, elemental = Elemental({ saved = Seasoned() })
        if order == "the word first" then
            w:said(elemental, "IMMUNE")
        end
        w:cast(REND, { word = false })
        if order == "the word between the casts" then
            w:said(elemental, "IMMUNE")
        end
        w:cast(SUNDER, { miss = true, word = false })
        if order == "both casts, then the word" then
            w:said(elemental, "IMMUNE")
        end
        w:advance(2)
        eq(w:icon("ActionButton1"), "check", order)
        eq(w:icon("ActionButton2"), "check", order)
        eq(next(ns.db.immune), nil, order)
        eq(#ns.Tracker:Immunities(ns.Now()), 0, order)
        local report = ns.db.report
        check(Last(report.combat.immune):find("in the moment of two casts of yours at that enemy: left open", 1, true),
            order .. ": " .. Last(report.combat.immune))
        eq(#report.combat.immune, 1, "one line for the one word")
        eq(report.verdicts.immune, nil)
        Clean(w)
    end
end)

test("immune: a cast of yours announced a frame after the game's word shares the word with the cast before it", function()
    -- Rend is held to the frame of its cast: a frame later it has nothing
    -- left to wait for. Its cast is kept all the same until the moment of the
    -- game's word is over, for the sake of a second cast in that moment.
    local saved = Seasoned()
    saved.learned.Rend = { casts = 12, hits = 12, prompt = 5, tardy = 0, instant = 5, lag = 0, timed = 3 }
    local w, ns = Elemental({ saved = saved })
    check(Sharp(ns, REND), "Rend is held to the frame of its cast")
    -- The icons are looked at every frame, and the frames come fast: Rend,
    -- the game's word two frames on, and Sunder Armor two frames after that.
    -- The word is in the moment of both casts, which are not in each other's.
    ns.db.interval = 0.01
    w:cast(REND, { said = 0.03 })
    w:advance(0.08, 0.02)
    w:cast(SUNDER, { miss = true, word = false })
    w:advance(2)
    eq(w:icon("ActionButton1"), "check")
    eq(w:icon("ActionButton2"), "check")
    eq(next(ns.db.immune), nil, "it is held against neither")
    eq(#ns.Tracker:Immunities(ns.Now()), 0)
    local report = ns.db.report
    check(Last(report.combat.immune):find("in the moment of two casts of yours at that enemy: left open", 1, true),
        Last(report.combat.immune))
    eq(#report.combat.immune, 1, "one line for the one word")
    eq(report.verdicts.immune, nil)
    Clean(w)
end)

test("immune: the game's word is the cast's answer just before the cast is announced and a frame after it", function()
    local cases = {
        { said = "first", line = "said just before the cast was announced" },
        { said = 0.05, line = "said just after the cast was announced" },
    }
    for _, case in ipairs(cases) do
        local w, ns, elemental = Elemental()
        w:cast(REND, { said = case.said })
        w:advance(0.3)
        eq(w:icon("ActionButton1"), "cross", case.line)
        check(Last(ns.db.report.combat.immune):find("in the moment of Rend, " .. case.line .. ": taken as its answer",
            1, true), Last(ns.db.report.combat.immune))
        eq(Kept(ns, "Rend", elemental).seen, 1)
        Clean(w)
    end

    -- Two frames after it is somebody else's business, as far as can be told.
    local w, ns = Elemental({ saved = Seasoned() })
    w:cast(REND, { said = 0.09 }) -- the frame that starts then
    w:advance(2)
    eq(w:icon("ActionButton1"), "check")
    check(Last(ns.db.report.combat.immune):find("0.10s after Rend, too far from it to be its answer", 1, true),
        Last(ns.db.report.combat.immune))
    eq(next(ns.db.immune), nil)
    Clean(w)
end)

test("immune: a skill that is held to the frame of its cast is answered in that frame too", function()
    local w, ns, boar = Simple({ saved = Proven() })
    for _ = 1, 3 do
        w:cast(REND)
        w:advance(22)
    end
    check(Sharp(ns, REND), "Rend is known to show in the frame of its cast")
    local elemental = Meet(w, "Fire Elemental", { immune = { Rend = true } })
    for _, said in ipairs({ "first", "after", 0.05 }) do
        w:cast(REND, { said = said ~= "after" and said or nil })
        w:advance(0.3)
        eq(w:icon("ActionButton1"), "cross", tostring(said))
        eq(ns.db.report.verdicts.immune, said == "first" and 1 or said == "after" and 2 or 3)
        -- A change on the elemental just after it is not kept as one that
        -- came too late for the cast: the cast has its answer.
        w:applyAura(elemental, "Mortal Wounds", 10, false)
        w:advance(13)
    end
    eq(#ns.db.report.late, 0)
    eq(Kept(ns, "Rend", elemental).seen, 3)
    w:target(boar)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "the boar is no elemental")
    Clean(w)
end)

test("immune: a client that keeps the game's word from addons, or does not send it, learns nothing and breaks nothing", function()
    local cases = {
        { options = { combatWords = "secret" }, heard = 1, unread = 1, listening = true,
            debug = "What the game said attacks did to enemies: heard 4 times, kept secret 4 times. Of those "
                .. "\"immune\": 0." },
        { options = { combatWords = "none" }, heard = 0, unread = 0, listening = true,
            debug = "What the game said attacks did to enemies: heard 0 times, kept secret 0 times. Of those "
                .. "\"immune\": 0." },
        { options = { unknownEvents = { UNIT_COMBAT = true } }, heard = 0, unread = 0, listening = false,
            debug = "This client does not let an addon hear what attacks did to enemies" },
    }
    for _, case in ipairs(cases) do
        case.options.saved = Seasoned()
        local w, ns = Elemental(case.options)
        for _ = 1, 2 do
            w:cast(REND)
            w:advance(2)
            eq(w:icon("ActionButton1"), "check", "nothing told the addon why the cast left nothing")
        end
        eq(next(ns.db.immune), nil)
        local said = ns.db.report.combat
        eq(said.target.heard, case.heard * 2)
        eq(said.target.unread, case.unread * 2)
        eq(said.listening > 0, case.listening)
        eq(next(said.words), nil, "no word could be read")
        w:slash("debug")
        local debug = w:drain()
        check(debug:find(case.debug, 1, true), debug)
        Clean(w)
    end
end)

test("immune: where the game hides what kind of creature an enemy is, only that one enemy is taken to be immune", function()
    local w, ns, first = Elemental({ combatIdentity = false })
    -- Met before the fight, when the game still said what it was.
    w:cast(REND)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross")
    eq(Kept(ns, "Rend", first).seen, 1)

    -- A second one walks into the fight: the game will not say what it is.
    local second = Meet(w, "Fire Elemental", { immune = { Rend = true } })
    eq(w:icon("ActionButton1"), "check")
    w:cast(REND)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "that one enemy, for now")
    eq(Kept(ns, "Rend", first).seen, 1, "nothing is added to what is known of fire elementals")
    local report = ns.db.report
    check(Last(report.combat.learned):find("Rend on an enemy the game does not name: that one enemy is immune for now",
        1, true), Last(report.combat.learned))
    w:advance(12.5)
    eq(w:icon("ActionButton1"), "check", "worth another try after a while")
    w:cast(REND)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross")
    check(Last(report.combat.learned):find("Rend on an enemy the game does not name: that one enemy is immune from "
        .. "now on", 1, true), Last(report.combat.learned))
    -- Said once more a moment later, of a cast through the red X: it stays as it is.
    w:advance(3)
    w:cast(REND)
    w:advance(0.3)
    check(Last(report.combat.learned):find("said again of the same enemy", 1, true), Last(report.combat.learned))
    w:advance(60)
    eq(w:icon("ActionButton1"), "cross", "for as long as it is about")
    eq(report.combat.kinds.calm.number, 1, "the saved report: one enemy named by its number, out of the fight")
    eq(report.combat.kinds.hidden.none, 1, "and one not named at all, in it")
    w:slash("debug")
    local debug = w:drain()
    check(debug:find("Rend: an enemy the game does not name is taken to be immune, for as long as it is about", 1, true),
        debug)
    w:slash("immune rend")
    check(w:drain():find("The game does not say what kind of enemy your target is right now, so nothing was added.",
        1, true),
        "nor can its kind be marked by hand in the middle of the fight")

    -- It bleeds after all, and Rend is used through the red X: seen to land,
    -- the enemy is not taken to be immune any more.
    second.immune = nil
    w:cast(REND)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross", "Rend is on it now")
    check(Booked(ns, "Rend"), "in the books")
    eq(#ns.Tracker:Immunities(ns.Now()), 0)
    w:advance(21.5)
    eq(w:icon("ActionButton1"), "check", "and when Rend has run out it is worth casting again")
    Clean(w)
end)

test("immune: where the game tells only an enemy's name in a fight, its kind goes by that name", function()
    local w, ns = Elemental({ combatIdentity = "names" })
    Open(w) -- the fight starts
    for nth = 1, 2 do
        Meet(w, "Lava Spawn", { immune = { Rend = true } })
        eq(w:icon("ActionButton1"), "check", "lava spawn " .. nth)
        w:cast(REND)
        w:advance(0.3)
        eq(w:icon("ActionButton1"), "cross")
        eq(ns.db.immune.Rend["Lava Spawn"].seen, nth)
    end
    Meet(w, "Lava Spawn", { immune = { Rend = true } })
    eq(w:icon("ActionButton1"), "cross", "the third one is known by its name")
    eq(ns.db.report.combat.kinds.hidden.name, 3)
    w:slash("immune")
    local list = w:drain()
    check(list:find("  Rend: Lava Spawn", 1, true), list)
    Clean(w)
end)

test("immune: where the game hides its own name for an enemy in a fight and still tells its number, the kind goes by the number", function()
    local w, ns = Elemental({ combatIdentity = "ids" })
    Open(w) -- the fight starts
    local spawn = Meet(w, "Lava Spawn", { immune = { Rend = true } })
    w:cast(REND)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross")
    eq(Kept(ns, "Rend", spawn).seen, 1)
    eq(Kept(ns, "Rend", spawn).name, "Lava Spawn")
    eq(ns.db.report.combat.kinds.hidden.number, 1, "named by its number, in the fight")
    Clean(w)
end)

test("immune: a client without the call for a creature's number reads it off the enemy's own name for the game", function()
    local w, ns, elemental = Elemental({ noCreatureID = true })
    w:cast(REND)
    w:advance(13)
    w:cast(REND)
    w:advance(0.3)
    eq(Kept(ns, "Rend", elemental).seen, 2)
    Meet(w, "Fire Elemental", { immune = { Rend = true } })
    eq(w:icon("ActionButton1"), "cross")
    Clean(w)
end)

test("immune: a player is never a kind of creature", function()
    local w, ns = Bar({ saved = Proven() }, REND, SUNDER)
    local paladin = Meet(w, "Uther", { npc = false, guid = "Player-1-00000777", immune = true })
    eq(w:icon("ActionButton1"), "check")
    w:cast(REND)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "behind a shield, for now")
    eq(w:icon("ActionButton2"), "check", "nothing was said of Sunder Armor")
    eq(next(ns.db.immune), nil, "nothing is kept: the next player is somebody else")
    local report = ns.db.report
    check(Last(report.combat.learned):find("Rend on a player: that one enemy is immune for now", 1, true),
        Last(report.combat.learned))
    eq(report.combat.kinds.calm.none + report.combat.kinds.hidden.none, 0, "a player is not counted as a creature "
        .. "the game would not name")
    w:slash("immune rend")
    check(w:drain():find("Your target is a player. Only creatures can be added as immune to a skill.", 1, true),
        "nor can a player be marked by hand")

    paladin.immune = nil -- the shield is gone
    w:advance(12.5)
    eq(w:icon("ActionButton1"), "check")
    w:cast(REND)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross", "Rend is on them")
    check(Booked(ns, "Rend"), "in the books")
    Clean(w)
end)

test("immune: what is known of one enemy only is dropped when it has not been seen for ten minutes", function()
    local w, ns = Bar({ saved = Proven() }, REND, SUNDER)
    local paladin = Meet(w, "Uther", { npc = false, guid = "Player-1-00000777", immune = true })
    w:cast(REND)
    w:advance(13)
    w:cast(REND)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "said twice of that one enemy")
    w:advance(700)
    eq(w:icon("ActionButton1"), "cross", "and it stays while they are about, however long")
    eq(#ns.Tracker:Immunities(ns.Now()), 1)

    w:target(nil)
    w:hidePlate(paladin)
    w:leaveCombat()
    w:advance(300)
    eq(#ns.Tracker:Immunities(ns.Now()), 1, "five minutes out of sight")
    w:advance(340)
    eq(#ns.Tracker:Immunities(ns.Now()), 0, "after ten it is forgotten")
    w:showPlate(paladin)
    w:target(paladin)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check")
    Clean(w)
end)

test("/se immune lists what was learned, marks a kind by hand and forgets", function()
    local w, ns, elemental = Elemental()
    w:slash("help")
    local help = w:drain()
    check(help:find("/se immune - lists the enemies that are immune to a skill", 1, true), help)
    check(help:find("/se immune forget [skill] - clears the list", 1, true), help)
    w:slash("immune")
    check(w:drain():find("No enemy has been found immune to one of your skills yet. When the game says \"Immune\" as "
        .. "you use a skill on an enemy, the addon remembers it", 1, true), "nothing to list yet")

    w:cast(REND)
    w:advance(0.3)
    w:slash("immune")
    local list = w:drain()
    check(list:find("No kind of enemy counts as immune to one of your skills yet.", 1, true), list)
    check(list:find("Seen immune once so far. These count as immune when the game says so a second time:", 1, true),
        list)
    check(list:find("  Rend: Fire Elemental", 1, true), list)
    w:slash("debug")
    local debug = w:drain()
    check(debug:find("What the game said attacks did to enemies: heard 2 times, kept secret 0 times. Of those "
        .. "\"immune\": 2.", 1, true), debug)
    check(debug:find("Rend: Fire Elemental is taken to be immune, 12s more unless the game says so again", 1, true),
        debug)
    check(debug:find("0 left something, 1 left nothing, 0 could not be judged", 1, true), debug)

    w:advance(13)
    w:cast(REND)
    w:advance(0.3)
    w:slash("immune")
    list = w:drain()
    check(list:find("These enemies are immune to these skills. An icon never tells you to use a skill on an enemy "
        .. "that is immune to it:", 1, true), list)
    check(list:find("  Rend: Fire Elemental", 1, true), list)
    check(not list:find("Seen immune once", 1, true), list)
    check(list:find("Type /se immune forget to clear the list, or /se immune forget <skill> to clear it for one skill.",
        1, true), list)

    -- By hand: the kind you have targeted, for a skill the game has said nothing about.
    eq(w:icon("ActionButton2"), "check")
    w:slash("immune sunder armor")
    check(w:drain():find("You added Fire Elemental to the enemies that are immune to Sunder Armor. It stays on that "
        .. "list until you clear it with /se immune forget Sunder Armor.", 1, true), "it says what it did")
    w:advance(0.3)
    eq(w:icon("ActionButton2"), "cross", "at once")
    eq(Kept(ns, "Sunder Armor", elemental).told, true)
    w:slash("immune")
    list = w:drain()
    check(list:find("  Sunder Armor: Fire Elemental (added by you)", 1, true), list)

    -- What you said stands, even when the skill is seen to land on one.
    local learned = #ns.db.report.combat.learned
    w:cast(SUNDER)
    w:advance(31)
    eq(w:icon("ActionButton2"), "cross", "Sunder Armor landed and ran out, and your word still holds")
    eq(Kept(ns, "Sunder Armor", elemental).told, true)
    eq(Kept(ns, "Sunder Armor", elemental).passes, nil)
    eq(#ns.db.report.combat.learned, learned, "nor is it written down that its kind is not immune after all")
    -- And when the game then calls that one immune, which would pass for any other kind.
    elemental.immune["Sunder Armor"] = true
    w:cast(SUNDER)
    w:advance(0.3)
    eq(w:icon("ActionButton2"), "cross")
    eq(Kept(ns, "Sunder Armor", elemental).told, true)
    eq(Kept(ns, "Sunder Armor", elemental).passes, nil)

    w:slash("immune forget sunder armor")
    check(w:drain():find("The list of enemies immune to Sunder Armor is cleared. It held 1 kind of enemy.", 1, true),
        "it says what it forgot")
    w:advance(0.3)
    eq(w:icon("ActionButton2"), "check")
    eq(w:icon("ActionButton1"), "cross", "Rend's are still kept")
    -- Forgotten with it: that Sunder Armor was seen to land on this one. The
    -- game's word for it counts like a first word again.
    elemental.immune["Sunder Armor"] = true
    w:cast(SUNDER)
    w:advance(0.3)
    eq(w:icon("ActionButton2"), "cross")
    eq(Kept(ns, "Sunder Armor", elemental).seen, 1)
    w:slash("immune forget")
    check(w:drain():find("The list of immune enemies is cleared for every skill. It held 2 kinds of enemy.", 1, true),
        "and all of them")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check")
    eq(next(ns.db.immune), nil)
    eq(#ns.Tracker:Immunities(ns.Now()), 0)

    -- Nothing to mark without an enemy targeted, or for a skill that is not on the bars.
    w:target(nil)
    w:slash("immune rend")
    check(w:drain():find("Target an enemy first.", 1, true), "no target")
    w:target(elemental)
    w:slash("immune no such skill")
    local answer = w:drain()
    check(answer:find("No skill called \"no such skill\" is on your action bars.", 1, true)
        and not answer:find("You added", 1, true), answer)
    eq(next(ns.db.immune), nil)
    Clean(w)
end)

test("/se immune forget with a spell leaves what is known of the other skills", function()
    local w, ns, elemental = Elemental()
    elemental.immune = { Rend = true, ["Sunder Armor"] = true }
    w:cast(REND)
    w:advance(1.5)
    w:cast(SUNDER)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross")
    eq(w:icon("ActionButton2"), "cross")
    eq(#ns.Tracker:Immunities(ns.Now()), 2, "said once of each skill: that one enemy, for now")

    w:slash("immune forget sunder armor")
    check(w:drain():find("The list of enemies immune to Sunder Armor is cleared. It held 1 kind of enemy.", 1, true),
        "it says what it forgot")
    w:advance(0.3)
    eq(w:icon("ActionButton2"), "check")
    eq(w:icon("ActionButton1"), "cross", "what the game said of Rend a moment ago still stands")
    eq(#ns.Tracker:Immunities(ns.Now()), 1)
    eq(Kept(ns, "Rend", elemental).seen, 1)
    eq(ns.db.immune["Sunder Armor"], nil)
    Clean(w)
end)

test("immune: what was learned is kept over a reload, and /se reset forgets it", function()
    local w, ns, elemental = Elemental()
    w:cast(REND)
    w:advance(13)
    w:cast(REND)
    w:advance(0.3)
    eq(Kept(ns, "Rend", elemental).seen, 2)
    Clean(w)

    local saved = w.env.StatusEfficiencyDB
    local w2, ns2 = Elemental({ saved = saved })
    eq(w2:icon("ActionButton1"), "cross", "known before the first cast of the next session")
    eq(w2:icon("ActionButton2"), "check")
    w2:slash("reset")
    w2:drain()
    ns2.SetAppear("always") -- as these scenarios have it
    w2:advance(0.5)
    eq(next(ns2.db.immune), nil)
    eq(w2:icon("ActionButton1"), "check", "everything learned is gone")
    Clean(w2)
end)

test("immune: a kind that was kept without its name gets the name when one of its kind is met", function()
    -- Kept in a session in which the game told the creature's number and not its name.
    local saved = Proven()
    saved.immune = { Rend = { ["#1001"] = { seen = 2 } } }
    local w, ns, elemental = Elemental({ saved = saved })
    eq(elemental.kind, 1001)
    eq(w:icon("ActionButton1"), "cross", "counted on by its number")
    eq(Kept(ns, "Rend", elemental).name, "Fire Elemental")
    w:slash("immune")
    local list = w:drain()
    check(list:find("  Rend: Fire Elemental", 1, true), list)
    Clean(w)
end)

test("immune: saved settings that are not what the addon wrote do no harm", function()
    local broken = {
        "broken", 7, true,
        { Rend = "yes" },
        { Rend = { ["#1001"] = "immune" } },
        { Rend = { ["#1001"] = { seen = "often", name = 5 } } },
        { Rend = { ["#1001"] = { seen = -3, passes = "no", told = "yes" } } },
        { [5] = { x = 1 }, Rend = { [7] = { seen = 9 } } },
    }
    for i = 1, #broken do
        local saved = Proven()
        saved.immune = broken[i]
        local w, ns, elemental = Elemental({ saved = saved })
        eq(w:icon("ActionButton1"), "check", "case " .. i .. ": nothing sound was kept")
        w:slash("immune")
        w:drain()
        w:cast(REND)
        w:advance(13)
        w:cast(REND)
        w:advance(0.3)
        eq(w:icon("ActionButton1"), "cross", "case " .. i .. ": and it is learned as usual")
        eq(Kept(ns, "Rend", elemental).seen, 2, "case " .. i)
        w:slash("immune")
        check(w:drain():find("  Rend: Fire Elemental", 1, true), "case " .. i)
        w:slash("immune forget")
        w:drain()
        Clean(w)
    end
end)

test("immune: a skill with no icon learns nothing from the game's word, and an immune enemy costs no skill its icon", function()
    local w, ns = Bar({ saved = Proven() }, REND, HEROIC, CLAP)
    local ghost = Meet(w, "Restless Ghost", { immune = true })
    eq(w:icon("ActionButton2"), nil, "Heroic Strike leaves nothing behind")
    w:cast(HEROIC)
    w:said(ghost, "IMMUNE")
    w:advance(2)
    eq(next(ns.db.immune), nil, "nothing is kept for a skill that has no icon to show it on")
    eq(w:icon("ActionButton2"), nil)

    -- Rend has only its tooltip to speak for it: three casts that leave nothing cost it its icon.
    -- Not when the game says why they left nothing.
    for _ = 1, 4 do
        w:cast(REND)
        w:advance(13)
    end
    check(w:icon("ActionButton1") ~= nil, "Rend still has its icon")
    local learned = ns.db.learned.Rend
    eq(learned and learned.casts or 0, 0, "an immune enemy says nothing about what the skill leaves on others")
    Meet(w, "Boar")
    eq(w:icon("ActionButton1"), "check")
    Clean(w)
end)

test("immune: where casts are taken to land for want of reports, the game's word takes that back", function()
    -- A client that never reports a unit's effects changing: every cast is taken to have landed.
    local quiet = { doubt = { player = BUILD, target = BUILD, softenemy = BUILD, plate = BUILD } }
    local w, ns, elemental = Elemental({ auraEvents = false, saved = quiet })
    w:cast(REND)
    eq(Booked(ns, "Rend") ~= nil, true, "taken to have landed, as it is cast")
    w:advance(0.3)
    eq(Booked(ns, "Rend"), nil, "the game said otherwise")
    eq(w:icon("ActionButton1"), "cross", "by its word now")
    eq(Kept(ns, "Rend", elemental).seen, 1)
    w:advance(12.5)
    eq(w:icon("ActionButton1"), "check", "and when the word is no longer counted on, the skill is worth a try: "
        .. "nothing is left in the books that would say Rend is on it")
    Clean(w)
end)

test("immune: a buff is never refused, and what the game says of a friend is nobody's immunity", function()
    local w, ns, boar, warrior = Party(nil, REND, BLOCK, SUNDER)
    Open(w)
    -- Shield Block goes on you while the boar is called immune to somebody's attack.
    w:cast(BLOCK)
    w:said(boar, "IMMUNE")
    w:advance(0.5)
    eq(w:icon("ActionButton2"), "cross", "Shield Block is on you")
    eq(w:icon("ActionButton1"), "check")
    eq(next(ns.db.immune), nil)
    local report = ns.db.report
    check(not Last(report.casts):find("the game said", 1, true), "the word is not put down to a buff: "
        .. Last(report.casts))

    -- A friend you have targeted is called immune to something. No enemy, no business of the addon's.
    w:target(warrior)
    w:advance(0.3)
    local before = #report.combat.immune
    w:said(warrior, "IMMUNE")
    w:advance(0.3)
    eq(#report.combat.immune, before, "not even a line in the saved report")
    eq(#ns.Tracker:Immunities(ns.Now()), 0)
    Clean(w)
end)

test("immune: the saved report keeps what the game said within bounds", function()
    local w, ns, boar = Simple({ saved = Proven() })
    w:cast(REND)
    w:advance(1)
    for _ = 1, 30 do
        w:said(boar, "IMMUNE")
        w:advance(0.3)
    end
    local said = ns.db.report.combat
    eq(#said.immune, 20, "the last twenty times it said \"immune\"")
    eq(said.words.IMMUNE, 60)
    for i = 1, 40 do
        w:said(boar, "WORD" .. i)
    end
    w:advance(0.3)
    local kinds = 0
    for _ in pairs(said.words) do
        kinds = kinds + 1
    end
    eq(kinds, 17, "sixteen words kept apart, and the rest together")
    eq(said.words.others, 50)
    eq(next(ns.db.immune), nil)
    Clean(w)
end)

test("immune: meeting more kinds of creature than are remembered at once starts the list over, and loses nothing learned", function()
    local w, ns, elemental = Elemental()
    w:cast(REND)
    w:advance(13)
    w:cast(REND)
    w:advance(0.3)
    eq(Kept(ns, "Rend", elemental).seen, 2)
    w:leaveCombat()
    for i = 1, 210 do
        local mob = w:addMob("Critter " .. i)
        w:target(mob)
        w:advance(0.1)
        w:kill(mob)
    end
    w:target(elemental)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "the elemental's kind is asked again, and known")
    local third = Meet(w, "Fire Elemental", { immune = { Rend = true } })
    eq(w:icon("ActionButton1"), "cross")
    eq(Kept(ns, "Rend", third).name, "Fire Elemental")
    Clean(w)
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
    local ns = w:load()
    eq(ns.db.usableOnly, true, "the default: an icon only on a skill that can be used")
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
    check(w:drain():find("The icons now appear on every skill.", 1, true), "it says so")
    eq(ns.db.usableOnly, false)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "out of reach, and shown all the same")
    eq(w:icon("ActionButton3"), "check")

    w.usableAsked = 0
    w:advance(2)
    eq(w.usableAsked, 0, "and the game is no longer asked")

    w:slash("usable on")
    check(w:drain():find("The icons now appear only on skills you can use right now.", 1, true))
    w:advance(0.3)
    eq(w:icon("ActionButton1"), nil)
    Clean(w)
end)

test("/se usable says and sets on which skills the icons appear", function()
    local w, ns = Simple()
    w:drain()
    w:slash("usable")
    local said = w:drain()
    check(said:find("The icons appear only on skills you can use right now.", 1, true),
        "with nothing after it, it says how things are: " .. said)
    check(said:find("To change that, type /se usable on (only on skills you can use right now) or /se usable off (on "
        .. "every skill).", 1, true), "and how to change them: " .. said)

    w:slash("usable maybe")
    eq(ns.db.usableOnly, true, "a word it does not know changes nothing")
    check(w:drain():find("type /se usable on (only on skills you can use right now) or /se usable off", 1, true))
    w:slash("usable OFF")
    eq(ns.db.usableOnly, false, "capitals do not matter")

    w:slash("off")
    w:drain()
    w:slash("on")
    check(w:drain():find("The icons are on. They appear always, and on every skill.", 1, true),
        "/se on says what to expect")
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
        check(w:drain():find("The game is not telling the addon whether a skill can be used, so for now the icons "
            .. "are shown on every skill.", 1, true),
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

--- The tile for an icon, on offer for one of the three results: brings up the
--- Icons tab and picks the result first, as the mouse would.
local function Swatch(w, view, result, choice)
    if view.tab ~= "icons" then
        w:click(view.tabs.icons)
    end
    if view.picked ~= result then
        w:click(view.results[result])
    end
    return view.tiles[choice]
end

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

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
    eq(canvas.view.tab, "display", "and opens on the Display tab")
    eq(canvas.view.pages.display:IsVisible(), true)
    eq(canvas.view.pages.icons:IsVisible(), false)
    eq(canvas.view.pages.spells:IsVisible(), false)
    local tabs = 0
    for _ in pairs(canvas.view.tabs) do
        tabs = tabs + 1
    end
    eq(tabs, 3, "three tabs: Display, Icons and Spells")
    Clean(w)
end)

panel("the game's own controls are used where the client has them", function(options)
    local w = Simple(options)
    local view = w:openSettings().view
    local native = not options.noTemplates
    eq(view.enable.native == true, native, "the tick box")
    eq(view.size.slider.native == true, native, "the size slider")
    eq(view.size.auto.native == true, native, "the Auto tick box")
    eq(view.defaults.native == true, native, "the Defaults button")
    eq(view.confirm.yes.native == true, native, "the buttons that confirm it")
    eq(view.pane.reset.native == true, native, "the button that resets one spell")
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
    eq(view.defaults.native, nil, "no game button")
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
        missingFonts = { GameFontHighlightHuge = true, GameFontHighlightLarge = true }, noAtlas = true, noLines = true,
        noSounds = true, noSpellTexture = true, noActionTexture = true,
    })
    local view = w:openSettings().view
    check(view ~= nil, "the panel is built")
    w:click(Swatch(w, view, "all", "hidden"))
    eq(ns.db.icons.all, "hidden", "the tile for no icon works without its stroke")
    w:click(view.tabs.spells)
    eq(view.spells.rows[1].icon.path, QUESTION, "a spell whose picture cannot be asked for gets a question mark")
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
        eq(view.defaults.native == true, fault[3] ~= "button", "the Defaults button, with a " .. what)
        eq(view.pane.reset.native == true, fault[3] ~= "button", "the button that resets a spell, with a " .. what)
        eq(Made(w, fault[1]), 1, "one that failed is not tried again for the next control, with a " .. what)

        -- Everything still works.
        w:slide(view.size.slider.widget, 26)
        eq(ns.db.size, 26, "the size slider works, with a " .. what)
        w:click(view.enable.frame)
        eq(ns.db.enabled, false, "the tick box works, with a " .. what)
        w:click(view.enable.frame)
        w:click(view.defaults)
        w:click(view.confirm.yes)
        eq(ns.db.size, 0, "the Defaults button works, with a " .. what)

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
    eq(view.defaults.native, nil, "its buttons are the addon's own")
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

    w:click(view.zones.RIGHT)
    eq(ns.db.corner, "RIGHT", "it works")
    w:click(view.defaults)
    w:click(view.confirm.yes)
    eq(ns.db.corner, "TOPLEFT")

    -- Later copies do not try the game's controls again this session.
    local made = Made(w, BUTTON)
    w:slash("options")
    local window = w.env.StatusEfficiencyOptions
    check(window:IsShown(), "the window of its own opens")
    eq(window.view.defaults.native, nil)
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
    eq(window.view.defaults.native, nil)
    eq(#w.env.UISpecialFrames, 1, "Escape closes it, and only it")
    eq(#ns.Options.views, 1)
    w:click(window.close)
    eq(window:IsShown(), false)
    eq(w:openSettings().view.defaults.native, nil, "and the Options window follows suit")
    Clean(w)
end)

--- Brings everything the panel can say on screen at least once, in both
--- copies: all three tabs, the note for two results on one icon, the box for a
--- texture of your own, each spell in the pane, and the question before a reset.
local function Tour(w)
    local canvas = w:openSettings()
    w:slash("options")
    local window = w.env.StatusEfficiencyOptions
    if not window:IsShown() then
        w:slash("options")
    end
    for _, view in ipairs({ canvas.view, window.view }) do
        w:click(view.tabs.display)
        w:click(view.defaults)
        w:click(view.confirm.no)
        w:click(Swatch(w, view, "some", "check")) -- two results share an icon, so the note about it is up
        w:click(Swatch(w, view, "all", "custom"))
        w:click(view.defaults)
        w:click(view.confirm.no)
        w:click(view.tabs.spells)
        for _, info in ipairs(view.spells.items) do
            view.Select(info.name)
        end
        -- Each group in the pane, with a question about it up: the offensive
        -- skills differ in who they are checked on, so a click there asks first.
        local group = view.groupPane
        w:click(view.spells.groups.defensive)
        w:click(view.spells.groups.offensive)
        for _, button in ipairs({ group.on.buttons.all, group.shared.buttons.mine }) do
            if group:IsShown() and group.same[button == group.on.buttons.all and "on" or "shared"] == nil then
                w:click(button)
                w:click(view.confirm.no)
            end
        end
        w:click(view.defaults)
        w:click(view.confirm.no)
    end
    return canvas.view, window.view
end

test("settings: in the game's standard font no label is drawn smaller", function()
    local w = Bar(nil, REND, HEROIC, SHOUT, CLAP, MARK, HAWK, SUNDER, DEMO)
    local view = Tour(w)
    local fitted = 0
    for _, label in ipairs(Labels(w)) do
        if label.fitRoom then
            fitted = fitted + 1
            eq(label.textScale or 1, 1, "the scale of \"" .. tostring(label.text) .. "\"")
            check(not label.fitCut, "\"" .. tostring(label.text) .. "\" is whole")
        end
    end
    check(fitted > 150, "the panel's labels are measured: " .. fitted)
    for _, preview in pairs(view.previews) do
        eq(preview.caption.textScale or 1, 1, "the captions beside the preview")
    end
    eq(next(w.ns.Options.notes.fonts), nil, "no font had to be replaced")
    Clean(w)
end)

--- Fails unless every fitted label in the world is inside the room it has.
local function Fits(w, what)
    local smaller, which = 0, {}
    for _, label in ipairs(Labels(w)) do
        local scale = label.textScale or 1
        check(scale >= 0.7 - 1e-9, "\"" .. tostring(label.text) .. "\" is too small to read, " .. what)
        if scale < 1 then
            smaller = smaller + 1
            which[#which + 1] = string.format("\"%s\" at %.2f", tostring(label.text), scale)
        end
        if label.fitLines then
            eq(label.maxLines, label.fitLines, "lines \"" .. tostring(label.text) .. "\" may take, " .. what)
        elseif label.fitRoom then
            check(label:GetStringWidth() <= label.fitRoom + 0.5, string.format("\"%s\" is %.0f wide in room for %.0f, %s",
                tostring(label.text), label:GetStringWidth(), label.fitRoom, what))
        end
    end
    return smaller, table.concat(which, "; ")
end

test("settings: the rooms are large enough for letters a third wider than the standard font's", function()
    -- The game's own font was measured a fifth wider than the pretend client's
    -- letters, and up to two fifths on a short word. Nothing may have to give
    -- for that: no label is drawn smaller, and none is cut short.
    for _, wider in ipairs({ 1.2, 1.35 }) do
        local what = "letters " .. wider .. " times as wide"
        local w = Bar({ fontWidth = wider }, REND, HEROIC, SHOUT, CLAP, MARK, HAWK, SUNDER, DEMO)
        Tour(w)
        local smaller, which = Fits(w, what)
        eq(smaller, 0, "labels that had to shrink, with " .. what .. ": " .. which)
        for _, label in ipairs(Labels(w)) do
            check(not label.fitCut, "\"" .. tostring(label.text) .. "\" is whole, with " .. what)
        end
        Clean(w)
    end
end)

test("settings: in a far wider font labels are drawn smaller, and none outgrows its room", function()
    for _, wider in ipairs({ 1.8, 2.5 }) do
        local what = "letters " .. wider .. " times as wide"
        local w, ns = Bar({ fontWidth = wider }, REND, HEROIC, SHOUT, CLAP, MARK, HAWK, SUNDER, DEMO)
        local view = Tour(w)
        check(Fits(w, what) > 0, "some labels had to shrink, with " .. what)

        -- What a result is called ends before the note at the far end of its line.
        w:click(view.tabs.icons)
        for _, key in ipairs({ "none", "some", "all" }) do
            local name, clash, row = view.names[key], view.clashes[key], view.results[key]
            local ends = 48 + name:GetStringWidth()
            local starts = clash:IsShown() and row.width - 8 - clash:GetStringWidth() or row.width
            check(ends <= starts + 0.5, "the name of " .. key .. " ends before the note, with " .. what)
        end

        -- A click on a tick box's words still lands on the box, and no further.
        local auto = view.size.auto
        local reach = -auto.frame.hitInsets[2] - 6
        near(reach, auto.label:GetStringWidth(), "how far the tick box reaches, with " .. what)

        -- What had to give is noted for later.
        w:closeSettings()
        check(next(ns.db.panel.tight) ~= nil, "tight labels are saved with the settings, with " .. what)
        Clean(w)
    end
end)

test("settings: a client whose labels cannot be drawn smaller still gets the whole panel", function()
    local w, ns = Bar({ fontWidth = 2.5, noTextScale = true }, REND, HEROIC, SHOUT)
    local view = w:openSettings().view
    check(view ~= nil, "the panel is built")
    for _, label in ipairs(Labels(w)) do
        eq(label.textScale, nil)
    end
    w:click(view.tabs.spells)
    eq(view.spells.intro.maxLines, 2, "what wraps is still kept to the lines it has room for")
    local name = view.pane.showArea.label
    eq(name:GetText(), "Show an icon")
    check(name:GetUnboundedStringWidth() > 112, "what a row is called is too long for its room in this font")
    check(name.fitCut and name:GetStringWidth() <= 112 and name.wordWrap == false,
        "and what has one line is cut short where its room ends, so that it never runs into what comes after it")
    for _, label in ipairs(Labels(w)) do
        if label.fitRoom and not label.fitLines then
            check(label:GetStringWidth() <= label.fitRoom + 0.5, "\"" .. tostring(label.text) .. "\" keeps to its room")
        end
    end
    w:click(view.tabs.display)
    w:click(view.zones.RIGHT)
    eq(ns.db.corner, "RIGHT")
    Clean(w)
end)

test("settings: a font this client lacks is replaced by its nearest neighbour", function()
    local w, ns = Simple({ missingFonts = { GameFontHighlightSmall = true, GameFontDisableSmall = true } })
    local view = w:openSettings().view
    eq(view.sizeNote.font, "GameFontNormalSmall", "the font of a line under a control")
    eq(view.footer.font, "GameFontNormalSmall", "the font of the line at the foot of the panel")
    eq(view.input.font, "GameFontNormalSmall", "the font of a box to type in")
    eq(ns.Options.notes.fonts.GameFontHighlightSmall, "GameFontNormalSmall", "it is noted")
    w:click(view.appear.buttons.combat)
    eq(ns.db.appear, "combat")
    Clean(w)

    -- The large white font of the headings has a gold neighbour of the same size.
    w, ns = Simple({ missingFonts = { GameFontHighlightLarge = true } })
    view = w:openSettings().view
    eq(ns.Options.notes.fonts.GameFontHighlightLarge, "GameFontNormalLarge")
    Clean(w)

    -- Not one of the fonts: the game's everyday typeface, by its file.
    local all = {}
    for _, font in ipairs({ "GameFontNormal", "GameFontNormalLarge", "GameFontNormalSmall", "GameFontHighlight",
        "GameFontHighlightSmall", "GameFontHighlightHuge", "GameFontHighlightLarge", "GameFontDisable",
        "GameFontDisableSmall" }) do
        all[font] = true
    end
    w, ns = Simple({ missingFonts = all, noTemplates = true })
    w:drain()
    view = w:openSettings().view
    check(view ~= nil, "the panel is built without a single font to borrow")
    eq(w:drain(), "")
    eq(view.footer.fontFile, "Fonts\\FRIZQT__.TTF")
    eq(view.footer.fontHeight, 10, "small text stays small")
    eq(view.tabs.spells.label.fontHeight, 12)
    eq(view.input.fontFile, "Fonts\\FRIZQT__.TTF", "boxes to type in too")
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
    w:click(canvas.view.zones.RIGHT)
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
    check(view.footer:GetText():find("turned off", 1, true), "and the panel says why")
    eq(view.off:GetText(), "The icons are turned off.", "beside the tick box too")

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
    eq(view.appear.buttons.always.label:GetText(), "Always")
    eq(view.appear.buttons.combat.label:GetText(), "When you are in combat")
    eq(view.appear.buttons.group.label:GetText(), "When you or your group are in combat")
    eq(view.appear.buttons.target, nil, "three choices, and the one earlier versions had is not among them")

    w:click(view.appear.buttons.combat)
    eq(ns.db.appear, "combat")
    eq(view.appear.picked, "combat")
    eq(view.appear.buttons.always.picked, false)
    w:slash("when group")
    eq(view.appear.picked, "group", "/se when moves it too")
    w:click(view.appear.buttons.always)
    eq(ns.db.appear, "always")
    w:click(view.appear.buttons.group)
    eq(ns.db.appear, "group")
    eq(view.appear.buttons.group.picked, true)

    local title, lines = w:hover(view.appear.buttons.group)
    eq(title, "When you or your group are in combat")
    check(lines[1]:find("party or raid", 1, true), "each choice explains itself: " .. tostring(lines[1]))
    w:unhover(view.appear.buttons.group)
    eq(w.tooltip, nil)
    title, lines = w:hover(view.appear.buttons.combat)
    eq(title, "When you are in combat")
    check(lines[1]:find("only while you yourself are in combat", 1, true), tostring(lines[1]))
    w:unhover(view.appear.buttons.combat)

    w:click(view.enable.frame)
    near(view.appear.frame:GetAlpha(), 0.35, "dimmed while the icons are off")
    w:click(view.appear.buttons.always)
    eq(ns.db.appear, "group", "and a click on a choice changes nothing then")
    w:click(view.enable.frame)
    near(view.appear.frame:GetAlpha(), 1)

    w:closeSettings()
    w:advance(0.3)
    eq(w:icon("ActionButton3"), nil, "an enemy is targeted, but nobody is fighting")
    w:enterCombat()
    w:advance(0.3)
    eq(w:icon("ActionButton3"), "check", "and now you are")
    Clean(w)
end)

panel("picking on which skills the icons appear", function(options)
    local w, ns = Simple(options)
    local view = w:openSettings().view
    w:slash("options")
    local window = w.env.StatusEfficiencyOptions.view
    eq(view.usable.picked, "usable", "only on usable skills to begin with")
    eq(view.usable.buttons.usable.picked, true)
    eq(view.usable.buttons.always.label:GetText(), "Every skill")
    eq(view.usable.buttons.usable.label:GetText(), "Only skills you can use right now")
    eq(view.usableNote:GetText(), "A skill that is only waiting for rage, mana, energy or its cooldown keeps its icon.",
        "what does not hide an icon is said under the two")

    w:click(view.usable.buttons.always)
    eq(ns.db.usableOnly, false)
    eq(view.usable.picked, "always")
    eq(view.usableNote:GetText(), "", "nothing to add to every skill")
    eq(window.usable.picked, "always", "the other copy follows")
    w:slash("usable on")
    eq(view.usable.picked, "usable", "/se usable moves it too")

    local title, lines = w:hover(view.usable.buttons.usable)
    eq(title, "Only skills you can use right now")
    check(lines[1]:find("out of range", 1, true), "each choice explains itself: " .. tostring(lines[1]))
    check(lines[1]:find("cooldown", 1, true), "and says what does not count")
    w:unhover(view.usable.buttons.usable)

    w:click(view.enable.frame)
    near(view.usable.frame:GetAlpha(), 0.35, "dimmed while the icons are off")
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

panel("sample icons show on the real buttons while the Display or the Icons tab is open", function(options)
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
    check(view.footer:GetText():find("sample icons", 1, true), "the panel says what they are")

    w:click(view.tabs.spells)
    w:advance(0.2)
    eq(w:icon("ActionButton1"), nil, "not while the Skills tab is up")
    w:click(view.tabs.icons)
    w:advance(0.2)
    eq(w:icon("ActionButton2"), "partial", "the Icons tab is about how they look too")
    check(view.footer:GetText():find("sample icons", 1, true), "and says so")
    w:click(view.tabs.spells)
    w:advance(0.2)
    w:click(view.tabs.display)
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
        eq(preview.caption:GetText(), state.title, "and the result's name beside it")
        local title, lines = w:hover(preview.slot)
        eq(title, state.title, "the mouse on it says what the result means")
        eq(lines[1], state.detail)
        w:unhover(preview.slot)
    end
    eq(view.previews.none.face.path, 130000 + SHOUT, "the pretend buttons wear spells from your own bars")
    eq(view.previews.some.face.path, 130000 + REND, "those with an icon first")
    eq(view.previews.all.face.path, 130000 + HEROIC)

    w:slash("size 30")
    w:slash("corner br")
    eq(view.previews.some.icon.width, 30)
    eq(view.previews.some.icon.point[1], "BOTTOMRIGHT")
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

panel("nine squares say where the icon sits, and a click on one moves it on every button", function(options)
    local w, ns = Simple(options)
    local view = w:openSettings().view
    eq(w:overlay("ActionButton1").point[1], "TOPLEFT", "starts in the top left")
    eq(view.zones.TOPLEFT.picked, true, "and that square is the one marked")
    eq(view.where:GetText(), "Top left", "with its name beside the nine")

    w:click(view.zones.BOTTOMRIGHT)
    eq(ns.db.corner, "BOTTOMRIGHT")
    eq(w:overlay("ActionButton1").point[1], "BOTTOMRIGHT", "the real icon moved")
    eq(view.previews.none.icon.point[1], "BOTTOMRIGHT", "and so did all three previews")
    eq(view.previews.some.icon.point[1], "BOTTOMRIGHT")
    eq(view.zones.BOTTOMRIGHT.picked, true)
    eq(view.zones.TOPLEFT.picked, false, "one square is marked at a time")
    eq(view.where:GetText(), "Bottom right")

    w:click(view.zones.TOP)
    eq(w:overlay("ActionButton1").point[1], "TOP", "edges work as well as corners")
    eq(w:hover(view.zones.CENTER), "Middle", "each square says where it is")
    w:unhover(view.zones.CENTER)

    -- The squares are laid out like the button itself: three lines of three.
    local count = 0
    for position, zone in pairs(view.zones) do
        count = count + 1
        local _, _, _, x, y = zone:GetPoint(1)
        eq(x, (zone.column - 1) * 22, position .. " is in its column")
        eq(y, -(zone.row - 1) * 22, position .. " is on its line")
    end
    eq(count, 9)
    eq(view.zones.TOPLEFT.row .. "," .. view.zones.TOPLEFT.column, "1,1")
    eq(view.zones.RIGHT.row .. "," .. view.zones.RIGHT.column, "2,3")
    eq(view.zones.BOTTOM.row .. "," .. view.zones.BOTTOM.column, "3,2")

    w:slash("corner left")
    eq(view.zones.LEFT.picked, true, "/se corner moves the mark too")
    eq(view.where:GetText(), "Left")
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

    w:click(inOptions.zones.LEFT)
    eq(window.previews.all.icon.point[1], "LEFT", "and the other way round")
    eq(window.zones.LEFT.picked, true)
    w:click(inOptions.appear.buttons.combat)
    eq(window.appear.picked, "combat")

    -- Each copy has its own tab open and its own result picked, and shows the
    -- same settings on whatever that is.
    w:click(Swatch(w, window, "some", "exclaim"))
    w:click(inOptions.tabs.icons)
    eq(inOptions.picked, "none", "the other copy has another result picked")
    eq(inOptions.tiles.exclaim.ring.shown, false)
    w:click(inOptions.results.some)
    eq(inOptions.tiles.exclaim.ring.shown, true, "and shows the same icon in use for this one")
    w:click(inOptions.tiles.star)
    eq(window.tiles.star.ring.shown, true, "a click there shows here at once")
    check(tostring(window.current.some.path):find("RaidTargetingIcon_1", 1, true), "in the result's own line too")

    w:slash("size auto")
    w:click(window.tabs.display)
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
    w:click(view.tabs.icons)
    eq(view.picked, "none", "the first result is the one picked to begin with")
    eq(view.results.none.picked, true)
    eq(view.results.none.chosen:IsShown(), true, "its line is marked")
    eq(view.results.all.chosen:IsShown(), false)
    eq(view.offer:GetText(), "Icon for \"Worth casting\"", "and the icons under the three are for it")
    eq(view.tiles.check.ring.shown, true, "the icon in use is framed")

    w:click(view.tiles.greendot)
    eq(ns.db.icons.none, "greendot")
    check(Art(w, "ActionButton1"):find("DotGreen.tga", 1, true), "the button shows the green dot straight away")
    eq(view.tiles.greendot.ring.shown, true)
    eq(view.tiles.check.ring.shown, false)
    check(view.current.none.path:find("DotGreen.tga", 1, true), "the result's line shows the icon in use")

    w:click(view.results.all)
    eq(view.picked, "all")
    eq(view.offer:GetText(), "Icon for \"No need to cast\"")
    eq(view.results.all.picked, true)
    eq(view.results.none.picked, false, "one result at a time")
    eq(view.tiles.cross.ring.shown, true, "the other results are untouched")
    eq(view.tiles.greendot.ring.shown, false, "the frame is on the icon of the result that is picked")
    eq(w:hover(view.results.some), "Partly worth casting", "a result says what it is")
    w:unhover(view.results.some)

    w:click(view.tiles.skull)
    eq(ns.db.icons.all, "skull")
    w:click(view.tabs.display)
    check(view.previews.none.icon.path:find("DotGreen.tga", 1, true), "the preview on the Display tab shows them too")
    eq(view.previews.all.icon.path, SKULL)
    w:closeSettings()
    w:cast(REND)
    w:advance(0.5)
    eq(Art(w, "ActionButton1"), SKULL, "the skull now means there is no need to cast")
    Clean(w)
end)

test("settings: the addon's ten icons are on one line and the game's eleven on the next", function()
    local w, ns = Simple()
    local view = w:openSettings().view
    w:click(view.tabs.icons)
    local own, game = 0, 0
    local lineOne, lineTwo
    for _, choice in ipairs(ns.Icons.CHOICES) do
        local tile = view.tiles[choice.key]
        check(tile, "missing tile " .. choice.key)
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
    eq(own, 10, "the addon's own icons")
    eq(game, 11, "the game's icons")
    for _, state in ipairs(ns.Icons.STATES) do
        check(ns.Icons.Choice(state.default), "default for " .. state.key .. " exists")
    end
    eq(w:hover(view.tiles.reddot), "Red dot", "each one says what it is")
    w:unhover(view.tiles.reddot)

    -- One grid serves all three results: a click gives the icon to whichever is picked.
    w:click(view.results.some)
    w:click(view.tiles.reddot)
    eq(ns.db.icons.some, "reddot")
    eq(ns.db.icons.none, nil)
    eq(ns.db.icons.all, nil)
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
    w:click(view.tabs.icons)
    eq(view.sets.marks.picked, true, "starts on the check, half circle and X")
    eq(view.sets.dots.picked, false)
    eq(view.setName:GetText(), "Check, half circle and X", "the set in use is named beside the four")

    w:click(view.sets.dots)
    eq(ns.db.icons.none, "greendot")
    eq(ns.db.icons.some, "yellowdot")
    eq(ns.db.icons.all, "reddot")
    eq(view.sets.dots.picked, true)
    eq(view.sets.marks.picked, false)
    eq(view.setName:GetText(), "Green, yellow and red dots")
    w:advance(0.2)
    check(Art(w, "ActionButton3"):find("DotRed.tga", 1, true), "the sample on the third button is the red dot")

    w:click(Swatch(w, view, "some", "star"))
    eq(view.sets.dots.picked, false, "a mix is no set")
    eq(view.setName:GetText(), "Your own mix of icons")
    w:click(view.sets.ready)
    eq(ns.db.icons.some, "waiting")
    eq(w:hover(view.sets.symbols), "Plus, exclamation mark and stop sign", "each set says what is in it")
    w:unhover(view.sets.symbols)
    Clean(w)
end)

panel("two results that share an icon are pointed out", function(options)
    local w = Simple(options)
    local view = w:openSettings().view
    w:click(view.tabs.icons)
    eq(view.clashes.some:IsShown(), false, "nothing to say to begin with")

    w:click(Swatch(w, view, "some", "check"))
    eq(view.clashes.some:IsShown(), true)
    eq(view.clashes.some:GetText(), "Same icon as \"Worth casting\"")
    eq(view.clashes.none:IsShown(), false, "only the later of the two says so")
    w:click(Swatch(w, view, "all", "check"))
    eq(view.clashes.all:GetText(), "Same icon as \"Worth casting\"")

    w:click(Swatch(w, view, "some", "hidden"))
    eq(view.clashes.some:IsShown(), false, "no icon clashes with nothing")
    w:click(Swatch(w, view, "none", "hidden"))
    eq(view.clashes.all:IsShown(), false)
    Clean(w)
end)

panel("a result can be given no icon at all", function(options)
    options.combatAuras = "none"
    local w, ns = Simple(options)
    local view = w:openSettings().view
    local hidden = Swatch(w, view, "all", "hidden")
    local title, lines = w:hover(hidden)
    eq(title, "No icon")
    eq(lines[1], "Nothing is drawn on the action button for this result.")
    w:unhover(hidden)

    w:click(hidden)
    eq(ns.db.icons.all, "hidden")
    eq(hidden.ring.shown, true, "the bare tile is framed")
    eq(view.tiles.cross.ring.shown, false)
    eq(view.current.all:IsShown(), false, "the result's line shows no icon")
    eq(view.results.all.none:IsShown(), true, "but the mark that stands for none")
    eq(view.results.none.none:IsShown(), false)
    w:advance(0.2)
    eq(w:icon("ActionButton3"), nil, "the sample for that result is bare too")
    eq(w:icon("ActionButton1"), "check", "the other results keep their icons")
    w:click(view.tabs.display)
    eq(view.previews.all.icon:IsShown(), false, "and so is the pretend button")
    eq(view.previews.none.icon:IsShown(), true)

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

panel("the icons to pick from line up in one grid, under the three results", function(options)
    local w, ns = Simple(options)
    local view = w:openSettings().view
    w:click(view.tabs.icons)
    local tiles = view.tiles
    local first, last = tiles.check.point, tiles.skull.point
    local hidden, custom = tiles[ns.Icons.HIDDEN].point, tiles.custom.point
    eq(hidden[5], first[5], "\"no icon\" sits on the first line, with the addon's own icons")
    eq(hidden[4], last[4], "in the column the second line ends in")
    eq(custom[5], first[5], "your own texture comes after it")
    eq(custom[4] - hidden[4], tiles.ring.point[4] - tiles.stop.point[4], "one step along")
    check(custom[4] + tiles.custom.width <= 624, "and the line ends inside the page")

    local lowest = view.results.all
    check(view.offer.point[5] < lowest.point[5] - lowest.height, "what the grid is for is said under the last result")
    check(first[5] <= view.offer.point[5] - 16, "and the grid starts under that")

    -- The box for a texture of your own opens under the grid, clear of it.
    local editor = view.editor
    check(editor.point[5] <= last[5] - tiles.skull.height, "under the second line")
    eq(editor.point[4], first[4], "starting where the grid does")
    check(editor.point[4] + editor.width <= 624, "and inside the page")
    check(editor.point[5] - editor.height >= -(514 - 34), "above the strip at the bottom")
    Clean(w)
end)

panel("your own texture: the tile opens a box that explains itself", function(options)
    options.missingTextures = { [424242] = true }
    local w, ns = Simple(options)
    local view = w:openSettings().view
    w:click(view.tabs.icons)
    local editor, box = view.editor, view.input
    eq(editor:IsShown(), false, "the box stays out of the way until it is asked for")

    eq(view.tiles.custom.art:IsShown(), false, "its tile shows three dots until there is a texture")
    eq(view.tiles.custom.dots:IsShown(), true)

    w:click(view.tiles.custom)
    eq(editor:IsShown(), true)
    eq(box:HasFocus(), true, "ready to type into")
    eq(editor.note:GetText(), "Type a file ID or a path, then press Enter.")

    w:drain()
    w:type(box, "nonsense")
    check(editor.note:GetText():find("That is not a picture the game knows.", 1, true),
        "a bad entry is explained next to the box")
    eq(w:drain(), "", "and not in the chat window")
    eq(ns.db.icons.none, nil, "it changes nothing")
    eq(box:HasFocus(), true, "and the box stays ready for another go")

    w:type(box, "136243")
    eq(ns.db.icons.none, "custom")
    eq(ns.db.custom.none, 136243)
    w:advance(0.2)
    eq(Art(w, "ActionButton1"), 136243, "the button shows the file ID")
    eq(view.tiles.check.ring.shown, false, "no stock icon is framed")
    eq(view.tiles.custom.ring.shown, true, "the tile for your own is")
    eq(view.tiles.custom.art.path, 136243, "and shows the texture")
    eq(view.tiles.custom.art:IsShown(), true)
    eq(view.tiles.custom.dots:IsShown(), false, "in place of the three dots")
    eq(view.current.none.path, 136243, "and so does the result's line")
    eq(box:GetText(), "136243")
    eq(editor.note:GetText(), "This picture is in use. To go back to the usual icon, empty the box and press Enter.",
        "the box says how to undo it")

    w:type(box, " Interface/Icons/Spell_Nature_Slow ")
    eq(Art(w, "ActionButton1"), "Interface\\Icons\\Spell_Nature_Slow", "a path with either kind of slash")

    w:type(box, "424242")
    eq(editor.note:GetText(), "The game has no picture with that ID or path, so no icon is shown.",
        "a texture that does not exist is pointed out")
    w:closeSettings()
    w:openSettings()
    eq(editor:IsShown(), true, "the box stays open while the result uses it")

    -- The box belongs to the result that is picked.
    w:click(view.results.some)
    eq(editor:IsShown(), false, "another result has no texture of its own")
    eq(view.tiles.custom.art:IsShown(), false, "and the tile is back to its dots for it")
    eq(view.tiles.custom.dots:IsShown(), true)
    w:click(view.results.none)
    eq(editor:IsShown(), true)
    eq(box:GetText(), "424242")

    w:type(box, "")
    eq(ns.db.icons.none, nil, "emptying the box goes back to the usual icon")
    eq(editor:IsShown(), false)
    eq(view.tiles.check.ring.shown, true)
    w:advance(0.2)
    eq(w:icon("ActionButton1"), "check")

    w:click(view.results.some)
    w:click(view.tiles.custom)
    eq(editor:IsShown(), true)
    w:escape(box)
    eq(editor:IsShown(), false, "Escape puts away a box that is not in use")
    w:click(view.tiles.custom)
    w:click(view.tiles.ring)
    eq(editor:IsShown(), false, "and so does picking another icon")
    w:click(view.tiles.custom)
    w:type(box, "nonsense")
    w:click(view.results.all)
    eq(editor:IsShown(), false, "or another result")
    eq(box:HasFocus(), false)
    w:click(view.results.some)
    eq(editor:IsShown(), false, "and coming back to the first one does not bring the box back")
    w:click(view.results.all)
    w:click(view.tiles.custom)
    eq(editor.note:GetText(), "Type a file ID or a path, then press Enter.",
        "which starts with a clean box, not the last one's complaint")

    -- Picking a result that has a texture of its own ends the typing for another.
    w:type(box, "136243")
    eq(ns.db.custom.all, 136243)
    w:click(view.results.some)
    w:click(view.tiles.custom)
    box:SetText("half typed")
    eq(box:HasFocus(), true)
    w:click(view.results.all)
    eq(editor:IsShown(), true, "its own box shows")
    eq(box:HasFocus(), false, "what was being typed for the other result is put away")
    eq(box:GetText(), "136243", "and the box holds this result's texture")
    check(editor.note:GetText():find("This picture is in use.", 1, true))
    eq(ns.db.icons.some, "ring", "the other one keeps the icon it had")
    w:click(view.results.some)
    w:click(view.tiles.custom)
    w:type(box, "nonsense")
    check(editor.note:GetText():find("That is not a picture the game knows.", 1, true))
    w:click(view.results.all)
    check(editor.note:GetText():find("This picture is in use.", 1, true),
        "and neither does a complaint about the other one stay up")
    Clean(w)
end)

test("settings: a client that does not say whether a texture exists is asked another way", function()
    local w = Simple({ quietTextures = true, missingTextures = { [424242] = true } })
    local view = w:openSettings().view
    w:click(Swatch(w, view, "none", "custom"))
    w:type(view.input, "136243")
    check(view.editor.note:GetText():find("This picture is in use.", 1, true), "one that exists")
    w:type(view.input, "424242")
    check(view.editor.note:GetText():find("The game has no picture with that ID or path", 1, true), "one that does not")
    Clean(w)
end)

panel("Defaults asks first, and puts back the tab that is open and nothing else", function(options)
    local w, ns = Simple(options)
    local view = w:openSettings().view
    w:slash("track heroic strike")
    w:slash("when combat")
    w:slash("usable off")
    w:click(view.zones.CENTER)
    w:slide(view.size.slider.widget, 20)
    w:click(Swatch(w, view, "some", "ring"))
    w:click(Swatch(w, view, "all", "custom"))
    w:type(view.input, "136243")
    local title, lines = w:hover(view.defaults)
    eq(title, "Defaults")
    check(lines[1]:find("every setting on the open tab", 1, true), "the button says how far it goes: " .. tostring(lines[1]))
    w:unhover(view.defaults)

    -- On the Icons tab it is about the three icons.
    w:click(view.defaults)
    eq(view.confirm.frame:IsShown(), true, "it asks first")
    eq(view.question:GetText(), "Put the three icons back to how they started?")
    eq(view.footer:IsShown(), false, "in place of the line at the bottom")
    eq(ns.db.icons.some, "ring", "and has changed nothing yet")
    w:click(view.confirm.no)
    eq(view.confirm.frame:IsShown(), false)
    eq(view.footer:IsShown(), true)
    eq(ns.db.custom.all, 136243, "Cancel leaves everything alone")

    w:click(view.defaults)
    w:click(view.confirm.yes)
    eq(next(ns.db.icons), nil)
    eq(next(ns.db.custom), nil)
    eq(view.editor:IsShown(), false)
    eq(view.confirm.frame:IsShown(), false)
    eq(view.sets.marks.picked, true)
    eq(ns.db.corner, "CENTER", "the Display tab is left alone")
    eq(ns.db.size, 20)
    eq(ns.db.appear, "combat")
    eq(ns.db.usableOnly, false)
    check(ns.db.spells["Heroic Strike"] ~= nil, "and so are the spells")

    -- On the Display tab it is about everything on that tab.
    w:click(view.tabs.display)
    w:click(view.enable.frame)
    eq(ns.db.enabled, false)
    w:click(view.defaults)
    eq(view.question:GetText(), "Put everything on the Display tab back to how it started?")
    w:click(view.confirm.yes)
    eq(ns.db.corner, "TOPLEFT")
    eq(ns.db.size, 0)
    eq(ns.db.appear, "group")
    eq(ns.db.usableOnly, true)
    eq(ns.db.enabled, true)
    eq(view.size.auto.ticked, true)
    eq(view.enable.ticked, true)
    eq(view.appear.picked, "group")
    eq(view.usable.picked, "usable")
    eq(view.zones.TOPLEFT.picked, true)
    check(ns.db.spells["Heroic Strike"] ~= nil, "spell choices are still left alone")

    -- A question that is left unanswered goes away.
    w:click(view.zones.RIGHT)
    w:click(view.defaults)
    w:closeSettings()
    w:openSettings()
    eq(view.confirm.frame:IsShown(), false, "closing the panel puts the question away")
    w:click(view.defaults)
    w:click(view.tabs.spells)
    eq(view.confirm.frame:IsShown(), false, "and so does leaving the tab")
    eq(view.footer:IsShown(), true)
    w:click(view.tabs.display)
    eq(view.confirm.frame:IsShown(), false)
    eq(ns.db.corner, "RIGHT", "neither is taken for a yes")
    Clean(w)
end)

test("settings: what Defaults puts back on the Display tab is what a new install starts with", function()
    local w = World()
    w:addButton("ActionButton1", 1, REND)
    local ns = w:install()
    local count = 0
    for key, value in pairs(ns.Options.DEFAULTS) do
        count = count + 1
        eq(ns.db[key], value, "a new install's " .. key)
    end
    eq(count, 5, "whether, when, on which skills, where and how large")
    Clean(w)
end)

panel("Defaults on the Skills tab forgets your own choices for every skill, and nothing the addon learned", function(options)
    local function Copy(value)
        if type(value) ~= "table" then
            return value
        end
        local copy = {}
        for key, inner in pairs(value) do
            copy[key] = Copy(inner)
        end
        return copy
    end
    local function Same(a, b)
        if type(a) ~= "table" or type(b) ~= "table" then
            return a == b
        end
        for key, value in pairs(a) do
            if not Same(value, b[key]) then
                return false
            end
        end
        for key in pairs(b) do
            if a[key] == nil then
                return false
            end
        end
        return true
    end

    local w, ns = Simple(options)
    w:cast(REND)
    w:advance(2)
    check(next(ns.db.learned) ~= nil, "the addon has learned something in play")
    w:slash("track heroic strike")
    w:slash("duration rend 30")
    w:slash("ignore battle shout")
    ns.db.spells["Mortal Strike"] = { track = true } -- a choice kept from when it was on the bars
    w:click(Swatch(w, w:openSettings().view, "all", "skull"))
    local view = w:openSettings().view
    w:click(view.tabs.spells)
    w:advance(0.5)
    eq(w:icon("ActionButton2"), "check", "Heroic Strike has an icon because you said so")
    eq(w:icon("ActionButton3"), nil, "and Battle Shout has none")
    local learned = Copy(ns.db.learned)

    w:click(view.defaults)
    eq(view.question:GetText(), "Undo every change you made to your skills?")
    check(ns.db.spells.Rend ~= nil, "it asks first")
    w:click(view.confirm.yes)
    eq(next(ns.db.spells), nil, "every choice of yours is gone, also for a skill no longer on the bars")
    check(Same(ns.db.learned, learned), "what the addon learned in play is kept")
    eq(ns.db.icons.all, "skull", "and the other tabs are left alone")
    eq(view.pane.show.picked, "auto")
    eq(view.pane.resetNote:GetText(), "You have not changed this skill.")
    w:advance(0.5)
    eq(w:icon("ActionButton2"), nil, "Heroic Strike is back to having no icon")
    eq(w:icon("ActionButton3"), "check", "and Battle Shout to having one")
    check(w:icon("ActionButton1") ~= nil, "Rend, which the addon was following, is still followed")
    eq(view.footer:GetText(), "3 skills are on your bars. 2 have an icon.")
    Clean(w)
end)

test("/se options opens a window of its own, on a tab if one is named", function()
    local w = Simple()
    w:slash("options")
    local window = w.env.StatusEfficiencyOptions
    check(window and window:IsShown(), "the window is showing")
    eq(w.env.UISpecialFrames[1], "StatusEfficiencyOptions", "Escape closes it")
    eq(window.view.tab, "display")

    w:slash("options")
    eq(window:IsShown(), false, "the command closes it again")
    w:slash("config")
    eq(window:IsShown(), true, "/se config is the same command")
    w:slash("options spells")
    eq(window:IsShown(), true, "naming a tab never closes it")
    eq(window.view.tab, "spells")
    eq(window.view.pages.spells:IsVisible(), true)
    eq(window.view.pages.display:IsVisible(), false)
    eq(window.view.spells.rows[1].name:GetText(), "Battle Shout", "and the tab is filled in")
    eq(window.view.pane.name:GetText(), "Battle Shout")

    w:click(window.close)
    eq(window:IsShown(), false, "the X closes it")
    w:slash("options icons")
    eq(window:IsShown(), true)
    eq(window.view.tab, "icons")
    eq(window.view.pages.icons:IsVisible(), true)
    eq(window.view.offer:GetText(), "Icon for \"Worth casting\"")
    w:slash("options display")
    eq(window.view.tab, "display")
    w:slash("options skills")
    eq(window.view.tab, "spells", "the third tab by the name on it")
    w:slash("options display")
    w:slash("options spells")
    eq(window.view.tab, "spells", "and by the name it had before")
    w:slash("options icon")
    eq(window.view.tab, "icons", "near enough is good enough")
    w:slash("options appearance")
    eq(window:IsShown(), true)
    eq(window.view.tab, "display", "the name the first tab had before there were three still opens it")
    w:click(window.view.tabs.spells)
    eq(window.view.tabs.spells.picked, true)
    eq(window.view.tabs.display.picked, false)
    eq(window.view.tabs.icons.picked, false)
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

test("settings: each of the three results says what it means, for an effect that stacks too", function()
    local w = Simple()
    local view = w:openSettings().view
    w:click(view.tabs.icons)
    eq(view.names.none:GetText(), "Worth casting")
    eq(view.details.none:GetText(), "Its effect is missing, or not at full stacks, so the skill is worth using.")
    eq(view.names.some:GetText(), "Partly worth casting")
    eq(view.details.some:GetText(), "Some enemies already have its effect in full and others do not.")
    eq(view.names.all:GetText(), "No need to cast")
    eq(view.details.all:GetText(), "Its effect is already there in full, or the enemy is immune to it.")
    Clean(w)
end)

--------------------------------------------------------------------------------
-- The settings panel: the Skills tab
--------------------------------------------------------------------------------

--- Picks a spell in the list of the Skills tab with a click on its line, and
--- returns the pane beside the list, which then shows it, and the line.
local function Pane(w, view, name)
    if view.tab ~= "spells" then
        w:click(view.tabs.spells)
    end
    for _, row in ipairs(view.spells.rows) do
        if row:IsShown() and row.name:GetText() == name then
            w:click(row)
            eq(view.pane.name:GetText(), name, "the pane shows the spell that was clicked")
            eq(row.selected, true, "and its line is marked")
            return view.pane, row
        end
    end
    error("the Skills tab has no line for " .. name, 2)
end

--- What a control says when the mouse is on it: its title and its sentence.
local function Says(w, widget)
    local title, lines = w:hover(widget)
    w:unhover(widget)
    return title, lines and lines[1] or ""
end

test("/se list gives the same reason for a skill's icon as the Skills tab, in the same words", function()
    local w = World()
    w:addSpell(902, {
        -- Castable on enemies, but its tooltip mentions no duration.
        name = "Gouge Armor", harmful = true,
        description = "Tears at the target's armor until it gives way.",
        effect = { duration = 12 },
    })
    w:addButton("ActionButton1", 1, REND)
    w:addButton("ActionButton2", 2, HEROIC)
    w:addButton("ActionButton3", 3, SHOUT)
    w:addButton("ActionButton4", 4, CLAP)
    w:addButton("ActionButton5", 5, 902)
    w:addButton("ActionButton6", 6, COMMAND)
    w:addButton("ActionButton7", 7, BLOODTHIRST)
    local ns = w:load()
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:advance(0.3)
    -- Two skills earn their icon by what is seen of them out of a fight, and one is given it.
    w:cast(902, { quiet = true })
    w:advance(0.5)
    w:cast(COMMAND)
    w:advance(0.5)
    w:slash("track heroic")
    w:drain()

    w:slash("list")
    local list = w:drain()
    local view = w:openSettings().view
    local reasons = {
        ["Rend"] = "It has an icon because its tooltip describes a debuff that lasts for a while.",
        ["Battle Shout"] = "It has an icon because its tooltip describes a buff that lasts for a while.",
        ["Thunder Clap"] = "It has an icon because it is a well-known debuff that hits every enemy around you.",
        ["Gouge Armor"] = "It has an icon because the addon has seen its debuff on an enemy.",
        ["Commanding Shout"] = "It has an icon because the addon has seen its buff on you.",
        ["Heroic Strike"] = "You chose Always, so it has an icon.",
    }
    for name, reason in pairs(reasons) do
        eq(Pane(w, view, name).why:GetText(), reason, name .. " on the Skills tab")
        local line = list:match("\n  |cff40d040" .. name .. "|r ([^\n]*)")
        check(line and line:find(reason, 1, true), name .. " in /se list gives the reason the Skills tab gives, \""
            .. reason .. "\": " .. tostring(line))
    end
    w:closeSettings()
    Clean(w)
end)

panel("the Skills tab lists every spell on the bars, and shows the one that is picked beside the list", function(options)
    local w, ns = Simple(options)
    local view = w:openSettings().view
    w:click(view.tabs.spells)
    local rows, pane = view.spells.rows, view.pane
    eq(view.tab, "spells")
    eq(view.tabs.spells.picked, true)
    eq(rows[1].name:GetText(), "Battle Shout", "spells with an icon come first")
    eq(rows[2].name:GetText(), "Rend")
    eq(rows[3].name:GetText(), "Heroic Strike", "then the rest")
    eq(rows[4]:IsShown(), false, "and no more lines than spells")
    eq(view.footer:GetText(), "3 skills are on your bars. 2 have an icon.")
    eq(view.spells.bar:IsShown(), false, "nothing to scroll")
    eq(view.spells.intro:GetText(), "Click a skill to see how the addon treats it and to change that. Click a group at "
        .. "the top of the list to change all of its skills at once.", "what the tab is for is said above the list")

    -- Each line: the skill's own picture, its name, and how it is treated in a few words.
    eq(rows[1].icon.path, 130000 + SHOUT, "with the spell's own picture")
    eq(rows[1].status:GetText(), "Buff on you, 2 min")
    eq(rows[2].status:GetText(), "Debuff on your target, 21 s")
    eq(rows[3].status:GetText(), "No icon")
    eq(rows[3].icon.path, 130000 + HEROIC)
    eq(rows[3].icon.desaturated, true, "a spell with no icon is greyed out")
    eq(rows[1].icon.desaturated, false)

    -- The first of the list is picked to begin with, and the pane is about it.
    eq(rows[1].selected, true)
    eq(rows[2].selected, false)
    eq(pane:IsShown(), true)
    eq(pane.name:GetText(), "Battle Shout")
    eq(pane.icon.path, 130000 + SHOUT)
    eq(pane.summary:GetText(), "Defensive: buff on you, 2 min", "which group it falls into, and how it is treated")
    eq(pane.show.picked, "auto")
    eq(pane.why:GetText(), "It has an icon because its tooltip describes a buff that lasts for a while.")
    eq(pane.on.picked, "self", "Battle Shout is judged on you")
    eq(pane.onNote:GetText(), "The icon tells you whether you have the effect, or the friend you have targeted.")
    eq(pane.lasts:GetText(), "2 min")
    eq(pane.lastsNote:GetText(), "The addon read this from the skill's tooltip.")

    w:click(rows[2])
    eq(rows[2].selected, true)
    eq(rows[1].selected, false, "one at a time")
    eq(pane.name:GetText(), "Rend")
    eq(pane.icon.path, 130000 + REND)
    eq(pane.summary:GetText(), "Offensive: debuff on your target, 21 s")
    eq(pane.why:GetText(), "It has an icon because its tooltip describes a debuff that lasts for a while.")
    eq(pane.on.picked, "target", "Rend on your target")
    eq(pane.onNote:GetText(), "The icon tells you whether the enemy you have targeted has the effect.")
    eq(pane.lasts:GetText(), "21 s")

    -- A spell with no icon: the rest of the pane is greyed out, and says why.
    w:click(rows[3])
    eq(pane.name:GetText(), "Heroic Strike")
    eq(pane.summary:GetText(), "Offensive skill with no icon")
    eq(pane.show.picked, "auto")
    eq(pane.why:GetText(), "It has no icon because it does not seem to leave a buff or a debuff behind.")
    eq(pane.on.picked, nil, "a spell with no icon has nobody to be judged on")
    eq(pane.on.enabled, false)
    near(pane.on.frame:GetAlpha(), 0.35, "so the rest is greyed out")
    eq(pane.onNote:GetText(), "This skill has no icon, so the settings below are not used.", "and the pane says why")
    eq(pane.lasts:GetText(), "", "it has no duration")
    eq(pane.lasts:IsEnabled(), false)
    eq(pane.stacks:IsEnabled(), false)
    eq(pane.shared.enabled, false)
    eq(pane.shared.picked, nil)
    near(pane.shared.frame:GetAlpha(), 0.35, "the two buttons for other players are drawn fainter")
    eq(pane.lastsNote:GetText(), "", "and no row has anything to say about a skill with no icon")
    eq(pane.stacksNote:GetText(), "")
    eq(pane.sharedNote:GetText(), "")
    eq(pane.immuneNote:GetText(), "")
    w:click(pane.on.buttons.all)
    w:click(pane.shared.buttons.anyone)
    eq(ns.db.spells["Heroic Strike"], nil, "a click on what is greyed out does nothing")

    local title, says = Says(w, pane.whyArea)
    eq(title, "Heroic Strike")
    eq(says, "It has no icon because it does not seem to leave a buff or a debuff behind. Choose Always if you want "
        .. "it to have one anyway.", "the mouse on the reason adds what can be done about it")
    title, says = Says(w, pane.showArea)
    eq(title, "Show an icon")
    check(says:find("With Auto the addon decides", 1, true), "and the setting itself is explained: " .. says)
    w:click(rows[2])
    eq(Says(w, pane.on.buttons.all), "A debuff on every enemy in the fight")

    -- The spell that is picked stays picked while the tab is away.
    w:click(view.tabs.display)
    w:click(view.tabs.spells)
    eq(pane.name:GetText(), "Rend")
    eq(rows[2].selected, true)
    Clean(w)
end)

test("settings: when the spell that is picked leaves the bars, the first of the list is picked instead", function()
    local w = Simple()
    local view = w:openSettings().view
    local pane = Pane(w, view, "Rend")
    w:addButton("ActionButton1", 1, nil) -- Rend is dragged off the bar
    w:advance(8)
    eq(view.footer:GetText(), "2 skills are on your bars. 1 has an icon.")
    eq(pane.name:GetText(), "Battle Shout")
    eq(view.spells.rows[1].selected, true)
    Clean(w)
end)

panel("Skills tab: Auto, Always and Never", function(options)
    local w, ns = Simple(options)
    local view = w:openSettings().view
    w:click(view.tabs.spells)
    w:advance(0.3)
    local rows = view.spells.rows
    eq(w:icon("ActionButton2"), nil, "Heroic Strike has no icon")

    local pane = Pane(w, view, "Heroic Strike")
    w:click(pane.show.buttons.always)
    eq(ns.db.spells["Heroic Strike"].track, true)
    w:advance(0.5)
    eq(w:icon("ActionButton2"), "check", "now it has")
    eq(rows[3].name:GetText(), "Heroic Strike", "the line stays where it is while the tab is open")
    check(rows[3].status:GetText():find("^Debuff on your target, "), "and says who it is now judged on: " .. rows[3].status:GetText())
    eq(rows[3].icon.desaturated, false)
    eq(pane.show.picked, "always")
    eq(pane.on.picked, "target")
    eq(pane.on.enabled, true, "the rest of the pane comes to life")
    near(pane.on.frame:GetAlpha(), 1)
    eq(pane.shared.enabled, true)
    near(pane.shared.frame:GetAlpha(), 1, "the two buttons for other players with it")
    eq(pane.why:GetText(), "You chose Always, so it has an icon.")
    local _, says = Says(w, pane.whyArea)
    eq(says, "You chose Always, so it has an icon. Choose Auto to let the addon decide again.")
    eq(view.footer:GetText(), "3 skills are on your bars. 3 have an icon and you have changed 1.",
        "the line at the bottom counts the skills that carry a choice of yours")

    pane = Pane(w, view, "Rend")
    w:click(pane.show.buttons.never)
    eq(ns.db.spells.Rend.track, false)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), nil, "Rend lost its icon")
    eq(pane.show.picked, "never")
    eq(pane.why:GetText(), "You chose Never, so it has no icon.")
    eq(pane.on.enabled, false)
    eq(rows[2].status:GetText(), "No icon")

    w:click(pane.show.buttons.auto)
    eq(ns.db.spells.Rend, nil, "back to automatic leaves nothing behind")
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "check")
    w:click(Pane(w, view, "Heroic Strike").show.buttons.auto)
    eq(view.footer:GetText(), "3 skills are on your bars. 2 have an icon.", "and nothing to count")

    pane = Pane(w, view, "Battle Shout")
    w:slash("ignore battle shout")
    eq(pane.show.picked, "never", "/se ignore shows here straight away")
    w:slash("auto battle shout")
    eq(pane.show.picked, "auto")

    -- Opened again, the list is sorted afresh, and the spell that was picked still is.
    pane = Pane(w, view, "Rend")
    w:click(pane.show.buttons.never)
    w:click(view.tabs.display)
    w:click(view.tabs.spells)
    eq(rows[1].name:GetText(), "Battle Shout")
    eq(rows[2].name:GetText(), "Heroic Strike", "the spell that gained an icon moved up")
    eq(rows[3].name:GetText(), "Rend", "and the one that lost its icon moved down")
    eq(rows[3].selected, true, "still picked, in its new place")
    eq(pane.name:GetText(), "Rend")
    Clean(w)
end)

panel("Skills tab: who a spell is judged on, and how long its effect lasts", function(options)
    local w, ns = Simple(options)
    local view = w:openSettings().view
    local rend, row = Pane(w, view, "Rend")

    w:click(rend.on.buttons.all)
    eq(ns.db.spells.Rend.aoe, true, "every enemy in the fight")
    eq(rend.on.picked, "all")
    eq(rend.onNote:GetText(), "The icon tells you whether all enemies in the fight have the effect, some, or none.")
    eq(row.status:GetText(), "Debuff on all enemies, 21 s", "the line in the list follows")
    eq(rend.summary:GetText(), "Offensive: debuff on all enemies, 21 s", "and so does the head of the pane")
    w:click(rend.on.buttons.target)
    eq(ns.db.spells.Rend.aoe, false, "your target only")
    w:click(rend.on.buttons.self)
    eq(ns.db.spells.Rend.kind, "buff", "the same as /se buff")
    eq(ns.db.spells.Rend.track, true)
    eq(rend.on.picked, "self")
    eq(rend.summary:GetText(), "Defensive: buff on you, 21 s", "which makes it a defensive skill")
    w:click(rend.on.buttons.target)
    eq(ns.db.spells.Rend.kind, "debuff", "and as /se debuff")
    eq(rend.on.picked, "target")

    eq(rend.lasts:GetText(), "21 s")
    eq(rend.lastsNote:GetText(), "The addon read this from the skill's tooltip.",
        "where the figure comes from is said under the box")
    rend.lasts:SetFocus()
    eq(rend.lasts:GetText(), "21", "typing starts from the bare number")
    w:type(rend.lasts, "21")
    eq(ns.db.spells.Rend.duration, nil, "Enter on what was there changes nothing: the addon's figure stays the addon's")
    eq(rend.lasts:HasFocus(), false, "and closes the box")
    eq(rend.lasts:GetText(), "21 s")
    w:type(rend.lasts, "30")
    eq(ns.db.spells.Rend.duration, 30)
    eq(rend.lasts:GetText(), "30 s")
    eq(rend.lastsNote:GetText(), "You set this yourself.")
    eq(rend.lasts:HasFocus(), false)
    w:type(rend.lasts, "2 min")
    eq(ns.db.spells.Rend.duration, 120, "minutes are understood")
    eq(rend.lasts:GetText(), "2 min")
    w:type(rend.lasts, "120")
    eq(ns.db.spells.Rend.duration, 120, "Enter on a figure of your own leaves that yours")

    w:type(rend.lasts, "soon")
    eq(rend.lastsNote:GetText(), "Type a number of seconds from 1 to 3600.", "a bad entry is explained under the box")
    eq(ns.db.spells.Rend.duration, 120, "and changes nothing")
    eq(rend.lasts:HasFocus(), true, "the box stays open to put it right")
    w:type(rend.lasts, "99999")
    check(rend.lastsNote:GetText():find("from 1 to 3600", 1, true), "so is one that is out of range")
    w:escape(rend.lasts)
    eq(rend.lastsNote:GetText(), "You set this yourself.", "Escape drops the complaint")
    eq(rend.lasts:GetText(), "2 min", "and the typing")

    w:type(rend.lasts, "")
    eq(ns.db.spells.Rend.duration, nil, "emptying the box lets the addon work it out again")
    eq(rend.lasts:GetText(), "21 s")
    local title, says = Says(w, rend.lasts)
    eq(title, "How long the effect lasts")
    eq(says, "The addon read this from the skill's tooltip. Type a number of seconds to change it, or empty the box "
        .. "to let the addon work it out.", "the box says where the duration comes from, and how to change it")

    -- A complaint does not follow you to another spell.
    w:type(rend.lasts, "soon")
    local shout = Pane(w, view, "Battle Shout")
    eq(shout.lastsNote:GetText(), "The addon read this from the skill's tooltip.")
    eq(shout.lasts:HasFocus(), false)
    eq(shout.lasts:GetText(), "2 min")
    Clean(w)
end)

panel("Skills tab: Reset this skill forgets your own choices for one skill", function(options)
    local w, ns = Simple(options)
    local view = w:openSettings().view
    local pane = Pane(w, view, "Rend")
    eq(pane.reset:IsEnabled(), false, "nothing to forget to begin with")
    eq(pane.resetNote:GetText(), "You have not changed this skill.", "and the pane says why the button is greyed")

    w:click(pane.on.buttons.all)
    w:type(pane.lasts, "30")
    eq(pane.reset:IsEnabled(), true)
    eq(pane.resetNote:GetText(), "You have changed this skill.")
    local title, says = Says(w, pane.reset)
    eq(title, "Reset this skill")
    check(says:find("What the addon has learned about the skill in your fights is kept.", 1, true), says)
    w:slash("track heroic strike")

    w:click(pane.reset)
    eq(ns.db.spells.Rend, nil)
    check(ns.db.spells["Heroic Strike"] ~= nil, "the other skills keep your choices")
    eq(pane.on.picked, "target")
    eq(pane.lasts:GetText(), "21 s")
    eq(pane.reset:IsEnabled(), false)
    eq(pane.resetNote:GetText(), "You have not changed this skill.")

    -- A choice made with a command shows here as one to reset.
    w:slash("duration rend 40")
    eq(pane.reset:IsEnabled(), true, "/se duration counts as a change of yours")
    w:click(pane.reset)
    eq(ns.db.spells.Rend, nil)

    -- Resetting a spell you had turned on takes its icon away again.
    pane = Pane(w, view, "Heroic Strike")
    eq(pane.show.picked, "always")
    w:click(pane.reset)
    eq(ns.db.spells["Heroic Strike"], nil)
    eq(pane.show.picked, "auto")
    w:advance(0.5)
    eq(w:icon("ActionButton2"), nil)
    Clean(w)
end)

panel("Skills tab: how many times an effect stacks", function(options)
    options.saved = Proven()
    local w, ns = Bar(options, SUNDER, REND, FRENZY, HEROIC)
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:advance(0.3)
    local view = w:openSettings().view
    local pane = Pane(w, view, "Sunder Armor")
    local stacks, note = pane.stacks, pane.stacksNote

    eq(stacks:GetText(), "5", "Sunder Armor: as its tooltip says")
    eq(stacks.textColor[1], 1)
    eq(note:GetText(), "The addon read this from the skill's tooltip.", "where the number comes from is said under the box")
    local title, says = Says(w, stacks)
    eq(title, "How many times the effect stacks")
    check(says:find("^The addon read this from the skill's tooltip%. "), "the box says where the number comes from: " .. says)
    check(says:find("The icon shows the skill as worth casting until all of these stacks are there.", 1, true),
        "and what it does to the icon: " .. says)
    Pane(w, view, "Battle Frenzy")
    eq(stacks:GetText(), "3", "a buff that stacks")
    Pane(w, view, "Rend")
    eq(stacks:GetText(), "-", "a dash for an effect that goes on once, as most do")
    eq(stacks.textColor[1], 0.5, "in grey")
    eq(note:GetText(), "This effect does not stack.")
    title, says = Says(w, stacks)
    eq(says, "The addon found nothing that says this effect stacks. If it does, type the most stacks it can have.")
    Pane(w, view, "Heroic Strike")
    eq(stacks:IsEnabled(), false, "a spell with no icon has no stacks to set")
    eq(stacks:GetText(), "")
    eq(note:GetText(), "")
    eq(pane.shared.enabled, false, "and nobody whose effect could count")

    -- Typing a number is the same as /se stacks.
    Pane(w, view, "Rend")
    stacks:SetFocus()
    eq(stacks:GetText(), "", "typing starts from an empty box for an effect that does not stack")
    w:type(stacks, "3")
    eq(ns.db.spells.Rend.stacks, 3)
    eq(stacks:GetText(), "3")
    eq(stacks.textColor[1], 1, "no longer grey")
    eq(stacks:HasFocus(), false)
    eq(note:GetText(), "You set this yourself.")
    title, says = Says(w, stacks)
    check(says:find("^You set this yourself%. The icon shows the skill as worth casting until"), says)
    w:type(stacks, "1")
    eq(ns.db.spells.Rend.stacks, 1, "1 says that it does not stack, whatever the addon makes of it")
    eq(stacks:GetText(), "1", "which shows as your 1, not as the addon's dash")
    eq(note:GetText(), "You set this yourself: the effect does not stack.")
    title, says = Says(w, stacks)
    check(says:find("^You set this yourself: the effect does not stack%. To change it, "), says)
    stacks:SetFocus()
    eq(stacks:GetText(), "1", "typing starts from your own number")
    w:type(stacks, "1")
    eq(ns.db.spells.Rend.stacks, 1, "Enter on what was there changes nothing")
    eq(stacks:HasFocus(), false)
    w:type(stacks, "")
    eq(ns.db.spells.Rend, nil, "emptying the box lets the addon work it out again, and leaves nothing behind")
    eq(stacks:GetText(), "-")
    eq(stacks.textColor[1], 0.5)

    Pane(w, view, "Sunder Armor")
    stacks:SetFocus()
    eq(stacks:GetText(), "5", "typing starts from the bare number")
    w:type(stacks, "5")
    eq(ns.db.spells["Sunder Armor"], nil, "Enter on the addon's own figure does not make it yours")
    eq(stacks:HasFocus(), false, "it only closes the box")

    for _, bad in ipairs({ "many", "0", "101", "2.5", "-3", "1e1" }) do
        w:type(stacks, bad)
        eq(note:GetText(), "Type a number from 1 to 100.", "\"" .. bad .. "\" is explained under the box")
        eq(ns.db.spells["Sunder Armor"], nil, "\"" .. bad .. "\" changes nothing")
        eq(stacks:HasFocus(), true, "and the box stays open to put it right")
    end
    w:escape(stacks)
    eq(note:GetText(), "The addon read this from the skill's tooltip.", "Escape drops the complaint")
    eq(stacks:GetText(), "5", "and the typing")
    w:type(stacks, " 4 ")
    eq(ns.db.spells["Sunder Armor"].stacks, 4, "spaces around the number do not matter")
    for _, auto in ipairs({ "auto", "-" }) do
        w:type(stacks, "4")
        w:type(stacks, auto)
        eq(ns.db.spells["Sunder Armor"], nil, "\"" .. auto .. "\" goes back to the addon's figure, like an empty box")
    end

    -- The number typed here is the one the icons go by, from the next moment on.
    for _ = 1, 2 do
        w:cast(SUNDER)
        w:advance(1.5)
    end
    eq(w:icon("ActionButton1"), "check", "two of five")
    w:type(stacks, "2")
    eq(ns.db.spells["Sunder Armor"].stacks, 2)
    w:advance(0.1)
    eq(w:icon("ActionButton1"), "cross", "two of two: full by the number typed in the panel, with no cast in between")

    w:slash("stacks sunder armor 4")
    eq(stacks:GetText(), "4", "/se stacks shows here straight away")
    w:advance(0.1)
    eq(w:icon("ActionButton1"), "check", "two of four")
    w:slash("stacks sunder armor auto")
    eq(stacks:GetText(), "5")
    eq(ns.db.spells["Sunder Armor"], nil)
    Clean(w)
end)

test("settings: the box for an effect's stacks says where each number comes from", function()
    -- The game's own figure, for a tooltip that does not say.
    local w, ns = World()
    w:addSpell(900, {
        name = "Festering Bite", harmful = true, cumulative = 4,
        description = "Bites the target, festering its wounds for 12 sec.",
        effect = { duration = 12, stacks = 4 },
    })
    w:addSpell(901, {
        name = "Creeping Rot", harmful = true,
        description = "Rots the target for 12 sec.",
        effect = { duration = 12, shared = true, stacks = 3 },
    })
    w:addButton("ActionButton1", 1, 900)
    w:addButton("ActionButton2", 2, 901)
    ns = w:load(Proven())
    local boar = w:addMob("Boar")
    w:showPlate(boar)
    w:target(boar)
    w:advance(0.3)
    local view = w:openSettings().view
    local pane = Pane(w, view, "Festering Bite")
    eq(pane.stacks:GetText(), "4")
    eq(pane.stacksNote:GetText(), "The game gives this number for the skill.")
    local _, says = Says(w, pane.stacks)
    check(says:find("^The game gives this number for the skill%. "), says)

    -- And what was read off a unit, which the effect may yet outgrow.
    Pane(w, view, "Creeping Rot")
    eq(pane.stacks:GetText(), "-", "nothing says that it stacks")
    for _ = 1, 2 do
        w:applyAura(boar, "Creeping Rot", 12, true, nil, nil, { shared = true, stacks = 3 })
    end
    w:advance(1.5)
    eq(ns.db.learned["Creeping Rot"].stacks, 2, "twice over on the boar")
    eq(pane.stacks:GetText(), "2", "what the addon sees shows up in the open panel by itself")
    eq(pane.stacksNote:GetText(), "The addon has seen this many. It may go higher.")
    _, says = Says(w, pane.stacks)
    check(says:find("^The addon has seen this many%. It may go higher%. "), says)
    Clean(w)
end)

panel("Skills tab: whether another player's effect counts", function(options)
    local w, ns, boar = Party(options, SUNDER, REND, RAGING, BLOCK)
    local view = w:openSettings().view
    local pane = Pane(w, view, "Sunder Armor")
    local shared, note = pane.shared, pane.sharedNote
    local anyone, mine = shared.buttons.anyone, shared.buttons.mine

    -- Two buttons, of which one is picked: there is no tick to read the wrong way round.
    eq(anyone.label:GetText(), "Count theirs")
    eq(mine.label:GetText(), "Ignore theirs")
    eq(shared.picked, "anyone", "an enemy carries Sunder Armor once, whoever put it there")
    eq(anyone.picked, true)
    eq(mine.picked, false)
    eq(note:GetText(), "The icon treats another player's Sunder Armor on the enemy like your own. The addon read this "
        .. "from its tooltip.", "what the choice does is said under the buttons in a whole sentence, and who decided")
    local title, says = Says(w, anyone)
    eq(title, "Count another player's effect")
    check(says:find("for an effect that a target can only have once, whoever put it there", 1, true), says)
    title, says = Says(w, mine)
    eq(title, "Only count your own effect")
    check(says:find("for an effect that every player puts on a target separately, such as a bleed", 1, true), says)
    Pane(w, view, "Raging Shout")
    eq(shared.picked, "anyone", "and you one shout, whichever warrior shouted")
    eq(note:GetText(), "The icon treats another player's Raging Shout on you like your own. The addon read this from "
        .. "its tooltip.", "a buff is on you, not on an enemy")
    Pane(w, view, "Rend")
    eq(shared.picked, "mine", "a bleed is its caster's own")
    eq(mine.picked, true)
    eq(note:GetText(), "The icon ignores another player's Rend and only looks for yours. The addon read this from its "
        .. "tooltip.")
    Pane(w, view, "Shield Block")
    eq(shared.enabled, false, "nobody else can put Shield Block on you: nothing to choose")
    eq(shared.picked, nil, "so neither button is picked")
    eq(note:GetText(), "No other player can put Shield Block on you, so there is nothing to choose here.",
        "and the pane says so")
    eq(pane.stacks:IsEnabled(), true, "though it could stack")
    w:click(anyone)
    eq(ns.db.spells["Shield Block"], nil, "a click on the greyed buttons does nothing")
    eq(shared.picked, nil)

    -- Another warrior's Sunder Armor is on the boar, as many times over as it goes.
    Pane(w, view, "Sunder Armor")
    for _ = 1, 5 do
        w:applyAura(boar, "Sunder Armor", 30, false, nil, nil, { shared = true, stacks = 5 })
    end
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "theirs counts: five of five")

    w:drain()
    w:click(mine)
    eq(ns.db.spells["Sunder Armor"].shared, false, "Ignore theirs: the same as /se mine")
    eq(shared.picked, "mine")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "and their effect stops counting at once")
    eq(note:GetText(), "The icon ignores another player's Sunder Armor and only looks for yours. You chose this.")
    w:click(mine)
    eq(ns.db.spells["Sunder Armor"].shared, false, "a second click on the same button changes nothing")

    w:click(anyone)
    eq(ns.db.spells["Sunder Armor"], nil, "back to what the addon made of it: nothing of yours is left behind")
    eq(shared.picked, "anyone")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "and their effect counts again at once")

    Pane(w, view, "Rend")
    w:click(anyone)
    eq(ns.db.spells.Rend.shared, true, "Count theirs: the same as /se anyone")
    w:applyAura(boar, "Rend", 21, false)
    w:advance(0.3)
    eq(w:icon("ActionButton2"), "cross", "now their Rend counts like yours")
    eq(note:GetText(), "The icon treats another player's Rend on the enemy like your own. You chose this.")
    w:click(mine)
    eq(ns.db.spells.Rend, nil)
    w:advance(0.3)
    eq(w:icon("ActionButton2"), "check", "and theirs is theirs again")
    eq(w:drain(), "", "the panel says nothing of this in chat")

    -- The commands show in the pane at once, and a click undoes them like any other choice.
    Pane(w, view, "Sunder Armor")
    w:slash("mine sunder armor")
    eq(shared.picked, "mine", "/se mine shows here straight away")
    w:slash("anyone sunder armor")
    eq(shared.picked, "anyone", "and so does /se anyone")
    eq(ns.db.spells["Sunder Armor"].shared, true, "which keeps the choice even where the addon agrees")
    check(note:GetText():find(" You chose this.", 1, true), note:GetText())
    w:click(mine)
    eq(ns.db.spells["Sunder Armor"].shared, false)
    w:click(anyone)
    eq(ns.db.spells["Sunder Armor"], nil)
    check(note:GetText():find(" The addon read this from its tooltip.", 1, true), note:GetText())

    -- A skill that loses its icon has nobody whose effect could count.
    w:click(pane.show.buttons.never)
    eq(shared.enabled, false)
    eq(shared.picked, nil)
    eq(pane.stacks:IsEnabled(), false)
    eq(note:GetText(), "")
    w:click(pane.show.buttons.auto)
    eq(shared.enabled, true)
    eq(shared.picked, "anyone")
    Clean(w)
end)

panel("Skills tab: ignoring another player's effect in the middle of a fight drops it at once", function(options)
    local w, ns, _, warrior = Party(options, DEMO, REND)
    local view = w:openSettings().view
    local demo = Pane(w, view, "Demoralizing Shout")
    eq(demo.shared.picked, "anyone")
    Open(w)
    w:partyCast(warrior, DEMO)
    w:advance(0.3)
    w:cast(REND)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "cross", "their shout")
    eq(w:icon("ActionButton2"), "cross", "your Rend")

    w:click(demo.shared.buttons.mine)
    eq(ns.db.spells["Demoralizing Shout"].shared, false)
    w:advance(0.1)
    eq(w:icon("ActionButton1"), "check", "theirs no longer counts, and nothing can be read to say so")
    eq(w:icon("ActionButton2"), "cross", "what is yours stays")
    w:partyCast(warrior, DEMO)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "and their next one is not followed")

    w:click(demo.shared.buttons.anyone)
    eq(ns.db.spells["Demoralizing Shout"], nil, "counted again")
    w:partyCast(warrior, DEMO)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "and the one after that counts again")
    Clean(w)
end)

panel("Skills tab: a reset drops another player's effect that only a choice of yours made count", function(options)
    local w, ns, _, warrior = Party(options, DEMO, REND)
    local view = w:openSettings().view
    local rend = Pane(w, view, "Rend")
    eq(rend.shared.picked, "mine", "a bleed is its caster's own")
    w:click(rend.shared.buttons.anyone)
    eq(ns.db.spells.Rend.shared, true)
    Open(w)
    w:partyCast(warrior, REND)
    w:advance(0.3)
    eq(w:icon("ActionButton2"), "cross", "their Rend counts, because you said so")

    w:click(rend.reset)
    eq(ns.db.spells.Rend, nil)
    w:advance(0.1)
    eq(w:icon("ActionButton2"), "check", "reset: theirs no longer counts, and nothing can be read to say so")

    -- A skill their copy counts for anyway keeps it through a reset.
    local demo = Pane(w, view, "Demoralizing Shout")
    w:partyCast(warrior, DEMO)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "their shout")
    w:type(demo.lasts, "40")
    eq(ns.db.spells["Demoralizing Shout"].duration, 40)
    w:click(demo.reset)
    eq(ns.db.spells["Demoralizing Shout"], nil)
    w:advance(0.1)
    eq(w:icon("ActionButton1"), "cross", "a reset that changes nothing about whose copy counts leaves theirs alone")

    -- Defaults does the same, also for a skill that has left the bars meanwhile.
    Pane(w, view, "Rend")
    w:click(rend.shared.buttons.anyone)
    w:partyCast(warrior, REND)
    w:advance(0.3)
    eq(w:icon("ActionButton2"), "cross")
    w:addButton("ActionButton2", 2, nil) -- Rend is dragged off the bar, back on, and off again
    w:advance(1.5)
    w:addButton("ActionButton2", 2, REND)
    w:advance(1.5)
    eq(w:icon("ActionButton2"), "cross", "their copy is still counted while the choice stands")
    w:addButton("ActionButton2", 2, nil)
    w:advance(1.5)
    w:click(view.defaults)
    w:click(view.confirm.yes)
    eq(ns.db.spells.Rend, nil)
    w:addButton("ActionButton2", 2, REND)
    w:advance(1.5)
    eq(w:icon("ActionButton2"), "check", "back on the bar after that, their copy from before is not counted")
    Clean(w)
end)

test("settings: a skill whose tooltip could not be read says so in the row for other players", function()
    local w = World()
    w:addSpell(902, { name = "Strange Brand", harmful = true, effect = { duration = 20, shared = true } })
    w:addButton("ActionButton1", 1, 902)
    local ns = w:load()
    w:slash("track strange brand")
    local view = w:openSettings().view
    local pane = Pane(w, view, "Strange Brand")
    eq(pane.shared.picked, "mine", "it counts as your own until you say otherwise")
    eq(pane.sharedNote:GetText(), "The addon could not read this skill's tooltip, so to be safe the icon only looks for "
        .. "your own Strange Brand.")
    w:click(pane.shared.buttons.anyone)
    eq(ns.db.spells["Strange Brand"].shared, true)
    eq(pane.shared.picked, "anyone")
    eq(pane.sharedNote:GetText(), "The icon treats another player's Strange Brand on the enemy like your own. You chose "
        .. "this.")
    w:click(pane.shared.buttons.mine)
    eq(ns.db.spells["Strange Brand"].shared, nil, "back to what the addon does by itself")
    check(pane.sharedNote:GetText():find("^The addon could not read this skill's tooltip"), pane.sharedNote:GetText())
    Clean(w)
end)

test("settings: the list of the Skills tab and the pane beside it keep clear of each other", function()
    for _, wider in ipairs({ 1, 1.35, 2 }) do
        local what = "letters " .. wider .. " times as wide"
        local w = Bar({ fontWidth = wider }, SUNDER, REND, RAGING)
        local view = w:openSettings().view
        local pane, row = Pane(w, view, "Sunder Armor")
        local list = view.spells

        -- Side by side on the page: the list, its scroll bar, the pane.
        local rowLeft, barLeft, paneLeft = row.point[4], list.bar.point[4], pane.point[4]
        check(rowLeft + row.width <= barLeft, "the list ends before its scroll bar, with " .. what)
        check(barLeft + list.bar.width + 4 <= paneLeft, "and the bar well before the pane")
        check(paneLeft + pane.width <= 624.01, "which ends inside the page")
        local offensive, defensive = list.groups.offensive, list.groups.defensive
        eq(pane.point[5], offensive.point[5], "the pane starts level with the first line")
        eq(offensive.point[4], rowLeft, "the two groups' lines start where the skills' lines do")
        eq(offensive.width, row.width, "and are as wide")
        check(offensive.point[5] - offensive.height >= defensive.point[5]
            and defensive.point[5] - defensive.height >= list.rows[1].point[5], "the two groups come first, then the skills")
        check(-list.rows[#list.rows].point[5] + row.height <= 514 - 34, "the last line ends above the strip at the bottom")
        for _, group in ipairs({ offensive, defensive }) do
            local last = group.faces[#group.faces]
            check(last.point[4] + last.width + 4 <= group.title.point[4], "a group's pictures end before its name")
            check(-last.point[5] + last.height <= group.height, "and inside its line")
            eq(group.status.point[4], group.title.point[4])
            check(group.title:GetStringWidth() <= group.title.fitRoom + 0.5
                and group.status:GetStringWidth() <= group.status.fitRoom + 0.5, "a group's words keep to their room, with " .. what)
            check(group.title.point[4] + group.title.fitRoom <= group.width, "which ends inside the line")
        end

        -- In a line: the picture, then the name over the few words about it.
        local textLeft = row.name.point[4]
        check(row.icon.point[4] + row.icon.width + 4 <= textLeft, "the picture ends before the name")
        eq(row.status.point[4], textLeft, "the words about it start under the name")
        check(row.name:GetStringWidth() <= row.name.fitRoom + 0.5 and row.status:GetStringWidth() <= row.status.fitRoom + 0.5,
            "both keep to their room, with " .. what)
        check(textLeft + row.name.fitRoom <= row.width, "which ends inside the line")

        -- In the pane every setting is a row: what it is called at the left, its
        -- control beside that, and under both, across the whole pane, a sentence
        -- of so many lines. No row runs into the one under it.
        local names = pane.showArea.label.fitRoom
        check(pane.showArea.label:GetStringWidth() <= names + 0.5, "what a row is called keeps to its room, with " .. what)
        local parts = {
            { "Show an icon", pane.show.frame, pane.show.width, pane.why, 2 },
            { "Affects", pane.on.frame, pane.on.width, pane.onNote, 2 },
            { "Lasts", pane.lasts, pane.lasts:GetWidth(), pane.lastsNote, 1 },
            { "Stacks up to", pane.stacks, pane.stacks:GetWidth(), pane.stacksNote, 1 },
            { "Other players", pane.shared.frame, pane.shared.width, pane.sharedNote, 3 },
            { "Immune", pane.mark, pane.forget.point[4] + pane.forget.width - pane.mark.point[4], pane.immuneNote, 3 },
        }
        local button = -pane.height + 4 + pane.reset.height -- the top of the button at the bottom of the pane
        for i, part in ipairs(parts) do
            local name, control, width, note, lines = part[1], part[2], part[3], part[4], part[5]
            local left, top = control.point[4], control.point[5]
            check(left >= names + 8, name .. " starts clear of the names, with " .. what)
            check(left + width <= pane.width + 0.01, name .. " ends inside the pane, with " .. what)
            eq(note.point[4], 0, name .. ": its sentence starts at the pane's left edge")
            check(note.point[5] <= top - 22, name .. ": under its control")
            check(note.fitRoom <= pane.width + 0.01, name .. ": and no wider than the pane, with " .. what)
            local under = parts[i + 1] and parts[i + 1][2].point[5] or button
            check(note.point[5] - lines * 13 >= under + 2, name .. ": its sentence ends above what is under it")
        end
        -- The words at the left of the button at the bottom end before it.
        check(pane.resetNote.fitRoom + 8 <= pane.width - pane.reset.width, "the words at the button's left end before it")
        Clean(w)
    end
end)

--------------------------------------------------------------------------------
-- The settings panel: the Immune row of the Skills tab
--------------------------------------------------------------------------------

--- What an earlier session would have saved of creatures found immune: for
--- Rend two kinds the game said twice or more and one it said once, and one
--- kind for Sunder Armor.
local function FoundImmune()
    local saved = Proven()
    saved.immune = {
        Rend = {
            ["#2001"] = { seen = 2, name = "Fire Elemental" },
            ["#2002"] = { seen = 3, name = "Rock Elemental" },
            ["#2003"] = { seen = 1, name = "Water Elemental" },
        },
        ["Sunder Armor"] = {
            ["#2004"] = { seen = 2, name = "Mud Golem" },
        },
    }
    return saved
end

--- The words on a push button.
local function Words(button)
    if button.native then
        return button:GetText()
    end
    return button.label:GetText()
end

panel("Skills tab: the kinds of enemy found immune to a skill", function(options)
    options.saved = FoundImmune()
    local w, ns = Party(options, REND, SUNDER, SHOUT, HEROIC, DEMO)
    local view = w:openSettings().view
    local pane = Pane(w, view, "Rend")
    local title, says = Says(w, pane.immuneLabel)
    eq(title, "Immune")
    eq(says, "These are the enemies this skill does not work on. When the game says \"Immune\" after one of your casts, "
        .. "the addon remembers what kind of enemy that was. From the second time on, the icon stops asking you to cast "
        .. "the skill on enemies of that kind.")

    -- The ones the addon counts on come first, then the ones the game said once.
    eq(pane.immuneNote:GetText(), "Immune: Fire Elemental, Rock Elemental. Seen immune once so far: Water Elemental.")
    eq(pane.mark:IsEnabled(), true)
    eq(pane.forget:IsEnabled(), true)
    local head, lines = w:hover(pane.immuneArea)
    eq(head, "Immune to Rend")
    eq(#lines, 3, "one line for each kind")
    eq(lines[1], "Fire Elemental")
    eq(lines[2], "Rock Elemental")
    eq(lines[3], "Water Elemental (seen once so far)")
    w:unhover(pane.immuneArea)

    pane = Pane(w, view, "Sunder Armor")
    eq(pane.immuneNote:GetText(), "Immune: Mud Golem.", "each skill has its own")

    -- Nothing found yet: nothing to clear, and no tooltip with nothing in it.
    pane = Pane(w, view, "Demoralizing Shout")
    eq(pane.immuneNote:GetText(), "The addon has not found an enemy that is immune to this skill.")
    eq(pane.mark:IsEnabled(), true, "a creature can still be added")
    eq(pane.forget:IsEnabled(), false)
    eq((w:hover(pane.immuneArea)), nil, "no tooltip over an empty list")
    w:unhover(pane.immuneArea)

    -- A skill that lands on you or your friends meets nothing immune.
    pane = Pane(w, view, "Battle Shout")
    eq(pane.immuneNote:GetText(), "This skill is not used on enemies, so nothing can be immune to it.")
    eq(pane.mark:IsEnabled(), false)
    eq(pane.forget:IsEnabled(), false)

    -- And a skill without an icon has nothing to say about it.
    pane = Pane(w, view, "Heroic Strike")
    eq(pane.immuneNote:GetText(), "")
    eq(pane.mark:IsEnabled(), false)
    eq(pane.forget:IsEnabled(), false)
    if options.noTemplates then
        near(pane.mark:GetAlpha(), 0.35, "a greyed button of the addon's own drawing looks greyed")
        near(pane.reset:GetAlpha(), 0.35, "Reset this skill too")
        pane = Pane(w, view, "Rend")
        near(pane.mark:GetAlpha(), 1, "and a live one live")
    end
    Clean(w)
end)

panel("Skills tab: a long list of immune enemies is cut short, in the pane and in its tooltip", function(options)
    -- Thirty-two kinds: nine the game said twice, the rest once.
    local kinds = {}
    local first = { "Ashen Colossus", "Bog Lurker", "Cinder Wraith", "Dune Stalker", "Ember Sprite", "Frost Revenant",
        "Gale Fury", "Hollow Shade", "Iron Sentinel" }
    for i, name in ipairs(first) do
        kinds["#" .. (3000 + i)] = { seen = 2, name = name }
    end
    for i = 1, 23 do
        kinds["#" .. (3100 + i)] = { seen = 1, name = string.format("Mist Walker %02d", i) }
    end
    local saved = Proven()
    saved.immune = { Rend = kinds }
    options.saved = saved
    local w, ns = Party(options, REND)
    local view = w:openSettings().view
    local pane = Pane(w, view, "Rend")
    eq(pane.immuneNote:GetText(), "Immune: Ashen Colossus, Bog Lurker, Cinder Wraith and 6 more. Seen immune once so far: "
        .. "Mist Walker 01 and 22 more.", "as many names as there is room for, and how many more")
    check(#pane.immuneNote:GetText() <= 120, "which is what three lines of the pane hold in a font a third wider")
    local head, lines = w:hover(pane.immuneArea)
    eq(head, "Immune to Rend")
    eq(#lines, 31, "thirty kinds and a line for the rest")
    eq(lines[1], "Ashen Colossus")
    eq(lines[10], "Mist Walker 01 (seen once so far)")
    eq(lines[31], "and 2 more")
    w:unhover(pane.immuneArea)
    Clean(w)
end)

panel("Skills tab: Add target says that the enemy you have targeted is immune", function(options)
    options.combatIdentity = false -- in a fight this client will not say what a newcomer is
    local w, ns, boar = Party(options, REND, SUNDER)
    local view = w:openSettings().view
    local pane = Pane(w, view, "Rend")
    local title, says = Says(w, pane.mark)
    eq(title, "Add target")
    check(says:find("/se immune", 1, true), says)
    eq(Words(pane.mark), "Add target")
    local nobody = "The addon has not found an enemy that is immune to this skill."
    eq(pane.immuneNote:GetText(), nobody)

    -- Nothing targeted, then a player: it says why nothing was added.
    w:target(nil)
    w:click(pane.mark)
    eq(pane.immuneNote:GetText(), "Target an enemy first, then click Add target.")
    Meet(w, "Uther", { npc = false, guid = "Player-1-00000777" })
    w:click(pane.mark)
    eq(pane.immuneNote:GetText(), "Your target is a player. Only creatures can be added.")
    eq(pane.forget:IsEnabled(), false, "and nothing was added")
    eq(#ns.Spells:ImmuneKinds("Rend"), 0)

    -- The complaint does not wait for you at another skill and back.
    Pane(w, view, "Sunder Armor")
    pane = Pane(w, view, "Rend")
    eq(pane.immuneNote:GetText(), nobody)

    -- It goes with the next thing that works, too.
    w:target(nil)
    w:click(pane.mark)
    eq(pane.immuneNote:GetText(), "Target an enemy first, then click Add target.")
    w:target(boar)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "Rend is worth casting at the boar")
    w:click(pane.mark)
    eq(pane.immuneNote:GetText(), "Immune: Boar.", "counted on at once, on your say-so")
    local _, lines = w:hover(pane.immuneArea)
    eq(lines[1], "Boar (added by you)")
    w:unhover(pane.immuneArea)
    eq(pane.forget:IsEnabled(), true)
    eq(ns.db.immune.Rend["#" .. boar.kind].told, true, "kept the way /se immune keeps it")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "and no longer at a boar")
    eq(w:icon("ActionButton2"), "check", "the other skill has its own list")
    pane = Pane(w, view, "Sunder Armor")
    eq(pane.immuneNote:GetText(), nobody)

    -- /se immune does the same, and shows here at once.
    w:slash("immune sunder armor")
    w:drain()
    eq(pane.immuneNote:GetText(), "Immune: Boar.")
    eq(pane.forget:IsEnabled(), true)
    w:slash("immune forget sunder armor")
    w:drain()
    eq(pane.immuneNote:GetText(), nobody)
    eq(pane.forget:IsEnabled(), false)

    -- In a fight, a creature that walks in is one the game will not name.
    Open(w)
    Meet(w, "Fire Elemental")
    w:click(pane.mark)
    eq(pane.immuneNote:GetText(),
        "The game is hiding what your target is during this fight. Try again after the fight.")
    eq(pane.forget:IsEnabled(), false)

    -- A reason this panel has no words for gets a plain line.
    ns.MarkImmune = function()
        return nil, "asleep"
    end
    w:click(pane.mark)
    eq(pane.immuneNote:GetText(), "Your target could not be added.")
    Clean(w)
end)

panel("Skills tab: Clear list asks first, and clears the enemies found immune to one skill", function(options)
    options.saved = FoundImmune()
    local w, ns = Party(options, REND, SUNDER)
    -- A fire elemental walks up: one of the kinds Rend is known to do nothing to.
    Meet(w, "Fire Elemental", { kind = 2001 })
    eq(w:icon("ActionButton1"), "cross", "Rend is no use on it")
    eq(w:icon("ActionButton2"), "check")
    local view = w:openSettings().view
    local pane = Pane(w, view, "Rend")
    local title, says = Says(w, pane.forget)
    eq(title, "Clear list")
    eq(Words(pane.forget), "Clear list")
    eq(says, "Empties the list of enemies that are immune to this skill, including the ones you added yourself. You are "
        .. "asked to confirm first.")

    w:click(pane.forget)
    eq(view.confirm.frame:IsShown(), true, "it asks first")
    eq(view.question:GetText(), "Clear the list of enemies immune to Rend?")
    eq(Words(view.confirm.yes), "Clear", "the button says what a yes does")
    eq(view.footer:IsShown(), false, "in place of the line at the bottom")
    eq(pane.immuneNote:GetText(), "Immune: Fire Elemental, Rock Elemental. Seen immune once so far: Water Elemental.",
        "nothing is gone yet")
    w:click(view.confirm.no)
    eq(view.confirm.frame:IsShown(), false)
    eq(view.footer:IsShown(), true)
    eq(pane.forget:IsEnabled(), true, "Cancel leaves them alone")

    -- The question is about one skill: picking another puts it away.
    w:click(pane.forget)
    pane = Pane(w, view, "Sunder Armor")
    eq(view.confirm.frame:IsShown(), false, "the question went with the skill it was about")
    eq(view.footer:IsShown(), true)
    pane = Pane(w, view, "Rend")
    eq(pane.forget:IsEnabled(), true, "and nothing was forgotten")

    eq(w:icon("ActionButton1"), "cross", "the icons have not moved either")
    w:click(pane.forget)
    w:click(view.confirm.yes)
    eq(view.confirm.frame:IsShown(), false)
    eq(pane.immuneNote:GetText(), "The addon has not found an enemy that is immune to this skill.")
    eq(pane.forget:IsEnabled(), false)
    eq(#ns.Spells:ImmuneKinds("Rend"), 0)
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "and Rend is worth a try on the elemental again")
    pane = Pane(w, view, "Sunder Armor")
    eq(pane.immuneNote:GetText(), "Immune: Mud Golem.", "the other skill keeps its own")

    -- Defaults has its own word on the button, and its question stays while
    -- you look at another skill: it is about all of them.
    w:click(view.defaults)
    eq(Words(view.confirm.yes), "Reset")
    Pane(w, view, "Rend")
    eq(view.confirm.frame:IsShown(), true, "the Defaults question is still there")
    w:click(view.confirm.yes)
    pane = Pane(w, view, "Sunder Armor")
    eq(pane.immuneNote:GetText(), "Immune: Mud Golem.", "Defaults leaves the enemies found immune alone")

    -- So does Reset this skill.
    w:type(pane.lasts, "40")
    w:click(pane.reset)
    eq(ns.db.spells["Sunder Armor"], nil)
    eq(pane.immuneNote:GetText(), "Immune: Mud Golem.")
    Clean(w)
end)

--------------------------------------------------------------------------------
-- The settings panel: the offensive and the defensive skills, changed at once
--------------------------------------------------------------------------------

--- A party's bars for the two groups: four skills used on enemies, of which
--- Heroic Strike has no icon, and three used on yourself or on friends, of
--- which Shield Block is the caster's alone.
local function Grouped(options)
    return Party(options, SUNDER, REND, DEMO, HEROIC, RAGING, BLOCK, SHOUT)
end

-- In the order of the list: the skills with an icon by name, then the rest.
local OFFENSIVE = { "Demoralizing Shout", "Rend", "Sunder Armor", "Heroic Strike" }
local DEFENSIVE = { "Battle Shout", "Raging Shout", "Shield Block" }

--- Opens the Skills tab and picks one of the two groups, as a click on its
--- line does. Returns the pane for the group, and the group's line.
local function Group(w, view, key)
    if view.tab ~= "spells" then
        w:click(view.tabs.spells)
    end
    local line = view.spells.groups[key]
    w:click(line)
    eq(view.spells.group, key, "the group is picked")
    eq(line.selected, true, "and its line is marked")
    eq(view.groupPane:IsShown(), true, "the pane for a group shows")
    eq(view.pane:IsShown(), false, "in place of the pane for one skill")
    return view.groupPane, line
end

--- Whether a note is in the colour of a question that is waiting.
local function Waiting(note)
    return note.textColor[1] == 1 and math.abs(note.textColor[2] - 0.6) < 0.01
end

panel("Skills tab: two lines at the head of the list stand for the offensive and the defensive skills", function(options)
    local w, ns = Grouped(options)
    local view = w:openSettings().view
    w:click(view.tabs.spells)
    local list, pane, group = view.spells, view.pane, view.groupPane
    local offensive, defensive = list.groups.offensive, list.groups.defensive

    -- What a group is called, and how many skills a click on it changes.
    eq(offensive.title:GetText(), "All offensive skills")
    eq(offensive.status:GetText(), "Change all 4 at once")
    eq(offensive.count, 4)
    eq(defensive.title:GetText(), "All defensive skills")
    eq(defensive.status:GetText(), "Change all 3 at once")
    local title, says = Says(w, offensive)
    eq(title, "All offensive skills")
    eq(says, "Offensive skills are the ones you use on enemies. Click here to change a setting for all of them at once.",
        "which skills a group holds is said when the mouse is on its line")
    title, says = Says(w, defensive)
    eq(says, "Defensive skills are the ones you use on yourself or on friends. Click here to change a setting for all "
        .. "of them at once.")

    -- A group's picture is made of its skills' own: four of them as one square.
    eq(#list.items, 7)
    for i, id in ipairs({ DEMO, REND, SUNDER, HEROIC }) do
        eq(offensive.faces[i]:IsShown(), true)
        eq(offensive.faces[i].path, 130000 + id, "the offensive skills in the order of the list, picture " .. i)
    end
    for i, id in ipairs({ SHOUT, RAGING, BLOCK }) do
        eq(defensive.faces[i].path, 130000 + id, "the defensive skills, picture " .. i)
    end
    eq(defensive.faces[4]:IsShown(), false, "three skills make three pictures")

    -- To begin with a skill is picked, as before, and neither group.
    eq(list.group, nil)
    eq(offensive.selected, false)
    eq(defensive.selected, false)
    eq(pane:IsShown(), true)
    eq(group:IsShown(), false)
    eq(pane.name:GetText(), "Battle Shout")
    eq(pane.summary:GetText(), "Defensive: buff on you, 2 min", "the pane for a skill says which group it falls into")
    eq(list.rows[1].member, false, "no line is marked as part of a group")

    -- A click on a group's line shows the group in the pane.
    group = Group(w, view, "offensive")
    eq(group.title:GetText(), "All offensive skills")
    eq(group.summary:GetText(), "You use these 4 skills on enemies.")
    eq(defensive.selected, false)
    for i, row in ipairs(list.rows) do
        if row:IsShown() then
            local inGroup = false
            for _, name in ipairs(OFFENSIVE) do
                inGroup = inGroup or row.name:GetText() == name
            end
            eq(row.member, inGroup, "the lines of the group's skills are marked: " .. row.name:GetText())
            eq(row.bar:IsShown(), inGroup, "with a bar at their left edge")
            eq(row.selected, false, "and no skill is the one picked")
            eq(row.chosen:IsShown(), false)
            if inGroup then
                near(row.bar:GetAlpha(), 0.55, "a fainter bar than the one of a line that is picked")
            end
        end
    end
    for i, id in ipairs({ DEMO, REND, SUNDER, HEROIC }) do
        eq(group.faces[i]:IsShown(), true)
        eq(group.faces[i].path, 130000 + id, "the skills of the group by their own pictures, picture " .. i)
    end
    eq(group.faces[5]:IsShown(), false)
    eq(group.more:IsShown(), false, "nothing is left out")
    local head, lines = w:hover(group.strip)
    eq(head, "The 4 offensive skills")
    eq(#lines, 4, "the mouse on the pictures names every skill")
    for i, name in ipairs(OFFENSIVE) do
        eq(lines[i], name)
    end
    w:unhover(group.strip)
    eq(group.rest:GetText(), "How long an effect lasts, how high it stacks and which enemies are immune to it are "
        .. "different for every skill. Click a skill in the list to change those.",
        "what cannot be changed for a group is said, and where to change it")
    eq(group.reset:IsEnabled(), false, "nothing of yours to undo")
    eq(group.resetNote:GetText(), "You have not changed any of them.")
    eq(view.footer:GetText(), "7 skills are on your bars. 6 have an icon.", "the line at the bottom stays about all skills")

    -- A click on a skill goes back to that skill.
    w:click(list.rows[2])
    eq(list.group, nil)
    eq(offensive.selected, false)
    eq(group:IsShown(), false)
    eq(pane:IsShown(), true)
    eq(pane.name:GetText(), "Demoralizing Shout")
    eq(pane.summary:GetText(), "Offensive: debuff on all enemies, 45 s")
    eq(list.rows[2].selected, true)
    eq(list.rows[1].member, false)
    eq(list.rows[1].bar:IsShown(), false)

    -- The defensive skills: their effects go on you or on friends, so there is
    -- no choice between one enemy and all of them.
    group = Group(w, view, "defensive")
    eq(group.title:GetText(), "All defensive skills")
    eq(group.summary:GetText(), "You use these 3 skills on yourself or on friends.")
    eq(group.onRow:IsShown(), false, "no Affects row for the defensive skills")
    eq(group.showRow:IsShown(), true)
    eq(group.sharedRow:IsShown(), true)
    head, lines = w:hover(group.strip)
    eq(head, "The 3 defensive skills")
    for i, name in ipairs(DEFENSIVE) do
        eq(lines[i], name)
    end
    w:unhover(group.strip)
    group = Group(w, view, "offensive")
    eq(group.onRow:IsShown(), true, "the offensive skills have one")

    -- The group that is picked stays picked while the tab is away.
    w:click(view.tabs.display)
    w:click(view.tabs.spells)
    eq(list.group, "offensive")
    eq(group:IsShown(), true)
    eq(offensive.selected, true)
    eq(ns.db.spells and next(ns.db.spells), nil, "looking at a group changes nothing")
    Clean(w)
end)

panel("Skills tab: a group needs two skills to change at once", function(options)
    local w, ns = Simple(options)
    local view = w:openSettings().view
    w:click(view.tabs.spells)
    local list, pane, group = view.spells, view.pane, view.groupPane
    local offensive, defensive = list.groups.offensive, list.groups.defensive

    -- Rend and Heroic Strike are used on enemies, Battle Shout alone on friends.
    eq(offensive.status:GetText(), "Change both at once")
    eq(offensive.enabled, true)
    near(offensive:GetAlpha(), 1)
    eq(defensive.status:GetText(), "Only 1 is on your action bars")
    eq(defensive.enabled, false)
    near(defensive:GetAlpha(), 0.35, "a group of one is greyed out")
    eq(defensive.faces[1]:IsShown(), true)
    eq(defensive.faces[2]:IsShown(), false)
    w:click(defensive)
    eq(list.group, nil, "and a click on it does nothing")
    eq(group:IsShown(), false)
    eq(pane:IsShown(), true)

    group = Group(w, view, "offensive")
    eq(group.summary:GetText(), "You use these 2 skills on enemies.")
    eq(group.showNote:GetText(), "Both are on Auto, so the addon decides which of them get an icon.")

    -- A skill that is told to go on you changes sides.
    local rend = Pane(w, view, "Rend")
    w:click(rend.on.buttons.self)
    eq(ns.db.spells.Rend.kind, "buff")
    eq(rend.summary:GetText(), "Defensive: buff on you, 21 s")
    eq(defensive.status:GetText(), "Change both at once", "which makes two defensive skills")
    eq(defensive.enabled, true)
    eq(offensive.status:GetText(), "Only 1 is on your action bars")
    eq(offensive.enabled, false)
    group = Group(w, view, "defensive")
    local head, lines = w:hover(group.strip)
    eq(head, "The 2 defensive skills")
    eq(lines[1], "Battle Shout")
    eq(lines[2], "Rend")
    w:unhover(group.strip)

    -- A group that is picked and drops below two skills gives way to a skill.
    w:slash("debuff rend")
    eq(list.group, nil, "Rend went back to the enemies: the defensive group is one skill again")
    eq(group:IsShown(), false)
    eq(pane:IsShown(), true)
    eq(pane.name:GetText(), "Rend", "the skill that was picked before the group is shown again")
    group = Group(w, view, "offensive")
    w:click(group.show.buttons.always)
    w:addButton("ActionButton2", 2, nil) -- Heroic Strike is dragged off the bar
    w:advance(8)
    eq(list.group, nil, "one offensive skill is left")
    eq(group:IsShown(), false)
    eq(pane:IsShown(), true)
    eq(offensive.status:GetText(), "Only 1 is on your action bars")
    eq(view.footer:GetText(), "2 skills are on your bars. 2 have an icon and you have changed 1.")
    Clean(w)

    -- Bars with nothing to use on enemies at all.
    w = Bar(options, SHOUT, BLOCK)
    view = w:openSettings().view
    w:click(view.tabs.spells)
    offensive, defensive = view.spells.groups.offensive, view.spells.groups.defensive
    eq(offensive.status:GetText(), "None are on your action bars")
    eq(offensive.enabled, false)
    eq(offensive.faces[1]:IsShown(), false, "no skills, no pictures")
    eq(defensive.status:GetText(), "Change both at once")
    Clean(w)
end)

panel("Skills tab: one click changes whether every skill of a group has an icon", function(options)
    local w, ns = Grouped(options)
    local view = w:openSettings().view
    local group = Group(w, view, "offensive")
    local list = view.spells
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "Sunder Armor has an icon")
    eq(w:icon("ActionButton4"), nil, "Heroic Strike has none")

    local title, says = Says(w, group.showRow.label)
    eq(title, "Show an icon")
    eq(says, "Choose whether these skills get a status icon on their action buttons. With Auto the addon decides that "
        .. "for each of them.")
    eq(group.show.picked, "auto", "all four are on Auto")
    eq(group.showNote:GetText(), "All 4 are on Auto, so the addon decides which of them get an icon.")

    -- They all have the same, so a click changes them at once: a click on
    -- Auto afterwards is all it takes to go back.
    w:click(group.show.buttons.never)
    eq(view.confirm.frame:IsShown(), false, "nothing is asked")
    for _, name in ipairs(OFFENSIVE) do
        eq(ns.db.spells[name].track, false, name .. " is on Never")
    end
    for _, name in ipairs(DEFENSIVE) do
        eq(ns.db.spells[name], nil, name .. " is not of this group, and is left alone")
    end
    eq(group.show.picked, "never")
    eq(group.showNote:GetText(), "All 4 are on Never, so they have no icon.")
    eq(group.reset:IsEnabled(), true)
    eq(group.resetNote:GetText(), "You have changed 4 of these skills.")
    eq(view.footer:GetText(), "7 skills are on your bars. 3 have an icon and you have changed 4.")
    for _, row in ipairs(list.rows) do
        if row.member then
            eq(row.status:GetText(), "No icon", "the list follows: " .. row.name:GetText())
        end
    end
    w:advance(0.5)
    eq(w:icon("ActionButton1"), nil, "the icons are gone from the action buttons")
    eq(w:icon("ActionButton2"), nil)
    eq(w:icon("ActionButton3"), nil)
    eq(w:icon("ActionButton7"), "check", "Battle Shout keeps its own")

    w:click(group.show.buttons.auto)
    eq(next(ns.db.spells), nil, "back on Auto, nothing of yours is left behind")
    eq(group.show.picked, "auto")
    eq(group.reset:IsEnabled(), false)
    w:advance(0.5)
    eq(w:icon("ActionButton1"), "check")
    eq(w:icon("ActionButton4"), nil)

    w:click(group.show.buttons.always)
    for _, name in ipairs(OFFENSIVE) do
        eq(ns.db.spells[name].track, true, name .. " is on Always")
    end
    eq(group.showNote:GetText(), "All 4 are on Always, so each of them has an icon.")
    w:advance(0.5)
    eq(w:icon("ActionButton4"), "check", "Heroic Strike has an icon now")
    eq(view.footer:GetText(), "7 skills are on your bars. 7 have an icon and you have changed 4.")
    w:click(group.show.buttons.always)
    eq(view.confirm.frame:IsShown(), false, "a click on the choice they already have does nothing")

    -- What was changed for the group shows on each skill, and can be changed there.
    local heroic = Pane(w, view, "Heroic Strike")
    eq(heroic.show.picked, "always")
    eq(heroic.why:GetText(), "You chose Always, so it has an icon.")
    w:click(heroic.show.buttons.auto)
    group = Group(w, view, "offensive")
    eq(group.show.picked, nil, "one skill differs now, so no choice is marked for the group")
    eq(group.showNote:GetText(), "1 is on Auto and 3 on Always. Click a choice to set all 4.")

    -- The same from chat shows here at once.
    w:slash("ignore rend")
    eq(group.showNote:GetText(), "1 is on Auto, 2 on Always and 1 on Never. Click a choice to set all 4.")
    eq(w:drain() ~= "", true)
    Clean(w)
end)

panel("Skills tab: a change for a group asks first where its skills differ", function(options)
    local w, ns = Grouped(options)
    w:slash("track heroic strike")
    w:slash("ignore rend")
    w:drain()
    local view = w:openSettings().view
    local group = Group(w, view, "offensive")
    eq(group.show.picked, nil, "they differ, so no choice is marked")
    eq(group.same.show, nil)
    eq(group.showNote:GetText(), "2 are on Auto, 1 on Always and 1 on Never. Click a choice to set all 4.")
    eq(Waiting(group.showNote), false)

    -- A click would wipe out that Rend and Heroic Strike were set by hand, so it asks.
    w:click(group.show.buttons.never)
    eq(view.confirm.frame:IsShown(), true, "it asks first")
    eq(view.question:GetText(), "Set all 4 offensive skills to Never?")
    eq(Words(view.confirm.yes), "Change", "the button says what a yes does")
    eq(view.footer:IsShown(), false, "the question takes the place of the line at the bottom")
    eq(ns.db.spells["Sunder Armor"], nil, "and nothing has changed yet")
    eq(ns.db.spells["Heroic Strike"].track, true)
    eq(group.show.picked, nil)
    eq(group.showNote:GetText(), "These skills differ. Answer the question at the bottom to change all 4.",
        "the row says where to look")
    eq(Waiting(group.showNote), true, "in the colour of something that is waiting")

    w:click(view.confirm.no)
    eq(view.confirm.frame:IsShown(), false)
    eq(view.footer:IsShown(), true)
    eq(ns.db.spells["Sunder Armor"], nil, "Cancel leaves every skill as it was")
    eq(ns.db.spells["Heroic Strike"].track, true)
    eq(ns.db.spells.Rend.track, false)
    eq(group.showNote:GetText(), "2 are on Auto, 1 on Always and 1 on Never. Click a choice to set all 4.")
    eq(Waiting(group.showNote), false)

    w:click(group.show.buttons.never)
    w:click(view.confirm.yes)
    eq(view.confirm.frame:IsShown(), false)
    for _, name in ipairs(OFFENSIVE) do
        eq(ns.db.spells[name].track, false, name .. " is on Never")
    end
    eq(group.show.picked, "never")
    eq(group.showNote:GetText(), "All 4 are on Never, so they have no icon.")
    w:click(group.show.buttons.auto)
    eq(view.confirm.frame:IsShown(), false, "now that they are the same, the next click needs no question")
    eq(next(ns.db.spells), nil)

    -- Who the icons check: Demoralizing Shout hits every enemy, the others one.
    local title, says = Says(w, group.onRow.label)
    eq(title, "Affects")
    eq(says, "Choose whether the icons of these skills check the enemy you have targeted or every enemy in the fight.")
    eq(group.on.buttons.self, nil, "a group of skills used on enemies cannot be told to go on you")
    eq(group.on.picked, nil)
    eq(group.onNote:GetText(), "3 are on Your target and 1 on All enemies. Click a choice to set all 4.")
    w:click(group.on.buttons.all)
    eq(view.question:GetText(), "Check all 4 offensive skills on every enemy?")
    eq(group.onNote:GetText(), "These skills differ. Answer the question at the bottom to change all 4.")
    eq(group.showNote:GetText(), "All 4 are on Auto, so the addon decides which of them get an icon.",
        "the other rows say what they said")
    w:click(view.confirm.yes)
    for _, name in ipairs(OFFENSIVE) do
        eq(ns.db.spells[name].aoe, true, name .. " is checked on every enemy")
        eq(ns.db.spells[name].track, nil, name .. ": which does not decide whether it has an icon")
    end
    eq(group.on.picked, "all")
    eq(group.onNote:GetText(), "For all 4, the icon checks every enemy in the fight.")
    w:click(group.on.buttons.target)
    eq(view.confirm.frame:IsShown(), false)
    for _, name in ipairs(OFFENSIVE) do
        eq(ns.db.spells[name].aoe, false, name .. " is checked on your target")
    end
    eq(group.onNote:GetText(), "For all 4, the icon checks the enemy you have targeted.")
    local sunder = Pane(w, view, "Demoralizing Shout")
    eq(sunder.on.picked, "target", "each skill shows what the group was given")
    eq(sunder.summary:GetText(), "Offensive: debuff on your target, 45 s")

    -- A question is about the group it was asked of: it goes away with it.
    w:click(sunder.on.buttons.all)
    group = Group(w, view, "offensive")
    w:click(group.on.buttons.all)
    eq(view.confirm.frame:IsShown(), true)
    Pane(w, view, "Rend")
    eq(view.confirm.frame:IsShown(), false, "picking a skill puts the question away")
    eq(ns.db.spells.Rend.aoe, false, "and nothing was changed")
    group = Group(w, view, "offensive")
    eq(Waiting(group.onNote), false, "nor is it waiting when the group is picked again")
    w:click(group.on.buttons.all)
    w:click(view.spells.groups.defensive)
    eq(view.confirm.frame:IsShown(), false, "so does picking the other group")
    group = Group(w, view, "offensive")
    w:click(group.on.buttons.all)
    w:click(view.tabs.display)
    w:click(view.tabs.spells)
    eq(view.confirm.frame:IsShown(), false, "and leaving the tab")
    eq(Waiting(group.onNote), false)
    eq(ns.db.spells.Rend.aoe, false)

    -- A click on a row whose skills are the same answers for the question that was up.
    w:click(group.on.buttons.all)
    eq(view.confirm.frame:IsShown(), true)
    w:click(group.show.buttons.always)
    eq(view.confirm.frame:IsShown(), false, "the question about the other row is put away")
    eq(ns.db.spells.Rend.track, true, "and the click did what it says")
    eq(ns.db.spells.Rend.aoe, false, "without what the question was about")
    eq(Waiting(group.onNote), false)

    -- Defaults asks a question of its own in the same place: the row stops waiting for its answer.
    w:click(group.on.buttons.all)
    eq(Waiting(group.onNote), true)
    w:click(view.defaults)
    eq(view.question:GetText(), "Undo every change you made to your skills?")
    eq(Waiting(group.onNote), false, "the question at the bottom is no longer this row's")
    eq(group.onNote:GetText(), "3 are on Your target and 1 on All enemies. Click a choice to set all 4.")
    w:click(view.confirm.no)
    eq(ns.db.spells.Rend.aoe, false, "and Cancel there leaves everything alone")

    -- The question was about four skills. When one of them changes sides, it is put away.
    w:click(group.on.buttons.all)
    eq(view.question:GetText(), "Check all 4 offensive skills on every enemy?")
    w:slash("buff rend")
    eq(view.confirm.frame:IsShown(), false, "the group it was asked about is no longer the same")
    eq(view.footer:IsShown(), true)
    eq(group.summary:GetText(), "You use these 3 skills on enemies.")
    eq(ns.db.spells["Sunder Armor"].aoe, false, "and nothing was changed")
    eq(Waiting(group.onNote), false)
    w:drain()
    eq(w:drain(), "", "the panel says nothing of all this in chat")
    Clean(w)
end)

panel("Skills tab: whether other players' effects count, for a whole group", function(options)
    local w, ns, boar = Grouped(options)
    local view = w:openSettings().view
    local group = Group(w, view, "offensive")

    -- Sunder Armor and Demoralizing Shout are on an enemy once, whoever cast
    -- them, and nothing in Heroic Strike's tooltip says otherwise of it. Rend
    -- is a bleed: its caster's own.
    local title, says = Says(w, group.sharedRow.label)
    eq(title, "Other players")
    eq(says, "Choose whether the icons of these skills take notice when another player has put the same effect on your "
        .. "target.")
    eq(#group.sharable, 4, "another player can put any of the four on an enemy")
    eq(group.shared.picked, nil)
    eq(group.sharedNote:GetText(), "3 are on Count theirs and 1 on Ignore theirs. Click a choice to set all 4.")

    -- Another warrior's Sunder Armor is on the boar, in full.
    for _ = 1, 5 do
        w:applyAura(boar, "Sunder Armor", 30, false, nil, nil, { shared = true, stacks = 5 })
    end
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "theirs counts: five of five")

    w:click(group.shared.buttons.mine)
    eq(view.question:GetText(), "Ignore other players' effects for all 4 skills?")
    eq(Words(view.confirm.yes), "Change")
    eq(group.sharedNote:GetText(), "These skills differ. Answer the question at the bottom to change all 4.")
    eq(ns.db.spells["Sunder Armor"], nil, "nothing has changed yet")
    w:click(view.confirm.yes)
    eq(ns.db.spells["Sunder Armor"].shared, false, "the same as /se mine for each of them")
    eq(ns.db.spells["Demoralizing Shout"].shared, false)
    eq(ns.db.spells["Heroic Strike"].shared, false)
    eq(ns.db.spells.Rend, nil, "a skill that was like that anyway carries no choice of yours")
    eq(group.shared.picked, "mine")
    eq(group.sharedNote:GetText(), "For all 4, the icon only looks for your own effect.")
    eq(group.resetNote:GetText(), "You have changed 3 of these skills.")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "check", "their Sunder Armor stops counting at once")

    w:click(group.shared.buttons.anyone)
    eq(view.confirm.frame:IsShown(), false, "they were the same, so nothing is asked")
    eq(ns.db.spells["Sunder Armor"], nil, "back to what the addon made of Sunder Armor")
    eq(ns.db.spells["Demoralizing Shout"], nil)
    eq(ns.db.spells["Heroic Strike"], nil)
    eq(ns.db.spells.Rend.shared, true, "and a choice of yours for the one it would not have counted")
    eq(group.shared.picked, "anyone")
    eq(group.resetNote:GetText(), "You have changed 1 of these skills.")
    eq(group.sharedNote:GetText(), "For all 4, another player's effect is treated like your own.")
    w:advance(0.3)
    eq(w:icon("ActionButton1"), "cross", "their Sunder Armor counts again")
    w:applyAura(boar, "Rend", 21, false)
    w:advance(0.3)
    eq(w:icon("ActionButton2"), "cross", "and now their Rend does too")
    w:click(group.reset)
    w:click(view.confirm.yes)
    eq(next(ns.db.spells), nil)
    w:advance(0.3)
    eq(w:icon("ActionButton2"), "check", "undone, their Rend is theirs again")

    -- Of the defensive skills, Shield Block only ever goes on its caster: no
    -- other player's can reach you, so the row is about the two shouts.
    group = Group(w, view, "defensive")
    eq(#group.members, 3)
    eq(#group.sharable, 2, "the two shouts")
    eq(group.shared.enabled, true)
    eq(group.shared.picked, "anyone", "one shout is on you once, whichever warrior shouted")
    eq(group.sharedNote:GetText(), "For both, another player's effect is treated like your own. The other one can only "
        .. "be cast on yourself.", "the skill that is left out is accounted for")
    w:click(group.shared.buttons.mine)
    eq(view.confirm.frame:IsShown(), false)
    eq(ns.db.spells["Raging Shout"].shared, false)
    eq(ns.db.spells["Battle Shout"].shared, false)
    eq(ns.db.spells["Shield Block"], nil, "Shield Block is left out of it")
    eq(group.sharedNote:GetText(), "For both, the icon only looks for your own effect. The other one can only be cast "
        .. "on yourself.")
    eq(group.resetNote:GetText(), "You have changed 2 of these skills.")
    w:slash("anyone raging shout")
    w:drain()
    eq(group.shared.picked, nil)
    eq(group.sharedNote:GetText(), "1 is on Count theirs and 1 on Ignore theirs. Click a choice to set both. The other "
        .. "one can only be cast on yourself.")
    w:click(group.shared.buttons.anyone)
    eq(view.question:GetText(), "Count other players' effects for both skills?")
    w:click(view.confirm.yes)
    eq(ns.db.spells["Battle Shout"], nil)
    Clean(w)

    -- Skills that are all the caster's alone leave nothing to choose.
    w, ns = Bar(options, BLOCK, FRENZY, WARD)
    view = w:openSettings().view
    group = Group(w, view, "defensive")
    eq(#group.sharable, 0)
    eq(group.shared.enabled, false)
    eq(group.shared.picked, nil)
    near(group.shared.frame:GetAlpha(), 0.35, "the two buttons are greyed out")
    eq(group.sharedNote:GetText(), "No other player can put these effects on you, so there is nothing to choose here.")
    w:click(group.shared.buttons.anyone)
    eq(next(ns.db.spells), nil, "and a click on them does nothing")
    Clean(w)

    -- One skill that another player's effect can reach is named.
    w, ns = Bar(options, BLOCK, FRENZY, SHOUT)
    view = w:openSettings().view
    group = Group(w, view, "defensive")
    eq(#group.sharable, 1)
    eq(group.sharedNote:GetText(), "For Battle Shout, another player's effect is treated like your own. The other 2 can "
        .. "only be cast on yourself.")
    w:click(group.shared.buttons.mine)
    eq(ns.db.spells["Battle Shout"].shared, false)
    eq(ns.db.spells["Shield Block"], nil)
    eq(group.sharedNote:GetText(), "For Battle Shout, the icon only looks for your own effect. The other 2 can only be "
        .. "cast on yourself.")
    Clean(w)
end)

panel("Skills tab: Reset these skills asks first, and undoes your changes to one group", function(options)
    local w, ns = Grouped(options)
    w:cast(REND)
    w:advance(2)
    check(next(ns.db.learned) ~= nil, "the addon has learned something in play")
    w:slash("track heroic strike")
    w:slash("duration rend 30")
    w:slash("ignore battle shout")
    w:drain()
    local view = w:openSettings().view
    local group = Group(w, view, "offensive")
    eq(group.reset:IsEnabled(), true)
    eq(Words(group.reset), "Reset these skills")
    eq(group.resetNote:GetText(), "You have changed 2 of these skills.")
    local title, says = Says(w, group.reset)
    eq(title, "Reset these skills")
    eq(says, "Undoes every change you made to the skills of this group, so that the addon decides everything about "
        .. "them again. What the addon has learned about them in your fights is kept. You are asked to confirm first.")
    local learned = ns.db.learned.Rend

    w:click(group.reset)
    eq(view.confirm.frame:IsShown(), true, "it asks first")
    eq(view.question:GetText(), "Undo your changes to all 4 offensive skills?")
    eq(Words(view.confirm.yes), "Reset")
    eq(group.resetNote:GetText(), "Answer the question below.")
    eq(Waiting(group.resetNote), true)
    eq(ns.db.spells.Rend.duration, 30, "and has changed nothing yet")
    w:click(view.confirm.no)
    eq(view.confirm.frame:IsShown(), false)
    eq(ns.db.spells.Rend.duration, 30, "Cancel leaves everything alone")
    eq(group.resetNote:GetText(), "You have changed 2 of these skills.")
    eq(Waiting(group.resetNote), false)

    w:click(group.reset)
    w:click(view.confirm.yes)
    eq(ns.db.spells.Rend, nil, "your changes to the offensive skills are gone")
    eq(ns.db.spells["Heroic Strike"], nil)
    eq(ns.db.spells["Battle Shout"].track, false, "the defensive skills keep theirs")
    eq(ns.db.learned.Rend, learned, "and so does the addon what it learned in play")
    eq(group.reset:IsEnabled(), false)
    eq(group.resetNote:GetText(), "You have not changed any of them.")
    eq(view.footer:GetText(), "7 skills are on your bars. 5 have an icon and you have changed 1.")
    w:click(group.reset)
    eq(view.confirm.frame:IsShown(), false, "with nothing to undo the button does nothing")

    -- Defaults still goes further: every skill, of either group.
    w:click(view.defaults)
    eq(view.question:GetText(), "Undo every change you made to your skills?")
    w:click(view.confirm.yes)
    eq(next(ns.db.spells), nil)
    eq(view.spells.group, "offensive", "the group stays picked")
    Clean(w)
end)

test("settings: the pane for a group keeps its rows clear of each other, however many skills it holds", function()
    for _, wider in ipairs({ 1, 1.35, 2 }) do
        for _, count in ipairs({ 2, 12, 13, 30 }) do
            local what = count .. " skills, letters " .. wider .. " times as wide"
            local w = World({ fontWidth = wider })
            for i = 1, count do
                w:addSpell(600 + i, {
                    name = string.format("Hex %02d", i), harmful = true,
                    description = "Hexes the target for 10 sec.", effect = { duration = 10 },
                })
                local name = i <= 12 and ("ActionButton" .. i) or (i <= 24 and ("MultiBarBottomLeftButton" .. (i - 12))
                    or ("MultiBarBottomRightButton" .. (i - 24)))
                w:addButton(name, i, 600 + i)
            end
            w:load()
            local view = w:openSettings().view
            local group = Group(w, view, "offensive")
            eq(#group.members, count, what)

            -- The pictures: twelve to a line, two lines at most, and how many more.
            local places = #group.faces
            eq(places, 24)
            local shown = 0
            for i = 1, places do
                if group.faces[i]:IsShown() then
                    shown = shown + 1
                    local face = group.faces[i]
                    check(face.point[4] + face.width <= group.width + 0.01, "a picture ends inside the pane, " .. what)
                end
            end
            eq(shown, count > places and places - 1 or count, "pictures shown, " .. what)
            eq(group.more:IsShown(), count > places)
            if count > places then
                eq(group.more:GetText(), "+" .. (count - places + 1), "the last place says how many it leaves out")
            end
            local lines = count > 12 and 2 or 1
            eq(group.strip.height, lines * 24 + (lines - 1) * 4, "the pictures take " .. lines .. " lines, " .. what)

            -- Under them the rows, each with its sentence, and under those what
            -- a group cannot change; all of it above the button at the bottom.
            local names = group.showRow.label.label.fitRoom
            local under = group.strip.point[5] - group.strip.height
            for _, part in ipairs({ { "Show an icon", group.showRow, 2 }, { "Affects", group.onRow, 2 },
                { "Other players", group.sharedRow, 3 } }) do
                local name, row, noteLines = part[1], part[2], part[3]
                eq(row:IsShown(), true, name)
                check(row.point[5] <= under - 8, name .. " starts under what is above it, " .. what)
                check(row.label.label:GetStringWidth() <= names + 0.5, name .. ": what the row is called keeps to its room")
                check(row.buttons.frame.point[4] >= names + 8, name .. ": the buttons start clear of it")
                check(row.buttons.frame.point[4] + row.buttons.width <= group.width + 0.01, name .. ": and end inside the pane")
                check(row.note.point[5] <= -22, name .. ": the sentence is under the buttons")
                check(row.note.fitRoom <= group.width + 0.01, name .. ": and no wider than the pane")
                eq(row.note.fitLines, noteLines)
                under = row.point[5] + row.note.point[5] - noteLines * 13
            end
            check(group.rest.point[5] <= under - 8, "what a group cannot change comes last, " .. what)
            local button = -group.height + 4 + group.reset.height
            check(group.rest.point[5] - 4 * 13 >= button + 2, "and ends above the button at the bottom, " .. what)
            check(group.resetNote.fitRoom + 8 <= group.width - group.reset.width, "the words at the button's left end before it")
            Clean(w)
        end
    end
end)

test("settings: a change for a group reaches every one of its skills, also the ones scrolled out of sight", function()
    local w = World()
    for i = 1, 20 do
        w:addSpell(500 + i, {
            name = string.format("Curse %02d", i), harmful = true,
            description = "Curses the target for 10 sec.", effect = { duration = 10 },
        })
        local name = i <= 12 and ("ActionButton" .. i) or ("MultiBarBottomLeftButton" .. (i - 12))
        w:addButton(name, i, 500 + i)
    end
    w:addButton("MultiBarBottomLeftButton9", 21, SHOUT)
    w:addButton("MultiBarBottomLeftButton10", 22, RAGING)
    local ns = w:load()
    local view = w:openSettings().view
    local group, line = Group(w, view, "offensive")
    eq(line.status:GetText(), "Change all 20 at once")
    eq(#view.spells.rows, 10, "ten of the twenty are in sight")
    eq(group.summary:GetText(), "You use these 20 skills on enemies.")
    w:click(group.show.buttons.never)
    for i = 1, 20 do
        eq(ns.db.spells[string.format("Curse %02d", i)].track, false, "curse " .. i)
    end
    eq(ns.db.spells["Battle Shout"], nil)
    eq(group.showNote:GetText(), "All 20 are on Never, so they have no icon.")
    eq(view.footer:GetText(), "22 skills are on your bars. 2 have an icon and you have changed 20. Scroll for more.")

    -- The list still scrolls under the two groups, and the group stays picked.
    w:wheel(view.pages.spells, -1)
    eq(view.spells.group, "offensive")
    eq(group:IsShown(), true)
    eq(view.spells.rows[1].member, true)
    w:click(group.show.buttons.auto)
    eq(next(ns.db.spells), nil)
    Clean(w)
end)

panel("Skills tab: a long list scrolls, and the pane stays", function(options)
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
    local list, page, pane = view.spells, view.pages.spells, view.pane
    eq(#list.items, 20)
    local shown = #list.rows
    eq(shown, 10, "ten skills at a time, under the two lines for the groups")
    eq(list.rows[1].name:GetText(), "Curse 01")
    eq(list.rows[shown].name:GetText(), string.format("Curse %02d", shown), "as many at a time as fit the page")
    eq(list.bar:IsShown(), true, "with a scroll bar once they do not all fit")
    eq(view.footer:GetText(), "20 skills are on your bars. 20 have an icon. Scroll for more.")
    eq(list.groups.offensive.status:GetText(), "Change all 20 at once")
    eq(pane.name:GetText(), "Curse 01", "the first is picked")

    w:wheel(page, -1)
    eq(list.rows[1].name:GetText(), "Curse 04", "the wheel moves three lines")
    eq(list.bar:GetValue(), 3, "and the bar with it")
    eq(list.groups.offensive:IsShown(), true, "the two groups stay at the head of the list while the skills scroll")
    eq(list.groups.defensive:IsShown(), true)
    eq(pane.name:GetText(), "Curse 01", "the pane keeps the spell that is picked, though its line scrolled away")
    eq(list.rows[1].selected, false)
    w:wheel(page, -1)
    w:wheel(page, -1)
    w:wheel(page, -1)
    eq(list.rows[shown].name:GetText(), "Curse 20", "it stops at the end")
    eq(list.rows[1].name:GetText(), string.format("Curse %02d", 21 - shown))
    w:wheel(page, 1)
    eq(list.rows[1].name:GetText(), string.format("Curse %02d", 18 - shown))
    w:slide(list.bar, 0)
    eq(list.rows[1].name:GetText(), "Curse 01", "dragging the bar works too")
    eq(list.rows[1].selected, true)

    -- What is being typed in the pane is not lost to the wheel.
    pane.lasts:SetFocus()
    w:wheel(page, -1)
    eq(pane.lasts:HasFocus(), true, "the pane stays as it is while the list scrolls")
    eq(pane.lasts:GetText(), "10")
    w:escape(pane.lasts)

    w:click(list.rows[2])
    eq(pane.name:GetText(), "Curse 05", "a click lands on the spell the line shows now")
    w:click(pane.show.buttons.never)
    eq(w.ns.db.spells["Curse 05"].track, false)

    -- Opened again, the list comes up with the spell that is picked in sight.
    view.Select("Curse 19")
    w:click(view.tabs.display)
    w:click(view.tabs.spells)
    eq(pane.name:GetText(), "Curse 19")
    local seen = false
    for _, row in ipairs(list.rows) do
        seen = seen or (row.selected == true and row.name:GetText() == "Curse 19")
    end
    check(seen, "the spell that is picked is on screen when the tab opens")
    Clean(w)
end)

test("settings: the Skills tab keeps up with what the addon learns, without a click", function()
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
    local view = w.env.StatusEfficiencyOptions.view
    local row, pane = view.spells.rows[1], view.pane
    w:advance(0.5)
    eq(row.name:GetText(), "Ground Stomp")
    eq(row.status:GetText(), "No icon")
    eq(pane.name:GetText(), "Ground Stomp")
    eq(pane.why:GetText(), "It has no icon because it does not seem to leave a buff or a debuff behind.")
    eq(pane.on.enabled, false)

    for _ = 1, 6 do
        w:cast(STOMP)
        w:advance(8)
    end
    eq(ns.db.learned["Ground Stomp"].hits, 6)
    eq(pane.why:GetText(), "It has an icon because 6 of your 6 casts left an effect behind.",
        "what was learned shows up by itself")
    eq(pane.on.picked, "all", "judged on every enemy in the fight, as the area spell it turned out to be")
    eq(pane.show.picked, "auto")
    check(row.status:GetText():find("^Debuff on all enemies, "), "and the line in the list says so too: " .. row.status:GetText())
    eq(view.footer:GetText(), "1 skill is on your bars. 1 has an icon.")
    local title, lines = w:hover(pane.whyArea)
    eq(title, "Ground Stomp")
    eq(lines[1], "It has an icon because 6 of your 6 casts left an effect behind. Choose Never if you do not want an icon "
        .. "on it.")
    w:unhover(pane.whyArea)
    Clean(w)
end)

test("settings: the line at the bottom of the Skills tab counts in whole sentences", function()
    local w = Bar(nil, HEROIC)
    local view = w:openSettings().view
    w:click(view.tabs.spells)
    eq(view.footer:GetText(), "1 skill is on your bars. None has an icon.")
    w:click(view.pane.show.buttons.always)
    eq(view.footer:GetText(), "1 skill is on your bars. 1 has an icon and you have changed 1.")
    Clean(w)
end)

test("settings: with no spells on the bars the Skills tab says so", function()
    local w, ns = World()
    ns = w:load()
    local view = w:openSettings().view
    w:click(view.tabs.spells)
    eq(view.spells.empty:IsShown(), true)
    eq(view.spells.empty:GetText(), "The addon has not found any skills on your action bars yet.")
    eq(view.spells.rows[1]:IsShown(), false)
    eq(view.spells.groups.offensive:IsShown(), false, "no lines for groups of nothing either")
    eq(view.spells.groups.defensive:IsShown(), false)
    eq(view.pane:IsShown(), false, "and there is no pane without a spell to show")
    eq(view.groupPane:IsShown(), false)
    eq(view.footer:GetText(), "")
    w:click(view.defaults)
    w:click(view.confirm.yes)
    eq(next(ns.db.spells), nil, "Defaults has nothing to forget, and does no harm")
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
    eq(view.previews.none.face.path, QUESTION, "nothing has been read yet")
    w:advance(1)
    eq(view.previews.none.face.path, 130000 + REND, "the pretend buttons get their pictures a moment after it opens")
    eq(view.enable.ticked, false)
    eq(view.off:GetText(), "The icons are turned off.")
    w:click(view.tabs.spells)
    eq(view.spells.rows[1].name:GetText(), "Rend", "and the Skills tab has its list")
    eq(view.spells.rows[2].name:GetText(), "Heroic Strike")
    eq(view.pane.name:GetText(), "Rend")
    eq(view.spells.empty:IsShown(), false)
    eq(w:icon("ActionButton1"), nil, "still no icons on the bars")

    w:addButton("ActionButton3", 3, SHOUT)
    w:advance(6)
    eq(view.footer:GetText(), "3 skills are on your bars. 2 have an icon.",
        "a spell put on the bars while the panel is open joins the list")

    w:closeSettings()
    w:addButton("ActionButton4", 4, MORTAL)
    w:advance(8)
    eq(#ns.BarSpells(), 3, "shut again, the addon goes back to reading nothing")
    eq(w:icon("ActionButton1"), nil)
    Clean(w)
end)

test("settings: a skill's own picture is shown wherever the panel points at the skill", function()
    local w, ns = Simple()
    local view = w:openSettings().view
    eq(view.previews.none.face.path, 130000 + SHOUT, "on the pretend buttons")
    w:click(view.tabs.spells)
    eq(view.spells.rows[2].icon.path, 130000 + REND, "in the list")
    w:click(view.spells.rows[2])
    eq(view.pane.icon.path, 130000 + REND, "and at the head of the pane")
    eq(next(ns.Options.notes.pictures), nil, "none was missing, so nothing is noted")
    Clean(w)
end)

test("settings: where the client has no picture for a spell, the one on its action button is shown", function()
    local w, ns = Simple()
    w.env.C_Spell.GetSpellTexture = function()
        return nil -- as for a spell the client has not loaded
    end
    w.env.GetActionTexture = function(slot)
        return 990000 + slot
    end
    local view = w:openSettings().view
    eq(view.previews.some.face.path, 990001, "Rend is on the first button, and wears that button's picture")
    w:click(view.tabs.spells)
    eq(view.spells.rows[1].icon.path, 990003, "Battle Shout is on the third")
    eq(view.pane.icon.path, 990003)
    eq(view.spells.rows[3].icon.path, 990002, "a skill with no status icon has its picture all the same")
    eq(next(ns.Options.notes.pictures), nil, "a picture was found, so nothing is noted")
    Clean(w)
end)

test("settings: the question mark stands in only while the client has no picture at all, and that is noted", function()
    local w, ns = Simple()
    local real = w.env.C_Spell.GetSpellTexture
    w.env.C_Spell.GetSpellTexture = function()
        return nil
    end
    w.env.GetActionTexture = function()
        return 0 -- an empty answer
    end
    local view = w:openSettings().view
    eq(view.previews.some.face.path, QUESTION)
    w:click(view.tabs.spells)
    eq(view.spells.rows[2].icon.path, QUESTION)
    eq(view.pane.icon.path, QUESTION)
    eq(ns.Options.notes.pictures.Rend, "none", "which skills had none is noted")

    -- The client has it a moment later: nothing was kept from the failure.
    w.env.C_Spell.GetSpellTexture = real
    w:advance(1.5)
    eq(view.spells.rows[2].icon.path, 130000 + REND, "it shows without a click")
    eq(view.pane.icon.path, 130000 + SHOUT)
    eq(ns.Options.notes.pictures.Rend, "late", "and that it came late is noted too")
    w:click(view.tabs.display)
    eq(view.previews.some.face.path, 130000 + REND)
    w:closeSettings()
    eq(ns.db.panel.pictures.Rend, "late", "the notes are saved with the settings")
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
    check(w:drain():find("Type which result, green, yellow or red, and then the icon for it.", 1, true),
        "an unknown result is told how to say it")
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
    w:click(w.env.StatusEfficiencyOptions.view.zones.RIGHT)
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
    check(said:find("type /se help to see them", 1, true), "with where to find the commands that do the same")
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
    w:click(view.zones.RIGHT)
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
    -- Both lines are whole sentences that say what to type next, with the game's own words for the problem
    -- in brackets after the first.
    check(text:find(SAID .. "The addon hit a problem and skipped an update. Type /se debug to see the details. (", 1,
        true), "the report says what happened and where to look: " .. text)
    check(text:find("simulated bug)\n", 1, true), "and gives the problem in the game's words: " .. text)
    check(text:find(SAID .. "The addon has stopped after repeated problems. Type /se on to start it again, or /se "
        .. "debug to see the last problem.", 1, true), "it says it stopped, and how to start it again: " .. text)
    eq(w.ns.halted, true)
    -- And /se on does start it again.
    w.ns.Tracker.Update = function() end
    Answer(w, "on")
    eq(w.ns.halted, false, "/se on starts it again")
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
    local view = window.view
    w:click(Swatch(w, view, "none", "plus"))
    w:click(view.sets.dots)
    w:click(Swatch(w, view, "some", "custom"))
    w:type(view.input, "136243")
    w:hover(view.tiles.hidden)
    w:hover(view.results.all)
    w:click(view.defaults)
    w:click(view.confirm.yes)
    w:click(view.tabs.display)
    w:slide(view.size.slider.widget, 22)
    w:click(view.size.auto.frame)
    w:click(view.enable.frame)
    w:click(view.enable.frame)
    w:click(view.appear.buttons.always)
    w:click(view.usable.buttons.always)
    w:click(view.zones.BOTTOM)
    w:hover(view.previews.all.slot)
    w:click(view.defaults)
    w:click(view.confirm.yes)
    w:drag(window, "TOP", "TOP", 0, -40)
    w:click(view.tabs.spells)
    w:click(view.spells.rows[2])
    w:click(view.pane.show.buttons.always)
    w:type(view.pane.lasts, "45")
    w:type(view.pane.stacks, "3")
    w:click(view.pane.shared.buttons.mine)
    w:click(view.pane.shared.buttons.anyone)
    w:hover(view.pane.whyArea)
    w:hover(view.pane.immuneArea)
    w:click(view.pane.reset)
    w:wheel(view.pages.spells, -1)
    -- The two groups: changes at once, changes that ask first, and a reset.
    local group, confirm = view.groupPane, view.confirm
    local function Answer(button)
        if confirm.frame:IsShown() then
            w:click(button)
        end
    end
    w:click(view.spells.groups.offensive)
    eq(view.spells.group, "offensive", "Rend, Thunder Clap and what was called a debuff by hand")
    w:hover(view.spells.groups.offensive)
    w:hover(group.strip)
    w:click(group.on.buttons.target)
    Answer(confirm.no)
    w:click(group.on.buttons.all)
    Answer(confirm.yes)
    w:click(group.show.buttons.always)
    Answer(confirm.yes)
    w:click(group.shared.buttons.mine)
    Answer(confirm.yes)
    w:click(group.reset)
    Answer(confirm.yes)
    w:slash("buff commanding")
    w:click(view.spells.groups.defensive)
    eq(view.spells.group, "defensive", "Fortitude and Commanding Shout")
    w:click(group.show.buttons.never)
    Answer(confirm.yes)
    w:click(group.shared.buttons.mine)
    Answer(confirm.yes)
    w:click(view.defaults)
    w:click(view.confirm.yes)
    w:click(window.close)
    view = w:openSettings().view
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
