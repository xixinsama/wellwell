class_name CharacterIntent
extends RefCounted

var move_axis := 0.0
var jump_pressed := false
var jump_released := false
var jump_held := false
var fast_fall := false
var _pressed_actions: Dictionary[StringName, bool] = {}


func press_action(action: StringName) -> bool:
	if action.is_empty() or _pressed_actions.has(action):
		return false
	_pressed_actions[action] = true
	return true


func is_action_pressed(action: StringName) -> bool:
	return _pressed_actions.has(action)


func clear_transient() -> void:
	jump_pressed = false
	jump_released = false
	_pressed_actions.clear()
