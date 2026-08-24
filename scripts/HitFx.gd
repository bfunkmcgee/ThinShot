class_name HitFx
extends Node2D

## One-shot code-drawn combat effect: muzzle flash, impact ring, or a round
## visibly crossing the gap. Animates a normalized t via tween, redraws each
## step, then frees itself.

enum Kind { MUZZLE, IMPACT, TRACER }

var kind := Kind.IMPACT
var from := Vector2.ZERO
var to := Vector2.ZERO
# Baked once per instance so a flash is not the same drawing every shot.
var _seed := 0.0
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
	_seed = randf() * TAU
	if kind == Kind.TRACER:
		return  # spawn_tracer drives its own tween
	var tween := create_tween()
	tween.tween_property(self, "t", 1.0, 0.22 if kind == Kind.IMPACT else 0.15)
	tween.tween_callback(queue_free)


func _draw() -> void:
	var fade := 1.0 - t
	match kind:
		Kind.MUZZLE:
			# Two-tone core: a white centre inside an amber bloom, so the flash
			# has a temperature instead of being one flat yellow disc.
			draw_circle(Vector2.ZERO, lerpf(13.0, 3.0, t),
					Color(1.0, 0.72, 0.26, fade * 0.55))
			draw_circle(Vector2.ZERO, lerpf(7.5, 1.5, t),
					Color(1.0, 0.97, 0.80, fade))
			# Five spokes at a per-instance angle and uneven lengths. The old
			# four at a fixed +0.4 offset drew an identical cross every shot,
			# and the eye picks that repetition up fast at the fire rates the
			# machinegunner shoots at.
			for i in 5:
				var dir := Vector2.RIGHT.rotated(TAU * i / 5.0 + _seed)
				var reach: float = lerpf(16.0 + float(i % 3) * 5.0, 5.0, t)
				draw_line(dir * 3.0, dir * reach,
						Color(1.0, 0.95, 0.6, fade), lerpf(2.6, 0.8, t))
		Kind.IMPACT:
			# Ring plus a trailing echo a beat behind it, which reads as the
			# shock spreading rather than as one hoop being scaled up.
			draw_arc(Vector2.ZERO, lerpf(4.0, 20.0, t), 0.0, TAU, 32,
					Color(1.0, 0.5, 0.25, fade), lerpf(4.0, 1.5, t), true)
			draw_arc(Vector2.ZERO, lerpf(2.0, 13.0, t), 0.0, TAU, 24,
					Color(1.0, 0.85, 0.55, fade * 0.5), lerpf(2.5, 1.0, t), true)
		Kind.TRACER:
			# Head eases toward the target, with the tail built from a few
			# segments that thin and dim behind it. One flat line of constant
			# width was the same bright bar from muzzle to target; a graded
			# tail is what makes the round look like it is MOVING.
			var eased := 1.0 - pow(1.0 - t, 2.0)
			var head := from.lerp(to, eased)
			const SEGS := 4
			for i in SEGS:
				var a: float = maxf(eased - 0.24 * float(i + 1) / SEGS, 0.0)
				var b: float = maxf(eased - 0.24 * float(i) / SEGS, 0.0)
				var f: float = 1.0 - float(i) / SEGS
				draw_line(from.lerp(to, a), from.lerp(to, b),
						Color(1.0, 0.86, 0.38, 0.9 * f * f), lerpf(1.0, 3.2, f))
			# Hot core and a bright head, so the leading edge reads first.
			draw_line(from.lerp(to, maxf(eased - 0.07, 0.0)), head,
					Color(1.0, 1.0, 0.88, 1.0), 1.6)
			draw_circle(head, 2.4, Color(1.0, 1.0, 0.92, 0.95))
