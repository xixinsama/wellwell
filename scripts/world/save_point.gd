class_name SavePoint
extends "res://scripts/world/world_entity.gd"

@export var interaction_required := false
var activated := false

func _ready() -> void:
	entity_type = "save_point"
	persistent = true

func activate() -> void:
	activated = true

func get_save_state() -> Dictionary:
	return {"activated": activated}

func apply_save_state(state: Dictionary) -> void:
	activated = bool(state.get("activated", false))
