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
local max = math.max

local GRACE = 2.0 -- seconds after a cast in which its effect is expected to appear
local EARLY = 0.3 -- a unit's effects can be seen to change this long before its cast is reported
local SENT_TTL = 15 -- forget a cast that was sent but never finished
local HOLD = 0.5 -- an effect we can still see stays alive at least this long between looks
local FOREVER = 3600 -- stand-in timer for an effect that has no duration
local CHANGE_TTL = 5 -- how long the time of a unit's last change is kept
local DUE_EARLY, DUE_LATE = 0.1, 0.3 -- how long before and after an effect was due to end a report is still its ending
local LINGER = 0.5 -- an effect that ran out is remembered this long, so the report of its ending is known for what it is

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
-- }
local records = {}
local pending = {} -- casts inside their grace period, oldest first
local sent = {} -- cast id -> snapshot taken when the cast was sent
local lastSent -- newest snapshot, for casts whose id cannot be matched
local lastChange = {} -- unit key -> when the client last reported its effects changing
local credited = {} -- unit key -> the change (by its time) already put down to a cast
local holders = {} -- unit key -> the cast it was put down to
-- unit -> the changes at one moment that were held against your effects there
-- running out: { when, n = how many, [1..n] = true for one put down to an
-- ending by its timing, "gone" for one the client showed to be an effect
-- going, false for one left to the casts, [unit token] = how many of them
-- were heard under that name }
local endings = {}
local heard = {} -- kind of unit token -> true once it has reported a change while details were hidden

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

--- How many live records a unit has, not counting one spell.
local function LiveCount(key, except, now)
    local set = records[key]
    local count = 0
    if set then
        for name, rec in pairs(set) do
            if name ~= except and IsLive(rec, now) then
                count = count + 1
            end
        end
    end
    return count
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

--- The effects on a watched unit changed while a cast of yours was on its way
--- there: take the cast as having landed at that moment.
local function Witness(cast, key, unit, when)
    credited[key] = when
    holders[key] = cast
    unit.signal = when

    local name = cast.name
    if cast.tracked then
        local rec = Live(key, name, when)
        local new = rec == nil
        if new then
            rec = Start(key, name, when, cast.duration)
            rec.fresh = cast
        end
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
    end
    ns.Spells:Landed(name, when - cast.time)
    ns.Log("%s: the unit's effects changed %.2fs after the cast, so it landed", name, when - cast.time)
end

--- True for a cast that is judged by what the unit reports. The others are
--- only credited with a change nobody else is waiting for: a spell taken to
--- land anyway, and one with no icon that is only being learned about.
local function Judged(cast)
    return cast.tracked and not cast.forced
end

--- A cast went off.
--- spell = { name, info, tracked, area, duration, forced, wait, learning }
---   info      what Spells:Get gave for the spell
---   forced    tracked on your say-so where reports cannot be relied on to
---             show what it leaves, so it is assumed to land whatever is seen
---   wait      how long a unit is given to show the cast, when reports of its
---             changes are all there is to judge by
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
            unit = { pre = not snapshot.late and was.pre or nil, engaged = was.engaged }
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
        end
    end
    if cast.trusted and spell.wait then
        -- Judged by reports alone: wait as long as this spell is known to take.
        cast.ends = now + spell.wait
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
        elseif spell.tracked then
            if rec then
                if unit.engaged then
                    -- Recast on a unit that already has it: the timer starts over.
                    rec.applied = now
                    rec.duration = spell.duration
                    rec.expires = now + spell.duration
                    rec.endless = nil
                    rec.exact = nil
                    rec.pending = cast
                end
            elseif not spell.area or (unit.pre == nil and unit.engaged) then
                -- Assume it lands. For an area spell we only assume when there
                -- will be no evidence to wait for.
                rec = Start(key, name, now, spell.duration)
                rec.pending = cast
                rec.fresh = cast
                rec.sticky = spell.forced or nil
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
                Witness(cast, key, unit, when)
            elseif when and when >= cast.from and Judged(cast) and holders[key] and not Judged(holders[key]) then
                -- It went to a cast that is only credited when nobody else is
                -- waiting, because this one had not been announced yet.
                local other = holders[key].units[key]
                if other and other.signal == when then
                    other.signal = nil
                end
                Witness(cast, key, unit, when)
            elseif Judged(cast) and PutDown(Owner(key), now) then
                -- A change on the unit this very frame was put down to an
                -- effect of yours running out, before this cast was announced.
                Witness(cast, key, unit, now)
            end
        end
    end
end

--- The client reported that the effects on a unit changed. It does not say
--- which effect or whose, so the newest cast still waiting on that unit gets
--- the credit. A spell that is taken to land anyway, or that has no icon and
--- is only being learned about, gets it when no other cast is waiting: it may
--- well leave nothing, and must not take the proof away from a cast that is
--- judged by it.
function Tracker:Changed(key, when)
    if lastChange[key] == when then
        return -- one change, reported once for each name the unit goes by
    end
    lastChange[key] = when
    local spare
    for i = #pending, 1, -1 do
        local cast = pending[i]
        local unit = cast.units[key]
        if unit and unit.watched and not unit.signal and not unit.settled and when >= cast.from then
            if Judged(cast) then
                Witness(cast, key, unit, when)
                return
            end
            spare = spare or cast
        end
    end
    if spare then
        Witness(spare, key, spare.units[key], when)
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
--- would take a change reported there now for its own effect arriving.
function Tracker:Judging(unit)
    local buffs = unit .. "+buffs"
    for i = 1, #pending do
        local cast = pending[i]
        if Judged(cast) then
            for book = 1, 2 do
                local waiting = cast.units[book == 1 and unit or buffs]
                if waiting and waiting.watched and not waiting.signal and not waiting.settled then
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
        local units = pending[i].units
        for book = 1, 2 do
            local waiting = units[book == 1 and unit or buffs]
            if waiting and waiting.watched and not waiting.signal and not waiting.settled then
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

    for key, unit in pairs(cast.units) do
        local set = records[key]
        local rec = set and set[name]
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

        local verdict = "unknown"
        if unit.settled then
            verdict = "seen" -- confirmed by its instance id, or read directly
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
            if unit.lost then
                -- It died or went out of sight while the cast waited. A dying
                -- enemy's effects all go, and where the client does not tell
                -- an effect going from one arriving, that is a change too:
                -- nothing is learned about the spell from it.
                blind = true
            else
                signalled = true
            end
            verdict = "changed" -- the books were brought up to date when it was seen
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
                        verdict = verdict == "unknown" and "assumed" or verdict
                    end
                end
            end
        end
        tally[verdict] = (tally[verdict] or 0) + 1
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
                end
            end
        end
    elseif not unclear and not signalled and (clean or (reports and quiet and not blind)) then
        ns.Spells:Evidence(name, false, cast.kind)
    end
    ns.Note(cast, tally, delay, unheard)
end

--- A unit went out of sight while a cast on it was still waiting, or is only
--- still in sight through a kind of token that has never been heard from. A
--- change on it could now go unreported, so the cast is taken to have landed,
--- as it is on a unit nobody reports on.
local function Lose(cast, key, unit)
    if not unit.trusted or unit.signal or unit.settled or not cast.tracked then
        return
    end
    if cast.area and not unit.engaged then
        return
    end
    local name = cast.name
    local rec = Live(key, name, cast.time)
    if not rec then
        rec = Start(key, name, cast.time, cast.duration)
        rec.fresh = cast
        rec.weak = true
    else
        rec.applied = cast.time
        rec.duration = cast.duration
        rec.expires = cast.time + cast.duration
        rec.endless = nil
        rec.exact = nil
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
        elseif not rec.pending and not rec.sticky and now < rec.expires then
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
            if not unit.settled and (countable or not unit.signal
                or (not Judged(cast) and now < unit.signal + EARLY)) then
                waiting = true
            end
        end
        if finishing or not waiting then
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
            credited[key] = nil
            holders[key] = nil
        end
    end
    for unit, note in pairs(endings) do
        if now - note.when > CHANGE_TTL then
            endings[unit] = nil
        end
    end
end

--------------------------------------------------------------------------------
-- Direct readings
--------------------------------------------------------------------------------

--- An effect with this spell's name was read off the unit.
--- aura = { duration, expires, id }, any of which may be nil.
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
    rec.renewed = nil
    rec.applied = duration and expires and (expires - duration) or rec.applied
    rec.id = aura.id or rec.id
    rec.weak = nil
    rec.fresh = nil
    rec.pending = nil
    -- Seen with our own eyes: a cast in flight has nothing left to prove.
    for i = 1, #pending do
        local cast = pending[i]
        local unit = cast.name == name and cast.units[key]
        if unit then
            unit.settled = true
        end
    end
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
--- `found` maps effect name to { duration, expires, id }; `bars` is the set of
--- spell names worth keeping.
function Tracker:Sync(key, found, bars, now, kind)
    for name, aura in pairs(found) do
        if bars[name] then
            self:Observe(key, name, aura, now)
            ns.Spells:LearnExact(name, aura.duration, kind)
        end
    end
    local set = records[key]
    if set then
        for name, rec in pairs(set) do
            if not found[name] and ns.Spells:IsExact(name, kind) then
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

--- Drops every record of one spell (it was just set to be ignored).
function Tracker:Forget(name)
    for key, set in pairs(records) do
        set[name] = nil
        if next(set) == nil then
            records[key] = nil
        end
    end
end

--- Drops everything known about one unit (you died, and your buffs with you).
function Tracker:ForgetUnit(key)
    records[key] = nil
    lastChange[key] = nil
    credited[key] = nil
    holders[key] = nil
    endings[Owner(key)] = nil -- kept under the unit, whichever book this is
    for i = 1, #pending do
        pending[i].units[key] = nil
    end
end

function Tracker:Reset()
    for key in pairs(records) do
        records[key] = nil
    end
    for i = #pending, 1, -1 do
        pending[i] = nil
    end
    for id in pairs(sent) do
        sent[id] = nil
    end
    lastSent = nil
    for key in pairs(lastChange) do
        lastChange[key] = nil
        credited[key] = nil
    end
    for key in pairs(holders) do
        holders[key] = nil
    end
    for unit in pairs(endings) do
        endings[unit] = nil
    end
end

--- Live records, for /se debug: { { key, name, left, how } ... }. `left` is nil
--- for an effect with no end time.
function Tracker:Describe(now)
    local list = {}
    for key, set in pairs(records) do
        for name, rec in pairs(set) do
            if IsLive(rec, now) then
                local how
                if rec.pending then
                    how = "just cast"
                elseif rec.id then
                    how = "matched to the real effect"
                elseif rec.weak then
                    how = "assumed"
                elseif rec.signal then
                    how = "the unit's effects changed when it was cast"
                else
                    how = "confirmed"
                end
                list[#list + 1] = {
                    key = key, name = name, how = how,
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
