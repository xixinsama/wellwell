@tool
class_name WorldBaker
extends RefCounted

const WORLD_DATA_SCRIPT: Script = preload("res://scripts/world/world_data.gd")
const ROOM_DATA_SCRIPT: Script = preload("res://scripts/world/room_data.gd")
const WORLD_VALIDATION: Script = preload("res://scripts/world/world_validation.gd")
const ROOM_AUTHORING_CONTRACT: Script = preload("res://scripts/authoring/room_authoring_contract.gd")
const TERRAIN_LAYER_NAMES: Array[String] = [
	"BackTiles", "SolidTiles", "GlassTiles", "VisionBlockTiles", "DetailTiles", "MarkerTiles"
]


func bake(world: WorldData) -> Dictionary:
	if not _is_world_data(world):
		return _failure("world is not WorldData")
	if world.resource_path.is_empty():
		return _failure("world resource_path is empty")
	var report: Dictionary = WORLD_VALIDATION.validate_world_report(world)
	var errors := _copy_strings(report.get("errors", []))
	var warnings := _copy_strings(report.get("warnings", []))
	if not errors.is_empty():
		return _result(false, errors, warnings)
	for room_id: String in world.get_room_ids():
		_validate_room_artifacts(world.get_room(room_id), errors)
	if not errors.is_empty():
		return _result(false, errors, warnings)
	world.sort_for_serialization()
	return _save_transactionally(world, warnings)


func _save_transactionally(world: WorldData, warnings: Array[String]) -> Dictionary:
	var final_path := world.resource_path
	var staged_path := _marked_path(final_path, ".stage")
	var backup_path := _marked_path(final_path, ".backup")
	var errors: Array[String] = []
	if FileAccess.file_exists(backup_path):
		return _result(false, ["refusing to replace world while backup exists: %s" % backup_path], warnings)
	if _remove_file(staged_path) != OK:
		return _result(false, ["could not remove stale staged world: %s" % staged_path], warnings)
	var expected_signature := _world_signature(world)
	var save_error := ResourceSaver.save(world, staged_path)
	if save_error != OK:
		_remove_file(staged_path)
		return _result(false, ["could not save staged world: %s" % staged_path], warnings)
	var hook_result := _after_staged_world_saved(staged_path, world)
	if not bool(hook_result.get("ok", false)):
		_remove_file(staged_path)
		return _result(false, _copy_strings(hook_result.get("errors", [])), warnings)
	if not _validate_saved_world(staged_path, expected_signature, errors):
		_remove_file(staged_path)
		return _result(false, errors, warnings)

	var had_previous := FileAccess.file_exists(final_path)
	if had_previous and _move_file(final_path, backup_path) != OK:
		_remove_file(staged_path)
		return _result(false, ["could not back up world resource: %s" % final_path], warnings)
	if _promote_staged_file(staged_path, final_path) != OK:
		errors.append("could not install staged world: %s" % final_path)
		_restore_world_backup(final_path, backup_path, staged_path, had_previous, errors)
		return _result(false, errors, warnings)
	if not _validate_saved_world(final_path, expected_signature, errors):
		_restore_world_backup(final_path, backup_path, staged_path, had_previous, errors)
		return _result(false, errors, warnings)
	if had_previous and _remove_file(backup_path) != OK:
		warnings.append("retained world backup after committed transaction: %s" % backup_path)
	return _result(true, [], warnings)


func _validate_saved_world(path: String, expected_signature: Dictionary, errors: Array[String]) -> bool:
	var saved := ResourceLoader.load(path, "WorldData", ResourceLoader.CACHE_MODE_IGNORE) as WorldData
	if saved == null:
		errors.append("could not reload staged world: %s" % path)
		return false
	var report: Dictionary = WORLD_VALIDATION.validate_world_report(saved)
	for error: String in report.get("errors", []):
		errors.append("reloaded world: %s" % error)
	for room_id: String in saved.get_room_ids():
		_validate_room_artifacts(saved.get_room(room_id), errors)
	if _world_signature(saved) != expected_signature:
		errors.append("reloaded world differs from staged WorldData")
	return errors.is_empty()


func _restore_world_backup(final_path: String, backup_path: String, staged_path: String, had_previous: bool, errors: Array[String]) -> void:
	if FileAccess.file_exists(final_path) and _remove_file(final_path) != OK:
		errors.append("could not remove failed world output: %s" % final_path)
	if had_previous:
		if not FileAccess.file_exists(backup_path):
			errors.append("world backup is missing: %s" % backup_path)
		elif FileAccess.file_exists(final_path) or _move_file(backup_path, final_path) != OK:
			errors.append("could not restore world backup: %s" % final_path)
	if FileAccess.file_exists(staged_path) and _remove_file(staged_path) != OK:
		errors.append("could not remove staged world after rollback: %s" % staged_path)


func _world_signature(world: WorldData) -> Dictionary:
	var rooms: Array[Dictionary] = []
	for room: Resource in world.rooms:
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


func _marked_path(path: String, marker: String) -> String:
	var extension_start := path.rfind(".")
	return "%s%s%s" % [path.left(extension_start), marker, path.substr(extension_start)]


func _move_file(from_path: String, to_path: String) -> Error:
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(from_path), ProjectSettings.globalize_path(to_path))


func _promote_staged_file(staged_path: String, final_path: String) -> Error:
	return _move_file(staged_path, final_path)


func _remove_file(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _after_staged_world_saved(_staged_path: String, _world: WorldData) -> Dictionary:
	return _result(true, [], [])


func _validate_room_artifacts(room: Resource, errors: Array[String]) -> void:
	if not _is_room_data(room):
		return
	var source_scene := _load_packed_scene(room.source_scene_path)
	if source_scene == null:
		errors.append("room %s source_scene_path is not a PackedScene: %s" % [room.room_id, room.source_scene_path])
	else:
		var source_root := source_scene.instantiate()
		var source_report: Dictionary = ROOM_AUTHORING_CONTRACT.validate(source_root)
		for error: String in source_report.get("errors", []):
			errors.append("room %s source scene: %s" % [room.room_id, error])
		source_root.free()

	var runtime_scene := _load_packed_scene(room.scene_path)
	if runtime_scene == null:
		errors.append("room %s scene_path is not a PackedScene: %s" % [room.room_id, room.scene_path])
	else:
		var runtime_root := runtime_scene.instantiate()
		if _contains_named_node(runtime_root, "PreviewOnly"):
			errors.append("room %s runtime content contains PreviewOnly" % room.room_id)
		for terrain_name: String in ["Background", "Terrain"] + TERRAIN_LAYER_NAMES:
			if _contains_named_node(runtime_root, terrain_name):
				errors.append("room %s runtime content contains terrain node: %s" % [room.room_id, terrain_name])
		for child_name: String in ["Entities", "Foreground"]:
			if runtime_root.get_node_or_null(child_name) == null:
				errors.append("room %s runtime content missing node: %s" % [room.room_id, child_name])
		runtime_root.free()

	var terrain_scene := _load_packed_scene(room.terrain_scene_path)
	if terrain_scene == null:
		errors.append("room %s terrain_scene_path is not a PackedScene: %s" % [room.room_id, room.terrain_scene_path])
	else:
		var terrain_root := terrain_scene.instantiate()
		if not terrain_root is Node2D:
			errors.append("room %s terrain content root must be Node2D" % room.room_id)
		if terrain_root.get_node_or_null("Background") == null:
			errors.append("room %s terrain content missing node: Background" % room.room_id)
		var terrain := terrain_root.get_node_or_null("Terrain")
		if terrain == null:
			errors.append("room %s terrain content missing node: Terrain" % room.room_id)
		else:
			for layer_name: String in TERRAIN_LAYER_NAMES:
				if not terrain.get_node_or_null(layer_name) is TileMapLayer:
					errors.append("room %s terrain content missing TileMapLayer: %s" % [room.room_id, layer_name])
		terrain_root.free()


func _load_packed_scene(path: String) -> PackedScene:
	if path.is_empty() or not ResourceLoader.exists(path, "PackedScene"):
		return null
	return ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene


func _contains_named_node(node: Node, node_name: String) -> bool:
	if node.name == node_name:
		return true
	for child: Node in node.get_children():
		if _contains_named_node(child, node_name):
			return true
	return false


func _copy_strings(values: Variant) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		result.append(str(value))
	result.sort()
	return result


func _failure(message: String) -> Dictionary:
	return _result(false, [message], [])


func _result(ok: bool, errors: Array[String], warnings: Array[String]) -> Dictionary:
	errors.sort()
	warnings.sort()
	return {"ok": ok, "errors": errors, "warnings": warnings}


static func _is_world_data(resource: Resource) -> bool:
	return resource != null and resource.get_script() == WORLD_DATA_SCRIPT


static func _is_room_data(resource: Resource) -> bool:
	return resource != null and resource.get_script() == ROOM_DATA_SCRIPT
