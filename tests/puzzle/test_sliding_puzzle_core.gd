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
	_assert_target_only_move(failures)
	_assert_extra_blocked_cells(failures)
	_assert_axis_move_distance_generation(failures)
	_assert_rider_registration(failures)
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
		failures.append("multi-step slide onto an occupied target was accepted")


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
		failures.append("session accepted a move onto an occupied target")
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


func _assert_target_only_move(failures: Array[String]) -> void:
	var def := PuzzleDefinition.new()
	def.board.board_size = Vector2i(4, 1)
	def.board.blocked_cells.append(Vector2i(1, 0))
	def.board.blocked_cells.append(Vector2i(3, 0))
	var piece := PieceDefinition.new()
	piece.id = &"p"
	piece.shape = [Vector2i.ZERO]
	piece.initial_cell = Vector2i(0, 0)
	piece.x_move_distance = 2
	piece.y_move_distance = 2
	def.pieces.append(piece)

	var rules := SlidingPuzzleRuleSet.new(def)
	var state := PuzzleSession.new(def).current_state
	if not rules.can_apply_move(state, PuzzleMove.new(0, Vector2i(0, 0), Vector2i(2, 0))):
		failures.append("target-only move was rejected despite a free target past a blocked cell")
	if rules.can_apply_move(state, PuzzleMove.new(0, Vector2i(0, 0), Vector2i(3, 0))):
		failures.append("target-only move onto a blocked target was accepted")


func _assert_extra_blocked_cells(failures: Array[String]) -> void:
	var def := PuzzleDefinition.new()
	def.board.board_size = Vector2i(3, 1)
	var piece := PieceDefinition.new()
	piece.id = &"p"
	piece.shape = [Vector2i.ZERO]
	piece.initial_cell = Vector2i(0, 0)
	def.pieces.append(piece)

	var rules := SlidingPuzzleRuleSet.new(def)
	var state := PuzzleSession.new(def).current_state
	var move := PuzzleMove.new(0, Vector2i(0, 0), Vector2i(1, 0))
	if rules.can_apply_move(state, move, [Vector2i(1, 0)]):
		failures.append("player wall did not block a move onto its cell")
	if not rules.can_apply_move(state, move):
		failures.append("move was rejected without the player wall")


func _assert_axis_move_distance_generation(failures: Array[String]) -> void:
	var def := PuzzleDefinition.new()
	def.board.board_size = Vector2i(3, 1)
	var piece := PieceDefinition.new()
	piece.id = &"p"
	piece.shape = [Vector2i.ZERO]
	piece.initial_cell = Vector2i(0, 0)
	piece.x_move_distance = 2
	piece.y_move_distance = 1
	def.pieces.append(piece)

	var rules := SlidingPuzzleRuleSet.new(def)
	var state := PuzzleSession.new(def).current_state
	var moves := rules.get_legal_moves(state)
	if moves.size() != 1:
		failures.append("axis-distance piece should have 1 legal move, got %d" % moves.size())
	elif moves[0].get_distance() != 2:
		failures.append("horizontal move did not travel x_move_distance")
	# The board is one row tall, so a vertical move would leave it; use a taller
	# fixture to verify the Y distance independently.
	var tall := PuzzleDefinition.new()
	tall.board.board_size = Vector2i(1, 4)
	var tall_piece := PieceDefinition.new()
	tall_piece.id = &"p"
	tall_piece.shape = [Vector2i.ZERO]
	tall_piece.initial_cell = Vector2i(0, 0)
	tall_piece.x_move_distance = 2
	tall_piece.y_move_distance = 3
	tall.pieces.append(tall_piece)
	var tall_rules := SlidingPuzzleRuleSet.new(tall)
	var tall_state := PuzzleSession.new(tall).current_state
	var tall_moves := tall_rules.get_legal_moves(tall_state)
	if tall_moves.size() != 1:
		failures.append("axis-distance tall piece should have 1 legal move, got %d" % tall_moves.size())
	elif tall_moves[0].get_distance() != 3:
		failures.append("vertical move did not travel y_move_distance")


func _assert_rider_registration(failures: Array[String]) -> void:
	var def := PuzzleDefinition.new()
	def.board.board_size = Vector2i(3, 1)
	var a := PieceDefinition.new()
	a.id = &"a"
	a.shape = [Vector2i.ZERO]
	a.initial_cell = Vector2i(0, 0)
	def.pieces.append(a)
	var b := PieceDefinition.new()
	b.id = &"b"
	b.shape = [Vector2i.ZERO]
	b.initial_cell = Vector2i(2, 0)
	def.pieces.append(b)

	var rules := SlidingPuzzleRuleSet.new(def)
	var state := PuzzleSession.new(def).current_state
	var b_into_cell := PuzzleMove.new(1, Vector2i(2, 0), Vector2i(1, 0))
	if not rules.can_apply_move(state, b_into_cell):
		failures.append("piece could not move into an unregistered free cell")
	# Glue a rider to the right of A: it now occupies cell (1, 0).
	rules.set_rider(0, Vector2i(1, 0))
	if rules.can_apply_move(state, b_into_cell):
		failures.append("rider did not block another piece")
	if rules.can_apply_move(state, PuzzleMove.new(0, Vector2i(0, 0), Vector2i(1, 0))):
		failures.append("rider did not block its own piece's destination")
	rules.clear_rider()
	if not rules.can_apply_move(state, b_into_cell):
		failures.append("clearing the rider did not free the cell")
