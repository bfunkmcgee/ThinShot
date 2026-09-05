extends Node2D

## THE RANGE - the real-time live-fire drill.
##
## Rodar alone, on a board built from the same tiles and props as the war, with
## his own sprite, against the Thirst arriving in waves. WASD walks, the mouse
## aims, the trigger is the trigger, and nothing here is a turn.
##
## What this scene is made of, and where each piece already lived:
##
##   - The walking is the camp's (Camp.gd): free movement, a wall blocks only
##     the axis that touched it. Facing is the one departure - it follows the
##     mouse, not the feet, which is the whole of a twin-stick controller.
##   - The soldiers are Unit.gd unchanged. Its animation clock is a delta
##     clock, not a turn clock, so raise_rifle / take_damage / play_reload and
##     the walk all just run; the arena never calls the turn-only half
##     (set_done, start_turn) and never touches campaign progression.
##   - The arithmetic is Rules.gd unchanged, plus one number. Every mover's
##     `cell` is kept live, so hit_chance and damage_for read cover, flank,
##     peek and the long-shot rule exactly as the battle does. One thing falls
##     out of that for free and is the mode's best idea: only the fighter
##     Rodar is aiming at is inside his front arc, so the rest are flanking
##     him. Getting surrounded strips your cover here because Rules says so.
##   - The shot is Battle's _fire_round, minus the turn: muzzle, tracer, spark,
##     kick, and a miss that sails past to one side.
##   - The waves are ArenaWaves; the fighters' minds are ArenaFoe.
##
## Self-contained on purpose. It reads Rodar's base stats through Unit.setup()
## and nothing else - no roster, no perks, no gear - then hands him the range's
## own issue (RANGE_* below), and the only thing it ever writes is its own
## best-run file beside the campaign save, never in it.

const UNIT_SCENE := preload("res://scenes/Unit.tscn")
# Camp's prop tables, read off its script at runtime rather than copied: this
# file is not a fourth copy of them for tools/check_prop_tables.gd to police.
# load() not preload(): the parser treats a preloaded script constant as a
# class, and refuses get_script_constant_map() on a class.
const CAMP_SCRIPT_PATH := "res://scripts/Camp.gd"

const ARENA_ZOOM := Board.MAX_ZOOM
# Camp walks him at 168; the range is not a stroll. Quicker than every fighter
# but the light runner (202), who is the one thing that should be able to
# close on him.
const WALK_SPEED := 190.0
const ISO_SQUASH := 0.469  # Camp's
# Semi-automatic: the rifle did not change, the pace of pulling did. ~3.3/s.
const FIRE_INTERVAL := 0.3

## The range's issue. Campaign Rodar is one rifle in a squad of eight with a
## medic behind him; here he is the whole line against a dozen, and a dozen
## rifles at once make Rules' flank arithmetic (cover only faces one way) do
## the enemy's work for them. So the drill kits him accordingly: a veteran's
## constitution, an extended magazine, and rounds that put a Breaker down in
## two. Applied to the arena's own instance in _spawn_player, never to
## Unit.setup(): the campaign's Rodar is not touched by this file.
const RANGE_HP := 14       # campaign 10; 7 well-hand rounds, 2 of the brute's
const RANGE_DAMAGE := 6    # campaign 4; even, so cover still halves it whole
const RANGE_MAG := 6       # campaign 3; a reload every six, not every three
# The rifle comes down this long after the last shot, not after each one -
# Battle's do_volley raises once per volley for the same reason.
const LOWER_AFTER := 1.5
const TRACER_TIME := 0.09  # Battle's
const STRIDE_PX := 48.0    # ground covered between footsteps
const CORPSE_CAP := 12
# The sprite has eight facings; the mouse has 360 degrees. A little margin at
# each sector boundary so a cursor resting on one does not flicker him.
const AIM_HYSTERESIS := 0.12
const RAY_STEP := 0.25     # cells per sample when walking a shot
const CELL_PX := 70.7      # one diagonal step of the grid in screen pixels
const GAME_OVER_DELAY := 1.4
const HIT_STOP_GAP := 0.35  # seconds between kill hit-stops - they never stack
const SAVE_PATH := "user://arena.json"
const SHAKE_OFFSETS: Array[Vector2] = [
	Vector2(4, -2), Vector2(-4, 2), Vector2(3, 1), Vector2(-2, -1), Vector2.ZERO,
]

@onready var board: Board = $Board
@onready var camera: Camera2D = $Camera
@onready var entities: Node2D = $Entities
@onready var title_label: Label = $UI/TitleLabel
@onready var subtitle_label: Label = $UI/SubtitleLabel
@onready var banner: Label = $UI/Banner
@onready var ammo_label: Label = $UI/AmmoLabel
@onready var prompt_label: Label = $UI/PromptLabel
@onready var game_over_panel: ColorRect = $UI/GameOver
@onready var readout_label: Label = $UI/GameOver/ReadoutLabel
@onready var again_button: Button = $UI/GameOver/AgainButton
@onready var menu_button: Button = $UI/GameOver/MenuButton

var player: Unit = null
var foes: Array[Unit] = []
var foe_states: Dictionary = {}   # Unit -> ArenaFoe state dict
var corpses: Array[Unit] = []
var waves: ArenaWaves = null
# The arena's own generator. Nothing here is campaign state, so nothing here
# has to be a hash of the campaign seed; the run's seed is printed and shown
# so a run can still be talked about afterwards.
var rng := RandomNumberGenerator.new()
var run_seed := 0
var kills := 0
var game_over := false

var fx_ground: Fx = null
var fx_air: Fx = null
var fx_glow: Fx = null
var _camp: Dictionary = {}
var _prop_seed := 0
var _swaying: Array = []

var _moving := false
var _fire_cooldown := 0.0
var _since_shot := 99.0
var _reloading := false
var _stride := 0.0
var _step_parity := 0
var _prompt_until := 0.0

var _cam_lean := Vector2.ZERO
var _cam_shake := Vector2.ZERO
var _shake_tween: Tween = null
var _kick_tween: Tween = null
var _banner_tween: Tween = null
var _hit_stop_cooldown := 0.0


func _ready() -> void:
	ArenaData.validate()
	var camp_script: GDScript = load(CAMP_SCRIPT_PATH)
	_camp = camp_script.get_script_constant_map()
	board.set_level(ArenaData.RANGE)
	_prop_seed = ArenaData.PROP_SEED
	_setup_fx_layers()
	_spawn_props()
	ApronScenery.spawn(board, entities, ArenaData.RANGE, _prop_seed)
	rng.randomize()
	run_seed = int(rng.seed)
	_spawn_player()
	waves = ArenaWaves.new()
	add_child(waves)
	waves.setup(self, rng)
	waves.wave_started.connect(_on_wave_started)
	waves.wave_cleared.connect(_on_wave_cleared)
	waves.breather_started.connect(_on_breather)
	again_button.pressed.connect(_again)
	menu_button.pressed.connect(Game.go_to_menu)
	game_over_panel.visible = false
	banner.modulate.a = 0.0
	camera.zoom = Vector2(ARENA_ZOOM, ARENA_ZOOM)
	_snap_camera()
	_refresh_hud()
	print("[Sandline] the range: run seed %d" % run_seed)


# ------------------------------------------------------------------ setup --


## Battle's three particle layers, minus the objective marks.
func _setup_fx_layers() -> void:
	fx_ground = Fx.new()
	fx_ground.z_index = -1
	add_child(fx_ground)
	move_child(fx_ground, board.get_index() + 1)
	fx_air = Fx.new()
	add_child(fx_air)
	fx_glow = Fx.new()
	var glow_material := CanvasItemMaterial.new()
	glow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	fx_glow.material = glow_material
	fx_glow.z_index = 15
	add_child(fx_glow)
	fx_air.set_ambient(_world_rect().grow(90.0), 26, Vector2(-34.0, 11.0))


func _pick(cell: Vector2i, salt: int, count: int) -> int:
	return mini(int(Board._hash01(cell, _prop_seed + salt) * count), count - 1)


## The range's rocks, scrap and scrub, off the camp's own tables.
func _spawn_props() -> void:
	var rocks: Array = _camp.ROCK_TEXTURES
	var junk: Array = _camp.JUNK_TEXTURES
	var plants: Array = _camp.PLANT_TEXTURES
	for y in board.size.y:
		for x in board.size.x:
			var cell := Vector2i(x, y)
			match board.map_char(cell):
				"#":
					_spawn_prop(rocks[_pick(cell, int(_camp.SALT_ROCK), rocks.size())],
							_camp.ROCK_OFFSET, cell)
				"j":
					_spawn_prop(junk[_pick(cell, int(_camp.SALT_JUNK), junk.size())],
							_camp.JUNK_OFFSET, cell)
				"p":
					var plant := _spawn_prop(plants[_pick(cell, int(_camp.SALT_PLANT),
							plants.size())], _camp.PLANT_OFFSET, cell)
					_swaying.append({
						"sprite": plant,
						"base_x": plant.position.x,
						"phase": Board._hash01(cell, _prop_seed + int(_camp.SALT_SWAY)) * TAU,
					})


func _spawn_prop(texture: Texture2D, offset: Vector2, cell: Vector2i) -> Sprite2D:
	var prop := Sprite2D.new()
	prop.texture = texture
	prop.offset = offset
	prop.scale = _camp.PROP_SCALE
	prop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	prop.position = board.cell_to_global(cell)
	entities.add_child(prop)
	return prop


func _sway_props() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var speed := float(_camp.SWAY_SPEED)
	var texels := float(_camp.SWAY_TEXELS) * (_camp.PROP_SCALE as Vector2).x
	for entry: Dictionary in _swaying:
		var wave: float = sin(t * speed + entry.phase)
		var step: float = texels * signf(wave) * (1.0 if absf(wave) > 0.45 else 0.0)
		entry.sprite.position.x = entry.base_x + step


func _make_unit(kind: int, cell: Vector2i) -> Unit:
	var unit: Unit = UNIT_SCENE.instantiate()
	entities.add_child(unit)
	unit.setup(kind, cell)
	# A game piece here, unlike the camp: pips over everybody's head.
	unit.show_combat_hud = true
	unit.shadow_color = board.shadow_tone(Unit.SHADOW_COLOR.a)
	unit.corpse_shadow_color = board.shadow_tone(Unit.CORPSE_SHADOW_COLOR.a)
	unit.position = board.cell_to_global(cell)
	unit.queue_redraw()
	return unit


## Rodar at base stats plus the range's issue. No apply_progression: the
## drill is the same drill for every campaign, which is what makes a best run
## mean anything.
func _spawn_player() -> void:
	player = _make_unit(Unit.Kind.HERO, ArenaData.PLAYER_SPAWN)
	player.max_hp = RANGE_HP
	player.hp = RANGE_HP
	player.damage = RANGE_DAMAGE
	player.mag_size = RANGE_MAG
	player.ammo = RANGE_MAG
	player.queue_redraw()
	player.died.connect(_on_player_died)
	player.wounded.connect(_on_player_wounded)


## Called by the wave director. Returns the fighter so a test can hold it.
func spawn_foe(kind: int, cell: Vector2i) -> Unit:
	var unit := _make_unit(kind, cell)
	unit.died.connect(_on_foe_died)
	foes.append(unit)
	foe_states[unit] = ArenaFoe.new_state(rng)
	fx_ground.footstep(unit.position, 1.0)
	return unit


## Whoever is standing on a cell, alive. Linear over a dozen fighters.
func unit_at(cell: Vector2i) -> Unit:
	if player != null and player.is_alive() and player.cell == cell:
		return player
	for foe in foes:
		if foe.is_alive() and foe.cell == cell:
			return foe
	return null


# ----------------------------------------------------------------- frame --


func _process(delta: float) -> void:
	_sway_props()
	camera.offset = _cam_lean + _cam_shake
	_hit_stop_cooldown = maxf(_hit_stop_cooldown - delta, 0.0)
	if Input.is_action_just_pressed("cancel"):
		Game.go_to_menu()
		return
	if game_over or player == null:
		_follow_camera()
		return
	_fire_cooldown -= delta
	_since_shot += delta
	_move_player(delta)
	_aim_player()
	_stance_player()
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_try_fire()
	if Input.is_action_just_pressed("reload"):
		_try_reload()
	for foe in foes.duplicate():
		if foe_states.has(foe):
			ArenaFoe.tick(self, foe, foe_states[foe], delta)
	_follow_camera()
	_refresh_hud()


# ---------------------------------------------------------------- player --


func _walk_input() -> Vector2:
	return Input.get_vector("walk_left", "walk_right", "walk_up", "walk_down")


## Camp's step: refused if the destination cell is not walkable, so running
## into a wall slides along it instead of sticking.
func _try_step(delta_pos: Vector2) -> void:
	if delta_pos == Vector2.ZERO:
		return
	var candidate := player.position + delta_pos
	var cell := board.global_to_cell(candidate)
	if not board.in_bounds(cell) or not board.is_walkable(cell):
		return
	player.position = candidate
	player.cell = cell


func _move_player(delta: float) -> void:
	if not player.is_alive():
		_moving = false
		return
	var dir := _walk_input()
	_moving = dir != Vector2.ZERO
	if not _moving:
		if player.anim == Unit.Anim.WALK:
			player.stop_walking()
		return
	var velocity := Vector2(dir.x, dir.y * ISO_SQUASH).normalized() \
			* WALK_SPEED * Vector2(1.0, ISO_SQUASH)
	var before := player.position
	# One axis at a time so a wall only blocks the axis that hits it.
	_try_step(Vector2(velocity.x * delta, 0.0))
	_try_step(Vector2(0.0, velocity.y * delta))
	_stride += player.position.distance_to(before)
	if _stride >= STRIDE_PX:
		_stride -= STRIDE_PX
		_step_parity ^= 1
		Sfx.play("footstep_1" if _step_parity == 0 else "footstep_2")
		fx_ground.footstep(player.position, 0.6)
	# start_walking() resets the cycle, so only on the transition - and never
	# over a reload or a flinch, which finish on their own.
	match player.anim:
		Unit.Anim.IDLE, Unit.Anim.IDLE_ALT, Unit.Anim.AIM_IDLE, \
		Unit.Anim.RAISE, Unit.Anim.LOWER:
			player.start_walking()


## The sprite turns to the mouse, eight ways, with a margin at each boundary.
func _aim_player() -> void:
	if not player.is_alive():
		return
	var d := get_global_mouse_position() - player.position
	if d.length_squared() < 16.0:
		return
	var angle := d.angle()
	var sector := wrapi(roundi(angle / (TAU / 8.0)), 0, 8)
	if sector == player.facing_sector:
		return
	var centre := player.facing_sector * TAU / 8.0
	if absf(angle_difference(angle, centre)) > TAU / 16.0 + AIM_HYSTERESIS:
		player.set_facing_sector(sector)


## Rifle up while he has been shooting lately, down when he has not - and
## never re-raised per shot, which would cap the fire rate at the animation.
func _stance_player() -> void:
	if _moving or not player.is_alive():
		return
	var up := _since_shot < LOWER_AFTER
	match player.anim:
		Unit.Anim.IDLE, Unit.Anim.IDLE_ALT:
			if up:
				player.raise_rifle()
		Unit.Anim.AIM_IDLE, Unit.Anim.RAISE:
			if not up:
				player.lower_rifle()


func _try_fire() -> void:
	if not player.is_alive() or _fire_cooldown > 0.0 or _reloading:
		return
	if player.needs_reload():
		_fire_cooldown = 0.25
		_flash_prompt("R  -  RELOAD")
		return
	_fire_cooldown = FIRE_INTERVAL
	_since_shot = 0.0
	var dir := (get_global_mouse_position() - player.position).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	player.spend_ammo()
	_shoot(player, dir, _moving)


func _try_reload() -> void:
	if _reloading or not player.is_alive() or player.mag_size == 0 \
			or player.ammo >= player.mag_size:
		return
	_reloading = true
	var cycle: Array = player.reload_frames[player.facing_sector]
	# The animation's own length, off the frames that ship.
	var seconds := float(maxi(cycle.size(), 1)) / Unit.RELOAD_FPS
	Sfx.play("reload")
	player.play_reload()
	await get_tree().create_timer(seconds + 0.05).timeout
	if is_instance_valid(player) and player.is_alive():
		player.reload()
	_reloading = false


# ------------------------------------------------------------------ shots --


## A fighter's trigger pull, from ArenaFoe. He faces the man and fires.
func foe_fire(unit: Unit) -> void:
	if player == null or not player.is_alive() or not unit.is_alive():
		return
	var dir := (player.position - unit.position).normalized()
	unit.set_facing(dir)
	unit.spend_ammo()
	_shoot(unit, dir, false)


## Walk the shot out from the shooter's cell along the aim, a quarter of a
## cell at a time, the way Board.has_line_of_sight samples: the first wall
## stops it, the first living enemy in its path is the target. Nothing in the
## path and the round carries to the end of the weapon's reach.
func _trace(attacker: Unit, dir: Vector2) -> Dictionary:
	var fx := dir.x / (Board.TILE_W / 2.0)
	var fy := dir.y / (Board.TILE_H / 2.0)
	var cdir := Vector2((fx + fy) / 2.0, (fy - fx) / 2.0)
	if cdir.length_squared() < 0.000001:
		cdir = Vector2(1, 0)
	cdir = cdir.normalized()
	var origin := Vector2(attacker.cell)
	var max_t := float(attacker.attack_range) + 0.5
	var last := attacker.cell
	var t := RAY_STEP
	while t <= max_t:
		var p := origin + cdir * t
		var cell := Vector2i(roundi(p.x), roundi(p.y))
		t += RAY_STEP
		if cell == attacker.cell or cell == last:
			continue
		last = cell
		if not board.in_bounds(cell):
			break
		if board.is_blocker(cell):
			return {"target": null, "impact": board.cell_to_global(cell) + Vector2(0, -24)}
		var u := unit_at(cell)
		if u != null and u != attacker and u.is_alive() and u.team != attacker.team:
			return {"target": u, "impact": u.position}
	return {"target": null, "impact": attacker.position + dir * (max_t * CELL_PX)}


## One round leaving a muzzle: Battle's _fire_round without the turn around
## it. The roll and the damage are settled before the tracer flies, so what
## the round does and what it looks like doing it are one shot.
func _shoot(attacker: Unit, dir: Vector2, moving: bool) -> void:
	var muzzle := attacker.muzzle_point()
	var found := _trace(attacker, dir)
	var target: Unit = found.target
	var impact: Vector2 = found.impact
	var landed := false
	var dmg := 0
	if target != null:
		var chance := Rules.arena_hit_chance(board, attacker, target, moving)
		landed = Rules.roll_hits(rng, chance)
		var chest := target.position + Vector2(0, -36)
		# A miss sails past the target and off to one side.
		impact = chest if landed else chest + dir * 54.0 \
				+ dir.orthogonal() * rng.randf_range(-34.0, 34.0)
		if landed:
			dmg = Rules.damage_for(board, attacker, target)
	attacker.recoil(dir)
	# The brute's "shot" is a hammer coming down; no flash leaves a hammer.
	var maul := attacker.kind == Unit.Kind.GOBLIN_BRUTE
	if not maul:
		Sfx.play("shot")
		HitFx.spawn(fx_glow, muzzle, HitFx.Kind.MUZZLE)
		HitFx.spawn_tracer(fx_glow, muzzle, impact, TRACER_TIME)
		fx_glow.muzzle(muzzle, dir)
		fx_air.smoke_plume(muzzle, dir)
		fx_ground.casing(muzzle, dir)
	if attacker == player:
		_camera_kick(dir)
	await get_tree().create_timer(TRACER_TIME).timeout
	if target == null or not landed:
		if not maul:
			Sfx.play("miss")
		var strike := impact + Vector2(0, 30)
		fx_ground.footstep(strike, 1.2)
		fx_ground.bullet_hole(strike, dir)
		if target != null and is_instance_valid(target):
			target.spawn_miss_text()
		return
	if not is_instance_valid(target) or not target.is_alive():
		return
	var at := target.position + Vector2(0, -36)
	var lethal := target.hp - dmg <= 0
	Sfx.play("hit_impact")
	HitFx.spawn(fx_glow, at, HitFx.Kind.IMPACT)
	fx_glow.impact(at, dir, lethal)
	fx_air.blood_mist(at, dir, lethal)
	target.take_damage(dmg, dir)


# ------------------------------------------------------------------ deaths --


func _on_foe_died(unit: Unit) -> void:
	kills += 1
	foes.erase(unit)
	foe_states.erase(unit)
	corpses.append(unit)
	waves.on_foe_died()
	Sfx.play("unit_death")
	fx_ground.death_puff(unit.position)
	# One hit-stop at a time. Battle awaits each; the range gets a cooldown
	# instead, because two fighters can drop in the same frame here.
	if _hit_stop_cooldown <= 0.0:
		_hit_stop_cooldown = HIT_STOP_GAP
		_hit_stop(0.2, 0.05)
	# The battle keeps every corpse because a mission ends. This does not, so
	# the oldest fade once the ground gets crowded.
	while corpses.size() > CORPSE_CAP:
		var old: Unit = corpses.pop_front()
		if is_instance_valid(old):
			var tween := old.create_tween()
			tween.tween_property(old, "modulate:a", 0.0, 0.6)
			tween.tween_callback(old.queue_free)


func _on_player_wounded(_unit: Unit) -> void:
	_screen_shake(1.4)


func _on_player_died(_unit: Unit) -> void:
	if game_over:
		return
	game_over = true
	Sfx.play("lose")
	var held: int = waves.wave if waves.in_breather else waves.wave - 1
	held = maxi(held, 0)
	var best := _save_run(held, kills)
	await get_tree().create_timer(GAME_OVER_DELAY).timeout
	readout_label.text = "Waves held: %d\nThirst put down: %d\n\nBest run: wave %d held, %d put down\nRun seed %d" % [
			held, kills, int(best.best_wave), int(best.best_kills), run_seed]
	game_over_panel.visible = true


func _again() -> void:
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


# ------------------------------------------------------------------- waves --


func _on_wave_started(wave: int, _count: int) -> void:
	title_label.text = "THE RANGE  -  WAVE %d" % wave
	show_banner("WAVE %d" % wave)


func _on_wave_cleared(_wave: int) -> void:
	show_banner("LINE HELD")


## The breather: a fresh magazine, the wounds seen to, a moment to breathe.
## Each string of the drill starts whole - the fight is the wave in front of
## him, not the arithmetic of what the last one left.
func _on_breather(_seconds: float) -> void:
	if player == null or not player.is_alive():
		return
	if not _reloading:
		player.reload()
	player.hp = player.max_hp
	player.queue_redraw()


# --------------------------------------------------------------------- hud --


func _refresh_hud() -> void:
	subtitle_label.text = "%d put down" % kills if kills > 0 else "live fire"
	if player.mag_size > 0:
		ammo_label.text = "ROUNDS  %d / %d" % [player.ammo, player.mag_size]
	var now := Time.get_ticks_msec() / 1000.0
	if now < _prompt_until:
		return
	prompt_label.text = "R  -  RELOAD" if player.needs_reload() and not _reloading else ""


func _flash_prompt(text: String) -> void:
	prompt_label.text = text
	_prompt_until = Time.get_ticks_msec() / 1000.0 + 0.8


## Battle's banner, with a fade-out so the range never keeps a heading up.
func show_banner(text: String) -> void:
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	banner.text = text
	banner.modulate.a = 0.0
	banner.pivot_offset = banner.size / 2.0
	banner.scale = Vector2(1.25, 1.25)
	_banner_tween = create_tween()
	_banner_tween.tween_property(banner, "modulate:a", 1.0, 0.2)
	_banner_tween.parallel().tween_property(banner, "scale", Vector2.ONE, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_interval(1.4)
	_banner_tween.tween_property(banner, "modulate:a", 0.0, 0.4)


# ------------------------------------------------------------------ camera --


## Camp's follow with Battle's kick and shake on the offset channel; the two
## never wrote the same property, so they compose.
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
	if rect.size.x <= view.x:
		out.x = rect.position.x + rect.size.x / 2.0
	else:
		out.x = clampf(out.x, rect.position.x + view.x / 2.0, rect.end.x - view.x / 2.0)
	if rect.size.y <= view.y:
		out.y = rect.position.y + rect.size.y / 2.0
	else:
		out.y = clampf(out.y, rect.position.y + view.y / 2.0, rect.end.y - view.y / 2.0)
	return out


func _snap_camera() -> void:
	camera.position = _clamped_camera(player.position if player != null else Vector2.ZERO)


func _follow_camera() -> void:
	if player == null:
		return
	camera.position = camera.position.lerp(_clamped_camera(player.position), 0.16)


func _screen_shake(strength := 1.0) -> void:
	if not bool(Game.setting("screen_shake")):
		return
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	var gain := strength / maxf(camera.zoom.x, 0.01)
	_shake_tween = create_tween()
	for off in SHAKE_OFFSETS:
		_shake_tween.tween_property(self, "_cam_shake", off * gain, 0.03)


func _camera_kick(dir: Vector2) -> void:
	if not bool(Game.setting("screen_shake")):
		return
	if _kick_tween != null and _kick_tween.is_valid():
		_kick_tween.kill()
	_cam_lean = -dir * 5.0 / maxf(camera.zoom.x, 0.01)
	_kick_tween = create_tween()
	_kick_tween.tween_property(self, "_cam_lean", Vector2.ZERO, 0.16) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Battle's hit-stop: real seconds, restore bound to the Engine so a scene
## change mid-freeze can never strand the game slow.
func _hit_stop(scale: float, real_seconds: float) -> void:
	if not bool(Game.setting("hit_stop")):
		return
	Engine.time_scale = scale
	var timer := get_tree().create_timer(real_seconds, true, false, true)
	timer.timeout.connect(Engine.set_time_scale.bind(1.0))


# -------------------------------------------------------------- best run --


## The mode's own file, beside the campaign save and never inside it.
func _load_best() -> Dictionary:
	var blank := {"best_wave": 0, "best_kills": 0, "runs": 0}
	if not FileAccess.file_exists(SAVE_PATH):
		return blank
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return blank
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if typeof(parsed) == TYPE_DICTIONARY else blank


## Game.save()'s shape: write beside, then rename over, so a crash mid-write
## leaves the old best rather than half a file.
func _save_run(held: int, put_down: int) -> Dictionary:
	var best := _load_best()
	best.best_wave = maxi(int(best.get("best_wave", 0)), held)
	best.best_kills = maxi(int(best.get("best_kills", 0)), put_down)
	best.runs = int(best.get("runs", 0)) + 1
	var tmp := SAVE_PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return best
	f.store_string(JSON.stringify(best, "\t"))
	f.close()
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.rename(tmp.get_file(), SAVE_PATH.get_file())
	return best
