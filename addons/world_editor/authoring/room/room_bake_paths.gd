@tool
class_name RoomBakePaths
extends RefCounted

const ROOM_RESOURCE_DIRECTORY := "res://resources/rooms/generated/"


static func sanitize_room_id(room_id: String) -> String:
	var value := room_id.strip_edges().to_lower()
	var result := ""
	var pending_separator := false
	for character: String in value:
		var code := character.unicode_at(0)
		if (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or character == "_":
			if pending_separator and not result.is_empty():
				result += "_"
			pending_separator = false
			result += character
		else:
			pending_separator = true
	while result.begins_with("_"):
		result = result.trim_prefix("_")
	while result.ends_with("_"):
		result = result.trim_suffix("_")
	return result


static func for_room_id(room_id: String) -> Dictionary:
	var sanitized := sanitize_room_id(room_id)
	if sanitized.is_empty():
		return {}
	return {
		"room_id": sanitized,
		"runtime_scene_path": "res://scenes/rooms/generated/%s/runtime.tscn" % sanitized,
		"terrain_scene_path": "res://scenes/rooms/generated/%s/terrain.tscn" % sanitized,
		"room_resource_path": "%s%s.tres" % [ROOM_RESOURCE_DIRECTORY, sanitized],
	}
