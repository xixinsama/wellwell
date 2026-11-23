extends SceneTree

## Validates every shipped world: WorldData graph, room asset paths, bake
## freshness, and the terrain tile-layer contract.
##
##   godot --headless --path . -s res://tools/validate_project.gd
##
## Exits non-zero when a world or a room is broken. Warnings (unconnected
## entrances, unreachable rooms) do not fail the run.

const WORLD_VALIDATION := preload("res://addons/platformer_kit/world/data/world_validation.gd")
const TILE_CONTRACT := preload("res://addons/platformer_kit/world/data/tile_layer_contract.gd")
const WORLD_DIRECTORY := "res://resources/worlds"


func _init() -> void:
	var failures: Array[String] = []
	var warnings: Array[String] = []
	var paths := _world_paths()
	for path: String in paths:
		_validate_world(path, failures, warnings)
	for warning: String in warnings:
		print("WARN  ", warning)
	for failure: String in failures:
		push_error(failure)
	print("project validation: %d worlds, %d errors, %d warnings" % [paths.size(), failures.size(), warnings.size()])
	quit(1 if not failures.is_empty() else 0)


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


func _validate_world(path: String, failures: Array[String], warnings: Array[String]) -> void:
	var world := ResourceLoader.load(path) as Resource
	if world == null:
		failures.append("%s: could not load world resource" % path)
		return
	var report: Dictionary = WORLD_VALIDATION.validate_world_report(world)
	for error: Variant in report.get("errors", []):
		failures.append("%s: %s" % [path, String(error)])
	for warning: Variant in report.get("warnings", []):
		warnings.append("%s: %s" % [path, String(warning)])
	if not world.has_method("get_room"):
		failures.append("%s: not a WorldData resource" % path)
		return
	for room: Resource in world.rooms:
		_validate_room(String(world.get("world_id")), room, failures)


func _validate_room(world_id: String, room: Resource, failures: Array[String]) -> void:
	var room_id := String(room.get("room_id"))
	for property: String in ["scene_path", "terrain_scene_path", "source_scene_path"]:
		var asset_path := String(room.get(property))
		if asset_path.is_empty():
			failures.append("%s/%s: %s is empty" % [world_id, room_id, property])
		elif not FileAccess.file_exists(asset_path):
			failures.append("%s/%s: %s does not exist: %s" % [world_id, room_id, property, asset_path])
	var source_path := String(room.get("source_scene_path"))
	if not source_path.is_empty() and FileAccess.file_exists(source_path):
		var fingerprint := String(room.get("source_fingerprint"))
		var current := FileAccess.get_sha256(source_path)
		if fingerprint.is_empty():
			failures.append("%s/%s: no bake fingerprint; re-bake the room" % [world_id, room_id])
		elif fingerprint != current:
			failures.append("%s/%s: stale bake, source changed since the last bake" % [world_id, room_id])
	var terrain_path := String(room.get("terrain_scene_path"))
	if not terrain_path.is_empty() and FileAccess.file_exists(terrain_path):
		for error: String in TILE_CONTRACT.validate_scene(terrain_path):
			failures.append("%s/%s: %s" % [world_id, room_id, error])
