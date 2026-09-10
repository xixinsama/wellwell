class_name PlayerInputSource
extends "res://addons/platformer_kit/character/input/input_source.gd"

var move_left_action: StringName = &"move_left"
var move_right_action: StringName = &"move_right"
var jump_action: StringName = &"jump"
var fast_fall_action: StringName = &"move_down"
var additional_actions: Array[StringName] = []


func get_intent() -> CHARACTER_INTENT:
	var intent := CHARACTER_INTENT.new()
	intent.move_axis = Input.get_axis(move_left_action, move_right_action)
	intent.jump_pressed = Input.is_action_just_pressed(jump_action)
	intent.jump_released = Input.is_action_just_released(jump_action)
	intent.jump_held = Input.is_action_pressed(jump_action)
	intent.fast_fall = Input.is_action_pressed(fast_fall_action)
	for action: StringName in additional_actions:
		if not action.is_empty() and _is_action_just_pressed(action):
			intent.press_action(action)
	return intent


func _is_action_just_pressed(action: StringName) -> bool:
	return Input.is_action_just_pressed(action)
