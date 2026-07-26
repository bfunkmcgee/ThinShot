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

const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]

# cell -> came_from cell, for cells the selected unit can move to.
var move_cells: Dictionary = {}
# Cells containing enemies the selected unit can shoot.
var attack_cells: Array[Vector2i] = []


func set_highlights(moves: Dictionary, attacks: Array[Vector2i]) -> void:
	move_cells = moves
	attack_cells = attacks
	queue_redraw()


func clear_highlights() -> void:
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
