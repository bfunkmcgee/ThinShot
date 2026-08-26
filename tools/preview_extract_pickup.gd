extends SceneTree

## Windowed preview of the extraction pickup and the ride home. Loads a
## level, completes its objectives by decree (no shots fired - this is about
## the sequences, not the fight), and captures frames of the arrival, the
## boarding and the departure.
##
## Two shapes, matching Battle's own:
##   extract finales (OUTPOST 7, THE COLD WELL): the caches/rescues are
##     flagged done, the transport arrives on the armed zone, the squad is
##     teleported aboard the zone and the winning check runs the departure.
##   eliminate finales (THE SURVEY CAMP): the enemy is removed outright and
##     the winning check itself dispatches the ride, waits for it, and boards
##     from wherever the squad stands.
##
## Run (windowed - headless renders nothing):
##   godot --path . -s tools/preview_extract_pickup.gd -- [--level N] [--out DIR]

func _init() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("preview_extract_pickup: needs a window; headless renders nothing")
		quit(1)
		return
	_run()


func _run() -> void:
	await process_frame
	var out_dir := "pickup_preview"
	var level_n := 3
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			out_dir = args[i + 1]
		if args[i] == "--level" and i + 1 < args.size():
			level_n = int(args[i + 1])
	if not out_dir.is_absolute_path():
		out_dir = ProjectSettings.globalize_path("res://").path_join(out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)

	var game: Node = root.get_node("/root/Game")
	game.current_level = level_n - 1
	var battle: Node = (load("res://scenes/Battle.tscn") as PackedScene).instantiate()
	battle.skip_disembark = true
	root.add_child(battle)
	await process_frame
	await process_frame
	battle._dismiss_briefing()
	await process_frame

	var zone: Array = []
	for obj: Dictionary in battle.level.get("objectives", []):
		if str(obj.get("kind", "")) == "extract":
			zone = obj.cells
	for cache: Dictionary in battle.caches:
		cache.destroyed = true

	if zone.is_empty():
		# An eliminate finale: the reading ends by decree, and the winning
		# check does the whole rest - dispatch, wait, board, leave.
		for goblin: Node in battle.living_units(1):
			goblin.free()
		await process_frame
		battle.check_game_over()
		await create_timer(3.0).timeout
		await _capture(out_dir.path_join("finale_arriving.png"))
		await create_timer(4.2).timeout
		await _capture(out_dir.path_join("finale_boarding.png"))
		await create_timer(3.8).timeout
		await _capture(out_dir.path_join("finale_departing.png"))
		await create_timer(4.0).timeout
		await _capture(out_dir.path_join("finale_card.png"))
	else:
		battle._refresh_objectives()
		await create_timer(1.4).timeout
		await _capture(out_dir.path_join("pickup_mid_drive.png"))
		await create_timer(6.6).timeout
		await _capture(out_dir.path_join("pickup_parked.png"))
		var squad: Array = battle.living_units(0)
		for i in squad.size():
			var cell: Vector2i = zone[mini(i, zone.size() - 1)]
			squad[i].cell = cell
			squad[i].position = battle.board.cell_to_global(cell)
		battle.check_game_over()
		await create_timer(2.2).timeout
		await _capture(out_dir.path_join("departure_boarding.png"))
		await create_timer(3.4).timeout
		await _capture(out_dir.path_join("departure_buttoned.png"))
		await create_timer(2.6).timeout
		await _capture(out_dir.path_join("departure_driving.png"))
	print("preview_extract_pickup: -> %s" % out_dir)
	quit(0)


func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var err := image.save_png(path)
	if err != OK:
		printerr("FAIL - could not save %s (%s)" % [path, error_string(err)])
