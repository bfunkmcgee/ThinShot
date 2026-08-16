extends SceneTree

## Does every briefing still fit on screen?
##
## The briefing panel is a CenterContainer with a fixed 1230px column and
## autowrapped labels, so it has no scrollbar and no clipping: text that grows
## past the viewport simply runs off the top and bottom edges where nobody can
## read it. Prose is data in this project - it lives in Levels.gd and gets
## rewritten - so the fit is worth asserting rather than eyeballing once.
##
##   godot --headless --path . -s res://tools/check_briefing_fit.gd

# Straight off scenes/Battle.tscn: UI/Briefing/Center/Box.
const BOX_WIDTH := 1230.0
const SEPARATION := 16.0
# UI/Briefing/Center insets the full-rect panel by 72px on every side.
const MARGIN := 72.0

# (level field, font size). BeginButton is a fixed-height control, measured
# separately below.
const ROWS: Array = [
	["_mission", 26],
	["name", 69],
	["fiction", 24],
	["briefing", 27],
	["_orders", 33],
]
const BUTTON_HEIGHT := 60.0

var _failures := 0


func _init() -> void:
	var viewport_height := float(ProjectSettings.get_setting(
			"display/window/size/viewport_height", 1080))
	var budget := viewport_height - MARGIN * 2.0
	print("briefing column %dpx wide, %dpx of vertical room\n"
			% [int(BOX_WIDTH), int(budget)])

	var font := ThemeDB.fallback_font
	for i in Levels.LEVELS.size():
		var level: Dictionary = Levels.LEVELS[i]
		_measure(font, i, level, budget)

	print("")
	if _failures > 0:
		print("RESULT: FAIL (%d briefing(s) overflow the panel)" % _failures)
		quit(1)
		return
	print("RESULT: PASS")
	quit(0)


func _measure(font: Font, index: int, level: Dictionary, budget: float) -> void:
	var total := BUTTON_HEIGHT + SEPARATION * float(ROWS.size())
	for row: Array in ROWS:
		var key: String = row[0]
		var size: int = row[1]
		var text := _text_for(key, level)
		total += _wrapped_height(font, text, size)

	var name_text := str(level.get("name", "?"))
	var slack := budget - total
	if slack < 0.0:
		_failures += 1
		print("  FAIL  level %d '%s': %dpx, over by %dpx"
				% [index + 1, name_text, int(total), int(-slack)])
	else:
		print("  ok    level %d '%s': %dpx (%dpx spare)"
				% [index + 1, name_text, int(total), int(slack)])


## The two labels whose text Battle.gd composes rather than reads straight off
## the level. Both are single lines; the longest realistic form is used.
func _text_for(key: String, level: Dictionary) -> String:
	match key:
		"_mission":
			return "OPERATION LONG SURVEY  -  MISSION 4 OF 4"
		"_orders":
			return "ORDERS:  %s" % level.get("orders", "")
	return str(level.get(key, ""))


## Height of `text` autowrapped into BOX_WIDTH at `size`, counting the explicit
## newlines the prose uses to separate paragraphs.
func _wrapped_height(font: Font, text: String, size: int) -> float:
	if text.is_empty():
		return 0.0
	var line_height := font.get_height(size)
	var lines := 0
	for paragraph in text.split("\n"):
		if paragraph.is_empty():
			lines += 1
			continue
		var width := font.get_string_size(
				paragraph, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		lines += maxi(1, int(ceil(width / BOX_WIDTH)))
	return float(lines) * line_height
