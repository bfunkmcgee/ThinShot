extends SceneTree

## The destination shot preview - "FROM HERE: n% ON <role>" - must be the
## number the soldier actually gets after walking there. _projected_shot
## answers by standing the unit on the candidate cell for one question and
## putting it back, so this harness pins the two properties that trick rests
## on:
##
##   1. projected == actual: for a sweep of reachable cells and targets, the
##      projection from a cell equals Rules.shot_preview computed with the
##      unit genuinely standing there, at the same post-move default mode
##   2. the question leaves no trace: unit.cell is untouched afterwards
##
## Run: godot --headless --path . -s tools/test_projection.gd

const SAVE_PATH := "user://campaign.json"
const BACKUP_PATH := "user://campaign.json.projection-test-backup"

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


func _run() -> void:
	await process_frame
	var game: Node = root.get_node("/root/Game")
	game.current_level = 0
	var battle: Node = (load("res://scenes/Battle.tscn") as PackedScene).instantiate()
	root.add_child(battle)
	await process_frame
	await process_frame

	var rules: GDScript = load("res://scripts/Rules.gd") as GDScript
	var scout: Node2D = battle.living_soldiers(TEAM_SCOUT)[0]
	var goblins: Array = battle.living_units(TEAM_GOBLIN)
	var board: Board = battle.board

	print("\n[1] projected equals actual, over reachable ground")
	var home: Vector2i = scout.cell
	var reach: Dictionary = board.flood_fill(home, 12,
			func(_cell: Vector2i) -> bool: return false)
	var compared := 0
	var agree := true
	var restored := true
	for cell: Vector2i in reach:
		if battle.unit_at(cell) != null:
			continue
		for goblin: Node2D in goblins:
			if Board.manhattan(cell, goblin.cell) > scout.attack_range \
					or not board.can_engage(cell, goblin.cell):
				continue
			var promised: Dictionary = battle._projected_shot(scout, cell, goblin)
			if scout.cell != home:
				restored = false
			# Now genuinely stand there and ask the resolver's question.
			scout.cell = cell
			var mode: int = battle._default_fire_mode(scout)
			var actual: Dictionary = rules.shot_preview(board, scout, goblin,
					battle._mode_accuracy(scout, mode),
					battle._inspiration_bonus(scout))
			scout.cell = home
			if int(promised.chance) != int(actual.chance) \
					or int(promised.dmg) != int(actual.dmg):
				agree = false
				printerr("  drift at %s vs %s: %d%%/%d != %d%%/%d" % [
						cell, goblin.cell, promised.chance, promised.dmg,
						actual.chance, actual.dmg])
			compared += 1
	_check(compared >= 10, "swept a real spread of cells (%d comparisons)" % compared)
	_check(agree, "every projection equals the shot it promised")
	_check(restored, "and the question left the soldier where he stood")

	battle.queue_free()
	await process_frame
	_restore()
	print("\nRESULT: ", "FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)
