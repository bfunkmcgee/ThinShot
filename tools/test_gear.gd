extends SceneTree

## The equipment system, pinned at both layers.
##
## The pure half - the catalog and its arithmetic - runs without a scene:
##   1. validate() answers clean, and the harness re-checks the invariants
##      independently (a validator asserting itself proves little)
##   2. NO ITEM TOUCHES DAMAGE - the even-damage cover-halving invariant
##      (Rules.gd) must survive this system forever
##   3. the drop is deterministic and draws only from tiers 1-2
##
## The Game half drives the book through the autoload:
##   4. buy_item: the catalog gate, the tier gate, the price, the multiset
##   5. equip_item: slot match, level gate, the swap back to the shelf, and
##      one-item-one-body
##
## Gear and Career are safe to name at parse time - neither names an
## autoload (Gear names only Roll).
##
## Run: godot --headless --path . -s tools/test_gear.gd

const SAVE_PATH := "user://campaign.json"
const BACKUP_PATH := "user://campaign.json.gear-test-backup"

var _failed := false
var _had_save := false


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    %s" % label)
	else:
		printerr("  FAIL  %s" % label)
		_failed = true


func _init() -> void:
	_had_save = FileAccess.file_exists(SAVE_PATH)
	if _had_save:
		DirAccess.copy_absolute(SAVE_PATH, BACKUP_PATH)
	_run()


func _restore() -> void:
	if _had_save:
		DirAccess.copy_absolute(BACKUP_PATH, SAVE_PATH)
		DirAccess.remove_absolute(BACKUP_PATH)
		print("\nrestored the original save")
	elif FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


func _run() -> void:
	_test_catalog()
	_test_no_damage()
	_test_drop()
	await process_frame
	_test_buying()
	_test_equipping()
	_restore()
	print("\nRESULT: ", "FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


# --- 1. the catalog -----------------------------------------------------------

func _test_catalog() -> void:
	print("\n[1] the catalog is sound, and the harness agrees independently")
	var problems: Array = Gear.validate()
	_check(problems.is_empty(), "validate() answers clean (%s)" % [problems])
	# Two per (slot, tier), counted here rather than trusted to validate().
	var buckets := {}
	for key: String in Gear.ITEMS:
		var b := "%s:%d" % [str(Gear.ITEMS[key].slot), int(Gear.ITEMS[key].tier)]
		buckets[b] = int(buckets.get(b, 0)) + 1
	var two_each := true
	for slot: String in Gear.SLOTS:
		for tier: int in Gear.TIER_LEVEL:
			if int(buckets.get("%s:%d" % [slot, tier], 0)) != 2:
				two_each = false
	_check(two_each and Gear.ITEMS.size() == 18,
			"18 items, two per slot per tier (%d)" % Gear.ITEMS.size())
	# Price monotonicity: within a slot, every higher-tier item out-prices
	# every lower-tier one.
	var ladder := true
	for key_a: String in Gear.ITEMS:
		for key_b: String in Gear.ITEMS:
			var a: Dictionary = Gear.ITEMS[key_a]
			var b: Dictionary = Gear.ITEMS[key_b]
			if str(a.slot) == str(b.slot) and int(a.tier) < int(b.tier) \
					and int(a.price) >= int(b.price):
				ladder = false
	_check(ladder, "within a slot, a dearer tier is always dearer")
	_check(Gear.mods_of("no_such_item").is_empty(), "mods_of unknown is {}")
	_check(Gear.level_gate("no_such_item") > Career.MAX_LEVEL,
			"an unknown key gates above the ladder")
	_check(Gear.level_gate("oiled_sling") == 1
			and Gear.level_gate("glass_sight") == 10
			and Gear.level_gate("match_fittings") == 25,
			"the tier gates read 1/10/25")
	for slot: String in Gear.SLOTS:
		_check(Gear.keys_for_slot(slot).size() == 6,
				"%s shelf lists its 6" % slot)


# --- 2. nothing touches damage ------------------------------------------------

func _test_no_damage() -> void:
	print("\n[2] no item touches damage - the cover-halving invariant survives")
	_check(not Gear.ALLOWED_MODS.has("damage"), "the whitelist has no damage key")
	var dirty: Array[String] = []
	for key: String in Gear.ITEMS:
		for stat: String in (Gear.ITEMS[key].mods as Dictionary):
			if stat == "damage" or not Gear.ALLOWED_MODS.has(stat):
				dirty.append("%s:%s" % [key, stat])
	_check(dirty.is_empty(),
			"and no item smuggles one in anyway (%s)" % [dirty])


# --- 3. the drop --------------------------------------------------------------

func _test_drop() -> void:
	print("\n[3] the drop is deterministic and stays in tiers 1-2")
	var stable := true
	var contained := true
	var dropped := 0
	for seed_ordinal in 40:
		var seed := 555000 + seed_ordinal * 3301
		for ordinal in [1000, 1041, 2000, 2001, 2002]:
			var first := Gear.drop(seed, ordinal)
			if Gear.drop(seed, ordinal) != first:
				stable = false
			if not first.is_empty():
				dropped += 1
				if int(Gear.ITEMS[first].tier) > 2:
					contained = false
	_check(stable, "the same seed and target always shake the same answer")
	_check(contained, "nothing tier 3 ever drops - the top shelf is bought")
	_check(dropped > 0, "and across 200 draws, something dropped (%d)" % dropped)


# --- 4. buying ----------------------------------------------------------------

func _test_buying() -> void:
	print("\n[4] the quartermaster's gates: catalog, tier, price")
	var game: Node = root.get_node("/root/Game")
	game.roster = []
	game._next_id = 1
	game.ensure_roster(Levels.LEVELS[0])
	game.scrip = 100
	game.armory = []
	_check(not game.buy_item("no_such_item"), "an unknown key is refused")
	_check(not game.buy_item("glass_sight"),
			"a level-1 squad cannot reach the tier-2 shelf")
	_check(game.buy_item("oiled_sling"), "a tier-1 buy goes through")
	_check(game.scrip == 60 and game.armory == ["oiled_sling"],
			"the price left the book and the item is on the shelf")
	_check(game.buy_item("oiled_sling") and game.armory.size() == 2,
			"buying it again is a second sling, not a no-op")
	_check(not game.buy_item("padded_jacket") or game.scrip >= 0,
			"the book never goes negative")
	game.scrip = 10
	_check(not game.buy_item("padded_jacket"),
			"10 scrip does not cover a 40-scrip jacket")
	# The tier gate follows the best LIVING soldier.
	(game.roster[0] as Dictionary).level = 25
	game.scrip = 300
	_check(game.buy_item("match_fittings"),
			"a level-25 soldier opens the tier-3 shelf")
	(game.roster[0] as Dictionary).alive = false
	_check(not game.buy_item("glass_sight"),
			"...and his death closes it again (best living is level 1)")
	(game.roster[0] as Dictionary).alive = true


# --- 5. equipping -------------------------------------------------------------

func _test_equipping() -> void:
	print("\n[5] equipping: slot match, level gate, the swap, one body")
	var game: Node = root.get_node("/root/Game")
	game.roster = []
	game._next_id = 1
	game.ensure_roster(Levels.LEVELS[0])
	var first: Dictionary = game.roster[0]
	var second: Dictionary = game.roster[1]
	first.level = 10
	second.level = 1
	game.armory = ["oiled_sling", "glass_sight", "scrap_vest"]
	var id := int(first.id)
	_check(not game.equip_item(id, "weapon", "no_such_item"),
			"an unknown key is refused")
	_check(not game.equip_item(id, "hat", "oiled_sling"),
			"an unknown slot is refused")
	_check(not game.equip_item(id, "weapon", "scrap_vest"),
			"armor does not go in the weapon slot")
	_check(not game.equip_item(id, "weapon", "drum_feed"),
			"an item the armory does not hold cannot be taken")
	_check(not game.equip_item(int(second.id), "weapon", "glass_sight"),
			"a level-1 soldier cannot carry a tier-2 sight")
	_check(game.equip_item(id, "weapon", "oiled_sling"),
			"a legal equip goes through")
	_check(str((first.gear as Dictionary).weapon) == "oiled_sling"
			and not game.armory.has("oiled_sling"),
			"the sling is on him and off the shelf")
	_check(game.equip_item(id, "weapon", "glass_sight"),
			"swapping to the sight goes through")
	_check(str((first.gear as Dictionary).weapon) == "glass_sight"
			and game.armory.has("oiled_sling"),
			"and the sling went back to the shelf")
	_check(not game.equip_item(int(second.id), "weapon", "glass_sight"),
			"one sight cannot be on two bodies (it is on him, not the shelf)")
	_check(game.equip_item(id, "weapon", ""),
			"an empty key unequips")
	_check(str((first.gear as Dictionary).weapon) == ""
			and game.armory.has("glass_sight"),
			"and the sight is back on the shelf")
	var dead_id := int(second.id)
	second.alive = false
	_check(not game.equip_item(dead_id, "armor", "scrap_vest"),
			"the dead are not issued equipment")
	second.alive = true