extends SceneTree

const WORLD_VALIDATION := preload("res://addons/platformer_kit/world/data/world_validation.gd")
const TILE_CONTRACT := preload("res://addons/platformer_kit/world/data/tile_layer_contract.gd")

func _init() -> void:
    var failures: Array[String] = []
    for error: String in failures:
        push_error(error)
    quit(1 if not failures.is_empty() else 0)
