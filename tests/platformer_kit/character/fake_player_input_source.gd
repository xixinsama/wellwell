extends "res://addons/platformer_kit/character/input/player_input_source.gd"

var pressed_actions: Array[StringName] = []


func _is_action_just_pressed(action: StringName) -> bool:
	return pressed_actions.has(action)
