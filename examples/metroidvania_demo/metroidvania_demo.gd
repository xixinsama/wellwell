extends Node2D

const MAP_DEFINITION := preload("res://addons/metroidvania_kit/map/data/map_definition.gd")
const MAP_REGION := preload("res://addons/metroidvania_kit/map/data/map_region.gd")
const MAP_ROOM := preload("res://addons/metroidvania_kit/map/data/map_room.gd")
const MAP_CONNECTION := preload("res://addons/metroidvania_kit/map/data/map_connection.gd")
const MAP_DISCOVERY := preload("res://addons/metroidvania_kit/map/discovery/map_discovery.gd")
const MAP_RUNTIME := preload("res://addons/metroidvania_kit/map/runtime/map_runtime.gd")
const REVEAL_ADJACENT := preload("res://addons/metroidvania_kit/map/discovery/rules/reveal_adjacent_rooms.gd")


func _ready() -> void:
	var room_a: Resource = _room(&"demo:start", &"demo", Vector2i(1, 2), Vector2i(2, 1))
	var room_b: Resource = _room(&"demo:hall", &"demo", Vector2i(4, 2), Vector2i(3, 1))
	var room_c: Resource = _room(&"demo:secret", &"demo", Vector2i(4, 4), Vector2i.ONE)
	var region: Resource = MAP_REGION.new()
	region.region_id = &"demo"
	var region_room_ids: Array[StringName] = [&"demo:start", &"demo:hall", &"demo:secret"]
	region.room_ids = region_room_ids
	var connection: Resource = MAP_CONNECTION.new()
	connection.from_room_id = &"demo:start"
	connection.to_room_id = &"demo:hall"
	var definition: Resource = MAP_DEFINITION.new()
	definition.map_id = &"demo"
	var rooms: Array[Resource] = [room_a, room_b, room_c]
	var regions: Array[Resource] = [region]
	var connections: Array[Resource] = [connection]
	definition.rooms = rooms
	definition.regions = regions
	definition.connections = connections
	var discovery: RefCounted = MAP_DISCOVERY.new()
	var runtime: RefCounted = MAP_RUNTIME.new()
	runtime.configure(definition, discovery)
	runtime.enter_room(&"demo:start")
	REVEAL_ADJACENT.new().apply(definition, discovery, &"demo:start")
	$MapPanel/MapView.bind_runtime(runtime)
	$MapPanel/MapView.focus_room(&"demo:start")
	$Status.text = "Current: demo:start\nExploration: %d%%" % roundi(runtime.exploration_ratio() * 100.0)


func _room(id: StringName, region_id: StringName, position: Vector2i, room_size: Vector2i) -> Resource:
	var room: Resource = MAP_ROOM.new()
	room.room_id = id
	room.region_id = region_id
	room.map_position = position
	room.map_size = room_size
	return room
