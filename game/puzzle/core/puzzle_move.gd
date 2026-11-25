class_name PuzzleMove
extends RefCounted

## A single, immutable-feeling record of one piece moving in a straight line.
##
## Moves are first-class objects so undo, redo, replay and solvers all share
## the same currency.

var piece_index: int = -1
var from_cell: Vector2i = Vector2i.ZERO
var to_cell: Vector2i = Vector2i.ZERO


func _init(p_piece_index: int = -1, p_from_cell: Vector2i = Vector2i.ZERO, p_to_cell: Vector2i = Vector2i.ZERO) -> void:
	piece_index = p_piece_index
	from_cell = p_from_cell
	to_cell = p_to_cell


## Unit direction of the move, e.g. Vector2i.RIGHT. Zero for a no-op move.
func get_direction() -> Vector2i:
	return (to_cell - from_cell).sign()


## Cell distance travelled along the dominant axis.
func get_distance() -> int:
	var delta := to_cell - from_cell
	return maxi(absi(delta.x), absi(delta.y))


func is_axis_aligned() -> bool:
	var delta := to_cell - from_cell
	return delta.x == 0 or delta.y == 0


func get_inverse() -> PuzzleMove:
	return PuzzleMove.new(piece_index, to_cell, from_cell)
