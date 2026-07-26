extends Node2D

## Battle controller: turn state machine, player input, enemy AI, win/lose.

enum State { PLAYER_TURN, ANIMATING, ENEMY_TURN, GAME_OVER }

const UNIT_SCENE := preload("res://scenes/Unit.tscn")
const ROCK_TEXTURE := preload("res://assets/sprites/rock.svg")

# rock.svg is 64x80 with its ground line at y=72.
const ROCK_OFFSET := Vector2(0, -32)

const SCOUT_SPAWNS: Array[Vector2i] = [
	Vector2i(1, 2), Vector2i(1, 4), Vector2i(3, 3),
]
const GOBLIN_SPAWNS: Array[Vector2i] = [
	Vector2i(10, 1), Vector2i(10, 3), Vector2i(10, 5), Vector2i(10, 7),
]

const MOVE_STEP_TIME := 0.12
const TRACER_TIME := 0.09
const AI_BEAT := 0.25
const AIM_TIME := 0.18  # rifle raised before the shot
const LOWER_TIME := 0.12  # rifle held after the shot

var state := State.PLAYER_TURN
var selected: Unit = null
var hover_cell := Board.NO_CELL

@onready var board: Board = $Board
@onready var entities_node: Node2D = $Entities
@onready var turn_banner: Label = $UI/TurnBanner
@onready var end_turn_button: Button = $UI/EndTurnButton
@onready var game_over_panel: ColorRect = $UI/GameOver
@onready var result_label: Label = $UI/GameOver/ResultLabel
@onready var restart_button: Button = $UI/GameOver/RestartButton


func _ready() -> void:
	_validate_spawns()
	for y in Board.SIZE.y:
		for x in Board.SIZE.x:
			var cell := Vector2i(x, y)
			if board.is_wall(cell):
				var rock := Sprite2D.new()
				rock.texture = ROCK_TEXTURE
				rock.offset = ROCK_OFFSET
				rock.position = board.cell_to_global(cell)
				entities_node.add_child(rock)
	for spawn in SCOUT_SPAWNS:
		_spawn_unit(Unit.TEAM_SCOUT, spawn)
	for spawn in GOBLIN_SPAWNS:
		_spawn_unit(Unit.TEAM_GOBLIN, spawn)
	end_turn_button.pressed.connect(end_player_turn)
	restart_button.pressed.connect(_on_restart)
	show_banner("DESERT SCOUTS' TURN")


func _validate_spawns() -> void:
	for spawn: Vector2i in SCOUT_SPAWNS + GOBLIN_SPAWNS:
		if not board.in_bounds(spawn) or board.is_wall(spawn):
			push_error("Bad spawn cell (wall or out of bounds): %s" % spawn)
			assert(false, "Bad spawn cell: %s" % spawn)


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
			do_attack(selected, clicked)
			return
		if board.move_cells.has(cell):
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
	_refresh_highlights()


func deselect() -> void:
	if selected != null:
		selected.set_selected(false)
		selected = null
	board.clear_highlights()


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
	board.set_highlights(moves, attacks)
	if moves.is_empty() and attacks.is_empty():
		selected.set_done(true)
		deselect()
		return
	_update_hover(board.global_to_cell(get_global_mouse_position()))


## Derives hover feedback (tile outline, path preview, aim line) from the
## current selection and pushes it to the Board for rendering.
func _update_hover(cell: Vector2i) -> void:
	if not board.in_bounds(cell):
		cell = Board.NO_CELL
	hover_cell = cell
	var path: Array[Vector2i] = []
	var aim_from := Board.NO_CELL
	if selected != null and cell != Board.NO_CELL:
		if board.move_cells.has(cell):
			path = board.reconstruct_path(board.move_cells, cell)
		elif board.attack_cells.has(cell):
			aim_from = selected.cell
	board.set_hover(cell, path, aim_from)


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
	unit.cell = dest
	var tween := create_tween()
	var from_pos := unit.position
	for step in path:
		var step_pos := board.cell_to_global(step)
		tween.tween_callback(unit.set_facing.bind(step_pos - from_pos))
		tween.tween_property(unit, "position", step_pos, MOVE_STEP_TIME)
		from_pos = step_pos
	await tween.finished
	unit.moved = true
	state = prev_state
	if prev_state == State.PLAYER_TURN and selected == unit:
		_refresh_highlights()


func do_attack(attacker: Unit, target: Unit) -> void:
	var prev_state := state
	state = State.ANIMATING
	board.clear_highlights()
	var aim := (target.position - attacker.position).normalized()
	attacker.set_facing(aim)
	attacker.set_aiming(true)
	await get_tree().create_timer(AIM_TIME).timeout
	HitFx.spawn(self, attacker.position + Vector2(0, -36) + aim * 16.0, HitFx.Kind.MUZZLE)
	var tracer := Line2D.new()
	tracer.width = 3.0
	tracer.default_color = Color(1.0, 0.95, 0.6)
	tracer.add_point(attacker.position + Vector2(0, -36))
	tracer.add_point(target.position + Vector2(0, -36))
	add_child(tracer)
	await get_tree().create_timer(TRACER_TIME).timeout
	tracer.queue_free()
	HitFx.spawn(self, target.position + Vector2(0, -36), HitFx.Kind.IMPACT)
	_screen_shake()
	target.take_damage(attacker.damage)
	await get_tree().create_timer(LOWER_TIME).timeout
	attacker.set_aiming(false)
	attacker.set_done(true)
	if attacker == selected:
		deselect()
	# A death inside take_damage triggers _on_unit_died -> check_game_over.
	if state == State.GAME_OVER:
		return
	state = prev_state


# --- Turn flow ---------------------------------------------------------------

func end_player_turn() -> void:
	if state != State.PLAYER_TURN:
		return
	deselect()
	state = State.ENEMY_TURN
	show_banner("RUST CHOIR'S TURN")
	end_turn_button.disabled = true
	await run_enemy_turn()
	if state == State.GAME_OVER:
		return
	# Reset both teams: scouts for the new player turn, goblins so they don't
	# sit dimmed through it looking like they already acted.
	for unit in living_units(Unit.TEAM_SCOUT) + living_units(Unit.TEAM_GOBLIN):
		unit.start_turn()
	end_turn_button.disabled = false
	show_banner("DESERT SCOUTS' TURN")
	state = State.PLAYER_TURN


func run_enemy_turn() -> void:
	for goblin in living_units(Unit.TEAM_GOBLIN):
		if not is_instance_valid(goblin) or not goblin.is_alive():
			continue
		var scouts := living_units(Unit.TEAM_SCOUT)
		if scouts.is_empty():
			return
		var shootable := _shootable_from(goblin.cell, goblin.attack_range, scouts)
		if not shootable.is_empty():
			await do_attack(goblin, _nearest(goblin.cell, shootable))
		else:
			var target := _nearest(goblin.cell, scouts)
			var reach := board.flood_fill(goblin.cell, goblin.move_range, _cell_blocked)
			var candidates: Array = reach.keys()
			candidates.append(goblin.cell)  # staying put is a valid choice
			var dest := _best_ai_dest(goblin, candidates, scouts, target.cell)
			if board.in_bounds(dest) and dest != goblin.cell:
				await do_move(goblin, dest)
			shootable = _shootable_from(goblin.cell, goblin.attack_range, living_units(Unit.TEAM_SCOUT))
			if goblin.is_alive() and not shootable.is_empty():
				await do_attack(goblin, _nearest(goblin.cell, shootable))
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


## Number of living scouts with range and line of sight on this cell.
func _threat_at(cell: Vector2i, scouts: Array[Unit]) -> int:
	var count := 0
	for scout in scouts:
		if Board.manhattan(cell, scout.cell) <= scout.attack_range \
				and board.has_line_of_sight(scout.cell, cell):
			count += 1
	return count


## Best move destination for an AI unit. A cell it can shoot a scout from
## beats every cell it can't; exposure to scout fire costs a little when
## healthy and a lot when wounded (so 1 HP goblins with no shot retreat to
## cover); nearer the chase target breaks remaining ties.
func _best_ai_dest(goblin: Unit, cells: Array, scouts: Array[Unit], chase_cell: Vector2i) -> Vector2i:
	var threat_weight := 50 if goblin.hp <= 1 else 3
	var best := Vector2i(-1, -1)
	var best_score := 999999
	for cell: Vector2i in cells:
		var score := Board.manhattan(cell, chase_cell)
		score += threat_weight * _threat_at(cell, scouts)
		if not _shootable_from(cell, goblin.attack_range, scouts).is_empty():
			score -= 1000
		if score < best_score:
			best_score = score
			best = cell
	return best


# --- Win / lose --------------------------------------------------------------

func _on_unit_died(_unit: Unit) -> void:
	check_game_over()


func check_game_over() -> bool:
	if state == State.GAME_OVER:
		return true
	if living_units(Unit.TEAM_GOBLIN).is_empty():
		_show_game_over("DESERT SCOUTS WIN")
		return true
	if living_units(Unit.TEAM_SCOUT).is_empty():
		_show_game_over("THE CHOIR SINGS ON")
		return true
	return false


func _show_game_over(text: String) -> void:
	state = State.GAME_OVER
	result_label.text = text
	game_over_panel.visible = true


func _on_restart() -> void:
	get_tree().reload_current_scene()


# Fixed offsets keep the shake deterministic and always settle back to zero.
const SHAKE_OFFSETS: Array[Vector2] = [
	Vector2(4, -2), Vector2(-4, 2), Vector2(3, 1), Vector2(-2, -1), Vector2.ZERO,
]


func _screen_shake() -> void:
	var tween := create_tween()
	for off in SHAKE_OFFSETS:
		tween.tween_property(self, "position", off, 0.03)


func show_banner(text: String) -> void:
	turn_banner.text = text
	turn_banner.modulate.a = 0.0
	turn_banner.pivot_offset = turn_banner.size / 2.0
	turn_banner.scale = Vector2(1.25, 1.25)
	var tween := create_tween()
	tween.tween_property(turn_banner, "modulate:a", 1.0, 0.2)
	tween.parallel().tween_property(turn_banner, "scale", Vector2.ONE, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
