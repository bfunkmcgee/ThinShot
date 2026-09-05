extends SceneTree

## Can every briefing still be dismissed, and does it still read without
## scrolling?
##
## This check used to MODEL the panel: hardcoded font sizes, a hand-rolled wrap,
## a button height copied off the scene. Every one of those drifted, and the
## harness passed green while the shipped game softlocked - it measured a
## level's raw "briefing" string, and Battle appends Dava's notebook and the
## ratline muster to it at runtime. A late-campaign briefing outgrew the screen,
## and the button went off the bottom with the text.
##
## So it measures the real scene now. The Briefing subtree is lifted out of
## Battle.tscn and stood up on its own, the composed text is assigned to the
## actual Labels, and the engine supplies the true font, the true WORD_SMART
## wrapping, the true separations and the true button height. Nothing here can
## drift from the scene, because nothing here describes the scene.
##
## Two things are asserted, and they are not the same thing:
##
##   1. THE BUTTON IS REACHABLE. It must sit inside the viewport and must NOT
##      live inside the scrolling column. This is the softlock guard, and it
##      holds for any prose length at all.
##   2. THE PROSE STILL FITS. A mission's own briefing should not need
##      scrolling to read. Text the campaign appends may push it over, and that
##      is reported rather than failed - it scrolls, which is fine now.
##
##   godot --headless --path . -s res://tools/check_briefing_fit.gd

var _failures := 0


func _init() -> void:
	await _check_briefings()
	print("")
	_measure_after_action(ThemeDB.fallback_font)

	print("")
	if _failures > 0:
		print("RESULT: FAIL (%d problem(s))" % _failures)
		quit(1)
		return
	print("RESULT: PASS")
	quit(0)


## The worst realistic pair of blocks Battle can append. Two returner warnings
## is the cap _notebook_warnings enforces (coming.slice(0, 2)), and the muster
## line is one sentence off Ratline.strength_line.
func _worst_notebook() -> Array[String]:
	return [
		"Orrun Anhal of Vennet Rill - ran at THE SCRAPLINE, then left for dead at OUTPOST 7. Expect him.",
		"Tammar Berrow of Bhorra Low - ran at THE LONG HAUL, then left for dead at THE CISTERN. Expect him.",
	] as Array[String]


func _check_briefings() -> void:
	# One frame before anything is loaded: the autoloads are not up yet when
	# _init runs, and Battle.gd names Game at class scope - loading the scene
	# any earlier fails to compile it and hands back a scriptless tree.
	await process_frame
	# Lifted out rather than instantiated whole: adding Battle to the tree would
	# run its _ready against no campaign. The subtree carries its own anchors.
	var battle: Node = (load("res://scenes/Battle.tscn") as PackedScene).instantiate()
	var briefing: Control = battle.get_node("UI/Briefing") as Control
	var scroll: ScrollContainer = briefing.get_node("Center") as ScrollContainer
	var box: Control = briefing.get_node("Center/Middle/Box") as Control
	var button: Control = briefing.get_node("BeginButton") as Control

	# The softlock guard, asserted structurally before anything is measured: a
	# button inside the scrolling column is a button the text can push away.
	if scroll.is_ancestor_of(button):
		_failures += 1
		print("  FAIL  BeginButton is inside the scroll column - "
				+ "long prose can push it off the screen")
	else:
		print("  ok    BeginButton hangs off the panel, not off the text")

	briefing.get_parent().remove_child(briefing)
	battle.free()
	briefing.visible = true
	root.add_child(briefing)
	await process_frame
	await process_frame

	var view := Vector2(
			float(ProjectSettings.get_setting("display/window/size/viewport_width", 1920)),
			float(ProjectSettings.get_setting("display/window/size/viewport_height", 1080)))
	var rect := button.get_global_rect()
	if rect.position.y < 0.0 or rect.end.y > view.y \
			or rect.position.x < 0.0 or rect.end.x > view.x:
		_failures += 1
		print("  FAIL  BeginButton sits at %s, outside the %dx%d viewport"
				% [rect, int(view.x), int(view.y)])
	else:
		print("  ok    BeginButton sits at y=%d..%d, inside the viewport"
				% [int(rect.position.y), int(rect.end.y)])

	var room := scroll.size.y
	print("\nbriefing column %dpx wide, %dpx of readable room before it scrolls\n"
			% [int(box.size.x), int(room)])

	var notebook := _worst_notebook()
	var muster := Ratline.strength_line(80)
	for i in Levels.LEVELS.size():
		var level: Dictionary = Levels.LEVELS[i]
		var bare: float = await _column_height(briefing, box, level, [], "")
		var loaded: float = await _column_height(briefing, box, level, notebook, muster)
		var name_text := str(level.get("name", "?"))
		if bare > room:
			_failures += 1
			print("  FAIL  level %d '%s': its own prose is %dpx, over by %dpx"
					% [i + 1, name_text, int(bare), int(bare - room)])
		elif loaded > room:
			print("  ok    level %d '%s': %dpx (%dpx spare) - scrolls at %dpx once the notebook and the muster land"
					% [i + 1, name_text, int(bare), int(room - bare), int(loaded)])
		else:
			print("  ok    level %d '%s': %dpx (%dpx spare), %dpx fully loaded"
					% [i + 1, name_text, int(bare), int(room - bare), int(loaded)])

	briefing.queue_free()
	await process_frame


## The rendered height of the column, with the text Battle would actually put
## in it. Composed through Levels.briefing_body so the harness and the game can
## never assemble it differently.
func _column_height(briefing: Control, box: Control, level: Dictionary,
		notebook: Array, muster: String) -> float:
	var at := "Center/Middle/Box/"
	(briefing.get_node(at + "MissionLabel") as Label).text = \
			"OPERATION LONG SURVEY  -  MISSION 4 OF 4"
	(briefing.get_node(at + "TitleLabel") as Label).text = str(level.get("name", ""))
	(briefing.get_node(at + "FictionLabel") as Label).text = str(level.get("fiction", ""))
	(briefing.get_node(at + "BodyLabel") as Label).text = Levels.briefing_body(
			str(level.get("briefing", "")), notebook, muster)
	(briefing.get_node(at + "OrdersLabel") as Label).text = \
			"ORDERS:  %s" % level.get("orders", "")
	await process_frame
	await process_frame
	return box.get_combined_minimum_size().y


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
## in a full squad, the pay line _debrief_text appends (a blank and the
## PAY: line), and the two trailing blocks _show_game_over appends.
const SQUAD_MAX := 6
const OPERATION_LINES := 2 + SQUAD_MAX + 2 + 2 + 2
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
