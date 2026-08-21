extends Control

## The front door: continue a campaign, start one, or read the notebook.
##
## Deliberately thin. Every decision here is already a decision Game.gd knows
## how to make - has_save(), campaign_summary(), new_campaign(), go_to_camp() -
## so this file is layout, wording, and the one guard that matters: erasing a
## campaign asks first, and says what it is erasing.
##
## The notebook is readable WITHOUT a campaign loaded and without starting one,
## which is the whole reason it is on this screen rather than behind the camp.
## It is the document the game keeps instead of a score, and a document you can
## only reach by playing is a scoreboard with extra steps.

@onready var status_label: Label = $Status
@onready var continue_button: Button = $Buttons/ContinueButton
@onready var new_button: Button = $Buttons/NewButton
@onready var notebook_button: Button = $Buttons/NotebookButton
@onready var quit_button: Button = $Buttons/QuitButton

@onready var notebook_panel: ColorRect = $Notebook
@onready var notebook_lead: Label = $Notebook/NotebookLead
@onready var notebook_body: Label = $Notebook/Scroll/NotebookBody
@onready var notebook_back: Button = $Notebook/NotebookBack

@onready var confirm_panel: ColorRect = $Confirm
@onready var confirm_body: Label = $Confirm/ConfirmBody
@onready var confirm_yes: Button = $Confirm/ConfirmYes
@onready var confirm_no: Button = $Confirm/ConfirmNo

# The settings panel is built in code, the way the battle HUD is: five rows
# that all show one value each are layout the scene file does not need to
# carry, and the Settings button itself rides the existing button column.
var settings_panel: ColorRect = null
var _settings_rows: Dictionary = {}  # setting key -> the Button that shows it


func _ready() -> void:
	# Game's own _ready() has already read the save by the time any scene runs,
	# so what is in memory here IS what is on disk.
	var summary := Game.campaign_summary()
	var has_campaign := Game.has_save() and not summary.is_empty()
	continue_button.disabled = not has_campaign
	status_label.text = summary if has_campaign \
			else "No campaign in progress."
	new_button.text = "New Campaign" if not has_campaign else "New Campaign..."

	continue_button.pressed.connect(_on_continue)
	new_button.pressed.connect(_on_new)
	notebook_button.pressed.connect(_open_notebook)
	quit_button.pressed.connect(_on_quit)
	_build_settings()
	notebook_back.pressed.connect(_close_notebook)
	confirm_yes.pressed.connect(_start_new_campaign)
	confirm_no.pressed.connect(_close_confirm)
	notebook_panel.visible = false
	confirm_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("cancel"):
		return
	if notebook_panel.visible:
		_close_notebook()
	elif settings_panel != null and settings_panel.visible:
		_close_settings()
	elif confirm_panel.visible:
		_close_confirm()


func _on_continue() -> void:
	# in_the_field decides which camp Camp.gd builds, so continuing lands the
	# player exactly where the operation left him.
	Game.go_to_camp()


## Starting over is the one destructive thing this screen can do, so it only
## asks when there is genuinely something to destroy - and it says what.
func _on_new() -> void:
	if continue_button.disabled:
		_start_new_campaign()
		return
	confirm_body.text = ("This will erase the campaign in progress.\n\n%s\n\n"
			+ "%d name%s in the notebook will go with it. There is one save "
			+ "and this cannot be undone.") % [
		Game.campaign_summary(), Game.notebook.size(),
		"" if Game.notebook.size() == 1 else "s",
	]
	confirm_panel.visible = true


func _close_confirm() -> void:
	confirm_panel.visible = false


func _start_new_campaign() -> void:
	if not Game.new_campaign():
		# Refused: the file belongs to a newer build. Say so on the screen the
		# player is looking at rather than only in the console.
		confirm_panel.visible = false
		status_label.text = "The save on disk was written by a newer build - " \
				+ "refusing to overwrite it."
		return
	Game.go_to_camp()


func _on_quit() -> void:
	get_tree().quit()


# ---------------------------------------------------------------- settings --
# What each row is: the setting it drives, the words on it, and how a click
# moves it. Booleans flip; volume walks a five-step ladder, because a slider
# is a lot of widget for a number most players set once.
const SETTING_ROWS := [
	{"key": "volume", "label": "Master volume"},
	{"key": "screen_shake", "label": "Screen shake"},
	{"key": "hit_stop", "label": "Hit-stop on landed shots"},
	{"key": "danger_default", "label": "Danger overlay starts on"},
	{"key": "high_contrast", "label": "High-contrast friendly arcs"},
]
const VOLUME_STEPS := [0, 25, 50, 75, 100]


func _build_settings() -> void:
	var settings_button := Button.new()
	settings_button.text = "Settings"
	settings_button.pressed.connect(_open_settings)
	# Above Quit, below the campaign rows: preferences are not a destination.
	var buttons := quit_button.get_parent()
	buttons.add_child(settings_button)
	buttons.move_child(settings_button, quit_button.get_index())

	settings_panel = ColorRect.new()
	settings_panel.color = Color(0.06, 0.05, 0.04, 0.92)
	settings_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_panel.visible = false
	add_child(settings_panel)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 14)
	settings_panel.add_child(box)
	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	for row: Dictionary in SETTING_ROWS:
		var button := Button.new()
		button.custom_minimum_size = Vector2(420, 0)
		button.pressed.connect(_on_setting_row.bind(str(row.key)))
		box.add_child(button)
		_settings_rows[str(row.key)] = button
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(_close_settings)
	box.add_child(back)


func _open_settings() -> void:
	_refresh_settings_rows()
	settings_panel.visible = true


func _close_settings() -> void:
	settings_panel.visible = false


func _on_setting_row(key: String) -> void:
	if key == "volume":
		var at := VOLUME_STEPS.find(int(Game.setting("volume")))
		Game.set_setting("volume", VOLUME_STEPS[(at + 1) % VOLUME_STEPS.size()])
	else:
		Game.set_setting(key, not bool(Game.setting(key)))
	_refresh_settings_rows()


func _refresh_settings_rows() -> void:
	for row: Dictionary in SETTING_ROWS:
		var key := str(row.key)
		var shown := ""
		if key == "volume":
			shown = "%d%%" % int(Game.setting(key))
		else:
			shown = "ON" if bool(Game.setting(key)) else "OFF"
		(_settings_rows[key] as Button).text = "%s:  %s" % [row.label, shown]


# ---------------------------------------------------------------- notebook --


func _open_notebook() -> void:
	notebook_lead.text = _notebook_lead()
	notebook_body.text = _notebook_text()
	notebook_panel.visible = true


func _close_notebook() -> void:
	notebook_panel.visible = false


func _notebook_lead() -> String:
	if Game.notebook.is_empty():
		return "Nothing written down yet."
	var out_there: int = Game.adversaries.size()
	if out_there == 0:
		return "%d name%s, and the two numbers the theater keeps." % [
			Game.notebook.size(), "" if Game.notebook.size() == 1 else "s"]
	return "%d name%s, %d of them still out there, and the two numbers the theater keeps." % [
		Game.notebook.size(), "" if Game.notebook.size() == 1 else "s", out_there]


## The document, grouped the way the district connects it.
##
## Settlement first, because that is the cross-link that means something: four
## settlements lost their water to the same survey, and this is how much of each
## one the squad has accounted for. Within a settlement the order is the order
## the campaign met them, which is chronological for free - the notebook is
## append-only.
func _notebook_text() -> String:
	if Game.notebook.is_empty():
		return ("The notebook fills as the campaign meets people.\n\n"
				+ "Every fighter the Thirst puts on a map has a name, an age "
				+ "and a settlement, and what becomes of them is written down "
				+ "here afterwards - killed, surrendered, or walked away.")

	var lines: Array[String] = []
	lines.append(_fate_tally())
	lines.append("")

	var by_settlement := Game.notebook_by_settlement()
	var names := by_settlement.keys()
	names.sort()
	for settlement: String in names:
		var entries: Array = by_settlement[settlement]
		lines.append("%s  -  %d, and the Crown's standing here is %d of 100" % [
			settlement.to_upper(), entries.size(), Game.standing_of(settlement)])
		for entry: Dictionary in entries:
			lines.append("    %s" % _entry_line(entry))
		lines.append("")

	lines.append(_still_out_there_text())
	lines.append(_bounties_settled_text())

	lines.append("ALLIANCE STRAIN  %d of 100" % Game.alliance_strain)
	lines.append("Strain has a floor above zero and conduct cannot reach "
			+ "through it. The squad is here whether or not it behaves.")
	return "\n".join(lines)


## What the garrison's posted hunts came to. These were recorded from the
## first bounty on and rendered NOWHERE - a player who turned a man got a
## banner, a stat, and then silence, and the notebook never said the campaign's
## most deliberate choices had happened at all. Same rule as the section above:
## an empty list writes no heading.
func _bounties_settled_text() -> String:
	if Game.bounty_outcomes.is_empty():
		return ""
	var lines: Array[String] = ["BOUNTIES SETTLED  -  %d"
			% Game.bounty_outcomes.size()]
	for entry: Dictionary in Game.bounty_outcomes:
		var what := "shot"
		match str(entry.get("outcome", "")):
			"surrendered":
				what = "brought in"
			"informant":
				what = "turned informant"
		var line := "    %s  -  %s" % [str(entry.get("name", "somebody")), what]
		var hunter := Game.soldier_by_id(int(entry.get("hunter_id", 0)))
		if not hunter.is_empty():
			line += "  (%s)" % Game.soldier_label(hunter)
		lines.append(line)
	lines.append("")
	return "\n".join(lines)


## The ones the campaign failed to account for, and what each of them has
## survived.
##
## The settlement listing above is the document - every name, in the order the
## squad met them, whatever became of them. This is the shorter and more useful
## list: the people who are still alive to be met again, most-storied first, so
## a fighter the squad has failed to finish three times reads as somebody rather
## than as a line in a tally.
##
## Ordered by how much history each one has rather than chronologically,
## because that is the order they matter in - and it is the same order
## Game.adversaries_for offers them back to a mission.
## Most history first. A named function rather than an inline lambda so the
## comparison is one readable line and can be pointed at from a test.
static func _more_history_first(a: Dictionary, b: Dictionary) -> bool:
	return int(a.get("survivals", 0)) > int(b.get("survivals", 0))


func _still_out_there_text() -> String:
	if Game.adversaries.is_empty():
		return ""
	var ranked: Array = Game.adversaries.duplicate()
	ranked.sort_custom(_more_history_first)
	var lines: Array[String] = ["STILL OUT THERE  -  %d" % ranked.size()]
	for rec: Dictionary in ranked:
		lines.append("    %s" % Game.adversary_line(rec))
		var wounds := int(rec.get("injuries", 0))
		if wounds > 0:
			lines.append("        carrying %d wound%s, and still not finished"
					% [wounds, "" if wounds == 1 else "s"])
	lines.append("")
	return "
".join(lines)


func _fate_tally() -> String:
	var counts := {}
	for entry: Dictionary in Game.notebook:
		var fate := str(entry.get("fate", "?"))
		counts[fate] = int(counts.get(fate, 0)) + 1
	var parts: Array[String] = []
	# Fixed order rather than dictionary order, so the tally does not reshuffle
	# itself between campaigns.
	for fate: String in ["killed", "surrendered", "escaped", "injured"]:
		if counts.has(fate):
			parts.append("%d %s" % [int(counts[fate]), fate])
			counts.erase(fate)
	for fate: String in counts:
		parts.append("%d %s" % [int(counts[fate]), fate])
	return "  -  ".join(parts)


func _entry_line(entry: Dictionary) -> String:
	var age := int(entry.get("age", 0))
	var who := str(entry.get("name", "?"))
	if age > 0:
		who += ", %d" % age
	return "%s  -  %s at %s" % [who, entry.get("fate", "?"),
			_mission_name(int(entry.get("level", -1)))]


## Missions are stored by index, so a save that outlives a change to the level
## table must not index off the end of it.
func _mission_name(level: int) -> String:
	if level < 0 or level >= Levels.LEVELS.size():
		return "AN EARLIER MISSION"
	return str(Levels.LEVELS[level].name)
