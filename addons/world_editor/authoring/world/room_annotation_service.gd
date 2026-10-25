class_name RoomAnnotationService
extends RefCounted

## Collects the interesting authoring anchors of a baked room runtime scene so
## the World editor canvas can draw spawn points, entrances and entities.
##
## Instances the packed scene **without adding it to the tree** (so @tool
## `_ready` side effects never run), walks the node tree accumulating
## transforms, then frees it. Results are cached by (path, mtime, size).

const TYPE_SPAWN := &"spawn"
const TYPE_ENTRANCE := &"entrance"
const TYPE_SAVE := &"save"
const TYPE_PICKUP := &"pickup"
const TYPE_HAZARD := &"hazard"
const TYPE_SWITCH := &"switch"
const TYPE_RESET_ZONE := &"reset_zone"
const TYPE_WORLD_ENTITY := &"world_entity"

## (path) -> PackedScene. Overridable in tests.
var load_provider: Callable

var _cache: Dictionary = {}


func _init() -> void:
	load_provider = _default_load


## Returns [{type, id, name, position, path}] in room-local coordinates.
func collect(room: RoomData) -> Array[Dictionary]:
	if room == null or room.scene_path.is_empty():
		return []
	var path := room.scene_path
	if not FileAccess.file_exists(path):
		return []
	var mtime := int(FileAccess.get_modified_time(path))
	var size := _file_size(path)
	var cached: Dictionary = _cache.get(path, {})
	if not cached.is_empty() \
		and int(cached.get("mtime", -1)) == mtime \
		and int(cached.get("size", -1)) == size:
		return (cached.get("annotations", []) as Array).duplicate(true)

	var annotations: Array[Dictionary] = []
	var packed := load_provider.call(path) as PackedScene
	if packed != null:
		var root := packed.instantiate()
		if root != null:
			_walk(root, Transform2D.IDENTITY, "", annotations)
			root.free()
	_cache[path] = {"mtime": mtime, "size": size, "annotations": annotations}
	return annotations.duplicate(true)


func clear_cache() -> void:
	_cache.clear()


func _walk(node: Node, parent_transform: Transform2D, parent_path: String, out: Array[Dictionary]) -> void:
	var transform := parent_transform
	if node is Node2D:
		transform = parent_transform * (node as Node2D).transform
	var node_path := node.name if parent_path.is_empty() else "%s/%s" % [parent_path, node.name]
	var type := _annotation_type(node)
	if type != &"":
		out.append({
			"type": type,
			"id": _annotation_id(node),
			"name": String(node.name),
			"position": transform.origin,
			"path": node_path,
		})
	for child: Node in node.get_children():
		_walk(child, transform, node_path, out)


static func _annotation_type(node: Node) -> StringName:
	if node is SpawnPoint:
		return TYPE_SPAWN
	if node is RoomEntrance:
		return TYPE_ENTRANCE
	if node is SavePoint:
		return TYPE_SAVE
	if node is PickupEntity:
		return TYPE_PICKUP
	if node is HazardEntity:
		return TYPE_HAZARD
	if node is SwitchEntity:
		return TYPE_SWITCH
	if node is ResetZone:
		return TYPE_RESET_ZONE
	if node is WorldEntity:
		return TYPE_WORLD_ENTITY
	return &""


static func _annotation_id(node: Node) -> String:
	if node is SpawnPoint:
		return String((node as SpawnPoint).spawn_id)
	if node is WorldEntity:
		return String((node as WorldEntity).entity_id)
	return ""


func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	var size := file.get_length()
	file.close()
	return size


static func _default_load(path: String) -> PackedScene:
	return ResourceLoader.load(path, "PackedScene") as PackedScene
