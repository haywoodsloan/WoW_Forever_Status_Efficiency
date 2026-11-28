"""Plays a few fights against the Status Efficiency addon in the working tree,
starting from a saved settings file as the game wrote it, with the action
bars of a warrior around level 30. Prints which
buttons have an icon at each step, what was said in chat, and what the saved
report holds afterwards. Run it before shipping a change to how casts are
judged or which skills get an icon: it once showed a false red X that no
scenario had caught.

  python3 replay_saved_fights.py <saved file> [window|fooling]

saved file  a copy of StatusEfficiency.lua from the game's SavedVariables
            folder. It is only read. Keep such a copy out of the repository:
            it is the player's own data.
window      Victory Rush's tooltip names a window for using it (default).
fooling     its tooltip reads like an effect's length, so only its saved cast
            record keeps the icon off.

The last two fights are about a change on the enemy that is an effect going,
not a cast landing (0.3.6): a buff of the enemy's own runs out a moment after a
Hamstring is dodged, a Rend is dodged in the frame the old one ends, and an
Execute kills. With change reports that say what kind they are, as build 71139
sends them, the dodged casts stay green and the kill teaches nothing about
Execute. The counts at the end say how often that happened.

The fight after those is about stacks and about another warrior in the party
(0.4.0): Sunder Armor is counted up to five, a dodged one followed by someone
else's curse a moment later adds no stack, the other warrior's Sunder Armor
and Demoralizing Shout are followed where the game says which spell they
cast, and their shouts are read off the enemy and off you out of a fight.
SE_GROUPCASTS=secret plays a client that keeps their spell secret in a fight.

The tooltips are Classic wordings written from memory. Spell ids 6343 and 1160
are defined as well because the addon's built-in list of area debuffs looks
names up by those ids. SE_REPO=/path/to/clone plays another checkout than
the one this file is in, and
SE_PAYLOAD=sealed plays a client whose change reports say nothing about what
changed (the default is "lists", what build 71139 sends). Needs
`pip install lupa`.
"""
import locale
import os
import sys
from pathlib import Path

from lupa import lua51

# The game's Lua sorts bytes by the plain "C" character table. Python takes the
# computer's own at start (a code page on Windows), and the Lua inside it would
# follow: go back to the plain one first, as tests/run_tests.py does.
locale.setlocale(locale.LC_ALL, "C")

if len(sys.argv) < 2:
    raise SystemExit(__doc__)
saved = sys.argv[1]
variant = sys.argv[2] if len(sys.argv) > 2 else "window"
lua = lua51.LuaRuntime(unpack_returned_tuples=True)
lua.globals().REPO_ROOT = os.environ.get("SE_REPO") or str(Path(__file__).resolve().parents[2]).replace("\\", "/")
lua.globals().VARIANT = variant
lua.globals().DEFAULT_AURA_PAYLOAD = os.environ.get("SE_PAYLOAD", "lists")
lua.globals().GROUP_CASTS = os.environ.get("SE_GROUPCASTS", "")
lua.globals().SAVED_TEXT = open(saved, encoding="utf-8").read().replace("\r", "")
lua.execute(r'''
local Mock = dofile(REPO_ROOT .. "/tests/wow_mock.lua")
local function Saved()
    local box = {}
    local chunk = assert(loadstring(SAVED_TEXT))
    setfenv(chunk, box)
    chunk()
    return box.StatusEfficiencyDB
end

local VICTORY_TEXT = {
    window = "Instantly attack the target causing 180 damage and healing you for 10% of your maximum health. Can only be used within 20 sec after you kill an enemy that yields experience or honor.",
    fooling = "Instantly attack the target causing 180 damage and healing you for 10% of your maximum health. Victory is yours to claim for 20 sec.",
}
local w = Mock.new({ clientVersion = "1.60.1", clientBuild = "71139", groupCasts = GROUP_CASTS ~= "" and GROUP_CASTS or nil })
local bar = {
    { 6548, "Rend", { harmful = true, range = 5, description = "Wounds the target causing them to bleed for 147 damage over 18 sec.", effect = { duration = 18 } } },
    { 6192, "Battle Shout", { harmful = false, helpful = false, description = "The warrior shouts, increasing the melee attack power of all party members within 20 yards by 185. Lasts 3 min.", effect = { buff = true, duration = 180, party = true } } },
    { 6190, "Demoralizing Shout", { harmful = false, helpful = false, description = "Reduces the melee attack power of all enemies within 10 yards by 80 for 45 sec.", effect = { area = true, duration = 45, shared = true } } },
    { 8204, "Thunder Clap", { harmful = false, helpful = false, description = "Blasts nearby enemies increasing the time between their attacks by 10% for 26 sec and doing 55 damage to them. Will affect up to 4 targets.", effect = { area = true, duration = 26 } } },
    { 6178, "Charge", { harmful = true, range = 25, description = "Charge an enemy, generate 12 rage, and stun it for 1 sec. Cannot be used in combat.", effect = { name = "Charge Stun", duration = 1 } } },
    { 1715, "Hamstring", { harmful = true, range = 5, description = "Maims the enemy, causing 18 damage and slowing the enemy's movement by 40% for 15 sec.", effect = { duration = 15 } } },
    { 7405, "Sunder Armor", { harmful = true, range = 5, description = "Sunders the target's armor, reducing it by 180 per Sunder Armor and causes a high amount of threat. Can be applied up to 5 times. Lasts 30 sec.", effect = { duration = 30, shared = true, stacks = 5 } } },
    { 402927, "Victory Rush", { harmful = true, range = 5, description = VICTORY_TEXT[VARIANT] } },
    { 2687, "Bloodrage", { selfOnly = true, description = "Generates 10 rage at the cost of health, and then generates an additional 10 rage over 10 sec. The warrior is considered in combat for the duration.", effect = { buff = true, duration = 10 } } },
    { 694, "Mocking Blow", { harmful = true, range = 5, description = "A mocking attack that causes 23 damage, a moderate amount of threat and forces the target to focus attacks on you for 6 sec.", effect = { duration = 6 } } },
    { 5246, "Intimidating Shout", { harmful = true, range = 10, description = "The warrior shouts, causing up to 5 enemies within 10 yards to cower in fear. The targeted enemy will be unable to move while cowering. Lasts 8 sec.", effect = { area = true, duration = 8 } } },
    { 1161, "Challenging Shout", { harmful = false, helpful = false, description = "Forces all nearby enemies to focus attacks on you for 6 sec.", effect = { area = true, duration = 6 } } },
    { 20230, "Retaliation", { selfOnly = true, description = "Instantly counterattack any enemy that strikes you in melee for 15 sec. Melee attacks made from behind cannot be counterattacked. A maximum of 30 attacks will cause retaliation.", effect = { buff = true, duration = 15 } } },
    { 12328, "Death Wish", { selfOnly = true, description = "When activated, increases your physical damage by 20% and makes you immune to Fear effects, but lowers your armor and all resistances by 20%. Lasts 30 sec.", effect = { buff = true, duration = 30 } } },
    { 2580, "Find Minerals", { selfOnly = true, description = "Allows the miner to find mineral veins on the minimap.", effect = { buff = true, duration = 0 } } },
    { 5308, "Execute", { harmful = true, range = 5, description = "Attempt to finish off a wounded foe, causing 325 damage and converting each extra point of rage into 9 additional damage. Only usable on enemies that have less than 20% health." } },
    { 7384, "Overpower", { harmful = true, range = 5, description = "Instantly overpower the enemy, causing weapon damage plus 15. Only useable after the target dodges. The Overpower cannot be blocked, dodged or parried." } },
    { 845, "Cleave", { harmful = true, range = 5, description = "A sweeping attack that does your weapon damage plus 18 to the target and his nearest ally." } },
    { 285, "Heroic Strike", { harmful = true, range = 5, description = "A strong attack that increases melee damage by 32 and causes a high amount of threat." } },
}
for _, entry in ipairs(bar) do
    entry[3].name = entry[2]
    w:addSpell(entry[1], entry[3])
end
-- The ids the built-in list looks names up by.
w:addSpell(6343, { name = "Thunder Clap", harmful = false, helpful = false, description = "x" })
w:addSpell(1160, { name = "Demoralizing Shout", harmful = false, helpful = false, description = "x" })
local id = {}
local frames = {}
for i, entry in ipairs(bar) do
    frames[i] = i <= 12 and ("ActionButton" .. i) or ("MultiBarBottomLeftButton" .. (i - 12))
    w:addButton(frames[i], i, entry[1])
    id[entry[2]] = entry[1]
end
local saved = Saved()
saved.appear = "always"
saved.usableOnly = false
local ns = w:load(saved)
print("variant: " .. VARIANT .. ", change reports: " .. DEFAULT_AURA_PAYLOAD .. ", group casts: "
    .. (GROUP_CASTS ~= "" and GROUP_CASTS or "readable") .. ", loaded " .. ns.VERSION)
local function show(what)
    local on, off = {}, {}
    for i, entry in ipairs(bar) do
        local icon = w:icon(frames[i])
        if icon then on[#on + 1] = entry[2] .. "=" .. icon else off[#off + 1] = entry[2] end
    end
    print("  " .. what)
    print("      icons: " .. table.concat(on, ", "))
    print("      none:  " .. table.concat(off, ", "))
    local chat = w:drain()
    if chat ~= "" then print("      chat: " .. chat) end
end
show("logged in, nothing targeted")
local boar = w:addMob("Boar")
w:showPlate(boar); w:target(boar); w:advance(0.5)
show("a boar targeted")
w:cast(id.Charge); w:advance(1.2)
w:cast(id.Rend); w:advance(1.6)
w:cast(id["Thunder Clap"]); w:advance(1.6)
w:cast(id["Heroic Strike"]); w:advance(1.6)
show("in the fight: Charge, Rend, Thunder Clap, Heroic Strike")
w:kill(boar); w:advance(0.3)
local wolf = w:addMob("Wolf")
w:showPlate(wolf); w:target(wolf); w:advance(0.5)
for i = 1, 3 do
    w:cast(id["Victory Rush"]); w:advance(1.6)
    show("Victory Rush used, time " .. i)
end
w:cast(id.Hamstring, { miss = true }); w:advance(1.6)
w:cast(id.Hamstring, { miss = true }); w:advance(1.6)
show("Hamstring dodged twice")
w:cast(id.Hamstring); w:advance(0.4)
show("Hamstring lands")
w:cast(id["Sunder Armor"]); w:advance(0.4)
w:cast(id["Mocking Blow"]); w:advance(0.4)
show("Sunder Armor and Mocking Blow land")
w:kill(wolf); w:advance(0.5); w:leaveCombat(); w:target(nil); w:advance(0.5)

-- A change on the enemy that is an effect going, not a cast landing.
local function learnedLine(name)
    local l = ns.db.learned[name] or {}
    return string.format("%s casts=%s hits=%s", name, tostring(l.casts), tostring(l.hits))
end
print("  before the last two fights: " .. learnedLine("Execute") .. ", " .. learnedLine("Hamstring") .. ", " .. learnedLine("Rend"))
local bear = w:addMob("Bear")
w:showPlate(bear); w:target(bear); w:advance(0.5)
w:cast(id.Charge); w:advance(1.2)
w:cast(id.Rend); w:advance(1.6)
w:applyAura(bear, "Enrage", 6, false, nil, true) -- a buff of the bear's own
w:advance(5.8)
w:cast(id.Hamstring, { miss = true }); w:advance(0.6)
show("Hamstring dodged 0.2s before the bear's own Enrage ran out")
w:advance(1.6)
show("1.6s later")
w:cast(id.Hamstring); w:advance(1.6)
show("Hamstring lands")
for _, aura in ipairs(bear.auras) do
    if aura.name == "Rend" then
        w:advance(aura.expirationTime - w.clock - 0.1) -- to a moment before the Rend runs out
        break
    end
end
-- The game takes the old Rend away in the frame the new one is dodged.
w:cast(id.Rend, { miss = true }); w:removeAura(bear, "Rend"); w:advance(0.4)
show("Rend dodged in the very frame the old Rend ran out")
w:advance(1.6)
w:cast(id.Rend); w:advance(1.6)
show("Rend lands")
w:cast(id.Execute); w:advance(0.1); w:kill(bear); w:advance(2)
local cat = w:addMob("Cat")
w:showPlate(cat); w:target(cat); w:advance(0.5)
w:cast(id.Rend); w:advance(1.6)
w:cast(id.Execute); w:advance(0.4); w:kill(cat); w:advance(2)
w:leaveCombat(); w:target(nil); w:advance(0.5)
print("  after them: " .. learnedLine("Execute") .. ", " .. learnedLine("Hamstring") .. ", " .. learnedLine("Rend"))

-- Stacks, and another warrior in the party (0.4.0).
if ns.Tracker.Stacks then
    local function stacks(name)
        return ns.Tracker:Stacks(ns.KeyOf("target", "debuff"), name, ns.Now())
    end
    local function pace(name)
        local l = ns.db.learned[name] or {}
        local wait, sharp = ns.Spells:Wait(ns.Spells:Get(id[name], ns.Now()))
        return string.format("%s: in its frame %s, at once %s, late %s, wait %.2fs%s", name, tostring(l.instant),
            tostring(l.prompt), tostring(l.tardy), wait, sharp and " and held to its frame" or "")
    end
    local function given(name, kind)
        local key = kind == "buff" and ns.KeyOf("player", "buff") or ns.KeyOf("target", "debuff")
        for _, effect in ipairs(ns.Tracker:Describe(ns.Now())) do
            if effect.name == name and effect.key == key then
                return string.format("%s, %.0fs left", effect.how, effect.left or -1)
            end
        end
        return "not on the books"
    end
    local warrior = w:addPartyMember("Other warrior")
    local ogre = w:addMob("Ogre")
    w:showPlate(ogre); w:target(ogre); warrior.target = ogre; w:advance(0.5)
    w:cast(id.Charge); w:advance(1.2)
    local counted = {}
    for i = 1, 3 do
        w:cast(id["Sunder Armor"]); w:advance(1.6)
        counted[i] = stacks("Sunder Armor")
    end
    show("Sunder Armor three times, counted " .. table.concat(counted, ", "))
    w:cast(id["Sunder Armor"], { miss = true }); w:advance(0.3)
    w:applyAura(ogre, "Curse of Weakness", 120, false); w:advance(1.3)
    show("Sunder Armor dodged and someone's curse lands 0.3s later, counted " .. stacks("Sunder Armor"))
    w:partyCast(warrior, id["Sunder Armor"]); w:advance(1.6)
    show("the other warrior's Sunder Armor lands, counted " .. stacks("Sunder Armor") .. " (on the ogre: "
        .. tostring(ogre.auras[1] and ogre.auras[1].stacks) .. ")")
    w:cast(id["Sunder Armor"]); w:advance(1.6)
    show("yours again, counted " .. stacks("Sunder Armor"))
    w:cast(id["Sunder Armor"]); w:advance(1.6)
    show("and again, counted " .. stacks("Sunder Armor"))
    w:partyCast(warrior, id["Demoralizing Shout"]); w:advance(1.6)
    show("the other warrior's Demoralizing Shout, nothing read of theirs yet (" .. given("Demoralizing Shout") .. ")")
    w:cast(id.Rend, { miss = true }); w:advance(0.2)
    w:applyAura(ogre, "Faerie Fire", 40, false); w:advance(1.4)
    show("Rend dodged and someone's Faerie Fire lands 0.2s later")
    w:kill(ogre); w:advance(0.5); w:leaveCombat(); w:target(nil); w:advance(0.5)
    local troll = w:addMob("Troll")
    w:applyAura(troll, "Demoralizing Shout", 45, false, nil, nil, { shared = true, source = warrior })
    for _ = 1, 4 do
        w:applyAura(troll, "Sunder Armor", 30, false, nil, nil, { shared = true, stacks = 5, source = warrior })
    end
    w:applyAura(w.player, "Battle Shout", 120, false, nil, true, { shared = true, source = warrior })
    w:showPlate(troll); w:target(troll); warrior.target = troll; w:advance(0.5)
    show("out of a fight: a troll with the other warrior's shout and four of their Sunder Armors, and their Battle Shout on you, counted "
        .. stacks("Sunder Armor"))
    w:cast(id["Sunder Armor"]); w:advance(1.6)
    show("your Sunder Armor on top, counted " .. stacks("Sunder Armor"))
    w:partyCast(warrior, id["Demoralizing Shout"], { lasts = 45 }); w:advance(1.6)
    show("their Demoralizing Shout again, now that theirs was read to last 45s (" .. given("Demoralizing Shout") .. ")")
    w:partyCast(warrior, id["Battle Shout"], { lasts = 120 }); w:advance(1.6)
    show("and their Battle Shout, read to last 2 min where yours lasts 3 (" .. given("Battle Shout", "buff") .. ")")
    w:kill(troll); w:advance(0.5); w:leaveCombat(); w:target(nil); w:advance(0.5)
    local o = ns.db.report.others or {}
    print(string.format("  casts heard from the group: %s, with details open %s, spell readable %s, secret %s, of a spell of yours %s, seen to land %s",
        tostring(o.casts), tostring(o.calm), tostring(o.named), tostring(o.unnamed), tostring(o.followed), tostring(o.landed)))
    print(string.format("  another player's copy read for how long it lasts: %s, with who put it there: %s",
        tostring(o.read), tostring(o.sourced)))
    print("  " .. pace("Sunder Armor"))
    print("  " .. pace("Rend"))
    print("  " .. pace("Demoralizing Shout"))
    print("  too late for a cast held to its frame:")
    for _, line in ipairs(ns.db.report.late or {}) do
        print("    " .. line)
    end
end
local counts = ns.db.report.reports
local kinds = counts.kinds or {}
print(string.format("  change reports with details hidden: arriving=%s going=%s both=%s not said=%s",
    tostring(kinds.came), tostring(kinds.went), tostring(kinds.both), tostring(kinds.unsaid)))
print(string.format("  put down to an effect of yours ending: %s, only an effect going: %s, of those with a cast waiting: %s",
    tostring(counts.ended), tostring(counts.gone), tostring(counts.spared)))
print("  casts as the report has them:")
for _, line in ipairs(ns.db.report.casts) do
    print("    " .. line)
end
print("  report spells:")
local names = {}
for name in pairs(ns.db.report.spells) do names[#names + 1] = name end
table.sort(names)
for _, name in ipairs(names) do
    local s = ns.db.report.spells[name]
    print(string.format("    %-18s why=%-8s lasts=%s passed=%s", name, tostring(s.why), tostring(s.lasts), tostring(s.passed)))
end
print("  learned Victory Rush: casts=" .. tostring(ns.db.learned["Victory Rush"].casts) .. " hits=" .. tostring(ns.db.learned["Victory Rush"].hits) .. " dropped=" .. tostring(ns.db.learned["Victory Rush"].dropped))
print("  errors: " .. #w.errors .. (w.errors[1] and (" " .. tostring(w.errors[1])) or "") .. ", last error: " .. tostring(ns.lastError) .. ", leaks: " .. #w.leaks)
''')
