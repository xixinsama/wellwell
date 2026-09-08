@tool
class_name WorldBaker
extends RefCounted

const WORLD_DATA_SCRIPT: Script = preload("res://addons/platformer_kit/world/data/world_data.gd")
const ROOM_DATA_SCRIPT: Script = preload("res://addons/platformer_kit/world/data/room_data.gd")
const WORLD_VALIDATION: Script = preload("res://addons/platformer_kit/world/data/world_validation.gd")
const WORLD_RESOURCE_SERVICE: Script = preload("res://scripts/authoring/world/world_resource_service.gd")
const ROOM_AUTHORING_CONTRACT: Script = preload("res://scripts/authoring/room/room_authoring_contract.gd")
const TERRAIN_LAYER_NAMES: Array[String] = [
	"BackTiles", "SolidTiles", "GlassTiles", "VisionBlockTiles", "DetailTiles", "MarkerTiles"
]

var _world_resources: Object = WORLD_RESOURCE_SERVICE.new()


func _init() -> void:
	if _world_resources.has_method("set_allow_user_paths"):
		_world_resources.call("set_allow_user_paths", true)


func set_world_resources_adapter(value: Object) -> void:
	_world_resources = value
	if _world_resources != null and _world_resources.has_method("set_allow_user_paths"):
		_world_resources.call("set_allow_user_paths", true)


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
	var result: Dictionary = _world_resources.call("save_candidate", world, world.resource_path)
	var service_warnings := _copy_strings(result.get("warnings", []))
	warnings.append_array(service_warnings)
	result["warnings"] = _copy_strings(warnings)
	return result


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
	var source_fingerprint := FileAccess.get_sha256(room.source_scene_path)
	if source_fingerprint.is_empty():
		errors.append("room %s source_scene_path could not be fingerprinted" % room.room_id)
	elif room.source_fingerprint != source_fingerprint:
		errors.append("room %s generated output is stale; Bake Room before Bake World" % room.room_id)

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
