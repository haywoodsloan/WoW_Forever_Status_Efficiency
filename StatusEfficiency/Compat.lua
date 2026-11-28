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
ns.VERSION = "0.5.5"

local pcall, type, pairs, tostring = pcall, type, pairs, tostring
local setmetatable, max, min = setmetatable, math.max, math.min

local PREFIX = "|cff66ccffStatus Efficiency|r: "

function ns.Print(text)
    print(PREFIX .. text)
end

-- Replaced by Core.lua once it loads.
function ns.Log() end
function ns.Note() end
function ns.NoteOthers() end
function ns.NoteLate() end
function ns.NoteRefusal() end
function ns.NoteImmune() end
function ns.NoteTaken() end
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

ns.IsSelf = IsSelf

--- Whether two unit tokens show the same unit: true, false, or nil when the
--- game will not say.
function ns.SameUnit(unit, other)
    local same = Flag(UnitIsUnit, unit, other)
    if same ~= nil then
        return same
    end
    local guid, otherGuid = ReadableGUID(unit), ReadableGUID(other)
    if guid and otherGuid then
        return guid == otherGuid
    end
    return nil
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
-- Your group
--
-- The icons stay on all through a fight, and a fight is also one that someone
-- in your party or raid is in close by. Whether a member is in combat is a
-- plain answer in the client's documentation. How far away they are is not:
-- the game's test for a group member being in range answers with secret
-- values (UnitInRange). So "close by" is taken to be close enough for the
-- game to show them to you, which is about a hundred yards (UnitIsVisible),
-- and the range test is only asked where that one will not answer.
--------------------------------------------------------------------------------

local PARTY_TOKENS, RAID_TOKENS = {}, {}
for i = 1, 4 do
    PARTY_TOKENS[i] = "party" .. i
end
for i = 1, 40 do
    RAID_TOKENS[i] = "raid" .. i
end
ns.partyTokens, ns.raidTokens = PARTY_TOKENS, RAID_TOKENS

--- True when your group is a raid: its members then go by raid names, and
--- the ones in your own party of five by party names as well.
function ns.InRaid()
    return Flag(IsInRaid) == true
end

--- The name a group member's casts are heard under (see ns.WatchCasts) for
--- the unit behind any token: a raid name in a raid, a party name otherwise.
--- Nil for a unit that is not in your group, for you, and when the game will
--- not say.
function ns.GroupToken(unit)
    if type(unit) ~= "string" then
        return nil
    end
    local raid = ns.InRaid()
    if unit:find(raid and "^raid%d+$" or "^party%d$") then
        return not IsSelf(unit) and unit or nil
    end
    local tokens = raid and RAID_TOKENS or PARTY_TOKENS
    for i = 1, #tokens do
        local token = tokens[i]
        if ns.SameUnit(unit, token) == true then
            return not IsSelf(token) and token or nil
        end
    end
    return nil
end

--- Whether a group member is close by. Nil when the game will not say.
local function Near(unit)
    local visible = Flag(UnitIsVisible, unit)
    if visible ~= nil then
        return visible
    end
    local ok, inRange, checked = pcall(UnitInRange, unit)
    if ok and not IsSecret(inRange) and not IsSecret(checked) and checked then
        return inRange and true or false
    end
    return nil
end

--- What the members behind a list of unit tokens are doing, added to what was
--- found so far. See ns.GroupState for the words.
local function Members(tokens, state)
    for i = 1, #tokens do
        local unit = tokens[i]
        local fighting = Flag(UnitAffectingCombat, unit)
        if fighting == true then
            if not IsSelf(unit) then
                local near = Near(unit)
                if near == true then
                    return "fighting"
                elseif near == false then
                    if state ~= "unsaid" then
                        state = "far"
                    end
                else
                    state = "unsaid"
                end
            end
        elseif fighting == nil then
            if ns.Exists(unit) and not IsSelf(unit) then
                state = "unsaid"
            end
        elseif state == "alone" and ns.Exists(unit) and not IsSelf(unit) then
            state = "quiet"
        end
    end
    return state
end

--- What your party or raid is doing, in one word:
---   "fighting"  someone in it is in combat close by
---   "far"       someone is in combat, but nobody close by
---   "quiet"     nobody in it is in combat
---   "unsaid"    the game will not say it of someone: whether they are in
---               combat, or whether they are close by
---   "alone"     you are in no group
--- Only the first makes a fight of yours out of theirs.
function ns.GroupState()
    local state = Members(PARTY_TOKENS, "alone")
    if state ~= "fighting" and Flag(IsInRaid) ~= false then
        state = Members(RAID_TOKENS, state)
    end
    return state
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

--- What kind of creature a unit is, so that what is learned of one Fire
--- Elemental holds for the next one. Returns the kind and the creature's name
--- for showing, where that is told. The kind is "#" and the game's number
--- for the creature: read out of `key` where that is the game's own name for
--- the unit (see ns.UnitKey), which stays known after the client hides it,
--- and asked for otherwise. Where no number is told, the creature's name
--- stands in. Nil for a player, whose immunities are never their kind's, and
--- for a unit the game will not name at all: the second answer is then
--- "player" or "hidden".
function ns.UnitKind(unit, key)
    local name = PlainString((Call(UnitName, unit)))
    if name == "" then
        name = nil
    end
    local id
    if type(key) == "string" then
        local what, number = key:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
        if what == "Creature" or what == "Vehicle" or what == "Pet" then
            id = number
        end
    end
    if not id then
        local number = PlainNumber((Call(UnitCreatureID, unit)))
        if number and number > 0 then
            id = tostring(number)
        end
    end
    if id then
        return "#" .. id, name
    end
    local player = Flag(UnitIsPlayer, unit)
    if name and player == false then
        return name, name
    end
    return nil, player == true and "player" or "hidden"
end

--------------------------------------------------------------------------------
-- Enemy nameplates, shown or not
--
-- The enemies around you are read from their nameplates. Whether the game
-- shows those is a setting of its own (the console variable
-- nameplateShowEnemies), which a key flips: V, unless it was bound to another.
-- With it off there is no nameplate to read anything from.
--
-- An addon may switch it on, but not during a fight: it is one of the settings
-- the game calls secure, and trying then is refused with an error the player
-- is shown. So it is never tried in a fight.
--------------------------------------------------------------------------------

local PLATES_SETTING = "nameplateShowEnemies"

-- What the addon can be told to do when enemy nameplates are off (see "With
-- no nameplates to go by" in Core.lua), in the order they are offered.
ns.NAMEPLATE_CHOICES = { "on", "tell", "off", on = true, tell = true, off = true }

--- Whether the game is set to show enemy nameplates: true, false, or nil
--- when it will not say.
function ns.EnemyPlates()
    local value = Call(C_CVar and C_CVar.GetCVar or GetCVar, PLATES_SETTING)
    if value == "1" then
        return true
    elseif value == "0" then
        return false
    end
    return nil
end

--- Whether the game calls that setting secure, which is what keeps an addon
--- from changing it in a fight: true, false, or nil when it will not say.
function ns.PlatesSettingSecure()
    local get = C_CVar and C_CVar.GetCVarInfo
    if type(get) ~= "function" then
        return nil
    end
    local ok, _, _, _, _, _, secure = pcall(get, PLATES_SETTING)
    if not ok or IsSecret(secure) or type(secure) ~= "boolean" then
        return nil
    end
    return secure
end

--- Switches enemy nameplates on in the game's settings. Not in a fight,
--- unless the game says plainly that the setting is not a secure one. Says
--- whether the game shows them afterwards.
function ns.ShowEnemyPlates()
    if ns.InCombat() and ns.PlatesSettingSecure() ~= false then
        return false
    end
    local ok, err = pcall(C_CVar and C_CVar.SetCVar or SetCVar, PLATES_SETTING, "1")
    if not ok then
        Refused("SetCVar", err)
    end
    return ns.EnemyPlates() == true
end

--- The key that shows or hides enemy nameplates, as the game writes it ("V"),
--- or nil when none is bound or the game will not say.
function ns.PlatesKey()
    local key = PlainString((Call(GetBindingKey, "NAMEPLATES")))
    if key and key ~= "" then
        return key
    end
    return nil
end

--- True for the game's report that the setting above changed (CVAR_UPDATE),
--- and for one that does not say which setting it is about.
function ns.IsPlatesSetting(name)
    name = PlainString(name)
    return name == nil or name == PLATES_SETTING
end

--- The kind of place you are in, in the game's word: "none" for the open
--- world, "party" for a dungeon, "raid", "pvp", "arena", "scenario". Nil when
--- the game will not say.
function ns.InstanceKind()
    local ok, _, kind = pcall(IsInInstance)
    if not ok then
        return nil
    end
    return PlainString(kind)
end

-- The other names the game gives an enemy, for when there is no nameplate to
-- go by: the enemy it picks for you, your focus, the one under the mouse and
-- the targets of the four others in your party. Each comes with the event that
-- tells when it moves to another unit; one whose event this client does not
-- have is not used, since what was learned through it would be put down to
-- whoever it points at next.
ns.handleTokens = { "softenemy", "focus", "mouseover" }
ns.handleEvents = {
    softenemy = "PLAYER_SOFT_ENEMY_CHANGED",
    focus = "PLAYER_FOCUS_CHANGED",
    mouseover = "UPDATE_MOUSEOVER_UNIT",
}
ns.memberTargets = {} -- "party2" -> "party2target"
for i = 1, 4 do
    local token = "party" .. i .. "target"
    ns.handleTokens[#ns.handleTokens + 1] = token
    ns.handleEvents[token] = "UNIT_TARGET"
    ns.memberTargets["party" .. i] = token
end

--------------------------------------------------------------------------------
-- Auras
--------------------------------------------------------------------------------

-- The effects the player applied: "debuff" is the player's debuffs on an
-- enemy, "buff" the player's buffs on themselves or on a friend.
local FILTERS = { debuff = "HARMFUL|PLAYER", buff = "HELPFUL|PLAYER" }
-- Everyone's effects of a kind. They are read as well for the sake of a spell
-- whose effect a unit carries only once, whoever put it there: another
-- player's copy then does what yours would.
local BROAD = { debuff = "HARMFUL", buff = "HELPFUL" }
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
    return aura.name, aura.duration, aura.expirationTime, aura.auraInstanceID, aura.applications
end

--- The unit that put an effect there, by the name the game gives it, where it
--- gives one. It is asked for apart from the rest, so that a client which
--- keeps it back still has the effect read.
local function SourceOf(aura)
    return PlainString(Field(aura, "sourceUnit"))
end

--- True when the effect `a` will be on the unit for longer than `b`. One with
--- no end time outlasts every other.
local function Outlasts(a, b)
    local mine, theirs = a.expires, b.expires
    if not mine or mine <= 0 then
        return theirs ~= nil and theirs > 0
    end
    return theirs ~= nil and theirs > 0 and mine > theirs
end

--- Lists the effects of one kind on a unit by name: the player's own, or with
--- `anyone` set those of every player (the player's among them).
--- name -> { duration, expires, id, stacks, source }, where `stacks` is how
--- many times over the effect is on the unit (0 for one that does not stack)
--- and `source`, given only with `anyone`, is the unit that put it there.
--- Returns nil when the client will not show them, which is most of combat.
--- The second return is false when the list came back but some of its entries
--- would not give their name.
function ns.ReadAuras(unit, kind, anyone)
    local byIndex = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
    local filter = (anyone and BROAD or FILTERS)[kind]
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
        local ok2, name, duration, expires, id, stacks = pcall(ReadAura, aura)
        if ok2 and not IsSecret(name) and type(name) == "string" then
            local entry = {
                duration = PlainNumber(duration),
                expires = PlainNumber(expires),
                id = PlainNumber(id),
                stacks = PlainNumber(stacks),
                source = anyone and SourceOf(aura) or nil,
            }
            -- Several players can each have put an effect of one name on the
            -- unit: the one that will be there longest is the one that counts.
            local other = anyone and found[name]
            if not other or Outlasts(entry, other) then
                found[name] = entry
            end
        else
            complete = false -- an effect the client keeps secret even now
        end
    end
    return found, complete
end

--- Looks for an effect on a unit by name: one of the player's, or with
--- `anyone` set one of any player's. Returns its details when it is there and
--- readable, false when the client answered with nothing (absent, or hidden
--- from addons), and nil when it would not answer at all.
function ns.ReadAuraByName(unit, name, kind, anyone)
    local byName = C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName
    local filter = (anyone and BROAD or FILTERS)[kind]
    if type(byName) ~= "function" or not filter then
        return nil
    end
    -- What asking after everyone's effects gave is kept apart in the report.
    local asked = anyone and (name .. ", anyone's") or name
    local ok, aura = pcall(byName, unit, name, filter)
    if not ok then
        Refused("GetAuraDataBySpellName", aura)
        NameRead(asked, "refused")
        return nil
    end
    if IsSecret(aura) then
        NameRead(asked, "refused")
        return nil
    end
    if aura == nil then
        NameRead(asked, "nothing")
        return false
    end
    if type(aura) ~= "table" then
        return nil
    end
    local ok2, found, duration, expires, id, stacks = pcall(ReadAura, aura)
    if not ok2 or IsSecret(found) or found ~= name then
        NameRead(asked, "refused")
        return nil
    end
    NameRead(asked, "found")
    return {
        duration = PlainNumber(duration),
        expires = PlainNumber(expires),
        id = PlainNumber(id),
        stacks = PlainNumber(stacks),
        source = anyone and SourceOf(aura) or nil,
    }
end

--------------------------------------------------------------------------------
-- Change signals
--
-- UNIT_AURA still fires in combat, but what it carries is sealed: the game's
-- own documentation marks the event as producing secret values while auras are
-- restricted. So one frame per unit token listens for it and passes on the
-- fact that the unit behind that token just had an effect added, renewed or
-- removed, and which of those it was where the client lets that be seen.
-- Registering each frame for a single unit is what tells us whose effects
-- changed without looking at the event's arguments.
--
-- What exactly a client hands over is worth knowing, because the more of it
-- is readable, the better a cast can be told from every other change. So the
-- first reports of a session are also described, in words, for the saved
-- report. Nothing is ever read out of a secret value for that: each field is
-- only asked what kind of thing it is.
--------------------------------------------------------------------------------

local issecrettable = issecrettable -- nil on clients without secret tables
local canaccesstable = canaccesstable

local watchers = {} -- unit token -> the frame listening for it
local shapesLeft = 60 -- reports still to be described this session

--- What a value is, in a word, without looking into a secret one.
local function Kind(value)
    if IsSecret(value) then
        return "secret"
    end
    if value == nil then
        return "nil"
    end
    return type(value)
end

--- Reads tbl[key] and says what kind of thing came back. A secret value is
--- never handed on, only named.
local function Peek(tbl, key)
    local ok, value = pcall(Index, tbl, key)
    if not ok then
        return nil, "refused"
    end
    local kind = Kind(value)
    if kind == "secret" then
        return nil, kind
    end
    return value, kind
end

local AURA_FIELDS = {
    { "auraInstanceID", "id" }, { "isFromPlayerOrPlayerPet", "mine" }, { "isHarmful", "harmful" },
    { "spellId", "spell" },
}

--- Describes the first entry of a list in the details: a number for a list of
--- instance ids, the readable fields for a list of effects.
local function FirstOf(list, effects)
    local first, kind = Peek(list, 1)
    if kind ~= "table" or not effects then
        return "[" .. kind .. "]"
    end
    local parts = {}
    for i = 1, #AURA_FIELDS do
        local _, what = Peek(first, AURA_FIELDS[i][1])
        parts[i] = AURA_FIELDS[i][2] .. " " .. what
    end
    return "[" .. table.concat(parts, ", ") .. "]"
end

local DETAIL_FIELDS = {
    { "isFullUpdate", "full" }, { "addedAuras", "added" }, { "updatedAuraInstanceIDs", "updated" },
    { "removedAuraInstanceIDs", "removed" },
}

--- Describes what the client handed over as the details of a change.
local function Shape(details)
    local kind = Kind(details)
    if kind ~= "table" then
        return kind == "nil" and "nothing" or kind
    end
    if Flag(canaccesstable, details) == false then
        return "a table addons may not touch"
    end
    local parts = {}
    for i = 1, #DETAIL_FIELDS do
        local value, what = Peek(details, DETAIL_FIELDS[i][1])
        if what == "table" then
            what = "list " .. FirstOf(value, i == 2)
        end
        parts[i] = DETAIL_FIELDS[i][2] .. " " .. what
    end
    return (Flag(issecrettable, details) and "sealed table: " or "table: ") .. table.concat(parts, ", ")
end

--- True when a list in the details has something in it, false when it is not
--- there or is empty, nil when that cannot be told. A secret value counts as
--- something: the client only hands one over where there is a list to hide.
local function Listed(details, field)
    local value, kind = Peek(details, field)
    if kind == "secret" then
        return true
    elseif kind == "nil" then
        return false
    elseif kind ~= "table" then
        return nil
    end
    local _, first = Peek(value, 1)
    if first == "refused" then
        return nil
    end
    return first ~= "nil"
end

--- What kind of change the details of a report speak of, where they say:
--- `came` is true when an effect was added or renewed, `went` when one was
--- taken away. Both are nil when the details do not tell.
---
--- The game's documentation has the details sealed in combat, every field a
--- secret value. The client this was checked against (build 71139) does
--- something else: the details are an ordinary table whose three lists, of
--- effects added, renewed and removed, each read as a secret value where
--- there is something in them and as nil where there is not. What is in a
--- list stays out of reach. That it is there does not, and it settles the one
--- thing a cast is judged by: a report that only took effects away cannot be
--- a cast landing. Nothing is asked of a secret value but whether it is one.
---
--- Details that say everything at once say nothing: a full update, no list
--- at all, or all three lists, which is also what a client that answers
--- "secret" for every field looks like.
---
--- A third value, `fresh`, tells an effect arriving on a unit that did not
--- carry it from one being put on top of itself: true when the report only
--- added effects, false when it renewed some and added none, nil when it did
--- both or does not say. That is what a stack is counted by. The first cast
--- of a stacking skill adds its effect, and each one after renews it.
local function Told(details)
    if IsSecret(details) or type(details) ~= "table" then
        return nil
    end
    if Flag(issecrettable, details) or Flag(canaccesstable, details) == false then
        return nil
    end
    local full, fullKind = Peek(details, "isFullUpdate")
    if fullKind == "refused" or full == true then
        return nil
    end
    local added = Listed(details, "addedAuras")
    local updated = Listed(details, "updatedAuraInstanceIDs")
    local removed = Listed(details, "removedAuraInstanceIDs")
    if added == nil or updated == nil or removed == nil then
        return nil
    end
    local came = added or updated
    if came == removed and (not came or (added and updated)) then
        return nil -- nothing listed, or everything
    end
    local fresh = nil
    if added and not updated and not removed then
        fresh = true
    elseif updated and not added then
        fresh = false
    end
    return came, removed, fresh
end

--- Calls onChange(token, shape, came, went, fresh) whenever the effects on
--- the unit behind `token` change. `shape` describes the details the client
--- sent along: "secret" when they are one secret value, a fuller description
--- for the first reports of a session, and "unread" after that. `came`,
--- `went` and `fresh` say what kind of change it was, where the details tell
--- (see Told above), and are all nil where they do not. Returns false when
--- the client will not allow the watch.
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
        local shape = "unread"
        if IsSecret(details) then
            shape = "secret"
        elseif shapesLeft > 0 then
            shapesLeft = shapesLeft - 1
            local described, text = pcall(Shape, details)
            shape = described and text or "could not be described"
        end
        local told, came, went, fresh = pcall(Told, details)
        if not told then
            came, went, fresh = nil, nil, nil
        end
        onChange(token, shape, came, went, fresh)
    end)
    watchers[token] = frame
    return true
end

--------------------------------------------------------------------------------
-- Casts by the people in your group
--
-- An effect that a unit carries only once, whoever put it there, can be put
-- there by someone else during a fight, when nothing on the unit can be read.
-- What is left to go on is that member's cast being announced in the same
-- moment as the unit reports a change. As with the change reports, one frame
-- per unit token listens, so that whose cast it was never has to be read out
-- of the event. Which spell it was does: the game's documentation lets a
-- client keep that secret, and then nothing is known but that they cast.
--------------------------------------------------------------------------------

local castWatchers = {} -- unit token -> the frame listening for it

--- Calls onCast(token, spellID) whenever the unit behind `token` finishes a
--- cast. `spellID` is nil when the client keeps it secret. Returns false when
--- the client will not allow the watch.
function ns.WatchCasts(token, onCast)
    if castWatchers[token] then
        return true
    end
    local ok, frame = pcall(CreateFrame, "Frame")
    if not ok or type(frame) ~= "table" then
        return false
    end
    local registered, answer = pcall(frame.RegisterUnitEvent, frame, "UNIT_SPELLCAST_SUCCEEDED", token)
    if not registered or answer == false then
        return false
    end
    frame:SetScript("OnEvent", function(_, _, _, _, spellID)
        onCast(token, PlainNumber(spellID))
    end)
    castWatchers[token] = frame
    return true
end

--------------------------------------------------------------------------------
-- What the game says an attack did
--
-- For every unit the game announces what an attack or a spell just did to it:
-- "WOUND", "MISS", "DODGE", "PARRY", "RESIST", "IMMUNE" and so on. Its own
-- unit frames print that word over the portrait. Its documentation marks
-- only the amount as hidden from addons in a fight, not the word. It is the
-- one thing an addon is told about a unit being immune to something. Whose
-- attack it was is not said. As with the change reports, one frame per unit
-- token listens, so that whose unit it was never has to be read out of the
-- event.
--------------------------------------------------------------------------------

local combatWatchers = {} -- unit token -> the frame listening for it

--- Calls onWord(token, word, flag) whenever the game says what an attack or
--- a spell did to the unit behind `token`. `word` is nil when the client
--- keeps it secret, and `flag` is what it adds to some words ("CRITICAL",
--- "GLANCING"), where it may be read. Returns false when the client will not
--- allow the watch.
function ns.WatchCombat(token, onWord)
    if combatWatchers[token] then
        return true
    end
    local ok, frame = pcall(CreateFrame, "Frame")
    if not ok or type(frame) ~= "table" then
        return false
    end
    local registered, answer = pcall(frame.RegisterUnitEvent, frame, "UNIT_COMBAT", token)
    if not registered or answer == false then
        return false
    end
    frame:SetScript("OnEvent", function(_, _, _, word, flag)
        onWord(token, PlainString(word), PlainString(flag))
    end)
    combatWatchers[token] = frame
    return true
end

--- How the client treats one spell's aura: 0 never secret, 1 always secret,
--- 2 it depends on the situation. nil when it will not say.
function ns.SpellAuraSecrecy(spellID)
    local answer = Call(C_Secrets and C_Secrets.GetSpellAuraSecrecy, spellID)
    return PlainNumber(answer)
end

--- How many times over a spell's effect can be on one unit, as the game's
--- own data has it: 0 or 1 for an effect that does not stack. Nil when the
--- client will not say, which its documentation allows for while effect
--- details are hidden, and when it cannot be asked at all.
function ns.SpellMaxStacks(spellID)
    local most = Call(C_Spell and C_Spell.GetSpellMaxCumulativeAuraApplications, spellID)
    return PlainNumber(most)
end

--- How far a spell reaches, in yards: little or nothing for one used at arm's
--- length or with no target at all. nil when the client will not say. The
--- second answer is how near its target may be at the least: 0 for most.
function ns.SpellRange(spellID)
    local info = Call(C_Spell and C_Spell.GetSpellInfo, spellID)
    if type(info) ~= "table" then
        return nil
    end
    local range = Field(info, "maxRange")
    if type(range) == "number" then
        local least = Field(info, "minRange")
        return range, type(least) == "number" and least > 0 and least or 0
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

--- Whether the game has a piece of art by this name: true, false, or nil when
--- the client cannot be asked.
function ns.AtlasExists(atlas)
    local art = C_Texture
    local exists = Flag(art and art.GetAtlasExists, atlas)
    if exists == nil then
        -- Clients from before that call describe the art, or give nothing for none.
        local info, known = Call(art and art.GetAtlasInfo, atlas)
        if known then
            exists = info ~= nil
        end
    end
    return exists
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

--- The picture an action slot shows, likewise. It stands in for a spell's own
--- picture where the client has none to give for the spell.
function ns.SlotIcon(slot)
    local icon = Call(GetActionTexture, slot)
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

--------------------------------------------------------------------------------
-- Whether a skill can be used right now
--------------------------------------------------------------------------------
--
-- The game is asked three ways, each only when the one before gave no answer
-- an addon may read: about the action in the slot, about the spell it casts,
-- and at last the button is looked at, which the game's own code has painted
-- for the player in colours that say the same.

-- Who answered, as /se debug and the saved report have it.
local BAR, SPELL, LOOK = "bar", "spell", "look"

--- Asks a call of the "can it be used" kind. Returns usable, lacking: each
--- true, false, or nil when the call is not there, failed or kept it secret.
local function AskUsable(ask, id)
    if type(ask) ~= "function" then
        return nil, nil
    end
    local ok, first, second = pcall(ask, id)
    if not ok then
        return nil, nil
    end
    local usable, lacking = nil, nil
    -- Older clients answer 1 and nothing where newer ones say true and false.
    if not IsSecret(first) then
        usable = first and true or false
    end
    if not IsSecret(second) then
        lacking = second and true or false
    end
    return usable, lacking
end

--- Asks a call of the "is it in reach" kind. Returns inRange, known. A known
--- nil is the game saying that reach does not come into it: there is nobody
--- to judge it on, or the skill has no range.
local function AskRange(ask, id, unit)
    if type(ask) ~= "function" then
        return nil, false
    end
    local ok, range = false, nil
    if unit and unit ~= "target" then
        -- Someone other than your target: say who. A call that takes no unit,
        -- or has nothing to say of this one, is asked the plain way after all.
        ok, range = pcall(ask, id, unit)
        if ok and IsSecret(range) then
            return nil, false
        end
        if range == nil then
            ok = false
        end
    end
    if not ok then
        ok, range = pcall(ask, id)
    end
    if not ok or IsSecret(range) then
        return nil, false
    end
    if range == nil then
        return nil, true
    end
    return not (range == false or range == 0), true -- older clients answer 1 and 0
end

--- Asks a call of the "is it in reach" kind about one unit by name, and takes
--- no answer about anybody else: true, false, or nil when the call is not
--- there, fails, keeps it secret or has nothing to say of that unit.
local function AskReach(ask, id, unit)
    if type(ask) ~= "function" then
        return nil
    end
    local ok, range = pcall(ask, id, unit)
    if not ok or IsSecret(range) or range == nil then
        return nil
    end
    return not (range == false or range == 0)
end

--- Whether a unit is within the range of the skill in an action slot: true,
--- false (too far, or too close for a skill with a shortest range), or nil
--- when the game does not say. The action bar is asked, then the spell, each
--- with the unit named. Unlike ns.ActionUsable this never falls back to the
--- plain question, which is about your target: an answer about somebody else
--- is worse than none. A client whose calls take no unit at all may still
--- answer about your target whoever is named, so what is said of anybody
--- else needs proof before it is believed (see "Enemies out of reach" in
--- Core.lua).
function ns.UnitInReach(slot, spellID, unit)
    local bar, book = C_ActionBar, C_Spell
    local answer = nil
    if slot then
        answer = AskReach(bar and bar.IsActionInRange or IsActionInRange, slot, unit)
    end
    if answer == nil and spellID then
        answer = AskReach(book and book.IsSpellInRange, spellID, unit)
    end
    return answer
end

--- The colour a part of a button is drawn in, when that can be read.
local function Tint(region)
    local get = Field(region, "GetVertexColor")
    if type(get) ~= "function" then
        return nil
    end
    local ok, r, g, b = pcall(get, region)
    if not ok then
        return nil
    end
    r, g, b = PlainNumber(r), PlainNumber(g), PlainNumber(b)
    if not (r and g and b) then
        return nil
    end
    return r, g, b
end

--- What a button shows, as the game's own bars and the bar addons that copy
--- them paint it: the picture white while the skill can be used, blue while
--- rage, mana or energy is short, grey while it cannot be used for any other
--- reason, and the key's name (on some bars the picture) red while the target
--- is out of reach. Returns usable, lacking, far: each nil when the button
--- does not show it in colours an addon may read.
local function ButtonLook(button)
    local usable, lacking, far = nil, nil, nil
    local r, g, b = Tint(Field(button, "icon"))
    if r then
        if r >= 0.95 and g >= 0.95 and b >= 0.95 then
            usable, lacking = true, false
        elseif b >= 0.9 and r <= 0.7 and g <= 0.7 then
            usable, lacking = false, true
        elseif r >= 0.7 and g <= 0.4 and b <= 0.4 then
            far = true
        elseif r <= 0.6 and g <= 0.6 and b <= 0.6 and max(r, g, b) - min(r, g, b) <= 0.1 then
            usable, lacking = false, false
        end
    end
    r, g, b = Tint(Field(button, "HotKey"))
    if r then
        if r >= 0.9 and g <= 0.35 and b <= 0.35 then
            far = true
        elseif far == nil then
            far = false
        end
    end
    return usable, lacking, far
end

-- How far the spell and the look are believed. Either can say "cannot be
-- used" of a skill for good: of a spell the game does not know by the number
-- the bar gives, or on a bar that paints every picture dim. An icon must not
-- vanish for good on such a say-so, so a plain "cannot be used" from either
-- counts only once that source has been right. While the action bar answers,
-- each is checked against it: one that agrees with it on something other than
-- a plain "no" is believed from then on, one that contradicts it three times
-- running is never asked again, and once two spells (or two buttons) have
-- been proved this way the rest are believed too. Where the action bar never
-- answers, a source is believed about a skill once it has said "yes" or
-- "short of rage" about it, which a source that says "no" to everything
-- never does.
local PROOF, DOUBTS = 2, 3

local function Trust()
    return { keys = setmetatable({}, { __mode = "k" }), proven = 0 }
end

local spellTrust, lookTrust = Trust(), Trust() -- by spell id, by button

local function Believed(trust, key)
    local state = trust.keys[key]
    return state == true or (state == nil and trust.proven >= PROOF)
end

--- Checks what a source says against what the action bar just said.
local function Check(trust, key, usable, lacking, barUsable, barLacking)
    if usable == nil then
        return
    end
    local keys = trust.keys
    local agrees = usable == barUsable
        and (usable or lacking == nil or barLacking == nil or lacking == barLacking)
    if not agrees then
        local doubts = (keys[key] or 0) + 1
        keys[key] = doubts < DOUBTS and doubts or false
    elseif usable or lacking then
        keys[key] = true
        trust.proven = trust.proven + 1
    else
        keys[key] = nil -- both say a plain "no": that proves nothing, and clears nothing but the doubts
    end
end

--- Takes what a source says when the action bar has not answered: nothing
--- from one that was caught out, and no plain "cannot be used" from one that
--- has not been right about this skill yet.
local function Heard(trust, key, usable, lacking)
    local keys = trust.keys
    if usable == nil or keys[key] == false then
        return nil, nil
    end
    if usable or lacking then
        keys[key] = true
    elseif lacking == false and not Believed(trust, key) then
        return nil, nil
    end
    return usable, lacking
end

--- Adds what another source says to the answer so far: all of it where there
--- was none, and only the reason where "cannot be used" came without one.
local function Merge(usable, lacking, how, can, short, source)
    if usable == nil then
        if can ~= nil then
            return can, short, source
        end
    elseif usable == false and lacking == nil and can == false and short ~= nil then
        return false, short, how
    end
    return usable, lacking, how
end

--- Whether the game would let the skill on a button be used right now, as far
--- as it tells an addon: usable, inRange, lacking, and then who answered each
--- of the two questions ("bar", "spell" or "look"; nil for nobody). The first
--- three are true, false, or nil when the game will not say or the question
--- does not come into it.
---   usable   false while the game dims the button: not enough rage, mana or
---            energy, the wrong stance, a target the skill is no use on
---   inRange  false while `unit`, whom the skill would go to, is out of its
---            reach, which includes too close for a skill with a shortest
---            range. Never asked for "player": you are in reach of yourself.
---   lacking  true when rage, mana or energy is what is missing: the game's
---            own buttons turn blue for that, and grey for everything else
--- A cooldown is part of none of them: the game can keep cooldowns from
--- addons during a fight.
function ns.ActionUsable(slot, unit, spellID, button)
    local bar, book = C_ActionBar, C_Spell
    local askSpell = book and book.IsSpellUsable
    local usable, lacking = AskUsable(bar and bar.IsUsableAction or IsUsableAction, slot)
    local how = usable ~= nil and BAR or nil
    local looked, lookUsable, lookLacking, lookFar = false, nil, nil, nil

    if usable == nil or (usable == false and lacking == nil) then
        -- No answer, or "no" without the reason: the spell, then the button.
        if spellID then
            local can, short = Heard(spellTrust, spellID, AskUsable(askSpell, spellID))
            usable, lacking, how = Merge(usable, lacking, how, can, short, SPELL)
        end
        if button and (usable == nil or (usable == false and lacking == nil)) then
            looked = true
            lookUsable, lookLacking, lookFar = ButtonLook(button)
            local can, short = Heard(lookTrust, button, lookUsable, lookLacking)
            usable, lacking, how = Merge(usable, lacking, how, can, short, LOOK)
        end
    else
        -- The action bar told it all. The other two are held against it until
        -- it is settled whether they can stand in for it.
        local state = spellID and spellTrust.keys[spellID]
        if spellID and state ~= true and state ~= false then
            local can, short = AskUsable(askSpell, spellID)
            Check(spellTrust, spellID, can, short, usable, lacking)
        end
        state = button and lookTrust.keys[button]
        if button and state ~= true and state ~= false then
            looked = true
            lookUsable, lookLacking, lookFar = ButtonLook(button)
            Check(lookTrust, button, lookUsable, lookLacking, usable, lacking)
        end
    end

    local inRange, howRange = nil, nil
    if unit ~= "player" then
        local known
        inRange, known = AskRange(bar and bar.IsActionInRange or IsActionInRange, slot, unit)
        if known then
            howRange = BAR
        elseif spellID then
            inRange, known = AskRange(book and book.IsSpellInRange, spellID, unit)
            if known then
                howRange = SPELL
            end
        end
        if not known and button then
            if not looked then
                lookUsable, lookLacking, lookFar = ButtonLook(button)
            end
            if lookFar ~= nil then
                howRange = LOOK
                if lookFar then
                    inRange = false
                end
            end
        end
    end
    return usable, inRange, lacking, how, howRange
end
