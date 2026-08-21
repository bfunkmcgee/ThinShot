extends SceneTree

## Overwatch interrupts, pinned - on the real board, through the real do_move.
##
##   1. a reaction that CONNECTS stops the mover on the cell it was hit on,
##      short of where it was going, and ends the activation - no shot after
##   2. a reaction that MISSES does nothing: the mover walks the whole path and
##      can still act, which is what keeps a covered lane a bet rather than a
##      wall
##   3. it is symmetrical - a goblin crossing a soldier's lane stops exactly
##      like a soldier crossing a goblin's, and the AI does not fire afterwards
##   4. start_turn clears it, so being stopped costs one activation and not the
##      rest of the battle
##   5. and the REAL enemy turn honours it - run_enemy_turn moves and then
##      shoots in the same activation, and that second half has to be gated
##      on the same flag do_move sets
##
## The dice are pinned by seeding Battle's rules stream so the first roll is a
## known value: `Rules.roll_hits` is `randi_range(1, 100) <= chance` and
## hit_chance is clamped to [20, 99], so a first roll of 1 always hits and a
## first roll of 100 always misses. Same trick tools/test_progression.gd uses.
##
## Run: godot --headless --path . -s tools/test_overwatch.gd

const SAVE_PATH := "user://campaign.json"
const BACKUP_PATH := "user://campaign.json.overwatch-test-backup"

const TEAM_SCOUT := 0
const TEAM_GOBLIN := 1

var _failed := false
var _had_save := false


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    %s" % label)
	else:
		printerr("  FAIL  %s" % label)
		_failed = true


func _init() -> void:
	_had_save = FileAccess.file_exists(SAVE_PATH)
	if _had_save:
		DirAccess.copy_absolute(SAVE_PATH, BACKUP_PATH)
	_run()


func _restore() -> void:
	if _had_save:
		DirAccess.copy_absolute(BACKUP_PATH, SAVE_PATH)
		DirAccess.remove_absolute(BACKUP_PATH)
		print("\nrestored the original save")
	elif FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


## A seed whose FIRST randi_range(1, 100) equals `want`.
func _seed_for_first_roll(want: int) -> int:
	var rng := RandomNumberGenerator.new()
	for candidate in range(1, 200000):
		rng.seed = candidate
		if rng.randi_range(1, 100) == want:
			return candidate
	return 1


func _battle(level: int) -> Node:
	var game: Node = root.get_node("/root/Game")
	game.current_level = level
	var battle: Node = (load("res://scenes/Battle.tscn") as PackedScene).instantiate()
	root.add_child(battle)
	await process_frame
	await process_frame
	return battle


func _dismiss(battle: Node) -> void:
	battle.queue_free()
	await process_frame
	await process_frame


func _place(battle: Node, unit: Node2D, cell: Vector2i) -> void:
	unit.cell = cell
	unit.position = battle.board.cell_to_global(cell)


## A straight walkable run of `length` cells with a free cell beside its middle
## to put the watcher on. Found rather than hardcoded, so this does not become a
## test about DRY WASH's furniture.
func _find_lane(battle: Node, length: int) -> Dictionary:
	var board: Board = battle.board
	for y in board.size.y:
		for x in range(board.size.x - length):
			var run: Array[Vector2i] = []
			var ok := true
			for i in length:
				var c := Vector2i(x + i, y)
				if not board.is_walkable(c):
					ok = false
					break
				run.append(c)
			if not ok:
				continue
			var mid: Vector2i = run[length / 2]
			for step in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(0, -2), Vector2i(0, 2)]:
				var watch: Vector2i = mid + step
				if board.is_walkable(watch) \
						and board.has_line_of_sight(watch, mid):
					return {"start": run[0], "dest": run[length - 1],
							"mid": mid, "watch": watch}
	return {}


## Everyone else out of the way, so the only units that matter are the two this
## test is about.
##
## Reached through battle.living_units() rather than by walking the entity tree
## and casting to Unit: naming `Unit` in a `-s` harness compiles Unit.gd before
## the autoloads exist, which fails, and leaves the broken script cached for
## everything that instantiates a unit afterwards. Board is safe to name - it
## reaches for no autoload - which is why _find_lane can.
func _clear_board_except(battle: Node, keep: Array) -> void:
	for unit in battle.living_units(TEAM_SCOUT) + battle.living_units(TEAM_GOBLIN):
		if keep.has(unit):
			continue
		unit.hp = 0
		unit.hide()


func _run() -> void:
	await process_frame
	await _test_hit_interrupts()
	await _test_miss_does_not()
	await _test_symmetry_and_reset()
	await _test_through_the_turn_loop()
	await _test_ai_routes_around()
	_restore()
	print("\nRESULT: ", "FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


# --- 1. a round that lands stops the advance --------------------------------

func _test_hit_interrupts() -> void:
	print("\n[1] a reaction that connects stops the mover where it hit him")
	var battle: Node = await _battle(0)
	var lane := _find_lane(battle, 5)
	_check(not lane.is_empty(), "found a straight lane to walk")

	var scout: Node2D = battle.living_soldiers(TEAM_SCOUT)[0]
	var watcher: Node2D = battle.living_units(TEAM_GOBLIN)[0]
	_clear_board_except(battle, [scout, watcher])
	_place(battle, scout, lane.start)
	_place(battle, watcher, lane.watch)
	watcher.set_facing_sector(Board.sector_from_to(lane.watch, lane.mid))
	watcher.set_overwatch(true)
	# Nothing about this test should depend on the soldier surviving.
	scout.max_hp = 40
	scout.hp = 40

	# The preconditions a reaction needs, checked here rather than assumed: the
	# lane is only watched if the watcher is on overwatch, has something to
	# fire, and can see the cell the soldier is about to walk onto.
	_check(watcher.overwatching and watcher.has_ammo(),
			"the watcher is up, loaded, and facing the lane")
	_check(battle.board.has_line_of_sight(lane.watch, lane.mid),
			"and can see the middle of it")

	battle._rules_rng.seed = _seed_for_first_roll(1)  # the first round hits
	battle.state = battle.State.PLAYER_TURN
	await battle.do_move(scout, lane.dest)

	_check(scout.interrupted, "the soldier is flagged interrupted")
	_check(scout.cell != lane.dest,
			"he did not reach %s - he stopped at %s" % [lane.dest, scout.cell])
	_check(scout.acted and scout.moved,
			"and his activation is over, so there is no shot after it")
	_check(not watcher.overwatching, "the watcher spent its reaction")
	await _dismiss(battle)


# --- 2. a round that misses changes nothing ---------------------------------

func _test_miss_does_not() -> void:
	print("\n[2] a reaction that misses lets him walk through")
	var battle: Node = await _battle(0)
	var lane := _find_lane(battle, 5)
	var scout: Node2D = battle.living_soldiers(TEAM_SCOUT)[0]
	var watcher: Node2D = battle.living_units(TEAM_GOBLIN)[0]
	_clear_board_except(battle, [scout, watcher])
	_place(battle, scout, lane.start)
	_place(battle, watcher, lane.watch)
	watcher.set_facing_sector(Board.sector_from_to(lane.watch, lane.mid))
	watcher.set_overwatch(true)
	scout.max_hp = 40
	scout.hp = 40

	battle._rules_rng.seed = _seed_for_first_roll(100)  # hit_chance caps at 99
	battle.state = battle.State.PLAYER_TURN
	await battle.do_move(scout, lane.dest)

	_check(not scout.interrupted, "he is not interrupted")
	_check(scout.cell == lane.dest,
			"he walked the whole path to %s" % scout.cell)
	_check(scout.hp == 40, "and took nothing (%d hp)" % scout.hp)
	_check(not scout.acted,
			"his shot is still there - a covered lane is a bet, not a wall")
	await _dismiss(battle)


# --- 3 & 4. both directions, and it lasts exactly one activation -------------

func _test_symmetry_and_reset() -> void:
	print("\n[3] a goblin crossing a soldier's lane stops the same way")
	var battle: Node = await _battle(0)
	var lane := _find_lane(battle, 5)
	var scout: Node2D = battle.living_soldiers(TEAM_SCOUT)[0]
	var goblin: Node2D = battle.living_units(TEAM_GOBLIN)[0]
	_clear_board_except(battle, [scout, goblin])
	_place(battle, goblin, lane.start)
	_place(battle, scout, lane.watch)
	scout.set_facing_sector(Board.sector_from_to(lane.watch, lane.mid))
	scout.set_overwatch(true)
	goblin.max_hp = 40
	goblin.hp = 40

	battle._rules_rng.seed = _seed_for_first_roll(1)
	battle.state = battle.State.ENEMY_TURN
	await battle.do_move(goblin, lane.dest)

	_check(goblin.interrupted, "the goblin is flagged interrupted")
	_check(goblin.cell != lane.dest, "he stopped at %s" % goblin.cell)
	_check(goblin.acted,
			"and run_enemy_turn's shoot branch is gated on the same flag")

	print("\n[4] and it costs one activation, not the battle")
	goblin.start_turn()
	_check(not goblin.interrupted,
			"start_turn clears it alongside moved and acted")
	_check(not goblin.acted and not goblin.moved, "...which it also clears")
	await _dismiss(battle)


# --- 5. through run_enemy_turn, not around it -------------------------------

func _test_through_the_turn_loop() -> void:
	print("\n[5] a stopped goblin does not get to shoot at the end of its move")
	# Section 3 drives do_move directly, which is the shape that misses the
	# caller. run_enemy_turn moves and THEN fires in the same activation, and
	# the firing half is a separate branch that has to be gated on its own.
	var battle: Node = await _battle(0)
	var lane := _find_lane(battle, 6)
	var scout: Node2D = battle.living_soldiers(TEAM_SCOUT)[0]
	var goblin: Node2D = battle.living_units(TEAM_GOBLIN)[0]
	_clear_board_except(battle, [scout, goblin])

	# The goblin starts at one end of the lane and the soldier holds the other,
	# so the only way to close is straight down the watched ground.
	_place(battle, goblin, lane.start)
	_place(battle, scout, lane.dest)
	scout.set_facing_sector(Board.sector_from_to(lane.dest, lane.start))
	scout.set_overwatch(true)
	scout.max_hp = 40
	scout.hp = 40
	# Enough reach that he genuinely tries to close the whole lane.
	goblin.move_range = 8

	battle._rules_rng.seed = _seed_for_first_roll(1)  # the reaction connects
	battle.state = battle.State.ENEMY_TURN
	await battle.run_enemy_turn()
	await process_frame

	_check(goblin.interrupted,
			"the goblin was stopped crossing the lane (at %s)" % goblin.cell)
	_check(scout.hp == 40,
			"and never fired - the soldier is untouched at %d hp" % scout.hp)
	_check(not scout.overwatching, "the soldier's reaction was spent")
	await _dismiss(battle)


# --- 5. the route planner respects a held arc --------------------------------

## _best_ai_dest charges a candidate destination for every watcher whose cone
## its actual walk would cross - the same reconstruct_path do_move will walk,
## so the planner and the reaction can never disagree. Two properties matter:
## the goblin routes around the cone when a clean advance exists, and it never
## stalls just because ground is being watched.
func _test_ai_routes_around() -> void:
	print("\n[5] the AI walks around a watched lane when a clean way exists")
	var battle: Node = await _battle(0)
	var lane := _find_lane(battle, 9)
	_check(not lane.is_empty(), "found a nine-cell lane with a watch post")
	if lane.is_empty():
		await _dismiss(battle)
		return

	var soldiers: Array = battle.living_soldiers(TEAM_SCOUT)
	var watcher: Node2D = soldiers[0]
	var bait: Node2D = soldiers[1]
	var goblin: Node2D = battle.living_units(TEAM_GOBLIN)[0]
	_clear_board_except(battle, [watcher, bait, goblin])
	_place(battle, goblin, lane.start)
	_place(battle, watcher, lane.watch)
	_place(battle, bait, lane.dest)
	watcher.set_facing_sector(Board.sector_from_to(lane.watch, lane.mid))
	watcher.attack_range = 2  # a short cone, so the map still offers a way around
	watcher.set_overwatch(true)
	goblin.hp = 4             # healthy - exposure stays a tie-breaker
	goblin.move_range = 4
	goblin.attack_range = 3   # the bait sits 8 out: no shot from anywhere reachable

	# The scorer is handed only the bait as a target, so a shot on the watcher
	# cannot outbid the property under test - the cone still comes from the
	# watcher, because _best_ai_dest reads the board for arcs itself.
	var scouts: Array = battle.living_soldiers(TEAM_SCOUT).slice(1, 2)
	var watched: Dictionary = battle._overwatch_cells_for(watcher, watcher.facing_sector)
	var reach: Dictionary = battle.board.flood_fill(goblin.cell, goblin.move_range,
			battle._blocked_for_team.bind(goblin.team))

	# The map has to actually offer a choice, or the clean-walk check below is
	# vacuous. Counted with the very same path logic the scorer uses.
	var clean_advances := 0
	for cell: Vector2i in battle._free_dests(reach):
		if Board.manhattan(cell, bait.cell) >= Board.manhattan(goblin.cell, bait.cell):
			continue
		var clean := true
		for step: Vector2i in battle.board.reconstruct_path(reach, cell):
			if watched.has(step):
				clean = false
				break
		if clean:
			clean_advances += 1
	_check(clean_advances > 0,
			"a clean advancing route exists (%d found)" % clean_advances)

	var dest: Vector2i = battle._best_ai_dest(goblin, reach, scouts, bait.cell)
	_check(dest != goblin.cell,
			"the goblin still advances (%s -> %s)" % [goblin.cell, dest])
	_check(Board.manhattan(dest, bait.cell) < Board.manhattan(goblin.cell, bait.cell),
			"and closes on the chase target")
	var crossed := false
	for step: Vector2i in battle.board.reconstruct_path(reach, dest):
		if watched.has(step):
			crossed = true
			break
	_check(not crossed, "without walking through the watched cone")

	# Watch down, same ground: the direct route is back on the table.
	watcher.set_overwatch(false)
	var direct: Vector2i = battle._best_ai_dest(goblin, reach, scouts, bait.cell)
	_check(Board.manhattan(direct, bait.cell) <= Board.manhattan(dest, bait.cell),
			"with the watch down the route is at least as direct")
	await _dismiss(battle)
