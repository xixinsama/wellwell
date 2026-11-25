extends Node

## Every shipped world must pass WorldValidation, and every generated room
## terrain must satisfy the tile-layer contract. `tools/validate_project.gd` runs
## the same checks plus bake-freshness from the command line.

const WORLD_VALIDATION := preload("res://addons/platformer_kit/world/data/world_validation.gd")
const TILE_CONTRACT := preload("res://addons/platformer_kit/world/data/tile_layer_contract.gd")
const WORLD_DIRECTORY := "res://resources/worlds"


func run() -> Array[String]:
	var failures: Array[String] = []
	var paths := _world_paths()
	if paths.is_empty():
		return ["no world resources found under %s" % WORLD_DIRECTORY]
	for path: String in paths:
		var world := ResourceLoader.load(path) as Resource
		if world == null:
			failures.append("world resource could not be loaded: %s" % path)
			continue
		for error: String in WORLD_VALIDATION.validate_world(world):
			failures.append("%s: %s" % [path, error])
		for room: Resource in world.rooms:
			var terrain_path := String(room.terrain_scene_path)
			for error: String in TILE_CONTRACT.validate_scene(terrain_path):
				failures.append("%s/%s: %s" % [path, String(room.room_id), error])
	return failures


func _world_paths() -> Array[String]:
	var paths: Array[String] = []
	var directory := DirAccess.open(WORLD_DIRECTORY)
	if directory == null:
		return paths
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry.ends_with(".tres") and not entry.ends_with("_stack.tres") and entry != "world_catalog.tres":
			paths.append(WORLD_DIRECTORY.path_join(entry))
		entry = directory.get_next()
	directory.list_dir_end()
	paths.sort()
	return paths
