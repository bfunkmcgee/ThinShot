extends SceneTree

## Prints a suggested Board.FLOOR_MOODS entry for a floor sheet, using the
## same math the shipped entries were derived with - so the upcoming salt/ash/
## compound re-promotions get their retune from one command instead of a
## by-hand measurement session.
##
## THE METHOD (reverse-engineered 2026-08 from the relationship between the
## old sheets' measured colours and the shipped constants, then verified: it
## reprints salt's shipped entry exactly - all six numbers - and compound's to
## within one final-digit rounding on tint blue; ash's shadow is exact while
## its tint is special-cased neutral and its haze was hand-darkened ~10% for
## the burnt bowl; the old hand-tuned desert tint reproduced to within 0.01):
##   mean   - masked mean colour of ALL the sheet's slots (alpha > 0.5).
##   lum    - Rec.601 luminance (0.299 R + 0.587 G + 0.114 B) of that mean.
##   tint   - (channel / lum)^0.2, then scaled so the tint's own Rec.601
##            luminance is 1 - the "normalised to preserve luminance" step in
##            Board.gd's FLOOR_MOODS comment.
##   haze   - mean desaturated 30% toward its own lum, then lifted 25% toward
##            white.
##   shadow - mean * 0.20 (exact for salt/ash/compound at two decimals).
##   gain   - REF_LUM / lum. REF_LUM is the ORIGINAL desert sheet's measured
##            lum, 146.5/255 - the "desert's 147" in Board.gd's comment. Every
##            hand-tuned shadow alpha in the game was tuned against that
##            sheet, so it stays the fixed readability reference even now the
##            desert art itself has moved on. Shipped ash (1.50 vs recipe
##            1.44) and compound (1.08 vs 1.05) were hand-nudged upward;
##            salt (0.96) matches the recipe exactly.
##   accent / spacing - from how loudly an accent shouts over the calmest base
##            family. Contrast = per-slot std of per-pixel luminance ((r+g+b)/3
##            in 0..255); ratio = the flattest-base zone's accent contrast over
##            its base contrast. The shipped values band as:
##              ratio < 2.0 -> 0.07 / 2   (old desert measured 1.1)
##              ratio < 3.1 -> 0.06 / 2   (salt 3.0)
##              ratio < 4.0 -> 0.05 / 3   (compound 3.2)
##              else        -> 0.04 / 4   (ash 4.6 - the "9 against 44" in
##                                         Board.gd's comment)
##            A judgment scale, not physics: eyeball the result on promotion.
##
## Run:
##   powershell tools/godot.ps1 --headless --path . -s tools/derive_floor_mood.gd `
##       -- --sheet assets/Tiles/Environments/Desert/Cracked_Desert_floor.png
##
## Slot rects/zones/roles come from the sheet's `.tiles.json` sidecar. A sheet
## without one falls back to the legacy 10-slot flat layout (Board.
## TILE_REGIONS_FLAT with Board.ZONE_ACCENTS as the accent slots).

const REF_LUM := 146.5 / 255.0  # original desert sheet, all slots, Rec.601

var failed := false


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var sheet_path := ""
	var i := 0
	while i < args.size():
		if args[i] == "--sheet" and i + 1 < args.size():
			sheet_path = args[i + 1]
			i += 2
		else:
			printerr("unknown argument '%s'" % args[i])
			i += 1
	if sheet_path.is_empty():
		printerr("usage: godot --headless --path . -s tools/derive_floor_mood.gd"
				+ " -- --sheet <floor sheet .png>")
		quit(1)
		return
	if not sheet_path.begins_with("res://") and sheet_path.is_relative_path():
		sheet_path = "res://" + sheet_path.replace("\\", "/")
	var img := Image.load_from_file(sheet_path)
	if img == null:
		printerr("cannot load image: %s" % sheet_path)
		quit(1)
		return
	var layout := _layout_for(sheet_path)
	_derive(sheet_path, img, layout)
	quit(1 if failed else 0)


## Base/accent slot rects per zone: {bases: [zone -> Array[Rect2]],
## accents: [zone -> Array[Rect2]], source: String}.
func _layout_for(sheet_path: String) -> Dictionary:
	var bases: Array = [[], [], []]
	var accents: Array = [[], [], []]
	var sidecar := TileCatalog.sidecar_path(sheet_path)
	if FileAccess.file_exists(sidecar):
		var data: Variant = JSON.parse_string(
				FileAccess.get_file_as_string(sidecar))
		if typeof(data) == TYPE_DICTIONARY:
			for slot: Dictionary in data.get("slots", []):
				var rect_arr: Array = slot.get("rect", [])
				if rect_arr.size() != 4:
					continue
				var rect := Rect2(float(rect_arr[0]), float(rect_arr[1]),
						float(rect_arr[2]), float(rect_arr[3]))
				var zone := clampi(int(slot.get("zone", 0)), 0, 2)
				if str(slot.get("role", "base")) == "accent":
					accents[zone].append(rect)
				else:
					bases[zone].append(rect)
			return {"bases": bases, "accents": accents, "source": sidecar}
		printerr("sidecar is not a JSON object, using legacy layout: %s" % sidecar)
	# Legacy 10-slot flat layout; zone families/accents as Board hardcodes them.
	for zone in 3:
		for idx: int in Board.ZONE_FAMILIES[zone]:
			bases[zone].append(Board.TILE_REGIONS_FLAT[idx])
		accents[zone].append(Board.TILE_REGIONS_FLAT[Board.ZONE_ACCENTS[zone]])
	return {"bases": bases, "accents": accents,
			"source": "legacy layout (no sidecar)"}


func _derive(sheet_path: String, img: Image, layout: Dictionary) -> void:
	var all_rects: Array = []
	for zone in 3:
		all_rects.append_array(layout.bases[zone])
		all_rects.append_array(layout.accents[zone])
	if all_rects.is_empty():
		printerr("no slots found for %s" % sheet_path)
		failed = true
		return
	var mean := _masked_mean(img, all_rects)
	var lum := _lum601(mean)
	if lum <= 0.0:
		printerr("sheet measures black/empty - wrong rects?")
		failed = true
		return
	print("sheet:  %s" % sheet_path)
	print("slots:  %s" % str(layout.source))
	print("mean:   (%.4f, %.4f, %.4f)  lum601 %.1f/255 (ref %.1f)"
			% [mean.x, mean.y, mean.z, lum * 255.0, REF_LUM * 255.0])

	var tint := Vector3(pow(mean.x / lum, 0.2), pow(mean.y / lum, 0.2),
			pow(mean.z / lum, 0.2))
	tint /= _lum601(tint)
	var desat := mean.lerp(Vector3.ONE * lum, 0.30)
	var haze := desat.lerp(Vector3.ONE, 0.25)
	var shadow := mean * 0.20
	var gain := REF_LUM / lum

	# Accent loudness: the flattest zone's base contrast vs its own accent.
	var flat_zone := -1
	var flat_contrast := INF
	for zone in 3:
		var c := _mean_contrast(img, layout.bases[zone])
		var a := _mean_contrast(img, layout.accents[zone])
		print("zone %d: base contrast %5.1f | accent %5.1f%s" % [zone, c, a,
				"" if a > 0.0 else " (no accent slots)"])
		if c > 0.0 and c < flat_contrast:
			flat_contrast = c
			flat_zone = zone
	var accent := 0.06
	var spacing := 2
	var ratio := 0.0
	if flat_zone >= 0:
		var accent_contrast := _mean_contrast(img, layout.accents[flat_zone])
		if accent_contrast > 0.0:
			ratio = accent_contrast / flat_contrast
			if ratio < 2.0:
				accent = 0.07
				spacing = 2
			elif ratio < 3.1:
				accent = 0.06
				spacing = 2
			elif ratio < 4.0:
				accent = 0.05
				spacing = 3
			else:
				accent = 0.04
				spacing = 4
	print("ratio:  %.2f (flattest zone %d) -> accent %.2f, spacing %d"
			% [ratio, flat_zone, accent, spacing])

	var floor_name := sheet_path.get_base_dir().get_file().to_lower()
	print("")
	print("suggested FLOOR_MOODS entry:")
	print("\t\"%s\": {" % floor_name)
	print("\t\t\"tint\": Vector3(%.2f, %.2f, %.2f)," % [tint.x, tint.y, tint.z])
	print("\t\t\"haze\": Vector3(%.2f, %.2f, %.2f)," % [haze.x, haze.y, haze.z])
	print("\t\t\"shadow\": Color(%.2f, %.2f, %.2f)," % [shadow.x, shadow.y, shadow.z])
	print("\t\t\"shadow_gain\": %.2f," % gain)
	print("\t\t\"accent\": %.2f," % accent)
	print("\t\t\"spacing\": %d," % spacing)
	print("\t},")


static func _lum601(c: Vector3) -> float:
	return 0.299 * c.x + 0.587 * c.y + 0.114 * c.z


## Mean RGB over the alpha>0.5 pixels of the given rects.
static func _masked_mean(img: Image, rects: Array) -> Vector3:
	var acc := Vector3.ZERO
	var n := 0
	for r: Rect2 in rects:
		for y in int(r.size.y):
			for x in int(r.size.x):
				var px := img.get_pixel(int(r.position.x) + x, int(r.position.y) + y)
				if px.a > 0.5:
					acc += Vector3(px.r, px.g, px.b)
					n += 1
	return acc / float(maxi(n, 1))


## Mean over the rects of each rect's contrast: the std of per-pixel
## (r+g+b)/3 luminance, in 0..255 so the numbers match Board.gd's comment.
static func _mean_contrast(img: Image, rects: Array) -> float:
	if rects.is_empty():
		return 0.0
	var total := 0.0
	for r: Rect2 in rects:
		var lums: Array[float] = []
		for y in int(r.size.y):
			for x in int(r.size.x):
				var px := img.get_pixel(int(r.position.x) + x, int(r.position.y) + y)
				if px.a > 0.5:
					lums.append((px.r + px.g + px.b) / 3.0 * 255.0)
		if lums.is_empty():
			continue
		var mean := 0.0
		for l in lums:
			mean += l
		mean /= lums.size()
		var var_sum := 0.0
		for l in lums:
			var_sum += (l - mean) * (l - mean)
		total += sqrt(var_sum / lums.size())
	return total / rects.size()
