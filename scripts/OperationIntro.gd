extends Control

## The operation-intro cutscene: a short, skippable drive across open desert
## before the FIRST mission of an operation, naming what the squad is about to
## fight over. Camp routes here instead of straight to Battle exactly once per
## operation - mission_number() == 1 is the gate, and it lives in Camp.gd, not
## here - so this scene never has to ask why it was reached, only how it ends.
##
## Runs standalone: `godot scenes/OperationIntro.tscn` with default autoload
## state (current_operation 0) is a valid operation, so nothing here may assume
## prior state was set up for it.
##
## Everything below is built in _ready rather than laid out in the .tscn -
## fewer places for a scene with exactly one entrance and one exit to fail.

const BACKDROP_TEX := preload(
		"res://assets/sprites/Cutscenes/operation_intro_backdrop.png")
const VEHICLE_ROOT := "res://assets/sprites/Cutscenes/transport_drive_east/"
const VEHICLE_FRAME_COUNT := 9

# The backdrop is authored at 384x216 and the viewport is always 1920x1080
# (canvas_items stretch, aspect keep) - 5x lands it exactly, corner to corner.
const BACKDROP_SCALE := 5.0
# The transport's frames are 256x256; 2x reads at the same texel density as
# everything else on screen without the wheels floating off the tile grid.
const VEHICLE_SCALE := 2.0
const VEHICLE_FPS := 9.0

# Off-screen left to off-screen right, at 2x the vehicle is 512px wide, so
# +-300 clears the frame before the drive starts and after it ends.
const DRIVE_START_X := -300.0
const DRIVE_END_X := 2300.0
const DRIVE_TIME := 5.5  # linear - a steady drive, not an ease
const HOLD_TIME := 0.4   # beat held after the transport clears frame

const TITLE_FADE_DELAY := 0.4
const TITLE_FADE_TIME := 0.8

const BG_COLOR := Color(0.055, 0.047, 0.039)
const TITLE_COLOR := Color(0.96, 0.9, 0.72)
const SECONDARY_COLOR := Color(0.78, 0.72, 0.55)

# The backdrop's stony foreground band sits at rows ~150-216 of the 384x216
# art, which is screen y ~750-1080 at 5x. The transport's own content-bottom
# (its wheels) sits at row 212 of its 256-tall frame, 84px below the frame's
# vertical centre - so a centred Sprite2D's position.y is the wheel line
# minus that offset at 2x, landing the wheels on the band rather than the sky.
const WHEEL_LINE_Y := 940.0
const VEHICLE_CONTENT_BOTTOM := 212.0
const VEHICLE_FRAME_CENTER := 128.0

var _done := false
var _vehicle_frames: Array[Texture2D] = []
var _vehicle: Sprite2D = null
var _vehicle_clock := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var backdrop := Sprite2D.new()
	backdrop.texture = BACKDROP_TEX
	backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	backdrop.centered = false
	backdrop.scale = Vector2(BACKDROP_SCALE, BACKDROP_SCALE)
	add_child(backdrop)

	_vehicle_frames = _load_vehicle_frames()
	_vehicle = Sprite2D.new()
	_vehicle.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_vehicle.scale = Vector2(VEHICLE_SCALE, VEHICLE_SCALE)
	if not _vehicle_frames.is_empty():
		_vehicle.texture = _vehicle_frames[0]
	elif OS.is_debug_build():
		push_error("[Sandline] no drive frames found under %s" % VEHICLE_ROOT)
	_vehicle.position = Vector2(DRIVE_START_X, WHEEL_LINE_Y
			- (VEHICLE_CONTENT_BOTTOM - VEHICLE_FRAME_CENTER) * VEHICLE_SCALE)
	add_child(_vehicle)

	var op: Dictionary = Game.operation()

	var title := Label.new()
	title.text = str(op.get("name", ""))
	title.add_theme_color_override("font_color", TITLE_COLOR)
	title.add_theme_font_size_override("font_size", 64)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 210.0
	title.offset_bottom = 290.0
	title.modulate.a = 0.0
	add_child(title)

	# Skipped gracefully rather than shown blank: not every operation is
	# guaranteed to carry one forever, only the shipped three do today.
	var summary_text := str(op.get("summary", ""))
	var summary: Label = null
	if not summary_text.is_empty():
		summary = Label.new()
		summary.text = summary_text
		summary.add_theme_color_override("font_color", SECONDARY_COLOR)
		summary.add_theme_font_size_override("font_size", 24)
		summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
		summary.set_anchors_preset(Control.PRESET_TOP_WIDE)
		summary.offset_left = 360.0
		summary.offset_right = -360.0
		summary.offset_top = 296.0
		summary.offset_bottom = 356.0
		summary.modulate.a = 0.0
		add_child(summary)

	var hint := Label.new()
	hint.text = "any key"
	hint.add_theme_color_override("font_color", SECONDARY_COLOR)
	hint.add_theme_font_size_override("font_size", 20)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.offset_left = -180.0
	hint.offset_top = -48.0
	hint.offset_right = -24.0
	hint.offset_bottom = -16.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(hint)

	var fade := create_tween()
	fade.tween_interval(TITLE_FADE_DELAY)
	fade.tween_property(title, "modulate:a", 1.0, TITLE_FADE_TIME)
	if summary != null:
		fade.parallel().tween_property(summary, "modulate:a", 1.0, TITLE_FADE_TIME)

	var drive := create_tween()
	drive.tween_property(_vehicle, "position:x", DRIVE_END_X, DRIVE_TIME) \
			.set_trans(Tween.TRANS_LINEAR)
	drive.tween_interval(HOLD_TIME)
	drive.tween_callback(_finish)


func _process(delta: float) -> void:
	if _vehicle == null or _vehicle_frames.is_empty():
		return
	_vehicle_clock += delta
	var idx := int(_vehicle_clock * VEHICLE_FPS) % _vehicle_frames.size()
	_vehicle.texture = _vehicle_frames[idx]


## Walks frame_000.png, frame_001.png ... until one is missing, the same rule
## Camp._load_frame_run uses for its own animated fixtures.
func _load_vehicle_frames() -> Array[Texture2D]:
	var frames: Array[Texture2D] = []
	for i in VEHICLE_FRAME_COUNT:
		var path := "%sframe_%03d.png" % [VEHICLE_ROOT, i]
		if not ResourceLoader.exists(path):
			break
		frames.append(load(path))
	return frames


## Any key, click or joypad button skips straight to the finish - a cutscene
## nobody can get past is worse than one nobody watches twice. _gui_input
## carries the mouse case (this Control's own MOUSE_FILTER_STOP claims clicks
## before they would ever reach _unhandled_input); _unhandled_input carries
## the keyboard and joypad case. _done is the only thing standing between
## either firing twice, or firing after the drive tween's own callback.
func _gui_input(event: InputEvent) -> void:
	_maybe_skip(event)


func _unhandled_input(event: InputEvent) -> void:
	_maybe_skip(event)


func _maybe_skip(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_finish()
	elif event is InputEventMouseButton and event.pressed:
		_finish()
	elif event is InputEventJoypadButton and event.pressed:
		_finish()


## The one door out, guarded so the drive tween's own callback and a skip
## press can never both fire it - whichever gets here first is the one that
## counts, and Battle loads exactly once either way.
func _finish() -> void:
	if _done:
		return
	_done = true
	Game.go_to_battle()
