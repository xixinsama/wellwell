extends Node

const WORLD_DATA := preload("res://scripts/world/world_data.gd")
const ROOM_DATA := preload("res://scripts/world/room_data.gd")
const ROOM_TRANSITION := preload("res://scripts/world/room_transition.gd")
const ENTRANCE := preload("res://scripts/world/room_entrance.gd")
const ROOM_CONNECTION_DATA := preload("res://scripts/world/room_connection_data.gd")

func run() -> Array[String]:
	var failures: Array[String] = []
	var a: Resource = ROOM_DATA.new()
	a.room_id = "a"
	var b: Resource = ROOM_DATA.new()
	b.room_id = "b"
	var world: Resource = WORLD_DATA.new()
	world.rooms.assign([a, b])
	var entrance: Node = ENTRANCE.new()
	entrance.entity_id = "exit_a"
	entrance.target_room_id = "b"
	entrance.target_spawn_id = "spawn_b"
	var connection: Resource = ROOM_CONNECTION_DATA.new()
	connection.from_room_id = "a"
	connection.from_entrance_id = "exit_a"
	connection.to_room_id = "b"
	connection.to_spawn_id = "spawn_b"
	world.connections.assign([connection])
	var resolved: Dictionary = ROOM_TRANSITION.resolve(world, "a", entrance)
	if resolved.get("to_room_id", "") != "b" or resolved.get("to_spawn_id", "") != "spawn_b":
		failures.append("room transition did not resolve entrance target")
	entrance.target_spawn_id = "wrong_spawn"
	if not ROOM_TRANSITION.resolve(world, "a", entrance).is_empty():
		failures.append("room transition accepted entrance data that disagreed with its connection")
	entrance.target_spawn_id = "spawn_b"
	entrance.entity_id = "unregistered_exit"
	if not ROOM_TRANSITION.resolve(world, "a", entrance).is_empty():
		failures.append("room transition accepted an entrance without a world connection")
	entrance.entity_id = "exit_a"
	entrance.target_room_id = "missing"
	if not ROOM_TRANSITION.resolve(world, "a", entrance).is_empty():
		failures.append("invalid room transition was accepted")
	entrance.free()
	return failures
