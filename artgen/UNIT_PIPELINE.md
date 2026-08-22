# ThinShot — unit art pipeline (runbook)

How a soldier goes from a reference drawing to a wired-in `Unit.Kind`. The
*shape* the art has to have lives in [UNIT_ASSET_SPEC.md](../UNIT_ASSET_SPEC.md);
the house look lives in [STYLE.md](STYLE.md); this file is the *order of
operations*, what each stage costs, and what to do when a stage fails.

Floor art has its own runbook — [PIPELINE.md](PIPELINE.md) — and the two loops
differ more than they look. Tiles come back as URLs and are posted as a sheet;
units come back as frames and are assembled as a folder tree. Do not read one
runbook while running the other.

All batch state lives in `artgen/staging/<batch>/manifest.json`. A `--kind unit`
batch stages one subtree per unit, so the loop is resumable from files alone
after any crash or MCP disconnect:

```
artgen/staging/units-<date>/
  manifest.json          the batch's single source of truth
  <UnitName>/
    params/              exact request params, one file per call  (make this yourself)
    raw/                 frames as delivered, per state/set/direction
    post/                the assembled canonical tree — what promote copies
    preview/             viewer HTML + judge shots
  backup_originals/      written by promote, and the only way back
```

`init` creates `raw/ post/ preview/` per unit. `params/` it does not create —
make it, and write every call's params there *before* submitting, because
`add-job --params` records the path and its hash and that is the whole
provenance story.

Prerequisites: Python 3 and **Pillow** — `validate_unit_sprites.py` and
`recanvas_frames.py` need it and say so rather than failing usefully
(`python -m pip install pillow`). The rest of the chain parses PNGs directly and
runs on a bare interpreter. Godot is needed from stage 8 onward.

---

## What a unit costs

Two generations per direction is the unit of account. From the recorded costs
in `artgen/batches/units-hires-2026-08-15.manifest.json`:

| Call | Recorded cost |
|---|---|
| `create_character` (ref-rotate, seeded from two views of an existing pose) | 2 |
| `animate_character`, 8 directions | 16 |
| `animate_character`, 7 directions | 14 |
| single-direction re-roll or custom-start append | 2 |

A clean unit is therefore **2 characters (4) + 8 animation sets (128) = 132**
generations, and nothing runs clean: HD Rodar shipped at 144 and HD Scout at
168 (STYLE.md §11). **Budget 150–175 per unit** and expect a fifth of it to be
per-direction fix re-rolls. That batch recorded 314 across three units against
a measured balance delta of 315 — the arithmetic is close enough that an
unexplained gap of more than a few generations means a job went unrecorded.

Log `get_balance` before the first call and after the last one. `close` prints
the measured delta against the manifest's recorded total.

---

## Stage 0 — decide the density tier, and check the suspension

**Read STYLE.md §1's status line before anything else.** As of 2026-08-15 the
hi-res unit program is **suspended by user verdict** and the 2×-class remains
the standard: new work is authored at the legacy tier — 60×60 (or 64/56 to
match a sibling), figure ~24–28 × ~29–30 px, feet 12–16 px below canvas
centre, drawn small and scaled 2× in engine.

This contradicts UNIT_ASSET_SPEC.md §1, which still opens with the v2 hi-res
mandate. The suspension is the later ruling — HD Rodar and HD Scout were
generated, validated, judge-accepted, promoted, and then **reverted at the
in-game gate the same day**. The spec's `[v2]` rows describe the hi-res
contract for when the program resumes; they are not a licence to spend 150
generations at 120px today. If the user lifts the suspension, say so in the
batch note and follow the `[v2]` rows instead.

Everything else in the spec — the eight directions, the eleven sets, the
canonical folder layout, `metadata.json`, the wiring checklist — is tier-
independent and binding either way.

---

## Stage 1 — open the batch

```powershell
# note the balance BEFORE spending (get_balance via MCP)
python tools/pixellab_batch.py init --batch artgen/staging/units-<yyyy-mm-dd> `
    --kind unit --units <UnitName> --balance <n>
mkdir artgen/staging/units-<yyyy-mm-dd>/<UnitName>/params
```

`--biome` is not required for unit batches. Add a unit to a running batch with
`add-unit --unit <Name>`; it gets its own subtree and its own provenance block.

For a **new** unit, settle the design before opening the batch: ASSETS.md
Tier 3 is the wishlist, and the silhouette test in UNIT_ASSET_SPEC.md §1 is the
gate — a new soldier has to be different *in outline* from all sixteen shipped
ones at 30 px, because that is what the player actually reads mid-fight.

---

## Stage 2 — the two characters

A unit is two PixelLab characters, not one: the **main** state (weapon down)
and the **rtf** state (weapon up). Both are made with `create_character`.

The cheap, style-safe way in is the one the Aug-15 batch used for all three
units: **ref-rotate** — seed the character from two views of an existing
drawing (the old south rotation, or the concept art) and let the generator
produce the other seven directions. Recorded at 2 generations per state, and it
keeps the new figure inside the house palette without prompting for it.

The moment an id comes back, record it — this must survive a disconnect:

```powershell
python tools/pixellab_batch.py set-unit --batch <dir> --unit <Name> `
    --group-id <uuid> --character main=<char_uuid> --character rtf=<char_uuid>
python tools/pixellab_batch.py add-job --batch <dir> --job-id <id> `
    --unit <Name> --state main --tool create_character `
    --targets "main char: ref-rotate of old south x2" --params <params-file> --cost 2
```

**Gate before animating.** Save the eight rotations into `<unit>/raw/` and run:

```powershell
# argument is the folder whose CHILDREN hold rotations/ - one row per state
python tools/measure_rotations.py artgen/staging/<batch>/<Unit>/raw
```

The scan is one level deep (`<root>/<child>/rotations/`), not recursive, so
point it at the parent of the state folders — `<Unit>/raw` while staging, and
`<Unit>/post` once assembled, where it reads all three rotation sets at once.
`no <unit>/rotations/ under ...` means the path is wrong, not that the art is.

Feet inside the tier's range is the hard gate; a crown over budget is usually
headwear, not scale (the tool says which). **Nobody spends 576 animation frames
on a figure that has not been measured.** A wrong foot line here is 130
generations of art that floats above its cell.

Note that this tool is **not tier-aware**: its constants are the legacy spec
(figure 30±2 px, feet 12–16 below centre, ≤128 colours), which is the correct
gate while the hi-res program is suspended and would false-fail a 120px set
(HD Rodar measured feet 29–31). `validate_unit_sprites.py` is the v2, per-tier
gate — at stage 6 it is the one that rules.

---

## Stage 3 — animate, one set per call

Eight `animate_character` calls, each 8 directions, each 9 frames
(UNIT_ASSET_SPEC.md §3). Record the animation group id into the manifest as it
returns (`set-unit --anim-group <set>=<uuid>`) and `add-job` immediately.

Order is not arbitrary — `standing_idle` first, because it is the pose every
other set starts from and the one the judge reads first:

| # | Set | State | Notes from the Aug-15 run |
|---|---|---|---|
| 1 | `standing_idle` | main | the reference cycle; check the weapon is visible in **all nine** frames before continuing |
| 2 | `standing_idle_walk` | main | full stride, weapon across the body |
| 3 | `standing_idle_alt` | main | optional set; a weight-shift fidget that returns to the stance |
| 4 | `standing_idle_damage` | main | flinch in the middle, neutral at both ends — it interrupts *either* idle |
| 5 | `standing_idle_reload` | main | same return rule |
| 6 | `standing_idle_to_dead` | main | one-shot; **also the source of the dead rotations** (stage 4) |
| 7 | `standing_idle_to_readyToFire` | main | submit as **8 singles with the aim rotation pinned as the end frame** — that is how Rodar and Scout came in at 0–4 px endpoint gaps instead of the Kestrels' 39–276 |
| 8 | `standing-readyToFire_idle` | rtf | the aim-idle, and the set that fights back (see below) |

Two prompt tricks that were paid for and are worth reusing:

- **The aim-idle wants to fire.** The prompt says "aiming" and the model shows
  the weapon working, so the loop shoots forever. Wording toward **frozen
  stillness** is what finally cleaned the Rodar and Scout sets; `fix_idle_flash.py`
  is the repair, not the plan.
- **Custom start frames** pin a direction to an already-accepted pose. Both
  units used them to re-roll a single bad direction for 2 generations and to
  append an eighth direction to a 7-direction set.

Whatever the MCP client hands back, the invariant is the same as the tile loop:
**frames land on disk before the next call**. The Aug-15 unit jobs recorded no
URLs at all, so `pixellab_batch.py download` — which fetches into the *batch
root's* `raw/` — is a floor-art stage; unit frames are written into
`<unit>/raw/` as they arrive. Never leave a delivered set unwritten across a
call: map objects expire 8 h after generation and a lost frame is a lost
generation.

---

## Stage 4 — assemble the canonical tree

Build `<unit>/post/` in the layout UNIT_ASSET_SPEC.md §4 mandates — base state
folder named after the unit, `ReadyToFire_Stance/`, `Dead_stance/`. The
downloaded bundle calls the base state `Idle`; it is renamed on assembly. Do
not reproduce a legacy layout, however the sibling unit is laid out: the
canonical tree is what collapses `Unit.gd` down to three path constants.

**The dead rotations are harvested, not generated.** `create_character_state`
with "lying dead" leaves the body standing in some directions — 3 of 8 on the
first Kestrel. Take all eight from the death animation's final frame:

```powershell
python tools/check_dead_stance.py <unit_root> --all
```

`--all`, not `--fix`: substituting only the standing directions leaves the rest
holding a separately-drawn corpse and the body visibly jumps when the animation
hands off. Record the deviation as a `note` on that state in `metadata.json` —
the spec permits the derivation, it does not permit lying about it.

Write `metadata.json` last, with the group id and a character id on every
state. The validator requires it before a hi-res set may be promoted, and it is
the only thing that makes a regeneration reproducible.

---

## Stage 5 — the five-defect repair pass

Pixel Lab reliably ships five defects. All five are quiet: the folder is
complete, the frame counts are right, and nothing errors. **Run these before
measuring anything** — the first three change the pixels the measurement reads.

| Tool | Defect |
|---|---|
| `recanvas_frames.py <unit> <canvas> --fix` | a job returns on the wrong canvas; one direction draws bigger and sits off its diamond. Centred crop/pad; refuses if it would clip the figure — a refusal means regenerate, not force |
| `check_dead_stance.py <unit> --all` | corpse still standing in some facings (stage 4) |
| `seal_raise_transition.py <unit> --fix` | the raise does not land on the aim rotation, so the figure snaps. The *animation* yields — the rotation has dependents (muzzle offsets, the aim-idle's start, the overwatch pose) |
| `fix_idle_flash.py <unit> --fix` | the aim-idle is drawn firing. Detection is colour **and** blinking; a direction lit in more than half its frames must be regenerated instead |
| `fix_idle_flash.py <unit> --fix` (third detector) | detached ejecta — a lump of brass or puff clear of the body that blinks. Deleted, not grafted |

---

## Stage 6 — validate

```powershell
python tools/check_unit_complete.py artgen/staging/<batch>/<Unit>/post
python tools/measure_rotations.py artgen/staging/<batch>/<Unit>/post
python tools/validate_unit_sprites.py artgen/staging/<batch>/<Unit>/post
```

`check_unit_complete.py` counts frame **continuity** from `frame_000`, because
the loader stops at the first missing file and silently shortens the cycle.
`validate_unit_sprites.py` gates canvas, alpha, palette, foot line, aim
direction, aim-idle flash, transition endpoints and `metadata.json`, at the
tier it detects from the canvas. Its check [5] flash rule is relative to each
cycle's median, so it catches a flash in one or two frames and is blind to one
in eight of nine — `fix_idle_flash.py` is the stricter of the two and both are
worth running.

Then record it:

```powershell
python tools/pixellab_batch.py set-validation --batch <dir> --pass --report "<summary>"
```

---

## Stage 7 — review gate, per direction

A validator PASS is not a review. File a verdict per slot, named
`<Unit>/<slot>` the way the Aug-15 batch did (`Scout/rtf-south`,
`Rodar_Akai/main-walk`, `Scout/damage-east`):

```powershell
python tools/pixellab_batch.py review --batch <dir> --job-id <id> `
    --slot <Unit>/<slot> --verdict accept --reason "<what you actually looked at>"
```

`promote` refuses while any slot is not `accept`, so a superseded strike record
has to be re-filed as an accepted supersession with its history in the reason —
that is what "this attempt does not ship" means in the shipped manifest, and it
is the honest way through the gate rather than deleting the record.

**Three-strike ladder.** Three failed re-rolls of the same direction and you
stop rolling. Both shipped units hit strike 3 on a flashing frame and were
salvaged deterministically — hot pixels replaced from the nearest clean frame —
rather than re-rolled a fourth time. Note: that salvage used a `scrub_flash.py`
that lived in staging and **is not in the repo**; `artgen/staging/` is
gitignored and it did not survive. Anything written mid-batch that a future
batch would want belongs in `tools/`, committed, before the batch closes.

---

## Stage 8 — the judge gate, in engine, **before** promote

This is the stage the Aug-15 batch teaches, and it cost 312 generations to
learn: HD Rodar passed the validator, took 13/13 accepts, and shipped; HD Scout
did the same; **both were reverted hours later on the user's in-game verdict.**
Every mechanical gate had passed. Nothing in a PNG review had asked the only
question that mattered — does this read as ThinShot on the board.

So build the comparison and put it in front of the user before anything touches
`assets/`:

```powershell
python tools/make_char_viewer.py <staged post tree> --compare assets/sprites/<Unit> `
    -o artgen/staging/<batch>/<unit>/preview/index.html
powershell tools/godot.ps1 --path . -s tools/render_unit_check.gd -- --kinds <NAME> --zoom 3
```

`--compare` renders old beside new per state, per rotation, per animation set.
`render_unit_check.gd` stands the unit up through the real `setup()` path in
all eight facings with a dot on `muzzle_point()` — measurements are made on
PNGs, and this is where you find out whether the number still lands on the
barrel after Godot applies `SPRITE_SPECS`. A new unit gets the same treatment
beside the soldier it will stand next to.

---

## Stage 9 — promote

```powershell
python tools/pixellab_batch.py promote --batch <dir> --unit <Name>
```

Copies `<unit>/post/` onto `assets/sprites/<Name>/` and archives **every file it
overwrites** into the batch's `backup_originals/` first — first promotion wins,
so the archive always holds the true original. It refuses without a validation
PASS and a full set of accept verdicts. Those refusals are the feature.

Never write into `assets/` any other way.

---

## Stage 10 — wire it in, and prove it loaded

UNIT_ASSET_SPEC.md §5 is the checklist and it is not optional reading. The
parts that bite:

- **Append to `Unit.Kind`, never insert.** Saves store the raw ordinal.
- Re-measure the muzzle table off the *new* folder and **repoint the unit's
  existing entry in `measure_muzzle.gd` in the same commit** — a retired folder
  usually stays on disk, so a stale entry goes on measuring a soldier the game
  no longer draws and reports `(all 8 facings match)` against nothing.
- Two load checks, and neither can do the other's job:
  ```powershell
  powershell tools/godot.ps1 --headless --path . -s tools/check_unit_art.gd
  python tools/check_res_case.py
  ```
  The loaders fail silently — a mistyped root leaves the unit standing still
  with an empty console and a green test suite. And a mis-cased path resolves
  on Windows, loads in every harness, and is missing only from the exported
  PCK.
- `godot --headless --path . --import` to generate `.import` files, then look
  at it once more in `render_unit_check.gd`.
- Stats and a spawn entry in `Levels.gd`, or the unit exists and never appears.

---

## Stage 11 — close

```powershell
python tools/pixellab_batch.py close --batch <dir> --balance <n-after>
```

Then append a dated line to STYLE.md §11: what shipped, what it cost, and every
accepted deviation. A batch that taught nothing still gets its budget line. Any
script written during the batch moves into `tools/` and is committed.

---

## Reverting a promoted unit

There is **no `revert` subcommand** — the Aug-15 revert was done by hand, and
this is the procedure it established:

1. Restore from the batch's `backup_originals/<Unit>/` — the exact tree that
   was overwritten, `.import` files included.
2. Verify by sha1 against git HEAD before believing it. Both units were
   sha1-verified in both directions.
3. Reverse the wiring in the same commit: `SPRITE_SPECS` entries, the loader
   path constants if the layout moved, and the muzzle tables back to their
   pre-promotion values.
4. **Park the rejected tree, do not delete it** — it stays in `<unit>/post/`
   with a `reverted` record in the manifest (`{units, reason, ts}`), so the
   next attempt starts from what was learned rather than from zero.

---

## Failure playbook

| Symptom | Cause | Fix |
|---|---|---|
| One direction of one set draws bigger and sits off its diamond | a backfill lost the request's canvas size | `recanvas_frames.py <unit> <canvas> --fix`; if it refuses, the frame is clipped — regenerate it |
| Corpse pops upright when the death animation ends | `create_character_state` kept the standing pose in some facings | `check_dead_stance.py --all`, and note the derivation in `metadata.json` |
| Figure snaps when the weapon-raise finishes | the raise's last frame is not the aim rotation | `seal_raise_transition.py --fix` — the animation yields, never the rotation |
| Unit fires forever while standing still | muzzle flash drawn into the aim-idle loop | `fix_idle_flash.py --fix`; a direction lit in >half its frames is a regen, and re-prompt toward frozen stillness |
| Animation truncates mid-cycle in game, all tools green | a missing `frame_%03d` — the loader counts up and stops | `check_unit_complete.py`; it checks continuity from 000, not file count |
| Unit stands still in game, nothing in the console | a mistyped root; `_load_dir_frames` returns empty and does not error | `check_unit_art.gd` — it asserts all 11 sets actually filled |
| Art loads everywhere, missing from the exported build | a mis-cased `res://` path, which Windows resolves and the PCK does not | `check_res_case.py` |
| Aim pose drawn levelled to the flank on south, or weaponless on north | a known and frequent generator failure on those two facings | re-roll that single direction (2 gens) with a custom start; if it survives three strikes, record `levelled` in the `measure_muzzle.gd` entry so the offset follows the art |
| Validator PASS, all slots accepted, and the art is still wrong | the mechanical gates cannot see art direction | stage 8 — that is exactly how 312 generations got reverted |
| Recorded cost and balance delta disagree by more than a few | a job was submitted without `add-job` | reconcile from the animation group ids before closing; an unrecorded job is an unreproducible unit |
