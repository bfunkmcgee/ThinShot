class_name Unit
extends Node2D

## One combatant on the grid. Stats are set by Battle.setup() per team.
## HP pips and the selection ring are drawn in _draw().

signal died(unit: Unit)

const TEAM_SCOUT := 0
const TEAM_GOBLIN := 1

## Which soldier this is. Team is allegiance; kind is the role, so the two
## scout types can differ in weapon, stats, and art.
enum Kind {
	SCOUT, TEAM_LEAD, MACHINEGUNNER,
	GOBLIN, GOBLIN_SMG, GOBLIN_SMG_ALT, GOBLIN_REVOLVER, GOBLIN_BOLT,
}

const LEAD_ROOT := "res://assets/sprites/Scout_TeamLead"
const MG_ROOT := "res://assets/sprites/Scout_MachineGunner/Scout_MachineGunner"
const SMG_ROOT := "res://assets/sprites/Goblin_SMG"
const REV_ROOT := "res://assets/sprites/Goblin_revolver"
const SMGA_ROOT := "res://assets/sprites/Goblin_SMG_alt"
const BOLT_ROOT := "res://assets/sprites/Goblin_BoltRifle"

# Directional pixel-art frames, indexed by 45-degree compass sector of the
# screen-space facing vector: 0=E, 1=SE, 2=S, 3=SW, 4=W, 5=NW, 6=N, 7=NE.
const SCOUT_FRAMES: Array[Texture2D] = [
	preload("res://assets/sprites/Scout/east.png"),
	preload("res://assets/sprites/Scout/south-east.png"),
	preload("res://assets/sprites/Scout/south.png"),
	preload("res://assets/sprites/Scout/south-west.png"),
	preload("res://assets/sprites/Scout/west.png"),
	preload("res://assets/sprites/Scout/north-west.png"),
	preload("res://assets/sprites/Scout/north.png"),
	preload("res://assets/sprites/Scout/north-east.png"),
]
const GOBLIN_FRAMES: Array[Texture2D] = [
	preload("res://assets/sprites/Goblin/east.png"),
	preload("res://assets/sprites/Goblin/south-east.png"),
	preload("res://assets/sprites/Goblin/south.png"),
	preload("res://assets/sprites/Goblin/south-west.png"),
	preload("res://assets/sprites/Goblin/west.png"),
	preload("res://assets/sprites/Goblin/north-west.png"),
	preload("res://assets/sprites/Goblin/north.png"),
	preload("res://assets/sprites/Goblin/north-east.png"),
]
const SCOUT_AIM_FRAMES: Array[Texture2D] = [
	preload("res://assets/sprites/Scout/Standing_Ready_to_fire_stance/rotations/east.png"),
	preload("res://assets/sprites/Scout/Standing_Ready_to_fire_stance/rotations/south-east.png"),
	preload("res://assets/sprites/Scout/Standing_Ready_to_fire_stance/rotations/south.png"),
	preload("res://assets/sprites/Scout/Standing_Ready_to_fire_stance/rotations/south-west.png"),
	preload("res://assets/sprites/Scout/Standing_Ready_to_fire_stance/rotations/west.png"),
	preload("res://assets/sprites/Scout/Standing_Ready_to_fire_stance/rotations/north-west.png"),
	preload("res://assets/sprites/Scout/Standing_Ready_to_fire_stance/rotations/north.png"),
	preload("res://assets/sprites/Scout/Standing_Ready_to_fire_stance/rotations/north-east.png"),
]
const GOBLIN_AIM_FRAMES: Array[Texture2D] = [
	preload("res://assets/sprites/Goblin/Standing_Ready_to_fire_stance/rotations/east.png"),
	preload("res://assets/sprites/Goblin/Standing_Ready_to_fire_stance/rotations/south-east.png"),
	preload("res://assets/sprites/Goblin/Standing_Ready_to_fire_stance/rotations/south.png"),
	preload("res://assets/sprites/Goblin/Standing_Ready_to_fire_stance/rotations/south-west.png"),
	preload("res://assets/sprites/Goblin/Standing_Ready_to_fire_stance/rotations/west.png"),
	preload("res://assets/sprites/Goblin/Standing_Ready_to_fire_stance/rotations/north-west.png"),
	preload("res://assets/sprites/Goblin/Standing_Ready_to_fire_stance/rotations/north.png"),
	preload("res://assets/sprites/Goblin/Standing_Ready_to_fire_stance/rotations/north-east.png"),
]

# Compass folder names in the same sector order as the frame arrays above.
const DIR_NAMES: Array[String] = [
	"east", "south-east", "south", "south-west",
	"west", "north-west", "north", "north-east",
]

# 9-frame animation cycles per direction, loaded once per class. Note the
# exact folder casing differs between the two walk sets.
static var SCOUT_WALK_FRAMES: Array = _load_dir_frames(
		"res://assets/sprites/Scout/animations/Standing_idle_walk")
static var GOBLIN_WALK_FRAMES: Array = _load_dir_frames(
		"res://assets/sprites/Goblin/animations/standing_idle_walk")
static var SCOUT_IDLE_FRAMES: Array = _load_dir_frames(
		"res://assets/sprites/Scout/animations/standing_idle")
static var GOBLIN_IDLE_FRAMES: Array = _load_dir_frames(
		"res://assets/sprites/Goblin/animations/standing_idle")
static var SCOUT_RAISE_FRAMES: Array = _load_dir_frames(
		"res://assets/sprites/Scout/animations/standing_idle_to_ready_to_fire")
static var GOBLIN_RAISE_FRAMES: Array = _load_dir_frames(
		"res://assets/sprites/Goblin/animations/standing_idle_to_Standing_Ready_to_fire")
static var SCOUT_AIM_IDLE_FRAMES: Array = _load_dir_frames(
		"res://assets/sprites/Scout/Standing_Ready_to_fire_stance/animations/standing_ready_to_fire_idle")
static var GOBLIN_AIM_IDLE_FRAMES: Array = _load_dir_frames(
		"res://assets/sprites/Goblin/Standing_Ready_to_fire_stance/animations/standing_ready_to_fire_idle")
static var SCOUT_DEATH_FRAMES: Array = _load_dir_frames(
		"res://assets/sprites/Scout/animations/standing_idle_to_dead")
static var GOBLIN_DEATH_FRAMES: Array = _load_dir_frames(
		"res://assets/sprites/Goblin/animations/standing_idle_to_dead")
static var SCOUT_IDLE_ALT_FRAMES: Array = _load_dir_frames(
		"res://assets/sprites/Scout/animations/standing_idle_alt")
static var GOBLIN_IDLE_ALT_FRAMES: Array = _load_dir_frames(
		"res://assets/sprites/Goblin/animations/standing_idle_alt")
static var SCOUT_HURT_FRAMES: Array = _load_dir_frames(
		"res://assets/sprites/Scout/animations/standing_idle_damage")
static var GOBLIN_HURT_FRAMES: Array = _load_dir_frames(
		"res://assets/sprites/Goblin/animations/standing_idle_damage")
static var SCOUT_RELOAD_FRAMES: Array = _load_dir_frames(
		"res://assets/sprites/Scout/animations/standing_idle_reload")
static var GOBLIN_RELOAD_FRAMES: Array = _load_dir_frames(
		"res://assets/sprites/Goblin/animations/standing_idle_reload")

# Team lead. Its stances live under differently named folders than the
# rank-and-file scout, so every set is spelled out here.
static var LEAD_FRAMES: Array[Texture2D] = _load_rotation_frames(
		LEAD_ROOT + "/standing_stance/rotations")
static var LEAD_AIM_FRAMES: Array[Texture2D] = _load_rotation_frames(
		LEAD_ROOT + "/Solider_aims_his_rif/rotations")
static var LEAD_DEAD_FRAMES: Array[Texture2D] = _load_rotation_frames(
		LEAD_ROOT + "/Solider_is_dead_with/rotations")
static var LEAD_IDLE_FRAMES: Array = _load_dir_frames(
		LEAD_ROOT + "/standing_stance/animations/standing_idle")
static var LEAD_WALK_FRAMES: Array = _load_dir_frames(
		LEAD_ROOT + "/standing_stance/animations/standing_idle_walk")
static var LEAD_RAISE_FRAMES: Array = _load_dir_frames(
		LEAD_ROOT + "/standing_stance/animations/standing_idle_to_ready_to_fire")
static var LEAD_AIM_IDLE_FRAMES: Array = _load_dir_frames(
		LEAD_ROOT + "/Solider_aims_his_rif/animations/standing_ready_to_fire_idle")
static var LEAD_DEATH_FRAMES: Array = _load_dir_frames(
		LEAD_ROOT + "/standing_stance/animations/standing_idle_to_dead")
static var LEAD_HURT_FRAMES: Array = _load_dir_frames(
		LEAD_ROOT + "/standing_stance/animations/standing_idle_damage")
static var LEAD_RELOAD_FRAMES: Array = _load_dir_frames(
		LEAD_ROOT + "/standing_stance/animations/standing_idle_reload")
# No alternate idle for the lead yet; resolves to 8 empty sets, which the
# idle roll already treats as "no variation available".
static var LEAD_IDLE_ALT_FRAMES: Array = _load_dir_frames(
		LEAD_ROOT + "/standing_stance/animations/standing_idle_alt")

# Machinegunner.
static var MG_FRAMES: Array[Texture2D] = _load_rotation_frames(MG_ROOT + "/rotations")
static var MG_AIM_FRAMES: Array[Texture2D] = _load_rotation_frames(
		MG_ROOT + "/ReadyToFire_Stance/rotations")
static var MG_DEAD_FRAMES: Array[Texture2D] = _load_rotation_frames(
		MG_ROOT + "/Dead_Stance/rotations")
static var MG_IDLE_FRAMES: Array = _load_dir_frames(
		MG_ROOT + "/animations/standing_idle")
static var MG_IDLE_ALT_FRAMES: Array = _load_dir_frames(
		MG_ROOT + "/animations/standing_idle_alt")
static var MG_WALK_FRAMES: Array = _load_dir_frames(
		MG_ROOT + "/animations/standing_idle_walk")
static var MG_RAISE_FRAMES: Array = _load_dir_frames(
		MG_ROOT + "/animations/standing_idle_to_readyToFire")
static var MG_AIM_IDLE_FRAMES: Array = _load_dir_frames(
		MG_ROOT + "/ReadyToFire_Stance/animations/Standing_ReadyToFire_idle")
static var MG_DEATH_FRAMES: Array = _load_dir_frames(
		MG_ROOT + "/animations/standing_idle_to_dead")
static var MG_HURT_FRAMES: Array = _load_dir_frames(
		MG_ROOT + "/animations/standing_idle_damage")
static var MG_RELOAD_FRAMES: Array = _load_dir_frames(
		MG_ROOT + "/animations/standing_idle_reload")

# Choir raider with a submachine gun. Note the aim-idle folder uses a
# hyphen where every other set uses an underscore.
static var SMG_FRAMES: Array[Texture2D] = _load_rotation_frames(
		SMG_ROOT + "/Goblin_SMG/rotations")
static var SMG_AIM_FRAMES: Array[Texture2D] = _load_rotation_frames(
		SMG_ROOT + "/Goblin_aims_submachi/rotations")
static var SMG_DEAD_FRAMES: Array[Texture2D] = _load_rotation_frames(
		SMG_ROOT + "/dead_with_blood/rotations")
static var SMG_IDLE_FRAMES: Array = _load_dir_frames(
		SMG_ROOT + "/Goblin_SMG/animations/standing_idle")
static var SMG_IDLE_ALT_FRAMES: Array = _load_dir_frames(
		SMG_ROOT + "/Goblin_SMG/animations/standing_idle_alt")
static var SMG_WALK_FRAMES: Array = _load_dir_frames(
		SMG_ROOT + "/Goblin_SMG/animations/standing_idle_walk")
static var SMG_RAISE_FRAMES: Array = _load_dir_frames(
		SMG_ROOT + "/Goblin_SMG/animations/standing_idle_to_readyToFire")
static var SMG_AIM_IDLE_FRAMES: Array = _load_dir_frames(
		SMG_ROOT + "/Goblin_aims_submachi/animations/standing-readyToFire_idle")
static var SMG_DEATH_FRAMES: Array = _load_dir_frames(
		SMG_ROOT + "/Goblin_SMG/animations/standing_idle_to_dead")
static var SMG_HURT_FRAMES: Array = _load_dir_frames(
		SMG_ROOT + "/Goblin_SMG/animations/standing_idle_damage")
static var SMG_RELOAD_FRAMES: Array = _load_dir_frames(
		SMG_ROOT + "/Goblin_SMG/animations/standing_idle_reload")

# The bottom of the Choir's roster: a shirtless novice with a revolver.
static var REV_FRAMES: Array[Texture2D] = _load_rotation_frames(
		REV_ROOT + "/goblin_revolver/rotations")
static var REV_AIM_FRAMES: Array[Texture2D] = _load_rotation_frames(
		REV_ROOT + "/standing_readyToFire_stance/rotations")
static var REV_DEAD_FRAMES: Array[Texture2D] = _load_rotation_frames(
		REV_ROOT + "/dead_stance/rotations")
static var REV_IDLE_FRAMES: Array = _load_dir_frames(
		REV_ROOT + "/goblin_revolver/animations/standing_idle")
static var REV_IDLE_ALT_FRAMES: Array = _load_dir_frames(
		REV_ROOT + "/goblin_revolver/animations/standing_idle_alt")
static var REV_WALK_FRAMES: Array = _load_dir_frames(
		REV_ROOT + "/goblin_revolver/animations/standing_idle_walk")
static var REV_RAISE_FRAMES: Array = _load_dir_frames(
		REV_ROOT + "/goblin_revolver/animations/standing_idle_to_readyToFire")
static var REV_AIM_IDLE_FRAMES: Array = _load_dir_frames(
		REV_ROOT + "/standing_readyToFire_stance/animations/standing-readyToFire_idle")
static var REV_DEATH_FRAMES: Array = _load_dir_frames(
		REV_ROOT + "/goblin_revolver/animations/standing_idle_to_dead")
static var REV_HURT_FRAMES: Array = _load_dir_frames(
		REV_ROOT + "/goblin_revolver/animations/standing_idle_damage")
static var REV_RELOAD_FRAMES: Array = _load_dir_frames(
		REV_ROOT + "/goblin_revolver/animations/standing_idle_reload")

# Alt raider. Same sheet layout as the raider above, except the aim-idle folder
# is named after its generation prompt, so it is scanned rather than baked in.
static var SMGA_FRAMES: Array[Texture2D] = _load_rotation_frames(
		SMGA_ROOT + "/Goblin_SMG_alt/rotations")
static var SMGA_AIM_FRAMES: Array[Texture2D] = _load_rotation_frames(
		SMGA_ROOT + "/ready_to_fire_stance/rotations")
static var SMGA_DEAD_FRAMES: Array[Texture2D] = _load_rotation_frames(
		SMGA_ROOT + "/dead_stance/rotations")
static var SMGA_IDLE_FRAMES: Array = _load_dir_frames(
		SMGA_ROOT + "/Goblin_SMG_alt/animations/standing_idle")
static var SMGA_IDLE_ALT_FRAMES: Array = _load_dir_frames(
		SMGA_ROOT + "/Goblin_SMG_alt/animations/standing_idle_alt")
static var SMGA_WALK_FRAMES: Array = _load_dir_frames(
		SMGA_ROOT + "/Goblin_SMG_alt/animations/standing_idle_walk")
static var SMGA_RAISE_FRAMES: Array = _load_dir_frames(
		SMGA_ROOT + "/Goblin_SMG_alt/animations/standing_idle_to_readyToFire")
static var SMGA_AIM_IDLE_FRAMES: Array = _load_only_anim(
		SMGA_ROOT + "/ready_to_fire_stance/animations")
static var SMGA_DEATH_FRAMES: Array = _load_dir_frames(
		SMGA_ROOT + "/Goblin_SMG_alt/animations/standing_idle_to_dead")
static var SMGA_HURT_FRAMES: Array = _load_dir_frames(
		SMGA_ROOT + "/Goblin_SMG_alt/animations/standing_idle_damage")
static var SMGA_RELOAD_FRAMES: Array = _load_dir_frames(
		SMGA_ROOT + "/Goblin_SMG_alt/animations/standing_idle_reload")

# Bolt-action marksman. The reload set carries real weight for this one - he
# works the bolt between every shot, so it plays as often as his firing does.
static var BOLT_FRAMES: Array[Texture2D] = _load_rotation_frames(
		BOLT_ROOT + "/Goblin_BoltRifle/rotations")
static var BOLT_AIM_FRAMES: Array[Texture2D] = _load_rotation_frames(
		BOLT_ROOT + "/ReadyToFire_Stance/rotations")
static var BOLT_DEAD_FRAMES: Array[Texture2D] = _load_rotation_frames(
		BOLT_ROOT + "/Dead_stance/rotations")
static var BOLT_IDLE_FRAMES: Array = _load_dir_frames(
		BOLT_ROOT + "/Goblin_BoltRifle/animations/standing_idle")
static var BOLT_IDLE_ALT_FRAMES: Array = _load_dir_frames(
		BOLT_ROOT + "/Goblin_BoltRifle/animations/standing_idle_alt")
static var BOLT_WALK_FRAMES: Array = _load_dir_frames(
		BOLT_ROOT + "/Goblin_BoltRifle/animations/standing_idle_walk")
static var BOLT_RAISE_FRAMES: Array = _load_dir_frames(
		BOLT_ROOT + "/Goblin_BoltRifle/animations/standing_idle_to_readyToFire")
static var BOLT_AIM_IDLE_FRAMES: Array = _load_dir_frames(
		BOLT_ROOT + "/ReadyToFire_Stance/animations/standing-readyToFire_idle")
static var BOLT_DEATH_FRAMES: Array = _load_dir_frames(
		BOLT_ROOT + "/Goblin_BoltRifle/animations/standing_idle_to_dead")
static var BOLT_HURT_FRAMES: Array = _load_dir_frames(
		BOLT_ROOT + "/Goblin_BoltRifle/animations/standing_idle_damage")
static var BOLT_RELOAD_FRAMES: Array = _load_dir_frames(
		BOLT_ROOT + "/Goblin_BoltRifle/animations/standing_idle_reload")

# Visual-only randomness (which idle variation plays). Never read back into
# game state, mirroring Sfx and Fx.
static var _vis_rng := RandomNumberGenerator.new()
static var SCOUT_DEAD_FRAMES: Array[Texture2D] = _load_rotation_frames(
		"res://assets/sprites/Scout/dead_stance/rotations")
static var GOBLIN_DEAD_FRAMES: Array[Texture2D] = _load_rotation_frames(
		"res://assets/sprites/Goblin/Dead_stance/rotations")

enum Anim { IDLE, IDLE_ALT, WALK, RAISE, AIM_IDLE, LOWER, DIE, DEAD, HURT, RELOAD }

# Chance that a completed idle cycle plays the alternate idle instead of
# repeating the main one. Kept low so the variation stays a garnish.
const IDLE_ALT_CHANCE := 0.14

# Front arc half-width in 45-degree sectors: 1 -> 135 degrees of cover.
# Shots from outside a unit's front arc ignore its cover, and overwatch
# only reacts inside it.
const ARC_HALF_SECTORS := 1

const WALK_FPS := 18.0
const IDLE_FPS := 8.0
const AIM_IDLE_FPS := 8.0
const RAISE_FPS := 36.0
const DIE_FPS := 14.0
const HURT_FPS := 18.0
const RELOAD_FPS := 14.0

# Rifle-tip offsets in Unit space per facing sector, measured from the
# aim-stance PNGs by tools/measure_muzzle.gd (sector order = DIR_NAMES).
const SCOUT_MUZZLE_OFFSETS: Array[Vector2] = [
	Vector2(32, -40),   # east
	Vector2(10, -6),    # south-east
	Vector2(10, -2),    # south
	Vector2(-14, -6),   # south-west
	Vector2(-34, -40),  # west
	Vector2(-34, -44),  # north-west
	Vector2(-8, -62),   # north
	Vector2(30, -44),   # north-east
]
# Battle rifle: longer barrel, so the muzzle sits further out than the
# carbine's. South is hand-corrected - facing the camera the rifle points
# down-left rather than toward the viewer, which the scan cannot know.
const LEAD_MUZZLE_OFFSETS: Array[Vector2] = [
	Vector2(34, -36),   # east
	Vector2(34, -20),   # south-east
	Vector2(-12, -20),  # south
	Vector2(-36, -20),  # south-west
	Vector2(-38, -36),  # west
	Vector2(-32, -52),  # north-west
	Vector2(-6, -60),   # north
	Vector2(30, -52),   # north-east
]
# Belt-fed weapon held low across the body. South and south-west are
# hand-corrected off the scan, which lands on boots for those poses.
const GUNNER_MUZZLE_OFFSETS: Array[Vector2] = [
	Vector2(36, -34),   # east
	Vector2(36, -26),   # south-east
	Vector2(-14, -18),  # south
	Vector2(-36, -24),  # south-west
	Vector2(-38, -34),  # west
	Vector2(-34, -46),  # north-west
	Vector2(-6, -60),   # north
	Vector2(32, -48),   # north-east
]
# A submachine gun is short and held tight to the chest, so the muzzle sits
# closer in than a rifle's. The three southern facings are hand-corrected -
# with the weapon pointing at the camera the scan lands on boots.
const SMG_MUZZLE_OFFSETS: Array[Vector2] = [
	Vector2(36, -34),   # east
	Vector2(26, -22),   # south-east
	Vector2(-12, -20),  # south
	Vector2(-26, -22),  # south-west
	Vector2(-32, -34),  # west
	Vector2(-28, -44),  # north-west
	Vector2(-4, -60),   # north
	Vector2(32, -44),   # north-east
]
# The alt raider is scrawnier and holds the same weapon tighter, so its
# muzzle sits a little closer in. Measured off 56x56 sheets against the
# SPRITE_OFFSET_56 anchor; the southern three are taken from the raider's
# hand-corrected values, since with the weapon aimed at the camera the scan
# lands on boots for those poses.
const SMGA_MUZZLE_OFFSETS: Array[Vector2] = [
	Vector2(30, -40),   # east
	Vector2(26, -22),   # south-east
	Vector2(-12, -20),  # south
	Vector2(-26, -22),  # south-west
	Vector2(-32, -40),  # west
	Vector2(-28, -42),  # north-west
	Vector2(2, -62),    # north
	Vector2(26, -42),   # north-east
]
# A revolver on an outstretched arm reaches further from the body than a
# shouldered weapon. South is hand-corrected off the boot the scan finds.
const REV_MUZZLE_OFFSETS: Array[Vector2] = [
	Vector2(38, -32),   # east
	Vector2(32, -14),   # south-east
	Vector2(-14, -20),  # south
	Vector2(-32, -14),  # south-west
	Vector2(-38, -32),  # west
	Vector2(-30, -50),  # north-west
	Vector2(-2, -66),   # north
	Vector2(30, -50),   # north-east
]
# A long bolt rifle, so the muzzle reaches further out than any other goblin
# weapon. North is genuinely offset to his right - the barrel stands clear of
# the head as a thin column in the art, and the scan lands on its tip. The
# southern three are hand-corrected off the boots the scan finds there.
const BOLT_MUZZLE_OFFSETS: Array[Vector2] = [
	Vector2(32, -36),   # east
	Vector2(32, -22),   # south-east
	Vector2(-24, -24),  # south
	Vector2(-34, -22),  # south-west
	Vector2(-34, -32),  # west
	Vector2(-30, -44),  # north-west
	Vector2(16, -68),   # north
	Vector2(28, -46),   # north-east
]
const GOBLIN_MUZZLE_OFFSETS: Array[Vector2] = [
	Vector2(34, -34),   # east
	Vector2(30, -20),   # south-east
	Vector2(-18, -2),   # south
	Vector2(-30, -18),  # south-west
	Vector2(-32, -34),  # west
	Vector2(-30, -40),  # north-west
	Vector2(-6, -60),   # north
	Vector2(32, -40),   # north-east
]

# Both sets have their figure's feet ~15px below canvas center; 2x scale puts
# a ~30px figure at ~60px on screen, sitting on the diamond center.
const SPRITE_SCALE := Vector2(2, 2)
const SPRITE_OFFSET := Vector2(0, -15)
# The alt raider ships on 56x56 sheets rather than 64x64. Its figure is the
# same size, but the tighter canvas puts the boots two screen pixels high on
# the shared anchor, so it gets its own.
const SPRITE_OFFSET_56 := Vector2(0, -14)

const PIP_SIZE := Vector2(7, 5)
const PIP_GAP := 2.0
const PIP_Y := -68.0
const PIP_FULL := Color("58c04a")
const PIP_EMPTY := Color(0.15, 0.15, 0.15, 0.7)
# Ammo pips sit just under the HP row. Only units with a magazine draw them.
const AMMO_SIZE := Vector2(4, 4)
const AMMO_GAP := 3.0
const AMMO_Y := PIP_Y + 8.0
const AMMO_FULL := Color("c9a227")
const AMMO_EMPTY := Color(0.18, 0.14, 0.06, 0.7)
const AMMO_OUT := Color("ff5a3c")
const SUPPRESSED_COLOR := Color("8fb8d8")
const RING_COLOR := Color("ffd94a")        # player selection
const ENEMY_RING_COLOR := Color("ff5a3c")  # AI unit currently acting
const DONE_TINT := Color(0.55, 0.55, 0.55)

# Ground contact shadow. Squashed to the tile's own 2:1 ratio and nudged
# toward a consistent upper-left sun, matching the props Board draws.
const SHADOW_SQUASH := 0.469  # TILE_H / TILE_W
const SHADOW_OFFSET := Vector2(3, 2)
const SHADOW_RADIUS := 19.0
const SHADOW_COLOR := Color(0.16, 0.10, 0.06, 0.26)
const CORPSE_SHADOW_RADIUS := 26.0
const CORPSE_SHADOW_COLOR := Color(0.16, 0.10, 0.06, 0.16)

# Ground wedge showing the unit's front arc (where cover protects it and
# overwatch reacts). Brighter while watching or selected.
const WEDGE_RADIUS := 34.0
const WEDGE_IDLE := Color(1.0, 0.95, 0.8, 0.10)
const WEDGE_ACTIVE := Color("ffb84a")  # matches the overwatch marker

var team := TEAM_SCOUT
var kind := Kind.SCOUT
var max_hp := 3
var move_range := 4
var attack_range := 4
var damage := 1
var accuracy := 90  # base percent chance to hit before modifiers
var mag_size := 0  # 0 means unlimited ammo (goblins)
var ammo := 0

var hp := 3
var cell := Vector2i.ZERO
var moved := false
var acted := false
var selected := false
var frames: Array[Texture2D] = SCOUT_FRAMES
var aim_frames: Array[Texture2D] = SCOUT_AIM_FRAMES
var walk_frames: Array = SCOUT_WALK_FRAMES
var idle_frames: Array = SCOUT_IDLE_FRAMES
var raise_frames: Array = SCOUT_RAISE_FRAMES
var aim_idle_frames: Array = SCOUT_AIM_IDLE_FRAMES
var death_frames: Array = SCOUT_DEATH_FRAMES
var dead_frames: Array[Texture2D] = SCOUT_DEAD_FRAMES
var idle_alt_frames: Array = SCOUT_IDLE_ALT_FRAMES
var hurt_frames: Array = SCOUT_HURT_FRAMES
var reload_frames: Array = SCOUT_RELOAD_FRAMES
var facing_sector := 2  # south
var arc_half := ARC_HALF_SECTORS
var arc_preview_sector := -1  # >= 0 while the player is aiming an arc
var overwatching := false
var suppression := 0  # team-turns of being pinned down remaining
var anim := Anim.IDLE
var anim_time := 0.0
var anim_frame := 0
var _anim_return := Anim.IDLE  # where a one-shot animation goes when it ends
var acting := false
var marker_y := 0.0:
	set(value):
		marker_y = value
		queue_redraw()
# Sprite anchor for this unit's sheet size; setup() picks it per kind.
var sprite_offset := SPRITE_OFFSET
var _body_tween: Tween = null
var _marker_tween: Tween = null

@onready var sprite: Sprite2D = $Sprite


func _ready() -> void:
	_vis_rng.randomize()
	sprite.scale = SPRITE_SCALE
	sprite.offset = sprite_offset
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func setup(p_kind: Kind, p_cell: Vector2i) -> void:
	kind = p_kind
	team = TEAM_SCOUT if kind == Kind.SCOUT or kind == Kind.TEAM_LEAD \
			or kind == Kind.MACHINEGUNNER else TEAM_GOBLIN
	cell = p_cell
	match kind:
		Kind.SCOUT:
			# Damage granularity is 2 so junk cover can halve it to 1.
			max_hp = 8
			move_range = 5
			attack_range = 4
			damage = 2
			accuracy = 90  # trained marksmen
			mag_size = 3
			frames = SCOUT_FRAMES
			aim_frames = SCOUT_AIM_FRAMES
			walk_frames = SCOUT_WALK_FRAMES
			idle_frames = SCOUT_IDLE_FRAMES
			raise_frames = SCOUT_RAISE_FRAMES
			aim_idle_frames = SCOUT_AIM_IDLE_FRAMES
			death_frames = SCOUT_DEATH_FRAMES
			dead_frames = SCOUT_DEAD_FRAMES
			idle_alt_frames = SCOUT_IDLE_ALT_FRAMES
			hurt_frames = SCOUT_HURT_FRAMES
			reload_frames = SCOUT_RELOAD_FRAMES
		Kind.TEAM_LEAD:
			# Designated marksman: a battle rifle reaches further and drops a
			# healthy goblin in one hit, paid for with a two-round magazine,
			# a slower advance, and no burst.
			max_hp = 8
			move_range = 4
			attack_range = 6
			damage = 4
			accuracy = 92
			mag_size = 2
			frames = LEAD_FRAMES
			aim_frames = LEAD_AIM_FRAMES
			walk_frames = LEAD_WALK_FRAMES
			idle_frames = LEAD_IDLE_FRAMES
			raise_frames = LEAD_RAISE_FRAMES
			aim_idle_frames = LEAD_AIM_IDLE_FRAMES
			death_frames = LEAD_DEATH_FRAMES
			dead_frames = LEAD_DEAD_FRAMES
			idle_alt_frames = LEAD_IDLE_ALT_FRAMES
			hurt_frames = LEAD_HURT_FRAMES
			reload_frames = LEAD_RELOAD_FRAMES
		Kind.MACHINEGUNNER:
			# Belt-fed support weapon: no single shot, a deep magazine, and
			# the volume of fire to pin a target. Slow to reposition.
			max_hp = 8
			move_range = 3
			attack_range = 4
			damage = 2
			accuracy = 78  # sprays rather than aims
			mag_size = 6
			frames = MG_FRAMES
			aim_frames = MG_AIM_FRAMES
			walk_frames = MG_WALK_FRAMES
			idle_frames = MG_IDLE_FRAMES
			raise_frames = MG_RAISE_FRAMES
			aim_idle_frames = MG_AIM_IDLE_FRAMES
			death_frames = MG_DEATH_FRAMES
			dead_frames = MG_DEAD_FRAMES
			idle_alt_frames = MG_IDLE_ALT_FRAMES
			hurt_frames = MG_HURT_FRAMES
			reload_frames = MG_RELOAD_FRAMES
		Kind.GOBLIN_SMG:
			# Close-assault raider: rushes in and empties a burst at knife
			# range. Almost no reach, so the answer is to kill it on the way.
			max_hp = 4
			move_range = 5
			attack_range = 2
			damage = 2
			accuracy = 58
			frames = SMG_FRAMES
			aim_frames = SMG_AIM_FRAMES
			walk_frames = SMG_WALK_FRAMES
			idle_frames = SMG_IDLE_FRAMES
			raise_frames = SMG_RAISE_FRAMES
			aim_idle_frames = SMG_AIM_IDLE_FRAMES
			death_frames = SMG_DEATH_FRAMES
			dead_frames = SMG_DEAD_FRAMES
			idle_alt_frames = SMG_IDLE_ALT_FRAMES
			hurt_frames = SMG_HURT_FRAMES
			reload_frames = SMG_RELOAD_FRAMES
		Kind.GOBLIN_SMG_ALT:
			# The same submachine gun on a half-starved frame. He outruns every
			# other unit on the field and arrives a turn ahead of his heavier
			# twin - but he cannot hold the weapon down, so he hits less often
			# and folds a shot sooner behind cover.
			max_hp = 3
			move_range = 6
			attack_range = 2
			damage = 2
			accuracy = 52  # too light to fight the recoil
			frames = SMGA_FRAMES
			aim_frames = SMGA_AIM_FRAMES
			walk_frames = SMGA_WALK_FRAMES
			idle_frames = SMGA_IDLE_FRAMES
			raise_frames = SMGA_RAISE_FRAMES
			aim_idle_frames = SMGA_AIM_IDLE_FRAMES
			death_frames = SMGA_DEATH_FRAMES
			dead_frames = SMGA_DEAD_FRAMES
			idle_alt_frames = SMGA_IDLE_ALT_FRAMES
			hurt_frames = SMGA_HURT_FRAMES
			reload_frames = SMGA_RELOAD_FRAMES
		Kind.GOBLIN_BOLT:
			# The Choir's designated marksman. One round in the rifle and the
			# bolt worked by hand between shots, so he reloads after every
			# single one - and since reloading costs the move, he is rooted
			# for as long as he keeps firing. In exchange he outranges every
			# other goblin and hits hard enough to halve a scout.
			max_hp = 4
			move_range = 3
			attack_range = 5
			damage = 4
			accuracy = 70  # the only goblin who actually aims
			mag_size = 1
			frames = BOLT_FRAMES
			aim_frames = BOLT_AIM_FRAMES
			walk_frames = BOLT_WALK_FRAMES
			idle_frames = BOLT_IDLE_FRAMES
			raise_frames = BOLT_RAISE_FRAMES
			aim_idle_frames = BOLT_AIM_IDLE_FRAMES
			death_frames = BOLT_DEATH_FRAMES
			dead_frames = BOLT_DEAD_FRAMES
			idle_alt_frames = BOLT_IDLE_ALT_FRAMES
			hurt_frames = BOLT_HURT_FRAMES
			reload_frames = BOLT_RELOAD_FRAMES
		Kind.GOBLIN_REVOLVER:
			# The Choir's newest and worst-equipped: no shirt, no cover, and
			# whatever sidearm was left over. Two HP means a single carbine
			# round puts him down - the fiction stated in numbers.
			max_hp = 2
			move_range = 5
			attack_range = 3
			damage = 2
			accuracy = 48  # a worn revolver and no training at all
			frames = REV_FRAMES
			aim_frames = REV_AIM_FRAMES
			walk_frames = REV_WALK_FRAMES
			idle_frames = REV_IDLE_FRAMES
			raise_frames = REV_RAISE_FRAMES
			aim_idle_frames = REV_AIM_IDLE_FRAMES
			death_frames = REV_DEATH_FRAMES
			dead_frames = REV_DEAD_FRAMES
			idle_alt_frames = REV_IDLE_ALT_FRAMES
			hurt_frames = REV_HURT_FRAMES
			reload_frames = REV_RELOAD_FRAMES
		Kind.GOBLIN:
			max_hp = 4
			move_range = 4
			attack_range = 3
			damage = 2
			accuracy = 60  # scavenged rifles, no training
			frames = GOBLIN_FRAMES
			aim_frames = GOBLIN_AIM_FRAMES
			walk_frames = GOBLIN_WALK_FRAMES
			idle_frames = GOBLIN_IDLE_FRAMES
			raise_frames = GOBLIN_RAISE_FRAMES
			aim_idle_frames = GOBLIN_AIM_IDLE_FRAMES
			death_frames = GOBLIN_DEATH_FRAMES
			dead_frames = GOBLIN_DEAD_FRAMES
			idle_alt_frames = GOBLIN_IDLE_ALT_FRAMES
			hurt_frames = GOBLIN_HURT_FRAMES
			reload_frames = GOBLIN_RELOAD_FRAMES
	sprite_offset = SPRITE_OFFSET_56 if kind == Kind.GOBLIN_SMG_ALT else SPRITE_OFFSET
	if sprite != null:  # setup() can run before _ready() outside a live tree
		sprite.offset = sprite_offset
	# Face the enemy side at the start of the battle.
	set_facing(Vector2(1, 0.5) if team == TEAM_SCOUT else Vector2(-1, 0.5))
	hp = max_hp
	ammo = mag_size
	# Desync idle cycles so units don't all breathe in lockstep.
	anim_time = float((p_cell.x * 7 + p_cell.y * 13) % 9) / IDLE_FPS


static func _load_dir_frames(base: String) -> Array:
	var result: Array = []
	for dir_name in DIR_NAMES:
		var dir_frames: Array[Texture2D] = []
		var i := 0
		while ResourceLoader.exists("%s/%s/frame_%03d.png" % [base, dir_name, i]):
			dir_frames.append(load("%s/%s/frame_%03d.png" % [base, dir_name, i]))
			i += 1
		result.append(dir_frames)
	return result


## Loads the single animation sitting under an animations/ folder. Pixel Lab
## names some export folders after the sentence that generated them, which is
## both unstable and unreadable - find the folder instead of baking it in.
static func _load_only_anim(anim_root: String) -> Array:
	var dir := DirAccess.open(anim_root)
	if dir != null:
		var names := dir.get_directories()
		if not names.is_empty():
			return _load_dir_frames(anim_root + "/" + names[0])
	push_error("[Unit] no animation folder under " + anim_root)
	return []


## Loads a rotations/ folder of single per-direction PNGs (east.png, ...).
static func _load_rotation_frames(base: String) -> Array[Texture2D]:
	var result: Array[Texture2D] = []
	for dir_name in DIR_NAMES:
		var path := "%s/%s.png" % [base, dir_name]
		result.append(load(path) if ResourceLoader.exists(path) else null)
	return result


## Turn toward a screen-space direction, keeping the current stance.
func set_facing(screen_dir: Vector2) -> void:
	if screen_dir.length_squared() < 0.01:
		return
	set_facing_sector(wrapi(roundi(screen_dir.angle() / (TAU / 8.0)), 0, 8))


func set_facing_sector(sector: int) -> void:
	if sector < 0 or sector == facing_sector:
		return
	facing_sector = sector
	_update_sprite()
	queue_redraw()


## True if the given sector falls inside this unit's front arc. Shots from
## outside it ignore cover, and overwatch will not react to it.
func covers_sector(sector: int) -> bool:
	if sector < 0:
		return true
	return absi(wrapi(sector - facing_sector + 4, 0, 8) - 4) <= arc_half


func _set_anim(value: Anim) -> void:
	anim = value
	anim_time = 0.0
	anim_frame = 0
	_update_sprite()


## Plays the idle-to-aim transition and holds in the aimed idle loop.
## Awaitable; returns immediately if the rifle is already up.
func raise_rifle() -> void:
	if anim == Anim.AIM_IDLE or anim == Anim.DIE or anim == Anim.DEAD:
		return
	if anim != Anim.RAISE:
		_set_anim(Anim.RAISE)
	var n: int = maxi(raise_frames[facing_sector].size(), 1)
	# One extra frame of padding so the shot never fires before _process
	# has visually reached the aimed pose (frame quantization race).
	await get_tree().create_timer(float(n) / RAISE_FPS + 0.03).timeout


## Plays the aim transition in reverse back to idle.
func lower_rifle() -> void:
	if anim == Anim.AIM_IDLE or anim == Anim.RAISE:
		_set_anim(Anim.LOWER)


## Flinch on taking a hit, then resume whatever stance was interrupted.
## Skipped mid-stride and mid-fall, where it would fight a longer animation.
func play_hurt() -> void:
	if anim == Anim.DIE or anim == Anim.DEAD or anim == Anim.WALK:
		return
	if hurt_frames[facing_sector].is_empty():
		return
	_anim_return = Anim.AIM_IDLE if _rifle_is_up() else Anim.IDLE
	_set_anim(Anim.HURT)


## Work the bolt and seat a fresh magazine. Awaitable so the caller can hold
## the turn for its duration.
func play_reload() -> void:
	var cycle: Array = reload_frames[facing_sector]
	if cycle.is_empty() or anim == Anim.DIE or anim == Anim.DEAD:
		return
	_anim_return = Anim.AIM_IDLE if _rifle_is_up() else Anim.IDLE
	_set_anim(Anim.RELOAD)
	await get_tree().create_timer(float(cycle.size()) / RELOAD_FPS).timeout


func _rifle_is_up() -> bool:
	return overwatching or anim == Anim.AIM_IDLE or anim == Anim.RAISE


## Global position of the raised rifle's tip for the current facing.
func muzzle_point() -> Vector2:
	var offsets := GOBLIN_MUZZLE_OFFSETS
	match kind:
		Kind.SCOUT:
			offsets = SCOUT_MUZZLE_OFFSETS
		Kind.TEAM_LEAD:
			offsets = LEAD_MUZZLE_OFFSETS
		Kind.MACHINEGUNNER:
			offsets = GUNNER_MUZZLE_OFFSETS
		Kind.GOBLIN_SMG:
			offsets = SMG_MUZZLE_OFFSETS
		Kind.GOBLIN_SMG_ALT:
			offsets = SMGA_MUZZLE_OFFSETS
		Kind.GOBLIN_BOLT:
			offsets = BOLT_MUZZLE_OFFSETS
		Kind.GOBLIN_REVOLVER:
			offsets = REV_MUZZLE_OFFSETS
	return to_global(offsets[facing_sector])


## The machinegunner has no semi-automatic setting - his lightest option is
## a burst, so a plain click fires one.
func can_single_shot() -> bool:
	return kind != Kind.MACHINEGUNNER


## The lead's battle rifle is semi-automatic; everything automatic bursts.
func can_burst() -> bool:
	return kind == Kind.SCOUT or kind == Kind.MACHINEGUNNER \
			or kind == Kind.GOBLIN_SMG or kind == Kind.GOBLIN_SMG_ALT


## Bracing is what buys the rifleman his burst. The gunner's weapon does it
## from the hip, so he keeps burst after moving.
func burst_requires_still() -> bool:
	return kind == Kind.SCOUT


func can_full_auto() -> bool:
	return kind == Kind.MACHINEGUNNER


## Suppressive fire is the gunner's ability alone - nobody else carries the
## volume of ammunition to keep heads down.
func can_suppress() -> bool:
	return kind == Kind.MACHINEGUNNER


func display_name() -> String:
	match kind:
		Kind.TEAM_LEAD:
			return "Scout Team Lead"
		Kind.MACHINEGUNNER:
			return "Scout Machinegunner"
		Kind.GOBLIN:
			return "Rust Choir Chorister"
		Kind.GOBLIN_SMG:
			return "Rust Choir Raider"
		Kind.GOBLIN_SMG_ALT:
			return "Rust Choir Skirmisher"
		Kind.GOBLIN_BOLT:
			return "Rust Choir Cantor"
		Kind.GOBLIN_REVOLVER:
			return "Rust Choir Novice"
	return "Desert Scout"


## Enter/leave overwatch: rifle raises and stays up, marker above the pips.
## Leaving overwatch does NOT lower the rifle - the shot flow or turn expiry
## handles that explicitly.
func set_overwatch(value: bool) -> void:
	overwatching = value
	if value and anim != Anim.RAISE and anim != Anim.AIM_IDLE:
		_set_anim(Anim.RAISE)
	queue_redraw()


func start_walking() -> void:
	if anim == Anim.DIE or anim == Anim.DEAD:
		return
	_set_anim(Anim.WALK)


func stop_walking() -> void:
	if anim == Anim.WALK:
		_set_anim(Anim.IDLE)


func _process(delta: float) -> void:
	if anim == Anim.DEAD:
		return
	var fps := IDLE_FPS
	match anim:
		Anim.WALK:
			fps = WALK_FPS
		Anim.RAISE, Anim.LOWER:
			fps = RAISE_FPS
		Anim.AIM_IDLE:
			fps = AIM_IDLE_FPS
		Anim.DIE:
			fps = DIE_FPS
		Anim.HURT:
			fps = HURT_FPS
		Anim.RELOAD:
			fps = RELOAD_FPS
	anim_time += delta
	var idx := int(anim_time * fps)
	if idx == anim_frame:
		return
	anim_frame = idx
	var cycle: Array = _current_cycle()
	var length: int = maxi(cycle.size(), 1)
	if anim_frame >= length:
		match anim:
			Anim.RAISE:
				_set_anim(Anim.AIM_IDLE)
			Anim.LOWER:
				_set_anim(Anim.IDLE)
			Anim.DIE:
				_set_anim(Anim.DEAD)
			Anim.HURT, Anim.RELOAD:
				_set_anim(_anim_return)  # back to whatever we interrupted
			Anim.IDLE:
				# Occasionally break the loop with the alternate idle.
				if not idle_alt_frames[facing_sector].is_empty() \
						and _vis_rng.randf() < IDLE_ALT_CHANCE:
					_set_anim(Anim.IDLE_ALT)
				else:
					_set_anim(Anim.IDLE)
			Anim.IDLE_ALT:
				_set_anim(Anim.IDLE)
			_:
				_set_anim(anim)  # WALK / AIM_IDLE loop from the top
		return
	_update_sprite()


func _current_cycle() -> Array:
	match anim:
		Anim.WALK:
			return walk_frames[facing_sector]
		Anim.RAISE, Anim.LOWER:
			return raise_frames[facing_sector]
		Anim.AIM_IDLE:
			return aim_idle_frames[facing_sector]
		Anim.DIE:
			return death_frames[facing_sector]
		Anim.IDLE_ALT:
			return idle_alt_frames[facing_sector]
		Anim.HURT:
			return hurt_frames[facing_sector]
		Anim.RELOAD:
			return reload_frames[facing_sector]
	return idle_frames[facing_sector]


func _update_sprite() -> void:
	if sprite == null:
		return  # setup() can run before _ready() outside a live tree
	if anim == Anim.DEAD:
		var corpse := dead_frames[facing_sector]
		if corpse != null:
			sprite.texture = corpse
		return
	var cycle: Array = _current_cycle()
	if cycle.is_empty():
		# Fallback to static poses if a frame set is missing.
		var wants_aim := anim == Anim.RAISE or anim == Anim.AIM_IDLE or anim == Anim.LOWER
		sprite.texture = (aim_frames if wants_aim else frames)[facing_sector]
		return
	var idx := anim_frame
	if anim == Anim.LOWER:
		idx = cycle.size() - 1 - clampi(anim_frame, 0, cycle.size() - 1)
	elif anim == Anim.DIE or anim == Anim.HURT or anim == Anim.RELOAD:
		idx = clampi(anim_frame, 0, cycle.size() - 1)  # one-shot, never wraps
	else:
		idx = anim_frame % cycle.size()
	sprite.texture = cycle[idx]


func is_alive() -> bool:
	return hp > 0


## Pinned down by incoming fire: shoots worse and cannot set overwatch.
## Set to 2 so it survives the decrement at the start of the target's own
## next turn and actually costs them that turn.
func suppress() -> void:
	suppression = 2
	queue_redraw()


func is_suppressed() -> bool:
	return suppression > 0


func has_ammo(rounds := 1) -> bool:
	return mag_size == 0 or ammo >= rounds


func spend_ammo() -> void:
	if mag_size > 0:
		ammo = maxi(ammo - 1, 0)
		queue_redraw()


func reload() -> void:
	ammo = mag_size
	queue_redraw()


## Dry and carrying a magazine, so it cannot shoot until it reloads. Units
## with unlimited ammo (mag_size 0) never need one.
func needs_reload() -> bool:
	return mag_size > 0 and ammo == 0


## Kick the sprite backward off a shot and settle it. sprite.position is
## otherwise unused (SPRITE_OFFSET lives in sprite.offset), so body motion
## has its own channel and never fights the animation frames.
func recoil(dir: Vector2) -> void:
	_body_shove(-dir * 4.0, 0.14, Tween.TRANS_QUAD)


func _body_shove(offset: Vector2, time: float, trans: Tween.TransitionType) -> void:
	if _body_tween != null and _body_tween.is_valid():
		_body_tween.kill()
	sprite.position = offset
	_body_tween = create_tween()
	_body_tween.tween_property(sprite, "position", Vector2.ZERO, time) \
			.set_trans(trans).set_ease(Tween.EASE_OUT)


func take_damage(amount: int, from_dir := Vector2.ZERO) -> void:
	if hp <= 0:
		return  # already dead; never double-kill a corpse
	_spawn_damage_number(amount)
	hp = maxi(hp - amount, 0)
	queue_redraw()
	var lethal := hp == 0
	if from_dir != Vector2.ZERO:
		_body_shove(from_dir * 5.0, 0.18, Tween.TRANS_BACK)
	var flash := create_tween()
	flash.tween_property(sprite, "modulate",
			Color(2.0, 2.0, 2.0) if lethal else Color(1.6, 0.3, 0.3),
			0.11 if lethal else 0.08)
	flash.tween_property(sprite, "modulate", Color.WHITE, 0.15)
	if lethal:
		died.emit(self)
		_die()
	else:
		play_hurt()


## Plays the fall animation, then rests in the dead stance. The corpse stays
## in the tree for the whole battle; is_alive() == false makes every gameplay
## query (occupancy, targeting, turns) ignore it.
## Seconds until the falling body reaches the ground - used to time the dust.
func death_landing_time() -> float:
	return maxi(death_frames[facing_sector].size(), 1) * 0.6 / DIE_FPS


func _die() -> void:
	overwatching = false
	selected = false
	arc_preview_sector = -1
	# Dustier than the living so the eye skips corpses on a busy board.
	modulate = Color(0.72, 0.68, 0.64)
	# Nudge up a hair so y-sort keeps living units on this tile in front.
	position.y -= 0.6
	_set_anim(Anim.DIE)
	queue_redraw()


## Front-arc wedge on the ground. Points are built with the isometric
## y-squash baked in so the wedge aims where the sprite is looking.
func _draw_facing_wedge() -> void:
	var sector := arc_preview_sector if arc_preview_sector >= 0 else facing_sector
	var mid := sector * TAU / 8.0
	var half := (arc_half + 0.5) * TAU / 8.0
	var points := PackedVector2Array([Vector2.ZERO])
	for i in 9:
		var a: float = mid - half + 2.0 * half * float(i) / 8.0
		points.append(Vector2(cos(a) * WEDGE_RADIUS, sin(a) * WEDGE_RADIUS * SHADOW_SQUASH))
	var color := WEDGE_IDLE
	if arc_preview_sector >= 0:
		color = Color(WEDGE_ACTIVE, 0.45)
	elif overwatching:
		color = Color(WEDGE_ACTIVE, 0.34)
	elif selected:
		color = Color(WEDGE_ACTIVE, 0.20)
	draw_colored_polygon(points, color)


func _draw_shadow() -> void:
	var dead := hp <= 0
	draw_set_transform(SHADOW_OFFSET, 0.0, Vector2(1.0, SHADOW_SQUASH))
	draw_circle(Vector2.ZERO,
			CORPSE_SHADOW_RADIUS if dead else SHADOW_RADIUS,
			CORPSE_SHADOW_COLOR if dead else SHADOW_COLOR)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Pale "MISS" callout where a shot went wide.
func spawn_miss_text() -> void:
	_spawn_float_text("MISS", Color(0.85, 0.88, 0.92), 20)


## Floating "-N" label. Parented to this unit's parent (not the unit itself)
## so it outlives a killed unit; its tween is owned by the label for the same
## reason. z_index lifts it clear of the y-sorted entities.
func _spawn_damage_number(amount: int) -> void:
	_spawn_float_text("-%d" % amount, Color(1.0, 0.35, 0.3), 24)


func _spawn_float_text(text: String, color: Color, size: int) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 6)
	label.z_index = 20
	get_parent().add_child(label)
	label.global_position = global_position + Vector2(-12.0, -84.0)
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 40.0, 0.6)
	tween.tween_property(label, "modulate:a", 0.0, 0.6).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)


func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


## Marks the AI unit currently taking its action with a chevron that drops
## in from above, so the player can follow a five-goblin turn.
func set_acting(value: bool) -> void:
	acting = value
	if _marker_tween != null and _marker_tween.is_valid():
		_marker_tween.kill()
	if not value:
		queue_redraw()
		return
	marker_y = 18.0
	_marker_tween = create_tween()
	_marker_tween.tween_property(self, "marker_y", 0.0, 0.22) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func set_done(value: bool) -> void:
	moved = value
	acted = value
	modulate = DONE_TINT if value else Color(1, 1, 1, modulate.a)
	queue_redraw()


func start_turn() -> void:
	moved = false
	acted = false
	suppression = maxi(suppression - 1, 0)
	modulate = Color.WHITE
	if overwatching:
		set_overwatch(false)  # unfired overwatch expires...
		lower_rifle()         # ...and the rifle comes down
	queue_redraw()


func _draw() -> void:
	# Drawn first (and before the corpse guard) so every body keeps its
	# contact shadow. _draw renders behind child nodes, so the sprite's
	# feet always sit on top of it.
	_draw_shadow()
	if hp <= 0:
		return  # corpses carry no pips, rings, or markers
	_draw_facing_wedge()
	if selected:
		# Ground ellipse at the unit's feet, matching the isometric 2:1 view.
		var ring := RING_COLOR if team == TEAM_SCOUT else ENEMY_RING_COLOR
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
		draw_arc(Vector2.ZERO, 38.0, 0.0, TAU, 48, ring, 3.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var total_width := max_hp * PIP_SIZE.x + (max_hp - 1) * PIP_GAP
	var start_x := -total_width / 2.0
	for i in max_hp:
		var rect := Rect2(Vector2(start_x + i * (PIP_SIZE.x + PIP_GAP), PIP_Y), PIP_SIZE)
		draw_rect(rect, PIP_FULL if i < hp else PIP_EMPTY)
		draw_rect(rect, Color(0, 0, 0, 0.5), false, 1.0)
	if mag_size > 0:
		var ammo_width := mag_size * AMMO_SIZE.x + (mag_size - 1) * AMMO_GAP
		var ammo_x := -ammo_width / 2.0
		for i in mag_size:
			var slot := Rect2(Vector2(ammo_x + i * (AMMO_SIZE.x + AMMO_GAP), AMMO_Y), AMMO_SIZE)
			if i < ammo:
				draw_rect(slot, AMMO_FULL)
			else:
				draw_rect(slot, AMMO_OUT if ammo == 0 else AMMO_EMPTY)
	if overwatching:
		# Small amber diamond above the pips: "this unit is watching".
		var m := Vector2(0, PIP_Y - 9.0)
		draw_colored_polygon(PackedVector2Array([
			m + Vector2(0, -5), m + Vector2(5, 0), m + Vector2(0, 5), m + Vector2(-5, 0),
		]), Color("ffb84a"))
	elif is_suppressed():
		# Steel chevron pressed downward: "this one has its head down".
		var s := Vector2(0, PIP_Y - 9.0)
		draw_colored_polygon(PackedVector2Array([
			s + Vector2(-7, -4), s + Vector2(7, -4), s + Vector2(0, 6),
		]), SUPPRESSED_COLOR)
	if acting:
		# Drop-in chevron marking the AI unit taking its action. Lives in
		# empty air above the unit, so it never obscures the board.
		var c := Vector2(0, PIP_Y - 26.0 - marker_y)
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(0, 9), c + Vector2(-9, -6), c + Vector2(9, -6),
		]), ENEMY_RING_COLOR)
