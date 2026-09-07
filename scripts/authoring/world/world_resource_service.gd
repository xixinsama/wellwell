@tool
class_name WorldResourceService
extends RefCounted

const WORLD_DATA_SCRIPT: Script = preload("res://scripts/world/data/world_data.gd")
const ROOM_DATA_SCRIPT: Script = preload("res://scripts/world/data/room_data.gd")
const CONNECTION_DATA_SCRIPT: Script = preload("res://scripts/world/data/room_connection_data.gd")
const ROOM_PLACEMENT_DATA_SCRIPT: Script = preload("res://scripts/world/data/world_room_placement_data.gd")
const WORLD_DIRECTORY := "res://resources/worlds/"

var allow_user_paths := false


func set_allow_user_paths(value: bool) -> void:
	allow_user_paths = value


func create_world(path: String) -> Dictionary:
	var path_error := _validate_path(path)
	if not path_error.is_empty():
		return _failure(path_error, path)
	if FileAccess.file_exists(path):
		return _failure("world resource already exists: %s" % path, path)
	var world := WORLD_DATA_SCRIPT.new() as WorldData
	world.world_id = path.get_file().get_basename()
	return save_candidate(world, path)


func load_world(path: String) -> Dictionary:
	var path_error := _validate_path(path)
	if not path_error.is_empty():
		return _failure(path_error, path)
	if not FileAccess.file_exists(path):
		return _failure("world resource does not exist: %s" % path, path)
	var world := ResourceLoader.load(path, "WorldData", ResourceLoader.CACHE_MODE_IGNORE) as WorldData
	if not _is_world_data(world):
		return _failure("resource is not WorldData: %s" % path, path)
	return _result(true, [], [], world, path)


func save_world(world: WorldData) -> Dictionary:
	if not _is_world_data(world):
		return _failure("world is not WorldData")
	if world.resource_path.is_empty():
		return _failure("world resource_path is empty")
	return save_candidate(world, world.resource_path)


func save_candidate(world: WorldData, final_path: String) -> Dictionary:
	if not _is_world_data(world):
		return _failure("world is not WorldData", final_path)
	var path_error := _validate_path(final_path)
	if not path_error.is_empty():
		return _failure(path_error, final_path)
	var directory_error := _ensure_directory(final_path.get_base_dir())
	if directory_error != OK:
		return _failure("could not create world resource directory: %s" % final_path.get_base_dir(), final_path)

	var candidate := world.duplicate(true) as WorldData
	candidate.sort_for_serialization()
	var expected_signature := _world_signature(candidate)
	var staged_path := _marked_path(final_path, ".stage")
	var backup_path := _marked_path(final_path, ".backup")
	var warnings: Array[String] = []
	var errors: Array[String] = []
	if FileAccess.file_exists(backup_path):
		return _failure("refusing to replace world while backup exists: %s" % backup_path, final_path)
	if _remove_file(staged_path) != OK:
		return _failure("could not remove stale staged world: %s" % staged_path, final_path)
	if _save_resource(candidate, staged_path) != OK:
		_remove_file(staged_path)
		return _failure("could not save staged world: %s" % staged_path, final_path)
	if not _validate_saved_world(staged_path, expected_signature, errors):
		_remove_file(staged_path)
		return _result(false, errors, warnings, null, final_path)

	var had_previous := FileAccess.file_exists(final_path)
	if had_previous and _move_file(final_path, backup_path) != OK:
		_remove_file(staged_path)
		return _failure("could not back up world resource: %s" % final_path, final_path)
	if _promote_staged_file(staged_path, final_path) != OK:
		errors.append("could not install staged world: %s" % final_path)
		_restore_backup(final_path, backup_path, staged_path, had_previous, errors)
		return _result(false, errors, warnings, null, final_path)
	if not _validate_saved_world(final_path, expected_signature, errors):
		_restore_backup(final_path, backup_path, staged_path, had_previous, errors)
		return _result(false, errors, warnings, null, final_path)
	if had_previous and _remove_file(backup_path) != OK:
		warnings.append("retained world backup after committed transaction: %s" % backup_path)
	var loaded := ResourceLoader.load(final_path, "WorldData", ResourceLoader.CACHE_MODE_IGNORE) as WorldData
	return _result(true, [], warnings, loaded, final_path)


func _validate_saved_world(path: String, expected_signature: Dictionary, errors: Array[String]) -> bool:
	var saved := ResourceLoader.load(path, "WorldData", ResourceLoader.CACHE_MODE_IGNORE) as WorldData
	if not _is_world_data(saved):
		errors.append("could not reload staged WorldData: %s" % path)
		return false
	if _world_signature(saved) != expected_signature:
		errors.append("reloaded world differs from staged WorldData: %s" % describe_first_difference(expected_signature, _world_signature(saved)))
	return errors.is_empty()


func describe_first_difference(expected: Dictionary, actual: Dictionary) -> String:
	var difference := _find_first_difference(expected, actual, "")
	return difference if not difference.is_empty() else "unknown difference"


func _find_first_difference(expected: Variant, actual: Variant, path: String) -> String:
	if expected is Dictionary and actual is Dictionary:
		var expected_dict: Dictionary = expected
		var actual_dict: Dictionary = actual
		var keys: Array[String] = []
		for key: Variant in expected_dict.keys():
			keys.append(String(key))
		for key: Variant in actual_dict.keys():
			if not keys.has(String(key)):
				keys.append(String(key))
		keys.sort()
		for key: String in keys:
			var child_path := key if path.is_empty() else "%s.%s" % [path, key]
			if not expected_dict.has(key) or not actual_dict.has(key):
				return "%s expected=%s actual=%s" % [child_path, str(expected_dict.get(key)), str(actual_dict.get(key))]
			var nested := _find_first_difference(expected_dict[key], actual_dict[key], child_path)
			if not nested.is_empty():
				return nested
		return ""
	if expected is Array and actual is Array:
		var expected_array: Array = expected
		var actual_array: Array = actual
		if expected_array.size() != actual_array.size():
			return "%s.size expected=%d actual=%d" % [path, expected_array.size(), actual_array.size()]
		for index: int in expected_array.size():
			var child_path := "%s[%d]" % [path, index]
			var nested := _find_first_difference(expected_array[index], actual_array[index], child_path)
			if not nested.is_empty():
				return nested
		return ""
	if expected != actual:
		return "%s expected=%s actual=%s" % [path, str(expected), str(actual)]
	return ""


func _restore_backup(
	final_path: String,
	backup_path: String,
	staged_path: String,
	had_previous: bool,
	errors: Array[String]
) -> void:
	if FileAccess.file_exists(final_path) and _remove_file(final_path) != OK:
		errors.append("could not remove failed world output: %s" % final_path)
	if had_previous:
		if not FileAccess.file_exists(backup_path):
			errors.append("world backup is missing: %s" % backup_path)
		elif FileAccess.file_exists(final_path) or _move_file(backup_path, final_path) != OK:
			errors.append("could not restore world backup: %s" % final_path)
	if FileAccess.file_exists(staged_path) and _remove_file(staged_path) != OK:
		errors.append("could not remove staged world after rollback: %s" % staged_path)


func _validate_path(path: String) -> String:
	if allow_user_paths and path.begins_with("user://"):
		if path.simplify_path() != path:
			return "world path must not contain relative segments: %s" % path
		if path.get_extension().to_lower() != "tres":
			return "world path must use the .tres extension: %s" % path
		return "" if not path.get_file().get_basename().is_empty() else "world filename must not be empty"
	if not path.begins_with(WORLD_DIRECTORY):
		return "world path must be inside %s" % WORLD_DIRECTORY
	if path.simplify_path() != path:
		return "world path must not contain relative segments: %s" % path
	if path.get_extension().to_lower() != "tres":
		return "world path must use the .tres extension: %s" % path
	if path.get_file().get_basename().is_empty():
		return "world filename must not be empty"
	return ""


func _world_signature(world: WorldData) -> Dictionary:
	var rooms: Array[Dictionary] = []
	for room: Resource in world.rooms:
		if room == null or room.get_script() != ROOM_DATA_SCRIPT:
			rooms.append({"invalid_resource": true})
			continue
		rooms.append({
			"room_id": room.room_id,
			"display_name": room.display_name,
			"scene_path": room.scene_path,
			"source_scene_path": room.source_scene_path,
			"terrain_scene_path": room.terrain_scene_path,
			"entrance_ids": Array(room.entrance_ids),
			"spawn_ids": Array(room.spawn_ids),
			"entity_ids": Array(room.entity_ids),
			"tags": Array(room.tags),
			"room_size_chunks": room.room_size_chunks,
			"map_color": room.map_color,
		})
	var placements: Dictionary = {}
	for index: int in world.placements.size():
		var placement: Resource = world.placements[index]
		if placement == null or placement.get_script() != ROOM_PLACEMENT_DATA_SCRIPT:
			placements["#invalid_%d" % index] = {"invalid_resource": true}
		else:
			placements[placement.room_id] = {"origin_chunk": placement.origin_chunk}
	var connections: Array[Dictionary] = []
	for connection: Resource in world.connections:
		if connection == null or connection.get_script() != CONNECTION_DATA_SCRIPT:
			connections.append({"invalid_resource": true})
			continue
		connections.append({
			"from_room_id": connection.from_room_id,
			"from_entrance_id": connection.from_entrance_id,
			"to_room_id": connection.to_room_id,
			"to_spawn_id": connection.to_spawn_id,
			"direction": connection.direction,
		})
	return {
		"world_id": world.world_id,
		"start_room_id": world.start_room_id,
		"start_spawn_id": world.start_spawn_id,
		"tags": Array(world.tags),
		"rooms": rooms,
		"placements": placements,
		"connections": connections,
	}


func _ensure_directory(path: String) -> Error:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
		return OK
	return DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))


func _save_resource(resource: Resource, path: String) -> Error:
	return ResourceSaver.save(resource, path)


func _move_file(from_path: String, to_path: String) -> Error:
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(from_path), ProjectSettings.globalize_path(to_path))


func _promote_staged_file(staged_path: String, final_path: String) -> Error:
	var uid := ResourceLoader.get_resource_uid(staged_path)
	var move_error := _move_file(staged_path, final_path)
	if move_error == OK and uid != ResourceUID.INVALID_ID and ResourceUID.has_id(uid):
		ResourceUID.set_id(uid, final_path)
	return move_error


func _remove_file(path: String) -> Error:
	var uid := _registered_uid_for_path(path)
	if not FileAccess.file_exists(path):
		_forget_uid_path(uid, path)
		return OK
	var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if remove_error == OK:
		_forget_uid_path(uid, path)
	return remove_error


func _registered_uid_for_path(path: String) -> int:
	var uid_text := ResourceUID.path_to_uid(path)
	if not uid_text.begins_with("uid://"):
		return ResourceUID.INVALID_ID
	return ResourceUID.text_to_id(uid_text)


func _forget_uid_path(uid: int, path: String) -> void:
	if uid != ResourceUID.INVALID_ID and ResourceUID.has_id(uid) and ResourceUID.get_id_path(uid) == path:
		ResourceUID.remove_id(uid)


func _copy_strings(values: Variant) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		result.append(String(value))
	return result


func _marked_path(path: String, marker: String) -> String:
	var extension_start := path.rfind(".")
	return "%s%s%s" % [path.left(extension_start), marker, path.substr(extension_start)]


func _failure(message: String, path := "") -> Dictionary:
	return _result(false, [message], [], null, path)


func _result(
	ok: bool,
	errors: Array[String],
	warnings: Array[String],
	world: WorldData,
	path: String
) -> Dictionary:
	errors.sort()
	warnings.sort()
	return {
		"ok": ok,
		"errors": errors,
		"warnings": warnings,
		"world": world,
		"path": path,
	}


static func _is_world_data(resource: Resource) -> bool:
	return resource != null and resource.get_script() == WORLD_DATA_SCRIPT
