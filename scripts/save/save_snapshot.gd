class_name SaveSnapshot
extends RefCounted

const FORMAT_VERSION := 1

var slot := 1
var respawn_position := Vector2.ZERO
var saved_unix_time := 0
var _explored_cells: Dictionary[String, bool] = {}


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


func to_dictionary() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"slot": slot,
		"respawn_position": {
			"x": respawn_position.x,
			"y": respawn_position.y,
		},
		"explored_cells": get_explored_cells(),
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

	return self
