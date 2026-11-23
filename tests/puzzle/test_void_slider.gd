extends Node

## Void slider coverage: A+ induced moves, atomic rejection, and undo/reset.

const PieceDefinition := preload("res://scripts/puzzle/definition/piece_definition.gd")
const PuzzleDefinition := preload("res://scripts/puzzle/definition/puzzle_definition.gd")
const PuzzleMove := preload("res://scripts/puzzle/core/puzzle_move.gd")
const PuzzleSession := preload("res://scripts/puzzle/systems/puzzle_session.gd")
const SlidingPuzzleRuleSet := preload("res://scripts/puzzle/rules/sliding_puzzle_rule_set.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_void_does_not_block_normal_pieces(failures)
	_assert_partial_overlap_does_not_push(failures)
	_assert_full_bbox_pushes_void(failures)
	_assert_blocked_void_target_rejects_turn(failures)
	_assert_player_cell_blocks_void_target(failures)
	_assert_void_target_may_overlap_normal_piece(failures)
	_assert_no_push_chain(failures)
	_assert_void_primary_does_not_push(failures)
	_assert_void_primary_respects_blocked_cells(failures)
	_assert_compound_turn_undo_redo(failures)
	_assert_reset_is_undoable(failures)
	return failures


func _assert_void_does_not_block_normal_pieces(failures: Array[String]) -> void:
	var mover := _piece(&"mover", Vector2i(2, 0), Vector2i.ONE, false, 1, 1)
	var hole := _piece(&"hole", Vector2i(2, 1), Vector2i(2, 2), true, 1, 1)
	var def := _definition(Vector2i(6, 4), [mover, hole])
	var rules := SlidingPuzzleRuleSet.new(def)
	var state := PuzzleSession.new(def).current_state
	var turn := rules.resolve_turn(state, PuzzleMove.new(0, Vector2i(2, 0), Vector2i(2, 1)))
	if turn == null:
		failures.append("a normal piece was blocked by a void footprint")
	elif turn.moves.size() != 1:
		failures.append("partial overlap with a void footprint should not push the void")
	elif state.get_piece(1).cell != Vector2i(2, 1):
		failures.append("partial overlap moved the void piece")


func _assert_partial_overlap_does_not_push(failures: Array[String]) -> void:
	var mover := _piece(&"mover", Vector2i(2, 1), Vector2i(2, 2), false, 1, 1)
	var hole := _piece(&"hole", Vector2i(4, 1), Vector2i(2, 2), true, 1, 1)
	var def := _definition(Vector2i(8, 4), [mover, hole])
	var rules := SlidingPuzzleRuleSet.new(def)
	var state := PuzzleSession.new(def).current_state
	var turn := rules.resolve_turn(state, PuzzleMove.new(0, Vector2i(2, 1), Vector2i(3, 1)))
	if turn == null:
		failures.append("the mover was blocked instead of overlapping the void")
	elif turn.moves.size() != 1:
		failures.append("a partially covering mover pushed the void")


func _assert_full_bbox_pushes_void(failures: Array[String]) -> void:
	# A hollow mover still pushes because A+ uses the minimum rectangle.
	var mover := _piece(
		&"mover",
		Vector2i(2, 1),
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)],
		false,
		2,
		1
	)
	var hole := _piece(&"hole", Vector2i(4, 1), Vector2i(2, 2), true, 2, 1)
	var def := _definition(Vector2i(8, 4), [mover, hole])
	var rules := SlidingPuzzleRuleSet.new(def)
	var state := PuzzleSession.new(def).current_state
	var turn := rules.resolve_turn(state, PuzzleMove.new(0, Vector2i(2, 1), Vector2i(4, 1)))
	if turn == null:
		failures.append("a fully covering move did not resolve")
	elif turn.moves.size() != 2:
		failures.append("a fully covering move did not push the void")
	elif turn.moves[1].piece_index != 1:
		failures.append("the induced move was not attributed to the void piece")
	elif turn.moves[1].from_cell != Vector2i(4, 1) or turn.moves[1].to_cell != Vector2i(2, 1):
		failures.append("the void did not move opposite to the primary move")


func _assert_blocked_void_target_rejects_turn(failures: Array[String]) -> void:
	var mover := _piece(
		&"mover",
		Vector2i(2, 1),
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)],
		false,
		2,
		1
	)
	var hole := _piece(&"hole", Vector2i(4, 1), Vector2i(2, 2), true, 2, 1)
	var def := _definition(Vector2i(8, 4), [mover, hole])
	def.board.blocked_cells = [Vector2i(3, 2)]
	var rules := SlidingPuzzleRuleSet.new(def)
	var state := PuzzleSession.new(def).current_state
	var session := PuzzleSession.new(def)
	var move := PuzzleMove.new(0, Vector2i(2, 1), Vector2i(4, 1))
	if rules.resolve_turn(state, move) != null:
		failures.append("a void destination containing a blocked cell was accepted")
	if session.try_move(move):
		failures.append("a blocked induced void move still committed the primary move")
	if session.current_state.get_piece(0).cell != Vector2i(2, 1):
		failures.append("the primary mover moved even though the turn was invalid")
	if session.get_move_count() != 0:
		failures.append("an invalid turn incremented the move count")


func _assert_player_cell_blocks_void_target(failures: Array[String]) -> void:
	var mover := _piece(&"mover", Vector2i(2, 1), Vector2i(2, 2), false, 2, 1)
	var hole := _piece(&"hole", Vector2i(4, 1), Vector2i(2, 2), true, 2, 1)
	var def := _definition(Vector2i(8, 4), [mover, hole])
	var rules := SlidingPuzzleRuleSet.new(def)
	var state := PuzzleSession.new(def).current_state
	var move := PuzzleMove.new(0, Vector2i(2, 1), Vector2i(4, 1))
	if rules.resolve_turn(state, move, [], Vector2i(3, 2)) != null:
		failures.append("the player's post-move cell did not block the void")


func _assert_void_target_may_overlap_normal_piece(failures: Array[String]) -> void:
	var mover := _piece(
		&"mover",
		Vector2i(2, 1),
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)],
		false,
		2,
		1
	)
	var hole := _piece(&"hole", Vector2i(4, 1), Vector2i(2, 2), true, 2, 1)
	var bystander := _piece(&"bystander", Vector2i(3, 2), Vector2i.ONE, false, 1, 1)
	var def := _definition(Vector2i(8, 4), [mover, hole, bystander])
	var rules := SlidingPuzzleRuleSet.new(def)
	var state := PuzzleSession.new(def).current_state
	var turn := rules.resolve_turn(state, PuzzleMove.new(0, Vector2i(2, 1), Vector2i(4, 1)))
	if turn == null or turn.moves.size() != 2:
		failures.append("a void target overlapping a normal piece was rejected")


func _assert_no_push_chain(failures: Array[String]) -> void:
	var mover := _piece(&"mover", Vector2i(1, 1), Vector2i(3, 2), false, 1, 1)
	var hole := _piece(&"hole", Vector2i(3, 1), Vector2i.ONE, true, 1, 1)
	var def := _definition(Vector2i(8, 4), [mover, hole])
	var rules := SlidingPuzzleRuleSet.new(def)
	var state := PuzzleSession.new(def).current_state
	var turn := rules.resolve_turn(state, PuzzleMove.new(0, Vector2i(1, 1), Vector2i(2, 1)))
	if turn == null:
		failures.append("no-chain fixture failed to resolve")
	elif turn.moves.size() != 2:
		failures.append("a void that stayed covered moved more than once")
	elif turn.moves[1].to_cell != Vector2i(2, 1):
		failures.append("a void push chained into a second move")


func _assert_void_primary_does_not_push(failures: Array[String]) -> void:
	var hole := _piece(&"hole", Vector2i(2, 1), Vector2i.ONE, true, 1, 1)
	var normal := _piece(&"normal", Vector2i(3, 1), Vector2i.ONE, false, 1, 1)
	var def := _definition(Vector2i(5, 3), [hole, normal])
	var session := PuzzleSession.new(def)
	if not session.try_move(PuzzleMove.new(0, Vector2i(2, 1), Vector2i(3, 1))):
		failures.append("a void primary move was blocked by a normal piece")
	elif session.current_state.get_piece(1).cell != Vector2i(3, 1):
		failures.append("a void primary move pushed a normal piece")
	elif session.get_move_count() != 1:
		failures.append("a void primary move did not count as one turn")


func _assert_void_primary_respects_blocked_cells(failures: Array[String]) -> void:
	var hole := _piece(&"hole", Vector2i(2, 1), Vector2i.ONE, true, 1, 1)
	var def := _definition(Vector2i(5, 3), [hole])
	def.board.blocked_cells = [Vector2i(3, 1)]
	var session := PuzzleSession.new(def)
	if session.try_move(PuzzleMove.new(0, Vector2i(2, 1), Vector2i(3, 1))):
		failures.append("a void primary move entered a blocked cell")


func _assert_compound_turn_undo_redo(failures: Array[String]) -> void:
	var session := _make_push_session()
	if not session.try_move(PuzzleMove.new(0, Vector2i(2, 1), Vector2i(4, 1))):
		failures.append("compound fixture move failed")
		return
	if session.current_state.get_piece(0).cell != Vector2i(4, 1):
		failures.append("primary piece did not end at its destination")
	if session.current_state.get_piece(1).cell != Vector2i(2, 1):
		failures.append("void piece did not end at its induced destination")
	if session.get_move_count() != 1:
		failures.append("a compound turn counted as more than one move")
	if not session.undo():
		failures.append("undo rejected a compound turn")
	elif session.current_state.get_piece(0).cell != Vector2i(2, 1) or session.current_state.get_piece(1).cell != Vector2i(4, 1):
		failures.append("undo did not restore both pieces")
	elif session.get_move_count() != 0:
		failures.append("undo did not restore the move count")
	if not session.redo():
		failures.append("redo rejected a compound turn")
	elif session.current_state.get_piece(0).cell != Vector2i(4, 1) or session.current_state.get_piece(1).cell != Vector2i(2, 1):
		failures.append("redo did not restore both pieces")


func _assert_reset_is_undoable(failures: Array[String]) -> void:
	var session := _make_push_session()
	if not session.try_move(PuzzleMove.new(0, Vector2i(2, 1), Vector2i(4, 1))):
		failures.append("reset fixture move failed")
		return
	if not session.reset():
		failures.append("reset rejected a moved board")
		return
	if session.current_state.get_piece(0).cell != Vector2i(2, 1) or session.current_state.get_piece(1).cell != Vector2i(4, 1):
		failures.append("reset did not restore the authored cells")
	if session.get_move_count() != 0:
		failures.append("reset did not clear the move count")
	if not session.undo():
		failures.append("reset was not undoable")
	elif session.current_state.get_piece(0).cell != Vector2i(4, 1) or session.current_state.get_piece(1).cell != Vector2i(2, 1):
		failures.append("undo after reset did not restore the pre-reset board")
	elif session.get_move_count() != 1:
		failures.append("undo after reset did not restore the pre-reset move count")


func _make_push_session() -> PuzzleSession:
	var mover := _piece(&"mover", Vector2i(2, 1), Vector2i(2, 2), false, 2, 1)
	var hole := _piece(&"hole", Vector2i(4, 1), Vector2i(2, 2), true, 2, 1)
	return PuzzleSession.new(_definition(Vector2i(8, 4), [mover, hole]))


func _definition(board_size: Vector2i, pieces: Array) -> PuzzleDefinition:
	var def := PuzzleDefinition.new()
	def.board.board_size = board_size
	for piece: PieceDefinition in pieces:
		def.pieces.append(piece)
	return def


func _piece(
	id: StringName,
	cell: Vector2i,
	cells: Variant,
	is_void: bool,
	x_distance: int,
	y_distance: int
) -> PieceDefinition:
	var piece := PieceDefinition.new()
	piece.id = id
	piece.initial_cell = cell
	piece.is_void = is_void
	piece.movement_mode = PieceDefinition.MovementMode.FREE
	piece.x_move_distance = x_distance
	piece.y_move_distance = y_distance
	if cells is Vector2i:
		piece.shape = PieceDefinition.make_rect_shape(cells)
	else:
		piece.shape.assign(cells)
	return piece
