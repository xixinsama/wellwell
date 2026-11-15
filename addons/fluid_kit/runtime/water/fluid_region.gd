@tool
class_name FluidRegion
extends Node2D

## Authored fluid region for the 2D grid. The rectangle is *filled* with water:
## every open cell inside it starts full, and any tile wall inside it simply keeps
## water out, so the region holds less than its area when it overlaps terrain.
##
## WaterGrid reads these markers when a room is entered, then simulates the whole
## room. Place regions under RoomContent/Entities so they bake with the room.

const CELL_PIXELS := 8
const PREVIEW_WATER := Color(0.22, 0.6, 0.95, 0.26)
const PREVIEW_BORDER := Color(0.55, 0.85, 1.0, 0.9)
const PREVIEW_HATCH := Color(0.55, 0.85, 1.0, 0.35)

@export var size_cells := Vector2i(16, 8):
	set(value):
		size_cells = Vector2i(maxi(value.x, 1), maxi(value.y, 1))
		queue_redraw()
@export var region_id := ""


func _ready() -> void:
	add_to_group(&"fluid_region")
	if region_id.is_empty():
		region_id = String(name)
	queue_redraw()


func get_world_rect() -> Rect2:
	return Rect2(global_position, Vector2(size_cells) * CELL_PIXELS)


func get_cell_rect() -> Rect2i:
	return Rect2i(Vector2i(global_position) / CELL_PIXELS, size_cells)


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var rect := Rect2(Vector2.ZERO, Vector2(size_cells) * CELL_PIXELS)
	draw_rect(rect, PREVIEW_WATER, true)
	# Diagonal hatch so a filled region is easy to tell from a basin marker.
	var step := 8.0
	var span := rect.size.x + rect.size.y
	var offset := 0.0
	while offset < span:
		var start := Vector2(maxf(offset - rect.size.y, 0.0), minf(offset, rect.size.y))
		var end := Vector2(minf(offset, rect.size.x), maxf(offset - rect.size.x, 0.0))
		draw_line(start, end, PREVIEW_HATCH, 1.0)
		offset += step
	draw_rect(rect, PREVIEW_BORDER, false, 1.0)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(2, -2),
		"fluid %dx%d %s" % [size_cells.x, size_cells.y, region_id],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		8,
		Color(1.0, 1.0, 1.0, 0.85)
	)
