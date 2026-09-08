extends Node

const TILE_CONTRACT := preload("res://addons/platformer_kit/world/data/tile_layer_contract.gd")
const MAIN_WORLD: Resource = preload("res://resources/worlds/main_world.tres")

func run() -> Array[String]:
	var failures: Array[String] = []
	for room: Resource in MAIN_WORLD.rooms:
		var errors := TILE_CONTRACT.validate_scene(room.terrain_scene_path)
		if not errors.is_empty():
			failures.append("generated terrain violates required tile layer contract: %s" % room.room_id)
	return failures
