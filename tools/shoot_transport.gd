extends SceneTree

## Dev screenshot driver for the operation-intro cutscene and the mission-1
## disembark. Boots a fresh campaign, captures the intro mid-drive, then the
## battle through the ramp drop and walk-out. The real save is backed up in
## _init - before the Game autoload can load it - and restored byte-identically
## on the way out.
##
## No `Unit` type hints anywhere in this file, deliberately - the harness
## type trap. Everything is duck-typed.
##
## Must run WINDOWED - headless renders nothing.
## Run: godot --path . -s tools/shoot_transport.gd -- --out <dir>

const SAVE_PATH := "user://campaign.json"

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


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _run() -> void:
	await process_frame
	var game: Node = root.get_node("/root/Game")
	var out := _out_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	game.new_campaign()

	# 1. The cutscene, mid-drive and late-drive. Freed before its own finish
	# so it never swaps the scene out from under the harness.
	var intro: Node = (load("res://scenes/OperationIntro.tscn") as PackedScene).instantiate()
	root.add_child(intro)
	await process_frame
	await _wait(1.6)
	await _snap(out + "/intro_mid_drive.png")
	await _wait(2.0)
	await _snap(out + "/intro_late_drive.png")
	intro.queue_free()
	await process_frame
	await process_frame

	# 2. The battle: sealed transport under the briefing, the ramp dropping,
	# the squad pouring out, and the field once the turn begins.
	var battle: Node = (load("res://scenes/Battle.tscn") as PackedScene).instantiate()
	root.add_child(battle)
	await process_frame
	await process_frame
	await _wait(0.4)
	await _snap(out + "/disembark_briefing.png")
	battle._dismiss_briefing()
	await _wait(0.75)
	await _snap(out + "/disembark_ramp.png")
	await _wait(1.1)
	await _snap(out + "/disembark_walkout.png")
	await _wait(3.0)
	await _snap(out + "/disembark_deployed.png")
	battle.queue_free()
	await process_frame

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
