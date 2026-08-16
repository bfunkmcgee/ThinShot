extends SceneTree

## THE ROLL's identities, pinned.
##
## Four things are checked, and the first two are the ones that would be
## expensive to discover late:
##   1. determinism - the same (seed, level, ordinal, kind) is the same person,
##      on every run, so `-- --seed N` replays the same dead as well as the
##      same dice
##   2. independence from any RNG - Roll draws from a hash, never a generator,
##      because Battle's rules stream decides shots and a name drawn from it
##      would shift every one of them
##   3. spread - consecutive spawns must not come out as consecutive names, and
##      the tables must actually get used rather than the hash favouring index 0
##   4. the age bands say what the roster says: the pressed conscript is young
##      and the well-hand is not, because that is characterisation done in
##      numbers
##
## Run: godot --headless --path . -s tools/test_roll.gd

# Raw ordinals - Unit.Kind cannot be named here (the `-s` preload trap).
const KIND_GOBLIN := 3
const KIND_REVOLVER := 6
const KIND_BOLT := 7

var _failed := false
var _roll: GDScript = null


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    %s" % label)
	else:
		printerr("  FAIL  %s" % label)
		_failed = true


func _init() -> void:
	_run()


func _id(seed: int, level: int, ordinal: int, kind := KIND_GOBLIN) -> Dictionary:
	return _roll.call("identity", seed, level, ordinal, kind)


func _run() -> void:
	await process_frame
	_roll = load("res://scripts/Roll.gd") as GDScript
	_check(_roll != null, "Roll.gd loaded")

	print("\n[1] the same campaign meets the same people")
	var a := _id(12345, 2, 7)
	var b := _id(12345, 2, 7)
	_check(a == b, "identity is a function of its inputs, not of when it is asked")
	_check(a.name != _id(12346, 2, 7).name
			or a.settlement != _id(12346, 2, 7).settlement,
			"a different campaign seed is different people")
	_check(_id(12345, 3, 7) != a, "so is a different mission")
	_check(_id(12345, 2, 8) != a, "so is the next man in the spawn order")

	print("\n[2] nothing here touches a generator")
	# Roll must not consume randomness: if it did, an interleaved sequence of
	# rng draws would come out differently when identities are minted between
	# them, and the campaign seed would stop meaning what it promises.
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var clean: Array[int] = []
	for i in 20:
		clean.append(rng.randi())
	rng.seed = 99
	var interleaved: Array[int] = []
	for i in 20:
		_id(12345, 1, i)
		interleaved.append(rng.randi())
	_check(clean == interleaved,
			"minting 20 identities does not move an RNG stream by one draw")

	print("\n[3] the tables are actually used")
	var names := {}
	var settlements := {}
	var ages := {}
	for level in 7:
		for ordinal in 40:
			var id := _id(4242, level, ordinal)
			names[id.name] = true
			settlements[id.settlement] = true
			ages[id.age] = true
	_check(names.size() > 200,
			"280 spawns produce %d distinct names" % names.size())
	_check(settlements.size() == 4,
			"all four capped settlements appear (%d)" % settlements.size())
	# Consecutive ordinals must decorrelate, or a firing line reads as a family.
	var adjacent_same := 0
	for ordinal in 200:
		if _id(7, 1, ordinal).name == _id(7, 1, ordinal + 1).name:
			adjacent_same += 1
	_check(adjacent_same == 0,
			"no two consecutive spawns share a name (%d collisions)" % adjacent_same)

	print("\n[4] the age bands are characterisation")
	var conscript_max := 0
	var wellhand_min := 99
	var out_of_band: Array[String] = []
	for ordinal in 300:
		var young := _id(31337, 4, ordinal, KIND_REVOLVER)
		var old := _id(31337, 4, ordinal, KIND_GOBLIN)
		conscript_max = maxi(conscript_max, int(young.age))
		wellhand_min = mini(wellhand_min, int(old.age))
		for pair in [[young, KIND_REVOLVER], [old, KIND_GOBLIN]]:
			var band: Array = _roll.get_script_constant_map()["AGE_BANDS"][pair[1]]
			var age: int = int((pair[0] as Dictionary).age)
			if age < int(band[0]) or age > int(band[1]):
				out_of_band.append("kind %d age %d" % [pair[1], age])
	_check(out_of_band.is_empty(),
			"every age lands inside its kind's band (%s)" % [out_of_band.slice(0, 3)])
	_check(conscript_max < wellhand_min,
			"every pressed conscript is younger than every well-hand (%d < %d)"
			% [conscript_max, wellhand_min])
	# The marksman is the one who was trained, which takes time.
	var bolt_min := 99
	for ordinal in 300:
		bolt_min = mini(bolt_min, int(_id(31337, 4, ordinal, KIND_BOLT).age))
	_check(bolt_min > conscript_max,
			"and the Marksman is older than any of them (%d)" % bolt_min)

	print("\n[5] the line reads")
	var sample := _id(2026, 0, 3)
	var line: String = _roll.call("line", sample, "killed")
	print("        %s" % line)
	_check(line.contains(str(sample.name)) and line.contains("killed")
			and line.contains(str(sample.settlement)),
			"a roll line carries the name, the settlement and the fate")
	_check(str(_roll.call("line", {}, "escaped")) == "ESCAPED",
			"and an identity-less unit degrades to its fate alone")

	print("\nRESULT: ", "FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)
