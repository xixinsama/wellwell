class_name PuzzleAimArrow
extends Node2D

## Runtime-only arrow preview from the selected slider to the right-stick target.

const LINE_COLOR := Color(1.0, 0.94, 0.52, 0.95)
const LINE_WIDTH := 1.0
const HEAD_LENGTH := 5.0
const HEAD_WIDTH := 4.0

var _from := Vector2.ZERO
var _to := Vector2.ZERO
var _has_target := false


func setup() -> void:
	z_index = 20
	visible = false
	queue_redraw()


func show_between(from_point: Vector2, to_point: Vector2) -> void:
	_from = from_point
	_to = to_point
	_has_target = true
	visible = true
	queue_redraw()


func hide_arrow() -> void:
	_has_target = false
	visible = false
	queue_redraw()


func get_aim_points() -> PackedVector2Array:
	return PackedVector2Array([_from, _to])


func _draw() -> void:
	if not _has_target:
		return
	var delta := _to - _from
	if delta.length_squared() <= 0.0001:
		return
	var direction := delta.normalized()
	draw_line(_from, _to, LINE_COLOR, LINE_WIDTH)
	var base := _to - direction * HEAD_LENGTH
	var perpendicular := Vector2(-direction.y, direction.x) * (HEAD_WIDTH * 0.5)
	draw_colored_polygon(
		PackedVector2Array([_to, base + perpendicular, base - perpendicular]),
		LINE_COLOR
	)
