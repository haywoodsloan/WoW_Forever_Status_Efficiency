-- Status Efficiency: finds the action buttons, follows your casts and the units
-- they land on, and draws the icon on each button.
--
-- A spell that puts a debuff on enemies:
--   green check          none of the enemies the spell would hit has its effect
--   yellow half circle   some of them have it
--   red X                all of them have it, so casting again changes nothing
--   no icon              no enemy to judge
--
-- A spell that puts a buff on you, or on the friend you have targeted:
--   green check          the buff is not there
--   red X                the buff is there, so casting again changes nothing
--
-- A spell that applies no status effect gets no icon. Two settings say when the
-- icons appear at all: always, only while an enemy is targeted (the default), or
-- only during a fight; and on every skill, or only on one that can be used right
-- now (the default).

local ADDON_NAME, ns = ...

local Spells, Tracker, Icons = ns.Spells, ns.Tracker, ns.Icons

local pairs, type, pcall, tostring = pairs, type, pcall, tostring
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
-- "target" (only while an enemy is targeted) or "combat" (only during a fight).
local APPEAR = { always = true, target = true, combat = true }
local APPEAR_DEFAULT = "target"
ns.APPEAR_DEFAULT = APPEAR_DEFAULT

local function Defaults()
    return {
        version = 1,
        enabled = true,
        appear = APPEAR_DEFAULT,
        usableOnly = true, -- an icon only on a skill that can be used right now
        corner = "TOPLEFT",
        size = 0, -- 0 sizes the icon from the button
        plain = false, -- draw the settings panel without the game's own controls
        window = {}, -- where the settings window was dragged to: { point, relative, x, y }
        interval = 0.2, -- seconds between looks at the enemies
        log = false,
        icons = {}, -- the icon chosen for each result; empty means the default
        custom = {}, -- your own texture for a result set to "custom"
        spells = {}, -- your choices by spell name: { track, kind, aoe, duration }
        learned = {}, -- what play has shown by spell name: { exact, casts, hits, buff, buffCasts, buffHits, duration }
    }
end

ns.db = Defaults()

local function LoadSettings()
    local saved = StatusEfficiencyDB
    if type(saved) ~= "table" then
        saved = {}
        StatusEfficiencyDB = saved
    end
    for key, value in pairs(Defaults()) do
        if type(saved[key]) ~= type(value) then
            saved[key] = value
        end
    end
    if not CORNERS[saved.corner] then
        saved.corner = "TOPLEFT"
    end
    if not APPEAR[saved.appear] then
        saved.appear = APPEAR_DEFAULT
    end
    if saved.interval < 0.05 or saved.interval > 2 then
        saved.interval = 0.2
    end
    if saved.size > SIZE_MAX and saved.size <= OLD_SIZE_MAX then
        saved.size = SIZE_MAX -- chosen when sizes went further: keep it as big as it can be
    elseif saved.size ~= 0 and (saved.size < SIZE_MIN or saved.size > SIZE_MAX) then
        saved.size = 0
    end
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

local function Report(err)
    err = tostring(err)
    ns.lastError = err
    ns.errorCount = (ns.errorCount or 0) + 1
    if not reported[err] and reportCount < 3 then
        reported[err] = true
        reportCount = reportCount + 1
        ns.Print("hit a problem and skipped an update. /se debug shows the details. (" .. err .. ")")
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
        entry.texture:SetTexture(art)
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

-- What the game said the last time it was asked whether a skill can be used,
-- for /se debug: "yes" when it answered, "no" when it would not.
local usableProbe = { usable = "not asked yet", range = "not asked yet" }
ns.usableProbe = usableProbe

--- Whether the skill on a button can be used right now: not while the game dims
--- it (no rage, the wrong stance and so on) or its target is too far or too
--- close. An answer the game will not give counts as yes, and so does a
--- cooldown, which it can keep to itself during a fight.
local function CanUse(entry)
    local slot = entry.slot
    if not slot then
        return true
    end
    local usable, inRange = ns.ActionUsable(slot)
    usableProbe.usable = usable == nil and "no" or "yes"
    if inRange ~= nil then
        usableProbe.range = "yes"
    elseif usableProbe.range ~= "yes" then
        usableProbe.range = "no answer so far"
    end
    return usable ~= false and inRange ~= false
end

-- While the settings panel is open on its Appearance tab, and you are not in a
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

--- Looks at a unit once per pass: counts your effects of one kind on it and,
--- while the client shows them, reads them by name. `note` is the part of the
--- probe to fill in, if this look is one /se debug reports on.
local function Look(unit, now, calm, kind, note)
    local key = KeyOf(unit, kind)
    if seen[key] ~= nil then
        return key
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
            Tracker:Sync(key, found, barNames, now, kind)
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

--- Does this unit have the spell's effect? While details are hidden, an effect
--- the client still shows by name is read directly and overrides the books.
local function HasEffect(unit, key, name, now, calm, kind)
    if not calm then
        local readable = nameReadable[kind]
        local aura = ns.ReadAuraByName(unit, name, kind)
        if aura then
            Tracker:Observe(key, name, aura, now)
            Spells:LearnExact(name, aura.duration, kind)
            readable[name] = combatEpoch
            if kind == "buff" then
                probe.buffs.hidden.byName = true
            else
                probe.hidden.byName = true
            end
        elseif aura == false and readable[name] == combatEpoch then
            Tracker:Absent(key, name)
        end
    end
    return Tracker:Has(key, name, now)
end

local function AreaState(name, now, calm)
    if fightSize == 0 then
        return false
    end
    local have = 0
    for i = 1, fightSize do
        local enemy = fight[i]
        if HasEffect(enemy.unit, enemy.key, name, now, calm, "debuff") then
            have = have + 1
        end
    end
    if have == 0 then
        return "none"
    elseif have == fightSize then
        return "all"
    end
    return "some"
end

--- A buff is either there or not: judged on the friend you have targeted when
--- the spell can be cast on others, otherwise on you.
local function BuffState(info, now, calm)
    local unit, key = "player", playerKey
    if friendKey and CastOnFriends(info) then
        unit, key = friendUnit, friendKey
    end
    if seen[key] == nil then
        Look(unit, now, calm, "buff") -- the first pass after a buff spell turned up on the bars
    end
    return HasEffect(unit, key, info.name, now, calm, "buff") and "all" or "none"
end

local function Refresh(now)
    ns.Wipe(seen)
    ns.Wipe(direct)
    ns.Wipe(engagedKeys)
    ns.Wipe(inFight)
    ns.Wipe(states)
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

    -- Nameplates are only walked when an area spell or a cast in flight needs them.
    if sweepWanted or Tracker:HasPending("debuff") then
        for i = 1, #plateTokens do
            local token = plateTokens[i]
            if Attackable(token) then
                local key = Look(token, now, calm, "debuff")
                if ns.IsEngaged(token) then
                    engagedKeys[key] = true
                    AddToFight(token, key)
                end
            end
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
    local when = ns.db.appear
    local appear = when == "always" or (when == "combat" and ns.InCombat())
        or (when ~= "combat" and primaryUnit ~= nil)
    local usableOnly = ns.db.usableOnly

    local wantSweep, wantBuffs, wantFriend, wantLearn = false, false, false, false
    for i = 1, #entries do
        local entry = entries[i]
        local info = entry.info
        local state
        if info and not entry.broken and Visible(entry.frame) then
            local tracked, area, _, _, kind = Spells:Tracking(info)
            if tracked then
                local name = info.name
                state = states[name]
                if state == nil then
                    if kind == "buff" then
                        state = BuffState(info, now, calm)
                    elseif area then
                        state = AreaState(name, now, calm)
                    elseif primaryKey then
                        state = HasEffect(primaryUnit, primaryKey, name, now, calm, kind) and "all" or "none"
                    else
                        state = false
                    end
                    states[name] = state
                end
                if kind == "buff" then
                    wantBuffs = true
                    if CastOnFriends(info) then
                        wantFriend = true
                    end
                elseif area then
                    wantSweep = true
                end
            end
            if not (tracked and kind == "buff") and Spells:Watched(info) then
                wantLearn = true
            end
            if not appear then
                state = nil
            elseif state and usableOnly and not CanUse(entry) then
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
    if kind == "buff" then
        local unit = BuffUnit(info)
        local key = KeyOf(unit, kind)
        snapshot.primary = key
        snapshot.units[key] = {
            pre = not late and Sample(unit, now, calm, kind) or nil,
            engaged = true,
        }
        return snapshot
    end
    local unit = PrimaryEnemy()
    if unit then
        local key = ns.UnitKey(unit)
        snapshot.primary = key
        snapshot.units[key] = {
            pre = not late and Sample(unit, now, calm, kind) or nil,
            engaged = ns.IsEngaged(unit),
        }
    end
    if area then
        for i = 1, #plateTokens do
            local token = plateTokens[i]
            if Attackable(token) then
                local key = ns.UnitKey(token)
                if not snapshot.units[key] then
                    snapshot.units[key] = {
                        pre = not late and Sample(token, now, calm, kind) or nil,
                        engaged = ns.IsEngaged(token),
                    }
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
    Tracker:Succeeded(snapshot, {
        name = info.name,
        tracked = tracked,
        area = area,
        duration = duration,
        forced = source == "you",
    }, now)
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
        ns.Print("stopped after repeated problems. /se on starts it again, and /se debug shows the last one.")
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

--- Sets when the icons appear: "always", "target" or "combat". Says whether
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
    ns.Print("v" .. ns.VERSION .. " loaded. Type /se for commands, or /se options for the settings window.")
end

function handlers.PLAYER_ENTERING_WORLD()
    ns.TokenChanged(nil)
    NewFight()
    nextFind = -100
    ns.MarkBarsDirty()
end

function handlers.PLAYER_TARGET_CHANGED()
    ns.TokenChanged("target")
    stateDirty = true
end

function handlers.PLAYER_DEAD()
    Tracker:ForgetUnit(KeyOf("player", "buff")) -- your buffs died with you
    stateDirty = true
end

function handlers.PLAYER_SOFT_ENEMY_CHANGED()
    ns.TokenChanged("softenemy")
    stateDirty = true
end

local function PlateChanged(token)
    token = ns.PlainString(token)
    if token then
        ns.TokenChanged(token)
    end
    stateDirty = true
end

handlers.NAME_PLATE_UNIT_ADDED = PlateChanged
handlers.NAME_PLATE_UNIT_REMOVED = PlateChanged

handlers.PLAYER_REGEN_DISABLED = NewFight
handlers.PLAYER_REGEN_ENABLED = NewFight

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
        pcall(frame.RegisterEvent, frame, event)
    end
end

frame:SetScript("OnEvent", function(_, event, ...)
    local handler = handlers[event]
    if handler then
        Guard(handler, ...)
    end
end)

frame:SetScript("OnUpdate", OnUpdate)

ns.frame = frame
