class_name BoardOccupancy
extends RefCounted

## Answers the "does this placement collide?" questions in cell space.
##
## This is the logical counterpart of the pieces' collision walls: a piece may
## not slide when its swept collision wall would overlap another piece's
## collision wall (or the board border / blocked cells).

var definition: PuzzleDefinition


func _init(p_definition: PuzzleDefinition) -> void:
	definition = p_definition


func get_piece_shape(piece_index: int) -> Array[Vector2i]:
	if definition == null or piece_index < 0 or piece_index >= definition.pieces.size():
		return []
	return definition.pieces[piece_index].shape


## Every cell a piece covers when its anchor cell is [param cell].
func get_occupied_cells(piece_index: int, cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for offset: Vector2i in get_piece_shape(piece_index):
		cells.append(cell + offset)
	return cells


func is_cell_inside_board(cell: Vector2i) -> bool:
	return definition != null and definition.board != null and definition.board.contains_cell(cell)


func is_cell_blocked(cell: Vector2i) -> bool:
	return definition != null and definition.board != null and definition.board.is_cell_blocked(cell)


## Whether the piece can rest at [param cell] without leaving the board,
## touching a blocked cell, or overlapping another piece.
## [param ignore_piece_index] is usually the moving piece itself.
func can_place_piece(state: BoardState, piece_index: int, cell: Vector2i, ignore_piece_index: int = -1) -> bool:
	if state == null:
		return false
	for occupied: Vector2i in get_occupied_cells(piece_index, cell):
		if not is_cell_inside_board(occupied):
			return false
		if is_cell_blocked(occupied):
			return false

	for other in state.pieces:
		if other.piece_index == ignore_piece_index:
			continue
		for occupied: Vector2i in get_occupied_cells(other.piece_index, other.cell):
			if _piece_covers_cell(piece_index, cell, occupied):
				return false
	return true


func _piece_covers_cell(piece_index: int, cell: Vector2i, target: Vector2i) -> bool:
	for offset: Vector2i in get_piece_shape(piece_index):
		if cell + offset == target:
			return true
	return false
