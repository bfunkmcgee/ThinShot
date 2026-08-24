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
	# SCOUT is Josen Marr and the line riflemen; MACHINEGUNNER is Brukk Meshan.
	# TEAM_LEAD is legacy - Rodar Akai took the lead slot and it is never
	# recruited again - but it stays reachable, and so does the art behind all
	# three. Scout, Scout_TeamLead and Scout_MachineGunner are the GENERIC
	# Kestrel troops: the bodies for cut scenes, for making a garrison feel
	# inhabited, and for missions where another squad works alongside this one.
	# They are not spare copies of the named soldiers' sprites and should not be
	# tidied away as such.
	SCOUT, TEAM_LEAD, MACHINEGUNNER,
	GOBLIN, GOBLIN_SMG, GOBLIN_SMG_ALT, GOBLIN_REVOLVER, GOBLIN_BOLT,
	# Not a soldier. Carries no weapon, is never shot at, and until somebody
	# reaches them, does not move either.
	CIVILIAN,
	# Rodar Akai, the hero of the scouts. Appended, and everything after it was
	# appended too: saves store the raw ordinal, so inserting ANYWHERE above
	# this line would quietly turn every saved soldier into somebody else.
	HERO,
	# Phase 3, and the same rule applies to these - append below, never insert.
	# The five specialist Kestrels. Each takes a rifle slot, so they are
	# alternatives to a rifleman rather than additions to the squad, and each
	# has its own entry in Game.CLASS_PERK_RANKS.
	#
	# Each also has its own 8-direction set under assets/sprites/Kestrel_<Role>/
	# (ASSETS.md tier 4 #20). The rules are still what makes them different; the
	# art is what makes that legible across a board.
	GRENADIER,
	MARKSMAN,
	BREACHER,
	MEDIC,
	TECHNICIAN,
	# The Thirst's belt-fed gunner. First fielded in the second operation -
	# OPERATION LONG SURVEY is where the enemy stops being a militia with
	# scavenged rifles and starts bringing crew weapons.
	GOBLIN_MG,
	# The brute. Deliberately breaks the goblin scale rules - ~1.65x a
	# rifleman with a scrap-iron maul - and the only unit on an 80x72 canvas
	# (UNIT_ASSET_SPEC.md section 6's inversion). Appears where the campaign
	# is at its most desperate: the survey camp and the cold well.
	GOBLIN_BRUTE,
}

## The kinds that can fill one of a mission's three rifle slots. Rodar owns the
## lead slot and the machinegunner owns the gun; everybody else competes for
## these, which is what the garrison's deployment screen is choosing between.
const RIFLE_SLOT_KINDS: Array[Kind] = [
	Kind.SCOUT, Kind.GRENADIER, Kind.MARKSMAN,
	Kind.BREACHER, Kind.MEDIC, Kind.TECHNICIAN,
]

const LEAD_ROOT := "res://assets/sprites/Scout_TeamLead"
# Brukk Meshan's set. The folder is called Hero_MachineGunner for historical
# reasons - it is the PixelLab "Hero_bandana" group - and that name is a trap
# worth reading twice: Kind.HERO is Rodar Akai, whose art is Rodar_Akai/. This
# is Kind.MACHINEGUNNER, ordinal 2.
#
# Unlike the Scout set it replaces, this one ships on the canonical layout
# (UNIT_ASSET_SPEC.md §4): the root is the UNIT folder, the base state is the
# folder beneath it that repeats the name, and ReadyToFire_Stance / Dead_stance
# are siblings of that rather than children. So the root does not carry the
# doubled segment the old one did.
const MG_ROOT := "res://assets/sprites/Hero_MachineGunner"
## Where the machinegunner's own rotations and animations live, one level in.
const MG_BASE := MG_ROOT + "/Hero_MachineGunner"
const SMG_ROOT := "res://assets/sprites/Goblin_SMG"
const REV_ROOT := "res://assets/sprites/Goblin_revolver"
const SMGA_ROOT := "res://assets/sprites/Goblin_SMG_alt"
const BOLT_ROOT := "res://assets/sprites/Goblin_BoltRifle"
const CIVILIAN_ROOT := "res://assets/sprites/Civilian"
const RODAR_ROOT := "res://assets/sprites/Rodar_Akai"
const SCOUT_ROOT := "res://assets/sprites/Scout"
# The five specialist Kestrels, each a full unit of its own.
const GRENADIER_ROOT := "res://assets/sprites/Kestrel_Grenadier"
const MARKSMAN_ROOT := "res://assets/sprites/Kestrel_Marksman"
const BREACHER_ROOT := "res://assets/sprites/Kestrel_Breacher"
const MEDIC_ROOT := "res://assets/sprites/Kestrel_Medic"
const TECHNICIAN_ROOT := "res://assets/sprites/Kestrel_Technician"
# The Thirst's belt-fed gunner, on the canonical layout like the Kestrels.
const GMG_ROOT := "res://assets/sprites/Goblin_MG"
const BRUTE_ROOT := "res://assets/sprites/Goblin_Brute"

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

# Machinegunner - Brukk Meshan. Folder names are taken from disk rather than
# from the set this replaced: the canonical layout spells the corpse stance
# `Dead_stance` with a small s and the aim-idle `standing-readyToFire_idle`
# with a hyphen, where the old Scout set used `Dead_Stance` and
# `Standing_ReadyToFire_idle`. Getting either wrong loads nothing and says
# nothing - _load_dir_frames returns an empty array for a path that is not
# there - and Windows resolves the wrong casing anyway, so it would only
# surface in an exported build, where res:// paths are case-sensitive.
static var MG_FRAMES: Array[Texture2D] = _load_rotation_frames(MG_BASE + "/rotations")
static var MG_AIM_FRAMES: Array[Texture2D] = _load_rotation_frames(
		MG_ROOT + "/ReadyToFire_Stance/rotations")
static var MG_DEAD_FRAMES: Array[Texture2D] = _load_rotation_frames(
		MG_ROOT + "/Dead_stance/rotations")
static var MG_IDLE_FRAMES: Array = _load_dir_frames(
		MG_BASE + "/animations/standing_idle")
static var MG_IDLE_ALT_FRAMES: Array = _load_dir_frames(
		MG_BASE + "/animations/standing_idle_alt")
static var MG_WALK_FRAMES: Array = _load_dir_frames(
		MG_BASE + "/animations/standing_idle_walk")
static var MG_RAISE_FRAMES: Array = _load_dir_frames(
		MG_BASE + "/animations/standing_idle_to_readyToFire")
static var MG_AIM_IDLE_FRAMES: Array = _load_dir_frames(
		MG_ROOT + "/ReadyToFire_Stance/animations/standing-readyToFire_idle")
static var MG_DEATH_FRAMES: Array = _load_dir_frames(
		MG_BASE + "/animations/standing_idle_to_dead")
static var MG_HURT_FRAMES: Array = _load_dir_frames(
		MG_BASE + "/animations/standing_idle_damage")
static var MG_RELOAD_FRAMES: Array = _load_dir_frames(
		MG_BASE + "/animations/standing_idle_reload")

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

# What suppressive fire adds over the gun's aimed reach. Suppression is area
# denial that does no damage at all, so the thing it must never require is
# walking into the beaten zone to deliver it - a machinegun that has to close
# to rifle distance before it can pin anybody is being used as a bad rifle.
# Matches OVERWATCH_RANGE_BONUS on purpose: the gun covers the same ground
# whether it is watching it or firing into it.
const SUPPRESS_RANGE_BONUS := 2

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
# Belt-fed weapon held low across the body. South is hand-corrected off the
# scan, which lands on boots for that pose.
const GUNNER_MUZZLE_OFFSETS: Array[Vector2] = [
	Vector2(34, -36),  # east
	Vector2(34, -32),  # south-east (band scan)
	Vector2(-16, -20),  # south (hand-set: the scan lands on a boot)
	Vector2(-26, -26),  # south-west (band scan)
	Vector2(-40, -36),  # west
	Vector2(-36, -46),  # north-west (band scan)
	Vector2(-8, -62),  # north
	Vector2(32, -46),  # north-east (band scan)
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
# The belt-fed gun at the shoulder. South and north are drawn genuinely
# foreshortened at/away from the camera (the muzzle is the dark ring at his
# chest), so those two are hand-set at the ring rather than scanned.
const GMG_MUZZLE_OFFSETS: Array[Vector2] = [
	Vector2(34, -34),   # east
	Vector2(36, -36),   # south-east (band scan)
	Vector2(-4, -24),   # south (hand-set: the muzzle ring at the chest - the scan lands on boots)
	Vector2(-34, -36),  # south-west (band scan)
	Vector2(-32, -34),  # west
	Vector2(-26, -42),  # north-west (band scan)
	Vector2(-4, -58),   # north (the flash leaves over his shoulder - the gun is hidden behind the body)
	Vector2(30, -28),   # north-east (band scan)
]
# The brute's "muzzle" is the maul head raised overhead - the impact flash
# leaves the hammer, not a barrel. Measured as the centroid of the top ten
# figure rows of each 80x72 aim sheet (the hammer mass), mapped through his
# own SPRITE_SPECS: (px - (40, 36) + (0, -27)) * 2. measure_muzzle.gd is not
# used here - it assumes a square canvas and would sit 4px low.
const BRUTE_MUZZLE_OFFSETS: Array[Vector2] = [
	Vector2(0, -98),    # east
	Vector2(0, -92),    # south-east
	Vector2(-10, -92),  # south
	Vector2(-28, -102), # south-west
	Vector2(6, -102),   # west
	Vector2(28, -98),   # north-west
	Vector2(8, -90),    # north
	Vector2(2, -90),    # north-east
]

# The five specialist Kestrels. Measured by tools/measure_muzzle.gd, which for
# these units leans on its band scan far more than the shipped set did, for two
# reasons worth knowing before touching these numbers:
#
#  - The plain scan takes the opaque pixel furthest along the facing, and on a
#    tall silhouette that can be the crown of the head. Dava's northern
#    diagonals scanned to her hair, twelve texels above the gun.
#  - Pixel Lab drew the south and north aim poses with the weapon levelled off
#    to one flank instead of foreshortened at or away from the camera
#    (validate_unit_sprites.py check [3] flags all five). The muzzle really is
#    out on that flank, so the offset follows the art rather than the ideal
#    pose - a flash has to come out of the barrel the player can see. Halvik
#    and Fen keep a centred north because theirs simply is not drawn there.
# Essa's tactical rifle with an underbarrel launcher.
const GRENADIER_MUZZLE_OFFSETS: Array[Vector2] = [
	Vector2(38, -38),  # east
	Vector2(34, -26),  # south-east (band scan)
	Vector2(26, -30),  # south (band scan: this pose is drawn levelled, not foreshortened)
	Vector2(-38, -26),  # south-west (band scan)
	Vector2(-44, -38),  # west
	Vector2(-40, -40),  # north-west (band scan)
	Vector2(-32, -48),  # north (band scan: this pose is drawn levelled, not foreshortened)
	Vector2(38, -40),  # north-east (band scan)
]

# Sillae's long scoped rifle - the longest reach of the five, which is why
# east, west and both northern diagonals sit level at -42.
const MARKSMAN_MUZZLE_OFFSETS: Array[Vector2] = [
	Vector2(38, -42),  # east
	Vector2(38, -24),  # south-east (band scan)
	Vector2(36, -36),  # south (band scan: this pose is drawn levelled, not foreshortened)
	Vector2(-38, -26),  # south-west (band scan)
	Vector2(-38, -42),  # west
	Vector2(-38, -42),  # north-west
	Vector2(-36, -48),  # north (band scan: this pose is drawn levelled, not foreshortened)
	Vector2(38, -42),  # north-east
]

# Halvik's shotgun, short and held low across the carrier.
const BREACHER_MUZZLE_OFFSETS: Array[Vector2] = [
	Vector2(34, -40),  # east
	Vector2(34, -32),  # south-east (band scan)
	Vector2(28, -40),  # south (band scan: this pose is drawn levelled, not foreshortened)
	Vector2(-40, -32),  # south-west (band scan)
	Vector2(-40, -38),  # west
	Vector2(-36, -42),  # north-west (band scan)
	Vector2(-8, -62),  # north
	Vector2(32, -42),  # north-east (band scan)
]

# Dava's submachine gun, held tight to the chest beside the satchel.
const MEDIC_MUZZLE_OFFSETS: Array[Vector2] = [
	Vector2(32, -38),  # east
	Vector2(30, -36),  # south-east (band scan)
	Vector2(26, -38),  # south (band scan: this pose is drawn levelled, not foreshortened)
	Vector2(-32, -36),  # south-west (band scan)
	Vector2(-32, -38),  # west
	Vector2(-28, -40),  # north-west (band scan)
	Vector2(-26, -36),  # north (band scan: this pose is drawn levelled, not foreshortened)
	Vector2(26, -40),  # north-east (band scan)
]

# Fen's carbine. The radio pack rides high on his back, which is why the
# northern diagonals read further out than the weapon alone.
const TECHNICIAN_MUZZLE_OFFSETS: Array[Vector2] = [
	Vector2(34, -38),  # east
	Vector2(32, -28),  # south-east (band scan)
	Vector2(24, -36),  # south (band scan: this pose is drawn levelled, not foreshortened)
	Vector2(-34, -26),  # south-west (band scan)
	Vector2(-38, -38),  # west
	Vector2(-30, -46),  # north-west (band scan)
	Vector2(-8, -60),  # north
	Vector2(28, -46),  # north-east (band scan)
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
	# 80x72 sheets with feet on y=63: 27px below the canvas centre, so the
	# offset is -27 where the family's is -15. Same screen anchor rule.
	Kind.GOBLIN_BRUTE: {"scale": Vector2(2, 2), "offset": Vector2(0, -27)},
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
# The notebook's tally, worn on the man himself: bone-white notches for a
# fighter the squad already settled once and who came back anyway.
const SURVIVAL_COLOR := Color(0.92, 0.88, 0.78, 0.95)

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
# career_level 0 means "not a career soldier" - the Thirst, bystanders, the
# riflemen lent to a detachment. Roster soldiers are always >= 1.
var soldier_id := 0
var surname := ""
var career_level := 0
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
## Where this unit STARTED, and the most a quiet turn can give back. Without it
## Rules.morale_recovered climbs everyone to MORALE_MAX and the per-kind table
## above becomes a three-turn opening condition rather than a class trait.
var morale_ceiling := 100
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
# Which body this was in the mission's own spawn order. Battle mints it; the
# roll and the notebook carry it, because a name is not a key - 280 spawns
# produce 228 distinct names, so two men called the same thing in one mission is
# an ordinary Tuesday. (level, ordinal) is the only pair that is actually unique.
var spawn_ordinal := -1
# This fighter ran from an earlier mission and came back. Steadier for it
# (Rules.returner_morale), unmoved by the fallen (Rules.shaken_by_the_fallen),
# and carrying the name he had when he ran rather than a fresh one.
var returned := false
## The standing record in Game.adversaries this body belongs to, 0 for somebody
## the campaign has never met. Stamped on a returner at spawn and written back
## onto the roll if he walks away again, which is what lets one person
## accumulate a history instead of being a fresh stranger every mission.
var adversary_id := 0
## How many times he has already walked away from this squad. Feeds
## Rules.survive_chance - the ones who keep getting up are better at it.
var survivals := 0
## He came back to raid rather than to hold ground: take his shot and break
## contact on his own terms. Set on some returners at spawn (Rules.RAID_CHANCE).
var raider := false
## Shots he still means to take before leaving. Counted down by the AI's fire.
var raid_shots_left := 0
## Set the moment a raider turns for the rim having done what he came for. It is
## the only thing separating that from a man whose nerve went, and the two must
## not be confused: `routing` is true for both, but firing on somebody who chose
## to withdraw after shooting at you is a combat kill and costs nothing, while
## firing on a broken man costs Standing. See Battle._record_on_roll.
var raid_withdrawal := false
## The warband this body belongs to, 0 for nobody. A leader carries his own id
## here, so `warband == leader.adversary_id` identifies the whole group and one
## comparison answers "is this my leader".
var warband := 0
## True only on the man who gathered them.
var warband_leader := false
## Somebody who LIVES at a bounty location. A goblin by kind and by sprite, and
## not a fighter by any other measure: he never takes a turn, he is not a
## combatant, and shooting him is scored the way shooting a civilian is. What he
## is for is that he knows where the posted man sleeps.
var resident := false
## He has already been asked, and either talked or refused. Both end the
## conversation - a settlement that could be asked twice would make GUILE a
## formality you grind rather than a stat.
var questioned := false
## The man the bounty is posted on.
var bounty_target := false
## How hard the blow that put him down landed, kept because Rules.decisive_blow
## reads it after the fact. A hit that would have killed him from full health
## leaves nobody to find; a carbine finishing a wounded man does not.
var last_blow := 0
# Cut short by a reaction: a round landed while this unit was crossing a watched
# lane. The advance stopped on the cell it was hit on and the activation stopped
# with it - see Rules.reaction_interrupts. Cleared by start_turn(), alongside
# moved and acted, because it is the same kind of fact as those two.
var interrupted := false
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
			or kind == Kind.CIVILIAN or RIFLE_SLOT_KINDS.has(kind) \
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
		# --- the five specialist Kestrels -------------------------------------
		#
		# Every one of them is a SIDEGRADE of the rifleman, because every one of
		# them is standing in a rifleman's slot. The baseline is 8 HP, move 5,
		# range 4, damage 2, accuracy 90, three rounds; each of these trades
		# some of that for the thing it is for, and none of them is simply
		# better. Choosing at the garrison has to be a decision rather than a
		# ranking, or the deployment screen is a formality with checkboxes.
		#
		# Each has its own 8-direction set: three rotation stances and seven
		# animation sets, generated against the shipped rifleman as the style
		# anchor so they stand in the same world.
		Kind.GRENADIER:
			# Essa Vane. Carries the squad's ordnance, which is heavy: a tile
			# slower and a little worse over the sights, for a frag the squad
			# would not otherwise have (the grenadier perk, which she starts
			# with) and the pockets to work with it.
			#
			# She also LAUNCHES it rather than throwing it - five tiles against
			# everyone else's four, frag and smoke alike, off the launcher drawn
			# under her barrel. Five is the Thirst Marksman's reach, so it is
			# the last tile from which she still has to stand on his line; the
			# reasoning is written out in full at Rules.throw_range(), which is
			# also where the number lives. It is not a field here because it is
			# a rule about ordnance rather than a property of her body, and
			# because this file cannot name Rules.
			max_hp = 8
			move_range = 4
			attack_range = 4
			damage = 2
			accuracy = 86
			mag_size = 3
			frames = GRENADIER_FRAMES
			aim_frames = GRENADIER_AIM_FRAMES
			walk_frames = GRENADIER_WALK_FRAMES
			idle_frames = GRENADIER_IDLE_FRAMES
			raise_frames = GRENADIER_RAISE_FRAMES
			aim_idle_frames = GRENADIER_AIM_IDLE_FRAMES
			death_frames = GRENADIER_DEATH_FRAMES
			dead_frames = GRENADIER_DEAD_FRAMES
			hurt_frames = GRENADIER_HURT_FRAMES
			reload_frames = GRENADIER_RELOAD_FRAMES
			# Assigned explicitly: the field DEFAULTS to the rifleman's, so
			# leaving it alone would have every Kestrel flashing somebody
			# else's animation one idle cycle in seven.
			idle_alt_frames = GRENADIER_IDLE_ALT_FRAMES
		Kind.MARKSMAN:
			# Sillae Vekh. Rodar's job at a Kestrel's pay grade: the reach and
			# the damage, none of the armour, and two rounds rather than three.
			# She is the answer to the Thirst Marksman when Rodar is elsewhere,
			# and she is the one who reads the district back to you.
			max_hp = 6
			move_range = 4
			attack_range = 6
			damage = 4
			accuracy = 88
			mag_size = 2
			frames = MARKSMAN_FRAMES
			aim_frames = MARKSMAN_AIM_FRAMES
			walk_frames = MARKSMAN_WALK_FRAMES
			idle_frames = MARKSMAN_IDLE_FRAMES
			raise_frames = MARKSMAN_RAISE_FRAMES
			aim_idle_frames = MARKSMAN_AIM_IDLE_FRAMES
			death_frames = MARKSMAN_DEATH_FRAMES
			dead_frames = MARKSMAN_DEAD_FRAMES
			hurt_frames = MARKSMAN_HURT_FRAMES
			reload_frames = MARKSMAN_RELOAD_FRAMES
			# Assigned explicitly: the field DEFAULTS to the rifleman's, so
			# leaving it alone would have every Kestrel flashing somebody
			# else's animation one idle cycle in seven.
			idle_alt_frames = MARKSMAN_IDLE_ALT_FRAMES
		Kind.BREACHER:
			# Halvik Dunn. Built to go through a gate first and be standing
			# afterwards: the deepest HP pool in the squad, bought with reach.
			# At three tiles he has to close, which is the whole shape of him.
			max_hp = 11
			move_range = 4
			attack_range = 3
			damage = 2
			accuracy = 84
			mag_size = 3
			frames = BREACHER_FRAMES
			aim_frames = BREACHER_AIM_FRAMES
			walk_frames = BREACHER_WALK_FRAMES
			idle_frames = BREACHER_IDLE_FRAMES
			raise_frames = BREACHER_RAISE_FRAMES
			aim_idle_frames = BREACHER_AIM_IDLE_FRAMES
			death_frames = BREACHER_DEATH_FRAMES
			dead_frames = BREACHER_DEAD_FRAMES
			hurt_frames = BREACHER_HURT_FRAMES
			reload_frames = BREACHER_RELOAD_FRAMES
			# Assigned explicitly: the field DEFAULTS to the rifleman's, so
			# leaving it alone would have every Kestrel flashing somebody
			# else's animation one idle cycle in seven.
			idle_alt_frames = BREACHER_IDLE_ALT_FRAMES
		Kind.MEDIC:
			# Dava Ren. The notebook is hers. She keeps the squad standing
			# rather than putting anything down - the worst shot of the six and
			# the only one who arrives already knowing how to patch a wound.
			max_hp = 8
			move_range = 5
			attack_range = 4
			damage = 2
			accuracy = 82
			mag_size = 3
			frames = MEDIC_FRAMES
			aim_frames = MEDIC_AIM_FRAMES
			walk_frames = MEDIC_WALK_FRAMES
			idle_frames = MEDIC_IDLE_FRAMES
			raise_frames = MEDIC_RAISE_FRAMES
			aim_idle_frames = MEDIC_AIM_IDLE_FRAMES
			death_frames = MEDIC_DEATH_FRAMES
			dead_frames = MEDIC_DEAD_FRAMES
			hurt_frames = MEDIC_HURT_FRAMES
			reload_frames = MEDIC_RELOAD_FRAMES
			# Assigned explicitly: the field DEFAULTS to the rifleman's, so
			# leaving it alone would have every Kestrel flashing somebody
			# else's animation one idle cycle in seven.
			idle_alt_frames = MEDIC_IDLE_ALT_FRAMES
		Kind.TECHNICIAN:
			# Fen Ost. Reads ground rather than holds it: the widest watch in
			# the squad for its own turn, thin in a firefight, and the man who
			# will be taking the readings when the campaign stops being about
			# water.
			max_hp = 7
			move_range = 5
			attack_range = 4
			damage = 2
			accuracy = 88
			mag_size = 3
			frames = TECHNICIAN_FRAMES
			aim_frames = TECHNICIAN_AIM_FRAMES
			walk_frames = TECHNICIAN_WALK_FRAMES
			idle_frames = TECHNICIAN_IDLE_FRAMES
			raise_frames = TECHNICIAN_RAISE_FRAMES
			aim_idle_frames = TECHNICIAN_AIM_IDLE_FRAMES
			death_frames = TECHNICIAN_DEATH_FRAMES
			dead_frames = TECHNICIAN_DEAD_FRAMES
			hurt_frames = TECHNICIAN_HURT_FRAMES
			reload_frames = TECHNICIAN_RELOAD_FRAMES
			# Assigned explicitly: the field DEFAULTS to the rifleman's, so
			# leaving it alone would have every Kestrel flashing somebody
			# else's animation one idle cycle in seven.
			idle_alt_frames = TECHNICIAN_IDLE_ALT_FRAMES
		Kind.MACHINEGUNNER:
			# Belt-fed support weapon: no single shot, a deep magazine, and
			# the volume of fire to pin a target. Slow to reposition.
			max_hp = 8
			move_range = 3
			attack_range = 5
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
			# Rules.starting_morale(), spelled here because this file cannot
			# name Rules - a raider, lighter in every sense than a well-hand.
			morale = 85
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
			# Rules.starting_morale(), spelled here because this file cannot
			# name Rules - stripped for speed, and nothing to stand behind.
			morale = 75
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
			# Rules.starting_morale(), spelled here because this file cannot
			# name Rules - pressed last week, no training, a worn-out sidearm.
			morale = 60
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
		Kind.GOBLIN_MG:
			# The Thirst's crew weapon: a belt-fed gun on a goblin who can
			# barely carry it. Long reach and a deep belt, but he sprays
			# rather than aims and repositions slower than anything else the
			# Thirst fields. Kill him before he settles, or stay out of his
			# lane. Morale is the default MAX on purpose - the gun goes to
			# somebody trusted, and he knows what he is holding.
			max_hp = 5
			move_range = 3
			attack_range = 5
			damage = 2
			accuracy = 55  # volume of fire, not marksmanship
			mag_size = 6
			frames = GMG_FRAMES
			aim_frames = GMG_AIM_FRAMES
			walk_frames = GMG_WALK_FRAMES
			idle_frames = GMG_IDLE_FRAMES
			raise_frames = GMG_RAISE_FRAMES
			aim_idle_frames = GMG_AIM_IDLE_FRAMES
			death_frames = GMG_DEATH_FRAMES
			dead_frames = GMG_DEAD_FRAMES
			idle_alt_frames = GMG_IDLE_ALT_FRAMES
			hurt_frames = GMG_HURT_FRAMES
			reload_frames = GMG_RELOAD_FRAMES
		Kind.GOBLIN_BRUTE:
			# A wall that walks. Reach of an arm's length and a lunge, damage
			# that ends what it touches, and enough body to absorb a squad's
			# whole turn. He does not aim, he arrives - kill him on the way
			# or give him the cell he wants. Default MAX morale: a brute has
			# never once considered leaving.
			max_hp = 10
			move_range = 4
			attack_range = 2
			damage = 6  # even, like every base damage: junk cover halves to 3
			accuracy = 75
			frames = BRUTE_FRAMES
			aim_frames = BRUTE_AIM_FRAMES
			walk_frames = BRUTE_WALK_FRAMES
			idle_frames = BRUTE_IDLE_FRAMES
			raise_frames = BRUTE_RAISE_FRAMES
			aim_idle_frames = BRUTE_AIM_IDLE_FRAMES
			death_frames = BRUTE_DEATH_FRAMES
			dead_frames = BRUTE_DEAD_FRAMES
			idle_alt_frames = BRUTE_IDLE_ALT_FRAMES
			hurt_frames = BRUTE_HURT_FRAMES
			reload_frames = BRUTE_RELOAD_FRAMES
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
	# After the stat blocks, so it captures whatever this kind starts on.
	morale_ceiling = morale
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


## Stamp a campaign soldier onto a freshly-setup unit: name, level, perks, and
## the stats those have earned. MUST run after setup(), which assigns every
## stat from scratch - and note setup() derives hp and ammo from max_hp and
## mag_size at its tail, so anything that moves those has to re-derive them or
## a promoted soldier deploys already wounded.
##
## Order matters and is fixed: level bonuses, then perks, then the accuracy
## cap ONCE, then the wound. The cap last-but-one is what lets a veteran
## class absorb late accuracy levels into it; the wound dead last is what
## keeps its contract - exactly one point off the top, whatever the career.
func apply_progression(soldier: Dictionary) -> void:
	soldier_id = int(soldier.id)
	surname = str(soldier.surname)
	career_level = int(soldier.get("level", 1))
	perks = (soldier.perks as Array).duplicate()
	# The career ladder: +1 accuracy at every even level, +1 max HP at every
	# odd one. Career.gd owns the arithmetic; this is the one place it lands
	# on a unit.
	accuracy += Career.accuracy_bonus_at(career_level)
	max_hp += Career.hp_bonus_at(career_level)
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
	# What he carries. Additive stat mods from the Gear catalog - never
	# damage, by ALLOWED_MODS - except arc_half, which is set-with-max so a
	# sentinel's widened watch never narrows and never stacks past itself.
	for slot: String in Gear.SLOTS:
		var mods := Gear.mods_of(str((soldier.get("gear", {}) as Dictionary)
				.get(slot, "")))
		accuracy += int(mods.get("accuracy", 0))
		max_hp += int(mods.get("max_hp", 0))
		move_range += int(mods.get("move_range", 0))
		attack_range += int(mods.get("attack_range", 0))
		mag_size += int(mods.get("mag_size", 0))
		if mods.has("arc_half"):
			arc_half = maxi(arc_half, int(mods.arc_half))
	# Nobody becomes a sure thing: capped once, after everything that can
	# raise it.
	accuracy = mini(accuracy, Game.ACCURACY_CAP)
	# Walking wounded: he chose to deploy rather than sit it out, and the
	# wound is one point off the top for the whole mission. After every
	# max_hp bonus, so the cost is always exactly one point regardless of
	# career - and never below 2, so a wound is a handicap, not a death
	# sentence waiting on a graze.
	if bool(soldier.get("wounded", false)):
		max_hp = maxi(max_hp - 1, 2)
	# The re-derive tail: setup() already set hp and ammo, so anything above
	# that moves max_hp or mag_size has to be re-derived here or a promoted
	# soldier deploys wounded or short-loaded.
	hp = max_hp
	ammo = mag_size
	queue_redraw()


func has_perk(perk: String) -> bool:
	return perks.has(perk)


# The specialist Kestrels' own sets. No standing_idle_alt: it is optional
# (UNIT_ASSET_SPEC.md §3) and an empty array is handled as "no variation", so
# _load_dir_frames is simply never asked for one.
# --- Kestrel_Grenadier ---
static var GRENADIER_FRAMES: Array[Texture2D] = _load_rotation_frames(
		GRENADIER_ROOT + "/Kestrel_Grenadier/rotations")
static var GRENADIER_AIM_FRAMES: Array[Texture2D] = _load_rotation_frames(
		GRENADIER_ROOT + "/ReadyToFire_Stance/rotations")
static var GRENADIER_DEAD_FRAMES: Array[Texture2D] = _load_rotation_frames(
		GRENADIER_ROOT + "/Dead_stance/rotations")
static var GRENADIER_IDLE_FRAMES: Array = _load_dir_frames(
		GRENADIER_ROOT + "/Kestrel_Grenadier/animations/standing_idle")
static var GRENADIER_WALK_FRAMES: Array = _load_dir_frames(
		GRENADIER_ROOT + "/Kestrel_Grenadier/animations/standing_idle_walk")
static var GRENADIER_RAISE_FRAMES: Array = _load_dir_frames(
		GRENADIER_ROOT + "/Kestrel_Grenadier/animations/standing_idle_to_readyToFire")
static var GRENADIER_AIM_IDLE_FRAMES: Array = _load_dir_frames(
		GRENADIER_ROOT + "/ReadyToFire_Stance/animations/standing-readyToFire_idle")
static var GRENADIER_DEATH_FRAMES: Array = _load_dir_frames(
		GRENADIER_ROOT + "/Kestrel_Grenadier/animations/standing_idle_to_dead")
static var GRENADIER_HURT_FRAMES: Array = _load_dir_frames(
		GRENADIER_ROOT + "/Kestrel_Grenadier/animations/standing_idle_damage")
static var GRENADIER_RELOAD_FRAMES: Array = _load_dir_frames(
		GRENADIER_ROOT + "/Kestrel_Grenadier/animations/standing_idle_reload")
# No alt idle was generated. _load_dir_frames on the absent path still
# returns the eight-slot shape with every cycle empty, which is what
# "no variation" has to look like - _current_cycle indexes this BY
# DIRECTION, so a flat [] is an out-of-bounds crash rather than a
# missing animation.
static var GRENADIER_IDLE_ALT_FRAMES: Array = _load_dir_frames(
		GRENADIER_ROOT + "/Kestrel_Grenadier/animations/standing_idle_alt")

# --- Kestrel_Marksman ---
static var MARKSMAN_FRAMES: Array[Texture2D] = _load_rotation_frames(
		MARKSMAN_ROOT + "/Kestrel_Marksman/rotations")
static var MARKSMAN_AIM_FRAMES: Array[Texture2D] = _load_rotation_frames(
		MARKSMAN_ROOT + "/ReadyToFire_Stance/rotations")
static var MARKSMAN_DEAD_FRAMES: Array[Texture2D] = _load_rotation_frames(
		MARKSMAN_ROOT + "/Dead_stance/rotations")
static var MARKSMAN_IDLE_FRAMES: Array = _load_dir_frames(
		MARKSMAN_ROOT + "/Kestrel_Marksman/animations/standing_idle")
static var MARKSMAN_WALK_FRAMES: Array = _load_dir_frames(
		MARKSMAN_ROOT + "/Kestrel_Marksman/animations/standing_idle_walk")
static var MARKSMAN_RAISE_FRAMES: Array = _load_dir_frames(
		MARKSMAN_ROOT + "/Kestrel_Marksman/animations/standing_idle_to_readyToFire")
static var MARKSMAN_AIM_IDLE_FRAMES: Array = _load_dir_frames(
		MARKSMAN_ROOT + "/ReadyToFire_Stance/animations/standing-readyToFire_idle")
static var MARKSMAN_DEATH_FRAMES: Array = _load_dir_frames(
		MARKSMAN_ROOT + "/Kestrel_Marksman/animations/standing_idle_to_dead")
static var MARKSMAN_HURT_FRAMES: Array = _load_dir_frames(
		MARKSMAN_ROOT + "/Kestrel_Marksman/animations/standing_idle_damage")
static var MARKSMAN_RELOAD_FRAMES: Array = _load_dir_frames(
		MARKSMAN_ROOT + "/Kestrel_Marksman/animations/standing_idle_reload")
# No alt idle was generated. _load_dir_frames on the absent path still
# returns the eight-slot shape with every cycle empty, which is what
# "no variation" has to look like - _current_cycle indexes this BY
# DIRECTION, so a flat [] is an out-of-bounds crash rather than a
# missing animation.
static var MARKSMAN_IDLE_ALT_FRAMES: Array = _load_dir_frames(
		MARKSMAN_ROOT + "/Kestrel_Marksman/animations/standing_idle_alt")

# --- Kestrel_Breacher ---
static var BREACHER_FRAMES: Array[Texture2D] = _load_rotation_frames(
		BREACHER_ROOT + "/Kestrel_Breacher/rotations")
static var BREACHER_AIM_FRAMES: Array[Texture2D] = _load_rotation_frames(
		BREACHER_ROOT + "/ReadyToFire_Stance/rotations")
static var BREACHER_DEAD_FRAMES: Array[Texture2D] = _load_rotation_frames(
		BREACHER_ROOT + "/Dead_stance/rotations")
static var BREACHER_IDLE_FRAMES: Array = _load_dir_frames(
		BREACHER_ROOT + "/Kestrel_Breacher/animations/standing_idle")
static var BREACHER_WALK_FRAMES: Array = _load_dir_frames(
		BREACHER_ROOT + "/Kestrel_Breacher/animations/standing_idle_walk")
static var BREACHER_RAISE_FRAMES: Array = _load_dir_frames(
		BREACHER_ROOT + "/Kestrel_Breacher/animations/standing_idle_to_readyToFire")
static var BREACHER_AIM_IDLE_FRAMES: Array = _load_dir_frames(
		BREACHER_ROOT + "/ReadyToFire_Stance/animations/standing-readyToFire_idle")
static var BREACHER_DEATH_FRAMES: Array = _load_dir_frames(
		BREACHER_ROOT + "/Kestrel_Breacher/animations/standing_idle_to_dead")
static var BREACHER_HURT_FRAMES: Array = _load_dir_frames(
		BREACHER_ROOT + "/Kestrel_Breacher/animations/standing_idle_damage")
static var BREACHER_RELOAD_FRAMES: Array = _load_dir_frames(
		BREACHER_ROOT + "/Kestrel_Breacher/animations/standing_idle_reload")
# No alt idle was generated. _load_dir_frames on the absent path still
# returns the eight-slot shape with every cycle empty, which is what
# "no variation" has to look like - _current_cycle indexes this BY
# DIRECTION, so a flat [] is an out-of-bounds crash rather than a
# missing animation.
static var BREACHER_IDLE_ALT_FRAMES: Array = _load_dir_frames(
		BREACHER_ROOT + "/Kestrel_Breacher/animations/standing_idle_alt")

# --- Kestrel_Medic ---
static var MEDIC_FRAMES: Array[Texture2D] = _load_rotation_frames(
		MEDIC_ROOT + "/Kestrel_Medic/rotations")
static var MEDIC_AIM_FRAMES: Array[Texture2D] = _load_rotation_frames(
		MEDIC_ROOT + "/ReadyToFire_Stance/rotations")
static var MEDIC_DEAD_FRAMES: Array[Texture2D] = _load_rotation_frames(
		MEDIC_ROOT + "/Dead_stance/rotations")
static var MEDIC_IDLE_FRAMES: Array = _load_dir_frames(
		MEDIC_ROOT + "/Kestrel_Medic/animations/standing_idle")
static var MEDIC_WALK_FRAMES: Array = _load_dir_frames(
		MEDIC_ROOT + "/Kestrel_Medic/animations/standing_idle_walk")
static var MEDIC_RAISE_FRAMES: Array = _load_dir_frames(
		MEDIC_ROOT + "/Kestrel_Medic/animations/standing_idle_to_readyToFire")
static var MEDIC_AIM_IDLE_FRAMES: Array = _load_dir_frames(
		MEDIC_ROOT + "/ReadyToFire_Stance/animations/standing-readyToFire_idle")
static var MEDIC_DEATH_FRAMES: Array = _load_dir_frames(
		MEDIC_ROOT + "/Kestrel_Medic/animations/standing_idle_to_dead")
static var MEDIC_HURT_FRAMES: Array = _load_dir_frames(
		MEDIC_ROOT + "/Kestrel_Medic/animations/standing_idle_damage")
static var MEDIC_RELOAD_FRAMES: Array = _load_dir_frames(
		MEDIC_ROOT + "/Kestrel_Medic/animations/standing_idle_reload")
# No alt idle was generated. _load_dir_frames on the absent path still
# returns the eight-slot shape with every cycle empty, which is what
# "no variation" has to look like - _current_cycle indexes this BY
# DIRECTION, so a flat [] is an out-of-bounds crash rather than a
# missing animation.
static var MEDIC_IDLE_ALT_FRAMES: Array = _load_dir_frames(
		MEDIC_ROOT + "/Kestrel_Medic/animations/standing_idle_alt")

# --- Kestrel_Technician ---
static var TECHNICIAN_FRAMES: Array[Texture2D] = _load_rotation_frames(
		TECHNICIAN_ROOT + "/Kestrel_Technician/rotations")
static var TECHNICIAN_AIM_FRAMES: Array[Texture2D] = _load_rotation_frames(
		TECHNICIAN_ROOT + "/ReadyToFire_Stance/rotations")
static var TECHNICIAN_DEAD_FRAMES: Array[Texture2D] = _load_rotation_frames(
		TECHNICIAN_ROOT + "/Dead_stance/rotations")
static var TECHNICIAN_IDLE_FRAMES: Array = _load_dir_frames(
		TECHNICIAN_ROOT + "/Kestrel_Technician/animations/standing_idle")
static var TECHNICIAN_WALK_FRAMES: Array = _load_dir_frames(
		TECHNICIAN_ROOT + "/Kestrel_Technician/animations/standing_idle_walk")
static var TECHNICIAN_RAISE_FRAMES: Array = _load_dir_frames(
		TECHNICIAN_ROOT + "/Kestrel_Technician/animations/standing_idle_to_readyToFire")
static var TECHNICIAN_AIM_IDLE_FRAMES: Array = _load_dir_frames(
		TECHNICIAN_ROOT + "/ReadyToFire_Stance/animations/standing-readyToFire_idle")
static var TECHNICIAN_DEATH_FRAMES: Array = _load_dir_frames(
		TECHNICIAN_ROOT + "/Kestrel_Technician/animations/standing_idle_to_dead")
static var TECHNICIAN_HURT_FRAMES: Array = _load_dir_frames(
		TECHNICIAN_ROOT + "/Kestrel_Technician/animations/standing_idle_damage")
static var TECHNICIAN_RELOAD_FRAMES: Array = _load_dir_frames(
		TECHNICIAN_ROOT + "/Kestrel_Technician/animations/standing_idle_reload")
# No alt idle was generated. _load_dir_frames on the absent path still
# returns the eight-slot shape with every cycle empty, which is what
# "no variation" has to look like - _current_cycle indexes this BY
# DIRECTION, so a flat [] is an out-of-bounds crash rather than a
# missing animation.
static var TECHNICIAN_IDLE_ALT_FRAMES: Array = _load_dir_frames(
		TECHNICIAN_ROOT + "/Kestrel_Technician/animations/standing_idle_alt")

# The goblin machine-gunner. Steel pot helmet, ammunition backpack, and the
# belt arcing between them - the silhouette no other goblin owns.
static var GMG_FRAMES: Array[Texture2D] = _load_rotation_frames(
		GMG_ROOT + "/Goblin_MG/rotations")
static var GMG_AIM_FRAMES: Array[Texture2D] = _load_rotation_frames(
		GMG_ROOT + "/ReadyToFire_Stance/rotations")
static var GMG_DEAD_FRAMES: Array[Texture2D] = _load_rotation_frames(
		GMG_ROOT + "/Dead_stance/rotations")
static var GMG_IDLE_FRAMES: Array = _load_dir_frames(
		GMG_ROOT + "/Goblin_MG/animations/standing_idle")
static var GMG_IDLE_ALT_FRAMES: Array = _load_dir_frames(
		GMG_ROOT + "/Goblin_MG/animations/standing_idle_alt")
static var GMG_WALK_FRAMES: Array = _load_dir_frames(
		GMG_ROOT + "/Goblin_MG/animations/standing_idle_walk")
static var GMG_RAISE_FRAMES: Array = _load_dir_frames(
		GMG_ROOT + "/Goblin_MG/animations/standing_idle_to_readyToFire")
static var GMG_AIM_IDLE_FRAMES: Array = _load_dir_frames(
		GMG_ROOT + "/ReadyToFire_Stance/animations/standing-readyToFire_idle")
static var GMG_DEATH_FRAMES: Array = _load_dir_frames(
		GMG_ROOT + "/Goblin_MG/animations/standing_idle_to_dead")
static var GMG_HURT_FRAMES: Array = _load_dir_frames(
		GMG_ROOT + "/Goblin_MG/animations/standing_idle_damage")
static var GMG_RELOAD_FRAMES: Array = _load_dir_frames(
		GMG_ROOT + "/Goblin_MG/animations/standing_idle_reload")

# The brute. 80x72 sheets, feet 27px below canvas centre - his SPRITE_SPECS
# entry is what keeps him on his diamond.
static var BRUTE_FRAMES: Array[Texture2D] = _load_rotation_frames(
		BRUTE_ROOT + "/Goblin_Brute/rotations")
static var BRUTE_AIM_FRAMES: Array[Texture2D] = _load_rotation_frames(
		BRUTE_ROOT + "/ReadyToFire_Stance/rotations")
static var BRUTE_DEAD_FRAMES: Array[Texture2D] = _load_rotation_frames(
		BRUTE_ROOT + "/Dead_stance/rotations")
static var BRUTE_IDLE_FRAMES: Array = _load_dir_frames(
		BRUTE_ROOT + "/Goblin_Brute/animations/standing_idle")
static var BRUTE_IDLE_ALT_FRAMES: Array = _load_dir_frames(
		BRUTE_ROOT + "/Goblin_Brute/animations/standing_idle_alt")
static var BRUTE_WALK_FRAMES: Array = _load_dir_frames(
		BRUTE_ROOT + "/Goblin_Brute/animations/standing_idle_walk")
static var BRUTE_RAISE_FRAMES: Array = _load_dir_frames(
		BRUTE_ROOT + "/Goblin_Brute/animations/standing_idle_to_readyToFire")
static var BRUTE_AIM_IDLE_FRAMES: Array = _load_dir_frames(
		BRUTE_ROOT + "/ReadyToFire_Stance/animations/standing-readyToFire_idle")
static var BRUTE_DEATH_FRAMES: Array = _load_dir_frames(
		BRUTE_ROOT + "/Goblin_Brute/animations/standing_idle_to_dead")
static var BRUTE_HURT_FRAMES: Array = _load_dir_frames(
		BRUTE_ROOT + "/Goblin_Brute/animations/standing_idle_damage")
static var BRUTE_RELOAD_FRAMES: Array = _load_dir_frames(
		BRUTE_ROOT + "/Goblin_Brute/animations/standing_idle_reload")


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
		Kind.GRENADIER:
			offsets = GRENADIER_MUZZLE_OFFSETS
		Kind.MARKSMAN:
			offsets = MARKSMAN_MUZZLE_OFFSETS
		Kind.BREACHER:
			offsets = BREACHER_MUZZLE_OFFSETS
		Kind.MEDIC:
			offsets = MEDIC_MUZZLE_OFFSETS
		Kind.TECHNICIAN:
			offsets = TECHNICIAN_MUZZLE_OFFSETS
		Kind.GOBLIN_MG:
			offsets = GMG_MUZZLE_OFFSETS
		Kind.GOBLIN_BRUTE:
			offsets = BRUTE_MUZZLE_OFFSETS
	return to_global(offsets[facing_sector])


## The machinegunner has no semi-automatic setting - his lightest option is
## a burst, so a plain click fires one.
func can_single_shot() -> bool:
	return kind != Kind.MACHINEGUNNER


## The lead's battle rifle is semi-automatic; everything automatic bursts.
func can_burst() -> bool:
	return kind == Kind.SCOUT or kind == Kind.MACHINEGUNNER \
			or kind == Kind.GOBLIN_SMG or kind == Kind.GOBLIN_SMG_ALT \
			or kind == Kind.GOBLIN_MG


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


## How far this unit can PUT a beaten zone, as opposed to how wide that zone is
## once it lands. Only a suppressor reaches past its aimed range; for everyone
## else this is the ordinary weapon envelope, so callers can ask without
## checking who they are asking about.
func suppress_range() -> int:
	return attack_range + (SUPPRESS_RANGE_BONUS if can_suppress() else 0)


## Someone who fights. A prisoner is on your side and walks out with you, but
## is never shot at, never shoots, and never counts toward a squad wipe.
func is_combatant() -> bool:
	# A resident of a bounty location fails this for the same reason a man with
	# his hands up does: he is not fighting. It is what keeps the mission from
	# counting a settlement of well-hands as opposition to be cleared.
	return kind != Kind.CIVILIAN and not surrendered and not resident


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
		Kind.GOBLIN_MG:
			return "Thirst Gunner"
		Kind.GOBLIN_BRUTE:
			return "Thirst Breaker"
		Kind.GOBLIN_REVOLVER:
			return "Pressed Conscript"
		Kind.GRENADIER:
			return "Kestrel Grenadier"
		Kind.MARKSMAN:
			return "Kestrel Marksman"
		Kind.BREACHER:
			return "Kestrel Breacher"
		Kind.MEDIC:
			return "Kestrel Medic"
		Kind.TECHNICIAN:
			return "Kestrel Technician"
		Kind.CIVILIAN:
			return "Prisoner"
	return "Kestrel Rifleman"


## Named soldiers answer to their name; the Thirst stays anonymous until the
## after-action names them.
func display_name() -> String:
	if surname.is_empty():
		return kind_role_name(kind)
	return Game.soldier_label({"level": career_level, "surname": surname})


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


## The fewest rounds this weapon can AIM at somebody. The machinegunner has no
## semi-automatic setting - his lightest trigger is a two-round burst - so his
## last belt round can never be fired at a man. It is not a dead round: drum
## shots and the overwatch reaction genuinely spend single rounds, which is why
## their gates stay has_ammo() while everything aimed asks for this.
func min_rounds() -> int:
	return 1 if can_single_shot() else 2


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
## Below the weapon's own minimum, not merely empty. The distinction is the
## machinegunner's: at one round he is not out, but nothing he can aim at a
## man will fire, and every prompt built on this used to stay silent about it.
func needs_reload() -> bool:
	return mag_size > 0 and not has_ammo(min_rounds())


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
	if lethal:
		last_blow = amount
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
	interrupted = false
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
	if Career.chevrons_for(career_level) > 0:
		# Career chevrons stacked just left of the HP row - one per 20 levels,
		# capped at 5, so the stack can never march off the sprite. Everything
		# else drawn up here (the overwatch diamond, the suppression and
		# acting chevrons) is centred on x = 0, so the flank is always clear.
		var rx := start_x - RANK_GAP
		for i in Career.chevrons_for(career_level):
			var ry := PIP_Y + PIP_SIZE.y * 0.5 - i * RANK_STEP
			draw_colored_polygon(PackedVector2Array([
				Vector2(rx, ry), Vector2(rx - RANK_W, ry - RANK_H),
				Vector2(rx - RANK_W, ry - RANK_H + RANK_T), Vector2(rx, ry + RANK_T),
			]), RANK_COLOR)
	if returned and survivals > 0 and career_level == 0:
		# The notebook's tally: one notch per time this fighter was settled
		# and came back. Worn on the same flank the scouts wear rank - a
		# returner has no rank to collide with - so the eye reads both marks
		# as "who this one is". Capped at four; past that the health bar is
		# already telling the story.
		var nx := start_x - RANK_GAP
		for i in mini(survivals, 4):
			draw_rect(Rect2(nx - 2.0 - i * 4.0, PIP_Y - 1.0, 2.0, PIP_SIZE.y + 2.0),
					SURVIVAL_COLOR)
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
