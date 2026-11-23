class_name MapTracker
extends Node

signal room_tracked(room_id: StringName)

var runtime: RefCounted
var reveal_rules: Array[Resource] = []


func configure(map_runtime: RefCounted, rules: Array[Resource] = []) -> bool:
	if map_runtime == null or not map_runtime.has_method("enter_room"):
		return false
	runtime = map_runtime
	reveal_rules = rules.duplicate()
	return true


func track_room(room_id: StringName) -> bool:
	if runtime == null or not runtime.call("enter_world_room", room_id):
		return false
	var map_room_id := StringName(runtime.get("current_room_id"))
	for rule: Resource in reveal_rules:
		if rule != null and rule.has_method("apply"):
			rule.call("apply", runtime.get("definition"), runtime.get("discovery"), map_room_id)
	room_tracked.emit(map_room_id)
	return true
