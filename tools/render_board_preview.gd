extends SceneTree

## Windowed board renderer for the art and level pipelines. Builds a real Board
## (tiles, haze, contact shadows via its FloorLayer), stands the level's props
## on it with the same textures, offsets and 2x scale Battle uses, marks spawns
## and objectives with colored diamonds, and saves PNGs.
##
## Headless CANNOT render - Godot's dummy rasterizer draws nothing - so this
## tool refuses under --headless rather than writing black frames. Windowed it
## costs a ~2 second window flash.
##
## Run:
##   powershell tools/godot.ps1 --path . -s tools/render_board_preview.gd -- --level 1
##   ... -- --draft artgen/staging/m1/draft.json --out preview --views full,quads --zoom 1.0
## --level is 1-based, matching the game's own --level flag. --out is project-
## relative unless absolute. Outputs: board_full.png, with "quads" also
## board_{nw,ne,sw,se}.png at 2x the fitted zoom, plus meta.json.
##
## Marker legend: green diamond = squad spawn (S scout, L lead, G gunner);
## red/orange = Thirst spawns (g rifle, s smg, a smg-alt, n novice, b bolt);
## cyan P = prisoner; amber ring = demolition target; green fill = extraction.

# --- prop art, kept in sync with Battle.gd's tables ---------------------------
const ENV := "res://assets/sprites/Environment/Desert"
const WALL_ROT := ENV + "/Walls/desert_brick_and_mud/rotations"
const WIRE_ROT := ENV + "/Walls/desert_barbed_wire/rotations"
const CACHE_ROOT := ENV + "/Props/Desert_insurgent_weapons_cache"
const PROP_ROOT := ENV + "/Props"

const ROCK_OFFSET := Vector2(0, -18)
const JUNK_OFFSET := Vector2(0, -20)
const PLANT_OFFSET := Vector2(0, -17)
const SANDBAG_OFFSET := Vector2(0, -22)
const THIRST_CACHE_OFFSET := Vector2(0, -15)
const DRUM_OFFSET := Vector2(0, -22)
const WALL_OFFSETS := {
	"x_run": Vector2(0, -15), "y_run": Vector2(0, -15),
	"junction": Vector2(0, -9), "cap": Vector2(0, -11),
}
const WIRE_OFFSETS := {
	"x_run": Vector2(0, -15), "y_run": Vector2(0, -13),
	"junction": Vector2(0, -15), "cap": Vector2(0, -10),
}
const ROT_FILES := {
	"x_run": "south-west.png", "y_run": "south-east.png",
	"junction": "north.png", "cap": "east.png",
}
const STRUCTURE_DIRS := {
	"hut_1": ENV + "/Structures/desert_hut/Desert_hut",
	"hut_2": ENV + "/Structures/desert_hut/Desert_hut_1",
	"tent": ENV + "/Structures/desert_hut/Desert_hut_2",
	"fortress": ENV + "/Structures/Desert_military_building",
	"hauler_wreck": ENV + "/Structures/desert_vehicle_wreck/Desert_hauler_wreck",
	"tanker_wreck": ENV + "/Structures/desert_vehicle_wreck/Desert_tanker_wreck",
	"troop_transport": ENV + "/Structures/troop_transport",
}
const STRUCTURE_OFFSETS := {
	"hut_1": Vector2(0, -22), "hut_2": Vector2(0, -33),
	"tent": Vector2(0, -33), "fortress": Vector2(0, -55),
	"hauler_wreck": Vector2(0, -19), "tanker_wreck": Vector2(0, -23),
	"troop_transport": Vector2(0, -16),
}
const CLAIM_ROOT := ENV + "/thirst_claim_markers"
const CLAIM_FILES := ["Thirst_tally_board.png", "Thirst_stake_bundle.png",
		"Thirst_cup_post.png", "Thirst_well_marker.png"]
const CLAIM_OFFSETS := [Vector2(0, -16), Vector2(0, -19),
		Vector2(0, -18), Vector2(0, -18)]
const DETRITUS_ROOT := ENV + "/desert_detritus"
const SIGNAL_ROOT := ENV + "/desert_signal_markers"
const SIGNAL_STAND_FILES := ["Signal_banner.png", "Signal_mast.png"]
const SIGNAL_STAND_OFFSETS := [Vector2(0, -17), Vector2(0, -19)]
const SIGNAL_STANDS := 3
const SIGNAL_STAND_SHADOW := 12.0
const DETRITUS_RATE := 0.17
const DETRITUS_GAP := 1
const DETRITUS_JITTER := 11.0
const TARGET_PROPS := {
	"crates": {
		"still": PROP_ROOT + "/Pile_of_desert_ammo_crates/Pile_of_desert_ammo_crates/rotations/unknown.png",
		"offset": Vector2(0, -18), "shadow": 20.0,
	},
	"mast": {
		"still": PROP_ROOT + "/Desert_Comms_mast/Desert_Comms_mast/rotations/unknown.png",
		"offset": Vector2(0, -69), "shadow": 16.0,
	},
}
# Battle's per-stream hash salts - same salts, same _prop_seed derivation, so
# the preview shows the exact variant the battle will.
const SALT_ROCK := 4
const SALT_JUNK := 5
const SALT_PLANT := 6
const SALT_SANDBAG := 7
const SALT_CACHE := 8
const SALT_CLAIM := 11
const SALT_DETRITUS := 12
const SALT_DETRITUS_PICK := 13
const SALT_DETRITUS_JITTER := 14
const SALT_SIGNAL := 15

const PROP_DUST := "res://assets/shaders/prop_dust.gdshader"

# --- markers ------------------------------------------------------------------
const SQUAD_COLOR := Color(0.35, 1.0, 0.5)
const PRISONER_COLOR := Color(0.4, 0.9, 1.0)
const DESTROY_COLOR := Color(1.0, 0.7, 0.2)
const EXTRACT_COLOR := Color(0.4, 1.0, 0.55)
const ENEMY_MARKS := {
	"goblin_spawns": {"color": Color(1.0, 0.3, 0.25), "letter": "g"},
	"smg_spawns": {"color": Color(1.0, 0.45, 0.2), "letter": "s"},
	"smg_alt_spawns": {"color": Color(1.0, 0.6, 0.2), "letter": "a"},
	"novice_spawns": {"color": Color(1.0, 0.75, 0.3), "letter": "n"},
	"bolt_spawns": {"color": Color(1.0, 0.25, 0.5), "letter": "b"},
	"heavy_spawns": {"color": Color(0.85, 0.2, 0.2), "letter": "h"},
	"brute_spawns": {"color": Color(0.7, 0.1, 0.35), "letter": "B"},
	"partisan_spawns": {"color": Color(0.95, 0.8, 0.45), "letter": "e"},
}
const SQUAD_MARKS := {
	"scout_spawns": "S", "lead_spawns": "L", "gunner_spawns": "G",
}

const SPAWN_KEYS := ["scout_spawns", "lead_spawns", "gunner_spawns",
		"goblin_spawns", "smg_spawns", "smg_alt_spawns", "novice_spawns",
		"bolt_spawns", "heavy_spawns", "brute_spawns", "partisan_spawns",
		"prisoner_spawns"]

var _prop_seed := 0
var _dust_materials: Dictionary = {}
var _dust_shader: Shader = null


func _init() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("render_board_preview: headless runs on a dummy rasterizer and "
				+ "renders nothing. Drop --headless and run windowed (~2s flash).")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	var level_n := 0
	var draft_path := ""
	var out_dir := "board_preview"
	var views: Array = ["full"]
	var zoom_mult := 1.0
	var i := 0
	while i < args.size():
		match args[i]:
			"--level":
				if i + 1 >= args.size():
					_die("--level needs a 1-based level number")
					return
				level_n = int(args[i + 1])
				i += 2
			"--draft":
				if i + 1 >= args.size():
					_die("--draft needs a JSON file path")
					return
				draft_path = args[i + 1]
				i += 2
			"--out":
				if i + 1 >= args.size():
					_die("--out needs a directory")
					return
				out_dir = args[i + 1]
				i += 2
			"--views":
				if i + 1 >= args.size():
					_die("--views needs a list like full,quads")
					return
				views = args[i + 1].split(",")
				i += 2
			"--zoom":
				if i + 1 >= args.size():
					_die("--zoom needs a number")
					return
				zoom_mult = maxf(float(args[i + 1]), 0.1)
				i += 2
			_:
				_die("unknown argument '%s'" % args[i])
				return
	if (level_n == 0) == draft_path.is_empty():
		_die("pass exactly one of --level N (1-based) or --draft file.json")
		return
	var data := {}
	var source := ""
	if level_n > 0:
		if level_n < 1 or level_n > Levels.LEVELS.size():
			_die("--level %d out of range 1..%d" % [level_n, Levels.LEVELS.size()])
			return
		data = Levels.LEVELS[level_n - 1]
		source = "--level %d" % level_n
	else:
		data = _load_draft(draft_path)
		source = draft_path
		if data.is_empty():
			_die("draft did not load: %s" % draft_path)
			return
	_render(data, source, _resolve_out(out_dir), views, zoom_mult)


func _die(why: String) -> void:
	printerr(why)
	printerr("usage: godot --path . -s tools/render_board_preview.gd -- "
			+ "[--level N | --draft file.json] [--out DIR] [--views full,quads] [--zoom Z]")
	quit(1)


# ------------------------------------------------------------------ renderer --


func _render(data: Dictionary, source: String, out_dir: String, views: Array,
		zoom_mult: float) -> void:
	# Let the window and render loop come up before building anything.
	await process_frame

	var err := DirAccess.make_dir_recursive_absolute(out_dir)
	if err != OK and err != ERR_ALREADY_EXISTS:
		_die("cannot create output dir %s (%s)" % [out_dir, error_string(err)])
		return

	var stage := Node2D.new()
	stage.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(stage)
	var board: Board = Board.new()
	stage.add_child(board)  # _ready builds the FloorLayer
	board.set_level(data)
	_prop_seed = int(data.get("prop_seed",
			int(data.get("zone_seed", 7)) * 977 + 101))
	var entities := Node2D.new()
	entities.y_sort_enabled = true
	stage.add_child(entities)
	_spawn_props(board, entities, data)
	ApronScenery.spawn(board, entities, data, _prop_seed)
	var markers := Markers.new()
	markers.board = board
	markers.marks = _build_marks(data)
	markers.z_index = 20
	stage.add_child(markers)

	var camera := Camera2D.new()
	root.add_child(camera)
	camera.make_current()

	# Fit the whole board plus headroom for tall structures, snapped down to
	# eighths like Battle._fit_camera so texels land on a stable pixel grid.
	var bounds := _board_bounds(board).grow_individual(20.0, 100.0, 20.0, 24.0)
	var view := root.get_visible_rect().size
	var fit := minf((view.x - 16.0) / bounds.size.x, (view.y - 16.0) / bounds.size.y)
	fit = minf(fit, 1.0)
	fit = maxf(floorf(fit * zoom_mult * 8.0) / 8.0, 0.25)
	var centre := board.to_global(bounds.get_center())

	var wrote: Array = []
	var ok := true
	if views.has("full"):
		camera.zoom = Vector2(fit, fit)
		camera.position = centre
		var saved: bool = await _capture(out_dir.path_join("board_full.png"), wrote)
		ok = ok and saved
	if views.has("quads"):
		camera.zoom = Vector2(fit * 2.0, fit * 2.0)
		var quads := {
			"nw": Vector2(0.25, 0.25), "ne": Vector2(0.75, 0.25),
			"sw": Vector2(0.25, 0.75), "se": Vector2(0.75, 0.75),
		}
		for quad_name: String in quads:
			var at: Vector2 = quads[quad_name]
			camera.position = board.to_global(
					bounds.position + bounds.size * at)
			var saved: bool = await _capture(
					out_dir.path_join("board_%s.png" % quad_name), wrote)
			ok = ok and saved

	var meta := {
		"source": source,
		"name": str(data.get("name", "")),
		"floor": str(data.get("floor", Board.DEFAULT_FLOOR)),
		"zone_seed": int(data.get("zone_seed", 7)),
		"shade_seed": int(data.get("shade_seed", 13)),
		"zone_thresholds": data.get("zone_thresholds", [-0.12, 0.22]),
		"prop_seed": _prop_seed,
		"views": views,
		"files": wrote,
	}
	var meta_file := FileAccess.open(out_dir.path_join("meta.json"), FileAccess.WRITE)
	if meta_file != null:
		meta_file.store_string(JSON.stringify(meta, "  "))
		meta_file.close()
		wrote.append("meta.json")
	else:
		printerr("FAIL - cannot write meta.json")
		ok = false
	print("render_board_preview: %s -> %s (%s)" % [
			source, out_dir, ", ".join(wrote)])
	quit(0 if ok and not wrote.is_empty() else 1)


## The board's extent in board-local pixels - the same corners Battle's
## _fit_camera frames.
func _board_bounds(board: Board) -> Rect2:
	var half_w := Board.TILE_W / 2.0
	var half_h := Board.TILE_H / 2.0
	var min_x := (0 - (board.size.y - 1)) * half_w - half_w
	var max_x := (board.size.x - 1) * half_w + half_w
	var min_y := -half_h
	var max_y := (board.size.x - 1 + board.size.y - 1) * half_h + half_h
	return Rect2(min_x, min_y, max_x - min_x, max_y - min_y)


func _capture(path: String, wrote: Array) -> bool:
	# Two settled frames after any camera move, exactly like Battle's
	# _capture_screenshot, then read the window's own texture back.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var err := image.save_png(path)
	if err == OK:
		wrote.append(path.get_file())
		return true
	printerr("FAIL - could not save %s (%s)" % [path, error_string(err)])
	return false


## --out is project-relative unless it is already absolute (or res://-style).
func _resolve_out(dir: String) -> String:
	var out := dir.replace("\\", "/")
	if out.begins_with("res://") or out.begins_with("user://"):
		return ProjectSettings.globalize_path(out)
	if out.is_absolute_path():
		return out
	return ProjectSettings.globalize_path("res://").path_join(out)


# -------------------------------------------------------------------- props --


func _numbered(dir: String, base: String, count: int) -> Array:
	var paths: Array = [dir.path_join(base + ".png")]
	for i in range(1, count):
		paths.append(dir.path_join("%s_%d.png" % [base, i]))
	return paths


## Stand every map character's prop on its cell, with Battle's textures,
## offsets, hash streams and 2x scale - visuals only, no drums-with-state, no
## sway, no animation.
func _spawn_props(board: Board, entities: Node2D, data: Dictionary) -> void:
	var rocks: Array = []
	for i in range(1, 9):
		rocks.append(ENV + "/Desert_Rock_or_bolder/Rock_%d.png" % i)
	var junk := _numbered(ENV + "/desert_rusted_garbage", "Rusted_desert_garbage", 7)
	var plants := _numbered(ENV + "/desert_plants", "Desert_Plants", 16)
	var sandbags := _numbered(ENV + "/desert_sandbags", "Desert_Sandbags", 2)
	var caches: Array = []
	for path in _numbered(CACHE_ROOT, "Desert_insurgent_weapons_cache", 6):
		caches.append((path as String).get_basename() + "/rotations/unknown.png")
	var drum := PROP_ROOT \
			+ "/desert_Explosive_Fuel_drum/desert_Explosive_Fuel_drum/rotations/unknown.png"

	for y in board.size.y:
		for x in board.size.x:
			var cell := Vector2i(x, y)
			match board.map_char(cell):
				"#":
					_prop(board, entities, _pick(rocks, cell, SALT_ROCK),
							ROCK_OFFSET, cell)
				"j":
					_prop(board, entities, _pick(junk, cell, SALT_JUNK),
							JUNK_OFFSET, cell)
				"p":
					_prop(board, entities, _pick(plants, cell, SALT_PLANT),
							PLANT_OFFSET, cell)
				"s":
					_prop(board, entities, _pick(sandbags, cell, SALT_SANDBAG),
							SANDBAG_OFFSET, cell)
				"c":
					_prop(board, entities, _pick(caches, cell, SALT_CACHE),
							THIRST_CACHE_OFFSET, cell)
				"d":
					_prop(board, entities, drum, DRUM_OFFSET, cell)
				"W":
					var kind := _wall_kind(board, cell)
					_prop(board, entities, WALL_ROT.path_join(ROT_FILES[kind]),
							WALL_OFFSETS[kind], cell)
				"=":
					var run := _wire_kind(board, cell)
					_prop(board, entities, WIRE_ROT.path_join(ROT_FILES[run]),
							WIRE_OFFSETS[run], cell)
				"t":
					var claim := mini(int(Board._hash01(cell, _prop_seed + SALT_CLAIM)
							* CLAIM_FILES.size()), CLAIM_FILES.size() - 1)
					_prop(board, entities, CLAIM_ROOT.path_join(CLAIM_FILES[claim]),
							CLAIM_OFFSETS[claim], cell)
	for s: Dictionary in data.structures:
		_spawn_structure(board, entities, s)
	# Demolition targets stand their prop art on their cells, with the contact
	# shadows Battle hands the Board.
	var shadows := {}
	for obj in data.get("objectives", []):
		if obj.get("kind", "") != "destroy":
			continue
		var spec: Dictionary = TARGET_PROPS.get(obj.get("prop", "crates"),
				TARGET_PROPS.crates)
		for cell in obj.get("cells", []):
			_prop(board, entities, spec.still, spec.offset, cell)
			shadows[cell] = spec.shadow
	_spawn_decals(board, entities, data, shadows)
	if not shadows.is_empty():
		board.set_prop_shadows(shadows)


## Battle._spawn_decals, reproduced against the same salts so the preview shows
## the scatter the mission will actually have. Runs last, for the same reason
## it does there: it only dresses cells nothing else claimed.
func _spawn_decals(board: Board, entities: Node2D, data: Dictionary,
		shadows: Dictionary) -> void:
	var extract := {}
	for obj in data.get("objectives", []):
		if obj.get("kind", "") != "extract":
			continue
		for cell in obj.get("cells", []):
			extract[_v2i(cell)] = true
	for cell: Vector2i in extract:
		_decal(board, SIGNAL_ROOT.path_join("Signal_panel.png"), cell, false)
	_spawn_signal_stands(board, entities, data, extract, shadows)
	var detritus := _numbered(DETRITUS_ROOT, "Desert_detritus", 8)
	var placed: Array[Vector2i] = []
	for y in board.size.y:
		for x in board.size.x:
			var cell := Vector2i(x, y)
			if board.map_char(cell) != "." or board.is_structure(cell):
				continue
			if extract.has(cell) or shadows.has(cell):
				continue
			if Board._hash01(cell, _prop_seed + SALT_DETRITUS) >= DETRITUS_RATE:
				continue
			var clear := true
			for other: Vector2i in placed:
				if maxi(absi(other.x - cell.x), absi(other.y - cell.y)) <= DETRITUS_GAP:
					clear = false
					break
			if not clear:
				continue
			placed.append(cell)
			_decal(board, _pick(detritus, cell, SALT_DETRITUS_PICK), cell, true)


func _spawn_signal_stands(board: Board, entities: Node2D, data: Dictionary,
		extract: Dictionary, shadows: Dictionary) -> void:
	if extract.is_empty():
		return
	var occupied := {}
	for key: String in SPAWN_KEYS:
		for spawn in data.get(key, []):
			occupied[_v2i(spawn)] = true
	for spawn in data.get("bystander_spawns", []):
		occupied[_v2i(spawn)] = true
	var taken: Array[Vector2i] = []
	for cell: Vector2i in extract:
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if taken.size() >= SIGNAL_STANDS:
				return
			var side: Vector2i = cell + dir
			if extract.has(side) or not board.in_bounds(side):
				continue
			if board.map_char(side) != "." or board.is_structure(side):
				continue
			if shadows.has(side) or occupied.has(side):
				continue
			var clear := true
			for other: Vector2i in taken:
				if maxi(absi(other.x - side.x), absi(other.y - side.y)) < 2:
					clear = false
					break
			if not clear:
				continue
			taken.append(side)
			var pick := mini(int(Board._hash01(side, _prop_seed + SALT_SIGNAL)
					* SIGNAL_STAND_FILES.size()), SIGNAL_STAND_FILES.size() - 1)
			_prop(board, entities, SIGNAL_ROOT.path_join(SIGNAL_STAND_FILES[pick]),
					SIGNAL_STAND_OFFSETS[pick], side)
			shadows[side] = SIGNAL_STAND_SHADOW


## Flat ground art, on the Board's decal layer at 1x - see Battle._spawn_decal
## for why this one class of scenery is not doubled.
func _decal(board: Board, path: String, cell: Vector2i, jitter: bool) -> void:
	if not ResourceLoader.exists(path):
		printerr("missing decal art: %s" % path)
		return
	var decal := Sprite2D.new()
	decal.texture = load(path)
	decal.material = _dust_material(board, cell)
	decal.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	decal.position = board.cell_to_local(cell)
	if jitter:
		var hx := Board._hash01(cell, _prop_seed + SALT_DETRITUS_JITTER)
		var hy := Board._hash01(cell + Vector2i(97, 61), _prop_seed + SALT_DETRITUS_JITTER)
		decal.position += Vector2(
				roundf((hx - 0.5) * 2.0 * DETRITUS_JITTER),
				roundf((hy - 0.5) * DETRITUS_JITTER))
		decal.flip_h = hx > 0.5
	board.decal_layer.add_child(decal)


func _pick(paths: Array, cell: Vector2i, salt: int) -> String:
	return paths[mini(int(Board._hash01(cell, _prop_seed + salt) * paths.size()),
			paths.size() - 1)]


func _prop(board: Board, entities: Node2D, path: String, offset: Vector2,
		cell: Vector2i) -> void:
	if not ResourceLoader.exists(path):
		printerr("missing prop art: %s" % path)
		return
	var prop := Sprite2D.new()
	prop.texture = load(path)
	prop.offset = offset
	prop.scale = Vector2(2, 2)
	prop.material = _dust_material(board, cell)
	prop.position = board.cell_to_global(cell)
	entities.add_child(prop)


## Battle draws structures as per-column y-sort strips so units interleave;
## with no units on a preview, one sprite anchored at the footprint's front
## cell lands on the identical pixels.
func _spawn_structure(board: Board, entities: Node2D, s: Dictionary) -> void:
	var dir: String = STRUCTURE_DIRS.get(s.kind, "")
	var still := dir + "/rotations/unknown.png"
	if dir.is_empty() or not ResourceLoader.exists(still):
		printerr("missing structure art for kind '%s'" % s.get("kind"))
		return
	var anchor: Vector2i = s.anchor
	var front: Vector2i = anchor + (s.size as Vector2i) - Vector2i.ONE
	var stand := Node2D.new()
	stand.position = board.cell_to_global(front)
	var spr := Sprite2D.new()
	spr.texture = load(still)
	spr.scale = Vector2(2, 2)
	spr.offset = STRUCTURE_OFFSETS.get(s.kind, Vector2.ZERO)
	spr.material = _dust_material(board, front)
	spr.position = (board.cell_to_global(anchor) + board.cell_to_global(front)) \
			/ 2.0 - stand.position
	stand.add_child(spr)
	entities.add_child(stand)


func _wall_connects(board: Board, cell: Vector2i) -> bool:
	return board.map_char(cell) == "W" or board.is_structure(cell)


func _wall_kind(board: Board, cell: Vector2i) -> String:
	var has_x := _wall_connects(board, cell + Vector2i(1, 0)) \
			or _wall_connects(board, cell + Vector2i(-1, 0))
	var has_y := _wall_connects(board, cell + Vector2i(0, 1)) \
			or _wall_connects(board, cell + Vector2i(0, -1))
	if has_x and has_y:
		return "junction"
	return "x_run" if has_x else ("y_run" if has_y else "cap")


func _wire_kind(board: Board, cell: Vector2i) -> String:
	var has_x := board.map_char(cell + Vector2i(1, 0)) == "=" \
			or board.map_char(cell + Vector2i(-1, 0)) == "="
	var has_y := board.map_char(cell + Vector2i(0, 1)) == "=" \
			or board.map_char(cell + Vector2i(0, -1)) == "="
	if has_x and has_y:
		return "junction"
	return "x_run" if has_x else ("y_run" if has_y else "cap")


## Battle's depth-banded dust grade, so preview props sit in the same air the
## game puts them in.
func _dust_material(board: Board, cell: Vector2i) -> ShaderMaterial:
	if _dust_shader == null:
		_dust_shader = load(PROP_DUST)
	var span := maxi(board.size.x + board.size.y - 2, 1)
	var depth := 1.0 - float(cell.x + cell.y) / float(span)
	var band := clampi(int(depth * float(Board.HAZE_BANDS)), 0, Board.HAZE_BANDS - 1)
	if not _dust_materials.has(band):
		var mood := board.floor_mood()
		var mat := ShaderMaterial.new()
		mat.shader = _dust_shader
		mat.set_shader_parameter("tint", mood.tint)
		mat.set_shader_parameter("haze_color", mood.haze)
		mat.set_shader_parameter("haze",
				Board.HAZE_MAX * (float(band) + 0.5) / float(Board.HAZE_BANDS))
		_dust_materials[band] = mat
	return _dust_materials[band]


# ------------------------------------------------------------------ markers --


func _build_marks(data: Dictionary) -> Array:
	var marks: Array = []
	for obj in data.get("objectives", []):
		match obj.get("kind", ""):
			"extract":
				for cell in obj.get("cells", []):
					marks.append({"cell": cell, "color": EXTRACT_COLOR, "fill": true})
			"destroy":
				for cell in obj.get("cells", []):
					marks.append({"cell": cell, "color": DESTROY_COLOR})
	for key: String in SQUAD_MARKS:
		for cell in data.get(key, []):
			marks.append({"cell": cell, "color": SQUAD_COLOR,
					"letter": SQUAD_MARKS[key]})
	for key: String in ENEMY_MARKS:
		for cell in data.get(key, []):
			marks.append({"cell": cell, "color": ENEMY_MARKS[key].color,
					"letter": ENEMY_MARKS[key].letter})
	for cell in data.get("prisoner_spawns", []):
		marks.append({"cell": cell, "color": PRISONER_COLOR, "letter": "P"})
	return marks


## Diamond outlines and letters over everything, in board coordinates. Kept as
## a node (not draw calls in _render) so it survives every camera move.
class Markers:
	extends Node2D
	var board: Board = null
	var marks: Array = []

	func _draw() -> void:
		if board == null:
			return
		var font := ThemeDB.fallback_font
		for m: Dictionary in marks:
			var d: PackedVector2Array = board._diamond(m.cell)
			if m.get("fill", false):
				var fill: Color = m.color
				fill.a = 0.22
				draw_colored_polygon(d, fill)
			var ring := d.duplicate()
			ring.append(ring[0])
			draw_polyline(ring, m.color, 3.0, true)
			var letter: String = m.get("letter", "")
			if letter != "":
				draw_string(font, board.cell_to_local(m.cell) + Vector2(-5, 7),
						letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, m.color)


# -------------------------------------------------------------------- draft --
# Identical shape and coercion to check_level.gd's draft loader, duplicated
# because tools/ carries a .gdignore and cannot cross-load its own scripts.


## Cells arrive as `[x, y]` from a JSON draft and as a real Vector2i from
## Levels.LEVELS. This used to handle only the draft form and answer (-1, -1)
## for the other, which is a silent wrong answer rather than an error: every
## extraction cell of a shipped level folded onto one off-board cell, and the
## preview drew a single signal panel in the void beside the map.
static func _v2i(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Vector2:
		return Vector2i(value)
	if value is Array and (value as Array).size() == 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i(-1, -1)


func _load_draft(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		printerr("cannot open draft: %s (%s)"
				% [path, error_string(FileAccess.get_open_error())])
		return {}
	var raw: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(raw) != TYPE_DICTIONARY:
		printerr("draft is not a JSON object: %s" % path)
		return {}
	return _coerce_draft(raw)


static func _coerce_draft(raw: Dictionary) -> Dictionary:
	var data := {}
	data.name = str(raw.get("name", "draft"))
	var map: Array = []
	for row in raw.get("map", []):
		map.append(str(row))
	data.map = map
	var size := Vector2i(str(map[0]).length() if map.size() > 0 else 0, map.size())
	if raw.has("size"):
		size = _v2i(raw.size)
	data.size = size
	for key: String in SPAWN_KEYS:
		if raw.has(key):
			var cells: Array = []
			for value in raw[key]:
				cells.append(_v2i(value))
			data[key] = cells
	var structures: Array = []
	for s in raw.get("structures", []):
		structures.append({"kind": str(s.get("kind", "")),
				"anchor": _v2i(s.get("anchor", [])), "size": _v2i(s.get("size", []))})
	data.structures = structures
	if raw.has("objectives"):
		var objectives: Array = []
		for o in raw.objectives:
			var obj := {"kind": str(o.get("kind", ""))}
			for copied: String in ["label", "prop"]:
				if o.has(copied):
					obj[copied] = str(o[copied])
			if o.has("cells"):
				var cells: Array = []
				for value in o.cells:
					cells.append(_v2i(value))
				obj.cells = cells
			objectives.append(obj)
		data.objectives = objectives
	if raw.has("floor"):
		data.floor = str(raw.floor)
	if raw.has("floor_inset"):
		var inset: Dictionary = raw.floor_inset
		var r: Array = inset.get("rect", [])
		data.floor_inset = {
			"floor": str(inset.get("floor", Board.DEFAULT_FLOOR)),
			"rect": Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])) \
					if r.size() == 4 else Rect2i(),
		}
	for key: String in ["zone_seed", "shade_seed", "prop_seed"]:
		if raw.has(key):
			data[key] = int(raw[key])
	if raw.has("zone_thresholds") and (raw.zone_thresholds as Array).size() == 2:
		data.zone_thresholds = [float(raw.zone_thresholds[0]),
				float(raw.zone_thresholds[1])]
	if raw.has("zone_map"):
		var rows: Array = []
		for row in raw.zone_map:
			rows.append(str(row))
		data.zone_map = rows
	if raw.has("lint"):
		data.lint = raw.lint
	return data
