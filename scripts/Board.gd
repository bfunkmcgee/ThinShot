class_name Board
extends Node2D

## Desert battle grid: isometric tile drawing, coordinate math, and BFS
## reachability. Cells are abstract Vector2i; only this script knows the
## 2:1 diamond projection. Highlight state is pushed in by Battle.gd.

const TILE_W := 96
const TILE_H := 48
const SIZE := Vector2i(12, 8)

# '#' = impassable rock, '.' = sand.
const MAP: Array[String] = [
	"............",
	"..#......#..",
	".....##.....",
	"..#...#..#..",
	"..#..#...#..",
	".....##.....",
	"..#......#..",
	"............",
]

const SAND_A := Color("d8c08c")
const SAND_B := Color("cdb37e")
const ROCK_TINT := Color("b89e6d")
const GRID_LINE := Color(0.35, 0.27, 0.15, 0.25)
const MOVE_HL := Color(0.95, 0.85, 0.3, 0.35)
const ATTACK_HL := Color(0.9, 0.2, 0.15, 0.4)
const HOVER_OUTLINE := Color(1.0, 0.97, 0.85, 0.9)
const PATH_DOT := Color(1.0, 0.95, 0.7, 0.9)
const AIM_LINE := Color(1.0, 0.45, 0.3, 0.85)
const ATTACK_HOVER_HL := Color(1.0, 0.35, 0.25, 0.55)

const NO_CELL := Vector2i(-1, -1)

const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]

# cell -> came_from cell, for cells the selected unit can move to.
var move_cells: Dictionary = {}
# Cells containing enemies the selected unit can shoot.
var attack_cells: Array[Vector2i] = []
# Hover feedback state, pushed in by Battle.
var hover_cell := NO_CELL
var path_preview: Array[Vector2i] = []
var aim_from := NO_CELL


func set_highlights(moves: Dictionary, attacks: Array[Vector2i]) -> void:
	move_cells = moves
	attack_cells = attacks
	queue_redraw()


func set_hover(cell: Vector2i, path: Array[Vector2i], p_aim_from: Vector2i) -> void:
	if cell == hover_cell and path == path_preview and p_aim_from == aim_from:
		return
	hover_cell = cell
	path_preview = path
	aim_from = p_aim_from
	queue_redraw()


func clear_highlights() -> void:
	hover_cell = NO_CELL
	path_preview = []
	aim_from = NO_CELL
	set_highlights({}, [])


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
	return cell.x >= 0 and cell.x < SIZE.x and cell.y >= 0 and cell.y < SIZE.y


func is_wall(cell: Vector2i) -> bool:
	return MAP[cell.y][cell.x] == "#"


static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## True if a straight shot between the two cell centers crosses no rock tile.
## Samples the segment in cell space; endpoints themselves are ignored.
func has_line_of_sight(from: Vector2i, to: Vector2i) -> bool:
	var a := Vector2(from)
	var b := Vector2(to)
	var steps := int(a.distance_to(b) * 4.0) + 1
	for i in range(1, steps):
		var p := a.lerp(b, float(i) / float(steps))
		var cell := Vector2i(roundi(p.x), roundi(p.y))
		if cell != from and cell != to and is_wall(cell):
			return false
	return true


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
			if is_wall(nxt) or blocked.call(nxt):
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


func _draw() -> void:
	for y in SIZE.y:
		for x in SIZE.x:
			var cell := Vector2i(x, y)
			var color := SAND_A if (x + y) % 2 == 0 else SAND_B
			if is_wall(cell):
				color = ROCK_TINT
			var points := _diamond(cell)
			draw_colored_polygon(points, color)
			var outline := points
			outline.append(points[0])
			draw_polyline(outline, GRID_LINE, 1.5, true)
	for cell: Vector2i in move_cells:
		draw_colored_polygon(_diamond(cell), MOVE_HL)
	for cell in attack_cells:
		draw_colored_polygon(_diamond(cell), ATTACK_HL)
	if hover_cell != NO_CELL:
		if attack_cells.has(hover_cell):
			draw_colored_polygon(_diamond(hover_cell), ATTACK_HOVER_HL)
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
		draw_dashed_line(cell_to_local(aim_from), cell_to_local(hover_cell),
				AIM_LINE, 2.0, 10.0)
