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
	_measure_after_action(font)

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


# --- the after-action ---------------------------------------------------------
#
# A second, unrelated collision, in the same spirit. The results panel stacks a
# debrief paragraph that flows DOWN from y=126 over two columns that are
# bottom-aligned at y=600 and therefore grow UP. Neither clips and neither
# scrolls, so the failure mode is prose printed through prose - and it gets
# likelier every time either half gains a line.

# Straight off scenes/Battle.tscn.
const NARRATIVE_TOP := 126.0
const NARRATIVE_WIDTH := 1200.0
const NARRATIVE_SIZE := 22
const COLUMN_BOTTOM := 890.0
const COLUMN_WIDTH := 500.0
const COLUMN_SIZE := 20

## The tallest the left column can get: heading, a blank, one line per soldier
## in a full squad, and the two trailing blocks _show_game_over appends.
const SQUAD_MAX := 6
const OPERATION_LINES := 2 + SQUAD_MAX + 2 + 2
## The right column is bounded by construction - ROLL_NAMES_SHOWN caps the names
## - so its worst case is every optional block present at once.
## +2 for the STILL OUT THERE block (a blank and one line). It is one line by
## construction - Battle._still_out_there joins every survivor into it - which
## is why this is a constant and not a per-survivor term.
const ROLL_LINES := 2 + 2 + 3 + 1 + 2 + 2 + 2


func _measure_after_action(font: Font) -> void:
	var line_height := font.get_height(COLUMN_SIZE)
	var tallest := maxi(OPERATION_LINES, ROLL_LINES)
	var column_top := COLUMN_BOTTOM - float(tallest) * line_height
	print("after-action: columns rise to y=%d at worst (%d lines)"
			% [int(column_top), tallest])
	for i in Levels.LEVELS.size():
		var level: Dictionary = Levels.LEVELS[i]
		var text := str(level.get("debrief", ""))
		var height := _wrapped_height_at(font, text, NARRATIVE_SIZE, NARRATIVE_WIDTH)
		var narrative_bottom := NARRATIVE_TOP + height
		var slack := column_top - narrative_bottom
		var name_text := str(level.get("name", "?"))
		if slack < 0.0:
			_failures += 1
			print("  FAIL  level %d '%s': debrief reaches y=%d, columns start y=%d - overlaps by %d"
					% [i + 1, name_text, int(narrative_bottom), int(column_top), int(-slack)])
		else:
			print("  ok    level %d '%s': debrief ends y=%d, %dpx clear of the columns"
					% [i + 1, name_text, int(narrative_bottom), int(slack)])


func _wrapped_height_at(font: Font, text: String, size: int, width: float) -> float:
	if text.is_empty():
		return 0.0
	var line_height := font.get_height(size)
	var lines := 0
	for paragraph in text.split("\n"):
		if paragraph.is_empty():
			lines += 1
			continue
		var w := font.get_string_size(
				paragraph, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		lines += maxi(1, int(ceil(w / width)))
	return float(lines) * line_height
