class_name Unit
extends Node2D

## One combatant on the grid. Stats are set by Battle.setup() per team.
## HP pips and the selection ring are drawn in _draw().

signal died(unit: Unit)

const TEAM_SCOUT := 0
const TEAM_GOBLIN := 1

const PIP_SIZE := Vector2(8, 5)
const PIP_GAP := 3.0
const PIP_Y := -34.0
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

@onready var sprite: Sprite2D = $Sprite


func setup(p_team: int, p_cell: Vector2i, texture: Texture2D) -> void:
	team = p_team
	cell = p_cell
	if team == TEAM_SCOUT:
		max_hp = 3
		move_range = 4
		attack_range = 4
	else:
		max_hp = 2
		move_range = 3
		attack_range = 3
	hp = max_hp
	sprite.texture = texture


func is_alive() -> bool:
	return hp > 0


func take_damage(amount: int) -> void:
	hp = maxi(hp - amount, 0)
	queue_redraw()
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color(1.6, 0.3, 0.3), 0.08)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.15)
	if hp == 0:
		died.emit(self)
		tween.tween_property(self, "modulate:a", 0.0, 0.3)
		tween.tween_callback(queue_free)


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
		draw_arc(Vector2.ZERO, 28.0, 0.0, TAU, 40, RING_COLOR, 2.5, true)
	var total_width := max_hp * PIP_SIZE.x + (max_hp - 1) * PIP_GAP
	var start_x := -total_width / 2.0
	for i in max_hp:
		var rect := Rect2(Vector2(start_x + i * (PIP_SIZE.x + PIP_GAP), PIP_Y), PIP_SIZE)
		draw_rect(rect, PIP_FULL if i < hp else PIP_EMPTY)
		draw_rect(rect, Color(0, 0, 0, 0.5), false, 1.0)
