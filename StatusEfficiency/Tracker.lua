-- Status Efficiency: which of your status effects are on which unit.
--
-- In combat the client will not tell an addon what debuffs an enemy has or what
-- buffs you have, and there is no combat log. What an addon can still see is
-- its own player's casts, and the moment a unit's effects change (though not
-- what changed). So this file keeps its own books:
--
--   * A cast on a unit whose changes the client reports counts for nothing
--     until that unit's effects are seen to change. If they do, the spell's
--     effect is taken to have landed then, and to last as long as the spell
--     says. If they do not, the cast missed, was dodged or resisted, and
--     nothing is recorded.
--   * Only a change that could be an effect arriving counts for a cast. Where
--     the client shows that a report only took effects away (the enemy died,
--     an effect ran out), no cast is credited with it. Core.lua keeps those
--     reports back, and only asks here whether an effect of yours was due.
--   * Where the client does not show what kind of change it was, one that
--     comes just as one of your own effects on the unit was due to run out is
--     put down to that, and not to a cast. That is given up for a spell whose
--     endings turn out to go unreported more often than not.
--   * A cast is assumed to land only where there is nothing to go on: a unit
--     nobody reports on, a client that has stopped reporting, and a spell
--     tracked on your say-so that reports cannot see.
--   * A spell with no icon is listened for all the same. That is how one that
--     lost its icon earns it back, and how one that never looked like a status
--     spell is found to be one.
--   * If the client still lets us count your effects on the unit (or see their
--     instance ids), a cast that adds nothing is treated as a miss, an effect
--     that drops off early is removed, and one that outlives its timer is kept.
--   * Whenever effects can be read outright, what is read replaces the guess.
--   * An effect that stacks is counted: each cast seen to land adds one, up to
--     the most the spell allows, and what is read outright replaces the count.
--     Where the client shows that a report only renewed effects, the effect
--     was on the unit before the cast, whoever put it there.
--   * An effect a unit carries only once, whoever casts it, can be someone
--     else's. It is read off the unit where that is allowed. In a fight it is
--     put in the books when the effects on a unit change in the very frame
--     someone in your group is heard casting that spell.
--   * The game says in a word what an attack or a spell did to a unit, and
--     "immune" is one of them. Said of a unit in the very moment a cast of
--     yours went to it, with nothing to show for the cast there and no other
--     word that could be the cast's answer, it is that answer: the cast left
--     nothing, and the unit is kept as immune to that spell. Nothing else
--     passes for immunity, least of all silence.
--   * "Miss", "dodge", "parry" and the like are words of the same kind: the
--     attack did not reach the unit. Said of a unit in the moment of a cast
--     of yours at it, with nothing to show for the cast there in that moment,
--     it is the cast's answer as well: the cast left nothing, whatever would
--     have been assumed of it, a change on the unit later on is something
--     else, and the miss is not held against the spell.
--   * Where the unit's effects did change in that moment, the game has said
--     two things at once: the cast landed and the word was about somebody
--     else's attack or a swing of yours, or the cast was turned away and
--     the change was something else. Which, it does not tell. Nothing is
--     made up in its place: the effect is put in the books as one that is
--     in doubt, and the icon says neither that it is there nor that it is
--     not (see "Two answers at once").
--   * The game keeps watch on your effects itself, in its own cooldown
--     tracker, and reads them where an addon may not. Where that shows your
--     effect of a spell on your target, or shows that there is none, that
--     is how it is, whatever the books made of the casts (see Tracker:Shown).
--
-- The books do not care whether a unit is an enemy carrying your debuffs or
-- you carrying your buffs: Core.lua decides which unit a spell is judged on.
--
-- A "sample" is what Compat.SampleAuras returns: { n = count, ids = set of aura
-- instance ids or nil }. Units are named by the keys Core.lua makes, which keep
-- a unit's buffs and its debuffs in separate books.

local _, ns = ...

local Tracker = {}
ns.Tracker = Tracker

local pairs, type, next = pairs, type, next
local sort, remove = table.sort, table.remove
local max, min, huge = math.max, math.min, math.huge

local GRACE = 2.0 -- seconds after a cast in which its effect is expected to appear
local EARLY = 0.3 -- a unit's effects can be seen to change this long before its cast is reported
local SENT_TTL = 15 -- forget a cast that was sent but never finished
local HOLD = 0.5 -- an effect we can still see stays alive at least this long between looks
local FOREVER = 3600 -- stand-in timer for an effect that has no duration
local CHANGE_TTL = 5 -- how long the time of a unit's last change is kept
local DUE_EARLY, DUE_LATE = 0.1, 0.3 -- how long before and after an effect was due to end a report is still its ending
local LINGER = 0.5 -- an effect that ran out is remembered this long, so the report of its ending is known for what it is
local GUEST_TTL = 1 -- how long a cast by someone in your group is kept, for the report that shows it landing
local SLACK = 0.001 -- two times this close together are the same moment
local ECHO = 0.6 -- how long after a cast that is held to its frame a change on the unit is still noted
local FRAME = 0.05 -- a report this close to a cast being announced came in the frame of the cast, or the next one
local MOMENT = FRAME + SLACK -- the same, for what the game says in a word: a time that was added up does not fall outside
local IMMUNE_HOLD = 12 -- how long a unit behind a shield is kept as immune after the game last said so
local BRACKET = 4 -- a hit this soon before the game's "immune" and one this soon after: no shield came between
local WORDS_TTL = 30 -- how long the last hit on a unit and its last "immune" are kept
local STALE = 600 -- what was learned of a unit that has not come up for this long is dropped
local SWEEP = 30 -- how often that is looked into
local CLEAN = 1 -- a landing seen this short a while ago is one the game's own tracker should be showing

Tracker.GRACE = GRACE

-- records[unit key][spell name] = {
--     applied, duration, expires   the timer
--     endless   read off the unit with no end time: `expires` is a stand-in
--     id        aura instance id, once one has been matched to this effect
--     pending   the cast still waiting to be judged, if any
--     fresh     the cast that created the record, until something confirms it
--     weak      assumed from a cast and never confirmed
--     signal    made when the unit's effects were seen to change after a cast
--     sticky    tracked on your say-so: a lack of evidence never removes it
--     exact     its end is known to the moment, if the spell's length is
--               right: put there at a known instant, or read off the unit
--     renewed   put there on top of the same effect, which the game may have
--               given extra time: when it ends is not held for or against
--               the spell
--     told      when the client's report of its ending was heard
--     moot      a change when it was due went to a cast, so whether its
--               ending was reported is left open
--     stacks    how many times over it is on the unit, for an effect that
--               stacks: counted from the casts seen to land, or read outright
--     counted   when that count was last made from a report of a landing,
--     before    what it was until then, and whether the landing was counted
--     sure      on: if the report turns out not to show what kind of landing
--               it was, the count is made again
--     theirs    another player's, as far as is known: your own effects, when
--               they are counted, do not include it
--     doubt     whether the cast that put it there, or started its timer
--               over, landed at all is not known: the game said two things
--               about that cast at once (see "Two answers at once")
--     clash     in doubt because the game's own tracker showed none of it
--               just after it was seen to land (see Tracker:Unsettle)
--     sureTill  until when it is on the unit whatever became of that cast:
--               the end of the timer the cast started over
--     had       how many times over it is on the unit if that cast left
--               nothing, for an effect that stacks
--     shown     when the game's own tracker last showed it on the unit
--     unbound   known from the game's own tracker alone: when it got there,
--               and so when it ends, is not known. It is there for as long
--               as the tracker shows it, and after that it is in doubt for
--               as long as one could last.
-- }
local records = {}
local pending = {} -- casts inside their grace period, oldest first
local guests = {} -- casts by people in your group that could leave an effect of one of your spells
-- Casts of yours that are held to the frame they were announced in, kept a
-- little longer than their wait: { cast, till }. A change that comes too late
-- for one is no longer its landing. It is noted in the saved report all the
-- same, so that it can be checked there that the game does not show landings
-- that late.
local echoes = {}
local sent = {} -- cast id -> snapshot taken when the cast was sent
local lastSent -- newest snapshot, for casts whose id cannot be matched
local lastChange = {} -- unit key -> when the client last reported its effects changing
local lastFresh = {} -- unit key -> whether that report only added effects (true) or only renewed them (false)
local credited = {} -- unit key -> the change (by its time) already put down to a cast
local holders = {} -- unit key -> the cast it was put down to
-- unit -> the changes at one moment that were held against your effects there
-- running out: { when, n = how many, [1..n] = true for one put down to an
-- ending by its timing, "gone" for one the client showed to be an effect
-- going, false for one left to the casts, [unit token] = how many of them
-- were heard under that name }
local endings = {}
local heard = {} -- kind of unit token -> true once it has reported a change while details were hidden
-- What the game has said of a unit and a spell of yours (see "Immune units").
-- immune[unit key][spell name] = { till, times, since, ... }: it said
--     "immune" as that spell was cast at the unit, which is taken to be
--     immune to it until `till`: for as long as the unit is remembered, as a
--     rule. `since` is when it last said so on a new occasion, and `times`
--     how many occasions that makes. Further:
--       open     nothing has been said of the unit since: what comes next
--                tells a lasting immunity from a shield
--       hit      when a hit last landed on the unit before the word
--       shield   other attacks were turned away there too with no hit
--                landing in between: it goes when a hit lands again
--       counted  this was told to the unit's kind of creature as an
--                occasion (see ns.NoteImmune)
--       timed    a player: kept the old way, for a while the first time
-- taken[unit key][spell name] = true: the unit has carried that spell's
--     effect, so it is not immune to it by nature. If the game calls it
--     immune afterwards, that will pass, and nothing is kept of it.
local immune = {}
local taken = {}
local touched = {} -- unit key -> when either of those was last added to or asked for
local sweepAt = 0 -- when they are next looked through for units to drop
local refusedAt = {} -- unit key -> when the game last called it immune
-- What the game last said of a unit, kept a little longer than that:
-- spoken[unit key] = {
--     hit      when a hit last landed on it (the game said "WOUND")
--     fresh    the first such hit that has not been held against the marks yet
--     no       when the game last called it immune, to anything at all
--     hitThen  `hit` as it was just before that word
--     other    when it last called it immune to something that was not, or
--              not only, a cast of yours with an icon: a swing, somebody
--              else's attack, a skill that is only listened for
-- }
local spoken = {}
local unheeded = {} -- unit key -> that moment, while no cast of yours has been found to go with it
local turned = {} -- unit key -> when the game last said an attack left nothing there for another reason
local turnedWord = {} -- unit key -> its word for that: "MISS", "DODGE", "RESIST" ...
local missedAt = {} -- unit key -> when it last said that an attack did not reach the unit at all
-- The game's words for an attack or a spell that did not reach the unit at
-- all. (A blow that was blocked or soaked up did reach it, and may have left
-- its effect there all the same: those words are not among them.)
local MISSES = { MISS = true, DODGE = true, PARRY = true, RESIST = true, EVADE = true, DEFLECT = true, REFLECT = true }
-- What is kept of a timer that a cast started over, for a cast the game then
-- says did not reach the unit.
local OLD = {
    "applied", "duration", "expires", "endless", "exact", "stacks", "counted", "before", "sure", "doubt", "sureTill",
    "had", "clash",
}
local lastCast = {} -- unit key -> your last cast that could leave a debuff there

--------------------------------------------------------------------------------
-- Records
--------------------------------------------------------------------------------

local function IsLive(rec, now)
    return rec.pending ~= nil or now < rec.expires
end

local function Live(key, name, now)
    local set = records[key]
    local rec = set and set[name]
    if rec and IsLive(rec, now) then
        return rec
    end
    return nil
end

local function Start(key, name, now, duration)
    local set = records[key]
    if not set then
        set = {}
        records[key] = set
    end
    local rec = { applied = now, duration = duration, expires = now + duration }
    set[name] = rec
    return rec
end

local function Drop(key, name)
    local set = records[key]
    if set then
        set[name] = nil
        if next(set) == nil then
            records[key] = nil
        end
    end
end

--- How many live records of your own effects a unit has, not counting one spell.
local function LiveCount(key, except, now)
    local set = records[key]
    local count = 0
    if set then
        for name, rec in pairs(set) do
            if name ~= except and not rec.theirs and IsLive(rec, now) then
                count = count + 1
            end
        end
    end
    return count
end

--------------------------------------------------------------------------------
-- Stacks
--------------------------------------------------------------------------------

--- How many times over an effect is on a unit once one more cast has landed.
--- `before` is how many it was taken to be, 0 for none. `fresh` is what the
--- report of the landing showed: true when it only added an effect, so there
--- was none before, whatever the books said. False when it only renewed
--- one, so it was there already: at least once, and from someone else if the
--- books had nothing. Nil when the report does not say.
---
--- `sure` is false for a landing that is not counted on: the effect is taken
--- to be there, and no more times over than it was. A count only ever grows
--- by a landing that is counted on, because a count that runs ahead shows the
--- red X on a skill that still has a stack to add.
local function Count(before, fresh, most, sure)
    if not sure then
        return max(before, 1)
    end
    if fresh == true then
        return 1
    end
    if before == 0 and fresh == false then
        return min(most, 2)
    end
    return min(most, before + 1)
end

--- Counts a cast that landed on a unit into the record of its effect there:
--- once for each cast, however many signs of its landing come in. `when` is
--- the moment of the report it is counted by, if it is counted by one.
---
--- A report is counted on when it came in the frame the cast was announced
--- in, or the one next to it: that is when the game shows a landing. One
--- that came later within the cast's wait passes for the landing, as it has
--- to where nothing better is known, but it is as likely something else that
--- changed on the unit after a miss, so it adds no stack. Only for a skill
--- whose landings are known to show late is it counted on like any other.
local function Stack(cast, unit, rec, before, fresh, when)
    local most = cast.most
    if not most then
        rec.stacks = nil
    elseif not unit.stacked then
        local sure = when == nil or cast.loose == true or (when - cast.time <= FRAME and cast.time - when <= FRAME)
        -- A landing that is not counted on leaves the cast open to a better sign of it.
        unit.stacked = sure or nil
        if unit.first then
            -- The better sign of a landing that was put down as the first
            -- stack already: that one was this cast's, and it is its only one.
            unit.first = nil
            return
        end
        unit.first = (not sure and before == 0) or nil
        rec.stacks = Count(before, fresh, most, sure)
        rec.counted, rec.before, rec.sure = when, before, sure
    end
end

--- What a report showed of a change is not to be read after all: another
--- report of the same moment showed something else, and which of the two was
--- the cast landing is not told. A count made from it is made again from the
--- books alone.
local function Blur(key, when)
    lastFresh[key] = nil
    local holder = credited[key] == when and holders[key]
    local set = holder and holder.most and records[key]
    local rec = set and set[holder.name]
    if rec and rec.counted == when then
        rec.stacks = Count(rec.before, nil, holder.most, rec.sure)
    end
end

--------------------------------------------------------------------------------
-- Immune units
--
-- The game says in a word what an attack or a spell just did to a unit, in a
-- fight too, and "immune" is one of its words (see ns.WatchCombat). Said of a
-- unit in the very moment a cast of yours went to it, with nothing to show
-- for the cast there, it is taken as the cast's answer: the cast left
-- nothing, and the unit is immune to that spell.
--
-- The game does not say whose attack its word is about, and in a group
-- somebody else's may be called immune in the moment of your cast. So the
-- word only stands as your cast's answer when nothing else in that moment
-- could be it instead:
--
--   * The unit's effects changed in that moment. Then the cast may have
--     landed and the word been about another attack, or the other way round.
--     The landing stands in the books, and nothing is learned from the word.
--   * The game also said "miss", "dodge", "resist" or the like of the unit
--     in that moment. Then two attacks were turned away, and which of the two
--     words was for the cast is not told: the cast is judged as if the word
--     had not been said.
--   * Two casts of yours went to the unit in that moment. Neither is held
--     to be the one that was meant.
--
-- The word can come a frame behind the cast, or behind a change on the unit.
-- So no cast at an enemy is judged before the moment of the cast is over, nor
-- before the moment of a word said of one of its units is: only then is it
-- known what else there was in that moment.
--
-- How long it is taken to stay immune: for as long as the unit is
-- remembered. An elemental that does not bleed will not start to, and an X
-- that gave way to the check again after a while sent a second cast into
-- the same immunity.
--
-- Some immunities pass, though: a shield, a banishment. Those turn
-- everything away, your ordinary hits as well, and the game says "immune"
-- of each. So what else it says of the unit tells the two apart:
--
--   * Called immune to something else as well (a swing, somebody else's
--     attack) with no hit landing in between: taken for a shield. The unit
--     is immune until a hit lands on it again, or until a while after the
--     game last said so, and nothing is held against its kind of creature.
--   * A hit landed on it just before the word and another just after, with
--     nothing else turned away in between: no shield came and went in so
--     short a time. It took the hits and not the spell, which is as good as
--     proof that its kind is immune to the spell (see ns.NoteProven).
--
-- A unit that has carried the effect is not immune by nature, so nothing is
-- kept of what the game says of it then. And a unit seen to carry the effect
-- after all stops being immune at once. A player is nobody's kind and seldom
-- immune for good: one is kept the old way, for a while the first time, and
-- for as long as they are remembered once the game has said so again after
-- that while.
--
-- Nothing else passes for immunity. A cast that showed nothing may as well
-- have missed, and several in a row may as well have missed in a row: a red
-- X that is wrong does more harm than a green check that is.
--------------------------------------------------------------------------------

--- Keeps one of the game's words for what was done to a unit in the moment of
--- a cast, for the saved report.
local function Word(unit, word)
    local words = unit.words
    if not words then
        words = {}
        unit.words = words
    end
    words[word] = true
end

--- True when the game's "immune" stands as the answer to a cast on this unit:
--- it was said of the unit in the moment of the cast, with no other word and
--- no other cast of yours in that moment that it could have been about. (A
--- change on the unit in that moment is looked at when the cast is judged.)
local function Answered(unit)
    return unit.refused ~= nil and not unit.missed and not unit.shared
end

--- True when the game's word that an attack did not reach the unit stands as
--- the answer to a cast on it: it was said of the unit in the moment of the
--- cast, with no other cast of yours in that moment that it could have been
--- about. (A change on the unit in that moment is looked at when the cast is
--- judged.)
local function Missed(unit)
    return unit.miss ~= nil and not unit.split
end

--- True while a unit a cast went to could still show the cast landing, by a
--- change reported at `when`. One the game called immune to the cast, or
--- said the cast did not reach, can only until the moment of the cast is
--- over: a change within it leaves open what the cast did, and a later one is
--- something else that happened there.
local function Open(cast, unit, when)
    if not unit.watched or unit.signal or unit.settled then
        return false
    end
    return not (when - cast.time > MOMENT and (Answered(unit) or Missed(unit)))
end

--- The game said at `when` that an attack did not reach a unit, in the moment
--- of a cast of yours at it: `unit` is the cast's entry for it. Another cast
--- of yours that the word was put down to already shares it from now on:
--- which of the two it was about is not told, and it is neither one's answer.
local function Unreached(key, unit, when)
    for i = #pending, 1, -1 do
        local other = pending[i].kind == "debuff" and pending[i].units[key]
        if other and other ~= unit and other.miss == when then
            other.split = true
            unit.split = true
        end
    end
    unit.miss = when
end

--- The game called a unit immune at `when`, in the moment of a cast of yours
--- at it that has only now been announced: `unit` is the cast's entry for
--- it. Another cast of yours that the word was put down to already shares it
--- from now on. Returns true when there is one.
local function Shared(key, unit, when)
    local shared = false
    for i = #pending, 1, -1 do
        local other = pending[i].kind == "debuff" and pending[i].units[key]
        if other and other.refused == when then
            other.shared = true
            unit.shared = true
            shared = true
        end
    end
    return shared
end

--- What the game last said of a unit, to add to.
local function Spoken(key)
    local said = spoken[key]
    if not said then
        said = {}
        spoken[key] = said
    end
    return said
end

--- Takes a unit's mark for one spell away.
local function Unmark(key, name)
    local marks = immune[key]
    if marks and marks[name] then
        marks[name] = nil
        if next(marks) == nil then
            immune[key] = nil
        end
    end
end

--- A unit was seen to carry a spell's effect, so it is not immune to it.
local function Taken(key, name, when)
    touched[key] = when
    Unmark(key, name)
    local set = taken[key]
    if not set then
        set = {}
        taken[key] = set
    end
    if not set[name] then
        set[name] = true
        ns.NoteTaken(name, key)
    end
end

--- The game called a unit immune to a cast of yours that showed nothing
--- there. Says what was made of it: "passing" for a unit that has carried
--- the effect before (nothing is kept), "once" the first time, "again" when
--- it is said once more within a while of that, and "twice" when it is said
--- after that while: a new occasion. The second answer is true when the unit
--- looks to be behind a shield (see "Immune units"), and the third when a
--- hit landed on it in the very moment of the word: it took the one and not
--- the other, which settles that it is no shield.
local function Refuse(key, name, when)
    local set = taken[key]
    if set and set[name] then
        return "passing"
    end
    touched[key] = when
    local marks = immune[key]
    if not marks then
        marks = {}
        immune[key] = marks
    end
    local mark = marks[name]
    local how = "once"
    if not mark then
        mark = { times = 1, since = when }
        marks[name] = mark
    elseif when - mark.since < IMMUNE_HOLD then
        how = "again"
    else
        how = "twice"
        mark.times = mark.times + 1
        mark.since = when
    end
    if key:find("^Player%-") then
        mark.timed = true
        if how == "twice" then
            mark.till = huge
        elseif mark.times < 2 then
            mark.till = when + IMMUNE_HOLD
        end
        return how
    end
    if how == "again" then
        if mark.shield then
            mark.till = when + IMMUNE_HOLD
        end
        return how, mark.shield == true
    end
    -- A new occasion. What the game said of the unit around it: the hit that
    -- last landed before the word, and whether something else was turned
    -- away there with no hit landing between the two.
    local said = Spoken(key)
    local before = said.no == when and said.hitThen or nil -- nil too once a later word has taken this one's place
    local latest = said.hit
    local other = said.other
    mark.counted = nil
    if other and other ~= when and when - other <= IMMUNE_HOLD then
        local first, last = min(other, when), max(other, when)
        local between = (latest and latest > first and latest < last) or (before and before > first and before < last)
        if not between then
            mark.shield, mark.open, mark.hit = true, nil, nil
            mark.till = last + IMMUNE_HOLD
            return how, true
        end
    end
    mark.shield = nil
    mark.till = huge
    mark.hit = before
    mark.counted = true
    if latest and latest - when <= MOMENT and when - latest <= MOMENT then
        mark.open = nil
        return how, false, true
    end
    mark.open = true
    return how, false
end

--- The game called a unit immune to something that was not a cast of yours
--- with an icon, or not that alone: a swing, somebody else's attack, a skill
--- that is only listened for. A unit that turned a spell of yours away
--- shortly before, with no hit landing on it since, looks to be behind a
--- shield. Not when a hit landed there in the very moment of this word:
--- whatever it turned away then, it took that hit.
---
--- A cast of yours with an icon that is turned away is no such sign for the
--- other spells the unit turned away. An elemental can be immune to two of
--- your skills, and they are often used one right after the other.
local function Elsewhere(key, when)
    local said = Spoken(key)
    local hit = said.hit
    if hit and hit - when <= MOMENT and when - hit <= MOMENT then
        return
    end
    if not said.other or when > said.other then
        said.other = when
    end
    local marks = immune[key]
    if not marks or (said.fresh and said.fresh < when) then
        return -- a hit landed first: the marks are held against that
    end
    for name, mark in pairs(marks) do
        if not mark.timed and when > mark.since then
            if mark.shield then
                mark.till = max(mark.till, when + IMMUNE_HOLD)
            elseif mark.open then
                mark.shield, mark.open, mark.hit = true, nil, nil
                mark.till = when + IMMUNE_HOLD
                ns.NoteShield(name, key, when, mark.counted == true)
                mark.counted = nil
            end
        end
    end
end

--- A hit was seen to land on a unit, and the moment of it is over, so that
--- whatever else the game said in it has been taken in. A unit behind a
--- shield has lost it. One whose word is still open took this hit and not
--- the spell: with a hit close before the word as well, it is settled that
--- no shield was there.
local function Struck(key, when)
    local marks = immune[key]
    if not marks then
        return
    end
    for name, mark in pairs(marks) do
        if mark.shield then
            marks[name] = nil
            ns.NoteShieldGone(name, key, when)
        elseif mark.open and when > mark.since then
            mark.open = nil
            if mark.hit and mark.since - mark.hit <= BRACKET and when - mark.since <= BRACKET then
                ns.NoteProven(name, key, when)
            end
        end
    end
    if next(marks) == nil then
        immune[key] = nil
    end
end

--------------------------------------------------------------------------------
-- Casts on their way
--------------------------------------------------------------------------------

--- Remembers what the units a cast could land on looked like when it was sent.
--- snapshot = { name, kind, time, primary = unit key or nil, late = true or nil,
---              hidden = true when effect details were hidden from addons,
---              units = { [unit key] = { pre = sample or nil, engaged = bool,
---                  watched = true when changes to its effects are reported to us,
---                  trusted = true when such reports are known to arrive in
---                            combat, so that nothing needs to be assumed,
---                  via = the kind of unit token the reports come through } } }
function Tracker:Sent(castID, snapshot)
    for id, old in pairs(sent) do
        if snapshot.time - old.time > SENT_TTL then
            sent[id] = nil
        end
    end
    if castID then
        sent[castID] = snapshot
    end
    lastSent = snapshot
end

--- A sent cast failed or was interrupted.
function Tracker:Unsend(castID, name)
    if castID then
        local snapshot = sent[castID]
        if snapshot then
            sent[castID] = nil
            if lastSent == snapshot then
                lastSent = nil
            end
        end
    elseif lastSent and lastSent.name == name then
        lastSent = nil
    end
end

--- Hands back the snapshot for a cast that has now gone off, or nil.
function Tracker:Claim(castID, name, now)
    local snapshot = castID and sent[castID]
    if snapshot then
        sent[castID] = nil
        if lastSent == snapshot then
            lastSent = nil
        end
        return snapshot
    end
    snapshot = lastSent
    if snapshot and snapshot.name == name and now - snapshot.time <= SENT_TTL then
        lastSent = nil
        for id, other in pairs(sent) do
            if other == snapshot then
                sent[id] = nil
            end
        end
        return snapshot
    end
    return nil
end

--- The unit a book belongs to: a unit's buffs and its debuffs are kept apart.
local function Owner(key)
    local unit = key:gsub("%+buffs$", "")
    return unit
end

--- True when a change on the unit at `when` was put down to one of your
--- effects there running out.
local function PutDown(unit, when)
    local note = endings[unit]
    if note and note.when == when then
        for i = 1, note.n do
            -- Only one put down to it by its timing can be taken back. One the
            -- client showed to be an effect going is that, whoever asks.
            if note[i] == true then
                return true
            end
        end
    end
    return false
end

--- True for a cast that is judged by what the unit reports. The others are
--- only credited with a change nobody else is waiting for: a spell taken to
--- land anyway, and one with no icon that is only being learned about.
local function Judged(cast)
    return cast.tracked and not cast.forced
end

--------------------------------------------------------------------------------
-- Two answers at once
--
-- A change on the unit in the moment of a cast says the cast landed. The
-- game's word in that same moment that an attack missed the unit, was dodged
-- or parried, or that the unit is immune, says it did not. With both, one of
-- the two was about something else: the word about somebody else's attack or
-- a swing of yours, or the change about an effect of somebody else's, of the
-- unit's own, or one of yours that another attack left. The game does not
-- tell which, and nothing an addon may read in a fight does.
--
-- Either guess is wrong often enough to matter. In a group both come every
-- few seconds: taking the change for the landing showed the red X after
-- casts that had been dodged, and taking the word for the answer would keep
-- the green check up on an enemy that carries the effect. So no guess is
-- made. The effect is put in the books as if the cast had landed, and marked
-- as in doubt (`doubt`). Tracker:Doubt says so to whoever asks, with what
-- would be on the unit if the cast left nothing, and the icon shows neither
-- of the two (see Carries in Core.lua).
--
-- A cast that came on top of the same effect leaves less in doubt: the
-- effect is on the unit either way until the timer that was running would
-- have ended (`sureTill`), and that many times over (`had`).
--
-- What ends the doubt: a later cast that is seen to land with nothing said
-- against it, the effect being read off the unit or shown by the game's own
-- tracker, and the end of its timer. The cast is counted neither for nor
-- against its spell.
--
-- For an effect that stacks, a later cast that plainly lands ends the doubt
-- about the effect being there, and not the doubt about how many times over:
-- that stays one more or one less (`had` is then the lesser count, and
-- `sureTill` the end of the new timer), until the two come to the same.
--------------------------------------------------------------------------------

--- True when the game gave two answers about a cast at a unit: its effects
--- were seen to change for the cast, and in the moment of the cast the game
--- said that an attack did not reach the unit, or that the unit is immune.
--- (A word about a spell that had not reached the unit yet is not kept as
--- one that could be about the cast: see Unreached.)
local function Clashes(unit)
    return unit.signal ~= nil and (unit.miss ~= nil or unit.refused ~= nil)
end

--- Marks what a cast left in the books on a unit as in doubt, once the game
--- has given two answers about it. Only for a cast that is judged by what
--- the unit reports: one that is taken to land on your say-so is not put in
--- doubt by a word, and one with no icon leaves nothing in the books.
local function Torn(cast, key, unit)
    if not Clashes(unit) or not Judged(cast) or unit.settled then
        return
    end
    local set = records[key]
    local rec = set and set[cast.name]
    if not rec or rec.clash or unit.torn then
        return
    end
    unit.torn = true
    rec.doubt = true
    rec.exact = nil -- when it ends, if it is there at all, is not known to the moment
    -- What the cast came on top of is there either way, for as long as it
    -- would have been.
    local old = unit.old
    local till = old and ((old.doubt and old.sureTill) or (not old.doubt and old.expires)) or nil
    if till and till > unit.signal then
        rec.sureTill = till
        rec.had = old.doubt and old.had or old.stacks
    else
        rec.sureTill, rec.had = nil, nil
    end
    ns.Log("%s: the unit's effects changed, and the game said an attack left nothing there: not known which",
        cast.name)
end

--- The effects on a watched unit changed while a cast of yours was on its way
--- there: take the cast as having landed at that moment. `fresh` is what the
--- report showed of the change (see Count).
local function Witness(cast, key, unit, when, fresh)
    credited[key] = when
    holders[key] = cast
    unit.signal = when
    cast.shown = true

    local name = cast.name
    if cast.tracked then
        local rec = Live(key, name, when)
        local new = rec == nil
        local before = rec and (rec.stacks or 1) or 0
        if new then
            rec = Start(key, name, when, cast.duration)
            rec.fresh = cast
        elseif not unit.old then
            -- What the timer was, for a cast the game turns out to have
            -- given two answers about.
            local old = {}
            for i = 1, #OLD do
                old[OLD[i]] = rec[OLD[i]]
            end
            unit.old = old
        end
        if unit.least == nil then
            -- How many times over it is on the unit if a cast that is in
            -- doubt left nothing, for an effect that stacks: this landing
            -- comes on top of that many, or of one more.
            unit.least = false
            if rec.doubt and cast.most then
                unit.least = rec.sureTill and when < rec.sureTill and (rec.had or 1) or 0
            end
        end
        rec.doubt, rec.sureTill, rec.had, rec.clash = nil, nil, nil, nil
        rec.unbound = nil
        rec.applied = when
        rec.duration = cast.duration
        rec.expires = when + cast.duration
        rec.endless = nil
        rec.weak = nil
        rec.signal = true
        rec.exact = true
        -- A renewed effect can be given extra time by the game, so whether it
        -- is reported ending on time says nothing about the spell or the client.
        rec.renewed = not new or nil
        rec.told = nil
        rec.moot = nil
        rec.theirs = nil -- yours is on it now, whoever's it was
        Stack(cast, unit, rec, before, fresh, when)
        if unit.least and rec.stacks then
            local least = min(cast.most, unit.least + 1)
            if least < rec.stacks then
                -- It is there, and one of two counts.
                rec.doubt = true
                rec.sureTill = rec.expires
                rec.had = least
            end
        end
        Torn(cast, key, unit) -- the game may have said already that an attack left nothing there
    end
    ns.Spells:Landed(name, when - cast.time)
    ns.Log("%s: the unit's effects changed %.2fs after the cast, so it landed", name, when - cast.time)
end

--- A cast went off.
--- spell = { name, info, tracked, area, duration, forced, wait, sharp, loose, atOnce, learning, most }
---   info      what Spells:Get gave for the spell
---   most      how many times over its effect can be on one unit, for one
---             that stacks
---   forced    tracked on your say-so where reports cannot be relied on to
---             show what it leaves, so it is assumed to land whatever is seen
---   wait      how long a unit is given to show the cast, when reports of its
---             changes are all there is to judge by
---   sharp     the spell shows in the frame of its cast: a change that came
---             longer than `wait` before the cast was announced is not its
---   loose     the spell is known to show late: a change that comes a while
---             after the cast is counted on as its landing all the same
---   atOnce    the spell reaches its target the moment it is cast, as far as
---             is known: the game's word that an attack did not reach the
---             unit, said in that moment, can be about the cast
---   learning  it has no icon, but is listened for all the same: that is how
---             a spell earns one, or earns back the one it lost
function Tracker:Succeeded(snapshot, spell, now)
    local name = spell.name
    local cast = {
        name = name,
        info = spell.info,
        kind = snapshot.kind or "debuff",
        tracked = spell.tracked,
        learning = (not spell.tracked and spell.learning) or nil,
        area = spell.area,
        duration = spell.duration,
        most = spell.most,
        loose = spell.loose,
        atOnce = spell.atOnce,
        forced = spell.forced,
        hidden = snapshot.hidden,
        time = now,
        -- A change on the unit this soon before the cast was reported is its doing.
        from = max(snapshot.time or now, now - EARLY),
        ends = now + GRACE,
        units = {},
    }

    for key, was in pairs(snapshot.units) do
        local unit
        if spell.area then
            unit = { pre = not snapshot.late and was.pre or nil, engaged = was.engaged, far = was.far }
        elseif key == snapshot.primary then
            unit = { pre = not snapshot.late and was.pre or nil, engaged = true }
        end
        if unit then
            if was.watched and (spell.tracked or cast.learning) then
                unit.watched = true
                unit.via = was.via
                cast.watched = true
                if not spell.forced then
                    -- A forced spell is listened for too, which is how it earns
                    -- being judged like any other, but silence is not held
                    -- against it: it is taken to land all the same.
                    unit.trusted = was.trusted or nil
                    cast.trusted = cast.trusted or was.trusted or nil
                end
            end
            cast.units[key] = unit
            if cast.kind == "debuff" then
                -- What the game said of the unit a moment before the cast
                -- was announced is about the cast as well.
                local at = refusedAt[key]
                if at and now - at <= MOMENT then
                    unit.refused = at
                    unit.early = true
                    Word(unit, "IMMUNE")
                    if unheeded[key] == at then
                        unheeded[key] = nil
                    elseif Shared(key, unit, at) then
                        ns.NoteRefusal("two", cast, at)
                    end
                end
                at = turned[key]
                if at and now - at <= MOMENT then
                    unit.missed = true
                    Word(unit, turnedWord[key])
                end
                at = missedAt[key]
                if at and now - at <= MOMENT and spell.atOnce then
                    Unreached(key, unit, at)
                end
                lastCast[key] = cast
            end
        end
    end
    if cast.trusted and spell.wait then
        -- Judged by reports alone: wait as long as this spell is known to take.
        cast.ends = now + spell.wait
        if spell.sharp then
            -- And one that shows in the frame of its cast is not looked for
            -- any longer before the cast was announced than after it (and a
            -- hair, so that a time that was added up does not fall outside).
            cast.from = max(cast.from, now - spell.wait - SLACK)
            if spell.tracked then
                echoes[#echoes + 1] = { cast = cast, till = now + ECHO }
            end
        end
    end

    if not spell.tracked and not (cast.learning and cast.trusted) then
        -- A spell we only learn from: pointless to follow if nothing can be compared.
        local comparable = false
        for _, unit in pairs(cast.units) do
            if unit.pre then
                comparable = true
                break
            end
        end
        if not comparable then
            return
        end
    end

    for key, unit in pairs(cast.units) do
        local rec = Live(key, name, now)
        unit.had = rec ~= nil
        if unit.trusted then
            -- Nothing is taken on trust: the books change when the unit does.
        elseif unit.far then
            -- Out of the spell's reach, as far as can be told: it is not
            -- taken to land there, and a timer running there is left alone.
        elseif spell.tracked then
            if rec then
                if unit.engaged then
                    -- Recast on a unit that already has it: the timer starts over.
                    -- (What it was is kept, for a cast the game then says
                    -- did not reach the unit.)
                    local old = {}
                    for i = 1, #OLD do
                        old[OLD[i]] = rec[OLD[i]]
                    end
                    unit.old = old
                    local before = rec.stacks or 1
                    rec.applied = now
                    rec.duration = spell.duration
                    rec.expires = now + spell.duration
                    rec.endless = nil
                    rec.exact = nil
                    rec.pending = cast
                    Stack(cast, unit, rec, before)
                end
            elseif not spell.area or (unit.pre == nil and unit.engaged) then
                -- Assume it lands. For an area spell we only assume when there
                -- will be no evidence to wait for.
                rec = Start(key, name, now, spell.duration)
                rec.pending = cast
                rec.fresh = cast
                rec.sticky = spell.forced or nil
                Stack(cast, unit, rec, 0)
            end
        end
    end

    pending[#pending + 1] = cast
    ns.Log("%s: cast, waiting to see what it leaves behind", name)

    -- The change can be reported a moment before the cast is.
    for key, unit in pairs(cast.units) do
        if unit.watched then
            local when = lastChange[key]
            if when and when >= cast.from and credited[key] ~= when then
                Witness(cast, key, unit, when, lastFresh[key])
            elseif when and when >= cast.from and Judged(cast) and holders[key] and not Judged(holders[key]) then
                -- It went to a cast that is only credited when nobody else is
                -- waiting, because this one had not been announced yet.
                local other = holders[key].units[key]
                if other and other.signal == when then
                    other.signal = nil
                end
                Witness(cast, key, unit, when, lastFresh[key])
            elseif Judged(cast) and PutDown(Owner(key), now) then
                -- A change on the unit this very frame was put down to an
                -- effect of yours running out, before this cast was announced.
                Witness(cast, key, unit, now)
            end
        end
    end
end

--- A cast of yours was credited with a change in the very frame someone in
--- your group was heard casting the same spell at the same unit. Which of the
--- two effects is on it now is not told. It stays yours in the books, with
--- the shorter time of the two, and its ending is not waited for.
local function Contested(cast, key, when)
    for i = #guests, 1, -1 do
        local guest = guests[i]
        if guest.time == when and guest.name == cast.name and guest.units[key] then
            local rec = Live(key, cast.name, when)
            if rec and guest.duration < rec.duration then
                rec.duration = guest.duration
                rec.expires = when + guest.duration
                rec.exact = nil
            end
            return
        end
    end
end

--- The effects on a unit changed in the very frame someone in your group was
--- heard casting a spell of yours whose effect a unit carries only once,
--- whoever casts it: their cast is taken to have landed there.
local function Welcome(guest, key, when, fresh)
    credited[key] = when
    holders[key] = guest

    local name = guest.name
    local rec = Live(key, name, when)
    local before = rec and (rec.stacks or 1) or 0
    if not rec then
        rec = Start(key, name, when, guest.duration)
    end
    -- A unit carries the effect only once, so theirs is the one on it now,
    -- also where yours was: it is no longer one of the effects of yours that
    -- are counted.
    rec.theirs = true
    rec.id = nil
    rec.applied = when
    rec.duration = guest.duration
    rec.expires = when + guest.duration
    rec.endless = nil
    rec.weak = nil
    rec.doubt, rec.sureTill, rec.had, rec.unbound, rec.clash = nil, nil, nil, nil, nil
    rec.signal = true
    -- How long their copy lasts is not known the way yours is, so its ending
    -- is neither waited for nor held for or against the spell.
    rec.exact = nil
    rec.told = nil
    rec.moot = nil
    if guest.most then
        rec.stacks = Count(before, fresh, guest.most, true) -- in the very frame of their cast
        rec.counted, rec.before, rec.sure = when, before, true
    else
        rec.stacks = nil
    end
    Taken(key, name, when)
    ns.NoteOthers("landed")
    ns.Log("%s: someone in your group cast it as the unit's effects changed, so theirs landed", name)
end

--- The client reported that the effects on a unit changed. It does not say
--- which effect or whose. `fresh` is what it does show, where it shows it:
--- true when the report only added effects, false when it only renewed some.
---
--- A cast of yours that was announced in this very frame gets the credit
--- first: where the game reports a landing, it does so in the frame of the
--- cast. Then a cast by someone in your group that was announced in this
--- frame and could leave an effect you track. Then the newest cast of yours
--- still waiting on the unit. A spell that is taken to land anyway, or that
--- has no icon and is only being learned about, gets it when nobody else is
--- waiting: it may well leave nothing, and must not take the proof away from
--- a cast that is judged by it. A cast whose wait is over gets nothing, even
--- if it has not been looked at since.
function Tracker:Changed(key, when, fresh)
    if lastChange[key] == when then
        -- One change is reported once for each name the unit goes by, and
        -- alike each time. A report of that moment that shows another kind of
        -- change is of a second change.
        if lastFresh[key] ~= fresh then
            Blur(key, when)
        end
        return
    end
    lastChange[key] = when
    lastFresh[key] = fresh
    local newest, spare
    for i = #pending, 1, -1 do
        local cast = pending[i]
        local unit = cast.units[key]
        if unit and Open(cast, unit, when) and when >= cast.from and when <= cast.ends then
            if not Judged(cast) then
                spare = spare or cast
            elseif cast.time == when then
                Witness(cast, key, unit, when, fresh)
                Contested(cast, key, when)
                return
            else
                newest = newest or cast
            end
        end
    end
    for i = #guests, 1, -1 do
        local guest = guests[i]
        if guest.time == when and guest.units[key] then
            Welcome(guest, key, when, fresh)
            return
        end
    end
    local cast = newest or spare
    if cast then
        Witness(cast, key, cast.units[key], when, fresh)
    end
    -- Too late for a cast that is held to its frame, and showed nothing there?
    for i = #echoes, 1, -1 do
        local echo = echoes[i]
        local late = echo.cast
        local unit = late.units[key]
        if unit and when > late.ends and when <= echo.till then
            remove(echoes, i)
            if not late.shown and not late.hit and not unit.settled and not unit.refused then
                ns.NoteLate(late, when - late.time, fresh)
            end
        end
    end
end

--- Someone in your group cast a spell of yours whose effect a unit carries
--- only once, whoever casts it. Nothing is taken on trust for a cast that is
--- not yours: it only counts where a unit that is known to report its changes
--- does so in this very frame. Returns whether there is such a unit to wait
--- for.
--- snapshot = { kind, units = { [unit key] = { watched, trusted } } }, as for
--- Tracker:Sent; spell = { name, duration, most }.
function Tracker:Joined(snapshot, spell, now)
    local guest = {
        name = spell.name,
        kind = snapshot.kind or "debuff",
        tracked = true, -- a change it was credited with is not up for the taking
        duration = spell.duration,
        most = spell.most,
        time = now,
        units = {},
    }
    local waiting = false
    for key, was in pairs(snapshot.units) do
        if was.watched and was.trusted then
            guest.units[key] = true
            waiting = true
        end
    end
    if not waiting then
        return false
    end
    guests[#guests + 1] = guest
    return true
end

--- True while a cast by someone in your group is waiting for the report that
--- would show it landing.
function Tracker:HasGuests()
    return #guests > 0
end

--- True while a change on a unit is still worth hearing of although no cast
--- is waiting for it: see `echoes`.
function Tracker:HasEchoes()
    return #echoes > 0
end

--- The game said what an attack or a spell just did to a unit, and that it
--- left nothing there: `word` is its word for why, "IMMUNE", "MISS", "DODGE"
--- and so on. It does not say whose attack it was. Said in the moment a cast
--- of yours went to that unit, it is put down to the cast, for the cast to
--- be judged by (see Finish). It is kept for that moment as well, for a cast
--- that is only just about to be announced.
---
--- What became of an "IMMUNE" is passed on for the saved report (see
--- ns.NoteRefusal): here when it cannot be any one cast's answer, and
--- otherwise when the cast is judged.
function Tracker:Said(key, when, word)
    local refusal = word == "IMMUNE"
    if refusal then
        if refusedAt[key] == when then
            return -- one word, heard once for every name the unit goes by
        end
        refusedAt[key] = when
        local said = Spoken(key)
        said.no, said.hitThen = when, said.hit
    else
        turned[key] = when
        turnedWord[key] = word
        if MISSES[word] then
            missedAt[key] = when
        end
    end
    local found, two
    for i = #pending, 1, -1 do
        local cast = pending[i]
        local unit = cast.kind == "debuff" and cast.units[key]
        if unit and when - cast.time <= MOMENT and cast.time - when <= MOMENT then
            Word(unit, word)
            if not refusal then
                unit.missed = true
                -- A spell that has to fly to the unit, or is known to show
                -- late, has not reached it yet: the word is about something
                -- else.
                if MISSES[word] and cast.atOnce then
                    Unreached(key, unit, when)
                end
            else
                unit.refused = when
                if found then
                    -- Two casts of yours in one moment at one unit: which of
                    -- them it is about is not told, and it is held against
                    -- neither.
                    unit.shared = true
                    found.units[key].shared = true
                    two = true
                else
                    found = cast
                end
            end
            Torn(cast, key, unit) -- its effects may have been seen to change for the cast already
        end
    end
    if two then
        ns.NoteRefusal("two", found, when)
    elseif refusal and not found then
        unheeded[key] = when
    end
end

--- The game said that a hit landed on a unit: its word for that is "WOUND".
--- Whose hit is not told, and need not be. A unit that takes hits is behind
--- no shield, which is what tells a lasting immunity from one that passes
--- (see "Immune units"). It is held against the unit's marks once the moment
--- of it is over, when everything else said in that moment has been taken in.
function Tracker:Hit(key, when)
    local said = Spoken(key)
    said.hit = when
    if not said.fresh then
        said.fresh = when
    end
end

--- True when a cast that is judged by reports was announced in this very
--- frame and is still waiting on this unit. A change reported in the frame of
--- a cast is that cast landing far more often than it is anything else.
local function Announced(unit, when)
    for i = #pending, 1, -1 do
        local cast = pending[i]
        if cast.time == when and Judged(cast) then
            for book = 1, 2 do
                local waiting = cast.units[book == 1 and unit or (unit .. "+buffs")]
                if waiting and waiting.watched and not waiting.signal and not waiting.settled then
                    return true
                end
            end
        end
    end
    return false
end

--- True while a cast that is judged by reports is waiting on this unit, and
--- would take a change reported there at `when` for its own effect arriving.
function Tracker:Judging(unit, when)
    local buffs = unit .. "+buffs"
    for i = 1, #pending do
        local cast = pending[i]
        if Judged(cast) then
            for book = 1, 2 do
                local waiting = cast.units[book == 1 and unit or buffs]
                if waiting and Open(cast, waiting, when) then
                    return true
                end
            end
        end
    end
    return false
end

--- True while a cast is waiting to see whether this unit's effects change:
--- one that has gone off, or one that was sent and not heard of since.
local function Awaited(unit, when)
    local buffs = unit .. "+buffs"
    for i = 1, #pending do
        local cast = pending[i]
        for book = 1, 2 do
            local waiting = cast.units[book == 1 and unit or buffs]
            if waiting and Open(cast, waiting, when) then
                return true
            end
        end
    end
    for _, snapshot in pairs(sent) do
        if when - snapshot.time <= SENT_TTL and (snapshot.units[unit] or snapshot.units[buffs]) then
            return true
        end
    end
    local last = lastSent
    return last ~= nil and when - last.time <= SENT_TTL and (last.units[unit] or last.units[buffs]) ~= nil
end

--- True when this record's effect is expected to be reported ending at `when`.
local function ComesDue(rec, when)
    return rec.exact and not rec.told and not rec.pending
        and when >= rec.expires - DUE_EARLY and when <= rec.expires + DUE_LATE
end

--- An effect of yours on the unit that was due to run out at `when`: its
--- record, its name, and whether endings of that spell are known to be
--- reported on time. One for which they are is picked first.
local function Due(unit, when)
    local found, foundName
    for book = 1, 2 do
        local set = records[book == 1 and unit or (unit .. "+buffs")]
        if set then
            for name, rec in pairs(set) do
                if ComesDue(rec, when) then
                    if ns.Spells:EndsOnTime(name) then
                        return rec, name, true
                    end
                    if not found then
                        found, foundName = rec, name
                    end
                end
            end
        end
    end
    return found, foundName, false
end

--- True when a change reported at `when` could be one of your effects running
--- out, on whatever unit: only then is it worth working out whose change it is.
function Tracker:Expecting(when)
    for _, note in pairs(endings) do
        if note.when == when then
            return true
        end
    end
    for _, set in pairs(records) do
        for _, rec in pairs(set) do
            if ComesDue(rec, when) then
                return true
            end
        end
    end
    return false
end

--- Is the change the client reported on a unit at `when` one of your own
--- effects there running out? An effect whose end is known to the moment is
--- expected to be reported just then, and that report says nothing about a
--- cast. Each ending answers for one change. `unit` is the unit's own key: its
--- debuffs and its buffs are both looked through. `token` is the name the
--- report came under: one change is reported under every name a unit goes by.
---
--- This is relied on from the start, and given up for a spell whose endings
--- turn out to go unreported more often than not: a report that fits is then
--- only counted, and passed on like any other. And a change in the very frame
--- a cast on the unit is announced goes to the cast, whatever else was due.
--- That one exception is what keeps a cast that landed from being lost here:
--- where the game reports a landing, it does so in the frame of the cast.
---
--- `gone` is true when the client showed that the report took effects away.
--- Then there is nothing to weigh: every effect of yours that was due went
--- with it, whatever else is waiting, and no cast can take the report back.
function Tracker:Explained(unit, when, token, gone)
    local note = endings[unit]
    if note and note.when ~= when then
        note = nil
    end
    local nth = (note and note[token] or 0) + 1 -- which of this moment's changes, under this name
    if note then
        note[token] = nth
        if nth <= note.n then
            -- One already looked into, heard under another of the unit's names.
            return note[nth] ~= false
        end
    end
    local rec, name, relied = Due(unit, when)
    if not rec then
        return false
    end
    if not note then
        note = { when = when, n = 0, [token] = 1 }
        endings[unit] = note
    end
    note.n = note.n + 1
    if gone then
        -- One report can take several effects away, so it answers for every
        -- effect of yours on the unit that was due.
        note[note.n] = "gone"
        for book = 1, 2 do
            local set = records[book == 1 and unit or (unit .. "+buffs")]
            if set then
                for other, due in pairs(set) do
                    if ComesDue(due, when) then
                        due.told = when
                        if not due.renewed then
                            ns.Spells:Ended(other, true)
                        end
                        ns.Log("%s: ran out on time, and the unit reported an effect going", other)
                    end
                end
            end
        end
        return true
    end
    if Announced(unit, when) then
        -- The game may have sent one report for the landing and the ending
        -- both, so whether this ending was reported is left open.
        rec.moot = true
        note[note.n] = false
        return false
    end
    rec.told = when
    note[note.n] = relied
    if not rec.renewed and not Awaited(unit, when) then
        -- Nothing else it could have been: this spell's endings are reported, and on time.
        ns.Spells:Ended(name, true)
    end
    if relied then
        ns.Log("%s: ran out on time, which is the change the unit reported", name)
    end
    return relied
end

--- The client has been seen to report a change through one kind of unit token
--- ("player", "target", "softenemy" or "plate") while effect details were
--- hidden. From then on a unit watched through that kind of token that reports
--- nothing after a cast is known to have gained nothing.
function Tracker:Heard(kind)
    heard[kind] = true
end

--- True while a cast is waiting to be judged: one of this kind ("debuff" or
--- "buff"), or any at all when no kind is given.
function Tracker:HasPending(kind)
    for i = 1, #pending do
        if kind == nil or pending[i].kind == kind then
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Judging a cast by what changed on the unit
--------------------------------------------------------------------------------

--- Did one of your effects appear on the unit since `pre`? Returns the new
--- aura instance id when ids are readable, true when only the count went up,
--- and false when nothing new is there.
local function Gained(pre, sample, key)
    if pre.ids and sample.ids then
        local set = records[key]
        local newest
        for id in pairs(sample.ids) do
            if not pre.ids[id] and (not newest or id < newest) then
                local owned = false
                if set then
                    for _, rec in pairs(set) do
                        if rec.id == id then
                            owned = true
                            break
                        end
                    end
                end
                if not owned then
                    newest = id
                end
            end
        end
        return newest or false
    end
    return sample.n > pre.n
end

local function Confirm(cast, key, unit, gained, sample, now)
    unit.settled = true
    cast.hit = true

    local name = cast.name
    local landed = unit.signal or cast.time
    local rec = Live(key, name, now)
    local before = rec and (rec.stacks or 1) or 0
    if not rec then
        rec = Start(key, name, landed, cast.duration)
        rec.sticky = cast.forced or nil
    end
    rec.applied = landed
    rec.duration = cast.duration
    rec.expires = landed + cast.duration
    rec.endless = nil
    rec.exact = nil
    rec.weak = nil
    rec.fresh = nil
    rec.theirs = nil
    rec.doubt, rec.sureTill, rec.had, rec.unbound, rec.clash = nil, nil, nil, nil, nil -- counted: it is there
    Stack(cast, unit, rec, before)
    if type(gained) == "number" then
        if not rec.id or not sample.ids[rec.id] then
            rec.id = gained
        end
    else
        rec.id = nil -- cannot be checked any more, so do not let a stale id speak
    end
    if rec.pending == cast then
        rec.pending = nil
    end

    if gained == true then
        -- Only a count: make sure a second cast in flight does not take credit
        -- for the same new effect.
        for i = 1, #pending do
            local other = pending[i]
            local otherUnit = other ~= cast and other.units[key]
            if otherUnit and not otherUnit.settled and otherUnit.pre and otherUnit.pre.n <= unit.pre.n then
                otherUnit.pre.n = otherUnit.pre.n + 1
            end
        end
    end
    ns.Log("%s: confirmed, a new effect of yours appeared", name)
end

local function Finish(cast, now, engaged)
    local name = cast.name
    local clean, unclear = false, false -- what counting the unit's effects showed
    local signalled, quiet = false, false -- what the unit's change reports showed
    local blind = false -- a unit the cast may have changed without anyone being told
    local tally = {} -- how each unit came out, for the report: verdict -> units
    local delay -- how long after the cast a unit's effects were seen to change
    local unheard -- kinds of token that reported nothing, and never have
    local said -- the game's words for what was done to the units in the moment of the cast

    for key, unit in pairs(cast.units) do
        local set = records[key]
        local rec = set and set[name]
        local restarted = rec ~= nil and rec.pending == cast and unit.old -- its timer, as it was before the cast
        if rec and rec.pending == cast then
            rec.pending = nil
        end
        local mine = rec ~= nil and rec.fresh == cast
        if mine then
            rec.fresh = nil
        end
        if unit.signal then
            delay = delay or (unit.signal - cast.time)
        end

        if unit.words then
            said = said or {}
            for word in pairs(unit.words) do
                said[word] = true
            end
        end

        -- The game called the unit immune in the moment of the cast, and
        -- nothing else it said then could be the cast's answer instead.
        local answered = Answered(unit)
        local refused = false -- and nothing showed of the cast there either
        local missed = false -- the game said the cast did not reach the unit, and nothing showed of it there
        local verdict = "unknown"
        if unit.settled then
            verdict = "seen" -- confirmed by its instance id, or read directly
        elseif answered and not unit.signal then
            refused = true
        elseif unit.far and not unit.signal then
            -- Out of the spell's reach when it was cast, as far as could be
            -- told: nothing was to be expected there. That nothing showed
            -- says nothing of the spell, nor of whether the game reports
            -- what changes on that unit.
            verdict = "out of reach"
        elseif Missed(unit) and not unit.signal then
            missed = true
        elseif unit.observed then
            -- Its effects were countable before and after, and nothing new appeared.
            if unit.had or (not unit.direct and unit.observed.n > LiveCount(key, name, now)) then
                -- A refresh, or effects we cannot account for: cannot call it a miss.
                -- (When they were also read by name it can be: an effect of this
                -- spell's would have been recognised among them.)
                unclear = true
                if mine and not unit.signal then
                    rec.weak = true
                end
                verdict = unit.signal and "changed" or "unclear"
            elseif answered then
                -- Whatever changed on the unit, it was not a new effect of
                -- yours, and the game said why not.
                refused = true
            else
                -- Whatever changed on the unit, it was not a new effect of yours.
                clean = true
                if mine then
                    if rec.sticky then
                        rec.weak = true
                    else
                        Drop(key, name)
                        ns.Log("%s: nothing new appeared, treating the cast as a miss", name)
                    end
                end
                verdict = "nothing new"
            end
        elseif unit.signal then
            verdict = "changed" -- the books were brought up to date when it was seen
            if Clashes(unit) then
                -- The game said in the moment of the cast that an attack
                -- left nothing on the unit, too. One of the two was not this
                -- cast, and which is not told: nothing is learned about the
                -- spell, and what the cast left in the books is in doubt
                -- (see "Two answers at once").
                blind = true
                if Judged(cast) then
                    Torn(cast, key, unit)
                    verdict = "unsure"
                end
            elseif unit.lost then
                -- It died or went out of sight while the cast waited. A dying
                -- enemy's effects all go, and where the client does not tell
                -- an effect going from one arriving, that is a change too:
                -- nothing is learned about the spell from it.
                blind = true
            else
                signalled = true
            end
        else
            -- Nothing was seen of this cast on the unit. What that says depends
            -- on whether a change there would have been reported.
            local told = unit.watched == true and not unit.lost -- in sight from the cast to now
            local silent = told and heard[unit.via] == true
            if told and not cast.forced and (silent or unit.trusted) then
                if silent then
                    verdict = "silent"
                    quiet = true
                    if mine then
                        -- Assumed when it was cast, before any report had come in.
                        if rec.sticky then
                            rec.weak = true
                        else
                            Drop(key, name)
                        end
                    end
                    ns.Log("%s: nothing on the unit changed, so the cast left nothing there", name)
                else
                    -- Relied on since an earlier session, and it has not been
                    -- heard from in this one: nothing is assumed either way.
                    verdict = "unproven"
                    blind = true
                    if cast.tracked then
                        -- A spell with no icon may well leave nothing, so its
                        -- silence says nothing about the client.
                        unheard = unheard or {}
                        unheard[unit.via] = true
                    end
                    if mine then
                        rec.weak = true
                    end
                end
            else
                -- Nothing can be held against the cast: nobody reports on the
                -- unit, or reports are not proven yet, or you asked for the
                -- spell to be tracked. It is taken to have landed.
                if silent then
                    quiet = true -- told against the spell, though not against this cast
                    verdict = "assumed"
                else
                    blind = true
                    if told then
                        verdict = "unproven"
                    end
                end
                if mine then
                    rec.weak = true
                    verdict = verdict == "unknown" and "assumed" or verdict
                elseif cast.tracked and cast.area and not (rec and IsLive(rec, now)) then
                    -- An area spell with nothing to go on for this unit: if it
                    -- is in the fight, take it as hit.
                    if unit.engaged or (engaged and engaged[key]) then
                        rec = Start(key, name, cast.time, cast.duration)
                        rec.weak = true
                        rec.sticky = cast.forced or nil
                        Stack(cast, unit, rec, 0)
                        verdict = verdict == "unknown" and "assumed" or verdict
                    end
                end
            end
        end
        if refused then
            -- The cast left nothing there. That says nothing about the
            -- spell, only about the unit: it is left out of what the cast
            -- tells of the spell.
            verdict = "immune"
            if mine then
                Drop(key, name) -- taken to land when it was cast, or when the unit changed
            end
            if cast.tracked then
                ns.NoteImmune(name, key, unit.refused, Refuse(key, name, unit.refused))
            end
        end
        if missed then
            -- The cast left nothing there, and the game said why. That is
            -- this cast's story and not the spell's: it is left out of what
            -- the cast tells of the spell, and the unit's silence is held
            -- against nobody.
            verdict = "missed"
            if mine then
                Drop(key, name) -- taken to land when it was cast
            elseif restarted then
                -- The effect that was there runs on as it did before.
                for i = 1, #OLD do
                    rec[OLD[i]] = restarted[OLD[i]]
                end
            end
            ns.Log("%s: the game said the cast did not reach the unit, so it left nothing there", name)
        end
        tally[verdict] = (tally[verdict] or 0) + 1
        if unit.refused and not unit.shared then
            -- What became of the game's word, for the saved report.
            local how = (refused and "counted") or ((unit.settled or unit.signal) and "shown") or "mixed"
            ns.NoteRefusal(how, cast, unit.refused, unit.early)
            if not (refused and cast.tracked) then
                -- Not the answer to a skill with an icon: one more thing
                -- that was turned away there.
                Elsewhere(key, unit.refused)
            end
        end
        -- A cast that showed on a unit taken to be out of its reach: the
        -- spell reaches further than was thought.
        if unit.far and cast.tracked and (verdict == "seen" or (verdict == "changed" and not unit.lost
            and not unit.refused)) then
            ns.NoteReached(name, unit.far)
        end
        -- A unit that was seen to carry the effect is not immune to it. Not
        -- one that was lost sight of, whose change may have been anything,
        -- and not where the game said "immune" in the same breath.
        if cast.tracked and cast.kind == "debuff"
            and (verdict == "seen" or (verdict == "changed" and not unit.lost and not unit.refused)) then
            Taken(key, name, now)
        end
    end

    -- What is learned about the spell. Counting is proof either way. Reports
    -- of a change are good evidence for a debuff: an enemy's effects seldom
    -- change at the very moment of a cast for another reason. For a buff they
    -- are no evidence at all, because your own effects come and go all through
    -- a fight, and counting them one way only would slowly talk a spell down.
    --
    -- Silence only tells against a spell when every unit it could have reached
    -- would have reported a change. An area spell that left its effect on
    -- enemies nobody reports on has not left nothing. And a change only tells
    -- for a spell on a unit that was still there afterwards: this is what
    -- keeps a finishing move from earning an icon one kill at a time.
    local reports = cast.kind == "debuff"
    if cast.hit or (reports and signalled) then
        ns.Spells:Evidence(name, true, cast.kind)
        if not cast.tracked and cast.info and ns.Spells:Tracking(cast.info) then
            -- This very cast earned the spell its icon. What it left is put
            -- in the books, so that the icon does not start out green.
            for key, unit in pairs(cast.units) do
                if unit.signal and not Live(key, name, now) then
                    local rec = Start(key, name, unit.signal, cast.duration)
                    rec.signal = true
                    rec.exact = true
                    rec.stacks = cast.most and 1 or nil
                end
            end
        end
    elseif not unclear and not signalled and (clean or (reports and quiet and not blind)) then
        ns.Spells:Evidence(name, false, cast.kind)
    end
    ns.Note(cast, tally, delay, unheard, said)
end

--- A unit went out of sight while a cast on it was still waiting, or is only
--- still in sight through a kind of token that has never been heard from. A
--- change on it could now go unreported, so the cast is taken to have landed,
--- as it is on a unit nobody reports on.
local function Lose(cast, key, unit)
    if not unit.trusted or unit.signal or unit.settled or Answered(unit) or Missed(unit) or not cast.tracked then
        return -- (the game's "immune" or "miss" leaves no doubt to give the benefit of)
    end
    if cast.area and (not unit.engaged or unit.far) then
        return -- (nor on an enemy that was out of the spell's reach)
    end
    local name = cast.name
    local rec = Live(key, name, cast.time)
    -- The benefit of the doubt: there, and no more times over than it was.
    if not rec then
        rec = Start(key, name, cast.time, cast.duration)
        rec.fresh = cast
        rec.weak = true
        rec.stacks = cast.most and 1 or nil
    else
        rec.applied = cast.time
        rec.duration = cast.duration
        rec.expires = cast.time + cast.duration
        rec.endless = nil
        rec.exact = nil
        rec.stacks = cast.most and (rec.stacks or 1) or nil
    end
end

--------------------------------------------------------------------------------
-- Keeping records in line with what the client shows
--------------------------------------------------------------------------------

local sortSet

local function Weaker(a, b)
    local ra, rb = sortSet[a], sortSet[b]
    local wa, wb = ra.weak == true, rb.weak == true
    if wa ~= wb then
        return wa
    end
    if ra.expires ~= rb.expires then
        return ra.expires < rb.expires
    end
    return a < b
end

local function Reconcile(key, sample, now)
    local set = records[key]
    if not set then
        return
    end

    local verified = 0
    local loose
    for name, rec in pairs(set) do
        if rec.id and sample.ids then
            if sample.ids[rec.id] then
                -- Still there, whatever the timer says.
                verified = verified + 1
                if rec.expires < now + HOLD then
                    rec.expires = now + HOLD
                    rec.exact = nil
                end
            elseif not rec.pending then
                set[name] = nil
                ns.Log("%s: the effect dropped off", name)
            end
        elseif not rec.pending and not rec.sticky and not rec.theirs and now < rec.expires then
            -- (Another player's effect is not among the ones counted.)
            loose = loose or {}
            loose[#loose + 1] = name
        end
    end

    -- The client's count caps how many of the unverified records can be real.
    if loose then
        local excess = #loose - (sample.n - verified)
        if excess > 0 then
            sortSet = set
            sort(loose, Weaker)
            sortSet = nil
            for i = 1, excess do
                set[loose[i]] = nil
                ns.Log("%s: fewer effects on the unit than expected, dropping it", loose[i])
            end
        end
    end

    if next(set) == nil then
        records[key] = nil
    end
end

--- One pass.
---   seen     unit key -> sample, or false when the unit is there but its
---            effects are not countable; only units looked at this pass
---   engaged  unit key -> true for enemies currently in the fight
---   direct   unit key -> true for units whose effects were also read by name
function Tracker:Update(now, seen, engaged, direct)
    local i = 1
    while i <= #pending do
        local cast = pending[i]
        local finishing = now >= cast.ends
        local waiting = false -- some unit could still show what the cast did
        -- What the game says a cast did to an enemy can come a frame after
        -- the cast is announced, and what a change or a silence there means
        -- hangs on it. So no cast at an enemy is judged before that moment is
        -- over, however soon it showed.
        local held = cast.kind == "debuff" and now - cast.time <= MOMENT
        for key, unit in pairs(cast.units) do
            local sample = seen[key]
            if not unit.lost and (sample == nil or (unit.watched and not ns.InSight(key, unit.via))) then
                unit.lost = true
                Lose(cast, key, unit)
            end
            local countable = unit.pre ~= nil and sample ~= nil and sample ~= false
            if not unit.settled and countable then
                local gained = Gained(unit.pre, sample, key)
                if gained then
                    Confirm(cast, key, unit, gained, sample, now)
                elseif finishing then
                    unit.observed = sample
                    unit.direct = direct ~= nil and direct[key] == true
                end
            end
            -- A unit is done with once the effect was seen on it, or once it
            -- reported a change and there is no count that could say otherwise.
            -- A cast that only gets the changes nobody else is waiting for is
            -- held a moment longer: the cast the change belongs to may not
            -- have been announced yet.
            -- And one the game called immune to the cast has nothing more
            -- to show. Its cast is kept until the moment of that word is
            -- over as well: a cast of yours that is only announced then
            -- would share the word, and it would be neither one's answer.
            -- The same goes for one the game said the cast did not reach.
            local open = not unit.signal and not Answered(unit) and not Missed(unit)
            if (unit.refused and now - unit.refused <= MOMENT) or (unit.miss and now - unit.miss <= MOMENT) then
                held = true
            end
            if not unit.settled and (countable or open
                or (unit.signal and not Judged(cast) and now < unit.signal + EARLY)) then
                waiting = true
            end
        end
        if not held and (finishing or not waiting) then
            Finish(cast, now, engaged)
            remove(pending, i)
        else
            i = i + 1
        end
    end

    for key, sample in pairs(seen) do
        if sample then
            Reconcile(key, sample, now)
        end
    end

    for key, set in pairs(records) do
        for name, rec in pairs(set) do
            if not IsLive(rec, now) then
                -- An effect that just ran out on a known timer stays a moment
                -- longer, dead, until the report of its ending has been heard.
                local awaited = rec.exact and not rec.told
                if not (awaited and now <= rec.expires + LINGER) then
                    if awaited and not rec.moot and not rec.renewed and ns.InSight(key) then
                        -- The unit was there to report it, and did not.
                        ns.Spells:Ended(name, false)
                    end
                    set[name] = nil
                end
            end
        end
        if next(set) == nil then
            records[key] = nil
        end
    end

    for key, when in pairs(lastChange) do
        if now - when > CHANGE_TTL then
            lastChange[key] = nil
            lastFresh[key] = nil
            credited[key] = nil
            holders[key] = nil
        end
    end
    for g = #guests, 1, -1 do
        if now - guests[g].time > GUEST_TTL then
            remove(guests, g)
        end
    end
    for e = #echoes, 1, -1 do
        if now > echoes[e].till then
            remove(echoes, e)
        end
    end
    for unit, note in pairs(endings) do
        if now - note.when > CHANGE_TTL then
            endings[unit] = nil
        end
    end
    for key, when in pairs(unheeded) do
        if now - when > MOMENT then
            -- No cast of yours was announced in that moment after all.
            ns.NoteRefusal("nobody", lastCast[key], when)
            unheeded[key] = nil
            Elsewhere(key, when)
        end
    end
    for key, said in pairs(spoken) do
        local fresh = said.fresh
        if fresh and now - fresh > MOMENT then
            said.fresh = nil
            Struck(key, fresh)
        end
        if now - max(said.hit or 0, said.no or 0, said.other or 0) > WORDS_TTL then
            spoken[key] = nil
        end
    end
    for key, when in pairs(refusedAt) do
        if now - when > CHANGE_TTL then
            refusedAt[key] = nil
        end
    end
    for key, when in pairs(turned) do
        if now - when > CHANGE_TTL then
            turned[key], turnedWord[key], missedAt[key] = nil, nil, nil
        end
    end
    for key, cast in pairs(lastCast) do
        if now - cast.time > CHANGE_TTL then
            lastCast[key] = nil
        end
    end
    if now >= sweepAt then
        sweepAt = now + SWEEP
        for key, when in pairs(touched) do
            if now - when > STALE then
                touched[key] = nil
                immune[key] = nil
                taken[key] = nil
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Direct readings
--------------------------------------------------------------------------------

--- An effect with this spell's name was read off the unit.
--- aura = { duration, expires, id, stacks, theirs }, any of which may be nil.
--- `stacks` is how many times over it is there, and `theirs` is true for one
--- that another player put there.
function Tracker:Observe(key, name, aura, now)
    local set = records[key]
    local rec = set and set[name]
    if not rec then
        rec = Start(key, name, now, 0)
    end
    local duration = aura.duration and aura.duration > 0 and aura.duration or nil
    local expires = aura.expires and aura.expires > 0 and aura.expires or nil
    rec.duration = duration or rec.duration
    if expires ~= rec.expires then
        rec.told = nil
        rec.moot = nil
    end
    rec.expires = expires or (now + FOREVER)
    rec.endless = expires == nil or nil
    rec.exact = expires ~= nil or nil -- the end time is the game's own
    -- Someone else can renew their copy unseen, so when it ends is not held
    -- for or against the spell.
    rec.renewed = aura.theirs or nil
    rec.applied = duration and expires and (expires - duration) or rec.applied
    if aura.theirs then
        rec.id = nil -- not one of the effects of yours that are counted
    else
        rec.id = aura.id or rec.id
    end
    rec.theirs = aura.theirs or nil
    if aura.stacks then
        rec.stacks = max(1, aura.stacks)
        rec.counted, rec.before, rec.sure = nil, nil, nil -- what was read stands
    end
    rec.weak = nil
    rec.fresh = nil
    rec.pending = nil
    rec.doubt, rec.sureTill, rec.had, rec.unbound, rec.clash = nil, nil, nil, nil, nil -- read off the unit: it is there
    if not key:find("+buffs", -6, true) then
        Taken(key, name, now) -- whoever put it there, the unit is not immune to it
    end
    -- Seen with our own eyes: a cast in flight has nothing left to prove,
    -- and nothing left to add to the count.
    for i = 1, #pending do
        local cast = pending[i]
        local unit = cast.name == name and cast.units[key]
        if unit then
            unit.settled = true
        end
    end
end

--- The game's own tracker answered for a unit and one of your spells (see
--- "The game's own tracker" in Compat.lua): `there` is true when it shows
--- your effect of that spell on the unit, and false when it shows that there
--- is none. It reads the effects themselves, which no addon may in a fight,
--- so its answer stands whatever the books made of your casts. It says
--- neither when the effect got there nor when it ends: the timer in the
--- books is kept, and the tracker's next answers put it right.
---
--- `lasts` is how long the spell's effect lasts at most, when that is known:
--- an effect the books knew nothing of is kept no longer than that after the
--- tracker last showed it. `shared` is true when another player's copy of the
--- effect may be on the unit in place of yours (the unit carries it once, and
--- you are in a group): "none of yours" then only tells of a cast of yours
--- that was not known to have landed.
---
--- Returns what that did to the books, for the saved report: "added" for an
--- effect they did not have, "settled" for one that was in doubt or only
--- assumed, "dropped" for one they had that is not there, and nil when they
--- agreed already. "clashed" when it shows none of an effect the books have
--- from a cast that was seen to land a moment before, with nothing said
--- against it: nothing is changed then, and the caller says which of the two
--- is believed (see Unsettle). "shared" when none of yours left the books as
--- they were because another player's may be there. "early" when a cast of
--- the spell at the unit is so new that the answer may be from before it:
--- it is to be asked again in a moment.
function Tracker:Shown(key, name, there, now, lasts, shared)
    -- While the moment of a cast of that spell at the unit is not over, what
    -- the tracker shows may still be from before the cast.
    for i = 1, #pending do
        local cast = pending[i]
        if cast.name == name and cast.units[key] and now - cast.time <= MOMENT then
            return "early"
        end
    end
    local set = records[key]
    local rec = set and set[name]
    local live = rec ~= nil and IsLive(rec, now)
    if not there then
        -- Not there. Another player's copy is not among the effects the
        -- tracker shows, and a cast still waiting may be on its way, unless
        -- it is of a spell that reaches its target the moment it is cast.
        local flying = rec and rec.pending and not rec.pending.atOnce
        if live and not flying and not rec.theirs and not rec.clash then
            -- Does the effect in the books rest on a cast of yours that is
            -- not known to have landed?
            local open = rec.doubt or rec.weak
            if shared and not open then
                -- Yours was there, and another player's may have taken its
                -- place since: the unit carries the effect once.
                return "shared"
            end
            if rec.signal == true and not rec.doubt and not rec.weak and now - rec.applied <= CLEAN then
                -- Put there by a landing seen a moment ago, with nothing
                -- said against it: the tracker and the unit's own report
                -- disagree. What becomes of it is the caller's to say (see
                -- Unsettle).
                return "clashed"
            end
            if shared and rec.doubt and rec.sureTill and now < rec.sureTill then
                -- The cast in doubt left nothing. What it came on top of is
                -- not yours either, or the tracker would show it: another
                -- player's, there for as long as it was going to be.
                rec.theirs = true
                rec.id = nil
                rec.expires = rec.sureTill
                rec.stacks = rec.had
                rec.doubt, rec.sureTill, rec.had = nil, nil, nil
                rec.exact = nil
                ns.Log("%s: the game's own tracker shows none of yours on the unit: your cast left nothing", name)
                return "dropped"
            end
            Drop(key, name)
            ns.Log("%s: the game's own tracker shows none of yours on the unit, so it is not there", name)
            return "dropped"
        end
        return nil
    end
    local what
    if not live then
        -- The books had nothing. If your last cast at the unit was of this
        -- spell, that is the likeliest way it got there: its timer is taken
        -- from that cast. Otherwise nothing is known of when it ends, only
        -- that it is there while the tracker shows it.
        local cast = lastCast[key]
        if cast and cast.name == name and cast.duration and now < cast.time + cast.duration then
            rec = Start(key, name, cast.time, cast.duration)
            rec.stacks = cast.most and 1 or nil
        else
            rec = Start(key, name, now, lasts or FOREVER)
            rec.endless = not lasts or nil
            rec.unbound = true
        end
        what = "added"
        ns.Log("%s: the game's own tracker shows yours on the unit, so it is there", name)
    elseif rec.doubt and rec.sureTill and now < rec.sureTill then
        -- In doubt, and there either way for now: that the tracker shows it
        -- says nothing of the cast in doubt.
        what = nil
    elseif rec.doubt or rec.weak or rec.theirs then
        what = "settled"
    end
    if not (rec.doubt and rec.sureTill and now < rec.sureTill) then
        rec.doubt, rec.sureTill, rec.had, rec.clash = nil, nil, nil, nil
    end
    rec.weak = nil
    rec.fresh = nil
    rec.theirs = nil -- the tracker only shows your own
    rec.shown = now
    if rec.unbound and lasts and rec.expires < now + lasts then
        -- From here on it can last no longer than a whole one does.
        rec.expires = now + lasts
    end
    if rec.expires < now + HOLD then
        -- Still there, whatever the timer says.
        rec.expires = now + HOLD
        rec.exact = nil
    end
    if not key:find("+buffs", -6, true) then
        Taken(key, name, now) -- the unit is not immune to it
    end
    -- A cast in flight at a unit that did not have the effect has nothing
    -- left to prove. (One that came on top of the effect has: the tracker
    -- shows the effect either way.)
    for i = 1, #pending do
        local cast = pending[i]
        local unit = cast.name == name and cast.units[key]
        if unit and not unit.had then
            unit.settled = true
            if rec.pending == cast then
                rec.pending = nil
            end
        end
    end
    return what
end

--- The unit was read and has no effect with this spell's name.
function Tracker:Absent(key, name)
    local set = records[key]
    local rec = set and set[name]
    if rec and not rec.pending then
        Drop(key, name)
    end
end

--- Everything of yours of one kind ("debuff" or "buff") on the unit was read.
--- `found` maps effect name to { duration, expires, id, stacks, theirs };
--- `bars` is the set of spell names worth keeping. `everyone` is true when
--- other players' effects were read as well, so that one of theirs that is
--- not among `found` is known to be gone.
function Tracker:Sync(key, found, bars, now, kind, everyone)
    for name, aura in pairs(found) do
        if bars[name] then
            self:Observe(key, name, aura, now)
            -- How long someone else's copy lasts says nothing of yours.
            ns.Spells:LearnExact(name, not aura.theirs and aura.duration or nil, kind)
            ns.Spells:LearnStacks(name, aura.stacks)
        end
    end
    local set = records[key]
    if set then
        for name, rec in pairs(set) do
            if not found[name] and ns.Spells:IsExact(name, kind) and (everyone or not rec.theirs) then
                -- A cast still in flight gets its moment to land. But if the
                -- effect was already there when it was cast and is gone now,
                -- the cast is what took it away: a spell that switches itself off.
                local unit = rec.pending and rec.pending.units[key]
                if not rec.pending or (unit and unit.had) then
                    if unit then
                        unit.settled = true
                    end
                    set[name] = nil
                end
            end
        end
        if next(set) == nil then
            records[key] = nil
        end
    end
end

--------------------------------------------------------------------------------
-- Questions
--------------------------------------------------------------------------------

--- Does this unit have this spell's effect right now, as far as we know?
function Tracker:Has(key, name, now)
    return Live(key, name, now) ~= nil
end

--- How many times over this unit has this spell's effect, as far as we know:
--- 0 for not at all, and 1 for an effect that is there and is not counted.
function Tracker:Stacks(key, name, now)
    local rec = Live(key, name, now)
    if not rec then
        return 0
    end
    return rec.stacks or 1
end

--- The game's own tracker shows none of an effect the books have from a
--- landing seen a moment ago (Shown said "clashed"). Two answers that each
--- deserve belief: the effect is in doubt from here on, until a later cast,
--- a look at the unit's effects or the tracker showing it settles it. What
--- the tracker goes on saying of it is not asked for again.
function Tracker:Unsettle(key, name, now)
    local rec = Live(key, name, now)
    if not rec then
        return
    end
    rec.doubt = true
    rec.clash = true
    rec.sureTill, rec.had = nil, nil -- the tracker shows no older one either
    rec.exact = nil
    ns.Log("%s: seen to land, and the game's own tracker shows none: left in doubt", name)
end

--- Whether what Has and Stacks say of this unit and this spell is in doubt.
--- Returns nil when it is not. Otherwise, how many times over the effect is
--- on the unit if things are the other way: 0 for not at all, and math.huge
--- for as many times as it goes.
---
--- Two things put an effect in doubt: a cast the game gave two answers about
--- (see "Two answers at once"), and an effect known from the game's own
--- tracker alone once that has stopped showing it at this very moment (it
--- can only be asked about your target, and not at all while it is hidden).
function Tracker:Doubt(key, name, now)
    local rec = Live(key, name, now)
    if not rec then
        return nil
    end
    if rec.unbound then
        -- Shown right now: it is there, but not how many times over. Not
        -- shown any more: nothing is known of it.
        return rec.shown == now and huge or 0
    end
    if not rec.doubt then
        return nil
    end
    if rec.sureTill and now < rec.sureTill then
        return rec.had or 1
    end
    return 0
end

--- Is this unit taken to be immune to this spell right now, on the game's
--- own word (see "Immune units")?
function Tracker:IsImmune(key, name, now)
    local marks = immune[key]
    local mark = marks and marks[name]
    if mark and now < mark.till then
        touched[key] = now -- still about: what is known of it is kept
        return true
    end
    return false
end

--- Takes back that a unit is immune to a spell: its kind is known to carry
--- the effect, so what the game said of this one will pass.
function Tracker:Pardon(key, name)
    Unmark(key, name)
end

--- Forgets which units were called immune to one spell and which were seen
--- to carry its effect, or all of that with no name given.
function Tracker:ForgetImmune(name)
    for book = 1, 2 do
        local kept = book == 1 and immune or taken
        for key, marks in pairs(kept) do
            if name then
                marks[name] = nil
            end
            if not name or next(marks) == nil then
                kept[key] = nil
            end
        end
    end
end

--- The units taken to be immune right now, for /se debug:
--- { { key, name, left, shield } ... }. `left` is nil for one that stays
--- immune, and `shield` true for one that looks to be behind a shield.
function Tracker:Immunities(now)
    local list = {}
    for key, marks in pairs(immune) do
        for name, mark in pairs(marks) do
            if now < mark.till then
                list[#list + 1] = {
                    key = key, name = name, shield = mark.shield,
                    left = mark.till ~= huge and (mark.till - now) or nil,
                }
            end
        end
    end
    sort(list, function(a, b)
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.key < b.key
    end)
    return list
end

--- Drops every record of one spell (it was just set to be ignored).
function Tracker:Forget(name)
    for key, set in pairs(records) do
        set[name] = nil
        if next(set) == nil then
            records[key] = nil
        end
    end
end

--- Drops every record of one spell's effect that is another player's (it was
--- just set to count only when it is your own).
function Tracker:ForgetTheirs(name)
    for key, set in pairs(records) do
        local rec = set[name]
        if rec and rec.theirs then
            set[name] = nil
            if next(set) == nil then
                records[key] = nil
            end
        end
    end
end

--- Drops everything known about one unit (you died, and your buffs with you).
function Tracker:ForgetUnit(key)
    records[key] = nil
    lastChange[key] = nil
    lastFresh[key] = nil
    credited[key] = nil
    holders[key] = nil
    endings[Owner(key)] = nil -- kept under the unit, whichever book this is
    immune[key], taken[key], touched[key] = nil, nil, nil
    unheeded[key], refusedAt[key], lastCast[key], spoken[key] = nil, nil, nil, nil
    turned[key], turnedWord[key], missedAt[key] = nil, nil, nil
    for i = 1, #pending do
        pending[i].units[key] = nil
    end
    for i = 1, #guests do
        guests[i].units[key] = nil
    end
    for i = 1, #echoes do
        echoes[i].cast.units[key] = nil
    end
end

function Tracker:Reset()
    for key in pairs(records) do
        records[key] = nil
    end
    for i = #pending, 1, -1 do
        pending[i] = nil
    end
    for i = #guests, 1, -1 do
        guests[i] = nil
    end
    for i = #echoes, 1, -1 do
        echoes[i] = nil
    end
    for id in pairs(sent) do
        sent[id] = nil
    end
    lastSent = nil
    for key in pairs(lastChange) do
        lastChange[key] = nil
        lastFresh[key] = nil
        credited[key] = nil
    end
    for key in pairs(holders) do
        holders[key] = nil
    end
    for unit in pairs(endings) do
        endings[unit] = nil
    end
    for _, tbl in pairs({ immune, taken, touched, unheeded, refusedAt, turned, turnedWord, missedAt, lastCast,
        spoken }) do
        for key in pairs(tbl) do
            tbl[key] = nil
        end
    end
    sweepAt = 0
end

--- Live records, for /se debug: { { key, name, left, how, stacks } ... }.
--- `left` is nil for an effect with no end time, and `stacks` for one that is
--- not counted.
function Tracker:Describe(now)
    local list = {}
    for key, set in pairs(records) do
        for name, rec in pairs(set) do
            if IsLive(rec, now) then
                local how
                if rec.pending then
                    how = "just cast"
                elseif rec.theirs then
                    how = "another player's"
                elseif rec.id then
                    how = "matched to the real effect"
                elseif rec.clash then
                    how = "in doubt: seen to land, and the game's own tracker shows none"
                elseif rec.doubt then
                    how = "in doubt: the game said two things about the cast"
                elseif rec.unbound then
                    how = "shown by the game's own tracker"
                elseif rec.weak then
                    how = "assumed"
                elseif rec.signal then
                    how = "the unit's effects changed when it was cast"
                else
                    how = "confirmed"
                end
                list[#list + 1] = {
                    key = key, name = name, how = how, stacks = rec.stacks,
                    left = not rec.endless and (rec.expires - now) or nil,
                }
            end
        end
    end
    sort(list, function(a, b)
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.key < b.key
    end)
    return list
end
