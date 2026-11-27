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
--   3. Its tooltip says how long an effect lasts and the client says where it
--      can land: on enemies (a debuff), on friends or only on yourself (a
--      buff). A time that is something else, such as how soon after a kill the
--      skill has to be used, does not count. A few well known area debuffs
--      count too. Casting it must not have kept failing to leave anything
--      behind; if it has, it gets its icon back once its casts are seen to
--      leave something after all.
--   4. Casting it has repeatedly been followed by a new effect of yours.
--
-- The tooltip is read for two more things. How many times over an effect can
-- be on one unit: a skill whose effect stacks is worth using until the last
-- stack is on. And whether the effect is each caster's own, as damage or
-- healing over time is, or one that a unit carries only once whoever put it
-- there: another player's copy of that kind does what yours would.

local _, ns = ...

local Spells = {}
ns.Spells = Spells

local type, tonumber, tostring, pairs, next = type, tonumber, tostring, pairs, next
local floor, max, min = math.floor, math.max, math.min
local sort = table.sort

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
-- One that has never once left anything is found out sooner, by its first
-- three casts. A real status spell that lands three times in four, which is
-- what was measured in play, starts with three empty casts about one time in
-- sixty, and then has its icon back after two casts that land.
local EMPTY_CASTS = 3
-- One that lost its icon has to do clearly better than that to get it back, so
-- that a spell near the line does not keep losing and regaining it.
local RESTORE_RATIO = 0.4
local PROMOTE_CASTS, PROMOTE_RATIO = 6, 0.8 -- an unlikely one that keeps leaving something
local EARLIER_RATIO = 0.75 -- the most that counts from before 0.3.6 are taken to show: short of earning an icon
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
--
-- A description names times that are not how long anything lasts: how soon
-- after something the skill has to be used, how often an effect ticks, a
-- cooldown, how much longer or shorter something else becomes. One of those
-- taken for the length of an effect puts an icon on a skill that leaves
-- nothing behind. So each time is read with the words around it, and the ones
-- those words rule out are passed over.
--
-- The words are English ones. In another language every time counts, as it
-- did before, and a skill that gets its icon that way loses it again after a
-- few casts that leave nothing (see "How cast results change what is
-- tracked").
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

-- Words that can stand between the telling word and the number without
-- changing what the number is: "by up to 6 sec", "used for the next 10 sec".
local FILLERS = { "up to", "the next", "the first", "an additional", "at least", "at most" }

-- Words right before a time that make it something other than the length of
-- an effect. Only wordings that are never one are listed. A time the list
-- lets through wrongly costs a skill three casts with an icon it should not
-- have; one it keeps out wrongly costs a real status skill its icon until its
-- casts have earned it, which takes longer. So "within" and "for" alone are
-- not on it: "if the target dies within 5 sec" is an effect that lasts 5.
local NOT_A_LENGTH = {
    "every", "each", "per", -- how often something happens
    -- How soon the skill has to be used: "can only be used within 20 sec after
    -- you kill an enemy", "usable for 5 sec after the target dodges".
    "used within", "used only within", "usable within", "usable only within",
    "useable within", "useable only within", "use within", "cast within", "performed within",
    "used for", "usable for", "useable for", "available for",
    "by", -- how much something else changes
    "the last", "the past", "the previous", -- looking back
    "less than", "more than", "longer than", "shorter than", -- a condition
    "cooldown of", "cooldown is",
    "from being cast for", -- how long an interrupted spell stays locked: nothing the enemy shows
}

-- A word right after a time that does the same: "a 30 sec cooldown".
local NOT_A_LENGTH_AFTER = { cooldown = true, recharge = true, cast = true }

local LEAD = 40 -- characters before a time that are looked at
local SHOWN = 28 -- of those, how many are kept for the saved report

--- True when `lead` ends with the word or words in `phrase`.
local function EndsWith(lead, phrase)
    local before = #lead - #phrase
    if before < 0 or lead:sub(before + 1) ~= phrase then
        return false
    end
    return before == 0 or not lead:sub(before, before):find("%a")
end

--- Whether a time can be how long an effect lasts, going by the words before
--- it (lower case, single spaces, none at the end) and the text after it.
--- When it is the word after the time that rules it out, that word is
--- returned as well.
local function IsLength(lead, follow)
    for i = 1, #FILLERS do
        local filler = FILLERS[i]
        if EndsWith(lead, filler) then
            lead = lead:sub(1, #lead - #filler):gsub(" $", "")
            break
        end
    end
    for i = 1, #NOT_A_LENGTH do
        if EndsWith(lead, NOT_A_LENGTH[i]) then
            return false
        end
    end
    local word = follow:match("^%s*(%a+)")
    if word and NOT_A_LENGTH_AFTER[word] then
        return false, word
    end
    return true
end

--- The last words before a time together with the time itself, for the saved
--- report: "damage over 15 sec".
local function Quote(lead, time)
    if #lead > SHOWN then
        lead = lead:sub(-SHOWN):gsub("^%S*%s", "")
    end
    -- Cut by bytes, so it may begin inside a character of more than one: drop
    -- what is left of that character.
    lead = lead:gsub("^[\128-\191]+", "")
    return lead == "" and time or (lead .. " " .. time)
end

--- The longest time in a spell description that can be how long its effect
--- lasts, in seconds, or nil. "X damage every 3 sec for 15 sec" gives 15, and
--- "can only be used within 20 sec after you kill an enemy" gives nothing.
--- Also returns the words that time was read from, and the first time that was
--- passed over with the words that ruled it out (each nil when there is none).
function Spells.ParseDuration(text)
    if type(text) ~= "string" or text == "" then
        return nil
    end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", " ")

    local best, read, passed
    local position = 1
    while true do
        local first, last, number, word = text:find("(%d+[%.,]?%d*)%s*([^%s%d%p]+)", position)
        if not first then
            break
        end
        position = last + 1
        local seconds = SecondsPer(word)
        local value = seconds and tonumber((number:gsub(",", ".")))
        if value then
            value = value * seconds
            local lead = text:sub(max(1, first - LEAD), first - 1):lower():gsub("%s+", " "):gsub(" $", "")
            local quote = Quote(lead, text:sub(first, last))
            local length, after = IsLength(lead, text:sub(last + 1, last + 16):lower())
            if not length then
                passed = passed or (after and (quote .. " " .. after) or quote)
            elseif value >= MIN_DURATION and value <= MAX_DURATION and (not best or value > best) then
                best, read = value, quote
            end
        end
    end
    return best, read, passed
end

--------------------------------------------------------------------------------
-- Reading stacks, and whose effect it is, out of tooltip text
--
-- The words are English ones here too. In another language nothing is read:
-- a skill then counts as one whose effect does not stack and is your own,
-- which is how every skill was treated before 0.4.0. /se stacks and
-- /se anyone say otherwise for a skill.
--------------------------------------------------------------------------------

local STACKS_MIN, STACKS_MAX = 2, 100

--- A description without colour codes, in lower case with single spaces.
local function Plainly(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", " ")
    return (text:lower():gsub("%s+", " "))
end

-- Words right before a number that make it the most times an effect stacks.
local UP_TO = { "up to", "maximum of", "max of", "a total of" }

local function EndsWithAny(lead, phrases)
    for i = 1, #phrases do
        if EndsWith(lead, phrases[i]) then
            return true
        end
    end
    return false
end

--- The most times a spell's effect can be on one unit, read from its
--- description, or nil for one that says nothing of the kind. "Can be
--- applied up to 5 times", "Stacks up to 5 times" and "up to 5 stacks" all
--- give 5. Also returns the words it was read from.
function Spells.ParseStacks(text)
    if type(text) ~= "string" or text == "" then
        return nil
    end
    text = Plainly(text)
    for first, number, last in text:gmatch("()(%d+)()") do
        local value = tonumber(number)
        -- Part of a number with a point in it, "2.5", is no count of anything.
        local before, after = text:sub(first - 1, first - 1), text:sub(last, last + 1)
        if value and value >= STACKS_MIN and value <= STACKS_MAX and not before:find("[%d%.,]")
            and not after:find("^[%.,]%d") then
            -- Only the sentence the number stands in is looked at.
            local lead = text:sub(max(1, first - LEAD), first - 1):gsub("^.*%. ", ""):gsub(" $", "")
            local word = text:sub(last, last + 16):match("^ ?(%a+)")
            local told
            if word == "times" then
                -- "applied up to 5 times", "stacks 3 times": a count of how
                -- often something else happens has neither word before it.
                told = (lead:find("stack") ~= nil or lead:find("appl") ~= nil)
                    and (EndsWithAny(lead, UP_TO) or lead:find("stack%a*$") ~= nil or lead:find("appl%a*$") ~= nil)
            elseif word == "stacks" or word == "applications" then
                told = EndsWithAny(lead, UP_TO) or EndsWith(lead, "max") or EndsWith(lead, "maximum")
            else
                told = lead:find("stack%a* up to$") ~= nil or lead:find("stack%a* to$") ~= nil
            end
            if told then
                local words = (word == "times" or word == "stacks" or word == "applications")
                    and (number .. " " .. word) or number
                return value, Quote(lead, words)
            end
        end
    end
    return nil
end

-- Wordings that show an effect to be each caster's own. One that does its
-- work bit by bit, damage or healing: every caster's adds to the others'.
-- And one that makes the enemy attack its caster: someone else's does not do
-- that for you. Anything else that lasts is taken to be on a unit only once.
local OWN_PLAIN = {
    "damage over", "over time", "per sec", "every sec", "each sec", "periodic",
    "attacks on you", "attack you", "taunt",
}
local OWN_TIMED = { "over (%d+[%.,]?%d*) ?([^%s%d%p]+)", "every (%d+[%.,]?%d*) ?([^%s%d%p]+)" }

--- The words in a spell description that show its effect to be each
--- caster's own, or nil when there are none: "damage over 18 sec", "every 3
--- sec", "attacks on you".
function Spells.ParseOwn(text)
    if type(text) ~= "string" or text == "" then
        return nil
    end
    text = Plainly(text)
    for i = 1, #OWN_TIMED do
        local position = 1
        while true do
            local first, last, _, word = text:find(OWN_TIMED[i], position)
            if not first then
                break
            end
            if SecondsPer(word) then
                return text:sub(first, last)
            end
            position = last + 1
        end
    end
    for i = 1, #OWN_PLAIN do
        local first, last = text:find(OWN_PLAIN[i], 1, true)
        if first then
            return text:sub(first, last)
        end
    end
    return nil
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
            info.tooltipDuration, info.tooltipRead, info.tooltipPassed = Spells.ParseDuration(text)
            info.tooltipStacks, info.stacksRead = Spells.ParseStacks(text)
            info.ownRead = Spells.ParseOwn(text)
            info.described = true
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
--- range, tooltipDuration, tooltipRead, tooltipPassed, tooltipStacks,
--- stacksRead, ownRead, described, gameStacks }. `tooltipRead` and `tooltipPassed` are the
--- words the duration was read from and the first time in the description
--- that was not taken for one. `stacksRead` is the words the most stacks were
--- read from, `ownRead` the words that show the effect to be each caster's
--- own, and `described` is true once a description was there to read.
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

-- Set while a likely spell is without its icon because its casts left nothing.
local DROPPED_FIELD = { debuff = "dropped", buff = "buffDropped" }

--- True when casts of a spell have left too little behind for it to be taken
--- for a status spell on the strength of its tooltip.
local function LeavesNothing(casts, hits)
    return (casts >= EMPTY_CASTS and hits == 0) or (casts >= DEMOTE_CASTS and hits / casts <= DEMOTE_RATIO)
end

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
            local share = casts > 0 and hits / casts or 1
            if LeavesNothing(casts, hits)
                or (learned and learned[DROPPED_FIELD[kind]] and share < RESTORE_RATIO) then
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

--- What the game's own data says of how often a spell's effect stacks: the
--- number for one that does, false for one that does not, nil while the
--- client has not said. It may keep that back while effect details are
--- hidden, so it is asked again until it has answered, or has had nothing to
--- say with the details open: then this client cannot be asked. Once it has
--- answered it is not asked again.
function Spells:GameStacks(info)
    local most = info.gameStacks
    if most == nil then
        most = ns.SpellMaxStacks(info.id)
        if most ~= nil then
            most = most >= STACKS_MIN and most <= STACKS_MAX and most
        elseif not ns.AurasSecret() then
            most = false
        end
        info.gameStacks = most
    end
    return most
end

--- The most times a spell's effect can be on one unit, when that is more than
--- once: what you said with /se stacks, or else the largest of what the game
--- says of the spell, what its tooltip says, and what has been read off a
--- unit. Nil for an effect that does not stack.
function Spells:Stacking(info)
    local user = ns.db.spells[info.name]
    local most = user and user.stacks
    if type(most) ~= "number" then
        local learned = ns.db.learned[info.name]
        local seen = learned and learned.stacks
        most = info.tooltipStacks
        if type(seen) == "number" and (not most or seen > most) then
            most = seen
        end
        local game = self:GameStacks(info)
        if game and (not most or game > most) then
            most = game
        end
    end
    if type(most) == "number" and most >= STACKS_MIN then
        return most
    end
    return nil
end

--- Where the most stacks of a spell comes from: "you", "tooltip", "game" (the
--- game's own data for the spell), "seen" (read off a unit in play), or nil
--- for one that does not stack.
function Spells:StackingSource(info)
    local most = self:Stacking(info)
    if not most then
        return nil
    end
    local user = ns.db.spells[info.name]
    if user and type(user.stacks) == "number" then
        return "you"
    end
    if info.tooltipStacks == most then
        return "tooltip"
    end
    return info.gameStacks == most and "game" or "seen"
end

--- True when a unit carries the spell's effect only once, whoever put it
--- there, so that another player's copy counts for as much as yours: what you
--- said with /se anyone or /se mine, or else what the tooltip shows (see
--- Spells.ParseOwn). A spell whose description could not be read counts as
--- your own.
function Spells:Shared(info)
    local user = ns.db.spells[info.name]
    if user and user.shared ~= nil then
        return user.shared
    end
    return info.described == true and info.ownRead == nil
end

--- Your own choices for a spell, made on first use: { track, kind, aoe,
--- duration, stacks, shared }.
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
    local dropped = DROPPED_FIELD[kind] or "dropped"
    if LeavesNothing(casts, hits) then
        learned[dropped] = true
    elseif hits / casts >= RESTORE_RATIO then
        learned[dropped] = nil
    end
    ns.Log("%s: %s (%d of %d casts left an effect)", name, hit and "new effect seen" or "no new effect",
        floor(hits + 0.5), floor(casts + 0.5))
    ns.MarkDirty()
end

--- Takes down what versions before 0.3.6 counted, once, when their saved
--- settings are first loaded. Then a skill used on an enemy that died in that
--- moment counted as having left something there: the dead enemy's effects
--- going looked like one arriving. For a real status spell that only ever
--- erred on the side of keeping its icon, and nothing changes for it here. For
--- a finishing move it could add up to an icon it should not have. So those
--- counts no longer earn an icon by themselves: a skill that nothing else
--- speaks for has to be seen leaving something a few more times.
function Spells.DiscountEarlier(learned)
    for _, record in pairs(learned) do
        if type(record) == "table" and not record.exact then
            local casts, hits = record.casts, record.hits
            if type(casts) == "number" and type(hits) == "number" and hits > casts * EARLIER_RATIO then
                record.hits = floor(casts * EARLIER_RATIO)
            end
        end
    end
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

--- Records how many times over an effect with the spell's own name was read
--- on a unit. That is how a spell whose tooltip does not say so in words this
--- file knows is found to stack: to at least that many.
function Spells:LearnStacks(name, stacks)
    if type(stacks) ~= "number" or stacks < STACKS_MIN or stacks > STACKS_MAX then
        return
    end
    local learned = Learned(name)
    if type(learned.stacks) ~= "number" or stacks > learned.stacks then
        learned.stacks = stacks
        ns.Log("%s: read %d times over on a unit, so its effect stacks", name, stacks)
        ns.MarkDirty()
    end
end

--------------------------------------------------------------------------------
-- How long another player's copy lasts
--
-- A talent can make your effect last longer than the same spell does from
-- someone without it: a warrior's shouts last half again as long with one. So
-- how long yours lasts is not how long theirs does. In a fight, where a group
-- member's cast is heard and nothing on the unit can be read, giving theirs
-- your time would leave the cross up after their effect had gone.
--
-- Out of a fight their copy can be read, and often who put it there. What a
-- member's own copy was read to last is what their casts are given from then
-- on. Without that, theirs is given two thirds of yours, and no more than the
-- shortest copy of anyone else's that was read. An effect that stacks is one
-- effect which every caster adds to and renews, so it keeps its whole time.
--
-- None of this is saved. It is about the people you are with, and is dropped
-- when the group changes (Core.lua).
--------------------------------------------------------------------------------

local THEIR_SHARE = 2 / 3 -- of how long yours lasts, for a copy nothing is known of

local copyTimes = {} -- spell name -> the shortest another player's copy of its effect was read to last
local memberTimes = {} -- group token -> { spell name -> the shortest that member's copy was read to last }

--- Records that another player's copy of a spell's effect was read off a
--- unit: how long it lasts and, where the game says who put it there, which
--- group member that is (`token`, see ns.GroupToken). Returns "member" or
--- "anyone" when that was news, about the member or about nobody in
--- particular, and nil when it was not.
function Spells:LearnCopy(name, duration, token)
    if type(duration) ~= "number" or duration < MIN_DURATION or duration > MAX_DURATION then
        return nil -- one with no timer, say: nothing to go by
    end
    local news
    local shortest = copyTimes[name]
    if not shortest or duration < shortest then
        copyTimes[name] = duration
        news = "anyone"
    end
    if token then
        local times = memberTimes[token]
        if not times then
            times = {}
            memberTimes[token] = times
        end
        if not times[name] or duration < times[name] then
            times[name] = duration
            news = "member"
            ns.Log("%s: the copy %s put there lasts %ds", name, token, duration)
        end
    end
    return news
end

--- How long a group member's cast of a spell is taken to leave its effect
--- for, where it can only be heard. `mine` is how long yours lasts, or their
--- rank of it where that is less. `token` is the name the member was heard
--- under, and `stacking` is true for an effect that stacks.
function Spells:CopyTime(name, mine, token, stacking)
    local times = token and memberTimes[token]
    local known = times and times[name]
    if known then
        return known
    end
    local time = stacking and mine or mine * THEIR_SHARE
    local shortest = copyTimes[name]
    if shortest and shortest < time then
        time = shortest
    end
    return time
end

--- Forgets what was read of other players' copies: the group has changed, and
--- with it whom each party or raid name stands for.
function Spells:ForgetCopies()
    ns.Wipe(copyTimes)
    ns.Wipe(memberTimes)
end

--------------------------------------------------------------------------------
-- Creatures that are immune
--
-- When the game calls an enemy immune to a skill of yours (see "Immune units"
-- in Tracker.lua), that is nearly always true of every creature of its kind:
-- an elemental does not bleed. So it is kept by kind of creature, with the
-- settings, and the next one of that kind is known for it before the first
-- cast.
--
-- Not on one word, though. An immunity can be passing (a shield, a
-- banishment), and the word can be about someone else's attack in the moment
-- yours missed. A kind is counted on as immune once the game has said so on
-- two occasions and no creature of that kind has been seen to carry the
-- effect. A kind that was both called immune and seen to carry the effect
-- has an immunity that comes and goes: that is kept too, and such a kind is
-- never counted on as immune, in this session or a later one.
--
-- ns.db.immune[spell name][kind] = {
--     seen    on how many occasions the game called that kind immune
--     name    the creature's name, for showing
--     told    true when you said so yourself (/se immune): that stands until
--             you take it back
--     passes  true for a kind whose immunity comes and goes
-- }
-- `kind` is what ns.UnitKind gives: "#" and the game's number for the
-- creature, or its name where the game tells no number.
--------------------------------------------------------------------------------

local SURE = 2 -- occasions on which the game called a kind immune before that is counted on
local SEEN_CAP = 99

local takers = {} -- spell name -> { kind -> true }: seen to carry the spell's effect this session

--- What is kept for a spell, by kind. With `create`, a table to add to.
local function Kinds(name, create)
    local saved = ns.db.immune
    if type(saved) ~= "table" then
        if not create then
            return nil
        end
        saved = {}
        ns.db.immune = saved
    end
    local kinds = saved[name]
    if type(kinds) ~= "table" then
        if not create then
            return nil
        end
        kinds = {}
        saved[name] = kinds
    end
    return kinds
end

--- How often a kind was called immune, as far as the saved entry says.
local function Seen(entry)
    return type(entry.seen) == "number" and entry.seen > 0 and entry.seen or 0
end

--- True for a saved entry that says its kind is, or may be, immune: one you
--- named yourself, or one the game called immune that has not been seen to
--- carry the effect since.
local function Held(entry)
    return type(entry) == "table" and (entry.told == true or (entry.passes ~= true and Seen(entry) > 0))
end

--- The game called a creature of this kind immune to a spell, on a new
--- occasion (`shown` is the creature's name, where that is told). Returns
--- "passing" when that kind has been seen to carry the effect, or when
--- this very creature has (`carried`): its immunity comes and goes, which is
--- what is kept of it. Otherwise whether the kind is counted on as immune
--- now, and how many occasions that makes.
function Spells:SawImmune(name, kind, shown, carried)
    local kinds = Kinds(name, true)
    local entry = kinds[kind]
    if type(entry) ~= "table" then
        entry = {}
        kinds[kind] = entry
    end
    entry.name = shown or entry.name
    local took = takers[name]
    if carried or entry.passes == true or (took and took[kind]) then
        if entry.told ~= true then
            entry.passes = true
            entry.seen = nil
        end
        return "passing"
    end
    entry.seen = min(SEEN_CAP, Seen(entry) + 1)
    return entry.told == true or entry.seen >= SURE, entry.seen
end

--- A creature of this kind was seen to carry the spell's effect, so the kind
--- is not immune to it by nature. Returns true when the game had called it
--- immune before: what was kept of that is turned into "comes and goes".
function Spells:Takes(name, kind)
    local took = takers[name]
    if not took then
        took = {}
        takers[name] = took
    end
    took[kind] = true
    local kinds = Kinds(name)
    local entry = kinds and kinds[kind]
    if entry == nil then
        return false -- nothing kept
    end
    if type(entry) ~= "table" then
        kinds[kind] = nil -- not something this addon wrote
        return false
    end
    if entry.told == true or not Held(entry) then
        return false -- you said so yourself, or known for it already
    end
    entry.passes = true
    entry.seen = nil
    return true
end

--- Is this kind of creature counted on as immune to the spell?
function Spells:KindImmune(name, kind)
    local kinds = Kinds(name)
    local entry = kinds and kinds[kind]
    return type(entry) == "table" and (entry.told == true or (entry.passes ~= true and Seen(entry) >= SURE))
end

--- You said it yourself: this kind of creature is immune to the spell.
function Spells:SetImmune(name, kind, shown)
    local kinds = Kinds(name, true)
    local entry = kinds[kind]
    if type(entry) ~= "table" then
        entry = { seen = 0 }
        kinds[kind] = entry
    end
    entry.told = true
    entry.passes = nil
    entry.name = shown or entry.name
end

--- What is kept of the kinds of creature that are, or may be, immune to a
--- spell, by name: { { kind, name, seen, told, sure } ... }. `sure` is true
--- for one that is counted on, and `told` for one you named yourself. A kind
--- whose immunity comes and goes is not among them.
function Spells:ImmuneKinds(name)
    local list = {}
    local kinds = Kinds(name)
    if kinds then
        for kind, entry in pairs(kinds) do
            if type(kind) == "string" and Held(entry) then
                local told = entry.told == true
                list[#list + 1] = {
                    kind = kind,
                    name = type(entry.name) == "string" and entry.name or tostring(kind),
                    seen = Seen(entry),
                    told = told or nil,
                    sure = told or Seen(entry) >= SURE,
                }
            end
        end
    end
    sort(list, function(a, b)
        if a.name ~= b.name then
            return a.name < b.name
        end
        return tostring(a.kind) < tostring(b.kind)
    end)
    return list
end

--- A kind of creature was found to go by this name: what is kept of it
--- without one gets it, for showing.
function Spells:NameKind(kind, shown)
    local saved = ns.db.immune
    if type(saved) ~= "table" then
        return
    end
    for _, kinds in pairs(saved) do
        local entry = type(kinds) == "table" and kinds[kind]
        if type(entry) == "table" and entry.name == nil then
            entry.name = shown
        end
    end
end

--- The names of the spells some kind of creature is, or may be, immune to
--- as far as is kept, in order.
function Spells:ImmuneSpells()
    local names = {}
    local saved = ns.db.immune
    if type(saved) == "table" then
        for name, kinds in pairs(saved) do
            if type(name) == "string" and type(kinds) == "table" then
                for kind, entry in pairs(kinds) do
                    if type(kind) == "string" and Held(entry) then
                        names[#names + 1] = name
                        break
                    end
                end
            end
        end
    end
    sort(names)
    return names
end

--- Forgets what is kept of immune creatures for one spell, or for every
--- spell with no name given, and with it which kinds were seen to carry the
--- effect. Returns how many kinds that were, or might have been, immune
--- were dropped.
function Spells:ForgetImmune(name)
    local dropped = 0
    local saved = ns.db.immune
    if type(saved) == "table" then
        for spell, kinds in pairs(saved) do
            if not name or spell == name then
                if type(kinds) == "table" then
                    for kind, entry in pairs(kinds) do
                        if type(kind) == "string" and Held(entry) then
                            dropped = dropped + 1
                        end
                    end
                end
                saved[spell] = nil
            end
        end
    end
    if name then
        takers[name] = nil
    else
        ns.Wipe(takers)
    end
    return dropped
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
--
-- A wait of half a second is still long in a group, where an enemy's effects
-- change a few times a second for reasons that are none of yours. In play,
-- about one cast in three of a skill that leaves nothing was followed by
-- such a change within its wait, and a cast that missed was shown as landed
-- as often. So a spell is held to what its casts have been seen to do:
--
--   * One whose casts have kept showing at once is given a quarter of a
--     second and no more.
--   * One whose casts have kept showing in the very frame they were
--     announced, which is what the game was seen to do with every skill used
--     at arm's length, is held to that frame, give or take a twentieth of a
--     second for a report that comes a frame apart from its cast.
--
-- Whatever shows inside the shorter wait and not in the frame itself counts
-- against it, so a spell that stops showing that fast gets its time back. What
-- comes later than that is no longer taken for the cast. Core.lua keeps a few
-- lines about it in the saved report, so that it can be checked afterwards
-- that nothing was turned away that was a cast landing after all.
--------------------------------------------------------------------------------

local WAIT_MIN, WAIT_MAX = 0.5, 3.0 -- seconds
local WAIT_NEAR = 1.5 -- for a spell used at arm's length that has not been timed yet
local NEAR = 10 -- yards: no flight time to speak of within this
local LAG_TIMED = 3 -- landings to time before a spell's gap is trusted
local LAG_FADE = 0.3 -- how fast an old, longer gap is forgotten
local PROMPT = 0.15 -- a cast that showed within this long of being announced showed at once
local PROMPT_SEEN, PROMPT_SHARE = 5, 0.8 -- how many landings at once, and what share of all, hold a spell to it
local WAIT_PROMPT = 0.25 -- how long such a spell is given
local INSTANT_SEEN, INSTANT_SHARE = 3, 0.9 -- the same for landings in the very frame of the cast
local WAIT_INSTANT = 0.05 -- how long such a spell is given, before the cast is announced and after
local LATE_SEEN, LATE_SHARE = 3, 0.5 -- how many landings, and how few of them in the frame, make a spell one that shows late
local PROMPT_CAP = 20 -- halve the counts past this so old results fade

Spells.WAIT_MAX = WAIT_MAX

--- How long to wait for a cast of this spell to change the effects on its
--- target before deciding that it left nothing there. The second value is
--- true for a spell that is held to the frame of its cast: a change is then
--- not looked for any longer before the cast is announced than after it.
function Spells:Wait(info)
    if type(info.range) ~= "number" or info.range > NEAR then
        return WAIT_MAX
    end
    local learned = ns.db.learned[info.name]
    local prompt = learned and learned.prompt
    if type(prompt) == "number" then
        local landings = prompt + (type(learned.tardy) == "number" and learned.tardy or 0)
        local instant = learned.instant
        if type(instant) == "number" and instant >= INSTANT_SEEN and instant >= INSTANT_SHARE * landings then
            return WAIT_INSTANT, true
        end
        if prompt >= PROMPT_SEEN and prompt >= PROMPT_SHARE * landings then
            return WAIT_PROMPT
        end
    end
    local lag = learned and learned.lag
    local timed = learned and learned.timed
    if type(lag) ~= "number" or type(timed) ~= "number" or timed < LAG_TIMED then
        return WAIT_NEAR
    end
    return max(WAIT_MIN, min(WAIT_MAX, 2 * lag + 0.5))
end

--- True for a spell whose casts have mostly shown on the unit outside the
--- frame they were announced in: a change that comes a while after a cast of
--- it is then as good a sign of its landing as there is.
function Spells:ShowsLate(name)
    local learned = ns.db.learned[name]
    local prompt = learned and learned.prompt
    if type(prompt) ~= "number" then
        return false
    end
    local landings = prompt + (type(learned.tardy) == "number" and learned.tardy or 0)
    local instant = type(learned.instant) == "number" and learned.instant or 0
    return landings >= LATE_SEEN and instant < LATE_SHARE * landings
end

--- Records that a cast of this spell showed on its target `delay` seconds
--- after it went off: none at all when it showed in the very frame the cast
--- was announced, and less than none when it showed before that.
function Spells:Landed(name, delay)
    local learned = Learned(name)
    local sameFrame = delay == 0
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
    -- How many of its landings showed at once, and how many later. And of
    -- the ones at once, how many in the very frame of the cast.
    local prompt = type(learned.prompt) == "number" and learned.prompt or 0
    local tardy = type(learned.tardy) == "number" and learned.tardy or 0
    local instant = type(learned.instant) == "number" and learned.instant or 0
    if delay <= PROMPT then
        prompt = prompt + 1
        if sameFrame then
            instant = instant + 1
        end
    else
        tardy = tardy + 1
    end
    if prompt + tardy > PROMPT_CAP then
        prompt, tardy, instant = prompt / 2, tardy / 2, instant / 2
    end
    learned.prompt, learned.tardy, learned.instant = prompt, tardy, instant
end

--------------------------------------------------------------------------------
-- Whether an effect is reported ending when its length says it should
--
-- A change on a unit just as one of your effects there was due to run out is
-- most likely that effect ending, and not a cast landing. That is taken to be
-- so from the start, because the other way round a cast that missed would show
-- as one that landed. It only holds for a spell whose length is right and on a
-- client that reports endings promptly, so it is kept an eye on: each time
-- such an effect comes due, either a change is reported then or it is not, and
-- a spell whose endings mostly go unreported is no longer judged this way.
--------------------------------------------------------------------------------

local ENDS_MISSED = 2 -- endings that have to go unreported before any doubt
local ENDS_CAP = 20 -- halve the counts past this so old results fade

--- Records whether an effect of this spell that came due was reported ending
--- just then.
function Spells:Ended(name, onTime)
    local learned = Learned(name)
    local due = (type(learned.due) == "number" and learned.due or 0) + (onTime and 1 or 0)
    local late = (type(learned.late) == "number" and learned.late or 0) + (onTime and 0 or 1)
    if due + late > ENDS_CAP then
        due, late = due / 2, late / 2
    end
    learned.due, learned.late = due, late
    ns.Log("%s: %s (%d of %d endings were reported on time)", name,
        onTime and "its ending was reported when it was due" or "nothing was reported when it was due to end",
        floor(due + 0.5), floor(due + late + 0.5))
end

--- True when a change at the moment this spell's effect was due to run out
--- can be put down to that. It can, unless its endings have gone unreported
--- at least twice and more than one time in three.
function Spells:EndsOnTime(name)
    local learned = ns.db.learned[name]
    local late = learned and learned.late
    if type(late) ~= "number" or late < ENDS_MISSED then
        return true
    end
    local due = type(learned.due) == "number" and learned.due or 0
    return due >= 2 * late
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
