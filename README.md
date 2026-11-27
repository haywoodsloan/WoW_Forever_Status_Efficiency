# Status Efficiency

A World of Warcraft addon for **WoW Forever**. It puts a small icon on each action
button that tells you whether casting that spell again would do anything for its
status effect: the debuff it leaves on enemies, or the buff it leaves on you.

| Icon | A spell that leaves a debuff on enemies | A spell that leaves a buff on you |
| --- | --- | --- |
| Green check | None of the enemies it would hit has the debuff. Casting puts it on all of them. | You do not have the buff. |
| Yellow half circle | Some of them have it and some do not. | Not used. |
| Red X | All of them already have it. Casting again changes nothing. | You already have it. Casting again changes nothing. |

No icon means there is nothing to say: the spell applies no status effect, or
it is a debuff and there is no enemy to judge and no fight going on. Out of the
box the icons also stay away until a fight starts, yours or one that someone in
your group is in close by, and from a skill you cannot use right now (too
close, too far, the wrong stance). Both can be changed in the settings.

Version 0.3.9 is an early draft. It loads and draws its icons in the real
client, but most of its testing has been against a simulated one (see
[Development](#development)), and what the client reports in combat is still
being confirmed: the addon keeps a short record of it (see
[Checking it against your client](#checking-it-against-your-client)). Expect a
few rough edges.

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

It loads without a word in chat. To see that it is there, type `/se`: the
first line of the reply gives the version, "Status Efficiency: v0.3.9".

To update, replace the files in the `StatusEfficiency` folder and type `/reload`.
A full restart is only needed when a new version adds files.

## Using it

Attack an enemy. Every spell on your bars that leaves a debuff gets a green
check. Cast one and, once it lands, its button turns to a red X until the effect
ends. A cast that misses, or is dodged, parried or resisted, leaves the green
check where it is. Spells that hit every enemy around you go yellow when only
some of the enemies in the fight have the effect.

Spells that put a buff on you work the same way: a green check while you do
not have the buff, a red X while you do. A buff you can also put on other
people (a heal over time, a stamina buff) is judged on the friend you have
targeted, and on you when your target is an enemy or nobody.

The icons appear when a fight starts, buff icons included, and stay on until it
ends, whatever you have targeted: your target dying does not take them away. A
fight is your own, or one that someone in your party or raid is in close by.
While it lasts, a debuff with no enemy to judge it on shows the green check
until you pick the next target. Out of a fight your buttons stay bare. If you
would rather see the icons all the time (buffs at any time, debuffs whenever
there is an enemy to check), or only during fights of your own, change **when
the icons appear** in the settings or with `/se when`.

A skill you cannot use right now shows no icon either, whatever the icon would
have said: the target is too close or too far, you are in the wrong stance, the
skill cannot be used during a fight, and so on. It is the test the game uses to
grey a button out or turn its key red.

Two things do not hide an icon. Being short of rage, mana or energy is one:
rage comes and goes all through a fight, and an icon that left each time a
skill had just been paid for would be gone at the very moment it has something
new to say. A cooldown is the other: the short pause after every cast would
make all the icons blink, and the game can keep cooldowns from addons during a
fight. To see the icon on every skill regardless, pick **On every skill** in
the settings or type `/se usable off`.

Reach is judged to whoever the skill would go to. A buff that goes on you is
never held back by how far away your target is.

The addon gets all this from the game, and has three ways of asking. It asks
about the action on the button. If the game will not answer that (a fight is
when it holds things back), it asks the same about the spell. Failing that it
reads the button itself, which the game has already painted for you: white for
a skill you can use, blue for one you are short of rage for, grey for one you
cannot use, and the key's name in red when the target is out of reach. Nothing
needs to be switched on for this. If none of the three says anything, the icons
show on every skill, and `/se usable` says so.

A buff spell the game does not label as one gets its icon the first time the
addon sees its buff on you out of combat. `/se buff <spell>` does the same by
hand.

### Settings

Open **Options > AddOns > Status Efficiency**, or type `/se options` for the same
panel in a window of its own. The window can be dragged by its title bar and
opens where you left it. Changes apply straight away and are saved per account.

The **Appearance** tab:

- **Show status icons** turns the icons on and off, like `/se on` and `/se off`.
- **When the icons appear**, beside it:
  - **Always**: whenever there is something to judge, which is a buff at any
    time and a debuff whenever there is an enemy to check, and all through a
    fight.
  - **When you are in combat**: only while you are in combat yourself. A fight
    that only others in your group are in does not count.
  - **When you or your group are in combat** (the default): while you are in
    combat, and while someone in your party or raid is in combat close by.
    [Known limitations](#known-limitations) says what close by means.

  Versions up to 0.3.8 had **When targeting an enemy** where the last choice is
  now. A setting saved as that becomes **When you or your group are in combat**:
  an enemy you target before a fight no longer brings the icons up.
- **On which skills**, under it: **On every skill**, or **Only when the skill
  is usable** (the default), which leaves a skill bare while you cannot use it:
  too close or too far, in the wrong stance and the like. Being short of rage,
  mana or energy does not count, and neither does a cooldown.
- **Preview.** Three pretend buttons, one for each result, drawn as large as
  your action buttons with the icon where and as big as it is on the bars.
  Click one of the nine spots on any of them to move the icon: the four
  corners, the four edges, or the middle. While this tab is open and you are
  out of combat, your real action buttons show sample icons as well.
- **Icon size.** A slider from 8 to 48. **Auto** sizes the icon from the button
  it sits on, at about a third of the button's width, which is 16 on a standard
  button.
- **Icon set.** Four ready-made sets that change all three icons in one click.
- **The icon for each result.** Each of the three results (worth casting,
  partly worth casting, no need to cast) can use any of 21 icons: the addon's
  own ten on the first line, the game's ready check marks and raid markers on
  the second. The tile with a stroke through it means no icon at all for that
  result. The panel says so when two results end up with the same icon. Buffs
  and debuffs share the icons.
- **Your own texture.** The tile marked `...` opens a box. Type a file ID such
  as `136243`, or a path such as `Interface\Icons\Spell_Nature_Slow`, and press
  Enter. Empty the box and press Enter to go back.
- **Reset appearance** asks first, then puts the position, size and icons back
  to the defaults. It leaves your spell choices alone.

The **Spells** tab has one row for every spell on your action bars:

- **Show an icon**: Auto (the addon decides), Always, or Never.
- **Judged on**: your target, all enemies in the fight, or you (a buff).
- **Lasts**: how long the effect lasts. Type a number of seconds to change it,
  or empty the box to let the addon work it out again.
- **Why**: what the addon's choice rests on. Hover it for the full sentence.

The panel uses the game's own buttons, tick boxes and slider where they work.
It looks after the rest by itself:

- Each of the game's controls is tried out as the panel is built. One that is
  missing in this client, has no art to show, or does not do what it is told
  is replaced by a plainer control the addon draws itself.
- If the panel cannot be built with the game's controls in it at all, it is
  built again with the addon's own.
- A font this client does not have is replaced by the nearest one it does have.
- A label that would not fit in this client's font is drawn smaller, and cut
  short only if that is not enough.
- If the Options window gives the page less room than the panel needs, the
  whole page is drawn smaller.

To have the plainer controls anyway, type `/se plain` and then `/reload`.

### Commands

`/se` and `/statusefficiency` are the same command. A spell can be typed in any
case, shortened to the start of its name, or shift-clicked from the spellbook.

| Command | What it does |
| --- | --- |
| `/se` | Lists the commands. The first line gives the version of the addon. |
| `/se options` | Opens or closes the settings window. `/se options spells` opens it on the Spells tab. |
| `/se on`, `/se off` | Turns the icons on or off. |
| `/se when <always\|combat\|group>` | When the icons appear: always, only while you are in combat, or while you or someone in your group close by is in combat (the default). `party` and `raid` work for `group`. |
| `/se usable <on\|off>` | `on` (the default) shows an icon only on a skill you can use right now. `off` shows it on every skill. |
| `/se list` | Shows the spells on your bars and how each one is treated, and why. |
| `/se track <spell>` | Always give this spell an icon. The reply says whether it is treated as a debuff or a buff. |
| `/se buff <spell>` | Always give this spell an icon, as a buff on you. |
| `/se debuff <spell>` | Always give this spell an icon, as a debuff on enemies. |
| `/se ignore <spell>` | Never give this spell an icon. |
| `/se auto <spell>` | Let the addon decide again, and forget what it learned about the spell. |
| `/se aoe <spell>` | Judge a debuff against every enemy in the fight. |
| `/se single <spell>` | Judge a debuff against your target only. |
| `/se duration <spell> <seconds>` | Say how long the effect lasts. `auto` goes back to the addon's own figure. |
| `/se corner <where>` | Moves the icon: `tl`, `top`, `tr`, `left`, `center`, `right`, `bl`, `bottom`, `br`. |
| `/se size <pixels>` | Icon size from 8 to 48. `auto` sizes it from the button again. |
| `/se icons` | Lists the icon names and what each result uses now. |
| `/se icon <green\|yellow\|red> <icon>` | Sets the icon for one result: an icon name, a file ID, a texture path, `none` for no icon, or `default`. |
| `/se debug` | Shows what the game lets the addon see right now. Paste this into a bug report. |
| `/se log` | Shows or hides a running commentary of what the tracker is doing. |
| `/se plain` | Has the settings panel draw its own plainer controls instead of the game's, or the game's again. Takes effect after `/reload`. The panel changes over by itself wherever the game's controls are missing or do not work. |
| `/se reset` | Forgets every setting and everything learned. |

## How it decides

### Which spells get an icon

WoW Forever has its own class design, so the addon carries no table of spells.
A spell on your bars is treated as a status effect when, strongest first:

1. you said so with `/se track`, `/se buff` or `/se debuff` (or said the
   opposite with `/se ignore`);
2. the addon has read an effect of yours with the spell's own name: a debuff
   off an enemy, or a buff off you;
3. its tooltip says how long an effect lasts and the game says where it can
   land: on enemies (a debuff), or on friends or only on yourself (a buff). A
   time that is something else does not count: how soon the skill has to be
   used ("can only be used within 20 sec after you kill an enemy"), how often
   an effect ticks, a cooldown, how long an interrupted spell stays locked. A
   few well known area debuffs (Thunder Clap, Frost Nova and the like) count
   too. Casting it must not have kept leaving nothing behind;
4. casting it has repeatedly been followed by a new effect of yours: six
   casts or more, and at least four in five of them. In combat, where the
   addon cannot see whose effect it was, a change the enemy reports right
   after the cast counts, as long as the enemy is still there afterwards. One
   that died or went out of sight in that moment says nothing about the
   skill: a dying enemy's effects all go, and that is a change too. So a
   finishing move does not earn an icon one kill at a time. Every spell on
   your bars is watched for this, icon or not, unless you set it to **Never**.

   Versions before 0.3.6 did count those kills. What they saved is taken down
   once, when 0.3.6 first loads it: a skill that nothing else speaks for (no
   tooltip, no effect read by name) has to be seen leaving something a few
   more times before it gets an icon.

Whether a spell is a debuff or a buff follows from the same facts. Seeing wins:
a spell whose buff has been read off you is a buff, even an attack that leaves
its effect on you rather than on its target. Otherwise a spell you can cast on
enemies is a debuff, and one you cast on friends or only on yourself is a buff.
`/se buff` and `/se debuff` overrule all of it.

Passive spells never get an icon. `/se list` shows the verdict for every spell
on your bars.

### Who is looked at

- A debuff aimed at one enemy is judged against your target (or the enemy the
  game's soft targeting has picked).
- A debuff that hits everything around you is judged against the enemies that
  are in the fight and have a nameplate showing, plus your target.
- No such enemy: the icon is hidden. During a fight it shows the green check
  instead: nobody the skill could go to has its effect.
- A buff is judged on you. One that can be cast on other people is judged on
  your target instead while that target is a living friend.

### How it knows what is there

The game hides auras from addons during combat, your own buffs as much as an
enemy's debuffs, and addons get no combat log. So the addon uses whatever the
client still allows, best first:

1. **Reading the effects outright.** Out of combat this works and is exact. The
   addon also learns from it which spells leave which effects and for how long.
2. **Asking for one effect by name**, for effects the client leaves visible in
   combat.
3. **Counting your effects on the unit** without looking at what they are. A
   cast that adds one landed, a cast that adds none missed, and an effect that
   disappears early is noticed. This is only believed after the same fight has
   shown at least one effect this way, so an empty answer from a client that is
   simply hiding everything is never mistaken for "nothing there".
4. **Watching for the unit's effects to change.** In combat the game still
   tells an addon the moment a unit gains, renews or loses an effect, without
   saying which effect or whose. So a cast counts for nothing until the unit it
   was aimed at reports such a change right after it, and that goes for the
   first cast as much as for any other. A cast that misses changes nothing on
   the enemy, nothing is reported, and the button stays green. The addon waits
   up to three seconds for the report: the full three for a spell cast from a
   distance, a second and a half for a skill used at arm's length, and less
   once it has timed a few of that skill's landings.

   Only a change that could be the cast's effect arriving counts. The client
   this was checked against (build 71139) hides what is in a report but not
   what kind of change it was: an effect added, one renewed, or one taken
   away. A report that only took effects away is never a cast landing,
   whatever went: the enemy died, an effect of its own or of another player's
   ran out, or one of yours did. On a client that does not show the kind, one
   change is still known for what it is: the one that comes just when an
   effect of your own on that unit was due to run out. That is put down to
   the effect ending, by its timing, and is not counted for a cast.
5. **Your own casts and a timer.** As a last resort a cast is assumed to land on
   the unit it was aimed at and to last as long as its tooltip says. That is
   only done for a unit the game reports nothing about, and on a client that
   has been found not to send those reports in combat (see below).

Debuffs on enemies and buffs on you are handled separately, so a client that
allows one and not the other is still used as far as it goes. `/se debug` shows
which of these the client allowed the last time the addon looked, for each of
the two, out of combat and in it.

### Checking it against your client

What a client allows in combat differs from one version to the next. The addon
listens for reports about you, your target, your soft target and the
nameplates, and judges a cast by them from the first one on. It does not wait
to hear a report before it counts on them, because until then every miss would
show a red X.

A client that does not send them is found out by its silence. After three
casts in a row with nothing at all reported through one of those four (six
where an earlier session on the same client version did hear reports there),
the addon stops waiting for them there, and a cast is assumed to land, as in
step 5. It says so in chat, once, remembers it for that client version, and
goes back to judging by reports the moment one arrives.

It also keeps a short record of what your client really sent: how many changes
were reported and through what, what came with them (described in words, such
as "sealed table"; nothing is read out of it), what kind of change each said
it was (an effect arriving, one going, both, or nothing said), how many were
put down to an effect of yours running out, how many only took effects away
and how many of those came while a cast was waiting to be judged, which
requests the game refused, how each of the last 40 casts was judged
("changed", "silent", and so on), how the casts of spells without an icon came
out, and for each spell you cast which words of its tooltip were read as an
effect's length and which time was passed over. `/se debug` prints the
summary. The full
record is saved with the addon's settings at the next `/reload` or logout,
under `report` in `WTF\Account\<account>\SavedVariables\StatusEfficiency.lua`,
and is the thing to send with a bug report. It holds spell names, counts and
timings, and no character or account names.

The same record says what the game answered about each skill being usable
(`usable`) and which of the three ways of asking got the answer, in a fight and
out of one (`usableFrom`), and what it said of your party or raid (`group`):
how often that turned to someone fighting close by, someone fighting but nobody
close by, nobody fighting, or the game not saying. Next to it, under `panel`, is
what the settings panel
found out about this client: which of the game's controls it kept, which fonts
it had to replace, which labels were a tight fit, and how much room the Options
window gave the page.

## Known limitations

- **In combat the addon is told that a unit's effects changed, not which
  effect or whose.** The game hides what is in that report from addons. The
  most a client lets through is the kind of change: an effect arriving, being
  renewed, or going. So a cast counts as landed when an effect arrives or is
  renewed on the unit within moments of it. Another effect arriving there in
  the same moment (another player's debuff landing, an effect the enemy puts
  on itself, an effect of your own that a talent or a weapon adds) passes for
  your cast, so a miss can still show a red X now and then, more often in a
  group than alone. On your own buffs this is weaker still, because your
  effects come and go all through a fight.
- **On a client that does not show what kind of change a report is, an effect
  going is told from a cast landing only by its timing.** Build 71139 shows
  the kind, so there this is left for the rare report that says nothing (one
  that says everything on the unit may have changed). Elsewhere any change on
  the unit within moments of a cast passes for the cast: an effect of the
  enemy's own or another player's running out as much as one arriving. One of
  your own effects running out is known by when it happens: a change that
  comes just when an effect of yours on the unit was due to end is put down
  to that, and not to a cast. Three things follow:
  - It needs the effect's length to be right, and the game to report the
    ending when it happens. The addon keeps count, and stops doing this for a
    spell whose endings went unreported twice and more than one time in three.
  - For an effect you renewed before it ran out, it rests on the renewed
    effect ending one full length after the renewal. If the game gives a
    renewed effect extra time, its ending comes later than expected and can
    pass for a cast.
  - A change in the very frame a cast is announced goes to the cast, because
    that is when the game reports a landing. So a cast that misses in the exact
    frame another of your effects ends shows a red X. And an effect renewed in
    its last tenth of a second, where the report comes a frame apart from the
    cast, shows a green check until the next cast.
- **"Close by", for a fight that someone in your group is in, means close
  enough for the game to show them to you**, which is about a hundred yards.
  The game's own test for a group member being in range (about 40 yards)
  answers addons with a hidden value, so it is only asked where the game will
  not say whether it shows the member to you.
  A member the game will not answer about is not counted: whether they are in
  combat, or whether they are close by. `/se debug` says what was found, under
  "Your group".
- **An effect that ends early in combat is not noticed.** A debuff that is
  dispelled or used up, or a buff that is removed, keeps its red X until its
  timer runs out or the fight ends. The game says that an effect went from the
  unit, and not which one. A buff you already had when the fight began keeps
  its real end time.
- **A cast is still assumed to land where the addon has nothing to go on.**
  There a miss shows a red X for the length of the effect. That covers three
  cases:
  - an enemy that is neither your target nor showing a nameplate;
  - a client that has been found not to report changes in combat (see
    [Checking it against your client](#checking-it-against-your-client));
  - a spell you set to **Always** show an icon (or `/se track`) that the enemy
    does not answer: once two or more of its casts have been watched and fewer
    than half were followed by a change, the addon takes your word that it
    leaves something it cannot see. A buff set to **Always** is taken to land
    from its first cast. Both end once an effect with the spell's own name has
    been read off a unit.
- **A very slow landing can be taken for a miss.** An effect that shows up more
  than three seconds after its cast (a slow missile from far away) is not put
  down to that cast, and the button stays green.
- **Only your own effects count.** The same debuff or buff put there by another
  player is not seen, so the button stays green.
- **Spell detection is a guess from the tooltip.** A spell whose tooltip
  gives a time gets an icon unless the words around that time say it is
  something other than an effect's length (see point 3 under
  [Which spells get an icon](#which-spells-get-an-icon)). Those words are read
  in English only, and no list of wordings is complete, so a skill that leaves
  nothing behind can still start out with an icon. It does not keep it: once
  its first three casts have all left nothing, or six casts have been watched
  of which at most one left anything, the addon drops the icon by itself and
  says so in chat, so that an icon never just goes missing. It can watch that
  out of combat, and in combat for a spell cast on enemies (the enemy's
  effects do not change). For a buff it needs a client that lets it count
  effects in combat. Otherwise use `/se ignore <spell>`. A real status spell
  can lose its icon this way when its first three casts all miss, or after a
  long run of misses or immune enemies. It keeps being watched, and gets its
  icon back by itself, with a line in chat, once at least two in five of its
  casts have left something. `/se track <spell>` gives it back at once. The
  other way round, a real status spell whose tooltip words its length
  unusually is still given its icon, because only the wordings listed in
  point 3 are ruled out.
- **Spells with no target** cannot be recognised from the tooltip. An area
  debuff gets an icon when it is on the small built-in list, when you add it
  with `/se track <spell>`, or once its casts have been seen to work (point 4
  under [Which spells get an icon](#which-spells-get-an-icon)). A buff (a shout
  for the whole party, an aura, a stance) is recognised once its buff has been
  seen on you out of combat, or straight away with `/se buff <spell>`.
- **Durations come from the tooltip.** When a tooltip gives no duration the
  addon assumes 12 seconds until it has seen the real effect. Fix one with
  `/se duration <spell> <seconds>`.
- **An effect named differently from its spell** cannot be looked up by name, so
  that spell falls back to counting, change reports or timers.
- **Buffs that switch each other off** (stances, forms and aspects, or a spell
  that turns its own buff off when cast again) are followed correctly out of
  combat. In combat, when the client hides your buffs, the addon only knows
  what you cast, so the buff that was switched off keeps its red X until the
  fight ends.
- **Buffs on other people** are only judged on the friend you have targeted.
  There is no yellow state for buffs: the addon does not look across your
  party.
- **A buff that always shows a green check** because it is meant to be used
  only now and then (a defensive cooldown) can be hidden with
  `/se ignore <spell>`.
- **Area spells have no range check.** Every enemy in the fight with a nameplate
  showing is assumed to be in reach. Enemy nameplates need to be turned on for
  area spells to see more than your target.
- **Casts aimed somewhere else** (a mouseover or focus macro, or a buff cast on
  yourself with a modifier key while a friend is targeted) are judged against
  your current target. In combat that unit reports no change, so the cast is
  taken to have left nothing.
- **When the client hides who an enemy is**, enemies are told apart by their
  nameplates. With nameplates off, switching away from an enemy and back forgets
  what was on it.
- **Action bars.** The default bars are supported. Bartender4, Dominos and ElvUI
  buttons are picked up by name but have not been tried.
- **Whether a skill can be used is only as good as what the game tells.** Where
  the game answers about the action, that answer is used as it comes. Where it
  does not, and the addon falls back on the spell or on the button's colours, a
  "cannot be used" from either is believed only once that source has been
  right: checked against the action bar while it still answered, or seen to say
  "yes" or "short of rage" about the same skill. Until then the icon shows. On
  a bar addon that paints its buttons in colours of its own, or keeps them from
  being read, the colours say nothing and the icon shows as well.
- **The game's own icons** (ready check marks, raid markers) are named by their
  usual texture paths. If one shows up blank in this client, pick another.

## Development

```
StatusEfficiency/     the addon; this folder is what gets installed
  StatusEfficiency.toc
  Compat.lua          every call into the game, guarded against secret values
  Icons.lua           the three results and the icons on offer
  Spells.lua          which spells leave a status effect, and for how long
  Tracker.lua         which of your effects are on whom
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
used in arithmetic), the different ways a client might restrict aura queries
in combat, and the reports a client sends when a unit's effects change. By
default every aura query is refused in combat, as the documentation has it,
and only those reports get through. What comes with a report is played two
ways, and every scenario is run under both: the way build 71139 was seen to
send it, where the kind of change shows, and the way the documentation
describes it, where nothing does. It can also be told to lack or
break the game's controls, fonts and art, to draw text wider, to give the
Options page less room, and to keep back what it says about using a skill, so
that each thing the addon does by itself has a scenario.

```
pip install lupa
python3 tests/run_tests.py                # everything, both ways a client reports changes
python3 tests/run_tests.py settings       # only scenarios with "settings" in the name
python3 tests/run_tests.py --only lists   # only the way build 71139 reports them ("sealed": the documented way)
```

To redraw the icons (needs Pillow):

```
python3 tools/make_icons.py
```
