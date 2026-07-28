extends Node2D

## Battle controller: turn state machine, player input, enemy AI, win/lose.

enum State { PLAYER_TURN, ANIMATING, ENEMY_TURN, GAME_OVER }

## Direction-picking modes: both preview a cone and commit on a click.
## OVERWATCH consumes the unit's attack; FACE is free.
enum AimMode { NONE, OVERWATCH, FACE }

## Which trigger setting the selected unit will use on its next shot.
## SUPPRESS is the machinegunner's ability rather than a trigger setting:
## it deals no damage and pins an area instead.
enum FireMode { SINGLE, BURST, AUTO, SUPPRESS }

const UNIT_SCENE := preload("res://scenes/Unit.tscn")
const ROCK_TEXTURES: Array[Texture2D] = [
	preload("res://assets/sprites/Environment/Desert/Desert_Rock_or_bolder/Rock_1.png"),
	preload("res://assets/sprites/Environment/Desert/Desert_Rock_or_bolder/Rock_2.png"),
	preload("res://assets/sprites/Environment/Desert/Desert_Rock_or_bolder/Rock_3.png"),
]
const JUNK_TEXTURES: Array[Texture2D] = [
	preload("res://assets/sprites/Environment/Desert/desert_rusted_garbage/Rusted_desert_garbage.png"),
	preload("res://assets/sprites/Environment/Desert/desert_rusted_garbage/Rusted_desert_garbage_1.png"),
	preload("res://assets/sprites/Environment/Desert/desert_rusted_garbage/Rusted_desert_garbage_2.png"),
	preload("res://assets/sprites/Environment/Desert/desert_rusted_garbage/Rusted_desert_garbage_3.png"),
	preload("res://assets/sprites/Environment/Desert/desert_rusted_garbage/Rusted_desert_garbage_4.png"),
	preload("res://assets/sprites/Environment/Desert/desert_rusted_garbage/Rusted_desert_garbage_5.png"),
	preload("res://assets/sprites/Environment/Desert/desert_rusted_garbage/Rusted_desert_garbage_6.png"),
]
const PLANT_TEXTURES: Array[Texture2D] = [
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants.png"),
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants_1.png"),
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants_2.png"),
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants_3.png"),
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants_4.png"),
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants_5.png"),
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants_6.png"),
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants_7.png"),
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants_8.png"),
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants_9.png"),
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants_10.png"),
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants_11.png"),
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants_12.png"),
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants_13.png"),
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants_14.png"),
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants_15.png"),
]
# The rotation names describe the wall's FACING, so its length runs along
# the perpendicular axis: a south-west-facing wall runs NW-SE (grid x).
const WALL_TEX_X_RUN := preload(
		"res://assets/sprites/Environment/Desert/Walls/desert_brick_and_mud/rotations/south-west.png")
const WALL_TEX_Y_RUN := preload(
		"res://assets/sprites/Environment/Desert/Walls/desert_brick_and_mud/rotations/south-east.png")
const WALL_TEX_JUNCTION := preload(
		"res://assets/sprites/Environment/Desert/Walls/desert_brick_and_mud/rotations/north.png")
const WALL_TEX_CAP := preload(
		"res://assets/sprites/Environment/Desert/Walls/desert_brick_and_mud/rotations/east.png")
const STRUCTURE_ROOT := "res://assets/sprites/Environment/Desert/Structures"
const STRUCTURE_DIRS := {
	"hut_1": STRUCTURE_ROOT + "/desert_hut/Desert_hut",
	"hut_2": STRUCTURE_ROOT + "/desert_hut/Desert_hut_1",
	"tent": STRUCTURE_ROOT + "/desert_hut/Desert_hut_2",
	"fortress": STRUCTURE_ROOT + "/Desert_military_building",
}
const STRUCTURE_FPS := 7.0  # gentle breeze loops

# Ground anchors measured from opaque bounds (texture px, pre-2x-scale).
# Props center their painted ground footprint on the cell center; walls sink
# toward the tile's front edge; structures align base to footprint front vertex.
const ROCK_OFFSET := Vector2(0, -18)
const JUNK_OFFSET := Vector2(0, -20)
const PLANT_OFFSET := Vector2(0, -17)
const WALL_OFFSETS := {
	"x_run": Vector2(0, -15), "y_run": Vector2(0, -15),
	"junction": Vector2(0, -9), "cap": Vector2(0, -11),
}
const STRUCTURE_OFFSETS := {
	"hut_1": Vector2(0, -22), "hut_2": Vector2(0, -33),
	"tent": Vector2(0, -33), "fortress": Vector2(0, -55),
}
const ROCK_SCALE := Vector2(2, 2)

const MOVE_STEP_TIME := 0.16
const TRACER_TIME := 0.09
const AI_BEAT := 0.12
const ACT_LEAD_IN := 0.15  # pause after marking a goblin, before it acts
const SWAY_SPEED := 1.6      # radians/sec of the plant sway cycle
const SWAY_TEXELS := 1.0     # sprite texels a plant leans at full sway
const FLANK_ACCURACY := 10   # bonus to hit from outside the target's arc
const LONG_SHOT_PENALTY := 5  # per tile past half the shooter's range
const SUPPRESSION_ACCURACY := 25  # to-hit penalty while pinned down
const LOWER_TIME := 0.12  # rifle held after the shot before lowering
const BURST_GAP := 0.13  # pause between the rounds of a burst
const AUTO_GAP := 0.07   # full auto cycles faster than a burst
const BURST_ROUNDS := 2
const AUTO_ROUNDS := 4
const AUTO_ACCURACY := -15  # per-round penalty for walking the gun
const SUPPRESS_ROUNDS := 3

# Ignore end-turn requests this soon after control returns to the player -
# they are almost always leftover E-mashing/clicking from the enemy turn.
const END_TURN_GRACE_MS := 350

var state := State.PLAYER_TURN
var selected: Unit = null
var hover_cell := Board.NO_CELL
var turn_number := 1
var enemy_turn_running := false
var player_turn_ready_msec := 0
var danger_on := false
var fire_mode := FireMode.SINGLE
var aim_mode := AimMode.NONE
var level: Dictionary = {}
var last_result_won := false
var base_camera_pos := Vector2.ZERO
var base_zoom := Vector2.ONE
var _cam_lean := Vector2.ZERO
var _cam_shake := Vector2.ZERO
var _shake_tween: Tween = null
var _kick_tween: Tween = null
var _rng := RandomNumberGenerator.new()
var _swaying: Array = []
var _animated_props: Array = []
var structure_frames: Dictionary = {}
var fx_ground: Fx = null
var fx_air: Fx = null
var fx_glow: Fx = null

@onready var board: Board = $Board
@onready var camera: Camera2D = $Camera
@onready var entities_node: Node2D = $Entities
@onready var turn_banner: Label = $UI/TurnBanner
@onready var end_turn_button: Button = $UI/EndTurnButton
@onready var overwatch_button: Button = $UI/OverwatchButton
@onready var burst_button: Button = $UI/BurstButton
@onready var auto_button: Button = $UI/AutoButton
@onready var suppress_button: Button = $UI/SuppressButton
@onready var reload_button: Button = $UI/ReloadButton
@onready var face_button: Button = $UI/FaceButton
@onready var danger_button: Button = $UI/DangerButton
@onready var unit_panel: PanelContainer = $UI/UnitPanel
@onready var panel_name_label: Label = $UI/UnitPanel/Margin/Rows/NameLabel
@onready var panel_hp_label: Label = $UI/UnitPanel/Margin/Rows/HpLabel
@onready var panel_stats_label: Label = $UI/UnitPanel/Margin/Rows/StatsLabel
@onready var panel_status_label: Label = $UI/UnitPanel/Margin/Rows/StatusLabel
@onready var game_over_panel: ColorRect = $UI/GameOver
@onready var result_label: Label = $UI/GameOver/ResultLabel
@onready var restart_button: Button = $UI/GameOver/RestartButton
@onready var level_1_button: Button = $UI/GameOver/Level1Button
@onready var level_2_button: Button = $UI/GameOver/Level2Button
@onready var level_3_button: Button = $UI/GameOver/Level3Button


func _ready() -> void:
	_rng.randomize()
	Engine.time_scale = 1.0  # a reload mid-hit-stop must never persist
	Levels.validate_all()  # push_error-based, so it reports in release too
	level = Game.data()
	board.set_level(level)
	_fit_camera()
	_setup_fx_layers()
	_validate_spawns()
	_load_structure_art()
	_spawn_props()
	for s: Dictionary in level.structures:
		_spawn_structure(s)
	for spawn: Vector2i in level.get("lead_spawns", []):
		_spawn_unit(Unit.Kind.TEAM_LEAD, spawn)
	for spawn: Vector2i in level.get("gunner_spawns", []):
		_spawn_unit(Unit.Kind.MACHINEGUNNER, spawn)
	for spawn: Vector2i in level.scout_spawns:
		_spawn_unit(Unit.Kind.SCOUT, spawn)
	for spawn: Vector2i in level.goblin_spawns:
		_spawn_unit(Unit.Kind.GOBLIN, spawn)
	for spawn: Vector2i in level.get("smg_spawns", []):
		_spawn_unit(Unit.Kind.GOBLIN_SMG, spawn)
	for spawn: Vector2i in level.get("smg_alt_spawns", []):
		_spawn_unit(Unit.Kind.GOBLIN_SMG_ALT, spawn)
	for spawn: Vector2i in level.get("novice_spawns", []):
		_spawn_unit(Unit.Kind.GOBLIN_REVOLVER, spawn)
	for spawn: Vector2i in level.get("bolt_spawns", []):
		_spawn_unit(Unit.Kind.GOBLIN_BOLT, spawn)
	end_turn_button.pressed.connect(end_player_turn)
	overwatch_button.toggled.connect(_on_aim_button_toggled.bind(AimMode.OVERWATCH))
	face_button.toggled.connect(_on_aim_button_toggled.bind(AimMode.FACE))
	burst_button.toggled.connect(_on_fire_button_toggled.bind(FireMode.BURST))
	auto_button.toggled.connect(_on_fire_button_toggled.bind(FireMode.AUTO))
	suppress_button.toggled.connect(_on_fire_button_toggled.bind(FireMode.SUPPRESS))
	reload_button.pressed.connect(_try_reload)
	danger_button.toggled.connect(_on_danger_button_toggled)
	restart_button.pressed.connect(_on_restart)
	# Hotkeys/buttons cover the first 3 levels; extend the level_N input
	# actions and this button row alongside any new Levels.LEVELS entries.
	var level_buttons: Array[Button] = [level_1_button, level_2_button, level_3_button]
	for i in level_buttons.size():
		if i < Levels.LEVELS.size():
			level_buttons[i].pressed.connect(_go_to_level.bind(i))
		else:
			level_buttons[i].visible = false
	show_banner("LEVEL %d - %s" % [Game.current_level + 1, level.name])
	player_turn_ready_msec = Time.get_ticks_msec()
	print("[ThinShot] level %d '%s', player turn 1 begins" % [
			Game.current_level + 1, level.name])
	await get_tree().create_timer(1.1).timeout
	# Swap to the turn banner unless the enemy turn or game over owns it
	# (ANIMATING just means the player is already acting - still their turn).
	if state == State.PLAYER_TURN or state == State.ANIMATING:
		show_banner("DESERT SCOUTS' TURN")


## Center the level on screen and zoom so it fits, leaving headroom for
## the banner (top) and the button row / unit panel (bottom).
func _fit_camera() -> void:
	var half_w := Board.TILE_W / 2.0
	var half_h := Board.TILE_H / 2.0
	var min_x := (0 - (board.size.y - 1)) * half_w - half_w
	var max_x := (board.size.x - 1) * half_w + half_w
	var min_y := -half_h
	var max_y := (board.size.x - 1 + board.size.y - 1) * half_h + half_h
	var world_size := Vector2(max_x - min_x, max_y - min_y)
	var view := get_viewport_rect().size
	var margin_top := 52.0
	var margin_bottom := 96.0
	var avail := Vector2(view.x - 40.0, view.y - margin_top - margin_bottom)
	var fit: float = minf(avail.x / world_size.x, avail.y / world_size.y)
	fit = minf(fit, 1.0)
	camera.zoom = Vector2(fit, fit)
	var center_local := Vector2((min_x + max_x) / 2.0, (min_y + max_y) / 2.0)
	var screen_center_y := margin_top + avail.y / 2.0
	camera.position = board.to_global(center_local) \
			+ Vector2(0, (view.y / 2.0 - screen_center_y) / fit)
	# Cached so shake/kick can scale to screen space. Nothing else may write
	# camera.position or camera.zoom - the full board staying framed is the
	# contract that keeps the game readable.
	base_camera_pos = camera.position
	base_zoom = camera.zoom


## Three pooled particle layers: dust under the board's entities, debris
## above them, and an additive layer for anything that glows.
func _setup_fx_layers() -> void:
	fx_ground = Fx.new()
	add_child(fx_ground)
	move_child(fx_ground, board.get_index() + 1)
	fx_air = Fx.new()
	add_child(fx_air)
	fx_glow = Fx.new()
	var glow_material := CanvasItemMaterial.new()
	glow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	fx_glow.material = glow_material
	fx_glow.z_index = 15
	add_child(fx_glow)
	# Steady desert wind across the board, plus the occasional gust.
	fx_air.set_ambient(_board_world_rect().grow(90.0), 26, Vector2(-34.0, 11.0))


## The board's extent in world space, used to frame the camera and to bound
## the ambient wind.
func _board_world_rect() -> Rect2:
	var half_w := Board.TILE_W / 2.0
	var half_h := Board.TILE_H / 2.0
	var min_x := (0 - (board.size.y - 1)) * half_w - half_w
	var max_x := (board.size.x - 1) * half_w + half_w
	var max_y := (board.size.x - 1 + board.size.y - 1) * half_h + half_h
	var origin := board.to_global(Vector2(min_x, -half_h))
	return Rect2(origin, Vector2(max_x - min_x, max_y + half_h))


func _validate_spawns() -> void:
	for spawn: Vector2i in level.scout_spawns + level.get("lead_spawns", []) \
			+ level.get("gunner_spawns", []) + level.goblin_spawns \
			+ level.get("smg_spawns", []) + level.get("smg_alt_spawns", []) \
			+ level.get("novice_spawns", []) + level.get("bolt_spawns", []):
		if not board.in_bounds(spawn) or not board.is_walkable(spawn):
			push_error("Bad spawn cell (blocked or out of bounds): %s" % spawn)
			assert(false, "Bad spawn cell: %s" % spawn)


func _spawn_props() -> void:
	for y in board.size.y:
		for x in board.size.x:
			var cell := Vector2i(x, y)
			# Deterministic variant per cell so layouts are stable.
			match board.map_char(cell):
				"#":
					_spawn_prop(ROCK_TEXTURES[(x * 7 + y * 13) % ROCK_TEXTURES.size()],
							ROCK_OFFSET, cell)
				"j":
					_spawn_prop(JUNK_TEXTURES[(x * 11 + y * 17) % JUNK_TEXTURES.size()],
							JUNK_OFFSET, cell)
				"p":
					var plant := _spawn_prop(
							PLANT_TEXTURES[(x * 5 + y * 23) % PLANT_TEXTURES.size()],
							PLANT_OFFSET, cell)
					# Phase from the cell so no two plants sway in step.
					_swaying.append({
						"sprite": plant,
						"base_x": plant.position.x,
						"phase": float((x * 7 + y * 13) % 16) / 16.0 * TAU,
					})
				"W":
					var kind := _wall_kind(cell)
					_spawn_prop(_wall_texture_for(kind), WALL_OFFSETS[kind], cell)


func _spawn_prop(texture: Texture2D, offset: Vector2, cell: Vector2i) -> Sprite2D:
	var prop := Sprite2D.new()
	prop.texture = texture
	prop.offset = offset
	prop.scale = ROCK_SCALE
	prop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	prop.position = board.cell_to_global(cell)
	entities_node.add_child(prop)
	return prop


func _wall_connects(cell: Vector2i) -> bool:
	return board.map_char(cell) == "W" or board.is_structure(cell)


## Wall runs along grid x read on the screen NW-SE diagonal; runs along
## grid y read NE-SW. Junctions use the flat face, lone cells the end cap.
func _wall_kind(cell: Vector2i) -> String:
	var has_x := _wall_connects(cell + Vector2i(1, 0)) or _wall_connects(cell + Vector2i(-1, 0))
	var has_y := _wall_connects(cell + Vector2i(0, 1)) or _wall_connects(cell + Vector2i(0, -1))
	if has_x and has_y:
		return "junction"
	if has_x:
		return "x_run"
	if has_y:
		return "y_run"
	return "cap"


func _wall_texture_for(kind: String) -> Texture2D:
	match kind:
		"x_run":
			return WALL_TEX_X_RUN
		"y_run":
			return WALL_TEX_Y_RUN
		"junction":
			return WALL_TEX_JUNCTION
	return WALL_TEX_CAP


## Structure art lives at <dir>/rotations/unknown.png, with an optional
## breeze loop beside it at <dir>/animations/<name>/unknown/frame_NNN.png.
## The animation folder is named after the prompt that generated it, so we
## scan for whatever is there instead of hardcoding the name.
static func _load_structure_frames(dir: String) -> Array[Texture2D]:
	var frames: Array[Texture2D] = []
	var anim_root := dir + "/animations"
	var da := DirAccess.open(anim_root)
	if da != null:
		for sub in da.get_directories():
			var base := "%s/%s/unknown" % [anim_root, sub]
			var i := 0
			while ResourceLoader.exists("%s/frame_%03d.png" % [base, i]):
				frames.append(load("%s/frame_%03d.png" % [base, i]))
				i += 1
			if not frames.is_empty():
				break
	if frames.is_empty():
		var still := dir + "/rotations/unknown.png"
		if ResourceLoader.exists(still):
			frames.append(load(still))
	return frames


func _load_structure_art() -> void:
	for kind: String in STRUCTURE_DIRS:
		structure_frames[kind] = _load_structure_frames(STRUCTURE_DIRS[kind])


## Multi-tile set-piece: a y-sort root at the footprint's front cell so units
## on nearer rows draw in front, with the sprite centered on the footprint.
func _spawn_structure(s: Dictionary) -> void:
	var anchor: Vector2i = s.anchor
	var struct_size: Vector2i = s.size
	var front: Vector2i = anchor + struct_size - Vector2i.ONE
	var frames: Array = structure_frames.get(s.kind, [])
	if frames.is_empty():
		push_error("No art found for structure kind '%s'" % s.kind)
		return
	var root := Node2D.new()
	root.position = board.cell_to_global(front)
	var spr := Sprite2D.new()
	spr.texture = frames[0]
	spr.scale = Vector2(2, 2)
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.offset = STRUCTURE_OFFSETS[s.kind]
	spr.position = (board.cell_to_global(anchor) + board.cell_to_global(front)) / 2.0 \
			- root.position
	root.add_child(spr)
	entities_node.add_child(root)
	if frames.size() > 1:
		# Phase from the anchor cell so no two structures breathe in step.
		_animated_props.append({
			"sprite": spr,
			"frames": frames,
			"phase": float((anchor.x * 5 + anchor.y * 11) % 9) / STRUCTURE_FPS,
			"frame": -1,
		})


func _spawn_unit(kind: Unit.Kind, spawn_cell: Vector2i) -> void:
	var unit: Unit = UNIT_SCENE.instantiate()
	entities_node.add_child(unit)
	unit.setup(kind, spawn_cell)
	unit.position = board.cell_to_global(spawn_cell)
	unit.died.connect(_on_unit_died)


func living_units(team: int) -> Array[Unit]:
	var result: Array[Unit] = []
	for child in entities_node.get_children():
		var unit := child as Unit
		if unit != null and unit.is_alive():
			if unit.team == team:
				result.append(unit)
	return result


func unit_at(cell: Vector2i) -> Unit:
	for child in entities_node.get_children():
		var unit := child as Unit
		if unit != null and unit.is_alive() and unit.cell == cell:
			return unit
	return null


## Movement blocker for a given team: only enemies stop you. Soldiers
## squeeze past their own squadmates, which matters on maps built around
## one-tile gates. Ending a move on an occupied tile is still illegal -
## that is enforced separately, on the destination rather than the path.
func _blocked_for_team(cell: Vector2i, team: int) -> bool:
	var other := unit_at(cell)
	return other != null and other.team != team


## Of the cells a unit can reach, the ones it could actually stand on.
func _free_dests(reachable: Dictionary) -> Dictionary:
	var dests := {}
	for cell: Vector2i in reachable:
		if unit_at(cell) == null:
			dests[cell] = true
	return dests


# --- Player input ------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if state != State.PLAYER_TURN:
		return
	if event is InputEventMouseMotion:
		_update_hover(board.global_to_cell(get_global_mouse_position()))
		return
	if event.is_action_pressed("end_turn"):
		end_player_turn()
		return
	if event.is_action_pressed("overwatch"):
		_try_overwatch()
		return
	if event.is_action_pressed("burst"):
		_toggle_fire_mode(FireMode.BURST)
		return
	if event.is_action_pressed("full_auto"):
		_toggle_fire_mode(FireMode.AUTO)
		return
	if event.is_action_pressed("suppress"):
		_toggle_fire_mode(FireMode.SUPPRESS)
		return
	if event.is_action_pressed("reload"):
		_try_reload()
		return
	if event.is_action_pressed("face"):
		_try_face()
		return
	if event.is_action_pressed("toggle_danger"):
		_toggle_danger()
		return
	if event.is_action_pressed("cycle_unit"):
		_cycle_unit()
		return
	for i in mini(3, Levels.LEVELS.size()):
		if event.is_action_pressed("level_%d" % (i + 1)):
			_go_to_level(i)
			return
	if event.is_action_pressed("cancel"):
		if aim_mode != AimMode.NONE:
			_cancel_aim()
		else:
			deselect()
		return
	var mouse := event as InputEventMouseButton
	if mouse == null or not mouse.pressed:
		return
	if mouse.button_index == MOUSE_BUTTON_RIGHT:
		if aim_mode != AimMode.NONE:
			_cancel_aim()
		else:
			deselect()
		return
	if mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	var cell := board.global_to_cell(get_global_mouse_position())
	if not board.in_bounds(cell):
		return
	_handle_click(cell)


func _handle_click(cell: Vector2i) -> void:
	if aim_mode != AimMode.NONE and selected != null and cell != selected.cell:
		_commit_aim(cell)
		return
	var clicked := unit_at(cell)
	if selected != null:
		if clicked != null and clicked.team == Unit.TEAM_GOBLIN \
				and board.attack_cells.has(cell):
			_fire_selected_at(clicked)
			return
		if board.move_dests.has(cell):
			do_move(selected, cell)
			return
	# Spent scouts stay selectable: turning to face is always available.
	if clicked != null and clicked.team == Unit.TEAM_SCOUT:
		select(clicked)
	else:
		deselect()


## Drops any direction-picking mode without touching the selection.
func _clear_aim_mode() -> void:
	if aim_mode == AimMode.NONE:
		return
	aim_mode = AimMode.NONE
	_sync_aim_buttons()
	if selected != null:
		selected.arc_preview_sector = -1
		selected.queue_redraw()
	_refresh_watch_cells()


## Shoot the target with whatever trigger setting is currently armed,
## falling back to the unit's default if the armed mode became unusable.
func _fire_selected_at(target: Unit) -> void:
	var mode := fire_mode
	if not _can_use_mode(selected, mode):
		mode = _default_fire_mode(selected)
		if not _can_use_mode(selected, mode):
			return
	match mode:
		FireMode.BURST:
			do_volley(selected, target, BURST_ROUNDS, BURST_GAP, 0)
		FireMode.AUTO:
			do_volley(selected, target, AUTO_ROUNDS, AUTO_GAP, AUTO_ACCURACY)
		FireMode.SUPPRESS:
			do_suppressive_fire(selected, target)
		_:
			do_attack(selected, target)


func select(unit: Unit) -> void:
	_clear_aim_mode()
	if selected != null:
		selected.set_selected(false)
	selected = unit
	unit.set_selected(true)
	_set_fire_mode(_default_fire_mode(unit))  # each soldier has its own default
	Sfx.play("select", 0.0, 0.0)
	_refresh_highlights()
	_update_unit_panel()


func deselect() -> void:
	_clear_aim_mode()
	if selected != null:
		selected.set_selected(false)
		selected = null
	_set_fire_mode(_default_fire_mode(selected))
	board.clear_highlights()
	_update_unit_panel()


## The trigger setting a unit falls back to. The machinegunner has no
## semi-automatic position, so his rest state is burst.
func _default_fire_mode(unit: Unit) -> FireMode:
	return FireMode.SINGLE if unit != null and unit.can_single_shot() else FireMode.BURST


## Rounds a mode spends, so ammo can be checked before arming or firing.
func _rounds_for(mode: FireMode) -> int:
	match mode:
		FireMode.BURST:
			return BURST_ROUNDS
		FireMode.AUTO:
			return AUTO_ROUNDS
		FireMode.SUPPRESS:
			return SUPPRESS_ROUNDS
	return 1


func _can_use_mode(unit: Unit, mode: FireMode) -> bool:
	if unit == null or unit.acted or not unit.has_ammo(_rounds_for(mode)):
		return false
	match mode:
		FireMode.BURST:
			return unit.can_burst() and not (unit.burst_requires_still() and unit.moved)
		FireMode.AUTO:
			# Walking the gun needs a firing position, never the advance.
			return unit.can_full_auto() and not unit.moved
		FireMode.SUPPRESS:
			return unit.can_suppress()
	return unit.can_single_shot()


## Toggle a firing mode on the selected unit, falling back to its default.
func _toggle_fire_mode(mode: FireMode) -> void:
	if fire_mode == mode:
		_set_fire_mode(_default_fire_mode(selected))
		return
	if state != State.PLAYER_TURN or not _can_use_mode(selected, mode):
		return
	_set_fire_mode(mode)
	Sfx.play("select", -3.0, 0.0)


func _set_fire_mode(mode: FireMode) -> void:
	if fire_mode == mode:
		return
	fire_mode = mode
	board.set_fire_mode(mode)
	_sync_fire_buttons()
	_update_unit_panel()


func _sync_fire_buttons() -> void:
	burst_button.set_pressed_no_signal(fire_mode == FireMode.BURST)
	auto_button.set_pressed_no_signal(fire_mode == FireMode.AUTO)
	suppress_button.set_pressed_no_signal(fire_mode == FireMode.SUPPRESS)


func _on_fire_button_toggled(pressed: bool, mode: FireMode) -> void:
	if pressed:
		_toggle_fire_mode(mode)
	elif fire_mode == mode:
		_set_fire_mode(_default_fire_mode(selected))
	_sync_fire_buttons()  # the request may have been refused


## Select the next living scout that can still act, wrapping in spawn order.
func _cycle_unit() -> void:
	var ready: Array[Unit] = []
	for scout in living_units(Unit.TEAM_SCOUT):
		if not scout.acted:
			ready.append(scout)
	if ready.is_empty():
		return
	select(ready[(ready.find(selected) + 1) % ready.size()])


## Bottom-left stat readout: hovered unit wins over the selected one.
func _update_unit_panel() -> void:
	var unit := unit_at(hover_cell) if hover_cell != Board.NO_CELL else null
	if unit == null:
		unit = selected
	if unit == null:
		unit_panel.visible = false
		return
	unit_panel.visible = true
	panel_name_label.text = unit.display_name()
	panel_hp_label.text = "HP %d / %d" % [unit.hp, unit.max_hp]
	panel_stats_label.text = "Move %d  Rng %d  Dmg %d  Acc %d%%%s" % [
			unit.move_range, unit.attack_range, unit.damage, unit.accuracy,
			"  Ammo %d/%d" % [unit.ammo, unit.mag_size] if unit.mag_size > 0 else ""]
	if aim_mode != AimMode.NONE and unit == selected:
		panel_status_label.text = "AIMING ARC" if aim_mode == AimMode.OVERWATCH \
				else "PICK A FACING"
		panel_status_label.modulate = Color("ffb84a")
		return
	# Hovering a shootable enemy: show what the shot would actually do.
	if unit.team == Unit.TEAM_GOBLIN and selected != null \
			and board.attack_cells.has(unit.cell):
		if fire_mode == FireMode.SUPPRESS:
			panel_status_label.text = "x%d SUPPRESS - NO DAMAGE, PINS AREA" % SUPPRESS_ROUNDS
			panel_status_label.modulate = Unit.SUPPRESSED_COLOR
			return
		var flanking := _is_flanking(selected, unit)
		var dmg := selected.damage
		var note := ""
		if flanking:
			note = "FLANK"
		elif board.shot_through_cover(selected.cell, unit.cell):
			dmg >>= 1
			note = "THROUGH COVER"
		var rounds := _rounds_for(fire_mode)
		var mod: int = AUTO_ACCURACY if fire_mode == FireMode.AUTO else 0
		if rounds > 1:
			var label := "AUTO" if fire_mode == FireMode.AUTO else "BURST"
			note = "x%d %s" % [rounds, label] if note == "" \
					else "x%d %s - %s" % [rounds, label, note]
		panel_status_label.text = "%d%% TO HIT - %d DMG%s" % [
				hit_chance(selected, unit, mod), dmg,
				"  " + note if note != "" else ""]
		panel_status_label.modulate = Color("7ae8ff") if flanking else Color.WHITE
		return
	if unit == selected and fire_mode != FireMode.SINGLE:
		match fire_mode:
			FireMode.AUTO:
				panel_status_label.text = "FULL AUTO ARMED"
				panel_status_label.modulate = Color("ff7a2a")
			FireMode.SUPPRESS:
				panel_status_label.text = "SUPPRESSIVE FIRE ARMED"
				panel_status_label.modulate = Unit.SUPPRESSED_COLOR
			_:
				panel_status_label.text = "BURST ARMED"
				panel_status_label.modulate = Color("ff7a2a")
		return
	if unit.is_suppressed():
		panel_status_label.text = "SUPPRESSED"
		panel_status_label.modulate = Unit.SUPPRESSED_COLOR
		return
	if unit.mag_size > 0 and unit.ammo == 0:
		panel_status_label.text = "OUT OF AMMO - RELOAD (R)"
		panel_status_label.modulate = Color("ff5a3c")
		return
	panel_status_label.text = _unit_status(unit)
	panel_status_label.modulate = Color("ffb84a") if unit.overwatching else Color.WHITE


func _unit_status(unit: Unit) -> String:
	if unit.overwatching:
		return "OVERWATCH"
	if unit.acted:
		return "Done"
	if unit.moved:
		return "Moved"
	return "Ready"


## Refill the selected scout's magazine. Costs the move, not the shot, so a
## dry scout can reload and still fire once - running out costs mobility,
## never a whole turn.
func _try_reload() -> void:
	if state != State.PLAYER_TURN or selected == null:
		return
	if selected.mag_size == 0 or selected.moved or selected.acted \
			or selected.ammo == selected.mag_size:
		return
	var scout := selected
	var prev_state := state
	state = State.ANIMATING
	scout.moved = true  # reloading costs the move, not the shot
	_set_fire_mode(_default_fire_mode(selected))
	board.clear_highlights()
	Sfx.play("reload")
	print("[ThinShot] scout at %s reloads" % scout.cell)
	await scout.play_reload()
	scout.reload()  # magazine seats as the animation lands
	state = prev_state
	if state == State.PLAYER_TURN:
		_refresh_highlights()
		_update_unit_panel()


## Enter overwatch-aiming: the player picks which way the scout watches.
## Clicking a cell commits the arc; cancel/right-click backs out.
func _try_overwatch() -> void:
	if aim_mode == AimMode.OVERWATCH:
		_cancel_aim()
		return
	if state != State.PLAYER_TURN or selected == null or selected.acted \
			or not selected.has_ammo() or selected.is_suppressed():
		return
	aim_mode = AimMode.OVERWATCH
	_sync_aim_buttons()
	_set_fire_mode(_default_fire_mode(selected))
	board.clear_highlights()
	show_banner("CHOOSE OVERWATCH ARC")
	_update_hover(board.global_to_cell(get_global_mouse_position()))


## Enter free-turn aiming. Turning costs nothing and can be done any number
## of times, including after the unit has moved, shot, or gone on overwatch -
## what it buys is choosing which way you face for the enemy turn.
func _try_face() -> void:
	if aim_mode == AimMode.FACE:
		_cancel_aim()
		return
	if state != State.PLAYER_TURN or selected == null:
		return
	aim_mode = AimMode.FACE
	_sync_aim_buttons()
	_set_fire_mode(_default_fire_mode(selected))
	board.clear_highlights()
	show_banner("TURN TO FACE")
	_update_hover(board.global_to_cell(get_global_mouse_position()))


func _on_aim_button_toggled(pressed: bool, mode: AimMode) -> void:
	if pressed:
		if mode == AimMode.OVERWATCH:
			_try_overwatch()
		else:
			_try_face()
	elif aim_mode == mode:
		_cancel_aim()
	_sync_aim_buttons()  # the request may have been refused


## Keep the two mode buttons showing the real aim state.
func _sync_aim_buttons() -> void:
	overwatch_button.set_pressed_no_signal(aim_mode == AimMode.OVERWATCH)
	face_button.set_pressed_no_signal(aim_mode == AimMode.FACE)


func _cancel_aim() -> void:
	if aim_mode == AimMode.NONE:
		return
	_clear_aim_mode()
	_refresh_highlights()


## Commit the direction picked in whichever aim mode is active.
func _commit_aim(cell: Vector2i) -> void:
	var unit := selected
	var sector := Board.sector_from_to(unit.cell, cell)
	var mode := aim_mode
	aim_mode = AimMode.NONE
	_sync_aim_buttons()
	unit.arc_preview_sector = -1
	unit.set_facing_sector(sector)
	if mode == AimMode.FACE:
		# Free: the unit keeps whatever activation it had left.
		Sfx.play("select", -6.0, 0.0)
		print("[ThinShot] scout at %s turns to sector %d" % [unit.cell, sector])
		_refresh_watch_cells()
		_refresh_highlights()
		return
	deselect()
	unit.set_done(true)
	unit.set_overwatch(true)
	Sfx.play("overwatch_set", 0.0, 0.0)
	_refresh_watch_cells()
	print("[ThinShot] scout at %s watches sector %d" % [unit.cell, sector])


## Cells an overwatching unit would cover: in range, in arc, with LOS.
func _overwatch_cells_for(unit: Unit, sector: int) -> Dictionary:
	var cells := {}
	var r := unit.attack_range
	for dy in range(-r, r + 1):
		var w := r - absi(dy)
		for dx in range(-w, w + 1):
			var cell: Vector2i = unit.cell + Vector2i(dx, dy)
			if cell == unit.cell or not board.in_bounds(cell) or not board.is_walkable(cell):
				continue
			var to_cell := Board.sector_from_to(unit.cell, cell)
			if absi(wrapi(to_cell - sector + 4, 0, 8) - 4) > unit.arc_half:
				continue
			if board.has_line_of_sight(unit.cell, cell):
				cells[cell] = true
	return cells


## Every overwatch arc on the board: hostile arcs (amber) are threats to
## route around, friendly arcs (green) are the ground you have covered.
## Hostile wins where they overlap.
func _refresh_watch_cells() -> void:
	var cells := {}
	for team: int in [Unit.TEAM_SCOUT, Unit.TEAM_GOBLIN]:
		var hostile: bool = team == Unit.TEAM_GOBLIN
		for unit in living_units(team):
			if not unit.overwatching:
				continue
			for cell: Vector2i in _overwatch_cells_for(unit, unit.facing_sector):
				if hostile or not cells.has(cell):
					cells[cell] = hostile
	board.set_watch_cells(cells)


func _refresh_highlights() -> void:
	if selected == null:
		board.clear_highlights()
		return
	var moves := {}
	if not selected.moved:
		moves = board.flood_fill(selected.cell, selected.move_range,
				_blocked_for_team.bind(selected.team))
	var attacks: Array[Vector2i] = []
	if not selected.acted and selected.has_ammo():
		for enemy in living_units(Unit.TEAM_GOBLIN):
			if Board.manhattan(selected.cell, enemy.cell) <= selected.attack_range \
					and board.has_line_of_sight(selected.cell, enemy.cell):
				attacks.append(enemy.cell)
	# Even with no moves or targets, the unit stays selected: overwatch (W)
	# is always a legal order for a unit that has not attacked.
	board.set_highlights(moves, _free_dests(moves), attacks)
	_update_hover(board.global_to_cell(get_global_mouse_position()))


## Derives hover feedback (tile outline, path preview, aim line) from the
## current selection and pushes it to the Board for rendering.
func _update_hover(cell: Vector2i) -> void:
	if not board.in_bounds(cell):
		cell = Board.NO_CELL
	hover_cell = cell
	# Aiming an overwatch arc: the cursor steers the cone, nothing else.
	if aim_mode != AimMode.NONE and selected != null:
		var sector := Board.sector_from_to(selected.cell, cell) if cell != Board.NO_CELL else -1
		if sector != selected.arc_preview_sector:
			selected.arc_preview_sector = sector
			selected.queue_redraw()
			var cone := {}
			if sector >= 0:
				for watched: Vector2i in _overwatch_cells_for(selected, sector):
					cone[watched] = false  # ally-colored preview
			board.set_watch_cells(cone)
		board.set_hover(cell, [], Board.NO_CELL)
		_update_unit_panel()
		return
	var path: Array[Vector2i] = []
	var aim_from := Board.NO_CELL
	var aim_covered := false
	var aim_flanking := false
	if selected != null and cell != Board.NO_CELL:
		if board.move_dests.has(cell):
			path = board.reconstruct_path(board.move_cells, cell)
		elif board.attack_cells.has(cell):
			var target := unit_at(cell)
			aim_from = selected.cell
			aim_flanking = target != null and _is_flanking(selected, target)
			aim_covered = not aim_flanking \
					and board.shot_through_cover(selected.cell, cell)
	board.set_hover(cell, path, aim_from, aim_covered, aim_flanking)
	_update_unit_panel()


# --- Actions (shared by player and AI) ---------------------------------------

func do_move(unit: Unit, dest: Vector2i) -> void:
	var prev_state := state
	state = State.ANIMATING
	board.clear_highlights()
	var came_from := board.flood_fill(unit.cell, unit.move_range,
			_blocked_for_team.bind(unit.team))
	if not came_from.has(dest) or unit_at(dest) != null:
		state = prev_state
		return
	var path := board.reconstruct_path(came_from, dest)
	unit.start_walking()
	var from_pos := unit.position
	for step_index in path.size():
		var step: Vector2i = path[step_index]
		var step_pos := board.cell_to_global(step)
		unit.set_facing(step_pos - from_pos)
		var tween := create_tween()
		tween.tween_property(unit, "position", step_pos, MOVE_STEP_TIME)
		await tween.finished
		Sfx.play("footstep_1" if step_index % 2 == 0 else "footstep_2")
		fx_ground.footstep(step_pos)
		unit.cell = step
		from_pos = step_pos
		var watchers := _overwatchers_against(unit)
		if not watchers.is_empty():
			unit.stop_walking()
			for watcher in watchers:
				if not unit.is_alive():
					break
				watcher.set_overwatch(false)  # consumed, even if the shot kills
				print("[ThinShot]   overwatch! %s fires at %s" % [watcher.cell, unit.cell])
				await _resolve_shot(watcher, unit, false)
			if not unit.is_alive() or state == State.GAME_OVER:
				if selected == unit:
					deselect()
				if state != State.GAME_OVER:
					state = prev_state
					if prev_state == State.PLAYER_TURN:
						_refresh_danger()
						_update_unit_panel()
				return
			unit.start_walking()
	unit.stop_walking()
	unit.moved = true
	state = prev_state
	if prev_state == State.PLAYER_TURN:
		_refresh_danger()
		_refresh_watch_cells()
		_update_unit_panel()
		if selected == unit:
			_refresh_highlights()


func do_attack(attacker: Unit, target: Unit) -> void:
	var prev_state := state
	state = State.ANIMATING
	board.clear_highlights()
	await _resolve_shot(attacker, target, true)
	attacker.set_done(true)
	if attacker == selected:
		deselect()
	# A death inside take_damage triggers _on_unit_died -> check_game_over.
	if state == State.GAME_OVER:
		return
	state = prev_state
	if prev_state == State.PLAYER_TURN:
		_refresh_danger()
		_refresh_watch_cells()
		_update_unit_panel()


## Suppressive fire: the machinegunner's ability. Rounds go downrange around
## the target rather than into it - no damage, no hit rolls - and everything
## hostile at or beside the impact point is pinned. Trades killing for
## control: two goblins with their heads down instead of one wounded.
func do_suppressive_fire(attacker: Unit, target: Unit) -> void:
	var prev_state := state
	state = State.ANIMATING
	board.clear_highlights()
	print("[ThinShot] suppressive fire %s -> %s" % [attacker.cell, target.cell])
	var aim := (target.position - attacker.position).normalized()
	attacker.set_facing(aim)
	await attacker.raise_rifle()
	for i in SUPPRESS_ROUNDS:
		if i > 0:
			await get_tree().create_timer(AUTO_GAP).timeout
		await _fire_suppression_round(attacker, target)
	# Pin the target and anything hostile beside it.
	var pinned: Array[Vector2i] = []
	for unit in living_units(_enemy_team_of(attacker)):
		if Board.manhattan(unit.cell, target.cell) <= 1:
			unit.suppress()
			pinned.append(unit.cell)
	print("[ThinShot]   pinned %s" % [pinned])
	await get_tree().create_timer(LOWER_TIME).timeout
	attacker.lower_rifle()
	attacker.set_done(true)
	if attacker == selected:
		deselect()
	state = prev_state
	if prev_state == State.PLAYER_TURN:
		_refresh_danger()
		_refresh_watch_cells()
		_update_unit_panel()


func _enemy_team_of(unit: Unit) -> int:
	return Unit.TEAM_GOBLIN if unit.team == Unit.TEAM_SCOUT else Unit.TEAM_SCOUT


## One round of suppressing fire: full muzzle presentation, but the round
## deliberately strikes the ground around the target instead of the target.
func _fire_suppression_round(attacker: Unit, target: Unit) -> void:
	var muzzle := attacker.muzzle_point()
	var chest := target.position + Vector2(0, -36)
	var dir := (chest - muzzle).normalized()
	var splash := chest + dir * _rng.randf_range(10.0, 40.0) \
			+ dir.orthogonal() * _rng.randf_range(-30.0, 30.0)
	attacker.spend_ammo()
	attacker.recoil(dir)
	Sfx.play("shot")
	HitFx.spawn(fx_glow, muzzle, HitFx.Kind.MUZZLE)
	HitFx.spawn_tracer(fx_glow, muzzle, splash, TRACER_TIME)
	fx_glow.muzzle(muzzle, dir)
	fx_air.smoke_plume(muzzle, dir)
	fx_ground.casing(muzzle, dir)
	_camera_kick(dir)
	await get_tree().create_timer(TRACER_TIME).timeout
	Sfx.play("miss")
	var strike := splash + Vector2(0, 26)
	fx_ground.footstep(strike, 1.4)
	fx_ground.bullet_hole(strike, dir)
	_screen_shake(0.6)


## The shot itself: face, (optionally) raise the rifle via the transition
## animation, fire one round, lower. Reaction shots skip the raise -
## the rifle is already up from overwatch.
func _resolve_shot(attacker: Unit, target: Unit, with_aim_beat: bool) -> void:
	var aim := (target.position - attacker.position).normalized()
	attacker.set_facing(aim)
	if with_aim_beat:
		await attacker.raise_rifle()
	await _fire_round(attacker, target)
	await get_tree().create_timer(LOWER_TIME).timeout
	attacker.lower_rifle()


## One round leaving the muzzle: effects, sound, cover-checked damage.
## Assumes the attacker is already facing the target with rifle raised.
func _fire_round(attacker: Unit, target: Unit, accuracy_mod := 0) -> void:
	var muzzle := attacker.muzzle_point()
	var chest := target.position + Vector2(0, -36)
	var dir := (chest - muzzle).normalized()
	var covered_cell := board.cover_cell_between(attacker.cell, target.cell)
	var flanking := _is_flanking(attacker, target)
	var chance := hit_chance(attacker, target, accuracy_mod)
	var hit := _rng.randi_range(1, 100) <= chance
	# A miss sails past the target and off to one side.
	var impact_point := chest if hit else chest + dir * 54.0 \
			+ dir.orthogonal() * _rng.randf_range(-34.0, 34.0)

	attacker.spend_ammo()
	attacker.recoil(dir)
	Sfx.play("shot")
	HitFx.spawn(fx_glow, muzzle, HitFx.Kind.MUZZLE)
	HitFx.spawn_tracer(fx_glow, muzzle, impact_point, TRACER_TIME)
	fx_glow.muzzle(muzzle, dir)
	fx_air.smoke_plume(muzzle, dir)  # non-additive layer so smoke reads as smoke
	fx_ground.footstep(attacker.position, 0.5)  # blast dust at the shooter's feet
	fx_ground.casing(muzzle, dir)
	_camera_kick(dir)

	# Sparks off the junk pile the round clips, timed to when it passes.
	if covered_cell != Board.NO_CELL:
		var travel := Vector2(target.cell - attacker.cell).length()
		var f: float = Vector2(covered_cell - attacker.cell).length() / maxf(travel, 0.001)
		_spark_cover(covered_cell, dir, TRACER_TIME * f)

	await get_tree().create_timer(TRACER_TIME).timeout

	if not hit:
		print("[ThinShot]   %s -> %s MISSES (%d%%)" % [
				attacker.cell, target.cell, chance])
		Sfx.play("miss")
		var strike := impact_point + Vector2(0, 30)
		fx_ground.footstep(strike, 1.2)  # dust where it lands
		fx_ground.bullet_hole(strike, dir)
		target.spawn_miss_text()
		_update_unit_panel()
		return

	var dmg := attacker.damage
	if not flanking and covered_cell != Board.NO_CELL:
		dmg >>= 1
		print("[ThinShot]   shot %s -> %s clips cover: %d dmg (%d%%)" % [
				attacker.cell, target.cell, dmg, chance])
	elif flanking:
		print("[ThinShot]   flanking shot %s -> %s: %d dmg (%d%%)" % [
				attacker.cell, target.cell, dmg, chance])
	var lethal := target.hp - dmg <= 0

	Sfx.play("hit_impact")
	HitFx.spawn(fx_glow, chest, HitFx.Kind.IMPACT)
	fx_air.impact(chest, dir, lethal)
	fx_air.blood_mist(chest, dir, lethal)
	fx_ground.blood_spray(chest, target.position.y, dir, lethal)
	_screen_shake(1.6 if lethal else 1.0)
	target.take_damage(dmg, dir)
	# A hit from outside the front arc knocks the target off overwatch.
	if flanking and target.is_alive() and target.overwatching:
		target.set_overwatch(false)
		target.lower_rifle()
	_update_unit_panel()  # keep hovered-unit HP live even during enemy fire
	await _hit_stop(0.09 if lethal else 0.14, 0.075 if lethal else 0.045)


## Percent chance this shot connects. Cover is deliberately NOT an accuracy
## modifier - it already halves damage, and keeping the two rules separate
## keeps both readable. Flanking helps; so does not taking a long shot.
func hit_chance(attacker: Unit, target: Unit, accuracy_mod := 0) -> int:
	var chance := attacker.accuracy + accuracy_mod
	if attacker.is_suppressed():
		chance -= SUPPRESSION_ACCURACY
	if _is_flanking(attacker, target):
		chance += FLANK_ACCURACY
	var dist := Board.manhattan(attacker.cell, target.cell)
	var comfortable: int = attacker.attack_range / 2
	if dist > comfortable:
		chance -= (dist - comfortable) * LONG_SHOT_PENALTY
	return clampi(chance, 20, 99)


## Fire-and-forget spark on the junk cell the round passes through.
func _spark_cover(cell: Vector2i, dir: Vector2, delay: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if not is_instance_valid(fx_glow):
		return
	var at := board.cell_to_global(cell)
	fx_glow.cover_spark(at + Vector2(0, -20), dir)
	fx_ground.bullet_hole(at + Vector2(_rng.randf_range(-14, 14), 0), dir, true)


## A multi-round volley. Each round is cover- and accuracy-checked on its
## own; the volley stops early if the target drops. Full auto walks the gun
## across the target, trading accuracy per round for volume, and pins
## whoever it was aimed at whether or not the rounds connect.
func do_volley(attacker: Unit, target: Unit, rounds: int, gap: float,
		accuracy_mod: int) -> void:
	var prev_state := state
	state = State.ANIMATING
	board.clear_highlights()
	print("[ThinShot] %d-round volley %s -> %s" % [rounds, attacker.cell, target.cell])
	var aim := (target.position - attacker.position).normalized()
	attacker.set_facing(aim)
	await attacker.raise_rifle()
	for i in rounds:
		if i > 0:
			await get_tree().create_timer(gap).timeout
		await _fire_round(attacker, target, accuracy_mod)
		if not target.is_alive() or state == State.GAME_OVER \
				or not attacker.has_ammo():
			break
	await get_tree().create_timer(LOWER_TIME).timeout
	attacker.lower_rifle()
	attacker.set_done(true)
	if attacker == selected:
		deselect()
	if state == State.GAME_OVER:
		return
	state = prev_state
	if prev_state == State.PLAYER_TURN:
		_refresh_danger()
		_refresh_watch_cells()
		_update_unit_panel()


# --- Danger overlay ----------------------------------------------------------

## Every tile some living goblin could shoot next turn: reachable move cells
## (plus standing still) expanded by attack range with line of sight.
## Projected with the same rule the goblins actually move under, so the
## overlay cannot promise safety that the enemy turn then breaks. Occupied
## cells are left in as firing origins on purpose - goblins act one at a
## time and vacate them for each other, so over-warning is the safe error.
func _compute_danger_cells() -> Dictionary:
	var danger := {}
	for goblin in living_units(Unit.TEAM_GOBLIN):
		var origins: Array = board.flood_fill(goblin.cell, goblin.move_range,
				_blocked_for_team.bind(goblin.team)).keys()
		origins.append(goblin.cell)
		var r := goblin.attack_range
		for origin: Vector2i in origins:
			for dy in range(-r, r + 1):
				var w := r - absi(dy)
				for dx in range(-w, w + 1):
					var tile := origin + Vector2i(dx, dy)
					if danger.has(tile) or not board.in_bounds(tile) \
							or not board.is_walkable(tile):
						continue
					if board.has_line_of_sight(origin, tile):
						danger[tile] = true
	return danger


func _refresh_danger() -> void:
	board.set_danger(_compute_danger_cells() if danger_on else {})


func _toggle_danger() -> void:
	danger_on = not danger_on
	danger_button.set_pressed_no_signal(danger_on)
	_refresh_danger()


func _on_danger_button_toggled(pressed: bool) -> void:
	danger_on = pressed
	_refresh_danger()


## True if the shot comes from outside the target's front arc, in which case
## cover does not protect it. Derived from cells, never live positions, so
## the hover preview and the resolved shot always agree.
func _is_flanking(attacker: Unit, target: Unit) -> bool:
	return not target.covers_sector(Board.sector_from_to(target.cell, attacker.cell))


## Living enemies of the mover that are on overwatch with range, LOS, and
## the mover inside their covered arc.
func _overwatchers_against(mover: Unit) -> Array[Unit]:
	var result: Array[Unit] = []
	for child in entities_node.get_children():
		var watcher := child as Unit
		if watcher == null or not watcher.is_alive() or not watcher.overwatching:
			continue
		if watcher.team == mover.team or not watcher.has_ammo():
			continue
		if Board.manhattan(watcher.cell, mover.cell) <= watcher.attack_range \
				and watcher.covers_sector(Board.sector_from_to(watcher.cell, mover.cell)) \
				and board.has_line_of_sight(watcher.cell, mover.cell):
			result.append(watcher)
	return result


# --- Turn flow ---------------------------------------------------------------

func end_player_turn() -> void:
	if state != State.PLAYER_TURN or enemy_turn_running:
		return
	if Time.get_ticks_msec() - player_turn_ready_msec < END_TURN_GRACE_MS:
		return
	enemy_turn_running = true
	deselect()
	board.set_danger({})
	state = State.ENEMY_TURN
	print("[ThinShot] enemy turn %d begins" % turn_number)
	Sfx.play("turn_enemy", 0.0, 0.0)
	show_banner("RUST CHOIR'S TURN")
	end_turn_button.disabled = true
	overwatch_button.disabled = true
	burst_button.disabled = true
	auto_button.disabled = true
	suppress_button.disabled = true
	reload_button.disabled = true
	face_button.disabled = true
	danger_button.disabled = true
	# Goblins refresh at the start of THEIR turn (expires last turn's
	# unfired goblin overwatch at the right moment).
	for goblin in living_units(Unit.TEAM_GOBLIN):
		goblin.start_turn()
	await run_enemy_turn()
	enemy_turn_running = false
	if state == State.GAME_OVER:
		return
	# Scouts refresh for the new player turn (expiring unfired overwatch);
	# goblins just undim so they don't look pre-acted - but keep any
	# overwatch stance they set up, since it stays armed through this turn.
	for unit in living_units(Unit.TEAM_SCOUT):
		unit.start_turn()
	for goblin in living_units(Unit.TEAM_GOBLIN):
		goblin.set_done(false)
	turn_number += 1
	print("[ThinShot] player turn %d begins" % turn_number)
	Sfx.play("turn_player", 0.0, 0.0)
	end_turn_button.disabled = false
	overwatch_button.disabled = false
	burst_button.disabled = false
	auto_button.disabled = false
	suppress_button.disabled = false
	reload_button.disabled = false
	face_button.disabled = false
	danger_button.disabled = false
	show_banner("DESERT SCOUTS' TURN")
	state = State.PLAYER_TURN
	player_turn_ready_msec = Time.get_ticks_msec()
	_refresh_danger()
	_refresh_watch_cells()
	_update_unit_panel()


func run_enemy_turn() -> void:
	var squad := living_units(Unit.TEAM_GOBLIN)
	var acted := 0
	for goblin in squad:
		if not is_instance_valid(goblin) or not goblin.is_alive():
			continue
		var scouts := living_units(Unit.TEAM_SCOUT)
		if scouts.is_empty():
			return
		acted += 1
		var from_cell := goblin.cell
		# Mark the actor and give the player a beat to find it before it
		# moves. The beat is taken out of AI_BEAT, so turns stay the same
		# length - the player's eye just arrives before the motion.
		goblin.set_selected(true)
		goblin.set_acting(true)
		await get_tree().create_timer(ACT_LEAD_IN).timeout
		# An empty weapon is worked before anything else is decided, and costs
		# the move - the same rule the scouts reload under.
		var reloaded := await _ai_reload(goblin, acted, squad.size())
		var shootable := _shootable_from(goblin.cell, goblin.attack_range, scouts)
		if goblin.has_ammo() and not shootable.is_empty():
			print("[ThinShot]   goblin %d/%d shoots from %s" % [acted, squad.size(), from_cell])
			await _ai_fire(goblin, _nearest(goblin.cell, shootable))
		else:
			var moved_now := false
			if not reloaded:  # working the bolt already spent the move
				var target := _nearest(goblin.cell, scouts)
				var reach := board.flood_fill(goblin.cell, goblin.move_range,
						_blocked_for_team.bind(goblin.team))
				var dest := _best_ai_dest(goblin, reach, scouts, target.cell)
				moved_now = board.in_bounds(dest) and dest != goblin.cell
				if moved_now:
					await do_move(goblin, dest)
			shootable = _shootable_from(goblin.cell, goblin.attack_range, living_units(Unit.TEAM_SCOUT))
			var shoots := goblin.is_alive() and goblin.has_ammo() and not shootable.is_empty()
			print("[ThinShot]   goblin %d/%d %s %s -> %s%s" % [
					acted, squad.size(), "reloads at" if reloaded else "moves",
					from_cell, goblin.cell, ", shoots" if shoots else ""])
			if shoots:
				await _ai_fire(goblin, _nearest(goblin.cell, shootable))
			elif not moved_now and goblin.is_alive() and not goblin.is_suppressed() \
					and goblin.has_ammo():
				# Dug in with no shot: watch the lane the scouts must cross. A
				# pinned goblin keeps its head down instead, and a dry one has
				# nothing to react with.
				goblin.set_facing_sector(_best_watch_sector(goblin, scouts))
				goblin.set_overwatch(true)
				Sfx.play("overwatch_set", -4.0, 0.0)
				print("[ThinShot]   goblin %d/%d holds %s on overwatch" % [
						acted, squad.size(), goblin.cell])
		goblin.set_selected(false)
		goblin.set_acting(false)
		if state == State.GAME_OVER:
			return
		await get_tree().create_timer(AI_BEAT).timeout


## Works a dry AI weapon. Costs the move rather than the shot, mirroring
## _try_reload, so a unit that reloads can still fire the same turn but cannot
## reposition - which is the whole shape of the bolt-action marksman: he holds
## his ground for exactly as long as he keeps shooting. Returns whether a
## reload happened, since that is what spends the move.
func _ai_reload(goblin: Unit, index: int, squad_size: int) -> bool:
	if not goblin.needs_reload():
		return false
	goblin.moved = true
	Sfx.play("reload")
	print("[ThinShot]   goblin %d/%d reloads at %s" % [index, squad_size, goblin.cell])
	await goblin.play_reload()
	goblin.reload()  # magazine seats as the animation lands
	return true


## AI units shoot with the heaviest setting their weapon allows, so a raider
## empties a burst instead of squeezing off one round like a rifleman.
func _ai_fire(attacker: Unit, target: Unit) -> void:
	if _can_use_mode(attacker, FireMode.BURST):
		await do_volley(attacker, target, BURST_ROUNDS, BURST_GAP, 0)
	else:
		await do_attack(attacker, target)


func _shootable_from(from_cell: Vector2i, attack_range: int, targets: Array[Unit]) -> Array[Unit]:
	var result: Array[Unit] = []
	for unit in targets:
		if Board.manhattan(from_cell, unit.cell) <= attack_range \
				and board.has_line_of_sight(from_cell, unit.cell):
			result.append(unit)
	return result


func _nearest(from_cell: Vector2i, candidates: Array[Unit]) -> Unit:
	var best: Unit = candidates[0]
	for unit in candidates:
		if Board.manhattan(from_cell, unit.cell) < Board.manhattan(from_cell, best.cell):
			best = unit
	return best


## How exposed a cell is to scout fire: 2 per clean firing line, 1 per line
## that has to cross junk (those shots only land for half damage). This is
## what makes the goblins actually value the cover on the map.
func _exposure_at(cell: Vector2i, scouts: Array[Unit]) -> int:
	var score := 0
	for scout in scouts:
		if Board.manhattan(cell, scout.cell) <= scout.attack_range \
				and board.has_line_of_sight(scout.cell, cell):
			score += 1 if board.shot_through_cover(scout.cell, cell) else 2
	return score


## Best move destination for an AI unit. A cell it can shoot a scout from
## beats every cell it can't; exposure to scout fire costs a little when
## healthy and a lot when wounded (so 1 HP goblins with no shot retreat to
## cover); nearer the chase target breaks remaining ties.
## `reach` is the flood_fill result (cell -> predecessor), which also tells us
## which way the goblin would be facing when it arrives.
func _best_ai_dest(goblin: Unit, reach: Dictionary, scouts: Array[Unit],
		chase_cell: Vector2i) -> Vector2i:
	var exposure_weight := 25 if goblin.hp <= 2 else 2
	# Reachable cells include squadmates' tiles, which can be crossed but
	# not occupied; standing still is always an option.
	var candidates: Array = _free_dests(reach).keys()
	candidates.append(goblin.cell)
	var best := Vector2i(-1, -1)
	var best_score := 999999
	for cell: Vector2i in candidates:
		var score := Board.manhattan(cell, chase_cell)
		score += exposure_weight * _exposure_at(cell, scouts)
		var shots := _shootable_from(cell, goblin.attack_range, scouts)
		var end_sector := -1
		if not shots.is_empty():
			var mark := _nearest(cell, shots)
			end_sector = Board.sector_from_to(cell, mark.cell)
			score -= 1000
			# A clean firing position beats one that only has covered shots.
			if board.shot_through_cover(cell, mark.cell):
				score += 400
			# Shooting someone in the back bypasses their cover.
			if not mark.covers_sector(Board.sector_from_to(mark.cell, cell)):
				score -= 60
		elif reach.has(cell):
			end_sector = Board.sector_from_to(reach[cell], cell)
		# Do not turn your back on the rest of the squad.
		if end_sector >= 0:
			for scout in scouts:
				if Board.manhattan(cell, scout.cell) <= scout.attack_range \
						and board.has_line_of_sight(scout.cell, cell) \
						and absi(wrapi(Board.sector_from_to(cell, scout.cell)
								- end_sector + 4, 0, 8) - 4) > goblin.arc_half:
					score += 6
		if score < best_score:
			best_score = score
			best = cell
	return best


## Which way a dug-in goblin should watch: the arc covering the most cells
## the scouts could advance through. Integer scoring keeps ties deterministic.
func _best_watch_sector(goblin: Unit, scouts: Array[Unit]) -> int:
	var approach := {}
	for scout in scouts:
		approach.merge(board.flood_fill(scout.cell, scout.move_range,
				_blocked_for_team.bind(scout.team)))
		approach[scout.cell] = true
	var best_sector := goblin.facing_sector
	var best_count := -1
	for sector in 8:
		var count := 0
		for cell: Vector2i in _overwatch_cells_for(goblin, sector):
			if approach.has(cell):
				count += 1
		if count > best_count:
			best_count = count
			best_sector = sector
	return best_sector


# --- Win / lose --------------------------------------------------------------

func _on_unit_died(unit: Unit) -> void:
	Sfx.play("unit_death")
	fx_ground.stain(unit.position)
	_puff_on_landing(unit)
	check_game_over()


## Dust kicked up when the falling body actually hits the ground, rather
## than when it starts to fall.
func _puff_on_landing(unit: Unit) -> void:
	await get_tree().create_timer(unit.death_landing_time()).timeout
	if is_instance_valid(fx_ground) and is_instance_valid(unit):
		fx_ground.death_puff(unit.position)


func check_game_over() -> bool:
	if state == State.GAME_OVER:
		return true
	if living_units(Unit.TEAM_GOBLIN).is_empty():
		_show_game_over("DESERT SCOUTS WIN", true)
		return true
	if living_units(Unit.TEAM_SCOUT).is_empty():
		_show_game_over("THE CHOIR SINGS ON", false)
		return true
	return false


func _show_game_over(text: String, won: bool) -> void:
	state = State.GAME_OVER
	last_result_won = won
	if won and Game.is_last_level():
		text = "CAMPAIGN COMPLETE - THE WASTES FALL SILENT"
	result_label.text = text
	if not won:
		restart_button.text = "Retry"
	elif Game.is_last_level():
		restart_button.text = "Play Again"
	else:
		restart_button.text = "Next Level"
	game_over_panel.visible = true
	Sfx.play("win" if won else "lose", 0.0, 0.0)


func _on_restart() -> void:
	Engine.time_scale = 1.0  # never carry a hit-stop across a reload
	if last_result_won:
		Game.select_level(0 if Game.is_last_level() else Game.current_level + 1)
	get_tree().reload_current_scene()


func _go_to_level(index: int) -> void:
	Engine.time_scale = 1.0
	Game.select_level(index)
	get_tree().reload_current_scene()


# Fixed offsets keep the shake deterministic and always settle back to zero.
const SHAKE_OFFSETS: Array[Vector2] = [
	Vector2(4, -2), Vector2(-4, 2), Vector2(3, 1), Vector2(-2, -1), Vector2.ZERO,
]


## Camera offset is composited from independent channels so a recoil kick and
## an impact shake can overlap (a burst fires two shots 0.13s apart) without
## fighting each other over the same property.
func _process(_delta: float) -> void:
	camera.offset = _cam_lean + _cam_shake
	_sway_plants()
	_animate_structures()


## Advance the huts' and outpost's breeze loops.
func _animate_structures() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for entry: Dictionary in _animated_props:
		var frames: Array = entry.frames
		var idx: int = int((t + entry.phase) * STRUCTURE_FPS) % frames.size()
		if idx != entry.frame:
			entry.frame = idx
			entry.sprite.texture = frames[idx]


## Cacti lean in the wind. The offset snaps to whole sprite texels (the props
## draw at 2x) so the pixel art never shimmers between subpixel positions.
func _sway_plants() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for entry: Dictionary in _swaying:
		var wave: float = sin(t * SWAY_SPEED + entry.phase)
		var step: float = SWAY_TEXELS * ROCK_SCALE.x * signf(wave) \
				* (1.0 if absf(wave) > 0.45 else 0.0)
		entry.sprite.position.x = entry.base_x + step


func _screen_shake(strength := 1.0) -> void:
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	var gain := strength / maxf(base_zoom.x, 0.01)
	_shake_tween = create_tween()
	for off in SHAKE_OFFSETS:
		_shake_tween.tween_property(self, "_cam_shake", off * gain, 0.03)


## A snap away from the shot direction that eases back - the camera reacts to
## where the round went instead of doing the same wiggle every time.
func _camera_kick(dir: Vector2) -> void:
	if _kick_tween != null and _kick_tween.is_valid():
		_kick_tween.kill()
	_cam_lean = -dir * 5.0 / maxf(base_zoom.x, 0.01)
	_kick_tween = create_tween()
	_kick_tween.tween_property(self, "_cam_lean", Vector2.ZERO, 0.16) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Brief global slow-motion on impact. The dip is measured in REAL seconds
## (ignore_time_scale), so its length does not depend on `scale`, and the
## restore is bound to the Engine singleton rather than this node so a scene
## reload mid-freeze can never strand the game in slow motion.
## Every caller must await this - that serialization is what keeps overlapping
## hit-stops from stacking.
func _hit_stop(scale: float, real_seconds: float) -> void:
	Engine.time_scale = scale
	var timer := get_tree().create_timer(real_seconds, true, false, true)
	timer.timeout.connect(Engine.set_time_scale.bind(1.0))
	await timer.timeout


func show_banner(text: String) -> void:
	turn_banner.text = text
	turn_banner.modulate.a = 0.0
	turn_banner.pivot_offset = turn_banner.size / 2.0
	turn_banner.scale = Vector2(1.25, 1.25)
	var tween := create_tween()
	tween.tween_property(turn_banner, "modulate:a", 1.0, 0.2)
	tween.parallel().tween_property(turn_banner, "scale", Vector2.ONE, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
