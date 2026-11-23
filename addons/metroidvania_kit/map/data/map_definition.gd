class_name MapDefinition
extends Resource

@export var map_id: StringName
@export var regions: Array[Resource] = []
@export var rooms: Array[Resource] = []
@export var connections: Array[Resource] = []


func get_room(room_id: StringName) -> Resource:
	for room: Resource in rooms:
		if room != null and StringName(room.get("room_id")) == room_id:
			return room
	return null


func get_region(region_id: StringName) -> Resource:
	for region: Resource in regions:
		if region != null and StringName(region.get("region_id")) == region_id:
			return region
	return null


func get_room_by_world_id(world_room_id: StringName) -> Resource:
	for room: Resource in rooms:
		if room != null and StringName(room.call("get_world_room_id")) == world_room_id:
			return room
	return null


func get_room_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for room: Resource in rooms:
		if room == null:
			continue
		var room_id := StringName(room.get("room_id"))
		if not room_id.is_empty():
			result.append(room_id)
	result.sort()
	return result


func get_neighbors(room_id: StringName) -> Array[StringName]:
	var unique: Dictionary[StringName, bool] = {}
	for connection: Resource in connections:
		if connection == null:
			continue
		var from_id := StringName(connection.get("from_room_id"))
		var to_id := StringName(connection.get("to_room_id"))
		if from_id == room_id and not to_id.is_empty():
			unique[to_id] = true
		if not bool(connection.get("one_way")) and to_id == room_id and not from_id.is_empty():
			unique[from_id] = true
	var result: Array[StringName] = []
	result.assign(unique.keys())
	result.sort()
	return result


func get_region_room_ids(region_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for room: Resource in rooms:
		if room != null and StringName(room.get("region_id")) == region_id:
			result.append(StringName(room.get("room_id")))
	result.sort()
	return result
