# ThinShot

A turn-based tactics thin slice built in **Godot 4** (2D isometric, GDScript,
placeholder art). One desert skirmish: the **Desert Scouts** against the
**Goblin Rust Choir**.

## The game

| | Desert Scouts (you) | Rust Choir goblins (AI) |
|---|---|---|
| Units | 3 | 4 |
| HP | 3 | 2 |
| Move | 4 tiles | 3 tiles |
| Attack range | 4 | 3 |
| Damage | 1 | 1 |

A 12×8 isometric grid strewn with rocks. You outrange them; they outnumber you.

## Controls

- **Left-click** — select a scout / move to a yellow-highlighted tile / shoot a
  red-highlighted enemy
- **Hover** — tile outline, movement path preview, dashed aim line on targets
- **W** or the **Overwatch** button — put the selected scout on overwatch
  (consumes its attack; it fires automatically at the first goblin that moves
  through its line of sight on the enemy turn)
- **D** or the **Danger** button — toggle the danger overlay (red-hatched tiles
  the goblins could shoot next turn)
- **Tab** — cycle through scouts that can still act
- **Right-click / Esc** — cancel selection
- **E** or the **End Turn** button — end your turn
- A stat panel (bottom-left) shows the hovered or selected unit

## Rules

- Each unit may **move once and shoot once** per turn; shooting ends its
  activation (you can move-then-shoot, but not shoot-then-move).
- **Rocks block movement *and* line of sight** — no shooting through cover, for
  either side.
- **Overwatch** works for both sides: an overwatching unit stands with rifle
  raised (amber marker above its HP) and takes one free reaction shot at the
  first enemy that moves through its range and line of sight. Unfired
  overwatch expires at the owner's next turn.
- Goblins chase, seek firing positions, avoid open ground lightly, and retreat
  to cover when wounded with no shot available; a goblin that holds position
  with no shot goes on overwatch to cover its lane.
- Win by destroying all goblins; lose if all scouts fall. Restart from the
  result screen.

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
  Battle.tscn     # main scene: board, y-sorted entities, UI
  Unit.tscn       # one combatant (Node2D + Sprite2D)
scripts/
  Battle.gd       # controller: turn state machine, input, AI, win/lose
  Board.gd        # grid: iso math, BFS pathfinding, LOS, tile/highlight drawing
  Unit.gd         # combatant: stats, damage, HP pips, damage numbers
  HitFx.gd        # one-shot code-drawn muzzle flash / impact ring
assets/sprites/
  Scout/          # 8-direction idle frames + aim stance + 9-frame walk cycles
  Goblin/         # same set for the goblins
  Environment/    # desert rocks (3 variants)
assets/Tiles/     # desert floor tileset (10 x 128x60 diamond variants)
```

All sprites are pixel art generated in Pixel Lab: units have 8-direction idle
and ready-to-fire stances plus walk cycles, and face along their movement path
and toward their targets. The board, UI, and combat effects are code-drawn.
