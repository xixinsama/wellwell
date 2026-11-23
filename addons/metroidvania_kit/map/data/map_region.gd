class_name MapRegion
extends Resource

@export var region_id: StringName
@export var display_name := ""
@export var room_ids: Array[StringName] = []
@export var map_offset := Vector2i.ZERO


func contains_room(room_id: StringName) -> bool:
	return room_ids.has(room_id)
