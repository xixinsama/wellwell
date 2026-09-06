@tool
class_name WorldLayoutModel
extends RefCounted

const ROOM_DATA_SCRIPT: Script = preload("res://scripts/world/room_data.gd")
const ROOM_CONNECTION_DATA_SCRIPT: Script = preload("res://scripts/world/room_connection_data.gd")
const WORLD_VALIDATION: Script = preload("res://scripts/world/world_validation.gd")


func add_room(world: WorldData, room: RoomData) -> Dictionary:
	if world == null:
		return _error("world is null")
	if room == null:
		return _error("room is null")
	if room.room_id.is_empty():
		return _error("room has empty room_id")
	if world.has_room(room.room_id):
		return _error("duplicate room_id: %s" % room.room_id)
	world.rooms.append(room)
	world.sort_for_serialization()
	return _success()


func remove_room(world: WorldData, room_id: String) -> Dictionary:
	if world == null:
		return _error("world is null")
	if not world.has_room(room_id):
		return _error("room_id does not reference a room: %s" % room_id)
	for index: int in range(world.rooms.size() - 1, -1, -1):
		var room: Resource = world.rooms[index]
		if _is_room_data(room) and room.room_id == room_id:
			world.rooms.remove_at(index)
	for index: int in range(world.connections.size() - 1, -1, -1):
		var connection: Resource = world.connections[index]
		if not _is_room_connection_data(connection):
			continue
		if connection.from_room_id == room_id or connection.to_room_id == room_id:
			world.connections.remove_at(index)
	for room: Resource in world.rooms:
		if not _is_room_data(room):
			continue
		var adjacent_ids := PackedStringArray()
		for adjacent_id: String in room.adjacent_room_ids:
			if adjacent_id != room_id:
				adjacent_ids.append(adjacent_id)
		room.adjacent_room_ids = adjacent_ids
	if world.start_room_id == room_id:
		world.start_room_id = ""
		world.start_spawn_id = ""
	world.sort_for_serialization()
	return _success()


func move_room(world: WorldData, room_id: String, origin_chunk: Vector2i) -> Dictionary:
	if world == null:
		return _error("world is null")
	var room: Resource = world.get_room(room_id)
	if room == null:
		return _error("room_id does not reference a room: %s" % room_id)
	room.room_origin_chunk = origin_chunk
	return _success()


func connect_rooms(world: WorldData, connection: RoomConnectionData) -> Dictionary:
	if world == null:
		return _error("world is null")
	if connection == null:
		return _error("connection is null")
	if connection.from_room_id.is_empty() or connection.from_entrance_id.is_empty():
		return _error("connection source endpoint is incomplete")
	if connection.to_room_id.is_empty() or connection.to_spawn_id.is_empty():
		return _error("connection target endpoint is incomplete")
	if world.get_connection(connection.from_room_id, connection.from_entrance_id) != null:
		return _error(
			"duplicate connection source endpoint: %s:%s"
			% [connection.from_room_id, connection.from_entrance_id]
		)
	var source_room: Resource = world.get_room(connection.from_room_id)
	var target_room: Resource = world.get_room(connection.to_room_id)
	if source_room == null:
		return _error("connection references unknown from_room_id: %s" % connection.from_room_id)
	if target_room == null:
		return _error("connection references unknown to_room_id: %s" % connection.to_room_id)
	if not source_room.entrance_ids.has(connection.from_entrance_id):
		return _error("connection references unknown source entrance: %s" % connection.from_entrance_id)
	if not target_room.spawn_ids.has(connection.to_spawn_id):
		return _error("connection references unknown target spawn: %s" % connection.to_spawn_id)
	world.connections.append(connection)
	world.sort_for_serialization()
	return _success()


func disconnect_rooms(world: WorldData, from_room_id: String, from_entrance_id: String) -> Dictionary:
	if world == null:
		return _error("world is null")
	for index: int in range(world.connections.size()):
		var connection: Resource = world.connections[index]
		if not _is_room_connection_data(connection):
			continue
		if connection.from_room_id == from_room_id and connection.from_entrance_id == from_entrance_id:
			world.connections.remove_at(index)
			world.sort_for_serialization()
			return _success()
	return _error("connection source endpoint does not exist: %s:%s" % [from_room_id, from_entrance_id])


func validate_world(world: WorldData) -> Dictionary:
	return WORLD_VALIDATION.validate_world_report(world)


func capture_world_state(world: WorldData) -> Dictionary:
	if world == null:
		return {}
	var adjacency: Dictionary = {}
	for room: Resource in world.rooms:
		if _is_room_data(room):
			adjacency[room.room_id] = room.adjacent_room_ids.duplicate()
	return {
		"rooms": world.rooms.duplicate(),
		"connections": world.connections.duplicate(),
		"start_room_id": world.start_room_id,
		"start_spawn_id": world.start_spawn_id,
		"adjacency": adjacency,
	}


func restore_world_state(world: WorldData, state: Dictionary) -> Dictionary:
	if world == null:
		return _error("world is null")
	if not state.has("rooms") or not state.has("connections") or not state.has("adjacency"):
		return _error("world state is incomplete")
	world.rooms.assign(state["rooms"])
	world.connections.assign(state["connections"])
	world.start_room_id = String(state.get("start_room_id", ""))
	world.start_spawn_id = String(state.get("start_spawn_id", ""))
	var adjacency: Dictionary = state["adjacency"]
	for room: Resource in world.rooms:
		if _is_room_data(room) and adjacency.has(room.room_id):
			room.adjacent_room_ids = PackedStringArray(adjacency[room.room_id])
	world.sort_for_serialization()
	return _success()


func replace_room(world: WorldData, room_id: String, replacement: RoomData) -> Dictionary:
	if world == null:
		return _error("world is null")
	var current: Resource = world.get_room(room_id)
	if current == null:
		return _error("room_id does not reference a room: %s" % room_id)
	if replacement == null or replacement.room_id != room_id:
		return _error("replacement room_id does not match: %s" % room_id)
	replacement.room_origin_chunk = current.room_origin_chunk
	replacement.adjacent_room_ids = current.adjacent_room_ids.duplicate()
	for index: int in range(world.rooms.size()):
		if world.rooms[index] == current:
			world.rooms[index] = replacement
			world.sort_for_serialization()
			return _success()
	return _error("room reference could not be replaced: %s" % room_id)


func _success() -> Dictionary:
	return {"ok": true, "errors": [], "warnings": []}


func _error(message: String) -> Dictionary:
	return {"ok": false, "errors": [message], "warnings": []}


static func _is_room_data(resource: Resource) -> bool:
	return resource != null and resource.get_script() == ROOM_DATA_SCRIPT


static func _is_room_connection_data(resource: Resource) -> bool:
	return resource != null and resource.get_script() == ROOM_CONNECTION_DATA_SCRIPT
