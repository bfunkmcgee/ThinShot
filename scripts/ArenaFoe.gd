class_name ArenaFoe

## The Thirst, in real time. One small state machine per fighter on THE RANGE,
## run as static functions over a state dictionary the arena keeps beside the
## Unit - the same shape AiPlan takes for the turn-based game: no instance, no
## node, nothing on the Unit itself.
##
##   SPAWNING -> APPROACH -> AIMING <-> FIRING -> (RELOADING | RELOCATE)
##                  ^                     |
##                  +------ sight lost ---+
##
## Everything about the fighter's WEAPON is read off the Unit the campaign
## already built: attack_range says how close he wants to be, mag_size says
## when he must reload, accuracy and damage go through Rules unchanged. What
## this file adds is pacing - how fast he walks in pixels, and how his rounds
## are spaced in seconds - which a turn never had to say.

enum State { SPAWNING, APPROACH, AIMING, FIRING, RELOADING, RELOCATE }

## Camp walks Rodar (move_range 5) at 168 px/s and never asked how fast anybody
## else walks. So: linear in move_range, anchored there.
const PX_PER_SEC_PER_MOVE := 168.0 / 5.0
const ISO_SQUASH := 0.469  # Board.TILE_H / Board.TILE_W, as Camp
## How often a fighter re-plans his path. Never per frame: Board.flood_fill is
## an uncached BFS, and ten of them a frame is the one real CPU risk here.
const REPATH := 0.4
const ARRIVE_PX := 4.0
const SPAWN_TIME := 0.5     # rising in at the edge before moving
const RAISE_TIME := 0.55    # the raise animation, plus a beat of aiming
const RELOCATE_TIME := 1.5  # how long a Cupbearer moves between bursts
const RELOCATE_RANGE := 3

## Rounds per trigger pull, the gap inside a burst, and the pause after it.
## Battle's own BURST_GAP (0.13) is the one cadence number the game had already
## tuned by feel; the rest are anchored to it. "relocate" is the Cupbearer's
## shoot-and-move. Pacing, not arithmetic - which is why it lives here and not
## in Rules.gd (RM5 is about numbers that decide hits and damage).
const CADENCE := {
	Unit.Kind.GOBLIN: {"burst": 1, "gap": 0.0, "pause": 1.1},
	Unit.Kind.GOBLIN_SMG: {"burst": 3, "gap": 0.13, "pause": 1.4},
	Unit.Kind.GOBLIN_SMG_ALT: {"burst": 3, "gap": 0.13, "pause": 1.1},
	Unit.Kind.GOBLIN_REVOLVER: {"burst": 1, "gap": 0.0, "pause": 1.3},
	# One round in the rifle: the reload after every shot is what roots him.
	Unit.Kind.GOBLIN_BOLT: {"burst": 1, "gap": 0.0, "pause": 0.9},
	Unit.Kind.GOBLIN_MG: {"burst": 6, "gap": 0.15, "pause": 0.6},
	Unit.Kind.GOBLIN_BRUTE: {"burst": 1, "gap": 0.0, "pause": 1.5},
	Unit.Kind.ELF_PARTISAN: {"burst": 2, "gap": 0.15, "pause": 0.4, "relocate": true},
}
const DEFAULT_CADENCE := {"burst": 1, "gap": 0.0, "pause": 1.2}


static func new_state(rng: RandomNumberGenerator) -> Dictionary:
	return {
		"state": State.SPAWNING,
		"timer": SPAWN_TIME,
		"path": [] as Array[Vector2i],
		# Phase-offset so ten fighters never all repath on the same frame.
		"repath": rng.randf() * REPATH,
		"burst_left": 0,
		"cooldown": 0.0,
		"dest": Vector2i(-1, -1),
	}


static func cadence_of(kind: int) -> Dictionary:
	return CADENCE.get(kind, DEFAULT_CADENCE)


## Real-time walking speed, from the turn-based stat.
static func speed_of(unit: Unit) -> float:
	return unit.move_range * PX_PER_SEC_PER_MOVE


## Close enough and can see him: the same two questions the turn-based AI asks
## before it commits a shot (Board.can_engage covers the lean around a corner).
static func can_shoot(board: Board, unit: Unit, target: Unit) -> bool:
	return Board.manhattan(unit.cell, target.cell) <= unit.attack_range \
			and board.can_engage(unit.cell, target.cell)


## One frame of one fighter. `arena` is the Arena scene: it owns the board,
## the player and the shot resolver (foe_fire), and this file asks it for all
## three rather than reaching for scene nodes itself.
static func tick(arena: Node2D, unit: Unit, st: Dictionary, delta: float) -> void:
	var board: Board = arena.board
	var target: Unit = arena.player
	if not unit.is_alive():
		return
	if target == null or not target.is_alive():
		# Nobody left to fight. Stand down where he is.
		if unit.anim == Unit.Anim.WALK:
			unit.stop_walking()
		return
	match int(st.state):
		State.SPAWNING:
			st.timer -= delta
			if st.timer <= 0.0:
				st.state = State.APPROACH
		State.APPROACH:
			_approach(arena, board, unit, target, st, delta)
		State.AIMING:
			if not can_shoot(board, unit, target):
				_break_off(unit, st)
				return
			unit.set_facing(target.position - unit.position)
			st.timer -= delta
			if st.timer <= 0.0:
				st.state = State.FIRING
				st.burst_left = int(cadence_of(unit.kind).burst)
				st.cooldown = 0.0
		State.FIRING:
			if not can_shoot(board, unit, target):
				_break_off(unit, st)
				return
			unit.set_facing(target.position - unit.position)
			st.cooldown -= delta
			if st.cooldown > 0.0:
				return
			if unit.needs_reload():
				_begin_reload(unit, st)
				return
			var cad := cadence_of(unit.kind)
			arena.foe_fire(unit)
			st.burst_left -= 1
			if st.burst_left > 0:
				st.cooldown = float(cad.gap)
			else:
				st.cooldown = float(cad.pause)
				st.burst_left = int(cad.burst)
				if bool(cad.get("relocate", false)):
					_begin_relocate(board, unit, target, st, arena.rng)
		State.RELOADING:
			st.timer -= delta
			if st.timer <= 0.0:
				unit.reload()
				st.state = State.AIMING
				st.timer = 0.15
		State.RELOCATE:
			st.timer -= delta
			var done := _walk_path(board, unit, st, delta)
			if done or st.timer <= 0.0:
				unit.stop_walking()
				st.state = State.AIMING
				st.timer = RAISE_TIME * 0.5
				unit.set_facing(target.position - unit.position)
				unit.raise_rifle()


## Lost the shot - sight or range - so the rifle comes down and he closes again.
static func _break_off(unit: Unit, st: Dictionary) -> void:
	unit.lower_rifle()
	st.state = State.APPROACH
	st.repath = 0.0


static func _approach(arena: Node2D, board: Board, unit: Unit, target: Unit,
		st: Dictionary, delta: float) -> void:
	if can_shoot(board, unit, target):
		unit.stop_walking()
		unit.set_facing(target.position - unit.position)
		unit.raise_rifle()
		st.state = State.AIMING
		st.timer = RAISE_TIME
		return
	st.repath -= delta
	if st.repath <= 0.0 or (st.path as Array).is_empty():
		st.repath = REPATH
		st.path = _path_toward(board, unit.cell, target.cell)
	if (st.path as Array).is_empty():
		# Boxed in or already adjacent with no sight: shuffle straight at him.
		_step_toward(board, unit, target.position, delta)
		return
	_walk_path(board, unit, st, delta)


## BFS to the target's cell. The whole board is in range (40 > 20 + 14); nothing
## is treated as blocked beyond what the Board itself refuses to walk, because
## v1 has no unit-on-unit collision and a path that dodged a fighter who is
## about to move would be a worse path than the straight one.
static func _path_toward(board: Board, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var came_from := board.flood_fill(from, 40, func(_c: Vector2i) -> bool: return false)
	if not came_from.has(to):
		return [] as Array[Vector2i]
	var path := board.reconstruct_path(came_from, to)
	# Stop one short: the destination is the man himself.
	if not path.is_empty():
		path.pop_back()
	return path


## Follow st.path a frame; true when it is used up.
static func _walk_path(board: Board, unit: Unit, st: Dictionary, delta: float) -> bool:
	var path: Array = st.path
	if path.is_empty():
		return true
	var next: Vector2i = path[0]
	var goal := board.cell_to_global(next)
	if unit.position.distance_to(goal) <= ARRIVE_PX:
		unit.position = goal
		unit.cell = next
		path.pop_front()
		return path.is_empty()
	_step_toward(board, unit, goal, delta)
	return false


## One frame of walking toward a world point, Camp's squash rule so a step up
## the screen covers the same ground as a step across it.
static func _step_toward(board: Board, unit: Unit, goal: Vector2, delta: float) -> void:
	var d := goal - unit.position
	if d.length_squared() < 0.01:
		return
	var velocity := Vector2(d.x, d.y * ISO_SQUASH).normalized() \
			* speed_of(unit) * Vector2(1.0, ISO_SQUASH)
	var step := velocity * delta
	if step.length() > d.length():
		step = d
	unit.position += step
	unit.cell = board.global_to_cell(unit.position)
	unit.set_facing(d)
	# start_walking() resets the cycle, so only on the transition - as Camp.
	if unit.anim != Unit.Anim.WALK and unit.anim != Unit.Anim.HURT \
			and unit.anim != Unit.Anim.RELOAD:
		unit.start_walking()


static func _begin_reload(unit: Unit, st: Dictionary) -> void:
	var cycle: Array = unit.reload_frames[unit.facing_sector]
	# Measured off the frames that ship, never assumed: units carry different
	# counts. The same length Unit.play_reload waits for.
	st.timer = float(maxi(cycle.size(), 1)) / Unit.RELOAD_FPS + 0.05
	st.state = State.RELOADING
	unit.play_reload()


## A Cupbearer fires his pair and is somewhere else before the answer comes:
## a walkable cell a few steps off, picked at random, walked for a moment.
static func _begin_relocate(board: Board, unit: Unit, target: Unit, st: Dictionary,
		rng: RandomNumberGenerator) -> void:
	var came_from := board.flood_fill(unit.cell, RELOCATE_RANGE,
			func(_c: Vector2i) -> bool: return false)
	var options: Array = came_from.keys()
	options = options.filter(func(c: Vector2i) -> bool:
		return Board.manhattan(c, target.cell) >= 2)
	if options.is_empty():
		st.state = State.AIMING
		st.timer = 0.1
		return
	var dest: Vector2i = options[rng.randi_range(0, options.size() - 1)]
	st.path = board.reconstruct_path(came_from, dest)
	st.timer = RELOCATE_TIME
	st.state = State.RELOCATE
	unit.lower_rifle()
