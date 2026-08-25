class_name ApronScenery

## Dresses the ground outside the arena, so the apron reads as country the
## fight is happening in rather than an empty margin around it.
##
## Three passes, in rank order. AUTHORED pieces come from the level's optional
## "apron_props" list - the garrison's perimeter towers are these - and own
## their ground outright. FORMATIONS are hash-seeded heaps of three to five
## overlapping rocks: massed silhouettes that give the flats some relief where
## a lone boulder would just repeat the board's own scatter. SCATTER is the
## per-floor drift of rocks, scrub, junk and flat detritus, thinnest on salt
## and never on the first ring, so the arena keeps a step of breathing room.
##
## Everything spawned here is scenery in the strictest sense: no cover, no
## LOS, no collision, nothing gameplay may read. Standing pieces go in the
## caller's y-sorted entities layer with the apron's own dissolve baked into
## their modulate (Board.apron_fade_at, the GDScript twin of the apron
## shader); flat detritus goes INTO the apron CanvasGroup, where the shader
## fades it with the ground it lies on. Contact shadows ride the group too,
## via Board.set_apron_shadows, so nothing out there reads as pasted on.
##
## Battle, Camp and the preview tool all call spawn() with their own entities
## node; a board whose apron is disabled (an interior room) no-ops on the
## empty apron_cache.

const ENV := "res://assets/sprites/Environment/Desert"
const FIXTURE_ROOT := ENV + "/garrison_fixtures/"

## Standing kinds: numbered art runs plus each kind's ground anchor and
## contact shadow, matching Battle's tables for the same art.
const KINDS := {
	"rock": {"dir": ENV + "/Desert_Rock_or_bolder", "base": "Rock", "count": 8,
			"style": "n1", "offset": Vector2(0, -18), "shadow": 22.0},
	"plant": {"dir": ENV + "/desert_plants", "base": "Desert_Plants", "count": 16,
			"offset": Vector2(0, -17), "shadow": 12.0},
	"junk": {"dir": ENV + "/desert_rusted_garbage", "base": "Rusted_desert_garbage",
			"count": 7, "offset": Vector2(0, -20), "shadow": 20.0},
	"watchtower": {"dir": FIXTURE_ROOT, "base": "Garrison_watchtower", "count": 1,
			"offset": Vector2(0, -73), "shadow": 16.0},
}
const DETRITUS := {"dir": ENV + "/desert_detritus", "base": "Desert_detritus",
		"count": 8}

## What drifts across each ground, and at what rate. Every entry gates its own
## hash stream through its own decorrelation primes (see Board.decorrelate for
## why same-cell streams must be remapped, not just re-salted). The mixes are
## the boards' own idiom continued: desert is the busiest ground, salt is a
## powder pan where anything standing is an event, ash keeps the burnt junk
## and loses the growth, and the compound's surroundings are a worked yard's -
## litter, not wilderness.
const SCATTER := {
	"desert": [
		{"kind": "rock", "rate": 0.030, "a": 3, "b": 5},
		{"kind": "plant", "rate": 0.030, "a": 7, "b": 11},
		{"kind": "junk", "rate": 0.008, "a": 13, "b": 17},
		{"kind": "detritus", "rate": 0.035, "a": 19, "b": 23},
	],
	"salt": [
		{"kind": "rock", "rate": 0.012, "a": 3, "b": 5},
		{"kind": "detritus", "rate": 0.020, "a": 19, "b": 23},
	],
	"ash": [
		{"kind": "rock", "rate": 0.022, "a": 3, "b": 5},
		{"kind": "junk", "rate": 0.015, "a": 13, "b": 17},
		{"kind": "detritus", "rate": 0.030, "a": 19, "b": 23},
	],
	"compound": [
		{"kind": "junk", "rate": 0.015, "a": 13, "b": 17},
		{"kind": "rock", "rate": 0.010, "a": 3, "b": 5},
		{"kind": "detritus", "rate": 0.030, "a": 19, "b": 23},
	],
}

## Hash salts. Battle claims 4..15 on the same prop_seed; starting at 31
## keeps every apron stream clear of every board stream.
const SALT_PICK := 31
const SALT_FLIP := 32
const SALT_JITTER := 33
const SALT_FORMATION := 34
const SALT_FORM_SIZE := 35
const SALT_GATE := 36

## Scatter stays off the first ring (breathing room - a rock against the
## boundary reads as cover) and off ground the fade has all but dissolved.
const SCATTER_RING_MIN := 2
const FADE_SKIP := 0.88
## Standing scatter keeps a cell of air between pieces; detritus may lie
## closer. Formations keep well apart from each other.
const SCATTER_GAP := 1
const FORMATION_RATE := 0.012
const FORMATION_GAP := 7
const FORMATION_RING_MIN := 4
const FORMATION_RING_MAX := 10
## What a formation is made of, as 0-based picks into the rock run: a tall
## HEART first - the arch, the crag cluster or the hoodoo spire, the shapes
## that read as standing ground rather than a dropped stone - then low
## fillers heaped against it. This is the relief the flats get: not painted
## height, but massed silhouettes the eye reads as rising ground.
const FORMATION_HEARTS: Array[int] = [2, 4, 6]
const FORMATION_FILLERS: Array[int] = [0, 3, 4]


static func spawn(board: Board, entities: Node2D, data: Dictionary,
		prop_seed: int) -> void:
	if board.apron_cache.is_empty():
		return
	var floor_name := str(data.get("floor", Board.DEFAULT_FLOOR))
	var shadows: Array = []
	# Ground nothing may spawn on: the road and its shoulders, so the lane
	# out of the world stays a lane.
	var blocked := {}
	for cell: Vector2i in board.apron_roads:
		_block_around(blocked, cell)
	# And the extraction pickup's parking spot plus its whole drive-in lane -
	# the transport must not arrive through a boulder somebody scattered.
	if data.has("extract_pickup"):
		var pickup: Dictionary = data.extract_pickup
		var pk_anchor: Vector2i = pickup.anchor
		var pk_drive: Vector2i = pickup.get("drive", Vector2i(-8, 0))
		var pk_step := Vector2i(signi(pk_drive.x), signi(pk_drive.y))
		for i in maxi(absi(pk_drive.x), absi(pk_drive.y)) + 1:
			var base := pk_anchor + pk_step * i
			for dy in range(-1, 3):
				for dx in range(-1, 3):
					blocked[base + Vector2i(dx, dy)] = true

	# 1. Authored pieces: single cells, or straight runs - a barrier the
	# level is ABOUT continues across the apron this way, so the map edge
	# never reads as the easy way around it.
	for spec: Dictionary in data.get("apron_props", []):
		for cell: Vector2i in _spec_cells(spec):
			if board.in_bounds(cell):
				push_warning("[ApronScenery] apron prop %s at %s is on the board"
						% [spec.kind, cell])
				continue
			_stand(board, entities, str(spec.kind), cell, Vector2.ZERO,
					prop_seed, shadows)
			_block_around(blocked, cell)

	# 2. Rock formations.
	for cell: Vector2i in board.apron_cache:
		var ring := _ring(board, cell)
		if ring < FORMATION_RING_MIN or ring > FORMATION_RING_MAX:
			continue
		if blocked.has(cell):
			continue
		if Board._hash01(cell, prop_seed + SALT_FORMATION) >= FORMATION_RATE:
			continue
		var clear := true
		for dy in range(-FORMATION_GAP, FORMATION_GAP + 1):
			if not clear:
				break
			for dx in range(-FORMATION_GAP, FORMATION_GAP + 1):
				if blocked.has(cell + Vector2i(dx, dy)):
					clear = false
					break
		if not clear:
			continue
		var count := 3 + mini(int(Board._hash01(
				Board.decorrelate(cell, 3, 5), prop_seed + SALT_FORM_SIZE) * 3), 2)
		for k in count:
			# Each stone in the heap draws its jitter off its own remapped
			# cell, so the heap's shape never echoes its variant picks. The
			# heart stays near the anchor; the fillers heap around it.
			var jc := Board.decorrelate(cell + Vector2i(k * 7, k * 11), 7, 11)
			var jitter := Vector2(
					roundf((Board._hash01(jc, prop_seed + SALT_JITTER) - 0.5) * 152.0),
					roundf((Board._hash01(jc, prop_seed + SALT_JITTER + 1) - 0.5) * 68.0))
			var pool := FORMATION_FILLERS if k > 0 else FORMATION_HEARTS
			var variant: int = pool[mini(int(Board._hash01(jc,
					prop_seed + SALT_PICK) * pool.size()), pool.size() - 1)]
			if k == 0:
				jitter *= 0.4
			_stand(board, entities, "rock", cell, jitter, prop_seed + k,
					shadows, variant)
		_block_around(blocked, cell, 2)

	# 3. Scatter.
	var recipes: Array = SCATTER.get(floor_name, SCATTER[Board.DEFAULT_FLOOR])
	var stood: Array[Vector2i] = []
	var lain: Array[Vector2i] = []
	for cell: Vector2i in board.apron_cache:
		var ring := _ring(board, cell)
		if ring < SCATTER_RING_MIN or blocked.has(cell):
			continue
		if board.apron_fade_at(cell) >= FADE_SKIP:
			continue
		for recipe: Dictionary in recipes:
			var gate := Board._hash01(
					Board.decorrelate(cell, recipe.a, recipe.b),
					prop_seed + SALT_GATE)
			if gate >= float(recipe.rate):
				continue
			var flat: bool = recipe.kind == "detritus"
			var others := lain if flat else stood
			var clear := true
			for other: Vector2i in others:
				if maxi(absi(other.x - cell.x), absi(other.y - cell.y)) \
						<= SCATTER_GAP:
					clear = false
					break
			if clear:
				if flat:
					_lay(board, cell, prop_seed)
					lain.append(cell)
				else:
					_stand(board, entities, str(recipe.kind), cell,
							Vector2.ZERO, prop_seed, shadows)
					stood.append(cell)
			break  # one drift per cell, first gate wins
	board.set_apron_shadows(shadows)


## A standing piece: hash-picked variant, the apron dissolve in its modulate,
## its contact shadow queued for the apron layer. Skips ground the fade has
## already taken.
static func _stand(board: Board, entities: Node2D, kind: String,
		cell: Vector2i, jitter: Vector2, prop_seed: int, shadows: Array,
		variant := -1) -> void:
	if not KINDS.has(kind):
		push_warning("[ApronScenery] unknown apron prop kind '%s'" % kind)
		return
	var fade := board.apron_fade_at(cell)
	if fade >= FADE_SKIP:
		return
	var spec: Dictionary = KINDS[kind]
	var path := _variant(spec, cell, prop_seed, variant)
	if not ResourceLoader.exists(path):
		push_warning("[ApronScenery] missing art: %s" % path)
		return
	var sprite := Sprite2D.new()
	sprite.texture = load(path)
	sprite.offset = spec.offset
	sprite.scale = Vector2(2, 2)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = board.cell_to_global(cell) + jitter
	sprite.modulate = Color(Board.APRON_SHADE, Board.APRON_SHADE,
			Board.APRON_SHADE, 1.0 - fade)
	# The dissolve IS this sprite's alpha, so the occlusion fader must never
	# adopt it: Battle._collect_occluders skips anything carrying this tag.
	sprite.set_meta("apron_scenery", true)
	entities.add_child(sprite)
	shadows.append({
		"pos": board.cell_to_local(cell) + jitter + Board.SHADOW_OFFSET,
		"radius": float(spec.shadow),
	})


## Flat detritus, laid INSIDE the apron group so the shader fades it with the
## ground. 1x like the board's own decals, jittered off its cell centre.
static func _lay(board: Board, cell: Vector2i, prop_seed: int) -> void:
	if board.apron_group == null:
		return
	var path := _variant(DETRITUS, cell, prop_seed)
	if not ResourceLoader.exists(path):
		return
	var decal := Sprite2D.new()
	decal.texture = load(path)
	decal.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var jc := Board.decorrelate(cell, 5, 7)
	decal.position = board.cell_to_local(cell) + Vector2(
			roundf((Board._hash01(jc, prop_seed + SALT_JITTER) - 0.5) * 22.0),
			roundf((Board._hash01(jc, prop_seed + SALT_JITTER + 1) - 0.5) * 11.0))
	decal.flip_h = Board._hash01(cell, prop_seed + SALT_FLIP) < 0.5
	decal.modulate = Color(Board.APRON_SHADE, Board.APRON_SHADE, Board.APRON_SHADE)
	board.apron_group.add_child(decal)


## The art file for a cell's hash pick (or a caller-forced pick, 0-based).
## Two naming runs ship: rocks count Rock_1..Rock_8 ("n1"), everything else
## counts Base, Base_1, Base_2...
static func _variant(spec: Dictionary, cell: Vector2i, prop_seed: int,
		override := -1) -> String:
	var count := int(spec.count)
	var pick := override if override >= 0 else mini(
			int(Board._hash01(cell, prop_seed + SALT_PICK) * count), count - 1)
	var file: String
	if str(spec.get("style", "")) == "n1":
		file = "%s_%d.png" % [spec.base, pick + 1]
	else:
		file = str(spec.base) + (".png" if pick == 0 else "_%d.png" % pick)
	return str(spec.dir).path_join(file)


## The cells an authored spec names: a single "cell", or the inclusive
## straight run "from" -> "to". Runs must be axis-aligned or a true 45-degree
## diagonal - the step is one cell per axis with a sign, nothing cleverer.
static func _spec_cells(spec: Dictionary) -> Array[Vector2i]:
	if spec.has("cell"):
		var single: Array[Vector2i] = [spec.cell]
		return single
	var from: Vector2i = spec.from
	var to: Vector2i = spec.to
	var step := Vector2i(signi(to.x - from.x), signi(to.y - from.y))
	var cells: Array[Vector2i] = []
	for i in maxi(absi(to.x - from.x), absi(to.y - from.y)) + 1:
		cells.append(from + step * i)
	return cells


static func _ring(board: Board, cell: Vector2i) -> int:
	return maxi(maxi(-cell.x, cell.x - board.size.x + 1),
			maxi(-cell.y, cell.y - board.size.y + 1))


static func _block_around(blocked: Dictionary, cell: Vector2i, reach := 1) -> void:
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			blocked[cell + Vector2i(dx, dy)] = true
