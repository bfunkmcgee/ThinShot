# ThinShot — unit sprite spec (v2)

What a new soldier has to ship so it drops into `Unit.gd` without new code
paths. Measured off the eleven units in `assets/sprites/`, and checked
against what the loader actually reads.

Companion to [ASSETS.md](ASSETS.md), which says *which* assets are worth making.
This says *what shape they have to be*.

> **v2 (2026-08-15, hi-res program).** New units and regenerations are
> authored on a **doubled canvas drawn at 1×** instead of a small canvas
> scaled 2×: same on-screen size, native pixels. Everything marked **[v2]**
> below is the hi-res contract; the legacy rows describe the shipped sets and
> stay valid until each unit is regenerated. `tools/validate_unit_sprites.py`
> enforces both tiers (hi-res sets are recognised by canvas and gate hard).

---

## 1. Style

| Property | Legacy (shipped) | **Hi-res [v2]** | Why it matters |
|---|---|---|---|
| Canvas | 60×60 (scouts, bolt goblin, hero, Rodar, civilian), 64×64 (Goblin, SMG, revolver), 56×56 (alt raider) | **120×120** replaces 60, **128×128** replaces 64, **112×112** replaces 56 | doubled canvas, drawn at 1× — the anchor maths stay put because `SPRITE_SPECS` flips per kind (§5) |
| Figure size | ~24–28 px wide × ~29–30 px tall | **~48–56 × ~58–60 px** | the canvas is mostly padding; the *figure* is the constant |
| Feet | ~14–15 px below canvas centre (12–16 accepted; alt raider anchors at 14) | **24–32 px below centre** (112-canvas: 22–30, anchor 28) | the `SPRITE_SPECS` offset assumes it — feet high or low and the unit floats or sinks |
| Scale in game | 2×, nearest-neighbour | **1× native** | this is the whole point of the program: room for detail that a doubled pixel destroys |
| Alpha | **binary — 0 or 255 only** | **same, no exceptions** | soft edges fringe against the sand; the validator hard-fails anti-aliased alpha at every tier |
| Ground shadow | none in the sprite | same | `Unit._draw()` draws a squashed ellipse under the feet; a baked shadow double-draws |
| Light | sun **upper left**, shading falls down-right | same | matches every prop, the floor sheet, and the code-drawn shadow offset |
| Outline | full near-black outline (`#00090B`, `#030109`) — 1 texel = 2 screen px | **1 px near-black outline** — at 1× the rim is a single screen px. **Judge criterion:** if a unit stops popping against the rimless floor at 100 % zoom, fall back to a **2 px outline** for that unit and log it | the outline is what keeps units legible on a busy desert board; at 1× it is also the thinnest line the style owns |
| Palette | tight; informational for shipped sets (Goblin 71 colours, Scout ships at ~387) | **≤128 colours per sprite** (validator warns above 128, fails above 160) | doubled canvas invites noise; the budget keeps the house style flat-shaded |
| Colour family | desert military: olive/khaki `#7D9352` `#61724B` `#97A272`, slate greys `#445153` `#4B4D54`, warm dust | same | scouts are tan/brown, Choir goblins green-skinned in darker rags |
| View | 3/4 top-down ("low top-down"), standing upright, for an isometric board | same | |

**The silhouette carries the identity.** At 30 px the face is four pixels; at
60 px it is sixteen, and the temptation is to spend them on faces. Don't. What
tells a bolt goblin from an SMG goblin is still the weapon shape and the
stance, read at a glance mid-fight. A new unit needs a silhouette that is
different *in outline* from all existing ones — hi-res buys cleaner cloth,
straps and weapon detail, not busier silhouettes.

---

## 2. The eight directions

Folder names, exactly, lowercase, hyphenated:

```
east  south-east  south  south-west  west  north-west  north  north-east
```

`Unit.DIR_NAMES` indexes these as compass sectors 0–7 (0 = E, going clockwise on
screen). All eight are required for every set — a missing direction loads as a
null texture, not a fallback.

---

## 3. The eleven sets

**Three static rotation sets** — one PNG per direction, named `<direction>.png`,
in a `rotations/` folder:

| Set | Used for |
|---|---|
| standing | fallback pose, and the source for `SCOUT_FRAMES`-style arrays |
| ready-to-fire | fallback aim pose |
| dead | **the corpse left on the board.** Not the last frame of the death animation — a separate drawing |

**Eight animation sets** — `<set>/<direction>/frame_%03d.png`, **9 frames**,
zero-padded, starting at `frame_000.png`. The loader counts up until a file is
missing, so a gap silently truncates the cycle.

| Set | Kind | Plays at | Notes |
|---|---|---|---|
| `standing_idle` | loop | 8 fps | the default state |
| `standing_idle_alt` | loop | 8 fps | **optional.** 14% chance after an idle cycle; an empty set is handled as "no variation" |
| `standing_idle_walk` | loop | 18 fps | |
| `standing_idle_to_readyToFire` | one-shot | 36 fps | **also played backwards** for lowering the weapon — so it must read correctly in reverse |
| `standing-readyToFire_idle` | loop | 8 fps | lives under the ready-to-fire stance folder |
| `standing_idle_to_dead` | one-shot | 14 fps | ends on a pose, then swaps to the static dead rotation |
| `standing_idle_damage` | one-shot | 18 fps | returns to idle *or* aim-idle, whichever it interrupted — so it must start and end on a neutral pose |
| `standing_idle_reload` | one-shot | 14 fps | same return rule |

**Total: 24 static PNGs + 8 × 8 × 9 = 576 animation frames.**

Two things you do *not* need to draw: **lowering the weapon** (the raise set
reversed) and **the dead idle** (a static rotation, not a cycle).

> `ASSETS.md` says "11 animation sets — 88 folders". That is the old count. The
> loader reads **8** sets = 64 folders, plus 3 rotation sets.

---

## 4. Folder layout to use

The legacy units are each laid out slightly differently — `Goblin_SMG`
puts its aim-idle under `standing-readyToFire_idle` with a hyphen, the alt
raider's is named after the sentence that generated it, the team lead uses
`Solider_aims_his_rif`, and Scout/Goblin keep their base state loose at the
unit root. Every one of those is a separate baked path constant in
`Unit.gd`, and `_load_only_anim()` exists purely to cope with the unstable one.

**[v2] The canonical layout below is a MANDATE for every regenerated unit,
not a suggestion.** A hi-res regen replaces its unit's folder in place; it
lands in this shape and none of the legacy special-casing applies (and the
unit's baked path constants in `Unit.gd` collapse to the standard three roots):

```
assets/sprites/<UnitName>/
  metadata.json                                        [v2: REQUIRED]
  <UnitName>/
    rotations/<direction>.png                          x8
    animations/standing_idle/<direction>/frame_%03d.png
    animations/standing_idle_alt/...
    animations/standing_idle_walk/...
    animations/standing_idle_to_readyToFire/...
    animations/standing_idle_damage/...
    animations/standing_idle_reload/...
    animations/standing_idle_to_dead/...
  ReadyToFire_Stance/
    rotations/<direction>.png                          x8
    animations/standing-readyToFire_idle/<direction>/frame_%03d.png
  Dead_stance/
    rotations/<direction>.png                          x8
```

This matches `Goblin_BoltRifle`, the cleanest of the legacy sets.

### metadata.json  [v2: REQUIRED]

Every unit folder carries a `metadata.json` in the PixelLab export format
(v3.1) — all eleven shipped units have one as of 2026-08-15 (seven exported,
four backfilled with pixel-verified ids). It is the provenance that makes a
regen reproducible. Required fields:

- `group_id` — the PixelLab character-group UUID
- `states[]` — one entry per state folder, each with:
  - `character` — `{id, name, prompt, size, template_id, directions, view,
    created_at}` as exported by PixelLab (the `id` is what a regen animates)
  - `folder` — the on-disk state folder (`""` for a root-level legacy layout)
  - `frames` — `rotations` map and `animations` map listing the shipped files
- `export_version`, `export_date`

Where the shipped art deviates from the cloud state (a dead pose assembled
from the death animation's last frame, a hand-fixed rotation), say so in a
`note` on that state instead of pointing at art that doesn't match. The
validator requires the file, with a character id on every state, before a
hi-res set may be promoted.

---

## 5. Wiring a finished unit in

1. Add a value to `Unit.Kind` — **append at the end.** Saves store the raw
   ordinal; inserting mid-enum quietly turns every saved soldier into
   somebody else.
2. Add a `<NAME>_ROOT` const and the 3 + 8 `static var` loader lines
   ([Unit.gd](scripts/Unit.gd)).
3. Dispatch the new kind in `setup()` and `_current_cycle()`.
4. **[v2] Give the kind its `SPRITE_SPECS` entry.** `Unit.SPRITE_SPECS` maps
   `Kind → {scale, offset}` (with a `"DEFAULT"` of `{(2,2), (0,-15)}`), and
   `setup()` applies it to the sprite — the old global `SPRITE_SCALE` /
   `SPRITE_OFFSET` consts are gone. A legacy-density unit rides `DEFAULT`
   (the 56-canvas alt raider keeps its `(0,-14)` entry). **When a unit's
   hi-res art lands, its entry flips to `{"scale": Vector2(1, 1), "offset":
   Vector2(0, -30)}`** (112-canvas: `(0, -28)`) — scale halves, offset
   doubles, same screen anchor, and nothing else in the unit's wiring moves.
5. Add the unit's aim stance to `tools/measure_muzzle.gd` — entries are
   `{label, canvas, scale, offset, path, unit_const}` and the tool computes
   `(p + offset − canvas/2) · scale`, so a hi-res entry is just
   `canvas: 120, scale: 1.0, offset: Vector2(0, -30)`. Run
   `godot --headless --path . -s tools/measure_muzzle.gd` and paste the
   printed `<NAME>_MUZZLE_OFFSETS` block in. Southern facings usually need
   hand correction — with the weapon pointed at the camera the scan lands on
   boots. The tool's closing **delta table** (measured vs the consts baked in
   `Unit.gd`) is where those corrections stay visible; after any regen, an
   unexpected delta on a non-southern facing means the art moved.
6. Validate before import: `python tools/validate_unit_sprites.py
   assets/sprites/<UnitName>` — a hi-res set gates on canvas, feet, alpha,
   palette, aim, flash, endpoints **and metadata.json**. A PASS writes the
   unit's `preview.html`.
7. Run `godot --headless --path . --import` to generate the `.import` files.
8. Give it stats and a spawn entry in `Levels.gd`.

For a **regeneration** of an existing unit, steps 1–3 and 8 are already done:
the work is the canonical folder layout (§4), the `SPRITE_SPECS` flip (step
4), re-measured muzzle offsets (step 5), and the validator + the
`make_char_viewer.py --compare <old>` page as the judge gate before the swap.
