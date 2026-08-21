extends SceneTree

## The take-back slot - a move is reversible only while it is still nobody's
## information.
##
##   1. a clean walk undoes: cell, facing and the spent move all come back,
##      and the soldier can walk again
##   2. a walk that drew a reaction does not - the board answered, it stands
##   3. a soldier who has acted since cannot rewind the walk that set it up
##   4. a walk that freed a prisoner is a rescue, not a route choice
##   5. the slot dies with the turn
##
## Run: godot --headless --path . -s tools/test_undo.gd

const SAVE_PATH := "user://campaign.json"
const BACKUP_PATH := "user://campaign.json.undo-test-backup"

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


## A straight walkable run with a free watch post beside its middle. Same
## search tools/test_overwatch.gd uses, so neither is a test of map furniture.
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


func _clear_board_except(battle: Node, keep: Array) -> void:
	for unit in battle.living_units(TEAM_SCOUT) + battle.living_units(TEAM_GOBLIN):
		if keep.has(unit):
			continue
		unit.hp = 0
		unit.hide()


func _run() -> void:
	await process_frame
	await _test_clean_walk_undoes()
	await _test_reaction_stands()
	await _test_acting_locks_it()
	await _test_rescue_stands()
	await _test_slot_dies_with_the_turn()
	_restore()
	print("\nRESULT: ", "FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


# --- 1. a clean walk comes back ----------------------------------------------

func _test_clean_walk_undoes() -> void:
	print("\n[1] a clean walk undoes, and the move is refunded")
	var battle: Node = await _battle(0)
	var lane := _find_lane(battle, 5)
	var scout: Node2D = battle.living_soldiers(TEAM_SCOUT)[0]
	var goblin: Node2D = battle.living_units(TEAM_GOBLIN)[0]
	_clear_board_except(battle, [scout, goblin])
	_place(battle, goblin, lane.watch)  # present but not watching: no reaction
	_place(battle, scout, lane.start)
	var facing_before: int = scout.facing_sector

	battle.state = battle.State.PLAYER_TURN
	await battle.do_move(scout, lane.dest)
	_check(scout.cell == lane.dest and scout.moved, "he walked and spent the move")

	battle._try_undo_move()
	_check(scout.cell == lane.start, "the walk came back (%s)" % scout.cell)
	_check(not scout.moved, "with the move refunded")
	_check(scout.facing_sector == facing_before, "and the old facing restored")
	_check(battle._undo.is_empty(), "the slot is spent")

	await battle.do_move(scout, lane.mid)
	_check(scout.cell == lane.mid, "and he can walk again")
	await _dismiss(battle)


# --- 2. a drawn reaction stands ----------------------------------------------

func _test_reaction_stands() -> void:
	print("\n[2] a walk that drew a reaction cannot be taken back")
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

	battle._rules_rng.seed = _seed_for_first_roll(1)  # the reaction hits
	battle.state = battle.State.PLAYER_TURN
	await battle.do_move(scout, lane.dest)
	_check(scout.interrupted, "the reaction connected")

	var where: Vector2i = scout.cell
	battle._try_undo_move()
	_check(scout.cell == where, "the walk stands where it was stopped")
	_check(scout.moved, "and the move stays spent")
	await _dismiss(battle)


# --- 3. acting locks the walk in ---------------------------------------------

func _test_acting_locks_it() -> void:
	print("\n[3] a soldier who has acted cannot rewind the walk under it")
	var battle: Node = await _battle(0)
	var lane := _find_lane(battle, 5)
	var scout: Node2D = battle.living_soldiers(TEAM_SCOUT)[0]
	var goblin: Node2D = battle.living_units(TEAM_GOBLIN)[0]
	_clear_board_except(battle, [scout, goblin])
	_place(battle, scout, lane.start)
	_place(battle, goblin, lane.dest)
	goblin.max_hp = 40  # the shot below must not end the mission
	goblin.hp = 40

	battle.state = battle.State.PLAYER_TURN
	await battle.do_move(scout, lane.mid)
	battle._rules_rng.seed = _seed_for_first_roll(100)  # a miss keeps it simple
	await battle.do_attack(scout, goblin)
	_check(scout.acted, "he moved and then fired")

	battle._try_undo_move()
	_check(scout.cell == lane.mid, "the firing position stands")
	await _dismiss(battle)


# --- 4. a rescue stands ------------------------------------------------------

func _test_rescue_stands() -> void:
	print("\n[4] a walk that freed a prisoner is a rescue, not a route choice")
	var battle: Node = await _battle(5)  # THE HOLDING PENS
	var prisoners: Array = []
	for unit in battle.living_units(TEAM_SCOUT):
		if unit.captive:
			prisoners.append(unit)
	_check(not prisoners.is_empty(), "the pens hold prisoners")
	if prisoners.is_empty():
		await _dismiss(battle)
		return
	var prisoner: Node2D = prisoners[0]
	var scout: Node2D = battle.living_soldiers(TEAM_SCOUT)[0]
	for goblin in battle.living_units(TEAM_GOBLIN):
		goblin.hp = 0
		goblin.hide()

	# Two cells out, walking to one cell out - the arrival is the rescue.
	var board: Board = battle.board
	var beside := Board.NO_CELL
	var from := Board.NO_CELL
	for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var near: Vector2i = prisoner.cell + dir
		var far: Vector2i = prisoner.cell + dir * 2
		if board.in_bounds(near) and board.is_walkable(near) \
				and board.in_bounds(far) and board.is_walkable(far) \
				and battle.unit_at(near) == null and battle.unit_at(far) == null:
			beside = near
			from = far
			break
	_check(beside != Board.NO_CELL, "found a clear approach to the wire")
	if beside == Board.NO_CELL:
		await _dismiss(battle)
		return
	_place(battle, scout, from)

	battle.state = battle.State.PLAYER_TURN
	await battle.do_move(scout, beside)
	_check(not prisoner.captive, "reaching them IS the rescue")

	battle._try_undo_move()
	_check(scout.cell == beside, "and it cannot be walked back")
	await _dismiss(battle)


# --- 5. the slot dies with the turn ------------------------------------------

func _test_slot_dies_with_the_turn() -> void:
	print("\n[5] the slot dies with the turn")
	var battle: Node = await _battle(0)
	var lane := _find_lane(battle, 5)
	var scout: Node2D = battle.living_soldiers(TEAM_SCOUT)[0]
	var goblin: Node2D = battle.living_units(TEAM_GOBLIN)[0]
	_clear_board_except(battle, [scout, goblin])
	_place(battle, goblin, lane.watch)
	_place(battle, scout, lane.start)

	battle.state = battle.State.PLAYER_TURN
	await battle.do_move(scout, lane.dest)
	# The next player turn arriving is what expires the slot; stepping the
	# counter directly tests the guard without running a whole enemy turn.
	battle.turn_number += 1
	battle._try_undo_move()
	_check(scout.cell == lane.dest, "last turn's walk stays walked")
	await _dismiss(battle)
