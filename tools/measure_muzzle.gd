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
## future drift are one glance.
##
## Run: godot --headless --path . -s tools/measure_muzzle.gd

const DIRS := [
	"east", "south-east", "south", "south-west",
	"west", "north-west", "north", "north-east",
]

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
	{"label": "GUNNER", "canvas": 60, "scale": 2.0, "offset": Vector2(0, -15),
		"path": "res://assets/sprites/Scout_MachineGunner/Scout_MachineGunner/ReadyToFire_Stance/rotations/%s.png",
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
]

const UNIT_GD := "res://scripts/Unit.gd"


func _measure(entry: Dictionary) -> Array:
	## Returns [Vector2 node-space muzzle, Vector2 raw pixel] per direction,
	## or [] where the sprite is missing.
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
		out.append([node, best])
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
			var m_v: Vector2 = measured[entry.label][i][0]
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
