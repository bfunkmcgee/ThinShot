class_name TileCatalog

## Loader for the `*.tiles.json` sidecars the art pipeline emits next to each
## floor sheet. The sidecar is the sheet describing itself: which slot belongs
## to which zone, which tiles are symmetric enough to mirror, and where the
## corner-transition sets live. Board reads the result; a sheet with no sidecar
## gets an empty dictionary back and Board keeps its hardcoded legacy tables,
## which is what every shipped sheet uses today.
##
## Sidecar v1 shape:
##   {
##     "sheet": "...", "tile_size": [128, 60],
##     "slots": [{"rect": [x,y,w,h], "zone": 0|1|2, "role": "base"|"accent",
##                "symmetric": bool, "tall": bool?}],
##     "sets": [{"lower": "zone0"|"desert"|..., "upper": ...,
##               "sheet": "res://...png"?,   # defaults to the base sheet
##               "tiles": [{"rect": [...], "corners": {"top": "lower"|"upper",
##                          "right": ..., "bottom": ..., "left": ...}}]}],
##     "provenance": {...}, "metrics": {...}
##   }
##
## Corner names are screen-space diamond vertices; Board maps them to grid
## vertices as top->(x,y), right->(x+1,y), bottom->(x+1,y+1), left->(x,y+1).
## A transition set is indexed by 4-bit mask - bit0 top, bit1 right, bit2
## bottom, bit3 left, a bit set where that corner is the UPPER terrain.
##
## Road sidecars are the same file shape with one edge-mode set instead of
## slots ("slots": [], "sets": [{"mode": "edge", "tiles": [...]}]). Each tile
## carries "edges" {n, e, s, w} 0/1 flags (or a precomputed 4-bit "mask"),
## a bit set where the road continues across that EDGE of the cell - grid
## directions, so n is the (x, y-1) neighbour. One tile may instead carry
## "role": "stamp" - decoration for tooling, never indexed by mask.

const ZONES := 3
const MASKS := 16
const CORNER_BITS := {"top": 0, "right": 1, "bottom": 2, "left": 3}
## Edge-set bit order. Deliberately matches how Board masks its 4-neighbours:
## bit0 north (y-1), bit1 east (x+1), bit2 south (y+1), bit3 west (x-1).
const EDGE_BITS := {"n": 0, "e": 1, "s": 2, "w": 3}

## Parsed sidecars by sidecar path, so a floor is only read off disk once per
## run. Values are the loaded dictionary, or {} for "no sidecar here".
static var _cache: Dictionary = {}
## Same, for edge-mode road sidecars - separate because the same JSON parses
## to a different shape through parse_road than through parse.
static var _road_cache: Dictionary = {}


## The sidecar path for a floor sheet: same folder, `.tiles.json` for `.png`.
static func sidecar_path(sheet_path: String) -> String:
	return sheet_path.get_basename() + ".tiles.json"


## The catalog for a floor sheet, or {} when it has no sidecar (the current
## state of every shipped sheet). Returned shape:
##   families:    [zone -> Array of {rect: Rect2, symmetric: bool}]
##   accents:     [zone -> Array of {rect: Rect2, symmetric: bool}]
##   transitions: {"0|1" / "1|2" / "desert|compound" ->
##                     {sheet: Texture2D, tiles: Array[Rect2] by mask}}
static func load_for(sheet_path: String) -> Dictionary:
	var path := sidecar_path(sheet_path)
	if _cache.has(path):
		return _cache[path]
	var catalog := _load_sidecar(path, sheet_path)
	_cache[path] = catalog
	return catalog


## The road catalog for a road sheet, or {} when it has no sidecar or the
## sidecar ships no edge-mode set. Returned shape:
##   sheet: Texture2D
##   tiles: Array[Rect2] indexed by 4-bit edge mask (EDGE_BITS; empty Rect2
##          for a mask the set does not cover)
##   stamp: Rect2 - the optional stamp-only tile, Rect2() when absent
static func load_road_for(sheet_path: String) -> Dictionary:
	var path := sidecar_path(sheet_path)
	if _road_cache.has(path):
		return _road_cache[path]
	var catalog := {}
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			push_error("[TileCatalog] cannot open %s" % path)
		else:
			var data: Variant = JSON.parse_string(file.get_as_text())
			file.close()
			if typeof(data) != TYPE_DICTIONARY:
				push_error("[TileCatalog] %s is not a JSON object" % path)
			else:
				catalog = parse_road(data, sheet_path)
	_road_cache[path] = catalog
	return catalog


## Build a road catalog from already-parsed sidecar JSON. Data-driven from the
## sidecar's own edge flags - nothing about the sheet layout is assumed here.
static func parse_road(data: Dictionary, sheet_path: String) -> Dictionary:
	if not ResourceLoader.exists(sheet_path):
		push_error("[TileCatalog] road sheet missing: %s" % sheet_path)
		return {}
	var tiles: Array = []
	tiles.resize(MASKS)
	tiles.fill(Rect2())
	var stamp := Rect2()
	var seen := 0
	for set_data: Dictionary in data.get("sets", []):
		if str(set_data.get("mode", "")) != "edge":
			continue
		for tile: Dictionary in set_data.get("tiles", []):
			var rect := _rect_of(tile.get("rect", []))
			if str(tile.get("role", "")) == "stamp":
				stamp = rect
				continue
			var mask := _edge_mask_of(tile)
			if tiles[mask] != Rect2():
				# Sheets legitimately ship a second all-closed tile as plain
				# ground; first occurrence wins for every mask, quietly.
				continue
			tiles[mask] = rect
			seen += 1
	if seen == 0:
		return {}
	if seen != MASKS:
		push_warning("[TileCatalog] %s: road set has %d of %d edge masks"
				% [sheet_path, seen, MASKS])
	return {"sheet": load(sheet_path), "tiles": tiles, "stamp": stamp}


## A road tile's 4-bit mask: the "edges" {n,e,s,w} flags folded through
## EDGE_BITS, or the tile's own precomputed "mask" when it carries one.
static func _edge_mask_of(tile: Dictionary) -> int:
	if tile.has("mask"):
		return clampi(int(tile.mask), 0, MASKS - 1)
	var edges: Dictionary = tile.get("edges", {})
	var mask := 0
	for edge: String in EDGE_BITS:
		if int(edges.get(edge, 0)) != 0:
			mask |= 1 << int(EDGE_BITS[edge])
	return mask


## Parse one sidecar file. Split out from load_for so tooling can point it at
## a sidecar anywhere on disk without wiring the sheet into FLOOR_SHEETS.
static func _load_sidecar(path: String, sheet_path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[TileCatalog] cannot open %s" % path)
		return {}
	var data: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(data) != TYPE_DICTIONARY:
		push_error("[TileCatalog] %s is not a JSON object" % path)
		return {}
	return parse(data, sheet_path)


## Build the catalog from already-parsed sidecar JSON. Kept separate and
## side-effect-free so a test can feed it a dictionary directly.
static func parse(data: Dictionary, sheet_path: String) -> Dictionary:
	var families: Array = []
	var accents: Array = []
	for zone in ZONES:
		families.append([])
		accents.append([])
	for slot: Dictionary in data.get("slots", []):
		var zone := clampi(int(slot.get("zone", 0)), 0, ZONES - 1)
		var entry := {
			"rect": _rect_of(slot.get("rect", [])),
			"symmetric": bool(slot.get("symmetric", false)),
		}
		if str(slot.get("role", "base")) == "accent":
			accents[zone].append(entry)
		else:
			families[zone].append(entry)
	for zone in ZONES:
		if (families[zone] as Array).is_empty():
			push_error("[TileCatalog] %s: zone %d has no base slots"
					% [sheet_path, zone])
			return {}
	var transitions := {}
	for set_data: Dictionary in data.get("sets", []):
		var key := "%s|%s" % [_zone_name(set_data.get("lower", "")),
				_zone_name(set_data.get("upper", ""))]
		var set_sheet_path := str(set_data.get("sheet", sheet_path))
		if not ResourceLoader.exists(set_sheet_path):
			push_error("[TileCatalog] %s: set '%s' names missing sheet %s"
					% [sheet_path, key, set_sheet_path])
			continue
		var tiles: Array = []
		tiles.resize(MASKS)
		tiles.fill(Rect2())
		var seen := 0
		for tile: Dictionary in set_data.get("tiles", []):
			var mask := _mask_of(tile.get("corners", {}))
			if tiles[mask] != Rect2():
				push_warning("[TileCatalog] %s: set '%s' repeats mask %d"
						% [sheet_path, key, mask])
				continue
			tiles[mask] = _rect_of(tile.get("rect", []))
			seen += 1
		if seen != MASKS:
			push_warning("[TileCatalog] %s: set '%s' has %d of %d corner masks"
					% [sheet_path, key, seen, MASKS])
		transitions[key] = {"sheet": load(set_sheet_path), "tiles": tiles}
	return {
		"families": families,
		"accents": accents,
		"transitions": transitions,
	}


static func _rect_of(values: Array) -> Rect2:
	if values.size() != 4:
		return Rect2()
	return Rect2(float(values[0]), float(values[1]),
			float(values[2]), float(values[3]))


## Set names come through as "zone0".."zone2" for in-floor transitions and as
## floor names ("desert", "compound") for cross-floor ones. Board keys the
## former by bare zone index, so strip the prefix here.
static func _zone_name(raw: Variant) -> String:
	var name := str(raw)
	if name.begins_with("zone"):
		return name.trim_prefix("zone")
	return name


static func _mask_of(corners: Dictionary) -> int:
	var mask := 0
	for corner: String in CORNER_BITS:
		if str(corners.get(corner, "lower")) == "upper":
			mask |= 1 << int(CORNER_BITS[corner])
	return mask
