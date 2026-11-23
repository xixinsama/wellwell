class_name MetroidvaniaSaveAdapter
extends RefCounted

const MODULE_ID: StringName = &"metroidvania_kit"


func capture(
	snapshot: RefCounted,
	progression: RefCounted,
	discovery: RefCounted,
	markers: RefCounted,
	world_state: RefCounted,
	fast_travel: RefCounted
) -> bool:
	if snapshot == null or not snapshot.has_method("set_module_state"):
		return false
	var state := {
		"progression": _capture_component(progression),
		"rooms": _capture_component(discovery),
		"markers": _capture_component(markers),
		"world_state": _capture_component(world_state),
		"fast_travel": _capture_component(fast_travel),
	}
	return snapshot.call("set_module_state", MODULE_ID, state)


func restore(
	snapshot: RefCounted,
	progression: RefCounted,
	discovery: RefCounted,
	markers: RefCounted,
	world_state: RefCounted,
	fast_travel: RefCounted
) -> bool:
	if snapshot == null or not snapshot.has_method("get_module_state"):
		return false
	var state: Dictionary = snapshot.call("get_module_state", MODULE_ID)
	if state.is_empty():
		return false
	return restore_state(state, progression, discovery, markers, world_state, fast_travel)


func reset(
	progression: RefCounted,
	discovery: RefCounted,
	markers: RefCounted,
	world_state: RefCounted,
	fast_travel: RefCounted
) -> bool:
	return restore_state(
		{
			"progression": {},
			"rooms": {},
			"markers": {},
			"world_state": {},
			"fast_travel": {},
		},
		progression,
		discovery,
		markers,
		world_state,
		fast_travel
	)


func restore_state(
	state: Dictionary,
	progression: RefCounted,
	discovery: RefCounted,
	markers: RefCounted,
	world_state: RefCounted,
	fast_travel: RefCounted
) -> bool:
	var entries: Array[Array] = [
		["progression", progression],
		["rooms", discovery],
		["markers", markers],
		["world_state", world_state],
		["fast_travel", fast_travel],
	]
	var previous_states: Array[Dictionary] = []
	var touched_components: Array[RefCounted] = []
	for entry: Array in entries:
		var component := entry[1] as RefCounted
		if component == null:
			continue
		var component_state: Variant = state.get(entry[0], null)
		if not component_state is Dictionary or not component.has_method("load_dictionary"):
			_rollback(touched_components, previous_states)
			return false
		previous_states.append(_capture_component(component))
		touched_components.append(component)
		if not component.call("load_dictionary", component_state):
			_rollback(touched_components, previous_states)
			return false
	return true


func _capture_component(component: RefCounted) -> Dictionary:
	if component == null or not component.has_method("to_dictionary"):
		return {}
	return component.call("to_dictionary")


func _rollback(components: Array[RefCounted], states: Array[Dictionary]) -> void:
	for index: int in range(components.size() - 1, -1, -1):
		components[index].call("load_dictionary", states[index])
