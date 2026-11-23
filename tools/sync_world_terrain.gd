extends SceneTree

## Re-slices every room from its world's authored terrain scene and re-bakes it.
##
## This is the headless twin of the World editor's **Sync Terrain** button: the
## terrain scene (`scenes/worlds/<world_id>/terrain.tscn`) is the source of truth,
## and every `scenes/rooms/generated/<room>/terrain.tscn` is a slice of it.
##
## Usage:
##   godot --headless --path . -s res://tools/sync_world_terrain.gd
##   godot --headless --path . -s res://tools/sync_world_terrain.gd -- --world=res://resources/worlds/test_world.tres

const WORLD_DIR := "res://resources/worlds/"
const BAKER := preload("res://addons/world_editor/authoring/room/room_baker.gd")
const WORLD_RESOURCES := preload("res://addons/world_editor/authoring/world/world_resource_service.gd")

var _only_world := ""
var _errors := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--world="):
			_only_world = argument.trim_prefix("--world=")
	var baker := BAKER.new()
	var service := WORLD_RESOURCES.new()
	var world_paths := _world_paths()
	print("sync: %d world(s)" % world_paths.size())
	for path: String in world_paths:
		_sync_world(path, baker, service)
	print("sync: done, errors=%d" % _errors)
	quit(0 if _errors == 0 else 1)


func _world_paths() -> Array[String]:
	var result: Array[String] = []
	if not _only_world.is_empty():
		result.append(_only_world)
		return result
	var directory := DirAccess.open(WORLD_DIR)
	if directory == null:
		return result
	for file_name: String in directory.get_files():
		if not file_name.ends_with(".tres"):
			continue
		if file_name.ends_with("_stack.tres") or file_name == "world_catalog.tres":
			continue
		result.append(WORLD_DIR + file_name)
	result.sort()
	return result


func _sync_world(world_path: String, baker: Object, service: Object) -> void:
	var world := ResourceLoader.load(world_path, "WorldData", ResourceLoader.CACHE_MODE_IGNORE) as WorldData
	if world == null:
		print("  skip (not WorldData): ", world_path)
		return
	var terrain_path := world.get_terrain_scene_path()
	if terrain_path.is_empty() or not FileAccess.file_exists(terrain_path):
		print("  skip (no world terrain): ", world_path)
		return
	print("world ", world.world_id)
	var changed := false
	for room_id: String in world.get_room_ids():
		var room: RoomData = world.get_room(room_id)
		if room == null or room.source_scene_path.is_empty():
			continue
		if not ResourceLoader.exists(room.source_scene_path, "PackedScene"):
			_warn("missing room source: %s" % room.source_scene_path)
			continue
		var room_root := (ResourceLoader.load(
			room.source_scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE
		) as PackedScene).instantiate()
		var result: Dictionary = baker.call(
			"bake",
			room_root,
			room.source_scene_path,
			world.get_room_origin_chunk(room_id),
			terrain_path
		)
		room_root.free()
		if not bool(result.get("ok", false)):
			_warn("%s: %s" % [room_id, str(result.get("errors", []))])
			continue
		var baked := ResourceLoader.load(
			String((result["outputs"] as Dictionary)["room_resource_path"]),
			"RoomData",
			ResourceLoader.CACHE_MODE_IGNORE
		) as RoomData
		if baked == null:
			_warn("%s: baked RoomData could not be reloaded" % room_id)
			continue
		var index := world.rooms.find(room)
		if index >= 0:
			world.rooms[index] = baked
			changed = true
	if not changed:
		return
	var saved: Dictionary = service.call("save_world", world)
	if not bool(saved.get("ok", false)):
		_warn("could not save %s: %s" % [world_path, str(saved.get("errors", []))])


func _warn(message: String) -> void:
	_errors += 1
	print("  ERROR: ", message)
