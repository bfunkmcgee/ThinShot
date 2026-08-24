extends SceneTree

## The shooting rules, pinned. Every assertion here runs against the real
## scripts/Rules.gd and the real Board, on geometry built for the purpose - a
## wall placed where the rule needs a wall, rather than whichever rock a
## shipped level happens to have near a spawn.
##
## Eleven things are checked, and they are the ones the game rests on. The
## numbering matches what the run prints, which is why it skips 8 - that sweep
## lives in tools/check_cover_rules.gd, where it can run over the shipped maps:
##   1. flanking and cover are mutually exclusive - a flanked target has NONE,
##      takes the flank bonus, and does NOT also charge the full-cover penalty
##   2. the long-shot threshold is `attack_range / 2` in INTEGER division, so a
##      5-tile weapon is comfortable to 2 exactly like a 4-tile one
##   3. the [20, 99] clamp on the position, inclusive at both ends, the pin's
##      quarter taken after it, and Marksman's exemption
##   4. cover halves damage with `>>`, which is why every base damage is even
##   5. Executioner adds its point on a flank and can never add it through cover
##   6. peek_origin leans around the END of a wall run and not around its MIDDLE
##   7. the promise equals the round: shot_preview and damage_for return the
##      same number over every combination of flank, cover, perk and bonus
##   8. cover_at and effective_cover are one rule: swept over every cell,
##      shooter, facing and arc width, and against the spelling effective_cover
##      had before it was decomposed - so the AI, which can only ask the
##      cell-and-facing form, is scoring what the resolver will apply
##      (in tools/check_cover_rules.gd, over all seven shipped maps)
##   9. a broken unit surrenders where somebody can take it and runs where
##      nobody can; the district's opinion moves that line, and the Marksman
##      does neither at any reputation
##  10. a clean kill costs nothing; every other conduct is priced
##  11. the grenadier alone puts ordnance further than an arm can throw it,
##      and not further than the Thirst's longest weapon can answer
##  12. most of the defeated are dead, the survivors get harder to finish and
##      weaker every time, and a decisive blow settles it outright
##
## Nothing here needs a scene, a save, or a turn. Board's spatial predicates run
## on a detached `Board.new()` (tools/check_cover_rules.gd sweeps all seven maps
## that way) and Rules takes the board as an argument, so the whole file is
## arithmetic over hand-drawn maps.
##
## NOTHING from scripts/ is preloaded, deliberately - the `-s` trap that
## tools/test_hero_gameover.gd documents at length. Rules' signatures name Unit,
## Unit names the Game autoload, and preloading Rules here would compile Unit
## before the autoloads exist, fail, and leave the broken script cached for
## everything that follows. So Rules.gd and Unit.gd are load()ed after the first
## frame. Board may be named directly: it reaches for no autoload.
##
## Units are built with `Unit.new()` + `setup()` and are never added to the
## tree - `sprite` is @onready and `_ready()` dereferences it immediately, so a
## bare unit is safe only while it stays detached.
##
## Run: godot --headless --path . -s tools/test_rules.gd

# Raw ordinals, matching test_save_load.gd's style: Unit.Kind cannot be named
# from here for the reason above.
const KIND_SCOUT := 0
const KIND_CIVILIAN := 8
const KIND_NAMES: Array[String] = [
	"SCOUT", "TEAM_LEAD", "MACHINEGUNNER", "GOBLIN", "GOBLIN_SMG",
	"GOBLIN_SMG_ALT", "GOBLIN_REVOLVER", "GOBLIN_BOLT", "CIVILIAN", "HERO",
	# The five specialist Kestrels. Listed so the sweeps below actually reach
	# them - every one of these is indexed BY ORDINAL, so a short table does
	# not fail, it silently stops checking at HERO.
	"GRENADIER", "MARKSMAN", "BREACHER", "MEDIC", "TECHNICIAN",
	# The Thirst's belt-fed gunner, first fielded in the second operation.
	"GOBLIN_MG",
]

var _failed := false
var _rules: GDScript = null   # scripts/Rules.gd
var _units: GDScript = null   # scripts/Unit.gd
var _k: Dictionary = {}       # Rules' constants, by name


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    %s" % label)
	else:
		printerr("  FAIL  %s" % label)
		_failed = true


func _init() -> void:
	_run()


# --- Calling into Rules ------------------------------------------------------
# Rules is a script resource here rather than a named class, so its statics are
# reached through call(). Wrapped once so the assertions below read like the
# rules they are checking.

func _chance(board: Board, a: Node2D, t: Node2D, mod := 0, insp := 0) -> int:
	return _rules.call("hit_chance", board, a, t, mod, insp)


func _flanking(a: Node2D, t: Node2D) -> bool:
	return _rules.call("is_flanking", a, t)


func _cover(board: Board, a: Node2D, t: Node2D) -> int:
	return _rules.call("effective_cover", board, a, t)


## The same rule with no units in it - a cell, a facing, an arc, and where the
## shot comes from. The AI scores candidate cells through this one.
func _cover_at(board: Board, cell: Vector2i, facing_sector: int, arc_half: int,
		from_cell: Vector2i) -> int:
	return _rules.call("cover_at", board, cell, facing_sector, arc_half, from_cell)


func _peeking(board: Board, a: Node2D, t: Node2D) -> bool:
	return _rules.call("is_peeking", board, a, t)


## The damage rule itself, no longer mirrored. Until step 5 this file carried
## its own copy of _fire_round's if/elif, because the real one lived inside a
## 90-line coroutine that fires effects and awaits timers and could not be
## called from a headless test. `Rules.damage_for` is that rule lifted out
## whole, so the assertions below now run against the shipping code rather
## than against a copy of it that had to be kept honest by hand.
func _damage(board: Board, a: Node2D, t: Node2D, bonus := 0, ignore_cover := false) -> int:
	return _rules.call("damage_for", board, a, t, bonus, ignore_cover)


## The other half of the same rule: what the panel promises before the trigger.
func _preview(board: Board, a: Node2D, t: Node2D, mod := 0, insp := 0,
		bonus := 0, ignore_cover := false) -> Dictionary:
	return _rules.call("shot_preview", board, a, t, mod, insp, bonus, ignore_cover)


# --- Building the fixtures ---------------------------------------------------

## A detached board from ASCII. '#' is a wall, '.' is open - the same two
## characters the shipped levels use, read by the same set_level().
func _board(rows: Array) -> Board:
	var b := Board.new()
	b.set_level({
		"size": Vector2i(str(rows[0]).length(), rows.size()),
		"map": rows,
		"structures": [],
	})
	return b


func _mk(kind: int, cell: Vector2i, perks: Array = []) -> Node2D:
	var u: Node2D = _units.new()
	u.setup(kind, cell)  # safe outside the tree; _update_sprite guards on null
	u.perks = perks
	return u


## Turn `target` until `shooter` is inside its front arc - a covered shot.
## Assigns the sector directly, the way test_progression does, so no sprite
## work is attempted on a detached unit.
func _face_covered(target: Node2D, shooter: Node2D) -> bool:
	for sector in 8:
		target.facing_sector = sector
		if not _flanking(shooter, target):
			return true
	return false


## The opposite: a facing that leaves `shooter` squarely on the flank.
func _face_flanked(target: Node2D, shooter: Node2D) -> bool:
	for sector in 8:
		target.facing_sector = sector
		if _flanking(shooter, target):
			return true
	return false


## The invariant the whole cover model rests on, swept over a board: there is
## no cell and no facing at which a unit is both flanked and behind cover.
func _sweep_exclusive(board: Board, label: String) -> void:
	var target: Node2D = _mk(KIND_SCOUT, Vector2i.ZERO)
	var shooter: Node2D = _mk(KIND_SCOUT, Vector2i.ZERO)
	var pairs := 0
	var flanked := 0
	var violations := 0
	for ty in board.size.y:
		for tx in board.size.x:
			var t := Vector2i(tx, ty)
			if not board.is_walkable(t):
				continue
			target.cell = t
			for sy in board.size.y:
				for sx in board.size.x:
					var s := Vector2i(sx, sy)
					if s == t or not board.is_walkable(s):
						continue
					shooter.cell = s
					for sector in 8:
						target.facing_sector = sector
						pairs += 1
						if not _flanking(shooter, target):
							continue
						flanked += 1
						if _cover(board, shooter, target) != Board.CoverLevel.NONE:
							violations += 1
	_check(violations == 0,
			"%s: flanked implies no cover (%d of %d flanked pairs broke it)"
			% [label, violations, flanked])
	_check(flanked > 0, "%s: the sweep found flanks to check (%d of %d pairs)"
			% [label, flanked, pairs])
	target.free()
	shooter.free()


## The spelling `effective_cover` had before it was decomposed, with
## `covers_sector`'s body written out in place so this depends on neither of the
## two statics the decomposition introduced. Kept for the same reason
## `_old_resolver_order` is kept: "expressing the rule through cover_at moved no
## number" is a claim, and only a sweep that finds no daylight is a proof.
func _old_effective_cover(board: Board, a: Node2D, t: Node2D) -> int:
	var sector := Board.sector_from_to(t.cell, a.cell)
	var in_arc: bool = sector < 0 \
			or absi(wrapi(sector - int(t.facing_sector) + 4, 0, 8) - 4) <= int(t.arc_half)
	if not in_arc:
		return Board.CoverLevel.NONE
	return board.cover_between(a.cell, t.cell)


## The decomposition, proved. `Rules.effective_cover` is now a single call to
## `Rules.cover_at` with a live target's own cell, facing and arc, which is what
## lets the AI ask the identical question about a cell it has not moved to yet.
## Three answers are compared at every combination of target cell, shooter cell,
## facing and arc width the board admits: the historical spelling above, the
## current `effective_cover`, and `cover_at` called with the target's numbers by
## hand. All three must agree everywhere.
##
## Arc widths run 0..4 rather than only the two the game issues (1, and 2 for a
## Sentinel), because `cover_at` takes the width as an argument and a caller is
## free to hand it any of them - 0 is a single sector, 4 is the whole circle and
## means cover always applies.
func _sweep_cover_at(board: Board, label: String) -> void:
	var target: Node2D = _mk(KIND_SCOUT, Vector2i.ZERO)
	var shooter: Node2D = _mk(KIND_SCOUT, Vector2i.ZERO)
	var combos := 0
	var with_cover := 0
	var drift_live := 0   # cover_at disagreeing with effective_cover
	var drift_old := 0    # effective_cover disagreeing with the old spelling
	for ty in board.size.y:
		for tx in board.size.x:
			var t := Vector2i(tx, ty)
			if not board.is_walkable(t):
				continue
			target.cell = t
			for sy in board.size.y:
				for sx in board.size.x:
					var s := Vector2i(sx, sy)
					if not board.is_walkable(s):
						continue
					shooter.cell = s
					for sector in 8:
						target.facing_sector = sector
						for half in 5:
							target.arc_half = half
							combos += 1
							var live := _cover(board, shooter, target)
							if _cover_at(board, t, sector, half, s) != live:
								drift_live += 1
							if _old_effective_cover(board, shooter, target) != live:
								drift_old += 1
							if live != Board.CoverLevel.NONE:
								with_cover += 1
	_check(drift_live == 0,
			"%s: cover_at answers exactly what effective_cover does (%d of %d combinations differed)"
			% [label, drift_live, combos])
	_check(drift_old == 0,
			"%s: and both answer what the pre-decomposition spelling did (%d differed)"
			% [label, drift_old])
	_check(with_cover > 0,
			"%s: the sweep found cover to check, not just empty ground (%d of %d combinations had some)"
			% [label, with_cover, combos])
	target.free()
	shooter.free()


func _run() -> void:
	await process_frame  # let the autoloads finish _ready()
	_rules = load("res://scripts/Rules.gd") as GDScript
	_units = load("res://scripts/Unit.gd") as GDScript
	_k = _rules.get_script_constant_map()
	_check(not _k.is_empty() and _k.has("MAX_HIT_CHANCE"),
			"Rules.gd loaded with its constants (%d of them)" % _k.size())

	_test_flank_excludes_cover()
	_test_long_shot_integer_division()
	_test_clamp_bounds()
	_test_cover_halving()
	_test_executioner()
	_test_peek_asymmetry()
	_test_preview_matches_resolution()
	_test_morale()
	_test_conduct()
	_test_formation_morale()
	_test_throw_range()
	_test_left_for_dead()

	print("\nRESULT: ", "FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


# --- 1. flanking and cover are mutually exclusive ----------------------------

func _test_flank_excludes_cover() -> void:
	print("\n[1] a flanked target gets the flank bonus and NOT the cover penalty")
	# The target at (2,3) has a wall due north at (2,2); the shooter at (4,1)
	# comes in on the diagonal, so the wall covers his sector without standing
	# in the line - a clean full-cover shot with no peek involved.
	var board := _board([
		"........",
		"........",
		"..#.....",
		"........",
		"........",
	])
	var shooter: Node2D = _mk(KIND_SCOUT, Vector2i(4, 1))
	var target: Node2D = _mk(KIND_SCOUT, Vector2i(2, 3))
	var base: int = shooter.accuracy
	# manhattan 4 against a 4-tile weapon: comfortable is 2, so two tiles of
	# long shot are in every number below. Held constant across both facings.
	var reach: int = 2 * _k.LONG_SHOT_PENALTY

	_check(board.has_line_of_sight(shooter.cell, target.cell),
			"the diagonal shot has a clean line (the wall covers, it does not block)")
	_check(not _peeking(board, shooter, target),
			"and nobody is leaning around anything")

	_check(_face_covered(target, shooter), "found a facing that covers the shooter")
	_check(_cover(board, shooter, target) == Board.CoverLevel.FULL,
			"facing into the wall, the target is in FULL cover")
	_check(not _flanking(shooter, target), "...and is not flanked")
	var covered := _chance(board, shooter, target)
	_check(covered == base - _k.FULL_COVER_ACCURACY - reach,
			"the covered shot pays the full-cover penalty and nothing else (%d%%)"
			% covered)

	_check(_face_flanked(target, shooter), "found a facing that leaves him flanked")
	_check(_cover(board, shooter, target) == Board.CoverLevel.NONE,
			"turned away from the wall, his cover is NONE - the wall is behind him")
	_check(_flanking(shooter, target), "...and the shot is a flank")
	var flanked := _chance(board, shooter, target)
	_check(flanked == base + _k.FLANK_ACCURACY - reach,
			"the flanking shot takes the bonus and is NOT also charged for cover (%d%%)"
			% flanked)
	_check(flanked - covered == _k.FLANK_ACCURACY + _k.FULL_COVER_ACCURACY,
			"turning the target is worth the bonus plus the penalty, %d points"
			% [_k.FLANK_ACCURACY + _k.FULL_COVER_ACCURACY])

	# The invariant itself, not just this one pair. It used to be what held the
	# damage rule's two spellings together - the resolver tested cover first,
	# the panel tested flanking first - and there is only one spelling now. But
	# it is still load-bearing one function up: hit_chance takes the flank
	# bonus in an `if` and charges full cover in the matching `elif`, so a
	# target that were somehow both would silently be granted the bonus and
	# excused the penalty. Sweep it.
	_sweep_exclusive(board, "one wall")
	_sweep_cover_at(board, "one wall")

	shooter.free()
	target.free()
	board.free()


# --- 2. the long-shot threshold is integer division --------------------------

func _test_long_shot_integer_division() -> void:
	print("\n[2] long shot starts past attack_range / 2, in integer division")
	var board := _board([
		".........",
		".........",
		".........",
		".........",
		".........",
		".........",
	])
	var shooter: Node2D = _mk(KIND_SCOUT, Vector2i(4, 5))
	var target: Node2D = _mk(KIND_SCOUT, Vector2i(4, 4))
	var base: int = shooter.accuracy
	_check(base == 90, "the test shooter is a stock 90%% scout (got %d)" % base)

	# An empty board: no cover anywhere, so every number below is base minus
	# the long-shot term and nothing else.
	for spec in [
		# [attack_range, comfortable, [distance...]]
		[4, 2], [5, 2], [6, 3],
	]:
		var weapon: int = spec[0]
		var comfortable: int = spec[1]
		shooter.attack_range = weapon
		for dist in [1, 2, 3, 4]:
			target.cell = shooter.cell - Vector2i(0, dist)
			_check(Board.manhattan(shooter.cell, target.cell) == dist,
					"range %d: the target really is %d tiles out" % [weapon, dist])
			_check(_face_covered(target, shooter),
					"range %d dist %d: target faces the shooter" % [weapon, dist])
			_check(_cover(board, shooter, target) == Board.CoverLevel.NONE,
					"range %d dist %d: open ground, no cover" % [weapon, dist])
			var want: int = base - maxi(dist - comfortable, 0) * _k.LONG_SHOT_PENALTY
			var got := _chance(board, shooter, target)
			_check(got == want,
					"range %d dist %d: %d%% (comfortable to %d)"
					% [weapon, dist, got, comfortable])

	# The assertion that catches somebody "fixing" the integer division: a
	# 5-tile weapon is comfortable to 2, not 2.5, so it reads identically to a
	# 4-tile one at every distance. Half a tile of comfort is not a thing the
	# grid can express.
	target.cell = shooter.cell - Vector2i(0, 3)
	_check(_face_covered(target, shooter), "three tiles out, facing the shooter")
	shooter.attack_range = 4
	var four := _chance(board, shooter, target)
	shooter.attack_range = 5
	var five := _chance(board, shooter, target)
	_check(four == five and five == base - _k.LONG_SHOT_PENALTY,
			"at 3 tiles a 5-tile weapon reads exactly like a 4-tile one, %d%% (2.5 would not)"
			% five)
	target.cell = shooter.cell - Vector2i(0, 4)
	_check(_face_covered(target, shooter), "four tiles out, facing the shooter")
	_check(_chance(board, shooter, target) == base - 2 * _k.LONG_SHOT_PENALTY,
			"and at 4 tiles it is still two penalties, not one and a half")

	shooter.free()
	target.free()
	board.free()


# --- 3. the clamp ------------------------------------------------------------

func _test_clamp_bounds() -> void:
	print("\n[3] the roll clamps to [%d, %d], inclusive at both ends"
			% [_k.MIN_HIT_CHANCE, _k.MAX_HIT_CHANCE])
	var board := _board([
		".........",
		".........",
		".........",
		".........",
	])
	var shooter: Node2D = _mk(KIND_SCOUT, Vector2i(4, 3))
	var target: Node2D = _mk(KIND_SCOUT, Vector2i(4, 2))  # adjacent: no long shot
	_check(_face_covered(target, shooter), "point blank, target facing the shooter")
	var base: int = shooter.accuracy

	_check(_chance(board, shooter, target, 200) == _k.MAX_HIT_CHANCE,
			"a 290%% shot comes back as %d" % _k.MAX_HIT_CHANCE)
	_check(_chance(board, shooter, target, 200) != 100,
			"...which is never 100 - the dice always get a say")
	_check(_chance(board, shooter, target, _k.MAX_HIT_CHANCE - base) == _k.MAX_HIT_CHANCE,
			"a shot landing exactly on %d is left there" % _k.MAX_HIT_CHANCE)
	_check(_chance(board, shooter, target, _k.MAX_HIT_CHANCE - base + 1) == _k.MAX_HIT_CHANCE,
			"one point over is pulled back to it")

	_check(_chance(board, shooter, target, _k.MIN_HIT_CHANCE - base) == _k.MIN_HIT_CHANCE,
			"a shot landing exactly on %d is left there" % _k.MIN_HIT_CHANCE)
	_check(_chance(board, shooter, target, _k.MIN_HIT_CHANCE - base - 1) == _k.MIN_HIT_CHANCE,
			"one point under is pushed back up to it")

	# Pinned: the position clamps FIRST, and the pin then takes its quarter
	# of whatever is left - the same fraction against a hopeless shot as
	# against a clean one, and the one number allowed below the floor.
	shooter.suppress()
	_check(shooter.is_suppressed(), "the shooter is pinned")
	_check(_chance(board, shooter, target)
					== base * (100 - _k.SUPPRESSION_ACCURACY) / 100,
			"the pin takes %d%% of a clean %d%% shot" % [
					_k.SUPPRESSION_ACCURACY, base])
	shooter.accuracy = 10
	_check(_chance(board, shooter, target)
					== _k.MIN_HIT_CHANCE * (100 - _k.SUPPRESSION_ACCURACY) / 100,
			"and %d%% of the floored %d%% - never nothing, never free"
			% [100 - _k.SUPPRESSION_ACCURACY, _k.MIN_HIT_CHANCE])
	shooter.suppression = 0
	shooter.accuracy = base

	# Marksman removes the long-shot term outright rather than softening it.
	target.cell = shooter.cell - Vector2i(0, 4)
	shooter.attack_range = 4
	_check(_face_covered(target, shooter), "four tiles out, target facing the shooter")
	var plain := _chance(board, shooter, target)
	_check(plain == base - 2 * _k.LONG_SHOT_PENALTY,
			"an ordinary soldier pays %d for the distance (%d%%)"
			% [2 * _k.LONG_SHOT_PENALTY, plain])
	shooter.perks = ["marksman"]
	_check(_chance(board, shooter, target) == base,
			"a Marksman pays nothing at all - the term is gone, not halved")

	shooter.free()
	target.free()
	board.free()


# --- 4. cover halves damage with a shift -------------------------------------

func _test_cover_halving() -> void:
	print("\n[4] cover halves damage with >>, which is why base damage is even")
	# `dmg >>= 1`, straight out of _fire_round. Written out so the odd case is
	# on the record: 3 into cover is 1, not 2 and not 1.5.
	_check(4 >> 1 == 2, "4 into cover is 2")
	_check(2 >> 1 == 1, "2 into cover is 1")
	_check(3 >> 1 == 1, "3 into cover is 1 - a shift rounds an odd hit DOWN")
	_check(1 >> 1 == 0, "1 into cover is 0 - a shot that does nothing at all")

	# Which is why the odd cases above are unreachable, and must stay so: every
	# base damage in the game is even, so halving always lands on a whole
	# number and no soldier ever fires a round that cannot hurt anybody.
	var odd: Array[String] = []
	for kind in KIND_NAMES.size():
		var u: Node2D = _mk(kind, Vector2i.ZERO)
		if u.damage % 2 != 0:
			odd.append("%s=%d" % [KIND_NAMES[kind], u.damage])
		if kind == KIND_CIVILIAN:
			_check(u.damage == 0 and not u.is_combatant(),
					"the civilian carries nothing and shoots nothing")
		u.free()
	_check(odd.is_empty(), "every kind's base damage is even (odd: %s)" % [odd])

	# The two bonuses that ever reach the damage rule cannot break that.
	# Executioner's point is odd, but it only applies on a flank, where cover is
	# NONE by [1] and nothing is halved. The called shot's bonus is even anyway,
	# and it passes ignore_cover, so it never meets the shift either.
	_check(_k.EXECUTIONER_BONUS == 1,
			"Executioner's %d is the only odd addend, and it is flank-only"
			% _k.EXECUTIONER_BONUS)


# --- 5. Executioner ----------------------------------------------------------

func _test_executioner() -> void:
	print("\n[5] Executioner's point lands on a flank and never through cover")
	var board := _board([
		"........",
		"........",
		"..#.....",
		"........",
		"........",
	])
	var killer: Node2D = _mk(KIND_SCOUT, Vector2i(4, 1), ["executioner"])
	var plain: Node2D = _mk(KIND_SCOUT, Vector2i(4, 1))
	var target: Node2D = _mk(KIND_SCOUT, Vector2i(2, 3))
	var hit: int = killer.damage
	_check(hit == 2, "the test shooter deals a stock %d (got %d)" % [2, hit])

	_check(_face_flanked(target, killer), "the target is turned away from the shooter")
	_check(_flanking(killer, target) and _cover(board, killer, target) == Board.CoverLevel.NONE,
			"so damage_for falls past its cover arm into the flanking one")
	_check(_damage(board, killer, target) == hit + _k.EXECUTIONER_BONUS,
			"a flanking round from the perked shooter deals %d"
			% (hit + _k.EXECUTIONER_BONUS))
	_check(_damage(board, plain, target) == hit,
			"the same flank without the perk deals %d" % hit)

	_check(_face_covered(target, killer), "now the target faces its wall")
	_check(not _flanking(killer, target)
			and _cover(board, killer, target) == Board.CoverLevel.FULL,
			"so the cover arm takes it first and the flanking one is unreachable")
	_check(_damage(board, killer, target) == hit >> 1,
			"the perked shooter deals %d into cover - halved, with no point added"
			% (hit >> 1))
	_check(_damage(board, killer, target) == _damage(board, plain, target),
			"...which is exactly what the unperked shooter deals")

	killer.free()
	plain.free()
	target.free()
	board.free()


# --- 6. the peek leans around the end of a wall, not its middle --------------

func _test_peek_asymmetry() -> void:
	print("\n[6] peek_origin finds the end of a wall run and not its middle")
	# One wall, five cells long, running down x=3 from y=2 to y=6. Two shots at
	# it from the same side and the same two-tile range: one level with the top
	# END of the run, one level with its MIDDLE. That asymmetry IS the peek
	# rule, and nothing tested it until now - which is how the aggregate
	# ignore-list bug shipped (ANALYSIS.md, finding #2).
	var board := _board([
		".......",
		".......",
		"...#...",
		"...#...",
		"...#...",
		"...#...",
		"...#...",
		".......",
	])
	var end_from := Vector2i(2, 2)   # level with (3,2), the top of the run
	var end_to := Vector2i(4, 2)
	var mid_from := Vector2i(2, 4)   # level with (3,4), the middle of it
	var mid_to := Vector2i(4, 4)

	_check(not board.has_line_of_sight(end_from, end_to),
			"the wall blocks the direct line at the end of the run")
	_check(not board.has_line_of_sight(mid_from, mid_to),
			"and blocks it just the same at the middle")

	_check(board.peek_origin(end_from, end_to) == Vector2i(2, 1),
			"at the end, leaning one north clears the run - peek_origin returns (2,1)")
	_check(board.peek_origin(mid_from, mid_to) == Board.NO_CELL,
			"at the middle there is no angle: the next section is still in the way")
	_check(board.can_engage(end_from, end_to), "so the end shot exists")
	_check(not board.can_engage(mid_from, mid_to), "and the middle shot does not")

	var shooter: Node2D = _mk(KIND_SCOUT, end_from)
	var target: Node2D = _mk(KIND_SCOUT, end_to)
	var base: int = shooter.accuracy
	_check(_peeking(board, shooter, target), "Rules agrees the end shot is a lean")
	shooter.cell = mid_from
	target.cell = mid_to
	_check(not _peeking(board, shooter, target), "and that the middle shot is not")

	# What the lean costs. The target at (4,2) is hugging the same wall from the
	# far side, so this one shot pays the peek AND the full-cover penalty - and
	# turning him around trades the penalty for the flank bonus, exactly as [1]
	# says it must, on completely different geometry.
	shooter.cell = end_from
	target.cell = end_to
	_check(Board.manhattan(end_from, end_to) == 2,
			"two tiles: inside a scout's comfortable range, so no long shot")
	_check(_face_covered(target, shooter), "the target faces his side of the wall")
	_check(_cover(board, shooter, target) == Board.CoverLevel.FULL,
			"which is FULL cover")
	_check(_chance(board, shooter, target)
			== base - _k.FULL_COVER_ACCURACY - _k.PEEK_ACCURACY,
			"leaning out at a covered target costs %d and %d (%d%%)"
			% [_k.FULL_COVER_ACCURACY, _k.PEEK_ACCURACY,
					_chance(board, shooter, target)])
	_check(_face_flanked(target, shooter), "turn him around")
	_check(_chance(board, shooter, target) == base + _k.FLANK_ACCURACY - _k.PEEK_ACCURACY,
			"and the lean still costs %d, but the cover is gone (%d%%)"
			% [_k.PEEK_ACCURACY, _chance(board, shooter, target)])

	_sweep_exclusive(board, "one long wall")
	_sweep_cover_at(board, "one long wall")

	shooter.free()
	target.free()
	board.free()


# --- 7. the promise equals the round -----------------------------------------

## The two branch orders the game used to carry, kept here as history rather
## than as rules - nothing runs either one now, because Rules.damage_for is the
## only spelling left. They stay because "unifying them changed no outcome" is
## a claim, and a sweep that tries every combination and finds no daylight
## between them is a proof. The resolver tested cover first; the panel tested
## flanking first; they agreed only because effective_cover returns NONE on a
## flank. If one of these ever fails, that invariant has broken and the
## unification silently moved a real number.
func _old_resolver_order(board: Board, a: Node2D, t: Node2D,
		bonus: int, ignore_cover: bool) -> int:
	var dmg: int = a.damage + bonus
	var cover: int = Board.CoverLevel.NONE if ignore_cover else _cover(board, a, t)
	if cover != Board.CoverLevel.NONE:
		dmg >>= 1
	elif _flanking(a, t) and a.has_perk("executioner"):
		dmg += _k.EXECUTIONER_BONUS
	return dmg


func _old_panel_order(board: Board, a: Node2D, t: Node2D,
		bonus: int, ignore_cover: bool) -> int:
	var dmg: int = a.damage + bonus
	var cover: int = Board.CoverLevel.NONE if ignore_cover else _cover(board, a, t)
	if _flanking(a, t):
		if a.has_perk("executioner"):
			dmg += _k.EXECUTIONER_BONUS
	elif cover == Board.CoverLevel.FULL:
		dmg >>= 1
	elif cover == Board.CoverLevel.HALF:
		dmg >>= 1
	return dmg


## Place the pair on a shot whose target, facing its shooter, has exactly the
## cover level asked for. Searched rather than hand-placed, so the assertion
## that all three levels were reached is a fact about the board instead of a
## diagram in a comment that nobody re-checks.
func _find_shot(board: Board, shooter: Node2D, target: Node2D, want: int) -> bool:
	for ty in board.size.y:
		for tx in board.size.x:
			var t := Vector2i(tx, ty)
			if not board.is_walkable(t):
				continue
			for sy in board.size.y:
				for sx in board.size.x:
					var s := Vector2i(sx, sy)
					if s == t or not board.is_walkable(s):
						continue
					if not board.has_line_of_sight(s, t):
						continue
					shooter.cell = s
					target.cell = t
					if _face_covered(target, shooter) \
							and _cover(board, shooter, target) == want:
						return true
	return false


func _test_preview_matches_resolution() -> void:
	print("\n[7] the promise and the round are one function, over every combination")
	# One wall and one junk pile, far enough apart that no cell is adjacent to
	# both - so the search below can find a clean FULL shot and a clean HALF
	# one without either contaminating the other.
	var board := _board([
		"..........",
		"..........",
		"..#.......",
		"..........",
		"..........",
		"......j...",
		"..........",
	])
	var shooter: Node2D = _mk(KIND_SCOUT, Vector2i.ZERO)
	var target: Node2D = _mk(KIND_SCOUT, Vector2i.ZERO)
	var levels := {"NONE": Board.CoverLevel.NONE, "HALF": Board.CoverLevel.HALF,
			"FULL": Board.CoverLevel.FULL}
	var drift: Array[String] = []    # the preview disagreed with the round
	var history: Array[String] = []  # an old branch order disagreed with either
	var fields: Array[String] = []   # a dict field disagreed with its predicate
	var combos := 0

	for level_name: String in levels:
		var want: int = levels[level_name]
		_check(_find_shot(board, shooter, target, want),
				"found a shot whose target sits in %s cover" % level_name)
		for flanked in [false, true]:
			# Turning the target does not change the geometry, only whether the
			# cover applies - which is the whole point of sweeping both.
			_check(_face_flanked(target, shooter) if flanked
					else _face_covered(target, shooter),
					"%s: a %s facing exists" % [level_name,
							"flanked" if flanked else "covered"])
			for executioner in [false, true]:
				shooter.perks = ["executioner"] if executioner else []
				for ignore_cover in [false, true]:
					for bonus in [0, 2]:
						combos += 1
						var tag := "%s/%s/exec=%s/ignore=%s/+%d" % [level_name,
								"flanked" if flanked else "covered",
								executioner, ignore_cover, bonus]
						var round_dmg := _damage(board, shooter, target,
								bonus, ignore_cover)
						var shot := _preview(board, shooter, target, 0, 0,
								bonus, ignore_cover)
						if int(shot.dmg) != round_dmg:
							drift.append("%s: promised %d, dealt %d"
									% [tag, shot.dmg, round_dmg])
						if _old_resolver_order(board, shooter, target, bonus,
										ignore_cover) != round_dmg \
								or _old_panel_order(board, shooter, target, bonus,
										ignore_cover) != round_dmg:
							history.append(tag)
						var applied: int = Board.CoverLevel.NONE if ignore_cover \
								else _cover(board, shooter, target)
						if int(shot.cover) != applied \
								or bool(shot.flanking) != _flanking(shooter, target) \
								or bool(shot.peeking) != _peeking(board, shooter, target) \
								or int(shot.chance) != _chance(board, shooter, target):
							fields.append(tag)

	_check(combos == 48, "the sweep ran all 48 combinations (got %d)" % combos)
	_check(drift.is_empty(),
			"shot_preview never quotes a number damage_for will not pay (%s)" % [drift])
	_check(history.is_empty(),
			"and both pre-unification orders return it too - no outcome moved (%s)"
			% [history])
	_check(fields.is_empty(),
			"cover, flanking, peeking and chance match their own predicates (%s)"
			% [fields])

	# The one combination the old code did quote wrong, now on the record. A
	# called shot forces cover to NONE, which drops it into the flanking arm, so
	# the resolver has always added Executioner's point - while the panel's
	# called-shot line composed `damage + CALLED_SHOT_BONUS` by hand and never
	# did. No shipped soldier can hold both perks (called_shot is HERO rank 1,
	# executioner is SCOUT rank 4), so it was never quoted at a live target; one
	# edit to the perk tables and it would have been.
	_check(_find_shot(board, shooter, target, Board.CoverLevel.FULL),
			"a full-cover shot, one more time")
	_check(_face_flanked(target, shooter), "with the target turned away from it")
	shooter.perks = ["executioner"]
	var called := _damage(board, shooter, target, 2, true)
	_check(called == shooter.damage + 2 + _k.EXECUTIONER_BONUS,
			"a flanking called shot pays the bonus AND Executioner's point (%d)" % called)
	_check(int(_preview(board, shooter, target, 0, 0, 2, true).dmg) == called,
			"...and the quote on the panel is now that same %d" % called)

	shooter.free()
	target.free()
	board.free()


# --- 9. morale, and the two ways a fight ends for one soldier ----------------

func _test_morale() -> void:
	print("\n[9] a unit breaks, and the squad decides which way")
	var bolt: int = int(_k.KIND_GOBLIN_BOLT)
	var smg := 4  # GOBLIN_SMG, and nothing special about it - that is the point

	# Unit.gd cannot name Rules - Rules names Unit in every signature and the
	# cycle would be resolved by compile order - so it carries the starting
	# morale as a literal in each stat block. This is the assertion that keeps
	# the two honest, and it sweeps every Kind rather than sampling one: the
	# numbers now DIFFER by kind, so a spot check would pass while any other
	# class quietly drifted.
	var wrong_morale: Array[String] = []
	for kind in KIND_NAMES.size():
		var u: Node2D = _mk(kind, Vector2i.ZERO)
		var want: int = int(_rules.call("starting_morale", kind))
		if int(u.morale) != want:
			wrong_morale.append("%s has %d, Rules says %d"
					% [KIND_NAMES[kind], int(u.morale), want])
		u.free()
	_check(wrong_morale.is_empty(),
			"every kind starts on the morale Rules gives it (%s)" % [wrong_morale])

	# The point of the table: the two classes the fiction calls least willing to
	# be there are now the two that can actually break. A conscript has 2 HP, so
	# the only round he survives is one already halved by cover - and that one
	# round has to be enough on its own.
	var conscript: int = int(_rules.call("starting_morale",
			int(_k.KIND_GOBLIN_REVOLVER)))
	var one_bad_round: int = _rules.call("morale_after_round", conscript, 1, 2)
	_check(_rules.call("is_broken", one_bad_round),
			"a conscript breaks on the one wounding round he can survive (%d -> %d)"
			% [conscript, one_bad_round])
	var well_hand: int = int(_rules.call("starting_morale", int(_k.KIND_GOBLIN)))
	var hurt_well_hand: int = _rules.call("morale_after_round", well_hand, 2, 4)
	_check(not _rules.call("is_broken", hurt_well_hand),
			"...and a well-hand does not (%d -> %d)" % [well_hand, hurt_well_hand])

	# A man who came back is steadier than the levy he was, and stops flinching
	# at the fallen.
	_check(int(_k.RETURNER_MORALE) >= int(_k.MORALE_MAX),
			"a returner starts at least as steady as anyone (%d)"
			% int(_k.RETURNER_MORALE))
	_check(not _rules.call("shaken_by_the_fallen", true)
			and _rules.call("shaken_by_the_fallen", false),
			"...and is the only one an ally going down does not move")

	var fresh: Node2D = _mk(smg, Vector2i.ZERO)
	_check(not fresh.surrendered and not fresh.routing and not fresh.has_stopped(),
			"a fresh unit starts fighting")
	fresh.free()

	# The Kind ordinal Rules names for the kill floor must be the real one.
	_check(KIND_NAMES[bolt] == "GOBLIN_BOLT",
			"Rules.KIND_GOBLIN_BOLT (%d) is the Marksman's real ordinal" % bolt)

	# The wound is the big term, and it only lands at half HP or less.
	var grazed: int = _rules.call("morale_after_round", 100, 3, 4)
	var hurt: int = _rules.call("morale_after_round", 100, 2, 4)
	_check(grazed == 100 - int(_k.MORALE_HIT),
			"a round that leaves him standing costs the hit only (%d)" % grazed)
	_check(hurt == 100 - int(_k.MORALE_HIT) - int(_k.MORALE_WOUNDED),
			"a round that halves him costs the wound as well (%d)" % hurt)
	_check(int(_k.MORALE_WOUNDED) > int(_k.MORALE_HIT),
			"and the wound is the larger of the two, which is the design")

	# Halving is integer, matching the cover rule: 5 HP is "half or less" at 2.
	_check(_rules.call("morale_after_round", 100, 2, 5) < grazed
			and _rules.call("morale_after_round", 100, 3, 5) == grazed,
			"half of an odd pool rounds down, exactly like cover's >>")

	# Morale is bounded at both ends and cannot be banked.
	_check(_rules.call("morale_after_round", 5, 1, 4) == 0,
			"morale floors at 0 rather than going negative")
	_check(_rules.call("morale_recovered", int(_k.MORALE_MAX)) == int(_k.MORALE_MAX),
			"a quiet turn cannot bank calm past MORALE_MAX")

	# Witnessing is a radius, and the edge of it is inclusive.
	var w: int = int(_k.MORALE_WITNESS)
	_check(_rules.call("morale_after_ally_down", 100, w) < 100
			and _rules.call("morale_after_ally_down", 100, w + 1) == 100,
			"an ally dies inside %d tiles and is felt, outside it is not" % w)

	# The break, and the two exhaustive outcomes on the far side of it.
	var brk: int = int(_k.MORALE_BREAK)
	var guns: int = int(_k.MORALE_SURRENDER_GUNS)
	_check(_rules.call("is_broken", brk) and not _rules.call("is_broken", brk + 1),
			"MORALE_BREAK is inclusive: %d breaks, %d does not" % [brk, brk + 1])
	_check(_rules.call("breaks_to_surrender", smg, brk, guns)
			and not _rules.call("breaks_to_rout", smg, brk, guns),
			"broken with %d guns on him: he surrenders, and does not also rout" % guns)
	_check(_rules.call("breaks_to_rout", smg, brk, guns - 1)
			and not _rules.call("breaks_to_surrender", smg, brk, guns - 1),
			"broken with %d: he runs, because there is nobody to give up to" % (guns - 1))

	# Exhaustive and mutually exclusive over every morale and every gun count,
	# for every kind. This is what lets the controller ask one question.
	var overlap: Array[String] = []
	var gap: Array[String] = []
	for kind in KIND_NAMES.size():
		for m in range(0, int(_k.MORALE_MAX) + 1):
			for g in 4:
				var s: bool = _rules.call("breaks_to_surrender", kind, m, g)
				var r: bool = _rules.call("breaks_to_rout", kind, m, g)
				if s and r:
					overlap.append("kind %d m%d g%d" % [kind, m, g])
				var should_break: bool = _rules.call("is_broken", m) \
						and not _rules.call("never_breaks", kind)
				if should_break and not (s or r):
					gap.append("kind %d m%d g%d" % [kind, m, g])
	_check(overlap.is_empty(),
			"no unit both surrenders and routs, over every kind/morale/guns (%s)"
			% [overlap.slice(0, 3)])
	_check(gap.is_empty(),
			"and every breakable unit that breaks does one of them (%s)"
			% [gap.slice(0, 3)])

	# Standing decides what breaking MEANS. The trusted squad is surrendered
	# to a gun earlier; the feared one is never surrendered to at all - and
	# the two outcomes stay exhaustive and exclusive at every reputation.
	var trusted: int = int(_k.STANDING_TRUSTED)
	var feared: int = int(_k.STANDING_FEARED)
	_check(_rules.call("breaks_to_surrender", smg, brk, guns - 1, false, trusted),
			"a town that trusts the squad: one gun fewer takes the surrender")
	_check(_rules.call("breaks_to_rout", smg, brk, 3, false, feared)
			and not _rules.call("breaks_to_surrender", smg, brk, 3, false, feared),
			"a town that fears it: three guns on him and he still runs")
	var standing_overlap := 0
	for st in [0, feared, feared + 1, 49, 50, trusted - 1, trusted, 100]:
		for g in 4:
			var s2: bool = _rules.call("breaks_to_surrender", smg, brk, g, false, st)
			var r2: bool = _rules.call("breaks_to_rout", smg, brk, g, false, st)
			if s2 == r2:
				standing_overlap += 1
	_check(standing_overlap == 0,
			"and the pair stays exhaustive-exclusive at every reputation")

	# The kill floor. One class holds, and it is the one the bolt already rooted.
	_check(_rules.call("never_breaks", bolt),
			"the Marksman never breaks - the kill floor has somebody standing on it")
	var breakers := 0
	for kind in KIND_NAMES.size():
		if not _rules.call("never_breaks", kind):
			breakers += 1
	_check(breakers == KIND_NAMES.size() - 1,
			"and he is the only one (%d of %d can break)"
			% [breakers, KIND_NAMES.size()])
	_check(not _rules.call("breaks_to_surrender", bolt, 0, 9)
			and not _rules.call("breaks_to_rout", bolt, 0, 9),
			"at zero morale with nine guns on him he still does neither")


# --- 10. conduct: the clean kill is free, and Strain never clears ------------

func _test_conduct() -> void:
	print("\n[10] killing armed men is free; the chosen acts are not")
	var conduct: Dictionary = _k.Conduct
	var costs: Dictionary = _k.CONDUCT_COST

	# The rule the whole after-action rests on.
	var clean: int = int(conduct.COMBATANT_KILLED)
	_check(_rules.call("standing_cost", clean) == 0
			and _rules.call("strain_cost", clean) == 0,
			"killing an armed, fighting combatant costs 0 Standing and 0 Strain")
	_check(_rules.call("standing_after", 50, clean) == 50,
			"...so a firefight leaves the settlement's opinion where it was")
	_check(_rules.call("strain_after", int(_k.STRAIN_START), clean)
			== int(_k.STRAIN_START),
			"...and the theater's, too")

	# Every OTHER entry is a chosen act and every one of them costs something.
	var free_acts: Array[String] = []
	for name: String in conduct:
		var c: int = int(conduct[name])
		if c == clean:
			continue
		if _rules.call("standing_cost", c) <= 0 and _rules.call("strain_cost", c) <= 0:
			free_acts.append(name)
	_check(free_acts.is_empty(),
			"every act that is not a clean kill costs something (%s)" % [free_acts])
	_check(costs.size() == conduct.size(),
			"and the table prices every Conduct there is (%d of %d)"
			% [costs.size(), conduct.size()])

	# Firing on a man with his hands up is the worst of the firing entries.
	_check(_rules.call("standing_cost", int(conduct.SURRENDERED_FIRED_ON))
			> _rules.call("standing_cost", int(conduct.ROUTING_FIRED_ON)),
			"shooting the surrendered costs more than shooting the running")

	# The floor. This is the assertion the plan asks for by name.
	var floor_at: int = int(_k.STRAIN_FLOOR)
	_check(floor_at > 0, "the Strain floor is above zero (%d)" % floor_at)
	var strain: int = int(_k.STRAIN_START)
	for i in 200:
		strain = _rules.call("strain_decayed", strain)
	_check(strain == floor_at,
			"200 clean missions walk Strain to the floor and stop there (%d)" % strain)
	var floored := true
	for s in range(0, int(_k.STRAIN_MAX) + 1):
		if int(_rules.call("strain_decayed", s)) < floor_at:
			floored = false
		for name: String in conduct:
			if int(_rules.call("strain_after", s, int(conduct[name]))) < floor_at:
				floored = false
	_check(floored,
			"no conduct and no decay puts Strain under the floor, from any value")
	_check(int(_k.STRAIN_START) > floor_at,
			"a campaign opens above the floor, so good conduct has somewhere to go")

	# Game.gd cannot name Rules either - Rules names Unit and Unit names the
	# Game autoload, so the reference would close a cycle in the one file the
	# `-s` harnesses load before the autoloads exist. It carries these two as
	# literals instead. Same deal as Unit.morale above, same assertion.
	var game_consts: Dictionary = (load("res://scripts/Game.gd") as GDScript) \
			.get_script_constant_map()
	_check(int(game_consts["STRAIN_START"]) == int(_k.STRAIN_START),
			"Game.STRAIN_START matches Rules' (%d)" % int(game_consts["STRAIN_START"]))
	_check(int(game_consts["STANDING_START"]) == int(_k.STANDING_START),
			"Game.STANDING_START matches Rules' (%d)"
			% int(game_consts["STANDING_START"]))
	# Same deal for the warband thresholds, which Game.warband_for compares
	# against and therefore has to carry as literals too.
	for key: String in ["WARBAND_LEADER_SURVIVALS", "WARBAND_MEMBER_SURVIVALS",
			"WARBAND_SIZE"]:
		_check(int(game_consts[key]) == int(_k.get(key)),
				"Game.%s matches Rules' (%d)" % [key, int(_k.get(key))])


# --- 10b. breaking as a formation --------------------------------------------
#
# The two terms that are about the unit rather than the man. Both have to be
# silent in an ordinary firefight and loud in a collapse, and the thresholds
# are the whole of that - so they are pinned here rather than left to feel.

func _test_formation_morale() -> void:
	print("
[10b] a formation breaks as well as a man")

	# Shock. Below the floor it must contribute NOTHING: the per-death ally
	# term already prices one or two casualties, and a second charge on top of
	# it would rout a map on a good opening volley.
	_check(int(_rules.call("shock_cost", 0)) == 0
			and int(_rules.call("shock_cost", int(_k.SHOCK_DEATHS) - 1)) == 0,
			"losses below the floor cost nothing extra - that is a firefight")
	var at_floor: int = int(_rules.call("shock_cost", int(_k.SHOCK_DEATHS)))
	_check(at_floor == int(_k.MORALE_SHOCK),
			"the %dth death in the window is the first that shocks (%d)"
			% [int(_k.SHOCK_DEATHS), at_floor])
	_check(int(_rules.call("shock_cost", int(_k.SHOCK_DEATHS) + 2))
			> at_floor,
			"and it goes on getting worse the faster they are dying")
	_check(int(_rules.call("morale_after_shock", 10, 99)) == 0,
			"shock floors at zero rather than going negative")

	# It has to be able to actually break somebody, or it is decoration. Four
	# dead in a window against a full-strength well-hand is the case: he is the
	# steadiest thing the Thirst fields and he should still be considering it.
	var whole: int = int(_rules.call("starting_morale", int(_k.KIND_GOBLIN)))
	var shocked: int = int(_rules.call("morale_after_shock", whole,
			int(_k.SHOCK_DEATHS) + 1))
	_check(shocked < whole,
			"a well-hand at full strength feels four of his own go down (%d -> %d)"
			% [whole, shocked])
	_check(_rules.call("is_broken", int(_rules.call("morale_after_shock",
			int(_k.MORALE_BREAK) + int(_k.MORALE_SHOCK), int(_k.SHOCK_DEATHS)))),
			"...and a man already worn thin breaks on it")

	# Outnumbered. Two conditions, and the pair is what stops it firing on the
	# opening turn of a map the Thirst outnumbers.
	_check(not _rules.call("is_outnumbered", 11, 5),
			"eleven against five is not outnumbered, whatever the ratio says")
	_check(not _rules.call("is_outnumbered", int(_k.OUTNUMBERED_FEW) + 1, 99),
			"more than a few left is not outnumbered either")
	_check(_rules.call("is_outnumbered", 2, 5),
			"two left against five is")
	_check(not _rules.call("is_outnumbered", 3, 5),
			"...but three against five is not yet %dx" % int(_k.OUTNUMBERED_BY))
	_check(not _rules.call("is_outnumbered", 0, 5),
			"and nobody left is not a morale state")
	_check(int(_rules.call("morale_after_outnumbered", 90, 11, 5)) == 90,
			"a fight in the balance costs nothing")
	_check(int(_rules.call("morale_after_outnumbered", 90, 2, 5)) < 90,
			"being the last two against five does")

	# Warbands. The leader is the difference between four returners and a unit.
	_check(_rules.call("can_lead_warband", int(_k.WARBAND_LEADER_SURVIVALS))
			and not _rules.call("can_lead_warband",
					int(_k.WARBAND_LEADER_SURVIVALS) - 1),
			"it takes %d escapes to gather a warband, not fewer"
			% int(_k.WARBAND_LEADER_SURVIVALS))
	_check(_rules.call("can_join_warband", int(_k.WARBAND_MEMBER_SURVIVALS))
			and not _rules.call("can_join_warband", 0),
			"and one to follow somebody who has")
	_check(int(_k.WARBAND_LEADER_SURVIVALS) > int(_k.WARBAND_MEMBER_SURVIVALS),
			"a leader has been through more than the people he gathers")
	var led: int = int(_rules.call("morale_recovered_led", 40))
	var alone: int = int(_rules.call("morale_recovered", 40))
	_check(led > alone,
			"a man whose leader is still up steadies faster (%d vs %d)" % [led, alone])
	_check(int(_rules.call("morale_recovered_led", 99, 100)) <= 100
			and int(_rules.call("morale_recovered_led", 40, 45)) == 45,
			"...but never past his own ceiling")
	var bereaved: int = int(_rules.call("morale_after_leader_down", whole))
	_check(bereaved < whole,
			"losing the man who gathered them costs the rest of them (%d -> %d)"
			% [whole, bereaved])
	_check(int(_k.MORALE_LEADER_DOWN) > int(_k.MORALE_HIT),
			"and costs more than being shot, because he was their reason to be here")


# --- 11. the grenadier launches, everybody else throws ------------------------

func _test_throw_range() -> void:
	print("
[11] ordnance goes further out of a launcher than out of an arm")
	var thrown: int = int(_k.THROW_RANGE)
	var launched: int = int(_k.LAUNCHER_RANGE)
	var grenadier: int = int(_k.KIND_GRENADIER)

	# Rules spells the ordinal by hand, for the reason never_breaks() does, so
	# something has to keep the literal honest. Read the REAL enum to do it:
	# comparing it against KIND_NAMES below would compare one hand-written
	# table against another, and an insertion above GRENADIER would move the
	# enum while leaving both literals agreeing with each other. The visible
	# symptom of that is the medic lobbing a frag five tiles.
	var kinds: Dictionary = _units.get_script_constant_map()["Kind"]
	_check(grenadier == int(kinds["GRENADIER"]),
			"Rules.KIND_GRENADIER (%d) is Essa Vane's real ordinal (%d)"
			% [grenadier, int(kinds["GRENADIER"])])
	# And the mirror this file sweeps with has to match the enum too, or every
	# ordinal-indexed check in the file is reading stale labels.
	_check(KIND_NAMES.size() == kinds.size(),
			"KIND_NAMES covers every Kind (%d of %d)"
			% [KIND_NAMES.size(), kinds.size()])
	var mislabelled: Array[String] = []
	for name: String in kinds:
		var ord_: int = int(kinds[name])
		if ord_ >= KIND_NAMES.size() or KIND_NAMES[ord_] != name:
			mislabelled.append("%d should be %s" % [ord_, name])
	_check(mislabelled.is_empty(), "...and names each one correctly (%s)"
			% [mislabelled])

	_check(launched > thrown,
			"a launched round outreaches a thrown one (%d vs %d)"
			% [launched, thrown])

	# Exactly one kind launches. Swept rather than spot-checked, because the
	# failure that matters is a SECOND kind quietly picking it up.
	var launchers: Array[String] = []
	for kind in KIND_NAMES.size():
		var reach: int = int(_rules.call("throw_range", kind))
		var claims: bool = bool(_rules.call("has_launcher", kind))
		_check(claims == (reach > thrown),
				"%s: has_launcher agrees with throw_range" % KIND_NAMES[kind])
		if reach != thrown:
			launchers.append("%s=%d" % [KIND_NAMES[kind], reach])
	_check(launchers == ["GRENADIER=%d" % launched],
			"the grenadier alone throws further than %d (got %s)"
			% [thrown, launchers])

	# The design claim in Rules' comment, pinned against the side of the board
	# it is actually about: the launcher must not clear the longest weapon the
	# THIRST owns, because that is the range at which a grenade stops being a
	# trade and starts being free. Pinning it against the squad's own rifles
	# instead - which the first draft of this test did - measures the wrong two
	# numbers, and would have let the launcher outreach every enemy on the board
	# while still reporting ok.
	var enemy_reach := 0
	var enemy_who := ""
	for kind in KIND_NAMES.size():
		var u: Node2D = _mk(kind, Vector2i.ZERO)
		if int(u.team) == 1 and int(u.attack_range) > enemy_reach:
			enemy_reach = int(u.attack_range)
			enemy_who = KIND_NAMES[kind]
		u.free()
	_check(enemy_reach > 0, "found the Thirst's longest weapon (%s at %d)"
			% [enemy_who, enemy_reach])
	_check(launched <= enemy_reach,
			("the launcher's %d does not clear the Thirst's longest weapon "
			+ "(%s at %d) - at %d she would never have to stand on his line")
			% [launched, enemy_who, enemy_reach, enemy_reach + 1])


# --- 12. left for dead --------------------------------------------------------

func _test_left_for_dead() -> void:
	print("
[12] most of them are dead, and the ones who are not get worse")
	var base: int = int(_k.SURVIVE_BASE)
	var step: int = int(_k.SURVIVE_STEP)
	var cap: int = int(_k.SURVIVE_CAP)

	_check(base >= 15 and base <= 20,
			"a first defeat is survived one time in five or six (%d%%)" % base)
	_check(_rules.call("survive_chance", 0) == base,
			"...which is what a stranger gets (%d%%)"
			% _rules.call("survive_chance", 0))
	var rising := true
	var last := -1
	for n in 8:
		var c: int = _rules.call("survive_chance", n)
		if c < last:
			rising = false
		last = c
	_check(rising, "the more often he has walked away, the likelier he is to again")
	_check(_rules.call("survive_chance", 1) == base + step,
			"...by a step each time (%d%%)" % _rules.call("survive_chance", 1))
	_check(_rules.call("survive_chance", 99) == cap,
			"but never past the cap, so nobody becomes unkillable (%d%%)" % cap)
	_check(cap < 100, "...and the cap is short of certain (%d%%)" % cap)
	# Negative is not a real input, but a hand-edited save is.
	_check(_rules.call("survive_chance", -5) == base,
			"a nonsense tally reads as none")

	# The player's lever. Read against max_hp rather than against what was left,
	# because almost every weapon does 2 and enemy HP runs 2-4, so overkill past
	# the remaining points is nearly always zero - a rule built on it would
	# never fire. This way it says something actionable.
	_check(_rules.call("decisive_blow", 4, 4) and _rules.call("decisive_blow", 4, 3),
			"Rodar's four settles a well-hand and a light runner")
	_check(_rules.call("decisive_blow", 3, 3) and _rules.call("decisive_blow", 3, 2),
			"a frag settles a light runner and a conscript")
	_check(not _rules.call("decisive_blow", 2, 4)
			and not _rules.call("decisive_blow", 2, 3),
			"a carbine finishing a wounded man does not - that is the crawl-away case")
	_check(_rules.call("decisive_blow", 2, 2),
			"...but a carbine on a conscript does, because it would have killed "
			+ "him from full")

	# What he brings back. Down a point per wound, floored at 1 so there is
	# always a body to shoot, and never starting already broken - a fighter who
	# arrived below MORALE_BREAK would rout on his first activation, which is
	# not a comeback.
	_check(_rules.call("injured_hp", 4, 1) == 3
			and _rules.call("injured_hp", 4, 3) == 1,
			"a wound costs a point of health, and the floor is 1")
	_check(_rules.call("injured_hp", 2, 9) == 1, "...however many he has taken")
	var conscript_kind: int = int(_k.KIND_GOBLIN_REVOLVER)
	var hurt: int = _rules.call("injured_morale", conscript_kind, 2)
	_check(hurt < int(_rules.call("starting_morale", conscript_kind)),
			"...and he comes back shakier than he started (%d)" % hurt)
	_check(not _rules.call("is_broken", hurt),
			"...but not already broken, or the comeback is a cutscene (%d)" % hurt)
	var very_hurt: int = _rules.call("injured_morale", conscript_kind, 99)
	_check(not _rules.call("is_broken", very_hurt),
			"...at any number of wounds (%d)" % very_hurt)

	# The two flavours are opposites, and that contrast is the read: one of them
	# chose to come back, the other was patched up and sent.
	_check(int(_rules.call("returner_morale", conscript_kind)) > hurt,
			"the man who merely ran comes back steadier than the man who was "
			+ "left for dead (%d vs %d)"
			% [int(_rules.call("returner_morale", conscript_kind)), hurt])
