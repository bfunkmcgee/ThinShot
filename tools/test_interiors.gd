extends SceneTree

## The rooms behind the garrison's doors, stood up for real.
##
## The boot validator already proves the MAPS (ring, naming, reachability,
## sealed cells); this proves the SCENE: each room builds, carries its exit
## hooks, and spawns the walker inside; the yard carries a door hook for
## every building; and leaving a room resumes at its yard door.
##
## No `Unit` type hints anywhere in this file, deliberately: naming a
## class_name script in a -s harness compiles it before the autoloads exist
## and takes the whole file down - see the harness-type-trap note.
##
## Run: godot --headless --path . -s tools/test_interiors.gd

var _failed := false
var _backup := ""
var _had_save := false
const SAVE_PATH := "user://campaign.json"


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    %s" % label)
	else:
		printerr("  FAIL  %s" % label)
		_failed = true


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	if FileAccess.file_exists(SAVE_PATH):
		var bf := FileAccess.open(SAVE_PATH, FileAccess.READ)
		_backup = bf.get_as_text()
		bf.close()
		_had_save = true
	var game: Node = root.get_node_or_null("/root/Game")
	if game == null:
		_check(false, "the Game autoload is up (it is not - nothing can run)")
		_finish()
		return
	game.new_campaign()

	print("\n[1] the yard knows its doors")
	game.camp_interior = ""
	var yard: Node = await _camp()
	var doors := 0
	var stray_exits := 0
	for f: Dictionary in yard.fixtures:
		if str(f.kind) == "enter":
			doors += 1
		if str(f.kind) == "exit":
			stray_exits += 1
	_check(doors == 8, "eight door hooks stand in the yard (%d)" % doors)
	_check(stray_exits == 0, "...and no exit leads out of outdoors")
	await _drop(yard)

	print("\n[2] every room stands up")
	for name: String in ["hq", "canteen", "armory", "lockup", "surgeon", "billet"]:
		game.camp_interior = name
		var room: Node = await _camp()
		var exits := 0
		var enters := 0
		for f: Dictionary in room.fixtures:
			if str(f.kind) == "exit":
				exits += 1
			if str(f.kind) == "enter":
				enters += 1
		_check(exits == 2 and enters == 0,
				"%s: two ways out, no doors deeper in (%d/%d)" % [name, exits, enters])
		_check(room.player != null and str(room.interior) == name,
				"%s: the walker stands inside" % name)
		# Idlers are people: anything in Entities that answers set_facing and
		# is not the player. Duck-typed so this file never names Unit.
		var squad := 0
		for child in room.entities.get_children():
			if child != room.player and child.has_method("set_facing"):
				squad += 1
		_check(squad == 0, "%s: the idlers stayed in the yard (%d)" % [name, squad])
		await _drop(room)
	game.camp_interior = ""

	print("\n[3] leaving a room resumes at its yard door")
	game.camp_return = Vector2i(13, 8)  # the armory's door
	var back: Node = await _camp()
	_check(Vector2i(back.player.cell) == Vector2i(13, 8),
			"the walker is at the door he came out of (%s)" % back.player.cell)
	_check(Vector2i(game.camp_return).x < 0, "...and the return slot is spent")
	await _drop(back)

	_finish()


func _camp() -> Node:
	var c: Node = (load("res://scenes/Camp.tscn") as PackedScene).instantiate()
	root.add_child(c)
	await process_frame
	await process_frame
	return c


func _drop(c: Node) -> void:
	c.queue_free()
	await process_frame
	await process_frame


func _finish() -> void:
	if _had_save:
		var rf := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		rf.store_string(_backup)
		rf.close()
	elif FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	print("\nRESULT: ", "FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)
