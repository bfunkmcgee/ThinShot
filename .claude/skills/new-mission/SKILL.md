---
name: new-mission
description: Author a new SANDLINE mission — brief, draft JSON in staging, lint and preview until it reads, install into Levels.gd, verify in engine
---

# /new-mission

Invocation: `/new-mission mission 8: ambush in a slot canyon`

The loop: brief → draft → lint → preview → read → iterate → install → verify →
screenshot → suggest a commit. Draft in `artgen/staging/`, never straight into
`scripts/Levels.gd` — the lint and the preview are cheaper than a broken ship.

## 1. Brief

Read `scripts/Levels.gd` first — a shipped entry IS the schema and the house
literal style. Settle with the user: name, fiction / briefing / orders / debrief,
objective kinds, floor/biome, and where it lands in the campaign. The arc is
carried by the objective kinds; a new mission should say something the existing
seven don't.

## 2. Draft

Write `artgen/staging/<mission>/draft.json`. Same keys as a Levels.gd entry,
JSON-encoded: cells as `[x, y]`, `size` as `[w, h]` (defaults to the map's own
dimensions), `floor_inset` as `{"floor": "<name>", "rect": [x, y, w, h]}`.

- `map` — array of row strings, chars from `Levels.LEGAL_CHARS` `.#Wjpdsc=`:
  - `.` open sand · `#` rock (blocks move + LOS) · `W` mud-brick wall (blocks
    move + LOS) · `p` plant (pure decoration, walkable)
  - half cover (unwalkable, shots pass at half damage): `j` rusted junk ·
    `s` sandbags (somebody dug in) · `c` Thirst ordnance (keep OFF any map with a
    `destroy` objective) · `d` fuel drum (half cover that detonates in a blast
    and chains to the next drum)
  - `=` barbed wire: stops movement and NOTHING else — sight and fire cross it
- spawns — `scout_spawns`, `lead_spawns`, `gunner_spawns`; `goblin_spawns`,
  `smg_spawns`, `smg_alt_spawns`, `novice_spawns`, `bolt_spawns`;
  `prisoner_spawns`
- `structures` — `[{"kind": "...", "anchor": [x, y], "size": [w, h]}]`
  (footprints overlay their cells as full blockers)
- `objectives` — ordered, completed in order:
  `[{"kind": "eliminate"|"destroy"|"rescue"|"extract", "label": "...",
  "prop": "...", "cells": [[x, y], ...]}]`
- optional: `zone_seed` / `shade_seed` / `prop_seed` (ints), `zone_thresholds`
  `[a, b]`, `zone_map` (row strings of `012.` — explicit zone painting; `.` =
  fall back to noise), `lint` overrides (`cover_min` / `cover_max` / `lane_max`
  / `safe_dist`), `floor`, `floor_inset`

## 3. Lint until PASS

```powershell
powershell tools/godot.ps1 --headless --path . -s tools/check_level.gd -- --draft artgen/staging/<mission>/draft.json
```

Eight checks, run against the real Board: 1 schema, 2 reachability (every
objective/prisoner/extraction cell reachable from squad spawns), 3 spawn safety
(no enemy LOS to a squad spawn at close range), 4 cover density, 5 sightline
cap, 6 enclosures (no sealed pockets holding objectives), 7 drum-chain warning,
8 zones. Calibrated bands: `COVER_MIN 0.08`, `COVER_MAX 0.66`, `LANE_MAX 12`,
`SAFE_DIST 5`. If the design genuinely needs to sit outside a band, override
per-level via the `"lint"` key with a comment saying why — never loosen the
constants themselves.

## 4. Preview and read it

```powershell
powershell tools/godot.ps1 --path . -s tools/render_board_preview.gd -- --draft artgen/staging/<mission>/draft.json --out artgen/staging/<mission>/preview
```

Windowed (~2 s flash; headless cannot render). Read `board_full.png` and the
quadrants against:

- **Readability** — does the layout read from the briefing alone? Could a player
  point at the map feature each sentence of the orders refers to?
- **Lanes** — 2+ viable approach routes to every objective; one route is a
  corridor, not a decision.
- **Cover shape** — cover clumps where the fights should happen, thins where
  movement should feel exposed. Even scatter reads as noise.

## 5. Iterate

Loop stages 2–4 until the lint passes AND the picture reads. The picture wins
arguments the lint can't have.

## 6. Install

Append the entry to `LEVELS` in `scripts/Levels.gd`, matching its exact literal
style — read a shipped entry again first: tab indentation, `Vector2i(x, y)`
cells, `Rect2i(...)` insets, a design comment above the entry explaining the
shape, briefing strings with `\n\n` paragraph breaks, trailing commas.

## 7. Verify the shipped entry

```powershell
powershell tools/godot.ps1 --headless --path . -s tools/check_level.gd -- --level <N>
powershell tools/godot.ps1 --headless --path . -s tools/check_cover_rules.gd
powershell tools/godot.ps1 --headless --path . res://scenes/Battle.tscn --quit-after 200 -- --level <N>
```

`--level` is 1-based everywhere. Grep the smoke run's output for `SCRIPT ERROR`
— a clean exit code is not enough, Godot script errors don't fail the process.

## 8. Screenshot the shipped level

```powershell
powershell tools/godot.ps1 --path . -- --level <N> --screenshot artgen/staging/<mission>/shipped.png
```

Windowed. Read it — the last chance to catch what the preview couldn't: real
props, real haze, the briefing banner over the actual board.

## 9. Suggest the commit

Suggest — do not run — a commit of `scripts/Levels.gd` (plus any tuned lint
override) with a message in the repo's voice: what the mission is and what the
layout does, not "add level 8". The user commits.
