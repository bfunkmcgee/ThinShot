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
# Scouts bleed red, the Choir bleeds green ichor.
const BLOOD_SCOUT := Color("a81f14")
const BLOOD_SCOUT_DARK := Color("6e1109")
const BLOOD_GOBLIN := Color("5c8a2a")
const BLOOD_GOBLIN_DARK := Color("31501a")
const STAIN_COLOR := Color(0.17, 0.10, 0.07, 0.18)


static func blood_of(team: int) -> Color:
	return BLOOD_SCOUT if team == 0 else BLOOD_GOBLIN


static func blood_dark_of(team: int) -> Color:
	return BLOOD_SCOUT_DARK if team == 0 else BLOOD_GOBLIN_DARK

var _p: Array = []
var _marks: Array = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	set_process(false)


func _process(delta: float) -> void:
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
	if live == 0:
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


## Flash, sparks and lingering smoke at the muzzle.
func muzzle(pos: Vector2, dir: Vector2) -> void:
	_add(pos, Vector2.ZERO, 0.12, 4.0, 18.0, Color(SPARK_WARM, 0.9), Shape.RING)
	for i in 6:
		_add(pos, _spread(dir, deg_to_rad(35), _rng.randf_range(120, 260)),
				0.18, 3.0, 1.0,
				SPARK_HOT if i % 2 == 0 else SPARK_WARM, Shape.STREAK, 90.0, 3.0)
	for i in 4:
		_add(pos + Vector2(_rng.randf_range(-3, 3), 0),
				_spread(Vector2.UP, PI * 0.35, _rng.randf_range(8, 20)),
				0.7, 4.0, 9.0, Color(SAND_DARK, 0.30), Shape.PIXEL, -6.0, 1.2)


## Impact burst: a bright ring plus sand kicked off the body.
func impact(pos: Vector2, dir: Vector2, _team: int, lethal := false) -> void:
	_add(pos, Vector2.ZERO, 0.22, 4.0, 16.0, Color(SPARK_WARM, 0.7), Shape.RING)
	for i in (6 if lethal else 4):
		_add(pos, _spread(dir, deg_to_rad(40), _rng.randf_range(30, 90)),
				0.3, 3.0, 1.0, Color(SAND_MID, 0.6), Shape.PIXEL, 380.0, 1.0)


## Blood bursting out of the wound: a fast mist punched through in the
## round's direction plus a little back-spatter toward the shooter.
## Belongs on the layer drawn above units.
func blood_mist(pos: Vector2, dir: Vector2, team: int, lethal := false) -> void:
	var gore := blood_of(team)
	var dark := blood_dark_of(team)
	for i in (14 if lethal else 8):
		_add(pos, _spread(dir, deg_to_rad(38), _rng.randf_range(90, 260)),
				_rng.randf_range(0.10, 0.20),
				_rng.randf_range(3, 6), 1.0,
				Color(gore if i % 3 else dark, 0.95), Shape.STREAK, 60.0, 4.0)
	for i in (5 if lethal else 3):
		_add(pos, _spread(-dir, deg_to_rad(55), _rng.randf_range(30, 90)),
				0.22, _rng.randf_range(2, 4), 1.0,
				Color(dark, 0.85), Shape.PIXEL, 260.0, 2.0)
	if lethal:
		# A heavier cloud hanging at the wound for a beat.
		for i in 6:
			_add(pos + Vector2(_rng.randf_range(-6, 6), _rng.randf_range(-6, 6)),
					_spread(dir, PI, _rng.randf_range(6, 24)),
					0.45, _rng.randf_range(5, 8), 2.0,
					Color(dark, 0.55), Shape.PIXEL, 40.0, 2.5)


## Droplets that arc away from the wound, fall, and permanently stain the
## sand where they land. Belongs on the ground layer so the splats sit
## under the units.
func blood_spray(pos: Vector2, ground_y: float, dir: Vector2, team: int,
		lethal := false) -> void:
	var gore := blood_of(team)
	var dark := blood_dark_of(team)
	for i in (18 if lethal else 11):
		var speed := _rng.randf_range(70, 210)
		_add(pos, _spread(dir, deg_to_rad(52), speed),
				1.4, _rng.randf_range(2, 4), _rng.randf_range(2, 4),
				Color(gore if i % 2 else dark, 0.95), Shape.PIXEL,
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


## Permanent pool left where a unit fell, in its own blood color.
func stain(pos: Vector2, team := -1) -> void:
	_add_mark(pos, 14.0, STAIN_COLOR)
	if team < 0:
		return
	for i in 5:
		_add_mark(pos + Vector2(_rng.randf_range(-16, 16), _rng.randf_range(-7, 7)),
				_rng.randf_range(4, 8), Color(blood_dark_of(team), 0.38))
