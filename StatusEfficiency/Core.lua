-- Status Efficiency: finds the action buttons, follows your casts and the enemies
-- around you, and draws the icon on each button.
--
--   green check          none of the enemies the spell would hit has its effect
--   yellow half circle   some of them have it
--   red X                all of them have it, so casting again changes nothing
--   no icon              no enemy to judge, or the spell applies no status effect

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

local function Defaults()
    return {
        version = 1,
        enabled = true,
        corner = "TOPLEFT",
        size = 0, -- 0 sizes the icon from the button
        interval = 0.2, -- seconds between looks at the enemies
        log = false,
        icons = {}, -- the icon chosen for each indication; empty means the default
        custom = {}, -- your own texture for an indication set to "custom"
        spells = {}, -- your choices by spell name: { track, aoe, duration }
        learned = {}, -- what play has shown by spell name: { casts, hits, exact, duration }
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
    if saved.interval < 0.05 or saved.interval > 2 then
        saved.interval = 0.2
    end
    if saved.size < 0 or saved.size > 128 then
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

local function IconSize(entry)
    local size = ns.db.size
    if size > 0 then
        return size
    end
    local width = ns.Call(ns.Field(entry.frame, "GetWidth"), entry.frame)
    if type(width) ~= "number" or width <= 0 then
        width = 40
    end
    return max(10, min(40, floor(width * 0.45 + 0.5)))
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

local function SetState(entry, state)
    local art = state and Icons.Texture(state) or nil
    if entry.state == state and entry.art == art then
        return
    end
    if state and not entry.overlay then
        if entry.broken or not pcall(CreateOverlay, entry) or not entry.overlay then
            entry.broken = true
            return
        end
    end
    entry.state, entry.art = state, art
    if state then
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
        entry.info = info
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
-- Enemies
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

-- What the client allowed the last time we looked, for /se debug.
local probe = { open = {}, hidden = {} }
ns.probe = probe

local combatEpoch = 0 -- goes up every time combat starts or ends

-- Counting debuffs can be refused outright in combat. Stop asking for a while
-- after a run of refusals rather than failing the same call every pass.
local sampleFailures, sampleBlockedUntil = 0, 0

-- While aura details are hidden, an answer of "no debuffs" could be the truth or
-- could be the client hiding them. It is only believed once the same fight has
-- shown at least one debuff of ours through the same call.
local trustedEpoch = -1
local lastAnswer = "none" -- what the last count looked like: "ids", "count" or "none"

--- Counts your debuffs on an enemy: { n, ids } or nil when that cannot be relied on.
local function Sample(unit, now, calm)
    lastAnswer = "none"
    if now < sampleBlockedUntil then
        return nil
    end
    local sample = ns.SamplePlayerDebuffs(unit)
    if not sample then
        sampleFailures = sampleFailures + 1
        if sampleFailures >= 6 then
            sampleFailures = 0
            sampleBlockedUntil = now + 5
        end
        return nil
    end
    sampleFailures = 0
    lastAnswer = sample.ids and "ids" or "count"
    if not calm then
        if sample.n > 0 then
            trustedEpoch = combatEpoch
        elseif trustedEpoch ~= combatEpoch then
            return nil
        end
    end
    return sample
end

local seen = {} -- unit key -> sample, or false when unreadable, for enemies looked at this pass
local engagedKeys = {} -- unit key -> true for enemies in the fight
local fight = {} -- the enemies an area spell is judged against: { unit, key }
local inFight = {}
local fightSize = 0
local states = {} -- spell name -> its state this pass
local sweepWanted = false
local nameReadable = {} -- spell name -> the fight in which its debuff was read by name
local primaryUnit, primaryKey

local function Look(unit, now, calm, isPrimary)
    local key = ns.UnitKey(unit)
    if seen[key] ~= nil then
        return key
    end
    local sample = Sample(unit, now, calm)
    local answer = lastAnswer
    seen[key] = sample or false
    local direct = false
    if calm then
        local found = ns.ReadPlayerDebuffs(unit)
        if found then
            direct = true
            Tracker:Sync(key, found, barNames, now)
        end
    end
    if isPrimary then
        local note = calm and probe.open or probe.hidden
        note.time = now
        note.sample = answer
        note.trusted = calm or trustedEpoch == combatEpoch
        note.direct = direct
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

--- Does this enemy have the spell's effect? While details are hidden, a debuff
--- the client still shows by name is read directly and overrides the books.
local function HasEffect(unit, key, name, now, calm)
    if not calm then
        local aura = ns.ReadPlayerDebuffByName(unit, name)
        if aura then
            Tracker:Observe(key, name, aura, now)
            Spells:LearnExact(name, aura.duration)
            nameReadable[name] = combatEpoch
            probe.hidden.byName = true
        elseif aura == false and nameReadable[name] == combatEpoch then
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
        if HasEffect(enemy.unit, enemy.key, name, now, calm) then
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

local function Refresh(now)
    ns.Wipe(seen)
    ns.Wipe(engagedKeys)
    ns.Wipe(inFight)
    ns.Wipe(states)
    fightSize = 0

    local calm = not ns.AurasSecret()

    primaryUnit = PrimaryEnemy()
    primaryKey = nil
    if primaryUnit then
        primaryKey = Look(primaryUnit, now, calm, true)
        AddToFight(primaryUnit, primaryKey)
        if ns.IsEngaged(primaryUnit) then
            engagedKeys[primaryKey] = true
        end
    end

    -- Nameplates are only walked when an area spell or a cast in flight needs them.
    if sweepWanted or Tracker:HasPending() then
        for i = 1, #plateTokens do
            local token = plateTokens[i]
            if Attackable(token) then
                local key = Look(token, now, calm, false)
                if ns.IsEngaged(token) then
                    engagedKeys[key] = true
                    AddToFight(token, key)
                end
            end
        end
    end

    Tracker:Update(now, seen, engagedKeys)

    local wantSweep = false
    for i = 1, #entries do
        local entry = entries[i]
        local info = entry.info
        local state
        if info and not entry.broken and Visible(entry.frame) then
            local tracked, area = Spells:Tracking(info)
            if tracked then
                local name = info.name
                state = states[name]
                if state == nil then
                    if area then
                        state = AreaState(name, now, calm)
                    elseif primaryKey then
                        state = HasEffect(primaryUnit, primaryKey, name, now, calm) and "all" or "none"
                    else
                        state = false
                    end
                    states[name] = state
                end
                if area then
                    wantSweep = true
                end
            end
        end
        SetState(entry, state or nil)
    end
    sweepWanted = wantSweep
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

--- Records who is around, and what they carry, as a cast begins.
local function Snapshot(info, area, now, late)
    local snapshot = { name = info.name, time = now, late = late or nil, units = {} }
    local calm = not ns.AurasSecret()
    local unit = PrimaryEnemy()
    if unit then
        local key = ns.UnitKey(unit)
        snapshot.primary = key
        snapshot.units[key] = {
            pre = not late and Sample(unit, now, calm) or nil,
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
                        pre = not late and Sample(token, now, calm) or nil,
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
    local _, area = Spells:Tracking(info)
    Tracker:Sent(ns.PlainString(castID), Snapshot(info, area, now, false))
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
    local tracked, area, duration, source = Spells:Tracking(info)
    local snapshot = Tracker:Claim(ns.PlainString(castID), info.name, now)
    if not snapshot then
        if mustBeSent then
            return
        end
        -- We never saw it being sent, so there is no "before" to compare with.
        snapshot = Snapshot(info, area, now, true)
    end
    Tracker:Succeeded(snapshot, {
        name = info.name,
        tracked = tracked,
        area = area,
        duration = duration,
        forced = source == "you",
    }, now)
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

--- Runs every frame; returns true when it actually did something.
local function Tick()
    local now = ns.Now()
    if not ns.db.enabled then
        return false
    end
    local worked = false
    if (barsDirty and now >= lastScan + 0.25) or now >= lastScan + 2 then
        ScanBars(now)
        worked = true
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
    sampleFailures, sampleBlockedUntil = 0, 0
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
