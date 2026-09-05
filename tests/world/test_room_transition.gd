extends Node

const WORLD_DATA := preload("res://scripts/world/world_data.gd")
const ROOM_DATA := preload("res://scripts/world/room_data.gd")
const ROOM_TRANSITION := preload("res://scripts/world/room_transition.gd")
const ENTRANCE := preload("res://scripts/world/room_entrance.gd")

func run() -> Array[String]:
	var failures: Array[String] = []
	var a: Resource = ROOM_DATA.new()
	a.room_id = "a"
	var b: Resource = ROOM_DATA.new()
	b.room_id = "b"
	var world: Resource = WORLD_DATA.new()
	world.rooms.assign([a, b])
	var entrance: Node = ENTRANCE.new()
	entrance.target_room_id = "b"
	entrance.target_spawn_id = "spawn_b"
	var resolved: Dictionary = ROOM_TRANSITION.resolve(world, "a", entrance)
	if resolved.get("to_room_id", "") != "b" or resolved.get("to_spawn_id", "") != "spawn_b":
		failures.append("room transition did not resolve entrance target")
	entrance.target_room_id = "missing"
	if not ROOM_TRANSITION.resolve(world, "a", entrance).is_empty():
		failures.append("invalid room transition was accepted")
	entrance.free()
	return failures
