@tool
class_name WaterBasin
extends Node2D

## Authored water basin marker.
##
## The rectangle's top edge is the water surface the basin starts with, and its
## width spans the basin columns. WaterField fills each column from that surface
## down to the terrain floor the first time the room is entered. Place basins
## under RoomContent/Entities so they bake with the room.

const CELL_PIXELS := 8
const PREVIEW_WATER := Color(0.24, 0.62, 0.92, 0.22)
const PREVIEW_SURFACE := Color(0.62, 0.9, 1.0, 0.9)
const PREVIEW_BORDER := Color(0.2, 0.45, 0.8, 0.75)

@export var size_cells := Vector2i(16, 6):
	set(value):
		size_cells = Vector2i(maxi(value.x, 1), maxi(value.y, 1))
		queue_redraw()
@export var basin_id := ""
## Initial surface offset from the rectangle's top edge, in pixels. Positive
## values start the water lower than the marker.
@export var surface_offset := 0.0:
	set(value):
		surface_offset = value
		queue_redraw()


func _ready() -> void:
	add_to_group(&"water_basin")
	if basin_id.is_empty():
		basin_id = String(name)
	queue_redraw()


func get_world_rect() -> Rect2:
	return Rect2(global_position, Vector2(size_cells) * CELL_PIXELS)


func get_initial_surface_y() -> float:
	return global_position.y + surface_offset


func get_basin_key(room_id: String) -> String:
	return "%s:%s" % [room_id, basin_id]


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var rect := Rect2(Vector2.ZERO, Vector2(size_cells) * CELL_PIXELS)
	draw_rect(rect, PREVIEW_WATER, true)
	draw_rect(rect, PREVIEW_BORDER, false, 1.0)
	var surface := Vector2(0.0, surface_offset)
	draw_line(surface, surface + Vector2(rect.size.x, 0.0), PREVIEW_SURFACE, 1.0)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(2, -2),
		"water %s" % basin_id,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		8,
		Color(1.0, 1.0, 1.0, 0.8)
	)
