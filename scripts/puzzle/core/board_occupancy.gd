class_name BoardOccupancy
extends RefCounted

## Answers the "does this placement collide?" questions in cell space.
##
## Wall cells block every direction. Upward-facing one-way platform cells only
## block entry from above; they can be entered from below, left, and right. Two
## pieces may therefore overlap when the destination cell is a one-way cell and
## the move approaches from an allowed direction.
##
## The player rider is registered as an extra wall cell, so it follows the same
## rules as a wall when another piece tries to enter its cell.

## Upward-facing platforms block movement down into their cell.
const ONE_WAY_BLOCKED_ENTRY := Vector2i.DOWN

var definition: PuzzleDefinition
## Extra relative cells glued to a piece (piece_index -> Array[Vector2i]).
## The view layer registers the player here so it moves as part of one piece.
var extra_offsets: Dictionary = {}


func _init(p_definition: PuzzleDefinition = null) -> void:
	definition = p_definition


func get_piece_shape(piece_index: int) -> Array[Vector2i]:
	if definition == null or piece_index < 0 or piece_index >= definition.pieces.size():
		return []
	return definition.pieces[piece_index].shape


## Offsets of cells that block from every direction. Legacy pieces that only
## define [member PieceDefinition.shape] are treated as all-wall.
func get_piece_wall_offsets(piece_index: int) -> Array[Vector2i]:
	var offsets: Array[Vector2i] = []
	if definition == null or piece_index < 0 or piece_index >= definition.pieces.size():
		return offsets
	var piece := definition.pieces[piece_index]
	if piece.is_void:
		return offsets
	if piece.wall_shape.is_empty() and piece.one_way_shape.is_empty():
		_append_unique(offsets, piece.shape)
	else:
		_append_unique(offsets, piece.wall_shape)
	var extras: Variant = extra_offsets.get(piece_index)
	if extras is Array:
		for extra: Vector2i in extras:
			if not offsets.has(extra):
				offsets.append(extra)
	return offsets


## Offsets of upward-facing one-way platform cells.
func get_piece_one_way_offsets(piece_index: int) -> Array[Vector2i]:
	var offsets: Array[Vector2i] = []
	if definition == null or piece_index < 0 or piece_index >= definition.pieces.size():
		return offsets
	var piece := definition.pieces[piece_index]
	if piece.is_void:
		return offsets
	if piece.wall_shape.is_empty() and piece.one_way_shape.is_empty():
		return offsets
	_append_unique(offsets, piece.one_way_shape)
	return offsets


## The piece's wall cells, one-way cells and any registered extra cells.
func get_piece_offsets(piece_index: int) -> Array[Vector2i]:
	var offsets: Array[Vector2i] = []
	if definition == null or piece_index < 0 or piece_index >= definition.pieces.size():
		return offsets
	if definition.pieces[piece_index].is_void:
		_append_unique(offsets, definition.pieces[piece_index].shape)
		return offsets
	_append_unique(offsets, get_piece_wall_offsets(piece_index))
	_append_unique(offsets, get_piece_one_way_offsets(piece_index))
	return offsets


## Every cell a piece covers when its anchor cell is [param cell].
func get_occupied_cells(piece_index: int, cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for offset: Vector2i in get_piece_offsets(piece_index):
		cells.append(cell + offset)
	return cells


func is_cell_inside_board(cell: Vector2i) -> bool:
	return definition != null and definition.board != null and definition.board.contains_cell(cell)


func is_cell_blocked(cell: Vector2i) -> bool:
	return definition != null and definition.board != null and definition.board.is_cell_blocked(cell)


## Whether the piece can rest at [param cell] without leaving the board,
## touching a blocked cell, or illegally overlapping another piece.
##
## [param ignore_piece_index] is usually the moving piece itself. Extra blocked
## cells are always walls (the player when it is not riding). Overlap is allowed
## only when the destination cell is a one-way cell and either the moving piece
## already covers that world cell or the move is not downward.
func can_place_piece(state: BoardState, piece_index: int, cell: Vector2i, ignore_piece_index: int = -1, extra_blocked_cells: Array[Vector2i] = []) -> bool:
	if state == null or definition == null:
		return false
	if piece_index < 0 or piece_index >= state.pieces.size():
		return false

	var current_cell := state.pieces[piece_index].cell
	var step := (cell - current_cell).sign()
	var current_cells: Dictionary = {}
	for current: Vector2i in get_occupied_cells(piece_index, current_cell):
		current_cells[current] = true

	var moving_is_void := definition.pieces[piece_index].is_void
	var other_wall_cells: Dictionary = {}
	var other_one_way_cells: Dictionary = {}
	for other in state.pieces:
		if other.piece_index == ignore_piece_index or other.piece_index == piece_index:
			continue
		if definition.pieces[other.piece_index].is_void:
			continue
		for offset: Vector2i in get_piece_wall_offsets(other.piece_index):
			other_wall_cells[other.cell + offset] = true
		for offset: Vector2i in get_piece_one_way_offsets(other.piece_index):
			other_one_way_cells[other.cell + offset] = true

	for occupied: Vector2i in get_occupied_cells(piece_index, cell):
		if not is_cell_inside_board(occupied):
			return false
		if is_cell_blocked(occupied):
			return false
		if extra_blocked_cells.has(occupied):
			return false
		if moving_is_void:
			continue
		if other_wall_cells.has(occupied):
			return false
		if other_one_way_cells.has(occupied) and not current_cells.has(occupied):
			if step == ONE_WAY_BLOCKED_ENTRY:
				return false
	return true


func _append_unique(target: Array[Vector2i], cells: Array[Vector2i]) -> void:
	for cell: Vector2i in cells:
		if not target.has(cell):
			target.append(cell)
