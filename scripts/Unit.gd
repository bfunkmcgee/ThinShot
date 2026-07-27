class_name Unit
extends Node2D

## One combatant on the grid. Stats are set by Battle.setup() per team.
## HP pips and the selection ring are drawn in _draw().

signal died(unit: Unit)

const TEAM_SCOUT := 0
const TEAM_GOBLIN := 1

# Directional pixel-art frames, indexed by 45-degree compass sector of the
# screen-space facing vector: 0=E, 1=SE, 2=S, 3=SW, 4=W, 5=NW, 6=N, 7=NE.
const SCOUT_FRAMES: Array[Texture2D] = [
	preload("res://assets/sprites/Scout/east.png"),
	preload("res://assets/sprites/Scout/south-east.png"),
	preload("res://assets/sprites/Scout/south.png"),
	preload("res://assets/sprites/Scout/south-west.png"),
	preload("res://assets/sprites/Scout/west.png"),
	preload("res://assets/sprites/Scout/north-west.png"),
	preload("res://assets/sprites/Scout/north.png"),
	preload("res://assets/sprites/Scout/north-east.png"),
]
const GOBLIN_FRAMES: Array[Texture2D] = [
	preload("res://assets/sprites/Goblin/east.png"),
	preload("res://assets/sprites/Goblin/south-east.png"),
	preload("res://assets/sprites/Goblin/south.png"),
	preload("res://assets/sprites/Goblin/south-west.png"),
	preload("res://assets/sprites/Goblin/west.png"),
	preload("res://assets/sprites/Goblin/north-west.png"),
	preload("res://assets/sprites/Goblin/north.png"),
	preload("res://assets/sprites/Goblin/north-east.png"),
]
const SCOUT_AIM_FRAMES: Array[Texture2D] = [
	preload("res://assets/sprites/Scout/Standing_Ready_to_fire_stance/rotations/east.png"),
	preload("res://assets/sprites/Scout/Standing_Ready_to_fire_stance/rotations/south-east.png"),
	preload("res://assets/sprites/Scout/Standing_Ready_to_fire_stance/rotations/south.png"),
	preload("res://assets/sprites/Scout/Standing_Ready_to_fire_stance/rotations/south-west.png"),
	preload("res://assets/sprites/Scout/Standing_Ready_to_fire_stance/rotations/west.png"),
	preload("res://assets/sprites/Scout/Standing_Ready_to_fire_stance/rotations/north-west.png"),
	preload("res://assets/sprites/Scout/Standing_Ready_to_fire_stance/rotations/north.png"),
	preload("res://assets/sprites/Scout/Standing_Ready_to_fire_stance/rotations/north-east.png"),
]
const GOBLIN_AIM_FRAMES: Array[Texture2D] = [
	preload("res://assets/sprites/Goblin/Standing_Ready_to_fire_stance/rotations/east.png"),
	preload("res://assets/sprites/Goblin/Standing_Ready_to_fire_stance/rotations/south-east.png"),
	preload("res://assets/sprites/Goblin/Standing_Ready_to_fire_stance/rotations/south.png"),
	preload("res://assets/sprites/Goblin/Standing_Ready_to_fire_stance/rotations/south-west.png"),
	preload("res://assets/sprites/Goblin/Standing_Ready_to_fire_stance/rotations/west.png"),
	preload("res://assets/sprites/Goblin/Standing_Ready_to_fire_stance/rotations/north-west.png"),
	preload("res://assets/sprites/Goblin/Standing_Ready_to_fire_stance/rotations/north.png"),
	preload("res://assets/sprites/Goblin/Standing_Ready_to_fire_stance/rotations/north-east.png"),
]

# Compass folder names in the same sector order as the frame arrays above.
const DIR_NAMES: Array[String] = [
	"east", "south-east", "south", "south-west",
	"west", "north-west", "north", "north-east",
]

# 9-frame animation cycles per direction, loaded once per class. Note the
# exact folder casing differs between the two walk sets.
static var SCOUT_WALK_FRAMES: Array = _load_dir_frames(
		"res://assets/sprites/Scout/animations/Standing_idle_walk")
static var GOBLIN_WALK_FRAMES: Array = _load_dir_frames(
		"res://assets/sprites/Goblin/animations/standing_idle_walk")
static var SCOUT_IDLE_FRAMES: Array = _load_dir_frames(
		"res://assets/sprites/Scout/animations/standing_idle")
static var GOBLIN_IDLE_FRAMES: Array = _load_dir_frames(
		"res://assets/sprites/Goblin/animations/standing_idle")
static var SCOUT_RAISE_FRAMES: Array = _load_dir_frames(
		"res://assets/sprites/Scout/animations/standing_idle_to_ready_to_fire")
static var GOBLIN_RAISE_FRAMES: Array = _load_dir_frames(
		"res://assets/sprites/Goblin/animations/standing_idle_to_Standing_Ready_to_fire")
static var SCOUT_AIM_IDLE_FRAMES: Array = _load_dir_frames(
		"res://assets/sprites/Scout/Standing_Ready_to_fire_stance/animations/standing_ready_to_fire_idle")
static var GOBLIN_AIM_IDLE_FRAMES: Array = _load_dir_frames(
		"res://assets/sprites/Goblin/Standing_Ready_to_fire_stance/animations/standing_ready_to_fire_idle")
static var SCOUT_DEATH_FRAMES: Array = _load_dir_frames(
		"res://assets/sprites/Scout/animations/standing_idle_to_dead")
static var GOBLIN_DEATH_FRAMES: Array = _load_dir_frames(
		"res://assets/sprites/Goblin/animations/standing_idle_to_dead")
static var SCOUT_DEAD_FRAMES: Array[Texture2D] = _load_rotation_frames(
		"res://assets/sprites/Scout/dead_stance/rotations")
static var GOBLIN_DEAD_FRAMES: Array[Texture2D] = _load_rotation_frames(
		"res://assets/sprites/Goblin/Dead_stance/rotations")

enum Anim { IDLE, WALK, RAISE, AIM_IDLE, LOWER, DIE, DEAD }

const WALK_FPS := 18.0
const IDLE_FPS := 8.0
const AIM_IDLE_FPS := 8.0
const RAISE_FPS := 36.0
const DIE_FPS := 14.0

# Rifle-tip offsets in Unit space per facing sector, measured from the
# aim-stance PNGs by tools/measure_muzzle.gd (sector order = DIR_NAMES).
const SCOUT_MUZZLE_OFFSETS: Array[Vector2] = [
	Vector2(32, -40),   # east
	Vector2(10, -6),    # south-east
	Vector2(10, -2),    # south
	Vector2(-14, -6),   # south-west
	Vector2(-34, -40),  # west
	Vector2(-34, -44),  # north-west
	Vector2(-8, -62),   # north
	Vector2(30, -44),   # north-east
]
const GOBLIN_MUZZLE_OFFSETS: Array[Vector2] = [
	Vector2(34, -34),   # east
	Vector2(30, -20),   # south-east
	Vector2(-18, -2),   # south
	Vector2(-30, -18),  # south-west
	Vector2(-32, -34),  # west
	Vector2(-30, -40),  # north-west
	Vector2(-6, -60),   # north
	Vector2(32, -40),   # north-east
]

# Both sets have their figure's feet ~15px below canvas center; 2x scale puts
# a ~30px figure at ~60px on screen, sitting on the diamond center.
const SPRITE_SCALE := Vector2(2, 2)
const SPRITE_OFFSET := Vector2(0, -15)

const PIP_SIZE := Vector2(7, 5)
const PIP_GAP := 2.0
const PIP_Y := -68.0
const PIP_FULL := Color("58c04a")
const PIP_EMPTY := Color(0.15, 0.15, 0.15, 0.7)
const RING_COLOR := Color("ffd94a")        # player selection
const ENEMY_RING_COLOR := Color("ff5a3c")  # AI unit currently acting
const DONE_TINT := Color(0.55, 0.55, 0.55)

var team := TEAM_SCOUT
var max_hp := 3
var move_range := 4
var attack_range := 4
var damage := 1

var hp := 3
var cell := Vector2i.ZERO
var moved := false
var acted := false
var selected := false
var frames: Array[Texture2D] = SCOUT_FRAMES
var aim_frames: Array[Texture2D] = SCOUT_AIM_FRAMES
var walk_frames: Array = SCOUT_WALK_FRAMES
var idle_frames: Array = SCOUT_IDLE_FRAMES
var raise_frames: Array = SCOUT_RAISE_FRAMES
var aim_idle_frames: Array = SCOUT_AIM_IDLE_FRAMES
var death_frames: Array = SCOUT_DEATH_FRAMES
var dead_frames: Array[Texture2D] = SCOUT_DEAD_FRAMES
var facing_sector := 2  # south
var overwatching := false
var anim := Anim.IDLE
var anim_time := 0.0
var anim_frame := 0

@onready var sprite: Sprite2D = $Sprite


func _ready() -> void:
	sprite.scale = SPRITE_SCALE
	sprite.offset = SPRITE_OFFSET
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func setup(p_team: int, p_cell: Vector2i) -> void:
	team = p_team
	cell = p_cell
	if team == TEAM_SCOUT:
		# Damage granularity is 2 so junk cover can halve it to 1.
		max_hp = 8
		move_range = 5
		attack_range = 4
		damage = 2
		frames = SCOUT_FRAMES
		aim_frames = SCOUT_AIM_FRAMES
		walk_frames = SCOUT_WALK_FRAMES
		idle_frames = SCOUT_IDLE_FRAMES
		raise_frames = SCOUT_RAISE_FRAMES
		aim_idle_frames = SCOUT_AIM_IDLE_FRAMES
		death_frames = SCOUT_DEATH_FRAMES
		dead_frames = SCOUT_DEAD_FRAMES
		set_facing(Vector2(1, 0.5))   # face the goblin side (south-east)
	else:
		max_hp = 4
		move_range = 4
		attack_range = 3
		damage = 2
		frames = GOBLIN_FRAMES
		aim_frames = GOBLIN_AIM_FRAMES
		walk_frames = GOBLIN_WALK_FRAMES
		idle_frames = GOBLIN_IDLE_FRAMES
		raise_frames = GOBLIN_RAISE_FRAMES
		aim_idle_frames = GOBLIN_AIM_IDLE_FRAMES
		death_frames = GOBLIN_DEATH_FRAMES
		dead_frames = GOBLIN_DEAD_FRAMES
		set_facing(Vector2(-1, 0.5))  # face the scout side (south-west)
	hp = max_hp
	# Desync idle cycles so units don't all breathe in lockstep.
	anim_time = float((p_cell.x * 7 + p_cell.y * 13) % 9) / IDLE_FPS


static func _load_dir_frames(base: String) -> Array:
	var result: Array = []
	for dir_name in DIR_NAMES:
		var dir_frames: Array[Texture2D] = []
		var i := 0
		while ResourceLoader.exists("%s/%s/frame_%03d.png" % [base, dir_name, i]):
			dir_frames.append(load("%s/%s/frame_%03d.png" % [base, dir_name, i]))
			i += 1
		result.append(dir_frames)
	return result


## Loads a rotations/ folder of single per-direction PNGs (east.png, ...).
static func _load_rotation_frames(base: String) -> Array[Texture2D]:
	var result: Array[Texture2D] = []
	for dir_name in DIR_NAMES:
		var path := "%s/%s.png" % [base, dir_name]
		result.append(load(path) if ResourceLoader.exists(path) else null)
	return result


## Turn toward a screen-space direction, keeping the current stance.
func set_facing(screen_dir: Vector2) -> void:
	if screen_dir.length_squared() < 0.01:
		return
	facing_sector = wrapi(roundi(screen_dir.angle() / (TAU / 8.0)), 0, 8)
	_update_sprite()


func _set_anim(value: Anim) -> void:
	anim = value
	anim_time = 0.0
	anim_frame = 0
	_update_sprite()


## Plays the idle-to-aim transition and holds in the aimed idle loop.
## Awaitable; returns immediately if the rifle is already up.
func raise_rifle() -> void:
	if anim == Anim.AIM_IDLE or anim == Anim.DIE or anim == Anim.DEAD:
		return
	if anim != Anim.RAISE:
		_set_anim(Anim.RAISE)
	var n: int = maxi(raise_frames[facing_sector].size(), 1)
	# One extra frame of padding so the shot never fires before _process
	# has visually reached the aimed pose (frame quantization race).
	await get_tree().create_timer(float(n) / RAISE_FPS + 0.03).timeout


## Plays the aim transition in reverse back to idle.
func lower_rifle() -> void:
	if anim == Anim.AIM_IDLE or anim == Anim.RAISE:
		_set_anim(Anim.LOWER)


## Global position of the raised rifle's tip for the current facing.
func muzzle_point() -> Vector2:
	var offsets := SCOUT_MUZZLE_OFFSETS if team == TEAM_SCOUT else GOBLIN_MUZZLE_OFFSETS
	return to_global(offsets[facing_sector])


## Enter/leave overwatch: rifle raises and stays up, marker above the pips.
## Leaving overwatch does NOT lower the rifle - the shot flow or turn expiry
## handles that explicitly.
func set_overwatch(value: bool) -> void:
	overwatching = value
	if value and anim != Anim.RAISE and anim != Anim.AIM_IDLE:
		_set_anim(Anim.RAISE)
	queue_redraw()


func start_walking() -> void:
	if anim == Anim.DIE or anim == Anim.DEAD:
		return
	_set_anim(Anim.WALK)


func stop_walking() -> void:
	if anim == Anim.WALK:
		_set_anim(Anim.IDLE)


func _process(delta: float) -> void:
	if anim == Anim.DEAD:
		return
	var fps := IDLE_FPS
	match anim:
		Anim.WALK:
			fps = WALK_FPS
		Anim.RAISE, Anim.LOWER:
			fps = RAISE_FPS
		Anim.AIM_IDLE:
			fps = AIM_IDLE_FPS
		Anim.DIE:
			fps = DIE_FPS
	anim_time += delta
	var idx := int(anim_time * fps)
	if idx == anim_frame:
		return
	anim_frame = idx
	var cycle: Array = _current_cycle()
	var length: int = maxi(cycle.size(), 1)
	if anim_frame >= length:
		match anim:
			Anim.RAISE:
				_set_anim(Anim.AIM_IDLE)
			Anim.LOWER:
				_set_anim(Anim.IDLE)
			Anim.DIE:
				_set_anim(Anim.DEAD)
			_:
				_update_sprite()  # loops wrap via modulo
		return
	_update_sprite()


func _current_cycle() -> Array:
	match anim:
		Anim.WALK:
			return walk_frames[facing_sector]
		Anim.RAISE, Anim.LOWER:
			return raise_frames[facing_sector]
		Anim.AIM_IDLE:
			return aim_idle_frames[facing_sector]
		Anim.DIE:
			return death_frames[facing_sector]
	return idle_frames[facing_sector]


func _update_sprite() -> void:
	if anim == Anim.DEAD:
		var corpse := dead_frames[facing_sector]
		if corpse != null:
			sprite.texture = corpse
		return
	var cycle: Array = _current_cycle()
	if cycle.is_empty():
		# Fallback to static poses if a frame set is missing.
		var wants_aim := anim == Anim.RAISE or anim == Anim.AIM_IDLE or anim == Anim.LOWER
		sprite.texture = (aim_frames if wants_aim else frames)[facing_sector]
		return
	var idx := anim_frame
	if anim == Anim.LOWER:
		idx = cycle.size() - 1 - clampi(anim_frame, 0, cycle.size() - 1)
	elif anim == Anim.DIE:
		idx = clampi(anim_frame, 0, cycle.size() - 1)
	else:
		idx = anim_frame % cycle.size()
	sprite.texture = cycle[idx]


func is_alive() -> bool:
	return hp > 0


func take_damage(amount: int) -> void:
	if hp <= 0:
		return  # already dead; never double-kill a corpse
	_spawn_damage_number(amount)
	hp = maxi(hp - amount, 0)
	queue_redraw()
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(1.6, 0.3, 0.3), 0.08)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.15)
	if hp == 0:
		died.emit(self)
		_die()


## Plays the fall animation, then rests in the dead stance. The corpse stays
## in the tree for the whole battle; is_alive() == false makes every gameplay
## query (occupancy, targeting, turns) ignore it.
func _die() -> void:
	overwatching = false
	selected = false
	modulate = Color(0.9, 0.87, 0.84)
	# Nudge up a hair so y-sort keeps living units on this tile in front.
	position.y -= 0.6
	_set_anim(Anim.DIE)
	queue_redraw()


## Floating "-N" label. Parented to this unit's parent (not the unit itself)
## so it outlives a killed unit; its tween is owned by the label for the same
## reason. z_index lifts it clear of the y-sorted entities.
func _spawn_damage_number(amount: int) -> void:
	var label := Label.new()
	label.text = "-%d" % amount
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 6)
	label.z_index = 20
	get_parent().add_child(label)
	label.global_position = global_position + Vector2(-12.0, -84.0)
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 40.0, 0.6)
	tween.tween_property(label, "modulate:a", 0.0, 0.6).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)


func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


func set_done(value: bool) -> void:
	moved = value
	acted = value
	modulate = DONE_TINT if value else Color(1, 1, 1, modulate.a)
	queue_redraw()


func start_turn() -> void:
	moved = false
	acted = false
	modulate = Color.WHITE
	if overwatching:
		set_overwatch(false)  # unfired overwatch expires...
		lower_rifle()         # ...and the rifle comes down
	queue_redraw()


func _draw() -> void:
	if hp <= 0:
		return  # corpses carry no pips, rings, or markers
	if selected:
		# Ground ellipse at the unit's feet, matching the isometric 2:1 view.
		var ring := RING_COLOR if team == TEAM_SCOUT else ENEMY_RING_COLOR
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
		draw_arc(Vector2.ZERO, 38.0, 0.0, TAU, 48, ring, 3.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var total_width := max_hp * PIP_SIZE.x + (max_hp - 1) * PIP_GAP
	var start_x := -total_width / 2.0
	for i in max_hp:
		var rect := Rect2(Vector2(start_x + i * (PIP_SIZE.x + PIP_GAP), PIP_Y), PIP_SIZE)
		draw_rect(rect, PIP_FULL if i < hp else PIP_EMPTY)
		draw_rect(rect, Color(0, 0, 0, 0.5), false, 1.0)
	if overwatching:
		# Small amber diamond above the pips: "this unit is watching".
		var m := Vector2(0, PIP_Y - 9.0)
		draw_colored_polygon(PackedVector2Array([
			m + Vector2(0, -5), m + Vector2(5, 0), m + Vector2(0, 5), m + Vector2(-5, 0),
		]), Color("ffb84a"))
