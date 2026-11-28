-- Status Efficiency: finds the action buttons, follows your casts and the units
-- they land on, and draws the icon on each button.
--
-- A spell that puts a debuff on enemies:
--   green check          none of the enemies the spell would hit has its effect
--   yellow half circle   some of them have it and some do not
--   red X                all of them have it, so casting again changes nothing
--   no icon              no enemy to judge, and no fight going on
--
-- A spell that puts a buff on you, or on the friend you have targeted:
--   green check          the buff is not there
--   red X                the buff is there, so casting again changes nothing
--
-- An effect that stacks is only "there" once it is on as many times over as
-- it goes: until then another cast still adds to it, and that is the green
-- check. The yellow half circle is for a spell that hits several enemies when
-- some of them carry it in full and others do not.
--
-- An effect that a unit carries only once, whoever put it there, counts when
-- it is another player's: a second warrior's shout does what yours would.
--
-- An enemy that is immune to a spell's effect is not counted: it can never
-- have it, so it is no reason to cast. With nobody left who could take the
-- effect, that is the red X. An enemy is only taken to be immune on the
-- game's own word (see "Immune enemies" below).
--
-- A spell that applies no status effect gets no icon. Two settings say when the
-- icons appear at all: always, only while you are in combat, or while you or
-- someone in your party or raid close by is in combat (the default); and on
-- every skill, or only on one that can be used right now (the default).
--
-- A fight that brings the icons up keeps them on from its first moment to its
-- last, whatever is targeted. A debuff with no enemy to judge it on shows the
-- green check then.
--
-- In combat the client hides what effects a unit has, but still reports the
-- moment they change. A cast only counts as applied once the unit it went to
-- reports such a change: a miss, a dodge or a resist changes nothing, so the
-- icon stays green. Where the client shows that a report only took effects
-- away, it is not such a change: nothing arrived.

local ADDON_NAME, ns = ...

local Spells, Tracker, Icons = ns.Spells, ns.Tracker, ns.Icons

local pairs, type, pcall, tostring, next = pairs, type, pcall, tostring, next
local floor, min, max = math.floor, math.min, math.max
local format = string.format

local plateTokens = ns.plateTokens

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

-- Where the icon can sit on a button, and how far it is nudged past the edge.
local CORNERS = {
    TOPLEFT = { -2, 2 },
    TOP = { 0, 2 },
    TOPRIGHT = { 2, 2 },
    LEFT = { -2, 0 },
    CENTER = { 0, 0 },
    RIGHT = { 2, 0 },
    BOTTOMLEFT = { -2, -2 },
    BOTTOM = { 0, -2 },
    BOTTOMRIGHT = { 2, -2 },
}
ns.CORNERS = CORNERS

-- The icon's size in pixels when one is chosen. With none chosen it follows the
-- button, taking this share of its width.
local SIZE_MIN, SIZE_MAX = 8, 48
local OLD_SIZE_MAX = 128 -- how far sizes went before 0.3.0
local AUTO_SHARE = 0.36
local STANDARD_BUTTON = 45 -- an action button's width, for when one cannot be measured
ns.SIZE_MIN, ns.SIZE_MAX = SIZE_MIN, SIZE_MAX

-- When the icons appear at all: "always" (whenever there is something to judge),
-- "combat" (only while you are in combat yourself) or "group" (while you are in
-- combat, or someone in your party or raid is in combat close by).
local APPEAR = { always = true, combat = true, group = true }
local APPEAR_DEFAULT = "group"
ns.APPEAR_DEFAULT = APPEAR_DEFAULT

-- A choice of earlier versions that is gone, and the one that takes its place.
-- "target" (0.3.0 to 0.3.8) showed the icons while an enemy was targeted, and
-- from 0.3.8 all through a fight as well, which is the part that is kept.
local APPEAR_BEFORE = { target = "group" }

-- The layout of what is saved. 2 (0.3.6): the cast counts under `learned` no
-- longer take an enemy's death for a skill leaving something.
local SETTINGS_VERSION = 2

local function Defaults()
    return {
        version = SETTINGS_VERSION,
        enabled = true,
        appear = APPEAR_DEFAULT,
        usableOnly = true, -- an icon only on a skill that can be used right now
        -- When enemy nameplates are off: "on" turns them back on and says
        -- so in chat, "tell" only says so, "off" does nothing.
        nameplates = "on",
        corner = "TOPLEFT",
        size = 0, -- 0 sizes the icon from the button
        plain = false, -- draw the settings panel without the game's own controls
        window = {}, -- where the settings window was dragged to: { point, relative, x, y }
        interval = 0.2, -- seconds between looks at the enemies
        log = false,
        icons = {}, -- the icon chosen for each result; empty means the default
        custom = {}, -- your own texture for a result set to "custom"
        spells = {}, -- your choices by spell name: { track, kind, aoe, duration, stacks, shared }
        -- What play has shown, by spell name: { exact, casts, hits, dropped, buff,
        -- buffCasts, buffHits, buffDropped, duration, lag, timed, prompt, tardy,
        -- instant, due, late, told, stacks }
        learned = {},
        -- The kinds of creature the game has called immune to a skill, by
        -- spell name and kind: { seen, name, told, passes } (see Spells.lua)
        immune = {},
    }
end

ns.db = Defaults()

local function LoadSettings()
    local saved = StatusEfficiencyDB
    if type(saved) ~= "table" then
        saved = {}
        StatusEfficiencyDB = saved
    end
    -- What an earlier version saved. Settings with no version at all are new.
    local version = type(saved.version) == "number" and saved.version or SETTINGS_VERSION
    for key, value in pairs(Defaults()) do
        if type(saved[key]) ~= type(value) then
            saved[key] = value
        end
    end
    if not CORNERS[saved.corner] then
        saved.corner = "TOPLEFT"
    end
    saved.appear = APPEAR_BEFORE[saved.appear] or saved.appear
    if not APPEAR[saved.appear] then
        saved.appear = APPEAR_DEFAULT
    end
    if saved.interval < 0.05 or saved.interval > 2 then
        saved.interval = 0.2
    end
    if not ns.NAMEPLATE_CHOICES[saved.nameplates] then
        saved.nameplates = "on"
    end
    if saved.size > SIZE_MAX and saved.size <= OLD_SIZE_MAX then
        saved.size = SIZE_MAX -- chosen when sizes went further: keep it as big as it can be
    elseif saved.size ~= 0 and (saved.size < SIZE_MIN or saved.size > SIZE_MAX) then
        saved.size = 0
    end
    if version < 2 then
        Spells.DiscountEarlier(saved.learned)
    end
    saved.version = SETTINGS_VERSION
    ns.db = saved
end

function ns.Log(text, ...)
    if ns.db.log then
        ns.Print("|cff999999" .. format(text, ...) .. "|r")
    end
end

--------------------------------------------------------------------------------
-- Problems
--
-- The addon runs on a client it was not tested against, so nothing here is
-- allowed to throw into the game's error handler over and over.
--------------------------------------------------------------------------------

local reported = {}
local reportCount = 0

--- Keeps a problem in the saved report as well, so that it can be read there
--- afterwards without anyone having to copy it out of the chat window.
local function KeepProblem(err)
    local journal = ns.Journal()
    local problems = journal.problems
    if type(problems) ~= "table" then
        problems = {}
        journal.problems = problems
    end
    problems[#problems + 1] = err
end

local function Report(err)
    err = tostring(err)
    ns.lastError = err
    ns.errorCount = (ns.errorCount or 0) + 1
    if not reported[err] and reportCount < 3 then
        reported[err] = true
        reportCount = reportCount + 1
        ns.Print("The addon hit a problem and skipped an update. Type /se debug to see the details. (" .. err .. ")")
        if ns.Journal then
            pcall(KeepProblem, err)
        end
    end
end

local function Guard(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        Report(err)
    end
    return ok
end

ns.Guard = Guard

--------------------------------------------------------------------------------
-- Action buttons
--------------------------------------------------------------------------------

local BUTTON_NAMES = {}
do
    local blizzard = {
        "ActionButton",
        "MultiBarBottomLeftButton",
        "MultiBarBottomRightButton",
        "MultiBarRightButton",
        "MultiBarLeftButton",
        "MultiBar5Button",
        "MultiBar6Button",
        "MultiBar7Button",
    }
    for _, prefix in pairs(blizzard) do
        for i = 1, 12 do
            BUTTON_NAMES[#BUTTON_NAMES + 1] = prefix .. i
        end
    end
    -- Popular bar addons, in case one is installed.
    for i = 1, 180 do
        BUTTON_NAMES[#BUTTON_NAMES + 1] = "BT4Button" .. i
        BUTTON_NAMES[#BUTTON_NAMES + 1] = "DominosActionButton" .. i
    end
    for bar = 1, 15 do
        for i = 1, 12 do
            BUTTON_NAMES[#BUTTON_NAMES + 1] = "ElvUI_Bar" .. bar .. "Button" .. i
        end
    end
end

local entries = {} -- { frame, name, info, overlay, texture, state, art, size, corner, broken }
local known = {} -- frame -> entry
local barNames = {} -- spell name -> true, for every spell on a button
local barInfo = {} -- spell name -> what Spells:Get gave for it

ns.buttons = entries
ns.barNames = barNames

local barsDirty, stateDirty = true, true
local lastScan, lastRefresh, nextFind = -100, -100, -100

function ns.MarkDirty()
    stateDirty = true
end

function ns.MarkBarsDirty()
    barsDirty = true
    stateDirty = true
end

local function FindButtons()
    for i = 1, #BUTTON_NAMES do
        local frame = _G[BUTTON_NAMES[i]]
        if type(frame) == "table" and not known[frame] and type(ns.Field(frame, "IsVisible")) == "function" then
            local entry = { frame = frame, name = BUTTON_NAMES[i] }
            known[frame] = entry
            entries[#entries + 1] = entry
        end
    end
end

local function Visible(frame)
    return ns.Flag(ns.Field(frame, "IsVisible"), frame) == true
end

--- The size an icon gets on this button when no size has been chosen.
local function AutoSize(frame)
    local width = frame and ns.Call(ns.Field(frame, "GetWidth"), frame)
    if type(width) ~= "number" or width <= 0 then
        width = STANDARD_BUTTON
    end
    return max(10, min(40, floor(width * AUTO_SHARE + 0.5)))
end

local function IconSize(entry)
    local size = ns.db.size
    if size > 0 then
        return size
    end
    return AutoSize(entry.frame)
end

--- The size "auto" comes to on a typical button: the first one on screen.
function ns.AutoIconSize()
    for i = 1, #entries do
        if Visible(entries[i].frame) then
            return AutoSize(entries[i].frame)
        end
    end
    return AutoSize(nil)
end

--- A typical action button, the first one on screen: its width, and how many
--- times larger it is drawn than `frame` would draw the same width (1 when the
--- two share a scale). The settings panel sizes its preview from this.
function ns.TypicalButton(frame)
    for i = 1, #entries do
        local button = entries[i].frame
        if Visible(button) then
            local width = ns.Call(ns.Field(button, "GetWidth"), button)
            if type(width) == "number" and width > 0 then
                local scale = ns.Call(ns.Field(button, "GetEffectiveScale"), button)
                local own = frame and ns.Call(ns.Field(frame, "GetEffectiveScale"), frame)
                if type(scale) == "number" and type(own) == "number" and scale > 0 and own > 0 then
                    return width, scale / own
                end
                return width, 1
            end
        end
    end
    return STANDARD_BUTTON, 1
end

local function Layout(entry)
    local overlay = entry.overlay
    if not overlay then
        return
    end
    local size = IconSize(entry)
    local corner = ns.db.corner
    if entry.size == size and entry.corner == corner then
        return
    end
    entry.size, entry.corner = size, corner
    local offset = CORNERS[corner] or CORNERS.TOPLEFT
    overlay:SetSize(size, size)
    overlay:ClearAllPoints()
    overlay:SetPoint(corner, entry.frame, corner, offset[1], offset[2])
end

-- The icon lives in its own frame parented to the button. Nothing is written
-- into the button itself, so Blizzard's secure button code stays untouched.
local function CreateOverlay(entry)
    local button = entry.frame
    local overlay = CreateFrame("Frame", nil, button)
    local level = ns.Call(ns.Field(button, "GetFrameLevel"), button)
    overlay:SetFrameLevel((type(level) == "number" and level or 1) + 10)
    local texture = overlay:CreateTexture(nil, "OVERLAY")
    texture:SetAllPoints(overlay)
    overlay:Hide()
    entry.overlay, entry.texture = overlay, texture
    Layout(entry)
end

--- Shows the icon for a state on a button, or nothing: for no state, and for a
--- state whose result has been given no icon.
local function SetState(entry, state)
    local art = state and Icons.Texture(state) or nil
    if entry.state == state and entry.art == art then
        return
    end
    if art and not entry.overlay then
        if entry.broken or not pcall(CreateOverlay, entry) or not entry.overlay then
            entry.broken = true
            return
        end
    end
    entry.state, entry.art = state, art
    if art then
        if entry.texture:SetTexture(art) == false and state == Icons.UNSURE.key then
            -- A copy of the addon without that file: the game's own mark.
            entry.texture:SetTexture(Icons.UNSURE.fallback)
        end
        entry.overlay:Show()
    elseif entry.overlay then
        entry.overlay:Hide()
    end
end

local function HideAll()
    for i = 1, #entries do
        SetState(entries[i], nil)
    end
end

ns.HideAll = HideAll

-- Who last answered whether a skill can be used, and whether its target is in
-- reach, for /se usable and /se debug: "bar" (the action bar's own call),
-- "spell" (the same asked about the spell), "look" (read off the button as the
-- game has painted it), or "no" once nobody has answered for a moment.
local usableProbe = { usable = "not asked yet", range = "not asked yet" }
ns.usableProbe = usableProbe

local PROBE_PATIENCE = 1 -- seconds without an answer, on any button, before it says "no"

local function Probed(what, how, now)
    local at = what .. "At"
    if how then
        usableProbe[what], usableProbe[at] = how, now
    elseif not usableProbe[at] or now - usableProbe[at] >= PROBE_PATIENCE then
        usableProbe[what] = "no"
    end
end

--- Keeps, in the saved report, who answered about each button: how often the
--- pair "usable / in reach" turned to each pair of sources, with "nobody" for
--- no answer and "-" where reach was not asked. In a fight and out of one are
--- kept apart, since a fight is when the game holds things back.
local function NoteSource(entry, how, howRange, reachAsked)
    local key = (how or "nobody") .. " / " .. (reachAsked and (howRange or "nobody") or "-")
    local when = ns.InCombat() and "fight" or "calm"
    if entry.from == key and entry.fromWhen == when then
        return
    end
    entry.from, entry.fromWhen = key, when
    local journal = ns.Journal()
    local from = journal.usableFrom
    if type(from) ~= "table" then
        from = {}
        journal.usableFrom = from
    end
    local counts = from[when]
    if type(counts) ~= "table" then
        counts = {}
        from[when] = counts
    end
    counts[key] = (counts[key] or 0) + 1
end

--- Keeps, in the saved report, what the game has answered about each skill:
--- how often its answer turned to "yes", "short" (of rage, mana or energy),
--- "no" (any other reason), "unsaid" (not usable, and it would not say why) or
--- "silent" (no answer at all), each with ", far" while the target is out of
--- reach or too close. That is how the rule below can be checked against a
--- real client afterwards.
local function NoteUsable(entry, usable, inRange, lacking)
    local name = entry.info and entry.info.name
    if not name then
        return
    end
    local answer
    if usable == nil then
        answer = inRange == false and "silent, far" or "silent"
    elseif usable then
        answer = inRange == false and "yes, far" or "yes"
    elseif lacking then
        answer = inRange == false and "short, far" or "short"
    elseif lacking == false then
        answer = inRange == false and "no, far" or "no"
    else
        answer = inRange == false and "unsaid, far" or "unsaid"
    end
    if entry.said == answer and entry.saidOf == name then
        return
    end
    entry.said, entry.saidOf = answer, name
    local journal = ns.Journal()
    local all = journal.usable
    if type(all) ~= "table" then
        all = {}
        journal.usable = all
    end
    local answers = all[name]
    if type(answers) ~= "table" then
        answers = {}
        all[name] = answers
    end
    answers[answer] = (answers[answer] or 0) + 1
end

--- Whether the skill on a button can be used right now: not while its target
--- is too far or too close, and not while the game dims it for the wrong
--- stance, a skill that cannot be used in a fight, and the like.
---
--- Being short of rage, mana or energy is not counted. The icon says whether
--- the skill is worth its cost, and rage comes and goes all through a fight:
--- an icon that went away each time a skill had just been paid for would be
--- gone at the very moment it has something new to say.
---
--- `unit` is whom the skill would go to: reach is judged to that unit, and
--- not at all when it is you.
---
--- The game is asked about the action, then about the spell, and at last the
--- button itself is looked at (see ns.ActionUsable). An answer nobody gives
--- counts as yes: that it can be used, or that rage is all that is missing. So
--- does a cooldown, which the game can keep to itself during a fight.
local function CanUse(entry, unit)
    local slot = entry.slot
    if not slot then
        return true
    end
    local usable, inRange, lacking, how, howRange = ns.ActionUsable(slot, unit, entry.info and entry.info.id,
        entry.frame)
    local now = ns.Now()
    Probed("usable", how, now)
    if unit ~= "player" then
        Probed("range", howRange, now)
    end
    NoteSource(entry, how, howRange, unit ~= "player")
    NoteUsable(entry, usable, inRange, lacking)
    if inRange == false then
        return false
    end
    return usable ~= false or lacking ~= false
end

-- While the settings panel is open on its Display or Icons tab, and you are not in a
-- fight, every button that holds a spell shows a sample icon, the three results
-- in turn, so the look can be judged on the real bars with nothing targeted.
local SAMPLE_STATES = { "none", "some", "all" }
local showSamples = false

--- Turns the sample icons on or off. The settings panel calls this.
function ns.SetSampling(on)
    on = on and true or false
    if showSamples ~= on then
        showSamples = on
        ns.MarkDirty()
    end
end

function ns.IsSampling()
    return showSamples
end

--- Re-applies icon size, position and artwork after a setting changed.
function ns.Relayout()
    for i = 1, #entries do
        local entry = entries[i]
        entry.size = nil
        Layout(entry)
        if entry.state then
            SetState(entry, entry.state)
        end
    end
end

local function ScanBars(now)
    barsDirty = false
    lastScan = now
    if now >= nextFind then
        nextFind = now + 5
        FindButtons()
    end
    ns.Wipe(barNames)
    ns.Wipe(barInfo)
    for i = 1, #entries do
        local entry = entries[i]
        local info
        local slot = ns.ButtonSlot(entry.frame)
        local spellID = slot and ns.SlotSpell(slot)
        if spellID then
            local loading
            info, loading = Spells:Get(ns.OverrideSpell(spellID), now)
            if loading then
                barsDirty = true -- its name or tooltip has not arrived yet
            end
        end
        entry.info, entry.slot = info, slot
        if info then
            barNames[info.name] = true
            barInfo[info.name] = info
        end
        Layout(entry)
    end
    stateDirty = true
end

--- The spells on the bars, one entry per name, sorted.
function ns.BarSpells()
    local list, have = {}, {}
    for i = 1, #entries do
        local info = entries[i].info
        if info and not have[info.name] then
            have[info.name] = true
            list[#list + 1] = info
        end
    end
    table.sort(list, function(a, b)
        return a.name < b.name
    end)
    return list
end

--- The action slot a spell sits in: the first of them, or nil for a spell that
--- is on no bar. The settings panel asks, for the picture on that slot.
function ns.BarSlot(name)
    for i = 1, #entries do
        local entry = entries[i]
        if entry.slot and entry.info and entry.info.name == name then
            return entry.slot
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Who a spell is judged on
--------------------------------------------------------------------------------

local function Attackable(unit)
    return ns.Exists(unit) and ns.IsEnemy(unit) and not ns.IsDead(unit)
end

--- The enemy a targeted spell would go to right now.
local function PrimaryEnemy()
    if Attackable("target") then
        return "target"
    end
    if Attackable("softenemy") then
        return "softenemy"
    end
    return nil
end

ns.PrimaryEnemy = PrimaryEnemy

--- Your target, when it is someone a helpful spell would go to instead of you.
local function FriendTarget()
    if ns.Exists("target") and not Attackable("target") and ns.CanAssist("target") and not ns.IsDead("target") then
        return "target"
    end
    return nil
end

--- True for a buff spell that can be put on someone other than you.
local function CastOnFriends(info)
    return info.helpful == true and info.selfOnly ~= true
end

--- The unit a buff spell would land on right now: the friend you have targeted
--- when the spell can be cast on others, otherwise you.
local function BuffUnit(info)
    return CastOnFriends(info) and FriendTarget() or "player"
end

--- The name a unit's books are kept under. A unit's buffs are kept apart from
--- its debuffs, so that no unit is ever judged on the wrong kind of effect.
local function KeyOf(unit, kind)
    local key = ns.UnitKey(unit)
    if kind == "buff" then
        return key .. "+buffs"
    end
    return key
end

ns.KeyOf = KeyOf

--------------------------------------------------------------------------------
-- Change reports
--
-- While effect details are hidden the client still says when the effects on a
-- unit change, though not what changed. Every unit token a spell can be judged
-- on is listened to for that: you, your target, your soft target and the
-- nameplates. All that is passed on to the tracker is "the effects on this unit
-- changed at this moment"; it decides whether a cast of yours explains it.
--
-- These reports are what a cast is judged by from the first one on: nothing is
-- taken to have landed until the unit says so. A client that turns out to say
-- nothing is found out after a few casts, and from then on a cast there is
-- taken to land, as it has to be wherever there is nothing to go on.
--
-- What the client really sends is also written to a report kept with the
-- settings, so that this can be checked against a real client afterwards.
--------------------------------------------------------------------------------

local SETTLE = 0.5 -- seconds a token counts as new after it was handed to another unit
local RECENT = 0.5 -- how long a report waits for a cast that has not been announced yet
-- Casts in a row with nothing at all reported before the client is taken not
-- to report there: more of them where an earlier session on this build heard it.
local QUIET_LIMIT, QUIET_PROVEN = 3, 6
local REPORT_CASTS = 40 -- casts kept in the saved report
local REPORT_SESSIONS = 2 -- earlier sessions kept in it
local REPORT_NOTES = 20
local REPORT_SHAPES = 12 -- different descriptions of what a report carried kept in it

local MAIN_TOKENS = { "target", "softenemy" }

local listening = {} -- unit token -> true when the client lets us listen for its changes
local changes = {} -- unit token -> when its effects were reported changing, until that is passed on
-- unit token -> what that report showed of the change: true when it only added
-- effects, false when it only renewed some. Nothing when it did not say, or
-- when two reports of one moment said different things.
local arrivals = {}
local departures = {} -- unit token -> when it last reported effects going and none coming
local assigned = {} -- unit token -> when it was last handed to a different unit
local everyone = -100 -- when every token was last handed out afresh

-- How often the client has reported a change while details were hidden, this
-- session, through each kind of unit token. Until it has, silence through that
-- kind of token is not held against a cast: a client could report on your
-- target and not on nameplates, or the other way round.
local TOKEN_KINDS = { "player", "target", "softenemy", "plate" }
local signals = {}
for i = 1, #TOKEN_KINDS do
    signals[TOKEN_KINDS[i]] = { heard = 0, quiet = 0 }
end
ns.signals = signals
ns.TOKEN_KINDS = TOKEN_KINDS

-- Kind of token -> the unit keys looked at through a listening token of that
-- kind in the current pass.
local sight = {}
for i = 1, #TOKEN_KINDS do
    sight[TOKEN_KINDS[i]] = {}
end

local SESSION = ns.WallClock() .. " / " .. format("%.2f", ns.Now())
local sessionStart = ns.Now()
local buildKey

local function BuildKey()
    buildKey = buildKey or ns.BuildKey()
    return buildKey
end

--- A table kept with the settings, made on first use. These are not part of
--- Defaults: they need no repair, and /se reset is meant to clear them.
local function Kept(field)
    local tbl = ns.db[field]
    if type(tbl) ~= "table" then
        tbl = {}
        ns.db[field] = tbl
    end
    return tbl
end

--- The report saved with the settings: what this client sends and how each
--- cast was judged, for this session and the last few that saw any casts.
local function Journal()
    local journal = ns.db.report
    if type(journal) == "table" and journal.session == SESSION then
        return journal
    end
    local earlier = {}
    if type(journal) == "table" then
        local older = journal.earlier
        journal.earlier = nil
        if type(journal.casts) == "table" and #journal.casts > 0 then
            earlier[1] = journal
        end
        if type(older) == "table" then
            for i = 1, #older do
                if #earlier < REPORT_SESSIONS then
                    earlier[#earlier + 1] = older[i]
                end
            end
        end
    end
    journal = {
        session = SESSION,
        addon = ns.VERSION,
        client = BuildKey(),
        started = ns.WallClock(),
        -- Reports of a unit's effects changing: with details hidden, without,
        -- with details hidden but a payload we could have read, and with a
        -- payload we could not read although nothing was said to be hidden.
        reports = {
            player = { hidden = 0, calm = 0, readable = 0, masked = 0 },
            target = { hidden = 0, calm = 0, readable = 0, masked = 0 },
            softenemy = { hidden = 0, calm = 0, readable = 0, masked = 0 },
            plate = { hidden = 0, calm = 0, readable = 0, masked = 0 },
            sameFrame = 0, -- ignored: the token was handed to another unit that very frame
            handover = 0, -- ignored: only a token the unit had just been given reported it
            ended = 0, -- put down to an effect of yours running out just then
            gone = 0, -- only took effects away, and none of yours was due: never a cast landing
            spared = 0, -- of those, the changes a cast was waiting on that unit to be judged by
            -- What kind of change the reports made with details hidden said
            -- they were: an effect added or renewed, one taken away, both at
            -- once, or nothing said. And of those, how many only added
            -- effects and how many only renewed some: stacks are counted by
            -- that.
            kinds = { came = 0, went = 0, both = 0, unsaid = 0, added = 0, renewed = 0 },
        },
        payload = {}, -- what came with the reports, in words: description -> how often
        verdicts = {}, -- how casts made with details hidden came out, by verdict
        spells = {}, -- what the client says about the spells that were cast, with or without an icon
        casts = {}, -- the last casts of spells with an icon, one line each
        learning = {}, -- casts of spells without one, by name: { casts, changed }
        -- Changes that came too late for a cast that is held to the moment it
        -- was announced in, and that had shown nothing: one line each.
        late = {},
        usable = {}, -- what the game answered about using each skill, by spell name
        notes = {},
        refusals = ns.refusals, -- the error each refused aura query raised
        nameReads = ns.nameReads, -- what asking for an effect by name gave, with details hidden
        earlier = earlier,
    }
    ns.db.report = journal
    return journal
end

ns.Journal = Journal

local function Stamp(now)
    local elapsed = max(0, now - sessionStart)
    return format("%d:%04.1f", floor(elapsed / 60), elapsed % 60)
end

local function Remark(text)
    local notes = Journal().notes
    if #notes < REPORT_NOTES then
        notes[#notes + 1] = Stamp(ns.Now()) .. " " .. text
    end
end

local function TokenKind(token)
    if token == "player" or token == "target" or token == "softenemy" then
        return token
    end
    return "plate"
end

--- True when a cast is judged by the changes reported through this kind of
--- unit token. It is from the start. Only a client build that was found to say
--- nothing there while details are hidden is doubted, until it does speak.
local function Trusted(kind)
    return signals[kind].heard > 0 or Kept("doubt")[kind] ~= BuildKey()
end

ns.Trusted = Trusted

--- When a token was last handed to a different unit.
local function Since(token)
    local at = assigned[token]
    if at == nil or everyone > at then
        return everyone
    end
    return at
end

--- A unit token now points at a different unit, or with no token they all may.
--- Whatever it reported before belonged to the unit it has left.
local function Reassigned(token)
    if token then
        assigned[token] = ns.Now()
        changes[token] = nil
        arrivals[token] = nil
        departures[token] = nil
    else
        everyone = ns.Now()
        ns.Wipe(changes)
        ns.Wipe(arrivals)
        ns.Wipe(departures)
    end
end

--- Keeps count of what came with the reports, by Compat's description of it.
local function NotePayload(journal, shape, secret)
    local payload = journal.payload
    local text = (secret and "hidden, " or "open, ") .. shape
    if not payload[text] then
        local shapes = 0
        for _ in pairs(payload) do
            shapes = shapes + 1
        end
        if shapes >= REPORT_SHAPES then
            text = "others"
        end
    end
    payload[text] = (payload[text] or 0) + 1
end

local goneAt, goneOn = nil, {} -- the units that reported an effect going at this very moment

--- A report only took effects away, and none of yours was due. True when a
--- cast was waiting on that unit to be judged: where the kind of a change
--- cannot be told, this report would have passed for the cast landing. A
--- change counts once, however many names the unit reported it under.
local function Spared(token, now)
    local key = ns.Exists(token) and ns.UnitKey(token)
    if not key then
        return false
    end
    if goneAt ~= now then
        goneAt = now
        ns.Wipe(goneOn)
    end
    if goneOn[key] then
        return false
    end
    goneOn[key] = true
    return Tracker:Judging(key, now)
end

--- The client reported that the effects on the unit behind a token changed.
--- `shape` is Compat's description of the details that came with the report:
--- "secret" when they are a value an addon may not look at. `came` is true
--- when the details show that an effect was added or renewed and `went` when
--- they show that one was taken away. Both are nil when they do not say.
--- `fresh` is true when they show that effects were only added and false
--- when they were only renewed, which is what a stack is counted by.
---
--- A cast is judged by a report that could be its effect arriving. One that
--- only took effects away never is: the enemy died, an effect of its own or
--- of another player's ran out, or one of yours did. Where the client does
--- not say which it was, a report at the moment one of your effects was due
--- to run out is put down to that, going by the timing alone.
local function OnAuraChange(token, shape, came, went, fresh)
    local now = ns.Now()
    local journal = Journal()
    local counts = journal.reports
    if token ~= "player" and Since(token) == now then
        -- Handed to another unit this very frame: that is the change reported.
        counts.sameFrame = counts.sameFrame + 1
        return
    end
    local kind = TokenKind(token)
    local count = counts[kind]
    local secret = ns.AurasSecret()
    local readable = shape ~= "secret"
    NotePayload(journal, shape, secret)
    if secret or not readable then
        count.hidden = count.hidden + 1
        if readable then
            count.readable = count.readable + 1
        elseif not secret then
            count.masked = count.masked + 1
        end
        local state = signals[kind]
        state.heard = state.heard + 1
        state.quiet = 0
        if state.heard == 1 then
            Tracker:Heard(kind)
            Kept("proof")[kind] = BuildKey()
            Kept("doubt")[kind] = nil
            ns.Log("the client reports changes through \"%s\" in combat: casts are judged by them", kind)
        end
        local kinds = counts.kinds
        if kinds then
            local said = (came == nil and "unsaid") or (not came and "went") or (went and "both") or "came"
            kinds[said] = (kinds[said] or 0) + 1
            if fresh ~= nil then
                local how = fresh and "added" or "renewed"
                kinds[how] = (kinds[how] or 0) + 1
            end
        end
    else
        count.calm = count.calm + 1
    end

    local unit = Tracker:Expecting(now) and ns.Exists(token) and ns.UnitKey(token)
    if came == false then
        -- Effects went and none came: whatever ended, no cast landed. If one
        -- of yours was due to run out just now, that is it.
        departures[token] = now
        if changes[token] == now and arrivals[token] == true then
            arrivals[token] = nil -- the one that came may have taken the place of the one that went
        end
        if unit and Tracker:Explained(unit, now, token, true) then
            counts.ended = (counts.ended or 0) + 1
            stateDirty = true -- the icon goes green now, not at the next look
        else
            counts.gone = (counts.gone or 0) + 1
            if Spared(token, now) then
                counts.spared = (counts.spared or 0) + 1
            end
        end
        return
    end
    if came == nil then
        -- A change that comes just as one of your own effects on the unit was
        -- due to run out is that, and says nothing about a cast.
        if unit and Tracker:Explained(unit, now, token) then
            counts.ended = (counts.ended or 0) + 1
            stateDirty = true
            return
        end
    elseif went and unit then
        -- Something came and something went in one report. What went may be
        -- an effect of yours that was due: that is noted, and the report is
        -- passed on all the same for what came.
        Tracker:Explained(unit, now, token, true)
    end
    if fresh == true and departures[token] == now then
        -- An effect went and one came, in two reports of one moment: a game
        -- that swaps an effect for a new one when it is renewed looks like
        -- this, so it is not taken for an effect that was not there before.
        fresh = nil
    end
    if changes[token] == now and arrivals[token] ~= fresh then
        arrivals[token] = nil -- two reports at one moment that differ: which was whose is not told
    else
        arrivals[token] = fresh
    end
    changes[token] = now
    if Tracker:HasPending() or Tracker:HasGuests() then
        stateDirty = true
    end
end

local function AuraChanged(token, shape, came, went, fresh)
    Guard(OnAuraChange, token, shape, came, went, fresh)
end

--- True when the unit has another name that has pointed at it for a while and
--- is known to report. A real change is reported under every name a unit goes
--- by, so one reported only under a name it was just given is the handover.
local function HasOlderName(token, key, when)
    for i = 1, #MAIN_TOKENS do
        local other = MAIN_TOKENS[i]
        if other ~= token and listening[other] and signals[other].heard > 0 and when - Since(other) >= SETTLE
            and ns.Exists(other) and ns.UnitKey(other) == key then
            return true
        end
    end
    local plate = ns.PlateTokenFor(token)
    return plate ~= nil and plate ~= token and listening[plate] == true and signals.plate.heard > 0
        and when - Since(plate) >= SETTLE
end

--- Hands the reports that have come in to the tracker. With no cast waiting,
--- of yours or of someone in your group, and none just over that is still
--- listened for, there is nothing they could explain, unless a cast is about
--- to be announced: the recent ones are kept back for that, and the rest are
--- dropped unread.
local function PassOnChanges(now)
    if next(changes) == nil then
        return
    end
    if not Tracker:HasPending() and not Tracker:HasGuests() and not Tracker:HasEchoes() then
        for token, when in pairs(changes) do
            if now - when > RECENT then
                changes[token] = nil
                arrivals[token] = nil
            end
        end
        return
    end
    for token, when in pairs(changes) do
        local fresh = arrivals[token]
        changes[token] = nil
        arrivals[token] = nil
        local key = ns.Exists(token) and ns.UnitKey(token)
        if key then
            if token ~= "player" and when - Since(token) < SETTLE and HasOlderName(token, key, when) then
                local counts = Journal().reports
                counts.handover = counts.handover + 1
            else
                Tracker:Changed(key, when, fresh)
                Tracker:Changed(key .. "+buffs", when, fresh)
            end
        end
    end
end

--- True while a change on the unit would still reach us: it is in sight
--- through the kind of token it was cast on through, or through another kind
--- that has been heard from. (Cast on your target and then switch target, and
--- only its nameplate is left to report on it, if nameplates report at all.)
function ns.InSight(key, via)
    if via and sight[via][key] then
        return true
    end
    for i = 1, #TOKEN_KINDS do
        local kind = TOKEN_KINDS[i]
        if signals[kind].heard > 0 and sight[kind][key] then
            return true
        end
    end
    return false
end

--- Notes on a unit in a cast's snapshot how its effects can be followed.
local function Follow(entry, token)
    if listening[token] then
        local kind = TokenKind(token)
        entry.watched = true
        entry.via = kind
        entry.trusted = Trusted(kind) or nil
    end
    return entry
end

--- Notes in the report what the client says about a spell that was just cast,
--- and what was made of the times in its description: that is what decides
--- whether a spell nothing else is known about gets an icon.
local function NoteSpell(info, kind, source)
    local spells = Journal().spells
    local entry = spells[info.name]
    if not entry then
        entry = {
            id = info.id,
            kind = kind,
            why = source or "none",
            secrecy = ns.SpellAuraSecrecy(info.id) or "unknown", -- 0 never hidden, 1 always, 2 depends
            lasts = info.tooltipRead, -- the words its effect's length was read from
            passed = info.tooltipPassed, -- a time that was not taken for an effect's length
            stacks = info.stacksRead, -- the words the most stacks were read from
            own = info.ownRead, -- the words that show its effect to be each caster's own
            range = info.range, -- how far it goes, and how near its target may be: what is asked of each enemy
            least = info.least,
            around = info.reachRead, -- the words that say how far around you it reaches
        }
        spells[info.name] = entry
    end
    -- How far around you it is taken to reach, for a skill that is judged on
    -- every enemy in the fight.
    entry.reach = Spells:Reach(info)
    if entry.gameStacks == nil then
        -- What the game's own data says of its stacks: false for an effect
        -- that goes on once, and nothing while the client keeps it back.
        entry.gameStacks = Spells:GameStacks(info)
    end
end

local VERDICTS = {
    "seen", "changed", "unsure", "immune", "missed", "nothing new", "silent", "out of reach", "unproven", "unclear",
    "assumed", "unknown",
}

-- Whose effects each kind of unit token reports changes to, for a line in chat.
local WHOSE = {
    player = "you",
    target = "your target",
    softenemy = "the enemy that is targeted for you",
    plate = "the enemies around your target",
}

--- The tracker has finished judging a cast. `tally` counts the units by how
--- they came out, `delay` is how long after the cast one was seen to change,
--- and `unheard` names the kinds of token that reported nothing and never have.
--- `said` holds the game's words for what was done to those units in the
--- moment of the cast, where it said any ("IMMUNE", "MISS", "DODGE").
function ns.Note(cast, tally, delay, unheard, said)
    if unheard and cast.hidden then
        -- A client that reports nothing at all for a run of casts is taken not
        -- to report there. Waiting for it any longer would keep every icon
        -- green however many casts landed.
        local proof, doubt = Kept("proof"), Kept("doubt")
        local build = BuildKey()
        local whose
        for kind in pairs(unheard) do
            local state = signals[kind]
            state.quiet = state.quiet + 1
            local limit = proof[kind] == build and QUIET_PROVEN or QUIET_LIMIT
            if state.quiet >= limit and doubt[kind] ~= build then
                doubt[kind] = build
                proof[kind] = nil
                Remark(format("nothing was reported through \"%s\" after %d casts in a row, so casts are taken to "
                    .. "land there until a change is reported", kind, state.quiet))
                whose = whose or {}
                whose[kind] = true
            end
        end
        if whose then
            local words = {}
            for i = 1, #TOKEN_KINDS do
                if whose[TOKEN_KINDS[i]] then
                    words[#words + 1] = WHOSE[TOKEN_KINDS[i]]
                end
            end
            ns.Print(format("The game has not reported any change to the effects on %s after several of your casts "
                .. "in a row. Until it does, the addon assumes that such a cast has landed.",
                table.concat(words, " or ")))
        end
    end

    local journal = Journal()
    if not cast.tracked then
        -- No icon rides on it: a count is enough.
        local learning = journal.learning
        local line = learning[cast.name]
        if not line then
            line = { casts = 0, changed = 0 }
            learning[cast.name] = line
        end
        line.casts = line.casts + 1
        if delay then
            line.changed = line.changed + 1
        end
        return
    end

    local parts = {}
    for i = 1, #VERDICTS do
        local verdict = VERDICTS[i]
        local units = tally[verdict]
        if units then
            parts[#parts + 1] = units > 1 and (verdict .. " x" .. units) or verdict
            if cast.hidden then
                journal.verdicts[verdict] = (journal.verdicts[verdict] or 0) + units
            end
        end
    end
    local following = "nobody reports on it"
    if cast.forced then
        following = "taken to land on your say-so"
    elseif cast.watched then
        following = cast.trusted and "waited for a report" or "the game is not reporting, taken to land"
    end
    local line = format("%s %s (%s, %s, %s): %s", Stamp(cast.time), cast.name, cast.kind,
        cast.hidden and "hidden" or "open", following, #parts > 0 and table.concat(parts, ", ") or "nobody to judge")
    if delay then
        line = line .. format(", %.2fs after the cast", delay)
    end
    if said then
        -- Whose attack a word was about is not told: a swing of yours in
        -- that moment has its word here as well.
        local words = {}
        for word in pairs(said) do
            words[#words + 1] = word
        end
        table.sort(words)
        line = line .. "; the game said " .. table.concat(words, ", ")
    end
    local casts = journal.casts
    casts[#casts + 1] = line
    if #casts > REPORT_CASTS then
        table.remove(casts, 1)
    end
end

--- A change came on a unit shortly after a cast of yours that is held to the
--- frame it was announced in, and that had shown nothing there. It is not
--- taken for the cast landing. What is kept is when it came and what kind of
--- change it was, so that it can be read afterwards whether the game ever
--- shows a landing that late: these would then come at about the same delay
--- each time, and add an effect or renew one as the cast would have.
function ns.NoteLate(cast, delay, fresh)
    local journal = Journal()
    local late = journal.late
    if type(late) ~= "table" then
        late = {}
        journal.late = late
    end
    late[#late + 1] = format("%s %s: nothing in the moment of the cast, then a change %.2fs after it%s",
        Stamp(cast.time), cast.name, delay,
        (fresh == true and " (an effect added)") or (fresh == false and " (an effect renewed)") or "")
    if #late > REPORT_NOTES then
        table.remove(late, 1)
    end
end

listening.player = ns.WatchAuras("player", AuraChanged) or nil
for i = 1, #MAIN_TOKENS do
    listening[MAIN_TOKENS[i]] = ns.WatchAuras(MAIN_TOKENS[i], AuraChanged) or nil
end
for i = 1, #plateTokens do
    listening[plateTokens[i]] = ns.WatchAuras(plateTokens[i], AuraChanged) or nil
end
ns.listening = listening

--------------------------------------------------------------------------------
-- Immune enemies
--
-- An enemy that is immune to a spell's effect can never have it, and so is no
-- reason to cast: it is left out when the spell is judged. Nothing an addon
-- may read says beforehand what a creature is immune to. What the game does
-- say, in a fight too, is a word for what an attack or a spell just did to a
-- unit, and "immune" is one of them (see ns.WatchCombat). Said of an enemy in
-- the very moment a cast of yours went to it, with nothing to show for the
-- cast and nothing else said that could be its answer, that is taken as the
-- cast's answer (see "Immune units" in Tracker.lua for what is ruled out):
--
--   * that enemy is taken to be immune to the spell for as long as it is
--     remembered, unless it looks to be behind a shield, which turns your
--     ordinary hits away as well: then until a hit lands on it again
--     (Tracker.lua);
--   * its kind of creature is kept with the settings, and counted on once
--     the game has said so twice of that kind, or once when you are on your
--     own and your hits landed on the enemy right before and right after
--     (Spells.lua);
--   * an enemy, or a kind, that is seen to carry the effect is not immune,
--     whatever was said, and what was kept of it is dropped.
--
-- Nothing else passes for immunity. A cast that showed nothing may as well
-- have missed, and several in a row may as well have missed in a row.
--
-- The game's word for a hit that landed, "WOUND", is passed on as well: it
-- is what tells a lasting immunity from a shield.
--
-- What the game said is counted in the saved report, so that it can be read
-- there what a real client sends: whether it says anything of enemies in a
-- fight, whether the word can be read, and whether an "immune" comes in the
-- moment of the cast it is about.
--------------------------------------------------------------------------------

local KINDS_KEPT = 200 -- units whose kind is remembered before the list starts over
local WORD_KINDS = 16 -- different words of the game's kept apart in the saved report
-- The game's words for an attack that did something: a hit, a heal, and
-- power given. Every other word is for one that left nothing behind.
local DID = { WOUND = true, HEAL = true, ENERGIZE = true }

local kindOf = {} -- unit key -> what kind of creature it is (see ns.UnitKind), false while that is not told
local kindName = {} -- kind -> the creature's name, for showing
local kindsKept = 0

--- What the game said attacks did to enemies, for the saved report.
--- `listening` is how many unit tokens it is listened for through: none on a
--- client that will not allow it. Then how often something was heard
--- through each kind of token (`heard`), how often of those with effect
--- details hidden (`hidden`) and how often the word was kept secret
--- (`unread`). Then the words themselves with how often each came, a line
--- for every "immune" with what it was taken for, and a line for everything
--- learned from them. `kinds` counts the enemies met by how the game named
--- their kind of creature, with details open (`calm`) and hidden: by its
--- number, by its name only, or not at all. What is learned of an enemy
--- holds for its kind only where the game names one.
local function Said()
    local journal = Journal()
    local said = journal.combat
    if type(said) ~= "table" then
        local listening = 0
        for _ in pairs(ns.saying) do
            listening = listening + 1
        end
        said = {
            listening = listening,
            target = { heard = 0, hidden = 0, unread = 0 },
            softenemy = { heard = 0, hidden = 0, unread = 0 },
            plate = { heard = 0, hidden = 0, unread = 0 },
            words = {},
            immune = {},
            learned = {},
            kinds = {
                calm = { number = 0, name = 0, none = 0 },
                hidden = { number = 0, name = 0, none = 0 },
            },
        }
        journal.combat = said
    end
    return said
end

local function Keep(lines, text)
    lines[#lines + 1] = text
    if #lines > REPORT_NOTES then
        table.remove(lines, 1)
    end
end

--- Finds out what kind of creature a unit is, once: what is learned of one
--- holds for the others of its kind.
local function Know(unit, key)
    local kind = kindOf[key]
    if kind == false or (kind and kindName[kind]) then
        return
    end
    local found, shown = ns.UnitKind(unit, key)
    if kind == nil then
        if kindsKept >= KINDS_KEPT then
            ns.Wipe(kindOf) -- the ones still about are learned again at the next look
            kindsKept = 0
        end
        kindsKept = kindsKept + 1
        kindOf[key] = found or false
        if found or shown ~= "player" then
            local kinds = Said().kinds
            local count = ns.AurasSecret() and kinds.hidden or kinds.calm
            local how = (not found and "none") or (found:find("^#") and "number") or "name"
            count[how] = count[how] + 1
        end
    end
    if found and shown and not kindName[found] then
        kindName[found] = shown
        Spells:NameKind(found, shown)
    end
end

--- The creature behind a unit key, in words for a line of text.
local function Named(key)
    local kind = kindOf[key]
    if not kind then
        return key:find("^Player%-") and "a player" or "an enemy the game does not name"
    end
    return kindName[kind] or ("creature " .. kind)
end

ns.EnemyName = Named

--- Is the enemy behind this key immune to the spell, as far as is known: by
--- the game's word of it, or of its kind of creature?
local function ImmuneTo(key, name, now)
    if Tracker:IsImmune(key, name, now) then
        return true
    end
    local kind = kindOf[key]
    return kind and Spells:KindImmune(name, kind) or false
end

--- The game said what an attack or a spell did to the unit behind a token.
--- `word` is nil when the client keeps it secret.
local function OnCombat(token, word)
    if not ns.db.enabled then
        return
    end
    local said = Said()
    local count = said[TokenKind(token)]
    count.heard = count.heard + 1
    if ns.AurasSecret() then
        count.hidden = count.hidden + 1
    end
    if not word then
        count.unread = count.unread + 1
        return
    end
    local words = said.words
    local kept = word
    if not words[kept] then
        local kinds = 0
        for _ in pairs(words) do
            kinds = kinds + 1
        end
        if kinds >= WORD_KINDS then
            kept = "others"
        end
    end
    words[kept] = (words[kept] or 0) + 1
    if DID[word] and word ~= "WOUND" then
        return -- says nothing of a cast that left nothing
    end
    if not Attackable(token) then
        return -- no enemy: nothing of yours was turned away there
    end
    if word == "WOUND" then
        Tracker:Hit(ns.UnitKey(token), ns.Now()) -- it takes hits: no shield is in the way
    else
        Tracker:Said(ns.UnitKey(token), ns.Now(), word)
    end
end

local function CombatSaid(token, word)
    Guard(OnCombat, token, word)
end

--- What became of an "immune" the game said of an enemy, for the saved
--- report. `how` is "counted" when it was taken as the answer to `cast`
--- (`early` when it was said before the cast was announced), "shown" when
--- the enemy's effects changed in that same moment, as if the cast had
--- landed, "mixed" when the game also said in that moment that an attack
--- missed or was turned away there, "two" when two casts of yours were in
--- that moment, and "nobody" with no cast of yours in it: `cast` is then
--- your last one at that unit, if there was one lately.
function ns.NoteRefusal(how, cast, when, early)
    local text
    if how == "counted" then
        text = format("in the moment of %s, said just %s the cast was announced: taken as its answer", cast.name,
            early and "before" or "after")
    elseif how == "shown" then
        text = format("in the moment of %s, which was seen to land there just then: left open", cast.name)
    elseif how == "mixed" then
        text = format("in the moment of %s, when another attack was turned away there too: left open", cast.name)
    elseif how == "two" then
        text = "in the moment of two casts of yours at that enemy: left open"
    elseif cast then
        local gap = when - cast.time
        text = format("%.2fs %s %s, too far from it to be its answer", gap < 0 and -gap or gap,
            gap < 0 and "before" or "after", cast.name)
    else
        text = "with no cast of yours at that enemy"
    end
    Keep(Said().immune, Stamp(when) .. " " .. text)
end

--- A cast of yours was answered with "immune". `how` is what the tracker
--- made of it for that one enemy: "once", "again", "twice" or "passing" (see
--- Refuse in Tracker.lua). `shielded` is true when the enemy looks to be
--- behind a shield, which is not held against its kind of creature, and
--- `struck` when a hit landed on it in the very moment of the word, which
--- settles that it is none. Its kind is told the rest.
function ns.NoteImmune(name, key, when, how, shielded, struck)
    local kind = kindOf[key] or nil
    local text
    if how == "again" then
        text = "said again of the same enemy"
    elseif shielded then
        text = "other attacks were turned away there too with no hit landing in between, so this may be a shield: "
            .. "that enemy is left out until a hit lands on it again, and nothing is held against its kind"
    else
        local known = kind and Spells:KindImmune(name, kind)
        local sure, seen
        if kind then
            sure, seen = Spells:SawImmune(name, kind, kindName[kind], how == "passing")
        end
        if how == "passing" then
            text = "it has carried the effect before, so this will pass: nothing kept"
        elseif sure == "passing" then
            Tracker:Pardon(key, name)
            text = "its kind has carried the effect before, so this will pass: nothing kept"
        elseif known then
            text = nil -- nothing new: its kind was counted on as immune already
        elseif not kind then
            text = key:find("^Player%-") and (how == "twice" and "that one enemy is immune from now on"
                or "that one enemy is immune for now") or "that one enemy is left out from now on"
        elseif sure then
            text = format("its kind is counted on as immune from now on (said %d times)", seen)
        else
            text = "that enemy is left out from now on, and its kind once this is proven or said of the kind again"
        end
        if struck and sure ~= "passing" and how ~= "passing" then
            if text then
                Keep(Said().learned, format("%s %s on %s: %s", Stamp(when), name, Named(key), text))
                text = nil
            end
            ns.NoteProven(name, key, when, true)
        end
    end
    if text then
        Keep(Said().learned, format("%s %s on %s: %s", Stamp(when), name, Named(key), text))
    end
end

--- An enemy that turned a spell of yours away took your hits all the same:
--- one landed right before the game's word and one right after (or, with
--- `struck`, in the very moment of it), and nothing else was turned away in
--- between. No shield comes and goes in so short a time, so it is the spell
--- the enemy is immune to. On your own, where every word the game says of
--- your enemy is about an attack of yours, that is proof enough for its kind
--- of creature. In a group it still takes the game saying so twice.
function ns.NoteProven(name, key, when, struck)
    local kind = kindOf[key]
    if not kind or ns.GroupState() ~= "alone" then
        return
    end
    if Spells:ProveImmune(name, kind) then
        Keep(Said().learned, format("%s %s on %s: %s, so it is behind no shield: its kind is counted on as immune "
            .. "from now on", Stamp(when), name, Named(key),
            struck and "a hit landed on it in that very moment" or "your hits landed on it right before and right after"))
        stateDirty = true
    end
end

--- An enemy that turned a spell of yours away turned something else away as
--- well before any hit landed on it: it looks to be behind a shield. With
--- `counted`, its kind was told of an occasion that is now taken back.
function ns.NoteShield(name, key, when, counted)
    local kind = kindOf[key]
    if counted and kind then
        Spells:Unsee(name, kind)
    end
    Keep(Said().learned, format("%s %s on %s: something else was turned away there before a hit landed, so this "
        .. "may be a shield: left out until a hit lands on it again, and not held against its kind",
        Stamp(when), name, Named(key)))
    stateDirty = true
end

--- A hit landed on an enemy that was taken to be behind a shield: the
--- shield is gone, and the enemy is judged like any other again.
function ns.NoteShieldGone(name, key, when)
    Keep(Said().learned, format("%s %s on %s: a hit landed on it again, so the shield is gone: no longer left out",
        Stamp(when), name, Named(key)))
    stateDirty = true
end

--- An enemy was seen to carry a spell's effect: its kind is not immune to
--- it by nature, whatever the game said of it before.
function ns.NoteTaken(name, key)
    local kind = kindOf[key]
    if kind and Spells:Takes(name, kind) then
        Keep(Said().learned, format("%s %s on %s: seen to carry it after all, so its kind is not counted as immune",
            Stamp(ns.Now()), name, Named(key)))
        stateDirty = true
    end
end

--- Forgets what was learned of immune enemies, for one spell or for all of
--- them with no name given. Returns how many kinds of creature were dropped.
function ns.ForgetImmune(name)
    local dropped = Spells:ForgetImmune(name)
    Tracker:ForgetImmune(name)
    stateDirty = true
    return dropped
end

--- Marks the kind of creature you have targeted as immune to a spell, on
--- your say-so. Returns its name. Or nil and why not: "target" when you
--- have no enemy targeted, "player" when it is a player, who is no kind of
--- creature, and "hidden" when the game will not say what kind it is.
function ns.MarkImmune(name)
    local unit = Attackable("target") and "target" or nil
    if not unit then
        return nil, "target"
    end
    local key = ns.UnitKey(unit)
    local kind, shown = ns.UnitKind(unit, key)
    if not kind then
        return nil, shown
    end
    Spells:SetImmune(name, kind, shown)
    stateDirty = true
    return shown or ("creature " .. kind)
end

-- The same unit tokens that are listened to for changes: your target, your
-- soft target and the nameplates.
local saying = {}
for i = 1, #MAIN_TOKENS do
    saying[MAIN_TOKENS[i]] = ns.WatchCombat(MAIN_TOKENS[i], CombatSaid) or nil
end
for i = 1, #plateTokens do
    saying[plateTokens[i]] = ns.WatchCombat(plateTokens[i], CombatSaid) or nil
end
ns.saying = saying

-- What the client allowed the last time we looked, for /se debug: at an enemy's
-- debuffs, and under `buffs` at your own buffs.
local probe = { open = {}, hidden = {}, buffs = { open = {}, hidden = {} } }
ns.probe = probe

local combatEpoch = 0 -- goes up every time combat starts or ends

-- Counting effects can be refused outright in combat. Stop asking for a while
-- after a run of refusals rather than failing the same call every pass.
--
-- While aura details are hidden, an answer of "none" could be the truth or could
-- be the client hiding them. It is only believed once the same fight has shown
-- at least one effect of ours through the same call: `trusted` is that fight.
--
-- Debuffs on enemies and buffs on you are kept apart, because the client may
-- well allow one and not the other.
local sampling = {
    debuff = { failures = 0, blockedUntil = 0, trusted = -1 },
    buff = { failures = 0, blockedUntil = 0, trusted = -1 },
}
local lastAnswer = "none" -- what the last count looked like: "ids", "count" or "none"

--- Counts your effects of one kind on a unit: { n, ids } or nil when that
--- cannot be relied on.
local function Sample(unit, now, calm, kind)
    lastAnswer = "none"
    local state = sampling[kind]
    if now < state.blockedUntil then
        return nil
    end
    local sample = ns.SampleAuras(unit, kind)
    if not sample then
        state.failures = state.failures + 1
        if state.failures >= 6 then
            state.failures = 0
            state.blockedUntil = now + 5
        end
        return nil
    end
    state.failures = 0
    lastAnswer = sample.ids and "ids" or "count"
    if not calm then
        if sample.n > 0 then
            state.trusted = combatEpoch
        elseif state.trusted ~= combatEpoch then
            return nil
        end
    end
    return sample
end

local SELF_RESCAN = 2 -- seconds between looks at your buffs when it is only to learn from them
local LEARN_DELAY = 0.3 -- seconds after a cast before looking for a buff it may have left on you

local seen = {} -- unit key -> sample, or false when unreadable, for units looked at this pass
local direct = {} -- unit key -> true for units whose effects were also listed by name this pass
local engagedKeys = {} -- unit key -> true for enemies in the fight
local fight = {} -- the enemies an area spell is judged against: { unit, key }
local inFight = {}
local fightSize = 0
local states = {} -- spell name -> its state this pass
local sweepWanted = false -- an area spell needs the nameplates walked
local buffsWanted = true -- a buff spell needs your buffs looked at every pass
local friendWanted = true -- and one of them can be cast on the friend you have targeted
local learnWanted = true -- a spell on the bars is not known to leave a buff on you, and might
local lastSelfLook = -100
local nameReadable = { debuff = {}, buff = {} } -- spell name -> the fight in which its effect was read by name
local primaryUnit, primaryKey
local friendUnit, friendKey
local playerKey

--- True for a spell on the bars whose effect, of this kind, a unit carries
--- only once whoever put it there: another player's copy then counts.
local function AnyonesCounts(name, kind)
    local info = barInfo[name]
    if not info or not Spells:Shared(info) then
        return false
    end
    local _, _, _, _, own = Spells:Tracking(info)
    return own == kind
end

local rosterHeard = false -- the game tells when the people in your group change

--- Another player's copy of a spell's effect was read off a unit. How long it
--- lasts is kept for the casts of theirs that can only be heard (see "How
--- long another player's copy lasts" in Spells.lua), with who put it there
--- where the game says.
local function NoteCopy(name, aura)
    -- Who put it there is only kept where the game tells when the group
    -- changes: a party name is handed on to whoever joins next.
    local token = rosterHeard and aura.source and ns.GroupToken(aura.source)
    local news = Spells:LearnCopy(name, aura.duration, token)
    if news then
        ns.NoteOthers("read")
        if news == "member" then
            ns.NoteOthers("sourced")
        end
    end
end

--- Looks at a unit once per pass: counts your effects of one kind on it and,
--- while the client shows them, reads them by name. `note` is the part of the
--- probe to fill in, if this look is one /se debug reports on.
local function Look(unit, now, calm, kind, note)
    local key = KeyOf(unit, kind)
    if listening[unit] then
        sight[TokenKind(unit)][key] = true
    end
    if seen[key] ~= nil then
        return key
    end
    if kind == "debuff" then
        Know(unit, key)
    end
    local sample = Sample(unit, now, calm, kind)
    local answer = lastAnswer
    seen[key] = sample or false
    local listed = false
    if calm then
        local found, complete = ns.ReadAuras(unit, kind)
        if found then
            listed = true
            direct[key] = complete or nil
            -- Other players' effects as well, for the spells whose effect a
            -- unit carries only once: theirs is then as good as yours.
            local everyone = ns.ReadAuras(unit, kind, true)
            if everyone then
                for name, aura in pairs(everyone) do
                    if not found[name] and AnyonesCounts(name, kind) then
                        aura.theirs = true
                        found[name] = aura
                        NoteCopy(name, aura)
                    end
                end
            end
            Tracker:Sync(key, found, barNames, now, kind, everyone ~= nil)
        end
    end
    if note then
        note.time = now
        note.sample = answer
        note.trusted = calm or sampling[kind].trusted == combatEpoch
        note.direct = listed
        note.identity = ns.IdentityReadable(unit)
    end
    return key
end

--- Whom a skill would go to, for the question of whether it reaches. An
--- attack goes to the enemy even when the effect it is tracked for lands on
--- you. A buff goes to the friend you have targeted, if it can, and to you
--- otherwise. No enemy to go to is nil.
local function AimOf(info, kind)
    if kind == "buff" and info.harmful ~= true then
        return CastOnFriends(info) and friendUnit or "player"
    end
    return primaryUnit
end

local function AddToFight(unit, key)
    if inFight[key] then
        return
    end
    inFight[key] = true
    fightSize = fightSize + 1
    local enemy = fight[fightSize]
    if not enemy then
        enemy = {}
        fight[fightSize] = enemy
    end
    enemy.unit, enemy.key = unit, key
end

--------------------------------------------------------------------------------
-- The game's own tracker
--
-- In a fight nothing an addon may read says which effects an enemy carries
-- (see Tracker.lua). The game knows, and one part of its own interface shows
-- it: the cooldown tracker, which can list a skill among its tracked effects
-- and then keeps watch on your effect of that skill on you and on your
-- target (see "The game's own tracker" in Compat.lua). What it shows is read
-- off the effects themselves. So it is asked about every skill that is
-- judged on your target or on you, and its answer stands above the books.
--
-- It can only answer for a skill it has an item for, while it is on screen,
-- and for your target and you: not for the other enemies an area skill hits.
--
-- "There" is believed whenever it is said: the item found your effect on the
-- unit. "None there" is only believed of an item that has shown this skill's
-- effect before, in this session: one that lists the skill under a spell
-- number its effect does not carry would say "none" for ever. And for a
-- skill whose effect a unit carries only once, whoever casts it, "none of
-- yours" says less while you are in a group: someone else's may be there in
-- its place. It still tells of a cast of yours that was not known to have
-- landed, and nothing more (see Tracker:Shown).
--
-- "None there" just after a cast was seen to land, with nothing said against
-- it, is two answers that each deserve belief. The effect is left in doubt
-- then, and the icon says so. The second time running that happens with a
-- skill it is the tracker that is no longer believed of it, until it next
-- shows the effect.
--
-- What it said and what that changed in the books is kept in the saved
-- report by skill, with what the game's tracker lists at all. On a client
-- nobody has looked at yet, that is how it is found out afterwards.
--
-- It is asked from the pass that runs every frame and from nowhere else:
-- inside the handling of an event it may not have heard of that event yet.
--------------------------------------------------------------------------------
do
    local proven = {} -- skill -> true once the tracker has shown its effect in this session
    local clashes = {} -- skill -> how often running it said "none" of a landing that had just been seen
    local CLASHES = 2

    --- The report's line for a skill, made on first use: where the game's
    --- data lists it, and which of the tracker's items is on screen for it.
    local function Line(name)
        local journal = Journal()
        local tracker = journal.tracker
        if type(tracker) ~= "table" then
            tracker = { game = ns.TrackerProbe(), skills = {} }
            journal.tracker = tracker
        end
        local line = tracker.skills[name]
        if not line then
            line = { listed = ns.TrackerLists(name) or "nowhere" }
            tracker.skills[name] = line
        end
        local item, loose = ns.TrackerItem(name)
        if item then
            line.item = loose and (item .. ", which also lights for " .. loose) or item
        end
        return line
    end

    local function Count(line, what)
        line[what] = (line[what] or 0) + 1
    end

    --- Asks the game's own tracker about a skill on a unit, and brings the
    --- books in line with an answer that can be believed.
    function ns.AskTracker(unit, key, name, kind, anyone, now)
        local which
        if kind == "buff" then
            which = unit == "player" and "player" or nil
        elseif unit == "target" or ns.SameUnit(unit, "target") == true then
            which = "target"
        end
        if not which then
            return -- it watches nobody else
        end
        local shown, why = ns.GameTracker(name, which)
        local line = Line(name)
        if shown == nil then
            Count(line, why or "unread")
            return
        end
        if shown then
            Count(line, "there")
            proven[name] = true
            clashes[name] = nil
        else
            Count(line, "none")
            if not proven[name] then
                Count(line, "unproven")
                return
            end
        end
        local info = barInfo[name]
        local lasts, shared
        if shown then
            if info then
                local _, _, duration = Spells:Tracking(info)
                lasts = duration
            end
        elseif anyone and ns.GroupState() ~= "alone" then
            -- Another player's copy may be there in place of yours, unless
            -- it is a buff nobody else can put on you.
            shared = not (kind == "buff" and info and info.selfOnly == true)
        end
        local did = Tracker:Shown(key, name, shown, now, lasts, shared)
        if did == "early" then
            ns.MarkDirty() -- asked again as soon as the moment of the cast is over
            return
        end
        if did then
            Count(line, did)
        end
        if did == "clashed" then
            -- It shows none of a cast that had just been seen to land.
            clashes[name] = (clashes[name] or 0) + 1
            if clashes[name] >= CLASHES then
                -- The second time running: it is the tracker that is not
                -- believed of this skill, and the landing stands.
                proven[name] = nil
                clashes[name] = nil
                Count(line, "doubted")
            else
                Tracker:Unsettle(key, name, now)
            end
        end
    end

    --- Whether the tracker's "none" is believed of a skill right now, for
    --- /se debug.
    function ns.TrackerProven(name)
        return proven[name] == true
    end
end

--- Does this unit have the spell's effect? While details are hidden, an effect
--- the client still shows by name is read directly and overrides the books,
--- and so does what the game's own tracker shows of it.
--- With `anyone` set, another player's effect of that name counts as well.
local function HasEffect(unit, key, name, now, calm, kind, anyone)
    if not calm then
        local readable = nameReadable[kind]
        local aura = ns.ReadAuraByName(unit, name, kind)
        if anyone and not aura then
            -- None of yours that can be seen. What is said of everyone's
            -- stands then: someone else's copy, nothing, or no answer.
            local theirs = ns.ReadAuraByName(unit, name, kind, true)
            if theirs then
                theirs.theirs = true
                NoteCopy(name, theirs)
            end
            if theirs or aura == false then
                aura = theirs
            end
        end
        if aura then
            Tracker:Observe(key, name, aura, now)
            Spells:LearnExact(name, not aura.theirs and aura.duration or nil, kind)
            Spells:LearnStacks(name, aura.stacks)
            readable[name] = combatEpoch
            if kind == "buff" then
                probe.buffs.hidden.byName = true
            else
                probe.hidden.byName = true
            end
        elseif aura == false and readable[name] == combatEpoch then
            Tracker:Absent(key, name)
        end
        if not aura then
            ns.AskTracker(unit, key, name, kind, anyone, now)
        end
    end
    return Tracker:Has(key, name, now)
end

--- Whether a unit carries a spell's effect so that casting again changes
--- nothing there: "all" when it does, "none" when it does not. An effect
--- that stacks (`most` is how many times over it goes) only counts once it
--- is on in full: below that another cast still adds a stack.
---
--- "unsure" when that cannot be told: the books hold the effect in doubt
--- (see "Two answers at once" in Tracker.lua), and the answer would be the
--- other one if the doubt went the other way.
local function Carries(unit, key, name, now, calm, kind, most, anyone)
    local carries = "none"
    if HasEffect(unit, key, name, now, calm, kind, anyone)
        and not (most and Tracker:Stacks(key, name, now) < most) then
        carries = "all"
    end
    local other = Tracker:Doubt(key, name, now)
    if other ~= nil then
        local otherwise = (other > 0 and not (most and other < most)) and "all" or "none"
        if otherwise ~= carries then
            return "unsure"
        end
    end
    return carries
end

--------------------------------------------------------------------------------
-- Enemies out of reach
--
-- A skill that hits every enemy around you does nothing for one that stands
-- too far away: such an enemy is no reason to use it, and none not to. The
-- game does not tell an addon how far away a unit is. It does say whether a
-- unit is within the range of each of your skills, the answer that turns a
-- button's key red. So every skill on the bars that goes to an enemy is
-- asked about each enemy in the fight, and what they say is put together:
-- Rend can reach it (within 5 yards), or Charge can (8 to 25), or neither
-- can and Intimidating Shout cannot either (beyond 10, so beyond 25).
--
-- An enemy is only left out when that proves it to be further off than the
-- skill reaches. One that nothing is known of counts as before, and so does
-- every enemy while the skill's own reach is not known (see Spells:Reach).
--
-- Three things could make such a proof wrong, and each is watched for:
--
--   * A client that answers about your target whoever it is asked about. So
--     what a range says of anybody but your target is only believed once it
--     has given two enemies different answers in the same moment.
--   * A skill that cannot be used on some enemy at all, and says "out of
--     range" of it. One that says so of an enemy the others put inside its
--     range is not asked again.
--   * A skill that reaches further than thought. A cast that shows on an
--     enemy taken to be out of reach is noted, and from the second one on
--     the skill is taken to reach past where that enemy stood
--     (Spells:Outreached).
--------------------------------------------------------------------------------

-- What the rest of this file needs of it: Reach.Ask starts a round of asking,
-- Reach.Beyond says whether an enemy is out of a skill's reach, Reach.Leaves
-- keeps count for the saved report, and Reach.nobody holds, by name, the
-- area skills that have every enemy out of their reach in this pass.
local Reach = { nobody = {} }

do
    local tinsert, tremove = table.insert, table.remove
    local MELEE = 5 -- yards: what a skill reaches that has no range of its own and answers all the same
    local PROBE_SKILLS = 2 -- skills of one range asked about a unit before that range is given up for it, once one of them is known to answer

    local probes = {} -- the ranges the skills on the bars have: { least, most, name, proven, heard, [1..n] = bar entry }
    local probesAt -- the reading of the bars they were listed from
    local proven = {} -- range name -> true once it gave two enemies different answers at once: the game heeds whom it is asked about
    local liars = {} -- spell id -> true for a skill that said "out of range" of an enemy inside its range
    local heard = {} -- spell id -> true for a skill the game has answered about: asked before the others of its range
    local reachLo = {} -- unit key -> how many yards off it is at the least, this pass; false when not known
    local reachHi = {} -- unit key -> how many yards off it is at the most, this pass, where that is known
    local probeYes, probeNo = {}, {} -- probe -> a unit that got that answer in this round of asking
    local answers, askedOf = {}, {} -- scratch: what each probe said of the unit being asked about, and which skill said it
    local leftOut = {} -- spell name -> true while an enemy is left out of its count

    --- The saved report's part on reach: how often the game said yes, no or
    --- nothing when asked whether an enemy is within a skill's range, by the
    --- kind of unit token asked about; the ranges whose answers about enemies
    --- other than your target were proven; how often each skill began leaving
    --- an enemy out; and a line for everything out of the ordinary.
    local function ReachReport()
        local journal = Journal()
        local reach = journal.reach
        if type(reach) ~= "table" then
            reach = {
                target = { yes = 0, no = 0, silent = 0 },
                softenemy = { yes = 0, no = 0, silent = 0 },
                plate = { yes = 0, no = 0, silent = 0 },
                proven = {},
                left = {},
                notes = {},
            }
            journal.reach = reach
        end
        return reach
    end

    --- Lists the ranges of the skills on the bars that go to an enemy, each with
    --- the buttons to ask. A skill that hits all around you has no range of
    --- its own and says nothing when asked: the ones that have answered before
    --- come first, so that such a skill does not stand in the way of one that
    --- does answer.
    local function ListProbes()
        probesAt = lastScan
        for i = #probes, 1, -1 do
            probes[i] = nil
        end
        local byRange = {}
        for i = 1, #entries do
            local entry = entries[i]
            local info = entry.info
            -- A skill the game calls harmful, or one it calls neither harmful
            -- nor helpful that has a range of its own (a shout that needs a
            -- target, say).
            if info and entry.slot and type(info.range) == "number" and not liars[info.id]
                and (info.harmful == true or (info.helpful ~= true and info.selfOnly ~= true and info.range > 0)) then
                local most = info.range > 0 and info.range or MELEE
                local least = type(info.least) == "number" and info.least or 0
                if least < most then
                    local name = least .. "-" .. most
                    local probe = byRange[name]
                    if not probe then
                        probe = { least = least, most = most, name = name, proven = proven[name] }
                        byRange[name] = probe
                        probes[#probes + 1] = probe
                    end
                    local listed = false
                    for c = 1, #probe do
                        listed = listed or probe[c].info == info -- the same skill on two buttons
                    end
                    if not listed then
                        if heard[info.id] then
                            probe.heard = (probe.heard or 0) + 1
                            tinsert(probe, probe.heard, entry)
                        else
                            probe[#probe + 1] = entry
                        end
                    end
                end
            end
        end
    end

    --- Starts a round of asking: all of it happens in one moment, so a range
    --- that gives two enemies different answers in it shows that the game
    --- heeds whom it is asked about. With `pass`, a pass over the fight starts as well, and what
    --- was worked out in the last one is dropped.
    function Reach.Ask(pass)
        ns.Wipe(probeYes)
        ns.Wipe(probeNo)
        if pass then
            ns.Wipe(reachLo)
            ns.Wipe(reachHi)
            ns.Wipe(Reach.nobody)
        end
    end

    --- How many yards off the unit behind a token is at the least, as far as the
    --- ranges of your skills tell. Nil when nothing is known of it and when what
    --- is said does not add up. Of anybody but your target, a range is only
    --- heeded once it is proven that the game heeds whom it is asked about.
    local function FarAtLeast(unit, key)
        local known = reachLo[key]
        if known ~= nil then
            return known or nil
        end
        if probesAt ~= lastScan then
            ListProbes()
        end
        local report = ReachReport()
        local tally = report[TokenKind(unit)] or report.plate
        local lo, hi = 0, math.huge
        local any = false
        local mine = unit == "target"
        for i = 1, #probes do
            local probe = probes[i]
            local answer, asked
            -- Every skill of this range is tried until one of them has
            -- answered; from then on the first few are enough.
            for c = 1, probe.heard and min(#probe, max(PROBE_SKILLS, probe.heard)) or #probe do
                asked = probe[c]
                answer = ns.UnitInReach(asked.slot, asked.info.id, unit)
                if answer ~= nil then
                    if not heard[asked.info.id] then
                        heard[asked.info.id] = true
                        probe.heard = (probe.heard or 0) + 1
                        tremove(probe, c)
                        tinsert(probe, probe.heard, asked)
                    end
                    break
                end
            end
            if answer == nil then
                tally.silent = tally.silent + 1
            else
                local same, other = probeYes, probeNo
                if answer then
                    tally.yes = tally.yes + 1
                else
                    tally.no = tally.no + 1
                    same, other = probeNo, probeYes
                end
                same[probe] = same[probe] or key
                if not probe.proven and other[probe] and other[probe] ~= key then
                    probe.proven = true
                    proven[probe.name] = true
                    if type(report.proven) == "table" then
                        report.proven[probe.name] = true
                    end
                end
                if not (mine or probe.proven) then
                    answer = nil -- not believed of anybody but your target yet
                elseif answer then
                    -- Within this skill's range: no nearer than its shortest, no further than its longest.
                    any = true
                    lo, hi = max(lo, probe.least), min(hi, probe.most)
                else
                    any = true
                end
            end
            answers[i], askedOf[i] = answer, asked
        end
        for i = #probes + 1, #answers do
            answers[i], askedOf[i] = nil, nil
        end
        local result = false
        if any and lo <= hi then
            for i = 1, #probes do
                local probe = probes[i]
                if answers[i] == false and lo >= probe.least and hi <= probe.most then
                    -- Out of range, of an enemy the others put inside its range:
                    -- it cannot be used on that enemy at all, or it does not
                    -- say what it is taken to say. Not asked again.
                    answers[i] = nil
                    local liar = askedOf[i].info
                    liars[liar.id] = true
                    probesAt = nil
                    Keep(report.notes, format("%s %s said an enemy was out of its range that your other skills put "
                        .. "inside it: not asked again", Stamp(ns.Now()), liar.name))
                end
            end
            -- What a "no" adds: the enemy is beyond that skill's longest
            -- range, once it is known not to be too close for the skill. One
            -- such answer can settle what another one means, so they are gone
            -- over until nothing more comes of it.
            local changed = true
            while changed do
                changed = false
                for i = 1, #probes do
                    local probe = probes[i]
                    if answers[i] == false and lo >= probe.least and probe.most > lo then
                        lo, changed = probe.most, true
                    end
                end
            end
            if lo <= hi then
                result = lo
            end
        end
        reachLo[key] = result
        reachHi[key] = result and hi or nil
        return result or nil
    end

    --- How far off an enemy is at the least, when that is further than a skill
    --- reaching `reach` yards around you gets. Nil for one it may get to.
    function Reach.Beyond(unit, key, reach)
        local lo = FarAtLeast(unit, key)
        return lo and lo >= reach and lo or nil
    end

    --- Keeps in the saved report how often a skill began leaving an enemy out
    --- of its count. `some` is whether it does so now.
    function Reach.Leaves(name, some)
        if some and not leftOut[name] then
            local left = ReachReport().left
            left[name] = (left[name] or 0) + 1
        end
        leftOut[name] = some or nil
    end

    --- A cast of an area skill showed on an enemy that was taken to be at least
    --- `far` yards away, and so out of its reach (the tracker says so when it has
    --- judged the cast).
    function ns.NoteReached(name, far)
        local reach = Spells:Outreached(name, far)
        Keep(ReachReport().notes, format("%s %s showed on an enemy taken to be at least %d yards away: %s",
            Stamp(ns.Now()), name, far, reach and format("it is taken to reach %d yards from now on", reach)
                or "noted, in case it happens again"))
        stateDirty = true
    end

    --- What is known of reach, for /se debug: the ranges the skills on the bars
    --- give to ask about, each as { least, most, proven = true once its answers
    --- about enemies other than your target are believed, [1..n] = bar entry },
    --- and the saved report's counts.
    function ns.ReachProbe()
        if probesAt ~= lastScan then
            ListProbes()
        end
        return probes, ReachReport()
    end

    ----------------------------------------------------------------------------
    -- With no nameplates to go by
    --
    -- The enemies around you are read from their nameplates. When the game
    -- shows none, all that is left are the few enemies it names in another
    -- way: your target, the enemy it picks for you, your focus, the one under
    -- the mouse and the targets of the others in your party.
    --
    --   * What is done about it is one setting (/se nameplates), with three
    --     choices for when the game's setting for enemy nameplates reads off:
    --     "on" turns them back on and says so in chat, "tell" only says so,
    --     "off" does nothing. The game refuses the change during a fight, so
    --     then it is made when the fight ends. The addon never turns them off.
    --   * Knowing it. Reach.blind is true while there are no nameplates to go
    --     by: because the setting reads off, or because you have stood in a
    --     fight next to your target for a while and not one enemy had a
    --     nameplate. It is false from the moment one is seen.
    --   * Making do. While it is true, those few other enemies are counted
    --     for an area skill, and such a skill is no longer hidden for having
    --     nobody in its reach: whoever stands next to you cannot be seen.
    --   * What the game does show is kept in the saved report (`sight`), by
    --     the kind of place you fought in.
    ----------------------------------------------------------------------------

    local NEAR = 10 -- yards: an enemy this close has a nameplate, where there are any
    local UNSEEN_WAIT = 2 -- seconds next to an enemy in a fight without one nameplate before none are taken to be shown
    local SETTING_EVERY = 2 -- seconds between looks at the game's setting
    local RETRY = 60 -- seconds before the game is asked again, once it has refused
    local sighting = { readAt = -100, fightPlates = 0, fightEvents = 0 }
    local others = {} -- the list Reach.Others gives
    local HANDLE_KINDS = { softenemy = "softenemy", focus = "focus", mouseover = "mouseover" } -- the rest are "party"

    Reach.events = {} -- event -> whether this client lets it be listened for

    -- What the icons go by while there are no nameplates, for a line of chat.
    ns.BLIND_WORDS = "a skill that hits every enemy around you is only checked on your target, your focus, the enemy "
        .. "under your mouse, the enemy the game picks for you and your party's targets"

    --- True where the addon is to turn enemy nameplates back on.
    local function Keeps()
        return ns.db.nameplates == "on"
    end

    --- A line said in chat about nameplates without being asked, where the
    --- addon is to say so when they are off.
    local function Announce(text)
        if ns.db.nameplates ~= "off" then
            ns.Print(text)
        end
    end

    --- How you can show enemy nameplates yourself, as the start of a sentence.
    local function ShowThem()
        local key = ns.PlatesKey()
        return key and ("Press " .. key .. " to show them") or "You can show them in the game's Options, under Nameplates"
    end

    ns.ShowPlatesWords = ShowThem

    --- Said where the addon only tells: enemy nameplates are off.
    local function TellOff()
        sighting.owed = nil
        Announce("Enemy nameplates are off. While they are, " .. ns.BLIND_WORDS .. ". " .. ShowThem()
            .. ", or type /se nameplates on to have the addon turn them on.")
    end

    --- The saved report's part on what the addon gets to see of the enemies.
    local function SightReport()
        local journal = Journal()
        local sight = journal.sight
        if type(sight) ~= "table" then
            sight = {
                -- By the kind of place ("none" is the open world, "party" a
                -- dungeon): fights, the ones in which an enemy's nameplate
                -- was seen, the ones in which any nameplate was announced,
                -- and the ones that began with the setting off.
                fights = {},
                most = 0, -- enemy nameplates seen at once
                blind = { off = 0, unseen = 0, back = 0 }, -- how often sight was lost, by why, and came back
                -- By softenemy, focus, mouseover and party: how often one was
                -- counted as a further enemy, was one already counted, and
                -- could not be told from one.
                handles = {},
                switched = 0, -- times the addon turned enemy nameplates on
                refused = 0, -- times the game did not let it
                forbidden = 0, -- nameplates announced that addons may not touch
                notes = {},
            }
            journal.sight = sight
        end
        return sight
    end

    --- Reads the game's setting for enemy nameplates. Off, there is nothing
    --- to see the enemies by, and that is known at once.
    local function ReadSetting(now)
        local on = ns.EnemyPlates()
        sighting.readAt = now
        if on ~= sighting.on or not sighting.read then
            if sighting.read or on ~= true then
                local sight = SightReport()
                Keep(sight.notes, format("%s the game's setting for enemy nameplates reads %s", Stamp(now),
                    (on == true and "on") or (on == false and "off") or "nothing"))
                if sight.secure == nil then
                    sight.secure = ns.PlatesSettingSecure()
                end
            end
            sighting.offSince = on == false and now or nil
            if on ~= false then
                sighting.toldFight = nil -- off again in the same fight is said again
            end
            if on == false and not Keeps() then
                if sighting.read then
                    TellOff() -- they went off just now
                else
                    -- Off already when the addon was loaded: nothing is said
                    -- for loading. It is said when a fight begins.
                    sighting.owed = true
                end
            end
            sighting.read = true
            sighting.on = on
            stateDirty = true
        end
        if on == false then
            if Reach.why ~= "off" and not sighting.disbelieved then
                Reach.blind, Reach.why = true, "off"
                sighting.lost = true
                sighting.unseenSince = nil
                local blind = SightReport().blind
                blind.off = blind.off + 1
                stateDirty = true
            end
        elseif Reach.why == "off" then
            -- On again. Whether anything is seen by them is not known yet.
            Reach.blind, Reach.why = nil, nil
            stateDirty = true
        end
        return on
    end

    --- True while the game would refuse to have the setting changed.
    local function Locked()
        return ns.InCombat() and ns.PlatesSettingSecure() ~= false
    end

    --- Sees to it that enemy nameplates are on, where the addon is to turn
    --- them back on. With `asked`, you have just chosen that, and whoever
    --- calls gives the answer in chat. Returns "on", "later" (in a fight: it
    --- is done when the fight ends), "refused" (the game did not let it) or
    --- "off" (the addon is not to turn them on), and true when it just
    --- turned them on.
    function Reach.Keep(now, asked)
        local on = ReadSetting(now)
        if not Keeps() then
            sighting.pending = nil
            return "off"
        end
        if on ~= false then
            sighting.pending, sighting.refusedAt = nil, nil
            return "on"
        end
        if Locked() then
            sighting.pending = true
            if asked then
                sighting.toldFight = combatEpoch -- the answer to what you typed says it
            elseif sighting.toldFight ~= combatEpoch then
                sighting.toldFight = combatEpoch
                Announce("Enemy nameplates are off, and the game does not let an addon turn them on during a fight: "
                    .. "the addon does it when your fight ends. Until then, " .. ns.BLIND_WORDS .. ". " .. ShowThem()
                    .. ".")
            end
            return "later"
        end
        sighting.pending = nil
        if not asked and sighting.refusedAt and now < sighting.refusedAt + RETRY then
            return "refused"
        end
        local sight = SightReport()
        if ns.ShowEnemyPlates() then
            sighting.refusedAt = nil
            ReadSetting(now)
            sight.switched = sight.switched + 1
            if not asked then
                if sighting.switched then
                    Announce("The addon turned enemy nameplates back on. Type /se nameplates to change what it does "
                        .. "when they are off.")
                else
                    Announce("Enemy nameplates were off, so the addon turned them on: it reads the enemies around "
                        .. "you from them. Type /se nameplates to change what it does when they are off.")
                end
            end
            sighting.switched = true
            return "on", true
        end
        sight.refused = sight.refused + 1
        sighting.refusedAt = now
        if not asked and not sighting.toldRefused then
            sighting.toldRefused = true
            Announce("Enemy nameplates are off, and the game did not let the addon turn them on. " .. ShowThem() .. ".")
        end
        return "refused"
    end

    --- The game's setting may have changed, or a fight began or ended: it is
    --- looked at, and seen to, at once.
    function Reach.Watch()
        if ns.db.enabled then
            Reach.Keep(ns.Now())
        end
        stateDirty = true
    end

    --- Whether the addon turns enemy nameplates back on, and how that
    --- stands: "on" (they are shown), "later" (they are off, and it turns
    --- them on when your fight ends), "refused" (they are off, and the game
    --- did not let it) or "off" (it is not to turn them on). Nothing is
    --- changed by asking.
    function ns.KeepsNameplates()
        if not Keeps() then
            return "off"
        elseif ns.EnemyPlates() ~= false then
            return "on"
        elseif sighting.refusedAt and not Locked() then
            return "refused"
        end
        return "later"
    end

    --- Sets what the addon does when enemy nameplates are off: "on", "tell"
    --- or "off" (/se nameplates and the settings), and sees to it at once.
    --- Never turns them off. False for any other word; otherwise it answers
    --- like Reach.Keep.
    function ns.SetNameplates(choice)
        if not ns.NAMEPLATE_CHOICES[choice] then
            return false
        end
        ns.db.nameplates = choice
        stateDirty = true
        return Reach.Keep(ns.Now(), true)
    end

    --- True for an enemy the ranges of your skills put within `yards` of you.
    local function Within(unit, key, yards)
        FarAtLeast(unit, key)
        local hi = reachHi[key]
        return hi ~= nil and hi <= yards
    end

    --- Called in each pass: `walked` says whether the nameplates were gone
    --- over in it, and `plates` how many of them showed an enemy. Works out
    --- whether there are nameplates to go by at all.
    function Reach.Sight(now, walked, plates)
        if now >= sighting.readAt + SETTING_EVERY then
            Reach.Keep(now)
        end
        if not walked then
            return
        end
        if plates > 0 then
            sighting.unseenSince = nil
            if plates > sighting.fightPlates then
                sighting.fightPlates = plates
                local sight = SightReport()
                if plates > sight.most then
                    sight.most = plates
                end
            end
            if sighting.on == false and not sighting.disbelieved then
                if now - sighting.offSince < SETTING_EVERY then
                    return -- they were turned off this moment, and have not gone yet
                end
                -- Enemies with nameplates, long after the setting read off: what
                -- is seen is believed, and the setting is not again.
                sighting.disbelieved = true
                Keep(SightReport().notes, format("%s enemies have nameplates though the setting reads off: it is "
                    .. "not gone by any more", Stamp(now)))
            end
            if sighting.lost then
                sighting.lost = nil
                local blind = SightReport().blind
                blind.back = blind.back + 1
            end
            Reach.blind, Reach.why = false, nil
            return
        end
        if Reach.blind == true then
            return
        end
        -- Not one enemy with a nameplate, and a setting that does not read
        -- off. Next to your target in a fight, that is not how it looks where
        -- nameplates are shown: its own would be there. (Out of a fight it
        -- may be: the game can be set to show nameplates in fights only.)
        if ns.InCombat() and primaryKey and engagedKeys[primaryKey] and Within(primaryUnit, primaryKey, NEAR) then
            sighting.unseenSince = sighting.unseenSince or now
            if now - sighting.unseenSince >= UNSEEN_WAIT then
                Reach.blind, Reach.why = true, "unseen"
                sighting.lost = true
                local sight = SightReport()
                sight.blind.unseen = sight.blind.unseen + 1
                Keep(sight.notes, format("%s no enemy has a nameplate, though your target is within %d yards and the "
                    .. "setting reads %s", Stamp(now), NEAR, sighting.on and "on" or "nothing"))
            end
        else
            sighting.unseenSince = nil
        end
    end

    --- With no nameplates to go by: the enemies in the fight that the game
    --- names in another way, as a list of unit tokens. `first` is the one
    --- already counted, your target or the enemy the game picks for you. One
    --- that may be an enemy already counted is left out: only the game's
    --- plain "not the same" lets it in, so that nobody is counted twice.
    function Reach.Others(first)
        for i = #others, 1, -1 do
            others[i] = nil
        end
        if Reach.blind ~= true then
            return others
        end
        local tokens, events = ns.handleTokens, ns.handleEvents
        local tallies
        for i = 1, #tokens do
            local token = tokens[i]
            if token ~= first and Reach.events[events[token]] and Attackable(token) and ns.IsEngaged(token) then
                local same = false
                if first then
                    same = ns.SameUnit(token, first)
                end
                local n = 1
                while same == false and n <= #others do
                    same = ns.SameUnit(token, others[n])
                    n = n + 1
                end
                tallies = tallies or SightReport().handles
                local kind = HANDLE_KINDS[token] or "party"
                local tally = tallies[kind]
                if type(tally) ~= "table" then
                    tally = { added = 0, same = 0, untold = 0 }
                    tallies[kind] = tally
                end
                if same == false then
                    others[#others + 1] = token
                    tally.added = tally.added + 1
                elseif same then
                    tally.same = tally.same + 1
                else
                    tally.untold = tally.untold + 1
                end
            end
        end
        return others
    end

    --- A fight began (`began`) or ended. What was seen of nameplates in it
    --- goes into the saved report, by the kind of place it was fought in.
    function Reach.Fight(began)
        if began then
            sighting.fighting = true
            sighting.fightPlates, sighting.fightEvents = 0, 0
            sighting.fightOff = sighting.on == false
        elseif sighting.fighting then
            sighting.fighting = nil
            local fights = SightReport().fights
            local place = ns.InstanceKind() or "unknown"
            local tally = fights[place]
            if type(tally) ~= "table" then
                tally = { n = 0, plates = 0, events = 0, off = 0 }
                fights[place] = tally
            end
            tally.n = tally.n + 1
            if sighting.fightPlates > 0 then
                tally.plates = tally.plates + 1
            end
            if sighting.fightEvents > 0 then
                tally.events = tally.events + 1
            end
            if sighting.fightOff then
                tally.off = tally.off + 1
            end
        end
        Reach.Watch()
        if began and sighting.owed and sighting.on == false and ns.db.enabled then
            TellOff() -- they were off when the addon was loaded, and now it matters
        end
    end

    --- The game announced a nameplate: one addons may not touch with
    --- `forbidden`.
    function Reach.Plate(forbidden)
        if forbidden then
            local sight = SightReport()
            sight.forbidden = sight.forbidden + 1
        else
            sighting.fightEvents = sighting.fightEvents + 1
        end
    end

    --- What is known of nameplates, for /se debug: whether there are none to
    --- go by (true, false, or nil while nothing shows either way), why
    --- ("off", "unseen"), and what the game's setting reads.
    function ns.SightProbe()
        return Reach.blind, Reach.why, sighting.on
    end
end

--- A spell that hits every enemy in the fight, judged over the ones that
--- could do with a cast. One that is immune and does not carry the effect is
--- not counted either way: it never will carry it, and is no reason to cast.
--- With nobody left who could take the effect, casting changes nothing.
---
--- An enemy that is proven to stand further off than the spell reaches is
--- left out as well: casting does nothing for it. With every enemy out of
--- reach there is nobody to judge it on: the second answer is then true, and
--- the first is what it would be with all of them in reach, for where icons
--- show on skills that cannot do anything right now.
local function AreaState(info, name, now, calm, most, anyone)
    if fightSize == 0 then
        return false
    end
    local reach = Spells:Reach(info)
    local full, bare, near = 0, 0, 0 -- of the ones it may get to
    local farFull, farBare = 0, 0 -- of the ones out of reach
    local open, farOpen = 0, 0 -- the ones of whom it is not known which they are
    for i = 1, fightSize do
        local enemy = fight[i]
        local carries = Carries(enemy.unit, enemy.key, name, now, calm, "debuff", most, anyone)
        local wants = carries ~= "all" and not ImmuneTo(enemy.key, name, now)
        if reach and Reach.Beyond(enemy.unit, enemy.key, reach) then
            if carries == "all" then
                farFull = farFull + 1
            elseif wants and carries == "unsure" then
                farOpen = farOpen + 1
            elseif wants then
                farBare = farBare + 1
            end
        else
            near = near + 1
            if carries == "all" then
                full = full + 1
            elseif wants and carries == "unsure" then
                open = open + 1
            elseif wants then
                bare = bare + 1
            end
        end
    end
    local nobody = near == 0
    Reach.Leaves(name, near < fightSize)
    if nobody then
        full, bare, open = farFull, farBare, farOpen
        if Reach.blind == true then
            -- No nameplates to go by: whoever stands next to you cannot be
            -- seen, so the skill is not taken to have nobody in its reach.
            nobody = false
        end
    end
    if open > 0 and (bare == 0 or full == 0) then
        -- With some who carry it and some who do not it is the half circle
        -- whatever the others turn out to be. Short of that, the ones in
        -- doubt decide it, and nothing is said.
        return "unsure", nobody
    end
    if bare == 0 then
        return "all", nobody
    elseif full == 0 then
        return "none", nobody
    end
    return "some", nobody
end

--- A skill that goes to one enemy, with none targeted in the middle of a
--- fight: your target has just died, or the next one is not picked yet. It
--- is judged on the enemies of the fight that are in sight, any of whom it
--- may go to next. With every one of them carrying its effect or immune to
--- it, there is nobody to use it for, which is the red X. With one that
--- could do with it, and with none of them in sight, it is the green check.
---
--- With nobody known to do with it, and one of whom it is not known whether
--- it carries the effect, neither is said.
local function Unaimed(name, now, calm, kind, most, anyone)
    local open = false
    for i = 1, fightSize do
        local enemy = fight[i]
        local carries = Carries(enemy.unit, enemy.key, name, now, calm, kind, most, anyone)
        if carries ~= "all" and not ImmuneTo(enemy.key, name, now) then
            if carries == "none" then
                return "none"
            end
            open = true
        end
    end
    if open then
        return "unsure"
    end
    return fightSize > 0 and "all" or "none"
end

--- A buff is judged on the friend you have targeted when the spell can be
--- cast on others, otherwise on you.
local function BuffState(info, now, calm, most, anyone)
    local unit, key = "player", playerKey
    if friendKey and CastOnFriends(info) then
        unit, key = friendUnit, friendKey
    end
    if seen[key] == nil then
        Look(unit, now, calm, "buff") -- the first pass after a buff spell turned up on the bars
    end
    return Carries(unit, key, info.name, now, calm, "buff", most, anyone)
end

--- Says in chat, once, that a skill has lost its icon because its casts kept
--- leaving nothing behind: an icon must never just go missing. `back` is true
--- once the skill has its icon again, which is said as well.
local function TellDropped(name, kind, back, earned)
    local learned = ns.db.learned[name]
    if not learned or (learned.told == true) ~= back then
        return
    end
    local casts, hits = Spells:Record(name, kind)
    casts, hits = floor(casts + 0.5), floor(hits + 0.5)
    if back then
        learned.told = nil
        if earned then
            ns.Print(format("%s does leave an effect behind: %d of your last %d casts did. It has its icon back.",
                name, hits, casts))
        end
        return
    end
    learned.told = true
    ns.Print(format("%s lost its icon because %d of your %d casts left no effect behind. It gets the icon back "
        .. "by itself once its casts are seen to leave one, or at once if you type /se track %s.",
        name, casts - hits, casts, name))
end

local groupSaid -- what your group was last found doing

--- Keeps, in the saved report, how often the answer to "what is your party
--- or raid doing" turned to each of its words (see ns.GroupState). What a
--- real client says of its members can then be read afterwards: whether they
--- are in combat, and whether they are close by.
local function NoteGroup(state)
    if state == groupSaid then
        return
    end
    groupSaid = state
    local journal = Journal()
    local group = journal.group
    if type(group) ~= "table" then
        group = {}
        journal.group = group
    end
    group[state] = (group[state] or 0) + 1
end

-- With no enemy to go to, there is nobody a skill's reach could be judged to:
-- it is asked as little as for a skill that goes to you.
local NOBODY = "player"

local function Refresh(now)
    PassOnChanges(now)
    for i = 1, #TOKEN_KINDS do
        ns.Wipe(sight[TOKEN_KINDS[i]])
    end
    ns.Wipe(seen)
    ns.Wipe(direct)
    ns.Wipe(engagedKeys)
    ns.Wipe(inFight)
    ns.Wipe(states)
    Reach.Ask(true)
    fightSize = 0

    local calm = not ns.AurasSecret()

    primaryUnit = PrimaryEnemy()
    primaryKey = nil
    if primaryUnit then
        primaryKey = Look(primaryUnit, now, calm, "debuff", calm and probe.open or probe.hidden)
        AddToFight(primaryUnit, primaryKey)
        if ns.IsEngaged(primaryUnit) then
            engagedKeys[primaryKey] = true
        end
    end

    -- Nameplates are only walked when an area spell or a cast in flight needs
    -- them, or a skill has to be judged with no enemy targeted in a fight.
    local walked, plates = false, 0
    if sweepWanted or Tracker:HasPending("debuff") or (not primaryUnit and ns.InCombat()) then
        walked = true
        for i = 1, #plateTokens do
            local token = plateTokens[i]
            if Attackable(token) then
                plates = plates + 1
                local key = Look(token, now, calm, "debuff")
                if ns.IsEngaged(token) then
                    engagedKeys[key] = true
                    AddToFight(token, key)
                end
            end
        end
    end
    Reach.Sight(now, walked, plates)
    if walked and plates == 0 then
        -- No nameplates to go by: the few enemies the game names in another
        -- way stand in for them.
        local others = Reach.Others(primaryUnit)
        for i = 1, #others do
            local key = Look(others[i], now, calm, "debuff")
            engagedKeys[key] = true
            AddToFight(others[i], key)
        end
    end

    -- Your own buffs are looked at every pass while a buff spell needs them. Out
    -- of combat they are also read now and then for the sake of the other spells
    -- on the bars, which is how a spell is found to leave a buff on you.
    playerKey = KeyOf("player", "buff")
    friendUnit = FriendTarget()
    friendKey = friendUnit and KeyOf(friendUnit, "buff") or nil
    local buffCast = Tracker:HasPending("buff")
    if buffsWanted or buffCast or (learnWanted and calm and now >= lastSelfLook + SELF_RESCAN) then
        lastSelfLook = now
        Look("player", now, calm, "buff", calm and probe.buffs.open or probe.buffs.hidden)
    end
    if friendKey and (friendWanted or buffCast) then
        Look(friendUnit, now, calm, "buff")
    end

    Tracker:Update(now, seen, engagedKeys, direct)

    -- The panel says when it closes, but ask it again while samples are up, so
    -- that they can never outstay it.
    if showSamples and ns.Options then
        ns.Options.UpdateSampling()
    end
    local samples = showSamples and not ns.InCombat()
    local sampled = 0

    -- Whether the icons may be on the buttons right now. Everything above goes
    -- on either way, so nothing is missed while they are away.
    --
    -- A fight keeps them on from its first moment to its last, whatever is
    -- targeted: your own fight, and under "group" also one that someone in
    -- your party or raid is in close by. Tied to a living target, they went
    -- away each time that target died and came back with the next one.
    local group = ns.GroupState()
    NoteGroup(group)
    local fighting = ns.InCombat() or group == "fighting"
    local when = ns.db.appear
    local appear = when == "always" or ns.InCombat() or (when == "group" and fighting)
    local usableOnly = ns.db.usableOnly

    local wantSweep, wantBuffs, wantFriend, wantLearn = false, false, false, false
    for i = 1, #entries do
        local entry = entries[i]
        local info = entry.info
        local state
        if info and not entry.broken and Visible(entry.frame) then
            local tracked, area, _, source, kind = Spells:Tracking(info)
            if source == "demoted" then
                TellDropped(info.name, kind, false)
            end
            if tracked then
                local name = info.name
                TellDropped(name, kind, true, source ~= "you")
                state = states[name]
                if state == nil then
                    -- How many times over its effect goes, when more than
                    -- once, and whether another player's copy counts.
                    local most = Spells:Stacking(info)
                    local anyone = Spells:Shared(info)
                    if kind == "buff" then
                        state = BuffState(info, now, calm, most, anyone)
                    elseif area then
                        state, Reach.nobody[name] = AreaState(info, name, now, calm, most, anyone)
                    elseif primaryKey then
                        state = Carries(primaryUnit, primaryKey, name, now, calm, kind, most, anyone)
                        if state ~= "all" and ImmuneTo(primaryKey, name, now) then
                            state = "all" -- it never will carry it: casting changes nothing
                        end
                    elseif fighting then
                        state = Unaimed(name, now, calm, kind, most, anyone)
                    else
                        state = false
                    end
                    if state == false and fighting then
                        -- No enemy to judge it on in the middle of a fight,
                        -- and none of the fight in sight: nobody the skill
                        -- could go to is known to have its effect, and that
                        -- is the green check.
                        state = "none"
                    end
                    states[name] = state
                end
                if usableOnly and Reach.nobody[name] then
                    -- Every enemy stands further off than it reaches: it can
                    -- do nothing right now, like a skill whose target is out
                    -- of range.
                    state = nil
                end
                if kind == "buff" then
                    wantBuffs = true
                    if CastOnFriends(info) then
                        wantFriend = true
                    end
                elseif area or (not primaryKey and fighting) then
                    wantSweep = true
                end
            end
            if not (tracked and kind == "buff") and Spells:Watched(info) then
                wantLearn = true
            end
            if not appear then
                state = nil
            elseif state and usableOnly and not CanUse(entry, AimOf(info, kind) or NOBODY) then
                state = nil -- nothing to say about a skill that cannot be used right now
            end
            if samples then
                state = SAMPLE_STATES[sampled % #SAMPLE_STATES + 1]
                sampled = sampled + 1
            end
        end
        SetState(entry, state or nil)
    end
    sweepWanted, buffsWanted, friendWanted, learnWanted = wantSweep, wantBuffs, wantFriend, wantLearn
end

--------------------------------------------------------------------------------
-- Casts
--------------------------------------------------------------------------------

local FORCED_CASTS = 2

--- A spell tracked on your say-so is judged like any other to begin with: by
--- what the unit reports after the cast. Only when that has shown nothing
--- more often than not is the spell taken to land whatever is seen, because
--- the addon then has no way to see what it leaves or where, and you said it
--- leaves something. A buff is taken to land from the start: it cannot miss,
--- and your own effects change too often for a report to say much.
---
--- A spell whose effect has been read by its own name is never in doubt.
local function Forced(name, kind)
    if Spells:IsExact(name, kind) then
        return false
    end
    if kind == "buff" then
        return true
    end
    local casts, hits = Spells:Record(name, kind)
    return casts >= FORCED_CASTS and hits * 2 < casts
end

--- The spell behind a cast event, if it is one we follow.
local function CastInfo(spellID, now)
    local id = ns.PlainNumber(spellID)
    if not id then
        return nil
    end
    local info = Spells:Get(ns.OverrideSpell(id), now)
    if not info or not barNames[info.name] or not Spells:Watched(info) then
        return nil
    end
    return info
end

--- Records who a cast could land on, and what they carry, as it begins.
local function Snapshot(info, area, now, late, kind)
    local snapshot = { name = info.name, kind = kind, time = now, late = late or nil, units = {} }
    local calm = not ns.AurasSecret()
    -- An enemy that stands further off than an area spell reaches is marked
    -- for it (`far`, with how far off it is at the least): nothing is to be
    -- expected of the cast there.
    local reach = area and kind ~= "buff" and Spells:Reach(info) or nil
    if reach then
        Reach.Ask()
    end
    if kind == "buff" then
        local unit = BuffUnit(info)
        local key = KeyOf(unit, kind)
        snapshot.primary = key
        snapshot.units[key] = Follow({
            pre = not late and Sample(unit, now, calm, kind) or nil,
            engaged = true,
        }, unit)
        return snapshot
    end
    local unit = PrimaryEnemy()
    if unit then
        local key = ns.UnitKey(unit)
        Know(unit, key)
        snapshot.primary = key
        snapshot.units[key] = Follow({
            pre = not late and Sample(unit, now, calm, kind) or nil,
            engaged = ns.IsEngaged(unit),
            far = reach and Reach.Beyond(unit, key, reach) or nil,
        }, unit)
    end
    if area then
        local plates = 0
        for i = 1, #plateTokens do
            local token = plateTokens[i]
            if Attackable(token) then
                plates = plates + 1
                local key = ns.UnitKey(token)
                if not snapshot.units[key] then
                    Know(token, key)
                    snapshot.units[key] = Follow({
                        pre = not late and Sample(token, now, calm, kind) or nil,
                        engaged = ns.IsEngaged(token),
                        far = reach and Reach.Beyond(token, key, reach) or nil,
                    }, token)
                end
            end
        end
        if plates == 0 then
            -- No nameplates to go by: the cast may land on the few enemies
            -- the game names in another way.
            local others = Reach.Others(unit)
            for i = 1, #others do
                local token = others[i]
                local key = ns.UnitKey(token)
                if not snapshot.units[key] then
                    Know(token, key)
                    snapshot.units[key] = Follow({
                        pre = not late and Sample(token, now, calm, kind) or nil,
                        engaged = true,
                        far = reach and Reach.Beyond(token, key, reach) or nil,
                    }, token)
                end
            end
        end
    end
    return snapshot
end

local function OnSent(unit, _, castID, spellID)
    if ns.PlainString(unit) ~= "player" or not ns.db.enabled then
        return
    end
    local now = ns.Now()
    local info = CastInfo(spellID, now)
    if not info then
        return
    end
    local _, area, _, _, kind = Spells:Tracking(info)
    Tracker:Sent(ns.PlainString(castID), Snapshot(info, area, now, false, kind))
end

local function Landed(unit, castID, spellID, mustBeSent)
    if ns.PlainString(unit) ~= "player" or not ns.db.enabled then
        return
    end
    local now = ns.Now()
    local info = CastInfo(spellID, now)
    if not info then
        return
    end
    local tracked, area, duration, source, kind = Spells:Tracking(info)
    local snapshot = Tracker:Claim(ns.PlainString(castID), info.name, now)
    if not snapshot then
        if mustBeSent then
            return
        end
        -- We never saw it being sent, so there is no "before" to compare with.
        snapshot = Snapshot(info, area, now, true, kind)
    end
    snapshot.hidden = ns.AurasSecret()
    local wait, sharp = Spells:Wait(info)
    Tracker:Succeeded(snapshot, {
        name = info.name,
        info = info,
        tracked = tracked,
        area = area,
        duration = duration,
        most = Spells:Stacking(info),
        forced = source == "you" and Forced(info.name, kind),
        wait = wait,
        sharp = sharp,
        loose = Spells:ShowsLate(info.name),
        atOnce = Spells:AtOnce(info),
        -- A spell with no icon is listened for all the same. Only a debuff:
        -- reports say too little about your own effects to learn a buff from.
        learning = not tracked and kind == "debuff",
    }, now)
    -- A change reported just before the cast was announced is the cast's doing.
    PassOnChanges(now)
    NoteSpell(info, kind, source)
    if not (tracked and kind == "buff") then
        -- Out of combat, look at your buffs a moment from now: that is how a
        -- spell is found to leave one on you.
        lastSelfLook = now + LEARN_DELAY - SELF_RESCAN
    end
    stateDirty = true
end

local function OnSucceeded(unit, castID, spellID)
    Landed(unit, castID, spellID, false)
end

-- A channel normally reports success as it starts. This only catches the case
-- where it does not: it acts only if the cast is still waiting.
local function OnChannelStart(unit, castID, spellID)
    Landed(unit, castID, spellID, true)
end

local function OnFailed(unit, castID, spellID)
    if ns.PlainString(unit) ~= "player" then
        return
    end
    castID = ns.PlainString(castID)
    if castID then
        Tracker:Unsend(castID)
        return
    end
    local info = CastInfo(spellID, ns.Now())
    if info then
        Tracker:Unsend(nil, info.name)
    end
end

--------------------------------------------------------------------------------
-- Casts by the people in your group
--
-- An effect that a unit carries only once, whoever put it there, is as good
-- from another player as from you. Out of a fight it is simply read off the
-- unit. In a fight nothing can be read, and what is left is this: someone in
-- your party or raid is heard casting a spell that is on your bars too, and
-- in that very frame a unit it could land on reports a change. Then theirs
-- is taken to have landed there.
--
-- That needs the game to say which spell they cast. Its documentation lets a
-- client keep that secret during a fight, and then their casts cannot be
-- followed at all. What was heard is counted in the saved report, so that it
-- can be read there what a real client does.
--------------------------------------------------------------------------------

--- What was heard of the casts of the people in your group, for the saved
--- report: how many (`casts`), how many of them with effect details open
--- (`calm`), and with details hidden how many came with a spell that could be
--- read (`named`) and how many without (`unnamed`). Then how many were of a
--- spell of yours that another player's copy counts for (`followed`), and how
--- many of those were seen to land (`landed`). And what was read off units of
--- other players' copies of such a spell: how often that told something new
--- of how long theirs lasts (`read`), and how often the game said with it
--- which group member had put it there (`sourced`).
local function Others()
    local journal = Journal()
    local others = journal.others
    if type(others) ~= "table" then
        others = { casts = 0, calm = 0, named = 0, unnamed = 0, followed = 0, landed = 0, read = 0, sourced = 0 }
        journal.others = others
    end
    return others
end

function ns.NoteOthers(what)
    local others = Others()
    others[what] = (others[what] or 0) + 1
end

--- The unit token we listen to that shows the same unit as `unit`, if any.
local function Watched(unit)
    for i = 1, #MAIN_TOKENS do
        local token = MAIN_TOKENS[i]
        if listening[token] and ns.SameUnit(unit, token) == true then
            return token
        end
    end
    local plate = ns.PlateTokenFor(unit)
    if plate and listening[plate] then
        return plate
    end
    return nil
end

--- The units a spell of yours cast by someone else could land on, with how
--- each can be followed: every enemy in sight for an area spell, the enemy
--- they have targeted for any other debuff, and you for a buff.
local function GuestSnapshot(token, name, area, kind, now)
    local snapshot = { name = name, kind = kind, time = now, units = {} }
    if kind == "buff" then
        snapshot.units[KeyOf("player", kind)] = Follow({}, "player")
    elseif area then
        local unit = PrimaryEnemy()
        if unit then
            local key = ns.UnitKey(unit)
            Know(unit, key)
            snapshot.units[key] = Follow({}, unit)
        end
        for i = 1, #plateTokens do
            local plate = plateTokens[i]
            if Attackable(plate) then
                local key = ns.UnitKey(plate)
                if not snapshot.units[key] then
                    Know(plate, key)
                    snapshot.units[key] = Follow({}, plate)
                end
            end
        end
    else
        local unit = Watched(token .. "target")
        if unit and Attackable(unit) then
            local key = ns.UnitKey(unit)
            Know(unit, key)
            snapshot.units[key] = Follow({}, unit)
        end
    end
    return snapshot
end

-- Spell id -> its name, for the spells other players were heard casting. A
-- name is all that is asked of them: nearly all of them are no business of
-- this addon's, and the ones that are sit on your bars under that name, at
-- whatever rank, with everything else already known.
local castNames = {}

local function CastName(spellID)
    local name = castNames[spellID]
    if not name then
        name = ns.SpellName(spellID)
        castNames[spellID] = name -- nothing is kept for one the game cannot name yet
    end
    return name
end

--- Someone in your party or raid finished a cast. `spellID` is nil when the
--- game keeps it secret.
local function OnGroupCast(token, spellID)
    if not ns.db.enabled then
        return
    end
    if token:find("^party") and ns.InRaid() then
        return -- in a raid they are heard under their raid name as well
    end
    if ns.IsSelf(token) then
        return -- your own casts are followed on their own
    end
    local now = ns.Now()
    local others = Others()
    others.casts = others.casts + 1
    if not ns.AurasSecret() then
        others.calm = others.calm + 1
    elseif spellID then
        others.named = others.named + 1
    else
        others.unnamed = others.unnamed + 1
    end
    local name = spellID and CastName(spellID)
    local info = name and barInfo[name]
    if not info then
        return -- a spell that could not be read, or one that is not on your bars
    end
    local tracked, area, duration, _, kind = Spells:Tracking(info)
    if not tracked or not Spells:Shared(info) then
        return
    end
    if kind == "buff" and info.selfOnly == true then
        return -- theirs is on them, and never on you
    end
    local most = Spells:Stacking(info)
    if spellID ~= info.id then
        -- Another rank of it than yours, which may leave a shorter effect.
        local rank = Spells:Get(spellID, now)
        local theirs = rank and rank.tooltipDuration
        if theirs and theirs < duration then
            duration = theirs
        end
    end
    -- Theirs may not last as long as yours does.
    duration = Spells:CopyTime(info.name, duration, token, most ~= nil)
    local snapshot = GuestSnapshot(token, info.name, area, kind, now)
    if Tracker:Joined(snapshot, { name = info.name, duration = duration, most = most }, now) then
        others.followed = others.followed + 1
        stateDirty = true
    end
end

local function GroupCast(token, spellID)
    Guard(OnGroupCast, token, spellID)
end

for i = 1, #ns.partyTokens do
    ns.WatchCasts(ns.partyTokens[i], GroupCast)
end
for i = 1, #ns.raidTokens do
    ns.WatchCasts(ns.raidTokens[i], GroupCast)
end

--------------------------------------------------------------------------------
-- The loop
--------------------------------------------------------------------------------

local failures = 0
local watching = false -- the settings panel is open

--- Tells the addon that the settings panel is on screen. The panel lists the
--- spells on the bars, so they are read while it is open even with the icons
--- turned off.
function ns.SetWatching(on)
    on = on and true or false
    if on and not watching then
        barsDirty = true
    end
    watching = on
end

--- Runs every frame; returns true when it actually did something.
local function Tick()
    local now = ns.Now()
    local enabled = ns.db.enabled
    if not enabled and not watching then
        return false
    end
    local worked = false
    if (barsDirty and now >= lastScan + 0.25) or now >= lastScan + 2 then
        ScanBars(now)
        worked = true
    end
    if not enabled then
        return worked -- the settings panel is open: the bars are read, and nothing is shown
    end
    if (stateDirty and now >= lastRefresh + 0.05) or now >= lastRefresh + ns.db.interval then
        stateDirty = false
        lastRefresh = now
        Refresh(now)
        worked = true
    end
    return worked
end

local function OnUpdate()
    if ns.halted then
        return
    end
    local ok, result = pcall(Tick)
    if ok then
        if result then
            failures = 0
        end
        return
    end
    Report(result)
    failures = failures + 1
    if failures >= 25 then
        ns.halted = true
        pcall(HideAll)
        ns.Print("The addon has stopped after repeated problems. Type /se on to start it again, or /se debug to "
            .. "see the last problem.")
    end
end

--- Starts over after /se on.
function ns.Resume()
    ns.halted = false
    failures = 0
    ns.MarkBarsDirty()
end

--- Turns the icons on or off: /se on, /se off and the tick box in the settings.
function ns.SetEnabled(on)
    ns.db.enabled = on and true or false
    if ns.db.enabled then
        ns.Resume()
    else
        HideAll()
    end
end

--- Sets when the icons appear: "always", "combat" or "group". Says whether
--- that was one of the three.
function ns.SetAppear(when)
    if not APPEAR[when] then
        return false
    end
    ns.db.appear = when
    ns.MarkDirty()
    return true
end

--- Sets whether an icon only shows on a skill that can be used right now.
function ns.SetUsableOnly(on)
    ns.db.usableOnly = on and true or false
    ns.MarkDirty()
end

function ns.ResetSettings()
    local saved = ns.db
    ns.Wipe(saved)
    for key, value in pairs(Defaults()) do
        saved[key] = value
    end
    Tracker:Reset()
    Spells:Reset()
    Spells:ForgetImmune()
    ns.Relayout()
    ns.MarkBarsDirty()
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
local handlers = {}

local function NewFight()
    combatEpoch = combatEpoch + 1
    for _, state in pairs(sampling) do
        state.failures, state.blockedUntil = 0, 0
    end
    -- What kind of creature a unit is may be told now where it was not before.
    for key, kind in pairs(kindOf) do
        if kind == false then
            kindOf[key] = nil
            kindsKept = kindsKept - 1
        end
    end
    lastSelfLook = -100
    stateDirty = true
end

function handlers.ADDON_LOADED(name)
    if ns.PlainString(name) == ADDON_NAME then
        LoadSettings()
    end
end

function handlers.PLAYER_LOGIN()
    nextFind = -100
    ns.MarkBarsDirty()
    if ns.Options then
        ns.Options.Register()
    end
    -- Nothing is said in chat for loading. /se gives the version.
end

function handlers.PLAYER_ENTERING_WORLD()
    ns.TokenChanged(nil)
    Reassigned(nil)
    NewFight()
    nextFind = -100
    ns.MarkBarsDirty()
end

function handlers.PLAYER_TARGET_CHANGED()
    ns.TokenChanged("target")
    Reassigned("target")
    stateDirty = true
end

--- The people in your group changed, and with them whom each party or raid
--- name stands for.
function handlers.GROUP_ROSTER_UPDATE()
    Spells:ForgetCopies()
end

function handlers.PLAYER_DEAD()
    Tracker:ForgetUnit(KeyOf("player", "buff")) -- your buffs died with you
    stateDirty = true
end

function handlers.PLAYER_SOFT_ENEMY_CHANGED()
    ns.TokenChanged("softenemy")
    Reassigned("softenemy")
    stateDirty = true
end

local function PlateChanged(token)
    token = ns.PlainString(token)
    if token then
        ns.TokenChanged(token)
        Reassigned(token)
    end
    stateDirty = true
end

function handlers.NAME_PLATE_UNIT_ADDED(token)
    PlateChanged(token)
    Reach.Plate()
end

handlers.NAME_PLATE_UNIT_REMOVED = PlateChanged

--- A nameplate that addons may not touch. Nothing can be read from it: that
--- there are such is kept for the saved report.
function handlers.FORBIDDEN_NAME_PLATE_UNIT_ADDED()
    Reach.Plate(true)
end

function handlers.PLAYER_REGEN_DISABLED()
    NewFight()
    Reach.Fight(true)
end

function handlers.PLAYER_REGEN_ENABLED()
    NewFight()
    Reach.Fight(false)
end

--- One of the game's settings changed: the one for enemy nameplates is the
--- addon's business (see "With no nameplates to go by").
function handlers.CVAR_UPDATE(name)
    if ns.IsPlatesSetting(name) then
        Reach.Watch()
    end
end

-- The other names the game gives an enemy each move to another unit now and
-- then, and what was learned through one belongs to the unit it has left.
function handlers.UPDATE_MOUSEOVER_UNIT()
    ns.TokenChanged("mouseover")
    if Reach.blind then
        stateDirty = true
    end
end

function handlers.PLAYER_FOCUS_CHANGED()
    ns.TokenChanged("focus")
    if Reach.blind then
        stateDirty = true
    end
end

function handlers.UNIT_TARGET(unit)
    local token = ns.memberTargets[ns.PlainString(unit) or ""]
    if token then
        ns.TokenChanged(token)
        if Reach.blind then
            stateDirty = true
        end
    end
end

handlers.ACTIONBAR_SLOT_CHANGED = ns.MarkBarsDirty
handlers.ACTIONBAR_PAGE_CHANGED = ns.MarkBarsDirty
handlers.UPDATE_BONUS_ACTIONBAR = ns.MarkBarsDirty
handlers.UPDATE_SHAPESHIFT_FORM = ns.MarkBarsDirty
handlers.UPDATE_MACROS = ns.MarkBarsDirty

function handlers.SPELLS_CHANGED()
    Spells:Reset()
    ns.MarkBarsDirty()
end

handlers.UNIT_SPELLCAST_SENT = OnSent
handlers.UNIT_SPELLCAST_SUCCEEDED = OnSucceeded
handlers.UNIT_SPELLCAST_CHANNEL_START = OnChannelStart
handlers.UNIT_SPELLCAST_FAILED = OnFailed
handlers.UNIT_SPELLCAST_FAILED_QUIET = OnFailed
handlers.UNIT_SPELLCAST_INTERRUPTED = OnFailed

-- An event this client does not have must not stop the others from registering.
local UNIT_EVENTS = {
    UNIT_SPELLCAST_SUCCEEDED = true,
    UNIT_SPELLCAST_CHANNEL_START = true,
    UNIT_SPELLCAST_FAILED = true,
    UNIT_SPELLCAST_FAILED_QUIET = true,
    UNIT_SPELLCAST_INTERRUPTED = true,
}

for event in pairs(handlers) do
    local registered = false
    if UNIT_EVENTS[event] then
        registered = pcall(frame.RegisterUnitEvent, frame, event, "player")
    end
    if not registered then
        registered = pcall(frame.RegisterEvent, frame, event)
    end
    if event == "GROUP_ROSTER_UPDATE" then
        rosterHeard = registered
    end
    Reach.events[event] = registered
end

frame:SetScript("OnEvent", function(_, event, ...)
    local handler = handlers[event]
    if handler then
        Guard(handler, ...)
    end
end)

frame:SetScript("OnUpdate", OnUpdate)

ns.frame = frame
