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
# Ground detritus: what the desert has left lying about. Pure dressing - it is
# scattered onto open sand by hash, blocks nothing, stops nothing, and is drawn
# on the Board's decal layer under every unit.
const DETRITUS_ROOT := "res://assets/sprites/Environment/Desert/desert_detritus/"
const DETRITUS_TEXTURES: Array[Texture2D] = [
	preload(DETRITUS_ROOT + "Desert_detritus.png"),
	preload(DETRITUS_ROOT + "Desert_detritus_1.png"),
	preload(DETRITUS_ROOT + "Desert_detritus_2.png"),
	preload(DETRITUS_ROOT + "Desert_detritus_3.png"),
	preload(DETRITUS_ROOT + "Desert_detritus_4.png"),
	preload(DETRITUS_ROOT + "Desert_detritus_5.png"),
	preload(DETRITUS_ROOT + "Desert_detritus_6.png"),
	preload(DETRITUS_ROOT + "Desert_detritus_7.png"),
]
# What the squad leaves to mark a landing zone. The panel lies flat and is a
# decal; the other two stand up and are props, so they are anchored on a base
# and get their own offsets.
const SIGNAL_ROOT := "res://assets/sprites/Environment/Desert/desert_signal_markers/"
const SIGNAL_PANEL := preload(SIGNAL_ROOT + "Signal_panel.png")
const SIGNAL_STAND_TEXTURES: Array[Texture2D] = [
	preload(SIGNAL_ROOT + "Signal_banner.png"),
	preload(SIGNAL_ROOT + "Signal_mast.png"),
]
const SIGNAL_STAND_OFFSETS: Array[Vector2] = [Vector2(0, -17), Vector2(0, -19)]
# The Thirst's own marks on ground they say is theirs: tally boards, staked
# claims, a cup hung at a well. Map char 't', walkable, decoration only - the
# same deal 'p' plants get, and for the same reason. What they buy is not
# cover, it is that the Charter finally appears on the ground it is about.
const CLAIM_ROOT := "res://assets/sprites/Environment/Desert/thirst_claim_markers/"
const CLAIM_TEXTURES: Array[Texture2D] = [
	preload(CLAIM_ROOT + "Thirst_tally_board.png"),
	preload(CLAIM_ROOT + "Thirst_stake_bundle.png"),
	preload(CLAIM_ROOT + "Thirst_cup_post.png"),
	preload(CLAIM_ROOT + "Thirst_well_marker.png"),
]
const CLAIM_OFFSETS: Array[Vector2] = [
	Vector2(0, -16), Vector2(0, -19), Vector2(0, -18), Vector2(0, -18),
]
# Cover somebody built on purpose, as opposed to junk they left behind.
const SANDBAG_TEXTURES: Array[Texture2D] = [
	preload("res://assets/sprites/Environment/Desert/desert_sandbags/Desert_Sandbags.png"),
	preload("res://assets/sprites/Environment/Desert/desert_sandbags/Desert_Sandbags_1.png"),
]
# The Thirst's own stacked ordnance. Deliberately kept off the maps that have
# demolition objectives on them: crates you must burn and crates you merely
# hide behind should never be on the same board.
const THIRST_CACHE_ROOT := "res://assets/sprites/Environment/Desert/Props/Desert_insurgent_weapons_cache/"
const THIRST_CACHE_TEXTURES: Array[Texture2D] = [
	preload(THIRST_CACHE_ROOT + "Desert_insurgent_weapons_cache/rotations/unknown.png"),
	preload(THIRST_CACHE_ROOT + "Desert_insurgent_weapons_cache_1/rotations/unknown.png"),
	preload(THIRST_CACHE_ROOT + "Desert_insurgent_weapons_cache_2/rotations/unknown.png"),
	preload(THIRST_CACHE_ROOT + "Desert_insurgent_weapons_cache_3/rotations/unknown.png"),
	preload(THIRST_CACHE_ROOT + "Desert_insurgent_weapons_cache_4/rotations/unknown.png"),
	preload(THIRST_CACHE_ROOT + "Desert_insurgent_weapons_cache_5/rotations/unknown.png"),
]
const STRUCTURE_ROOT := "res://assets/sprites/Environment/Desert/Structures"
const STRUCTURE_DIRS := {
	"hut_1": STRUCTURE_ROOT + "/desert_hut/Desert_hut",
	"hut_2": STRUCTURE_ROOT + "/desert_hut/Desert_hut_1",
	"tent": STRUCTURE_ROOT + "/desert_hut/Desert_hut_2",
	"fortress": STRUCTURE_ROOT + "/Desert_military_building",
	# Dead vehicles, on the same 2x2 footprint as a hut and blocking exactly
	# as hard. They earn their place twice: a big piece to fight around on
	# boards that had only rocks, and the only thing on any map that says the
	# desert had a war in it before this squad turned up.
	"hauler_wreck": STRUCTURE_ROOT + "/desert_vehicle_wreck/Desert_hauler_wreck",
	"tanker_wreck": STRUCTURE_ROOT + "/desert_vehicle_wreck/Desert_tanker_wreck",
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
const THIRST_CACHE_OFFSET := Vector2(0, -15)
const STRUCTURE_OFFSETS := {
	"hut_1": Vector2(0, -22), "hut_2": Vector2(0, -33),
	"tent": Vector2(0, -33), "fortress": Vector2(0, -55),
	"hauler_wreck": Vector2(0, -19), "tanker_wreck": Vector2(0, -23),
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

# Thrown ordnance - the squad's edge, and the one thing the Thirst has no
# answer to. Carried as a shared pool rather than per soldier, so the decision
# is "is this the moment" rather than "which pocket".
# How far ordnance goes is Rules.throw_range(kind) - it varies by soldier now
# that the grenadier launches hers rather than throwing it.
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
# How long a "still ready" warning stays armed. Long enough to read the count
# and press again on purpose, short enough that a warning from two decisions
# ago cannot silently authorise a later slip.
const END_TURN_CONFIRM_MS := 2500

var state := State.PLAYER_TURN
# The end-turn confirm window: pressing E with soldiers still ready arms this
# instead of ending the turn, and only a second press inside it goes through.
var _end_turn_confirm_until := 0
var selected: Unit = null
var hover_cell := Board.NO_CELL
var turn_number := 1
var enemy_turn_running := false
var player_turn_ready_msec := 0
var danger_on := false
var fire_mode := FireMode.SINGLE
var aim_mode := AimMode.NONE
# The take-back slot: the last player move, held for as long as it is still
# nobody's information - no reaction drawn, no prisoner freed, nothing done
# since. One slot, because only the last move is ever honestly reversible.
var _undo: Dictionary = {}
# Every unit this battle ever spawned, corpses included - the index behind
# living_units()/unit_at(), so occupancy checks stop walking (and allocating)
# the ~50-child entity list per call. Appended in _spawn_unit; the escapee
# _run_for_it frees is erased where it is freed, and every reader still
# guards with is_instance_valid - the harnesses free units directly (see
# tools/test_morale.gd's outnumbered scenario), and a stale entry must read
# as absent, never crash.
var _units: Array[Unit] = []
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
# What _rules_rng was started from: Game.battle_seed(), or whatever `-- --seed N`
# pinned instead. Kept because it goes on the results panel - a bug report that
# carries this number is a battle somebody can play back, rather than a story
# about some goblin who hit three times running.
var rules_seed := 0
# Spawn order among the Thirst, and the third input to their identities. Counted
# rather than derived from the cell so that two fighters on the same tile across
# two different missions are still two different people.
var _enemy_ordinal := 0
## The ones who ran from an earlier mission and are walking back onto this one,
## keyed by the turn they arrive on. Settled once, at _ready(), from a pure hash
## - so reloading a save mid-mission produces the same people on the same turn.
## Thirst dead per player turn, `turn_number -> count`. The formation's own
## memory of how fast it is dying, which Rules.shock_cost reads over a window.
## Kept as a per-turn tally rather than a running total because the whole point
## is that four in one exchange is a collapse and four across ten turns is a
## long afternoon.
# --- bounty state -------------------------------------------------------------
## The soldier the bounty was given to. Their PRESENCE and GUILE are what every
## roll on this mission reads, so a party that loses them loses the mission's
## whole second half - which is the risk the player accepts by choosing.
var bounty_hunter: Unit = null
## The people who live here, in spawn order.
var residents: Array[Unit] = []
## How many of them have refused so far. The settlement talks to itself: each
## refusal makes the next person warier (Bounty.question_chance).
var bounty_refusals := 0
## The posted man, once somebody has said where he is. Null until then.
var bounty_target: Unit = null
## What became of him: "" while it is still open, then killed / surrendered /
## informant. This is what ends the mission rather than a body count.
var bounty_outcome := ""

var _thirst_deaths: Dictionary = {}
var _returners_due: Dictionary = {}
## Everyone this mission actually put back on the board, for mark_returned().
var _returners_landed: Array = []
# THE ROLL: what became of every one of them, in the order it happened.
# [{identity, kind, fate, conduct}] - see Roll.gd and Rules.Conduct.
var roll: Array[Dictionary] = []
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
## Every piece of scenery in the entities layer, paired with the node whose Y
## position decides where it sorts. See _refresh_occlusion().
var _occluders: Array[Dictionary] = []
## Sum of the living units' screen positions last frame. Occlusion only has to
## be recomputed when somebody has actually moved, and on a turn-based board
## that is a few frames in ten seconds.
var _occlusion_watch := Vector2.ZERO
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
## The bounty conversation, on buttons as well as on Z. The informant button is
## the whole reason these exist: the third ending was implemented, tested, and
## reachable by NOTHING in play - Z offered only question/surrender, so the
## mission's stated three-way choice was a two-way choice with a test.
@onready var parley_button: Button = $UI/ParleyButton
@onready var informant_button: Button = $UI/InformantButton
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
@onready var roll_label: Label = $UI/GameOver/RollLabel
@onready var narrative_label: Label = $UI/GameOver/NarrativeLabel
@onready var briefing_panel: ColorRect = $UI/Briefing
@onready var briefing_mission_label: Label = $UI/Briefing/Center/Box/MissionLabel
@onready var briefing_title_label: Label = $UI/Briefing/Center/Box/TitleLabel
@onready var briefing_fiction_label: Label = $UI/Briefing/Center/Box/FictionLabel
@onready var briefing_body_label: Label = $UI/Briefing/Center/Box/BodyLabel
@onready var briefing_orders_label: Label = $UI/Briefing/Center/Box/OrdersLabel
@onready var briefing_begin_button: Button = $UI/Briefing/Center/Box/BeginButton
## The framed HUD. Built in code (scripts/Hud.gd) rather than in Battle.tscn,
## and handed the action buttons and the contact panel to reparent - so every
## handler, hotkey and enable rule above still drives the same nodes.
var hud: BattleHud = null


func _ready() -> void:
	# Cosmetics stay on the clock - nothing reads them back, and a puff of smoke
	# that lands in the same place twice is not a feature. The rules stream is
	# seeded from the campaign instead, inside _apply_cmdline_overrides(): the
	# seed depends on which mission this is, so it cannot be settled until
	# --level has had its say.
	_vis_rng.randomize()
	Engine.time_scale = 1.0  # a reload mid-hit-stop must never persist
	Levels.validate_all()  # push_error-based, so it reports in release too
	_apply_cmdline_overrides()
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
	# Strictly last of the scenery: it dresses whatever ground the props, the
	# structures and the caches did not claim, and it reads _prop_shadows to
	# find out which cells those were.
	_spawn_decals()
	board.set_prop_shadows(_prop_shadows)
	if Game.on_bounty():
		_spawn_bounty_party()
		_spawn_bounty_residents()
	else:
		_spawn_campaign_squad()
	_finish_setup()


## The hunting party: the soldier the player chose, and two riflemen lent to
## them. Deliberately NOT the deployment machinery - a bounty is not the squad
## going out, it is one person being sent, and the two who go with them are
## anonymous on purpose. They are drawn as generic Kestrel troops, which is what
## Scout/ exists for (see the enum comment in Unit.gd).
func _spawn_bounty_party() -> void:
	var spawns: Array = level.get("scout_spawns", [])
	if spawns.is_empty():
		push_error("[Sandline] a bounty board with nowhere to land")
		return
	var hunter: Dictionary = Game.soldier_by_id(int(Game.bounty.get("hunter_id", 0)))
	if hunter.is_empty():
		push_error("[Sandline] the bounty's hunter is not on the roster")
		return
	_spawn_unit(int(hunter.get("kind", Unit.Kind.SCOUT)), spawns[0], hunter)
	bounty_hunter = unit_at(spawns[0])
	for i in range(1, spawns.size()):
		# No roster record, so no name, no rank and no progression: these two are
		# not the player's people and are not at risk of being permanently lost.
		_spawn_unit(Unit.Kind.SCOUT, spawns[i])
	print("[Sandline] bounty party: %s and %d riflemen"
			% [Game.full_name(hunter), spawns.size() - 1])


## The people who live here. Goblins by sprite and by kind, and fighters by
## nothing at all: they never take a turn, they are not combatants, and killing
## one is scored as killing a civilian. Every one of them can be asked once.
func _spawn_bounty_residents() -> void:
	var spec: Dictionary = level.get("bounty", {})
	var ordinal := 0
	for cell: Vector2i in spec.get("residents", []):
		if not board.in_bounds(cell) or unit_at(cell) != null:
			continue
		_spawn_unit(Unit.Kind.GOBLIN, cell)
		var who := unit_at(cell)
		if who == null:
			continue
		who.resident = true
		who.identity = Roll.identity(Game.campaign_seed,
				Game.current_level + 900, ordinal, Unit.Kind.GOBLIN)
		who.set_facing_sector(Board.sector_from_to(cell, board.size / 2))
		residents.append(who)
		ordinal += 1
	print("[Sandline] %d living at %s" % [residents.size(),
			str(spec.get("offer", {}).get("place", "somewhere"))])


func _spawn_campaign_squad() -> void:
	# Rodar Akai deploys in the lead slot: same spawn key, stronger soldier.
	_spawn_squad(Unit.Kind.HERO, level.get("lead_spawns", []))
	_spawn_squad(Unit.Kind.MACHINEGUNNER, level.get("gunner_spawns", []))
	_spawn_rifle_slots(level.scout_spawns)
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
	for spawn: Vector2i in level.get("bystander_spawns", []):
		_spawn_bystander(spawn)


## Everything that is true of a mission whichever kind it is: the buttons, the
## ordnance pool, the HUD and the opening state. Split out when bounties landed,
## because the two spawn paths above are the ONLY part that differs and having
## the bounty path re-do all of this was how the first draft ended up with an
## action bar wired twice.
func _finish_setup() -> void:
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
	parley_button.pressed.connect(_on_parley_pressed)
	informant_button.pressed.connect(_try_parley.bind("informant"))
	# Grenadier: a gunner packing them puts one more frag in the squad's pool.
	# Once, not per holder - the blurb promises "one more", and the pool is
	# squad ordnance rather than anybody's webbing.
	for soldier in living_units(Unit.TEAM_SCOUT):
		if soldier.has_perk("grenadier"):
			frags_left += 1
			break
	_sync_throw_buttons()
	danger_button.toggled.connect(_on_danger_button_toggled)
	_build_hud()
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
	# After every spawner has run, so the scenery list is the whole board.
	_collect_occluders()
	_schedule_returners()
	show_banner("%s  -  %s" % [Game.operation().name, level.name])
	player_turn_ready_msec = Time.get_ticks_msec()
	print("[Sandline] level %d '%s', player turn 1 begins" % [
			Game.current_level + 1, level.name])
	_apply_cmdline_screenshot()


## The two switches that decide which battle this is:
## `godot --path . -- --level 2 --seed 12345`. Everything after the bare `--`
## is ours.
##
## --level boots straight into a mission, so a headless run can smoke-test one
## other than the first, which is otherwise only reachable by playing to it.
## --seed pins the rules stream, which is how a battle out of a bug report gets
## fought a second time: the results panel prints the number, this reads it back.
##
## The seed is settled AFTER the loop rather than inside it, because the seed
## the campaign would have chosen depends on which mission this is - so
## `--seed` has to be able to win no matter which order the two arrive in.
func _apply_cmdline_overrides() -> void:
	var args := OS.get_cmdline_user_args()
	var pinned := 0
	var was_pinned := false
	for i in args.size():
		if i + 1 >= args.size():
			continue
		match args[i]:
			"--level":
				Game.select_level(int(args[i + 1]) - 1)
			"--seed":
				pinned = int(args[i + 1])
				was_pinned = true
	rules_seed = pinned if was_pinned else Game.battle_seed()
	_rules_rng.seed = rules_seed
	print("[Sandline] rules seed %d%s" % [rules_seed, " (--seed)" if was_pinned else ""])


## Save one settled frame to disk and quit:
## `godot --path . -- --level 1 --screenshot out.png`. The art pipeline's way
## of seeing a board. Must run WINDOWED - headless swaps in a dummy rasterizer
## that renders nothing, so it refuses rather than writing a black frame.
## `--pose` selects the Nth surviving scout and rests the cursor on the nearest
## goblin before the shot is taken. Half the HUD only exists while something is
## selected or hovered - the contact card, the ability buttons, the highlight
## overlays - so without this a screenshot can only ever show the idle state,
## and the panels that took the most work are the ones that never appear in it.
func _apply_cmdline_pose() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] != "--pose" or i + 1 >= args.size():
			continue
		var squad := living_units(Unit.TEAM_SCOUT)
		if squad.is_empty():
			return
		var who: Unit = squad[clampi(int(args[i + 1]) - 1, 0, squad.size() - 1)]
		select(who)
		var best: Unit = null
		for goblin in living_units(Unit.TEAM_GOBLIN):
			if best == null or Board.manhattan(who.cell, goblin.cell) \
					< Board.manhattan(who.cell, best.cell):
				best = goblin
		if best != null:
			hover_cell = best.cell
			_update_unit_panel()
		return


func _apply_cmdline_screenshot() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--screenshot" and i + 1 < args.size():
			_apply_cmdline_pose()
			_capture_screenshot(args[i + 1])
			return


func _capture_screenshot(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		push_error("[Sandline] --screenshot needs a window; headless renders nothing")
		get_tree().quit(1)
		return
	# The shot exists to show the board, and the briefing would cover it.
	if briefing_panel.visible:
		_dismiss_briefing()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	print("[Sandline] screenshot -> %s (%s) zoom=%s" % [
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


## Stand the HUD up and hand it the widgets that were loose on the CanvasLayer.
##
## It goes in as the FIRST child of UI so it paints under the two full-screen
## overlays (the briefing and the results card), which are later siblings. Put
## it last and the action bar shows through the debrief.
func _build_hud() -> void:
	var ui := $UI
	hud = BattleHud.new()
	hud.battle = self
	ui.add_child(hud)
	ui.move_child(hud, 0)
	hud.adopt([ability_1_button, ability_2_button, parley_button,
			informant_button, face_button, reload_button,
			burst_button, auto_button, suppress_button, frag_button,
			smoke_button, demolish_button, overwatch_button, danger_button,
			end_turn_button], unit_panel, turn_banner)
	# The Objectives panel says all of this, in a list, with progress bars.
	objective_label.visible = false
	# The banner stops being a headline: which side is acting matters, but not
	# at 39px across the top of a board the player is trying to read. The HUD
	# owns where it sits, because it has to clear the order-of-battle strip.
	turn_banner.add_theme_font_size_override("font_size", 23)
	# Only the keys the bar does not already print on itself. Every button
	# carries its own hotkey in its label, so listing all twelve again down here
	# was a second copy of the same information and a worse one.
	# E ends the turn and TAB cycles soldiers - this line said the opposite
	# for a while, which is the kind of bug a hint should be ashamed of.
	hud.set_hint("E end turn      TAB next soldier      Q / T abilities      "
			+ ("Z ask / offer      " if Game.on_bounty() else "")
			+ "click a soldier's card to select them")
	_apply_informant_intel()


## What the turned are worth, every mission after they turn.
##
## An informant who is only a line in the notebook is a reward the player reads
## once. This is the other half of what the Accord bought: positions given away
## before the first shot, drawn through the danger overlay that already exists
## rather than through a screen of its own - so it reads as knowledge about the
## board rather than as a menu.
##
## Never on a bounty: the man is standing in front of you, and there is nothing
## to be told.
func _apply_informant_intel() -> void:
	if Game.on_bounty() or Game.informants.is_empty():
		return
	var enemies := living_soldiers(Unit.TEAM_GOBLIN)
	if enemies.is_empty():
		return
	var marks := mini(Game.informant_marks(), enemies.size())
	var told := {}
	# Deterministic, and by position rather than by draw: the same campaign
	# walking into the same mission is told the same things.
	for i in marks:
		var pick := Roll.pick(Game.campaign_seed, Game.current_level,
				"intel:%d" % i, enemies.size())
		told[enemies[pick].cell] = true
	board.intel_cells = told
	board.queue_redraw()
	var who: Array[String] = []
	for rec: Dictionary in Game.informants:
		who.append(str(rec.get("name", "")))
	print("[Sandline] informant intel: %d position(s) marked, from %s"
			% [told.size(), ", ".join(who)])


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


## Every cell somebody starts the mission standing on. Two callers want this:
## the spawn check below, and the scenery, which must not stake a banner on a
## cell that is about to have a soldier on it.
func _spawn_cells() -> Array:
	return level.scout_spawns + level.get("lead_spawns", []) \
			+ level.get("gunner_spawns", []) + level.goblin_spawns \
			+ level.get("smg_spawns", []) + level.get("smg_alt_spawns", []) \
			+ level.get("novice_spawns", []) + level.get("bolt_spawns", []) \
			+ level.get("prisoner_spawns", []) + level.get("bystander_spawns", [])


func _validate_spawns() -> void:
	for spawn: Vector2i in _spawn_cells():
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
const SALT_CLAIM := 11
const SALT_DETRITUS := 12
const SALT_DETRITUS_PICK := 13
const SALT_DETRITUS_JITTER := 14
const SALT_SIGNAL := 15


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
							THIRST_CACHE_TEXTURES[_prop_pick(cell, SALT_CACHE,
									THIRST_CACHE_TEXTURES.size())],
							THIRST_CACHE_OFFSET, cell)
				"t":
					var claim := _prop_pick(cell, SALT_CLAIM, CLAIM_TEXTURES.size())
					var stake := _spawn_prop(CLAIM_TEXTURES[claim],
							CLAIM_OFFSETS[claim], cell)
					# Rags and pennants catch the same wind the cacti do.
					_swaying.append({
						"sprite": stake,
						"base_x": stake.position.x,
						"phase": Board._hash01(cell, _prop_seed + SALT_SWAY) * TAU,
					})
				"W":
					var kind := _wall_kind(cell)
					_spawn_prop(_wall_texture_for(kind), WALL_OFFSETS[kind], cell)
				"=":
					var run := _wire_kind(cell)
					_spawn_prop(WIRE_TEXTURES[run], WIRE_OFFSETS[run], cell)


## How much of the open sand gets a piece of detritus on it, and how close two
## of them may sit. Tuned on the emptiest board in the game (THE LONG HAUL, one
## rock and nine scraps of cover): enough that no stretch of ground is blank,
## sparse enough that the eye still reads the cover as the thing worth looking
## at. The gap is Chebyshev, so nothing is ever placed in a neighbouring cell.
const DETRITUS_RATE := 0.17
const DETRITUS_GAP := 1
## Sub-cell drift, in decal texels, so a scatter is not a grid of centred
## stamps. Whole texels only - a decal draws at 1x, and a half-pixel offset
## would smear the one class of art that is pixel-exact with the floor.
const DETRITUS_JITTER := 11.0
## Standing signal markers set out beside an extraction zone. Three is enough
## to bracket a six-cell zone without crowding the ground the squad has to
## finish the mission standing on.
const SIGNAL_STANDS := 3
const SIGNAL_STAND_SHADOW := 12.0


## Flat scenery painted onto the ground: the extraction zone's signal panels,
## then detritus scattered over whatever open sand is left.
##
## Called after the props, the structures and the caches, so everything that
## occupies a cell has already claimed it and this only dresses what is spare.
## Nothing here has any rule attached - no cover, no blocking, no line of sight.
## It exists because seven maps share one desert and bare sand between the
## cover pieces is what made them read as the same desert.
func _spawn_decals() -> void:
	var extract := {}
	for obj: Dictionary in level.get("objectives", []):
		if str(obj.get("kind", "")) != "extract":
			continue
		for cell: Vector2i in obj.get("cells", []):
			extract[cell] = true
	# The zone was a green tint and nothing else. Panels are pegged flat, so
	# the squad can stand on the ground they mark without the mark vanishing
	# behind them - which a staked banner on the same cell would do.
	for cell: Vector2i in extract:
		_spawn_decal(SIGNAL_PANEL, cell, false)
	_spawn_signal_stands(extract)
	var placed: Array[Vector2i] = []
	for y in board.size.y:
		for x in board.size.x:
			var cell := Vector2i(x, y)
			if board.map_char(cell) != "." or board.is_structure(cell):
				continue
			# Never under a signal panel, a cache, a mast or a drum wreck:
			# those cells are being read for a reason.
			if extract.has(cell) or _prop_shadows.has(cell):
				continue
			if Board._hash01(cell, _prop_seed + SALT_DETRITUS) >= DETRITUS_RATE:
				continue
			var clear := true
			for other: Vector2i in placed:
				if maxi(absi(other.x - cell.x), absi(other.y - cell.y)) <= DETRITUS_GAP:
					clear = false
					break
			if not clear:
				continue
			placed.append(cell)
			_spawn_decal(DETRITUS_TEXTURES[_prop_pick(cell, SALT_DETRITUS_PICK,
					DETRITUS_TEXTURES.size())], cell, true)


## A decal sprite on the Board's ground layer.
##
## Drawn at 1x, alone among the scenery. Every standing prop is 48px art at 2x
## because it has to hold its own against a 120px soldier; a decal has to sit
## INTO a 128x60 tile, and at 2x a jawbone would span three quarters of that
## tile and read as something to take cover behind. 1x also puts it at exactly
## the floor sheet's texel density, which is the honest class for it: this is
## ground marking, not an object standing on the ground.
func _spawn_decal(texture: Texture2D, cell: Vector2i, jitter: bool) -> Sprite2D:
	var decal := Sprite2D.new()
	decal.texture = texture
	decal.material = _dust_material(cell)  # same haze band as the props above it
	decal.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	decal.position = board.cell_to_local(cell)
	if jitter:
		# Two independent hashes off one salt, so drift in x and y are not
		# the same number and the scatter never falls on a diagonal.
		var hx := Board._hash01(cell, _prop_seed + SALT_DETRITUS_JITTER)
		var hy := Board._hash01(cell + Vector2i(97, 61), _prop_seed + SALT_DETRITUS_JITTER)
		decal.position += Vector2(
				roundf((hx - 0.5) * 2.0 * DETRITUS_JITTER),
				roundf((hy - 0.5) * DETRITUS_JITTER))  # tiles are half as tall
		decal.flip_h = hx > 0.5
	board.decal_layer.add_child(decal)
	return decal


## Standing markers on the open ground beside an extraction zone, so the last
## objective is somewhere the eye finds before the rules do.
##
## They go BESIDE the zone rather than in it: these are 96px-tall staked
## banners, and the zone's own cells are where five soldiers have to end the
## mission standing. Cells already carrying anything are skipped, so a zone
## boxed in by rock simply gets fewer - the panels underfoot are the part that
## is guaranteed.
func _spawn_signal_stands(extract: Dictionary) -> void:
	if extract.is_empty():
		return
	var occupied := {}
	for spawn: Vector2i in _spawn_cells():
		occupied[spawn] = true
	var taken: Array[Vector2i] = []
	for cell: Vector2i in extract:
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if taken.size() >= SIGNAL_STANDS:
				return
			var side: Vector2i = cell + dir
			if extract.has(side) or not board.in_bounds(side):
				continue
			if board.map_char(side) != "." or board.is_structure(side):
				continue
			if _prop_shadows.has(side) or occupied.has(side):
				continue
			# Spread them along the zone instead of clustering on its first cell.
			var clear := true
			for other: Vector2i in taken:
				if maxi(absi(other.x - side.x), absi(other.y - side.y)) < 2:
					clear = false
					break
			if not clear:
				continue
			taken.append(side)
			var pick := _prop_pick(side, SALT_SIGNAL, SIGNAL_STAND_TEXTURES.size())
			var stand := _spawn_prop(SIGNAL_STAND_TEXTURES[pick],
					SIGNAL_STAND_OFFSETS[pick], side)
			_prop_shadows[side] = SIGNAL_STAND_SHADOW
			# Cloth on stakes, so it moves with the plants and the claim stakes.
			_swaying.append({
				"sprite": stand,
				"base_x": stand.position.x,
				"phase": Board._hash01(side, _prop_seed + SALT_SWAY) * TAU,
			})


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


## Recompute only when somebody has actually moved.
##
## The board is turn-based and the units are still for most of a session, but a
## move TWEENS, so this cannot be event-driven off the destination alone or the
## scenery would jump aside a beat after the soldier arrives. Watching the sum
## of their positions catches every frame of a slide for the cost of one vector
## add per unit, and a fade in progress keeps running until it lands.
var _occlusion_settling := false

func _watch_for_occlusion(delta: float) -> void:
	if _occluders.is_empty():
		return
	var now := Vector2.ZERO
	for unit in _units:
		if is_instance_valid(unit) and unit.is_alive():
			now += unit.global_position
	if not now.is_equal_approx(_occlusion_watch):
		_occlusion_watch = now
		_occlusion_settling = true
	if not _occlusion_settling:
		return
	_refresh_occlusion(delta)
	# Stop once every prop has arrived at the alpha it wants.
	_occlusion_settling = false
	for entry: Dictionary in _occluders:
		var a: float = (entry.sprite as Sprite2D).modulate.a
		if not is_equal_approx(a, 1.0) and not is_equal_approx(a, OCCLUDED_ALPHA):
			_occlusion_settling = true
			break


# ------------------------------------------------------------------ occlusion

## How much of an occluder is left when somebody is standing behind it. Not
## zero: the prop still has to read as cover, and a rock that vanishes when a
## soldier walks past it is a worse lie than one that hides him.
const OCCLUDED_ALPHA := 0.42
## Only the part of a body that has to stay recognisable. A soldier's boots
## going behind a barrel is depth and reads correctly; his head and shoulders
## going behind it is the bug. Measured down from the crown as a fraction of
## the sprite's height.
const RECOGNISE_BAND := 0.62
## And how much of that band has to be covered before the scenery is actually
## in the way. Without this, a prop whose mostly-transparent rectangle merely
## overlaps a neighbour's counts - which faded 18 of 40 props on THE SCRAPLINE
## and left the yard looking like a ghost of itself.
const OCCLUDED_FRACTION := 0.22
## How fast it gets out of the way, in alpha per second. Fast enough not to lag
## a move, slow enough that a soldier crossing a junk field does not strobe.
const OCCLUSION_FADE := 4.0


## Collect the scenery once, after everything has been placed.
##
## Structures are the awkward case and the reason this stores a pair. They are
## sliced into per-column strips, each strip a Sprite2D under its own Node2D
## root positioned on that column's FRONT cell - which is what makes a building
## y-sort per column instead of as one slab. So the node that decides the draw
## order is the root, and the node that has the pixels is the child.
func _collect_occluders() -> void:
	_occluders.clear()
	for child in entities_node.get_children():
		if child is Unit:
			continue
		if child is Sprite2D:
			_occluders.append({"sprite": child, "sorts_by": child})
			continue
		for grandchild in child.get_children():
			if grandchild is Sprite2D:
				_occluders.append({"sprite": grandchild, "sorts_by": child})


## The screen rectangle a sprite actually covers.
func _sprite_rect(spr: Sprite2D) -> Rect2:
	var size: Vector2 = spr.region_rect.size if spr.region_enabled 			else Vector2(spr.texture.get_size())
	size *= spr.scale
	var centre := spr.global_position + spr.offset * spr.scale
	return Rect2(centre - size * 0.5, size)


## Fade any scenery that is standing in front of somebody.
##
## The board is 3/4 top-down and the props are tall: a rock reaches 74px above
## its own cell and a sandbag line 90px, against a 60px tile step - so a prop
## covers two and a half cells of screen behind it, and a soldier who walks
## into that band disappears. Y-sorting is correct and does not help: the unit
## IS behind the prop, and the prop IS drawn over him. The art is the problem
## and the art cannot be shortened without making the desert flat.
##
## So the scenery gets out of the way. This is the same principle the prop dust
## shader already states - "units should stay the crispest things on screen so
## they read against the scenery" - applied to the one case the shader cannot
## reach.
##
## Enemies count too. There is no fog of war in this game; a goblin behind a
## drum is drawn, just invisibly, and losing track of him is the same bug.
func _refresh_occlusion(delta: float) -> void:
	var hiding := {}
	for unit in living_units(Unit.TEAM_SCOUT) + living_units(Unit.TEAM_GOBLIN):
		if unit.sprite == null or unit.sprite.texture == null:
			continue
		var body := _sprite_rect(unit.sprite)
		# Head and shoulders only - see RECOGNISE_BAND.
		body.size.y *= RECOGNISE_BAND
		var need := body.size.x * body.size.y * OCCLUDED_FRACTION
		for i in _occluders.size():
			if hiding.has(i):
				continue
			var entry: Dictionary = _occluders[i]
			var spr: Sprite2D = entry.sprite
			if spr.texture == null:
				continue
			# Sorts behind him, so it is drawn first and cannot be hiding him.
			if (entry.sorts_by as Node2D).global_position.y <= unit.global_position.y:
				continue
			var over := body.intersection(_sprite_rect(spr))
			if over.size.x * over.size.y >= need:
				hiding[i] = true
	for i in _occluders.size():
		var spr: Sprite2D = _occluders[i].sprite
		var want := OCCLUDED_ALPHA if hiding.has(i) else 1.0
		if is_equal_approx(spr.modulate.a, want):
			continue
		spr.modulate.a = move_toward(spr.modulate.a, want, OCCLUSION_FADE * delta)


func _spawn_prop(texture: Texture2D, offset: Vector2, cell: Vector2i,
		scale := 0.0, expected := 2.0) -> Sprite2D:
	# Every standing prop draws at the density class its art was authored for -
	# today that is 48px-class art doubled, everywhere. The guard compares each
	# call against ITS declared class rather than a hard-coded 2.0, so hi-res
	# 1x props can land per-prop without silencing the stray-scale alarm. Art
	# that cannot draw at its class gets downsampled, not scaled; the mast and
	# the structures stay 2x forever.
	if OS.is_debug_build() and scale > 0.0 and not is_equal_approx(scale, expected):
		push_error("[Sandline] prop at %s spawned at %sx - normalise the art to "
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


## `soldier` is the roster entry for a named Kestrel, or {} for the Thirst.
##
## The Thirst are not anonymous either, they are just not introduced: every
## fighter is given an identity here and it stays hidden until THE ROLL reads it
## out. See scripts/Roll.gd for why this cannot draw from the rules stream.
func _spawn_unit(kind: Unit.Kind, spawn_cell: Vector2i, soldier := {}) -> void:
	var unit: Unit = UNIT_SCENE.instantiate()
	entities_node.add_child(unit)
	_units.append(unit)
	unit.setup(kind, spawn_cell)
	if not soldier.is_empty():
		# Strictly after setup(), which assigns every stat from scratch.
		unit.apply_progression(soldier)
	elif unit.team == Unit.TEAM_GOBLIN:
		unit.identity = Roll.identity(Game.campaign_seed, Game.current_level,
				_enemy_ordinal, kind)
		# Kept on the body, not just used to mint the name. A name is not a key
		# - Roll draws 228 distinct ones over 280 spawns - so (level, ordinal)
		# is what the notebook needs if anybody is ever to be looked up again.
		unit.spawn_ordinal = _enemy_ordinal
		_enemy_ordinal += 1
	unit.position = board.cell_to_global(spawn_cell)
	unit.shadow_color = board.shadow_tone(Unit.SHADOW_COLOR.a)
	unit.corpse_shadow_color = board.shadow_tone(Unit.CORPSE_SHADOW_COLOR.a)
	unit.died.connect(_on_unit_died)
	unit.wounded.connect(_on_unit_wounded)



# ------------------------------------------------------- the ones who came back

## How long the squad gets before the first of them walks on. Late enough that
## the opening contact is the player's own problem, early enough that it is not
## a footnote to a fight already decided.
const RETURN_FIRST_TURN := 3
## And how far apart, when more than one is coming.
const RETURN_TURN_GAP := 2
## Nobody wants four of them at once. The pool is small in practice, but a long
## campaign should not turn the rim into a parade.
const RETURN_MAX := 2
## When a warband walks on. Later than the first stragglers: the squad should
## have committed to a plan and taken some losses before four fresh rifles
## arrive behind them, or it is just a bigger opening force.
const WARBAND_TURN := 4


## Settle who is coming, and when. Called once, from _ready().
##
## The whole schedule is decided up front rather than rolled per turn, for the
## same reason Roll mints identities from a hash: a mission that is reloaded
## must play out the same way. Game.returners_from() is already deterministic;
## this only has to not add a coin flip of its own.
func _schedule_returners() -> void:
	# A warband takes precedence over the trickle and replaces it. Four named
	# fighters walking on together IS the event; adding two more strangers
	# behind them turns it into a stream of reinforcements, which is a different
	# and much worse thing for a sixteen-by-ten board.
	var band: Dictionary = Game.warband_for(Game.current_level)
	if not band.is_empty():
		_schedule_warband(band)
		return
	var coming: Array = Game.adversaries_for(Game.current_level)
	if coming.is_empty():
		return
	coming = coming.slice(0, RETURN_MAX)
	for i in coming.size():
		var turn := RETURN_FIRST_TURN + i * RETURN_TURN_GAP
		var due: Array = _returners_due.get(turn, [])
		due.append(coming[i])
		_returners_due[turn] = due
	print("[Sandline] %d returning to level %d" % [coming.size(), Game.current_level + 1])


## The whole band lands on one turn, off one rim, as one arrival.
##
## Stamped onto each record rather than tracked beside them, because the entries
## are what _land_returners carries and what _spawn_returner reads - anything
## kept in a parallel structure would have to survive the same reordering the
## arrival-cell search does, and would not.
func _schedule_warband(band: Dictionary) -> void:
	var leader: Dictionary = band.get("leader", {})
	var members: Array = band.get("members", [])
	if leader.is_empty():
		return
	var band_id := int(leader.get("id", 0))
	# One rim for all four, so they come on as a formation rather than as four
	# people who happened to arrive at once. The leader's own recorded edge is
	# the one they use - he is the reason they are here.
	var edge := str(leader.get("edge", "north"))
	var due: Array = []
	var lead_entry: Dictionary = leader.duplicate()
	lead_entry["edge"] = edge
	lead_entry["warband"] = band_id
	lead_entry["warband_leader"] = true
	due.append(lead_entry)
	for rec: Dictionary in members:
		var entry: Dictionary = rec.duplicate()
		entry["edge"] = edge
		entry["warband"] = band_id
		entry["warband_leader"] = false
		due.append(entry)
	_returners_due[WARBAND_TURN] = due
	print("[Sandline] %s brings a warband of %d to level %d, turn %d" % [
			str(leader.get("name", "somebody")), due.size(),
			Game.current_level + 1, WARBAND_TURN])


## Nobody arrives at a contact that is already over.
##
## An earlier draft held the mission OPEN until every scheduled arrival had
## landed, so a squad that cleared the board on turn 2 would still meet the
## turn-3 reinforcement. That was wrong in a way worth writing down, because it
## looked reasonable. A win is otherwise always decided during the player's own
## turn; deferring one moved the commit into the middle of an AI activation, and
## run_enemy_turn does not stop when the mission is scored - it fires that
## goblin's shot anyway. A banked WIN could be flipped to "RODAR AKAI HAS
## FALLEN" by a round that landed after commit_mission() had cleared the
## rollback. On a destroy map it also left the squad standing in the open for
## four turns after the job was done, with every casualty in them permanent.
##
## So the contact ends when it ends. Somebody who does not get here stays in the
## notebook, unreturned, and a later mission can have him. Clearing the ground
## quickly is its own reward.


## True where this map is held by people who have been told how it ends.
func _fighters_hold() -> bool:
	return bool(level.get("fighters_hold", false))


## Where a man coming from `edge` steps back on.
##
## The rim he left by, and then the cell on it CLOSEST TO THE SQUAD that is
## still at least ARRIVAL_STANDOFF tiles off them. He steps out behind you.
##
## This took three attempts and the two failures are worth keeping, because both
## sounded right. Furthest from the squad drops him at the far end of the rim,
## which on every shipped map is the corner nearest the Thirst's own spawns - he
## arrives as one more body on the side you are already pointed at. Furthest
## from the other GOBLINS fixes that on turn one and breaks by turn three: the
## Thirst advances west toward the squad, so the cell furthest from them becomes
## the east corner they started in, and he lands 16 tiles behind their own line.
##
## What actually makes an arrival alarming is proximity, not distance. The rim
## nobody is watching is the one behind the squad, and a man who steps onto it
## is between them and the way home. The standoff is what stops that being a
## free shot rather than a surprise - it is one tile past the attack range of
## both kinds that can return, so he has to close first.
const ARRIVAL_STANDOFF := 4

func _arrival_cell(edge: String) -> Vector2i:
	var rim: Array[Vector2i] = []
	match edge:
		"north":
			for x in board.size.x:
				rim.append(Vector2i(x, 0))
		"south":
			for x in board.size.x:
				rim.append(Vector2i(x, board.size.y - 1))
		"west":
			for y in board.size.y:
				rim.append(Vector2i(0, y))
		_:
			for y in board.size.y:
				rim.append(Vector2i(board.size.x - 1, y))
	var scouts := living_soldiers(Unit.TEAM_SCOUT)
	var best := Board.NO_CELL
	var best_room := 9999
	var fallback := Board.NO_CELL
	var fallback_room := -1
	for cell: Vector2i in rim:
		if not board.is_walkable(cell) or unit_at(cell) != null:
			continue
		var room := 9999
		for scout in scouts:
			room = mini(room, Board.manhattan(cell, scout.cell))
		if room >= ARRIVAL_STANDOFF and room < best_room:
			best_room = room
			best = cell
		# Nowhere on this rim clears the standoff - every cell is in somebody's
		# lap. Take the roomiest rather than refusing to arrive at all.
		if room > fallback_room:
			fallback_room = room
			fallback = cell
	return best if best != Board.NO_CELL else fallback


## Put this turn's arrivals on the board.
func _land_returners() -> void:
	if state == State.GAME_OVER:
		return
	var due: Array = _returners_due.get(turn_number, [])
	if due.is_empty():
		return
	_returners_due.erase(turn_number)
	var names: Array[String] = []
	for entry: Dictionary in due:
		var edge := str(entry.get("edge", "north"))
		var cell := _arrival_cell(edge)
		if cell == Board.NO_CELL:
			# Every cell on that rim is a wall or already occupied. Rather than
			# drop him somewhere he did not come from, he stays out there - he
			# is still in the notebook, and still unreturned, so a later mission
			# can have him.
			print("[Sandline]   no way back on from the %s rim" % edge)
			continue
		_spawn_returner(entry, cell)
		# Stamped with where and when, not just who. He walks on his own
		# activation the moment he lands, so his cell a second later is wherever
		# the AI took him - this is the only record of the arrival itself.
		var landed := entry.duplicate()
		landed["arrived_on"] = turn_number
		landed["arrived_at"] = cell
		_returners_landed.append(landed)
		names.append(str(entry.get("name", "somebody")))
	if names.is_empty():
		return
	Sfx.play("turn_enemy", 0.0, 0.0)
	# Named, because the name is the entire point: the player let this man walk
	# off a map two missions ago and the game wrote it down. The console carries
	# the whole history, which is more than a banner can hold.
	for entry: Dictionary in due:
		print("[Sandline]   %s" % Game.adversary_line(entry))
	# A warband is announced by the man who gathered it, not by a list of four
	# names the player cannot read in the time the banner is up. The names are
	# all in the console and all on THE ROLL afterwards.
	var chief := ""
	for entry: Dictionary in due:
		if bool(entry.get("warband_leader", false)):
			chief = str(entry.get("name", ""))
			break
	if chief != "":
		show_banner("%s HAS BROUGHT A WARBAND" % chief.to_upper())
	else:
		show_banner("%s CAME BACK" % ", ".join(names).to_upper())
	await get_tree().create_timer(0.9).timeout


## One returning fighter, carrying the name he had when he ran.
func _spawn_returner(entry: Dictionary, cell: Vector2i) -> void:
	_spawn_unit(int(entry.get("kind", 3)), cell)
	var unit := unit_at(cell)
	if unit == null:
		return
	unit.identity = {
		"name": str(entry.get("name", "")),
		"age": int(entry.get("age", 0)),
		"settlement": str(entry.get("settlement", "")),
		"grievance": str(entry.get("grievance", "")),
	}
	unit.returned = true
	unit.adversary_id = int(entry.get("id", 0))
	unit.survivals = int(entry.get("survivals", 0))
	unit.warband = int(entry.get("warband", 0))
	unit.warband_leader = bool(entry.get("warband_leader", false))
	# Some of them came back to hold ground and some came back to hit the squad
	# once and go. Decided from the campaign seed and this man's id rather than
	# from _rules_rng: that stream advances exactly once per shot so a seed
	# replays a firefight, and a draw here would shift every roll in the mission.
	#
	# A warband does not raid. Four men who gathered on purpose came to fight,
	# and a leader who shoots once and leaves would take his people with him
	# before the player had met them.
	if unit.warband == 0 and Roll.chance(Game.campaign_seed, Game.current_level,
			"raid:%d" % unit.adversary_id, Rules.RAID_CHANCE):
		unit.raider = true
		unit.raid_shots_left = Rules.RAID_SHOTS
	var injuries := int(entry.get("injuries", 0))
	if injuries > 0:
		# Left for dead and patched up in a settlement with no doctor. Down a
		# point of health per wound and a long way down on nerve - the exact
		# opposite of the man who merely ran, and legible at a glance from the
		# health bar, which is the whole reason the two read differently.
		unit.max_hp = Rules.injured_hp(unit.max_hp, injuries)
		unit.hp = unit.max_hp
		unit.morale = Rules.injured_morale(unit.kind, injuries)
	else:
		# He chose to come back. Steadier than the levy he was.
		unit.morale = Rules.returner_morale(unit.kind)
	unit.morale_ceiling = unit.morale
	# Facing in off the rim he came from, so his first act reads as an entrance
	# rather than as a body that was always standing there.
	unit.set_facing_sector(Board.sector_from_to(cell, board.size / 2))


## Somebody who lives here. Same body as a prisoner and none of the protection:
## on their feet from the start rather than huddled, no objective pointing at
## them, and nothing in the game arranging for them to survive.
##
## release() is what puts a civilian on their feet, and it is the entire reason
## this reuses the prisoner plumbing instead of adding a kind - which would have
## meant appending to Unit.Kind and climbing the save version for a unit that
## never appears on a roster.
func _spawn_bystander(spawn_cell: Vector2i) -> void:
	_spawn_unit(Unit.Kind.CIVILIAN, spawn_cell)
	var unit := unit_at(spawn_cell)
	if unit == null:
		return
	unit.bystander = true
	unit.release()
	# They get a name too, and from the same four settlements: the water this
	# place is arguing about is theirs. Without one, killing a bystander would
	# cost the theater Strain but cost no district anything, and there would be
	# nobody for THE ROLL to name.
	#
	# The prisoners in the pens deliberately do NOT get one - they are
	# Confederacy survey staff, not Thirst, and Roll's tables are not theirs.
	unit.identity = Roll.identity(Game.campaign_seed, Game.current_level,
			_enemy_ordinal, unit.kind)
	_enemy_ordinal += 1


## The three rifle slots, filled with whoever the garrison chose.
##
## Distinct from _spawn_squad because it is a different question. That one asks
## "which soldiers hold this posting" and pairs a kind to its spawns; this one
## asks "who is going", and the answer is six people deep and three places wide.
## The kind comes off the soldier rather than being handed in, so a grenadier
## and a medic can stand in slots that used to be riflemen only.
func _spawn_rifle_slots(spawns: Array) -> void:
	var going := Game.deployment(spawns.size())
	for i in mini(spawns.size(), going.size()):
		var soldier: Dictionary = going[i]
		_spawn_unit(int(soldier.kind), spawns[i], soldier)
	if going.size() < spawns.size():
		print("[Sandline] %d of %d rifle slots filled - the rest were lost" % [
				going.size(), spawns.size()])
	else:
		var names: Array[String] = []
		for soldier: Dictionary in going:
			names.append(Game.full_name(soldier))
		print("[Sandline] deploying: %s" % ", ".join(names))


## Walk a level's spawn list for one scout role alongside the roster slots for
## that role, so the same soldier lands in the same job every mission.
func _spawn_squad(kind: Unit.Kind, spawns: Array) -> void:
	# Anybody just back from a bounty sits this one out - see Game.resting_ids.
	# The lead and gunner slots go through here, so a hero who spent last week
	# hunting somebody is genuinely absent, and the mission is fought without
	# him. deployable_of_kind falls back to recalling him if the campaign is too
	# thin to field the slot at all.
	var soldiers := Game.deployable_of_kind(kind, spawns.size())
	# Only as many bodies as there are soldiers left alive to fill them. A
	# spawn point with nobody to stand on it simply goes unused - deploying an
	# anonymous unit there would quietly undo permadeath.
	for i in mini(spawns.size(), soldiers.size()):
		_spawn_unit(kind, spawns[i], soldiers[i])
	if soldiers.size() < spawns.size():
		print("[Sandline] %s deploys %d of %d - the rest were lost" % [
				Unit.kind_role_name(kind), soldiers.size(), spawns.size()])


## Living units of a team that actually fight. The prisoner is on your side and
## walks out with the squad, but the Thirst never shoots at them and losing every
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
		print("[Sandline] %s reaches the prisoner at %s" % [
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
	for unit in _units:
		if is_instance_valid(unit) and unit.is_alive() and unit.team == team:
			result.append(unit)
	return result


func unit_at(cell: Vector2i) -> Unit:
	for unit in _units:
		if is_instance_valid(unit) and unit.is_alive() and unit.cell == cell:
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
	if event.is_action_pressed("parley"):
		# One key for the whole bounty conversation, because at any moment only
		# one of the three is available: somebody to ask, or somebody to make an
		# offer to. Which it is, the panel says.
		if _resident_in_reach() != null:
			_try_question()
			return
		if _target_in_reach() != null:
			_try_parley("surrender")
			return
	if event.is_action_pressed("demolish"):
		_try_demolish()
		return
	if event.is_action_pressed("hustle"):
		_try_hustle()
		return
	if event.is_action_pressed("undo_move"):
		_try_undo_move()
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


## The promise from a cell the soldier is not standing on yet. Answered by
## the same Rules.shot_preview every real shot resolves through - the unit is
## stood on the candidate cell for the length of one question and put back -
## so the projected number IS the number he gets standing there, inspiration
## aura and all. No second spelling of the rule exists to drift.
##
## Quoted at the mode he would actually hold after walking: bracing is gone,
## so a rifleman projects his single shot and the gunner his hip burst.
func _projected_shot(unit: Unit, from_cell: Vector2i, target: Unit) -> Dictionary:
	var real := unit.cell
	unit.cell = from_cell
	var mode := _default_fire_mode(unit)
	var shot := Rules.shot_preview(board, unit, target,
			_mode_accuracy(unit, mode), _inspiration_bonus(unit))
	unit.cell = real
	return shot


## Best answer the hovered destination offers: the highest-odds target the
## soldier could engage from there (with how many are in reach at all), or {}
## when the cell has no shot.
func _best_projected_shot(unit: Unit, from_cell: Vector2i) -> Dictionary:
	var best := {}
	var count := 0
	for goblin in living_soldiers(Unit.TEAM_GOBLIN):
		if Board.manhattan(from_cell, goblin.cell) > unit.attack_range \
				or not board.can_engage(from_cell, goblin.cell):
			continue
		count += 1
		var shot := _projected_shot(unit, from_cell, goblin)
		if best.is_empty() or int(shot.chance) > int(best.chance):
			shot["target"] = goblin
			best = shot
	if not best.is_empty():
		best["count"] = count
	return best


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


## Clicking a roster card. Routed through the same select() a board click uses,
## with the same two gates the board applies - it is the player's turn, and the
## soldier is one of theirs - so the card cannot reach a state a click could
## not. A dead soldier has no card at all.
func select_from_roster(unit: Unit) -> void:
	if state != State.PLAYER_TURN or unit == null or not unit.is_alive():
		return
	if unit.team != Unit.TEAM_SCOUT:
		return
	if unit == selected:
		return
	select(unit)


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
	# through here already, so the two buttons ride along - and the bounty
	# conversation's pair with them, since reach changes on the same events.
	_refresh_ability_buttons()
	_refresh_parley_buttons()
	if state == State.PLAYER_TURN:
		var ready := _soldiers_still_ready()
		end_turn_button.text = "End (E)" if ready == 0 				else "End (E) - %d ready" % ready
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
	# An unnamed fighter's "progress" line is just their role, and their name
	# line is their role too, so the card printed the same words twice. Harmless
	# at the old size; at the contact card's size it reads as a bug.
	panel_progress_label.visible = panel_progress_label.text != panel_name_label.text
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
	# Both throw lines quote their reach, the way the overwatch line above does
	# and for the same reason: the action's range is not the weapon's, and the
	# stat line two lines up is already showing the player "Rng 4" off the rifle.
	# Without this the grenadier's launcher is a rule with no readout - she
	# reaches further than the number on screen and nothing says so, so a player
	# who has learnt "grenades go four tiles" simply never sweeps the cursor out
	# to the fifth.
	if aim_mode == AimMode.THROW_FRAG and unit == selected:
		panel_status_label.text = "%s FRAG - %d TILES - %d CROSS / %d CORNERS" % [
				"LAUNCH" if Rules.has_launcher(unit.kind) else "THROW",
				Rules.throw_range(unit.kind),
				FRAG_DAMAGE, maxi(FRAG_DAMAGE - FRAG_FALLOFF, 1)]
		panel_status_label.modulate = Color("ff8a3c")
		return
	if aim_mode == AimMode.THROW_SMOKE and unit == selected:
		panel_status_label.text = "%s SMOKE - %d TILES" % [
				"LAUNCH" if Rules.has_launcher(unit.kind) else "THROW",
				Rules.throw_range(unit.kind)]
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
	# Hovering ground the soldier could walk to: answer the move before it is
	# made. The cover half of that answer is already on the board - the cover
	# overlay previews the hovered destination - and this line is the fire
	# half: the best shot the cell offers, from the function that will keep
	# the promise, plus whether a goblin's watch is on the ground itself.
	if unit == selected and selected != null and hover_cell != Board.NO_CELL \
			and board.move_dests.has(hover_cell) and _armed(selected):
		var projected := _best_projected_shot(selected, hover_cell)
		var line := ""
		if projected.is_empty():
			line = "FROM HERE: NO SHOT"
		else:
			var mark: Unit = projected.target
			line = "FROM HERE: %d%% ON %s - %d DMG" % [
					int(projected.chance), mark.role_name().to_upper(),
					int(projected.dmg)]
			if int(projected.count) > 1:
				line += " (+%d MORE)" % (int(projected.count) - 1)
		if _hostile_watch_covers(hover_cell):
			line += " - WATCHED GROUND"
		panel_status_label.text = line
		panel_status_label.modulate = Color("ffb84a") \
				if _hostile_watch_covers(hover_cell) else Color.WHITE
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
	if unit.needs_reload():
		panel_status_label.text = "OUT OF AMMO - RELOAD (R)" if unit.ammo == 0 				else "%d ROUND LEFT - TOO FEW TO FIRE - RELOAD (R)" % unit.ammo
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
	print("[Sandline] scout at %s reloads" % scout.cell)
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
		print("[Sandline] scout at %s turns to sector %d" % [unit.cell, sector])
		_refresh_watch_cells()
		_refresh_highlights()
		return
	deselect()
	unit.set_done(true)
	unit.set_overwatch(true)
	Sfx.play("overwatch_set", 0.0, 0.0)
	_refresh_watch_cells()
	print("[Sandline] scout at %s watches sector %d" % [unit.cell, sector])


## Cells an overwatching unit would cover: in range, in arc, with LOS.
func _overwatch_cells_for(unit: Unit, sector: int) -> Dictionary:
	# The geometry is Rules' now - one cone for the overlay, the AI and the
	# trigger check alike. See Rules.overwatch_cells.
	return Rules.overwatch_cells(board, unit, sector)


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


## Whether any goblin's held arc covers `cell` - the same sets the amber
## overlay paints, asked cell-at-a-time for the hover line.
func _hostile_watch_covers(cell: Vector2i) -> bool:
	for watcher in living_units(Unit.TEAM_GOBLIN):
		if watcher.overwatching and watcher.has_ammo() \
				and _overwatch_cells_for(watcher, watcher.facing_sector).has(cell):
			return true
	return false


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
	# min_rounds, not 1: the gunner's last belt round cannot be aimed at a man
	# (his lightest trigger is a burst), and painting the tile red used to
	# promise a shot that then failed without a sound.
	if not selected.acted and selected.has_ammo(selected.min_rounds()):
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
	# A new walk always replaces the take-back slot - whatever was pending is
	# no longer the last move. Snapshot what an undo would need to restore and
	# what it must verify went unchanged.
	_undo = {}
	var undo_from := unit.cell
	var undo_facing := unit.facing_sector
	var undo_watch := unit.overwatching
	var undo_acted := unit.acted
	var undo_captives := captives().size()
	var reaction_fired := false
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
			reaction_fired = true
			unit.stop_walking()
			for watcher in watchers:
				if not unit.is_alive():
					break
				watcher.set_overwatch(false)  # consumed, even if the shot kills
				print("[Sandline]   overwatch! %s fires %d at %s" % [
						watcher.cell, watcher.overwatch_rounds(), unit.cell])
				if Rules.reaction_interrupts(await _resolve_reaction(watcher, unit)):
					unit.interrupted = true
			if not unit.is_alive() or state == State.GAME_OVER:
				if selected == unit:
					deselect()
				if state != State.GAME_OVER:
					state = prev_state
					if prev_state == State.PLAYER_TURN:
						_refresh_danger()
						_update_unit_panel()
				return
			# A round that landed ends the advance here rather than at the
			# destination. Everything below still runs - the unit is standing
			# on a real cell, it may have reached a prisoner, and an extraction
			# map has to re-test the win condition either way.
			if unit.interrupted:
				print("[Sandline]   %s is stopped at %s" % [
						unit.role_name(), unit.cell])
				break
			unit.start_walking()
	unit.stop_walking()
	unit.moved = true
	# Hit crossing the lane: the activation is over, not just the walk. For a
	# soldier this greys him out; the AI checks the same flag before shooting.
	if unit.interrupted:
		unit.set_done(true)
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
		# The walk is reversible only while it changed nothing but the cell.
		if unit.team == Unit.TEAM_SCOUT and not reaction_fired \
				and not unit.interrupted and captives().size() == undo_captives:
			_undo = {"unit": unit, "from": undo_from, "dest": unit.cell,
					"facing": undo_facing, "watch": undo_watch,
					"acted": undo_acted, "ammo": unit.ammo, "hp": unit.hp,
					"turn": turn_number}
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
	print("[Sandline] suppressive fire %s -> %s" % [attacker.cell, target.cell])
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
	print("[Sandline]   pinned %s for %d turn(s)" % [pinned, pin_turns - 1])
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


## Credit a kill, if a named soldier earned it against the Thirst. Guards both
## directions: goblins earn nothing, and a frag that catches your own scout is
## not an achievement.
func _credit_kill(killer: Unit, victim: Unit) -> void:
	if killer == null or killer.soldier_id == 0:
		return
	if victim.team != Unit.TEAM_GOBLIN or killer.team != Unit.TEAM_SCOUT:
		return
	Game.award(killer.soldier_id, Game.XP_KILL)
	print("[Sandline]   %s credited a kill (+%d xp)" % [
			killer.display_name(), Game.XP_KILL])


## Squad ordnance is shared, so a grenade charge is too. (The Grenadier perk
## this once anticipated exists now - see the frags_left bump in _ready.)
func _award_xp(unit: Unit, amount: int, reason: String) -> void:
	if unit == null or unit.soldier_id == 0:
		return
	Game.award(unit.soldier_id, amount)
	print("[Sandline]   %s +%d xp (%s)" % [unit.display_name(), amount, reason])


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
	print("[Sandline] %s hustles - second move, no shot" % selected.display_name())
	_set_fire_mode(_default_fire_mode(selected))
	_refresh_highlights()
	_update_unit_panel()


## Take the last move back. Only while it is still nobody's information: the
## walk drew no reaction, freed no prisoner, and the soldier has done nothing
## since - anything else is a decision the battle has already answered, and it
## stands. Restores cell, facing and a Protective Fire watch the walk broke.
func _try_undo_move() -> void:
	if state != State.PLAYER_TURN:
		return
	if _undo.is_empty():
		show_banner("NOTHING TO TAKE BACK")
		return
	var unit: Unit = _undo.unit
	if not _can_undo_move(unit):
		show_banner("TOO LATE TO TAKE BACK")
		return
	unit.cell = _undo.from
	unit.position = board.cell_to_global(_undo.from)
	unit.moved = false
	unit.set_facing_sector(_undo.facing)
	if _undo.watch:
		unit.set_overwatch(true)
	print("[Sandline] %s takes the move back to %s" % [
			unit.display_name(), unit.cell])
	Sfx.play("select", -3.0, 0.0)
	show_banner("MOVE TAKEN BACK")
	_undo = {}
	if selected == unit:
		_set_fire_mode(_default_fire_mode(unit))
	_refresh_danger()
	_refresh_watch_cells()
	_refresh_objectives()
	_update_unit_panel()
	if selected == unit:
		_refresh_highlights()


## Whether the held slot still describes the board. Every field the move could
## legitimately have changed is verified unchanged, so a slot that survived a
## reload, a shot, a patch-up or a new turn can never restore stale state.
func _can_undo_move(unit: Unit) -> bool:
	return is_instance_valid(unit) and unit.is_alive() \
			and int(_undo.turn) == turn_number \
			and unit.moved and unit.cell == _undo.dest \
			and unit.acted == _undo.acted \
			and unit.ammo == int(_undo.ammo) and unit.hp == int(_undo.hp)


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


## The bounty conversation's buttons, refreshed on the same funnel the ability
## buttons ride (_update_unit_panel). Three states:
##   somebody unasked in reach  -> "Ask (Z)"
##   the posted man in reach    -> "Demand Surrender (Z)" + "Offer Deal"
##   neither                    -> hidden
## The reach helpers already answer false once the bounty is settled or before
## the man is found, so the buttons cannot outlive the conversation.
func _refresh_parley_buttons() -> void:
	if not Game.on_bounty() or state != State.PLAYER_TURN:
		parley_button.visible = false
		informant_button.visible = false
		return
	var resident := _resident_in_reach()
	var target := _target_in_reach()
	# The enemy-turn lock sets .disabled the way it does for every button; the
	# ability buttons un-stick themselves in their own refresh, so this pair
	# does the same rather than relying on the blanket re-enable block.
	parley_button.disabled = false
	informant_button.disabled = false
	informant_button.visible = target != null
	if target != null:
		parley_button.visible = true
		parley_button.text = "Demand Surrender (Z)"
	elif resident != null:
		parley_button.visible = true
		parley_button.text = "Ask (Z)"
	else:
		parley_button.visible = false


## The button mirrors Z exactly: ask if somebody is there to ask, else put the
## surrender demand to the man himself.
func _on_parley_pressed() -> void:
	if state != State.PLAYER_TURN:
		return
	if _resident_in_reach() != null:
		_try_question()
	elif _target_in_reach() != null:
		_try_parley("surrender")


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
	print("[Sandline] called shot %s -> %s" % [attacker.cell, target.cell])
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
	print("[Sandline] %s rallies %d soldier(s)" % [hero.display_name(), steadied])
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
	print("[Sandline] %s patches up to %d/%d HP" % [
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
			# Everyone still FIGHTING, rather than everyone still breathing.
			# A fighter with his hands up has stopped holding the ground the
			# squad was sent to clear, and the objective is the ground.
			# is_combatant() is false once he surrenders; a routing one is
			# gone from the tree the moment he steps off the rim.
			return living_soldiers(Unit.TEAM_GOBLIN).is_empty()
		"bounty":
			# One question, and it is not a body count: is the man settled? He
			# can be shot, taken, or turned, and all three finish the mission.
			return bounty_outcome != ""
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
				# Bystanders are nobody's to extract. They live here; the
				# squad is the one leaving.
				if scout.bystander:
					continue
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
		push_error("[Sandline] objective prop '%s' has no art at %s" % [kind, dir])
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
## One pass, two consumers. The HUD's checklist wants the same numbers the old
## one-line banner did, so this builds a structured entry per objective and the
## banner text falls out of the same loop - there is no second place that has to
## know how a cache count is worked out.
##
## Completed objectives are KEPT here and struck through, where the banner used
## to drop them. A list that silently loses its first line is worse than a list
## that ticks it: the player is owed the fact that they finished something.
func _update_objective_label() -> void:
	var parts: Array[String] = []
	var entries: Array = []
	for i in _objectives().size():
		var done := _objective_complete(i)
		var obj: Dictionary = _objectives()[i]
		var text: String = obj.get("label", "")
		var have := 0
		var need := 0
		match obj.get("kind", ""):
			"eliminate":
				if text.is_empty():
					text = "CLEAR THE CONTACT"
				var left := living_units(Unit.TEAM_GOBLIN).size()
				text += " %d LEFT" % left
			"destroy":
				need = obj.get("cells", []).size()
				have = need - _targets_left(i)
				text += " %d/%d" % [have, need]
			"rescue":
				need = level.get("prisoner_spawns", []).size()
				have = need - captives().size()
				text += " %d/%d" % [have, need]
			"extract":
				var zone: Array = obj.get("cells", [])
				need = living_units(Unit.TEAM_SCOUT).size()
				for scout in living_units(Unit.TEAM_SCOUT):
					if zone.has(scout.cell):
						have += 1
				text += " %d/%d ABOARD" % [have, need]
				# The zone is inert until the earlier jobs are done, so say so
				# rather than showing a target that cannot be met yet.
				if i != _active_objective() and not done:
					text = "THEN " + text
		entries.append({"label": text, "done": done, "have": have, "need": need})
		if not done:
			parts.append(text)
	objective_label.text = "     ".join(parts)
	if hud != null:
		hud.set_objectives(entries)


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
	print("[Sandline] scout at %s sets charges on the %s at %s (stage %d/%d)" % [
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
	print("[Sandline] %s shoots the drum at %s" % [shooter.display_name(), cell])
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
		print("[Sandline]   fuel drum at %s goes up" % cell)
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
## that is not solid. Junk counts - lobbing onto the scrap the Thirst is hiding
## behind is the whole point.
func _can_target_throw(thrower: Unit, cell: Vector2i) -> bool:
	return board.in_bounds(cell) and not board.is_blocker(cell) \
			and Board.manhattan(thrower.cell, cell) <= Rules.throw_range(thrower.kind) \
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
	print("[Sandline] frag %s -> %s (%d left)" % [thrower.cell, cell, frags_left])
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
		# Only the prisoners come through untouched - Unit.is_blast_immune()
		# owns that rule now. A man with his hands up does NOT: he can be shot
		# with a rifle, so a grenade going around him would be the inconsistency
		# rather than the mercy. Neither does a bystander, which is the whole
		# of what makes one.
		if blast.has(unit.cell) and not unit.is_blast_immune():
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
		print("[Sandline]   %s hits %s at %s for %d" % [
				what, unit.display_name(), unit.cell, dmg])
	print("[Sandline]   %s caught %d unit(s)" % [what, caught.size()])
	_resolving_blast = false
	check_game_over()


func do_throw_smoke(thrower: Unit, cell: Vector2i) -> void:
	var prev_state := state
	state = State.ANIMATING
	board.clear_highlights()
	smokes_left -= 1
	print("[Sandline] smoke %s -> %s (%d left)" % [thrower.cell, cell, smokes_left])
	await _deliver_throw(thrower, cell)
	var cloud := _blast_cells_at(cell)
	Sfx.play("smoke_pop")
	for smoke_cell: Vector2i in cloud:
		smoke[smoke_cell] = SMOKE_TURNS
		var pos := board.cell_to_global(smoke_cell)
		for i in 7:
			fx_air.smoke_drift(pos)
	_apply_smoke()
	print("[Sandline]   smoke covers %d cell(s)" % cloud.size())
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
## Returns whether any round in the volley connected. The whole burst is fired
## either way - a machinegunner's reaction is one burst, not three decisions -
## and the interrupt is settled once at the end of it.
func _resolve_reaction(watcher: Unit, target: Unit) -> bool:
	watcher.set_facing((target.position - watcher.position).normalized())
	var connected := false
	for i in watcher.overwatch_rounds():
		if i > 0:
			await get_tree().create_timer(BURST_GAP).timeout
		if await _fire_round(watcher, target):
			connected = true
		# Stop on a kill, a finished battle, or an empty belt rather than
		# firing rounds that have nowhere to go.
		if not target.is_alive() or state == State.GAME_OVER \
				or not watcher.has_ammo():
			break
	await get_tree().create_timer(LOWER_TIME).timeout
	watcher.lower_rifle()
	return connected


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
## Returns whether the round CONNECTED, which is what a reaction needs to know
## to decide whether it interrupted anybody (Rules.reaction_interrupts). Every
## other caller is free to ignore it.
func _fire_round(attacker: Unit, target: Unit, accuracy_mod := 0,
		ignore_cover := false, bonus_damage := 0) -> bool:
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
	var hit := Rules.roll_hits(_rules_rng, chance)
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
		print("[Sandline]   %s -> %s MISSES (%d%%)" % [
				attacker.cell, target.cell, chance])
		Sfx.play("miss")
		var strike := impact_point + Vector2(0, 30)
		fx_ground.footstep(strike, 1.2)  # dust where it lands
		fx_ground.bullet_hole(strike, dir)
		target.spawn_miss_text()
		_update_unit_panel()
		return false

	# Both numbers were settled above; all that is left is to say which happened.
	# `cover` is already NONE if this round was a called shot, so the log never
	# claims a wall the damage did not pay for.
	var dmg: int = shot.dmg
	var cover: Board.CoverLevel = shot.cover
	if cover != Board.CoverLevel.NONE:
		print("[Sandline]   shot %s -> %s into %s cover: %d dmg (%d%%)" % [
				attacker.cell, target.cell,
				"full" if cover == Board.CoverLevel.FULL else "half", dmg, chance])
	elif flanking:
		print("[Sandline]   flanking shot %s -> %s: %d dmg (%d%%)" % [
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
	return true


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
	print("[Sandline] %d-round volley %s -> %s" % [rounds, attacker.cell, target.cell])
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
	for watcher in _units:
		if not is_instance_valid(watcher) or not watcher.is_alive() \
				or not watcher.overwatching:
			continue
		if watcher.team == mover.team or not watcher.has_ammo():
			continue
		if Board.manhattan(watcher.cell, mover.cell) <= watcher.overwatch_range() \
				and watcher.covers_sector(Board.sector_from_to(watcher.cell, mover.cell)) \
				and board.has_line_of_sight(watcher.cell, mover.cell):
			result.append(watcher)
	return result


# --- Turn flow ---------------------------------------------------------------

## Soldiers who still have their action. A man who merely moved is still
## ready; one who shot, threw, set overwatch or was patched into acting is
## spent. Freed prisoners wear the squad's colours but never act, so they are
## not counted against the player's conscience here.
func _soldiers_still_ready() -> int:
	var n := 0
	for unit in living_units(Unit.TEAM_SCOUT):
		if unit.kind == Unit.Kind.CIVILIAN or unit.has_stopped():
			continue
		if not unit.acted:
			n += 1
	return n


## `force` exists for the harnesses and for nothing else: the turn loop tests
## drive whole turns without spending anybody, and the confirm window would
## turn every one of those calls into a no-op with a banner.
func end_player_turn(force := false) -> void:
	if state != State.PLAYER_TURN or enemy_turn_running:
		return
	if Time.get_ticks_msec() - player_turn_ready_msec < END_TURN_GRACE_MS:
		return
	# E is also the camp's interact key, and one slip used to hand the Thirst
	# a free round with up to five activations unspent. With soldiers still
	# ready the first press warns and arms a short window; only a deliberate
	# second press ends the turn.
	if not force:
		var ready := _soldiers_still_ready()
		var now := Time.get_ticks_msec()
		if ready > 0 and now > _end_turn_confirm_until:
			_end_turn_confirm_until = now + END_TURN_CONFIRM_MS
			Sfx.play("select", -4.0, 0.0)
			show_banner("%d STILL READY - END TURN AGAIN" % ready)
			_update_unit_panel()  # the button label carries the count
			return
	_end_turn_confirm_until = 0
	enemy_turn_running = true
	deselect()
	board.set_danger({})
	state = State.ENEMY_TURN
	print("[Sandline] enemy turn %d begins" % turn_number)
	Sfx.play("turn_enemy", 0.0, 0.0)
	show_banner("THE THIRST'S TURN")
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
	parley_button.disabled = true
	informant_button.disabled = true
	# The ones who ran, walking back on. Deliberately here and not a line
	# later: run_enemy_turn() snapshots its squad on its first statement, so a
	# body added after this point would stand still for a turn before noticing
	# there was a war on. Arriving now, it is refreshed by the loop below and
	# is in that snapshot, so it acts on the turn it lands.
	await _land_returners()
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
	print("[Sandline] player turn %d begins" % turn_number)
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
	show_banner("KESTREL SQUAD'S TURN")
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
		# Hands already up: he is finished for the battle, not for the turn.
		if goblin.surrendered:
			continue
		# The people who live here are not in this. They never move, never
		# shoot, and never break - the mission is that you have to talk to them.
		if goblin.resident:
			continue
		acted += 1
		var from_cell := goblin.cell
		# Mark the actor and give the player a beat to find it before it
		# moves. The beat is taken out of AI_BEAT, so turns stay the same
		# length - the player's eye just arrives before the motion.
		goblin.set_selected(true)
		goblin.set_acting(true)
		await get_tree().create_timer(ACT_LEAD_IN).timeout
		# Morale is settled before anything is decided, because whether this
		# fighter is still fighting is a prior question to what he does.
		if await _resolve_morale(goblin, acted, squad.size()):
			# The one branch that can end with no unit left to tidy up: a
			# fighter who reaches the rim is freed by _run_for_it, and the
			# frame it waits for to make that stick has already passed by the
			# time we are back here. Everything else - surrender, a rout that
			# is still running - leaves him on the board.
			if is_instance_valid(goblin):
				goblin.set_selected(false)
				goblin.set_acting(false)
			if state == State.GAME_OVER:
				return
			await get_tree().create_timer(AI_BEAT).timeout
			continue
		# An empty weapon is worked before anything else is decided, and costs
		# the move - the same rule the scouts reload under.
		var reloaded := await _ai_reload(goblin, acted, squad.size())
		var shootable := _shootable_from(goblin.cell, goblin.attack_range, scouts)
		if goblin.has_ammo() and not shootable.is_empty():
			print("[Sandline]   goblin %d/%d shoots from %s" % [acted, squad.size(), from_cell])
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
			# A reaction that landed ended this activation where it landed.
			# do_move has already set_done() him; this is the branch that would
			# otherwise walk straight past that and fire anyway.
			var shoots := goblin.is_alive() and not goblin.interrupted \
					and goblin.has_ammo() and not shootable.is_empty()
			print("[Sandline]   goblin %d/%d %s %s -> %s%s" % [
					acted, squad.size(), "reloads at" if reloaded else "moves",
					from_cell, goblin.cell,
					" and is stopped" if goblin.interrupted
							else (", shoots" if shoots else "")])
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
				print("[Sandline]   goblin %d/%d holds %s on overwatch" % [
						acted, squad.size(), goblin.cell])
		goblin.set_selected(false)
		goblin.set_acting(false)
		if state == State.GAME_OVER:
			return
		await get_tree().create_timer(AI_BEAT).timeout


## Settle whether this fighter is still fighting, before asking what he does.
## Returns true when the activation is over - he has put his hands up, he has
## run, or he is off the map - and the caller should move to the next one.
##
## The order is deliberate. Pressure is applied first, then the break is tested,
## then a unit already running keeps running. A fighter who breaks this turn
## does not also get to shoot on the way out.
func _resolve_morale(goblin: Unit, index: int, squad_size: int) -> bool:
	# A unit under a beaten zone erodes. One that had a genuinely quiet turn
	# steadies. One that was shot at does neither: it holds where the player
	# left it.
	#
	# That last case is the whole reason morale_pressed exists. Without it,
	# recovery lands between the round that broke a fighter and the check that
	# asks whether he is broken - so the squad could shoot a man to the edge of
	# breaking and watch him steady himself on his own turn, and MORALE_BREAK
	# would quietly mean MORALE_BREAK minus MORALE_RECOVER.
	if goblin.is_suppressed():
		goblin.morale = Rules.morale_after_suppression(goblin.morale)
	elif not goblin.morale_pressed and not goblin.routing:
		# Somebody whose leader is still standing steadies faster. It is the
		# only thing a warband does for its members while it is intact, and it
		# is enough to make killing the leader first the right answer.
		if goblin.warband != 0 and _warband_leader_alive(goblin.warband):
			goblin.morale = Rules.morale_recovered_led(
					goblin.morale, goblin.morale_ceiling)
		else:
			goblin.morale = Rules.morale_recovered(
					goblin.morale, goblin.morale_ceiling)
	goblin.morale_pressed = false

	if goblin.routing:
		return await _run_for_it(goblin, index, squad_size)

	# A raider leaves when he has done what he came for, and this is checked
	# BEFORE the morale terms below because it is not a morale decision at all -
	# he is not broken, he is finished. Flagged as a withdrawal so that firing on
	# him on the way out is scored as a combat kill rather than as shooting a man
	# whose nerve went.
	if goblin.raider and goblin.raid_shots_left <= 0:
		goblin.raid_withdrawal = true
		goblin.begin_rout()
		print("[Sandline]   goblin %d/%d has done what it came for and breaks contact at %s"
				% [index, squad_size, goblin.cell])
		return await _run_for_it(goblin, index, squad_size)

	# The two formation terms. Both are charged once per fighter per turn, both
	# apply wherever he is standing, and both are silent until their thresholds -
	# so an ordinary firefight never sees either of them.
	var still_up := living_units(Unit.TEAM_GOBLIN).size()
	var rifles := living_soldiers(Unit.TEAM_SCOUT).size()
	var recent := _recent_thirst_deaths()
	var before := goblin.morale
	goblin.morale = Rules.morale_after_shock(goblin.morale, recent)
	goblin.morale = Rules.morale_after_outnumbered(goblin.morale, still_up, rifles)
	if goblin.morale < before:
		print("[Sandline]   goblin %d/%d: %d dead lately, %d left against %d - morale %d -> %d"
				% [index, squad_size, recent, still_up, rifles, before, goblin.morale])

	var guns := _guns_on(goblin)
	if Rules.breaks_to_surrender(goblin.kind, goblin.morale, guns, _fighters_hold()):
		goblin.surrender()
		_record_on_roll(goblin, "surrendered")
		Sfx.play("overwatch_set", -6.0, 0.0)
		print("[Sandline]   goblin %d/%d surrenders at %s (morale %d, %d guns)" % [
				index, squad_size, goblin.cell, goblin.morale, guns])
		_refresh_objectives()
		check_game_over()
		return true
	if Rules.breaks_to_rout(goblin.kind, goblin.morale, guns, _fighters_hold()):
		goblin.begin_rout()
		print("[Sandline]   goblin %d/%d breaks at %s (morale %d, %d guns)" % [
				index, squad_size, goblin.cell, goblin.morale, guns])
		return await _run_for_it(goblin, index, squad_size)
	return false


## One turn of running. A fighter who starts his activation already on the rim
## is gone; otherwise he moves toward it and tries again next turn.
##
## Escaping is not a kill and is not a loss. The contact is resolved - he is no
## longer on the ground the squad was sent to clear - and THE ROLL says which of
## the two it was.
func _run_for_it(goblin: Unit, index: int, squad_size: int) -> bool:
	if _at_map_edge(goblin.cell):
		print("[Sandline]   goblin %d/%d escapes off %s" % [
				index, squad_size, goblin.cell])
		_record_on_roll(goblin, "escaped")
		goblin.hide()
		# Off the board rather than dead: removed from every query the turn
		# loop and the objectives make, without a corpse or a death sound.
		_units.erase(goblin)
		goblin.queue_free()
		await get_tree().process_frame
		_refresh_objectives()
		check_game_over()
		return true
	var dest := _rout_dest(goblin)
	if board.in_bounds(dest) and dest != goblin.cell and goblin.can_move():
		await do_move(goblin, dest)
		print("[Sandline]   goblin %d/%d runs %s -> %s" % [
				index, squad_size, goblin.cell, dest])
	return true


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
	print("[Sandline]   goblin %d/%d reloads at %s" % [index, squad_size, goblin.cell])
	await goblin.play_reload()
	goblin.reload()  # magazine seats as the animation lands
	return true


## AI units shoot with the heaviest setting their weapon allows, so a raider
## empties a burst instead of squeezing off one round like a rifleman.
func _ai_fire(attacker: Unit, target: Unit) -> void:
	# Counted here rather than at the two call sites, so no future branch that
	# finds a shot can forget to spend the raider's reason for being here.
	if attacker.raider and attacker.raid_shots_left > 0:
		attacker.raid_shots_left -= 1
	if _can_use_mode(attacker, FireMode.BURST):
		await do_volley(attacker, target, BURST_ROUNDS, BURST_GAP, 0)
	else:
		await do_attack(attacker, target)


func _shootable_from(from_cell: Vector2i, attack_range: int, targets: Array[Unit]) -> Array[Unit]:
	return AiPlan.shootable_from(board, from_cell, attack_range, targets)


func _nearest(from_cell: Vector2i, candidates: Array[Unit]) -> Unit:
	return AiPlan.nearest(from_cell, candidates)


## The judgement below is AiPlan's now (see scripts/AiPlan.gd), where
## tools/test_aiplan.gd pins it without standing up a scene. These forwarders
## assemble the two things the planner is not allowed to know - occupancy and
## which arcs are live - and keep every call site reading as before.

## Best move destination for an AI unit. Occupancy is the controller's
## knowledge, so the free destinations are gathered here; the watch sets use
## the same gate _overwatchers_against applies when a step actually triggers,
## so the route planner and the reaction can never disagree about what is
## covered.
func _best_ai_dest(goblin: Unit, reach: Dictionary, scouts: Array[Unit],
		chase_cell: Vector2i) -> Vector2i:
	# Reachable cells include squadmates' tiles, which can be crossed but
	# not occupied; standing still is always an option.
	var candidates: Array = _free_dests(reach).keys()
	candidates.append(goblin.cell)
	var watch_sets: Array[Dictionary] = []
	for watcher in living_units(_enemy_team_of(goblin)):
		if watcher.overwatching and watcher.has_ammo() and watcher.is_combatant():
			watch_sets.append(_overwatch_cells_for(watcher, watcher.facing_sector))
	return AiPlan.best_dest(board, goblin, reach, candidates, scouts,
			chase_cell, watch_sets)


## Which way a dug-in goblin should watch. The scouts' reach is gathered here
## - reachability depends on who is standing where - and AiPlan scores the
## eight arcs over it.
func _best_watch_sector(goblin: Unit, scouts: Array[Unit]) -> int:
	var approach := {}
	for scout in scouts:
		approach.merge(board.flood_fill(scout.cell, scout.move_range,
				_blocked_for_team.bind(scout.team)))
		approach[scout.cell] = true
	return AiPlan.best_watch_sector(board, goblin, approach)


# --- Win / lose --------------------------------------------------------------

func _on_unit_died(unit: Unit) -> void:
	if unit.soldier_id != 0:
		# Provisional: abort_mission() puts them back if the mission is lost
		# and retried, so only a won mission makes a death permanent.
		Game.mark_dead(unit.soldier_id)
		print("[Sandline] %s is down" % unit.display_name())
	else:
		_record_on_roll(unit, _fate_of(unit))
	# Shooting him is one of the three endings, and the only one that needs no
	# roll. Booked here rather than in the shooting code so that a frag, a drum
	# and a rifle round all finish the bounty the same way.
	if unit.bounty_target and bounty_outcome == "":
		_settle_bounty("killed")
	_spread_morale_from_death(unit)
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


## A round that did not kill. Only the Thirst has morale (see Unit.morale), and
## the arithmetic is Rules' - this reads the wound and hands it over.
func _on_unit_wounded(unit: Unit) -> void:
	if unit.team != Unit.TEAM_GOBLIN:
		return
	unit.morale = Rules.morale_after_round(unit.morale, unit.hp, unit.max_hp)
	unit.morale_pressed = true


## Watching somebody go down. Charged to every fighter close enough to have
## seen it, which is a radius rather than a line of sight on purpose: the sound
## of it carries further than the view does.
## Deaths inside Rules.SHOCK_WINDOW turns of now, counting this one.
func _recent_thirst_deaths() -> int:
	var n := 0
	for turn: int in _thirst_deaths:
		if turn > turn_number - Rules.SHOCK_WINDOW:
			n += int(_thirst_deaths[turn])
	return n


func _spread_morale_from_death(dead: Unit) -> void:
	if dead.team == Unit.TEAM_GOBLIN and not dead.is_civilian():
		_thirst_deaths[turn_number] = int(_thirst_deaths.get(turn_number, 0)) + 1
	# A warband is held together by the man who gathered it, and it comes apart
	# when he goes down - all at once, and wherever his people are standing.
	# Nothing else in the game targets a specific enemy for a morale reason, and
	# that is what makes a leader worth shooting first.
	if dead.warband_leader and dead.adversary_id != 0:
		for goblin in living_units(Unit.TEAM_GOBLIN):
			if goblin == dead or goblin.has_stopped():
				continue
			if goblin.warband != dead.adversary_id:
				continue
			goblin.morale = Rules.morale_after_leader_down(goblin.morale)
			goblin.morale_pressed = true
		print("[Sandline]   %s's warband loses its leader" % dead.display_name())
	for goblin in living_units(Unit.TEAM_GOBLIN):
		if goblin == dead or goblin.has_stopped():
			continue
		# A man who already walked away from one fight and came back to this
		# one does not need telling that people die here.
		if not Rules.shaken_by_the_fallen(goblin.returned):
			continue
		var before: int = goblin.morale
		goblin.morale = Rules.morale_after_ally_down(
				goblin.morale, Board.manhattan(goblin.cell, dead.cell))
		if goblin.morale < before:
			goblin.morale_pressed = true


# --- bounties: asking, finding, and what happens then --------------------------

## The soldier's two negotiation stats, or zeroes. Read through the roster
## rather than off the unit so that a stat awarded mid-mission is visible to the
## next roll without a second copy to keep in step.
func _hunter_stat(stat: String) -> int:
	if bounty_hunter == null or not bounty_hunter.is_alive():
		return 0
	var rec: Dictionary = Game.soldier_by_id(bounty_hunter.soldier_id)
	return maxi(int(rec.get(stat, 0)), 0)


## Somebody standing next to the selected soldier who can still be asked.
func _resident_in_reach() -> Unit:
	if not Game.on_bounty() or selected == null or bounty_target != null:
		return null
	for who in residents:
		if not is_instance_valid(who) or not who.is_alive() or who.questioned:
			continue
		if Board.manhattan(selected.cell, who.cell) <= 1:
			return who
	return null


## The posted man, if the selected soldier is close enough to talk to him. A
## parley is a conversation rather than a shout, so it wants adjacency the way
## questioning does.
func _target_in_reach() -> Unit:
	if bounty_target == null or selected == null or bounty_outcome != "":
		return null
	if not is_instance_valid(bounty_target) or not bounty_target.is_alive():
		return null
	if bounty_target.surrendered:
		return null
	if Board.manhattan(selected.cell, bounty_target.cell) <= 1:
		return bounty_target
	return null


## Ask somebody where he is.
##
## The roll is the hunter's GUILE against how wary the place has become, and it
## is drawn from _rules_rng - the same stream the shooting uses - so a bounty
## replays the same way a firefight does under the same seed.
func _try_question() -> void:
	var who := _resident_in_reach()
	if who == null or state != State.PLAYER_TURN:
		return
	who.questioned = true
	var guile := _hunter_stat("guile")
	var chance := Bounty.question_chance(guile, bounty_refusals)
	var rolled := _rules_rng.randi_range(1, 100)
	var talked := rolled <= chance
	print("[Sandline] question at %s: guile %d, %d refusals -> %d%% (rolled %d) %s"
			% [who.cell, guile, bounty_refusals, chance, rolled,
					"TALKS" if talked else "REFUSES"])
	if not talked:
		bounty_refusals += 1
		Sfx.play("miss", -4.0, 0.0)
		show_banner("THEY WILL NOT SAY")
		_update_unit_panel()
		# Everybody refusing is not a dead end: the man is still on the board,
		# and a party that cannot talk can still go and look.
		if _residents_left() == 0 and bounty_target == null:
			await get_tree().create_timer(0.6).timeout
			_reveal_bounty_target("nobody would say, so they went and looked")
		return
	Sfx.play("select", 0.0, 0.0)
	await _reveal_bounty_target("%s told them" % str(who.identity.get("name", "somebody")))


func _residents_left() -> int:
	var n := 0
	for who in residents:
		if is_instance_valid(who) and who.is_alive() and not who.questioned:
			n += 1
	return n


## He is where they said he would be - and if he has people, they are with him.
func _reveal_bounty_target(because: String) -> void:
	if bounty_target != null:
		return
	var spec: Dictionary = level.get("bounty", {})
	var offer: Dictionary = spec.get("offer", {})
	var hide: Vector2i = spec.get("hide", Board.NO_CELL)
	if not board.in_bounds(hide) or unit_at(hide) != null:
		hide = _arrival_cell("east")
	if not board.in_bounds(hide):
		push_error("[Sandline] nowhere to put the bounty target")
		return
	_spawn_unit(int(offer.get("kind", Unit.Kind.GOBLIN)), hide)
	bounty_target = unit_at(hide)
	if bounty_target == null:
		return
	bounty_target.bounty_target = true
	bounty_target.adversary_id = int(offer.get("target_id", 0))
	bounty_target.survivals = int(offer.get("survivals", 0))
	bounty_target.identity = {
		"name": str(offer.get("name", "")),
		"age": int(offer.get("age", 0)),
		"settlement": str(offer.get("settlement", "")),
		"grievance": str(offer.get("grievance", "")),
	}
	bounty_target.returned = true
	bounty_target.morale = Rules.returner_morale(bounty_target.kind)
	bounty_target.morale_ceiling = bounty_target.morale
	var injuries := int(offer.get("injuries", 0))
	if injuries > 0:
		bounty_target.max_hp = Rules.injured_hp(bounty_target.max_hp, injuries)
		bounty_target.hp = bounty_target.max_hp
	# The warband he gathered, if he has one. Same rule the campaign uses: a man
	# who has walked away twice can hold people, and they stand with him here.
	var band: Array = []
	if Rules.can_lead_warband(int(offer.get("survivals", 0))):
		band = Game.warband_members_for(int(offer.get("target_id", 0)))
	for rec: Dictionary in band:
		var cell := _free_cell_near(hide)
		if cell == Board.NO_CELL:
			break
		_spawn_unit(int(rec.get("kind", Unit.Kind.GOBLIN)), cell)
		var mate := unit_at(cell)
		if mate == null:
			continue
		mate.returned = true
		mate.adversary_id = int(rec.get("id", 0))
		mate.warband = int(offer.get("target_id", 0))
		mate.identity = {
			"name": str(rec.get("name", "")), "age": int(rec.get("age", 0)),
			"settlement": str(rec.get("settlement", "")),
			"grievance": str(rec.get("grievance", "")),
		}
		mate.morale = Rules.returner_morale(mate.kind)
		mate.morale_ceiling = mate.morale
	if not band.is_empty():
		bounty_target.warband = int(offer.get("target_id", 0))
		bounty_target.warband_leader = true
	print("[Sandline] %s found at %s (%s), %d with him"
			% [str(offer.get("name", "")), hide, because, band.size()])
	Sfx.play("turn_enemy", 0.0, 0.0)
	show_banner("%s IS HERE" % str(offer.get("name", "")).to_upper())
	_refresh_objectives()
	_update_unit_panel()
	await get_tree().create_timer(0.9).timeout


func _free_cell_near(cell: Vector2i) -> Vector2i:
	for step in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(-1, 0),
			Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
		var c: Vector2i = cell + step
		if board.in_bounds(c) and board.is_walkable(c) and unit_at(c) == null:
			return c
	return Board.NO_CELL


## The parley. Two offers, and the third option is the rifle already in the
## soldier's hands - so this only implements the two that need a roll.
##
## `want` is "surrender" or "informant". Both are one attempt: a player who
## could ask twice would always ask twice, and the choice between them is the
## whole decision the mission is built around.
func _try_parley(want: String) -> void:
	var target := _target_in_reach()
	if target == null or state != State.PLAYER_TURN or bounty_outcome != "":
		return
	var offer: Dictionary = level.get("bounty", {}).get("offer", {})
	var presence := _hunter_stat("presence")
	var guile := _hunter_stat("guile")
	var band_up := _warband_leader_alive(target.warband) and _band_still_standing(target)
	var wounded := target.hp * 2 <= target.max_hp
	var chance := 0
	if want == "surrender":
		chance = Bounty.surrender_chance(presence, target.survivals, band_up, wounded)
	else:
		chance = Bounty.informant_chance(guile, presence, target.survivals,
				band_up, not str(offer.get("grievance", "")).is_empty())
	var rolled := _rules_rng.randi_range(1, 100)
	var took_it := rolled <= chance
	print("[Sandline] parley (%s): presence %d guile %d vs %d escapes%s -> %d%% (rolled %d) %s"
			% [want, presence, guile, target.survivals,
					", warband up" if band_up else "", chance, rolled,
					"ACCEPTED" if took_it else "REFUSED"])
	if not took_it:
		# A refused offer is not a free action. He knows what you came for now,
		# and the only thing left is the rifle.
		Sfx.play("miss", -2.0, 0.0)
		show_banner("HE REFUSES")
		if selected != null:
			selected.set_done(true)
		_update_unit_panel()
		return
	target.surrender()
	bounty_outcome = "surrendered" if want == "surrender" else "informant"
	Sfx.play("overwatch_set", -4.0, 0.0)
	show_banner("HE COMES QUIETLY" if want == "surrender" else "HE WILL TALK")
	_settle_bounty(bounty_outcome)


## Whether anybody who came with him is still up. A leader whose people are all
## down is a man alone, and should hear the offer differently.
func _band_still_standing(target: Unit) -> bool:
	if target.warband == 0:
		return false
	for goblin in living_units(Unit.TEAM_GOBLIN):
		if goblin != target and goblin.warband == target.warband \
				and not goblin.has_stopped():
			return true
	return false


## The debrief a bounty earns, written from its ending. The campaign missions
## carry authored debriefs; a bounty's story is which of the three choices was
## made, and until this existed the results panel just went blank on it.
func _bounty_debrief() -> String:
	var offer: Dictionary = level.get("bounty", {}).get("offer", {})
	var name := str(offer.get("name", "the man"))
	var settlement := str(offer.get("settlement", "his settlement"))
	match bounty_outcome:
		"killed":
			return ("%s is dead. The Accord pays either way, and the paper "
					+ "does not ask how - but %s will hear which way it went, "
					+ "and bury him closer to the grievance than to the Crown.") \
					% [name, settlement]
		"surrendered":
			return ("%s put his weapon down and walked in ahead of the party."
					+ "\n\n%s will hear that it was offered, and that it was "
					+ "kept. That is worth more out here than the man is.") \
					% [name, settlement]
		"informant":
			return ("%s will talk.\n\nThe Crown has ears in %s now. Every "
					+ "mission after this one starts with something he knows, "
					+ "and he is nobody's martyr - which is the part the "
					+ "Assembly will find hardest to use.") % [name, settlement]
	return ""


## Book the result. Called from the parley and from the target's death, and it
## is the only place a bounty is scored - so the three endings cannot drift.
func _settle_bounty(outcome: String) -> void:
	if not Game.on_bounty() or outcome == "":
		return
	bounty_outcome = outcome
	var offer: Dictionary = level.get("bounty", {}).get("offer", {})
	var settlement := str(offer.get("settlement", ""))
	var standing := Bounty.standing_for(outcome)
	var strain := Bounty.strain_for(outcome)
	if standing != 0 and settlement != "":
		Game.set_standing(settlement,
				Game.standing_of(settlement) + standing)
	if strain != 0:
		Game.alliance_strain = clampi(Game.alliance_strain + strain, 0, 100)
	# What the soldier learned. Narrow on purpose - see Bounty's constants.
	var hunter_id := bounty_hunter.soldier_id if bounty_hunter != null else 0
	if outcome == "surrendered":
		Game.award_stat(hunter_id, "presence", Bounty.PRESENCE_FOR_SURRENDER)
	elif outcome == "informant":
		Game.award_stat(hunter_id, "guile", Bounty.GUILE_FOR_INFORMANT)
	if outcome != "killed" and _residents_unharmed():
		Game.award_stat(hunter_id, "guile", Bounty.GUILE_FOR_CLEAN_RUN)
	print("[Sandline] bounty settled: %s -> %s (standing %+d, strain %+d)"
			% [str(offer.get("name", "")), outcome, standing, strain])
	_refresh_objectives()
	check_game_over()


## Did everybody who lives here live through it?
func _residents_unharmed() -> bool:
	for who in residents:
		if not is_instance_valid(who) or not who.is_alive():
			return false
	return true


## Is the man who gathered this warband still on his feet? A leader who has
## surrendered or is routing counts as gone: his people can see him too.
func _warband_leader_alive(band: int) -> bool:
	if band == 0:
		return false
	for goblin in living_units(Unit.TEAM_GOBLIN):
		if goblin.warband_leader and goblin.adversary_id == band:
			return not goblin.has_stopped()
	return false


## How many living soldiers have a shot on this unit right now. The number that
## decides whether a broken fighter has somebody to surrender TO, so it asks the
## same engagement question the shooting does rather than a cheaper proxy.
func _guns_on(unit: Unit) -> int:
	var n := 0
	for scout in living_soldiers(Unit.TEAM_SCOUT):
		if Board.manhattan(scout.cell, unit.cell) <= scout.attack_range \
				and board.can_engage(scout.cell, unit.cell):
			n += 1
	return n


## True once a routing fighter is standing on the rim of the map. One step off
## it and he is gone - not killed, and the contact resolved either way.

## The ones this mission failed to account for, and how many times that has now
## happened to each of them.
##
## One line, and deliberately: the after-action's right column is measured by
## tools/check_briefing_fit.gd against a fixed budget, and mission 7's is the
## tightest. A name per survivor would blow it on exactly the mission where the
## most people are on the board.
##
## Read AFTER _remember_the_survivors has run, so the count includes today.
func _still_out_there() -> String:
	var names: Array[String] = []
	for entry: Dictionary in roll:
		var fate := str(entry.get("fate", ""))
		if fate != "escaped" and fate != "injured":
			continue
		var identity: Dictionary = entry.get("identity", {})
		var who := str(identity.get("name", ""))
		if who == "":
			continue
		# Their tally now, which is the point: the second time somebody walks
		# away from this squad should not read like the first.
		var times := 0
		for rec: Dictionary in Game.adversaries:
			if str(rec.get("name", "")) == who:
				times = int(rec.get("survivals", 0))
				break
		names.append(who if times < 2 else "%s (%d)" % [who, times])
	if names.is_empty():
		return ""
	return ", ".join(names)


## Everybody who walked away from this mission, written into the campaign's
## standing record of who is still out there.
##
## Runs on a won mission only, beside the notebook write, and for the same
## reason: a lost mission is rolled back wholesale, so nothing that happened in
## it happened. Somebody the squad already knew keeps his id and adds a line to
## his history; a stranger is minted one. Either way the next mission that meets
## him meets the same man.
func _remember_the_survivors() -> void:
	for entry: Dictionary in roll:
		var fate := str(entry.get("fate", ""))
		if fate != "escaped" and fate != "injured":
			continue
		Game.remember_survivor(entry.get("identity", {}),
				int(entry.get("kind", -1)), fate, Game.current_level,
				str(entry.get("edge", "")), int(entry.get("adversary_id", 0)))


## Killed, or only left for dead.
##
## Most of them are dead. The ones who are not are what turns a body count into
## a cast: he keeps his name, and the next time the squad meets him they are
## meeting somebody who has met them.
##
## Two gates, and the first is the player's. A blow that would have killed him
## from full health settles it - Rodar's rifle, Sillae's scope, a frag on
## anything but a well-hand - so if you want somebody gone for good you can
## spend the shot that does it. Chip damage is what lets people crawl away.
##
## The second is a hash, not a die, keyed on the campaign, the mission and which
## body he was. Reloading a mission must not turn a death into a survival, and
## drawing from _rules_rng here would shift every later shot in the mission by
## an amount depending on how many people had died first.
func _fate_of(unit: Unit) -> String:
	if unit.team != Unit.TEAM_GOBLIN or unit.is_civilian():
		return "killed"
	if Rules.decisive_blow(unit.last_blow, unit.max_hp):
		return "killed"
	var odds := Rules.survive_chance(unit.survivals)
	if Roll.chance(Game.campaign_seed, Game.current_level,
			"down:%d" % unit.spawn_ordinal, odds):
		return "injured"
	return "killed"


## Which way a man went. The rim he stood on if he reached one, otherwise the
## rim he was heading for - the sweep below records fighters who were still
## running when the objective completed, and they never arrived anywhere.
func _escape_edge(unit: Unit) -> String:
	var on := _edge_of(unit.cell)
	return on if on != "" else _nearest_edge(unit.cell)


## Anybody still running when the mission ended got away.
##
## Five of the seven missions finish on a destroy, extract or rescue objective,
## which can complete while a broken goblin is halfway to the rim. Until now the
## scene was torn down around him and he left no line on THE ROLL at all - not
## killed, not escaped, not anything. He was simply deleted, which is the one
## outcome that is not true: the squad did not account for him.
##
## So the roll is closed out over the survivors. A fighter who was routing when
## the shooting stopped is recorded as escaped, from whichever rim he had
## reached - or the one he was nearest, since he never got there.
func _sweep_the_still_running() -> void:
	for goblin in living_units(Unit.TEAM_GOBLIN):
		if not goblin.routing:
			continue
		print("[Sandline]   goblin was still running when it ended: %s"
				% str(goblin.identity.get("name", "?")))
		_record_on_roll(goblin, "escaped")


## The rim this cell is on or nearest to, for somebody who never reached one.
func _nearest_edge(cell: Vector2i) -> String:
	var far := {
		"north": cell.y,
		"south": board.size.y - 1 - cell.y,
		"west": cell.x,
		"east": board.size.x - 1 - cell.x,
	}
	var best := "north"
	for name: String in far:
		if int(far[name]) < int(far[best]):
			best = name
	return best

## Which rim a cell is on, as a word. "" for a cell that is not on one.
##
## Order matters where two edges meet: a corner is reported by its longer run,
## which on every 16x10 map in the game is north or south. That is also the
## answer the reinforcement code wants, since west is always the squad's rim and
## east is always the Thirst's - so a corner reads as the unexpected direction
## rather than the obvious one.
func _edge_of(cell: Vector2i) -> String:
	if cell.y == 0:
		return "north"
	if cell.y == board.size.y - 1:
		return "south"
	if cell.x == 0:
		return "west"
	if cell.x == board.size.x - 1:
		return "east"
	return ""


func _at_map_edge(cell: Vector2i) -> bool:
	return cell.x == 0 or cell.y == 0 \
			or cell.x == board.size.x - 1 or cell.y == board.size.y - 1


## Where a broken fighter runs. Of everything he can reach this turn, the cell
## closest to leaving - ties broken by distance from the nearest rifle, because
## a man running for the edge would still rather not run past somebody.
func _rout_dest(goblin: Unit) -> Vector2i:
	var reach: Dictionary = board.flood_fill(goblin.cell, goblin.move_range,
			_blocked_for_team.bind(goblin.team))
	var scouts := living_soldiers(Unit.TEAM_SCOUT)
	var best := goblin.cell
	var best_score := Vector2i(_edge_distance(goblin.cell),
			-_nearest_scout_distance(goblin.cell, scouts))
	for cell: Vector2i in reach:
		var score := Vector2i(_edge_distance(cell),
				-_nearest_scout_distance(cell, scouts))
		if score.x < best_score.x \
				or (score.x == best_score.x and score.y < best_score.y):
			best = cell
			best_score = score
	return best


func _edge_distance(cell: Vector2i) -> int:
	return mini(mini(cell.x, cell.y),
			mini(board.size.x - 1 - cell.x, board.size.y - 1 - cell.y))


func _nearest_scout_distance(cell: Vector2i, scouts: Array[Unit]) -> int:
	var best := 99
	for scout in scouts:
		best = mini(best, Board.manhattan(cell, scout.cell))
	return best


## Walk THE ROLL and charge the campaign for it.
##
## This is the layer that can name both Rules and Game: Game holds the counters
## as plain numbers and cannot reach for Rules without closing a compile cycle
## (see the v3 block in Game.gd), and Rules is static arithmetic that has never
## heard of a campaign. So the arithmetic is Rules', the storage is Game's, and
## the one place that puts them together is here.
##
## Standing is charged to the SETTLEMENT the person came from - a district
## notices what happened to its own - while Strain is theater-wide. A mission
## with nothing but clean kills on its roll charges neither, and walks Strain
## down toward the floor instead, because a war fought properly is still a war
## and the floor is where that fact lives.
func _apply_conduct() -> void:
	var charged := 0
	for entry: Dictionary in roll:
		var conduct: int = int(entry.get("conduct", Rules.Conduct.COMBATANT_KILLED))
		if Rules.standing_cost(conduct) == 0 and Rules.strain_cost(conduct) == 0:
			continue
		charged += 1
		var identity: Dictionary = entry.get("identity", {})
		var where := str(identity.get("settlement", ""))
		if not where.is_empty():
			Game.set_standing(where, Rules.standing_after(
					Game.standing_of(where), conduct))
		Game.alliance_strain = Rules.strain_after(Game.alliance_strain, conduct)
	if charged == 0:
		Game.alliance_strain = Rules.strain_decayed(Game.alliance_strain)
	print("[Sandline] conduct: %d of %d roll entries charged, strain now %d" % [
			charged, roll.size(), Game.alliance_strain])


## Add one line to THE ROLL, and price what it cost.
##
## The conduct is decided HERE, from the state the unit was in when it stopped,
## rather than at the trigger - because "he was already running" is a fact about
## the target and not about the shot, and the same round means different things
## depending on which. Rules owns the prices; this only reads the situation.
##
## A clean kill is on the roll exactly like the rest of them. It costs nothing,
## and it is still a name.
func _record_on_roll(unit: Unit, fate: String) -> void:
	if unit.team != Unit.TEAM_GOBLIN and not unit.is_civilian():
		return
	var conduct: int = Rules.Conduct.COMBATANT_KILLED
	if unit.is_civilian() or unit.resident:
		# Somebody who lives at a bounty location is a well-hand standing in
		# his own settlement. He is drawn as a goblin because he is one; he is
		# scored as what he is, which is a civilian.
		conduct = Rules.Conduct.CIVILIAN_KILLED
	elif fate == "killed":
		if unit.surrendered:
			conduct = Rules.Conduct.SURRENDERED_FIRED_ON
		elif unit.routing and not unit.raid_withdrawal:
			# A raider breaking contact after shooting at you is still a
			# combatant, and the price of mercy should not be charged for
			# refusing to let one go. Only a man whose nerve went is protected.
			conduct = Rules.Conduct.ROUTING_FIRED_ON
	roll.append({
		"identity": unit.identity,
		"kind": int(unit.kind),
		"fate": fate,
		"conduct": conduct,
		# The two facts that let a man who walked away be put back on a board:
		# which body he was, and which way he went. Both are worthless to the
		# after-action panel and both are why Game.notebook can now be read.
		"ordinal": int(unit.spawn_ordinal),
		"adversary_id": int(unit.adversary_id),
		"edge": _escape_edge(unit) if fate == "escaped" else "",
	})


## Only your own dead leave a rifle. The Thirst loses eleven bodies on a bad
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
		_show_game_over("THE SQUAD IS GONE", false)
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
		# Not "WIN": the victory line should not read as a scoreline. The
		# objective is met, the contact is over, and what that cost is the
		# after-action's business rather than this banner's.
		_show_game_over("CONTACT RESOLVED", true)
		return true
	return false


## The hero's corpse, if the battle fielded him and he is down; null while he
## lives or when the level never deployed him (a roster short of its hero
## simply fights without one - it must not read as an instant loss).
func _fallen_hero() -> Unit:
	for unit in _units:
		if is_instance_valid(unit) and unit.kind == Unit.Kind.HERO \
				and not unit.is_alive():
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
	print("[Sandline] level %d over on turn %d: %s" % [
			Game.current_level + 1, turn_number, "WON" if won else "LOST"])
	if won:
		# Walking off the map is worth something on its own - to the soldiers
		# who did the walking. The people they carried out are not on the roster.
		for scout in living_soldiers(Unit.TEAM_SCOUT):
			_award_xp(scout, Game.XP_SURVIVE, "survived")
		_sweep_the_still_running()
		_apply_conduct()
		_remember_the_survivors()
		Game.add_to_notebook(Game.current_level, roll)
		if Game.on_bounty():
			# A bounty is not a campaign mission and must not advance the
			# operation: the squad went out after one man and came home to the
			# same garrison. finish_bounty saves, so commit_mission - which is
			# what moves current_level on - is deliberately not called.
			var spec: Dictionary = level.get("bounty", {}).get("offer", {})
			Game.finish_bounty(bounty_outcome, bounty_hunter.soldier_id
					if bounty_hunter != null else 0,
					{"id": int(spec.get("target_id", 0)),
					"name": str(spec.get("name", "")),
					"settlement": str(spec.get("settlement", ""))})
		else:
			Game.commit_mission()
	else:
		# Nothing earned in a failed attempt sticks, so retrying cannot be
		# farmed for XP - and the fallen are un-killed along with it.
		Game.abort_mission()
	if won and Game.is_last_level():
		text = "CAMPAIGN COMPLETE - THE WASTES FALL SILENT"
	result_label.text = text
	# The story beat only lands on a win - a failed attempt is not part of it.
	# A bounty's debrief cannot be authored in Levels - which of the three
	# endings happened is the whole story - so it is composed here from what
	# was actually done. Read off Battle's own fields, not Game.on_bounty():
	# finish_bounty has already run in the won-branch above and cleared the
	# campaign-side state by the time this line executes.
	if won and level.has("bounty"):
		narrative_label.text = _bounty_debrief()
	else:
		narrative_label.text = str(level.get("debrief", "")) if won else ""
	debrief_label.text = _debrief_text(won)
	# Built after _apply_conduct() has run, so the Strain it reports is the one
	# this mission left behind rather than the one it started with.
	roll_label.text = _roll_text(won)
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
	# The number this battle's dice came out of, on the one screen a player is
	# looking at when a battle goes wrong. `-- --seed N` deals the same hand
	# again, so a report that quotes it is a report that can be reproduced.
	debrief_label.text += "\n\nSEED %d" % rules_seed
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


## THE OPERATION - the graded panel, and the only one that is graded.
##
## Objective, squad, tempo, and who earned what. Killing armed men is how this
## is earned: a hard-fought firefight with every soldier walking out is a
## perfect operation, and nothing on THE ROLL can take a point off it. The two
## are never summed and this one never mentions the other.
func _debrief_text(won: bool) -> String:
	if not won:
		return "NOTHING EARNED - THE ATTEMPT DOES NOT COUNT"
	# The heading and the grade share a line. This panel is bottom-aligned and
	# grows UPWARD into the debrief prose above it, so every line it gains is a
	# line closer to collision on the missions with the longest debriefs -
	# which is what tools/check_briefing_fit.gd now measures.
	var walked: int = living_soldiers(Unit.TEAM_SCOUT).size()
	var deployed: int = Game.mission_dead.size() + walked
	var lines: Array[String] = [
		"THE OPERATION  -  OBJECTIVE MET  -  %d OF %d OUT  -  %s" % [
				walked, deployed,
				"1 TURN" if turn_number == 1 else "%d TURNS" % turn_number],
		"",
	]
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


## THE ROLL - the reported panel, and it is never ranked.
##
## Who the squad met and what became of them. There is no grade here, no score,
## and nothing that subtracts from the operation next to it. It is a list of
## people, a count of what was done to them, and the two numbers the theater
## keeps - reported flatly, in the order a clerk would write them.
##
## Only three names are read out. The rest are in Dava's notebook, which is the
## document that remembers; this panel only has to say that they existed and
## that somebody wrote them down.
const ROLL_NAMES_SHOWN := 3

func _roll_text(won: bool) -> String:
	if not won or roll.is_empty():
		return ""
	var killed := 0
	var surrendered := 0
	var escaped := 0
	var injured := 0
	var civilians := 0
	for entry: Dictionary in roll:
		match str(entry.get("fate", "")):
			"surrendered": surrendered += 1
			"escaped": escaped += 1
			"injured": injured += 1
			_: killed += 1
		if int(entry.get("conduct", -1)) == Rules.Conduct.CIVILIAN_KILLED:
			civilians += 1

	var lines: Array[String] = ["THE ROLL", ""]
	var tally: Array[String] = []
	if killed > 0:
		tally.append("%d KILLED" % killed)
	if surrendered > 0:
		tally.append("%d SURRENDERED" % surrendered)
	if escaped > 0:
		tally.append("%d WALKED AWAY" % escaped)
	if injured > 0:
		# Not "killed", though the squad watched every one of them go down.
		# What the squad saw and what the campaign knows are different things,
		# and this line is the difference.
		tally.append("%d LEFT FOR DEAD" % injured)
	lines.append("  -  ".join(tally))
	lines.append("")

	var shown := 0
	for entry: Dictionary in roll:
		var identity: Dictionary = entry.get("identity", {})
		if identity.is_empty() or shown >= ROLL_NAMES_SHOWN:
			continue
		lines.append(Roll.line(identity, str(entry.get("fate", ""))))
		shown += 1
	var named := 0
	for entry: Dictionary in roll:
		if not (entry.get("identity", {}) as Dictionary).is_empty():
			named += 1
	if named > shown:
		lines.append("...and %d more in the notebook" % (named - shown))

	var out_there := _still_out_there()
	if out_there != "":
		lines.append("")
		lines.append("STILL OUT THERE  %s" % out_there)

	if civilians > 0:
		lines.append("")
		lines.append("CIVILIANS HARMED: %d" % civilians)
	lines.append("")
	lines.append("ALLIANCE STRAIN %d" % Game.alliance_strain)
	return "\n".join(lines)


# -------------------------------------------------------------- narrative --
# The three missions are one story: a border contact, the discovery of what
# the Thirst is really carrying, and a raid to take it away again. The briefing
# sets the situation, the debrief pays it off and points at the next mission.


func _show_briefing() -> void:
	var body: String = level.get("briefing", "")
	if body.is_empty():
		# No briefing to dismiss, so nothing else will swap the level banner
		# for the turn banner - do it here.
		briefing_panel.visible = false
		show_banner("KESTREL SQUAD'S TURN")
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
		show_banner("KESTREL SQUAD'S TURN")
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
	_watch_for_occlusion(delta)
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
