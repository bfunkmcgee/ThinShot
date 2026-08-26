# The garrison, indoors

GARRISON.md built the yard; this plans what is behind the doors. It is a
design, not an implementation: every map below is validated mechanically
(ring closed except its door, every furniture cell named, every floor cell
reachable from the door, every jail cell sealed) but nothing here ships
until its assets do.

## Why interiors, and why these

The campaign's thesis is that it remembers, and an interior is where memory
becomes furniture. The yard already says what the garrison *does*; the
rooms can say what the campaign has *done*:

- A named soldier dies and his **bunk** is stripped bare the next time you
  walk the billet.
- A soldier ends a mission walking wounded and he is **on a cot** in the
  surgeon's tent, not idling in the yard.
- A bounty ends with "he walked in ahead of the party" and the man is **in
  the lockup's cell**, visible through the bars, until the Accord collects
  between operations.
- The gear the company book has actually bought stands on the **armory's
  racks**.
- The files on the ones who got away are **pinned in the HQ**, one card per
  name on STILL OUT THERE.

None of that needs new rules. It is the roster, the wounds ledger, the
bounty outcomes and the armory list — state the game already saves — drawn
as objects in rooms.

## The mechanics, in the machinery that exists

Interiors are camp maps. `Board.set_level()` eats any `size`/`map`/
`structures` dict; the walk mode, prompts, fixtures, occlusion fade, sway
and breeze loops all come along for free. What is new is small:

- **Doors.** A building's door cell in the yard gets a fixture hook
  (`"enter": "hq"`), prompt `E - inside`. Each interior's south wall has a
  two-cell door gap with an `"exit"` hook at it. Transition = set
  `Game.camp_interior`, then `get_tree().reload_current_scene()` — the
  exact pattern the levy post already uses to refresh the camp after
  recruiting. Camp reads `camp_interior` at `_ready` and builds that map
  instead of the yard; exiting clears it and re-enters at the building's
  door.
- **Scale.** Rooms are larger inside than their 2×2 footprint, which is
  the convention of every game with doors and bothers nobody.
- **Jail bars are wire.** The `=` char already stops movement without
  stopping sight — exactly what bars do. The lockup's cells are sealed
  with `=` and the man inside is visible through them. (New bar ART is
  wanted — vertical steel bars, not concertina — but the CHAR is right.)
- **Floors.** Stage one reuses the shipped `compound` concrete sheet for
  HQ / armory / lockup and the desert default elsewhere; a proper interior
  sheet (packed earth and plank, standard 515×386 layout) is on the bill.
- **Prompt collision.** A building's enter-hook cell must not share a cell
  with an existing station spot (the armory's door hook goes at (13,8),
  beside the stores spot at (14,8), not on it).

## The rooms

Legend as the camps: `.` floor, `W` wall, `j` furniture, `=` bars. Doors
are the south-wall gaps. Spawn is just inside the door.

### HQ — the ops room

```
WWWWWWWWWW
W.j..j..jW    files cabinet(2,1)  radio desk(5,1)  map board(8,1)
W........W
Wj..jj..jW    command desk(1,3)  map table+crates(4,5 ,3)  strongbox safe(8,3)
W........W
W........W
WWWW..WWWW
```

The room where the campaign's paper lives. The map board carries one card
per name on STILL OUT THERE — the files made physical, count driven by
`Game.adversaries`. The safe is where the scrip fiction sits. Nothing
interactive moves here in stage one; the CAREERS/chronicle hook could
migrate from the memorial later, or not — that pairing is load-bearing.

### The wet canteen

```
WWWWWWWWWW
Wjjj..j.jW    bar counter run(1..3,1)  bottle shelf(6,1)  stove(8,1)
W........W
W..j..j..W    barrel tables(3,3)(6,3)
W........W
W.j....j.W    barrel tables(2,5)(7,5)
WWWW..WWWW
```

Where the squad actually is, off duty. Two or three of the yard's idle
spots move indoors; talking to Sillae here reads the theater over a drink,
which is where that conversation always wanted to happen. The banked
`canteen_table` spare finally gets placed — four times.

### The armory

```
WWWWWWWWW
Wjj.j.jjW    rifle racks(1,2 ,1)  tall shelving(4,1)  ammo boxes(6,7 ,1)
W.......W
Wj.....jW    issue counter(1,3)  cleaning bench(7,3)
W.......W
WWW..WWWW
```

The banked `qm_shelving` tall spare gets placed. Dynamic dressing:
`Game.armory`'s contents drawn as kit bundles on the counter — a shop
whose shelves are its actual stock. The QM hook itself STAYS at the yard
window; the room is where the stock lives, not a second shop.

### The lockup

```
WWWWWWWWW
Wj..W..jW    cell cots(1,1)(7,1), divider wall
W...W...W    standing room - prisoner spawns (2,2) / (6,2)
W===W===W    bars: sealed, seen through
W.......W    corridor
Wj.....jW    guard stool(1,5)  notice board(7,5)
WWW..WWWW
```

The payoff room. A bounty that ended `surrendered` puts the man in a cell
— his actual identity, standing behind the bars — until the operation
ends and the Accord collects. Two cells, because the campaign can hold two
before anybody comes for them. Walking in and looking at a man you chose
not to shoot is exactly the kind of thing this game is about, and it costs
one spawn call driven by `Game.bounty_outcomes`.

### The surgeon's tent

```
WWWWWWWWW
Wj.j.j.jW    cots(1,3,5 ,1)  medical chest(7,1)
W.......W
Wj.....jW    wash stand(1,3)  folding screen(7,3)
W.......W
WWW..WWWW
```

Roster members whose `wounded` flag is set idle HERE, beside the cots,
instead of in the yard — the walking wounded made visible, driven by the
ledger that already exists. Dava works here when she is not deployed.

### The billet (one map, reused by both huts and the tent)

```
WWWWWWWWW
Wj.j.j.jW    bunks(1,3,5,7 ,1)
W.......W
Wjj....jW    footlockers(1,2 ,3)  stove(7,3)
W.......W
WWW..WWWW
```

One bunk per named soldier, assigned by roster order. A dead Kestrel's
bunk draws the STRIPPED variant — bare frame, folded mattress — from the
day he dies to the end of the campaign. The billet is the notebook,
furnished.

## The asset bill

Reused, already shipped: `qm_shelving` and `canteen_table` (banked
spares, finally placed), `qm_counter`, `cleaning_bench`, `ammo_box`,
`field_stove`, `notice_board`, `field_radio` (on the radio desk),
briefing-table art for the map table, crates, the compound floor.

| Piece | Canvas | Notes |
|---|---|---|
| Bunk + stripped bunk | 48×48 ×2 | the pair is the point — made, and bare frame |
| Footlocker | 48×48 | stencilled name plate |
| Cot + occupied cot | 48×48 ×2 | surgeon's tent; occupied variant optional if wounded idle beside instead |
| Bar counter run + end | 48×48 ×2 | mud brick base, plank top |
| Bottle shelf | 48×48 | or 168 tall if it should read at distance |
| Files cabinet | 48×48 | steel, drawers, one open |
| Radio desk | 48×48 | desk + set; the manpack prop can sit on it |
| Command desk | 48×48 | maps under glass, folding chair |
| Map board (cards) | 48×48 | pinned file cards, string |
| Strongbox safe | 48×48 | floor safe, painted crest |
| Cell cot | 48×48 | plank shelf and a bucket |
| Guard stool | 48×48 | or reuse a crate |
| Wash stand | 48×48 | basin, jug, towel |
| Folding screen | 48×48 | canvas on a frame |
| Jail bars | 68×68 wall-format ×2 | straight run + end; vertical steel bars for `=` INDOORS (the concertina stays outdoors) |
| Interior floor sheet | 515×386 | packed earth and plank, standard ten-diamond layout |

Two 48px review packs cover the furniture (~40-50 generations); the bars
and floor sheet are their own calls. Generation rules per the recipe
memory: modern material named per item, no sand disc, magnify empty
surfaces before accepting.

## Staging

1. ~~**Shells**~~ — **shipped 2026-08-25**: doors, transitions, all six
   rooms furnished from reused props, `--interior <name>` for screenshot
   runs, `tools/test_interiors.gd` proving the scene (22 checks), and the
   desert's detritus stopped at the door. Both known stage-one reads
   (concertina indoors, the counter in QM's art) are gone as of stage two.
2. ~~**Furniture batch**~~ — **shipped 2026-08-24**: sixteen 48px pieces
   (two review packs, 45 generations with the bars) under the names stage
   one reserved, so no map changed; the canteen's counter run gained its
   `bar_counter_end`. Deliberate reuse stands: `rifle_rack` wears the kit
   frame, `map_table`/`map_crates` the briefing set, `qm_shelving` and
   `canteen_table` their banked spares, `medical_chest` the ammo box.
   The jail bars landed in the same pass — vertical steel on the 68px
   wall class (`desert_jail_bars/`, offset -17 uniform), drawn by the
   `=` char whenever `interior != ""`; the yard keeps its concertina.
   Banked in `spares/`: a barred door, west pier, window insert, steel
   bench, key board and guard table, for the operation-two prison.
3. **Memory dressing** — stripped bunks, cots for the wounded, the man in
   the cell, stock on the counter, cards on the board. Each is a small
   read of saved state at `_spawn_props` time, and each is independently
   shippable.
4. **Interior floor sheet** — the last coat of paint (the bars are done).

Validation: `interiors_design.py` alongside the garrison's design script —
ring, naming, reachability and cell-seal checks all green on the maps
above before this document was written.
