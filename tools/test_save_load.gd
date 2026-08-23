extends SceneTree

## Round-trips a campaign through Game.save()/load_save() and asserts that both
## the values and their TYPES survive.
##
## The types are the point. JSON has one number type, so every int written out
## comes back as a float unless it is coerced on the way in - and a level that
## loads as 3.0 compares wrong in Career.level_for_xp(), a kind that loads as
## 2.0 misses every `match` on Unit.Kind, and neither fails loudly.
##
## Sections 7-11 are the version machinery rather than the round trip: that a
## newer save is refused AND left unwritten, that an older one climbs the
## migration ladder with its roster intact, that a version this build cannot
## start from is still refused, that the ladder has no missing rungs, and that
## the newer-save lock never sticks to a session that did not meet one.
##
## Any real save is backed up and restored, so this is safe to run on a machine
## someone is actually playing on.
##
## Run: godot --headless --path . -s tools/test_save_load.gd

const GAME := preload("res://scripts/Game.gd")

var _failed := false


## What is actually on disk, as a Dictionary - {} if the file is gone or is not
## an object. The version assertions read the FILE rather than the Game that
## wrote it, because "did save() touch this" is a question only the file can
## answer.
func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    %s" % label)
	else:
		printerr("  FAIL  %s" % label)
		_failed = true


func _init() -> void:
	var game: Node = GAME.new()
	var backup: String = ""
	var had_save: bool = FileAccess.file_exists(game.SAVE_PATH)
	if had_save:
		var bf := FileAccess.open(game.SAVE_PATH, FileAccess.READ)
		backup = bf.get_as_text()
		bf.close()
		print("backed up existing save (%d bytes)" % backup.length())

	print("\n[1] build a campaign and write it")
	# Built by hand rather than through ensure_roster(): under `-s` the global
	# class registry resolves `Unit` to a bare GDScript, so the static
	# Unit.kind_role_name() that ensure_roster prints with is not callable here.
	# That is a quirk of this harness, not of the game. Kind is the raw enum
	# ordinal - 0 SCOUT, 1 TEAM_LEAD, 2 MACHINEGUNNER, and 9 HERO (Rodar Akai,
	# appended after CIVILIAN=8; the save depends on that ordinal never moving).
	game.roster = [
		{"id": 1, "surname": "NAKAMURA", "kind": 1, "xp": 27, "level": 11,
				"gear": {"weapon": "oiled_sling", "armor": "", "kit": ""},
				"perks": ["marksman", "sentinel"] as Array, "alive": true},
		# The gunner carries class-tree perk strings: they must round-trip
		# exactly like the four originals. His weapon slot holds a key the
		# catalog does not know - it must load back as "", and must not take
		# the real armor beside it down with it.
		{"id": 2, "surname": "HARGREAVE", "kind": 2, "xp": 8, "level": 5,
				"gear": {"weapon": "ghost_item", "armor": "scrap_vest", "kit": ""},
				"perks": ["pack_mule", "grenadier"] as Array, "alive": true},
		# A perk string the game does not know must be dropped on load, and
		# must not take the known one beside it down with it.
		{"id": 3, "surname": "VANCE", "kind": 0, "xp": 3, "level": 3,
				"perks": ["flanker", "ghost_perk"] as Array, "alive": false},
		# A real item in the WRONG slot (armor in the kit slot) is as invalid
		# as an unknown key, and gets the same "".
		{"id": 4, "surname": "Akai", "kind": 9, "xp": 15, "level": 8,
				"gear": {"weapon": "glass_sight", "armor": "", "kit": "scrap_vest"},
				"perks": ["marksman", "called_shot"] as Array, "alive": true},
	]
	game._next_id = 5
	_check(game.roster.size() == 4, "roster populated (%d)" % game.roster.size())
	var lead: Dictionary = game.roster[0]
	var fallen: Dictionary = game.roster[2]
	var fallen_id := int(fallen.id)
	# The lead's gate-30 pick survives via the TEAM_LEAD->HERO table mapping
	# (his conversion to Rodar happens after load); the gunner's gate-50 pick
	# exercises the top gate. Level 7 is no gate at all and must be dropped.
	game.pending_promotions.append({"id": int(lead.id), "level": 30})
	game.pending_promotions.append({"id": 2, "level": 50})
	game.pending_promotions.append({"id": 2, "level": 7})
	# The company book: a duplicate is two real items, and junk is dropped on
	# the way back in. Negative scrip is a tamper case tested separately.
	game.scrip = 123
	game.armory = ["oiled_sling", "oiled_sling", "boiler_plate", "ghost_item"]
	game.current_level = 4
	game.current_operation = 1
	game.in_the_field = true
	game.frags = 3
	game.smokes = 1
	var want_ids: Array = []
	for s: Dictionary in game.roster:
		want_ids.append(int(s.id))
	var want_next_id: int = game._next_id
	game.save()
	_check(FileAccess.file_exists(game.SAVE_PATH), "save file written")

	print("\n[2] scribble over every field, then load")
	game.roster = [{"id": 99, "surname": "WRONG", "kind": 0, "xp": 0,
			"level": 1, "perks": [], "alive": true}]
	game.pending_promotions = []
	game.scrip = 0
	game.armory = []
	game.current_level = 0
	game.current_operation = 0
	game.in_the_field = false
	game.frags = 0
	game.smokes = 0
	game._next_id = 1
	game._snapshot = [{"id": 1}]
	game.mission_xp = {1: 5}
	game.mission_dead = {1: true}
	_check(game.load_save(), "load_save() reported success")

	print("\n[3] values came back")
	_check(game.current_level == 4, "current_level 4 (got %s)" % game.current_level)
	_check(game.current_operation == 1, "current_operation 1 (got %s)" % game.current_operation)
	_check(game.in_the_field == true, "in_the_field true")
	_check(game.frags == 3 and game.smokes == 1,
			"loadout 3/1 (got %d/%d)" % [game.frags, game.smokes])
	_check(game._next_id == want_next_id,
			"_next_id %d (got %s)" % [want_next_id, game._next_id])
	var got_ids: Array = []
	for s: Dictionary in game.roster:
		got_ids.append(int(s.id))
	_check(got_ids == want_ids, "roster ids %s (got %s)" % [want_ids, got_ids])
	var back: Dictionary = game.soldier_by_id(int(lead.id))
	_check(not back.is_empty(), "lead found by id")
	_check(int(back.get("xp", -1)) == 27, "lead xp 27 (got %s)" % back.get("xp"))
	_check(int(back.get("level", -1)) == 11, "lead level 11 (got %s)" % back.get("level"))
	_check((back.get("perks", []) as Array).has("marksman")
			and (back.get("perks", []) as Array).has("sentinel"), "both perks kept")
	_check(str((back.get("gear", {}) as Dictionary).get("weapon", "?")) == "oiled_sling",
			"the lead's sling round-trips (got %s)" % [back.get("gear")])
	_check(bool(game.soldier_by_id(fallen_id).get("alive", true)) == false,
			"the fallen stayed dead")
	var hero: Dictionary = game.soldier_by_id(4)
	_check(not hero.is_empty(), "hero found by id")
	_check(int(hero.get("kind", -1)) == 9, "hero kind ordinal 9 (got %s)" % hero.get("kind"))
	_check(str(hero.get("surname", "")) == "Akai",
			"hero surname 'Akai' (got '%s')" % hero.get("surname"))
	var gunner: Dictionary = game.soldier_by_id(2)
	_check((gunner.get("perks", []) as Array) == ["pack_mule", "grenadier"],
			"class-tree perk strings round-trip (got %s)" % [gunner.get("perks")])
	_check((hero.get("perks", []) as Array) == ["marksman", "called_shot"],
			"hero perk strings round-trip (got %s)" % [hero.get("perks")])
	_check((game.soldier_by_id(fallen_id).get("perks", []) as Array) == ["flanker"],
			"unknown perk dropped, the known one kept (got %s)"
			% [game.soldier_by_id(fallen_id).get("perks")])
	var gunner_gear: Dictionary = gunner.get("gear", {})
	_check(str(gunner_gear.get("weapon", "?")) == ""
			and str(gunner_gear.get("armor", "?")) == "scrap_vest",
			"unknown gear key dropped to \"\", the real vest kept (got %s)"
			% [gunner_gear])
	var hero_gear: Dictionary = hero.get("gear", {})
	_check(str(hero_gear.get("kit", "?")) == ""
			and str(hero_gear.get("weapon", "?")) == "glass_sight",
			"an armor item in the kit slot is dropped to \"\" (got %s)" % [hero_gear])
	var fallen_gear: Dictionary = game.soldier_by_id(fallen_id).get("gear", {})
	_check(str(fallen_gear.get("weapon", "?")) == "" and fallen_gear.size() == 3,
			"a soldier saved without gear loads the three empty slots (got %s)"
			% [fallen_gear])
	_check(game.pending_promotions.size() == 2
			and int(game.pending_promotions[0].level) == 30
			and int(game.pending_promotions[1].level) == 50,
			"promotion queue survived, the level-7 junk dropped (got %s)"
			% [game.pending_promotions])
	_check(game.scrip == 123, "scrip round-trips (got %d)" % game.scrip)
	_check(game.armory == ["oiled_sling", "oiled_sling", "boiler_plate"],
			"the armory keeps its duplicate and drops the junk (got %s)"
			% [game.armory])

	print("\n[4] types survived JSON (the whole reason for the coercion)")
	_check(typeof(back["xp"]) == TYPE_INT, "xp is int, not float")
	_check(typeof(back["level"]) == TYPE_INT, "level is int, not float")
	_check(typeof(back["id"]) == TYPE_INT, "id is int, not float")
	_check(typeof(back["kind"]) == TYPE_INT, "kind is int, not float")
	_check(typeof(game.soldier_by_id(4)["kind"]) == TYPE_INT, "hero kind is int, not float")
	_check(typeof(back["alive"]) == TYPE_BOOL, "alive is bool")
	_check(typeof(game.pending_promotions[0]["level"]) == TYPE_INT,
			"promotion level is int")
	_check(typeof(game.scrip) == TYPE_INT, "scrip is int, not float")
	# The load must be usable by the code that reads it, not merely equal.
	_check(Career.level_label(int(back["level"])) == "Level 11",
			"level_label reads the loaded level (got '%s')"
			% Career.level_label(int(back["level"])))
	_check(Career.level_for_xp(int(back["xp"])) == 11,
			"level_for_xp agrees with the stored level")

	print("\n[5] per-mission scratch was not restored")
	_check(game._snapshot.is_empty(), "_snapshot cleared")
	_check(game.mission_xp.is_empty(), "mission_xp cleared")
	_check(game.mission_dead.is_empty(), "mission_dead cleared")

	print("\n[6] a corrupt save is no worse than a missing one")
	var cf := FileAccess.open(game.SAVE_PATH, FileAccess.WRITE)
	cf.store_string("{ this is not json")
	cf.close()
	var before_level: int = game.current_level
	_check(game.load_save() == false, "load_save() refused the corrupt file")
	_check(game.current_level == before_level, "state left untouched by the failure")

	print("\n[7] a save from an unknown version is refused - and left alone")
	var vf := FileAccess.open(game.SAVE_PATH, FileAccess.WRITE)
	vf.store_string(JSON.stringify({"version": 999, "roster": []}))
	vf.close()
	_check(game.load_save() == false, "load_save() refused a future version")
	# Refusing to READ it is only half the job. What a real session does next is
	# form a squad from the empty roster the refusal left and checkpoint it -
	# straight over the campaign it just declined to understand. So the refusal
	# has to reach into save() as well, and this is the regression test for it:
	# after the refusal, saving must not touch the file.
	game.save()
	var kept: Dictionary = _read_json(game.SAVE_PATH)
	_check(int(kept.get("version", 0)) == 999,
			"save() left the newer file alone (version %s)" % kept.get("version", "gone"))

	print("\n[8] a version-1 save climbs the ladder to %d" % game.SAVE_VERSION)
	# Written by hand in the version-1 shape - no campaign_seed, no
	# mission_attempts - because that is what is genuinely sitting on players'
	# disks. A fresh Game: the one above is locked for good, which is the point
	# of it.
	var g2: Node = GAME.new()
	var mf := FileAccess.open(g2.SAVE_PATH, FileAccess.WRITE)
	mf.store_string(JSON.stringify({
		"version": 1,
		"current_operation": 1,
		"current_level": 4,
		"in_the_field": true,
		"frags": 3,
		"smokes": 1,
		"next_id": 3,
		"roster": [
			{"id": 1, "surname": "KELLER", "kind": 0, "xp": 14, "rank": 2,
					"perks": ["sprinter", "flanker"], "alive": true},
			{"id": 2, "surname": "Akai", "kind": 9, "xp": 26, "rank": 3,
					"perks": ["called_shot"], "alive": true},
		],
		"pending_promotions": [],
	}, "\t"))
	mf.close()
	_check(g2.load_save(), "load_save() accepted the v1 save")
	var climbed_ids: Array = []
	for s: Dictionary in g2.roster:
		climbed_ids.append(int(s.id))
	_check(climbed_ids == [1, 2], "both soldiers survived the climb (got %s)" % [climbed_ids])
	_check((g2.soldier_by_id(1).get("perks", []) as Array) == ["sprinter", "flanker"]
			and (g2.soldier_by_id(2).get("perks", []) as Array) == ["called_shot"],
			"perks came through the migration intact")
	_check(int(g2.soldier_by_id(2).get("kind", -1)) == 9
			and int(g2.soldier_by_id(1).get("xp", -1)) == 14,
			"kinds and xp came through the migration intact")
	_check(int(g2.soldier_by_id(1).get("level", -1)) == 7
			and int(g2.soldier_by_id(2).get("level", -1)) == 11,
			"the v10 rung recomputed levels from the kept XP (got %s/%s)"
			% [g2.soldier_by_id(1).get("level"), g2.soldier_by_id(2).get("level")])
	_check(not g2.soldier_by_id(1).has("rank"),
			"and the rank key is gone from the loaded roster")
	_check(g2.current_level == 4 and g2.current_operation == 1
			and g2.frags == 3 and g2.in_the_field,
			"the v1 fields were not disturbed by the climb")
	# What v2 actually carries.
	_check(g2.campaign_seed != 0, "the climb minted a campaign_seed (%s)" % g2.campaign_seed)
	_check(g2.mission_attempts == 0,
			"mission_attempts starts at 0 (got %s)" % g2.mission_attempts)
	_check(g2.battle_seed() != 0, "battle_seed() has something to work with")
	var minted: int = g2.campaign_seed
	# The climb checkpoints itself, before anything else in the session has a
	# reason to save. Without that the file would be climbed again at every
	# launch - and the v1 rung mints a seed, so "again" means a different
	# campaign every time.
	var checkpointed: Dictionary = _read_json(g2.SAVE_PATH)
	_check(int(checkpointed.get("version", 0)) == g2.SAVE_VERSION
			and int(checkpointed.get("campaign_seed", 0)) == minted,
			"load_save() wrote the climb back out (version %s, seed %s)"
			% [checkpointed.get("version", "?"), checkpointed.get("campaign_seed", "?")])
	g2.save()
	var upgraded: Dictionary = _read_json(g2.SAVE_PATH)
	_check(int(upgraded.get("version", 0)) == g2.SAVE_VERSION,
			"the file on disk is now version %s (got %s)"
			% [g2.SAVE_VERSION, upgraded.get("version", "?")])
	_check(int(upgraded.get("campaign_seed", 0)) == minted,
			"...carrying the seed it was minted with")
	_check(g2.load_save() and g2.campaign_seed == minted,
			"a second load re-reads that seed rather than minting another")

	print("\n[9] a version-0 or unversioned save is still refused")
	# The ladder is a way forward for saves this build understands, not a way in
	# for anything that happens to parse.
	for junk: Dictionary in [
			{"roster": [{"id": 1, "surname": "GHOST", "kind": 0}]},
			{"version": 0, "roster": [{"id": 1, "surname": "GHOST", "kind": 0}]},
			{"version": "one", "roster": [{"id": 1, "surname": "GHOST", "kind": 0}]}]:
		var jf := FileAccess.open(g2.SAVE_PATH, FileAccess.WRITE)
		jf.store_string(JSON.stringify(junk))
		jf.close()
		_check(g2.load_save() == false,
				"refused version %s" % junk.get("version", "<missing>"))
	_check(g2.roster.size() == 2 and g2.campaign_seed == minted,
			"the refusals left the loaded campaign untouched")
	_check(g2._save_locked == false, "an old save does not lock saving")

	print("\n[10] the ladder has no gaps")
	# A missing rung is a bug in Game.gd, not a bad save: SAVE_VERSION raised
	# without the step that reaches it. Every version from 1 up must be able to
	# take one step forward.
	for v in range(1, g2.SAVE_VERSION):
		_check(not (g2._migrate_step({}, v) as Dictionary).is_empty(),
				"there is a step out of version %d" % v)

	print("\n[11] a version-2 save gains the theater's memory")
	# The v3 rung, from the shape a player of the seeded build actually has on
	# disk right now: campaign_seed and mission_attempts, and nothing after.
	var g3: Node = GAME.new()
	var mf3 := FileAccess.open(g3.SAVE_PATH, FileAccess.WRITE)
	mf3.store_string(JSON.stringify({
		"version": 2,
		"current_operation": 0, "current_level": 2, "in_the_field": false,
		"frags": 2, "smokes": 2, "next_id": 2,
		"roster": [{"id": 1, "surname": "ODUYA", "kind": 0, "xp": 6, "rank": 1,
				"perks": ["sprinter"], "alive": true}],
		"pending_promotions": [],
		"campaign_seed": 555111, "mission_attempts": 2,
	}, "\t"))
	mf3.close()
	_check(g3.load_save(), "load_save() accepted the v2 save")
	_check(g3.campaign_seed == 555111 and g3.mission_attempts == 2
			and g3.current_level == 2,
			"the v2 fields were not disturbed by the climb")
	_check(g3.notebook.is_empty(), "the notebook opens empty")
	_check(g3.district_standing.is_empty(), "and no district has an opinion yet")
	_check(g3.alliance_strain == g3.STRAIN_START,
			"Strain opens where a fresh campaign opens (%d)" % g3.alliance_strain)
	_check(g3.standing_of("Kessit") == g3.STANDING_START,
			"a settlement nobody has met reads as STANDING_START (%d)"
			% g3.standing_of("Kessit"))

	# The document and the counters survive a round trip.
	g3.add_to_notebook(2, [
		{"identity": {"name": "Kesh Varr", "age": 33, "settlement": "Kessit"},
				"fate": "killed"},
		{"identity": {}, "fate": "escaped"},
	])
	g3.set_standing("Kessit", 31)
	g3.alliance_strain = 44
	g3.save()
	var g4: Node = GAME.new()
	_check(g4.load_save(), "the v3 file loads back")
	_check(g4.notebook.size() == 2
			and str((g4.notebook[0] as Dictionary).get("name", "")) == "Kesh Varr"
			and int((g4.notebook[0] as Dictionary).get("level", -1)) == 2,
			"the notebook round-trips with its names and its missions")
	_check(g4.standing_of("Kessit") == 31 and g4.alliance_strain == 44,
			"so do Standing and Strain (%d / %d)"
			% [g4.standing_of("Kessit"), g4.alliance_strain])
	_check((g4.notebook_by_settlement().get("Kessit", []) as Array).size() == 1,
			"and the notebook cross-links by settlement")

	# A hand-edited file must not be able to stand the theater at zero Strain,
	# and must not be able to invent a district by writing nonsense at one.
	var tampered: Dictionary = _read_json(g4.SAVE_PATH)
	tampered["alliance_strain"] = 0
	tampered["district_standing"] = {"Kessit": 31, "": 5, "Ashet Draw": "nonsense"}
	var tf := FileAccess.open(g4.SAVE_PATH, FileAccess.WRITE)
	tf.store_string(JSON.stringify(tampered, "\t"))
	tf.close()
	var g5: Node = GAME.new()
	_check(g5.load_save(), "a tampered v3 file still loads")
	_check(g5.alliance_strain >= 1,
			"but Strain 0 is refused on the way in (%d)" % g5.alliance_strain)
	_check(not g5.district_standing.has("")
			and not g5.district_standing.has("Ashet Draw")
			and g5.standing_of("Kessit") == 31,
			"and unreadable district entries are dropped rather than repaired")
	g3.free()
	g4.free()
	g5.free()

	print("\n[12] a version-9 save trades its ranks for the career ladder")
	# The exact shape the ratline build wrote: a ranked soldier with a queued
	# rank-3 pick. The rung must recompute the level from XP (27 -> 11), erase
	# the rank, default the gear, translate the pick to gate level 30, and
	# open an empty company book.
	var g6: Node = GAME.new()
	var mf6 := FileAccess.open(g6.SAVE_PATH, FileAccess.WRITE)
	mf6.store_string(JSON.stringify({
		"version": 9,
		"current_operation": 0, "current_level": 1, "in_the_field": false,
		"frags": 2, "smokes": 2, "next_id": 2,
		"roster": [{"id": 1, "surname": "KELLER", "kind": 0, "xp": 27, "rank": 3,
				"perks": ["sprinter"], "alive": true}],
		"pending_promotions": [{"id": 1, "rank": 3}],
		"campaign_seed": 777333, "mission_attempts": 1,
	}, "\t"))
	mf6.close()
	_check(g6.load_save(), "load_save() accepted the v9 save")
	var veteran: Dictionary = g6.soldier_by_id(1)
	_check(int(veteran.get("level", -1)) == 11,
			"27 xp becomes level 11 (got %s)" % veteran.get("level"))
	_check(not veteran.has("rank"), "the rank key is erased")
	_check((veteran.get("gear", {}) as Dictionary) ==
			{"weapon": "", "armor": "", "kit": ""},
			"the gear slots default empty (got %s)" % [veteran.get("gear")])
	_check(g6.pending_promotions == [{"id": 1, "level": 30}],
			"the queued rank-3 pick becomes gate level 30 (got %s)"
			% [g6.pending_promotions])
	_check(g6.scrip == 0 and g6.armory.is_empty(),
			"the company book opens empty")
	# A tampered book: negative scrip must floor at 0 on the way back in.
	var tampered_book: Dictionary = _read_json(g6.SAVE_PATH)
	tampered_book["scrip"] = -400
	var tbf := FileAccess.open(g6.SAVE_PATH, FileAccess.WRITE)
	tbf.store_string(JSON.stringify(tampered_book, "\t"))
	tbf.close()
	_check(g6.load_save() and g6.scrip == 0,
			"hand-edited debt is floored at 0 (got %d)" % g6.scrip)
	g6.free()

	print("\n[13] the lock is not sticky")
	g2.frags = 1
	g2.smokes = 3
	g2.save()
	var rewritten: Dictionary = _read_json(g2.SAVE_PATH)
	_check(int(rewritten.get("frags", -1)) == 1,
			"an unlocked Game still writes (frags %s)" % rewritten.get("frags", "?"))
	g2.free()

	# --- restore whatever was there before ---
	if had_save:
		var rf := FileAccess.open(game.SAVE_PATH, FileAccess.WRITE)
		rf.store_string(backup)
		rf.close()
		print("\nrestored the original save")
	else:
		game.delete_save()
		print("\nremoved the test save")

	game.free()
	print("\nRESULT: ", "FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)
