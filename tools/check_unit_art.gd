extends SceneTree

## Asserts every Unit.Kind actually loads the art it claims to.
##
## Why this exists: the frame loaders fail SILENTLY. `_load_dir_frames` returns
## an empty array for a path that is not there and `_load_rotation_frames`
## appends nulls, neither pushes an error, and `_update_sprite` falls back to a
## static pose when a cycle is empty. So a mistyped root leaves a unit standing
## still with no console output at all - and on Windows a mis-CASED path
## resolves anyway at the OS level, so it survives every local run and only
## breaks in an exported build, where res:// paths are case-sensitive.
##
## Nothing else caught that. tools/test_progression.gd builds machinegunners
## through the real setup() and asserts overwatch rounds, magazine size,
## suppression radius and arc - never a frame. The whole suite would print PASS
## with all eleven of a kind's frame sets empty.
##
## Checked per kind:
##   rotations      frames / aim_frames / dead_frames: 8 entries, none null
##   animations     idle / walk / raise / aim_idle / death / hurt / reload:
##                  8 direction arrays, each holding at least one frame
##   idle_alt       optional (UNIT_ASSET_SPEC.md §3), but if it is present it
##                  must be 8 directions, because the field is INDEXED BY
##                  DIRECTION - a half-filled one is an out-of-bounds crash the
##                  first time that unit idles facing the wrong way
##
## Kinds whose art genuinely reuses one set for several fields (the civilian
## cowers instead of aiming, and has no reload) are declared in REUSES below
## rather than exempted wholesale, so a real regression there still fails.
##
## Unit is loaded at runtime and its enums read from the constant map: naming
## it in the script body would make a -s run compile Unit.gd before the
## autoloads exist, and Unit.gd names Game.
##
## Run: godot --headless --path . -s tools/check_unit_art.gd

const DIRS := 8

const ROTATION_FIELDS := ["frames", "aim_frames", "dead_frames"]
const ANIM_FIELDS := ["idle_frames", "walk_frames", "raise_frames",
		"aim_idle_frames", "death_frames", "hurt_frames", "reload_frames"]

## Kinds that deliberately point several fields at one set, and why. Listed so
## the check stays strict everywhere else.
const REUSES := {
	"CIVILIAN": "carries no weapon: aim, raise, aim-idle, hurt and reload are all the cower loop",
}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var unit_script: GDScript = load("res://scripts/Unit.gd")
	var kind_enum: Dictionary = unit_script.get_script_constant_map()["Kind"]
	var scene: PackedScene = load("res://scenes/Unit.tscn")

	var failures: Array[String] = []
	var checked := 0
	var names: Array = kind_enum.keys()
	names.sort()

	for kind_name: String in names:
		var u := scene.instantiate()
		root.add_child(u)
		u.setup(int(kind_enum[kind_name]), Vector2i.ZERO)
		checked += 1

		for field: String in ROTATION_FIELDS:
			var rot: Array = u.get(field)
			if rot.size() != DIRS:
				failures.append("%s.%s: %d rotations, want %d"
						% [kind_name, field, rot.size(), DIRS])
				continue
			for i in DIRS:
				if rot[i] == null:
					failures.append("%s.%s[%d] is null (missing PNG)"
							% [kind_name, field, i])

		for field: String in ANIM_FIELDS:
			var sets: Array = u.get(field)
			if sets.size() != DIRS:
				failures.append("%s.%s: %d direction(s), want %d - the loader "
						% [kind_name, field, sets.size(), DIRS]
						+ "found nothing, so the path is wrong")
				continue
			for i in DIRS:
				var cycle: Array = sets[i]
				if cycle.is_empty():
					failures.append("%s.%s[%d]: no frames" % [kind_name, field, i])

		# Optional, but a partially-filled one crashes on first use because the
		# field is indexed by direction.
		var alt: Array = u.get("idle_alt_frames")
		if not alt.is_empty() and alt.size() != DIRS:
			failures.append("%s.idle_alt_frames: %d direction(s) - must be 0 or %d"
					% [kind_name, alt.size(), DIRS])

		u.queue_free()

	print("checked %d kind(s): %s" % [checked, ", ".join(names)])
	for kind_name: String in REUSES:
		print("  note: %s reuses sets - %s" % [kind_name, REUSES[kind_name]])
	if failures.is_empty():
		print("\nRESULT: PASS")
		quit()
		return
	print("\n%d problem(s):" % failures.size())
	for f: String in failures:
		print("  %s" % f)
	print("\nRESULT: FAIL")
	quit(1)
