extends SceneTree

## The mission clock, pinned. Levels.pressure_wave is pure arithmetic over the
## level dict, so every property is asserted without standing up a scene:
##
##   1. the cadence: first_turn, every, and the list of lists as its own cap
##   2. the while-gate: waves flow while the objective stands and stop the
##      refresh after it is done - the player closes the tap by playing
##   3. the after-gate: silent until the gate opens, then anchored to the
##      turn it opened rather than to a schedule the squad never heard
##   4. the shipped tables: the Scrapline's mast calls and Outpost 7's
##      withdrawal is chased, exactly as their comments promise
##   5. the validator refuses the mistakes a table could ship with
##
## Run: godot --headless --path . -s tools/test_pressure.gd

var _failed := false


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    %s" % label)
	else:
		printerr("  FAIL  %s" % label)
		_failed = true


func _level(pressure: Dictionary) -> Dictionary:
	return {
		"name": "TEST",
		"objectives": [{"kind": "destroy"}, {"kind": "destroy"}],
		"pressure": pressure,
	}


func _init() -> void:
	_run()


func _run() -> void:
	_test_cadence()
	_test_while_gate()
	_test_after_gate()
	_test_shipped_tables()
	_test_validator()
	print("\nRESULT: ", "FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


func _test_cadence() -> void:
	print("\n[1] the cadence, and the wave list as its own cap")
	var level := _level({
		"while_objective": 1, "first_turn": 3, "every": 3,
		"edge": "east", "units": [[5], [6, 6]],
	})
	var open := [false, false]
	_check(Levels.pressure_wave(level, 1, open).is_empty(), "quiet on turn 1")
	_check(Levels.pressure_wave(level, 2, open).is_empty(), "quiet on turn 2")
	var first := Levels.pressure_wave(level, 3, open)
	_check(not first.is_empty() and first.units == [5], "the first wave lands on turn 3")
	_check(str(first.edge) == "east", "on the named rim")
	_check(Levels.pressure_wave(level, 4, open).is_empty(), "nothing between beats")
	var second := Levels.pressure_wave(level, 6, open)
	_check(not second.is_empty() and second.units == [6, 6], "the second on turn 6")
	_check(Levels.pressure_wave(level, 9, open).is_empty(),
			"and the tap runs dry when the list does")
	_check(Levels.pressure_wave({"name": "BARE"}, 3, open).is_empty(),
			"a level with no table has no clock")


func _test_while_gate() -> void:
	print("\n[2] the while-gate closes when the objective is done")
	var level := _level({
		"while_objective": 1, "first_turn": 2, "every": 2,
		"units": [[4], [4], [4], [4]],
	})
	_check(not Levels.pressure_wave(level, 2, [false, false]).is_empty(),
			"waves flow while the mast stands")
	_check(Levels.pressure_wave(level, 4, [false, true]).is_empty(),
			"and stop the refresh after it drops")
	_check(not Levels.pressure_wave(level, 2, [true, false]).is_empty(),
			"the other objective's state is nobody's business")


func _test_after_gate() -> void:
	print("\n[3] the after-gate anchors to the turn it opened")
	var level := _level({
		"after_objective": 0, "first_turn": 2, "every": 2,
		"units": [[4, 6], [6]],
	})
	var done := [true, false]
	_check(Levels.pressure_wave(level, 6, done, -1).is_empty(),
			"silent while the gate is shut, whatever the turn")
	_check(Levels.pressure_wave(level, 8, done, 7).is_empty(),
			"one turn after a turn-7 blast is too soon")
	var chase := Levels.pressure_wave(level, 9, done, 7)
	_check(not chase.is_empty() and chase.units == [4, 6],
			"the chase starts two turns after the turn-7 blast")
	var second := Levels.pressure_wave(level, 11, done, 7)
	_check(not second.is_empty() and second.units == [6], "and keeps its cadence")
	_check(Levels.pressure_wave(level, 13, done, 7).is_empty(), "then runs dry")


func _test_shipped_tables() -> void:
	print("\n[4] the shipped tables do what their comments promise")
	var scrapline: Dictionary = Levels.LEVELS[1]
	_check(scrapline.has("pressure"), "THE SCRAPLINE carries a clock")
	_check(int(scrapline.pressure.while_objective) == 1,
			"gated on the relay objective")
	var wave := Levels.pressure_wave(scrapline, 3, [false, false])
	_check(not wave.is_empty(), "the mast calls its first patrol on turn 3")
	_check(Levels.pressure_wave(scrapline, 6, [false, true]).is_empty(),
			"a dropped mast calls nobody")

	var outpost: Dictionary = Levels.LEVELS[2]
	_check(outpost.has("pressure"), "OUTPOST 7 carries one")
	_check(int(outpost.pressure.after_objective) == 0,
			"gated on the stores going up")
	_check(Levels.pressure_wave(outpost, 9, [false, false], -1).is_empty(),
			"quiet while the stores stand")
	_check(not Levels.pressure_wave(outpost, 9, [true, false], 7).is_empty(),
			"and chasing two turns after they blow")

	# Every fighting kind in every shipped wave is a Thirst fighter.
	for idx in Levels.LEVELS.size():
		var level: Dictionary = Levels.LEVELS[idx]
		if not level.has("pressure"):
			continue
		for wave_kinds: Array in level.pressure.units:
			for kind in wave_kinds:
				_check(int(kind) >= 3 and int(kind) <= 7,
						"%s wave kind %s is a fighter" % [level.name, str(kind)])


func _test_validator() -> void:
	print("\n[5] the validator refuses what a table could ship with")
	var good := _level({"while_objective": 1, "units": [[4]]})
	_check(Levels._validate_pressure(good, "good"), "a sound table passes")
	_check(not Levels._validate_pressure(
			_level({"while_objective": 5, "units": [[4]]}), "t"),
			"a gate past the objective list is refused")
	_check(not Levels._validate_pressure(
			_level({"while_objective": 0, "after_objective": 1, "units": [[4]]}), "t"),
			"both gates at once is refused")
	_check(not Levels._validate_pressure(
			_level({"edge": "up", "units": [[4]]}), "t"),
			"an unknown rim is refused")
	_check(not Levels._validate_pressure(
			_level({"units": []}), "t"),
			"a clock with no waves is refused")
	_check(not Levels._validate_pressure(
			_level({"units": [[8]]}), "t"),
			"conscripting the CIVILIAN kind is refused")
