extends Node

## Campaign progress (autoload) - the only thing that survives
## reload_current_scene(), and therefore where the squad lives.
##
## A soldier is a plain Dictionary:
##   {id, surname, kind, xp, level, gear: Dictionary, perks: Array[String], alive}
## Units are rebuilt from scratch every battle, so nothing on Unit persists;
## Battle maps roster entries onto the level's spawn slots at spawn time and
## Unit.apply_progression() stamps the earned stats on.

const MENU_SCENE := "res://scenes/MainMenu.tscn"
const CAMP_SCENE := "res://scenes/Camp.tscn"
const BATTLE_SCENE := "res://scenes/Battle.tscn"
const INTRO_SCENE := "res://scenes/OperationIntro.tscn"

# Where the campaign is. An operation is a run of missions the squad stays out
# on; current_level is the flat index of the mission being fought, kept because
# a mission has never needed to know which operation it belongs to.
var current_operation := 0
var current_level := 0
# True while the squad is out on an operation - that is, between its missions
# rather than back at the garrison. Decides which camp the player walks around
# and whether replacements are available.
var in_the_field := false
# Which garrison room the camp scene shows; "" is the yard. Runtime only -
# deliberately not saved: a reloaded campaign opens on the yard, the same
# way it opens on the garrison rather than mid-conversation.
var camp_interior := ""
var camp_return := Vector2i(-1, -1)

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
## The living, keyed by person rather than by appearance. See the section below.
var adversaries: Array = []
## The closed files: everybody the campaign has finished with, and how.
##
## The other half of `adversaries`, and it did not exist. Nothing removed a man
## from the roster when the squad settled him on a campaign map - `last_level`
## is only written when he SURVIVES, so a returner who was killed still passed
## the return gate on every later mission and the notice board went on posting
## a bounty on a corpse. A record leaves `adversaries` for exactly two reasons
## now: a bounty finished him, or the roll says the squad did.
var adversary_endings: Array = []

# --- bounties ----------------------------------------------------------------
#
# A bounty is a mission the campaign generates rather than ships: one named
# soldier, two riflemen lent to them, and somebody the squad has already let get
# away. See scripts/Bounty.gd, which owns the generator and the odds; this file
# only remembers what happened.

## The generated board while one is being fought, {} otherwise. Not saved - it
## is a pure function of (campaign_seed, target) and Camp rebuilds it.
var bounty_level: Dictionary = {}
## {"hunter_id": int, "target_id": int} while one is running.
var bounty: Dictionary = {}
## Targets already hunted, so the board does not post the same man twice.
var bounties_done: Array = []
## The ones who took the other offer. Each is worth marked enemy positions at
## the start of every later mission, and moved the two counters when he turned.
var informants: Array = []
## One line per finished bounty, for the notebook and the after-action.
var bounty_outcomes: Array = []
## Soldiers who came back from a bounty and are sitting the next campaign
## mission out. Cleared wholesale by commit_mission(), so a rest is exactly one
## main mission long however many bounties happen in between.
##
## The point of it is roster rotation. Without it a campaign settles into one
## squad of five that fights every mission and a bench that never plays; a
## bounty now costs the main line the person who took it, so sending your best
## negotiator is a decision about the NEXT fight as well as this one.
var resting_ids: Array = []
# --- the ratline (v9) ---------------------------------------------------------
## The generated interdiction board while one is being fought, {} otherwise.
## Not saved - a pure function of (campaign_seed, operation, ordinal); the
## field radio rebuilds it.
var interdiction_level: Dictionary = {}
## {"leader_id": int, "ordinal": int} while one is running.
var interdiction: Dictionary = {}
## Crossing ordinals RUN DOWN this garrison stay. A lost attempt is not here -
## the crossing ran, and the offer stays open for retry until the operation
## starts.
var ratline_done: Array = []
## The muster strength the operation in progress locked at its first story
## mission, 0 while unlocked. Battle computes the value through Ratline (which
## this file may not import) and hands it over as a plain int.
var ratline_strength := 0
var _next_adversary_id := 1
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
# Specialty choices earned and not yet spent: [{id, level}], the level being
# the perk gate that granted the pick (one of Career.PERK_LEVELS).
var pending_promotions: Array = []
# Per-soldier XP earned this mission, for the debrief: id -> int.
var mission_xp: Dictionary = {}
# Who fell this mission. The roster keeps its dead forever now, so the debrief
# needs to know which of them to read out rather than listing every casualty
# the campaign has ever taken.
var mission_dead: Dictionary = {}

# The company book: scrip earned by mission rewards, spent at the
# quartermaster, and the armory of bought-or-found item keys (a multiset -
# two glass sights are two entries). The book belongs to the war, not the
# soldiers: reset_roster() keeps it across the campaign loop, new_campaign()
# wipes it.
var scrip := 0
var armory: Array = []
# Mission-scoped reward scratch, the mission_xp construction exactly: Battle
# accrues into these during the debrief, and only the three win sites bank
# them into the book. A loss, a retry or a load zeroes them, so a rolled-back
# mission can never leave its pay behind.
var mission_scrip := 0
var mission_loot: Array = []

var _rng := RandomNumberGenerator.new()

# Progression is Career.gd's ladder now: levels 1..100 off lifetime XP, +1 to
# one stat every level (even levels accuracy, odd levels max HP), specialty
# choices at Career.PERK_LEVELS. The military ranks are gone; the class perk
# trees below are untouched and Career.perk_gate() is the bridge into them.
#
# Nobody becomes a sure thing. Without this a level-90 veteran would shoot
# well past certainty; the cap is applied once, in Unit.apply_progression,
# after levels AND gear.
const ACCURACY_CAP := 95

# What a soldier chooses between at each of the four perk gates - one tree
# per class, a two-way choice at every gate. The inner keys are gate ordinals
# 1..4; Career.perk_gate() maps a gate LEVEL (5/15/30/50) onto them, so the
# tables survived the rank system they were named for. Every perk hangs off
# machinery the game already has rather than adding a subsystem.
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


## The two specialties a soldier of this kind chooses between at a gate
## (ordinal 1..4 - what Career.perk_gate() answers for a gate level), or []
## when that gate and class offer no choice. The one indirection every
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

# What a mission pays the company book, in scrip. XP is a soldier's and pay
# is the company's - the two never mix. A story win pays a base plus a cut
# per objective beyond the first; a bounty pays by how it ended, an informant
# being worth more alive than a corpse is dead; a crossing pays flat.
const SCRIP_STORY_BASE := 60
const SCRIP_PER_EXTRA_OBJECTIVE := 15
const SCRIP_INTERDICTION := 30
const SCRIP_BOUNTY := {"killed": 20, "surrendered": 30, "informant": 40}

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


# ---------------------------------------------------------------- settings --
# Player preferences, apart from the campaign on purpose: they describe the
# install, not the war, so they live in their own file with no version ladder
# - a missing or mangled key falls back to its default and the next write
# repairs the file. Volume is applied at the audio bus so one number covers
# every sound the game will ever make.
const SETTINGS_PATH := "user://settings.json"
const SETTINGS_DEFAULTS := {
	"volume": 100,          # master bus, percent
	"screen_shake": true,   # camera shake and kicks
	"hit_stop": true,       # the sub-second slow-motion on a landed hit
	"danger_default": true, # the danger overlay starts each battle on
	"high_contrast": false, # colorblind-safe friendly-arc alternates
}
var settings: Dictionary = SETTINGS_DEFAULTS.duplicate()


func setting(name: String) -> Variant:
	return settings.get(name, SETTINGS_DEFAULTS.get(name))


func set_setting(name: String, value: Variant) -> void:
	if not SETTINGS_DEFAULTS.has(name):
		push_error("[Sandline] no such setting: %s" % name)
		return
	settings[name] = value
	if name == "volume":
		_apply_volume()
	save_settings()


func _apply_volume() -> void:
	var linear := clampf(int(setting("volume")) / 100.0, 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(linear))


func load_settings() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		var raw := FileAccess.open(SETTINGS_PATH, FileAccess.READ).get_as_text()
		var parsed: Variant = JSON.parse_string(raw)
		if typeof(parsed) == TYPE_DICTIONARY:
			for key: String in SETTINGS_DEFAULTS:
				if (parsed as Dictionary).has(key):
					# Coerced per key: JSON round-trips ints as floats, and a
					# hand-edited file should degrade to defaults, not crash.
					if typeof(SETTINGS_DEFAULTS[key]) == TYPE_BOOL:
						settings[key] = bool(parsed[key])
					else:
						settings[key] = int(parsed[key])
	_apply_volume()


func save_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		push_error("[Sandline] cannot write %s" % SETTINGS_PATH)
		return
	file.store_string(JSON.stringify(settings, "\t"))
	file.close()


func _ready() -> void:
	load_settings()
	_rng.randomize()
	load_save()
	# A campaign that has never been saved has no identity yet. load_save() mints
	# one for every file it reads; this covers the first launch, where there is
	# no file to read and the first save() has not happened yet. Without it the
	# opening mission of every fresh campaign would roll the same dice.
	if campaign_seed == 0:
		campaign_seed = _mint_campaign_seed()


## The mission being fought. A bounty replaces it wholesale while one is
## running, which is the whole of how a generated board reaches Board and
## Battle: they read Game.data() and neither has to know where it came from.
##
## The board itself is NOT held here between sessions - it is a pure function of
## the campaign seed and the target, so Camp regenerates it. Persisting it would
## be a second copy of something already derivable, and the one that got stale.
##
## This file deliberately does not name Bounty. Bounty names Rules, Rules names
## Unit and Unit names this autoload; importing it here would close the cycle
## the layering note in Rules.gd exists to prevent. Camp builds the board and
## hands it over as a plain dictionary.
func data() -> Dictionary:
	if not bounty_level.is_empty():
		return bounty_level
	if not interdiction_level.is_empty():
		return interdiction_level
	return Levels.LEVELS[current_level]


## Is the squad out on a bounty rather than on a campaign mission?
func on_bounty() -> bool:
	return not bounty.is_empty() and not bounty_level.is_empty()


## Take a bounty. `level` is the generated board; Camp built it.
func begin_bounty(hunter_id: int, target_id: int, level: Dictionary) -> void:
	bounty = {"hunter_id": hunter_id, "target_id": target_id}
	bounty_level = level
	print("[Sandline] bounty accepted: soldier %d after adversary %d"
			% [hunter_id, target_id])


## Put the campaign back the way it was. Called whether the bounty was finished
## or abandoned, because a half-set bounty_level would silently replace the next
## campaign mission with a stale board.
func clear_bounty() -> void:
	bounty = {}
	bounty_level = {}


## Settle a finished bounty: what became of the man, what the district and the
## theater make of it, and what the soldier who did it learned.
##
## `outcome` is "killed", "surrendered" or "informant". Anything else is treated
## as no result at all and leaves the bounty on the board to be taken again -
## a mission the squad walked away from is not a mission they finished.
func finish_bounty(outcome: String, hunter_id: int, target: Dictionary) -> void:
	var target_id := int(target.get("id", 0))
	if not ["killed", "surrendered", "informant"].has(outcome):
		clear_bounty()
		return
	if not bounties_done.has(target_id):
		bounties_done.append(target_id)
	# He is no longer somebody who might walk back onto a mission, whichever of
	# the three it was. That is the point of a bounty.
	for i in range(adversaries.size() - 1, -1, -1):
		if int(adversaries[i].get("id", 0)) == target_id:
			adversaries.remove_at(i)
	if outcome == "informant":
		informants.append({
			"id": target_id,
			"name": str(target.get("name", "")),
			"settlement": str(target.get("settlement", "")),
			"turned_by": hunter_id,
		})
	bounty_outcomes.append({"id": target_id, "name": str(target.get("name", "")),
			"outcome": outcome, "hunter_id": hunter_id})
	# Whoever went is off the next main mission. Booked here rather than when
	# the bounty was accepted so that a bounty the squad lost - and had rolled
	# back - costs nobody anything.
	rest_from_bounty(hunter_id)
	clear_bounty()
	_bank_rewards()
	save()


## Close a file. The campaign is done with this man, and says how.
##
## Deliberately not called from the death hook. A lost mission is rolled back
## wholesale, so a man killed on a mission the squad then lost has to still be
## out there - which is the same rule, and the same reason, that keeps
## _remember_the_survivors() on the won branch. Battle calls this from that
## branch and from nowhere else.
func settle_adversary(id: int, fate: String, level: int) -> void:
	if id <= 0:
		return
	for i in range(adversaries.size() - 1, -1, -1):
		var rec: Dictionary = adversaries[i]
		if int(rec.get("id", 0)) != id:
			continue
		adversary_endings.append({
			"id": id,
			"name": str(rec.get("name", "")),
			"settlement": str(rec.get("settlement", "")),
			"survivals": int(rec.get("survivals", 0)),
			"fate": fate,
			"level": level,
		})
		adversaries.remove_at(i)
		return


## Is the detachment out on an interdiction rather than a campaign mission?
func on_interdiction() -> bool:
	return not interdiction.is_empty() and not interdiction_level.is_empty()


## Take a crossing. `level` is the generated board; the field radio built it -
## the same layering as begin_bounty, because Game may not import Ratline.
func begin_interdiction(leader_id: int, ordinal: int, level: Dictionary) -> void:
	interdiction = {"leader_id": leader_id, "ordinal": ordinal}
	interdiction_level = level
	print("[Sandline] interdiction accepted: soldier %d against crossing %d"
			% [leader_id, ordinal])


func clear_interdiction() -> void:
	interdiction = {}
	interdiction_level = {}


## A crossing run down. WIN only - a loss goes through abort_mission, which
## clears the board and leaves the offer open, because a crossing the squad
## failed to stop is a crossing that ran.
func finish_interdiction(leader_id: int, ordinal: int) -> void:
	if ordinal >= 0 and not ratline_done.has(ordinal):
		ratline_done.append(ordinal)
	# Whoever led is off the next main mission - the same rest, booked at the
	# same moment and for the same reason, as a bounty hunter's.
	rest_from_bounty(leader_id)
	clear_interdiction()
	_bank_rewards()
	save()
	print("[Sandline] crossing %d run down - %d of the net shut"
			% [ordinal, ratline_done.size()])


## The muster the coming operation fights at, locked exactly once - at its
## first story mission - so a retried attempt cannot re-roll the season.
## Battle hands the value in; 0 stays the unlocked sentinel.
func lock_ratline_strength(value: int) -> void:
	if ratline_strength != 0:
		return
	ratline_strength = clampi(value, 80, 115)
	save()
	print("[Sandline] the ratline settles: the Thirst musters at %d%%"
			% ratline_strength)


## The number everything reads, so "0 = unlocked" never leaks into arithmetic.
func ratline_strength_now() -> int:
	return ratline_strength if ratline_strength > 0 else 100


## Raise one of the two negotiation stats on a soldier. Named rather than let
## callers poke the roster so there is one place that knows they are floored at
## zero and one place to log the change from.
func award_stat(soldier_id: int, stat: String, amount := 1) -> void:
	if stat != "presence" and stat != "guile":
		push_error("[Sandline] no such negotiation stat: %s" % stat)
		return
	for soldier: Dictionary in roster:
		if int(soldier.get("id", 0)) != soldier_id:
			continue
		soldier[stat] = maxi(int(soldier.get(stat, 0)) + amount, 0)
		print("[Sandline] %s now has %s %d" % [soldier_label(soldier), stat,
				int(soldier[stat])])
		return


## How many enemy positions the squad is given at the start of a mission. One
## informant is worth a few; a stable of them should not hand over the board, so
## this is what the caller clamps against the number of enemies there are.
func informant_marks() -> int:
	return informants.size() * 3


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
	# Walls, stores, and a surgeon with time: coming home clears the wound
	# ledger outright. The field camp never does - that is the difference
	# between the two camps with a rule behind it.
	for soldier: Dictionary in roster:
		if bool(soldier.get("wounded", false)):
			soldier.wounded = false
	# Home again: the season's net is settled and a new one is cast. The radio
	# posts three fresh crossings against the operation just now pending.
	ratline_done.clear()
	ratline_strength = 0
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


## The drive-out cutscene ahead of an operation's first mission. Camp is the
## only caller, and only when mission_number() == 1 - every later mission in
## the operation goes straight to go_to_battle() instead.
func go_to_operation_intro() -> void:
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(INTRO_SCENE)


# ------------------------------------------------------------------ roster --


## "Lv 12 FINCH", or just "ABARA" for someone still at the bottom - level 1 is
## where everybody starts and does not need announcing.
func soldier_label(soldier: Dictionary) -> String:
	var level := int(soldier.get("level", 1))
	var name := str(soldier.get("surname", ""))
	return name if level <= 1 else "Lv %d %s" % [level, name]


func soldier_by_id(id: int) -> Dictionary:
	for soldier: Dictionary in roster:
		if int(soldier.id) == id:
			return soldier
	return {}


## Living soldiers of a kind, in stable slot order.
## Is this soldier sitting out the next campaign mission?
func is_resting(id: int) -> bool:
	return resting_ids.has(id)


## Book a rest. Called when a bounty is booked, so a bounty the squad LOST -
## which is rolled back wholesale like any lost mission - costs nobody a rest.
func rest_from_bounty(id: int) -> void:
	if id <= 0 or resting_ids.has(id):
		return
	var soldier := soldier_by_id(id)
	if soldier.is_empty() or not bool(soldier.get("alive", false)):
		return
	resting_ids.append(id)
	print("[Sandline] %s is off the next mission - just back from a bounty"
			% soldier_label(soldier))


## Drop the resting from a list of candidates - unless doing so would leave the
## mission short.
##
## The fallback is the whole reason this is a function rather than a filter. The
## roster is deeper than the squad but not infinitely: a campaign that has lost
## people can reach a point where resting one more would deploy four soldiers
## into a five-slot mission, and a side activity must never be able to do that.
## So the rest is a PREFERENCE, and a campaign thin enough to need somebody gets
## them back with a line in the log saying so.
func _rested_out(candidates: Array, slots: int) -> Array:
	var free: Array = []
	var resting: Array = []
	for soldier: Dictionary in candidates:
		if is_resting(int(soldier.get("id", 0))):
			resting.append(soldier)
		else:
			free.append(soldier)
	if free.size() >= slots or resting.is_empty():
		return free
	for soldier: Dictionary in resting:
		if free.size() >= slots:
			break
		free.append(soldier)
		print("[Sandline] %s is recalled off their rest - the squad is short"
				% soldier_label(soldier))
	return free


## The HERO and MACHINEGUNNER slots, minus anybody resting. Separate from
## soldiers_of_kind() on purpose: that one answers "who does the campaign have",
## which is what recruiting and the camp crowd both want, and must keep counting
## a resting soldier or the levy post would mint a second Rodar Akai to stand
## beside the one having a week off.
func deployable_of_kind(kind: int, slots := 1) -> Array:
	return _rested_out(soldiers_of_kind(kind), slots)


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
## filling a slot: "Josen Marr" for the named, "Lv 12 KELLER" for everybody
## else.
##
## The level is deliberately dropped for the named ones. A level is what the
## ledger says about you; these six have names, which is the point of them.
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
		"level": 1,
		# One item per slot, "" for nothing. Keys into Gear.ITEMS; Game never
		# interprets them beyond the whitelist on load - Unit applies the mods.
		"gear": {"weapon": "", "armor": "", "kit": ""},
		# Specialists arrive knowing their specialty; everybody else starts
		# with nothing and earns it.
		"perks": ([CLASS_STARTING_PERK[kind]] if CLASS_STARTING_PERK.has(kind)
				else []) as Array,
		"alive": true,
		# What a soldier is worth across a table rather than across a board.
		# Both start at nothing and are earned on bounties: PRESENCE is whether
		# a man believes you can make good on what you are offering, GUILE is
		# reading a room and being believed in it. Everybody starts equal
		# because the point of them is that a particular soldier BECOMES your
		# negotiator, and a class that arrived good at it would decide that on
		# the player's behalf.
		"presence": 0,
		"guile": 0,
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
	# now fills. Convert that soldier in place - id, xp, level, gear and perks
	# kept -
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
## losing somebody. What a death takes permanently is the levels, the perks
## and the kills; what it does not take is the campaign.
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
	adversaries.clear()
	adversary_endings.clear()
	bounties_done.clear()
	informants.clear()
	bounty_outcomes.clear()
	resting_ids.clear()
	clear_bounty()
	clear_interdiction()
	ratline_done.clear()
	ratline_strength = 0
	scrip = 0
	armory.clear()
	_next_adversary_id = 1
	deployed_ids.clear()
	# A new campaign is a different campaign, so it fights different dice.
	campaign_seed = _mint_campaign_seed()
	save()
	print("[Sandline] new campaign, seed %d" % campaign_seed)
	return true


## The whole war, written out. Everything the campaign remembers - the
## soldiers and their records, the dead, the adversary files, the district's
## opinion settlement by settlement, the notebook - composed as one document.
## The thesis of the campaign is that it remembers; this is the page that
## proves it, and user://chronicle.txt is the copy the player can keep.
func chronicle() -> String:
	var lines: Array[String] = []
	lines.append("SANDLINE - THE CAMPAIGN'S LEDGER")
	lines.append("campaign %d - %s, mission %d of %d - %d attempt(s) spent"
			% [campaign_seed, str(operation().name), mission_number(),
					mission_count(), mission_attempts])
	lines.append("")
	lines.append("THE SQUAD")
	for soldier: Dictionary in roster:
		var perk_names: Array[String] = []
		for perk: String in soldier.get("perks", []):
			perk_names.append(str(PERKS[perk].name))
		var marks: Array[String] = []
		if not bool(soldier.alive):
			marks.append("KILLED IN ACTION")
		elif bool(soldier.get("wounded", false)):
			marks.append("walking wounded")
		if int(soldier.get("presence", 0)) > 0:
			marks.append("presence %d" % int(soldier.presence))
		if int(soldier.get("guile", 0)) > 0:
			marks.append("guile %d" % int(soldier.guile))
		var worn: Array[String] = []
		for slot: String in Gear.SLOTS:
			var key := str((soldier.get("gear", {}) as Dictionary).get(slot, ""))
			if Gear.ITEMS.has(key):
				worn.append(str(Gear.ITEMS[key].name))
		if not worn.is_empty():
			marks.append("carries " + ", ".join(worn))
		lines.append("  %-16s %-18s %-16s %3d xp%s%s" % [
				full_name(soldier), Unit.kind_role_name(int(soldier.kind)),
				Career.level_label(int(soldier.get("level", 1))), int(soldier.xp),
				"  " + ", ".join(perk_names) if not perk_names.is_empty() else "",
				"  [" + "; ".join(marks) + "]" if not marks.is_empty() else ""])
	if not district_standing.is_empty():
		lines.append("")
		lines.append("THE DISTRICT'S OPINION")
		for settlement: String in district_standing:
			lines.append("  %-16s %d" % [settlement, int(district_standing[settlement])])
	lines.append("  theater strain     %d" % alliance_strain)
	if not adversaries.is_empty():
		lines.append("")
		lines.append("THE FILES")
		for rec: Dictionary in adversaries:
			var state := str(rec.get("state", ""))
			lines.append("  %s%s" % [adversary_line(rec),
					"" if state.is_empty() else "  (%s)" % state])
	if not informants.is_empty():
		lines.append("")
		lines.append("THE TURNED")
		for rec: Dictionary in informants:
			lines.append("  %s of %s" % [str(rec.get("name", "")),
					str(rec.get("settlement", ""))])
	if not ratline_done.is_empty() or ratline_strength != 0:
		lines.append("")
		lines.append("THE RATLINE")
		lines.append("  %d of 3 crossings run down this stay%s" % [
				ratline_done.size(),
				"" if ratline_strength == 0
						else " - the Thirst musters at %d%%" % ratline_strength])
	if scrip > 0 or not armory.is_empty():
		lines.append("")
		lines.append("THE COMPANY BOOK: %d scrip, %d item(s) in the armory"
				% [scrip, armory.size()])
		var shelved: Array[String] = []
		for key: String in armory:
			shelved.append(str(Gear.ITEMS[key].name))
		if not shelved.is_empty():
			lines.append("  on the rack: %s" % ", ".join(shelved))
	var by_settlement := notebook_by_settlement()
	if not by_settlement.is_empty():
		lines.append("")
		lines.append("DAVA'S NOTEBOOK")
		for settlement: String in by_settlement:
			lines.append("  %s:" % settlement)
			for entry: Dictionary in by_settlement[settlement]:
				lines.append("    %s, %s" % [str(entry.get("name", "")),
						str(entry.get("fate", ""))])
	return "\n".join(lines)


## The chronicle, cut down to what a modal can hold: the counts and the names
## that matter. The full document is the file.
func chronicle_digest() -> String:
	var alive := 0
	var dead: Array[String] = []
	for soldier: Dictionary in roster:
		if bool(soldier.alive):
			alive += 1
		else:
			dead.append(full_name(soldier))
	var lines: Array[String] = [
		campaign_summary(),
		"%d attempt(s) spent, %d soldier(s) standing" % [mission_attempts, alive],
	]
	if not dead.is_empty():
		lines.append("The dead: %s." % ", ".join(dead))
	if not adversaries.is_empty():
		lines.append("%d name(s) in the files, %d turned."
				% [adversaries.size(), informants.size()])
	if scrip > 0:
		lines.append("%d scrip in the company book." % scrip)
	if not district_standing.is_empty():
		var parts: Array[String] = []
		for settlement: String in district_standing:
			parts.append("%s %d" % [settlement, int(district_standing[settlement])])
		lines.append("Standing: %s." % ", ".join(parts))
	return "\n".join(lines)


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
	# Deliberately does NOT touch scrip or the armory: the loop throws the
	# squad away, but the company book belongs to the war, not the soldiers.
	# Only new_campaign() wipes the book.
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
		# Without this line the snapshot's gear dict is the LIVE soldier's gear
		# dict, and a mid-mission equip would survive the rollback that is this
		# copy's whole reason to exist. Same trap perks fell into above.
		copy.gear = (soldier.get("gear", {}) as Dictionary).duplicate()
		out.append(copy)
	return out


## Snapshot the squad so a failed mission can be rolled back wholesale.
## Deliberately does NOT clear pending_promotions: nothing queues a promotion
## during a mission (only commit_mission does, at the end of one), so anything
## still queued here is an unspent pick carried in from the last debrief, and
## commit_mission only ever queues newly-crossed gates - it can never re-offer
## one. Clearing here silently destroyed the pick of anyone who walked to the
## briefing table instead of to the promoted soldier. Camp._on_choice removes
## each entry as it is spent.
# Who actually walked out the gate this mission: soldier ids, stamped by
# Battle as it spawns them. Mission-scoped like mission_xp - reset on load
# rather than persisted - and what commit_mission reads to heal the wounded
# who sat the mission out.
var mission_fielded: Array = []


## A mission ended with this soldier badly hurt: below half. He deploys a
## point of max HP short until he sits a mission out or the squad makes it
## home to the garrison. Stamped only on a WON mission - a lost attempt rolls
## back wholesale, wounds included, exactly like the deaths.
func mark_wounded(id: int) -> void:
	var soldier := soldier_by_id(id)
	if soldier.is_empty():
		return
	soldier.wounded = true
	print("[Sandline] %s is walking wounded" % soldier.surname)


func begin_mission() -> void:
	_snapshot = _deep_copy(roster)
	mission_xp.clear()
	mission_dead.clear()
	mission_fielded.clear()
	mission_scrip = 0
	mission_loot = []


func award(id: int, amount: int) -> void:
	var soldier := soldier_by_id(id)
	if soldier.is_empty() or amount <= 0:
		return
	soldier.xp = int(soldier.xp) + amount
	mission_xp[id] = int(mission_xp.get(id, 0)) + amount


## Pay earned this mission, not yet the company's. Banked by the win sites.
func accrue_scrip(amount: int) -> void:
	if amount > 0:
		mission_scrip += amount


## An item shaken loose this mission, not yet the armory's. Unknown keys are
## refused here rather than at the bank, so a bad drop is loud where it rolls.
func accrue_loot(key: String) -> void:
	if Gear.ITEMS.has(key):
		mission_loot.append(key)
	elif not key.is_empty():
		push_error("[Sandline] no such item to loot: %s" % key)


## The soldier level the quartermaster's rack unlocks against: the highest
## LIVING soldier's, so a dead veteran's ghost does not keep tier 3 open.
func best_living_level() -> int:
	var best := 1
	for soldier: Dictionary in roster:
		if bool(soldier.get("alive", false)):
			best = maxi(best, int(soldier.get("level", 1)))
	return best


## Sign for an item at the quartermaster: known key, its tier unlocked by the
## best living soldier's level, and the book can cover it. Into the armory,
## not onto anybody - equipping is its own decision.
func buy_item(key: String) -> bool:
	if not Gear.ITEMS.has(key):
		return false
	if best_living_level() < Gear.level_gate(key):
		return false
	var price := int(Gear.ITEMS[key].price)
	if scrip < price:
		return false
	scrip -= price
	armory.append(key)
	print("[Sandline] signed for %s - %d scrip left in the book"
			% [str(Gear.ITEMS[key].name), scrip])
	save()
	return true


## Put an armory item on a soldier ("" unequips the slot). The item must be
## on the shelf, match the slot, and sit at a tier the SOLDIER's own level
## has earned; whatever he was carrying goes back to the shelf. One item, one
## body: equipping removes it from the armory, so two soldiers can only carry
## two sights if the book paid for two.
func equip_item(id: int, slot: String, key: String) -> bool:
	if not Gear.SLOTS.has(slot):
		return false
	var soldier := soldier_by_id(id)
	if soldier.is_empty() or not bool(soldier.get("alive", false)):
		return false
	if not key.is_empty():
		if not armory.has(key):
			return false
		if str(Gear.ITEMS[key].slot) != slot:
			return false
		if int(soldier.get("level", 1)) < Gear.level_gate(key):
			return false
	if not soldier.has("gear"):
		soldier.gear = {"weapon": "", "armor": "", "kit": ""}
	var gear: Dictionary = soldier.gear
	var worn := str(gear.get(slot, ""))
	if worn == key:
		return false
	if not worn.is_empty():
		armory.append(worn)
	if not key.is_empty():
		armory.erase(key)
	gear[slot] = key
	print("[Sandline] %s %s %s" % [soldier.surname,
			"sets down" if key.is_empty() else "takes",
			str(Gear.ITEMS[worn if key.is_empty() else key].name)])
	save()
	return true


## Move the mission's pay into the company book. Called from exactly the
## three win sites - commit_mission, finish_bounty, finish_interdiction -
## before their save(), and nowhere else: the loss paths just zero the
## scratch, which is the whole exploit-proofing.
func _bank_rewards() -> void:
	if mission_scrip > 0:
		scrip += mission_scrip
		print("[Sandline] %d scrip to the company book (%d held)"
				% [mission_scrip, scrip])
	for key: String in mission_loot:
		armory.append(key)
		print("[Sandline] %s signed into the armory" % str(Gear.ITEMS[key].name))
	mission_scrip = 0
	mission_loot = []


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
	var candidates := _rested_out(rifle_candidates(), slots)
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

## Rebuild the adversary roster from a save, field by field.
##
## Same discipline as _read_notebook and the same reason, only more so: these
## records go straight to a spawner AND carry a survival count that feeds a
## rule. An id that collides, a kind that is not one of the Thirst, or a
## negative survival count would all be adopted verbatim otherwise.
## Two shapes the v7 lists come in, sanitised the way every other loaded list
## is: whatever is on disk is somebody else's data until it has been checked.
func _read_int_list(raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for entry: Variant in raw:
		var value := int(entry)
		if value > 0 and not out.has(value):
			out.append(value)
	return out


func _read_dict_list(raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for entry: Variant in raw:
		if typeof(entry) == TYPE_DICTIONARY:
			out.append(entry)
	return out


func _read_adversaries(raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	var seen: Array[int] = []
	for row: Variant in raw:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var rec: Dictionary = row
		var id := int(rec.get("id", 0))
		var kind := int(rec.get("kind", -1))
		if id <= 0 or seen.has(id) or not GOBLIN_KINDS.has(kind):
			continue
		seen.append(id)
		var history: Array = []
		for step: Variant in rec.get("history", []):
			if typeof(step) != TYPE_DICTIONARY:
				continue
			history.append({
				"level": int(step.get("level", 0)),
				"fate": str(step.get("fate", "")),
			})
		out.append({
			"id": id,
			"name": str(rec.get("name", "")),
			"age": int(rec.get("age", 0)),
			"settlement": str(rec.get("settlement", "")),
			"grievance": str(rec.get("grievance", "")),
			"kind": kind,
			"survivals": maxi(int(rec.get("survivals", 0)), 0),
			"injuries": maxi(int(rec.get("injuries", 0)), 0),
			"state": str(rec.get("state", "escaped")),
			"edge": str(rec.get("edge", "")),
			"history": history,
			"last_level": int(rec.get("last_level", 0)),
		})
	return out


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


# --- The ones who keep coming back -------------------------------------------
#
# The notebook is the document: append-only, one line per person per mission,
# never revised. This is the other thing - a roster of the living, keyed by a
# person rather than by an appearance, which is what a rising survival chance
# and a logged history both need. A man who runs at Dry Wash, is left for dead
# at Outpost 7 and turns up again at the Cistern is ONE row here and three lines
# there, and that is the correct division: the document records what happened,
# this records who is still out there.

## How often somebody still out there turns up on a given later mission.
const RETURN_CHANCE := 45

## How often a man who could gather a warband actually brings one. Well under
## the individual return chance on purpose: four named fighters arriving as a
## fireteam should be something the campaign does to you a couple of times, not
## the standard shape of a mission's back half.
const WARBAND_CHANCE := 35
## Mirrors of Rules.WARBAND_* - see the layering note at the top of Rules'
## morale section. This file may not name Rules (Rules names Unit, Unit names
## this autoload, and the -s harnesses load all three before the autoloads
## exist), so the numbers are written twice and tools/test_rules.gd asserts the
## two copies agree. Do not "fix" this by importing Rules.
const WARBAND_LEADER_SURVIVALS := 2
const WARBAND_MEMBER_SURVIVALS := 1
const WARBAND_SIZE := 4


## Find the standing record for a person, or -1.
func _adversary_index(id: int) -> int:
	for i in adversaries.size():
		if int(adversaries[i].get("id", 0)) == id:
			return i
	return -1


## Write down that somebody walked away from a mission, minting them a lasting
## identity the first time it happens.
##
## `fate` is "escaped" (his nerve went and he made the rim) or "injured" (the
## squad put him down and he got up again). Both count as surviving, and both
## make him harder to finish next time; only the second costs him health.
##
## Returns the adversary id, so Battle can stamp it on the body if he is still
## on the board.
func remember_survivor(identity: Dictionary, kind: int, fate: String,
		level: int, edge: String, existing_id := 0) -> int:
	var idx := _adversary_index(existing_id) if existing_id > 0 else -1
	if idx < 0:
		var minted := {
			"id": _next_adversary_id,
			"name": str(identity.get("name", "")),
			"age": int(identity.get("age", 0)),
			"settlement": str(identity.get("settlement", "")),
			"grievance": str(identity.get("grievance", "")),
			"kind": kind,
			"survivals": 0,
			"injuries": 0,
			"state": fate,
			"edge": edge,
			"history": [],
			"last_level": level,
		}
		_next_adversary_id += 1
		adversaries.append(minted)
		idx = adversaries.size() - 1
	var rec: Dictionary = adversaries[idx]
	rec["survivals"] = int(rec.get("survivals", 0)) + 1
	if fate == "injured":
		rec["injuries"] = int(rec.get("injuries", 0)) + 1
	rec["state"] = fate
	rec["last_level"] = level
	if edge != "":
		rec["edge"] = edge
	var history: Array = rec.get("history", [])
	history.append({"level": level, "fate": fate})
	rec["history"] = history
	return int(rec["id"])


## Everything the campaign knows about one adversary, as prose the game can
## show. This is the "logged history" the whole feature exists for - without it
## a returning fighter is just a goblin with an unusual name.
func adversary_line(rec: Dictionary) -> String:
	var bits: PackedStringArray = []
	for step: Dictionary in rec.get("history", []):
		var lvl := int(step.get("level", 0))
		var where := "?"
		if lvl >= 0 and lvl < Levels.LEVELS.size():
			where = str(Levels.LEVELS[lvl].name)
		bits.append("%s at %s" % [
			"ran" if str(step.get("fate", "")) == "escaped" else "left for dead",
			where])
	return "%s of %s - %s" % [str(rec.get("name", "")),
			str(rec.get("settlement", "")), ", then ".join(bits)]


## Who might walk back onto THIS mission.
##
## Deterministic, and deliberately not a draw from any generator. Battle's
## _rules_rng advances exactly once per shot so that a seed replays a mission
## shot for shot; taking a variable number of draws here - one per survivor the
## campaign happens to have accumulated - would shift every roll in the mission
## by an amount depending on campaign history. Roll.identity has the same
## discipline for the same reason.
##
## Sorted by how much history they have, most first, because the slice Battle
## takes is small and the interesting man is the one the squad has met twice.
## Left unsorted this returned them in the order they were first met, so the
## earliest escapee crowded out every later one for the rest of the campaign.
##
## Only survivors of WON missions are here: a lost mission is rolled back
## wholesale and its roll dies with the scene.
func adversaries_for(level: int) -> Array:
	var out: Array = []
	for rec: Dictionary in adversaries:
		if int(rec.get("kind", -1)) < 0:
			continue
		# Nobody returns to the mission he left, or to one already behind us.
		if int(rec.get("last_level", 0)) >= level:
			continue
		if Roll.chance(campaign_seed, level, "adv:%d" % int(rec.get("id", 0)),
				RETURN_CHANCE):
			out.append(rec)
	out.sort_custom(func(a, b): return int(a.get("survivals", 0)) 			> int(b.get("survivals", 0)))
	return out


## Everybody eligible to walk back onto this mission, whether or not the return
## roll picked them. Warbands draw from here rather than from adversaries_for(),
## because a warband is a decision its leader made and not four coincidences:
## requiring all four to independently pass the return roll would have made a
## full band vanishingly rare, and the ones that did form would be random
## strangers rather than the people he keeps.
func _available_adversaries(level: int) -> Array:
	var out: Array = []
	for rec: Dictionary in adversaries:
		if int(rec.get("kind", -1)) < 0:
			continue
		if int(rec.get("last_level", 0)) >= level:
			continue
		out.append(rec)
	return out


## The warband coming to this mission, or {} for none.
##
## A leader is somebody who has walked away from this squad at least twice; his
## people have managed it at least once. The whole group is decided from the
## campaign seed and the level, never from an RNG, for the reason every other
## pre-mission decision is: a reloaded mission has to play out the same way, and
## Battle's rules stream advances once per shot so that a seed replays a
## firefight exactly. A draw here would shift every roll in the mission by an
## amount depending on how much campaign history happened to exist.
##
## Returns {"leader": rec, "members": [rec, rec, rec]}. Members exclude the
## leader, so the band on the board is members.size() + 1.
func warband_for(level: int) -> Dictionary:
	var pool := _available_adversaries(level)
	var leaders: Array = []
	for rec: Dictionary in pool:
		if int(rec.get("survivals", 0)) >= WARBAND_LEADER_SURVIVALS:
			leaders.append(rec)
	if leaders.is_empty():
		return {}
	# The most experienced man present leads, ties broken by id so the answer
	# cannot depend on the order records happen to sit in the save.
	leaders.sort_custom(func(a, b):
		var sa := int(a.get("survivals", 0))
		var sb := int(b.get("survivals", 0))
		if sa != sb:
			return sa > sb
		return int(a.get("id", 0)) < int(b.get("id", 0)))
	var leader: Dictionary = leaders[0]
	var leader_id := int(leader.get("id", 0))
	if not Roll.chance(campaign_seed, level, "warband:%d" % leader_id,
			WARBAND_CHANCE):
		return {}
	var followers: Array = []
	for rec: Dictionary in pool:
		if int(rec.get("id", 0)) == leader_id:
			continue
		if int(rec.get("survivals", 0)) >= WARBAND_MEMBER_SURVIVALS:
			followers.append(rec)
	followers.sort_custom(func(a, b):
		var sa := int(a.get("survivals", 0))
		var sb := int(b.get("survivals", 0))
		if sa != sb:
			return sa > sb
		return int(a.get("id", 0)) < int(b.get("id", 0)))
	# A band that cannot be filled does not form. Three is what the leader went
	# looking for; two men and a story is just a returner with company, and the
	# arrival banner would be promising something the board does not deliver.
	var want := WARBAND_SIZE - 1
	if followers.size() < want:
		return {}
	return {"leader": leader, "members": followers.slice(0, want)}


## The people a given leader can hold, for a bounty that has found him.
##
## Deliberately NOT warband_for(): that decides whether a band turns up on a
## CAMPAIGN mission, and rolls for it. On a bounty the question is already
## settled - the squad has walked to where he lives and he is either a man with
## people or a man alone - so this only asks who qualifies.
func warband_members_for(leader_id: int) -> Array:
	var out: Array = []
	for rec: Dictionary in adversaries:
		if int(rec.get("id", 0)) == leader_id:
			continue
		if int(rec.get("kind", -1)) < 0:
			continue
		if int(rec.get("survivals", 0)) >= WARBAND_MEMBER_SURVIVALS:
			out.append(rec)
	out.sort_custom(func(a, b):
		var sa := int(a.get("survivals", 0))
		var sb := int(b.get("survivals", 0))
		if sa != sb:
			return sa > sb
		return int(a.get("id", 0)) < int(b.get("id", 0)))
	return out.slice(0, WARBAND_SIZE - 1)


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
	# A rest is one main mission long, and this is the line that makes that
	# true. Cleared before the promotions below so that a soldier who was
	# resting is available again the moment this mission is in the books.
	if not resting_ids.is_empty():
		print("[Sandline] %d soldier(s) come off rest" % resting_ids.size())
		resting_ids.clear()
	for soldier: Dictionary in roster:
		if not bool(soldier.alive):
			continue
		var old_level := int(soldier.get("level", 1))
		var new_level := Career.level_for_xp(int(soldier.xp))
		if new_level <= old_level:
			continue
		soldier.level = new_level
		print("[Sandline] %s reaches %s" % [soldier.surname, Career.level_label(new_level)])
		# Only the perk gates queue a choice - every other level pays its stat
		# point silently. A soldier who crosses two gates in one mission still
		# gets both picks; the queue stays sparse because gates_crossed() can
		# only ever answer with a subset of the four gate levels.
		for gate_level: int in Career.gates_crossed(old_level, new_level):
			if not perk_choices(int(soldier.kind),
					Career.perk_gate(gate_level)).is_empty():
				pending_promotions.append({"id": int(soldier.id), "level": gate_level})
	# The wound ledger's other half: a soldier who sat this one out has had a
	# mission's worth of the medic's time, and comes back whole. Deploying
	# wounded was the player's call; healing is what sitting out is FOR.
	for soldier: Dictionary in roster:
		if bool(soldier.alive) and bool(soldier.get("wounded", false)) \
				and not mission_fielded.has(int(soldier.id)):
			soldier.wounded = false
			print("[Sandline] %s is off the wounded list" % soldier.surname)
	_bank_rewards()
	_snapshot.clear()
	save()


## Mission lost, retried, or abandoned via the level buttons: put the squad back
## exactly as it was when the mission started, XP and casualties included.
func abort_mission() -> void:
	# A lost or abandoned generated mission must not leave its board installed:
	# data() would keep returning it and camp would deploy straight back into
	# it. Cleared here rather than at the call sites so every abort path - the
	# loss screen, the debug level jumps, whatever comes third - is covered.
	# Clearing state is not settling the offer: a lost bounty stays postable
	# and a lost crossing stays open.
	clear_bounty()
	clear_interdiction()
	if _snapshot.is_empty():
		return
	roster = _deep_copy(_snapshot)
	# Same reasoning as begin_mission: the queue can only hold carry-over from
	# an earlier debrief, and the snapshot being restored already contains the
	# XP that earned it, so the pick is still owed. Clearing it here lost the
	# perk of anyone who deployed with one unspent and then lost the mission.
	mission_xp.clear()
	mission_dead.clear()
	# The pay dies with the attempt, exactly like the XP above it.
	mission_scrip = 0
	mission_loot = []
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
# back as a float, and a level that loads as 3.0 breaks the integer
# comparisons in Career.level_for_xp in ways that are miserable to track down.
# So nothing is read
# back raw - every field is coerced through int()/bool()/str() below.


const SAVE_PATH := "user://campaign.json"
# Raise this in the same commit that adds the migration step reaching it, and
# never one without the other - _migrate_step() is what turns a number into a
# shape the rest of this file can read.
const SAVE_VERSION := 11

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
		"adversaries": adversaries,
		"adversary_endings": adversary_endings,
		"next_adversary_id": _next_adversary_id,
		# v7: bounties. The generated board is NOT here - it is derivable from
		# the campaign seed and the target, so only what happened is kept.
		"bounties_done": bounties_done,
		"informants": informants,
		"bounty_outcomes": bounty_outcomes,
		"resting_ids": resting_ids,
		# v9: the ratline. The generated board is NOT here - derivable, like
		# a bounty's - so only which crossings were run down and what the
		# operation locked are kept.
		"ratline_done": ratline_done,
		"ratline_strength": ratline_strength,
		# v10: the company book. Each soldier's level and gear ride the roster
		# entries; these two are the campaign's shared half.
		"scrip": scrip,
		"armory": armory,
		# v4: who the garrison picked.
		"deployed_ids": deployed_ids,
	}
	# Written to a sibling and renamed into place, never straight over the only
	# copy. A crash or power cut mid-store_string used to truncate
	# campaign.json - and the migration ladder is version-shaped, not
	# corruption-shaped: it cannot help a half-written file. The rename is the
	# atomic step; worst case now is a stale save plus an orphaned .tmp, never
	# a lost campaign.
	var tmp_path := SAVE_PATH + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_error("[Sandline] cannot write %s: %s" % [
				tmp_path, error_string(FileAccess.get_open_error())])
		return
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	var dir := DirAccess.open("user://")
	if dir == null:
		push_error("[Sandline] cannot open user:// to finish the save")
		return
	var err := dir.rename(tmp_path.get_file(), SAVE_PATH.get_file())
	if err != OK:
		push_error("[Sandline] cannot move %s into place: %s"
				% [tmp_path, error_string(err)])


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
		5:
			return _migrate_5_to_6(payload)
		6:
			return _migrate_6_to_7(payload)
		7:
			return _migrate_7_to_8(payload)
		8:
			return _migrate_8_to_9(payload)
		9:
			return _migrate_9_to_10(payload)
		10:
			return _migrate_10_to_11(payload)
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


## v6: survivors became people rather than appearances.
##
## A campaign already in flight is not thrown away. Every escapee the v5
## notebook recorded well enough to rebuild - one that carries a kind - becomes
## a standing adversary with that one line of history already on it, so a save
## mid-campaign keeps the men it has met instead of starting the ledger empty.
## Rows that predate v5 have no kind and are skipped, because there is no honest
## way to know what they were carrying.
func _migrate_5_to_6(payload: Dictionary) -> Dictionary:
	var built: Array = []
	var next_id := 1
	var already: Array = payload.get("returned", []) if typeof(
			payload.get("returned", [])) == TYPE_ARRAY else []
	for row: Variant in payload.get("notebook", []):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = row
		if str(entry.get("fate", "")) != "escaped":
			continue
		if int(entry.get("kind", -1)) < 0:
			continue
		var level := int(entry.get("level", 0))
		built.append({
			"id": next_id,
			"name": str(entry.get("name", "")),
			"age": int(entry.get("age", 0)),
			"settlement": str(entry.get("settlement", "")),
			"grievance": str(entry.get("grievance", "")),
			"kind": int(entry.get("kind", -1)),
			"survivals": 1,
			"injuries": 0,
			"state": "escaped",
			"edge": str(entry.get("edge", "")),
			"history": [{"level": level, "fate": "escaped"}],
			# Somebody v5 had already sent back does not queue up again for a
			# mission he has already been to.
			"last_level": level,
		})
		next_id += 1
	payload["adversaries"] = built
	payload["next_adversary_id"] = next_id
	# `returned` was v5's way of saying "already used"; the record carries its
	# own last_level now, so the list stops meaning anything. Kept on disk
	# rather than dropped, so a save that climbs can still be read by eye.
	payload["returned"] = already
	return payload


## v6 -> v7: soldiers learn to talk, and the campaign starts keeping bounties.
##
## Nothing is invented. Every existing soldier gets PRESENCE and GUILE of zero,
## which is exactly what a fresh recruit gets - a campaign that has never posted
## a bounty has had no way to earn either, so zero is the truthful number rather
## than a default. The three bounty lists start empty for the same reason.
func _migrate_6_to_7(payload: Dictionary) -> Dictionary:
	var roster_raw: Variant = payload.get("roster", [])
	if typeof(roster_raw) == TYPE_ARRAY:
		for entry: Variant in roster_raw:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var soldier: Dictionary = entry
			soldier["presence"] = maxi(int(soldier.get("presence", 0)), 0)
			soldier["guile"] = maxi(int(soldier.get("guile", 0)), 0)
	payload["bounties_done"] = payload.get("bounties_done", [])
	payload["informants"] = payload.get("informants", [])
	payload["bounty_outcomes"] = payload.get("bounty_outcomes", [])
	payload["resting_ids"] = payload.get("resting_ids", [])
	return payload


## v8 adds the wound ledger: a named soldier can come out of a mission
## walking wounded, and the flag rides the roster entry like everything else
## about him. Old saves carry nobody wounded, which is also what a missing
## key means on read - so this rung only has to exist to stamp the version.
## v9 adds the ratline: which of the garrison's interdiction offers were run
## down, and the muster strength the operation locked. Materialising both
## keys is the reshape itself - an old save has run nothing down and locked
## nothing, which is exactly what these say - and it is what keeps the
## ladder's no-gaps check honest about this rung.
func _migrate_8_to_9(payload: Dictionary) -> Dictionary:
	payload["ratline_done"] = payload.get("ratline_done", [])
	payload["ratline_strength"] = int(payload.get("ratline_strength", 0))
	return payload


func _migrate_7_to_8(payload: Dictionary) -> Dictionary:
	# The reshape is the promise itself: v8 has a roster array whose entries
	# carry a wounded boolean. Materialising the key is what keeps the
	# ladder's no-gaps check honest about this rung doing real work.
	payload["roster"] = payload.get("roster", [])
	if typeof(payload.roster) == TYPE_ARRAY:
		for entry: Variant in payload.roster:
			if typeof(entry) == TYPE_DICTIONARY:
				(entry as Dictionary)["wounded"] = bool(
						(entry as Dictionary).get("wounded", false))
	return payload


## v10 retires the military ranks for the 1..100 career ladder. Each soldier's
## level is recomputed from the XP he already earned - the rank field is not
## consulted, because XP was always the ground truth the ranks were derived
## from - and the rank key is erased. Queued promotions translate rank 1..4
## onto the four gate levels; anything else in the queue is dropped. An honest
## reshape, documented here: a migrated veteran keeps every perk already taken
## and every queued pick, even where his recomputed level sits below the gate
## that would have offered it - what was earned stays earned.
## v11 adds the closed files. An old save has closed none - not because it
## behaved differently, but because the build that wrote it had no way to close
## one - so the honest reshape is an empty list. Inventing endings for men the
## campaign never settled would be the lie _migrate_2_to_3 and _migrate_4_to_5
## both refuse to tell; the men themselves are still in `adversaries` where
## that save left them, and the first won mission that accounts for one will
## write the first ending.
func _migrate_10_to_11(payload: Dictionary) -> Dictionary:
	payload["adversary_endings"] = payload.get("adversary_endings", [])
	return payload


func _migrate_9_to_10(payload: Dictionary) -> Dictionary:
	payload["roster"] = payload.get("roster", [])
	if typeof(payload.roster) == TYPE_ARRAY:
		for entry: Variant in payload.roster:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var soldier: Dictionary = entry
			soldier["level"] = maxi(Career.level_for_xp(int(soldier.get("xp", 0))), 1)
			soldier.erase("rank")
			soldier["gear"] = {"weapon": "", "armor": "", "kit": ""}
	var translated: Array = []
	var raw_pending: Variant = payload.get("pending_promotions", [])
	if typeof(raw_pending) == TYPE_ARRAY:
		for entry: Variant in raw_pending:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var promotion: Dictionary = entry
			var rank := int(promotion.get("rank", 0))
			if rank >= 1 and rank <= Career.PERK_LEVELS.size():
				translated.append({"id": int(promotion.get("id", 0)),
						"level": Career.PERK_LEVELS[rank - 1]})
	payload["pending_promotions"] = translated
	payload["scrip"] = 0
	payload["armory"] = []
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
	adversaries = _read_adversaries(payload.get("adversaries", []))
	adversary_endings = _read_dict_list(payload.get("adversary_endings", []))
	bounties_done = _read_int_list(payload.get("bounties_done", []))
	informants = _read_dict_list(payload.get("informants", []))
	bounty_outcomes = _read_dict_list(payload.get("bounty_outcomes", []))
	# Defaults to nobody resting, which is why this needed no version of its
	# own: a save written before rests existed is a save where nobody is on one.
	resting_ids = _read_int_list(payload.get("resting_ids", []))
	# Not _read_int_list: that reader is for id lists and drops zero, and the
	# first crossing on the net is ordinal 0.
	ratline_done = []
	var raw_ratline: Variant = payload.get("ratline_done", [])
	if typeof(raw_ratline) == TYPE_ARRAY:
		for entry: Variant in raw_ratline:
			var ordinal := int(entry)
			if ordinal >= 0 and not ratline_done.has(ordinal):
				ratline_done.append(ordinal)
	ratline_strength = int(payload.get("ratline_strength", 0))
	# 0 stays the unlocked sentinel; anything locked is clamped so a
	# hand-edited 40 cannot halve an operation.
	if ratline_strength != 0:
		ratline_strength = clampi(ratline_strength, 80, 115)
	# The v10 fields. Scrip floored at 0 - a hand-edited debt is not a
	# mechanic - and the armory whitelisted key by key.
	scrip = maxi(int(payload.get("scrip", 0)), 0)
	armory = _read_armory(payload.get("armory", []))
	# A bounty in progress is never resumed: the board is regenerated at the
	# notice board, and a save written mid-bounty should come back to a garrison
	# rather than to half a mission. An interdiction gets the same treatment
	# for the same reason.
	clear_bounty()
	clear_interdiction()
	_next_adversary_id = maxi(int(payload.get("next_adversary_id", 1)), 1)
	for rec: Dictionary in adversaries:
		_next_adversary_id = maxi(_next_adversary_id, int(rec.get("id", 0)) + 1)
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
	mission_scrip = 0
	mission_loot = []
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
	# Through user:// directly rather than a globalized absolute path - same
	# operation, but portable to every platform Godot resolves user:// on.
	var dir := DirAccess.open("user://")
	var err := dir.remove(SAVE_PATH.get_file()) if dir != null else FAILED
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
		# Gear is rebuilt slot by slot: an empty string stays, a key the catalog
		# knows AND that names this slot stays, and anything else - a deleted
		# item, a hand-edited weapon in the kit slot - silently becomes "".
		var gear := {}
		var raw_gear: Variant = soldier.get("gear", {})
		for slot: String in Gear.SLOTS:
			var key := str((raw_gear as Dictionary).get(slot, "")) \
					if typeof(raw_gear) == TYPE_DICTIONARY else ""
			gear[slot] = key if Gear.ITEMS.has(key) \
					and str(Gear.ITEMS[key].slot) == slot else ""
		out.append({
			"id": id,
			"surname": str(soldier.get("surname", "SCOUT-%d" % id)),
			"kind": int(soldier.get("kind", Unit.Kind.SCOUT)),
			"xp": maxi(int(soldier.get("xp", 0)), 0),
			"level": clampi(int(soldier.get("level", 1)), 1, Career.MAX_LEVEL),
			"gear": gear,
			"perks": perks,
			"alive": bool(soldier.get("alive", true)),
			# Floored at 0 rather than trusted: these drive negotiation odds,
			# and a hand-edited save should not be able to hand somebody a
			# guaranteed informant.
			"presence": maxi(int(soldier.get("presence", 0)), 0),
			"guile": maxi(int(soldier.get("guile", 0)), 0),
			"wounded": bool(soldier.get("wounded", false)),
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
		var gate_level := int(promotion.get("level", 0))
		# Drop anything that no longer names a living soldier, a level that is
		# not one of the four gates, or a gate that offers that soldier's class
		# no choice - otherwise the camp opens a modal it cannot fill. Runs
		# after the roster is adopted, so the kind lookup always sees the
		# loaded soldier. Deliberately does NOT require soldier.level >= the
		# gate: a migrated veteran's earned pick survives even where the
		# recomputed level sits below it (see _migrate_9_to_10).
		var soldier := soldier_by_id(id)
		if soldier.is_empty() or not bool(soldier.alive):
			continue
		if not Career.PERK_LEVELS.has(gate_level):
			continue
		if perk_choices(int(soldier.kind), Career.perk_gate(gate_level)).is_empty():
			continue
		var already_kept := false
		for kept: Dictionary in out:
			if int(kept.id) == id and int(kept.level) == gate_level:
				already_kept = true
				break
		if already_kept:
			continue
		out.append({"id": id, "level": gate_level})
	return out


## The armory list, rebuilt: only keys the catalog knows survive, and
## duplicates are KEPT - two bought slings are two slings.
func _read_armory(raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for entry: Variant in raw:
		var key := str(entry)
		if Gear.ITEMS.has(key):
			out.append(key)
	return out
