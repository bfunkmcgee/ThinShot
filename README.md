# Sandline

A turn-based tactics thin slice built in **Godot 4** (2D isometric, GDScript,
placeholder art). One desert counterinsurgency: **Kestrel Squad**, Crown
soldiers seconded to a Confederacy the locals never asked them to police,
against **the Thirst** - goblin settlements dispossessed of their water.

## The game

| | Rodar Akai | Machinegunner | Rifleman | Well-hand | Runner | Light Runner | Conscript | Marksman |
|---|---|---|---|---|---|---|---|---|
| Side | you | you | you | AI | AI | AI | AI | AI |
| Per battle | 1 | 1 | 3 | 3–4 | 1 | 1–2 | 3 | 1 |
| Weapon | battle rifle | belt-fed MG | carbine | scavenged rifle | submachine gun | submachine gun | revolver | bolt rifle |
| HP | **10** | 8 | 8 | 4 | 4 | 3 | **2** | 4 |
| Move | 5 | 3 | 5 | 4 | **5** | **6** | **5** | 3 |
| Attack range | **6** | 4 | 4 | 3 | **2** | **2** | 3 | **5** |
| Damage/round | **4** (2 in cover) | 2 (1) | 2 (1) | 2 (1) | 2 (1) | 2 (1) | 2 (1) | **4** (2) |
| Accuracy | **95%** | 78% | 90% | 60% | 58% | 52% | **48%** | 70% |
| Magazine | 3 | **6** | 3 | ∞ | ∞ | ∞ | ∞ | **1** |
| Fire modes | single | **burst, full auto** | single, burst | single | **burst** | **burst** | single | single |
| Ability | *(his perk tree)* | **suppressive fire** | — | — | — | — | — | — |

(The Scout Team Lead is retired: Rodar Akai fills his slot — same spawn, same
job, stronger soldier. An old save's lead becomes Rodar, record intact.)

The squad also carries **ordnance the Thirst has nothing like** — two frags and
two smokes for the whole battle, pooled, thrown by whichever soldier is in the
right place. It is the answer to being outnumbered: grenades are the only
thing in the game that touches more than one cell, and the only damage that
does not roll to hit.

A five-soldier squad, each with a job:

- **Rodar Akai, Hero of the Scouts** — designated marksman and the squad's
  leader. A battle rifle reaching half again as far as a carbine, dropping a
  healthy goblin in one hit — held by a veteran who starts at the accuracy cap,
  so his whole progression is his perk tree. If he falls, the mission is lost
  on the spot.
- **Machinegunner** — area control. No semi-automatic setting at all: his
  lightest option is a two-round burst, and **full auto (A)** walks four rounds
  across a target at reduced accuracy. **His overwatch is not a sentry post**:
  it reaches **6 tiles rather than his weapon's 4**, and answers with **two
  rounds instead of one** — so putting him on watch genuinely covers the ground
  the rest of the squad has to cross. On top of that he has an ability no one
  else does — **suppressive fire (S)**: three rounds put down *around* a
  target rather than into it. No damage and no hit roll, but **everything
  within two tiles is pinned — it cannot move at all next turn**, shoots 25%
  worse, and cannot set overwatch. Six rounds in the belt, and he is the
  slowest soldier on the field.
- **Kestrel Riflemen** ×3 — the fast, accurate line. Single shots, or a braced
  burst when they hold still.

The Thirst fields what a dispossessed duneworks can arm and no more, and its
roster is a reading of its supply. **Well-hands** hold ground with old rifles:
labourers off the capped wells, fighting where they used to draw water.
**Runners** carry submachine guns - almost no reach at two tiles, but they move
as fast as your riflemen and fire a burst the moment they close, so the answer
is to kill them on the way in rather than let them arrive. **Light Runners**
are the same gun stripped for speed: the fastest thing on the field at six
tiles, so they arrive a full turn ahead of their heavier twin and split your
attention before the real push lands. Travelling light costs them - nothing to
brace the weapon against (52%), and no plate to stop the third round through
cover instead of the fourth.

**Pressed Conscripts** are the newest of them, and their numbers are an
equipment list rather than a character sketch: a worn-out sidearm handed over
last week, no armour, and no training to speak of. Two HP means a single
carbine round puts one down, and at 48% they mostly miss. They are pushed out
front because the settlements that lost their water have sons and the Thirst
has more of them than it has rifles. Every round you spend on one is a round
Rodar did not spend on something that matters, which is the whole reason
they are standing there.

Do not mistake the supply for the skill. The **Thirst Marksman** is their
designated shot: a bolt rifle reaching five tiles — further than anything
you carry except Rodar's — at 70% and four damage a round, which is
half a scout. He is the counter-sniper the campaign builds toward, and he
answers to exactly one weakness. **One round in the rifle**, and the bolt
worked by hand between shots, so he reloads after every single one. Reloading
costs the move, so the Marksman is **rooted for as long as he keeps firing**: he
will trade with you every turn, from the same tile, forever. Kill him with
Rodar (six tiles out-reaches him, and four damage drops him in one), break
line of sight and make him choose between shooting and repositioning, or eat a
scout's worth of damage crossing his lane.

Seven missions across two operations, on 16×10 isometric maps. It is one story,
and **the objectives are how it is told** — each mission opens with a briefing
and closes on a debrief that sets up the next.

### Operation Dry Well

Push the Thirst back off the eastern wells, and find out what they are carrying.

1. A border contact. The Thirst has crossed the wash for the first time -
   eleven days after an Accord survey capped four marginal wells north of it -
   and the Accord wants the crossing clear. You fight them because that is the
   order you were given, and the bodies turn out to be carrying sorted,
   tallied crates. Nobody hauls a tally into a raid.
2. You follow the route to the yard where the load is stacked. Killing carriers
   changes nothing - there are always more carriers - so the load is what
   matters. Burn it, and find it was never scrap: machined ordnance, and
   factory-new Tarkesh Mattocks from a foundry unwritten three centuries ago,
   in crates struck with a Crown depot mark that came off the maps eleven
   years back.
3. That depot is Outpost 7, and the Thirst has been eating out of it for a
   decade. You cannot hold the place, so you do not try: blow the two ammo
   stores and walk the squad back out.

### Operation Long Survey

The stores were drawn down before you got there. Find out who took the rest,
and where it went.

4. **The Long Haul** — a Thirst column still walking, two days after you were
   told they were finished. **Burn its load**, strung out across ground with
   almost nothing on it to hide behind. What they were hauling turns out to be
   water, which means they are supplying something a long way out.
5. **The Cistern** — the only water east for a day, walled and held. You
   cannot go round it and you could not hold it, so you **break through and
   out the far side**: no caches, no body count, just get the squad through.
   Past it every track runs together into one.
6. **The Holding Pens** — the water was never for the Thirst. Behind their line
   is a wire pen with Confederacy surveyors in it, kept alive for eleven years
   because somebody wanted the maps in their heads. **Reach them, then walk
   them out.**
7. **The Survey Camp** — a bowl in the rock with the whole Thirst standing in
   it, because somebody down there has been keeping them together. **End the
   reading.** The first operation taught that killing carriers changed
   nothing; this is the one time the killing is the point, and the man who
   made it so is not among the bodies.

Which is why each map asks for something different:

1. **Dry Wash** — open skirmish. Kill every goblin. The teaching level.
2. **The Scrapline** — a raid on the yard where the load is stacked. **Burn
   three caches** spread corner to corner behind the barricades, and **drop the
   relay mast** that tells everyone within forty miles you are here. A
   body count does not end this one; you can win with goblins still standing,
   and you can wipe them out and still not be finished. The crates turn out to
   hold machined ordnance — and the mast carries the same depot mark, which is
   what points you at Outpost 7.
3. **Outpost 7** — a raid with a way out. **Blow both ammo stores** at opposite
   ends of the compound, *then* **walk the whole squad back to the extraction
   zone** on the west edge. The zone stays shut until the charges go off, so
   the last stretch is a fighting withdrawal across ground you already crossed
   once — with whatever the Thirst has left chasing you.
4. **The Holding Pens** — a rescue behind **barbed wire**, which is the only
   thing on the board that stops movement and nothing else: you can see the
   prisoners from your start line and shoot the guards straight through the
   fence, but the only way in is **one gate**, dug in behind sandbags. Prep by
   fire, breach, walk back out the same hole carrying people.
   Ending a move next to a prisoner cuts them loose — there is no button, and
   reaching them *is* the rescue. Freed, they get up, keep their own slower
   pace, and count for the extraction like anyone else: the zone will not open
   until all of them are aboard. They carry nothing and cannot shoot, throw or
   set charges, and the Thirst will not fire on them or catch them in a blast —
   which makes the walk home a problem of tempo rather than of covering fire.

The Thirst gets heavier as you go — 9 goblins on Dry Wash, 13 in the bowl at
the end — but so does your squad, and by the second operation your veterans
have specialties.

Kestrel Squad is elite — tougher, faster, longer-ranged — but the Thirst has
numbers, holds the ground, and is fighting where it lives.

## Operations, and the two camps

The campaign is a series of **operations**, each a run of missions the squad
flies out for and stays out on. Where they sleep between missions depends on
where they are in one:

- **The garrison** is home, and where an operation begins and ends. Walls,
  huts, stores — and **the assignment post**, the only place the dead are
  replaced.
- **The field camp** goes up between the missions of a single operation: a
  tent, some scrap, and open ground in every direction. Same functions, no
  permanence, and it takes its ground from **the operation's biome**.

**Replacements are a garrison thing.** Lose a scout on the first mission of an
operation and you fight the rest of it four strong — that is the cost of the
loss, and it is felt for as long as the operation lasts. Back at the garrison,
command signs on however many bodies you are short. What a death takes
permanently is the rank, the specialties and the kills; what it does not take
is the campaign.

Both camps are **real time and directly controlled** — you walk Rodar Akai
around with **WASD or the arrows**, and press **E** at anything worth
using:

- **Your squad** stand around the camp. Walk up to one to read their record —
  rank, XP, specialties — and if they earned a promotion on the last mission,
  **you choose their specialty here**, face to face, rather than on a screen
  that interrupts the debrief. **Standing clear of everyone selects yourself**,
  which is how you take your own promotion.
- **The stores tent** holds the squad's ordnance. Four pieces between them,
  split however you like: four frags and no smoke, one and three, or the 2/2
  the squad carried before there was anywhere to change it.
- **The briefing table** gives the next mission's orders and deploys you.
- **The assignment post** — garrison only — signs on replacements for anyone
  lost, green: no rank, no specialty, nothing the squad lost with them.

Who you walk around as follows the chain of command: **Rodar Akai, then the
machinegunner, then a rifleman**, and within a role the senior survivor. Nobody
is replaced until the operation is over, so somebody always has to take it.

Biomes are plumbed and every value currently resolves to the desert set, since
there is one floor tilesheet in the project — see `ASSETS.md`. Both operations
are desert, so nothing looks wrong yet.

## The squad

The five soldiers are **named, and they are the same five from one mission to
the next**. They earn ranks, they specialise, and **when one falls they are
gone for the campaign** — nobody replaces them. Lose a scout on Dry Wash and
you assault The Scrapline four strong, with one fewer rifle for every fight
that follows.

Everything else resets between missions: **survivors deploy at full HP, with
full magazines, and the squad's grenades are restocked**. Attrition costs you
soldiers, never a wounded start.

| Rank | XP | Gains |
|---|---|---|
| Scout | 0 | — |
| Corporal | 6 | +3 acc, +1 HP, **choose a specialty** |
| Sergeant | 14 | +3 acc, +1 HP, **choose a specialty** |
| Staff Sergeant | 26 | +3 acc, +1 HP, **choose a specialty** |
| Master Sergeant | 40 | +3 acc, +1 HP, **choose a specialty** |

Rank gains are cumulative, and accuracy is capped at 95% — nobody ever becomes
a sure thing. Because of the cap the machinegunner (78%) gains far more from
rank than Rodar, who starts capped — which is why his specialties, not his
accuracy, are his whole progression.

**XP:** 3 a kill, 4 a demolished cache, 4 a rescue, 3 for walking off the map
alive.

**Specialties** are a two-way choice at every rank — four picks over a full
career — and **each class chooses from its own tree**:

**Scout — the skirmisher:**

- Corporal: **Sprinter** (+1 tile of movement, permanently) or **Quick Hands**
  (reload without giving up the move).
- Sergeant: **Snap Burst** (burst fire on the move — no bracing needed) or
  **Field Dressing** (**Q**: patch yourself up 3 HP, once per battle; costs the
  shot).
- Staff Sergeant: **Hustle** (**V**: give up the shot to move a second time —
  the extraction run on Outpost 7 is exactly what it is for) or **Flanker**
  (flanking shots hit 10% harder still).
- Master Sergeant: **Ranger** (+1 move *and* +1 range) or **Executioner**
  (+1 damage on flanking shots).

**Machinegunner — area denial:**

- Corporal: **Bipod** (overwatch answers with three rounds instead of two) or
  **Pack Mule** (two more rounds in the belt).
- Sergeant: **Wide Sweep** (suppression pins everything within three tiles
  instead of two) or **Grenadier** (the squad carries one more frag).
- Staff Sergeant: **Sentinel** (a wider overwatch arc) or **Locked Belts**
  (suppression pins for an extra turn).
- Master Sergeant: **Protective Fire** (unfired overwatch carries over to the
  next turn — taking any order breaks it) or **Walking Fire** (full auto after
  moving, at another −10% per round).

**Rodar Akai — the marksman-leader:**

- Corporal: **Called Shot** (**Q**: a whole-turn aimed round that ignores cover
  entirely — the roll is normal, the damage is never halved) or **Iron Will**
  (+2 HP).
- Sergeant: **Rally** (**T**: clear every pin within four tiles and steady the
  squad's aim +10% until their next turn; once per battle, costs the shot) or
  **Marksman** (shots past half range stop losing accuracy).
- Staff Sergeant: **Inspiration** (every soldier within four tiles of him
  shoots 5% better, always) or **Deep Pockets** (+2 rounds in the magazine).
- Master Sergeant: **One Shot** (Called Shot hits +2 harder) or **Untouchable**
  (the first killing blow each battle leaves him at 1 HP — the campaign-ending
  bullet, refused once).

Rank shows as chevrons beside a soldier's HP pips, and the info panel carries
their name, XP, and specialties. When a selected soldier owns an active
specialty, its button appears in the bottom row (**Q** and **T**).

**A failed mission counts for nothing.** XP earned in an attempt you lose is
rolled back when you retry, and so are the casualties — so you can never farm a
level, and a wipe costs you the attempt rather than the squad. That is also why
the campaign can never strand itself: losing every scout loses the mission, so
a mission you *win* always leaves at least one of them standing. Finishing the
campaign and playing again starts you with five fresh recruits.

## Controls

- **Left-click** — select a scout / move to a yellow-highlighted tile / shoot a
  red-highlighted enemy
- **Hover** — tile outline, movement path preview, dashed aim line on targets
- **W** or the **Watch** button — put the selected scout on overwatch, then
  **click the direction to watch**: a green cone previews exactly which tiles
  it will cover before you commit (consumes its attack; it fires automatically
  at the first goblin that steps into that arc)
- **F** or the **Face** button — turn the selected scout to look anywhere, for
  **free**. Costs no move and no attack, works even for a scout that has
  already acted, and can be repeated — it decides which way you face when the
  goblins take their turn.
- **B** or the **Burst** button — arm a two-round burst (highlights turn
  orange). Riflemen must be braced (unmoved); the gunner fires it from the hip.
- **A** or the **Auto** button — arm the machinegunner's four-round full auto
  (highlights turn amber). Requires a firing position.
- **S** or the **Suppress** button — arm the machinegunner's suppressive fire
  (highlights turn blue). Hovering a target draws the beaten zone and counts
  how many goblins it would pin.
- **V** — **Hustle** (scout specialty): give up this soldier's shot to move a
  second time.
- **Q / T** — the selected soldier's **active specialties** (Called Shot,
  Rally, Field Dressing), on the two ability buttons that appear when a
  soldier owns one. Called Shot aims like a throw: arm it, then click the
  enemy; the panel quotes the odds and the unhalved damage before you commit.
- **X** or the **Demolish** button — set charges on an objective the selected
  scout is standing on or beside. Costs the attack, needs no ammunition.
  Targets in reach get a bright rim, and a beacon floats over any still
  standing. **Ammo crates** go up in one charge; the **relay mast** takes two —
  the first buckles it, and it stands there leaning and sparking until somebody
  comes back to finish it.
- **G** or the **Frag** button — throw a fragmentation grenade, then **click
  the tile to land it on**: the five cells it will catch light up orange
  before you commit. Four tiles of throw range, needs line of sight.
- **C** or the **Smoke** button — throw a smoke grenade the same way (the
  preview turns pale). Lays a cloud that blinds both sides.
- **R** or the **Reload** button — refill a scout's magazine. Costs the move,
  not the shot, so a dry scout can reload and still fire once.
- **D** or the **Danger** button — toggle the danger overlay (red-hatched tiles
  the goblins could shoot next turn)
- **Tab** — cycle through scouts that can still act
- **Right-click / Esc** — cancel selection
- **E** or the **End Turn** button — end your turn
- **1 / 2 / 3** — jump to a level (also buttons on the result screen)
- A stat panel (bottom-left) shows the hovered or selected unit

## Rules

- Each unit may **move once and shoot once** per turn; shooting ends its
  activation (you can move-then-shoot, but not shoot-then-move).
- **Shots can miss.** Your soldiers are trained marksmen; the Thirst fires
  scavenged rifles badly. Hovering a target shows the exact odds. Flanking adds
  +10%, and shots past half your range lose 5% per extra tile — so the accuracy
  gap is the elite-squad edge, and closing distance sharpens it. Half cover
  costs the shooter damage only; full cover costs damage *and* accuracy, which
  is the whole reason to prefer a wall to a scrap pile.
- **Cover is where you stand, not what the bullet crosses.** A soldier is in
  cover from a direction when the tile next to them that way is something to
  get behind — so pressing up against a wall is a decision, and the ground
  between two walls is a route.
  - **Half cover** — rusted junk, sandbags, the Thirst's stacked ordnance, and
    fuel drums. Shots pass over it at **half damage**, both ways. You can shoot
    over it freely. The four behave identically and differ only in what they
    tell you about the ground: junk is cover nobody put there, sandbags are
    cover somebody *dug*, crates are the Thirst's, and a drum is all three right
    up until it goes off.
  - **Full cover** — rock, brick wall, building. **Half damage *and* 25% harder
    to hit**, and it blocks sight both ways.
  - **Barbed wire is not cover at all.** It is the one thing on the board that
    stops movement and *nothing else*: sight and fire cross it freely, and
    standing against it is standing in the open. A wire line divides ground
    without dividing fire, which is what makes the gate in it worth fighting
    over — see The Holding Pens.
  - One wall covers a **135° wedge**; an inside corner covers most of the
    field. **Facing still decides it** — caught with your back to a wall you
    are not behind it, so a flanking shot ignores cover entirely, and the free
    turn-to-face order (**F**) is how you take cover without moving.
  - Tiles you can reach that offer cover are dotted, and the tile under your
    cursor shows a bar on every protected edge — thick for a wall, thin for
    scrap. A soldier in cover hunkers down and wears shield bars by its HP.
- **You can lean around your own cover to shoot.** If a wall blocks your shot,
  you lean **past its edge** and take it at **-10% to hit**. That works at a
  corner or the end of a wall run, and *not* against the middle of an unbroken
  wall — the next section of the same wall is still in the way. Hovering a
  target shows `PEEK` when the shot is one.
- **Fuel drums are cover that can be turned into a weapon.** They behave like
  junk — you can't stand on them, you can shoot over them — until something
  sets one off. **Click a drum in range to put a round into it** (it lights up
  orange, and hovering shows the footprint and how many it would catch); a
  grenade blast will do it too. There is no hit roll: a drum is a big
  stationary object, so the decision is whether the shot is worth spending,
  not whether it lands. It goes up with a frag's force, **and its blast sets
  off the next drum along**, so a line of them is a fuse. Each drum burns
  exactly once, and they catch your own soldiers as readily as the Thirst.
- Cacti are decoration.
- Every mission opens on a **briefing** — situation, then orders — and a won
  mission closes on a **debrief** that points at the next one. A lost attempt
  gets no debrief; it is not part of the story.
- **The objective, not the body count, decides the level.** A banner under the
  turn indicator always says what the squad is there to do and how far along it
  is. Objectives complete **in order** — Outpost 7's extraction zone is inert
  until both ammo dumps are down, so you cannot simply walk off the map. Losing
  is the one thing that never changes: if the squad dies, you lose, whatever
  the objective said.
- **Extraction takes everyone who is still alive.** You pick the moment; a
  scout left behind means the zone is not full and the level does not end. If
  one dies on the way, the requirement shrinks with the squad — and anyone you
  freed on the way in counts too.
- **A rescue is over when you reach them, not when you free them.** Ending a
  move next to a prisoner cuts them loose; there is no action to spend and no
  button to remember. From there they are yours to walk out: slower than a
  soldier, unarmed, and untouchable — the Thirst never fires on them and a blast
  goes round them. Losing every soldier is still a wipe whether or not a
  prisoner is left standing.
- Winning advances to the next level; losing retries the current one.
- **Facing matters.** Every unit covers a 135° front arc, drawn as a wedge at
  its feet. Cover only protects against shots arriving inside that arc — a
  **flanking** shot (cyan aim line) ignores junk entirely and knocks the target
  off overwatch. Units face the way they last moved or shot, so sprinting
  across an enemy's front exposes your flank while advancing into it does not.
- **Overwatch** works for both sides: an overwatching unit stands with rifle
  raised (amber marker above its HP) and takes one free reaction shot at the
  first enemy that moves through **the arc it is watching** — except the
  machinegunner, who watches two tiles further than he can shoot and answers
  with a pair. The panel names both numbers while you aim the arc. Covered ground is
  hatched on the board: amber for goblin arcs, green for your own. Unfired
  overwatch expires at the owner's next turn.
- **Grenades** cost the attack, never the move, so a soldier can advance and
  then throw. They are **thrown at a tile rather than a unit**, cover the
  **3×3 square** around where they land, **always connect** (no hit roll), and
  **cover does not stop them** — lobbing onto the scrap the Thirst is hiding behind is
  the entire point. A blast will not reach through a wall.
  - **Frag** falls off from the centre — **3 down the cross, 2 on the four
    corners**:

    ```
    2 3 2
    3 3 3
    2 3 2
    ```

    A 3 kills a Conscript or a Light Runner outright and leaves a Well-hand,
    Runner or Marksman on 1; a corner 2 still finishes a Conscript but only wounds the
    rest. So the blast has an axis worth lining up, and the soft ring is
    exactly where a hurried throw catches your own squad. The preview draws
    the corners dimmer, and the panel shows the two numbers while you aim.
  - **Smoke** blocks line of sight through those cells — for **both sides**,
    including yours. It stands for the rest of the turn you threw it and the
    whole enemy turn that follows, then burns off. Throw it, walk the rest of
    the squad under it, and the Marksman gets nothing. A unit standing *in* its
    own cloud can still see out; only lines passing *through* it are cut.
  - **A frag catches your own scouts too**, and a 3×3 is wide enough that it
    will if you are careless. The preview shows exactly which tiles are in it,
    and that warning is the whole safety rail.
- **Suppression pins.** A pinned unit **cannot move at all** on its next
  activation, shoots 25% worse, and cannot go on overwatch. That is the point:
  suppressive fire deals no damage and never will, so what you are buying is a
  turn in which those goblins do not get to close, flank, or take ground. It
  catches everything within **two tiles** of the aim point — the panel counts
  how many before you fire, and the beaten zone is drawn on the board.
- **The gun keeps working.** Once it is down, the machinegunner holds his
  stance and fires volleys into that ground for the whole enemy turn, until the
  pin expires. The rounds are spent when you fire it; the sustained fire costs
  nothing further and resolves nothing — it is there so you can *see* what is
  holding them down.
- **Suppression** is the machinegunner's alone. A pinned unit shoots 25% worse
  and cannot go on overwatch until the turn after, and wears a steel chevron.
  Pinning two goblins costs you the damage you'd have dealt to one — that
  trade is the decision.
- **Magazines** are drawn as brass pips under a unit's HP. Your scouts carry
  one, and so does the Marksman; every other goblin has unlimited ammo. A burst
  costs two rounds, so bursting every chance you get means reloading — and
  giving up a move — every other turn. **Reloading costs the move, never the
  shot**, for both sides: a dry unit can reload and still fire, but cannot
  reposition that turn. Watch the Marksman's single pip to know whether he is
  about to shoot or about to work the bolt.
- Goblins chase, seek firing positions, avoid open ground lightly, and retreat
  to cover when wounded with no shot available; a goblin that holds position
  with no shot goes on overwatch to cover its lane.
- Win by destroying all goblins; lose if all scouts fall — the fallen stay on
  the battlefield where they dropped. Restart from the result screen.

## Running it

1. Install a **Godot 4.x standard build** (no .NET needed):
   `winget install GodotEngine.GodotEngine` / `brew install godot` /
   [godotengine.org/download](https://godotengine.org/download)
2. `git clone <this-repo>` and open `project.godot` in Godot (or `godot .`).
3. Press **F5**.

Headless smoke test (parse/boot check, exit code 0 = healthy). Godot exits 0
even when a scene fails to compile, so grep the output for `SCRIPT ERROR`
rather than trusting the exit code alone:

```
godot --headless --path . --quit-after 200                        # the garrison
godot --headless --path . --quit-after 200 -- --field             # the field camp
godot --headless --path . res://scenes/Battle.tscn --quit-after 200
godot --headless --path . res://scenes/Battle.tscn --quit-after 200 -- --level 2
```

## Project layout

```
scenes/
  Camp.tscn       # main scene: the real-time base camp between missions
  Battle.tscn     # a mission: board, camera, y-sorted entities, UI
  Unit.tscn       # one combatant (Node2D + Sprite2D)
scripts/
  Camp.gd         # camp: walk controller, follow camera, squad, fixtures
  CampData.gd     # the camp's map, fixture spots + boot validator
  Battle.gd       # controller: turn state machine, input, AI, campaign flow
  Board.gd        # grid: iso math, BFS, LOS/cover traces, tile/highlight drawing
  Unit.gd         # combatant: stats, animation state machine, damage, pips
  Levels.gd       # campaign data: maps, spawns, objectives, story + validator
  ObjectiveMarks.gd # beacons over objectives, above every unit and structure
  Game.gd         # autoload: campaign roster, ranks, perks, level progress
  Sfx.gd          # autoload: pooled sound playback
  HitFx.gd        # one-shot code-drawn muzzle flash / impact ring
tools/            # asset generators/measurers (SFX synth, muzzle scanner)
assets/audio/     # 11 generated retro SFX
assets/sprites/
  Scout/, Goblin/ # 8-direction idle/walk/aim/aim-idle/death sets + dead stances
  Environment/    # rocks, junk, cacti, sandbags, wire, walls, huts, props
assets/Tiles/     # desert floor tileset (10 x 128x60 diamond variants)
```

All sprites are pixel art generated in Pixel Lab: units have 8-direction idle
and ready-to-fire stances plus walk cycles, and face along their movement path
and toward their targets. The board, UI, and combat effects are code-drawn.
