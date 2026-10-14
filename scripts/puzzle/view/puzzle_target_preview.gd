class_name PuzzleTargetPreview
extends Node2D

## Dashed rectangle shown at the cell a dragged block would move to.

var cell_size: int = 8
var preview_size: Vector2i = Vector2i.ONE
var dash_color: Color = Color(1.0, 1.0, 1.0, 0.9)


func setup(p_cell_size: int) -> void:
	cell_size = p_cell_size
	visible = false
	z_index = 10


func show_at(cell: Vector2i, size: Vector2i) -> void:
	preview_size = size
	dash_color = Color(1.0, 1.0, 1.0, 0.9)
	modulate = Color.WHITE
	position = Vector2(cell) * float(cell_size)
	visible = true
	queue_redraw()


func set_invalid() -> void:
	dash_color = Color(1.0, 0.2, 0.2, 0.95)
	queue_redraw()


func hide_preview() -> void:
	visible = false


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, Vector2(preview_size) * float(cell_size))
	var tl := rect.position
	var tr := rect.position + Vector2(rect.size.x, 0.0)
	var br := rect.position + rect.size
	var bl := rect.position + Vector2(0.0, rect.size.y)
	draw_dashed_line(tl, tr, dash_color, 1.0, 3.0)
	draw_dashed_line(tr, br, dash_color, 1.0, 3.0)
	draw_dashed_line(br, bl, dash_color, 1.0, 3.0)
	draw_dashed_line(bl, tl, dash_color, 1.0, 3.0)
