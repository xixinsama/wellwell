extends Node

## Gamepad slider selection: action contract, auto-selection, cycling,
## rider shortcut, cancel, reset, and inactive-board scoping.

const PuzzleBoard := preload("res://scripts/puzzle/view/puzzle_board.gd")
const PuzzlePiece := preload("res://scripts/puzzle/view/puzzle_piece.gd")
const PieceDefinition := preload("res://scripts/puzzle/definition/piece_definition.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_gamepad_bindings(failures)
	return failures


func _assert_gamepad_bindings(failures: Array[String]) -> void:
	_assert_joy_button(failures, &"slider_prev", JOY_BUTTON_LEFT_SHOULDER)
	_assert_joy_button(failures, &"slider_next", JOY_BUTTON_RIGHT_SHOULDER)
	_assert_joy_button(failures, &"slider_select_rider", JOY_BUTTON_A)
	_assert_joy_button(failures, &"slider_cancel", JOY_BUTTON_B)
	_assert_joy_button(failures, &"undo", JOY_BUTTON_BACK)
	_assert_joy_button(failures, &"reset", JOY_BUTTON_START)
	_assert_joy_button(failures, &"switch_mode", JOY_BUTTON_Y)
	_assert_key(failures, &"undo", KEY_Z)
	_assert_key(failures, &"reset", KEY_R)
	_assert_key(failures, &"switch_mode", KEY_TAB)


func _assert_joy_button(failures: Array[String], action: StringName, button: int) -> void:
	if not InputMap.has_action(action):
		failures.append("missing gamepad action: %s" % action)
		return
	for event: InputEvent in InputMap.action_get_events(action):
		var joy := event as InputEventJoypadButton
		if joy != null and joy.button_index == button:
			return
	failures.append("%s is not bound to joypad button %d" % [action, button])


func _assert_key(failures: Array[String], action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		failures.append("missing keyboard action: %s" % action)
		return
	for event: InputEvent in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key != null and (key.keycode == keycode or key.physical_keycode == keycode):
			return
	failures.append("%s lost its %s keyboard binding" % [action, keycode])
