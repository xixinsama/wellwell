class_name WorldTerrainRuntime
extends Node2D

const WORLD_DATA_SCRIPT: Script = preload("res://scripts/world/world_data.gd")
const ROOM_DATA_SCRIPT: Script = preload("res://scripts/world/room_data.gd")
const TERRAIN_LAYER_NAMES: Array[String] = [
	"BackTiles", "SolidTiles", "GlassTiles", "VisionBlockTiles", "DetailTiles", "MarkerTiles"
]

var _world_data: Resource
var _world_signature := ""
var _terrain_by_room: Dictionary[String, Node2D] = {}


func setup_world(world: WorldData) -> bool:
	if not _is_world_data(world):
		return false
	var signature := _get_world_signature(world)
	if signature.is_empty():
		return false
	if signature == _world_signature:
		_world_data = world
		return true
	var staged: Dictionary[String, Node2D] = {}
	for room_id: String in world.get_room_ids():
		var room: Resource = world.get_room(room_id)
		var terrain := _instantiate_terrain(room)
		if terrain == null:
			_free_staged(staged)
			return false
		staged[room_id] = terrain

	clear_world()
	for room_id: String in world.get_room_ids():
		var terrain: Node2D = staged[room_id]
		add_child(terrain)
		_terrain_by_room[room_id] = terrain
	staged.clear()
	_world_data = world
	_world_signature = signature
	return true


func get_room_terrain(room_id: String) -> Node:
	return _terrain_by_room.get(room_id, null)


func clear_world() -> void:
	for terrain: Node2D in _terrain_by_room.values():
		if is_instance_valid(terrain):
			terrain.free()
	_terrain_by_room.clear()
	_world_data = null
	_world_signature = ""


func _instantiate_terrain(room: Resource) -> Node2D:
	if not _is_room_data(room) or room.terrain_scene_path.is_empty():
		return null
	if not ResourceLoader.exists(room.terrain_scene_path, "PackedScene"):
		return null
	var scene := ResourceLoader.load(
		room.terrain_scene_path,
		"PackedScene",
		ResourceLoader.CACHE_MODE_IGNORE
	) as PackedScene
	if scene == null:
		return null
	var instance := scene.instantiate() as Node2D
	if instance == null:
		return null
	if not _is_valid_terrain_root(instance):
		instance.free()
		return null
	instance.name = room.room_id
	instance.position = Vector2(room.room_origin_chunk * RoomData.DEFAULT_CHUNK_SIZE_PIXELS)
	return instance


func _is_valid_terrain_root(root: Node2D) -> bool:
	if root.get_node_or_null("Background") == null:
		return false
	var terrain := root.get_node_or_null("Terrain")
	if terrain == null:
		return false
	for layer_name: String in TERRAIN_LAYER_NAMES:
		if not terrain.get_node_or_null(layer_name) is TileMapLayer:
			return false
	return true


func _get_world_signature(world: Resource) -> String:
	var parts: Array[String] = []
	var seen: Dictionary = {}
	for room: Resource in world.rooms:
		if not _is_room_data(room) or room.room_id.is_empty() or seen.has(room.room_id):
			return ""
		seen[room.room_id] = true
		parts.append("%s|%s|%d,%d" % [
			room.room_id,
			room.terrain_scene_path,
			room.room_origin_chunk.x,
			room.room_origin_chunk.y,
		])
	parts.sort()
	return "\n".join(parts)


func _free_staged(staged: Dictionary[String, Node2D]) -> void:
	for terrain: Node2D in staged.values():
		terrain.free()
	staged.clear()


static func _is_world_data(resource: Resource) -> bool:
	return resource != null and resource.get_script() == WORLD_DATA_SCRIPT


static func _is_room_data(resource: Resource) -> bool:
	return resource != null and resource.get_script() == ROOM_DATA_SCRIPT
