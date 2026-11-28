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

--- Turns typed text (or a shift-clicked spell link) into the name of a skill on
--- the bars. Returns the name, or nil and a reason.
local function ResolveSpell(text)
    text = Trim(text or "")
    local linked = text:match("|h%[(.-)%]|h")
    if linked then
        text = linked
    end
    if text == "" then
        return nil, "Which skill? Type its name after the command, as in /se track Thunder Clap."
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
        return nil, "More than one skill on your action bars starts with \"" .. text .. "\". Type more of the name."
    end

    -- Not on a bar right now, but maybe a spell the client knows by that name.
    local name = ns.SpellName(text)
    if name then
        return name
    end
    return nil, "No skill called \"" .. text .. "\" is on your action bars."
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
    ns.Options.RefreshAll() -- the Skills tab shows the same choices
end

--- The skill of that name on the action bars, as ns.BarSpells lists it.
local function OnBars(name)
    local list = ns.BarSpells()
    for i = 1, #list do
        if list[i].name == name then
            return list[i]
        end
    end
    return nil
end

--- How a spell on the bars is treated right now: tracked, area, duration,
--- source, kind. A spell that is not on the bars gives nothing.
local function Treatment(name)
    local info = OnBars(name)
    if info then
        return Spells:Tracking(info)
    end
    return nil
end

--- A length of time in short, for /se debug: "21s", "2 min", "an hour or more".
local function Span(seconds)
    if seconds >= Spells.MAX_DURATION then
        return "an hour or more"
    elseif seconds >= 120 then
        return floor(seconds / 60 + 0.5) .. " min"
    end
    return floor(seconds + 0.5) .. "s"
end

--- A number of things in words: "1 second", "21 seconds".
local function Count(number, one, many)
    return number .. " " .. (number == 1 and one or many)
end

--- A length of time written out: "21 seconds", "2 minutes", "an hour or more".
local function Lasting(seconds)
    if seconds >= Spells.MAX_DURATION then
        return "an hour or more"
    elseif seconds >= 120 then
        return Count(floor(seconds / 60 + 0.5), "minute", "minutes")
    end
    return Count(floor(seconds + 0.5), "second", "seconds")
end

--- True for a buff skill that can be used on a friend as well as on you: its
--- icon looks at the friend you have targeted, when there is one.
local function OnFriends(info)
    return info ~= nil and info.helpful == true and info.selfOnly ~= true
end

--- Whom the icon of a buff skill looks at, as a sentence. `what` is how the
--- buff was last spoken of: "its buff", or "it".
local function BuffChecks(info, what)
    if OnFriends(info) then
        return "The icon checks you, or the friend you have targeted, for " .. what .. "."
    end
    return "The icon checks you for " .. what .. "."
end

--- What to say of a skill that was put on Always while it is on no action
--- button. `as` is what its effect will be treated as, where that was said.
local function NotOnBars(name, as)
    return name .. " is now on Always" .. (as and (", and its effect is treated as " .. as) or "")
        .. ", but it is not on your action bars right now. It will have an icon as soon as it is."
end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

local commands = {}

local HELP = {
    "An icon on each action button shows whether using that skill again would do anything.",
    "  For a debuff, the green check means that no enemy it would hit has it, the yellow half circle that some",
    "    of them do, and the red X that all of them do.",
    "  For a buff, the green check means that you do not have it, and the red X that you do.",
    "  For an effect that stacks, the green check stays until all of its stacks are there.",
    "  An icon never tells you to use a skill on an enemy that is immune to it. /se immune lists those enemies.",
    "  /se options - opens the settings window, where all of this can be set with clicks",
    "  /se on | off - turns the icons on or off",
    "  /se when <always | combat | group> - sets when the icons appear",
    "  /se usable <on | off> - shows an icon only on a skill you can use right now, or on every skill",
    "  /se nameplates <on | tell | off> - when enemy nameplates are off, turns them back on and says so, only",
    "    says so, or does nothing. The addon reads the enemies around you from them",
    "  /se list - lists the skills on your action bars and what the addon does with each",
    "  /se track <skill> - puts a skill on Always, so it has an icon",
    "  /se ignore <skill> - puts a skill on Never, so it has no icon",
    "  /se auto <skill> - puts a skill back on Auto, so the addon decides about it by itself again",
    "  /se buff <skill> | debuff <skill> - treats a skill's effect as a buff on you, or as a debuff on enemies",
    "  /se aoe <skill> | single <skill> - makes the icon check every enemy in the fight, or only your target",
    "  /se duration <skill> <seconds | auto> - sets how long a skill's effect lasts",
    "  /se stacks <skill> <number | auto> - sets the most stacks a skill's effect can have",
    "  /se anyone <skill> | mine <skill> - counts another player's effect like your own, or ignores it",
    "  /se immune - lists the enemies that are immune to a skill",
    "  /se immune <skill> - adds the kind of enemy you have targeted to that list",
    "  /se immune forget [skill] - clears the list, for one skill or for all of them",
    "  /se corner <tl | top | tr | left | center | right | bl | bottom | br> - moves the icon on the button",
    "  /se size <pixels | auto> - sets how big the icon is",
    "  /se icon <green | yellow | red> <icon name | file ID | path | none | default> - picks the icon shown",
    "    for one of the three results. /se icons lists the names",
    "  /se debug - prints technical details, for tracking down a problem",
    "  /se log - shows or hides a running log of what the addon notices",
    "  /se plain - makes the settings window draw its own buttons and sliders instead of the game's. It does",
    "    that by itself where the game's are missing or do not work",
    "  /se reset - clears every setting and everything the addon has learned",
}

function commands.help()
    Print("Version " .. ns.VERSION .. ". " .. HELP[1])
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
    Print("The icons are on. They appear " .. AppearWords(ns.db.appear) .. ", and " .. UsableWords(ns.db.usableOnly)
        .. ".")
end

function commands.off()
    ns.SetEnabled(false)
    ns.Options.RefreshAll()
    Print("The icons are off. Type /se on to turn them back on.")
end

local APPEAR_WORDS = {
    always = "always", all = "always",
    combat = "combat", fight = "combat", fighting = "combat",
    group = "group", party = "group", raid = "group",
}

function commands.when(rest)
    local when = APPEAR_WORDS[Trim(rest):lower()]
    if not when then
        Print("The icons appear " .. AppearWords(ns.db.appear) .. ". To change that, type /se when always, /se when "
            .. "combat (when you are in combat) or /se when group (when you or your group are in combat).")
        return
    end
    ns.Options.Change(function()
        ns.SetAppear(when)
    end)
    Print("The icons now appear " .. AppearWords(when) .. ".")
end

commands.appear = commands.when

local USABLE_WORDS = {
    on = true, yes = true, only = true, usable = true,
    off = false, no = false, always = false, all = false, every = false,
}

--- Owns up when the setting cannot do its work on this client: asked about
--- the action, about the spell, and with the button itself looked at, nothing
--- said whether a skill can be used.
local function UsableNote()
    if ns.db.usableOnly and ns.usableProbe.usable == "no" then
        Print("The game is not telling the addon whether a skill can be used, so for now the icons are shown on "
            .. "every skill.")
    end
end

function commands.usable(rest)
    local only = USABLE_WORDS[Trim(rest):lower()]
    if only == nil then
        Print("The icons appear " .. UsableWords(ns.db.usableOnly) .. ". To change that, type /se usable on (only "
            .. "on skills you can use right now) or /se usable off (on every skill).")
        UsableNote()
        return
    end
    ns.Options.Change(function()
        ns.SetUsableOnly(only)
    end)
    Print("The icons now appear " .. UsableWords(only) .. ".")
    UsableNote()
end

-- What the addon does when enemy nameplates are off, by choice: each follows
-- "the addon".
local PLATE_WORDS = {
    on = "turns them back on and says so in chat",
    tell = "only says so in chat",
    off = "does nothing",
}

--- How things stand with enemy nameplates right now, as a sentence to follow
--- another. `kept` is what ns.KeepsNameplates says. Nothing where the game
--- does not say whether they are shown.
local function PlatesNow(kept)
    local shown = ns.EnemyPlates()
    if shown == nil then
        return ""
    elseif shown then
        return " They are on right now."
    elseif kept == "later" then
        return " They are off right now, and the game does not let an addon turn them on during a fight, so the "
            .. "addon does that when your fight ends."
    elseif kept == "refused" then
        return " They are off right now, and the game did not let the addon turn them on. " .. ns.ShowPlatesWords()
            .. "."
    end
    return " They are off right now, so " .. ns.BLIND_WORDS .. "."
end

--- /se nameplates: what the addon does when enemy nameplates are off.
function commands.nameplates(rest)
    local choice = Trim(rest):lower()
    if not PLATE_WORDS[choice] then
        Print("When enemy nameplates are off, the addon " .. PLATE_WORDS[ns.db.nameplates] .. "."
            .. PlatesNow(ns.KeepsNameplates()) .. " It reads the enemies around you from them. To change what it "
            .. "does, type /se nameplates on (it turns them back on and says so), /se nameplates tell (it only says "
            .. "so) or /se nameplates off (it does nothing).")
        return
    end
    local result, turned
    ns.Options.Change(function()
        result, turned = ns.SetNameplates(choice)
    end)
    Print("When enemy nameplates are off, the addon now " .. PLATE_WORDS[choice] .. "."
        .. (turned and " They were off, so it turned them on." or PlatesNow(result)))
end

commands.plates = commands.nameplates

function commands.track(rest)
    WithSpell(rest, function(name)
        Choice(name).track = true
        local info = OnBars(name)
        local _, area, _, _, kind = Treatment(name)
        local now = name .. " is now on Always, so it has an icon. "
        if not info then
            Print(NotOnBars(name) .. " If the addon then gets its effect wrong, type /se buff " .. name
                .. " for a buff on you, or /se debuff " .. name .. " for a debuff on enemies.")
        elseif kind == "buff" then
            Print(now .. BuffChecks(info, "its buff") .. " If " .. name
                .. " puts a debuff on enemies instead, type /se debuff " .. name .. ".")
        elseif area then
            Print(now .. "The icon checks every enemy in the fight for its debuff. If " .. name
                .. " gives you a buff instead, type /se buff " .. name .. ".")
        else
            Print(now .. "The icon checks the enemy you have targeted for its debuff. If " .. name
                .. " hits every enemy in the fight, type /se aoe " .. name .. ". If it gives you a buff instead, "
                .. "type /se buff " .. name .. ".")
        end
    end)
end

function commands.buff(rest)
    WithSpell(rest, function(name)
        local choice = Choice(name)
        choice.track, choice.kind = true, "buff"
        Tracker:Forget(name)
        local info = OnBars(name)
        if not info then
            Print(NotOnBars(name, "a buff"))
        else
            Print(name .. " is now on Always, so it has an icon, and its effect is treated as a buff. "
                .. BuffChecks(info, "it"))
        end
    end)
end

function commands.debuff(rest)
    WithSpell(rest, function(name)
        local choice = Choice(name)
        choice.track, choice.kind = true, "debuff"
        Tracker:Forget(name)
        local _, area = Treatment(name)
        local now = name .. " is now on Always, so it has an icon, and its effect is treated as a debuff. "
        if not OnBars(name) then
            Print(NotOnBars(name, "a debuff on enemies"))
        elseif area then
            Print(now .. "The icon checks every enemy in the fight for it. If " .. name
                .. " only hits your target, type /se single " .. name .. ".")
        else
            Print(now .. "The icon checks the enemy you have targeted for it. If " .. name
                .. " hits every enemy in the fight, type /se aoe " .. name .. ".")
        end
    end)
end

function commands.ignore(rest)
    WithSpell(rest, function(name)
        Choice(name).track = false
        Tracker:Forget(name)
        Print(name .. " is now on Never, so it has no icon. Type /se track " .. name .. " to give it one again.")
    end)
end

function commands.auto(rest)
    WithSpell(rest, function(name)
        ns.db.spells[name] = nil
        ns.db.learned[name] = nil
        Print(name .. " is back on Auto, so the addon decides everything about it by itself again. Your own "
            .. "choices for it are cleared, and so is what the addon had learned about it.")
    end)
end

--- Which enemies a debuff is judged against. It is remembered for a buff
--- too, but only comes into play if the spell is made a debuff. `said` is
--- the sentence for a debuff, with %s for the skill's name.
local function SetArea(name, area, said)
    Choice(name).aoe = area
    local _, _, _, _, kind = Treatment(name)
    if kind == "buff" then
        Print("The effect of " .. name .. " is treated as a buff, so this changes nothing for now. It would only "
            .. "matter if you made it a debuff with /se debuff " .. name .. ".")
    else
        Print(format(said, name))
    end
end

function commands.aoe(rest)
    WithSpell(rest, function(name)
        SetArea(name, true, "The icon for %s now checks every enemy in the fight.")
    end)
end

function commands.single(rest)
    WithSpell(rest, function(name)
        SetArea(name, false, "The icon for %s now checks only the enemy you have targeted.")
    end)
end

function commands.duration(rest)
    local spell, value = Trim(rest):match("^(.-)%s+(%S+)$")
    if not spell then
        Print("Type the skill's name and then how long its effect lasts in seconds. For example: /se duration "
            .. "Thunder Clap 30, or /se duration Thunder Clap auto to let the addon work it out.")
        return
    end
    local seconds = tonumber(value)
    if value:lower() ~= "auto" and not (seconds and seconds >= 1 and seconds <= 3600) then
        Print("Type how long the effect lasts in seconds, from 1 to 3600, or type auto to let the addon work it out.")
        return
    end
    WithSpell(spell, function(name)
        if seconds then
            Choice(name).duration = seconds
            Print("The effect of " .. name .. " is now set to last " .. Count(seconds, "second", "seconds") .. ".")
        else
            local choice = ns.db.spells[name]
            if choice then
                choice.duration = nil
            end
            Print("The addon works out by itself again how long the effect of " .. name .. " lasts.")
        end
    end)
end

function commands.stacks(rest)
    local spell, value = Trim(rest):match("^(.-)%s+(%S+)$")
    if not spell then
        Print("Type the skill's name and then the most stacks its effect can have. For example: /se stacks Sunder "
            .. "Armor 5, or /se stacks Sunder Armor auto to let the addon work it out.")
        return
    end
    local most = tonumber(value)
    if value:lower() ~= "auto" and not (most and most >= 1 and most <= 100 and most == floor(most)) then
        Print("Type the most stacks the effect can have as a whole number from 1 to 100, where 1 means that it does "
            .. "not stack, or type auto to let the addon work it out.")
        return
    end
    WithSpell(spell, function(name)
        if most and most > 1 then
            Choice(name).stacks = most
            Print(format("The effect of %s can now have up to %d stacks. The icon shows the green check until all %d "
                .. "are there.", name, most, most))
        elseif most then
            Choice(name).stacks = most
            Print("The effect of " .. name .. " is now set as one that does not stack.")
        else
            local choice = ns.db.spells[name]
            if choice then
                choice.stacks = nil
                Spells:Tidy(name)
            end
            Print("The addon works out by itself again how many stacks the effect of " .. name .. " can have, from "
                .. "the game and from the skill's tooltip.")
        end
    end)
end

function commands.anyone(rest)
    WithSpell(rest, function(name)
        Choice(name).shared = true
        Print("The icon for " .. name .. " now treats another player's " .. name .. " like your own.")
    end)
end

function commands.mine(rest)
    WithSpell(rest, function(name)
        Choice(name).shared = false
        Tracker:ForgetTheirs(name)
        Print("The icon for " .. name .. " now only looks for your own " .. name .. ". Another player's is ignored.")
    end)
end

--- /se immune: what was learned of immune creatures, by skill.
local function ListImmune()
    local names = Spells:ImmuneSpells()
    local sure, once = {}, {}
    for i = 1, #names do
        local counted, heard = {}, {}
        local kinds = Spells:ImmuneKinds(names[i])
        for k = 1, #kinds do
            local kind = kinds[k]
            if kind.sure then
                counted[#counted + 1] = kind.name .. (kind.told and " (added by you)" or "")
            else
                heard[#heard + 1] = kind.name
            end
        end
        if #counted > 0 then
            sure[#sure + 1] = "  " .. names[i] .. ": " .. table.concat(counted, ", ")
        end
        if #heard > 0 then
            once[#once + 1] = "  " .. names[i] .. ": " .. table.concat(heard, ", ")
        end
    end
    if #sure == 0 and #once == 0 then
        Print("No enemy has been found immune to one of your skills yet. When the game says \"Immune\" as you use a "
            .. "skill on an enemy, the icon stops telling you to use that skill on that enemy. Once the addon is "
            .. "sure the enemy was not just shielded for a moment, it does the same for every enemy of that kind. "
            .. "It is sure at once when you fight alone and your other hits land on that enemy, and otherwise when "
            .. "the game says \"Immune\" of that kind a second time. To add a kind of enemy yourself, target one "
            .. "and type /se immune <skill>.")
        return
    end
    if #sure > 0 then
        Print("These enemies are immune to these skills. An icon never tells you to use a skill on an enemy that is "
            .. "immune to it:")
        for i = 1, #sure do
            print(sure[i])
        end
    else
        Print("No kind of enemy counts as immune to one of your skills yet.")
    end
    if #once > 0 then
        print("  Seen immune once so far. These count as immune when the game says so a second time:")
        for i = 1, #once do
            print("  " .. once[i])
        end
    end
    print("  Type /se immune forget to clear the list, or /se immune forget <skill> to clear it for one skill. An "
        .. "enemy that the addon added also comes off the list by itself when the skill is seen to work on one of "
        .. "its kind.")
end

--- How many kinds of enemy a cleared list held, as a sentence.
local function Held(dropped)
    return "It held " .. Count(dropped, "kind of enemy", "kinds of enemy") .. "."
end

function commands.immune(rest)
    rest = Trim(rest)
    if rest == "" then
        ListImmune()
        return
    end
    local word, more = rest:match("^(%S+)%s*(.*)$")
    if word:lower() == "forget" then
        if more == "" then
            local dropped = ns.ForgetImmune()
            ns.Options.RefreshAll()
            if dropped > 0 then
                Print("The list of immune enemies is cleared for every skill. " .. Held(dropped))
            else
                Print("The list of immune enemies was already empty.")
            end
            return
        end
        WithSpell(more, function(name)
            local dropped = ns.ForgetImmune(name)
            if dropped > 0 then
                Print("The list of enemies immune to " .. name .. " is cleared. " .. Held(dropped))
            else
                Print("No enemy was on the list as immune to " .. name .. ".")
            end
        end)
        return
    end
    WithSpell(rest, function(name)
        local who, why = ns.MarkImmune(name)
        if who then
            Print(format("You added %s to the enemies that are immune to %s. It stays on that list until you clear "
                .. "it with /se immune forget %s.", who, name, name))
        elseif why == "player" then
            Print("Your target is a player. Only creatures can be added as immune to a skill.")
        elseif why == "hidden" then
            Print("The game does not say what kind of enemy your target is right now, so nothing was added. Try "
                .. "again when the fight is over.")
        else
            Print("Target an enemy first. /se immune <skill> then adds every enemy of its kind as immune to that "
                .. "skill.")
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
        Print("The icon size follows the size of the button again.")
    elseif pixels and pixels >= ns.SIZE_MIN and pixels <= ns.SIZE_MAX then
        ns.Options.Change(function()
            ns.db.size = floor(pixels + 0.5)
        end)
        Print("The icon size is now " .. Count(ns.db.size, "pixel", "pixels") .. ".")
    else
        Print("Type a size from " .. ns.SIZE_MIN .. " to " .. ns.SIZE_MAX .. " pixels, as in /se size 24, or type "
            .. "/se size auto to let the icons follow the size of the button.")
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
        Print("Type where the icon goes on the button: tl, top, tr, left, center, right, bl, bottom or br. For "
            .. "example: /se corner tr puts it at the top right.")
        return
    end
    ns.Options.Change(function()
        ns.db.corner = corner
    end)
    Print("The icons have moved to the " .. ns.Options.POSITION_NAMES[corner]:lower() .. " of each button.")
end

commands.position = commands.corner

local TAB_WORDS = {
    display = "display", appearance = "display", look = "display", icons = "icons", icon = "icons",
    spells = "spells", spell = "spells", skills = "spells", skill = "spells",
}

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
    Print("These are the icons you can pick with /se icon <green | yellow | red> <name>:")
    local line = {}
    for i = 1, #Icons.CHOICES do
        line[#line + 1] = Icons.CHOICES[i].key
        if #line == 7 or i == #Icons.CHOICES then
            print("  " .. table.concat(line, ", "))
            line = {}
        end
    end
    print("  In place of a name you can type the file ID of a picture such as 136243, its path such as")
    print("  Interface\\Icons\\INV_Misc_QuestionMark, none for no icon at all, or default for the usual one.")
    print("  What the three results show now:")
    for i = 1, #Icons.STATES do
        local state = Icons.STATES[i]
        local current, custom = Icons.Current(state.key)
        if current == Icons.HIDDEN then
            current = "none"
        elseif current == "custom" then
            current = tostring(custom)
        end
        print(format("    %s: %s", state.title, current))
    end
end

-- The word the help names each of the three results by, for a line that says
-- what to type.
local RESULT_WORDS = { none = "green", some = "yellow", all = "red" }

function commands.icon(rest)
    local word, choice = Trim(rest):match("^(%S+)%s*(.-)$")
    local state = Icons.StateFor(word)
    if not state or choice == "" then
        Print("Type which result, green, yellow or red, and then the icon for it. For example: /se icon green "
            .. "plus, or /se icon green default for the usual one. /se icons lists the names.")
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
        Print("\"" .. title .. "\" now shows no icon. Type /se icon " .. (RESULT_WORDS[state] or state)
            .. " default to bring its icon back.")
    else
        local texture = Icons.ParseCustom(choice)
        if not texture then
            Print("\"" .. choice .. "\" is not an icon name, and not the file ID or the path of a picture the game "
                .. "knows. /se icons lists the names.")
            return
        end
        ns.Options.Change(function()
            Icons.SetCustom(state, texture)
        end)
        Print("\"" .. title .. "\" now shows your own picture, " .. tostring(texture) .. ".")
    end
end

function commands.log()
    ns.db.log = not ns.db.log
    Print(ns.db.log and "The log is on: the addon now says in chat what it notices. Type /se log again to turn "
        .. "it off." or "The log is off.")
end

function commands.plain()
    ns.db.plain = not ns.db.plain
    Print(ns.db.plain
        and "The settings window will draw its own buttons and sliders. Type /reload to see it. Type /se plain "
            .. "again to go back to the game's own."
        or "The settings window will use the game's own buttons and sliders again, wherever they work. Type "
            .. "/reload to see it.")
end

function commands.reset()
    ns.ResetSettings()
    ns.Options.PlaceWindow()
    ns.Options.RefreshAll()
    Print("Every setting is back to how it started, and everything the addon had learned is cleared.")
end

-- Why a skill has an icon. These are the sentences the Skills tab of the
-- settings gives for the same reasons (WHY in Options.lua), so that the list
-- in chat and the panel say one thing. A scenario holds the two together.
local REASONS = {
    debuff = {
        you = "You chose Always, so it has an icon.",
        seen = "It has an icon because the addon has seen its debuff on an enemy.",
        ["built-in"] = "It has an icon because it is a well-known debuff that hits every enemy around you.",
        tooltip = "It has an icon because its tooltip describes a debuff that lasts for a while.",
    },
    buff = {
        you = "You chose Always, so it has an icon.",
        seen = "It has an icon because the addon has seen its buff on you.",
        tooltip = "It has an icon because its tooltip describes a buff that lasts for a while.",
    },
}
local EARNED = "It has an icon because %d of your %d casts left an effect behind."

--- What a skill with an icon does, to follow its name: where its effect is
--- looked for, with %s for how long the effect lasts.
local function Where(info, area, kind)
    if kind == "buff" then
        if OnFriends(info) then
            return "gives you, or the friend you have targeted, a buff that lasts %s"
        end
        return "gives you a buff that lasts %s"
    end
    return area and "puts a debuff that lasts %s on every enemy in the fight"
        or "puts a debuff that lasts %s on your target"
end

-- How many stacks a skill's effect can have and who said so, for /se list,
-- with %d for the number and %s for the skill's name. What was seen in the
-- game is the weakest of them: the effect may go higher than it has been seen
-- to, and /se stacks says how high.
local STACKS = " Its effect can have up to %d stacks."
local STACKS_FROM = {
    you = STACKS .. " You set this yourself.",
    tooltip = STACKS .. " The addon read this from the skill's tooltip.",
    game = STACKS .. " The game gives this number for the skill.",
    seen = " The addon has seen its effect reach %d stacks so far, and takes that as the most it can have. If it "
        .. "can go higher, type /se stacks %s <number>.",
}

function commands.list()
    local list = ns.BarSpells()
    if #list == 0 then
        Print("No skills were found on your action bars yet.")
        return
    end
    Print("The skills on your action bars:")
    local quiet = 0
    for i = 1, #list do
        local info = list[i]
        local name = info.name
        local tracked, area, duration, source, kind = Spells:Tracking(info)
        local casts, hits = Spells:Record(name, kind)
        casts, hits = floor(casts + 0.5), floor(hits + 0.5)
        if tracked then
            local why = REASONS[kind][source] or format(EARNED, hits, casts)
            local line = format("  |cff40d040%s|r %s. %s", name, format(Where(info, area, kind), Lasting(duration)),
                why)
            local most = Spells:Stacking(info)
            if most then
                line = line .. format(STACKS_FROM[Spells:StackingSource(info)] or STACKS, most, name)
            end
            -- Nobody else can put on you what a skill only ever puts on its caster.
            if Spells:Shared(info) and not (kind == "buff" and info.selfOnly == true) then
                line = line .. " The icon treats another player's " .. name .. " like your own."
            end
            print(line)
        elseif source == "ignored" then
            print(format("  |cff999999%s|r is on Never, so it has no icon.", name))
        elseif source == "demoted" then
            print(format("  |cff999999%s|r lost its icon because %d of your %d casts left no effect behind.", name,
                casts - hits, casts))
        else
            quiet = quiet + 1
        end
    end
    local ADD = " an icon anyway, type /se track <skill>, or /se buff <skill> if its effect is a buff on you. The "
        .. "Skills tab of /se options does the same with clicks."
    if quiet == 1 then
        print("  1 other skill has no icon because it does not seem to leave a buff or a debuff behind. To give it"
            .. ADD)
    elseif quiet > 1 then
        print(format("  %d other skills have no icon because they do not seem to leave a buff or a debuff behind. To "
            .. "give one of them", quiet) .. ADD)
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

local REPORT_LABELS = { player = "you", target = "your target", softenemy = "your soft target", plate = "nameplates" }

-- Who answers whether a skill can be used, as ns.usableProbe names them.
local USABLE_SOURCES = {
    bar = "told by the action bar",
    spell = "not told by the action bar, so asked about the spell",
    look = "read off the button's own colours",
    no = "nothing tells",
    ["not asked yet"] = "not asked yet",
}

-- What ns.GroupState says of your party or raid, in words.
local GROUP_WORDS = {
    alone = "you are in no party or raid",
    quiet = "nobody in it is in combat",
    far = "someone in it is in combat, but nobody close by",
    fighting = "someone close by is in combat",
    unsaid = "the game will not say who in it is in combat, or who is close by",
}

-- What a fight of theirs close by does for the icons, which goes by the
-- setting for when they appear.
local GROUP_FIGHT = {
    group = ", which keeps the icons on like a fight of your own",
    combat = ", which does not bring the icons up: they are set to appear when you are in combat yourself",
}

function commands.debug()
    local now = ns.Now()
    local ok, version, build, _, interface = pcall(GetBuildInfo)
    if not ok then
        version, build, interface = "?", "?", "?"
    end
    Print(format("Version %s on client %s (build %s), interface %s.", ns.VERSION,
        tostring(ns.Plain(version)), tostring(ns.Plain(build)), tostring(ns.Plain(interface))))
    print(format("  Secret values: %s. Aura details hidden right now: %s. In combat: %s.",
        YesNo(ns.hasSecretValues), YesNo(ns.AurasSecret()), YesNo(ns.InCombat())))
    local group = ns.GroupState()
    print("  Your group: " .. (GROUP_WORDS[group] or "nothing known")
        .. (group == "fighting" and GROUP_FIGHT[ns.db.appear] or "") .. ".")

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

    local blind, why, setting = ns.SightProbe()
    print(format("  Enemy nameplates: the game's setting reads %s. When they are off: %s (%s). Enemies seen by them: %s.",
        (setting == true and "on") or (setting == false and "off") or "nothing", tostring(ns.db.nameplates),
        ns.KeepsNameplates(),
        (blind == true and ("no (" .. tostring(why) .. ")")) or (blind == false and "yes") or "not known yet"))

    local unit = ns.PrimaryEnemy()
    if unit then
        print(format("  Enemy target right now: your debuffs %s, identity readable: %s.",
            ReadableNow(unit, "debuff"), YesNo(ns.IdentityReadable(unit))))
    else
        print("  No enemy targeted.")
    end
    print(format("  You right now: your buffs %s.", ReadableNow("player", "buff")))
    local asked = ns.usableProbe
    print(format("  Whether a skill can be used: %s. Whether its target is in reach: %s.",
        USABLE_SOURCES[asked.usable] or tostring(asked.usable), USABLE_SOURCES[asked.range] or tostring(asked.range)))

    local probe = ns.probe
    print(ProbeLine("  Enemy debuffs, out of combat", probe.open, now, false, true))
    print(ProbeLine("  Enemy debuffs, details hidden", probe.hidden, now, true, true))
    print(ProbeLine("  Your buffs, out of combat", probe.buffs.open, now, false, false))
    print(ProbeLine("  Your buffs, details hidden", probe.buffs.hidden, now, true, false))

    -- What the client reports while details are hidden, and how casts came out.
    local journal = ns.Journal()
    local heard = {}
    for i = 1, #ns.TOKEN_KINDS do
        local kind = ns.TOKEN_KINDS[i]
        heard[i] = format("%s: %d%s", REPORT_LABELS[kind], journal.reports[kind].hidden,
            ns.Trusted(kind) and "" or " (silent after several casts, so a cast there is taken to land)")
    end
    print("  Changes the game reported while details were hidden, about " .. table.concat(heard, ", ") .. ".")
    print(format("  Of those, put down to an effect of yours running out just then: %d.", journal.reports.ended or 0))
    local kinds = journal.reports.kinds
    if kinds then
        -- A change that only took effects away is never a cast landing. Where
        -- the game does not say what kind a change was, timing has to do.
        print(format("  What the game said each one was: an effect arriving %d, one going %d, both %d, not said %d.",
            kinds.came, kinds.went, kinds.both, kinds.unsaid))
        print(format("  An effect going while a cast was waiting to be judged, and not taken for it landing: %d.",
            journal.reports.spared or 0))
        -- A stack is counted by this: the first cast adds the effect, each one after renews it.
        print(format("  Of the ones arriving, only added: %d, only renewed: %d.", kinds.added or 0, kinds.renewed or 0))
    end
    local others = journal.others
    if type(others) == "table" then
        -- Another player's copy of an effect can only be followed in a fight
        -- if the game says which spell they cast.
        print(format("  Casts heard from your group: %d. With details hidden, the spell could be read for %d and "
            .. "was kept secret for %d. Of a spell of yours: %d, seen to land: %d.", others.casts or 0,
            others.named or 0, others.unnamed or 0, others.followed or 0, others.landed or 0))
        -- How long theirs lasts is what their casts are given from then on.
        print(format("  Another player's copy read for how long it lasts: %d, and with who put it there: %d.",
            others.read or 0, others.sourced or 0))
    else
        print("  Casts heard from your group: none yet.")
    end
    -- An enemy is only taken to be immune on the game's own word for what a
    -- cast did to it, so whether that word is heard at all matters.
    local said = journal.combat
    if next(ns.saying) == nil then
        print("  This client does not let an addon hear what attacks did to enemies, so which enemies are immune "
            .. "is not learned. /se immune <skill> adds the kind you have targeted by hand.")
    elseif type(said) == "table" then
        local heard, unread = 0, 0
        for _, kind in pairs({ "target", "softenemy", "plate" }) do
            local count = said[kind]
            if type(count) == "table" then
                heard = heard + (count.heard or 0)
                unread = unread + (count.unread or 0)
            end
        end
        print(format("  What the game said attacks did to enemies: heard %d times, kept secret %d times. Of those "
            .. "\"immune\": %d.", heard, unread, type(said.words) == "table" and said.words.IMMUNE or 0))
    else
        print("  What the game said attacks did to enemies: nothing heard yet.")
    end
    local immune = Tracker:Immunities(now)
    for i = 1, #immune do
        if i > 6 then
            print(format("    and %d more", #immune - 6))
            break
        end
        print(format("    %s: %s is taken to be immune, %s", immune[i].name, ns.EnemyName(immune[i].key),
            (immune[i].shield and "behind a shield: until a hit lands on it, or " .. Span(immune[i].left)
                .. " more unless the game says so again")
            or (immune[i].left and (Span(immune[i].left) .. " more unless the game says so again"))
            or "for as long as it is about"))
    end
    -- How far off an enemy stands is put together from what the game says of
    -- the ranges of the skills on the bars (see "Enemies out of reach" in
    -- Core.lua).
    local ranges, reach = ns.ReachProbe()
    if #ranges == 0 then
        print("  Enemies out of reach: no skill on your bars has a range to ask the game about, so every enemy "
            .. "counts as within reach.")
    else
        local told = {}
        for i = 1, #ranges do
            told[i] = format("%s to %s yards%s", ranges[i].least, ranges[i].most,
                ranges[i].proven and "" or " (believed of your target only so far)")
        end
        local mine, others, soft = reach.target, reach.plate, reach.softenemy
        print(format("  Enemies out of reach: told by skills that reach %s. Asked about your target, the game "
            .. "answered %d times and said nothing %d times; about other enemies, %d and %d times.",
            table.concat(told, ", "), mine.yes + mine.no, mine.silent,
            others.yes + others.no + soft.yes + soft.no, others.silent + soft.silent))
        local left = {}
        for name, times in pairs(reach.left) do
            left[#left + 1] = format("%s (%d)", name, times)
        end
        if #left > 0 then
            table.sort(left)
            print("    Began leaving an enemy out, by skill and how often: " .. table.concat(left, ", ") .. ".")
        end
        if #reach.notes > 0 then
            print("    " .. reach.notes[#reach.notes])
        end
    end
    local verdicts = journal.verdicts
    local landed = (verdicts.changed or 0) + (verdicts.seen or 0)
    local empty = (verdicts.silent or 0) + (verdicts["nothing new"] or 0) + (verdicts.immune or 0)
    local open = (verdicts.unproven or 0) + (verdicts.assumed or 0) + (verdicts.unclear or 0) + (verdicts.unknown or 0)
    print(format("  Casts made with details hidden this session: %d left something, %d left nothing, %d could not be judged.",
        landed, empty, open))
    local refused = {}
    for name in pairs(ns.refusals) do
        refused[#refused + 1] = name
    end
    if #refused > 0 then
        table.sort(refused)
        print("  Refused by the game so far: " .. table.concat(refused, ", ") .. ".")
    end
    print("  A fuller report is saved with the addon's settings at the next /reload or logout.")

    local effects = Tracker:Describe(now)
    local me = ns.KeyOf("player", "buff")
    print(format("  Effects being tracked: %d.", #effects))
    for i = 1, #effects do
        if i > 8 then
            print(format("    and %d more", #effects - 8))
            break
        end
        local key, left, stacks = effects[i].key, effects[i].left, effects[i].stacks
        local where = key == me and " on you" or (key:sub(-6) == "+buffs" and " on a friend" or "")
        print(format("    %s%s%s, %s (%s)", effects[i].name, stacks and format(" x%d", stacks) or "", where,
            left and (Span(left) .. " left") or "no end time", effects[i].how))
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
        Print("That command ran into a problem: " .. tostring(err))
    end
end

ns.RunCommand = Run
