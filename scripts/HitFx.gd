class_name HitFx
extends Node2D

## One-shot code-drawn combat effect: muzzle flash or impact ring.
## Animates a normalized t via tween, redraws each step, then frees itself.

enum Kind { MUZZLE, IMPACT }

var kind := Kind.IMPACT
var t := 0.0:
	set(value):
		t = value
		queue_redraw()


static func spawn(parent: Node, pos: Vector2, p_kind: Kind) -> void:
	var fx := HitFx.new()
	fx.kind = p_kind
	fx.position = pos
	fx.z_index = 15
	parent.add_child(fx)


func _ready() -> void:
	var tween := create_tween()
	tween.tween_property(self, "t", 1.0, 0.22 if kind == Kind.IMPACT else 0.15)
	tween.tween_callback(queue_free)


func _draw() -> void:
	var fade := 1.0 - t
	if kind == Kind.MUZZLE:
		draw_circle(Vector2.ZERO, lerpf(9.0, 2.0, t), Color(1.0, 0.9, 0.4, fade))
		for i in 4:
			var dir := Vector2.RIGHT.rotated(TAU * i / 4.0 + 0.4)
			draw_line(dir * 4.0, dir * lerpf(14.0, 6.0, t),
					Color(1.0, 0.95, 0.6, fade), 2.0)
	else:
		draw_arc(Vector2.ZERO, lerpf(4.0, 20.0, t), 0.0, TAU, 24,
				Color(1.0, 0.5, 0.25, fade), lerpf(4.0, 1.5, t), true)
