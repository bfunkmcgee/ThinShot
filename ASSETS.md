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
| Ground **decal** (bones, scorch, signal panel) | **48×48** | one PNG, drawn at **1×** on the Board's decal layer, centred on its own paint |
| **Tall** single-cell prop (mast, flagpole, watchtower) | **168×168** | one PNG, drawn at 2× on ONE cell — a structure's canvas without a structure's footprint. Anchor `-(bbox.bottom − 85)`, not the 48px rule |
| Wall | **68×68** | `rotations/<8 names>.png`, named by the wall's *facing* |
| Structure, 2×2 footprint | **168×168** | `rotations/unknown.png` + optional `animations/<any name>/unknown/frame_%03d.png` |
| Structure, 4×4 footprint | **256×256** | as above |
| Floor tilesheet | **515×386** | ten 128×60 diamonds, 129px stride, rows at y 34 / 163 / 292 (one row is 66px tall for overhanging detail) |
| Unit | **56–64 px** | 8 directions × `standing_idle`, `_alt`, `_walk`, `_to_readyToFire`, `_to_dead`, `_damage`, `_reload`, plus `readyToFire` idle, and `rotations/` for idle / aim / dead |

---

## Tier 1 — fixes something currently faked (do these first)

> **Done:** #1 ammo crates, #6 comms mast and #7 fuel drum are generated and
> wired in. They live under `assets/sprites/Environment/Desert/Props/`, each as
> a standing pose, one or more destruction animations, and a wreck.

| # | Asset | Buys | Code |
|---|---|---|---|
| ~~1~~ | ~~**Supply cache / ammo crate**~~ — **done** | Tithe caches were a *tinted scrap pile* on maps covered in scrap piles, which is why they were hard to find. Now a real crate pile that plays its own 13-frame detonation and leaves wreckage behind. | shipped |
| 2 | **Gate** — 68×68, matching the wall set: **closed / open / blown** | The Scrapline's "gates" and Outpost 7's entrances are just *gaps in the wall*. A real gate makes them read as entrances, and unlocks **breaching**: a closed gate blocks movement until someone demolishes it, so the map has doors you have to open under fire. | small |
| 3 | **Sandbags — battered / destroyed states** (the intact prop is **done**, see 5c) | The prop shipped and the Thirst's prepared positions now read as prepared. What is still missing is the *states*: two more 56×56 poses would unlock **destructible cover**, letting suppressing fire and frags degrade a position over a mission instead of leaving it identical to the end. Cover is adjacency-based, so this is a per-cell tier downgrade rather than new geometry. | medium |
| ~~4~~ | ~~**Compound floor tilesheet**~~ — **done** | Outpost 7's interior was the same sand as the open desert, so the fortress did not read as *built*. Now weathered concrete hardstanding, drawn only inside the wall via the level's `floor_inset`, so the staging ground outside stays sand and breaching a gate puts you on concrete. | shipped |

## Tier 2 — new mission types

| # | Asset | Buys | Code |
|---|---|---|---|
| ~~5~~ | ~~**Civilian / prisoner**~~ — **done** | The `rescue` objective, and THE HOLDING PENS built on it. Ending a move beside one cuts them loose; the cower set swaps to the standing set and they walk out with the squad, counting for the extraction. | shipped |
| ~~5b~~ | ~~**Wire fence / pen**~~ — **done** | Better than asked for. Wire became its own cell kind (`'='`): it stops movement and *nothing else* — sight and fire cross it freely, and it shields nobody. The pen on THE HOLDING PENS is now the only enclosure in the game you can shoot into before you can walk into, which turns its one gate into the whole mission. | shipped |
| ~~5c~~ | ~~**Sandbags**~~ — **done** | `'s'`: mechanically identical to junk, tonally opposite. Junk is half cover nobody put there; sandbags are half cover somebody *dug*, so the Thirst's prepared positions now read as prepared — the outpost gate, the cistern gap, the pen gate. | shipped |
| ~~5d~~ | ~~**Dropped assault rifle**~~ — **done** | Its eight rotations exist to lie pointing somewhere. A fallen scout leaves their rifle on the cell they died on, facing the way they last faced. Only your own dead — eleven goblin rifles would be litter, five soldiers is a squad. | shipped |
| ~~6~~ | ~~**Comms mast / radio set**~~ — **done** | "SILENCE THE RELAY" on The Scrapline. Its three states made it the first **two-charge** objective: one charge buckles it into a leaning, sparking wreck, the second brings it down. | shipped |
| ~~7~~ | ~~**Fuel drum**~~ — **done** | Cover until a blast reaches it, then it detonates with a frag's force **and sets off the next drum along**. A line of them is a fuse. | shipped |
| ~~8~~ | ~~**Vehicle wreck**~~ — **done** | Two of them, on the hut's 2×2 footprint and blocking exactly as hard: a six-wheel cargo hauler and a split water tanker. The hauler is on THE HOLDING PENS, where it is the only hard cover on the walk back out with unarmed people at move 4, and where a dead hauler answers why the column was carrying water by hand. The tanker is on THE CISTERN's southern approach, which had no cover at all, so the breakthrough now has two lanes worth trying instead of one. | shipped |
| ~~9~~ | ~~**Extraction marker**~~ — **done** | An orange signal panel pegged flat, drawn as a **decal** on every extraction cell — flat, so five soldiers can finish the mission standing on the mark without hiding it — plus up to three staked banners on the open ground beside the zone. No level data: Battle reads the `extract` objective's own cells. | shipped |

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
| ~~15~~ | ~~**Two more floor tilesheets**~~ — **done** | Salt flat and ash are generated, wired and assigned: THE LONG HAUL and THE CISTERN are fought on the pan, THE CHOIRMASTER on burnt ground. Levels now carry a `floor` name alongside `zone_seed`, `shade_seed` and `zone_thresholds`, so re-skinning a mission is one line. | shipped |
| 16 | **Track / road tiles** — 3–4 diamonds in the same sheet layout | The campaign's story is literally *follow the route back*. A visible road makes that legible on the map. | small |
| ~~17~~ | ~~**Dead scrub, bones, tyre ruts, scorch decals**~~ — **done** | Eight of them: rib bones, a jawbone, a scorch ring, pottery shards, driftwood, a curled mud plate, a fallen cactus, buried corrugated iron. There was no scatter system to place them — props are per-map-char — so `Battle._spawn_decals` is new: 17% of the open sand, minimum one cell apart, hashed per cell so a board is stable, and it runs *last* so it only dresses ground the props, structures and caches did not claim. The camps scatter the same set off the same salts. | shipped |
| ~~18~~ | ~~**Thirst claim-stakes / well-markers**~~ — **done** | Four: an Assembly tally-board with the count cut into it, a bundle of staked claims with rag pennants, a post hung with a tin cup, a stone well-ring. Map char `'t'` — walkable decoration, the deal `'p'` gets — and they sway on the plants' wind rather than needing frames. Placed as tally-boards on THE SCRAPLINE, claims on THE CISTERN's disputed water, and as the survey stakes on THE SURVEY CAMP, where the debrief *already described them* ("markers at the bends, stakes at the depth changes") and nothing was on the ground. | shipped |
| 19 | **Sandstorm overlay** — tileable band or a few drifting sheets | Weather that **cuts sight range** — reusing the exact `has_line_of_sight` path smoke already goes through, so it is far cheaper than it sounds, and it makes a mission feel like a different fight. | medium |
| ~~20~~ | ~~**Kestrel specialist sprites**~~ — **done** | All five are generated, validated and wired: Essa Vane (grenadier), Sillae Vekh (marksman), Halvik Dunn (breacher), Dava Ren (medic), Fen Ost (technician). Each is a full unit — 3 rotation stances and 7 animation sets across 8 directions, 528 PNGs — generated against the shipped rifleman as the style anchor, with its own `*_MUZZLE_OFFSETS` in `Unit.gd`. `_use_rifleman_art` is gone. Known deviation, recorded in each `metadata.json`: the south aim pose is drawn with the weapon levelled to one flank rather than foreshortened at the camera, and the muzzle offsets follow the art so the flash still leaves the barrel. | shipped |
| ~~21~~ | ~~**Brukk Meshan's own machinegunner art**~~ — **done** | The squad's heaviest weapon was drawn by the generic `Scout_MachineGunner` set, so the gunner read as a rifleman. He now draws `assets/sprites/Hero_MachineGunner/` — 600 PNGs, 8 animation sets, 60×60 on the canonical layout, feet 14px below centre in all eight standing rotations, so `SPRITE_SPECS` needs no entry for him at all. The swap also brought his aim stance into the project's 12–16 foot gate (13–16, where the old set failed at 14–17), and `GUNNER_MUZZLE_OFFSETS` was re-measured off the new aim rotations — 7 of 8 facings exact, south hand-corrected. The folder name is historical, and a trap: it is the PixelLab `Hero_bandana` group, so `Hero_MachineGunner/` is `Kind.MACHINEGUNNER`, while `Kind.HERO` is Rodar Akai in `Rodar_Akai/`. | shipped |
| ~~22~~ | ~~**Garrison fixture kit**~~ — **done** | Home was a walled yard containing three buildings and eight junk heaps, two of which were wrecked car doors, and it read as a scrapheap the squad happened to sleep in. Fourteen fixtures now: steel flag mast, scaffold observation tower, raised steel water tank, camo-net workshop bay, sheet-metal duty board, skid-mounted water bowser, pipe kit rack, steel ammunition box, jerricans, manpack field radio, field stove, weapons cleaning bench, laundry line, and a battlefield cross — rifle muzzle-down, helmet, dog tags. Every one stands on a cell that was scrap, so the garrison has no junk left at all. **The first pass of these was wrong and was regenerated:** seven of the fourteen prompts said *wooden*, *timber* or *stone* outright, and four were pre-industrial objects no adjective could save — a treadle grinding wheel, a stone draw-well, a heraldic standard, a log-stilt watchtower. The garrison came out a frontier stockade in a biome whose own art is an outpost sign, a cargo truck and steel ammo crates. The lesson is cheap and worth keeping: **the fixture prompts are the only place the era is set, so name the material every time** — sheet steel, angle iron, galvanised, olive drab — because the model's default for an unqualified camp object is pre-modern. | shipped |

## Tier 5 — polish

- **Corpse variants** per goblin type so a battlefield reads as a battlefield.
- **Muzzle-flash sprites** — everything combat-related is code-drawn today; hand-drawn flashes would sharpen the shooting.
- **Night / dusk palettes** of the floor sheets, for a dawn assault on Outpost 7 that actually looks like dawn.

## Art that is kept on purpose

Read this before deleting anything under `assets/sprites/`. A folder that no
`.gd` or `.tscn` file names is **not** proof of dead art.

`Scout/`, `Scout_TeamLead/` and `Scout_MachineGunner/` are the **generic Kestrel
troops**, and all three are kept deliberately. They are the bodies for cut
scenes, for making a garrison feel inhabited, and for missions where another
squad fights alongside the player's. Two of them still back a kind directly:
`Scout` is `Kind.SCOUT` (Josen Marr and the line riflemen), and
`Scout_TeamLead` is `Kind.TEAM_LEAD` — legacy, since Rodar Akai took the lead
slot and it is never recruited again, but still reachable. Only
`Scout_MachineGunner` stopped backing a named soldier, when #21 above landed,
and it stays for the same reason as the other two. The enum comment at the top
of [Unit.gd](scripts/Unit.gd) says the same thing where a reader of the code
will hit it.

One measured detail, so the file counts do not mislead a future tidy-up:
`Scout_MachineGunner` holds 688 PNGs against `Hero_MachineGunner`'s 600 only
because its top-level `Dead_Stance/` and `ReadyToFire_Stance/` are
byte-identical duplicates of the nested copies — 88 files that are copies, not
extra art.

---

# Floor tilesheets

Four sheets exist now, all on the same grid and all interchangeable:

```
assets/Tiles/Environments/Desert/Cracked_Desert_floor.png    "desert"
assets/Tiles/Environments/Salt/Salt_flat_floor.png           "salt"
assets/Tiles/Environments/Ash/Ash_burnt_floor.png            "ash"
assets/Tiles/Environments/Compound/Compound_floor.png        "compound"
```

A level picks one by name with `"floor": "salt"`, and may name a second for a
rectangle of the board with
`"floor_inset": {"floor": "compound", "rect": Rect2i(9, 0, 7, 8)}` — that is
how Outpost 7 is sand outside its wall and concrete inside it. A biome in
`BIOMES` names the sheet the field camp stands on. Unknown names fall back to
desert and are caught by `Levels.validate_all()`; `tools/check_floor_sheets.gd`
checks every sheet against the region table that reads it.

## What the code needs

Each sheet is a **4 columns × 3 rows grid of 129×129 cells**, with a **128×60
isometric diamond centred in each cell** (10 of the 12 cells used). The desert
sheet's plant tuft (index 6) is 6px taller and hangs above its diamond; the
three later sheets are uniform 128×60 and use `Board.TILE_REGIONS_FLAT`.

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

## How the last three were made

The recipe has moved. **[artgen/STYLE.md](artgen/STYLE.md) §9** is the
canonical generation recipe (with §7 prompt fragments and the §10 review
rubric), and **[artgen/PIPELINE.md](artgen/PIPELINE.md)** is the
stage-by-stage runbook with the failure playbook. Everything that used to be
written here — shape mode not style mode, the one-Lanczos squash to 128×60,
the shared-silhouette mask, luminance normalization, the ash special case —
lives there now, enforced by `tools/floor_pipeline.py` and gated by
`tools/validate_floor_art.py`.

One correction from this section's history worth repeating: **"six tiles per
call" was right all along.** `create_tiles_pro` at 128px silently caps at 6
variants per call regardless of how many numbered prompts you send — never
send more than 6.

## If you add another sheet

Generate the ten roles above, drop the sheet in
`assets/Tiles/Environments/<Name>/`, add it to `Board.FLOOR_SHEETS` and
`Board.SHEET_REGIONS` (pointing at `TILE_REGIONS_FLAT` unless index 6
overhangs), then name it from a level's `floor` or a biome. Run
`godot --headless --path . -s tools/check_floor_sheets.gd` to confirm the
slots line up.

---

## If you only do three

Every drop-in on this list is now shipped — 8, 9, 17 and 18 went in together on
19 August 2026, which is what closed out Tier 4's cheap half. What is left all
costs code or a unit:

**10 (shielded goblin)** is still the one worth most — it turns the flanking
rules from a detail into the point. After that, **2 (gate)** for breaching and
**16 (road tiles)**, now that a mission can pick its own ground.

One note for whoever does 16: a **salt** road set is the actual blocker for THE
LONG HAUL, not the code. The level already says so in its own comment.

## The decal layer, and what belongs on it

Item 17 added a class of art the game did not have, so it is worth stating what
distinguishes it, because the next person will otherwise generate a decal and
wire it as a prop.

A **prop** stands on a cell. It is 48px art drawn at **2×**, it sits in
`Entities` where it y-sorts against the units, it casts a contact shadow, and
it can hide a soldier — which is why every prop is on the occlusion fade.

A **decal** is a marking *on* the ground. It is 48px art drawn at **1×** on
`Board.decal_layer`, under everything; it casts no shadow, sorts against
nothing, and can never occlude anybody, so it is not on the fade list at all.

The 1× is the part that looks like a mistake and is not. Props are doubled
because they have to hold their own against a 120px soldier. A decal has to sit
*into* a 128×60 tile: at 2× a jawbone spans three quarters of a tile and starts
reading as something to take cover behind, which is a lie about the rules. 1×
also lands it at exactly the floor sheet's texel density, which is the honest
class for it — this is ground, not an object on the ground.

Rule of thumb: **if it would be wrong for a soldier to stand on it, it is a
prop.** The extraction signal panel is the case that proves it — pegged flat
and drawn as a decal specifically so the squad can end the mission standing on
the mark without covering it up.

## Camp fixtures, and why they are 'j'

The garrison's furniture (item 22) needed to be **solid** — you should not walk
through a flagpole — and the camps have no cover rules to hang that on. Three
routes were possible and two are traps:

- A new map char per fixture: fourteen new legend entries for one scene.
- A 1×1 entry in `structures`: it *would* block, but `Board` gives every
  structure cell a `DIAMOND_SHADOW`, so a flagpole would stand in a full black
  tile. This is the one to remember, because it looks like the obvious answer.

What shipped instead: a fixture stands on a cell that is already **`'j'`**, and
the camp's optional `props` table says what to draw there instead of a scrap
pile. The char is doing all the mechanical work it always did — solid, and a
contact shadow the right size — so a fixture needs no rules of its own, and a
camp with no `props` table behaves exactly as before.

`CampData.GARRISON_PROPS` is that table. Two things it is worth knowing:

- Every `'j'` in the garrison is named in it, so the garrison has **no scrap
  left**. `Camp.JUNK_TEXTURES` is now the field camp's alone — and it is
  deliberately three of the seven battlefield junk sprites, not all of them.
  `Rusted_desert_garbage_3` is the wrecked car door: it belongs on a map whose
  point is stripped wreckage, not in a manned camp.
- Three of the four tall fixtures are on **row 1, against the back wall**. They
  stand two soldiers high, and on the back row there is nothing behind them to
  hide. Put a 270px prop mid-yard and it eats whoever is standing behind it.
- The **awning is the exception, and it is a width problem rather than a height
  one**. Its canopy is 256px — two full tiles — on a 128px cell, so against the
  back wall its right half hung past the wall line and floated over open desert
  outside the compound. It sits at (5, 6) now, where the yard is wide enough to
  hold it; the memorial took the wall cell it gave up. Height is safe on row 1,
  **width is not**: check a tall fixture's alpha width against `TILE_W` before
  placing it there, because the wall does not clip anything.

## Passive motion: the camp used to be a still life

Nothing in either camp moved — fourteen fixtures, three buildings, and not one
of them so much as leaned. The battlefield had solved this long ago, so camp
borrows the rule instead of inventing a second one: `Camp._sway_props` is
`Battle._sway_plants`, a lean of one whole sprite texel snapped so the pixel art
never shimmers between subpixel positions, phased off the cell so no two things
sway in step.

Two things about it are deliberate:

- **Only cloth is on the list** — the camo net, the colours, the laundry, the
  kit rack's hanging webbing, plus the camp's cacti. A jerrican or an ammunition
  box that drifted sideways would read as a physics bug rather than as weather,
  so the steel half of the yard is deliberately still. `SWAYING_FIXTURES` is the
  whole list; adding to it is one line.
- **The tick sits above `_process`'s player guard.** The wind belongs to the
  scene, not to the avatar, so it keeps blowing through the frames where there
  is nobody to walk around as.

## Kestrel canvas is modern; Thirst canvas is not

The camps used to pitch `tent` — the shipped rustic pole tent, ragged and
stripe-canvassed — which put a nomad's tent in a regular army's garrison. Three
battle levels still place that same `tent`, and there it is exactly right: it is
Thirst ground, and the Thirst are a dispossessed people. So rather than swap the
shipped art out from under those levels, the camps got their own kinds:
`stores_tent` (sandbags, mesh windows, stores cases — it stands beside the
garrison's `stores` spot) and `field_tent` (a plain frame tent with a stove pipe,
for the one tent the squad has out on operation). The rule worth keeping: **when
an asset reads wrong in one scene and right in another, add a kind — do not
retexture the shared one.**
