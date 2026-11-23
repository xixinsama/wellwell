class_name StateMachine
extends RefCounted

signal state_changed(previous: StringName, current: StringName)

var current_state: StringName = &""

var _states: Dictionary[StringName, Dictionary] = {}


func add_state(
	state_id: StringName,
	on_enter: Callable = Callable(),
	on_exit: Callable = Callable()
) -> bool:
	if state_id.is_empty() or _states.has(state_id):
		return false
	_states[state_id] = {"enter": on_enter, "exit": on_exit}
	return true


func has_state(state_id: StringName) -> bool:
	return _states.has(state_id)


func transition_to(state_id: StringName) -> bool:
	if not _states.has(state_id):
		return false
	if current_state == state_id:
		return true
	var previous := current_state
	if not previous.is_empty():
		_call_state_callback(previous, "exit")
	current_state = state_id
	_call_state_callback(current_state, "enter")
	state_changed.emit(previous, current_state)
	return true


func _call_state_callback(state_id: StringName, callback_name: String) -> void:
	var callback: Callable = _states[state_id].get(callback_name, Callable())
	if callback.is_valid():
		callback.call()

