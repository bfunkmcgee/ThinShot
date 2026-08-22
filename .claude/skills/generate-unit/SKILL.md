---
name: generate-unit
description: Generate or regenerate a ThinShot unit (two characters, eight animation sets, 600 PNGs) through the PixelLab pipeline with repair, validation, review and in-game judge gates
---

# /generate-unit

Invocation forms:

- `/generate-unit shielded goblin` — NEW unit, full run: 2 characters + 8 animation sets
- `/generate-unit regen Kestrel_Medic` — regenerate an existing unit in place
- `/generate-unit repair Scout aim-idle north` — re-roll named direction(s) of one set
- `/generate-unit finish artgen/staging/units-2026-08-20` — resume an open batch from its manifest

Depth lives in [artgen/UNIT_PIPELINE.md](../../../artgen/UNIT_PIPELINE.md)
(runbook, cost model, failure playbook), [UNIT_ASSET_SPEC.md](../../../UNIT_ASSET_SPEC.md)
(the shape the art must have — §3 the eleven sets, §4 the canonical layout, §5
the wiring checklist) and [artgen/STYLE.md](../../../artgen/STYLE.md) (§1 the
density tier and its status, §2 light). This skill is the order of operations
plus the rules that must never drift. All batch state goes in
`artgen/staging/<batch>/manifest.json`; the loop is resumable from files alone.

Floor biomes are a **different** loop — that is `/generate-biome` and
`artgen/PIPELINE.md`. Do not mix the two runbooks.

## Hard rules — before spending anything

1. **Check the suspension first.** STYLE.md §1 carries the density-tier status.
   As of 2026-08-15 the hi-res unit program is **suspended by user verdict** —
   author at the legacy tier (60/64/56 canvas, drawn small, scaled 2×), not at
   120/128/112, unless the user lifts it in this conversation. UNIT_ASSET_SPEC.md
   §1 still opens with the v2 hi-res mandate; the suspension is the later ruling.
2. **Manifest first.** `set-unit` the moment a character or animation-group id
   exists, `add-job` the moment a job id exists — before anything else. A
   disconnect must never lose a paid job.
3. **Measure the rotations before animating.** `measure_rotations.py` on the
   eight raw rotations, feet inside the tier's range, or stop. 128 generations
   of animation on an unmeasured figure is the most expensive mistake available.
4. **Frames on disk before the next call.** Map objects expire 8 h after
   generation. Never batch saving to the end of a session.
5. **Never write into `assets/`** except through `pixellab_batch.py promote`.
6. **Taste-check pause for a NEW unit:** show the user the silhouette test and
   the reference the character will be rotated from BEFORE the first paid call.
   A new soldier must read differently *in outline* from all sixteen shipped
   ones at 30 px.
7. **3-strike thrash breaker:** three failed re-rolls of the same direction =
   stop, salvage deterministically or escalate. Never a fourth roll.
8. **The in-game judge gate (stage 8) is non-negotiable, and it comes BEFORE
   promote.** HD Rodar and HD Scout passed the validator, took 13/13 accepts,
   promoted, and were reverted hours later on the user's in-game verdict — 312
   generations. A PASS is not a verdict on the art.
9. **Anything written mid-batch belongs in `tools/`, committed, before close.**
   `artgen/staging/` is gitignored; the Aug-15 `scrub_flash.py` salvage tool did
   not survive its own batch.

## Stages

1. **Init.** `get_balance` first and log it.
   ```powershell
   python tools/pixellab_batch.py init --batch artgen/staging/units-<yyyy-mm-dd> `
       --kind unit --units <UnitName> --balance <n>
   mkdir artgen/staging/units-<yyyy-mm-dd>/<UnitName>/params
   ```
   For a NEW unit, do the taste-check pause (rule 6) here. Budget yardstick:
   **132 generations floor, 150–175 realistic** — 2 per direction, 16 per
   8-direction animation set, 2 per character and per single-direction re-roll.
2. **Params files.** Write each call's exact request params to
   `<unit>/params/<call>.json` before submitting; `add-job --params` records the
   path + hash into provenance.
3. **Two characters.** `create_character` for **main** (weapon down) and **rtf**
   (weapon up) — ref-rotate from two views of an existing pose, 2 generations
   each, which keeps the figure inside the house palette without prompting for
   it. Record ids immediately:
   ```powershell
   python tools/pixellab_batch.py set-unit --batch <dir> --unit <Name> `
       --group-id <uuid> --character main=<uuid> --character rtf=<uuid>
   python tools/pixellab_batch.py add-job --batch <dir> --job-id <id> `
       --unit <Name> --state main --tool create_character `
       --targets "main char: ref-rotate of old south x2" --params <file> --cost 2
   ```
4. **GATE: measure.** `python tools/measure_rotations.py artgen/staging/<batch>/<Unit>/raw`
   — the argument is the folder whose *children* hold `rotations/` (one level
   deep, not recursive). Feet are the hard gate; a crown over budget is usually
   headwear and the tool says so. Its constants are the **legacy** tier (feet
   12–16, ≤128 colours), which is correct under the suspension and would
   false-fail a hi-res set. Do not animate until this passes (rule 3).
5. **Animate, one set per call, idle first.** Eight `animate_character` calls ×
   8 directions × 9 frames: `standing_idle`, `_walk`, `_alt`, `_damage`,
   `_reload`, `_to_dead`, `_to_readyToFire`, and `standing-readyToFire_idle`
   (rtf state). Two things that were paid for:
   - **`standing_idle_to_readyToFire` goes as 8 singles with the aim rotation
     pinned as the end frame** — that is how the shipped units came in at 0–4 px
     endpoint gaps against the Kestrels' 39–276.
   - **The aim-idle wants to fire.** Prompt toward *frozen stillness*;
     `fix_idle_flash.py` is the repair, not the plan.
   Custom start frames re-roll one bad direction for 2 generations — use them
   instead of re-rolling a set.
6. **Assemble.** Build `<unit>/post/` in the canonical layout (spec §4; base
   state renamed from `Idle` to the unit). **Dead rotations are harvested, not
   generated:** `python tools/check_dead_stance.py <unit_root> --all` takes all
   eight from the death animation's final frame — `--all`, never `--fix`, or the
   body jumps at the hand-off. Write `metadata.json` last, with the group id, a
   character id per state, and a `note` on every state where the shipped art
   deviates from the cloud state.
7. **Repair pass — before measuring anything.** In order:
   `recanvas_frames.py <unit> <canvas> --fix` (wrong canvas; a refusal means
   regenerate, not force) → `check_dead_stance.py --all` → `seal_raise_transition.py --fix`
   (the animation yields, never the rotation — the rotation carries the muzzle
   offsets) → `fix_idle_flash.py --fix` (flash, and its third detector for
   detached ejecta; a direction lit in more than half its frames is a regen).
8. **Validate.**
   ```powershell
   python tools/check_unit_complete.py <post tree>     # frame CONTINUITY from 000
   python tools/measure_rotations.py <post tree>       # all three rotation sets
   python tools/validate_unit_sprites.py <post tree>   # the per-tier v2 gate
   python tools/pixellab_batch.py set-validation --batch <dir> --pass --report "<summary>"
   ```
9. **Review, per direction.** File a verdict per slot named `<Unit>/<slot>`:
   ```powershell
   python tools/pixellab_batch.py review --batch <dir> --job-id <id> `
       --slot <Unit>/rtf-south --verdict accept --reason "<what you looked at>"
   ```
   `promote` refuses while any slot is not `accept`; re-file a superseded strike
   as an accepted supersession with its history in the reason. Three strikes on
   one direction → salvage deterministically or escalate (rule 7).
10. **JUDGE GATE — in engine, before promote.**
    ```powershell
    python tools/make_char_viewer.py <post tree> --compare assets/sprites/<Unit> `
        -o artgen/staging/<batch>/<unit>/preview/index.html
    powershell tools/godot.ps1 --path . -s tools/render_unit_check.gd -- --kinds <NAME> --zoom 3
    ```
    Read the pages, then **put them in front of the user and wait**. A new unit
    is judged standing beside the soldier it will fight next to. This gate is
    what the Aug-15 revert bought (rule 8).
11. **Promote.** `python tools/pixellab_batch.py promote --batch <dir> --unit <Name>`
    — copies `post/` onto `assets/sprites/<Name>/`, archiving every overwritten
    file into `backup_originals/` first (first promotion wins). Refuses without
    PASS + full accepts.
12. **Wire + verify.** UNIT_ASSET_SPEC.md §5: **append** to `Unit.Kind` (never
    insert — saves store the ordinal), loader roots, `SPRITE_SPECS`, re-measure
    the muzzle table off the new folder and **repoint that unit's
    `measure_muzzle.gd` entry in the same commit**, then:
    ```powershell
    godot --headless --path . --import
    powershell tools/godot.ps1 --headless --path . -s tools/check_unit_art.gd
    python tools/check_res_case.py
    powershell tools/godot.ps1 --path . -s tools/render_unit_check.gd -- --kinds <NAME> --zoom 3
    ```
    The loaders fail silently and a mis-cased path is fatal only in the exported
    PCK — neither check can do the other's job. Finish with stats and a spawn
    entry in `Levels.gd`.
13. **Close.** `get_balance` again, `python tools/pixellab_batch.py close --batch <dir> --balance <n>`,
    append a dated line to STYLE.md §11 (what shipped, what it cost, every
    accepted deviation), and commit any tool written during the batch (rule 9).

## Reverting

There is no `revert` subcommand. Restore from the batch's
`backup_originals/<Unit>/` (`.import` files included), sha1-verify against git
HEAD, reverse the wiring in the same commit (`SPRITE_SPECS`, loader paths,
muzzle tables), and **park the rejected tree rather than deleting it** — it
stays in `<unit>/post/` with a `reverted` record in the manifest, so the next
attempt starts from what was learned. Full procedure in the runbook.
