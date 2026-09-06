@tool
class_name RoomAuthoringContract
extends RefCounted

const ROOM_AUTHORING_ROOT_SCRIPT: Script = preload("res://scripts/authoring/room_authoring_root.gd")
const REQUIRED_CONTENT_NODES: Array[String] = ["Background", "Terrain", "Entities", "Foreground"]
const REQUIRED_TERRAIN_LAYERS: Array[String] = [
	"BackTiles", "SolidTiles", "GlassTiles", "VisionBlockTiles", "DetailTiles", "MarkerTiles"
]


static func validate(root: Node) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	if not _is_room_authoring_root(root):
		errors.append("root must use RoomAuthoringRoot")
		return {"errors": errors, "warnings": warnings}
	var room_content: Node = root.get_node_or_null("RoomContent")
	var preview_root: Node = root.get_node_or_null("PreviewOnly")
	if room_content == null:
		errors.append("missing root node: RoomContent")
	if preview_root == null:
		errors.append("missing root node: PreviewOnly")
	if room_content != null:
		_validate_content(room_content, errors)
	var room_id: String = String(root.get("room_id"))
	var room_size_chunks: Vector2i = root.get("room_size_chunks")
	if room_id.is_empty():
		errors.append("room_id must be non-empty")
	if room_size_chunks.x <= 0 or room_size_chunks.y <= 0:
		errors.append("room_size_chunks must be positive on both axes")
	if room_content != null:
		var ids := _validate_unique_ids(room_content, errors)
		var preview_spawn_id := String(root.get("preview_spawn_id"))
		if not preview_spawn_id.is_empty() and not (ids.get("spawns", {}) as Dictionary).has(preview_spawn_id):
			errors.append("preview_spawn_id does not reference a SpawnPoint: %s" % preview_spawn_id)
	return {"errors": errors, "warnings": warnings}


static func _validate_content(room_content: Node, errors: Array[String]) -> void:
	for child_name: String in REQUIRED_CONTENT_NODES:
		var child: Node = room_content.get_node_or_null(child_name)
		if child == null:
			errors.append("RoomContent missing node: %s" % child_name)
	if room_content.get_node_or_null("Terrain") == null:
		return
	var terrain: Node = room_content.get_node("Terrain")
	for layer_name: String in REQUIRED_TERRAIN_LAYERS:
		var layer: Node = terrain.get_node_or_null(layer_name)
		if layer == null:
			errors.append("Terrain missing layer: %s" % layer_name)
		elif not layer is TileMapLayer:
			errors.append("Terrain layer must be TileMapLayer: %s" % layer_name)


static func _validate_unique_ids(root: Node, errors: Array[String]) -> Dictionary:
	var entrance_ids: Dictionary = {}
	var spawn_ids: Dictionary = {}
	var persistent_entity_ids: Dictionary = {}
	_validate_ids_recursive(root, entrance_ids, spawn_ids, persistent_entity_ids, errors)
	return {
		"entrances": entrance_ids,
		"spawns": spawn_ids,
		"persistent_entities": persistent_entity_ids,
	}


static func _is_room_authoring_root(root: Node) -> bool:
	var script: Script = root.get_script()
	while script != null:
		if script == ROOM_AUTHORING_ROOT_SCRIPT:
			return true
		script = script.get_base_script()
	return false


static func _validate_ids_recursive(node: Node, entrance_ids: Dictionary, spawn_ids: Dictionary, persistent_entity_ids: Dictionary, errors: Array[String]) -> void:
	if node is RoomEntrance:
		var entrance: RoomEntrance = node as RoomEntrance
		_check_id(entrance.entity_id, "entrance", entrance_ids, errors)
	if node is SpawnPoint:
		var spawn: SpawnPoint = node as SpawnPoint
		_check_id(spawn.spawn_id, "spawn", spawn_ids, errors)
	if node is WorldEntity:
		var entity: WorldEntity = node as WorldEntity
		if entity.persistent:
			_check_id(entity.entity_id, "persistent entity", persistent_entity_ids, errors)
	for child: Node in node.get_children():
		_validate_ids_recursive(child, entrance_ids, spawn_ids, persistent_entity_ids, errors)


static func _check_id(value: String, id_namespace: String, seen: Dictionary, errors: Array[String]) -> void:
	if value.is_empty():
		errors.append("%s ID must be non-empty" % id_namespace)
		return
	if seen.has(value):
		errors.append("duplicate %s ID: %s" % [id_namespace, value])
	else:
		seen[value] = true
