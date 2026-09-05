class_name ArenaData

## THE RANGE: the ground the live-fire drill is fought on.
##
## One map for now, shaped to be eaten by Board.set_level() exactly as the
## camps are (CampData): `size`, `map`, `structures`, and the rest defaulted.
## Same legend as Levels - '.' open sand, '#' rock (blocks sight, full cover
## to whoever stands beside it), 'j' scrap (half cover you can shoot over),
## 'p' plant. Nothing else: no walls, no wire, no buildings. The drill is
## about the ground between the cover, not about a position to hold.
##
## Bigger than a mission board (20x14 against 16x10) for one reason: the
## Thirst arrives from the edges, and a wave that spawns in the player's lap is
## a wave that was never fought. The outer ring is kept clear on all four
## sides - it is where they come on - and the cover sits inboard of it.
const RANGE := {
	"size": Vector2i(20, 14),
	"map": [
		"....................",
		"....................",
		"..#......j.......#..",
		"...j...........j....",
		"......jj....p.......",
		"..p.........jj......",
		".......#........j...",
		"...j........#.......",
		"......jj............",
		"..#.........j..p....",
		"....p....j.......#..",
		"....................",
		"....................",
		"....................",
	],
	"structures": [],
	"floor": "desert",
	"zone_seed": 91,
	"shade_seed": 17,
	"zone_thresholds": [-0.30, 0.10],
}

## Where Rodar stands when the drill opens: the middle of the range, so the
## first wave has the same walk from every edge.
const PLAYER_SPAWN := Vector2i(10, 7)

## The scenery-variant hash seed, mirroring CampData.map_for's derivation.
const PROP_SEED := 91 * 977 + 101


## Every walkable cell on the outer ring. The wave director draws its spawn
## points from these; nothing else uses them.
static func spawn_rim(data: Dictionary) -> Array[Vector2i]:
	var grid: Vector2i = data.size
	var rim: Array[Vector2i] = []
	for x in grid.x:
		for y in grid.y:
			if x == 0 or y == 0 or x == grid.x - 1 or y == grid.y - 1:
				var cell := Vector2i(x, y)
				if data.map[y][x] == ".":
					rim.append(cell)
	return rim


static func _check(cond: bool, msg: String) -> bool:
	if not cond:
		push_error("[ArenaData] " + msg)
	return cond


## Walkable = '.' or 'p', same as CampData and Levels. No structures here, so
## there are no footprints to subtract.
static func walkable(data: Dictionary, cell: Vector2i) -> bool:
	var grid: Vector2i = data.size
	if cell.x < 0 or cell.x >= grid.x or cell.y < 0 or cell.y >= grid.y:
		return false
	var ch: String = data.map[cell.y][cell.x]
	return ch == "." or ch == "p"


static func _reachable(data: Dictionary, from: Vector2i) -> Dictionary:
	var seen := {from: true}
	var frontier: Array[Vector2i] = [from]
	while not frontier.is_empty():
		var cur: Vector2i = frontier.pop_front()
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nxt: Vector2i = cur + dir
			if seen.has(nxt) or not walkable(data, nxt):
				continue
			seen[nxt] = true
			frontier.push_back(nxt)
	return seen


## Runs at the arena's boot. push_error-based so it reports in release too,
## matching CampData.validate() and Levels.validate_all().
static func validate() -> void:
	var ok := true
	var grid: Vector2i = RANGE.size
	ok = _check(RANGE.map.size() == grid.y, "map must have %d rows" % grid.y) and ok
	if not ok:
		assert(false, "Arena data invalid - see errors above")
		return
	for row: String in RANGE.map:
		ok = _check(row.length() == grid.x, "row '%s' wrong length" % row) and ok
		for ch in row:
			ok = _check(".#jp".contains(ch), "illegal char '%s'" % ch) and ok
	ok = _check(walkable(RANGE, PLAYER_SPAWN), "player spawn %s not walkable" % PLAYER_SPAWN) and ok
	var rim := spawn_rim(RANGE)
	# A wave has to be able to come on from every side, or the "away from the
	# player" pick collapses onto one edge and the drill has a safe wall.
	ok = _check(rim.size() >= 40, "only %d walkable rim cells" % rim.size()) and ok
	var reach := _reachable(RANGE, PLAYER_SPAWN)
	for cell: Vector2i in rim:
		ok = _check(reach.has(cell), "rim cell %s cannot reach the player" % cell) and ok
	assert(ok, "Arena data invalid - see errors above")
