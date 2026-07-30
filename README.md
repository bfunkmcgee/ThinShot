# ThinShot

A turn-based tactics thin slice built in **Godot 4** (2D isometric, GDScript,
placeholder art). One desert skirmish: the **Desert Scouts** against the
**Goblin Rust Choir**.

## The game

| | Team Lead | Machinegunner | Desert Scout | Chorister | Raider | Skirmisher | Novice | Cantor |
|---|---|---|---|---|---|---|---|---|
| Side | you | you | you | AI | AI | AI | AI | AI |
| Per battle | 1 | 1 | 3 | 3–4 | 1 | 1–2 | 3 | 1 |
| Weapon | battle rifle | belt-fed MG | carbine | scavenged rifle | submachine gun | submachine gun | revolver | bolt rifle |
| HP | 8 | 8 | 8 | 4 | 4 | 3 | **2** | 4 |
| Move | 4 | 3 | 5 | 4 | **5** | **6** | **5** | 3 |
| Attack range | **6** | 4 | 4 | 3 | **2** | **2** | 3 | **5** |
| Damage/round | **4** (2 in cover) | 2 (1) | 2 (1) | 2 (1) | 2 (1) | 2 (1) | 2 (1) | **4** (2) |
| Accuracy | 92% | 78% | 90% | 60% | 58% | 52% | **48%** | 70% |
| Magazine | 2 | **6** | 3 | ∞ | ∞ | ∞ | ∞ | **1** |
| Fire modes | single | **burst, full auto** | single, burst | single | **burst** | **burst** | single | single |
| Ability | — | **suppressive fire** | — | — | — | — | — | — |

The squad also carries **ordnance the Choir has nothing like** — two frags and
two smokes for the whole battle, pooled, thrown by whichever soldier is in the
right place. It is the answer to being outnumbered: grenades are the only
thing in the game that touches more than one cell, and the only damage that
does not roll to hit.

A five-soldier squad, each with a job:

- **Team Lead** — designated marksman. A battle rifle reaching half again as
  far as a carbine, dropping a healthy goblin in one hit. Paid for with a
  two-round magazine, a slower advance, and no burst.
- **Machinegunner** — area control. No semi-automatic setting at all: his
  lightest option is a two-round burst, and **full auto (A)** walks four rounds
  across a target at reduced accuracy. On top of those he has an ability no one
  else does — **suppressive fire (S)**: three rounds put down *around* a
  target rather than into it. No damage and no hit roll, but **everything
  within two tiles is pinned — it cannot move at all next turn**, shoots 25%
  worse, and cannot set overwatch. Six rounds in the belt, and he is the
  slowest soldier on the field.
- **Desert Scouts** ×3 — the fast, accurate line. Single shots, or a braced
  burst when they hold still.

The Choir is an armed rabble, and its roster shows it. **Choristers** hold
ground with scavenged rifles. **Raiders** carry submachine guns: almost no
reach at two tiles, but they move as fast as your riflemen and fire a burst the
moment they close, so the answer is to kill them on the way in rather than let
them arrive. **Skirmishers** are the same gun on a half-starved frame — the
fastest thing on the field at six tiles, so they arrive a full turn ahead of
their heavier twin and split your attention before the real push lands. Being
scrawny costs them: too light to hold the weapon down (52%), and thin enough
that three rounds through cover put one away instead of four. **Novices** are
the bottom of it — shirtless, handed whatever
sidearm was left over, and pushed out front as a screen. Two HP means a single
carbine round puts one down, and at 48% they mostly miss. They are dangerous
only because there are always more of them, and because every round you spend
on one is a round your Team Lead did not spend on something that matters.

One goblin in the rabble is not a joke. The **Cantor** is the Choir's
designated marksman: a bolt rifle reaching five tiles — further than anything
you carry except the Team Lead's — at 70% and four damage a round, which is
half a scout. He is the counter-sniper the campaign builds toward, and he
answers to exactly one weakness. **One round in the rifle**, and the bolt
worked by hand between shots, so he reloads after every single one. Reloading
costs the move, so the Cantor is **rooted for as long as he keeps firing**: he
will trade with you every turn, from the same tile, forever. Kill him with the
Team Lead (six tiles out-reaches him, and four damage drops him in one), break
line of sight and make him choose between shooting and repositioning, or eat a
scout's worth of damage crossing his lane.

A three-level desert campaign on 16×10 isometric maps. It is one story told in
three missions, and **the objectives are how it is told** — each mission opens
with a briefing and closes on a debrief that sets up the next:

1. A border contact. The Choir has crossed the wash for the first time, and
   command wants them off scout ground. You kill them because there is nothing
   else to be done yet — but the bodies are carrying sorted, tallied scrap, and
   nobody carries a tally into a raid.
2. You follow the route to the yard where the tithe is stacked. Killing
   collectors changes nothing; the tithe is what matters. Burn it — and find
   that it was never scrap. Machined ordnance, every crate struck with a depot
   mark of your own army's, off the maps for eleven years.
3. That depot is Outpost 7, and the Choir lives in it. Every round fired at you
   came out of your own magazines. You cannot hold the place, so you do not try:
   blow the magazines and walk the squad back out.

Which is why each map asks for something different:

1. **Dry Wash** — open skirmish. Kill every goblin. The teaching level.
2. **The Scrapline** — a raid. **Burn three tithe caches** spread corner to
   corner behind the barricades, and **drop the relay mast** in the corridor
   between them. A body count does not end this one; you can win with goblins
   still standing, and you can wipe them out and still not be finished.
3. **Outpost 7** — a raid with a way out. **Blow both magazines** at opposite
   ends of the compound, *then* **walk the whole squad back to the extraction
   zone** on the west edge. The zone stays shut until the charges go off, so
   the last stretch is a fighting withdrawal across ground you already crossed
   once — with whatever the Choir has left chasing you.

Your scouts are elite — tougher, faster, longer-ranged — but the Choir has
numbers and holds the ground.

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

Both camps are **real time and directly controlled** — you walk the Scout Team
Lead around with **WASD or the arrows**, and press **E** at anything worth
using:

- **Your squad** stand around the camp. Walk up to one to read their record —
  rank, XP, specialties — and if they earned a promotion on the last mission,
  **you choose their specialty here**, face to face, rather than on a screen
  that interrupts the debrief.
- **The stores tent** holds the squad's ordnance. Four pieces between them,
  split however you like: four frags and no smoke, one and three, or the 2/2
  the squad carried before there was anywhere to change it.
- **The briefing table** gives the next mission's orders and deploys you.
- **The assignment post** — garrison only — signs on replacements for anyone
  lost, green: no rank, no specialty, nothing the squad lost with them.

If the Team Lead falls, the senior surviving soldier takes over as the one you
walk around as — nobody is replaced until the operation is over, so somebody
always has to.

There is **one operation today**, *Dry Choir*, and it is the three missions
below. The structure is built for more: an operation is a name, a biome, and a
list of missions, so a second one is data. Biomes are plumbed and every value
currently resolves to the desert set, since there is one floor tilesheet in the
project — see `ASSETS.md`.

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
| Sergeant | 14 | +3 acc, +1 HP |
| Staff Sergeant | 26 | +3 acc, +1 HP, **choose a specialty** |
| Master Sergeant | 40 | +3 acc, +1 HP |

Rank gains are cumulative, and accuracy is capped at 95% — nobody ever becomes
a sure thing. Because of the cap the machinegunner (78%) gains far more from
rank than the team lead (92%), so the squad evens out as it matures.

**XP:** 3 a kill, 4 a demolished cache, 3 for walking off the map alive.

**Specialties**, chosen at Corporal and again at Staff Sergeant:

- **Marksman** — shots past half range stop losing accuracy. Turns a scout into
  something that can answer the Cantor.
- **Sprinter** — +1 tile of movement, permanently.
- **Sentinel** — overwatch covers 180° instead of 135°.
- **Hustle** — **V**: give up the shot to move a second time. The extraction
  run on Outpost 7 is exactly what it is for.

Rank shows as chevrons beside a soldier's HP pips, and the info panel carries
their name, XP, and specialties.

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
- **V** — **Hustle** (Staff Sergeant specialty only): give up this soldier's
  shot to move a second time.
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
- **Shots can miss.** Your scouts are trained marksmen; the Choir fires
  scavenged rifles badly. Hovering a target shows the exact odds. Flanking adds
  +10%, and shots past half your range lose 5% per extra tile — so the accuracy
  gap is the elite-squad edge, and closing distance sharpens it. Half cover
  costs the shooter damage only; full cover costs damage *and* accuracy, which
  is the whole reason to prefer a wall to a scrap pile.
- **Cover is where you stand, not what the bullet crosses.** A soldier is in
  cover from a direction when the tile next to them that way is something to
  get behind — so pressing up against a wall is a decision, and the ground
  between two walls is a route.
  - **Half cover** — rusted junk. Shots pass over it at **half damage**, both
    ways. You can shoot over it freely.
  - **Full cover** — rock, brick wall, building. **Half damage *and* 25% harder
    to hit**, and it blocks sight both ways.
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
  exactly once, and they catch your own scouts as readily as the Choir.
- Cacti are decoration.
- Every mission opens on a **briefing** — situation, then orders — and a won
  mission closes on a **debrief** that points at the next one. A lost attempt
  gets no debrief; it is not part of the story.
- **The objective, not the body count, decides the level.** A banner under the
  turn indicator always says what the squad is there to do and how far along it
  is. Objectives complete **in order** — Outpost 7's extraction zone is inert
  until both magazines are down, so you cannot simply walk off the map. Losing
  is the one thing that never changes: if the squad dies, you lose, whatever
  the objective said.
- **Extraction takes everyone who is still alive.** You pick the moment; a
  scout left behind means the zone is not full and the level does not end. If
  one dies on the way, the requirement shrinks with the squad.
- Winning advances to the next level; losing retries the current one.
- **Facing matters.** Every unit covers a 135° front arc, drawn as a wedge at
  its feet. Cover only protects against shots arriving inside that arc — a
  **flanking** shot (cyan aim line) ignores junk entirely and knocks the target
  off overwatch. Units face the way they last moved or shot, so sprinting
  across an enemy's front exposes your flank while advancing into it does not.
- **Overwatch** works for both sides: an overwatching unit stands with rifle
  raised (amber marker above its HP) and takes one free reaction shot at the
  first enemy that moves through **the arc it is watching**. Covered ground is
  hatched on the board: amber for goblin arcs, green for your own. Unfired
  overwatch expires at the owner's next turn.
- **Grenades** cost the attack, never the move, so a soldier can advance and
  then throw. They are **thrown at a tile rather than a unit**, cover the
  **3×3 square** around where they land, **always connect** (no hit roll), and
  **cover does not stop them** — lobbing onto the scrap the Choir is hiding behind is
  the entire point. A blast will not reach through a wall.
  - **Frag** falls off from the centre — **3 down the cross, 2 on the four
    corners**:

    ```
    2 3 2
    3 3 3
    2 3 2
    ```

    A 3 kills a Novice or a Skirmisher outright and leaves a Chorister, Raider
    or Cantor on 1; a corner 2 still finishes a Novice but only wounds the
    rest. So the blast has an axis worth lining up, and the soft ring is
    exactly where a hurried throw catches your own squad. The preview draws
    the corners dimmer, and the panel shows the two numbers while you aim.
  - **Smoke** blocks line of sight through those cells — for **both sides**,
    including yours. It stands for the rest of the turn you threw it and the
    whole enemy turn that follows, then burns off. Throw it, walk the rest of
    the squad under it, and the Cantor gets nothing. A unit standing *in* its
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
  one, and so does the Cantor; every other goblin has unlimited ammo. A burst
  costs two rounds, so bursting every chance you get means reloading — and
  giving up a move — every other turn. **Reloading costs the move, never the
  shot**, for both sides: a dry unit can reload and still fire, but cannot
  reposition that turn. Watch the Cantor's single pip to know whether he is
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
  Environment/    # rocks, rusted junk, cacti, brick walls, huts, tent, fortress
assets/Tiles/     # desert floor tileset (10 x 128x60 diamond variants)
```

All sprites are pixel art generated in Pixel Lab: units have 8-direction idle
and ready-to-fire stances plus walk cycles, and face along their movement path
and toward their targets. The board, UI, and combat effects are code-drawn.
