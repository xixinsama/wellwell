extends Node

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
