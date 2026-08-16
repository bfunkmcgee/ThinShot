class_name Unit
extends Node2D

## One combatant on the grid. Stats are set by Battle.setup() per team.
## HP pips and the selection ring are drawn in _draw().

signal died(unit: Unit)
## Took a round and lived. Battle listens so it can charge the morale, which is
## a rule and therefore Rules' arithmetic rather than this file's - and Unit
## cannot name Rules without closing a compile cycle (see `morale` below).
signal wounded(unit: Unit)

const TEAM_SCOUT := 0
const TEAM_GOBLIN := 1

## Which soldier this is. Team is allegiance; kind is the role, so the two
## scout types can differ in weapon, stats, and art.
enum Kind {
	SCOUT, TEAM_LEAD, MACHINEGUNNER,
	GOBLIN, GOBLIN_SMG, GOBLIN_SMG_ALT, GOBLIN_REVOLVER, GOBLIN_BOLT,
	# Not a soldier. Carries no weapon, is never shot at, and until somebody
	# reaches them, does not move either.
	CIVILIAN,
	# Rodar Akai, the hero of the scouts. Appended last and must STAY last:
	# saves store the raw ordinal, so inserting mid-enum would quietly turn
	# every saved soldier into somebody else.
	HERO,
}

const LEAD_ROOT := "res://assets/sprites/Scout_TeamLead"
const MG_ROOT := "res://assets/sprites/Scout_MachineGunner/Scout_MachineGunner"
const SMG_ROOT := "res://assets/sprites/Goblin_SMG"
const REV_ROOT := "res://assets/sprites/Goblin_revolver"
const SMGA_ROOT := "res://assets/sprites/Goblin_SMG_alt"
const BOLT_ROOT := "res://assets/sprites/Goblin_BoltRifle"
const CIVILIAN_ROOT := "res://assets/sprites/Civilian"
const RODAR_ROOT := "res://assets/sprites/Rodar_Akai"
const SCOUT_ROOT := "res://assets/sprites/Scout"

# Directional pixel-art frames, indexed by 45-degree compass sector of the
# screen-space facing vector: 0=E, 1=SE, 2=S, 3=SW, 4=W, 5=NW, 6=N, 7=NE.
static var SCOUT_FRAMES: Array[Texture2D] = _load_rotation_frames(SCOUT_ROOT)
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
static var SCOUT_AIM_FRAMES: Array[Texture2D] = _load_rotation_frames(
		SCOUT_ROOT + "/Standing_Ready_to_fire_stance/rotations")
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
		SCOUT_ROOT + "/animations/Standing_idle_walk")
static var GOBLIN_WALK_FRAMES: Array = _load_dir_frames(
		"res://assets/sprites/Goblin/animations/standing_idle_walk")
static var SCOUT_IDLE_FRAMES: Array = _load_dir_frames(
		SCOUT_ROOT + "/animations/standing_idle")
static var GOBLIN_IDLE_FRAMES: Array = _load_dir_frames(
		"res://assets/sprites/Goblin/animations/standing_idle")
static var SCOUT_RAISE_FRAMES: Array = _load_dir_frames(
		SCOUT_ROOT + "/animations/standing_idle_to_ready_to_fire")
static var GOBLIN_RAISE_FRAMES: Array = _load_dir_frames(
		"res://assets/sprites/Goblin/animations/standing_idle_to_Standing_Ready_to_fire")
static var SCOUT_AIM_IDLE_FRAMES: Array = _load_dir_frames(
		SCOUT_ROOT + "/Standing_Ready_to_fire_stance/animations/standing_ready_to_fire_idle")
static var GOBLIN_AIM_IDLE_FRAMES: Array = _load_dir_frames(
		"res://assets/sprites/Goblin/Standing_Ready_to_fire_stance/animations/standing_ready_to_fire_idle")
static var SCOUT_DEATH_FRAMES: Array = _load_dir_frames(
		SCOUT_ROOT + "/animations/standing_idle_to_dead")
static var GOBLIN_DEATH_FRAMES: Array = _load_dir_frames(
		"res://assets/sprites/Goblin/animations/standing_idle_to_dead")
static var SCOUT_IDLE_ALT_FRAMES: Array = _load_dir_frames(
		SCOUT_ROOT + "/animations/standing_idle_alt")
static var GOBLIN_IDLE_ALT_FRAMES: Array = _load_dir_frames(
		"res://assets/sprites/Goblin/animations/standing_idle_alt")
static var SCOUT_HURT_FRAMES: Array = _load_dir_frames(
		SCOUT_ROOT + "/animations/standing_idle_damage")
static var GOBLIN_HURT_FRAMES: Array = _load_dir_frames(
		"res://assets/sprites/Goblin/animations/standing_idle_damage")
static var SCOUT_RELOAD_FRAMES: Array = _load_dir_frames(
		SCOUT_ROOT + "/animations/standing_idle_reload")
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

# Thirst runner with a submachine gun. Note the aim-idle folder uses a
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

# The worst-equipped of the Thirst: a pressed conscript with a revolver.
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

# Rodar Akai. A battle rifle like the team lead's, but his sheets ship on the
# canonical layout, so the paths read like the goblins' rather than the lead's.
static var RODAR_FRAMES: Array[Texture2D] = _load_rotation_frames(
		RODAR_ROOT + "/Rodar_Akai/rotations")
static var RODAR_AIM_FRAMES: Array[Texture2D] = _load_rotation_frames(
		RODAR_ROOT + "/ReadyToFire_Stance/rotations")
static var RODAR_DEAD_FRAMES: Array[Texture2D] = _load_rotation_frames(
		RODAR_ROOT + "/Dead_stance/rotations")
static var RODAR_IDLE_FRAMES: Array = _load_dir_frames(
		RODAR_ROOT + "/Rodar_Akai/animations/standing_idle")
static var RODAR_IDLE_ALT_FRAMES: Array = _load_dir_frames(
		RODAR_ROOT + "/Rodar_Akai/animations/standing_idle_alt")
static var RODAR_WALK_FRAMES: Array = _load_dir_frames(
		RODAR_ROOT + "/Rodar_Akai/animations/standing_idle_walk")
static var RODAR_RAISE_FRAMES: Array = _load_dir_frames(
		RODAR_ROOT + "/Rodar_Akai/animations/standing_idle_to_readyToFire")
static var RODAR_AIM_IDLE_FRAMES: Array = _load_dir_frames(
		RODAR_ROOT + "/ReadyToFire_Stance/animations/standing-readyToFire_idle")
static var RODAR_DEATH_FRAMES: Array = _load_dir_frames(
		RODAR_ROOT + "/Rodar_Akai/animations/standing_idle_to_dead")
static var RODAR_HURT_FRAMES: Array = _load_dir_frames(
		RODAR_ROOT + "/Rodar_Akai/animations/standing_idle_damage")
static var RODAR_RELOAD_FRAMES: Array = _load_dir_frames(
		RODAR_ROOT + "/Rodar_Akai/animations/standing_idle_reload")

# The prisoner. Two poses that matter: huddled where the Thirst left them, and
# on their feet once somebody has reached them. free() swaps between the sets.
static var CIVILIAN_COWER_FRAMES: Array[Texture2D] = _load_rotation_frames(
		CIVILIAN_ROOT + "/Cower_stance/rotations")
static var CIVILIAN_COWER_IDLE: Array = _load_dir_frames(
		CIVILIAN_ROOT + "/Cower_stance/animations/cower_idle")
static var CIVILIAN_FRAMES: Array[Texture2D] = _load_rotation_frames(
		CIVILIAN_ROOT + "/Civilian/rotations")
static var CIVILIAN_IDLE_FRAMES: Array = _load_dir_frames(
		CIVILIAN_ROOT + "/Civilian/animations/standing_idle")
static var CIVILIAN_WALK_FRAMES: Array = _load_dir_frames(
		CIVILIAN_ROOT + "/Civilian/animations/standing_idle_walk")
static var CIVILIAN_DEATH_FRAMES: Array = _load_dir_frames(
		CIVILIAN_ROOT + "/Civilian/animations/standing_idle_to_dead")
static var CIVILIAN_DEAD_FRAMES: Array[Texture2D] = _load_rotation_frames(
		CIVILIAN_ROOT + "/Dead_stance/rotations")

# Visual-only randomness (which idle variation plays). Never read back into
# game state, mirroring Sfx and Fx.
static var _vis_rng := RandomNumberGenerator.new()
static var SCOUT_DEAD_FRAMES: Array[Texture2D] = _load_rotation_frames(
		SCOUT_ROOT + "/dead_stance/rotations")
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

# What the machinegunner's overwatch adds over everyone else's: two tiles of
# reach, and two rounds in the reaction instead of one.
const OVERWATCH_RANGE_BONUS := 2
const OVERWATCH_VOLLEY := 2

# Manhattan radius of suppressive fire's beaten zone. Wide on purpose: it
# deals no damage, so its whole value is how much ground it shuts down at
# once. Queried through suppress_radius(), which Wide Sweep grows.
const SUPPRESS_RADIUS := 2

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
# Rodar's battle rifle. The southern three are taken from the team lead's
# hand-corrected values, since with the rifle aimed at the camera the scan
# lands on boots for those poses.
const RODAR_MUZZLE_OFFSETS: Array[Vector2] = [
	Vector2(38, -40),   # east
	Vector2(34, -20),   # south-east
	Vector2(-12, -20),  # south
	Vector2(-36, -20),  # south-west
	Vector2(-38, -36),  # west
	Vector2(-38, -40),  # north-west
	Vector2(-6, -62),   # north
	Vector2(38, -40),   # north-east
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
# muzzle sits a little closer in. Measured off 56x56 sheets against its own
# SPRITE_SPECS anchor; the southern three are taken from the raider's
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

# Per-kind sprite draw spec: the scale a kind's sheets are authored for and
# the offset that sits its figure's feet on the diamond centre. Legacy
# sheets have the feet ~15px below canvas centre and draw at 2x, putting a
# ~30px figure at ~60px on screen; the alt raider's tighter 56x56 canvas
# rides its boots one texel higher, so its offset is one short. As hi-res
# art lands, that unit's entry flips to scale (1, 1) with the offset doubled
# (0, -2x the texel figure) - same screen anchor, native pixels. Kinds
# without an entry use DEFAULT.
const SPRITE_SPECS: Dictionary = {
	"DEFAULT": {"scale": Vector2(2, 2), "offset": Vector2(0, -15)},
	Kind.GOBLIN_SMG_ALT: {"scale": Vector2(2, 2), "offset": Vector2(0, -14)},
}

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
# Rank chevrons, stacked upward beside the HP pips. Small enough to read as
# insignia rather than as another gameplay marker.
const RANK_COLOR := Color("ffd98a")
const RANK_GAP := 4.0   # from the left edge of the pip row
const RANK_W := 6.0     # how far the chevron reaches left
const RANK_H := 4.0     # how far it rises
const RANK_T := 2.0     # stroke thickness
const RANK_STEP := 5.0  # vertical pitch between chevrons

# How far the body drops when hunkered behind cover. Small on purpose: the
# prop drawn in front does most of the work, this just breaks the silhouette.
const CROUCH_SINK := 5.0
# Cover pips beside the rank chevrons: one bar for half, two for full.
const COVER_HALF_COLOR := Color("8ad4a0")
const COVER_FULL_COLOR := Color("6fe08a")

const SUPPRESSED_COLOR := Color("8fb8d8")
const RING_COLOR := Color("ffd94a")        # player selection
const ENEMY_RING_COLOR := Color("ff5a3c")  # AI unit currently acting
# The two ways a fighter stops. Deliberately not red: neither of these is a
# threat, and the palette should say so before the player reads the word.
const SURRENDER_COLOR := Color("e8e2c8")  # hands up
const ROUT_COLOR := Color("d9a441")       # running for the edge
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

# Campaign identity, stamped on by apply_progression() from the Game roster.
# Goblins never carry any: soldier_id 0 means "anonymous".
var soldier_id := 0
var surname := ""
var rank := 0
var perks: Array = []

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
# What this unit's shadow looks like on the ground it is standing on. Set by
# whoever spawns it; the defaults are the desert's, so a Unit dropped into a
# scene with no opinion still looks right. Kept as plain colours rather than a
# Board lookup so Unit stays free of any reference to the board it is on.
var shadow_color := SHADOW_COLOR
var corpse_shadow_color := CORPSE_SHADOW_COLOR
var facing_sector := 2  # south
var arc_half := ARC_HALF_SECTORS
var arc_preview_sector := -1  # >= 0 while the player is aiming an arc
var overwatching := false
var suppression := 0  # team-turns of being pinned down remaining
# Per-battle ability state. Units are rebuilt from scratch every battle, so
# plain vars ARE the once-per-battle charges - nothing here persists or saves.
var field_dressing_used := false
var rally_used := false
var untouchable_used := false
# Rally's steadying hand: added straight into hit_chance, cleared in this
# soldier's own start_turn - so it covers the rest of the player turn it was
# given in and any overwatch reaction fired during the enemy turn after.
var rally_bonus := 0
var anim := Anim.IDLE
var anim_time := 0.0
var anim_frame := 0
var _anim_return := Anim.IDLE  # where a one-shot animation goes when it ends
var acting := false
var marker_y := 0.0:
	set(value):
		marker_y = value
		queue_redraw()
# Sprite anchor and draw scale for this unit's sheets; setup() picks them
# per kind from SPRITE_SPECS.
var sprite_scale: Vector2 = SPRITE_SPECS.DEFAULT.scale
var sprite_offset: Vector2 = SPRITE_SPECS.DEFAULT.offset
# Board.CoverLevel of the cell this unit is standing on, as a plain int so
# Unit stays independent of Board. 0 = none, 1 = half, 2 = full.
var cover_level := 0
# Every combat marking - pips, wedge, rank, cover bars, status chevrons - hangs
# off this. Outside a battle a unit is a person standing in a camp, and all of
# it is noise; only the contact shadow survives.
var show_combat_hud := true
# A prisoner nobody has reached yet: rooted where the Thirst left them, and
# huddled rather than standing. free() ends it.
var captive := false
# Who this one is, for the Thirst: {name, age, settlement, grievance}, minted at
# spawn by Roll.identity and empty for everybody else. Deliberately NOT read by
# display_name() or anything else the battle draws - the squad is not being
# asked to hesitate, and a name over a target would be a mechanic. THE ROLL
# reads it afterwards, where it cannot change a decision already made.
var identity: Dictionary = {}
# Morale, and the only meter the Thirst has that the squad does not.
#
# The literal is deliberate and is NOT Rules.MORALE_MAX, however much it wants
# to be: Rules names Unit in every one of its signatures, so reaching back the
# other way would make the two mutually dependent and put the resolution of
# that cycle at the mercy of compile order - in a project whose test harnesses
# already run scripts before the autoloads exist. Rules still owns the number.
# tools/test_rules.gd asserts these two agree, so the duplication cannot drift.
var morale := 100
# Hands up. Stops fighting, stops being fired on by the AI, and stops counting
# as a combatant - so a map cleared of everyone still standing is cleared.
var surrendered := false
# Broken with nobody to give up to: heading for the nearest map edge. Reaching
# it is an ESCAPE rather than a kill, and resolves the contact either way.
var routing := false
# Something cost this unit morale since its last activation. What it buys is
# the difference between a lull and a pause for breath: recovery is only given
# back to a fighter nothing happened to, so the squad cannot shoot a man to the
# edge of breaking and then have him steady himself on his own turn.
var morale_pressed := false
# A civilian who is not an objective: present, in the way, and killable. The
# prisoners in the pens are the other kind - huddled where they were left,
# waiting to be reached, and protected by every rule that can protect them.
# A bystander gets none of that. Nobody sent the squad to fetch him and nobody
# will notice if he is still standing at the end except THE ROLL.
var bystander := false
var _body_tween: Tween = null
var _marker_tween: Tween = null

@onready var sprite: Sprite2D = $Sprite


func _ready() -> void:
	_vis_rng.randomize()
	sprite.scale = sprite_scale
	sprite.offset = sprite_offset
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func setup(p_kind: Kind, p_cell: Vector2i) -> void:
	kind = p_kind
	# Civilians count as yours: they walk out with the squad, and the Thirst
	# never shoots at them (is_combatant keeps them off the AI's target list).
	team = TEAM_SCOUT if kind == Kind.SCOUT or kind == Kind.TEAM_LEAD \
			or kind == Kind.MACHINEGUNNER or kind == Kind.HERO \
			or kind == Kind.CIVILIAN \
			else TEAM_GOBLIN
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
		Kind.HERO:
			# Rodar Akai: the same designated-marksman job as the lead, done by
			# a veteran - faster on his feet, steadier over the sights, and one
			# more round in the magazine. Still semi-automatic only; the rifle
			# did not change, the hands holding it did.
			max_hp = 10
			move_range = 5
			attack_range = 6
			damage = 4
			accuracy = 95
			mag_size = 3
			frames = RODAR_FRAMES
			aim_frames = RODAR_AIM_FRAMES
			walk_frames = RODAR_WALK_FRAMES
			idle_frames = RODAR_IDLE_FRAMES
			raise_frames = RODAR_RAISE_FRAMES
			aim_idle_frames = RODAR_AIM_IDLE_FRAMES
			death_frames = RODAR_DEATH_FRAMES
			dead_frames = RODAR_DEAD_FRAMES
			idle_alt_frames = RODAR_IDLE_ALT_FRAMES
			hurt_frames = RODAR_HURT_FRAMES
			reload_frames = RODAR_RELOAD_FRAMES
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
			# The Thirst's designated marksman. One round in the rifle and the
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
			# Pressed last week and handed a bad sidearm: no armour, no
			# training, and a revolver somebody else had already worn out.
			# Two HP means a single carbine round puts him down - the
			# fiction stated in numbers, and the fiction is equipment.
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
		Kind.CIVILIAN:
			# Carries nothing and shoots nothing. Starts huddled where the
			# Thirst left them; release() puts them on their feet.
			max_hp = 4
			move_range = 4
			attack_range = 0
			damage = 0
			accuracy = 0
			captive = true
			frames = CIVILIAN_COWER_FRAMES
			aim_frames = CIVILIAN_COWER_FRAMES
			walk_frames = CIVILIAN_WALK_FRAMES
			idle_frames = CIVILIAN_COWER_IDLE
			# Every set has to be 8 entries long even where it will never play:
			# _current_cycle() indexes by facing sector without checking.
			raise_frames = CIVILIAN_COWER_IDLE
			aim_idle_frames = CIVILIAN_COWER_IDLE
			death_frames = CIVILIAN_DEATH_FRAMES
			dead_frames = CIVILIAN_DEAD_FRAMES
			idle_alt_frames = CIVILIAN_COWER_IDLE
			hurt_frames = CIVILIAN_COWER_IDLE
			reload_frames = CIVILIAN_COWER_IDLE
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
	var spec: Dictionary = SPRITE_SPECS.get(kind, SPRITE_SPECS.DEFAULT)
	sprite_scale = spec.scale
	sprite_offset = spec.offset
	if sprite != null:  # setup() can run before _ready() outside a live tree
		sprite.scale = sprite_scale
		sprite.offset = sprite_offset
	# Face the enemy side at the start of the battle.
	set_facing(Vector2(1, 0.5) if team == TEAM_SCOUT else Vector2(-1, 0.5))
	hp = max_hp
	ammo = mag_size
	# Desync idle cycles so units don't all breathe in lockstep.
	anim_time = float((p_cell.x * 7 + p_cell.y * 13) % 9) / IDLE_FPS


## Stamp a campaign soldier onto a freshly-setup unit: name, rank, perks, and
## the stats those have earned. MUST run after setup(), which assigns every
## stat from scratch - and note setup() derives hp and ammo from max_hp and
## mag_size at its tail, so anything that moves those has to re-derive them or
## a promoted soldier deploys already wounded.
func apply_progression(soldier: Dictionary) -> void:
	soldier_id = int(soldier.id)
	surname = str(soldier.surname)
	rank = int(soldier.rank)
	perks = (soldier.perks as Array).duplicate()
	accuracy = mini(accuracy + rank * Game.ACCURACY_PER_RANK, Game.ACCURACY_CAP)
	max_hp += rank * Game.HP_PER_RANK
	if has_perk("sprinter"):
		move_range += 1
	if has_perk("sentinel"):
		# A wider overwatch arc: 225 degrees against the base 135. (Half-width
		# 2 sectors is 225, not the 180 the blurb used to promise - see
		# ANALYSIS.md; the docs now say "wider" and mean it.)
		arc_half = 2
	if has_perk("ranger"):
		move_range += 1
		attack_range += 1
	if has_perk("iron_will"):
		max_hp += 2
	if has_perk("pack_mule"):
		mag_size += 2
	if has_perk("deep_pockets"):
		mag_size += 2
	# The re-derive tail: setup() already set hp and ammo, so any perk above
	# that moves max_hp or mag_size has to be re-derived here or a promoted
	# soldier deploys wounded or short-loaded.
	hp = max_hp
	ammo = mag_size
	queue_redraw()


func has_perk(perk: String) -> bool:
	return perks.has(perk)


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
		Kind.HERO:
			offsets = RODAR_MUZZLE_OFFSETS
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
## from the hip, so he keeps burst after moving - and Snap Burst teaches a
## scout the same trick.
func burst_requires_still() -> bool:
	return kind == Kind.SCOUT and not has_perk("snap_burst")


func can_full_auto() -> bool:
	return kind == Kind.MACHINEGUNNER


## Suppressive fire is the gunner's ability alone - nobody else carries the
## volume of ammunition to keep heads down.
func can_suppress() -> bool:
	return kind == Kind.MACHINEGUNNER


## The gunner's job on overwatch is covering ground the rest of the squad has
## to cross, not holding a doorway. His watch reaches further than he can
## normally shoot, and he answers with a pair of rounds rather than one - which
## is the difference between a sentry and covering fire.
func overwatch_range() -> int:
	return attack_range + (OVERWATCH_RANGE_BONUS if kind == Kind.MACHINEGUNNER else 0)


func overwatch_rounds() -> int:
	# A Bipod steadies the reaction for one more round on top of whatever the
	# weapon answers with - three for the gunner it is offered to.
	var rounds := OVERWATCH_VOLLEY if kind == Kind.MACHINEGUNNER else 1
	return rounds + (1 if has_perk("bipod") else 0)


## How wide a diamond this unit's suppressing fire pins. Wide Sweep buys the
## third ring out.
func suppress_radius() -> int:
	return SUPPRESS_RADIUS + (1 if has_perk("wide_sweep") else 0)


## Someone who fights. A prisoner is on your side and walks out with you, but
## is never shot at, never shoots, and never counts toward a squad wipe.
func is_combatant() -> bool:
	return kind != Kind.CIVILIAN and not surrendered


## A civilian is anyone who never carried a weapon: the prisoners in the pens,
## and the bystanders who were only ever standing there. Distinct from
## is_combatant(), which a fighter with his hands up also fails.
func is_civilian() -> bool:
	return kind == Kind.CIVILIAN


## Who a blast goes around. Exactly one group: the prisoners the squad was sent
## to fetch. Being able to frag the person you came to rescue turns a rescue
## into a chore, and the Thirst wants them alive anyway.
##
## Everybody else in the footprint takes it - including a fighter with his hands
## up, and including a bystander who was only ever standing there. Both of those
## are the point. A grenade does not ask, which is why THE ROLL does.
func is_blast_immune() -> bool:
	return captive or (is_civilian() and not bystander)


## Has stopped fighting and is trying to leave. Still a legal target - the game
## will let you - which is exactly why THE ROLL records that you did.
func has_stopped() -> bool:
	return surrendered or routing


## Hands up. The weapon comes down, the watch is dropped, and the unit is done
## for good rather than for the turn: nothing in the AI will pick it up again,
## and is_combatant() now answers false, so a map with nobody left fighting on
## it counts as cleared whether or not this one is still standing.
##
## Deliberately does NOT make the unit untargetable. The player can still shoot
## him. That is the entire point of the prompt existing - a choice with no
## wrong option is not a choice - and THE ROLL is where the answer is kept.
func surrender() -> void:
	if surrendered or not is_alive():
		return
	surrendered = true
	routing = false
	set_overwatch(false)
	lower_rifle()
	set_done(true)
	_spawn_float_text("HANDS UP", SURRENDER_COLOR, 18)
	queue_redraw()


## Broken with nobody to give up to. Runs for the nearest edge; Battle walks it.
func begin_rout() -> void:
	if routing or surrendered or not is_alive():
		return
	routing = true
	set_overwatch(false)
	lower_rifle()
	_spawn_float_text("BREAKS", ROUT_COLOR, 18)
	queue_redraw()


## Reached. They get up off the floor and can walk out with the squad.
## Not named free() - that is Object's, and shadowing it deletes the node.
func release() -> void:
	if not captive:
		return
	captive = false
	frames = CIVILIAN_FRAMES
	aim_frames = CIVILIAN_FRAMES
	idle_frames = CIVILIAN_IDLE_FRAMES
	aim_idle_frames = CIVILIAN_IDLE_FRAMES
	idle_alt_frames = CIVILIAN_IDLE_FRAMES
	raise_frames = CIVILIAN_IDLE_FRAMES
	hurt_frames = CIVILIAN_IDLE_FRAMES
	reload_frames = CIVILIAN_IDLE_FRAMES
	_set_anim(Anim.IDLE)
	queue_redraw()


## Being pinned means exactly that, and so does being tied up.
func can_move_freely() -> bool:
	return can_move() and not captive


## The role a kind fills, with no reference to who is filling it.
static func kind_role_name(p_kind: Kind) -> String:
	match p_kind:
		Kind.TEAM_LEAD:
			return "Kestrel Team Lead"
		Kind.HERO:
			return "Rodar Akai, Kestrel Squad"
		Kind.MACHINEGUNNER:
			return "Kestrel Machinegunner"
		Kind.GOBLIN:
			return "Thirst Well-hand"
		Kind.GOBLIN_SMG:
			return "Thirst Runner"
		Kind.GOBLIN_SMG_ALT:
			return "Thirst Light Runner"
		Kind.GOBLIN_BOLT:
			return "Thirst Marksman"
		Kind.GOBLIN_REVOLVER:
			return "Pressed Conscript"
		Kind.CIVILIAN:
			return "Prisoner"
	return "Kestrel Rifleman"


## Named soldiers answer to their name; the Thirst stays anonymous until the
## after-action names them.
func display_name() -> String:
	if surname.is_empty():
		return kind_role_name(kind)
	return Game.soldier_label({"rank": rank, "surname": surname})


func role_name() -> String:
	return kind_role_name(kind)


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


## Pinned down by incoming fire: shoots worse, cannot set overwatch, and
## cannot leave the spot it is standing on. The default 2 survives the
## decrement at the start of the target's own next turn and actually costs
## them that turn; a Locked Belts gunner passes 3 to cost them two. A fresh
## shorter pin never trims a longer one already holding.
func suppress(turns := 2) -> void:
	suppression = maxi(suppression, turns)
	queue_redraw()


func is_suppressed() -> bool:
	return suppression > 0


## Being pinned means exactly that: heads down, nobody moves. This is what
## makes suppressing fire area denial rather than a worse way to shoot.
func can_move() -> bool:
	return not is_suppressed()


func has_ammo(rounds := 1) -> bool:
	return mag_size == 0 or ammo >= rounds


func spend_ammo() -> void:
	if mag_size > 0:
		ammo = maxi(ammo - 1, 0)
		queue_redraw()


func reload() -> void:
	ammo = mag_size
	queue_redraw()


## Patch up, clamped to max_hp. Never resurrects - a corpse stays one - and
## never shows a "+0" for a soldier already whole.
func heal(amount: int) -> void:
	if hp <= 0 or amount <= 0 or hp >= max_hp:
		return
	var gained := mini(amount, max_hp - hp)
	hp += gained
	_spawn_float_text("+%d" % gained, PIP_FULL, 24)
	queue_redraw()


## Steadied by the hero's Rally: any pin comes off and the next shots come
## easier. The bonus fades in this soldier's own start_turn.
func rally(bonus: int) -> void:
	suppression = 0
	rally_bonus = bonus
	queue_redraw()


## Dry and carrying a magazine, so it cannot shoot until it reloads. Units
## with unlimited ammo (mag_size 0) never need one.
func needs_reload() -> bool:
	return mag_size > 0 and ammo == 0


## Lean out around a corner and settle back. Same channel as recoil, so a
## peek shot's lean and its kick compose instead of fighting.
func lean(offset: Vector2) -> void:
	_body_shove(offset, 0.30, Tween.TRANS_QUAD)


## Hunker down behind cover, or stand back up. The sprite sinks a few pixels
## and the cover prop in front - drawn later by the y-sort - takes care of the
## rest, which is a convincing crouch for no new art at all.
func set_in_cover(level: int) -> void:
	if cover_level == level:
		return
	cover_level = level
	sprite.offset = sprite_offset + Vector2(0, CROUCH_SINK if level > 0 else 0.0)
	queue_redraw()


## Kick the sprite backward off a shot and settle it. sprite.position is
## otherwise unused (the SPRITE_SPECS anchor lives in sprite.offset), so body
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
	if amount >= hp and has_perk("untouchable") and not untouchable_used:
		# Untouchable: the first killing blow of the battle leaves him at
		# exactly 1 HP. Every damage path routes through here - rounds,
		# reactions, blasts, drums - so the guarantee holds everywhere. The
		# second lethal hit is the real one.
		untouchable_used = true
		amount = hp - 1
		_spawn_float_text("HELD ON", RANK_COLOR, 20)
	if amount > 0:
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
		wounded.emit(self)


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
			corpse_shadow_color if dead else shadow_color)
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
	if get_parent() == null:
		return  # a unit outside a battle (tests, tools) has nowhere to float it
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
	if value and overwatching:
		# Spending the activation breaks a watch carried over by Protective
		# Fire - only that perk can produce "overwatching and not yet done".
		# The normal overwatch order is unharmed: _commit_aim calls
		# set_done(true) first and re-arms with set_overwatch(true) right after.
		set_overwatch(false)
	modulate = DONE_TINT if value else Color(1, 1, 1, modulate.a)
	queue_redraw()


func start_turn() -> void:
	moved = false
	acted = false
	suppression = maxi(suppression - 1, 0)
	rally_bonus = 0  # Rally's steadying lasts until the soldier's own turn
	modulate = Color.WHITE
	if overwatching and not has_perk("protective_fire"):
		set_overwatch(false)  # unfired overwatch expires...
		lower_rifle()         # ...and the rifle comes down
	# Protective Fire: the rifle stays up and the watch stands. Taking any
	# order breaks it - set_done(true) covers every action, and do_move
	# breaks it for the walk itself.
	queue_redraw()


func _draw() -> void:
	# Drawn first (and before the corpse guard) so every body keeps its
	# contact shadow. _draw renders behind child nodes, so the sprite's
	# feet always sit on top of it.
	_draw_shadow()
	if hp <= 0:
		return  # corpses carry no pips, rings, or markers
	if not show_combat_hud:
		return  # walking around camp: a soldier, not a game piece
	# Who has stopped fighting, readable without selecting anything. A ring at
	# the feet in the same two colours the float text used, because the player
	# needs this at a glance while deciding where to point five rifles - and
	# because the game will happily let him shoot either of them.
	if has_stopped():
		var stop_col := SURRENDER_COLOR if surrendered else ROUT_COLOR
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
		draw_arc(Vector2.ZERO, 32.0, 0.0, TAU, 32,
				Color(stop_col, 0.85), 2.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
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
	if rank > 0:
		# Rank chevrons stacked just left of the HP row. Everything else drawn
		# up here (the overwatch diamond, the suppression and acting chevrons)
		# is centred on x = 0, so the flank is always clear.
		var rx := start_x - RANK_GAP
		for i in rank:
			var ry := PIP_Y + PIP_SIZE.y * 0.5 - i * RANK_STEP
			draw_colored_polygon(PackedVector2Array([
				Vector2(rx, ry), Vector2(rx - RANK_W, ry - RANK_H),
				Vector2(rx - RANK_W, ry - RANK_H + RANK_T), Vector2(rx, ry + RANK_T),
			]), RANK_COLOR)
	if cover_level > 0:
		# Shield bars on the right of the HP row, mirroring the rank chevrons
		# on the left: one bar behind a scrap pile, two behind a wall.
		var cx := start_x + total_width + RANK_GAP
		var col := COVER_FULL_COLOR if cover_level > 1 else COVER_HALF_COLOR
		for i in cover_level:
			draw_rect(Rect2(cx + i * 4.0, PIP_Y - 1.0, 2.0, PIP_SIZE.y + 2.0), col)
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
