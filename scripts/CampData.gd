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
## Seventeen of them, and the garrison has no scrap piles left at all - which was
## the point. Home used to be a walled yard with eight junk heaps in it, two of
## them wrecked car doors, and it read as a scrapheap the squad happened to
## sleep in rather than as anywhere the Accord posted them. Nothing here is
## interactive; the briefing table, stores and levy post are still the only
## things you can walk up to and use.
##
## The tall four - flagpole, watchtower, water tank, awning - are all on row 1,
## against the back wall. That is deliberate and worth keeping: they stand two
## soldiers high, and on the back row there is nothing behind them to hide.
## The garrison is laid out in QUARTERS now, because it stopped being scenery.
## Four of its fixtures are interactive stations (briefing, stores, bounties,
## the levy) and four more are becoming ones (signals/ratline, ledger,
## quartermaster, the surgeon) - and in the old 14x10 yard they all sat in one
## undifferentiated ring of props. A player looking for "where do missions
## come from" needs the ground itself to answer, so like goes with like:
##
##   NW - COMMAND: the command billet, the colours, the briefing table with
##        its map crates, and the paymaster's desk (#25) - scenery until the
##        money moves off the memorial. Deployment happens here.
##   NE - SIGNALS: the signals station (#24) under the watchtower - a guyed
##        lattice mast over the border desk. The ratline hook rides it.
##   E  - LOGISTICS: the stores tent with the stores spot at its door, water
##        tank, ammo, fuel, and the quartermaster's issue counter (#26) at
##        the tent's side - the QM hook rides it; the kit frame dries kit.
##   W  - THE MEMORIAL: the cross alone in a planted row. Nothing else stands
##        near it, which is the point.
##   SW - DOMESTIC: the squad billet, the awning's shade, washing, the stove,
##        the kit frame. Where the soldiers idle.
##   S  - PARADE: the duty roster, the Accord's own bounty board (#23)
##        beside it - posted sheets or bare cork by the campaign's state -
##        and the levy post, on the open ground the player walks first.
##   SE - the second tent stands where the surgeon's tent (#27) will: the
##        wounds rule already promises "a surgeon with time", and the ground
##        now says roughly where he works.
##
## The Tier 6 stands landed 2026-08-24 exactly as reserved: each held-open
## cell flipped to 'j', one props line each, and the hook pointed at the new
## name - which is what reserving them was for.
const GARRISON_PROPS := {
	# NW - command
	Vector2i(4, 1): "flagpole",
	# NW - command: the paymaster's desk beside the colours (ASSETS.md #25).
	# Scenery for now: the ledger stays at the memorial, deliberately.
	Vector2i(6, 1): "paymaster_desk",
	# NE - signals: the ratline's mission-giver is a LANDMARK now (#24) - a
	# guyed lattice mast over the border desk, on the back row with the tall.
	Vector2i(12, 1): "signals_mast",
	Vector2i(13, 1): "watchtower",
	# W - the memorial, alone
	Vector2i(2, 4): "memorial_cross",
	# E - logistics. The issue counter (#26) works beside the stores tent's
	# door; the kit frame goes back to drying kit.
	Vector2i(11, 4): "qm_counter",
	Vector2i(14, 4): "water_tank",
	Vector2i(12, 6): "ammo_box",
	Vector2i(13, 6): "jerry_cans",
	# W edge of the domestic quarter - the Crown's own water
	Vector2i(2, 6): "water_bowser",
	Vector2i(4, 6): "kit_frame",
	# SW - domestic. The awning is 256px of canopy on a 128px cell - two
	# tiles wide on a one-tile stand - so it keeps clear cells either side.
	Vector2i(4, 8): "awning",
	Vector2i(3, 10): "washing_line",
	Vector2i(5, 10): "field_stove",
	# S - parade: the duty roster, and the Accord's own board beside it (#23).
	Vector2i(7, 9): "notice_board",
	Vector2i(8, 9): "bounty_board",
	# SE
	Vector2i(14, 9): "cleaning_bench",
}

const GARRISON := {
	"size": Vector2i(16, 12),
	"map": [
		"WWWWWWWWWWWWWWWW",
		"W...j.j.....jj.W",
		"W..............W",
		"W..............W",
		"W.j........j..jW",
		"Wp.p...........W",
		"W.j.j.......jj.W",
		"W..............W",
		"W...j..........W",
		"W......jj.....jW",
		"W..j.j........pW",
		"WWWWWWWWWWWWWWWW",
	],
	"props": GARRISON_PROPS,
	"structures": [
		# The command billet and the squad billet anchor their quarters; the
		# stores tent fronts the logistics yard; the second tent holds the
		# surgeon's ground until his own art lands.
		{"kind": "hut_1", "anchor": Vector2i(1, 1), "size": Vector2i(2, 2)},
		{"kind": "hut_2", "anchor": Vector2i(1, 7), "size": Vector2i(2, 2)},
		{"kind": "stores_tent", "anchor": Vector2i(12, 4), "size": Vector2i(2, 2)},
		{"kind": "field_tent", "anchor": Vector2i(12, 8), "size": Vector2i(2, 2)},
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
	# The player wakes mid-yard, a short walk from every quarter.
	"player": Vector2i(7, 6),
	# The briefing table sits in the command quarter, flag behind it.
	"briefing": Vector2i(5, 2),
	# The stores spot is the stores tent's DOOR, not a lone crate in a field.
	"stores": Vector2i(11, 5),
	# The levy post works the parade ground. Only the garrison posts one.
	"recruit": Vector2i(10, 9),
	# The squad idles where people would: two by the billets, one on the
	# parade, one by the stores, two loose in the yard.
	"squad": [
		Vector2i(5, 4), Vector2i(8, 3), Vector2i(6, 7),
		Vector2i(9, 7), Vector2i(10, 8), Vector2i(8, 10),
	],
	# Map crates flanking the briefing table.
	"dressing": [Vector2i(4, 2), Vector2i(6, 2)],
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
