-- Status Efficiency: the three indications and the icons each one can use.

local ADDON_NAME, ns = ...

local Icons = {}
ns.Icons = Icons

local type, tonumber = type, tonumber

local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
local READY = "Interface\\RaidFrame\\ReadyCheck-"
local RAID = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"

--- The three things an icon can say, in the order they are shown.
Icons.STATES = {
    {
        key = "none",
        title = "No enemy has it",
        detail = "Casting puts the effect on every enemy the spell would hit.",
        default = "check",
    },
    {
        key = "some",
        title = "Some enemies have it",
        detail = "Casting puts the effect on some enemies. Others already have it.",
        default = "partial",
    },
    {
        key = "all",
        title = "Every enemy has it",
        detail = "Casting again would change nothing.",
        default = "cross",
    },
}

--- The icons on offer. The first ten ship with the addon; the rest are the
--- game's own art.
Icons.CHOICES = {
    { key = "check", name = "Green check", texture = MEDIA .. "Check.tga" },
    { key = "partial", name = "Yellow half circle", texture = MEDIA .. "Partial.tga" },
    { key = "cross", name = "Red X", texture = MEDIA .. "Cross.tga" },
    { key = "greendot", name = "Green dot", texture = MEDIA .. "DotGreen.tga" },
    { key = "yellowdot", name = "Yellow dot", texture = MEDIA .. "DotYellow.tga" },
    { key = "reddot", name = "Red dot", texture = MEDIA .. "DotRed.tga" },
    { key = "plus", name = "Green plus", texture = MEDIA .. "Plus.tga" },
    { key = "exclaim", name = "Yellow exclamation mark", texture = MEDIA .. "Exclaim.tga" },
    { key = "stop", name = "Red stop sign", texture = MEDIA .. "Stop.tga" },
    { key = "ring", name = "Yellow ring", texture = MEDIA .. "Ring.tga" },
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

local byKey = {}
for i = 1, #Icons.CHOICES do
    byKey[Icons.CHOICES[i].key] = Icons.CHOICES[i]
end

local stateByKey = {}
for i = 1, #Icons.STATES do
    stateByKey[Icons.STATES[i].key] = Icons.STATES[i]
end

-- Words people use for the three indications on the command line.
local STATE_WORDS = {
    none = "none", green = "none", check = "none", clean = "none", fresh = "none",
    some = "some", yellow = "some", partial = "some", half = "some",
    all = "all", red = "all", cross = "all", x = "all", full = "all",
}

--- The indication a typed word refers to ("green", "some", "x" ...), or nil.
function Icons.StateFor(word)
    return type(word) == "string" and STATE_WORDS[word:lower()] or nil
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

--- What an indication is set to: a choice key, or "custom" plus the texture.
function Icons.Current(state)
    local key = ns.db.icons[state]
    if key == "custom" then
        local custom = ns.db.custom[state]
        if ValidCustom(custom) then
            return "custom", custom
        end
    elseif byKey[key] then
        return key
    end
    return stateByKey[state].default
end

--- The texture to draw for an indication: a file path, or a file id.
function Icons.Texture(state)
    local key, custom = Icons.Current(state)
    if key == "custom" then
        return custom
    end
    return byKey[key].texture
end

function Icons.Set(state, key)
    ns.db.icons[state] = key
    ns.db.custom[state] = nil
end

function Icons.SetCustom(state, texture)
    ns.db.icons[state] = "custom"
    ns.db.custom[state] = texture
end

function Icons.ResetAll()
    ns.Wipe(ns.db.icons)
    ns.Wipe(ns.db.custom)
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
