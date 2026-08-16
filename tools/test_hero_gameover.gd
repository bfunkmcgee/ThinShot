extends SceneTree

## Exercises the two campaign rules Rodar Akai adds, against the real Battle
## scene rather than a re-implementation:
##   1. an old save's alive TEAM_LEAD is converted in place to the HERO by
##      ensure_roster() - id, xp, rank and perks kept, surname now Akai, and
##      no orphaned lead left standing beside him
##   2. a SCOUT dying does NOT end the battle while others still stand, but
##      the HERO dying loses it on the spot - and the verdict panel waits for
##      the body to land before it appears
##
## Any real save is backed up in _init() - BEFORE the Game autoload's _ready
## can load it - and restored on the way out, so this is safe to run on a
## machine someone is actually playing on. The battle is booted on a planted
## full-strength roster so ensure_roster() recruits nobody, which keeps the
## run deterministic.
##
## NOTHING from scripts/ is preloaded, deliberately. Unit.gd names the Game
## autoload in its body, and compiling this tool is what compiles anything it
## preloads - which under `-s` happens before the autoloads exist. A preload
## of Game.gd here drags Unit.gd in at that point, its compile fails on the
## missing identifier, and the broken script stays cached: every Unit the
## booted scene then instantiates comes out scriptless. So Game.gd is load()ed
## after the first frame, once the autoloads are up. (Levels.gd references no
## autoload, so naming it below is safe - check_cover_rules.gd already does.)
##
## Run: godot --headless --path . -s tools/test_hero_gameover.gd

const SAVE_PATH := "user://campaign.json"  # mirrors Game.SAVE_PATH (not preloaded)
const BACKUP_PATH := "user://campaign.json.testbak"  # crash-proof copy, see _init

# Raw ordinals, matching test_save_load.gd's style.
const KIND_SCOUT := 0
const KIND_TEAM_LEAD := 1
const KIND_MACHINEGUNNER := 2
const KIND_HERO := 9  # appended after CIVILIAN=8; saves store this ordinal
const TEAM_SCOUT := 0
const STATE_GAME_OVER := 3  # Battle.State { PLAYER_TURN, ANIMATING, ENEMY_TURN, GAME_OVER }

var _failed := false
var _had_save := false
var _backup := ""


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    %s" % label)
	else:
		printerr("  FAIL  %s" % label)
		_failed = true


## Runs before the autoloads are added to the tree, so the real campaign is
## whisked away before Game._ready() can load it. The backup goes to disk as
## well as memory: a run that dies before _finish() takes a String copy with
## it, and a campaign was lost that way once. The sidecar outlives the crash
## and the next run puts it back.
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


## A backup still on disk means a previous run died before restoring it.
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


func _run() -> void:
	await process_frame  # let the autoloads finish _ready()

	print("\n[1] an old save's alive team lead becomes Rodar Akai")
	# A pre-Rodar campaign at full strength for level 1 (3 scouts, 1 lead,
	# 1 gunner), so ensure_roster() has nothing to recruit and the only thing
	# it can possibly do is the conversion.
	var game: Node = (load("res://scripts/Game.gd") as GDScript).new()
	game.roster = [
		{"id": 1, "surname": "NAKAMURA", "kind": KIND_TEAM_LEAD, "xp": 27,
				"rank": 3, "perks": ["marksman", "sentinel"] as Array, "alive": true},
		{"id": 2, "surname": "HARGREAVE", "kind": KIND_MACHINEGUNNER, "xp": 8,
				"rank": 1, "perks": [] as Array, "alive": true},
		{"id": 3, "surname": "VANCE", "kind": KIND_SCOUT, "xp": 3, "rank": 0,
				"perks": [] as Array, "alive": true},
		{"id": 4, "surname": "QUINN", "kind": KIND_SCOUT, "xp": 0, "rank": 0,
				"perks": [] as Array, "alive": true},
		{"id": 5, "surname": "ORTIZ", "kind": KIND_SCOUT, "xp": 0, "rank": 0,
				"perks": [] as Array, "alive": true},
	]
	game._next_id = 6
	print("  before: %s" % [game.roster.map(
			func(s: Dictionary) -> String: return "%s(kind %d)" % [s.surname, s.kind])])
	game.ensure_roster(Levels.LEVELS[0])
	print("  after:  %s" % [game.roster.map(
			func(s: Dictionary) -> String: return "%s(kind %d)" % [s.surname, s.kind])])
	var hero: Dictionary = game.soldier_by_id(1)
	_check(int(hero.get("kind", -1)) == KIND_HERO, "lead converted to HERO in place")
	_check(str(hero.get("surname", "")) == "Akai", "surname is Akai")
	_check(int(hero.get("xp", 0)) == 27 and int(hero.get("rank", 0)) == 3,
			"xp and rank kept (%s xp, rank %s)" % [hero.get("xp"), hero.get("rank")])
	_check((hero.get("perks", []) as Array).has("marksman")
			and (hero.get("perks", []) as Array).has("sentinel"), "perks kept")
	var orphan := false
	var recruited: bool = game.roster.size() != 5
	for s: Dictionary in game.roster:
		if int(s.kind) == KIND_TEAM_LEAD and bool(s.alive):
			orphan = true
	_check(not orphan, "no orphaned alive TEAM_LEAD remains")
	_check(not recruited, "nobody new recruited (roster still %d)" % game.roster.size())
	_check(game.vacancies(Levels.LEVELS[0]).is_empty(),
			"vacancies() reports none (hero slot never refills)")

	print("\n[2] boot Battle.tscn on that campaign (level 1, headless)")
	# ensure_roster() saved the converted roster; hand it to the live autoload
	# the same way a real launch would get it.
	var game_auto: Node = root.get_node("/root/Game")
	_check(game_auto.load_save(), "autoload loaded the planted campaign")
	game.free()
	var battle: Node = (load("res://scenes/Battle.tscn") as PackedScene).instantiate()
	root.add_child(battle)
	await process_frame
	await process_frame

	var hero_unit: Node2D = null
	var scout_units: Array = []
	for unit in battle.living_soldiers(TEAM_SCOUT):
		if int(unit.kind) == KIND_HERO:
			hero_unit = unit
		elif int(unit.kind) == KIND_SCOUT:
			scout_units.append(unit)
	_check(hero_unit != null, "HERO deployed in the lead slot")
	if hero_unit != null:
		_check(hero_unit.cell == Levels.LEVELS[0].lead_spawns[0],
				"hero stands on lead_spawns[0] (got %s)" % hero_unit.cell)
		_check(str(hero_unit.surname) == "Akai", "hero unit carries the name")
		_check(int(hero_unit.max_hp) >= 10 and int(hero_unit.mag_size) == 3,
				"hero stats applied (hp %d, mag %d)" % [hero_unit.max_hp, hero_unit.mag_size])
	_check(scout_units.size() == 3, "3 scouts deployed (got %d)" % scout_units.size())
	if hero_unit == null or scout_units.is_empty():
		_finish()
		return

	print("\n[3] a scout death does not end the battle")
	scout_units[0].take_damage(999)
	_check(int(battle.state) != STATE_GAME_OVER, "state is not GAME_OVER")
	_check(not battle.game_over_panel.visible, "no verdict panel shown")

	print("\n[4] the hero's death loses the battle on the spot")
	hero_unit.take_damage(999)
	_check(int(battle.state) == STATE_GAME_OVER, "state is GAME_OVER immediately")
	_check(battle.last_result_won == false, "recorded as a loss")
	_check(battle.result_label.text == "RODAR AKAI HAS FALLEN",
			"verdict reads RODAR AKAI HAS FALLEN (got '%s')" % battle.result_label.text)
	_check(not battle.game_over_panel.visible,
			"panel held back while the body falls")
	# abort_mission() ran inside the loss: the roster must be back to the
	# mission-start state, hero included - a lost mission un-kills him.
	var restored: Dictionary = game_auto.soldier_by_id(1)
	_check(bool(restored.get("alive", false)), "abort_mission un-killed the hero")
	await create_timer(hero_unit.death_landing_time() + 0.5).timeout
	_check(battle.game_over_panel.visible, "panel appeared after the fall")

	_finish()


func _finish() -> void:
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
