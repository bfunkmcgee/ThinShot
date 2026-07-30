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
# Ranks 1 and 3 additionally offer a choice of two specialties. Thresholds are
# tuned to the campaign's real size - 31 goblins and 5 caches across three
# maps, split five ways - so an average soldier makes Corporal after the first
# mission and Staff Sergeant by the end, and a standout makes Master Sergeant.
const RANKS: Array[Dictionary] = [
	{"title": "Scout", "abbrev": "", "xp": 0},
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

# Which ranks let the player choose, and what they choose between. Every perk
# hangs off machinery the game already has rather than adding a subsystem.
const PERK_RANKS := {
	1: ["marksman", "sprinter"],
	3: ["sentinel", "hustle"],
}
const PERKS := {
	# Blurbs are kept short deliberately: they are rendered on fixed-width
	# buttons with no autowrap, so a long one would clip.
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
		"blurb": "Overwatch covers 180 degrees.",
	},
	"hustle": {
		"name": "Hustle",
		"blurb": "Give up the shot to move again (V).",
	},
}

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
		"surname": _unused_surname(),
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
	var wanted := {
		Unit.Kind.TEAM_LEAD: level_data.get("lead_spawns", []).size(),
		Unit.Kind.MACHINEGUNNER: level_data.get("gunner_spawns", []).size(),
		Unit.Kind.SCOUT: level_data.scout_spawns.size(),
	}
	for kind: int in wanted:
		for i in maxi(int(wanted[kind]) - _ever_of_kind(kind), 0):
			var soldier := _recruit(kind)
			print("[ThinShot] new recruit: %s (%s)" % [
					soldier.surname, Unit.kind_role_name(kind)])


## How many bodies short of a full squad the roster is, by role.
func vacancies(level_data: Dictionary) -> Dictionary:
	var wanted := {
		Unit.Kind.TEAM_LEAD: level_data.get("lead_spawns", []).size(),
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
			print("[ThinShot] garrison assigns %s (%s)" % [
					soldier.surname, Unit.kind_role_name(kind)])
	return taken


func reset_roster() -> void:
	roster.clear()
	_snapshot.clear()
	pending_promotions.clear()
	mission_xp.clear()
	_next_id = 1


# ----------------------------------------------------------------- missions --


func _deep_copy(source: Array) -> Array:
	var out: Array = []
	for soldier: Dictionary in source:
		var copy := soldier.duplicate()
		copy.perks = (soldier.perks as Array).duplicate()
		out.append(copy)
	return out


## Snapshot the squad so a failed mission can be rolled back wholesale.
func begin_mission() -> void:
	_snapshot = _deep_copy(roster)
	pending_promotions.clear()
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
		print("[ThinShot] %s promoted to %s" % [soldier.surname, rank_title(new_rank)])
		# Every rank crossed that offers a choice queues one, so a soldier who
		# jumps two ranks at once still gets both picks.
		for rank in range(old_rank + 1, new_rank + 1):
			if PERK_RANKS.has(rank):
				pending_promotions.append({"id": int(soldier.id), "rank": rank})
	_snapshot.clear()


## Mission lost, retried, or abandoned via the level buttons: put the squad back
## exactly as it was when the mission started, XP and casualties included.
func abort_mission() -> void:
	if _snapshot.is_empty():
		return
	roster = _deep_copy(_snapshot)
	pending_promotions.clear()
	mission_xp.clear()
	mission_dead.clear()


func choose_perk(id: int, perk: String) -> void:
	var soldier := soldier_by_id(id)
	if soldier.is_empty() or (soldier.perks as Array).has(perk):
		return
	(soldier.perks as Array).append(perk)
	print("[ThinShot] %s takes %s" % [soldier.surname, PERKS[perk].name])
