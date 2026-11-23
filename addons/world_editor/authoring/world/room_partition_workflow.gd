@tool
class_name RoomPartitionWorkflow
extends RefCounted

## Merge/split orchestration for the World editor.
##
## The world is the source of truth: merging unions room rectangles and moving
## their entities into one new room source, splitting divides one room source in
## two. The world terrain scene is never modified, because the terrain under those
## rectangles already exists.
##
## Everything the operation touches is backed up first: the world resource goes to
## `res://resources/worlds/_partition_backup/`, the members' sources and generated
## outputs to `res://resources/worlds/<world>/merge_backup/<stamp>/`.

const PARTITION := preload("res://addons/world_editor/authoring/world/room_partition_operations.gd")
const IMPORTER := preload("res://addons/world_editor/authoring/world/world_room_importer.gd")
const WORLD_RESOURCES := preload("res://addons/world_editor/authoring/world/world_resource_service.gd")
const MODEL := preload("res://addons/world_editor/authoring/world/world_layout_model.gd")
const CONNECTION_DATA := preload("res://addons/platformer_kit/world/data/room_connection_data.gd")
const BACKUP_DIR := "res://resources/worlds/_partition_backup/"
const ROOM_SOURCE_DIR := "res://scenes/levels/generated/"

var _partition: Object = PARTITION.new()
var _importer: Object = IMPORTER.new()
var _resources: Object = WORLD_RESOURCES.new()
var _model: Object = MODEL.new()


func set_importer_adapter(value: Object) -> void:
	_importer = value


func set_world_resources_adapter(value: Object) -> void:
	_resources = value


## Merges [param room_ids] into [param new_room_id]. `source_path` is where the new
## entity-only source scene is written. Returns
## `{ok, world, new_room_id, warnings, errors}`; `world` is a new WorldData instance.
func merge(
	world: WorldData,
	room_ids: Array[String],
	new_room_id: String,
	source_path: String
) -> Dictionary:
	if world == null or world.resource_path.is_empty():
		return _failure("WorldData must be saved before merging rooms")
	var union_result: Dictionary = _partition.call("merge_rect", world, room_ids)
	if not bool(union_result.get("ok", false)):
		return _failure(String(union_result.get("error", "invalid selection")))
	var rect: Rect2i = union_result["rect"]
	var built: Dictionary = _partition.call(
		"merge_sources", world, room_ids, new_room_id, source_path
	)
	if not bool(built.get("ok", false)):
		return built
	var source: Node = built["source"]
	var world_backup := backup_world(world)
	var old_start_room := world.start_room_id
	var old_start_spawn := world.start_spawn_id
	var new_id: String = built["room_id"]
	var result: Dictionary = _importer.call(
		"import_room", world, source, source_path, rect.position, true
	)
	source.free()
	if not bool(result.get("ok", false)):
		return _with_world_backup(result, world_backup)
	var merged_world := result.get("world") as WorldData
	if merged_world == null:
		_restore_world(world, world_backup)
		return _failure("Room importer returned no world")
	for room_id: String in room_ids:
		backup_room_assets(merged_world, room_id)
		_remap_connections(merged_world, room_ids, new_id)
	for room_id: String in room_ids:
		var removed: Dictionary = _model.call("remove_room", merged_world, room_id)
		if not bool(removed.get("ok", false)):
			_restore_world(world, world_backup)
			return _failure(String(removed.get("errors", ["could not remove room"])[0]))
	if room_ids.has(old_start_room):
		merged_world.start_room_id = new_id
		merged_world.start_spawn_id = _spawn_id_or_first(merged_world, new_id, old_start_spawn)
	var saved: Dictionary = _resources.call("save_world", merged_world)
	if not bool(saved.get("ok", false)):
		_restore_world(world, world_backup)
		return _failure(String((saved.get("errors", ["could not save world"]) as Array)[0]))
	return {
		"ok": true,
		"errors": [],
		"warnings": ["Merged %d room(s) into '%s'" % [room_ids.size(), new_id]],
		"world": merged_world,
		"new_room_ids": [new_id] as Array[String],
		"backup": world_backup,
	}


## Splits [param room_id] at [param index] chunks along [param axis] ("x"/"y").
## [param new_ids] and [param source_paths] must both have two entries.
func split(
	world: WorldData,
	room_id: String,
	axis: String,
	index: int,
	new_ids: Array[String],
	source_paths: Array[String]
) -> Dictionary:
	if world == null or world.resource_path.is_empty():
		return _failure("WorldData must be saved before splitting a room")
	if new_ids.size() != 2 or source_paths.size() != 2:
		return _failure("split needs two new ids and two source paths")
	var split_result: Dictionary = _partition.call("split_rects", world, room_id, axis, index)
	if not bool(split_result.get("ok", false)):
		return _failure(String(split_result.get("error", "invalid split")))
	var rects: Array = split_result["rects"]
	var built: Dictionary = _partition.call(
		"split_sources", world, room_id, axis, index, source_paths
	)
	if not bool(built.get("ok", false)):
		return built
	var sources: Array = built["sources"]
	var room := world.get_room(room_id)
	var origin: Vector2i = world.get_room_origin_chunk(room_id)
	var size: Vector2i = room.room_size_chunks
	var old_source := _load_source(room)
	var old_start_room := world.start_room_id
	var old_start_spawn := world.start_spawn_id
	var start_side := -1
	if old_start_room == room_id:
		var start_position: Variant = null
		if old_source != null:
			start_position = _partition.call(
				"entity_world_position", old_source, origin, size, "spawn_id", old_start_spawn
			)
		start_side = _side_for_position(start_position, rects)
	_remap_split_connections(world, old_source, origin, size, room_id, new_ids, rects)
	if old_source != null:
		old_source.free()
	var world_backup := backup_world(world)
	var current_world := world
	for side: int in 2:
		var side_rect: Rect2i = rects[side]
		var result: Dictionary = _importer.call(
			"import_room", current_world, sources[side], source_paths[side],
			side_rect.position, true
		)
		if not bool(result.get("ok", false)):
			for remaining: int in range(side, 2):
				(sources[remaining] as Node).free()
			_restore_world(world, world_backup)
			return _with_world_backup(result, world_backup)
		sources[side].free()
		current_world = result.get("world") as WorldData
	backup_room_assets(current_world, room_id)
	var removed: Dictionary = _model.call("remove_room", current_world, room_id)
	if not bool(removed.get("ok", false)):
		_restore_world(world, world_backup)
		return _failure("could not remove the split room")
	if start_side >= 0:
		current_world.start_room_id = new_ids[start_side]
		current_world.start_spawn_id = _spawn_id_or_first(
			current_world, new_ids[start_side], old_start_spawn
		)
	var saved: Dictionary = _resources.call("save_world", current_world)
	if not bool(saved.get("ok", false)):
		_restore_world(world, world_backup)
		return _failure("could not save the world after splitting")
	return {
		"ok": true,
		"errors": [],
		"warnings": ["Split '%s' into %s and %s" % [room_id, new_ids[0], new_ids[1]]],
		"world": current_world,
		"new_room_ids": new_ids,
		"backup": world_backup,
	}


## Where a new partition room source is written.
func source_path_for(world: WorldData, room_id: String) -> String:
	return "%s%s/%s.tscn" % [ROOM_SOURCE_DIR, world.world_id, room_id]


func backup_world(world: WorldData) -> String:
	if world == null or world.resource_path.is_empty():
		return ""
	var path := "%s%s/%s.tres" % [BACKUP_DIR, world.world_id, _stamp()]
	_copy_path(world.resource_path, path)
	return path


## Restores [param world]'s file from [param backup_path] in place. Used when a step
## fails after the importer already wrote a new world file.
func _restore_world(world: WorldData, backup_path: String) -> void:
	if world == null or world.resource_path.is_empty() or backup_path.is_empty():
		return
	if not FileAccess.file_exists(backup_path):
		return
	DirAccess.copy_absolute(
		ProjectSettings.globalize_path(backup_path),
		ProjectSettings.globalize_path(world.resource_path)
	)


func backup_room_assets(world: WorldData, room_id: String) -> void:
	var room := world.get_room(room_id)
	if room == null:
		return
	var root := "res://resources/worlds/%s/merge_backup/%s/" % [world.world_id, _stamp()]
	if not room.source_scene_path.is_empty():
		_copy_path(room.source_scene_path, root + room.source_scene_path.get_file())
	_copy_path(
		"res://resources/rooms/generated/%s.tres" % room_id,
		root + "rooms/%s.tres" % room_id
	)
	_copy_directory(
		"res://scenes/rooms/generated/%s" % room_id,
		root + "generated/%s" % room_id
	)


func _remap_connections(world: WorldData, ids: Array[String], new_id: String) -> void:
	for value: Variant in world.connections:
		var connection := value as RoomConnectionData
		if connection == null:
			continue
		if ids.has(connection.from_room_id):
			connection.from_room_id = new_id
		if ids.has(connection.to_room_id):
			connection.to_room_id = new_id


func _remap_split_connections(
	world: WorldData,
	source: Node,
	origin: Vector2i,
	size: Vector2i,
	old_id: String,
	new_ids: Array[String],
	rects: Array
) -> void:
	for value: Variant in world.connections:
		var connection := value as RoomConnectionData
		if connection == null:
			continue
		if connection.from_room_id == old_id:
			var entrance_position: Variant = null
			if source != null:
				entrance_position = _partition.call(
					"entity_world_position", source, origin, size,
					"entity_id", connection.from_entrance_id
				)
			connection.from_room_id = new_ids[_side_for_position(entrance_position, rects)]
		if connection.to_room_id == old_id:
			var spawn_position: Variant = null
			if source != null:
				spawn_position = _partition.call(
					"entity_world_position", source, origin, size,
					"spawn_id", connection.to_spawn_id
				)
			connection.to_room_id = new_ids[_side_for_position(spawn_position, rects)]


func _side_for_position(position: Variant, rects: Array) -> int:
	if position is Vector2:
		for side: int in 2:
			var side_rect: Rect2i = rects[side]
			var rect := RoomPartitionOperations.room_rect_pixels(side_rect)
			if rect.has_point(position as Vector2):
				return side
	return 0


func _spawn_id_or_first(world: WorldData, room_id: String, preferred: String) -> String:
	var room := world.get_room(room_id)
	if room == null:
		return preferred
	if not preferred.is_empty() and room.spawn_ids.has(preferred):
		return preferred
	return "" if room.spawn_ids.is_empty() else String(room.spawn_ids[0])


func _load_source(room: Resource) -> Node:
	if room == null or String(room.get("source_scene_path")).is_empty():
		return null
	var path := String(room.get("source_scene_path"))
	if not ResourceLoader.exists(path, "PackedScene"):
		return null
	var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	return null if packed == null else packed.instantiate()


func _copy_path(source: String, target: String) -> void:
	if source.is_empty() or not FileAccess.file_exists(source):
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir()))
	DirAccess.copy_absolute(
		ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(target)
	)


func _copy_directory(source_dir: String, target_dir: String) -> void:
	var directory := DirAccess.open(source_dir)
	if directory == null:
		return
	for file_name: String in directory.get_files():
		_copy_path(source_dir + "/" + file_name, target_dir + "/" + file_name)
	for child_name: String in directory.get_directories():
		_copy_directory(source_dir + "/" + child_name, target_dir + "/" + child_name)


func _stamp() -> String:
	return "%s_%d" % [
		Time.get_datetime_string_from_system().replace(":", "-"),
		Time.get_ticks_msec(),
	]


func _with_world_backup(result: Dictionary, backup_path: String) -> Dictionary:
	if not result.has("backup"):
		result["backup"] = backup_path
	return result


func _failure(message: String) -> Dictionary:
	return {"ok": false, "errors": [message], "warnings": []}
