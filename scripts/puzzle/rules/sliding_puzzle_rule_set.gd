class_name SlidingPuzzleRuleSet
extends PuzzleRuleSet

## Klotski ("华容道") rules: axis-aligned slides blocked by the board border,
## blocked cells, and other pieces' collision footprints.

@export var definition: PuzzleDefinition

var _occupancy: BoardOccupancy


func _init(p_definition: PuzzleDefinition = null) -> void:
	definition = p_definition


func _get_occupancy() -> BoardOccupancy:
	if definition != null and (_occupancy == null or _occupancy.definition != definition):
		_occupancy = BoardOccupancy.new(definition)
	return _occupancy


## All moves currently available, each travelling the piece's move_distance.
## Interactive input may call [method can_apply_move] directly instead.
func get_legal_moves(state: BoardState, extra_blocked_cells: Array[Vector2i] = []) -> Array[PuzzleMove]:
	var moves: Array[PuzzleMove] = []
	if state == null or definition == null:
		return moves
	var occupancy := _get_occupancy()
	if occupancy == null:
		return moves
	for piece in state.pieces:
		var distance := _piece_move_distance(piece)
		for axis: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if not _allows_direction(piece, axis):
				continue
			var move := PuzzleMove.new(piece.piece_index, piece.cell, piece.cell + axis * distance)
			if can_apply_move(state, move, extra_blocked_cells):
				moves.append(move)
	return moves


func can_apply_move(state: BoardState, move: PuzzleMove, extra_blocked_cells: Array[Vector2i] = []) -> bool:
	if state == null or move == null or definition == null:
		return false
	var occupancy := _get_occupancy()
	if occupancy == null:
		return false
	if move.piece_index < 0 or move.piece_index >= state.pieces.size():
		return false
	var piece := state.pieces[move.piece_index]
	if piece.cell != move.from_cell:
		return false

	var delta := move.to_cell - move.from_cell
	if delta == Vector2i.ZERO:
		return false
	if delta.x != 0 and delta.y != 0:
		return false

	var step := delta.sign()
	if not _allows_direction(piece, step):
		return false

	# Only the destination cells are checked. Intermediate cells are skipped, so
	# a multi-cell jump can enter a hollow block through surrounding walls.
	return occupancy.can_place_piece(state, move.piece_index, move.to_cell, move.piece_index, extra_blocked_cells)


func is_solved(state: BoardState) -> bool:
	if state == null or definition == null or definition.goal == null:
		return false
	return definition.goal.is_satisfied(state)


func _allows_direction(piece: PieceState, direction: Vector2i) -> bool:
	if definition == null or piece.piece_index < 0 or piece.piece_index >= definition.pieces.size():
		return false
	return definition.pieces[piece.piece_index].allows_axis(direction)


func _piece_move_distance(piece: PieceState) -> int:
	if definition == null or piece.piece_index < 0 or piece.piece_index >= definition.pieces.size():
		return 1
	return maxi(1, definition.pieces[piece.piece_index].move_distance)


## Glue a single extra cell (the player rider) onto [param piece_index]. The
## rider is then part of that piece's footprint for every occupancy question.
func set_rider(piece_index: int, offset: Vector2i) -> void:
	var occupancy := _get_occupancy()
	if occupancy == null:
		return
	var offsets: Array[Vector2i] = [offset]
	occupancy.extra_offsets.clear()
	occupancy.extra_offsets[piece_index] = offsets


func clear_rider() -> void:
	var occupancy := _get_occupancy()
	if occupancy != null:
		occupancy.extra_offsets.clear()
