class_name WorldGraph
extends RefCounted

var _rooms: Dictionary[StringName, Dictionary] = {}
var _connections: Array[Dictionary] = []


func add_room(room_id: StringName, metadata: Dictionary = {}) -> bool:
	if room_id.is_empty() or _rooms.has(room_id):
		return false
	_rooms[room_id] = metadata.duplicate(true)
	return true


func has_room(room_id: StringName) -> bool:
	return _rooms.has(room_id)


func connect_rooms(
	from_room_id: StringName,
	to_room_id: StringName,
	bidirectional := false,
	metadata: Dictionary = {}
) -> bool:
	if not has_room(from_room_id) or not has_room(to_room_id):
		return false
	if not _add_connection(from_room_id, to_room_id, metadata):
		return false
	if bidirectional:
		_add_connection(to_room_id, from_room_id, metadata)
	return true


func get_neighbors(room_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for connection: Dictionary in _connections:
		if connection.get("from_room_id") == room_id:
			result.append(StringName(connection.get("to_room_id", StringName())))
	result.sort()
	return result


func get_connections() -> Array[Dictionary]:
	return _connections.duplicate(true)


func _add_connection(from_room_id: StringName, to_room_id: StringName, metadata: Dictionary) -> bool:
	for connection: Dictionary in _connections:
		if connection.get("from_room_id") == from_room_id and connection.get("to_room_id") == to_room_id:
			return false
	_connections.append({
		"from_room_id": from_room_id,
		"to_room_id": to_room_id,
		"metadata": metadata.duplicate(true),
	})
	return true
