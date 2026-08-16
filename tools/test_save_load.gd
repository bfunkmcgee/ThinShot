extends SceneTree

## Round-trips a campaign through Game.save()/load_save() and asserts that both
## the values and their TYPES survive.
##
## The types are the point. JSON has one number type, so every int written out
## comes back as a float unless it is coerced on the way in - and a rank that
## loads as 3.0 compares wrong in rank_for_xp() and rank_title(), a kind that
## loads as 2.0 misses every `match` on Unit.Kind, and neither fails loudly.
##
## Any real save is backed up and restored, so this is safe to run on a machine
## someone is actually playing on.
##
## Run: godot --headless --path . -s tools/test_save_load.gd

const GAME := preload("res://scripts/Game.gd")

var _failed := false


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

	print("\n[7] a save from an unknown version is refused")
	var vf := FileAccess.open(game.SAVE_PATH, FileAccess.WRITE)
	vf.store_string(JSON.stringify({"version": 999, "roster": []}))
	vf.close()
	_check(game.load_save() == false, "load_save() refused a future version")

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
