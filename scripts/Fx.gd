class_name Fx
extends Node2D

## Pooled, code-drawn particle layer. Every live particle is drawn by a single
## _draw() on one CanvasItem, matching HitFx's aesthetic without a node per
## burst. Battle owns three instances (ground / air / additive glow).
##
## Randomness uses a private RNG, mirroring Sfx: nothing here may ever be read
## back into game state, so gameplay determinism is preserved by construction.

enum Shape { PIXEL, STREAK, RING }

const MAX_PARTICLES := 256
const MAX_MARKS := 80

# Palette sampled from the actual desert art.
const SAND_MID := Color("e9b569")
const SAND_DARK := Color("d0a36f")
const RUST_LIGHT := Color("8c6a50")
const RUST_MID := Color("774532")
const RUST_DARK := Color("5f3725")
const SPARK_HOT := Color("ffffd0")
const SPARK_WARM := Color("ffe666")
const SMOKE := Color("cfc3ad")
const SMOKE_WARM := Color("e0d0b0")
# Everyone on this battlefield bleeds red.
const BLOOD := Color("a81f14")
const BLOOD_DARK := Color("6e1109")
const STAIN_COLOR := Color(0.17, 0.10, 0.07, 0.18)

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
		d.pos += d.vel * delta
		if d.floor_y != 0.0 and d.pos.y >= d.floor_y:
			d.pos.y = d.floor_y
			d.vel = Vector2.ZERO
			if d.mark > 0.0:
				# A droplet that lands becomes a permanent splat.
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
		draw_set_transform(m.pos, 0.0, Vector2(1.0, 0.469))
		draw_circle(Vector2.ZERO, m.size, m.col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for d: Dictionary in _p:
		var k: float = d.age / d.life
		var col: Color = d.col
		col.a *= 1.0 - k * k
		var size: float = lerpf(d.size, d.size_end, k)
		match d.shape:
			Shape.PIXEL:
				draw_rect(Rect2(d.pos - Vector2(size, size) * 0.5,
						Vector2(size, size)), col)
			Shape.STREAK:
				draw_line(d.pos, d.pos - d.vel * 0.03, col, maxf(size * 0.5, 1.0))
			Shape.RING:
				draw_arc(d.pos, size, 0.0, TAU, 20, col, maxf(size * 0.18, 1.0), true)


func _add(pos: Vector2, vel: Vector2, life: float, size: float, size_end: float,
		col: Color, shape: Shape, grav := 0.0, drag := 0.0, floor_y := 0.0,
		mark := 0.0) -> void:
	if _p.size() >= MAX_PARTICLES:
		_p.pop_front()
	_p.append({
		"pos": pos, "vel": vel, "grav": grav, "drag": drag,
		"age": 0.0, "life": life, "size": size, "size_end": size_end,
		"col": col, "shape": shape, "floor_y": floor_y, "mark": mark,
	})
	set_process(true)


func _add_mark(pos: Vector2, size: float, col: Color) -> void:
	if _marks.size() >= MAX_MARKS:
		_marks.pop_front()
	_marks.append({"pos": pos, "size": size, "col": col})
	queue_redraw()


func _spread(dir: Vector2, spread_rad: float, speed: float) -> Vector2:
	return dir.rotated(_rng.randf_range(-spread_rad, spread_rad)) * speed


## Dust kicked up where a boot lands.
func footstep(pos: Vector2, strength := 1.0) -> void:
	for i in 3:
		_add(pos + Vector2(_rng.randf_range(-6, 6), _rng.randf_range(-2, 2)),
				_spread(Vector2.UP, PI * 0.6, _rng.randf_range(16, 34) * strength),
				0.35, _rng.randf_range(3, 4), 2.0,
				Color(SAND_DARK, 0.55), Shape.PIXEL, 260.0, 1.5)


## Flash and sparks at the muzzle. Smoke is a separate emitter so it can
## live on a non-additive layer and hang around after the flash is gone.
func muzzle(pos: Vector2, dir: Vector2) -> void:
	_add(pos, Vector2.ZERO, 0.12, 4.0, 18.0, Color(SPARK_WARM, 0.9), Shape.RING)
	# A short cone of flame down the barrel line.
	for i in 5:
		_add(pos + dir * float(i) * 3.0,
				_spread(dir, deg_to_rad(14), _rng.randf_range(60, 130)),
				0.09, 7.0 - float(i), 1.0,
				Color(SPARK_HOT, 0.85), Shape.PIXEL, 0.0, 6.0)
	for i in 8:
		_add(pos, _spread(dir, deg_to_rad(38), _rng.randf_range(120, 300)),
				_rng.randf_range(0.12, 0.22), 3.0, 1.0,
				SPARK_HOT if i % 2 == 0 else SPARK_WARM, Shape.STREAK, 120.0, 3.0)
	# Embers that arc and die out.
	for i in 4:
		_add(pos, _spread(dir, deg_to_rad(60), _rng.randf_range(40, 110)),
				_rng.randf_range(0.3, 0.55), 2.0, 1.0,
				Color(SPARK_WARM, 0.8), Shape.PIXEL, 300.0, 1.0)


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
				Shape.PIXEL, -16.0, 1.7)
	# Barrel wisp: slow, small, long-lived.
	for i in 5:
		_add(pos + Vector2(_rng.randf_range(-3, 3), _rng.randf_range(-3, 3)),
				Vector2(_rng.randf_range(-6, 6), -_rng.randf_range(8, 20)),
				_rng.randf_range(0.9, 1.6),
				_rng.randf_range(2, 4), _rng.randf_range(7, 13),
				Color(SMOKE, _rng.randf_range(0.10, 0.20)), Shape.PIXEL, -8.0, 1.2)


## Impact burst: a bright ring plus sand kicked off the body.
func impact(pos: Vector2, dir: Vector2, lethal := false) -> void:
	_add(pos, Vector2.ZERO, 0.22, 4.0, 16.0, Color(SPARK_WARM, 0.7), Shape.RING)
	for i in (6 if lethal else 4):
		_add(pos, _spread(dir, deg_to_rad(40), _rng.randf_range(30, 90)),
				0.3, 3.0, 1.0, Color(SAND_MID, 0.6), Shape.PIXEL, 380.0, 1.0)


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
				_rng.randf_range(2.5, 5.0))


## Rust sparks thrown off the junk pile a round clips on its way through.
func cover_spark(pos: Vector2, dir: Vector2) -> void:
	for i in 7:
		_add(pos, _spread(-dir, deg_to_rad(60), _rng.randf_range(60, 170)),
				0.3, 3.0, 1.0,
				[RUST_LIGHT, RUST_MID, SPARK_WARM][i % 3], Shape.STREAK, 340.0, 1.5)
	for i in 3:
		_add(pos, _spread(-dir, deg_to_rad(80), _rng.randf_range(30, 80)),
				0.45, 3.0, 2.0, RUST_DARK, Shape.PIXEL, 500.0, 0.8)


## Slow dust cloud when a body hits the ground.
func death_puff(pos: Vector2) -> void:
	for i in 14:
		_add(pos + Vector2(_rng.randf_range(-14, 14), _rng.randf_range(-4, 4)),
				_spread(Vector2.UP, PI * 0.8, _rng.randf_range(10, 40)),
				0.7, _rng.randf_range(5, 7), 3.0,
				Color(SAND_MID if i % 2 == 0 else SAND_DARK, 0.45),
				Shape.PIXEL, 90.0, 1.8)


## Ejected shell casing that bounces once and settles on the sand.
func casing(pos: Vector2, dir: Vector2) -> void:
	var side := dir.orthogonal().normalized()
	_add(pos, side * _rng.randf_range(50, 90) + Vector2(0, -60),
			4.0, 3.0, 3.0, Color("d6b593"), Shape.PIXEL, 700.0, 0.0,
			pos.y + _rng.randf_range(28, 40))


## Permanent pool left where a unit fell.
func stain(pos: Vector2) -> void:
	_add_mark(pos, 14.0, STAIN_COLOR)
	for i in 5:
		_add_mark(pos + Vector2(_rng.randf_range(-16, 16), _rng.randf_range(-7, 7)),
				_rng.randf_range(4, 8), Color(BLOOD_DARK, 0.38))
