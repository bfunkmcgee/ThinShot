extends SceneTree

## Verifies every floor tilesheet against the region table that reads it, and
## every level against the sheet it asks for.
## Run: godot --headless --path . -s tools/check_floor_sheets.gd

func _init() -> void:
	var failed := false
	for name: String in Board.FLOOR_SHEETS:
		var tex: Texture2D = Board.FLOOR_SHEETS[name]
		var img := tex.get_image()
		var regions: Array[Rect2] = Board.SHEET_REGIONS[name]
		print("%s: %dx%d, %d regions" % [name, img.get_width(), img.get_height(),
				regions.size()])
		for i in regions.size():
			var r: Rect2 = regions[i]
			if not Rect2(0, 0, img.get_width(), img.get_height()).encloses(r):
				printerr("  slot %d region %s outside the sheet" % [i, r])
				failed = true
				continue
			# A mis-indexed slot lands on empty sheet, so count opaque pixels
			# and check the diamond's own centre is solid.
			var opaque := 0
			for y in int(r.size.y):
				for x in int(r.size.x):
					if img.get_pixel(int(r.position.x) + x, int(r.position.y) + y).a > 0.5:
						opaque += 1
			var coverage := float(opaque) / (r.size.x * r.size.y)
			var mid := img.get_pixel(int(r.position.x + r.size.x / 2),
					int(r.position.y + r.size.y / 2))
			if coverage < 0.4 or mid.a < 0.5:
				printerr("  slot %d looks empty (coverage %.2f, centre a=%.2f)"
						% [i, coverage, mid.a])
				failed = true
			else:
				print("  slot %d ok (coverage %.2f)" % [i, coverage])

	for idx in Levels.LEVELS.size():
		var data: Dictionary = Levels.LEVELS[idx]
		var floor_name: String = data.get("floor", Board.DEFAULT_FLOOR)
		var inset: Dictionary = data.get("floor_inset", {})
		var extra := ""
		if not inset.is_empty():
			extra = " + %s inset %s" % [inset.get("floor"), inset.get("rect")]
		if not Board.FLOOR_SHEETS.has(floor_name):
			printerr("level '%s' unknown floor '%s'" % [data.name, floor_name])
			failed = true
		print("level %d '%s': %s%s" % [idx, data.name, floor_name, extra])

	print("RESULT: ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
