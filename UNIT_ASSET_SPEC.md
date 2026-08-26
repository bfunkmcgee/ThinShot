# SANDLINE — unit sprite spec (v2)

What a new soldier has to ship so it drops into `Unit.gd` without new code
paths. Measured off the sixteen units in `assets/sprites/` (everything there
except `Environment/`), and checked against what the loader actually reads.

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
| Canvas | 60×60 for twelve of the sixteen (the three Scout sets, the five Kestrel specialists, `Hero_MachineGunner`, `Rodar_Akai`, bolt goblin, civilian), 64×64 (Goblin, SMG, revolver), 56×56 (alt raider) | **120×120** replaces 60, **128×128** replaces 64, **112×112** replaces 56 | doubled canvas, drawn at 1× — the anchor maths stay put because `SPRITE_SPECS` flips per kind (§5) |
| Figure size | ~24–28 px wide × ~29–30 px tall | **~48–56 × ~58–60 px** | the canvas is mostly padding; the *figure* is the constant |
| Feet | ~14–15 px below canvas centre (12–16 accepted; alt raider anchors at 14) | **24–32 px below centre** (112-canvas: 22–30, anchor 28) | the `SPRITE_SPECS` offset assumes it — feet high or low and the unit floats or sinks |
| Scale in game | 2×, nearest-neighbour | **1× native** | this is the whole point of the program: room for detail that a doubled pixel destroys |
| Alpha | **binary — 0 or 255 only** | **same, no exceptions** | soft edges fringe against the sand; the validator hard-fails anti-aliased alpha at every tier |
| Ground shadow | none in the sprite | same | `Unit._draw()` draws a squashed ellipse under the feet; a baked shadow double-draws |
| Light | sun **upper left**, shading falls down-right | same | matches every prop, the floor sheet, and the code-drawn shadow offset |
| Outline | full near-black outline (`#00090B`, `#030109`) — 1 texel = 2 screen px | **1 px near-black outline** — at 1× the rim is a single screen px. **Judge criterion:** if a unit stops popping against the rimless floor at 100 % zoom, fall back to a **2 px outline** for that unit and log it | the outline is what keeps units legible on a busy desert board; at 1× it is also the thinnest line the style owns |
| Palette | tight; informational for shipped sets (Goblin 71 colours, Scout ships at ~387) | **≤128 colours per sprite** (validator warns above 128, fails above 160) | doubled canvas invites noise; the budget keeps the house style flat-shaded |
| Colour family | desert military: olive/khaki `#7D9352` `#61724B` `#97A272`, slate greys `#445153` `#4B4D54`, warm dust | same | Kestrels are tan/brown, Thirst goblins green-skinned in worn work clothes |
| View | 3/4 top-down ("low top-down"), standing upright, for an isometric board | same | |

> **Naming trap — name the kind, not "the hero".** The folder
> `Hero_MachineGunner/` is **Brukk Meshan's** art: `Kind.MACHINEGUNNER`, raw
> ordinal 2. `Kind.HERO` is ordinal 9 and it is **Rodar Akai**, whose art is
> `Rodar_Akai/`. The folder name is historical: it is the PixelLab
> "Hero_bandana" group, the name its `metadata.json` still carries. So say
> which `Kind` you mean — "the hero's sprite" names two different folders.

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
(v3.1) — all sixteen shipped units have one. The eleven that existed on
2026-08-15 were brought up to it then (seven exported, four backfilled with
pixel-verified ids); the five Kestrel specialists shipped with theirs. It is
the provenance that makes a regen reproducible. Required fields:

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
5. **Repair the five defects Pixel Lab reliably ships.** Each has a tool, each
   writes a `note` on the affected state in `metadata.json` (§4), and all five
   are quiet — the folder is complete and the frame counts are right in every
   case. Run them before measuring anything, because the first three change the
   pixels the measurement reads:

   | Tool | Defect | Repair |
   |---|---|---|
   | `recanvas_frames.py <unit> <canvas> --fix` | A job returns on the wrong canvas (a backfill loses the request's size). One direction draws bigger and sits off its diamond. | Centred crop/pad. Refuses if it would clip the figure. |
   | `check_dead_stance.py <unit> --all` | `create_character_state` leaves the corpse standing in some facings. | All eight rotations taken from `standing_idle_to_dead`'s last frame — which also makes the death hand-off exact. |
   | `seal_raise_transition.py <unit> --fix` | `standing_idle_to_readyToFire` does not land on the aim rotation, so the figure snaps when the raise ends. | The animation's last frame becomes the rotation. The rotation does **not** move: the aim-idle starts on it and the muzzle offsets are measured off it. |
   | `fix_idle_flash.py <unit> --fix` | The aim-idle is drawn firing, so the unit shoots forever while standing. | Each lit frame is replaced by its opposite number across the loop. A direction lit in more than half its frames must be regenerated. |
   | `fix_idle_flash.py <unit> --fix` (third detector) | The aim-idle throws **detached ejecta** — spent brass or an ejection puff, a lump of pixels clear of the body that appears for part of the loop and is gone by the end of it. It says what a flash says and is too dim for either flash rule to see: Brukk Meshan's north-west carried a 35-pixel object beside him for five frames of nine. | Deleted, not grafted — a component touching no part of the soldier cannot take a pixel of him with it. Narrow on purpose: aim-idle only, and only lumps that blink, since a dropped weapon separating from the body is most of a death animation. |

6. Add the unit's aim stance to `tools/measure_muzzle.gd` — entries are
   `{label, canvas, scale, offset, path, unit_const}` and the tool computes
   `(p + offset − canvas/2) · scale`, so a hi-res entry is just
   `canvas: 120, scale: 1.0, offset: Vector2(0, -30)`. Run
   `godot --headless --path . -s tools/measure_muzzle.gd` and paste the
   printed `<NAME>_MUZZLE_OFFSETS` block in.

   The plain scan takes the opaque pixel furthest along the facing, which on a
   tall figure can be the **crown of the head** — so the tool prints a second
   **band** opinion, restricted to the shoulder-to-hip rows where a carried
   weapon is, and where the two disagree the band is nearly always what to
   bake. If check [3] below reports the south or north aim pose drawn
   *levelled* to a flank instead of foreshortened, say so in the entry's
   `levelled` key (`{"south": LEVELLED_RIGHT}`) — the muzzle really is out
   there, and the offset must follow the art so the flash leaves the barrel
   the player can see. The tool's closing **delta table** compares against
   what it recommends per facing, so `(all 8 facings match)` is the goal and
   any delta is a hand-correction or real drift.

   **When a unit's art is *replaced*, repoint that unit's existing entry in the
   same commit.** The retired folder usually stays on disk — kept for another
   use, or just not deleted — so its `path` still resolves, and left alone the
   tool goes on measuring a sheet the game no longer draws and reports
   `(all 8 facings match)` against a table that has stopped describing anything
   on screen. Nothing fails; the numbers are simply about a different soldier.
   Brukk Meshan's `GUNNER` entry had to be moved to
   `Hero_MachineGunner/ReadyToFire_Stance/` by hand for exactly that reason.
7. Validate before import: `python tools/validate_unit_sprites.py
   assets/sprites/<UnitName>` — a hi-res set gates on canvas, feet, alpha,
   palette, aim, flash, endpoints **and metadata.json**. A PASS writes the
   unit's `preview.html`. Note that its check [5] flash rule is *relative to
   each cycle's median*, so it catches a flash in one or two frames and is
   blind to one in eight of nine; `fix_idle_flash.py` is the stricter of the
   two and both are worth running.
8. Run `godot --headless --path . --import` to generate the `.import` files.
9. **Prove the wiring loaded, and prove it will load off this machine.** Two
   checks, and neither can do the other's job:

   `godot --headless --path . -s tools/check_unit_art.gd` walks every
   `Unit.Kind` and asserts all 11 frame sets actually filled. It exists because
   **the loaders fail silently**: `_load_dir_frames` returns an empty array for
   a path that is not there, `_load_rotation_frames` appends nulls, neither
   pushes an error, and `_update_sprite` falls back to a static pose. A mistyped
   root leaves the unit standing still with nothing in the console, and no
   gameplay test looks at a frame — the whole suite prints PASS with a kind's
   art entirely empty.

   `python tools/check_res_case.py` compares every `res://` string in
   `scripts/` against the disk's own **casing**, constants resolved, so
   `MG_BASE + "/animations/standing_idle"` is checked as the full path a
   player's machine will ask for. This is the bug the first check structurally
   cannot see: Windows resolves `Dead_Stance/` to `Dead_stance/` at the OS
   level, so a mis-cased path loads in the editor, loads in every harness, and
   loads in `check_unit_art.gd` — it is missing only from an exported PCK,
   where the path is a case-sensitive key. A wrong case is invisible on the
   machine the game is developed on and fatal in the build that ships.
10. **Look at it.** `powershell tools/godot.ps1 --path . -s
    tools/render_unit_check.gd -- --kinds <NAME> --zoom 3` stands the unit up
    through the real `setup()` path in all eight facings and puts a dot on
    `muzzle_point()`. Measurements are made on PNGs; this is where you find out
    whether the number still lands on the barrel after Godot applies
    `SPRITE_SPECS`.
11. Give it stats and a spawn entry in `Levels.gd`.

For a **regeneration** of an existing unit, steps 1–4 and 11 are already done:
the work is the canonical folder layout (§4), the `SPRITE_SPECS` flip (step
4), the repair pass (step 5), re-measured muzzle offsets off the new folder
(step 6), the two load checks (step 9), and the validator + the
`make_char_viewer.py --compare <old>` page as the judge gate before the swap.

---

## 6. Getting the base + aimed stance out of PixelLab  [proven 2026-08-23]

The process that produced the goblin machine-gunner's approved pair in six
generations flat, distilled from the brute loop before it. It generalises to
any unit whose ready stance raises a long weapon.

**Base figure — the canvas is the scale dial, not the prompt.**
`create_character` (pro mode, `style_character_id` = the family's shipped base)
fills ~60–65 % of whatever canvas it gets, and scale adjectives lose to that
geometry every time. To land a 29–31 px goblin-family figure, generate on a
**48 px canvas** and pad to the family's 64×64 offline afterwards (pure
translation: centre horizontally, drop the feet row onto the family feet line,
assert the opaque-pixel count unchanged). Judge the base against the whole
faction lineup, not just its own compass — "visually distinct" means a
silhouette (headwear, pack, weapon shape) no sibling unit owns.

**Aimed stance — no single pass gets all eight; plan the composite.**
An aimed stance must point the muzzle wherever the unit faces, which means the
weapon foreshortens to nearly nothing at south and shows full profile at
east/west. The generator cannot do both from one instruction:

1. `create_character_state`, **mechanical hold language** ("stock pressed into
   the shoulder, one hand under the barrel, muzzle in the facing direction")
   → the seven side/diagonal/rear frames come out right; **south aims
   sideways** instead of at the camera.
2. `create_character_state`, **rendered-result language** ("barrel points
   directly at the camera, heavily foreshortened, only the dark muzzle end
   visible as a small circle at the chest, head tucked sighting at the
   viewer") → **south is right**; every other frame now also points at the
   camera.
3. The same applies to **north**: the mechanical-hold pass renders the rear
   view holding the gun in side profile, which reads as "not aiming north".
   A third pass with rendered-result language for the away axis ("seen from
   behind, the barrel heavily foreshortened, hidden beyond his body") fixes
   it — accept that the weapon may vanish entirely from behind if the player
   judges it readable (the MG goblin shipped that way, user-approved).
4. **Composite**: the toward-camera pass's south + the away-camera pass's
   north + the mechanical pass's other six. Same character, same canvas,
   feet within a pixel — the splices are invisible. Then level all frames to
   the family feet line as above. Animations of the stance follow the same
   split: animate each direction on the character whose rotation owns it.

**Do not reach for the v3-rotate here.** Rotating from the approved south
loses the weapon entirely (a foreshortened frame carries no barrel geometry
for the engine to swing round), and rotating from a full-profile east drifts
(stubby sides, sideways south). The rotate trick is for **carried** weapons,
where one frame shows the whole weapon and the grip must stay in one hand —
see the brute. Corollary: an aimed stance's weapon *correctly* switches
sides as the facing swings; only carried stances get the hand-switch check.

---

## 7. The animation program  [proven 2026-08-24, goblin machine-gunner]

How two approved stances become the eight animated sets, one generation
batch per set, a human checkpoint after each. The whole program cost ~60
generations on the MG goblin, point repairs included.

**The 9-frame house shape is `keep_first_frame`.** Every shipped set is 9
frames because frame 0 IS the state's rotation (the reference) and the
engine generates 8 more (`frame_count: 8, keep_first_frame: true`). The
shipped Goblin's walk confirms it: walk frame 0 is pixel-identical to its
idle frame 0. Keep that shape — it is also what makes endpoint sealing (§5,
assemble step) nearly a no-op instead of a visible snap.

**Which engine mode per set:**

| Set | Mode | Why |
|---|---|---|
| `standing_idle`, `standing_idle_alt`, `standing_idle_walk`, `standing-readyToFire_idle`, `standing_idle_damage`, `standing_idle_reload` | plain v3, all 8 directions in one call | v3 loops naturally close back onto their reference (measured seams sit inside the per-step delta range); for the one-shots, say "then returning to his exact starting pose" and the return rule (§3) mostly takes care of itself |
| `standing_idle_to_readyToFire` | v3 **interpolation**, one call per direction: `custom_start_frame` = idle rotation, `end_frame` = aim rotation | the transition must land on the aim rotation *and* read in reverse as the lower; pinning both ends made every direction land 0–1px off its target |
| `standing_idle_to_dead` | v3 interpolation: start = idle rotation, end = the **corpse** rotation | the death lands exactly on the corpse the board keeps, so the swap to the static Dead sprite is invisible |

A stance built as a §6 composite animates **each direction on the character
that owns its rotation** — the aim-idle's south ran on the toward-camera
state, its north on the away state, the rest on the mechanical pass.

**Always in the action language:** "the weapon completely inactive, not
firing, no muzzle flash, no sparks, no bright highlights". It reduces but
does not eliminate flash — which is why the scan below is not optional.

**Scan every batch, before the human looks:**
`python tools/judge_frames.py anim <set-dir> --gif out.gif --fps <spec fps>`
— feet weld/bob per direction, row-0, per-frame glint counts, per-step
deltas, loop seam. A handful of flash pixels is a point repair (recolor to
the median of the surrounding weapon pixels; erase a detached spark);
a direction lit in most frames is a re-roll. If a facing keeps re-lighting
across sets, its ROTATION carries the seed glint: repair the rotation's
white pixels and re-roll that direction with the repaired frame as
`custom_start_frame` — negation language alone lost twice before this won.
The MG goblin's south-east did exactly this in every single set.

**The human judges the GIF, not the strip.** The tool's GIF holds two extra
beats on frame 0 at the loop point — the in-game snap back to idle — so a
one-shot that fails to return to neutral shows as the twitch it will be in
play. Two verdicts from the checkpoint loop worth keeping: "not jarring
enough" is a real failure of a damage set (re-roll with mechanically bigger
language: body snaps, head whips, a knee buckles), and a corpse generated on
an enlarged canvas inflates to fill it (§6 canvas law) — the Dead state is a
48-canvas state pass with "a small crumpled heap no larger than his standing
figure's footprint", judged against the shipped corpse for perspective.

**Then assemble.** Write a manifest pointing at the approved staging folders
and run `python tools/assemble_unit.py <manifest>` — binary alpha, one
frame-0-anchored transform per direction, endpoint seals, corpse taken from
the death's last frames. It rebuilt the shipped MG goblin byte-identically
from staging, so what it enforces is exactly what shipped. From there §5
takes over: metadata.json by hand (only the operator knows the character ids
and repair notes), `validate_unit_sprites.py`, wiring, `measure_muzzle.gd`,
`check_unit_art.gd`, `check_res_case.py`, and the render check.

**Animating: a glint pixel is a firing instruction.** A white highlight on a
weapon's muzzle in the rotation frame gets read by the animator as "this
weapon sparks" and grows into muzzle flash in the generated frames (found on
the MG goblin's south-east: 2 white pixels became flashes in both idle and
walk). Negation language ("not firing, no muzzle flash") reduces but does not
stop it. The fix that works: recolor the glint pixels to the weapon's metal in
the seed frame, pass it via `custom_start_frame_base64` (single-direction v3
call), and apply the same repair to the static rotation so still and animation
agree. Scan every rotation for near-white pixels (`min(RGB) > 200`) before
animating — and scan every animation for them after.

**Gates before any human judging** (`python tools/judge_frames.py rotations
<dir> --sheet out.png`): row 0 must hold <6 opaque px (else the weapon is
amputated), zero near-white glint pixels (see §7 — a glint becomes muzzle
flash the moment the frame seeds an animation), feet per direction within the
family band, the carry-side sweep, and a 5× nearest-neighbour compass sheet —
measured numbers catch clipping and scale, only the eye catches pose lies.
Spec-number checks (feet band, figure height, palette) stay with
`measure_rotations.py`; the two tools judge different failures and both run.
