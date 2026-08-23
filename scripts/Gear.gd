class_name Gear

## Equipment: the quartermaster's whole catalog, and the arithmetic over it.
##
## A soldier carries at most one item per slot - weapon fitting, armor, kit.
## Items are stat modifiers only, applied by Unit.apply_progression after the
## level bonuses and before the accuracy cap. Nothing here touches damage:
## the even-damage cover-halving invariant (Rules.gd) survives this system
## because ALLOWED_MODS says it must, and test_gear.gd pins that forever.
##
## LAYERING. This file may name Roll (for deterministic drop hashing) and
## nothing else - Bounty.gd's rule, for Bounty.gd's reason. Game holds the
## armory and each soldier's gear as plain strings and calls in here to
## interpret them. Do not have Game import this.

## The three slots, in the order every screen lists them.
const SLOTS: Array[String] = ["weapon", "armor", "kit"]

## Every stat an item is allowed to touch. Deliberately no "damage": damage
## stays even so cover halving stays exact (see Rules.gd). arc_half is
## set-with-max, not additive - a sentinel's widened arc never narrows and
## never stacks past itself.
const ALLOWED_MODS: Array[String] = [
	"accuracy", "max_hp", "move_range", "attack_range", "mag_size", "arc_half",
]

## The soldier level each tier unlocks at (highest LIVING soldier's level, so
## a dead veteran's ghost does not keep the good rack open).
const TIER_LEVEL := {1: 1, 2: 10, 3: 25}

## Chance a won side mission shakes an item loose. Deterministic per target
## via Roll, and unfarmable: the target leaves its pool on the banked win.
const DROP_PERCENT := 25

## The catalog. Two items per slot per tier - a cheap one and a dear one -
## so the rack always offers a real choice and never a scroll. Blurbs stay
## under 48 characters: they share a two-button modal with the price line.
const ITEMS := {
	# --- weapon fittings ---
	"oiled_sling": {"name": "OILED SLING", "slot": "weapon", "tier": 1,
		"price": 40, "blurb": "a steadier carry. nothing fancy",
		"mods": {"accuracy": 3}},
	"long_barrel": {"name": "LONG BARREL", "slot": "weapon", "tier": 1,
		"price": 50, "blurb": "reaches one square further",
		"mods": {"attack_range": 1}},
	"glass_sight": {"name": "GLASS SIGHT", "slot": "weapon", "tier": 2,
		"price": 110, "blurb": "ground glass. the shot goes where you look",
		"mods": {"accuracy": 6}},
	"drum_feed": {"name": "DRUM FEED", "slot": "weapon", "tier": 2,
		"price": 100, "blurb": "three more in the gun before the swap",
		"mods": {"mag_size": 3}},
	"match_fittings": {"name": "MATCH FITTINGS", "slot": "weapon", "tier": 3,
		"price": 240, "blurb": "armory work. further, and truer",
		"mods": {"accuracy": 8, "attack_range": 1}},
	"gunsmiths_rebuild": {"name": "GUNSMITH'S REBUILD", "slot": "weapon",
		"tier": 3, "price": 220, "blurb": "the whole action, done right",
		"mods": {"accuracy": 4, "mag_size": 4}},
	# --- armor ---
	"padded_jacket": {"name": "PADDED JACKET", "slot": "armor", "tier": 1,
		"price": 40, "blurb": "quilted cotton. better than a shirt",
		"mods": {"max_hp": 1}},
	"scrap_vest": {"name": "SCRAP VEST", "slot": "armor", "tier": 1,
		"price": 60, "blurb": "tin and wire over the heart",
		"mods": {"max_hp": 2}},
	"wire_weave": {"name": "WIRE WEAVE", "slot": "armor", "tier": 2,
		"price": 120, "blurb": "turns a blade, slows a ball",
		"mods": {"max_hp": 3}},
	"boiler_plate": {"name": "BOILER PLATE", "slot": "armor", "tier": 2,
		"price": 140, "blurb": "cut from a dead engine. heavy, honest",
		"mods": {"max_hp": 4}},
	"accord_cuirass": {"name": "ACCORD CUIRASS", "slot": "armor", "tier": 3,
		"price": 260, "blurb": "officer's issue, from better years",
		"mods": {"max_hp": 6}},
	"stalkers_rig": {"name": "STALKER'S RIG", "slot": "armor", "tier": 3,
		"price": 240, "blurb": "light plate cut for moving",
		"mods": {"max_hp": 3, "move_range": 1}},
	# --- kit ---
	"bandolier": {"name": "BANDOLIER", "slot": "kit", "tier": 1,
		"price": 40, "blurb": "rounds across the chest, ready",
		"mods": {"mag_size": 2}},
	"light_order": {"name": "LIGHT ORDER", "slot": "kit", "tier": 1,
		"price": 50, "blurb": "carry less. arrive first",
		"mods": {"move_range": 1}},
	"swivel_harness": {"name": "SWIVEL HARNESS", "slot": "kit", "tier": 2,
		"price": 100, "blurb": "the gun turns with you on watch",
		"mods": {"arc_half": 2}},
	"runners_canteen": {"name": "RUNNER'S CANTEEN", "slot": "kit", "tier": 2,
		"price": 120, "blurb": "water and wind for the long dash",
		"mods": {"move_range": 1, "max_hp": 1}},
	"pathfinder_kit": {"name": "PATHFINDER KIT", "slot": "kit", "tier": 3,
		"price": 230, "blurb": "maps, spikes, and no wasted steps",
		"mods": {"move_range": 2}},
	"watchmans_glass": {"name": "WATCHMAN'S GLASS", "slot": "kit", "tier": 3,
		"price": 250, "blurb": "see it coming. put it down",
		"mods": {"arc_half": 2, "accuracy": 4}},
}

# --- reading the catalog ------------------------------------------------------

## An item's stat mods, or {} for an unknown key - callers never branch on
## existence, they just add nothing.
static func mods_of(key: String) -> Dictionary:
	if not ITEMS.has(key):
		return {}
	return ITEMS[key].mods

## Catalog keys for one slot, catalog order (tier asc, cheap before dear).
static func keys_for_slot(slot: String) -> Array:
	var keys: Array = []
	for key in ITEMS:
		if str(ITEMS[key].slot) == slot:
			keys.append(key)
	return keys

## The soldier level an item demands. Unknown items gate at MAX+1 - nobody
## equips a key the catalog does not know.
static func level_gate(key: String) -> int:
	if not ITEMS.has(key):
		return 101
	return int(TIER_LEVEL.get(int(ITEMS[key].tier), 101))

## A won side mission's item drop: "" three times in four, otherwise a
## deterministic pick from the tier-1 and tier-2 pool. Keyed by the mission's
## own ordinal so the same target always shakes the same thing loose - and
## never twice, because the target leaves its pool on the banked win.
static func drop(seed: int, ordinal: int) -> String:
	if not Roll.chance(seed, ordinal, "gear:drop", DROP_PERCENT):
		return ""
	var pool: Array = []
	for key in ITEMS:
		if int(ITEMS[key].tier) <= 2:
			pool.append(key)
	pool.sort()
	return pool[Roll.pick(seed, ordinal, "gear:drop:which", pool.size())]

# --- self-check ---------------------------------------------------------------

## Everything test_gear.gd holds the catalog to, in one place: every problem
## returned as a string, empty array means the catalog is sound.
static func validate() -> Array:
	var problems: Array = []
	var per_slot_tier := {}
	for key in ITEMS:
		var item: Dictionary = ITEMS[key]
		if not SLOTS.has(str(item.get("slot", ""))):
			problems.append("%s: bad slot" % key)
		if not TIER_LEVEL.has(int(item.get("tier", 0))):
			problems.append("%s: bad tier" % key)
		if int(item.get("price", 0)) <= 0:
			problems.append("%s: price must be positive" % key)
		if str(item.get("name", "")).is_empty():
			problems.append("%s: no name" % key)
		if str(item.get("blurb", "")).length() > 48:
			problems.append("%s: blurb over 48 chars" % key)
		var mods: Dictionary = item.get("mods", {})
		if mods.is_empty():
			problems.append("%s: no mods" % key)
		for stat in mods:
			if not ALLOWED_MODS.has(str(stat)):
				problems.append("%s: illegal mod %s" % [key, stat])
			if int(mods[stat]) <= 0:
				problems.append("%s: mod %s must be positive" % [key, stat])
		var bucket := "%s:%d" % [str(item.get("slot", "")), int(item.get("tier", 0))]
		per_slot_tier[bucket] = int(per_slot_tier.get(bucket, 0)) + 1
	for slot in SLOTS:
		for tier in TIER_LEVEL:
			if int(per_slot_tier.get("%s:%d" % [slot, tier], 0)) != 2:
				problems.append("%s tier %d: want exactly 2 items" % [slot, tier])
	# Within a slot, a higher tier's cheapest item must out-price a lower
	# tier's dearest - the rack reads as a ladder, not a jumble.
	for slot in SLOTS:
		for tier in [1, 2]:
			var below := _price_range(slot, tier)
			var above := _price_range(slot, tier + 1)
			if below.size() == 2 and above.size() == 2 and above[0] <= below[1]:
				problems.append("%s: tier %d prices overlap tier %d" % [slot, tier + 1, tier])
	return problems

## [min, max] price for a (slot, tier) bucket, [] when the bucket is empty.
static func _price_range(slot: String, tier: int) -> Array:
	var prices: Array = []
	for key in ITEMS:
		if str(ITEMS[key].slot) == slot and int(ITEMS[key].tier) == tier:
			prices.append(int(ITEMS[key].price))
	if prices.is_empty():
		return []
	prices.sort()
	return [prices[0], prices[prices.size() - 1]]
