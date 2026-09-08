@tool
class_name RegionData
extends Resource

@export var region_id: StringName
@export var display_name := ""
@export var room_ids := PackedStringArray()
@export var tags := PackedStringArray()


func contains_room(room_id: StringName) -> bool:
	return room_ids.has(String(room_id))
