extends SceneTree

## The squad's wound ledger, pinned at the Game/Unit seam.
##
##   1. a wound is stamped, survives a save round-trip, and reads back a bool
##   2. a wounded soldier deploys a point of max HP short - after level
##      bonuses, so the cost is exactly one point at any career
##   3. sitting a mission out heals him; fighting it does not
##   4. coming home to the garrison clears the ledger outright
##   5. a v7 save (no wounded key) climbs the ladder to nobody-wounded
##
## Game state is manipulated directly - the battle-side stamping (below half
## on a won mission) is one guarded loop in _show_game_over, and what matters
## to the campaign is the ledger arithmetic, which is all here.
##
## Run: godot --headless --path . -s tools/test_wounds.gd

const SAVE_PATH := "user://campaign.json"
const BACKUP_PATH := "user://campaign.json.wounds-test-backup"

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
	await process_frame
	var game: Node = root.get_node("/root/Game")
	var unit_script: GDScript = load("res://scripts/Unit.gd") as GDScript

	print("\n[1] the flag is stamped and survives the disk")
	game.new_campaign()
	game.ensure_roster(Levels.LEVELS[0])  # names the squad; units come later
	var soldier: Dictionary = game.roster[0]
	var id := int(soldier.id)
	game.mark_wounded(id)
	_check(bool(game.soldier_by_id(id).wounded), "marked wounded")
	game.save()
	game.mark_wounded(id)  # no-op refresh, then wipe and reload
	game.roster = []
	_check(game.load_save(), "the save loads back")
	_check(bool(game.soldier_by_id(id).get("wounded", false)),
			"and the wound came back a bool")

	print("\n[2] a wounded soldier deploys a point short, at any level")
	var fresh: Node2D = unit_script.new()
	fresh.setup(int(game.soldier_by_id(id).kind), Vector2i(1, 1))
	var whole_hp: int = fresh.max_hp
	var hurt: Node2D = unit_script.new()
	hurt.setup(int(game.soldier_by_id(id).kind), Vector2i(1, 1))
	hurt.apply_progression(game.soldier_by_id(id))
	_check(hurt.max_hp == whole_hp - 1,
			"a scout: %d against the whole %d" % [hurt.max_hp, whole_hp])
	var leveled: Dictionary = game.soldier_by_id(id).duplicate(true)
	leveled.level = 20
	var vet: Node2D = unit_script.new()
	vet.setup(int(leveled.kind), Vector2i(1, 1))
	vet.apply_progression(leveled)
	# Level 20 has earned +9 max HP (one per odd level), and the wound still
	# costs exactly one point off that taller top.
	_check(vet.max_hp == whole_hp + 9 - 1,
			"a level 20: still exactly one point off the top (%d)" % vet.max_hp)
	_check(vet.hp == vet.max_hp, "and he deploys at his (reduced) full")

	print("\n[3] sitting out heals; fighting does not")
	game.begin_mission()
	game.mission_fielded.append(id)
	game.commit_mission()
	_check(bool(game.soldier_by_id(id).wounded),
			"he fought this one, so the wound stands")
	game.begin_mission()
	# fielded stays empty: he sat it out
	game.commit_mission()
	_check(not bool(game.soldier_by_id(id).wounded),
			"a mission on the bench and he is whole")

	print("\n[4] the garrison clears the ledger outright")
	game.mark_wounded(id)
	var second_id := int((game.roster[1] as Dictionary).id)
	game.mark_wounded(second_id)
	# Walk the campaign to the last mission of the operation, then advance.
	game.current_level = int((game.operation().missions as Array).back())
	game.advance_mission()
	_check(not game.in_the_field, "the operation ended at home")
	var still := 0
	for s: Dictionary in game.roster:
		if bool(s.get("wounded", false)):
			still += 1
	_check(still == 0, "and nobody is on the wounded list")

	print("\n[5] a v7 save climbs to nobody-wounded")
	game.new_campaign()
	game.ensure_roster(Levels.LEVELS[0])
	game.save()
	var raw := FileAccess.open(SAVE_PATH, FileAccess.READ).get_as_text()
	var payload: Dictionary = JSON.parse_string(raw)
	payload["version"] = 7
	for entry: Dictionary in payload.roster:
		entry.erase("wounded")
	var out := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	out.store_string(JSON.stringify(payload))
	out.close()
	_check(game.load_save(), "the doctored v7 loads")
	var any := false
	for s: Dictionary in game.roster:
		if bool(s.get("wounded", false)):
			any = true
	_check(not any, "and it climbed the ladder to nobody-wounded")

	game.delete_save()
	_restore()
	print("\nRESULT: ", "FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)
