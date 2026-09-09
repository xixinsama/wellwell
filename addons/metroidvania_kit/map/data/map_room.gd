class_name MapRoom
extends Resource

@export var room_id: StringName
@export var world_room_id: StringName
@export var region_id: StringName
@export var map_position := Vector2i.ZERO
@export var map_size := Vector2i.ONE
@export var hidden_on_map := false
@export var metadata: Dictionary = {}


func get_world_room_id() -> StringName:
	return room_id if world_room_id.is_empty() else world_room_id
