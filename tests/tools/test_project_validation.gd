extends Node

const TILE_CONTRACT := preload("res://scripts/world/tile_layer_contract.gd")

func run() -> Array[String]:
	var failures: Array[String] = []
	var errors := TILE_CONTRACT.validate_scene("res://scenes/game.tscn")
	if not errors.is_empty():
		failures.append("existing game scene violates required tile layer contract")
	return failures
