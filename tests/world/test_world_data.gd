extends Node

const ROOM_DATA: Script = preload("res://scripts/world/room_data.gd")
const WORLD_DATA: Script = preload("res://scripts/world/world_data.gd")
const ROOM_CONNECTION_DATA: Script = preload("res://scripts/world/room_connection_data.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_room_bounds_convert_between_chunks_pixels_and_cells(failures)
	_assert_room_chunk_ids_are_stable_and_sorted(failures)
	_assert_contains_chunk_uses_room_rect(failures)
	_assert_world_indexes_room_ids_by_chunk_rect(failures)
	_assert_world_returns_spatial_and_connected_residency(failures)
	_assert_world_returns_unique_connection_by_source_endpoint(failures)
	_assert_world_indexes_rooms_by_id(failures)
	_assert_world_combines_room_and_connection_adjacency(failures)
	_assert_world_resolves_positions_to_chunks_and_rooms(failures)
	_assert_world_ignores_invalid_resources(failures)
	_assert_room_data_keeps_legacy_and_world_owned_fields(failures)
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


func _assert_world_indexes_room_ids_by_chunk_rect(failures: Array[String]) -> void:
	var world: Resource = WORLD_DATA.new()
	var room_b: Resource = _make_room("room_b")
	room_b.room_origin_chunk = Vector2i(0, 0)
	room_b.room_size_chunks = Vector2i(2, 2)
	var room_a: Resource = _make_room("room_a")
	room_a.room_origin_chunk = Vector2i(1, 1)
	var room_c: Resource = _make_room("room_c")
	room_c.room_origin_chunk = Vector2i(3, 3)
	world.rooms.assign([room_c, room_b, room_a, room_b])

	if not world.has_method("get_room_ids_at_chunk"):
		failures.append("world data did not expose get_room_ids_at_chunk")
		return
	var overlapping_ids: Array[String] = world.get_room_ids_at_chunk(Vector2i(1, 1))
	if overlapping_ids != ["room_a", "room_b"]:
		failures.append("room ids at an overlapping chunk were not unique and sorted: %s" % str(overlapping_ids))
	var empty_ids: Array[String] = world.get_room_ids_at_chunk(Vector2i(2, 2))
	if empty_ids != []:
		failures.append("room ids outside all chunk rects were not empty: %s" % str(empty_ids))


func _assert_world_returns_spatial_and_connected_residency(failures: Array[String]) -> void:
	var world: Resource = WORLD_DATA.new()
	var nearby_ids := ["center", "right", "left", "up", "down", "diagonal"]
	var origins := {
		"center": Vector2i(0, 0),
		"right": Vector2i(1, 0),
		"left": Vector2i(-1, 0),
		"up": Vector2i(0, -1),
		"down": Vector2i(0, 1),
		"diagonal": Vector2i(1, 1),
	}
	var rooms: Array[Resource] = []
	for room_id: String in nearby_ids:
		var room: Resource = _make_room(room_id)
		room.room_origin_chunk = origins[room_id]
		rooms.append(room)
	var current_room: Resource = _make_room("current_room")
	current_room.room_origin_chunk = Vector2i(20, 20)
	var remote_room: Resource = _make_room("remote_room")
	remote_room.room_origin_chunk = Vector2i(30, 30)
	var incoming_room: Resource = _make_room("incoming_room")
	incoming_room.room_origin_chunk = Vector2i(40, 40)
	rooms.append(current_room)
	rooms.append(remote_room)
	rooms.append(incoming_room)
	world.rooms.assign(rooms)
	var connection: Resource = ROOM_CONNECTION_DATA.new()
	connection.from_room_id = "current_room"
	connection.from_entrance_id = "exit_remote"
	connection.to_room_id = "remote_room"
	connection.to_spawn_id = "spawn_main"
	var incoming_connection: Resource = ROOM_CONNECTION_DATA.new()
	incoming_connection.from_room_id = "incoming_room"
	incoming_connection.from_entrance_id = "exit_current"
	incoming_connection.to_room_id = "current_room"
	incoming_connection.to_spawn_id = "spawn_main"
	world.connections.assign([connection, incoming_connection])

	if not world.has_method("get_resident_room_ids"):
		failures.append("world data did not expose get_resident_room_ids")
		return
	var resident_ids: Array[String] = world.get_resident_room_ids(Vector2i.ZERO, "current_room")
	var expected := ["center", "current_room", "down", "incoming_room", "left", "remote_room", "right", "up"]
	if resident_ids != expected:
		failures.append("resident room ids did not include current, cardinal chunks, and direct connections: %s" % str(resident_ids))
	if resident_ids.has("diagonal"):
		failures.append("diagonal chunk room was incorrectly included in residency")


func _assert_world_returns_unique_connection_by_source_endpoint(failures: Array[String]) -> void:
	var world: Resource = WORLD_DATA.new()
	var connection: Resource = ROOM_CONNECTION_DATA.new()
	connection.from_room_id = "room_a"
	connection.from_entrance_id = "exit_right"
	connection.to_room_id = "room_b"
	connection.to_spawn_id = "spawn_left"
	world.connections.assign([connection])

	if not world.has_method("get_connection"):
		failures.append("world data did not expose get_connection")
		return
	if world.get_connection("room_a", "exit_right") != connection:
		failures.append("world data did not return the matching unique connection")
	if world.get_connection("room_a", "missing") != null:
		failures.append("world data returned a connection for a missing source endpoint")
	var duplicate: Resource = connection.duplicate()
	world.connections.append(duplicate)
	if world.get_connection("room_a", "exit_right") != null:
		failures.append("world data returned an ambiguous duplicate source endpoint")


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


func _assert_world_resolves_positions_to_chunks_and_rooms(failures: Array[String]) -> void:
	var room_a: Resource = _make_room("room_a")
	room_a.room_origin_chunk = Vector2i.ZERO
	room_a.room_size_chunks = Vector2i(2, 1)
	var room_b: Resource = _make_room("room_b")
	room_b.room_origin_chunk = Vector2i(1, 0)
	var world: Resource = WORLD_DATA.new()
	world.rooms.assign([room_b, room_a])

	if not world.has_method("get_chunk_at_world_position") or not world.has_method("get_room_id_at_world_position"):
		failures.append("world data did not expose position lookup")
		return
	if world.get_chunk_at_world_position(Vector2(319.9, 179.9)) != Vector2i.ZERO:
		failures.append("world position did not resolve inside the first chunk")
	if world.get_chunk_at_world_position(Vector2(-0.1, -0.1)) != Vector2i(-1, -1):
		failures.append("negative world position did not use floor chunk coordinates")
	if world.get_room_id_at_world_position(Vector2(330.0, 20.0), "room_b") != "room_b":
		failures.append("overlapping room lookup did not preserve the preferred room")
	if world.get_room_id_at_world_position(Vector2(330.0, 20.0)) != "room_a":
		failures.append("overlapping room lookup was not deterministic")
	if world.get_room_id_at_world_position(Vector2(960.0, 20.0)) != "":
		failures.append("world position outside every room resolved to a room")


func _assert_world_ignores_invalid_resources(failures: Array[String]) -> void:
	var room_a: Resource = _make_room("room_a")
	var wrong_resource := Resource.new()
	var world: Resource = WORLD_DATA.new()
	world.rooms.assign([wrong_resource, room_a])
	world.connections.assign([wrong_resource])

	if world.get_room_ids() != ["room_a"]:
		failures.append("world did not ignore invalid room resources")
	if world.get_adjacent_room_ids("room_a") != []:
		failures.append("world did not ignore invalid connection resources")


func _assert_room_data_keeps_legacy_and_world_owned_fields(failures: Array[String]) -> void:
	var room: Resource = ROOM_DATA.new()
	room.room_id = "room_a"
	room.scene_path = "res://scenes/rooms/legacy_runtime.tscn"
	room.source_scene_path = "res://scenes/levels/room_a.tscn"
	room.terrain_scene_path = "res://scenes/rooms/generated/room_a_terrain.tscn"
	room.room_origin_chunk = Vector2i(7, -3)
	room.adjacent_room_ids = PackedStringArray(["room_b"])
	room.entrance_ids = PackedStringArray(["exit_a"])
	room.spawn_ids = PackedStringArray(["spawn_a"])
	room.entity_ids = PackedStringArray(["switch_a"])

	if room.scene_path != "res://scenes/rooms/legacy_runtime.tscn":
		failures.append("legacy scene_path was not preserved")
	if room.source_scene_path.is_empty() or room.terrain_scene_path.is_empty():
		failures.append("room provenance paths were not stored")
	if room.room_origin_chunk != Vector2i(7, -3):
		failures.append("room origin chunk was not retained")
	if room.adjacent_room_ids != PackedStringArray(["room_b"]):
		failures.append("adjacent room ids were not retained")


func _make_room(room_id: String) -> Resource:
	var room: Resource = ROOM_DATA.new()
	room.room_id = room_id
	room.scene_path = "res://scenes/rooms/%s.tscn" % room_id
	return room
