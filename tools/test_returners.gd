extends SceneTree

## The ones who ran, and came back.
##
## A goblin who breaks with nobody covering him routs for the map rim, and
## reaching it is an escape rather than a kill. THE ROLL has always written that
## down; now the notebook keeps enough of it to put him back on a later board,
## carrying the name he had when he ran.
##
## Six things are checked:
##   1. selection is a pure function of (campaign seed, mission, who he was) -
##      the same answer every time, a different answer for a different campaign,
##      and never a draw from any generator
##   2. who is eligible: escaped only, from an EARLIER mission only, never twice,
##      and never a pre-v5 entry that cannot say what he was carrying
##   3. the notebook survives a save round trip with the three new fields, and a
##      v4 save climbs to v5 without inventing anybody
##   4. a hand-edited save cannot put an arbitrary Kind on the board
##   5. a scheduled arrival actually lands, on its turn, off the rim it fled by,
##      steadier than it was and known to the enemy turn
##   6. a cleared board does not end the mission while somebody is still walking
##      toward it
##
## Any real save is backed up and restored, so this is safe to run on a machine
## someone is actually playing on.
##
## Run: godot --headless --path . -s tools/test_returners.gd

const KIND_GOBLIN := 3
const KIND_GOBLIN_SMG := 4
const KIND_GOBLIN_REVOLVER := 6

var _failed := false
var _backup := ""
var _had_save := false
const SAVE_PATH := "user://campaign.json"


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    %s" % label)
	else:
		printerr("  FAIL  %s" % label)
		_failed = true


func _init() -> void:
	_run()


## One notebook row, the shape Game.add_to_notebook writes.
func _row(level: int, ordinal: int, fate := "escaped", kind := KIND_GOBLIN,
		edge := "north", name := "Vekh Marr") -> Dictionary:
	return {
		"level": level, "name": name, "age": 30, "settlement": "Kessit",
		"grievance": "the well", "fate": fate,
		"kind": kind, "ordinal": ordinal, "edge": edge,
	}


func _run() -> void:
	await process_frame  # let the autoloads finish _ready()

	# Taken FIRST, and restored by _finish(), which every exit goes through.
	# The earlier draft restored on the last statement of _run and wrote the
	# real campaign.json in between, so an engine abort mid-run left harness
	# data in a player's save - which happened twice while this was being
	# reviewed. A harness that can eat a campaign is not worth its coverage.
	if FileAccess.file_exists(SAVE_PATH):
		var bf := FileAccess.open(SAVE_PATH, FileAccess.READ)
		_backup = bf.get_as_text()
		bf.close()
		_had_save = true
		print("backed up existing save (%d bytes)" % _backup.length())

	var game: Node = root.get_node("/root/Game")
	_test_determinism(game)
	_test_eligibility(game)
	_test_round_trip(game)
	_test_hostile_save(game)
	await _test_arrival()
	_finish()


## Put the player's campaign back and go. Called from every exit.
func _finish() -> void:
	if _had_save:
		var rf := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		rf.store_string(_backup)
		rf.close()
		print("
restored the original save")
	elif FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	print("
RESULT: ", "FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


# --- 1. the same campaign always sends back the same people ------------------

func _test_determinism(game: Node) -> void:
	print("\n[1] who comes back is decided by a hash, not by a die")
	game.campaign_seed = 4242
	game.returned = []
	game.notebook = []
	for i in 40:
		game.notebook.append(_row(0, i))

	var first: Array = game.returners_from(4)
	var second: Array = game.returners_from(4)
	_check(first.size() == second.size(),
			"asked twice, the same mission returns the same count (%d)" % first.size())
	var same := true
	for i in first.size():
		if int(first[i].ordinal) != int(second[i].ordinal):
			same = false
	_check(same, "...and the same people, in the same order")

	# Reloading a save must not reshuffle. Nothing here touches an RNG, so the
	# strongest form of that claim is: perturb every generator and ask again.
	for i in 50:
		randi()
	var third: Array = game.returners_from(4)
	_check(third.size() == first.size(),
			"...and still does after 50 draws from the global RNG")

	# A different campaign is a different war.
	game.campaign_seed = 9001
	var other: Array = game.returners_from(4)
	var differs := other.size() != first.size()
	if not differs:
		for i in first.size():
			if int(other[i].ordinal) != int(first[i].ordinal):
				differs = true
	_check(differs, "a different campaign seed sends back different people")

	# And a different mission of the SAME campaign is a different roll.
	game.campaign_seed = 4242
	var later: Array = game.returners_from(5)
	var moved := later.size() != first.size()
	if not moved:
		for i in first.size():
			if int(later[i].ordinal) != int(first[i].ordinal):
				moved = true
	_check(moved, "...and a different mission of the same campaign does too")

	# It has to actually fire. A rule nobody ever meets is not a rule.
	_check(not first.is_empty(),
			"out of 40 escapees somebody comes back (%d of them)" % first.size())


# --- 2. who is allowed back ---------------------------------------------------

func _test_eligibility(game: Node) -> void:
	print("\n[2] who is eligible")
	game.campaign_seed = 4242
	game.returned = []
	game.notebook = [
		_row(0, 0, "killed"),
		_row(0, 1, "surrendered"),
		_row(6, 2),                              # a later mission than the one asked
		_row(4, 3),                              # the mission being played
		_row(0, 4, "escaped", -1),               # pre-v5: no kind on record
		{"level": 0, "name": "Old Row", "age": 4, "settlement": "Kessit",
				"fate": "escaped"},              # pre-v5 entirely
	]
	var out: Array = game.returners_from(4)
	_check(out.is_empty(),
			"nobody who was killed, surrendered, is from this mission or later, "
			+ "or predates v5 (%d came back)" % out.size())

	# Now somebody who does qualify, and who must stop qualifying once used.
	game.notebook.append(_row(1, 7))
	var eligible := false
	for lvl in range(2, 7):
		if not game.returners_from(lvl).is_empty():
			eligible = true
			_check(true, "an escapee from mission 2 is eligible on mission %d" % (lvl + 1))
			game.mark_returned(game.returners_from(lvl))
			_check(game.returners_from(lvl).is_empty(),
					"...and is not, once he has been sent back")
			break
	_check(eligible, "the qualifying escapee is reachable on some later mission")
	_check(game.returned.size() == 1 and str(game.returned[0]) == "1:7",
			"the key written down is level:ordinal (%s)" % [game.returned])


# --- 3. the save carries it ---------------------------------------------------

func _test_round_trip(game: Node) -> void:
	print("\n[3] the notebook survives the save, and a v4 save climbs")
	# A roster of its own: save() refuses to write a campaign with none, and the
	# earlier draft only passed because the machine happened to have a real
	# campaign.json already. On a clean checkout it failed and then crashed on
	# an empty array.
	game.new_campaign()
	# ...and a body on it: load_save refuses a campaign with an empty roster, so
	# a bare new_campaign() writes a file that will not read back.
	game.roster = [{"id": 1, "surname": "Akai", "kind": 9, "xp": 0, "rank": 0,
			"perks": [] as Array, "alive": true}]
	game._next_id = 2
	game.campaign_seed = 4242
	game.notebook = [_row(1, 7, "escaped", KIND_GOBLIN_REVOLVER, "south", "Ilsa Vane")]
	game.returned = ["0:3"]
	game.save()

	var g2: Node = (load("res://scripts/Game.gd") as GDScript).new()
	root.add_child(g2)
	_check(g2.load_save(), "a saved campaign loads")
	_check(g2.notebook.size() == 1, "the notebook came back (%d)" % g2.notebook.size())
	var row: Dictionary = g2.notebook[0]
	_check(int(row.get("kind", -1)) == KIND_GOBLIN_REVOLVER,
			"...carrying what he was holding (kind %d)" % int(row.get("kind", -1)))
	_check(int(row.get("ordinal", -1)) == 7,
			"...which body he was (ordinal %d)" % int(row.get("ordinal", -1)))
	_check(str(row.get("edge", "")) == "south",
			"...and which way he went (%s)" % str(row.get("edge", "")))
	_check(str(row.get("name", "")) == "Ilsa Vane",
			"...under the name he had (%s)" % str(row.get("name", "")))
	_check(g2.returned.size() == 1 and str(g2.returned[0]) == "0:3",
			"and the already-sent-back list survives (%s)" % [g2.returned])

	# A v4 save has no `returned` and no new notebook fields. It must climb
	# without inventing anybody: there is no honest way to know what an old
	# escapee was carrying.
	var raw := FileAccess.open(game.SAVE_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(raw.get_as_text())
	var payload: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	raw.close()
	payload["version"] = 4
	payload.erase("returned")
	payload["notebook"] = [{"level": 0, "name": "Old Row", "age": 40,
			"settlement": "Kessit", "fate": "escaped"}]
	var wf := FileAccess.open(game.SAVE_PATH, FileAccess.WRITE)
	wf.store_string(JSON.stringify(payload))
	wf.close()

	var g3: Node = (load("res://scripts/Game.gd") as GDScript).new()
	root.add_child(g3)
	_check(g3.load_save(), "a v4 save loads")
	_check(g3.returned.is_empty(), "...with nobody yet sent back")
	_check(g3.notebook.size() == 1 and int(g3.notebook[0].get("kind", -1)) == -1,
			"...and its escapee kept, but unrecoverable (kind %d)"
			% int(g3.notebook[0].get("kind", -1)))
	var climbed: Array = g3.returners_from(6)
	_check(climbed.is_empty(), "...so he is never put on a board")
	g2.queue_free()
	g3.queue_free()


# --- 4. the notebook now drives a spawner, so it is no longer trusted ---------

func _test_hostile_save(game: Node) -> void:
	print("\n[4] a hand-edited save cannot choose a Unit.Kind")
	var poisoned: Array = game._read_notebook([
		{"level": 0, "name": "X", "fate": "escaped", "kind": 9999, "ordinal": 1},
		{"level": 0, "name": "Y", "fate": "escaped", "kind": -40, "ordinal": 2},
		"not a dictionary at all",
		# The ones a bare range check waves through, and the reason this section
		# exists at all: 9 is HERO and 8 is CIVILIAN, both inside Unit.Kind and
		# both put on TEAM_SCOUT by setup(). A save saying kind 9 walked a
		# second Rodar Akai onto the rim, on the player's own side, where he
		# counted toward the wipe condition.
		{"level": 0, "name": "Ghost Akai", "fate": "escaped", "kind": 9, "ordinal": 4},
		{"level": 0, "name": "Ghost Civ", "fate": "escaped", "kind": 8, "ordinal": 5},
		{"level": 0, "name": "Z", "fate": "escaped", "kind": KIND_GOBLIN_SMG,
				"ordinal": 3},
	])
	_check(poisoned.size() == 5, "junk rows are dropped (%d kept)" % poisoned.size())
	_check(int(poisoned[0].kind) == -1 and int(poisoned[1].kind) == -1,
			"an out-of-range kind is refused rather than passed to setup()")
	_check(int(poisoned[2].kind) == -1 and int(poisoned[3].kind) == -1,
			"...and so is an in-range kind that is not one of the Thirst "
			+ "(HERO %d, CIVILIAN %d)" % [int(poisoned[2].kind), int(poisoned[3].kind)])
	_check(int(poisoned[4].kind) == KIND_GOBLIN_SMG,
			"a real goblin is kept (%d)" % int(poisoned[4].kind))


# --- 5 and 6. the arrival, through the real turn loop -------------------------

func _test_arrival() -> void:
	print("
[5] a returner lands, through end_player_turn and nothing else")
	var game: Node = root.get_node("/root/Game")
	game.new_campaign()
	game.campaign_seed = 4242
	# THE SURVEY CAMP: index 6, the last mission, and one of only two whose
	# objective is `eliminate`. It has to be an eliminate map for section 6 to
	# mean anything - on a destroy map _all_objectives_complete() stays false
	# with the board cleared, so a test of "the mission ends" there proves
	# nothing, which is exactly how the first version of this passed while the
	# rule it checked was deleted.
	game.current_level = 6
	game.current_operation = 1
	game.notebook = []
	game.returned = []
	# Conscripts, deliberately: their starting morale is 60, so the assertion
	# that a returner arrives at Rules.returner_morale() can actually fail. The
	# first version spawned a well-hand, whose plain default is already 100.
	for i in 30:
		game.notebook.append(_row(0, i, "escaped", KIND_GOBLIN_REVOLVER, "south",
				"Runner %d" % i))

	var battle: Node = (load("res://scenes/Battle.tscn") as PackedScene).instantiate()
	root.add_child(battle)
	await process_frame
	await process_frame

	var due_turns: Array = battle._returners_due.keys()
	_check(not due_turns.is_empty(), "somebody is scheduled (turns %s)" % [due_turns])
	if due_turns.is_empty():
		battle.queue_free()
		_finish()
		return
	var first_turn: int = 99
	for t: int in due_turns:
		first_turn = mini(first_turn, int(t))

	# Drive the REAL loop. Nothing here calls _land_returners by hand: deleting
	# its one production call is precisely the regression this has to catch, and
	# the earlier version invoked it directly, so the feature could be cut out
	# of the game entirely with every harness still green.
	# Watch the conscripts across those turns. THE SURVEY CAMP fields three
	# (novice_spawns), and their whole point is that they start at 60 - so if
	# Rules.morale_recovered is handed MORALE_MAX instead of their own ceiling,
	# +5 a turn walks them back to 100 and the class trait quietly evaporates.
	# Asserting the ceiling FIELD is not enough: that is set at spawn and says
	# nothing about whether the recovery path reads it.
	var watched: Array[Node2D] = []
	for u in battle.living_units(1):
		if int(u.kind) == KIND_GOBLIN_REVOLVER:
			watched.append(u)
	_check(not watched.is_empty(), "the map fields conscripts to watch (%d)"
			% watched.size())
	# Every one of them, not just the first: the `break` that used to be here
	# left `ceilings` one entry long against three watched units, so the
	# comparison below indexed out of range and killed the coroutine silently -
	# taking the rest of this section with it, and reporting PASS.
	var ceilings: Array[int] = []
	var wrong_ceiling: Array[String] = []
	for u: Node2D in watched:
		ceilings.append(int(u.morale_ceiling))
		if int(u.morale_ceiling) != 60:
			wrong_ceiling.append(str(int(u.morale_ceiling)))
	_check(wrong_ceiling.is_empty(),
			"every conscript's ceiling is his own 60, not 100 (%s)"
			% [wrong_ceiling])

	var before: int = battle.living_units(1).size()
	var guard := 0
	# `<=`, not `<`: _land_returners runs at the top of end_player_turn, before
	# turn_number is incremented, so the arrival happens during the call that
	# BEGINS on the due turn. Stopping at `<` leaves the clock sitting on it
	# with the call never made - which is how the first run of this reported
	# "13 -> 13 units" and was right to.
	while battle.turn_number <= first_turn and guard < 12:
		guard += 1
		battle.player_turn_ready_msec = 0   # skip the double-click grace
		battle.state = battle.State.PLAYER_TURN
		battle.enemy_turn_running = false
		await battle.end_player_turn()
	_check(battle.turn_number >= first_turn,
			"the clock reached the arrival turn (%d)" % battle.turn_number)

	var over_ceiling: Array[String] = []
	for i in watched.size():
		var u: Node2D = watched[i]
		if is_instance_valid(u) and int(u.morale) > ceilings[i]:
			over_ceiling.append("%d > %d" % [int(u.morale), ceilings[i]])
	_check(over_ceiling.is_empty(),
			"and after %d quiet turns no conscript has climbed past his own "
			% battle.turn_number + "morale (%s)" % [over_ceiling])

	var landed: Array = []
	for u in battle.living_units(1):
		if bool(u.returned):
			landed.append(u)
	_check(not landed.is_empty(),
			"he is on the board, put there by the turn loop (%d -> %d units)"
			% [before, battle.living_units(1).size()])
	if landed.is_empty():
		battle.queue_free()
		_finish()
		return
	var him: Node2D = landed[0]

	_check(int(him.morale) == 100 and int(him.morale) > 60,
			"steadier than the conscript he was: %d, against a fresh one's 60"
			% int(him.morale))
	_check(int(him.morale_ceiling) == int(him.morale),
			"...and his quiet turns cannot lift him past it (%d)"
			% int(him.morale_ceiling))
	_check(str(him.identity.get("name", "")).begins_with("Runner"),
			"under the name he ran with (%s)" % str(him.identity.get("name", "")))
	# Asserted against the ARRIVAL, not against where he is standing now: he
	# acts on the turn he lands, so by the time this runs the AI has already
	# walked him inland. The first version of this checked him.cell and read
	# (12, 7) - a perfectly correct landing followed by a perfectly correct
	# move. "south" is recorded rather than "north" on purpose, too: _edge_of
	# answers "north" for any y == 0 and every arrival is a corner, so an
	# assertion of "north" is satisfied by a landing on the wrong side of the
	# map entirely.
	var arrival: Dictionary = battle._returners_landed[0]
	var at: Vector2i = arrival.get("arrived_at", Vector2i.ZERO)
	_check(at.y == battle.board.size.y - 1,
			"came in off the SOUTH rim he fled by (%s)" % [at])
	_check(int(arrival.get("arrived_on", -1)) == first_turn,
			"on the turn he was due (%d)" % int(arrival.get("arrived_on", -1)))
	_check(battle.board.is_walkable(at), "onto ground he can stand on")
	var closest := 99
	for scout in battle.living_soldiers(0):
		closest = mini(closest, Board.manhattan(at, scout.cell))
	_check(closest >= battle.ARRIVAL_STANDOFF,
			"outside his own reach, so he had to close first (%d tiles)" % closest)
	# And close enough to matter. The failure this pins is not hypothetical: two
	# earlier versions of the rule put him 16 tiles away in the Thirst's own
	# corner, which passes every other assertion here and is not an ambush.
	_check(closest <= battle.ARRIVAL_STANDOFF + 3,
			"...but behind the squad rather than across the map (%d tiles)" % closest)

	print("
[6] and nobody arrives at a contact that is already over")
	# Clear the board on an eliminate map: the mission must commit immediately,
	# and the second scheduled arrival must never happen.
	var still_due: int = battle._returners_due.size()
	_check(still_due > 0, "a second arrival is still on the books (%d)" % still_due)
	for goblin in battle.living_units(1):
		goblin.hp = 0
		goblin.hide()
	battle.state = battle.State.PLAYER_TURN
	_check(battle.check_game_over(),
			"an empty eliminate map ends the mission on the spot")
	_check(battle.state == battle.State.GAME_OVER, "...and the state says so")
	var count_at_end: int = battle.living_units(1).size()
	battle.player_turn_ready_msec = 0
	await battle.end_player_turn()
	_check(battle.living_units(1).size() == count_at_end,
			"nobody walks onto a finished board (%d)" % battle.living_units(1).size())
	battle.free()
