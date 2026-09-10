class_name SaveSnapshot
extends RefCounted

const FORMAT_VERSION := 1

var slot := 1
var world_id := ""
var current_room_id := ""
var respawn_room_id := ""
var respawn_spawn_id := ""
var respawn_position := Vector2.ZERO
var saved_unix_time := 0
var _entity_states: Dictionary[String, Dictionary] = {}
var _module_states: Dictionary[StringName, Dictionary] = {}


func set_respawn(room_id: String, spawn_id: String, position: Vector2) -> bool:
	if room_id.is_empty() or spawn_id.is_empty() or not position.is_finite():
		return false
	respawn_room_id = room_id
	respawn_spawn_id = spawn_id
	respawn_position = position
	return true


func set_entity_state(entity_key: String, state: Dictionary) -> void:
	if not entity_key.is_empty():
		_entity_states[entity_key] = state.duplicate(true)


func get_entity_state(entity_key: String) -> Dictionary:
	return _entity_states.get(entity_key, {}).duplicate(true)


func set_module_state(module_id: StringName, state: Dictionary) -> bool:
	if module_id.is_empty():
		return false
	_module_states[module_id] = state.duplicate(true)
	return true


func get_module_state(module_id: StringName) -> Dictionary:
	return _module_states.get(module_id, {}).duplicate(true)


func to_dictionary() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"slot": slot,
		"world_id": world_id,
		"current_room_id": current_room_id,
		"respawn_room_id": respawn_room_id,
		"respawn_spawn_id": respawn_spawn_id,
		"respawn_position": {
			"x": respawn_position.x,
			"y": respawn_position.y,
		},
		"entity_states": _entity_states.duplicate(true),
		"module_states": _serialize_module_states(),
		"saved_unix_time": saved_unix_time,
	}


static func from_dictionary(data: Dictionary) -> RefCounted:
	var result: RefCounted = load("res://addons/platformer_kit/save/save_snapshot.gd").new()
	return result.load_from_dictionary(data)


func load_from_dictionary(data: Dictionary) -> RefCounted:
	if int(data.get("format_version", -1)) != FORMAT_VERSION:
		return null
	var parsed_slot := int(data.get("slot", 0))
	if parsed_slot < 1 or parsed_slot > 3:
		return null
	var position_data: Variant = data.get("respawn_position", null)
	if not position_data is Dictionary:
		return null
	if not position_data.has("x") or not position_data.has("y"):
		return null
	var parsed_entity_states: Dictionary[String, Dictionary] = {}
	var entity_states: Variant = data.get("entity_states", {})
	if not entity_states is Dictionary:
		return null
	for key: Variant in entity_states.keys():
		if not key is String or not entity_states[key] is Dictionary:
			return null
		if not String(key).is_empty():
			parsed_entity_states[String(key)] = (entity_states[key] as Dictionary).duplicate(true)
	var parsed_module_states: Dictionary[StringName, Dictionary] = {}
	var module_states: Variant = data.get("module_states", {})
	if not module_states is Dictionary:
		return null
	for key: Variant in module_states:
		if String(key).is_empty() or not module_states[key] is Dictionary:
			return null
		parsed_module_states[StringName(key)] = (module_states[key] as Dictionary).duplicate(true)

	slot = parsed_slot
	world_id = String(data.get("world_id", ""))
	current_room_id = String(data.get("current_room_id", ""))
	respawn_room_id = String(data.get("respawn_room_id", ""))
	respawn_spawn_id = String(data.get("respawn_spawn_id", ""))
	respawn_position = Vector2(float(position_data["x"]), float(position_data["y"]))
	saved_unix_time = int(data.get("saved_unix_time", 0))
	_entity_states = parsed_entity_states
	_module_states = parsed_module_states
	return self


func _serialize_module_states() -> Dictionary:
	var result: Dictionary = {}
	for module_id: StringName in _module_states:
		result[String(module_id)] = _module_states[module_id].duplicate(true)
	return result
