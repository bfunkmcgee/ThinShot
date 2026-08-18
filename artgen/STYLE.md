# Sandline floor-art style bible

The single source of truth for what Sandline ground art looks like and how it
is generated. The machine half of this document lives in [style.json](style.json) —
every number a tool needs is there; every number quoted here is documentation
of that file, not a second authority. `tools/floor_pipeline.py` enforces the
recipe, `tools/validate_floor_art.py` enforces the contract, and any accepted
deviation gets a dated line in the changelog at the bottom.

This file migrates and supersedes ASSETS.md "How the last three were made";
ASSETS.md keeps the wishlist and points here.

## 1. Identity & camera

- **2:1 isometric flat diamonds, 128×60**, seen from above with the barest
  suggestion of relief (`tile_flat_top_px: 4`). Ground only: no side faces, no
  thickness, no raised edges, no perspective walls. A tile is a *patch of
  ground*, not a block.
- Tiles are generated on a square **128×128** canvas and arrive with the
  diamond **already squashed 2:1** inside it (verified across live records;
  some return a 1:1 diamond instead — see changelog 2026-08-14). The post
  chain crops to the alpha bbox and makes **exactly one** Lanczos resize to
  128×60: that resize is the 2:1 projection for 1:1 inputs and a near-no-op
  for pre-squashed ones, so nothing is distorted either way. Never draw at
  128×60 directly, and never add a second resize.
- **Texel rules:** the floor renders at native 1× (64px world lattice). All
  standing props belong to the 48px class rendered at 2× — a prop sheet is
  authored at 96/80/72px and nearest-downsampled to 48/40/36. Floor detail
  must therefore stay *finer* than prop detail: a crack on the floor is 1–2
  texels, a plank edge on a crate is 2 screen px.
- The board lays diamonds edge to edge in large patches, half of them
  mirrored. Every tile must read as *continuous ground* at 100% zoom, not as
  an object sitting on the screen.
- **Texel-density target (2026-08-15, hi-res program):** every population
  renders at **1.0 px/texel at zoom 1.0** — floors already do; units and
  props get there by authoring on a doubled canvas drawn at 1× (units:
  60→120, 64→128, 56→112, feet 24–32 below centre, ≤128 colours, binary
  alpha, per-kind `Unit.SPRITE_SPECS` flipping to scale 1× / doubled offset
  as each set lands). The single exception is **structures, which stay at
  2×** by API-cap necessity (the building-kit generator tops out below the
  needed canvas); everything else drawing at 2× is a migration remnant, not
  a target. **Status (2026-08-15): hi-res unit program suspended by user
  verdict — 2×-class remains the standard** (see changelog: HD Rodar and
  Scout were shipped, then reverted at the in-game gate).

## 2. Light

- **Sun from the upper left**, shadows falling down and to the right. Every
  prop and unit shadow in the game is drawn that way; a sheet lit from
  anywhere else fights them all.
- **No baked cast shadows on floors.** Floors receive shadows from the
  engine (prop contact shadows, structure diamonds). A floor tile may have
  *texture* shading (crack interiors darker, ripple crests lighter) but never
  a directional cast shadow from an imagined object.
- Accent tiles that contain a real object (plant tuft, log, grate) may shade
  that object directionally — which makes them asymmetric, which is exactly
  what the sidecar `symmetric: false` flag records so the engine never
  mirrors them.

## 3. Tone contract

- **Mid-tone and low contrast**, always. Units, yellow movement highlights,
  red attack tiles, danger hatching and smoke are drawn *on top*; the ground
  must never compete. Rule of thumb: you could comfortably read black text on
  any tile.
- Per-biome numeric targets (mean masked luminance, ITU-601) live in
  [style.json](style.json) `biomes.*.lum_mean` — measured from the shipped
  sheets: desert 0.575, salt 0.601, ash 0.400, compound 0.548.
- All tiles of a sheet hold inside a **0.08 luminance spread** (shipped
  sheets sit at 0.047–0.056). Raw generations span ~0.39 — a chequerboard —
  which is why normalization is a pipeline stage, not a hope.
- **Ash is special:** brightening ash multiplies the warm sand underneath
  into embers. Ash is desaturated to 0.45 and normalized to a 0.40 mean only,
  keeping it cold and long-dead.

## 4. Outline policy

- **Floors: NO outlines, ever.** The shipped sheets carry a ~2px near-black
  rim on every diamond (ring/interior luminance ratio ≈0.60 on desert;
  healthy is ≥0.90) and the board reads as a lattice of outlined objects —
  this is the number-one measured defect. The generator's `segmentation`
  outline mode paints these rims; the pipeline's rim inward-fill removes
  them; the validator rejects any tile where they survive. Prompts must never
  ask for edges, and must actively forbid them (see §7 forbidden words).
- **Props and units: near-black rim outline** — that is the house sprite
  style and it is what makes them pop *against* the rimless floor. The
  contrast between outlined objects and un-outlined ground is deliberate.

## 5. Palette anchors

Dominant colors sampled from the shipped sheets (median-cut over masked
pixels; swatch sheet at [reference/palette.png](reference/palette.png)):

| Biome | Anchors |
|---|---|
| desert | `#e5aa61` `#e9b569` `#d69d5f` `#e2b271` |
| salt | `#c7bdab` `#998e7d` `#b5ae9e` `#aaa596` |
| ash | `#98908c` `#5d595a` `#747070` `#303032` |
| compound | `#a29785` `#4b423f` `#9e9280` `#9f9584` |

**Warm grit rule:** every biome keeps some warm sand in the palette. The
rocks, rusted junk, cacti and buildings are desert-toned and reused on every
map; a little `#d69d5f`-family grit showing through keeps them sitting
naturally on any ground. Salt shows it as beige staining, ash as scorched
pink-tan patches under the char, compound as sand blown across the slabs.

Palette budget: ≤96 unique colors per tile (post clamps, validator gates).

## 6. Slot role table — the 18-slot sheet

Sheets grow from 10 to **18 slots**: per zone (A soft / B mid / C harsh),
**4 base + 2 accents**. Grid: **4 cols × 5 rows at 129px stride**, sheet
**515×644**, diamonds at x = 0/129/258/387, y = 34/163/292/421/550. All slots
are uniform 128×60 (the desert plant accent moves in-diamond; the 128×66
slot-6 special case is retired and desert joins `TILE_REGIONS_FLAT`).

| Slot | Grid | Zone | Role |
|---|---|---|---|
| 0–3 | row 1 | A (softest) | base ×4 |
| 4–7 | row 2 | B (middle) | base ×4 |
| 8–11 | row 3 | C (harshest) | base ×4 |
| 12, 13 | row 4, cols 1–2 | A | accent ×2 |
| 14, 15 | row 4, cols 3–4 | B | accent ×2 |
| 16, 17 | row 5, cols 1–2 | C | accent ×2 |
| — | row 5, cols 3–4 | | unused |

Roles: **base** tiles are anonymous ground — nothing on them the eye can
count. **Accent** tiles carry one themed object or feature, pushed to the
tile center with plain edges, scattered by the engine at ~7% with minimum
spacing. Zone A→C runs softest→harshest ground within the biome's story.
The engine reads zone/role from the sidecar, so slot order is convention,
not code — but keep this order anyway; humans read the sheets too.

## 7. Per-biome prompt fragments

Shared prefix for every floor call (proven wording from record `2f2213cd`):
*"flat top-down desert ground tile, completely flat terrain, no thickness, no
side faces, lit softly from the upper left, muted mid-tone pixel art, seamless
edge-to-edge texture"* — adjust "desert" per biome.

**Forbidden words in any floor prompt** (they summon the rim/extrusion
defects): border, outline, frame, wall, edge, edge highlight, rim, ledge,
cliff, raised, 3D, block, cube, platform.

Numbered prompts: every tile in a call gets its own numbered line
(`1. …`, `2. …`); the generator honors per-tile intent far better than one
blanket sentence.

### desert — cracked hardpan under a hot sky
- Vocabulary: warm ochre sand, cracked clay hardpan, fine pebbles, dry silt,
  wind ripples, bleached driftwood, hardy desert grass tuft, dusty crater.
- Zone A (soft): rippled sand wash, faint shallow cracks under drifted sand.
- Zone B (mid): lightly cracked hardpan, scattered pebbles, patches of silt.
- Zone C (harsh): dense fine crack networks, mottled baked clay plates.
- Accents: A — small green-grey grass tuft, drawn inside the diamond;
  B — sun-bleached log fragment / wood debris; C — shallow dusty crater.

### salt — the dead pan
- Vocabulary: pale salt crust, crazed polygon plates, powdery gypsum, brine
  stain, mineral nodules, grey-beige dust, dead twigs.
- Zone A (soft): smooth powder pan, faint wind streaks, dusty film.
- Zone B (mid): nodular salt crust, crazed small polygons, beige brine
  staining bleeding through.
- Zone C (harsh): large fractured crust plates, deep dark crack seams.
- Accents: A — dark still brine pool sunk into the crust; B — scatter of
  dead grey twigs; C — collapsed crust sinkhole with dark center.

### ash — burnt ground, long cold
- Vocabulary: cold grey ash drifts, charred crust, soot mottle, burnt
  stubble, scorched pink-tan earth showing through, cinders.
- Zone A (soft): smooth ash drifts, soft grey, barely marked.
- Zone B (mid): patchy char over scorched warm earth — the warm grit rule
  lives here, pink-tan ground under broken soot cover.
- Zone C (harsh): charred crack networks, burnt crust plates, cinder seams.
- Accents: A — scorched dead cactus / burnt shrub skeleton; B — charred
  branch and bone fragments lying flat; C — burn crater with radiating soot
  streaks.
- Post special-case: desaturate 0.45, normalize to 0.40 mean (never brighter).

### compound — poured concrete hardstanding
- Vocabulary: weathered concrete slabs, expansion joints, hairline cracks,
  oil stains, tire scuffs, patched aggregate, dusty sand blown into corners.
- Zone A (soft): smoother poured slabs, light dust film, faint joints.
- Zone B (mid): jointed slabs, hairline cracks, stains, sand in the joints.
- Zone C (harsh): shattered slab, exposed aggregate, heavy crack webs.
- Accents: A — recessed steel drainage grate, flush with the surface;
  B — dark oil stain cluster; C — radial impact-star crack.

### new-biome template
```
### <name> — <one-line character>
- Vocabulary: <6–10 concrete nouns/adjectives in the biome's register>
- Zone A (soft): <the biome's gentlest walkable surface>
- Zone B (mid): <the default ground — most of the map>
- Zone C (harsh): <the broken/extreme version>
- Accents: A — <organic/soft feature>; B — <debris/object>; C — <damage/void>
- Post special-case: <none, or desat/mean overrides — add to style.json>
- Palette anchors: <sample after first accepted batch>
```

## 8. Reference-image strategy

- Golden references are stored **RAW at 128×128, pre-squash**, in
  `artgen/reference/<biome>/` — the generator works at 1:1, so references
  must be 1:1 too. Post-squash 128×60 art is never a generation reference.
- Every generation call passes the biome's base references (up to the tool's
  limit, base tiles preferred over accents) via `style_images`/reference
  inputs where the mode supports it. Note `tile_feature: "tileset"` mode
  cannot take style images — transitions rely on prompt + seed instead.
- A **new biome bootstraps from desert** references (the palette bridge —
  warm grit is in every biome), then its own first accepted batch replaces
  them: promotion with `--as-reference` copies accepted raws into the
  biome's reference dir.
- References are provenance: never edit them in place. A better tile
  replaces the file through `promote`, which logs it in the manifest archive.
- **Anything passed as `style_images` must be CLEAN.** Style mode copies
  shape + size from its refs (verified live) — a rimmed raw reference clones
  the rim straight back into the new tile. Refs for style-mode top-ups are
  2–3 accepted tiles, post-processed rim-free, at native 128×128 (rim
  inward-fill applied, no squash). The raws in `reference/` are provenance
  and 1:1 shape context; clean them before they touch `style_images`.

## 9. Generation recipe

- **Base tiles:** `create_tiles_pro` **shape mode** (never style mode for
  full sheets — style mode returns extruded side faces inset in the canvas),
  `tile_type: "isometric"`, `tile_size: 128`, `tile_view: "top-down"`,
  `tile_depth_ratio: 0`, `tile_flat_top_px: 4`,
  `outline_mode: "segmentation"`, numbered prompts (§7).
  **`tile_depth_ratio: 0` is mandatory on every flat-floor call** — without
  it, isometric mode returns extruded 3D slabs.
- **One call yields at most 6 variants at 128px — silently.** Never send
  more than 6 numbered prompts per call; prompts 7+ are discarded with no
  error (a 10-prompt call wastes 4 prompts). An 18-slot sheet is exactly
  3 calls of 6: slots 0–5, 6–11, 12–17.
- **Seeds are fixed per biome** (style.json): desert 101, salt 102, ash 103,
  compound 104. A retry adds **+1000·attempt** (attempt 1 retry of desert =
  1101, attempt 2 = 2101) so no run is unreproducible and no retry collides.
- **Transitions:** `create_tiles_pro` with `tile_feature: "tileset"`,
  `tile_type: "isometric"`, `tile_size: 96`, and the same flat params
  (`tile_view: "top-down"`, `tile_depth_ratio: 0`, `tile_flat_top_px: 4`) —
  16-tile corner sets. **96 is the hard API cap** for isometric tilesets:
  tiles come back 96×96 and are Lanczos-upscaled ×4/3 to 128×128 in post
  *before* the squash. Transition seeds: 2xx block. Prompts open with
  `"<first terrain> to <second terrain>:"` — the FIRST-named terrain is what
  the mask bits refer to (mask = NW<<3 | NE<<2 | SW<<1 | SE, bit set = first
  terrain at that corner; grid→screen NW→top, NE→right, SE→bottom, SW→left).
  Broken tiles in a set are fixed by regenerating the WHOLE set with a new
  seed and cherry-picking — tileset mode can't do single tiles and can't
  take style refs.
- **Paths/roads:** `create_path_tiles` isometric 96px (per-tile N/E/S/W edge
  bitmask metadata) → same ×4/3 upscale → standard chain. Seeds: 3xx block.
  **Roads are risky:** one live call returned unusable fragmented-3D tiles;
  the working reference is record `f9426fe8` ("cracked desert with a dirt
  road"). Always eyeball the raw contact sheet before running post.
- **Single-slot regens (top-ups):** style mode with 2–3 accepted **cleaned**
  tiles as `style_images` — post-processed, rim-free, native 128×128 (§8).
  P4 verdict: style mode copies shape + size from its refs, so clean refs
  work and rimmed raws clone the rim back in. Fallback: fresh-seed shape
  mode with the retry offset. Three failed regens of the same slot = stop
  and escalate, don't thrash.
- Segmentation mode paints the rims we then remove; that is accepted — the
  rim inward-fill stage exists for it. What segmentation must never be asked
  to do is draw *internal* borders (see the ridge detector in the validator).
- Map objects (`create_map_object`) expire **8 hours** after generation —
  download immediately on completion, never batch downloads at the end.

## 10. Review rubric (per batch, Claude reads the viewer PNGs)

Judge the `_seams.png` / `_slots.png` / `_compare.png` from
`make_tile_viewer.py` against these, in order:

1. **Seams invisible at 100%?** In each 3×3 patch, can you find the diamond
   boundaries without knowing where they are? If yes → fail the slots on the
   visible edge.
2. **Luminance chequerboard?** Squint (or downscale 4×): does the patch read
   as one surface or as light/dark tiles alternating? 
3. **Rim pixels?** Any dark lattice line along diamond edges, even partial.
4. **Accent legible?** Each accent readable as its object at 100% zoom, and
   contained — nothing crossing the tile edge.
5. **Drift vs the compare row?** New tiles sit next to shipped ones without
   a visible style break (palette, crack scale, dither density).
6. **Warm grit present?** The biome shows its warm-sand component (§5).

Verdicts are per-slot (`accept` / `regen` + reason) into the batch manifest;
`promote` refuses while any slot lacks an accept.

## 11. Changelog

Every accepted deviation from this document gets a dated line here — this is
the anti-drift mechanism. Style questions are settled by appending, never by
silent edits above.

- **2026-08-18** — **Machinegunner repointed to the `Hero_MachineGunner`
  set.** Brukk Meshan (`Unit.Kind.MACHINEGUNNER`, raw ordinal 2) now draws
  `assets/sprites/Hero_MachineGunner/`, which had sat imported and referenced
  by zero `.gd`/`.tscn` files since 2026-08-15. **The folder name is
  historical and it misleads:** `Hero_MachineGunner/` is the PixelLab
  "Hero_bandana" group and it is *Brukk's* art. `Kind.HERO` (ordinal 9) is
  Rodar Akai, whose art is `Rodar_Akai/`. Read the metadata.json line in the
  2026-08-15 scaffolding entry below with that correction in hand — "shipped
  hero art" there means this machinegunner set, not the hero's. The set is
  **canonical layout** (UNIT_ASSET_SPEC.md §4): unit folder
  `Hero_MachineGunner/`, base state nested one level below it as
  `Hero_MachineGunner/Hero_MachineGunner/` (`rotations/` plus seven
  `animations/` sets), with `ReadyToFire_Stance/` and `Dead_stance/` at the
  top level and the aim-idle spelled `standing-readyToFire_idle`. That nesting
  is why `Unit.gd` carries two consts: `MG_ROOT` for the two top-level
  stances, `MG_BASE` (= `MG_ROOT + "/Hero_MachineGunner"`) for the base
  rotations and animations. Measured: 600 PNGs, all 60×60, 8 animation sets,
  palette max 48 colours, feet 14 px below canvas centre in all 8 standing
  rotations — bbox-identical to the Scout set's, so `SPRITE_SPECS` DEFAULT
  still applies and `MACHINEGUNNER` needs no entry. Its ReadyToFire stance
  sits 1 texel higher than its own standing stance (feet 13 in seven facings,
  16 on south); the outgoing `Scout_MachineGunner`'s was 14 → 14/17. The
  project gate wants 12–16, so the swap moves that stance **into** spec
  (13–16 passes, 14–17 failed). `GUNNER_MUZZLE_OFFSETS` re-measured with
  `measure_muzzle.gd`'s GUNNER entry repointed to the Hero aim rotations:
  7 of 8 facings now measure exactly and only "south" carries the documented
  hand-correction, per the Rodar/Scout precedent (the scan lands on boots
  there). **Ejecta repaired before shipping** — the aim-idle threw *detached*
  debris: a 35 px object beside him for 5 frames of 9 in north-west, and a
  puff drifting off in east. Both deleted rather than grafted back, because a
  disconnected lump cannot take a pixel of the soldier with it;
  `tools/fix_idle_flash.py` grew a third "debris" detector for the case. The
  standing rule this enforces: **an idle loop must not show the weapon
  working.** ReadyToFire idle is a soldier holding aim — muzzle flash, smoke
  and ejected brass belong to the firing beat, and on a loop they read as the
  gun going off forever. The retired `Scout_MachineGunner/` set **stays on
  disk on purpose**: with `Scout/` and `Scout_TeamLead/` it is the generic
  Kestrel troop art — bodies for cut scenes, for making a garrison feel
  inhabited, and for missions where another squad fights alongside the
  player's. It only stops backing a named soldier. (Its 688-PNG count is 600
  plus 88 top-level duplicates: `Dead_Stance/` and `ReadyToFire_Stance/` are
  byte-identical copies of the nested ones.) New checks, all in `tools/`:
  `check_unit_art.gd` asserts every `Unit.Kind` actually loaded its 11 frame
  sets — the loaders fail silently, so nothing caught an empty set before;
  `check_res_case.py` asserts every `res://` asset path matches the disk's own
  casing, because Windows resolves a wrong case at the OS level and a
  mis-cased path works locally and breaks only in an exported PCK;
  `check_unit_complete.py` was matching stance folder names case-sensitively
  and so picked `Scout_MachineGunner`'s `Dead_Stance` (capital S) as the base
  state, reporting PASS over 96 of that unit's 688 files — now
  case-insensitive, it reads 8 animation sets / 600 PNGs there. Watch items,
  older art, not fixed and nobody asked: `Rodar_Akai`'s aim-idle north-west
  frame 8 carries a 13 px white smoke puff, and `Goblin_revolver`'s east
  aim-idle grows one behind his head across frames 2–6 — same defect family
  as the ejecta above.
- **2026-08-15** — **HD Rodar + Scout REVERTED by user verdict** — the art
  direction was rejected at the in-game gate (models/animations), overruling
  the earlier judge accepts below. Both 60px originals restored exactly from
  the batch's `backup_originals/` (Rodar 600 PNGs sha1-verified, canonical
  layout unchanged; Scout back on its ROOT layout — rotations on the folder
  root, `Standing_Ready_to_fire_stance`, `Standing_idle_walk` casing,
  `standing_idle_to_ready_to_fire`, `standing_ready_to_fire_idle`,
  `dead_stance` — byte-identical to git HEAD, original .import files
  carried back with it). Wiring reverted: `SPRITE_SPECS` drops the
  `Kind.HERO` / `Kind.SCOUT` hi-res entries (both fall back to DEFAULT 2× /
  (0,−15); the table itself stays as migration scaffolding), the 11
  `SCOUT_*` loader paths return to the root layout, and both muzzle tables
  return to their pre-HD 60px values; `measure_muzzle.gd`'s SCOUT and RODAR
  entries measure the 60px assets again (canvas 60, scale 2, offset
  (0,−15)). The HD sets are **parked, not deleted**: 600 PNGs per unit
  remain in the batch's `<unit>/post/`, sha1-verified against the promoted
  trees before the revert (`reverted` records in both manifests). The
  **Goblin hi-res pilot is halted mid-ladder**; the display uplift (1080p
  window, zoom 1.0) ships regardless. The §1 texel-density target carries a
  suspension note — the hi-res unit program stops here by user verdict, and
  the 2×-class look remains the standard.
- **2026-08-15** — **HD Scout shipped** (batch `units-hires-2026-08-15`,
  168 generations, judge-accepted, validator v2 hires-120 PASS on the
  promoted path). Second unit at the §1 density target: 120px canvas drawn
  at 1× — `SPRITE_SPECS[Kind.SCOUT]` flips to scale (1,1) / offset (0,−30),
  same screen anchor as the 60px set it replaces. Unlike Rodar, the legacy
  Scout was a ROOT-layout unit (rotations on the folder root, odd stance
  spellings), so the promoted canonical tree (`Scout/Scout`,
  `ReadyToFire_Stance`, `Dead_stance`) moved all 11 `SCOUT_*` loader paths
  in Unit.gd; all 601 originals were archived to the batch's
  `backup_originals/Scout/` before the old tree was cleared, and its four
  regen-strike review slots were re-filed as accepted supersession records
  (history kept in the reasons) to open the promote gate. Accepted
  deviations, judge-ruled: the +4px RTF up-shift, the scrubbed damage-SW,
  the mirrored RTF-north barrel (screen-right), and the **lying-profile dead
  style** — profile corpses match the shipped Rodar precedent, the legacy
  overhead-sprawl drawing retires, and remaining legacy sprawls converge as
  the roster regenerates. `SCOUT_MUZZLE_OFFSETS` re-measured at native
  scale; the southern trio is hand-read off the art per the Rodar precedent
  (the scan lands on boots there — it reproduced the legacy boot-line
  values to within 1–2px): SE rifle level right (tip px 91,50) → (31,−40),
  S gunmetal bore highlight at the chest (px 56,53) → (−4,−37), SW mirrored
  down-left hold (tip px 26,50) → (−34,−40). `measure_muzzle.gd`'s SCOUT
  entry now measures the promoted 120px assets (the legacy 60px entry and
  the SCOUT_HD_STAGING judge entry both retire); in-engine judge shots
  (battle full board, staged scout-beside-goblin density pair, squad-side
  density line against the still-2× machinegunner, staged east muzzle
  flash at the barrel) live in the batch's `Scout/preview/`.
- **2026-08-15** — **HD Rodar shipped** (batch `units-hires-2026-08-15`,
  144 generations, judge-accepted 13/13 slots, validator v2 hires-120 PASS).
  First unit at the §1 density target: 120px canvas drawn at 1× —
  `SPRITE_SPECS[Kind.HERO]` flips to scale (1,1) / offset (0,−30), same
  screen anchor as the 60px set it replaces (all 600 originals archived to
  the batch's `backup_originals/`; layout was already canonical, so paths
  and .import files carried over unchanged). `RODAR_MUZZLE_OFFSETS`
  re-measured at native scale; the southern trio is hand-read off the art
  per the lead's precedent (the scan lands on boots): SE holds the rifle
  nearly level right (37,−40), S is the drawn bore highlight dead centre
  (−1,−29), SW is a compact down-left hold (−28,−40). `measure_muzzle.gd`'s
  RODAR entry now measures the promoted 120px assets; in-engine judge shots
  (battle, density pair vs a 2× scout, staged east muzzle flash, garrison
  avatar) live in the batch's `preview/`.
- **2026-08-15** — **Hi-res pipeline scaffolding (Phase 2a, zero generations).**
  §1 gains the texel-density target: all populations at 1.0 px/texel at zoom
  1.0, structures excepted (API cap). Tooling made density-aware ahead of any
  art: `validate_unit_sprites.py` v2 (per-set spec table — 64/56 canvases
  validatable at last, palette informational for legacy, hard 128/160 gate +
  metadata.json required for hi-res), `measure_muzzle.gd` v2 (per-entry
  {canvas, scale, offset}, byte-identical parity with v1 verified, delta
  table vs Unit.gd), `make_char_viewer.py` density-aware + `--compare`
  old-vs-new judge view, `pixellab_batch.py --kind unit` (per-unit staging,
  provenance fields, promote archives overwritten originals to
  backup_originals/). UNIT_ASSET_SPEC.md v2 published. metadata.json
  backfilled for Scout / Goblin / Rodar_Akai / Hero_MachineGunner with
  pixel-verified ids (notable: shipped hero art lives in the
  Scout_MachineGunner group as Hero_bandana states; both hero and Rodar dead
  stances are the death animation's final frame).
- **2026-08-14** — **Salt promoted** (18-slot base sheet + both transition
  sets, merged sidecar, FLOOR_MOODS re-derived — accent cadence moves
  0.06/2 → 0.04/4 because the rebuilt zone0 powder pan is nearly featureless
  and its accents shout; tint/haze/shadow move a final digit, gain holds at
  the recipe 0.96). Accepted deviation: **trans-12 is a v4
  symmetry-completed set** — delivery `5fca231a` (seed 3204, same-tone
  terrain identity) arrived mask-degenerate per its own metadata AND
  empirics (12 usable masks, {7,12,13,14} absent; strike 4 art on this set
  after `8a0d5622`/`a1d9756e`/`caa0e49e`), so the four missing masks were
  synthesized from verified v4 raws: 12 = H-flip(mask-10), 13 =
  H-flip(mask-11), 14 = rot90-CW(mask-11), 7 = rot90-CW(synth 13)
  (unsquash ×2 → ROTATE_270 → resquash, re-masked); full provenance in the
  sidecar, every synth re-classified empirically (16/16, margins 19–43).
  Known signature: mixed tiles' pale corners render +0.03..+0.14 vs
  pure-pale (crust-margin bloom, same family as the accepted trans-01's
  +0.05 — a single per-tile gain cannot compress the raw class contrast).
  Watch items standing: **cold-blue crack cast on zoneC**, brine smudge
  repeats, trans-12 dark_ridge WARN is the seam motif itself (2221 px on
  pure-dense, non-defect).
- **2026-08-14** — **Prop regrade APPLIED to assets/** (staging
  `artgen/staging/prop-regrade-2026-08-14/`, coordinator-approved; 249
  originals overwritten, all backed up under the batch's
  `backup_originals/`). Interior-only grade toward the desert floor anchor
  (#a58f72): **G2** default (sat 0.82 / warm 0.20 / black 0.11 / gain 1.04),
  **G3** for junk (0.75 / 0.30 / 0.16 / 1.08), **G1** for fortress +
  briefing (0.90 / 0.10 / 0.06 / 1.00), fuel drums G2 with a red-preserving
  override (sat 0.86 / warm 0.15). **Skirt recolors** (tent + relay mast):
  recolor not alpha-trim, bottom-of-bbox warm-sand selection remapped to the
  floor anchor before the class regrade. Money cache + drug still frames
  replaced with 48-canvas Lanczos+palette-clamp downsamples. Three
  regenerated props placed beside their originals (unwired, originals
  kept): junk statue `statue_c2_48.png` (48), rune tech `rune_c2_48.png`
  (48), market stall `stall_c2_68native.png` (68 native — at 48 it reads
  crate-sized). Logged follow-ups: statue torn_state and rune-tech
  normal_idle glow frames not regenerated. Verified: import clean, boot
  smoke clean, cover canary PASS, engine screenshots (Scrapline / Outpost 7
  / garrison) read correctly — props sit into the muted floor, drums still
  read hazard red, skirts blend.
- **2026-08-14** — Phase 4 rollout: **ash and compound promoted** (18-slot
  base sheets + both transition sets each, merged sidecars, FLOOR_MOODS
  re-derived via `tools/derive_floor_mood.gd`). Accepted deviations —
  **ash**: trans-12 mask 3 is a horizontal mirror-synth of the accepted
  mask-5 tile (screen L-R flip swaps NE↔SW; regen `671b8181` rejected
  wholesale); base slots 4/7/15 swapped to the zoneBfix repairs; FLOOR_MOODS
  keeps the hand-tuned cold-dead intent (tint pinned neutral against the
  recipe's 1.01 warm read, haze keeps the ~10% burnt-bowl darkening, gain
  keeps the 1.50 readability nudge) while accent cadence follows the new
  sheet (0.05 / spacing 3). **compound**: trans-12 mask 3 likewise
  mirror-synthed from its mask-5 tile (`712844b9` art kept for the other 15
  masks); strike regens `696af086` (seed 1209, reproduced the defect) and
  `5e390648` (seed 2209, fixed mask 3 at the cost of tone drift) both logged
  unused; the cross-set **+0.025 bright** delta vs `Desert_to_compound`
  stands as a watch item. **Salt NOT promoted** — base + trans-01 accepted
  (watch items: cold-blue crack cast on zoneC, brine smudge repeats) but the
  trans-12 v3 replacement (`caa0e49e`, seed 2204, same-tone terrain-identity
  fix) arrived **mask-degenerate**: 7 distinct masks of 16, confirmed both
  empirically and by PixelLab's own metadata; strike 3 on the set, promote
  gate closed in the manifest, escalated. Building-kit verdict: 96→128
  upscale viable on low-contrast concrete (probe `eb297a56`); integration
  deferred — existing walls read well on the new floors.
- **2026-08-14** — Desert promoted: 18-slot base sheet + 3 transition sets
  (zone0↔zone1, zone1↔zone2, desert↔compound, merged into
  `Cracked_Desert_floor.tiles.json` with per-set `res://` sheets) + 18-tile
  road sheet. Accepted deviations: (a) trans-12 shows a pale crust-edge
  boundary highlight; (b) zone1-accent ground hue reads slightly warmer than
  the fix1 zone1 bases — watch item for a future top-up; (c) road sheet keeps
  a warmer pre-style surround (record `f9426fe8`, unwired until Phase 4).
- **2026-08-14** — First full desert batch through the pipeline; the
  operational findings, now folded into §§1/8/9 and PIPELINE.md:
  (a) 128px `create_tiles_pro` **silently caps at 6 variants per call** no
  matter how many numbered prompts are sent — the pre-pipeline ASSETS.md
  "six per call" was right and the probe-era 10-variant reading wrong; ≤6
  prompts per call, 18 slots = 3 calls; (b) `tile_depth_ratio: 0` is
  mandatory on every flat-floor call — omitted, isometric mode returns
  extruded slabs; (c) isometric tileset mode hard-caps at `tile_size: 96`;
  transition prompts open `"<first> to <second>:"` and the first-named
  terrain owns the mask bits (NW<<3|NE<<2|SW<<1|SE; NW→top, NE→right,
  SE→bottom, SW→left) — verified by classifying every tile's corner regions
  against the pure tiles (expect 100%; mismatches are broken tiles, not a
  remap); (d) broken tiles inside a 16-tile set: regen the whole set
  (+1000·attempt) and cherry-pick; base-sheet slots: style-mode top-ups
  with CLEANED rim-free 128×128 refs — P4 verdict is that style mode copies
  shape+size from refs, so rimmed raws clone the rim back; (e) one live
  `create_path_tiles` call returned fragmented-3D junk — roads are
  eyeball-before-post risky; working reference `f9426fe8`; (f) cost ≈20–40
  generations per call (40 at 4K); a full biome (3 base + 2 transition
  calls) ≈ 200; log balance at init/close. Standing reminder proven twice
  this batch: validator PASS does not waive the §10 PNG read — the metric
  tolerance cannot see a transition tile with a missing dark half or a
  wrong-corner layout.
- **2026-08-14** — P3 dry-run calibration (records `b01a283b` base +
  `f9426fe8` paths, zero generation cost). Four accepted findings:
  (a) verified records return the diamond **already squashed 2:1** inside
  the square canvas (128×60-in-128×128; paths 96×48-in-96×96) — ASSETS.md's
  "comes back as a 1:1 diamond" is not universal, so the post chain crops to
  the alpha bbox and resizes to 128×60 in one step, handling 1:1, 2:1 and
  96px inputs alike; (b) post order is **normalize, then harmonize** — the
  reverse biased every ring up to +10% bright on dark-textured tiles;
  (c) the validator's rim denominator is the 4–8 px shoulder band, not the
  whole interior — a dark road through the middle skewed whole-interior
  ratios to a false 1.17 on defect-free path tiles; (d) shipped desert vs
  post-processed same-record output: rim 0.543–0.666 → 1.008–1.086, seam
  1.55–1.62× → 0.33–0.49×. The audit's "5.2×" seam figure did not reproduce
  under the validator's TV-profile metric; the shipped defect reads ≈1.6×
  there and still fails the ≤1.5 gate, so the gate stands.
- **2026-08-14** — Initial version. Measured from the shipped 10-slot
  sheets: biome luminance means desert 0.5746 / salt 0.6006 / ash 0.3993 /
  compound 0.5478; canonical diamond mask extracted from desert slot 0
  (salt/ash/compound match it pixel-exactly on all 30 slots; desert's own
  slots 1–9 drift 1–53 px and slot 6 overhangs — both retire with the next
  desert sheet). Defect baselines this pipeline exists to fix: rim
  ring/interior ratio ≈0.60 (healthy ≥0.90), cross-boundary seam
  discontinuity ≈5.2× within-tile baseline (target ≤1.5×), raw generation
  luminance spread 0.394 (target ≤0.08). 18-slot layout adopted (§6).
