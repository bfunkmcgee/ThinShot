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
##   '.' open sand  '#' rock  'W' mud-brick wall  'j' scrap  'p' plant  '=' wire
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
	# N wall, command: the colours, then the signals mast at the HQ's east
	# gable - the two mission sources ten steps apart.
	Vector2i(6, 1): "flagpole",
	Vector2i(12, 1): "signals_mast",
	# NE - the range's backstop: a berm bank against the north wall, so a
	# round that misses leaves over empty desert. Targets in front of it,
	# firing points three rows south, the flag flying at the entry because
	# the range is live whenever the yard is.
	Vector2i(13, 1): "berm", Vector2i(14, 1): "berm_1",
	Vector2i(15, 1): "berm_2", Vector2i(16, 1): "berm",
	Vector2i(17, 1): "berm_1", Vector2i(18, 1): "berm_2",
	Vector2i(19, 1): "berm",
	Vector2i(14, 2): "target", Vector2i(16, 2): "target_1",
	Vector2i(18, 2): "target",
	Vector2i(12, 5): "range_flag",
	Vector2i(14, 5): "firing_point", Vector2i(16, 5): "firing_point",
	Vector2i(18, 5): "firing_point",
	# Command row: the paymaster beside the HQ. Scenery still - the ledger
	# stays at the memorial, deliberately.
	Vector2i(11, 2): "paymaster_desk",
	# Parade north edge, facing the HQ porch: the duty roster and the
	# Accord's board, with the levy post working the same row.
	Vector2i(7, 5): "notice_board",
	Vector2i(9, 5): "bounty_board",
	# W - billets and the domestic quarter.
	Vector2i(3, 2): "washing_line",
	Vector2i(4, 6): "kit_frame",
	Vector2i(7, 7): "water_bowser",
	Vector2i(6, 9): "field_stove",
	# E - the armory's yard: ammunition and cleaning at its east wall, the
	# issue counter at its west window.
	Vector2i(15, 6): "ammo_box",
	Vector2i(16, 6): "cleaning_bench",
	Vector2i(12, 7): "qm_counter",
	# SE - motor pool inside the gate, the tank where the trucks fill.
	Vector2i(19, 7): "water_tank",
	Vector2i(12, 8): "awning",
	# Beside the tank, at the fill point - and OFF the corridor: at (13,9)
	# they sealed the armory's south door into a pocket the validator caught.
	Vector2i(19, 8): "jerry_cans",
	# The tower watches the one gate. It is a tall prop on the FRONT row -
	# the known cost is that it can occlude a walker two rows behind it;
	# Battle's occlusion fade is the fix if it bothers.
	Vector2i(12, 10): "watchtower",
	# SW - the memorial: alone, in a planted row, beside the way out.
	Vector2i(3, 10): "memorial_cross",
}

const GARRISON := {
	"size": Vector2i(22, 12),
	"map": [
		"WWWWWWWWWWWWWWWWWWWWWW",
		"W.....j.....jjjjjjjj.W",
		"W..j.......j..j.j.j..W",
		"W....................W",
		"W....................W",
		"W......j.j..j.j.j.j..W",
		"W...j..........jj....W",
		"W......j....j......j.W",
		"W...........j..=...j.W",
		"W.....j.......=......W",
		"W.pjp.......j.=......W",
		"WWWWWWWWW..WWWWWWWWWWW",
	],
	"props": GARRISON_PROPS,
	# The two wall cells flanking the gateway carry the gate art: piers with
	# their steel leaves standing OPEN against the wall, so the gap reads as
	# a way through that somebody could close, which is what a gate is.
	"gate": {
		Vector2i(8, 11): "open_west",
		Vector2i(11, 11): "open_east",
	},
	"structures": [
		# The billet row holds the west wall; the five buildings of the
		# construction pass (GARRISON.md) hold their quarters. The gate is
		# the two open cells in the south wall - somewhere to stand, not
		# somewhere to leave; its art (#2) hangs on the flanking wall cells
		# when it lands.
		{"kind": "hut_1", "anchor": Vector2i(1, 1), "size": Vector2i(2, 2)},
		{"kind": "hut_2", "anchor": Vector2i(1, 4), "size": Vector2i(2, 2)},
		{"kind": "field_tent", "anchor": Vector2i(1, 7), "size": Vector2i(2, 2)},
		{"kind": "hq", "anchor": Vector2i(8, 1), "size": Vector2i(2, 2)},
		{"kind": "surgeon_tent", "anchor": Vector2i(4, 3), "size": Vector2i(2, 2)},
		{"kind": "canteen", "anchor": Vector2i(4, 8), "size": Vector2i(2, 2)},
		{"kind": "armory", "anchor": Vector2i(13, 6), "size": Vector2i(2, 2)},
		# The motor pool's one vehicle, parked between the armory yard and
		# the lockup, nose to the pen wire - in service, not a wreck.
		{"kind": "water_truck", "anchor": Vector2i(17, 7), "size": Vector2i(2, 2)},
		{"kind": "lockup", "anchor": Vector2i(17, 9), "size": Vector2i(2, 2)},
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
	# The player wakes mid-parade, the yard's crossroads.
	"player": Vector2i(9, 6),
	# The briefing happens standing up on the HQ porch - the map is pinned
	# to the porch wall - with the map crates flanking.
	"briefing": Vector2i(9, 3),
	# The stores spot is the armory's south door; the tent it used to be is
	# retired from the garrison.
	"stores": Vector2i(14, 8),
	# The levy works the boards' row on the parade edge: sign on where the
	# duty roster and the Accord's notices already are.
	"recruit": Vector2i(8, 5),
	# Two by the canteen and billets, one on the parade, one at the firing
	# line, one by the motor pool, one loose.
	"squad": [
		Vector2i(5, 5), Vector2i(10, 4), Vector2i(6, 8),
		Vector2i(17, 5), Vector2i(10, 9), Vector2i(3, 5),
	],
	"dressing": [Vector2i(8, 3), Vector2i(10, 3)],
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
			# '=' joined the legend with the detention pen: wire, exactly the
			# battle rule - stops movement, no cover, no LOS effect.
			ok = _check(".#Wjp=".contains(ch),
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
