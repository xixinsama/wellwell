@tool
class_name WorldRoomImporter
extends RefCounted

const WORLD_DATA_SCRIPT := preload("res://scripts/world/world_data.gd")
const ROOM_DATA_SCRIPT := preload("res://scripts/world/room_data.gd")
const ROOM_BAKER := preload("res://scripts/authoring/room_baker.gd")
const WORLD_RESOURCE_SERVICE := preload("res://scripts/authoring/world_resource_service.gd")
const WORLD_LAYOUT_MODEL := preload("res://scripts/authoring/world_layout_model.gd")
const WORLD_DIRECTORY := "res://resources/worlds/"

var _room_baker: Object = ROOM_BAKER.new()
var _world_resources: Object = WORLD_RESOURCE_SERVICE.new()
var _layout_model: Object = WORLD_LAYOUT_MODEL.new()


func set_room_baker_adapter(value: Object) -> void:
	_room_baker = value


func set_world_resources_adapter(value: Object) -> void:
	_world_resources = value


func set_layout_model_adapter(value: Object) -> void:
	_layout_model = value


func import_room(world: WorldData, source_root: Node, source_path: String) -> Dictionary:
	if not _is_world_data(world):
		return _failure("world is not WorldData")
	if world.resource_path.is_empty() or not FileAccess.file_exists(world.resource_path):
		return _failure("WorldData must be saved before importing a room", world.resource_path)
	if world.resource_path.simplify_path() != world.resource_path \
		or not world.resource_path.begins_with(WORLD_DIRECTORY) \
		or world.resource_path.get_extension().to_lower() != "tres":
		return _failure("WorldData must be saved inside %s" % WORLD_DIRECTORY, world.resource_path)
	if source_root == null:
		return _failure("room source is null", world.resource_path)
	if source_path.simplify_path() != source_path \
		or not source_path.begins_with("res://") \
		or source_path.get_extension().to_lower() != "tscn":
		return _failure("room source path must be a res:// .tscn file", world.resource_path)

	var staged: Dictionary = _room_baker.call("stage", source_root, source_path)
	if not bool(staged.get("ok", false)):
		return _from_dependency_failure(staged, world.resource_path)
	var staged_room := staged.get("room_data") as RoomData
	var manifest: Dictionary = staged.get("manifest", {})
	var outputs: Dictionary = staged.get("outputs", {})
	var output_error := _validate_staged_outputs(staged_room, manifest, outputs)
	if not output_error.is_empty():
		return _failure(output_error, world.resource_path)

	var before_state: Dictionary = _layout_model.call("capture_world_state", world)
	var candidate := world.duplicate(true) as WorldData
	var add_result: Dictionary = _layout_model.call("add_room", candidate, staged_room)
	if not bool(add_result.get("ok", false)):
		return _from_dependency_failure(add_result, world.resource_path)
	var start_error := _prepare_start_endpoint(world, candidate, staged_room, manifest)
	if not start_error.is_empty():
		return _failure(start_error, world.resource_path)

	var final_outputs := outputs.duplicate()
	final_outputs["world_resource_path"] = world.resource_path
	var final_paths := _ordered_final_paths(final_outputs)
	var transaction_file_error := _find_existing_transaction_file(final_paths)
	if not transaction_file_error.is_empty():
		return _failure(transaction_file_error, world.resource_path)
	var backup_state: Dictionary = {}
	var backup_errors: Array[String] = []
	if not _create_outer_backups(final_paths, backup_state, backup_errors):
		_cleanup_created_outer_backups(backup_state, backup_errors)
		return _result(false, backup_errors, _copy_strings(staged.get("warnings", [])), null, null, world.resource_path, final_outputs)

	var warnings := _copy_strings(staged.get("warnings", []))
	var room_save: Dictionary = _room_baker.call("save_staged", staged)
	warnings.append_array(_copy_strings(room_save.get("warnings", [])))
	if not bool(room_save.get("ok", false)):
		var errors := _copy_strings(room_save.get("errors", []))
		_rollback(final_paths, backup_state, errors)
		_cleanup_inner_files(final_paths, errors)
		return _result(false, errors, warnings, null, null, world.resource_path, final_outputs)

	var imported_room := ResourceLoader.load(
		String(outputs["room_resource_path"]),
		"RoomData",
		ResourceLoader.CACHE_MODE_IGNORE
	) as RoomData
	if not _is_room_data(imported_room):
		var errors: Array[String] = ["generated RoomData could not be reloaded: %s" % outputs["room_resource_path"]]
		_rollback(final_paths, backup_state, errors)
		_cleanup_inner_files(final_paths, errors)
		return _result(false, errors, warnings, null, null, world.resource_path, final_outputs)

	var replace_result: Dictionary = _layout_model.call("replace_room", candidate, staged_room.room_id, imported_room)
	if not bool(replace_result.get("ok", false)):
		var errors := _copy_strings(replace_result.get("errors", []))
		_rollback(final_paths, backup_state, errors)
		_cleanup_inner_files(final_paths, errors)
		return _result(false, errors, warnings, null, null, world.resource_path, final_outputs)

	var world_save: Dictionary = _world_resources.call("save_candidate", candidate, world.resource_path)
	warnings.append_array(_copy_strings(world_save.get("warnings", [])))
	if not bool(world_save.get("ok", false)):
		var errors := _copy_strings(world_save.get("errors", []))
		_rollback(final_paths, backup_state, errors)
		_cleanup_inner_files(final_paths, errors)
		return _result(false, errors, warnings, null, null, world.resource_path, final_outputs)
	var saved_world := world_save.get("world") as WorldData
	if not _is_world_data(saved_world) or not saved_world.has_room(imported_room.room_id):
		var errors: Array[String] = ["saved WorldData does not contain the imported room"]
		_rollback(final_paths, backup_state, errors)
		_cleanup_inner_files(final_paths, errors)
		return _result(false, errors, warnings, null, null, world.resource_path, final_outputs)

	_cleanup_committed_backups(backup_state, warnings)
	_cleanup_inner_files(final_paths, warnings)
	var result := _result(true, [], warnings, saved_world, saved_world.get_room(imported_room.room_id), world.resource_path, final_outputs)
	result["source_path"] = source_path
	result["before_state"] = before_state
	result["after_state"] = _layout_model.call("capture_world_state", saved_world)
	return result


func _prepare_start_endpoint(world: WorldData, candidate: WorldData, room: RoomData, manifest: Dictionary) -> String:
	if world.rooms.is_empty():
		var preview_spawn_id := String(manifest.get("preview_spawn_id", ""))
		if preview_spawn_id.is_empty() or not room.spawn_ids.has(preview_spawn_id):
			return "first room requires a valid preview_spawn_id"
		candidate.start_room_id = room.room_id
		candidate.start_spawn_id = preview_spawn_id
		return ""
	if world.start_room_id.is_empty() or world.start_spawn_id.is_empty():
		return "non-empty WorldData is missing its start endpoint"
	var start_room: Resource = world.get_room(world.start_room_id)
	if start_room == null or not start_room.spawn_ids.has(world.start_spawn_id):
		return "non-empty WorldData has an invalid start endpoint"
	return ""


func _validate_staged_outputs(room: RoomData, manifest: Dictionary, outputs: Dictionary) -> String:
	if not _is_room_data(room):
		return "staged room is not RoomData"
	if String(manifest.get("room_id", "")) != room.room_id:
		return "staged manifest room_id does not match RoomData"
	var paths: Array[String] = []
	for key: String in ["room_resource_path", "runtime_scene_path", "terrain_scene_path"]:
		var path := String(outputs.get(key, ""))
		if path.is_empty() or not path.begins_with("res://"):
			return "staged room output path is invalid: %s" % key
		paths.append(path)
	var unique_paths: Dictionary = {}
	for path: String in paths:
		if unique_paths.has(path):
			return "staged room output paths are not distinct"
		unique_paths[path] = true
	return ""


func _ordered_final_paths(outputs: Dictionary) -> Array[String]:
	return [
		String(outputs["runtime_scene_path"]),
		String(outputs["terrain_scene_path"]),
		String(outputs["room_resource_path"]),
		String(outputs["world_resource_path"]),
	]


func _create_outer_backups(paths: Array[String], state: Dictionary, errors: Array[String]) -> bool:
	for path: String in paths:
		var backup := _marked_path(path, ".import_backup")
		if FileAccess.file_exists(backup):
			errors.append("room import backup already exists: %s" % backup)
			return false
		var existed := FileAccess.file_exists(path)
		state[path] = {"existed": existed, "backup": backup, "copied": false}
		if existed:
			var copy_error := DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(backup))
			if copy_error != OK:
				errors.append("could not back up room import output: %s" % path)
				return false
			state[path]["copied"] = true
	return true


func _find_existing_transaction_file(paths: Array[String]) -> String:
	for path: String in paths:
		for marker: String in [".backup", ".import_backup"]:
			var temporary := _marked_path(path, marker)
			if FileAccess.file_exists(temporary):
				return "refusing room import while transaction file exists: %s" % temporary
	return ""


func _cleanup_created_outer_backups(state: Dictionary, errors: Array[String]) -> void:
	for path: String in state:
		var backup := String(state[path].get("backup", ""))
		if not backup.is_empty() and FileAccess.file_exists(backup) and _remove_file(backup) != OK:
			errors.append("could not remove unused room import backup: %s" % backup)


func _rollback(paths: Array[String], state: Dictionary, errors: Array[String]) -> void:
	for path: String in paths:
		var entry: Dictionary = state.get(path, {})
		var existed := bool(entry.get("existed", false))
		var backup := String(entry.get("backup", ""))
		if FileAccess.file_exists(path) and _remove_file(path) != OK:
			errors.append("could not remove failed room import output: %s" % path)
			continue
		if existed:
			if not FileAccess.file_exists(backup):
				errors.append("room import backup is missing: %s" % backup)
			elif _move_file(backup, path) != OK:
				errors.append("could not restore room import output: %s" % path)
		elif FileAccess.file_exists(backup) and _remove_file(backup) != OK:
			errors.append("could not remove room import backup: %s" % backup)
	for path: String in paths:
		var backup := _marked_path(path, ".import_backup")
		if FileAccess.file_exists(backup) and _remove_file(backup) != OK:
			errors.append("could not clean room import backup: %s" % backup)


func _cleanup_committed_backups(state: Dictionary, warnings: Array[String]) -> void:
	for path: String in state:
		var backup := String(state[path].get("backup", ""))
		if FileAccess.file_exists(backup) and _remove_file(backup) != OK:
			warnings.append("retained room import backup after commit: %s" % backup)


func _cleanup_inner_files(paths: Array[String], messages: Array[String]) -> void:
	for path: String in paths:
		for marker: String in [".stage", ".backup"]:
			var temporary := _marked_path(path, marker)
			if FileAccess.file_exists(temporary) and _remove_file(temporary) != OK:
				messages.append("could not remove transaction file: %s" % temporary)


func _marked_path(path: String, marker: String) -> String:
	var extension_start := path.rfind(".")
	return "%s%s%s" % [path.left(extension_start), marker, path.substr(extension_start)]


func _move_file(from_path: String, to_path: String) -> Error:
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(from_path), ProjectSettings.globalize_path(to_path))


func _remove_file(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _copy_strings(values: Variant) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		result.append(String(value))
	return result


func _from_dependency_failure(result: Dictionary, path: String) -> Dictionary:
	return _result(
		false,
		_copy_strings(result.get("errors", [])),
		_copy_strings(result.get("warnings", [])),
		null,
		null,
		path,
		{}
	)


func _failure(message: String, path := "") -> Dictionary:
	return _result(false, [message], [], null, null, path, {})


func _result(
	ok: bool,
	errors: Array[String],
	warnings: Array[String],
	world: WorldData,
	room: RoomData,
	path: String,
	outputs: Dictionary
) -> Dictionary:
	errors.sort()
	warnings.sort()
	return {
		"ok": ok,
		"errors": errors,
		"warnings": warnings,
		"world": world,
		"room": room,
		"path": path,
		"outputs": outputs,
	}


static func _is_world_data(resource: Resource) -> bool:
	return resource != null and resource.get_script() == WORLD_DATA_SCRIPT


static func _is_room_data(resource: Resource) -> bool:
	return resource != null and resource.get_script() == ROOM_DATA_SCRIPT
