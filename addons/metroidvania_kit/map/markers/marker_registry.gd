class_name MarkerRegistry
extends RefCounted

signal marker_state_changed(marker_id: StringName, state: Dictionary)

var _markers: Dictionary[StringName, Resource] = {}
var _states: Dictionary[StringName, Dictionary] = {}


func register_marker(marker: Resource) -> bool:
	if marker == null:
		return false
	var marker_id := StringName(marker.get("marker_id"))
	if marker_id.is_empty() or _markers.has(marker_id):
		return false
	_markers[marker_id] = marker
	_states[marker_id] = {
		"discovered": false,
		"active": false,
		"completed": false,
	}
	return true


func get_marker(marker_id: StringName) -> Resource:
	return _markers.get(marker_id)


func get_state(marker_id: StringName) -> Dictionary:
	return _states.get(marker_id, {}).duplicate(true)


func set_discovered(marker_id: StringName, value: bool) -> bool:
	return _set_field(marker_id, "discovered", value)


func set_active(marker_id: StringName, value: bool) -> bool:
	return _set_field(marker_id, "active", value)


func set_completed(marker_id: StringName, value: bool) -> bool:
	return _set_field(marker_id, "completed", value)


func visible_markers(context: RefCounted = null) -> Array[Resource]:
	var result: Array[Resource] = []
	for marker_id: StringName in _markers:
		var state: Dictionary = _states[marker_id]
		if not state.get("discovered", false):
			continue
		var marker: Resource = _markers[marker_id]
		var condition := marker.get("visibility_condition") as Resource
		if condition != null and (not condition.has_method("evaluate") or not condition.call("evaluate", context)):
			continue
		result.append(marker)
	return result


func to_dictionary() -> Dictionary:
	var result: Dictionary = {}
	for marker_id: StringName in _states:
		result[String(marker_id)] = _states[marker_id].duplicate(true)
	return result


func load_dictionary(data: Dictionary) -> bool:
	var parsed: Dictionary[StringName, Dictionary] = {}
	for marker_id: StringName in _markers:
		parsed[marker_id] = {
			"discovered": false,
			"active": false,
			"completed": false,
		}
	for key: Variant in data:
		var marker_id := StringName(key)
		var value: Variant = data[key]
		if not _markers.has(marker_id) or not value is Dictionary:
			return false
		for field: String in ["discovered", "active", "completed"]:
			if not value.has(field) or not value[field] is bool:
				return false
		parsed[marker_id] = (value as Dictionary).duplicate(true)
	_states = parsed
	return true


func _set_field(marker_id: StringName, field: String, value: bool) -> bool:
	if not _states.has(marker_id):
		return false
	var state: Dictionary = _states[marker_id]
	if state.get(field, false) == value:
		return false
	state[field] = value
	_states[marker_id] = state
	marker_state_changed.emit(marker_id, state.duplicate(true))
	return true
