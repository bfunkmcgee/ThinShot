extends SceneTree

## FX bench: every effect Fx/HitFx can produce, on one sand background, using
## the SAME three layers Battle builds (ground / air / additive glow), run for
## --at seconds and saved as a frame. Particles are transient, so this is the
## only way to actually LOOK at a change to Fx.gd instead of guessing.
##
## Windowed only - headless renders nothing.
##
## Run:
##   tools/godot.ps1 --path . -s tools/render_fx_bench.gd -- --at 0.4 --out fx.png
## --at is seconds of simulated life before the shot (0.1 catches flashes, 0.4
## the debris, 0.8 the smoke). --zoom magnifies the effects, not the backdrop.
##
## The backdrop sits at z -5 on purpose: fx_ground draws at z -1, so a z 0
## background would hide the ground layer entirely and blood spray, footsteps
## and scorch would all silently read as "missing".

const W := 1920
const H := 1080
const SAND := Color("8e7860")

var _shot_at := 0.35
var _out := "fx.png"
var _zoom := 2.2


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--at" and i + 1 < args.size():
			_shot_at = float(args[i + 1])
		if args[i] == "--out" and i + 1 < args.size():
			_out = args[i + 1]
		if args[i] == "--zoom" and i + 1 < args.size():
			_zoom = float(args[i + 1])
	if DisplayServer.get_name() == "headless":
		push_error("[fxbench] needs a window")
		quit(1)
		return
	_run()


func _run() -> void:
	var root_node := Node2D.new()
	root.add_child(root_node)
	var bg := ColorRect.new()
	bg.size = Vector2(W, H)
	bg.color = SAND
	bg.z_index = -5
	root_node.add_child(bg)

	var stage := Node2D.new()
	stage.scale = Vector2(_zoom, _zoom)
	root_node.add_child(stage)
	var ground := Fx.new(); ground.z_index = -1; stage.add_child(ground)
	var air := Fx.new(); stage.add_child(air)
	var glow := Fx.new()
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = m
	glow.z_index = 15
	stage.add_child(glow)

	var label_font := ThemeDB.fallback_font
	var cells := [
		["muzzle", func(p): glow.muzzle(p, Vector2.RIGHT); air.smoke_plume(p, Vector2.RIGHT)],
		["impact", func(p): glow.impact(p, Vector2.LEFT, false)],
		["impact lethal", func(p): glow.impact(p, Vector2.LEFT, true); air.blood_mist(p, Vector2.LEFT, true)],
		["cover spark", func(p): glow.cover_spark(p, Vector2.LEFT)],
		["explosion", func(p): glow.explosion(p); ground.scorch(p)],
		["blood spray", func(p): ground.blood_spray(p, p.y + 40.0, Vector2.LEFT, true)],
		["death puff", func(p): air.death_puff(p)],
		["casing x6", func(p):
			for i in 6: air.casing(p + Vector2(i * 3, 0), Vector2.RIGHT)],
		["footstep", func(p): ground.footstep(p, 1.4)],
		["smoke drift", func(p):
			for i in 6: air.smoke_drift(p)],
		["tracer", func(p): HitFx.spawn_tracer(stage, p - Vector2(90, 0), p + Vector2(90, 0), 0.5)],
		["hit ring", func(p): HitFx.spawn(stage, p, HitFx.Kind.IMPACT)],
	]
	var cols := 4
	for i in cells.size():
		var pos := Vector2(110 + (i % cols) * 190, 85 + (i / cols) * 130)
		(cells[i][1] as Callable).call(pos)
		var lab := Label.new()
		lab.text = str(cells[i][0])
		lab.position = pos * _zoom + Vector2(-64, 104)
		lab.add_theme_font_override("font", label_font)
		lab.add_theme_color_override("font_color", Color(0.15, 0.10, 0.06))
		root_node.add_child(lab)

	var elapsed := 0.0
	while elapsed < _shot_at:
		await process_frame
		elapsed += root.get_process_delta_time()
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	print("[fxbench] %s -> %s" % [_out, error_string(img.save_png(_out))])
	quit(0)
