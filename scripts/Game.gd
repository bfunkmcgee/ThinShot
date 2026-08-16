extends Node

## Campaign progress (autoload) - the only thing that survives
## reload_current_scene(), and therefore where the squad lives.
##
## A soldier is a plain Dictionary:
##   {id, surname, kind, xp, rank, perks: Array[String], alive}
## Units are rebuilt from scratch every battle, so nothing on Unit persists;
## Battle maps roster entries onto the level's spawn slots at spawn time and
## Unit.apply_progression() stamps the earned stats on.

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
	"QUINN", "TAVARES", "WOLFE", "ABARA", "KESTREL", "DUNMORE",
]


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
		# Rodar is a person, not a posting: he arrives under his own name.
		# "Akai" is not in SURNAMES, so the random pool can never mint a
		# second one - keep it that way if the pool ever grows.
		"surname": "Akai" if kind == Unit.Kind.HERO else _unused_surname(),
		"kind": kind,
		"xp": 0,
		"rank": 0,
		"perks": [] as Array,
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
	var wanted := {
		Unit.Kind.HERO: level_data.get("lead_spawns", []).size(),
		Unit.Kind.MACHINEGUNNER: level_data.get("gunner_spawns", []).size(),
		Unit.Kind.SCOUT: level_data.scout_spawns.size(),
	}
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
	var wanted := {
		Unit.Kind.MACHINEGUNNER: level_data.get("gunner_spawns", []).size(),
		Unit.Kind.SCOUT: level_data.scout_spawns.size(),
	}
	var gaps := {}
	for kind: int in wanted:
		var short := int(wanted[kind]) - soldiers_of_kind(kind).size()
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
const SAVE_VERSION := 2

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
