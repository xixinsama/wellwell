@tool
class_name RoomPartitionOperations
extends RefCounted

## Merge and split room source scenes and rectangles for the World editor.
##
## The world terrain is untouched: merging only unions the room rectangles (the
## world terrain under them already exists), splitting only divides one. Entity
## nodes are moved between the new source scenes by world position, keeping the
## instanced prefabs intact.

const ROOM_GRID := preload("res://addons/platformer_kit/world/data/room_grid.gd")
const SPAWN_POINT := preload("res://addons/platformer_kit/world/entities/spawn_point.gd")
const ENTITY_LAYERS: Array[String] = ["Entities", "Foreground"]


## The union of a selection, or an error when the selection is not a rectangle.
## Returns `{ok, rect: Rect2i, error: String}` with the result in chunk units.
static func merge_rect(world: WorldData, room_ids: Array[String]) -> Dictionary:
	if world == null:
		return {"ok": false, "rect": Rect2i(), "error": "world is null"}
	if room_ids.size() < 2:
		return {"ok": false, "rect": Rect2i(), "error": "select at least two rooms"}
	var rects: Array[Rect2i] = []
	var seen: Dictionary = {}
	for room_id: String in room_ids:
		if room_id.is_empty() or seen.has(room_id):
			continue
		seen[room_id] = true
		var room := world.get_room(room_id)
		if room == null:
			return {"ok": false, "rect": Rect2i(), "error": "unknown room: %s" % room_id}
		rects.append(Rect2i(world.get_room_origin_chunk(room_id), room.room_size_chunks))
	if rects.size() < 2:
		return {"ok": false, "rect": Rect2i(), "error": "select at least two rooms"}
	var union := rects[0]
	var area := 0
	for rect: Rect2i in rects:
		union = union.merge(rect)
		area += rect.size.x * rect.size.y
	if area != union.size.x * union.size.y:
		return {"ok": false, "rect": Rect2i(), "error": "the selection's union is not a rectangle"}
	return {"ok": true, "rect": union, "error": ""}


## Two rectangles after cutting [param room] at [param index] chunks along
## [param axis] ("x" or "y"). The cut must be on a chunk boundary inside the room.
static func split_rects(
	world: WorldData,
	room_id: String,
	axis: String,
	index: int
) -> Dictionary:
	var room := world.get_room(room_id) if world != null else null
	if room == null:
		return {"ok": false, "rects": [], "error": "unknown room: %s" % room_id}
	var origin: Vector2i = world.get_room_origin_chunk(room_id)
	var size: Vector2i = room.room_size_chunks
	var is_x := axis == "x"
	var extent := size.x if is_x else size.y
	if index <= 0 or index >= extent:
		return {"ok": false, "rects": [], "error": "cut must be on an interior chunk boundary"}
	var first_size := Vector2i(index, size.y) if is_x else Vector2i(size.x, index)
	var second_origin := origin + (Vector2i(index, 0) if is_x else Vector2i(0, index))
	var second_size := (
		Vector2i(size.x - index, size.y) if is_x else Vector2i(size.x, size.y - index)
	)
	return {
		"ok": true,
		"rects": [Rect2i(origin, first_size), Rect2i(second_origin, second_size)],
		"error": "",
	}


## Builds a merged source scene for [param room_ids] at [param target_path].
## The returned `source` is a live instance for the importer; the caller frees it.
func merge_sources(
	world: WorldData,
	room_ids: Array[String],
	new_room_id: String,
	target_path: String
) -> Dictionary:
	var union_result := merge_rect(world, room_ids)
	if not bool(union_result["ok"]):
		return _failure(String(union_result["error"]))
	var rect: Rect2i = union_result["rect"]
	var shell := _load_source(world, room_ids[0])
	if shell == null:
		return _failure("could not load the first room source")
	for layer_name: String in ENTITY_LAYERS:
		var layer := shell.get_node_or_null("RoomContent/%s" % layer_name)
		if layer != null:
			_clear_children(layer)
	var union_pixels := _room_origin_pixels(rect)
	for room_id: String in room_ids:
		var room := world.get_room(room_id)
		if room == null:
			continue
		var source := _load_source(world, room_id)
		if source == null:
			shell.free()
			return _failure("could not load the source for room '%s'" % room_id)
		var room_rect := Rect2i(world.get_room_origin_chunk(room_id), room.room_size_chunks)
		var offset := _room_origin_pixels(room_rect) - union_pixels
		for layer_name: String in ENTITY_LAYERS:
			var source_layer := source.get_node_or_null("RoomContent/%s" % layer_name)
			var target_layer := shell.get_node_or_null("RoomContent/%s" % layer_name)
			if source_layer == null or target_layer == null:
				continue
			for child: Node in source_layer.get_children():
				source_layer.remove_child(child)
				# Clearing the stale owner first keeps `add_child` from warning that
				# the new parent's ownership is inconsistent.
				child.owner = null
				target_layer.add_child(child)
				if child is Node2D:
					(child as Node2D).position += Vector2(offset)
				_claim_node(child, shell)
		source.free()
	_apply_room_properties(shell, new_room_id, rect)
	_ensure_spawn(shell, rect)
	var duplicate := _duplicate_ids(shell)
	if not duplicate.is_empty():
		shell.free()
		return _failure("duplicate entity ids after merging: %s" % duplicate)
	var save_error := _save_scene(shell, target_path)
	if not save_error.is_empty():
		shell.free()
		return _failure(save_error)
	return {"ok": true, "errors": [], "warnings": [], "source": shell, "path": target_path, "rect": rect, "room_id": new_room_id}


## Builds two split source scenes for [param room_id]. The returned `sources` are
## live instances in the same order as `rects`; the caller frees them.
func split_sources(
	world: WorldData,
	room_id: String,
	axis: String,
	index: int,
	target_paths: Array[String]
) -> Dictionary:
	var split := split_rects(world, room_id, axis, index)
	if not bool(split["ok"]):
		return _failure(String(split["error"]))
	var rects: Array = split["rects"]
	if target_paths.size() != 2:
		return _failure("split needs two target paths")
	var room := world.get_room(room_id)
	if room == null or room.source_scene_path.is_empty():
		return _failure("room source is missing")
	var sources: Array[Node] = []
	for side: int in 2:
		var rect: Rect2i = rects[side]
		var source := _load_source(world, room_id)
		if source == null:
			for built: Node in sources:
				built.free()
			return _failure("could not load the room source")
		var old_pixels := _room_origin_pixels(Rect2i(world.get_room_origin_chunk(room_id), room.room_size_chunks))
		var side_pixels := _room_origin_pixels(rect)
		var side_rect_pixels := Rect2(side_pixels, Vector2(_room_rect_pixels(rect).size))
		for layer_name: String in ENTITY_LAYERS:
			var layer := source.get_node_or_null("RoomContent/%s" % layer_name)
			if layer == null:
				continue
			for child: Node in layer.get_children():
				if not child is Node2D:
					continue
				var node := child as Node2D
				var world_position := old_pixels + node.position
				if not side_rect_pixels.has_point(world_position):
					layer.remove_child(node)
					node.free()
					continue
				node.position = world_position - side_pixels
				_set_owner_recursive(node, source)
		_apply_room_properties(source, target_paths[side].get_file().get_basename(), rect)
		_ensure_spawn(source, rect)
		var save_error := _save_scene(source, target_paths[side])
		if not save_error.is_empty():
			source.free()
			for built: Node in sources:
				built.free()
			return _failure(save_error)
		sources.append(source)
	return {"ok": true, "errors": [], "warnings": [], "sources": sources, "rects": rects}


## World position of an entity/entrance/spawn id inside a room source scene, or
## `null` when it cannot be found. Used to decide a connection's side on split.
static func entity_world_position(
	source_root: Node,
	origin_chunk: Vector2i,
	size_chunks: Vector2i,
	match_key: String,
	match_value: String
) -> Variant:
	var origin := _room_origin_pixels(Rect2i(origin_chunk, size_chunks))
	return _find_entity(source_root, origin, match_key, match_value)


static func _find_entity(node: Node, origin: Vector2, match_key: String, match_value: String) -> Variant:
	if node is Node2D and node != null:
		var value: Variant = node.get(match_key)
		if value != null and String(value) == match_value:
			return origin + (node as Node2D).position
	for child: Node in node.get_children():
		var found := _find_entity(child, origin, match_key, match_value)
		if found != null:
			return found
	return null


static func room_rect_pixels(rect: Rect2i) -> Rect2:
	var cell_rect := RoomGrid.get_room_cell_rect(rect.position, rect.size)
	return Rect2(
		Vector2(cell_rect.position * RoomGrid.DEFAULT_CELL_SIZE),
		Vector2(cell_rect.size * RoomGrid.DEFAULT_CELL_SIZE)
	)


static func _room_origin_pixels(rect: Rect2i) -> Vector2:
	return Vector2(RoomGrid.get_room_cell_rect(rect.position, rect.size).position * RoomGrid.DEFAULT_CELL_SIZE)


static func _room_rect_pixels(rect: Rect2i) -> Rect2:
	return room_rect_pixels(rect)


func _load_source(world: WorldData, room_id: String) -> Node:
	var room := world.get_room(room_id)
	if room == null or room.source_scene_path.is_empty():
		return null
	if not ResourceLoader.exists(room.source_scene_path, "PackedScene"):
		return null
	var packed := ResourceLoader.load(
		room.source_scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE
	) as PackedScene
	return null if packed == null else packed.instantiate()


func _clear_children(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.free()


## Re-owns a node that moved between scenes.
##
## The node still points at its old scene root, which is outside the new tree, so
## `pack()` would drop it. Instanced sub-scenes keep their own children owned by
## the instance root (re-owning those would flatten the prefab into a copy), so
## the recursion stops at an instance root.
func _claim_node(node: Node, scene_root: Node) -> void:
	node.owner = scene_root
	if not node.scene_file_path.is_empty():
		return
	for child: Node in node.get_children():
		_claim_node(child, scene_root)


func _set_owner_recursive(node: Node, scene_root: Node) -> void:
	if node.owner == null:
		node.owner = scene_root
	for child: Node in node.get_children():
		_set_owner_recursive(child, scene_root)


func _apply_room_properties(source: Node, room_id: String, rect: Rect2i) -> void:
	if source.get("room_id") == null:
		return
	source.set("room_id", room_id)
	source.set("display_name", room_id)
	source.set("room_size_chunks", rect.size)
	source.set("world_origin_chunk", rect.position)
	source.set("world_origin_known", true)


func _ensure_spawn(source: Node, rect: Rect2i) -> void:
	var entities := source.get_node_or_null("RoomContent/Entities")
	if entities == null:
		return
	for child: Node in entities.get_children():
		if child is SpawnPoint:
			return
	var spawn: SpawnPoint = SPAWN_POINT.new() as SpawnPoint
	spawn.name = "StartSpawn"
	spawn.spawn_id = "start"
	spawn.position = Vector2(_room_rect_pixels(rect).size) * 0.5
	var previous_owner := entities.owner
	entities.owner = null
	entities.add_child(spawn)
	entities.owner = previous_owner
	spawn.owner = source


func _duplicate_ids(source: Node) -> Array[String]:
	var duplicates: Array[String] = []
	if not source.has_method("get_manifest"):
		return duplicates
	var manifest: Dictionary = source.call("get_manifest")
	for key: String in ["spawn_ids", "entrance_ids", "persistent_entity_ids"]:
		var seen: Dictionary = {}
		for value: Variant in manifest.get(key, []):
			var id := String(value)
			if id.is_empty():
				continue
			if seen.has(id):
				duplicates.append(id)
			seen[id] = true
	return duplicates


func _save_scene(source: Node, path: String) -> String:
	if path.is_empty():
		return "empty room source path"
	var dir_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(path.get_base_dir())
	)
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		return "could not create %s" % path.get_base_dir()
	var scene := PackedScene.new()
	if scene.pack(source) != OK:
		return "could not pack %s" % path
	if ResourceSaver.save(scene, path) != OK:
		return "could not save %s" % path
	return ""


func _failure(message: String) -> Dictionary:
	return {"ok": false, "errors": [message], "warnings": []}
