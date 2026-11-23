class_name RevealByRadius
extends "res://addons/metroidvania_kit/map/discovery/reveal_rule.gd"

@export_range(0, 100, 1) var radius := 1


func apply(definition: Resource, discovery: RefCounted, current_room_id: StringName) -> Array[StringName]:
	if definition == null:
		return []
	var current: Resource = definition.call("get_room", current_room_id)
	if current == null:
		return []
	var origin := Vector2i(current.get("map_position"))
	var room_ids: Array[StringName] = []
	for room: Resource in definition.get("rooms"):
		if room == null:
			continue
		var position := Vector2i(room.get("map_position"))
		if absi(position.x - origin.x) + absi(position.y - origin.y) <= radius:
			room_ids.append(StringName(room.get("room_id")))
	return _discover(discovery, room_ids)
