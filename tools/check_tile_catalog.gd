extends SceneTree

## Sidecar-aware floor sheet validator - the successor to check_floor_sheets.gd.
##
## For every floor in Board.FLOOR_SHEETS:
##   - WITH a `<sheet>.tiles.json` sidecar: validate what the engine actually
##     consumes (TileCatalog.parse -> Board's families/accents/transitions):
##     JSON parses, every rect inside its sheet, 128x60 faces (or declared
##     tall), per-slot opaque coverage >= 0.4 with an opaque centre, >= 1 base
##     and >= 1 accent per zone 0-2, each transition set exactly 16 tiles
##     covering all 16 corner masks exactly once, and no transition tile
##     flagged symmetric (Board never mirrors them; a flag would lie).
##   - WITHOUT one: report "legacy (no sidecar)" and run the region checks
##     check_floor_sheets.gd runs, so this tool can eventually replace it.
##
## Also checks every cross-floor transition key the engine can ask for (each
## level's floor|inset pair - Board._build_tile_cache's cross_key) and every
## level's floor names, mirroring check_floor_sheets' level pass.
##
## Run: powershell tools/godot.ps1 --headless --path . -s tools/check_tile_catalog.gd

const FACE_W := 128.0
const FACE_H := 60.0
const MIN_COVERAGE := 0.4
## Transition keys Board reads from a floor's own sidecar: zone seams one step
## apart. Anything else in "sets" is either a cross-floor key or dead weight.
const ZONE_SET_KEYS := ["0|1", "1|2"]

var failed := false


func _ok(cond: bool, msg: String) -> bool:
	if cond:
		print("  ok - " + msg)
	else:
		printerr("  FAIL - " + msg)
		failed = true
	return cond


## Per-item variant: silent on pass (a sheet has dozens of rects), loud on
## failure. Summary ok lines come from the caller.
func _quiet(cond: bool, msg: String) -> bool:
	if not cond:
		printerr("  FAIL - " + msg)
		failed = true
	return cond


func _warn(msg: String) -> void:
	print("  warn - " + msg)


func _init() -> void:
	var cross_keys := _cross_keys()
	for floor_name: String in Board.FLOOR_SHEETS:
		var tex: Texture2D = Board.FLOOR_SHEETS[floor_name]
		var sidecar := TileCatalog.sidecar_path(tex.resource_path)
		if FileAccess.file_exists(sidecar):
			print("%s: sidecar %s" % [floor_name, sidecar])
			_check_sidecar(floor_name, tex, sidecar, cross_keys)
		else:
			print("%s: legacy (no sidecar)" % floor_name)
			_check_legacy(floor_name, tex)

	# Cross-floor transition sets, keyed exactly as Board._build_tile_cache
	# builds its cross_key. A missing set is today's shipped state (hard inset
	# edge), so absence is informational, not a failure.
	print("cross-floor transition keys the engine can ask for:")
	if cross_keys.is_empty():
		print("  (none - no shipped level names a floor_inset)")
	for key: String in cross_keys:
		var parts := key.split("|")
		var lower_cat := TileCatalog.load_for(
				(Board.FLOOR_SHEETS[parts[0]] as Texture2D).resource_path)
		var upper_cat := TileCatalog.load_for(
				(Board.FLOOR_SHEETS[parts[1]] as Texture2D).resource_path)
		var found := {}
		if (lower_cat.get("transitions", {}) as Dictionary).has(key):
			found[parts[0]] = lower_cat.transitions[key]
		if (upper_cat.get("transitions", {}) as Dictionary).has(key):
			found[parts[1]] = upper_cat.transitions[key]
		if found.is_empty():
			print("  ok - '%s' not shipped (hard inset edge - the legacy look)" % key)
			continue
		for owner: String in found:
			var tiles: Array = found[owner].tiles
			var missing := 0
			for r: Rect2 in tiles:
				if r.size.x <= 0.0:
					missing += 1
			_ok(missing == 0, "'%s' (in %s sidecar): %d/%d corner masks usable"
					% [key, owner, tiles.size() - missing, TileCatalog.MASKS])

	# Every level's floor names, so this tool fully replaces check_floor_sheets.
	print("levels:")
	for idx in Levels.LEVELS.size():
		var data: Dictionary = Levels.LEVELS[idx]
		var floor_name: String = data.get("floor", Board.DEFAULT_FLOOR)
		var inset: Dictionary = data.get("floor_inset", {})
		var ok := Board.FLOOR_SHEETS.has(floor_name)
		var extra := ""
		if not inset.is_empty():
			var inset_name: String = inset.get("floor", Board.DEFAULT_FLOOR)
			ok = ok and Board.FLOOR_SHEETS.has(inset_name)
			extra = " + %s inset %s" % [inset_name, inset.get("rect")]
		_ok(ok, "level %d '%s': %s%s" % [idx + 1, data.name, floor_name, extra])

	print("RESULT: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)


## Every floor|inset pair a shipped level can hand Board, i.e. every cross_key
## _build_tile_cache can construct.
func _cross_keys() -> Dictionary:
	var keys := {}
	for data: Dictionary in Levels.LEVELS:
		var inset: Dictionary = data.get("floor_inset", {})
		if inset.is_empty():
			continue
		var floor_name: String = data.get("floor", Board.DEFAULT_FLOOR)
		var inset_name: String = inset.get("floor", Board.DEFAULT_FLOOR)
		if Board.FLOOR_SHEETS.has(floor_name) and Board.FLOOR_SHEETS.has(inset_name):
			keys["%s|%s" % [floor_name, inset_name]] = true
	return keys


# ------------------------------------------------------------------ sidecar --


func _check_sidecar(floor_name: String, tex: Texture2D, sidecar: String,
		cross_keys: Dictionary) -> void:
	var file := FileAccess.open(sidecar, FileAccess.READ)
	if not _ok(file != null, "sidecar opens"):
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not _ok(typeof(data) == TYPE_DICTIONARY, "sidecar parses to a JSON object"):
		return
	var sheet_img := tex.get_image()
	var bounds := Rect2(0, 0, sheet_img.get_width(), sheet_img.get_height())

	var tile_size: Array = data.get("tile_size", [int(FACE_W), int(FACE_H)])
	_ok(tile_size.size() == 2 and int(tile_size[0]) == int(FACE_W)
			and int(tile_size[1]) == int(FACE_H),
			"tile_size %s is the board's %dx%d face" % [tile_size, FACE_W, FACE_H])

	# --- slots: the uniform families and accents Board draws every cell from --
	var base_count := [0, 0, 0]
	var accent_count := [0, 0, 0]
	var slots: Array = data.get("slots", [])
	var slots_ok := true
	for i in slots.size():
		var slot: Dictionary = slots[i]
		var rect := _rect_of(slot.get("rect", []))
		var tall := bool(slot.get("tall", false))
		var zone := clampi(int(slot.get("zone", 0)), 0, TileCatalog.ZONES - 1)
		if str(slot.get("role", "base")) == "accent":
			accent_count[zone] += 1
		else:
			base_count[zone] += 1
		slots_ok = _quiet(rect.size.x > 0.0 and bounds.encloses(rect),
				"slot %d rect %s inside %s sheet" % [i, rect, floor_name]) and slots_ok
		if rect.size.x <= 0.0 or not bounds.encloses(rect):
			continue
		var face_ok: bool = rect.size.x == FACE_W \
				and (rect.size.y == FACE_H if not tall else rect.size.y >= FACE_H)
		slots_ok = _quiet(face_ok, "slot %d face %s (%s)" % [i, rect.size,
				"declared tall" if tall else "standard"]) and slots_ok
		slots_ok = _check_opacity(sheet_img, rect, "slot %d" % i) and slots_ok
	if slots_ok:
		print("  ok - %d slots: rects, faces, opacity" % slots.size())
	for zone in TileCatalog.ZONES:
		_ok(base_count[zone] >= 1 and accent_count[zone] >= 1,
				"zone %d has %d base + %d accent slot(s)"
				% [zone, base_count[zone], accent_count[zone]])

	# --- sets: the corner-Wang transitions Board indexes by 4-bit mask --------
	for set_data: Dictionary in data.get("sets", []):
		var key := "%s|%s" % [TileCatalog._zone_name(set_data.get("lower", "")),
				TileCatalog._zone_name(set_data.get("upper", ""))]
		if not ZONE_SET_KEYS.has(key) and not cross_keys.has(key):
			_warn("set '%s' matches no key Board reads (zone seams %s or a level's floor|inset)"
					% [key, ZONE_SET_KEYS])
		var set_sheet_path := str(set_data.get("sheet", tex.resource_path))
		if not _ok(ResourceLoader.exists(set_sheet_path),
				"set '%s' sheet exists: %s" % [key, set_sheet_path]):
			continue
		var set_tex: Texture2D = load(set_sheet_path)
		var set_img := set_tex.get_image()
		var set_bounds := Rect2(0, 0, set_img.get_width(), set_img.get_height())
		var tiles: Array = set_data.get("tiles", [])
		_ok(tiles.size() == TileCatalog.MASKS,
				"set '%s' has exactly %d tiles (%d found)"
				% [key, TileCatalog.MASKS, tiles.size()])
		var mask_seen := {}
		var tiles_ok := true
		for tile: Dictionary in tiles:
			var mask := TileCatalog._mask_of(tile.get("corners", {}))
			if mask_seen.has(mask):
				tiles_ok = _quiet(false, "set '%s' repeats corner mask %d" % [key, mask])
			mask_seen[mask] = true
			var rect := _rect_of(tile.get("rect", []))
			tiles_ok = _quiet(rect.size.x > 0.0 and set_bounds.encloses(rect),
					"set '%s' mask %d rect %s inside its sheet" % [key, mask, rect]) \
					and tiles_ok
			if rect.size.x <= 0.0 or not set_bounds.encloses(rect):
				continue
			tiles_ok = _quiet(rect.size == Vector2(FACE_W, FACE_H),
					"set '%s' mask %d face is %dx%d (%s)"
					% [key, mask, FACE_W, FACE_H, rect.size]) and tiles_ok
			tiles_ok = _check_opacity(set_img, rect, "set '%s' mask %d" % [key, mask]) \
					and tiles_ok
			# Board mirrors only art flagged symmetric, and never a transition
			# tile - a flag here would promise a mirror the engine refuses.
			tiles_ok = _quiet(not bool(tile.get("symmetric", false)),
					"set '%s' mask %d not flagged symmetric" % [key, mask]) and tiles_ok
		_ok(mask_seen.size() == TileCatalog.MASKS,
				"set '%s' covers all %d corner masks (%d covered)"
				% [key, TileCatalog.MASKS, mask_seen.size()])
		if tiles_ok:
			print("  ok - set '%s': rects, faces, opacity, no symmetric flags" % key)

	# --- what the engine actually consumes ------------------------------------
	var catalog := TileCatalog.parse(data, tex.resource_path)
	if not _ok(not catalog.is_empty(), "TileCatalog.parse accepts the sidecar"):
		return
	for zone in TileCatalog.ZONES:
		_ok(not (catalog.families[zone] as Array).is_empty(),
				"parsed catalog zone %d has a family" % zone)
	for key: String in catalog.get("transitions", {}):
		var usable := 0
		for r: Rect2 in catalog.transitions[key].tiles:
			if r.size.x > 0.0:
				usable += 1
		_ok(usable == TileCatalog.MASKS,
				"parsed set '%s': %d/%d masks usable by Board._set_tile"
				% [key, usable, TileCatalog.MASKS])


# ------------------------------------------------------------------- legacy --


## The region checks check_floor_sheets.gd runs, verbatim in spirit: every
## hardcoded region inside the sheet, mostly opaque, solid at the centre.
func _check_legacy(floor_name: String, tex: Texture2D) -> void:
	var img := tex.get_image()
	var regions: Array[Rect2] = Board.SHEET_REGIONS[floor_name]
	print("  %dx%d sheet, %d legacy regions" % [img.get_width(), img.get_height(),
			regions.size()])
	var all_ok := true
	for i in regions.size():
		var r: Rect2 = regions[i]
		if not _quiet(Rect2(0, 0, img.get_width(), img.get_height()).encloses(r),
				"slot %d region %s inside the sheet" % [i, r]):
			all_ok = false
			continue
		all_ok = _check_opacity(img, r, "slot %d" % i) and all_ok
	if all_ok:
		print("  ok - all %d regions in bounds and solid" % regions.size())


## check_floor_sheets' opacity test: a mis-indexed slot lands on empty sheet,
## so count opaque pixels and require the diamond's own centre to be solid.
func _check_opacity(img: Image, r: Rect2, label: String) -> bool:
	var opaque := 0
	for y in int(r.size.y):
		for x in int(r.size.x):
			if img.get_pixel(int(r.position.x) + x, int(r.position.y) + y).a > 0.5:
				opaque += 1
	var coverage := float(opaque) / (r.size.x * r.size.y)
	var mid := img.get_pixel(int(r.position.x + r.size.x / 2),
			int(r.position.y + r.size.y / 2))
	if coverage < MIN_COVERAGE or mid.a < 0.5:
		return _ok(false, "%s looks empty (coverage %.2f, centre a=%.2f)"
				% [label, coverage, mid.a])
	return true


static func _rect_of(values: Array) -> Rect2:
	if values.size() != 4:
		return Rect2()
	return Rect2(float(values[0]), float(values[1]),
			float(values[2]), float(values[3]))
