extends Node

## Campaign progress (autoload) - the only thing that survives
## reload_current_scene(), and therefore where the squad lives.
##
## A soldier is a plain Dictionary:
##   {id, surname, kind, xp, rank, perks: Array[String], alive}
## Units are rebuilt from scratch every battle, so nothing on Unit persists;
## Battle maps roster entries onto the level's spawn slots at spawn time and
## Unit.apply_progression() stamps the earned stats on.

var current_level := 0

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


func is_last_level() -> bool:
	return current_level >= Levels.LEVELS.size() - 1


func select_level(index: int) -> void:
	current_level = clampi(index, 0, Levels.LEVELS.size() - 1)


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


## Bring the roster up to the strength this level's spawns ask for. Squad
## composition stays level-defined rather than hard-coded to five: any kind the
## level wants more of than we have living soldiers for gets fresh recruits,
## which is also how the dead are replaced.
func ensure_roster(level_data: Dictionary) -> void:
	var wanted := {
		Unit.Kind.TEAM_LEAD: level_data.get("lead_spawns", []).size(),
		Unit.Kind.MACHINEGUNNER: level_data.get("gunner_spawns", []).size(),
		Unit.Kind.SCOUT: level_data.scout_spawns.size(),
	}
	for kind: int in wanted:
		var have := soldiers_of_kind(kind).size()
		for i in maxi(int(wanted[kind]) - have, 0):
			var soldier := _recruit(kind)
			print("[ThinShot] new recruit: %s (%s)" % [
					soldier.surname, Unit.kind_role_name(kind)])


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


func choose_perk(id: int, perk: String) -> void:
	var soldier := soldier_by_id(id)
	if soldier.is_empty() or (soldier.perks as Array).has(perk):
		return
	(soldier.perks as Array).append(perk)
	print("[ThinShot] %s takes %s" % [soldier.surname, PERKS[perk].name])
