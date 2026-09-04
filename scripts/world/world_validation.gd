class_name WorldValidation
extends RefCounted

const ROOM_DATA_SCRIPT: Script = preload("res://scripts/world/room_data.gd")
const ROOM_CONNECTION_DATA_SCRIPT: Script = preload("res://scripts/world/room_connection_data.gd")


static func validate_world(world: Resource) -> Array[String]:
	var errors: Array[String] = []
	if world == null:
		return ["world is null"]
	if world.world_id.is_empty():
		errors.append("world_id is empty")
	if world.rooms.is_empty():
		errors.append("world has no rooms")

	var room_ids: Dictionary[String, bool] = {}
	for room: Resource in world.rooms:
		if room == null:
			errors.append("world has null room")
			continue
		if not _is_room_data(room):
			errors.append("world has non-RoomData room resource")
			continue
		if room.room_id.is_empty():
			errors.append("room has empty room_id")
			continue
		if room_ids.has(room.room_id):
			errors.append("duplicate room_id: %s" % room.room_id)
		room_ids[room.room_id] = true
		if room.scene_path.is_empty():
			errors.append("room %s has empty scene_path" % room.room_id)
		if room.room_size_chunks.x < 1 or room.room_size_chunks.y < 1:
			errors.append("room %s has invalid room_size_chunks: %s" % [room.room_id, str(room.room_size_chunks)])

	if not world.start_room_id.is_empty() and not room_ids.has(world.start_room_id):
		errors.append("start_room_id does not reference a room: %s" % world.start_room_id)

	for room: Resource in world.rooms:
		if not _is_room_data(room) or room.room_id.is_empty():
			continue
		for adjacent_id: String in room.adjacent_room_ids:
			if adjacent_id == room.room_id:
				errors.append("room %s cannot list itself as adjacent" % room.room_id)
			elif not room_ids.has(adjacent_id):
				errors.append("room %s has unknown adjacent_room_id: %s" % [room.room_id, adjacent_id])

	for connection: Resource in world.connections:
		if connection == null:
			errors.append("world has null connection")
			continue
		if not _is_room_connection_data(connection):
			errors.append("world has non-RoomConnectionData connection resource")
			continue
		var connection_name := "%s->%s" % [connection.from_room_id, connection.to_room_id]
		if connection.from_room_id.is_empty():
			errors.append("connection has empty from_room_id")
		elif not room_ids.has(connection.from_room_id):
			errors.append("connection %s references unknown from_room_id" % connection_name)
		if connection.to_room_id.is_empty():
			errors.append("connection has empty to_room_id")
		elif not room_ids.has(connection.to_room_id):
			errors.append("connection %s references unknown to_room_id" % connection_name)
		if connection.from_entrance_id.is_empty():
			errors.append("connection %s has empty from_entrance_id" % connection_name)
		if connection.to_spawn_id.is_empty():
			errors.append("connection %s has empty to_spawn_id" % connection_name)

	return errors


static func _is_room_data(resource: Resource) -> bool:
	return resource != null and resource.get_script() == ROOM_DATA_SCRIPT


static func _is_room_connection_data(resource: Resource) -> bool:
	return resource != null and resource.get_script() == ROOM_CONNECTION_DATA_SCRIPT
