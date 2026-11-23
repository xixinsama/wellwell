extends Node

## Merged test suite. Every inner class below is one original test file,
## kept in its own class so fixtures and helper names stay isolated. Do not
## add logic here: split a class back into its own file when it grows.

## tests/puzzle/test_sliding_puzzle_core.gd
class SlidingPuzzleCoreCase extends Node:
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


## tests/puzzle/test_puzzle_history.gd
class PuzzleHistoryCase extends Node:
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


## tests/puzzle/test_puzzle_tile_piece.gd
class PuzzleTilePieceCase extends Node:
	## Coverage for tile-authored sliding regions: footprint derivation, background
	## exclusion, board integration and the legacy polygon fallback.

	const TILESET := preload("res://resources/tilesets/primordial_tileset.tres")
	const TILE_PIECE_SCRIPT := preload("res://scripts/puzzle/view/puzzle_tile_piece.gd")


	func run() -> Array[String]:
		var failures: Array[String] = []
		_assert_footprint_uses_colliding_tiles(failures)
		_assert_board_scans_tile_piece(failures)
		_assert_void_layer_builds_player_body(failures)
		_assert_void_layer_wins_hybrid(failures)
		_assert_void_selection_priority(failures)
		_assert_polygon_fallback(failures)
		return failures


	func _assert_footprint_uses_colliding_tiles(failures: Array[String]) -> void:
		var piece := _make_tile_piece()
		piece.position = Vector2(16.0, 8.0)
		add_child(piece)

		var solid := piece.get_node("SolidTiles") as TileMapLayer
		var one_way := piece.get_node("OneWayTiles") as TileMapLayer
		var back := piece.get_node("BackTiles") as TileMapLayer
		# Wall + one-way platform: both have tileset physics and must count.
		solid.set_cell(Vector2i.ZERO, 0, Vector2i(0, 0))
		one_way.set_cell(Vector2i(1, 0), 0, Vector2i(1, 4))
		# Background tile painted on the solid layer has no physics: no footprint.
		solid.set_cell(Vector2i(2, 0), 0, Vector2i(0, 5))
		# Background layer alone never enlarges the footprint.
		back.set_cell(Vector2i(3, 0), 0, Vector2i(0, 5))
		piece.call("_refresh_from_polygon")

		if piece.get_logical_cell() != Vector2i(2, 1):
			failures.append("tile piece did not derive its anchor cell from its position")
		var expected: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0)]
		if piece.shape != expected:
			failures.append("tile piece footprint was not limited to colliding tiles: %s" % [piece.shape])
		if piece.get_bounds() != Rect2i(0, 0, 2, 1):
			failures.append("tile piece bounds followed non-colliding background cells")
		if piece.wall_shape != [Vector2i.ZERO]:
			failures.append("tile piece wall classification was wrong: %s" % [piece.wall_shape])
		if piece.one_way_shape != [Vector2i(1, 0)]:
			failures.append("tile piece one-way classification was wrong: %s" % [piece.one_way_shape])

		solid.set_cell(Vector2i(0, 1), 0, Vector2i(0, 0))
		piece.call("_refresh_from_polygon")
		if not piece.shape.has(Vector2i(0, 1)):
			failures.append("tile piece footprint did not refresh after painting a wall")
		if not piece.wall_shape.has(Vector2i(0, 1)):
			failures.append("tile piece did not classify the new wall cell")
		if piece.one_way_shape.has(Vector2i(0, 1)):
			failures.append("tile piece classified a wall cell as one-way")
		if piece.shape.has(Vector2i(2, 0)) or piece.shape.has(Vector2i(3, 0)):
			failures.append("tile piece footprint included physics-less background tiles")

		piece.queue_free()


	func _assert_board_scans_tile_piece(failures: Array[String]) -> void:
		var board := PuzzleBoard.new()
		board.board_size = Vector2i(8, 4)
		board.cell_size = 8

		var piece := _make_tile_piece()
		piece.position = Vector2(16.0, 8.0)
		piece.x_move_distance = 3
		piece.y_move_distance = 2
		var solid := piece.get_node("SolidTiles") as TileMapLayer
		var one_way := piece.get_node("OneWayTiles") as TileMapLayer
		solid.set_cell(Vector2i.ZERO, 0, Vector2i(0, 0))
		one_way.set_cell(Vector2i(1, 0), 0, Vector2i(1, 4))

		board.add_child(piece)
		add_child(board)

		var session: Variant = board.get("session")
		if session == null or session.current_state.pieces.size() != 1:
			failures.append("PuzzleBoard did not build a session from a tile piece")
		else:
			var state_piece: Variant = session.current_state.pieces[0]
			if state_piece.cell != Vector2i(2, 1):
				failures.append("PuzzleBoard registered the tile piece at the wrong anchor")
			var definition_piece: Variant = session.definition.pieces[0]
			if not definition_piece.shape.has(Vector2i.ZERO):
				failures.append("PuzzleBoard did not copy the tile piece footprint into the session")
			if not definition_piece.shape.has(Vector2i(1, 0)):
				failures.append("PuzzleBoard dropped the one-way platform cell from the footprint")
			if not definition_piece.wall_shape.has(Vector2i.ZERO):
				failures.append("PuzzleBoard did not copy the wall classification")
			if not definition_piece.one_way_shape.has(Vector2i(1, 0)):
				failures.append("PuzzleBoard did not copy the one-way classification")

		board.queue_free()


	func _assert_void_layer_builds_player_body(failures: Array[String]) -> void:
		var piece := _make_void_piece()
		add_child(piece)
		var void_layer := piece.get_node("VoidTiles") as TileMapLayer
		void_layer.set_cell(Vector2i.ZERO, 0, Vector2i(0, 0))
		void_layer.set_cell(Vector2i(1, 0), 0, Vector2i(0, 0))
		piece.call("_refresh_from_polygon")
		if not piece.is_void:
			failures.append("VoidTiles did not mark the piece as void")
		if piece.shape.size() != 2:
			failures.append("void footprint did not use the painted VoidTiles cells")
		if not piece.wall_shape.is_empty() or not piece.one_way_shape.is_empty():
			failures.append("void piece leaked wall or one-way cells")
		var body := piece.get_node_or_null("VoidBody") as StaticBody2D
		if body == null:
			failures.append("void piece did not build a player-only body")
		elif body.collision_layer != 8 or body.collision_mask != 0:
			failures.append("void body used the wrong collision layer or mask")
		elif body.get_child_count() != 1:
			failures.append("adjacent void cells must merge into one collision shape")
		else:
			var shape := (body.get_child(0) as CollisionShape2D).shape as RectangleShape2D
			if shape.size != Vector2(16, 8):
				failures.append("merged void collision shape has wrong rectangle size")
		piece.queue_free()


	func _assert_void_layer_wins_hybrid(failures: Array[String]) -> void:
		var piece := _make_void_piece()
		var void_layer := piece.get_node("VoidTiles") as TileMapLayer
		var solid := piece.get_node("SolidTiles") as TileMapLayer
		void_layer.set_cell(Vector2i.ZERO, 0, Vector2i(0, 0))
		solid.set_cell(Vector2i(1, 0), 0, Vector2i(0, 0))
		add_child(piece)
		piece.call("_refresh_from_polygon")
		if not piece.is_void or piece.shape != [Vector2i.ZERO]:
			failures.append("VoidTiles did not win over SolidTiles in a hybrid piece")
		if solid.collision_enabled:
			failures.append("hybrid void piece left SolidTiles collision enabled")
		piece.queue_free()


	func _assert_void_selection_priority(failures: Array[String]) -> void:
		var board := PuzzleBoard.new()
		board.board_size = Vector2i(4, 3)
		board.cell_size = 8
		var normal := _make_tile_piece()
		normal.position = Vector2(0.0, 0.0)
		var normal_solid := normal.get_node("SolidTiles") as TileMapLayer
		normal_solid.set_cell(Vector2i.ZERO, 0, Vector2i(0, 0))
		normal_solid.set_cell(Vector2i(2, 0), 0, Vector2i(0, 0))
		var void_piece := _make_void_piece()
		void_piece.position = Vector2(0.0, 0.0)
		var void_layer := void_piece.get_node("VoidTiles") as TileMapLayer
		void_layer.set_cell(Vector2i.ZERO, 0, Vector2i(0, 0))
		board.add_child(normal)
		board.add_child(void_piece)
		add_child(board)
		var picked: PuzzlePiece = board.call("get_piece_at_cell", Vector2i.ZERO)
		if picked != void_piece:
			failures.append("void piece did not win hit-testing against a normal piece")
		var normal_pick: PuzzlePiece = board.call("get_piece_at_cell", Vector2i(2, 0))
		if normal_pick != normal:
			failures.append("a void piece outside its footprint stole a normal piece click")
		board.queue_free()


	func _assert_polygon_fallback(failures: Array[String]) -> void:
		var piece := TILE_PIECE_SCRIPT.new() as PuzzleTilePiece
		piece.cell_size = 8
		piece.polygon = PackedVector2Array([
			Vector2.ZERO,
			Vector2(16.0, 0.0),
			Vector2(16.0, 8.0),
			Vector2(0.0, 8.0),
		])
		add_child(piece)
		if piece.shape.size() != 2:
			failures.append("PuzzleTilePiece did not fall back to its Polygon2D face")
		if piece.wall_shape.size() != 2 or not piece.one_way_shape.is_empty():
			failures.append("legacy polygon fallback was not classified as all walls")
		piece.queue_free()


	func _make_tile_piece() -> PuzzleTilePiece:
		var piece := TILE_PIECE_SCRIPT.new() as PuzzleTilePiece
		piece.cell_size = 8
		piece.add_child(_make_layer("BackTiles", false))
		piece.add_child(_make_layer("SolidTiles", true))
		piece.add_child(_make_layer("OneWayTiles", true))
		piece.add_child(_make_layer("DetailTiles", false))
		return piece


	func _make_void_piece() -> PuzzleTilePiece:
		var piece := TILE_PIECE_SCRIPT.new() as PuzzleTilePiece
		piece.cell_size = 8
		piece.add_child(_make_layer("BackTiles", false))
		piece.add_child(_make_layer("SolidTiles", true))
		piece.add_child(_make_layer("OneWayTiles", true))
		piece.add_child(_make_layer("DetailTiles", false))
		piece.add_child(_make_layer("VoidTiles", false))
		return piece


	func _make_layer(layer_name: String, collision_enabled: bool) -> TileMapLayer:
		var layer := TileMapLayer.new()
		layer.name = layer_name
		layer.tile_set = TILESET
		layer.collision_enabled = collision_enabled
		return layer


## tests/puzzle/test_puzzle_board_auto.gd
class PuzzleBoardAutoCase extends Node:
	## Coverage for the auto-split board: chunking a painted TileMapLayer into
	## equal-size PuzzleTilePieces, including void chunks and regeneration.

	const AUTO_BOARD := preload("res://scripts/puzzle/view/puzzle_board_auto.gd")
	const TILESET := preload("res://resources/tilesets/primordial_tileset.tres")


	func run() -> Array[String]:
		var failures: Array[String] = []
		_assert_split_creates_pieces(failures)
		_assert_generation_is_idempotent(failures)
		_assert_void_enable_flag(failures)
		_assert_out_of_range_cells_are_ignored(failures)
		_assert_missing_source_is_rejected(failures)
		return failures


	func _assert_split_creates_pieces(failures: Array[String]) -> void:
		var board := _make_board(true)
		if not board.generate_pieces():
			failures.append("PuzzleBoardAuto.generate_pieces returned false for a valid picture")
			board.free()
			return
		if board.board_size != Vector2i(4, 4):
			failures.append("board_size was not derived from puzzle_size * piece_size")
		if board.get_generated_pieces().size() != 4:
			failures.append("expected 4 generated pieces, got %d" % board.get_generated_pieces().size())
		var piece_10 := board.get_node_or_null("Piece_1_0") as PuzzleTilePiece
		var piece_11 := board.get_node_or_null("Piece_1_1") as PuzzleTilePiece
		if piece_10 == null or piece_11 == null:
			failures.append("generated piece names are not Piece_<chunk_x>_<chunk_y>")
			board.free()
			return
		if piece_10.position != Vector2(16.0, 0.0) or piece_11.position != Vector2(16.0, 16.0):
			failures.append("generated pieces are not placed at their chunk origins")
		if piece_10.x_move_distance != 2 or piece_10.y_move_distance != 2:
			failures.append("generated pieces did not get piece_size as move distance")
		if not piece_10.enable:
			failures.append("normal generated pieces must be controllable")
		if piece_10.get_meta(&"authored_cell", Vector2i(-1, -1)) != Vector2i(2, 0):
			failures.append("generated pieces did not record their authored chunk cell")
		if not piece_11.is_void:
			failures.append("a chunk painted in the void layer was not generated as a void piece")
		if piece_11.enable:
			failures.append("void pieces must default to enable = false")
		if piece_11.z_index != 1:
			failures.append("void pieces must draw above normal pieces")
		var solid := piece_10.get_node_or_null("SolidTiles") as TileMapLayer
		if solid == null or not solid.collision_enabled:
			failures.append("normal pieces need a colliding SolidTiles layer")
		elif solid.tile_set != TILESET:
			failures.append("generated layers did not copy the source TileSet")
		elif solid.get_used_cells().size() != 4:
			failures.append("SolidTiles did not receive the chunk cells")
		elif solid.get_cell_atlas_coords(Vector2i(1, 1)) != Vector2i(0, 3):
			failures.append("chunk cells were not offset into piece-local coordinates")
		var void_layer := piece_11.get_node_or_null("VoidTiles") as TileMapLayer
		if void_layer == null or void_layer.collision_enabled:
			failures.append("void pieces need a non-colliding VoidTiles layer")
		elif piece_11.get_node_or_null("SolidTiles") != null:
			failures.append("void chunks must not also create SolidTiles")
		add_child(board)
		if piece_10.shape.size() != 4 or piece_11.shape.size() != 4:
			failures.append("generated tile pieces did not derive their footprints")
		if board.session == null or board.session.current_state.pieces.size() != 4:
			failures.append("PuzzleBoardAuto did not build a session from generated pieces")
		elif not board.session.definition.pieces[3].is_void:
			failures.append("the generated void piece was not registered as void")
		board.free()


	func _assert_generation_is_idempotent(failures: Array[String]) -> void:
		var board := _make_board(true)
		if not board.generate_pieces() or not board.generate_pieces():
			failures.append("regeneration reported failure")
		if board.get_generated_pieces().size() != 4:
			failures.append("regeneration duplicated generated pieces")
		var piece := board.get_node_or_null("Piece_1_1") as PuzzleTilePiece
		if piece == null:
			failures.append("regeneration lost a generated piece")
		elif piece.get_node("VoidTiles").get_used_cells().size() != 4:
			failures.append("regeneration dropped generated cell data")
		board.free()


	func _assert_void_enable_flag(failures: Array[String]) -> void:
		var board := _make_board(true)
		board.void_enable = true
		board.generate_pieces()
		var void_piece := board.get_node_or_null("Piece_1_1") as PuzzleTilePiece
		if void_piece == null or not void_piece.enable:
			failures.append("void_enable = true did not enable the generated void piece")
		board.free()


	func _assert_out_of_range_cells_are_ignored(failures: Array[String]) -> void:
		var board := _make_board(true)
		var source := board.get_node("PictureSource") as TileMapLayer
		source.set_cell(Vector2i(4, 4), 0, Vector2i(0, 0))
		if not board.generate_pieces():
			failures.append("out-of-range cells made generation fail")
		if board.get_node_or_null("Piece_2_2") != null:
			failures.append("a cell outside the board created a chunk")
		if board.get_generated_pieces().size() != 4:
			failures.append("out-of-range cells changed the piece count")
		board.free()


	func _assert_missing_source_is_rejected(failures: Array[String]) -> void:
		var board := AUTO_BOARD.new() as PuzzleBoardAuto
		board.puzzle_size = Vector2i(2, 2)
		board.piece_size = Vector2i(2, 2)
		if board.generate_pieces():
			failures.append("generate_pieces succeeded without a source layer")
		if not board.get_generated_pieces().is_empty():
			failures.append("generate_pieces modified the board on failure")
		board.free()


	func _make_board(with_void: bool) -> PuzzleBoardAuto:
		var board := AUTO_BOARD.new() as PuzzleBoardAuto
		board.puzzle_size = Vector2i(2, 2)
		board.piece_size = Vector2i(2, 2)
		board.cell_size = 8
		var source := _layer("PictureSource", [
			{"cell": Vector2i(0, 0), "atlas": Vector2i(0, 0)}, {"cell": Vector2i(1, 0), "atlas": Vector2i(0, 0)},
			{"cell": Vector2i(0, 1), "atlas": Vector2i(0, 0)}, {"cell": Vector2i(1, 1), "atlas": Vector2i(0, 0)},
			{"cell": Vector2i(2, 0), "atlas": Vector2i(0, 3)}, {"cell": Vector2i(3, 0), "atlas": Vector2i(0, 3)},
			{"cell": Vector2i(2, 1), "atlas": Vector2i(0, 3)}, {"cell": Vector2i(3, 1), "atlas": Vector2i(0, 3)},
			{"cell": Vector2i(0, 2), "atlas": Vector2i(0, 0)}, {"cell": Vector2i(1, 2), "atlas": Vector2i(0, 0)},
			{"cell": Vector2i(0, 3), "atlas": Vector2i(0, 0)}, {"cell": Vector2i(1, 3), "atlas": Vector2i(0, 0)},
		])
		board.add_child(source)
		board.source_layer_path = ^"PictureSource"
		if with_void:
			var void_source := _layer("VoidSource", [
				{"cell": Vector2i(2, 2), "atlas": Vector2i(0, 5)}, {"cell": Vector2i(3, 2), "atlas": Vector2i(0, 5)},
				{"cell": Vector2i(2, 3), "atlas": Vector2i(0, 5)}, {"cell": Vector2i(3, 3), "atlas": Vector2i(0, 5)},
			])
			board.add_child(void_source)
			board.void_layer_path = ^"VoidSource"
		return board


	func _layer(layer_name: String, cells: Array) -> TileMapLayer:
		var layer := TileMapLayer.new()
		layer.name = layer_name
		layer.tile_set = TILESET
		layer.collision_enabled = false
		for entry: Dictionary in cells:
			layer.set_cell(entry["cell"], 0, entry["atlas"], 0)
		return layer


## tests/puzzle/test_puzzle_board_shuffler.gd
class PuzzleBoardShufflerCase extends Node:
	## Coverage for the scramble pipeline: the pure random walk, the PuzzleBoard
	## adoption API and the PuzzleBoardShuffler node component.

	const PuzzleScrambler := preload("res://scripts/puzzle/systems/puzzle_scrambler.gd")
	const SlidingPuzzleRuleSet := preload("res://scripts/puzzle/rules/sliding_puzzle_rule_set.gd")
	const PuzzleSession := preload("res://scripts/puzzle/systems/puzzle_session.gd")
	const PUZZLE_BOARD := preload("res://scripts/puzzle/view/puzzle_board.gd")
	const PUZZLE_SHUFFLER := preload("res://scripts/puzzle/view/puzzle_board_shuffler.gd")
	const TILESET := preload("res://resources/tilesets/primordial_tileset.tres")


	func run() -> Array[String]:
		var failures: Array[String] = []
		_assert_scrambler_walks_around_void(failures)
		_assert_scrambler_is_deterministic(failures)
		_assert_scrambler_void_only_filter(failures)
		_assert_scrambler_rejects_packed_board(failures)
		_assert_scrambler_handles_two_voids(failures)
		_assert_board_scramble_updates_initial_layout(failures)
		_assert_apply_initial_layout_adopts_state(failures)
		_assert_shuffler_node_scrambles_on_ready(failures)
		_assert_child_shuffler_can_scramble_now(failures)
		return failures


	# --- Pure scrambler -----------------------------------------------------------

	func _assert_scrambler_walks_around_void(failures: Array[String]) -> void:
		var def := _void_board()
		var rules := SlidingPuzzleRuleSet.new(def)
		var start := PuzzleSession.new(def).current_state
		var rng := RandomNumberGenerator.new()
		rng.seed = 1
		var result: BoardState = PuzzleScrambler.build_scrambled_state(def, rules, start, 40, rng, true, true)
		if result == null:
			failures.append("scrambler returned null for a board with a void slider")
			return
		if result.get_hash_key() == start.get_hash_key():
			failures.append("scrambler returned the start layout")
		_assert_state_legal(def, result, failures, "void walk")


	func _assert_scrambler_is_deterministic(failures: Array[String]) -> void:
		var def := _void_board()
		var rules := SlidingPuzzleRuleSet.new(def)
		var start := PuzzleSession.new(def).current_state
		var first: BoardState = _scramble_with_seed(def, rules, start, 4242)
		var second: BoardState = _scramble_with_seed(def, rules, start, 4242)
		if first == null or second == null:
			failures.append("deterministic scramble returned null")
			return
		if first.get_hash_key() != second.get_hash_key():
			failures.append("same seed produced different scrambled layouts")
		var other: BoardState = _scramble_with_seed(def, rules, start, 99)
		if other != null and other.get_hash_key() == first.get_hash_key():
			failures.append("different seeds produced the same scrambled layout")


	func _assert_scrambler_void_only_filter(failures: Array[String]) -> void:
		var def := _definition(Vector2i(4, 4), [
			_piece(&"a", Vector2i(0, 0), Vector2i(2, 2), false),
			_piece(&"b", Vector2i(2, 0), Vector2i(2, 2), false),
			_piece(&"c", Vector2i(0, 2), Vector2i(2, 2), false),
		])
		var rules := SlidingPuzzleRuleSet.new(def)
		var start := PuzzleSession.new(def).current_state
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		if PuzzleScrambler.build_scrambled_state(def, rules, start, 20, rng, true, true) != null:
			failures.append("void_only scramble succeeded on a board without void sliders")
		rng.seed = 5
		var result: BoardState = PuzzleScrambler.build_scrambled_state(def, rules, start, 20, rng, false, true)
		if result == null or result.get_hash_key() == start.get_hash_key():
			failures.append("non-void_only scramble did not move a board with an empty slot")
		else:
			_assert_state_legal(def, result, failures, "empty slot")


	func _assert_scrambler_rejects_packed_board(failures: Array[String]) -> void:
		var def := _definition(Vector2i(4, 4), [
			_piece(&"a", Vector2i(0, 0), Vector2i(2, 2), false),
			_piece(&"b", Vector2i(2, 0), Vector2i(2, 2), false),
			_piece(&"c", Vector2i(0, 2), Vector2i(2, 2), false),
			_piece(&"d", Vector2i(2, 2), Vector2i(2, 2), false),
		])
		var rules := SlidingPuzzleRuleSet.new(def)
		var start := PuzzleSession.new(def).current_state
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		if PuzzleScrambler.build_scrambled_state(def, rules, start, 20, rng, false, true) != null:
			failures.append("scrambler moved a packed board with no empty slot")


	func _assert_scrambler_handles_two_voids(failures: Array[String]) -> void:
		var pieces: Array = []
		for y in 3:
			for x in 3:
				pieces.append(_piece(
					StringName("p_%d_%d" % [x, y]),
					Vector2i(x * 2, y * 2),
					Vector2i(2, 2),
					(x == 0 and y == 0) or (x == 2 and y == 2)
				))
		var def := _definition(Vector2i(6, 6), pieces)
		var rules := SlidingPuzzleRuleSet.new(def)
		var start := PuzzleSession.new(def).current_state
		var rng := RandomNumberGenerator.new()
		rng.seed = 17
		var result: BoardState = PuzzleScrambler.build_scrambled_state(def, rules, start, 60, rng, true, true)
		if result == null or result.get_hash_key() == start.get_hash_key():
			failures.append("scrambler did not move a board with two void sliders")
		else:
			_assert_state_legal(def, result, failures, "two voids")


	# --- PuzzleBoard adoption API -------------------------------------------------

	func _assert_board_scramble_updates_initial_layout(failures: Array[String]) -> void:
		var board := _make_board_with_void()
		var start := board.session.current_state.get_hash_key()
		if not board.scramble(40, 7, true, true):
			failures.append("PuzzleBoard.scramble returned false on a board with a void slider")
			return
		if board.session.current_state.get_hash_key() == start:
			failures.append("PuzzleBoard.scramble did not change the layout")
		var state: BoardState = board.session.current_state
		for i in state.pieces.size():
			if board.definition.pieces[i].initial_cell != state.pieces[i].cell:
				failures.append("scramble did not adopt piece %d as new initial cell" % i)
		if board.session.get_move_count() != 0:
			failures.append("scramble left a non-zero move count")
		if board.session.undo():
			failures.append("scramble left an undo entry")
		if board.session.reset():
			failures.append("reset after scramble was not a no-op")
		var pieces: Array[PuzzlePiece] = []
		for child in board.get_children():
			if child is PuzzlePiece:
				pieces.append(child as PuzzlePiece)
		if pieces.size() != state.pieces.size():
			failures.append("scrambled board lost pieces")
		for i in pieces.size():
			if pieces[i].get_logical_cell() != state.pieces[i].cell:
				failures.append("piece %d node cell was not synced after scramble" % i)
			if not pieces[i].position.is_equal_approx(pieces[i].cell_to_world(state.pieces[i].cell)):
				failures.append("piece %d node position was not synced after scramble" % i)
		_assert_state_legal(board.definition, state, failures, "board scramble")
		board.free()


	func _assert_apply_initial_layout_adopts_state(failures: Array[String]) -> void:
		var board := _make_board_with_void()
		var state: BoardState = board.session.current_state.duplicate_state()
		# Move piece 0 into the void chunk's cells (no legality check here: adoption
		# is a data operation; the scrambler is the thing that only feeds it legal
		# turns).
		state.pieces[0].cell = Vector2i(2, 2)
		board.apply_initial_layout(state)
		if board.definition.pieces[0].initial_cell != Vector2i(2, 2):
			failures.append("apply_initial_layout did not write the new initial cell")
		if board.session.current_state.pieces[0].cell != Vector2i(2, 2):
			failures.append("apply_initial_layout did not restart the session from the new layout")
		var piece := board.get_children().filter(func(child): return child is PuzzlePiece)[0] as PuzzlePiece
		if piece.get_logical_cell() != Vector2i(2, 2):
			failures.append("apply_initial_layout did not sync the piece's logical cell")
		if not piece.position.is_equal_approx(piece.cell_to_world(Vector2i(2, 2))):
			failures.append("apply_initial_layout did not sync the piece's node position")
		if board.session.undo() or board.session.reset() or board.session.get_move_count() != 0:
			failures.append("apply_initial_layout left history behind")
		board.free()


	# --- Shuffler node ------------------------------------------------------------

	func _assert_shuffler_node_scrambles_on_ready(failures: Array[String]) -> void:
		var root := Node2D.new()
		add_child(root)
		var board := _make_board_with_void(root)
		var start := board.session.current_state.get_hash_key()
		var shuffler := PUZZLE_SHUFFLER.new() as PuzzleBoardShuffler
		shuffler.board_path = ^"../PuzzleBoard"
		shuffler.steps = 40
		shuffler.seed = 11
		root.add_child(shuffler)
		if board.session.current_state.get_hash_key() == start:
			failures.append("PuzzleBoardShuffler did not scramble a sibling board on ready")
		if not shuffler.shuffle_now():
			failures.append("PuzzleBoardShuffler.shuffle_now returned false")
		root.free()


	func _assert_child_shuffler_can_scramble_now(failures: Array[String]) -> void:
		var board := _make_board_with_void()
		var shuffler := PUZZLE_SHUFFLER.new() as PuzzleBoardShuffler
		shuffler.shuffle_on_ready = false
		shuffler.steps = 40
		shuffler.seed = 21
		board.add_child(shuffler)
		var start := board.session.current_state.get_hash_key()
		if not shuffler.shuffle_now():
			failures.append("child PuzzleBoardShuffler.shuffle_now returned false")
		if board.session.current_state.get_hash_key() == start:
			failures.append("child PuzzleBoardShuffler.shuffle_now did not scramble")
		board.free()


	# --- Helpers ------------------------------------------------------------------

	func _make_board_with_void(parent: Node = null) -> PuzzleBoard:
		var board := PUZZLE_BOARD.new() as PuzzleBoard
		board.name = "PuzzleBoard"
		board.board_size = Vector2i(4, 4)
		board.cell_size = 8
		board.add_child(_make_tile_piece(Vector2i(0, 0), false))
		board.add_child(_make_tile_piece(Vector2i(2, 0), false))
		board.add_child(_make_tile_piece(Vector2i(0, 2), false))
		board.add_child(_make_tile_piece(Vector2i(2, 2), true))
		if parent != null:
			parent.add_child(board)
		else:
			add_child(board)
		return board


	func _make_tile_piece(cell: Vector2i, is_void: bool) -> PuzzleTilePiece:
		var piece := PuzzleTilePiece.new()
		piece.position = Vector2(cell * 8)
		piece.x_move_distance = 2
		piece.y_move_distance = 2
		var layer := TileMapLayer.new()
		layer.name = "VoidTiles" if is_void else "SolidTiles"
		layer.tile_set = TILESET
		layer.collision_enabled = not is_void
		for y in 2:
			for x in 2:
				layer.set_cell(Vector2i(x, y), 0, Vector2i(0, 5) if is_void else Vector2i(0, 0))
		piece.add_child(layer)
		return piece


	func _void_board() -> PuzzleDefinition:
		var pieces: Array = []
		for y in 3:
			for x in 3:
				pieces.append(_piece(
					StringName("p_%d_%d" % [x, y]),
					Vector2i(x * 2, y * 2),
					Vector2i(2, 2),
					x == 2 and y == 2
				))
		return _definition(Vector2i(6, 6), pieces)


	func _definition(board_size: Vector2i, pieces: Array) -> PuzzleDefinition:
		var def := PuzzleDefinition.new()
		def.board = BoardDefinition.new()
		def.board.board_size = board_size
		var index := 0
		for piece: PieceDefinition in pieces:
			piece.id = StringName("piece_%d" % index)
			def.pieces.append(piece)
			index += 1
		return def


	func _piece(id: StringName, cell: Vector2i, size: Vector2i, is_void: bool) -> PieceDefinition:
		var piece := PieceDefinition.new()
		piece.id = id
		piece.shape = PieceDefinition.make_rect_shape(size)
		piece.initial_cell = cell
		piece.is_void = is_void
		piece.enable = not is_void
		piece.x_move_distance = size.x
		piece.y_move_distance = size.y
		return piece


	func _scramble_with_seed(def: PuzzleDefinition, rules: PuzzleRuleSet, start: BoardState, seed_value: int) -> BoardState:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		return PuzzleScrambler.build_scrambled_state(def, rules, start, 40, rng, true, true)


	func _assert_state_legal(
		def: PuzzleDefinition,
		state: BoardState,
		failures: Array[String],
		label: String
	) -> void:
		var occupied: Dictionary = {}
		for i in state.pieces.size():
			var piece_def: PieceDefinition = def.pieces[i]
			var cell: Vector2i = state.pieces[i].cell
			for offset: Vector2i in piece_def.shape:
				var world := cell + offset
				if not def.board.contains_cell(world):
					failures.append("%s: piece %d left the board at %s" % [label, i, world])
				if not piece_def.is_void:
					if occupied.has(world):
						failures.append("%s: normal pieces overlap at %s" % [label, world])
					occupied[world] = true


## tests/puzzle/test_puzzle_auto_room.gd
class PuzzleAutoRoomCase extends Node:
	## Contract coverage for the migrated main_room_02_00: the baked runtime scene
	## carries the generated 3x3 picture (8 solid sliders + one 25-cell void
	## diamond), the shuffler scrambled it on load, and the editor-only source
	## layers stayed out of the runtime.

	const AUTO_BOARD := preload("res://scripts/puzzle/view/puzzle_board_auto.gd")
	const RUNTIME := "res://scenes/rooms/generated/main_room_02_00/runtime.tscn"
	const BOARD_SIZE := Vector2i(21, 21)
	const VOID_CELLS := 25
	const AUTHORED_CELL_META := &"authored_cell"


	func run() -> Array[String]:
		var failures: Array[String] = []
		var scene: PackedScene = load(RUNTIME)
		if scene == null:
			failures.append("main_room_02_00 runtime scene is missing")
			return failures
		var root: Node = scene.instantiate()
		add_child(root)
		if root.get_node_or_null("PreviewOnly") != null:
			failures.append("PreviewOnly leaked into the baked runtime scene")
		var board := root.get_node_or_null("Entities/PuzzleBoard")
		if board == null or board.get_script() != AUTO_BOARD:
			failures.append("main_room_02_00 PuzzleBoard is not a PuzzleBoardAuto")
			root.free()
			return failures
		if board.board_size != BOARD_SIZE:
			failures.append("main_room_02_00 board is not 21x21 cells")
		if board.get_node_or_null("PuzzleSourceTiles") != null or board.get_node_or_null("PuzzleVoidTiles") != null:
			failures.append("the runtime board still carries editor-only source layers")
		var pieces: Array = board.call("get_generated_pieces")
		if pieces.size() != 9:
			failures.append("main_room_02_00 should generate 9 sliders, got %d" % pieces.size())
		var void_count := 0
		var moved := 0
		for piece: PuzzleTilePiece in pieces:
			var authored := Vector2i(piece.get_meta(AUTHORED_CELL_META, Vector2i.ZERO))
			if piece.get_logical_cell() != authored:
				moved += 1
			if piece.is_void:
				void_count += 1
				if piece.shape.size() != VOID_CELLS:
					failures.append("main_room_02_00 void slider is not the 25-cell diamond")
				if piece.get_bounds() != Rect2i(0, 0, 7, 7):
					failures.append("main_room_02_00 void slider bounds are not 7x7")
				if authored != Vector2i(7, 7):
					failures.append("main_room_02_00 void slider was authored at the wrong chunk")
			elif piece.shape.size() != 49:
				failures.append("main_room_02_00 solid slider does not cover its full 7x7 chunk")
		if void_count != 1:
			failures.append("main_room_02_00 should have exactly one void slider")
		if moved == 0:
			failures.append("the shuffler did not scramble main_room_02_00 on load")
		var shuffler := root.get_node_or_null("Entities/PuzzleBoardShuffler")
		if shuffler == null:
			failures.append("main_room_02_00 is missing the PuzzleBoardShuffler")
		elif not bool(shuffler.get("void_only")):
			failures.append("main_room_02_00 shuffler should only walk void turns")
		if board.session == null or board.session.current_state.pieces.size() != 9:
			failures.append("main_room_02_00 did not boot a 9-piece session")
		root.free()
		return failures


## tests/puzzle/test_puzzle_room_contract.gd
class PuzzleRoomContractCase extends Node:
	## Contract coverage for the authored room_04_00: the world registers the room,
	## the baked runtime scene contains the PuzzleBoard, and it boots a session from
	## three tile-authored sliding regions at 8px tiles.

	const WORLD_PATH := "res://resources/worlds/the_world.tres"
	const RUNTIME_SCENE_PATH := "res://scenes/rooms/generated/room_04_00/runtime.tscn"
	const PUZZLE_BOARD_SCRIPT := preload("res://scripts/puzzle/view/puzzle_board.gd")
	const PUZZLE_MOVE := preload("res://scripts/puzzle/core/puzzle_move.gd")


	func run() -> Array[String]:
		var failures: Array[String] = []
		_assert_world_registration(failures)
		_assert_runtime_scene_boots_board(failures)
		_assert_player_riding_rules(failures)
		_assert_one_way_overlap_rules(failures)
		_assert_mode_overlay(failures)
		return failures


	func _assert_world_registration(failures: Array[String]) -> void:
		var world: Resource = load(WORLD_PATH)
		if world == null or not world.has_room("room_04_00"):
			failures.append("the_world does not contain room_04_00")
			return
		if world.get_room_origin_chunk("room_04_00") != Vector2i(4, 0):
			failures.append("room_04_00 is not placed at chunk (4, 0)")
		var room_data: Resource = world.get_room("room_04_00")
		if room_data == null or not room_data.spawn_ids.has("start"):
			failures.append("room_04_00 RoomData lacks the start spawn")


	func _assert_runtime_scene_boots_board(failures: Array[String]) -> void:
		var scene: PackedScene = load(RUNTIME_SCENE_PATH)
		if scene == null:
			failures.append("room_04_00 runtime scene is missing")
			return
		var root: Node = scene.instantiate()
		add_child(root)
		var board: Node = root.get_node_or_null("Entities/PuzzleBoard")
		if board == null or board.get_script() != PUZZLE_BOARD_SCRIPT:
			failures.append("runtime scene is missing the PuzzleBoard")
			root.free()
			return
		if int(board.get("cell_size")) != 8:
			failures.append("PuzzleBoard cell_size is not 8 px")
		var session: Variant = board.get("session")
		if session == null or int(session.current_state.pieces.size()) != 4:
			failures.append("PuzzleBoard did not build a 4-piece session from scene pieces")
		else:
			_assert_tile_pieces(board.get("_pieces"), failures)
			if int(session.definition.pieces[0].x_move_distance) != 4 or int(session.definition.pieces[0].y_move_distance) != 4:
				failures.append("PieceA axis move distances were not preserved through the bake")
			if int(session.definition.pieces[2].x_move_distance) != 2 or int(session.definition.pieces[2].y_move_distance) != 2:
				failures.append("PieceC axis move distances were not preserved through the bake")
		if board.call("get_piece_at_cell", Vector2i(16, 5)) == null:
			failures.append("PieceA was not registered at cell (16, 5)")
		if board.call("get_piece_at_cell", Vector2i(7, 16)) == null:
			failures.append("PieceB was not registered at cell (7, 16)")
		if board.call("get_piece_at_cell", Vector2i(3, 10)) == null:
			failures.append("PieceC was not registered at cell (3, 10)")
		if board.call("get_piece_at_cell", Vector2i(0, 8)) == null:
			failures.append("the legacy scene piece was not registered at cell (0, 8)")
		if board.call("get_piece_at_cell", Vector2i(11, 17)) == null:
			failures.append("PieceB L-shape did not cover cell (11, 17)")
		if board.call("get_piece_at_cell", Vector2i(11, 18)) != null:
			failures.append("PieceB L-shape incorrectly covered hole cell (11, 18)")
		if board.call("get_piece_at_cell", Vector2i(7, 10)) == null:
			failures.append("PieceC L-shape did not cover cell (7, 10)")
		if board.call("get_piece_at_cell", Vector2i(7, 11)) != null:
			failures.append("PieceC L-shape incorrectly covered hole cell (7, 11)")
		if board.call("get_piece_at_cell", Vector2i(24, 11)) != null:
			failures.append("PieceA background-only hole incorrectly blocked cell (24, 11)")
		root.free()


	func _assert_tile_pieces(pieces: Array, failures: Array[String]) -> void:
		var expected_cells: Array[Vector2i] = [Vector2i(16, 5), Vector2i(7, 16), Vector2i(3, 10)]
		for i in 3:
			var piece := pieces[i] as PuzzleTilePiece
			if piece == null:
				failures.append("scene piece %d is not a PuzzleTilePiece" % i)
				continue
			if Vector2i(piece.get("logical_cell")) != expected_cells[i]:
				failures.append("scene piece %d has unexpected anchor cell" % i)
			var back := piece.get_node_or_null("BackTiles") as TileMapLayer
			var solid := piece.get_node_or_null("SolidTiles") as TileMapLayer
			var one_way := piece.get_node_or_null("OneWayTiles") as TileMapLayer
			if back == null or back.collision_enabled:
				failures.append("scene piece %d lacks a non-colliding BackTiles layer" % i)
			if solid == null or not solid.collision_enabled:
				failures.append("scene piece %d lacks a colliding SolidTiles layer" % i)
			if one_way == null or not one_way.collision_enabled:
				failures.append("scene piece %d lacks a colliding OneWayTiles layer" % i)
			if back != null and solid != null and one_way != null:
				var footprint := solid.get_used_cells().size() + one_way.get_used_cells().size()
				if back.get_used_cells().size() <= footprint:
					failures.append("scene piece %d background did not extend beyond the footprint" % i)
				if piece.shape.size() != footprint:
					failures.append("scene piece %d footprint did not match its colliding tile cells" % i)
				if piece.wall_shape.size() != solid.get_used_cells().size():
					failures.append("scene piece %d wall classification did not match SolidTiles" % i)
				if piece.one_way_shape.size() != one_way.get_used_cells().size():
					failures.append("scene piece %d one-way classification did not match OneWayTiles" % i)
		var piece_a := pieces[0] as PuzzleTilePiece
		if piece_a == null:
			return
		if piece_a.get_node("OneWayTiles").get_cell_atlas_coords(Vector2i(0, 0)) != Vector2i(0, 4):
			failures.append("PieceA top-left cell is not a one-way platform tile")
		if piece_a.get_node("OneWayTiles").z_index <= piece_a.get_node("SolidTiles").z_index:
			failures.append("PieceA one-way layer is not drawn above the wall layer")
		var legacy := pieces[3] as PuzzlePiece
		if legacy == null or legacy is PuzzleTilePiece:
			failures.append("the fourth scene piece is not the expected legacy polygon piece")
		elif legacy.wall_shape.size() != legacy.shape.size() or not legacy.one_way_shape.is_empty():
			failures.append("the legacy scene piece was not classified as all walls")
		return


	func _assert_player_riding_rules(failures: Array[String]) -> void:
		var scene: PackedScene = load(RUNTIME_SCENE_PATH)
		if scene == null:
			failures.append("room_04_00 runtime scene is missing")
			return
		var root: Node = scene.instantiate()
		add_child(root)
		var board: Node = root.get_node_or_null("Entities/PuzzleBoard")
		if board == null:
			failures.append("riding test could not find the PuzzleBoard")
			root.free()
			return
		var player := Node2D.new()
		player.name = "TestPlayer"
		player.add_to_group("player")
		root.add_child(player)
		board.call("_resolve_player_lazy")

		var pieces: Array = board.get("_pieces")
		if pieces.size() < 2:
			failures.append("riding test needs the two scene pieces")
			root.free()
			return
		var piece_a: Node = pieces[0]
		var piece_b: Node = pieces[1]

		# Case 1: standing on the one-way top of PieceA, outside its bounding rect.
		board.call("set_player_to_cell", Vector2i(16, 4))
		if not board.call("_player_rides", piece_a):
			failures.append("player standing on PieceA did not ride")
		# Case 2: inside PieceB's bounding rect with empty support.
		board.call("set_player_to_cell", Vector2i(10, 18))
		if not board.call("_player_rides", piece_b):
			failures.append("player inside PieceB's rect did not ride")
		# Far from every piece: no ride.
		board.call("set_player_to_cell", Vector2i(0, 0))
		if board.call("_player_rides", piece_a):
			failures.append("distant player incorrectly rode PieceA")
		# Touching from below (piece above the head): no ride.
		board.call("set_player_to_cell", Vector2i(16, 15))
		if board.call("_player_rides", piece_a):
			failures.append("player under PieceA incorrectly rode")
		root.free()


	func _assert_one_way_overlap_rules(failures: Array[String]) -> void:
		var scene: PackedScene = load(RUNTIME_SCENE_PATH)
		if scene == null:
			failures.append("room_04_00 runtime scene is missing")
			return
		var root: Node = scene.instantiate()
		add_child(root)
		var board: Node = root.get_node_or_null("Entities/PuzzleBoard")
		if board == null:
			failures.append("overlap test could not find the PuzzleBoard")
			root.free()
			return
		var pieces: Array = board.get("_pieces")
		var session: Variant = board.get("session")
		if pieces.size() < 4 or session == null:
			failures.append("overlap test needs the four scene pieces")
			root.free()
			return
		# The fourth (legacy wall) piece starts at (0, 8), 3x3. PieceC's top row
		# has one-way cells starting at (3, 10). Moving right enters that one-way
		# cell from the side and is allowed to overlap.
		if not session.try_move(PUZZLE_MOVE.new(3, Vector2i(0, 8), Vector2i(1, 8))):
			failures.append("wall could not enter PieceC's one-way cell from the left")
		if board.call("get_piece_at_cell", Vector2i(3, 10)) != pieces[2]:
			failures.append("one-way platform was not selected above the overlapping wall")
		# Moving down from the overlap would enter PieceC's one-way cell from above.
		if session.try_move(PUZZLE_MOVE.new(3, Vector2i(1, 8), Vector2i(1, 9))):
			failures.append("wall slid down into a one-way cell")
		root.free()


	func _assert_mode_overlay(failures: Array[String]) -> void:
		var scene: PackedScene = load(RUNTIME_SCENE_PATH)
		if scene == null:
			failures.append("room_04_00 runtime scene is missing")
			return
		var root: Node = scene.instantiate()
		add_child(root)
		var board: Node = root.get_node_or_null("Entities/PuzzleBoard")
		if board == null:
			failures.append("mode overlay test could not find the PuzzleBoard")
			root.free()
			return
		if board.get_node_or_null("ModeHud") != null:
			failures.append("PuzzleBoard still creates the mode text HUD")
		var overlay: Node2D = board.get_node_or_null("ModeOverlay") as Node2D
		if overlay == null:
			failures.append("PuzzleBoard did not create its mode overlay")
			root.free()
			return
		if overlay.visible:
			failures.append("mode overlay was visible outside slider mode")
		board.call("_enter_drag_mode")
		if not overlay.visible:
			failures.append("mode overlay did not appear in slider mode")
		var piece: PuzzlePiece = board.get("_pieces")[0]
		board.call("_select_piece", piece)
		if overlay.get("_selected") != piece:
			failures.append("mode overlay did not mark the selected piece solid")
		board.call("_exit_drag_mode")
		if overlay.visible:
			failures.append("mode overlay stayed visible after leaving slider mode")
		root.free()


func run() -> Array[String]:
	var failures: Array[String] = []
	failures.append_array(_run_case(SlidingPuzzleCoreCase.new()))
	failures.append_array(_run_case(PuzzleHistoryCase.new()))
	failures.append_array(_run_case(PuzzleTilePieceCase.new()))
	failures.append_array(_run_case(PuzzleBoardAutoCase.new()))
	failures.append_array(_run_case(PuzzleBoardShufflerCase.new()))
	failures.append_array(_run_case(PuzzleAutoRoomCase.new()))
	failures.append_array(_run_case(PuzzleRoomContractCase.new()))
	return failures


func _run_case(test: Node) -> Array[String]:
	add_child(test)
	var result: Array = test.call("run")
	test.queue_free()
	var failures: Array[String] = []
	failures.assign(result)
	return failures
