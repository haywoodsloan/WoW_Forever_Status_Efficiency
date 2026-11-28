# Status Efficiency

A World of Warcraft addon for **WoW Forever**. It puts a small icon on each action
button that tells you whether casting that spell again would do anything for its
status effect: the debuff it leaves on enemies, or the buff it leaves on you.

| Icon | A spell that leaves a debuff on enemies | A spell that leaves a buff on you |
| --- | --- | --- |
| Green check | None of the enemies it would hit has the debuff in full. Casting puts it on all of them, or adds a stack on all of them. | You do not have the buff, or it stacks and is not yet on you as many times over as it goes. |
| Yellow half circle | Some of them have it in full and some do not. | Not used: a buff is judged on one person. |
| Red X | All of them already have it, at full stacks. Casting again changes nothing. | You already have it, at full stacks. Casting again changes nothing. |

An enemy that is immune to a debuff is left out: it never will have it, and is
no reason to cast. So is one that stands further off than the spell reaches.

No icon means there is nothing to say: the spell applies no status effect, or
it is a debuff and there is no enemy to judge and no fight going on. Out of the
box the icons also stay away until a fight starts, yours or one that someone in
your group is in close by, and from a skill you cannot use right now (too
close, too far, the wrong stance). Both can be changed in the settings.

Version 0.5.4 is an early draft. It loads and draws its icons in the real
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
first line of the reply gives the version, "Status Efficiency: Version 0.5.4."

To update, replace the files in the `StatusEfficiency` folder and type `/reload`.
A full restart is only needed when a new version adds files.

## Using it

Attack an enemy. Every spell on your bars that leaves a debuff gets a green
check. Cast one and, once it lands, its button turns to a red X until the effect
ends. A cast that misses, or is dodged, parried or resisted, leaves the green
check where it is. Spells that hit every enemy around you go yellow when only
some of the enemies in the fight have the effect. Only the ones the spell can
reach are counted: with Thunder Clap on the enemy next to you and a second one
shooting at you from twenty yards off, the icon is the red X, because casting
again would do nothing for either (see
[Enemies out of reach](#enemies-out-of-reach)).

Spells that put a buff on you work the same way: a green check while you do
not have the buff, a red X while you do. A buff you can also put on other
people (a heal over time, a stamina buff) is judged on the friend you have
targeted, and on you when your target is an enemy or nobody.

A skill whose effect stacks, like Sunder Armor, keeps the green check until
the last stack is on: casting again still adds to it. The red X comes with the
last stack. A skill that stacks and hits every enemy shows the yellow half
circle when some of them carry every stack and others do not.

An enemy that is immune to a skill does not count for it. Use Rend on an
elemental that cannot bleed and the game says "Immune". From then on Rend
shows the red X on that elemental for as long as it is about. Every creature
of its kind gets the same, in later sessions too, once the addon is sure that
this was no passing shield: at once when you fight on your own and your other
hits land on the elemental, and otherwise when the game says "Immune" of its
kind a second time. A skill that hits every enemy is judged on the ones that
can take its effect. `/se immune` lists what was learned (see
[Immune enemies](#immune-enemies)).

An effect that a unit carries only once, whoever put it there, counts when it
is another player's. With another warrior's Demoralizing Shout on the enemy
your own shows the red X, and so does your Battle Shout while theirs is on
you: casting yours would change nothing. Their Sunder Armor adds to the same
stacks as yours. An effect that every caster has one of, like a bleed or a
heal over time, only counts when it is yours.

The icons appear when a fight starts, buff icons included, and stay on until it
ends, whatever you have targeted: your target dying does not take them away. A
fight is your own, or one that someone in your party or raid is in close by.
While it lasts and you have no enemy targeted, a debuff for one enemy is judged
on the enemies of the fight whose nameplates show: the green check when one of
them could do with it or none is in sight, and the red X when every one of
them carries it or is immune to it. Out of a fight your buttons stay bare. If you
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
fight. To see the icon on every skill regardless, pick **Every skill** in the
settings or type `/se usable off`.

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
addon sees its buff on you out of combat. `/se buff <skill>` does the same by
hand.

### Settings

Open **Options > AddOns > Status Efficiency**, or type `/se options` for the same
panel in a window of its own. The window can be dragged by its title bar and
opens where you left it. Changes apply straight away and are saved per account.

The panel has three tabs. Every setting is a row of its own: what it is called
on the left, its control on the right, and under them a sentence in plain words
that says what the setting is doing now. Hover a row's name or its control for
more. **Defaults**, at the top right, puts the tab that is open back to how it
started, and asks first.

The **Display** tab is about whether the icons show, and where:

- **Show status icons** turns the icons on and off, like `/se on` and `/se off`.
  While they are off the next two rows are greyed out, since neither changes
  anything then.
- **When to show them**:
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
- **On which skills**: **Every skill**, or **Only skills you can use right now**
  (the default), which leaves a skill bare while you cannot use it: too close
  or too far, in the wrong stance and the like. Being short of rage, mana or
  energy does not count, and neither does a cooldown.
- **Position.** Nine squares laid out like a button: the four corners, the four
  edges and the middle. Click one to put the icon there.
- **Size.** A slider from 8 to 48. **Auto** sizes the icon from the button it
  sits on, at about a third of the button's width, which is 16 on a standard
  button.
- **Preview.** Three pretend buttons, one for each result, wearing skills from
  your own bars and drawn as large as your action buttons, with the icon where
  and as big as it is on the bars. While this tab or the Icons tab is open and
  you are out of combat, your real action buttons show sample icons as well.

The **Icons** tab is about which icon stands for which result:

- **Icon set.** Four ready-made sets that change all three icons in one click.
  The set in use is framed, and named beside the four.
- **One icon for each result.** The three results (worth casting, partly worth
  casting, no need to cast) are listed with the icon each uses now and what it
  means. Click a result, then one of the 21 icons under the three: the addon's
  own ten on the first line, the game's ready check marks and raid markers on
  the second. The tile with a stroke through it means no icon at all for that
  result. A result says so when it ends up with the same icon as an earlier
  one. Buffs and debuffs share the icons.
- **Your own picture.** The tile marked `...` opens a box under the icons. Type
  a file ID such as `136243`, or a path such as
  `Interface\Icons\Spell_Nature_Slow`, and press Enter. Empty the box and press
  Enter to go back.

The **Skills** tab lists every skill on your action bars, those with an icon
first, each with its own picture and a few words on how it is treated. Click
one, and the pane beside the list shows everything about it. Every row has a
sentence under it that says what the setting is doing now and who decided: the
skill's tooltip, the game, what the addon saw in your fights, or you.

- **Show an icon**: Auto (the addon decides), Always, or Never. The sentence
  under it says why the skill has an icon or has none. For a skill without an
  icon the rest of the pane is greyed out.
- **Affects**: your target, all enemies in the fight, or you (a buff).
- **Lasts**: how long the effect lasts. Type a number of seconds to change it,
  or empty the box to let the addon work it out again.
- **Stacks up to**: the most stacks the effect can have, with a dash for an
  effect that does not stack. Until all of them are there the icon stays the
  green check. Type a number to change it, `1` for an effect that does not
  stack, or empty the box to let the addon work it out again. The same as
  `/se stacks`.
- **Other players**: **Count theirs** treats another player's effect like your
  own, which is right for an effect a target can only have once, whoever put it
  there. **Ignore theirs** only looks for your own, which is right for an
  effect that every player applies separately, like a bleed. The same as
  `/se anyone` and `/se mine`. Both are greyed out for a buff that only ever
  goes on its caster.
- **Immune**: the kinds of enemy the skill does nothing to, as far as the addon
  has found (see [Immune enemies](#immune-enemies)): first the kinds the icon
  leaves out, then the ones seen immune only once. Hover the list for all of
  them and for which ones you added yourself. **Add target** marks the kind of
  enemy you have targeted as immune to the skill, like `/se immune <skill>`,
  and says so when there is nothing it can add. **Clear list** empties the list
  for this skill, like `/se immune forget <skill>`, and asks first.
- **Reset this skill** undoes your own changes to the skill, so that the addon
  works it out by itself again. What it learned about the skill in your fights
  stays, and so do the enemies found immune to it. **Defaults** on this tab
  does the same for every skill at once.

Pressing Enter in a box you did not change leaves the addon's figure the
addon's own.

Two lines at the head of the list change a setting for many skills at once:
**All offensive skills**, which are the ones you use on enemies, and **All
defensive skills**, which are the ones you use on yourself or on friends. A
group takes in every skill on your bars that falls into it, with or without an
icon, and needs at least two of them. Click a group, and the pane shows its
skills by their pictures, with three rows under them:

- **Show an icon**: Auto, Always or Never, for every skill of the group.
- **Affects**, for the offensive skills only: your target or all enemies.
- **Other players**: Count theirs or Ignore theirs. Skills that only ever go on
  their caster are left out of this one, and the row says how many.

Where all skills of the group have the same setting, a click changes them at
once, and a click on the choice they had puts them back. Where they differ, the
row says how ("9 are on Auto, 4 on Always and 1 on Never."), and a click asks
first in the strip at the bottom, since it wipes those differences out.
**Reset these skills** undoes your own changes to the skills of the group, and
always asks first. How long an effect lasts, how high it stacks and which
enemies are immune stay with each skill: click the skill for those.

A skill is shown with its own picture, the one on its action button. Where the
game gives none for the skill, the panel takes the picture of the action slot
the skill sits in, and shows a question mark only while the game has neither.

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
- If this client cannot make a box to type in, the panel shows the number as
  plain words and says which chat command changes it.

To have the plainer controls anyway, type `/se plain` and then `/reload`.

### Commands

`/se` and `/statusefficiency` are the same command. A skill's name can be typed
in any case, shortened to the start of it, or shift-clicked from the spellbook.
Every command answers in chat with a sentence that says what it did, and what
to type if that was not what you meant.

| Command | What it does |
| --- | --- |
| `/se` | Lists the commands. The first line gives the version of the addon. |
| `/se options` | Opens or closes the settings window. `/se options display`, `/se options icons` and `/se options skills` open it on that tab. |
| `/se on`, `/se off` | Turns the icons on or off. |
| `/se when <always\|combat\|group>` | When the icons appear: always, only while you are in combat, or while you or someone in your group close by is in combat (the default). `party` and `raid` work for `group`. |
| `/se usable <on\|off>` | `on` (the default) shows an icon only on a skill you can use right now. `off` shows it on every skill. |
| `/se list` | Lists the skills on your action bars and says of each what its icon checks and why it has one, or why it has none. |
| `/se track <skill>` | Puts the skill on Always, so it has an icon. The answer says what the icon will check. |
| `/se buff <skill>` | Puts the skill on Always, and treats its effect as a buff on you. |
| `/se debuff <skill>` | Puts the skill on Always, and treats its effect as a debuff on enemies. |
| `/se ignore <skill>` | Puts the skill on Never, so it has no icon. |
| `/se auto <skill>` | Puts the skill back on Auto: the addon decides everything about it by itself again. Your own choices for it are cleared, and so is what the addon had learned about it. |
| `/se aoe <skill>` | Makes the icon check every enemy in the fight. |
| `/se single <skill>` | Makes the icon check only the enemy you have targeted. |
| `/se duration <skill> <seconds>` | Sets how long the skill's effect lasts. `auto` lets the addon work it out again. |
| `/se stacks <skill> <number>` | Sets the most stacks the skill's effect can have: the green check stays until all of them are there. `1` is an effect that does not stack, and `auto` goes back to what the game and the tooltip say. |
| `/se anyone <skill>` | The icon treats another player's effect of this skill like your own. |
| `/se mine <skill>` | The icon only looks for your own effect. Another player's is ignored. |
| `/se immune` | Lists the enemies that are immune to a skill. `/se immune <skill>` adds the kind of enemy you have targeted to that list yourself. |
| `/se immune forget [skill]` | Clears the list, for one skill or for all of them. |
| `/se corner <where>` | Moves the icon: `tl`, `top`, `tr`, `left`, `center`, `right`, `bl`, `bottom`, `br`. |
| `/se size <pixels>` | Icon size from 8 to 48. `auto` sizes it from the button again. |
| `/se icons` | Lists the icon names and what each result uses now. |
| `/se icon <green\|yellow\|red> <icon>` | Sets the icon for one result: an icon name, the file ID or the path of a picture in the game's files, `none` for no icon, or `default`. |
| `/se debug` | Shows what the game lets the addon see right now. Paste this into a bug report. |
| `/se log` | Shows or hides a running log of what the addon notices. |
| `/se plain` | Has the settings panel draw its own plainer controls instead of the game's, or the game's again. Takes effect after `/reload`. The panel changes over by itself wherever the game's controls are missing or do not work. |
| `/se reset` | Clears every setting and everything the addon has learned. |

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

### Effects that stack

How many times over an effect can be on one unit comes from three places, and
the largest of them counts:

- the game's own data for the spell, where the client gives it out. It may
  keep it back during a fight, and is then asked again afterwards;
- the spell's tooltip: "Can be applied up to 5 times", "Stacks up to 5 times",
  "up to 5 stacks";
- what has been read off a unit: an effect seen there three times over stacks
  at least that far. This is the weakest of the three, because the effect may
  go higher than it has been seen to.

`/se stacks` overrules all of them. `/se list` shows the number for each spell
and where it comes from.

Out of a fight the stacks are read off the unit. In a fight the game hides
them, so they are counted: one for each cast that is seen to land, yours or
that of someone in your group (see the next section), up to the most the spell
allows. What is read once the fight is over replaces the count.

The count is kept on the low side on purpose, because a count that runs ahead
shows the red X on a skill that still has a stack to add:

- A cast only adds a stack when the enemy reports a change in the very moment
  the cast is announced, which is when the game shows a landing. A change that
  comes later, within the time the skill is still being waited for, passes for
  the landing where nothing better is known, and the effect is taken to be
  there. It adds no stack: it is as likely something else that changed on the
  enemy after a miss.
- Where the client shows that a report only added effects, the effect was not
  there before, so the count starts at one whatever it was. Where it shows the
  report only renewed effects and the addon had nothing for the enemy, someone
  else put the first stack there: the count goes to two.
- When the effect runs out, the count starts over.

### Other players' effects

Whether another player's copy counts is also read from the tooltip. An effect
that does its work bit by bit ("damage over 21 sec", "every 3 sec") is each
caster's own, and so is one that makes the enemy attack its caster. Anything
else that lasts is taken to be on a unit only once, whoever cast it. A spell
with no tooltip to read counts as your own. `/se anyone` and `/se mine` say
otherwise for a spell, and `/se list` shows which it is.

Out of a fight their copy is read off the unit like your own, with how long it
has left. In a fight nothing on a unit can be read, and what is left is this:
someone in your party or raid is heard casting a spell that is on your bars
too (any rank of it), and in that very moment a unit it could land on reports
a change. Then theirs is taken to have landed there. Nothing is taken on trust
for a cast that is not yours: no change in that moment, no effect.

If you and they cast the same spell in the same moment, your cast is judged
first and the effect is put down as yours. Which of the two is on the unit is
not told then, so it is given the shorter time of the two.

How long theirs lasts is not how long yours does. A talent can make your
shouts last half again as long as another warrior's, and a lower rank of a
spell can leave a shorter effect. So their cast is given:

- what that member's own copy was read to last, once it has been read off a
  unit out of a fight with the game saying who put it there. This is kept
  until the group changes;
- otherwise two thirds of the time yours lasts (or of the time their rank of
  the spell lasts, where that is less), and no more than the shortest copy of
  anyone else's that was read. That is on the safe side: the red X can go a
  little before their effect does, and does not stay on after it;
- the whole time for an effect that stacks, which is one effect that every
  caster renews.

### Immune enemies

Nothing an addon may read says beforehand what a creature is immune to. What
the game does say, in a fight too, is a word for what an attack or a spell
just did to a unit, the same word it floats over that unit's portrait: "Miss",
"Dodge", "Resist", "Immune". It does not say whose attack the word is about.

So an enemy is taken to be immune to a skill only when the game says "Immune"
of it in the very moment a cast of yours with that skill went to it, with
nothing to show for the cast there. Then:

- **That enemy** gets the red X on the skill, and keeps it for as long as it
  is about. (Up to 0.5.3 the X went again after twelve seconds, and the green
  check then asked for a cast that the enemy turned away once more.)
- **A passing shield is told by what else the game says of that enemy.** A
  shield or a banishment turns everything away, your swings too. So when the
  game also calls the enemy immune to something else, a swing or a skill
  without an icon, with no hit landing on it in between, the enemy is taken
  to be behind a shield. It gets the red X until a hit lands on it again, or
  until twelve seconds after the game last said "Immune" of it, and nothing
  is held against its kind of creature. A second skill with an icon that is
  turned away is no such sign: an elemental can be immune to two of your
  skills.
- **Its kind of creature** is kept with your settings, and counted on once it
  is sure that no shield was in the way. Fighting on your own, that is when a
  hit landed on the enemy within four seconds before the game's word and
  another within four seconds after it, with nothing else turned away in
  between, or when a hit landed in the very moment of the word. In a party or
  raid the game's word may be about somebody else's attack, so there it takes
  the word on two occasions: the same creature twice, twelve seconds or more
  apart, or two of a kind once each. From then on every creature of that kind
  is left out for that skill before the first cast, in later sessions too.
- **An enemy seen to carry the effect** is not immune, whatever was said
  before: what was kept of it is dropped at once. Its kind is then known for
  an immunity that comes and goes, and is never counted on as immune again.
  Nor is anything kept when the game calls an enemy immune that has carried
  the effect before: that will pass, and the skill stays worth a try.

In a group somebody else's attack can be called immune in the moment of your
cast. The word is not taken for your cast's answer, and nothing is learned
from it, when anything else in that moment could be the answer instead:

- the enemy's effects changed in that moment, as they do when a cast lands.
  The landing then stands, as it would without the word;
- the game also said "Miss", "Dodge", "Parry", "Resist" or the like of that
  enemy in that moment: one of the two words was for another attack;
- two casts of yours went to that enemy in that moment.

Nothing else passes for immunity. A cast that showed nothing may as well have
missed, and several in a row may as well have missed in a row, so silence
never turns an icon red.

What kind of creature an enemy is comes from the game's own number for it,
which is part of the name the game gives the enemy. Where a client hides that
during a fight, an enemy met before the fight is still known, one that joins
later goes by its name if the client tells that, and otherwise only that one
enemy is learned about and not its kind. A player is never a kind of creature.

`/se immune` lists the kinds of enemy that are immune to each skill, and the
ones seen immune only once so far. `/se immune <skill>` adds the kind of enemy
you have targeted to that list yourself. It is then shown as "(added by you)",
and it stays until you clear the list: `/se immune forget <skill>` clears it
for one skill, and `/se immune forget` for all of them.

### Who is looked at

- A debuff aimed at one enemy is judged against your target (or the enemy the
  game's soft targeting has picked).
- A debuff that hits everything around you is judged against the enemies that
  are in the fight and have a nameplate showing, plus your target.
- A debuff that hits everything around you leaves out the enemies that stand
  further off than it reaches (see
  [Enemies out of reach](#enemies-out-of-reach)).
- No such enemy: the icon is hidden. During a fight a debuff aimed at one
  enemy is judged on the enemies of the fight whose nameplates show instead:
  the red X when every one of them carries the effect or is immune to it, and
  the green check otherwise, also when none of them is in sight.
- A buff is judged on you. One that can be cast on other people is judged on
  your target instead while that target is a living friend.

### Enemies out of reach

A skill that hits every enemy around you does nothing for one that stands
further off than it reaches. Such an enemy is left out when the skill is
judged: it is no reason to cast, and none not to. With every enemy out of
reach there is nobody to judge the skill on, and its icon is hidden like that
of any skill that can do nothing right now. (With **Every skill** chosen it
shows what it would with all of them within reach.)

The game does not tell an addon how far away an enemy is. It does say whether
an enemy is within the range of each of your skills, which is what turns the
key on a button red. The addon asks that about every enemy in the fight, for
every skill on your bars that goes to an enemy, and puts the answers together.
For a warrior: Rend reaches the enemy, so it is within 5 yards. Charge does, so
it is 8 to 25 yards off. Neither does and Intimidating Shout does not either,
so it is more than 25 yards off.

An enemy is only left out when that proves it to be further off than the
skill reaches. How far a skill reaches is read out of its description ("all
enemies within 10 yards"), and for the well known ones that do not say it
comes from a list (Thunder Clap: 8 yards). A skill whose reach is not known
leaves nobody out, and an enemy of whom the game says nothing counts as it
always did.

Three things could make such a proof wrong, and each is watched for:

- **A game that answers about your target whoever it is asked about.** What a
  range says of anybody but your target is only believed once it has given
  two enemies different answers in the same moment.
- **A skill that cannot be used on some enemy at all** and says "out of
  range" of it. One that says so of an enemy the other skills put inside its
  range is not asked again.
- **A skill that reaches further than thought**, through a talent or in
  another version of the game. A cast that shows on an enemy taken to be out
  of reach is noted, and from the second such cast on the skill is taken to
  reach a yard past where that enemy stood. That is kept with your settings.

A cast with an enemy out of reach is not expected to show on that enemy, and
that it does not is never held against the skill. The record's `reach` part
says what your game answered (see
[Checking it against your client](#checking-it-against-your-client)).

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
   distance, and a second and a half for a skill used at arm's length, which
   comes down as that skill's landings are timed. A skill used at arm's length
   is then held to what its landings have been seen to do:

   - once five of them, and four in five, have shown within 0.15 seconds of
     the cast, it is given a quarter of a second;
   - once three of them, and nine in ten, have shown in the very moment the
     cast was announced, it is held to that moment, give or take a twentieth
     of a second. That is how build 71139 reported every skill used at arm's
     length: 36 of the 40 casts in its record showed with no gap at all.

   The shorter the wait, the less often something else that changes on the
   enemy after a miss is taken for the cast landing. A landing that shows
   later than the skill is held to counts against the hold, so a skill that
   stops showing that fast gets its time back. What comes too late for a cast
   held to its moment is not taken for that cast, and a line about it is kept
   in the record (see below), so that it can be checked afterwards that no
   landing was turned away.

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
it was (an effect arriving, one going, both, or nothing said, and of the ones
arriving how many only added effects and how many only renewed them), how many were
put down to an effect of yours running out, how many only took effects away
and how many of those came while a cast was waiting to be judged, which
requests the game refused, how each of the last 40 casts was judged
("changed", "silent", and so on), how the casts of spells without an icon came
out, and for each spell you cast which words of its tooltip were read as an
effect's length and which time was passed over, which words say how often its
effect stacks (`stacks`), what the game's own data gave for that (`gameStacks`:
a number, `false` for an effect that goes on once, and nothing where the game
would not say), and which words show the effect to be each caster's own
(`own`). It also holds what was heard of the casts of the people in your
group (`others`): how many, for how many of those made in a fight the game
said which spell it was and for how many it kept that back, how many were of a
spell of yours that another player's copy counts for, how many of those were
seen to land, how often another player's copy was read for how long it lasts,
and how often the game said with it who had put it there. And the last 20
changes that came too late for a cast held to its moment (`late`). And what
the game said attacks did to enemies (`combat`): through how many unit names
the addon could listen for it, how often it heard something and how often the
word was kept from it, each word with how often it came, a line for each of
the last 20 times the game said "Immune" with what that was taken for, a line
for each thing learned from it, and how the game named the kinds of the
enemies you met (by number, by name only, or not at all). A cast's own line
ends with the words the game said of its targets in that moment. And what the
game said when asked whether an enemy is within the range of a skill
(`reach`): how often it said yes, no or nothing, of your target, your soft
target and the nameplates, which ranges gave two enemies different answers
at once and so are believed of enemies other than your target (`proven`), how
often each skill began leaving an enemy out of its count (`left`), and a line
for everything out of the ordinary (`notes`). Each area skill's entry under
`spells` gives how far it is taken to reach (`reach`) and the words that was
read from (`around`). `/se debug`
prints the summary. The full
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
it had to replace, which labels were a tight fit, how much room the Options
window gave the page, and which skills the game had no picture for.

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
  down to that cast, and the button stays green. The same goes for a skill used
  at arm's length that has always shown in the moment of its cast and for once
  shows later: the record keeps a line about each such change (`late`).
- **In a fight, another player's effect is only seen through their cast.**
  The game hides what is on a unit, so their copy is followed by the cast that
  put it there (see [Other players' effects](#other-players-effects)). That
  leaves these gaps, and in each of them the button stays green or yellow
  where a red X would be right, never the other way round:
  - The game has to say which spell a group member cast. Its documentation
    lets a client keep that back during a fight, and then their casts cannot
    be followed at all. The record says what your client does, under `others`.
  - Only the casts of people in your party or raid are heard, and only a cast
    that the unit answers with a change in the same moment counts.
  - An effect that was already on an enemy when the fight began, and that the
    addon had no chance to read, is not known.
  - Your own cast still finds some of it out: where the client shows that your
    cast only renewed an effect, the effect was there already, and a stacking
    one is counted as two.
- **How long another player's effect lasts is a careful guess until it has
  been read.** Theirs is given two thirds of the time yours lasts, so the red
  X can turn green up to a third early when theirs lasts as long as yours.
  Once their copy has been read off a unit out of a fight, with the game
  saying who put it there, their casts are given what theirs really lasts.
  Whether the game says who put an effect there is in the record too
  (`others.sourced`).
- **Effects that go by different names are not known to exclude each other.**
  Two skills whose effects do not stack with one another (two different
  shouts that raise the same thing, say) are each judged by their own name.
- **Stacks are counted in a fight, not read.** The count can fall behind the
  real number: a stack added by someone outside your group, or by a group
  member whose cast the game kept secret, or by a cast of yours whose landing
  was reported a moment later than usual, is not counted. The button then
  shows the green check where the red X would be right. It is put right
  when the effect is read out of a fight.
- **An immune enemy is only known by the game's word for it.** If a client
  does not send that word to addons, or keeps it secret during a fight, no
  enemy is ever learned to be immune and the green check stays, as before
  0.4.2. `/se debug` and the record (`combat`) say what your client does.
  The same goes for these, in each of which the green check stays where a red
  X would be right:
  - a skill whose damage lands while only its effect is refused, if the game
    does not announce the refusal;
  - a spell that takes a while to reach its target, which is answered when it
    arrives and not when it is cast;
  - an "Immune" that came together with a miss or with a change on the enemy
    (see [Immune enemies](#immune-enemies)).

  `/se immune <skill>` adds such a creature by hand.
- **A shield can still be taken for a lasting immunity** when nothing else is
  turned away while it holds. If a skill of yours with an icon is the one
  thing an enemy's shield turns away, that enemy keeps the red X after the
  shield is gone. If you were also fighting on your own and your hits landed
  within four seconds before and after, or it happens with two of a kind, the
  kind is kept as immune. This takes a shield that comes and goes between two
  of your swings, before the skill has ever been seen to land on that kind of
  creature. Casting the skill once all the same puts it right for good: the
  effect is seen to land, and that kind is never counted on as immune again.
  So does `/se immune forget <skill>`.
- **A kind of enemy is only known to be immune after the game has said so
  once.** The first cast at the first one of its kind still shows the green
  check.
- **How far off an enemy stands is only known through the ranges of your own
  skills** (see [Enemies out of reach](#enemies-out-of-reach)). With nothing
  but melee skills on the bars an enemy 6 yards off and one 30 yards off look
  the same, and neither is left out of a skill that reaches 8 yards. An enemy
  standing between a skill's reach and the next range your skills can tell
  apart is counted as within reach, so the yellow half circle can still show
  for it. An enemy without a nameplate is not seen at all, as before.
- **A skill is held to the moment of its cast only after three landings.**
  Until then its casts are waited for a little longer, and in that time
  another effect arriving on the enemy after a miss can pass for the landing.
  The first three landed casts of each skill after updating to 0.4.0 are
  judged that way.
- **Spell detection is a guess from the tooltip.** A spell whose tooltip
  gives a time gets an icon unless the words around that time say it is
  something other than an effect's length (see point 3 under
  [Which spells get an icon](#which-spells-get-an-icon)). Those words are read
  in English only, as are the ones that say how often an effect stacks and
  whether it is each caster's own. No list of wordings is complete, so a skill that leaves
  nothing behind can still start out with an icon. It does not keep it: once
  its first three casts have all left nothing, or six casts have been watched
  of which at most one left anything, the addon drops the icon by itself and
  says so in chat, so that an icon never just goes missing. It can watch that
  out of combat, and in combat for a spell cast on enemies (the enemy's
  effects do not change). For a buff it needs a client that lets it count
  effects in combat. Otherwise use `/se ignore <skill>`. A real status spell
  can lose its icon this way when its first three casts all miss, or after a
  long run of misses, or of casts at immune enemies that the game did not
  call immune (one it did call immune is not held against the skill). It
  keeps being watched, and gets its icon back by itself, with a line in chat,
  once at least two in five of its casts have left something. `/se track <skill>` gives it back at once. The
  other way round, a real status spell whose tooltip words its length
  unusually is still given its icon, because only the wordings listed in
  point 3 are ruled out.
- **Spells with no target** cannot be recognised from the tooltip. An area
  debuff gets an icon when it is on the small built-in list, when you add it
  with `/se track <skill>`, or once its casts have been seen to work (point 4
  under [Which spells get an icon](#which-spells-get-an-icon)). A buff (a shout
  for the whole party, an aura, a stance) is recognised once its buff has been
  seen on you out of combat, or straight away with `/se buff <skill>`.
- **Durations come from the tooltip.** When a tooltip gives no duration the
  addon assumes 12 seconds until it has seen the real effect. Fix one with
  `/se duration <skill> <seconds>`.
- **An effect named differently from its spell** cannot be looked up by name, so
  that spell falls back to counting, change reports or timers.
- **Buffs that switch each other off** (stances, forms and aspects, or a spell
  that turns its own buff off when cast again) are followed correctly out of
  combat. In combat, when the client hides your buffs, the addon only knows
  what you cast, so the buff that was switched off keeps its red X until the
  fight ends.
- **Buffs on other people** are only judged on the friend you have targeted.
  The addon does not look across your party, so a buff never shows yellow for
  being on some of you and not on others.
- **A buff that always shows a green check** because it is meant to be used
  only now and then (a defensive cooldown) can be hidden with
  `/se ignore <skill>`.
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
in combat, the reports a client sends when a unit's effects change, and the
casts of the people in your group, with the spell readable or kept secret. By
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
