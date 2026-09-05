class_name RoomEntrance
extends "res://scripts/world/world_entity.gd"

@export var target_room_id := ""
@export var target_spawn_id := ""

signal transition_requested(entrance: RoomEntrance)

func _ready() -> void:
	entity_type = "room_entrance"

func request_transition() -> void:
	transition_requested.emit(self)
