class_name MapConnection
extends Resource

@export var connection_id: StringName
@export var from_room_id: StringName
@export var to_room_id: StringName
@export var one_way := false
@export var metadata: Dictionary = {}


func connects(room_id: StringName) -> bool:
	return from_room_id == room_id or (not one_way and to_room_id == room_id)
