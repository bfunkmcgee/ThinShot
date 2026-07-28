extends SceneTree

## Measures the rifle-tip pixel in each aim-stance sprite: the opaque pixel
## farthest along the facing direction. Prints baked-const lines for Unit.gd
## (node space: sprite scale 2x, offset (0,-15)).
## Run: godot --headless --path . -s tools/measure_muzzle.gd

const DIRS := [
	"east", "south-east", "south", "south-west",
	"west", "north-west", "north", "north-east",
]


const AIM_STANCES := [
	["SCOUT", 60, "res://assets/sprites/Scout/Standing_Ready_to_fire_stance/rotations/%s.png"],
	["GOBLIN", 64, "res://assets/sprites/Goblin/Standing_Ready_to_fire_stance/rotations/%s.png"],
	["LEAD", 60, "res://assets/sprites/Scout_TeamLead/Solider_aims_his_rif/rotations/%s.png"],
	["GUNNER", 60, "res://assets/sprites/Scout_MachineGunner/Scout_MachineGunner/ReadyToFire_Stance/rotations/%s.png"],
	["GOBLIN_SMG", 64, "res://assets/sprites/Goblin_SMG/Goblin_aims_submachi/rotations/%s.png"],
	["GOBLIN_REVOLVER", 64, "res://assets/sprites/Goblin_revolver/standing_readyToFire_stance/rotations/%s.png"],
	["GOBLIN_SMG_ALT", 56, "res://assets/sprites/Goblin_SMG_alt/ready_to_fire_stance/rotations/%s.png"],
]


func _init() -> void:
	for stance in AIM_STANCES:
		var label: String = stance[0]
		var size: int = stance[1]
		var template: String = stance[2]
		print("%s_MUZZLE_OFFSETS:" % label)
		for i in DIRS.size():
			var path: String = template % DIRS[i]
			var img := Image.load_from_file(path)
			var dir := Vector2.RIGHT.rotated(TAU * i / 8.0)
			var center := Vector2(size / 2.0, size / 2.0)
			var best := center
			var best_dot := -1e9
			for y in img.get_height():
				for x in img.get_width():
					if img.get_pixel(x, y).a > 0.5:
						var d := (Vector2(x, y) - center).dot(dir)
						if d > best_dot:
							best_dot = d
							best = Vector2(x, y)
			var node := Vector2(
					(best.x - size / 2.0) * 2.0,
					(best.y - size / 2.0) * 2.0 - 30.0)
			print("\tVector2(%d, %d),  # %s  px(%d, %d)" % [
					node.x, node.y, DIRS[i], best.x, best.y])
	quit()
