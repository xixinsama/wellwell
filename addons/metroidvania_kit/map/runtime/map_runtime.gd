class_name MapRuntime
extends RefCounted

signal current_room_changed(previous_room_id: StringName, current_room_id: StringName)

var definition: Resource
var discovery: RefCounted
var markers: RefCounted
var current_room_id: StringName
var current_region_id: StringName


func configure(map_definition: Resource, map_discovery: RefCounted, marker_registry: RefCounted = null) -> bool:
	if map_definition == null or map_discovery == null:
		return false
	definition = map_definition
	discovery = map_discovery
	markers = marker_registry
	return true


func enter_room(room_id: StringName) -> bool:
	if definition == null or definition.call("get_room", room_id) == null:
		return false
	var previous := current_room_id
	current_room_id = room_id
	var room: Resource = definition.call("get_room", room_id)
	current_region_id = StringName(room.get("region_id"))
	discovery.call("mark_visited", room_id)
	if previous != current_room_id:
		current_room_changed.emit(previous, current_room_id)
	return true


func enter_world_room(world_room_id: StringName) -> bool:
	if definition == null:
		return false
	var room: Resource = definition.call("get_room_by_world_id", world_room_id)
	if room == null:
		return false
	return enter_room(StringName(room.get("room_id")))


func get_room_state(room_id: StringName) -> int:
	return 0 if discovery == null else int(discovery.call("get_state", room_id))


func get_map_room(room_id: StringName) -> Resource:
	return null if definition == null else definition.call("get_room", room_id)


func exploration_ratio() -> float:
	if definition == null:
		return 0.0
	var room_ids: Array[StringName] = definition.call("get_room_ids")
	if room_ids.is_empty():
		return 0.0
	var visible_count := 0
	for room_id: StringName in room_ids:
		if get_room_state(room_id) > 0:
			visible_count += 1
	return float(visible_count) / float(room_ids.size())
