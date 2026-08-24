extends SceneTree

## Dev screenshot driver for the garrison's rooms. Boots each interior on a
## fresh campaign and captures it dressed - the furniture batch, the jail
## bars, the exit prompts. The real save is backed up in _init - before the
## Game autoload can load it - and restored byte-identically on the way out.
##
## No `Unit` type hints anywhere in this file, deliberately - the harness
## type trap. The camp scene is duck-typed.
##
## Must run WINDOWED - headless renders nothing.
## Run: godot --path . -s tools/shoot_interiors.gd -- --out <dir>

const SAVE_PATH := "user://campaign.json"
const ROOMS := ["hq", "canteen", "armory", "lockup", "surgeon", "billet"]

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
	game.new_campaign()

	for name: String in ROOMS:
		game.camp_interior = name
		var camp: Node = (load("res://scenes/Camp.tscn") as PackedScene).instantiate()
		root.add_child(camp)
		await process_frame
		await process_frame
		# A beat for the breeze loops and prompt fade to settle.
		await create_timer(0.4).timeout
		await _snap(out + "/interior_%s.png" % name)
		camp.queue_free()
		await process_frame
	game.camp_interior = ""

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
