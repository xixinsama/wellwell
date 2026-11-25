class_name PuzzleTurn
extends RefCounted

## A primary move plus every void move induced by it.
##
## The first move is always the piece the player moved. Remaining moves are
## void sliders pushed by that primary move. The session applies the whole turn
## atomically.

var moves: Array[PuzzleMove] = []


func add(piece_index: int, from_cell: Vector2i, to_cell: Vector2i) -> void:
	moves.append(PuzzleMove.new(piece_index, from_cell, to_cell))


func is_empty() -> bool:
	return moves.is_empty()
