extends SceneTree

## Who the camp will let you send.
##
## A bounty and a crossing each take one soldier and lend him two riflemen. The
## modal that picks him has two buttons, and for a long time it simply listed
## the first two people on the roster - which did not read as a bug, it read as
## a squad of two. Six of the eight could never be sent at all.
##
## Both pickers page now, the way the quartermaster's rack does. What is checked
## is the property that was broken: every living soldier can be reached, and the
## one the button names is the one the confirm sends.
##
## Any real save is backed up and restored, so this is safe to run on a machine
## someone is actually playing on.
##
## Run: godot --headless --path . -s tools/test_camp_pickers.gd

var _failed := false
var _backup := ""
var _had_save := false
var _pickers_run := 0
const SAVE_PATH := "user://campaign.json"


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    %s" % label)
	else:
		printerr("  FAIL  %s" % label)
		_failed = true


func _init() -> void:
	_run()


func _run() -> void:
	await process_frame
	if FileAccess.file_exists(SAVE_PATH):
		var bf := FileAccess.open(SAVE_PATH, FileAccess.READ)
		_backup = bf.get_as_text()
		bf.close()
		_had_save = true
	var game: Node = root.get_node_or_null("/root/Game")
	if game == null:
		_check(false, "the Game autoload is up (it is not - nothing can run)")
		_finish()
		return
	game.new_campaign()
	# ensure_roster reads the mission's slot counts to decide who the campaign
	# needs; any shipped level answers that the same way.
	game.ensure_roster(Levels.LEVELS[0])
	var alive := 0
	for soldier: Dictionary in game.roster:
		if bool(soldier.get("alive", false)):
			alive += 1
	_check(alive > 2, "the roster is deeper than the two the modal can show (%d)" % alive)

	var camp: Node = (load("res://scenes/Camp.tscn") as PackedScene).instantiate()
	root.add_child(camp)
	await process_frame
	await process_frame

	await _test_picker(camp, game, alive, "bounty")
	await _test_picker(camp, game, alive, "ratline")
	# Stated rather than assumed. If a picker cannot be driven at all - a
	# changed signature, an error inside the walk - the checks above are simply
	# never reached, and a harness that prints PASS because it did nothing is
	# worse than no harness.
	_check(_pickers_run == 2,
			"both pickers were actually exercised (%d of 2)" % _pickers_run)

	camp.queue_free()
	await process_frame
	_finish()


## Page the whole way round and collect who was offered. The cursor is what the
## confirm button reads, so the same walk proves both halves: that everybody can
## be reached, and that the name on the button is the name that would go.
func _test_picker(camp: Node, game: Node, alive: int, which: String) -> void:
	print("\n[%s] every living soldier can be sent" % which)
	var offer := {}
	if which == "bounty":
		offer = {"id": 1, "name": "Test Target", "settlement": "Kessit",
				"place": "THE SUMP", "survivals": 1, "grievance": "the well",
				"age": 30, "kind": 3, "injuries": 0}
	else:
		offer = {"ordinal": 0, "title": "crossing", "place": "SALT REACH",
				"where": "the low ford", "arch": 0}

	var seen := {}
	var named_on_button := {}
	for step in alive:
		if which == "bounty":
			camp._open_bounty_hunters(offer, step)
		else:
			camp._open_ratline_leaders(offer, step)
		var people: Array = camp._choice_args[1]
		var at: int = int(camp._choice_args[2])
		var marked: Dictionary = people[at]
		seen[int(marked.get("id", 0))] = true
		# The button must name the man under the cursor, or the list is a
		# decoration over a two-man pick again.
		if camp.choice_a.text.contains(game.soldier_label(marked)):
			named_on_button[int(marked.get("id", 0))] = true
		# ...and the body must list everybody, not just him.
		if step == 0:
			var listed := 0
			for soldier: Dictionary in game.roster:
				if bool(soldier.get("alive", false)) \
						and camp.modal_body.text.contains(game.soldier_label(soldier)):
					listed += 1
			_check(listed == alive,
					"the panel lists the whole roster (%d of %d)" % [listed, alive])
	_check(seen.size() == alive,
			"paging reaches every one of them (%d of %d)" % [seen.size(), alive])
	_check(named_on_button.size() == alive,
			"...and the send button names whoever is under the cursor (%d)"
			% named_on_button.size())
	# Wrapping, so the list is a ring rather than a dead end at the bottom.
	if which == "bounty":
		camp._open_bounty_hunters(offer, alive)
	else:
		camp._open_ratline_leaders(offer, alive)
	_check(int(camp._choice_args[2]) == 0, "paging past the last one wraps")
	camp._close_modal()
	_pickers_run += 1


func _finish() -> void:
	if _had_save:
		var rf := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		rf.store_string(_backup)
		rf.close()
		print("\nrestored the original save")
	elif FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	print("\nRESULT: ", "FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)
