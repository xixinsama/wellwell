extends Node

const ROOM_DATA: Script = preload("res://scripts/world/room_data.gd")
const WORLD_DATA: Script = preload("res://scripts/world/world_data.gd")
const ROOM_CONNECTION_DATA: Script = preload("res://scripts/world/room_connection_data.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_room_bounds_convert_between_chunks_pixels_and_cells(failures)
	_assert_room_chunk_ids_are_stable_and_sorted(failures)
	_assert_contains_chunk_uses_room_rect(failures)
	_assert_world_indexes_rooms_by_id(failures)
	_assert_world_combines_room_and_connection_adjacency(failures)
	return failures


func _assert_room_bounds_convert_between_chunks_pixels_and_cells(failures: Array[String]) -> void:
	var room: Resource = ROOM_DATA.new()
	room.room_origin_chunk = Vector2i(2, 1)
	room.room_size_chunks = Vector2i(3, 2)

	if room.get_chunk_rect() != Rect2i(2, 1, 3, 2):
		failures.append("room chunk rect was wrong")
	if room.get_pixel_rect() != Rect2i(640, 180, 960, 360):
		failures.append("room pixel rect was wrong")
	if room.get_cell_rect() != Rect2i(80, 23, 120, 46):
		failures.append("room cell rect did not use ceiled chunk cell size")


func _assert_room_chunk_ids_are_stable_and_sorted(failures: Array[String]) -> void:
	var room: Resource = ROOM_DATA.new()
	room.room_origin_chunk = Vector2i(2, 1)
	room.room_size_chunks = Vector2i(2, 2)

	var chunk_ids: Array[String] = room.get_chunk_ids("world_01")

	if chunk_ids != [
		"world_01:chunk:2,1",
		"world_01:chunk:3,1",
		"world_01:chunk:2,2",
		"world_01:chunk:3,2",
	]:
		failures.append("room chunk ids were not stable")


func _assert_contains_chunk_uses_room_rect(failures: Array[String]) -> void:
	var room: Resource = ROOM_DATA.new()
	room.room_origin_chunk = Vector2i(-1, 3)
	room.room_size_chunks = Vector2i(2, 1)

	if not room.contains_chunk(Vector2i(-1, 3)):
		failures.append("room did not contain its first chunk")
	if not room.contains_chunk(Vector2i(0, 3)):
		failures.append("room did not contain its last chunk")
	if room.contains_chunk(Vector2i(1, 3)):
		failures.append("room contained a chunk outside its width")


func _assert_world_indexes_rooms_by_id(failures: Array[String]) -> void:
	var room_a: Resource = _make_room("room_a")
	var room_b: Resource = _make_room("room_b")
	var world: Resource = WORLD_DATA.new()
	world.world_id = "world_01"
	world.rooms.assign([room_b, room_a])

	if not world.has_room("room_a"):
		failures.append("world did not find an existing room")
	if world.has_room("missing"):
		failures.append("world found a missing room")
	if world.get_room("room_b") != room_b:
		failures.append("world returned the wrong room")
	if world.get_room_ids() != ["room_a", "room_b"]:
		failures.append("world room ids were not sorted")


func _assert_world_combines_room_and_connection_adjacency(failures: Array[String]) -> void:
	var room_a: Resource = _make_room("room_a")
	room_a.adjacent_room_ids = PackedStringArray(["room_b"])
	var room_b: Resource = _make_room("room_b")
	var room_c: Resource = _make_room("room_c")
	var connection: Resource = ROOM_CONNECTION_DATA.new()
	connection.from_room_id = "room_a"
	connection.from_entrance_id = "exit_right"
	connection.to_room_id = "room_c"
	connection.to_spawn_id = "spawn_left"
	connection.direction = ROOM_CONNECTION_DATA.Direction.RIGHT
	var reverse_connection: Resource = ROOM_CONNECTION_DATA.new()
	reverse_connection.from_room_id = "room_b"
	reverse_connection.from_entrance_id = "exit_left"
	reverse_connection.to_room_id = "room_a"
	reverse_connection.to_spawn_id = "spawn_right"
	reverse_connection.direction = ROOM_CONNECTION_DATA.Direction.LEFT
	var world: Resource = WORLD_DATA.new()
	world.rooms.assign([room_a, room_b, room_c])
	world.connections.assign([connection, reverse_connection])

	if world.get_adjacent_room_ids("room_a") != ["room_b", "room_c"]:
		failures.append("world adjacency did not combine room ids and connections")


func _make_room(room_id: String) -> Resource:
	var room: Resource = ROOM_DATA.new()
	room.room_id = room_id
	room.scene_path = "res://scenes/rooms/%s.tscn" % room_id
	return room
