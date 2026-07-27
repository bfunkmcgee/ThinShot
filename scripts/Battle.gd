extends Node2D

## Battle controller: turn state machine, player input, enemy AI, win/lose.

enum State { PLAYER_TURN, ANIMATING, ENEMY_TURN, GAME_OVER }

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
const STRUCTURE_TEXTURES := {
	"hut_1": preload("res://assets/sprites/Environment/Desert/Structures/desert_hut/Desert_hut.png"),
	"hut_2": preload("res://assets/sprites/Environment/Desert/Structures/desert_hut/Desert_hut_1.png"),
	"tent": preload("res://assets/sprites/Environment/Desert/Structures/desert_hut/Desert_hut_2.png"),
	"fortress": preload("res://assets/sprites/Environment/Desert/Structures/Desert_military_building/rotations/unknown.png"),
}

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
const AI_BEAT := 0.25
const LOWER_TIME := 0.12  # rifle held after the shot before lowering
const BURST_GAP := 0.13  # pause between the two rounds of a burst

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
var burst_armed := false
var level: Dictionary = {}
var last_result_won := false

@onready var board: Board = $Board
@onready var camera: Camera2D = $Camera
@onready var entities_node: Node2D = $Entities
@onready var turn_banner: Label = $UI/TurnBanner
@onready var end_turn_button: Button = $UI/EndTurnButton
@onready var overwatch_button: Button = $UI/OverwatchButton
@onready var burst_button: Button = $UI/BurstButton
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
	Levels.validate_all()  # push_error-based, so it reports in release too
	level = Game.data()
	board.set_level(level)
	_fit_camera()
	_validate_spawns()
	_spawn_props()
	for s: Dictionary in level.structures:
		_spawn_structure(s)
	for spawn: Vector2i in level.scout_spawns:
		_spawn_unit(Unit.TEAM_SCOUT, spawn)
	for spawn: Vector2i in level.goblin_spawns:
		_spawn_unit(Unit.TEAM_GOBLIN, spawn)
	end_turn_button.pressed.connect(end_player_turn)
	overwatch_button.pressed.connect(_try_overwatch)
	burst_button.toggled.connect(_on_burst_button_toggled)
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


func _validate_spawns() -> void:
	for spawn: Vector2i in level.scout_spawns + level.goblin_spawns:
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
					_spawn_prop(PLANT_TEXTURES[(x * 5 + y * 23) % PLANT_TEXTURES.size()],
							PLANT_OFFSET, cell)
				"W":
					var kind := _wall_kind(cell)
					_spawn_prop(_wall_texture_for(kind), WALL_OFFSETS[kind], cell)


func _spawn_prop(texture: Texture2D, offset: Vector2, cell: Vector2i) -> void:
	var prop := Sprite2D.new()
	prop.texture = texture
	prop.offset = offset
	prop.scale = ROCK_SCALE
	prop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	prop.position = board.cell_to_global(cell)
	entities_node.add_child(prop)


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


## Multi-tile set-piece: a y-sort root at the footprint's front cell so units
## on nearer rows draw in front, with the sprite centered on the footprint.
func _spawn_structure(s: Dictionary) -> void:
	var anchor: Vector2i = s.anchor
	var struct_size: Vector2i = s.size
	var front: Vector2i = anchor + struct_size - Vector2i.ONE
	var root := Node2D.new()
	root.position = board.cell_to_global(front)
	var spr := Sprite2D.new()
	spr.texture = STRUCTURE_TEXTURES[s.kind]
	spr.scale = Vector2(2, 2)
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.offset = STRUCTURE_OFFSETS[s.kind]
	spr.position = (board.cell_to_global(anchor) + board.cell_to_global(front)) / 2.0 \
			- root.position
	root.add_child(spr)
	entities_node.add_child(root)


func _spawn_unit(team: int, spawn_cell: Vector2i) -> void:
	var unit: Unit = UNIT_SCENE.instantiate()
	entities_node.add_child(unit)
	unit.setup(team, spawn_cell)
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


func _cell_blocked(cell: Vector2i) -> bool:
	return unit_at(cell) != null


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
		_toggle_burst()
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
		deselect()
		return
	var mouse := event as InputEventMouseButton
	if mouse == null or not mouse.pressed:
		return
	if mouse.button_index == MOUSE_BUTTON_RIGHT:
		deselect()
		return
	if mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	var cell := board.global_to_cell(get_global_mouse_position())
	if not board.in_bounds(cell):
		return
	_handle_click(cell)


func _handle_click(cell: Vector2i) -> void:
	var clicked := unit_at(cell)
	if selected != null:
		if clicked != null and clicked.team == Unit.TEAM_GOBLIN \
				and board.attack_cells.has(cell):
			if burst_armed:
				_set_burst_armed(false)
				do_burst(selected, clicked)
			else:
				do_attack(selected, clicked)
			return
		if board.move_cells.has(cell):
			_set_burst_armed(false)  # moving forfeits the braced burst
			do_move(selected, cell)
			return
	if clicked != null and clicked.team == Unit.TEAM_SCOUT and not clicked.acted:
		select(clicked)
	else:
		deselect()


func select(unit: Unit) -> void:
	if selected != null:
		selected.set_selected(false)
	selected = unit
	unit.set_selected(true)
	Sfx.play("select", 0.0, 0.0)
	_refresh_highlights()
	_update_unit_panel()


func deselect() -> void:
	if selected != null:
		selected.set_selected(false)
		selected = null
	_set_burst_armed(false)
	board.clear_highlights()
	_update_unit_panel()


## Arm/disarm burst fire for the selected scout. Eligible only while the
## scout has neither moved nor attacked (a braced, standing volley).
func _toggle_burst() -> void:
	if burst_armed:
		_set_burst_armed(false)
		return
	if state != State.PLAYER_TURN or selected == null:
		return
	if selected.team != Unit.TEAM_SCOUT or selected.moved or selected.acted:
		return
	_set_burst_armed(true)
	Sfx.play("select", -3.0, 0.0)


func _set_burst_armed(value: bool) -> void:
	if burst_armed == value:
		return
	burst_armed = value
	burst_button.set_pressed_no_signal(value)
	board.set_burst_mode(value)
	_update_unit_panel()


func _on_burst_button_toggled(pressed: bool) -> void:
	if pressed:
		_toggle_burst()
		# _toggle_burst may refuse; resync the button to the real state.
		burst_button.set_pressed_no_signal(burst_armed)
	else:
		_set_burst_armed(false)


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
	panel_name_label.text = "Desert Scout" if unit.team == Unit.TEAM_SCOUT \
			else "Rust Choir Chorister"
	panel_hp_label.text = "HP %d / %d" % [unit.hp, unit.max_hp]
	panel_stats_label.text = "Move %d   Range %d   Dmg %d" % [
			unit.move_range, unit.attack_range, unit.damage]
	if unit == selected and burst_armed:
		panel_status_label.text = "BURST ARMED"
		panel_status_label.modulate = Color("ff7a2a")
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


## Put the selected scout on overwatch, consuming its activation.
func _try_overwatch() -> void:
	if state != State.PLAYER_TURN or selected == null or selected.acted:
		return
	var scout := selected
	deselect()
	scout.set_done(true)
	scout.set_overwatch(true)
	Sfx.play("overwatch_set", 0.0, 0.0)
	print("[ThinShot] scout at %s goes on overwatch" % scout.cell)


func _refresh_highlights() -> void:
	if selected == null:
		board.clear_highlights()
		return
	var moves := {}
	if not selected.moved:
		moves = board.flood_fill(selected.cell, selected.move_range, _cell_blocked)
	var attacks: Array[Vector2i] = []
	if not selected.acted:
		for enemy in living_units(Unit.TEAM_GOBLIN):
			if Board.manhattan(selected.cell, enemy.cell) <= selected.attack_range \
					and board.has_line_of_sight(selected.cell, enemy.cell):
				attacks.append(enemy.cell)
	# Even with no moves or targets, the unit stays selected: overwatch (W)
	# is always a legal order for a unit that has not attacked.
	board.set_highlights(moves, attacks)
	_update_hover(board.global_to_cell(get_global_mouse_position()))


## Derives hover feedback (tile outline, path preview, aim line) from the
## current selection and pushes it to the Board for rendering.
func _update_hover(cell: Vector2i) -> void:
	if not board.in_bounds(cell):
		cell = Board.NO_CELL
	hover_cell = cell
	var path: Array[Vector2i] = []
	var aim_from := Board.NO_CELL
	var aim_covered := false
	if selected != null and cell != Board.NO_CELL:
		if board.move_cells.has(cell):
			path = board.reconstruct_path(board.move_cells, cell)
		elif board.attack_cells.has(cell):
			aim_from = selected.cell
			aim_covered = board.shot_through_cover(selected.cell, cell)
	board.set_hover(cell, path, aim_from, aim_covered)
	_update_unit_panel()


# --- Actions (shared by player and AI) ---------------------------------------

func do_move(unit: Unit, dest: Vector2i) -> void:
	var prev_state := state
	state = State.ANIMATING
	board.clear_highlights()
	var came_from := board.flood_fill(unit.cell, unit.move_range, _cell_blocked)
	if not came_from.has(dest):
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
		_update_unit_panel()


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
func _fire_round(attacker: Unit, target: Unit) -> void:
	var muzzle := attacker.muzzle_point()
	Sfx.play("shot")
	HitFx.spawn(self, muzzle, HitFx.Kind.MUZZLE)
	var tracer := Line2D.new()
	tracer.width = 3.0
	tracer.default_color = Color(1.0, 0.95, 0.6)
	tracer.add_point(muzzle)
	tracer.add_point(target.position + Vector2(0, -36))
	add_child(tracer)
	await get_tree().create_timer(TRACER_TIME).timeout
	tracer.queue_free()
	Sfx.play("hit_impact")
	HitFx.spawn(self, target.position + Vector2(0, -36), HitFx.Kind.IMPACT)
	_screen_shake()
	var dmg := attacker.damage
	if board.shot_through_cover(attacker.cell, target.cell):
		dmg >>= 1
		print("[ThinShot]   shot %s -> %s clips cover: %d dmg" % [
				attacker.cell, target.cell, dmg])
	target.take_damage(dmg)
	_update_unit_panel()  # keep hovered-unit HP live even during enemy fire


## Braced two-round burst: only for scouts that have not moved this turn.
## Each round is cover-checked independently; stops early if the target drops.
func do_burst(attacker: Unit, target: Unit) -> void:
	var prev_state := state
	state = State.ANIMATING
	board.clear_highlights()
	print("[ThinShot] burst! %s -> %s" % [attacker.cell, target.cell])
	var aim := (target.position - attacker.position).normalized()
	attacker.set_facing(aim)
	await attacker.raise_rifle()
	await _fire_round(attacker, target)
	if target.is_alive() and state != State.GAME_OVER:
		await get_tree().create_timer(BURST_GAP).timeout
		await _fire_round(attacker, target)
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
		_update_unit_panel()


# --- Danger overlay ----------------------------------------------------------

## Blocker for danger projection: only scouts block a goblin's projected
## reach. Goblins move sequentially on their turn and can vacate cells for
## each other, so counting them as blockers would under-warn (cells marked
## safe that a goblin can provably reach). Over-warning is the safe error.
func _cell_blocked_for_danger(cell: Vector2i) -> bool:
	var unit := unit_at(cell)
	return unit != null and unit.team == Unit.TEAM_SCOUT


## Every tile some living goblin could shoot next turn: reachable move cells
## (plus standing still) expanded by attack range with line of sight.
func _compute_danger_cells() -> Dictionary:
	var danger := {}
	for goblin in living_units(Unit.TEAM_GOBLIN):
		var origins: Array = board.flood_fill(
				goblin.cell, goblin.move_range, _cell_blocked_for_danger).keys()
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


## Living enemies of the mover that are on overwatch with range and LOS
## on the mover's current cell.
func _overwatchers_against(mover: Unit) -> Array[Unit]:
	var result: Array[Unit] = []
	for child in entities_node.get_children():
		var watcher := child as Unit
		if watcher == null or not watcher.is_alive() or not watcher.overwatching:
			continue
		if watcher.team == mover.team:
			continue
		if Board.manhattan(watcher.cell, mover.cell) <= watcher.attack_range \
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
	danger_button.disabled = false
	show_banner("DESERT SCOUTS' TURN")
	state = State.PLAYER_TURN
	player_turn_ready_msec = Time.get_ticks_msec()
	_refresh_danger()
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
		goblin.set_selected(true)  # red ring marks the acting goblin
		var shootable := _shootable_from(goblin.cell, goblin.attack_range, scouts)
		if not shootable.is_empty():
			print("[ThinShot]   goblin %d/%d shoots from %s" % [acted, squad.size(), from_cell])
			await do_attack(goblin, _nearest(goblin.cell, shootable))
		else:
			var target := _nearest(goblin.cell, scouts)
			var reach := board.flood_fill(goblin.cell, goblin.move_range, _cell_blocked)
			var candidates: Array = reach.keys()
			candidates.append(goblin.cell)  # staying put is a valid choice
			var dest := _best_ai_dest(goblin, candidates, scouts, target.cell)
			var moved_now := board.in_bounds(dest) and dest != goblin.cell
			if moved_now:
				await do_move(goblin, dest)
			shootable = _shootable_from(goblin.cell, goblin.attack_range, living_units(Unit.TEAM_SCOUT))
			var shoots := goblin.is_alive() and not shootable.is_empty()
			print("[ThinShot]   goblin %d/%d moves %s -> %s%s" % [
					acted, squad.size(), from_cell, goblin.cell,
					", shoots" if shoots else ""])
			if shoots:
				await do_attack(goblin, _nearest(goblin.cell, shootable))
			elif not moved_now and goblin.is_alive():
				# Dug in with no shot: cover the approach instead.
				goblin.set_overwatch(true)
				Sfx.play("overwatch_set", -4.0, 0.0)
				print("[ThinShot]   goblin %d/%d holds %s on overwatch" % [
						acted, squad.size(), goblin.cell])
		goblin.set_selected(false)
		if state == State.GAME_OVER:
			return
		await get_tree().create_timer(AI_BEAT).timeout


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
func _best_ai_dest(goblin: Unit, cells: Array, scouts: Array[Unit], chase_cell: Vector2i) -> Vector2i:
	var exposure_weight := 25 if goblin.hp <= 2 else 2
	var best := Vector2i(-1, -1)
	var best_score := 999999
	for cell: Vector2i in cells:
		var score := Board.manhattan(cell, chase_cell)
		score += exposure_weight * _exposure_at(cell, scouts)
		var shots := _shootable_from(cell, goblin.attack_range, scouts)
		if not shots.is_empty():
			score -= 1000
			# A clean firing position beats one that only has covered shots.
			if board.shot_through_cover(cell, _nearest(cell, shots).cell):
				score += 400
		if score < best_score:
			best_score = score
			best = cell
	return best


# --- Win / lose --------------------------------------------------------------

func _on_unit_died(_unit: Unit) -> void:
	Sfx.play("unit_death")
	check_game_over()


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
	if last_result_won:
		Game.select_level(0 if Game.is_last_level() else Game.current_level + 1)
	get_tree().reload_current_scene()


func _go_to_level(index: int) -> void:
	Game.select_level(index)
	get_tree().reload_current_scene()


# Fixed offsets keep the shake deterministic and always settle back to zero.
const SHAKE_OFFSETS: Array[Vector2] = [
	Vector2(4, -2), Vector2(-4, 2), Vector2(3, 1), Vector2(-2, -1), Vector2.ZERO,
]


func _screen_shake() -> void:
	var tween := create_tween()
	for off in SHAKE_OFFSETS:
		tween.tween_property(camera, "offset", off, 0.03)


func show_banner(text: String) -> void:
	turn_banner.text = text
	turn_banner.modulate.a = 0.0
	turn_banner.pivot_offset = turn_banner.size / 2.0
	turn_banner.scale = Vector2(1.25, 1.25)
	var tween := create_tween()
	tween.tween_property(turn_banner, "modulate:a", 1.0, 0.2)
	tween.parallel().tween_property(turn_banner, "scale", Vector2.ONE, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
