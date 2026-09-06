@tool
class_name WorldEntity
extends Node2D

@export var entity_id := ""
@export var entity_type := "entity"
@export var persistent := false
@export var map_visible := false

var room_id := ""

func setup_entity(context: Dictionary) -> void:
	room_id = String(context.get("room_id", room_id))
	var world_id := String(context.get("world_id", ""))
	if not world_id.is_empty():
		set_meta("world_id", world_id)

func get_save_key() -> String:
	if room_id.is_empty() or entity_id.is_empty():
		return entity_id
	return "%s:%s:%s" % [String(get_meta("world_id", "world")), room_id, entity_id]

func get_save_state() -> Dictionary:
	return {}

func apply_save_state(_state: Dictionary) -> void:
	pass

func get_map_marker() -> Dictionary:
	if not map_visible:
		return {}
	return {"entity_id": entity_id, "entity_type": entity_type, "position": global_position}
