class_name ArenaWaves
extends Node

## How the Thirst comes on at THE RANGE. A budget-based director: every wave
## has a spend, the spend goes on the costliest fighters unlocked so far with
## a cap so no wave is all one thing, and the change buys the cheapest. They
## arrive in squads from the edges, a few seconds apart, never more than the
## board can read at once, and there is a breather between waves in which the
## rifle is refilled.
##
## The shape is Dustline's WaveDirector (c:\dev\Dustline), retuned for one man
## on a 20x14 board instead of a squad in an open arena. None of it is combat
## arithmetic - costs and cadence are pacing - so none of it is in Rules.gd.

signal wave_started(wave: int, count: int)
signal wave_cleared(wave: int)
signal breather_started(seconds: float)

## Rough worth of one fighter against a wave's budget. Scaled off what each
## one does to Rodar, not off his hit points: a Marksman who takes four of
## ten in one round is dearer than a well-hand with a scavenged rifle.
const COSTS := {
	Unit.Kind.GOBLIN_REVOLVER: 1.0,
	Unit.Kind.GOBLIN: 1.5,
	Unit.Kind.GOBLIN_SMG_ALT: 1.5,
	Unit.Kind.GOBLIN_SMG: 2.0,
	Unit.Kind.GOBLIN_BOLT: 3.0,
	Unit.Kind.ELF_PARTISAN: 3.5,
	Unit.Kind.GOBLIN_MG: 4.0,
	Unit.Kind.GOBLIN_BRUTE: 5.0,
}
## The first wave a kind may appear in. The drill teaches its roster the way
## the campaign does: rifles first, the crew weapons and the brute last.
const UNLOCK := {
	Unit.Kind.GOBLIN_REVOLVER: 1,
	Unit.Kind.GOBLIN: 1,
	Unit.Kind.GOBLIN_SMG_ALT: 2,
	Unit.Kind.GOBLIN_SMG: 2,
	Unit.Kind.GOBLIN_BOLT: 3,
	Unit.Kind.ELF_PARTISAN: 4,
	Unit.Kind.GOBLIN_MG: 5,
	Unit.Kind.GOBLIN_BRUTE: 6,
}
const BUDGET_BASE := 1.6
const BUDGET_GROWTH := 1.9
const SHARE_CAP := 0.45      # no one kind may take more than this of a wave
const MAX_ALIVE := 12        # a 20x14 board with one man on it, readable
const SQUAD_SIZE := 4
const SQUAD_GAP := 2.4
const FIRST_DELAY := 2.5     # a breath to find the controls
const BREATHER := 6.0

var arena: Node2D = null
var rng := RandomNumberGenerator.new()
var wave := 0
var alive := 0
var _queue: Array = []
var _squad_timer := 0.0
var _breather := FIRST_DELAY
var in_breather := true


func setup(p_arena: Node2D, p_rng: RandomNumberGenerator) -> void:
	arena = p_arena
	rng = p_rng


func _process(delta: float) -> void:
	if arena == null or bool(arena.game_over):
		return
	if in_breather:
		_breather -= delta
		if _breather <= 0.0:
			_begin_wave()
		return
	if _queue.is_empty() and alive == 0:
		_clear_wave()
		return
	_squad_timer -= delta
	if _squad_timer <= 0.0 and not _queue.is_empty():
		var sent := 0
		while sent < SQUAD_SIZE and not _queue.is_empty() and alive < MAX_ALIVE:
			if not _spawn_one(int(_queue.pop_front())):
				break
			sent += 1
		_squad_timer = SQUAD_GAP


## What wave `w` is made of. Deterministic for a given rng state, which is what
## lets a run's seed be written on its readout and a test pin the curve.
func compose(w: int) -> Array:
	var budget := BUDGET_BASE + BUDGET_GROWTH * w
	var unlocked: Array = []
	for kind in COSTS:
		if int(UNLOCK[kind]) <= w:
			unlocked.append(kind)
	unlocked.sort_custom(func(a, b) -> bool: return float(COSTS[a]) > float(COSTS[b]))
	var picks: Array = []
	var spent_on := {}
	var left := budget
	# Costliest first, each capped to its share, so the wave has a spine.
	for kind in unlocked:
		var cost := float(COSTS[kind])
		while left >= cost and float(spent_on.get(kind, 0.0)) + cost <= budget * SHARE_CAP:
			picks.append(kind)
			spent_on[kind] = float(spent_on.get(kind, 0.0)) + cost
			left -= cost
	# The change buys the cheapest thing that fits, cap or no cap.
	if not unlocked.is_empty():
		var cheapest = unlocked[unlocked.size() - 1]
		var cheap_cost := float(COSTS[cheapest])
		while left >= cheap_cost:
			picks.append(cheapest)
			left -= cheap_cost
	if picks.is_empty():
		picks.append(unlocked[unlocked.size() - 1] if not unlocked.is_empty()
				else Unit.Kind.GOBLIN)
	# Shuffled so a squad is mixed, off the run's own generator.
	for i in range(picks.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = picks[i]
		picks[i] = picks[j]
		picks[j] = tmp
	return picks


func _begin_wave() -> void:
	wave += 1
	_queue = compose(wave)
	in_breather = false
	_squad_timer = 0.0
	wave_started.emit(wave, _queue.size())


func _clear_wave() -> void:
	wave_cleared.emit(wave)
	in_breather = true
	_breather = BREATHER
	breather_started.emit(BREATHER)


func on_foe_died() -> void:
	alive = maxi(alive - 1, 0)


func _spawn_one(kind: int) -> bool:
	var cell := _spawn_cell()
	if cell == Board.NO_CELL:
		return false
	arena.spawn_foe(kind, cell)
	alive += 1
	return true


## A rim cell nobody stands on that the player cannot see, on the far side
## of the board from him for preference. Battle's _arrival_cell uses a
## Manhattan standoff for the same job; sight is the better filter here,
## because a fighter who appears in view appears at the end of a rifle.
func _spawn_cell() -> Vector2i:
	var board: Board = arena.board
	var player: Unit = arena.player
	var rim: Array[Vector2i] = ArenaData.spawn_rim(ArenaData.RANGE)
	var free: Array[Vector2i] = []
	var unseen: Array[Vector2i] = []
	for cell in rim:
		if not board.is_walkable(cell) or arena.unit_at(cell) != null:
			continue
		free.append(cell)
		if player != null and not board.has_line_of_sight(cell, player.cell):
			unseen.append(cell)
	var pool := unseen if not unseen.is_empty() else free
	if pool.is_empty():
		return Board.NO_CELL
	if player != null:
		pool.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return Board.manhattan(a, player.cell) > Board.manhattan(b, player.cell))
	var half := maxi(1, pool.size() / 2)
	return pool[rng.randi_range(0, half - 1)]
