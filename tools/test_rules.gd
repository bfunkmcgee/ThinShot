extends SceneTree

## The shooting rules, pinned. Every assertion here runs against the real
## scripts/Rules.gd and the real Board, on geometry built for the purpose - a
## wall placed where the rule needs a wall, rather than whichever rock a
## shipped level happens to have near a spawn.
##
## Six things are checked, and they are the six the game rests on:
##   1. flanking and cover are mutually exclusive - a flanked target has NONE,
##      takes the flank bonus, and does NOT also charge the full-cover penalty
##   2. the long-shot threshold is `attack_range / 2` in INTEGER division, so a
##      5-tile weapon is comfortable to 2 exactly like a 4-tile one
##   3. the [20, 99] clamp, inclusive at both ends, and Marksman's exemption
##   4. cover halves damage with `>>`, which is why every base damage is even
##   5. Executioner adds its point on a flank and can never add it through cover
##   6. peek_origin leans around the END of a wall run and not around its MIDDLE
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


func _peeking(board: Board, a: Node2D, t: Node2D) -> bool:
	return _rules.call("is_peeking", board, a, t)


## The damage rule exactly as _fire_round applies it today, mirrored here
## because it still lives inside a 90-line coroutine that fires effects and
## awaits timers. Step 5 moves it to `Rules.damage_for` and deletes this
## helper; every assertion that calls it re-points there unchanged. What the
## assertions get from the real code meanwhile is the branch SELECTION -
## `_cover` and `_flanking` below are Rules', so the test proves which arm of
## _fire_round's if/elif a given board position lands in.
func _damage(board: Board, a: Node2D, t: Node2D, bonus := 0) -> int:
	var dmg: int = a.damage + bonus
	if _cover(board, a, t) != Board.CoverLevel.NONE:
		return dmg >> 1
	if _flanking(a, t) and a.has_perk("executioner"):
		dmg += _k.EXECUTIONER_BONUS
	return dmg


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

	# The invariant itself, not just this one pair. Step 5's damage rule tests
	# cover before flanking; _update_unit_panel tests flanking before cover.
	# Both are correct only because these two can never be true at once.
	_sweep_exclusive(board, "one wall")

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

	# A bad shooter, pinned: 10 - 25 is well under the floor.
	shooter.accuracy = 10
	shooter.suppress()
	_check(shooter.is_suppressed(), "the shooter is pinned")
	_check(_chance(board, shooter, target) == _k.MIN_HIT_CHANCE,
			"10%% accuracy minus the %d-point pin still gets a %d%% shot"
			% [_k.SUPPRESSION_ACCURACY, _k.MIN_HIT_CHANCE])
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
			"so _fire_round takes its `elif flanking:` arm, with cover NONE")
	_check(_damage(board, killer, target) == hit + _k.EXECUTIONER_BONUS,
			"a flanking round from the perked shooter deals %d"
			% (hit + _k.EXECUTIONER_BONUS))
	_check(_damage(board, plain, target) == hit,
			"the same flank without the perk deals %d" % hit)

	_check(_face_covered(target, killer), "now the target faces its wall")
	_check(not _flanking(killer, target)
			and _cover(board, killer, target) == Board.CoverLevel.FULL,
			"so the flanking arm is unreachable and the cover arm halves instead")
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

	shooter.free()
	target.free()
	board.free()
