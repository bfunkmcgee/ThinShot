extends SceneTree

## The enemy's judgement, pinned on geometry built for the purpose.
##
## scripts/AiPlan.gd is arithmetic over a Board and the units it is handed -
## no scene, no occupancy, no autoload reads - which is what makes this
## harness cheap: a hand-drawn map, detached units, direct calls.
##
##   1. nearest() and shootable_from() respect distance, range and walls
##   2. exposure_at() values a wall over junk over open ground
##   3. a healthy goblin takes a firing position over a safe crouch
##   4. a wounded goblin with no shot retreats to the covered cell
##   5. the watch penalty steers a walk around a held cone - and never
##      stops the advance when every way is watched
##   6. best_watch_sector() faces the arc the scouts can actually cross
##
## Units are built with `Unit.new()` + `setup()` and never added to the tree;
## AiPlan, Rules and Unit are load()ed after the first frame - the `-s` trap
## tools/test_hero_gameover.gd documents.
##
## Run: godot --headless --path . -s tools/test_aiplan.gd

const KIND_SCOUT := 0
const KIND_GOBLIN := 3

var _failed := false
var _aiplan: GDScript
var _unit_script: GDScript


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    %s" % label)
	else:
		printerr("  FAIL  %s" % label)
		_failed = true


## A 12x8 yard with a wall run and a junk pile mid-field:
##
##   x:  0123456789ab
##   y0  ............
##   y1  ............
##   y2  ....W.......
##   y3  ....W.......
##   y4  ....j.......
##   y5  ............
##   y6  ............
##   y7  ............
func _board() -> Board:
	var board := Board.new()
	board.set_level({
		"name": "AIPLAN YARD",
		"size": Vector2i(12, 8),
		"map": [
			"............",
			"............",
			"....W.......",
			"....W.......",
			"....j.......",
			"............",
			"............",
			"............",
		],
		"structures": [],
	})
	return board


func _unit(kind: int, cell: Vector2i) -> Node2D:
	var u: Node2D = _unit_script.new()
	u.setup(kind, cell)
	return u


func _never(_cell: Vector2i) -> bool:
	return false


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	_aiplan = load("res://scripts/AiPlan.gd") as GDScript
	_unit_script = load("res://scripts/Unit.gd") as GDScript
	_test_reach_and_walls()
	_test_exposure_ladder()
	_test_healthy_takes_the_shot()
	_test_wounded_retreats()
	_test_watched_lane()
	_test_watch_sector()
	print("\nRESULT: ", "FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


# --- 1. distance, range and walls --------------------------------------------

func _test_reach_and_walls() -> void:
	print("\n[1] nearest and shootable_from respect distance, range and walls")
	var board := _board()
	var near: Node2D = _unit(KIND_SCOUT, Vector2i(2, 6))
	var far: Node2D = _unit(KIND_SCOUT, Vector2i(9, 6))
	var targets: Array = [near, far]
	var picked: Node2D = _aiplan.nearest(Vector2i(0, 6), targets)
	_check(picked == near, "nearest picks the near man")

	# Range 3 from (0,6): the near scout at 2 is in reach, the far one is not.
	var in_reach: Array = _aiplan.shootable_from(board, Vector2i(0, 6), 3, targets)
	_check(in_reach.size() == 1 and in_reach[0] == near,
			"range gates the target list")
	# The wall's middle blocks: (3,3) to (5,3) crosses W at (4,3) with the run
	# continuing above and below, so there is no lean either.
	var walled: Array = _aiplan.shootable_from(board, Vector2i(3, 3), 3,
			[_unit(KIND_SCOUT, Vector2i(5, 3))])
	_check(walled.is_empty(), "the middle of a wall run blocks the shot")


# --- 2. cover is worth standing behind ---------------------------------------

func _test_exposure_ladder() -> void:
	print("\n[2] exposure values a wall over junk over open ground")
	var board := _board()
	var shooter: Node2D = _unit(KIND_SCOUT, Vector2i(2, 3))
	var scouts: Array = [shooter]
	# Facing the shooter from behind the wall run's east side: full cover.
	var walled: int = _aiplan.exposure_at(board, Vector2i(5, 3), 6, 2, scouts)
	# Beside the junk pile: half cover, shots land for half damage.
	var junked: int = _aiplan.exposure_at(board, Vector2i(5, 4), 6, 2, scouts)
	# Open ground on the same line.
	var open_e: int = _aiplan.exposure_at(board, Vector2i(5, 5), 6, 2, scouts)
	_check(walled < junked and junked < open_e,
			"wall %d < junk %d < open %d" % [walled, junked, open_e])


# --- 3 & 4. the two ends of the exposure weight -------------------------------

func _test_healthy_takes_the_shot() -> void:
	print("\n[3] a healthy goblin takes a firing position over a safe crouch")
	var board := _board()
	var goblin: Node2D = _unit(KIND_GOBLIN, Vector2i(8, 3))
	goblin.hp = 4
	var scout: Node2D = _unit(KIND_SCOUT, Vector2i(2, 5))
	var scouts: Array = [scout]
	var reach: Dictionary = board.flood_fill(goblin.cell, goblin.move_range, _never)
	var candidates: Array = reach.keys()
	candidates.append(goblin.cell)
	var dest: Vector2i = _aiplan.best_dest(board, goblin, reach, candidates,
			scouts, scout.cell, [] as Array[Dictionary])
	var shots: Array = _aiplan.shootable_from(board, dest, goblin.attack_range, scouts)
	_check(not shots.is_empty(), "the chosen cell %s has the shot" % dest)


func _test_wounded_retreats() -> void:
	print("\n[4] a wounded goblin with no shot retreats to the covered cell")
	var board := _board()
	var goblin: Node2D = _unit(KIND_GOBLIN, Vector2i(6, 3))
	goblin.hp = 1
	# The scout is far enough that no reachable cell has a shot back, and his
	# own line of fire covers the open ground but not the wall's shadow.
	var scout: Node2D = _unit(KIND_SCOUT, Vector2i(11, 3))
	scout.attack_range = 6
	var scouts: Array = [scout]
	var reach: Dictionary = board.flood_fill(goblin.cell, goblin.move_range, _never)
	var candidates: Array = reach.keys()
	candidates.append(goblin.cell)
	# Chase target far past the scout keeps "advance" and "retreat" distinct.
	var dest: Vector2i = _aiplan.best_dest(board, goblin, reach, candidates,
			scouts, scout.cell, [] as Array[Dictionary])
	var end_facing: int = Board.sector_from_to(reach[dest], dest) if reach.has(dest) \
			else goblin.facing_sector
	var exposure: int = _aiplan.exposure_at(board, dest, end_facing,
			goblin.arc_half, scouts)
	_check(exposure == 0, "he stands where the scout's fire cannot price him (%s)" % dest)


# --- 5. the watched lane ------------------------------------------------------

func _test_watched_lane() -> void:
	print("\n[5] the watch penalty steers the walk, and never stalls it")
	var board := _board()
	var goblin: Node2D = _unit(KIND_GOBLIN, Vector2i(0, 6))
	goblin.hp = 4
	var bait: Node2D = _unit(KIND_SCOUT, Vector2i(9, 6))
	var scouts: Array = [bait]
	var reach: Dictionary = board.flood_fill(goblin.cell, goblin.move_range, _never)
	var candidates: Array = reach.keys()
	candidates.append(goblin.cell)

	# A hand-drawn cone over the straight lane: the row itself, three tiles on.
	var cone := {Vector2i(2, 6): true, Vector2i(3, 6): true, Vector2i(4, 6): true}
	var watch_sets: Array[Dictionary] = [cone]
	var dest: Vector2i = _aiplan.best_dest(board, goblin, reach, candidates,
			scouts, bait.cell, watch_sets)
	_check(dest != goblin.cell, "he advances (%s -> %s)" % [goblin.cell, dest])
	var crossed := false
	for step: Vector2i in board.reconstruct_path(reach, dest):
		if cone.has(step):
			crossed = true
	_check(not crossed, "around the cone, not through it")

	# Every reachable cell watched: the penalty is uniform, so he still moves.
	var everywhere := {}
	for cell: Vector2i in reach:
		everywhere[cell] = true
	var pressed: Vector2i = _aiplan.best_dest(board, goblin, reach, candidates,
			scouts, bait.cell, [everywhere] as Array[Dictionary])
	_check(pressed != goblin.cell,
			"and when every way is watched he crosses anyway (%s)" % pressed)


# --- 6. the watch sector ------------------------------------------------------

func _test_watch_sector() -> void:
	print("\n[6] a dug-in goblin faces the ground the scouts can cross")
	var board := _board()
	var goblin: Node2D = _unit(KIND_GOBLIN, Vector2i(6, 6))
	# The approach is entirely to the goblin's east.
	var approach := {}
	for y in range(5, 8):
		for x in range(9, 12):
			approach[Vector2i(x, y)] = true
	var sector: int = _aiplan.best_watch_sector(board, goblin, approach)
	var covered: Dictionary = load("res://scripts/Rules.gd").overwatch_cells(
			board, goblin, sector)
	var hits := 0
	for cell: Vector2i in covered:
		if approach.has(cell):
			hits += 1
	var west: Dictionary = load("res://scripts/Rules.gd").overwatch_cells(
			board, goblin, (sector + 4) % 8)
	var away := 0
	for cell: Vector2i in west:
		if approach.has(cell):
			away += 1
	_check(hits > away, "the chosen arc covers the approach (%d vs %d cells)" % [hits, away])
