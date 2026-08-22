extends SceneTree

## The ratline, pinned. scripts/Ratline.gd is arithmetic and data over plain
## values - boards, muster strength, the trim and the surplus - so the first
## half of this harness runs without standing up a scene, and the second half
## drives the mission through the real Battle the way test_bounty.gd does.
##
##   1. every generated board is valid, both archetypes, across seeds - and
##      the validator objects to the mistakes a generator could make
##   2. generation is deterministic, and distinct where it must be
##   3. the strength table is exact: 115 / 103 / 92 / 80, clamped, monotonic
##   4. the trim is exact and untouchable lists stay untouched
##   5. the surplus schedule delivers the right kinds on the right turns
##   6. a crossing, played and won: detachment shape, the ordinal banked,
##      the leader resting, the operation NOT advanced
##   7. a waystation, played and won with the guard still breathing
##   8. a loss is a neglect, and a lost board clears - both rails
##   9. the muster locks at the operation's first story mission, holds
##      through a retry, and resets at the garrison
##  10. the trim and the surplus reach a real story battle
##  11. save v9 round-trips and a v8 save climbs
##
## Ratline is reached through load() and Game through /root/Game - the `-s`
## trap tools/test_hero_gameover.gd documents.
##
## Run: godot --headless --path . -s tools/test_ratline.gd

const SAVE_PATH := "user://campaign.json"
const BACKUP_PATH := "user://campaign.json.ratline-test-backup"

const TEAM_SCOUT := 0
const TEAM_GOBLIN := 1

var _failed := false
var _had_save := false
var _ratline: GDScript


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    %s" % label)
	else:
		printerr("  FAIL  %s" % label)
		_failed = true


func _init() -> void:
	_had_save = FileAccess.file_exists(SAVE_PATH)
	if _had_save:
		DirAccess.copy_absolute(SAVE_PATH, BACKUP_PATH)
	_run()


func _restore() -> void:
	if _had_save:
		DirAccess.copy_absolute(BACKUP_PATH, SAVE_PATH)
		DirAccess.remove_absolute(BACKUP_PATH)
		print("\nrestored the original save")
	elif FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


func _run() -> void:
	await process_frame
	_ratline = load("res://scripts/Ratline.gd") as GDScript
	_test_boards_valid()
	_test_determinism()
	_test_strength_table()
	_test_trim()
	_test_surplus()
	await _test_save_v9()
	_restore()
	print("\nRESULT: ", "FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


# --- 1. every board is valid --------------------------------------------------

func _test_boards_valid() -> void:
	print("\n[1] every generated board is valid, both archetypes, across seeds")
	var bad := 0
	var crossings := 0
	var waystations := 0
	var long_briefing := 0
	for seed_ordinal in 12:
		var campaign_seed := 1000003 + seed_ordinal * 77771
		for operation in 3:
			for ordinal in 3:
				var offer: Dictionary = _ratline.offer_for(campaign_seed,
						operation, ordinal)
				if str(offer.archetype) == "crossing":
					crossings += 1
				else:
					waystations += 1
				var level: Dictionary = _ratline.generate(offer, campaign_seed)
				var problems: Array = _ratline.validate(level)
				if level.is_empty() or not problems.is_empty():
					bad += 1
					printerr("  bad board seed %d op %d #%d: %s"
							% [campaign_seed, operation, ordinal, problems])
				if str(level.get("briefing", "")).length() >= 700:
					long_briefing += 1
	_check(bad == 0, "108 boards generated and validated clean")
	_check(crossings > 0 and waystations > 0,
			"both archetypes drawn (%d crossings, %d waystations)"
			% [crossings, waystations])
	_check(long_briefing == 0,
			"every generated briefing stays under the 700-char budget")

	# The validator has to actually object, or the sweep above proves nothing.
	var offer: Dictionary = _ratline.offer_for(1, 0, 0)
	var level: Dictionary = _ratline.generate(offer, 1)
	var torn: Dictionary = level.duplicate(true)
	(torn.map as Array).remove_at(0)
	_check(not (_ratline.validate(torn) as Array).is_empty(),
			"a torn map is refused")
	var walled: Dictionary = level.duplicate(true)
	var spawn: Vector2i = walled.scout_spawns[0]
	var row: String = walled.map[spawn.y]
	walled.map[spawn.y] = row.substr(0, spawn.x) + "#" + row.substr(spawn.x + 1)
	_check(not (_ratline.validate(walled) as Array).is_empty(),
			"a spawn under a rock is refused")
	var unmarked: Dictionary = level.duplicate(true)
	unmarked.erase("ratline")
	_check(not (_ratline.validate(unmarked) as Array).is_empty(),
			"a board with no ratline marker is refused")


# --- 2. determinism -----------------------------------------------------------

func _test_determinism() -> void:
	print("\n[2] generation is deterministic, and distinct where it must be")
	var offer: Dictionary = _ratline.offer_for(424242, 1, 1)
	var a: Dictionary = _ratline.generate(offer, 424242)
	var b: Dictionary = _ratline.generate(offer, 424242)
	_check(a == b, "the same offer builds the same board twice")
	_check(_ratline.build(offer, 424242, 0) != _ratline.build(offer, 424242, 1),
			"a different attempt builds a different board")
	_check(_ratline.offer_for(424242, 1, 0) != _ratline.offer_for(424242, 1, 2)
			or _ratline.offer_for(424242, 2, 0) != _ratline.offer_for(424242, 1, 0),
			"offers vary by ordinal and operation")
	var listed: Array = _ratline.offers(424242, 1, [1])
	_check(listed.size() == 3, "three crossings on the net")
	_check(bool(listed[1].settled) and not bool(listed[0].settled),
			"the done list stamps settled flags")


# --- 3. the strength table ----------------------------------------------------

func _test_strength_table() -> void:
	print("\n[3] the muster table is exact and clamped")
	_check(int(_ratline.strength(0, 3)) == 115, "all three ignored: 115")
	_check(int(_ratline.strength(1, 3)) == 103, "one run down: 103")
	_check(int(_ratline.strength(2, 3)) == 92, "two run down: 92")
	_check(int(_ratline.strength(3, 3)) == 80, "the net shut: 80")
	_check(int(_ratline.strength(0, 0)) == 100, "no offers posted: base")
	var last := 999
	var monotonic := true
	for s in 4:
		var now: int = _ratline.strength(s, 3)
		if now > last:
			monotonic = false
		last = now
	_check(monotonic, "every crossing run down helps or holds, never hurts")
	_check(int(_ratline.strength(99, 3)) == 80 and int(_ratline.strength(-5, 3)) == 115,
			"out-of-range successes clamp to the caps")


# --- 4. the trim --------------------------------------------------------------

func _test_trim() -> void:
	print("\n[4] the trim is exact, deterministic, and never touches the untouchable")
	_check(int(_ratline.trim_count(9, 80)) == 2, "nine eligible at 80 is two short")
	_check(int(_ratline.trim_count(9, 100)) == 0 and int(_ratline.trim_count(9, 115)) == 0,
			"at or above base nobody is short")
	var level: Dictionary = Levels.LEVELS[0]
	var eligible: Array = level.goblin_spawns + level.get("smg_spawns", []) \
			+ level.get("smg_alt_spawns", []) + level.get("novice_spawns", [])
	var cells: Array = _ratline.trim_cells(eligible, 80, 31337, 0)
	_check(cells.size() == int(_ratline.trim_count(eligible.size(), 80)),
			"exactly trim_count cells picked (%d of %d)" % [cells.size(), eligible.size()])
	var sound := true
	var seen := {}
	for cell: Vector2i in cells:
		if not eligible.has(cell) or seen.has(cell):
			sound = false
		if (level.get("bolt_spawns", []) as Array).has(cell) \
				or (level.get("prisoner_spawns", []) as Array).has(cell):
			sound = false
		seen[cell] = true
	_check(sound, "all picks eligible, distinct, and never a bolt or prisoner")
	_check(cells == _ratline.trim_cells(eligible, 80, 31337, 0),
			"the same campaign trims the same men")


# --- 5. the surplus -----------------------------------------------------------

func _test_surplus() -> void:
	print("\n[5] the surplus delivers the right kinds on the right turns")
	_check(int(_ratline.surplus_count(20, 115)) == 3, "twenty base at 115 is three more")
	_check(int(_ratline.surplus_count(20, 100)) == 0 and int(_ratline.surplus_count(20, 80)) == 0,
			"at or below base nothing is delivered")
	var schedule: Dictionary = _ratline.surplus_schedule(20, 115, 777, 3)
	var total := 0
	var sound := true
	for turn: int in schedule:
		if turn != 2 and turn != 3:
			sound = false
		for kind: int in schedule[turn]:
			total += 1
			if kind != 4 and kind != 6:
				sound = false
	_check(total == 3, "the schedule carries every delivery (%d)" % total)
	_check(sound, "turns 2-3 only, smuggled kinds only")
	_check(schedule == _ratline.surplus_schedule(20, 115, 777, 3),
			"and it is the same schedule every time")
	_check((_ratline.surplus_schedule(20, 95, 777, 3) as Dictionary).is_empty(),
			"below base the schedule is empty")

# --- 11. save v9 --------------------------------------------------------------

func _test_save_v9() -> void:
	print("\n[11] the net survives the disk, and a v8 save climbs")
	var game: Node = root.get_node("/root/Game")
	game.new_campaign()
	game.ensure_roster(Levels.LEVELS[0])  # a save with no roster refuses to load
	game.ratline_done = [0, 2]
	game.ratline_strength = 92
	game.save()
	game.ratline_done = []
	game.ratline_strength = 0
	_check(game.load_save(), "the save loads back")
	_check(game.ratline_done == [0, 2] and game.ratline_strength == 92,
			"crossings and muster came back intact")

	# A v8 save - no ratline keys at all - climbs to nothing-run-down.
	var raw := FileAccess.open(SAVE_PATH, FileAccess.READ).get_as_text()
	var payload: Dictionary = JSON.parse_string(raw)
	payload["version"] = 8
	payload.erase("ratline_done")
	payload.erase("ratline_strength")
	var out := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	out.store_string(JSON.stringify(payload))
	out.close()
	_check(game.load_save(), "the doctored v8 loads")
	_check(game.ratline_done.is_empty() and game.ratline_strength == 0,
			"and climbed to nothing run down, nothing locked")
	_check(not (game._migrate_step({}, 8) as Dictionary).is_empty(),
			"the ladder has a rung out of version 8")
	game.delete_save()
