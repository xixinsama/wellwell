extends Node

## Board-level coverage for scoped Z undo / R reset and multiple boards.

const PuzzleBoard := preload("res://scripts/puzzle/view/puzzle_board.gd")
const PuzzlePiece := preload("res://scripts/puzzle/view/puzzle_piece.gd")
const PuzzleMove := preload("res://scripts/puzzle/core/puzzle_move.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_input_actions(failures)
	_assert_board_scope(failures)
	_assert_overlapping_boards_both_react(failures)
	_assert_reset_is_undoable_on_board(failures)
	_assert_undo_priority(failures)
	_assert_jump_mode_ignores_history(failures)
	return failures


func _assert_input_actions(failures: Array[String]) -> void:
	if not InputMap.has_action("undo") or not InputMap.has_action("reset"):
		failures.append("undo/reset input actions are missing")
		return
	if _action_keycode("undo") != KEY_Z:
		failures.append("undo is not bound to Z")
	if _action_keycode("reset") != KEY_R:
		failures.append("reset is not bound to R")


func _action_keycode(action: StringName) -> Key:
	for event in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key != null and key.physical_keycode != KEY_NONE:
			return key.physical_keycode
	return KEY_NONE


func _assert_board_scope(failures: Array[String]) -> void:
	var player := _make_player()
	var active := _make_board(Vector2.ZERO)
	var inactive := _make_board(Vector2(200.0, 0.0))
	active.set("_player", player)
	inactive.set("_player", player)
	active.call("set_player_to_cell", Vector2i(3, 1))
	active.call("_enter_drag_mode")
	inactive.call("_enter_drag_mode")
	active.get("session").try_move(PuzzleMove.new(0, Vector2i(1, 1), Vector2i(2, 1)))

	if not active.call("_is_player_inside_board_rect"):
		failures.append("active board did not contain the player")
	if inactive.call("_is_player_inside_board_rect"):
		failures.append("inactive board considered the player inside its rect")

	_press_and_process(&"undo", [active, inactive])
	if active.get("session").current_state.get_piece(0).cell != Vector2i(1, 1):
		failures.append("Z did not undo the active board")
	if inactive.get("session").current_state.get_piece(0).cell != Vector2i(1, 1):
		failures.append("inactive board history changed on Z")
	active.get("session").try_move(PuzzleMove.new(0, Vector2i(1, 1), Vector2i(2, 1)))

	_press_and_process(&"reset", [active, inactive])
	if active.get("session").current_state.get_piece(0).cell != Vector2i(1, 1):
		failures.append("R did not reset the active board")
	_press_and_process(&"undo", [active, inactive])
	if active.get("session").current_state.get_piece(0).cell != Vector2i(2, 1):
		failures.append("Z after R did not restore the pre-reset board")

	active.free()
	inactive.free()
	player.free()


func _assert_overlapping_boards_both_react(failures: Array[String]) -> void:
	var player := _make_player()
	var first := _make_board(Vector2.ZERO)
	var second := _make_board(Vector2.ZERO)
	for board in [first, second]:
		board.set("_player", player)
		board.call("set_player_to_cell", Vector2i(3, 1))
		board.call("_enter_drag_mode")
		board.get("session").try_move(PuzzleMove.new(0, Vector2i(1, 1), Vector2i(2, 1)))
	_press_and_process(&"reset", [first, second])
	for board in [first, second]:
		if board.get("session").current_state.get_piece(0).cell != Vector2i(1, 1):
			failures.append("an overlapping board did not react to R")
	_press_and_process(&"undo", [first, second])
	for board in [first, second]:
		if board.get("session").current_state.get_piece(0).cell != Vector2i(2, 1):
			failures.append("an overlapping board did not undo its reset")
	first.free()
	second.free()
	player.free()


func _assert_reset_is_undoable_on_board(failures: Array[String]) -> void:
	var player := _make_player()
	var board := _make_board(Vector2.ZERO)
	board.set("_player", player)
	board.call("set_player_to_cell", Vector2i(3, 1))
	board.call("_enter_drag_mode")
	board.get("session").try_move(PuzzleMove.new(0, Vector2i(1, 1), Vector2i(2, 1)))
	board.call("_reset_puzzle")
	if board.get("session").current_state.get_piece(0).cell != Vector2i(1, 1):
		failures.append("_reset_puzzle did not restore the authored state")
	board.call("_undo")
	if board.get("session").current_state.get_piece(0).cell != Vector2i(2, 1):
		failures.append("_undo did not restore the pre-reset state")
	if board.get("session").get_move_count() != 1:
		failures.append("_undo after reset did not restore the move count")
	board.free()
	player.free()


func _assert_undo_priority(failures: Array[String]) -> void:
	var player := _make_player()
	var board := _make_board(Vector2.ZERO)
	board.set("_player", player)
	board.call("set_player_to_cell", Vector2i(3, 1))
	board.call("_enter_drag_mode")
	var session: PuzzleSession = board.get("session")
	session.try_move(PuzzleMove.new(0, Vector2i(1, 1), Vector2i(2, 1)))
	session.try_move(PuzzleMove.new(0, Vector2i(2, 1), Vector2i(3, 1)))
	board.call("_handle_history_input", true, true)
	if session.current_state.get_piece(0).cell != Vector2i(2, 1):
		failures.append("Z did not take priority over R when both were pressed")
	board.free()
	player.free()


func _assert_jump_mode_ignores_history(failures: Array[String]) -> void:
	var player := _make_player()
	var board := _make_board(Vector2.ZERO)
	board.set("_player", player)
	board.call("set_player_to_cell", Vector2i(3, 1))
	var session: PuzzleSession = board.get("session")
	session.try_move(PuzzleMove.new(0, Vector2i(1, 1), Vector2i(2, 1)))
	board.call("_handle_history_input", true, true)
	if session.current_state.get_piece(0).cell != Vector2i(2, 1):
		failures.append("jump mode consumed Z/R history input")
	board.free()
	player.free()


func _make_board(origin: Vector2) -> PuzzleBoard:
	var board := PuzzleBoard.new()
	board.board_size = Vector2i(6, 3)
	board.cell_size = 8
	board.position = origin
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
	return board


func _make_player() -> Node2D:
	var player := Node2D.new()
	player.add_to_group("player")
	add_child(player)
	return player


func _press_and_process(action: StringName, boards: Array) -> void:
	var undo_pressed := action == &"undo"
	var reset_pressed := action == &"reset"
	for board in boards:
		board.call("_handle_history_input", undo_pressed, reset_pressed)
