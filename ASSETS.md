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

## If you only do three

**1 (supply cache)**, **15 (two floor sheets)**, **10 (shielded goblin)** — one
fixes the objective players could not find, one makes three missions look like
three places, and one turns the flanking rules from a detail into the point.
