extends Node

const ROOM_DATA: Script = preload("res://addons/platformer_kit/world/data/room_data.gd")
const WORLD_DATA: Script = preload("res://addons/platformer_kit/world/data/world_data.gd")
const ROOM_CONNECTION_DATA: Script = preload("res://addons/platformer_kit/world/data/room_connection_data.gd")
const ROOM_PLACEMENT_DATA: Script = preload("res://addons/platformer_kit/world/data/world_room_placement_data.gd")
const WORLD_VALIDATION: Script = preload("res://addons/platformer_kit/world/data/world_validation.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_valid_world_has_no_errors(failures)
	_assert_missing_and_duplicate_placements_are_errors(failures)
	_assert_invalid_room_and_connection_data_are_errors(failures)
	_assert_overlap_and_reachability_are_warnings(failures)
	return failures


func _assert_valid_world_has_no_errors(failures: Array[String]) -> void:
	var world := _make_world([_make_room("room_a"), _make_room("room_b")])
	world.start_room_id = "room_a"
	world.start_spawn_id = "start"
	world.connections.assign([_make_connection("room_a", "exit", "room_b", "start")])
	var report: Dictionary = WORLD_VALIDATION.validate_world_report(world)
	if not report.ok:
		failures.append("valid world returned errors: %s" % str(report.errors))


func _assert_missing_and_duplicate_placements_are_errors(failures: Array[String]) -> void:
	var world: Resource = WORLD_DATA.new()
	world.world_id = "world_01"
	world.rooms.assign([_make_room("room_a")])
	world.start_room_id = "room_a"
	world.start_spawn_id = "start"
	_assert_contains(WORLD_VALIDATION.validate_world(world), "world has no placement for room: room_a", failures)
	var duplicate: Resource = ROOM_PLACEMENT_DATA.new()
	duplicate.room_id = "room_a"
	world.placements.assign([_make_placement("room_a", Vector2i.ZERO), duplicate, _make_placement("missing", Vector2i.ONE)])
	var errors: Array[String] = WORLD_VALIDATION.validate_world(world)
	_assert_contains(errors, "world contains duplicate placement for room room_a", failures)
	_assert_contains(errors, "world placement references unknown room missing", failures)


func _assert_invalid_room_and_connection_data_are_errors(failures: Array[String]) -> void:
	var invalid_room := _make_room("room_a")
	invalid_room.scene_path = ""
	invalid_room.room_size_chunks = Vector2i(0, 1)
	var world := _make_world([invalid_room])
	world.start_room_id = "missing"
	world.start_spawn_id = "start"
	world.connections.assign([_make_connection("room_a", "", "missing", "start")])
	var errors: Array[String] = WORLD_VALIDATION.validate_world(world)
	_assert_contains(errors, "room room_a has empty scene_path", failures)
	_assert_contains(errors, "room room_a has invalid room_size_chunks: (0, 1)", failures)
	_assert_contains(errors, "start_room_id does not reference a room: missing", failures)
	_assert_contains(errors, "connection room_a->missing has empty from_entrance_id", failures)
	_assert_contains(errors, "connection room_a->missing references unknown to_room_id", failures)


func _assert_overlap_and_reachability_are_warnings(failures: Array[String]) -> void:
	var world := _make_world([_make_room("room_a"), _make_room("room_b"), _make_room("room_c")])
	world.start_room_id = "room_a"
	world.start_spawn_id = "start"
	world.set_room_origin_chunk("room_b", Vector2i.ZERO)
	world.connections.assign([_make_connection("room_a", "exit", "room_b", "start")])
	var report: Dictionary = WORLD_VALIDATION.validate_world_report(world)
	if not report.ok:
		failures.append("overlap and unreachable room should remain warning-only: %s" % str(report.errors))
	_assert_contains(report.warnings, "overlapping rooms: room_a, room_b", failures)
	_assert_contains(report.warnings, "room room_c is unreachable from start room", failures)


func _make_world(rooms: Array[Resource]) -> Resource:
	var world: Resource = WORLD_DATA.new()
	world.world_id = "world_01"
	world.rooms.assign(rooms)
	for index: int in rooms.size():
		world.set_room_origin_chunk(rooms[index].room_id, Vector2i(index, 0))
	return world


func _make_room(room_id: String) -> Resource:
	var room: Resource = ROOM_DATA.new()
	room.room_id = room_id
	room.scene_path = "res://scenes/rooms/generated/%s/runtime.tscn" % room_id
	room.source_scene_path = "res://scenes/rooms/source/%s.tscn" % room_id
	room.terrain_scene_path = "res://scenes/rooms/generated/%s/terrain.tscn" % room_id
	room.entrance_ids = PackedStringArray(["exit"])
	room.spawn_ids = PackedStringArray(["start"])
	room.room_size_chunks = Vector2i.ONE
	return room


func _make_placement(room_id: String, origin: Vector2i) -> Resource:
	var placement: Resource = ROOM_PLACEMENT_DATA.new()
	placement.room_id = room_id
	placement.origin_chunk = origin
	return placement


func _make_connection(from_room_id: String, entrance: String, to_room_id: String, spawn: String) -> Resource:
	var connection: Resource = ROOM_CONNECTION_DATA.new()
	connection.from_room_id = from_room_id
	connection.from_entrance_id = entrance
	connection.to_room_id = to_room_id
	connection.to_spawn_id = spawn
	return connection


func _assert_contains(values: Array, expected: String, failures: Array[String]) -> void:
	if not values.has(expected):
		failures.append("missing validation result %s in %s" % [expected, str(values)])
