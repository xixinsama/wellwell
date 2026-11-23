class_name DebugMap
extends Node2D

@export var map_model: Dictionary = {}
@export var chunk_pixel_size := Vector2(12.0, 8.0)
@export var offset := Vector2(8.0, 8.0)
@export var hidden_color := Color(0.12, 0.14, 0.18, 0.9)
@export var explored_color := Color(0.35, 0.7, 0.75, 0.95)
@export var current_color := Color(1.0, 0.85, 0.35, 1.0)

func set_map_model(value: Dictionary) -> void:
	map_model = value
	queue_redraw()

func _draw() -> void:
	for room: Dictionary in map_model.get("rooms", []):
		for chunk: Dictionary in room.get("chunks", []):
			var id_parts := String(chunk.id).split(":")
			if id_parts.size() < 3:
				continue
			var coords := id_parts[2].split(",")
			if coords.size() != 2:
				continue
			var pos := offset + Vector2(float(coords[0]), float(coords[1])) * chunk_pixel_size
			var color: Color = current_color if room.current else (explored_color if chunk.explored else hidden_color)
			draw_rect(Rect2(pos, chunk_pixel_size - Vector2.ONE), color, true)

