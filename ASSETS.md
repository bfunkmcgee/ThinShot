# ThinShot — asset wishlist

What to generate next in Pixel Lab, ordered by **gameplay unlocked per hour of
your time**. Each entry says what it buys, the format to match, and whether it
drops straight in or needs code first.

**The cost rule:** props are cheap and units are expensive. A prop is one 48×48
PNG. A unit is 8 directions × 11 animation sets — 88 folders — plus three
rotation sets. So a single new prop that unlocks an objective type is usually
worth more than a fourth goblin.

## Formats already in use

| Kind | Canvas | Layout |
|---|---|---|
| Ground prop (rock, junk, plant) | **48×48** | one PNG, drawn flat on the cell |
| Wall | **68×68** | `rotations/<8 names>.png`, named by the wall's *facing* |
| Structure, 2×2 footprint | **168×168** | `rotations/unknown.png` + optional `animations/<any name>/unknown/frame_%03d.png` |
| Structure, 4×4 footprint | **256×256** | as above |
| Floor tilesheet | **515×386** | ten 128×60 diamonds, 129px stride, rows at y 34 / 163 / 292 (one row is 66px tall for overhanging detail) |
| Unit | **56–64 px** | 8 directions × `standing_idle`, `_alt`, `_walk`, `_to_readyToFire`, `_to_dead`, `_damage`, `_reload`, plus `readyToFire` idle, and `rotations/` for idle / aim / dead |

---

## Tier 1 — fixes something currently faked (do these first)

| # | Asset | Buys | Code |
|---|---|---|---|
| 1 | **Supply cache / ammo crate** — 48×48, plus a **blown-open variant** | Tithe caches currently reuse a *tinted scrap pile* on maps deliberately covered in scrap piles. That is why they were hard to find. A real crate fixes the confusion at its source, and a wrecked variant means a demolished cache leaves a mark instead of vanishing. | drop-in |
| 2 | **Gate** — 68×68, matching the wall set: **closed / open / blown** | The Scrapline's "gates" and Outpost 7's entrances are just *gaps in the wall*. A real gate makes them read as entrances, and unlocks **breaching**: a closed gate blocks movement until someone demolishes it, so the map has doors you have to open under fire. | small |
| 3 | **Sandbag emplacement** — 48×48, **intact / battered / destroyed** | Cover is permanent today. Three states unlock **destructible cover** — suppressing fire and frags degrade a position instead of leaving it identical all mission. | medium |
| 4 | **Compound floor tilesheet** — 515×386, concrete or flagstone | Outpost 7's interior is the same sand as the open desert, so the fortress does not read as *built*. A second sheet makes interiors feel like somewhere else. | small |

## Tier 2 — new mission types

| # | Asset | Buys | Code |
|---|---|---|---|
| 5 | **Civilian / prisoner** — unit format, but only needs `idle`, `walk`, `cower`, `to_dead` | **Rescue and escort objectives.** Reach them, then get them to the extraction zone alive. Slots straight into the objective list next to `destroy` and `extract`. | medium |
| 6 | **Comms mast / radio set** — 168×168 structure | "Destroy the transmitter", "hold the relay for N turns". A tall silhouette also gives maps a landmark to navigate by. | small |
| 7 | **Fuel drum / gas cylinder** — 48×48 + scorched variant | **Chain explosions.** Shoot or frag one and it detonates, so the battlefield has hazards you can turn on the Choir. Reuses the existing blast code. | small |
| 8 | **Vehicle wreck** — 168×168, 2×2 | A big multi-cell cover piece to fight around, and visual proof the desert had a war in it — which is exactly the campaign's story. | drop-in |
| 9 | **Extraction marker** — 48×48 signal panel or smoke pot | The extraction zone is tinted tiles. A physical marker makes the last objective a *place* rather than a colour. | drop-in |

## Tier 3 — units (expensive; pick one or two)

| # | Asset | Buys | Code |
|---|---|---|---|
| 10 | **Shielded goblin** — carrying a scrap-plate shield | Best gameplay-per-unit of any new soldier: it **makes flanking mandatory**. Immune or heavily resistant from the front, soft from the sides — and the facing/arc system that decides this already exists and is currently only used for cover and overwatch. | medium |
| 11 | **Goblin grenadier** — pipe bomb / satchel | Mirrors your frag back at you. Suddenly clustering your own squad is punished, which makes your spacing a decision. | medium |
| 12 | **Scout Sapper** — a sixth squad slot, demolition charges | The demolish action exists but no one specialises in it. A sapper who demolishes faster, or from a distance, makes the raid missions his to lead. | small |
| 13 | **Scout Medic** | Stabilise a downed soldier before the mission ends — the counterweight to permadeath, and the reason to take risks. | medium |
| 14 | **Goblin brute** — big, slow, melee | A unit you cannot solve by kiting. Forces the machinegunner and grenades to earn their keep. | medium |

## Tier 4 — variety and atmosphere

| # | Asset | Buys | Code |
|---|---|---|---|
| 15 | **Two more floor tilesheets** — 515×386 each. Suggested: **salt flat** (pale, glaring) and **ash / burnt ground** | The single biggest immersion win per asset. Every map is currently the same sand. Levels already carry `zone_seed`, `shade_seed` and `zone_thresholds` — add a sheet field and each mission can look like a different place. | small |
| 16 | **Track / road tiles** — 3–4 diamonds in the same sheet layout | The campaign's story is literally *follow the route back*. A visible road makes that legible on the map. | small |
| 17 | **Dead scrub, bones, tyre ruts, scorch decals** — 48×48 each, 4–6 of them | Cheap density. The prop scatter system already places these deterministically by cell. | drop-in |
| 18 | **Choir totems / banners** — 48×48, ideally with a 9-frame sway | The Rust Choir is a *cult* and nothing on the map says so. Territorial markers around the Scrapline would sell it. | drop-in |
| 19 | **Sandstorm overlay** — tileable band or a few drifting sheets | Weather that **cuts sight range** — reusing the exact `has_line_of_sight` path smoke already goes through, so it is far cheaper than it sounds, and it makes a mission feel like a different fight. | medium |

## Tier 5 — polish

- **Corpse variants** per goblin type so a battlefield reads as a battlefield.
- **Muzzle-flash sprites** — everything combat-related is code-drawn today; hand-drawn flashes would sharpen the shooting.
- **Night / dusk palettes** of the floor sheets, for a dawn assault on Outpost 7 that actually looks like dawn.

---

# Generating the two floor tilesheets

## What the code needs

The desert sheet is a **4 columns × 3 rows grid of 129×129 cells**, with a
**128×60 isometric diamond centred in each cell** (10 of the 12 cells used).
That is a normal tileset export — **you do not need to hit exact pixel
offsets.** Generate the same kind of sheet and I will measure the regions and
wire them up.

What *does* matter is the ten tiles' **roles**. The board sorts them into three
terrain zones by smooth noise, so neighbouring cells read as one patch of
ground, and sprinkles one themed accent per zone at 7% with a minimum spacing:

| Grid slot | Index | Role |
|---|---|---|
| row 1, cols 1–3 | 0, 1, 2 | **Zone B base** ×3 — the middle ground |
| row 1, col 4 | 3 | **Zone C base** A — the harshest ground |
| row 2, col 1 | 4 | **Zone C accent** |
| row 2, col 2 | 5 | **Zone C base** B |
| row 2, col 3 | 6 | **Zone A accent** — may overhang the diamond upward |
| row 2, col 4 | 7 | **Zone B accent** |
| row 3, cols 1–2 | 8, 9 | **Zone A base** ×2 — the softest ground |

So: **three zones running softest → harshest, two or three base variants each,
plus one accent per zone.** Keep that shape and any biome drops in.

## Constraints for every tile (this is the part that is easy to get wrong)

- **Isometric 2:1 diamond floor**, seen from above. Ground only — no walls, no
  raised edges, no perspective sides.
- **Sun from the upper left**, shadows falling down and to the right. Every prop
  and unit shadow in the game is drawn that way; a sheet lit from elsewhere will
  fight them.
- **Stay mid-tone and low contrast.** Units, yellow movement highlights, red
  attack tiles, danger hatching and smoke are all drawn *on top*. A blown-out
  white salt pan would swallow the movement highlight. Aim for something you
  could comfortably read black text on.
- **Tile seamlessly** — edges must meet neighbouring diamonds without a visible
  seam, since the board places these edge to edge in large patches.
- **Keep some warm sand in the palette.** The rocks, rusted junk, cacti and
  buildings are all desert-toned and are reused on every map. A little warm
  grit showing through keeps them sitting naturally on the new ground.

## Prompt 1 — SALT FLAT

> Isometric 2:1 diamond floor tiles for a top-down tactics game, pixel art. A
> dried-out desert salt pan: pale grey-white mineral crust over warm sand, with
> the sand showing through in patches. Muted and chalky rather than bright
> white. Lit by a low sun from the upper left. Flat ground only, seen from
> above, tiling seamlessly.

Then the ten tiles, softest to harshest:

| Index | Tile |
|---|---|
| 8, 9 | **Zone A base** — damp brine margin. Darker, faintly wet, grey-brown, smooth |
| 6 | **Zone A accent** — a shallow brine pool with a crusted white rim |
| 0, 1, 2 | **Zone B base** — dry salt crust with fine polygon cracking, sand in the cracks |
| 7 | **Zone B accent** — salt-crusted driftwood and dry sticks half buried |
| 3, 5 | **Zone C base** — thick heaved salt, brittle plates, deep crack lines |
| 4 | **Zone C accent** — a collapsed sinkhole, plates tipped inward |

## Prompt 2 — ASH AND BURNT GROUND

> Isometric 2:1 diamond floor tiles for a top-down tactics game, pixel art.
> Ground that burned a long time ago: grey ash and soot over scorched desert
> hardpan, warm sand still showing through where the ash is thin. Charcoal
> greys and browns, no bright orange. Lit by a low sun from the upper left.
> Flat ground only, seen from above, tiling seamlessly.

| Index | Tile |
|---|---|
| 8, 9 | **Zone A base** — soft grey ash drift, powdery, wind-rippled |
| 6 | **Zone A accent** — a charred stump or burnt scrub, black against the ash |
| 0, 1, 2 | **Zone B base** — scorched hardpan streaked with soot, sand showing through |
| 7 | **Zone B accent** — twisted burnt scrap and warped metal |
| 3, 5 | **Zone C base** — cracked charcoal crust, deep black fissures |
| 4 | **Zone C accent** — an old blast crater, ash blown outward in a ring |

Index 6 is the one that may **overhang the top of its diamond** — the desert
sheet's plant tuft does, and the code already allows that tile to be taller.

## Where to put them

```
assets/Tiles/Environments/Salt/Salt_flat_floor.png
assets/Tiles/Environments/Ash/Ash_burnt_floor.png
```

Matching the existing
`assets/Tiles/Environments/Desert/Cracked_Desert_floor.png`.

## What I will do with them

Measure each sheet's regions, turn the currently hard-coded `FLOOR_SHEET` and
`TILE_REGIONS` into a per-sheet table, and add a `floor` field to the level
data so each mission picks its own ground — alongside the `zone_seed`,
`shade_seed` and `zone_thresholds` the levels already carry. Small change; the
whole zone system is already parameterised.

---

## If you only do three

**1 (supply cache)**, **15 (two floor sheets)**, **10 (shielded goblin)** — one
fixes the objective players could not find, one makes three missions look like
three places, and one turns the flanking rules from a detail into the point.
