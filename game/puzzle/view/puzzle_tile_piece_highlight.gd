@tool
class_name PuzzleTilePieceHighlight
extends Node2D

## Translucent footprint overlay drawn above a [PuzzleTilePiece]'s tile layers.

var _cells: Array[Vector2i] = []
var _cell_size: int = 8


func setup(cell_size: int, cells: Array[Vector2i]) -> void:
	_cell_size = maxi(1, cell_size)
	_cells.clear()
	_cells.append_array(cells)
	queue_redraw()


func _draw() -> void:
	if _cells.is_empty():
		return
	var fill := Color(1.0, 1.0, 1.0, 0.14)
	var border := Color(1.0, 1.0, 1.0, 0.85)
	for cell: Vector2i in _cells:
		var rect := Rect2(
			Vector2(cell) * float(_cell_size),
			Vector2(_cell_size, _cell_size)
		)
		draw_rect(rect, fill, true)
		draw_rect(rect, border, false, 1.0)
