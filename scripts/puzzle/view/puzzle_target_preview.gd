class_name PuzzleTargetPreview
extends Node2D

## Dashed rectangle shown at the cell a dragged block would move to.

var cell_size: int = 8
var preview_size: Vector2i = Vector2i.ONE
var dash_color: Color = Color(1.0, 1.0, 1.0, 0.9)


func setup(p_cell_size: int) -> void:
    cell_size = p_cell_size
    visible = false
    z_index = 20


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
    var top_left := rect.position
    var top_right := rect.position + Vector2(rect.size.x, 0.0)
    var bottom_right := rect.position + rect.size
    var bottom_left := rect.position + Vector2(0.0, rect.size.y)
    draw_dashed_line(top_left, top_right, dash_color, 1.0, 3.0)
    draw_dashed_line(top_right, bottom_right, dash_color, 1.0, 3.0)
    draw_dashed_line(bottom_right, bottom_left, dash_color, 1.0, 3.0)
    draw_dashed_line(bottom_left, top_left, dash_color, 1.0, 3.0)
