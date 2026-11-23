class_name RevealAll
extends "res://addons/metroidvania_kit/map/discovery/reveal_rule.gd"


func apply(definition: Resource, discovery: RefCounted, _current_room_id: StringName) -> Array[StringName]:
	if definition == null:
		return []
	var room_ids: Array[StringName] = definition.call("get_room_ids")
	return _discover(discovery, room_ids)
