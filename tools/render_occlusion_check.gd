extends SceneTree

## Photographs a soldier standing behind scenery, with the occlusion fade off
## and on, so the fix can be judged by eye rather than by assertion.
##
## The bug it exists for: the board is 3/4 top-down and the props are tall. A
## rock reaches 74px above its own cell, a sandbag line 90px, against a 60px
## tile step - so a prop covers about two and a half cells of screen behind it,
## and a soldier who walks into that band is simply gone. Y-sorting is right and
## does not help: the unit IS behind the prop and the prop IS drawn over him.
##
## Headless CANNOT render - Godot's dummy rasterizer draws nothing - so this
## refuses under --headless rather than writing a black frame, exactly like
## tools/render_board_preview.gd and tools/render_unit_check.gd.
##
## Run:
##   powershell tools/godot.ps1 --path . -s tools/render_occlusion_check.gd -- --level 2

const OUT_DIR := "artgen/staging/occlusion_check"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("render_occlusion_check: headless cannot rasterize - drop --headless.")
		quit(1)
		return

	var level_index := 1
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--level" and i + 1 < args.size():
			level_index = maxi(int(args[i + 1]) - 1, 0)

	var game: Node = root.get_node("/root/Game")
	if game.roster.is_empty():
		game.new_campaign()
	game.current_level = level_index
	game.in_the_field = true

	var battle: Node = (load("res://scenes/Battle.tscn") as PackedScene).instantiate()
	# --level 1, 4 or 8 lands on a mission-1 board with a parked transport;
	# without this the squad stays hidden below (disembark_pending never gets
	# consumed, since nothing here calls _dismiss_briefing()) and there is
	# nobody left to stand in the occlusion band this tool exists to photograph.
	battle.skip_disembark = true
	root.add_child(battle)
	await process_frame
	await process_frame
	# The mission opens on its briefing, which covers the board this exists to
	# photograph.
	battle.briefing_panel.visible = false
	await process_frame

	# Find scenery with room behind it, and stand somebody in that room. "Behind"
	# is up-screen: one cell of (x-1, y-1) is half a tile height nearer the top,
	# which is exactly the band a tall prop covers.
	var victim: Node2D = null
	for u in battle.living_soldiers(0):
		victim = u
		break
	if victim == null:
		printerr("no soldier to hide")
		quit(1)
		return

	var best := Board.NO_CELL
	var best_cover := 0.0
	for entry: Dictionary in battle._occluders:
		var spr: Sprite2D = entry.sprite
		if spr.texture == null:
			continue
		var here: Vector2i = battle.board.global_to_cell(spr.global_position)
		for step in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0)]:
			var behind: Vector2i = here + step
			if not battle.board.in_bounds(behind) \
					or not battle.board.is_walkable(behind) \
					or battle.unit_at(behind) != null:
				continue
			# How much of a body standing there this prop would cover.
			var body := Rect2(battle.board.cell_to_global(behind)
					+ Vector2(-30, -105), Vector2(60, 120))
			var over := body.intersection(battle._sprite_rect(spr))
			var area := over.size.x * over.size.y
			if area > best_cover:
				best_cover = area
				best = behind
	if best == Board.NO_CELL:
		printerr("found no scenery with standing room behind it")
		quit(1)
		return
	print("hiding %s at %s, %d px^2 of him covered"
			% [victim.display_name(), best, int(best_cover)])

	victim.cell = best
	victim.position = battle.board.cell_to_global(best)
	battle.deselect()
	await process_frame

	var dir := ProjectSettings.globalize_path("res://").path_join(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(dir)

	# Before: every prop at full opacity, which is what shipped.
	for entry: Dictionary in battle._occluders:
		(entry.sprite as Sprite2D).modulate.a = 1.0
	battle._occlusion_settling = false
	await _shoot(dir.path_join("before.png"))

	# After: let the pass settle.
	for i in 40:
		battle._refresh_occlusion(1.0)
		await process_frame
	var faded := 0
	for entry: Dictionary in battle._occluders:
		if (entry.sprite as Sprite2D).modulate.a < 0.99:
			faded += 1
	print("%d of %d props stood aside" % [faded, battle._occluders.size()])
	await _shoot(dir.path_join("after.png"))

	print("RESULT: PASS")
	quit()


func _shoot(path: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var err := root.get_texture().get_image().save_png(path)
	if err != OK:
		printerr("FAIL - could not save %s (%s)" % [path, error_string(err)])
		return
	print("wrote %s" % path)
