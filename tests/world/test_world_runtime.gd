extends Node

const ROOM_DATA: Script = preload("res://scripts/world/data/room_data.gd")
const ROOM_CONNECTION_DATA: Script = preload("res://scripts/world/data/room_connection_data.gd")
const WORLD_DATA: Script = preload("res://scripts/world/data/world_data.gd")
const WORLD_RUNTIME: Script = preload("res://scripts/world/runtime/world_runtime.gd")
const SAVE_SNAPSHOT: Script = preload("res://scripts/save/save_snapshot.gd")
const SPAWN_POINT: Script = preload("res://scripts/world/entities/spawn_point.gd")
const PICKUP_ENTITY: Script = preload("res://scripts/world/entities/pickup_entity.gd")
const ROOM_ENTRANCE: Script = preload("res://scripts/world/entities/room_entrance.gd")

const FIXTURE_PATH := "user://world_runtime_room_fixture.tscn"
const MISSING_PATH := "user://missing_world_runtime_room_fixture.tscn"


class TestPlayer extends Node2D:
	var respawn_count := 0
	func respawn_at(target: Vector2) -> void:
		global_position = target
		respawn_count += 1


func run() -> Array[String]:
	var failures: Array[String] = []
	if _save_room_fixture() != OK:
		return ["world runtime fixture save failed"]
	_assert_explicit_placements_drive_residency(failures)
	_assert_failed_stage_preserves_active_world(failures)
	_assert_session_restores_persistent_entities(failures)
	_assert_connection_transition_uses_target_spawn(failures)
	_remove_fixture()
	return failures


func _assert_explicit_placements_drive_residency(failures: Array[String]) -> void:
	var world := _make_world([
		["room_a", Vector2i.ZERO, FIXTURE_PATH],
		["room_b", Vector2i.RIGHT, FIXTURE_PATH],
		["room_c", Vector2i(3, 0), FIXTURE_PATH],
	])
	world.connections.assign([_make_connection("room_a", "exit_right", "room_c", "entry")])
	var runtime := WORLD_RUNTIME.new() as Node2D
	if not runtime.setup_world(world):
		failures.append("world runtime rejected a placed room world")
	elif runtime.get_loaded_room_ids() != ["room_a", "room_b", "room_c"]:
		failures.append("world runtime did not combine spatial and connection residency")
	elif not runtime.set_current_room("room_b"):
		failures.append("world runtime rejected a valid placed target room")
	runtime.free()


func _assert_failed_stage_preserves_active_world(failures: Array[String]) -> void:
	var good := _make_world([["room_a", Vector2i.ZERO, FIXTURE_PATH]])
	var bad := _make_world([
		["room_b", Vector2i.ZERO, FIXTURE_PATH],
		["room_c", Vector2i.RIGHT, MISSING_PATH],
	])
	bad.start_room_id = "room_b"
	bad.connections.assign([_make_connection("room_b", "exit_right", "room_c", "entry")])
	var runtime := WORLD_RUNTIME.new() as Node2D
	if not runtime.setup_world(good):
		failures.append("world runtime could not establish the active world fixture")
	elif runtime.setup_world(bad):
		failures.append("world runtime accepted a world with an unloadable resident room")
	elif runtime.get_current_room_id() != "room_a" or runtime.get_loaded_room_ids() != ["room_a"]:
		failures.append("failed staging replaced the active world")
	runtime.free()


func _assert_session_restores_persistent_entities(failures: Array[String]) -> void:
	var world := _make_world([["room_a", Vector2i.ZERO, FIXTURE_PATH]])
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	snapshot.world_id = world.world_id
	snapshot.set_entity_state("world_runtime:room_a:pickup_01", {"collected": true})
	var player := TestPlayer.new()
	var runtime := WORLD_RUNTIME.new() as Node2D
	if not runtime.setup_session(world, snapshot, player):
		failures.append("world runtime rejected a valid entity snapshot")
	else:
		var pickup: Node = runtime.get_room_runtime("room_a").get_entity("pickup_01")
		if pickup == null or not bool(pickup.get("collected")):
			failures.append("world runtime did not restore persistent entity state")
	runtime.free()
	player.free()


func _assert_connection_transition_uses_target_spawn(failures: Array[String]) -> void:
	var world := _make_world([
		["room_a", Vector2i.ZERO, FIXTURE_PATH],
		["room_b", Vector2i.RIGHT, FIXTURE_PATH],
	])
	world.start_spawn_id = "entry"
	world.connections.assign([_make_connection("room_a", "exit_right", "room_b", "entry")])
	var player := TestPlayer.new()
	var runtime := WORLD_RUNTIME.new() as Node2D
	if not runtime.setup_session(world, SAVE_SNAPSHOT.new(), player):
		failures.append("world runtime rejected a transition fixture")
	else:
		var entrance: Node = runtime.get_room_runtime("room_a").get_entity("exit_right")
		entrance.request_transition()
		if runtime.get_current_room_id() != "room_b" or player.global_position != Vector2(328, 12):
			failures.append("world runtime did not transition to the connected target spawn")
	runtime.free()
	player.free()


func _make_world(entries: Array) -> Resource:
	var world: Resource = WORLD_DATA.new()
	world.world_id = "world_runtime"
	world.start_room_id = "room_a"
	world.start_spawn_id = "entry"
	for entry: Array in entries:
		var room: Resource = ROOM_DATA.new()
		room.room_id = entry[0]
		room.scene_path = entry[2]
		room.room_size_chunks = Vector2i.ONE
		world.rooms.append(room)
		world.set_room_origin_chunk(room.room_id, entry[1])
	return world


func _make_connection(from_room_id: String, entrance: String, to_room_id: String, spawn: String) -> Resource:
	var connection: Resource = ROOM_CONNECTION_DATA.new()
	connection.from_room_id = from_room_id
	connection.from_entrance_id = entrance
	connection.to_room_id = to_room_id
	connection.to_spawn_id = spawn
	return connection


func _save_room_fixture() -> Error:
	var root := Node2D.new()
	root.name = "RoomRoot"
	var entities := Node2D.new()
	entities.name = "Entities"
	root.add_child(entities)
	entities.owner = root
	for spawn_data: Array in [["EntrySpawn", "entry", Vector2(8, 12)], ["FarEntrySpawn", "far_entry", Vector2(328, 12)]]:
		var spawn := SPAWN_POINT.new() as Marker2D
		spawn.name = spawn_data[0]
		spawn.spawn_id = spawn_data[1]
		spawn.position = spawn_data[2]
		entities.add_child(spawn)
		spawn.owner = root
	var pickup := PICKUP_ENTITY.new() as Node2D
	pickup.name = "Pickup"
	pickup.entity_id = "pickup_01"
	pickup.persistent = true
	entities.add_child(pickup)
	pickup.owner = root
	var entrance := ROOM_ENTRANCE.new() as Node2D
	entrance.name = "ExitRight"
	entrance.entity_id = "exit_right"
	entities.add_child(entrance)
	entrance.owner = root
	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	root.free()
	return pack_error if pack_error != OK else ResourceSaver.save(packed, FIXTURE_PATH)


func _remove_fixture() -> void:
	if FileAccess.file_exists(FIXTURE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE_PATH))
