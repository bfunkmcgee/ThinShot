class_name ObjectiveMarks
extends Node2D

## Floating beacons over mission objectives, drawn above every unit and
## structure so an objective can never be lost behind the scenery.
##
## Two things made caches hard to find without this. They reuse a scrap-pile
## texture on maps already strewn with scrap, and - because the board layer
## sits below the entities - a structure sprite tall enough to overlap the cell
## painted over both the pile and its board marker. A beacon in its own layer
## above everything answers both at once.

const BEACON_COLOR := Color("ffb02e")
const BEACON_GLOW := Color(1.0, 0.78, 0.3, 0.30)
const STEM_COLOR := Color(1.0, 0.72, 0.25, 0.45)
# How far above the cell the beacon floats, and how far it bobs.
const HOVER := 104.0
const BOB := 7.0
const SIZE := 11.0
const SPIN := 2.0

var marks: Array[Vector2] = []
var _t := 0.0


func _ready() -> void:
	z_index = 40  # above units (y-sorted, ~0) and the additive glow layer (15)
	set_process(false)


func set_marks(positions: Array[Vector2]) -> void:
	marks = positions
	set_process(not marks.is_empty())
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta * SPIN
	queue_redraw()


func _draw() -> void:
	for i in marks.size():
		# Phase per beacon so several never pulse in lockstep.
		var phase := _t + float(i) * 0.8
		var bob := sin(phase) * BOB
		var centre: Vector2 = marks[i] + Vector2(0, -HOVER + bob)
		# Soft halo, then a solid downward-pointing chevron pointing at the
		# cell it belongs to.
		draw_circle(centre, SIZE * 2.1, BEACON_GLOW)
		draw_line(centre + Vector2(0, SIZE), marks[i] + Vector2(0, -22.0),
				STEM_COLOR, 2.0, true)
		draw_colored_polygon(PackedVector2Array([
			centre + Vector2(0, SIZE),
			centre + Vector2(-SIZE, -SIZE * 0.6),
			centre + Vector2(SIZE, -SIZE * 0.6),
		]), BEACON_COLOR)
