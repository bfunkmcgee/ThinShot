extends SceneTree

## THE RANGE, pinned. Five things the real-time mode rests on, checked headless:
##   1. the map data validates and its rim can be spawned from on every side
##   2. the wave director is deterministic for a seed and honours its unlocks -
##      wave one is rifles, never the gun or the brute
##   3. the range's roll delegates to Rules.hit_chance and charges the stride
##   4. the player's step slides along a rock instead of sticking to it, and a
##      fighter walked in from the edge closes to range and opens fire
##   5. Rodar's death ends the run: the panel shows and the best-run file
##      records it - with the player's own file moved aside and put back
##
## NOTHING from scripts/ is preloaded (the -s trap tools/test_hero_gameover.gd
## documents): ArenaFoe and ArenaWaves name Unit, Unit names the Game autoload,
## and a preload here would compile all of it before the autoloads exist. So
## every script is load()ed after the first frame, and the scene is
## instantiated, which compiles its scripts only once the tree is live. Board
## may be named directly: it reaches for no autoload.
##
## Run: godot --headless --path . -s tools/test_arena.gd

const KIND_GOBLIN := 3
const KIND_HERO := 9
const KIND_GOBLIN_MG := 15
const KIND_GOBLIN_BRUTE := 16
const KIND_SCOUT := 0
const ARENA_SAVE := "user://arena.json"
const BACKUP := "user://arena.json.test-backup"

var _failed := false
var _had_save := false


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    %s" % label)
	else:
		printerr("  FAIL  %s" % label)
		_failed = true


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame  # autoloads up before anything from scripts/ compiles
	var data := load("res://scripts/ArenaData.gd") as GDScript
	var waves_script := load("res://scripts/ArenaWaves.gd") as GDScript
	var foe_script := load("res://scripts/ArenaFoe.gd") as GDScript
	var rules := load("res://scripts/Rules.gd") as GDScript
	var units := load("res://scripts/Unit.gd") as GDScript

	_test_data(data)
	_test_waves(waves_script)
	_test_roll(rules, units)
	await _test_scene(foe_script)

	print("\nRESULT: ", "FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


# --- 1. the ground -----------------------------------------------------------

func _test_data(data: GDScript) -> void:
	print("\n[1] the range validates, and the Thirst can come on from every side")
	data.call("validate")  # asserts on failure; reaching the next line is the pass
	_check(true, "ArenaData.validate() raised nothing")
	var range_map: Dictionary = data.get_script_constant_map()["RANGE"]
	var rim: Array = data.call("spawn_rim", range_map)
	var grid: Vector2i = range_map.size
	var north := rim.filter(func(c: Vector2i) -> bool: return c.y == 0).size()
	var south := rim.filter(func(c: Vector2i) -> bool: return c.y == grid.y - 1).size()
	var west := rim.filter(func(c: Vector2i) -> bool: return c.x == 0).size()
	var east := rim.filter(func(c: Vector2i) -> bool: return c.x == grid.x - 1).size()
	_check(north > 0 and south > 0 and west > 0 and east > 0,
			"walkable rim on all four sides (N %d, S %d, W %d, E %d)" % [north, south, west, east])
	var spawn: Vector2i = data.get_script_constant_map()["PLAYER_SPAWN"]
	_check(not rim.has(spawn), "Rodar does not start on the rim (%s)" % spawn)


# --- 2. the waves ------------------------------------------------------------

func _test_waves(waves_script: GDScript) -> void:
	print("\n[2] the director is deterministic for a seed and honours its unlocks")
	var w: Node = waves_script.new()
	w.rng.seed = 7
	var a: Array = w.compose(3)
	w.rng.seed = 7
	var b: Array = w.compose(3)
	_check(a == b and not a.is_empty(),
			"wave 3 composes the same way twice from seed 7 (%d fighters)" % a.size())
	w.rng.seed = 11
	var first: Array = w.compose(1)
	_check(not first.is_empty(), "wave 1 fields somebody (%d)" % first.size())
	_check(not first.has(KIND_GOBLIN_MG) and not first.has(KIND_GOBLIN_BRUTE),
			"wave 1 is rifles: no gun, no brute")
	var later: Array = w.compose(9)
	_check(later.size() > first.size(), "wave 9 is bigger than wave 1 (%d > %d)"
			% [later.size(), first.size()])
	var cap := int(waves_script.get_script_constant_map()["MAX_ALIVE"])
	_check(cap >= 6 and cap <= 20, "the alive cap is a readable board (%d)" % cap)
	w.free()


# --- 3. the roll -------------------------------------------------------------

func _test_roll(rules: GDScript, units: GDScript) -> void:
	print("\n[3] the range's roll is hit_chance, less the stride")
	var k := rules.get_script_constant_map()
	var board := Board.new()
	board.set_level({"size": Vector2i(6, 3), "map": ["......", "......", "......"],
			"structures": []})
	var shooter: Node2D = units.new()
	shooter.setup(KIND_SCOUT, Vector2i(2, 1))
	var target: Node2D = units.new()
	target.setup(KIND_SCOUT, Vector2i(3, 1))
	# Turn the target until the shooter is in its front arc: no flank.
	for sector in 8:
		target.facing_sector = sector
		if not rules.call("is_flanking", shooter, target):
			break
	var still: int = rules.call("hit_chance", board, shooter, target, 0, 0)
	_check(rules.call("arena_hit_chance", board, shooter, target, false) == still,
			"standing still it is hit_chance (%d)" % still)
	_check(rules.call("arena_hit_chance", board, shooter, target, true)
			== still - int(k.ARENA_MOVING_ACCURACY),
			"walking costs %d" % int(k.ARENA_MOVING_ACCURACY))
	shooter.free()
	target.free()
	board.free()


# --- 4 & 5. the scene --------------------------------------------------------

func _test_scene(foe_script: GDScript) -> void:
	print("\n[4] Rodar walks the range and the Thirst closes on him")
	_had_save = FileAccess.file_exists(ARENA_SAVE)
	if _had_save:
		DirAccess.copy_absolute(ProjectSettings.globalize_path(ARENA_SAVE),
				ProjectSettings.globalize_path(BACKUP))
	var runs_before := _runs_recorded()

	var arena: Node2D = (load("res://scenes/Arena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	await process_frame
	await process_frame
	var player: Node2D = arena.player
	_check(player != null and player.is_alive(), "Rodar stands on the range")
	_check(player.kind == KIND_HERO and player.mag_size == int(arena.RANGE_MAG)
			and player.max_hp == int(arena.RANGE_HP) and player.hp == player.max_hp,
			"as himself, with the range's issue: kind %d, %d HP, %d in the magazine"
			% [player.kind, player.max_hp, player.mag_size])

	# Wall slide. A rock at (7,6); stand him at (7,7) and push straight into it.
	var board: Board = arena.board
	player.position = board.cell_to_global(Vector2i(7, 7))
	player.cell = Vector2i(7, 7)
	var into_rock := board.cell_to_global(Vector2i(7, 6)) - player.position
	var before := player.position
	arena._try_step(into_rock)
	_check(player.position == before and player.cell == Vector2i(7, 7),
			"a step straight into the rock is refused")
	arena._try_step(Vector2(64.0, 0.0))
	_check(player.position != before and board.is_walkable(player.cell),
			"the same push along the free axis moves him (now %s)" % player.cell)

	# One fighter, walked in from the north edge by hand.
	var foe: Node2D = arena.spawn_foe(KIND_GOBLIN, Vector2i(10, 1))
	var st: Dictionary = arena.foe_states[foe]
	var states: Dictionary = foe_script.get_script_constant_map()["State"]
	var reached := false
	var ticks := 0
	while ticks < 600 and not reached:
		foe_script.call("tick", arena, foe, st, 0.05)
		reached = int(st.state) == int(states.AIMING) or int(st.state) == int(states.FIRING)
		ticks += 1
	_check(reached, "he closes to range and raises his rifle (%d ticks, state %d)"
			% [ticks, int(st.state)])
	_check(Board.manhattan(foe.cell, player.cell) <= foe.attack_range,
			"from inside his own reach (%d <= %d)"
			% [Board.manhattan(foe.cell, player.cell), foe.attack_range])

	print("\n[5] his death ends the run and the best-run file records it")
	player.take_damage(999)
	_check(not player.is_alive(), "999 is enough")
	await create_timer(1.8).timeout
	_check(bool(arena.game_over), "the run is over")
	_check(arena.game_over_panel.visible, "and the panel says so")
	_check(_runs_recorded() == runs_before + 1,
			"arena.json counts one more run (%d)" % _runs_recorded())
	arena.queue_free()
	await process_frame
	_restore()


func _runs_recorded() -> int:
	if not FileAccess.file_exists(ARENA_SAVE):
		return 0
	var f := FileAccess.open(ARENA_SAVE, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return int(parsed.get("runs", 0)) if typeof(parsed) == TYPE_DICTIONARY else 0


func _restore() -> void:
	if _had_save:
		DirAccess.copy_absolute(ProjectSettings.globalize_path(BACKUP),
				ProjectSettings.globalize_path(ARENA_SAVE))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BACKUP))
		print("\nrestored the player's own best-run file")
	elif FileAccess.file_exists(ARENA_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ARENA_SAVE))
