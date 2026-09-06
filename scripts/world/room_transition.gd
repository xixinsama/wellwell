class_name RoomTransition
extends RefCounted

const ROOM_CONNECTION_DATA_SCRIPT: Script = preload("res://scripts/world/room_connection_data.gd")

static func resolve(world: Resource, from_room_id: String, entrance: Node) -> Dictionary:
	if world == null or entrance == null:
		return {}
	var entrance_id_value: Variant = entrance.get("entity_id")
	var entrance_id := "" if entrance_id_value == null else str(entrance_id_value)
	if entrance_id.is_empty() or not world.has_method("get_connection"):
		return {}
	var connection: Resource = world.get_connection(from_room_id, entrance_id)
	if connection == null or connection.get_script() != ROOM_CONNECTION_DATA_SCRIPT:
		return {}
	if connection.to_room_id.is_empty() or not world.has_room(connection.to_room_id):
		return {}
	if connection.to_spawn_id.is_empty():
		return {}
	return {
		"from_room_id": from_room_id,
		"to_room_id": connection.to_room_id,
		"to_spawn_id": connection.to_spawn_id,
	}
