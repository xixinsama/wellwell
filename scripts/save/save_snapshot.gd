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
var _explored_cells: Dictionary[String, bool] = {}
var _explored_chunks: Dictionary[String, bool] = {}
var _entity_states: Dictionary[String, Dictionary] = {}


func add_explored_cell(cell_id: String) -> bool:
	if cell_id.is_empty() or _explored_cells.has(cell_id):
		return false
	_explored_cells[cell_id] = true
	return true


func has_explored_cell(cell_id: String) -> bool:
	return _explored_cells.has(cell_id)


func get_explored_cells() -> Array[String]:
	var result: Array[String] = []
	result.assign(_explored_cells.keys())
	result.sort()
	return result


func add_explored_chunk(chunk_id: String) -> bool:
	if chunk_id.is_empty() or _explored_chunks.has(chunk_id):
		return false
	_explored_chunks[chunk_id] = true
	return true


func has_explored_chunk(chunk_id: String) -> bool:
	return _explored_chunks.has(chunk_id)


func get_explored_chunks() -> Array[String]:
	var result: Array[String] = []
	result.assign(_explored_chunks.keys())
	result.sort()
	return result


func set_entity_state(entity_key: String, state: Dictionary) -> void:
	if not entity_key.is_empty():
		_entity_states[entity_key] = state.duplicate(true)


func get_entity_state(entity_key: String) -> Dictionary:
	return _entity_states.get(entity_key, {}).duplicate(true)


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
		"explored_cells": get_explored_cells(),
		"explored_chunks": get_explored_chunks(),
		"entity_states": _entity_states.duplicate(true),
		"saved_unix_time": saved_unix_time,
	}


static func from_dictionary(data: Dictionary) -> RefCounted:
	var result: RefCounted = load("res://scripts/save/save_snapshot.gd").new()
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

	var explored_data: Variant = data.get("explored_cells", [])
	if not explored_data is Array:
		return null

	slot = parsed_slot
	world_id = String(data.get("world_id", ""))
	current_room_id = String(data.get("current_room_id", ""))
	respawn_room_id = String(data.get("respawn_room_id", ""))
	respawn_spawn_id = String(data.get("respawn_spawn_id", ""))
	respawn_position = Vector2(
		float(position_data["x"]),
		float(position_data["y"])
	)
	saved_unix_time = int(data.get("saved_unix_time", 0))
	_explored_cells.clear()

	for value: Variant in explored_data:
		if not value is String:
			return null
		add_explored_cell(value)

	var explored_chunks: Variant = data.get("explored_chunks", [])
	if not explored_chunks is Array:
		return null
	for value: Variant in explored_chunks:
		if not value is String:
			return null
		add_explored_chunk(value)

	var entity_states: Variant = data.get("entity_states", {})
	if not entity_states is Dictionary:
		return null
	for key: Variant in entity_states.keys():
		if not key is String or not entity_states[key] is Dictionary:
			return null
		set_entity_state(key, entity_states[key])

	return self
