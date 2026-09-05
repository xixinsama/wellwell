class_name RoomRuntime
extends Node2D

const ROOM_DATA_SCRIPT: Script = preload("res://scripts/world/room_data.gd")

var _room_data: Resource
var _room_instance: Node


func setup_room(room_data: Resource) -> bool:
	_clear_room_instance()
	_room_data = null
	if not _is_room_data(room_data) or room_data.scene_path.is_empty():
		return false
	if not ResourceLoader.exists(room_data.scene_path, "PackedScene"):
		return false

	var packed: PackedScene = load(room_data.scene_path) as PackedScene
	if packed == null:
		return false

	_room_instance = packed.instantiate()
	if _room_instance == null:
		return false

	_room_data = room_data
	name = room_data.room_id
	position = Vector2(room_data.get_pixel_rect().position)
	add_child(_room_instance)
	_setup_entities()
	return true


func get_room_id() -> String:
	return "" if _room_data == null else _room_data.room_id


func get_room_data() -> Resource:
	return _room_data


func get_room_instance() -> Node:
	return _room_instance


func get_room_chunk_rect() -> Rect2i:
	return Rect2i() if _room_data == null else _room_data.get_chunk_rect()


func get_room_cell_rect() -> Rect2i:
	return Rect2i() if _room_data == null else _room_data.get_cell_rect()


func get_layer_node(layer_name: String) -> Node:
	if _room_instance == null:
		return null
	return _room_instance.get_node_or_null(layer_name)


func get_entities_root() -> Node:
	return get_layer_node("Entities")


func get_entity(entity_id: String) -> Node:
	var root := get_entities_root()
	if root == null:
		return null
	for child: Node in root.get_children():
		if String(child.get("entity_id")) == entity_id:
			return child
	return null


func get_map_markers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var root := get_entities_root()
	if root == null:
		return result
	for child: Node in root.get_children():
		if child.has_method("get_map_marker"):
			var marker: Dictionary = child.call("get_map_marker")
			if not marker.is_empty():
				result.append(marker)
	return result


func _clear_room_instance() -> void:
	if _room_instance != null:
		_room_instance.free()
		_room_instance = null


func _setup_entities() -> void:
	var root := get_entities_root()
	if root == null:
		return
	for child: Node in root.get_children():
		if not child.has_method("setup_entity"):
			continue
		child.call("setup_entity", {"room_id": get_room_id()})
		if child.get("persistent") and child.has_method("get_save_key"):
			var manager := get_tree().root.get_node_or_null("SaveManager")
			if manager != null and manager.has_method("get_entity_state"):
				var state: Dictionary = manager.call("get_entity_state", child.call("get_save_key"))
				if not state.is_empty() and child.has_method("apply_save_state"):
					child.call("apply_save_state", state)


static func _is_room_data(resource: Resource) -> bool:
	return resource != null and resource.get_script() == ROOM_DATA_SCRIPT
