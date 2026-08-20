class_name BattleHud
extends Control

## The battle HUD: everything on screen that is not the board.
##
## Built entirely in code rather than in Battle.tscn, for one reason - the HUD
## is a dozen panels that all show the same handful of numbers, and in a scene
## file that becomes a dozen node paths for Battle to hold and keep in step.
## Here Battle holds ONE reference and calls refresh(); this file decides what
## every panel says. Battle.gd is 4700 lines and none of them needed to become
## layout code.
##
## The one deliberate exception is the action bar. Those Buttons still live in
## Battle.tscn and are still wired to Battle's handlers and its .disabled /
## .text / .visible writes - this only REPARENTS them into a styled row. That
## keeps every hotkey, every enable rule and every label exactly as it was, and
## meant the overhaul did not have to re-derive when Suppress is legal.
##
## Nothing here invents state. Every number is read from the mission that is
## actually running: objective progress off Battle's own objective pass, HP and
## action pips off the units, ordnance off the two counters that the throw code
## decrements. There is no resource meter here that the rules do not also know
## about.

const PAD := 14.0        # screen edge inset
const PIP := Vector2(9, 7)
const PIP_GAP := 3.0
const PORTRAIT := 46.0   # roster / inspect chip
const ORDER_CHIP := 40.0 # order-of-battle chip

var battle: Node = null

var _obj_frame: Framed
var _mission_frame: Framed
var _order_frame: Framed
var _roster_frame: Framed
var _objectives_box: VBoxContainer
var _mission_box: VBoxContainer
var _order_row: HBoxContainer
var _roster_box: VBoxContainer
var _inspect_frame: Framed
var _inspect_portrait: TextureRect
var _inspect_pips: PipRow
var _action_row: HBoxContainer
var _bar_frame: Framed
var _hint: Label
## Battle's own turn banner. Not reparented - it is a full-width Label and it
## animates - but its vertical offset is set from here, because it has to clear
## the order-of-battle strip and that strip's height depends on how many
## fighters are in the mission.
var _banner: Control = null

## Rebuilt only when the cast changes, not every refresh: these hold TextureRects
## whose portraits cost an image read, and the order of battle is stable for
## whole turns at a time.
var _order_signature := ""
var _roster_signature := ""
var _mission_signature := ""


# --------------------------------------------------------------------- pieces

## A panel with brass corner brackets. The brackets are the whole reason this
## is a custom class: a plain 1px border reads as a web page, and the mockup's
## military-issue look comes almost entirely from the corners being drawn
## heavier than the edges.
class Framed extends PanelContainer:
	var edge := UiTheme.EDGE_BRIGHT
	var bracket := 11.0

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var w := 2.0
		for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
			var o := Vector2(r.position.x + corner.x * r.size.x,
					r.position.y + corner.y * r.size.y)
			var sx := 1.0 if corner.x == 0 else -1.0
			var sy := 1.0 if corner.y == 0 else -1.0
			draw_line(o + Vector2(0, sy * 0.5), o + Vector2(sx * bracket, sy * 0.5), edge, w)
			draw_line(o + Vector2(sx * 0.5, 0), o + Vector2(sx * 0.5, sy * bracket), edge, w)


## A row of small rectangles. Used for HP, for the two action pips, and for
## ordnance - one visual idea for "how many of these are left", so the player
## learns to read it once. The board draws its unit HP the same way.
class PipRow extends Control:
	var total := 0
	var filled := 0
	var full_color := UiTheme.READY
	var empty_color := UiTheme.SPENT
	var pip := Vector2(9, 7)
	var gap := 3.0
	## Above zero, pips are drawn in groups of this many with a wider break
	## between groups, so ten hit points can be counted at a glance instead of
	## measured. Zero disables grouping.
	var group := 0

	func set_pips(p_filled: int, p_total: int) -> void:
		if p_filled == filled and p_total == total:
			return
		filled = p_filled
		total = p_total
		_resize()
		queue_redraw()

	func _resize() -> void:
		var breaks := 0 if group <= 0 else maxi(int((total - 1) / group), 0)
		custom_minimum_size = Vector2(
				total * pip.x + maxf(total - 1, 0) * gap + breaks * gap * 1.6, pip.y)

	func _draw() -> void:
		var x := 0.0
		for i in total:
			if group > 0 and i > 0 and i % group == 0:
				x += gap * 1.6
			draw_rect(Rect2(Vector2(x, 0), pip),
					full_color if i < filled else empty_color)
			x += pip.x + gap


func _label(text: String, size: int, color: Color, bold_caps := false) -> Label:
	var l := Label.new()
	l.text = text.to_upper() if bold_caps else text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Panel scaffold: a framed box with a title rule across the top.
func _panel(title: String) -> Array:
	var frame := Framed.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", UiTheme.panel_style(false, UiTheme.EDGE, 12))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(col)
	if not title.is_empty():
		var head := _label(title, UiTheme.FONT_HEAD, UiTheme.HEADER, true)
		col.add_child(head)
		var rule := ColorRect.new()
		rule.color = UiTheme.EDGE
		rule.custom_minimum_size = Vector2(0, 1)
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(rule)
	return [frame, col]


func _portrait_chip(unit: Unit, box: float, tint: Color) -> Control:
	var holder := Framed.new()
	holder.bracket = 6.0
	holder.edge = tint
	holder.custom_minimum_size = Vector2(box, box)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := UiTheme.panel_style(true, tint.darkened(0.25), 0)
	holder.add_theme_stylebox_override("panel", sb)
	var tex := TextureRect.new()
	tex.texture = UiTheme.portrait(_face_texture(unit))
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex.custom_minimum_size = Vector2(box, box)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tex.clip_contents = true
	if not unit.is_alive():
		tex.modulate = Color(0.45, 0.42, 0.40, 0.85)
	holder.add_child(tex)
	return holder


## The south-facing standing rotation, which is the pose the player sees most
## and the one every kind is most recognisable in. Read off the unit's own
## loaded set rather than a path table, so a kind whose art is re-pointed in
## Unit.gd cannot end up with somebody else's face on its card.
func _face_texture(unit: Unit) -> Texture2D:
	if unit == null:
		return null
	if unit.frames.size() > 2 and unit.frames[2] != null:
		return unit.frames[2]
	if unit.sprite != null:
		return unit.sprite.texture
	return null


# ---------------------------------------------------------------------- build

func _ready() -> void:
	name = "Hud"
	# Anchors alone give a Control under a CanvasLayer nothing: the layer is not
	# a Control, so there is no parent rect for them to resolve against and this
	# node stays 0x0. Everything downstream then centres against a width of
	# zero, which put the order strip half off the left edge and the roster and
	# action bar off the top of the screen entirely. _layout measures the
	# viewport itself; the preset is kept so the node still reports a sane rect.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.build()
	_build_objectives()
	_build_mission()
	_build_order()
	_build_roster()
	_build_hint()


func _build_objectives() -> void:
	var made := _panel("Objectives")
	var frame: Framed = made[0]
	_objectives_box = VBoxContainer.new()
	_objectives_box.add_theme_constant_override("separation", 8)
	_objectives_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(made[1] as VBoxContainer).add_child(_objectives_box)
	frame.custom_minimum_size = Vector2(330, 0)
	_obj_frame = frame
	add_child(frame)


func _build_mission() -> void:
	var made := _panel("Mission")
	var frame: Framed = made[0]
	_mission_box = VBoxContainer.new()
	_mission_box.add_theme_constant_override("separation", 5)
	_mission_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(made[1] as VBoxContainer).add_child(_mission_box)
	frame.custom_minimum_size = Vector2(330, 0)
	_mission_frame = frame
	add_child(frame)


func _build_order() -> void:
	var made := _panel("Order of Battle")
	var frame: Framed = made[0]
	_order_row = HBoxContainer.new()
	_order_row.add_theme_constant_override("separation", 5)
	_order_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(made[1] as VBoxContainer).add_child(_order_row)
	_order_frame = frame
	add_child(frame)


func _build_roster() -> void:
	var made := _panel("Squad")
	var frame: Framed = made[0]
	frame.mouse_filter = Control.MOUSE_FILTER_PASS
	_roster_box = VBoxContainer.new()
	_roster_box.add_theme_constant_override("separation", 4)
	(made[1] as VBoxContainer).add_child(_roster_box)
	frame.custom_minimum_size = Vector2(330, 0)
	_roster_frame = frame
	add_child(frame)


func _build_hint() -> void:
	_hint = _label("", UiTheme.FONT_SMALL, UiTheme.TEXT_DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint)


## Called once by Battle after its own @onready refs have resolved. Takes the
## action buttons and the existing unit panel out of the raw CanvasLayer and
## puts them inside framed furniture. Their node paths are already captured by
## Battle's @onready vars, so reparenting is invisible to every caller.
func adopt(buttons: Array, unit_panel: Control, banner: Control) -> void:
	_banner = banner
	var made := _panel("")
	_bar_frame = made[0]
	_bar_frame.mouse_filter = Control.MOUSE_FILTER_PASS
	_action_row = HBoxContainer.new()
	_action_row.add_theme_constant_override("separation", 6)
	(made[1] as VBoxContainer).add_child(_action_row)
	add_child(_bar_frame)
	for b: Control in buttons:
		if b == null:
			continue
		if b.get_parent() != null:
			b.get_parent().remove_child(b)
		b.set_anchors_preset(Control.PRESET_TOP_LEFT)
		b.offset_left = 0.0
		b.offset_top = 0.0
		b.offset_right = 0.0
		b.offset_bottom = 0.0
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		if b is Button:
			(b as Button).add_theme_font_size_override("font_size", UiTheme.FONT_SMALL)
		_action_row.add_child(b)
	_adopt_inspect(unit_panel)


func _adopt_inspect(unit_panel: Control) -> void:
	if unit_panel == null:
		return
	var made := _panel("Contact")
	_inspect_frame = made[0]
	var col: VBoxContainer = made[1]
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspect_portrait = TextureRect.new()
	_inspect_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_inspect_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_inspect_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var box := PORTRAIT + 16.0
	_inspect_portrait.custom_minimum_size = Vector2(box, box)
	_inspect_portrait.clip_contents = true
	_inspect_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chip := Framed.new()
	chip.bracket = 7.0
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Both of these matter. A PanelContainer in an HBox stretches to the tallest
	# row, and a KEEP_ASPECT_COVERED texture in a box twice as tall as it is
	# wide crops to a vertical slice - which drew the contact's face as a strip
	# of four green pixels. Pinning the size and refusing the vertical expand
	# keeps the chip square whatever the panel beside it does.
	chip.custom_minimum_size = Vector2(box, box)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	chip.add_theme_stylebox_override("panel",
			UiTheme.panel_style(true, UiTheme.EDGE_BRIGHT, 0))
	chip.add_child(_inspect_portrait)
	top.add_child(chip)
	# The five labels Battle already writes into, lifted wholesale. Nothing in
	# Battle._update_unit_panel changed; it just lands somewhere better looking.
	if unit_panel.get_parent() != null:
		unit_panel.get_parent().remove_child(unit_panel)
	unit_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	unit_panel.offset_left = 0.0
	unit_panel.offset_top = 0.0
	unit_panel.offset_right = 0.0
	unit_panel.offset_bottom = 0.0
	unit_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if unit_panel is PanelContainer:
		var flat := StyleBoxFlat.new()
		flat.bg_color = Color(0, 0, 0, 0)
		(unit_panel as PanelContainer).add_theme_stylebox_override("panel", flat)
	# The scene's own font sizes were set for a lone panel in the corner - 29px
	# for the name, 22 for the stat lines. Inside a framed card beside a 62px
	# portrait they shout, and they are the only text on screen bigger than the
	# turn banner. Re-pitched here rather than in the scene so the sizes sit
	# next to the rest of the HUD's.
	var sizes := {"NameLabel": 21, "ProgressLabel": 14, "HpLabel": 16,
			"StatsLabel": 16, "StatusLabel": 16}
	for key: String in sizes:
		var l := unit_panel.find_child(key, true, false) as Label
		if l != null:
			l.add_theme_font_size_override("font_size", int(sizes[key]))
	top.add_child(unit_panel)
	col.add_child(top)
	_inspect_pips = PipRow.new()
	_inspect_pips.group = 5
	_inspect_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_inspect_pips)
	_inspect_frame.custom_minimum_size = Vector2(430, 0)
	add_child(_inspect_frame)


# -------------------------------------------------------------------- refresh

func _process(_delta: float) -> void:
	_layout()
	refresh()


## Panels are positioned in code, and sized here too.
##
## The sizing is the part that is easy to get wrong and did get wrong: these are
## Containers parented to a bare Control, and a Control does NOT lay out its
## children. Left alone every panel stays 0x0 - which does not merely hide them,
## it corrupts the centring, because `(view.x - 0) * 0.5` puts a box that is
## really 700px wide half off the left edge. reset_size() asks each panel for
## the size its contents actually need, and must run BEFORE anything is placed.
func _layout() -> void:
	var view := get_viewport_rect().size
	if view.x <= 0.0 or view.y <= 0.0:
		return
	size = view
	for f: Framed in [_obj_frame, _mission_frame, _order_frame, _roster_frame,
			_inspect_frame, _bar_frame]:
		if f != null and f.visible:
			f.reset_size()
	if _obj_frame != null:
		_obj_frame.position = Vector2(PAD, PAD)
	if _mission_frame != null and _obj_frame != null:
		_mission_frame.position = Vector2(PAD,
				_obj_frame.position.y + _obj_frame.size.y + 10.0)
	if _order_frame != null:
		_order_frame.position = Vector2(roundf((view.x - _order_frame.size.x) * 0.5), PAD)
		if _banner != null:
			# Under the strip rather than at a fixed y: a mission with thirteen
			# defenders makes that panel taller than one with six, and a fixed
			# offset had the banner printed across the enemy portraits.
			var top := _order_frame.position.y + _order_frame.size.y + 10.0
			_banner.offset_top = top
			_banner.offset_bottom = top + 34.0
	if _inspect_frame != null:
		_inspect_frame.position = Vector2(view.x - _inspect_frame.size.x - PAD, PAD)
	if _roster_frame != null:
		_roster_frame.position = Vector2(PAD, view.y - _roster_frame.size.y - PAD - 20.0)
	if _bar_frame != null:
		_bar_frame.position = Vector2(roundf((view.x - _bar_frame.size.x) * 0.5),
				view.y - _bar_frame.size.y - PAD - 20.0)
	if _hint != null:
		_hint.position = Vector2(0, view.y - 22.0)
		_hint.size.x = view.x


func refresh() -> void:
	if battle == null:
		return
	# The results card is only 62% opaque, so without this the whole HUD - five
	# roster cards, the action bar, sixteen portraits - reads straight through
	# the debrief the mission just earned. The briefing is nearly opaque and
	# would have got away with it; both are hidden for the same reason anyway,
	# which is that neither is a moment for a soldier's hit points.
	visible = not (battle.game_over_panel.visible or battle.briefing_panel.visible)
	if not visible:
		return
	_refresh_mission()
	_refresh_order()
	_refresh_roster()
	_refresh_inspect()


## Objectives come from Battle rather than being re-derived here: it already
## walks the objective list to write the old one-line banner, and two places
## computing "how many caches are left" is two places to get it wrong.
func set_objectives(entries: Array) -> void:
	for child in _objectives_box.get_children():
		child.queue_free()
	for entry: Dictionary in entries:
		var done: bool = entry.get("done", false)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mark := _label("[x]" if done else "[ ]", UiTheme.FONT_BODY,
				UiTheme.DONE if done else UiTheme.OBJECTIVE)
		row.add_child(mark)
		var text := _label(str(entry.get("label", "")), UiTheme.FONT_BODY,
				UiTheme.TEXT_DIM if done else UiTheme.TEXT_BRIGHT, true)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		_objectives_box.add_child(row)
		var need := int(entry.get("need", 0))
		if need > 0:
			var bar := PipRow.new()
			bar.total = need
			bar.filled = int(entry.get("have", 0))
			bar.full_color = UiTheme.DONE if done else UiTheme.OBJECTIVE
			# Lighter than the pip default: an objective's UNFILLED segments are
			# the part that matters here - they are the work left - and at the
			# standard empty tone they vanished into the panel.
			bar.empty_color = Color(0.30, 0.26, 0.19, 0.95)
			bar.pip = Vector2(16, 5)
			bar.gap = 3.0
			bar._resize()
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_objectives_box.add_child(bar)


## Soldiers, not everybody wearing the squad's colours.
##
## Freed prisoners are Kind.CIVILIAN on TEAM_SCOUT - they have to be, because
## the extraction objective counts them and the Thirst must not shoot them. So
## the plain team query answers "7 effective" on a five-soldier mission, and
## would have put two unarmed surveyors in the roster with hit points and
## action pips beside Rodar Akai. They are counted where they belong instead:
## on their own mission row, and in the extraction tally Battle already writes.
func _soldiers() -> Array:
	var out: Array = []
	for u: Unit in battle.living_units(Unit.TEAM_SCOUT):
		if u.kind != Unit.Kind.CIVILIAN:
			out.append(u)
	return out


func _stat_row(key: String, value: String, tone := UiTheme.TEXT) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var k := _label(key, UiTheme.FONT_SMALL, UiTheme.TEXT_DIM, true)
	k.custom_minimum_size = Vector2(150, 0)
	row.add_child(k)
	row.add_child(_label(value, UiTheme.FONT_SMALL, tone, true))
	return row


func _refresh_mission() -> void:
	var squad: Array = _soldiers()
	var thirst: Array = battle.living_units(Unit.TEAM_GOBLIN)
	var held: int = battle.captives().size()
	var prisoners: int = battle.level.get("prisoner_spawns", []).size()
	# refresh() runs off _process, so every panel that rebuilds nodes is gated
	# on its own contents changing. Without this the HUD would free and rebuild
	# a few dozen controls sixty times a second to show the same four numbers.
	var sig := "%d/%d/%d/%d/%d/%d" % [battle.turn_number, squad.size(), thirst.size(),
			battle.frags_left, battle.smokes_left, held]
	if sig == _mission_signature:
		return
	_mission_signature = sig
	for child in _mission_box.get_children():
		_mission_box.remove_child(child)
		child.queue_free()
	_mission_box.add_child(_stat_row("Turn", str(battle.turn_number)))
	_mission_box.add_child(_stat_row("Squad", "%d effective" % squad.size(),
			UiTheme.HP_LOW if squad.size() <= 1 else UiTheme.TEXT))
	_mission_box.add_child(_stat_row("Thirst", "%d standing" % thirst.size()))
	if prisoners > 0:
		_mission_box.add_child(_stat_row("Prisoners",
				"%d freed / %d held" % [prisoners - held, held],
				UiTheme.DONE if held == 0 else UiTheme.WARN))
	var ord_row := HBoxContainer.new()
	ord_row.add_theme_constant_override("separation", 8)
	ord_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ok := _label("Ordnance", UiTheme.FONT_SMALL, UiTheme.TEXT_DIM, true)
	ok.custom_minimum_size = Vector2(150, 0)
	ord_row.add_child(ok)
	ord_row.add_child(_label("F", UiTheme.FONT_TINY, UiTheme.WARN))
	var frags := PipRow.new()
	frags.full_color = UiTheme.WARN
	frags.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frags.set_pips(battle.frags_left, maxi(battle.frags_left, Game.frags))
	ord_row.add_child(frags)
	ord_row.add_child(_label("S", UiTheme.FONT_TINY, UiTheme.TEXT_DIM))
	var smokes := PipRow.new()
	smokes.full_color = Color(0.78, 0.80, 0.82)
	smokes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	smokes.set_pips(battle.smokes_left, maxi(battle.smokes_left, Game.smokes))
	ord_row.add_child(smokes)
	_mission_box.add_child(ord_row)


## Squad first, then the Thirst. This is NOT an initiative list and is not
## labelled as one - the game runs every scout, then every goblin, so the strip
## says who is in the fight and who has already acted, which is the question a
## player actually asks it.
func _refresh_order() -> void:
	var cast: Array = _soldiers() + battle.living_units(Unit.TEAM_GOBLIN)
	var sig := ""
	for u: Unit in cast:
		sig += "%d/%s;" % [u.get_instance_id(), u.acted]
	if sig != _order_signature:
		_order_signature = sig
		for child in _order_row.get_children():
			child.queue_free()
		var i := 0
		var side := -1
		for u: Unit in cast:
			# A hard rule between the two sides. Without it sixteen chips read
			# as one queue, and the player has to count colours to find where
			# their own squad stops.
			if side != -1 and u.team != side:
				var split := ColorRect.new()
				split.color = UiTheme.EDGE_BRIGHT
				split.custom_minimum_size = Vector2(1, ORDER_CHIP + 14)
				split.mouse_filter = Control.MOUSE_FILTER_IGNORE
				_order_row.add_child(split)
			side = u.team
			i += 1
			_order_row.add_child(_order_card(u, i))


func _order_card(unit: Unit, index: int) -> Control:
	var friendly := unit.team == Unit.TEAM_SCOUT
	var tint := UiTheme.SQUAD if friendly else UiTheme.ENEMY
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chip := _portrait_chip(unit, ORDER_CHIP, tint)
	if unit.acted:
		chip.modulate = Color(0.55, 0.55, 0.55, 0.8)
	col.add_child(chip)
	var n := _label(str(index), UiTheme.FONT_TINY,
			tint if not unit.acted else UiTheme.TEXT_DIM)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(n)
	return col


func _refresh_roster() -> void:
	var squad: Array = _soldiers()
	var sig := ""
	for u: Unit in squad:
		sig += "%d;" % u.get_instance_id()
	if sig != _roster_signature:
		_roster_signature = sig
		for child in _roster_box.get_children():
			child.queue_free()
		var i := 0
		for u: Unit in squad:
			i += 1
			_roster_box.add_child(_roster_card(u, i))
		return
	# Same cast: repaint the live numbers in place rather than rebuilding
	# fourteen controls a frame.
	var n := 0
	for child in _roster_box.get_children():
		if n >= squad.size():
			break
		_paint_roster_card(child, squad[n])
		n += 1


func _roster_card(unit: Unit, index: int) -> Control:
	var card := Button.new()
	card.focus_mode = Control.FOCUS_NONE
	card.custom_minimum_size = Vector2(0, PORTRAIT + 16)
	card.add_theme_stylebox_override("normal",
			UiTheme.panel_style(true, UiTheme.EDGE, 6))
	card.add_theme_stylebox_override("hover",
			UiTheme.panel_style(true, UiTheme.EDGE_BRIGHT, 6))
	card.add_theme_stylebox_override("pressed",
			UiTheme.panel_style(true, UiTheme.EDGE_HOT, 6))
	card.pressed.connect(func() -> void:
		if battle != null and battle.has_method("select_from_roster"):
			battle.select_from_roster(unit))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 7.0
	row.offset_top = 5.0
	row.offset_right = -7.0
	row.offset_bottom = -5.0
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	row.add_child(_label(str(index), UiTheme.FONT_SMALL, UiTheme.TEXT_DIM))
	row.add_child(_portrait_chip(unit, PORTRAIT, UiTheme.SQUAD))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var name_label := _label(unit.display_name(), UiTheme.FONT_SMALL,
			UiTheme.TEXT_BRIGHT, true)
	name_label.name = "NameLabel"
	col.add_child(name_label)
	var pips := PipRow.new()
	pips.name = "Hp"
	pips.group = 5
	pips.pip = Vector2(7, 6)
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(pips)
	var acts := PipRow.new()
	acts.name = "Acts"
	acts.pip = Vector2(16, 4)
	acts.full_color = UiTheme.SQUAD
	acts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(acts)
	# Held directly rather than looked up by name each repaint: _paint_roster_card
	# runs off _process for every card, and find_child is a tree walk.
	card.set_meta("unit", unit)
	card.set_meta("hp", pips)
	card.set_meta("acts", acts)
	card.set_meta("name_label", name_label)
	_paint_roster_card(card, unit)
	return card


## The two action pips are the closest honest thing this game has to the
## mockup's AP: a soldier holds a move and a shot, and spends them separately.
## can_move() and `acted` are exactly what the rules gate on, so the pips go
## out at the same instant the option does.
func _paint_roster_card(card: Node, unit: Unit) -> void:
	if unit == null or not (card is Control) or not card.has_meta("hp"):
		return
	var hp: PipRow = card.get_meta("hp")
	if hp != null:
		hp.full_color = UiTheme.HP_LOW if unit.hp <= 2 else UiTheme.READY
		hp.set_pips(unit.hp, unit.max_hp)
	var acts: PipRow = card.get_meta("acts")
	if acts != null:
		var left := 0
		if unit.can_move():
			left += 1
		if not unit.acted:
			left += 1
		acts.set_pips(left, 2)
	var selected: Unit = battle.selected if battle != null else null
	(card as Control).modulate = Color(1, 1, 1) if unit == selected \
			else Color(0.82, 0.82, 0.82)
	var name_label: Label = card.get_meta("name_label")
	if name_label != null:
		name_label.add_theme_color_override("font_color",
				UiTheme.WARN if unit == selected else UiTheme.TEXT_BRIGHT)


## The contact card follows the same unit Battle's own panel is describing:
## whatever is under the cursor, else the selection. Battle writes the words;
## this supplies the face and the hit points beside them.
func _refresh_inspect() -> void:
	if _inspect_frame == null:
		return
	var unit: Unit = null
	if battle.hover_cell != Board.NO_CELL:
		unit = battle.unit_at(battle.hover_cell)
	if unit == null:
		unit = battle.selected
	var panel: Control = battle.unit_panel
	_inspect_frame.visible = panel != null and panel.visible and unit != null
	if not _inspect_frame.visible:
		return
	_inspect_frame.edge = UiTheme.ENEMY if unit.team == Unit.TEAM_GOBLIN \
			else UiTheme.SQUAD
	_inspect_portrait.texture = UiTheme.portrait(_face_texture(unit))
	_inspect_pips.full_color = UiTheme.ENEMY if unit.team == Unit.TEAM_GOBLIN \
			else (UiTheme.HP_LOW if unit.hp <= 2 else UiTheme.READY)
	_inspect_pips.set_pips(unit.hp, unit.max_hp)


func set_hint(text: String) -> void:
	if _hint != null:
		_hint.text = text
