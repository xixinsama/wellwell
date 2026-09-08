@tool
class_name WorldEntity
extends Node2D

@export var entity_id := ""
@export var persistent_id: StringName
@export var entity_type := "entity"
@export var persistent := false
@export var map_visible := false

var room_id := ""
var _entity_state_sink: Object

func setup_entity(context: Dictionary) -> void:
	room_id = String(context.get("room_id", room_id))
	_entity_state_sink = context.get("entity_state_sink") as Object
	var world_id := String(context.get("world_id", ""))
	if not world_id.is_empty():
		set_meta("world_id", world_id)


func commit_save_state() -> bool:
	if not persistent or _entity_state_sink == null or not is_instance_valid(_entity_state_sink):
		return false
	if not _entity_state_sink.has_method("set_entity_state"):
		return false
	_entity_state_sink.call("set_entity_state", get_save_key(), get_save_state())
	return true

func get_save_key() -> String:
	if not persistent_id.is_empty():
		return String(persistent_id)
	if room_id.is_empty() or entity_id.is_empty():
		return entity_id
	return "%s:%s:%s" % [String(get_meta("world_id", "world")), room_id, entity_id]

func get_save_state() -> Dictionary:
	return {}

func apply_save_state(_state: Dictionary) -> void:
	pass

func get_persistent_id() -> StringName:
	return persistent_id

func capture_save_state() -> Dictionary:
	return get_save_state()

func restore_save_state(state: Dictionary) -> void:
	apply_save_state(state)

func get_map_marker() -> Dictionary:
	if not map_visible:
		return {}
	return {"entity_id": entity_id, "entity_type": entity_type, "position": global_position}
