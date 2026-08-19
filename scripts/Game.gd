extends Node

## Campaign progress (autoload) - the only thing that survives
## reload_current_scene(), and therefore where the squad lives.
##
## A soldier is a plain Dictionary:
##   {id, surname, kind, xp, rank, perks: Array[String], alive}
## Units are rebuilt from scratch every battle, so nothing on Unit persists;
## Battle maps roster entries onto the level's spawn slots at spawn time and
## Unit.apply_progression() stamps the earned stats on.

const MENU_SCENE := "res://scenes/MainMenu.tscn"
const CAMP_SCENE := "res://scenes/Camp.tscn"
const BATTLE_SCENE := "res://scenes/Battle.tscn"

# Where the campaign is. An operation is a run of missions the squad stays out
# on; current_level is the flat index of the mission being fought, kept because
# a mission has never needed to know which operation it belongs to.
var current_operation := 0
var current_level := 0
# True while the squad is out on an operation - that is, between its missions
# rather than back at the garrison. Decides which camp the player walks around
# and whether replacements are available.
var in_the_field := false

# This campaign's own number, minted once and then never touched again. It is
# what makes a battle reproducible: the dice a mission rolls are derived from
# the save rather than from the wall clock, so the same campaign at the same
# mission on the same attempt fights the same fight - and a bug report can
# carry the seed instead of a description of what the goblins did.
#
# 0 means "never minted", which is why every mint below refuses to return it:
# a campaign that landed on 0 would be re-minted on every load and would never
# settle on an identity at all.
var campaign_seed := 0
# How many times this campaign has thrown a mission away - lost, retried, or
# abandoned. Part of the battle seed on purpose: a retry has to be a DIFFERENT
# battle, or a player who reloads into the same rolls is not retrying, he is
# rewinding. Counted for the campaign rather than per mission, because what it
# has to do is move.
var mission_attempts := 0

# --- v3: what the theater thinks of the squad, and what it remembers ---------
#
# Every number here is a LITERAL and not a Rules.* constant, and that is load
# bearing. Rules names Unit in every signature, Unit names this autoload, and
# a reference the other way would close the cycle - in the one file the `-s`
# harnesses load before the autoloads exist (see CLASS_PERK_RANKS above, which
# is keyed by raw ordinal for the same reason). Rules still owns these numbers
# and does all the arithmetic on them; Battle is the layer that can name both
# and is where conduct is actually applied. tools/test_rules.gd asserts the
# duplicated values agree, so this cannot drift.
const STANDING_START := 50
const STRAIN_START := 12

# Per settlement, 0..100: what the people whose water this was make of the
# squad. Absent means nobody there has met them yet - see standing_of().
var district_standing: Dictionary = {}
# Theater-wide, and never zero. An Accord counterinsurgency is standing on
# ground whose Assembly filed an objection, and conduct cannot make that untrue.
var alliance_strain := STRAIN_START
# Dava's notebook: every name the campaign has taken, mission by mission, in
# the order it happened. Append-only. This is the document the game keeps
# instead of a score.
var notebook: Array = []
## Keys of the escapees the campaign has already sent back, so the same man is
## not waiting on the rim of every remaining mission. A key is "level:ordinal",
## which is the only pair that is unique - Roll draws 228 distinct names over
## 280 spawns, so a name is a label rather than an identifier.
##
## He can still return more than once across a campaign, and that is deliberate:
## a returner who breaks and runs AGAIN writes a fresh notebook line under a new
## ordinal, carrying the name he already had. The man comes back; the key does
## not repeat.
var returned: Array = []
# v4: which three of the six rifle-slot Kestrels go out this mission, by id.
# Ids rather than indices - the roster reorders as people die, and an index
# would quietly deploy somebody else.
var deployed_ids: Array = []

# Squad ordnance, set at the camp's stores tent. The slots are a fixed budget
# split between the two grenades, so choosing is a real decision and never an
# increase in power - the 2/2 default is exactly what the squad carried before
# there was anywhere to change it.
const LOADOUT_SLOTS := 4
var frags := 2
var smokes := 2

# Slot-keyed squad. Order within a kind is stable, so soldier 3 of 3 scouts
# stays the same person from mission to mission.
var roster: Array = []
# Deep copy taken when a mission starts. A loss or a level jump restores it,
# so XP earned in a failed attempt cannot be farmed by retrying.
var _snapshot: Array = []
var _next_id := 1
# Promotions earned this mission and not yet spent: [{id, rank}].
var pending_promotions: Array = []
# Per-soldier XP earned this mission, for the debrief: id -> int.
var mission_xp: Dictionary = {}
# Who fell this mission. The roster keeps its dead forever now, so the debrief
# needs to know which of them to read out rather than listing every casualty
# the campaign has ever taken.
var mission_dead: Dictionary = {}

var _rng := RandomNumberGenerator.new()

# Ranks are cumulative: every one adds ACCURACY_PER_RANK and HP_PER_RANK.
# Every rank past the first additionally offers a choice of two specialties
# from the soldier's own class tree. Thresholds are tuned to the campaign's
# real size - 31 goblins and 5 caches across three maps, split five ways - so
# an average soldier makes Corporal after the first mission and Staff Sergeant
# by the end, and a standout makes Master Sergeant.
const RANKS: Array[Dictionary] = [
	# Rodar enters as a conscript, so the bottom rung says so. Title only -
	# the threshold and both per-rank bonuses are unchanged.
	{"title": "Levy", "abbrev": "", "xp": 0},
	{"title": "Corporal", "abbrev": "Cpl.", "xp": 6},
	{"title": "Sergeant", "abbrev": "Sgt.", "xp": 14},
	{"title": "Staff Sergeant", "abbrev": "SSgt.", "xp": 26},
	{"title": "Master Sergeant", "abbrev": "MSgt.", "xp": 40},
]
const ACCURACY_PER_RANK := 3
const HP_PER_RANK := 1
# Nobody becomes a sure thing. Without this a Master Sergeant team lead would
# reach 104%.
const ACCURACY_CAP := 95

# Which ranks let a soldier choose, and what they choose between - one tree
# per class, a two-way choice at EVERY rank. Every perk hangs off machinery
# the game already has rather than adding a subsystem.
#
# Keyed by the raw Unit.Kind ordinal (0 SCOUT, 2 MACHINEGUNNER, 9 HERO) rather
# than the enum name: saves already store the ordinal, and a constant here must
# not drag Unit.gd into this script's compile (the `-s` test harness preloads
# Game.gd before the autoloads exist - see tools/test_save_load.gd).
#
# TEAM_LEAD (1) is retired and deliberately has no table of his own:
# commit_mission simply never queues a choice for one. Anything that still asks
# about a lead is answered with the hero's tree via perk_choices(), because a
# pre-Rodar save's lead is converted in place to the HERO the moment a camp or
# battle wants him - his queued promotion must survive the load that precedes
# that conversion.
const CLASS_PERK_RANKS := {
	0: {  # SCOUT - the skirmisher
		1: ["sprinter", "quick_hands"],
		2: ["snap_burst", "field_dressing"],
		3: ["hustle", "flanker"],
		4: ["ranger", "executioner"],
	},
	2: {  # MACHINEGUNNER - area denial
		1: ["bipod", "pack_mule"],
		2: ["wide_sweep", "grenadier"],
		3: ["sentinel", "locked_belts"],
		4: ["protective_fire", "walking_fire"],
	},
	9: {  # HERO - the marksman-leader; his tree IS his progression, since
		  # Rodar arrives already at the accuracy cap
		1: ["called_shot", "iron_will"],
		2: ["rally", "marksman"],
		3: ["inspiration", "deep_pockets"],
		4: ["one_shot", "untouchable"],
	},
	# --- the five specialist Kestrels (Phase 3) ---------------------------
	#
	# Composed entirely from perks the game already implements. That is not
	# laziness, it is the same rule the original three trees were built under:
	# every perk hangs off machinery that exists rather than adding a
	# subsystem. A tree that promised an effect nothing reads would be a lie
	# told on a promotion screen.
	#
	# Perks deliberately repeat across classes. A perk is an effect, not a
	# possession, and Sprinter means the same thing on a medic as on a
	# rifleman; what separates these six is the STAT LINE and which effects
	# they can reach, not a private vocabulary each.
	10: {  # GRENADIER - Essa Vane, the squad's ordnance
		1: ["pack_mule", "quick_hands"],
		2: ["deep_pockets", "sprinter"],
		3: ["hustle", "flanker"],
		4: ["ranger", "executioner"],
	},
	11: {  # MARKSMAN - Sillae Vekh, reach without armour
		1: ["iron_will", "quick_hands"],
		2: ["sentinel", "sprinter"],
		3: ["flanker", "hustle"],
		4: ["one_shot", "executioner"],
	},
	12: {  # BREACHER - Halvik Dunn, through the gate first
		1: ["iron_will", "pack_mule"],
		2: ["snap_burst", "quick_hands"],
		3: ["sprinter", "hustle"],
		4: ["untouchable", "executioner"],
	},
	13: {  # MEDIC - Dava Ren, keeps them standing
		1: ["sprinter", "quick_hands"],
		2: ["iron_will", "snap_burst"],
		3: ["hustle", "sentinel"],
		4: ["ranger", "untouchable"],
	},
	14: {  # TECHNICIAN - Fen Ost, reads ground rather than holds it
		1: ["sprinter", "quick_hands"],
		2: ["marksman", "snap_burst"],
		3: ["flanker", "hustle"],
		4: ["ranger", "deep_pockets"],
	},
}

## What each specialist walks in already knowing - the thing that makes the
## deployment screen a decision on mission one rather than after a promotion.
##
## Keyed by raw ordinal like the tree above, and every value must be a real key
## in PERKS: _read_roster whitelists against that table, so a typo here would be
## silently deleted from every save that stored it. tools/test_progression.gd
## asserts the whole table resolves.
##
## Rodar and the machinegunner are deliberately absent: their trees ARE their
## progression, and handing them a free perk would flatten a curve that is
## already tuned.
const CLASS_STARTING_PERK := {
	10: "grenadier",       # the squad carries one more frag because she is on it
	11: "marksman",        # no accuracy loss at long range - the reason she is here
	12: "iron_will",       # the breacher goes first and stays standing
	13: "field_dressing",  # the seed the plan named, in the hands it was meant for
	14: "sentinel",        # the widest watch in the squad
}
const PERKS := {
	# Blurbs are kept short deliberately: they are rendered on fixed-width
	# buttons with no autowrap, so a long one would clip. Keep them under 48
	# characters - tools/test_progression.gd enforces it.
	#
	# The four pre-tree keys (marksman, sprinter, sentinel, hustle) must keep
	# their exact strings forever: _read_roster whitelists against this table,
	# so renaming one silently deletes the pick from every save that holds it.
	"marksman": {
		"name": "Marksman",
		"blurb": "No accuracy loss at long range.",
	},
	"sprinter": {
		"name": "Sprinter",
		"blurb": "One more tile of movement.",
	},
	"sentinel": {
		"name": "Sentinel",
		"blurb": "A wider overwatch arc.",
	},
	"hustle": {
		"name": "Hustle",
		"blurb": "Give up the shot to move again (V).",
	},
	# --- scout tree ---
	"quick_hands": {
		"name": "Quick Hands",
		"blurb": "Reload without giving up the move.",
	},
	"snap_burst": {
		"name": "Snap Burst",
		"blurb": "Burst fire on the move.",
	},
	"field_dressing": {
		"name": "Field Dressing",
		"blurb": "Patch yourself up (Q). Once per battle.",
	},
	"flanker": {
		"name": "Flanker",
		"blurb": "Flanking shots hit 10 harder.",
	},
	"ranger": {
		"name": "Ranger",
		"blurb": "+1 move and +1 range.",
	},
	"executioner": {
		"name": "Executioner",
		"blurb": "+1 damage on flanking shots.",
	},
	# --- machinegunner tree ---
	"bipod": {
		"name": "Bipod",
		"blurb": "Overwatch fires three rounds.",
	},
	"pack_mule": {
		"name": "Pack Mule",
		"blurb": "Two more rounds in the belt.",
	},
	"wide_sweep": {
		"name": "Wide Sweep",
		"blurb": "Suppression pins a wider area.",
	},
	"grenadier": {
		"name": "Grenadier",
		"blurb": "The squad carries one more frag.",
	},
	"locked_belts": {
		"name": "Locked Belts",
		"blurb": "Suppression pins for an extra turn.",
	},
	"protective_fire": {
		"name": "Protective Fire",
		"blurb": "Unfired overwatch carries over.",
	},
	"walking_fire": {
		"name": "Walking Fire",
		"blurb": "Full auto on the move, -10 acc.",
	},
	# --- hero tree ---
	"called_shot": {
		"name": "Called Shot",
		"blurb": "Aimed shot ignores cover (Q).",
	},
	"iron_will": {
		"name": "Iron Will",
		"blurb": "+2 HP.",
	},
	"rally": {
		"name": "Rally",
		"blurb": "Steady the squad (T). Once per battle.",
	},
	"inspiration": {
		"name": "Inspiration",
		"blurb": "Allies within 4 tiles shoot 5 better.",
	},
	"deep_pockets": {
		"name": "Deep Pockets",
		"blurb": "+2 rounds in the magazine.",
	},
	"one_shot": {
		"name": "One Shot",
		"blurb": "Called Shot hits +2 harder.",
	},
	"untouchable": {
		"name": "Untouchable",
		"blurb": "First killing blow leaves 1 HP. Once a battle.",
	},
}


## The two specialties a soldier of this kind chooses between at this rank, or
## [] when that rank and class offer no choice. The one indirection every
## consumer goes through - commit_mission queueing, _read_promotions
## validating, and the camp modal filling its two buttons.
static func perk_choices(kind: int, rank: int) -> Array:
	# The retired TEAM_LEAD answers with the hero's tree: an old save's lead
	# becomes Rodar in ensure_roster(), and his unspent promotion has to
	# survive the load_save() that runs first.
	if kind == 1:  # Unit.Kind.TEAM_LEAD, as a raw ordinal like the table keys
		kind = 9   # Unit.Kind.HERO
	var table: Dictionary = CLASS_PERK_RANKS.get(kind, {})
	return table.get(rank, [])

const XP_KILL := 3
const XP_CACHE := 4
const XP_RESCUE := 4
const XP_SURVIVE := 3

const SURNAMES: Array[String] = [
	"VANCE", "ORTIZ", "KELLER", "MBEKI", "DRAKE", "SOLIS", "HARGREAVE",
	"NAKAMURA", "REYES", "FINCH", "ODUYA", "BRANDT", "ILIC", "MARSH",
	"QUINN", "TAVARES", "WOLFE", "ABARA", "DUNMORE", "SERRANO",
]

# The Kestrels who are people rather than postings, by raw Kind ordinal - keyed
# that way for the same reason CLASS_PERK_RANKS is (see its comment).
#
# Filled IN ORDER before the random pool for their kind, so the squad the player
# meets is the squad the campaign is about. Once one of them is on the roster he
# is never recruited again, dead or alive: that is the whole weight of
# permadeath here. Lose Josen Marr and the next body at the levy post is a
# stranger with a surname out of SURNAMES, and Josen is simply gone.
#
# Mixed case on purpose. SURNAMES are shouted all-caps because they are postings;
# these read as names because they are.
const NAMED_KESTRELS := {
	9: ["Akai"],    # HERO
	2: ["Meshan"],  # MACHINEGUNNER
	0: ["Marr"],    # SCOUT
	10: ["Vane"],   # GRENADIER
	11: ["Vekh"],   # MARKSMAN
	12: ["Dunn"],   # BREACHER
	13: ["Ren"],    # MEDIC
	14: ["Ost"],    # TECHNICIAN
}

## Given names, for the places that are talking about a person rather than
## filling a slot. Surname-keyed because that is what the roster stores.
const GIVEN_NAMES := {
	"Akai": "Rodar",
	"Meshan": "Brukk",
	"Marr": "Josen",
	"Vane": "Essa",
	"Vekh": "Sillae",
	"Dunn": "Halvik",
	"Ren": "Dava",
	"Ost": "Fen",
}

## How many of each kind the campaign keeps on the ROSTER, as opposed to how
## many it fields. A mission has three rifle slots; six people can stand in one,
## and which three go is chosen at the garrison.
##
## This is the whole shape of Phase 3: the squad did not get bigger - the plan
## forbids touching the spawn tables - it got deeper. Losing Dava Ren does not
## cost a body, it costs the only pair of hands that could patch one.
const ROSTER_STRENGTH := {
	9: 1,   # HERO          - Rodar, the lead slot
	2: 1,   # MACHINEGUNNER - Brukk, the gun
	0: 1,   # SCOUT         - Josen
	10: 1,  # GRENADIER     - Essa
	11: 1,  # MARKSMAN      - Sillae
	12: 1,  # BREACHER      - Halvik
	13: 1,  # MEDIC         - Dava
	14: 1,  # TECHNICIAN    - Fen
}


func _ready() -> void:
	_rng.randomize()
	load_save()
	# A campaign that has never been saved has no identity yet. load_save() mints
	# one for every file it reads; this covers the first launch, where there is
	# no file to read and the first save() has not happened yet. Without it the
	# opening mission of every fresh campaign would roll the same dice.
	if campaign_seed == 0:
		campaign_seed = _mint_campaign_seed()


func data() -> Dictionary:
	return Levels.LEVELS[current_level]


func operation() -> Dictionary:
	return Levels.OPERATIONS[clampi(current_operation, 0, Levels.OPERATIONS.size() - 1)]


func biome() -> Dictionary:
	return Levels.BIOMES.get(operation().get("biome", "desert"), Levels.BIOMES.desert)


## Which mission of the current operation this is, counting from 1.
func mission_number() -> int:
	var missions: Array = operation().missions
	var at := missions.find(current_level)
	return (at if at >= 0 else 0) + 1


func mission_count() -> int:
	return (operation().missions as Array).size()


func is_last_level() -> bool:
	return current_level >= Levels.LEVELS.size() - 1


## The last mission of the operation the squad is currently out on - the one
## after which they go home rather than back to a tent.
func is_last_of_operation() -> bool:
	var missions: Array = operation().missions
	return missions.is_empty() or int(missions[missions.size() - 1]) == current_level


func is_last_operation() -> bool:
	return current_operation >= Levels.OPERATIONS.size() - 1


## The number Battle starts its rules stream from. Four things decide it, and
## each one is there for a reason: the campaign, so two players do not fight
## identical wars; the operation and the mission, so the second map is not a
## replay of the first; and the attempt count, so a mission thrown away and
## fought again rolls new dice. Everything in it is saved, which is what makes
## the battle reproducible from the file rather than from the session.
##
## Not the turn number and not the clock: this is read once, at the top of
## _ready, and a battle's whole sequence of rolls follows from it.
func battle_seed() -> int:
	return hash([campaign_seed, current_operation, current_level, mission_attempts])


func select_level(index: int) -> void:
	current_level = clampi(index, 0, Levels.LEVELS.size() - 1)
	# Keep the operation pointer honest when a level is chosen directly, which
	# the debug level buttons and the --level switch both do.
	for i in Levels.OPERATIONS.size():
		if (Levels.OPERATIONS[i].missions as Array).has(current_level):
			current_operation = i
			return


## Move to the next mission, or home if that was the last of the operation.
## Returns true when the squad is going back to the garrison.
func advance_mission() -> bool:
	var missions: Array = operation().missions
	var at := missions.find(current_level)
	if at >= 0 and at + 1 < missions.size():
		current_level = int(missions[at + 1])
		in_the_field = true
		return false
	# Operation over. Next one, or loop the campaign.
	if is_last_operation():
		current_operation = 0
	else:
		current_operation += 1
	var next: Array = operation().missions
	current_level = int(next[0]) if not next.is_empty() else 0
	in_the_field = false
	return true


## Split the slot budget between frags and smoke. Frags are authoritative and
## smoke takes the remainder, so the total can never drift.
func set_loadout(frag_count: int) -> void:
	frags = clampi(frag_count, 0, LOADOUT_SLOTS)
	smokes = LOADOUT_SLOTS - frags
	save()


# -------------------------------------------------------------- transitions --
# The first scene changes in the project. Both reset Engine.time_scale: hit-stop
# scales it globally and binds its restore to the engine singleton rather than
# to a node, precisely so it survives a reload - which means a transition taken
# mid-freeze would otherwise hand the next scene to the player in slow motion.


func go_to_menu() -> void:
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(MENU_SCENE)


func go_to_camp() -> void:
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(CAMP_SCENE)


func go_to_battle() -> void:
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(BATTLE_SCENE)


# ------------------------------------------------------------------ roster --


func rank_for_xp(xp: int) -> int:
	var rank := 0
	for i in RANKS.size():
		if xp >= int(RANKS[i].xp):
			rank = i
	return rank


func rank_title(rank: int) -> String:
	return str(RANKS[clampi(rank, 0, RANKS.size() - 1)].title)


func rank_abbrev(rank: int) -> String:
	return str(RANKS[clampi(rank, 0, RANKS.size() - 1)].abbrev)


## XP still needed for the next rank, or -1 at the top of the ladder.
func xp_to_next(xp: int) -> int:
	var rank := rank_for_xp(xp)
	if rank >= RANKS.size() - 1:
		return -1
	return int(RANKS[rank + 1].xp) - xp


## "SSgt. FINCH", or just "ABARA" for someone who has not been promoted yet -
## rank 0 has no abbreviation and must not leave a dangling space.
func soldier_label(soldier: Dictionary) -> String:
	var abbrev := rank_abbrev(int(soldier.get("rank", 0)))
	var name := str(soldier.get("surname", ""))
	return name if abbrev.is_empty() else "%s %s" % [abbrev, name]


func soldier_by_id(id: int) -> Dictionary:
	for soldier: Dictionary in roster:
		if int(soldier.id) == id:
			return soldier
	return {}


## Living soldiers of a kind, in stable slot order.
func soldiers_of_kind(kind: int) -> Array:
	var out: Array = []
	for soldier: Dictionary in roster:
		if int(soldier.kind) == kind and bool(soldier.alive):
			out.append(soldier)
	return out


## The next name for a kind: the first named Kestrel of that kind the campaign
## has not already fielded, and a random surname once they are all accounted
## for.
##
## "Accounted for" includes the dead. A unique person is never re-recruited -
## the roster keeps its fallen forever, so this reads the whole of it and not
## just the living.
func _next_name_for(kind: int) -> String:
	var fielded := {}
	for soldier: Dictionary in roster:
		fielded[str(soldier.get("surname", ""))] = true
	for name: String in NAMED_KESTRELS.get(kind, []):
		if not fielded.has(name):
			return name
	return _unused_surname()


## What to call a soldier when the game is talking about a person rather than
## filling a slot: "Josen Marr" for the named, "Cpl. KELLER" for everybody else.
##
## The rank is deliberately dropped for the named ones. A rank is what the Crown
## calls you; these six have names, which is the point of them.
func full_name(soldier: Dictionary) -> String:
	var surname := str(soldier.get("surname", ""))
	if GIVEN_NAMES.has(surname):
		return "%s %s" % [GIVEN_NAMES[surname], surname]
	return soldier_label(soldier)


## Whether this soldier is one of the named Kestrels rather than a replacement
## drawn off the levy post.
func is_named_kestrel(soldier: Dictionary) -> bool:
	return GIVEN_NAMES.has(str(soldier.get("surname", "")))


func _unused_surname() -> String:
	var taken := {}
	for soldier: Dictionary in roster:
		taken[soldier.surname] = true
	var free: Array[String] = []
	for name in SURNAMES:
		if not taken.has(name):
			free.append(name)
	if free.is_empty():
		return "SCOUT-%d" % _next_id
	return free[_rng.randi_range(0, free.size() - 1)]


func _recruit(kind: int) -> Dictionary:
	var soldier := {
		"id": _next_id,
		"surname": _next_name_for(kind),
		"kind": kind,
		"xp": 0,
		"rank": 0,
		# Specialists arrive knowing their specialty; everybody else starts
		# with nothing and earns it.
		"perks": ([CLASS_STARTING_PERK[kind]] if CLASS_STARTING_PERK.has(kind)
				else []) as Array,
		"alive": true,
	}
	_next_id += 1
	roster.append(soldier)
	return soldier


## Every soldier of a kind the campaign has ever fielded, the fallen included.
func _ever_of_kind(kind: int) -> int:
	var n := 0
	for soldier: Dictionary in roster:
		if int(soldier.kind) == kind:
			n += 1
	return n


## Form the squad the first time, and grow it only if a level asks for more of
## a role than the campaign has ever fielded.
##
## The dead count against that quota, so **they are never replaced** - lose a
## scout and you assault the next map one scout down, for good. There is no
## risk of the campaign stranding itself at zero soldiers: losing every scout
## loses the mission, and a lost mission is rolled back wholesale, so a won
## mission always leaves at least one of them standing.
func ensure_roster(level_data: Dictionary) -> void:
	# The lead slot belongs to Rodar Akai now: same spawn key, same job,
	# stronger soldier. TEAM_LEAD is never requested again.
	# The roster is deeper than the squad. Slot counts decide how many DEPLOY
	# (see deployment() below); ROSTER_STRENGTH decides how many people the
	# campaign has, and the two stopped being the same number in Phase 3.
	var wanted := ROSTER_STRENGTH.duplicate()
	# A mission with no lead or gunner slot wants no lead or gunner. Nothing
	# shipped looks like that, but a draft map might.
	if level_data.get("lead_spawns", []).is_empty():
		wanted[Unit.Kind.HERO] = 0
	if level_data.get("gunner_spawns", []).is_empty():
		wanted[Unit.Kind.MACHINEGUNNER] = 0
	var formed := false
	# Saves from before Rodar existed hold an alive TEAM_LEAD in the slot he
	# now fills. Convert that soldier in place - id, xp, rank and perks kept -
	# rather than recruiting a stranger beside him: the player's veteran lead
	# BECOMES Rodar, and an orphaned lead would otherwise still stand around
	# camp next to him. Done here rather than in load_save() because both Camp
	# and Battle call this before touching the roster, and only here is
	# "a hero is wanted" actually known.
	if int(wanted[Unit.Kind.HERO]) > 0 and _ever_of_kind(Unit.Kind.HERO) == 0:
		for soldier: Dictionary in roster:
			if int(soldier.kind) == Unit.Kind.TEAM_LEAD and bool(soldier.alive):
				soldier.kind = Unit.Kind.HERO
				soldier.surname = "Akai"
				formed = true
				print("[Sandline] the team lead steps forward: Rodar Akai")
				break
	for kind: int in wanted:
		for i in maxi(int(wanted[kind]) - _ever_of_kind(kind), 0):
			var soldier := _recruit(kind)
			formed = true
			print("[Sandline] new recruit: %s (%s)" % [
					soldier.surname, Unit.kind_role_name(kind)])
	# Surnames are drawn at random, so a squad that is not written down is a
	# different five people next launch. Nothing earned is being captured here -
	# this runs before begin_mission() - so it is safe to checkpoint.
	if formed:
		save()


## How many bodies short of a full squad the roster is, by role. The hero's
## slot is deliberately absent: a unique named character is never re-recruited.
## The garrison cannot replace Rodar Akai - his death ends the mission on the
## spot, and abort_mission() un-kills him on the loss path, so a roster that
## reaches camp always still has him.
func vacancies(level_data: Dictionary) -> Dictionary:
	# Sized off ROSTER_STRENGTH rather than off the level's spawn counts, and
	# that distinction is the whole of Phase 3: the garrison refills the
	# CAMPAIGN's roster, not the mission's three rifle slots. Sizing this off
	# scout_spawns would cap the squad at three riflemen again and quietly make
	# four of the specialists unreplaceable.
	var gaps := {}
	for kind: int in ROSTER_STRENGTH:
		# Rodar is not a posting. If he is gone the campaign is over, which
		# check_game_over settles a long way before the levy post opens.
		if kind == Unit.Kind.HERO:
			continue
		# A map with no gun has no gunner to replace.
		if kind == Unit.Kind.MACHINEGUNNER \
				and level_data.get("gunner_spawns", []).is_empty():
			continue
		var short := int(ROSTER_STRENGTH[kind]) - soldiers_of_kind(kind).size()
		if short > 0:
			gaps[kind] = short
	return gaps


func vacancy_count(level_data: Dictionary) -> int:
	var n := 0
	for kind: int in vacancies(level_data):
		n += int(vacancies(level_data)[kind])
	return n


## Fill every empty slot with a green recruit. Only the garrison calls this -
## inside an operation the squad fights short, and that is the whole cost of
## losing somebody. What a death takes permanently is the rank, the perks and
## the kills; what it does not take is the campaign.
func recruit_to_strength(level_data: Dictionary) -> Array:
	var taken: Array = []
	var gaps := vacancies(level_data)
	for kind: int in gaps:
		for i in int(gaps[kind]):
			var soldier := _recruit(kind)
			taken.append(soldier)
			print("[Sandline] garrison assigns %s (%s)" % [
					soldier.surname, Unit.kind_role_name(kind)])
	if not taken.is_empty():
		save()
	return taken


## Throw this campaign away and open a fresh one.
##
## Every piece of campaign state is listed here explicitly rather than being
## reset by re-running _ready() or by newing a second Game: this is an autoload,
## the scene tree keeps the one instance for the life of the process, and a
## field that gets added later and forgotten here would survive a "new campaign"
## and quietly haunt the next one. tools/test_menu.gd asserts against the saved
## payload's own key list so that forgetting one is a failing test rather than a
## ghost.
##
## Refuses if saving is locked. That lock means the file on disk was written by
## a newer build, and wiping the campaign in memory while being unable to
## replace the file would leave the player with neither.
##
## Returns whether the campaign was actually replaced.
func new_campaign() -> bool:
	if _save_locked:
		push_error("[Sandline] %s was written by a newer build - refusing to start over it"
				% SAVE_PATH)
		return false
	current_operation = 0
	current_level = 0
	in_the_field = false
	frags = 2
	smokes = LOADOUT_SLOTS - frags
	roster.clear()
	_snapshot.clear()
	pending_promotions.clear()
	mission_xp.clear()
	mission_dead.clear()
	_next_id = 1
	mission_attempts = 0
	district_standing.clear()
	alliance_strain = STRAIN_START
	notebook.clear()
	returned.clear()
	deployed_ids.clear()
	# A new campaign is a different campaign, so it fights different dice.
	campaign_seed = _mint_campaign_seed()
	save()
	print("[Sandline] new campaign, seed %d" % campaign_seed)
	return true


## A one-line description of what is on disk, for the menu to print. Empty when
## there is nothing to continue.
func campaign_summary() -> String:
	if roster.is_empty():
		return ""
	var alive := 0
	for soldier: Dictionary in roster:
		if bool(soldier.get("alive", false)):
			alive += 1
	return "%s  -  MISSION %d OF %d  -  %d SOLDIER%s" % [
		operation().name, mission_number(), mission_count(),
		alive, "" if alive == 1 else "S",
	]


func reset_roster() -> void:
	roster.clear()
	_snapshot.clear()
	pending_promotions.clear()
	mission_xp.clear()
	_next_id = 1
	# Persist the wipe immediately. This is the one place the campaign throws
	# the squad away, and a save left holding the old one would resurrect five
	# dead soldiers on the next launch.
	save()


# ----------------------------------------------------------------- missions --


func _deep_copy(source: Array) -> Array:
	var out: Array = []
	for soldier: Dictionary in source:
		var copy := soldier.duplicate()
		copy.perks = (soldier.perks as Array).duplicate()
		out.append(copy)
	return out


## Snapshot the squad so a failed mission can be rolled back wholesale.
## Deliberately does NOT clear pending_promotions: nothing queues a promotion
## during a mission (only commit_mission does, at the end of one), so anything
## still queued here is an unspent pick carried in from the last debrief, and
## commit_mission only ever queues newly-crossed ranks - it can never re-offer
## one. Clearing here silently destroyed the pick of anyone who walked to the
## briefing table instead of to the promoted soldier. Camp._on_choice removes
## each entry as it is spent.
func begin_mission() -> void:
	_snapshot = _deep_copy(roster)
	mission_xp.clear()
	mission_dead.clear()


func award(id: int, amount: int) -> void:
	var soldier := soldier_by_id(id)
	if soldier.is_empty() or amount <= 0:
		return
	soldier.xp = int(soldier.xp) + amount
	mission_xp[id] = int(mission_xp.get(id, 0)) + amount


func mark_dead(id: int) -> void:
	var soldier := soldier_by_id(id)
	if not soldier.is_empty():
		soldier.alive = false
		mission_dead[id] = true


## Who can stand in one of a mission's three rifle slots: everybody alive who is
## not the lead or the gun. Six people for three places, which is the decision
## the garrison exists to make.
func rifle_candidates() -> Array:
	var out: Array = []
	for soldier: Dictionary in roster:
		if not bool(soldier.get("alive", false)):
			continue
		if Unit.RIFLE_SLOT_KINDS.has(int(soldier.get("kind", -1))):
			out.append(soldier)
	return out


## The three ids going out this mission, sanitised on the way out rather than
## trusted: a soldier who died since the choice was made, or an id from a save
## written against a different roster, must not deploy a ghost.
##
## Under-filled choices are topped up in roster order so a player who never
## opens the deployment screen still fields a full squad - and so does a
## campaign loaded from before the screen existed.
func deployment(slots: int) -> Array:
	var candidates := rifle_candidates()
	var by_id := {}
	for soldier: Dictionary in candidates:
		by_id[int(soldier.id)] = soldier
	var chosen: Array = []
	for id: int in deployed_ids:
		if by_id.has(id) and not chosen.has(by_id[id]):
			chosen.append(by_id[id])
	for soldier: Dictionary in candidates:
		if chosen.size() >= slots:
			break
		if not chosen.has(soldier):
			chosen.append(soldier)
	return chosen.slice(0, slots)


## Record the player's choice. Ids rather than indices, because the roster
## reorders as people die and an index would quietly deploy somebody else.
func set_deployment(ids: Array) -> void:
	deployed_ids = []
	for id: Variant in ids:
		deployed_ids.append(int(id))
	save()


## What a settlement makes of the squad. Absent means nobody from there has met
## them yet, which is not the same as neutral having been earned - but it reads
## the same from here, and STANDING_START is what "we have heard of you" means.
func standing_of(settlement: String) -> int:
	return int(district_standing.get(settlement, STANDING_START))


func set_standing(settlement: String, value: int) -> void:
	if settlement.is_empty():
		return
	district_standing[settlement] = clampi(value, 0, 100)


## Add a mission's roll to the notebook. Entries are whatever Battle recorded,
## stamped with the mission they happened on so the document reads as a
## chronology rather than a heap.
##
## Append-only on purpose. The notebook is not a score and there is nothing in
## the game that subtracts from it: a campaign that goes badly does not get to
## revise what is already written down.
func add_to_notebook(level: int, entries: Array) -> void:
	for entry: Dictionary in entries:
		var identity: Dictionary = entry.get("identity", {})
		notebook.append({
			"level": level,
			"name": str(identity.get("name", "")),
			"age": int(identity.get("age", 0)),
			"settlement": str(identity.get("settlement", "")),
			"grievance": str(identity.get("grievance", "")),
			"fate": str(entry.get("fate", "")),
			# Everything below is for the ones who walked away. The notebook was
			# a document; it is now also the only record of who is still out
			# there, and a man cannot be put back on a board without knowing
			# which body he was, what he was carrying, and which way he went.
			"kind": int(entry.get("kind", -1)),
			"ordinal": int(entry.get("ordinal", -1)),
			"edge": str(entry.get("edge", "")),
		})


## The only kinds that can ever have escaped, and so the only ones that can be
## read back off a save and put on a board. Spelled as ordinals because that is
## what the notebook stores and what Unit.setup takes.
const GOBLIN_KINDS: Array[int] = [3, 4, 5, 6, 7]

## Rebuild the notebook from a save, field by field.
##
## Every other adopted structure in this file is rebuilt rather than trusted;
## the notebook was the exception because nothing read it except the diary
## screen, where a malformed entry is a cosmetic problem. It drives a spawner
## now. `kind` in particular is handed to Unit.setup(), so it is checked against
## the real enum rather than merely cast: an out-of-range ordinal from a
## hand-edited file would otherwise fall through setup()'s match and produce a
## unit with no stats, no art and no team.
func _read_notebook(raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for row: Variant in raw:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = row
		# Range is not enough, and the first version of this check thought it
		# was. Unit.setup puts kinds 0-2, 8 and 9-14 on TEAM_SCOUT, so an
		# in-range ordinal is not necessarily one of the Thirst: a campaign.json
		# edited to say kind 9 put a second Rodar Akai on the rim, on the
		# player's own team, where he counted toward the wipe condition. Only a
		# goblin ever escapes, so only a goblin can come back.
		var kind := int(entry.get("kind", -1))
		if not GOBLIN_KINDS.has(kind):
			kind = -1
		out.append({
			"level": int(entry.get("level", 0)),
			"name": str(entry.get("name", "")),
			"age": int(entry.get("age", 0)),
			"settlement": str(entry.get("settlement", "")),
			"grievance": str(entry.get("grievance", "")),
			"fate": str(entry.get("fate", "")),
			"kind": kind,
			"ordinal": int(entry.get("ordinal", -1)),
			"edge": str(entry.get("edge", "")),
		})
	return out


## The key that identifies a person the campaign has met. Not their name.
static func roll_key(level: int, ordinal: int) -> String:
	return "%d:%d" % [level, ordinal]


## Who is still out there, and might walk back onto THIS mission.
##
## Deterministic, and deliberately not a draw from any generator. Battle's
## _rules_rng advances exactly once per shot so that a seed replays a mission
## shot for shot; taking a variable number of draws from it here - one per
## escapee the campaign happens to have accumulated - would shift every roll in
## the mission by an amount that depends on campaign history. Roll.identity has
## the same discipline and the same reason. So this is a pure hash of
## (campaign seed, the mission being played, who he was), asked once per
## candidate, and it answers the same way every time the mission is loaded.
##
## Only escapees from WON missions are in here, because a lost mission is rolled
## back wholesale and its roll dies with the scene. That is the existing rule
## rather than a new one, and it reads correctly: the mission did not happen.
##
## Entries from before save v5 carry kind -1 and are skipped - there is no
## honest way to know what an old escapee was holding.
const RETURN_CHANCE := 45

func returners_from(level: int) -> Array:
	var out: Array = []
	for entry: Dictionary in notebook:
		if str(entry.get("fate", "")) != "escaped":
			continue
		if int(entry.get("kind", -1)) < 0 or int(entry.get("ordinal", -1)) < 0:
			continue
		# Nobody returns to the mission he ran from, or to one already behind us.
		if int(entry.get("level", 0)) >= level:
			continue
		var key := roll_key(int(entry.level), int(entry.ordinal))
		if returned.has(key):
			continue
		if Roll.chance(campaign_seed, level, key, RETURN_CHANCE):
			out.append(entry)
	return out


## Write down that these people have been sent back, so the rim of every
## remaining mission is not the same crowd.
func mark_returned(entries: Array) -> void:
	for entry: Dictionary in entries:
		var key := roll_key(int(entry.get("level", 0)), int(entry.get("ordinal", -1)))
		if not returned.has(key):
			returned.append(key)


## The notebook grouped the way the district connects it: settlement -> the
## people from it, in the order the campaign met them. The cross-link the plan
## asks for is this - four settlements lost their water, and the document shows
## how much of each one the squad has accounted for.
func notebook_by_settlement() -> Dictionary:
	var out := {}
	for entry: Dictionary in notebook:
		var where := str(entry.get("settlement", ""))
		if where.is_empty():
			continue
		if not out.has(where):
			out[where] = []
		out[where].append(entry)
	return out


## Mission won: keep the XP, promote whoever earned it, and queue the perk
## choices those promotions unlocked. The dead were already marked during play
## and simply stay marked.
func commit_mission() -> void:
	for soldier: Dictionary in roster:
		if not bool(soldier.alive):
			continue
		var old_rank := int(soldier.rank)
		var new_rank := rank_for_xp(int(soldier.xp))
		if new_rank <= old_rank:
			continue
		soldier.rank = new_rank
		print("[Sandline] %s promoted to %s" % [soldier.surname, rank_title(new_rank)])
		# Every rank crossed that offers this soldier's class a choice queues
		# one, so a soldier who jumps two ranks at once still gets both picks.
		for rank in range(old_rank + 1, new_rank + 1):
			if not perk_choices(int(soldier.kind), rank).is_empty():
				pending_promotions.append({"id": int(soldier.id), "rank": rank})
	_snapshot.clear()
	save()


## Mission lost, retried, or abandoned via the level buttons: put the squad back
## exactly as it was when the mission started, XP and casualties included.
func abort_mission() -> void:
	if _snapshot.is_empty():
		return
	roster = _deep_copy(_snapshot)
	# Same reasoning as begin_mission: the queue can only hold carry-over from
	# an earlier debrief, and the snapshot being restored already contains the
	# rank that earned it, so the pick is still owed. Clearing it here lost the
	# perk of anyone who deployed with one unspent and then lost the mission.
	mission_xp.clear()
	mission_dead.clear()
	# The one place an attempt is spent without being kept. Counted here rather
	# than in begin_mission so that battle_seed() only moves when a mission is
	# actually being fought AGAIN - a first attempt and the campaign's state
	# going into it are the same thing.
	mission_attempts += 1
	save()


func choose_perk(id: int, perk: String) -> void:
	var soldier := soldier_by_id(id)
	if soldier.is_empty() or (soldier.perks as Array).has(perk):
		return
	(soldier.perks as Array).append(perk)
	print("[Sandline] %s takes %s" % [soldier.surname, PERKS[perk].name])
	save()


# -------------------------------------------------------------- persistence --
# The campaign is saved at mission granularity and never mid-battle. A battle
# is already a transaction - begin_mission() snapshots the squad and
# abort_mission() rolls it back wholesale - so the boundary between missions is
# the one point where the roster is unambiguously settled. Saving inside one
# would mean either reproducing the board state on load or lying about it, and
# a mission is short enough that it is not worth either.
#
# Everything here is a plain int, bool, String or Array of those, so JSON is
# enough. The one trap is that JSON has a single number type: every int comes
# back as a float, and a rank that loads as 3.0 breaks the integer comparisons
# in rank_for_xp in ways that are miserable to track down. So nothing is read
# back raw - every field is coerced through int()/bool()/str() below.


const SAVE_PATH := "user://campaign.json"
# Raise this in the same commit that adds the migration step reaching it, and
# never one without the other - _migrate_step() is what turns a number into a
# shape the rest of this file can read.
const SAVE_VERSION := 5

# Raised, and never lowered again, when load_save() finds a campaign written by
# a build newer than this one. Refusing to READ such a file is only half the
# job: the refusal leaves the roster empty, and the very next ensure_roster()
# forms a squad from nothing and checkpoints it - straight over the campaign it
# just declined to understand. A player who launches an old build once, for any
# reason, would lose everything the new one had earned. So a version we cannot
# read is treated as someone else's data and this process writes no more saves
# at all: better a session that cannot checkpoint than a campaign that is gone.
var _save_locked := false


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save() -> void:
	if _save_locked:
		push_error("[Sandline] %s was written by a newer build - refusing to overwrite it"
				% SAVE_PATH)
		return
	var payload := {
		"version": SAVE_VERSION,
		"current_operation": current_operation,
		"current_level": current_level,
		"in_the_field": in_the_field,
		"frags": frags,
		"smokes": smokes,
		"next_id": _next_id,
		"roster": roster,
		"pending_promotions": pending_promotions,
		# v2: what makes a battle reproducible from the file. See battle_seed().
		"campaign_seed": campaign_seed,
		"mission_attempts": mission_attempts,
		# v3: what the theater thinks, and what it remembers.
		"district_standing": district_standing,
		"alliance_strain": alliance_strain,
		"notebook": notebook,
		"returned": returned,
		# v4: who the garrison picked.
		"deployed_ids": deployed_ids,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("[Sandline] cannot write %s: %s" % [
				SAVE_PATH, error_string(FileAccess.get_open_error())])
		return
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()


# ---------------------------------------------------------------- migration --
# Old saves climb a ladder of one-version steps until they are shaped like the
# current one, and only then is anything read out of them. Two jobs that sound
# alike are deliberately kept apart:
#
#   a migration RESHAPES - it is allowed to know what version 1 looked like,
#   because a file that says "version 1" is a promise about its own shape;
#   _read_roster SANITISES - it trusts nothing, rebuilds every soldier field by
#   field, whitelists perks and dedups ids, and it runs LAST, on whatever the
#   ladder produced. A hand-edited v1 save is still a hand-edited save after
#   climbing, and still has to get past the gate.
#
# The rungs are written as a `match` rather than a table of Callables because
# GDScript constants cannot hold one, and because this codebase does no
# metaprogramming anywhere else - a reader looking for what version 1 became
# should find a function named after the answer.


## One rung: a version-`from` payload in, a version-`from + 1` payload out.
## Returns {} when there is no such rung.
##
## An empty return is a bug in THIS FILE, not a bad save: it means SAVE_VERSION
## was raised without adding the step that reaches it. tools/test_save_load.gd
## walks every rung from 1 to SAVE_VERSION for exactly that reason.
##
## Never edit a step that has shipped. Every save in the wild that was going to
## climb it already has, and its stamped version now says so - so changing what
## the step does cannot reach those files, it can only disagree with them.
## Getting a rung wrong after release is fixed by adding the NEXT one.
func _migrate_step(payload: Dictionary, from: int) -> Dictionary:
	match from:
		1:
			return _migrate_1_to_2(payload)
		2:
			return _migrate_2_to_3(payload)
		3:
			return _migrate_3_to_4(payload)
		4:
			return _migrate_4_to_5(payload)
	return {}


## Climb from `from` up to SAVE_VERSION, stamping the version as it goes so a
## half-finished climb can never be mistaken for a finished one.
##
## Forward only. A newer-than-us save is refused by load_save() before it gets
## here and is never handed to the ladder; there is no downward rung and there
## should not be, because this build cannot write the shape a newer one reads.
## Returns {} the moment a rung is missing - a partly-migrated campaign is not
## something to adopt and hope about.
func _migrate(payload: Dictionary, from: int) -> Dictionary:
	if from > SAVE_VERSION:
		push_error("[Sandline] refusing to migrate save version %d down to %d"
				% [from, SAVE_VERSION])
		return {}
	var out := payload
	var at := from
	while at < SAVE_VERSION:
		out = _migrate_step(out, at)
		if out.is_empty():
			push_error("[Sandline] no migration step from save version %d - the ladder in Game.gd has a gap"
					% at)
			return {}
		at += 1
		out["version"] = at
	return out


## v1 -> v2: the campaign gains an identity.
##
## v1 saves were written before battles were reproducible, so they carry neither
## field. The seed is minted here - a campaign in progress gets a new one and
## keeps it forever after, which means its NEXT mission is seeded and the ones
## already fought stay unrepeatable. mission_attempts starts at 0 rather than at
## a guess: what a v1 save never recorded cannot be recovered, and the only
## thing the count has to do is move from here on.
func _migrate_1_to_2(payload: Dictionary) -> Dictionary:
	payload["campaign_seed"] = _mint_campaign_seed()
	payload["mission_attempts"] = 0
	return payload


## v2 -> v3: the theater starts keeping score of the squad, and the squad
## starts keeping a document.
##
## A campaign already in progress has fought missions nobody was writing down,
## and none of that is recoverable - so the notebook opens empty and Strain
## opens where a fresh campaign opens. That is deliberately NOT an amnesty
## dressed up as a migration: it is the honest shape of "this build started
## counting today", and the alternative would be inventing a history.
func _migrate_2_to_3(payload: Dictionary) -> Dictionary:
	payload["district_standing"] = {}
	payload["alliance_strain"] = STRAIN_START
	payload["notebook"] = []
	return payload


## Standing, sanitised the way the roster is: the ladder guarantees the field
## exists and a hand-edited file guarantees nothing. Anything that is not a
## settlement name mapped to a number in 0..100 is dropped rather than repaired,
## because a district whose opinion cannot be read has not got one.
func _read_standing(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var out := {}
	for key: Variant in raw:
		if typeof(key) != TYPE_STRING or str(key).is_empty():
			continue
		var value: Variant = raw[key]
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			continue
		out[str(key)] = clampi(int(value), 0, 100)
	return out


## v3 -> v4: the squad becomes deeper than the slots it fills.
##
## An empty choice is the honest migration here, and it is not a gap: the
## roster of a v3 campaign holds only the three kinds that existed then, and
## deployment() tops an under-filled choice up in roster order. So a campaign
## in progress fields exactly the squad it fielded yesterday, and meets the
## other five Kestrels the first time it walks into the garrison.
func _migrate_3_to_4(payload: Dictionary) -> Dictionary:
	payload["deployed_ids"] = []
	return payload


## v5: the notebook grew from a document into a record that can be read back,
## and the campaign started remembering who it has already sent back.
##
## Old entries are left exactly as they are. They carry no kind, no ordinal and
## no edge, so returners_from() skips them - which is right rather than
## unfortunate: there is genuinely no way to know what an old escapee was
## carrying, and inventing one would put a fighter on the board the campaign
## never met. A save from before this rung simply has nobody to send back, and
## fills up again from its next won mission onward.
func _migrate_4_to_5(payload: Dictionary) -> Dictionary:
	payload["returned"] = []
	return payload


## A campaign's number. Never 0 - that is the "not minted yet" sentinel, and a
## campaign that landed on it would be re-minted on every single load.
func _mint_campaign_seed() -> int:
	var minted := 0
	while minted == 0:
		minted = hash([Time.get_unix_time_from_system(), Time.get_ticks_usec(),
				_rng.randi()])
	return minted


## Restore a saved campaign. Returns false - leaving every field untouched at
## its default - when there is no save, or when the file is unreadable or from
## a version this build does not understand. A corrupt save must never be worse
## than a missing one; a save from a NEWER build is worse than either, and
## additionally locks saving for the rest of the process (see _save_locked).
func load_save() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		push_error("[Sandline] cannot read %s: %s" % [
				SAVE_PATH, error_string(FileAccess.get_open_error())])
		return false
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[Sandline] %s is not valid JSON - ignoring it" % SAVE_PATH)
		return false
	var payload: Dictionary = parsed
	var version := int(payload.get("version", 0))
	# Newer than us. Starting fresh is fine; overwriting is not, so lock first.
	# Note the asymmetry: an OLDER version - like anything that fails to parse
	# as a number at all, and lands at 0 - falls through to the plain refusal
	# below and leaves saving alone, because a fresh campaign written over a
	# save this build has outgrown loses nothing that can still be read.
	if version > SAVE_VERSION:
		_save_locked = true
		push_warning("[Sandline] save is version %d, this build reads %d - leaving it alone"
				% [version, SAVE_VERSION])
		return false
	# Below the first version the game ever wrote - which is also where a version
	# that is not a number at all lands, int() answering 0 for it. There is no
	# rung to start from, so this is refused like a corrupt file: no lock, start
	# fresh. See the asymmetry note above for why that is safe here and is not
	# safe for a newer save.
	if version < 1:
		push_warning("[Sandline] save is version %s, this build reads %d - starting fresh"
				% [payload.get("version", "?"), SAVE_VERSION])
		return false
	# Old, but a shape this build knows how to bring forward. The ladder runs on
	# the RAW payload, before a single field is read out of it, so everything
	# below this point - _read_roster included - only ever sees a current-shaped
	# save and needs to know nothing about the versions that came before.
	var climbed := false
	if version < SAVE_VERSION:
		var migrated := _migrate(payload, version)
		if migrated.is_empty():
			push_warning("[Sandline] cannot bring save version %d up to %d - starting fresh"
					% [version, SAVE_VERSION])
			return false
		payload = migrated
		climbed = true
		print("[Sandline] save migrated from version %d to %d" % [version, SAVE_VERSION])

	var loaded := _read_roster(payload.get("roster", []))
	if loaded.is_empty():
		push_warning("[Sandline] save has no roster - starting fresh")
		return false
	roster = loaded
	# Ids must stay unique or soldier_by_id() starts returning the wrong person.
	_next_id = maxi(int(payload.get("next_id", 1)), _highest_id() + 1)
	pending_promotions = _read_promotions(payload.get("pending_promotions", []))
	# Clamped rather than trusted: a save written against a longer LEVELS table
	# would otherwise index straight off the end of it in data().
	current_level = clampi(int(payload.get("current_level", 0)),
			0, Levels.LEVELS.size() - 1)
	current_operation = clampi(int(payload.get("current_operation", 0)),
			0, Levels.OPERATIONS.size() - 1)
	in_the_field = bool(payload.get("in_the_field", false))
	# set_loadout()'s body, inlined: going through the setter would write the
	# file straight back out again while we are still reading it.
	frags = clampi(int(payload.get("frags", 2)), 0, LOADOUT_SLOTS)
	smokes = LOADOUT_SLOTS - frags
	# The v2 fields. Read with defaults like everything else here rather than
	# trusted to exist: the ladder above guarantees they are present, and a
	# hand-edited file guarantees nothing. A seed that arrives as 0 - deleted,
	# blanked, or never minted - is minted now, because 0 is the one value that
	# means "this campaign has no identity yet".
	campaign_seed = int(payload.get("campaign_seed", 0))
	mission_attempts = maxi(int(payload.get("mission_attempts", 0)), 0)
	# The v3 fields, read the same defensive way. Strain is floored at 1 rather
	# than at 0 - Rules.STRAIN_FLOOR is the authority and asserts it, but a
	# hand-edited save that says 0 must not be adopted as gospel, because a
	# theater at zero Strain is a bug in the theme.
	district_standing = _read_standing(payload.get("district_standing", {}))
	alliance_strain = clampi(int(payload.get("alliance_strain", STRAIN_START)), 1, 100)
	# Sanitised field by field, unlike every earlier build of this line, because
	# the notebook stopped being a document the moment returners_from() started
	# reading it. It now names a Unit.Kind that goes to a spawner, and a
	# hand-edited campaign.json must not be able to put an arbitrary ordinal on
	# the board. Everything else in this file is rebuilt this way already
	# (_read_roster, _read_promotions, _read_standing); this was the exception.
	notebook = _read_notebook(payload.get("notebook", []))
	var read_returned: Variant = payload.get("returned", [])
	returned = []
	if typeof(read_returned) == TYPE_ARRAY:
		for key: Variant in read_returned:
			returned.append(str(key))
	# The v4 field. Read as ints and no further: deployment() re-checks every id
	# against the living roster anyway, so a stale or invented one costs nothing.
	deployed_ids = []
	var read_deployed: Variant = payload.get("deployed_ids", [])
	if typeof(read_deployed) == TYPE_ARRAY:
		for id: Variant in read_deployed:
			if typeof(id) == TYPE_FLOAT or typeof(id) == TYPE_INT:
				deployed_ids.append(int(id))
	if campaign_seed == 0:
		campaign_seed = _mint_campaign_seed()
	# Per-mission scratch is never saved, and must not survive a load either.
	_snapshot.clear()
	mission_xp.clear()
	mission_dead.clear()
	print("[Sandline] campaign loaded: %d soldier(s), %s mission %d/%d" % [
			roster.size(), operation().name, mission_number(), mission_count()])
	# A climb is checkpointed once, here, and this is the one write load_save()
	# does. Not tidiness: the v1 rung MINTS the campaign seed, and nothing else
	# on the way from the garrison to a mission is guaranteed to save - so a
	# migration left in memory would be redone at every launch, with a different
	# seed each time, and the campaign would never settle on the identity the
	# whole feature is about. Written last, after the payload has been fully
	# adopted AND sanitised, so what lands on disk is the campaign this build
	# actually loaded rather than the file it read.
	if climbed:
		save()
	return true


func delete_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	if err != OK:
		push_error("[Sandline] cannot delete %s: %s" % [SAVE_PATH, error_string(err)])


func _highest_id() -> int:
	var top := 0
	for soldier: Dictionary in roster:
		top = maxi(top, int(soldier.id))
	return top


## Rebuild the roster field by field rather than adopting whatever the file
## holds, so a hand-edited save cannot introduce keys the rest of the game does
## not expect, or a perk string that no longer exists.
func _read_roster(raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	var seen_ids := {}
	for entry: Variant in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var soldier: Dictionary = entry
		var id := int(soldier.get("id", 0))
		if id <= 0 or seen_ids.has(id):
			continue
		seen_ids[id] = true
		var perks: Array = []
		var raw_perks: Variant = soldier.get("perks", [])
		if typeof(raw_perks) == TYPE_ARRAY:
			for p: Variant in raw_perks:
				var perk := str(p)
				if PERKS.has(perk) and not perks.has(perk):
					perks.append(perk)
		out.append({
			"id": id,
			"surname": str(soldier.get("surname", "SCOUT-%d" % id)),
			"kind": int(soldier.get("kind", Unit.Kind.SCOUT)),
			"xp": maxi(int(soldier.get("xp", 0)), 0),
			"rank": clampi(int(soldier.get("rank", 0)), 0, RANKS.size() - 1),
			"perks": perks,
			"alive": bool(soldier.get("alive", true)),
		})
	return out


func _read_promotions(raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for entry: Variant in raw:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var promotion: Dictionary = entry
		var id := int(promotion.get("id", 0))
		var rank := int(promotion.get("rank", 0))
		# Drop anything that no longer names a living soldier, or a rank that
		# offers that soldier's class no choice - otherwise the camp opens a
		# modal it cannot fill. Runs after the roster is adopted, so the kind
		# lookup always sees the loaded soldier.
		var soldier := soldier_by_id(id)
		if soldier.is_empty() or not bool(soldier.alive):
			continue
		if perk_choices(int(soldier.kind), rank).is_empty():
			continue
		out.append({"id": id, "rank": rank})
	return out
