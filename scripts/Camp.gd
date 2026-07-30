extends Node2D

## The base camp: real time, directly controlled, and the campaign's home.
##
## Everything between missions happens here rather than on a game-over overlay.
## Your squad stand around it, you promote them face to face, you set the
## grenade loadout at the stores tent, and you deploy from the briefing table.
##
## Reuses the battle's pieces wholesale: Board draws the ground (with its grid
## switched off), Unit is the avatar and the squad (with its combat HUD
## switched off), and Game holds everything that persists. Nothing here knows
## about turns.

const UNIT_SCENE := preload("res://scenes/Unit.tscn")

# Ground props. These paths are duplicated from Battle rather than shared: the
# two scenes are deliberately independent, and a common prop table is a
# refactor worth doing on its own rather than smuggling into this one.
const ROCK_TEXTURES: Array[Texture2D] = [
	preload("res://assets/sprites/Environment/Desert/Desert_Rock_or_bolder/Rock_1.png"),
	preload("res://assets/sprites/Environment/Desert/Desert_Rock_or_bolder/Rock_2.png"),
	preload("res://assets/sprites/Environment/Desert/Desert_Rock_or_bolder/Rock_3.png"),
	preload("res://assets/sprites/Environment/Desert/Desert_Rock_or_bolder/Rock_4.png"),
	preload("res://assets/sprites/Environment/Desert/Desert_Rock_or_bolder/Rock_5.png"),
	preload("res://assets/sprites/Environment/Desert/Desert_Rock_or_bolder/Rock_6.png"),
	preload("res://assets/sprites/Environment/Desert/Desert_Rock_or_bolder/Rock_7.png"),
	preload("res://assets/sprites/Environment/Desert/Desert_Rock_or_bolder/Rock_8.png"),
]
const JUNK_TEXTURES: Array[Texture2D] = [
	preload("res://assets/sprites/Environment/Desert/desert_rusted_garbage/Rusted_desert_garbage.png"),
	preload("res://assets/sprites/Environment/Desert/desert_rusted_garbage/Rusted_desert_garbage_1.png"),
	preload("res://assets/sprites/Environment/Desert/desert_rusted_garbage/Rusted_desert_garbage_2.png"),
	preload("res://assets/sprites/Environment/Desert/desert_rusted_garbage/Rusted_desert_garbage_3.png"),
]
const PLANT_TEXTURES: Array[Texture2D] = [
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants.png"),
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants_4.png"),
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants_9.png"),
]
const WALL_TEX_X_RUN := preload(
		"res://assets/sprites/Environment/Desert/Walls/desert_brick_and_mud/rotations/south-west.png")
const WALL_TEX_Y_RUN := preload(
		"res://assets/sprites/Environment/Desert/Walls/desert_brick_and_mud/rotations/south-east.png")
const WALL_TEX_JUNCTION := preload(
		"res://assets/sprites/Environment/Desert/Walls/desert_brick_and_mud/rotations/north.png")
const CRATE_TEXTURE := preload(
		"res://assets/sprites/Environment/Desert/Props/Pile_of_desert_ammo_crates/Pile_of_desert_ammo_crates/rotations/unknown.png")
# Loose crates for the stores, as opposed to the assignment post's stacked
# pile. Single crates read as "opened and worked out of" - which is what a
# quartermaster's ground looks like, and what you walk up to here to do.
const STORES_TEXTURES: Array[Texture2D] = [
	preload("res://assets/sprites/Environment/Desert/desert_ammo_crates/Desert_ammo_crate.png"),
	preload("res://assets/sprites/Environment/Desert/desert_ammo_crates/Desert_ammo_crate_1.png"),
	preload("res://assets/sprites/Environment/Desert/desert_ammo_crates/Desert_ammo_crate_2.png"),
]
# The briefing table is the one fixture that differs between the two camps, and
# it is the clearest thing on the ground saying which one you are standing in:
# the garrison has a trestle command table with the radio permanently on it, the
# field camp has whatever folds flat enough to carry to the next mission.
const BRIEFING_TEX_GARRISON := preload(
		"res://assets/sprites/Environment/Desert/Props/Briefing_table/Briefing_table_garrison/rotations/unknown.png")
const BRIEFING_TEX_FIELD := preload(
		"res://assets/sprites/Environment/Desert/Props/Briefing_table/Briefing_table_field/rotations/unknown.png")
const STRUCTURE_ROOT := "res://assets/sprites/Environment/Desert/Structures"
const STRUCTURE_DIRS := {
	"hut_1": STRUCTURE_ROOT + "/desert_hut/Desert_hut",
	"hut_2": STRUCTURE_ROOT + "/desert_hut/Desert_hut_1",
	"tent": STRUCTURE_ROOT + "/desert_hut/Desert_hut_2",
}
const STRUCTURE_OFFSETS := {
	"hut_1": Vector2(0, -22), "hut_2": Vector2(0, -33), "tent": Vector2(0, -33),
}
const PROP_DUST := preload("res://assets/shaders/prop_dust.gdshader")
const ROCK_OFFSET := Vector2(0, -18)
const JUNK_OFFSET := Vector2(0, -20)
const PLANT_OFFSET := Vector2(0, -17)
const WALL_OFFSET := Vector2(0, -15)
const CRATE_OFFSET := Vector2(0, -37)
# Authored at 72px; like the pile and the tables, drawn 1:1.
const STORES_OFFSET := Vector2(0, -23)
# Measured from opaque bounds like every other prop: the painted feet land on
# the cell centre, sunk a pixel so nothing floats. Both tables are authored at
# 96px, so like the crates they are drawn 1:1 rather than at PROP_SCALE.
const BRIEFING_OFFSET_GARRISON := Vector2(0, -46)
const BRIEFING_OFFSET_FIELD := Vector2(0, -40)
const PROP_SCALE := Vector2(2, 2)
const HAZE_BANDS := 5
const HAZE_MAX := 0.20

# Walking speed in screen pixels per second along the horizontal. Vertical is
# squashed to the tile ratio so a step "up" covers the same ground as a step
# right instead of sprinting across rows.
const WALK_SPEED := 168.0
const ISO_SQUASH := 0.469  # Board.TILE_H / Board.TILE_W
# How close the player has to stand before a fixture offers itself.
const INTERACT_RANGE := 74.0

@onready var title_label: Label = $UI/TitleLabel
@onready var board: Board = $Board
@onready var camera: Camera2D = $Camera
@onready var entities: Node2D = $Entities
@onready var subtitle_label: Label = $UI/SubtitleLabel
@onready var prompt_label: Label = $UI/PromptLabel
@onready var modal: ColorRect = $UI/Modal
# Laid out by containers rather than by hand. The panel has to hold anything
# from a one-line "nothing to sign for" to a full operation briefing, and fixed
# offsets sized for the short case let the long case draw straight over itself.
@onready var modal_title: Label = $UI/Modal/Center/Box/TitleLabel
@onready var modal_body: Label = $UI/Modal/Center/Box/BodyLabel
@onready var choice_a: Button = $UI/Modal/Center/Box/Choices/ChoiceAButton
@onready var choice_b: Button = $UI/Modal/Center/Box/Choices/ChoiceBButton
@onready var close_button: Button = $UI/Modal/Center/Box/CloseButton

var player: Unit = null
# Which camp this is, and the layout that goes with it.
var in_field := false
var camp: Dictionary = {}
var spots: Dictionary = {}
# [{kind, cell, pos, label, id}] - "soldier" | "briefing" | "stores" | "recruit".
var fixtures: Array = []
var _focus: Dictionary = {}
var _dust_materials: Dictionary = {}
# What the two modal buttons currently mean, set when a panel is opened.
var _choice_action := ""
var _choice_args: Array = []


func _ready() -> void:
	CampData.validate()
	Levels.validate_all()
	# `godot --path . -- --field` drops straight into the field camp, which is
	# otherwise only reachable by finishing a mission. Mirrors Battle's --level.
	in_field = Game.in_the_field or OS.get_cmdline_user_args().has("--field")
	camp = CampData.map_for(in_field, Game.biome())
	spots = CampData.spots_for(in_field)
	board.show_grid = false  # a camp is a place, not a tactical grid
	board.set_level(camp)
	_spawn_props()
	# The roster forms here on a fresh campaign, before the first mission ever
	# runs, so the squad the player meets in camp is the squad that deploys.
	Game.ensure_roster(Game.data())
	_spawn_squad()
	_build_fixtures()
	close_button.pressed.connect(_close_modal)
	choice_a.pressed.connect(_on_choice.bind(0))
	choice_b.pressed.connect(_on_choice.bind(1))
	modal.visible = false
	title_label.text = "FIELD CAMP" if in_field else "GARRISON"
	_refresh_subtitle()
	_snap_camera()
	print("[ThinShot] %s: %d soldier(s), %s mission %d/%d '%s'" % [
			"field camp" if in_field else "garrison", Game.roster.size(),
			Game.operation().name, Game.mission_number(), Game.mission_count(),
			Game.data().name])


func _refresh_subtitle() -> void:
	var op: Dictionary = Game.operation()
	subtitle_label.text = "%s  -  %s  -  mission %d of %d: %s  -  %s" % [
			op.name, Game.biome().label, Game.mission_number(),
			Game.mission_count(), Game.data().name, _squad_summary()]


func _squad_summary() -> String:
	var alive := 0
	for soldier: Dictionary in Game.roster:
		if bool(soldier.alive):
			alive += 1
	var pending: int = Game.pending_promotions.size()
	if pending > 0:
		return "%d in the squad  -  %d awaiting promotion" % [alive, pending]
	return "%d in the squad" % alive


# ------------------------------------------------------------------ scenery --


func _dust_material(cell: Vector2i) -> ShaderMaterial:
	var span := maxi(board.size.x + board.size.y - 2, 1)
	var depth := 1.0 - float(cell.x + cell.y) / float(span)
	var band := clampi(int(depth * float(HAZE_BANDS)), 0, HAZE_BANDS - 1)
	if not _dust_materials.has(band):
		# The camp dresses itself from the operation's biome, so its air has to
		# follow the same ground its floor does.
		var mood := board.floor_mood()
		var mat := ShaderMaterial.new()
		mat.shader = PROP_DUST
		mat.set_shader_parameter("tint", mood.tint)
		mat.set_shader_parameter("haze_color", mood.haze)
		mat.set_shader_parameter("haze",
				HAZE_MAX * (float(band) + 0.5) / float(HAZE_BANDS))
		_dust_materials[band] = mat
	return _dust_materials[band]


func _spawn_prop(texture: Texture2D, offset: Vector2, cell: Vector2i,
		scale := PROP_SCALE) -> Sprite2D:
	var prop := Sprite2D.new()
	prop.texture = texture
	prop.offset = offset
	prop.scale = scale
	prop.material = _dust_material(cell)
	prop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	prop.position = board.cell_to_global(cell)
	entities.add_child(prop)
	return prop


func _wall_texture(cell: Vector2i) -> Texture2D:
	var has_x := board.map_char(cell + Vector2i(1, 0)) == "W" \
			or board.map_char(cell + Vector2i(-1, 0)) == "W"
	var has_y := board.map_char(cell + Vector2i(0, 1)) == "W" \
			or board.map_char(cell + Vector2i(0, -1)) == "W"
	if has_x and has_y:
		return WALL_TEX_JUNCTION
	return WALL_TEX_X_RUN if has_x else WALL_TEX_Y_RUN


func _spawn_props() -> void:
	for y in board.size.y:
		for x in board.size.x:
			var cell := Vector2i(x, y)
			match board.map_char(cell):
				"#":
					_spawn_prop(ROCK_TEXTURES[(x * 7 + y * 13) % ROCK_TEXTURES.size()],
							ROCK_OFFSET, cell)
				"j":
					_spawn_prop(JUNK_TEXTURES[(x * 11 + y * 17) % JUNK_TEXTURES.size()],
							JUNK_OFFSET, cell)
				"p":
					_spawn_prop(PLANT_TEXTURES[(x * 5 + y * 23) % PLANT_TEXTURES.size()],
							PLANT_OFFSET, cell)
				"W":
					_spawn_prop(_wall_texture(cell), WALL_OFFSET, cell)
	for cell: Vector2i in spots.dressing:
		# Crates are authored at 96px against the 48px everything else uses.
		_spawn_prop(CRATE_TEXTURE, CRATE_OFFSET, cell, Vector2.ONE)
	for s: Dictionary in camp.structures:
		_spawn_structure(s)


func _spawn_structure(s: Dictionary) -> void:
	var anchor: Vector2i = s.anchor
	var size: Vector2i = s.size
	var front: Vector2i = anchor + size - Vector2i.ONE
	var still: String = STRUCTURE_DIRS[s.kind] + "/rotations/unknown.png"
	if not ResourceLoader.exists(still):
		push_error("[Camp] no art for structure '%s'" % s.kind)
		return
	var root := Node2D.new()
	root.position = board.cell_to_global(front)
	var spr := Sprite2D.new()
	spr.texture = load(still)
	spr.scale = PROP_SCALE
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.material = _dust_material(front)
	spr.offset = STRUCTURE_OFFSETS[s.kind]
	spr.position = (board.cell_to_global(anchor) + board.cell_to_global(front)) / 2.0 \
			- root.position
	root.add_child(spr)
	entities.add_child(root)


# -------------------------------------------------------------------- squad --


## Who the player walks around as: the chain of command, in order. Nobody is
## replaced until the operation is over, so the camp has to cope with the Team
## Lead being dead - the machinegunner takes it, then a rifleman, and within a
## role the senior survivor.
const AVATAR_ORDER: Array[int] = [
	Unit.Kind.TEAM_LEAD, Unit.Kind.MACHINEGUNNER, Unit.Kind.SCOUT,
]


func _avatar_soldier() -> Dictionary:
	for kind: int in AVATAR_ORDER:
		var of_kind := Game.soldiers_of_kind(kind)
		if of_kind.is_empty():
			continue
		var best: Dictionary = of_kind[0]
		for soldier: Dictionary in of_kind:
			if int(soldier.rank) > int(best.rank):
				best = soldier
		return best
	# Belt and braces: anyone still standing, if the roster ever holds a role
	# the order above does not name.
	for soldier: Dictionary in Game.roster:
		if bool(soldier.alive):
			return soldier
	return {}


func _make_unit(soldier: Dictionary, cell: Vector2i) -> Unit:
	var unit: Unit = UNIT_SCENE.instantiate()
	entities.add_child(unit)
	unit.setup(int(soldier.get("kind", Unit.Kind.TEAM_LEAD)), cell)
	unit.apply_progression(soldier)
	# Off duty: no pips, no wedge, no rank flashes - just a person and a shadow.
	unit.show_combat_hud = false
	unit.shadow_color = board.shadow_tone(Unit.SHADOW_COLOR.a)
	unit.corpse_shadow_color = board.shadow_tone(Unit.CORPSE_SHADOW_COLOR.a)
	unit.position = board.cell_to_global(cell)
	unit.queue_redraw()
	return unit


func _spawn_squad() -> void:
	var avatar := _avatar_soldier()
	if avatar.is_empty():
		push_error("[Camp] no living soldier to play as")
		return
	player = _make_unit(avatar, spots.player)
	player.set_facing(Vector2(0, 1))  # face the camera at rest
	var slot := 0
	var squad: Array = spots.squad
	for soldier: Dictionary in Game.roster:
		if not bool(soldier.alive) or int(soldier.id) == int(avatar.id):
			continue
		if slot >= squad.size():
			break
		# Distinct cells matter: setup() seeds the idle clock from the cell, so
		# identical cells would have the whole squad breathing in lockstep.
		var cell: Vector2i = squad[slot]
		var unit := _make_unit(soldier, cell)
		unit.set_facing(Vector2(0, 1))
		fixtures.append({
			"kind": "soldier", "cell": cell,
			"pos": board.cell_to_global(cell),
			"label": Game.soldier_label(soldier), "id": int(soldier.id),
		})
		slot += 1


func _build_fixtures() -> void:
	fixtures.append({
		"kind": "briefing", "cell": spots.briefing,
		"pos": board.cell_to_global(spots.briefing),
		"label": "the briefing table", "id": 0,
	})
	fixtures.append({
		"kind": "stores", "cell": spots.stores,
		"pos": board.cell_to_global(spots.stores),
		"label": "the stores tent", "id": 0,
	})
	# The stores had nothing on the ground at all - you walked up to an empty
	# patch of sand and a prompt appeared. Variant keyed off the cell so the
	# two camps do not put out the same crate.
	_spawn_prop(
			STORES_TEXTURES[(spots.stores.x * 5 + spots.stores.y * 3)
					% STORES_TEXTURES.size()],
			STORES_OFFSET, spots.stores, Vector2.ONE)
	# Replacements are a garrison thing. Out on operation the squad fights
	# with whoever walked away from the last mission.
	var post: Vector2i = spots.recruit
	if post.x >= 0:
		fixtures.append({
			"kind": "recruit", "cell": post,
			"pos": board.cell_to_global(post),
			"label": "the assignment post", "id": 0,
		})
		_spawn_prop(CRATE_TEXTURE, CRATE_OFFSET, post, Vector2.ONE)
	# The table itself, so the fixture is the thing it is named after rather than
	# a crate standing in for one.
	_spawn_prop(
			BRIEFING_TEX_FIELD if in_field else BRIEFING_TEX_GARRISON,
			BRIEFING_OFFSET_FIELD if in_field else BRIEFING_OFFSET_GARRISON,
			spots.briefing, Vector2.ONE)


# ----------------------------------------------------------------- movement --


func _walk_input() -> Vector2:
	return Input.get_vector("walk_left", "walk_right", "walk_up", "walk_down")


## Try to move along one axis. Refused if the destination cell is not walkable,
## so running into a wall slides along it instead of sticking.
func _try_step(delta_pos: Vector2) -> void:
	if delta_pos == Vector2.ZERO:
		return
	var candidate := player.position + delta_pos
	var cell := board.global_to_cell(candidate)
	if not board.in_bounds(cell) or not board.is_walkable(cell):
		return
	player.position = candidate
	player.cell = cell


func _process(delta: float) -> void:
	if player == null:
		return
	var dir := Vector2.ZERO if modal.visible else _walk_input()
	if dir != Vector2.ZERO:
		var velocity := Vector2(dir.x, dir.y * ISO_SQUASH).normalized() \
				* WALK_SPEED * Vector2(1.0, ISO_SQUASH)
		# One axis at a time so a wall only blocks the axis that hits it.
		_try_step(Vector2(velocity.x * delta, 0.0))
		_try_step(Vector2(0.0, velocity.y * delta))
		player.set_facing(velocity)
		# start_walking() resets the animation clock, so calling it every frame
		# would freeze the cycle on frame 0.
		if player.anim != Unit.Anim.WALK:
			player.start_walking()
	else:
		player.stop_walking()
	_follow_camera()
	_update_prompt()


# ------------------------------------------------------------------ camera --


## The camp's extent in world space, used to keep the view inside the walls.
func _world_rect() -> Rect2:
	var half_w := Board.TILE_W / 2.0
	var half_h := Board.TILE_H / 2.0
	var min_x := (0 - (board.size.y - 1)) * half_w - half_w
	var max_x := (board.size.x - 1) * half_w + half_w
	var max_y := (board.size.x - 1 + board.size.y - 1) * half_h + half_h
	var origin := board.to_global(Vector2(min_x, -half_h))
	return Rect2(origin, Vector2(max_x - min_x, max_y + half_h))


func _clamped_camera(target: Vector2) -> Vector2:
	var rect := _world_rect()
	var view := get_viewport_rect().size / camera.zoom
	var out := target
	# When the camp is smaller than the view on an axis, centre it instead of
	# clamping to an inverted range.
	if rect.size.x <= view.x:
		out.x = rect.position.x + rect.size.x / 2.0
	else:
		out.x = clampf(out.x, rect.position.x + view.x / 2.0,
				rect.end.x - view.x / 2.0)
	if rect.size.y <= view.y:
		out.y = rect.position.y + rect.size.y / 2.0
	else:
		out.y = clampf(out.y, rect.position.y + view.y / 2.0,
				rect.end.y - view.y / 2.0)
	return out


func _snap_camera() -> void:
	camera.position = _clamped_camera(player.position if player != null else Vector2.ZERO)


func _follow_camera() -> void:
	camera.position = camera.position.lerp(_clamped_camera(player.position), 0.16)


# ------------------------------------------------------------- interaction --


## Your own record, as a fixture. You cannot walk up to yourself, so standing
## clear of everything else selects you - without which a promotion earned by
## whoever the player is walking around as could never be spent at all.
func _self_fixture() -> Dictionary:
	if player == null or player.soldier_id == 0:
		return {}
	return {
		"kind": "soldier", "cell": player.cell, "pos": player.position,
		"label": Game.soldier_label(Game.soldier_by_id(player.soldier_id)),
		"id": player.soldier_id, "is_self": true,
	}


func _nearest_fixture() -> Dictionary:
	var best := {}
	var best_d := INTERACT_RANGE
	for fixture: Dictionary in fixtures:
		var d: float = player.position.distance_to(fixture.pos)
		if d < best_d:
			best_d = d
			best = fixture
	# Nothing else in reach: you are what is selected.
	return _self_fixture() if best.is_empty() else best


func _prompt_for(fixture: Dictionary) -> String:
	match fixture.kind:
		"soldier":
			var mine: bool = bool(fixture.get("is_self", false))
			for promotion: Dictionary in Game.pending_promotions:
				if int(promotion.id) == int(fixture.id):
					return "E  -  take your own promotion" if mine \
							else "E  -  promote %s" % fixture.label
			return "E  -  your record (%s)" % fixture.label if mine \
					else "E  -  speak to %s" % fixture.label
		"briefing":
			return "E  -  orders and deploy"
		"stores":
			return "E  -  stores: %d frag / %d smoke" % [Game.frags, Game.smokes]
		"recruit":
			var short := Game.vacancy_count(Game.data())
			if short <= 0:
				return "E  -  assignment post: squad at full strength"
			return "E  -  assignment post: %d replacement(s) available" % short
	return ""


func _update_prompt() -> void:
	if modal.visible:
		prompt_label.text = ""
		return
	_focus = _nearest_fixture()
	prompt_label.text = "" if _focus.is_empty() else _prompt_for(_focus)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel") and modal.visible:
		_close_modal()
		return
	if not event.is_action_pressed("interact") or modal.visible:
		return
	if _focus.is_empty():
		return
	match _focus.kind:
		"soldier":
			_open_soldier(int(_focus.id))
		"briefing":
			_open_briefing()
		"stores":
			_open_stores()
		"recruit":
			_open_recruit()


# ------------------------------------------------------------------- modal --


func _open_modal(title: String, body: String, a := "", b := "") -> void:
	modal_title.text = title
	modal_body.text = body
	choice_a.text = a
	choice_b.text = b
	choice_a.visible = not a.is_empty()
	choice_b.visible = not b.is_empty()
	modal.visible = true
	player.stop_walking()


func _close_modal() -> void:
	modal.visible = false
	_choice_action = ""
	_choice_args = []
	_refresh_subtitle()


func _open_soldier(id: int) -> void:
	var soldier := Game.soldier_by_id(id)
	if soldier.is_empty():
		return
	var xp: int = int(soldier.xp)
	var to_next := Game.xp_to_next(xp)
	var perks: Array = soldier.perks
	var lines: Array[String] = [
		Unit.kind_role_name(int(soldier.kind)),
		"%s  -  %d xp%s" % [Game.rank_title(int(soldier.rank)), xp,
				"" if to_next < 0 else "  (%d to the next rank)" % to_next],
	]
	if perks.is_empty():
		lines.append("No specialty yet.")
	else:
		var names: Array[String] = []
		for perk: String in perks:
			names.append("%s - %s" % [Game.PERKS[perk].name, Game.PERKS[perk].blurb])
		lines.append_array(names)
	# A promotion waiting on this soldier turns the record into the choice.
	for promotion: Dictionary in Game.pending_promotions:
		if int(promotion.id) != id:
			continue
		var rank := int(promotion.rank)
		var choices: Array = Game.PERK_RANKS[rank]
		lines.append("")
		lines.append("PROMOTED TO %s - choose a specialty." % Game.rank_title(rank).to_upper())
		_choice_action = "perk"
		_choice_args = [id, rank, choices]
		var a: Dictionary = Game.PERKS[choices[0]]
		var b: Dictionary = Game.PERKS[choices[1]]
		_open_modal(Game.soldier_label(soldier), "\n".join(lines),
				"%s\n%s" % [str(a.name).to_upper(), a.blurb],
				"%s\n%s" % [str(b.name).to_upper(), b.blurb])
		return
	_open_modal(Game.soldier_label(soldier), "\n".join(lines))


func _open_stores() -> void:
	_choice_action = "loadout"
	_choice_args = []
	var body := "The squad carries %d pieces of ordnance between them.\n\n" % Game.LOADOUT_SLOTS \
			+ "Carrying %d frag and %d smoke." % [Game.frags, Game.smokes]
	_open_modal("STORES TENT", body,
			"MORE FRAGS\nTake one smoke off the rack", "MORE SMOKE\nPut one frag back")


## Replacements, garrison only. Filling every gap at once is deliberate: what
## a death takes permanently is the rank, the perks and the kills, not the
## campaign - and the squad still fought the rest of the operation short.
func _open_recruit() -> void:
	var short := Game.vacancy_count(Game.data())
	if short <= 0:
		_choice_action = ""
		_open_modal("ASSIGNMENT POST",
				"The squad is at full strength. Nothing to sign for.")
		return
	_choice_action = "recruit"
	_choice_args = []
	var lines: Array[String] = []
	for kind: int in Game.vacancies(Game.data()):
		lines.append("%d x %s" % [int(Game.vacancies(Game.data())[kind]),
				Unit.kind_role_name(kind)])
	_open_modal("ASSIGNMENT POST",
			"Command has bodies to spare, and none of them have done this before.\n\n"
			+ "Open postings:\n" + "\n".join(lines)
			+ "\n\nThey arrive green - no rank, no specialty, nothing the squad lost.",
			"SIGN THEM ON\nBring the squad back to strength", "")


func _open_briefing() -> void:
	var level: Dictionary = Game.data()
	var op: Dictionary = Game.operation()
	_choice_action = "deploy"
	_choice_args = []
	var body := "%s\n\n%s\n\n%s\n\nORDERS:  %s" % [
			op.get("summary", ""), level.get("fiction", ""),
			level.get("briefing", ""), level.get("orders", "")]
	_open_modal("%s  -  MISSION %d OF %d\n%s" % [
			op.name, Game.mission_number(), Game.mission_count(), level.name],
			body, "DEPLOY\nTake the squad out", "")


func _on_choice(slot: int) -> void:
	match _choice_action:
		"perk":
			var id: int = int(_choice_args[0])
			var choices: Array = _choice_args[2]
			Game.choose_perk(id, choices[slot])
			# Spend the queued promotion so it is not offered twice.
			for i in Game.pending_promotions.size():
				var p: Dictionary = Game.pending_promotions[i]
				if int(p.id) == id and int(p.rank) == int(_choice_args[1]):
					Game.pending_promotions.remove_at(i)
					break
			_close_modal()
			_open_soldier(id)
		"loadout":
			Game.set_loadout(Game.frags + (1 if slot == 0 else -1))
			_open_stores()  # reopen so the numbers update in place
		"recruit":
			var taken := Game.recruit_to_strength(Game.data())
			_close_modal()
			# Rebuild the camp so the new faces are actually standing in it.
			get_tree().reload_current_scene()
			print("[ThinShot] %d replacement(s) signed on" % taken.size())
		"deploy":
			print("[ThinShot] deploying: %s mission %d/%d" % [
					Game.operation().name, Game.mission_number(), Game.mission_count()])
			Game.go_to_battle()

