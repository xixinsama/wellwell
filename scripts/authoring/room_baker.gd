@tool
class_name RoomBaker
extends RefCounted

const ROOM_AUTHORING_CONTRACT: Script = preload("res://scripts/authoring/room_authoring_contract.gd")
const ROOM_BAKE_MANIFEST: Script = preload("res://scripts/authoring/room_bake_manifest.gd")
const ROOM_BAKE_PATHS: Script = preload("res://scripts/authoring/room_bake_paths.gd")
const ROOM_DATA: Script = preload("res://scripts/world/room_data.gd")

const DUPLICATE_FLAGS := Node.DUPLICATE_SIGNALS | Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS | Node.DUPLICATE_USE_INSTANTIATION
const TERRAIN_CHILD_NAMES: Array[String] = ["Background", "Terrain"]
const RUNTIME_EXCLUDED_CHILD_NAMES: Array[String] = ["Background", "Terrain"]
const REQUIRED_RUNTIME_CHILD_NAMES: Array[String] = ["Entities", "Foreground"]
const REQUIRED_TERRAIN_LAYER_NAMES: Array[String] = ["BackTiles", "SolidTiles", "GlassTiles", "VisionBlockTiles", "DetailTiles", "MarkerTiles"]
const RESOURCE_PRESENTATION_PROPERTIES: Array[String] = ["resource_path", "resource_scene_unique_id"]


func validate(source_root: Node) -> Dictionary:
	var contract: Dictionary = ROOM_AUTHORING_CONTRACT.validate(source_root)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	for error: String in contract.get("errors", []):
		errors.append(error)
	for warning: String in contract.get("warnings", []):
		warnings.append(warning)
	return _result(errors.is_empty(), errors, warnings)


func stage(source_root: Node, source_path: String) -> Dictionary:
	var validation := validate(source_root)
	if not validation["ok"]:
		return validation
	var warnings := _copy_strings(validation["warnings"])
	var manifest: Dictionary = ROOM_BAKE_MANIFEST.from_authoring_root(source_root, source_path)
	if manifest.is_empty():
		return _failure("could not build a normalized room bake manifest", warnings)
	var room_content: Node = source_root.get_node_or_null("RoomContent")
	if room_content == null:
		return _failure("missing direct RoomContent node during staging", warnings)
	var terrain_scene_result := _pack_terrain_scene(room_content)
	if not terrain_scene_result["ok"]:
		return _with_warnings(terrain_scene_result, warnings)
	var runtime_scene_result := _pack_runtime_scene(room_content)
	if not runtime_scene_result["ok"]:
		return _with_warnings(runtime_scene_result, warnings)
	var room_data: Resource = ROOM_DATA.new()
	if not ROOM_BAKE_MANIFEST.apply_to_room_data(manifest, room_data):
		return _failure("could not apply room bake manifest to RoomData", warnings)
	return {
		"ok": true,
		"errors": [],
		"warnings": warnings,
		"manifest": manifest,
		"outputs": _output_paths(manifest),
		"runtime_scene": runtime_scene_result["scene"],
		"terrain_scene": terrain_scene_result["scene"],
		"runtime_signature": _scene_signature(runtime_scene_result["scene"]),
		"terrain_signature": _scene_signature(terrain_scene_result["scene"]),
		"room_data": room_data,
	}


func save_staged(staged: Dictionary) -> Dictionary:
	var staged_validation := _validate_staged(staged)
	if not staged_validation["ok"]:
		return staged_validation
	var outputs: Dictionary = staged["outputs"]
	var errors: Array[String] = []
	var warnings := _copy_strings(staged["warnings"])
	if not _ensure_output_directories(outputs, errors):
		return _result(false, errors, warnings)
	var staged_paths := _staged_paths(outputs)
	if not _remove_paths(staged_paths, errors, "stale staged output"):
		return _result(false, errors, warnings)
	var resources := {
		staged_paths["runtime_scene_path"]: staged["runtime_scene"],
		staged_paths["terrain_scene_path"]: staged["terrain_scene"],
		staged_paths["room_resource_path"]: staged["room_data"],
	}
	for staged_path: String in resources:
		var save_error := ResourceSaver.save(resources[staged_path], staged_path)
		if save_error != OK:
			errors.append("could not save staged resource: %s" % staged_path)
			_remove_paths(staged_paths, errors, "staged resource")
			return _result(false, errors, warnings)
	var post_save_result := _after_staged_resources_saved(staged_paths, staged)
	if not post_save_result.get("ok", false):
		for error: String in post_save_result.get("errors", []):
			errors.append(error)
		for warning: String in post_save_result.get("warnings", []):
			warnings.append(warning)
		_remove_paths(staged_paths, errors, "staged resource")
		return _result(false, errors, warnings)
	for warning: String in post_save_result.get("warnings", []):
		warnings.append(warning)
	if not _validate_saved_resources(staged_paths, staged, errors):
		_remove_paths(staged_paths, errors, "staged resource")
		return _result(false, errors, warnings)
	return _replace_transactionally(outputs, staged_paths, warnings)


func bake(source_root: Node, source_path: String) -> Dictionary:
	var staged := stage(source_root, source_path)
	if not staged["ok"]:
		return staged
	return save_staged(staged)


func _pack_terrain_scene(room_content: Node) -> Dictionary:
	return _pack_scene(room_content, "RoomTerrain", TERRAIN_CHILD_NAMES)


func _pack_runtime_scene(room_content: Node) -> Dictionary:
	var child_names: Array[String] = []
	for child: Node in room_content.get_children():
		var child_name := str(child.name)
		if not RUNTIME_EXCLUDED_CHILD_NAMES.has(child_name):
			child_names.append(child_name)
	return _pack_scene(room_content, "RoomRuntimeContent", child_names)


func _pack_scene(room_content: Node, root_name: String, child_names: Array[String]) -> Dictionary:
	var root := Node2D.new()
	root.name = root_name
	for child_name: String in child_names:
		var source_child: Node = room_content.get_node_or_null(child_name)
		if source_child == null:
			root.free()
			return _failure("missing RoomContent child during staging: %s" % child_name)
		var duplicate: Node = source_child.duplicate(DUPLICATE_FLAGS)
		if duplicate == null:
			root.free()
			return _failure("could not duplicate RoomContent child: %s" % child_name)
		root.add_child(duplicate)
		_assign_owner_recursive(duplicate, root)
	var scene := PackedScene.new()
	var pack_error := scene.pack(root)
	root.free()
	if pack_error != OK:
		return _failure("could not pack staged scene: %s" % root_name)
	return {
		"ok": true,
		"errors": [],
		"warnings": [],
		"scene": scene,
	}


func _assign_owner_recursive(node: Node, scene_root: Node) -> void:
	node.owner = scene_root
	for group_name: StringName in node.get_groups():
		node.add_to_group(group_name, true)
	for child: Node in node.get_children():
		_assign_owner_recursive(child, scene_root)


func _validate_staged(staged: Dictionary) -> Dictionary:
	for key: String in ["manifest", "outputs", "runtime_scene", "terrain_scene", "runtime_signature", "terrain_signature", "room_data", "warnings"]:
		if not staged.has(key):
			return _failure("staged bake is missing: %s" % key)
	if not staged["runtime_scene"] is PackedScene or not staged["terrain_scene"] is PackedScene or not staged["room_data"] is Resource:
		return _failure("staged bake resources have invalid types")
	if not staged["runtime_signature"] is Dictionary or not staged["terrain_signature"] is Dictionary or not staged["warnings"] is Array:
		return _failure("staged bake validation data has invalid types")
	var manifest: Dictionary = staged["manifest"]
	var outputs: Dictionary = staged["outputs"]
	var errors: Array[String] = []
	var warnings := _copy_strings(staged["warnings"])
	var expected_outputs := _output_paths(manifest)
	if expected_outputs.is_empty() or outputs != expected_outputs:
		errors.append("staged bake outputs do not match deterministic room paths")
	if not _validate_runtime_scene(staged["runtime_scene"], staged["runtime_signature"], errors):
		pass
	if not _validate_terrain_scene(staged["terrain_scene"], staged["terrain_signature"], errors):
		pass
	_validate_room_data_against_manifest(staged["room_data"], manifest, outputs, errors)
	return _result(errors.is_empty(), errors, warnings)


func _ensure_output_directories(outputs: Dictionary, errors: Array[String]) -> bool:
	var directories: Dictionary = {}
	for output_path: String in outputs.values():
		directories[output_path.get_base_dir()] = true
	for directory: String in directories:
		if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) != OK:
			errors.append("could not create generated output directory: %s" % directory)
	return errors.is_empty()


func _validate_saved_resources(staged_paths: Dictionary, staged: Dictionary, errors: Array[String]) -> bool:
	var runtime_scene := ResourceLoader.load(staged_paths["runtime_scene_path"], "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var terrain_scene := ResourceLoader.load(staged_paths["terrain_scene_path"], "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var room_data := ResourceLoader.load(staged_paths["room_resource_path"], "RoomData", ResourceLoader.CACHE_MODE_IGNORE) as Resource
	if runtime_scene == null or terrain_scene == null or room_data == null:
		errors.append("could not reload every staged resource")
		return false
	var valid := true
	if not _validate_runtime_scene(runtime_scene, staged["runtime_signature"], errors):
		valid = false
	if not _validate_terrain_scene(terrain_scene, staged["terrain_signature"], errors):
		valid = false
	var staged_room_data: Resource = staged["room_data"]
	if not _room_data_matches(room_data, staged_room_data, errors):
		valid = false
	if not _validate_room_data_against_manifest(room_data, staged["manifest"], staged["outputs"], errors):
		valid = false
	return valid


func _validate_runtime_scene(scene: PackedScene, expected_signature: Dictionary, errors: Array[String]) -> bool:
	var root: Node = scene.instantiate()
	var valid := root.name == "RoomRuntimeContent"
	if not valid:
		errors.append("staged runtime scene root mismatch")
	for child_name: String in REQUIRED_RUNTIME_CHILD_NAMES:
		if root.get_node_or_null(child_name) == null:
			valid = false
			errors.append("staged runtime scene missing required child: %s" % child_name)
	for excluded_name: String in ["Background", "Terrain", "PreviewOnly"]:
		if _contains_named_node(root, excluded_name):
			valid = false
			errors.append("staged runtime scene contains excluded child: %s" % excluded_name)
	root.free()
	if _scene_signature(scene) != expected_signature:
		valid = false
		errors.append("staged runtime scene signature differs from the in-memory staged scene")
	return valid


func _validate_terrain_scene(scene: PackedScene, expected_signature: Dictionary, errors: Array[String]) -> bool:
	var root: Node = scene.instantiate()
	var valid := root.name == "RoomTerrain"
	if not valid:
		errors.append("staged terrain scene root mismatch")
	for child_name: String in TERRAIN_CHILD_NAMES:
		if root.get_node_or_null(child_name) == null:
			valid = false
			errors.append("staged terrain scene missing required child: %s" % child_name)
	if _contains_named_node(root, "PreviewOnly"):
		valid = false
		errors.append("staged terrain scene contains PreviewOnly")
	for layer_name: String in REQUIRED_TERRAIN_LAYER_NAMES:
		if not root.get_node_or_null("Terrain/%s" % layer_name) is TileMapLayer:
			valid = false
			errors.append("staged terrain scene missing TileMapLayer: %s" % layer_name)
	root.free()
	if _scene_signature(scene) != expected_signature:
		valid = false
		errors.append("staged terrain scene signature differs from the in-memory staged scene")
	return valid


func _validate_room_data_against_manifest(room_data: Resource, manifest: Dictionary, outputs: Dictionary, errors: Array[String]) -> bool:
	var expected_values := {
		"room_id": manifest.get("room_id", ""),
		"display_name": manifest.get("display_name", ""),
		"scene_path": outputs.get("runtime_scene_path", ""),
		"source_scene_path": manifest.get("source_scene_path", ""),
		"terrain_scene_path": outputs.get("terrain_scene_path", ""),
		"room_size_chunks": manifest.get("room_size_chunks", Vector2i.ONE),
		"entrance_ids": PackedStringArray(manifest.get("entrance_ids", [])),
		"spawn_ids": PackedStringArray(manifest.get("spawn_ids", [])),
		"entity_ids": PackedStringArray(manifest.get("entity_ids", [])),
		"tags": PackedStringArray(manifest.get("tags", [])),
		"map_color": manifest.get("map_color", Color.WHITE),
	}
	var valid := true
	for property_name: String in expected_values:
		if room_data.get(property_name) != expected_values[property_name]:
			valid = false
			errors.append("staged RoomData metadata mismatch: %s" % property_name)
	return valid


func _room_data_matches(actual: Resource, expected: Resource, errors: Array[String]) -> bool:
	var valid := true
	for property_name: String in ["room_id", "display_name", "scene_path", "source_scene_path", "terrain_scene_path", "entrance_ids", "spawn_ids", "entity_ids", "tags", "room_origin_chunk", "room_size_chunks", "adjacent_room_ids", "map_color"]:
		if actual.get(property_name) != expected.get(property_name):
			valid = false
			errors.append("reloaded RoomData differs from staged RoomData: %s" % property_name)
	return valid


func _contains_named_node(root: Node, node_name: String) -> bool:
	for child: Node in root.get_children():
		if str(child.name) == node_name or _contains_named_node(child, node_name):
			return true
	return false


func _scene_signature(scene: PackedScene) -> Dictionary:
	var state := scene.get_state()
	var root: Node = scene.instantiate()
	var nodes: Array[Dictionary] = []
	for node_index: int in state.get_node_count():
		var node_path := state.get_node_path(node_index)
		var path_text := str(node_path)
		var node: Node = root if path_text.is_empty() or path_text == "." else root.get_node_or_null(node_path)
		var properties: Array[Dictionary] = []
		for property_index: int in state.get_node_property_count(node_index):
			properties.append({
				"name": str(state.get_node_property_name(node_index, property_index)),
				"value": _canonicalize_value(state.get_node_property_value(node_index, property_index)),
			})
		var groups: Array[String] = []
		for group_name: StringName in state.get_node_groups(node_index):
			groups.append(str(group_name))
		groups.sort()
		var script_path := ""
		if node != null:
			var script: Script = node.get_script()
			if script != null:
				script_path = script.resource_path
		nodes.append({
			"path": path_text,
			"type": state.get_node_type(node_index),
			"script_path": script_path,
			"owner_path": str(state.get_node_owner_path(node_index)),
			"groups": groups,
			"properties": properties,
		})
	root.free()
	return {"nodes": nodes}


func _canonicalize_value(value: Variant) -> Variant:
	return _canonicalize_value_with_resources(value, {})


func _canonicalize_value_with_resources(value: Variant, active_resources: Dictionary) -> Variant:
	match typeof(value):
		TYPE_ARRAY:
			var values: Array = []
			for item: Variant in value:
				values.append(_canonicalize_value_with_resources(item, active_resources))
			return values
		TYPE_DICTIONARY:
			var entries: Array[Dictionary] = []
			for key: Variant in value.keys():
				entries.append({
					"key": _canonicalize_value_with_resources(key, active_resources),
					"value": _canonicalize_value_with_resources(value[key], active_resources),
				})
			entries.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
				return _stable_canonical_key(left["key"]) < _stable_canonical_key(right["key"])
			)
			return entries
		TYPE_OBJECT:
			return _canonicalize_object(value, active_resources)
		TYPE_STRING_NAME:
			return {"variant_type": "StringName", "value": str(value)}
		TYPE_NODE_PATH:
			return {"variant_type": "NodePath", "value": str(value)}
		_:
			return value


func _canonicalize_object(value: Variant, active_resources: Dictionary) -> Variant:
	if value == null:
		return null
	if value is Resource:
		var resource := value as Resource
		if not resource.resource_path.is_empty() and not resource.is_built_in():
			return {"external_resource_path": resource.resource_path}
		var resource_id := resource.get_instance_id()
		if active_resources.has(resource_id):
			return {"embedded_resource_cycle": active_resources[resource_id]}
		var resource_marker := "embedded_%d" % active_resources.size()
		active_resources[resource_id] = resource_marker
		var properties: Array[Dictionary] = []
		for property_info: Dictionary in resource.get_property_list():
			if (int(property_info.get("usage", 0)) & PROPERTY_USAGE_STORAGE) != 0:
				var property_name := str(property_info.get("name", ""))
				if RESOURCE_PRESENTATION_PROPERTIES.has(property_name):
					continue
				properties.append({"name": property_name, "value": _canonicalize_value_with_resources(resource.get(property_name), active_resources)})
		properties.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			return left["name"] < right["name"]
		)
		active_resources.erase(resource_id)
		return {"embedded_resource_class": resource.get_class(), "properties": properties}
	if value is Node:
		return {"node_class": value.get_class(), "node_name": str(value.name)}
	return {"object_class": value.get_class()}


func _stable_canonical_key(value: Variant) -> String:
	return "%d:%s" % [typeof(value), var_to_str(value)]


func _after_staged_resources_saved(_staged_paths: Dictionary, _staged: Dictionary) -> Dictionary:
	return _result(true, [], [])


func _replace_transactionally(outputs: Dictionary, staged_paths: Dictionary, warnings: Array[String]) -> Dictionary:
	var backup_paths := _backup_paths(outputs)
	var errors: Array[String] = []
	for backup_path: String in backup_paths.values():
		if FileAccess.file_exists(backup_path):
			errors.append("refusing to remove existing generated output backup: %s" % backup_path)
	if not errors.is_empty():
		_remove_paths(staged_paths, errors, "staged resource")
		return _result(false, errors, warnings)
	var backed_up: Array[Dictionary] = []
	for final_path: String in outputs.values():
		if FileAccess.file_exists(final_path):
			var backup_path: String = backup_paths[_output_key_for_path(outputs, final_path)]
			if _move_file(final_path, backup_path) != OK:
				errors.append("could not back up generated output: %s" % final_path)
				_restore_backups(backed_up, errors)
				_remove_paths(staged_paths, errors, "staged resource")
				return _result(false, errors, warnings)
			backed_up.append({"final_path": final_path, "backup_path": backup_path})
	var installed_paths: Array[String] = []
	for output_key: String in ["runtime_scene_path", "terrain_scene_path", "room_resource_path"]:
		var promote_error := _promote_staged_file(staged_paths[output_key], outputs[output_key])
		if promote_error != OK:
			errors.append("could not install generated output: %s" % outputs[output_key])
			_rollback_replacement(installed_paths, backed_up, staged_paths, errors)
			return _result(false, errors, warnings)
		installed_paths.append(outputs[output_key])
	var committed_warnings := _copy_strings(warnings)
	for backup_path: String in backup_paths.values():
		if _remove_file(backup_path) != OK:
			committed_warnings.append("retained generated output backup: %s" % backup_path)
	for staged_path: String in staged_paths.values():
		if _remove_file(staged_path) != OK:
			committed_warnings.append("retained staged resource after committed transaction: %s" % staged_path)
	return {
		"ok": true,
		"errors": [],
		"warnings": committed_warnings,
		"outputs": outputs.duplicate(),
	}


func _rollback_replacement(installed_paths: Array[String], backed_up: Array[Dictionary], staged_paths: Dictionary, errors: Array[String]) -> void:
	var installed_outputs_removed := true
	for installed_path: String in installed_paths:
		var removal_error := _remove_file(installed_path)
		if removal_error != OK:
			installed_outputs_removed = false
			errors.append("could not remove newly installed output: %s" % installed_path)
		elif FileAccess.file_exists(installed_path):
			installed_outputs_removed = false
			errors.append("newly installed output still exists after removal: %s" % installed_path)
	if installed_outputs_removed:
		_restore_backups(backed_up, errors)
	else:
		errors.append("generated output backups were retained because installed outputs remain")
	_remove_paths(staged_paths, errors, "staged resource")


func _restore_backups(backed_up: Array[Dictionary], errors: Array[String]) -> void:
	for entry: Dictionary in backed_up:
		if not FileAccess.file_exists(entry["backup_path"]):
			errors.append("generated output backup is missing: %s" % entry["backup_path"])
		elif FileAccess.file_exists(entry["final_path"]):
			errors.append("could not restore generated output backup while final exists: %s" % entry["final_path"])
		elif _move_file(entry["backup_path"], entry["final_path"]) != OK:
			errors.append("could not restore generated output backup: %s" % entry["final_path"])
		elif FileAccess.file_exists(entry["backup_path"]) or not FileAccess.file_exists(entry["final_path"]):
			errors.append("generated output backup restoration could not be verified: %s" % entry["final_path"])


func _move_file(from_path: String, to_path: String) -> Error:
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(from_path), ProjectSettings.globalize_path(to_path))


func _promote_staged_file(staged_path: String, final_path: String) -> Error:
	var uid := ResourceLoader.get_resource_uid(staged_path)
	var move_error := _move_file(staged_path, final_path)
	if move_error == OK and uid != ResourceUID.INVALID_ID and ResourceUID.has_id(uid):
		ResourceUID.set_id(uid, final_path)
	return move_error


func _remove_paths(paths: Variant, errors: Array[String], label: String) -> bool:
	var valid := true
	if paths is Dictionary:
		for path: String in (paths as Dictionary).values():
			if _remove_file(path) != OK:
				valid = false
				errors.append("could not remove %s: %s" % [label, path])
	elif paths is Array:
		for path: String in paths:
			if _remove_file(path) != OK:
				valid = false
				errors.append("could not remove %s: %s" % [label, path])
	return valid


func _remove_file(path: String) -> Error:
	var uid := _registered_uid_for_path(path)
	if not FileAccess.file_exists(path):
		_forget_uid_path(uid, path)
		return OK
	var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if remove_error == OK:
		_forget_uid_path(uid, path)
	return remove_error


func _forget_uid_path(uid: int, path: String) -> void:
	if uid != ResourceUID.INVALID_ID and ResourceUID.has_id(uid) and ResourceUID.get_id_path(uid) == path:
		ResourceUID.remove_id(uid)


func _registered_uid_for_path(path: String) -> int:
	var uid_text := ResourceUID.path_to_uid(path)
	if not uid_text.begins_with("uid://"):
		return ResourceUID.INVALID_ID
	return ResourceUID.text_to_id(uid_text)


func _output_paths(manifest: Dictionary) -> Dictionary:
	var paths: Dictionary = ROOM_BAKE_PATHS.for_room_id(str(manifest.get("room_id", "")))
	if paths.is_empty():
		return {}
	return {
		"runtime_scene_path": paths["runtime_scene_path"],
		"terrain_scene_path": paths["terrain_scene_path"],
		"room_resource_path": paths["room_resource_path"],
	}


func _staged_paths(outputs: Dictionary) -> Dictionary:
	return _marked_paths(outputs, ".stage")


func _backup_paths(outputs: Dictionary) -> Dictionary:
	return _marked_paths(outputs, ".backup")


func _marked_paths(outputs: Dictionary, marker: String) -> Dictionary:
	var result: Dictionary = {}
	for output_key: String in outputs:
		result[output_key] = _marked_path(outputs[output_key], marker)
	return result


func _marked_path(path: String, marker: String) -> String:
	var extension_start := path.rfind(".")
	return "%s%s%s" % [path.left(extension_start), marker, path.substr(extension_start)]


func _output_key_for_path(outputs: Dictionary, output_path: String) -> String:
	for output_key: String in outputs:
		if outputs[output_key] == output_path:
			return output_key
	return ""


func _result(ok: bool, errors: Array[String], warnings: Array[String]) -> Dictionary:
	return {"ok": ok, "errors": errors, "warnings": warnings}


func _failure(error: String, warnings: Array[String] = []) -> Dictionary:
	return _result(false, [error], warnings)


func _with_warnings(result: Dictionary, warnings: Array[String]) -> Dictionary:
	var combined_warnings := _copy_strings(result.get("warnings", []))
	combined_warnings.append_array(warnings)
	result["warnings"] = combined_warnings
	return result


func _copy_strings(values: Variant) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		result.append(str(value))
	return result
