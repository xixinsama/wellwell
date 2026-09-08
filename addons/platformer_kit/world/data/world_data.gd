@tool
class_name WorldData
extends Resource

const ROOM_DATA_SCRIPT: Script = preload("res://addons/platformer_kit/world/data/room_data.gd")
const ROOM_CONNECTION_DATA_SCRIPT: Script = preload("res://addons/platformer_kit/world/data/room_connection_data.gd")
const ROOM_PLACEMENT_DATA_SCRIPT: Script = preload("res://addons/platformer_kit/world/data/world_room_placement_data.gd")
const ROOM_GRID: Script = preload("res://addons/platformer_kit/world/data/room_grid.gd")
const REGION_DATA_SCRIPT: Script = preload("res://addons/platformer_kit/world/region/region_data.gd")
const WORLD_GRAPH_SCRIPT: Script = preload("res://addons/platformer_kit/world/graph/world_graph.gd")
const DEFAULT_CHUNK_SIZE_PIXELS := Vector2i(320, 180)
const DEFAULT_CELL_SIZE := Vector2i(8, 8)

@export var world_id := ""
@export var start_room_id := ""
@export var start_spawn_id := ""
@export var rooms: Array[Resource] = []
@export var placements: Array[Resource] = []
@export var connections: Array[Resource] = []
@export var regions: Array[Resource] = []
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


func get_region(region_id: StringName) -> Resource:
	for region: Resource in regions:
		if region != null and region.get_script() == REGION_DATA_SCRIPT and region.region_id == region_id:
			return region
	return null


func build_graph() -> WorldGraph:
	var graph := WORLD_GRAPH_SCRIPT.new() as WorldGraph
	for room_id: String in get_room_ids():
		graph.add_room(StringName(room_id))
	for connection: Resource in connections:
		if not _is_room_connection_data(connection):
			continue
		graph.connect_rooms(
			StringName(connection.from_room_id),
			StringName(connection.to_room_id),
			false,
			{
				"from_entrance_id": connection.from_entrance_id,
				"to_spawn_id": connection.to_spawn_id,
				"direction": connection.direction,
			}
		)
	return graph


func get_room_placement(room_id: String) -> Resource:
	var found: Resource
	for placement: Resource in placements:
		if not _is_room_placement_data(placement) or placement.room_id != room_id:
			continue
		if found != null:
			return null
		found = placement
	return found


func get_room_origin_chunk(room_id: String) -> Vector2i:
	var placement := get_room_placement(room_id)
	if placement != null:
		return placement.origin_chunk
	return Vector2i.ZERO


func set_room_origin_chunk(room_id: String, origin: Vector2i) -> bool:
	if not has_room(room_id):
		return false
	var placement := get_room_placement(room_id)
	if placement == null:
		placement = ROOM_PLACEMENT_DATA_SCRIPT.new()
		placement.room_id = room_id
		placements.append(placement)
	placement.origin_chunk = origin
	placements.sort_custom(_placement_resource_less)
	return true


func get_room_chunk_rect(room_id: String) -> Rect2i:
	var room := get_room(room_id)
	if room == null:
		return Rect2i()
	return Rect2i(get_room_origin_chunk(room_id), room.room_size_chunks)


func get_room_pixel_rect(
	room_id: String,
	chunk_size_pixels: Vector2i = DEFAULT_CHUNK_SIZE_PIXELS
) -> Rect2i:
	var chunk_rect := get_room_chunk_rect(room_id)
	return Rect2i(chunk_rect.position * chunk_size_pixels, chunk_rect.size * chunk_size_pixels)


func get_room_cell_rect(
	room_id: String,
	cell_size: Vector2i = DEFAULT_CELL_SIZE,
	chunk_size_pixels: Vector2i = DEFAULT_CHUNK_SIZE_PIXELS
) -> Rect2i:
	var room := get_room(room_id)
	if room == null:
		return Rect2i()
	return ROOM_GRID.get_room_cell_rect(
		get_room_origin_chunk(room_id), room.room_size_chunks, cell_size, chunk_size_pixels
	)


func get_connection(from_room_id: String, from_entrance_id: String) -> RoomConnectionData:
	var found: RoomConnectionData
	for connection: Resource in connections:
		if not _is_room_connection_data(connection):
			continue
		if connection.from_room_id == from_room_id and connection.from_entrance_id == from_entrance_id:
			if found != null:
				return null
			found = connection as RoomConnectionData
	return found


func get_room_ids_at_chunk(chunk: Vector2i) -> Array[String]:
	var unique: Dictionary[String, bool] = {}
	for room: Resource in rooms:
		if _is_room_data(room) and get_room_chunk_rect(room.room_id).has_point(chunk):
			unique[room.room_id] = true
	var result: Array[String] = []
	result.assign(unique.keys())
	result.sort()
	return result


func get_resident_room_ids(player_chunk: Vector2i, current_room_id: String) -> Array[String]:
	var unique: Dictionary[String, bool] = {}
	for offset: Vector2i in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		for room_id: String in get_room_ids_at_chunk(player_chunk + offset):
			unique[room_id] = true
	if has_room(current_room_id):
		unique[current_room_id] = true
	for connection: Resource in connections:
		if not _is_room_connection_data(connection):
			continue
		if connection.from_room_id == current_room_id and has_room(connection.to_room_id):
			unique[connection.to_room_id] = true
		if connection.to_room_id == current_room_id and has_room(connection.from_room_id):
			unique[connection.from_room_id] = true
	var result: Array[String] = []
	result.assign(unique.keys())
	result.sort()
	return result


func sort_for_serialization() -> void:
	rooms.sort_custom(_room_resource_less)
	placements.sort_custom(_placement_resource_less)
	connections.sort_custom(_connection_resource_less)


func get_adjacent_room_ids(room_id: String) -> Array[String]:
	var unique: Dictionary[String, bool] = {}
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
	if preferred != null and get_room_chunk_rect(preferred_room_id).has_point(chunk):
		return preferred_room_id
	for room_id: String in get_room_ids():
		if get_room_chunk_rect(room_id).has_point(chunk):
			return room_id
	return ""


static func _is_room_data(resource: Resource) -> bool:
	return resource != null and resource.get_script() == ROOM_DATA_SCRIPT


static func _is_room_connection_data(resource: Resource) -> bool:
	return resource != null and resource.get_script() == ROOM_CONNECTION_DATA_SCRIPT


static func _is_room_placement_data(resource: Resource) -> bool:
	return resource != null and resource.get_script() == ROOM_PLACEMENT_DATA_SCRIPT


static func _room_resource_less(left: Resource, right: Resource) -> bool:
	if not _is_room_data(left):
		return _is_room_data(right)
	if not _is_room_data(right):
		return false
	return left.room_id < right.room_id


static func _placement_resource_less(left: Resource, right: Resource) -> bool:
	if not _is_room_placement_data(left):
		return _is_room_placement_data(right)
	if not _is_room_placement_data(right):
		return false
	return left.room_id < right.room_id


static func _connection_resource_less(left: Resource, right: Resource) -> bool:
	if not _is_room_connection_data(left):
		return _is_room_connection_data(right)
	if not _is_room_connection_data(right):
		return false
	var left_key := "%s\u001f%s\u001f%s\u001f%s\u001f%d" % [
		left.from_room_id,
		left.from_entrance_id,
		left.to_room_id,
		left.to_spawn_id,
		left.direction,
	]
	var right_key := "%s\u001f%s\u001f%s\u001f%s\u001f%d" % [
		right.from_room_id,
		right.from_entrance_id,
		right.to_room_id,
		right.to_spawn_id,
		right.direction,
	]
	return left_key < right_key
