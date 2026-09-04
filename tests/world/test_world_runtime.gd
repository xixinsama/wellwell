extends Node

const ROOM_DATA: Script = preload("res://scripts/world/room_data.gd")
const ROOM_CONNECTION_DATA: Script = preload("res://scripts/world/room_connection_data.gd")
const WORLD_DATA: Script = preload("res://scripts/world/world_data.gd")
const WORLD_RUNTIME: Script = preload("res://scripts/world/world_runtime.gd")

const FIXTURE_PATH := "user://world_runtime_room_fixture.tscn"
const MISSING_FIXTURE_PATH := "user://missing_world_runtime_room_fixture.tscn"


func run() -> Array[String]:
	var failures: Array[String] = []
	var save_error := _save_room_fixture()
	if save_error != OK:
		failures.append("world runtime fixture save failed: %d" % save_error)
		return failures
	_assert_world_runtime_loads_current_and_adjacent_rooms(failures)
	_assert_world_runtime_rejects_unknown_room(failures)
	_assert_world_runtime_rejects_unloadable_current_room(failures)
	_assert_world_runtime_rejects_wrong_resource_type(failures)
	return failures


func _assert_world_runtime_loads_current_and_adjacent_rooms(failures: Array[String]) -> void:
	var room_a: Resource = _make_room("room_a", Vector2i(0, 0))
	room_a.adjacent_room_ids = PackedStringArray(["room_b"])
	var room_b: Resource = _make_room("room_b", Vector2i(1, 0))
	room_b.adjacent_room_ids = PackedStringArray(["room_a"])
	var room_c: Resource = _make_room("room_c", Vector2i(2, 0))
	var connection: Resource = ROOM_CONNECTION_DATA.new()
	connection.from_room_id = "room_a"
	connection.from_entrance_id = "exit_right"
	connection.to_room_id = "room_c"
	connection.to_spawn_id = "spawn_left"
	var world: Resource = WORLD_DATA.new()
	world.world_id = "world_01"
	world.start_room_id = "room_a"
	world.rooms.assign([room_a, room_b, room_c])
	world.connections.assign([connection])
	var runtime: Node2D = WORLD_RUNTIME.new() as Node2D

	if not runtime.setup_world(world):
		failures.append("world runtime did not accept a valid world")
	if runtime.get_current_room_id() != "room_a":
		failures.append("world runtime did not enter the start room")
	if runtime.get_loaded_room_ids() != ["room_a", "room_b", "room_c"]:
		failures.append("world runtime did not load current plus adjacent rooms")
	if runtime.get_room_runtime("room_b") == null:
		failures.append("world runtime did not expose a loaded adjacent room")
	if runtime.get_child_count() != 3:
		failures.append("world runtime child count did not match loaded rooms")
	if not runtime.set_current_room("room_b"):
		failures.append("world runtime did not change to a valid room")
	if runtime.get_loaded_room_ids() != ["room_a", "room_b"]:
		failures.append("world runtime did not unload rooms outside the adjacency set")
	if runtime.get_child_count() != 2:
		failures.append("world runtime child count did not match loaded rooms after unload")
	runtime.free()


func _assert_world_runtime_rejects_unknown_room(failures: Array[String]) -> void:
	var room_a: Resource = _make_room("room_a", Vector2i.ZERO)
	var world: Resource = WORLD_DATA.new()
	world.start_room_id = "room_a"
	world.rooms.assign([room_a])
	var runtime: Node2D = WORLD_RUNTIME.new() as Node2D
	runtime.setup_world(world)

	if runtime.set_current_room("missing"):
		failures.append("world runtime accepted an unknown room")
	if runtime.get_current_room_id() != "room_a":
		failures.append("world runtime changed current room after rejecting unknown room")
	runtime.free()


func _assert_world_runtime_rejects_unloadable_current_room(failures: Array[String]) -> void:
	_remove_user_file(MISSING_FIXTURE_PATH)
	var room_a: Resource = _make_room("room_a", Vector2i.ZERO)
	var room_b: Resource = _make_room("room_b", Vector2i(1, 0))
	room_b.scene_path = MISSING_FIXTURE_PATH
	var world: Resource = WORLD_DATA.new()
	world.start_room_id = "room_a"
	world.rooms.assign([room_a, room_b])
	var runtime: Node2D = WORLD_RUNTIME.new() as Node2D
	runtime.setup_world(world)

	if runtime.set_current_room("room_b"):
		failures.append("world runtime accepted an unloadable current room")
	if runtime.get_current_room_id() != "room_a":
		failures.append("world runtime changed current room after unloadable room rejection")
	if runtime.get_loaded_room_ids() != ["room_a"]:
		failures.append("world runtime changed loaded rooms after unloadable room rejection")
	runtime.free()


func _assert_world_runtime_rejects_wrong_resource_type(failures: Array[String]) -> void:
	var runtime: Node2D = WORLD_RUNTIME.new() as Node2D
	if runtime.setup_world(Resource.new()):
		failures.append("world runtime accepted a non-WorldData resource")
	if runtime.get_current_room_id() != "":
		failures.append("world runtime exposed current room for wrong resource data")
	runtime.free()


func _make_room(room_id: String, room_origin_chunk: Vector2i) -> Resource:
	var room: Resource = ROOM_DATA.new()
	room.room_id = room_id
	room.scene_path = FIXTURE_PATH
	room.room_origin_chunk = room_origin_chunk
	room.room_size_chunks = Vector2i.ONE
	return room


func _save_room_fixture() -> Error:
	var root := Node2D.new()
	root.name = "RoomRoot"
	var entities := Node2D.new()
	entities.name = "Entities"
	root.add_child(entities)
	entities.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	var error := ResourceSaver.save(packed, FIXTURE_PATH)
	root.free()
	return error


func _remove_user_file(path: String) -> void:
	var absolute_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(absolute_path)
