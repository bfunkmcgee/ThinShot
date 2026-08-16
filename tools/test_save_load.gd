extends SceneTree

## Round-trips a campaign through Game.save()/load_save() and asserts that both
## the values and their TYPES survive.
##
## The types are the point. JSON has one number type, so every int written out
## comes back as a float unless it is coerced on the way in - and a rank that
## loads as 3.0 compares wrong in rank_for_xp() and rank_title(), a kind that
## loads as 2.0 misses every `match` on Unit.Kind, and neither fails loudly.
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
		{"id": 1, "surname": "NAKAMURA", "kind": 1, "xp": 27, "rank": 3,
				"perks": ["marksman", "sentinel"] as Array, "alive": true},
		# The gunner carries class-tree perk strings: they must round-trip
		# exactly like the four originals.
		{"id": 2, "surname": "HARGREAVE", "kind": 2, "xp": 8, "rank": 1,
				"perks": ["pack_mule", "grenadier"] as Array, "alive": true},
		# A perk string the game does not know must be dropped on load, and
		# must not take the known one beside it down with it.
		{"id": 3, "surname": "VANCE", "kind": 0, "xp": 3, "rank": 0,
				"perks": ["flanker", "ghost_perk"] as Array, "alive": false},
		{"id": 4, "surname": "Akai", "kind": 9, "xp": 15, "rank": 2,
				"perks": ["marksman", "called_shot"] as Array, "alive": true},
	]
	game._next_id = 5
	_check(game.roster.size() == 4, "roster populated (%d)" % game.roster.size())
	var lead: Dictionary = game.roster[0]
	var fallen: Dictionary = game.roster[2]
	var fallen_id := int(fallen.id)
	# The lead's rank-3 pick survives via the TEAM_LEAD->HERO table mapping
	# (his conversion to Rodar happens after load); the gunner's rank-4 pick is
	# a class-tree rank that never offered a choice before. Rank 7 exists in no
	# table and must be dropped.
	game.pending_promotions.append({"id": int(lead.id), "rank": 3})
	game.pending_promotions.append({"id": 2, "rank": 4})
	game.pending_promotions.append({"id": 2, "rank": 7})
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
			"rank": 0, "perks": [], "alive": true}]
	game.pending_promotions = []
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
	_check(int(back.get("rank", -1)) == 3, "lead rank 3 (got %s)" % back.get("rank"))
	_check((back.get("perks", []) as Array).has("marksman")
			and (back.get("perks", []) as Array).has("sentinel"), "both perks kept")
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
	_check(game.pending_promotions.size() == 2
			and int(game.pending_promotions[0].rank) == 3
			and int(game.pending_promotions[1].rank) == 4,
			"promotion queue survived, rank-7 junk dropped (got %s)"
			% [game.pending_promotions])

	print("\n[4] types survived JSON (the whole reason for the coercion)")
	_check(typeof(back["xp"]) == TYPE_INT, "xp is int, not float")
	_check(typeof(back["rank"]) == TYPE_INT, "rank is int, not float")
	_check(typeof(back["id"]) == TYPE_INT, "id is int, not float")
	_check(typeof(back["kind"]) == TYPE_INT, "kind is int, not float")
	_check(typeof(game.soldier_by_id(4)["kind"]) == TYPE_INT, "hero kind is int, not float")
	_check(typeof(back["alive"]) == TYPE_BOOL, "alive is bool")
	_check(typeof(game.pending_promotions[0]["rank"]) == TYPE_INT,
			"promotion rank is int")
	# The load must be usable by the code that reads it, not merely equal.
	_check(game.rank_title(int(back["rank"])) == "Staff Sergeant",
			"rank_title reads the loaded rank (got '%s')"
			% game.rank_title(int(back["rank"])))
	_check(game.rank_for_xp(int(back["xp"])) == 3,
			"rank_for_xp agrees with the stored rank")

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

	print("\n[11] the lock is not sticky")
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
