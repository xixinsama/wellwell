extends Node

## Piece enable flag coverage: disabled pieces cannot be controlled, but a
## disabled void slider can still be moved by an A+ induced turn.

const PieceDefinition := preload("res://scripts/puzzle/definition/piece_definition.gd")
const PuzzleDefinition := preload("res://scripts/puzzle/definition/puzzle_definition.gd")
const PuzzleMove := preload("res://scripts/puzzle/core/puzzle_move.gd")
const PuzzleSession := preload("res://scripts/puzzle/systems/puzzle_session.gd")
const SlidingPuzzleRuleSet := preload("res://scripts/puzzle/rules/sliding_puzzle_rule_set.gd")
const PuzzleBoard := preload("res://scripts/puzzle/view/puzzle_board.gd")
const PuzzlePiece := preload("res://scripts/puzzle/view/puzzle_piece.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_disabled_piece_cannot_move(failures)
	_assert_disabled_piece_still_blocks(failures)
	_assert_disabled_void_can_be_pushed(failures)
	_assert_disabled_void_cannot_move_itself(failures)
	_assert_board_propagates_enable(failures)
	return failures


func _assert_disabled_piece_cannot_move(failures: Array[String]) -> void:
	var piece := _piece(&"normal", Vector2i.ONE, Vector2i(1, 1), false)
	piece.enable = false
	var def := _definition(Vector2i(4, 3), [piece])
	var rules := SlidingPuzzleRuleSet.new(def)
	var state := PuzzleSession.new(def).current_state
	if rules.can_apply_move(state, PuzzleMove.new(0, Vector2i(1, 1), Vector2i(2, 1))):
		failures.append("disabled piece accepted an active move")
	if not rules.get_legal_moves(state).is_empty():
		failures.append("disabled piece appeared in legal move generation")


func _assert_disabled_piece_still_blocks(failures: Array[String]) -> void:
	var mover := _piece(&"mover", Vector2i(1, 1), Vector2i(0, 1), false)
	var disabled := _piece(&"disabled", Vector2i.ONE, Vector2i(1, 1), false)
	disabled.enable = false
	var def := _definition(Vector2i(4, 3), [mover, disabled])
	var rules := SlidingPuzzleRuleSet.new(def)
	var state := PuzzleSession.new(def).current_state
	if rules.can_apply_move(state, PuzzleMove.new(0, Vector2i(0, 1), Vector2i(1, 1))):
		failures.append("disabled piece stopped blocking its cells")


func _assert_disabled_void_can_be_pushed(failures: Array[String]) -> void:
	var mover := _piece(
		&"mover",
		Vector2i(2, 1),
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)],
		false
	)
	mover.x_move_distance = 2
	var hole := _piece(&"hole", Vector2i(4, 1), Vector2i(2, 2), true)
	hole.enable = false
	var def := _definition(Vector2i(8, 4), [mover, hole])
	var rules := SlidingPuzzleRuleSet.new(def)
	var state := PuzzleSession.new(def).current_state
	var turn := rules.resolve_turn(state, PuzzleMove.new(0, Vector2i(2, 1), Vector2i(4, 1)))
	if turn == null:
		failures.append("disabled void blocked its inducing move")
	elif turn.moves.size() != 2 or turn.moves[1].piece_index != 1:
		failures.append("disabled void was not moved by the induced turn")


func _assert_disabled_void_cannot_move_itself(failures: Array[String]) -> void:
	var hole := _piece(&"hole", Vector2i(1, 1), Vector2i.ONE, true)
	hole.enable = false
	var def := _definition(Vector2i(4, 3), [hole])
	var rules := SlidingPuzzleRuleSet.new(def)
	var state := PuzzleSession.new(def).current_state
	if rules.can_apply_move(state, PuzzleMove.new(0, Vector2i(1, 1), Vector2i(2, 1))):
		failures.append("disabled void accepted an active move")


func _assert_board_propagates_enable(failures: Array[String]) -> void:
	var board := PuzzleBoard.new()
	board.board_size = Vector2i(6, 3)
	board.cell_size = 8
	var piece := PuzzlePiece.new()
	piece.cell_size = 8
	piece.enable = false
	piece.position = Vector2(8.0, 8.0)
	piece.polygon = PackedVector2Array([
		Vector2.ZERO,
		Vector2(8.0, 0.0),
		Vector2(8.0, 8.0),
		Vector2(0.0, 8.0),
	])
	board.add_child(piece)
	add_child(board)
	var definition: PuzzleDefinition = board.get("definition")
	if definition == null or definition.pieces.is_empty():
		failures.append("board did not build a definition for the enable test")
	elif definition.pieces[0].enable:
		failures.append("board did not copy PuzzlePiece.enable into the definition")
	if board.call("_can_drag_piece", piece):
		failures.append("disabled piece was still considered controllable")
	board.call("_select_piece", piece)
	if board.get("_selected_piece") != null:
		failures.append("disabled piece was selected")
	board.call("_move_piece_to", piece, Vector2i.RIGHT)
	if board.get("session").current_state.get_piece(0).cell != Vector2i(1, 1):
		failures.append("disabled piece moved through a direct board call")
	board.free()


func _definition(size: Vector2i, pieces: Array) -> PuzzleDefinition:
	var def := PuzzleDefinition.new()
	def.board.board_size = size
	def.pieces.assign(pieces)
	return def


func _piece(id: StringName, cell: Vector2i, shape: Variant, is_void: bool) -> PieceDefinition:
	var piece := PieceDefinition.new()
	piece.id = id
	piece.initial_cell = cell
	piece.is_void = is_void
	piece.movement_mode = PieceDefinition.MovementMode.FREE
	if shape is Vector2i:
		piece.shape = PieceDefinition.make_rect_shape(shape)
	else:
		piece.shape.assign(shape)
	return piece
