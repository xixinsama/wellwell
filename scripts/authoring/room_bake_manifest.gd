@tool
class_name RoomBakeManifest
extends RefCounted

const ROOM_BAKE_PATHS: Script = preload("res://scripts/authoring/room_bake_paths.gd")


static func from_authoring_root(source_root: Node, source_path: String) -> Dictionary:
	if source_root == null or source_path.strip_edges().is_empty():
		return {}
	var raw_manifest: Dictionary = {}
	if source_root.has_method("get_manifest"):
		raw_manifest = source_root.get_manifest()
	var paths: Dictionary = ROOM_BAKE_PATHS.for_room_id(str(raw_manifest.get("room_id", source_root.get("room_id"))))
	if paths.is_empty():
		return {}
	var output_paths := [
		str(paths.get("runtime_scene_path", "")),
		str(paths.get("terrain_scene_path", "")),
		str(paths.get("room_resource_path", "")),
	]
	if _has_duplicate_strings(output_paths):
		return {}
	var manifest: Dictionary = {
		"room_id": paths["room_id"],
		"display_name": str(raw_manifest.get("display_name", "")),
		"room_size_chunks": raw_manifest.get("room_size_chunks", Vector2i.ONE),
		"preview_spawn_id": str(raw_manifest.get("preview_spawn_id", "")),
		"map_color": raw_manifest.get("map_color", Color.WHITE),
		"tags": _sorted_unique_strings(raw_manifest.get("tags", PackedStringArray())),
		"source_scene_path": source_path,
		"entrance_ids": _sorted_unique_strings(raw_manifest.get("entrance_ids", [])),
		"spawn_ids": _sorted_unique_strings(raw_manifest.get("spawn_ids", [])),
		"entity_ids": _sorted_unique_strings(raw_manifest.get("entity_ids", raw_manifest.get("persistent_entity_ids", []))),
	}
	manifest.merge(paths)
	return manifest


static func apply_to_room_data(manifest: Dictionary, room_data: Resource) -> bool:
	if room_data == null or manifest.is_empty():
		return false
	var required_keys := [
		"room_id", "display_name", "room_size_chunks", "preview_spawn_id", "map_color",
		"tags", "source_scene_path", "runtime_scene_path", "terrain_scene_path", "room_resource_path",
	]
	for key: String in required_keys:
		if not manifest.has(key):
			return false
	var paths: Dictionary = ROOM_BAKE_PATHS.for_room_id(str(manifest.get("room_id", "")))
	if paths.is_empty() or str(manifest.get("source_scene_path", "")).strip_edges().is_empty():
		return false
	if manifest.get("runtime_scene_path") != paths["runtime_scene_path"] or manifest.get("terrain_scene_path") != paths["terrain_scene_path"] or manifest.get("room_resource_path") != paths["room_resource_path"]:
		return false
	room_data.room_id = str(manifest["room_id"])
	room_data.display_name = str(manifest["display_name"])
	room_data.scene_path = str(manifest["runtime_scene_path"])
	room_data.room_size_chunks = manifest["room_size_chunks"] as Vector2i
	room_data.map_color = manifest["map_color"] as Color
	room_data.source_scene_path = str(manifest["source_scene_path"])
	room_data.terrain_scene_path = str(manifest["terrain_scene_path"])
	room_data.tags = PackedStringArray(_sorted_unique_strings(manifest.get("tags", [])))
	room_data.entrance_ids = PackedStringArray(_sorted_unique_strings(manifest.get("entrance_ids", [])))
	room_data.spawn_ids = PackedStringArray(_sorted_unique_strings(manifest.get("spawn_ids", [])))
	room_data.entity_ids = PackedStringArray(_sorted_unique_strings(manifest.get("entity_ids", [])))
	return true


static func _sorted_unique_strings(values: Variant) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		var text := str(value)
		if not text.is_empty() and not result.has(text):
			result.append(text)
	result.sort()
	return result


static func _has_duplicate_strings(values: Array) -> bool:
	var seen: Dictionary = {}
	for value: String in values:
		if seen.has(value):
			return true
		seen[value] = true
	return false
