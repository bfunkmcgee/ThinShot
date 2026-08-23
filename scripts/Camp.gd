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
# Deliberately NOT the full battlefield junk set. `Rusted_desert_garbage_3` is
# the wrecked car door, and two of them were standing in the middle of the
# garrison yard - the base the squad comes home to read as a scrapheap with
# soldiers in it. It stays on the battle maps, where a yard full of stripped
# wreckage is the point; it does not belong in a manned camp. Anything added
# here should pass the same test: would a garrison sergeant leave it lying
# there?
const JUNK_TEXTURES: Array[Texture2D] = [
	preload("res://assets/sprites/Environment/Desert/desert_rusted_garbage/Rusted_desert_garbage.png"),
	preload("res://assets/sprites/Environment/Desert/desert_rusted_garbage/Rusted_desert_garbage_1.png"),
	preload("res://assets/sprites/Environment/Desert/desert_rusted_garbage/Rusted_desert_garbage_2.png"),
]
const PLANT_TEXTURES: Array[Texture2D] = [
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants.png"),
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants_4.png"),
	preload("res://assets/sprites/Environment/Desert/desert_plants/Desert_Plants_9.png"),
]
# The garrison's furniture. Keyed by the name CampData.GARRISON_PROPS uses for
# the cell, and every one of them stands on a 'j' - so they are solid and get
# their contact shadow for free, and none of them needed a rule.
#
# Two canvas classes here, both drawn at PROP_SCALE. The 48px ones are the
# ordinary prop class. The four tall ones are 168px on a SINGLE cell, which is
# the comms mast's trick rather than a structure's: a structure spans a
# footprint and is sliced per column, this is one sprite on one cell that
# simply reaches a long way up. Their offsets follow the mast's rule
# (-(bbox.bottom - 85)) instead of the 48px one (-(bbox.bottom - 26)).
const FIXTURE_ROOT := "res://assets/sprites/Environment/Desert/garrison_fixtures/"
const FIXTURE_TEXTURES := {
	"ammo_box": preload(FIXTURE_ROOT + "Garrison_ammo_box.png"),
	"awning": preload(FIXTURE_ROOT + "Garrison_awning.png"),
	"cleaning_bench": preload(FIXTURE_ROOT + "Garrison_cleaning_bench.png"),
	"field_radio": preload(FIXTURE_ROOT + "Garrison_field_radio.png"),
	"field_stove": preload(FIXTURE_ROOT + "Garrison_field_stove.png"),
	"flagpole": preload(FIXTURE_ROOT + "Garrison_flagpole.png"),
	"jerry_cans": preload(FIXTURE_ROOT + "Garrison_jerry_cans.png"),
	"kit_frame": preload(FIXTURE_ROOT + "Garrison_kit_frame.png"),
	"memorial_cross": preload(FIXTURE_ROOT + "Garrison_memorial_cross.png"),
	"notice_board": preload(FIXTURE_ROOT + "Garrison_notice_board.png"),
	"washing_line": preload(FIXTURE_ROOT + "Garrison_washing_line.png"),
	"watchtower": preload(FIXTURE_ROOT + "Garrison_watchtower.png"),
	"water_bowser": preload(FIXTURE_ROOT + "Garrison_water_bowser.png"),
	"water_tank": preload(FIXTURE_ROOT + "Garrison_water_tank.png"),
}
## Measured off each texture's opaque bounds, so the base sits on the cell.
const FIXTURE_OFFSETS := {
	"ammo_box": Vector2(0, -21),
	"awning": Vector2(0, -65),
	"cleaning_bench": Vector2(0, -21),
	"field_radio": Vector2(0, -21),
	"field_stove": Vector2(0, -21),
	"flagpole": Vector2(0, -72),
	"jerry_cans": Vector2(0, -19),
	"kit_frame": Vector2(0, -21),
	"memorial_cross": Vector2(0, -20),
	"notice_board": Vector2(0, -20),
	"washing_line": Vector2(0, -18),
	"watchtower": Vector2(0, -73),
	"water_bowser": Vector2(0, -22),
	"water_tank": Vector2(0, -63),
}
const WALL_TEX_X_RUN := preload(
		"res://assets/sprites/Environment/Desert/Walls/desert_brick_and_mud/rotations/south-west.png")
const WALL_TEX_Y_RUN := preload(
		"res://assets/sprites/Environment/Desert/Walls/desert_brick_and_mud/rotations/south-east.png")
const WALL_TEX_JUNCTION := preload(
		"res://assets/sprites/Environment/Desert/Walls/desert_brick_and_mud/rotations/north.png")
const CRATE_TEXTURE := preload(
		"res://assets/sprites/Environment/Desert/Props/Pile_of_desert_ammo_crates/Pile_of_desert_ammo_crates/rotations/unknown.png")
# Loose crates for the stores, as opposed to the levy post's stacked
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
# The camps' own canvas is modern military; the Thirst's is not. `tent` is the
# shipped rustic pole tent and three battle levels still place it, where a
# ragged tent on a dispossessed people's ground is the right read - so the
# Kestrel camps get their own kinds rather than the shipped one being swapped
# out from under those levels.
const STRUCTURE_DIRS := {
	"hut_1": STRUCTURE_ROOT + "/desert_hut/Desert_hut",
	"hut_2": STRUCTURE_ROOT + "/desert_hut/Desert_hut_1",
	"tent": STRUCTURE_ROOT + "/desert_hut/Desert_hut_2",
	"stores_tent": STRUCTURE_ROOT + "/camp_tents/Stores_tent",
	"field_tent": STRUCTURE_ROOT + "/camp_tents/Field_tent",
}
const STRUCTURE_OFFSETS := {
	"hut_1": Vector2(0, -22), "hut_2": Vector2(0, -33), "tent": Vector2(0, -33),
	"stores_tent": Vector2(0, -17), "field_tent": Vector2(0, -23),
}
const PROP_DUST := preload("res://assets/shaders/prop_dust.gdshader")
const ROCK_OFFSET := Vector2(0, -18)
const JUNK_OFFSET := Vector2(0, -20)
const PLANT_OFFSET := Vector2(0, -17)
const WALL_OFFSET := Vector2(0, -15)
# The pile, the loose crates and both tables are all nearest-downsampled into
# the 48px class now, so everything standing in camp draws at PROP_SCALE and
# the offsets are halved to match - the painted bases stay on their cells.
const CRATE_OFFSET := Vector2(0, -18)
const STORES_OFFSET := Vector2(0, -12)
# Measured from opaque bounds like every other prop: the painted feet land on
# the cell centre, sunk a pixel so nothing floats.
const BRIEFING_OFFSET_GARRISON := Vector2(0, -23)
const BRIEFING_OFFSET_FIELD := Vector2(0, -20)
const PROP_SCALE := Vector2(2, 2)
# Battle and camp share one zoom so a soldier is the same size on screen at
# home as in the fight: native texel density, where a floor texel is one
# screen pixel. The garrison world (1536x720) fits a 1920x1080 view at 1.0.
const CAMP_ZOOM := Board.MAX_ZOOM

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
@onready var roster_box: VBoxContainer = $UI/Modal/Center/Box/Roster

# The rifle-slot candidates currently listed, parallel to the roster buttons.
# Rebuilt every time the briefing opens, because people die between missions.
var _deploy_candidates: Array = []
@onready var close_button: Button = $UI/Modal/Center/Box/CloseButton

var player: Unit = null
# Seed for the scenery-variant hash streams, mirroring Battle: derived from
# the biome's floor seed via CampData.map_for, so each biome's camp dresses
# itself differently and deterministically.
var _prop_seed := 0
# Which camp this is, and the layout that goes with it.
var in_field := false
var camp: Dictionary = {}
var spots: Dictionary = {}
# [{kind, cell, pos, label, id}] - "soldier" | "briefing" | "stores" | "recruit".
var fixtures: Array = []
var _focus: Dictionary = {}
var _dust_materials: Dictionary = {}
var _swaying: Array = []
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
	board.set_level(camp)
	_prop_seed = int(camp.get("prop_seed",
			int(camp.get("zone_seed", 91)) * 977 + 101))
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
	# Same texel density as the battle: _clamped_camera divides the viewport
	# by zoom, so the clamping adapts on its own.
	camera.zoom = Vector2(CAMP_ZOOM, CAMP_ZOOM)
	_snap_camera()
	print("[Sandline] %s: %d soldier(s), %s mission %d/%d '%s'" % [
			"field camp" if in_field else "garrison", Game.roster.size(),
			Game.operation().name, Game.mission_number(), Game.mission_count(),
			Game.data().name])
	_apply_cmdline_screenshot()


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
	# "On the roster", not "in the squad". Since Phase 3 those are different
	# numbers - eight people, five of whom go - and the camp should not imply
	# the whole of it walks out.
	if pending > 0:
		return "%d on the roster  -  %d awaiting promotion" % [alive, pending]
	return "%d on the roster" % alive


# ------------------------------------------------------------------ scenery --


func _dust_material(cell: Vector2i) -> ShaderMaterial:
	var span := maxi(board.size.x + board.size.y - 2, 1)
	var depth := 1.0 - float(cell.x + cell.y) / float(span)
	var band := clampi(int(depth * float(Board.HAZE_BANDS)), 0, Board.HAZE_BANDS - 1)
	if not _dust_materials.has(band):
		# The camp dresses itself from the operation's biome, so its air has to
		# follow the same ground its floor does.
		var mood := board.floor_mood()
		var mat := ShaderMaterial.new()
		mat.shader = PROP_DUST
		mat.set_shader_parameter("tint", mood.tint)
		mat.set_shader_parameter("haze_color", mood.haze)
		mat.set_shader_parameter("haze",
				Board.HAZE_MAX * (float(band) + 0.5) / float(Board.HAZE_BANDS))
		_dust_materials[band] = mat
	return _dust_materials[band]


func _spawn_prop(texture: Texture2D, offset: Vector2, cell: Vector2i,
		scale := PROP_SCALE, expected := PROP_SCALE) -> Sprite2D:
	# One texel density in camp too: each prop draws at the class its art was
	# authored for - today all 48px-class at 2x. The guard checks the call
	# against its declared class, not a hard-coded 2x, so hi-res 1x art can
	# land per-prop without losing the stray-scale alarm.
	if OS.is_debug_build() and scale != expected:
		push_error("[Camp] prop at %s spawned at %s - normalise the art to the "
				% [cell, scale] + "%s class instead" % expected)
	var prop := Sprite2D.new()
	prop.texture = texture
	prop.offset = offset
	prop.scale = scale
	prop.material = _dust_material(cell)
	prop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	prop.position = board.cell_to_global(cell)
	entities.add_child(prop)
	return prop


# ------------------------------------------------------------ passive motion --
# The camp used to be a still life - the yard held fourteen fixtures and not one
# of them moved. The battlefield already leans its cacti and claim-pennants in
# the wind, so camp borrows that rule rather than inventing a second one: a lean
# of one whole sprite texel, snapped so the pixel art never shimmers between
# subpixel positions, phased off the cell so no two things sway in step.
#
# Only cloth is on the list, and that is the point. A jerrican or an ammunition
# box that drifted sideways would read as a physics bug rather than as weather,
# so the steel half of the yard is deliberately still and the canvas half moves.
const SWAY_SPEED := 1.6      # radians/sec, matching Battle's cycle
const SWAY_TEXELS := 1.0     # sprite texels a thing leans at full sway
const SWAYING_FIXTURES := {
	"awning": true,          # the camo net is the largest cloth in the yard
	"flagpole": true,        # the colours, and the one thing wind is *for*
	"washing_line": true,
	"kit_frame": true,       # webbing and canteens hang loose off the rack
}


## Registers a sprite on the camp's wind. Phase comes from the cell so a given
## yard always sways the same way, and no two neighbours move together.
func _sway(sprite: Sprite2D, cell: Vector2i) -> void:
	_swaying.append({
		"sprite": sprite,
		"base_x": sprite.position.x,
		"phase": Board._hash01(cell, _prop_seed + SALT_SWAY) * TAU,
	})


func _sway_props() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for entry: Dictionary in _swaying:
		var wave: float = sin(t * SWAY_SPEED + entry.phase)
		var step: float = SWAY_TEXELS * PROP_SCALE.x * signf(wave) \
				* (1.0 if absf(wave) > 0.45 else 0.0)
		entry.sprite.position.x = entry.base_x + step


func _wall_texture(cell: Vector2i) -> Texture2D:
	var has_x := board.map_char(cell + Vector2i(1, 0)) == "W" \
			or board.map_char(cell + Vector2i(-1, 0)) == "W"
	var has_y := board.map_char(cell + Vector2i(0, 1)) == "W" \
			or board.map_char(cell + Vector2i(0, -1)) == "W"
	if has_x and has_y:
		return WALL_TEX_JUNCTION
	return WALL_TEX_X_RUN if has_x else WALL_TEX_Y_RUN


## Hash-stream salts, matching Battle's for the streams both scenes have.
const SALT_ROCK := 4
const SALT_JUNK := 5
const SALT_PLANT := 6
const SALT_CRATE := 8
const SALT_SWAY := 9
const SALT_DETRITUS := 12
const SALT_DETRITUS_PICK := 13
const SALT_DETRITUS_JITTER := 14

## Flat ground clutter, on the same terms Battle scatters it: same textures,
## same salts, same rate. The camps stand on the same desert as the missions
## and are dressed from the same prop set, so bare sand here would have been
## the one ground in the game that had nothing on it.
const DETRITUS_ROOT := "res://assets/sprites/Environment/Desert/desert_detritus/"
const DETRITUS_TEXTURES: Array[Texture2D] = [
	preload(DETRITUS_ROOT + "Desert_detritus.png"),
	preload(DETRITUS_ROOT + "Desert_detritus_1.png"),
	preload(DETRITUS_ROOT + "Desert_detritus_2.png"),
	preload(DETRITUS_ROOT + "Desert_detritus_3.png"),
	preload(DETRITUS_ROOT + "Desert_detritus_4.png"),
	preload(DETRITUS_ROOT + "Desert_detritus_5.png"),
	preload(DETRITUS_ROOT + "Desert_detritus_6.png"),
	preload(DETRITUS_ROOT + "Desert_detritus_7.png"),
]
const DETRITUS_RATE := 0.17
const DETRITUS_GAP := 1
const DETRITUS_JITTER := 11.0


## A deterministic pick out of `count` variants for this cell and stream.
func _prop_pick(cell: Vector2i, salt: int, count: int) -> int:
	return mini(int(Board._hash01(cell, _prop_seed + salt) * count), count - 1)


func _spawn_props() -> void:
	for y in board.size.y:
		for x in board.size.x:
			var cell := Vector2i(x, y)
			match board.map_char(cell):
				"#":
					_spawn_prop(ROCK_TEXTURES[_prop_pick(cell, SALT_ROCK,
							ROCK_TEXTURES.size())], ROCK_OFFSET, cell)
				"j":
					# A scrap cell the camp has named becomes that fixture; an
					# unnamed one is still a scrap pile. The garrison names all
					# of its, which is why there is no junk left in it.
					var fixture := str(camp.get("props", {}).get(cell, ""))
					if FIXTURE_TEXTURES.has(fixture):
						var fix := _spawn_prop(FIXTURE_TEXTURES[fixture],
								FIXTURE_OFFSETS[fixture], cell)
						if SWAYING_FIXTURES.has(fixture):
							_sway(fix, cell)
					else:
						if not fixture.is_empty():
							push_error("[Camp] %s names unknown fixture '%s'"
									% [cell, fixture])
						_spawn_prop(JUNK_TEXTURES[_prop_pick(cell, SALT_JUNK,
								JUNK_TEXTURES.size())], JUNK_OFFSET, cell)
				"p":
					# The camp's cacti lean on the same wind the battlefield's do.
					_sway(_spawn_prop(PLANT_TEXTURES[_prop_pick(cell, SALT_PLANT,
							PLANT_TEXTURES.size())], PLANT_OFFSET, cell), cell)
				"W":
					_spawn_prop(_wall_texture(cell), WALL_OFFSET, cell)
	for cell: Vector2i in spots.dressing:
		_spawn_prop(CRATE_TEXTURE, CRATE_OFFSET, cell)
	for s: Dictionary in camp.structures:
		_spawn_structure(s)
	_spawn_detritus()


## Ground clutter over whatever open sand the camp's own fixtures left spare.
## Runs last so the crates, tables and structures have already claimed theirs;
## the walkable spots the player actually interacts with are left clear, since
## a bone under the briefing table would read as something to click on.
func _spawn_detritus() -> void:
	var claimed := {}
	for cell: Vector2i in spots.dressing:
		claimed[cell] = true
	for key: String in spots:
		var value: Variant = spots[key]
		if value is Vector2i:
			claimed[value] = true
	var placed: Array[Vector2i] = []
	for y in board.size.y:
		for x in board.size.x:
			var cell := Vector2i(x, y)
			if board.map_char(cell) != "." or board.is_structure(cell):
				continue
			if claimed.has(cell):
				continue
			if Board._hash01(cell, _prop_seed + SALT_DETRITUS) >= DETRITUS_RATE:
				continue
			var clear := true
			for other: Vector2i in placed:
				if maxi(absi(other.x - cell.x), absi(other.y - cell.y)) <= DETRITUS_GAP:
					clear = false
					break
			if not clear:
				continue
			placed.append(cell)
			var decal := Sprite2D.new()
			decal.texture = DETRITUS_TEXTURES[_prop_pick(cell, SALT_DETRITUS_PICK,
					DETRITUS_TEXTURES.size())]
			decal.material = _dust_material(cell)
			decal.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			decal.position = board.cell_to_local(cell)
			var hx := Board._hash01(cell, _prop_seed + SALT_DETRITUS_JITTER)
			var hy := Board._hash01(cell + Vector2i(97, 61),
					_prop_seed + SALT_DETRITUS_JITTER)
			decal.position += Vector2(
					roundf((hx - 0.5) * 2.0 * DETRITUS_JITTER),
					roundf((hy - 0.5) * DETRITUS_JITTER))
			decal.flip_h = hx > 0.5
			board.decal_layer.add_child(decal)


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


## Who the player walks around as: the chain of command, in order. Rodar Akai
## leads it while he lives (and a lost mission un-kills him, so in camp he
## always does). TEAM_LEAD stays as a fallback for any roster the hero
## migration has not touched; then the machinegunner, then a rifleman, and
## within a role the senior survivor.
const AVATAR_ORDER: Array[int] = [
	Unit.Kind.HERO, Unit.Kind.TEAM_LEAD, Unit.Kind.MACHINEGUNNER, Unit.Kind.SCOUT,
]


func _avatar_soldier() -> Dictionary:
	for kind: int in AVATAR_ORDER:
		var of_kind := Game.soldiers_of_kind(kind)
		if of_kind.is_empty():
			continue
		var best: Dictionary = of_kind[0]
		for soldier: Dictionary in of_kind:
			if int(soldier.get("level", 1)) > int(best.get("level", 1)):
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
			STORES_TEXTURES[_prop_pick(spots.stores, SALT_CRATE,
					STORES_TEXTURES.size())],
			STORES_OFFSET, spots.stores)
	# The duty roster board doubles as the bounty board. Garrison only, and only
	# once the campaign has actually let somebody get away - a board with
	# nothing posted on it is a prompt that wastes a walk.
	#
	# The count is computed once and cached. The offer list cannot change while
	# the player is standing in camp - it moves only when a bounty is settled,
	# and settling one goes through a battle and back through a fresh Camp
	# scene - but _prompt_for used to recompute it EVERY FRAME the player stood
	# near the board: an allocation and a sort per frame to re-learn a number
	# that was decided at _ready.
	if not in_field:
		_bounties_posted = Bounty.offers(Game.campaign_seed, Game.adversaries,
				Game.bounties_done).size()
	if _bounties_posted > 0:
		var board_cell: Vector2i = _fixture_cell("notice_board")
		if board_cell.x >= 0:
			fixtures.append({
				"kind": "bounties", "cell": board_cell,
				"pos": board.cell_to_global(board_cell),
				"label": "the bounty board", "id": 0,
			})
	# The field radio is where interdiction runs are taken: the net over the
	# crossings that would feed the NEXT operation its fighters. Garrison
	# only by construction - the field camp's prop table has no radio - and
	# always present there, unlike the bounty board: the net always has
	# three crossings on it, worked or not.
	if not in_field:
		_ratline_offers = Ratline.offers(Game.campaign_seed,
				Game.current_operation, Game.ratline_done)
		var radio: Vector2i = _fixture_cell("field_radio")
		if radio.x >= 0:
			fixtures.append({
				"kind": "ratline", "cell": radio,
				"pos": board.cell_to_global(radio),
				"label": "the field radio", "id": 0,
			})
	# The ledger is read at the memorial, which is where a campaign keeps
	# what it cannot get back. Garrison only, because the cross is.
	var cross: Vector2i = _fixture_cell("memorial_cross")
	if cross.x >= 0:
		fixtures.append({
			"kind": "ledger", "cell": cross,
			"pos": board.cell_to_global(cross),
			"label": "the ledger", "id": 0,
		})
	# Replacements are a garrison thing. Out on operation the squad fights
	# with whoever walked away from the last mission.
	var post: Vector2i = spots.recruit
	if post.x >= 0:
		fixtures.append({
			"kind": "recruit", "cell": post,
			"pos": board.cell_to_global(post),
			"label": "the levy post", "id": 0,
		})
		_spawn_prop(CRATE_TEXTURE, CRATE_OFFSET, post)
	# The table itself, so the fixture is the thing it is named after rather than
	# a crate standing in for one.
	_spawn_prop(
			BRIEFING_TEX_FIELD if in_field else BRIEFING_TEX_GARRISON,
			BRIEFING_OFFSET_FIELD if in_field else BRIEFING_OFFSET_GARRISON,
			spots.briefing)


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
	# Above the player guard on purpose: the wind is the scene's, not his, so it
	# keeps blowing through the frames where there is nobody to walk around as.
	_sway_props()
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
				return "E  -  levy post: squad at full strength"
			return "E  -  levy post: %d levy/levies available" % short
		"bounties":
			return "E  -  bounty board: %d posted" % _bounties_posted
		"ledger":
			return "E  -  the campaign's ledger"
		"ratline":
			if Game.ratline_strength != 0:
				return "E  -  field radio: the operation is on - the net is closed"
			var open_count := 0
			for offer: Dictionary in _ratline_offers:
				if not bool(offer.get("settled", false)):
					open_count += 1
			return "E  -  field radio: %d crossing(s) on the net" % open_count
	return ""


func _update_prompt() -> void:
	if modal.visible:
		prompt_label.text = ""
		return
	_focus = _nearest_fixture()
	prompt_label.text = "" if _focus.is_empty() else _prompt_for(_focus)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		# Closes whatever is open; from the camp itself it goes back to the
		# front door, which is the only way to reach the notebook mid-campaign.
		# Nothing is lost either way - the campaign is saved as it changes, not
		# on the way out.
		if modal.visible:
			_close_modal()
		else:
			Game.go_to_menu()
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
		"bounties":
			_open_bounties()
		"ledger":
			_open_ledger()
		"ratline":
			_open_ratline()


# ------------------------------------------------------------------ bounties --

## The board, then who goes, then away.
##
## Three panels rather than one, because the choice is genuinely two decisions -
## which man is worth hunting, and who you can spare to hunt him - and folding
## them into one list would hide the interesting half. The middle panel is the
## one that matters: it shows each candidate's PRESENCE and GUILE against the
## odds they would actually face, so choosing a hunter is choosing an approach.
var _bounty_offer: Dictionary = {}
## The three crossings posted this stay, settled flags included - computed
## once at _ready for the same reason _bounties_posted is: the list only
## moves across a battle, and every battle comes back through a fresh Camp.
var _ratline_offers: Array = []
## How many bounties the board is posting, settled once at _ready. The list
## only changes across a battle, and every battle comes back through a fresh
## Camp scene - so a per-visit cache is exact, and the per-frame prompt stops
## paying an allocation and a sort to re-learn it.
var _bounties_posted := 0

## Where a named garrison fixture stands, or (-1, -1). Looked up in the camp's
## own prop table rather than hardcoded, so moving the notice board moves the
## bounty board with it instead of leaving a prompt in an empty patch of sand.
func _fixture_cell(kind: String) -> Vector2i:
	var props: Dictionary = camp.get("props", {})
	for cell: Vector2i in props:
		if str(props[cell]) == kind:
			return cell
	return Vector2i(-1, -1)


func _open_bounties() -> void:
	var posted: Array = Bounty.offers(Game.campaign_seed, Game.adversaries,
			Game.bounties_done)
	if posted.is_empty():
		_open_modal("BOUNTY BOARD",
				"Nothing posted. The Accord pays for the ones who got away, and "
				+ "so far this squad has not let anybody.")
		return
	_bounty_offer = {}
	var lines: Array[String] = ["The Accord pays for these.", ""]
	for i in posted.size():
		var o: Dictionary = posted[i]
		lines.append("%d.  %s of %s" % [i + 1, o.name, o.settlement])
		lines.append("     got away %d time(s)  -  rumoured at %s"
				% [int(o.survivals), o.place])
		lines.append("     %s" % o.where)
		lines.append("")
	lines.append("Pick one and the garrison will post a party.")
	_choice_action = "bounty_pick"
	_choice_args = [posted]
	# Two buttons, so at most the first two are takeable from here. Three are
	# posted because the third is information - what else is out there - and a
	# board that only listed what you could take would be a menu.
	_open_modal("BOUNTY BOARD", "
".join(lines),
			"Take: %s" % str(posted[0].name),
			"Take: %s" % str(posted[1].name) if posted.size() > 1 else "")


## Who to send. Every living named soldier, with what they would actually roll.
func _open_bounty_hunters(offer: Dictionary) -> void:
	_bounty_offer = offer
	var candidates: Array = []
	for soldier: Dictionary in Game.roster:
		if bool(soldier.get("alive", false)):
			candidates.append(soldier)
	if candidates.is_empty():
		_open_modal("NOBODY TO SEND", "There is no one on their feet.")
		return
	var survivals := int(offer.get("survivals", 0))
	var has_band := Rules.can_lead_warband(survivals)
	var lines: Array[String] = [
		"%s of %s, at %s." % [offer.name, offer.settlement, offer.place],
		"He has got away %d time(s)%s." % [survivals,
				" and he does not travel alone" if has_band else ""],
		"",
		"Two riflemen go with whoever you send.",
		"",
	]
	for i in mini(candidates.size(), 2):
		var s: Dictionary = candidates[i]
		var presence := int(s.get("presence", 0))
		var guile := int(s.get("guile", 0))
		lines.append("%s  -  %s" % [Game.soldier_label(s),
				Unit.kind_role_name(int(s.kind))])
		lines.append("   presence %d, guile %d" % [presence, guile])
		lines.append("   talk him down %d%%   turn him %d%%" % [
				Bounty.surrender_chance(presence, survivals, has_band, false),
				Bounty.informant_chance(guile, presence, survivals, has_band,
						not str(offer.get("grievance", "")).is_empty())])
		lines.append("")
	_choice_action = "bounty_send"
	_choice_args = [offer, candidates]
	_open_modal("WHO GOES", "
".join(lines),
			Game.soldier_label(candidates[0]),
			Game.soldier_label(candidates[1]) if candidates.size() > 1 else "")


## The net. Three crossings against the coming operation, what running them
## down is worth, and what ignoring them costs - the projection quoted
## through the same Ratline.strength_line the battle briefing reads, so the
## promise and the season can never disagree.
func _open_ratline() -> void:
	if Game.ratline_strength != 0:
		_open_modal("THE FIELD RADIO",
				"The operation has begun. What crossed, crossed.\n\nAs it stands, %s"
				% Ratline.strength_line(Game.ratline_strength))
		return
	var done := Game.ratline_done.size()
	var lines: Array[String] = [
		"Sillae's set is tuned to the smugglers' band. Three crossings are",
		"feeding the operation the squad is about to fly out on.",
		"",
	]
	var open_offers: Array = []
	for i in _ratline_offers.size():
		var offer: Dictionary = _ratline_offers[i]
		if bool(offer.get("settled", false)):
			lines.append("%d.  %s at %s  -  RUN DOWN" % [i + 1,
					str(offer.title), str(offer.place)])
		else:
			lines.append("%d.  %s at %s" % [i + 1, str(offer.title),
					str(offer.place)])
			lines.append("     %s" % str(offer.where))
			open_offers.append(offer)
		lines.append("")
	lines.append("As it stands, %s" % Ratline.strength_line(
			Ratline.strength(done, Ratline.OFFERS)))
	if done < Ratline.OFFERS:
		lines.append("Run them all down and %s" % Ratline.strength_line(
				Ratline.strength(Ratline.OFFERS, Ratline.OFFERS)))
	if open_offers.is_empty():
		_open_modal("THE FIELD RADIO", "\n".join(lines))
		return
	_choice_action = "ratline_pick"
	_choice_args = [open_offers]
	# Two buttons, the board's own compromise: at most the first two open
	# crossings are takeable from here, and finishing one promotes the third.
	_open_modal("THE FIELD RADIO", "\n".join(lines),
			"Work: %s" % str(open_offers[0].place),
			"Work: %s" % str(open_offers[1].place) if open_offers.size() > 1 else "")


## Who leads the run. No negotiation odds - an interdiction is a gunfight -
## so the panel shows who they are rather than what they would roll.
func _open_ratline_leaders(offer: Dictionary) -> void:
	var candidates: Array = []
	for soldier: Dictionary in Game.roster:
		if bool(soldier.get("alive", false)):
			candidates.append(soldier)
	if candidates.is_empty():
		_open_modal("NOBODY TO SEND", "There is no one on their feet.")
		return
	var lines: Array[String] = [
		"%s at %s - %s." % [str(offer.title).capitalize(), str(offer.place),
				str(offer.where)],
		"",
		"Two riflemen go with whoever you send, and whoever leads sits out",
		"the next mission.",
		"",
	]
	for i in mini(candidates.size(), 2):
		var s: Dictionary = candidates[i]
		lines.append("%s  -  %s, %s" % [Game.soldier_label(s),
				Unit.kind_role_name(int(s.kind)),
				Career.level_label(int(s.get("level", 1)))])
		lines.append("")
	_choice_action = "ratline_send"
	_choice_args = [offer, candidates]
	_open_modal("WHO LEADS", "\n".join(lines),
			Game.soldier_label(candidates[0]),
			Game.soldier_label(candidates[1]) if candidates.size() > 1 else "")


# ------------------------------------------------------------------- modal --


## The war so far, read at the cross. The modal carries the digest; the whole
## document - squad records, the files, the district's opinion, the notebook -
## is written to user://chronicle.txt where the player can keep it.
func _open_ledger() -> void:
	var file := FileAccess.open("user://chronicle.txt", FileAccess.WRITE)
	if file != null:
		file.store_string(Game.chronicle())
		file.close()
	var body := Game.chronicle_digest()
	body += "\n\nThe full ledger is written to user://chronicle.txt."
	_open_modal("THE LEDGER", body)


func _open_modal(title: String, body: String, a := "", b := "") -> void:
	# Only the briefing shows it, and _open_briefing turns it back on after
	# calling this. Everything else - a soldier, the stores, the levy post -
	# gets a clean panel.
	roster_box.visible = false
	choice_a.disabled = false
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
	var to_next := Career.xp_to_next(xp)
	var perks: Array = soldier.perks
	var lines: Array[String] = [
		Unit.kind_role_name(int(soldier.kind)),
		"%s  -  %d xp%s" % [Career.level_label(int(soldier.get("level", 1))), xp,
				"" if to_next < 0 else "  (%d to the next level)" % to_next],
	]
	# The named Kestrels are people the campaign is about, so the tent they are
	# standing in says so. A replacement off the levy post gets his posting.
	if Game.is_named_kestrel(soldier):
		lines.insert(0, Game.full_name(soldier))
	# Sillae Vekh reads the theater back to you. The plan is explicit that she
	# ships with or before Alliance Strain, because a meter with no face is a
	# number - so the number lives in her mouth rather than on a status bar,
	# and what she is willing to say about it is what it costs.
	if str(soldier.get("surname", "")) == "Vekh":
		lines.append("")
		lines.append(_sillae_reads_the_district())
	if bool(soldier.get("wounded", false)):
		lines.append("Walking wounded - a point of HP short until he sits a")
		lines.append("mission out, or the squad makes it home.")
	if perks.is_empty():
		lines.append("No specialty yet.")
	else:
		var names: Array[String] = []
		for perk: String in perks:
			names.append("%s - %s" % [Game.PERKS[perk].name, Game.PERKS[perk].blurb])
		lines.append_array(names)
	# A specialty choice waiting on this soldier turns the record into the
	# choice.
	for promotion: Dictionary in Game.pending_promotions:
		if int(promotion.id) != id:
			continue
		var gate_level := int(promotion.level)
		# The choice comes from this soldier's CLASS tree. _read_promotions
		# already dropped anything the class cannot answer, but a promotion
		# queued in-session for an unexpected kind must not crash the modal.
		var choices: Array = Game.perk_choices(int(soldier.kind),
				Career.perk_gate(gate_level))
		if choices.size() < 2:
			continue
		lines.append("")
		lines.append("REACHED %s - choose a specialty."
				% Career.level_label(gate_level).to_upper())
		_choice_action = "perk"
		_choice_args = [id, gate_level, choices]
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
## a death takes permanently is the levels, the perks and the kills, not the
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
			+ "\n\nThey arrive green - level 1, no specialty, nothing the squad lost.",
			"SIGN THEM ON\nBring the squad back to strength", "")


## What Sillae will tell you about the theater, which is a function of how much
## the theater is willing to tell her.
##
## Her cooperation degrades as Strain climbs (GS1 SS.4). That is not a penalty
## bolted on - it is the interface itself getting worse, so the player reads the
## consequence in the quality of his own intelligence rather than in a bar going
## red. Bands rather than a number, because she is a person and not a gauge.
func _sillae_reads_the_district() -> String:
	var strain: int = Game.alliance_strain
	var worst := ""
	var worst_at := 101
	for settlement: String in Game.district_standing:
		var standing: int = Game.standing_of(settlement)
		if standing < worst_at:
			worst_at = standing
			worst = settlement
	if strain <= 15:
		if worst.is_empty():
			return "\"Nobody out there has an opinion about us yet. Enjoy it.\""
		return "\"%s is the one to watch - they are at %d with us. Everywhere else still talks to me.\"" \
				% [worst, worst_at]
	if strain <= 35:
		if worst.is_empty():
			return "\"People are quieter than they were. Nothing I can point at.\""
		return "\"%s has stopped volunteering things. I can still get an answer if I ask twice.\"" % worst
	if strain <= 60:
		return "\"I am getting told what I already know. Whatever is moving out there, we are hearing it late.\""
	return "\"I have nothing for you. Not nothing to say - nothing given. That is what %d of Strain buys.\"" \
			% strain


## The briefing, and the decision that goes with it: who is walking into it.
##
## The orders and the roster live on the same panel deliberately. Choosing three
## of six is a tactical read of the mission - a rescue wants the medic, a
## demolition wants the breacher - and asking for it on a separate screen with
## the briefing already dismissed would make it a chore instead of a choice.
func _open_briefing() -> void:
	var level: Dictionary = Game.data()
	var op: Dictionary = Game.operation()
	_choice_action = "deploy"
	_choice_args = []
	# The operation, the ground, and the order - not the full briefing. Six
	# roster rows and a button need the room, and Battle reads the whole
	# briefing out again on the first turn, so nothing is lost by not printing
	# it twice. What is here is what the choice below is made on.
	var body := "%s\n\n%s\n\nORDERS:  %s" % [
			op.get("summary", ""), level.get("fiction", ""),
			level.get("orders", "")]
	_open_modal("%s  -  MISSION %d OF %d\n%s" % [
			op.name, Game.mission_number(), Game.mission_count(), level.name],
			body, "DEPLOY", "")
	_build_deployment_rows()


## Fill the roster rows from the living rifle-slot candidates, pre-ticking
## whoever went last time (Game.deployment tops that up if somebody has died).
func _build_deployment_rows() -> void:
	_deploy_candidates = Game.rifle_candidates()
	var going := Game.deployment(_rifle_slots())
	var rows := roster_box.get_children()
	for i in rows.size():
		var row: Button = rows[i]
		row.visible = i < _deploy_candidates.size()
		if not row.visible:
			continue
		var soldier: Dictionary = _deploy_candidates[i]
		row.set_pressed_no_signal(going.has(soldier))
		row.text = _deployment_row_text(soldier, row.button_pressed)
		if not row.toggled.is_connected(_on_deploy_toggled):
			row.toggled.connect(_on_deploy_toggled)
	roster_box.visible = true
	_refresh_deploy_button()


## One line per Kestrel: who, what they do, and what they have learned. Enough
## to choose on without opening five soldier panels first.
## A toggled button in this theme is one shade lighter, which is not enough to
## read at a glance when the decision is which three of six go. The row says it
## in words instead.
func _deployment_row_text(soldier: Dictionary, going: bool) -> String:
	var resting := Game.is_resting(int(soldier.get("id", 0)))
	var parts: Array[String] = [
		# A resting soldier is shown rather than hidden: the player chose to
		# send them on a bounty, and the cost of that choice should be visible
		# on the screen where the next one is made.
		("RESTED" if resting else ("GOING " if going else "      ")),
		"%-14s" % Game.full_name(soldier),
		"%-20s" % Unit.kind_role_name(int(soldier.kind)),
		"%-10s" % Career.level_label(int(soldier.get("level", 1))),
	]
	# The wound rides the row where the deploy decision is made: taking him
	# anyway is allowed and costs a point of HP; the row is what says so.
	if bool(soldier.get("wounded", false)):
		parts.append("WOUNDED -1 HP")
	var perks: Array = soldier.get("perks", [])
	var named: Array[String] = []
	for key: String in perks:
		named.append(str(Game.PERKS[key].name))
	parts.append("-" if named.is_empty() else ", ".join(named))
	return "  ".join(parts)


func _rifle_slots() -> int:
	return Game.data().scout_spawns.size()


func _chosen_ids() -> Array:
	var ids: Array = []
	var rows := roster_box.get_children()
	for i in rows.size():
		var row: Button = rows[i]
		if row.visible and row.button_pressed and i < _deploy_candidates.size():
			ids.append(int(_deploy_candidates[i].id))
	return ids


func _on_deploy_toggled(_pressed: bool) -> void:
	var rows := roster_box.get_children()
	for i in rows.size():
		var row: Button = rows[i]
		if row.visible and i < _deploy_candidates.size():
			row.text = _deployment_row_text(_deploy_candidates[i], row.button_pressed)
	_refresh_deploy_button()


## DEPLOY only lights up on exactly the right number. Fewer would walk into a
## mission short-handed for no reason; more has nowhere to stand.
func _refresh_deploy_button() -> void:
	var slots := _rifle_slots()
	var chosen := _chosen_ids().size()
	choice_a.disabled = chosen != slots
	choice_a.text = "DEPLOY\n%d of %d chosen" % [chosen, slots] if chosen != slots \
			else "DEPLOY\nTake the squad out"


func _on_choice(slot: int) -> void:
	match _choice_action:
		"perk":
			var id: int = int(_choice_args[0])
			var choices: Array = _choice_args[2]
			Game.choose_perk(id, choices[slot])
			# Spend the queued promotion so it is not offered twice.
			for i in Game.pending_promotions.size():
				var p: Dictionary = Game.pending_promotions[i]
				if int(p.id) == id and int(p.level) == int(_choice_args[1]):
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
			print("[Sandline] %d levy/levies reported" % taken.size())
		"bounty_pick":
			var posted: Array = _choice_args[0]
			if slot < posted.size():
				_close_modal()
				_open_bounty_hunters(posted[slot])
		"bounty_send":
			var offer: Dictionary = _choice_args[0]
			var people: Array = _choice_args[1]
			if slot >= people.size():
				return
			var hunter: Dictionary = people[slot]
			# Built here rather than in Game, which may not name Bounty - see
			# the layering note in Bounty.gd. If the generator cannot produce a
			# sound board the bounty is simply refused: an unfinishable map is
			# worse than a bounty that has to be taken again.
			var generated: Dictionary = Bounty.generate(offer, Game.campaign_seed)
			if generated.is_empty():
				_open_modal("NO ROUTE",
						"The rumour does not hold up. Try another posting.")
				return
			Game.begin_bounty(int(hunter.id), int(offer.target_id), generated)
			print("[Sandline] bounty: %s after %s at %s" % [
					Game.full_name(hunter), offer.name, offer.place])
			Game.go_to_battle()
		"ratline_pick":
			var open_offers: Array = _choice_args[0]
			if slot < open_offers.size():
				_close_modal()
				_open_ratline_leaders(open_offers[slot])
		"ratline_send":
			var offer: Dictionary = _choice_args[0]
			var people: Array = _choice_args[1]
			if slot >= people.size():
				return
			var leader: Dictionary = people[slot]
			# Built here rather than in Game, which may not name Ratline - the
			# same layering note as the bounty arm above. A generator that
			# cannot produce a sound board refuses the run; the crossing
			# stays on the net to be taken again.
			var generated: Dictionary = Ratline.generate(offer, Game.campaign_seed)
			if generated.is_empty():
				_open_modal("NO ROUTE",
						"The crossing cannot be found tonight. Try another.")
				return
			Game.begin_interdiction(int(leader.id), int(offer.ordinal), generated)
			print("[Sandline] interdiction: %s against %s at %s" % [
					Game.full_name(leader), str(offer.title), str(offer.place)])
			Game.go_to_battle()
		"deploy":
			# Recorded before the scene changes: Battle reads the choice back
			# out of Game when it fills the rifle slots.
			Game.set_deployment(_chosen_ids())
			print("[Sandline] deploying: %s mission %d/%d" % [
					Game.operation().name, Game.mission_number(), Game.mission_count()])
			Game.go_to_battle()


# -------------------------------------------------------------------- debug --


## Save one settled frame to disk and quit, mirroring Battle's flag:
## `godot --path . -- --field --screenshot out.png`. Windowed only - headless
## runs on a dummy rasterizer that renders nothing.
func _apply_cmdline_screenshot() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--screenshot" and i + 1 < args.size():
			_capture_screenshot(args[i + 1])
			return


func _capture_screenshot(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		push_error("[Sandline] --screenshot needs a window; headless renders nothing")
		get_tree().quit(1)
		return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	print("[Sandline] screenshot -> %s (%s) zoom=%s" % [
			path, "saved" if err == OK else error_string(err), camera.zoom])
	get_tree().quit(0 if err == OK else 1)
