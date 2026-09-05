---
name: generate-biome
description: Generate or repair a SANDLINE floor biome (base sheet + transition sets) through the PixelLab pipeline with validation and review gates
---

# /generate-biome

Invocation forms:

- `/generate-biome red canyon` — NEW biome, full run: 18-slot base sheet + two zone-transition sets
- `/generate-biome desert` — regenerate an existing biome on its fixed seed
- `/generate-biome repair desert slot 4` — repair named slot(s) of an existing sheet
- `/generate-biome transitions-only ash` — just the two 16-tile transition sets

Depth lives in [artgen/PIPELINE.md](../../../artgen/PIPELINE.md) (runbook + failure
playbook) and [artgen/STYLE.md](../../../artgen/STYLE.md) (prompt fragments §7,
recipe §9, review rubric §10). This skill is the order of operations plus the
rules that must never drift. All batch state goes in
`artgen/staging/<batch>/manifest.json`; the loop is resumable from files alone.

## Hard rules — before spending anything

1. **Manifest first.** Run `pixellab_batch.py add-job` the moment a job ID exists,
   before anything else. A disconnect must never lose a paid job.
2. **Never more than 6 numbered prompts per `create_tiles_pro` call.** At 128px the
   API silently caps at 6 variants; prompts 7+ are discarded, not queued — a
   10-prompt call wastes 4 prompts with no error. 18-slot sheet = 3 calls of 6
   (slots 0–5, 6–11, 12–17).
3. **`tile_depth_ratio: 0` on every flat-floor call.** Without it, isometric mode
   returns extruded 3D slabs instead of flat ground.
4. **Download on completion**, never batched at session end (assets expire in 8 h).
5. **Never write into `assets/`** except through `pixellab_batch.py promote`.
6. **Read artgen/STYLE.md before assembling any prompt** — §7 fragments + forbidden
   words, §9 recipe. Prompts are assembled from the bible, not from memory.
7. **Taste-check pause for NEW biomes:** show the user the assembled prompts and
   the chosen style references BEFORE the first paid call. Do not skip this.
8. **3-strike thrash breaker:** three failed regens of the same slot = stop and
   escalate to the user.
9. **The review gate (stage 8) is non-negotiable.** A validator PASS never skips
   reading the PNGs — the metric tolerance provably cannot see a transition tile
   with a missing dark half or a wrong-corner layout.

## Stages

1. **Init.** Log the balance: `get_balance` (MCP). For a NEW biome first add its §7
   fragment block to STYLE.md (new-biome template) and a `biomes.<name>` entry to
   style.json (next free seed; provisional `lum_mean` near desert's until
   measured), then do the taste-check pause (rule 7).
   ```powershell
   python tools/pixellab_batch.py init --batch artgen/staging/<biome>-<yyyy-mm-dd> `
       --kind biome --biome <biome> --balance <n>
   ```
2. **Params files.** Write each call's exact request params to
   `<batch>/params_<call>.json` before submitting — `add-job --params` records the
   path + hash into provenance.
3. **Submit.** Base sheet, 3 calls × 6 numbered prompts, shape mode (never style
   mode for full sheets):
   `create_tiles_pro(tile_type="isometric", tile_size=128, tile_view="top-down",
   tile_depth_ratio=0, tile_flat_top_px=4, outline_mode="segmentation",
   seed=<biome seed>)` — retry seed is `seed + 1000*attempt`.
   Transition sets (2 calls: zone 0↔1, zone 1↔2): same params but
   `tile_feature="tileset"`, `tile_size=96` (hard API cap for isometric tilesets;
   post upscales ×4/3), seeds from the 2xx block. Transition prompts open with
   `"<first terrain> to <second terrain>: ..."` — the FIRST-named terrain is what
   the mask bits refer to (`mask = NW<<3 | NE<<2 | SW<<1 | SE`, bit set = first
   terrain at that corner; grid→screen: NW→top, NE→right, SE→bottom, SW→left).
   Record every job the moment its ID returns:
   ```powershell
   python tools/pixellab_batch.py add-job --batch <dir> --job-id <id> `
       --tool create_tiles_pro --targets "slots 0-5" --params <file> --cost 40
   ```
   Roads (`create_path_tiles`) are RISKY — one live record came back as fragmented
   3D junk; the working reference is record `f9426fe8` ("cracked desert with a
   dirt road"). Always eyeball the raw contact sheet before running post.
4. **Poll + download.** Poll `get_tiles_pro` round-robin (~15–100 s). On each
   completion run `set-status ... --url name=<url> ...` then immediately
   `python tools/pixellab_batch.py download --batch <dir>`. Budget yardstick:
   ~20–40 generations per call (canvas-size dependent; 40 at 4K); a full biome
   (3 base + 2 transition calls) lands around 200.
5. **Post.** Base sheet:
   ```powershell
   python tools/floor_pipeline.py post --raw <dir>/raw --out <dir>/post/<Biome>_floor.png `
       --style artgen/style.json --kind tiles --biome <biome> `
       --slots-map <slots.json> --sidecar-out <dir>/post/<Biome>_floor.tiles.json
   ```
   Transitions: same but `--kind tileset --rules <corner-rules.json>` (rules
   translated from the `get_tiles_pro` corner metadata). Tiles arrive PRE-SQUASHED
   (2:1 diamond inside the square canvas): the chain bbox-crops and makes exactly
   one Lanczos resize to 128×60 — never add extra resizes.
6. **Validate.**
   `python tools/validate_floor_art.py <sheet> --sidecar <...> --style artgen/style.json`
   → exit 0, then record it: `pixellab_batch.py set-validation --batch <dir> --pass`.
7. **Viewer.**
   `python tools/make_tile_viewer.py <sheet> --sidecar <...> --compare <shipped sheet> -o <dir>/preview/index.html`
8. **REVIEW GATE.** Read `_slots.png` / `_seams.png` / `_compare.png` against the
   STYLE.md §10 rubric. For transition sets, verify corners empirically: classify
   each tile's 4 corner regions against the pure tiles' colors — expect 100%
   match; mismatches are broken tiles to regen, NOT a mapping error, unless they
   form a systematic bit-flip pattern. File a verdict per slot:
   ```powershell
   python tools/pixellab_batch.py review --batch <dir> --job-id <id> --slot <n> `
       --verdict accept --reason "<why>"
   ```
9. **Repair loop.**
   - Base-sheet slots: style-mode top-up with 2–3 CLEANED refs (post-processed,
     rim-free, native 128×128) — style mode copies shape+size from its refs
     (verified), so a rimmed raw ref clones the rim back in. Then
     `floor_pipeline.py post --slot N --into <sheet>`.
   - Transition tiles: REGENERATE THE WHOLE 16-TILE SET with a new seed
     (`+1000*attempt`) and cherry-pick the good tiles — tileset mode cannot do
     single tiles and cannot take style refs.
   - Three strikes on one slot → stop and escalate (rule 8).
10. **Promote.**
    ```powershell
    python tools/pixellab_batch.py promote --batch <dir> `
        --to assets/Tiles/Environments/<Biome> --as-reference artgen/reference/<biome>
    ```
    Refuses without validator PASS + a full set of accept verdicts — that refusal
    is the feature. Caveat: `--as-reference` copies only top-level `raw/*.png`;
    raws downloaded into subdirs (`raw/base_a/tile_0.png`) are missed — copy the
    ACCEPTED 128×128 raws into `artgen/reference/<biome>/` by hand in that case.
11. **Wire check.** Brand-new biome: add the sheet to `Board.FLOOR_SHEETS`
    (+ `SHEET_REGIONS`), and to `Levels.BIOMES` if a camp will stand on it.
    Existing biomes: same path/filename → the preload picks it up, nothing to edit.
12. **Engine verify.**
    ```powershell
    powershell tools/godot.ps1 --headless --path . -s tools/check_tile_catalog.gd
    powershell tools/godot.ps1 --headless --path . -s tools/check_cover_rules.gd
    powershell tools/godot.ps1 --path . -s tools/render_board_preview.gd -- --level 1
    # full scene alternative: powershell tools/godot.ps1 --path . -- --level 1 --screenshot shot.png
    ```
    `--headless` cannot screenshot (dummy rasterizer); previews run windowed with
    a ~2 s flash. `--level` is 1-based everywhere. READ the screenshots — that is
    the point of taking them.
13. **Close.** `get_balance` again, then
    `python tools/pixellab_batch.py close --batch <dir> --balance <n>`, and append
    a dated line to STYLE.md §11 for anything learned or deviated. A batch that
    taught nothing still gets its budget line via the archived manifest.
