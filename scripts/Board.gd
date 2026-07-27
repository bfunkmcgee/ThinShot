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
const SHADOW_RADII := {"#": 22.0, "j": 20.0, "p": 12.0, "W": DIAMOND_SHADOW}

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
# Burst-armed attack highlight: hotter orange than the normal red.
const BURST_HL := Color(1.0, 0.45, 0.05, 0.5)
# Cyan means "flanking - cover ignored" (amber is already taken by cover).
const AIM_LINE_FLANK := Color(0.45, 0.95, 1.0, 0.9)
const ATTACK_HOVER_FLANK_HL := Color(0.3, 0.85, 1.0, 0.5)
# Enemy overwatch arcs: amber, hatched on the opposite diagonal from danger.
const WATCH_FILL := Color(1.0, 0.72, 0.28, 0.10)
const WATCH_HATCH := Color(1.0, 0.72, 0.28, 0.26)

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

# cell -> came_from cell, for cells the selected unit can move to.
var move_cells: Dictionary = {}
# Cells containing enemies the selected unit can shoot.
var attack_cells: Array[Vector2i] = []
# Hover feedback state, pushed in by Battle.
var hover_cell := NO_CELL
var path_preview: Array[Vector2i] = []
var aim_from := NO_CELL
var aim_covered := false
var aim_flanking := false
var burst_mode := false
# Cells covered by enemy overwatch arcs (selection-independent).
var watch_cells: Dictionary = {}
# Cells any enemy could shoot next turn (selection-independent; cleared
# only via set_danger, never by clear_highlights).
var danger_cells: Dictionary = {}


func set_highlights(moves: Dictionary, attacks: Array[Vector2i]) -> void:
	move_cells = moves
	attack_cells = attacks
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


func set_burst_mode(value: bool) -> void:
	if burst_mode != value:
		burst_mode = value
		queue_redraw()


func clear_highlights() -> void:
	hover_cell = NO_CELL
	path_preview = []
	aim_from = NO_CELL
	aim_covered = false
	aim_flanking = false
	set_highlights({}, [])


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
			elif ch == "j":
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
## blocker. Junk (COVER) does not stop sight - it attenuates damage instead.
## Samples the segment in cell space; endpoints themselves are ignored.
func has_line_of_sight(from: Vector2i, to: Vector2i) -> bool:
	var a := Vector2(from)
	var b := Vector2(to)
	var steps := int(a.distance_to(b) * 4.0) + 1
	for i in range(1, steps):
		var p := a.lerp(b, float(i) / float(steps))
		var cell := Vector2i(roundi(p.x), roundi(p.y))
		if cell != from and cell != to and is_blocker(cell):
			return false
	return true


## True if the straight shot crosses at least one junk (COVER) cell.
## Same sampling as has_line_of_sight so the two always agree.
func shot_through_cover(from: Vector2i, to: Vector2i) -> bool:
	var a := Vector2(from)
	var b := Vector2(to)
	var steps := int(a.distance_to(b) * 4.0) + 1
	for i in range(1, steps):
		var p := a.lerp(b, float(i) / float(steps))
		var cell := Vector2i(roundi(p.x), roundi(p.y))
		if cell != from and cell != to and cell_kind(cell) == CellKind.COVER:
			return true
	return false


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
	for cell: Vector2i in danger_cells:
		var d := _diamond(cell)
		draw_colored_polygon(d, DANGER_FILL)
		for f in [0.25, 0.5, 0.75]:
			draw_line(d[3].lerp(d[2], f), d[0].lerp(d[1], f), DANGER_HATCH, 1.0, true)
	# Enemy overwatch arcs, hatched on the opposite diagonal from danger so
	# the two stay legible where they overlap.
	for cell: Vector2i in watch_cells:
		var w := _diamond(cell)
		draw_colored_polygon(w, WATCH_FILL)
		for f in [0.3, 0.6]:
			draw_line(w[3].lerp(w[0], f), w[2].lerp(w[1], f), WATCH_HATCH, 1.0, true)
	for cell: Vector2i in move_cells:
		draw_colored_polygon(_diamond(cell), MOVE_HL)
	for cell in attack_cells:
		draw_colored_polygon(_diamond(cell), BURST_HL if burst_mode else ATTACK_HL)
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
