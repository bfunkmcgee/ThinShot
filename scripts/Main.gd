extends Node2D

## Entry point for the ThinShot project.
## Attached to the root node of scenes/Main.tscn.

func _ready() -> void:
	print("ThinShot is running! Godot ", Engine.get_version_info().string)


func _process(_delta: float) -> void:
	# Press the "fire" action (Spacebar by default) to log an event.
	# This is just a placeholder to show the input map wired up in project.godot.
	if Input.is_action_just_pressed("fire"):
		print("fire!")
