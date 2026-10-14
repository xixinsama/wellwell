class_name PieceState
extends RefCounted

## Runtime position of a single puzzle piece.
##
## This is pure data: the real position lives in [member cell], never in a
## Node2D. The view layer only draws this state.

var id: StringName = &""
var piece_index: int = -1
var cell: Vector2i = Vector2i.ZERO


func _init(p_id: StringName = &"", p_index: int = -1, p_cell: Vector2i = Vector2i.ZERO) -> void:
	id = p_id
	piece_index = p_index
	cell = p_cell
