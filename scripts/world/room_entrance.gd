@tool
class_name RoomEntrance
extends "res://scripts/world/world_entity.gd"

# Serialized for one migration phase. WorldData connections are authoritative.
@export_storage var target_room_id := ""
@export_storage var target_spawn_id := ""

signal transition_requested(entrance: RoomEntrance)

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	entity_type = "room_entrance"

func request_transition() -> void:
	transition_requested.emit(self)
