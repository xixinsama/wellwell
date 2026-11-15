@tool
class_name WaterGate
extends Node2D

## Authored sluice gate between two basins.
##
## While closed, every water column overlapping the rectangle is blocked, so the
## higher basin keeps its water. After the room is entered the gate waits
## `open_delay_seconds`, then slides up over `slide_seconds`; WaterField notices
## and releases the columns so the water can flow.

const CELL_PIXELS := 8
const FRAME_COLOR := Color(0.29, 0.31, 0.38, 1.0)
const FRAME_LIGHT := Color(0.52, 0.56, 0.66, 1.0)
const PANEL_COLOR := Color(0.36, 0.42, 0.5, 1.0)
const PANEL_LIGHT := Color(0.62, 0.7, 0.8, 1.0)
const PANEL_DARK := Color(0.18, 0.21, 0.27, 1.0)
const EDITOR_PREVIEW := Color(0.95, 0.75, 0.25, 0.8)

@export var size_cells := Vector2i(3, 3):
	set(value):
		size_cells = Vector2i(maxi(value.x, 1), maxi(value.y, 1))
		queue_redraw()
@export var gate_id := ""
@export_range(0.0, 5.0, 0.05) var open_delay_seconds := 0.8
@export_range(0.05, 2.0, 0.05) var slide_seconds := 0.45

var _elapsed := 0.0
var _progress := 0.0
var _open := false


func _ready() -> void:
	add_to_group(&"water_gate")
	if gate_id.is_empty():
		gate_id = String(name)
	_elapsed = 0.0
	_progress = 0.0
	_open = false
	queue_redraw()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _open:
		return
	_elapsed += maxf(delta, 0.0)
	var opening := _elapsed - open_delay_seconds
	if opening <= 0.0:
		return
	_progress = clampf(opening / maxf(slide_seconds, 0.01), 0.0, 1.0)
	if _progress >= 1.0:
		_open = true
	queue_redraw()


func is_open() -> bool:
	return _open


func is_opening() -> bool:
	return _progress > 0.0 and not _open


func get_progress() -> float:
	return _progress


func get_world_rect() -> Rect2:
	return Rect2(global_position, Vector2(size_cells) * CELL_PIXELS)


func reset() -> void:
	_elapsed = 0.0
	_progress = 0.0
	_open = false
	queue_redraw()


func _draw() -> void:
	var size := Vector2(size_cells) * CELL_PIXELS
	if Engine.is_editor_hint():
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.2, 0.25, 0.35, 0.35), true)
		draw_rect(Rect2(Vector2.ZERO, size), EDITOR_PREVIEW, false, 1.0)
		draw_string(
			ThemeDB.fallback_font,
			Vector2(2, size.y * 0.5 + 3.0),
			"gate",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			8,
			Color(1.0, 1.0, 1.0, 0.85)
		)
		return
	var lift := size.y * _progress
	var panel := Rect2(0.0, -lift, size.x, size.y)
	# Recessed guide rails on both sides stay put while the panel slides up.
	draw_rect(Rect2(-1.0, 0.0, 1.0, size.y), FRAME_COLOR, true)
	draw_rect(Rect2(size.x, 0.0, 1.0, size.y), FRAME_COLOR, true)
	draw_rect(panel, PANEL_COLOR, true)
	draw_rect(panel, PANEL_LIGHT, false, 1.0)
	for row: int in range(0, int(size.y), 6):
		var y := row + 3.0 - lift
		draw_line(Vector2(1.0, y), Vector2(size.x - 1.0, y), PANEL_DARK, 1.0)
	var wheel := Vector2(size.x * 0.5, size.y * 0.5 - lift)
	draw_circle(wheel, 2.0, PANEL_DARK)
	draw_circle(wheel, 1.0, FRAME_LIGHT)
