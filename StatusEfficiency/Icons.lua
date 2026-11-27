-- Status Efficiency: the three results an icon can show, and the icons each one
-- can use.

local ADDON_NAME, ns = ...

local Icons = {}
ns.Icons = Icons

local type, tonumber, tostring = type, tonumber, tostring

local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
local READY = "Interface\\RaidFrame\\ReadyCheck-"
local RAID = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"

--- The three things an icon can say, in the order they are shown. Each is named
--- for what it tells you to do, so it reads the same for a debuff on enemies and
--- for a buff on you. The middle one is for an effect that is there, but not on
--- every enemy the spell would hit, or not yet as many times over as it stacks.
Icons.STATES = {
    {
        key = "none",
        title = "Worth casting",
        detail = "Nothing it would land on has the effect yet.",
        default = "check",
    },
    {
        key = "some",
        title = "Partly worth casting",
        detail = "Some enemies have the effect, or it can still stack higher.",
        default = "partial",
    },
    {
        key = "all",
        title = "No need to cast",
        detail = "Everything it would land on already has the effect.",
        default = "cross",
    },
}

--- The icons on offer. The first ten ship with the addon (`own`); the rest are
--- the game's own art.
Icons.CHOICES = {
    { key = "check", name = "Green check", texture = MEDIA .. "Check.tga", own = true },
    { key = "partial", name = "Yellow half circle", texture = MEDIA .. "Partial.tga", own = true },
    { key = "cross", name = "Red X", texture = MEDIA .. "Cross.tga", own = true },
    { key = "greendot", name = "Green dot", texture = MEDIA .. "DotGreen.tga", own = true },
    { key = "yellowdot", name = "Yellow dot", texture = MEDIA .. "DotYellow.tga", own = true },
    { key = "reddot", name = "Red dot", texture = MEDIA .. "DotRed.tga", own = true },
    { key = "plus", name = "Green plus", texture = MEDIA .. "Plus.tga", own = true },
    { key = "exclaim", name = "Yellow exclamation mark", texture = MEDIA .. "Exclaim.tga", own = true },
    { key = "stop", name = "Red stop sign", texture = MEDIA .. "Stop.tga", own = true },
    { key = "ring", name = "Yellow ring", texture = MEDIA .. "Ring.tga", own = true },
    { key = "ready", name = "Ready check: ready", texture = READY .. "Ready" },
    { key = "waiting", name = "Ready check: waiting", texture = READY .. "Waiting" },
    { key = "notready", name = "Ready check: not ready", texture = READY .. "NotReady" },
    { key = "star", name = "Raid marker: star", texture = RAID .. "1" },
    { key = "circle", name = "Raid marker: circle", texture = RAID .. "2" },
    { key = "diamond", name = "Raid marker: diamond", texture = RAID .. "3" },
    { key = "triangle", name = "Raid marker: triangle", texture = RAID .. "4" },
    { key = "moon", name = "Raid marker: moon", texture = RAID .. "5" },
    { key = "square", name = "Raid marker: square", texture = RAID .. "6" },
    { key = "redx", name = "Raid marker: cross", texture = RAID .. "7" },
    { key = "skull", name = "Raid marker: skull", texture = RAID .. "8" },
}

--- A result can also be given no icon at all, so its buttons stay bare.
local HIDDEN = "hidden"
Icons.HIDDEN = HIDDEN
Icons.HIDDEN_NAME = "No icon"

--- Icons that belong together, one per result, to set all three in one go.
Icons.SETS = {
    { key = "marks", name = "Check, half circle and X", icons = { none = "check", some = "partial", all = "cross" } },
    { key = "dots", name = "Green, yellow and red dots", icons = { none = "greendot", some = "yellowdot", all = "reddot" } },
    { key = "symbols", name = "Plus, exclamation mark and stop sign", icons = { none = "plus", some = "exclaim", all = "stop" } },
    { key = "ready", name = "The game's ready check marks", icons = { none = "ready", some = "waiting", all = "notready" } },
}

local byKey = {}
for i = 1, #Icons.CHOICES do
    byKey[Icons.CHOICES[i].key] = Icons.CHOICES[i]
end

local stateByKey = {}
for i = 1, #Icons.STATES do
    stateByKey[Icons.STATES[i].key] = Icons.STATES[i]
end

-- Words people use for the three results on the command line.
local STATE_WORDS = {
    none = "none", green = "none", check = "none", clean = "none", fresh = "none", worth = "none",
    some = "some", yellow = "some", partial = "some", half = "some", partly = "some",
    all = "all", red = "all", cross = "all", x = "all", full = "all", noneed = "all",
}

-- And for giving a result no icon.
local HIDDEN_WORDS = { none = true, hidden = true, hide = true, off = true, nothing = true, blank = true }

--- The result a typed word refers to ("green", "some", "x" ...), or nil.
function Icons.StateFor(word)
    return type(word) == "string" and STATE_WORDS[word:lower()] or nil
end

--- True when a typed word asks for no icon at all ("none", "hidden", "off" ...).
function Icons.IsHiddenWord(word)
    return type(word) == "string" and HIDDEN_WORDS[word:lower()] == true
end

function Icons.State(state)
    return stateByKey[state]
end

--- The choice with this key, or nil.
function Icons.Choice(key)
    return type(key) == "string" and byKey[key:lower()] or nil
end

local function ValidCustom(value)
    return (type(value) == "number" and value > 0) or (type(value) == "string" and value ~= "")
end

--- What a result is set to: a choice key, "hidden", or "custom" plus the texture.
function Icons.Current(state)
    local key = ns.db.icons[state]
    if key == HIDDEN then
        return HIDDEN
    elseif key == "custom" then
        local custom = ns.db.custom[state]
        if ValidCustom(custom) then
            return "custom", custom
        end
    elseif byKey[key] then
        return key
    end
    return stateByKey[state].default
end

--- The texture to draw for a result: a file path or a file id, or nil when the
--- result is set to show no icon.
function Icons.Texture(state)
    local key, custom = Icons.Current(state)
    if key == HIDDEN then
        return nil
    elseif key == "custom" then
        return custom
    end
    return byKey[key].texture
end

--- What a result is set to, in words.
function Icons.CurrentName(state)
    local key, custom = Icons.Current(state)
    if key == HIDDEN then
        return Icons.HIDDEN_NAME
    elseif key == "custom" then
        return "Your own texture, " .. tostring(custom)
    end
    return byKey[key].name
end

function Icons.Set(state, key)
    ns.db.icons[state] = key
    ns.db.custom[state] = nil
end

function Icons.SetCustom(state, texture)
    ns.db.icons[state] = "custom"
    ns.db.custom[state] = texture
end

function Icons.SetHidden(state)
    ns.db.icons[state] = HIDDEN
    ns.db.custom[state] = nil
end

function Icons.ResetAll()
    ns.Wipe(ns.db.icons)
    ns.Wipe(ns.db.custom)
end

--- Gives all three results the icons of one set.
function Icons.ApplySet(set)
    for i = 1, #Icons.STATES do
        local state = Icons.STATES[i].key
        Icons.Set(state, set.icons[state])
    end
end

--- The set all three results are on right now, or nil when they are mixed.
function Icons.CurrentSet()
    for i = 1, #Icons.SETS do
        local set, match = Icons.SETS[i], true
        for j = 1, #Icons.STATES do
            local state = Icons.STATES[j].key
            if Icons.Current(state) ~= set.icons[state] then
                match = false
            end
        end
        if match then
            return set
        end
    end
    return nil
end

--- The earlier result that shows the very same icon as this one, if any: the two
--- could not be told apart on a button. Results with no icon never clash.
function Icons.SharedWith(state)
    local art = Icons.Texture(state)
    if art == nil then
        return nil
    end
    for i = 1, #Icons.STATES do
        local other = Icons.STATES[i]
        if other.key == state then
            return nil
        end
        if Icons.Texture(other.key) == art then
            return other
        end
    end
    return nil
end

--- Reads a texture someone typed: a file id such as 136243, or a path such as
--- Interface\Icons\Spell_Nature_Slow. Returns nil when it is neither.
function Icons.ParseCustom(text)
    if type(text) ~= "string" then
        return nil
    end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text:find("^%d+$") then
        local id = tonumber(text)
        if id and id > 0 then
            return id
        end
        return nil
    end
    if text:find("[\\/]") and not text:find("|", 1, true) then
        return (text:gsub("/", "\\"))
    end
    return nil
end
