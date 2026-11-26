-- Status Efficiency: the /se slash command.

local _, ns = ...

local Spells, Tracker, Icons = ns.Spells, ns.Tracker, ns.Icons

local pairs, type, tonumber, tostring, pcall = pairs, type, tonumber, tostring, pcall
local floor = math.floor
local format = string.format

local Print = ns.Print

local function Trim(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function YesNo(value)
    return value and "yes" or "no"
end

--------------------------------------------------------------------------------
-- Finding the spell someone typed
--------------------------------------------------------------------------------

--- Turns typed text (or a shift-clicked spell link) into the name of a spell on
--- the bars. Returns the name, or nil and a reason.
local function ResolveSpell(text)
    text = Trim(text or "")
    local linked = text:match("|h%[(.-)%]|h")
    if linked then
        text = linked
    end
    if text == "" then
        return nil, "Which spell? For example: /se track Thunder Clap"
    end

    local wanted = text:lower()
    local partial, partials = nil, 0
    local list = ns.BarSpells()
    for i = 1, #list do
        local name = list[i].name
        local lower = name:lower()
        if lower == wanted then
            return name
        end
        if lower:sub(1, #wanted) == wanted then
            partial, partials = name, partials + 1
        end
    end
    if partials == 1 then
        return partial
    elseif partials > 1 then
        return nil, "More than one spell on your bars starts with \"" .. text .. "\". Type more of the name."
    end

    -- Not on a bar right now, but maybe a spell the client knows by that name.
    local name = ns.SpellName(text)
    if name then
        return name
    end
    return nil, "No spell called \"" .. text .. "\" is on your action bars."
end

local function Choice(name)
    return Spells:Choice(name)
end

local function WithSpell(text, fn)
    local name, problem = ResolveSpell(text)
    if not name then
        Print(problem)
        return
    end
    fn(name)
    ns.MarkBarsDirty()
    ns.Options.RefreshAll() -- the Spells tab shows the same choices
end

--- How a spell on the bars is treated right now: tracked, area, duration,
--- source, kind. A spell that is not on the bars gives nothing.
local function Treatment(name)
    local list = ns.BarSpells()
    for i = 1, #list do
        if list[i].name == name then
            return Spells:Tracking(list[i])
        end
    end
    return nil
end

--- A length of time in words: "21s", "2 min", "an hour or more".
local function Span(seconds)
    if seconds >= Spells.MAX_DURATION then
        return "an hour or more"
    elseif seconds >= 120 then
        return floor(seconds / 60 + 0.5) .. " min"
    end
    return floor(seconds + 0.5) .. "s"
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local commands = {}

local HELP = {
    "icons on your action buttons show whether casting again is worth it.",
    "  A debuff: green check = no enemy it would hit has it, yellow half circle = some do, red X = all do.",
    "  A buff: green check = you do not have it, red X = you do.",
    "  /se options - the settings window: when the icons appear, where they sit, how big they are, which icon",
    "    means what, and how each spell on your bars is treated",
    "  /se on | off   /se when <always | target | combat> - when the icons appear",
    "  /se usable <on | off> - an icon only on a skill you can use right now, or on every skill",
    "  /se list - the spells on your bars and how each is treated",
    "  /se track <spell> | ignore <spell> | auto <spell>",
    "  /se buff <spell> | debuff <spell> - track it as a buff on you, or as a debuff on enemies",
    "  /se aoe <spell> | single <spell> - judge a debuff against every enemy in the fight, or only your target",
    "  /se duration <spell> <seconds | auto>",
    "  /se corner <tl | top | tr | left | center | right | bl | bottom | br>   /se size <pixels | auto>",
    "  /se icon <green | yellow | red> <icon name | file ID | texture path | none | default>   /se icons lists the names",
    "  /se debug - what the game lets the addon see right now",
    "  /se log - show or hide what the tracker is doing",
    "  /se plain - draw the settings window without the game's own buttons and sliders, should they look wrong",
    "  /se reset - forget every setting and everything learned",
}

function commands.help()
    Print("v" .. ns.VERSION .. ", " .. HELP[1])
    for i = 2, #HELP do
        print(HELP[i])
    end
end

--- When the icons appear, in the words the settings window uses.
local function AppearWords(when)
    local choices = ns.Options.APPEAR_CHOICES
    for i = 1, #choices do
        if choices[i].key == when then
            return choices[i].words
        end
    end
    return tostring(when)
end

--- On which skills they appear, likewise.
local function UsableWords(only)
    local choices = ns.Options.USABLE_CHOICES
    local key = only and "usable" or "always"
    for i = 1, #choices do
        if choices[i].key == key then
            return choices[i].words
        end
    end
    return key
end

function commands.on()
    ns.SetEnabled(true)
    ns.Options.RefreshAll()
    Print("on. Icons appear " .. AppearWords(ns.db.appear) .. ", " .. UsableWords(ns.db.usableOnly) .. ".")
end

function commands.off()
    ns.SetEnabled(false)
    ns.Options.RefreshAll()
    Print("off. /se on turns it back on.")
end

local APPEAR_WORDS = {
    always = "always", all = "always",
    target = "target", targeting = "target", targeted = "target", enemy = "target",
    combat = "combat", fight = "combat", fighting = "combat",
}

function commands.when(rest)
    local when = APPEAR_WORDS[Trim(rest):lower()]
    if not when then
        Print("icons appear " .. AppearWords(ns.db.appear) .. ". /se when <always | target | combat> changes that: "
            .. "always, when targeting an enemy, or when in combat.")
        return
    end
    ns.Options.Change(function()
        ns.SetAppear(when)
    end)
    Print("icons now appear " .. AppearWords(when) .. ".")
end

commands.appear = commands.when

local USABLE_WORDS = {
    on = true, yes = true, only = true, usable = true,
    off = false, no = false, always = false, all = false, every = false,
}

--- Owns up when the setting cannot do its work on this client.
local function UsableNote()
    if ns.db.usableOnly and ns.usableProbe.usable == "no" then
        Print("this client is not telling the addon whether a skill can be used, so for now the icons show on "
            .. "every skill.")
    end
end

function commands.usable(rest)
    local only = USABLE_WORDS[Trim(rest):lower()]
    if only == nil then
        Print("icons appear " .. UsableWords(ns.db.usableOnly) .. ". /se usable <on | off> changes that: on for "
            .. "only on a skill you can use right now, off for on every skill.")
        UsableNote()
        return
    end
    ns.Options.Change(function()
        ns.SetUsableOnly(only)
    end)
    Print("icons now appear " .. UsableWords(only) .. ".")
    UsableNote()
end

function commands.track(rest)
    WithSpell(rest, function(name)
        Choice(name).track = true
        local _, area, _, _, kind = Treatment(name)
        if not kind then
            Print(name .. " is now tracked. /se buff " .. name .. " treats it as a buff on you, and /se debuff "
                .. name .. " as a debuff on enemies.")
        elseif kind == "buff" then
            Print(name .. " is now tracked, as a buff on you. /se debuff " .. name
                .. " treats it as a debuff on enemies instead.")
        elseif area then
            Print(name .. " is now tracked, as a debuff on every enemy in the fight. /se buff " .. name
                .. " treats it as a buff on you instead.")
        else
            Print(name .. " is now tracked, as a debuff on your target. /se aoe " .. name
                .. " judges it against every enemy in the fight, and /se buff " .. name
                .. " treats it as a buff on you instead.")
        end
    end)
end

function commands.buff(rest)
    WithSpell(rest, function(name)
        local choice = Choice(name)
        choice.track, choice.kind = true, "buff"
        Tracker:Forget(name)
        Print(name .. " is now tracked as a buff on you, or on the friend you have targeted if it can be cast on others.")
    end)
end

function commands.debuff(rest)
    WithSpell(rest, function(name)
        local choice = Choice(name)
        choice.track, choice.kind = true, "debuff"
        Tracker:Forget(name)
        Print(name .. " is now tracked as a debuff on enemies. /se aoe " .. name .. " and /se single " .. name
            .. " say which enemies.")
    end)
end

function commands.ignore(rest)
    WithSpell(rest, function(name)
        Choice(name).track = false
        Tracker:Forget(name)
        Print(name .. " will no longer get an icon.")
    end)
end

function commands.auto(rest)
    WithSpell(rest, function(name)
        ns.db.spells[name] = nil
        ns.db.learned[name] = nil
        Print(name .. " is back to automatic, and what was learned about it is forgotten.")
    end)
end

--- Which enemies a debuff is judged against. It is remembered for a buff
--- too, but only comes into play if the spell is made a debuff.
local function SetArea(name, area, said)
    Choice(name).aoe = area
    local _, _, _, _, kind = Treatment(name)
    if kind == "buff" then
        Print(name .. " is tracked as a buff on you, so that changes nothing for now. It would only matter after /se debuff "
            .. name)
    else
        Print(name .. said)
    end
end

function commands.aoe(rest)
    WithSpell(rest, function(name)
        SetArea(name, true, " is now judged against every enemy in the fight.")
    end)
end

function commands.single(rest)
    WithSpell(rest, function(name)
        SetArea(name, false, " is now judged against your target only.")
    end)
end

function commands.duration(rest)
    local spell, value = Trim(rest):match("^(.-)%s+(%S+)$")
    if not spell then
        Print("Usage: /se duration <spell> <seconds | auto>")
        return
    end
    local seconds = tonumber(value)
    if value:lower() ~= "auto" and not (seconds and seconds >= 1 and seconds <= 3600) then
        Print("Give the duration in seconds, from 1 to 3600, or auto.")
        return
    end
    WithSpell(spell, function(name)
        if seconds then
            Choice(name).duration = seconds
            Print(name .. " is now assumed to last " .. seconds .. " seconds.")
        else
            local choice = ns.db.spells[name]
            if choice then
                choice.duration = nil
            end
            Print(name .. " uses its own duration again.")
        end
    end)
end

function commands.size(rest)
    local value = Trim(rest):lower()
    local pixels = tonumber(value)
    if value == "auto" then
        ns.Options.Change(function()
            ns.db.size = 0
        end)
        Print("icon size follows the button again.")
    elseif pixels and pixels >= ns.SIZE_MIN and pixels <= ns.SIZE_MAX then
        ns.Options.Change(function()
            ns.db.size = floor(pixels + 0.5)
        end)
        Print("icon size is " .. ns.db.size .. ".")
    else
        Print("Usage: /se size <" .. ns.SIZE_MIN .. " to " .. ns.SIZE_MAX .. " | auto>")
    end
end

local CORNER_WORDS = {
    tl = "TOPLEFT", topleft = "TOPLEFT",
    t = "TOP", top = "TOP",
    tr = "TOPRIGHT", topright = "TOPRIGHT",
    l = "LEFT", left = "LEFT",
    c = "CENTER", center = "CENTER", centre = "CENTER", middle = "CENTER",
    r = "RIGHT", right = "RIGHT",
    bl = "BOTTOMLEFT", bottomleft = "BOTTOMLEFT",
    b = "BOTTOM", bottom = "BOTTOM",
    br = "BOTTOMRIGHT", bottomright = "BOTTOMRIGHT",
}

function commands.corner(rest)
    local word = Trim(rest):lower():gsub("[%s%-_]", "")
    local corner = CORNER_WORDS[word]
    if not corner then
        Print("Usage: /se corner <tl | top | tr | left | center | right | bl | bottom | br>")
        return
    end
    ns.Options.Change(function()
        ns.db.corner = corner
    end)
    Print("icons moved to the " .. ns.Options.POSITION_NAMES[corner]:lower() .. " of each button.")
end

commands.position = commands.corner

local TAB_WORDS = { spells = "spells", spell = "spells", appearance = "appearance", look = "appearance", icons = "appearance" }

function commands.options(rest)
    local tab = TAB_WORDS[Trim(rest or ""):lower()]
    if tab then
        ns.Options.Open(tab) -- a tab was named: bring the window up on it
    else
        ns.Options.Toggle()
    end
end

commands.config = commands.options
commands.settings = commands.options

function commands.icons()
    Print("icons you can pick with /se icon <green | yellow | red> <name>:")
    local line = {}
    for i = 1, #Icons.CHOICES do
        line[#line + 1] = Icons.CHOICES[i].key
        if #line == 7 or i == #Icons.CHOICES then
            print("  " .. table.concat(line, ", "))
            line = {}
        end
    end
    print("  or a file ID such as 136243, a texture path such as Interface\\Icons\\INV_Misc_QuestionMark,")
    print("  none for no icon at all, or default.")
    for i = 1, #Icons.STATES do
        local state = Icons.STATES[i]
        local current, custom = Icons.Current(state.key)
        if current == Icons.HIDDEN then
            current = "none"
        elseif current == "custom" then
            current = tostring(custom)
        end
        print(format("  %s: %s", state.title, current))
    end
end

function commands.icon(rest)
    local word, choice = Trim(rest):match("^(%S+)%s*(.-)$")
    local state = Icons.StateFor(word)
    if not state or choice == "" then
        Print("Usage: /se icon <green | yellow | red> <icon name | file ID | texture path | none | default>. "
            .. "/se icons lists the names.")
        return
    end
    local title = Icons.State(state).title
    local known = Icons.Choice(choice)
    if choice:lower() == "default" then
        ns.Options.Change(function()
            Icons.Set(state, nil)
        end)
        Print("\"" .. title .. "\" is back to its usual icon.")
    elseif known then
        ns.Options.Change(function()
            Icons.Set(state, known.key)
        end)
        Print("\"" .. title .. "\" now shows the " .. known.name:lower() .. ".")
    elseif Icons.IsHiddenWord(choice) then
        ns.Options.Change(function()
            Icons.SetHidden(state)
        end)
        Print("\"" .. title .. "\" now shows no icon. /se icon " .. state .. " default brings its icon back.")
    else
        local texture = Icons.ParseCustom(choice)
        if not texture then
            Print("\"" .. choice .. "\" is not an icon name, a file ID or a texture path. /se icons lists the names.")
            return
        end
        ns.Options.Change(function()
            Icons.SetCustom(state, texture)
        end)
        Print("\"" .. title .. "\" now shows your own texture, " .. tostring(texture) .. ".")
    end
end

function commands.log()
    ns.db.log = not ns.db.log
    Print(ns.db.log and "showing what the tracker does. /se log hides it again." or "tracker messages hidden.")
end

function commands.plain()
    ns.db.plain = not ns.db.plain
    Print(ns.db.plain
        and "the settings window will draw its own buttons and sliders. Type /reload to see it. /se plain again brings the game's own back."
        or "the settings window will use the game's own buttons and sliders again. Type /reload to see it.")
end

function commands.reset()
    ns.ResetSettings()
    ns.Options.PlaceWindow()
    ns.Options.RefreshAll()
    Print("all settings and everything learned are back to the start.")
end

local REASONS = {
    debuff = {
        you = "you turned it on",
        seen = "its debuff was read off an enemy",
        ["built-in"] = "it is a well known area debuff",
        tooltip = "it can be cast on enemies and its tooltip mentions a duration",
    },
    buff = {
        you = "you turned it on",
        seen = "its buff was read off you",
        tooltip = "it is cast on yourself or friends and its tooltip mentions a duration",
    },
}

--- Where a tracked spell's effect is looked for, in words.
local function Where(info, area, kind)
    if kind == "buff" then
        if info.helpful == true and info.selfOnly ~= true then
            return "a buff on you, or on the friend you have targeted"
        end
        return "a buff on you"
    end
    return area and "a debuff on every enemy in the fight" or "a debuff on your target"
end

function commands.list()
    local list = ns.BarSpells()
    if #list == 0 then
        Print("no spells found on your action bars yet.")
        return
    end
    Print("spells on your action bars:")
    local quiet = 0
    for i = 1, #list do
        local info = list[i]
        local tracked, area, duration, source, kind = Spells:Tracking(info)
        local casts, hits = Spells:Record(info.name, kind)
        casts, hits = floor(casts + 0.5), floor(hits + 0.5)
        if tracked then
            local why = REASONS[kind][source] or format("a new effect of yours followed %d of %d casts", hits, casts)
            print(format("  |cff40d040%s|r: %s, lasting %s. Tracked because %s.", info.name,
                Where(info, area, kind), Span(duration), why))
        elseif source == "ignored" then
            print(format("  |cff999999%s|r: no icon, you turned it off.", info.name))
        elseif source == "demoted" then
            print(format("  |cff999999%s|r: no icon, no new effect of yours followed %d of %d casts.", info.name,
                casts - hits, casts))
        else
            quiet = quiet + 1
        end
    end
    local ADD = " /se track <spell> adds one, and /se buff <spell> adds one as a buff on you. The Spells tab of /se options does the same with clicks."
    if quiet == 1 then
        print("  1 other spell does not look like a status effect." .. ADD)
    elseif quiet > 1 then
        print(format("  %d other spells do not look like status effects.", quiet) .. ADD)
    end
end

local function Ago(now, when)
    if not when then
        return "not seen yet"
    end
    return format("%ds ago", floor(now - when + 0.5))
end

local SAMPLE_WORDS = {
    ids = "yes, one by one",
    count = "the count only",
    none = "no",
}

--- One line of /se debug about what the client allowed at the last look.
local function ProbeLine(label, note, now, hidden, identity)
    if not note.time then
        return label .. ": not looked at yet."
    end
    local text = format("%s (%s): countable: %s, listed outright: %s", label, Ago(now, note.time),
        SAMPLE_WORDS[note.sample] or "no", YesNo(note.direct))
    if identity then
        text = text .. ", identity readable: " .. YesNo(note.identity)
    end
    if hidden then
        text = text .. format(", count backed by a real one: %s, found by name: %s", YesNo(note.trusted),
            YesNo(note.byName))
    end
    return text .. "."
end

--- What can be read about your effects of one kind on a unit right now.
local function ReadableNow(unit, kind)
    local sample = ns.SampleAuras(unit, kind)
    local listed = ns.ReadAuras(unit, kind)
    return format("countable: %s%s, listed outright: %s",
        SAMPLE_WORDS[sample and (sample.ids and "ids" or "count") or "none"],
        sample and format(" (%d)", sample.n) or "", YesNo(listed ~= nil))
end

function commands.debug()
    local now = ns.Now()
    local ok, version, build, _, interface = pcall(GetBuildInfo)
    if not ok then
        version, build, interface = "?", "?", "?"
    end
    Print(format("v%s on client %s (build %s), interface %s.", ns.VERSION,
        tostring(ns.Plain(version)), tostring(ns.Plain(build)), tostring(ns.Plain(interface))))
    print(format("  Secret values: %s. Aura details hidden right now: %s. In combat: %s.",
        YesNo(ns.hasSecretValues), YesNo(ns.AurasSecret()), YesNo(ns.InCombat())))

    local buttons, withSpell, showing = #ns.buttons, 0, 0
    for i = 1, buttons do
        local entry = ns.buttons[i]
        if entry.info then
            withSpell = withSpell + 1
        end
        if entry.state then
            showing = showing + 1
        end
    end
    print(format("  Action buttons found: %d, holding a spell: %d, showing an icon: %d. Enabled: %s.",
        buttons, withSpell, showing, YesNo(ns.db.enabled)))

    local unit = ns.PrimaryEnemy()
    if unit then
        print(format("  Enemy target right now: your debuffs %s, identity readable: %s.",
            ReadableNow(unit, "debuff"), YesNo(ns.IdentityReadable(unit))))
    else
        print("  No enemy targeted.")
    end
    print(format("  You right now: your buffs %s.", ReadableNow("player", "buff")))

    local probe = ns.probe
    print(ProbeLine("  Enemy debuffs, out of combat", probe.open, now, false, true))
    print(ProbeLine("  Enemy debuffs, details hidden", probe.hidden, now, true, true))
    print(ProbeLine("  Your buffs, out of combat", probe.buffs.open, now, false, false))
    print(ProbeLine("  Your buffs, details hidden", probe.buffs.hidden, now, true, false))

    local effects = Tracker:Describe(now)
    local me = ns.KeyOf("player", "buff")
    print(format("  Effects being tracked: %d.", #effects))
    for i = 1, #effects do
        if i > 8 then
            print(format("    and %d more", #effects - 8))
            break
        end
        local key, left = effects[i].key, effects[i].left
        local where = key == me and " on you" or (key:sub(-6) == "+buffs" and " on a friend" or "")
        print(format("    %s%s, %s (%s)", effects[i].name, where, left and (Span(left) .. " left") or "no end time",
            effects[i].how))
    end

    local options = ns.Options
    print(format("  Settings panel in the game's Options window: %s%s.", YesNo(options.registered == true),
        options.problem and (" (" .. options.problem .. ")") or ""))

    if ns.lastError then
        print(format("  Last problem (%d so far): %s", ns.errorCount or 1, ns.lastError))
    else
        print("  No problems recorded.")
    end
    if ns.halted then
        print("  The addon stopped itself after repeated problems. /se on starts it again.")
    end
end

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

local function Run(message)
    message = Trim(type(message) == "string" and message or "")
    local word, rest = message:match("^(%S+)%s*(.*)$")
    local command = word and commands[word:lower()]
    if not command then
        commands.help()
        return
    end
    command(rest or "")
end

SLASH_STATUSEFFICIENCY1 = "/se"
SLASH_STATUSEFFICIENCY2 = "/statusefficiency"
SlashCmdList["STATUSEFFICIENCY"] = function(message)
    local ok, err = pcall(Run, message)
    if not ok then
        Print("that command ran into a problem: " .. tostring(err))
    end
end

ns.RunCommand = Run
