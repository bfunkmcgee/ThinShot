class_name CampData

## The base camp the squad lives in between missions.
##
## Shaped so Board.set_level() can eat it directly - that function reads only
## `size`, `map` and `structures`, and everything else it needs has a default.
## Same map legend as Levels:
##   '.' open sand   '#' rock   'W' mud-brick wall   'j' scrap   'p' plant
##
## A camp is not a battlefield, so the walls here enclose rather than divide:
## a wadi wall along the north and east, huts and a tent for the squad, and
## scrap and scrub for the eye to rest on. Everything the player has to reach
## sits on open ground with a clear route to it, which validate() enforces.

const CAMP := {
	"size": Vector2i(14, 10),
	"map": [
		"WWWWWWWWWWWWWW",
		"W..p.......j.W",
		"W....j.......W",
		"W..........j.W",
		"W.j..........W",
		"W..........j.W",
		"W....j.......W",
		"W..j.......p.W",
		"W..........j.W",
		"WWWWWWWWWWWWWW",
	],
	"structures": [
		# The squad's quarters along the west side, and the stores tent east.
		{"kind": "hut_1", "anchor": Vector2i(1, 1), "size": Vector2i(2, 2)},
		{"kind": "hut_2", "anchor": Vector2i(1, 6), "size": Vector2i(2, 2)},
		{"kind": "tent", "anchor": Vector2i(10, 6), "size": Vector2i(2, 2)},
	],
	"zone_seed": 91,
	"shade_seed": 17,
	"zone_thresholds": [-0.30, 0.10],
}

## Where the player starts, and where each fixture stands. Squad slots are
## walked in order, so soldier 1 always stands in the same place.
const PLAYER_SPAWN := Vector2i(6, 5)
const BRIEFING_TABLE := Vector2i(9, 2)
const STORES_TENT := Vector2i(9, 6)
const SQUAD_SPOTS: Array[Vector2i] = [
	Vector2i(4, 3), Vector2i(4, 6), Vector2i(6, 2),
	Vector2i(7, 7), Vector2i(5, 8), Vector2i(8, 4),
]

## Props that dress the camp without blocking anything, as cell -> kind.
const DRESSING := {
	Vector2i(8, 2): "crates",
	Vector2i(10, 2): "crates",
}


static func _check(cond: bool, msg: String) -> bool:
	if not cond:
		push_error("[CampData] " + msg)
	return cond


## Walkable = '.' or 'p', outside every structure footprint. Same rule Levels
## validates against.
static func walkable(cell: Vector2i) -> bool:
	var grid: Vector2i = CAMP.size
	if cell.x < 0 or cell.x >= grid.x or cell.y < 0 or cell.y >= grid.y:
		return false
	for s: Dictionary in CAMP.structures:
		var anchor: Vector2i = s.anchor
		var size: Vector2i = s.size
		if cell.x >= anchor.x and cell.x < anchor.x + size.x \
				and cell.y >= anchor.y and cell.y < anchor.y + size.y:
			return false
	var ch: String = CAMP.map[cell.y][cell.x]
	return ch == "." or ch == "p"


## Every walkable cell reachable from the player's spawn.
static func _reachable() -> Dictionary:
	var seen := {PLAYER_SPAWN: true}
	var frontier: Array[Vector2i] = [PLAYER_SPAWN]
	while not frontier.is_empty():
		var cur: Vector2i = frontier.pop_front()
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nxt: Vector2i = cur + dir
			if seen.has(nxt) or not walkable(nxt):
				continue
			seen[nxt] = true
			frontier.push_back(nxt)
	return seen


## Runs at boot. push_error-based so it reports in release too, matching
## Levels.validate_all().
static func validate() -> void:
	var ok := true
	var grid: Vector2i = CAMP.size
	ok = _check(CAMP.map.size() == grid.y,
			"map must have %d rows" % grid.y) and ok
	if not ok:
		assert(false, "Camp data invalid - see errors above")
		return
	for row: String in CAMP.map:
		ok = _check(row.length() == grid.x, "row '%s' wrong length" % row) and ok
		for ch in row:
			ok = _check(".#Wjp".contains(ch), "illegal char '%s'" % ch) and ok
	if not ok:
		assert(false, "Camp data invalid - see errors above")
		return
	ok = _check(walkable(PLAYER_SPAWN), "player spawn %s not walkable" % PLAYER_SPAWN) and ok
	# The squad must be able to fill every slot without standing in a wall, and
	# the player must be able to walk to everything they are asked to use.
	var reach := _reachable()
	var seen := {PLAYER_SPAWN: true}
	for spot: Vector2i in SQUAD_SPOTS:
		ok = _check(walkable(spot), "squad spot %s not walkable" % spot) and ok
		ok = _check(not seen.has(spot), "two fixtures share %s" % spot) and ok
		seen[spot] = true
	for named in [["briefing table", BRIEFING_TABLE], ["stores tent", STORES_TENT]]:
		var cell: Vector2i = named[1]
		ok = _check(walkable(cell), "%s %s not walkable" % [named[0], cell]) and ok
		ok = _check(reach.has(cell), "%s %s unreachable from spawn" % [named[0], cell]) and ok
		ok = _check(not seen.has(cell), "two fixtures share %s" % cell) and ok
		seen[cell] = true
	# Every soldier has to be walkable-up-to, or a promotion could be stranded.
	for spot: Vector2i in SQUAD_SPOTS:
		ok = _check(reach.has(spot), "squad spot %s unreachable from spawn" % spot) and ok
	assert(ok, "Camp data invalid - see errors above")
