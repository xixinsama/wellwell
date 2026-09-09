class_name RevealRule
extends Resource


func apply(_definition: Resource, _discovery: RefCounted, _current_room_id: StringName) -> Array[StringName]:
	return []


func _discover(discovery: RefCounted, room_ids: Array[StringName]) -> Array[StringName]:
	var changed: Array[StringName] = []
	if discovery == null:
		return changed
	for room_id: StringName in room_ids:
		if discovery.call("mark_discovered", room_id):
			changed.append(room_id)
	return changed
