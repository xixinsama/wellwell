extends Node

## Merged test suite. Every inner class below is one original test file,
## kept in its own class so fixtures and helper names stay isolated. Do not
## add logic here: split a class back into its own file when it grows.

## tests/puzzle/test_gamepad_selection.gd
class GamepadSelectionCase extends Node:
	## Gamepad slider selection: action contract, auto-selection, cycling,
	## rider shortcut, cancel, reset, and inactive-board scoping.

	const PuzzleBoard := preload("res://scripts/puzzle/view/puzzle_board.gd")
	const PuzzlePiece := preload("res://scripts/puzzle/view/puzzle_piece.gd")
	const PieceDefinition := preload("res://scripts/puzzle/definition/piece_definition.gd")
	const PuzzleSession := preload("res://scripts/puzzle/systems/puzzle_session.gd")


	func run() -> Array[String]:
		var failures: Array[String] = []
		_assert_gamepad_bindings(failures)
		_assert_initial_selection(failures)
		_assert_cycle_order(failures)
		_assert_rider_shortcut_and_cancel(failures)
		_assert_inactive_board(failures)
		_assert_reset_reselects(failures)
		_assert_selection_does_not_create_history(failures)
		_assert_process_wiring(failures)
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


	func _assert_initial_selection(failures: Array[String]) -> void:
		var fixture := _make_board(Vector2i(9, 5))
		var board: PuzzleBoard = fixture.board
		board.call("_enter_drag_mode")
		var selected: PuzzlePiece = board.get("_selected_piece")
		if selected != board.get("_pieces")[0]:
			failures.append("slider mode did not select the first eligible piece")
		_cleanup(fixture)

		fixture = _make_board(Vector2i(6, 0))
		board = fixture.board
		board.call("_enter_drag_mode")
		selected = board.get("_selected_piece")
		if selected != board.get("_pieces")[2]:
			failures.append("slider mode did not select the ridden piece")
		_cleanup(fixture)


	func _assert_cycle_order(failures: Array[String]) -> void:
		var fixture := _make_board(Vector2i(9, 5))
		var board: PuzzleBoard = fixture.board
		board.call("_enter_drag_mode")
		if not board.call("_handle_selection_input", false, true, false, false):
			failures.append("RB did not consume the next-piece input")
		var selected: PuzzlePiece = board.get("_selected_piece")
		if selected != board.get("_pieces")[2]:
			failures.append("RB did not skip the disabled piece")
		board.call("_handle_selection_input", false, true, false, false)
		if board.get("_selected_piece") != board.get("_pieces")[4]:
			failures.append("RB did not reach the enabled void piece")
		board.call("_handle_selection_input", false, true, false, false)
		if board.get("_selected_piece") != board.get("_pieces")[0]:
			failures.append("RB did not wrap to the first piece")
		board.call("_handle_selection_input", true, false, false, false)
		if board.get("_selected_piece") != board.get("_pieces")[4]:
			failures.append("LB did not wrap backward")
		_cleanup(fixture)


	func _assert_rider_shortcut_and_cancel(failures: Array[String]) -> void:
		var fixture := _make_board(Vector2i(6, 0))
		var board: PuzzleBoard = fixture.board
		board.call("_enter_drag_mode")
		board.call("_handle_selection_input", false, false, false, true)
		if board.get("_selected_piece") != null:
			failures.append("B did not clear the selection")
		board.call("_handle_selection_input", false, false, true, false)
		if board.get("_selected_piece") != board.get("_pieces")[2]:
			failures.append("A did not re-select the ridden piece")
		board.call("_handle_selection_input", false, false, false, true)
		if board.get("_selected_piece") != null:
			failures.append("B did not clear the rider shortcut selection")
		board.call("set_player_to_cell", Vector2i(9, 5))
		board.call("_handle_selection_input", false, false, true, false)
		if board.get("_selected_piece") != null:
			failures.append("A selected a piece when the player was not riding")
		_cleanup(fixture)


	func _assert_inactive_board(failures: Array[String]) -> void:
		var fixture := _make_board(Vector2i(20, 20))
		var board: PuzzleBoard = fixture.board
		board.call("_enter_drag_mode")
		if board.get("_selected_piece") != null:
			failures.append("inactive board auto-selected a piece")
		board.call("_handle_selection_input", false, true, true, false)
		if board.get("_selected_piece") != null:
			failures.append("inactive board accepted gamepad selection")
		_cleanup(fixture)


	func _assert_reset_reselects(failures: Array[String]) -> void:
		var fixture := _make_board(Vector2i(9, 5))
		var board: PuzzleBoard = fixture.board
		board.call("_enter_drag_mode")
		board.call("_handle_selection_input", false, true, false, false)
		if board.get("_selected_piece") != board.get("_pieces")[2]:
			failures.append("reset fixture did not select the second eligible piece")
		board.call("_reset_puzzle")
		if board.get("_selected_piece") != board.get("_pieces")[0]:
			failures.append("reset did not re-select the first eligible piece")
		_cleanup(fixture)


	func _assert_selection_does_not_create_history(failures: Array[String]) -> void:
		var fixture := _make_board(Vector2i(9, 5))
		var board: PuzzleBoard = fixture.board
		board.call("_enter_drag_mode")
		board.call("_handle_selection_input", false, true, false, false)
		var session: PuzzleSession = board.get("session")
		if session.get_move_count() != 0:
			failures.append("selection created a puzzle history entry")
		_cleanup(fixture)


	func _make_board(rider_at: Vector2i) -> Dictionary:
		var board := PuzzleBoard.new()
		board.board_size = Vector2i(10, 6)
		board.cell_size = 8
		var specs: Array[Dictionary] = [
			{"cell": Vector2i(2, 1), "enable": true, "mode": PieceDefinition.MovementMode.FREE, "void": false},
			{"cell": Vector2i(4, 1), "enable": false, "mode": PieceDefinition.MovementMode.FREE, "void": false},
			{"cell": Vector2i(6, 1), "enable": true, "mode": PieceDefinition.MovementMode.FREE, "void": false},
			{"cell": Vector2i(8, 1), "enable": true, "mode": PieceDefinition.MovementMode.STATIC, "void": false},
			{"cell": Vector2i(2, 4), "enable": true, "mode": PieceDefinition.MovementMode.FREE, "void": true},
			{"cell": Vector2i(4, 4), "enable": false, "mode": PieceDefinition.MovementMode.FREE, "void": true},
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
			piece.is_void = bool(spec.void)
			board.add_child(piece)
		add_child(board)
		var player := Node2D.new()
		player.name = "TestPlayer"
		player.add_to_group("player")
		add_child(player)
		board.set("_player", player)
		board.call("set_player_to_cell", rider_at)
		return {"board": board, "player": player}


	func _cleanup(fixture: Dictionary) -> void:
		(fixture.board as PuzzleBoard).free()
		(fixture.player as Node2D).free()


	func _assert_process_wiring(failures: Array[String]) -> void:
		var source := FileAccess.get_file_as_string("res://scripts/puzzle/view/puzzle_board.gd")
		for action: StringName in [
			&"prev_piece_action",
			&"next_piece_action",
			&"select_rider_action",
			&"cancel_selection_action",
		]:
			if not source.contains(String(action)):
				failures.append("PuzzleBoard is missing live action export %s" % action)
		if not source.contains("_handle_selection_input("):
			failures.append("PuzzleBoard does not call the selection input seam")
		for action: StringName in [
			&"prev_piece_action",
			&"next_piece_action",
			&"select_rider_action",
			&"cancel_selection_action",
		]:
			if not source.contains("Input.is_action_just_pressed(String(%s))" % action):
				failures.append("PuzzleBoard does not poll live action %s" % action)


## tests/puzzle/test_gamepad_stick_aim.gd
class GamepadStickAimCase extends Node:
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
		_assert_live_wiring(failures)
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


	func _assert_live_wiring(failures: Array[String]) -> void:
		var source := FileAccess.get_file_as_string("res://scripts/puzzle/view/puzzle_board.gd")
		if not source.contains("_read_stick_aim()"):
			failures.append("PuzzleBoard does not read the right-stick aim vector")
		for action: StringName in [
			&"aim_left_action",
			&"aim_right_action",
			&"aim_up_action",
			&"aim_down_action",
		]:
			if not source.contains(String(action)):
				failures.append("PuzzleBoard is missing live aim action %s" % action)
		if not source.contains("_handle_stick_selection(_read_stick_aim())"):
			failures.append("PuzzleBoard does not poll the right stick in _process")


## tests/puzzle/test_rider_jump_reset.gd
class RiderJumpResetCase extends Node:
	## A rider carried by a slider during drag mode earns exactly one mid-air jump
	## after leaving drag mode. Merely selecting a piece, a failed move, or a board
	## teardown must not grant it.

	const PuzzleBoard := preload("res://scripts/puzzle/view/puzzle_board.gd")
	const PuzzlePiece := preload("res://scripts/puzzle/view/puzzle_piece.gd")
	const PLAYER_FIXTURE := preload("res://tests/puzzle/rider_jump_player_fixture.gd")


	func run() -> Array[String]:
		var failures: Array[String] = []
		_assert_carried_move_grants_air_jump(failures)
		_assert_select_without_move_does_not_grant(failures)
		_assert_failed_move_does_not_grant(failures)
		_assert_blocked_exit_keeps_grant_for_next_exit(failures)
		_assert_reentry_requires_a_new_carry(failures)
		_assert_forced_exit_does_not_grant(failures)
		return failures


	func _assert_carried_move_grants_air_jump(failures: Array[String]) -> void:
		var fixture := _make_rider()
		var board := _make_board(fixture)
		board.call("_enter_drag_mode")
		board.call("_select_piece", _piece(board))
		board.call("_move_piece_to", _piece(board), Vector2i.RIGHT)
		if fixture.air_jump_grants != 0:
			failures.append("carried move granted the air jump before leaving drag mode")
		board.call("_exit_drag_mode")
		if fixture.air_jump_grants != 1:
			failures.append("a carried rider did not receive exactly one air jump")
		if fixture.control_locked:
			failures.append("leaving drag mode did not unlock the rider")
		_cleanup(board, fixture)


	func _assert_select_without_move_does_not_grant(failures: Array[String]) -> void:
		var fixture := _make_rider()
		var board := _make_board(fixture)
		board.call("_enter_drag_mode")
		board.call("_select_piece", _piece(board))
		board.call("_exit_drag_mode")
		if fixture.air_jump_grants != 0:
			failures.append("selecting a ridden piece without moving granted an air jump")
		_cleanup(board, fixture)


	func _assert_failed_move_does_not_grant(failures: Array[String]) -> void:
		var fixture := _make_rider()
		var board := _make_board(fixture, [Vector2i(0, 1)])
		board.call("_enter_drag_mode")
		board.call("_select_piece", _piece(board))
		# The author-placed wall blocks the left turn.
		board.call("_move_piece_to", _piece(board), Vector2i.LEFT)
		board.call("_exit_drag_mode")
		if fixture.air_jump_grants != 0:
			failures.append("a rejected slider move granted an air jump")
		_cleanup(board, fixture)


	func _assert_blocked_exit_keeps_grant_for_next_exit(failures: Array[String]) -> void:
		var fixture := _make_rider()
		var board := _make_board(fixture)
		board.call("_enter_drag_mode")
		board.call("_select_piece", _piece(board))
		board.call("_move_piece_to", _piece(board), Vector2i.RIGHT)
		board.call("set_player_to_cell", Vector2i(2, 1))
		board.call("_exit_drag_mode")
		if board.get("mode") != PuzzleBoard.ControlMode.DRAG or fixture.air_jump_grants != 0:
			failures.append("a blocked exit still granted the air jump")
		board.call("set_player_to_cell", Vector2i(1, 0))
		board.call("_exit_drag_mode")
		if fixture.air_jump_grants != 1:
			failures.append("the deferred air jump was lost after a blocked exit")
		_cleanup(board, fixture)


	func _assert_reentry_requires_a_new_carry(failures: Array[String]) -> void:
		var fixture := _make_rider()
		var board := _make_board(fixture)
		board.call("_enter_drag_mode")
		board.call("_select_piece", _piece(board))
		board.call("_move_piece_to", _piece(board), Vector2i.RIGHT)
		board.call("_exit_drag_mode")
		board.call("_enter_drag_mode")
		board.call("_exit_drag_mode")
		if fixture.air_jump_grants != 1:
			failures.append("re-entering drag mode without a carry granted another air jump")
		_cleanup(board, fixture)


	func _assert_forced_exit_does_not_grant(failures: Array[String]) -> void:
		var fixture := _make_rider()
		var board := _make_board(fixture)
		board.call("_enter_drag_mode")
		board.call("_select_piece", _piece(board))
		board.call("_move_piece_to", _piece(board), Vector2i.RIGHT)
		board.call("_exit_drag_mode", true)
		if fixture.air_jump_grants != 0:
			failures.append("force-exiting drag mode granted an air jump")
		_cleanup(board, fixture)


	func _make_rider() -> Node2D:
		var rider := PLAYER_FIXTURE.new() as Node2D
		rider.add_to_group("player")
		add_child(rider)
		return rider


	func _make_board(rider: Node2D, blocked: Array[Vector2i] = []) -> PuzzleBoard:
		var board := PuzzleBoard.new()
		board.board_size = Vector2i(6, 3)
		board.cell_size = 8
		board.blocked_cells = blocked
		var piece := PuzzlePiece.new()
		piece.cell_size = 8
		piece.position = Vector2(8.0, 8.0)
		piece.polygon = PackedVector2Array([
			Vector2.ZERO,
			Vector2(8.0, 0.0),
			Vector2(8.0, 8.0),
			Vector2(0.0, 8.0),
		])
		board.add_child(piece)
		add_child(board)
		board.set("_player", rider)
		board.call("set_player_to_cell", Vector2i(1, 0))
		return board


	func _piece(board: PuzzleBoard) -> PuzzlePiece:
		return board.get("_pieces")[0] as PuzzlePiece


	func _cleanup(board: PuzzleBoard, rider: Node2D) -> void:
		board.free()
		rider.free()


func run() -> Array[String]:
	var failures: Array[String] = []
	failures.append_array(_run_case(GamepadSelectionCase.new()))
	failures.append_array(_run_case(GamepadStickAimCase.new()))
	failures.append_array(_run_case(RiderJumpResetCase.new()))
	return failures


func _run_case(test: Node) -> Array[String]:
	add_child(test)
	var result: Array = test.call("run")
	test.queue_free()
	var failures: Array[String] = []
	failures.assign(result)
	return failures
