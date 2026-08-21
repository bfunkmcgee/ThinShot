class_name Bounty

## Bounties: the campaign's procedurally generated missions.
##
## A bounty is one named soldier, two riflemen lent to them, and a man the
## squad has already let get away. The board is generated rather than authored -
## a remote place the Thirst lives, rumoured to be where he is hiding - and the
## people there are not fighting anybody. You walk up to them and ask.
##
## Everything in this file is arithmetic and data over plain values, with no
## Unit and no Node in any signature, for the same reason Rules.gd is written
## that way: tools/test_bounty.gd can pin the whole of it without standing up a
## scene, and a generator you cannot test is a generator that ships broken maps.
##
## LAYERING. This file may name Rules (for the morale and survival numbers a
## negotiation reads) and Roll (for deterministic hashing). Nothing that Rules
## or Game names may name THIS file, or the cycle the project already documents
## in Rules.gd closes again - so Game holds bounty state as plain dictionaries
## and Camp/Battle call in here to interpret them. Do not have Game import this.

# --- what a bounty is ---------------------------------------------------------

## How many bounties the garrison has posted at once. Three is a choice; one is
## an errand and six is a menu.
const OFFERS := 3

## A bounty is only worth posting on somebody the squad has actually lost. The
## adversary pool is exactly that list, so eligibility is "is he still out
## there", which every record already answers.
const ELIGIBLE_STATES := ["escaped", "injured"]

## Remote places the Thirst lives. Picked by hash per target, so the same man is
## always rumoured to be in the same place until you go and look.
const PLACES: Array[Dictionary] = [
	{"name": "THE SUMP", "floor": "desert",
		"where": "a seep in the rock that three families share"},
	{"name": "KHERRA WELL", "floor": "desert",
		"where": "a walled well on the old survey line"},
	{"name": "THE TAILINGS", "floor": "ash",
		"where": "a burnt-over camp nobody has rebuilt"},
	{"name": "SALT REACH", "floor": "salt",
		"where": "a handful of shelters at the edge of the pan"},
	{"name": "THE LOW CROSSING", "floor": "desert",
		"where": "a dry ford where the tracks still meet"},
	{"name": "OSSA FLATS", "floor": "salt",
		"where": "a stock pen and two huts, a long way from anywhere"},
]

# --- the generated board ------------------------------------------------------

const BOARD := Vector2i(16, 10)
## Where the hunting party comes on. The west rim, always: the board is built
## around the approach and a randomised entry would make half the generations
## indefensible rather than interesting.
const SPAWN_X := 1
## How much of the open ground gets a prop on it. Low, and deliberately so - a
## bounty board is a place people live, not a battlefield, and the map has to
## stay walkable enough that questioning four people is not an expedition.
const PROP_RATE := 0.16
## Residents to question. Three or four: enough that finding the talkative one
## is a decision, few enough that asking everybody is not a chore.
const RESIDENTS_MIN := 3
const RESIDENTS_MAX := 4
## How far east the settlement sits, as a fraction of the board.
const SETTLEMENT_X := 9


## The bounties on offer to a campaign, newest history first.
##
## Deterministic in exactly the way Game.adversaries_for is, and for the same
## reason: the board a player is looking at must not change because they walked
## away from the notice board and came back.
static func offers(campaign_seed: int, adversaries: Array,
		completed_ids: Array = []) -> Array:
	var out: Array = []
	for rec: Dictionary in adversaries:
		if not ELIGIBLE_STATES.has(str(rec.get("state", ""))):
			continue
		if completed_ids.has(int(rec.get("id", 0))):
			continue
		if int(rec.get("kind", -1)) < 0:
			continue
		out.append(rec)
	# The most-storied first: the man you have let go three times is the one
	# worth sending somebody after.
	out.sort_custom(func(a, b):
		var sa := int(a.get("survivals", 0))
		var sb := int(b.get("survivals", 0))
		if sa != sb:
			return sa > sb
		return int(a.get("id", 0)) < int(b.get("id", 0)))
	var posted: Array = []
	for rec: Dictionary in out.slice(0, OFFERS):
		posted.append(offer_for(campaign_seed, rec))
	return posted


## One posted bounty: who, where, and what the garrison is calling it.
static func offer_for(campaign_seed: int, rec: Dictionary) -> Dictionary:
	var id := int(rec.get("id", 0))
	var place: Dictionary = PLACES[Roll.pick(campaign_seed, 0, "bplace:%d" % id,
			PLACES.size())]
	return {
		"target_id": id,
		"name": str(rec.get("name", "")),
		"settlement": str(rec.get("settlement", "")),
		"kind": int(rec.get("kind", 3)),
		"survivals": int(rec.get("survivals", 0)),
		"injuries": int(rec.get("injuries", 0)),
		"grievance": str(rec.get("grievance", "")),
		"age": int(rec.get("age", 0)),
		"place": str(place.get("name", "")),
		"where": str(place.get("where", "")),
		"floor": str(place.get("floor", "desert")),
	}


# --- generation ---------------------------------------------------------------

## Build the board for a bounty. Returns a level dictionary in exactly the shape
## Levels.LEVELS entries have, because Board.set_level and Battle read it
## through the same fields and a second shape would be a second set of bugs.
##
## `attempt` exists for the retry in generate(): a layout that fails its own
## validation is regenerated with a different hash rather than patched, which is
## the cheaper and far more predictable of the two fixes.
static func build(offer: Dictionary, campaign_seed: int, attempt := 0) -> Dictionary:
	var id := int(offer.get("target_id", 0))
	var salt := "bounty:%d:%d" % [id, attempt]
	var grid := BOARD
	var rows: Array[String] = []
	for y in grid.y:
		rows.append(".".repeat(grid.x))

	# The settlement: two or three shelters in the east, on clean ground.
	var structures: Array = []
	var kinds := ["hut_1", "hut_2", "tent"]
	var want_structures := 2 + Roll.pick(campaign_seed, 0, salt + ":nstruct", 2)
	var used := {}
	for i in want_structures:
		var anchor := Vector2i(
			SETTLEMENT_X + Roll.pick(campaign_seed, i, salt + ":sx", 4),
			1 + Roll.pick(campaign_seed, i, salt + ":sy", grid.y - 4))
		if anchor.x + 2 > grid.x - 1 or anchor.y + 2 > grid.y - 1:
			continue
		var clash := false
		for dy in 3:
			for dx in 3:
				if used.has(anchor + Vector2i(dx - 1, dy - 1)):
					clash = true
		if clash:
			continue
		for dy in 2:
			for dx in 2:
				used[anchor + Vector2i(dx, dy)] = true
		structures.append({"kind": kinds[i % kinds.size()], "anchor": anchor,
				"size": Vector2i(2, 2)})

	# Where the hunting party comes on, and where the residents are standing.
	var scout_spawns: Array[Vector2i] = []
	for i in 3:
		scout_spawns.append(Vector2i(SPAWN_X, 3 + i * 2))
	var residents: Array[Vector2i] = []
	var want_residents := RESIDENTS_MIN + Roll.pick(campaign_seed, 0,
			salt + ":nres", RESIDENTS_MAX - RESIDENTS_MIN + 1)
	var taken := {}
	for cell: Vector2i in scout_spawns:
		taken[cell] = true
	for i in want_residents:
		var cell := _free_near(campaign_seed, i, salt + ":res", grid,
				Vector2i(SETTLEMENT_X, grid.y / 2), used, taken)
		if cell.x >= 0:
			residents.append(cell)
			taken[cell] = true

	# And where the man himself is, once somebody talks. Far side, clear of the
	# shelters, with room around him for a warband to come up beside him.
	var hide := _free_near(campaign_seed, 0, salt + ":hide", grid,
			Vector2i(grid.x - 2, grid.y / 2), used, taken)
	if hide.x < 0:
		hide = Vector2i(grid.x - 2, grid.y / 2)
	taken[hide] = true

	# Scenery last, so it can be told what not to bury.
	var glyphs := ["#", "j", "p", "j", "p"]
	for y in grid.y:
		var row := rows[y]
		for x in grid.x:
			var cell := Vector2i(x, y)
			if used.has(cell) or taken.has(cell):
				continue
			# The approach lane stays clear: a party that cannot walk in is not
			# a hard mission, it is a broken one.
			if x <= SPAWN_X + 1:
				continue
			if Roll.chance(campaign_seed, x * 31 + y, salt + ":prop",
					int(PROP_RATE * 100.0)):
				var g: String = glyphs[Roll.pick(campaign_seed, x * 17 + y,
						salt + ":glyph", glyphs.size())]
				row = row.substr(0, x) + g + row.substr(x + 1)
		rows[y] = row

	var floor_name := str(offer.get("floor", "desert"))
	return {
		"name": "BOUNTY: %s" % str(offer.get("name", "")).to_upper(),
		"fiction": "%s, %s. He is said to be here." % [
				str(offer.get("place", "")), str(offer.get("where", ""))],
		"briefing": _briefing_for(offer),
		"orders": "FIND %s" % str(offer.get("name", "")).to_upper(),
		"debrief": "",  # written after the fact, from what was actually done
		"size": grid,
		"map": rows,
		"scout_spawns": scout_spawns,
		# Nobody is fighting when the party walks on. Every goblin on this board
		# is a resident until the man himself is found, and residents are not
		# spawned through the enemy lists - see Battle._spawn_bounty_residents.
		"goblin_spawns": [] as Array[Vector2i],
		"structures": structures,
		"objectives": [{"kind": "bounty", "label": "FIND %s"
				% str(offer.get("name", "")).to_upper()}],
		"floor": floor_name,
		"zone_seed": 400 + id,
		"shade_seed": 500 + id,
		"zone_thresholds": [-0.25, 0.15],
		"prop_seed": 600 + id,
		# Bounty-only fields. Battle reads these; nothing else in the game has
		# them, and Levels never will - a shipped mission has authored answers
		# to all three.
		"bounty": {
			"target_id": id,
			"residents": residents,
			"hide": hide,
			"offer": offer,
		},
	}


## Generate and check, retrying with a fresh layout rather than repairing one.
## Returns {} only if every attempt failed, which is a bug in this file - the
## caller should treat it as one rather than shipping the player a blank map.
static func generate(offer: Dictionary, campaign_seed: int) -> Dictionary:
	for attempt in 6:
		var level := build(offer, campaign_seed, attempt)
		var problems := validate(level)
		if problems.is_empty():
			return level
		if attempt == 5:
			push_error("[Bounty] could not generate a valid board for %s: %s"
					% [str(offer.get("name", "")), ", ".join(problems)])
	return {}


## Everything Battle and Board assume about a level, checked before either sees
## it. Returns a list of problems, empty when the board is sound.
##
## This is the whole reason a generated mission is safe to ship: an authored
## level is validated once by a human and then forever by Levels.validate_all,
## and a generated one gets neither unless it asks for it here.
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
		problems.append("a bounty party is three, got %d" % spawns.size())
		return problems
	for cell: Vector2i in spawns:
		if not walk.call(cell):
			problems.append("spawn %s is not walkable" % cell)
	if not problems.is_empty():
		return problems
	# Reachability, which is the check that actually matters: every resident and
	# the place the man is hiding have to be walkable to from the rim the party
	# lands on, or the mission cannot be finished.
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
	var bounty: Dictionary = level.get("bounty", {})
	var residents: Array = bounty.get("residents", [])
	if residents.size() < RESIDENTS_MIN:
		problems.append("only %d residents" % residents.size())
	for cell: Vector2i in residents:
		if not seen.has(cell):
			problems.append("resident at %s cannot be reached" % cell)
	var hide: Vector2i = bounty.get("hide", Vector2i(-1, -1))
	if not seen.has(hide):
		problems.append("the hide at %s cannot be reached" % hide)
	for cell: Vector2i in spawns:
		if not seen.has(cell):
			problems.append("spawn %s is cut off from the rest of the party" % cell)
	return problems


## A walkable cell near `around` that nothing has claimed, or (-1, -1).
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


static func _briefing_for(offer: Dictionary) -> String:
	var name := str(offer.get("name", ""))
	var survivals := int(offer.get("survivals", 0))
	var times := "once"
	if survivals == 2:
		times = "twice"
	elif survivals > 2:
		times = "%d times" % survivals
	return ("%s of %s has walked away from this squad %s.\n\n"
			+ "The Accord has posted him. He is rumoured to be at %s - %s - and "
			+ "the people there are not fighting anybody: they draw water, they "
			+ "keep stock, and they know where he sleeps.\n\n"
			+ "Take two riflemen. Ask them.\n\n"
			+ "What you do when you find him is yours to decide, and the Accord "
			+ "would rather have him talking than dead.") % [
			name, str(offer.get("settlement", "")), times,
			str(offer.get("place", "")), str(offer.get("where", ""))]


# --- questioning and negotiation ----------------------------------------------
#
# Three rolls, all of them the same shape: a soldier's stat against a number
# that says how hard this person is to move. Written as percentages because
# that is what the shooting already speaks, and a player who has learnt to read
# a 65% to hit should not have to learn a second scale to read a 65% to be
# believed.

## Nobody is impossible and nobody is certain. The same clamp the to-hit uses.
const CHANCE_MIN := 5
const CHANCE_MAX := 95

## What a question is worth before anybody's stats are counted.
const QUESTION_BASE := 40
const QUESTION_PER_GUILE := 15
## Each refusal makes the next person warier. The settlement talks to itself.
const QUESTION_PER_REFUSAL := 12

## Demanding surrender.
const SURRENDER_BASE := 25
const SURRENDER_PER_PRESENCE := 12
## Every time he has got away is a reason to think he can do it again.
const SURRENDER_PER_SURVIVAL := 8
## Men at his back.
const SURRENDER_WARBAND := 15
## Being already hurt when the offer is made.
const SURRENDER_WOUNDED := 20
## His settlement's opinion of the squad, one point per five from neutral -
## +-10 across the full range. The same reputation that decides what a broken
## fighter does mid-battle (Rules.surrender_guns_needed) leans on the offer
## made to a cornered one: a man surrenders to soldiers his town says keep
## prisoners alive, and not to ones it says do not.
const SURRENDER_STANDING_DIV := 5

## Turning him. Harder than a surrender in every case, which is the point: it
## is the best outcome and it should be the one that needs a specialist.
const INFORMANT_BASE := 10
const INFORMANT_PER_GUILE := 12
## Presence helps a little - he has to believe you can protect him - but this
## is guile's roll.
const INFORMANT_PER_PRESENCE := 4
const INFORMANT_PER_SURVIVAL := 6
const INFORMANT_WARBAND := 20
## A man with a grievance against the Thirst rather than against the Crown is
## the one who turns. Read off the record the campaign already keeps.
const INFORMANT_GRIEVANCE := 15


static func _clamped(value: int) -> int:
	return clampi(value, CHANCE_MIN, CHANCE_MAX)


## Whether this resident tells you where he is.
static func question_chance(guile: int, refusals: int) -> int:
	return _clamped(QUESTION_BASE + QUESTION_PER_GUILE * maxi(guile, 0)
			- QUESTION_PER_REFUSAL * maxi(refusals, 0))


## Whether he puts his weapon down when asked.
static func surrender_chance(presence: int, survivals: int, warband_up: bool,
		wounded: bool, standing := Rules.STANDING_START) -> int:
	var pct := SURRENDER_BASE + SURRENDER_PER_PRESENCE * maxi(presence, 0)
	pct -= SURRENDER_PER_SURVIVAL * maxi(survivals, 0)
	if warband_up:
		pct -= SURRENDER_WARBAND
	if wounded:
		pct += SURRENDER_WOUNDED
	pct += (standing - Rules.STANDING_START) / SURRENDER_STANDING_DIV
	return _clamped(pct)


## Whether he takes the other offer.
static func informant_chance(guile: int, presence: int, survivals: int,
		warband_up: bool, holds_a_grievance: bool) -> int:
	var pct := INFORMANT_BASE + INFORMANT_PER_GUILE * maxi(guile, 0)
	pct += INFORMANT_PER_PRESENCE * maxi(presence, 0)
	pct -= INFORMANT_PER_SURVIVAL * maxi(survivals, 0)
	if warband_up:
		pct -= INFORMANT_WARBAND
	if holds_a_grievance:
		pct += INFORMANT_GRIEVANCE
	return _clamped(pct)


# --- what it is worth ---------------------------------------------------------

## Stat growth, per outcome. Deliberately narrow: a stat that goes up on every
## bounty stops meaning anything by the fourth one, and these are meant to make
## a particular soldier the person you send.
const PRESENCE_FOR_SURRENDER := 1
const GUILE_FOR_INFORMANT := 1
## Talking your way through the settlement without firing on anybody who lives
## there. The quiet run, and the only other thing that teaches guile.
const GUILE_FOR_CLEAN_RUN := 1

## What the district and the theater make of each ending. Standing is per
## settlement and Strain is theater-wide, the same division the conduct table
## uses - see Rules.Conduct.
const OUTCOME_STANDING := {
	"killed": 0,
	"surrendered": 6,
	"informant": 10,
}
const OUTCOME_STRAIN := {
	"killed": 0,
	"surrendered": -4,
	"informant": -8,
}


static func standing_for(outcome: String) -> int:
	return int(OUTCOME_STANDING.get(outcome, 0))


static func strain_for(outcome: String) -> int:
	return int(OUTCOME_STRAIN.get(outcome, 0))


## How many enemy positions an informant gives away at the start of a later
## mission. Flat per informant and capped by the caller against how many there
## actually are - three is enough to change an approach and not enough to hand
## the player the map.
const INFORMANT_MARKS := 3
