class_name RevealRegion
extends "res://addons/metroidvania_kit/map/discovery/reveal_rule.gd"


func apply(definition: Resource, discovery: RefCounted, current_room_id: StringName) -> Array[StringName]:
	if definition == null:
		return []
	var current: Resource = definition.call("get_room", current_room_id)
	if current == null:
		return []
	var room_ids: Array[StringName] = definition.call("get_region_room_ids", StringName(current.get("region_id")))
	return _discover(discovery, room_ids)
