extends SceneTree

## The career ladder, pinned. scripts/Career.gd is arithmetic over plain ints,
## so everything here runs without standing up a scene - and unlike most
## harnesses this one can name Career and Gear at parse time, because neither
## names an autoload (Career names nothing at all; Gear names only Roll).
##
##   1. the XP curve: every anchor exact, strictly increasing, capped
##   2. level_for_xp inverts the curve, and xp_to_next counts honestly
##   3. the four perk gates, and gates_crossed staying a subset of them
##   4. per-level growth: every level pays exactly one +1, by parity
##   5. chevrons: one per 20 levels, capped at five
##
## Run: godot --headless --path . -s tools/test_career.gd

var _failed := false


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    %s" % label)
	else:
		printerr("  FAIL  %s" % label)
		_failed = true


func _init() -> void:
	_test_curve()
	_test_inverse()
	_test_gates()
	_test_growth()
	_test_chevrons()
	print("\nRESULT: ", "FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


# --- 1. the curve ---------------------------------------------------------------

func _test_curve() -> void:
	print("\n[1] the XP curve: anchors exact, strictly increasing, capped")
	var anchors := {1: 0, 2: 1, 5: 7, 10: 22, 15: 42, 20: 68, 25: 99,
			30: 136, 50: 337, 100: 1226}
	for level: int in anchors:
		_check(Career.xp_for_level(level) == int(anchors[level]),
				"T(%d) == %d (got %d)" % [level, int(anchors[level]),
						Career.xp_for_level(level)])
	var rising := true
	for level in range(2, Career.MAX_LEVEL + 1):
		if Career.xp_for_level(level) <= Career.xp_for_level(level - 1):
			rising = false
	_check(rising, "strictly increasing across 1..100")
	_check(Career.xp_for_level(0) == 0 and Career.xp_for_level(-5) == 0,
			"below the ladder clamps to level 1's 0")
	_check(Career.xp_for_level(101) == Career.xp_for_level(100),
			"above the ladder clamps to level 100")


# --- 2. the inverse -------------------------------------------------------------

func _test_inverse() -> void:
	print("\n[2] level_for_xp inverts the curve; xp_to_next counts honestly")
	var round_trip := true
	for level in range(1, Career.MAX_LEVEL + 1):
		# Exactly at the threshold, and one short of the next.
		if Career.level_for_xp(Career.xp_for_level(level)) != level:
			round_trip = false
		if level < Career.MAX_LEVEL \
				and Career.level_for_xp(Career.xp_for_level(level + 1) - 1) != level:
			round_trip = false
	_check(round_trip, "threshold and threshold-minus-one land on the level")
	_check(Career.level_for_xp(0) == 1, "0 xp is level 1")
	_check(Career.level_for_xp(-3) == 1, "negative xp is still level 1")
	_check(Career.level_for_xp(999999) == Career.MAX_LEVEL,
			"xp past the top buys level 100 and no more")
	_check(Career.xp_to_next(0) == 1, "level 1 owes 1 xp for level 2")
	_check(Career.xp_to_next(22) == Career.xp_for_level(11) - 22,
			"a fresh level 10 owes the whole gap to 11")
	_check(Career.xp_to_next(1226) == -1, "the cap answers -1")
	_check(Career.xp_to_next(2000) == -1, "past the cap still answers -1")


# --- 3. the gates ---------------------------------------------------------------

func _test_gates() -> void:
	print("\n[3] the four perk gates")
	_check(Career.PERK_LEVELS == ([5, 15, 30, 50] as Array[int]),
			"the gates are 5/15/30/50")
	_check(Career.perk_gate(5) == 1 and Career.perk_gate(15) == 2
			and Career.perk_gate(30) == 3 and Career.perk_gate(50) == 4,
			"each gate answers its ordinal")
	_check(Career.perk_gate(1) == 0 and Career.perk_gate(20) == 0
			and Career.perk_gate(100) == 0, "every other level answers 0")
	_check(Career.gates_crossed(4, 30) == [5, 15, 30],
			"4 -> 30 crosses three gates")
	_check(Career.gates_crossed(1, 100) == [5, 15, 30, 50],
			"1 -> 100 crosses all four")
	_check(Career.gates_crossed(5, 14).is_empty(),
			"5 -> 14 crosses none (5 was already held)")
	_check(Career.gates_crossed(30, 30).is_empty(), "standing still crosses none")
	# The queue-flood proof: whatever the jump, the answer is a subset of the
	# four gate levels.
	var subset := true
	for old_level in range(0, 101, 7):
		for new_level in range(old_level, 101, 11):
			for crossed: int in Career.gates_crossed(old_level, new_level):
				if not Career.PERK_LEVELS.has(crossed):
					subset = false
	_check(subset, "gates_crossed is always a subset of PERK_LEVELS")


# --- 4. per-level growth --------------------------------------------------------

func _test_growth() -> void:
	print("\n[4] per-level growth: every level pays exactly one +1, by parity")
	var sums_hold := true
	var steps_hold := true
	for level in range(1, Career.MAX_LEVEL + 1):
		var acc := Career.accuracy_bonus_at(level)
		var hp := Career.hp_bonus_at(level)
		# Together the two bonuses account for every level-up once...
		if acc + hp != level - 1:
			sums_hold = false
		# ...and each single level moves exactly one of them by exactly 1.
		if level > 1:
			var acc_step := acc - Career.accuracy_bonus_at(level - 1)
			var hp_step := hp - Career.hp_bonus_at(level - 1)
			if acc_step + hp_step != 1 or acc_step < 0 or hp_step < 0 \
					or (level % 2 == 0 and acc_step != 1) \
					or (level % 2 == 1 and hp_step != 1):
				steps_hold = false
	_check(sums_hold, "acc_bonus(L) + hp_bonus(L) == L - 1 across 1..100")
	_check(steps_hold, "even levels pay accuracy, odd levels pay HP, 1 each")
	_check(Career.accuracy_bonus_at(2) == 1 and Career.accuracy_bonus_at(10) == 5
			and Career.accuracy_bonus_at(30) == 15
			and Career.accuracy_bonus_at(100) == 50,
			"accuracy anchors: 1/5/15/50 at L2/10/30/100")
	_check(Career.hp_bonus_at(3) == 1 and Career.hp_bonus_at(21) == 10
			and Career.hp_bonus_at(100) == 49,
			"HP anchors: 1/10/49 at L3/21/100")
	_check(Career.accuracy_bonus_at(1) == 0 and Career.hp_bonus_at(1) == 0,
			"level 1 has earned nothing")


# --- 5. chevrons ----------------------------------------------------------------

func _test_chevrons() -> void:
	print("\n[5] chevrons: one per 20 levels, capped at five")
	var table := {0: 0, 1: 0, 19: 0, 20: 1, 39: 1, 40: 2, 60: 3, 80: 4,
			99: 4, 100: 5}
	var all_match := true
	for level: int in table:
		if Career.chevrons_for(level) != int(table[level]):
			all_match = false
	_check(all_match, "the chevron table holds at every boundary")
	_check(Career.chevrons_for(140) == Career.CHEVRON_MAX,
			"an impossible level still caps at %d" % Career.CHEVRON_MAX)
	_check(Career.level_label(12) == "Level 12", "the label is 'Level %d'")
