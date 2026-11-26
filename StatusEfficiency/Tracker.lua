-- Status Efficiency: which of your status effects are on which unit.
--
-- In combat the client will not tell an addon what debuffs an enemy has or what
-- buffs you have, and there is no combat log. What an addon can still see is
-- its own player's casts. So this file keeps its own books:
--
--   * When you cast a tracked spell, its effect is assumed to land on the unit
--     it was aimed at and to last as long as the spell says.
--   * If the client still lets us count your effects on that unit (or see their
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

local GRACE = 2.0 -- seconds after a cast in which its effect is expected to appear
local SENT_TTL = 15 -- forget a cast that was sent but never finished
local HOLD = 0.5 -- an effect we can still see stays alive at least this long between looks
local FOREVER = 3600 -- stand-in timer for an effect that has no duration

Tracker.GRACE = GRACE

-- records[unit key][spell name] = {
--     applied, duration, expires   the timer
--     endless   read off the unit with no end time: `expires` is a stand-in
--     id        aura instance id, once one has been matched to this effect
--     pending   the cast still waiting to be judged, if any
--     fresh     the cast that created the record, until something confirms it
--     weak      assumed from a cast and never confirmed
--     sticky    tracked on your say-so: a lack of evidence never removes it
-- }
local records = {}
local pending = {} -- casts inside their grace period, oldest first
local sent = {} -- cast id -> snapshot taken when the cast was sent
local lastSent -- newest snapshot, for casts whose id cannot be matched

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
---              units = { [unit key] = { pre = sample or nil, engaged = bool } } }
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

--- A cast went off.
--- spell = { name, tracked, area, duration, forced }
function Tracker:Succeeded(snapshot, spell, now)
    local name = spell.name
    local cast = {
        name = name,
        kind = snapshot.kind or "debuff",
        tracked = spell.tracked,
        area = spell.area,
        duration = spell.duration,
        forced = spell.forced,
        time = now,
        ends = now + GRACE,
        units = {},
    }

    for key, was in pairs(snapshot.units) do
        if spell.area then
            cast.units[key] = { pre = not snapshot.late and was.pre or nil, engaged = was.engaged }
        elseif key == snapshot.primary then
            cast.units[key] = { pre = not snapshot.late and was.pre or nil, engaged = true }
        end
    end

    if not spell.tracked then
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
        if spell.tracked then
            if rec then
                if unit.engaged then
                    -- Recast on a unit that already has it: the timer starts over.
                    rec.applied = now
                    rec.duration = spell.duration
                    rec.expires = now + spell.duration
                    rec.endless = nil
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
end

--- True while a cast of this kind ("debuff" or "buff") is waiting to be judged.
function Tracker:HasPending(kind)
    for i = 1, #pending do
        if pending[i].kind == kind then
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
    local rec = Live(key, name, now)
    if not rec then
        rec = Start(key, name, cast.time, cast.duration)
        rec.sticky = cast.forced or nil
    end
    rec.applied = cast.time
    rec.duration = cast.duration
    rec.expires = cast.time + cast.duration
    rec.endless = nil
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
    local clean, unclear = false, false

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

        if unit.settled then
            -- Already confirmed or read directly.
        elseif unit.observed then
            -- Its effects were countable before and after, and nothing new appeared.
            if unit.had or (not unit.direct and unit.observed.n > LiveCount(key, name, now)) then
                -- A refresh, or effects we cannot account for: cannot call it a miss.
                -- (When they were also read by name it can be: an effect of this
                -- spell's would have been recognised among them.)
                unclear = true
                if mine then
                    rec.weak = true
                end
            else
                clean = true
                if mine then
                    if rec.sticky then
                        rec.weak = true
                    else
                        Drop(key, name)
                        ns.Log("%s: nothing new appeared, treating the cast as a miss", name)
                    end
                end
            end
        elseif mine then
            rec.weak = true -- no way to check; keep the assumption
        elseif cast.tracked and cast.area and not (rec and IsLive(rec, now))
            and (unit.engaged or (engaged and engaged[key])) then
            -- An area spell we could not check: assume it caught the enemies in the fight.
            rec = Start(key, name, cast.time, cast.duration)
            rec.weak = true
            rec.sticky = cast.forced or nil
        end
    end

    if cast.hit then
        ns.Spells:Evidence(name, true, cast.kind)
    elseif clean and not unclear then
        ns.Spells:Evidence(name, false, cast.kind)
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
        for key, unit in pairs(cast.units) do
            if not unit.settled and unit.pre then
                local sample = seen[key]
                if sample then
                    local gained = Gained(unit.pre, sample, key)
                    if gained then
                        Confirm(cast, key, unit, gained, sample, now)
                    elseif finishing then
                        unit.observed = sample
                        unit.direct = direct ~= nil and direct[key] == true
                    end
                end
            end
        end
        if finishing then
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
                set[name] = nil
            end
        end
        if next(set) == nil then
            records[key] = nil
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
    rec.expires = expires or (now + FOREVER)
    rec.endless = expires == nil or nil
    rec.applied = duration and expires and (expires - duration) or rec.applied
    rec.id = aura.id or rec.id
    rec.weak = nil
    rec.fresh = nil
    if rec.pending then
        -- Seen with our own eyes: the cast in flight has nothing left to prove.
        local unit = rec.pending.units[key]
        if unit then
            unit.settled = true
        end
        rec.pending = nil
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
