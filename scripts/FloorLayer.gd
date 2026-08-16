class_name FloorLayer
extends Node2D

## The still half of the board's picture: tile blits, distance haze, and every
## contact shadow. Split out of Board so the 160-blit floor repaints only when
## the level or the prop set changes, while Board._draw stays free to redraw
## its highlights every frame - and so ground-level effects can slot between
## the two (FloorLayer at z -2, fx_ground at -1, Board's overlays at 0).
##
## Board creates one in _ready, hands it a back-reference, and forwards
## redraws from set_level() / set_prop_shadows(). Everything here is read
## through that reference; this node owns no state of its own.

## Haze bands dimmer than this are not worth a polygon per cell - the nearest
## band's 0.02 alpha is invisible over sand.
const HAZE_MIN_VISIBLE := 0.06

var board: Board = null


func _draw() -> void:
	if board == null or board.tile_cache.is_empty():
		return
	for y in board.size.y:
		for x in board.size.x:
			var cell := Vector2i(x, y)
			var info: Dictionary = board.tile_cache[y][x]
			var region: Rect2 = info.region
			var c := board.cell_to_local(cell)
			var dest := Rect2(
				c.x - Board.TILE_W / 2.0,
				c.y - Board.TILE_H / 2.0 - (region.size.y - Board.TILE_H),
				region.size.x, region.size.y)
			if info.flip:
				# Mirror around the tile's vertical center line.
				draw_set_transform(Vector2(2.0 * c.x, 0.0), 0.0, Vector2(-1, 1))
			draw_texture_rect_region(info.sheet, dest, region, info.shade)
			if info.flip:
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Distance haze over the bare tiles, quantised into the same depth bands
	# the props' dust materials use (Battle/Camp _dust_material), so the
	# ground recedes with what stands on it instead of staying pin-sharp
	# underneath hazed scenery.
	var haze: Vector3 = board.floor_mood().get("haze", Vector3(0.80, 0.71, 0.55))
	var span := maxi(board.size.x + board.size.y - 2, 1)
	for y in board.size.y:
		for x in board.size.x:
			var depth := 1.0 - float(x + y) / float(span)  # 1 at the far corner
			var band := clampi(int(depth * float(Board.HAZE_BANDS)), 0,
					Board.HAZE_BANDS - 1)
			var t := Board.HAZE_MAX * (float(band) + 0.5) / float(Board.HAZE_BANDS)
			if t < HAZE_MIN_VISIBLE:
				continue
			draw_colored_polygon(board._diamond(Vector2i(x, y)),
					Color(haze.x, haze.y, haze.z, t))
	# Contact shadows go on the hazed ground, below every gameplay overlay.
	for y in board.size.y:
		for x in board.size.x:
			var radius: float = board.tile_cache[y][x].shadow
			if radius == 0.0:
				continue
			var centre := board.cell_to_local(Vector2i(x, y)) + Board.SHADOW_OFFSET
			if radius == Board.DIAMOND_SHADOW:
				var shape := PackedVector2Array()
				for point in board._diamond(Vector2i(x, y)):
					shape.append(centre + (point - board.cell_to_local(Vector2i(x, y))) * 0.88)
				draw_colored_polygon(shape, board.shadow_tone(Board.SHADOW_COLOR.a))
			else:
				draw_set_transform(centre, 0.0, Vector2(1.0, Board.SHADOW_SQUASH))
				draw_circle(Vector2.ZERO, radius,
						board.shadow_tone(Board.SHADOW_COLOR.a))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Objective props are not map characters, so their contact shadows come
	# from the dictionary Battle hands the Board instead of the tile cache.
	for cell: Vector2i in board.prop_shadows:
		var centre := board.cell_to_local(cell) + Board.SHADOW_OFFSET
		draw_set_transform(centre, 0.0, Vector2(1.0, Board.SHADOW_SQUASH))
		draw_circle(Vector2.ZERO, float(board.prop_shadows[cell]),
				board.shadow_tone(Board.SHADOW_COLOR.a))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
