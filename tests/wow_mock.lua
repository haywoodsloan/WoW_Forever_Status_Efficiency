-- A pretend WoW Forever client, just big enough to run the addon outside the game.
--
-- It imitates the parts of the 12.1.5 addon API the addon touches, including the
-- awkward part: "secret values". A secret here is a userdata that throws when it
-- is indexed, called, measured, concatenated, turned into a string, used in
-- arithmetic or ordered, which is most of what the real client forbids.
-- (Lua 5.1 cannot trap `secret == x` or `if secret then`; the addon keeps those
-- out by never letting a secret past Compat.lua.)
--
-- Mock.new(options) returns a world. Options:
--   secrets        true (default): the client has secret values and hides aura
--                  details in combat. false: an older client with neither.
--   combatAuras    what counting the player's debuffs gives in combat:
--                  "none" (default, and what the 12.1.5 documentation says) a
--                  Lua error, "ids" plain instance ids, "count" a list of
--                  secret ids, "empty" an empty list whatever the enemy
--                  really carries.
--   combatBuffs    the same choice for counting the player's buffs, when the
--                  client treats them differently. Defaults to combatAuras.
--   auraEvents     when UNIT_AURA is sent as a unit's effects change: true
--                  (default) always, with unreadable arguments while details
--                  are hidden; "calm" only while they are not hidden; false
--                  never.
--   auraTokens     set of the kinds of unit token UNIT_AURA is sent for
--                  ("player", "target", "softenemy", "plate"). Default: all.
--   handover       "same": UNIT_AURA is also sent for a token in the frame it
--                  is handed to another unit; "late": a frame after that.
--   noSelfBuffAPI  true: C_Spell.IsSelfBuff does not exist.
--   combatIdentity true (default): NPC GUIDs stay readable in combat.
--   secretFlags    true: UnitExists, UnitCanAttack and friends answer with
--                  secret booleans in combat.
--   byName         set of aura names the client still shows by name in combat.
--   alwaysSecret   set of aura names whose details are secret at all times.
--   noCSecrets     true: C_Secrets does not exist.
--   noAuraAPI      true: C_UnitAuras does not exist.
--   macroStyle     "index" (default) GetActionInfo gives the macro index,
--                  "spell" it gives the macro's spell id with subType "spell".
--   noTemplates    true: CreateFrame knows none of the game's own templates.
--                  A set of template names: it does not know those.
--   brokenTemplates set of template names that exist but whose methods fail.
--   missingFonts   set of font objects this client does not have.
--   missingTextures set of textures (paths or file ids) that do not exist.
--   quietTextures  true: Texture:SetTexture does not say whether it worked.
--   noAtlas        true: textures have no SetAtlas.
--   noLines        true: frames have no CreateLine.
--   noSounds       true: PlaySound and SOUNDKIT do not exist.
--   noSpellTexture true: C_Spell.GetSpellTexture does not exist.
--   usableAPI      how the client says whether an action can be used: nil for
--                  C_ActionBar.IsUsableAction and IsActionInRange, "globals" for
--                  the old plain functions that answer 1 and nil, "secret" when
--                  the answers are secret values, "none" when there is no such call.

local Mock = {}

local REPO = REPO_ROOT or "."

local function Shallow(tbl)
    local copy = {}
    for key, value in pairs(tbl) do
        copy[key] = value
    end
    return copy
end

function Mock.new(options)
    options = options or {}
    if options.secrets == nil then
        options.secrets = true
    end
    options.combatAuras = options.combatAuras or "none"
    if options.auraEvents == nil then
        options.auraEvents = true
    end
    if options.combatIdentity == nil then
        options.combatIdentity = true
    end
    options.byName = options.byName or {}

    local world = {
        options = options,
        clock = 1000,
        combat = false,
        output = {},
        frames = {},
        tokens = {}, -- unit token -> mob
        mobs = {},
        spells = {}, -- id -> { name, description, harmful, helpful, passive, override, range, effect }
        actions = {}, -- slot -> { kind = "spell" | "macro", id = n }
        macros = {}, -- macro index -> spell id
        effects = {}, -- delayed aura applications
        nextAura = 100,
        nextMob = 1,
        nextCast = 1,
        errors = {},
    }

    ----------------------------------------------------------------------------
    -- Secret values
    ----------------------------------------------------------------------------

    local secretValues = setmetatable({}, { __mode = "k" })

    local function Forbidden(what)
        return function()
            error("attempt to " .. what .. " a secret value", 2)
        end
    end

    local function Secret(value)
        local proxy = newproxy(true)
        local meta = getmetatable(proxy)
        meta.__index = Forbidden("index")
        meta.__newindex = Forbidden("index")
        meta.__call = Forbidden("call")
        meta.__len = Forbidden("take the length of")
        meta.__concat = Forbidden("concatenate")
        meta.__tostring = Forbidden("convert")
        meta.__add = Forbidden("perform arithmetic on")
        meta.__sub = meta.__add
        meta.__mul = meta.__add
        meta.__div = meta.__add
        meta.__mod = meta.__add
        meta.__pow = meta.__add
        meta.__unm = meta.__add
        meta.__lt = Forbidden("compare")
        meta.__le = meta.__lt
        secretValues[proxy] = { value = value }
        return proxy
    end

    world.Secret = Secret

    local function AurasHidden()
        return options.secrets and world.combat
    end

    local function IdentityHidden(mob)
        return options.secrets and world.combat and not options.combatIdentity and mob.npc
    end

    local function FlagsHidden(unit)
        return options.secrets and world.combat and options.secretFlags and unit ~= "player"
    end

    ----------------------------------------------------------------------------
    -- The sandbox the addon runs in
    ----------------------------------------------------------------------------

    local env = {
        pairs = pairs, ipairs = ipairs, next = next, type = type, select = select,
        tostring = tostring, tonumber = tonumber, pcall = pcall, error = error,
        unpack = unpack, setmetatable = setmetatable, getmetatable = getmetatable,
        rawget = rawget, rawset = rawset, assert = assert,
        string = string, table = table, math = math,
    }
    env._G = env
    world.env = env

    function env.print(...)
        local parts = {}
        for i = 1, select("#", ...) do
            parts[i] = tostring((select(i, ...)))
        end
        world.output[#world.output + 1] = table.concat(parts, " ")
    end

    if options.secrets then
        function env.issecretvalue(value)
            return secretValues[value] ~= nil
        end
    end

    function env.GetTime()
        return world.clock
    end

    function env.GetBuildInfo()
        return options.clientVersion or "1.60.1", options.clientBuild or "70888", "Nov 11 2026", 16001
    end

    function env.date()
        return "2026-11-26 20:15:00"
    end

    function env.InCombatLockdown()
        return world.combat
    end

    ----------------------------------------------------------------------------
    -- Units
    ----------------------------------------------------------------------------

    local function Resolve(unit)
        if type(unit) ~= "string" then
            error("bad unit token", 3)
        end
        if unit == "player" then
            return world.player
        end
        return world.tokens[unit]
    end

    world.player = { guid = "Player-1-0001", name = "Tester", hostile = false, auras = {} }

    local function Answer(value, unit)
        if FlagsHidden(unit) then
            return Secret(value)
        end
        return value
    end

    function env.UnitExists(unit)
        return Answer(Resolve(unit) ~= nil, unit)
    end

    function env.UnitGUID(unit)
        local mob = Resolve(unit)
        if not mob then
            return nil
        end
        if IdentityHidden(mob) then
            return Secret(mob.guid)
        end
        return mob.guid
    end

    function env.UnitName(unit)
        local mob = Resolve(unit)
        if not mob then
            return nil
        end
        if IdentityHidden(mob) then
            return Secret(mob.name)
        end
        return mob.name
    end

    function env.UnitCanAttack(_, unit)
        local mob = Resolve(unit)
        return Answer(mob ~= nil and mob.hostile == true, unit)
    end

    function env.UnitIsEnemy(_, unit)
        local mob = Resolve(unit)
        return Answer(mob ~= nil and mob.hostile == true, unit)
    end

    function env.UnitIsFriend(_, unit)
        local mob = Resolve(unit)
        return Answer(mob ~= nil and not mob.hostile, unit)
    end

    function env.UnitCanAssist(_, unit)
        local mob = Resolve(unit)
        return Answer(mob ~= nil and not mob.hostile, unit)
    end

    function env.UnitIsUnit(unit, other)
        local mob = Resolve(unit)
        return Answer(mob ~= nil and mob == Resolve(other), unit)
    end

    function env.UnitReaction(unit)
        local mob = Resolve(unit)
        if not mob then
            return nil
        end
        local reaction = mob.hostile and 2 or 5
        if FlagsHidden(unit) then
            return Secret(reaction)
        end
        return reaction
    end

    function env.UnitIsDeadOrGhost(unit)
        local mob = Resolve(unit)
        return Answer(mob ~= nil and mob.dead == true, unit)
    end

    function env.UnitThreatSituation(_, unit)
        local mob = Resolve(unit)
        if not mob or not mob.engaged then
            return nil
        end
        if FlagsHidden(unit) then
            return Secret(1)
        end
        return 1
    end

    function env.UnitAffectingCombat(unit)
        local mob = Resolve(unit)
        return Answer(mob ~= nil and mob.engaged == true, unit)
    end

    ----------------------------------------------------------------------------
    -- Auras
    ----------------------------------------------------------------------------

    local function Matching(mob, filter)
        local list = {}
        local mine = filter and filter:find("PLAYER", 1, true)
        local harmful = filter and filter:find("HARMFUL", 1, true)
        local helpful = filter and filter:find("HELPFUL", 1, true)
        for i = 1, #mob.auras do
            local aura = mob.auras[i]
            if (not mine or aura.fromPlayer) and (not harmful or aura.harmful) and (not helpful or not aura.harmful) then
                list[#list + 1] = aura
            end
        end
        return list
    end

    local function Public(aura)
        if options.alwaysSecret and options.alwaysSecret[aura.name] then
            return {
                name = Secret(aura.name),
                spellId = Secret(aura.spellId),
                duration = Secret(aura.duration),
                expirationTime = Secret(aura.expirationTime),
                auraInstanceID = aura.auraInstanceID,
                isHarmful = aura.harmful,
                isHelpful = not aura.harmful,
                isFromPlayerOrPlayerPet = aura.fromPlayer,
            }
        end
        return {
            name = aura.name,
            spellId = aura.spellId,
            duration = aura.duration,
            expirationTime = aura.expirationTime,
            auraInstanceID = aura.auraInstanceID,
            isHarmful = aura.harmful,
            isHelpful = not aura.harmful,
            isFromPlayerOrPlayerPet = aura.fromPlayer,
        }
    end

    if not options.noAuraAPI then
        env.C_UnitAuras = {}

        function env.C_UnitAuras.GetUnitAuraInstanceIDs(unit, filter)
            local mob = Resolve(unit)
            if not mob then
                return nil
            end
            local mode = options.combatAuras
            if options.combatBuffs and filter and filter:find("HELPFUL", 1, true) then
                mode = options.combatBuffs
            end
            if AurasHidden() and mode == "none" then
                error("C_UnitAuras.GetUnitAuraInstanceIDs requires unit aura access", 2)
            end
            world.sampleCalls = (world.sampleCalls or 0) + 1
            if AurasHidden() and mode == "empty" then
                return {} -- no error, no secrets, and no information either
            end
            local ids = {}
            for _, aura in ipairs(Matching(mob, filter)) do
                if AurasHidden() and mode == "count" then
                    ids[#ids + 1] = Secret(aura.auraInstanceID)
                else
                    ids[#ids + 1] = aura.auraInstanceID
                end
            end
            return ids
        end

        function env.C_UnitAuras.GetUnitAuras(unit, filter)
            local mob = Resolve(unit)
            if not mob then
                return nil
            end
            if AurasHidden() then
                error("C_UnitAuras.GetUnitAuras requires unit aura access", 2)
            end
            local list = {}
            for _, aura in ipairs(Matching(mob, filter)) do
                list[#list + 1] = Public(aura)
            end
            return list
        end

        function env.C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
            local mob = Resolve(unit)
            if not mob then
                return nil
            end
            if AurasHidden() then
                error("C_UnitAuras.GetAuraDataByIndex requires unit aura access", 2)
            end
            local aura = Matching(mob, filter)[index]
            return aura and Public(aura) or nil
        end

        function env.C_UnitAuras.GetAuraDataBySpellName(unit, name, filter)
            local mob = Resolve(unit)
            if not mob then
                return nil
            end
            if AurasHidden() and not options.byName[name] then
                return nil -- hidden auras simply are not found
            end
            if options.alwaysSecret and options.alwaysSecret[name] then
                return nil
            end
            for _, aura in ipairs(Matching(mob, filter)) do
                if aura.name == name then
                    return Public(aura)
                end
            end
            return nil
        end
    end

    if options.secrets and not options.noCSecrets then
        env.C_Secrets = {
            ShouldAurasBeSecret = function()
                return world.combat
            end,
        }
    end

    ----------------------------------------------------------------------------
    -- Nameplates
    ----------------------------------------------------------------------------

    local plateFrames = {}

    env.C_NamePlate = {
        GetNamePlateForUnit = function(unit)
            local mob = Resolve(unit)
            if not mob or not mob.plate then
                return nil
            end
            return plateFrames[mob.plate]
        end,
    }

    ----------------------------------------------------------------------------
    -- Spells and action slots
    ----------------------------------------------------------------------------

    local function FindSpell(spell)
        if type(spell) == "number" then
            return world.spells[spell]
        elseif type(spell) == "string" then
            for _, data in pairs(world.spells) do
                if data.name:lower() == spell:lower() then
                    return data
                end
            end
        end
        return nil
    end

    env.C_Spell = {
        GetSpellName = function(spell)
            local data = FindSpell(spell)
            if not data or data.unloaded then
                return nil
            end
            return data.name
        end,
        GetSpellInfo = function(spell)
            local data = FindSpell(spell)
            if not data or data.unloaded then
                return nil
            end
            return { name = data.name, spellID = data.id, iconID = 1, castTime = 0, minRange = 0,
                maxRange = data.range or 0 }
        end,
        GetSpellDescription = function(spell)
            local data = FindSpell(spell)
            if not data then
                return nil
            end
            if data.textPending and data.textPending > 0 then
                data.textPending = data.textPending - 1
                return ""
            end
            return data.description or ""
        end,
        IsSpellHarmful = function(spell)
            local data = FindSpell(spell)
            return data ~= nil and data.harmful == true
        end,
        IsSpellHelpful = function(spell)
            local data = FindSpell(spell)
            return data ~= nil and data.helpful == true
        end,
        IsSpellPassive = function(spell)
            local data = FindSpell(spell)
            return data ~= nil and data.passive == true
        end,
        IsSelfBuff = not options.noSelfBuffAPI and function(spell)
            local data = FindSpell(spell)
            return data ~= nil and data.selfOnly == true
        end or nil,
        RequestLoadSpellData = function(spell)
            local data = FindSpell(spell)
            if data then
                data.unloaded = nil
            end
        end,
        GetOverrideSpell = function(spell)
            local data = FindSpell(spell)
            return data and data.override or spell
        end,
        GetSpellTexture = not options.noSpellTexture and function(spell)
            local data = FindSpell(spell)
            if not data or data.unloaded then
                return nil
            end
            return data.icon or (130000 + data.id)
        end or nil,
    }

    if env.C_Secrets then
        function env.C_Secrets.GetSpellAuraSecrecy(spell)
            local data = FindSpell(spell)
            local name = data and ((data.effect and data.effect.name) or data.name)
            if name and options.alwaysSecret and options.alwaysSecret[name] then
                return 1
            end
            if name and options.byName[name] then
                return 0
            end
            return 2
        end
    end

    function env.GetActionInfo(slot)
        local action = world.actions[slot]
        if not action then
            return nil
        end
        if action.kind == "macro" then
            if options.macroStyle == "spell" then
                return "macro", world.macros[action.id], "spell"
            end
            return "macro", action.id, nil
        end
        return action.kind, action.id, action.subType or "spell"
    end

    function env.GetMacroSpell(index)
        return world.macros[index]
    end

    env.C_ActionBar = {
        GetSpell = function(slot)
            local action = world.actions[slot]
            if action and action.kind == "spell" then
                return action.id
            end
            return nil
        end,
    }

    -- Whether an action can be used right now, and whether its target is in
    -- reach. Tests set `unusable`, `lacking` and `inRange` on world.actions[slot]
    -- through world:setUsable and world:setRange.
    local function IsUsableAction(slot)
        if type(slot) ~= "number" then
            error("IsUsableAction: bad slot", 2)
        end
        world.usableAsked = (world.usableAsked or 0) + 1
        local action = world.actions[slot]
        if not action then
            return false, false
        end
        if options.usableAPI == "secret" then
            return Secret(not action.unusable), Secret(action.lacking == true)
        end
        return not action.unusable, action.lacking == true
    end
    local function IsActionInRange(slot)
        if type(slot) ~= "number" then
            error("IsActionInRange: bad slot", 2)
        end
        local action = world.actions[slot]
        local inRange = action and action.inRange
        if inRange == nil then
            return nil -- no target, or range does not come into it
        end
        if options.usableAPI == "secret" then
            return Secret(inRange)
        end
        return inRange
    end
    if options.usableAPI == "globals" then
        -- An older client: plain functions that answer 1 and nil, or 1 and 0.
        function env.IsUsableAction(slot)
            local usable, lacking = IsUsableAction(slot)
            return usable and 1 or nil, lacking and 1 or nil
        end
        function env.IsActionInRange(slot)
            local inRange = IsActionInRange(slot)
            if inRange == nil then
                return nil
            end
            return inRange and 1 or 0
        end
    elseif options.usableAPI ~= "none" then
        env.C_ActionBar.IsUsableAction = IsUsableAction
        env.C_ActionBar.IsActionInRange = IsActionInRange
    end

    env.SlashCmdList = {}

    ----------------------------------------------------------------------------
    -- Frames
    ----------------------------------------------------------------------------

    local KNOWN_EVENTS = {
        ADDON_LOADED = true, PLAYER_LOGIN = true, PLAYER_ENTERING_WORLD = true,
        PLAYER_TARGET_CHANGED = true, PLAYER_SOFT_ENEMY_CHANGED = true,
        PLAYER_REGEN_DISABLED = true, PLAYER_REGEN_ENABLED = true, PLAYER_DEAD = true,
        NAME_PLATE_UNIT_ADDED = true, NAME_PLATE_UNIT_REMOVED = true,
        ACTIONBAR_SLOT_CHANGED = true, ACTIONBAR_PAGE_CHANGED = true,
        UPDATE_BONUS_ACTIONBAR = true, UPDATE_SHAPESHIFT_FORM = true, UPDATE_MACROS = true,
        SPELLS_CHANGED = true, UNIT_AURA = true,
        UNIT_SPELLCAST_SENT = true, UNIT_SPELLCAST_SUCCEEDED = true,
        UNIT_SPELLCAST_CHANNEL_START = true, UNIT_SPELLCAST_FAILED = true,
        UNIT_SPELLCAST_FAILED_QUIET = true, UNIT_SPELLCAST_INTERRUPTED = true,
    }
    if options.unknownEvents then
        for event in pairs(options.unknownEvents) do
            KNOWN_EVENTS[event] = nil
        end
    end

    -- Only methods the real widgets have are defined here, so a call to
    -- something that does not exist fails in the tests as it would in the game.

    -- Font objects, with their height in points.
    local FONTS = {
        GameFontNormal = 12, GameFontNormalLarge = 16, GameFontNormalSmall = 10,
        GameFontHighlight = 12, GameFontHighlightSmall = 10, GameFontHighlightHuge = 20,
        GameFontDisable = 12, GameFontDisableSmall = 10,
    }
    if options.missingFonts then
        for font in pairs(options.missingFonts) do
            FONTS[font] = nil
        end
    end
    for font in pairs(FONTS) do
        env[font] = { fontObject = font }
    end

    local POINTS = {
        TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true, RIGHT = true,
        BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
    }

    --- Runs a widget's script the way the client does: a failure in it goes to
    --- the error handler, not to whoever caused the script to run.
    local function Run(widget, kind, ...)
        local handler = widget.scripts[kind]
        if not handler then
            return false
        end
        local ok, err = pcall(handler, widget, ...)
        if not ok then
            world.errors[#world.errors + 1] = tostring(err)
        end
        return true
    end

    local Region = {}
    Region.__index = Region
    function Region:SetPoint(point, ...)
        if type(point) ~= "string" or not POINTS[point] then
            error("SetPoint: bad point", 2)
        end
        local anchor = { point, ... }
        self.points = self.points or {}
        local at = #self.points + 1
        for i = 1, #self.points do
            if self.points[i][1] == point then
                at = i -- setting a point a second time moves it
            end
        end
        self.points[at] = anchor
        self.point = anchor
    end
    --- point, relativeTo, relativePoint, x, y of an anchor, however it was given.
    function Region:GetPoint(index)
        local anchor = self.points and self.points[index or 1]
        if not anchor then
            return nil
        end
        local point, a, b, c, d = anchor[1], anchor[2], anchor[3], anchor[4], anchor[5]
        if type(a) == "number" then
            return point, self.parent or self.owner, point, a, b or 0
        elseif type(b) == "string" then
            return point, a, b, c or 0, d or 0
        end
        return point, a or self.parent or self.owner, point, b or 0, c or 0
    end
    function Region:ClearAllPoints()
        self.points, self.point, self.allPoints = nil, nil, nil
    end
    function Region:SetAllPoints(target)
        self.allPoints = target or true
    end
    function Region:SetSize(width, height)
        if type(width) ~= "number" or type(height) ~= "number" then
            error("SetSize: bad size", 2)
        end
        self.width, self.height = width, height
    end
    function Region:SetWidth(width)
        if type(width) ~= "number" then
            error("SetWidth: bad width", 2)
        end
        self.width = width
    end
    function Region:SetHeight(height)
        if type(height) ~= "number" then
            error("SetHeight: bad height", 2)
        end
        self.height = height
    end
    function Region:GetWidth()
        return self.width or 0
    end
    function Region:GetHeight()
        return self.height or 0
    end
    function Region:SetAlpha(alpha)
        if type(alpha) ~= "number" then
            error("SetAlpha: bad alpha", 2)
        end
        self.alpha = alpha
    end
    function Region:GetAlpha()
        return self.alpha or 1
    end
    function Region:Show()
        self.shown = true
    end
    function Region:Hide()
        self.shown = false
    end
    function Region:IsShown()
        return self.shown
    end

    local Texture = setmetatable({}, { __index = Region })
    Texture.__index = Texture
    --- Answers whether the texture exists, as the client does. With the option
    --- quietTextures it answers nothing, as older clients do.
    function Texture:SetTexture(path)
        self.color, self.atlas = nil, nil
        local missing = path ~= nil and options.missingTextures and options.missingTextures[path]
        self.path = not missing and path or nil
        if options.quietTextures then
            return
        end
        return not missing
    end
    function Texture:GetTexture()
        return self.path
    end
    function Texture:SetColorTexture(r, g, b, a)
        if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
            error("SetColorTexture: bad colour", 2)
        end
        self.color = { r, g, b, a }
        self.path, self.atlas = nil, nil
    end
    if not options.noAtlas then
        function Texture:SetAtlas(atlas, useAtlasSize)
            if type(atlas) ~= "string" then
                error("SetAtlas: bad atlas", 2)
            end
            self.atlas, self.atlasSize = atlas, useAtlasSize
            self.path, self.color = nil, nil
        end
    end
    function Texture:SetTexCoord(...)
        self.texCoord = { ... }
    end
    function Texture:SetVertexColor() end
    function Texture:SetDesaturated(desaturated)
        self.desaturated = desaturated and true or false
    end

    local Line = setmetatable({}, { __index = Region })
    Line.__index = Line
    function Line:SetStartPoint(point, relativeTo, x, y)
        if not POINTS[point] then
            error("SetStartPoint: bad point", 2)
        end
        self.from = { point, relativeTo, x, y }
    end
    function Line:SetEndPoint(point, relativeTo, x, y)
        if not POINTS[point] then
            error("SetEndPoint: bad point", 2)
        end
        self.to = { point, relativeTo, x, y }
    end
    function Line:SetThickness(thickness)
        self.thickness = thickness
    end
    Line.SetColorTexture = Texture.SetColorTexture

    local FontString = setmetatable({}, { __index = Region })
    FontString.__index = FontString
    function FontString:SetText(text)
        self.text = text
    end
    function FontString:GetText()
        return self.text
    end
    --- Roughly how wide the text is drawn, in the panel's units.
    function FontString:GetStringWidth()
        return #tostring(self.text or "") * (FONTS[self.font] or 12) * 0.5
    end
    function FontString:SetJustifyH(justify)
        self.justifyH = justify
    end
    function FontString:SetJustifyV(justify)
        self.justifyV = justify
    end
    function FontString:SetTextColor(r, g, b, a)
        if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
            error("SetTextColor: bad colour", 2)
        end
        self.textColor = { r, g, b, a }
    end
    function FontString:SetWordWrap(wrap)
        self.wordWrap = wrap
    end
    function FontString:SetMaxLines(lines)
        if type(lines) ~= "number" then
            error("SetMaxLines: bad number", 2)
        end
        self.maxLines = lines
    end

    local Frame = setmetatable({}, { __index = Region })
    Frame.__index = Frame

    -- The scripts each kind of widget has. Setting any other is an error, as it
    -- is in the game.
    local FRAME_SCRIPTS = {
        OnEvent = true, OnUpdate = true, OnShow = true, OnHide = true, OnEnter = true, OnLeave = true,
        OnMouseDown = true, OnMouseUp = true, OnMouseWheel = true, OnDragStart = true, OnDragStop = true,
        OnSizeChanged = true,
    }
    local EXTRA_SCRIPTS = {
        Button = { OnClick = true, OnDoubleClick = true, PreClick = true, PostClick = true },
        CheckButton = { OnClick = true, OnDoubleClick = true, PreClick = true, PostClick = true },
        EditBox = {
            OnEnterPressed = true, OnEscapePressed = true, OnTextChanged = true, OnEditFocusGained = true,
            OnEditFocusLost = true, OnTabPressed = true, OnChar = true,
        },
        Slider = { OnValueChanged = true, OnMinMaxChanged = true },
    }

    world.updaters = {} -- frames with an OnUpdate script

    function Frame:RegisterEvent(event)
        if not KNOWN_EVENTS[event] then
            error("Frame:RegisterEvent(): Attempt to register unknown event \"" .. tostring(event) .. "\"", 2)
        end
        self.events[event] = true
        return true
    end
    function Frame:RegisterUnitEvent(event, unit)
        if not KNOWN_EVENTS[event] then
            error("Frame:RegisterUnitEvent(): Attempt to register unknown event \"" .. tostring(event) .. "\"", 2)
        end
        self.unitEvents[event] = unit
        return true
    end
    function Frame:UnregisterEvent(event)
        self.events[event] = nil
        self.unitEvents[event] = nil
    end
    function Frame:SetScript(kind, fn)
        if fn ~= nil and type(fn) ~= "function" then
            error("SetScript: handler is not a function", 2)
        end
        local extra = EXTRA_SCRIPTS[self.frameType]
        if not FRAME_SCRIPTS[kind] and not (extra and extra[kind]) then
            error(tostring(self.frameType) .. " doesn't have a \"" .. tostring(kind) .. "\" script", 2)
        end
        if kind == "OnUpdate" and fn and not self.scripts.OnUpdate then
            world.updaters[#world.updaters + 1] = self
        end
        self.scripts[kind] = fn
    end
    function Frame:GetScript(kind)
        return self.scripts[kind]
    end
    function Frame:SetFrameLevel(level)
        if type(level) ~= "number" then
            error("SetFrameLevel: bad level", 2)
        end
        self.level = level
    end
    function Frame:GetFrameLevel()
        return self.level or 1
    end
    function Frame:SetFrameStrata(strata)
        self.strata = strata
    end
    function Frame:EnableMouse(enabled)
        self.mouse = enabled and true or false
    end
    function Frame:EnableMouseWheel(enabled)
        self.mouseWheel = enabled and true or false
    end
    function Frame:SetMovable() end
    function Frame:SetClampedToScreen() end
    function Frame:RegisterForDrag() end
    function Frame:StartMoving()
        self.moving = true
    end
    function Frame:StopMovingOrSizing()
        self.moving = false
    end
    function Frame:SetClipsChildren(clips)
        self.clips = clips and true or false
    end
    function Frame:SetHitRectInsets(left, right, top, bottom)
        self.hitInsets = { left, right, top, bottom }
    end
    --- How large the frame is drawn next to the screen: tests set `scale` on a
    --- frame to stand for SetScale.
    function Frame:GetEffectiveScale()
        local scale, frame = 1, self
        while frame do
            scale = scale * (frame.scale or 1)
            frame = frame.parent
        end
        return scale
    end
    function Frame:GetName()
        return self.name
    end
    function Frame:GetParent()
        return self.parent
    end
    function Frame:IsVisible()
        local frame = self
        while frame do
            if not frame.shown then
                return false
            end
            frame = frame.parent
        end
        return true
    end

    -- A frame that comes on screen, or leaves it, takes the frames inside it
    -- along: each of them that is shown gets its OnShow or OnHide too.
    local function Appeared(frame)
        Run(frame, "OnShow")
        local i = 1
        while i <= #frame.children do
            if frame.children[i].shown then
                Appeared(frame.children[i])
            end
            i = i + 1
        end
    end

    local function Vanished(frame)
        if frame.focus then
            frame:ClearFocus() -- an edit box nobody can see cannot be typed into
        end
        local i = 1
        while i <= #frame.children do
            if frame.children[i].shown then
                Vanished(frame.children[i])
            end
            i = i + 1
        end
        Run(frame, "OnHide")
    end

    function Frame:Show()
        if self.shown then
            return
        end
        self.shown = true
        if self:IsVisible() then
            Appeared(self)
        end
    end
    function Frame:Hide()
        if not self.shown then
            return
        end
        local was = self:IsVisible()
        self.shown = false
        if was then
            Vanished(self)
        end
    end
    function Frame:SetParent(parent)
        local was = self:IsVisible()
        local old = self.parent
        if old and old.children then
            for i = #old.children, 1, -1 do
                if old.children[i] == self then
                    table.remove(old.children, i)
                end
            end
        end
        self.parent = parent
        if parent and parent.children then
            parent.children[#parent.children + 1] = self
        end
        local now = self:IsVisible()
        if was and not now then
            Vanished(self)
        elseif now and not was then
            Appeared(self)
        end
    end
    function Frame:GetAttribute(name)
        return self.attributes and self.attributes[name]
    end
    function Frame:CreateTexture(_, layer)
        local texture = setmetatable({ owner = self, layer = layer, shown = true }, Texture)
        self.textures[#self.textures + 1] = texture
        return texture
    end
    function Frame:CreateFontString(_, layer, font)
        if font ~= nil and not FONTS[font] then
            error("CreateFontString: no font object called " .. tostring(font), 2)
        end
        local text = setmetatable({ owner = self, layer = layer, font = font, shown = true }, FontString)
        self.strings[#self.strings + 1] = text
        return text
    end
    if not options.noLines then
        function Frame:CreateLine(_, layer)
            local line = setmetatable({ owner = self, layer = layer, shown = true }, Line)
            self.lines[#self.lines + 1] = line
            return line
        end
    end

    local Button = setmetatable({}, { __index = Frame })
    Button.__index = Button
    function Button:RegisterForClicks() end
    function Button:Enable()
        self.enabled = true
    end
    function Button:Disable()
        self.enabled = false
    end
    function Button:SetEnabled(enabled)
        self.enabled = enabled and true or false
    end
    function Button:IsEnabled()
        return self.enabled ~= false
    end
    function Button:SetText(text)
        self.text = text
    end
    function Button:GetText()
        return self.text
    end

    local CheckButton = setmetatable({}, { __index = Button })
    CheckButton.__index = CheckButton
    function CheckButton:SetChecked(checked)
        self.checked = checked and true or false
    end
    function CheckButton:GetChecked()
        return self.checked == true
    end

    local Slider = setmetatable({}, { __index = Frame })
    Slider.__index = Slider
    local function Within(slider, value)
        return math.max(slider.low or 0, math.min(slider.high or 0, value))
    end
    function Slider:SetMinMaxValues(low, high)
        if type(low) ~= "number" or type(high) ~= "number" or low > high then
            error("SetMinMaxValues: bad range", 2)
        end
        self.low, self.high = low, high
        if self.value ~= nil and Within(self, self.value) ~= self.value then
            self:SetValue(self.value) -- pulled back inside the new range
        end
    end
    function Slider:GetMinMaxValues()
        return self.low or 0, self.high or 0
    end
    function Slider:SetValueStep(step)
        if type(step) ~= "number" then
            error("SetValueStep: bad step", 2)
        end
        self.step = step
    end
    function Slider:GetValueStep()
        return self.step or 0
    end
    function Slider:SetObeyStepOnDrag(obey)
        self.obeyStep = obey and true or false
    end
    function Slider:SetOrientation(orientation)
        if orientation ~= "HORIZONTAL" and orientation ~= "VERTICAL" then
            error("SetOrientation: bad orientation", 2)
        end
        self.orientation = orientation
    end
    function Slider:SetThumbTexture(texture)
        self.thumb = texture
    end
    function Slider:GetValue()
        return self.value or self.low or 0
    end
    --- Tells the script only when the value really changes, as the client does.
    function Slider:SetValue(value)
        if type(value) ~= "number" then
            error("SetValue: bad value", 2)
        end
        value = Within(self, value)
        if self.value ~= value then
            self.value = value
            Run(self, "OnValueChanged", value, false)
        end
    end
    Slider.Enable, Slider.Disable = Button.Enable, Button.Disable
    Slider.SetEnabled, Slider.IsEnabled = Button.SetEnabled, Button.IsEnabled

    local EditBox = setmetatable({}, { __index = Frame })
    EditBox.__index = EditBox
    function EditBox:SetAutoFocus() end
    function EditBox:SetFontObject(font)
        if type(font) ~= "table" then
            error("SetFontObject: not a font object", 2)
        end
    end
    function EditBox:SetTextInsets() end
    function EditBox:SetMaxLetters() end
    function EditBox:SetJustifyH(justify)
        self.justifyH = justify
    end
    function EditBox:HighlightText(first, last)
        self.highlight = { first, last }
    end
    function EditBox:SetText(text)
        self.text = tostring(text)
    end
    function EditBox:GetText()
        return self.text or ""
    end
    -- One box has the keyboard at a time, and each is told when it gets or loses it.
    function EditBox:SetFocus()
        if self.focus then
            return
        end
        if world.focused then
            world.focused:ClearFocus()
        end
        self.focus = true
        world.focused = self
        Run(self, "OnEditFocusGained")
    end
    function EditBox:ClearFocus()
        if not self.focus then
            return
        end
        self.focus = false
        if world.focused == self then
            world.focused = nil
        end
        Run(self, "OnEditFocusLost")
    end
    function EditBox:HasFocus()
        return self.focus == true
    end

    local CLASSES = { Frame = Frame, Button = Button, CheckButton = CheckButton, EditBox = EditBox, Slider = Slider }

    world.sounds = {}
    if not options.noSounds then
        env.SOUNDKIT = {
            IG_MAINMENU_OPTION_CHECKBOX_ON = 856, IG_MAINMENU_OPTION_CHECKBOX_OFF = 857,
            IG_CHARACTER_INFO_TAB = 841,
        }
        function env.PlaySound(id)
            if type(id) ~= "number" then
                error("PlaySound: bad sound", 2)
            end
            world.sounds[#world.sounds + 1] = id
        end
    end

    -- The few of the game's own templates the addon uses, as far as it uses
    -- them. `kind` is the widget each one is for; `build` adds what it brings.
    local function Sized(width, height, level)
        return function(frame)
            frame.width, frame.height, frame.level = width, height, level
        end
    end
    local TEMPLATES = {
        UIPanelButtonTemplate = { kind = "Button", build = Sized(40, 22) },
        UIPanelCloseButtonNoScripts = { kind = "Button", build = Sized(24, 24, 510) },
        MinimalCheckboxTemplate = { kind = "CheckButton", build = Sized(30, 29) },
        MinimalSliderWithSteppersTemplate = { kind = "Frame" },
    }

    -- Blizzard_SharedXML/Shared/Slider/MinimalSlider.lua and .xml, in outline.
    function TEMPLATES.MinimalSliderWithSteppersTemplate.build(frame)
        frame.width, frame.height = 250, 40
        local slider = env.CreateFrame("Slider", nil, frame)
        slider:SetPoint("TOPLEFT", 19, 0)
        slider:SetPoint("BOTTOMRIGHT", -19, 0)
        local back = env.CreateFrame("Button", nil, frame)
        back:SetSize(11, 19)
        back:SetPoint("RIGHT", slider, "LEFT", -4, 0)
        local forward = env.CreateFrame("Button", nil, frame)
        forward:SetSize(9, 18)
        forward:SetPoint("LEFT", slider, "RIGHT", 4, 0)
        frame.Slider, frame.Back, frame.Forward = slider, back, forward
        frame.Event = { OnValueChanged = "OnValueChanged", OnInteractStart = "OnInteractStart",
            OnInteractEnd = "OnInteractEnd" }

        local callbacks = {}
        function frame:RegisterCallback(event, func, owner)
            if type(event) ~= "string" then
                error("CallbackRegistryMixin::RegisterCallback 'event' requires string type.")
            elseif type(func) ~= "function" then
                error("CallbackRegistryMixin::RegisterCallback 'func' requires function type.")
            elseif type(owner) == "number" then
                error("CallbackRegistryMixin:RegisterCallback 'owner' as number is reserved internally.")
            end
            callbacks[event] = callbacks[event] or {}
            callbacks[event][owner or {}] = func
        end
        local function Trigger(event, ...)
            for owner, func in pairs(callbacks[event] or {}) do
                local ok, err = pcall(func, owner, ...)
                if not ok then
                    world.errors[#world.errors + 1] = tostring(err)
                end
            end
        end

        local function UpdateSteppers()
            local value, step = slider:GetValue(), slider:GetValueStep()
            local low, high = slider:GetMinMaxValues()
            back:SetEnabled(value > low + step * 0.5)
            forward:SetEnabled(value < high - step * 0.5)
        end
        function frame:Init(value, minValue, maxValue, steps)
            if options.brokenTemplates and options.brokenTemplates.MinimalSliderWithSteppersTemplate then
                error("attempt to call method 'Init' (a nil value)", 2)
            end
            slider:SetMinMaxValues(minValue, maxValue)
            slider:SetValueStep((maxValue - minValue) / steps)
            slider:SetValue(value)
            UpdateSteppers()
            slider:SetScript("OnValueChanged", function(_, now)
                UpdateSteppers()
                Trigger("OnValueChanged", now)
            end)
        end
        function frame:SetValue(value)
            slider:SetValue(value)
        end
        function frame:SetEnabled(enabled)
            slider:SetEnabled(enabled)
            if enabled then
                UpdateSteppers()
            else
                back:SetEnabled(false)
                forward:SetEnabled(false)
            end
        end
        back:SetScript("OnClick", function()
            slider:SetValue(slider:GetValue() - slider:GetValueStep())
            env.PlaySound(env.SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end)
        forward:SetScript("OnClick", function()
            slider:SetValue(slider:GetValue() + slider:GetValueStep())
            env.PlaySound(env.SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end)
    end

    function env.CreateFrame(frameType, name, parent, template)
        local class = CLASSES[frameType]
        if not class then
            error("CreateFrame: unknown frame type " .. tostring(frameType), 2)
        end
        local inherits
        if template ~= nil then
            inherits = TEMPLATES[template]
            local without = options.noTemplates
            if not inherits or without == true or (type(without) == "table" and without[template]) then
                error("CreateFrame: Couldn't find inherited node: " .. tostring(template), 2)
            end
            if inherits.kind ~= frameType then
                error("CreateFrame: " .. tostring(template) .. " is a template for a " .. inherits.kind, 2)
            end
        end
        if options.failCreateFrameWithParent and parent then
            error("CreateFrame is not allowed right now", 2)
        end
        local frame = setmetatable({
            events = {}, unitEvents = {}, scripts = {}, textures = {}, strings = {}, lines = {}, children = {},
            shown = true, parent = parent, name = name, frameType = frameType, template = template,
        }, class)
        world.frames[#world.frames + 1] = frame
        if parent and parent.children then
            parent.children[#parent.children + 1] = frame
        end
        if name then
            rawset(env, name, frame)
        end
        if inherits and inherits.build then
            inherits.build(frame)
        end
        return frame
    end

    env.UIParent = env.CreateFrame("Frame", "UIParent", nil)
    env.UISpecialFrames = {}
    world.tooltipLines = {}
    env.GameTooltip = {
        SetOwner = function(_, owner)
            world.tooltipOwner = owner
        end,
        SetText = function(_, text)
            world.tooltip = text
            world.tooltipLines = {}
        end,
        AddLine = function(_, text)
            world.tooltipLines[#world.tooltipLines + 1] = text
        end,
        Show = function() end,
        Hide = function()
            world.tooltip, world.tooltipOwner = nil, nil
            world.tooltipLines = {}
        end,
    }

    -- The game's Options window, as far as registering an addon panel goes.
    world.settings = { categories = {}, addons = {} }
    if not options.noSettings then
        env.Settings = {
            RegisterCanvasLayoutCategory = function(frame, name)
                if type(frame) ~= "table" or type(name) ~= "string" then
                    error("RegisterCanvasLayoutCategory: bad arguments", 2)
                end
                local category = { frame = frame, name = name, ID = #world.settings.categories + 1 }
                function category:GetID()
                    return self.ID
                end
                world.settings.categories[#world.settings.categories + 1] = category
                return category, {}
            end,
            RegisterAddOnCategory = function(category)
                world.settings.addons[#world.settings.addons + 1] = category
            end,
        }
    end

    ----------------------------------------------------------------------------
    -- Driving the world
    ----------------------------------------------------------------------------

    function world:fire(event, ...)
        for i = 1, #self.frames do
            local frame = self.frames[i]
            local unit = frame.unitEvents[event]
            local first = ...
            if frame.events[event] or (unit ~= nil and unit == first) then
                local handler = frame.scripts.OnEvent
                if handler then
                    local ok, err = pcall(handler, frame, event, ...)
                    if not ok then
                        self.errors[#self.errors + 1] = tostring(err)
                    end
                end
            end
        end
    end

    local function TokenKind(token)
        if token == "player" or token == "target" or token == "softenemy" then
            return token
        end
        return "plate"
    end

    --- Sends UNIT_AURA for one unit token. While aura details are hidden the
    --- arguments are secret, the unit included, so a frame only learns whose
    --- effects changed from having registered for that one unit.
    local function SendAuraEvent(token)
        if options.auraTokens and not options.auraTokens[TokenKind(token)] then
            return
        end
        local hidden = AurasHidden()
        local unit = hidden and Secret(token) or token
        local details = hidden and Secret({}) or { isFullUpdate = false }
        world.auraEventsSent = (world.auraEventsSent or 0) + 1
        for i = 1, #world.frames do
            local frame = world.frames[i]
            if frame.events.UNIT_AURA or frame.unitEvents.UNIT_AURA == token then
                local handler = frame.scripts.OnEvent
                if handler then
                    local ok, err = pcall(handler, frame, "UNIT_AURA", unit, details)
                    if not ok then
                        world.errors[#world.errors + 1] = tostring(err)
                    end
                end
            end
        end
    end

    --- The effects on a unit changed: the client says so once for every unit
    --- token that points at it.
    function world:auraChanged(mob)
        local mode = options.auraEvents
        if mode == false or (mode == "calm" and AurasHidden()) then
            return
        end
        local tokens = {}
        if mob == self.player then
            tokens[#tokens + 1] = "player"
        end
        for token, other in pairs(self.tokens) do
            if other == mob then
                tokens[#tokens + 1] = token
            end
        end
        table.sort(tokens)
        for _, token in ipairs(tokens) do
            SendAuraEvent(token)
        end
    end

    --- A unit token was handed to another unit. Some clients follow that with
    --- a UNIT_AURA for the token although no effect changed.
    local function Handover(token)
        if options.auraEvents == false then
            return
        end
        if options.handover == "same" then
            SendAuraEvent(token)
        elseif options.handover == "late" then
            world.effects[#world.effects + 1] = {
                at = world.clock + 0.01,
                run = function()
                    if world.tokens[token] then
                        SendAuraEvent(token)
                    end
                end,
            }
        end
    end

    local function Expire(mob, now)
        local expired = false
        for i = #mob.auras, 1, -1 do
            local aura = mob.auras[i]
            if aura.expirationTime > 0 and aura.expirationTime <= now then
                table.remove(mob.auras, i)
                expired = true
            end
        end
        if expired then
            world:auraChanged(mob)
        end
    end

    function world:step(dt)
        self.clock = self.clock + dt
        for i = #self.effects, 1, -1 do
            local effect = self.effects[i]
            if effect.at <= self.clock then
                table.remove(self.effects, i)
                effect.run()
            end
        end
        for _, mob in pairs(self.mobs) do
            Expire(mob, self.clock)
        end
        Expire(self.player, self.clock)
        -- Only frames that are on screen get their OnUpdate.
        for i = 1, #self.updaters do
            local frame = self.updaters[i]
            if frame.scripts.OnUpdate and frame:IsVisible() then
                Run(frame, "OnUpdate", dt)
            end
        end
    end

    --- Lets time pass, a frame at a time.
    function world:advance(seconds, dt)
        dt = dt or 0.05
        local steps = math.floor(seconds / dt + 0.5)
        for _ = 1, steps do
            self:step(dt)
        end
    end

    function world:addSpell(id, data)
        data = Shallow(data)
        data.id = id
        self.spells[id] = data
        return data
    end

    --- Puts a spell (or a macro casting one) on a default action button.
    function world:addButton(name, slot, spellID, kind)
        local frame = env[name]
        if not frame then
            frame = env.CreateFrame("CheckButton", name, nil)
            frame.width, frame.height = 45, 45
        end
        frame.action = slot
        if kind == "macro" then
            self.macros[slot] = spellID
            self.actions[slot] = { kind = "macro", id = slot }
        elseif spellID then
            self.actions[slot] = { kind = kind or "spell", id = spellID }
        else
            self.actions[slot] = nil
        end
        return frame
    end

    --- Says whether the skill in a slot can be used (enough rage, the right
    --- stance and so on). `lacking` marks it as short of rage, mana or energy.
    function world:setUsable(slot, usable, lacking)
        local action = assert(self.actions[slot], "no action in that slot")
        action.unusable = not usable
        action.lacking = lacking and true or nil
    end

    --- Says whether the target is in the skill's reach: true, false (too far or
    --- too close), or nil when range does not come into it.
    function world:setRange(slot, inRange)
        assert(self.actions[slot], "no action in that slot").inRange = inRange
    end

    function world:addMob(name, fields)
        local mob = {
            name = name,
            guid = string.format("Creature-0-1-2-3-%d-%010d", 1000 + self.nextMob, self.nextMob),
            hostile = true, npc = true, auras = {}, engaged = false,
        }
        self.nextMob = self.nextMob + 1
        if fields then
            for key, value in pairs(fields) do
                mob[key] = value
            end
        end
        self.mobs[#self.mobs + 1] = mob
        return mob
    end

    function world:target(mob)
        self.tokens.target = mob
        self:fire("PLAYER_TARGET_CHANGED")
        if mob then
            Handover("target")
        end
    end

    function world:showPlate(mob)
        if mob.plate then
            return mob.plate
        end
        for i = 1, 40 do
            local token = "nameplate" .. i
            if not self.tokens[token] then
                self.tokens[token] = mob
                mob.plate = token
                plateFrames[token] = plateFrames[token] or { unitToken = token }
                self:fire("NAME_PLATE_UNIT_ADDED", token)
                Handover(token)
                return token
            end
        end
        error("out of nameplates")
    end

    function world:hidePlate(mob)
        local token = mob.plate
        if token then
            self.tokens[token] = nil
            mob.plate = nil
            self:fire("NAME_PLATE_UNIT_REMOVED", token)
        end
    end

    function world:enterCombat()
        if not self.combat then
            self.combat = true
            self:fire("PLAYER_REGEN_DISABLED")
        end
    end

    function world:leaveCombat()
        if self.combat then
            self.combat = false
            for _, mob in pairs(self.mobs) do
                mob.engaged = false
            end
            self:fire("PLAYER_REGEN_ENABLED")
        end
    end

    --- Puts a debuff on a unit, or a buff when `helpful` is true. The unit is a
    --- mob, or world.player.
    function world:applyAura(mob, name, duration, fromPlayer, spellId, helpful)
        local harmful = not helpful
        -- Recasting refreshes the same instance unless asked otherwise.
        for _, aura in ipairs(mob.auras) do
            if aura.name == name and aura.fromPlayer == (fromPlayer ~= false) and aura.harmful == harmful then
                if self.options.refreshReplaces then
                    aura.auraInstanceID = self.nextAura
                    self.nextAura = self.nextAura + 1
                end
                aura.duration = duration
                aura.expirationTime = duration > 0 and self.clock + duration or 0
                self:auraChanged(mob)
                return aura
            end
        end
        local aura = {
            name = name, spellId = spellId or 0, duration = duration,
            expirationTime = duration > 0 and self.clock + duration or 0,
            auraInstanceID = self.nextAura, harmful = harmful, fromPlayer = fromPlayer ~= false,
        }
        self.nextAura = self.nextAura + 1
        mob.auras[#mob.auras + 1] = aura
        self:auraChanged(mob)
        return aura
    end

    --- Puts a buff on a unit: world.player unless one is given.
    function world:applyBuff(name, duration, fromPlayer, mob)
        return self:applyAura(mob or self.player, name, duration, fromPlayer, nil, true)
    end

    function world:removeAura(mob, name)
        local removed = false
        for i = #mob.auras, 1, -1 do
            if mob.auras[i].name == name then
                table.remove(mob.auras, i)
                removed = true
            end
        end
        if removed then
            self:auraChanged(mob)
        end
    end

    function world:kill(mob)
        local had = #mob.auras > 0
        mob.dead = true
        mob.engaged = false
        mob.auras = {}
        if had then
            self:auraChanged(mob)
        end
    end

    --- The player dies, losing every aura, and comes back to life.
    function world:die()
        local had = #self.player.auras > 0
        self.player.auras = {}
        if had then
            self:auraChanged(self.player)
        end
        self:fire("PLAYER_DEAD")
        self:leaveCombat()
    end

    --- The player casts a spell.
    --- opts: miss = true (nothing lands), travel = seconds before the effect
    --- lands, early = seconds the effect shows on the unit before the cast is
    --- announced, castTime = seconds between sent and success, noSent = true,
    --- fail = true (the cast is sent and then fails), hits = list of mobs an
    --- area spell reaches (default: every engaged mob plus the target),
    --- quiet = true (does not start combat).
    ---
    --- A spell's effect = { duration, name, area, extra, fromPlayer, buff,
    --- replaces, toggle }. With buff = true it lands on the player, or on a
    --- friendly target when the spell is helpful and not selfOnly, and removes
    --- the buff named by `replaces` (two stances cannot be up together). With
    --- toggle = true, casting it while its effect is up takes the effect away.
    function world:cast(spellID, opts)
        opts = opts or {}
        local data = assert(self.spells[spellID], "unknown spell " .. tostring(spellID))
        local castID = "Cast-3-0-0-0-" .. spellID .. "-" .. self.nextCast
        self.nextCast = self.nextCast + 1
        local target = self.tokens.target
        local shownID = spellID

        if not opts.noSent then
            self:fire("UNIT_SPELLCAST_SENT", "player", target and target.name or "", castID, shownID)
        end
        if opts.castTime then
            self:advance(opts.castTime)
        end
        if opts.fail then
            self:fire("UNIT_SPELLCAST_FAILED", "player", castID, shownID)
            return
        end

        local effect = data.effect
        local function Land()
            if not effect or opts.miss then
                return
            end
            local victims
            if effect.buff then
                local friend = target and not target.hostile and not target.dead
                    and data.helpful and not data.selfOnly
                victims = { opts.on or (friend and target) or self.player }
            elseif effect.area then
                victims = opts.hits
                if not victims then
                    victims = {}
                    for _, mob in pairs(self.mobs) do
                        if not mob.dead and (mob.engaged or mob == target) then
                            victims[#victims + 1] = mob
                        end
                    end
                end
            else
                victims = { opts.on or target }
            end
            for _, mob in ipairs(victims) do
                if mob and not mob.dead then
                    if effect.replaces then
                        self:removeAura(mob, effect.replaces)
                    end
                    local name = effect.name or data.name
                    local up = false
                    for _, aura in ipairs(mob.auras) do
                        up = up or aura.name == name
                    end
                    if effect.toggle and up then
                        self:removeAura(mob, name)
                    else
                        self:applyAura(mob, name, effect.duration, effect.fromPlayer, nil, effect.buff)
                    end
                    if effect.extra then
                        self:applyAura(mob, effect.extra, effect.duration, nil, nil, effect.buff)
                    end
                end
            end
        end

        if not opts.quiet and (data.harmful or (effect and effect.area)) then
            if target and target.hostile and not target.dead then
                target.engaged = true
            end
            if opts.hits then
                for _, mob in ipairs(opts.hits) do
                    mob.engaged = true
                end
            end
            self:enterCombat()
        end

        if opts.early then
            Land()
            self:advance(opts.early)
        end

        self:fire("UNIT_SPELLCAST_SUCCEEDED", "player", castID, shownID)

        if opts.early then
            return
        end
        if opts.travel and opts.travel > 0 then
            self.effects[#self.effects + 1] = { at = self.clock + opts.travel, run = Land }
        else
            Land()
        end
    end

    ----------------------------------------------------------------------------
    -- Looking at the result
    ----------------------------------------------------------------------------

    local ICONS = { Check = "check", Partial = "partial", Cross = "cross" }

    --- What the addon is drawing on a button: "check", "partial", "cross" or nil.
    function world:icon(buttonName)
        local button = env[buttonName]
        for i = 1, #self.frames do
            local frame = self.frames[i]
            if frame.parent == button and #frame.textures > 0 then
                if not frame:IsVisible() then
                    return nil
                end
                local path = frame.textures[1].path or ""
                local file = path:match("([^\\]+)%.tga$")
                return ICONS[file] or ("unknown:" .. path)
            end
        end
        return nil
    end

    function world:overlay(buttonName)
        local button = env[buttonName]
        for i = 1, #self.frames do
            local frame = self.frames[i]
            if frame.parent == button and #frame.textures > 0 then
                return frame
            end
        end
        return nil
    end

    function world:slash(text)
        env.SlashCmdList["STATUSEFFICIENCY"](text)
    end

    --- Clicks a button the way the mouse would. A widget that is not on screen
    --- cannot be clicked, and a disabled one ignores the click.
    function world:click(button)
        assert(type(button) == "table" and button.scripts, "that is not a widget")
        if not button:IsVisible() then
            error("that widget is not on screen", 2)
        end
        if button.IsEnabled and not button:IsEnabled() then
            return
        end
        Run(button, "OnMouseDown", "LeftButton")
        Run(button, "OnMouseUp", "LeftButton")
        if button.frameType == "CheckButton" then
            button.checked = not button.checked -- the game flips the box before the script runs
        end
        assert(button.scripts.OnClick, "that widget has no click handler")
        Run(button, "OnClick", "LeftButton")
    end

    --- Puts the mouse over a widget. Returns the tooltip's title and its lines.
    function world:hover(widget)
        if not widget:IsVisible() then
            error("that widget is not on screen", 2)
        end
        Run(widget, "OnEnter")
        return self.tooltip, self.tooltipLines
    end

    function world:unhover(widget)
        Run(widget, "OnLeave")
    end

    --- Types into an edit box and presses Enter.
    function world:type(box, text)
        if not box:IsVisible() then
            error("that edit box is not on screen", 2)
        end
        box:SetFocus()
        box:SetText(text)
        Run(box, "OnEnterPressed")
    end

    --- Presses Escape in an edit box.
    function world:escape(box)
        Run(box, "OnEscapePressed")
    end

    --- Drags a slider's thumb to a value.
    function world:slide(slider, value)
        if not slider:IsVisible() then
            error("that slider is not on screen", 2)
        end
        value = math.max(slider.low or 0, math.min(slider.high or 0, value))
        if slider.value ~= value then
            slider.value = value
            Run(slider, "OnValueChanged", value, true)
        end
    end

    --- Turns the mouse wheel over a frame: 1 is one notch up, -1 one down.
    function world:wheel(frame, delta)
        if not frame:IsVisible() then
            error("that frame is not on screen", 2)
        end
        assert(frame.mouseWheel, "that frame does not take the mouse wheel")
        Run(frame, "OnMouseWheel", delta)
    end

    --- Drags a movable frame, leaving it anchored the way the client leaves it.
    function world:drag(frame, point, relativePoint, x, y)
        Run(frame, "OnDragStart", "LeftButton")
        frame.points = { { point, env.UIParent, relativePoint, x, y } }
        frame.point = frame.points[1]
        Run(frame, "OnDragStop")
    end

    --- Opens the game's Options window on the addon's panel, the way
    --- SettingsPanelMixin:DisplayLayout does.
    function world:openSettings()
        local category = assert(self.settings.addons[1], "the addon registered no settings panel")
        if not self.settingsPanel then
            self.settingsPanel = env.CreateFrame("Frame", nil, env.UIParent)
            self.settingsPanel:Hide()
            self.settingsCanvas = env.CreateFrame("Frame", nil, self.settingsPanel)
            self.settingsCanvas:SetSize(665, 601)
            self.settingsCanvas:Hide()
        end
        self.settingsPanel:Show()
        local frame = category.frame
        frame:SetParent(self.settingsCanvas)
        frame:ClearAllPoints()
        frame:SetAllPoints(self.settingsCanvas)
        frame:Show()
        if frame.OnRefresh then
            frame:OnRefresh()
        end
        self.settingsCanvas:Show()
        return frame
    end

    --- Moves the Options window on to another page.
    function world:leaveSettings()
        local frame = self.settings.addons[1].frame
        frame:SetParent(nil)
        frame:ClearAllPoints()
        frame:Hide()
        self.settingsCanvas:Hide()
    end

    --- Closes the Options window with whatever page it was on.
    function world:closeSettings()
        self.settingsPanel:Hide()
    end

    --- Everything printed so far, as one string; clears the buffer.
    function world:drain()
        local text = table.concat(self.output, "\n")
        self.output = {}
        return text
    end

    --- Loads the addon the way the client would: the files in the TOC, in order.
    function world:load(saved)
        local folder = REPO .. "/StatusEfficiency/"
        local ns = {}
        self.ns = ns
        rawset(env, "StatusEfficiencyDB", saved)

        -- From here on, note every global the addon creates and every global it
        -- reads that does not exist.
        self.globalWrites, self.globalMisses = {}, {}
        setmetatable(env, {
            __index = function(_, key)
                self.globalMisses[key] = true
                return nil
            end,
            __newindex = function(tbl, key, value)
                self.globalWrites[key] = true
                rawset(tbl, key, value)
            end,
        })
        self.leaks = {}
        local function Scan(value, where, depth)
            if secretValues[value] then
                self.leaks[#self.leaks + 1] = where
            elseif type(value) == "table" and depth < 3 and getmetatable(value) == nil then
                for key, inner in pairs(value) do
                    Scan(key, where, depth + 1)
                    Scan(inner, where, depth + 1)
                end
            end
        end
        local function Pack(...)
            return { n = select("#", ...), ... }
        end
        local function Watch(name, fn)
            return function(...)
                local results = Pack(fn(...))
                for i = 1, results.n do
                    Scan(results[i], "ns." .. name, 0)
                end
                return unpack(results, 1, results.n)
            end
        end

        for line in io.lines(folder .. "StatusEfficiency.toc") do
            line = line:gsub("%s+$", "")
            if line ~= "" and line:sub(1, 2) ~= "##" then
                local chunk = assert(loadfile(folder .. line))
                setfenv(chunk, env)
                chunk("StatusEfficiency", ns)
                if line == "Compat.lua" then
                    -- Nothing secret may leave the guarded layer.
                    for name, value in pairs(ns) do
                        if type(value) == "function" and name ~= "Log" and name ~= "MarkDirty" then
                            ns[name] = Watch(name, value)
                        end
                    end
                end
            end
        end
        self:fire("ADDON_LOADED", "StatusEfficiency")
        self:fire("PLAYER_LOGIN")
        self:fire("PLAYER_ENTERING_WORLD", true, false)
        self:fire("SPELLS_CHANGED")
        self:advance(0.5)
        return ns
    end

    return world
end

return Mock
