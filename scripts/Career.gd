class_name Career

## The career ladder: levels 1..100 instead of military ranks.
##
## Everything in this file is arithmetic over plain ints, with no Unit and no
## Node in any signature, for the same reason Rules.gd is written that way:
## tools/test_career.gd can pin the whole curve without standing up a scene.
##
## LAYERING. This file names nothing at all - not Rules, not Roll, not Game.
## Game holds each soldier's xp and level as plain dictionary fields and calls
## in here to interpret them; Unit calls in here to turn a level into stat
## bonuses. Do not have this file name anything, or the harnesses that preload
## Game.gd before the autoloads exist will drag a compile cascade in with it.

## The top of the ladder. XP keeps accruing past it but buys nothing more.
const MAX_LEVEL := 100

## The levels that grant a specialty choice. Exactly four, mapping 1:1 onto
## the four per-class perk pairs in Game.CLASS_PERK_RANKS - the trees are
## untouched; only the doors moved. perk_gate() is the bridge.
const PERK_LEVELS: Array[int] = [5, 15, 30, 50]

## Sleeve chevrons: one per this many levels, capped at CHEVRON_MAX. A level
## 100 veteran wears five; a first-campaign soldier wears one, maybe two.
const CHEVRON_LEVELS := 20
const CHEVRON_MAX := 5

# --- the curve ----------------------------------------------------------------

## Total XP required to REACH level `level`. Quadratic, tuned long-haul: one
## campaign's ~130 XP lands a soldier near level 30-35; level 100 is 1,226 XP,
## a multi-campaign career. Anchors the tests pin: T(1)=0, T(2)=1, T(5)=7,
## T(10)=22, T(15)=42, T(20)=68, T(25)=99, T(30)=136, T(50)=337, T(100)=1226.
##
## Computed in integers - floor(1.5n + 0.11n^2) with n = level-1 becomes
## (150n + 11n^2) / 100 exactly, so no float ever rounds an anchor sideways.
static func xp_for_level(level: int) -> int:
	var n := clampi(level, 1, MAX_LEVEL) - 1
	@warning_ignore("integer_division")
	return (150 * n + 11 * n * n) / 100

## The level a lifetime XP total has bought. Clamped 1..MAX_LEVEL; XP past the
## top of the curve is kept on the books but buys nothing.
static func level_for_xp(xp: int) -> int:
	var level := 1
	while level < MAX_LEVEL and xp >= xp_for_level(level + 1):
		level += 1
	return level

## XP still owed for the next level, or -1 at the cap (the debrief suppresses
## the line rather than promising a level that cannot come).
static func xp_to_next(xp: int) -> int:
	var level := level_for_xp(xp)
	if level >= MAX_LEVEL:
		return -1
	return xp_for_level(level + 1) - xp

# --- perk gates ---------------------------------------------------------------

## Which of the four perk pairs a gate level opens: 1..4 for the PERK_LEVELS,
## 0 for any other level. The return value is the key Game.perk_choices()
## already takes, so the class trees never hear that ranks are gone.
static func perk_gate(level: int) -> int:
	var at := PERK_LEVELS.find(level)
	return at + 1 if at >= 0 else 0

## The gate levels crossed moving from `old_level` (exclusive) to `new_level`
## (inclusive). A subset of PERK_LEVELS by construction, so the promotion
## queue stays sparse - at most four entries in a whole career.
static func gates_crossed(old_level: int, new_level: int) -> Array:
	var crossed: Array = []
	for gate_level in PERK_LEVELS:
		if old_level < gate_level and new_level >= gate_level:
			crossed.append(gate_level)
	return crossed

# --- per-level growth ---------------------------------------------------------
# Every single level-up raises exactly one stat by 1, alternating by parity:
# even levels pay +1 accuracy, odd levels pay +1 max HP. So the two bonuses
# below always sum to level - 1, and neither ever jumps by more than 1.
# The 95 accuracy cap is the consumer's to apply (Unit.apply_progression does,
# once, after gear) - veteran classes absorb late accuracy gains into the cap.

## Cumulative accuracy bonus at a level: +1 at every EVEN level.
## L2 -> 1, L10 -> 5, L30 -> 15, L100 -> 50.
static func accuracy_bonus_at(level: int) -> int:
	@warning_ignore("integer_division")
	return clampi(level, 1, MAX_LEVEL) / 2

## Cumulative max-HP bonus at a level: +1 at every ODD level past the first.
## L3 -> 1, L21 -> 10, L100 -> 49.
static func hp_bonus_at(level: int) -> int:
	@warning_ignore("integer_division")
	return (clampi(level, 1, MAX_LEVEL) - 1) / 2

# --- display ------------------------------------------------------------------

## Sleeve chevrons for a level. Non-career units (career_level 0) get none.
static func chevrons_for(level: int) -> int:
	@warning_ignore("integer_division")
	return clampi(level / CHEVRON_LEVELS, 0, CHEVRON_MAX)

## The label everything prints. One format, one place.
static func level_label(level: int) -> String:
	return "Level %d" % level
