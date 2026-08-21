extends SceneTree

## The front door, pinned.
##
## Five things, and the first is the one that will actually rot:
##   1. new_campaign() resets EVERY field a campaign carries - asserted by
##      comparing the file it writes against the file a never-played campaign
##      writes, key by key, so a field added later and forgotten in
##      new_campaign() fails here instead of haunting the next campaign
##   2. it re-mints the seed, because a new campaign fights different dice
##   3. it refuses when saving is locked, rather than wiping memory it cannot
##      replace on disk
##   4. campaign_summary() is what the menu shows, and is empty when there is
##      nothing to continue
##   5. the notebook renders: grouped by settlement, tallied, and readable with
##      no campaign at all
##   6. Continue is offered only when there is something to continue
##
## The real save is backed up in _init() before the Game autoload can touch it,
## the way tools/test_progression.gd does.
##
## Run: godot --headless --path . -s tools/test_menu.gd

const SAVE_PATH := "user://campaign.json"
const BACKUP_PATH := "user://campaign.json.menu-test-backup"

# The one key that is SUPPOSED to differ between two fresh campaigns.
const EXPECTED_TO_DIFFER := ["campaign_seed"]

var _failed := false
var _had_save := false
var _game_script: GDScript = null


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


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _run() -> void:
	await process_frame
	_game_script = load("res://scripts/Game.gd") as GDScript

	_test_new_campaign_resets_everything()
	_test_lock_refuses()
	_test_summary()
	await _test_notebook_screen()
	await _test_button_state()

	_restore()
	print("\nRESULT: ", "FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


# --- 1 & 2. nothing survives a new campaign ---------------------------------

func _test_new_campaign_resets_everything() -> void:
	print("\n[1] a new campaign keeps nothing from the old one")

	# What a campaign that has never been played writes.
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	var pristine: Node = _game_script.new()
	pristine.campaign_seed = pristine._mint_campaign_seed()
	pristine.save()
	var fresh_payload := _read_json(SAVE_PATH)
	_check(not fresh_payload.is_empty(), "a fresh campaign writes a save")
	pristine.free()

	# A campaign that has been everywhere and done everything.
	var dirty: Node = _game_script.new()
	dirty.current_operation = 1
	dirty.current_level = 5
	dirty.in_the_field = true
	dirty.frags = 4
	dirty.smokes = 0
	dirty.mission_attempts = 7
	dirty.alliance_strain = 61
	dirty.district_standing = {"Kessit": 12, "Bhorra Low": 3}
	dirty.notebook = [{"level": 2, "name": "Kesh Varr", "age": 33,
			"settlement": "Kessit", "fate": "killed"}]
	dirty.pending_promotions = [{"id": 1, "rank": 2}]
	dirty.roster = [{"id": 1, "surname": "ODUYA", "kind": 0, "xp": 40,
			"rank": 4, "perks": ["sprinter"], "alive": false}]
	dirty._next_id = 9
	# A bare .new() never runs the autoload's _ready(), so mint one by hand -
	# otherwise old_seed is 0 and "the seed changed" would pass for free.
	dirty.campaign_seed = dirty._mint_campaign_seed()
	dirty.save()
	var old_seed: int = dirty.campaign_seed

	_check(dirty.new_campaign(), "new_campaign() reports it replaced the campaign")
	var after := _read_json(SAVE_PATH)

	# The assertion that matters: same shape as a never-played campaign, key by
	# key, over the payload's OWN key list - so a field added to save() later
	# and forgotten in new_campaign() is caught here.
	var stale: Array[String] = []
	for key: String in fresh_payload:
		if EXPECTED_TO_DIFFER.has(key):
			continue
		if str(after.get(key, "<missing>")) != str(fresh_payload[key]):
			stale.append("%s: %s (fresh: %s)"
					% [key, after.get(key, "<missing>"), fresh_payload[key]])
	_check(stale.is_empty(),
			"every saved field is back where a fresh campaign leaves it (%s)"
			% [stale])
	_check(after.keys().size() == fresh_payload.keys().size(),
			"and the payload has the same %d keys" % fresh_payload.keys().size())

	print("\n[2] and it is a different campaign")
	_check(int(after.get("campaign_seed", 0)) != old_seed,
			"the seed was re-minted (%s was %s)"
			% [after.get("campaign_seed", "?"), old_seed])
	_check(int(after.get("campaign_seed", 0)) != 0,
			"and is never 0, which is the not-minted sentinel")
	_check(dirty.notebook.is_empty() and dirty.roster.is_empty()
			and dirty.district_standing.is_empty(),
			"the in-memory autoload was wiped too, not just the file")
	dirty.free()


# --- 3. a locked save is not wiped ------------------------------------------

func _test_lock_refuses() -> void:
	print("\n[3] a save from a newer build is refused rather than replaced")
	var g: Node = _game_script.new()
	g.notebook = [{"level": 0, "name": "Someone", "age": 30,
			"settlement": "Kessit", "fate": "killed"}]
	g._save_locked = true
	_check(not g.new_campaign(), "new_campaign() refuses")
	_check(g.notebook.size() == 1,
			"and leaves the campaign in memory alone, since it cannot rewrite the file")
	g.free()


# --- 4. what the menu prints ------------------------------------------------

func _test_summary() -> void:
	print("\n[4] the status line")
	var g: Node = _game_script.new()
	g.roster = []
	_check(g.campaign_summary().is_empty(),
			"empty with no roster, so the menu knows there is nothing to continue")
	g.roster = [
		{"id": 1, "surname": "A", "kind": 0, "xp": 0, "rank": 0, "perks": [], "alive": true},
		{"id": 2, "surname": "B", "kind": 0, "xp": 0, "rank": 0, "perks": [], "alive": true},
		{"id": 3, "surname": "C", "kind": 0, "xp": 0, "rank": 0, "perks": [], "alive": false},
	]
	g.current_level = 0
	g.current_operation = 0
	var summary: String = g.campaign_summary()
	print("        %s" % summary)
	_check(summary.contains("OPERATION DRY WELL") and summary.contains("2 SOLDIERS"),
			"names the operation and counts only the living")
	g.free()


# --- 5. the notebook screen -------------------------------------------------

func _test_notebook_screen() -> void:
	print("\n[5] the notebook renders")
	var game: Node = root.get_node("/root/Game")
	game.notebook = []
	game.district_standing = {}
	# Cleared for the same reason the two above are, and it was the one piece of
	# global state this test forgot: STILL OUT THERE is driven by
	# Game.adversaries, so without this the "no empty heading" check below is
	# really asking whether the DEVELOPER'S campaign has ever let anybody escape.
	# It passes on a fresh machine and fails on any machine that has played the
	# game, which is the worst way for a test to fail - it looks like whatever
	# you changed most recently.
	game.adversaries = []
	# Same isolation rule, learned the hard way above: BOUNTIES SETTLED is
	# driven by this list, so a developer campaign that has hunted somebody
	# would otherwise leak a heading into the empty-page check.
	game.bounty_outcomes = []
	var menu: Node = (load("res://scenes/MainMenu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	await process_frame

	var empty_text: String = menu._notebook_text()
	_check(empty_text.contains("fills as the campaign meets people"),
			"an empty notebook explains itself rather than showing a blank page")

	game.notebook = [
		{"level": 0, "name": "Wen Ulmet", "age": 46,
				"settlement": "Bhorra Low", "fate": "killed"},
		{"level": 0, "name": "Ossa Torren", "age": 35,
				"settlement": "Bhorra Low", "fate": "surrendered"},
		{"level": 4, "name": "Tammar Falk", "age": 35,
				"settlement": "Kessit", "fate": "escaped"},
		# A save written against a longer level table than this build has.
		{"level": 99, "name": "Bel Noss", "age": 22,
				"settlement": "Kessit", "fate": "killed"},
	]
	game.set_standing("Kessit", 31)
	game.alliance_strain = 44
	var text: String = menu._notebook_text()
	print("\n%s\n" % text)

	_check(text.contains("BHORRA LOW") and text.contains("KESSIT"),
			"grouped by settlement")
	_check(text.contains("Wen Ulmet, 46") and text.contains("DRY WASH"),
			"each line carries the person and the mission")
	_check(text.contains("2 killed") and text.contains("1 surrendered")
			and text.contains("1 escaped"),
			"the tally counts every fate, not just the dead")
	_check(text.contains("standing here is 31"),
			"the district's own standing sits with its own dead")
	_check(text.contains("ALLIANCE STRAIN  44"), "and the theater's number is on it")
	_check(text.contains("AN EARLIER MISSION"),
			"a mission index this build no longer has degrades instead of crashing")
	_check(menu._notebook_lead().contains("4 names"), "the lead counts them")
	_check(not text.contains("STILL OUT THERE"),
			"with nobody still alive, the page does not offer an empty heading")
	_check(not text.contains("BOUNTIES SETTLED"),
			"...and no empty bounty ledger either")

	# The settled bounties, rendered. One with a hunter still on the roster,
	# one whose hunter_id resolves to nobody - both lines must hold.
	game.roster = [{"id": 41, "surname": "Vane", "kind": 10, "xp": 0,
			"rank": 2, "perks": [], "alive": true, "presence": 1, "guile": 2}]
	game.bounty_outcomes = [
		{"id": 7, "name": "Hesh Korrin", "outcome": "informant", "hunter_id": 41},
		{"id": 8, "name": "Tammar Falk", "outcome": "killed", "hunter_id": 999},
	]
	var settled: String = menu._notebook_text()
	_check(settled.contains("BOUNTIES SETTLED  -  2"),
			"settled bounties get a ledger with a count")
	_check(settled.contains("Hesh Korrin  -  turned informant"),
			"...saying what was done")
	_check(settled.contains("Vane"),
			"...and who did it, when the roster still knows them")
	_check(settled.contains("Tammar Falk  -  shot")
			and not settled.contains("999"),
			"...while an unresolvable hunter is simply omitted")
	game.bounty_outcomes = []
	game.roster = []

	# The other list: the ones who are still out there to be met again. The
	# settlement listing above is the document - everyone, whatever became of
	# them - and this is the shorter one that matters, because these people can
	# walk back onto a board.
	game.adversaries = [
		{"id": 1, "name": "Tammar Falk", "age": 35, "settlement": "Kessit",
				"grievance": "the well", "kind": 3, "survivals": 1,
				"injuries": 0, "state": "escaped", "edge": "north",
				"history": [{"level": 0, "fate": "escaped"}], "last_level": 0},
		{"id": 2, "name": "Hesh Korrin", "age": 28, "settlement": "Kessit",
				"grievance": "the well", "kind": 6, "survivals": 3,
				"injuries": 2, "state": "injured", "edge": "south",
				"history": [{"level": 0, "fate": "escaped"},
						{"level": 1, "fate": "injured"},
						{"level": 3, "fate": "injured"}], "last_level": 3},
	]
	var living: String = menu._notebook_text()
	print("
%s
" % living)
	_check(living.contains("STILL OUT THERE  -  2"),
			"the living are listed and counted")
	_check(living.contains("Hesh Korrin") and living.contains("Tammar Falk"),
			"...by name")
	_check(living.contains("ran at DRY WASH") and living.contains("left for dead"),
			"...with what happened to them, mission by mission")
	_check(living.contains("carrying 2 wounds"),
			"...and what they are carrying")
	# Most-storied first, because that is the order they matter in and the same
	# order a mission is offered them back in. Compared WITHIN the section:
	# both names also appear in the settlement listing above, so a bare find()
	# on the whole page answers about the document rather than about this list.
	var section: String = living.substr(living.find("STILL OUT THERE"))
	_check(section.find("Hesh Korrin") < section.find("Tammar Falk"),
			"the man met three times is listed above the man met once")
	_check(menu._notebook_lead().contains("2 of them still out there"),
			"and the lead says how many are still alive to meet")
	game.adversaries = []

	menu.queue_free()
	await process_frame


# --- 6. the buttons say what is true ----------------------------------------

func _test_button_state() -> void:
	print("\n[6] Continue is offered only when there is something to continue")
	var game: Node = root.get_node("/root/Game")

	# Nothing to continue: no roster, whatever is on disk.
	game.roster = []
	var bare: Node = (load("res://scenes/MainMenu.tscn") as PackedScene).instantiate()
	root.add_child(bare)
	await process_frame
	_check(bare.continue_button.disabled,
			"with no roster the button is disabled")
	_check(str(bare.status_label.text).contains("No campaign in progress"),
			"and the status line says so")
	bare.queue_free()
	await process_frame

	# Something to continue.
	game.roster = [{"id": 1, "surname": "ODUYA", "kind": 0, "xp": 0, "rank": 0,
			"perks": [], "alive": true}]
	game.current_level = 0
	game.current_operation = 0
	game.save()
	var loaded: Node = (load("res://scenes/MainMenu.tscn") as PackedScene).instantiate()
	root.add_child(loaded)
	await process_frame
	_check(not loaded.continue_button.disabled, "with a roster it is offered")
	_check(str(loaded.status_label.text).contains("OPERATION"),
			"and the status line names the operation (%s)" % loaded.status_label.text)
	# The three scenes the menu can reach must all exist, or a button is a
	# dead end that only fails when a player presses it.
	for path: String in [game.MENU_SCENE, game.CAMP_SCENE, game.BATTLE_SCENE]:
		_check(ResourceLoader.exists(path), "%s exists" % path)
	loaded.queue_free()
	await process_frame
