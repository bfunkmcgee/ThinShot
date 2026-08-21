extends SceneTree

## The ones who ran, and came back.
##
## A goblin who breaks with nobody covering him routs for the map rim, and
## reaching it is an escape rather than a kill. THE ROLL has always written that
## down; now the notebook keeps enough of it to put him back on a later board,
## carrying the name he had when he ran.
##
## Seven things are checked:
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
##   7. a man who has got away twice gathers three who have got away once, the
##      band only forms when it can be filled, and which band forms is the same
##      hash-driven decision the individual return is
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


## One standing adversary, the shape Game.remember_survivor writes.
func _adv(id: int, last_level: int, state := "escaped", kind := KIND_GOBLIN,
		edge := "north", name := "Vekh Marr", survivals := 1,
		injuries := 0) -> Dictionary:
	return {
		"id": id, "name": name, "age": 30, "settlement": "Kessit",
		"grievance": "the well", "kind": kind, "survivals": survivals,
		"injuries": injuries, "state": state, "edge": edge,
		"history": [{"level": last_level, "fate": state}],
		"last_level": last_level,
	}


## One notebook row, still written by add_to_notebook as the document.
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
	_test_warbands(game)
	await _test_arrival()


## A man who has walked away twice can gather the ones who managed it once.
##
## Everything here is about SELECTION, which is Game's half: who is eligible to
## lead, who is eligible to follow, and the determinism the whole returner
## system is built on. Whether the four of them actually land together is
## _test_arrival's business.
func _test_warbands(game: Node) -> void:
	print("
[7] a warband forms around somebody who keeps getting away")
	var seeded := func(records: Array) -> void:
		game.adversaries = records.duplicate(true)
		game.campaign_seed = 20260821

	# Nobody experienced enough to lead: four men who each ran once is four
	# returners, not a warband. This is the case that must NOT fire, because it
	# is the common one for most of a campaign.
	seeded.call([_adv(1, 0, "escaped", KIND_GOBLIN, "north", "One", 1),
			_adv(2, 0, "escaped", KIND_GOBLIN, "north", "Two", 1),
			_adv(3, 0, "escaped", KIND_GOBLIN, "north", "Three", 1),
			_adv(4, 0, "escaped", KIND_GOBLIN, "north", "Four", 1)])
	var none_yet := true
	for level in range(1, 7):
		if not game.warband_for(level).is_empty():
			none_yet = false
	_check(none_yet, "four one-time escapees gather nobody - there is no leader")

	# A leader with too few followers does not form one either: the banner
	# promises a warband and the board has to deliver four.
	seeded.call([_adv(1, 0, "escaped", KIND_GOBLIN, "north", "Storied", 3),
			_adv(2, 0, "escaped", KIND_GOBLIN, "north", "Two", 1)])
	var short_handed := true
	for level in range(1, 7):
		if not game.warband_for(level).is_empty():
			short_handed = false
	_check(short_handed, "a leader with only one follower brings nobody")

	# The real thing: one man with three escapes, and enough people who have
	# managed one.
	var full := [_adv(1, 0, "escaped", KIND_GOBLIN, "north", "Storied", 3),
			_adv(2, 0, "escaped", KIND_GOBLIN, "south", "Two", 1),
			_adv(3, 0, "escaped", KIND_GOBLIN, "east", "Three", 2),
			_adv(4, 0, "escaped", KIND_GOBLIN, "west", "Four", 1),
			_adv(5, 0, "escaped", KIND_GOBLIN, "north", "Five", 1)]
	seeded.call(full)
	var formed := {}
	var found_level := -1
	for level in range(1, 7):
		var band: Dictionary = game.warband_for(level)
		if not band.is_empty():
			formed = band
			found_level = level
			break
	if formed.is_empty():
		_check(false, "expected a warband to form on some mission")
		return
	_check(true, "a warband forms on mission %d" % (found_level + 1))
	_check(int(formed.leader.get("survivals", 0))
			>= int(game.WARBAND_LEADER_SURVIVALS),
			"its leader has walked away at least %d times (%d)"
			% [int(game.WARBAND_LEADER_SURVIVALS),
					int(formed.leader.get("survivals", 0))])
	_check(str(formed.leader.get("name", "")) == "Storied",
			"and it is the most experienced man available who leads (%s)"
			% str(formed.leader.get("name", "")))
	_check(formed.members.size() == int(game.WARBAND_SIZE) - 1,
			"he brings %d others (%d)"
			% [int(game.WARBAND_SIZE) - 1, formed.members.size()])
	var leader_in_members := false
	var all_qualify := true
	for rec: Dictionary in formed.members:
		if int(rec.get("id", 0)) == int(formed.leader.get("id", 0)):
			leader_in_members = true
		if int(rec.get("survivals", 0)) < int(game.WARBAND_MEMBER_SURVIVALS):
			all_qualify = false
	_check(not leader_in_members, "...and is not counted among them")
	_check(all_qualify, "...every one of whom has got away at least once")

	# Determinism, which is the same contract adversaries_for is held to: a
	# reloaded mission has to field the same warband, and Battle's rules stream
	# must never be involved in deciding it.
	var again: Dictionary = game.warband_for(found_level)
	_check(int(again.get("leader", {}).get("id", -1))
			== int(formed.leader.get("id", 0)),
			"asking twice gives the same leader")
	game.campaign_seed = 777333
	var elsewhere := false
	for level in range(1, 7):
		var other: Dictionary = game.warband_for(level)
		if other.is_empty() or int(other.get("leader", {}).get("id", -1)) \
				!= int(formed.leader.get("id", 0)):
			elsewhere = true
	_check(elsewhere, "a different campaign does not get the same warband")

	# Same rule the individual return obeys: nobody comes back to the mission he
	# left, or to one already behind us.
	game.campaign_seed = 20260821
	game.adversaries = full.duplicate(true)
	for rec: Dictionary in game.adversaries:
		rec["last_level"] = 5
	var not_backwards := true
	for level in range(0, 6):
		if not game.warband_for(level).is_empty():
			not_backwards = false
	_check(not_backwards,
			"a band whose members all left on mission 6 does not appear before it")


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
	print("
[1] who comes back is decided by a hash, not by a die")
	game.campaign_seed = 4242
	game.adversaries = []
	for i in 40:
		game.adversaries.append(_adv(i + 1, 0))

	var first: Array = game.adversaries_for(4)
	var second: Array = game.adversaries_for(4)
	_check(first.size() == second.size(),
			"asked twice, the same mission returns the same count (%d)" % first.size())
	var same := true
	for i in first.size():
		if int(first[i].id) != int(second[i].id):
			same = false
	_check(same, "...and the same people, in the same order")

	for i in 50:
		randi()
	_check(game.adversaries_for(4).size() == first.size(),
			"...and still does after 50 draws from the global RNG")

	game.campaign_seed = 9001
	var other: Array = game.adversaries_for(4)
	var differs := other.size() != first.size()
	if not differs:
		for i in first.size():
			if int(other[i].id) != int(first[i].id):
				differs = true
	_check(differs, "a different campaign seed sends back different people")

	game.campaign_seed = 4242
	var later: Array = game.adversaries_for(5)
	var moved := later.size() != first.size()
	if not moved:
		for i in first.size():
			if int(later[i].id) != int(first[i].id):
				moved = true
	_check(moved, "...and a different mission of the same campaign does too")
	_check(not first.is_empty(),
			"out of 40 survivors somebody comes back (%d of them)" % first.size())

	# The storied come first, because Battle only takes the top few. Left
	# unsorted this returned them in the order they were first met, so the
	# earliest survivor crowded out every later one for the rest of the run.
	game.adversaries = [_adv(1, 0, "escaped", KIND_GOBLIN, "north", "Quiet", 1),
			_adv(2, 0, "injured", KIND_GOBLIN, "north", "Storied", 4)]
	var ordered: Array = game.adversaries_for(6)
	if ordered.size() == 2:
		_check(str(ordered[0].name) == "Storied",
				"the man with the most history is offered first (%s)"
				% str(ordered[0].name))
	else:
		_check(false, "expected both to be eligible (got %d)" % ordered.size())


# --- 2. who is allowed back ---------------------------------------------------

func _test_eligibility(game: Node) -> void:
	print("
[2] who is eligible")
	game.campaign_seed = 4242
	game.adversaries = [
		_adv(1, 6),                                    # a later mission
		_adv(2, 4),                                    # the mission being played
		_adv(3, 0, "escaped", -1),                     # nothing on record to rebuild
	]
	var out: Array = game.adversaries_for(4)
	_check(out.is_empty(),
			"nobody from this mission or later, and nobody unrebuildable (%d)"
			% out.size())

	# Somebody who does qualify, and who stops qualifying once he has been.
	game.adversaries = [_adv(7, 1)]
	var seen_on := -1
	for lvl in range(2, 7):
		if not game.adversaries_for(lvl).is_empty():
			seen_on = lvl
			break
	_check(seen_on > 0, "a survivor of mission 2 is eligible later (mission %d)"
			% (seen_on + 1))
	if seen_on > 0:
		# remember_survivor moves last_level forward, which is what stops the
		# same man queueing for every remaining mission.
		game.remember_survivor({"name": "Vekh Marr"}, KIND_GOBLIN, "escaped",
				seen_on, "north", 7)
		_check(game.adversaries_for(seen_on).is_empty(),
				"...and not for the mission he has just left")
		_check(int(game.adversaries[0].survivals) == 2,
				"...with another survival on his record (%d)"
				% int(game.adversaries[0].survivals))
		_check(game.adversaries[0].history.size() == 2,
				"...and another line in his history (%d)"
				% game.adversaries[0].history.size())


# --- 3. the save carries it ---------------------------------------------------

func _test_round_trip(game: Node) -> void:
	print("
[3] the roster survives the save, and a v5 save climbs")
	game.new_campaign()
	game.roster = [{"id": 1, "surname": "Akai", "kind": 9, "xp": 0, "rank": 0,
			"perks": [] as Array, "alive": true}]
	game._next_id = 2
	game.campaign_seed = 4242
	game.adversaries = [_adv(3, 1, "injured", KIND_GOBLIN_REVOLVER, "south",
			"Ilsa Vane", 3, 2)]
	game._next_adversary_id = 4
	game.notebook = [_row(1, 7, "escaped", KIND_GOBLIN_REVOLVER, "south",
			"Ilsa Vane")]
	game.save()

	var g2: Node = (load("res://scripts/Game.gd") as GDScript).new()
	root.add_child(g2)
	_check(g2.load_save(), "a saved campaign loads")
	_check(g2.adversaries.size() == 1, "the roster came back (%d)"
			% g2.adversaries.size())
	if g2.adversaries.is_empty():
		g2.free()
		_finish()
		return
	var rec: Dictionary = g2.adversaries[0]
	_check(int(rec.get("id", 0)) == 3, "with his id (%d)" % int(rec.get("id", 0)))
	_check(int(rec.get("survivals", 0)) == 3 and int(rec.get("injuries", 0)) == 2,
			"...his tally (%d survivals, %d wounds)"
			% [int(rec.get("survivals", 0)), int(rec.get("injuries", 0))])
	_check(int(rec.get("kind", -1)) == KIND_GOBLIN_REVOLVER,
			"...what he was carrying (%d)" % int(rec.get("kind", -1)))
	_check(str(rec.get("edge", "")) == "south", "...and which way he went (%s)"
			% str(rec.get("edge", "")))
	_check(int(g2._next_adversary_id) > 3,
			"and the next id will not collide (%d)" % int(g2._next_adversary_id))

	# A v5 save has a notebook and no roster. It must build one from the
	# escapees it CAN rebuild, so a campaign in flight keeps the men it met.
	var raw := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(raw.get_as_text())
	raw.close()
	var payload: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	payload["version"] = 5
	payload.erase("adversaries")
	payload.erase("next_adversary_id")
	payload["notebook"] = [
		_row(0, 1, "escaped", KIND_GOBLIN, "north", "Rebuilt Man"),
		_row(0, 2, "killed", KIND_GOBLIN, "north", "Dead Man"),
		{"level": 0, "name": "Ancient", "age": 40, "settlement": "Kessit",
				"fate": "escaped"},
	]
	var wf := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	wf.store_string(JSON.stringify(payload))
	wf.close()

	var g3: Node = (load("res://scripts/Game.gd") as GDScript).new()
	root.add_child(g3)
	_check(g3.load_save(), "a v5 save loads")
	_check(g3.adversaries.size() == 1,
			"...and its one rebuildable escapee becomes a standing adversary (%d)"
			% g3.adversaries.size())
	if g3.adversaries.size() == 1:
		_check(str(g3.adversaries[0].name) == "Rebuilt Man",
				"...the right one (%s)" % str(g3.adversaries[0].name))
		_check(g3.adversaries[0].history.size() == 1,
				"...with the line of history it already had")
	g2.free()
	g3.free()


# --- 4. the notebook now drives a spawner, so it is no longer trusted ---------

func _test_hostile_save(game: Node) -> void:
	print("
[4] a hand-edited save cannot choose who walks on")
	var poisoned: Array = game._read_notebook([
		{"level": 0, "name": "X", "fate": "escaped", "kind": 9999, "ordinal": 1},
		{"level": 0, "name": "Y", "fate": "escaped", "kind": -40, "ordinal": 2},
		"not a dictionary at all",
		# In range and NOT one of the Thirst: 9 is HERO, 8 is CIVILIAN, and
		# Unit.setup puts both on TEAM_SCOUT. A save saying kind 9 walked a
		# second Rodar Akai onto the rim, on the player's own side.
		{"level": 0, "name": "Ghost Akai", "fate": "escaped", "kind": 9, "ordinal": 4},
		{"level": 0, "name": "Ghost Civ", "fate": "escaped", "kind": 8, "ordinal": 5},
		{"level": 0, "name": "Z", "fate": "escaped", "kind": KIND_GOBLIN_SMG,
				"ordinal": 3},
	])
	_check(poisoned.size() == 5, "junk notebook rows are dropped (%d kept)"
			% poisoned.size())
	_check(int(poisoned[0].kind) == -1 and int(poisoned[1].kind) == -1,
			"an out-of-range kind is refused rather than passed to setup()")
	_check(int(poisoned[2].kind) == -1 and int(poisoned[3].kind) == -1,
			"...and so is an in-range kind that is not one of the Thirst "
			+ "(HERO %d, CIVILIAN %d)" % [int(poisoned[2].kind), int(poisoned[3].kind)])
	_check(int(poisoned[4].kind) == KIND_GOBLIN_SMG,
			"a real goblin is kept (%d)" % int(poisoned[4].kind))

	# The roster is stricter again: these go to a spawner AND carry a survival
	# count that feeds Rules.survive_chance.
	var roster: Array = game._read_adversaries([
		_adv(1, 0, "escaped", 9),                      # HERO
		_adv(2, 0, "escaped", 8),                      # CIVILIAN
		_adv(0, 0),                                    # no id
		_adv(5, 0),                                    # fine
		_adv(5, 0, "escaped", KIND_GOBLIN, "north", "Twin"),   # duplicate id
		"not a dictionary",
	])
	_check(roster.size() == 1, "only the one real record survives (%d)"
			% roster.size())
	if roster.size() == 1:
		_check(int(roster[0].id) == 5, "...and it is the right one (id %d)"
				% int(roster[0].id))
	var negative: Array = game._read_adversaries([
		{"id": 9, "kind": KIND_GOBLIN, "survivals": -5, "injuries": -2,
				"history": ["junk", {"level": 1, "fate": "escaped"}]},
	])
	_check(negative.size() == 1 and int(negative[0].survivals) == 0
			and int(negative[0].injuries) == 0,
			"a negative tally is floored rather than adopted")
	_check(negative.size() == 1 and negative[0].history.size() == 1,
			"and a malformed history line is dropped")


# --- 5 and 6. the arrival, through the real turn loop -------------------------

func _test_arrival() -> void:
	print("\n[5] a returner lands, through end_player_turn and nothing else")
	var game: Node = root.get_node("/root/Game")
	game.new_campaign()
	game.campaign_seed = 4242
	# THE SURVEY CAMP: index 6, and one of only two missions whose objective is
	# `eliminate`. It has to be an eliminate map for section 6 to mean anything -
	# on a destroy map _all_objectives_complete() stays false with the board
	# cleared, so "the mission ends" proves nothing there, which is exactly how
	# an earlier version of this passed while the rule it checked was deleted.
	game.current_level = 6
	game.current_operation = 1
	game.notebook = []
	game.adversaries = []
	# Conscripts, deliberately: their starting morale is 60, so the assertion
	# that a returner arrives at Rules.returner_morale() can actually fail. An
	# earlier version spawned a well-hand, whose plain default is already 100.
	for i in 30:
		game.adversaries.append(_adv(i + 1, 0, "escaped", KIND_GOBLIN_REVOLVER,
				"south", "Runner %d" % i))

	var battle: Node = (load("res://scenes/Battle.tscn") as PackedScene).instantiate()
	root.add_child(battle)
	await process_frame
	await process_frame

	var due_turns: Array = battle._returners_due.keys()
	_check(not due_turns.is_empty(), "somebody is scheduled (turns %s)" % [due_turns])
	if due_turns.is_empty():
		battle.free()
		_finish()
		return
	var first_turn: int = 99
	for t: int in due_turns:
		first_turn = mini(first_turn, int(t))

	# Watch the conscripts. THE SURVEY CAMP fields three, and their whole point
	# is that they start at 60 - so if Rules.morale_recovered is handed
	# MORALE_MAX instead of their own ceiling, +5 a quiet turn walks them back to
	# 100 and the class trait evaporates. Asserting the ceiling FIELD is not
	# enough: that is set at spawn and says nothing about the recovery path.
	var watched: Array[Node2D] = []
	for u in battle.living_units(1):
		if int(u.kind) == KIND_GOBLIN_REVOLVER:
			watched.append(u)
	_check(not watched.is_empty(), "the map fields conscripts to watch (%d)"
			% watched.size())
	if watched.is_empty():
		battle.free()
		_finish()
		return
	var ceilings: Array[int] = []
	var wrong_ceiling: Array[String] = []
	for u: Node2D in watched:
		ceilings.append(int(u.morale_ceiling))
		if int(u.morale_ceiling) != 60:
			wrong_ceiling.append(str(int(u.morale_ceiling)))
	_check(wrong_ceiling.is_empty(),
			"every conscript's ceiling is his own 60, not 100 (%s)" % [wrong_ceiling])
	var whole_hp: int = int(watched[0].max_hp)

	# Drive the REAL loop. Nothing here calls _land_returners by hand: deleting
	# its one production call is precisely the regression this has to catch.
	# `<=`, not `<`: _land_returners runs before turn_number is incremented, so
	# the arrival happens during the call that BEGINS on the due turn.
	var before: int = battle.living_units(1).size()
	var guard := 0
	while battle.turn_number <= first_turn and guard < 12:
		guard += 1
		battle.player_turn_ready_msec = 0
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
		battle.free()
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
	_check(int(him.adversary_id) > 0, "carrying his standing record (id %d)"
			% int(him.adversary_id))

	# Asserted against the ARRIVAL, not where he is standing now: he acts on the
	# turn he lands, so the AI has already walked him inland. "south" is recorded
	# rather than "north" on purpose too - _edge_of answers "north" for any
	# y == 0 and every arrival is a corner, so asserting "north" is satisfied by
	# a landing on the wrong side of the map entirely.
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
	# And close enough to matter: two earlier versions of the rule put him 16
	# tiles away in the Thirst's own corner, which passes everything else here
	# and is not an ambush.
	_check(closest <= battle.ARRIVAL_STANDOFF + 3,
			"...but behind the squad rather than across the map (%d tiles)" % closest)

	print("\n[6] and nobody arrives at a contact that is already over")
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

	_test_left_for_dead(battle, whole_hp)
	battle.free()
	_finish()


# --- 7 and 8. left for dead ---------------------------------------------------

func _test_left_for_dead(battle: Node, whole_hp: int) -> void:
	print("\n[7] the ones who were left for dead come back hurt")
	var rules_script: GDScript = load("res://scripts/Rules.gd") as GDScript
	# Placed directly rather than waited for: whether a WOUNDED man is offered on
	# any given mission is a coin the seed flips, and a test that waits for it is
	# a test that sometimes checks nothing.
	var wounded_rec := _adv(99, 0, "injured", KIND_GOBLIN_REVOLVER, "south",
			"Wounded Man", 6, 2)
	battle.state = battle.State.PLAYER_TURN
	var spot: Vector2i = battle._arrival_cell("north")
	battle._spawn_returner(wounded_rec, spot)
	var hurt: Node2D = battle.unit_at(spot)
	_check(hurt != null, "he is on the board at %s" % [spot])
	if hurt == null:
		return

	_check(int(hurt.max_hp) < whole_hp,
			"twice wounded, he is down on health (%d against a fresh %d)"
			% [int(hurt.max_hp), whole_hp])
	_check(int(hurt.hp) == int(hurt.max_hp), "...and arrives at what is left of it")
	var want_morale: int = rules_script.call("injured_morale", int(hurt.kind), 2)
	_check(int(hurt.morale) == want_morale,
			"down on nerve to exactly what two wounds cost (%d, want %d) - "
			% [int(hurt.morale), want_morale]
			+ "'under 100' would be satisfied by his untouched 60")
	_check(int(hurt.morale) > 30,
			"...but not already broken, or he routs on his first activation (%d)"
			% int(hurt.morale))
	_check(int(hurt.adversary_id) == 99 and int(hurt.survivals) == 6,
			"carrying his record: id %d, %d times away"
			% [int(hurt.adversary_id), int(hurt.survivals)])

	# The survival roll. A decisive blow is the player's lever and must never
	# roll; anything less asks a hash, which must answer the same way twice.
	hurt.last_blow = int(hurt.max_hp) + 2
	_check(battle._fate_of(hurt) == "killed",
			"a blow that would have killed him from full leaves nobody to find")
	# Not on HIM: two wounds have left him on 1 max HP, so every blow in the
	# game is decisive against him and _fate_of correctly never rolls. That is
	# the self-limiting half of the design working - a veteran is hard to finish
	# for good and trivial to put down again - but it makes him useless for
	# testing the roll. A whole well-hand at 4 HP taking a carbine round is the
	# case the roll actually exists for.
	# Put a whole one on the board for it: section 6 cleared the map, and the
	# only goblin left standing is the wretch above.
	var bench: Vector2i = battle._arrival_cell("west")
	battle._spawn_unit(KIND_GOBLIN, bench)
	var subject: Node2D = battle.unit_at(bench)
	if subject == null or int(subject.max_hp) < 4:
		_check(false, "needed a full-health goblin to test the roll on")
		return
	subject.last_blow = 2
	subject.survivals = 6
	var once: String = battle._fate_of(subject)
	_check(once == battle._fate_of(subject),
			"a lesser blow asks a hash, and it answers the same twice")
	# It has to be ABLE to say injured. Asking once cannot show that - a _fate_of
	# that returned "killed" unconditionally passed every assertion above.
	# Swept over spawn ordinals instead.
	var lived := 0
	for ord_ in 40:
		subject.spawn_ordinal = ord_
		if battle._fate_of(subject) == "injured":
			lived += 1
	_check(lived > 0,
			"at a veteran's odds some of forty defeats are survived (%d)" % lived)
	_check(lived < 40, "...and some are not (%d died)" % (40 - lived))
	subject.survivals = 0
	var stranger := 0
	for ord_ in 40:
		subject.spawn_ordinal = ord_
		if battle._fate_of(subject) == "injured":
			stranger += 1
	_check(stranger < lived,
			"a stranger survives less often than a veteran (%d vs %d of 40)"
			% [stranger, lived])
	# And the wounded man's own case, stated rather than left implicit.
	hurt.last_blow = 1
	_check(battle._fate_of(hurt) == "killed",
			"a man down to his last point of health is finished by anything")

	print("\n[8] and a won mission writes them into the campaign")
	# The call SITE, not the function: deleting _remember_the_survivors() from
	# _show_game_over leaves every assertion above green, because section 2 calls
	# Game.remember_survivor directly.
	var game2: Node = root.get_node("/root/Game")
	game2.adversaries = []
	battle.state = battle.State.PLAYER_TURN
	battle.roll.assign([{
		"identity": {"name": "Ledger Test", "age": 33, "settlement": "Kessit",
				"grievance": "the well"},
		"kind": KIND_GOBLIN, "fate": "escaped", "conduct": 0,
		"ordinal": 41, "edge": "north", "adversary_id": 0,
	}, {
		# Shot down and not accounted for. The squad watched him drop, so the
		# tally must not read him as killed.
		"identity": {"name": "Crawled Off", "age": 24, "settlement": "Kessit",
				"grievance": "the well"},
		"kind": KIND_GOBLIN, "fate": "injured", "conduct": 0,
		"ordinal": 42, "edge": "south", "adversary_id": 0,
	}])
	battle._show_game_over("TEST", true)
	_check(game2.adversaries.size() == 2,
			"both survivors of a won mission join the standing roster (%d)"
			% game2.adversaries.size())
	if game2.adversaries.size() != 2:
		return
	var written: Dictionary = game2.adversaries[0]
	_check(str(written.get("name", "")) == "Ledger Test",
			"...under his own name (%s)" % str(written.get("name", "")))
	_check(int(written.get("survivals", 0)) == 1, "...with one survival on the tally")
	_check(written.get("history", []).size() == 1, "...and one line of history")

	# And the player is told, at the moment it happens rather than by going to
	# look. _roll_text is built after _remember_the_survivors, so the tally it
	# quotes includes today.
	var after_action: String = battle.roll_label.text
	_check(after_action.contains("STILL OUT THERE"),
			"the after-action says somebody is still out there")
	_check(after_action.contains("Ledger Test"),
			"...and names him (%s)" % after_action.split("
")[-1])
	# He is not counted among the dead: the squad watched him go, and the roll
	# should not read as though it accounted for him.
	_check(after_action.contains("LEFT FOR DEAD"),
			"the man who was shot down is counted apart from the dead")
	_check(not after_action.contains("KILLED"),
			"...and nobody in this roll is counted killed at all")
