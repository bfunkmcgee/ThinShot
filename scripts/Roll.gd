class_name Roll

## Who the enemy was, one name at a time.
##
## Every fighter the Thirst puts on a map gets an identity the moment it spawns:
## a name, an age, the settlement it came from, and the line of provenance that
## explains why it walked forty miles to stand on a wash. None of it is visible
## during the contact - the squad is not being asked to hesitate, and a name
## floating over a target would be a mechanic. It is read out afterwards, on THE
## ROLL, where it cannot change a decision that has already been made.
##
## Two hard constraints shaped this file.
##
## FIRST: no RNG. Battle keeps two generators and only one of them is allowed to
## decide anything, so drawing a name from the rules stream would shift every
## shot in the mission and quietly make the campaign seed a lie. Identities come
## out of a hash of (seed, level, ordinal) instead. That also makes them
## reproducible for free: `-- --seed N` deals the same hand AND the same dead.
##
## SECOND: nothing from scripts/ in any signature. This is plain arithmetic over
## ints and strings, so tools running under `-s` can pin it before the autoloads
## exist - the trap tools/test_hero_gameover.gd documents at length.

# --- The Charter grievance ---------------------------------------------------
#
# The capping took four settlements off their water. Every fighter comes from
# one of them, and the provenance line is the settlement's, not the person's -
# which is the point. They are not individually aggrieved. They are the same
# people with the same complaint, filed the only way left to them after the
# Assembly's objection went nowhere.

const SETTLEMENTS: Array[Dictionary] = [
	{
		"name": "Ashet Draw",
		"grievance": "drew from the Ashet wells until the survey capped them",
	},
	{
		"name": "Bhorra Low",
		"grievance": "hauled water eleven miles a day after the Low ran dry",
	},
	{
		"name": "Kessit",
		"grievance": "signed the Assembly's objection and watched it filed",
	},
	{
		"name": "Vennet Rill",
		"grievance": "was born the year the Rill was surveyed and never saw it run",
	},
]

const GIVEN: Array[String] = [
	"Orrun", "Kesh", "Tammar", "Bel", "Ruk", "Ossa", "Hennik", "Marro",
	"Dell", "Sarra", "Vek", "Immet", "Tovar", "Nesh", "Bruk", "Alla",
	"Ferrin", "Wen", "Kado", "Rethe", "Sull", "Onna", "Garrit", "Ilse",
]

const FAMILY: Array[String] = [
	"Anhal", "Berrow", "Casst", "Dunmar", "Eshet", "Falk", "Gorrun", "Haist",
	"Ivrin", "Jesst", "Kalder", "Lom", "Merrick", "Noss", "Ovar", "Pell",
	"Quarr", "Reth", "Sable", "Torren", "Ulmet", "Varr", "Wesk", "Yarrow",
]

## Age bands by Unit.Kind ordinal. Raw ordinals for the no-imports rule above.
##
## These are characterisation done in numbers rather than in prose. The pressed
## conscript is somebody's son and the band says so; the well-hand is labour off
## a capped well and has been for twenty years; the marksman is the one of them
## who was trained, and is the age a man is when training took.
const AGE_BANDS := {
	3: [26, 54],  # GOBLIN         - well-hand, the settlement's working middle
	4: [19, 38],  # GOBLIN_SMG     - runner
	5: [18, 31],  # GOBLIN_SMG_ALT - light runner, chosen for being quick
	6: [16, 23],  # GOBLIN_REVOLVER - pressed conscript, and this is the point
	7: [24, 41],  # GOBLIN_BOLT    - marksman
}
const AGE_DEFAULT: Array[int] = [20, 45]


## A deterministic 32-bit mix of three ints. Not cryptography and not trying to
## be: it needs to decorrelate the four fields drawn from one ordinal so that
## consecutive spawns do not come out as consecutive names, and it needs to give
## the same answer on every platform and every run. Integer ops only, masked to
## 32 bits at every step so GDScript's 64-bit ints cannot let a shift carry
## something a different build would round away.
static func _mix(a: int, b: int, c: int) -> int:
	var h := (a & 0xFFFFFFFF) ^ ((b & 0xFFFFFFFF) * 0x9E3779B1 & 0xFFFFFFFF)
	h = (h ^ (c * 0x85EBCA6B)) & 0xFFFFFFFF
	h = (h ^ (h >> 15)) & 0xFFFFFFFF
	h = (h * 0x2545F491) & 0xFFFFFFFF
	h = (h ^ (h >> 13)) & 0xFFFFFFFF
	return h


## Who this one is. `seed` is the campaign's, `level` the mission index, and
## `ordinal` the unit's position in the level's spawn order - all three stable
## across a reload, which is what makes the same campaign re-fight the same
## mission against the same people.
##
## `kind` only picks the age band. Everything else is drawn the same way for
## everybody, because the Thirst does not recruit differently by weapon.
static func identity(seed: int, level: int, ordinal: int, kind: int) -> Dictionary:
	var g := _mix(seed, level * 977 + ordinal, 0x1B873593)
	var f := _mix(seed, level * 977 + ordinal, 0x27D4EB2F)
	var s := _mix(seed, level * 977 + ordinal, 0x165667B1)
	var a := _mix(seed, level * 977 + ordinal, 0x374761C7)
	var home: Dictionary = SETTLEMENTS[s % SETTLEMENTS.size()]
	var band: Array = AGE_BANDS.get(kind, AGE_DEFAULT)
	var lo: int = int(band[0])
	var hi: int = int(band[1])
	return {
		"name": "%s %s" % [GIVEN[g % GIVEN.size()], FAMILY[f % FAMILY.size()]],
		"age": lo + a % (hi - lo + 1),
		"settlement": str(home.name),
		"grievance": str(home.grievance),
	}


## A stable yes/no, out of a hash rather than a generator.
##
## `percent` is the chance of true. The same (seed, level, key) always answers
## the same way, which is the whole point: whether a man who ran comes back is
## decided by who he is and which mission this is, not by how many times the
## player has reloaded. Nothing here touches an RNG, for the reason identity()
## does not - see the note there.
static func chance(seed: int, level: int, key: String, percent: int) -> bool:
	return _mix(seed, level * 977 + hash(key), 0x9E3779B1) % 100 < percent


## A stable index into a list of `count`, out of the same hash.
##
## chance() answers yes or no; a generator needs "which one", and doing that as
## a run of chance() calls both biases the answer and costs a different number
## of draws per outcome. Same discipline as everything else here: no RNG, so a
## generated board is a function of the campaign and not of when you looked at
## it. Returns 0 for a non-positive count rather than dividing by zero.
static func pick(seed: int, level: int, key: String, count: int) -> int:
	if count <= 0:
		return 0
	return _mix(seed, level * 977 + hash(key), 0x27D4EB2F) % count


## One line of THE ROLL. `fate` is what became of them - "killed", "surrendered",
## "escaped" - and is the controller's word, not this file's.
static func line(identity: Dictionary, fate: String) -> String:
	if identity.is_empty():
		return fate.to_upper()
	return "%s, %d, of %s - %s" % [
		identity.get("name", "?"), int(identity.get("age", 0)),
		identity.get("settlement", "?"), fate,
	]
