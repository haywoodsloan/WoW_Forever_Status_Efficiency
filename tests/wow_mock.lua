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
--                  "ids" (default) plain instance ids, "count" a list of secret
--                  ids, "none" a Lua error, "empty" an empty list whatever the
--                  enemy really carries.
--   combatBuffs    the same choice for counting the player's buffs, when the
--                  client treats them differently. Defaults to combatAuras.
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
    options.combatAuras = options.combatAuras or "ids"
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
        spells = {}, -- id -> { name, description, harmful, helpful, passive, override, effect }
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
        return "1.60.1", "70888", "Nov 11 2026", 16001
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
            return { name = data.name, spellID = data.id, iconID = 1, castTime = 0, minRange = 0, maxRange = 0 }
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
    }

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

    local FONTS = {
        GameFontNormal = true, GameFontNormalLarge = true, GameFontNormalSmall = true,
        GameFontHighlight = true, GameFontHighlightSmall = true, GameFontDisableSmall = true,
    }
    for font in pairs(FONTS) do
        env[font] = { fontObject = font }
    end

    local Region = {}
    Region.__index = Region
    function Region:SetPoint(point, ...)
        if type(point) ~= "string" then
            error("SetPoint: bad point", 2)
        end
        self.points = self.points or {}
        self.points[#self.points + 1] = { point, ... }
        self.point = { point, ... }
    end
    function Region:ClearAllPoints()
        self.points, self.point = nil, nil
    end
    function Region:SetAllPoints() end
    function Region:SetSize(width, height)
        self.width, self.height = width, height
    end
    function Region:SetWidth(width)
        self.width = width
    end
    function Region:SetHeight(height)
        self.height = height
    end
    function Region:GetWidth()
        return self.width or 0
    end
    function Region:GetHeight()
        return self.height or 0
    end
    function Region:SetAlpha() end
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
    function Texture:SetTexture(path)
        self.path = path
        self.color = nil
    end
    function Texture:GetTexture()
        return self.path
    end
    function Texture:SetColorTexture(r, g, b, a)
        if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
            error("SetColorTexture: bad colour", 2)
        end
        self.color = { r, g, b, a }
        self.path = nil
    end
    function Texture:SetTexCoord() end
    function Texture:SetVertexColor() end

    local FontString = setmetatable({}, { __index = Region })
    FontString.__index = FontString
    function FontString:SetText(text)
        self.text = text
    end
    function FontString:GetText()
        return self.text
    end
    function FontString:SetJustifyH() end
    function FontString:SetJustifyV() end
    function FontString:SetTextColor() end
    function FontString:SetWordWrap() end

    local Frame = setmetatable({}, { __index = Region })
    Frame.__index = Frame

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
        self.scripts[kind] = fn
    end
    function Frame:GetScript(kind)
        return self.scripts[kind]
    end
    function Frame:SetFrameLevel(level)
        self.level = level
    end
    function Frame:GetFrameLevel()
        return self.level or 1
    end
    function Frame:SetFrameStrata(strata)
        self.strata = strata
    end
    function Frame:EnableMouse() end
    function Frame:SetMovable() end
    function Frame:SetClampedToScreen() end
    function Frame:RegisterForDrag() end
    function Frame:StartMoving() end
    function Frame:StopMovingOrSizing() end
    function Frame:GetName()
        return self.name
    end
    function Frame:SetParent(parent)
        self.parent = parent
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
    function Frame:Show()
        local was = self:IsVisible()
        self.shown = true
        if not was and self:IsVisible() and self.scripts.OnShow then
            self.scripts.OnShow(self)
        end
    end
    function Frame:Hide()
        local was = self:IsVisible()
        self.shown = false
        if was and self.scripts.OnHide then
            self.scripts.OnHide(self)
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

    local Button = setmetatable({}, { __index = Frame })
    Button.__index = Button
    function Button:RegisterForClicks() end
    function Button:Enable() end
    function Button:Disable() end

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
    function EditBox:SetText(text)
        self.text = tostring(text)
    end
    function EditBox:GetText()
        return self.text or ""
    end
    function EditBox:SetFocus()
        self.focus = true
    end
    function EditBox:ClearFocus()
        self.focus = false
    end
    function EditBox:HasFocus()
        return self.focus == true
    end

    local CLASSES = { Frame = Frame, Button = Button, CheckButton = Button, EditBox = EditBox }

    function env.CreateFrame(frameType, name, parent, template)
        local class = CLASSES[frameType]
        if not class then
            error("CreateFrame: unknown frame type " .. tostring(frameType), 2)
        end
        if template ~= nil then
            error("CreateFrame: the addon should not rely on the template " .. tostring(template), 2)
        end
        if options.failCreateFrameWithParent and parent then
            error("CreateFrame is not allowed right now", 2)
        end
        local frame = setmetatable({
            events = {}, unitEvents = {}, scripts = {}, textures = {}, strings = {},
            shown = true, parent = parent, name = name, frameType = frameType,
        }, class)
        world.frames[#world.frames + 1] = frame
        if name then
            rawset(env, name, frame)
        end
        return frame
    end

    env.UIParent = env.CreateFrame("Frame", "UIParent", nil)
    env.UISpecialFrames = {}
    env.GameTooltip = {
        SetOwner = function() end,
        SetText = function(self, text)
            world.tooltip = text
        end,
        Show = function() end,
        Hide = function()
            world.tooltip = nil
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

    local function Expire(mob, now)
        for i = #mob.auras, 1, -1 do
            local aura = mob.auras[i]
            if aura.expirationTime > 0 and aura.expirationTime <= now then
                table.remove(mob.auras, i)
            end
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
        for i = 1, #self.frames do
            local frame = self.frames[i]
            local handler = frame.scripts.OnUpdate
            if handler then
                local ok, err = pcall(handler, frame, dt)
                if not ok then
                    self.errors[#self.errors + 1] = tostring(err)
                end
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
        return aura
    end

    --- Puts a buff on a unit: world.player unless one is given.
    function world:applyBuff(name, duration, fromPlayer, mob)
        return self:applyAura(mob or self.player, name, duration, fromPlayer, nil, true)
    end

    function world:removeAura(mob, name)
        for i = #mob.auras, 1, -1 do
            if mob.auras[i].name == name then
                table.remove(mob.auras, i)
            end
        end
    end

    function world:kill(mob)
        mob.dead = true
        mob.engaged = false
        mob.auras = {}
    end

    --- The player dies, losing every aura, and comes back to life.
    function world:die()
        self.player.auras = {}
        self:fire("PLAYER_DEAD")
        self:leaveCombat()
    end

    --- The player casts a spell.
    --- opts: miss = true (nothing lands), travel = seconds before the effect
    --- lands, castTime = seconds between sent and success, noSent = true,
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

        self:fire("UNIT_SPELLCAST_SUCCEEDED", "player", castID, shownID)

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

    --- Clicks a button the way the mouse would.
    function world:click(button)
        local handler = assert(button.scripts.OnClick, "that widget has no click handler")
        local ok, err = pcall(handler, button, "LeftButton")
        if not ok then
            self.errors[#self.errors + 1] = tostring(err)
        end
    end

    --- Types into an edit box and presses Enter.
    function world:type(box, text)
        box:SetFocus()
        box:SetText(text)
        local ok, err = pcall(box.scripts.OnEnterPressed, box)
        if not ok then
            self.errors[#self.errors + 1] = tostring(err)
        end
    end

    --- Opens the game's Options window on the addon's panel.
    function world:openSettings()
        local category = assert(self.settings.addons[1], "the addon registered no settings panel")
        local canvas = env.CreateFrame("Frame", nil, env.UIParent)
        category.frame:SetParent(canvas)
        category.frame:Show()
        return category.frame
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
