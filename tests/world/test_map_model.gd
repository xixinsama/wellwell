extends Node

const WORLD_DATA := preload("res://scripts/world/world_data.gd")
const ROOM_DATA := preload("res://scripts/world/room_data.gd")
const MAP_MODEL := preload("res://scripts/world/map_model.gd")

func run() -> Array[String]:
	var failures: Array[String] = []
	var room: Resource = ROOM_DATA.new()
	room.room_id = "room_a"
	room.display_name = "Start"
	room.room_origin_chunk = Vector2i(2, 1)
	room.room_size_chunks = Vector2i(2, 1)
	var world: Resource = WORLD_DATA.new()
	world.world_id = "world_01"
	world.rooms.assign([room])
	var model: Dictionary = MAP_MODEL.build(world, ["world_01:chunk:2,1"], "room_a")
	if model.rooms.size() != 1:
		failures.append("map model did not include room")
	if not model.rooms[0].current:
		failures.append("map model did not mark current room")
	if not model.rooms[0].chunks[0].explored or model.rooms[0].chunks[1].explored:
		failures.append("map model explored chunks were wrong")
	return failures
