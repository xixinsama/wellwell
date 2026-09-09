class_name MetroidvaniaWorldState
extends RefCounted

var _states: Dictionary[StringName, Dictionary] = {}


func set_state(stable_id: StringName, state: Dictionary) -> bool:
	if stable_id.is_empty():
		return false
	_states[stable_id] = state.duplicate(true)
	return true


func get_state(stable_id: StringName) -> Dictionary:
	return _states.get(stable_id, {}).duplicate(true)


func erase_state(stable_id: StringName) -> bool:
	return _states.erase(stable_id)


func to_dictionary() -> Dictionary:
	var result: Dictionary = {}
	for stable_id: StringName in _states:
		result[String(stable_id)] = _states[stable_id].duplicate(true)
	return result


func load_dictionary(data: Dictionary) -> bool:
	var parsed: Dictionary[StringName, Dictionary] = {}
	for key: Variant in data:
		if String(key).is_empty() or not data[key] is Dictionary:
			return false
		parsed[StringName(key)] = (data[key] as Dictionary).duplicate(true)
	_states = parsed
	return true
