class_name BoardState
extends RefCounted

## The full logical state of a puzzle: nothing but the cells pieces occupy.
##
## Keep this free of Node2D/Physics references so a solver can run without a
## running scene tree.

var pieces: Array[PieceState] = []


func get_piece(piece_index: int) -> PieceState:
	if piece_index < 0 or piece_index >= pieces.size():
		return null
	return pieces[piece_index]


func find_piece_index(piece_id: StringName) -> int:
	for i in pieces.size():
		if pieces[i].id == piece_id:
			return i
	return -1


func duplicate_state() -> BoardState:
	var result := BoardState.new()
	for piece in pieces:
		result.pieces.append(PieceState.new(piece.id, piece.piece_index, piece.cell))
	return result


## Stable string fingerprint, used by solvers to deduplicate visited states.
func get_hash_key() -> String:
	var entries: Array[String] = []
	for piece in pieces:
		entries.append("%d:%d,%d" % [piece.piece_index, piece.cell.x, piece.cell.y])
	entries.sort()
	return "|".join(entries)
