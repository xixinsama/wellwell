@tool
class_name WorldLayoutModel
extends RefCounted

const ROOM_DATA_SCRIPT: Script = preload("res://addons/platformer_kit/world/data/room_data.gd")
const ROOM_CONNECTION_DATA_SCRIPT: Script = preload("res://addons/platformer_kit/world/data/room_connection_data.gd")
const ROOM_PLACEMENT_DATA_SCRIPT: Script = preload("res://addons/platformer_kit/world/data/world_room_placement_data.gd")
const WORLD_VALIDATION: Script = preload("res://addons/platformer_kit/world/data/world_validation.gd")


func add_room(world: WorldData, room: RoomData, origin_chunk: Vector2i = Vector2i.ZERO) -> Dictionary:
	if world == null:
		return _error("world is null")
	if room == null:
		return _error("room is null")
	if room.room_id.is_empty():
		return _error("room has empty room_id")
	if world.has_room(room.room_id):
		return _error("duplicate room_id: %s" % room.room_id)
	world.rooms.append(room)
	if not world.set_room_origin_chunk(room.room_id, origin_chunk):
		world.rooms.erase(room)
		return _error("could not create placement for room: %s" % room.room_id)
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
	for index: int in range(world.placements.size() - 1, -1, -1):
		var placement: Resource = world.placements[index]
		if _is_room_placement_data(placement) and placement.room_id == room_id:
			world.placements.remove_at(index)
	for index: int in range(world.connections.size() - 1, -1, -1):
		var connection: Resource = world.connections[index]
		if not _is_room_connection_data(connection):
			continue
		if connection.from_room_id == room_id or connection.to_room_id == room_id:
			world.connections.remove_at(index)
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
	if not world.set_room_origin_chunk(room_id, origin_chunk):
		return _error("could not update placement for room: %s" % room_id)
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
	return {
		"rooms": world.rooms.duplicate(),
		"placements": _duplicate_resources(world.placements),
		"connections": world.connections.duplicate(),
		"start_room_id": world.start_room_id,
		"start_spawn_id": world.start_spawn_id,
	}


func restore_world_state(world: WorldData, state: Dictionary) -> Dictionary:
	if world == null:
		return _error("world is null")
	if not state.has("rooms") or not state.has("connections"):
		return _error("world state is incomplete")
	world.rooms.assign(state["rooms"])
	world.placements.assign(_duplicate_resources(state.get("placements", [])))
	world.connections.assign(state["connections"])
	world.start_room_id = String(state.get("start_room_id", ""))
	world.start_spawn_id = String(state.get("start_spawn_id", ""))
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
	for index: int in range(world.rooms.size()):
		if world.rooms[index] == current:
			world.rooms[index] = replacement
			world.sort_for_serialization()
			return _success()
	return _error("room reference could not be replaced: %s" % room_id)


func _success() -> Dictionary:
	return {"ok": true, "errors": [], "warnings": []}


func _success_with_warnings(values: Variant) -> Dictionary:
	var warnings: Array[String] = []
	for value: Variant in values:
		warnings.append(String(value))
	return {"ok": true, "errors": [], "warnings": warnings}


func _error(message: String) -> Dictionary:
	return {"ok": false, "errors": [message], "warnings": []}


func _from_world_result(result: Dictionary) -> Dictionary:
	return {
		"ok": false,
		"errors": result.get("errors", []),
		"warnings": result.get("warnings", []),
	}


func _duplicate_resources(values: Variant) -> Array[Resource]:
	var result: Array[Resource] = []
	for value: Variant in values:
		if value is Resource:
			result.append((value as Resource).duplicate(true))
	return result


static func _is_room_data(resource: Resource) -> bool:
	return resource != null and resource.get_script() == ROOM_DATA_SCRIPT


static func _is_room_connection_data(resource: Resource) -> bool:
	return resource != null and resource.get_script() == ROOM_CONNECTION_DATA_SCRIPT


static func _is_room_placement_data(resource: Resource) -> bool:
	return resource != null and resource.get_script() == ROOM_PLACEMENT_DATA_SCRIPT
