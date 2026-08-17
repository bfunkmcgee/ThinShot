extends SceneTree

## Stands units on screen through the real Unit.setup() path and photographs
## them, so a newly wired unit is checked by eye and not only by measurement.
##
## Each unit gets two rows - the walking rotation and the aim stance - across
## all eight facings, with a dot on muzzle_point() in the aim row. That is the
## whole point: the offsets in Unit.gd are measured off PNGs by
## tools/measure_muzzle.gd, and this is where you find out whether the number
## lands on the barrel once Godot has applied SPRITE_SPECS scale and offset on
## top. A muzzle dot floating beside the gun means the two disagree.
##
## Headless CANNOT render - Godot's dummy rasterizer draws nothing - so this
## refuses under --headless rather than writing a black frame, exactly like
## tools/render_board_preview.gd.
##
## Unit is loaded at runtime and its enums read out of the constant map rather
## than written as `Unit.Kind`. Naming it in the script body would make a -s
## run compile Unit.gd before the autoloads exist, and Unit.gd names Game -
## the same preload trap tools/check_level.gd works around.
##
## Run:
##   powershell tools/godot.ps1 --path . -s tools/render_unit_check.gd -- --kestrels
##   ... -- --kinds GRENADIER,MEDIC --out artgen/staging/check --zoom 3

const OUT_DEFAULT := "artgen/staging/unit_check"
const CELL := Vector2(96, 104)     # room for a 60px figure at 2x plus labels
const MARGIN := Vector2(40, 56)   # top margin clears the direction header row

const KESTRELS := ["GRENADIER", "MARKSMAN", "BREACHER", "MEDIC", "TECHNICIAN"]
const DIR_LABELS := ["E", "SE", "S", "SW", "W", "NW", "N", "NE"]


func _init() -> void:
	_run.call_deferred()


func _resolve(names: Array, kind_enum: Dictionary) -> Array:
	## Kind names -> [[name, ordinal], ...], failing loudly on a typo rather
	## than silently rendering the wrong unit.
	var out: Array = []
	for n in names:
		var key := String(n).strip_edges().to_upper()
		if not kind_enum.has(key):
			printerr("no such Unit.Kind: %s" % key)
			printerr("known: %s" % ", ".join(kind_enum.keys()))
			quit(1)
			return []
		out.append([key, int(kind_enum[key])])
	return out


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("render_unit_check: headless cannot rasterize - drop --headless.")
		quit(1)
		return

	var args := OS.get_cmdline_user_args()
	var names: Array = []
	var out_dir := OUT_DEFAULT
	var zoom := 2.0
	var i := 0
	while i < args.size():
		match args[i]:
			"--kestrels":
				names = KESTRELS.duplicate()
			"--kinds":
				i += 1
				names = String(args[i] if i < args.size() else "").split(",", false)
			"--out":
				i += 1
				out_dir = String(args[i] if i < args.size() else OUT_DEFAULT)
			"--zoom":
				i += 1
				zoom = maxf(1.0, float(args[i] if i < args.size() else 2.0))
			_:
				printerr("unknown argument: %s" % args[i])
				quit(1)
				return
		i += 1
	if names.is_empty():
		names = KESTRELS.duplicate()
	var unit_script: GDScript = load("res://scripts/Unit.gd")
	var consts := unit_script.get_script_constant_map()
	var kind_enum: Dictionary = consts["Kind"]
	var anim_enum: Dictionary = consts["Anim"]
	var kinds := _resolve(names, kind_enum)
	if kinds.is_empty():
		return

	await process_frame

	# Into a SubViewport, not the window: the sheet is taller than a screen and
	# a window silently clamps to the display, which crops the last units off
	# the bottom of the PNG without any error to notice.
	var size := Vector2(MARGIN.x * 2 + CELL.x * 8,
			MARGIN.y * 2 + CELL.y * 2 * kinds.size())
	var vp := SubViewport.new()
	vp.size = Vector2i(size * zoom)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)

	var stage := Node2D.new()
	stage.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	stage.scale = Vector2(zoom, zoom)
	vp.add_child(stage)

	var bg := ColorRect.new()
	bg.color = Color(0.10, 0.09, 0.08)
	bg.size = size
	stage.add_child(bg)

	var unit_scene: PackedScene = load("res://scenes/Unit.tscn")
	var made := 0
	for row in kinds.size():
		var kind_name: String = kinds[row][0]
		var kind: int = kinds[row][1]
		for aim in 2:
			for sector in 8:
				var u := unit_scene.instantiate()
				stage.add_child(u)          # _ready first, so $Sprite exists
				u.setup(kind, Vector2i.ZERO)
				u.show_combat_hud = false   # pips and wedges hide the art
				u.position = MARGIN + Vector2(
						CELL.x * sector + CELL.x / 2.0,
						CELL.y * (row * 2 + aim) + CELL.y * 0.72)
				u.facing_sector = sector
				if aim == 1:
					u.anim = anim_enum["AIM_IDLE"]
				u._update_sprite()
				u.queue_redraw()
				if aim == 1:
					var dot := _Dot.new()
					# muzzle_point() is global; the dot is a child of the unit,
					# so it needs the same point expressed in the unit's own
					# space. Subtracting u.position would mix the two and put
					# the dot somewhere off the sheet entirely.
					dot.position = u.to_local(u.muzzle_point())
					u.add_child(dot)
				made += 1
		stage.add_child(_label("%s  (rotation / aim + muzzle_point)" % kind_name,
				Vector2(MARGIN.x, MARGIN.y + CELL.y * row * 2 - 18)))
	for sector in 8:
		stage.add_child(_label(DIR_LABELS[sector],
				Vector2(MARGIN.x + CELL.x * sector + CELL.x / 2.0 - 6, 12)))

	print("%d unit instance(s) across %d kind(s)" % [made, kinds.size()])

	var dir := ProjectSettings.globalize_path("res://").path_join(out_dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join("unit_check.png")

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var err := vp.get_texture().get_image().save_png(path)
	if err != OK:
		printerr("FAIL - could not save %s (%s)" % [path, error_string(err)])
		quit(1)
		return
	print("wrote %s" % path)
	print("RESULT: PASS")
	quit()


func _label(text: String, at: Vector2) -> Label:
	var l := Label.new()
	l.text = text
	l.position = at
	l.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75))
	l.add_theme_font_size_override("font_size", 13)
	return l


## Drawn as a child of the unit so it rides the same transform the sprite does.
## Carries its own radius: an inner class cannot read the outer script's consts.
class _Dot:
	extends Node2D

	const R := 3.0

	func _draw() -> void:
		draw_circle(Vector2.ZERO, R, Color(1.0, 0.35, 0.15))
		draw_circle(Vector2.ZERO, R * 0.45, Color(1, 1, 0.85))
