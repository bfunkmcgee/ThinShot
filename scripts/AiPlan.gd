class_name AiPlan
## How the Thirst reads the board: the scoring half of the enemy turn.
##
## The enemy turn is two kinds of code. The coroutines that walk goblins and
## await animations belong to Battle, which owns the tree they animate in. The
## judgement - which cell is worth standing on, who is nearest, which way to
## watch - is arithmetic over a Board and the units in play, and it lives here
## so tools/test_aiplan.gd can pin it on geometry built for the purpose, the
## way Rules and Bounty are already tested.
##
## Occupancy stays out, deliberately. Who is standing where, which arcs are
## live, which cells are free to stop on - that is the controller's knowledge
## of the fight, so Battle hands in candidate destinations and watch sets and
## this file decides what they are worth. Nothing here reaches for a scene
## tree, an autoload, or Battle itself.
##
## LAYERING. This file may name Board, Unit and Rules. Nothing those three
## name may name this file back - the enemy's read of the rules sits above
## the rules, never inside them.

## What a candidate destination pays for walking into a live overwatch arc,
## per watcher whose cone the path would cross. Sized to lose to having a shot
## at all (-1000) but to dominate distance ties and cover terms - so a goblin
## routes around a covered lane when a clean way exists, and still crosses
## when crossing is the only way to fight.
const WATCHED_LANE := 120


## The targets a unit could engage from `from_cell`: inside its reach, and
## either seen clean or reachable with a lean - can_engage folds peeking in.
static func shootable_from(board: Board, from_cell: Vector2i, attack_range: int,
		targets: Array[Unit]) -> Array[Unit]:
	var result: Array[Unit] = []
	for unit in targets:
		if Board.manhattan(from_cell, unit.cell) <= attack_range \
				and board.can_engage(from_cell, unit.cell):
			result.append(unit)
	return result


static func nearest(from_cell: Vector2i, candidates: Array[Unit]) -> Unit:
	var best: Unit = candidates[0]
	for unit in candidates:
		if Board.manhattan(from_cell, unit.cell) < Board.manhattan(from_cell, best.cell):
			best = unit
	return best


## How exposed a cell is to scout fire: 2 per clean firing line, 1 per line
## that has to cross junk (those shots only land for half damage). This is
## what makes the goblins actually value the cover on the map.
##
## The goblin is the TARGET of every shot counted here, so the facing that
## decides its cover is its own - the one it would be holding on arrival,
## which is why best_dest works `end_sector` out before it asks. A cell with a
## wall behind the goblin's back is not cover; both sides of that judgement go
## through Rules.cover_at, the same function the resolver applies.
static func exposure_at(board: Board, cell: Vector2i, facing_sector: int,
		arc_half: int, scouts: Array[Unit]) -> int:
	var score := 0
	for scout in scouts:
		if Board.manhattan(cell, scout.cell) <= scout.attack_range \
				and board.can_engage(scout.cell, cell):
			match Rules.cover_at(board, cell, facing_sector, arc_half, scout.cell):
				Board.CoverLevel.FULL:
					score += 0
				Board.CoverLevel.HALF:
					score += 1
				_:
					score += 2
	return score


## Best move destination for an AI unit. A cell it can shoot a scout from
## beats every cell it can't; exposure to scout fire costs a little when
## healthy and a lot when wounded (so 1 HP goblins with no shot retreat to
## cover); nearer the chase target breaks remaining ties.
##
## `reach` is the flood_fill result (cell -> predecessor), which also tells us
## which way the goblin would be facing when it arrives - and which cells its
## walk would actually cross, which is what the watch penalty is charged on.
## `candidates` are the destinations the controller says are free to stop on
## (plus the goblin's own cell); `watch_sets` are the live hostile arcs, one
## cell-set per watcher.
static func best_dest(board: Board, goblin: Unit, reach: Dictionary,
		candidates: Array, scouts: Array[Unit], chase_cell: Vector2i,
		watch_sets: Array[Dictionary]) -> Vector2i:
	var exposure_weight := 25 if goblin.hp <= 2 else 2
	var best := Vector2i(-1, -1)
	var best_score := 999999
	for cell: Vector2i in candidates:
		# Which way the goblin would be looking once it got here, worked out
		# before anything is scored because its own facing decides the cover it
		# would have (see exposure_at). A goblin with a shot turns to take it;
		# one without walks in facing the way it came. Neither is on the unit
		# yet, which is what Rules.cover_at exists to be asked about.
		var shots := shootable_from(board, cell, goblin.attack_range, scouts)
		var mark: Unit = null
		var end_sector := -1
		if not shots.is_empty():
			mark = nearest(cell, shots)
			end_sector = Board.sector_from_to(cell, mark.cell)
		elif reach.has(cell):
			end_sector = Board.sector_from_to(reach[cell], cell)
		# Standing still with no shot ends the turn on overwatch, which picks its
		# own sector later; the facing we can honestly predict there is the one
		# the goblin already has.
		var end_facing := end_sector if end_sector >= 0 else goblin.facing_sector
		var score := Board.manhattan(cell, chase_cell)
		score += exposure_weight * exposure_at(board, cell, end_facing,
				goblin.arc_half, scouts)
		# A reaction is drawn on the first watched cell entered, so the honest
		# cost is per watcher engaged along the walk, not per tile inside the
		# cone. Standing still triggers nothing and costs nothing.
		if not watch_sets.is_empty() and cell != goblin.cell:
			var walk := board.reconstruct_path(reach, cell)
			for watched: Dictionary in watch_sets:
				for step: Vector2i in walk:
					if watched.has(step):
						score += WATCHED_LANE
						break
		if mark != null:
			score -= 1000
			# A clean firing position beats one where the target is dug in. The
			# target is a live scout standing where it stands, so the facing that
			# decides ITS cover is its real one, read off the unit - the opposite
			# perspective to the exposure term above, and the reason both are
			# asked through the same function rather than through cover_between.
			if Rules.cover_at(board, mark.cell, mark.facing_sector, mark.arc_half,
					cell) != Board.CoverLevel.NONE:
				score += 400
			# Shooting someone in the back bypasses their cover.
			if not mark.covers_sector(Board.sector_from_to(mark.cell, cell)):
				score -= 60
		# Do not turn your back on the rest of the squad.
		if end_sector >= 0:
			for scout in scouts:
				if Board.manhattan(cell, scout.cell) <= scout.attack_range \
						and board.has_line_of_sight(scout.cell, cell) \
						and absi(wrapi(Board.sector_from_to(cell, scout.cell)
								- end_sector + 4, 0, 8) - 4) > goblin.arc_half:
					score += 6
		if score < best_score:
			best_score = score
			best = cell
	return best


## Which way a dug-in goblin should watch: the arc covering the most cells of
## `approach` - every cell the scouts could advance through, computed by the
## controller because reachability depends on who is standing where. Integer
## scoring keeps ties deterministic.
static func best_watch_sector(board: Board, goblin: Unit, approach: Dictionary) -> int:
	var best_sector := goblin.facing_sector
	var best_count := -1
	for sector in 8:
		var count := 0
		for cell: Vector2i in Rules.overwatch_cells(board, goblin, sector):
			if approach.has(cell):
				count += 1
		if count > best_count:
			best_count = count
			best_sector = sector
	return best_sector
