class_name Board
extends Node2D

## Desert battle grid: isometric tile drawing, coordinate math, and BFS
## reachability. Cells are abstract Vector2i; only this script knows the
## 2:1 diamond projection. Highlight state is pushed in by Battle.gd.

const TILE_W := 128
const TILE_H := 60

## What a cell means for movement and shooting.
enum CellKind {
	OPEN,   # walkable, no LOS effect ('.', 'p')
	BLOCK,  # impassable, blocks LOS ('#', 'W', structure footprints)
	COVER,  # impassable, LOS passes at half damage ('j')
}

const FLOOR_SHEET := preload(
		"res://assets/Tiles/Environments/Desert/Cracked_Desert_floor.png")

# Measured source regions in the floor sheet: 128x60 diamond faces on a
# 129px stride, rows at y 34/163/292. The plant tile (index 6) is 6px
# taller; its extra height hangs above the diamond when drawn.
const TILE_REGIONS: Array[Rect2] = [
	Rect2(0, 34, 128, 60),    # 0 cracked plain
	Rect2(129, 34, 128, 60),  # 1 cracked plain
	Rect2(258, 34, 128, 60),  # 2 fine cracks
	Rect2(387, 34, 128, 60),  # 3 dense cracks
	Rect2(0, 163, 128, 60),   # 4 crater (accent)
	Rect2(129, 163, 128, 60), # 5 mottled
	Rect2(258, 157, 128, 66), # 6 plant tuft (accent, taller)
	Rect2(387, 163, 128, 60), # 7 log debris (accent)
	Rect2(0, 292, 128, 60),   # 8 sandy waves
	Rect2(129, 292, 128, 60), # 9 sandy cracks
]

# Tile families by terrain zone (indices into TILE_REGIONS), carved out of
# the map by smooth noise so neighboring cells read as one terrain patch.
const ZONE_FAMILIES: Array = [
	[8, 9],     # 0: sandy wash
	[0, 1, 2],  # 1: lightly cracked hardpan
	[3, 5],     # 2: heavily cracked / mottled hardpan
]
# One themed accent per zone: plants grow in sand, debris lies among the
# light cracks, craters pock the heavy hardpan.
const ZONE_ACCENTS: Array[int] = [6, 7, 4]

const ACCENT_CHANCE := 0.07
const ACCENT_MIN_SPACING := 2  # Chebyshev cells between any two accents

# Ground contact shadows for props, matching Unit's sun direction. Positive
# values are ellipse radii; DIAMOND_SHADOW means "shrunk tile diamond", so
# adjacent walls and structure footprints union into one cast shadow.
const SHADOW_SQUASH := 0.469  # TILE_H / TILE_W
const SHADOW_OFFSET := Vector2(3, 2)
const SHADOW_COLOR := Color(0.16, 0.10, 0.06, 0.24)
const DIAMOND_SHADOW := -1.0
const SHADOW_RADII := {"#": 22.0, "j": 20.0, "p": 12.0, "d": 15.0, "W": DIAMOND_SHADOW}

const GRID_LINE := Color(0.35, 0.27, 0.15, 0.25)
const MOVE_HL := Color(0.95, 0.85, 0.3, 0.35)
const ATTACK_HL := Color(0.9, 0.2, 0.15, 0.4)
const DANGER_FILL := Color(0.85, 0.15, 0.1, 0.13)
const DANGER_HATCH := Color(0.85, 0.2, 0.12, 0.30)
const HOVER_OUTLINE := Color(1.0, 0.97, 0.85, 0.9)
const PATH_DOT := Color(1.0, 0.95, 0.7, 0.9)
const AIM_LINE := Color(1.0, 0.45, 0.3, 0.85)
const ATTACK_HOVER_HL := Color(1.0, 0.35, 0.25, 0.55)
# Amber variants signal a shot that clips junk cover (half damage).
const AIM_LINE_COVER := Color(1.0, 0.82, 0.25, 0.85)
const ATTACK_HOVER_COVER_HL := Color(1.0, 0.65, 0.2, 0.5)
# Armed-fire-mode highlights: hotter than the normal attack red.
const BURST_HL := Color(1.0, 0.45, 0.05, 0.5)
const AUTO_HL := Color(1.0, 0.72, 0.1, 0.55)
const SUPPRESS_HL := Color(0.45, 0.72, 0.9, 0.5)
# Cyan means "flanking - cover ignored" (amber is already taken by cover).
const AIM_LINE_FLANK := Color(0.45, 0.95, 1.0, 0.9)
const ATTACK_HOVER_FLANK_HL := Color(0.3, 0.85, 1.0, 0.5)
# Overwatch arcs, hatched on the opposite diagonal from danger. Amber for
# enemy arcs (a threat), green for your own (ground you have covered).
# Thrown ordnance. The blast preview is the footprint a grenade would cover
# if released at the hovered cell; smoke is live cover already on the board.
const BLAST_FRAG_HL := Color(1.0, 0.42, 0.12, 0.42)
const BLAST_SMOKE_HL := Color(0.80, 0.84, 0.88, 0.38)
const BLAST_EDGE := Color(1.0, 0.85, 0.6, 0.75)
const SMOKE_FILL := Color(0.74, 0.72, 0.68, 0.50)
const SMOKE_EDGE := Color(0.84, 0.83, 0.80, 0.30)

# Mission objectives. Caches pulse so they read as things to act on rather
# than scenery; the extraction zone goes flat green and only lights up once
# it is actually open.
const CACHE_FILL := Color(0.95, 0.35, 0.12, 0.30)
const CACHE_EDGE := Color(1.0, 0.66, 0.26, 0.95)
const CACHE_REACH_EDGE := Color(1.0, 0.95, 0.55, 1.0)
const EXTRACT_FILL := Color(0.35, 0.9, 0.45, 0.16)
const EXTRACT_EDGE := Color(0.5, 1.0, 0.6, 0.55)
const EXTRACT_ARMED_FILL := Color(0.4, 1.0, 0.5, 0.30)
const EXTRACT_ARMED_EDGE := Color(0.7, 1.0, 0.8, 0.95)

# Cover readability. A bar hugging a tile edge means "something to get behind
# on that side"; a dot in the middle of a reachable tile means "there is cover
# here somewhere", so a route between covered tiles can be read at a glance.
const HAZARD_HL := Color(1.0, 0.55, 0.08, 0.42)
const HAZARD_EDGE := Color(1.0, 0.82, 0.3, 0.95)

const COVER_HALF_PIP := Color(0.55, 0.86, 0.62, 0.95)
const COVER_FULL_PIP := Color(0.45, 1.0, 0.58, 1.0)
const COVER_DEST_DOT := Color(0.55, 0.95, 0.65, 0.55)
# Which diamond vertices bound the edge facing each orthogonal neighbour.
# _diamond() is ordered [top, right, bottom, left] and +x reads south-east.
const COVER_EDGES := {
	Vector2i(1, 0): [1, 2],   # south-east
	Vector2i(0, 1): [2, 3],   # south-west
	Vector2i(-1, 0): [3, 0],  # north-west
	Vector2i(0, -1): [0, 1],  # north-east
}

const WATCH_FILL := Color(1.0, 0.72, 0.28, 0.10)
const WATCH_HATCH := Color(1.0, 0.72, 0.28, 0.26)
const WATCH_FILL_ALLY := Color(0.45, 0.92, 0.5, 0.10)
const WATCH_HATCH_ALLY := Color(0.5, 0.95, 0.55, 0.26)

const NO_CELL := Vector2i(-1, -1)

const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]

# Level state, loaded by set_level().
var size := Vector2i(12, 8)
var map_rows: Array = []
var _kind: Array = []                     # size.y rows of Array[int] CellKind
var _structure_cells: Dictionary = {}     # Vector2i -> true

# Per-cell render info ({region, flip, shade}) built by set_level.
var tile_cache: Array = []

# cell -> came_from cell, for every cell the selected unit can route
# THROUGH. Paths are reconstructed from this.
var move_cells: Dictionary = {}
# The subset of those it could actually stop on - drawn and clickable.
# Squadmates can be walked past but not stood on, so these differ.
var move_dests: Dictionary = {}
# Cells containing enemies the selected unit can shoot.
var attack_cells: Array[Vector2i] = []
# Hover feedback state, pushed in by Battle.
var hover_cell := NO_CELL
var path_preview: Array[Vector2i] = []
var aim_from := NO_CELL
var aim_covered := false
var aim_flanking := false
var fire_mode := 0  # mirrors Battle.FireMode; tints the attack highlights
# Cells covered by overwatch arcs: cell -> true if the watcher is hostile.
# Objectives. cache_cells maps an intact cache cell -> true if a selected
# scout is close enough to demolish it this turn.
# Cover overlay: the one cell to spell out edge by edge, and the set of
# reachable cells that have cover at all.
var cover_focus := NO_CELL
var cover_dests: Dictionary = {}

# Contact shadows for props that are not map characters. Objective targets are
# spawned from the objective list rather than a map char, so without this they
# sit on the sand with nothing under them and read as pasted on.
var prop_shadows: Dictionary = {}

# The tile outline reads as a tactical grid, which is right in a battle and
# wrong in a camp you simply walk around.
var show_grid := true

# Fuel drums the selected unit could put a round into. Drawn hotter than an
# attack tile so a hazard never reads as an enemy.
var hazard_cells: Dictionary = {}

var cache_cells: Dictionary = {}
var extract_cells: Dictionary = {}
var extract_armed := false
var _pulse := 0.0

# Live smoke: blocks line of sight for both sides but never movement.
var smoke_cells: Dictionary = {}
# Preview footprint while a grenade is being aimed; true = frag, false = smoke.
var blast_cells: Dictionary = {}
var blast_is_frag := true

var watch_cells: Dictionary = {}
# Cells any enemy could shoot next turn (selection-independent; cleared
# only via set_danger, never by clear_highlights).
var danger_cells: Dictionary = {}


func set_highlights(moves: Dictionary, dests: Dictionary,
		attacks: Array[Vector2i], hazards := {}) -> void:
	move_cells = moves
	move_dests = dests
	attack_cells = attacks
	hazard_cells = hazards
	queue_redraw()


func set_hover(cell: Vector2i, path: Array[Vector2i], p_aim_from: Vector2i,
		p_aim_covered := false, p_aim_flanking := false) -> void:
	if cell == hover_cell and path == path_preview and p_aim_from == aim_from \
			and p_aim_covered == aim_covered and p_aim_flanking == aim_flanking:
		return
	hover_cell = cell
	path_preview = path
	aim_from = p_aim_from
	aim_covered = p_aim_covered
	aim_flanking = p_aim_flanking
	queue_redraw()


func set_watch_cells(cells: Dictionary) -> void:
	watch_cells = cells
	queue_redraw()


func set_danger(cells: Dictionary) -> void:
	danger_cells = cells
	queue_redraw()


func set_cover_overlay(focus: Vector2i, dests: Dictionary) -> void:
	if focus == cover_focus and dests == cover_dests:
		return
	cover_focus = focus
	cover_dests = dests
	queue_redraw()


func set_objectives(caches: Dictionary, extracts: Dictionary, armed: bool) -> void:
	cache_cells = caches
	extract_cells = extracts
	extract_armed = armed
	set_process(not caches.is_empty() or not extracts.is_empty())
	queue_redraw()


## Objective markers breathe so they stay findable on a busy board.
func _process(delta: float) -> void:
	_pulse = fmod(_pulse + delta * 2.2, TAU)
	queue_redraw()


func set_smoke(cells: Dictionary) -> void:
	smoke_cells = cells
	queue_redraw()


func set_blast_cells(cells: Dictionary, is_frag: bool) -> void:
	if cells == blast_cells and is_frag == blast_is_frag:
		return
	blast_cells = cells
	blast_is_frag = is_frag
	queue_redraw()


func set_fire_mode(value: int) -> void:
	if fire_mode != value:
		fire_mode = value
		queue_redraw()


func clear_highlights() -> void:
	hover_cell = NO_CELL
	path_preview = []
	aim_from = NO_CELL
	aim_covered = false
	aim_flanking = false
	set_blast_cells({}, true)  # smoke is board state and deliberately survives
	set_cover_overlay(NO_CELL, {})
	set_highlights({}, {}, [])


## Load a level definition: cell kinds from the map chars plus structure
## footprints, then rebuild the floor with the level's noise character.
func set_level(data: Dictionary) -> void:
	size = data.size
	map_rows = data.map
	_structure_cells = {}
	for s: Dictionary in data.structures:
		var anchor: Vector2i = s.anchor
		var struct_size: Vector2i = s.size
		for dy in struct_size.y:
			for dx in struct_size.x:
				_structure_cells[anchor + Vector2i(dx, dy)] = true
	_kind = []
	for y in size.y:
		var row: Array[int] = []
		for x in size.x:
			var cell := Vector2i(x, y)
			var ch: String = map_rows[y][x]
			if ch == "#" or ch == "W" or _structure_cells.has(cell):
				row.append(CellKind.BLOCK)
			elif ch == "j" or ch == "d":
				# A fuel drum is cover you can shoot over, exactly like junk -
				# right up until somebody sets it off.
				row.append(CellKind.COVER)
			else:
				row.append(CellKind.OPEN)
		_kind.append(row)
	var thresholds: Array = data.get("zone_thresholds", [-0.12, 0.22])
	_build_tile_cache(data.get("zone_seed", 7), data.get("shade_seed", 13), thresholds)
	queue_redraw()


## Diamond center of a cell, in Board-local pixels (2:1 isometric projection).
func cell_to_local(cell: Vector2i) -> Vector2:
	return Vector2(
		(cell.x - cell.y) * TILE_W / 2.0,
		(cell.x + cell.y) * TILE_H / 2.0,
	)


func cell_to_global(cell: Vector2i) -> Vector2:
	return to_global(cell_to_local(cell))


func global_to_cell(point: Vector2) -> Vector2i:
	var p := to_local(point)
	var fx := p.x / (TILE_W / 2.0)
	var fy := p.y / (TILE_H / 2.0)
	return Vector2i(roundi((fx + fy) / 2.0), roundi((fy - fx) / 2.0))


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < size.x and cell.y >= 0 and cell.y < size.y


func cell_kind(cell: Vector2i) -> CellKind:
	return _kind[cell.y][cell.x]


func is_blocker(cell: Vector2i) -> bool:
	return cell_kind(cell) == CellKind.BLOCK


func is_walkable(cell: Vector2i) -> bool:
	return cell_kind(cell) == CellKind.OPEN


func map_char(cell: Vector2i) -> String:
	return map_rows[cell.y][cell.x] if in_bounds(cell) else ""


func is_structure(cell: Vector2i) -> bool:
	return _structure_cells.has(cell)


static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## Facing sector (0=E, 1=SE .. 7=NE) pointing from one cell toward another.
## Uses the same screen-space formula as Unit.set_facing, so a previewed
## flank and a resolved flank can never disagree. -1 for the same cell.
static func sector_from_to(from: Vector2i, to: Vector2i) -> int:
	if from == to:
		return -1
	var d := to - from
	var screen := Vector2(
			float(d.x - d.y) * TILE_W / 2.0,
			float(d.x + d.y) * TILE_H / 2.0)
	return wrapi(roundi(screen.angle() / (TAU / 8.0)), 0, 8)


## True if a straight shot between the two cell centers crosses no full
## blocker and no smoke. Junk (COVER) does not stop sight - it attenuates
## damage instead. Samples the segment in cell space; endpoints themselves are
## ignored, so a unit standing in its own smoke can still shoot out of it and
## be shot at - only lines that pass THROUGH the cloud are cut.
## Every sight test in the game routes through here, so smoke shortens overwatch
## cones, hides the danger overlay, and blinds the AI without further plumbing.
func has_line_of_sight(from: Vector2i, to: Vector2i) -> bool:
	var a := Vector2(from)
	var b := Vector2(to)
	var steps := int(a.distance_to(b) * 4.0) + 1
	for i in range(1, steps):
		var p := a.lerp(b, float(i) / float(steps))
		var cell := Vector2i(roundi(p.x), roundi(p.y))
		if cell == from or cell == to:
			continue
		if is_blocker(cell) or smoke_cells.has(cell):
			return false
	return true


# ------------------------------------------------------------------- cover --
# Cover is a property of the cell you STAND on, not of the line a bullet
# happens to cross. A unit is covered from a direction when the neighbouring
# cell that way is something to get behind - so hugging a wall is a decision,
# and the ground between two positions is a route rather than a lottery.
#
# Junk gives HALF cover: you can shoot over it, and it can be shot over, at
# reduced damage. Rock, wall and building give FULL cover: much harder to hit
# past, and it blocks sight both ways - which is what the peek rule exists to
# work around.

enum CoverLevel { NONE, HALF, FULL }

## An adjacent blocker shields the sector pointing at it plus the sector each
## side, so one wall covers a 135 degree wedge and an inside corner covers most
## of the field. Matches the 135 degree front arc units already use.
const COVER_SPREAD := 1


func cover_level_of(cell: Vector2i) -> CoverLevel:
	if not in_bounds(cell):
		return CoverLevel.FULL  # the map edge is something to put your back to
	match cell_kind(cell):
		CellKind.BLOCK:
			return CoverLevel.FULL
		CellKind.COVER:
			return CoverLevel.HALF
	return CoverLevel.NONE


## Best cover this cell has against each of the 8 facing sectors.
## Returns sector -> CoverLevel for every sector that has any.
func cover_map_at(cell: Vector2i) -> Dictionary:
	var out := {}
	for dir in DIRS:
		var level := cover_level_of(cell + dir)
		if level == CoverLevel.NONE:
			continue
		var sector := sector_from_to(cell, cell + dir)
		for offset in range(-COVER_SPREAD, COVER_SPREAD + 1):
			var s := wrapi(sector + offset, 0, 8)
			if int(out.get(s, CoverLevel.NONE)) < int(level):
				out[s] = level
	return out


## The cover a target standing at `target` has against a shot from `from`.
func cover_between(from: Vector2i, target: Vector2i) -> CoverLevel:
	var sector := sector_from_to(target, from)
	return cover_map_at(target).get(sector, CoverLevel.NONE)


## Which neighbouring cell is actually doing the protecting, so effects can
## spark off the right piece of scenery. NO_CELL when the target is exposed.
func cover_source(from: Vector2i, target: Vector2i) -> Vector2i:
	var want := sector_from_to(target, from)
	var best := NO_CELL
	var best_level := CoverLevel.NONE
	for dir in DIRS:
		var level := cover_level_of(target + dir)
		if level == CoverLevel.NONE:
			continue
		var sector := sector_from_to(target, target + dir)
		if absi(wrapi(want - sector + 4, 0, 8) - 4) > COVER_SPREAD:
			continue
		if int(level) > int(best_level):
			best_level = level
			best = target + dir
	return best


## True if this cell is worth moving to for protection at all.
func has_any_cover(cell: Vector2i) -> bool:
	return not cover_map_at(cell).is_empty()


## Line of sight that ignores a given set of cells - used by the peek rule to
## look past the specific piece of cover the shooter is hugging, and nothing
## else on the line.
func _los_ignoring(from: Vector2i, to: Vector2i, ignore: Dictionary) -> bool:
	var a := Vector2(from)
	var b := Vector2(to)
	var steps := int(a.distance_to(b) * 4.0) + 1
	for i in range(1, steps):
		var p := a.lerp(b, float(i) / float(steps))
		var cell := Vector2i(roundi(p.x), roundi(p.y))
		if cell == from or cell == to or ignore.has(cell):
			continue
		if is_blocker(cell) or smoke_cells.has(cell):
			return false
	return true


## Can a shooter at `from` lean around the edge of its own full cover to hit
## `to`? Only fires when the direct line is blocked. The shooter does not move:
## it leans **perpendicular** to whatever it is hugging and shoots past the
## edge, so the piece being hugged stops blocking but nothing else does.
##
## That is what separates a corner from a wall. Lean past the end of a wall run
## and the shot is there; lean against the middle of an unbroken wall and the
## next section of the same wall is still in the way.
## Returns the cell leaned toward, or NO_CELL when there is no angle.
func peek_origin(from: Vector2i, to: Vector2i) -> Vector2i:
	if has_line_of_sight(from, to):
		return NO_CELL  # nothing to lean around
	# Only full cover is worth leaning past; junk never blocked sight anyway.
	var hugged := {}
	for dir in DIRS:
		if cover_level_of(from + dir) == CoverLevel.FULL:
			hugged[from + dir] = true
	if hugged.is_empty():
		return NO_CELL
	for cover_cell: Vector2i in hugged:
		var d: Vector2i = cover_cell - from
		for perp in [Vector2i(d.y, d.x), Vector2i(-d.y, -d.x)]:
			var side: Vector2i = from + perp
			if not in_bounds(side) or is_blocker(side) or smoke_cells.has(side):
				continue
			if _los_ignoring(side, to, hugged):
				return side
	return NO_CELL


func can_peek(from: Vector2i, to: Vector2i) -> bool:
	return peek_origin(from, to) != NO_CELL


## Can a shooter at `from` engage `to` at all - straight down the line, or by
## leaning around the edge of whatever it is tucked behind?
func can_engage(from: Vector2i, to: Vector2i) -> bool:
	return has_line_of_sight(from, to) or peek_origin(from, to) != NO_CELL


## BFS from start up to max_range steps. Walls and cells where blocked.call(cell)
## is true are impassable. Returns {reachable_cell: came_from_cell}, excluding start.
func flood_fill(start: Vector2i, max_range: int, blocked: Callable) -> Dictionary:
	var came_from := {start: start}
	var dist := {start: 0}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var cur: Vector2i = frontier.pop_front()
		if dist[cur] == max_range:
			continue
		for dir in DIRS:
			var nxt := cur + dir
			if not in_bounds(nxt) or came_from.has(nxt):
				continue
			if not is_walkable(nxt) or blocked.call(nxt):
				continue
			came_from[nxt] = cur
			dist[nxt] = dist[cur] + 1
			frontier.push_back(nxt)
	came_from.erase(start)
	return came_from


## Ordered path (first step .. dest) from a flood_fill result.
func reconstruct_path(came_from: Dictionary, dest: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [dest]
	while came_from.has(path[0]):
		path.push_front(came_from[path[0]])
	path.pop_front()  # drop the start cell itself
	return path


func _diamond(cell: Vector2i) -> PackedVector2Array:
	var c := cell_to_local(cell)
	return PackedVector2Array([
		c + Vector2(0, -TILE_H / 2.0),
		c + Vector2(TILE_W / 2.0, 0),
		c + Vector2(0, TILE_H / 2.0),
		c + Vector2(-TILE_W / 2.0, 0),
	])


## Deterministic per-cell pseudo-random in [0, 1); salt separates streams.
static func _hash01(cell: Vector2i, salt: int) -> float:
	return float(absi(cell.x * 92821 + cell.y * 31337 + salt * 53987) % 997) / 997.0


## Precompute each cell's tile region, mirror flag, and shade tint.
## Everything is seeded/hashed, so a level's floor is identical every run.
func _build_tile_cache(zone_seed: int, shade_seed: int, thresholds: Array) -> void:
	var zone_noise := FastNoiseLite.new()
	zone_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	zone_noise.seed = zone_seed
	zone_noise.frequency = 0.17
	var shade_noise := FastNoiseLite.new()
	shade_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	shade_noise.seed = shade_seed
	shade_noise.frequency = 0.09

	var accent_cells: Array[Vector2i] = []
	tile_cache = []
	for y in size.y:
		var row: Array = []
		for x in size.x:
			var cell := Vector2i(x, y)
			var n := zone_noise.get_noise_2d(cell.x, cell.y)
			var zone: int = 0 if n < thresholds[0] else (1 if n < thresholds[1] else 2)
			var family: Array = ZONE_FAMILIES[zone]
			var variant: int = family[int(_hash01(cell, 1) * family.size()) % family.size()]
			if map_char(cell) == "." and not is_structure(cell) \
					and _hash01(cell, 2) < ACCENT_CHANCE:
				var clear := true
				for placed in accent_cells:
					if maxi(absi(placed.x - x), absi(placed.y - y)) <= ACCENT_MIN_SPACING:
						clear = false
						break
				if clear:
					variant = ZONE_ACCENTS[zone]
					accent_cells.append(cell)
			# Subtle brightness patches (0.94..1.0) fake large-scale lighting.
			var shade := 0.94 + 0.06 * (shade_noise.get_noise_2d(cell.x, cell.y) * 0.5 + 0.5)
			var shadow: float = DIAMOND_SHADOW if is_structure(cell) \
					else SHADOW_RADII.get(map_char(cell), 0.0)
			row.append({
				"region": TILE_REGIONS[variant],
				"flip": _hash01(cell, 3) < 0.5,
				"shade": Color(shade, shade, shade),
				"shadow": shadow,
			})
		tile_cache.append(row)


func _draw() -> void:
	if tile_cache.is_empty():
		return
	for y in size.y:
		for x in size.x:
			var cell := Vector2i(x, y)
			var info: Dictionary = tile_cache[y][x]
			var region: Rect2 = info.region
			var c := cell_to_local(cell)
			var dest := Rect2(
				c.x - TILE_W / 2.0,
				c.y - TILE_H / 2.0 - (region.size.y - TILE_H),
				region.size.x, region.size.y)
			if info.flip:
				# Mirror around the tile's vertical center line.
				draw_set_transform(Vector2(2.0 * c.x, 0.0), 0.0, Vector2(-1, 1))
			draw_texture_rect_region(FLOOR_SHEET, dest, region, info.shade)
			if info.flip:
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			if show_grid:
				var outline := _diamond(cell)
				outline.append(outline[0])
				draw_polyline(outline, GRID_LINE, 1.5, true)
	# Prop shadows sit above the floor but below every gameplay overlay.
	for y in size.y:
		for x in size.x:
			var radius: float = tile_cache[y][x].shadow
			if radius == 0.0:
				continue
			var center := cell_to_local(Vector2i(x, y)) + SHADOW_OFFSET
			if radius == DIAMOND_SHADOW:
				var shape := PackedVector2Array()
				for point in _diamond(Vector2i(x, y)):
					shape.append(center + (point - cell_to_local(Vector2i(x, y))) * 0.88)
				draw_colored_polygon(shape, SHADOW_COLOR)
			else:
				draw_set_transform(center, 0.0, Vector2(1.0, SHADOW_SQUASH))
				draw_circle(Vector2.ZERO, radius, SHADOW_COLOR)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Objective props are not map characters, so they get their contact shadow
	# from here instead of from the tile cache.
	for cell: Vector2i in prop_shadows:
		var centre := cell_to_local(cell) + SHADOW_OFFSET
		draw_set_transform(centre, 0.0, Vector2(1.0, SHADOW_SQUASH))
		draw_circle(Vector2.ZERO, float(prop_shadows[cell]), SHADOW_COLOR)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Smoke is world, not overlay: it goes down with the props so every
	# gameplay marking still reads on top of it.
	for cell: Vector2i in smoke_cells:
		var s := _diamond(cell)
		draw_colored_polygon(s, SMOKE_FILL)
		var ring := s.duplicate()
		ring.append(ring[0])
		draw_polyline(ring, SMOKE_EDGE, 2.0, true)
	# Objectives sit above smoke and below the move/attack overlays: they are
	# where you are going, not what you can do this instant.
	var breath := 0.5 + 0.5 * sin(_pulse)
	for cell: Vector2i in extract_cells:
		var e := _diamond(cell)
		draw_colored_polygon(e, EXTRACT_ARMED_FILL if extract_armed else EXTRACT_FILL)
		var e_ring := e.duplicate()
		e_ring.append(e_ring[0])
		if extract_armed:
			draw_polyline(e_ring, EXTRACT_ARMED_EDGE.lerp(EXTRACT_EDGE, breath), 2.5, true)
		else:
			draw_polyline(e_ring, EXTRACT_EDGE, 1.5, true)
	for cell: Vector2i in cache_cells:
		var in_reach: bool = cache_cells[cell]
		var k := _diamond(cell)
		draw_colored_polygon(k, CACHE_FILL)
		var k_ring := k.duplicate()
		k_ring.append(k_ring[0])
		var edge := CACHE_REACH_EDGE if in_reach else CACHE_EDGE
		draw_polyline(k_ring, edge.lerp(CACHE_FILL, breath * 0.6),
				3.0 if in_reach else 2.0, true)
	for cell: Vector2i in danger_cells:
		var d := _diamond(cell)
		draw_colored_polygon(d, DANGER_FILL)
		for f in [0.25, 0.5, 0.75]:
			draw_line(d[3].lerp(d[2], f), d[0].lerp(d[1], f), DANGER_HATCH, 1.0, true)
	# Overwatch arcs, hatched on the opposite diagonal from danger so the
	# two stay legible where they overlap.
	for cell: Vector2i in watch_cells:
		var hostile: bool = watch_cells[cell]
		var w := _diamond(cell)
		draw_colored_polygon(w, WATCH_FILL if hostile else WATCH_FILL_ALLY)
		var hatch := WATCH_HATCH if hostile else WATCH_HATCH_ALLY
		for f in [0.3, 0.6]:
			draw_line(w[3].lerp(w[0], f), w[2].lerp(w[1], f), hatch, 1.0, true)
	for cell: Vector2i in move_dests:
		draw_colored_polygon(_diamond(cell), MOVE_HL)
	# A dot marks a reachable tile that has cover of some kind, so a bound
	# from one piece of cover to the next can be planned without hovering
	# every candidate.
	for cell: Vector2i in cover_dests:
		draw_circle(cell_to_local(cell) + Vector2(0, 4.0), 3.5, COVER_DEST_DOT)
	# The focused tile gets it spelled out: a bar on every edge that has
	# something worth hiding behind, thicker for a wall than for scrap.
	if cover_focus != NO_CELL:
		var d := _diamond(cover_focus)
		var centre := cell_to_local(cover_focus)
		for dir: Vector2i in COVER_EDGES:
			var level := cover_level_of(cover_focus + dir)
			if level == CoverLevel.NONE:
				continue
			var pair: Array = COVER_EDGES[dir]
			var a: Vector2 = d[int(pair[0])]
			var b: Vector2 = d[int(pair[1])]
			var inward := (centre - (a + b) * 0.5).normalized() * 6.0
			var full := level == CoverLevel.FULL
			draw_line(a.lerp(b, 0.22) + inward, a.lerp(b, 0.78) + inward,
					COVER_FULL_PIP if full else COVER_HALF_PIP,
					5.0 if full else 3.0, true)
	var attack_color := ATTACK_HL
	if fire_mode == 1:
		attack_color = BURST_HL
	elif fire_mode == 2:
		attack_color = AUTO_HL
	elif fire_mode == 3:
		attack_color = SUPPRESS_HL
	for cell in attack_cells:
		draw_colored_polygon(_diamond(cell), attack_color)
	for cell: Vector2i in hazard_cells:
		var h := _diamond(cell)
		draw_colored_polygon(h, HAZARD_HL)
		var ring := h.duplicate()
		ring.append(ring[0])
		draw_polyline(ring, HAZARD_EDGE, 2.0, true)
	# Grenade footprint under the cursor, outlined so the exact cells that
	# will be caught are unambiguous before the throw is committed.
	# blast_cells maps cell -> damage. A frag falls off toward the corners, so
	# the softer ring is drawn dimmer and thinner-edged; smoke has no falloff
	# and stays uniform.
	var peak := 1
	for cell: Vector2i in blast_cells:
		peak = maxi(peak, int(blast_cells[cell]))
	for cell: Vector2i in blast_cells:
		var b := _diamond(cell)
		var col := BLAST_FRAG_HL if blast_is_frag else BLAST_SMOKE_HL
		var core := not blast_is_frag or int(blast_cells[cell]) >= peak
		if not core:
			col.a *= 0.45
		draw_colored_polygon(b, col)
		var edge := b.duplicate()
		edge.append(edge[0])
		draw_polyline(edge, BLAST_EDGE if core else Color(BLAST_EDGE, 0.45),
				2.0 if core else 1.0, true)
	if hover_cell != NO_CELL:
		if attack_cells.has(hover_cell):
			var hl := ATTACK_HOVER_HL
			if aim_flanking:
				hl = ATTACK_HOVER_FLANK_HL
			elif aim_covered:
				hl = ATTACK_HOVER_COVER_HL
			draw_colored_polygon(_diamond(hover_cell), hl)
		var outline := _diamond(hover_cell)
		outline.append(outline[0])
		draw_polyline(outline, HOVER_OUTLINE, 2.5, true)
	if not path_preview.is_empty():
		var centers := PackedVector2Array()
		for cell in path_preview:
			centers.append(cell_to_local(cell))
		if centers.size() >= 2:
			draw_polyline(centers, PATH_DOT, 2.0, true)
		for i in centers.size():
			draw_circle(centers[i], 8.0 if i == centers.size() - 1 else 5.0, PATH_DOT)
	if aim_from != NO_CELL and hover_cell != NO_CELL:
		var line_color := AIM_LINE
		if aim_flanking:
			line_color = AIM_LINE_FLANK
		elif aim_covered:
			line_color = AIM_LINE_COVER
		draw_dashed_line(cell_to_local(aim_from), cell_to_local(hover_cell),
				line_color, 2.0, 10.0)
