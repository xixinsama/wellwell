class_name RoomTransition
extends RefCounted

const ROOM_CONNECTION_DATA_SCRIPT: Script = preload("res://scripts/world/room_connection_data.gd")

static func resolve(world: Resource, from_room_id: String, entrance: Node) -> Dictionary:
	if world == null or entrance == null:
		return {}
	var target_room_id := String(entrance.get("target_room_id"))
	var target_spawn_id := String(entrance.get("target_spawn_id"))
	if target_room_id.is_empty() or not world.has_room(target_room_id):
		return {}
	var entrance_id_value: Variant = entrance.get("entity_id")
	var entrance_id := "" if entrance_id_value == null else str(entrance_id_value)
	var match_count := 0
	for connection: Resource in world.connections:
		if connection == null or connection.get_script() != ROOM_CONNECTION_DATA_SCRIPT:
			continue
		if String(connection.get("from_room_id")) != from_room_id:
			continue
		if String(connection.get("from_entrance_id")) != entrance_id:
			continue
		match_count += 1
		if String(connection.get("to_room_id")) != target_room_id:
			return {}
		if String(connection.get("to_spawn_id")) != target_spawn_id:
			return {}
	if match_count != 1:
		return {}
	return {"from_room_id": from_room_id, "to_room_id": target_room_id, "to_spawn_id": target_spawn_id}
