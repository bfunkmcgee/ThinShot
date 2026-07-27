# ThinShot

A turn-based tactics thin slice built in **Godot 4** (2D isometric, GDScript,
placeholder art). One desert skirmish: the **Desert Scouts** against the
**Goblin Rust Choir**.

## The game

| | Scout Team Lead | Desert Scout | Rust Choir goblin |
|---|---|---|---|
| Per squad | 1 | 2 | 4–5 (AI) |
| Weapon | battle rifle | carbine | scavenged rifle |
| HP | 8 | 8 | 4 |
| Move | 4 tiles | 5 tiles | 4 tiles |
| Attack range | **6** | 4 | 3 |
| Damage | **4** (2 through cover) | 2 (1 through cover) | 2 (1 through cover) |
| Accuracy | 92% | 90% | 60% |
| Burst fire | no | yes | no |

Your **Team Lead** is the squad's designated marksman: a battle rifle that
reaches half again as far as a carbine and drops a healthy goblin in a single
hit, paid for with a two-round magazine, a slower advance, and no burst.

A three-level desert campaign on 16×10 isometric maps: **Dry Wash** (open
skirmish), **The Scrapline** (the Choir's junkyard), and **Outpost 7** (fortress
assault). Your scouts are elite — tougher, faster, longer-ranged — but the
Choir has numbers and holds the ground.

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
- **B** or the **Burst** button — arm burst fire for a scout that hasn't moved
  (highlights turn orange); click a target to fire a braced two-round burst
  (2×2 damage, each round halved by cover). Moving disarms it.
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
- **Burst fire** is scout-only: a scout that stays put may spend its attack on
  a two-round burst — enough to drop a full-health goblin in one action, at
  the price of not repositioning.
- **Scouts carry a 3-round magazine** (brass pips under their HP); goblins have
  unlimited ammo. A burst costs two rounds, so bursting every chance you get
  means reloading — and giving up a move — every other turn.
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

Headless smoke test (parse/boot check, exit code 0 = healthy):

```
godot --headless --path . --quit
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
  Game.gd         # autoload: current level across scene reloads
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
