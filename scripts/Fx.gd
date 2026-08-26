class_name Fx
extends Node2D

## Pooled, code-drawn particle layer. Every live particle is drawn by a single
## _draw() on one CanvasItem, matching HitFx's aesthetic without a node per
## burst. Battle owns three instances (ground / air / additive glow).
##
## Randomness uses a private RNG, mirroring Sfx: nothing here may ever be read
## back into game state, so gameplay determinism is preserved by construction.

## PIXEL is a rotated quad rather than an axis-aligned rect: a field of
## perfectly square, perfectly aligned dots is the single loudest tell that a
## particle system is code-drawn, and one angle per particle removes it for the
## cost of four cos/sin.
enum Shape { PIXEL, STREAK, RING, SHARD }

## What a landed particle leaves behind: a soaked-in blob (blood, craters)
## or a piece of brass lying where it fell.
enum MarkKind { BLOB, CASING }

# Ground marks are squashed to the tile's 2:1 isometric ratio so they read
# as lying flat on the sand rather than facing the camera.
const GROUND_SQUASH := 0.469

const MAX_PARTICLES := 512
# Ground marks are permanent for the battle. Misses are common enough that
# a long firefight leaves a lot of them, so the cap is generous - they are
# only draw_circle calls in a _draw that reruns while particles are alive.
const MAX_MARKS := 240

# Palette sampled from the actual desert art.
const SAND_MID := Color("e9b569")
const SAND_DARK := Color("d0a36f")
const RUST_LIGHT := Color("8c6a50")
const RUST_MID := Color("774532")
const RUST_DARK := Color("5f3725")
const SPARK_HOT := Color("ffffd0")
const SPARK_COOL := Color("c8481a")   # what a spark fades to before it dies
const EMBER_DEAD := Color("3a1206")
const SPARK_WARM := Color("ffe666")
const SMOKE := Color("cfc3ad")
const SMOKE_WARM := Color("e0d0b0")
# Everyone on this battlefield bleeds red.
const BLOOD := Color("a81f14")
const BLOOD_DARK := Color("6e1109")
const STAIN_COLOR := Color(0.17, 0.10, 0.07, 0.18)
# A strike on the ground: a dark punched core inside a ring of pale ejecta.
const HOLE_CORE := Color(0.12, 0.08, 0.05, 0.66)
# Scuffed subsoil, not pale ejecta - a light rim composites to nothing
# against sand that is already light.
const HOLE_RIM := Color(0.44, 0.33, 0.21, 0.30)
# Rounds clipping scrap chew rust rather than sand.
const HOLE_CORE_RUST := Color(0.16, 0.08, 0.04, 0.66)
const HOLE_RIM_RUST := Color(0.62, 0.38, 0.22, 0.30)
const CASING_BRASS := Color("d8b256")
const CASING_SPENT := Color(0.62, 0.47, 0.20, 0.85)

var _p: Array = []
var _marks: Array = []
var _rng := RandomNumberGenerator.new()

# Ambient wind: a steady trickle of sand motes crossing the board, with an
# occasional stronger gust. Purely atmospheric - kept faint so it never
# competes with the highlights for attention.
var ambient_rect := Rect2()
var ambient_rate := 0.0     # motes per second
var ambient_wind := Vector2.ZERO
var _ambient_accum := 0.0
var _gust_countdown := 0.0


func _ready() -> void:
	_rng.randomize()
	set_process(false)


## Start a steady wind of sand motes drifting across the given world rect.
func set_ambient(rect: Rect2, density: int, wind: Vector2) -> void:
	ambient_rect = rect
	ambient_wind = wind
	# Motes live ~5s, so the rate needed to hold `density` on screen is
	# density / lifetime.
	ambient_rate = float(density) / 5.0
	_gust_countdown = _rng.randf_range(6.0, 13.0)
	if ambient_rate > 0.0:
		set_process(true)


func _spawn_mote(from_edge: bool, speed_scale := 1.0) -> void:
	# Enter from the upwind edge, or seed anywhere on the first fill.
	var pos := Vector2(
			_rng.randf_range(ambient_rect.position.x, ambient_rect.end.x),
			_rng.randf_range(ambient_rect.position.y, ambient_rect.end.y))
	if from_edge:
		pos.x = ambient_rect.end.x if ambient_wind.x < 0.0 else ambient_rect.position.x
	var vel := ambient_wind * speed_scale * _rng.randf_range(0.7, 1.4)
	vel.y += _rng.randf_range(-8, 8)
	_add(pos, vel, _rng.randf_range(3.5, 6.0),
			_rng.randf_range(2, 3), _rng.randf_range(1, 2),
			Color(SAND_MID if _rng.randf() < 0.5 else SAND_DARK,
					_rng.randf_range(0.07, 0.16)),
			Shape.PIXEL, 0.0, 0.05)


## A stronger sweep of sand low across the board.
func gust() -> void:
	for i in 26:
		_spawn_mote(true, _rng.randf_range(2.2, 4.0))


func _update_ambient(delta: float) -> void:
	if ambient_rate <= 0.0:
		return
	_ambient_accum += delta * ambient_rate
	while _ambient_accum >= 1.0:
		_ambient_accum -= 1.0
		_spawn_mote(true)
	_gust_countdown -= delta
	if _gust_countdown <= 0.0:
		_gust_countdown = _rng.randf_range(7.0, 15.0)
		gust()


func _process(delta: float) -> void:
	_update_ambient(delta)
	var live := 0
	for i in _p.size():
		var d: Dictionary = _p[i]
		d.age += delta
		if d.age >= d.life:
			continue
		d.vel += Vector2(0, d.grav) * delta
		d.vel *= 1.0 - minf(d.drag * delta, 1.0)
		d.rot += d.spin * delta
		# Turbulence is a sideways wander whose phase is baked per particle, so
		# a puff of smoke curls instead of every mote in it rising on the same
		# straight line. Costs one sin() and buys most of the life in a plume.
		var drift := Vector2.ZERO
		if d.turb != 0.0:
			drift = Vector2(sin(d.age * 3.1 + d.phase), cos(d.age * 2.3 + d.phase) * 0.4) * d.turb
		d.pos += (d.vel + drift) * delta
		if d.floor_y != 0.0 and d.pos.y >= d.floor_y:
			d.pos.y = d.floor_y
			if d.bounces > 0:
				# Brass tumbles once before it settles.
				d.bounces -= 1
				d.vel = Vector2(d.vel.x * 0.55, -absf(d.vel.y) * 0.36)
			else:
				d.vel = Vector2.ZERO
				if d.mark > 0.0:
					# What lands stays: a splat, or a piece of spent brass.
					if d.mark_kind == MarkKind.CASING:
						_add_casing_mark(d.pos)
					else:
						_add_mark(d.pos, d.mark, Color(d.col, 0.42))
					continue
		_p[live] = d
		live += 1
	_p.resize(live)
	queue_redraw()
	if live == 0 and ambient_rate <= 0.0:
		set_process(false)


func _draw() -> void:
	for m: Dictionary in _marks:
		if m.kind == MarkKind.CASING:
			# Endpoints are squashed directly rather than via a transform,
			# so the case lies on the ground plane at its resting angle.
			var ang: float = m.angle
			var half_len: float = m.size
			var brass: Color = m.col
			var at: Vector2 = m.pos
			var half := Vector2(cos(ang), sin(ang) * GROUND_SQUASH) * half_len
			draw_line(at - half, at + half, brass, 3.0)
			draw_line(at + half * 0.55, at + half,
					Color(brass, brass.a * 0.55), 3.0)
			continue
		draw_set_transform(m.pos, 0.0, Vector2(1.0, GROUND_SQUASH))
		var rim: Color = m.rim
		if rim.a > 0.0:
			draw_circle(Vector2.ZERO, m.rim_size, rim)
		draw_circle(Vector2.ZERO, m.size, m.col)
		for lobe: Dictionary in m.get("lobes", []):
			draw_circle(lobe.off, lobe.r, m.col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for d: Dictionary in _p:
		var k: float = d.age / d.life
		# Colour over life, not just alpha over life. A spark that cools from
		# white through amber to a dead ember reads as burning; the same spark
		# holding one colour and dropping alpha reads as a fading dot.
		var col: Color = d.col if d.col_end.a < 0.0 else d.col.lerp(d.col_end, k)
		col.a *= 1.0 - k * k
		var size: float = lerpf(d.size, d.size_end, k)
		match d.shape:
			Shape.PIXEL:
				_draw_quad(d.pos, size, d.rot, col)
			Shape.SHARD:
				# A splinter: long on its axis of travel, thin across it.
				_draw_quad_wh(d.pos, size * 2.1, size * 0.7, d.rot, col)
			Shape.STREAK:
				# Tapered: bright head, thin tail, so speed reads as direction.
				var tail: Vector2 = d.pos - d.vel * 0.032
				var w: float = maxf(size * 0.5, 1.0)
				draw_line(d.pos, d.pos.lerp(tail, 0.55), col, w)
				draw_line(d.pos.lerp(tail, 0.45), tail,
						Color(col, col.a * 0.45), maxf(w * 0.55, 1.0))
			Shape.RING:
				# Segments scale with radius: a fixed 20 was visibly a polygon
				# once the explosion ring passed about 40px.
				var segs: int = clampi(int(size * 0.9), 16, 64)
				draw_arc(d.pos, size, 0.0, TAU, segs, col,
						maxf(size * 0.18, 1.0), true)
				draw_arc(d.pos, size * 0.82, 0.0, TAU, segs,
						Color(col, col.a * 0.35), maxf(size * 0.09, 1.0), true)


## A square rotated about its centre, as two triangles. Cheaper than setting a
## canvas transform per particle and it keeps everything in one draw list.
func _draw_quad(at: Vector2, size: float, rot: float, col: Color) -> void:
	_draw_quad_wh(at, size, size, rot, col)


func _draw_quad_wh(at: Vector2, w: float, h: float, rot: float, col: Color) -> void:
	var c := cos(rot)
	var s := sin(rot)
	var ex := Vector2(c, s) * (w * 0.5)
	var ey := Vector2(-s, c) * (h * 0.5)
	draw_colored_polygon(PackedVector2Array([
			at - ex - ey, at + ex - ey, at + ex + ey, at - ex + ey]), col)


func _add(pos: Vector2, vel: Vector2, life: float, size: float, size_end: float,
		col: Color, shape: Shape, grav := 0.0, drag := 0.0, floor_y := 0.0,
		mark := 0.0, mark_kind := MarkKind.BLOB, bounces := 0,
		col_end := Color(0, 0, 0, -1.0), spin := 0.0, turb := 0.0) -> void:
	if _p.size() >= MAX_PARTICLES:
		# Drop whatever is closest to dying rather than whatever was added
		# first: pop_front() culled the oldest ENTRY, which during a volley
		# meant the long-lived smoke column vanished to make room for brass.
		var worst := 0
		var worst_k := -1.0
		for i in _p.size():
			var e: Dictionary = _p[i]
			var ek: float = e.age / e.life
			if ek > worst_k:
				worst_k = ek
				worst = i
		_p.remove_at(worst)
	_p.append({
		"pos": pos, "vel": vel, "grav": grav, "drag": drag,
		"age": 0.0, "life": life, "size": size, "size_end": size_end,
		"col": col, "shape": shape, "floor_y": floor_y, "mark": mark,
		"mark_kind": mark_kind, "bounces": bounces,
		"col_end": col_end, "rot": _rng.randf() * TAU, "spin": spin,
		"turb": turb, "phase": _rng.randf() * TAU,
	})
	set_process(true)


func _add_mark(pos: Vector2, size: float, col: Color,
		rim := Color(0, 0, 0, 0), rim_size := 0.0) -> void:
	if _marks.size() >= MAX_MARKS:
		_marks.pop_front()
	# Lobes, baked once. A stain drawn as one circle is a perfect disc, and
	# nothing on a battlefield is a perfect disc - two or three offset bulges
	# cost nothing at draw time and break the silhouette.
	var lobes: Array = []
	for i in _rng.randi_range(2, 3):
		lobes.append({
			"off": Vector2(_rng.randf_range(-size, size),
					_rng.randf_range(-size, size)) * 0.62,
			"r": size * _rng.randf_range(0.45, 0.78),
		})
	_marks.append({
		"pos": pos, "size": size, "col": col,
		"rim": rim, "rim_size": rim_size,
		"kind": MarkKind.BLOB, "angle": 0.0, "lobes": lobes,
	})
	queue_redraw()


## A spent case lying on the sand, at whatever angle it came to rest.
func _add_casing_mark(pos: Vector2) -> void:
	if _marks.size() >= MAX_MARKS:
		_marks.pop_front()
	_marks.append({
		"pos": pos,
		"size": _rng.randf_range(7.0, 9.0),  # half-length; ~14px of brass
		"col": CASING_SPENT if _rng.randf() < 0.5 else CASING_BRASS,
		"rim": Color(0, 0, 0, 0), "rim_size": 0.0,
		"kind": MarkKind.CASING,
		"angle": _rng.randf_range(0.0, PI),
	})
	queue_redraw()


## A round striking the ground: a permanent pockmark with a scatter of grit
## thrown clear of it. `rust` swaps the palette for hits on scrap.
## Sized against the death pool (radius 14), which is the reference for
## "clearly readable on the ground": a strike scar sits well under it but
## still resolves at the board's zoom.
func bullet_hole(pos: Vector2, dir := Vector2.ZERO, rust := false) -> void:
	var r := _rng.randf_range(5.0, 7.0)
	_add_mark(pos, r,
			HOLE_CORE_RUST if rust else HOLE_CORE,
			HOLE_RIM_RUST if rust else HOLE_RIM,
			r * _rng.randf_range(1.8, 2.2))
	# A couple of chips flung out of the crater, opposite the round.
	var away := -dir if dir != Vector2.ZERO else Vector2.UP
	for i in 3:
		_add(pos, _spread(away, deg_to_rad(70), _rng.randf_range(30, 90)),
				0.35, _rng.randf_range(3, 4), 1.0,
				Color(RUST_MID if rust else SAND_DARK, 0.85),
				Shape.PIXEL, 460.0, 1.0)


func _spread(dir: Vector2, spread_rad: float, speed: float) -> Vector2:
	return dir.rotated(_rng.randf_range(-spread_rad, spread_rad)) * speed


## Dust kicked up where a boot lands.
func footstep(pos: Vector2, strength := 1.0) -> void:
	for i in 3:
		_add(pos + Vector2(_rng.randf_range(-6, 6), _rng.randf_range(-2, 2)),
				_spread(Vector2.UP, PI * 0.6, _rng.randf_range(16, 34) * strength),
				0.35, _rng.randf_range(3, 4), 2.0,
				Color(SAND_DARK, 0.55), Shape.PIXEL, 260.0, 1.5, 0.0,
				0.0, MarkKind.BLOB, 0, Color(SAND_MID, 0.30),
				_rng.randf_range(-7, 7))


## Flash and sparks at the muzzle. Smoke is a separate emitter so it can
## live on a non-additive layer and hang around after the flash is gone.
func muzzle(pos: Vector2, dir: Vector2) -> void:
	_add(pos, Vector2.ZERO, 0.12, 4.0, 18.0, Color(SPARK_WARM, 0.9), Shape.RING)
	# A short cone of flame down the barrel line.
	for i in 5:
		_add(pos + dir * float(i) * 3.0,
				_spread(dir, deg_to_rad(14), _rng.randf_range(60, 130)),
				0.09, 7.0 - float(i), 1.0,
				Color(SPARK_HOT, 0.85), Shape.PIXEL, 0.0, 6.0, 0.0,
				0.0, MarkKind.BLOB, 0, Color(SPARK_WARM, 0.6),
				_rng.randf_range(-9, 9))
	for i in 8:
		_add(pos, _spread(dir, deg_to_rad(38), _rng.randf_range(120, 300)),
				_rng.randf_range(0.12, 0.22), 3.0, 1.0,
				SPARK_HOT if i % 2 == 0 else SPARK_WARM, Shape.STREAK, 120.0, 3.0,
				0.0, 0.0, MarkKind.BLOB, 0, Color(SPARK_COOL, 0.5))
	# Embers that arc and die out.
	for i in 4:
		_add(pos, _spread(dir, deg_to_rad(60), _rng.randf_range(40, 110)),
				_rng.randf_range(0.3, 0.55), 2.0, 1.0,
				Color(SPARK_WARM, 0.8), Shape.PIXEL, 300.0, 1.0, 0.0,
				0.0, MarkKind.BLOB, 0, Color(EMBER_DEAD, 0.0),
				_rng.randf_range(-14, 14))


## Gunsmoke rolling off the barrel: a puff punched along the barrel line
## that slows, billows outward and drifts upward, plus a slow wisp that
## keeps curling off the muzzle for a beat after the shot.
func smoke_plume(pos: Vector2, dir: Vector2) -> void:
	for i in 10:
		var falloff := 1.0 - float(i) / 14.0
		_add(pos + dir * _rng.randf_range(0, 10),
				_spread(dir, deg_to_rad(30), _rng.randf_range(30, 110) * falloff)
						+ Vector2(0, -_rng.randf_range(4, 16)),
				_rng.randf_range(0.5, 1.1),
				_rng.randf_range(3, 6), _rng.randf_range(11, 20),
				Color(SMOKE_WARM if i % 3 == 0 else SMOKE,
						_rng.randf_range(0.16, 0.30)),
				Shape.PIXEL, -16.0, 1.7, 0.0, 0.0, MarkKind.BLOB, 0,
				Color(SMOKE.darkened(0.12), 0.22), _rng.randf_range(-2.0, 2.0),
				_rng.randf_range(6, 16))
	# Barrel wisp: slow, small, long-lived.
	for i in 5:
		_add(pos + Vector2(_rng.randf_range(-3, 3), _rng.randf_range(-3, 3)),
				Vector2(_rng.randf_range(-6, 6), -_rng.randf_range(8, 20)),
				_rng.randf_range(0.9, 1.6),
				_rng.randf_range(2, 4), _rng.randf_range(7, 13),
				Color(SMOKE, _rng.randf_range(0.10, 0.20)), Shape.PIXEL, -8.0, 1.2,
				0.0, 0.0, MarkKind.BLOB, 0, Color(SMOKE, 0.15),
				_rng.randf_range(-1.5, 1.5), _rng.randf_range(5, 12))


## Impact burst: a bright ring plus sand kicked off the body.
func impact(pos: Vector2, dir: Vector2, lethal := false) -> void:
	_add(pos, Vector2.ZERO, 0.22, 4.0, 16.0, Color(SPARK_WARM, 0.7), Shape.RING)
	for i in (6 if lethal else 4):
		_add(pos, _spread(dir, deg_to_rad(40), _rng.randf_range(30, 90)),
				0.3, 3.0, 1.0, Color(SAND_MID, 0.6), Shape.SHARD, 380.0, 1.0,
				0.0, 0.0, MarkKind.BLOB, 0, Color(SAND_DARK, 0.0),
				_rng.randf_range(-16, 16))


## Blood bursting out of the wound: a fast mist punched through in the
## round's direction plus a little back-spatter toward the shooter.
## Belongs on the layer drawn above units.
func blood_mist(pos: Vector2, dir: Vector2, lethal := false) -> void:
	for i in (14 if lethal else 8):
		_add(pos, _spread(dir, deg_to_rad(38), _rng.randf_range(90, 260)),
				_rng.randf_range(0.10, 0.20),
				_rng.randf_range(3, 6), 1.0,
				Color(BLOOD if i % 3 else BLOOD_DARK, 0.95), Shape.STREAK, 60.0, 4.0)
	for i in (5 if lethal else 3):
		_add(pos, _spread(-dir, deg_to_rad(55), _rng.randf_range(30, 90)),
				0.22, _rng.randf_range(2, 4), 1.0,
				Color(BLOOD_DARK, 0.85), Shape.PIXEL, 260.0, 2.0)
	if lethal:
		# A heavier cloud hanging at the wound for a beat.
		for i in 6:
			_add(pos + Vector2(_rng.randf_range(-6, 6), _rng.randf_range(-6, 6)),
					_spread(dir, PI, _rng.randf_range(6, 24)),
					0.45, _rng.randf_range(5, 8), 2.0,
					Color(BLOOD_DARK, 0.55), Shape.PIXEL, 40.0, 2.5)


## Droplets that arc away from the wound, fall, and permanently stain the
## sand where they land. Belongs on the ground layer so the splats sit
## under the units.
func blood_spray(pos: Vector2, ground_y: float, dir: Vector2,
		lethal := false) -> void:
	for i in (18 if lethal else 11):
		var speed := _rng.randf_range(70, 210)
		_add(pos, _spread(dir, deg_to_rad(52), speed),
				1.4, _rng.randf_range(2, 4), _rng.randf_range(2, 4),
				Color(BLOOD if i % 2 else BLOOD_DARK, 0.95), Shape.PIXEL,
				620.0, 0.4,
				ground_y + _rng.randf_range(-6, 10),
				_rng.randf_range(5.0, 8.5))


## Rust sparks thrown off the junk pile a round clips on its way through.
func cover_spark(pos: Vector2, dir: Vector2) -> void:
	for i in 7:
		_add(pos, _spread(-dir, deg_to_rad(60), _rng.randf_range(60, 170)),
				0.3, 3.0, 1.0,
				[RUST_LIGHT, RUST_MID, SPARK_WARM][i % 3], Shape.STREAK, 340.0, 1.5,
				0.0, 0.0, MarkKind.BLOB, 0, Color(EMBER_DEAD, 0.3))
	for i in 3:
		_add(pos, _spread(-dir, deg_to_rad(80), _rng.randf_range(30, 80)),
				0.45, 3.0, 2.0, RUST_DARK, Shape.SHARD, 500.0, 0.8, 0.0,
				0.0, MarkKind.BLOB, 0, Color(RUST_DARK, 0.0),
				_rng.randf_range(-20, 20))


## Slow dust cloud when a body hits the ground.
func death_puff(pos: Vector2) -> void:
	for i in 14:
		_add(pos + Vector2(_rng.randf_range(-14, 14), _rng.randf_range(-4, 4)),
				_spread(Vector2.UP, PI * 0.8, _rng.randf_range(10, 40)),
				0.7, _rng.randf_range(5, 7), 3.0,
				Color(SAND_MID if i % 2 == 0 else SAND_DARK, 0.45),
				Shape.PIXEL, 90.0, 1.8, 0.0, 0.0, MarkKind.BLOB, 0,
				Color(SAND_DARK.darkened(0.15), 0.45), _rng.randf_range(-3, 3),
				_rng.randf_range(4, 10))


## Ejected shell casing: flicked clear of the weapon, tumbles once off the
## ground, then stays there for the rest of the battle.
func casing(pos: Vector2, dir: Vector2) -> void:
	var side := dir.orthogonal().normalized()
	_add(pos, side * _rng.randf_range(55, 105) + Vector2(0, -_rng.randf_range(55, 85)),
			3.0, 4.5, 4.5, CASING_BRASS, Shape.PIXEL, 760.0, 0.0,
			pos.y + _rng.randf_range(30, 44),
			1.0, MarkKind.CASING, 1)


## Grenade detonation: a hot flash ring, fragments thrown flat along the
## ground, and a column of dirty smoke that outlives both. Loud enough that
## the blast footprint is obvious without reading the highlights.
func explosion(pos: Vector2) -> void:
	_add(pos, Vector2.ZERO, 0.16, 10.0, 70.0, Color(SPARK_HOT, 0.85), Shape.RING,
			0.0, 0.0, 0.0, 0.0, MarkKind.BLOB, 0, Color(SPARK_COOL, 0.2))
	_add(pos, Vector2.ZERO, 0.30, 6.0, 104.0, Color(SPARK_WARM, 0.40), Shape.RING,
			0.0, 0.0, 0.0, 0.0, MarkKind.BLOB, 0, Color(SPARK_COOL, 0.0))
	# A dust wall running out along the ground. Squashed to the tile's own 2:1
	# so it reads as travelling ACROSS the sand rather than as a sphere hanging
	# over it - the blast had a footprint and this is the shape of it.
	for i in 20:
		var ang := TAU * float(i) / 20.0
		var out := Vector2(cos(ang), sin(ang) * GROUND_SQUASH)
		_add(pos + out * 6.0, out * _rng.randf_range(190, 300),
				_rng.randf_range(0.35, 0.6), _rng.randf_range(5, 9),
				_rng.randf_range(13, 20),
				Color(SAND_MID, _rng.randf_range(0.35, 0.6)), Shape.PIXEL,
				0.0, 3.6, 0.0, 0.0, MarkKind.BLOB, 0,
				Color(SAND_DARK, 0.45), _rng.randf_range(-6, 6), 0.0)
	for i in 22:  # fragments, thrown low and fast in every direction
		_add(pos, _spread(Vector2.RIGHT.rotated(TAU * i / 22.0), deg_to_rad(20),
						_rng.randf_range(150, 420)),
				_rng.randf_range(0.20, 0.42), _rng.randf_range(3, 6), 1.0,
				Color(SPARK_WARM if i % 3 else SAND_MID, 0.9), Shape.STREAK,
				520.0, 2.4, pos.y + _rng.randf_range(6, 20), 0.0,
				MarkKind.BLOB, 0, Color(SPARK_COOL, 0.25))
	for i in 16:  # dirt kicked up off the crater
		_add(pos + Vector2(_rng.randf_range(-18, 18), _rng.randf_range(-6, 6)),
				_spread(Vector2.UP, PI * 0.55, _rng.randf_range(70, 200)),
				_rng.randf_range(0.45, 0.85), _rng.randf_range(5, 9), 2.0,
				Color(SAND_DARK if i % 2 else RUST_MID, 0.7), Shape.SHARD, 340.0, 1.6,
				0.0, 0.0, MarkKind.BLOB, 0, Color(RUST_DARK, 0.0),
				_rng.randf_range(-18, 18))
	for i in 14:  # smoke column, rising and spreading as it goes
		_add(pos + Vector2(_rng.randf_range(-16, 16), _rng.randf_range(-8, 8)),
				_spread(Vector2.UP, PI * 0.4, _rng.randf_range(20, 60)),
				_rng.randf_range(0.9, 1.7), _rng.randf_range(8, 14),
				_rng.randf_range(22, 34),
				Color(SMOKE.darkened(0.55), _rng.randf_range(0.30, 0.5)),
				Shape.PIXEL, -14.0, 1.1, 0.0, 0.0, MarkKind.BLOB, 0,
				Color(SMOKE.darkened(0.15), 0.38), _rng.randf_range(-2, 2),
				_rng.randf_range(10, 22))


## Scorch left on the sand where a grenade went off. Permanent, like the
## bullet holes and casings.
func scorch(pos: Vector2) -> void:
	_add_mark(pos, 17.0, Color(0.10, 0.07, 0.05, 0.42),
			Color(0.28, 0.18, 0.10, 0.24), 30.0)
	for i in 7:
		_add_mark(pos + Vector2(_rng.randf_range(-26, 26), _rng.randf_range(-12, 12)),
				_rng.randf_range(4, 9), Color(0.13, 0.09, 0.06, 0.30))


## One drifting puff of a standing smoke cloud. Battle calls this repeatedly
## over live smoke cells so the screened ground keeps moving instead of
## sitting there as a flat tint.
func smoke_drift(pos: Vector2) -> void:
	_add(pos + Vector2(_rng.randf_range(-30, 30), _rng.randf_range(-12, 12)),
			Vector2(_rng.randf_range(-14, 14), -_rng.randf_range(4, 16)),
			_rng.randf_range(1.1, 2.0),
			_rng.randf_range(14, 22), _rng.randf_range(30, 46),
			Color(SMOKE_WARM, _rng.randf_range(0.13, 0.24)), Shape.PIXEL, -5.0, 0.9,
			0.0, 0.0, MarkKind.BLOB, 0, Color(SMOKE, 0.14),
			_rng.randf_range(-1.2, 1.2), _rng.randf_range(5, 14))


## Permanent pool left where a unit fell.
func stain(pos: Vector2) -> void:
	_add_mark(pos, 14.0, STAIN_COLOR)
	for i in 5:
		_add_mark(pos + Vector2(_rng.randf_range(-16, 16), _rng.randf_range(-7, 7)),
				_rng.randf_range(4, 8), Color(BLOOD_DARK, 0.38))
