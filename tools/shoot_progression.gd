extends SceneTree

## Dev screenshot driver for the class perk trees. Boots the battle on a
## crafted roster and captures: a plain scout selected (no ability buttons),
## Rodar selected with Called Shot armed and a target hovered (both ability
## buttons + the status preview line), and the camp promotion modal offering
## a class pair. The real save is backed up in _init - before the Game
## autoload can load it - and restored byte-identically on the way out.
##
## Must run WINDOWED - headless renders nothing.
## Run: godot --path . -s tools/shoot_progression.gd -- --out <dir>

const SAVE_PATH := "user://campaign.json"
const KIND_SCOUT := 0
const KIND_MACHINEGUNNER := 2
const KIND_HERO := 9
const TEAM_SCOUT := 0
const TEAM_GOBLIN := 1

var _had_save := false
var _backup := ""


func _init() -> void:
	_had_save = FileAccess.file_exists(SAVE_PATH)
	if _had_save:
		var bf := FileAccess.open(SAVE_PATH, FileAccess.READ)
		_backup = bf.get_as_text()
		bf.close()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
		print("backed up existing save (%d bytes)" % _backup.length())
	_run()


func _out_dir() -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			return args[i + 1]
	return "user://shots"


func _snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var err := image.save_png(path)
	print("shot -> %s (%s)" % [path, "saved" if err == OK else error_string(err)])


func _run() -> void:
	await process_frame
	var game: Node = root.get_node("/root/Game")
	var out := _out_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))

	game.roster = [
		{"id": 1, "surname": "Akai", "kind": KIND_HERO, "xp": 26, "rank": 3,
				"perks": ["called_shot", "rally"] as Array, "alive": true},
		{"id": 2, "surname": "HARGREAVE", "kind": KIND_MACHINEGUNNER, "xp": 0,
				"rank": 0, "perks": [] as Array, "alive": true},
		{"id": 3, "surname": "VANCE", "kind": KIND_SCOUT, "xp": 0, "rank": 0,
				"perks": [] as Array, "alive": true},
		{"id": 4, "surname": "QUINN", "kind": KIND_SCOUT, "xp": 0, "rank": 0,
				"perks": [] as Array, "alive": true},
		{"id": 5, "surname": "ORTIZ", "kind": KIND_SCOUT, "xp": 0, "rank": 0,
				"perks": [] as Array, "alive": true},
	]
	game._next_id = 6
	game.pending_promotions = []
	game.current_level = 0
	game.current_operation = 0

	var battle: Node = (load("res://scenes/Battle.tscn") as PackedScene).instantiate()
	root.add_child(battle)
	await process_frame
	await process_frame
	battle._dismiss_briefing()

	var hero: Node2D = null
	var plain: Node2D = null
	for unit in battle.living_soldiers(TEAM_SCOUT):
		if str(unit.surname) == "Akai":
			hero = unit
		elif str(unit.surname) == "ORTIZ":
			plain = unit

	# 1. A plain scout selected: no ability buttons in the row.
	battle.select(plain)
	await _snap(out + "/battle_scout_selected.png")

	# 2. Rodar beside a goblin, Called Shot armed, target hovered: both
	# ability buttons visible and the status line quoting the shot.
	var goblin: Node2D = battle.living_units(TEAM_GOBLIN)[0]
	var board: Node2D = battle.board
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var dist: int = absi(dx) + absi(dy)
			if dist < 2 or dist > 3:
				continue
			var cell: Vector2i = goblin.cell + Vector2i(dx, dy)
			if board.in_bounds(cell) and board.is_walkable(cell) \
					and battle.unit_at(cell) == null \
					and board.can_engage(cell, goblin.cell):
				hero.cell = cell
				hero.position = board.cell_to_global(cell)
				break
		if hero.cell != Vector2i(0, 5):
			break
	battle.select(hero)
	battle._try_called_shot()
	battle._update_hover(goblin.cell)
	await _snap(out + "/battle_rodar_called_shot.png")

	battle.queue_free()
	await process_frame

	# 3. The camp promotion modal offering Rodar's rank-3 class pair.
	game.pending_promotions = [{"id": 1, "rank": 3}]
	var camp: Node = (load("res://scenes/Camp.tscn") as PackedScene).instantiate()
	root.add_child(camp)
	await process_frame
	await process_frame
	camp._open_soldier(1)
	await _snap(out + "/camp_promotion_modal.png")

	# Restore the save byte-identically and prove it.
	if _had_save:
		var rf := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		rf.store_string(_backup)
		rf.close()
		var check := FileAccess.open(SAVE_PATH, FileAccess.READ)
		var readback := check.get_as_text()
		check.close()
		print("save restored byte-identical: %s" % ("YES" if readback == _backup else "NO"))
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
		print("removed the crafted save")
	quit(0)
