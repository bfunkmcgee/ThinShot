class_name HitFx
extends Node2D

## One-shot code-drawn combat effect: muzzle flash, impact ring, or a round
## visibly crossing the gap. Animates a normalized t via tween, redraws each
## step, then frees itself.

enum Kind { MUZZLE, IMPACT, TRACER }

var kind := Kind.IMPACT
var from := Vector2.ZERO
var to := Vector2.ZERO
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


## A round travelling from one point to another over `travel` seconds.
static func spawn_tracer(parent: Node, p_from: Vector2, p_to: Vector2,
		travel: float) -> void:
	var fx := HitFx.new()
	fx.kind = Kind.TRACER
	fx.from = p_from
	fx.to = p_to
	fx.z_index = 15
	parent.add_child(fx)
	var tween := fx.create_tween()
	tween.tween_property(fx, "t", 1.0, travel)
	tween.tween_callback(fx.queue_free)


func _ready() -> void:
	if kind == Kind.TRACER:
		return  # spawn_tracer drives its own tween
	var tween := create_tween()
	tween.tween_property(self, "t", 1.0, 0.22 if kind == Kind.IMPACT else 0.15)
	tween.tween_callback(queue_free)


func _draw() -> void:
	var fade := 1.0 - t
	match kind:
		Kind.MUZZLE:
			draw_circle(Vector2.ZERO, lerpf(9.0, 2.0, t), Color(1.0, 0.9, 0.4, fade))
			for i in 4:
				var dir := Vector2.RIGHT.rotated(TAU * i / 4.0 + 0.4)
				draw_line(dir * 4.0, dir * lerpf(14.0, 6.0, t),
						Color(1.0, 0.95, 0.6, fade), 2.0)
		Kind.IMPACT:
			draw_arc(Vector2.ZERO, lerpf(4.0, 20.0, t), 0.0, TAU, 24,
					Color(1.0, 0.5, 0.25, fade), lerpf(4.0, 1.5, t), true)
		Kind.TRACER:
			# Head eases toward the target with a short tail behind it.
			var eased := 1.0 - pow(1.0 - t, 2.0)
			var head := from.lerp(to, eased)
			var tail := from.lerp(to, maxf(eased - 0.22, 0.0))
			draw_line(tail, head, Color(1.0, 0.9, 0.4, 0.9), 3.0)
			draw_line(head.lerp(tail, 0.5), head, Color(1.0, 1.0, 0.85, 1.0), 1.5)
