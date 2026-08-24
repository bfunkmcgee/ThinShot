extends SceneTree

## Bounties: the generated boards, and the numbers a negotiation runs on.
##
## The generator is the part that has to be pinned hardest. An authored mission
## is checked once by a person and then forever by Levels.validate_all; a board
## that is built at the moment the player accepts a bounty gets neither unless
## it is checked here, and "the map generated wrong" is the one bug class a
## player cannot work around.
##
## Five things are checked:
##   1. every board a campaign can generate is VALID - right shape, legal
##      characters, and every resident and the hide reachable from the rim the
##      party lands on
##   2. generation is a pure function of (campaign seed, target), so a bounty
##      looked at twice is the same bounty
##   3. offers are only ever people the squad actually let get away, most
##      storied first, and never somebody already hunted
##   4. the three negotiation rolls move the way their stats say, and neither
##      end of the scale is ever certain
##   5. the outcomes are ordered - turning a man is worth more to the district
##      and the theater than shooting him
##
## Run: godot --headless --path . -s tools/test_bounty.gd

## Spelled as literals rather than as TEAM_SCOUT, and this is not a style
## choice. A `-s` harness compiles before the autoloads exist, so naming Unit
## here would pull in a file that names the Game autoload and the whole script
## fails to compile - the same trap tools/test_morale.gd and test_returners.gd
## already dodge the same way. The engine-driven half below reaches Game through
## root.get_node("/root/Game"), which resolves at run time and is fine.
const TEAM_SCOUT := 0
const TEAM_GOBLIN := 1

var _failed := false
var _bounty: GDScript = null


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    %s" % label)
	else:
		printerr("  FAIL  %s" % label)
		_failed = true


func _init() -> void:
	_run()


## One standing adversary, the shape Game.remember_survivor writes.
func _adv(id: int, survivals := 1, state := "escaped", kind := 3) -> Dictionary:
	return {
		"id": id, "name": "Vekh %d" % id, "age": 30, "settlement": "Kessit",
		"grievance": "the well", "kind": kind, "survivals": survivals,
		"injuries": 0, "state": state, "edge": "north",
		"history": [{"level": 0, "fate": state}], "last_level": 0,
	}


func _run() -> void:
	# Before anything else: autoloads are instantiated on the first processed
	# frame, and section 6 stands up a real Battle, which cannot exist without
	# them. Without this the engine half of the file silently no-ops against a
	# null Game while the arithmetic half still passes.
	await process_frame
	_bounty = load("res://scripts/Bounty.gd") as GDScript
	_test_every_board_is_valid()
	_test_generation_is_stable()
	_test_who_gets_posted()
	_test_negotiation_odds()
	_test_outcomes_are_ordered()
	await _test_the_whole_mission()
	await _test_the_manhunt()
	_restore()
	print("\nRESULT: ", "FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


# --- 1. the generator cannot ship a broken board ------------------------------

func _test_every_board_is_valid() -> void:
	print("\n[1] every board a campaign can generate is walkable and finishable")
	# A wide sweep rather than a couple of spot checks: this is procedural
	# content, and the failures that matter are the ones that only happen on the
	# one seed nobody tried. 240 boards across 12 campaigns is cheap and covers
	# every branch the layout code has.
	var bad := 0
	var first_problem := ""
	var boards := 0
	for s in 12:
		var campaign_seed := 1000 + s * 7717
		for t in 20:
			var offer: Dictionary = _bounty.call("offer_for", campaign_seed,
					_adv(t + 1, 1 + t % 4))
			var level: Dictionary = _bounty.call("generate", offer, campaign_seed)
			boards += 1
			if level.is_empty():
				bad += 1
				if first_problem == "":
					first_problem = "generate() gave up on seed %d target %d" % [
							campaign_seed, t + 1]
				continue
			var problems: Array = _bounty.call("validate", level)
			if not problems.is_empty():
				bad += 1
				if first_problem == "":
					first_problem = "seed %d target %d: %s" % [campaign_seed,
							t + 1, ", ".join(problems)]
	_check(bad == 0, "%d generated boards, %d bad%s" % [boards, bad,
			"" if first_problem == "" else " (" + first_problem + ")"])

	# And that the validator is not simply always happy, which would make the
	# sweep above worthless. Break a board in each of the ways that matter.
	var sample: Dictionary = _bounty.call("generate",
			_bounty.call("offer_for", 4242, _adv(1)), 4242)
	_check((_bounty.call("validate", sample) as Array).is_empty(),
			"the sample board is sound to begin with")
	var torn: Dictionary = sample.duplicate(true)
	torn["map"] = (torn["map"] as Array).slice(0, 4)
	_check(not (_bounty.call("validate", torn) as Array).is_empty(),
			"...a short map is caught")
	var walled: Dictionary = sample.duplicate(true)
	var rows: Array = []
	for y in int(walled.size.y):
		# A wall down the board between the party and everything they came for.
		rows.append("...#############".substr(0, int(walled.size.x)))
	walled["map"] = rows
	_check(not (_bounty.call("validate", walled) as Array).is_empty(),
			"...and so is a board the party cannot cross")
	var illegal: Dictionary = sample.duplicate(true)
	var r0: String = str(illegal.map[0])
	illegal.map[0] = "Z" + r0.substr(1)
	_check(not (_bounty.call("validate", illegal) as Array).is_empty(),
			"...and a character the board cannot draw")


# --- 2. the same bounty twice ------------------------------------------------

func _test_generation_is_stable() -> void:
	print("\n[2] a bounty looked at twice is the same bounty")
	var offer_a: Dictionary = _bounty.call("offer_for", 555, _adv(9, 2))
	var offer_b: Dictionary = _bounty.call("offer_for", 555, _adv(9, 2))
	_check(str(offer_a.place) == str(offer_b.place),
			"the same man is rumoured to be in the same place (%s)" % offer_a.place)
	var one: Dictionary = _bounty.call("generate", offer_a, 555)
	var two: Dictionary = _bounty.call("generate", offer_b, 555)
	_check(str(one.map) == str(two.map), "and the board is laid out the same way")
	_check(str(one.bounty.hide) == str(two.bounty.hide),
			"...with him hiding in the same place (%s)" % str(one.bounty.hide))
	var other: Dictionary = _bounty.call("offer_for", 556, _adv(9, 2))
	var three: Dictionary = _bounty.call("generate", other, 556)
	_check(str(three.map) != str(one.map),
			"a different campaign generates a different board")
	# Different people, same campaign, must not share a board either - the
	# obvious hashing mistake here is keying on the seed and forgetting the man.
	var neighbour: Dictionary = _bounty.call("generate",
			_bounty.call("offer_for", 555, _adv(10, 2)), 555)
	_check(str(neighbour.map) != str(one.map),
			"and so does a different man in the same campaign")


# --- 3. who the garrison posts -----------------------------------------------

func _test_who_gets_posted() -> void:
	print("\n[3] only the ones who got away, most storied first")
	var pool := [_adv(1, 1), _adv(2, 3), _adv(3, 2),
			_adv(4, 5, "killed"), _adv(5, 1, "surrendered")]
	var posted: Array = _bounty.call("offers", 99, pool, [])
	_check(posted.size() == int(_bounty.get_script_constant_map()["OFFERS"]),
			"the board posts %d of them (%d)"
			% [int(_bounty.get_script_constant_map()["OFFERS"]), posted.size()])
	var ids: Array = []
	for o: Dictionary in posted:
		ids.append(int(o.target_id))
	_check(not ids.has(4) and not ids.has(5),
			"a man who was killed or taken is not on the board")
	_check(int(posted[0].target_id) == 2 and int(posted[1].target_id) == 3,
			"and the most storied is posted first (%s)" % str(ids))
	var after: Array = _bounty.call("offers", 99, pool, [2])
	var after_ids: Array = []
	for o: Dictionary in after:
		after_ids.append(int(o.target_id))
	_check(not after_ids.has(2),
			"somebody already hunted comes off the board (%s)" % str(after_ids))
	_check((_bounty.call("offers", 99, [], []) as Array).is_empty(),
			"a campaign that has never let anybody go has no bounties")


# --- 4. the three rolls ------------------------------------------------------

func _test_negotiation_odds() -> void:
	print("\n[4] the rolls move the way the stats say")
	var k: Dictionary = _bounty.get_script_constant_map()

	_check(int(_bounty.call("question_chance", 3, 0))
			> int(_bounty.call("question_chance", 0, 0)),
			"guile makes a resident likelier to talk")
	_check(int(_bounty.call("question_chance", 2, 3))
			< int(_bounty.call("question_chance", 2, 0)),
			"and every refusal makes the next one warier")

	_check(int(_bounty.call("surrender_chance", 4, 1, false, false))
			> int(_bounty.call("surrender_chance", 0, 1, false, false)),
			"presence makes a surrender likelier")
	_check(int(_bounty.call("surrender_chance", 2, 4, false, false))
			< int(_bounty.call("surrender_chance", 2, 0, false, false)),
			"...a man who has got away four times is harder to talk down")
	_check(int(_bounty.call("surrender_chance", 2, 1, true, false))
			< int(_bounty.call("surrender_chance", 2, 1, false, false)),
			"...and men at his back make him braver")
	_check(int(_bounty.call("surrender_chance", 2, 1, false, false, 90))
			> int(_bounty.call("surrender_chance", 2, 1, false, false, 50)),
			"a town that trusts the squad leans on the offer")
	_check(int(_bounty.call("surrender_chance", 2, 1, false, false, 10))
			< int(_bounty.call("surrender_chance", 2, 1, false, false, 50)),
			"and one that fears it leans the other way")
	_check(int(_bounty.call("surrender_chance", 2, 1, false, true))
			> int(_bounty.call("surrender_chance", 2, 1, false, false)),
			"...while being hurt when you ask makes him listen")

	_check(int(_bounty.call("informant_chance", 4, 0, 1, false, false))
			> int(_bounty.call("informant_chance", 0, 0, 1, false, false)),
			"guile is what turns a man")
	_check(int(_bounty.call("informant_chance", 2, 0, 1, false, true))
			> int(_bounty.call("informant_chance", 2, 0, 1, false, false)),
			"...and a grievance of his own helps")
	# The ordering that makes the third option the prize rather than a synonym.
	_check(int(_bounty.call("informant_chance", 2, 2, 1, false, false))
			< int(_bounty.call("surrender_chance", 2, 1, false, false)),
			"turning him is always harder than making him give up")

	# Neither end is ever a certainty. A 0% would make a hopeless bounty
	# unplayable and a 100% would make a specialist a formality.
	var lo := int(k["CHANCE_MIN"])
	var hi := int(k["CHANCE_MAX"])
	_check(int(_bounty.call("surrender_chance", 0, 99, true, false)) >= lo,
			"the worst surrender odds are still %d%%" % lo)
	_check(int(_bounty.call("surrender_chance", 99, 0, false, true)) <= hi,
			"the best are still only %d%%" % hi)
	_check(int(_bounty.call("informant_chance", 99, 99, 0, false, true)) <= hi,
			"and so are the best odds of turning somebody")
	_check(int(_bounty.call("question_chance", 99, 0)) <= hi
			and int(_bounty.call("question_chance", 0, 99)) >= lo,
			"...and of being talked to at all")


# --- 5. what each ending is worth --------------------------------------------

func _test_outcomes_are_ordered() -> void:
	print("\n[5] the endings are ordered, and the best one is the quiet one")
	_check(int(_bounty.call("standing_for", "informant"))
			> int(_bounty.call("standing_for", "surrendered"))
			and int(_bounty.call("standing_for", "surrendered"))
			> int(_bounty.call("standing_for", "killed")),
			"turned beats taken beats shot, for the district")
	_check(int(_bounty.call("strain_for", "informant"))
			< int(_bounty.call("strain_for", "surrendered"))
			and int(_bounty.call("strain_for", "surrendered"))
			< int(_bounty.call("strain_for", "killed")),
			"...and the same order eases the theater")
	_check(int(_bounty.call("standing_for", "killed")) == 0
			and int(_bounty.call("strain_for", "killed")) == 0,
			"shooting a posted man costs nothing - he was armed and wanted")
	_check(int(_bounty.call("standing_for", "nonsense")) == 0,
			"an outcome this file does not know is worth nothing rather than crashing")


# --- 6. the mission, played through --------------------------------------------
#
# The three sections above are arithmetic. This one stands a real Battle up on a
# generated board and drives it, because everything interesting about a bounty
# is wiring: whether the party that lands is the party that was chosen, whether
# a resident can be asked, whether the man turns up when somebody talks, and
# whether each of the three endings books the same way.

const SAVE_PATH := "user://campaign.json"
var _backup := ""
var _had_save := false


func _keep_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		_backup = f.get_as_text()
		f.close()
		_had_save = true


func _restore() -> void:
	if not _had_save:
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(_backup)
		f.close()


## Stand up a bounty with a known target and a known hunter.
func _stage(game: Node, survivals := 1) -> Dictionary:
	game.adversaries = [_adv(41, survivals)]
	game.bounties_done = []
	game.informants = []
	game.bounty_outcomes = []
	# Zeroed so the pay assertions below read this bounty's earnings alone,
	# whatever campaign the autoload booted into.
	game.scrip = 0
	game.armory = []
	game.campaign_seed = 31337
	game.current_level = 0
	# An empty level wants no hero and no gunner slot, which is exactly what a
	# bounty party is - ensure_roster reads those two keys and nothing else.
	game.ensure_roster({})
	var hunter: Dictionary = game.roster[0]
	var offer: Dictionary = _bounty.call("offer_for", game.campaign_seed,
			game.adversaries[0])
	var level: Dictionary = _bounty.call("generate", offer, game.campaign_seed)
	game.begin_bounty(int(hunter.id), 41, level)
	return {"hunter": hunter, "offer": offer}


func _battle() -> Node:
	var b: Node = (load("res://scenes/Battle.tscn") as PackedScene).instantiate()
	root.add_child(b)
	await process_frame
	await process_frame
	return b


func _drop(b: Node) -> void:
	b.queue_free()
	await process_frame
	await process_frame


func _test_the_whole_mission() -> void:
	print("
[6] a bounty, played")
	_keep_save()
	var game: Node = root.get_node_or_null("/root/Game")
	# Stated rather than assumed. A harness that cannot reach the campaign must
	# FAIL here - the earlier draft went on to poke a null and still printed
	# PASS, because every _check after this point was simply never reached.
	if game == null:
		_check(false, "the Game autoload is up (it is not - section 6 cannot run)")
		return
	_check(true, "the Game autoload is up")

	# --- the party that lands is the party that was chosen -------------------
	var staged := _stage(game)
	var battle: Node = await _battle()
	_check(game.on_bounty(), "the mission that loaded is the bounty")
	var squad: Array = battle.living_units(TEAM_SCOUT)
	_check(squad.size() == 3, "three go out (%d)" % squad.size())
	_check(battle.bounty_hunter != null
			and battle.bounty_hunter.soldier_id == int(staged.hunter.id),
			"and the one the player picked is among them")
	var named := 0
	for u in squad:
		if u.soldier_id != 0:
			named += 1
	_check(named == 1, "the other two are nobody from the roster (%d named)" % named)
	_check(battle.residents.size() >= 3,
			"the place is lived in (%d residents)" % battle.residents.size())
	var fighting := 0
	for u in battle.living_units(TEAM_GOBLIN):
		if u.is_combatant():
			fighting += 1
	_check(fighting == 0, "and nobody there is fighting anybody")
	_check(battle.bounty_target == null, "the man himself is not on the board yet")

	# --- asking ---------------------------------------------------------------
	# Put the hunter next to somebody and make the roll certain, so this checks
	# the wiring rather than re-testing question_chance().
	var who: Node2D = battle.residents[0]
	battle.selected = battle.bounty_hunter
	battle.bounty_hunter.cell = who.cell + Vector2i(1, 0)
	_check(battle._resident_in_reach() == who, "somebody in reach can be asked")
	game.award_stat(int(staged.hunter.id), "guile", 9)
	await battle._try_question()
	await process_frame
	_check(who.questioned, "and having been asked, is not asked again")
	_check(battle.bounty_target != null, "he talks, and the man turns up")
	if battle.bounty_target == null:
		await _drop(battle)
		return
	_check(battle.bounty_target.bounty_target
			and int(battle.bounty_target.adversary_id) == 41,
			"...and it is the man the bounty was posted on")
	_check(battle.bounty_target.is_combatant(),
			"...who IS fighting, unlike everybody else here")

	# --- turning him ----------------------------------------------------------
	battle.selected = battle.bounty_hunter
	battle.bounty_hunter.cell = battle.bounty_target.cell + Vector2i(1, 0)
	_check(battle._target_in_reach() == battle.bounty_target,
			"close enough to make him an offer")
	game.award_stat(int(staged.hunter.id), "presence", 9)
	var standing_before: int = game.standing_of(str(staged.offer.settlement))
	var strain_before: int = game.alliance_strain
	# Driven through the BUTTON, not the function. The informant ending shipped
	# reachable only from this file - no key, no button ever called it in play -
	# and a test that dials the function directly would keep certifying exactly
	# that gap. The panel refresh is what shows the buttons; press what a player
	# would press.
	battle._update_unit_panel()
	_check(battle.informant_button.visible,
			"with the man in reach, the deal is on screen")
	_check(battle.parley_button.visible
			and battle.parley_button.text.begins_with("Demand"),
			"...beside the surrender demand")
	battle.informant_button.pressed.emit()
	await process_frame
	_check(battle.bounty_outcome == "informant", "he takes the other offer")
	_check(battle.bounty_target.surrendered,
			"...and stops being something to shoot")
	_check(game.standing_of(str(staged.offer.settlement)) > standing_before,
			"the district notices (%d -> %d)" % [standing_before,
					game.standing_of(str(staged.offer.settlement))])
	_check(game.alliance_strain < strain_before,
			"and the theater eases (%d -> %d)" % [strain_before, game.alliance_strain])
	_check(battle._objective_complete(0), "which finishes the mission")
	await _drop(battle)

	# --- booking it -----------------------------------------------------------
	# Nothing is called by hand here. Completing the objective ends the mission,
	# and _show_game_over books the bounty on the way out - which is the path a
	# player takes and therefore the one worth checking. An earlier draft called
	# finish_bounty() again afterwards and then asserted one informant, which
	# failed at two: the test was double-booking, not the game.
	_check(game.informants.size() == 1,
			"the informant is on the books (%d)" % game.informants.size())
	_check(game.bounties_done.has(41), "the bounty comes off the board")
	# The pay: an informant is the dearest of the three endings, banked by
	# finish_bounty on the way out - plus whatever Gear.drop deterministically
	# rolled for this target.
	var expect_find: String = Gear.drop(game.campaign_seed, 1000 + 41)
	_check(int(game.scrip) == int(game.SCRIP_BOUNTY.informant),
			"the informant paid %d scrip (book holds %d)"
			% [int(game.SCRIP_BOUNTY.informant), game.scrip])
	_check(game.armory.size() == (0 if expect_find.is_empty() else 1),
			"and the drop matched Gear.drop's answer ('%s')" % expect_find)
	_check(game.adversaries.is_empty(),
			"and he is no longer somebody who walks back onto a mission")
	_check(not game.on_bounty(), "the campaign is back at the garrison")
	# --- and whoever went is off the next main mission ------------------------
	_check(game.is_resting(int(staged.hunter.id)),
			"the soldier who went is resting")
	var deploying: Array = game.deployment(3)
	var went_again := false
	for s2: Dictionary in deploying:
		if int(s2.id) == int(staged.hunter.id):
			went_again = true
	_check(not went_again, "...and is not in the next mission's deployment")
	_check(deploying.size() == 3,
			"...which still fields a full party (%d)" % deploying.size())
	game.commit_mission()
	_check(not game.is_resting(int(staged.hunter.id)),
			"one main mission later, they are available again")

	# The fallback: a campaign too thin to bench anybody must not deploy short.
	# This is the case that would otherwise turn a side activity into a
	# soft-lock, so it is checked rather than trusted.
	var thin: Array = []
	for s3: Dictionary in game.rifle_candidates():
		thin.append(int(s3.id))
	game.resting_ids = thin.duplicate()
	var forced: Array = game.deployment(3)
	_check(forced.size() == 3,
			"with everybody resting, the mission still fields three (%d)"
			% forced.size())
	game.resting_ids = []
	_check((_bounty.call("offers", game.campaign_seed, game.adversaries,
			game.bounties_done) as Array).is_empty(),
			"...and the board no longer posts him")

	# --- the other two endings ------------------------------------------------
	for ending in ["surrendered", "killed"]:
		var st := _stage(game, 1)
		var b2: Node = await _battle()
		await b2._reveal_bounty_target("the test said so")
		if b2.bounty_target == null:
			_check(false, "%s: expected the target to be revealed" % ending)
			await _drop(b2)
			continue
		if ending == "surrendered":
			b2.selected = b2.bounty_hunter
			b2.bounty_hunter.cell = b2.bounty_target.cell + Vector2i(1, 0)
			game.award_stat(int(st.hunter.id), "presence", 20)
			await b2._try_parley("surrender")
		else:
			# However he dies, the bounty is settled the same way - which is why
			# it is booked in _on_unit_died rather than in the shooting code.
			b2.bounty_target.hp = 0
			b2._on_unit_died(b2.bounty_target)
		_check(b2.bounty_outcome == ending,
				"%s: the mission books it as %s (%s)"
				% [ending, ending, b2.bounty_outcome])
		_check(b2._objective_complete(0), "%s: ...and that ends it" % ending)
		await _drop(b2)

	# --- what an informant is worth afterwards --------------------------------
	game.clear_bounty()
	game.informants = [{"id": 41, "name": "Vekh 41", "settlement": "Kessit",
			"turned_by": 1}]
	game.current_level = 0
	var mission: Node = await _battle()
	_check(not game.on_bounty(), "a campaign mission, not a bounty")
	var marked: int = mission.board.intel_cells.size()
	_check(marked > 0, "the informant gives positions away before the first shot (%d)"
			% marked)
	_check(marked <= mission.living_soldiers(TEAM_GOBLIN).size(),
			"...but never more than there are people to give away")
	await _drop(mission)
	game.informants = []


# --- 7. the manhunt runs in real time until he is found -----------------------

## A bounty does not open as a battle. The party walks into somewhere people
## live and asks after a man; whether it becomes a firefight at all is decided
## by how that goes. This checks the mode itself: that the tactical layer is
## genuinely not running, that nothing else is scheduled to walk on, and that
## finding him is what hands the board over to it.
func _test_the_manhunt() -> void:
	print("
[7] the manhunt runs in real time until he is found")
	_keep_save()
	var game: Node = root.get_node_or_null("/root/Game")
	if game == null:
		_check(false, "the Game autoload is up (it is not - section 7 cannot run)")
		return
	_stage(game)
	var battle: Node = await _battle()

	_check(battle.roaming, "the board opens in real time, not on a turn")
	_check(battle.bounty_target == null, "...with nobody found yet")
	# The man's own warband is the only arrival a manhunt gets. Campaign
	# returners walking onto it would put strangers next to the people the
	# party is trying to talk to.
	_check(battle._returners_due.is_empty(),
			"nobody else who survived is scheduled to walk on")
	_check(battle.end_turn_button.disabled,
			"there is no turn to end while the party is still walking")
	_check(battle.suppress_button.disabled, "...and no gun to open up with")

	# --- walking -------------------------------------------------------------
	# Deliberately untyped: naming Unit here would compile Unit.gd before the
	# autoloads exist and it would fail to resolve Game, taking this whole file
	# down with a type error twenty frames away from the cause.
	var leader = battle.bounty_hunter
	_check(leader != null and battle.selected == leader,
			"the man the player chose is the one being walked")
	if leader == null:
		await _drop(battle)
		return
	var was_cell: Vector2i = leader.cell
	var was_pos: Vector2 = leader.position
	# Step him east until the cell changes, the way a held key would.
	for i in 90:
		battle._roam_step(leader, Vector2(4.0, 0.0))
		if leader.cell != was_cell:
			break
	_check(leader.position != was_pos, "he moves in real time")
	_check(leader.cell != was_cell,
			"...and his cell follows him, because every reach test is in cells")
	_check(battle.board.is_walkable(leader.cell), "...and never off walkable ground")

	# A step into somebody is refused rather than walked through. Stood one
	# cell west of a resident and pushed east hard enough to cross the boundary.
	var blocked := false
	for who in battle.residents:
		if not is_instance_valid(who):
			continue
		var west: Vector2i = who.cell + Vector2i(-1, 0)
		if not battle.board.in_bounds(west) or not battle.board.is_walkable(west):
			continue
		if battle.unit_at(west) != null:
			continue
		leader.position = battle.board.cell_to_global(west)
		leader.cell = west
		for i in 60:
			battle._roam_step(leader, Vector2(6.0, 0.0))
		blocked = leader.cell != who.cell
		break
	_check(blocked, "and does not walk through the people who live here")

	# --- finding him ---------------------------------------------------------
	await battle._reveal_bounty_target("the harness went and looked")
	_check(battle.bounty_target != null, "he can be found")
	_check(battle.parley_dialog != null and battle.parley_dialog.visible,
			"...and being found opens the conversation by itself")
	_check(battle.roaming,
			"...with the board still out of turns while it is up")

	# --- and the three ways it ends ------------------------------------------
	battle._on_dialog_choice("fight")
	_check(not battle.parley_dialog.visible, "choosing the rifle closes it")
	_check(not battle.roaming, "...and hands the board to the tactical layer")
	_check(not battle.end_turn_button.disabled,
			"...which has its orders back")
	for scout in battle.living_soldiers(TEAM_SCOUT):
		_check(scout.position == battle.board.cell_to_global(scout.cell),
				"everybody is back on the grid they will fight on")
		break
	await _drop(battle)
