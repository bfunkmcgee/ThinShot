extends Node

## Campaign progress (autoload) - survives reload_current_scene().

var current_level := 0


func data() -> Dictionary:
	return Levels.LEVELS[current_level]


func is_last_level() -> bool:
	return current_level >= Levels.LEVELS.size() - 1


func select_level(index: int) -> void:
	current_level = clampi(index, 0, Levels.LEVELS.size() - 1)
