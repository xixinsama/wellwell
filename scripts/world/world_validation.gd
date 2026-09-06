@tool
class_name WorldValidation
extends RefCounted

const ROOM_DATA_SCRIPT: Script = preload("res://scripts/world/room_data.gd")
const ROOM_CONNECTION_DATA_SCRIPT: Script = preload("res://scripts/world/room_connection_data.gd")
const WORLD_DATA_SCRIPT: Script = preload("res://scripts/world/world_data.gd")


static func validate_world(world: Resource) -> Array[String]:
	var report := validate_world_report(world)
	var errors: Array[String] = []
	errors.assign(report.get("errors", []))
	return errors


static func validate_world_report(world: Resource) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	if world == null:
		return {"ok": false, "errors": ["world is null"], "warnings": []}
	if world.get_script() != WORLD_DATA_SCRIPT:
		return {"ok": false, "errors": ["world is not WorldData"], "warnings": []}
	if world.world_id.is_empty():
		errors.append("world_id is empty")
	if world.rooms.is_empty():
		errors.append("world has no rooms")

	var room_by_id: Dictionary = {}
	var valid_rooms: Array[Resource] = []
	for room: Resource in world.rooms:
		_validate_room(room, room_by_id, valid_rooms, errors)

	_validate_start(world, room_by_id, errors)
	_validate_adjacency(valid_rooms, room_by_id, errors)
	var connected_entrances: Dictionary = {}
	var valid_connection_targets: Dictionary = {}
	_validate_connections(
		world.connections,
		room_by_id,
		connected_entrances,
		valid_connection_targets,
		errors
	)
	_validate_overlaps(valid_rooms, warnings)
	_validate_unconnected_entrances(valid_rooms, connected_entrances, warnings)
	_validate_reachability(world, room_by_id, valid_connection_targets, warnings)

	errors = _sorted_unique(errors)
	warnings = _sorted_unique(warnings)
	return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings}


static func _validate_room(
	room: Resource,
	room_by_id: Dictionary,
	valid_rooms: Array[Resource],
	errors: Array[String]
) -> void:
	if room == null:
		errors.append("world has null room")
		return
	if not _is_room_data(room):
		errors.append("world has non-RoomData room resource")
		return
	if room.room_id.is_empty():
		errors.append("room has empty room_id")
		return
	if room_by_id.has(room.room_id):
		errors.append("duplicate room_id: %s" % room.room_id)
	else:
		room_by_id[room.room_id] = room
		valid_rooms.append(room)
	if room.scene_path.is_empty():
		errors.append("room %s has empty scene_path" % room.room_id)
	if room.source_scene_path.is_empty():
		errors.append("room %s has empty source_scene_path" % room.room_id)
	if room.terrain_scene_path.is_empty():
		errors.append("room %s has empty terrain_scene_path" % room.room_id)
	if room.room_size_chunks.x < 1 or room.room_size_chunks.y < 1:
		errors.append("room %s has invalid room_size_chunks: %s" % [room.room_id, str(room.room_size_chunks)])
	_validate_manifest_ids(room.room_id, "entrance", room.entrance_ids, errors)
	_validate_manifest_ids(room.room_id, "spawn", room.spawn_ids, errors)
	_validate_manifest_ids(room.room_id, "entity", room.entity_ids, errors)


static func _validate_manifest_ids(
	room_id: String,
	id_kind: String,
	values: PackedStringArray,
	errors: Array[String]
) -> void:
	var seen: Dictionary = {}
	for value: String in values:
		if value.is_empty():
			errors.append("room %s has empty %s_id" % [room_id, id_kind])
		elif seen.has(value):
			errors.append("room %s has duplicate %s_id: %s" % [room_id, id_kind, value])
		else:
			seen[value] = true


static func _validate_start(world: Resource, room_by_id: Dictionary, errors: Array[String]) -> void:
	if world.start_room_id.is_empty():
		errors.append("start_room_id is empty")
		return
	if not room_by_id.has(world.start_room_id):
		errors.append("start_room_id does not reference a room: %s" % world.start_room_id)
		return
	if world.start_spawn_id.is_empty():
		errors.append("start_spawn_id is empty")
		return
	var start_room: Resource = room_by_id[world.start_room_id]
	if not start_room.spawn_ids.has(world.start_spawn_id):
		errors.append(
			"start_spawn_id does not reference a spawn in room %s: %s"
			% [world.start_room_id, world.start_spawn_id]
		)


static func _validate_adjacency(
	rooms: Array[Resource],
	room_by_id: Dictionary,
	errors: Array[String]
) -> void:
	for room: Resource in rooms:
		for adjacent_id: String in room.adjacent_room_ids:
			if adjacent_id == room.room_id:
				errors.append("room %s cannot list itself as adjacent" % room.room_id)
			elif not room_by_id.has(adjacent_id):
				errors.append("room %s has unknown adjacent_room_id: %s" % [room.room_id, adjacent_id])


static func _validate_connections(
	connections: Array[Resource],
	room_by_id: Dictionary,
	connected_entrances: Dictionary,
	valid_connection_targets: Dictionary,
	errors: Array[String]
) -> void:
	var source_endpoints: Dictionary = {}
	for connection: Resource in connections:
		if connection == null:
			errors.append("world has null connection")
			continue
		if not _is_room_connection_data(connection):
			errors.append("world has non-RoomConnectionData connection resource")
			continue
		var connection_name := "%s->%s" % [connection.from_room_id, connection.to_room_id]
		var source_room: Resource = room_by_id.get(connection.from_room_id)
		var target_room: Resource = room_by_id.get(connection.to_room_id)
		var source_key := "%s\u001f%s" % [connection.from_room_id, connection.from_entrance_id]
		var duplicate_source := false
		if connection.from_room_id.is_empty():
			errors.append("connection has empty from_room_id")
		elif source_room == null:
			errors.append("connection %s references unknown from_room_id" % connection_name)
		if connection.to_room_id.is_empty():
			errors.append("connection has empty to_room_id")
		elif target_room == null:
			errors.append("connection %s references unknown to_room_id" % connection_name)
		if connection.from_entrance_id.is_empty():
			errors.append("connection %s has empty from_entrance_id" % connection_name)
		elif source_room != null:
			if source_endpoints.has(source_key):
				duplicate_source = true
				errors.append(
					"duplicate connection source endpoint: %s:%s"
					% [connection.from_room_id, connection.from_entrance_id]
				)
			else:
				source_endpoints[source_key] = true
			if not source_room.entrance_ids.has(connection.from_entrance_id):
				errors.append(
					"connection %s references unknown source entrance: %s"
					% [connection_name, connection.from_entrance_id]
				)
		if connection.to_spawn_id.is_empty():
			errors.append("connection %s has empty to_spawn_id" % connection_name)
		elif target_room != null and not target_room.spawn_ids.has(connection.to_spawn_id):
			errors.append(
				"connection %s references unknown target spawn: %s"
				% [connection_name, connection.to_spawn_id]
			)
		var source_is_valid: bool = (
			source_room != null
			and not connection.from_entrance_id.is_empty()
			and source_room.entrance_ids.has(connection.from_entrance_id)
			and not duplicate_source
		)
		var target_is_valid: bool = (
			target_room != null
			and not connection.to_spawn_id.is_empty()
			and target_room.spawn_ids.has(connection.to_spawn_id)
		)
		if source_is_valid and target_is_valid:
			connected_entrances[source_key] = true
			var targets: Dictionary = valid_connection_targets.get(connection.from_room_id, {})
			targets[connection.to_room_id] = true
			valid_connection_targets[connection.from_room_id] = targets


static func _validate_overlaps(rooms: Array[Resource], warnings: Array[String]) -> void:
	var sorted_rooms := rooms.duplicate()
	sorted_rooms.sort_custom(func(left: Resource, right: Resource) -> bool: return left.room_id < right.room_id)
	for left_index: int in range(sorted_rooms.size()):
		var left: Resource = sorted_rooms[left_index]
		for right_index: int in range(left_index + 1, sorted_rooms.size()):
			var right: Resource = sorted_rooms[right_index]
			if left.get_chunk_rect().intersects(right.get_chunk_rect()):
				warnings.append("overlapping rooms: %s, %s" % [left.room_id, right.room_id])


static func _validate_unconnected_entrances(
	rooms: Array[Resource],
	connected_entrances: Dictionary,
	warnings: Array[String]
) -> void:
	for room: Resource in rooms:
		for entrance_id: String in room.entrance_ids:
			if entrance_id.is_empty():
				continue
			var source_key := "%s\u001f%s" % [room.room_id, entrance_id]
			if not connected_entrances.has(source_key):
				warnings.append("room %s has unconnected entrance: %s" % [room.room_id, entrance_id])


static func _validate_reachability(
	world: Resource,
	room_by_id: Dictionary,
	valid_connection_targets: Dictionary,
	warnings: Array[String]
) -> void:
	if not room_by_id.has(world.start_room_id):
		return
	var reached: Dictionary = {world.start_room_id: true}
	var pending: Array[String] = [world.start_room_id]
	while not pending.is_empty():
		var current_id: String = pending.pop_front()
		var targets: Dictionary = valid_connection_targets.get(current_id, {})
		for target_id: String in targets.keys():
			if not reached.has(target_id):
				reached[target_id] = true
				pending.append(target_id)
	for room_id: String in room_by_id.keys():
		if not reached.has(room_id):
			warnings.append("room %s is unreachable from start room" % room_id)


static func _sorted_unique(values: Array[String]) -> Array[String]:
	var seen: Dictionary = {}
	for value: String in values:
		seen[value] = true
	var result: Array[String] = []
	result.assign(seen.keys())
	result.sort()
	return result


static func _is_room_data(resource: Resource) -> bool:
	return resource != null and resource.get_script() == ROOM_DATA_SCRIPT


static func _is_room_connection_data(resource: Resource) -> bool:
	return resource != null and resource.get_script() == ROOM_CONNECTION_DATA_SCRIPT
