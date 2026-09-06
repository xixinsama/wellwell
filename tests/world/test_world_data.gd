extends Node

const ROOM_DATA: Script = preload("res://scripts/world/room_data.gd")
const WORLD_DATA: Script = preload("res://scripts/world/world_data.gd")
const ROOM_CONNECTION_DATA: Script = preload("res://scripts/world/room_connection_data.gd")
const PLACEMENT_SCRIPT_PATH := "res://scripts/world/world_room_placement_data.gd"


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
	_assert_world_placement_overrides_legacy_origin(failures)
	_assert_world_normalizes_missing_placements(failures)
	_assert_world_rejects_invalid_placements_without_deleting_them(failures)
	_assert_shared_room_can_have_independent_world_placements(failures)
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


func _assert_world_placement_overrides_legacy_origin(failures: Array[String]) -> void:
	var world: Resource = WORLD_DATA.new()
	var room: Resource = _make_room("room_a")
	room.room_origin_chunk = Vector2i(7, 3)
	world.rooms.assign([room])
	if not _has_placement_api(world, failures):
		return
	var placement: Resource = _make_placement("room_a", Vector2i(-2, 4), failures)
	if placement == null:
		return
	var placement_resources: Array[Resource] = [placement]
	world.set("placements", placement_resources)
	if world.call("get_room_origin_chunk", "room_a") != Vector2i(-2, 4):
		failures.append("world placement did not override the legacy room origin")
	if world.call("get_room_chunk_rect", "room_a") != Rect2i(-2, 4, 1, 1):
		failures.append("world chunk rect did not use the authoritative placement")


func _assert_world_normalizes_missing_placements(failures: Array[String]) -> void:
	var world: Resource = WORLD_DATA.new()
	var room_a: Resource = _make_room("room_a")
	room_a.room_origin_chunk = Vector2i(3, 5)
	var room_b: Resource = _make_room("room_b")
	room_b.room_origin_chunk = Vector2i(-1, 2)
	world.rooms.assign([room_b, room_a])
	if not _has_placement_api(world, failures):
		return
	var result: Dictionary = world.call("normalize_room_placements")
	if not result.get("ok", false):
		failures.append("valid legacy rooms could not be normalized: %s" % str(result))
		return
	if result.get("created_count", 0) != 2:
		failures.append("normalization did not create one placement per missing room")
	if world.call("get_room_origin_chunk", "room_a") != Vector2i(3, 5):
		failures.append("normalization did not migrate room_a's legacy origin")
	if world.call("get_room_origin_chunk", "room_b") != Vector2i(-1, 2):
		failures.append("normalization did not migrate room_b's legacy origin")
	var placements: Array = world.get("placements")
	if placements.size() != 2 or placements[0].room_id != "room_a" or placements[1].room_id != "room_b":
		failures.append("normalized placements were not complete and sorted")


func _assert_world_rejects_invalid_placements_without_deleting_them(failures: Array[String]) -> void:
	var world: Resource = WORLD_DATA.new()
	world.rooms.assign([_make_room("room_a")])
	if not _has_placement_api(world, failures):
		return
	var first: Resource = _make_placement("room_a", Vector2i.ZERO, failures)
	var duplicate: Resource = _make_placement("room_a", Vector2i.ONE, failures)
	var unknown: Resource = _make_placement("missing", Vector2i(2, 2), failures)
	var empty: Resource = _make_placement("", Vector2i(3, 3), failures)
	if first == null or duplicate == null or unknown == null or empty == null:
		return
	var placement_resources: Array[Resource] = [first, duplicate, unknown, empty]
	world.set("placements", placement_resources)
	var result: Dictionary = world.call("normalize_room_placements")
	if result.get("ok", true):
		failures.append("normalization accepted duplicate, unknown, or empty placement ids")
	if (world.get("placements") as Array).size() != 4:
		failures.append("normalization silently deleted invalid placement resources")


func _assert_shared_room_can_have_independent_world_placements(failures: Array[String]) -> void:
	var shared_room: Resource = _make_room("shared")
	shared_room.room_origin_chunk = Vector2i(7, 3)
	var world_a: Resource = WORLD_DATA.new()
	var world_b: Resource = WORLD_DATA.new()
	world_a.rooms.assign([shared_room])
	world_b.rooms.assign([shared_room])
	if not _has_placement_api(world_a, failures) or not _has_placement_api(world_b, failures):
		return
	world_a.call("normalize_room_placements")
	world_b.call("normalize_room_placements")
	world_a.call("set_room_origin_chunk", "shared", Vector2i(-1, -1))
	world_b.call("set_room_origin_chunk", "shared", Vector2i(4, 2))
	if world_a.call("get_room_origin_chunk", "shared") != Vector2i(-1, -1):
		failures.append("world A placement was not authoritative")
	if world_b.call("get_room_origin_chunk", "shared") != Vector2i(4, 2):
		failures.append("world B placement was not independent")
	if shared_room.room_origin_chunk != Vector2i(7, 3):
		failures.append("setting a world placement mutated shared RoomData")


func _has_placement_api(world: Resource, failures: Array[String]) -> bool:
	for method_name: String in [
		"get_room_origin_chunk",
		"set_room_origin_chunk",
		"get_room_chunk_rect",
		"normalize_room_placements",
	]:
		if not world.has_method(method_name):
			failures.append("world data did not expose %s" % method_name)
			return false
	if not "placements" in world:
		failures.append("world data did not expose embedded placements")
		return false
	return true


func _make_placement(room_id: String, origin: Vector2i, failures: Array[String]) -> Resource:
	if not ResourceLoader.exists(PLACEMENT_SCRIPT_PATH):
		failures.append("world room placement resource script did not exist")
		return null
	var script := load(PLACEMENT_SCRIPT_PATH) as Script
	if script == null or not script.can_instantiate():
		failures.append("world room placement resource script could not be instantiated")
		return null
	var placement := script.new() as Resource
	placement.set("room_id", room_id)
	placement.set("origin_chunk", origin)
	return placement


func _make_room(room_id: String) -> Resource:
	var room: Resource = ROOM_DATA.new()
	room.room_id = room_id
	room.scene_path = "res://scenes/rooms/%s.tscn" % room_id
	return room
