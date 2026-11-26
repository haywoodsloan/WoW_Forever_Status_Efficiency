# Status Efficiency

A World of Warcraft addon for **WoW Forever**. It puts a small icon on each action
button that tells you whether casting that spell again would do anything for its
status effect.

| Icon | Meaning |
| --- | --- |
| Green check | None of the enemies the spell would hit has its effect. Casting puts it on all of them. |
| Yellow half circle | Some of them have it and some do not. |
| Red X | All of them already have it. Casting again changes nothing. |
| No icon | There is no enemy to judge, or the spell applies no status effect. |

Version 0.1.0 is a first draft. It has been run against a simulated game client
(see [Development](#development)) but not yet inside the real one, so expect a
few rough edges and please report what `/se debug` prints.

## Install

1. Copy the `StatusEfficiency` folder into the game's AddOns folder:

   ```
   World of Warcraft\_forever_\Interface\AddOns\
   ```

   On a default Windows install that is
   `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\`.
   When it is in the right place this file exists:
   `...\Interface\AddOns\StatusEfficiency\StatusEfficiency.toc`.
2. Fully close the game and start it again. A `/reload` does not pick up a newly
   added addon.
3. On the character screen, open **AddOns** and make sure **Status Efficiency** is
   ticked. If it is listed as out of date, tick "Load out of date AddOns" and
   type `/dump select(4, GetBuildInfo())` in game: the number it prints belongs
   on the `## Interface:` line of `StatusEfficiency.toc` (it ships as `16001`,
   for client 1.60.1).

When it loads you get one line in chat: "Status Efficiency: v0.1.0 loaded."

## Using it

Target an enemy. Every spell on your bars that leaves a status effect gets a
green check. Cast one and its button turns to a red X until the effect ends.
Spells that hit every enemy around you go yellow when only some of the enemies
in the fight have the effect.

### Settings

Open **Options > AddOns > Status Efficiency**, or type `/se options` for the same
panel in a window of its own. Changes apply straight away and are saved per
account.

- **Icon position.** Click one of nine spots on the pretend button: the four
  corners, the four edges, or the middle.
- **Icon for each indication.** Each of the three indications (no enemy has it,
  some enemies have it, every enemy has it) can use any of 21 icons: the three
  defaults, coloured dots, a plus, an exclamation mark, a stop sign, a ring, the
  ready check marks and the eight raid markers.
- **Your own texture.** Type a file ID such as `136243`, or a path such as
  `Interface\Icons\Spell_Nature_Slow`, into the box beside an indication and
  press Enter. Empty the box and press Enter to go back.
- **Reset position and icons** puts those two things back to the defaults and
  leaves your spell choices alone.

### Commands

`/se` and `/statusefficiency` are the same command. A spell can be typed in any
case, shortened to the start of its name, or shift-clicked from the spellbook.

| Command | What it does |
| --- | --- |
| `/se` | Lists the commands. |
| `/se options` | Opens or closes the settings window. |
| `/se on`, `/se off` | Turns the icons on or off. |
| `/se list` | Shows the spells on your bars and how each one is treated, and why. |
| `/se track <spell>` | Always give this spell an icon. |
| `/se ignore <spell>` | Never give this spell an icon. |
| `/se auto <spell>` | Let the addon decide again, and forget what it learned about the spell. |
| `/se aoe <spell>` | Judge the spell against every enemy in the fight. |
| `/se single <spell>` | Judge the spell against your target only. |
| `/se duration <spell> <seconds>` | Say how long the effect lasts. `auto` goes back to the addon's own figure. |
| `/se corner <where>` | Moves the icon: `tl`, `top`, `tr`, `left`, `center`, `right`, `bl`, `bottom`, `br`. |
| `/se size <pixels>` | Icon size from 8 to 128. `auto` sizes it from the button. |
| `/se icons` | Lists the icon names and what each indication uses now. |
| `/se icon <green\|yellow\|red> <icon>` | Sets the icon for one indication: an icon name, a file ID, a texture path, or `default`. |
| `/se debug` | Shows what the game lets the addon see right now. Paste this into a bug report. |
| `/se log` | Shows or hides a running commentary of what the tracker is doing. |
| `/se reset` | Forgets every setting and everything learned. |

## How it decides

### Which spells get an icon

WoW Forever has its own class design, so the addon carries no table of debuff
spells. A spell on your bars is treated as a status effect when, strongest first:

1. you said so with `/se track` (or said the opposite with `/se ignore`);
2. the addon has read a debuff of yours with the spell's own name off an enemy;
3. the spell can be cast on enemies and its tooltip mentions a duration, or it
   is one of a few well known area debuffs (Thunder Clap, Frost Nova and the
   like), and casting it has not kept leaving nothing behind;
4. casting it has repeatedly been followed by a new debuff of yours.

Passive spells and spells that can only be cast on friends never get an icon.
`/se list` shows the verdict for every spell on your bars.

### Which enemies count

- A spell aimed at one enemy is judged against your target (or the enemy the
  game's soft targeting has picked).
- A spell that hits everything around you is judged against the enemies that
  are in the fight and have a nameplate showing, plus your target.
- No such enemy: the icon is hidden.

### How it knows what an enemy has

The game hides enemies' debuffs from addons during combat, and addons get no
combat log. So the addon uses whatever the client still allows, best first:

1. **Reading the debuffs outright.** Out of combat this works and is exact. The
   addon also learns from it which spells leave which debuffs and for how long.
2. **Asking for one debuff by name**, for debuffs the client leaves visible in
   combat.
3. **Counting your debuffs on the enemy** without looking at what they are. A
   cast that adds one landed, a cast that adds none missed, and a debuff that
   disappears early is noticed. This is only believed after the same fight has
   shown at least one debuff this way, so an empty answer from a client that is
   simply hiding everything is never mistaken for "nothing there".
4. **Your own casts and a timer.** When none of the above works, a cast is
   assumed to land on the enemy it was aimed at and to last as long as its
   tooltip says.

`/se debug` shows which of these the client allowed the last time the addon
looked, out of combat and in it.

## Known limitations

- **In combat the icons are most likely running on timers.** If the client
  refuses even the counting, the addon cannot see a miss, a dodge, an immune
  enemy or a debuff that is removed early. It shows a red X for the length of
  the effect after every cast that goes off.
- **Only your own debuffs count.** The same effect put there by another player
  is not seen.
- **Spell detection is a guess from the tooltip.** A spell that can be cast on
  enemies and mentions any duration gets an icon, which includes some that leave
  no debuff (an interrupt that locks a spell school "for 3 sec", for example).
  Use `/se ignore <spell>`. Area spells that have no target cannot be recognised
  this way unless they are on the small built-in list, so add them with
  `/se track <spell>`.
- **Durations come from the tooltip.** When a tooltip gives no duration the
  addon assumes 12 seconds until it has seen the real debuff. Fix one with
  `/se duration <spell> <seconds>`.
- **A debuff named differently from its spell** cannot be looked up by name, so
  that spell falls back to counting or timers.
- **Area spells have no range check.** Every enemy in the fight with a nameplate
  showing is assumed to be in reach. Enemy nameplates need to be turned on for
  area spells to see more than your target.
- **Casts aimed somewhere else** (a mouseover or focus macro) are booked against
  your current target.
- **When the client hides who an enemy is**, enemies are told apart by their
  nameplates. With nameplates off, switching away from an enemy and back forgets
  what was on it.
- **Action bars.** The default bars are supported. Bartender4, Dominos and ElvUI
  buttons are picked up by name but have not been tried.
- **The game's own icons** (ready check marks, raid markers) are named by their
  usual texture paths. If one shows up blank in this client, pick another.

## Development

```
StatusEfficiency/     the addon; this folder is what gets installed
  StatusEfficiency.toc
  Compat.lua          every call into the game, guarded against secret values
  Icons.lua           the three indications and the icons on offer
  Spells.lua          which spells leave a status effect, and for how long
  Tracker.lua         which of your effects are on which enemy
  Core.lua            action buttons, enemies, casts, the update loop
  Options.lua         the settings panel
  Commands.lua        the /se command
  Media/              the shipped icons, 64x64 TGA
tests/                a pretend game client and the scenarios run against it
tools/make_icons.py   draws the icons in Media/
```

The addon is plain Lua 5.1, the dialect the game embeds, so the tests load it
unchanged into a Lua 5.1 runtime where `tests/wow_mock.lua` stands in for the
game. The mock imitates secret values (they throw when compared, indexed or
used in arithmetic) and the different ways a client might restrict aura queries
in combat.

```
pip install lupa
python3 tests/run_tests.py            # everything
python3 tests/run_tests.py settings   # only scenarios with "settings" in the name
```

To redraw the icons (needs Pillow):

```
python3 tools/make_icons.py
```
