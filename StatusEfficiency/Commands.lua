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
    local choice = ns.db.spells[name]
    if not choice then
        choice = {}
        ns.db.spells[name] = choice
    end
    return choice
end

local function WithSpell(text, fn)
    local name, problem = ResolveSpell(text)
    if not name then
        Print(problem)
        return
    end
    fn(name)
    ns.MarkBarsDirty()
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local commands = {}

local HELP = {
    "icons on your action buttons show whether casting again is worth it.",
    "  green check = no enemy it would hit has the effect, yellow half circle = some do, red X = all do.",
    "  /se options - the settings window: icon position, icon size and which icon means what",
    "  /se on | off",
    "  /se list - the spells on your bars and how each is treated",
    "  /se track <spell> | ignore <spell> | auto <spell>",
    "  /se aoe <spell> | single <spell> - judge it against every enemy in the fight, or only your target",
    "  /se duration <spell> <seconds | auto>",
    "  /se corner <tl | top | tr | left | center | right | bl | bottom | br>   /se size <pixels | auto>",
    "  /se icon <green | yellow | red> <icon name | file ID | texture path | default>   /se icons lists the names",
    "  /se debug - what the game lets the addon see right now",
    "  /se log - show or hide what the tracker is doing",
    "  /se reset - forget every setting and everything learned",
}

function commands.help()
    Print("v" .. ns.VERSION .. ", " .. HELP[1])
    for i = 2, #HELP do
        print(HELP[i])
    end
end

function commands.on()
    ns.db.enabled = true
    ns.Resume()
    Print("on.")
end

function commands.off()
    ns.db.enabled = false
    ns.HideAll()
    Print("off. /se on turns it back on.")
end

function commands.track(rest)
    WithSpell(rest, function(name)
        Choice(name).track = true
        Print(name .. " is now tracked. If it hits every enemy around you, also use /se aoe " .. name)
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

function commands.aoe(rest)
    WithSpell(rest, function(name)
        Choice(name).aoe = true
        Print(name .. " is now judged against every enemy in the fight.")
    end)
end

function commands.single(rest)
    WithSpell(rest, function(name)
        Choice(name).aoe = false
        Print(name .. " is now judged against your target only.")
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

function commands.options()
    ns.Options.Toggle()
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
    print("  or a file ID such as 136243, a texture path such as Interface\\Icons\\INV_Misc_QuestionMark, or default.")
    for i = 1, #Icons.STATES do
        local state = Icons.STATES[i]
        local current, custom = Icons.Current(state.key)
        print(format("  %s: %s", state.title, current == "custom" and tostring(custom) or current))
    end
end

function commands.icon(rest)
    local word, choice = Trim(rest):match("^(%S+)%s*(.-)$")
    local state = Icons.StateFor(word)
    if not state or choice == "" then
        Print("Usage: /se icon <green | yellow | red> <icon name | file ID | texture path | default>. /se icons lists the names.")
        return
    end
    local title = Icons.State(state).title
    local known = Icons.Choice(choice)
    if choice:lower() == "default" then
        ns.Options.Change(function()
            Icons.Set(state, nil)
        end, state)
        Print("\"" .. title .. "\" is back to its usual icon.")
    elseif known then
        ns.Options.Change(function()
            Icons.Set(state, known.key)
        end, state)
        Print("\"" .. title .. "\" now shows the " .. known.name:lower() .. ".")
    else
        local texture = Icons.ParseCustom(choice)
        if not texture then
            Print("\"" .. choice .. "\" is not an icon name, a file ID or a texture path. /se icons lists the names.")
            return
        end
        ns.Options.Change(function()
            Icons.SetCustom(state, texture)
        end, state)
        Print("\"" .. title .. "\" now shows your own texture, " .. tostring(texture) .. ".")
    end
end

function commands.log()
    ns.db.log = not ns.db.log
    Print(ns.db.log and "showing what the tracker does. /se log hides it again." or "tracker messages hidden.")
end

function commands.reset()
    ns.ResetSettings()
    ns.Options.RefreshAll()
    Print("all settings and everything learned are back to the start.")
end

local REASONS = {
    you = "you turned it on",
    ignored = "you turned it off",
    seen = "its debuff was read off an enemy",
    ["built-in"] = "a well known area debuff",
    tooltip = "castable on enemies and its tooltip mentions a duration",
}

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
        local tracked, area, duration, source = Spells:Tracking(info)
        local casts, hits = Spells:Record(info.name)
        casts, hits = floor(casts + 0.5), floor(hits + 0.5)
        if tracked then
            local why = REASONS[source] or format("a new debuff followed %d of %d casts", hits, casts)
            print(format("  |cff40d040%s|r: %s, about %ds. Tracked because %s.", info.name,
                area and "every enemy in the fight" or "your target", floor(duration + 0.5), why))
        elseif source == "ignored" then
            print(format("  |cff999999%s|r: no icon, %s.", info.name, REASONS.ignored))
        elseif source == "demoted" then
            print(format("  |cff999999%s|r: no icon, no debuff followed %d of %d casts.", info.name, casts - hits, casts))
        else
            quiet = quiet + 1
        end
    end
    if quiet == 1 then
        print("  1 other spell does not look like a status effect. /se track <spell> adds one.")
    elseif quiet > 1 then
        print(format("  %d other spells do not look like status effects. /se track <spell> adds one.", quiet))
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
        local sample = ns.SamplePlayerDebuffs(unit)
        local listed = ns.ReadPlayerDebuffs(unit)
        print(format("  Enemy target: identity readable: %s, your debuffs countable: %s%s, listed outright: %s.",
            YesNo(ns.IdentityReadable(unit)),
            SAMPLE_WORDS[sample and (sample.ids and "ids" or "count") or "none"],
            sample and format(" (%d)", sample.n) or "",
            YesNo(listed ~= nil)))
    else
        print("  No enemy targeted.")
    end

    for i = 1, 2 do
        local which = i == 1 and "open" or "hidden"
        local note = ns.probe[which]
        local label = which == "open" and "  Out of combat" or "  With aura details hidden"
        if note.time then
            print(format("%s (%s): debuffs countable: %s, listed outright: %s, identity readable: %s%s.",
                label, Ago(now, note.time), SAMPLE_WORDS[note.sample] or "no", YesNo(note.direct),
                YesNo(note.identity),
                which == "hidden" and format(", count backed by a real debuff: %s, found by name: %s",
                    YesNo(note.trusted), YesNo(note.byName)) or ""))
        else
            print(label .. ": no enemy looked at yet.")
        end
    end

    local effects = Tracker:Describe(now)
    print(format("  Effects being tracked: %d.", #effects))
    for i = 1, #effects do
        if i > 8 then
            print(format("    and %d more", #effects - 8))
            break
        end
        print(format("    %s, %ds left (%s)", effects[i].name, floor(effects[i].left + 0.5), effects[i].how))
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
