extends Node

const ROOM_BAKE_PATHS: Script = preload("res://scripts/authoring/room/room_bake_paths.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	var paths: Dictionary = ROOM_BAKE_PATHS.for_room_id("level_2")
	if paths.get("runtime_scene_path") != "res://scenes/rooms/generated/level_2/runtime.tscn":
		failures.append("runtime output must be grouped beneath its room id")
	if paths.get("terrain_scene_path") != "res://scenes/rooms/generated/level_2/terrain.tscn":
		failures.append("terrain output must be grouped beneath its room id")
	if paths.get("room_resource_path") != "res://resources/rooms/generated/level_2.tres":
		failures.append("RoomData output must use one canonical resource path")
	return failures
