extends SceneTree

## Measures the rifle-tip pixel in each aim-stance sprite: the opaque pixel
## farthest along the facing direction. Prints baked-const lines for Unit.gd
## (node space: sprite scale 2x, offset (0,-15)).
## Run: godot --headless --path . -s tools/measure_muzzle.gd

const DIRS := [
	"east", "south-east", "south", "south-west",
	"west", "north-west", "north", "north-east",
]


func _init() -> void:
	for team in [["Scout", 60], ["Goblin", 64]]:
		var team_name: String = team[0]
		var size: int = team[1]
		print("%s_MUZZLE_OFFSETS:" % team_name.to_upper())
		for i in DIRS.size():
			var path := "res://assets/sprites/%s/Standing_Ready_to_fire_stance/rotations/%s.png" % [
					team_name, DIRS[i]]
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
