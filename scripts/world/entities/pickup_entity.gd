class_name PickupEntity
extends "res://scripts/world/entities/world_entity.gd"

var collected := false

func _ready() -> void:
	entity_type = "pickup"
	persistent = true

func collect() -> void:
	collected = true
	visible = false
	commit_save_state()

func get_save_state() -> Dictionary:
	return {"collected": collected}

func apply_save_state(state: Dictionary) -> void:
	collected = bool(state.get("collected", false))
	visible = not collected
