extends SceneTree

## The per-class perk trees, end to end:
##   1. table integrity - every class offers exactly two known perks at every
##      perk gate 1-4, and every blurb fits the fixed-width choice buttons
##   2. commit_mission queues one choice per crossed perk gate, per class -
##      and stamps the career level the XP bought
##   3. apply_progression / Unit stamps each perk's stat and gate effects,
##      plus the per-level career bonuses and the once-only accuracy cap
##   4. a real Battle.tscn boot on a crafted roster: the ability buttons, the
##      quick-hands reload, walking fire's gate, grenadier's frag, Rally,
##      Field Dressing, Inspiration, Flanker/Executioner, and Called Shot
##      against a full-cover goblin - plus that a resolved round takes exactly
##      the HP Rules.damage_for promised for it before the trigger, which is
##      the preview/resolver agreement measured on the live resolver

##   5. Untouchable refuses the first killing blow and honours the second
##
## Any real save is backed up in _init() - BEFORE the Game autoload's _ready
## can load it - and restored on the way out, so this is safe to run on a
## machine someone is actually playing on.
##
## NOTHING from scripts/ is preloaded, deliberately - the same `-s` trap
## test_hero_gameover.gd documents: preloading Game.gd here would compile
## Unit.gd before the autoloads exist and cache the broken script. Everything
## is load()ed after the first frame, once the autoloads are up.
##
## Hit rolls are made deterministic by seeding battle._rules_rng immediately
## before each resolved shot with a seed whose first roll is known to land
## under the quoted chance (hit_chance clamps at 99, so an unseeded miss is
## always possible). That is exact rather than hopeful because the rules
## stream carries nothing but hit rolls - every cosmetic draw goes to
## _vis_rng - so the very next number out of it is the one the shot reads.
##
## Run: godot --headless --path . -s tools/test_progression.gd

const SAVE_PATH := "user://campaign.json"  # mirrors Game.SAVE_PATH (not preloaded)
const BACKUP_PATH := "user://campaign.json.testbak"  # crash-proof copy, see _init

# Raw ordinals, matching test_save_load.gd's style.
const KIND_SCOUT := 0
const KIND_TEAM_LEAD := 1
const KIND_MACHINEGUNNER := 2
const KIND_HERO := 9
const KIND_GRENADIER := 10
const TEAM_SCOUT := 0
const TEAM_GOBLIN := 1
const STATE_GAME_OVER := 3  # Battle.State
const MODE_AUTO := 2        # Battle.FireMode
const AIM_CALLED_SHOT := 5  # Battle.AimMode
const COVER_FULL := 2       # Board.CoverLevel

var _failed := false
var _had_save := false
var _backup := ""


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    %s" % label)
	else:
		printerr("  FAIL  %s" % label)
		_failed = true


## The backup lives on disk, not just in this script's memory. A parse error
## or a failed assertion can abort the run before _finish() gets to put the
## campaign back, and a copy held only in a String dies with the process -
## which is exactly how a real campaign was lost once. A sidecar survives,
## and the next run below restores from it before doing anything else.
func _init() -> void:
	_recover_stale_backup()
	_had_save = FileAccess.file_exists(SAVE_PATH)
	if _had_save:
		var bf := FileAccess.open(SAVE_PATH, FileAccess.READ)
		_backup = bf.get_as_text()
		bf.close()
		var wf := FileAccess.open(BACKUP_PATH, FileAccess.WRITE)
		wf.store_string(_backup)
		wf.close()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
		print("backed up existing save (%d bytes)" % _backup.length())
	_run()


## A backup still on disk means a previous run died before restoring it. Put
## it back rather than letting this run's fixture bury the campaign for good.
func _recover_stale_backup() -> void:
	if not FileAccess.file_exists(BACKUP_PATH):
		return
	var bf := FileAccess.open(BACKUP_PATH, FileAccess.READ)
	var text := bf.get_as_text()
	bf.close()
	var rf := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	rf.store_string(text)
	rf.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BACKUP_PATH))
	print("recovered a save left behind by an interrupted run (%d bytes)" % text.length())


## A seed whose FIRST randi_range(1, 100) roll lands at or under `roll_max`,
## so a shot resolved right after re-seeding is a guaranteed hit.
func _seed_for_roll(roll_max: int) -> int:
	var rng := RandomNumberGenerator.new()
	for candidate in range(1, 20000):
		rng.seed = candidate
		if rng.randi_range(1, 100) <= roll_max:
			return candidate
	return 1


func _run() -> void:
	await process_frame  # let the autoloads finish _ready()
	var game: Node = root.get_node("/root/Game")

	# The ordinals every save on disk is written in, and Game.CLASS_PERK_RANKS is
	# keyed by. Inserting a kind mid-enum would renumber every soldier in every
	# campaign - a scout would load as a goblin - and nothing else in the game
	# would notice. Read off the script rather than named, for the header's
	# reason: `Unit` in source compiles Unit.gd before the autoloads exist.
	print("\n[0] the Kind ordinals the saves are written in")
	var ordinals: Dictionary = (load("res://scripts/Unit.gd") as GDScript) \
			.get_script_constant_map()["Kind"]
	_check(int(ordinals.SCOUT) == KIND_SCOUT
			and int(ordinals.TEAM_LEAD) == KIND_TEAM_LEAD
			and int(ordinals.MACHINEGUNNER) == KIND_MACHINEGUNNER,
			"SCOUT 0, TEAM_LEAD 1, MACHINEGUNNER 2 (got %d/%d/%d)"
			% [ordinals.SCOUT, ordinals.TEAM_LEAD, ordinals.MACHINEGUNNER])
	_check(int(ordinals.CIVILIAN) == 8 and int(ordinals.HERO) == KIND_HERO,
			"CIVILIAN 8, HERO 9 (got %d/%d)" % [ordinals.CIVILIAN, ordinals.HERO])

	print("\n[1] table integrity: 2 known choices per class per gate, short blurbs")
	for kind in [KIND_SCOUT, KIND_MACHINEGUNNER, KIND_HERO]:
		for gate_level: int in Career.PERK_LEVELS:
			var gate := Career.perk_gate(gate_level)
			var choices: Array = game.perk_choices(kind, gate)
			_check(choices.size() == 2,
					"kind %d level %d offers 2 (got %d)"
					% [kind, gate_level, choices.size()])
			for perk: String in choices:
				_check(game.PERKS.has(perk),
						"kind %d level %d '%s' exists in PERKS"
						% [kind, gate_level, perk])
	var long_blurbs: Array[String] = []
	for key: String in game.PERKS:
		if str(game.PERKS[key].blurb).length() > 48:
			long_blurbs.append(key)
	_check(long_blurbs.is_empty(), "every blurb <= 48 chars (over: %s)" % [long_blurbs])
	for key in ["marksman", "sprinter", "sentinel", "hustle"]:
		_check(game.PERKS.has(key), "legacy perk '%s' still accepted" % key)
	_check(game.perk_choices(KIND_TEAM_LEAD, 1) == game.perk_choices(KIND_HERO, 1),
			"retired TEAM_LEAD answers with the hero's tree")
	_check(game.perk_choices(3, 1).is_empty(), "goblins have no tree")

	print("\n[2] commit_mission stamps levels and queues one choice per crossed gate")
	var g: Node = (load("res://scripts/Game.gd") as GDScript).new()
	g.roster = [
		{"id": 1, "surname": "A", "kind": KIND_SCOUT, "xp": 337, "level": 1,
				"perks": [] as Array, "alive": true},   # level 50: all 4 gates
		{"id": 2, "surname": "B", "kind": KIND_MACHINEGUNNER, "xp": 42, "level": 1,
				"perks": [] as Array, "alive": true},   # level 15: gates 5, 15
		{"id": 3, "surname": "C", "kind": KIND_HERO, "xp": 7, "level": 1,
				"perks": [] as Array, "alive": true},   # level 5: gate 5
		{"id": 4, "surname": "D", "kind": KIND_SCOUT, "xp": 3, "level": 1,
				"perks": [] as Array, "alive": true},   # level 3: no gate
		{"id": 5, "surname": "E", "kind": KIND_SCOUT, "xp": 337, "level": 1,
				"perks": [] as Array, "alive": false},  # the dead earn nothing
	]
	g._next_id = 6
	g.commit_mission()
	var queued := {}
	var gate_levels_of_1: Array = []
	for p: Dictionary in g.pending_promotions:
		var id: int = int(p.id)
		queued[id] = int(queued.get(id, 0)) + 1
		if id == 1:
			gate_levels_of_1.append(int(p.level))
	_check(int(queued.get(1, 0)) == 4, "scout xp337 queues 4 (got %s)" % queued.get(1, 0))
	_check(gate_levels_of_1 == [5, 15, 30, 50],
			"...and the queue holds the gate levels, sparse (%s)" % [gate_levels_of_1])
	_check(int(queued.get(2, 0)) == 2, "gunner xp42 queues 2 (got %s)" % queued.get(2, 0))
	_check(int(queued.get(3, 0)) == 1, "hero xp7 queues 1 (got %s)" % queued.get(3, 0))
	_check(not queued.has(4), "xp3 queues nothing")
	_check(not queued.has(5), "the dead queue nothing")
	_check(int((g.roster[0] as Dictionary).level) == 50
			and int((g.roster[3] as Dictionary).level) == 3
			and int((g.roster[4] as Dictionary).level) == 1,
			"levels stamped: 50 for the living, 3 below the gates, the dead untouched")
	g.free()

	print("\n[3] apply_progression and Unit: every stat and gate effect")
	var unit_scene := load("res://scenes/Unit.tscn") as PackedScene
	var plain_scout: Node2D = _mk(unit_scene, KIND_SCOUT, [])
	var sprinter: Node2D = _mk(unit_scene, KIND_SCOUT, ["sprinter"])
	var ranger: Node2D = _mk(unit_scene, KIND_SCOUT, ["ranger"])
	var snapper: Node2D = _mk(unit_scene, KIND_SCOUT, ["snap_burst"])
	_check(plain_scout.move_range == 5, "scout baseline move 5")
	_check(sprinter.move_range == 6, "sprinter move 6")
	_check(ranger.move_range == 6 and ranger.attack_range == 5,
			"ranger move 6, range 5 (got %d/%d)" % [ranger.move_range, ranger.attack_range])
	_check(plain_scout.burst_requires_still() and not snapper.burst_requires_still(),
			"snap_burst lifts the bracing gate, baseline keeps it")
	var plain_mg: Node2D = _mk(unit_scene, KIND_MACHINEGUNNER, [])
	var bipod: Node2D = _mk(unit_scene, KIND_MACHINEGUNNER, ["bipod"])
	var mule: Node2D = _mk(unit_scene, KIND_MACHINEGUNNER, ["pack_mule"])
	var sweep: Node2D = _mk(unit_scene, KIND_MACHINEGUNNER, ["wide_sweep"])
	var sentinel: Node2D = _mk(unit_scene, KIND_MACHINEGUNNER, ["sentinel"])
	var keeper: Node2D = _mk(unit_scene, KIND_MACHINEGUNNER, ["protective_fire"])
	_check(plain_mg.overwatch_rounds() == 2 and bipod.overwatch_rounds() == 3,
			"bipod overwatch rounds 2 -> 3")
	_check(mule.mag_size == 8 and mule.ammo == 8,
			"pack_mule mag 8 and ammo re-derived (got %d/%d)" % [mule.mag_size, mule.ammo])
	_check(plain_mg.suppress_radius() == 2 and sweep.suppress_radius() == 3,
			"wide_sweep beaten zone 2 -> 3")
	_check(sentinel.arc_half == 2 and plain_mg.arc_half == 1, "sentinel widens the arc")
	plain_mg.set_overwatch(true)
	plain_mg.start_turn()
	keeper.set_overwatch(true)
	keeper.start_turn()
	_check(not plain_mg.overwatching and keeper.overwatching,
			"protective_fire carries unfired overwatch over; baseline expires")
	keeper.set_done(true)
	_check(not keeper.overwatching, "spending the activation breaks the carried watch")
	keeper.set_done(true)
	keeper.set_overwatch(true)
	_check(keeper.overwatching, "the normal overwatch order (done, then armed) still stands")
	var willed: Node2D = _mk(unit_scene, KIND_HERO, ["iron_will"])
	var pockets: Node2D = _mk(unit_scene, KIND_HERO, ["deep_pockets"])
	_check(willed.max_hp == 12 and willed.hp == 12,
			"iron_will hp 10 -> 12, deployed whole (got %d/%d)" % [willed.hp, willed.max_hp])
	_check(pockets.mag_size == 5 and pockets.ammo == 5,
			"deep_pockets mag 3 -> 5, ammo re-derived (got %d/%d)"
			% [pockets.mag_size, pockets.ammo])
	plain_scout.suppress()
	sprinter.suppress(3)
	_check(plain_scout.suppression == 2 and sprinter.suppression == 3,
			"suppress() defaults to 2, takes 3 for locked belts")
	sprinter.suppress()
	_check(sprinter.suppression == 3, "a fresh shorter pin never trims a longer one")
	sprinter.rally(10)
	_check(sprinter.suppression == 0 and sprinter.rally_bonus == 10,
			"rally() unpins and steadies")
	sprinter.start_turn()
	_check(sprinter.rally_bonus == 0, "the steadying fades on the soldier's own turn")
	plain_scout.hp = 3
	plain_scout.heal(3)
	_check(plain_scout.hp == 6, "heal(3) heals 3 (got %d)" % plain_scout.hp)
	plain_scout.heal(99)
	_check(plain_scout.hp == plain_scout.max_hp, "heal clamps at max_hp")

	print("\n  the career ladder on a unit: one +1 every level, capped once")
	var base_acc: int = plain_scout.accuracy
	var base_hp: int = plain_scout.max_hp
	var cap: int = int(game.ACCURACY_CAP)
	var lv2: Node2D = _mk_level(unit_scene, KIND_SCOUT, 2)
	var lv10: Node2D = _mk_level(unit_scene, KIND_SCOUT, 10)
	var lv11: Node2D = _mk_level(unit_scene, KIND_SCOUT, 11)
	var lv90: Node2D = _mk_level(unit_scene, KIND_HERO, 90)
	_check(lv2.accuracy == mini(base_acc + 1, cap) and lv2.max_hp == base_hp,
			"level 2 pays +1 accuracy and nothing else (got %d/%d)"
			% [lv2.accuracy, lv2.max_hp])
	_check(lv10.accuracy == mini(base_acc + 5, cap) and lv10.max_hp == base_hp + 4
			and lv10.hp == lv10.max_hp,
			"level 10 is +5 acc / +4 HP, deployed whole (got %d/%d)"
			% [lv10.accuracy, lv10.max_hp])
	_check(lv11.accuracy == mini(base_acc + 5, cap) and lv11.max_hp == base_hp + 5,
			"level 11 adds the odd level's HP point (got %d/%d)"
			% [lv11.accuracy, lv11.max_hp])
	_check(lv90.accuracy == cap,
			"a level 90 hero is capped at %d (got %d)" % [cap, lv90.accuracy])
	for u in [plain_scout, sprinter, ranger, snapper, plain_mg, bipod, mule,
			sweep, sentinel, keeper, willed, pockets, lv2, lv10, lv11, lv90]:
		u.free()

	print("\n[4] boot Battle.tscn on a crafted roster (level 1, headless)")
	game.roster = [
		{"id": 1, "surname": "Akai", "kind": KIND_HERO, "xp": 40, "level": 14,
				"perks": ["called_shot", "one_shot", "rally", "untouchable",
						"inspiration"] as Array, "alive": true},
		{"id": 2, "surname": "HARGREAVE", "kind": KIND_MACHINEGUNNER, "xp": 0,
				"level": 1, "perks": ["grenadier", "walking_fire"] as Array,
				"alive": true},
		{"id": 3, "surname": "VANCE", "kind": KIND_SCOUT, "xp": 0, "level": 1,
				"perks": ["field_dressing", "quick_hands"] as Array, "alive": true},
		{"id": 4, "surname": "QUINN", "kind": KIND_SCOUT, "xp": 0, "level": 1,
				"perks": ["flanker", "executioner"] as Array, "alive": true},
		{"id": 5, "surname": "ORTIZ", "kind": KIND_SCOUT, "xp": 0, "level": 1,
				"perks": [] as Array, "alive": true},
	]
	game._next_id = 6
	game.pending_promotions = []
	game.current_level = 0
	game.current_operation = 0
	var battle: Node = (load("res://scenes/Battle.tscn") as PackedScene).instantiate()
	root.add_child(battle)
	await process_frame
	await process_frame

	var hero: Node2D = null
	var mg: Node2D = null
	var medic: Node2D = null
	var flanker: Node2D = null
	var plain: Node2D = null
	for unit in battle.living_soldiers(TEAM_SCOUT):
		match str(unit.surname):
			"Akai": hero = unit
			"HARGREAVE": mg = unit
			"VANCE": medic = unit
			"QUINN": flanker = unit
			"ORTIZ": plain = unit
	_check(hero != null and mg != null and medic != null and flanker != null
			and plain != null, "all five crafted soldiers deployed")
	if hero == null or mg == null or medic == null or flanker == null or plain == null:
		_finish()
		return

	_check(battle.frags_left == game.frags + 1,
			"grenadier adds one frag to the pool (got %d of %d+1)"
			% [battle.frags_left, game.frags])

	battle.select(hero)
	_check(battle.ability_1_button.visible
			and battle.ability_1_button.text == "Called Shot"
			and battle.ability_2_button.visible
			and battle.ability_2_button.text == "Rally",
			"hero's two ability buttons show Called Shot (Q) and Rally (T)")
	battle.select(medic)
	_check(battle.ability_1_button.visible
			and battle.ability_1_button.text == "Patch Up"
			and not battle.ability_2_button.visible,
			"medic shows Patch Up alone")
	battle.select(plain)
	_check(not battle.ability_1_button.visible and not battle.ability_2_button.visible,
			"a soldier with no actives shows no ability buttons")

	print("
  the launcher, against the real board and the real gate")
	# _can_target_throw is the one line the launcher change actually altered,
	# and no Rules-level test can see it: revert that line to a flat constant
	# and every arithmetic assertion in test_rules.gd still passes. So ask the
	# booted Battle itself, on the level it is standing on.
	#
	# Two units differing ONLY in kind, on the same cell, so board, geometry and
	# line of sight are identical and the kind is the whole experiment. The
	# grenadier is synthesised beside the squad rather than deployed with it:
	# the crafted roster above is shaped for the ability-button checks, and
	# swapping a member would quietly change what those assert.
	var throw_scene := load("res://scenes/Unit.tscn") as PackedScene
	var throw_script := load("res://scripts/Rules.gd") as GDScript
	var throw_rules := throw_script.get_script_constant_map()
	var thrown_reach := int(throw_rules["THROW_RANGE"])
	var launched_reach := int(throw_rules["LAUNCHER_RANGE"])
	var launcher: Node2D = _mk(throw_scene, KIND_GRENADIER, [])
	launcher.cell = plain.cell
	var only_launcher: Array[Vector2i] = []
	var only_rifleman: Array[Vector2i] = []
	var near_disagreements := 0
	var wrong_band := 0
	for y in battle.board.size.y:
		for x in battle.board.size.x:
			var c := Vector2i(x, y)
			var by_rifle: bool = battle._can_target_throw(plain, c)
			var by_launcher: bool = battle._can_target_throw(launcher, c)
			if by_rifle == by_launcher:
				continue
			var d: int = Board.manhattan(plain.cell, c)
			if by_rifle:
				only_rifleman.append(c)
				continue
			only_launcher.append(c)
			if d <= thrown_reach:
				near_disagreements += 1
			elif d > launched_reach:
				wrong_band += 1
	_check(only_rifleman.is_empty(),
			"the launcher reaches everywhere an arm does (rifleman-only: %s)"
			% [only_rifleman.slice(0, 3)])
	_check(near_disagreements == 0,
			"...they agree on every cell within %d tiles" % thrown_reach)
	_check(wrong_band == 0,
			"...and she reaches nothing beyond %d" % launched_reach)
	_check(not only_launcher.is_empty(),
			"the launcher buys real ground on this map (%d cell(s) at %d-%d tiles)"
			% [only_launcher.size(), thrown_reach + 1, launched_reach])
	launcher.free()

	print("\n  walking fire and quick hands")
	mg.moved = true
	_check(battle._can_use_mode(mg, MODE_AUTO), "walking_fire arms full auto after moving")
	_check(battle._mode_accuracy(mg, MODE_AUTO)
					== battle.AUTO_ACCURACY + battle.WALKING_FIRE_ACCURACY,
			"...at auto's %d plus walking's %d (got %d)" % [battle.AUTO_ACCURACY,
					battle.WALKING_FIRE_ACCURACY, battle._mode_accuracy(mg, MODE_AUTO)])
	mg.moved = false
	_check(battle._mode_accuracy(mg, MODE_AUTO) == battle.AUTO_ACCURACY,
			"...and auto's own %d from a firing position" % battle.AUTO_ACCURACY)
	battle.select(medic)
	medic.spend_ammo()
	await battle._try_reload()
	_check(medic.ammo == medic.mag_size and not medic.moved,
			"quick_hands reloads without giving up the move")

	print("\n  field dressing")
	medic.hp = medic.max_hp - 4
	battle.select(medic)
	battle._use_ability(0)
	_check(medic.hp == medic.max_hp - 1 and medic.acted and medic.field_dressing_used,
			"patch up heals 3 and costs the shot (hp %d/%d)" % [medic.hp, medic.max_hp])
	medic.acted = false
	battle._use_ability(0)
	_check(medic.hp == medic.max_hp - 1, "the one charge is spent - no second heal")

	print("\n  rally")
	plain.cell = hero.cell + Vector2i(1, 0)  # inside RALLY_RANGE of the hero
	var goblin: Node2D = battle.living_units(TEAM_GOBLIN)[0]
	goblin.cell = plain.cell + Vector2i(2, 0)
	goblin.set_facing_sector(_facing_covering(battle, goblin, plain))
	var base_chance: int = battle.hit_chance(plain, goblin, -20)
	plain.suppress()
	_check(plain.is_suppressed(), "the ally starts pinned")
	battle.select(hero)
	battle._use_ability(1)
	_check(not plain.is_suppressed() and plain.rally_bonus == 10,
			"rally unpins the ally within 4 tiles and steadies him")
	_check(hero.acted and hero.rally_used, "rally costs the hero's attack and charge")
	_check(battle.hit_chance(plain, goblin, -20) == base_chance + 10,
			"the +10 is live in hit_chance")
	battle.select(hero)
	_check(battle.ability_2_button.text == "Rally (spent)"
			and battle.ability_2_button.disabled, "the button wears the spent charge")
	plain.start_turn()
	_check(battle.hit_chance(plain, goblin, -20) == base_chance,
			"...and fades on the soldier's own next turn")

	print("\n  inspiration")
	var near_chance: int = battle.hit_chance(plain, goblin, -20)
	var hero_home: Vector2i = hero.cell
	hero.cell = hero_home + Vector2i(9, 4)  # out of the 4-tile aura
	_check(battle.hit_chance(plain, goblin, -20) == near_chance - 5,
			"a living perked hero within 4 tiles is worth +5")
	hero.cell = hero_home

	print("\n  flanker and executioner")
	flanker.cell = goblin.cell + Vector2i(1, 0)
	goblin.set_facing_sector(_facing_flanked_by(battle, goblin, flanker))
	_check(battle._is_flanking(flanker, goblin), "the test shot is a flank")
	var with_perk: int = battle.hit_chance(flanker, goblin, -30)
	flanker.perks = []
	var without_perk: int = battle.hit_chance(flanker, goblin, -30)
	flanker.perks = ["flanker", "executioner"]
	_check(with_perk == without_perk + 10,
			"flanker adds 10 on top of the flank bonus (%d vs %d)"
			% [with_perk, without_perk])
	goblin.hp = 4
	# What the panel would promise for this exact shot, read BEFORE the trigger
	# and out of the same function the panel reads. Checking the HP that
	# actually left the goblin against it is preview-vs-resolution agreement
	# measured on the live resolver - through _fire_round's effects, awaits and
	# seeded roll - which tools/test_rules.gd cannot reach from a bare board.
	# Rules is load()ed rather than named for the -s reason in the header.
	var rules := load("res://scripts/Rules.gd") as GDScript
	var promised: int = rules.call("damage_for", battle.board, flanker, goblin)
	var hp_before: int = goblin.hp
	battle._rules_rng.seed = _seed_for_roll(battle.hit_chance(flanker, goblin))
	await battle._fire_round(flanker, goblin)
	_check(goblin.hp == 1,
			"executioner's flanking round deals 3 (2+1) - hp 4 -> %d" % goblin.hp)
	_check(hp_before - goblin.hp == promised,
			"...and the HP that left him is exactly what damage_for promised (%d)"
			% promised)

	print("\n  called shot against full cover")
	var mark_and_from := _full_cover_shot(battle)
	_check(not mark_and_from.is_empty(), "found a full-cover firing solution on the map")
	if not mark_and_from.is_empty():
		# Teleport a goblin into the pocket - the map's geometry stays real,
		# only the actors are placed.
		var mark: Node2D = battle.living_units(TEAM_GOBLIN)[0]
		mark.cell = mark_and_from.goblin_cell
		hero.cell = mark_and_from.from
		mark.set_facing_sector(_facing_covering(battle, mark, hero))
		_check(battle.effective_cover(hero, mark) == COVER_FULL,
				"the goblin is genuinely in full cover from the hero")
		hero.moved = false
		hero.acted = false
		battle.select(hero)
		battle._use_ability(0)
		_check(int(battle.aim_mode) == AIM_CALLED_SHOT, "Q arms the called-shot aim mode")
		battle._cancel_aim()
		mark.hp = 6  # only an unhalved 4+2 kills through this
		var ammo_before: int = hero.ammo
		battle._rules_rng.seed = _seed_for_roll(battle.hit_chance(hero, mark))
		await battle.do_called_shot(hero, mark)
		_check(not mark.is_alive(),
				"called shot killed through full cover for 6 (halved would leave 3)")
		_check(hero.ammo == ammo_before - 1, "called shot spent one round")
		_check(hero.acted and hero.moved, "called shot ends the hero's turn")

	print("\n[5] untouchable refuses the first killing blow, honours the second")
	hero.take_damage(999)
	_check(hero.hp == 1 and hero.is_alive(), "the first lethal hit leaves him at 1 HP")
	_check(int(battle.state) != STATE_GAME_OVER, "and the battle carries on")
	hero.take_damage(999)
	_check(not hero.is_alive(), "the second lethal hit lands for real")
	_check(int(battle.state) == STATE_GAME_OVER, "hero death still ends the battle")
	_check(battle.result_label.text == "RODAR AKAI HAS FALLEN",
			"the verdict is the hero's (got '%s')" % battle.result_label.text)

	_finish()


## Instantiate a Unit, set it up as `kind`, and stamp a level-1 soldier with
## `perks` on it. Lives outside the tree - Unit.setup guards for that.
func _mk(unit_scene: PackedScene, kind: int, perks: Array) -> Node2D:
	var unit: Node2D = unit_scene.instantiate()
	unit.setup(kind, Vector2i(2, 2))
	unit.apply_progression({"id": 1, "surname": "TEST", "kind": kind, "xp": 0,
			"level": 1, "perks": perks, "alive": true})
	return unit


## The same, but a perkless soldier at a chosen career level.
func _mk_level(unit_scene: PackedScene, kind: int, level: int) -> Node2D:
	var unit: Node2D = unit_scene.instantiate()
	unit.setup(kind, Vector2i(2, 2))
	unit.apply_progression({"id": 1, "surname": "TEST", "kind": kind, "xp": 0,
			"level": level, "perks": [] as Array, "alive": true})
	return unit


## A facing sector for `target` that keeps `shooter` inside its front arc
## (covered - not a flank). -1 never happens on a 360-degree sweep.
func _facing_covering(battle: Node, target: Node2D, shooter: Node2D) -> int:
	for sector in 8:
		target.facing_sector = sector
		if not battle._is_flanking(shooter, target):
			return sector
	return -1


## The opposite: a facing that leaves `shooter` squarely on the flank.
func _facing_flanked_by(battle: Node, target: Node2D, shooter: Node2D) -> int:
	for sector in 8:
		target.facing_sector = sector
		if battle._is_flanking(shooter, target):
			return sector
	return -1


## A cell pair {goblin_cell, from} where a shot from `from` crosses FULL
## cover on its way in: engageable, within 3 tiles (no long-shot penalty),
## both cells free and walkable. Searched over the whole board so the map's
## own rocks decide - returns {} only if the level genuinely has no pocket.
func _full_cover_shot(battle: Node) -> Dictionary:
	var board: Node2D = battle.board
	for y in range(board.size.y):
		for x in range(board.size.x):
			var g := Vector2i(x, y)
			if not board.is_walkable(g) or battle.unit_at(g) != null:
				continue
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					var dist: int = absi(dx) + absi(dy)
					if dist == 0 or dist > 3:
						continue
					var from: Vector2i = g + Vector2i(dx, dy)
					if not board.in_bounds(from) or not board.is_walkable(from) \
							or battle.unit_at(from) != null:
						continue
					if not board.can_engage(from, g):
						continue
					if int(board.cover_between(from, g)) == COVER_FULL:
						return {"goblin_cell": g, "from": from}
	return {}


func _finish() -> void:
	_test_named_kestrels()
	_test_specialists()
	_test_deployment()
	_test_gear_rollback()

	if _had_save:
		var rf := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		rf.store_string(_backup)
		rf.close()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(BACKUP_PATH))
		print("\nrestored the original save")
	else:
		var err := DirAccess.remove_absolute(
				ProjectSettings.globalize_path(SAVE_PATH))
		print("\nremoved the test save (%s)" % error_string(err))
	print("\nRESULT: ", "FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)


# --- 6. the Kestrels who are people rather than postings ---------------------

func _test_named_kestrels() -> void:
	print("\n[6] named Kestrels, and what permadeath means for them")
	var game: Node = root.get_node("/root/Game")
	var consts: Dictionary = (load("res://scripts/Game.gd") as GDScript) \
			.get_script_constant_map()
	var named: Dictionary = consts["NAMED_KESTRELS"]
	var given: Dictionary = consts["GIVEN_NAMES"]
	var surnames: Array = consts["SURNAMES"]

	# The invariant the old code kept by hand for "Akai" alone, now swept: a
	# named person must never be mintable by the random pool, or the campaign
	# could field two Josen Marrs.
	var collisions: Array[String] = []
	var missing_given: Array[String] = []
	for kind: int in named:
		for name: String in named[kind]:
			if surnames.has(name):
				collisions.append(name)
			if not given.has(name):
				missing_given.append(name)
	_check(collisions.is_empty(),
			"no named Kestrel is also in the random pool (%s)" % [collisions])
	_check(missing_given.is_empty(),
			"every named Kestrel has a given name (%s)" % [missing_given])
	_check(given.size() == _named_total(named),
			"and GIVEN_NAMES has no entries for people who do not exist (%d/%d)"
			% [given.size(), _named_total(named)])

	# Formation order: the named ones fill their kind's slots first.
	game.roster = []
	game._next_id = 1
	game.ensure_roster(Levels.LEVELS[0])
	var by_kind := {}
	for soldier: Dictionary in game.roster:
		var k: int = int(soldier.kind)
		if not by_kind.has(k):
			by_kind[k] = []
		by_kind[k].append(str(soldier.surname))
	for kind: int in named:
		var first: String = str(named[kind][0])
		_check((by_kind.get(kind, []) as Array).has(first),
				"%s formed into kind %d (%s)" % [first, kind, by_kind.get(kind, [])])
	_check(game.is_named_kestrel(game.roster[0])
			and game.full_name(game.roster[0]).contains(" "),
			"full_name reads as a person (%s)" % game.full_name(game.roster[0]))

	# The weight of it: a named Kestrel who dies does NOT come back, and the
	# replacement is a stranger off the levy post.
	var josen: Dictionary = {}
	for soldier: Dictionary in game.roster:
		if str(soldier.surname) == "Marr":
			josen = soldier
	_check(not josen.is_empty(), "Josen Marr is on the roster")
	josen["alive"] = false
	var before: int = game.roster.size()
	game.ensure_roster(Levels.LEVELS[0])
	var marrs := 0
	for soldier: Dictionary in game.roster:
		if str(soldier.surname) == "Marr":
			marrs += 1
	_check(marrs == 1, "after his death there is still exactly one Marr (%d)" % marrs)
	_check(game.roster.size() == before,
			"and ensure_roster did not quietly recruit over him (%d)"
			% game.roster.size())

	# The garrison DOES replace him - with somebody else.
	var replacements: Array = game.recruit_to_strength(Levels.LEVELS[0])
	_check(replacements.size() == 1,
			"the levy post offers one replacement (%d)" % replacements.size())
	if replacements.size() == 1:
		var who: String = str((replacements[0] as Dictionary).surname)
		_check(who != "Marr" and not game.is_named_kestrel(replacements[0]),
				"and it is a stranger, not Josen again (%s)" % who)


func _named_total(named: Dictionary) -> int:
	var n := 0
	for kind: int in named:
		n += (named[kind] as Array).size()
	return n


# --- 7. the five specialists -------------------------------------------------

func _test_specialists() -> void:
	print("\n[7] the specialist Kestrels are sidegrades, and their trees are real")
	var game: Node = root.get_node("/root/Game")
	var gconsts: Dictionary = (load("res://scripts/Game.gd") as GDScript) \
			.get_script_constant_map()
	var uconsts: Dictionary = (load("res://scripts/Unit.gd") as GDScript) \
			.get_script_constant_map()
	var trees: Dictionary = gconsts["CLASS_PERK_RANKS"]
	var perks: Dictionary = gconsts["PERKS"]
	var starting: Dictionary = gconsts["CLASS_STARTING_PERK"]
	var kinds: Dictionary = uconsts["Kind"]
	var rifle_kinds: Array = uconsts["RIFLE_SLOT_KINDS"]

	# The ordinals every save is written in. Appending is the only safe edit,
	# so these five must sit ABOVE the nine that shipped before them.
	_check(int(kinds["GRENADIER"]) == 10 and int(kinds["MARKSMAN"]) == 11
			and int(kinds["BREACHER"]) == 12 and int(kinds["MEDIC"]) == 13
			and int(kinds["TECHNICIAN"]) == 14,
			"the five specialists are ordinals 10-14, appended after HERO")
	_check(int(kinds["HERO"]) == 9 and int(kinds["CIVILIAN"]) == 8
			and int(kinds["SCOUT"]) == 0,
			"and nothing that shipped before them moved")

	# Every specialist can hold a rifle slot; the lead and the gun cannot.
	for name: String in ["SCOUT", "GRENADIER", "MARKSMAN", "BREACHER",
			"MEDIC", "TECHNICIAN"]:
		_check(rifle_kinds.has(int(kinds[name])),
				"%s can stand in a rifle slot" % name)
	_check(not rifle_kinds.has(int(kinds["HERO"]))
			and not rifle_kinds.has(int(kinds["MACHINEGUNNER"])),
			"the lead and the gun cannot - they have their own slots")

	# A tree that names a perk nothing implements is a lie told on a promotion
	# screen. Sweep every class, not just the new ones.
	var unknown: Array[String] = []
	var malformed: Array[String] = []
	for kind: int in trees:
		var tree: Dictionary = trees[kind]
		for rank: int in tree:
			var choices: Array = tree[rank]
			if choices.size() != 2:
				malformed.append("kind %d rank %d has %d" % [kind, rank, choices.size()])
			for key: String in choices:
				if not perks.has(key):
					unknown.append("kind %d rank %d: %s" % [kind, rank, key])
	_check(unknown.is_empty(), "every perk in every tree exists (%s)" % [unknown])
	_check(malformed.is_empty(), "and every rank offers exactly two (%s)" % [malformed])

	# Starting perks must be real too - _read_roster whitelists against PERKS,
	# so a typo here is silently deleted from every save that stored it.
	var bad_start: Array[String] = []
	for kind: int in starting:
		if not perks.has(str(starting[kind])):
			bad_start.append("kind %d: %s" % [kind, starting[kind]])
	_check(bad_start.is_empty(),
			"every starting specialty is a real perk (%s)" % [bad_start])

	# Sidegrades, not upgrades: nobody is strictly better than the rifleman.
	game.roster = []
	game._next_id = 1
	game.ensure_roster(Levels.LEVELS[0])
	var baseline := _stats_of(int(kinds["SCOUT"]))
	var dominated: Array[String] = []
	for name: String in ["GRENADIER", "MARKSMAN", "BREACHER", "MEDIC", "TECHNICIAN"]:
		var s := _stats_of(int(kinds[name]))
		var better_or_equal := true
		var strictly_better := false
		for stat: String in baseline:
			if s[stat] < baseline[stat]:
				better_or_equal = false
			elif s[stat] > baseline[stat]:
				strictly_better = true
		if better_or_equal and strictly_better:
			dominated.append(name)
	_check(dominated.is_empty(),
			"no specialist dominates the rifleman on every stat (%s)" % [dominated])

	# And each of them arrives already being the thing they are.
	for soldier: Dictionary in game.roster:
		var kind: int = int(soldier.kind)
		if starting.has(kind):
			_check((soldier.perks as Array).has(str(starting[kind])),
					"%s starts with %s" % [game.full_name(soldier), starting[kind]])


## A bare unit's stat line, built the way Battle builds one.
func _stats_of(kind: int) -> Dictionary:
	var unit: Node2D = (load("res://scenes/Unit.tscn") as PackedScene).instantiate()
	unit.setup(kind, Vector2i.ZERO)
	var out := {
		"max_hp": int(unit.max_hp), "move_range": int(unit.move_range),
		"attack_range": int(unit.attack_range), "damage": int(unit.damage),
		"accuracy": int(unit.accuracy), "mag_size": int(unit.mag_size),
	}
	unit.free()
	return out


# --- 8. who actually goes ----------------------------------------------------

func _test_deployment() -> void:
	print("\n[8] three of the six go, and the choice survives the roster moving")
	var game: Node = root.get_node("/root/Game")
	game.roster = []
	game._next_id = 1
	game.deployed_ids = []
	game.ensure_roster(Levels.LEVELS[0])

	_check(game.roster.size() == 8, "the campaign keeps eight people (%d)" % game.roster.size())
	_check(game.rifle_candidates().size() == 6,
			"six of them can hold a rifle slot (%d)" % game.rifle_candidates().size())

	# No choice made: a full squad still deploys, in roster order.
	var default_three: Array = game.deployment(3)
	_check(default_three.size() == 3,
			"an unset deployment still fields three (%d)" % default_three.size())

	# A choice is honoured, and honoured by identity rather than by position.
	var candidates: Array = game.rifle_candidates()
	var picked: Array = [int(candidates[5].id), int(candidates[3].id),
			int(candidates[1].id)]
	game.set_deployment(picked)
	var going: Array = game.deployment(3)
	var going_ids: Array = []
	for soldier: Dictionary in going:
		going_ids.append(int(soldier.id))
	_check(going_ids == picked,
			"the three chosen are the three that go, in order (%s)" % [going_ids])

	# One of them dies. The dead do not deploy, and the gap is filled rather
	# than left - a squad of two because somebody died last mission would be a
	# punishment nobody chose.
	for soldier: Dictionary in game.roster:
		if int(soldier.id) == picked[1]:
			soldier["alive"] = false
	var after: Array = game.deployment(3)
	var after_ids: Array = []
	for soldier: Dictionary in after:
		after_ids.append(int(soldier.id))
	_check(not after_ids.has(picked[1]), "the dead one does not deploy")
	_check(after.size() == 3,
			"and the slot is backfilled rather than left empty (%s)" % [after_ids])

	# A save from another campaign cannot deploy a ghost.
	game.deployed_ids = [999, 1000, 1001]
	var ghosts: Array = game.deployment(3)
	_check(ghosts.size() == 3, "invented ids fall back to the roster (%d)" % ghosts.size())
	for soldier: Dictionary in ghosts:
		_check(bool(soldier.alive), "and everybody who deploys is alive")
		break


# --- 9. the snapshot carries gear ---------------------------------------------

## Pins the one line in _deep_copy that makes gear rollback-safe. Without it
## the snapshot's gear dict IS the live soldier's gear dict, and a mid-mission
## equip would survive the wholesale rollback a lost mission promises.
func _test_gear_rollback() -> void:
	print("\n[9] a lost mission rolls the kit back with everything else")
	var game: Node = root.get_node("/root/Game")
	game.roster = []
	game._next_id = 1
	game.ensure_roster(Levels.LEVELS[0])
	var soldier: Dictionary = game.roster[0]
	soldier.gear = {"weapon": "oiled_sling", "armor": "", "kit": ""}
	game.begin_mission()
	(game.roster[0] as Dictionary).gear["weapon"] = "glass_sight"
	(game.roster[0] as Dictionary).gear["armor"] = "boiler_plate"
	game.abort_mission()
	var restored: Dictionary = (game.roster[0] as Dictionary).gear
	_check(str(restored.weapon) == "oiled_sling" and str(restored.armor) == "",
			"the equip made mid-mission is rolled back (%s)" % [restored])
