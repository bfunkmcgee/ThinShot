extends Node2D

## Battle controller: turn state machine, player input, enemy AI, win/lose.

enum State { PLAYER_TURN, ANIMATING, ENEMY_TURN, GAME_OVER }

const UNIT_SCENE := preload("res://scenes/Unit.tscn")
const SCOUT_TEXTURE := preload("res://assets/sprites/scout.svg")
const GOBLIN_TEXTURE := preload("res://assets/sprites/goblin.svg")
const ROCK_TEXTURE := preload("res://assets/sprites/rock.svg")

# Sprites are 64x80 with the ground-contact line at texture y=72;
# this offset puts their feet on the node position (the diamond center).
const SPRITE_FOOT_OFFSET := Vector2(0, -32)

const SCOUT_SPAWNS: Array[Vector2i] = [
	Vector2i(1, 2), Vector2i(1, 4), Vector2i(2, 3),
]
const GOBLIN_SPAWNS: Array[Vector2i] = [
	Vector2i(10, 1), Vector2i(10, 3), Vector2i(10, 5), Vector2i(9, 6),
]

const MOVE_STEP_TIME := 0.12
const TRACER_TIME := 0.09
const AI_BEAT := 0.25

var state := State.PLAYER_TURN
var selected: Unit = null

@onready var board: Board = $Board
@onready var entities_node: Node2D = $Entities
@onready var turn_banner: Label = $UI/TurnBanner
@onready var end_turn_button: Button = $UI/EndTurnButton
@onready var game_over_panel: ColorRect = $UI/GameOver
@onready var result_label: Label = $UI/GameOver/ResultLabel
@onready var restart_button: Button = $UI/GameOver/RestartButton


func _ready() -> void:
	for y in Board.SIZE.y:
		for x in Board.SIZE.x:
			var cell := Vector2i(x, y)
			if board.is_wall(cell):
				var rock := Sprite2D.new()
				rock.texture = ROCK_TEXTURE
				rock.offset = SPRITE_FOOT_OFFSET
				rock.position = board.cell_to_global(cell)
				entities_node.add_child(rock)
	for spawn in SCOUT_SPAWNS:
		_spawn_unit(Unit.TEAM_SCOUT, spawn, SCOUT_TEXTURE)
	for spawn in GOBLIN_SPAWNS:
		_spawn_unit(Unit.TEAM_GOBLIN, spawn, GOBLIN_TEXTURE)
	end_turn_button.pressed.connect(end_player_turn)
	restart_button.pressed.connect(_on_restart)
	show_banner("DESERT SCOUTS' TURN")


func _spawn_unit(team: int, spawn_cell: Vector2i, texture: Texture2D) -> void:
	var unit: Unit = UNIT_SCENE.instantiate()
	entities_node.add_child(unit)
	unit.setup(team, spawn_cell, texture)
	unit.position = board.cell_to_global(spawn_cell)


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
			if Board.manhattan(selected.cell, enemy.cell) <= selected.attack_range:
				attacks.append(enemy.cell)
	board.set_highlights(moves, attacks)
	if moves.is_empty() and attacks.is_empty():
		selected.set_done(true)
		deselect()


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
	for step in path:
		tween.tween_property(unit, "position", board.cell_to_global(step), MOVE_STEP_TIME)
	await tween.finished
	unit.moved = true
	state = prev_state
	if prev_state == State.PLAYER_TURN and selected == unit:
		_refresh_highlights()


func do_attack(attacker: Unit, target: Unit) -> void:
	var prev_state := state
	state = State.ANIMATING
	board.clear_highlights()
	var tracer := Line2D.new()
	tracer.width = 3.0
	tracer.default_color = Color(1.0, 0.95, 0.6)
	tracer.add_point(attacker.position + Vector2(0, -36))
	tracer.add_point(target.position + Vector2(0, -36))
	add_child(tracer)
	await get_tree().create_timer(TRACER_TIME).timeout
	tracer.queue_free()
	target.take_damage(attacker.damage)
	attacker.set_done(true)
	if attacker == selected:
		deselect()
	if check_game_over():
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
	for unit in living_units(Unit.TEAM_SCOUT):
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
		var target := _nearest(goblin.cell, scouts)
		if Board.manhattan(goblin.cell, target.cell) <= goblin.attack_range:
			await do_attack(goblin, target)
		else:
			var reach := board.flood_fill(goblin.cell, goblin.move_range, _cell_blocked)
			var dest := _closest_cell_to(reach.keys(), target.cell)
			if board.in_bounds(dest):
				await do_move(goblin, dest)
			if goblin.is_alive() and target.is_alive() \
					and Board.manhattan(goblin.cell, target.cell) <= goblin.attack_range:
				await do_attack(goblin, target)
		if state == State.GAME_OVER:
			return
		await get_tree().create_timer(AI_BEAT).timeout


func _nearest(from_cell: Vector2i, candidates: Array[Unit]) -> Unit:
	var best: Unit = candidates[0]
	for unit in candidates:
		if Board.manhattan(from_cell, unit.cell) < Board.manhattan(from_cell, best.cell):
			best = unit
	return best


func _closest_cell_to(cells: Array, target_cell: Vector2i) -> Vector2i:
	var best := target_cell  # sentinel; replaced below if any cell exists
	var best_dist := 999
	for cell: Vector2i in cells:
		var dist := Board.manhattan(cell, target_cell)
		if dist < best_dist:
			best_dist = dist
			best = cell
	return best if best_dist < 999 else Vector2i(-1, -1)


# --- Win / lose --------------------------------------------------------------

func check_game_over() -> bool:
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


func show_banner(text: String) -> void:
	turn_banner.text = text
	turn_banner.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(turn_banner, "modulate:a", 1.0, 0.2)
