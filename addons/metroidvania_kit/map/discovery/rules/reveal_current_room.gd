class_name RevealCurrentRoom
extends "res://addons/metroidvania_kit/map/discovery/reveal_rule.gd"


func apply(definition: Resource, discovery: RefCounted, current_room_id: StringName) -> Array[StringName]:
	if definition == null or discovery == null or definition.call("get_room", current_room_id) == null:
		return []
	return [current_room_id] if discovery.call("mark_visited", current_room_id) else []
