# Sandline floor-art pipeline — runbook

How a batch of ground art goes from prompt to shipped sheet. The style rules
live in [STYLE.md](STYLE.md); the numbers live in [style.json](style.json);
this file is the *order of operations* and what to do when a stage fails.
**Ground art only** — units run a different loop, with different tools, gates
and failure modes: see [UNIT_PIPELINE.md](UNIT_PIPELINE.md).

All commands run from the repo root in PowerShell. All batch state lives in
`artgen/staging/<batch>/manifest.json` — the loop is resumable from files
alone after any crash or MCP disconnect.

```
artgen/staging/<batch>/
  manifest.json     the batch's single source of truth
  raw/              tiles as downloaded (128x128 or 96x96, pre-post)
  post/             finished sheet(s) + *.tiles.json sidecars
  preview/          viewer HTML + PNGs, synthetic board patches
```

## Stage 0 — open the batch

```powershell
# note the balance BEFORE spending (get_balance via MCP)
python tools/pixellab_batch.py init --batch artgen/staging/desert-2026-08-xx `
    --kind biome --biome desert --balance <n>
```

`init` snapshots `style_hash` (sha1 over STYLE.md + style.json) into the
manifest — if the style files change mid-batch, the mismatch is visible in
provenance forever.

Budget yardstick: a `create_tiles_pro` call costs ~20–40 generations
(canvas-size dependent; 40 at 4K), so a full biome — 3 base calls + 2
transition sets — lands around 200. `close` logs the measured delta.

## Stage 1 — submit

Claude assembles prompts from STYLE.md §7 fragments (shared prefix + numbered
per-tile lines, forbidden words absent) and calls the MCP generator with the
biome's fixed seed (style.json; retry = seed + 1000·attempt). Three submit
rules that cost real generations when broken:

- **≤6 numbered prompts per `create_tiles_pro` call.** At 128px the API
  silently caps at 6 variants per call — prompts 7+ are discarded with no
  error. An 18-slot sheet is 3 calls of 6 (slots 0–5, 6–11, 12–17).
- **`tile_depth_ratio: 0` on every flat-floor call.** Omitted, isometric mode
  returns extruded 3D slabs (full parameter recipe in STYLE.md §9).
- **Transition prompts open `"<first terrain> to <second terrain>:"`** — the
  first-named terrain is what the corner-mask bits refer to
  (mask = NW<<3 | NE<<2 | SW<<1 | SE, bit set = first terrain at that corner;
  grid→screen NW→top, NE→right, SE→bottom, SW→left).

**The moment a job ID comes back**, record it — this must survive a disconnect:

```powershell
python tools/pixellab_batch.py add-job --batch <dir> --job-id <id> `
    --tool create_tiles_pro --targets "slots 0-5" --params <saved-params.json> --cost 40
```

Save the exact request params to a file first; `--params` records its path
and hash. `--regen-of <old-job>` links a retry to what it replaces.

## Stage 2 — poll and download

Poll `get_*` round-robin (~15–100 s per job). On completion:

```powershell
python tools/pixellab_batch.py set-status --batch <dir> --job-id <id> `
    --status completed --url tile_0=https://... --url tile_1=https://...
python tools/pixellab_batch.py download --batch <dir>
```

`download` fetches every completed job's URLs into `raw/` with plain urllib
(no auth, but with a **browser User-Agent** — the backblaze storage URLs 403
Python's default UA; the tool already sends one, remember that for any manual
fetch), records sha1 + timestamp, skips files already on disk, retries
each URL once. **Never batch downloads at the end of a session** — map
objects expire after 8 h, and a lost URL is a lost generation.

`status` prints the job table and exits 0 only when nothing is pending —
safe to gate a script on.

## Stage 3 — post-process + layout

```powershell
python tools/floor_pipeline.py post --raw <dir>/raw --out <dir>/post/Sheet.png `
    --style artgen/style.json --kind tiles --biome desert `
    --slots-map <slots.json> --sidecar-out <dir>/post/Sheet.tiles.json
```

Per-tile chain (order matters; see STYLE.md §9 for why each exists):
rim inward-fill (3 px, at native res) → crop to the diamond's alpha bbox →
[optional `--zoom-crop` 1.08 fallback] → one Lanczos resize to 128×60 (this
is simultaneously the 2:1 squash for 1:1 inputs, the ×4/3 upscale for
96px-capped modes, and a no-op for pre-squashed 128px records — verified
records return both shapes) → canonical diamond alpha mask → luminance
normalization (`tiles`: pull to shared mean keeping 15% own deviation, ash
desat/0.40 special case; `tileset`: **per-corner-class targets, never a
single mean** — a global mean silently erases the transition) → edge
harmonization (outer 6 px band blended ≤35% toward the *normalized* sheet
mean; harmonizing before normalization measurably biases rims bright) →
palette clamp (≤96).

`--kind tileset` needs `--rules <json>` (the translated corner metadata);
`--kind paths` needs the edge-mask rules. Single-slot regen:
`--slot N --into existing.png` posts one tile using the existing sheet's
statistics and pastes it in place.

## Stage 4 — validate

```powershell
python tools/validate_floor_art.py <dir>/post/Sheet.png `
    --sidecar <dir>/post/Sheet.tiles.json --style artgen/style.json
```

Exit 0 = gate passed; record it:
`python tools/pixellab_batch.py set-validation --batch <dir> --pass --report "<summary>"`.
`--report` mode prints all metrics without failing — use it for calibration
and for auditing legacy sheets.

## Stage 5 — review

```powershell
python tools/make_tile_viewer.py <dir>/post/Sheet.png --sidecar <...> `
    --compare assets/Tiles/Environments/Desert/Cracked_Desert_floor.png `
    -o <dir>/preview/index.html
```

Claude Reads `*_seams.png` / `*_slots.png` / `*_compare.png` against STYLE.md
§10 and files per-slot verdicts:

```powershell
python tools/pixellab_batch.py review --batch <dir> --job-id <id> --slot 3 `
    --verdict regen --reason "rim survives on SE edge"
```

This read happens **even when the validator passed** — the metric tolerance
provably cannot see a transition tile with a missing dark half or a
wrong-corner layout; only the PNG read catches those. For transition sets,
also verify the corners empirically: classify each tile's 4 corner regions
against the pure tiles' colors and expect 100% match. Scattered mismatches
are broken tiles to regen, not a mapping error — only a systematic bit-flip
pattern across the whole set means the mapping itself is wrong.

Failed base-sheet slots regen via style-mode top-up with CLEANED rim-free
refs (STYLE.md §9); broken transition tiles mean regenerating the whole
16-tile set and cherry-picking (see the playbook) — three strikes on one
slot = stop and escalate to the user.

## Stage 6 — promote

```powershell
python tools/pixellab_batch.py promote --batch <dir> `
    --to assets/Tiles/Environments/Desert --as-reference artgen/reference/desert
```

`promote` **refuses** unless `validation.pass` is true and every slot has an
accept verdict. It copies `post/*.png` + `*.tiles.json` to the target,
optionally copies accepted raws into the biome reference dir, and archives
the manifest to `artgen/batches/<batch>.manifest.json` (committed —
provenance + budget log).

Caveat: `--as-reference` copies only top-level `raw/*.png`, and `download`
may write into subdirectories (URL names like `base_a/tile_0` land at
`raw/base_a/tile_0.png`). When raws live in subdirs, copy the ACCEPTED
128×128 raws into `artgen/reference/<biome>/` by hand after promoting.

## Stage 7 — engine verify + close

```powershell
powershell tools/godot.ps1 --headless --path . -s tools/check_cover_rules.gd
powershell tools/godot.ps1 --headless --path . -s tools/check_tile_catalog.gd
powershell tools/godot.ps1 --headless --path . -s tools/check_floor_sheets.gd
# windowed screenshots via render_board_preview.gd (headless cannot render);
# --level is 1-based; full-scene alternative: --path . -- --level N --screenshot out.png
python tools/pixellab_batch.py close --batch <dir> --balance <n-after>
```

`check_tile_catalog.gd` is the sidecar-aware successor; `check_floor_sheets.gd`
stays in the list only while any biome still lacks a sidecar.

`close` records `balance_end`; the manifest archive is the budget log.

### The Godot invocation gotcha

The editor binary is NOT on PATH and lives inside a folder that is itself
named `.exe`:
`C:\Users\bhixe\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe`
— the obvious path (treating the folder name as the file) fails confusingly.
Always go through `tools/godot.ps1`, which resolves `$env:GODOT_EXE`, then
the known Downloads path, then PATH. Remember `--headless` cannot screenshot
(dummy rasterizer): previews run windowed with a ~2 s window flash.

One caveat with the shim: Windows PowerShell 5.1 strips a bare `--` from the
argument list before the shim can forward it, which silently drops user args
(`-- --level 1 --screenshot out.png` arrives as `--level 1 ...` and Godot eats
it as its own flag). For any invocation that needs game-side user args, call
the console exe directly (from bash, or with the full quoted path via `&`),
or pass `'--'` quoted so PS treats it as a string. Headless `-s` tool runs
don't hit this — their `--` is consumed by Godot, not the game.

## Failure playbook

| Symptom | Cause | Fix |
|---|---|---|
| Dark lattice over the board / rim FAIL | segmentation outline survived | it should never survive post — check the tile actually went through `post`; if rim-fill genuinely can't reach (art darkens gradually inward), regen the slot; `--zoom-crop` is the fallback of last resort |
| Seam ratio FAIL on specific pairs | one tile's edge texture too busy | regen that slot with "plain edges, detail in the center" pushed harder in its numbered prompt |
| Chequerboard in preview | normalization skipped or targets wrong | confirm `--biome` was passed; for tileset kind confirm corner classes came from `--rules` |
| Transition band vanished after post | a global mean was applied to a tileset | rerun `post --kind tileset` — per-corner-class targets are mandatory |
| Dark ridge WARN on transition tiles | segmentation painted internal borders | `inpaint_image` touch-up on the ridge, or regen with boundary words removed from the prompt |
| Extruded side faces, diamond inset in canvas | style mode used for a full sheet | shape mode only (STYLE.md §9); style mode is for P4-gated single-slot top-ups |
| Tiles arrive 96×96 | isometric tileset/path cap | expected — the ×4/3 upscale stage handles it; do NOT prompt-fight the cap |
| Download 404 | asset expired (8 h) or URL recorded wrong | regen; next time download on completion, not at session end |
| `promote` refuses | validation not recorded or slot verdicts missing | run stages 4–5; the refusal is the feature |
| Godot "not recognized" | PATH assumption | use `tools/godot.ps1` (see gotcha above) |
| MCP disconnect mid-batch | — | nothing is lost if add-job ran on submit: `status` shows pending jobs, re-poll by job ID, resume from Stage 2 |
| Sent 10 numbered prompts, got 6 tiles | 128px `create_tiles_pro` silently caps at 6 variants per call | expected — never send >6 prompts per call; the extras were discarded, not queued; resubmit them as their own call |
| Extruded 3D slabs from a *shape-mode* call | `tile_depth_ratio` omitted | pass `tile_depth_ratio: 0` on every flat-floor call (STYLE.md §9) |
| Path-tile set arrives as fragmented 3D chunks | `create_path_tiles` failure mode (seen live once) | roads are risky: always eyeball the raw contact sheet before post; regen with a new seed; the working reference is record `f9426fe8` ("cracked desert with a dirt road") |
| One broken tile in a 16-tile transition set | tileset mode can't regen single tiles and can't take style refs | regenerate the WHOLE set with seed +1000·attempt and cherry-pick the good tiles into the sheet |
| Style-mode top-up brings the rim back | raw (rimmed) tiles passed as `style_images` | style mode copies shape+size from its refs (verified) — pass 2–3 CLEANED refs: post-processed, rim-free, native 128×128 |
| Storage URL 403s a manual fetch | backblaze rejects Python's default UA | send a browser User-Agent (the batch tools already do) |
| Transition corners look systematically wrong | almost never the mask mapping | corner-classify every tile against the pure tiles: scattered mismatches = broken tiles to regen; only a consistent bit-flip across the whole set = remap |
| Corner set's tile_3 is a pure-terrain duplicate | trans12-style corner sets repeatedly ship tile_3 (mask 3, SW+SE) broken — observed desert/ash/compound, 5 records; PixelLab's own metadata lists mask=15 for it | check mask 3 FIRST on every corner set; proven fix: horizontal mirror-synth from the mask-5 tile (screen L-R flip swaps NE↔SW; re-mask with the canonical diamond, keep the palette ≤96 when filling edge px); prompting for stronger terrain contrast fixed it once (compound seed 2209) at the cost of tone drift |
| Corner set arrives with duplicate masks (<16 distinct) | the delivery itself is mask-degenerate — tile_N ≠ mask N and PixelLab's placement metadata concurs (salt trans12 v3 `caa0e49e` shipped 7 distinct masks: [0,10,12,10,10,10,10,10,5,5,5,5,12,12,12,15]), so it is generation-level, not a misread | classify all 64 corners AND read the record's mask listing before post; mirrors cannot rebuild the missing masks (they form flip-closed classes — a full L-R flip only buys 3↔5 and 10↔12) — the set is unusable, regen with a new seed |
| Boundary glow band on transition tiles; upper terrain mismatches its base sheet | prompt described the second terrain as "darker X" — the generator obliges with a genuinely different surface tone that no per-corner-class normalization can reconcile | describe BOTH transition terrains with the same surface tone, differing in feature density — "X to darker Y" produces boundary glow bands and base-sheet mismatches (salt trans12 v2 `a1d9756e` is the live example) |
| Same-tone transition pair delivers <16 distinct masks | same-tone transition pairs reliably yield mask-degenerate deliveries (2/2 observed: salt trans12 v3 `caa0e49e` 7 distinct, v4 `5fca231a` 12 distinct) — plan on symmetry synthesis to complete the set | verify every delivered mask empirically (corner-classify against the pure tiles; the v3/v4 metadata agreed with empirics both times, but check anyway), then synthesize the gaps from VERIFIED raws: H-flip for NE↔SW-swapped masks (10↔12, 11↔13, 3↔5); unsquash (×2 vertical Lanczos) → rot90 → resquash for the rest (rot CW maps NW→NE→SE→SW; 11→14, 13→7); re-mask with the delivery alpha and verify every synth empirically — a 12-mask delivery closes with 2 flips + 2 rotations (salt trans12 v4, promoted). Seam textures are near-directionless, so flips/rotations don't fight the light; check at 2× anyway |
