extends SceneTree

const WORLD_VALIDATION := preload("res://scripts/world/world_validation.gd")
const TILE_CONTRACT := preload("res://scripts/world/tile_layer_contract.gd")

func _init() -> void:
	var failures: Array[String] = []
	failures.append_array(TILE_CONTRACT.validate_scene("res://scenes/game.tscn"))
	for error: String in failures:
		push_error(error)
	quit(1 if not failures.is_empty() else 0)
