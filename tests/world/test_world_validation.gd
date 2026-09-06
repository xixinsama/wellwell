extends Node

const ROOM_DATA: Script = preload("res://scripts/world/room_data.gd")
const WORLD_DATA: Script = preload("res://scripts/world/world_data.gd")
const ROOM_CONNECTION_DATA: Script = preload("res://scripts/world/room_connection_data.gd")
const ROOM_PLACEMENT_DATA: Script = preload("res://scripts/world/world_room_placement_data.gd")
const WORLD_VALIDATION: Script = preload("res://scripts/world/world_validation.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_valid_world_has_no_errors(failures)
	_assert_validation_reports_room_authoring_errors(failures)
	_assert_validation_reports_bad_adjacency_and_connections(failures)
	_assert_validation_reports_invalid_resource_entries(failures)
	_assert_validation_rejects_wrong_world_resource(failures)
	_assert_validation_report_contract(failures)
	_assert_world_without_connections_skips_reachability(failures)
	_assert_validation_reports_invalid_placement_membership(failures)
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


func _assert_validation_reports_invalid_resource_entries(failures: Array[String]) -> void:
	var room_a: Resource = _make_room("room_a")
	var world: Resource = _make_world([null, Resource.new(), room_a], [null, Resource.new()])
	world.world_id = ""
	world.start_room_id = "room_a"

	var errors: Array[String] = WORLD_VALIDATION.validate_world(world)

	_assert_has_error(errors, "world_id is empty", failures)
	_assert_has_error(errors, "world has null room", failures)
	_assert_has_error(errors, "world has non-RoomData room resource", failures)
	_assert_has_error(errors, "world has null connection", failures)
	_assert_has_error(errors, "world has non-RoomConnectionData connection resource", failures)


func _assert_validation_rejects_wrong_world_resource(failures: Array[String]) -> void:
	var errors: Array[String] = WORLD_VALIDATION.validate_world(Resource.new())
	_assert_has_error(errors, "world is not WorldData", failures)


func _assert_validation_report_contract(failures: Array[String]) -> void:
	if not WORLD_VALIDATION.has_method("validate_world_report"):
		failures.append("missing production API: WorldValidation.validate_world_report")
		return
	var room_a: Resource = _make_room("room_a")
	var room_b: Resource = _make_room("room_b")
	room_b.room_origin_chunk = Vector2i.ZERO
	var world: Resource = _make_world([room_a, room_b], [])
	world.start_room_id = "room_a"
	world.start_spawn_id = "spawn_main"
	var report: Dictionary = WORLD_VALIDATION.call("validate_world_report", world)

	if not report.has_all(["ok", "errors", "warnings"]):
		failures.append("world validation report must expose ok, errors, and warnings keys: %s" % str(report))
		return
	if report.get("ok", false) != true:
		failures.append("overlapping rooms should keep report ok=true: %s" % str(report))
	var report_errors: Array = report.get("errors", [])
	var report_warnings: Array = report.get("warnings", [])
	_assert_has_error(report_warnings, "overlapping rooms: room_a, room_b", failures)
	var invalid_world: Resource = _make_world([
		_make_room("duplicate"),
		_make_room("duplicate"),
		_make_room("duplicate"),
	], [])
	var invalid_report: Dictionary = WORLD_VALIDATION.call("validate_world_report", invalid_world)
	var invalid_errors: Array = invalid_report.get("errors", [])
	if invalid_errors.count("duplicate room_id: duplicate") != 1:
		failures.append("world validation report errors must not contain duplicates: %s" % str(invalid_errors))
	var sorted_errors: Array = invalid_errors.duplicate()
	sorted_errors.sort()
	if invalid_errors != sorted_errors:
		failures.append("world validation report errors must be sorted: %s" % str(invalid_errors))
	var sorted_warnings: Array = report_warnings.duplicate()
	sorted_warnings.sort()
	if report_warnings != sorted_warnings:
		failures.append("world validation report warnings must be sorted: %s" % str(report_warnings))


func _assert_world_without_connections_skips_reachability(failures: Array[String]) -> void:
	var world: Resource = _make_world([_make_room("room_a"), _make_room("room_b")], [])
	world.start_room_id = "room_a"
	world.start_spawn_id = "spawn_main"
	var report: Dictionary = WORLD_VALIDATION.call("validate_world_report", world)
	for warning: String in report.get("warnings", []):
		if warning.contains("is unreachable from start room"):
			failures.append("connection-free world produced a reachability warning: %s" % warning)


func _assert_validation_reports_invalid_placement_membership(failures: Array[String]) -> void:
	var world: Resource = WORLD_DATA.new()
	world.world_id = "world_01"
	world.rooms.assign([_make_room("room_a")])
	world.start_room_id = "room_a"
	world.start_spawn_id = "spawn_main"
	var missing_report: Dictionary = WORLD_VALIDATION.call("validate_world_report", world)
	_assert_has_error(missing_report.get("errors", []), "world has no placement for room: room_a", failures)

	var first: Resource = ROOM_PLACEMENT_DATA.new()
	first.room_id = "room_a"
	var duplicate: Resource = ROOM_PLACEMENT_DATA.new()
	duplicate.room_id = "room_a"
	var unknown: Resource = ROOM_PLACEMENT_DATA.new()
	unknown.room_id = "missing"
	world.placements.assign([first, duplicate, unknown])
	var invalid_report: Dictionary = WORLD_VALIDATION.call("validate_world_report", world)
	_assert_has_error(invalid_report.get("errors", []), "world contains duplicate placement for room room_a", failures)
	_assert_has_error(invalid_report.get("errors", []), "world placement references unknown room missing", failures)


func _make_world(rooms: Array, connections: Array) -> Resource:
	var world: Resource = WORLD_DATA.new()
	world.world_id = "world_01"
	world.rooms.assign(rooms)
	world.connections.assign(connections)
	world.normalize_room_placements()
	return world


func _make_room(room_id: String) -> Resource:
	var room: Resource = ROOM_DATA.new()
	room.room_id = room_id
	room.scene_path = "res://scenes/rooms/%s.tscn" % room_id
	room.source_scene_path = "res://scenes/levels/%s.tscn" % room_id
	room.terrain_scene_path = "res://scenes/generated/%s_terrain.tscn" % room_id
	room.entrance_ids = PackedStringArray(["exit_right"])
	room.spawn_ids = PackedStringArray(["spawn_main", "spawn_left"])
	room.entity_ids = PackedStringArray(["entity_main"])
	room.room_size_chunks = Vector2i.ONE
	return room


func _make_connection(from_room_id: String, from_entrance_id: String, to_room_id: String, to_spawn_id: String) -> Resource:
	var connection: Resource = ROOM_CONNECTION_DATA.new()
	connection.from_room_id = from_room_id
	connection.from_entrance_id = from_entrance_id
	connection.to_room_id = to_room_id
	connection.to_spawn_id = to_spawn_id
	return connection


func _assert_has_error(errors: Array, expected: String, failures: Array[String], required: bool = true) -> void:
	if not errors.has(expected):
		if required:
			failures.append("missing validation error: %s in %s" % [expected, str(errors)])
