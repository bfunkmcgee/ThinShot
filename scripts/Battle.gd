extends Node2D

## Battle controller: turn state machine, player input, enemy AI, win/lose.

enum State { PLAYER_TURN, ANIMATING, ENEMY_TURN, GAME_OVER }

const UNIT_SCENE := preload("res://scenes/Unit.tscn")
const ROCK_TEXTURES: Array[Texture2D] = [
	preload("res://assets/sprites/Environment/Desert/Desert_Rock_or_bolder/Rock_1.png"),
	preload("res://assets/sprites/Environment/Desert/Desert_Rock_or_bolder/Rock_2.png"),
	preload("res://assets/sprites/Environment/Desert/Desert_Rock_or_bolder/Rock_3.png"),
]

# Rocks are 48x48 with their base ~19px below canvas center; drawn at 2x.
const ROCK_OFFSET := Vector2(0, -18)
const ROCK_SCALE := Vector2(2, 2)

const SCOUT_SPAWNS: Array[Vector2i] = [
	Vector2i(1, 2), Vector2i(1, 4), Vector2i(3, 3),
]
const GOBLIN_SPAWNS: Array[Vector2i] = [
	Vector2i(10, 1), Vector2i(10, 3), Vector2i(10, 5), Vector2i(10, 7),
]

const MOVE_STEP_TIME := 0.16
const TRACER_TIME := 0.09
const AI_BEAT := 0.25
const AIM_TIME := 0.18  # rifle raised before the shot
const LOWER_TIME := 0.12  # rifle held after the shot

# Ignore end-turn requests this soon after control returns to the player -
# they are almost always leftover E-mashing/clicking from the enemy turn.
const END_TURN_GRACE_MS := 350

var state := State.PLAYER_TURN
var selected: Unit = null
var hover_cell := Board.NO_CELL
var turn_number := 1
var enemy_turn_running := false
var player_turn_ready_msec := 0

@onready var board: Board = $Board
@onready var entities_node: Node2D = $Entities
@onready var turn_banner: Label = $UI/TurnBanner
@onready var end_turn_button: Button = $UI/EndTurnButton
@onready var overwatch_button: Button = $UI/OverwatchButton
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
				# Deterministic variant per cell so the layout is stable.
				rock.texture = ROCK_TEXTURES[(cell.x * 7 + cell.y * 13) % ROCK_TEXTURES.size()]
				rock.offset = ROCK_OFFSET
				rock.scale = ROCK_SCALE
				rock.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				rock.position = board.cell_to_global(cell)
				entities_node.add_child(rock)
	for spawn in SCOUT_SPAWNS:
		_spawn_unit(Unit.TEAM_SCOUT, spawn)
	for spawn in GOBLIN_SPAWNS:
		_spawn_unit(Unit.TEAM_GOBLIN, spawn)
	end_turn_button.pressed.connect(end_player_turn)
	overwatch_button.pressed.connect(_try_overwatch)
	restart_button.pressed.connect(_on_restart)
	show_banner("DESERT SCOUTS' TURN")
	player_turn_ready_msec = Time.get_ticks_msec()
	print("[ThinShot] player turn 1 begins")


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
	if event.is_action_pressed("overwatch"):
		_try_overwatch()
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


## Put the selected scout on overwatch, consuming its activation.
func _try_overwatch() -> void:
	if state != State.PLAYER_TURN or selected == null or selected.acted:
		return
	var scout := selected
	deselect()
	scout.set_done(true)
	scout.set_overwatch(true)
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
	unit.start_walking()
	var from_pos := unit.position
	for step in path:
		var step_pos := board.cell_to_global(step)
		unit.set_facing(step_pos - from_pos)
		var tween := create_tween()
		tween.tween_property(unit, "position", step_pos, MOVE_STEP_TIME)
		await tween.finished
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
				return
			unit.start_walking()
	unit.stop_walking()
	unit.moved = true
	state = prev_state
	if prev_state == State.PLAYER_TURN and selected == unit:
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


## The shot itself: face, (optionally) raise and hold, fire effects, damage,
## lower. Reaction shots skip the aim beat - the rifle is already up.
func _resolve_shot(attacker: Unit, target: Unit, with_aim_beat: bool) -> void:
	var aim := (target.position - attacker.position).normalized()
	attacker.set_facing(aim)
	if with_aim_beat:
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
	state = State.ENEMY_TURN
	print("[ThinShot] enemy turn %d begins" % turn_number)
	show_banner("RUST CHOIR'S TURN")
	end_turn_button.disabled = true
	overwatch_button.disabled = true
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
	end_turn_button.disabled = false
	overwatch_button.disabled = false
	show_banner("DESERT SCOUTS' TURN")
	state = State.PLAYER_TURN
	player_turn_ready_msec = Time.get_ticks_msec()


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
