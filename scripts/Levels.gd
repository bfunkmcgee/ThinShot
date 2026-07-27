class_name Levels

## Static campaign data. Map legend:
##   '.' open sand          '#' rock (blocks move + LOS)
##   'W' mud-brick wall (blocks move + LOS)
##   'j' rusted junk (partial cover: unwalkable, shots pass at half damage)
##   'p' plant (pure decoration, walkable)
## Structure footprints overlay their cells as full blockers.

const LEVELS: Array[Dictionary] = [
	{
		"name": "DRY WASH",
		"fiction": "The dry riverbed where the Rust Choir first crossed into scout territory.",
		"map": [
			".....p......",
			"..#......#..",
			".....##.....",
			"..#.j.#..#..",
			"..#..#.j.#..",
			".....##.....",
			"..#p.....#..",
			"........p..p",
		],
		"scout_spawns": [Vector2i(1, 2), Vector2i(1, 4), Vector2i(3, 3)],
		"goblin_spawns": [Vector2i(10, 1), Vector2i(10, 3), Vector2i(10, 5), Vector2i(10, 7)],
		"structures": [],
		"zone_seed": 7,
		"shade_seed": 13,
		"zone_thresholds": [-0.12, 0.22],
	},
	{
		"name": "THE SCRAPLINE",
		"fiction": "The Choir's scrap-tithe yard - tribute junk sung into rows.",
		"map": [
			".....j......",
			"..p.j.j.....",
			"............",
			"..#...j.j...",
			"..j....j.j..",
			"..........j.",
			"p..j.....j..",
			"............",
		],
		"scout_spawns": [Vector2i(1, 1), Vector2i(0, 3), Vector2i(1, 5)],
		"goblin_spawns": [Vector2i(11, 1), Vector2i(10, 3), Vector2i(11, 4), Vector2i(10, 6)],
		"structures": [
			{"kind": "hut_1", "anchor": Vector2i(9, 1), "size": Vector2i(2, 2)},
			{"kind": "tent", "anchor": Vector2i(7, 6), "size": Vector2i(2, 2)},
		],
		"zone_seed": 21,
		"shade_seed": 34,
		"zone_thresholds": [-0.5, -0.2],
	},
	{
		"name": "OUTPOST 7",
		"fiction": "The old desert command, now the Choir's hive. Two walls are down; the scouts go in at dawn.",
		"map": [
			"...p.WWW....",
			"..#.W.......",
			"............",
			"..#.W.......",
			"...jW...W...",
			"....WW.W..j.",
			"....j.......",
			".....j.p....",
		],
		"scout_spawns": [Vector2i(0, 3), Vector2i(0, 5), Vector2i(2, 7)],
		"goblin_spawns": [Vector2i(6, 1), Vector2i(7, 2), Vector2i(5, 3), Vector2i(6, 4)],
		"structures": [
			{"kind": "fortress", "anchor": Vector2i(8, 0), "size": Vector2i(4, 4)},
			{"kind": "hut_2", "anchor": Vector2i(1, 5), "size": Vector2i(2, 2)},
			{"kind": "hut_1", "anchor": Vector2i(9, 6), "size": Vector2i(2, 2)},
		],
		"zone_seed": 42,
		"shade_seed": 55,
		"zone_thresholds": [-0.12, 0.22],
	},
]

const SIZE := Vector2i(12, 8)
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
	assert(data.map.size() == SIZE.y, "%s: map must have %d rows" % [label, SIZE.y])
	for row: String in data.map:
		assert(row.length() == SIZE.x, "%s: row '%s' wrong length" % [label, row])
		for ch in row:
			assert(LEGAL_CHARS.contains(ch), "%s: illegal char '%s'" % [label, ch])
	var footprints := _footprint_cells(data)
	var seen_footprint := {}
	for s: Dictionary in data.structures:
		var anchor: Vector2i = s.anchor
		var size: Vector2i = s.size
		for dy in size.y:
			for dx in size.x:
				var cell: Vector2i = anchor + Vector2i(dx, dy)
				assert(cell.x >= 0 and cell.x < SIZE.x and cell.y >= 0 and cell.y < SIZE.y,
						"%s: structure %s out of bounds at %s" % [label, s.kind, cell])
				assert(not seen_footprint.has(cell),
						"%s: overlapping structures at %s" % [label, cell])
				seen_footprint[cell] = true
	# Walkable = '.' or 'p', outside every footprint.
	var walkable := func(cell: Vector2i) -> bool:
		if cell.x < 0 or cell.x >= SIZE.x or cell.y < 0 or cell.y >= SIZE.y:
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
