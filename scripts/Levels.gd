class_name Levels

## Static campaign data. Map legend:
##   '.' open sand          '#' rock (blocks move + LOS)
##   'W' mud-brick wall (blocks move + LOS)
##   'j' rusted junk (partial cover: unwalkable, shots pass at half damage)
##   'p' plant (pure decoration, walkable)
## Structure footprints overlay their cells as full blockers.

const LEVELS: Array[Dictionary] = [
	{
		# Three lanes: open wash through the middle, rock outcrops guarding
		# the north and south rims. Junk covers the two wash crossings.
		"name": "DRY WASH",
		"fiction": "The dry riverbed where the Rust Choir first crossed into scout territory.",
		"size": Vector2i(16, 10),
		"map": [
			"......p.........",
			"....##.....#..p.",
			"....##.....##...",
			".#.....j........",
			"................",
			"................",
			"..#.....j.....#.",
			"...#......##....",
			"...#p.....##..p.",
			".........p......",
		],
		"scout_spawns": [Vector2i(0, 3), Vector2i(0, 5), Vector2i(1, 7)],
		"goblin_spawns": [Vector2i(15, 2), Vector2i(14, 4), Vector2i(15, 6), Vector2i(15, 8)],
		"structures": [],
		"zone_seed": 7,
		"shade_seed": 13,
		"zone_thresholds": [-0.12, 0.22],
	},
	{
		# A junk barricade wall bisects the yard at x=8 with three gates
		# (y 2, 5, 8). The Choir compound sits behind it; loose scrap gives
		# the scouts approach cover in front.
		"name": "THE SCRAPLINE",
		"fiction": "The Choir's scrap-tithe yard - tribute junk sung into rows.",
		"size": Vector2i(16, 10),
		"map": [
			".p......j.......",
			"....j...j.......",
			"..#.............",
			"........j.j.....",
			"........j..j....",
			"p...............",
			".....j..j.......",
			"..#.....j.......",
			"................",
			"......p.j.......",
		],
		"scout_spawns": [Vector2i(0, 2), Vector2i(1, 4), Vector2i(0, 7)],
		"goblin_spawns": [
			Vector2i(10, 2), Vector2i(14, 4), Vector2i(10, 5),
			Vector2i(10, 8), Vector2i(14, 8),
		],
		"structures": [
			{"kind": "hut_1", "anchor": Vector2i(12, 1), "size": Vector2i(2, 2)},
			{"kind": "tent", "anchor": Vector2i(12, 6), "size": Vector2i(2, 2)},
		],
		"zone_seed": 21,
		"shade_seed": 34,
		"zone_thresholds": [-0.5, -0.2],
	},
	{
		# The fortress compound: walled courtyard with a west gate (5,3) and
		# two south gates (7,7) and (11,7); the east flank is open. A small
		# hamlet outside gives the scouts staging cover.
		"name": "OUTPOST 7",
		"fiction": "The old desert command, now the Choir's hive. The scouts go in at dawn.",
		"size": Vector2i(16, 10),
		"map": [
			"....p.WWWWW.....",
			".....W..........",
			".....W..........",
			"...j............",
			".....W..........",
			"...#.W..........",
			".....W..........",
			".....WW.WWW.WW..",
			"....#....j..j...",
			"......p........p",
		],
		"scout_spawns": [Vector2i(0, 3), Vector2i(0, 5), Vector2i(2, 8)],
		"goblin_spawns": [
			Vector2i(7, 2), Vector2i(9, 3), Vector2i(6, 5),
			Vector2i(11, 5), Vector2i(12, 6),
		],
		"structures": [
			{"kind": "fortress", "anchor": Vector2i(10, 1), "size": Vector2i(4, 4)},
			{"kind": "hut_1", "anchor": Vector2i(1, 1), "size": Vector2i(2, 2)},
			{"kind": "hut_2", "anchor": Vector2i(1, 6), "size": Vector2i(2, 2)},
		],
		"zone_seed": 42,
		"shade_seed": 55,
		"zone_thresholds": [-0.12, 0.22],
	},
]

const LEGAL_CHARS := ".#Wjp"


## Asserts every level is well-formed. Cheap; run on debug boots so one
## headless run validates the whole campaign.
static func validate_all() -> void:
	for i in LEVELS.size():
		_validate(i)


static func _footprint_cells(data: Dictionary) -> Dictionary:
	var cells := {}
	for s: Dictionary in data.structures:
		var anchor: Vector2i = s.anchor
		var size: Vector2i = s.size
		for dy in size.y:
			for dx in size.x:
				cells[anchor + Vector2i(dx, dy)] = true
	return cells


static func _validate(index: int) -> void:
	var data: Dictionary = LEVELS[index]
	var label: String = "Level %d '%s'" % [index + 1, data.name]
	var grid: Vector2i = data.size
	assert(data.map.size() == grid.y, "%s: map must have %d rows" % [label, grid.y])
	for row: String in data.map:
		assert(row.length() == grid.x, "%s: row '%s' wrong length" % [label, row])
		for ch in row:
			assert(LEGAL_CHARS.contains(ch), "%s: illegal char '%s'" % [label, ch])
	var footprints := _footprint_cells(data)
	var seen_footprint := {}
	for s: Dictionary in data.structures:
		var anchor: Vector2i = s.anchor
		var struct_size: Vector2i = s.size
		for dy in struct_size.y:
			for dx in struct_size.x:
				var cell: Vector2i = anchor + Vector2i(dx, dy)
				assert(cell.x >= 0 and cell.x < grid.x and cell.y >= 0 and cell.y < grid.y,
						"%s: structure %s out of bounds at %s" % [label, s.kind, cell])
				assert(not seen_footprint.has(cell),
						"%s: overlapping structures at %s" % [label, cell])
				seen_footprint[cell] = true
	# Walkable = '.' or 'p', outside every footprint.
	var walkable := func(cell: Vector2i) -> bool:
		if cell.x < 0 or cell.x >= grid.x or cell.y < 0 or cell.y >= grid.y:
			return false
		if footprints.has(cell):
			return false
		var ch: String = data.map[cell.y][cell.x]
		return ch == "." or ch == "p"
	var spawns: Array = data.scout_spawns + data.goblin_spawns
	var seen_spawn := {}
	for spawn: Vector2i in spawns:
		assert(walkable.call(spawn), "%s: spawn %s not walkable" % [label, spawn])
		assert(not seen_spawn.has(spawn), "%s: duplicate spawn %s" % [label, spawn])
		seen_spawn[spawn] = true
	# Reachability: every spawn connected to the first scout spawn.
	var start: Vector2i = data.scout_spawns[0]
	var visited := {start: true}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var cur: Vector2i = frontier.pop_front()
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nxt: Vector2i = cur + dir
			if visited.has(nxt) or not walkable.call(nxt):
				continue
			visited[nxt] = true
			frontier.push_back(nxt)
	for spawn: Vector2i in spawns:
		assert(visited.has(spawn), "%s: spawn %s unreachable from %s" % [label, spawn, start])
