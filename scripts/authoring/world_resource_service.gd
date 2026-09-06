@tool
class_name WorldResourceService
extends RefCounted

const WORLD_DATA_SCRIPT: Script = preload("res://scripts/world/world_data.gd")
const ROOM_DATA_SCRIPT: Script = preload("res://scripts/world/room_data.gd")
const CONNECTION_DATA_SCRIPT: Script = preload("res://scripts/world/room_connection_data.gd")
const WORLD_DIRECTORY := "res://resources/worlds/"


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
	if _move_file(staged_path, final_path) != OK:
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
		errors.append("reloaded world differs from staged WorldData")
	return errors.is_empty()


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
			"room_origin_chunk": room.room_origin_chunk,
			"room_size_chunks": room.room_size_chunks,
			"adjacent_room_ids": Array(room.adjacent_room_ids),
			"map_color": room.map_color,
		})
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


func _remove_file(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


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
