class_name FastTravelRegistry
extends RefCounted

var _points: Dictionary[StringName, Resource] = {}
var _unlocked: Dictionary[StringName, bool] = {}


func register_point(point: Resource) -> bool:
	if point == null:
		return false
	var travel_id := StringName(point.get("travel_id"))
	var room_id := StringName(point.get("room_id"))
	var spawn_id := StringName(point.get("spawn_id"))
	if travel_id.is_empty() or room_id.is_empty() or spawn_id.is_empty() or _points.has(travel_id):
		return false
	_points[travel_id] = point
	return true


func unlock(travel_id: StringName) -> bool:
	if not _points.has(travel_id) or _unlocked.has(travel_id):
		return false
	_unlocked[travel_id] = true
	return true


func is_unlocked(travel_id: StringName) -> bool:
	return _unlocked.has(travel_id)


func can_travel(travel_id: StringName, context: RefCounted) -> bool:
	if not is_unlocked(travel_id):
		return false
	var point: Resource = _points[travel_id]
	var condition := point.get("condition") as Resource
	return condition == null or (condition.has_method("evaluate") and condition.call("evaluate", context))


func get_destination(travel_id: StringName, context: RefCounted) -> Dictionary:
	if not can_travel(travel_id, context):
		return {}
	var point: Resource = _points[travel_id]
	return {
		"room_id": StringName(point.get("room_id")),
		"spawn_id": StringName(point.get("spawn_id")),
	}


func to_dictionary() -> Dictionary:
	var result: Array[String] = []
	for travel_id: StringName in _unlocked:
		result.append(String(travel_id))
	result.sort()
	return {"unlocked": result}


func load_dictionary(data: Dictionary) -> bool:
	var unlocked: Variant = data.get("unlocked", [])
	if not unlocked is Array:
		return false
	var parsed: Dictionary[StringName, bool] = {}
	for value: Variant in unlocked:
		var travel_id := StringName(value)
		if not _points.has(travel_id):
			return false
		parsed[travel_id] = true
	_unlocked = parsed
	return true
