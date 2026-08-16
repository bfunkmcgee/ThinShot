extends SceneTree

## Exercises the spatial rules against every shipped level, using the real
## Board code rather than a re-implementation of it.
##
## Answers two questions the cover model turns on:
##   1. Does any real shooter/target pair ever actually receive map-edge cover?
##      cover_level_of() returns FULL off-map ("something to put your back to"),
##      but cover is looked up by sector, and a shooter cannot stand off-map.
##   2. Does peek_origin ever return a lean whose line crosses a full blocker?
##      It must not: leaning past one piece of cover does not see through the
##      next one along.
##
## Run: godot --headless --path . -s tools/check_cover_rules.gd

func _init() -> void:
	var board: Board = Board.new()
	var failed := false
	var total_edge_cover := 0
	var total_illegal := 0
	var total_peeks := 0

	for idx in Levels.LEVELS.size():
		var data: Dictionary = Levels.LEVELS[idx]
		board.set_level(data)
		var size: Vector2i = board.size
		var cells: Array[Vector2i] = []
		for y in size.y:
			for x in size.x:
				var c := Vector2i(x, y)
				if board.is_walkable(c):
					cells.append(c)

		# --- 1. edge cover ---------------------------------------------------
		# Count pairs where the cover the target receives comes from an
		# off-map neighbour, i.e. cover that exists only because of the
		# out-of-bounds FULL. Anything > 0 means the rule is real and
		# cover_level_of must keep returning FULL off-map.
		var edge_cover := 0
		var perimeter_claiming := 0
		for target in cells:
			var on_edge := target.x == 0 or target.y == 0 \
					or target.x == size.x - 1 or target.y == size.y - 1
			if not on_edge:
				continue
			# does this perimeter cell advertise cover it could never receive?
			if not board.cover_map_at(target).is_empty():
				perimeter_claiming += 1
			for from in cells:
				if from == target:
					continue
				if board.cover_between(from, target) == Board.CoverLevel.NONE:
					continue
				var src := board.cover_source(from, target)
				if not board.in_bounds(src):
					edge_cover += 1

		# --- 2. peek legality ------------------------------------------------
		# Every lean peek_origin returns must have a clean line to the target
		# once the single hugged piece is discounted. We cannot see which piece
		# was hugged from outside, so assert the weaker but sufficient property:
		# the leaned line may cross at most the one blocker adjacent to BOTH
		# the shooter and the line.
		var illegal := 0
		var peeks := 0
		for from in cells:
			for to in cells:
				if from == to:
					continue
				if board.has_line_of_sight(from, to):
					continue
				var side := board.peek_origin(from, to)
				if side == Board.NO_CELL:
					continue
				peeks += 1
				# Which single neighbour of `from` could legitimately be the
				# piece being leaned past? Try each; the peek is legal if any
				# one of them alone clears the line.
				var ok := false
				for dir in Board.DIRS:
					var cover_cell: Vector2i = from + dir
					if not board.in_bounds(cover_cell):
						continue
					if board.cover_level_of(cover_cell) != Board.CoverLevel.FULL:
						continue
					if board._los_ignoring(side, to, {cover_cell: true}):
						ok = true
						break
				if not ok:
					illegal += 1

		total_edge_cover += edge_cover
		total_illegal += illegal
		total_peeks += peeks
		print("level %d '%s' (%dx%d, %d walkable)" % [
				idx, data.name, size.x, size.y, cells.size()])
		print("    edge-cover pairs: %d   perimeter cells advertising cover: %d"
				% [edge_cover, perimeter_claiming])
		print("    peeks: %d   illegal (line crosses a second blocker): %d"
				% [peeks, illegal])
		if illegal > 0:
			failed = true

	print("")
	print("TOTAL peeks %d, illegal %d, edge-cover pairs %d"
			% [total_peeks, total_illegal, total_edge_cover])
	if total_edge_cover == 0:
		print("NOTE: no shot on any shipped map receives map-edge cover.")
	board.free()
	print("RESULT: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
