extends Node

const ROOM_DATA: Script = preload("res://scripts/world/room_data.gd")
const WORLD_DATA: Script = preload("res://scripts/world/world_data.gd")
const ROOM_CONNECTION_DATA: Script = preload("res://scripts/world/room_connection_data.gd")
const MODEL_PATH := "res://scripts/authoring/world_layout_model.gd"

var _missing_model_reported := false


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_add_remove_move_and_deterministic_arrays(failures)
	_assert_connection_direction_breaks_sort_ties(failures)
	_assert_duplicate_room_and_duplicate_source_endpoint_are_rejected(failures)
	_assert_remove_room_clears_referencing_connections_without_files(failures)
	_assert_overlap_is_warning_only(failures)
	_assert_start_room_and_spawn_are_required(failures)
	_assert_no_connections_skip_reachability_warnings(failures)
	_assert_directed_unreachable_rooms_are_warnings(failures)
	_assert_connection_endpoints_and_unconnected_entrances_are_validated(failures)
	_assert_room_paths_and_manifest_ids_are_validated(failures)
	_assert_restore_and_replace_support_editor_history(failures)
	return failures


func _assert_restore_and_replace_support_editor_history(failures: Array[String]) -> void:
	var model = _new_model(failures)
	if model == null:
		return
	for method_name: String in ["capture_world_state", "restore_world_state", "replace_room"]:
		if not model.has_method(method_name):
			failures.append("world layout model is missing editor history API: %s" % method_name)
			return
	var world: Resource = _make_world()
	var room_a := _make_room("room_a")
	var room_b := _make_room("room_b")
	room_a.adjacent_room_ids = PackedStringArray(["room_b"])
	world.rooms.assign([room_a, room_b])
	world.connections.assign([_make_connection("room_a", "exit", "room_b", "spawn_main")])
	world.start_room_id = "room_b"
	world.start_spawn_id = "spawn_main"
	var state: Dictionary = model.call("capture_world_state", world)
	_assert_ok(model.call("remove_room", world, "room_b"), "remove before model restore", failures)
	_assert_ok(model.call("restore_world_state", world, state), "restore complete model state", failures)
	_assert_equal(world.connections.size(), 1, "model restore returns connections", failures)
	_assert_equal(world.start_room_id, "room_b", "model restore returns start room", failures)
	_assert_true(room_a.adjacent_room_ids.has("room_b"), "model restore returns adjacency", failures)

	var replacement := _make_room("room_a")
	replacement.display_name = "Rebaked"
	replacement.spawn_ids = PackedStringArray(["new_spawn"])
	_assert_ok(model.call("move_room", world, "room_a", Vector2i(3, 4)), "move room before replace", failures)
	var state_before_move: Dictionary = model.call("capture_world_state", world)
	_assert_ok(model.call("move_room", world, "room_a", Vector2i(9, 9)), "move room after snapshot", failures)
	_assert_ok(model.call("restore_world_state", world, state_before_move), "restore placement snapshot", failures)
	_assert_ok(model.call("replace_room", world, "room_a", replacement), "replace rebaked room metadata", failures)
	var replaced: Resource = world.get_room("room_a")
	_assert_equal(replaced.display_name, "Rebaked", "replace uses rebaked metadata", failures)
	_assert_equal(world.call("get_room_origin_chunk", "room_a"), Vector2i(3, 4), "replace preserves world placement", failures)
	_assert_equal(replaced.room_origin_chunk, Vector2i.ZERO, "replace does not write world placement into RoomData", failures)
	_assert_true(replaced.adjacent_room_ids.has("room_b"), "replace preserves world adjacency", failures)


func _assert_add_remove_move_and_deterministic_arrays(failures: Array[String]) -> void:
	var model = _new_model(failures)
	if model == null:
		return
	var world: Resource = _make_world()
	var room_b: Resource = _make_room("room_b")
	room_b.room_origin_chunk = Vector2i(4, 2)
	var room_a: Resource = _make_room("room_a")

	_assert_ok(model.call("add_room", world, room_b), "add room_b", failures)
	_assert_ok(model.call("add_room", world, room_a), "add room_a", failures)
	_assert_equal(_room_ids(world), ["room_a", "room_b"], "rooms are sorted after add", failures)
	_assert_equal(world.call("get_room_origin_chunk", "room_b"), Vector2i.ZERO, "add creates a world-owned placement", failures)

	_assert_ok(model.call("move_room", world, "room_b", Vector2i(-2, 3)), "move room_b", failures)
	_assert_equal(world.call("get_room_origin_chunk", "room_b"), Vector2i(-2, 3), "move uses exact integer chunk origin", failures)
	_assert_equal(room_b.room_origin_chunk, Vector2i(4, 2), "move does not mutate RoomData legacy origin", failures)

	var connection_ba: Resource = _make_connection("room_b", "exit", "room_a", "spawn_main")
	var connection_ab: Resource = _make_connection("room_a", "exit", "room_b", "spawn_main")
	_assert_ok(model.call("connect_rooms", world, connection_ba), "connect room_b to room_a", failures)
	_assert_ok(model.call("connect_rooms", world, connection_ab), "connect room_a to room_b", failures)
	_assert_equal(_connection_keys(world), ["room_a:exit", "room_b:exit"], "connections are sorted after connect", failures)

	_assert_ok(model.call("disconnect_rooms", world, "room_a", "exit"), "disconnect room_a exit", failures)
	_assert_equal(_connection_keys(world), ["room_b:exit"], "disconnect removes the selected source endpoint", failures)


func _assert_duplicate_room_and_duplicate_source_endpoint_are_rejected(failures: Array[String]) -> void:
	var model = _new_model(failures)
	if model == null:
		return
	var world: Resource = _make_world()
	var room_a: Resource = _make_room("room_a")
	_assert_ok(model.call("add_room", world, room_a), "add initial room", failures)
	var duplicate_result: Dictionary = model.call("add_room", world, _make_room("room_a"))
	_assert_false(duplicate_result.get("ok", true), "duplicate room id is rejected", failures)
	_assert_contains(duplicate_result.get("errors", []), "duplicate room_id: room_a", "duplicate room id error", failures)

	var room_b: Resource = _make_room("room_b")
	_assert_ok(model.call("add_room", world, room_b), "add target room", failures)
	var first: Resource = _make_connection("room_a", "exit", "room_b", "spawn_main")
	var second: Resource = _make_connection("room_a", "exit", "room_b", "spawn_main")
	_assert_ok(model.call("connect_rooms", world, first), "add first connection", failures)
	var duplicate_connection: Dictionary = model.call("connect_rooms", world, second)
	_assert_false(duplicate_connection.get("ok", true), "duplicate source endpoint is rejected", failures)


func _assert_connection_direction_breaks_sort_ties(failures: Array[String]) -> void:
	var world: Resource = _make_world()
	var right: Resource = _make_connection("room_a", "exit", "room_b", "spawn_main")
	right.direction = ROOM_CONNECTION_DATA.Direction.RIGHT
	var left: Resource = _make_connection("room_a", "exit", "room_b", "spawn_main")
	left.direction = ROOM_CONNECTION_DATA.Direction.LEFT
	world.connections.assign([right, left])
	world.sort_for_serialization()
	var directions: Array[int] = []
	for connection: Resource in world.connections:
		directions.append(connection.direction)
	_assert_equal(
		directions,
		[ROOM_CONNECTION_DATA.Direction.LEFT, ROOM_CONNECTION_DATA.Direction.RIGHT],
		"connection direction breaks otherwise identical sort keys",
		failures
	)


func _assert_remove_room_clears_referencing_connections_without_files(failures: Array[String]) -> void:
	var model = _new_model(failures)
	if model == null:
		return
	var world: Resource = _make_world()
	_assert_ok(model.call("add_room", world, _make_room("room_a")), "add room_a for removal", failures)
	var room_b: Resource = _make_room("room_b")
	room_b.source_scene_path = "res://scenes/game.tscn"
	_assert_ok(model.call("add_room", world, room_b), "add room_b for removal", failures)
	_assert_ok(model.call("connect_rooms", world, _make_connection("room_a", "exit", "room_b", "spawn_main")), "add outgoing connection", failures)
	_assert_ok(model.call("connect_rooms", world, _make_connection("room_b", "exit", "room_a", "spawn_main")), "add incoming connection", failures)

	var remove_result: Dictionary = model.call("remove_room", world, "room_b")
	_assert_ok(remove_result, "remove room_b", failures)
	_assert_equal(_room_ids(world), ["room_a"], "removed room is absent", failures)
	_assert_equal(world.call("get_room_placement", "room_b"), null, "removed room placement is absent", failures)
	_assert_equal(world.connections.size(), 0, "removing a room clears all referencing connections", failures)
	_assert_true(FileAccess.file_exists(room_b.source_scene_path), "removing a room does not delete its source file", failures)


func _assert_overlap_is_warning_only(failures: Array[String]) -> void:
	var model = _new_model(failures)
	if model == null:
		return
	var world: Resource = _make_world()
	var room_a: Resource = _make_room("room_a")
	var room_b: Resource = _make_room("room_b")
	room_b.room_origin_chunk = Vector2i.ZERO
	_assert_ok(model.call("add_room", world, room_a), "add overlap room_a", failures)
	_assert_ok(model.call("add_room", world, room_b), "add overlap room_b", failures)
	world.start_room_id = "room_a"
	world.start_spawn_id = "spawn_main"

	var report: Dictionary = model.call("validate_world", world)
	_assert_true(report.get("ok", false), "overlapping rooms keep validation ok", failures)
	_assert_contains(report.get("warnings", []), "overlapping rooms: room_a, room_b", "overlap warning", failures)


func _assert_start_room_and_spawn_are_required(failures: Array[String]) -> void:
	var model = _new_model(failures)
	if model == null:
		return
	var world: Resource = _make_world()
	_assert_ok(model.call("add_room", world, _make_room("room_a")), "add start room", failures)
	world.start_room_id = "missing"
	world.start_spawn_id = "missing"
	var missing_room_report: Dictionary = model.call("validate_world", world)
	_assert_contains(missing_room_report.get("errors", []), "start_room_id does not reference a room: missing", "missing start room error", failures)

	world.start_room_id = "room_a"
	var missing_spawn_report: Dictionary = model.call("validate_world", world)
	_assert_contains(missing_spawn_report.get("errors", []), "start_spawn_id does not reference a spawn in room room_a: missing", "missing start spawn error", failures)


func _assert_directed_unreachable_rooms_are_warnings(failures: Array[String]) -> void:
	var model = _new_model(failures)
	if model == null:
		return
	var world: Resource = _make_world()
	for room_id: String in ["room_a", "room_b", "room_c"]:
		_assert_ok(model.call("add_room", world, _make_room(room_id)), "add %s for reachability" % room_id, failures)
	world.start_room_id = "room_a"
	world.start_spawn_id = "spawn_main"
	_assert_ok(model.call("connect_rooms", world, _make_connection("room_a", "exit", "room_b", "spawn_main")), "connect reachable room", failures)

	var report: Dictionary = model.call("validate_world", world)
	_assert_true(report.get("ok", false), "unreachable room is warning-only", failures)
	_assert_contains(report.get("warnings", []), "room room_c is unreachable from start room", "unreachable room warning", failures)


func _assert_no_connections_skip_reachability_warnings(failures: Array[String]) -> void:
	var model = _new_model(failures)
	if model == null:
		return
	var world: Resource = _make_world()
	for room_id: String in ["room_a", "room_b", "room_c"]:
		_assert_ok(model.call("add_room", world, _make_room(room_id)), "add %s without connections" % room_id, failures)
	world.start_room_id = "room_a"
	world.start_spawn_id = "spawn_main"
	var report: Dictionary = model.call("validate_world", world)
	for warning: String in report.get("warnings", []):
		if warning.contains("is unreachable from start room"):
			failures.append("world without valid connections produced a reachability warning: %s" % warning)


func _assert_connection_endpoints_and_unconnected_entrances_are_validated(failures: Array[String]) -> void:
	var model = _new_model(failures)
	if model == null:
		return
	var world: Resource = _make_world()
	var room_a: Resource = _make_room("room_a")
	room_a.entrance_ids = PackedStringArray(["exit_left"])
	var room_b: Resource = _make_room("room_b")
	_assert_ok(model.call("add_room", world, room_a), "add room_a for endpoint validation", failures)
	_assert_ok(model.call("add_room", world, room_b), "add room_b for endpoint validation", failures)
	world.start_room_id = "room_a"
	world.start_spawn_id = "spawn_main"

	var missing_source: Resource = _make_connection("room_a", "missing_exit", "room_b", "spawn_main")
	var missing_target: Resource = _make_connection("room_a", "exit_left", "room_b", "missing_spawn")
	world.connections.assign([missing_source, missing_target])
	var report: Dictionary = model.call("validate_world", world)
	_assert_contains(report.get("errors", []), "connection room_a->room_b references unknown source entrance: missing_exit", "unknown source entrance error", failures)
	_assert_contains(report.get("errors", []), "connection room_a->room_b references unknown target spawn: missing_spawn", "unknown target spawn error", failures)
	_assert_contains(report.get("warnings", []), "room room_a has unconnected entrance: exit_left", "unconnected entrance warning", failures)
	for warning: String in report.get("warnings", []):
		if warning.contains("is unreachable from start room"):
			failures.append("invalid-only connections enabled reachability warnings: %s" % warning)


func _assert_room_paths_and_manifest_ids_are_validated(failures: Array[String]) -> void:
	var model = _new_model(failures)
	if model == null:
		return
	var world: Resource = _make_world()
	var room: Resource = _make_room("room_a")
	room.scene_path = ""
	room.source_scene_path = ""
	room.terrain_scene_path = ""
	room.entrance_ids = PackedStringArray(["exit", "exit"])
	room.spawn_ids = PackedStringArray(["spawn", "spawn"])
	room.entity_ids = PackedStringArray(["entity", "entity"])
	world.rooms.assign([room])
	world.start_room_id = "room_a"
	world.start_spawn_id = "spawn"

	var report: Dictionary = model.call("validate_world", world)
	_assert_contains(report.get("errors", []), "room room_a has empty scene_path", "empty runtime path error", failures)
	_assert_contains(report.get("errors", []), "room room_a has empty source_scene_path", "empty source path error", failures)
	_assert_contains(report.get("errors", []), "room room_a has empty terrain_scene_path", "empty terrain path error", failures)
	_assert_contains(report.get("errors", []), "room room_a has duplicate entrance_id: exit", "duplicate entrance id error", failures)
	_assert_contains(report.get("errors", []), "room room_a has duplicate spawn_id: spawn", "duplicate spawn id error", failures)
	_assert_contains(report.get("errors", []), "room room_a has duplicate entity_id: entity", "duplicate entity id error", failures)


func _new_model(failures: Array[String]):
	if not FileAccess.file_exists(MODEL_PATH):
		if not _missing_model_reported:
			failures.append("missing production API: %s" % MODEL_PATH)
			_missing_model_reported = true
		return null
	var model_script: Script = load(MODEL_PATH) as Script
	if model_script == null:
		if not _missing_model_reported:
			failures.append("missing production API: %s" % MODEL_PATH)
			_missing_model_reported = true
		return null
	return model_script.new()


func _make_world() -> Resource:
	var world: Resource = WORLD_DATA.new()
	world.world_id = "world_01"
	return world


func _make_room(room_id: String) -> Resource:
	var room: Resource = ROOM_DATA.new()
	room.room_id = room_id
	room.scene_path = "res://scenes/rooms/%s.tscn" % room_id
	room.source_scene_path = "res://scenes/levels/%s.tscn" % room_id
	room.terrain_scene_path = "res://scenes/generated/%s_terrain.tscn" % room_id
	room.entrance_ids = PackedStringArray(["exit"])
	room.spawn_ids = PackedStringArray(["spawn_main"])
	room.entity_ids = PackedStringArray(["entity_main"])
	return room


func _make_connection(from_room_id: String, from_entrance_id: String, to_room_id: String, to_spawn_id: String) -> Resource:
	var connection: Resource = ROOM_CONNECTION_DATA.new()
	connection.from_room_id = from_room_id
	connection.from_entrance_id = from_entrance_id
	connection.to_room_id = to_room_id
	connection.to_spawn_id = to_spawn_id
	return connection


func _room_ids(world: Resource) -> Array[String]:
	var result: Array[String] = []
	for room: Resource in world.rooms:
		if room != null and "room_id" in room:
			result.append(room.room_id)
	return result


func _connection_keys(world: Resource) -> Array[String]:
	var result: Array[String] = []
	for connection: Resource in world.connections:
		result.append("%s:%s" % [connection.from_room_id, connection.from_entrance_id])
	return result


func _assert_ok(result: Dictionary, label: String, failures: Array[String]) -> void:
	if not result.get("ok", false):
		failures.append("%s failed: %s" % [label, str(result.get("errors", []))])


func _assert_true(condition: bool, label: String, failures: Array[String]) -> void:
	if not condition:
		failures.append("%s: expected true" % label)


func _assert_false(condition: bool, label: String, failures: Array[String]) -> void:
	if condition:
		failures.append("%s: expected false" % label)


func _assert_equal(actual: Variant, expected: Variant, label: String, failures: Array[String]) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_contains(values: Variant, expected: String, label: String, failures: Array[String]) -> void:
	if not values is Array or not values.has(expected):
		failures.append("%s: missing %s in %s" % [label, expected, str(values)])
