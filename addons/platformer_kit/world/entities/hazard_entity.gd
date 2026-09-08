class_name HazardEntity
extends "res://addons/platformer_kit/world/entities/world_entity.gd"

@export var damage := 1

func _ready() -> void:
	entity_type = "hazard"
