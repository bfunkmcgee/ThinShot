extends SceneTree

## Measures the rifle-tip pixel in each aim-stance sprite: the opaque pixel
## farthest along the facing direction. Prints baked-const lines for Unit.gd.
##
## v2: entries carry their own {canvas, scale, offset} instead of the old
## baked "x2, -30" math, so hi-res sheets (drawn at 1x with a doubled offset)
## measure through the same table. Node-space math for every entry:
##
##     node = (p + offset - canvas/2) * scale
##
## where `offset` is the unit's SPRITE_SPECS offset in texels (Godot applies
## sprite.offset before scale). With the legacy scale (2,2) / offset (0,-15)
## this reproduces the v1 output exactly - verified by diff.
##
## After the measured blocks it prints a delta table against the consts
## currently baked into scripts/Unit.gd, so hand-corrections (the southern
## facings, mostly - aimed at the camera, the scan lands on boots) and any
## future drift are one glance. It compares against the value this tool
## recommends for each facing, which is the band scan wherever there is one.
##
## v3 adds a second opinion for the six facings that have a horizontal
## component: the farthest-along-facing pixel is whatever sticks out most in
## that direction, which on a tall silhouette can be the crown of the head
## rather than the weapon. Dava's medic caught this - her north-west and
## north-east both scanned to her hair, 12 texels above the submachine gun.
## So each such facing also gets a BAND scan: the extreme pixel restricted to
## the shoulder-to-waist rows, where a carried weapon always is. When the two
## disagree the band line prints, and it is nearly always the one to bake.
##
## North and south get a band scan only where an entry's `levelled` key says
## the pose was drawn with the weapon off to a flank instead of foreshortened.
## See LEVELLED_LEFT below.
##
## Run: godot --headless --path . -s tools/measure_muzzle.gd

const DIRS := [
	"east", "south-east", "south", "south-west",
	"west", "north-west", "north", "north-east",
]

# The band as a fraction of the figure's own height, so it holds on the 56,
# 60 and 64 canvases alike: shoulder down to hip.
const BAND_FROM := 0.28
const BAND_TO := 0.66
const BAND_SIDE := {0: 1, 1: 1, 7: 1, 4: -1, 3: -1, 5: -1}  # sector -> +right/-left

# North and south are not in BAND_SIDE because a correctly drawn barrel is
# foreshortened at or away from the camera there, leaving no flank to scan.
# Pixel Lab often draws them levelled off sideways instead - all five Kestrels
# came back that way and validate_unit_sprites.py check [3] flags every one -
# and then the muzzle genuinely is out on one flank.
#
# Which flank is a fact about the art, so an entry states it in `levelled`
# rather than the tool guessing. Guessing was tried: comparing how far each
# side reaches past centre separates the north poses cleanly but not the south
# ones, where the free arm swings out far enough to bury the signal. An entry
# without the key measures as before, which is every shipped unit.
const LEVELLED_LEFT := -1
const LEVELLED_RIGHT := 1

# NOTE: GOBLIN_SMG_ALT keeps offset (0,-15) here although its live
# SPRITE_SPECS anchor is (0,-14): v1 baked the -30 screen shift into every
# kind, and these entries must reproduce v1 exactly. The 2px ride shows up
# in the delta table below, where it belongs, instead of silently moving
# every measured value.
const AIM_STANCES := [
	{"label": "SCOUT", "canvas": 60, "scale": 2.0, "offset": Vector2(0, -15),
		"path": "res://assets/sprites/Scout/Standing_Ready_to_fire_stance/rotations/%s.png",
		"unit_const": "SCOUT_MUZZLE_OFFSETS"},
	{"label": "GOBLIN", "canvas": 64, "scale": 2.0, "offset": Vector2(0, -15),
		"path": "res://assets/sprites/Goblin/Standing_Ready_to_fire_stance/rotations/%s.png",
		"unit_const": "GOBLIN_MUZZLE_OFFSETS"},
	{"label": "LEAD", "canvas": 60, "scale": 2.0, "offset": Vector2(0, -15),
		"path": "res://assets/sprites/Scout_TeamLead/Solider_aims_his_rif/rotations/%s.png",
		"unit_const": "LEAD_MUZZLE_OFFSETS"},
	# Brukk Meshan. The old Scout_MachineGunner path still resolves - that art
	# is kept as generic-troop art - which is exactly why this had to be moved
	# by hand: left alone the tool would have gone on measuring a sheet the
	# game no longer draws and reported "all 8 facings match" against a table
	# that had stopped describing anything on screen.
	{"label": "GUNNER", "canvas": 60, "scale": 2.0, "offset": Vector2(0, -15),
		"path": "res://assets/sprites/Hero_MachineGunner/ReadyToFire_Stance/rotations/%s.png",
		"unit_const": "GUNNER_MUZZLE_OFFSETS"},
	{"label": "GOBLIN_SMG", "canvas": 64, "scale": 2.0, "offset": Vector2(0, -15),
		"path": "res://assets/sprites/Goblin_SMG/Goblin_aims_submachi/rotations/%s.png",
		"unit_const": "SMG_MUZZLE_OFFSETS"},
	{"label": "GOBLIN_REVOLVER", "canvas": 64, "scale": 2.0, "offset": Vector2(0, -15),
		"path": "res://assets/sprites/Goblin_revolver/standing_readyToFire_stance/rotations/%s.png",
		"unit_const": "REV_MUZZLE_OFFSETS"},
	{"label": "GOBLIN_SMG_ALT", "canvas": 56, "scale": 2.0, "offset": Vector2(0, -15),
		"path": "res://assets/sprites/Goblin_SMG_alt/ready_to_fire_stance/rotations/%s.png",
		"unit_const": "SMGA_MUZZLE_OFFSETS"},
	{"label": "GOBLIN_BOLT", "canvas": 60, "scale": 2.0, "offset": Vector2(0, -15),
		"path": "res://assets/sprites/Goblin_BoltRifle/ReadyToFire_Stance/rotations/%s.png",
		"unit_const": "BOLT_MUZZLE_OFFSETS"},
	# v2 additions - not in the v1 table, appended after it. The southern
	# facings in Unit.gd are hand-corrected, so expect deltas there - aimed
	# at the camera, the scan lands on boots.
	{"label": "RODAR", "canvas": 60, "scale": 2.0, "offset": Vector2(0, -15),
		"path": "res://assets/sprites/Rodar_Akai/ReadyToFire_Stance/rotations/%s.png",
		"unit_const": "RODAR_MUZZLE_OFFSETS"},
	# South and north are drawn genuinely foreshortened at/away from the
	# camera (validate_unit_sprites.py check [3] confirms), so the scan lands
	# on boots/helmet there and Unit.gd hand-sets those two at the muzzle ring.
	{"label": "GOBLIN_MG", "canvas": 64, "scale": 2.0, "offset": Vector2(0, -15),
		"path": "res://assets/sprites/Goblin_MG/ReadyToFire_Stance/rotations/%s.png",
		"unit_const": "GMG_MUZZLE_OFFSETS"},
	# South/north are foreshortened at/away from the camera (section 6
	# composite), so the scan lands on boots/hair there - hand-set those two.
	{"label": "ELF_PARTISAN", "canvas": 64, "scale": 2.0, "offset": Vector2(0, -15),
		"path": "res://assets/sprites/Elf_Partisan/ReadyToFire_Stance/rotations/%s.png",
		"unit_const": "ELFP_MUZZLE_OFFSETS"},
	# The five specialist Kestrels. Same 60-canvas legacy density as the
	# rifleman they were generated against, so they ride SPRITE_SPECS DEFAULT.
	#
	# Every one of them has its south aim pose drawn levelled to the right
	# instead of foreshortened at the camera. Three also carry a visible weapon
	# levelled left on north; Halvik and Fen are drawn as a plain back view with
	# no weapon at all there, so they take the ordinary centred, head-height
	# north that every shipped unit uses for a barrel pointing away.
	{"label": "KESTREL_GRENADIER", "canvas": 60, "scale": 2.0, "offset": Vector2(0, -15),
		"path": "res://assets/sprites/Kestrel_Grenadier/ReadyToFire_Stance/rotations/%s.png",
		"levelled": {"south": LEVELLED_RIGHT, "north": LEVELLED_LEFT},
		"unit_const": "GRENADIER_MUZZLE_OFFSETS"},
	{"label": "KESTREL_MARKSMAN", "canvas": 60, "scale": 2.0, "offset": Vector2(0, -15),
		"path": "res://assets/sprites/Kestrel_Marksman/ReadyToFire_Stance/rotations/%s.png",
		"levelled": {"south": LEVELLED_RIGHT, "north": LEVELLED_LEFT},
		"unit_const": "MARKSMAN_MUZZLE_OFFSETS"},
	{"label": "KESTREL_BREACHER", "canvas": 60, "scale": 2.0, "offset": Vector2(0, -15),
		"path": "res://assets/sprites/Kestrel_Breacher/ReadyToFire_Stance/rotations/%s.png",
		"levelled": {"south": LEVELLED_RIGHT},
		"unit_const": "BREACHER_MUZZLE_OFFSETS"},
	{"label": "KESTREL_MEDIC", "canvas": 60, "scale": 2.0, "offset": Vector2(0, -15),
		"path": "res://assets/sprites/Kestrel_Medic/ReadyToFire_Stance/rotations/%s.png",
		"levelled": {"south": LEVELLED_RIGHT, "north": LEVELLED_LEFT},
		"unit_const": "MEDIC_MUZZLE_OFFSETS"},
	{"label": "KESTREL_TECHNICIAN", "canvas": 60, "scale": 2.0, "offset": Vector2(0, -15),
		"path": "res://assets/sprites/Kestrel_Technician/ReadyToFire_Stance/rotations/%s.png",
		"levelled": {"south": LEVELLED_RIGHT},
		"unit_const": "TECHNICIAN_MUZZLE_OFFSETS"},
]

const UNIT_GD := "res://scripts/Unit.gd"


func _band_pixel(img: Image, side: int) -> Vector2:
	## The extreme pixel on `side` (+1 right / -1 left) within the figure's
	## shoulder-to-hip rows. Returns (-1, -1) if the band holds nothing.
	var top := img.get_height()
	var bottom := -1
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				top = mini(top, y)
				bottom = maxi(bottom, y)
				break
	if bottom < 0:
		return Vector2(-1, -1)
	var span := float(bottom - top + 1)
	var lo := top + int(span * BAND_FROM)
	var hi := top + int(span * BAND_TO)
	var best := Vector2(-1, -1)
	for y in range(lo, hi + 1):
		for x in img.get_width():
			if img.get_pixel(x, y).a <= 0.5:
				continue
			if best.x < 0 or (side > 0 and x > best.x) or (side < 0 and x < best.x):
				best = Vector2(x, y)
	return best


func _measure(entry: Dictionary) -> Array:
	## Returns [Vector2 node-space muzzle, Vector2 raw pixel, Vector2 band
	## node-space or (INF, INF) where there is none] per direction, or [] where
	## the sprite is missing.
	var out: Array = []
	var canvas: float = entry.canvas
	var center := Vector2(canvas / 2.0, canvas / 2.0)
	for i in DIRS.size():
		var path: String = entry.path % DIRS[i]
		var img := Image.load_from_file(path)
		if img == null:
			out.append([])
			continue
		var dir := Vector2.RIGHT.rotated(TAU * i / 8.0)
		var best := center
		var best_dot := -1e9
		for y in img.get_height():
			for x in img.get_width():
				if img.get_pixel(x, y).a > 0.5:
					var d := (Vector2(x, y) - center).dot(dir)
					if d > best_dot:
						best_dot = d
						best = Vector2(x, y)
		var node: Vector2 = (best + entry.offset - center) * float(entry.scale)
		var band := Vector2(INF, INF)
		var bp := Vector2(-1, -1)
		var levelled: Dictionary = entry.get("levelled", {})
		if BAND_SIDE.has(i):
			bp = _band_pixel(img, BAND_SIDE[i])
		elif levelled.has(DIRS[i]):
			bp = _band_pixel(img, levelled[DIRS[i]])
		if bp.x >= 0:
			band = (bp + entry.offset - center) * float(entry.scale)
		out.append([node, best, band])
	return out


func _baked_consts() -> Dictionary:
	## Parse the *_MUZZLE_OFFSETS consts out of Unit.gd: name -> Array[Vector2].
	var out := {}
	var f := FileAccess.open(UNIT_GD, FileAccess.READ)
	if f == null:
		return out
	var text := f.get_as_text()
	var head := RegEx.new()
	head.compile("const\\s+(\\w+_MUZZLE_OFFSETS)\\s*:\\s*Array\\[Vector2\\]\\s*=\\s*\\[")
	var vec := RegEx.new()
	vec.compile("Vector2\\(\\s*(-?\\d+)\\s*,\\s*(-?\\d+)\\s*\\)")
	for m in head.search_all(text):
		var name: String = m.get_string(1)
		var start: int = m.get_end()
		var stop: int = text.find("]", start)
		var vals: Array = []
		for v in vec.search_all(text.substr(start, stop - start)):
			vals.append(Vector2(v.get_string(1).to_int(), v.get_string(2).to_int()))
		out[name] = vals
	return out


func _init() -> void:
	var measured := {}
	for entry in AIM_STANCES:
		var rows := _measure(entry)
		measured[entry.label] = rows
		print("%s_MUZZLE_OFFSETS:" % entry.label)
		for i in DIRS.size():
			if rows[i].is_empty():
				print("\t# %s: MISSING %s" % [DIRS[i], entry.path % DIRS[i]])
				continue
			var node: Vector2 = rows[i][0]
			var best: Vector2 = rows[i][1]
			print("\tVector2(%d, %d),  # %s  px(%d, %d)" % [
					node.x, node.y, DIRS[i], best.x, best.y])
			var band: Vector2 = rows[i][2]
			if band.x != INF and band != node:
				print("\t\t# band says Vector2(%d, %d) - the scan found something"
						% [band.x, band.y]
						+ " outside the weapon rows, so prefer the band.")

	# ---- delta vs the consts actually baked into Unit.gd -------------------
	var baked := _baked_consts()
	print("")
	print("== delta vs %s (measured - baked; non-zero = hand-correction or drift) ==" % UNIT_GD)
	for entry in AIM_STANCES:
		var name: String = entry.unit_const
		if not baked.has(name):
			print("%s: not found in Unit.gd (unwired kind?)" % name)
			continue
		var vals: Array = baked[name]
		print("%s (from %s):" % [name, entry.label])
		var clean := true
		for i in DIRS.size():
			if measured[entry.label][i].is_empty() or i >= vals.size():
				print("\t%-12s -- missing" % DIRS[i])
				continue
			# Compare against what the tool would have you bake, not against the
			# plain scan - otherwise every band-sourced facing shows a delta
			# forever and real drift has nowhere to stand out.
			var m_v: Vector2 = measured[entry.label][i][0]
			var band_v: Vector2 = measured[entry.label][i][2]
			if band_v.x != INF:
				m_v = band_v
			var b_v: Vector2 = vals[i]
			var d := m_v - b_v
			if d == Vector2.ZERO:
				continue
			clean = false
			print("\t%-12s measured (%4d, %4d)  baked (%4d, %4d)  delta (%4d, %4d)" % [
					DIRS[i], m_v.x, m_v.y, b_v.x, b_v.y, d.x, d.y])
		if clean:
			print("\t(all 8 facings match)")
	quit()
