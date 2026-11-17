class_name MapDefinitionBuilder
extends RefCounted

## Builds the map model from the same data the game streams: WorldData
## placements decide where a room sits on the map, RoomData decides its size.
## Nothing here is authored by hand, so the map can never drift from the level.

const MAP_DEFINITION_SCRIPT: Script = preload("res://addons/metroidvania_kit/map/data/map_definition.gd")
const MAP_ROOM_SCRIPT: Script = preload("res://addons/metroidvania_kit/map/data/map_room.gd")
const MAP_CONNECTION_SCRIPT: Script = preload("res://addons/metroidvania_kit/map/data/map_connection.gd")
const MAP_REGION_SCRIPT: Script = preload("res://addons/metroidvania_kit/map/data/map_region.gd")

## Fog and terrain both use 8 px cells inside a 320x180 chunk.
const CELLS_PER_CHUNK := Vector2i(40, 23)


static func from_world(world: Resource) -> Resource:
	if world == null or not world.has_method("get_room_ids"):
		return null
	var definition: Resource = MAP_DEFINITION_SCRIPT.new()
	definition.map_id = StringName(String(world.get("world_id")))
	var start_room_id := String(world.get("start_room_id"))
	definition.set_meta("start_room_id", start_room_id)

	var rooms: Array[Resource] = []
	for room_id: String in world.get_room_ids():
		var room: Resource = world.get_room(room_id)
		if room == null:
			continue
		var map_room: Resource = MAP_ROOM_SCRIPT.new()
		map_room.room_id = StringName(room_id)
		map_room.world_room_id = StringName(room_id)
		map_room.region_id = StringName(String(room.get("region_id"))) if _has_property(room, "region_id") else StringName()
		map_room.map_position = world.get_room_origin_chunk(room_id)
		map_room.map_size = room.room_size_chunks
		map_room.metadata = {
			"terrain_scene_path": String(room.terrain_scene_path),
			"display_name": String(room.display_name),
		}
		rooms.append(map_room)
	definition.rooms = rooms

	var connections: Array[Resource] = []
	for connection: Resource in world.get("connections"):
		if connection == null:
			continue
		var from_room := String(connection.get("from_room_id"))
		var to_room := String(connection.get("to_room_id"))
		if not world.has_room(from_room) or not world.has_room(to_room):
			continue
		var map_connection: Resource = MAP_CONNECTION_SCRIPT.new()
		map_connection.from_room_id = StringName(from_room)
		map_connection.to_room_id = StringName(to_room)
		map_connection.connection_id = StringName("%s:%s" % [from_room, to_room])
		connections.append(map_connection)
	definition.connections = connections

	var regions: Array[Resource] = []
	for region: Resource in world.get("regions"):
		if region == null:
			continue
		var map_region: Resource = MAP_REGION_SCRIPT.new()
		map_region.region_id = StringName(String(region.get("region_id")))
		map_region.display_name = String(region.get("display_name"))
		regions.append(map_region)
	definition.regions = regions
	return definition


static func room_cell_origin(room: Resource) -> Vector2i:
	return Vector2i(room.get("map_position")) * CELLS_PER_CHUNK


static func room_cell_size(room: Resource) -> Vector2i:
	return Vector2i(room.get("map_size")) * CELLS_PER_CHUNK


static func _has_property(object: Object, property_name: String) -> bool:
	for property_info: Dictionary in object.get_property_list():
		if String(property_info.get("name", "")) == property_name:
			return true
	return false
