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
- **Right-click / Esc** — cancel selection
- **E** or the **End Turn** button — end your turn

## Rules

- Each unit may **move once and shoot once** per turn; shooting ends its
  activation (you can move-then-shoot, but not shoot-then-move).
- **Rocks block movement *and* line of sight** — no shooting through cover, for
  either side.
- Goblins chase, seek firing positions, avoid open ground lightly, and retreat
  to cover when wounded with no shot available.
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
assets/sprites/   # hand-authored SVG placeholders (scout, goblin, rock)
```

All art is hand-rolled SVG and all UI/effects are code-drawn — intentionally
placeholder, meant to be replaced as the game grows.
