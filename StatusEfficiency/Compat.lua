-- Status Efficiency: guarded access to the game API.
--
-- WoW Forever runs the modern (12.1.5) addon API with "secret values". In combat
-- the client hands addons values they may store and pass along but must not
-- compare, do arithmetic on, use as table keys or (for booleans) test. Touching
-- one the wrong way raises a Lua error, and some aura queries refuse addons
-- outright while auras are hidden.
--
-- Everything that talks to the game goes through this file. Nothing leaves it
-- unless it is a plain value, so the rest of the addon never handles a secret.
--
-- ns.refusals notes the last error each aura query raised, and ns.nameReads
-- what asking for an effect by name gave, for /se debug and the saved report:
-- it is how we find out what a given client really allows.

local ADDON_NAME, ns = ...

ns.ADDON_NAME = ADDON_NAME
ns.VERSION = "0.3.1"

local pcall, type, pairs, tostring = pcall, type, pairs, tostring

local PREFIX = "|cff66ccffStatus Efficiency|r: "

function ns.Print(text)
    print(PREFIX .. text)
end

-- Replaced by Core.lua once it loads.
function ns.Log() end
function ns.Note() end
function ns.MarkDirty() end
function ns.InSight()
    return true
end

function ns.Wipe(tbl)
    for key in pairs(tbl) do
        tbl[key] = nil
    end
    return tbl
end

--------------------------------------------------------------------------------
-- Secret values
--------------------------------------------------------------------------------

local issecretvalue = issecretvalue -- nil on clients that have no secret values

local function IsSecret(value)
    if issecretvalue then
        return issecretvalue(value) and true or false
    end
    return false
end

ns.IsSecret = IsSecret
ns.hasSecretValues = issecretvalue ~= nil

--- Returns the value, or nil when it is secret.
local function Plain(value)
    if IsSecret(value) then
        return nil
    end
    return value
end

local function PlainNumber(value)
    value = Plain(value)
    if type(value) == "number" then
        return value
    end
    return nil
end

local function PlainString(value)
    value = Plain(value)
    if type(value) == "string" then
        return value
    end
    return nil
end

ns.Plain = Plain
ns.PlainNumber = PlainNumber
ns.PlainString = PlainString

--- Calls fn and returns its first result, but only when the call succeeded and
--- the result is not secret. The second return says whether the answer is known.
local function Call(fn, ...)
    if type(fn) ~= "function" then
        return nil, false
    end
    local ok, result = pcall(fn, ...)
    if not ok or IsSecret(result) then
        return nil, false
    end
    return result, true
end

--- Like Call, for yes/no questions: true, false, or nil when the client will not say.
local function Flag(fn, ...)
    local result, known = Call(fn, ...)
    if not known then
        return nil
    end
    if result then
        return true
    end
    return false
end

local function Index(tbl, key)
    return tbl[key]
end

--- Reads tbl[key] without risking an error on a protected table or a secret value.
local function Field(tbl, key)
    local value = Call(Index, tbl, key)
    return value
end

ns.Call = Call
ns.Flag = Flag
ns.Field = Field

ns.refusals = {} -- name of a game function -> the error it last raised
ns.nameReads = {} -- effect name -> how often asking for it by name found it, found nothing, or was refused

local function Refused(name, err)
    err = PlainString(err)
    ns.refusals[name] = err and err:sub(1, 160) or "an error with no text"
end

local function NameRead(name, outcome)
    local reads = ns.nameReads[name]
    if not reads then
        reads = { found = 0, nothing = 0, refused = 0 }
        ns.nameReads[name] = reads
    end
    reads[outcome] = reads[outcome] + 1
end

--------------------------------------------------------------------------------
-- Combat and secrecy state
--------------------------------------------------------------------------------

function ns.Now()
    return GetTime()
end

function ns.InCombat()
    return Flag(InCombatLockdown) == true
end

--- True while the client is hiding aura details from addons.
function ns.AurasSecret()
    local secret = Flag(C_Secrets and C_Secrets.ShouldAurasBeSecret)
    if secret ~= nil then
        return secret
    end
    if not ns.hasSecretValues then
        return false
    end
    return ns.InCombat()
end

--------------------------------------------------------------------------------
-- Units
--------------------------------------------------------------------------------

local function ReadableGUID(unit)
    local guid = Call(UnitGUID, unit)
    if type(guid) == "string" and guid ~= "" then
        return guid
    end
    return nil
end

--- True when the unit is your own character, whatever token it goes by.
local function IsSelf(unit)
    if unit == "player" then
        return true
    end
    local same = Flag(UnitIsUnit, unit, "player")
    if same ~= nil then
        return same
    end
    local guid = ReadableGUID(unit)
    return guid ~= nil and guid == ReadableGUID("player")
end

function ns.Exists(unit)
    local exists = Flag(UnitExists, unit)
    if exists ~= nil then
        return exists
    end
    -- The client would not say. A unit that has an identity, even a secret one, exists.
    local ok, guid = pcall(UnitGUID, unit)
    if ok then
        if IsSecret(guid) then
            return true
        end
        return guid ~= nil
    end
    return false
end

function ns.IsEnemy(unit)
    local answer = Flag(UnitCanAttack, "player", unit)
    if answer ~= nil then
        return answer
    end
    if Flag(UnitIsEnemy, "player", unit) == true then
        return true
    end
    answer = Flag(UnitIsFriend, "player", unit)
    if answer ~= nil then
        return not answer
    end
    local reaction = Call(UnitReaction, unit, "player")
    if type(reaction) == "number" then
        return reaction <= 4
    end
    -- Nothing readable. Party members always answer, so an unreadable unit is an
    -- NPC, and while we are fighting it is most likely the thing we are fighting.
    -- Unless it is you: targeting yourself does not make you an enemy.
    if IsSelf(unit) then
        return false
    end
    return ns.InCombat()
end

function ns.IsDead(unit)
    return Flag(UnitIsDeadOrGhost, unit) == true
end

--- True when a helpful spell of ours could land on the unit.
function ns.CanAssist(unit)
    local answer = Flag(UnitCanAssist, "player", unit)
    if answer ~= nil then
        return answer
    end
    return Flag(UnitIsFriend, "player", unit) == true or IsSelf(unit)
end

--- True when the unit is in a fight (ideally with us), so an area spell cast now
--- could plausibly hit it.
function ns.IsEngaged(unit)
    local threat, known = Call(UnitThreatSituation, "player", unit)
    if known and threat ~= nil then
        return true
    end
    local fighting = Flag(UnitAffectingCombat, unit)
    if fighting ~= nil then
        return fighting
    end
    return ns.InCombat()
end

--------------------------------------------------------------------------------
-- Unit keys
--
-- Tracked effects are stored per unit. The GUID is the natural key, but the
-- client can hide NPC identity. When it does we fall back to the nameplate token
-- that currently shows the unit, tagged with a counter that changes whenever the
-- token is handed to a different unit.
--------------------------------------------------------------------------------

local NAMEPLATE_COUNT = 40
local plateTokens = {}
for i = 1, NAMEPLATE_COUNT do
    plateTokens[i] = "nameplate" .. i
end
ns.plateTokens = plateTokens

local tokenEpoch = {}
local worldEpoch = 0
local knownGUID = {} -- token key -> the GUID read while the client still showed it

local function TokenKey(token)
    return token .. "#" .. (tokenEpoch[token] or 0) .. "." .. worldEpoch
end

--- Call when a unit token starts pointing at a different unit. With no token,
--- every token-based key is invalidated.
function ns.TokenChanged(token)
    if type(token) == "string" then
        knownGUID[TokenKey(token)] = nil
        tokenEpoch[token] = (tokenEpoch[token] or 0) + 1
    else
        worldEpoch = worldEpoch + 1
        for key in pairs(knownGUID) do
            knownGUID[key] = nil
        end
    end
end

local function IsPlateToken(unit)
    return type(unit) == "string" and unit:find("^nameplate%d+$") ~= nil
end

local function PlateFor(unit)
    local plate = Call(C_NamePlate and C_NamePlate.GetNamePlateForUnit, unit)
    if type(plate) == "table" then
        return plate
    end
    return nil
end

--- The nameplate token ("nameplate7") showing the same unit as `unit`, if any.
function ns.PlateTokenFor(unit)
    if IsPlateToken(unit) then
        return unit
    end
    local plate = PlateFor(unit)
    if not plate then
        return nil
    end
    local token = Field(plate, "unitToken") or Field(plate, "namePlateUnitToken")
    if IsPlateToken(token) then
        return token
    end
    for i = 1, NAMEPLATE_COUNT do
        if PlateFor(plateTokens[i]) == plate then
            return plateTokens[i]
        end
    end
    return nil
end

--- True when the unit's GUID is readable right now.
function ns.IdentityReadable(unit)
    return ReadableGUID(unit) ~= nil
end

--- A stable name for the unit behind a token. A GUID that was readable earlier
--- keeps identifying the unit after the client hides it, for as long as the
--- token (or the nameplate showing the unit) has not moved to another unit.
function ns.UnitKey(unit)
    if unit == "player" then
        return ReadableGUID(unit) or unit -- you are never hidden, and need no nameplate
    end
    local guid = ReadableGUID(unit)
    local plate = ns.PlateTokenFor(unit)
    local plateKey = plate and TokenKey(plate)
    local ownKey = plate ~= unit and TokenKey(unit) or nil
    if not guid then
        guid = (plateKey and knownGUID[plateKey]) or (ownKey and knownGUID[ownKey])
    end
    if guid then
        if plateKey then
            knownGUID[plateKey] = guid
        end
        if ownKey then
            knownGUID[ownKey] = guid
        end
        return guid
    end
    return plateKey or ownKey
end

--------------------------------------------------------------------------------
-- Auras
--------------------------------------------------------------------------------

-- Only effects the player applied are looked at: "debuff" is the player's
-- debuffs on an enemy, "buff" the player's buffs on themselves or on a friend.
local FILTERS = { debuff = "HARMFUL|PLAYER", buff = "HELPFUL|PLAYER" }
local MAX_AURAS = 60 -- how far a unit's auras are walked when they are listed

local function ReadIDList(list)
    local count = #list
    local ids = {}
    for i = 1, count do
        local id = list[i]
        if IsSecret(id) or type(id) ~= "number" then
            return count, nil
        end
        ids[id] = true
    end
    return count, ids
end

local function ReadAuraList(list)
    local count = #list
    local ids = {}
    for i = 1, count do
        local ok, id = pcall(Index, list[i], "auraInstanceID")
        if not ok or IsSecret(id) or type(id) ~= "number" then
            return count, nil
        end
        ids[id] = true
    end
    return count, ids
end

local function SampleWith(name, reader, unit, filter)
    local fn = C_UnitAuras[name]
    if type(fn) ~= "function" then
        return nil
    end
    local ok, list = pcall(fn, unit, filter)
    if not ok then
        Refused(name, list)
        return nil
    end
    if IsSecret(list) or type(list) ~= "table" then
        return nil
    end
    local ok2, count, ids = pcall(reader, list)
    if not ok2 or IsSecret(count) or type(count) ~= "number" then
        return nil
    end
    return { n = count, ids = ids }
end

--- Counts the player's own effects of one kind ("debuff" or "buff") on a unit
--- without looking at what they are, which the client may still allow while the
--- details are hidden.
--- Returns { n = count, ids = set of aura instance ids or nil } or nil.
function ns.SampleAuras(unit, kind)
    local filter = FILTERS[kind]
    if not C_UnitAuras or not filter then
        return nil
    end
    return SampleWith("GetUnitAuraInstanceIDs", ReadIDList, unit, filter)
        or SampleWith("GetUnitAuras", ReadAuraList, unit, filter)
end

local function ReadAura(aura)
    return aura.name, aura.duration, aura.expirationTime, aura.auraInstanceID
end

--- Lists the player's own effects of one kind on a unit by name:
--- name -> { duration, expires, id }. Returns nil when the client will not show
--- them, which is most of combat. The second return is false when the list
--- came back but some of its entries would not give their name.
function ns.ReadAuras(unit, kind)
    local byIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    local filter = FILTERS[kind]
    if type(byIndex) ~= "function" or not filter then
        return nil
    end
    local found, complete = {}, true
    for i = 1, MAX_AURAS do
        local ok, aura = pcall(byIndex, unit, i, filter)
        if not ok then
            Refused("GetAuraDataByIndex", aura)
            return nil
        end
        if IsSecret(aura) then
            return nil
        end
        if aura == nil then
            break
        end
        if type(aura) ~= "table" then
            return nil
        end
        local ok2, name, duration, expires, id = pcall(ReadAura, aura)
        if ok2 and not IsSecret(name) and type(name) == "string" then
            found[name] = {
                duration = PlainNumber(duration),
                expires = PlainNumber(expires),
                id = PlainNumber(id),
            }
        else
            complete = false -- an effect the client keeps secret even now
        end
    end
    return found, complete
end

--- Looks for one of the player's effects on a unit by name. Returns its details
--- when it is there and readable, false when the client answered with nothing
--- (absent, or hidden from addons), and nil when it would not answer at all.
function ns.ReadAuraByName(unit, name, kind)
    local byName = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
    local filter = FILTERS[kind]
    if type(byName) ~= "function" or not filter then
        return nil
    end
    local ok, aura = pcall(byName, unit, name, filter)
    if not ok then
        Refused("GetAuraDataBySpellName", aura)
        NameRead(name, "refused")
        return nil
    end
    if IsSecret(aura) then
        NameRead(name, "refused")
        return nil
    end
    if aura == nil then
        NameRead(name, "nothing")
        return false
    end
    if type(aura) ~= "table" then
        return nil
    end
    local ok2, found, duration, expires, id = pcall(ReadAura, aura)
    if not ok2 or IsSecret(found) or found ~= name then
        NameRead(name, "refused")
        return nil
    end
    NameRead(name, "found")
    return {
        duration = PlainNumber(duration),
        expires = PlainNumber(expires),
        id = PlainNumber(id),
    }
end

--------------------------------------------------------------------------------
-- Change signals
--
-- UNIT_AURA still fires in combat, but with a payload an addon must not read.
-- So one frame per unit token listens for it and passes on nothing but the fact
-- that the unit behind that token just had an effect added, renewed or removed.
-- Registering each frame for a single unit is what tells us whose effects
-- changed without looking at the event's arguments.
--------------------------------------------------------------------------------

local watchers = {} -- unit token -> the frame listening for it

--- Calls onChange(token, readable) whenever the effects on the unit behind
--- `token` change. `readable` says whether the client sent details an addon may
--- look at, which it does not do in combat. Returns false when the client will
--- not allow the watch.
function ns.WatchAuras(token, onChange)
    if watchers[token] then
        return true
    end
    local ok, frame = pcall(CreateFrame, "Frame")
    if not ok or type(frame) ~= "table" then
        return false
    end
    local registered, answer = pcall(frame.RegisterUnitEvent, frame, "UNIT_AURA", token)
    if not registered or answer == false then
        return false
    end
    frame:SetScript("OnEvent", function(_, _, _, details)
        onChange(token, not IsSecret(details))
    end)
    watchers[token] = frame
    return true
end

--- How the client treats one spell's aura: 0 never secret, 1 always secret,
--- 2 it depends on the situation. nil when it will not say.
function ns.SpellAuraSecrecy(spellID)
    local answer = Call(C_Secrets and C_Secrets.GetSpellAuraSecrecy, spellID)
    return PlainNumber(answer)
end

--- How far a spell reaches, in yards: little or nothing for one used at arm's
--- length or with no target at all. nil when the client will not say.
function ns.SpellRange(spellID)
    local info = Call(C_Spell and C_Spell.GetSpellInfo, spellID)
    if type(info) ~= "table" then
        return nil
    end
    local range = Field(info, "maxRange")
    if type(range) == "number" then
        return range
    end
    return nil
end

--- A name for the client build, so that what was learned about one build is
--- not taken for granted on the next.
function ns.BuildKey()
    local ok, version, build = pcall(GetBuildInfo)
    if not ok then
        return "unknown"
    end
    return tostring(Plain(version)) .. "." .. tostring(Plain(build))
end

--- The date and time as text, for the saved report.
function ns.WallClock()
    local text = Call(date, "%Y-%m-%d %H:%M:%S")
    return type(text) == "string" and text or "unknown"
end

--------------------------------------------------------------------------------
-- Spells
--------------------------------------------------------------------------------

function ns.SpellName(spell)
    local name = Call(C_Spell and C_Spell.GetSpellName, spell)
    if type(name) == "string" and name ~= "" then
        return name
    end
    local info = Call(C_Spell and C_Spell.GetSpellInfo, spell)
    if type(info) == "table" then
        name = Field(info, "name")
        if type(name) == "string" and name ~= "" then
            return name
        end
    end
    name = Call(GetSpellInfo, spell) -- clients older than 11.0
    if type(name) == "string" and name ~= "" then
        return name
    end
    return nil
end

function ns.SpellDescription(spellID)
    local text = Call(C_Spell and C_Spell.GetSpellDescription, spellID)
    if type(text) == "string" then
        return text
    end
    text = Call(GetSpellDescription, spellID)
    if type(text) == "string" then
        return text
    end
    return nil
end

--- True if the spell can be cast on enemies, false if not, nil if unknown.
function ns.SpellIsHarmful(spellID, name)
    local answer = Flag(C_Spell and C_Spell.IsSpellHarmful, spellID)
    if answer == nil then
        answer = Flag(IsHarmfulSpell, name)
    end
    return answer
end

function ns.SpellIsHelpful(spellID, name)
    local answer = Flag(C_Spell and C_Spell.IsSpellHelpful, spellID)
    if answer == nil then
        answer = Flag(IsHelpfulSpell, name)
    end
    return answer
end

--- True if the spell only ever affects the caster, false if it can affect
--- anyone else, nil if the client cannot say.
function ns.SpellIsSelfOnly(spellID)
    local answer = Flag(C_Spell and C_Spell.IsSelfBuff, spellID)
    if answer == nil then
        answer = Flag(SpellIsSelfBuff, spellID) -- its name before 12.0
    end
    return answer
end

function ns.SpellIsPassive(spellID)
    local answer = Flag(C_Spell and C_Spell.IsSpellPassive, spellID)
    if answer == nil then
        answer = Flag(IsPassiveSpell, spellID)
    end
    return answer == true
end

function ns.RequestSpellLoad(spellID)
    Call(C_Spell and C_Spell.RequestLoadSpellData, spellID)
end

--- The spell's own picture, as something a texture can show: a file id or a
--- path. Nil when the client will not say.
function ns.SpellIcon(spellID)
    local icon = Call(C_Spell and C_Spell.GetSpellTexture, spellID)
    if icon == nil then
        icon = Call(GetSpellTexture, spellID) -- clients older than 11.0
    end
    if (type(icon) == "number" and icon > 0) or (type(icon) == "string" and icon ~= "") then
        return icon
    end
    return nil
end

--- The spell that is really cast when this one is used: talents and forms can
--- swap one spell for another without changing what sits on the bar.
function ns.OverrideSpell(spellID)
    local override = Call(C_Spell and C_Spell.GetOverrideSpell, spellID)
    if type(override) ~= "number" or override <= 0 then
        override = Call(FindSpellOverrideByID, spellID)
    end
    if type(override) == "number" and override > 0 then
        return override
    end
    return spellID
end

--------------------------------------------------------------------------------
-- Action bars
--------------------------------------------------------------------------------

--- The action slot a button currently shows.
function ns.ButtonSlot(button)
    local slot = Field(button, "action")
    if type(slot) == "number" and slot > 0 then
        return slot
    end
    slot = Field(button, "_state_action") -- LibActionButton
    if type(slot) == "number" and slot > 0 then
        return slot
    end
    slot = Call(Field(button, "GetAttribute"), button, "action")
    if type(slot) == "number" and slot > 0 then
        return slot
    end
    return nil
end

--- The spell an action slot casts, for a spell on the bar or a macro that casts one.
function ns.SlotSpell(slot)
    if type(GetActionInfo) ~= "function" then
        return nil
    end
    local ok, actionType, id, subType = pcall(GetActionInfo, slot)
    if not ok or IsSecret(actionType) or IsSecret(id) or IsSecret(subType) then
        return nil
    end
    if actionType == "spell" then
        if subType ~= "assistedcombat" and type(id) == "number" and id > 0 then
            return id
        end
        return nil
    end
    if actionType == "macro" then
        -- Newer clients report the macro's spell directly, older ones the macro index.
        if subType == "spell" and type(id) == "number" and ns.SpellName(id) then
            return id
        end
        local spellID = Call(GetMacroSpell, id)
        if type(spellID) == "number" and spellID > 0 then
            return spellID
        end
        spellID = Call(C_ActionBar and C_ActionBar.GetSpell, slot)
        if type(spellID) == "number" and spellID > 0 then
            return spellID
        end
    end
    return nil
end

--- Whether the game would let the action in a slot be used right now, as far as
--- it tells an addon: usable, inRange. Each is true, false, or nil when the game
--- will not say or the question does not come into it.
---   usable   false while the game dims the button: not enough rage, mana or
---            energy, the wrong stance, a target the skill is no use on
---   inRange  false while the target is out of the skill's reach, which
---            includes too close for a skill with a shortest range
--- A cooldown is part of neither answer: the game can keep cooldowns from
--- addons during a fight.
function ns.ActionUsable(slot)
    local bar = C_ActionBar
    local usable = Flag(bar and bar.IsUsableAction or IsUsableAction, slot)
    local range, known = Call(bar and bar.IsActionInRange or IsActionInRange, slot)
    local inRange = nil
    if known and range ~= nil then
        inRange = not (range == false or range == 0) -- older clients answer 1 and 0
    end
    return usable, inRange
end
