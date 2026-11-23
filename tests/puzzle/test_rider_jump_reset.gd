extends Node

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
