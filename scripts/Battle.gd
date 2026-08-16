extends Node2D

## Battle controller: turn state machine, player input, enemy AI, win/lose.

enum State { PLAYER_TURN, ANIMATING, ENEMY_TURN, GAME_OVER }

## Direction-picking modes: each previews and commits on a click.
## OVERWATCH consumes the unit's attack; FACE is free. CALLED_SHOT is the
## hero's aimed round - armed like a throw, committed on an enemy.
enum AimMode { NONE, OVERWATCH, FACE, THROW_FRAG, THROW_SMOKE, CALLED_SHOT }

## Which trigger setting the selected unit will use on its next shot.
## SUPPRESS is the machinegunner's ability rather than a trigger setting:
## it deals no damage and pins an area instead.
enum FireMode { SINGLE, BURST, AUTO, SUPPRESS }

const UNIT_SCENE := preload("res://scenes/Unit.tscn")
const ROCK_TEXTURES: Array[Texture2D] = [
	preload("res://assets/sprites/Environment/Desert/Desert_Rock_or_bolder/Rock_1.png"),
	preload("res://assets/sprites/Environment/Desert/Desert_Rock_or_bolder/Rock_2.png"),
	preload("res://assets/sprites/Environment/Desert/Desert_Rock_or_bolder/Rock_3.png"),
	preload("res://assets/sprites/Environment/Desert/Desert_Rock_or_bolder/Rock_4.png"),
	preload("res://assets/sprites/Environment/Desert/Desert_Rock_or_bolder/Rock_5.png"),
	preload("res://assets/sprites/Environment/Desert/Desert_Rock_or_bolder/Rock_6.png"),
	preload("res://assets/sprites/Environment/Desert/Desert_Rock_or_bolder/Rock_7.png"),
	preload("res://assets/sprites/Environment/Desert/Desert_Rock_or_bolder/Rock_8.png"),
]
const JUNK_TEXTURES: Array[Texture2D] = [
	preload("res://assets/sprites/Environment/Desert/desert_rusted_garbage/Rusted_desert_garbage.png"),
	preload("res://assets/sprites/Environment/Desert/desert_rusted_garbage/Rusted_desert_garbage_1.png"),
	preload("res://assets/sprites/Environment/Desert/desert_rusted_garbage/Rusted_desert_garbage_2.png"),
	preload("res://assets/sprites/Environment/Desert/desert_rusted_garbage/Rusted_desert_garbage_3.png"),
	preload("res://assets/sprites/Environment/Desert/desert_rusted_garbage/Rusted_desert_garbage_4.png"),
	preload("res://assets/sprites/Environment/Desert/desert_rusted_garbage/Rusted_desert_garbage_5.png"),
	preload("res://assets/sprites/Environment/Desert/desert_rusted_garbage/Rusted_desert_garbage_6.png"),
]
const PLANT_TEXTURES: Array[Texture2D] = [
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants.png"),
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants_1.png"),
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants_2.png"),
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants_3.png"),
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants_4.png"),
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants_5.png"),
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants_6.png"),
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants_7.png"),
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants_8.png"),
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants_9.png"),
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants_10.png"),
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants_11.png"),
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants_12.png"),
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants_13.png"),
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants_14.png"),
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants_15.png"),
]
# The rotation names describe the wall's FACING, so its length runs along
# the perpendicular axis: a south-west-facing wall runs NW-SE (grid x).
const WALL_TEX_X_RUN := preload(
		"res://assets/sprites/Environment/Desert/Walls/desert_brick_and_mud/rotations/south-west.png")
const WALL_TEX_Y_RUN := preload(
		"res://assets/sprites/Environment/Desert/Walls/desert_brick_and_mud/rotations/south-east.png")
const WALL_TEX_JUNCTION := preload(
		"res://assets/sprites/Environment/Desert/Walls/desert_brick_and_mud/rotations/north.png")
const WALL_TEX_CAP := preload(
		"res://assets/sprites/Environment/Desert/Walls/desert_brick_and_mud/rotations/east.png")
# Wire reads the same four ways a wall does, from its own rotation set.
const WIRE_ROOT := "res://assets/sprites/Environment/Desert/Walls/desert_barbed_wire/rotations/"
const WIRE_TEXTURES := {
	"x_run": preload(WIRE_ROOT + "south-west.png"),
	"y_run": preload(WIRE_ROOT + "south-east.png"),
	"junction": preload(WIRE_ROOT + "north.png"),
	"cap": preload(WIRE_ROOT + "east.png"),
}
# Cover somebody built on purpose, as opposed to junk they left behind.
const SANDBAG_TEXTURES: Array[Texture2D] = [
	preload("res://assets/sprites/Environment/Desert/desert_sandbags/Desert_Sandbags.png"),
	preload("res://assets/sprites/Environment/Desert/desert_sandbags/Desert_Sandbags_1.png"),
]
# The Choir's own stacked ordnance. Deliberately kept off the maps that have
# demolition objectives on them: crates you must burn and crates you merely
# hide behind should never be on the same board.
const CHOIR_CACHE_ROOT := "res://assets/sprites/Environment/Desert/Props/Desert_insurgent_weapons_cache/"
const CHOIR_CACHE_TEXTURES: Array[Texture2D] = [
	preload(CHOIR_CACHE_ROOT + "Desert_insurgent_weapons_cache/rotations/unknown.png"),
	preload(CHOIR_CACHE_ROOT + "Desert_insurgent_weapons_cache_1/rotations/unknown.png"),
	preload(CHOIR_CACHE_ROOT + "Desert_insurgent_weapons_cache_2/rotations/unknown.png"),
	preload(CHOIR_CACHE_ROOT + "Desert_insurgent_weapons_cache_3/rotations/unknown.png"),
	preload(CHOIR_CACHE_ROOT + "Desert_insurgent_weapons_cache_4/rotations/unknown.png"),
	preload(CHOIR_CACHE_ROOT + "Desert_insurgent_weapons_cache_5/rotations/unknown.png"),
]
const STRUCTURE_ROOT := "res://assets/sprites/Environment/Desert/Structures"
const STRUCTURE_DIRS := {
	"hut_1": STRUCTURE_ROOT + "/desert_hut/Desert_hut",
	"hut_2": STRUCTURE_ROOT + "/desert_hut/Desert_hut_1",
	"tent": STRUCTURE_ROOT + "/desert_hut/Desert_hut_2",
	"fortress": STRUCTURE_ROOT + "/Desert_military_building",
}
const STRUCTURE_FPS := 7.0  # gentle breeze loops

# Ground anchors measured from opaque bounds (texture px, pre-2x-scale).
# Props center their painted ground footprint on the cell center; walls sink
# toward the tile's front edge; structures align base to footprint front vertex.
const ROCK_OFFSET := Vector2(0, -18)
const JUNK_OFFSET := Vector2(0, -20)
const PLANT_OFFSET := Vector2(0, -17)
const WALL_OFFSETS := {
	"x_run": Vector2(0, -15), "y_run": Vector2(0, -15),
	"junction": Vector2(0, -9), "cap": Vector2(0, -11),
}
# Same 14px sink as the brick wall, measured off wire's own opaque bounds -
# its canvas is 97px where the wall's is 68, so the numbers differ but the
# base lands on the same front vertex.
const WIRE_OFFSETS := {
	"x_run": Vector2(0, -10), "y_run": Vector2(0, -10),
	"junction": Vector2(0, -4), "cap": Vector2(0, -17),
}
const SANDBAG_OFFSET := Vector2(0, -22)
# A rifle lying where its owner fell, in the direction they were last facing.
# Sector order matches Unit.DIR_NAMES. Anchored on the painted centre rather
# than a base, because it is flat on the ground and has no base.
const RIFLE_ROOT := "res://assets/sprites/Environment/Desert/Props/Dropped_assault_rifle/rotations/"
const RIFLE_TEXTURES: Array[Texture2D] = [
	preload(RIFLE_ROOT + "east.png"),
	preload(RIFLE_ROOT + "south-east.png"),
	preload(RIFLE_ROOT + "south.png"),
	preload(RIFLE_ROOT + "south-west.png"),
	preload(RIFLE_ROOT + "west.png"),
	preload(RIFLE_ROOT + "north-west.png"),
	preload(RIFLE_ROOT + "north.png"),
	preload(RIFLE_ROOT + "north-east.png"),
]
const RIFLE_OFFSET := Vector2(0, -1)
# Far enough off the body that both read, close enough that they are obviously
# the same event.
const RIFLE_DROP := Vector2(0, 10)
# Downsampled to 40px so it draws at the shared 2x like every other standing
# prop - one texel density across the board.
const CHOIR_CACHE_OFFSET := Vector2(0, -15)
const STRUCTURE_OFFSETS := {
	"hut_1": Vector2(0, -22), "hut_2": Vector2(0, -33),
	"tent": Vector2(0, -33), "fortress": Vector2(0, -55),
}
const ROCK_SCALE := Vector2(2, 2)

# Scenery is pulled into one palette by a shared dust shader rather than by
# re-authoring the art. Haze is quantised into a few depth bands so the whole
# board needs only a handful of materials instead of one per prop; the band
# constants live on Board, where the FloorLayer reads the same numbers.
const PROP_DUST := preload("res://assets/shaders/prop_dust.gdshader")

const PROP_ROOT := "res://assets/sprites/Environment/Desert/Props"

# Objective props. Each has a standing pose, an optional idle loop, one or more
# one-shot destruction stages, and the wreck it leaves behind. The number of
# stages IS the number of charges it takes to put down - crates go in one, the
# relay mast takes two because it buckles before it falls.
#
# Ground offsets are measured from opaque bounds so each prop's base sits on
# the cell centre, matching the rocks and junk.
const TARGET_PROPS := {
	# The crates were authored at 96px and have been nearest-downsampled to
	# 48, so they draw at the shared 2x like everything else and land on the
	# same screen size as before: a pile a little taller than a soldier.
	"crates": {
		"dir": PROP_ROOT + "/Pile_of_desert_ammo_crates",
		"body": "Pile_of_desert_ammo_crates",
		"idles": [],
		"stages": ["normal_to_destroyed"],
		# Sprite2D applies offset before scale, so this anchor holds at any size.
		"offset": Vector2(0, -18),
		"scale": 2.0,
		"shadow": 20.0,
	},
	"mast": {
		"dir": PROP_ROOT + "/Desert_Comms_mast",
		"body": "Desert_Comms_mast",
		# One idle per surviving state: upright, then leaning and sparking.
		"idles": ["normal_idle", "broken_idle"],
		"stages": ["normal_to_broken", "broken_to_destroyed"],
		"offset": Vector2(0, -69),
		"scale": 2.0,
		"shadow": 16.0,
	},
}
const PROP_FPS := 14.0  # one-shot destruction playback

const DRUM_DIR := PROP_ROOT + "/desert_Explosive_Fuel_drum"
const DRUM_STILL := preload(
		PROP_ROOT + "/desert_Explosive_Fuel_drum/desert_Explosive_Fuel_drum/rotations/unknown.png")
const DRUM_WRECK := preload(
		PROP_ROOT + "/desert_Explosive_Fuel_drum/destroyed_state/rotations/unknown.png")
const DRUM_OFFSET := Vector2(0, -22)
# A drum going up hits as hard as a frag at its centre and reaches as far.
const DRUM_DAMAGE := 3

const MOVE_STEP_TIME := 0.16
const TRACER_TIME := 0.09
const AI_BEAT := 0.12
const ACT_LEAD_IN := 0.15  # pause after marking a goblin, before it acts
const SWAY_SPEED := 1.6      # radians/sec of the plant sway cycle
const SWAY_TEXELS := 1.0     # sprite texels a plant leans at full sway
# The to-hit arithmetic lives on Rules now, and the numbers it reads went with
# it. What stays here is an alias for each constant Battle still quotes on its
# own account - one number under two names, so the sentence the panel writes
# and the penalty the roll applies cannot come apart.
const SUPPRESSION_ACCURACY := Rules.SUPPRESSION_ACCURACY  # the panel says this out loud
const PEEK_LEAN := 0.34           # how far toward the corner the body shifts
const LOWER_TIME := 0.12  # rifle held after the shot before lowering
const BURST_GAP := 0.13  # pause between the rounds of a burst
const AUTO_GAP := 0.07   # full auto cycles faster than a burst
const BURST_ROUNDS := 2
const AUTO_ROUNDS := 4
const AUTO_ACCURACY := -15  # per-round penalty for walking the gun
const WALKING_FIRE_ACCURACY := -10  # Walking Fire's extra for full auto off the advance
const SUPPRESS_ROUNDS := 3
# The beaten zone's radius lives on Unit (suppress_radius()), because Wide
# Sweep grows it per gunner - every consumer here asks the unit.
# Sustained fire while the pin holds. Two rounds close together, then a long
# pause, so it reads as volleys. Well under the shot volume - it runs for a
# whole enemy turn and must sit behind the action, not on top of it.
const SUSTAIN_ROUND_GAP := 0.12
const SUSTAIN_VOLLEY_GAP := 1.45
const SUSTAIN_VOLUME := -13.0

# Thrown ordnance - the squad's edge, and the one thing the Choir has no
# answer to. Carried as a shared pool rather than per soldier, so the decision
# is "is this the moment" rather than "which pocket".
const THROW_RANGE := 4       # tiles from the thrower, needs line of sight
# Half-width of the square a grenade covers: 1 gives the 3x3 footprint.
const BLAST_RADIUS := 1
const FRAG_DAMAGE := 3       # no hit roll and cover does not stop it
const FRAG_FALLOFF := 1      # lost per step out, so the four corners take 2
# Turns of smoke, counted down at the start of each player turn. One means the
# cloud stands for the rest of the turn it was thrown and all of the enemy
# turn that follows - long enough to cross under, not long enough to camp.
const SMOKE_TURNS := 1
const THROW_ARC_TIME := 0.42
const THROW_ARC_HEIGHT := 90.0

# Class actives - the abilities a perk hangs a button on. Fixed slots so the
# key each blurb promises is always true: Called Shot and Field Dressing are
# (Q) abilities, Rally is the (T) one. No class tree offers a soldier two
# Q-abilities, so the slots can never collide on a legitimate roster.
const ACTIVE_LABELS := {
	"called_shot": "Called Shot",
	"rally": "Rally",
	"field_dressing": "Patch Up",
}
const FIELD_DRESSING_HEAL := 3
const RALLY_RANGE := 4        # manhattan tiles around the hero
const RALLY_ACCURACY := 10    # to-hit, until each soldier's own next turn
# Inspiration's numbers are Rules'; the search that finds the hero is Battle's,
# so the aliases stay beside the ability they belong to.
const INSPIRATION_RANGE := Rules.INSPIRATION_RANGE  # manhattan tiles around the perked hero
const INSPIRATION_ACCURACY := Rules.INSPIRATION_ACCURACY
const CALLED_SHOT_BONUS := 2  # One Shot's extra damage on a called shot

# Ignore end-turn requests this soon after control returns to the player -
# they are almost always leftover E-mashing/clicking from the enemy turn.
const END_TURN_GRACE_MS := 350

var state := State.PLAYER_TURN
var selected: Unit = null
var hover_cell := Board.NO_CELL
var turn_number := 1
var enemy_turn_running := false
var player_turn_ready_msec := 0
var danger_on := false
var fire_mode := FireMode.SINGLE
var aim_mode := AimMode.NONE
var level: Dictionary = {}
var last_result_won := false
var base_camera_pos := Vector2.ZERO
var base_zoom := Vector2.ONE
var _cam_lean := Vector2.ZERO
var _cam_shake := Vector2.ZERO
var _shake_tween: Tween = null
var _kick_tween: Tween = null
# Two streams, deliberately. _rules_rng rolls to hit and nothing else;
# _vis_rng does every scatter, splash and puff. They were one generator, and
# the punchline is _boil_smoke(): it runs off _process, fourteen draws a second
# for as long as smoke is on the board, so the number a shot would have rolled
# used to depend on how long the player sat and thought about it. Sustained
# suppression draws off a wall clock too, and the miss-offset draw hid inside a
# ternary, so the stream even advanced by a different amount on a hit than on a
# miss. Split, the rules stream advances exactly once per shot and cosmetics
# cost nothing - which is also what makes seeding it reproducible.
var _rules_rng := RandomNumberGenerator.new()
var _vis_rng := RandomNumberGenerator.new()
# Seed for every scenery-variant hash stream, so prop picks decorrelate from
# cell coordinates without losing determinism. Levels may pin it with a
# "prop_seed" key; otherwise it derives from the zone seed.
var _prop_seed := 0
var _swaying: Array = []
var _animated_props: Array = []
var structure_frames: Dictionary = {}
var fx_ground: Fx = null
var fx_air: Fx = null
var fx_glow: Fx = null
var objective_marks: ObjectiveMarks = null
# Squad ordnance, shared across all five soldiers and spent for the battle.
# Set at the camp's stores tent, not here - the split is the player's call.
var frags_left := Game.frags
var smokes_left := Game.smokes
# Live smoke: cell -> player turns remaining.
var smoke: Dictionary = {}
var _smoke_puff_accum := 0.0
# Objective props: [{cell, obj, kind, art, sprite, stage, destroyed, anim}]
var caches: Array = []
# Fuel drums by cell: {sprite, spent}. Cover until something sets them off.
var drums: Dictionary = {}
# Contact shadows for objective props, handed to the Board once they exist.
var _prop_shadows: Dictionary = {}
# Dust materials by depth band, shared across every prop in that band.
var _dust_materials: Dictionary = {}
# The gunner currently laying down sustained fire, and where he is working.
var _suppressor: Unit = null
var _suppress_point := Vector2.ZERO
var _suppress_timer := 0.0
var _suppress_in_volley := 0
# Set while a blast is handing out damage. A blast is the one thing that can
# kill units on both sides in a single indivisible action, and take_damage
# emits `died` synchronously - so without this the win check runs on the first
# casualty and commits the mission before the rest of the footprint resolves.
var _resolving_blast := false

@onready var board: Board = $Board
@onready var camera: Camera2D = $Camera
@onready var entities_node: Node2D = $Entities
@onready var turn_banner: Label = $UI/TurnBanner
@onready var objective_label: Label = $UI/ObjectiveLabel
@onready var end_turn_button: Button = $UI/EndTurnButton
@onready var overwatch_button: Button = $UI/OverwatchButton
@onready var burst_button: Button = $UI/BurstButton
@onready var auto_button: Button = $UI/AutoButton
@onready var suppress_button: Button = $UI/SuppressButton
@onready var reload_button: Button = $UI/ReloadButton
@onready var face_button: Button = $UI/FaceButton
@onready var danger_button: Button = $UI/DangerButton
@onready var demolish_button: Button = $UI/DemolishButton
@onready var frag_button: Button = $UI/FragButton
@onready var smoke_button: Button = $UI/SmokeButton
@onready var ability_1_button: Button = $UI/Ability1Button
@onready var ability_2_button: Button = $UI/Ability2Button
@onready var unit_panel: PanelContainer = $UI/UnitPanel
@onready var panel_name_label: Label = $UI/UnitPanel/Margin/Rows/NameLabel
@onready var panel_progress_label: Label = $UI/UnitPanel/Margin/Rows/ProgressLabel
@onready var panel_hp_label: Label = $UI/UnitPanel/Margin/Rows/HpLabel
@onready var panel_stats_label: Label = $UI/UnitPanel/Margin/Rows/StatsLabel
@onready var panel_status_label: Label = $UI/UnitPanel/Margin/Rows/StatusLabel
@onready var game_over_panel: ColorRect = $UI/GameOver
@onready var result_label: Label = $UI/GameOver/ResultLabel
@onready var restart_button: Button = $UI/GameOver/RestartButton
@onready var level_1_button: Button = $UI/GameOver/Level1Button
@onready var level_2_button: Button = $UI/GameOver/Level2Button
@onready var level_3_button: Button = $UI/GameOver/Level3Button
@onready var debrief_label: Label = $UI/GameOver/DebriefLabel
@onready var narrative_label: Label = $UI/GameOver/NarrativeLabel
@onready var briefing_panel: ColorRect = $UI/Briefing
@onready var briefing_mission_label: Label = $UI/Briefing/Center/Box/MissionLabel
@onready var briefing_title_label: Label = $UI/Briefing/Center/Box/TitleLabel
@onready var briefing_fiction_label: Label = $UI/Briefing/Center/Box/FictionLabel
@onready var briefing_body_label: Label = $UI/Briefing/Center/Box/BodyLabel
@onready var briefing_orders_label: Label = $UI/Briefing/Center/Box/OrdersLabel
@onready var briefing_begin_button: Button = $UI/Briefing/Center/Box/BeginButton


func _ready() -> void:
	_rules_rng.randomize()
	_vis_rng.randomize()
	Engine.time_scale = 1.0  # a reload mid-hit-stop must never persist
	Levels.validate_all()  # push_error-based, so it reports in release too
	_apply_cmdline_level()
	level = Game.data()
	# Bring the squad up to strength (replacing anyone lost) and snapshot it,
	# so a failed mission can be rolled back wholesale.
	Game.ensure_roster(level)
	Game.begin_mission()
	board.set_level(level)
	_prop_seed = int(level.get("prop_seed", int(level.get("zone_seed", 7)) * 977 + 101))
	_fit_camera()
	_setup_fx_layers()
	_validate_spawns()
	_load_structure_art()
	_spawn_props()
	for s: Dictionary in level.structures:
		_spawn_structure(s)
	_spawn_caches()
	board.set_prop_shadows(_prop_shadows)
	# Rodar Akai deploys in the lead slot: same spawn key, stronger soldier.
	_spawn_squad(Unit.Kind.HERO, level.get("lead_spawns", []))
	_spawn_squad(Unit.Kind.MACHINEGUNNER, level.get("gunner_spawns", []))
	_spawn_squad(Unit.Kind.SCOUT, level.scout_spawns)
	for spawn: Vector2i in level.goblin_spawns:
		_spawn_unit(Unit.Kind.GOBLIN, spawn)
	for spawn: Vector2i in level.get("smg_spawns", []):
		_spawn_unit(Unit.Kind.GOBLIN_SMG, spawn)
	for spawn: Vector2i in level.get("smg_alt_spawns", []):
		_spawn_unit(Unit.Kind.GOBLIN_SMG_ALT, spawn)
	for spawn: Vector2i in level.get("novice_spawns", []):
		_spawn_unit(Unit.Kind.GOBLIN_REVOLVER, spawn)
	for spawn: Vector2i in level.get("bolt_spawns", []):
		_spawn_unit(Unit.Kind.GOBLIN_BOLT, spawn)
	for spawn: Vector2i in level.get("prisoner_spawns", []):
		_spawn_unit(Unit.Kind.CIVILIAN, spawn)
	end_turn_button.pressed.connect(end_player_turn)
	overwatch_button.toggled.connect(_on_aim_button_toggled.bind(AimMode.OVERWATCH))
	face_button.toggled.connect(_on_aim_button_toggled.bind(AimMode.FACE))
	burst_button.toggled.connect(_on_fire_button_toggled.bind(FireMode.BURST))
	auto_button.toggled.connect(_on_fire_button_toggled.bind(FireMode.AUTO))
	suppress_button.toggled.connect(_on_fire_button_toggled.bind(FireMode.SUPPRESS))
	reload_button.pressed.connect(_try_reload)
	demolish_button.pressed.connect(_try_demolish.bind(Board.NO_CELL))
	# Only levels with something to blow up show the button at all.
	demolish_button.visible = not caches.is_empty()
	frag_button.toggled.connect(_on_aim_button_toggled.bind(AimMode.THROW_FRAG))
	smoke_button.toggled.connect(_on_aim_button_toggled.bind(AimMode.THROW_SMOKE))
	ability_1_button.pressed.connect(_use_ability.bind(0))
	ability_2_button.pressed.connect(_use_ability.bind(1))
	# Grenadier: a gunner packing them puts one more frag in the squad's pool.
	# Once, not per holder - the blurb promises "one more", and the pool is
	# squad ordnance rather than anybody's webbing.
	for soldier in living_units(Unit.TEAM_SCOUT):
		if soldier.has_perk("grenadier"):
			frags_left += 1
			break
	_sync_throw_buttons()
	danger_button.toggled.connect(_on_danger_button_toggled)
	restart_button.pressed.connect(_on_restart)
	briefing_begin_button.pressed.connect(_dismiss_briefing)
	# Hotkeys/buttons cover the first 3 levels; extend the level_N input
	# actions and this button row alongside any new Levels.LEVELS entries.
	# On the win screen commit_mission() has already banked the XP and cleared
	# the rollback snapshot, so re-entering a level from here would bank it
	# again - an unbounded XP farm. Debug builds only, same as the hotkeys.
	var level_buttons: Array[Button] = [level_1_button, level_2_button, level_3_button]
	for i in level_buttons.size():
		if OS.is_debug_build() and i < Levels.LEVELS.size():
			level_buttons[i].pressed.connect(_go_to_level.bind(i))
		else:
			level_buttons[i].visible = false
	_refresh_objectives()
	_refresh_watch_cells()  # also settles everyone into whatever cover they spawned in
	_show_briefing()
	show_banner("%s  -  %s" % [Game.operation().name, level.name])
	player_turn_ready_msec = Time.get_ticks_msec()
	print("[ThinShot] level %d '%s', player turn 1 begins" % [
			Game.current_level + 1, level.name])
	_apply_cmdline_screenshot()


## Boot straight into a level: `godot --path . -- --level 2`. Everything after
## the bare `--` is ours. Exists so a headless run can smoke-test a level other
## than the first one, which is otherwise only reachable by playing to it.
func _apply_cmdline_level() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--level" and i + 1 < args.size():
			Game.select_level(int(args[i + 1]) - 1)
			return


## Save one settled frame to disk and quit:
## `godot --path . -- --level 1 --screenshot out.png`. The art pipeline's way
## of seeing a board. Must run WINDOWED - headless swaps in a dummy rasterizer
## that renders nothing, so it refuses rather than writing a black frame.
func _apply_cmdline_screenshot() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--screenshot" and i + 1 < args.size():
			_capture_screenshot(args[i + 1])
			return


func _capture_screenshot(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		push_error("[ThinShot] --screenshot needs a window; headless renders nothing")
		get_tree().quit(1)
		return
	# The shot exists to show the board, and the briefing would cover it.
	if briefing_panel.visible:
		_dismiss_briefing()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	print("[ThinShot] screenshot -> %s (%s) zoom=%s" % [
			path, "saved" if err == OK else error_string(err), camera.zoom])
	get_tree().quit(0 if err == OK else 1)


## Center the level on screen and zoom so it fits, leaving headroom for
## the banner (top) and the button row / unit panel (bottom).
func _fit_camera() -> void:
	var half_w := Board.TILE_W / 2.0
	var half_h := Board.TILE_H / 2.0
	var min_x := (0 - (board.size.y - 1)) * half_w - half_w
	var max_x := (board.size.x - 1) * half_w + half_w
	var min_y := -half_h
	var max_y := (board.size.x - 1 + board.size.y - 1) * half_h + half_h
	var world_size := Vector2(max_x - min_x, max_y - min_y)
	var view := get_viewport_rect().size
	var margin_top := 78.0
	var margin_bottom := 144.0
	var avail := Vector2(view.x - 60.0, view.y - margin_top - margin_bottom)
	var fit: float = minf(avail.x / world_size.x, avail.y / world_size.y)
	# Clamped at native texel density: floor texels 1:1 with screen pixels,
	# the 2x prop/unit class at an exact integer 2. Every shipped board fits
	# a 1920x1080 view at 1.0, so the clamp is what actually binds; the
	# eighths snap below stays only for hypothetically bigger boards, where
	# it keeps a fractional fit from smearing every tile seam. The logical
	# viewport is pinned under stretch canvas_items + aspect keep, so no
	# window resize can change `view` and no re-fit on resize is needed.
	fit = minf(fit, Board.MAX_ZOOM)
	fit = maxf(floorf(fit * 8.0) / 8.0, 0.25)
	camera.zoom = Vector2(fit, fit)
	var center_local := Vector2((min_x + max_x) / 2.0, (min_y + max_y) / 2.0)
	var screen_center_y := margin_top + avail.y / 2.0
	camera.position = board.to_global(center_local) \
			+ Vector2(0, (view.y / 2.0 - screen_center_y) / fit)
	# Cached so shake/kick can scale to screen space. Nothing else may write
	# camera.position or camera.zoom - the full board staying framed is the
	# contract that keeps the game readable.
	base_camera_pos = camera.position
	base_zoom = camera.zoom


## Three pooled particle layers: dust under the board's entities, debris
## above them, and an additive layer for anything that glows.
func _setup_fx_layers() -> void:
	fx_ground = Fx.new()
	# Between the FloorLayer (-2) and the Board's overlays (0): scorch marks
	# and casings belong on the ground, under the highlights, not over them.
	fx_ground.z_index = -1
	add_child(fx_ground)
	move_child(fx_ground, board.get_index() + 1)
	fx_air = Fx.new()
	add_child(fx_air)
	fx_glow = Fx.new()
	var glow_material := CanvasItemMaterial.new()
	glow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	fx_glow.material = glow_material
	fx_glow.z_index = 15
	add_child(fx_glow)
	objective_marks = ObjectiveMarks.new()
	add_child(objective_marks)
	# Steady desert wind across the board, plus the occasional gust.
	fx_air.set_ambient(_board_world_rect().grow(90.0), 26, Vector2(-34.0, 11.0))


## The board's extent in world space, used to frame the camera and to bound
## the ambient wind.
func _board_world_rect() -> Rect2:
	var half_w := Board.TILE_W / 2.0
	var half_h := Board.TILE_H / 2.0
	var min_x := (0 - (board.size.y - 1)) * half_w - half_w
	var max_x := (board.size.x - 1) * half_w + half_w
	var max_y := (board.size.x - 1 + board.size.y - 1) * half_h + half_h
	var origin := board.to_global(Vector2(min_x, -half_h))
	return Rect2(origin, Vector2(max_x - min_x, max_y + half_h))


func _validate_spawns() -> void:
	for spawn: Vector2i in level.scout_spawns + level.get("lead_spawns", []) \
			+ level.get("gunner_spawns", []) + level.goblin_spawns \
			+ level.get("smg_spawns", []) + level.get("smg_alt_spawns", []) \
			+ level.get("novice_spawns", []) + level.get("bolt_spawns", []):
		if not board.in_bounds(spawn) or not board.is_walkable(spawn):
			push_error("Bad spawn cell (blocked or out of bounds): %s" % spawn)
			assert(false, "Bad spawn cell: %s" % spawn)


## One salt per hash stream, so a rock and the junk beside it never correlate.
## The linear-congruence picks these replace repeated every few tiles along a
## row ((x*7+y*13) % 8 has period 8); Board._hash01 does not.
const SALT_ROCK := 4
const SALT_JUNK := 5
const SALT_PLANT := 6
const SALT_SANDBAG := 7
const SALT_CACHE := 8
const SALT_SWAY := 9
const SALT_STRUCT_PHASE := 10


## A deterministic pick out of `count` variants for this cell and stream.
func _prop_pick(cell: Vector2i, salt: int, count: int) -> int:
	return mini(int(Board._hash01(cell, _prop_seed + salt) * count), count - 1)


func _spawn_props() -> void:
	for y in board.size.y:
		for x in board.size.x:
			var cell := Vector2i(x, y)
			# Deterministic variant per cell so layouts are stable.
			match board.map_char(cell):
				"#":
					_spawn_prop(ROCK_TEXTURES[_prop_pick(cell, SALT_ROCK,
							ROCK_TEXTURES.size())], ROCK_OFFSET, cell)
				"j":
					_spawn_prop(JUNK_TEXTURES[_prop_pick(cell, SALT_JUNK,
							JUNK_TEXTURES.size())], JUNK_OFFSET, cell)
				"d":
					drums[cell] = {
						"sprite": _spawn_prop(DRUM_STILL, DRUM_OFFSET, cell),
						"spent": false,
					}
				"p":
					var plant := _spawn_prop(
							PLANT_TEXTURES[_prop_pick(cell, SALT_PLANT,
									PLANT_TEXTURES.size())],
							PLANT_OFFSET, cell)
					# Phase from the cell so no two plants sway in step.
					_swaying.append({
						"sprite": plant,
						"base_x": plant.position.x,
						"phase": Board._hash01(cell, _prop_seed + SALT_SWAY) * TAU,
					})
				"s":
					_spawn_prop(
							SANDBAG_TEXTURES[_prop_pick(cell, SALT_SANDBAG,
									SANDBAG_TEXTURES.size())],
							SANDBAG_OFFSET, cell)
				"c":
					_spawn_prop(
							CHOIR_CACHE_TEXTURES[_prop_pick(cell, SALT_CACHE,
									CHOIR_CACHE_TEXTURES.size())],
							CHOIR_CACHE_OFFSET, cell)
				"W":
					var kind := _wall_kind(cell)
					_spawn_prop(_wall_texture_for(kind), WALL_OFFSETS[kind], cell)
				"=":
					var run := _wire_kind(cell)
					_spawn_prop(WIRE_TEXTURES[run], WIRE_OFFSETS[run], cell)


## One dust material per depth band, built on demand and shared. Farther back
## on the board means more haze, which is what stops the far edge competing
## with the fight in front of it.
##
## The tint and haze colour come from the ground being fought on. The shader's
## own defaults are the desert's, so leaving them alone would warm-shift every
## prop toward sand and fade the far edge to tan on burnt ash - which is the
## collage this shader exists to prevent, just in a different direction.
func _dust_material(cell: Vector2i) -> ShaderMaterial:
	var span := maxi(board.size.x + board.size.y - 2, 1)
	var depth := 1.0 - float(cell.x + cell.y) / float(span)  # 1 at the far corner
	var band := clampi(int(depth * float(Board.HAZE_BANDS)), 0, Board.HAZE_BANDS - 1)
	if not _dust_materials.has(band):
		var mood := board.floor_mood()
		var mat := ShaderMaterial.new()
		mat.shader = PROP_DUST
		mat.set_shader_parameter("tint", mood.tint)
		mat.set_shader_parameter("haze_color", mood.haze)
		mat.set_shader_parameter("haze",
				Board.HAZE_MAX * (float(band) + 0.5) / float(Board.HAZE_BANDS))
		_dust_materials[band] = mat
	return _dust_materials[band]


func _spawn_prop(texture: Texture2D, offset: Vector2, cell: Vector2i,
		scale := 0.0, expected := 2.0) -> Sprite2D:
	# Every standing prop draws at the density class its art was authored for -
	# today that is 48px-class art doubled, everywhere. The guard compares each
	# call against ITS declared class rather than a hard-coded 2.0, so hi-res
	# 1x props can land per-prop without silencing the stray-scale alarm. Art
	# that cannot draw at its class gets downsampled, not scaled; the mast and
	# the structures stay 2x forever.
	if OS.is_debug_build() and scale > 0.0 and not is_equal_approx(scale, expected):
		push_error("[ThinShot] prop at %s spawned at %sx - normalise the art to "
				% [cell, scale] + "the %sx class instead" % expected)
	var prop := Sprite2D.new()
	prop.texture = texture
	prop.offset = offset
	prop.material = _dust_material(cell)
	prop.scale = ROCK_SCALE if scale <= 0.0 else Vector2(scale, scale)
	prop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	prop.position = board.cell_to_global(cell)
	entities_node.add_child(prop)
	return prop


func _wall_connects(cell: Vector2i) -> bool:
	return board.map_char(cell) == "W" or board.is_structure(cell)


## Wall runs along grid x read on the screen NW-SE diagonal; runs along
## grid y read NE-SW. Junctions use the flat face, lone cells the end cap.
func _wall_kind(cell: Vector2i) -> String:
	var has_x := _wall_connects(cell + Vector2i(1, 0)) or _wall_connects(cell + Vector2i(-1, 0))
	var has_y := _wall_connects(cell + Vector2i(0, 1)) or _wall_connects(cell + Vector2i(0, -1))
	if has_x and has_y:
		return "junction"
	if has_x:
		return "x_run"
	if has_y:
		return "y_run"
	return "cap"


## Wire runs read exactly like wall runs, but only wire continues a wire fence.
## A fence meeting a building has to cap off there rather than pretend the
## brick is more of the same.
func _wire_kind(cell: Vector2i) -> String:
	var has_x := board.map_char(cell + Vector2i(1, 0)) == "=" \
			or board.map_char(cell + Vector2i(-1, 0)) == "="
	var has_y := board.map_char(cell + Vector2i(0, 1)) == "=" \
			or board.map_char(cell + Vector2i(0, -1)) == "="
	if has_x and has_y:
		return "junction"
	if has_x:
		return "x_run"
	if has_y:
		return "y_run"
	return "cap"


func _wall_texture_for(kind: String) -> Texture2D:
	match kind:
		"x_run":
			return WALL_TEX_X_RUN
		"y_run":
			return WALL_TEX_Y_RUN
		"junction":
			return WALL_TEX_JUNCTION
	return WALL_TEX_CAP


## Structure art lives at <dir>/rotations/unknown.png, with an optional
## breeze loop beside it at <dir>/animations/<name>/unknown/frame_NNN.png.
## The animation folder is named after the prompt that generated it, so we
## scan for whatever is there instead of hardcoding the name.
## frame_000.png, frame_001.png ... from a folder, until they run out.
static func _load_frame_run(base: String) -> Array[Texture2D]:
	var frames: Array[Texture2D] = []
	var i := 0
	while true:
		var path := "%s/frame_%03d.png" % [base, i]
		if not ResourceLoader.exists(path):
			break
		frames.append(load(path))
		i += 1
	return frames


static func _load_structure_frames(dir: String) -> Array[Texture2D]:
	var frames: Array[Texture2D] = []
	var anim_root := dir + "/animations"
	var da := DirAccess.open(anim_root)
	if da != null:
		for sub in da.get_directories():
			frames = _load_frame_run("%s/%s/unknown" % [anim_root, sub])
			if not frames.is_empty():
				break
	if frames.is_empty():
		var still := dir + "/rotations/unknown.png"
		if ResourceLoader.exists(still):
			frames.append(load(still))
	return frames


func _load_structure_art() -> void:
	for kind: String in STRUCTURE_DIRS:
		structure_frames[kind] = _load_structure_frames(STRUCTURE_DIRS[kind])


## Multi-tile set-piece, cut into one vertical strip per footprint column, each
## under its own y-sort root at that column's front cell. A single root at the
## footprint's front corner sorted the whole building as one plane, so a unit
## standing beside a wide fortress popped in front of walls it was behind; per
## column, each strip sorts against what is actually in front of IT. Strip
## geometry is derived from where the old single sprite sat, so the reassembled
## art is pixel-identical.
func _spawn_structure(s: Dictionary) -> void:
	var anchor: Vector2i = s.anchor
	var struct_size: Vector2i = s.size
	var front: Vector2i = anchor + struct_size - Vector2i.ONE
	var frames: Array = structure_frames.get(s.kind, [])
	if frames.is_empty():
		push_error("No art found for structure kind '%s'" % s.kind)
		return
	var tex: Texture2D = frames[0]
	var strips: int = struct_size.x
	var strip_w := tex.get_width() / float(strips)
	# Where the single sprite's centre used to sit, in world space.
	var centre := (board.cell_to_global(anchor) + board.cell_to_global(front)) / 2.0
	var sprites: Array = []
	for i in strips:
		var root := Node2D.new()
		root.position = board.cell_to_global(anchor + Vector2i(i, struct_size.y - 1))
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.region_enabled = true
		spr.region_rect = Rect2(i * strip_w, 0.0, strip_w, tex.get_height())
		spr.scale = Vector2(2, 2)
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.material = _dust_material(front)  # same treatment as every other prop
		spr.offset = STRUCTURE_OFFSETS[s.kind]
		# This strip's region centre, offset from the full texture's centre at
		# the 2x draw scale, then rebased onto the strip's own root.
		spr.position = centre - root.position \
				+ Vector2(((float(i) + 0.5) * strip_w - tex.get_width() / 2.0) * 2.0, 0.0)
		root.add_child(spr)
		entities_node.add_child(root)
		sprites.append(spr)
	if frames.size() > 1:
		# Phase from the anchor cell so no two structures breathe in step.
		# One entry drives every strip - the building still animates as one.
		_animated_props.append({
			"sprites": sprites,
			"frames": frames,
			"phase": Board._hash01(anchor, _prop_seed + SALT_STRUCT_PHASE) \
					* 9.0 / STRUCTURE_FPS,
			"frame": -1,
		})


## `soldier` is the roster entry for a named scout, or {} for the Choir.
func _spawn_unit(kind: Unit.Kind, spawn_cell: Vector2i, soldier := {}) -> void:
	var unit: Unit = UNIT_SCENE.instantiate()
	entities_node.add_child(unit)
	unit.setup(kind, spawn_cell)
	if not soldier.is_empty():
		# Strictly after setup(), which assigns every stat from scratch.
		unit.apply_progression(soldier)
	unit.position = board.cell_to_global(spawn_cell)
	unit.shadow_color = board.shadow_tone(Unit.SHADOW_COLOR.a)
	unit.corpse_shadow_color = board.shadow_tone(Unit.CORPSE_SHADOW_COLOR.a)
	unit.died.connect(_on_unit_died)


## Walk a level's spawn list for one scout role alongside the roster slots for
## that role, so the same soldier lands in the same job every mission.
func _spawn_squad(kind: Unit.Kind, spawns: Array) -> void:
	var soldiers := Game.soldiers_of_kind(kind)
	# Only as many bodies as there are soldiers left alive to fill them. A
	# spawn point with nobody to stand on it simply goes unused - deploying an
	# anonymous unit there would quietly undo permadeath.
	for i in mini(spawns.size(), soldiers.size()):
		_spawn_unit(kind, spawns[i], soldiers[i])
	if soldiers.size() < spawns.size():
		print("[ThinShot] %s deploys %d of %d - the rest were lost" % [
				Unit.kind_role_name(kind), soldiers.size(), spawns.size()])


## Living units of a team that actually fight. The prisoner is on your side and
## walks out with the squad, but the Choir never shoots at them and losing every
## soldier is a wipe whether or not they are still standing.
func living_soldiers(team: int) -> Array[Unit]:
	var result: Array[Unit] = []
	for unit in living_units(team):
		if unit.is_combatant():
			result.append(unit)
	return result


## A soldier finishing a move beside a prisoner cuts them loose. No action, no
## button: reaching them IS the rescue, which keeps the objective about crossing
## the ground rather than remembering to press something once you are there.
func _free_reached_captives(mover: Unit) -> void:
	if not mover.is_combatant() or mover.team != Unit.TEAM_SCOUT:
		return
	for prisoner in captives():
		if Board.manhattan(mover.cell, prisoner.cell) > 1:
			continue
		prisoner.release()
		prisoner.set_facing((mover.position - prisoner.position).normalized())
		# They have not moved yet this turn, so they can walk the moment they
		# are up rather than standing there for a full round.
		prisoner.start_turn()
		Sfx.play("select", 0.0, 0.0)
		_award_xp(mover, Game.XP_RESCUE, "cut a prisoner loose")
		show_banner("PRISONER FREED")
		print("[ThinShot] %s reaches the prisoner at %s" % [
				mover.display_name(), prisoner.cell])
		_refresh_objectives()


## Every prisoner still waiting to be reached.
func captives() -> Array[Unit]:
	var result: Array[Unit] = []
	for unit in living_units(Unit.TEAM_SCOUT):
		if unit.captive:
			result.append(unit)
	return result


func living_units(team: int) -> Array[Unit]:
	var result: Array[Unit] = []
	for child in entities_node.get_children():
		var unit := child as Unit
		if unit != null and unit.is_alive():
			if unit.team == team:
				result.append(unit)
	return result


func unit_at(cell: Vector2i) -> Unit:
	for child in entities_node.get_children():
		var unit := child as Unit
		if unit != null and unit.is_alive() and unit.cell == cell:
			return unit
	return null


## Movement blocker for a given team: only enemies stop you. Soldiers
## squeeze past their own squadmates, which matters on maps built around
## one-tile gates. Ending a move on an occupied tile is still illegal -
## that is enforced separately, on the destination rather than the path.
func _blocked_for_team(cell: Vector2i, team: int) -> bool:
	var other := unit_at(cell)
	return other != null and other.team != team


## Of the cells a unit can reach, the ones it could actually stand on.
func _free_dests(reachable: Dictionary) -> Dictionary:
	var dests := {}
	for cell: Vector2i in reachable:
		if unit_at(cell) == null:
			dests[cell] = true
	return dests


# --- Player input ------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# The briefing eats mouse input by being a Control, but keyboard actions
	# would otherwise reach the board behind it.
	if briefing_panel.visible:
		return
	if state != State.PLAYER_TURN:
		return
	if event is InputEventMouseMotion:
		_update_hover(board.global_to_cell(get_global_mouse_position()))
		return
	if event.is_action_pressed("end_turn"):
		end_player_turn()
		return
	if event.is_action_pressed("overwatch"):
		_try_overwatch()
		return
	if event.is_action_pressed("burst"):
		_toggle_fire_mode(FireMode.BURST)
		return
	if event.is_action_pressed("full_auto"):
		_toggle_fire_mode(FireMode.AUTO)
		return
	if event.is_action_pressed("suppress"):
		_toggle_fire_mode(FireMode.SUPPRESS)
		return
	if event.is_action_pressed("reload"):
		_try_reload()
		return
	if event.is_action_pressed("throw_frag"):
		_try_throw(AimMode.THROW_FRAG)
		return
	if event.is_action_pressed("throw_smoke"):
		_try_throw(AimMode.THROW_SMOKE)
		return
	if event.is_action_pressed("demolish"):
		_try_demolish()
		return
	if event.is_action_pressed("hustle"):
		_try_hustle()
		return
	if event.is_action_pressed("ability_primary"):
		_use_ability(0)
		return
	if event.is_action_pressed("ability_secondary"):
		_use_ability(1)
		return
	if event.is_action_pressed("face"):
		_try_face()
		return
	if event.is_action_pressed("toggle_danger"):
		_toggle_danger()
		return
	if event.is_action_pressed("cycle_unit"):
		_cycle_unit()
		return
	# Jumping levels aborts the run and rewinds the campaign, with no
	# confirmation - a debug convenience that has no business being one
	# unmodified keypress away during play. Editor and debug builds only.
	if OS.is_debug_build():
		for i in mini(3, Levels.LEVELS.size()):
			if event.is_action_pressed("level_%d" % (i + 1)):
				_go_to_level(i)
				return
	if event.is_action_pressed("cancel"):
		if aim_mode != AimMode.NONE:
			_cancel_aim()
		else:
			deselect()
		return
	var mouse := event as InputEventMouseButton
	if mouse == null or not mouse.pressed:
		return
	if mouse.button_index == MOUSE_BUTTON_RIGHT:
		if aim_mode != AimMode.NONE:
			_cancel_aim()
		else:
			deselect()
		return
	if mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	var cell := board.global_to_cell(get_global_mouse_position())
	if not board.in_bounds(cell):
		return
	_handle_click(cell)


func _handle_click(cell: Vector2i) -> void:
	if aim_mode != AimMode.NONE and selected != null and cell != selected.cell:
		_commit_aim(cell)
		return
	var clicked := unit_at(cell)
	if selected != null:
		if clicked != null and clicked.team == Unit.TEAM_GOBLIN \
				and board.attack_cells.has(cell):
			_fire_selected_at(clicked)
			return
		# Clicking a drum in range puts a round into it.
		if _can_shoot_drum(selected, cell):
			do_shoot_drum(selected, cell)
			return
		# Clicking a cache in reach sets charges on it.
		if not _cache_at(cell).is_empty() and _can_demolish(selected, cell):
			_try_demolish(cell)
			return
		if board.move_dests.has(cell):
			do_move(selected, cell)
			return
	# Spent scouts stay selectable: turning to face is always available.
	if clicked != null and clicked.team == Unit.TEAM_SCOUT:
		select(clicked)
	else:
		deselect()


## Drops any direction-picking mode without touching the selection.
func _clear_aim_mode() -> void:
	if aim_mode == AimMode.NONE:
		return
	aim_mode = AimMode.NONE
	_sync_aim_buttons()
	board.set_blast_cells({}, true)
	if selected != null:
		selected.arc_preview_sector = -1
		selected.queue_redraw()
	_refresh_watch_cells()


## Shoot the target with whatever trigger setting is currently armed,
## falling back to the unit's default if the armed mode became unusable.
func _fire_selected_at(target: Unit) -> void:
	var mode := fire_mode
	if not _can_use_mode(selected, mode):
		mode = _default_fire_mode(selected)
		if not _can_use_mode(selected, mode):
			return
	match mode:
		FireMode.BURST:
			do_volley(selected, target, BURST_ROUNDS, BURST_GAP, 0)
		FireMode.AUTO:
			do_volley(selected, target, AUTO_ROUNDS, AUTO_GAP,
					_mode_accuracy(selected, FireMode.AUTO))
		FireMode.SUPPRESS:
			do_suppressive_fire(selected, target)
		_:
			do_attack(selected, target)


## The accuracy modifier a fire mode carries for this shooter - one function,
## so the panel's preview and the resolved volley can never disagree. Walking
## Fire pays another 10 points for firing full auto off the advance.
func _mode_accuracy(unit: Unit, mode: FireMode) -> int:
	if mode != FireMode.AUTO:
		return 0
	var mod := AUTO_ACCURACY
	if unit != null and unit.moved:
		mod += WALKING_FIRE_ACCURACY  # only reachable with walking_fire
	return mod


func select(unit: Unit) -> void:
	_clear_aim_mode()
	if selected != null:
		selected.set_selected(false)
	selected = unit
	unit.set_selected(true)
	_set_fire_mode(_default_fire_mode(unit))  # each soldier has its own default
	Sfx.play("select", 0.0, 0.0)
	_refresh_highlights()
	_update_unit_panel()


func deselect() -> void:
	_clear_aim_mode()
	if selected != null:
		selected.set_selected(false)
		selected = null
	_set_fire_mode(_default_fire_mode(selected))
	board.clear_highlights()
	_refresh_objectives()  # nothing selected, so no cache is in reach
	_update_unit_panel()


## The trigger setting a unit falls back to. The machinegunner has no
## semi-automatic position, so his rest state is burst.
func _default_fire_mode(unit: Unit) -> FireMode:
	return FireMode.SINGLE if unit != null and unit.can_single_shot() else FireMode.BURST


## Rounds a mode spends, so ammo can be checked before arming or firing.
func _rounds_for(mode: FireMode) -> int:
	match mode:
		FireMode.BURST:
			return BURST_ROUNDS
		FireMode.AUTO:
			return AUTO_ROUNDS
		FireMode.SUPPRESS:
			return SUPPRESS_ROUNDS
	return 1


func _can_use_mode(unit: Unit, mode: FireMode) -> bool:
	if unit == null or unit.acted or not _armed(unit) \
			or not unit.has_ammo(_rounds_for(mode)):
		return false
	match mode:
		FireMode.BURST:
			return unit.can_burst() and not (unit.burst_requires_still() and unit.moved)
		FireMode.AUTO:
			# Walking the gun needs a firing position, never the advance -
			# unless Walking Fire taught him to do it off the hip, for another
			# 10 points of accuracy (_mode_accuracy charges it).
			return unit.can_full_auto() \
					and (not unit.moved or unit.has_perk("walking_fire"))
		FireMode.SUPPRESS:
			return unit.can_suppress()
	return unit.can_single_shot()


## Toggle a firing mode on the selected unit, falling back to its default.
func _toggle_fire_mode(mode: FireMode) -> void:
	if fire_mode == mode:
		_set_fire_mode(_default_fire_mode(selected))
		return
	if state != State.PLAYER_TURN or not _can_use_mode(selected, mode):
		return
	_set_fire_mode(mode)
	Sfx.play("select", -3.0, 0.0)


func _set_fire_mode(mode: FireMode) -> void:
	if fire_mode == mode:
		return
	fire_mode = mode
	board.set_fire_mode(mode)
	_sync_fire_buttons()
	_update_unit_panel()


func _sync_fire_buttons() -> void:
	burst_button.set_pressed_no_signal(fire_mode == FireMode.BURST)
	auto_button.set_pressed_no_signal(fire_mode == FireMode.AUTO)
	suppress_button.set_pressed_no_signal(fire_mode == FireMode.SUPPRESS)


func _on_fire_button_toggled(pressed: bool, mode: FireMode) -> void:
	if pressed:
		_toggle_fire_mode(mode)
	elif fire_mode == mode:
		_set_fire_mode(_default_fire_mode(selected))
	_sync_fire_buttons()  # the request may have been refused


## Someone who can shoot, throw or demolish. A prisoner walks out with you and
## nothing more - and mag_size 0 means "unlimited" everywhere else, so without
## this they would inherit every weapon action by default.
func _armed(unit: Unit) -> bool:
	return unit.is_combatant()


## Select the next living scout that can still act, wrapping in spawn order.
## A prisoner joins the rotation only once freed - and only to be walked out.
func _cycle_unit() -> void:
	var ready: Array[Unit] = []
	for scout in living_units(Unit.TEAM_SCOUT):
		if scout.captive:
			continue
		if not scout.acted and (_armed(scout) or not scout.moved):
			ready.append(scout)
	if ready.is_empty():
		return
	select(ready[(ready.find(selected) + 1) % ready.size()])


## Bottom-left stat readout: hovered unit wins over the selected one.
func _update_unit_panel() -> void:
	# Every state change that could move an ability's usability funnels
	# through here already, so the two buttons ride along.
	_refresh_ability_buttons()
	var unit := unit_at(hover_cell) if hover_cell != Board.NO_CELL else null
	if unit == null:
		unit = selected
	if unit == null:
		unit_panel.visible = false
		return
	unit_panel.visible = true
	# Hovering a drum you could shoot: say what it would do rather than
	# describing whichever unit happens to be under the cursor.
	if selected != null and _can_shoot_drum(selected, hover_cell):
		var zone := _blast_cells_at(hover_cell)
		var in_blast := 0
		for other in living_units(Unit.TEAM_GOBLIN) + living_units(Unit.TEAM_SCOUT):
			if zone.has(other.cell):
				in_blast += 1
		unit_panel.visible = true
		panel_name_label.text = "Fuel Drum"
		panel_progress_label.text = "Volatile - one round sets it off"
		panel_hp_label.text = "%d damage at the centre, %d out" % [
				DRUM_DAMAGE, maxi(FRAG_DAMAGE - FRAG_FALLOFF, 1)]
		panel_stats_label.text = "Chains into any drum it reaches"
		panel_status_label.text = "SHOOT TO DETONATE - CATCHES %d" % in_blast
		panel_status_label.modulate = Color("ff9a3c")
		return
	panel_name_label.text = unit.display_name()
	panel_progress_label.text = _progress_text(unit)
	panel_hp_label.text = "HP %d / %d" % [unit.hp, unit.max_hp]
	panel_stats_label.text = "Move %d  Rng %d  Dmg %d  Acc %d%%%s" % [
			unit.move_range, unit.attack_range, unit.damage, unit.accuracy,
			"  Ammo %d/%d" % [unit.ammo, unit.mag_size] if unit.mag_size > 0 else ""]
	if aim_mode == AimMode.OVERWATCH and unit == selected:
		panel_status_label.text = "AIMING ARC - %d TILES, %d ROUND(S) IN REPLY" % [
				unit.overwatch_range(), unit.overwatch_rounds()]
		panel_status_label.modulate = Color("ffb84a")
		return
	if aim_mode == AimMode.CALLED_SHOT and selected != null:
		# Aiming the hero's called shot: quote the round the way the other
		# modes quote theirs - odds are the normal roll, cover buys nothing.
		if unit.team == Unit.TEAM_GOBLIN and _can_call_shot_at(selected, unit):
			# Quoted through the same function do_called_shot resolves through,
			# passed the same two arguments: One Shot's extra, and the trick
			# itself. Composing the number here instead is what let this line
			# quietly forget Executioner's point on a flanking called shot.
			var called := Rules.shot_preview(board, selected, unit, 0,
					_inspiration_bonus(selected),
					CALLED_SHOT_BONUS if selected.has_perk("one_shot") else 0, true)
			panel_status_label.text = "CALLED SHOT %d%% - %d DMG, IGNORES COVER" % [
					called.chance, called.dmg]
			panel_status_label.modulate = Color("7ae8ff")
			return
		if unit == selected:
			panel_status_label.text = "PICK CALLED SHOT TARGET"
			panel_status_label.modulate = Color("ffb84a")
			return
	if aim_mode == AimMode.THROW_FRAG and unit == selected:
		panel_status_label.text = "PICK FRAG TARGET - %d CROSS / %d CORNERS" % [
				FRAG_DAMAGE, maxi(FRAG_DAMAGE - FRAG_FALLOFF, 1)]
		panel_status_label.modulate = Color("ff8a3c")
		return
	if aim_mode == AimMode.THROW_SMOKE and unit == selected:
		panel_status_label.text = "PICK SMOKE TARGET"
		panel_status_label.modulate = Color("cfd4d8")
		return
	if aim_mode != AimMode.NONE and unit == selected:
		panel_status_label.text = "AIMING ARC" if aim_mode == AimMode.OVERWATCH \
				else "PICK A FACING"
		panel_status_label.modulate = Color("ffb84a")
		return
	# Hovering a shootable enemy: show what the shot would actually do.
	if unit.team == Unit.TEAM_GOBLIN and selected != null \
			and board.attack_cells.has(unit.cell):
		if fire_mode == FireMode.SUPPRESS:
			var caught := 0
			for goblin in living_units(Unit.TEAM_GOBLIN):
				if Board.manhattan(goblin.cell, unit.cell) <= selected.suppress_radius():
					caught += 1
			panel_status_label.text = \
					"SUPPRESS - NO DAMAGE - PINS %d: NO MOVE, -%d%% TO HIT" % [
							caught, SUPPRESSION_ACCURACY]
			panel_status_label.modulate = Unit.SUPPRESSED_COLOR
			return
		# The promise, straight from the function that will keep it. The panel
		# no longer re-derives the damage rule - it reads the answer and writes
		# the label, which is all a readout was ever supposed to do.
		var shot := Rules.shot_preview(board, selected, unit,
				_mode_accuracy(selected, fire_mode), _inspiration_bonus(selected))
		var flanking: bool = shot.flanking
		var note := ""
		if flanking:
			note = "FLANK"
		elif shot.cover == Board.CoverLevel.FULL:
			note = "FULL COVER"
		elif shot.cover == Board.CoverLevel.HALF:
			note = "HALF COVER"
		if shot.peeking:
			note = "PEEK" if note == "" else "PEEK - " + note
		# The burst note stays the panel's own: `dmg` is one round, and how many
		# rounds a mode sends is a controller question.
		var rounds := _rounds_for(fire_mode)
		if rounds > 1:
			var label := "AUTO" if fire_mode == FireMode.AUTO else "BURST"
			note = "x%d %s" % [rounds, label] if note == "" \
					else "x%d %s - %s" % [rounds, label, note]
		panel_status_label.text = "%d%% TO HIT - %d DMG%s" % [
				shot.chance, shot.dmg, "  " + note if note != "" else ""]
		panel_status_label.modulate = Color("7ae8ff") if flanking else Color.WHITE
		return
	if unit == selected and fire_mode != FireMode.SINGLE:
		match fire_mode:
			FireMode.AUTO:
				panel_status_label.text = "FULL AUTO ARMED"
				panel_status_label.modulate = Color("ff7a2a")
			FireMode.SUPPRESS:
				panel_status_label.text = "SUPPRESSIVE FIRE ARMED"
				panel_status_label.modulate = Unit.SUPPRESSED_COLOR
			_:
				panel_status_label.text = "BURST ARMED"
				panel_status_label.modulate = Color("ff7a2a")
		return
	if unit.is_suppressed():
		panel_status_label.text = "PINNED - CANNOT MOVE"
		panel_status_label.modulate = Unit.SUPPRESSED_COLOR
		return
	if unit.mag_size > 0 and unit.ammo == 0:
		panel_status_label.text = "OUT OF AMMO - RELOAD (R)"
		panel_status_label.modulate = Color("ff5a3c")
		return
	panel_status_label.text = _unit_status(unit)
	panel_status_label.modulate = Color("ffb84a") if unit.overwatching else Color.WHITE


func _unit_status(unit: Unit) -> String:
	if unit.overwatching and unit.overwatch_rounds() > 1:
		return "COVERING - %d TILES, %d ROUNDS" % [
				unit.overwatch_range(), unit.overwatch_rounds()]
	var cover := ""
	if unit.cover_level >= int(Board.CoverLevel.FULL):
		cover = " - IN FULL COVER"
	elif unit.cover_level >= int(Board.CoverLevel.HALF):
		cover = " - IN HALF COVER"
	if unit.overwatching:
		return "OVERWATCH" + cover
	if unit.acted:
		return "Done" + cover
	if unit.moved:
		return "Moved" + cover
	return "Ready" + cover


## Refill the selected scout's magazine. Costs the move, not the shot, so a
## dry scout can reload and still fire once - running out costs mobility,
## never a whole turn.
func _try_reload() -> void:
	if state != State.PLAYER_TURN or selected == null:
		return
	if selected.mag_size == 0 or selected.moved or selected.acted \
			or selected.ammo == selected.mag_size:
		return
	var scout := selected
	var prev_state := state
	state = State.ANIMATING
	# Reloading costs the move, not the shot - unless Quick Hands has drilled
	# it down to costing nothing at all.
	scout.moved = not scout.has_perk("quick_hands")
	_set_fire_mode(_default_fire_mode(selected))
	board.clear_highlights()
	Sfx.play("reload")
	print("[ThinShot] scout at %s reloads" % scout.cell)
	await scout.play_reload()
	scout.reload()  # magazine seats as the animation lands
	state = prev_state
	if state == State.PLAYER_TURN:
		_refresh_highlights()
		_update_unit_panel()


## Enter overwatch-aiming: the player picks which way the scout watches.
## Clicking a cell commits the arc; cancel/right-click backs out.
func _try_overwatch() -> void:
	if aim_mode == AimMode.OVERWATCH:
		_cancel_aim()
		return
	if state != State.PLAYER_TURN or selected == null or selected.acted \
			or not _armed(selected) or not selected.has_ammo() \
			or selected.is_suppressed():
		return
	aim_mode = AimMode.OVERWATCH
	_sync_aim_buttons()
	_set_fire_mode(_default_fire_mode(selected))
	board.clear_highlights()
	show_banner("CHOOSE OVERWATCH ARC")
	_update_hover(board.global_to_cell(get_global_mouse_position()))


## Enter free-turn aiming. Turning costs nothing and can be done any number
## of times, including after the unit has moved, shot, or gone on overwatch -
## what it buys is choosing which way you face for the enemy turn.
func _try_face() -> void:
	if aim_mode == AimMode.FACE:
		_cancel_aim()
		return
	if state != State.PLAYER_TURN or selected == null:
		return
	aim_mode = AimMode.FACE
	_sync_aim_buttons()
	_set_fire_mode(_default_fire_mode(selected))
	board.clear_highlights()
	show_banner("TURN TO FACE")
	_update_hover(board.global_to_cell(get_global_mouse_position()))


func _on_aim_button_toggled(pressed: bool, mode: AimMode) -> void:
	if pressed:
		match mode:
			AimMode.OVERWATCH:
				_try_overwatch()
			AimMode.FACE:
				_try_face()
			_:
				_try_throw(mode)
	elif aim_mode == mode:
		_cancel_aim()
	_sync_aim_buttons()  # the request may have been refused


## Keep the two mode buttons showing the real aim state.
func _sync_aim_buttons() -> void:
	overwatch_button.set_pressed_no_signal(aim_mode == AimMode.OVERWATCH)
	face_button.set_pressed_no_signal(aim_mode == AimMode.FACE)
	frag_button.set_pressed_no_signal(aim_mode == AimMode.THROW_FRAG)
	smoke_button.set_pressed_no_signal(aim_mode == AimMode.THROW_SMOKE)


func _cancel_aim() -> void:
	if aim_mode == AimMode.NONE:
		return
	_clear_aim_mode()
	_refresh_highlights()


## Commit the direction (or, for a grenade, the target cell) picked in
## whichever aim mode is active.
func _commit_aim(cell: Vector2i) -> void:
	var unit := selected
	var mode := aim_mode
	if mode == AimMode.CALLED_SHOT:
		var mark := unit_at(cell)
		if mark == null or mark.team != Unit.TEAM_GOBLIN \
				or not _can_call_shot_at(unit, mark):
			return  # not a target the shot can be called on: keep aiming
		aim_mode = AimMode.NONE
		_sync_aim_buttons()
		do_called_shot(unit, mark)
		return
	if mode == AimMode.THROW_FRAG or mode == AimMode.THROW_SMOKE:
		if not _can_target_throw(unit, cell):
			return  # out of range, out of sight, or solid: keep aiming
		aim_mode = AimMode.NONE
		_sync_aim_buttons()
		unit.arc_preview_sector = -1
		board.set_blast_cells({}, true)
		if mode == AimMode.THROW_FRAG:
			do_throw_frag(unit, cell)
		else:
			do_throw_smoke(unit, cell)
		return
	var sector := Board.sector_from_to(unit.cell, cell)
	aim_mode = AimMode.NONE
	_sync_aim_buttons()
	unit.arc_preview_sector = -1
	unit.set_facing_sector(sector)
	if mode == AimMode.FACE:
		# Free: the unit keeps whatever activation it had left.
		Sfx.play("select", -6.0, 0.0)
		print("[ThinShot] scout at %s turns to sector %d" % [unit.cell, sector])
		_refresh_watch_cells()
		_refresh_highlights()
		return
	deselect()
	unit.set_done(true)
	unit.set_overwatch(true)
	Sfx.play("overwatch_set", 0.0, 0.0)
	_refresh_watch_cells()
	print("[ThinShot] scout at %s watches sector %d" % [unit.cell, sector])


## Cells an overwatching unit would cover: in range, in arc, with LOS.
func _overwatch_cells_for(unit: Unit, sector: int) -> Dictionary:
	var cells := {}
	var r := unit.overwatch_range()  # the gunner watches further than he shoots
	for dy in range(-r, r + 1):
		var w := r - absi(dy)
		for dx in range(-w, w + 1):
			var cell: Vector2i = unit.cell + Vector2i(dx, dy)
			if cell == unit.cell or not board.in_bounds(cell) or not board.is_walkable(cell):
				continue
			var to_cell := Board.sector_from_to(unit.cell, cell)
			if absi(wrapi(to_cell - sector + 4, 0, 8) - 4) > unit.arc_half:
				continue
			if board.has_line_of_sight(unit.cell, cell):
				cells[cell] = true
	return cells


## Every overwatch arc on the board: hostile arcs (amber) are threats to
## route around, friendly arcs (green) are the ground you have covered.
## Hostile wins where they overlap.
## The best cover this unit is actually using: the strongest cover among the
## sectors inside its front arc. A soldier with its back to a wall is not
## behind it, so facing decides this as much as position does - which makes the
## free turn-to-face order a way to take cover.
func _cover_for(unit: Unit) -> int:
	var best := 0
	var by_sector := board.cover_map_at(unit.cell)
	for sector: int in by_sector:
		if unit.covers_sector(sector):
			best = maxi(best, int(by_sector[sector]))
	return best


func _refresh_cover() -> void:
	for team: int in [Unit.TEAM_SCOUT, Unit.TEAM_GOBLIN]:
		for unit in living_units(team):
			unit.set_in_cover(_cover_for(unit))


func _refresh_watch_cells() -> void:
	# Cover changes when a unit moves and when it turns, and every caller of
	# this already means "the board just changed", so the two stay in step.
	_refresh_cover()
	var cells := {}
	for team: int in [Unit.TEAM_SCOUT, Unit.TEAM_GOBLIN]:
		var hostile: bool = team == Unit.TEAM_GOBLIN
		for unit in living_units(team):
			if not unit.overwatching:
				continue
			for cell: Vector2i in _overwatch_cells_for(unit, unit.facing_sector):
				if hostile or not cells.has(cell):
					cells[cell] = hostile
	board.set_watch_cells(cells)


func _refresh_highlights() -> void:
	if selected == null:
		board.clear_highlights()
		return
	var moves := {}
	if not selected.moved and selected.can_move_freely():
		moves = board.flood_fill(selected.cell, selected.move_range,
				_blocked_for_team.bind(selected.team))
	var attacks: Array[Vector2i] = []
	if not selected.acted and selected.has_ammo():
		for enemy in living_units(Unit.TEAM_GOBLIN):
			if Board.manhattan(selected.cell, enemy.cell) <= selected.attack_range \
					and board.can_engage(selected.cell, enemy.cell):
				attacks.append(enemy.cell)
	# Even with no moves or targets, the unit stays selected: overwatch (W)
	# is always a legal order for a unit that has not attacked.
	var hazards := {}
	for cell: Vector2i in _drum_targets(selected):
		hazards[cell] = true
	board.set_highlights(moves, _free_dests(moves), attacks, hazards)
	# Mark every reachable tile that offers protection, so the player can see
	# the route between cover rather than discovering it a tile at a time.
	var covered := {}
	for cell: Vector2i in board.move_dests:
		if board.has_any_cover(cell):
			covered[cell] = true
	board.set_cover_overlay(selected.cell, covered)
	_refresh_objectives()  # which caches are in reach depends on the selection
	_update_hover(board.global_to_cell(get_global_mouse_position()))


## Derives hover feedback (tile outline, path preview, aim line) from the
## current selection and pushes it to the Board for rendering.
func _update_hover(cell: Vector2i) -> void:
	if not board.in_bounds(cell):
		cell = Board.NO_CELL
	hover_cell = cell
	# Aiming a grenade: the cursor picks the landing cell, and the footprint
	# it would catch is drawn outright. An unreachable cell shows nothing,
	# which is what tells the player the throw would be refused.
	if (aim_mode == AimMode.THROW_FRAG or aim_mode == AimMode.THROW_SMOKE) \
			and selected != null:
		var reachable := cell != Board.NO_CELL and _can_target_throw(selected, cell)
		board.set_blast_cells(_blast_cells_at(cell) if reachable else {},
				aim_mode == AimMode.THROW_FRAG)
		board.set_hover(cell, [], Board.NO_CELL)
		_update_unit_panel()
		return
	# Aiming a called shot: the cursor picks the enemy. A valid target gets
	# the aim line, anything else nothing - the refusal reads as a refusal.
	if aim_mode == AimMode.CALLED_SHOT and selected != null:
		var mark := unit_at(cell) if cell != Board.NO_CELL else null
		var can_call := mark != null and mark.team == Unit.TEAM_GOBLIN \
				and _can_call_shot_at(selected, mark)
		board.set_hover(cell, [], selected.cell if can_call else Board.NO_CELL)
		_update_unit_panel()
		return
	# Aiming an overwatch arc: the cursor steers the cone, nothing else.
	if aim_mode != AimMode.NONE and selected != null:
		var sector := Board.sector_from_to(selected.cell, cell) if cell != Board.NO_CELL else -1
		if sector != selected.arc_preview_sector:
			selected.arc_preview_sector = sector
			selected.queue_redraw()
			var cone := {}
			if sector >= 0:
				for watched: Vector2i in _overwatch_cells_for(selected, sector):
					cone[watched] = false  # ally-colored preview
			board.set_watch_cells(cone)
		board.set_hover(cell, [], Board.NO_CELL)
		_update_unit_panel()
		return
	var path: Array[Vector2i] = []
	var aim_from := Board.NO_CELL
	var aim_covered := false
	var aim_flanking := false
	# The beaten zone suppressive fire would shut down, previewed the same way
	# a grenade previews its footprint - it is a wide area and the player has
	# no way to judge it otherwise.
	var beaten := {}
	if selected != null and cell != Board.NO_CELL:
		if _can_shoot_drum(selected, cell):
			# Preview what the drum would take with it, the same way a grenade
			# previews its footprint.
			aim_from = selected.cell
			beaten = _blast_cells_at(cell)
			beaten[cell] = DRUM_DAMAGE
		elif board.move_dests.has(cell):
			path = board.reconstruct_path(board.move_cells, cell)
		elif board.attack_cells.has(cell):
			var target := unit_at(cell)
			aim_from = selected.cell
			if fire_mode == FireMode.SUPPRESS:
				beaten = _suppress_zone(cell, selected.suppress_radius())
			if target != null:
				# The aim line's colour is the panel's answer rather than a
				# second opinion about the same shot: one preview decides
				# both, so the line can never read FLANK while the readout
				# under it quotes cover. Only these two fields are wanted
				# here - the panel a few lines below quotes the numbers.
				var aim := Rules.shot_preview(board, selected, target)
				aim_flanking = aim.flanking
				aim_covered = aim.cover != Board.CoverLevel.NONE
	board.set_blast_cells(beaten, _can_shoot_drum(selected, cell))
	board.set_hover(cell, path, aim_from, aim_covered, aim_flanking)
	# Hovering somewhere you could move to previews the cover you would have
	# standing there; otherwise the overlay stays on the unit's own tile.
	if selected != null:
		board.set_cover_overlay(cell if board.move_dests.has(cell) else selected.cell,
				board.cover_dests)
	_update_unit_panel()


# --- Actions (shared by player and AI) ---------------------------------------

func do_move(unit: Unit, dest: Vector2i) -> void:
	var prev_state := state
	state = State.ANIMATING
	board.clear_highlights()
	var came_from := board.flood_fill(unit.cell, unit.move_range,
			_blocked_for_team.bind(unit.team))
	if not came_from.has(dest) or unit_at(dest) != null:
		state = prev_state
		return
	var path := board.reconstruct_path(came_from, dest)
	if unit.overwatching:
		# Only Protective Fire can produce a mover still on watch (its carried
		# overwatch survives start_turn). The stance does not survive walking.
		unit.set_overwatch(false)
		unit.lower_rifle()
		_refresh_watch_cells()
	unit.start_walking()
	var from_pos := unit.position
	for step_index in path.size():
		var step: Vector2i = path[step_index]
		var step_pos := board.cell_to_global(step)
		unit.set_facing(step_pos - from_pos)
		var tween := create_tween()
		tween.tween_property(unit, "position", step_pos, MOVE_STEP_TIME)
		await tween.finished
		Sfx.play("footstep_1" if step_index % 2 == 0 else "footstep_2")
		fx_ground.footstep(step_pos)
		unit.cell = step
		from_pos = step_pos
		var watchers := _overwatchers_against(unit)
		if not watchers.is_empty():
			unit.stop_walking()
			for watcher in watchers:
				if not unit.is_alive():
					break
				watcher.set_overwatch(false)  # consumed, even if the shot kills
				print("[ThinShot]   overwatch! %s fires %d at %s" % [
						watcher.cell, watcher.overwatch_rounds(), unit.cell])
				await _resolve_reaction(watcher, unit)
			if not unit.is_alive() or state == State.GAME_OVER:
				if selected == unit:
					deselect()
				if state != State.GAME_OVER:
					state = prev_state
					if prev_state == State.PLAYER_TURN:
						_refresh_danger()
						_update_unit_panel()
				return
			unit.start_walking()
	unit.stop_walking()
	unit.moved = true
	_free_reached_captives(unit)
	state = prev_state
	# Walking is itself an objective action on an extraction map, so the win
	# condition has to be re-tested the moment a scout stops moving.
	_refresh_objectives()
	if check_game_over():
		return
	if prev_state == State.PLAYER_TURN:
		# Moving invalidates the modes that need a still shooter (full auto
		# always, a scout's braced burst). Every other order that does this
		# resets the armed mode; without it the panel goes on quoting
		# "x4 AUTO @ 58%" while _fire_selected_at silently fires 2 at 73%.
		if selected == unit and not _can_use_mode(unit, fire_mode):
			_set_fire_mode(_default_fire_mode(unit))
		_refresh_danger()
		_refresh_watch_cells()
		_update_unit_panel()
		if selected == unit:
			_refresh_highlights()


func do_attack(attacker: Unit, target: Unit) -> void:
	var prev_state := state
	state = State.ANIMATING
	board.clear_highlights()
	await _resolve_shot(attacker, target, true)
	attacker.set_done(true)
	if attacker == selected:
		deselect()
	# A death inside take_damage triggers _on_unit_died -> check_game_over.
	if state == State.GAME_OVER:
		return
	state = prev_state
	if prev_state == State.PLAYER_TURN:
		_refresh_danger()
		_refresh_watch_cells()
		_update_unit_panel()


## Suppressive fire: the machinegunner's ability. Rounds go downrange around
## the target rather than into it - no damage, no hit rolls - and everything
## hostile at or beside the impact point is pinned. Trades killing for
## control: two goblins with their heads down instead of one wounded.
func do_suppressive_fire(attacker: Unit, target: Unit) -> void:
	var prev_state := state
	state = State.ANIMATING
	board.clear_highlights()
	print("[ThinShot] suppressive fire %s -> %s" % [attacker.cell, target.cell])
	var aim := (target.position - attacker.position).normalized()
	attacker.set_facing(aim)
	await attacker.raise_rifle()
	for i in SUPPRESS_ROUNDS:
		if i > 0:
			await get_tree().create_timer(AUTO_GAP).timeout
		await _fire_suppression_round(attacker, target)
	# Pin everything hostile inside the beaten zone. Locked Belts keeps their
	# heads down for an extra turn.
	var pin_turns := 3 if attacker.has_perk("locked_belts") else 2
	var pinned: Array[Vector2i] = []
	for unit in living_units(_enemy_team_of(attacker)):
		if Board.manhattan(unit.cell, target.cell) <= attacker.suppress_radius():
			unit.suppress(pin_turns)
			pinned.append(unit.cell)
	print("[ThinShot]   pinned %s for %d turn(s)" % [pinned, pin_turns - 1])
	# The gun does not stop. It keeps working the same ground until the
	# gunner's next turn, which is exactly as long as the pin lasts - so the
	# effect is visible on screen for its whole duration instead of being a
	# status icon nobody notices.
	_begin_sustained_fire(attacker, target.position)
	attacker.set_done(true)
	if attacker == selected:
		deselect()
	state = prev_state
	if prev_state == State.PLAYER_TURN:
		_refresh_danger()
		_refresh_watch_cells()
		_update_unit_panel()


## Every cell a burst of suppressing fire would pin, as a diamond of the
## gunner's suppress_radius() around the aim point. Solid cells are dropped -
## the rounds go over the ground, not through a wall.
func _suppress_zone(centre: Vector2i, radius: int) -> Dictionary:
	var zone := {}
	for dy in range(-radius, radius + 1):
		var w := radius - absi(dy)
		for dx in range(-w, w + 1):
			var cell: Vector2i = centre + Vector2i(dx, dy)
			if board.in_bounds(cell) and not board.is_blocker(cell):
				zone[cell] = 1
	return zone


## Keep the gun talking. The gunner holds his stance and works the same ground
## in short volleys for as long as the pin is on, which is what makes
## suppression legible: you can see the fire that is keeping their heads down.
## Purely presentational - the ammunition was already spent, and no further
## rounds are rolled or resolved.
func _begin_sustained_fire(gunner: Unit, at: Vector2) -> void:
	_suppressor = gunner
	_suppress_point = at
	_suppress_timer = SUSTAIN_VOLLEY_GAP
	_suppress_in_volley = 0


func _end_sustained_fire() -> void:
	if _suppressor == null:
		return
	if is_instance_valid(_suppressor) and _suppressor.is_alive():
		_suppressor.lower_rifle()
	_suppressor = null


func _sustain_suppression(delta: float) -> void:
	if _suppressor == null:
		return
	if not is_instance_valid(_suppressor) or not _suppressor.is_alive():
		_suppressor = null
		return
	_suppress_timer -= delta
	if _suppress_timer > 0.0:
		return
	# Rounds come in twos with a long pause between, so it reads as volleys
	# rather than a metronome.
	if _suppress_in_volley == 0:
		_suppress_in_volley = 1
		_suppress_timer = SUSTAIN_ROUND_GAP
	else:
		_suppress_in_volley = 0
		_suppress_timer = SUSTAIN_VOLLEY_GAP
	var muzzle := _suppressor.muzzle_point()
	var scatter := Vector2(_vis_rng.randf_range(-26, 26), _vis_rng.randf_range(-14, 14))
	var strike := _suppress_point + Vector2(0, -18) + scatter
	var dir := (strike - muzzle).normalized()
	_suppressor.recoil(dir)
	Sfx.play("shot", SUSTAIN_VOLUME)
	HitFx.spawn(fx_glow, muzzle, HitFx.Kind.MUZZLE)
	HitFx.spawn_tracer(fx_glow, muzzle, strike, TRACER_TIME)
	fx_glow.muzzle(muzzle, dir)
	fx_air.smoke_plume(muzzle, dir)
	fx_ground.casing(muzzle, dir)
	fx_ground.footstep(strike + Vector2(0, 20), 1.0)
	fx_ground.bullet_hole(strike + Vector2(0, 20), dir)


func _enemy_team_of(unit: Unit) -> int:
	return Unit.TEAM_GOBLIN if unit.team == Unit.TEAM_SCOUT else Unit.TEAM_SCOUT


# ------------------------------------------------------------- progression --
# XP is credited at the damage sites rather than from the died signal, which
# only carries the victim. Everything funnels through two call sites, and both
# already have the attacker in scope.


## Credit a kill, if a named soldier earned it against the Choir. Guards both
## directions: goblins earn nothing, and a frag that catches your own scout is
## not an achievement.
func _credit_kill(killer: Unit, victim: Unit) -> void:
	if killer == null or killer.soldier_id == 0:
		return
	if victim.team != Unit.TEAM_GOBLIN or killer.team != Unit.TEAM_SCOUT:
		return
	Game.award(killer.soldier_id, Game.XP_KILL)
	print("[ThinShot]   %s credited a kill (+%d xp)" % [
			killer.display_name(), Game.XP_KILL])


## Squad ordnance is shared, so a grenade charge is too. (The Grenadier perk
## this once anticipated exists now - see the frags_left bump in _ready.)
func _award_xp(unit: Unit, amount: int, reason: String) -> void:
	if unit == null or unit.soldier_id == 0:
		return
	Game.award(unit.soldier_id, amount)
	print("[ThinShot]   %s +%d xp (%s)" % [unit.display_name(), amount, reason])


## Hustle: give up the shot to move a second time. Reuses do_move untouched -
## all it does is hand the move back and spend the attack instead.
func _try_hustle() -> void:
	if state != State.PLAYER_TURN or selected == null:
		return
	if not selected.has_perk("hustle") or selected.acted or not selected.moved:
		return
	selected.moved = false
	selected.acted = true
	Sfx.play("select", -3.0, 0.0)
	print("[ThinShot] %s hustles - second move, no shot" % selected.display_name())
	_set_fire_mode(_default_fire_mode(selected))
	_refresh_highlights()
	_update_unit_panel()


# ------------------------------------------------------------ class actives --
# The abilities a perk hangs a button on. Two fixed slots: Q drives the first
# button, T the second, and each active owns a slot so the key its blurb
# promises is always the key that fires it.


## The selected-unit actives by button slot: [Q-slot perk, T-slot perk], with
## "" for a slot the soldier has nothing in. Called Shot and Field Dressing
## are Q abilities (no legitimate soldier holds both - different classes);
## Rally is the T one.
func _held_actives(unit: Unit) -> Array[String]:
	var primary := ""
	for perk in ["called_shot", "field_dressing"]:
		if unit.has_perk(perk):
			primary = perk
			break
	return [primary, "rally" if unit.has_perk("rally") else ""]


## Whether an active could fire right now - one function feeding both the
## button's disabled state and the keyboard path, so they can never disagree.
func _can_use_active(unit: Unit, perk: String) -> bool:
	if unit == null or state != State.PLAYER_TURN or _resolving_blast:
		return false
	match perk:
		"called_shot":
			# The whole turn goes into the shot: no move first, and a pinned
			# man cannot take the time it needs. Spends a round.
			return not unit.moved and not unit.acted and unit.has_ammo() \
					and not unit.is_suppressed()
		"rally":
			# Costs the attack and the battle's one charge. A suppressed hero
			# CAN rally - he is within his own reach, so it is how he unpins.
			return not unit.acted and not unit.rally_used
		"field_dressing":
			return not unit.acted and not unit.field_dressing_used \
					and unit.hp < unit.max_hp
	return false


## Keep the two ability buttons carrying the SELECTED unit's actives: hidden
## for a soldier with none (or no selection), disabled while unusable, and
## wearing their charge state in the label.
func _refresh_ability_buttons() -> void:
	var actives: Array[String] = ["", ""]
	if selected != null and selected.team == Unit.TEAM_SCOUT:
		actives = _held_actives(selected)
	var buttons: Array[Button] = [ability_1_button, ability_2_button]
	for i in buttons.size():
		var perk := actives[i]
		buttons[i].visible = not perk.is_empty()
		if perk.is_empty():
			continue
		var spent := (perk == "rally" and selected.rally_used) \
				or (perk == "field_dressing" and selected.field_dressing_used)
		buttons[i].text = str(ACTIVE_LABELS[perk]) + (" (spent)" if spent else "")
		buttons[i].disabled = not _can_use_active(selected, perk)


## Q (slot 0) / T (slot 1), and the two buttons: dispatch to whichever active
## the selected soldier holds in that slot.
func _use_ability(slot: int) -> void:
	if state != State.PLAYER_TURN or selected == null or _resolving_blast:
		return
	match _held_actives(selected)[slot]:
		"called_shot":
			_try_called_shot()
		"rally":
			_try_rally()
		"field_dressing":
			_try_field_dressing()


## A target Called Shot could take: a living goblin in the rifle's normal
## reach with an engageable line. Cover is no defence against it, but it is
## not extra reach either.
func _can_call_shot_at(attacker: Unit, target: Unit) -> bool:
	return target != null and target.is_alive() \
			and target.team == Unit.TEAM_GOBLIN \
			and Board.manhattan(attacker.cell, target.cell) <= attacker.attack_range \
			and board.can_engage(attacker.cell, target.cell)


## Arm the called shot: an aim mode like the throws, committed on an enemy.
func _try_called_shot() -> void:
	if aim_mode == AimMode.CALLED_SHOT:
		_cancel_aim()
		return
	if selected == null or not selected.has_perk("called_shot") \
			or not _can_use_active(selected, "called_shot"):
		return
	aim_mode = AimMode.CALLED_SHOT
	_sync_aim_buttons()
	_set_fire_mode(_default_fire_mode(selected))
	board.clear_highlights()
	show_banner("CHOOSE CALLED SHOT TARGET")
	_update_hover(board.global_to_cell(get_global_mouse_position()))


## Called Shot: the hero's aimed round. Takes the whole turn - no move first,
## nothing after - and goes where the cover is not: damage is never halved.
## The roll itself stays a normal one, full-cover penalty included.
func do_called_shot(attacker: Unit, target: Unit) -> void:
	var prev_state := state
	state = State.ANIMATING
	board.clear_highlights()
	print("[ThinShot] called shot %s -> %s" % [attacker.cell, target.cell])
	attacker.set_facing((target.position - attacker.position).normalized())
	await attacker.raise_rifle()
	await _fire_round(attacker, target, 0, true,
			CALLED_SHOT_BONUS if attacker.has_perk("one_shot") else 0)
	await get_tree().create_timer(LOWER_TIME).timeout
	attacker.lower_rifle()
	attacker.set_done(true)
	if attacker == selected:
		deselect()
	if state == State.GAME_OVER:
		return
	state = prev_state
	if prev_state == State.PLAYER_TURN:
		_refresh_danger()
		_refresh_watch_cells()
		_update_unit_panel()


func _try_rally() -> void:
	if selected == null or not selected.has_perk("rally") \
			or not _can_use_active(selected, "rally"):
		return
	do_rally(selected)


## Rally: the hero steadies every soldier within reach - pins come off, and
## their next shots land RALLY_ACCURACY better until each soldier's own next
## turn. Costs the attack and the battle's one charge; no ammunition.
func do_rally(hero: Unit) -> void:
	hero.rally_used = true
	hero.acted = true
	var steadied := 0
	for ally in living_soldiers(Unit.TEAM_SCOUT):
		if Board.manhattan(ally.cell, hero.cell) <= RALLY_RANGE:
			ally.rally(RALLY_ACCURACY)  # the hero is within 0 of himself
			steadied += 1
	Sfx.play("overwatch_set", 0.0, 0.3)
	show_banner("RALLY - THE SQUAD STEADIES")
	print("[ThinShot] %s rallies %d soldier(s)" % [hero.display_name(), steadied])
	_set_fire_mode(_default_fire_mode(selected))
	_refresh_highlights()
	_update_unit_panel()


func _try_field_dressing() -> void:
	if selected == null or not selected.has_perk("field_dressing") \
			or not _can_use_active(selected, "field_dressing"):
		return
	do_field_dressing(selected)


## Field Dressing: the scout patches himself up FIELD_DRESSING_HEAL, capped
## at full. Costs the attack and the battle's one charge; no ammunition.
func do_field_dressing(medic: Unit) -> void:
	medic.field_dressing_used = true
	medic.acted = true
	medic.heal(FIELD_DRESSING_HEAL)
	Sfx.play("reload", -2.0)
	print("[ThinShot] %s patches up to %d/%d HP" % [
			medic.display_name(), medic.hp, medic.max_hp])
	_set_fire_mode(_default_fire_mode(selected))
	_refresh_highlights()
	_update_unit_panel()


# -------------------------------------------------------------- objectives --
# Levels state what winning means rather than assuming a body count. The list
# is ordered and finished front to back, so a level can ask the squad to do a
# job and then get back out again.


func _objectives() -> Array:
	return level.get("objectives", [{"kind": "eliminate"}])


func _objective_complete(index: int) -> bool:
	var obj: Dictionary = _objectives()[index]
	match obj.get("kind", ""):
		"eliminate":
			return living_units(Unit.TEAM_GOBLIN).is_empty()
		"destroy":
			return _targets_left(index) == 0
		"rescue":
			# Reaching them is the whole objective; walking them out is the
			# extract objective's job.
			return captives().is_empty()
		"extract":
			# Only counts once the earlier jobs are done, so a squad cannot
			# simply walk off the map at turn one.
			for i in index:
				if not _objective_complete(i):
					return false
			var zone: Array = obj.get("cells", [])
			for scout in living_units(Unit.TEAM_SCOUT):
				if not zone.has(scout.cell):
					return false
			return true
	return false


func _all_objectives_complete() -> bool:
	for i in _objectives().size():
		if not _objective_complete(i):
			return false
	return true


## The objective the squad is actually working right now: the first unfinished
## one. Returns -1 when they are all done.
func _active_objective() -> int:
	for i in _objectives().size():
		if not _objective_complete(i):
			return i
	return -1


## Targets still standing for one objective. Counted per objective rather than
## globally, so a level can ask for two different things at once.
func _targets_left(index: int) -> int:
	var n := 0
	for target: Dictionary in caches:
		if int(target.obj) == index and not target.destroyed:
			n += 1
	return n


## An animation folder anywhere one level under a prop's directory. The mast
## keeps its upright loop under its own folder and its damaged loop under
## broken_state/, so searching beats hard-coding which state owns which.
static func _find_prop_anim(dir: String, anim: String) -> Array[Texture2D]:
	var da := DirAccess.open(dir)
	if da == null:
		return []
	for sub in da.get_directories():
		var frames := _load_frame_run("%s/%s/animations/%s/unknown" % [dir, sub, anim])
		if not frames.is_empty():
			return frames
	return []


static func _load_still(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null


func _load_target_art(kind: String) -> Dictionary:
	var spec: Dictionary = TARGET_PROPS[kind]
	var dir: String = spec.dir
	var art := {
		"still": _load_still("%s/%s/rotations/unknown.png" % [dir, spec.body]),
		"wreck": _load_still("%s/destroyed_state/rotations/unknown.png" % dir),
		"idles": [] as Array,
		"stages": [] as Array,
		"offset": spec.offset,
		"scale": float(spec.get("scale", 2.0)),
		"shadow": float(spec.get("shadow", 18.0)),
	}
	for name: String in spec.idles:
		art.idles.append(_find_prop_anim(dir, name))
	for name: String in spec.stages:
		art.stages.append(_find_prop_anim(dir, name))
	if art.stages.is_empty() or art.still == null:
		push_error("[ThinShot] objective prop '%s' has no art at %s" % [kind, dir])
	return art


## Objective props are markers and nothing else - they do not block movement or
## sight, so no pathing or LOS behaviour changes on a level that has them.
func _spawn_caches() -> void:
	for i in _objectives().size():
		var obj: Dictionary = _objectives()[i]
		if obj.get("kind", "") != "destroy":
			continue
		var kind: String = obj.get("prop", "crates")
		var art := _load_target_art(kind)
		for cell: Vector2i in obj.get("cells", []):
			var sprite := _spawn_prop(art.still, art.offset, cell, art.scale)
			_prop_shadows[cell] = art.shadow
			var target := {
				"cell": cell, "obj": i, "kind": kind, "art": art,
				"sprite": sprite, "stage": 0, "destroyed": false, "anim": null,
			}
			_set_target_idle(target)
			caches.append(target)


## Point the prop at the idle loop for its current state, if it has one. States
## with no loop simply hold their pose.
func _set_target_idle(target: Dictionary) -> void:
	var art: Dictionary = target.art
	var stage: int = int(target.stage)
	var idles: Array = art.idles
	var frames: Array = idles[stage] if stage < idles.size() else []
	if frames.is_empty():
		if target.anim != null:
			_animated_props.erase(target.anim)
			target.anim = null
		return
	if target.anim == null:
		target.anim = {
			"sprite": target.sprite, "frames": frames,
			"phase": Board._hash01(target.cell, _prop_seed + SALT_STRUCT_PHASE) \
					* 9.0 / STRUCTURE_FPS,
			"frame": -1,
		}
		_animated_props.append(target.anim)
	else:
		target.anim.frames = frames
		target.anim.frame = -1


## Cache cells still standing, each mapped to whether the selected scout could
## demolish it right now - which is what the Board draws the bright rim from.
func _cache_highlight() -> Dictionary:
	var cells := {}
	for cache: Dictionary in caches:
		if not cache.destroyed:
			cells[cache.cell] = _can_demolish(selected, cache.cell)
	return cells


func _refresh_objectives() -> void:
	var active := _active_objective()
	var extract_zone := {}
	var armed := false
	for i in _objectives().size():
		var obj: Dictionary = _objectives()[i]
		if obj.get("kind", "") != "extract":
			continue
		for cell: Vector2i in obj.get("cells", []):
			extract_zone[cell] = true
		# The zone only lights up once it is the live objective.
		armed = active == i
	board.set_objectives(_cache_highlight(), extract_zone, armed)
	# Beacons only over what still needs doing: intact caches, or the
	# extraction zone once it is actually open.
	var beacons: Array[Vector2] = []
	for cache: Dictionary in caches:
		if not cache.destroyed:
			beacons.append(board.cell_to_global(cache.cell))
	# A prisoner huddled among scenery is exactly as findable as a cache was
	# before it got a beacon, which is to say not.
	for prisoner in captives():
		beacons.append(prisoner.position)
	if objective_marks != null:
		objective_marks.set_marks(beacons)
	_update_objective_label()


## Every outstanding job, not just the first. A level can ask for two things at
## once, and showing only one of them makes the other look like scenery.
func _update_objective_label() -> void:
	var parts: Array[String] = []
	for i in _objectives().size():
		if _objective_complete(i):
			continue
		var obj: Dictionary = _objectives()[i]
		var text: String = obj.get("label", "")
		match obj.get("kind", ""):
			"eliminate":
				if text.is_empty():
					text = "DESTROY THE RUST CHOIR"
				text += " %d LEFT" % living_units(Unit.TEAM_GOBLIN).size()
			"destroy":
				var total: int = obj.get("cells", []).size()
				text += " %d/%d" % [total - _targets_left(i), total]
			"rescue":
				var held: int = level.get("prisoner_spawns", []).size()
				text += " %d/%d" % [held - captives().size(), held]
			"extract":
				var zone: Array = obj.get("cells", [])
				var home := 0
				for scout in living_units(Unit.TEAM_SCOUT):
					if zone.has(scout.cell):
						home += 1
				text += " %d/%d ABOARD" % [home, living_units(Unit.TEAM_SCOUT).size()]
				# The zone is inert until the earlier jobs are done, so say so
				# rather than showing a target that cannot be met yet.
				if i != _active_objective():
					text = "THEN " + text
		parts.append(text)
	objective_label.text = "     ".join(parts)


## A scout can demolish a cache it is standing on or beside, as long as it has
## not already acted. No ammunition involved - it is a charge, not a shot.
func _can_demolish(unit: Unit, cell: Vector2i) -> bool:
	return unit != null and unit.team == Unit.TEAM_SCOUT and not unit.acted \
			and Board.manhattan(unit.cell, cell) <= 1


func _cache_at(cell: Vector2i) -> Dictionary:
	for cache: Dictionary in caches:
		if not cache.destroyed and cache.cell == cell:
			return cache
	return {}


## Demolish the one adjacent cache, or the only one in reach if the player hit
## the key instead of clicking a specific pile.
func _try_demolish(cell := Board.NO_CELL) -> void:
	if state != State.PLAYER_TURN or selected == null or not _armed(selected):
		return
	var cache := _cache_at(cell) if cell != Board.NO_CELL else {}
	if cache.is_empty():
		for candidate: Dictionary in caches:
			if not candidate.destroyed and _can_demolish(selected, candidate.cell):
				cache = candidate
				break
	if cache.is_empty() or not _can_demolish(selected, cache.cell):
		return
	do_demolish(selected, cache)


## Play a prop's one-shot destruction stage through, frame by frame.
func _play_prop_stage(target: Dictionary, frames: Array) -> void:
	var sprite: Sprite2D = target.sprite
	if frames.is_empty() or not is_instance_valid(sprite):
		return
	for frame: Texture2D in frames:
		sprite.texture = frame
		await get_tree().create_timer(1.0 / PROP_FPS).timeout
		if not is_instance_valid(sprite):
			return


func do_demolish(scout: Unit, cache: Dictionary) -> void:
	var prev_state := state
	state = State.ANIMATING
	board.clear_highlights()
	var pos: Vector2 = board.cell_to_global(cache.cell)
	var art: Dictionary = cache.art
	var stage: int = int(cache.stage)
	var last: bool = stage + 1 >= (art.stages as Array).size()
	scout.set_facing((pos - scout.position).normalized())
	print("[ThinShot] scout at %s sets charges on the %s at %s (stage %d/%d)" % [
			scout.cell, cache.kind, cache.cell, stage + 1, (art.stages as Array).size()])
	await scout.play_reload()  # doubles as the setting-charges beat
	# The prop comes apart a stage at a time, so a two-stage target visibly
	# buckles before it goes down and the second charge is obviously needed.
	if cache.anim != null:
		_animated_props.erase(cache.anim)
		cache.anim = null
	Sfx.play("explosion")
	fx_air.explosion(pos + Vector2(0, -20))
	fx_ground.scorch(pos)
	_screen_shake(2.6)
	_camera_kick((pos - scout.position).normalized())
	await _hit_stop(0.25, 0.09)
	await _play_prop_stage(cache, art.stages[stage])
	cache.stage = stage + 1
	if last:
		cache.destroyed = true
		# Wreckage stays on the board - a razed objective should read as razed
		# rather than simply vanishing.
		var sprite: Sprite2D = cache.sprite
		if is_instance_valid(sprite) and art.wreck != null:
			sprite.texture = art.wreck
	else:
		_set_target_idle(cache)
	_award_xp(scout, Game.XP_CACHE, "demolition")
	scout.set_done(true)
	if scout == selected:
		deselect()
	state = prev_state
	_refresh_objectives()
	if check_game_over():
		return
	if prev_state == State.PLAYER_TURN:
		_refresh_highlights()
		_update_unit_panel()


# ---------------------------------------------------------------- ordnance --
# Grenades are the squad's answer to being outnumbered. They do not roll to
# hit and cover does not stop them, which makes them the only reliable damage
# on the field - and the only thing that touches more than one cell at once.


## The footprint a grenade covers, as cell -> damage: the full square around
## where it lands, diagonals included - nine cells at BLAST_RADIUS 1.
##
## Force falls off with distance from the burst, so the cross takes the full
## FRAG_DAMAGE and the corners, a step further out, take one less. That gives
## the blast an axis worth aiming rather than a uniform blob, and puts the
## softer edge exactly where a careless throw catches your own squad.
##
## Blockers are excluded, so a blast never reaches into a wall and smoke never
## sits inside one. Shared by both grenades, so the shape can never diverge -
## smoke simply ignores the values.
func _blast_cells_at(cell: Vector2i) -> Dictionary:
	var cells := {}
	for dy in range(-BLAST_RADIUS, BLAST_RADIUS + 1):
		for dx in range(-BLAST_RADIUS, BLAST_RADIUS + 1):
			var nxt := cell + Vector2i(dx, dy)
			if not board.in_bounds(nxt) or board.is_blocker(nxt):
				continue
			var steps := absi(dx) + absi(dy)
			cells[nxt] = maxi(FRAG_DAMAGE - maxi(steps - 1, 0) * FRAG_FALLOFF, 1)
	return cells


## An intact drum a unit could put a round into: in range, and visible.
func _can_shoot_drum(unit: Unit, cell: Vector2i) -> bool:
	if unit == null or unit.acted or not unit.has_ammo():
		return false
	if not drums.has(cell) or drums[cell].spent:
		return false
	return Board.manhattan(unit.cell, cell) <= unit.attack_range \
			and board.can_engage(unit.cell, cell)


## Every intact drum this unit could set off from where it stands.
func _drum_targets(unit: Unit) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell: Vector2i in drums:
		if _can_shoot_drum(unit, cell):
			out.append(cell)
	return out


## Put a round into a drum. A fuel drum is a big stationary object at the far
## end of a rifle, so there is no hit roll - the decision worth making is
## whether the shot is worth spending, not whether it lands.
func do_shoot_drum(shooter: Unit, cell: Vector2i) -> void:
	var prev_state := state
	state = State.ANIMATING
	board.clear_highlights()
	var pos := board.cell_to_global(cell)
	var muzzle := shooter.muzzle_point()
	var dir := (pos + Vector2(0, -20) - muzzle).normalized()
	print("[ThinShot] %s shoots the drum at %s" % [shooter.display_name(), cell])
	shooter.set_facing(dir)
	await shooter.raise_rifle()
	shooter.spend_ammo()
	shooter.recoil(dir)
	Sfx.play("shot")
	HitFx.spawn(fx_glow, muzzle, HitFx.Kind.MUZZLE)
	HitFx.spawn_tracer(fx_glow, muzzle, pos + Vector2(0, -20), TRACER_TIME)
	fx_glow.muzzle(muzzle, dir)
	fx_air.smoke_plume(muzzle, dir)
	fx_ground.casing(muzzle, dir)
	_camera_kick(dir)
	await get_tree().create_timer(TRACER_TIME).timeout
	# The round is the spark; everything after it is the drum's own doing.
	var blast := await _detonate_drums({cell: 0})
	_apply_blast(blast, pos, shooter, "drum")
	await get_tree().create_timer(LOWER_TIME).timeout
	shooter.lower_rifle()
	shooter.set_done(true)
	if shooter == selected:
		deselect()
	if state == State.GAME_OVER:
		return
	state = prev_state
	if prev_state == State.PLAYER_TURN:
		_refresh_danger()
		_refresh_watch_cells()
		_update_unit_panel()


## Set off every fuel drum inside a blast, and every drum those blasts reach,
## until the fire runs out of fuel. Returns the combined damage map, keeping
## the harshest value any single blast dealt to each cell.
##
## Each drum is spent exactly once, which is what stops two adjacent drums
## setting each other off forever.
func _detonate_drums(blast: Dictionary) -> Dictionary:
	var combined := blast.duplicate()
	var queue: Array[Vector2i] = []
	for cell: Vector2i in blast:
		if drums.has(cell) and not drums[cell].spent:
			queue.append(cell)
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		var drum: Dictionary = drums[cell]
		if drum.spent:
			continue
		drum.spent = true
		var pos := board.cell_to_global(cell)
		print("[ThinShot]   fuel drum at %s goes up" % cell)
		Sfx.play("explosion")
		fx_air.explosion(pos + Vector2(0, -18))
		fx_ground.scorch(pos)
		_screen_shake(2.2)
		var sprite: Sprite2D = drum.sprite
		if is_instance_valid(sprite):
			var frames := _find_prop_anim(DRUM_DIR, "normal_to_destroyed")
			await _play_prop_stage({"sprite": sprite}, frames)
			if is_instance_valid(sprite):
				sprite.texture = DRUM_WRECK
		# Its own blast, which may reach the next drum along.
		var spread := _blast_cells_at(cell)
		for hit: Vector2i in spread:
			var dmg: int = int(spread[hit])
			if hit == cell:
				dmg = DRUM_DAMAGE
			if int(combined.get(hit, 0)) < dmg:
				combined[hit] = dmg
			if drums.has(hit) and not drums[hit].spent:
				queue.append(hit)
	return combined


## A grenade can be released at any cell in range that the thrower can see and
## that is not solid. Junk counts - lobbing onto the scrap the Choir is hiding
## behind is the whole point.
func _can_target_throw(thrower: Unit, cell: Vector2i) -> bool:
	return board.in_bounds(cell) and not board.is_blocker(cell) \
			and Board.manhattan(thrower.cell, cell) <= THROW_RANGE \
			and board.has_line_of_sight(thrower.cell, cell)


func _charges_for(mode: AimMode) -> int:
	return frags_left if mode == AimMode.THROW_FRAG else smokes_left


## Enter throw-aiming. Costs the attack when it lands, never the move, so a
## soldier can advance and then throw.
func _try_throw(mode: AimMode) -> void:
	if aim_mode == mode:
		_cancel_aim()
		return
	if state != State.PLAYER_TURN or selected == null or selected.acted \
			or not _armed(selected) or _charges_for(mode) <= 0:
		return
	aim_mode = mode
	_sync_aim_buttons()
	_set_fire_mode(_default_fire_mode(selected))
	board.clear_highlights()
	show_banner("CHOOSE FRAG TARGET" if mode == AimMode.THROW_FRAG
			else "CHOOSE SMOKE TARGET")
	_update_hover(board.global_to_cell(get_global_mouse_position()))


## The grenade itself, arcing over whatever is in the way. Drawn as a handful
## of short-lived motes stepped along a parabola rather than a real node.
func _throw_arc(from_pos: Vector2, to_pos: Vector2) -> void:
	var steps := 9
	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		var lift := -THROW_ARC_HEIGHT * 4.0 * t * (1.0 - t)  # peaks at midpoint
		fx_air.smoke_drift(from_pos.lerp(to_pos, t) + Vector2(0, lift - 30.0))
		await get_tree().create_timer(THROW_ARC_TIME / float(steps)).timeout


## Shared throw preamble: face the target, arc the grenade over, spend the
## thrower's activation.
func _deliver_throw(thrower: Unit, cell: Vector2i) -> void:
	var landing := board.cell_to_global(cell)
	thrower.set_facing((landing - thrower.position).normalized())
	await thrower.raise_rifle()
	Sfx.play("select", -3.0, 0.0)
	await _throw_arc(thrower.muzzle_point(), landing)
	thrower.lower_rifle()


func do_throw_frag(thrower: Unit, cell: Vector2i) -> void:
	var prev_state := state
	state = State.ANIMATING
	board.clear_highlights()
	frags_left -= 1
	print("[ThinShot] frag %s -> %s (%d left)" % [thrower.cell, cell, frags_left])
	await _deliver_throw(thrower, cell)
	var blast := _blast_cells_at(cell)
	var center := board.cell_to_global(cell)
	Sfx.play("explosion")
	# One full detonation at the centre. The outer cells get dust and smoke
	# only - five explosions would evict the whole particle pool and the
	# blast would read as less, not more.
	fx_air.explosion(center + Vector2(0, -20))
	for hit_cell: Vector2i in blast:
		var pos := board.cell_to_global(hit_cell)
		fx_ground.scorch(pos)
		if hit_cell != cell:
			fx_ground.footstep(pos, 2.0)
			# Two per outer cell rather than three: the footprint doubled to
			# nine, and the centre detonation must not get evicted from the
			# particle pool by its own dust.
			for i in 2:
				fx_air.smoke_drift(pos + Vector2(0, -16))
	_screen_shake(2.6)
	_camera_kick((center - thrower.position).normalized())
	await _hit_stop(0.25, 0.09)
	# Anything flammable inside the footprint goes up too, and its own blast
	# can reach the next drum along - so a line of them is a fuse.
	blast = await _detonate_drums(blast)
	_apply_blast(blast, center, thrower, "frag")
	_finish_throw(thrower, prev_state)


## Hand out a blast's damage. Everything standing in the footprint takes it,
## both sides, with no hit roll and no cover - how hard depends only on which
## cell they were caught in. Shared by grenades and by anything that goes up.
func _apply_blast(blast: Dictionary, center: Vector2, source: Unit, what: String) -> void:
	var caught: Array[Unit] = []
	for unit in living_units(Unit.TEAM_GOBLIN) + living_units(Unit.TEAM_SCOUT):
		# Prisoners come through a blast untouched. Being able to frag the
		# person you came to rescue is the kind of thing that turns a rescue
		# into a chore, and the Choir wants them alive anyway.
		if blast.has(unit.cell) and unit.is_combatant():
			caught.append(unit)
	# The whole footprint resolves before anyone asks who won. `caught` lists
	# goblins first, so a blast that kills the last goblin AND a scout would
	# otherwise commit the mission - awarding the scout his survival XP and
	# clearing the rollback snapshot - and only then kill him, leaving him
	# scored as a survivor in the debrief and dead on the roster.
	_resolving_blast = true
	for unit in caught:
		var dmg: int = int(blast[unit.cell])
		if dmg <= 0:
			continue
		var away := (unit.position - center).normalized()
		fx_air.blood_mist(unit.position + Vector2(0, -36), away, unit.hp <= dmg)
		# Credited before the damage lands, while the victim is still alive to
		# be inspected. _credit_kill ignores friendly fire.
		if unit.hp <= dmg:
			_credit_kill(source, unit)
		unit.take_damage(dmg, away)
		print("[ThinShot]   %s hits %s at %s for %d" % [
				what, unit.display_name(), unit.cell, dmg])
	print("[ThinShot]   %s caught %d unit(s)" % [what, caught.size()])
	_resolving_blast = false
	check_game_over()


func do_throw_smoke(thrower: Unit, cell: Vector2i) -> void:
	var prev_state := state
	state = State.ANIMATING
	board.clear_highlights()
	smokes_left -= 1
	print("[ThinShot] smoke %s -> %s (%d left)" % [thrower.cell, cell, smokes_left])
	await _deliver_throw(thrower, cell)
	var cloud := _blast_cells_at(cell)
	Sfx.play("smoke_pop")
	for smoke_cell: Vector2i in cloud:
		smoke[smoke_cell] = SMOKE_TURNS
		var pos := board.cell_to_global(smoke_cell)
		for i in 7:
			fx_air.smoke_drift(pos)
	_apply_smoke()
	print("[ThinShot]   smoke covers %d cell(s)" % cloud.size())
	_finish_throw(thrower, prev_state)


## Spend the thrower's turn and put the board back the way the shot paths do.
func _finish_throw(thrower: Unit, prev_state: State) -> void:
	thrower.set_done(true)
	if thrower == selected:
		deselect()
	if state == State.GAME_OVER:
		return
	state = prev_state
	if prev_state == State.PLAYER_TURN:
		_refresh_danger()
		_refresh_watch_cells()
		_update_unit_panel()
	_sync_throw_buttons()


## Push the live cloud to the board. Everything that depends on sight -
## overwatch cones, the danger overlay, the AI's own checks - reads
## has_line_of_sight, so this one call is the whole propagation.
func _apply_smoke() -> void:
	board.set_smoke(smoke.duplicate())
	_refresh_watch_cells()
	_refresh_danger()


## Age the clouds by one player turn and clear the spent ones.
func _tick_smoke() -> void:
	if smoke.is_empty():
		return
	for cell: Vector2i in smoke.keys():
		smoke[cell] -= 1
		if smoke[cell] <= 0:
			smoke.erase(cell)
	_apply_smoke()


func _sync_throw_buttons() -> void:
	frag_button.text = "Frag %d (G)" % frags_left
	smoke_button.text = "Smoke %d (C)" % smokes_left
	frag_button.disabled = frags_left <= 0
	smoke_button.disabled = smokes_left <= 0


## One round of suppressing fire: full muzzle presentation, but the round
## deliberately strikes the ground around the target instead of the target.
func _fire_suppression_round(attacker: Unit, target: Unit) -> void:
	var muzzle := attacker.muzzle_point()
	var chest := target.position + Vector2(0, -36)
	var dir := (chest - muzzle).normalized()
	var splash := chest + dir * _vis_rng.randf_range(10.0, 40.0) \
			+ dir.orthogonal() * _vis_rng.randf_range(-30.0, 30.0)
	attacker.spend_ammo()
	attacker.recoil(dir)
	Sfx.play("shot")
	HitFx.spawn(fx_glow, muzzle, HitFx.Kind.MUZZLE)
	HitFx.spawn_tracer(fx_glow, muzzle, splash, TRACER_TIME)
	fx_glow.muzzle(muzzle, dir)
	fx_air.smoke_plume(muzzle, dir)
	fx_ground.casing(muzzle, dir)
	_camera_kick(dir)
	await get_tree().create_timer(TRACER_TIME).timeout
	Sfx.play("miss")
	var strike := splash + Vector2(0, 26)
	fx_ground.footstep(strike, 1.4)
	fx_ground.bullet_hole(strike, dir)
	_screen_shake(0.6)


## A reaction shot off overwatch. The rifle is already up, so there is no raise
## beat - and the gunner answers with a burst, which is what makes his watch
## read as covering the ground rather than guarding a line.
func _resolve_reaction(watcher: Unit, target: Unit) -> void:
	watcher.set_facing((target.position - watcher.position).normalized())
	for i in watcher.overwatch_rounds():
		if i > 0:
			await get_tree().create_timer(BURST_GAP).timeout
		await _fire_round(watcher, target)
		# Stop on a kill, a finished battle, or an empty belt rather than
		# firing rounds that have nowhere to go.
		if not target.is_alive() or state == State.GAME_OVER \
				or not watcher.has_ammo():
			break
	await get_tree().create_timer(LOWER_TIME).timeout
	watcher.lower_rifle()


## The shot itself: face, (optionally) raise the rifle via the transition
## animation, fire one round, lower. Reaction shots skip the raise -
## the rifle is already up from overwatch.
func _resolve_shot(attacker: Unit, target: Unit, with_aim_beat: bool) -> void:
	var aim := (target.position - attacker.position).normalized()
	attacker.set_facing(aim)
	if with_aim_beat:
		await attacker.raise_rifle()
	await _fire_round(attacker, target)
	await get_tree().create_timer(LOWER_TIME).timeout
	attacker.lower_rifle()


## One round leaving the muzzle: effects, sound, cover-checked damage.
## Assumes the attacker is already facing the target with rifle raised.
## `ignore_cover` is the called shot's whole trick - the roll stays normal but
## the damage is never halved; `bonus_damage` carries One Shot's extra.
func _fire_round(attacker: Unit, target: Unit, accuracy_mod := 0,
		ignore_cover := false, bonus_damage := 0) -> void:
	var muzzle := attacker.muzzle_point()
	# Leaning out: shift the muzzle toward the cell being leaned into, so the
	# round visibly comes around the corner instead of through the wall.
	var peek := board.peek_origin(attacker.cell, target.cell)
	if peek != Board.NO_CELL:
		var lean := board.cell_to_global(peek) - board.cell_to_global(attacker.cell)
		muzzle += lean * PEEK_LEAN
		attacker.lean(lean * PEEK_LEAN)
	var chest := target.position + Vector2(0, -36)
	var dir := (chest - muzzle).normalized()
	# The whole shot, asked once and asked early: the number to roll against,
	# the damage it will do, and which of the two the log should describe. This
	# is the same call the panel made while the player was still hovering, which
	# is precisely what makes the promise on screen and the round out of the
	# barrel the same shot rather than two shots that happen to match. Taken
	# before the tracer's flight, so flank and cover are read at one instant
	# instead of one on each side of an await.
	var shot := Rules.shot_preview(board, attacker, target, accuracy_mod,
			_inspiration_bonus(attacker), bonus_damage, ignore_cover)
	var flanking: bool = shot.flanking
	# Sparks come off whatever the target is actually hunkered behind.
	var covered_cell := Board.NO_CELL
	if not flanking:
		covered_cell = board.cover_source(attacker.cell, target.cell)
	var chance: int = shot.chance
	var hit := _rules_rng.randi_range(1, 100) <= chance
	# A miss sails past the target and off to one side.
	var impact_point := chest if hit else chest + dir * 54.0 \
			+ dir.orthogonal() * _vis_rng.randf_range(-34.0, 34.0)

	attacker.spend_ammo()
	attacker.recoil(dir)
	Sfx.play("shot")
	HitFx.spawn(fx_glow, muzzle, HitFx.Kind.MUZZLE)
	HitFx.spawn_tracer(fx_glow, muzzle, impact_point, TRACER_TIME)
	fx_glow.muzzle(muzzle, dir)
	fx_air.smoke_plume(muzzle, dir)  # non-additive layer so smoke reads as smoke
	fx_ground.footstep(attacker.position, 0.5)  # blast dust at the shooter's feet
	fx_ground.casing(muzzle, dir)
	_camera_kick(dir)

	# Sparks off the junk pile the round clips, timed to when it passes.
	if covered_cell != Board.NO_CELL:
		var travel := Vector2(target.cell - attacker.cell).length()
		var f: float = Vector2(covered_cell - attacker.cell).length() / maxf(travel, 0.001)
		_spark_cover(covered_cell, dir, TRACER_TIME * f)

	await get_tree().create_timer(TRACER_TIME).timeout

	if not hit:
		print("[ThinShot]   %s -> %s MISSES (%d%%)" % [
				attacker.cell, target.cell, chance])
		Sfx.play("miss")
		var strike := impact_point + Vector2(0, 30)
		fx_ground.footstep(strike, 1.2)  # dust where it lands
		fx_ground.bullet_hole(strike, dir)
		target.spawn_miss_text()
		_update_unit_panel()
		return

	# Both numbers were settled above; all that is left is to say which happened.
	# `cover` is already NONE if this round was a called shot, so the log never
	# claims a wall the damage did not pay for.
	var dmg: int = shot.dmg
	var cover: Board.CoverLevel = shot.cover
	if cover != Board.CoverLevel.NONE:
		print("[ThinShot]   shot %s -> %s into %s cover: %d dmg (%d%%)" % [
				attacker.cell, target.cell,
				"full" if cover == Board.CoverLevel.FULL else "half", dmg, chance])
	elif flanking:
		print("[ThinShot]   flanking shot %s -> %s: %d dmg (%d%%)" % [
				attacker.cell, target.cell, dmg, chance])
	var lethal := target.hp - dmg <= 0

	Sfx.play("hit_impact")
	HitFx.spawn(fx_glow, chest, HitFx.Kind.IMPACT)
	fx_air.impact(chest, dir, lethal)
	fx_air.blood_mist(chest, dir, lethal)
	fx_ground.blood_spray(chest, target.position.y, dir, lethal)
	_screen_shake(1.6 if lethal else 1.0)
	if lethal:
		_credit_kill(attacker, target)
	target.take_damage(dmg, dir)
	# A hit from outside the front arc knocks the target off overwatch.
	if flanking and target.is_alive() and target.overwatching:
		target.set_overwatch(false)
		target.lower_rifle()
	_update_unit_panel()  # keep hovered-unit HP live even during enemy fire
	await _hit_stop(0.09 if lethal else 0.14, 0.075 if lethal else 0.045)


## Percent chance this shot connects, from Rules - which owns the arithmetic
## and the numbers, and knows nothing about the scene tree. Battle supplies the
## two things it cannot reach for itself: the board, and the inspiration aura,
## which has to be found by walking the living units.
##
## Like the three forwarders further down, this now has no caller in the
## controller: the panel and the resolver both take their chance off the same
## Rules.shot_preview that hands them the damage, so the two can never be
## quoted from different moments. It survives for tools/test_progression.gd,
## which measures Rally and Inspiration through a booted Battle and wants the
## aura included exactly as a real shot would include it.
func hit_chance(attacker: Unit, target: Unit, accuracy_mod := 0) -> int:
	return Rules.hit_chance(board, attacker, target, accuracy_mod,
			_inspiration_bonus(attacker))


## Inspiration's aura: +5 to hit while a living allied hero carrying the perk
## stands within 4 tiles of the SHOOTER. The hero inspires himself too -
## simpler than excluding him, and a leader who believes his own speech is
## not a bug.
func _inspiration_bonus(attacker: Unit) -> int:
	for unit in living_units(attacker.team):
		if unit.kind == Unit.Kind.HERO and unit.has_perk("inspiration") \
				and Board.manhattan(unit.cell, attacker.cell) <= INSPIRATION_RANGE:
			return INSPIRATION_ACCURACY
	return 0


## Fire-and-forget spark on the junk cell the round passes through.
func _spark_cover(cell: Vector2i, dir: Vector2, delay: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if not is_instance_valid(fx_glow):
		return
	var at := board.cell_to_global(cell)
	fx_glow.cover_spark(at + Vector2(0, -20), dir)
	fx_ground.bullet_hole(at + Vector2(_vis_rng.randf_range(-14, 14), 0), dir, true)


## A multi-round volley. Each round is cover- and accuracy-checked on its
## own; the volley stops early if the target drops. Full auto walks the gun
## across the target, trading accuracy per round for volume, and pins
## whoever it was aimed at whether or not the rounds connect.
func do_volley(attacker: Unit, target: Unit, rounds: int, gap: float,
		accuracy_mod: int) -> void:
	var prev_state := state
	state = State.ANIMATING
	board.clear_highlights()
	print("[ThinShot] %d-round volley %s -> %s" % [rounds, attacker.cell, target.cell])
	var aim := (target.position - attacker.position).normalized()
	attacker.set_facing(aim)
	await attacker.raise_rifle()
	for i in rounds:
		if i > 0:
			await get_tree().create_timer(gap).timeout
		await _fire_round(attacker, target, accuracy_mod)
		if not target.is_alive() or state == State.GAME_OVER \
				or not attacker.has_ammo():
			break
	await get_tree().create_timer(LOWER_TIME).timeout
	attacker.lower_rifle()
	attacker.set_done(true)
	if attacker == selected:
		deselect()
	if state == State.GAME_OVER:
		return
	state = prev_state
	if prev_state == State.PLAYER_TURN:
		_refresh_danger()
		_refresh_watch_cells()
		_update_unit_panel()


# --- Danger overlay ----------------------------------------------------------

## Every tile some living goblin could shoot next turn: reachable move cells
## (plus standing still) expanded by attack range with line of sight.
## Projected with the same rule the goblins actually move under, so the
## overlay cannot promise safety that the enemy turn then breaks. Occupied
## cells are left in as firing origins on purpose - goblins act one at a
## time and vacate them for each other, so over-warning is the safe error.
func _compute_danger_cells() -> Dictionary:
	var danger := {}
	for goblin in living_units(Unit.TEAM_GOBLIN):
		var origins: Array = board.flood_fill(goblin.cell, goblin.move_range,
				_blocked_for_team.bind(goblin.team)).keys()
		origins.append(goblin.cell)
		var r := goblin.attack_range
		for origin: Vector2i in origins:
			for dy in range(-r, r + 1):
				var w := r - absi(dy)
				for dx in range(-w, w + 1):
					var tile := origin + Vector2i(dx, dy)
					if danger.has(tile) or not board.in_bounds(tile) \
							or not board.is_walkable(tile):
						continue
					# can_engage, not has_line_of_sight: the goblins pick their
					# targets with can_engage (via _shootable_from), so a plain
					# LOS test here paints every lean-around-cover shot SAFE -
					# precisely the corners the player is taught to bound between.
					if board.can_engage(origin, tile):
						danger[tile] = true
	return danger


func _refresh_danger() -> void:
	board.set_danger(_compute_danger_cells() if danger_on else {})


func _toggle_danger() -> void:
	danger_on = not danger_on
	danger_button.set_pressed_no_signal(danger_on)
	_refresh_danger()


func _on_danger_button_toggled(pressed: bool) -> void:
	danger_on = pressed
	_refresh_danger()


# Three one-line forwarders into Rules, kept under their old names. The
# controller itself no longer asks any of them: every shot it quotes or fires
# now comes from one Rules.shot_preview call, which is the point. What still
# calls them is tools/test_progression.gd, which reaches through a booted
# Battle to check flank and cover on the shipped map's real geometry - a
# seam worth keeping, and three lines is a cheap price for it.
# The rules themselves, and the reasoning behind them, are in scripts/Rules.gd.

func _is_flanking(attacker: Unit, target: Unit) -> bool:
	return Rules.is_flanking(attacker, target)


func effective_cover(attacker: Unit, target: Unit) -> Board.CoverLevel:
	return Rules.effective_cover(board, attacker, target)


func _is_peeking(attacker: Unit, target: Unit) -> bool:
	return Rules.is_peeking(board, attacker, target)


## Living enemies of the mover that are on overwatch with range, LOS, and
## the mover inside their covered arc.
func _overwatchers_against(mover: Unit) -> Array[Unit]:
	var result: Array[Unit] = []
	if not mover.is_combatant():
		return result  # nobody wastes a reaction shot on the prisoner
	for child in entities_node.get_children():
		var watcher := child as Unit
		if watcher == null or not watcher.is_alive() or not watcher.overwatching:
			continue
		if watcher.team == mover.team or not watcher.has_ammo():
			continue
		if Board.manhattan(watcher.cell, mover.cell) <= watcher.overwatch_range() \
				and watcher.covers_sector(Board.sector_from_to(watcher.cell, mover.cell)) \
				and board.has_line_of_sight(watcher.cell, mover.cell):
			result.append(watcher)
	return result


# --- Turn flow ---------------------------------------------------------------

func end_player_turn() -> void:
	if state != State.PLAYER_TURN or enemy_turn_running:
		return
	if Time.get_ticks_msec() - player_turn_ready_msec < END_TURN_GRACE_MS:
		return
	enemy_turn_running = true
	deselect()
	board.set_danger({})
	state = State.ENEMY_TURN
	print("[ThinShot] enemy turn %d begins" % turn_number)
	Sfx.play("turn_enemy", 0.0, 0.0)
	show_banner("RUST CHOIR'S TURN")
	end_turn_button.disabled = true
	overwatch_button.disabled = true
	burst_button.disabled = true
	auto_button.disabled = true
	suppress_button.disabled = true
	reload_button.disabled = true
	face_button.disabled = true
	danger_button.disabled = true
	demolish_button.disabled = true
	frag_button.disabled = true
	smoke_button.disabled = true
	ability_1_button.disabled = true
	ability_2_button.disabled = true
	# Goblins refresh at the start of THEIR turn (expires last turn's
	# unfired goblin overwatch at the right moment).
	for goblin in living_units(Unit.TEAM_GOBLIN):
		goblin.start_turn()
	await run_enemy_turn()
	enemy_turn_running = false
	if state == State.GAME_OVER:
		return
	# Scouts refresh for the new player turn (expiring unfired overwatch);
	# goblins just undim so they don't look pre-acted - but keep any
	# overwatch stance they set up, since it stays armed through this turn.
	for unit in living_units(Unit.TEAM_SCOUT):
		unit.start_turn()
	for goblin in living_units(Unit.TEAM_GOBLIN):
		goblin.set_done(false)
	turn_number += 1
	print("[ThinShot] player turn %d begins" % turn_number)
	Sfx.play("turn_player", 0.0, 0.0)
	end_turn_button.disabled = false
	overwatch_button.disabled = false
	burst_button.disabled = false
	auto_button.disabled = false
	suppress_button.disabled = false
	reload_button.disabled = false
	face_button.disabled = false
	danger_button.disabled = false
	demolish_button.disabled = false
	_sync_throw_buttons()  # respects charges rather than blanket-enabling
	# Smoke thrown last turn has now covered the enemy turn it was meant to
	# cover, so it burns off as control comes back.
	_tick_smoke()
	# The pin expires as the goblins refresh, so the gun stops with it.
	_end_sustained_fire()
	show_banner("DESERT SCOUTS' TURN")
	state = State.PLAYER_TURN
	player_turn_ready_msec = Time.get_ticks_msec()
	_refresh_danger()
	_refresh_watch_cells()
	_refresh_objectives()
	_update_unit_panel()


func run_enemy_turn() -> void:
	var squad := living_units(Unit.TEAM_GOBLIN)
	var acted := 0
	for goblin in squad:
		if not is_instance_valid(goblin) or not goblin.is_alive():
			continue
		var scouts := living_soldiers(Unit.TEAM_SCOUT)
		if scouts.is_empty():
			return
		acted += 1
		var from_cell := goblin.cell
		# Mark the actor and give the player a beat to find it before it
		# moves. The beat is taken out of AI_BEAT, so turns stay the same
		# length - the player's eye just arrives before the motion.
		goblin.set_selected(true)
		goblin.set_acting(true)
		await get_tree().create_timer(ACT_LEAD_IN).timeout
		# An empty weapon is worked before anything else is decided, and costs
		# the move - the same rule the scouts reload under.
		var reloaded := await _ai_reload(goblin, acted, squad.size())
		var shootable := _shootable_from(goblin.cell, goblin.attack_range, scouts)
		if goblin.has_ammo() and not shootable.is_empty():
			print("[ThinShot]   goblin %d/%d shoots from %s" % [acted, squad.size(), from_cell])
			await _ai_fire(goblin, _nearest(goblin.cell, shootable))
		else:
			var moved_now := false
			# Working the bolt already spent the move, and a pinned goblin
			# holds where it is - it can still shoot from there, badly.
			if not reloaded and goblin.can_move():
				var target := _nearest(goblin.cell, scouts)
				var reach := board.flood_fill(goblin.cell, goblin.move_range,
						_blocked_for_team.bind(goblin.team))
				var dest := _best_ai_dest(goblin, reach, scouts, target.cell)
				moved_now = board.in_bounds(dest) and dest != goblin.cell
				if moved_now:
					await do_move(goblin, dest)
			shootable = _shootable_from(goblin.cell, goblin.attack_range,
					living_soldiers(Unit.TEAM_SCOUT))
			var shoots := goblin.is_alive() and goblin.has_ammo() and not shootable.is_empty()
			print("[ThinShot]   goblin %d/%d %s %s -> %s%s" % [
					acted, squad.size(), "reloads at" if reloaded else "moves",
					from_cell, goblin.cell, ", shoots" if shoots else ""])
			if shoots:
				await _ai_fire(goblin, _nearest(goblin.cell, shootable))
			elif not moved_now and goblin.is_alive() and not goblin.is_suppressed() \
					and goblin.has_ammo():
				# Dug in with no shot: watch the lane the scouts must cross. A
				# pinned goblin keeps its head down instead, and a dry one has
				# nothing to react with.
				goblin.set_facing_sector(_best_watch_sector(goblin, scouts))
				goblin.set_overwatch(true)
				Sfx.play("overwatch_set", -4.0, 0.0)
				print("[ThinShot]   goblin %d/%d holds %s on overwatch" % [
						acted, squad.size(), goblin.cell])
		goblin.set_selected(false)
		goblin.set_acting(false)
		if state == State.GAME_OVER:
			return
		await get_tree().create_timer(AI_BEAT).timeout


## Works a dry AI weapon. Costs the move rather than the shot, mirroring
## _try_reload, so a unit that reloads can still fire the same turn but cannot
## reposition - which is the whole shape of the bolt-action marksman: he holds
## his ground for exactly as long as he keeps shooting. Returns whether a
## reload happened, since that is what spends the move.
func _ai_reload(goblin: Unit, index: int, squad_size: int) -> bool:
	if not goblin.needs_reload():
		return false
	goblin.moved = true
	Sfx.play("reload")
	print("[ThinShot]   goblin %d/%d reloads at %s" % [index, squad_size, goblin.cell])
	await goblin.play_reload()
	goblin.reload()  # magazine seats as the animation lands
	return true


## AI units shoot with the heaviest setting their weapon allows, so a raider
## empties a burst instead of squeezing off one round like a rifleman.
func _ai_fire(attacker: Unit, target: Unit) -> void:
	if _can_use_mode(attacker, FireMode.BURST):
		await do_volley(attacker, target, BURST_ROUNDS, BURST_GAP, 0)
	else:
		await do_attack(attacker, target)


func _shootable_from(from_cell: Vector2i, attack_range: int, targets: Array[Unit]) -> Array[Unit]:
	var result: Array[Unit] = []
	for unit in targets:
		if Board.manhattan(from_cell, unit.cell) <= attack_range \
				and board.can_engage(from_cell, unit.cell):
			result.append(unit)
	return result


func _nearest(from_cell: Vector2i, candidates: Array[Unit]) -> Unit:
	var best: Unit = candidates[0]
	for unit in candidates:
		if Board.manhattan(from_cell, unit.cell) < Board.manhattan(from_cell, best.cell):
			best = unit
	return best


## How exposed a cell is to scout fire: 2 per clean firing line, 1 per line
## that has to cross junk (those shots only land for half damage). This is
## what makes the goblins actually value the cover on the map.
func _exposure_at(cell: Vector2i, scouts: Array[Unit]) -> int:
	var score := 0
	for scout in scouts:
		if Board.manhattan(cell, scout.cell) <= scout.attack_range \
				and board.can_engage(scout.cell, cell):
			# Now measured from the cover the cell itself would give, which is
			# what makes the AI move wall to wall rather than just away.
			match board.cover_between(scout.cell, cell):
				Board.CoverLevel.FULL:
					score += 0
				Board.CoverLevel.HALF:
					score += 1
				_:
					score += 2
	return score


## Best move destination for an AI unit. A cell it can shoot a scout from
## beats every cell it can't; exposure to scout fire costs a little when
## healthy and a lot when wounded (so 1 HP goblins with no shot retreat to
## cover); nearer the chase target breaks remaining ties.
## `reach` is the flood_fill result (cell -> predecessor), which also tells us
## which way the goblin would be facing when it arrives.
func _best_ai_dest(goblin: Unit, reach: Dictionary, scouts: Array[Unit],
		chase_cell: Vector2i) -> Vector2i:
	var exposure_weight := 25 if goblin.hp <= 2 else 2
	# Reachable cells include squadmates' tiles, which can be crossed but
	# not occupied; standing still is always an option.
	var candidates: Array = _free_dests(reach).keys()
	candidates.append(goblin.cell)
	var best := Vector2i(-1, -1)
	var best_score := 999999
	for cell: Vector2i in candidates:
		var score := Board.manhattan(cell, chase_cell)
		score += exposure_weight * _exposure_at(cell, scouts)
		var shots := _shootable_from(cell, goblin.attack_range, scouts)
		var end_sector := -1
		if not shots.is_empty():
			var mark := _nearest(cell, shots)
			end_sector = Board.sector_from_to(cell, mark.cell)
			score -= 1000
			# A clean firing position beats one where the target is dug in.
			if board.cover_between(cell, mark.cell) != Board.CoverLevel.NONE:
				score += 400
			# Shooting someone in the back bypasses their cover.
			if not mark.covers_sector(Board.sector_from_to(mark.cell, cell)):
				score -= 60
		elif reach.has(cell):
			end_sector = Board.sector_from_to(reach[cell], cell)
		# Do not turn your back on the rest of the squad.
		if end_sector >= 0:
			for scout in scouts:
				if Board.manhattan(cell, scout.cell) <= scout.attack_range \
						and board.has_line_of_sight(scout.cell, cell) \
						and absi(wrapi(Board.sector_from_to(cell, scout.cell)
								- end_sector + 4, 0, 8) - 4) > goblin.arc_half:
					score += 6
		if score < best_score:
			best_score = score
			best = cell
	return best


## Which way a dug-in goblin should watch: the arc covering the most cells
## the scouts could advance through. Integer scoring keeps ties deterministic.
func _best_watch_sector(goblin: Unit, scouts: Array[Unit]) -> int:
	var approach := {}
	for scout in scouts:
		approach.merge(board.flood_fill(scout.cell, scout.move_range,
				_blocked_for_team.bind(scout.team)))
		approach[scout.cell] = true
	var best_sector := goblin.facing_sector
	var best_count := -1
	for sector in 8:
		var count := 0
		for cell: Vector2i in _overwatch_cells_for(goblin, sector):
			if approach.has(cell):
				count += 1
		if count > best_count:
			best_count = count
			best_sector = sector
	return best_sector


# --- Win / lose --------------------------------------------------------------

func _on_unit_died(unit: Unit) -> void:
	if unit.soldier_id != 0:
		# Provisional: abort_mission() puts them back if the mission is lost
		# and retried, so only a won mission makes a death permanent.
		Game.mark_dead(unit.soldier_id)
		print("[ThinShot] %s is down" % unit.display_name())
	Sfx.play("unit_death")
	fx_ground.stain(unit.position)
	_drop_rifle(unit)
	_puff_on_landing(unit)
	_refresh_objectives()  # the remaining-goblin count and extract tally move
	# A blast resolves as one action: _apply_blast runs the check itself once
	# the whole footprint has been dealt, so that the last casualty on either
	# side is counted before the mission is scored.
	if not _resolving_blast:
		check_game_over()


## Only your own dead leave a rifle. The Choir loses eleven bodies on a bad
## map and eleven rifles would be litter; five soldiers is a squad, and the
## mark one of them leaves should still be there ten turns later when you
## walk back past it. Prisoners carried nothing to drop.
func _drop_rifle(unit: Unit) -> void:
	if unit.team != Unit.TEAM_SCOUT or not unit.is_combatant():
		return
	var rifle := _spawn_prop(RIFLE_TEXTURES[unit.facing_sector], RIFLE_OFFSET, unit.cell)
	# Nudged toward the camera so it clears the body it fell from. Entities are
	# y-sorted, so that also puts it in front rather than under.
	rifle.position += RIFLE_DROP


## Dust kicked up when the falling body actually hits the ground, rather
## than when it starts to fall.
func _puff_on_landing(unit: Unit) -> void:
	await get_tree().create_timer(unit.death_landing_time()).timeout
	if is_instance_valid(fx_ground) and is_instance_valid(unit):
		fx_ground.death_puff(unit.position)


func check_game_over() -> bool:
	if state == State.GAME_OVER:
		return true
	# Losing is unconditional and checked first: no objective saves a squad
	# that is already dead.
	# A wipe is every soldier down. A prisoner left standing alone is not a
	# squad, and cannot finish anything.
	if living_soldiers(Unit.TEAM_SCOUT).is_empty():
		_show_game_over("THE CHOIR SINGS ON", false)
		return true
	# Rodar is the campaign: if he deployed and is down, the mission is lost
	# no matter who else is still standing. After the wipe check so a full
	# wipe still reads as one. His corpse stays in the tree, so the fallen
	# hero is found here rather than tracked by a flag.
	var fallen_hero := _fallen_hero()
	if fallen_hero != null:
		_show_game_over("RODAR AKAI HAS FALLEN", false,
				fallen_hero.death_landing_time())
		return true
	if _all_objectives_complete():
		_show_game_over("DESERT SCOUTS WIN", true)
		return true
	return false


## The hero's corpse, if the battle fielded him and he is down; null while he
## lives or when the level never deployed him (a roster short of its hero
## simply fights without one - it must not read as an instant loss).
func _fallen_hero() -> Unit:
	for child in entities_node.get_children():
		var unit := child as Unit
		if unit != null and unit.kind == Unit.Kind.HERO and not unit.is_alive():
			return unit
	return null


## panel_delay holds back only the verdict's PRESENTATION - state flips to
## GAME_OVER immediately, so the re-entry guard and every call site see the
## same synchronous contract as before. Used when the loss is one body
## falling: the panel waits for it to land instead of covering the fall.
func _show_game_over(text: String, won: bool, panel_delay := 0.0) -> void:
	state = State.GAME_OVER
	# The only other teardown is at the top of end_player_turn, which sits
	# behind a GAME_OVER early-out - so without this the machinegun keeps
	# cycling a volley every SUSTAIN_VOLLEY_GAP behind the results panel.
	_end_sustained_fire()
	last_result_won = won
	print("[ThinShot] level %d over on turn %d: %s" % [
			Game.current_level + 1, turn_number, "WON" if won else "LOST"])
	if won:
		# Walking off the map is worth something on its own - to the soldiers
		# who did the walking. The people they carried out are not on the roster.
		for scout in living_soldiers(Unit.TEAM_SCOUT):
			_award_xp(scout, Game.XP_SURVIVE, "survived")
		Game.commit_mission()
	else:
		# Nothing earned in a failed attempt sticks, so retrying cannot be
		# farmed for XP - and the fallen are un-killed along with it.
		Game.abort_mission()
	if won and Game.is_last_level():
		text = "CAMPAIGN COMPLETE - THE WASTES FALL SILENT"
	result_label.text = text
	# The story beat only lands on a win - a failed attempt is not part of it.
	narrative_label.text = str(level.get("debrief", "")) if won else ""
	debrief_label.text = _debrief_text(won)
	# Where the squad wakes up next is the difference between a tent and home.
	if not won:
		restart_button.text = "Back to Camp"
	elif Game.is_last_level():
		restart_button.text = "Play Again"
	elif Game.is_last_of_operation():
		restart_button.text = "Return to Garrison"
	else:
		restart_button.text = "Back to Camp"
	if not Game.pending_promotions.is_empty():
		debrief_label.text += "\n\n%d PROMOTION(S) TO HAND OUT BACK AT CAMP" % \
				Game.pending_promotions.size()
	if panel_delay > 0.0:
		get_tree().create_timer(panel_delay).timeout.connect(
				_present_game_over.bind(won))
	else:
		_present_game_over(won)


func _present_game_over(won: bool) -> void:
	game_over_panel.visible = true
	Sfx.play("win" if won else "lose", 0.0, 0.0)


## The panel's second row: role for anyone, plus rank progress and earned
## specialties for a named soldier.
func _progress_text(unit: Unit) -> String:
	if unit.soldier_id == 0:
		return unit.role_name()
	var soldier := Game.soldier_by_id(unit.soldier_id)
	var xp: int = int(soldier.get("xp", 0))
	var parts: Array[String] = [unit.role_name()]
	var to_next := Game.xp_to_next(xp)
	parts.append("%d xp" % xp if to_next < 0 else "%d xp (+%d)" % [xp, to_next])
	for perk: String in unit.perks:
		parts.append(str(Game.PERKS[perk].name))
	return "  ".join(parts)


## Who earned what, so a win reads as more than a banner.
func _debrief_text(won: bool) -> String:
	if not won:
		return "NOTHING EARNED - THE ATTEMPT DOES NOT COUNT"
	var lines: Array[String] = []
	for soldier: Dictionary in Game.roster:
		var id: int = int(soldier.id)
		# The roster keeps its dead permanently, so only the squad that
		# deployed is read out - earlier casualties are not re-reported.
		if not bool(soldier.alive) and not Game.mission_dead.has(id):
			continue
		var gained: int = int(Game.mission_xp.get(id, 0))
		# The role goes on every line: a list of five surnames tells you
		# nothing about who you actually lost.
		var who := "%s, %s" % [Game.soldier_label(soldier),
				Unit.kind_role_name(int(soldier.kind))]
		if not bool(soldier.alive):
			lines.append("%s - KILLED IN ACTION" % who)
		elif gained > 0:
			lines.append("%s  +%d xp" % [who, gained])
		else:
			lines.append(who)
	return "\n".join(lines)


# -------------------------------------------------------------- narrative --
# The three missions are one story: a border contact, the discovery of what
# the Choir is really carrying, and a raid to take it away again. The briefing
# sets the situation, the debrief pays it off and points at the next mission.


func _show_briefing() -> void:
	var body: String = level.get("briefing", "")
	if body.is_empty():
		# No briefing to dismiss, so nothing else will swap the level banner
		# for the turn banner - do it here.
		briefing_panel.visible = false
		show_banner("DESERT SCOUTS' TURN")
		return
	briefing_mission_label.text = "%s  -  MISSION %d OF %d" % [
			Game.operation().name, Game.mission_number(), Game.mission_count()]
	briefing_title_label.text = str(level.name)
	briefing_fiction_label.text = str(level.get("fiction", ""))
	briefing_body_label.text = body
	briefing_orders_label.text = "ORDERS:  %s" % level.get("orders", "")
	briefing_panel.visible = true


func _dismiss_briefing() -> void:
	briefing_panel.visible = false
	# The turn banner has been sitting behind the briefing this whole time.
	if state == State.PLAYER_TURN:
		show_banner("DESERT SCOUTS' TURN")
		player_turn_ready_msec = Time.get_ticks_msec()


## Leave the battlefield. Promotions earned here are spent back at camp, face
## to face with the soldier who earned them, so this screen only has to report
## and hand back.
func _on_restart() -> void:
	if last_result_won:
		# Asked before advancing: advance_mission() winds the operation pointer
		# back to zero when the campaign loops, so afterwards there is no way
		# left to tell a fresh campaign from the first operation of any other.
		var campaign_over := Game.is_last_level()
		# Advancing decides where the squad wakes up: another tent if the
		# operation has missions left, the garrison if it does not.
		Game.advance_mission()
		if campaign_over:
			Game.reset_roster()  # the campaign looped; the squad starts over
	else:
		# A lost mission is retried from the same camp it was launched from.
		Game.in_the_field = Game.mission_number() > 1
	# Leaving the battlefield is the campaign's real checkpoint: whichever
	# branch ran above has just moved the squad, the operation pointer, or both.
	Game.save()
	Game.go_to_camp()


func _go_to_level(index: int) -> void:
	Game.abort_mission()  # jumping away mid-mission banks nothing
	Game.select_level(index)
	Game.go_to_battle()


# Fixed offsets keep the shake deterministic and always settle back to zero.
const SHAKE_OFFSETS: Array[Vector2] = [
	Vector2(4, -2), Vector2(-4, 2), Vector2(3, 1), Vector2(-2, -1), Vector2.ZERO,
]


## Camera offset is composited from independent channels so a recoil kick and
## an impact shake can overlap (a burst fires two shots 0.13s apart) without
## fighting each other over the same property.
func _process(delta: float) -> void:
	camera.offset = _cam_lean + _cam_shake
	_sway_plants()
	_animate_structures()
	_boil_smoke(delta)
	_sustain_suppression(delta)


## Keep live smoke moving. The Board draws the flat footprint for clarity;
## these puffs go on the layer above the units so the cloud actually screens
## what is standing in it.
func _boil_smoke(delta: float) -> void:
	if smoke.is_empty():
		return
	_smoke_puff_accum += delta * 14.0
	while _smoke_puff_accum >= 1.0:
		_smoke_puff_accum -= 1.0
		var cells: Array = smoke.keys()
		var cell: Vector2i = cells[_vis_rng.randi_range(0, cells.size() - 1)]
		fx_air.smoke_drift(board.cell_to_global(cell) + Vector2(0, -18))


## Advance the huts' and outpost's breeze loops. Structures animate a strip
## sprite per footprint column ("sprites"); objective props still animate one
## ("sprite") - both kinds share this list.
func _animate_structures() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for entry: Dictionary in _animated_props:
		var frames: Array = entry.frames
		var idx: int = int((t + entry.phase) * STRUCTURE_FPS) % frames.size()
		if idx == entry.frame:
			continue
		entry.frame = idx
		if entry.has("sprites"):
			for spr: Sprite2D in entry.sprites:
				spr.texture = frames[idx]
		else:
			entry.sprite.texture = frames[idx]


## Cacti lean in the wind. The offset snaps to whole sprite texels (the props
## draw at 2x) so the pixel art never shimmers between subpixel positions.
func _sway_plants() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for entry: Dictionary in _swaying:
		var wave: float = sin(t * SWAY_SPEED + entry.phase)
		var step: float = SWAY_TEXELS * ROCK_SCALE.x * signf(wave) \
				* (1.0 if absf(wave) > 0.45 else 0.0)
		entry.sprite.position.x = entry.base_x + step


func _screen_shake(strength := 1.0) -> void:
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	var gain := strength / maxf(base_zoom.x, 0.01)
	_shake_tween = create_tween()
	for off in SHAKE_OFFSETS:
		_shake_tween.tween_property(self, "_cam_shake", off * gain, 0.03)


## A snap away from the shot direction that eases back - the camera reacts to
## where the round went instead of doing the same wiggle every time.
func _camera_kick(dir: Vector2) -> void:
	if _kick_tween != null and _kick_tween.is_valid():
		_kick_tween.kill()
	_cam_lean = -dir * 5.0 / maxf(base_zoom.x, 0.01)
	_kick_tween = create_tween()
	_kick_tween.tween_property(self, "_cam_lean", Vector2.ZERO, 0.16) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Brief global slow-motion on impact. The dip is measured in REAL seconds
## (ignore_time_scale), so its length does not depend on `scale`, and the
## restore is bound to the Engine singleton rather than this node so a scene
## reload mid-freeze can never strand the game in slow motion.
## Every caller must await this - that serialization is what keeps overlapping
## hit-stops from stacking.
func _hit_stop(scale: float, real_seconds: float) -> void:
	Engine.time_scale = scale
	var timer := get_tree().create_timer(real_seconds, true, false, true)
	timer.timeout.connect(Engine.set_time_scale.bind(1.0))
	await timer.timeout


func show_banner(text: String) -> void:
	turn_banner.text = text
	turn_banner.modulate.a = 0.0
	turn_banner.pivot_offset = turn_banner.size / 2.0
	turn_banner.scale = Vector2(1.25, 1.25)
	var tween := create_tween()
	tween.tween_property(turn_banner, "modulate:a", 1.0, 0.2)
	tween.parallel().tween_property(turn_banner, "scale", Vector2.ONE, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

