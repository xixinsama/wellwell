extends Node

## Merged test suite. Every inner class below is one original test file,
## kept in its own class so fixtures and helper names stay isolated. Do not
## add logic here: split a class back into its own file when it grows.

## tests/puzzle/test_piece_enable.gd
class PieceEnableCase extends Node:
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


## tests/puzzle/test_piece_fog_occlusion.gd
class PieceFogOcclusionCase extends Node:
	const PUZZLE_PIECE: Script = preload("res://scripts/puzzle/view/puzzle_piece.gd")


	func run() -> Array[String]:
		var failures: Array[String] = []
		var piece: Polygon2D = PUZZLE_PIECE.new() as Polygon2D
		piece.cell_size = 8
		piece.polygon = PackedVector2Array([
			Vector2(0, 0), Vector2(16, 0), Vector2(16, 8), Vector2(0, 8)
		])
		piece.position = Vector2(96, 48)
		add_child(piece)
		if not bool(piece.call("is_occluding")):
			failures.append("a solid puzzle piece does not occlude sight")
		if not piece.is_in_group(&"fog_occluder"):
			failures.append("puzzle piece did not join the fog occluder group")
		var cells: Array[Vector2i] = piece.call("get_occluder_cells")
		if cells.size() != 2:
			failures.append("puzzle piece occluder cell count was %d" % cells.size())
		for cell: Vector2i in [Vector2i(12, 6), Vector2i(13, 6)]:
			if not cells.has(cell):
				failures.append("puzzle piece did not expose world cell %s" % cell)
		piece.position.x += 8.0
		var moved: Array[Vector2i] = piece.call("get_occluder_cells")
		for cell: Vector2i in [Vector2i(13, 6), Vector2i(14, 6)]:
			if not moved.has(cell):
				failures.append("moved puzzle piece did not expose world cell %s" % cell)
		piece.set("is_void", true)
		if bool(piece.call("is_occluding")):
			failures.append("a void puzzle piece must not occlude sight")
		piece.queue_free()
		return failures


## tests/puzzle/test_one_way_occupancy.gd
class OneWayOccupancyCase extends Node:
	## Directional occupancy coverage for upward-facing one-way platforms.
	##
	## A one-way cell blocks entry from above (downward movement) but can be entered
	## from below, left, and right. Wall cells block every direction. The player
	## rider is an extra wall cell.

	const BoardOccupancy := preload("res://scripts/puzzle/core/board_occupancy.gd")
	const PieceDefinition := preload("res://scripts/puzzle/definition/piece_definition.gd")
	const PuzzleDefinition := preload("res://scripts/puzzle/definition/puzzle_definition.gd")
	const PuzzleMove := preload("res://scripts/puzzle/core/puzzle_move.gd")
	const PuzzleSession := preload("res://scripts/puzzle/systems/puzzle_session.gd")
	const SlidingPuzzleRuleSet := preload("res://scripts/puzzle/rules/sliding_puzzle_rule_set.gd")


	func run() -> Array[String]:
		var failures: Array[String] = []
		_assert_wall_enters_from_below(failures)
		_assert_wall_blocked_from_above(failures)
		_assert_wall_enters_from_sides(failures)
		_assert_one_way_enters_allowed_sides(failures)
		_assert_one_way_into_wall_blocked(failures)
		_assert_already_overlapping_can_move_down(failures)
		_assert_rider_counts_as_wall(failures)
		return failures


	func _assert_wall_enters_from_below(failures: Array[String]) -> void:
		var gate := _one_way("gate", Vector2i(2, 1))
		var wall := _wall("wall", Vector2i(2, 2))
		var def := _definition([gate, wall])
		if not _can_apply(def, 1, Vector2i(2, 2), Vector2i(2, 1)):
			failures.append("wall could not enter a one-way cell from below")


	func _assert_wall_blocked_from_above(failures: Array[String]) -> void:
		var gate := _one_way("gate", Vector2i(2, 1))
		var wall := _wall("wall", Vector2i(2, 0))
		var def := _definition([gate, wall])
		if _can_apply(def, 1, Vector2i(2, 0), Vector2i(2, 1)):
			failures.append("wall entered a one-way cell from above")


	func _assert_wall_enters_from_sides(failures: Array[String]) -> void:
		var gate := _one_way("gate", Vector2i(2, 1))
		var left_wall := _wall("left", Vector2i(1, 1))
		var right_wall := _wall("right", Vector2i(3, 1))
		if not _can_apply(_definition([gate, left_wall]), 1, Vector2i(1, 1), Vector2i(2, 1)):
			failures.append("wall could not enter a one-way cell from the left")
		if not _can_apply(_definition([gate, right_wall]), 1, Vector2i(3, 1), Vector2i(2, 1)):
			failures.append("wall could not enter a one-way cell from the right")


	func _assert_one_way_enters_allowed_sides(failures: Array[String]) -> void:
		var gate := _one_way("gate", Vector2i(2, 1))
		var below := _one_way("below", Vector2i(2, 2))
		var above := _one_way("above", Vector2i(2, 0))
		var left := _one_way("left", Vector2i(1, 1))
		var right := _one_way("right", Vector2i(3, 1))
		if not _can_apply(_definition([gate, below]), 1, Vector2i(2, 2), Vector2i(2, 1)):
			failures.append("one-way piece could not enter another one-way cell from below")
		if _can_apply(_definition([gate, above]), 1, Vector2i(2, 0), Vector2i(2, 1)):
			failures.append("one-way piece entered another one-way cell from above")
		if not _can_apply(_definition([gate, left]), 1, Vector2i(1, 1), Vector2i(2, 1)):
			failures.append("one-way piece could not enter another one-way cell from the left")
		if not _can_apply(_definition([gate, right]), 1, Vector2i(3, 1), Vector2i(2, 1)):
			failures.append("one-way piece could not enter another one-way cell from the right")


	func _assert_one_way_into_wall_blocked(failures: Array[String]) -> void:
		var mover := _one_way("mover", Vector2i(2, 1))
		var wall_below := _wall("below", Vector2i(2, 2))
		var wall_right := _wall("right", Vector2i(3, 1))
		if _can_apply(_definition([mover, wall_below]), 0, Vector2i(2, 1), Vector2i(2, 2)):
			failures.append("one-way piece entered a wall cell from above")
		if _can_apply(_definition([mover, wall_right]), 0, Vector2i(2, 1), Vector2i(3, 1)):
			failures.append("one-way piece entered a wall cell from the side")


	func _assert_already_overlapping_can_move_down(failures: Array[String]) -> void:
		var gate := _one_way("gate", Vector2i(2, 1))
		var tall_wall := _wall("tall", Vector2i(2, 0), [
			Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2),
		])
		var def := _definition([gate, tall_wall])
		var state := PuzzleSession.new(def).current_state
		var occupancy := BoardOccupancy.new(def)
		# The wall already covers the one-way cell at (2, 1); moving down keeps it
		# covered, so the downward entry rule must not block the slide.
		if not occupancy.can_place_piece(state, 1, Vector2i(2, 1), 1):
			failures.append("overlapping wall was blocked when moving down")


	func _assert_rider_counts_as_wall(failures: Array[String]) -> void:
		var gate := _one_way("gate", Vector2i(2, 1))
		var wall := _wall("wall", Vector2i(1, 0))
		var def := _definition([gate, wall])
		var state := PuzzleSession.new(def).current_state
		var occupancy := BoardOccupancy.new(def)
		occupancy.extra_offsets[0] = [Vector2i(0, -1)]
		if not occupancy.get_piece_wall_offsets(0).has(Vector2i(0, -1)):
			failures.append("rider offset was not registered as a wall cell")
		if occupancy.can_place_piece(state, 1, Vector2i(2, 0), 1):
			failures.append("piece moved into the rider's wall cell")
		var rules := SlidingPuzzleRuleSet.new(def)
		rules.set_rider(0, Vector2i(0, -1))
		if rules.can_apply_move(state, PuzzleMove.new(1, Vector2i(1, 0), Vector2i(2, 0))):
			failures.append("rule set allowed a move into the rider's wall cell")


	func _definition(pieces: Array) -> PuzzleDefinition:
		var def := PuzzleDefinition.new()
		def.board.board_size = Vector2i(5, 4)
		for piece: PieceDefinition in pieces:
			def.pieces.append(piece)
		return def


	func _wall(id: StringName, cell: Vector2i, cells: Array[Vector2i] = [Vector2i.ZERO]) -> PieceDefinition:
		var piece := PieceDefinition.new()
		piece.id = id
		piece.shape = _copy_cells(cells)
		piece.wall_shape = _copy_cells(cells)
		piece.one_way_shape = []
		piece.initial_cell = cell
		return piece


	func _one_way(id: StringName, cell: Vector2i, cells: Array[Vector2i] = [Vector2i.ZERO]) -> PieceDefinition:
		var piece := PieceDefinition.new()
		piece.id = id
		piece.shape = _copy_cells(cells)
		piece.wall_shape = []
		piece.one_way_shape = _copy_cells(cells)
		piece.initial_cell = cell
		return piece


	func _copy_cells(cells: Array[Vector2i]) -> Array[Vector2i]:
		var copy: Array[Vector2i] = []
		copy.append_array(cells)
		return copy


	func _can_apply(def: PuzzleDefinition, piece_index: int, from_cell: Vector2i, to_cell: Vector2i) -> bool:
		var rules := SlidingPuzzleRuleSet.new(def)
		var state := PuzzleSession.new(def).current_state
		return rules.can_apply_move(state, PuzzleMove.new(piece_index, from_cell, to_cell))


## tests/puzzle/test_puzzle_void_zone.gd
class PuzzleVoidZoneCase extends Node:
	## Coverage for player-only void regions: painted cells, collision body,
	## player collision-mask toggling, and the slider-mode exit guard.

	const VOID_ZONE_SCRIPT := preload("res://scripts/puzzle/view/puzzle_void_zone.gd")
	const PUZZLE_BOARD_SCRIPT := preload("res://scripts/puzzle/view/puzzle_board.gd")
	const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
	const TILESET := preload("res://resources/tilesets/primordial_tileset.tres")


	func run() -> Array[String]:
		var failures: Array[String] = []
		_assert_void_cells_and_body(failures)
		_assert_player_void_collision_toggle(failures)
		_assert_board_blocks_mode_exit_inside_void(failures)
		return failures


	func _assert_void_cells_and_body(failures: Array[String]) -> void:
		var zone := _make_zone(Vector2i(2, 3))
		add_child(zone)
		if not bool(zone.call("has_cell", Vector2i(2, 3))):
			failures.append("void zone did not read its painted cell")
		if not bool(zone.call("has_world_position", Vector2(20.0, 28.0))):
			failures.append("void zone did not map a world position to its cell")
		if bool(zone.call("has_world_position", Vector2(4.0, 4.0))):
			failures.append("void zone reported a cell that was not painted")
		var body := zone.get_node_or_null("VoidBody") as StaticBody2D
		if body == null:
			failures.append("void zone did not build its collision body")
		elif body.collision_layer != (1 << 3) or body.collision_mask != 0:
			failures.append("void zone body is not on the player-only void layer")
		elif body.get_child_count() != 1:
			failures.append("void zone body did not get one shape per painted cell")
		zone.free()


	func _assert_player_void_collision_toggle(failures: Array[String]) -> void:
		var player := PLAYER_SCENE.instantiate() as Node2D
		add_child(player)
		if (int(player.get("collision_mask")) & (1 << 3)) == 0:
			failures.append("player did not include the void layer in its collision mask")
		player.call("set_control_locked", true)
		if (int(player.get("collision_mask")) & (1 << 3)) != 0:
			failures.append("locked player still collided with the void layer")
		player.call("set_control_locked", false)
		if (int(player.get("collision_mask")) & (1 << 3)) == 0:
			failures.append("unlocked player did not restore void collision")
		player.free()


	func _assert_board_blocks_mode_exit_inside_void(failures: Array[String]) -> void:
		var board := PUZZLE_BOARD_SCRIPT.new() as Node2D
		board.set("board_size", Vector2i(8, 8))
		board.set("cell_size", 8)
		board.add_child(_make_zone(Vector2i(2, 2)))
		var player := Node2D.new()
		player.name = "TestPlayer"
		player.add_to_group("player")
		add_child(player)
		add_child(board)
		board.call("set_player_to_cell", Vector2i(2, 2))
		board.call("_enter_drag_mode")
		if int(board.get("mode")) != 1:
			failures.append("board did not enter slider mode")
		board.call("_exit_drag_mode")
		if int(board.get("mode")) != 1:
			failures.append("board exited slider mode while the player was inside void")
		board.call("set_player_to_cell", Vector2i(0, 0))
		board.call("_exit_drag_mode")
		if int(board.get("mode")) != 0:
			failures.append("board stayed in slider mode after the player left void")
		board.free()
		player.free()


	func _make_zone(cell: Vector2i) -> Node2D:
		var zone := VOID_ZONE_SCRIPT.new() as Node2D
		zone.name = "VoidZone"
		zone.set("cell_size", 8)
		var layer := TileMapLayer.new()
		layer.name = "VoidTiles"
		layer.tile_set = TILESET
		layer.collision_enabled = false
		layer.set_cell(cell, 0, Vector2i(0, 0))
		zone.add_child(layer)
		return zone


## tests/puzzle/test_void_slider.gd
class VoidSliderCase extends Node:
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


## tests/puzzle/test_start_room_void.gd
class StartRoomVoidCase extends Node:
	## Source-scene contract for the bottom-left void slider in room_start_00.

	const SOURCE := "res://scenes/levels/main_world/room_start_00.tscn"


	func run() -> Array[String]:
		var failures: Array[String] = []
		var scene: PackedScene = load(SOURCE)
		if scene == null:
			failures.append("room_start_00 source scene is missing")
			return failures
		var root: Node = scene.instantiate()
		add_child(root)
		var board := root.get_node_or_null("RoomContent/Entities/PuzzleBoard")
		if board == null:
			failures.append("room_start_00 has no PuzzleBoard")
			root.free()
			return failures
		var void_piece: PuzzleTilePiece = null
		for child in board.get_children():
			if child is PuzzleTilePiece and child.is_void:
				void_piece = child as PuzzleTilePiece
				break
		if void_piece == null:
			failures.append("room_start_00 has no void slider")
		else:
			if void_piece.get_logical_cell() != Vector2i(0, 14):
				failures.append("void slider is not at the bottom-left anchor (0, 14)")
			if void_piece.shape.size() != 91:
				failures.append("void slider footprint is not 13x7 (got %d cells)" % void_piece.shape.size())
			if void_piece.get_bounds() != Rect2i(0, 0, 13, 7):
				failures.append("void slider bounds are not 13x7")
			if void_piece.x_move_distance != 13 or void_piece.y_move_distance != 7:
				failures.append("void slider distances are not 13/7")
			if void_piece.get_node_or_null("VoidTiles") == null:
				failures.append("void slider has no VoidTiles layer")
			if void_piece.get_node_or_null("VoidBody") == null:
				failures.append("void slider did not build its runtime VoidBody")
			if board.call("get_piece_at_cell", Vector2i(2, 16)) != void_piece:
				failures.append("void slider was not selectable inside its footprint")
			var normal_pick: PuzzlePiece = board.call("get_piece_at_cell", Vector2i(2, 2))
			if normal_pick == null or normal_pick == void_piece:
				failures.append("a normal slider was not selectable outside the void footprint")
			for child in board.get_children():
				if child is PuzzleTilePiece and not child.is_void:
					var anchor_pick: PuzzlePiece = board.call("get_piece_at_cell", child.get_logical_cell())
					if anchor_pick == null or anchor_pick.is_void:
						failures.append("normal slider %s was not selectable at its anchor" % child.name)
		if root.get_node_or_null("RoomContent/Entities/PuzzleBoard/VoidZone") != null:
			failures.append("room_start_00 still has the static VoidZone placeholder")
		root.free()
		return failures


func run() -> Array[String]:
	var failures: Array[String] = []
	failures.append_array(_run_case(PieceEnableCase.new()))
	failures.append_array(_run_case(PieceFogOcclusionCase.new()))
	failures.append_array(_run_case(OneWayOccupancyCase.new()))
	failures.append_array(_run_case(PuzzleVoidZoneCase.new()))
	failures.append_array(_run_case(VoidSliderCase.new()))
	failures.append_array(_run_case(StartRoomVoidCase.new()))
	return failures


func _run_case(test: Node) -> Array[String]:
	add_child(test)
	var result: Array = test.call("run")
	test.queue_free()
	var failures: Array[String] = []
	failures.assign(result)
	return failures
