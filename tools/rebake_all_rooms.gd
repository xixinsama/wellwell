extends SceneTree

## Maintenance: re-bake every shipped room from its source so
## generated scenes and fingerprints match the current tree. Use it after moving
## source scenes or changing the room template; run tools/validate_project.gd after.

const BAKER := preload("res://addons/world_editor/authoring/room/room_baker.gd")
const WORLD_DIRECTORY := "res://resources/worlds"


func _init() -> void:
	var failures := 0
	for path: String in _world_paths():
		var world := ResourceLoader.load(path) as Resource
		if world == null or not world.has_method("get_room"):
			continue
		var terrain_path := String(world.call("get_terrain_scene_path"))
		for room: Resource in world.rooms:
			var room_id := String(room.get("room_id"))
			var source_path := String(room.get("source_scene_path"))
			if not FileAccess.file_exists(source_path):
				print("SKIP  ", room_id, " (missing source)")
				failures += 1
				continue
			var source_root := (load(source_path) as PackedScene).instantiate()
			var baker: RefCounted = BAKER.new()
			var origin: Vector2i = world.call("get_room_origin_chunk", room_id)
			var result: Dictionary = baker.call("bake", source_root, source_path, origin, terrain_path)
			source_root.free()
			if bool(result.get("ok", false)):
				print("BAKED ", room_id)
			else:
				failures += 1
				print("FAIL  ", room_id, " ", str(result.get("errors", [])))
	print("re-bake done: %d failures" % failures)
	quit(1 if failures > 0 else 0)


func _world_paths() -> Array[String]:
	var paths: Array[String] = []
	var directory := DirAccess.open(WORLD_DIRECTORY)
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry.ends_with(".tres") and not entry.ends_with("_stack.tres") and entry != "world_catalog.tres":
			paths.append(WORLD_DIRECTORY.path_join(entry))
		entry = directory.get_next()
	directory.list_dir_end()
	paths.sort()
	return paths
