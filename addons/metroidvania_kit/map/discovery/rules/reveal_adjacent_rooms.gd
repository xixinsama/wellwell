class_name RevealAdjacentRooms
extends "res://addons/metroidvania_kit/map/discovery/reveal_rule.gd"


func apply(definition: Resource, discovery: RefCounted, current_room_id: StringName) -> Array[StringName]:
	if definition == null:
		return []
	var room_ids: Array[StringName] = definition.call("get_neighbors", current_room_id)
	return _discover(discovery, room_ids)
