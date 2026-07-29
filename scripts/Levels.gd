class_name Levels

## Static campaign data.
##
## Each level carries an ordered "objectives" list; a level with none defaults
## to wiping out the Choir, which is what the first one does. Objectives are
## completed in order, and the level is won when the last one is:
##   {"kind": "eliminate"}                       - kill every goblin
##   {"kind": "destroy", "cells": [...]}         - demolish every tithe cache
##   {"kind": "extract", "cells": [...]}         - every surviving scout to the
##                                                 zone, and only once every
##                                                 earlier objective is done
## Losing is unchanged and unconditional: the squad dies, you lose.
##
## Map legend:
##   '.' open sand          '#' rock (blocks move + LOS)
##   'W' mud-brick wall (blocks move + LOS)
##   'j' rusted junk (partial cover: unwalkable, shots pass at half damage)
##   'p' plant (pure decoration, walkable)
## Structure footprints overlay their cells as full blockers.

const LEVELS: Array[Dictionary] = [
	{
		# Four rock outcrops pinch the field into three lanes, and a junk
		# island splits the middle one so it cannot be walked straight down.
		# Every lane has a piece of cover to bound between, and each cover
		# piece has open ground on both sides so it can be flanked around.
		# Goblins hold in pairs, one per lane, which is what gives the
		# gunner's suppression something worth pinning.
		"name": "DRY WASH",
		"fiction": "The dry riverbed where the Rust Choir first crossed into scout territory.",
		"size": Vector2i(16, 10),
		"map": [
			"..p.##.....##...",
			"....##...p.##...",
			"......j.........",
			"..........j.....",
			".......jj....j..",
			".......jj....j..",
			"...p......j.....",
			"......j.......p.",
			"....##.....##...",
			"....##..p..##...",
		],
		"scout_spawns": [Vector2i(1, 2), Vector2i(1, 7), Vector2i(2, 4)],
		"lead_spawns": [Vector2i(0, 5)],
		"gunner_spawns": [Vector2i(2, 5)],
		"goblin_spawns": [
			Vector2i(13, 1), Vector2i(14, 4), Vector2i(14, 8),
		],
		# Raiders start a lane ahead of the riflemen and come straight on.
		# One per lane, and the southern one is the scrawny variant - open
		# ground is where his extra tile of movement reads clearest.
		"smg_spawns": [Vector2i(12, 3)],
		"smg_alt_spawns": [Vector2i(12, 6)],
		# Novices are pushed out in front of everyone as a screen.
		"novice_spawns": [Vector2i(15, 2), Vector2i(15, 5), Vector2i(15, 7)],
		# The Cantor sits at the back of the middle lane behind the junk
		# island, so he only starts mattering once the squad is most of the
		# way across - the backstop rather than the opening problem.
		"bolt_spawns": [Vector2i(15, 4)],
		"structures": [],
		"zone_seed": 7,
		"shade_seed": 13,
		"zone_thresholds": [-0.12, 0.22],
	},
	{
		# Two scrap barricades in depth. The outer line (x=6) has gates at
		# y=3 and y=7; the inner line (x=11) has gates at y=1 and y=5 -
		# deliberately offset, so breaching the first one leaves you crossing
		# the yard sideways under fire to reach the second. Gate defenders
		# stand in pairs, and the corridor between the lines is the killing
		# ground the machinegunner exists for.
		"name": "THE SCRAPLINE",
		"fiction": "The Choir's scrap-tithe yard - tribute junk sung into rows.",
		"size": Vector2i(16, 10),
		"map": [
			".p....j..p.j....",
			"......j.........",
			"...j..j....j....",
			"...........j....",
			"......j....j....",
			"....j.j.........",
			"......j....j....",
			"...j.......j....",
			"......j....j....",
			"..p...j..p.j....",
		],
		"scout_spawns": [Vector2i(1, 1), Vector2i(1, 8), Vector2i(2, 5)],
		"lead_spawns": [Vector2i(0, 4)],
		"gunner_spawns": [Vector2i(2, 4)],
		"goblin_spawns": [
			Vector2i(7, 3), Vector2i(8, 3),    # north gate
			Vector2i(7, 7), Vector2i(8, 7),    # south gate
		],
		# Raiders wait in the corridor between the barricades, ready to
		# rush whichever gate the scouts commit to. The skirmishers are the
		# ones who can cross it in a single turn, so a second waits deep.
		"smg_spawns": [Vector2i(9, 1)],
		"smg_alt_spawns": [Vector2i(9, 8), Vector2i(12, 2)],
		"novice_spawns": [Vector2i(12, 5), Vector2i(15, 2), Vector2i(15, 7)],
		# Behind the inner barricade with junk at (11,4) to hide behind, five
		# tiles of reach covering the corridor lengthwise. Crossing between
		# the lines now costs something even when the gates are clear.
		"bolt_spawns": [Vector2i(12, 4)],
		"structures": [
			{"kind": "hut_1", "anchor": Vector2i(13, 2), "size": Vector2i(2, 2)},
			{"kind": "tent", "anchor": Vector2i(13, 6), "size": Vector2i(2, 2)},
		],
		# The tithe itself. Three caches spread corner to corner behind the
		# barricades, so clearing the yard is the only way to reach them all -
		# and a body count no longer ends the level. All three sit clear of the
		# hut and tent sprites, which are tall enough to paint over a cell
		# several rows in front of their own footprint.
		"objectives": [
			{
				"kind": "destroy",
				"label": "BURN THE TITHE CACHES",
				"cells": [Vector2i(15, 1), Vector2i(14, 4), Vector2i(12, 8)],
			},
		],
		"zone_seed": 21,
		"shade_seed": 34,
		"zone_thresholds": [-0.5, -0.2],
	},
	{
		# A properly sealed compound this time. The fortress is flush to the
		# east edge so there is no walking around the back: the only ways in
		# are the west gate (8,4) and the two south gates (11,7) and (14,7).
		# Three ways in, all covered, and the garrison holds each in pairs.
		# The hamlet and rocks outside give the squad staging cover to set
		# the gun up before anyone steps into a gateway.
		"name": "OUTPOST 7",
		"fiction": "The old desert command, now the Choir's hive. The scouts go in at dawn.",
		"size": Vector2i(16, 10),
		"map": [
			".p......WWWWWWWW",
			"......p.W.......",
			".....#..W.......",
			".....#..W.......",
			"....j...........",
			"......j.W.......",
			"........W.......",
			".........WW.WW.W",
			"....p.j.........",
			".......p........",
		],
		"scout_spawns": [Vector2i(0, 2), Vector2i(1, 8), Vector2i(0, 6)],
		"lead_spawns": [Vector2i(0, 4)],
		"gunner_spawns": [Vector2i(1, 5)],
		"goblin_spawns": [
			Vector2i(9, 3), Vector2i(9, 4),    # west gate
			Vector2i(10, 1),                   # courtyard
			Vector2i(14, 5),                   # fortress door
		],
		# Raiders hold the south gates and counter-attack through them; a
		# skirmisher in the courtyard reaches whichever gateway breaks first.
		"smg_spawns": [Vector2i(10, 6)],
		"smg_alt_spawns": [Vector2i(11, 6), Vector2i(11, 2)],
		"novice_spawns": [Vector2i(10, 2), Vector2i(13, 5), Vector2i(15, 6)],
		# Laid in on the west gate at (8,4) from five tiles back, straight
		# down the entry lane. The gateway is the obvious way in, and this is
		# what makes walking through it the wrong idea.
		"bolt_spawns": [Vector2i(11, 4)],
		"structures": [
			{"kind": "fortress", "anchor": Vector2i(12, 1), "size": Vector2i(4, 4)},
			{"kind": "hut_1", "anchor": Vector2i(2, 1), "size": Vector2i(2, 2)},
			{"kind": "hut_2", "anchor": Vector2i(2, 6), "size": Vector2i(2, 2)},
		],
		# A raid, not a massacre: blow the magazines, then walk everyone back
		# out the way they came in. The extraction zone is the ground the squad
		# started on, so the level ends where it began and the last stretch is
		# a fighting withdrawal.
		# The fortress sprite is 512px square and swallows most of the northern
		# compound, so the western magazine sits at (10,4) rather than deeper
		# in - close behind the west-gate defenders and the Cantor, which makes
		# it something to fight toward rather than something to hunt for.
		"objectives": [
			{
				"kind": "destroy",
				"label": "BLOW THE MAGAZINES",
				"cells": [Vector2i(10, 4), Vector2i(14, 6)],
			},
			{
				"kind": "extract",
				"label": "EXTRACT THE SQUAD",
				"cells": [
					Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4),
					Vector2i(0, 5), Vector2i(0, 6), Vector2i(0, 7),
				],
			},
		],
		"zone_seed": 42,
		"shade_seed": 55,
		"zone_thresholds": [-0.12, 0.22],
	},
]

const LEGAL_CHARS := ".#Wjp"


## Validates every level. push_error-based so it also reports in release
## builds (asserts are stripped there); debug builds additionally hard-stop.
static func validate_all() -> void:
	var ok := true
	for i in LEVELS.size():
		ok = _validate(i) and ok
	assert(ok, "Level data invalid - see errors above")


static func _check(cond: bool, msg: String) -> bool:
	if not cond:
		push_error("[Levels] " + msg)
	return cond


static func _footprint_cells(data: Dictionary) -> Dictionary:
	var cells := {}
	for s: Dictionary in data.structures:
		var anchor: Vector2i = s.anchor
		var size: Vector2i = s.size
		for dy in size.y:
			for dx in size.x:
				cells[anchor + Vector2i(dx, dy)] = true
	return cells


static func _validate(index: int) -> bool:
	var data: Dictionary = LEVELS[index]
	var label: String = "Level %d '%s'" % [index + 1, data.name]
	var grid: Vector2i = data.size
	var ok := _check(data.map.size() == grid.y, "%s: map must have %d rows" % [label, grid.y])
	if not ok:
		return false  # row checks below would misindex
	for row: String in data.map:
		ok = _check(row.length() == grid.x, "%s: row '%s' wrong length" % [label, row]) and ok
		for ch in row:
			ok = _check(LEGAL_CHARS.contains(ch), "%s: illegal char '%s'" % [label, ch]) and ok
	if not ok:
		return false
	var footprints := _footprint_cells(data)
	var seen_footprint := {}
	for s: Dictionary in data.structures:
		var anchor: Vector2i = s.anchor
		var struct_size: Vector2i = s.size
		for dy in struct_size.y:
			for dx in struct_size.x:
				var cell: Vector2i = anchor + Vector2i(dx, dy)
				ok = _check(cell.x >= 0 and cell.x < grid.x and cell.y >= 0 and cell.y < grid.y,
						"%s: structure %s out of bounds at %s" % [label, s.kind, cell]) and ok
				ok = _check(not seen_footprint.has(cell),
						"%s: overlapping structures at %s" % [label, cell]) and ok
				seen_footprint[cell] = true
	# Walkable = '.' or 'p', outside every footprint.
	var walkable := func(cell: Vector2i) -> bool:
		if cell.x < 0 or cell.x >= grid.x or cell.y < 0 or cell.y >= grid.y:
			return false
		if footprints.has(cell):
			return false
		var ch: String = data.map[cell.y][cell.x]
		return ch == "." or ch == "p"
	var spawns: Array = data.scout_spawns + data.get("lead_spawns", []) \
			+ data.get("gunner_spawns", []) + data.goblin_spawns \
			+ data.get("smg_spawns", []) + data.get("smg_alt_spawns", []) \
			+ data.get("novice_spawns", []) + data.get("bolt_spawns", [])
	var seen_spawn := {}
	for spawn: Vector2i in spawns:
		ok = _check(walkable.call(spawn), "%s: spawn %s not walkable" % [label, spawn]) and ok
		ok = _check(not seen_spawn.has(spawn), "%s: duplicate spawn %s" % [label, spawn]) and ok
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
		ok = _check(visited.has(spawn),
				"%s: spawn %s unreachable from %s" % [label, spawn, start]) and ok
	ok = _validate_objectives(data, label, walkable, visited, seen_spawn) and ok
	return ok


## The squad size an extraction zone has to be able to hold. Every scout still
## alive has to fit inside it at once, so a zone smaller than the whole squad
## would make the level unwinnable on a no-casualty run.
static func squad_size(data: Dictionary) -> int:
	return data.scout_spawns.size() + data.get("lead_spawns", []).size() \
			+ data.get("gunner_spawns", []).size()


static func _validate_objectives(data: Dictionary, label: String,
		walkable: Callable, visited: Dictionary, spawns: Dictionary) -> bool:
	var ok := true
	var objectives: Array = data.get("objectives", [])
	var seen_cell := {}
	for obj: Dictionary in objectives:
		var kind: String = obj.get("kind", "")
		ok = _check(kind == "eliminate" or kind == "destroy" or kind == "extract",
				"%s: unknown objective kind '%s'" % [label, kind]) and ok
		if kind == "eliminate":
			continue
		var cells: Array = obj.get("cells", [])
		ok = _check(not cells.is_empty(),
				"%s: '%s' objective needs cells" % [label, kind]) and ok
		for cell: Vector2i in cells:
			ok = _check(walkable.call(cell),
					"%s: objective cell %s not walkable" % [label, cell]) and ok
			ok = _check(visited.has(cell),
					"%s: objective cell %s unreachable" % [label, cell]) and ok
			ok = _check(not seen_cell.has(cell),
					"%s: objective cell %s used twice" % [label, cell]) and ok
			seen_cell[cell] = true
			# A cache sitting under a starting unit reads as a bug even
			# though nothing about it actually breaks.
			if kind == "destroy":
				ok = _check(not spawns.has(cell),
						"%s: cache %s sits on a spawn" % [label, cell]) and ok
		if kind == "extract":
			ok = _check(cells.size() >= squad_size(data),
					"%s: extraction zone holds %d, squad is %d" % [
							label, cells.size(), squad_size(data)]) and ok
	return ok
