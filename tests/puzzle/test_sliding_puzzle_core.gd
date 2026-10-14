extends Node

## Pure-logic coverage for the Klotski core: occupancy, rules, moves and session.

const BoardOccupancy := preload("res://scripts/puzzle/core/board_occupancy.gd")
const BoardState := preload("res://scripts/puzzle/core/board_state.gd")
const PuzzleMove := preload("res://scripts/puzzle/core/puzzle_move.gd")
const PieceDefinition := preload("res://scripts/puzzle/definition/piece_definition.gd")
const PuzzleDefinition := preload("res://scripts/puzzle/definition/puzzle_definition.gd")
const SlidingPuzzleRuleSet := preload("res://scripts/puzzle/rules/sliding_puzzle_rule_set.gd")
const PuzzleSession := preload("res://scripts/puzzle/systems/puzzle_session.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_initial_state(failures)
	_assert_duplicate_state_is_independent(failures)
	_assert_hash_key_is_stable(failures)
	_assert_occupancy_out_of_bounds(failures)
	_assert_occupancy_overlap(failures)
	_assert_occupancy_blocked_cells(failures)
	_assert_move_validation(failures)
	_assert_movement_mode_restrictions(failures)
	_assert_apply_move_is_pure(failures)
	_assert_legal_move_generation(failures)
	_assert_session_flow(failures)
	_assert_solved_state(failures)
	_assert_free_form_shape_occupancy(failures)
	return failures


# --- Fixtures -----------------------------------------------------------------

func _make_classic() -> PuzzleDefinition:
	var def := PuzzleDefinition.new()
	def.board.board_size = Vector2i(4, 5)
	def.goal.piece_id = &"cao"
	def.goal.target_cell = Vector2i(1, 3)
	def.pieces.append(_piece(&"cao", Vector2i(2, 2), Vector2i(1, 0), PieceDefinition.MovementMode.FREE))
	def.pieces.append(_piece(&"guan", Vector2i(1, 2), Vector2i(0, 2), PieceDefinition.MovementMode.VERTICAL))
	def.pieces.append(_piece(&"zhang", Vector2i(1, 2), Vector2i(3, 2), PieceDefinition.MovementMode.VERTICAL))
	def.pieces.append(_piece(&"bing1", Vector2i(1, 1), Vector2i(0, 4), PieceDefinition.MovementMode.FREE))
	def.pieces.append(_piece(&"bing2", Vector2i(1, 1), Vector2i(1, 4), PieceDefinition.MovementMode.FREE))
	def.pieces.append(_piece(&"bing3", Vector2i(1, 1), Vector2i(2, 4), PieceDefinition.MovementMode.FREE))
	def.pieces.append(_piece(&"bing4", Vector2i(1, 1), Vector2i(3, 4), PieceDefinition.MovementMode.FREE))
	return def


func _make_small() -> PuzzleDefinition:
	var def := PuzzleDefinition.new()
	def.board.board_size = Vector2i(3, 2)
	def.pieces.append(_piece(&"h", Vector2i.ONE, Vector2i(0, 0), PieceDefinition.MovementMode.HORIZONTAL))
	def.pieces.append(_piece(&"v", Vector2i.ONE, Vector2i(2, 0), PieceDefinition.MovementMode.VERTICAL))
	def.pieces.append(_piece(&"s", Vector2i.ONE, Vector2i(1, 1), PieceDefinition.MovementMode.STATIC))
	return def


func _make_goal_fixture() -> PuzzleDefinition:
	var def := PuzzleDefinition.new()
	def.board.board_size = Vector2i(2, 1)
	def.goal.piece_id = &"a"
	def.goal.target_cell = Vector2i(1, 0)
	def.pieces.append(_piece(&"a", Vector2i.ONE, Vector2i(0, 0), PieceDefinition.MovementMode.FREE))
	return def


func _piece(id: StringName, size: Vector2i, cell: Vector2i, mode: PieceDefinition.MovementMode) -> PieceDefinition:
	var piece := PieceDefinition.new()
	piece.id = id
	piece.shape = PieceDefinition.make_rect_shape(size)
	piece.initial_cell = cell
	piece.movement_mode = mode
	return piece


# --- Assertions ---------------------------------------------------------------

func _assert_initial_state(failures: Array[String]) -> void:
	var session := PuzzleSession.new(_make_classic())
	var state := session.current_state
	if state.pieces.size() != 7:
		failures.append("classic fixture did not build 7 pieces")
	if state.get_piece(0).cell != Vector2i(1, 0) or state.get_piece(0).id != &"cao":
		failures.append("piece 0 did not start at the authored cell")
	if state.find_piece_index(&"zhang") != 2:
		failures.append("find_piece_index did not locate zhang")


func _assert_duplicate_state_is_independent(failures: Array[String]) -> void:
	var state := PuzzleSession.new(_make_classic()).current_state
	var copy := state.duplicate_state()
	copy.get_piece(0).cell = Vector2i(9, 9)
	if state.get_piece(0).cell == Vector2i(9, 9):
		failures.append("duplicate_state shared piece data with the original")


func _assert_hash_key_is_stable(failures: Array[String]) -> void:
	var session := PuzzleSession.new(_make_small())
	var key_a := session.current_state.get_hash_key()
	var rebuilt := PuzzleSession.new(_make_small()).current_state.get_hash_key()
	if key_a != rebuilt:
		failures.append("identical states produced different hash keys")
	session.try_move(PuzzleMove.new(0, Vector2i(0, 0), Vector2i(1, 0)))
	if session.current_state.get_hash_key() == key_a:
		failures.append("hash key did not change after a move")


func _assert_occupancy_out_of_bounds(failures: Array[String]) -> void:
	var def := _make_classic()
	var occupancy := BoardOccupancy.new(def)
	var state := PuzzleSession.new(def).current_state
	if occupancy.can_place_piece(state, 0, Vector2i(3, 4), 0):
		failures.append("2x2 piece was allowed to leave the board")
	if not occupancy.can_place_piece(state, 3, Vector2i(0, 0), 3):
		failures.append("1x1 piece was rejected from a free corner cell")


func _assert_occupancy_overlap(failures: Array[String]) -> void:
	var def := _make_classic()
	var occupancy := BoardOccupancy.new(def)
	var state := PuzzleSession.new(def).current_state
	# cao (2x2) slid onto guan (1x2 at 0,2) should collide.
	if occupancy.can_place_piece(state, 0, Vector2i(0, 2), 0):
		failures.append("occupancy allowed two pieces to overlap")


func _assert_occupancy_blocked_cells(failures: Array[String]) -> void:
	var def := _make_small()
	def.board.blocked_cells.append(Vector2i(0, 1))
	var occupancy := BoardOccupancy.new(def)
	var state := PuzzleSession.new(def).current_state
	if occupancy.can_place_piece(state, 0, Vector2i(0, 1), 0):
		failures.append("occupancy allowed a piece onto a blocked cell")


func _assert_move_validation(failures: Array[String]) -> void:
	var def := _make_classic()
	var rules := SlidingPuzzleRuleSet.new(def)
	var state := PuzzleSession.new(def).current_state

	if not rules.can_apply_move(state, PuzzleMove.new(0, Vector2i(1, 0), Vector2i(1, 1))):
		failures.append("valid single-step slide was rejected")
	if rules.can_apply_move(state, PuzzleMove.new(0, Vector2i(1, 0), Vector2i(2, 1))):
		failures.append("diagonal move was accepted")
	if rules.can_apply_move(state, PuzzleMove.new(0, Vector2i(1, 0), Vector2i(1, 0))):
		failures.append("zero-distance move was accepted")
	if rules.can_apply_move(state, PuzzleMove.new(0, Vector2i(1, 1), Vector2i(1, 2))):
		failures.append("move with a stale from_cell was accepted")
	if rules.can_apply_move(state, PuzzleMove.new(0, Vector2i(1, 0), Vector2i(1, 3))):
		failures.append("multi-step slide through a blocked path was accepted")


func _assert_movement_mode_restrictions(failures: Array[String]) -> void:
	var rules := SlidingPuzzleRuleSet.new(_make_small())
	var state := PuzzleSession.new(_make_small()).current_state

	if not rules.can_apply_move(state, PuzzleMove.new(0, Vector2i(0, 0), Vector2i(1, 0))):
		failures.append("horizontal piece could not slide right")
	if rules.can_apply_move(state, PuzzleMove.new(0, Vector2i(0, 0), Vector2i(0, 1))):
		failures.append("horizontal piece slid vertically")
	if rules.can_apply_move(state, PuzzleMove.new(1, Vector2i(2, 0), Vector2i(1, 0))):
		failures.append("vertical piece slid horizontally")
	if rules.can_apply_move(state, PuzzleMove.new(2, Vector2i(1, 1), Vector2i(0, 1))):
		failures.append("static piece was allowed to move")


func _assert_apply_move_is_pure(failures: Array[String]) -> void:
	var def := _make_classic()
	var rules := SlidingPuzzleRuleSet.new(def)
	var state := PuzzleSession.new(def).current_state
	var applied := rules.apply_move(state, PuzzleMove.new(0, Vector2i(1, 0), Vector2i(1, 1)))
	if state.get_piece(0).cell != Vector2i(1, 0):
		failures.append("apply_move mutated the input state")
	if applied.get_piece(0).cell != Vector2i(1, 1):
		failures.append("apply_move did not move the piece in the returned state")


func _assert_legal_move_generation(failures: Array[String]) -> void:
	var rules := SlidingPuzzleRuleSet.new(_make_small())
	var state := PuzzleSession.new(_make_small()).current_state
	var moves := rules.get_legal_moves(state)
	if moves.size() != 2:
		failures.append("small fixture should have exactly 2 legal moves, got %d" % moves.size())


func _assert_session_flow(failures: Array[String]) -> void:
	var session := PuzzleSession.new(_make_classic())
	if session.get_move_count() != 0:
		failures.append("fresh session had a non-zero move count")
	if session.is_solved():
		failures.append("fresh classic session reported solved")

	if not session.try_move(PuzzleMove.new(0, Vector2i(1, 0), Vector2i(1, 1))):
		failures.append("session rejected a valid move")
	if session.get_move_count() != 1:
		failures.append("session move count did not advance")
	if session.current_state.get_piece(0).cell != Vector2i(1, 1):
		failures.append("session did not apply the move to its state")

	if session.try_move(PuzzleMove.new(0, Vector2i(1, 1), Vector2i(1, 3))):
		failures.append("session accepted an invalid multi-step move")
	if session.get_move_count() != 1:
		failures.append("failed move changed the move count")

	if not session.undo() or session.current_state.get_piece(0).cell != Vector2i(1, 0):
		failures.append("undo did not restore the previous cell")
	if session.get_move_count() != 0:
		failures.append("undo did not decrease the move count")

	if not session.redo() or session.current_state.get_piece(0).cell != Vector2i(1, 1):
		failures.append("redo did not re-apply the move")

	session.reset()
	if session.get_move_count() != 0 or session.current_state.get_piece(0).cell != Vector2i(1, 0):
		failures.append("reset did not restore the initial state")


func _assert_solved_state(failures: Array[String]) -> void:
	var session := PuzzleSession.new(_make_goal_fixture())
	if session.is_solved():
		failures.append("goal fixture started solved")
	session.try_move(PuzzleMove.new(0, Vector2i(0, 0), Vector2i(1, 0)))
	if not session.is_solved():
		failures.append("goal fixture did not solve after reaching the target cell")


func _assert_free_form_shape_occupancy(failures: Array[String]) -> void:
	var def := PuzzleDefinition.new()
	def.board.board_size = Vector2i(3, 3)
	var l := PieceDefinition.new()
	l.id = &"l"
	l.shape = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]
	l.initial_cell = Vector2i.ZERO
	def.pieces.append(l)
	var unit := PieceDefinition.new()
	unit.id = &"unit"
	unit.shape = [Vector2i.ZERO]
	unit.initial_cell = Vector2i(2, 2)
	def.pieces.append(unit)

	var occupancy := BoardOccupancy.new(def)
	var state := PuzzleSession.new(def).current_state
	if occupancy.can_place_piece(state, 1, Vector2i(0, 1), 1):
		failures.append("free-form L-shape did not block an overlapping unit cell")
	if not occupancy.can_place_piece(state, 1, Vector2i(1, 1), 1):
		failures.append("free-form L-shape blocked a free cell inside its bounding box")
	if l.get_bounds() != Rect2i(Vector2i.ZERO, Vector2i(2, 2)):
		failures.append("free-form L-shape reported wrong bounds")
