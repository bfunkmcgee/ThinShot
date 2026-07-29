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
  target rather than into it. No damage and no hit roll, but it **pins that
  goblin and every goblin beside it**. Six rounds in the belt, and he is the
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

A three-level desert campaign on 16×10 isometric maps, and **each one asks for
something different**:

1. **Dry Wash** — open skirmish. Kill every goblin. The teaching level.
2. **The Scrapline** — a raid. **Burn three tithe caches** spread corner to
   corner behind the barricades. A body count does not end this one; you can
   win with goblins still standing, and you can wipe them out and still not be
   finished.
3. **Outpost 7** — a raid with a way out. **Blow both magazines** at opposite
   ends of the compound, *then* **walk the whole squad back to the extraction
   zone** on the west edge. The zone stays shut until the charges go off, so
   the last stretch is a fighting withdrawal across ground you already crossed
   once — with whatever the Choir has left chasing you.

Your scouts are elite — tougher, faster, longer-ranged — but the Choir has
numbers and holds the ground.

## The squad

The five soldiers are **named, and they are the same five from one mission to
the next**. They earn ranks, they specialise, and **when one falls they are
gone** — a raw recruit fills the slot next mission and everything that soldier
had earned goes with them.

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
level, and a wipe costs you the attempt rather than the squad. Finishing the
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
  (highlights turn blue). Deals no damage; pins the target and its neighbours.
- **V** — **Hustle** (Staff Sergeant specialty only): give up this soldier's
  shot to move a second time.
- **X** or the **Demolish** button — set charges on a tithe cache the selected
  scout is standing on or beside (the orange piles). Costs the attack, needs
  no ammunition. Caches in reach get a bright rim.
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
  gap is the elite-squad edge, and closing distance sharpens it. Cover does
  *not* reduce accuracy; it halves damage, which keeps the two rules separate.
- **Rocks, brick walls, and buildings block movement *and* line of sight.**
- **Rusted junk is partial cover**: you can't stand on it, but shots pass over
  it at **half damage** (the aim line turns amber). Cacti are decoration.
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
  then throw. They are **thrown at a tile rather than a unit**, land on that
  tile plus its four neighbours, **always connect** (no hit roll), and **cover
  does not stop them** — lobbing onto the scrap the Choir is hiding behind is
  the entire point. A blast will not reach through a wall.
  - **Frag** deals 3 to everything in the footprint. That kills a Novice or a
    Skirmisher outright and leaves a Chorister, Raider, or Cantor on 1.
  - **Smoke** blocks line of sight through those cells — for **both sides**,
    including yours. It stands for the rest of the turn you threw it and the
    whole enemy turn that follows, then burns off. Throw it, walk the rest of
    the squad under it, and the Cantor gets nothing. A unit standing *in* its
    own cloud can still see out; only lines passing *through* it are cut.
  - **A frag catches your own scouts too.** The preview shows exactly which
    tiles are in it, and that warning is the whole safety rail.
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
godot --headless --path . --quit-after 200
godot --headless --path . --quit-after 200 -- --level 2   # boot straight into a level
```

## Project layout

```
scenes/
  Battle.tscn     # main scene: board, camera, y-sorted entities, UI
  Unit.tscn       # one combatant (Node2D + Sprite2D)
scripts/
  Battle.gd       # controller: turn state machine, input, AI, campaign flow
  Board.gd        # grid: iso math, BFS, LOS/cover traces, tile/highlight drawing
  Unit.gd         # combatant: stats, animation state machine, damage, pips
  Levels.gd       # campaign data: maps, spawns, structures + boot validator
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
