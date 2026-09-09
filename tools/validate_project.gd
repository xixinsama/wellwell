extends SceneTree

const WORLD_VALIDATION := preload("res://addons/platformer_kit/world/data/world_validation.gd")
const TILE_CONTRACT := preload("res://addons/platformer_kit/world/data/tile_layer_contract.gd")
const MAIN_WORLD: Resource = preload("res://resources/worlds/main_world.tres")

func _init() -> void:
    var failures: Array[String] = []
    for room: Resource in MAIN_WORLD.rooms:
        failures.append_array(TILE_CONTRACT.validate_scene(room.terrain_scene_path))
    for error: String in failures:
        push_error(error)
    quit(1 if not failures.is_empty() else 0)
