extends SceneTree

## The prop tables exist three times, and this asserts they agree.
##
## Battle.gd, Camp.gd and tools/render_board_preview.gd each carry their own
## copy of the prop offsets, hash salts, scatter rates and structure tables.
## That duplication is documented as deliberate - the two scenes are
## independent, and the preview mirrors Battle "kept in sync by hand" - but it
## has already produced one shipped bug (the preview's _v2i fix), and a copy
## that drifts fails SILENTLY: a prop lands two pixels off its cell in one
## scene, or the preview quietly stops drawing a structure kind Battle can.
##
## So the copies stay (that is the two scenes' charter) and this becomes the
## enforcement, exactly the way tools/test_rules.gd asserts the layering
## rule's literal mirrors: the numbers may exist twice, but the suite fails
## the moment the copies disagree.
##
## What is deliberately NOT compared, and why:
##   - Camp's JUNK_TEXTURES / PLANT_TEXTURES are documented SUBSETS of
##     Battle's (the car door stays on the battlefield; the camp plants are a
##     curated three). Subset-by-path is asserted, equality is not.
##   - Camp's stores/briefing/fixture tables are camp-only furniture with no
##     Battle counterpart.
##   - The preview's detritus list is built by a runtime _numbered() call, not
##     a constant, so it is invisible to a constant map. Its claim and signal
##     file lists ARE constants and are checked against Battle's preloads.
##
## Run: godot --headless --path . -s tools/check_prop_tables.gd

var _failed := false


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    %s" % label)
	else:
		printerr("  FAIL  %s" % label)
		_failed = true


func _init() -> void:
	_run()


func _consts(path: String) -> Dictionary:
	var script := load(path) as GDScript
	if script == null:
		_check(false, "cannot load %s" % path)
		return {}
	return script.get_script_constant_map()


## resource_path of every entry in an array of preloaded resources.
func _paths(arr: Variant) -> Array:
	var out: Array = []
	if typeof(arr) != TYPE_ARRAY:
		return out
	for entry: Variant in arr:
		if entry is Resource:
			out.append((entry as Resource).resource_path)
	return out


## Equal values for every key the two tables share; listed keys must exist in
## both. `only_shared` relaxes the second half for tables where one side
## legitimately carries extra entries (Camp's own tent kinds).
func _same_dict(a: Dictionary, b: Dictionary, label: String,
		only_shared := false) -> void:
	if not only_shared:
		var missing: Array = []
		for key: Variant in a:
			if not b.has(key):
				missing.append(key)
		for key: Variant in b:
			if not a.has(key):
				missing.append(key)
		if not missing.is_empty():
			_check(false, "%s: key sets differ (%s)" % [label, str(missing)])
			return
	var wrong: Array = []
	for key: Variant in a:
		if b.has(key) and str(a[key]) != str(b[key]):
			wrong.append("%s: %s vs %s" % [str(key), str(a[key]), str(b[key])])
	_check(wrong.is_empty(), "%s agree%s" % [label,
			"" if wrong.is_empty() else " (" + ", ".join(wrong) + ")"])


func _same(a: Variant, b: Variant, label: String) -> void:
	_check(str(a) == str(b), "%s (%s vs %s)" % [label, str(a), str(b)]
			if str(a) != str(b) else "%s agree" % label)


func _run() -> void:
	await process_frame  # autoloads up before Battle.gd is compiled
	var battle := _consts("res://scripts/Battle.gd")
	var camp := _consts("res://scripts/Camp.gd")
	var preview := _consts("res://tools/render_board_preview.gd")
	if battle.is_empty() or camp.is_empty() or preview.is_empty():
		print("\nRESULT: FAIL")
		quit(1)
		return

	print("\n[1] Battle vs the board preview")
	for key: String in ["ROCK_OFFSET", "JUNK_OFFSET", "PLANT_OFFSET",
			"SANDBAG_OFFSET", "THIRST_CACHE_OFFSET", "DRUM_OFFSET",
			"DETRITUS_RATE", "DETRITUS_GAP", "DETRITUS_JITTER",
			"SIGNAL_STANDS", "SIGNAL_STAND_SHADOW",
			"SALT_ROCK", "SALT_JUNK", "SALT_PLANT", "SALT_SANDBAG",
			"SALT_CACHE", "SALT_CLAIM", "SALT_DETRITUS", "SALT_DETRITUS_PICK",
			"SALT_DETRITUS_JITTER", "SALT_SIGNAL"]:
		_same(battle.get(key), preview.get(key), key)
	_same_dict(battle.get("WALL_OFFSETS", {}), preview.get("WALL_OFFSETS", {}),
			"WALL_OFFSETS")
	_same_dict(battle.get("WIRE_OFFSETS", {}), preview.get("WIRE_OFFSETS", {}),
			"WIRE_OFFSETS")
	_same_dict(battle.get("STRUCTURE_DIRS", {}),
			preview.get("STRUCTURE_DIRS", {}), "STRUCTURE_DIRS")
	_same_dict(battle.get("STRUCTURE_OFFSETS", {}),
			preview.get("STRUCTURE_OFFSETS", {}), "STRUCTURE_OFFSETS")
	_same(battle.get("CLAIM_OFFSETS"), preview.get("CLAIM_OFFSETS"),
			"CLAIM_OFFSETS")
	_same(battle.get("SIGNAL_STAND_OFFSETS"),
			preview.get("SIGNAL_STAND_OFFSETS"), "SIGNAL_STAND_OFFSETS")

	# The texture lists against the preview's file lists, path by path: this is
	# the check that catches "the preview quietly draws different art".
	var claim_expected: Array = []
	for f: String in preview.get("CLAIM_FILES", []):
		claim_expected.append(str(preview.get("CLAIM_ROOT", "")).path_join(f))
	_check(str(_paths(battle.get("CLAIM_TEXTURES"))) == str(claim_expected),
			"claim marker art matches file for file")
	var signal_expected: Array = []
	for f: String in preview.get("SIGNAL_STAND_FILES", []):
		signal_expected.append(str(preview.get("SIGNAL_ROOT", "")).path_join(f))
	_check(str(_paths(battle.get("SIGNAL_STAND_TEXTURES"))) == str(signal_expected),
			"signal stand art matches file for file")

	# TARGET_PROPS: the preview carries a reduced spec (still/offset/shadow).
	# Same kinds, same anchors, same shadows, and its still must live inside
	# the directory Battle animates from.
	var b_props: Dictionary = battle.get("TARGET_PROPS", {})
	var p_props: Dictionary = preview.get("TARGET_PROPS", {})
	_check(b_props.keys() == p_props.keys(),
			"objective props cover the same kinds (%s vs %s)"
			% [str(b_props.keys()), str(p_props.keys())])
	for kind: String in b_props:
		if not p_props.has(kind):
			continue
		var bs: Dictionary = b_props[kind]
		var ps: Dictionary = p_props[kind]
		_check(str(bs.get("offset")) == str(ps.get("offset"))
				and str(bs.get("shadow")) == str(ps.get("shadow")),
				"'%s' anchors and shadow agree" % kind)
		_check(str(ps.get("still", "")).begins_with(
				str(bs.get("dir", "")) + "/" + str(bs.get("body", ""))),
				"'%s' preview still lives in Battle's prop directory" % kind)

	print("\n[2] Battle vs the camp")
	for key: String in ["ROCK_OFFSET", "JUNK_OFFSET", "PLANT_OFFSET",
			"SALT_ROCK", "SALT_JUNK", "SALT_PLANT",
			"SALT_DETRITUS", "SALT_DETRITUS_PICK", "SALT_DETRITUS_JITTER",
			"DETRITUS_RATE", "DETRITUS_GAP", "DETRITUS_JITTER"]:
		_same(battle.get(key), camp.get(key), key)
	# Different names, one hash stream: the camp calls the cache salt CRATE.
	_same(battle.get("SALT_CACHE"), camp.get("SALT_CRATE"),
			"SALT_CACHE / SALT_CRATE")
	_same_dict(battle.get("STRUCTURE_DIRS", {}), camp.get("STRUCTURE_DIRS", {}),
			"shared STRUCTURE_DIRS entries", true)
	_same_dict(battle.get("STRUCTURE_OFFSETS", {}),
			camp.get("STRUCTURE_OFFSETS", {}), "shared STRUCTURE_OFFSETS", true)
	_check((battle.get("PROP_DUST") as Resource).resource_path
			== (camp.get("PROP_DUST") as Resource).resource_path,
			"one dust shader between them")
	_check(str(_paths(battle.get("ROCK_TEXTURES")))
			== str(_paths(camp.get("ROCK_TEXTURES"))),
			"the camps stack the same rocks")
	_check(str(_paths(battle.get("DETRITUS_TEXTURES")))
			== str(_paths(camp.get("DETRITUS_TEXTURES"))),
			"and scatter the same detritus")
	# Documented subsets: fewer on purpose, never different.
	var battle_junk := _paths(battle.get("JUNK_TEXTURES"))
	var stray_junk: Array = []
	for path: String in _paths(camp.get("JUNK_TEXTURES")):
		if not battle_junk.has(path):
			stray_junk.append(path)
	_check(stray_junk.is_empty(),
			"camp junk is a subset of battle junk (the car door rule)")
	var battle_plants := _paths(battle.get("PLANT_TEXTURES"))
	var stray_plants: Array = []
	for path: String in _paths(camp.get("PLANT_TEXTURES")):
		if not battle_plants.has(path):
			stray_plants.append(path)
	_check(stray_plants.is_empty(), "camp plants are a subset of battle plants")

	print("\nRESULT: ", "FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)
