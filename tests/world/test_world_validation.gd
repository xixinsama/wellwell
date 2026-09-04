extends Node

const ROOM_DATA: Script = preload("res://scripts/world/room_data.gd")
const WORLD_DATA: Script = preload("res://scripts/world/world_data.gd")
const ROOM_CONNECTION_DATA: Script = preload("res://scripts/world/room_connection_data.gd")
const WORLD_VALIDATION: Script = preload("res://scripts/world/world_validation.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_valid_world_has_no_errors(failures)
	_assert_validation_reports_room_authoring_errors(failures)
	_assert_validation_reports_bad_adjacency_and_connections(failures)
	return failures


func _assert_valid_world_has_no_errors(failures: Array[String]) -> void:
	var room_a: Resource = _make_room("room_a")
	room_a.adjacent_room_ids = PackedStringArray(["room_b"])
	var room_b: Resource = _make_room("room_b")
	var connection: Resource = _make_connection("room_a", "exit_right", "room_b", "spawn_left")
	var world: Resource = _make_world([room_a, room_b], [connection])
	world.start_room_id = "room_a"
	world.start_spawn_id = "spawn_main"

	var errors: Array[String] = WORLD_VALIDATION.validate_world(world)

	if not errors.is_empty():
		failures.append("valid world returned validation errors: %s" % str(errors))


func _assert_validation_reports_room_authoring_errors(failures: Array[String]) -> void:
	var room_a: Resource = _make_room("room_a")
	var duplicate: Resource = _make_room("room_a")
	var missing_path: Resource = _make_room("missing_path")
	missing_path.scene_path = ""
	var invalid_size: Resource = _make_room("invalid_size")
	invalid_size.room_size_chunks = Vector2i(0, 1)
	var world: Resource = _make_world([room_a, duplicate, missing_path, invalid_size], [])
	world.start_room_id = "unknown_start"

	var errors: Array[String] = WORLD_VALIDATION.validate_world(world)

	_assert_has_error(errors, "duplicate room_id: room_a", failures)
	_assert_has_error(errors, "room missing_path has empty scene_path", failures)
	_assert_has_error(errors, "room invalid_size has invalid room_size_chunks: (0, 1)", failures)
	_assert_has_error(errors, "start_room_id does not reference a room: unknown_start", failures)


func _assert_validation_reports_bad_adjacency_and_connections(failures: Array[String]) -> void:
	var room_a: Resource = _make_room("room_a")
	room_a.adjacent_room_ids = PackedStringArray(["room_b", "room_a"])
	var world: Resource = _make_world([room_a], [
		_make_connection("room_a", "", "missing_room", "spawn_left"),
	])
	world.start_room_id = "room_a"

	var errors: Array[String] = WORLD_VALIDATION.validate_world(world)

	_assert_has_error(errors, "room room_a has unknown adjacent_room_id: room_b", failures)
	_assert_has_error(errors, "room room_a cannot list itself as adjacent", failures)
	_assert_has_error(errors, "connection room_a->missing_room has empty from_entrance_id", failures)
	_assert_has_error(errors, "connection room_a->missing_room references unknown to_room_id", failures)


func _make_world(rooms: Array, connections: Array) -> Resource:
	var world: Resource = WORLD_DATA.new()
	world.world_id = "world_01"
	world.rooms.assign(rooms)
	world.connections.assign(connections)
	return world


func _make_room(room_id: String) -> Resource:
	var room: Resource = ROOM_DATA.new()
	room.room_id = room_id
	room.scene_path = "res://scenes/rooms/%s.tscn" % room_id
	room.room_size_chunks = Vector2i.ONE
	return room


func _make_connection(from_room_id: String, from_entrance_id: String, to_room_id: String, to_spawn_id: String) -> Resource:
	var connection: Resource = ROOM_CONNECTION_DATA.new()
	connection.from_room_id = from_room_id
	connection.from_entrance_id = from_entrance_id
	connection.to_room_id = to_room_id
	connection.to_spawn_id = to_spawn_id
	return connection


func _assert_has_error(errors: Array[String], expected: String, failures: Array[String]) -> void:
	if not errors.has(expected):
		failures.append("missing validation error: %s in %s" % [expected, str(errors)])
