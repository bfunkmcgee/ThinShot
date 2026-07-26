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

const WALK_FPS := 18.0
const IDLE_FPS := 8.0

# Both sets have their figure's feet ~15px below canvas center; 2x scale puts
# a ~30px figure at ~60px on screen, sitting on the diamond center.
const SPRITE_SCALE := Vector2(2, 2)
const SPRITE_OFFSET := Vector2(0, -15)

const PIP_SIZE := Vector2(8, 5)
const PIP_GAP := 3.0
const PIP_Y := -68.0
const PIP_FULL := Color("58c04a")
const PIP_EMPTY := Color(0.15, 0.15, 0.15, 0.7)
const RING_COLOR := Color("ffd94a")
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
var facing_sector := 2  # south
var aiming := false
var walking := false
var walk_time := 0.0
var walk_frame := 0
var idle_time := 0.0
var idle_frame := 0

@onready var sprite: Sprite2D = $Sprite


func _ready() -> void:
	sprite.scale = SPRITE_SCALE
	sprite.offset = SPRITE_OFFSET
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func setup(p_team: int, p_cell: Vector2i) -> void:
	team = p_team
	cell = p_cell
	if team == TEAM_SCOUT:
		max_hp = 3
		move_range = 4
		attack_range = 4
		damage = 1
		frames = SCOUT_FRAMES
		aim_frames = SCOUT_AIM_FRAMES
		walk_frames = SCOUT_WALK_FRAMES
		idle_frames = SCOUT_IDLE_FRAMES
		set_facing(Vector2(1, 0.5))   # face the goblin side (south-east)
	else:
		max_hp = 2
		move_range = 3
		attack_range = 3
		damage = 1
		frames = GOBLIN_FRAMES
		aim_frames = GOBLIN_AIM_FRAMES
		walk_frames = GOBLIN_WALK_FRAMES
		idle_frames = GOBLIN_IDLE_FRAMES
		set_facing(Vector2(-1, 0.5))  # face the scout side (south-west)
	hp = max_hp
	# Desync idle cycles so units don't all breathe in lockstep.
	idle_time = float((p_cell.x * 7 + p_cell.y * 13) % 9) / IDLE_FPS


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


## Turn toward a screen-space direction, keeping the current stance.
func set_facing(screen_dir: Vector2) -> void:
	if screen_dir.length_squared() < 0.01:
		return
	facing_sector = wrapi(roundi(screen_dir.angle() / (TAU / 8.0)), 0, 8)
	_update_sprite()


## Raise (true) or lower (false) the rifle.
func set_aiming(value: bool) -> void:
	aiming = value
	_update_sprite()


func start_walking() -> void:
	walking = true
	walk_time = 0.0
	walk_frame = 0
	_update_sprite()


func stop_walking() -> void:
	walking = false
	_update_sprite()


func _process(delta: float) -> void:
	if walking:
		walk_time += delta
		var idx := int(walk_time * WALK_FPS)
		if idx != walk_frame:
			walk_frame = idx
			_update_sprite()
	elif not aiming:
		idle_time += delta
		var idx := int(idle_time * IDLE_FPS)
		if idx != idle_frame:
			idle_frame = idx
			_update_sprite()


func _update_sprite() -> void:
	if aiming:
		sprite.texture = aim_frames[facing_sector]
		return
	if walking:
		var dir_frames: Array = walk_frames[facing_sector]
		if not dir_frames.is_empty():
			sprite.texture = dir_frames[walk_frame % dir_frames.size()]
			return
	var idle_dir: Array = idle_frames[facing_sector]
	if not idle_dir.is_empty():
		sprite.texture = idle_dir[idle_frame % idle_dir.size()]
		return
	sprite.texture = frames[facing_sector]


func is_alive() -> bool:
	return hp > 0


func take_damage(amount: int) -> void:
	_spawn_damage_number(amount)
	hp = maxi(hp - amount, 0)
	queue_redraw()
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(1.6, 0.3, 0.3), 0.08)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.15)
	if hp == 0:
		died.emit(self)
		tween.tween_property(self, "modulate:a", 0.0, 0.3)
		tween.tween_callback(queue_free)


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
	queue_redraw()


func _draw() -> void:
	if selected:
		# Ground ellipse at the unit's feet, matching the isometric 2:1 view.
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
		draw_arc(Vector2.ZERO, 38.0, 0.0, TAU, 48, RING_COLOR, 3.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var total_width := max_hp * PIP_SIZE.x + (max_hp - 1) * PIP_GAP
	var start_x := -total_width / 2.0
	for i in max_hp:
		var rect := Rect2(Vector2(start_x + i * (PIP_SIZE.x + PIP_GAP), PIP_Y), PIP_SIZE)
		draw_rect(rect, PIP_FULL if i < hp else PIP_EMPTY)
		draw_rect(rect, Color(0, 0, 0, 0.5), false, 1.0)
