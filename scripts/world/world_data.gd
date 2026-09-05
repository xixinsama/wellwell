class_name WorldData
extends Resource

const ROOM_DATA_SCRIPT: Script = preload("res://scripts/world/room_data.gd")
const ROOM_CONNECTION_DATA_SCRIPT: Script = preload("res://scripts/world/room_connection_data.gd")

@export var world_id := ""
@export var start_room_id := ""
@export var start_spawn_id := ""
@export var rooms: Array[Resource] = []
@export var connections: Array[Resource] = []
@export var tags: PackedStringArray = []


func get_room(room_id: String) -> Resource:
	for room: Resource in rooms:
		if _is_room_data(room) and room.room_id == room_id:
			return room
	return null


func has_room(room_id: String) -> bool:
	return get_room(room_id) != null


func get_room_ids() -> Array[String]:
	var result: Array[String] = []
	for room: Resource in rooms:
		if _is_room_data(room):
			result.append(room.room_id)
	result.sort()
	return result


func get_adjacent_room_ids(room_id: String) -> Array[String]:
	var unique: Dictionary[String, bool] = {}
	var room: Resource = get_room(room_id)
	if room != null:
		for adjacent_id: String in room.adjacent_room_ids:
			if not adjacent_id.is_empty() and adjacent_id != room_id:
				unique[adjacent_id] = true
	for connection: Resource in connections:
		if not _is_room_connection_data(connection):
			continue
		if connection.from_room_id == room_id and not connection.to_room_id.is_empty():
			unique[connection.to_room_id] = true
		if connection.to_room_id == room_id and not connection.from_room_id.is_empty():
			unique[connection.from_room_id] = true
	var result: Array[String] = []
	result.assign(unique.keys())
	result.sort()
	return result


func get_chunk_at_world_position(
	world_position: Vector2,
	chunk_size_pixels: Vector2i = Vector2i(320, 180)
) -> Vector2i:
	return Vector2i(
		floori(world_position.x / float(chunk_size_pixels.x)),
		floori(world_position.y / float(chunk_size_pixels.y))
	)


func get_room_id_at_world_position(
	world_position: Vector2,
	preferred_room_id: String = "",
	chunk_size_pixels: Vector2i = Vector2i(320, 180)
) -> String:
	var chunk := get_chunk_at_world_position(world_position, chunk_size_pixels)
	var preferred: Resource = get_room(preferred_room_id)
	if preferred != null and preferred.contains_chunk(chunk):
		return preferred_room_id
	for room_id: String in get_room_ids():
		var room: Resource = get_room(room_id)
		if room != null and room.contains_chunk(chunk):
			return room_id
	return ""


static func _is_room_data(resource: Resource) -> bool:
	return resource != null and resource.get_script() == ROOM_DATA_SCRIPT


static func _is_room_connection_data(resource: Resource) -> bool:
	return resource != null and resource.get_script() == ROOM_CONNECTION_DATA_SCRIPT
