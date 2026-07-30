# ThinShot — unit sprite spec

What a new soldier has to ship so it drops into `Unit.gd` without new code
paths. Measured off the eight units already in `assets/sprites/`, and checked
against what the loader actually reads.

Companion to [ASSETS.md](ASSETS.md), which says *which* assets are worth making.
This says *what shape they have to be*.

---

## 1. Style

| Property | Value | Why it matters |
|---|---|---|
| Canvas | **64×64** (Goblin, Goblin_SMG, Goblin_revolver). Scouts and the bolt goblin are 60×60; the alt raider is 56×56 | 60 and 64 both work on the shared anchor. **56 does not** — it needed its own `SPRITE_OFFSET_56` |
| Figure size | ~24–28 px wide × ~29–30 px tall inside that canvas | The canvas is mostly padding; the *figure* is the constant |
| Feet | land **~14–15 px below canvas centre** | `SPRITE_OFFSET = (0, -15)` assumes this. Boots higher or lower and the unit floats or sinks |
| Scale in game | **2×**, nearest-neighbour, so a ~30 px figure reads ~60 px on screen | Every pixel is two. There is no room for detail that only survives at 1× |
| Alpha | **binary — 0 or 255 only.** Verified: both sampled sprites have exactly two alpha values | Soft/anti-aliased edges will fringe against the sand at 2× |
| Ground shadow | **none in the sprite.** `Unit._draw()` draws a squashed ellipse under the feet | A baked shadow double-draws |
| Light | sun **upper left**, shading falls down-right | Matches every prop, the floor sheet, and the code-drawn shadow offset |
| Outline | full near-black outline around the silhouette (`#00090B`, `#030109`) | This is what keeps units legible on a busy desert board |
| Palette | tight. The Goblin sprite uses **71 distinct colours**; the Scout is noisier at ~335 | Aim for the Goblin end — under ~80 colours reads cleaner |
| Colour family | desert military: olive/khaki `#7D9352` `#61724B` `#97A272`, slate greys `#445153` `#4B4D54`, warm dust | Scouts are tan/brown, Choir goblins are green-skinned in darker rags |
| View | 3/4 top-down, standing upright, drawn for an isometric board | |

**The silhouette carries the identity.** At 30 px the face is four pixels — what
tells a bolt goblin from an SMG goblin is the weapon shape and the stance. A new
unit needs a silhouette that is different *in outline* from all eight existing
ones, or players will not tell it apart mid-fight.

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

The eight existing units are each laid out slightly differently — `Goblin_SMG`
puts its aim-idle under `standing-readyToFire_idle` with a hyphen, the alt
raider's is named after the sentence that generated it, the team lead uses
`Solider_aims_his_rif`. Every one of those is a separate baked path constant in
`Unit.gd`, and `_load_only_anim()` exists purely to cope with the unstable one.

**For a new unit, use this and none of that applies:**

```
assets/sprites/<UnitName>/
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

This matches `Goblin_BoltRifle`, the cleanest of the eight.

---

## 5. Wiring a finished unit in

1. Add a value to `Unit.Kind`.
2. Add a `<NAME>_ROOT` const and the 3 + 8 `static var` loader lines
   ([Unit.gd:19-257](scripts/Unit.gd#L19-L257)).
3. Dispatch the new kind in `setup()` and `_current_cycle()`.
4. Add the unit's aim rotations to `tools/measure_muzzle.gd`, run
   `godot --headless --path . -s tools/measure_muzzle.gd`, and paste the printed
   `<NAME>_MUZZLE_OFFSETS` block in. Southern facings usually need hand
   correction — with the weapon pointed at the camera the scan lands on boots.
5. Run `godot --headless --path . --import` to generate the `.import` files.
6. Give it stats and a spawn entry in `Levels.gd`.
