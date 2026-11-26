-- Status Efficiency: which spells leave a status effect, on whom, and for how long.
--
-- A status effect is one of two kinds: a "debuff" the spell puts on enemies, or
-- a "buff" it puts on you (or on the friend you have targeted).
--
-- WoW Forever has its own class design, so there is no table of spells in here.
-- A spell is treated as applying a status effect when one of these holds,
-- strongest first:
--
--   1. You said so with /se track, /se buff or /se debuff (or said the opposite
--      with /se ignore).
--   2. The addon has seen an effect of yours carrying the spell's own name: a
--      debuff on an enemy, or a buff on you. That also settles which of the two
--      the spell leaves, whatever it can be cast on.
--   3. Its tooltip mentions a duration and the client says where it can land: on
--      enemies (a debuff), on friends or only on yourself (a buff). A few well
--      known area debuffs count too. Casting it must not have kept failing to
--      leave anything behind.
--   4. Casting it has repeatedly been followed by a new effect of yours.

local _, ns = ...

local Spells = {}
ns.Spells = Spells

local type, tonumber, pairs, next = type, tonumber, pairs, next
local floor, max = math.floor, math.max

local DEFAULT_DURATION = 12 -- seconds, when nothing better is known
local MAX_DURATION = 3600
local MIN_DURATION = 1

local LOAD_TRIES = 8 -- spell text can arrive late, so ask a few times
local LOAD_RETRY = 1.5

-- How cast results change what is tracked.
-- A likely status spell that keeps leaving nothing loses its icon. A real one
-- misses, is dodged or meets an immune enemy now and then, so this asks for more
-- than a short run of bad luck: of the first six casts, at most one may land.
local DEMOTE_CASTS, DEMOTE_RATIO = 6, 0.2
local PROMOTE_CASTS, PROMOTE_RATIO = 6, 0.8 -- an unlikely one that keeps leaving something
local EVIDENCE_CAP = 40 -- halve the counts past this so old results fade

Spells.DEFAULT_DURATION = DEFAULT_DURATION
Spells.MAX_DURATION = MAX_DURATION
Spells.MIN_DURATION = MIN_DURATION

--------------------------------------------------------------------------------
-- Well known area debuffs
--
-- Spells with no target cannot be recognised from the client's "can be cast on
-- an enemy" answer. These are looked up by id only to get their name in the
-- game's language; an id the client does not know is skipped, and results in
-- play still override the list.
--------------------------------------------------------------------------------

local SEED_IDS = {
    6343, -- Thunder Clap
    1160, -- Demoralizing Shout
    12323, -- Piercing Howl
    5246, -- Intimidating Shout
    1161, -- Challenging Shout
    99, -- Demoralizing Roar
    5209, -- Challenging Roar
    122, -- Frost Nova
    120, -- Cone of Cold
    11113, -- Blast Wave
    31661, -- Dragon's Breath
    5484, -- Howl of Terror
    8122, -- Psychic Scream
}

local seedNames -- name -> true, built on first use

local function IsSeed(name)
    if not seedNames then
        seedNames = {}
        for i = 1, #SEED_IDS do
            local seedName = ns.SpellName(SEED_IDS[i])
            if seedName then
                seedNames[seedName] = true
            end
        end
    end
    return seedNames[name] == true
end

--------------------------------------------------------------------------------
-- Reading a duration out of tooltip text
--------------------------------------------------------------------------------

-- Seconds per unit, for the words that follow a number in a spell description.
local UNIT_WORDS = {
    s = 1, sec = 1, secs = 1, second = 1, seconds = 1,
    sek = 1, sekunde = 1, sekunden = 1,
    seconde = 1, secondes = 1,
    seg = 1, segundo = 1, segundos = 1,
    secondo = 1, secondi = 1,
    min = 60, mins = 60, minute = 60, minutes = 60,
    minuten = 60, minuto = 60, minutos = 60, minuti = 60,
    hr = 3600, hrs = 3600, hour = 3600, hours = 3600,
    std = 3600, stunde = 3600, stunden = 3600,
    heure = 3600, heures = 3600, hora = 3600, horas = 3600,
}

-- Units written without a space or in another script; matched as a prefix.
local UNIT_PREFIXES = {
    { "сек", 1 }, { "мин", 60 }, { "час", 3600 },
    { "초", 1 }, { "분", 60 }, { "시간", 3600 },
    { "秒", 1 }, { "分", 60 }, { "小时", 3600 }, { "小時", 3600 },
}

local function SecondsPer(word)
    local seconds = UNIT_WORDS[word:lower()]
    if seconds then
        return seconds
    end
    for i = 1, #UNIT_PREFIXES do
        local prefix = UNIT_PREFIXES[i]
        if word:sub(1, #prefix[1]) == prefix[1] then
            return prefix[2]
        end
    end
    return nil
end

--- The longest duration mentioned in a spell description, in seconds, or nil.
--- "X damage every 3 sec for 15 sec" gives 15.
function Spells.ParseDuration(text)
    if type(text) ~= "string" or text == "" then
        return nil
    end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", " ")

    local best
    local position = 1
    while true do
        local first, last, number, word = text:find("(%d+[%.,]?%d*)%s*([^%s%d%p]+)", position)
        if not first then
            break
        end
        position = last + 1
        local seconds = SecondsPer(word)
        if seconds then
            local value = tonumber((number:gsub(",", ".")))
            local lead = text:sub(max(1, first - 8), first - 1):lower()
            if value and not lead:find("every%s*$") then
                value = value * seconds
                if value >= MIN_DURATION and value <= MAX_DURATION and (not best or value > best) then
                    best = value
                end
            end
        end
    end
    return best
end

--------------------------------------------------------------------------------
-- What the client says about a spell
--------------------------------------------------------------------------------

local cache = {} -- spell id -> info

local function Load(info, now)
    local id = info.id
    if not info.name then
        info.name = ns.SpellName(id)
    end
    if info.name then
        if info.harmful == nil then
            info.harmful = ns.SpellIsHarmful(id, info.name)
        end
        if info.helpful == nil then
            info.helpful = ns.SpellIsHelpful(id, info.name)
        end
        if info.selfOnly == nil then
            info.selfOnly = ns.SpellIsSelfOnly(id)
        end
        info.passive = ns.SpellIsPassive(id)
        info.range = ns.SpellRange(id)
        local text = ns.SpellDescription(id)
        if text and text ~= "" then
            info.tooltipDuration = Spells.ParseDuration(text)
            info.done = true
        end
    end
    if not info.done then
        info.tries = info.tries + 1
        if info.tries >= LOAD_TRIES then
            info.done = true
        else
            info.retry = now + LOAD_RETRY
            ns.RequestSpellLoad(id)
        end
    end
end

--- Static facts about a spell: { id, name, harmful, helpful, selfOnly, passive,
--- range, tooltipDuration }.
--- Returns nil while the client does not know the spell's name, with a second
--- value of true if it is still worth asking again.
function Spells:Get(spellID, now)
    if type(spellID) ~= "number" then
        return nil, false
    end
    local info = cache[spellID]
    if not info then
        info = { id = spellID, tries = 0, retry = 0, done = false }
        cache[spellID] = info
    end
    if not info.done and now >= info.retry then
        Load(info, now)
    end
    if info.name then
        return info, not info.done
    end
    return nil, not info.done
end

--- Forget everything read from the client (spells changed, or text arrived).
function Spells:Reset(spellID)
    if spellID then
        cache[spellID] = nil
    else
        for id in pairs(cache) do
            cache[id] = nil
        end
        seedNames = nil
    end
end

--------------------------------------------------------------------------------
-- Tracking decisions
--------------------------------------------------------------------------------

-- What was learned by seeing an effect with the spell's own name, per kind.
local SEEN_FIELD = { debuff = "exact", buff = "buff" }

-- Where cast results are counted, per kind. "No new debuff on the enemy" says
-- nothing about a buff on you, so the two are never mixed.
local CASTS_FIELD = { debuff = "casts", buff = "buffCasts" }
local HITS_FIELD = { debuff = "hits", buff = "buffHits" }

--- Where the spell's effect lands: "debuff" (on enemies) or "buff" (on you, or
--- on the friend you have targeted).
local function KindOf(info, user, learned, seed)
    if user and (user.kind == "buff" or user.kind == "debuff") then
        return user.kind
    end
    if seed then
        return "debuff"
    end
    -- What has been seen says more than what the client says a spell can be
    -- cast on: an attack can leave its effect on you rather than on its target.
    if learned and learned.exact then
        return "debuff"
    end
    if learned and learned.buff then
        return "buff"
    end
    if info.harmful == true then
        return "debuff"
    end
    if info.helpful == true or info.selfOnly == true then
        return "buff"
    end
    return "debuff"
end

--- Decides how a spell is treated.
--- Returns tracked, area, duration, source, kind:
---   tracked   whether its status effect is followed and gets an icon
---   area      whether a debuff is judged against every enemy in the fight
---             (true) or only your target (false); always false for a buff
---   duration  how long the effect is assumed to last when it cannot be watched
---   source    why: "you", "ignored", "seen", "built-in", "tooltip", "learned",
---             "demoted", or nil when it simply does not look like a status effect
---   kind      "debuff" or "buff"
function Spells:Tracking(info)
    local name = info.name
    local user = ns.db.spells[name]
    local learned = ns.db.learned[name]
    local seed = IsSeed(name)
    local kind = KindOf(info, user, learned, seed)

    local tracked, source = false, nil
    if user and user.track ~= nil then
        tracked = user.track
        source = tracked and "you" or "ignored"
    elseif info.passive then
        tracked = false
    elseif learned and learned[SEEN_FIELD[kind]] then
        tracked, source = true, "seen"
    else
        local casts = learned and learned[CASTS_FIELD[kind]] or 0
        local hits = learned and learned[HITS_FIELD[kind]] or 0
        local likely
        if kind == "buff" then
            likely = (info.helpful == true or info.selfOnly == true) and info.tooltipDuration ~= nil
        else
            likely = seed or (info.harmful == true and info.tooltipDuration ~= nil)
        end
        if likely then
            if casts >= DEMOTE_CASTS and hits / casts <= DEMOTE_RATIO then
                source = "demoted"
            else
                tracked, source = true, (seed and kind == "debuff") and "built-in" or "tooltip"
            end
        elseif casts >= PROMOTE_CASTS and hits / casts >= PROMOTE_RATIO then
            tracked, source = true, "learned"
        end
    end

    local area
    if kind == "buff" then
        area = false
    elseif user and user.aoe ~= nil then
        area = user.aoe
    elseif seed then
        area = true
    else
        -- Not castable on an enemy and not a helpful spell: no target at all.
        area = info.harmful == false and info.helpful ~= true
    end

    local duration = (user and user.duration)
        or (learned and learned.duration)
        or info.tooltipDuration
        or DEFAULT_DURATION

    return tracked, area, duration, source, kind
end

--- Your own choices for a spell, made on first use: { track, kind, aoe, duration }.
function Spells:Choice(name)
    local choice = ns.db.spells[name]
    if not choice then
        choice = {}
        ns.db.spells[name] = choice
    end
    return choice
end

--- Drops a spell's choices again once none are left, so that it is treated
--- exactly like a spell nobody has touched.
function Spells:Tidy(name)
    local choice = ns.db.spells[name]
    if choice and next(choice) == nil then
        ns.db.spells[name] = nil
    end
end

--- Where a spell's assumed duration comes from: "you", "seen" (read off a unit
--- in play), "tooltip", or "guess" when nothing better is known.
function Spells:DurationSource(info)
    local user = ns.db.spells[info.name]
    local learned = ns.db.learned[info.name]
    if user and user.duration then
        return "you"
    elseif learned and learned.duration then
        return "seen"
    elseif info.tooltipDuration then
        return "tooltip"
    end
    return "guess"
end

--- Whether the spell's casts are worth following at all. Spells that are not
--- tracked yet are still followed, quietly, so the addon can learn from them.
function Spells:Watched(info)
    local user = ns.db.spells[info.name]
    if user and user.track ~= nil then
        return user.track
    end
    return not info.passive
end

--- True when an effect of this kind carrying this exact name has been seen, so
--- a direct look at the unit can confirm or rule out the spell's effect.
function Spells:IsExact(name, kind)
    local learned = ns.db.learned[name]
    return learned ~= nil and learned[SEEN_FIELD[kind]] == true
end

--------------------------------------------------------------------------------
-- Learning
--------------------------------------------------------------------------------

local function Learned(name)
    local learned = ns.db.learned[name]
    if not learned then
        learned = { casts = 0, hits = 0 }
        ns.db.learned[name] = learned
    end
    return learned
end

--- Records the outcome of one cast: did a new effect of yours, of the kind
--- the cast was judged as, follow it?
function Spells:Evidence(name, hit, kind)
    local learned = Learned(name)
    local castsField, hitsField = CASTS_FIELD[kind] or "casts", HITS_FIELD[kind] or "hits"
    local casts = (learned[castsField] or 0) + 1
    local hits = (learned[hitsField] or 0) + (hit and 1 or 0)
    if casts > EVIDENCE_CAP then
        casts, hits = casts / 2, hits / 2
    end
    learned[castsField], learned[hitsField] = casts, hits
    ns.Log("%s: %s (%d of %d casts left an effect)", name, hit and "new effect seen" or "no new effect",
        floor(hits + 0.5), floor(casts + 0.5))
    ns.MarkDirty()
end

--- Records that an effect with the spell's own name was read outright: a debuff
--- off an enemy, or a buff off you or a friend.
function Spells:LearnExact(name, duration, kind)
    local learned = Learned(name)
    local field = SEEN_FIELD[kind]
    local changed = not learned[field]
    learned[field] = true
    if kind == "buff" and duration == 0 then
        duration = MAX_DURATION -- a buff with no timer lasts until something removes it
    end
    if type(duration) == "number" and duration >= MIN_DURATION and duration <= MAX_DURATION then
        if learned.duration ~= duration then
            learned.duration = duration
            changed = true
        end
    end
    if changed then
        ns.Log("%s: its %s was read directly, lasts %s", name, kind,
            learned.duration and (learned.duration .. "s") or "an unknown time")
        ns.MarkDirty()
    end
end

--------------------------------------------------------------------------------
-- How long a cast takes to show on its target
--
-- When the only thing the client reports is that a unit's effects changed, a
-- cast is judged by whether that happens soon after it. The shorter the wait,
-- the less often something else changing on the unit is mistaken for the cast,
-- and the more often a cast that was slow to show is called a miss.
--
-- A spell used at arm's length shows at once, so the gap is timed and the wait
-- cut down to fit. One cast from a distance may have to fly there, for longer
-- or shorter depending on where you stand, so it always gets the full wait.
--------------------------------------------------------------------------------

local min = math.min

local WAIT_MIN, WAIT_MAX = 0.5, 3.0 -- seconds
local WAIT_NEAR = 1.5 -- for a spell used at arm's length that has not been timed yet
local NEAR = 10 -- yards: no flight time to speak of within this
local LAG_TIMED = 3 -- landings to time before a spell's gap is trusted
local LAG_FADE = 0.3 -- how fast an old, longer gap is forgotten

Spells.WAIT_MAX = WAIT_MAX

--- How long to wait for a cast of this spell to change the effects on its
--- target before deciding that it left nothing there.
function Spells:Wait(info)
    if type(info.range) ~= "number" or info.range > NEAR then
        return WAIT_MAX
    end
    local learned = ns.db.learned[info.name]
    local lag = learned and learned.lag
    local timed = learned and learned.timed
    if type(lag) ~= "number" or type(timed) ~= "number" or timed < LAG_TIMED then
        return WAIT_NEAR
    end
    return max(WAIT_MIN, min(WAIT_MAX, 2 * lag + 0.5))
end

--- Records that a cast of this spell showed on its target `delay` seconds
--- after it went off.
function Spells:Landed(name, delay)
    local learned = Learned(name)
    delay = max(0, min(WAIT_MAX, delay))
    local lag = learned.lag
    if type(lag) ~= "number" then
        lag = delay
    else
        lag = max(delay, lag - LAG_FADE * (lag - delay))
    end
    learned.lag = floor(lag * 100 + 0.5) / 100
    local timed = type(learned.timed) == "number" and learned.timed or 0
    learned.timed = min(LAG_TIMED, timed + 1)
end

--- The cast record for a spell judged as one kind, for display: casts, hits
--- (both may be fractional).
function Spells:Record(name, kind)
    local learned = ns.db.learned[name]
    if not learned then
        return 0, 0
    end
    return learned[CASTS_FIELD[kind] or "casts"] or 0, learned[HITS_FIELD[kind] or "hits"] or 0
end
