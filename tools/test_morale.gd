extends SceneTree

## Surrender and rout, driven through the real battle.
##
## Rules.gd's arithmetic is pinned in tools/test_rules.gd; this is the other
## half - that the controller actually asks it, and that the answers reach the
## board. Everything here runs against a live Battle scene with real units on a
## real map, because the interesting failures are all in the wiring:
##
##   1. a broken fighter with rifles on him puts his hands up, stops being a
##      combatant, and goes on THE ROLL as surrendered
##   2. a broken fighter with nobody covering him runs instead, and runs
##      TOWARD the edge rather than in some arbitrary direction
##   3. reaching the rim is an escape - off the tree, on the roll, not a death
##   4. an objective to CLEAR ground is met when nobody is still fighting for
##      it, whether or not everybody is dead
##   5. shooting a man with his hands up is allowed, and is recorded
##   6. the Marksman never breaks, which is what holds the kill floor up
##   7. morale is given back only to a fighter nothing happened to
##   8. bystanders: killable, uncounted, and not what a blast goes around
##   9. the after-action is two panels that are never summed, and the roll
##      reaches the notebook and the theater's two counters
##  10. an escape survives the REAL turn loop - the one that keeps holding
##      the unit after the activation that freed it
##
## The save is backed up in _init() before the Game autoload can touch it, the
## way tools/test_progression.gd does - a test that fights battles commits
## missions, and a developer's campaign should survive the suite.
##
## Known cosmetic noise: this is the only harness that moves units, so it is the
## only one that plays footstep SFX, and Godot's audio teardown occasionally
## races `quit()` and reports "2 ObjectDB instances were leaked at exit". The
## streams are stopped and released below and the exit code is 0 either way -
## grep RESULT, not stderr.
##
## Run: godot --headless --path . -s tools/test_morale.gd

const SAVE_PATH := "user://campaign.json"
const BACKUP_PATH := "user://campaign.json.morale-test-backup"

const TEAM_SCOUT := 0
const TEAM_GOBLIN := 1
const KIND_GOBLIN_BOLT := 7

var _failed := false
var _rules: GDScript = null
var _had_save := false


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    %s" % label)
	else:
		printerr("  FAIL  %s" % label)
		_failed = true


func _init() -> void:
	# Before anything loads it.
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


## A fresh battle on `level`, with its own scene tree node.
func _battle(level: int) -> Node:
	var game: Node = root.get_node("/root/Game")
	game.current_level = level
	var battle: Node = (load("res://scenes/Battle.tscn") as PackedScene).instantiate()
	root.add_child(battle)
	await process_frame
	await process_frame
	return battle


## Put `unit` on `cell`. Occupancy is derived from unit.cell (see
## Battle.unit_at), so this is the whole of it.
func _place(battle: Node, unit: Node2D, cell: Vector2i) -> void:
	unit.cell = cell
	unit.position = battle.board.cell_to_global(cell)


## Tear a battle down. queue_free() rather than free(): a live battle has tweens
## and timers hanging off its units, and freeing it out from under them is what
## the ObjectDB leak warning at exit is complaining about. The other harnesses
## never hit this because they build one battle and keep it; this file builds
## five.
func _dismiss(battle: Node) -> void:
	battle.queue_free()
	await process_frame
	await process_frame


## A walkable, unoccupied cell adjacent to `cell`, or NO_CELL.
func _free_neighbour(battle: Node, cell: Vector2i, taken: Array) -> Vector2i:
	for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		var c: Vector2i = cell + step
		if battle.board.in_bounds(c) and battle.board.is_walkable(c) \
				and battle.unit_at(c) == null and not taken.has(c):
			return c
	return Board.NO_CELL


func _run() -> void:
	await process_frame
	_rules = load("res://scripts/Rules.gd") as GDScript

	# Fight a campaign of our own, not the developer's.
	#
	# Backing the save up (in _init) protects the player's campaign FROM this
	# harness. It does not protect the harness from the campaign, and the Game
	# autoload has already loaded whatever was on disk by the time we get here.
	# Three things in a real save reach into these battles:
	#
	#   * district standing, which decides what breaking MEANS - at or below
	#     Rules.STANDING_FEARED nobody surrenders to this squad at any number of
	#     guns, so case [1] asserted a rule the district had switched off;
	#   * the ratline muster, which trims fighters off the spawn lists, so the
	#     board is not the board these cases were written against;
	#   * the adversary files, which walk returners on mid-battle.
	#
	# On CI there is no save and none of that happens, so the suite was green
	# there and red on any machine anyone had actually played on - the worst
	# shape a test can take. A fresh campaign here IS the CI condition, stated
	# rather than depended on.
	var game: Node = root.get_node("/root/Game")
	game.new_campaign()
	game.ensure_roster(Levels.LEVELS[0])

	await _test_surrender()
	await _test_rout_and_escape()
	await _test_clear_means_still_fighting()
	await _test_marksman_holds()
	await _test_recovery_needs_a_quiet_turn()
	await _test_bystanders()
	await _test_after_action()
	await _test_escape_through_the_turn_loop()
	await _test_shock_and_being_outnumbered()
	await _test_raider_breaks_contact()
	await _test_warband_lands_together()
	await _test_gunner_last_round()
	await _test_end_turn_guard()

	# Moving and surrendering play pooled SFX. Sfx assigns `player.stream` and
	# never clears it, so whichever player went last is still holding its WAV
	# when a `-s` script calls quit() - and Godot reports that at exit as a
	# leaked instance and a resource still in use. The game itself never trips
	# this because it quits through the main loop; the other harnesses never
	# trip it because they never move anybody. Let the tails finish, then hand
	# the streams back, so the suite does not ship a warning that means nothing.
	await create_timer(0.8).timeout
	var sfx: Node = root.get_node_or_null("/root/Sfx")
	if sfx != null:
		for player: AudioStreamPlayer in sfx._players:
			player.stop()
			player.stream = null
	# stop() retires the playback on the audio server's next pass, not on this
	# line, so quitting immediately can still race it.
	await process_frame
	await process_frame

	_restore()
	print("\nRESULT: ", "FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


# --- 1 & 5. hands up --------------------------------------------------------

func _test_surrender() -> void:
	print("\n[1] a broken fighter with rifles on him puts his hands up")
	var battle: Node = await _battle(0)
	var brk: int = int(_rules.get_script_constant_map()["MORALE_BREAK"])

	# A runner - anything but the Marksman, who is the one that never breaks.
	var goblin: Node2D = null
	for u in battle.living_units(TEAM_GOBLIN):
		if u.kind != KIND_GOBLIN_BOLT:
			goblin = u
			break
	_check(goblin != null, "found a breakable fighter on Dry Wash")

	# Two rifles on him, which is what makes surrender possible rather than rout.
	var scouts: Array = battle.living_soldiers(TEAM_SCOUT)
	var taken: Array = []
	var placed := 0
	for scout in scouts:
		var spot: Vector2i = _free_neighbour(battle, goblin.cell, taken)
		if spot == Board.NO_CELL:
			break
		_place(battle, scout, spot)
		taken.append(spot)
		placed += 1
		if placed == 2:
			break
	_check(placed == 2, "put two soldiers alongside him (%d)" % placed)
	_check(battle._guns_on(goblin) >= 2,
			"and the game agrees they have a shot (%d guns)" % battle._guns_on(goblin))

	# Two guns is enough IN A DISTRICT WITH NO OPINION EITHER WAY, and that is
	# a precondition of this case rather than a fact about the world - so it is
	# set here instead of assumed. A district that has learnt to fear the squad
	# raises the price of a surrender past any number of rifles (see below).
	var game: Node = root.get_node("/root/Game")
	var home := str(goblin.identity.get("settlement", ""))
	game.set_standing(home, int(_rules.get_script_constant_map()["STANDING_START"]))

	# The state a fighter is actually in when he breaks: pushed to the
	# threshold by a round that landed during the player's turn.
	goblin.morale = brk
	goblin.morale_pressed = true
	var done: bool = await battle._resolve_morale(goblin, 1, 9)
	_check(done, "his activation ends there")
	_check(goblin.surrendered and not goblin.routing,
			"he surrenders rather than running")
	_check(not goblin.is_combatant(),
			"a man with his hands up is not a combatant any more")
	_check(goblin.has_stopped(), "and reads as stopped")

	var last: Dictionary = battle.roll.back()
	_check(str(last.fate) == "surrendered", "THE ROLL says surrendered")
	_check(not (last.identity as Dictionary).is_empty(),
			"and it has his name on it (%s)" % last.identity.get("name", "?"))
	_check(int(last.conduct) == int(_rules.get_script_constant_map()["Conduct"].COMBATANT_KILLED),
			"taking a surrender costs nothing")

	print("\n[5] and the game still lets you shoot him")
	var before: int = battle.roll.size()
	goblin.take_damage(goblin.hp)
	await process_frame
	_check(battle.roll.size() == before + 1, "the round lands and is recorded")
	var shot: Dictionary = battle.roll.back()
	_check(int(shot.conduct)
			== int(_rules.get_script_constant_map()["Conduct"].SURRENDERED_FIRED_ON),
			"as firing on the surrendered, which is the entry that costs most")

	# And the other half of that precondition, which is what this harness is
	# for: the arithmetic of surrender_guns_needed is pinned in test_rules, but
	# only the controller can be caught failing to ASK. Same fighter class, same
	# two rifles, same broken morale - a district that has learnt to fear the
	# squad, and he runs instead. This is the term that was reaching in from a
	# real save and quietly turning case [1] over.
	var feared: int = int(_rules.get_script_constant_map()["STANDING_FEARED"])
	var other: Node2D = null
	for u in battle.living_units(TEAM_GOBLIN):
		if u.kind != KIND_GOBLIN_BOLT and not u.has_stopped():
			other = u
			break
	_check(other != null, "there is a second fighter to break")
	if other != null:
		game.set_standing(str(other.identity.get("settlement", "")), feared)
		var moved: Array = []
		var on_him := 0
		for scout in battle.living_soldiers(TEAM_SCOUT):
			var spot: Vector2i = _free_neighbour(battle, other.cell, moved)
			if spot == Board.NO_CELL:
				break
			_place(battle, scout, spot)
			moved.append(spot)
			on_him += 1
			if on_him == 2:
				break
		_check(battle._guns_on(other) >= 2,
				"with the same two rifles on him (%d guns)" % battle._guns_on(other))
		other.morale = brk
		other.morale_pressed = true
		await battle._resolve_morale(other, 2, 9)
		_check(other.routing and not other.surrendered,
				"nobody puts his hands up to a squad his district is afraid of")
	await _dismiss(battle)


# --- 2 & 3. running for it --------------------------------------------------

func _test_rout_and_escape() -> void:
	print("\n[2] a broken fighter with nobody covering him runs")
	var battle: Node = await _battle(0)
	var brk: int = int(_rules.get_script_constant_map()["MORALE_BREAK"])

	var goblin: Node2D = null
	for u in battle.living_units(TEAM_GOBLIN):
		if u.kind != KIND_GOBLIN_BOLT:
			goblin = u
			break
	# Every soldier a long way off, so nobody has a shot.
	for scout in battle.living_soldiers(TEAM_SCOUT):
		_place(battle, scout, Vector2i(0, 0))
	_check(battle._guns_on(goblin) == 0, "no rifle is on him")

	var edge_before: int = battle._edge_distance(goblin.cell)
	goblin.morale = brk
	goblin.morale_pressed = true
	var done: bool = await battle._resolve_morale(goblin, 1, 9)
	_check(done, "his activation ends there too")
	_check(goblin.routing and not goblin.surrendered, "he breaks and runs")
	var edge_after: int = battle._edge_distance(goblin.cell)
	_check(edge_after < edge_before,
			"and runs TOWARD the edge (%d -> %d tiles from it)"
			% [edge_before, edge_after])

	print("\n[3] reaching the rim is an escape, not a death")
	# Walk him onto the rim and give him one more activation.
	var rim := Vector2i(0, goblin.cell.y)
	while rim.x < battle.board.size.x and (not battle.board.is_walkable(rim)
			or battle.unit_at(rim) != null):
		rim.y = (rim.y + 1) % battle.board.size.y
		if rim.y == goblin.cell.y:
			break
	_place(battle, goblin, rim)
	_check(battle._at_map_edge(goblin.cell),
			"he is standing on the rim at %s" % goblin.cell)
	var roll_before: int = battle.roll.size()
	var alive_before: int = battle.living_units(TEAM_GOBLIN).size()
	done = await battle._resolve_morale(goblin, 1, 9)
	await process_frame
	await process_frame
	_check(done, "the activation ends")
	_check(battle.roll.size() == roll_before + 1
			and str(battle.roll.back().fate) == "escaped",
			"THE ROLL says escaped")
	_check(battle.living_units(TEAM_GOBLIN).size() == alive_before - 1,
			"and he is off the board without dying (%d -> %d)"
			% [alive_before, battle.living_units(TEAM_GOBLIN).size()])
	await _dismiss(battle)


# --- 4. what CLEAR means ----------------------------------------------------

func _test_clear_means_still_fighting() -> void:
	print("\n[4] ground is cleared when nobody is still fighting for it")
	var battle: Node = await _battle(0)
	_check(not battle._objective_complete(0),
			"Dry Wash starts uncleared")
	var total: int = battle.living_units(TEAM_GOBLIN).size()
	var surrendered := 0
	for u in battle.living_units(TEAM_GOBLIN):
		if u.kind == KIND_GOBLIN_BOLT:
			continue  # he never breaks; he has to be killed
		u.surrender()
		surrendered += 1
	_check(not battle._objective_complete(0),
			"%d of %d with their hands up is not cleared - the Marksman holds"
			% [surrendered, total])
	for u in battle.living_units(TEAM_GOBLIN):
		if u.kind == KIND_GOBLIN_BOLT:
			u.take_damage(u.hp)
	await process_frame
	_check(battle._objective_complete(0),
			"kill the one who would not stop, and the contact is resolved")
	var standing: int = battle.living_units(TEAM_GOBLIN).size()
	_check(standing > 0,
			"with %d of them still alive and standing on it" % standing)
	await _dismiss(battle)


# --- 6. the kill floor, on the board ----------------------------------------

func _test_marksman_holds() -> void:
	print("\n[6] the Marksman never breaks")
	var battle: Node = await _battle(0)
	var bolt: Node2D = null
	for u in battle.living_units(TEAM_GOBLIN):
		if u.kind == KIND_GOBLIN_BOLT:
			bolt = u
			break
	_check(bolt != null, "Dry Wash fields one")
	# Everything stacked against him: no morale at all, and rifles all round.
	var taken: Array = []
	for scout in battle.living_soldiers(TEAM_SCOUT):
		var spot: Vector2i = _free_neighbour(battle, bolt.cell, taken)
		if spot == Board.NO_CELL:
			break
		_place(battle, scout, spot)
		taken.append(spot)
	bolt.morale = 0
	var done: bool = await battle._resolve_morale(bolt, 1, 9)
	_check(not done, "at zero morale under %d guns his activation continues"
			% battle._guns_on(bolt))
	_check(not bolt.surrendered and not bolt.routing,
			"he neither surrenders nor runs")
	_check(bolt.is_combatant(), "he is still a combatant, and still in the way")
	await _dismiss(battle)


# --- 7. a lull, and a pause for breath --------------------------------------

func _test_recovery_needs_a_quiet_turn() -> void:
	print("
[7] morale is given back only to a fighter nothing happened to")
	var battle: Node = await _battle(0)
	var k: Dictionary = _rules.get_script_constant_map()
	var brk: int = int(k["MORALE_BREAK"])
	var recover: int = int(k["MORALE_RECOVER"])

	var quiet: Node2D = null
	var shot_at: Node2D = null
	for u in battle.living_units(TEAM_GOBLIN):
		if u.kind == KIND_GOBLIN_BOLT:
			continue
		if quiet == null:
			quiet = u
		elif shot_at == null:
			shot_at = u
	# Nobody covering either of them, so neither can surrender and confuse this.
	for scout in battle.living_soldiers(TEAM_SCOUT):
		_place(battle, scout, Vector2i(0, 0))

	quiet.morale = brk + 1  # above the line, and left alone
	quiet.morale_pressed = false
	await battle._resolve_morale(quiet, 1, 9)
	_check(quiet.morale == brk + 1 + recover,
			"a quiet turn steadies him by %d (%d)" % [recover, quiet.morale])

	shot_at.morale = brk + 1
	shot_at.morale_pressed = true
	await battle._resolve_morale(shot_at, 2, 9)
	_check(shot_at.morale == brk + 1,
			"a turn he was shot in gives back nothing (%d)" % shot_at.morale)
	_check(not shot_at.morale_pressed,
			"and the pressure is consumed, so the NEXT quiet turn counts")

	# The rule this exists to protect: the break threshold means what it says.
	var edge: Node2D = null
	for u in battle.living_units(TEAM_GOBLIN):
		if u.kind != KIND_GOBLIN_BOLT and u != quiet and u != shot_at:
			edge = u
			break
	edge.morale = brk
	edge.morale_pressed = true
	await battle._resolve_morale(edge, 3, 9)
	_check(edge.has_stopped(),
			"a fighter shot exactly to MORALE_BREAK breaks, rather than steadying past it")
	await _dismiss(battle)


# --- 8. the people who were only ever standing there -------------------------

func _test_bystanders() -> void:
	print("
[8] a bystander is a civilian nobody arranged to protect")
	var battle: Node = await _battle(4)  # THE CISTERN
	var conduct: Dictionary = _rules.get_script_constant_map()["Conduct"]

	var bystanders: Array = []
	for u in battle.living_units(TEAM_SCOUT):
		if u.bystander:
			bystanders.append(u)
	_check(bystanders.size() == 2,
			"THE CISTERN fields %d of them" % bystanders.size())
	var one: Node2D = bystanders[0]
	_check(one.is_civilian() and not one.captive,
			"on their feet from the start rather than huddled")
	_check(battle.captives().is_empty(),
			"and invisible to the rescue plumbing they are built on")
	_check(not one.is_combatant(),
			"never a combatant, so the Thirst does not shoot at them either")

	print("
     what a blast goes around, and what it does not")
	_check(not one.is_blast_immune(), "a bystander is NOT blast-immune")
	# The prisoners on the rescue map still are - that rule did not move.
	var pens: Node = await _battle(5)  # THE HOLDING PENS
	var prisoner: Node2D = pens.captives()[0]
	_check(prisoner.is_blast_immune(),
			"a prisoner the squad came to fetch still is")
	await _dismiss(pens)
	# And the bug this pass fixed: a man with his hands up can be shot with a
	# rifle, so a grenade going around him would be the inconsistency.
	var fighter: Node2D = null
	for u in battle.living_units(TEAM_GOBLIN):
		if u.kind != KIND_GOBLIN_BOLT:
			fighter = u
			break
	fighter.surrender()
	_check(not fighter.is_blast_immune(),
			"and a fighter with his hands up is not blast-immune either")

	print("
     killing one is recorded, and costs")
	var before: int = battle.roll.size()
	one.take_damage(one.hp)
	await process_frame
	_check(battle.roll.size() == before + 1, "it reaches THE ROLL")
	var entry: Dictionary = battle.roll.back()
	_check(int(entry.conduct) == int(conduct.CIVILIAN_KILLED),
			"as a civilian killed")
	_check(_rules.call("standing_cost", int(conduct.CIVILIAN_KILLED)) > 0
			and _rules.call("strain_cost", int(conduct.CIVILIAN_KILLED)) > 0,
			"which costs both Standing and Strain, unlike a clean kill")

	print("
     and nobody has to walk them out")
	# THE CISTERN wins by getting the SQUAD to the east edge. The surviving
	# bystander must not be able to hold that objective open.
	var zone: Array = battle._objectives()[0].get("cells", [])
	for scout in battle.living_soldiers(TEAM_SCOUT):
		_place(battle, scout, zone[battle.living_soldiers(TEAM_SCOUT).find(scout)])
	var survivor: Node2D = bystanders[1]
	_check(not zone.has(survivor.cell),
			"the surviving bystander is nowhere near the extraction zone")
	_check(battle._objective_complete(0),
			"and the squad still extracts")
	await _dismiss(battle)


# --- 9. the after-action ----------------------------------------------------

func _test_after_action() -> void:
	print("\n[9] two panels, and neither one is the other's score")
	var game: Node = root.get_node("/root/Game")
	# A campaign that has not been anywhere, so the counters start where a
	# fresh one does and the notebook is empty.
	game.notebook = []
	game.district_standing = {}
	game.alliance_strain = game.STRAIN_START
	var battle: Node = await _battle(0)

	# Fight it the cleanest way there is: every fighter killed while fighting.
	# Not one conduct entry, and every one of them still a name.
	for u in battle.living_units(TEAM_GOBLIN):
		u.take_damage(u.hp)
	await process_frame
	await process_frame
	_check(battle.last_result_won, "the wash is cleared")

	var operation: String = battle.debrief_label.text
	var roll: String = battle.roll_label.text
	print("\n--- THE OPERATION ---\n%s\n\n--- THE ROLL ---\n%s\n" % [operation, roll])

	_check(operation.begins_with("THE OPERATION"), "the left panel is the operation")
	_check(operation.contains("OBJECTIVE MET"), "it grades the objective")
	_check(operation.contains(" TURN"),
			"and reports the tempo, singular or plural")
	_check(roll.begins_with("THE ROLL"), "the right panel is the roll")
	_check(roll.contains("KILLED"), "it counts what happened")
	_check(roll.contains(", of "), "and reads out names rather than a headcount")

	# The rule the whole split exists for.
	_check(not operation.contains("STRAIN") and not operation.contains("ROLL"),
			"the graded panel never mentions the reported one")
	_check(not roll.contains("xp") and not roll.contains("OBJECTIVE"),
			"and the reported panel never grades anything")

	print("\n     a clean fight costs the theater nothing")
	_check(game.alliance_strain < game.STRAIN_START,
			"Strain walked DOWN toward the floor (%d from %d)"
			% [game.alliance_strain, game.STRAIN_START])
	_check(game.district_standing.is_empty(),
			"and no settlement thinks worse of the squad for a firefight")
	_check(not roll.contains("CIVILIANS HARMED"),
			"the roll has no civilian line to print")

	print("\n     and the notebook remembers all of them")
	_check(game.notebook.size() == 9,
			"nine names went into the notebook (%d)" % game.notebook.size())
	var by_settlement: Dictionary = game.notebook_by_settlement()
	_check(by_settlement.size() >= 2,
			"cross-linked across %d settlements" % by_settlement.size())
	var first: Dictionary = game.notebook[0]
	_check(int(first.get("level", -1)) == 0 and not str(first.get("name", "")).is_empty(),
			"each entry carries its mission and its name (%s)" % first.get("name", "?"))
	# The panel is a summary; the document is the record. That distinction is
	# the reason only three names are on screen.
	_check(roll.contains("more in the notebook"),
			"and the panel says where the rest of them are")
	await _dismiss(battle)


# --- 10. the escape, through run_enemy_turn rather than around it -------------

func _test_escape_through_the_turn_loop() -> void:
	print("\n[10] a fighter who runs off the map does not take the turn with him")
	# This is the test that was missing. Sections 2 and 3 call _resolve_morale
	# directly, which is exactly the shape that hid the bug: run_enemy_turn
	# goes on to clear the acting markers off the unit AFTER the activation
	# that freed it, and calling anything on a freed instance is a hard error
	# that stops the enemy turn dead.
	var battle: Node = await _battle(0)

	# One fighter left, standing on the rim, already broken and running.
	var runner: Node2D = null
	for u in battle.living_units(TEAM_GOBLIN):
		if u.kind != KIND_GOBLIN_BOLT and runner == null:
			runner = u
		else:
			u.take_damage(u.hp)
	await process_frame
	_check(battle.living_units(TEAM_GOBLIN).size() == 1,
			"one fighter left on the wash")

	var rim := Vector2i(0, runner.cell.y)
	var tries := 0
	while tries < battle.board.size.y and (not battle.board.is_walkable(rim)
			or battle.unit_at(rim) != null):
		rim.y = (rim.y + 1) % battle.board.size.y
		tries += 1
	_place(battle, runner, rim)
	runner.begin_rout()
	_check(battle._at_map_edge(runner.cell),
			"he is broken and standing on the rim at %s" % runner.cell)

	# The real thing, with its timers and its marker bookkeeping.
	battle.state = battle.State.ENEMY_TURN
	await battle.run_enemy_turn()
	await process_frame

	_check(battle.living_units(TEAM_GOBLIN).is_empty(),
			"the turn ran him off the board")
	# The invariant the guard in run_enemy_turn exists for, stated directly.
	# The structural assertions around it cannot catch the regression on their
	# own: calling a method on a freed instance logs a SCRIPT ERROR and returns
	# null rather than halting, so the turn limps on and every other check here
	# still passes. Run the suite with `grep -E "RESULT|SCRIPT ERROR"` - which
	# is what the README already tells you to do - and pin the reason here.
	_check(not is_instance_valid(runner),
			"the escaped fighter is genuinely freed, which is why the turn loop "
			+ "must not touch him afterwards")
	_check(not battle.roll.is_empty()
			and str(battle.roll.back().fate) == "escaped",
			"THE ROLL says escaped")
	# The proof that the turn loop finished rather than erroring out partway:
	# clearing the wash is what ends the mission, and _show_game_over is what
	# sets this. A crash in run_enemy_turn would leave it false.
	_check(battle.last_result_won,
			"and the contact resolved, so the loop ran to the end")
	await _dismiss(battle)


# --- 11. the formation breaks, not just the man -------------------------------
#
# Rules' arithmetic for both terms is pinned in tools/test_rules.gd. What is
# checked here is that _resolve_morale actually asks: both live in the
# controller, both are charged once per fighter per turn, and neither has a
# Rules signature that a wiring mistake would trip over.

func _test_shock_and_being_outnumbered() -> void:
	print("\n[11] losing several at once, and being the last two")
	var k: Dictionary = _rules.get_script_constant_map()
	var battle: Node = await _battle(0)

	# Three down inside the window, which is the shock floor. Written into the
	# tally rather than staged as real deaths on purpose: the thing under test
	# is that the turn READS the tally, and killing three would drag in the
	# ally-down term and prove less about this code.
	battle.turn_number = 5
	battle._thirst_deaths = {5: 2, 4: 1, 1: 4}
	_check(battle._recent_thirst_deaths() == 3,
			"deaths inside the window count and older ones do not (%d)"
			% battle._recent_thirst_deaths())

	var goblins: Array = battle.living_units(TEAM_GOBLIN)
	if goblins.size() < 2:
		_check(false, "expected the wash to field goblins")
		await _dismiss(battle)
		return
	# All but two off the board, so the survivors are outnumbered as well as
	# shocked. Freed rather than killed so no death handler fires and the tally
	# written above stays exactly what it was.
	var kept: Array = [goblins[0], goblins[1]]
	for g in goblins:
		if not kept.has(g):
			g.cell = Vector2i(-99, -99)
			g.queue_free()
	await process_frame

	var subject: Node2D = kept[0]
	# Deliberately below his ceiling. At full morale the quiet-turn recovery is
	# capped to nothing and the arithmetic below cannot tell "recovery ran and
	# was capped" from "recovery never ran", which is exactly the wiring this is
	# supposed to be checking.
	subject.morale = 90
	subject.morale_ceiling = 100
	subject.morale_pressed = false
	var soldiers: int = battle.living_soldiers(TEAM_SCOUT).size()
	var left: int = battle.living_units(TEAM_GOBLIN).size()
	_check(_rules.call("is_outnumbered", left, soldiers),
			"%d fighters against %d soldiers is outnumbered" % [left, soldiers])

	battle.state = battle.State.ENEMY_TURN
	var before: int = subject.morale
	await battle._resolve_morale(subject, 1, left)
	_check(subject.morale < before,
			"a fighter activating into that pays for both (%d -> %d)"
			% [before, subject.morale])
	var expected: int = int(_rules.call("morale_recovered", before, 100)) \
			- int(_rules.call("shock_cost", 3)) - int(k["MORALE_OUTNUMBERED"])
	_check(subject.morale == expected,
			"...exactly the two terms, after the quiet-turn recovery (%d, wanted %d)"
			% [subject.morale, expected])

	# And it has to be able to finish somebody, or none of it matters.
	var other: Node2D = kept[1]
	if is_instance_valid(other):
		other.morale = int(k["MORALE_BREAK"]) + int(k["MORALE_SHOCK"])
		other.morale_pressed = true  # deny recovery, so only the terms move him
		await battle._resolve_morale(other, 2, left)
		_check(_rules.call("is_broken", other.morale),
				"a man already worn thin is broken by it (%d)" % other.morale)
	await _dismiss(battle)


# --- 12. a raider hits once and goes ------------------------------------------

func _test_raider_breaks_contact() -> void:
	print("\n[12] somebody who came back to raid leaves when he is done")
	var conduct: Dictionary = _rules.get_script_constant_map()["Conduct"]
	var battle: Node = await _battle(0)
	var goblins: Array = battle.living_units(TEAM_GOBLIN)
	if goblins.is_empty():
		_check(false, "expected the wash to field goblins")
		await _dismiss(battle)
		return
	var raider: Node2D = goblins[0]
	raider.returned = true
	raider.raider = true
	raider.raid_shots_left = 1
	raider.morale = 100
	raider.morale_ceiling = 100
	raider.morale_pressed = true  # steady: nothing here is a morale break

	battle.state = battle.State.ENEMY_TURN
	var done: bool = await battle._resolve_morale(raider, 1, goblins.size())
	_check(not done and not raider.routing,
			"with his shot still owed he holds his ground")

	raider.raid_shots_left = 0
	done = await battle._resolve_morale(raider, 1, goblins.size())
	_check(raider.routing, "having taken it, he breaks contact")
	_check(raider.raid_withdrawal,
			"...and it is marked a withdrawal, not nerve going")
	_check(not _rules.call("is_broken", raider.morale),
			"...on full morale, which is the whole difference (%d)" % raider.morale)

	# The conduct consequence, which is the reason the flag exists at all.
	battle.roll.clear()
	battle._record_on_roll(raider, "killed")
	_check(not battle.roll.is_empty()
			and int(battle.roll.back().conduct) == int(conduct.COMBATANT_KILLED),
			"firing on him on the way out is a combat kill and costs nothing")
	raider.raid_withdrawal = false
	battle.roll.clear()
	battle._record_on_roll(raider, "killed")
	_check(int(battle.roll.back().conduct) == int(conduct.ROUTING_FIRED_ON),
			"...while a man whose nerve went is still protected")
	await _dismiss(battle)


# --- 13. a warband walks on as one --------------------------------------------

func _test_warband_lands_together() -> void:
	print("\n[13] a warband walks on together")
	var game: Node = root.get_node("/root/Game")
	var kept_adversaries: Array = game.adversaries.duplicate(true)
	var kept_seed: int = game.campaign_seed
	game.adversaries = []
	for i in 4:
		game.adversaries.append({
			"id": 900 + i, "name": "Band%d" % i, "age": 30,
			"settlement": "Kessit", "grievance": "the well", "kind": 3,
			"survivals": 3 if i == 0 else 1, "injuries": 0,
			"state": "escaped", "edge": "north",
			"history": [{"level": 0, "fate": "escaped"}], "last_level": 0,
		})
	# Whichever campaign and mission this band actually turns up on. Searching
	# rather than pinning one seed is the point: WARBAND_CHANCE is a coin the
	# hash flips per (seed, level, leader), and a hardcoded pair that happens to
	# come up tails today would make this a test of one arbitrary number rather
	# than of the machinery. The search is over a fixed list, so it is still
	# deterministic.
	var level := -1
	for seed_try in [20260821, 4242, 99881, 7, 1234567]:
		game.campaign_seed = seed_try
		for candidate in range(1, 7):
			if not game.warband_for(candidate).is_empty():
				level = candidate
				break
		if level >= 0:
			break
	if level < 0:
		_check(false, "expected some mission to draw the warband")
		game.adversaries = kept_adversaries
		game.campaign_seed = kept_seed
		return

	var battle: Node = await _battle(level)
	var before: int = battle.living_units(TEAM_GOBLIN).size()
	var due: Array = battle._returners_due.get(battle.WARBAND_TURN, [])
	_check(due.size() == int(game.WARBAND_SIZE),
			"all %d are scheduled for the same turn (%d)"
			% [int(game.WARBAND_SIZE), due.size()])
	var edges := {}
	var chiefs := 0
	for entry: Dictionary in due:
		edges[str(entry.get("edge", ""))] = true
		if bool(entry.get("warband_leader", false)):
			chiefs += 1
	_check(edges.size() == 1, "off one rim, so they arrive as a formation")
	_check(chiefs == 1, "with exactly one of them leading")

	battle.turn_number = battle.WARBAND_TURN
	await battle._land_returners()
	await process_frame
	var after: int = battle.living_units(TEAM_GOBLIN).size()
	_check(after == before + int(game.WARBAND_SIZE),
			"and all %d are standing on the board (%d -> %d)"
			% [int(game.WARBAND_SIZE), before, after])

	var band_id := 0
	var stamped := 0
	var leaders := 0
	var follower: Node2D = null
	var chief: Node2D = null
	for g in battle.living_units(TEAM_GOBLIN):
		if g.warband == 0:
			continue
		stamped += 1
		band_id = g.warband
		if g.warband_leader:
			leaders += 1
			chief = g
			_check(g.adversary_id == g.warband,
					"the leader carries the band's own id, so his people can find him")
		else:
			follower = g
	_check(stamped == int(game.WARBAND_SIZE), "all of them stamped with the band")
	_check(leaders == 1, "and one of them leading it")

	# The cohesion a band buys, and what losing it costs.
	if follower != null and chief != null:
		_check(battle._warband_leader_alive(band_id),
				"while he is up, his people know it")
		follower.morale = 50
		follower.morale_ceiling = 100
		follower.morale_pressed = false
		battle.state = battle.State.ENEMY_TURN
		await battle._resolve_morale(follower, 1, after)
		_check(follower.morale == int(_rules.call("morale_recovered_led", 50, 100)),
				"...and steady faster for it (%d)" % follower.morale)
		var was: int = follower.morale
		battle._spread_morale_from_death(chief)
		_check(follower.morale < was,
				"losing him costs the rest of them at once (%d -> %d)"
				% [was, follower.morale])
		chief.cell = Vector2i(-99, -99)
		chief.queue_free()
		await process_frame
		_check(not battle._warband_leader_alive(band_id),
				"and the band knows he is gone")
	await _dismiss(battle)
	game.adversaries = kept_adversaries
	game.campaign_seed = kept_seed


# --- 14. the machinegunner's last round ---------------------------------------
#
# His lightest trigger is a two-round burst, so a lone belt round can never be
# aimed at a man - but the attack overlay used to paint the tile red anyway,
# and the shot then failed with no sound, no banner, and no prompt. min_rounds
# is the fix; this drives the real overlay to prove the gate reads it.

func _test_gunner_last_round() -> void:
	print("
[14] the gunner's last round cannot be promised to a target")
	var battle: Node = await _battle(0)
	var gunner: Node2D = null
	for u in battle.living_units(TEAM_SCOUT):
		if not u.can_single_shot():
			gunner = u
			break
	if gunner == null:
		_check(false, "expected the wash to field the machinegunner")
		await _dismiss(battle)
		return
	var goblin: Node2D = battle.living_units(TEAM_GOBLIN)[0]
	_place(battle, gunner, goblin.cell + Vector2i(0, 1))

	_check(gunner.min_rounds() == 2 and battle.living_units(TEAM_SCOUT)[0]
			.min_rounds() <= gunner.min_rounds(),
			"the gunner needs two where a rifleman needs one")
	gunner.ammo = 1
	_check(gunner.needs_reload(),
			"one round in a two-round weapon reads as needing a reload")
	battle.select(gunner)
	_check(not battle.board.attack_cells.has(goblin.cell),
			"...and the overlay no longer offers the man beside him")
	# The round is not dead - the single-round spenders keep it.
	_check(gunner.has_ammo(),
			"the round itself is still there for overwatch and drums")

	gunner.ammo = 2
	_check(not gunner.needs_reload(), "two rounds is a working weapon again")
	battle.select(gunner)
	_check(battle.board.attack_cells.has(goblin.cell),
			"...and the overlay offers the shot")
	await _dismiss(battle)


# --- 15. one keypress cannot throw the turn away ------------------------------
#
# E is also the camp's interact key. With soldiers still ready, the first press
# must warn and arm a confirm window rather than handing the Thirst a free
# round; a second press inside the window is a decision and goes through.

func _test_end_turn_guard() -> void:
	print("
[15] ending the turn with soldiers ready takes two presses")
	var battle: Node = await _battle(0)
	# Step past the anti-mash grace that exists for a different reason.
	battle.player_turn_ready_msec = Time.get_ticks_msec() - 1000

	var ready: int = battle._soldiers_still_ready()
	_check(ready > 0, "a fresh deployment has soldiers ready (%d)" % ready)
	battle.end_player_turn()
	_check(battle.state == battle.State.PLAYER_TURN
			and not battle.enemy_turn_running,
			"the first press does not end the turn")
	_check(battle._end_turn_confirm_until > Time.get_ticks_msec(),
			"...it arms the confirm window instead")
	_check(battle.end_turn_button.text.contains("%d ready" % ready),
			"...and the button says why (%s)" % battle.end_turn_button.text)

	# The second press, inside the window, is a decision.
	var before: int = battle.turn_number
	await battle.end_player_turn()
	_check(battle.turn_number == before + 1,
			"the second press runs the turn (turn %d -> %d)"
			% [before, battle.turn_number])
	_check(battle._end_turn_confirm_until == 0,
			"...and disarms the window behind it")
	await _dismiss(battle)
