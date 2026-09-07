@tool
class_name RoomEntrance
extends "res://scripts/world/entities/world_entity.gd"

signal transition_requested(entrance: RoomEntrance)

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	entity_type = "room_entrance"

func request_transition() -> void:
	transition_requested.emit(self)
