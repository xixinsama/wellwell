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


## All single-cell moves currently available. Multi-cell drags use
## [method can_apply_move] directly.
func get_legal_moves(state: BoardState) -> Array[PuzzleMove]:
	var moves: Array[PuzzleMove] = []
	if state == null or definition == null:
		return moves
	var occupancy := _get_occupancy()
	if occupancy == null:
		return moves
	for piece in state.pieces:
		for axis: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if not _allows_direction(piece, axis):
				continue
			var move := PuzzleMove.new(piece.piece_index, piece.cell, piece.cell + axis)
			if can_apply_move(state, move):
				moves.append(move)
	return moves


func can_apply_move(state: BoardState, move: PuzzleMove) -> bool:
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

	# Sweep one cell at a time, including the final cell, so the whole
	# collision wall must fit on every step of the path.
	var current := move.from_cell
	while current != move.to_cell:
		current += step
		if not occupancy.can_place_piece(state, move.piece_index, current, move.piece_index):
			return false
	return true


func is_solved(state: BoardState) -> bool:
	if state == null or definition == null or definition.goal == null:
		return false
	return definition.goal.is_satisfied(state)


func _allows_direction(piece: PieceState, direction: Vector2i) -> bool:
	if definition == null or piece.piece_index < 0 or piece.piece_index >= definition.pieces.size():
		return false
	return definition.pieces[piece.piece_index].allows_axis(direction)
