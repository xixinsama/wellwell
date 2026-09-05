class_name RoomPreviewController
extends Node

signal preview_ready()
signal transition_blocked(entrance: RoomEntrance)

const ROOM_AUTHORING_CONTRACT: Script = preload("res://scripts/authoring/room_authoring_contract.gd")
const SAVE_SNAPSHOT: Script = preload("res://scripts/save/save_snapshot.gd")

@export var authoring_root_path := NodePath("..")
@export var player_path := NodePath("../PreviewOnly/Player")
@export var camera_path := NodePath("../PreviewOnly/PixelCamera2D")
@export var fog_path := NodePath("../PreviewOnly/FogOfWar")
@export var debug_hud_path := NodePath("../PreviewOnly/DebugHud")

var _preview_snapshot: RefCounted


func _ready() -> void:
	setup_preview()


func setup_preview(authoring_root: Node = null) -> bool:
	var root := authoring_root
	if root == null:
		root = get_node_or_null(authoring_root_path)
	if root == null:
		return false
	var validation: Dictionary = ROOM_AUTHORING_CONTRACT.validate(root)
	if not (validation.get("errors", []) as Array).is_empty():
		return false

	var player := get_node_or_null(player_path) as Node2D
	var camera := get_node_or_null(camera_path)
	var fog := get_node_or_null(fog_path)
	var debug_hud := get_node_or_null(debug_hud_path)
	var room_content := root.get_node_or_null("RoomContent")
	var spawn := _find_spawn_point(room_content, String(root.get("preview_spawn_id")))
	if player == null or camera == null or fog == null or debug_hud == null or spawn == null:
		return false

	_ensure_preview_snapshot(String(root.get("room_id")), String(root.get("preview_spawn_id")), spawn.global_position)
	player.global_position = spawn.global_position
	_bind_target(camera, player)
	_bind_player(fog, player)
	_bind_player(debug_hud, player)
	if fog.has_method("bind_persistence_source"):
		fog.call("bind_persistence_source", self)
	if fog.has_method("set_room_chunks"):
		fog.call("set_room_chunks", Vector2i.ZERO, root.get("room_size_chunks"))
	if _has_property(fog, "level_id"):
		fog.set("level_id", String(root.get("room_id")))
	_connect_entrances(room_content)
	preview_ready.emit()
	return true


func get_preview_snapshot() -> RefCounted:
	return _preview_snapshot


func mark_cell_explored(cell_id: String) -> bool:
	return _preview_snapshot != null and _preview_snapshot.add_explored_cell(cell_id)


func mark_chunk_explored(chunk_id: String) -> bool:
	return _preview_snapshot != null and _preview_snapshot.add_explored_chunk(chunk_id)


func get_explored_cells() -> Array[String]:
	if _preview_snapshot == null:
		return []
	return _preview_snapshot.get_explored_cells()


func get_explored_chunks() -> Array[String]:
	if _preview_snapshot == null:
		return []
	return _preview_snapshot.get_explored_chunks()


func set_entity_state(entity_key: String, state: Dictionary) -> void:
	if _preview_snapshot != null:
		_preview_snapshot.set_entity_state(entity_key, state)


func get_entity_state(entity_key: String) -> Dictionary:
	if _preview_snapshot == null:
		return {}
	return _preview_snapshot.get_entity_state(entity_key)


func queue_commit() -> bool:
	return false


func _ensure_preview_snapshot(room_id: String, spawn_id: String, spawn_position: Vector2) -> void:
	if _preview_snapshot == null:
		_preview_snapshot = SAVE_SNAPSHOT.new()
	_preview_snapshot.slot = 0
	_preview_snapshot.world_id = "preview"
	_preview_snapshot.current_room_id = room_id
	_preview_snapshot.respawn_room_id = room_id
	_preview_snapshot.respawn_spawn_id = spawn_id
	_preview_snapshot.respawn_position = spawn_position


func _find_spawn_point(node: Node, spawn_id: String) -> Node2D:
	if node == null or spawn_id.is_empty():
		return null
	if node is SpawnPoint and (node as SpawnPoint).spawn_id == spawn_id:
		return node as Node2D
	for child: Node in node.get_children():
		var found := _find_spawn_point(child, spawn_id)
		if found != null:
			return found
	return null


func _connect_entrances(node: Node) -> void:
	if node == null:
		return
	if node is RoomEntrance:
		var callback := Callable(self, "_on_transition_requested")
		var connection_key := "room_preview_controller_%d" % get_instance_id()
		if not node.has_meta(connection_key):
			node.connect("transition_requested", callback)
			node.set_meta(connection_key, true)
	for child: Node in node.get_children():
		_connect_entrances(child)


func _on_transition_requested(entrance: RoomEntrance) -> void:
	transition_blocked.emit(entrance)


func _bind_target(target_owner: Node, target: Node2D) -> void:
	if target_owner.has_method("bind_target"):
		target_owner.call("bind_target", target)
	elif _has_property(target_owner, "target"):
		target_owner.set("target", target)


func _bind_player(target_owner: Node, player: Node2D) -> void:
	if target_owner.has_method("bind_player"):
		target_owner.call("bind_player", player)
	elif _has_property(target_owner, "player"):
		target_owner.set("player", player)
	elif _has_property(target_owner, "_player"):
		target_owner.set("_player", player)


func _has_property(target: Object, property_name: String) -> bool:
	for property_info: Dictionary in target.get_property_list():
		if String(property_info.get("name", "")) == property_name:
			return true
	return false
