# ThinShot — full analysis

> ## Status — verified against the code on 2026-08-21
>
> This audit predates most of the campaign of work that followed it, and its
> findings have been substantially IMPLEMENTED. It is kept as written — the
> reasoning and the recipes are the valuable part — but read it with this
> scorecard, so its remaining open items stop hiding among the fixed ones.
>
> **All 11 critical/high bugs are now fixed**, the last two on 2026-08-21:
>
> | Finding | Status |
> |---|---|
> | Blast commits the win before its own casualties | FIXED (`_resolving_blast`) |
> | Units shoot through walls (`peek_origin` ignore set) | FIXED (single-cell ignore + `in_bounds`) |
> | No persistence | FIXED (save v7, forward-only ladder, atomic write) |
> | Debug level jumps destroy campaigns | FIXED (debug-gated) |
> | Machinegun fires behind the results screen | FIXED (`_end_sustained_fire` in `_show_game_over`) |
> | Fire-mode panel lies after a move | FIXED (reset in `do_move` tail) |
> | Machinegunner's stranded last round | FIXED 2026-08-21 (`Unit.min_rounds`) |
> | Free perimeter peek / phantom edge cover | FIXED (bounds guard) |
> | Promotions evaporate | FIXED (clears only on campaign reset) |
> | Danger overlay under-warns | FIXED (`can_engage`) |
> | End Turn has no guard | FIXED 2026-08-21 (two-press confirm + count) |
>
> **"Do this first" (12 items): all 12 are now done.** 1–10 and 12 landed
> first — the save system, the `Rules.gd` extraction, `tools/test_rules.gd`,
> and the visual pass. The 2026-08-21 enactment branch closed the rest: **#8,
> the entity index** (`Battle._units`, guarded readers), and **#11, the
> balance pass, taken** — `AUTO_ACCURACY` −35, the burst priced at −8 a
> round, and suppression made multiplicative after the clamp.
>
> **Enacted 2026-08-21 (branch `claude/enact-survey`),** from the field
> survey that followed this audit: the AI routes around held overwatch arcs
> (its scoring extracted to `AiPlan.gd`, the cone to `Rules.overwatch_cells`);
> a clean move can be taken back (U); hovering a move tile projects the shot
> from the destination through the same `Rules.shot_preview` the round uses;
> missions can carry a pressure clock (the Scrapline mast calls patrols until
> it drops, Outpost 7's withdrawal is chased); Standing decides what breaking
> means and leans on the parley; the squad has a wound ledger (save v8); the
> briefing reads Dava's notebook back and returners wear their survival
> tally; the garrison ledger writes the campaign chronicle to
> `user://chronicle.txt`; a settings file covers volume, shake, hit-stop, the
> danger default and a high-contrast arc palette; and OPERATION BURNT SURVEY
> puts two authored missions on the ash tilesheet. The suite is 21 harnesses.
>
> The addenda below the metrics line were appended as later features landed
> and describe shipped systems, not proposals.

Audit of bugs, architecture, features, graphics, visual consistency and game design.
Produced by 9 parallel code analysts plus adversarial verification of every claim (99 raw
findings, 6 refuted); the five headline defects were then re-confirmed by hand against the
source, and the art metrics in the addendum were measured directly from the PNGs.

## Verdict

ThinShot is a genuinely well-built turn-based tactics game — the isometric board math, the cover/peek/facing rules, the mission-rollback campaign layer and the animation state machine are all real systems written by someone who understood the genre, and the writing across seven missions is better than the code needs it to be. It is also one keystroke from destroying a campaign, one grenade from corrupting the roster, and zero keystrokes from losing everything when the window closes: **there is no save file anywhere in the project**. Underneath that, the two rules the whole game rests on — `peek_origin` and the win check — are both wrong in ways that let units shoot through solid rock and let a mission be scored as won before its own casualties are counted. Battle.gd is a 3117-line god object with no test seam, which is why these survived.

**Do this first: add `Game.save()`/`load()` and gate the 1/2/3 debug hotkeys.** Everything else in this document is improvement; those two are the difference between a game you can play and a demo you can look at.

## Bugs

Rendering defects are listed separately under **Graphics** to keep them next to their fixes. This table is logic, state and rules.

| Severity | What breaks | Where | Fix |
|---|---|---|---|
| CRITICAL | A blast that kills the last goblin commits the win before it kills your own scouts in the same blast — they are marked permanently dead but scored as survivors, promoted, and given the survival XP | [Battle.gd:2208](scripts/Battle.gd#L2208) | `_resolving_blast` flag; `_on_unit_died` skips `check_game_over()` while set; call it once after the loop |
| CRITICAL | `peek_origin` passes the whole `hugged` set as an LOS ignore-list, so units lean around one wall and shoot through a different one — 260 illegal shots across the 7 shipped maps | [Board.gd:683](scripts/Board.gd#L683) | Ignore only `cover_cell`, not the aggregate; add `in_bounds` guard to the hugged loop |
| CRITICAL | Campaign state is never written to disk — roster, ranks, perks, mission progress all die with the process | [Game.gd:18](scripts/Game.gd#L18) | `save()`/`load()` over JSON to `user://`; call from `commit_mission`, `abort_mission`, `_ready` |
| CRITICAL | Bare `1`/`2`/`3` during play, and three unlabelled buttons on the win screen, abandon the mission and rewind the campaign — also an unbounded XP farm on the win path | [Battle.gd:833](scripts/Battle.gd#L833), [Battle.gd:3016](scripts/Battle.gd#L3016) | `OS.is_debug_build()` gate on both the hotkey loop and the button visibility |
| HIGH | Sustained suppressive fire is never torn down on game over — the machinegun keeps firing behind the results screen forever | [Battle.gd:2609](scripts/Battle.gd#L2609) | `_end_sustained_fire()` as the first line of `_show_game_over` |
| HIGH | Armed fire mode is not revalidated after `do_move`: panel promises `x4 AUTO @ 58%`, the gun fires 2 rounds at 73% | [Battle.gd:1443](scripts/Battle.gd#L1443) | Add `if not _can_use_mode(unit, fire_mode): _set_fire_mode(_default_fire_mode(unit))` to `do_move`'s tail |
| HIGH | Machinegunner with exactly 1 round: target is highlighted, panel quotes odds, click is a silent no-op | [Battle.gd:903](scripts/Battle.gd#L903), [Unit.gd:1161](scripts/Unit.gd#L1161) | `Unit.min_rounds()`; gate the highlight on it; give `_fire_selected_at`'s refusal feedback |
| HIGH | Off-map cells count as FULL cover, so every unit on the board perimeter gets a free one-tile lean-and-shoot (113 extra shots on OUTPOST 7 alone) | [Board.gd:673](scripts/Board.gd#L673) | `if in_bounds(from + dir) and cover_level_of(...) == FULL` |
| HIGH | An unspent promotion is silently destroyed the moment the next mission starts | [Game.gd:374](scripts/Game.gd#L374) | Delete `pending_promotions.clear()` from `begin_mission()` |
| HIGH | Danger overlay uses `has_line_of_sight` while the AI shoots with `can_engage`, so peek shots are never warned — and its own docstring claims the opposite | [Battle.gd:2517](scripts/Battle.gd#L2517) | `board.can_engage(origin, tile)`; also default `danger_on := true` |
| HIGH | `E` ends the turn instantly with unspent soldiers; the only guard is a 350 ms timer | [Battle.gd:2583](scripts/Battle.gd#L2583) | Count `not acted` soldiers, banner + confirm on first press |
| MEDIUM | A pinned unit still fires overwatch reactions, so suppressing the goblin covering a lane does not shut the lane down | [Battle.gd:2567](scripts/Battle.gd#L2567) | `or watcher.is_suppressed()` in the skip condition |
| MEDIUM | Overwatch arc consumed by a fatal reaction stays painted; the player routes around a threat that no longer exists | [Battle.gd:1479](scripts/Battle.gd#L1479) | `_refresh_watch_cells()` in the death branch; hoist it out of the `PLAYER_TURN` gate at 1495 |
| MEDIUM | Drum hover panel says "3 at the centre, 2 out"; the four orthogonal neighbours actually take 3 | [Battle.gd:1051](scripts/Battle.gd#L1051) | Print `FRAG_DAMAGE` on the cross and `FRAG_DAMAGE - FRAG_FALLOFF` on the corners, as the frag branch already does |
| MEDIUM | `--level N` is re-applied on every battle load, so the campaign can never advance past N; camp meanwhile shows mission 1 | [Battle.gd:400](scripts/Battle.gd#L400) | Latch it, or apply it in `Game._ready()` |
| MEDIUM | Danger overlay projects a pinned goblin's full move range — suppression produces a byte-identical overlay | [Battle.gd:2505](scripts/Battle.gd#L2505) | `origins = []` when `not goblin.can_move()` |
| MEDIUM | `_exposure_at` scores cover using `cover_between` (no facing), but shots resolve through `effective_cover` (facing-dependent) — wounded goblins retreat into cover they will not be facing and die flanked | [Battle.gd:2758](scripts/Battle.gd#L2758) | Pass the candidate `end_sector` in and apply the same arc test `covers_sector` uses |
| MEDIUM | LOS leaks through the corner joint of two diagonally touching blockers, and `roundi`'s half-away-from-zero makes the two orientations of the same corner disagree | [Board.gd:551](scripts/Board.gd#L551) | Supercover walk, or test both flanking cells at an exact lattice crossing |
| MEDIUM | Sentinel grants a 225° arc, not the 180° the perk blurb, the inline comment and the README all promise — and silently also shrinks the flankable rear arc and widens which cover the soldier claims | [Unit.gd:766](scripts/Unit.gd#L766) | Float `arc_half` (1.5) with a `+0.5` tolerance in `covers_sector`, or accept 225 and correct three docs |
| MEDIUM | `_load_only_anim` returns a 0-length array on failure while `_update_sprite` indexes it by facing sector | [Unit.gd:791](scripts/Unit.gd#L791) | Return an 8-entry skeleton of empty arrays so the existing `if cycle.is_empty()` fallback engages |
| MEDIUM | Flanked overwatcher that survives the hit is stuck in the aim-idle pose with overwatch already cleared — the exact visual cue the player reads for "who is on watch" | [Unit.gd:854](scripts/Unit.gd#L854) | Clear overwatch and `lower_rifle()` *before* `take_damage` at [Battle.gd:2415](scripts/Battle.gd#L2415) |
| MEDIUM | The whole board perimeter draws the cover dot and full-cover bars, and units visibly crouch there, but `cover_between` can never return edge cover to any real shot (0 of 160×160 pairs) | [Board.gd:637](scripts/Board.gd#L637) | Return `NONE` for out-of-bounds in `cover_level_of` — which also fixes the perimeter peek above |
| LOW | A soldier killed by his own drum/grenade gets `DONE_TINT` over the corpse tint | [Battle.gd:2055](scripts/Battle.gd#L2055) | Wrap the cleanup in `if shooter.is_alive():` |
| LOW | `_can_demolish` omits the `_armed()` check every other action path has, so a freed prisoner beside a cache draws the "set charges here" rim and the click dies | [Battle.gd:1892](scripts/Battle.gd#L1892) | Add `and _armed(unit)` |
| LOW | Both operations declare `"biome": "desert"`, so `BIOMES.salt` and `BIOMES.ash` are dead data — the camp between two salt-pan missions is dressed as desert and labelled DESERT | [Levels.gd:501](scripts/Levels.gd#L501) | `"biome": "salt"` on OPERATION SECOND VERSE; validate the key exists |
| LOW | `reset_roster()` leaves the previous run's grenade split in place on campaign loop | [Game.gd:351](scripts/Game.gd#L351) | Add `frags = 2; smokes = 2` |
| LOW | `_load_target_art`'s "no art" guard can never fire for a missing animation stage — an empty run is still appended | [Battle.gd:1766](scripts/Battle.gd#L1766) | Check each run as it is appended |
| LOW | Hit rolls and a 14 Hz smoke effect share one `RandomNumberGenerator`, and no seed is recorded | [Battle.gd:2360](scripts/Battle.gd#L2360) | Separate `_combat_rng`, seeded and printed at battle start |

---

**CRITICAL — the blast commits the win before it kills your own men.** Repro: mission 1, get a scout to 3 HP or less, then frag a cell that contains both the last living goblin and that scout. `_apply_blast` builds `caught` as `living_units(TEAM_GOBLIN) + living_units(TEAM_SCOUT)` at [Battle.gd:2202](scripts/Battle.gd#L2202) — goblins strictly first — then walks it in a plain loop. `Unit.take_damage` emits `died` synchronously ([Unit.gd:1213](scripts/Unit.gd#L1213)), `_on_unit_died` ends in `check_game_over()` ([Battle.gd:2848](scripts/Battle.gd#L2848)), and `_show_game_over` awards `XP_SURVIVE` to every living scout and calls `Game.commit_mission()` ([Battle.gd:2896-2898](scripts/Battle.gd#L2896)) — which clears `_snapshot`, making rollback impossible. Control then returns to the loop and the scout dies, hitting `Game.mark_dead()` *after* the commit. The debrief lists him with a `+xp` line; the roster lists him dead. Fix: add `var _resolving_blast := false`, set it around the damage loop in `_apply_blast`, have `_on_unit_died` skip its `check_game_over()` call while it is true, and call `check_game_over()` once immediately after the loop. `do_shoot_drum` and `_finish_throw` already guard on `state == GAME_OVER` at [2058](scripts/Battle.gd#L2058) and [2248](scripts/Battle.gd#L2248), so they need no change. (The total-squad-wipe soft-lock a lens claimed is a stretch — blast damage is capped at 3 and the garrison refills at operation boundaries — but the mis-scored single death is routine.)

**CRITICAL — units shoot through walls.** Repro from shipped data: THE LONG HAUL, team lead spawns at `(0,5)` beside the map's only rock at `(1,5)`; a goblin due east at `(2,5)` is engageable. `peek_origin` collects every orthogonally adjacent FULL-cover cell into `hugged` ([Board.gd:671-674](scripts/Board.gd#L671)) and then tests the leaned line with *that whole set* as the ignore list ([Board.gd:683](scripts/Board.gd#L683)), while `_los_ignoring` skips ignored cells outright ([Board.gd:651](scripts/Board.gd#L651)). The ignore is only defensible for a line starting at `from`; the line actually tested starts at `side`, where the other hugged cells are frequently squarely in the way. Re-implementing the three functions and sweeping all 7 maps yields 260 shots whose leaned line crosses a full blocker (OUTPOST 7: 121, THE CISTERN: 80, THE CHOIRMASTER: 55, THE LONG HAUL: 4) plus 148 more that lean to the wrong side. **Two analysts disagreed on the fix and I resolved it by reading the doc comment at [Board.gd:658-665](scripts/Board.gd#L658)** — "the piece being hugged stops blocking but nothing else does" — which makes the single-cell ignore documented intent and the *aggregate* ignore the actual bug. So: `_los_ignoring(side, to, {cover_cell: true})`, plus the `in_bounds` guard from the perimeter finding, which together remove the illegal wall shots. The LONG HAUL case survives that pair (you step off a one-cell rock and shoot past it) and I believe that is intended; the strict `has_line_of_sight(side, to)` would kill it along with every legitimate corner lean, so do not use it.

**CRITICAL — no persistence.** `grep -rn "FileAccess|ConfigFile|ResourceSaver|user://" scripts/` returns nothing. Game.gd's own header calls itself "the only thing that survives `reload_current_scene()`" ([Game.gd:3-4](scripts/Game.gd#L3)) — correct, and also the ceiling. Every field is an int, bool, String or Array of those (`roster` is `{id, surname, kind, xp, rank, perks, alive}`), so this is ~40 lines: `save()` builds a Dictionary of `{roster, _next_id, current_operation, current_level, in_the_field, frags, smokes, pending_promotions}`, `JSON.stringify`, `FileAccess.open("user://campaign.json", WRITE)`. Call it at the end of `commit_mission()` ([Game.gd:412](scripts/Game.gd#L412)) and `abort_mission()`, and after Camp's `choose_perk`/`set_loadout`/`recruit_to_strength`. `load_save()` from `Game._ready()` ([Game.gd:108](scripts/Game.gd#L108)) — and **coerce explicitly with `int()`/`bool()`**, because JSON round-trips ints as floats and `rank == 3.0` will break `rank_for_xp` comparisons in ways you will not enjoy debugging. Do not save mid-battle: `abort_mission` already restores the pre-mission snapshot, so mission granularity is the correct and safest checkpoint. Reset `_snapshot`, `mission_xp` and `mission_dead` on load rather than persisting them.

**CRITICAL — the level-jump keys.** `_unhandled_input` handles `1`/`2`/`3` inside the live-play block, after the `state != PLAYER_TURN` early-out ([Battle.gd:833-836](scripts/Battle.gd#L833)); project.godot binds them to bare physical keycodes 49/50/51 with every modifier flag false. `_go_to_level` is `abort_mission(); select_level(index); go_to_battle()` ([Battle.gd:3016](scripts/Battle.gd#L3016)) with no confirmation — mid-mission that discards the run and rewinds `current_level` *and* `current_operation` ([Game.gd:150-157](scripts/Game.gd#L150)). The same three buttons sit on the win panel directly under Restart ([Battle.tscn:294-331](scenes/Battle.tscn#L294)), where the failure mode inverts: `_show_game_over` has already called `commit_mission()`, which cleared `_snapshot`, so `abort_mission()` hits `if _snapshot.is_empty(): return` and rolls back nothing — the XP banks and the mission re-arms. Win mission 1, click "Level 1", repeat: every soldier reaches Master Sergeant with both perks off the opening skirmish, defeating the explicit design note at [Game.gd:37-38](scripts/Game.gd#L37). Fix both at once: wrap the hotkey loop in `if OS.is_debug_build():`, and change the button loop at [Battle.gd:383-387](scripts/Battle.gd#L383) so visibility keys off `OS.is_debug_build()` rather than `i < Levels.LEVELS.size()` (which, with 7 levels, is always true).

**HIGH — the machinegun fires behind the results screen.** `_end_sustained_fire` is defined at [Battle.gd:1585](scripts/Battle.gd#L1585) and called from exactly one place, [line 2635](scripts/Battle.gd#L2635) — which sits *after* `if state == State.GAME_OVER: return` at [2609](scripts/Battle.gd#L2609). `_show_game_over` never calls it, nothing sets `process_mode` or `set_process(false)`, and `_process` unconditionally drives `_sustain_suppression`, which only self-clears when the gunner himself dies. Repro: gunner suppresses (deals no damage, so the battle cannot end on that action), then another scout frags the last goblin the same turn — or, on THE CISTERN, a scout simply walks onto an extract tile and `check_game_over()` at [1493](scripts/Battle.gd#L1493) wins mid-turn. A gunshot, muzzle flash, tracer, casing, bullet hole and camera recoil every 1.45 s, forever. Fix is one line beside `state = State.GAME_OVER` at [Battle.gd:2889](scripts/Battle.gd#L2889).

**HIGH — the fire-mode panel lies after a move.** Every other order that invalidates the armed mode resets it — `_try_reload` (1175), `_try_overwatch` (1199), `_try_face` (1216), `_try_throw` (2134) all call `_set_fire_mode(_default_fire_mode(selected))`. `do_move`'s tail is only `_refresh_danger(); _refresh_watch_cells(); _update_unit_panel(); _refresh_highlights()`. But `_can_use_mode` gates AUTO on `not unit.moved` ([Battle.gd:970](scripts/Battle.gd#L970)) and scout BURST on `not (burst_requires_still() and moved)` ([967](scripts/Battle.gd#L967)). The panel renders the *armed* mode blind — `var rounds := _rounds_for(fire_mode)` at [1109](scripts/Battle.gd#L1109) — while `_fire_selected_at` silently downgrades at [903-908](scripts/Battle.gd#L903). Repro: select the gunner, press A, click a move tile, hover a goblin 3 tiles out. Panel: `58% TO HIT - 2 DMG  x4 AUTO`. Reality: 2 rounds at 73%. 4.64 expected damage promised, 2.92 delivered. Fix: one line in `do_move`'s `prev_state == PLAYER_TURN` block; belt-and-braces, have `_update_unit_panel` walk the same fallback chain `_fire_selected_at` does.

**HIGH — the machinegunner's last round.** Three lenses found this from three angles; it is one bug with two halves. `_refresh_highlights` gates the attack overlay on bare `selected.has_ammo()`, whose default is `rounds := 1` ([Unit.gd:1144](scripts/Unit.gd#L1144)), so the goblin tile paints red. `_default_fire_mode` returns BURST for the gunner because `can_single_shot()` is `kind != Kind.MACHINEGUNNER` ([Unit.gd:908](scripts/Unit.gd#L908)), and `_can_use_mode` needs `has_ammo(2)`. So `_fire_selected_at` fails, falls back to BURST, fails again, and returns with no sound, no banner, no print. Reachable in two turns from a full 6-round belt: suppress (3) then burst (2). Panel still reads `73% TO HIT - 2 DMG  x2 BURST` and does not say "OUT OF AMMO - RELOAD (R)" because `needs_reload()` is `ammo == 0`. The round is not entirely stranded — `_can_shoot_drum` and `_try_overwatch` both use the 1-round check and work — but it cannot be aimed at the thing the UI says to aim it at. Fix: `func min_rounds() -> int: return 1 if can_single_shot() else 2` on Unit; `needs_reload()` becomes `mag_size > 0 and not has_ammo(min_rounds())`; [Battle.gd:1353](scripts/Battle.gd#L1353) becomes `selected.has_ammo(selected.min_rounds())` and [1136](scripts/Battle.gd#L1136) reads `unit.needs_reload()`.

**HIGH — the free perimeter peek.** `cover_level_of` returns FULL for out-of-bounds ([Board.gd:585](scripts/Board.gd#L585), "the map edge is something to put your back to"), and `peek_origin` builds `hugged` straight off it with no bounds guard. Any unit on row 0/9 or column 0/15 is treated as hugging cover that does not exist and gets a free one-tile lean-and-shoot. Shots that exist only because of this: DRY WASH 26, SCRAPLINE 42, OUTPOST 7 113, LONG HAUL 33, CISTERN 14, HOLDING PENS 12, CHOIRMASTER 64. The same off-map FULL is what paints the cover dot and full-cover bars along all 48 perimeter tiles and sinks units into a crouch there — while `cover_between` looks cover up by sector and the sectors an off-map neighbour protects are geometrically unreachable, so **zero** of the 160×160 shooter/target pairs on an empty board ever receive edge cover. The overlay teaches a rule that does not exist. Cleanest single fix: return `CoverLevel.NONE` for out-of-bounds. If you keep FULL for aesthetic reasons, guard both `peek_origin`'s hugged loop and `cover_map_at`'s loop with `in_bounds`.

**HIGH — promotions evaporate.** `begin_mission()` does `pending_promotions.clear()` unconditionally ([Game.gd:374](scripts/Game.gd#L374)) and `Battle._ready()` calls it on every deploy ([Battle.gd:338](scripts/Battle.gd#L338)). `commit_mission()` only queues ranks *newly crossed* (`for rank in range(old_rank + 1, new_rank + 1)`, [Game.gd:409-411](scripts/Game.gd#L409)) and writes `soldier.rank` first, so the pick can never be re-offered. Camp never forces it: `_open_briefing()` builds the DEPLOY modal with no reference to `pending_promotions` ([Camp.gd:621-631](scripts/Camp.gd#L621)). Repro: win a mission, walk straight to the briefing table instead of to the promoted soldier, deploy. Marksman/Sprinter/Sentinel/Hustle gone permanently; the rank bonuses still apply so nothing on screen ever tells you. Fix: delete the `clear()` — the queue is per-soldier, `choose_perk` already refuses duplicates ([Game.gd:428](scripts/Game.gd#L428)), and `abort_mission()` still clears it on rollback. Add a line to the DEPLOY modal body when the queue is non-empty.

**HIGH — the danger overlay under-warns.** `_compute_danger_cells` tests `board.has_line_of_sight(origin, tile)` ([Battle.gd:2517](scripts/Battle.gd#L2517)); the AI targets with `_shootable_from` → `board.can_engage` ([2735](scripts/Battle.gd#L2735)) = `has_line_of_sight(...) or peek_origin(...) != NO_CELL`. Every cell a goblin could reach only by leaning around its own cover is painted SAFE — precisely the corners the player is taught to bound between. The function's own docstring at [2499-2501](scripts/Battle.gd#L2499) asserts the opposite, so nobody would suspect it. **Two lenses also flagged the pinned-goblin over-projection here; I read the same docstring and it explicitly endorses over-warning** ("over-warning is the safe error"), so that half is a feedback problem for suppression, not a correctness bug — fix it, but for a different reason. One-word change: `can_engage`. While you are in there, `var danger_on := false` at [250](scripts/Battle.gd#L250) should be `true`.

**HIGH — End Turn has no guard.** `end_player_turn`'s entire precondition is a state check and a 350 ms grace timer ([Battle.gd:2581-2584](scripts/Battle.gd#L2581)). It never counts unspent soldiers. `E` is also the camp's `interact` key, i.e. the key the player was mashing sixty seconds earlier. One press throws away up to five activations and hands the Choir a free round. Units *do* grey out when fully spent (`set_done`, [Unit.gd:1317](scripts/Unit.gd#L1317)), so "no feedback at all" is overstated — but there is no count, and no distinction between "moved, still has a shot" and "fresh". Fix: count `not acted` soldiers first; if any, `show_banner("%d SCOUT(S) STILL READY - PRESS AGAIN")` and arm a 2 s confirm window. Put the count in the button text from `_refresh_highlights`.

## Balance & combat math

**AUTO strictly dominates BURST for a stationary gunner.** `AUTO_ACCURACY := -15` ([Battle.gd:213](scripts/Battle.gd#L213)) against BURST's literal `0` ([911](scripts/Battle.gd#L911)). Gunner: accuracy 78, damage 2, range 4, `comfortable = 2`. At 3 tiles BURST is 73% × 2 rounds × 2 dmg = **2.92**; AUTO is 58% × 4 × 2 = **4.64** — +59% for the same action. Ammo is not a real cost either: `do_volley` breaks on a kill ([2477](scripts/Battle.gd#L2477)), so against a 4 HP Chorister AUTO kills 79.7% of the time on E[3.04] rounds and BURST 53.3% on 2 — 0.262 vs 0.267 kills per round, identical efficiency, 50% more kills per turn. To make 4 rounds merely equal 2 at base 78 you need the penalty at **−35**, not −15. Alternatively keep −15 and give AUTO a structural cost (forfeits next turn's move). Note the one thing that keeps BURST alive: AUTO requires `not unit.moved`, so BURST is the gunner's only mode after repositioning.

**BURST has no accuracy penalty at all**, so per activation it is exactly 2× SINGLE. Scout at 3 tiles: SINGLE 85% × 2 = 1.70, BURST 2 × 0.85 × 2 = 3.40, same hit chance, same action. There is never a reason to press SINGLE while standing still with 2 rounds. Pass about **−8** as the `accuracy_mod` at [911](scripts/Battle.gd#L911) (3.08 stays worth it, precision costs something). Note the perverse coupling: `_try_reload` sets `moved = true` ([1174](scripts/Battle.gd#L1174)), so a scout who reloads without stepping is barred from bursting — the opposite of the "bracing buys the burst" fiction. Track repositioning in its own flag.

**Suppressive fire is a 4.6:1 losing trade.** `do_suppressive_fire` deals no damage — `_fire_suppression_round` rolls nothing ([2287-2307](scripts/Battle.gd#L2287)) — and pins for exactly one enemy turn (`suppression = 2`, decremented once at the goblins' `start_turn`). Per pinned Chorister (acc 60, dmg 2, range 3): 1.00 expected damage/turn normally, 0.50 pinned. Two pinned = **1.00 damage denied, once**, against the 4.64 the gunner forgoes. Killing removes 1.00/turn permanently. Worse, `run_enemy_turn` checks shooting *first* ([2665-2668](scripts/Battle.gd#L2665)), so a pinned goblin with a target simply shoots at −25 — the ability never denies the lane it is sold on. And the pinned goblin still fires overwatch reactions (bug above). Make the pin cost the target's next attack, or invert the AI priority at 2666 so a pinned goblin must also pass `not is_suppressed()` to fire.

**`clampi(chance, 20, 99)` makes suppression worth 5 points where it should be worth 25.** The floor at [Battle.gd:2446](scripts/Battle.gd#L2446) is applied *after* every penalty. Chorister at 3 tiles: 50% open → 25% vs full cover → 0 → clamped to **20**. The gunner's entire activation bought 5 points. Novice (acc 48): 38 → 13 → clamped 20 → pinned, still 20 — the pin is literally a no-op. Suppression is worth least exactly where the player is playing well. Fix: clamp the positional chance first, then apply status penalties multiplicatively — `base = base * (100 - SUPPRESSION_ACCURACY) / 100` — so the pin always removes a quarter of whatever is left.

**Reload costs the move, never the shot.** Scout mag 3: fire, fire, fire, reload+fire — he shoots every single turn forever, paying one stationary turn in four (and that turn is single-only, 1.70 instead of 3.40). Team Lead mag 2 fires every turn, stationary every other turn, and at move 4 / range 6 he wants to be a turret anyway — his 3.48/turn never stops. Every goblin except the Cantor has `mag_size = 0`, which `has_ammo()` treats as unlimited. The "they have infinite ammo and you do not" pressure is a 25-50% mobility tax on the two units whose job is to stand still. Make reload cost the whole activation for the Team Lead, or drop the scout to mag 2 so the tax lands on the mobile unit.

**The Cantor's one-round magazine costs him nothing.** `_ai_reload` sets `moved = true` and returns; control falls straight through to the shoot branch and `has_ammo()` is already true again ([Battle.gd:2664-2668](scripts/Battle.gd#L2664)). His rate of fire is 1/turn — identical to a Chorister's. At range 5 that is 70−15 = 55% × 4 dmg = **2.20/turn**, still 1.10 through half cover, and he is a move-3 marksman who wants to sit still anyway. The bolt-action fiction is implemented as a mobility restriction the unit does not care about. Make `_ai_reload` end the activation.

**The 5v9 attrition math favours the player about 2.3:1 per turn.** Mission 1: 29 goblin HP vs 40 scout HP, fully restored every mission (`setup()` ends `hp = max_hp`). Player output at typical range against targets in the open = 3 scouts × 1.70 + Lead 3.48 + gunner AUTO 4.64 = **13.22/turn**. All nine goblins engaged against scouts in half cover = **5.74/turn**. That is 2.2 turns to clear the map versus 7 to be wiped — and most goblins have range 2-3 and must cross 11+ tiles first, under overwatch, before contributing. Plus 2 frags at 3 damage per cell, no roll, no cover. The lever with the least collateral damage is enemy *reach*, not enemy HP: start goblins closer or in cover, or give Chorister/Novice +1 range so more of the nine contribute per turn.

**Overwatch has no counterplay.** `_best_ai_dest` never inspects `overwatching` — the word does not appear in the function ([2774-2811](scripts/Battle.gd#L2774)). Meanwhile `do_move` re-tests `_overwatchers_against` after *every step*. p(trigger) against 9-11 goblins pathfinding blind to arcs is near 1, and the gunner's watch is range 6 answering with a 2-round volley = 2.72 expected damage for an action that would otherwise be idle. One scoring line fixes it: penalise candidate cells inside `_overwatch_cells_for(watcher, watcher.facing_sector)` by ~+20. That helper already exists and is already called for the board overlay.

**Goblins always shoot the physically nearest scout.** Both fire paths call `_nearest` ([2668](scripts/Battle.gd#L2668), [2688](scripts/Battle.gd#L2688)), pure Manhattan — never hp, cover, facing, or lethality. Damage smears evenly, scouts sit at 3/8 for whole missions, and the "pull him out or lose him" moment permadeath exists for never arrives. (One lens called this a bait exploit for the Team Lead; it is not — scout, lead and gunner all have `max_hp = 8`.) Add `_best_ai_target`: score each candidate as `(lethal ? -1000) + (-10 × missing_hp) + (-60 if flanking) + (+40 if in cover) + distance`, reusing `effective_cover`/`_is_flanking` which already take two Units. ~12 lines.

**Composition is flat across all seven missions.** Every level ships exactly 3 Novices and exactly 1 Cantor (`novice_spawns` at [Levels.gd:95](scripts/Levels.gd#L95), 151, 227, 308, 360, 424, 479; `bolt_spawns` at 99, 155, 231, 309, 361, 425, 480). Totals go 9 / 11 / 11 / 11 / 12 / 11 / 13 — a 44% headcount ramp is the campaign's only difficulty lever. Against that, a Master Sergeant is +4 HP (8→12, a 50% pool increase) and +12 accuracy before the cap, and with ~78 goblins available at XP_KILL 3 the squad saturates at rank 4 well before the finale. Rebalance in Levels.gd data only: taper Novices to 0-1 by missions 6-7, ramp Cantors to 2-3 late, give THE LONG HAUL extra Skirmishers (the bare salt pan is where move-6 reads) and OUTPOST 7 extra Raiders. Same totals, different texture.

**The finale has no Choirmaster.** Mission 7 briefs "Somebody down there is keeping them" ([Levels.gd:452](scripts/Levels.gd#L452)) and fields one ordinary Cantor at (14,8), statistically identical to Dry Wash's. `Unit.Kind` has no leader entry and `_objective_complete` uses the same `eliminate` branch as mission 1. Cheapest fix with no new art: a `"choirmaster_spawn"` key spawning a GOBLIN_BOLT with overridden hp/accuracy and a `leader` flag; while he lives, nearby goblins get +1 move or immunity to the suppression penalty, and the objective label reads SILENCE THE CHOIRMASTER. An afternoon turns a bigger crowd into a target-priority puzzle.

## Architecture

Battle.gd is 3117 lines with 34 `@onready` UI refs, 119 `board.` references, and exactly one signal in the entire 8700-line codebase (`Unit.gd:7 signal died`). The decomposition below is ordered by value per hour. Every step is behaviour-preserving; do them in this order because each unblocks the next.

**1. `scripts/Rules.gd` — static combat math (2-3 hours, unblocks everything).**
Move: the balance consts at [194-236](scripts/Battle.gd#L194) (FLANK/LONG_SHOT/SUPPRESSION/FULL_COVER/PEEK/AUTO accuracy, BURST/AUTO/SUPPRESS rounds, SUPPRESS/BLAST radius, FRAG_DAMAGE/FALLOFF, DRUM_DAMAGE; THROW_RANGE has already gone, and lives with LAUNCHER_RANGE in Rules as a function of kind), plus `hit_chance` [2427-2446](scripts/Battle.gd#L2427), `_is_flanking` [2540](scripts/Battle.gd#L2540), `effective_cover` [2547](scripts/Battle.gd#L2547), `_is_peeking` [2555](scripts/Battle.gd#L2555), `_blast_cells_at` [1996-2005](scripts/Battle.gd#L1996), `_suppress_zone` [1562-1570](scripts/Battle.gd#L1562), `_overwatch_cells_for` [1289-1303](scripts/Battle.gd#L1289), `_cover_for` [1313-1319](scripts/Battle.gd#L1313), `_can_target_throw` [2113-2116](scripts/Battle.gd#L2113), `_rounds_for` [950-958](scripts/Battle.gd#L950), `_can_use_mode` [961-973](scripts/Battle.gd#L961), `_exposure_at` [2751-2765](scripts/Battle.gd#L2751). All become `static func f(board: Board, ...)`. **The `FireMode` enum at [Battle.gd:14](scripts/Battle.gd#L14) must move too** — `_rounds_for` and `_can_use_mode` take it, and `_can_use_mode` calls `_armed`, which is a one-line `is_combatant()` forward. Battle keeps one-line forwarders so no call site changes on day one. This is the prerequisite for the test seam, and it is what lets you delete `_update_unit_panel`'s duplicate of the cover-damage rule at [1098-1106](scripts/Battle.gd#L1098) (`dmg >>= 1` twice) — a second copy of `_fire_round`'s [2396-2398](scripts/Battle.gd#L2396), and the worst class of bug in a tactics game if it ever drifts.

**2. Entity index (30 min, unblocks the AI extraction).**
`unit_at` [756-761](scripts/Battle.gd#L756) and `living_units` [746-753](scripts/Battle.gd#L746) walk `entities_node.get_children()` — which holds ~48 nodes: every prop, structure root, dropped rifle, objective cache and transient damage Label ([Unit.gd:1288](scripts/Unit.gd#L1288)). `_blocked_for_team` [768-770](scripts/Battle.gd#L768) calls `unit_at`, and is the blocked predicate for every `flood_fill` in the file ([1350](scripts/Battle.gd#L1350), [1447](scripts/Battle.gd#L1447), [2505](scripts/Battle.gd#L2505), [2675](scripts/Battle.gd#L2675), [2819](scripts/Battle.gd#L2819)). The cost is not the cast — it is that `get_children()` allocates a fresh 48-element array per predicate call, ~200 times per fill. Add `var _units: Array[Unit]` and `var _by_cell: Dictionary`; append in `_spawn_unit` [677](scripts/Battle.gd#L677), remove in `_on_unit_died` [2837](scripts/Battle.gd#L2837), maintain `_by_cell` at the per-step `unit.cell = step` in `do_move` [1464](scripts/Battle.gd#L1464). ~15 lines, makes lookup O(1), and makes it testable.

**3. `tools/test_rules.gd` — headless rule tests (half a day, the highest-value thing in this section).**
The harness already exists and is proven: `tools/check_floor_sheets.gd` is `extends SceneTree` run as `godot --headless --path . -s`, and it already reaches into `Board.FLOOR_SHEETS` and `Levels.LEVELS`. Two facts make it free: `Board.set_level`/`flood_fill`/`has_line_of_sight`/`cover_between`/`peek_origin`/`can_engage` touch no tree API (`set_level` ends in `queue_redraw()`, a no-op on a detached CanvasItem), and `Unit.new()` works without Unit.tscn because `_update_sprite` guards it (`if sprite == null: return  # setup() can run before _ready() outside a live tree`, [Unit.gd:1098](scripts/Unit.gd#L1098)). **Never `add_child()` such a Unit** — `sprite` is `@onready` and `_ready()` dereferences it immediately at [Unit.gd:542-546](scripts/Unit.gd#L542); detached, `setup()` and every accessor are safe. Assert: a hand-counted flood_fill diamond; `reconstruct_path` step counts; LOS true down a lane and false through a wall; `cover_between` FULL beside wall / HALF beside junk / NONE in the open; **`peek_origin` returns a cell at a wall's END and NO_CELL against its middle** — that asymmetry is the entire peek rule and nothing tests it, which is why finding #2 shipped; `Rules.hit_chance` clamps to [20,99], loses LONG_SHOT_PENALTY per tile past `attack_range / 2` (integer division, worth pinning), and that flank and full-cover are mutually exclusive (`elif` at [2431-2437](scripts/Battle.gd#L2431)). ~120 lines covers every rule the game rests on.

**4. `_end_action(prev_state)` (30 min).**
The identical 5-line epilogue appears at `do_attack` [1514-1518](scripts/Battle.gd#L1514), `do_suppressive_fire` [1552](scripts/Battle.gd#L1552), `do_shoot_drum` [2060](scripts/Battle.gd#L2060), `_finish_throw` [2250](scripts/Battle.gd#L2250), `do_volley` [2487](scripts/Battle.gd#L2487), with three drifted variants — and `do_demolish` [1970-1976](scripts/Battle.gd#L1970) already forgot `_refresh_watch_cells()`, which is what calls `_refresh_cover()`, which is facing-dependent, on the one action that turns the unit ([1940](scripts/Battle.gd#L1940)). The stale `cover_level` is cosmetic (crouch sink + panel text; combat recomputes live), but the point is that every new verb inherits an unwritten five-item checklist and one of eight already failed it. The refreshes are idempotent — make all eight do all of them.

**5. `scripts/Scenery.gd` — ~430 lines of art tables (half a day).**
Lines [17-193](scripts/Battle.gd#L17) are pure texture tables and pixel offsets; the consumers are `_spawn_props` [478-519](scripts/Battle.gd#L478), `_dust_material` [529](scripts/Battle.gd#L529), `_spawn_prop` [545](scripts/Battle.gd#L545), the wall/wire kind helpers [560-603](scripts/Battle.gd#L560), `_load_frame_run`/`_load_structure_frames`/`_load_structure_art` [611-641](scripts/Battle.gd#L611), `_spawn_structure` [646](scripts/Battle.gd#L646), `_find_prop_anim`/`_load_still`/`_load_target_art` [1737-1770](scripts/Battle.gd#L1737), `_animate_structures`/`_sway_plants` [3054-3072](scripts/Battle.gd#L3054), `_drop_rifle` [2855](scripts/Battle.gd#L2855). Give it its own `_process` for sway/structure animation. **Watch one trap: `_spawn_props` also builds live game state** at [491-494](scripts/Battle.gd#L491) (`drums[cell] = {...}`), which `_can_shoot_drum` and `_detonate_drums` mutate — `Scenery.build()` must hand the drum cells back the way it hands back `prop_shadows`, or you will move a hazard system out of the controller by accident. `_spawn_caches` stays in Battle (it is objective state) but calls into Scenery. This is also the part that changes most often — four new prop folders are staged in this branch and would all have landed here.

**6. `scripts/BattleHUD.gd` (half a day).**
34 `@onready` refs at [293-326](scripts/Battle.gd#L293) and ~300 lines of formatting: `_update_unit_panel` [1032-1141](scripts/Battle.gd#L1032), `_unit_status` [1144](scripts/Battle.gd#L1144), `_update_objective_label` [1857](scripts/Battle.gd#L1857), `_show_briefing` [2971](scripts/Battle.gd#L2971), `_show_game_over` [2888](scripts/Battle.gd#L2888), `_progress_text` [2927](scripts/Battle.gd#L2927), `_debrief_text` [2941](scripts/Battle.gd#L2941), `show_banner` [3108](scripts/Battle.gd#L3108), plus three `_sync_*_buttons`. The button enable/disable list is written by hand three times ([364-377](scripts/Battle.gd#L364), [2592-2602](scripts/Battle.gd#L2592), [2621-2629](scripts/Battle.gd#L2621)). Attach it to the existing `UI` CanvasLayer at [Battle.tscn:19](scenes/Battle.tscn#L19) so all 34 paths shorten. Emit four signals from Battle — `selection_changed`, `hover_changed`, `turn_changed`, `objectives_changed` — the signal seam the codebase entirely lacks. Note the failure mode is milder than it looks: every order handler re-checks `state` independently, so a forgotten disable yields a lit button that refuses the order. The one genuinely unguarded handler is `_on_danger_button_toggled` [2532-2534](scripts/Battle.gd#L2532), which recomputes the overlay in any state including mid-animation.

**7. `scripts/AiPlan.gd` (2-3 hours, after #2).**
190 contiguous lines at [2645-2832](scripts/Battle.gd#L2645) split cleanly: `run_enemy_turn`/`_ai_reload`/`_ai_fire` are coroutines that `await`; `_shootable_from`/`_nearest`/`_exposure_at`/`_best_ai_dest`/`_best_watch_sector` are scoring. **They are not quite pure, and one analyst missed it**: `_best_ai_dest` calls `_free_dests` (→`unit_at`) at [2779](scripts/Battle.gd#L2779), and `_best_watch_sector` flood-fills with `_blocked_for_team.bind(...)` at [2819](scripts/Battle.gd#L2819). So `AiPlan.for_goblin(board, goblin, scouts, blocked)` needs occupancy passed in — which is exactly why the entity index goes first. Payoff: "a wounded goblin with no shot retreats to a covered cell" becomes a one-line assertion instead of a full animated enemy turn.

**8. `scripts/BattleCamera.gd` (1 hour — lowest risk, good warm-up).**
`_fit_camera` [410-433](scripts/Battle.gd#L410), `_board_world_rect` [458-465](scripts/Battle.gd#L458), `_screen_shake` [3075](scripts/Battle.gd#L3075), `_camera_kick` [3086](scripts/Battle.gd#L3086), `_hit_stop` [3101](scripts/Battle.gd#L3101), `SHAKE_OFFSETS`, and the state vars at [255-260](scripts/Battle.gd#L255). Attach to the existing Camera node at [Battle.tscn:14](scenes/Battle.tscn#L14). `_fit_camera` and `_board_world_rect` duplicate the same four-line extent math — put `world_rect() -> Rect2` on Board, which already owns TILE_W/TILE_H and `size`, and delete the copy. Delete `base_camera_pos` while you are there: it is written at [432](scripts/Battle.gd#L432) and never read anywhere in the codebase. And note the invariant at [429-431](scripts/Battle.gd#L429) — "Nothing else may write camera.position or camera.zoom" — currently enforced by a comment.

**Board should stop being the model.** Move legality is read back off the renderer: `board.move_dests.has(cell)` at [878](scripts/Battle.gd#L878), `board.attack_cells.has(cell)` at [867](scripts/Battle.gd#L867) and [1084](scripts/Battle.gd#L1084), `board.reconstruct_path(board.move_cells, cell)` at [1422](scripts/Battle.gd#L1422). Battle already does not trust it — `do_move` re-runs the entire flood_fill defensively at [1447-1449](scripts/Battle.gd#L1447) rather than using what it just drew. And `board.clear_highlights()` runs first thing in all eight verbs, ending in `set_highlights({}, {}, [])`, so the source of truth for legality is zeroed as a side effect of starting an animation. There is no live bug today (the `state != PLAYER_TURN` early-out covers it), but any future async gap becomes a phantom-move bug that cannot be unit-tested because reproducing it requires the renderer. Keep `_move_cells`/`_move_dests`/`_attack_cells` on Battle; push copies to Board for drawing only. Also fix [Board.gd:278](scripts/Board.gd#L278) `var fire_mode := 0  # mirrors Battle.FireMode` — an untyped int shadowing another script's enum with no compile-time link.

**Two smaller structural items.** (a) The map glyph vocabulary is defined three times — [Board.gd:419-431](scripts/Board.gd#L419) authoritatively, [Levels.gd:601-607](scripts/Levels.gd#L601) as the validator's own lambda, [Levels.gd:545](scripts/Levels.gd#L545) as `LEGAL_CHARS` — and the spawn-key list four times, one of which is short: `_validate_spawns` at [Battle.gd:469-472](scripts/Battle.gd#L469) omits `prisoner_spawns`, covered only because `Levels.validate_all()` happens to run first. Add `Levels.SPAWN_KEYS` + `all_spawns(data)` and `Board.kind_of_char(ch)`, derive `LEGAL_CHARS` from the latter, and make `_ready` [349-363](scripts/Battle.gd#L349) iterate a `{key: Unit.Kind}` map instead of nine near-identical loops. (b) **Keep Levels.gd and the Unit stat table as GDScript consts.** `.tres` renders the ASCII map rows — the single most-edited thing in the file — as a collapsible `PackedStringArray`, renumbers sub-resource ids on save (diff noise), and has no clean equivalent for heterogeneous objective dicts; JSON has no `Vector2i` literal. The two things a data format buys, schema validation and diffability, [Levels.gd:550-724](scripts/Levels.gd#L550) already provides. Do split `Unit.setup`'s stats out of the art match though: a `const STATS := {Kind.SCOUT: {...}}` above the `match` removes ~54 lines and makes the balance table a plain dictionary a headless test can assert invariants over — e.g. *every non-zero `damage` must be even*, because `_fire_round` halves cover damage with `dmg >>= 1` and an odd 3 silently becomes 1.

**Battle.tscn's order row should be an HBoxContainer.** Eleven buttons hand-positioned on a 105px pitch ([FaceButton `-858.0`](scenes/Battle.tscn#L59), Reload `-753.0`, Burst `-648.0`, Auto `-543.0`, Suppress `-438.0`), with three more pushed onto a second row at `offset_top = -124.0` because the first row overflowed. Adding a twelfth verb — and `hustle` already has a hotkey at [821-823](scripts/Battle.gd#L821) with no button — means recomputing five offsets by hand. The briefing panel in this same file already got containers in the last commit; the order row did not. Wrapping them also makes `set_orders_enabled(on)` a two-line loop, and `demolish_button.visible` reflows for free.

## Graphics & visual consistency

### Rendering bugs

**`_fit_camera` picks a fractional zoom, so all pixel art renders at 1.47× and shimmers.** [Battle.gd:422](scripts/Battle.gd#L422): `fit = minf(avail.x / world_size.x, avail.y / world_size.y)`. With 1280×720 and a 16×10 board that is min(0.745, 0.733) = **0.733**; props and units are drawn at 2× (`ROCK_SCALE`, `SPRITE_SCALE`), giving a net **1.467×** with nearest filtering everywhere. Source texels alternate between one and two screen pixels in an irregular pattern, so silhouettes gain and lose rows as anything moves and tile seams are uneven across the board. This is the single loudest reason the art looks softer than the source PNGs. Quantise after computing fit — `fit = maxf(floorf(fit * 8.0) / 8.0, 0.25)` gives 0.625, a clean 1.25× — and recompute `base_zoom` from the snapped value so shake/kick gains stay correct. **Incomplete on its own**: project.godot sets `window/stretch/mode="canvas_items"`, so the canvas is additionally scaled by `window_size / 1280`; the quantisation must account for the stretch scale, or lock the window to integer multiples of 1280×720.

**`fx_ground` is a sibling above Board, so permanent marks paint over every gameplay overlay.** `_setup_fx_layers` does `move_child(fx_ground, board.get_index() + 1)` ([Battle.gd:439](scripts/Battle.gd#L439)); the root is a plain Node2D with no y_sort, so equal-z siblings draw in tree order. Board's entire overlay set — move_dests, attack cells, danger, watch arcs, cover pips, blast footprint, hover outline, path dots, aim line — is one canvas item at [Board.gd:849-976](scripts/Board.gd#L849), drawn *before* up to `MAX_MARKS = 240` bullet holes (alpha 0.66), scorch discs (0.42 with a 30px rim), death stains and brass. By mid-battle the player reads the yellow move range through a growing field of craters, and it worsens monotonically. Fix with the FloorLayer split below: FloorLayer at `z_index -1`, fx_ground at 0 in tree slot 1, Board's overlay `_draw` at +1.

**HitFx never gets the additive material it was written for.** `_setup_fx_layers` builds `fx_glow` with `BLEND_MODE_ADD` ([Battle.gd:444-449](scripts/Battle.gd#L444)) and every HitFx is parented into it — but `HitFx.spawn`/`spawn_tracer` ([HitFx.gd:19-38](scripts/HitFx.gd#L19)) only do `fx.z_index = 15; parent.add_child(fx)`. `CanvasItem.material` is per-item and `use_parent_material` defaults false, so the flash disc, the 4-spoke star and the tracer render with normal alpha blend **on the same node** whose `Fx.muzzle()` sparks are additive. Two things emitted from the same point in the same frame blend differently. Set `fx.use_parent_material = true` before `add_child` and drop the `z_index = 15` line — `z_as_relative` defaults true, so on a z=15 parent it resolves to 30, not the 15 the code reads as.

**Multi-tile structures y-sort off their front cell only.** `_spawn_structure` puts the whole building under one root at `board.cell_to_global(anchor + size - ONE)` ([Battle.gd:646-665](scripts/Battle.gd#L646)) with no `y_sort_enabled` on the root, so the entire subtree sorts by that one key. Mission 3's fortress is `anchor (12,1), size (4,4)`, front (15,4), sort y = 570; its sprite spans x 448..960. A unit at **(13,5)** — walkable, on the building's front-left wall face, exactly where cover rules push you — sorts at y = 540 with a sprite spanning 452..572: entirely inside the fortress and entirely hidden. Slice the building into anti-diagonal bands with `region_enabled`, add each band directly to `entities_node`, position each at its own band's `cell_to_global`. Keeps the art and the dust material.

**Damage flashes stack un-killed tweens.** `take_damage` creates a fresh unowned tween every call ([Unit.gd:1207-1211](scripts/Unit.gd#L1207)) — unlike `_body_shove` directly above it, which kills its previous one. Total flash is 0.23 s; AUTO's cadence is ~0.166 s including the awaited `_hit_stop`, so hit 2 ramps from a partly-red sprite and shows about 57% of the first flash's swing, hit 3 less. The sprite never returns to white between rounds. On the mode whose entire trade is "how many landed", the player cannot count hits. Mirror `_body_shove`: store `_flash_tween`, kill it, reset `modulate` to white, then start the new one; shorten the return leg to ~0.10 s.

**Plants and structures animate off `Time.get_ticks_msec()`.** [Battle.gd:3054](scripts/Battle.gd#L3054) and [3066](scripts/Battle.gd#L3066) both read wall clock, which `Engine.time_scale` does not affect — while unit animation, all three Fx layers, the camera tweens and Board's objective pulse are all delta-driven and do slow down. So at the exact frame the game freezes to sell an impact, the cacti keep swaying at full speed. In practice the visibility is small (hit-stops are 45-90 real ms and plant sway is quantised to three positions over a 3.9 s period), but the fix is one line: `_anim_clock += delta` at the top of `_process` and read that instead.

### Performance

**Board repaints the entire floor every frame.** `set_objectives` enables `_process` whenever a level has caches or an extract zone ([Board.gd:361](scripts/Board.gd#L361)) — that is missions 2, 3, 4, 5 and 6 — and `_process` is nothing but `_pulse = fmod(...); queue_redraw()`. `_draw` then re-emits 160 `draw_texture_rect_region` calls, 160 antialiased grid polylines, a `draw_set_transform` pair on the ~50% of tiles with `info.flip`, and a second 160-cell prop-shadow pass with its own transform per shadow — ~320 primitives and ~120 transform-state changes, 60 times a second, for a floor where nothing moves. In GL Compatibility each `draw_set_transform` breaks the batch and each AA polyline is its own generated mesh. The other two missions pay the same cost on every mouse-motion event via `set_hover()`. Fix: child Node2D `FloorLayer` at `z_index -1` owning the tile/grid/shadow passes, invalidated only from `set_level()` and from the `prop_shadows` assignment at [Battle.gd:348](scripts/Battle.gd#L348) — **not from `_ready`**, since the floor pass reads `is_structure(cell)` for the diamond-shadow branch and structures are registered during `set_level`.

**Fx redraws its 240 static marks every frame a particle is alive.** `Fx._process` ends in an unconditional `queue_redraw()` and `_draw` always walks `_marks` first ([Fx.gd:152-185](scripts/Fx.gd#L152)) — a `draw_set_transform` + 1-2 `draw_circle` per blob, two `draw_line` per casing, transform reset each time. Marks are immutable once added. Bounded to firefights (`_process` self-disables when no particles are live, and `fx_ground` never gets `set_ambient`), but that is exactly when frames matter. Give Fx a `_marks_layer` child with its own `_draw`, redrawn only from `_add_mark`/`_add_casing_mark`.

**Unit's static initialisers load 5,008 textures at engine boot.** ~90 `static var` frame sets at [Unit.gd:81-286](scripts/Unit.gd#L81), each built by `_load_dir_frames`/`_load_rotation_frames`, which `load()` in a `while ResourceLoader.exists(...)` scan. Static initialisers run once at script load — which the autoload dependency drags in at boot — covering all nine kinds unconditionally: **~69 MB of RGBA8 as 5,008 individual GL texture objects** for a mission that fields at most nine units. It is paid once, not per scene, but it is a boot hitch and a permanent footprint, and it means unit sprites can never batch with each other. Cheapest fix: a lazily-populated `static var _sets := {}` keyed by Kind, built on the first `setup()` for that kind — a desert mission then loads three kinds instead of nine. Better: pack each direction's cycle into one horizontal strip and hand out `AtlasTexture`s, collapsing the texture count ~9× and restoring batching.

**Drum destruction frames are read from disk mid-explosion.** `_detonate_drums` calls `_find_prop_anim(DRUM_DIR, "normal_to_destroyed")` **inside** the chain loop ([Battle.gd:2093](scripts/Battle.gd#L2093)) — a `DirAccess` enumeration plus a `ResourceLoader.exists` probe per frame, per drum, after the explosion FX have already fired and during a hit-stop. `DRUM_STILL` and `DRUM_WRECK` are preloaded; only the destruction run is not. The resource cache absorbs repeats, so the stutter lands hardest on the first drum of the mission — the worst possible frame. Add `var _drum_stage_frames` filled once in `_ready`. Same trip: `_load_structure_art` [639-641](scripts/Battle.gd#L639) scans all four `STRUCTURE_DIRS` at every mission start even though two missions have no structures at all and three have exactly one — pass the level's structure list in.

**`can_engage` rasterizes the line, then `peek_origin` rasterizes it again as its own first statement** ([Board.gd:668](scripts/Board.gd#L668), [694](scripts/Board.gd#L694)), then up to 8 more `_los_ignoring` passes. Only costs on *blocked* pairs (the `or` short-circuits otherwise), but blocked pairs are exactly what the AI candidate sweep generates: `_best_ai_dest` calls `_shootable_from` and `_exposure_at` per (candidate × scout). Add a private `_peek_from_blocked(from, to)` that skips the redundant precheck, and have `can_engage` call it. Better, return the engage result and the peek cell together so `hit_chance`/`_fire_round` stop recomputing it twice more per shot ([2439](scripts/Battle.gd#L2439), [2347](scripts/Battle.gd#L2347)).

**`_compute_danger_cells` is cheaper than one lens claimed** — line [2514](scripts/Battle.gd#L2514) rejects on `danger.has(tile) or not in_bounds or not is_walkable` *before* any LOS call, so on a 160-cell map each tile costs at most one successful walk per refresh. Realistic worst case on the final map is low thousands of LOS walks, i.e. a dropped frame after each action rather than a hitch. Cache it per player turn with a dirty flag; the bounds-rejection half of the suggested fix is already there.

### Visual improvements, ranked

1. **Re-quantize Scout and Goblin_SMG_alt.** Measured max distinct opaque colours in one 60×60 sprite: **Scout 387, Goblin_SMG_alt 396**, against Goblin 72, Goblin_SMG 61, Civilian 36, Rodar_Akai 50, Hero_MachineGunner 48. `Scout/south-east.png` has 410 opaque pixels and 335 colours, 285 of them used exactly once, top-5 = 6% of pixels; `Goblin/south-east.png` has 71 colours with top-5 = 61%. The project's own gate already encodes the rule — the 80-colour budget carried per set in `tools/validate_unit_sprites.py`'s `SPECS` — and these two sets are the only ones over it. Note the gate does not currently stop them: the v2 validator made the palette budget *informational* on the legacy 60×60 tier precisely so the shipped Scout would not start failing, so the excess is reported and ignored. UNIT_ASSET_SPEC.md documents the deviation explicitly ("the Scout is noisier at ~335... Aim for the Goblin end"), so it is known and shipped. At 2× nearest-neighbour every noise pixel becomes a 2×2 screen block, so three of five player soldiers and the raider that spawns on all seven missions read as muddy dither next to clean flat goblins. `Image.quantize(colors=64, method=MEDIANCUT, dither=NONE)` against a fixed desert palette, then re-run the validator. **Add the palette check to a pre-import gate.**
2. **Fix the mixed pixel density.** `_spawn_prop`'s default is `ROCK_SCALE = (2,2)`, but five callers pass an explicit 1× over native-resolution art: the Choir cache (80px, [Battle.gd:512](scripts/Battle.gd#L512)), the ammo crates (96px, [Battle.gd:171](scripts/Battle.gd#L171) — whose own comment admits "drawn at 96px against the 48px the junk props use"), and the camp's crate/stores/briefing table (72px and 96px, [Camp.gd:237](scripts/Camp.gd#L237), [352](scripts/Camp.gd#L352), [368](scripts/Camp.gd#L368)). I checked the obvious refutation — that the 96px art might be a 2× upscale, which would make texel sizes match — by counting horizontal colour changes at even vs odd x boundaries: crates 1621/1556, cache 883/872, table 1067/1078, drum 398/418. All balanced; every one is native-res. So the crate stack beside a soldier has literally half-size pixels, and since Camp.tscn is the main scene, **the briefing table is the first art the player ever sees.** Downsample 96→48, 80→40, 72→36 nearest-neighbour, re-measure offsets, delete the five scale arguments, then make the `scale` parameter non-optional so nothing can silently opt out again.
3. **Give the HUD a Theme.** There is no `.tres`, `.theme`, `.ttf` or `.otf` anywhere in the project and no `gui/theme/custom` in project.godot. All 16 Buttons in Battle.tscn set only `theme_override_font_sizes`; `UI/UnitPanel` is a bare PanelContainer drawing Godot's default dark rounded panel; HpLabel/StatsLabel/StatusLabel set no `font_color` and render default white while NameLabel and ProgressLabel directly above them use hand-authored warm tones (0.96,0.9,0.72 / 0.78,0.72,0.55). A hand-made desert pixel board framed in Godot blue-grey and antialiased Noto Sans. Build `assets/ui/thinshot.theme` with a bitmap font (`subpixel_positioning = 0`, AA off) and StyleBoxFlats in the existing palette (#241d13 / #7d6a45 / #f5e6b8), set it as `gui/theme/custom`, delete the per-node overrides.
4. **Unify the frame.** `prop_dust.gdshader` is the only shader in the project and is applied to props and structures only — its header states units are deliberately excluded. The floor's only lighting is a 0.94–1.00 per-cell `shade` multiplier. There is no CanvasModulate, no vignette, no grade anywhere in the playing frame. Three separately-graded populations share one screen: hazed warm scenery, a nearly flat floor, and fully saturated units with no atmosphere. Two cheap GL-Compat additions in `_setup_fx_layers`: a CanvasModulate driven by `board.floor_mood()` (warm amber for desert/salt, cold grey-blue for ash) grading everything in one node at zero cost, and a CanvasLayer above the world holding a full-screen ColorRect with a 6-line radial vignette shader tinted from the same mood dict.
5. **Raise the aim line above Entities.** Every prop, wall, hut and unit goes into `entities_node`, which is child index 2; Board is index 0 with no z_index anywhere. So the dashed aim line ([Board.gd:969-976](scripts/Board.gd#L969)) — whose colour switches between `AIM_LINE`, `AIM_LINE_COVER` and `AIM_LINE_FLANK` specifically to answer "does this shot clip cover" — is erased by exactly the rock or wall it is asking about. Same for the path preview and hover outline. **The precedent is already in this codebase**: [ObjectiveMarks.gd:8-11](scripts/ObjectiveMarks.gd#L8) diagnoses the identical problem verbatim and solves it with a `z_index = 40` beacon layer — but only for objectives. Move lines 950-976 plus the blast footprint into a third CanvasItem above the y-sorted range; leave the ground fills where they are so they still read as painted on sand.
6. **Make smoke look like smoke.** One `draw_colored_polygon` per cell at `Color(0.74,0.72,0.68,0.50)` with a hard diamond edge, drawn below Entities so units stand on top of it, plus `_boil_smoke` spending a flat 14 puffs/second across the *whole* cloud at alpha 0.10-0.20 — a 3×3 cloud averages 1.5 near-invisible puffs per cell per second. Smoke genuinely blocks LOS for both sides ([Board.gd:560](scripts/Board.gd#L560)), but it reads as a movement highlight. Draw the edge only on cells with no smoke neighbour (reuse the `COVER_EDGES` test at [Board.gd:218](scripts/Board.gd#L218)) so the cloud has one silhouette, drop the fill to ~0.25, scale the puff accumulator by `smoke.size()`, and add a heavier `smoke_drift` variant at alpha 0.30-0.45 on `fx_air` so it actually screens.
7. **Give the grenade a body.** `_throw_arc` is nine `fx_air.smoke_drift` calls ([Battle.gd:2143-2149](scripts/Battle.gd#L2143)) — each one particle at 10-20% alpha, randomly displaced up to 30px off the parabola, larger than a grenade, living 1.1-2.0 s against a 0.42 s throw. And `_boil_smoke` uses the identical call for standing clouds, so **a frag in flight and a smoke already on the ground look the same.** Add an `Fx.grenade(pos)` emitting one high-contrast dark pixel at alpha 1.0 with a life just over one arc step, plus a ground shadow tracking the un-lifted lerp.
8. **Recolour Goblin_SMG_alt onto the Choir ramp.** It has saturated blue trousers, near-white shoes and a red hip pouch against a family documented as "green-skinned in darker rags" (#7d9352 / #61724b / #385836 over #00090b outline). It has no dominant colour at all — 2342 distinct colours across its 8 standing rotations, top colour under 1%. It spawns on all seven missions. (The "cyan weapon" one lens reported does not hold up — the weapon clusters are #293437 and #545654, dark blue-grey.) Do it in the same pass as the Scout quantization; regenerating at 60×60 would also let you delete the bespoke `SPRITE_OFFSET_56` at [Unit.gd:421](scripts/Unit.gd#L421) and the dedicated `SMGA_MUZZLE_OFFSETS` table.
9. **Darken the bolt marksman's head-wrap.** Goblin_BoltRifle's third most common colour is `#f8fcfc` at 10.9% of pixels; near-white total 13.8%; mean HSV value 0.380 against Goblin 0.221, SMG 0.212, revolver 0.298 — the other three have essentially zero near-white. One goblin per map is the brightest object on the board, and ASSETS.md keeps the floor mid-tone specifically so highlights, danger hatching and the selection ring read on top. Units get no dust shader, so nothing pulls it back down. Shift to a dusty bone tone in the sandbag family (#caa971 / #c4a275).
10. ~~**Resolve the orphaned hero art.**~~ — **done: repointed, and nothing was deleted.** `Hero_MachineGunner` is Brukk Meshan's set and the game draws it. [Unit.gd:70](scripts/Unit.gd#L70) sets `MG_ROOT` to `res://assets/sprites/Hero_MachineGunner`, with a second const `MG_BASE` adding the nested `/Hero_MachineGunner` segment for the base state's rotations and animations — this set ships on the canonical layout (UNIT_ASSET_SPEC.md §4), where the doubled segment belongs on the base state, not on the root the way the old one did. `Rodar_Akai` is wired as its own `Kind.HERO` behind `RODAR_ROOT` ([Unit.gd:78](scripts/Unit.gd#L78)), and both directories are tracked now, so neither is work in flight any more. `LEAD_ROOT` was deliberately **not** repointed: Rodar is a kind of his own, and `Scout_TeamLead` still backs the legacy `Kind.TEAM_LEAD`. **The folder name is a trap worth reading twice** — `Hero_MachineGunner/` is `Kind.MACHINEGUNNER`, raw ordinal 2, Brukk Meshan; `Kind.HERO` is ordinal 9, Rodar Akai, and his art is `Rodar_Akai/`. The name is historical: it is the PixelLab `Hero_bandana` group. **And the three Scout sets stay.** `Scout`, `Scout_TeamLead` and `Scout_MachineGunner` are the generic Kestrel troops — the bodies for cut scenes, for making a garrison feel inhabited, and for missions where another squad fights alongside the player's. `Scout` is still `Kind.SCOUT` (Josen Marr and the line riflemen), `Scout_TeamLead` is still `Kind.TEAM_LEAD` (legacy, never re-recruited, still reachable), and only `Scout_MachineGunner` stopped backing a named soldier. They are not spare copies of the named soldiers' sprites; the enum says so at [Unit.gd:22-26](scripts/Unit.gd#L22) so that the next audit does not tidy them away. Measured on the set now shipping: 600 PNGs, all 60×60, 8 animation sets, palette max 48 colours, feet 14 px below canvas centre in all 8 standing rotations (the validator's count; the addendum table measures the same line as 15.0) — bbox-identical to the Scout set's, so `SPRITE_SPECS.DEFAULT` still applies and `MACHINEGUNNER` needs no entry of its own. `tools/measure_muzzle.gd`'s `GUNNER` entry was repointed at the Hero aim rotations and re-run: 7 of 8 facings now measure exactly, and only *south* keeps the documented hand-correction, because the scan lands on his boots there. Two aim-idle defects were repaired before the swap shipped — a 35 px lump of detached ejecta beside him for 5 frames of 9 in *north-west*, and a puff drifting off in *east* — using `tools/fix_idle_flash.py`, which grew a third "debris" detector for them and deletes rather than grafts, since a disconnected lump cannot take a pixel of the soldier with it. And because the frame loaders fail silently, `tools/check_unit_art.gd` now asserts that every `Unit.Kind` really loaded all 11 of its frame sets; nothing caught an empty set before.
11. **Delete the two duplicate machinegunner stance folders.** Still there, still duplicates — but the reason to care changed. `MG_ROOT` no longer points into `Scout_MachineGunner` at all (see #10), so *neither* copy is loaded during play; the set is generic-troop art now. `assets/sprites/Scout_MachineGunner/Dead_Stance/` and `.../ReadyToFire_Stance/` sit one level above the nested set that is the real one, and `diff -rq` still reports only `.import` files differing: all 88 PNGs are byte-identical, which is exactly why this set counts 688 against every other complete unit's 600. Because the `.import` UIDs differ, both copies still land in the pack. The trap they set turned out to be for tooling rather than for the eye. `tools/check_unit_complete.py` matched stance folder names case-sensitively, so the capital-S `Dead_Stance` at the top level was picked as this unit's base state and the tool reported PASS over 96 of its 688 files. That is fixed — the match is case-insensitive now, and it reports 8 animation sets / 600 PNGs here — but the duplicates are what made a green check meaningless in the first place, and they are still capable of doing it to the next tool.
12. **Decide on the five unwired environment folders.** 80 PNGs across Desert_Makeshift_Junk_Statue (2 @ 256px), Hidden_cache_of_money (30 @ 64px), Illegal_rune_technology (20 @ 96px), Makeshift_goblin_drug_still (20 @ 80px), Desert_Market_Stall (8 @ 97px) — referenced nowhere. These are exactly the Rust-Choir set dressing ASSETS.md tier 4 asks for. Note none of them is on the documented 48px ground-prop canvas, so wiring them requires downsampling first or they inherit the density bug above. The two-state Junk_Statue fits `TARGET_PROPS` as a demolish target; the Market_Stall fits `STRUCTURE_DIRS` as a 2×2 kind. Wire or delete — leave nothing imported-but-unnamed.
13. **Animate the camp.** `Battle._load_structure_frames` scans `<dir>/animations/<prompt-folder>/unknown/` and falls back to a still; `Camp._spawn_structure` ([Camp.gd:246-253](scripts/Camp.gd#L246)) loads only `rotations/unknown.png`. The breeze frames exist for all three camp kinds. Camp.tscn is the main scene, so the first thing the player sees is the same tent that breathes in the desert standing perfectly still — and the camp's plants do not sway either (no `_swaying` equivalent). Both Battle helpers are already `static func`; call them.
14. **Generate the team lead's alt idle.** Resolving all 90 loader paths against disk, 89 hit a full 8-direction × 9-frame set. The one miss is `LEAD_ROOT + "/standing_stance/animations/standing_idle_alt"` ([Unit.gd:138](scripts/Unit.gd#L138)) — the directory does not exist, which is why Scout_TeamLead counts 528 PNGs (600 − 72). Not a crash; the guard at [Unit.gd:1064](scripts/Unit.gd#L1064) means the 14% roll simply never fires. Every other soldier and goblin breaks its idle loop; this set is the only one that does not. It stings less than it did: `Kind.TEAM_LEAD` is legacy now that Rodar Akai holds the lead slot, so the miss shows on cut-scene bodies and allied squads rather than on the unit the player selects first every turn. No code change needed — or take Rodar_Akai's, which has the full set. (That 90-path census predates both the machinegunner repoint and the five `Kestrel_*` sets, so the total is larger now and unaudited; the one miss is still the miss.)

## Design: fun, AI, and pacing

**The core loop has a hole in it: you cannot see a shot's odds until after you have irrevocably committed the move.** `_refresh_highlights` builds the target list from `selected.cell` only ([Battle.gd:1354-1357](scripts/Battle.gd#L1354)); `_update_unit_panel`'s hit readout reads `attacker.cell` live and only fires when `board.attack_cells.has(unit.cell)`; and hovering a move destination in `_update_hover` produces a path and nothing else ([1421-1422](scripts/Battle.gd#L1421)). Cover *is* answered from the prospective cell — [1366-1370](scripts/Battle.gd#L1366) marks covered move-dests and [1435-1437](scripts/Battle.gd#L1435) re-focuses the overlay on the hovered tile, which Board draws as per-edge cover bars — so do not re-implement that half. What is missing is range, LOS, flank, peek and hit chance from where you are thinking of standing. In a cover-and-facing tactics game, "if I stand there, what is my shot" *is* the decision; here you spend the move to find out, and `do_move` sets `moved = true` with no way back. Every advance is a blind bet. This single gap turns the game's four best systems into post-hoc explanations. Fix: in `_update_hover`, run the same range + `can_engage` loop against the hovered cell and push it to a new dimmer `projected_attacks` overlay, and add one line to the panel — `FROM HERE: n% ON <role>`. Refactor `hit_chance`/`_is_flanking`/`effective_cover`/`_is_peeking` to take an origin-cell parameter defaulting to `attacker.cell` (which the Rules extraction does anyway) and nothing else changes.

**Every committing click is a single unconfirmed left-click.** `_handle_click` commits instantly at [878-880](scripts/Battle.gd#L878) and [866-868](scripts/Battle.gd#L866). `do_move` walks, resolves every reaction shot, sets `moved = true`, and stores no prior state — there is no undo path anywhere in the file. A one-pixel slip on an isometric diamond walks a scout into an amber cone; a misclick with Burst armed spends two of a scout's three rounds; `hit_chance` floors at 20 so a stray click can throw away an activation on a 20% shot. The mitigation is that a death is only *provisionally* permanent — `Game.abort_mission` restores the whole roster from the `begin_mission` snapshot, so it sticks only when the mission is won. That is a real safety net and it means the ask is smaller than it looks: cache `{cell, moved, facing_sector}` before the walk and add `_undo_move()` on Z, legal while `not unit.acted` and no reaction fired (set a `_move_was_contested` flag in the watchers block at [1466](scripts/Battle.gd#L1466)). Add double-click-to-confirm only for destinations inside `watch_cells` or `danger_cells` — those cones are already drawn, so it is refinement rather than new information.

**"Never move" is the optimal play on all seven maps, and nothing punishes it.** `_best_ai_dest` scores `manhattan(cell, chase_cell) + exposure_weight * _exposure_at(...)`, and `_exposure_at` only counts scouts already within their own attack range with LOS — so a goblin outside that envelope scores pure distance and always steps closer. The AI is not naive elsewhere (−1000 for a cell with a shot, +400 if the target is in cover, −60 for a flanking angle, exposure weight jumping to 25 at hp≤2, wounded goblins genuinely retreat), but **Levels.gd carries no turn limit, no reinforcement and no timer on any of the seven entries**, and `turn_number` is only ever printed. So the unbeatable strategy everywhere is: hold the start line, everyone on overwatch facing east, shoot them as they arrive, then stroll to the objective. Missions 1 and 7 play identically despite fifteen missions' worth of writing between them. Two cheap levers: an optional `"pressure": {"turn": N, "spawns": [...]}` per mission with a `_spawn_reinforcements()` call at the top of `run_enemy_turn`, and a penalty in `_best_ai_dest` for leaving cover when no scout is inside the goblin's threat envelope, so ranged goblins hold ground instead of feeding themselves in one lane at a time. **And put `turn_number` on screen** — it is console-only today, and the player cannot feel a clock that is invisible.

**Honest AI assessment:** the scoring function is better than its reputation — it prefers firing positions, values the target's cover, prefers flanking angles, avoids turning its back, and retreats when wounded. Three specific things are missing, all cheap: it does not choose *whom* to shoot (`_nearest`, distance only), it does not see overwatch arcs at all, and it values cover it will not be facing into (`cover_between` has no facing term while `effective_cover` does). Fix those three and the enemy turn becomes genuinely threatening without touching a single stat.

**The enemy turn is 10-15 seconds of unskippable watching every round.** Per goblin: `ACT_LEAD_IN` 0.15 + `AI_BEAT` 0.12, plus `MOVE_STEP_TIME` 0.16 per tile, plus a shot (raise 0.28 + tracer 0.09 + awaited hit-stop + lower 0.12). **One lens claimed the lead-in is double-counted against a stale comment; I checked `git show 38cb126` and the commit that added `ACT_LEAD_IN := 0.15` lowered `AI_BEAT` from 0.25 to 0.12 in the same diff — the comment is accurate and the net cost is +0.02 s per goblin.** The duration is also lower than claimed, because `run_enemy_turn` shoots without moving when a shot exists from the current cell: ~0.82 s to shoot only, ~0.9 s to move only. That is still 10-13 s on the 11-goblin maps and ~15 s on the finale, with `_unhandled_input` returning immediately during ENEMY_TURN so no key does anything. Over a 12-turn mission the player spends 2-3 minutes watching. Add hold-to-fast-forward in `_process` (`Engine.time_scale = 3.0` while `ui_accept` is held and `state == ENEMY_TURN`, guarding the `_hit_stop` restore which already binds to the Engine singleton), and skip both beats entirely for goblins that neither move nor shoot.

**The HUD has no roster and no turn counter.** The UI CanvasLayer holds a turn banner, an objective label, sixteen buttons, one unit panel and two modals. **One lens overstated this** — `Unit._draw` already puts HP pips, ammo pips (red when empty), cover bars, rank chevrons, an overwatch diamond and a suppression chevron on the board itself, so per-soldier HP and ammo *are* visible. The three real gaps: no roster strip (so auditing five soldiers means Tab-cycling and hovering one at a time, which is exactly what makes the unguarded End Turn punishing), no turn number, and no distinction between "moved but can still shoot" and "fresh" — `do_move` sets `moved = true` without touching `modulate`, so those look identical. Add an HBoxContainer of small per-soldier panels (surname, state chip READY/MOVED/DONE/WATCH/PINNED, click to select), put `turn_number` in the banner string, and give "moved" its own half-tint in `set_done`'s sibling path.

## Feature roadmap

**1. Campaign save/load.** *Buys:* the campaign becomes playable across sessions — which is what makes permadeath, named survivors, ranks and perks mean anything at all, and what makes the already-excellent `begin_mission`/`abort_mission` rollback matter outside one sitting. *Costs:* [Game.gd](scripts/Game.gd) only, ~40 lines. *Sketch:* `save()` writes `JSON.stringify({roster, _next_id, current_operation, current_level, in_the_field, frags, smokes, pending_promotions})` to `user://campaign.json`; `load_save()` parses with explicit `int()`/`bool()` coercion and resets `_snapshot`/`mission_xp`/`mission_dead`; call from `commit_mission`, `abort_mission`, `_ready`. Mission granularity, never mid-battle.

**2. Projected shot preview from the hovered destination.** *Buys:* converts every advance from a blind bet into a decision, and retroactively makes peek, flank, cover and long-shot falloff visible systems instead of after-the-fact explanations. The single largest fun delta available. *Costs:* [Battle.gd](scripts/Battle.gd) `_update_hover`/`_update_unit_panel`/`_refresh_highlights`, [Board.gd](scripts/Board.gd) one new overlay array. *Sketch:* add an optional `from_cell` parameter to `hit_chance`/`effective_cover`/`_is_flanking`/`_is_peeking`, run the range + `can_engage` loop against the hovered cell, draw the results in a dimmer attack tint, and print `FROM HERE: n% ON <role>` for the best target.

**3. Free undo + end-turn confirmation.** *Buys:* removes the #1 rage-quit source in the genre. Cheap because a mission-level rollback already exists; this is the move-level equivalent. *Costs:* [Battle.gd](scripts/Battle.gd) `do_move`, `_handle_click`, `end_player_turn`, one new binding in project.godot. *Sketch:* cache `{cell, moved, facing_sector}` before the walk; `_undo_move()` on Z restores it while `not unit.acted` and no reaction fired; `end_player_turn` counts unspent soldiers and requires a second press inside 2 s.

~~**4. Mission pressure — turn clocks and reinforcements.**~~ — **half done.** The reinforcement half shipped, but not as a level table: arrivals are the campaign's own escapees walking back on, so they carry names the player has seen rather than being anonymous pressure (see *The ones who came back* below). What is still open is the turn clock, the on-screen turn counter, and the `_best_ai_dest` cover-holding penalty — those are what actually punish holding the start line, and this feature does not.

**Original entry:** *Buys:* kills the "hold the start line and overwatch" dominant strategy on all seven maps, and finally differentiates the destroy/extract missions from the eliminate ones. *Costs:* [Levels.gd](scripts/Levels.gd) data + ~30 lines in [Battle.gd](scripts/Battle.gd) `run_enemy_turn`, plus the turn counter in the banner. *Sketch:* optional `"pressure": {"turn": N, "spawns": [...], "edge": ...}` per mission; `_spawn_reinforcements()` keyed off `turn_number` at the top of `run_enemy_turn`; add a cover-holding penalty to `_best_ai_dest` so ranged goblins stop feeding themselves into the kill zone.

**5. The Choirmaster.** *Buys:* seven missions of escalating narrative currently resolve into "kill thirteen of the same goblins" with the same `eliminate` handler as mission 1. This makes the finale a target-priority puzzle for roughly an afternoon of work and no new art. *Costs:* [Levels.gd](scripts/Levels.gd) one key, [Unit.gd](scripts/Unit.gd) a `leader` flag, [Battle.gd](scripts/Battle.gd) `_spawn_unit` + `_objective_complete` + `_update_objective_label`. *Sketch:* `"choirmaster_spawn": Vector2i(...)` spawns a GOBLIN_BOLT with overridden max_hp/accuracy and `leader = true`; while alive, goblins within N tiles get +1 move or ignore the suppression penalty; objective label reads SILENCE THE CHOIRMASTER.

## What is already good

**The isometric board is genuinely well-built.** [Board.gd](scripts/Board.gd) owns cell↔world math, LOS, cover levels, peeking, flood-fill pathfinding, a tile cache and all the overlays in 976 readable lines, and — crucially — `set_level`, `flood_fill`, `has_line_of_sight`, `cover_between`, `cover_map_at`, `peek_origin` and `can_engage` touch no tree API. That is what makes the whole test plan above nearly free. The two defects found in it are both in one function's ignore-list.

**The peek rule is a real idea, correctly conceived.** The doc comment at [Board.gd:658-665](scripts/Board.gd#L658) — "Lean past the end of a wall run and the shot is there; lean against the middle of an unbroken wall and the next section is still in the way" — is a genuinely good mechanic that most tactics games do not attempt. The implementation has a bug; the design does not. Fix the ignore set and leave the rest alone.

**The campaign rollback is exactly right.** `begin_mission()` snapshots the roster, `abort_mission()` restores it wholesale, `commit_mission()` promotes and clears — so a failed attempt costs nothing and cannot be farmed for XP, and provisional deaths un-kill themselves. It is a clean, correct, deliberately-designed transaction boundary, and it is also the natural save point. Do not disturb it; just persist it.

**`Levels.validate_all()` is a real schema check that runs in release.** `_validate`, `_validate_floor` and `_validate_objectives` ([Levels.gd:550-724](scripts/Levels.gd#L550)) check legal chars, spawn walkability, connectivity and objective placement, called from `Battle._ready()` at line 332 with a comment explaining that it is `push_error`-based so it reports in release too. Very few projects at this stage have this. It is why the ".tres vs GDScript" question answers itself: the data format already has the property people migrate for.

**The animation state machine in [Unit.gd](scripts/Unit.gd) is careful.** `_anim_return`, `_rifle_is_up()`, the eight-sector facing model, the deliberate `if sprite == null: return` guard so `setup()` works outside a live tree, the `null` padding in `_load_rotation_frames` so a missing file degrades instead of crashing, the corpse tint, the per-unit HP/ammo/cover/rank/overwatch pips drawn straight onto the board. One loader (`_load_only_anim`) breaks the 8-entry invariant everything else maintains; that is the exception that proves the pattern.

**The prose. All of it.** Seven mission briefings, orders and debriefs; a `_debrief_text` that reads out who died by name; and — unusually — code comments that explain *why*: "the map edge is something to put your back to", "a reload mid-hit-stop must never persist", "Prisoners come through a blast untouched... the kind of thing that turns a rescue into a chore", "Credited before the damage lands, while the victim is still alive to be inspected". Several of the bugs above were found *because* a comment stated the intent clearly enough to contradict the code.

**The camera and impact layer.** `_hit_stop` binds its restore to the Engine singleton so a scene reload cannot strand slow-motion; `_ready` defensively resets `Engine.time_scale`; `_screen_shake` and `_camera_kick` compose into a single `camera.offset` write with a documented single-writer invariant. It is subtle work that deserves to live somewhere findable — hence the BattleCamera extraction — but it is correct.

## Do this first

1. **Gate the debug level jumps.** (15 min) Wrap the hotkey loop at [Battle.gd:833-836](scripts/Battle.gd#L833) in `if OS.is_debug_build():` and key the three win-screen buttons' visibility off the same at [383-387](scripts/Battle.gd#L383). Zero risk, and it removes both the only irreversible destructive action in the game and the unbounded XP farm.

2. **Batch the four one-to-fifteen-line correctness fixes.** (1 hour total) `_end_sustained_fire()` as the first line of `_show_game_over` [2889](scripts/Battle.gd#L2889); `if not _can_use_mode(unit, fire_mode): _set_fire_mode(_default_fire_mode(unit))` at `do_move`'s tail [1494](scripts/Battle.gd#L1494); `board.can_engage(origin, tile)` at [2517](scripts/Battle.gd#L2517) plus `danger_on := true` at [250](scripts/Battle.gd#L250); delete `pending_promotions.clear()` at [Game.gd:374](scripts/Game.gd#L374). Four separate reported bugs, one sitting.

3. **Fix the blast/win-check ordering.** (1 hour) `_resolving_blast` flag set around the loop in `_apply_blast`, consulted by `_on_unit_died`, with one `check_game_over()` after the loop. This one is corrupting roster data every time it fires, silently.

4. **Fix `peek_origin` and the map-edge cover.** (1-2 hours) In [Board.gd:672-674](scripts/Board.gd#L672) add the `in_bounds` guard; at [683](scripts/Board.gd#L683) narrow the ignore to `{cover_cell: true}`. Then decide on the edge: returning `NONE` from `cover_level_of` for out-of-bounds kills the phantom perimeter cover dots, the fake crouch and the free perimeter lean in one line — I recommend it, since zero real shots ever receive edge cover anyway. Play one mission on OUTPOST 7 afterwards; this changes 260+ shot legalities.

5. **Add campaign save/load.** (half a day) See feature #1. Test the round trip specifically for `rank` and `xp` coming back as floats.

6. **Extract `scripts/Rules.gd`.** (2-3 hours) Move the balance consts, `FireMode`, and the ten pure functions; leave one-line forwarders on Battle so no call site changes. Mechanical, zero behaviour change, and it is the gate for everything after.

7. **Write `tools/test_rules.gd`.** (half a day) `extends SceneTree`, modelled on `tools/check_floor_sheets.gd`. Pin flood_fill counts, `reconstruct_path` lengths, LOS through and around a wall, `cover_between` at all three levels, **`peek_origin` at a wall's end vs its middle**, and `hit_chance`'s clamp / long-shot integer division / flank-cover exclusivity. Never `add_child` a bare `Unit.new()`. Run it after every change from here on.

8. **Add the entity index.** (30 min) `_units` array + `_by_cell` dictionary, maintained in `_spawn_unit`, `_on_unit_died` and `do_move`'s per-step assignment. Makes `_blocked_for_team` O(1) and unblocks the AI extraction.

9. **Build the projected shot preview.** (half a day) See feature #2. This is the change that most improves the game as a game, and step 6 has already given you the origin-cell parameter.

10. **Fix the machinegunner's last round and give suppression teeth.** (2 hours) `Unit.min_rounds()`, redefined `needs_reload()`, and the highlight gate — then, in the same sitting, add `or watcher.is_suppressed()` to `_overwatchers_against` [2567](scripts/Battle.gd#L2567) and `origins = []` for immobile goblins in `_compute_danger_cells` [2504](scripts/Battle.gd#L2504). Three findings, one weapon system that starts behaving as advertised.

11. **Do the balance pass in one commit.** (2 hours) `AUTO_ACCURACY` −15 → −35; `-8` accuracy_mod on BURST at [911](scripts/Battle.gd#L911); apply the clamp before status penalties in `hit_chance` and make suppression multiplicative; `_ai_reload` ends the Cantor's activation; add `_best_ai_target` and the overwatch-arc term to `_best_ai_dest`. With the test script in place you can change all of these at once and still know what broke.

12. **Do the visual pass in one commit.** (half a day) Quantise the camera zoom in `_fit_camera`; split Board's floor into a `FloorLayer` at `z_index -1` and re-order fx_ground between it and the overlays; set `use_parent_material = true` in HitFx and drop its `z_index`; kill the previous flash tween in `take_damage`; re-quantize Scout and Goblin_SMG_alt to ≤80 colours and add the palette check to a pre-import gate. Five fixes, one screenshot, and the game stops looking softer than its own source art.
---

## Addendum: measured art metrics

Everything in this section was produced by running the project's own tooling and measuring
the PNGs directly, rather than by reading code. It corrects and extends the visual-consistency
section above.

**The project is clean at the build level.** `godot --headless --path . --quit` under
Godot 4.7.stable returns zero parse errors, zero import errors, and bootstraps the campaign
correctly (5 recruits, OPERATION DRY CHOIR mission 1/3). Whatever else is wrong, nothing is
broken enough to stop the engine.

**`tools/validate_unit_sprites.py` now fails on 1 of the 16 unit sets.** There are 16 unit
folders under `assets/sprites/` (everything but `Environment/`): the original 11, plus the five
`Kestrel_*` specialists. Re-run per set with `--no-preview`, the only FAIL is
**Scout_MachineGunner**, on the foot line — `ReadyToFire_Stance: feet 14-17px below centre
(want 12-16)`, twice. Everything else passes.

Five of those six now pass and not one of them was repainted: the change is in the validator,
not the art. The v1 tally recorded here (6 of 11 failing:
Scout, Scout_MachineGunner, Goblin, Goblin_SMG, Goblin_SMG_alt, Goblin_revolver) was measured
against a tool that assumed one 60×60 spec for every set. v2 gives each set its real canvas,
foot range and palette budget, and tiers the enforcement: the legacy 60×60 palette budget is
informational (so the shipped Scout at ~387 colours reports and does not gate), and the newly
validatable 64/56 goblin sets are advisory unless run with `--strict`. Read the current PASSes
accordingly — they mean "nothing gated", not "nothing found". One caveat worth carrying:
`Hero_MachineGunner` passes with a note that `Dead_stance` has no character id in its
`metadata.json`.

The five `Kestrel_*` sets used to be the other caveat — no `SPECS` entry at all, so they fell
through to the measured-canvas fallback where *every* finding is advisory, which made the five
newest units in the game the only ones nothing could gate. They have entries now
([validate_unit_sprites.py:107](tools/validate_unit_sprites.py#L107)) and gate on the same
legacy-60 contract as the rifleman they were generated against. Their one real deviation is
registered rather than muted: a south (and on three of them north) aim pose drawn with the
weapon levelled to a flank instead of foreshortened, declared per unit as `aim_levelled` so
that facing is checked against the pose actually drawn while the other six still gate. Muting
the whole `aim` category for them would also have hidden a missing weapon, which is the thing
that check exists to catch. The muzzle offsets in `Unit.gd` follow the art for exactly those
facings, so the flash still leaves the barrel the player can see.

### The 64×64 sheets sink below the tile — and nothing handles them

Measured canvas size and drawn foot line (median over the 8 standing rotations, distance in
texture px from canvas centre to the bottom edge of the lowest opaque row — one more than the
row *index* `tools/validate_unit_sprites.py` prints, so this table's 15.0 and the validator's
"feet 14px below centre" are the same foot line):

| Set | Canvas | Feet below centre | Anchor applied | Error |
|---|---|---|---|---|
| Scout, Scout_TeamLead, Scout_MachineGunner, Goblin_BoltRifle, Civilian, Hero_MachineGunner, Rodar_Akai | 60×60 | 15.0 | `SPRITE_OFFSET` −15 | exact |
| Goblin_SMG_alt | 56×56 | 14.0 | `SPRITE_OFFSET_56` −14 | exact |
| **Goblin** | **64×64** | **15.5** | `SPRITE_OFFSET` −15 | **−0.5 tex = 1 screen px** |
| **Goblin_SMG** | **64×64** | **15.5** | `SPRITE_OFFSET` −15 | **−0.5 tex = 1 screen px** |
| **Goblin_revolver** | **64×64** | **16.0** | `SPRITE_OFFSET` −15 | **−1.0 tex = 2 screen px** |

`Unit.gd:740` reads `sprite_offset = SPRITE_OFFSET_56 if kind == Kind.GOBLIN_SMG_ALT else SPRITE_OFFSET`
— a special case for the one 56×56 set, and nothing for the three 64×64 sets. At `SPRITE_SCALE`
(2,2) those three goblin types stand 1–2 screen pixels below their diamond. The Novice
(`Goblin_revolver`) is both the worst offender and the most numerous enemy in the game.

The reason it was missed is a comment. `Unit.gd:414-417` states the baseline canvas is 64×64
with the alt raider as the deviation. Measurement says the opposite: **60×60 is the baseline**
(12 of the 16 sets, including every player unit — the seven above plus all five `Kestrel_*`
specialists) and the 64×64 goblins are the deviation. The special case was written for the
wrong exception.

Fix: `const SPRITE_OFFSET_64 := Vector2(0, -16)`, selected for `GOBLIN`, `GOBLIN_SMG` and
`GOBLIN_REVOLVER`; correct the comment. Or regenerate those three at 60×60, which also lets
you delete both bespoke offsets and the `SMGA_MUZZLE_OFFSETS` table.

### Figure scale is *not* a problem — checked and cleared

Drawn figure heights are consistent across every set: 28–31 px (Goblin 29, Scout 30,
Goblin_revolver 31, Goblin_SMG_alt 28, Rodar_Akai 30.5). The differing canvas sizes do **not**
make goblins render larger — only the foot line moves. This was the obvious hypothesis and it
is wrong; do not "fix" the figure scale.

### Five animation defects the tooling caught

- **The Novice fires while standing still.** `Goblin_revolver`'s *east* aim-idle contains a
  muzzle flash in frames 4–5 (bright-pixel counts `[0,0,8,0,20,19,6,6,0]`). The aim-idle is a
  loop, so an east-facing Novice on overwatch visibly discharges its revolver on a cycle
  without a shot ever being resolved. Every other set and every other direction is clean.
- **Corpses teleport on handoff.** `standing_idle_to_dead` must land on `dead_stance`; the
  worst endpoint gap measured: **Goblin_revolver 167 px**, Goblin_SMG 45 px, Scout 27 px,
  Goblin 26 px. Under 10 px reads as continuous. The 167 px pop is on the most common enemy in
  the game, so it fires constantly.
- **The machinegunner shifts when he raises — in the set the game no longer draws.** The
  14–17 px measurement is `Scout_MachineGunner`'s `ReadyToFire_Stance`, outside the 12–16 band
  every other stance holds: that set sinks as it shoulders the gun, and it is still the one
  FAIL in the whole sprite tree. It is now generic-troop art rather than Brukk Meshan's, so it
  is a cut-scene and background-squad defect, not a defect the player sees on their own gunner.
  The gunner the game draws is `Hero_MachineGunner`, whose `ReadyToFire_Stance` sits one texel
  *higher* than its own standing stance — feet 13 px in seven facings and 16 px on south,
  against a standing 14 px flat — so it measures 13–16 and passes. The swap moved that stance
  into spec rather than fixing it in place; the 14–17 art is untouched and still on disk.

**Two more are known and not fixed.** `tools/fix_idle_flash.py`'s debris detector — the third
one, written for Brukk Meshan's ejecta during the swap above — flags two shipped units besides
him, and it is right about both: `Rodar_Akai`'s *north-west* aim-idle carries a 13 px puff of
white smoke on frame 8 that is in no other frame, and `Goblin_revolver`'s *east* cycle grows one
behind his head across frames 2–6 — the same loop that already fires the revolver in frames 4–5,
so one direction of one unit carries two independent defects. Both are older art, both say "the
gun is working" on a unit that is standing still, and neither was repaired because nobody asked.
They are written down here so the report stays an honest finding rather than a false negative
somebody tunes away later. Whenever it is worth doing, debris is deleted rather than grafted and
that is safe: a disconnected component cannot take a pixel of the soldier with it.

### Palette outliers, measured

Max distinct opaque colours in a single sprite, against the project's own 80-colour budget
(carried per set in `SPECS`, and advisory rather than gating on this tier):

`Scout` **387** · `Goblin_SMG_alt` **396** · Scout_TeamLead 76 · Scout_MachineGunner 75 ·
Goblin 72 · Goblin_SMG 61 · Goblin_revolver 53 · Civilian 36

Two sets are ~5× over budget and the rest are comfortably inside it. One of them is the unit
the player controls three of.

### The orphaned hero art is not orphaned any more

Both sets are wired. `Rodar_Akai` became `Kind.HERO` behind `RODAR_ROOT`, and `Hero_MachineGunner`
is now `MG_ROOT` — Brukk Meshan, `Kind.MACHINEGUNNER`, raw ordinal 2. **The folder name is not
the kind:** `Hero_MachineGunner/` is the machinegunner's art and `Rodar_Akai/` is the hero's;
the folder is named after the PixelLab `Hero_bandana` group it came out of, and nothing else.

The geometry claim held. Both are 60×60 with feet at exactly 15.0 by the table above — 14 in the
validator's convention, the same line — matching `SPRITE_OFFSET` without modification, so the
swap needed no anchor work: the standing
rotations are bbox-identical to the Scout set's, `SPRITE_SPECS.DEFAULT` still applies, and
`MACHINEGUNNER` has no `SPRITE_SPECS` entry of its own. What the swap did cost was the muzzle
table (`tools/measure_muzzle.gd`'s `GUNNER` entry repointed and re-run — 7 of 8 facings exact,
*south* hand-corrected because the scan lands on his boots) and two aim-idle repairs.

`LEAD_ROOT` was not repointed and should not be. Rodar is a kind of his own; `Scout_TeamLead`
still backs `Kind.TEAM_LEAD`, and along with `Scout` and `Scout_MachineGunner` it is kept
deliberately as generic Kestrel troop art. The sets these two "would replace" are not being
replaced — they are being kept for cut scenes, garrisons and allied squads. Nothing here is a
delete list.

### The ones who came back

A goblin who breaks with nobody covering him routs for the rim, and reaching it
has always been an escape rather than a kill. That was written to THE ROLL and
read by nobody. It now feeds a reinforcement: escapees can walk back onto a
later mission, mid-battle, off the rim they fled by, under the name they had
when they ran.

Three things had to change before it could work at all, and each was a defect
on its own terms.

**Most of them were being deleted.** Five of the seven missions end on a
destroy, extract or rescue objective, which can complete while a broken goblin
is still walking. `_show_game_over` committed the roll as it stood, so that man
left no line at all — not killed, not escaped, nothing. `_sweep_the_still_running`
closes the roll over the survivors.

**Two classes could not break.** A conscript has 2 HP, so the only round he
survives is one already halved by cover, and that single round is the entire 40
morale he will ever be charged against a 70-point requirement. The two kinds the
fiction calls least willing to be there were the two that could not run.
`Rules.starting_morale()` gives them their own numbers — well-hand 100, runner
85, light runner 75, conscript 60 — and `morale_recovered()` now caps at the
unit's own ceiling rather than at MORALE_MAX, without which +5 a quiet turn
walks everyone back to 100 and the table means nothing after turn four.

**The notebook was a document, not a record.** `add_to_notebook` kept
`{level, name, age, settlement, fate}` and dropped the `kind` Battle had
recorded, so nothing on disk said what an escapee was carrying. It now keeps
kind, spawn ordinal and the rim he left by — and because it drives a spawner, it
is sanitised on load like every other adopted structure, against the Thirst's
kinds specifically rather than merely against the enum's range.

Two things that were tried and were wrong, kept here because both sounded right:

- **Holding the mission open** for a scheduled arrival. A win is otherwise
  always decided during the player's own turn; deferring one moves the commit
  into the middle of an AI activation, and `run_enemy_turn` does not stop when
  the mission is scored. A banked WIN could be flipped to "RODAR AKAI HAS
  FALLEN" by a round that landed after `commit_mission()` had cleared the
  rollback. On a destroy map it also left the squad standing in the open for
  four turns after the job was done, with every casualty permanent. The contact
  ends when it ends; somebody who does not get here stays in the notebook.
- **Choosing the arrival cell by distance.** Furthest from the squad is the
  corner nearest the Thirst's own spawns. Furthest from the other goblins is
  correct on turn one and wrong by turn three, because the Thirst advances west
  and the far cell becomes the corner they started in. What makes an arrival
  alarming is proximity: the rim nobody is watching is the one behind the squad.

### Left for dead

Escaping was one way off a board. Being shot down is now the other: a defeated
fighter is usually dead and sometimes only left for dead, and the ones who get
up become the campaign's recurring adversaries.

**The unit still drops.** He plays the death animation, leaves a corpse, spreads
morale, scores XP and prices conduct exactly as before — the district saw a man
shot down and does not care that he crawled off later. Only the campaign record
differs, which is why the whole feature is one line at the death hook rather
than a second lifecycle.

**Two gates, and the first belongs to the player.** `Rules.decisive_blow` reads
the blow against the target's MAX health, not against what was left: almost
every weapon does 2 and enemy HP runs 2-4, so overkill past the remaining points
is nearly always zero and a rule built on it would never fire. Read this way it
says something actionable — spend Rodar, Sillae or a grenade and he is gone;
finish a wounded man with a carbine and he may not be. The second gate is
`survive_chance`, 18% rising 12 a time to a 60% cap, keyed on the campaign seed,
the mission and which body he was so a reload cannot turn a death into a
survival.

**The record had to stop being a list of appearances.** `(level, ordinal)` is
unique per body, which was enough to send somebody back once and useless for
accumulating anything. `Game.adversaries` is keyed by PERSON: one row, a
survival tally, a wound count and a history, minted the first time somebody
walks away and updated every time after. The notebook stays what it was — the
append-only document, one line per person per mission. The document records what
happened; the roster records who is still out there.

**The wear is the balance.** Each injury costs a point of max health, floored at
1, so a four-time survivor is hard to finish and trivial to knock down — his own
test found this the hard way, because at 1 max HP every blow in the game is
decisive and `_fate_of` correctly stops rolling for him at all.

### Units disappeared behind the scenery

Reported from play: soldiers walking behind buildings and props became
invisible. Measured before anything was changed - a rock's art reaches 74px
above its own cell, junk 82px and a sandbag line 90px, against a 60px tile
step. So a prop covers about two and a half cells of screen behind itself, and
anybody standing in that band is buried.

Y-sorting was not the bug and fixing it would not have helped: the unit IS
behind the prop and the prop IS correctly drawn over him. Structures were
already handled - they are sliced into per-column strips, each parented to its
own column's front cell, which is why a building sorts per column rather than
as one slab. Loose props and walls had no equivalent.

So the scenery stands aside. Anything drawn after a unit whose rectangle covers
enough of him fades to 42% while he is there, and returns when he moves off.
That is the principle the prop dust shader already states in its own header -
"units should stay the crispest things on screen so they read against the
scenery" - applied to the one case a shader cannot reach.

Two refinements, both from looking at the result rather than from reasoning:

- **Head and shoulders, not the whole body.** A first pass faded on any overlap
  of the sprite rectangle and took 18 of THE SCRAPLINE's 40 props with it,
  leaving the yard a ghost of itself. Only the top 62% of a body has to stay
  recognisable; boots going behind a barrel is depth, not a defect. With a 22%
  area threshold on that band it takes 9.
- **42%, not nothing.** A prop that vanishes is a worse lie than one that
  hides somebody: it still has to read as cover, because it still IS cover.

Enemies count too. There is no fog of war here - a goblin behind a drum is
already drawn, just invisibly, and losing track of him is the same bug.
