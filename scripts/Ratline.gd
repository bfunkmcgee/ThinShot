class_name Ratline
## The ratline: the smuggling routes that feed the Thirst its fighters, and
## the garrison's interdiction missions against them.
##
## Every operation the squad flies out on is fought against men who were
## WALKED IN - across the border, through crossings the Accord does not watch
## because watching them is what the Accord has a squad for. At each garrison
## stay the field radio posts three of those crossings. Run one down and the
## men it would have carried never arrive; ignore it and they do, with
## friends. What the player does about the net moves the muster of the whole
## next operation: all three shut is a fifth fewer rifles on every map, all
## three ignored is 15% more.
##
## Everything in this file is arithmetic and data over plain values, with no
## Unit and no Node in any signature, for the same reason Bounty.gd is
## written that way: tools/test_ratline.gd can pin the whole of it without
## standing up a scene, and a generator you cannot test is a generator that
## ships broken maps. Enemy kinds are raw ordinals (3 well-hand, 4 runner,
## 6 conscript), the same discipline the morale tables use.
##
## LAYERING. This file may name Rules (nothing yet), Roll (for deterministic
## hashing) and Levels (for LEGAL_CHARS). Nothing that Rules or Game names
## may name THIS file - so Game holds ratline state as plain ints and arrays
## and Camp/Battle call in here to interpret them. Do not have Game import
## this.

# --- what an interdiction is --------------------------------------------------

## How many crossings the radio posts per garrison stay. Three is a choice:
## it makes the maximum swing reachable without grinding, and it means a
## player who runs one and skips two still feels the difference.
const OFFERS := 3

## The two shapes a crossing comes in. A column caught in the open, or the
## waystation that feeds the columns - run down the men, or burn what they
## cannot cross without.
const ARCH_CROSSING := "crossing"
const ARCH_WAYSTATION := "waystation"

const BOARD := Vector2i(16, 10)
const SPAWN_X := 1        # the detachment lands on the west rim, like a bounty party
const PROP_RATE := 0.14   # barer than a bounty board: this is open border country
const CACHES := 2         # the waystation's staged supplies
const CACHE_GAP := 3      # manhattan tiles between them, so one frag never solves the map
const CROSSING_MIN := 5   # escort column size (5..7)
const CROSSING_MAX := 7
const GUARDS_MIN := 3     # waystation guard (3..4)
const GUARDS_MAX := 4

## Remote crossings on the eastern border. Picked by hash per offer, so the
## same garrison stay always posts the same three.
const PLACES: Array[Dictionary] = [
	{"name": "the Dry Ford", "where": "where the wash narrows to a cart's width"},
	{"name": "the Salt Gap", "where": "a break in the pan wall the maps never carried"},
	{"name": "Broke-Tooth Pass", "where": "the one shaded route over the ridge line"},
	{"name": "the Old Survey Track", "where": "a graded road with nothing left at either end"},
	{"name": "Threadneedle Wash", "where": "deep enough to walk a column through unseen"},
	{"name": "the Night Steps", "where": "goat paths cut two hundred years before the border"},
]

# --- the muster ---------------------------------------------------------------

## What the net is worth. With S of M crossings run down the next operation
## musters at:
##
##   strength = 100 - round(20*S/M) + round(15*(M-S)/M),  clamped [80, 115]
##
## All three shut: 80. All three ignored: 115. There is no neutral outcome by
## design - the net is either worked or it is working, and a lost attempt
## counts as an ignored one, because the crossing ran either way.
const STRENGTH_BASE := 100
const CUT_MAX := 20     # all M run down: a fifth fewer rifles
const SWELL_MAX := 15   # all M ignored: the crossings ran all season
const STRENGTH_MIN := STRENGTH_BASE - CUT_MAX
const STRENGTH_MAX := STRENGTH_BASE + SWELL_MAX

## When the surplus walks on, and what walks. Turns 2-3, over the east rim -
## the border is east - and only the kinds a man can carry across a desert:
## a submachine gun or a worn-out revolver. Nobody smuggles a bolt rifle team.
const SURPLUS_TURNS: Array[int] = [2, 3]
const SURPLUS_KINDS: Array[int] = [4, 6]  # GOBLIN_SMG, GOBLIN_REVOLVER


static func strength(successes: int, offers_posted: int) -> int:
	if offers_posted <= 0:
		return STRENGTH_BASE
	var s := clampi(successes, 0, offers_posted)
	var ignored := offers_posted - s
	return clampi(STRENGTH_BASE
			- roundi(CUT_MAX * float(s) / offers_posted)
			+ roundi(SWELL_MAX * float(ignored) / offers_posted),
			STRENGTH_MIN, STRENGTH_MAX)


## How many of the eligible fighters never made the crossing. 0 at or above
## base strength; 9 eligible at 80 is 2 men short.
static func trim_count(base_total: int, muster: int) -> int:
	if muster >= STRENGTH_BASE:
		return 0
	return maxi(base_total - roundi(base_total * muster / 100.0), 0)


## WHICH spawn cells stay empty: distinct deterministic picks over the
## eligible list. The caller owns the list and its order (and therefore what
## is untouchable - bolts, prisoners and bystanders are simply never in it);
## this file owns only the draw, so a retried mission faces the same absences.
static func trim_cells(eligible: Array, muster: int, campaign_seed: int,
		level_index: int) -> Array:
	var pool := eligible.duplicate()
	var out: Array = []
	for i in trim_count(eligible.size(), muster):
		if pool.is_empty():
			break
		var idx := Roll.pick(campaign_seed, level_index, "ratline:trim:%d" % i,
				pool.size())
		out.append(pool.pop_at(idx))
	return out


## How many extra guns the ignored crossings delivered. 0 at or below base.
static func surplus_count(base_total: int, muster: int) -> int:
	if muster <= STRENGTH_BASE:
		return 0
	return maxi(roundi(base_total * muster / 100.0) - base_total, 0)


## The delivery schedule: {turn -> Array of kind ordinals}, spread over
## SURPLUS_TURNS. Empty at or below base strength.
static func surplus_schedule(base_total: int, muster: int, campaign_seed: int,
		level_index: int) -> Dictionary:
	var out := {}
	for i in surplus_count(base_total, muster):
		var turn: int = SURPLUS_TURNS[i % SURPLUS_TURNS.size()]
		var kind: int = SURPLUS_KINDS[Roll.pick(campaign_seed, level_index,
				"ratline:kind:%d" % i, SURPLUS_KINDS.size())]
		var due: Array = out.get(turn, [])
		due.append(kind)
		out[turn] = due
	return out


## The one sentence the camp modal and the battle briefing share, so the
## projection and the fact can never disagree.
static func strength_line(muster: int) -> String:
	if muster < STRENGTH_BASE:
		return "the Thirst musters at %d%% for the coming operation - the crossings are hurting." % muster
	if muster > STRENGTH_BASE:
		return "the Thirst musters at %d%% for the coming operation - the crossings ran unwatched." % muster
	return "the Thirst musters at full strength for the coming operation."


# --- the offers ---------------------------------------------------------------

## The three crossings posted for this garrison stay. Pure and re-derivable
## from (campaign_seed, operation), like everything else here; `done` is the
## list of ordinals already run down, stamped onto each offer as `settled`.
static func offers(campaign_seed: int, operation: int, done: Array = []) -> Array:
	var out: Array = []
	for ordinal in OFFERS:
		var offer := offer_for(campaign_seed, operation, ordinal)
		offer["settled"] = done.has(ordinal)
		out.append(offer)
	return out


static func offer_for(campaign_seed: int, operation: int, ordinal: int) -> Dictionary:
	var archetype := ARCH_CROSSING if Roll.pick(campaign_seed, operation,
			"ratline:arch:%d" % ordinal, 2) == 0 else ARCH_WAYSTATION
	var place: Dictionary = PLACES[Roll.pick(campaign_seed, operation,
			"ratline:place:%d:%d" % [operation, ordinal], PLACES.size())]
	return {
		"ordinal": ordinal,
		"operation": operation,
		"archetype": archetype,
		"place": str(place.name),
		"where": str(place.where),
		"title": ("A COLUMN ON THE MOVE" if archetype == ARCH_CROSSING
				else "A WAYSTATION STOCKED"),
		"floor": "desert",
	}


# --- the boards ---------------------------------------------------------------

## Build the board for an interdiction. Returns a level dictionary in exactly
## the shape Levels.LEVELS entries have, for the same reason Bounty.build
## does: Board.set_level and Battle read it through the same fields, and a
## second shape would be a second set of bugs. `attempt` is generate()'s
## retry knob - a layout that fails validation is regenerated with a fresh
## hash rather than patched.
static func build(offer: Dictionary, campaign_seed: int, attempt := 0) -> Dictionary:
	if str(offer.get("archetype", "")) == ARCH_WAYSTATION:
		return _build_waystation(offer, campaign_seed, attempt)
	return _build_crossing(offer, campaign_seed, attempt)


static func generate(offer: Dictionary, campaign_seed: int) -> Dictionary:
	for attempt in 6:
		var level := build(offer, campaign_seed, attempt)
		var problems := validate(level)
		if problems.is_empty():
			return level
		if attempt == 5:
			push_error("[Ratline] could not generate a valid board for %s: %s"
					% [str(offer.get("place", "")), ", ".join(problems)])
	return {}


static func _salt(offer: Dictionary, attempt: int) -> String:
	return "ratline:%d:%d:%d" % [int(offer.get("operation", 0)),
			int(offer.get("ordinal", 0)), attempt]


## THE CROSSING: an escort column caught strung out on the track, NE toward
## SW. Kill every fighter - the cargo scatters back over the border on its
## own. Kinds drawn per man from a travel-light pool: runners, conscripts,
## and the odd well-hand walking as a porter.
static func _build_crossing(offer: Dictionary, campaign_seed: int,
		attempt: int) -> Dictionary:
	var salt := _salt(offer, attempt)
	var grid := BOARD
	var rows: Array[String] = []
	for y in grid.y:
		rows.append(".".repeat(grid.x))

	var scout_spawns: Array[Vector2i] = []
	for i in 3:
		scout_spawns.append(Vector2i(SPAWN_X, 3 + i * 2))
	var taken := {}
	for cell: Vector2i in scout_spawns:
		taken[cell] = true

	# The column, strung along the diagonal track from the NE crossing toward
	# the SW settlements, two-to-three tiles apart so no single grenade or
	# burst solves the mission.
	var count := CROSSING_MIN + Roll.pick(campaign_seed, 0, salt + ":ncol",
			CROSSING_MAX - CROSSING_MIN + 1)
	var kind_pool := [4, 6, 6, 3]  # runner, two conscripts, a well-hand porter
	var goblin_spawns: Array[Vector2i] = []
	var smg_spawns: Array[Vector2i] = []
	var novice_spawns: Array[Vector2i] = []
	var used := {}
	for i in count:
		var t := float(i) / maxf(count - 1, 1.0)
		var around := Vector2i(roundi(lerpf(13.0, 6.0, t)), roundi(lerpf(2.0, 7.0, t)))
		var cell := _free_near(campaign_seed, i, salt + ":col", grid, around,
				used, taken)
		if cell.x < 0:
			continue
		taken[cell] = true
		match kind_pool[Roll.pick(campaign_seed, i, salt + ":kind", kind_pool.size())]:
			3:
				goblin_spawns.append(cell)
			4:
				smg_spawns.append(cell)
			_:
				novice_spawns.append(cell)

	_scatter_props(campaign_seed, salt, grid, rows, used, taken)

	return {
		"name": "THE CROSSING: %s" % str(offer.get("place", "")).to_upper(),
		"fiction": "%s, %s. The column is on it tonight." % [
				str(offer.get("place", "")).capitalize(), str(offer.get("where", ""))],
		"briefing": briefing_for(offer),
		"orders": "RUN DOWN THE COLUMN",
		"debrief": "The column is finished, and the crossing knows it.\n\nThe men it carried are counted; the men it would have carried next month are not coming. Word travels the ratline faster than cargo does - a route that eats a column stops being a route.\n\nThe detachment walks home. One crossing fewer on the net.",
		"size": grid,
		"map": rows,
		"scout_spawns": scout_spawns,
		"goblin_spawns": goblin_spawns,
		"smg_spawns": smg_spawns,
		"novice_spawns": novice_spawns,
		"structures": [] as Array,
		"objectives": [{"kind": "eliminate", "label": "RUN DOWN THE COLUMN"}],
		"floor": str(offer.get("floor", "desert")),
		"zone_seed": 700 + int(offer.get("operation", 0)) * 8 + int(offer.get("ordinal", 0)),
		"shade_seed": 800 + int(offer.get("operation", 0)) * 8 + int(offer.get("ordinal", 0)),
		"zone_thresholds": [-0.25, 0.15],
		"prop_seed": 900 + int(offer.get("operation", 0)) * 8 + int(offer.get("ordinal", 0)),
		# The marker Battle and the results flow read; parallel to "bounty".
		"ratline": {"ordinal": int(offer.get("ordinal", 0)), "offer": offer},
	}


## THE WAYSTATION: the stock a crossing cannot run without - water and food
## staged at the midpoint - under a light guard. Burn both caches and walk
## away; the guard does not have to die for the route to.
static func _build_waystation(offer: Dictionary, campaign_seed: int,
		attempt: int) -> Dictionary:
	var salt := _salt(offer, attempt)
	var grid := BOARD
	var rows: Array[String] = []
	for y in grid.y:
		rows.append(".".repeat(grid.x))

	var scout_spawns: Array[Vector2i] = []
	for i in 3:
		scout_spawns.append(Vector2i(SPAWN_X, 3 + i * 2))
	var taken := {}
	for cell: Vector2i in scout_spawns:
		taken[cell] = true

	# One shelter for the men who mind the stock.
	var anchor := Vector2i(9 + Roll.pick(campaign_seed, 0, salt + ":sx", 4),
			1 + Roll.pick(campaign_seed, 0, salt + ":sy", grid.y - 4))
	var used := {}
	var structures: Array = []
	if anchor.x + 2 <= grid.x - 1 and anchor.y + 2 <= grid.y - 1:
		for dy in 2:
			for dx in 2:
				used[anchor + Vector2i(dx, dy)] = true
		structures.append({"kind": "tent", "anchor": anchor, "size": Vector2i(2, 2)})

	# The two caches, far apart in the eastern half - CACHE_GAP is what stops
	# one frag or one push from being the whole mission.
	var cache_cells: Array[Vector2i] = []
	var corners := [Vector2i(11, 2), Vector2i(12, 7)]
	for i in CACHES:
		var cell := _free_near(campaign_seed, i, salt + ":cache", grid,
				corners[i % corners.size()], used, taken)
		if cell.x < 0:
			continue
		var clear := true
		for other: Vector2i in cache_cells:
			if absi(cell.x - other.x) + absi(cell.y - other.y) < CACHE_GAP:
				clear = false
		if not clear:
			continue
		cache_cells.append(cell)
		taken[cell] = true

	# The guard, posted near the stock: well-hands who live here, plus what
	# the route can spare.
	var guard_pool := [3, 4, 6]
	var guards := GUARDS_MIN + Roll.pick(campaign_seed, 0, salt + ":nguard",
			GUARDS_MAX - GUARDS_MIN + 1)
	var goblin_spawns: Array[Vector2i] = []
	var smg_spawns: Array[Vector2i] = []
	var novice_spawns: Array[Vector2i] = []
	for i in guards:
		var near: Vector2i = cache_cells[i % maxi(cache_cells.size(), 1)] \
				if not cache_cells.is_empty() else Vector2i(11, grid.y / 2)
		var cell := _free_near(campaign_seed, i, salt + ":guard", grid, near,
				used, taken)
		if cell.x < 0:
			continue
		taken[cell] = true
		match guard_pool[Roll.pick(campaign_seed, i, salt + ":gkind",
				guard_pool.size())]:
			3:
				goblin_spawns.append(cell)
			4:
				smg_spawns.append(cell)
			_:
				novice_spawns.append(cell)

	_scatter_props(campaign_seed, salt, grid, rows, used, taken)

	return {
		"name": "THE WAYSTATION: %s" % str(offer.get("place", "")).to_upper(),
		"fiction": "%s, %s. The stock for a season of crossings is staged here." % [
				str(offer.get("place", "")).capitalize(), str(offer.get("where", ""))],
		"briefing": briefing_for(offer),
		"orders": "BURN THE CACHES",
		"debrief": "Both caches burned where they were stacked.\n\nA crossing is not a line on a map, it is water every twelve miles - and now there is none here for a season. The columns will try somewhere else, or they will not try.\n\nThe detachment walks home. One crossing fewer on the net.",
		"size": grid,
		"map": rows,
		"scout_spawns": scout_spawns,
		"goblin_spawns": goblin_spawns,
		"smg_spawns": smg_spawns,
		"novice_spawns": novice_spawns,
		"structures": structures,
		"objectives": [{
			"kind": "destroy",
			"label": "BURN THE CACHES",
			"prop": "crates",
			"cells": cache_cells,
		}],
		"floor": str(offer.get("floor", "desert")),
		"zone_seed": 700 + int(offer.get("operation", 0)) * 8 + int(offer.get("ordinal", 0)),
		"shade_seed": 800 + int(offer.get("operation", 0)) * 8 + int(offer.get("ordinal", 0)),
		"zone_thresholds": [-0.25, 0.15],
		"prop_seed": 900 + int(offer.get("operation", 0)) * 8 + int(offer.get("ordinal", 0)),
		"ratline": {"ordinal": int(offer.get("ordinal", 0)), "offer": offer},
	}


## The mission text, kept deliberately shorter than a bounty's: the radio
## does not editorialize. tools/test_ratline.gd holds every generated
## briefing under 700 characters, which is the check behind the convention.
static func briefing_for(offer: Dictionary) -> String:
	var place := str(offer.get("place", ""))
	var where := str(offer.get("where", ""))
	if str(offer.get("archetype", "")) == ARCH_WAYSTATION:
		return ("Sillae's set has been reading the smugglers' band all week, and the traffic agrees: the stock for a season of crossings is staged at %s - %s.\n\n"
				+ "Water and food, cached and guarded. A column cannot cross without it, which makes the caches the mission: burn both and walk away. The guard does not have to die for the route to.\n\n"
				+ "A detachment goes. Whoever leads it sits out the next mission.") % [place, where]
	return ("A column is moving tonight through %s - %s. Fighters for the next operation, walked in the way they always are: strung out, travelling light, counting on nobody watching.\n\n"
			+ "Somebody is watching. Run the column down - every man of it. The cargo that scatters back over the border tonight is cargo the squad never meets on a wash.\n\n"
			+ "A detachment goes. Whoever leads it sits out the next mission.") % [place, where]


# --- shared layout helpers ----------------------------------------------------

## A walkable cell near `around` that nothing has claimed, or (-1, -1).
## Verbatim clone of Bounty._free_near, x clamped clear of the approach lane.
static func _free_near(campaign_seed: int, n: int, salt: String, grid: Vector2i,
		around: Vector2i, blocked: Dictionary, taken: Dictionary) -> Vector2i:
	for tries in 24:
		var cell := Vector2i(
			clampi(around.x - 3 + Roll.pick(campaign_seed, n * 40 + tries,
					salt + ":x", 7), SPAWN_X + 2, grid.x - 1),
			clampi(around.y - 3 + Roll.pick(campaign_seed, n * 40 + tries,
					salt + ":y", 7), 0, grid.y - 1))
		if blocked.has(cell) or taken.has(cell):
			continue
		return cell
	return Vector2i(-1, -1)


## Scenery last, so it can be told what not to bury. The glyph pool carries
## no 'c' on purpose - the waystation has a destroy objective, and crates you
## can only hide behind must never dress a map that asks you to burn crates.
static func _scatter_props(campaign_seed: int, salt: String, grid: Vector2i,
		rows: Array[String], used: Dictionary, taken: Dictionary) -> void:
	var glyphs := ["#", "j", "p", "j", "p"]
	for y in grid.y:
		var row := rows[y]
		for x in grid.x:
			var cell := Vector2i(x, y)
			if used.has(cell) or taken.has(cell):
				continue
			if x <= SPAWN_X + 1:
				continue  # the approach lane stays clear
			if Roll.chance(campaign_seed, x * 31 + y, salt + ":prop",
					int(PROP_RATE * 100.0)):
				var g: String = glyphs[Roll.pick(campaign_seed, x * 17 + y,
						salt + ":glyph", glyphs.size())]
				row = row.substr(0, x) + g + row.substr(x + 1)
		rows[y] = row


# --- validation ---------------------------------------------------------------

## Everything Battle and Board assume about a level, checked before either
## sees it - the whole reason a generated mission is safe to ship. Returns a
## list of problems, empty when the board is sound.
static func validate(level: Dictionary) -> Array:
	var problems: Array = []
	if level.is_empty():
		return ["empty level"]
	var grid: Vector2i = level.get("size", Vector2i.ZERO)
	var rows: Array = level.get("map", [])
	if rows.size() != grid.y:
		problems.append("map has %d rows, wants %d" % [rows.size(), grid.y])
		return problems
	for row: String in rows:
		if row.length() != grid.x:
			problems.append("row '%s' is %d wide, wants %d"
					% [row, row.length(), grid.x])
			return problems
		for ch in row:
			if not Levels.LEGAL_CHARS.contains(ch):
				problems.append("illegal char '%s'" % ch)
				return problems
			if ch == "c":
				problems.append("'c' crates must never dress a ratline map")
				return problems
	if not level.has("ratline"):
		problems.append("no ratline marker")
		return problems
	var blocked := {}
	for s: Dictionary in level.get("structures", []):
		var anchor: Vector2i = s.get("anchor", Vector2i.ZERO)
		var size: Vector2i = s.get("size", Vector2i.ONE)
		for dy in size.y:
			for dx in size.x:
				var cell: Vector2i = anchor + Vector2i(dx, dy)
				if cell.x < 0 or cell.x >= grid.x or cell.y < 0 or cell.y >= grid.y:
					problems.append("structure out of bounds at %s" % cell)
					return problems
				if blocked.has(cell):
					problems.append("structures overlap at %s" % cell)
					return problems
				blocked[cell] = true
	var walk := func(cell: Vector2i) -> bool:
		if cell.x < 0 or cell.x >= grid.x or cell.y < 0 or cell.y >= grid.y:
			return false
		if blocked.has(cell):
			return false
		var ch: String = str(rows[cell.y])[cell.x]
		return ch == "." or ch == "p" or ch == "t"
	var spawns: Array = level.get("scout_spawns", [])
	if spawns.size() < 3:
		problems.append("a detachment is three, got %d" % spawns.size())
		return problems
	for cell: Vector2i in spawns:
		if not walk.call(cell):
			problems.append("spawn %s is not walkable" % cell)
	if not problems.is_empty():
		return problems
	# Reachability from the rim the detachment lands on: every enemy and
	# every objective cell, or the mission cannot be finished.
	var seen := {spawns[0]: true}
	var frontier: Array[Vector2i] = [spawns[0]]
	while not frontier.is_empty():
		var cur: Vector2i = frontier.pop_front()
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nxt: Vector2i = cur + step
			if seen.has(nxt) or not walk.call(nxt):
				continue
			seen[nxt] = true
			frontier.push_back(nxt)
	var spawn_set := {}
	for cell: Vector2i in spawns:
		spawn_set[cell] = true
		if not seen.has(cell):
			problems.append("spawn %s is cut off from the rest of the party" % cell)
	var enemies: Array = level.get("goblin_spawns", []) \
			+ level.get("smg_spawns", []) + level.get("smg_alt_spawns", []) \
			+ level.get("novice_spawns", []) + level.get("bolt_spawns", [])
	if enemies.is_empty():
		problems.append("nobody is holding the crossing")
	for cell: Vector2i in enemies:
		if not walk.call(cell):
			problems.append("enemy at %s is not walkable" % cell)
		elif not seen.has(cell):
			problems.append("enemy at %s cannot be reached" % cell)
		if spawn_set.has(cell):
			problems.append("enemy at %s stands on a spawn" % cell)
	for obj: Dictionary in level.get("objectives", []):
		if str(obj.get("kind", "")) != "destroy":
			continue
		var cells: Array = obj.get("cells", [])
		if cells.size() < CACHES:
			problems.append("only %d cache(s) staged" % cells.size())
		for i in cells.size():
			var cell: Vector2i = cells[i]
			if not walk.call(cell):
				problems.append("cache at %s is not on clean ground" % cell)
			elif not seen.has(cell):
				problems.append("cache at %s cannot be reached" % cell)
			if spawn_set.has(cell) or enemies.has(cell):
				problems.append("cache at %s is under somebody's feet" % cell)
			for j in range(i + 1, cells.size()):
				var other: Vector2i = cells[j]
				if absi(cell.x - other.x) + absi(cell.y - other.y) < CACHE_GAP:
					problems.append("caches at %s and %s solve as one push"
							% [cell, other])
	return problems
