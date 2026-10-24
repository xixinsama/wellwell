extends Node

## Right-stick aim target selection and release-to-switch behavior.

const PuzzleBoard := preload("res://scripts/puzzle/view/puzzle_board.gd")
const PuzzlePiece := preload("res://scripts/puzzle/view/puzzle_piece.gd")
const PieceDefinition := preload("res://scripts/puzzle/definition/piece_definition.gd")
const PuzzleSession := preload("res://scripts/puzzle/systems/puzzle_session.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_aim_bindings(failures)
	_assert_right_target_and_arrow(failures)
	_assert_release_switches(failures)
	_assert_no_target_release(failures)
	_assert_cancel_discards_target(failures)
	_assert_mode_exit_discards_target(failures)
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


func _assert_right_target_and_arrow(failures: Array[String]) -> void:
	var fixture := _make_board()
	var board: PuzzleBoard = fixture.board
	board.call("_enter_drag_mode")
	board.call("_handle_stick_selection", Vector2.RIGHT)
	var target: PuzzlePiece = board.get("_stick_target")
	if target != board.get("_pieces")[2]:
		failures.append("right aim did not skip the disabled piece to the nearest enabled piece")
	var arrow = board.get("_aim_arrow")
	if arrow == null or not arrow.visible:
		failures.append("right aim did not show the arrow")
	else:
		var points: PackedVector2Array = arrow.call("get_aim_points")
		if points.size() != 2 or not points[0].is_equal_approx(Vector2(20, 12)):
			failures.append("aim arrow did not start at the selected piece center")
		if not points[1].is_equal_approx(Vector2(52, 12)):
			failures.append("aim arrow did not end at the target piece center")
	_cleanup(fixture)


func _assert_release_switches(failures: Array[String]) -> void:
	var fixture := _make_board()
	var board: PuzzleBoard = fixture.board
	board.call("_enter_drag_mode")
	board.call("_handle_stick_selection", Vector2.RIGHT)
	board.call("_handle_stick_selection", Vector2.ZERO)
	if board.get("_selected_piece") != board.get("_pieces")[2]:
		failures.append("releasing the stick did not switch to the aimed piece")
	var arrow = board.get("_aim_arrow")
	if arrow != null and arrow.visible:
		failures.append("releasing the stick left the aim arrow visible")
	var session: PuzzleSession = board.get("session")
	if session.get_move_count() != 0:
		failures.append("aim selection created a puzzle history entry")
	_cleanup(fixture)


func _assert_no_target_release(failures: Array[String]) -> void:
	var fixture := _make_board()
	var board: PuzzleBoard = fixture.board
	board.call("_enter_drag_mode")
	board.call("_handle_stick_selection", Vector2.UP)
	if board.get("_stick_target") != null:
		failures.append("up aim found a target when no piece was above")
	board.call("_handle_stick_selection", Vector2.ZERO)
	if board.get("_selected_piece") != board.get("_pieces")[0]:
		failures.append("release without a target changed the selection")
	_cleanup(fixture)


func _assert_cancel_discards_target(failures: Array[String]) -> void:
	var fixture := _make_board()
	var board: PuzzleBoard = fixture.board
	board.call("_enter_drag_mode")
	board.call("_handle_stick_selection", Vector2.RIGHT)
	board.call("_handle_selection_input", false, false, false, true)
	if board.get("_selected_piece") != null or board.get("_stick_target") != null:
		failures.append("cancel did not clear the pending aim target")
	board.call("_handle_stick_selection", Vector2.ZERO)
	if board.get("_selected_piece") != null:
		failures.append("release after cancel switched to a discarded target")
	_cleanup(fixture)


func _assert_mode_exit_discards_target(failures: Array[String]) -> void:
	var fixture := _make_board()
	var board: PuzzleBoard = fixture.board
	board.call("_enter_drag_mode")
	board.call("_handle_stick_selection", Vector2.RIGHT)
	board.call("_exit_drag_mode")
	var arrow = board.get("_aim_arrow")
	if board.get("_stick_target") != null or (arrow != null and arrow.visible):
		failures.append("mode exit did not clear the aim target and arrow")
	_cleanup(fixture)


func _make_board() -> Dictionary:
	var board := PuzzleBoard.new()
	board.board_size = Vector2i(10, 6)
	board.cell_size = 8
	var specs: Array[Dictionary] = [
		{"cell": Vector2i(2, 1), "enable": true, "mode": PieceDefinition.MovementMode.FREE},
		{"cell": Vector2i(4, 1), "enable": false, "mode": PieceDefinition.MovementMode.FREE},
		{"cell": Vector2i(6, 1), "enable": true, "mode": PieceDefinition.MovementMode.FREE},
		{"cell": Vector2i(2, 4), "enable": true, "mode": PieceDefinition.MovementMode.FREE},
		{"cell": Vector2i(8, 1), "enable": true, "mode": PieceDefinition.MovementMode.STATIC},
	]
	for spec: Dictionary in specs:
		var piece := PuzzlePiece.new()
		piece.cell_size = 8
		piece.position = Vector2(spec.cell) * 8.0
		piece.polygon = PackedVector2Array([
			Vector2.ZERO,
			Vector2(8.0, 0.0),
			Vector2(8.0, 8.0),
			Vector2(0.0, 8.0),
		])
		piece.enable = bool(spec.enable)
		piece.movement_mode = spec.mode
		board.add_child(piece)
	add_child(board)
	var player := Node2D.new()
	player.add_to_group("player")
	add_child(player)
	board.set("_player", player)
	board.call("set_player_to_cell", Vector2i(9, 5))
	return {"board": board, "player": player}


func _cleanup(fixture: Dictionary) -> void:
	(fixture.board as PuzzleBoard).free()
	(fixture.player as Node2D).free()
