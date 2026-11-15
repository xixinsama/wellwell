extends Node

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
