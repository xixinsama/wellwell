class_name SwitchEntity
extends "res://addons/platformer_kit/world/entities/world_entity.gd"

var activated := false

func _ready() -> void:
	entity_type = "switch"
	persistent = true

func toggle() -> void:
	activated = not activated
	commit_save_state()

func get_save_state() -> Dictionary:
	return {"activated": activated}

func apply_save_state(state: Dictionary) -> void:
	activated = bool(state.get("activated", false))
