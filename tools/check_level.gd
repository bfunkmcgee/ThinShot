extends SceneTree

## Level lint, run against the real Board (real LOS, real cell kinds) rather
## than a re-implementation. Checks per map:
##   1. schema        - Levels._validate for shipped levels; a minimal
##                      replication for drafts and camp maps
##   2. reachability  - every objective/prisoner/extraction cell reachable from
##                      the squad spawns, or orthogonally adjacent to a
##                      reachable cell
##   3. spawn safety  - no enemy spawn with clear line of sight to a squad
##                      spawn at close range
##   4. cover density - fraction of walkable cells with an orthogonal
##                      COVER/BLOCK neighbour inside a sane band
##   5. sightline cap - longest clear straight orthogonal lane through any
##                      squad spawn (junk/walls break a lane; wire does not -
##                      it divides ground, never fire)
##   6. enclosures    - every walkable region holding an objective also holds a
##                      spawn-reachable cell (no sealed pockets with objectives)
##   7. drum chains   - warn on >= 3 mutually-chained fuel drums near a spawn
##   8. zones         - Levels._validate_zones (occupancy warns via push_warning)
## Warnings never fail the run. Camp maps (no enemy spawns) skip the combat
## checks - there is no combat in camp.
##
## Run:
##   powershell tools/godot.ps1 --headless --path . -s tools/check_level.gd -- --all
##   ...                                            -s tools/check_level.gd -- --level 1
##   ...                                            -s tools/check_level.gd -- --draft path/to/draft.json
## --level is 1-based, matching the game's own --level flag.

# --- lint bands ---------------------------------------------------------------
# Defaults are calibrated so every shipped level passes; a level can override
# any of them through its "lint" dictionary (keys cover_min / cover_max /
# lane_max / safe_dist), which the game validates as a dict and ignores.
#
# Calibration (2026-08, all 7 shipped levels):
#   cover density measured 0.29 (LONG HAUL) .. 0.65 (THE SCRAPLINE), so the
#   band's ceiling sits just above the scrap yard; the 0.08 floor never binds.
#   Spawn-LOS distances bottom out at 6 - SCRAPLINE's outer gates, CISTERN's
#   own gap, and THE HOLDING PENS, where seeing the pen from the start line IS
#   the design ("wire stops a boot and nothing else") - so the guard is 5, a
#   point-blank check. Lanes max at 11 (LONG HAUL's open row), cap 12 holds.
const COVER_MIN := 0.08
const COVER_MAX := 0.66
const LANE_MAX := 12
const SAFE_DIST := 5
# Drum-chain warning: a cluster of this many drums, each within blast reach of
# the next, sitting this close to a spawn, can cascade on turn one.
const DRUM_CHAIN_MIN := 3
const DRUM_NEAR_SPAWN := 3

const SQUAD_KEYS := ["scout_spawns", "lead_spawns", "gunner_spawns"]
const ENEMY_KEYS := ["goblin_spawns", "smg_spawns", "smg_alt_spawns",
		"novice_spawns", "bolt_spawns"]
const SPAWN_KEYS := SQUAD_KEYS + ENEMY_KEYS + ["prisoner_spawns",
		"bystander_spawns"]

var failed := false
var warnings := 0
var board: Board = null


func _init() -> void:
	_run()


## Deferred out of _init() for one reason: _check_kill_floor loads Rules.gd, and
## Rules type-hints Unit, and Unit names the Game autoload. Compiling that chain
## before the autoloads exist is the `-s` trap tools/test_hero_gameover.gd
## documents at length - it still produced the right answer here, because
## never_breaks() touches none of it at runtime, but it logged a compile error
## into a tool that had none. One frame is the whole fix, and it is the same
## shape every test harness in this directory already uses.
func _run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var jobs: Array = []  # {label: String, data: Dictionary, shipped_idx: int}
	var i := 0
	var parsed_any := false
	while i < args.size():
		match args[i]:
			"--level":
				if i + 1 >= args.size():
					_usage("--level needs a 1-based level number")
					return
				var n := int(args[i + 1])
				if n < 1 or n > Levels.LEVELS.size():
					_usage("--level %d out of range 1..%d" % [n, Levels.LEVELS.size()])
					return
				jobs.append(_shipped_job(n - 1))
				parsed_any = true
				i += 2
			"--draft":
				if i + 1 >= args.size():
					_usage("--draft needs a JSON file path")
					return
				var data := _load_draft(args[i + 1])
				if data.is_empty():
					failed = true
				else:
					jobs.append({"label": "draft '%s' (%s)" % [data.name, args[i + 1]],
							"data": data, "shipped_idx": -1})
				parsed_any = true
				i += 2
			"--all":
				for idx in Levels.LEVELS.size():
					jobs.append(_shipped_job(idx))
				for biome_key: String in Levels.BIOMES:
					var biome: Dictionary = Levels.BIOMES[biome_key]
					jobs.append({"label": "garrison camp [%s]" % biome_key,
							"data": CampData.map_for(false, biome), "shipped_idx": -1})
					jobs.append({"label": "field camp [%s]" % biome_key,
							"data": CampData.map_for(true, biome), "shipped_idx": -1})
				parsed_any = true
				i += 1
			_:
				_usage("unknown argument '%s'" % args[i])
				return
	if not parsed_any:
		_usage("nothing to check")
		return

	board = Board.new()
	for job: Dictionary in jobs:
		_check_map(job)
	board.free()
	if warnings > 0:
		print("")
		print("%d warning(s) - warnings never fail the run" % warnings)
	print("RESULT: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)


func _shipped_job(idx: int) -> Dictionary:
	return {"label": "level %d '%s'" % [idx + 1, Levels.LEVELS[idx].name],
			"data": Levels.LEVELS[idx], "shipped_idx": idx}


func _usage(why: String) -> void:
	printerr(why)
	printerr("usage: godot --headless --path . -s tools/check_level.gd -- "
			+ "[--level N (1-based) | --draft file.json | --all]")
	print("RESULT: FAIL")
	quit(1)


func _pass(cond: bool, msg: String) -> bool:
	if cond:
		print("  ok - " + msg)
	else:
		printerr("  FAIL - " + msg)
		failed = true
	return cond


func _warn(msg: String) -> void:
	print("  warn - " + msg)
	warnings += 1


# ------------------------------------------------------------------- driver --


func _check_map(job: Dictionary) -> void:
	var data: Dictionary = job.data
	print("%s (%dx%d, floor %s)" % [job.label, data.size.x, data.size.y,
			data.get("floor", Board.DEFAULT_FLOOR)])
	board.set_level(data)
	_check_schema(job)
	_check_reachability(data)
	# A map with no enemy spawn keys is a camp: nobody fights there, so the
	# combat-tuning bands would only measure the scenery.
	if not data.has("goblin_spawns"):
		print("  ok - combat checks skipped (camp map: no enemy spawns)")
	else:
		_check_spawn_safety(data)
		_check_cover_density(data)
		_check_sightlines(data)
		_check_enclosures(data)
		_check_drum_chains(data)
		_check_kill_floor(data)
	_check_zones(job)


func _cells_of(data: Dictionary, keys: Array) -> Array:
	var out: Array = []
	for key: String in keys:
		for cell in data.get(key, []):
			out.append(cell)
	return out


## Objective cells that live somewhere on the map: destroy targets, extraction
## zones, and the prisoners a rescue points at. Eliminate has no geography.
func _objective_cells(data: Dictionary) -> Array:
	var out: Array = []  # {cell, what}
	for obj in data.get("objectives", []):
		var kind: String = obj.get("kind", "")
		if kind == "destroy" or kind == "extract":
			for cell in obj.get("cells", []):
				out.append({"cell": cell, "what": kind})
	for cell in data.get("prisoner_spawns", []):
		out.append({"cell": cell, "what": "prisoner"})
	return out


## Enemy spawn keys, paired with the Unit.Kind ordinal each one fields. Raw
## ordinals for the same reason test_rules.gd uses them: this tool runs under
## `-s` and must not drag Unit.gd into a compile that happens before the
## autoloads exist.
const ENEMY_KIND_OF := {
	"goblin_spawns": 3,
	"smg_spawns": 4,
	"smg_alt_spawns": 5,
	"novice_spawns": 6,
	"bolt_spawns": 7,
}


# ------------------------------------------------------------------- checks --


## 0. The kill floor. A mission that asks the squad to CLEAR ground has to
## contain somebody who will not leave it, or a good enough player could finish
## it having killed nobody - and the game would be quietly promising that
## restraint is always on the table. It is not, and the campaign has a mission
## whose whole point is that it is not.
##
## Only eliminate missions are checked. The destroy, extract and rescue maps are
## deliberately free of this: those CAN be completed without killing, which is
## the other half of the same design and the reason the floor is per-objective
## rather than per-map.
##
## Rules.never_breaks is the authority on who holds; this only asks whether the
## map fields one of them.
func _check_kill_floor(data: Dictionary) -> void:
	var eliminates := false
	for obj in data.get("objectives", []):
		if str(obj.get("kind", "")) == "eliminate":
			eliminates = true
	if not eliminates:
		print("  ok - kill floor n/a (no eliminate objective: winnable without killing)")
		return
	var rules: GDScript = load("res://scripts/Rules.gd") as GDScript
	var holders := 0
	var held_by: Array[String] = []
	for key: String in ENEMY_KIND_OF:
		var n: int = data.get(key, []).size()
		if n > 0 and rules.call("never_breaks", int(ENEMY_KIND_OF[key])):
			holders += n
			held_by.append("%s x%d" % [key, n])
	_pass(holders > 0,
			"kill floor: %d unbreakable enemy(s) on an eliminate map%s"
					% [holders, "" if held_by.is_empty() else " (%s)" % ", ".join(held_by)])


## 1. Shipped levels get the engine's own validator - no point duplicating what
## Levels.validate_all() already enforces. Drafts and camp maps get a minimal
## replication of the same rules.
func _check_schema(job: Dictionary) -> void:
	if int(job.shipped_idx) >= 0:
		_pass(Levels._validate(int(job.shipped_idx)),
				"schema (Levels._validate: chars, spawns, objectives, floor, zones)")
		return
	var data: Dictionary = job.data
	var grid: Vector2i = data.size
	var ok := true
	ok = data.map.size() == grid.y
	if not ok:
		_pass(false, "schema: map must have %d rows, has %d"
				% [grid.y, data.map.size()])
		return
	for row: String in data.map:
		if row.length() != grid.x:
			_pass(false, "schema: row '%s' is %d chars, wants %d"
					% [row, row.length(), grid.x])
			return
		for ch in row:
			if not Levels.LEGAL_CHARS.contains(ch):
				ok = _pass(false, "schema: illegal char '%s'" % ch) and ok
	var seen := {}
	var spawn_count := 0
	for key: String in SPAWN_KEYS:
		for cell in data.get(key, []):
			spawn_count += 1
			if not (board.in_bounds(cell) and board.is_walkable(cell)):
				ok = _pass(false, "schema: %s spawn %s not walkable" % [key, cell]) and ok
			if seen.has(cell):
				ok = _pass(false, "schema: duplicate spawn %s" % [cell]) and ok
			seen[cell] = true
	for entry: Dictionary in _objective_cells(data):
		var cell: Vector2i = entry.cell
		if entry.what != "prisoner" \
				and not (board.in_bounds(cell) and board.is_walkable(cell)):
			ok = _pass(false, "schema: %s cell %s not walkable" % [entry.what, cell]) and ok
	if ok:
		_pass(true, "schema: %dx%d rows, legal chars, %d spawns walkable + unique"
				% [grid.x, grid.y, spawn_count])


## 2. Flood fill 4-dir over walkable cells from every squad spawn. An objective
## needs to be reachable, or orthogonally adjacent to a reachable cell.
func _check_reachability(data: Dictionary) -> void:
	var squad := _cells_of(data, SQUAD_KEYS)
	var objectives := _objective_cells(data)
	if squad.is_empty():
		_pass(objectives.is_empty(),
				"reachability: no squad spawns%s" % (
						"" if objectives.is_empty()
						else ", yet %d objective cells" % objectives.size()))
		return
	var reach := _squad_reach(squad)
	var bad: Array[String] = []
	for entry: Dictionary in objectives:
		var cell: Vector2i = entry.cell
		var found: bool = reach.has(cell)
		if not found:
			for dir in Board.DIRS:
				if reach.has(cell + dir):
					found = true
					break
		if not found:
			bad.append("%s %s" % [entry.what, cell])
	_pass(bad.is_empty(), "reachability: %d objective cells from %d squad spawns%s"
			% [objectives.size(), squad.size(),
					"" if bad.is_empty() else " - unreachable: " + ", ".join(bad)])


func _squad_reach(squad: Array) -> Dictionary:
	var reach := {}
	var everywhere := board.size.x * board.size.y
	for spawn in squad:
		reach[spawn] = true
		for cell in board.flood_fill(spawn, everywhere,
				func(_c: Vector2i) -> bool: return false):
			reach[cell] = true
	return reach


## 3. An enemy spawn that already has a clear firing line onto a squad spawn at
## close range decides turn one before the player moves. Uses the Board's real
## LOS (junk and wire do not block sight; walls and rock do).
func _check_spawn_safety(data: Dictionary) -> void:
	var safe_dist := int(data.get("lint", {}).get("safe_dist", SAFE_DIST))
	var bad: Array[String] = []
	var closest := -1
	for enemy in _cells_of(data, ENEMY_KEYS):
		for squad in _cells_of(data, SQUAD_KEYS):
			if not board.has_line_of_sight(enemy, squad):
				continue
			var d := Board.manhattan(enemy, squad)
			if closest < 0 or d < closest:
				closest = d
			if d <= safe_dist:
				bad.append("%s sees %s at %d" % [enemy, squad, d])
	var seen := "no enemy/squad LOS pair at all" if closest < 0 \
			else "closest enemy LOS onto a squad spawn: %d" % closest
	_pass(bad.is_empty(), "spawn safety (LOS within %d): %s%s" % [safe_dist, seen,
			"" if bad.is_empty() else " - " + "; ".join(bad)])


## 4. How much of the walkable ground has something to get behind beside it.
## Too little and the map is a firing range; too much and it is a warehouse.
func _check_cover_density(data: Dictionary) -> void:
	var lint: Dictionary = data.get("lint", {})
	var lo := float(lint.get("cover_min", COVER_MIN))
	var hi := float(lint.get("cover_max", COVER_MAX))
	var walkable := 0
	var covered := 0
	for y in board.size.y:
		for x in board.size.x:
			var cell := Vector2i(x, y)
			if not board.is_walkable(cell):
				continue
			walkable += 1
			for dir in Board.DIRS:
				var n: Vector2i = cell + dir
				if not board.in_bounds(n):
					continue
				var kind := board.cell_kind(n)
				if kind == Board.CellKind.COVER or kind == Board.CellKind.BLOCK:
					covered += 1
					break
	var frac := float(covered) / float(maxi(walkable, 1))
	_pass(frac >= lo and frac <= hi,
			"cover density %.2f (%d of %d walkable) in [%.2f, %.2f]"
			% [frac, covered, walkable, lo, hi])


## 5. The longest straight orthogonal lane a shot travels unimpeded through a
## squad spawn. BLOCK stops a lane, COVER breaks it (the shot is no longer
## clean); WIRE does not - wire divides ground, never fire.
func _check_sightlines(data: Dictionary) -> void:
	var lane_max := int(data.get("lint", {}).get("lane_max", LANE_MAX))
	var longest := 0
	var where := Vector2i.ZERO
	var axis := ""
	for spawn in _cells_of(data, SQUAD_KEYS):
		for run in [{"dir": Vector2i(1, 0), "name": "row"},
				{"dir": Vector2i(0, 1), "name": "column"}]:
			var length := _lane_length(spawn, run.dir)
			if length > longest:
				longest = length
				where = spawn
				axis = run.name
	_pass(longest <= lane_max,
			"sightline cap: longest clear lane %d (%s through %s) <= %d"
			% [longest, axis, where, lane_max])


func _lane_length(spawn: Vector2i, dir: Vector2i) -> int:
	if _lane_blocked(spawn):
		return 0
	var length := 1
	for step: int in [1, -1]:
		var cell := spawn + dir * step
		while board.in_bounds(cell) and not _lane_blocked(cell):
			length += 1
			cell += dir * step
	return length


func _lane_blocked(cell: Vector2i) -> bool:
	var kind := board.cell_kind(cell)
	return kind == Board.CellKind.BLOCK or kind == Board.CellKind.COVER


## 6. Flood fill treating blockers AND wire as walls is exactly "regions of
## walkable ground". Every region holding an objective must also hold a cell
## the squad can reach - i.e. be the squad's own region - or the objective
## sits in a sealed pocket (a wire pen with no gate).
func _check_enclosures(data: Dictionary) -> void:
	var comp := {}  # walkable cell -> component id
	var next_id := 0
	for y in board.size.y:
		for x in board.size.x:
			var cell := Vector2i(x, y)
			if not board.is_walkable(cell) or comp.has(cell):
				continue
			comp[cell] = next_id
			var frontier: Array[Vector2i] = [cell]
			while not frontier.is_empty():
				var cur: Vector2i = frontier.pop_back()
				for dir in Board.DIRS:
					var nxt: Vector2i = cur + dir
					if board.in_bounds(nxt) and board.is_walkable(nxt) \
							and not comp.has(nxt):
						comp[nxt] = next_id
						frontier.push_back(nxt)
			next_id += 1
	var reachable := {}
	for spawn in _cells_of(data, SQUAD_KEYS):
		if comp.has(spawn):
			reachable[comp[spawn]] = true
	var bad: Array[String] = []
	for entry: Dictionary in _objective_cells(data):
		var cell: Vector2i = entry.cell
		if comp.has(cell) and not reachable.has(comp[cell]):
			bad.append("%s %s sealed off" % [entry.what, cell])
	_pass(bad.is_empty(), "enclosures: %d walkable region(s), objectives in squad-"
			% next_id + "reachable ones%s" % (
					"" if bad.is_empty() else " - " + "; ".join(bad)))


## 7. Warning only: drums that can cascade. Two drums catch each other when one
## sits in the other's 3x3 blast (Chebyshev <= 1); a chain of three or more
## parked next to a spawn is a first-turn wipe waiting for one stray frag.
func _check_drum_chains(data: Dictionary) -> void:
	var drums: Array[Vector2i] = []
	for y in board.size.y:
		for x in board.size.x:
			if board.map_char(Vector2i(x, y)) == "d":
				drums.append(Vector2i(x, y))
	var spawns := _cells_of(data, SPAWN_KEYS)
	var seen := {}
	var chains := 0
	for start in drums:
		if seen.has(start):
			continue
		var cluster: Array[Vector2i] = [start]
		seen[start] = true
		var frontier: Array[Vector2i] = [start]
		while not frontier.is_empty():
			var cur: Vector2i = frontier.pop_back()
			for other in drums:
				if not seen.has(other) \
						and maxi(absi(other.x - cur.x), absi(other.y - cur.y)) <= 1:
					seen[other] = true
					cluster.append(other)
					frontier.push_back(other)
		if cluster.size() < DRUM_CHAIN_MIN:
			continue
		var near := ""
		for cell in cluster:
			for spawn in spawns:
				if Board.manhattan(cell, spawn) <= DRUM_NEAR_SPAWN:
					near = str(spawn)
					break
			if near != "":
				break
		if near != "":
			chains += 1
			_warn("drum chain: %d drums %s within blast reach of each other, near spawn %s"
					% [cluster.size(), cluster, near])
	print("  ok - drum chains: %d drums, %d risky chain(s) (warn-only)"
			% [drums.size(), chains])


## 8. The zone split is cosmetic but it is still authored: rebuildable only
## with the exact noise Board uses, which is what Levels._validate_zones does.
## Lopsided splits arrive as push_warnings, not failures.
func _check_zones(job: Dictionary) -> void:
	_pass(Levels._validate_zones(job.data, job.label),
			"zones (Levels._validate_zones: thresholds, zone_map shape, occupancy)")


# -------------------------------------------------------------------- draft --


## A draft is the same dictionary a Levels entry is, as JSON: map rows as
## strings, every cell as [x, y], rects as [x, y, w, h]. Coerced here to the
## typed shapes Levels.gd produces so Board and the checks cannot tell the
## difference.
func _load_draft(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		printerr("cannot open draft: %s (%s)"
				% [path, error_string(FileAccess.get_open_error())])
		return {}
	var raw: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(raw) != TYPE_DICTIONARY:
		printerr("draft is not a JSON object: %s" % path)
		return {}
	return _coerce_draft(raw)


static func _v2i(value: Variant) -> Vector2i:
	if value is Array and (value as Array).size() == 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i(-1, -1)  # out of bounds, so it fails loudly downstream


static func _coerce_draft(raw: Dictionary) -> Dictionary:
	var data := {}
	data.name = str(raw.get("name", "draft"))
	var map: Array = []
	for row in raw.get("map", []):
		map.append(str(row))
	data.map = map
	var size := Vector2i(str(map[0]).length() if map.size() > 0 else 0, map.size())
	if raw.has("size"):
		size = _v2i(raw.size)
	data.size = size
	for key: String in SPAWN_KEYS:
		if raw.has(key):
			var cells: Array = []
			for value in raw[key]:
				cells.append(_v2i(value))
			data[key] = cells
	var structures: Array = []
	for s in raw.get("structures", []):
		structures.append({"kind": str(s.get("kind", "")),
				"anchor": _v2i(s.get("anchor", [])), "size": _v2i(s.get("size", []))})
	data.structures = structures
	if raw.has("objectives"):
		var objectives: Array = []
		for o in raw.objectives:
			var obj := {"kind": str(o.get("kind", ""))}
			for copied: String in ["label", "prop"]:
				if o.has(copied):
					obj[copied] = str(o[copied])
			if o.has("cells"):
				var cells: Array = []
				for value in o.cells:
					cells.append(_v2i(value))
				obj.cells = cells
			objectives.append(obj)
		data.objectives = objectives
	if raw.has("floor"):
		data.floor = str(raw.floor)
	if raw.has("floor_inset"):
		var inset: Dictionary = raw.floor_inset
		var r: Array = inset.get("rect", [])
		data.floor_inset = {
			"floor": str(inset.get("floor", Board.DEFAULT_FLOOR)),
			"rect": Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])) \
					if r.size() == 4 else Rect2i(),
		}
	for key: String in ["zone_seed", "shade_seed", "prop_seed"]:
		if raw.has(key):
			data[key] = int(raw[key])
	if raw.has("zone_thresholds") and (raw.zone_thresholds as Array).size() == 2:
		data.zone_thresholds = [float(raw.zone_thresholds[0]),
				float(raw.zone_thresholds[1])]
	if raw.has("zone_map"):
		var rows: Array = []
		for row in raw.zone_map:
			rows.append(str(row))
		data.zone_map = rows
	if raw.has("lint"):
		data.lint = raw.lint
	return data
