class_name RoomRuntime
extends Node2D

const ROOM_DATA_SCRIPT: Script = preload("res://scripts/world/room_data.gd")
const SPAWN_POINT_SCRIPT: Script = preload("res://scripts/world/spawn_point.gd")

signal transition_requested(entrance: Node)

var _room_data: Resource
var _room_instance: Node
var _world_id := ""
var _entity_state_source: Object


func setup_room(room_data: Resource, world_id: String = "", entity_state_source: Object = null) -> bool:
	_clear_room_instance()
	_room_data = null
	_world_id = ""
	_entity_state_source = entity_state_source
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
	_world_id = world_id
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
		var child_entity_id: Variant = child.get("entity_id")
		if child_entity_id != null and str(child_entity_id) == entity_id:
			return child
	return null


func get_spawn_point(spawn_id: String) -> Node2D:
	if _room_instance == null or spawn_id.is_empty():
		return null
	return _find_spawn_point(_room_instance, spawn_id)


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
		_setup_entity_tree(child)


func _setup_entity_tree(entity: Node) -> void:
	if entity.has_method("setup_entity"):
		entity.call("setup_entity", {"world_id": _world_id, "room_id": get_room_id()})
		if bool(entity.get("persistent")) and entity.has_method("get_save_key"):
			var state_source := _get_entity_state_source()
			if state_source != null and state_source.has_method("get_entity_state"):
				var state: Dictionary = state_source.call("get_entity_state", entity.call("get_save_key"))
				if not state.is_empty() and entity.has_method("apply_save_state"):
					entity.call("apply_save_state", state)
	if entity.has_signal("transition_requested") and entity.has_method("request_transition"):
		var callback := Callable(self, "_on_transition_requested")
		if not entity.is_connected("transition_requested", callback):
			entity.connect("transition_requested", callback)
	for child: Node in entity.get_children():
		_setup_entity_tree(child)


func _find_spawn_point(node: Node, spawn_id: String) -> Node2D:
	if _is_spawn_point_node(node) and String(node.get("spawn_id")) == spawn_id:
		return node as Node2D
	for child: Node in node.get_children():
		var found := _find_spawn_point(child, spawn_id)
		if found != null:
			return found
	return null


func _is_spawn_point_node(node: Node) -> bool:
	var script := node.get_script() as Script
	while script != null:
		if script == SPAWN_POINT_SCRIPT:
			return true
		script = script.get_base_script()
	return false


func _on_transition_requested(entrance: Node) -> void:
	transition_requested.emit(entrance)


func _get_entity_state_source() -> Object:
	if is_instance_valid(_entity_state_source):
		return _entity_state_source
	if is_inside_tree():
		return get_tree().root.get_node_or_null("SaveManager")
	return null


static func _is_room_data(resource: Resource) -> bool:
	return resource != null and resource.get_script() == ROOM_DATA_SCRIPT
