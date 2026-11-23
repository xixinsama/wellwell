class_name MapDiscovery
extends RefCounted

signal state_changed(room_id: StringName, previous_state: int, current_state: int)

enum State {
	HIDDEN,
	DISCOVERED,
	VISITED,
	CLEARED,
}

var _states: Dictionary[StringName, int] = {}


func get_state(room_id: StringName) -> int:
	return _states.get(room_id, State.HIDDEN)


func set_state(room_id: StringName, state: int) -> bool:
	if room_id.is_empty() or state < State.HIDDEN or state > State.CLEARED:
		return false
	var previous := get_state(room_id)
	if state <= previous:
		return false
	_states[room_id] = state
	state_changed.emit(room_id, previous, state)
	return true


func mark_discovered(room_id: StringName) -> bool:
	return set_state(room_id, State.DISCOVERED)


func mark_visited(room_id: StringName) -> bool:
	return set_state(room_id, State.VISITED)


func mark_cleared(room_id: StringName) -> bool:
	return set_state(room_id, State.CLEARED)


func is_visible(room_id: StringName) -> bool:
	return get_state(room_id) >= State.DISCOVERED


func to_dictionary() -> Dictionary:
	var result: Dictionary = {}
	for room_id: StringName in _states:
		result[String(room_id)] = _states[room_id]
	return result


func load_dictionary(data: Dictionary) -> bool:
	var parsed: Dictionary[StringName, int] = {}
	for key: Variant in data:
		var room_id := StringName(key)
		var raw_state: Variant = data[key]
		if not raw_state is int and not (raw_state is float and is_equal_approx(raw_state, floorf(raw_state))):
			return false
		var state := int(raw_state)
		if room_id.is_empty() or state < State.HIDDEN or state > State.CLEARED:
			return false
		if state > State.HIDDEN:
			parsed[room_id] = state
	_states = parsed
	return true
