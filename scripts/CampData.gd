class_name CampData

## The two places the squad sleeps.
##
## The GARRISON is home: walls, huts, stores, and the only place the dead are
## replaced. The squad returns here between operations.
##
## The FIELD camp is what they put up between the missions of a single
## operation - a tent and whatever they carried in. Same functions, no walls,
## no permanence, and it dresses itself from the operation's biome.
##
## Both are shaped so Board.set_level() can eat them directly: that function
## reads only `size`, `map` and `structures`, and everything else has a
## default. Same map legend as Levels:
##   '.' open sand   '#' rock   'W' mud-brick wall   'j' scrap   'p' plant
##
## A 'j' cell named in a camp's optional `props` table is drawn as that fixture
## instead of a scrap pile. The char is doing real work either way - it is what
## makes the cell solid and gives it its contact shadow - so a fixture needs no
## rules of its own, and a camp with no `props` table behaves exactly as before.

## The base's furniture, keyed by the cell it stands on. Every one of these is
## a 'j' in the map below.
##
## Twelve of them, and the garrison has no scrap piles left at all - which was
## the point. Home used to be a walled yard with eight junk heaps in it, two of
## them wrecked car doors, and it read as a scrapheap the squad happened to
## sleep in rather than as anywhere the Accord posted them. Nothing here is
## interactive; the briefing table, stores and levy post are still the only
## things you can walk up to and use.
##
## The tall four - flagpole, watchtower, water tank, awning - are all on row 1,
## against the back wall. That is deliberate and worth keeping: they stand two
## soldiers high, and on the back row there is nothing behind them to hide.
const GARRISON_PROPS := {
	# The awning is 256px of canopy on a 128px cell - two tiles wide on a
	# one-tile stand. Against the back wall its right half hung past the wall
	# line over open desert, so it sits a rank in where the yard is wide enough
	# to hold it, still shading the west billet. Nothing else here is wide
	# enough to care, and the memorial takes the wall cell it gave up.
	Vector2i(5, 6): "awning",
	Vector2i(8, 1): "flagpole",       # the colours, behind the command table
	Vector2i(10, 1): "field_radio",
	Vector2i(11, 1): "jerry_cans",
	Vector2i(12, 1): "watchtower",    # the one corner that overlooks the gate road
	Vector2i(5, 2): "notice_board",   # the duty roster, on the parade side
	Vector2i(2, 3): "water_bowser",   # the Crown's own water, in a war about water
	Vector2i(11, 3): "water_tank",
	Vector2i(2, 4): "kit_frame",
	Vector2i(11, 5): "ammo_box",
	Vector2i(3, 1): "memorial_cross", # the garrison is where the dead are replaced
	Vector2i(3, 7): "washing_line",
	Vector2i(6, 8): "field_stove",
	Vector2i(11, 8): "cleaning_bench",
}

const GARRISON := {
	"size": Vector2i(14, 10),
	"map": [
		"WWWWWWWWWWWWWW",
		"W..j....j.jjjW",
		"W....j.......W",
		"W.j........j.W",
		"W.j..........W",
		"W..........j.W",
		"W....j.......W",
		"W..j.......p.W",
		"W.....j....j.W",
		"WWWWWWWWWWWWWW",
	],
	"props": GARRISON_PROPS,
	"structures": [
		{"kind": "hut_1", "anchor": Vector2i(1, 1), "size": Vector2i(2, 2)},
		{"kind": "hut_2", "anchor": Vector2i(1, 6), "size": Vector2i(2, 2)},
		{"kind": "stores_tent", "anchor": Vector2i(10, 6), "size": Vector2i(2, 2)},
	],
	"zone_seed": 91,
	"shade_seed": 17,
	"zone_thresholds": [-0.30, 0.10],
}

## Out on operation: one tent, some scrap, and open ground in every direction.
const FIELD := {
	"size": Vector2i(11, 8),
	"map": [
		"...........",
		"..j........",
		".......j...",
		"...........",
		"....j......",
		"..........j",
		"...j.......",
		"...........",
	],
	"structures": [
		{"kind": "field_tent", "anchor": Vector2i(7, 4), "size": Vector2i(2, 2)},
	],
	"zone_seed": 91,
	"shade_seed": 17,
	"zone_thresholds": [-0.30, 0.10],
}

const GARRISON_SPOTS := {
	"player": Vector2i(6, 5),
	"briefing": Vector2i(9, 2),
	"stores": Vector2i(9, 6),
	# Only the garrison can post replacements.
	"recruit": Vector2i(4, 8),
	"squad": [
		Vector2i(4, 3), Vector2i(4, 6), Vector2i(6, 2),
		Vector2i(7, 7), Vector2i(5, 8), Vector2i(8, 4),
	],
	"dressing": [Vector2i(8, 2), Vector2i(10, 2)],
}

const FIELD_SPOTS := {
	"player": Vector2i(5, 3),
	"briefing": Vector2i(4, 1),
	"stores": Vector2i(6, 5),
	"recruit": Vector2i(-1, -1),  # no replacements in the field
	"squad": [
		Vector2i(3, 2), Vector2i(3, 5), Vector2i(6, 2),
		Vector2i(7, 6), Vector2i(5, 6), Vector2i(2, 4),
	],
	"dressing": [Vector2i(6, 4)],
}


## The map for whichever camp the squad is in, with the biome's floor
## character applied: its tilesheet, tile family and shading. The map layout
## itself is the same wherever the squad pitches up.
static func map_for(in_field: bool, biome: Dictionary) -> Dictionary:
	var base: Dictionary = (FIELD if in_field else GARRISON).duplicate(true)
	base.floor = biome.get("floor", "desert")
	base.zone_seed = int(biome.get("floor_seed", 91))
	base.shade_seed = int(biome.get("shade_seed", 17))
	base.zone_thresholds = biome.get("thresholds", [-0.30, 0.10])
	# Prop variants follow the biome's floor seed the same way Battle's follow
	# the level's zone seed, so each biome's camp dresses itself its own way
	# and does it the same way every visit.
	base.prop_seed = int(biome.get("prop_seed", int(base.zone_seed) * 977 + 101))
	return base


static func spots_for(in_field: bool) -> Dictionary:
	return FIELD_SPOTS if in_field else GARRISON_SPOTS


static func _check(cond: bool, msg: String) -> bool:
	if not cond:
		push_error("[CampData] " + msg)
	return cond


## Walkable = '.' or 'p', outside every structure footprint. Same rule Levels
## validates against.
static func walkable(camp: Dictionary, cell: Vector2i) -> bool:
	var grid: Vector2i = camp.size
	if cell.x < 0 or cell.x >= grid.x or cell.y < 0 or cell.y >= grid.y:
		return false
	for s: Dictionary in camp.structures:
		var anchor: Vector2i = s.anchor
		var size: Vector2i = s.size
		if cell.x >= anchor.x and cell.x < anchor.x + size.x \
				and cell.y >= anchor.y and cell.y < anchor.y + size.y:
			return false
	var ch: String = camp.map[cell.y][cell.x]
	return ch == "." or ch == "p"


static func _reachable(camp: Dictionary, from: Vector2i) -> Dictionary:
	var seen := {from: true}
	var frontier: Array[Vector2i] = [from]
	while not frontier.is_empty():
		var cur: Vector2i = frontier.pop_front()
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nxt: Vector2i = cur + dir
			if seen.has(nxt) or not walkable(camp, nxt):
				continue
			seen[nxt] = true
			frontier.push_back(nxt)
	return seen


static func _validate_one(camp: Dictionary, spots: Dictionary, label: String) -> bool:
	var ok := true
	var grid: Vector2i = camp.size
	ok = _check(camp.map.size() == grid.y,
			"%s: map must have %d rows" % [label, grid.y]) and ok
	if not ok:
		return false
	for row: String in camp.map:
		ok = _check(row.length() == grid.x,
				"%s: row '%s' wrong length" % [label, row]) and ok
		for ch in row:
			ok = _check(".#Wjp".contains(ch),
					"%s: illegal char '%s'" % [label, ch]) and ok
	if not ok:
		return false
	var start: Vector2i = spots.player
	ok = _check(walkable(camp, start), "%s: player spawn %s not walkable" % [label, start]) and ok
	var reach := _reachable(camp, start)
	var seen := {start: true}
	var fixtures: Array[Vector2i] = [spots.briefing, spots.stores]
	if Vector2i(spots.recruit).x >= 0:
		fixtures.append(spots.recruit)
	fixtures.append_array(spots.squad)
	for cell: Vector2i in fixtures:
		ok = _check(walkable(camp, cell),
				"%s: fixture %s not walkable" % [label, cell]) and ok
		ok = _check(reach.has(cell),
				"%s: fixture %s unreachable from spawn" % [label, cell]) and ok
		ok = _check(not seen.has(cell),
				"%s: two fixtures share %s" % [label, cell]) and ok
		seen[cell] = true
	# The squad has to have somewhere to stand for every slot a level can field.
	ok = _check((spots.squad as Array).size() >= 5,
			"%s: only %d squad spots" % [label, (spots.squad as Array).size()]) and ok
	return ok


## Runs at boot. push_error-based so it reports in release too, matching
## Levels.validate_all().
static func validate() -> void:
	var ok := _validate_one(GARRISON, GARRISON_SPOTS, "garrison")
	ok = _validate_one(FIELD, FIELD_SPOTS, "field camp") and ok
	assert(ok, "Camp data invalid - see errors above")
