extends Node

const SERVICE_PATH := "res://scripts/authoring/world/world_resource_service.gd"
const WORLD_DATA := preload("res://addons/platformer_kit/world/data/world_data.gd")
const ROOM_DATA := preload("res://addons/platformer_kit/world/data/room_data.gd")
const WORLD_PATH := "res://resources/worlds/test_main_world.tres"
const WRONG_TYPE_PATH := "res://resources/worlds/test_wrong_world_resource.tres"


class FailingWorldResourceService extends "res://scripts/authoring/world/world_resource_service.gd":
	func _save_resource(_resource: Resource, _path: String) -> Error:
		return ERR_CANT_CREATE


func run() -> Array[String]:
	var failures: Array[String] = []
	_cleanup()
	if not FileAccess.file_exists(SERVICE_PATH):
		return ["missing production API: %s" % SERVICE_PATH]
	var service_script := load(SERVICE_PATH) as Script
	if service_script == null or not service_script.can_instantiate():
		return ["WorldResourceService could not be loaded"]
	var service: Object = service_script.new()
	_assert_rejected_paths(service, failures)
	_assert_create_and_save(service, failures)
	_assert_load_errors(service, failures)
	_assert_failed_save_preserves_existing_world(failures)
	_assert_moved_world_placement_survives_reload(service, failures)
	_assert_signature_reports_placement_difference(service, failures)
	_cleanup()
	return failures


func _assert_rejected_paths(service: Object, failures: Array[String]) -> void:
	for path: String in [
		"user://bad.tres",
		"res://tests/bad_world.tres",
		"res://resources/worlds/bad_world.res",
	]:
		var result: Dictionary = service.call("create_world", path)
		_assert_envelope(result, "rejected path %s" % path, failures)
		if bool(result.get("ok", false)):
			failures.append("world creation accepted invalid path: %s" % path)


func _assert_create_and_save(service: Object, failures: Array[String]) -> void:
	var result: Dictionary = service.call("create_world", WORLD_PATH)
	_assert_envelope(result, "create world", failures)
	if not bool(result.get("ok", false)):
		failures.append("valid WorldData creation failed: %s" % str(result.get("errors", [])))
		return
	var world := result.get("world") as Resource
	if world == null or world.get_script() != WORLD_DATA:
		failures.append("world creation did not return WorldData")
		return
	if world.world_id != "test_main_world":
		failures.append("world_id was not derived from the filename")
	if world.resource_path != WORLD_PATH or not FileAccess.file_exists(WORLD_PATH):
		failures.append("created WorldData was not installed at the requested path")
	if bool(service.call("create_world", WORLD_PATH).get("ok", false)):
		failures.append("world creation replaced an existing resource")

	world.tags = PackedStringArray(["saved-change"])
	result = service.call("save_world", world)
	_assert_envelope(result, "save world", failures)
	var reloaded := ResourceLoader.load(WORLD_PATH, "WorldData", ResourceLoader.CACHE_MODE_IGNORE) as Resource
	if not bool(result.get("ok", false)) or reloaded == null or reloaded.tags != PackedStringArray(["saved-change"]):
		failures.append("save_world did not persist the changed WorldData")

	var unsaved := WORLD_DATA.new() as Resource
	if bool(service.call("save_world", unsaved).get("ok", false)):
		failures.append("save_world accepted an unsaved WorldData")
	if bool(service.call("save_world", null).get("ok", false)):
		failures.append("save_world accepted null")


func _assert_load_errors(service: Object, failures: Array[String]) -> void:
	var missing: Dictionary = service.call("load_world", "res://resources/worlds/test_missing_world.tres")
	_assert_envelope(missing, "missing world", failures)
	if bool(missing.get("ok", false)):
		failures.append("load_world accepted a missing resource")
	if ResourceSaver.save(Resource.new(), WRONG_TYPE_PATH) != OK:
		failures.append("could not save wrong-type resource fixture")
		return
	var wrong_type: Dictionary = service.call("load_world", WRONG_TYPE_PATH)
	_assert_envelope(wrong_type, "wrong resource type", failures)
	if bool(wrong_type.get("ok", false)):
		failures.append("load_world accepted a resource that is not WorldData")


func _assert_failed_save_preserves_existing_world(failures: Array[String]) -> void:
	var previous_bytes := FileAccess.get_file_as_bytes(WORLD_PATH)
	var candidate := ResourceLoader.load(WORLD_PATH, "WorldData", ResourceLoader.CACHE_MODE_IGNORE) as Resource
	if candidate == null:
		failures.append("could not load existing world for failed-save test")
		return
	candidate.tags = PackedStringArray(["must-not-replace-existing"])
	var result: Dictionary = FailingWorldResourceService.new().save_candidate(candidate, WORLD_PATH)
	_assert_envelope(result, "forced save failure", failures)
	if bool(result.get("ok", false)):
		failures.append("forced staged save failure was reported as success")
	if FileAccess.get_file_as_bytes(WORLD_PATH) != previous_bytes:
		failures.append("forced staged save failure changed the existing world file")
	for temporary_path: String in [
		_marked_path(WORLD_PATH, ".stage"),
		_marked_path(WORLD_PATH, ".backup"),
	]:
		if FileAccess.file_exists(temporary_path):
			failures.append("forced staged save failure retained temporary file: %s" % temporary_path)


func _assert_moved_world_placement_survives_reload(service: Object, failures: Array[String]) -> void:
	var world: Resource = WORLD_DATA.new()
	world.world_id = "placement_persistence_world"
	var room: Resource = ROOM_DATA.new()
	room.room_id = "room_a"
	world.rooms.assign([room])
	world.set_room_origin_chunk("room_a", Vector2i(-1, -1))
	var result: Dictionary = service.call("save_candidate", world, WORLD_PATH)
	if not result.get("ok", false):
		failures.append("moved placement could not be saved: %s" % result.get("errors", []))
		return
	var reloaded := ResourceLoader.load(WORLD_PATH, "WorldData", ResourceLoader.CACHE_MODE_IGNORE) as Resource
	if reloaded == null or reloaded.call("get_room_origin_chunk", "room_a") != Vector2i(-1, -1):
		failures.append("moved WorldData placement did not survive save/reload")
	var signature: Dictionary = service.call("_world_signature", world)
	var reloaded_signature: Dictionary = service.call("_world_signature", reloaded)
	if signature != reloaded_signature:
		failures.append("world signature changed after reloading embedded placement")


func _assert_signature_reports_placement_difference(service: Object, failures: Array[String]) -> void:
	if not service.has_method("describe_first_difference"):
		failures.append("world resource service is missing first-difference diagnostics")
		return
	var world_a: Resource = WORLD_DATA.new()
	world_a.world_id = "diagnostic_world"
	var room_a: Resource = ROOM_DATA.new()
	room_a.room_id = "room_a"
	world_a.rooms.assign([room_a])
	world_a.set_room_origin_chunk("room_a", Vector2i.ZERO)
	var world_b := world_a.duplicate(true) as Resource
	world_b.set_room_origin_chunk("room_a", Vector2i(4, 2))
	var difference := String(service.call(
		"describe_first_difference",
		service.call("_world_signature", world_a),
		service.call("_world_signature", world_b)
	))
	if not difference.contains("placements.room_a.origin_chunk"):
		failures.append("placement signature diagnostic omitted the first differing field: %s" % difference)


func _assert_envelope(result: Dictionary, label: String, failures: Array[String]) -> void:
	if not result.has_all(["ok", "errors", "warnings", "world", "path"]):
		failures.append("%s result is missing the common envelope: %s" % [label, str(result)])


func _cleanup() -> void:
	for path: String in [
		WORLD_PATH,
		_marked_path(WORLD_PATH, ".stage"),
		_marked_path(WORLD_PATH, ".backup"),
		WRONG_TYPE_PATH,
		_marked_path(WRONG_TYPE_PATH, ".stage"),
		_marked_path(WRONG_TYPE_PATH, ".backup"),
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _marked_path(path: String, marker: String) -> String:
	return "%s%s.tres" % [path.trim_suffix(".tres"), marker]
