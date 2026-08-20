extends SceneTree

## Scenery gets out of the way of the people.
##
## The board is 3/4 top-down and the props are tall: a rock reaches 74px above
## its own cell and a sandbag line 90px, against a 60px tile step. So a prop
## covers about two and a half cells of screen behind it, and a soldier who
## walks into that band is invisible. Y-sorting is correct and does not help -
## the unit IS behind the prop and the prop IS drawn over him.
##
## Five things are checked, and the last three are the ones that keep the fix
## from being worse than the bug:
##   1. scenery is collected, and soldiers are not in the list
##   2. a prop standing over a body fades
##   3. a prop BEHIND him never does - it is drawn first and hides nothing
##   4. a prop that only clips his boots never does either, because feet going
##      behind a barrel is depth rather than a bug
##   5. and everything that is not in the way goes back to solid
##
## Runs headless: nothing here reads a pixel. It asserts on the alpha the pass
## decides, which is the whole of the rule; whether that alpha LOOKS right is
## tools/render_occlusion_check.gd's job, and it needs a window.
##
## Run: godot --headless --path . -s tools/test_occlusion.gd

var _failed := false


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok    %s" % label)
	else:
		printerr("  FAIL  %s" % label)
		_failed = true


func _init() -> void:
	_run()


## Settle the fade: the pass moves alpha at OCCLUSION_FADE per second, so a
## generous delta lands it in one call.
func _settle(battle: Node) -> void:
	for i in 4:
		battle._refresh_occlusion(1.0)


func _run() -> void:
	await process_frame
	var game: Node = root.get_node("/root/Game")
	if game.roster.is_empty():
		game.new_campaign()
	game.current_level = 1          # THE SCRAPLINE - the scrap yard, plenty of props
	game.in_the_field = true

	var battle: Node = (load("res://scenes/Battle.tscn") as PackedScene).instantiate()
	root.add_child(battle)
	await process_frame
	await process_frame

	print("\n[1] the scenery is collected and the soldiers are not in it")
	_check(not battle._occluders.is_empty(),
			"the board's scenery is on the list (%d pieces)" % battle._occluders.size())
	# Compared against the real units rather than with `is Unit`: naming Unit
	# here compiles Unit.gd, which names the Game autoload, which does not exist
	# yet under -s - and the failed compile is then CACHED, so Battle's own
	# `child as Unit` starts returning null and the board empties. The harnesses
	# that document this trap at length are test_hero_gameover.gd and
	# test_rules.gd; this is the same one.
	var unit_sprites := {}
	for team in 2:
		for u in battle.living_units(team):
			unit_sprites[u.sprite.get_instance_id()] = true
			unit_sprites[u.get_instance_id()] = true
	var soldiers_in_list := 0
	for entry: Dictionary in battle._occluders:
		if unit_sprites.has((entry.sprite as Node).get_instance_id()):
			soldiers_in_list += 1
	_check(soldiers_in_list == 0,
			"and no soldier is in it - fading a unit to reveal a unit is circular")

	var subject: Node2D = null
	for u in battle.living_soldiers(0):
		subject = u
		break
	_check(subject != null, "somebody to stand behind things")
	if subject == null or battle._occluders.is_empty():
		battle.free()
		_finish()
		return

	# A prop of our own, placed exactly over his head, so the assertions below
	# are about the RULE rather than about whatever the level happens to scatter.
	var body: Rect2 = battle._sprite_rect(subject.sprite)
	var head := Vector2(body.position.x + body.size.x * 0.5,
			body.position.y + body.size.y * 0.25)

	print("\n[2] a prop standing over a body fades")
	var over := _plant(battle, head + Vector2(0, 40.0), subject.global_position.y + 40.0)
	_settle(battle)
	_check(over.modulate.a < 0.99,
			"the prop in front of him stands aside (alpha %.2f)" % over.modulate.a)
	_check(is_equal_approx(over.modulate.a, battle.OCCLUDED_ALPHA),
			"...to exactly OCCLUDED_ALPHA (%.2f)" % over.modulate.a)
	_check(over.modulate.a > 0.0,
			"...and not to nothing: it still has to read as cover (%.2f)"
			% over.modulate.a)

	print("\n[3] a prop behind him does not")
	# Same overlap, but it sorts BEHIND - it is drawn first, so it cannot be
	# covering anybody, and fading it would be pure vandalism.
	var behind := _plant(battle, head + Vector2(0, 40.0),
			subject.global_position.y - 80.0)
	_settle(battle)
	_check(is_equal_approx(behind.modulate.a, 1.0),
			"scenery drawn before him is left alone (alpha %.2f)" % behind.modulate.a)

	print("\n[4] and one that only clips his boots does not either")
	# Sorts in front and overlaps the sprite - but only the bottom of it, which
	# is the case a naive rectangle test gets wrong and which is not a bug: feet
	# going behind a barrel is how depth reads.
	# Sized to cover his LEGS and almost nothing above them: about a third of
	# the sprite, sitting from roughly two-thirds of the way down. That is the
	# case that tells the two rules apart. A third of the whole body is over the
	# threshold, so a version that measures the whole sprite fades this; the
	# same prop is barely inside the recognition band, so the shipped rule does
	# not. A small prop passes under both and proves nothing - which is what the
	# first version of this did.
	# WIDE and short: as wide as he is, about a third of him tall. Width matters
	# as much as height, because the test is on area - a narrow prop across his
	# legs is under the threshold either way and proves nothing, which is what
	# the first two versions of this did.
	var legs := Vector2i(int(body.size.x / 2.0), int(body.size.y * 0.34 / 2.0))
	var boots := _plant(battle,
			Vector2(body.position.x + body.size.x * 0.5,
					body.position.y + body.size.y * 0.84),
			subject.global_position.y + 40.0, legs)
	_settle(battle)
	_check(is_equal_approx(boots.modulate.a, 1.0),
			"a prop across his boots stays solid (alpha %.2f)" % boots.modulate.a)

	print("\n[5] and it goes back when he moves off")
	subject.position += Vector2(0, -4000.0)   # a long way up-screen, and away
	_settle(battle)
	_check(is_equal_approx(over.modulate.a, 1.0),
			"the prop that stood aside is solid again (alpha %.2f)" % over.modulate.a)
	# Only the props planted here. The level's own scenery is legitimately faded
	# by the OTHER seventeen people on the board, and asserting over all of it
	# was asserting that nobody else exists.
	var mine: Array[Sprite2D] = [over, behind, boots]
	var still_faded := 0
	for spr: Sprite2D in mine:
		if spr.modulate.a < 0.99:
			still_faded += 1
	_check(still_faded == 0,
			"and none of the planted props is left ghosted (%d of 3)" % still_faded)

	battle.free()
	_finish()


## A test prop: a Sprite2D in the entities layer with a known screen rect, put
## on the occluder list the same way the real ones are.
func _plant(battle: Node, centre: Vector2, sort_y: float,
		art := Vector2i(64, 64)) -> Sprite2D:
	var img := Image.create(art.x, art.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	var spr := Sprite2D.new()
	spr.texture = ImageTexture.create_from_image(img)
	spr.scale = Vector2(2, 2)
	spr.position = Vector2(centre.x, sort_y)
	# offset is in texture space and scales with the sprite, so this puts the
	# 128px-tall drawn rect where the caller asked while leaving the node's own
	# y - the one that decides sort order - where it was put.
	spr.offset = Vector2(0, (centre.y - sort_y) / spr.scale.y)
	battle.entities_node.add_child(spr)
	battle._occluders.append({"sprite": spr, "sorts_by": spr})
	return spr


func _finish() -> void:
	print("\nRESULT: ", "FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)
