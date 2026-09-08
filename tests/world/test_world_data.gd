extends Node

const ROOM_DATA: Script = preload("res://addons/platformer_kit/world/data/room_data.gd")
const WORLD_DATA: Script = preload("res://addons/platformer_kit/world/data/world_data.gd")
const ROOM_CONNECTION_DATA: Script = preload("res://addons/platformer_kit/world/data/room_connection_data.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_world_owns_room_placements(failures)
	_assert_chunk_and_cell_bounds_use_world_placement(failures)
	_assert_spatial_and_connection_residency(failures)
	_assert_connection_lookup_and_adjacency(failures)
	_assert_position_lookup_is_deterministic(failures)
	_assert_shared_room_has_independent_world_placements(failures)
	return failures


func _assert_world_owns_room_placements(failures: Array[String]) -> void:
	var world := _make_world([
		_make_room("room_b", Vector2i(1, 0)),
		_make_room("room_a", Vector2i(-1, 2)),
	])
	if world.get_room_ids() != ["room_a", "room_b"]:
		failures.append("world room ids were not sorted")
	if world.get_room_origin_chunk("room_a") != Vector2i(-1, 2):
		failures.append("world did not return its room placement")
	if not world.set_room_origin_chunk("room_a", Vector2i(3, -2)):
		failures.append("world rejected a valid room placement move")
	if world.get_room_origin_chunk("room_a") != Vector2i(3, -2):
		failures.append("world did not retain a moved room placement")
	if world.set_room_origin_chunk("missing", Vector2i.ZERO):
		failures.append("world accepted a placement for an unknown room")


func _assert_chunk_and_cell_bounds_use_world_placement(failures: Array[String]) -> void:
	var room := _make_room("room_a", Vector2i(2, 1), Vector2i(3, 2))
	var world := _make_world([room])
	if world.get_room_chunk_rect("room_a") != Rect2i(2, 1, 3, 2):
		failures.append("world chunk bounds were wrong")
	if world.get_room_pixel_rect("room_a") != Rect2i(640, 180, 960, 360):
		failures.append("world pixel bounds were wrong")
	if world.get_room_cell_rect("room_a") != Rect2i(80, 23, 120, 45):
		failures.append("world cell bounds did not use exact chunk cell dimensions")


func _assert_spatial_and_connection_residency(failures: Array[String]) -> void:
	var world := _make_world([
		_make_room("center", Vector2i.ZERO),
		_make_room("right", Vector2i.RIGHT),
		_make_room("left", Vector2i.LEFT),
		_make_room("up", Vector2i.UP),
		_make_room("down", Vector2i.DOWN),
		_make_room("diagonal", Vector2i(1, 1)),
		_make_room("current", Vector2i(20, 20)),
		_make_room("remote", Vector2i(30, 30)),
	])
	world.connections.assign([_make_connection("current", "exit", "remote", "entry")])
	var resident_ids: Array[String] = world.get_resident_room_ids(Vector2i.ZERO, "current")
	var expected := ["center", "current", "down", "left", "remote", "right", "up"]
	if resident_ids != expected:
		failures.append("residency did not include cardinal rooms and connections: %s" % str(resident_ids))
	if world.get_room_ids_at_chunk(Vector2i.ZERO) != ["center"]:
		failures.append("world did not index rooms by placed chunk")


func _assert_connection_lookup_and_adjacency(failures: Array[String]) -> void:
	var world := _make_world([_make_room("room_a"), _make_room("room_b"), _make_room("room_c")])
	var first := _make_connection("room_a", "exit", "room_b", "entry")
	var second := _make_connection("room_c", "return", "room_a", "entry")
	world.connections.assign([first, second])
	if world.get_connection("room_a", "exit") != first:
		failures.append("world did not find a unique connection endpoint")
	if world.get_adjacent_room_ids("room_a") != ["room_b", "room_c"]:
		failures.append("world adjacency was not derived from connections")
	world.connections.append(first.duplicate())
	if world.get_connection("room_a", "exit") != null:
		failures.append("world accepted an ambiguous connection endpoint")


func _assert_position_lookup_is_deterministic(failures: Array[String]) -> void:
	var world := _make_world([
		_make_room("room_a", Vector2i.ZERO, Vector2i(2, 1)),
		_make_room("room_b", Vector2i(1, 0)),
	])
	if world.get_chunk_at_world_position(Vector2(-0.1, -0.1)) != Vector2i(-1, -1):
		failures.append("negative world coordinates did not floor to a chunk")
	if world.get_room_id_at_world_position(Vector2(330, 20)) != "room_a":
		failures.append("overlapping room lookup was not deterministic")
	if world.get_room_id_at_world_position(Vector2(330, 20), "room_b") != "room_b":
		failures.append("preferred room lookup was ignored")


func _assert_shared_room_has_independent_world_placements(failures: Array[String]) -> void:
	var shared := _make_room("shared")
	var world_a := _make_world([shared])
	var world_b := _make_world([shared])
	world_a.set_room_origin_chunk("shared", Vector2i(-1, -1))
	world_b.set_room_origin_chunk("shared", Vector2i(4, 2))
	if world_a.get_room_origin_chunk("shared") != Vector2i(-1, -1):
		failures.append("first world placement was not retained")
	if world_b.get_room_origin_chunk("shared") != Vector2i(4, 2):
		failures.append("second world placement was not independent")


func _make_world(rooms: Array[Resource]) -> Resource:
	var world: Resource = WORLD_DATA.new()
	world.world_id = "world_01"
	world.rooms.assign(rooms)
	for room: Resource in rooms:
		world.set_room_origin_chunk(room.room_id, room.get_meta("test_origin", Vector2i.ZERO))
	return world


func _make_room(room_id: String, origin: Vector2i = Vector2i.ZERO, size: Vector2i = Vector2i.ONE) -> Resource:
	var room: Resource = ROOM_DATA.new()
	room.room_id = room_id
	room.scene_path = "res://scenes/rooms/generated/%s/runtime.tscn" % room_id
	room.room_size_chunks = size
	room.set_meta("test_origin", origin)
	return room


func _make_connection(from_room_id: String, entrance_id: String, to_room_id: String, spawn_id: String) -> Resource:
	var connection: Resource = ROOM_CONNECTION_DATA.new()
	connection.from_room_id = from_room_id
	connection.from_entrance_id = entrance_id
	connection.to_room_id = to_room_id
	connection.to_spawn_id = spawn_id
	return connection
