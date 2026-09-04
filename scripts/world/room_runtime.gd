class_name RoomRuntime
extends Node2D

var _room_data: Resource
var _room_instance: Node


func setup_room(room_data: Resource) -> bool:
	_clear_room_instance()
	_room_data = room_data
	if room_data == null or room_data.scene_path.is_empty():
		return false
	if not ResourceLoader.exists(room_data.scene_path, "PackedScene"):
		return false

	var packed: PackedScene = load(room_data.scene_path) as PackedScene
	if packed == null:
		return false

	_room_instance = packed.instantiate()
	if _room_instance == null:
		return false

	name = room_data.room_id
	position = Vector2(room_data.get_pixel_rect().position)
	add_child(_room_instance)
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


func _clear_room_instance() -> void:
	if _room_instance != null:
		_room_instance.free()
	_room_instance = null
