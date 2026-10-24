extends Node

## Right-stick aim target selection and release-to-switch behavior.

const PuzzleBoard := preload("res://scripts/puzzle/view/puzzle_board.gd")
const PuzzlePiece := preload("res://scripts/puzzle/view/puzzle_piece.gd")
const PieceDefinition := preload("res://scripts/puzzle/definition/piece_definition.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_aim_bindings(failures)
	return failures


func _assert_aim_bindings(failures: Array[String]) -> void:
	_assert_joy_axis(failures, &"aim_left", JOY_AXIS_RIGHT_X, -1.0)
	_assert_joy_axis(failures, &"aim_right", JOY_AXIS_RIGHT_X, 1.0)
	_assert_joy_axis(failures, &"aim_up", JOY_AXIS_RIGHT_Y, -1.0)
	_assert_joy_axis(failures, &"aim_down", JOY_AXIS_RIGHT_Y, 1.0)


func _assert_joy_axis(
	failures: Array[String],
	action: StringName,
	axis: JoyAxis,
	value: float
) -> void:
	if not InputMap.has_action(action):
		failures.append("missing aim action: %s" % action)
		return
	for event: InputEvent in InputMap.action_get_events(action):
		var motion := event as InputEventJoypadMotion
		if motion != null and motion.axis == axis and is_equal_approx(motion.axis_value, value):
			return
	failures.append("%s is not bound to right-stick axis %d value %.1f" % [action, axis, value])
