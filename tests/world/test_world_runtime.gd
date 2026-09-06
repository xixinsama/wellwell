extends Node

const ROOM_DATA: Script = preload("res://scripts/world/room_data.gd")
const ROOM_CONNECTION_DATA: Script = preload("res://scripts/world/room_connection_data.gd")
const WORLD_DATA: Script = preload("res://scripts/world/world_data.gd")
const WORLD_RUNTIME: Script = preload("res://scripts/world/world_runtime.gd")
const SAVE_SNAPSHOT: Script = preload("res://scripts/save/save_snapshot.gd")
const SPAWN_POINT: Script = preload("res://scripts/world/spawn_point.gd")
const PICKUP_ENTITY: Script = preload("res://scripts/world/pickup_entity.gd")
const ROOM_ENTRANCE: Script = preload("res://scripts/world/room_entrance.gd")

const FIXTURE_PATH := "user://world_runtime_room_fixture.tscn"
const MISSING_FIXTURE_PATH := "user://missing_world_runtime_room_fixture.tscn"


func run() -> Array[String]:
	var failures: Array[String] = []
	var save_error := _save_room_fixture()
	if save_error != OK:
		failures.append("world runtime fixture save failed: %d" % save_error)
		return failures
	_assert_world_runtime_loads_current_and_adjacent_rooms(failures)
	_assert_world_runtime_uses_spatial_residency_without_legacy_adjacency(failures)
	_assert_world_runtime_does_not_rebuild_same_player_chunk(failures)
	_assert_world_runtime_preserves_player_and_snapshot_on_failed_chunk_transition(failures)
	_assert_transition_expands_residency_from_multichunk_spawn(failures)
	_assert_setup_world_uses_bound_player_chunk(failures)
	_assert_session_restore_expands_from_far_spawn(failures)
	_assert_external_room_change_uses_player_chunk(failures)
	_assert_world_runtime_starts_from_snapshot_and_tracks_player_room(failures)
	_assert_world_runtime_falls_back_from_stale_snapshot(failures)
	_assert_world_runtime_restores_entity_state_while_loading(failures)
	_assert_world_runtime_uses_session_snapshot_for_entities(failures)
	_assert_world_runtime_keeps_existing_world_after_failed_reinitialization(failures)
	_assert_world_runtime_transitions_player_to_target_spawn(failures)
	_assert_world_runtime_rejects_unknown_room(failures)
	_assert_world_runtime_rejects_unloadable_current_room(failures)
	_assert_world_runtime_rejects_wrong_resource_type(failures)
	_assert_clear_world_resets_session_state(failures)
	_assert_external_tracking_sync_records_player_position(failures)
	return failures


func _assert_external_tracking_sync_records_player_position(failures: Array[String]) -> void:
	var runtime: Node2D = WORLD_RUNTIME.new() as Node2D
	if not runtime.has_method("synchronize_player_tracking"):
		failures.append("world runtime is missing external tracking synchronization")
		runtime.free()
		return
	var player := Node2D.new()
	player.global_position = Vector2(73, 29)
	runtime.bind_player(player)
	var world: Resource = WORLD_DATA.new()
	world.world_id = "world_tracking"
	world.start_room_id = "room_a"
	world.rooms.assign([_make_room("room_a", Vector2i.ZERO)])
	runtime.world_data = world
	runtime.call("synchronize_player_tracking")
	if runtime.get("_last_safe_player_position") != Vector2(73, 29):
		failures.append("external tracking synchronization did not record player position")
	runtime.free()
	player.free()


func _assert_clear_world_resets_session_state(failures: Array[String]) -> void:
	var room: Resource = _make_room("room_a", Vector2i.ZERO)
	var world: Resource = WORLD_DATA.new()
	world.start_room_id = "room_a"
	world.rooms.assign([room])
	var runtime: Node2D = WORLD_RUNTIME.new() as Node2D
	if not runtime.has_method("clear_world"):
		failures.append("world runtime is missing a public session rollback clear")
		runtime.free()
		return
	runtime.setup_world(world)
	runtime.call("clear_world")
	if runtime.get_current_room_id() != "" or not runtime.get_loaded_room_ids().is_empty():
		failures.append("world runtime clear did not reset current and loaded rooms")
	if runtime.get("world_data") != null:
		failures.append("world runtime clear retained WorldData")
	runtime.free()


func _assert_world_runtime_loads_current_and_adjacent_rooms(failures: Array[String]) -> void:
	var room_a: Resource = _make_room("room_a", Vector2i(0, 0))
	var room_b: Resource = _make_room("room_b", Vector2i(1, 0))
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
	if runtime.get_loaded_room_ids() != ["room_a", "room_b", "room_c"]:
		failures.append("world runtime did not keep the current chunk neighborhood resident")
	if runtime.get_child_count() != 3:
		failures.append("world runtime child count did not match spatial residency after room change")
	runtime.free()


func _assert_world_runtime_uses_spatial_residency_without_legacy_adjacency(failures: Array[String]) -> void:
	var room_a: Resource = _make_room("room_a", Vector2i(0, 0))
	var room_b: Resource = _make_room("room_b", Vector2i(1, 0))
	var room_c: Resource = _make_room("room_c", Vector2i(0, 1))
	var room_remote: Resource = _make_room("room_remote", Vector2i(8, 8))
	var connection: Resource = _make_connection("room_a", "exit_right", "room_remote", "entry")
	var world: Resource = WORLD_DATA.new()
	world.world_id = "world_01"
	world.start_room_id = "room_a"
	world.rooms.assign([room_remote, room_c, room_b, room_a])
	world.connections.assign([connection])
	var runtime: Node2D = WORLD_RUNTIME.new() as Node2D

	if not runtime.setup_world(world):
		failures.append("world runtime rejected a spatial residency fixture")
	else:
		var loaded_ids: Array[String] = runtime.get_loaded_room_ids()
		if loaded_ids != ["room_a", "room_b", "room_c", "room_remote"]:
			failures.append("world runtime did not use spatial neighbors plus connection target: %s" % str(loaded_ids))
	runtime.free()


func _assert_world_runtime_does_not_rebuild_same_player_chunk(failures: Array[String]) -> void:
	var room_a: Resource = _make_room("room_a", Vector2i(0, 0))
	room_a.room_size_chunks = Vector2i(2, 1)
	var room_b: Resource = _make_room("room_b", Vector2i(1, 0))
	var world: Resource = WORLD_DATA.new()
	world.world_id = "world_01"
	world.start_room_id = "room_a"
	world.rooms.assign([room_a, room_b])
	var player := TestPlayer.new()
	player.global_position = Vector2(40.0, 40.0)
	var runtime: Node2D = WORLD_RUNTIME.new() as Node2D
	runtime.bind_player(player)
	if not runtime.setup_world(world):
		failures.append("world runtime could not initialize same-chunk fixture")
	else:
		var room_runtime: Node = runtime.get_room_runtime("room_a")
		var loaded_before: Array[String] = runtime.get_loaded_room_ids()
		var child_count_before := runtime.get_child_count()
		player.global_position = Vector2(280.0, 40.0)
		if not runtime.update_player_room():
			failures.append("world runtime rejected movement within the current room")
		if runtime.get_room_runtime("room_a") != room_runtime:
			failures.append("world runtime rebuilt a room while the player stayed in the same chunk")
		if runtime.get_loaded_room_ids() != loaded_before or runtime.get_child_count() != child_count_before:
			failures.append("same-chunk movement changed the residency set")
	runtime.free()
	player.free()


func _assert_world_runtime_preserves_player_and_snapshot_on_failed_chunk_transition(failures: Array[String]) -> void:
	_remove_user_file(MISSING_FIXTURE_PATH)
	var room_a: Resource = _make_room("room_a", Vector2i(0, 0))
	var room_b: Resource = _make_room("room_b", Vector2i(1, 0))
	var room_c: Resource = _make_room("room_c", Vector2i(2, 0))
	room_c.scene_path = MISSING_FIXTURE_PATH
	var world: Resource = WORLD_DATA.new()
	world.world_id = "world_01"
	world.start_room_id = "room_a"
	world.start_spawn_id = "entry"
	world.rooms.assign([room_a, room_b, room_c])
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	snapshot.world_id = "world_01"
	snapshot.current_room_id = "room_a"
	snapshot.respawn_room_id = "room_a"
	snapshot.respawn_spawn_id = "entry"
	var player := TestPlayer.new()
	var runtime: Node2D = WORLD_RUNTIME.new() as Node2D
	if not runtime.setup_session(world, snapshot, player):
		failures.append("world runtime could not initialize failed chunk transition fixture")
	else:
		var safe_position := Vector2(40.0, 40.0)
		player.global_position = safe_position
		if not runtime.update_player_room():
			failures.append("world runtime could not record the last safe same-chunk position")
		var loaded_before: Array[String] = runtime.get_loaded_room_ids()
		var current_before: String = runtime.get_current_room_id()
		var room_a_runtime: Node = runtime.get_room_runtime("room_a")
		player.global_position = Vector2(360.0, 40.0)
		if runtime.update_player_room():
			failures.append("world runtime accepted a chunk transition with an unloadable resident room")
		if runtime.get_current_room_id() != current_before:
			failures.append("failed chunk transition changed current room")
		if runtime.get_loaded_room_ids() != loaded_before:
			failures.append("failed chunk transition changed loaded room ids")
		if runtime.get_room_runtime("room_a") != room_a_runtime:
			failures.append("failed chunk transition replaced the existing room runtime")
		if player.global_position != safe_position:
			failures.append("failed chunk transition changed the player's last safe position")
		if snapshot.current_room_id != "room_a" or snapshot.respawn_room_id != "room_a" or snapshot.respawn_spawn_id != "entry":
			failures.append("failed chunk transition changed the snapshot's last safe state")
	runtime.free()
	player.free()


func _assert_transition_expands_residency_from_multichunk_spawn(failures: Array[String]) -> void:
	var room_a: Resource = _make_room("room_a", Vector2i.ZERO)
	var room_b: Resource = _make_room("room_b", Vector2i(1, 0))
	room_b.room_size_chunks = Vector2i(2, 1)
	var room_c: Resource = _make_room("room_c", Vector2i(3, 0))
	var world: Resource = WORLD_DATA.new()
	world.world_id = "world_01"
	world.start_room_id = "room_a"
	world.start_spawn_id = "entry"
	world.rooms.assign([room_a, room_b, room_c])
	world.connections.assign([_make_connection("room_a", "exit_right", "room_b", "far_entry")])
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	var player := TestPlayer.new()
	var runtime: Node2D = WORLD_RUNTIME.new() as Node2D
	if not runtime.setup_session(world, snapshot, player):
		failures.append("world runtime could not initialize multichunk spawn fixture")
	elif not runtime.request_transition(runtime.get_room_runtime("room_a").get_entity("exit_right")):
		failures.append("world runtime rejected multichunk spawn transition")
	else:
		if player.global_position != Vector2(648.0, 12.0):
			failures.append("world runtime did not respawn at the far multichunk spawn")
		if runtime.get_loaded_room_ids() != ["room_a", "room_b", "room_c"]:
			failures.append("spawn chunk neighbors were not staged before transition commit")
	runtime.free()
	player.free()


func _assert_setup_world_uses_bound_player_chunk(failures: Array[String]) -> void:
	var room_a: Resource = _make_room("room_a", Vector2i(1, 0))
	room_a.room_size_chunks = Vector2i(2, 1)
	var room_c: Resource = _make_room("room_c", Vector2i(3, 0))
	var world: Resource = WORLD_DATA.new()
	world.world_id = "world_01"
	world.start_room_id = "room_a"
	world.rooms.assign([room_a, room_c])
	var player := TestPlayer.new()
	player.global_position = Vector2(648.0, 12.0)
	var runtime: Node2D = WORLD_RUNTIME.new() as Node2D
	runtime.bind_player(player)
	if not runtime.setup_world(world):
		failures.append("world runtime rejected bound-player setup fixture")
	elif runtime.get_loaded_room_ids() != ["room_a", "room_c"]:
		failures.append("setup_world did not stage from the bound player's actual chunk")
	runtime.free()
	player.free()


func _assert_session_restore_expands_from_far_spawn(failures: Array[String]) -> void:
	var room_a: Resource = _make_room("room_a", Vector2i.ZERO)
	var room_b: Resource = _make_room("room_b", Vector2i(1, 0))
	room_b.room_size_chunks = Vector2i(2, 1)
	var room_c: Resource = _make_room("room_c", Vector2i(3, 0))
	var world: Resource = WORLD_DATA.new()
	world.world_id = "world_01"
	world.start_room_id = "room_a"
	world.start_spawn_id = "entry"
	world.rooms.assign([room_a, room_b, room_c])
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	snapshot.world_id = "world_01"
	snapshot.current_room_id = "room_b"
	snapshot.respawn_room_id = "room_b"
	snapshot.respawn_spawn_id = "far_entry"
	var player := TestPlayer.new()
	var runtime: Node2D = WORLD_RUNTIME.new() as Node2D
	if not runtime.setup_session(world, snapshot, player):
		failures.append("world runtime rejected far saved spawn")
	elif player.global_position != Vector2(648.0, 12.0):
		failures.append("world runtime did not restore the far saved spawn")
	elif runtime.get_loaded_room_ids() != ["room_b", "room_c"]:
		failures.append("saved spawn chunk neighbors were not staged before session commit")
	runtime.free()
	player.free()


func _assert_external_room_change_uses_player_chunk(failures: Array[String]) -> void:
	var room_a: Resource = _make_room("room_a", Vector2i.ZERO)
	var room_b: Resource = _make_room("room_b", Vector2i(5, 0))
	var room_c: Resource = _make_room("room_c", Vector2i(4, 0))
	var world: Resource = WORLD_DATA.new()
	world.world_id = "world_01"
	world.start_room_id = "room_a"
	world.rooms.assign([room_a, room_b, room_c])
	var player := TestPlayer.new()
	player.global_position = Vector2(40.0, 40.0)
	var runtime: Node2D = WORLD_RUNTIME.new() as Node2D
	runtime.bind_player(player)
	if not runtime.setup_world(world):
		failures.append("world runtime could not initialize external room change fixture")
	elif not runtime.set_current_room("room_b"):
		failures.append("world runtime rejected external current-room change")
	elif runtime.get_loaded_room_ids() != ["room_a", "room_b"]:
		failures.append("external room change did not use the player's tracked chunk")
	runtime.free()
	player.free()


func _assert_world_runtime_starts_from_snapshot_and_tracks_player_room(failures: Array[String]) -> void:
	var room_a: Resource = _make_room("room_a", Vector2i.ZERO)
	room_a.adjacent_room_ids = PackedStringArray(["room_b"])
	var room_b: Resource = _make_room("room_b", Vector2i(1, 0))
	room_b.adjacent_room_ids = PackedStringArray(["room_a"])
	var world: Resource = WORLD_DATA.new()
	world.world_id = "world_01"
	world.start_room_id = "room_a"
	world.start_spawn_id = "entry"
	world.rooms.assign([room_a, room_b])
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	snapshot.world_id = "world_01"
	snapshot.current_room_id = "room_b"
	snapshot.respawn_room_id = "room_b"
	snapshot.respawn_spawn_id = "entry"
	var player := TestPlayer.new()
	var runtime: Node2D = WORLD_RUNTIME.new() as Node2D

	if not runtime.has_method("setup_session"):
		failures.append("world runtime did not expose snapshot session setup")
	else:
		if not runtime.call("setup_session", world, snapshot, player):
			failures.append("world runtime did not start from a valid snapshot")
		if runtime.get_current_room_id() != "room_b":
			failures.append("world runtime did not restore the snapshot room")
		if player.global_position != Vector2(328.0, 12.0):
			failures.append("world runtime did not place the player at the saved room spawn")
		player.global_position = Vector2(40.0, 40.0)
		runtime.call("_physics_process", 0.0)
		if runtime.get_current_room_id() != "room_a":
			failures.append("world runtime did not track the room from player position")
	if snapshot.current_room_id != "room_a":
		failures.append("world runtime did not write the active room back to the snapshot")
	runtime.free()
	player.free()

	snapshot = SAVE_SNAPSHOT.new()
	snapshot.world_id = "world_01"
	snapshot.current_room_id = "room_b"
	snapshot.respawn_room_id = "room_a"
	snapshot.respawn_spawn_id = "entry"
	player = TestPlayer.new()
	runtime = WORLD_RUNTIME.new() as Node2D
	if not runtime.setup_session(world, snapshot, player):
		failures.append("world runtime rejected a separate respawn room")
	if runtime.get_current_room_id() != "room_a" or player.global_position != Vector2(8.0, 12.0):
		failures.append("world runtime did not prefer the saved respawn anchor")
	runtime.free()
	player.free()


func _assert_world_runtime_falls_back_from_stale_snapshot(failures: Array[String]) -> void:
	var room_a: Resource = _make_room("room_a", Vector2i.ZERO)
	var room_b: Resource = _make_room("room_b", Vector2i(1, 0))
	var world: Resource = WORLD_DATA.new()
	world.world_id = "world_01"
	world.start_room_id = "room_a"
	world.start_spawn_id = "entry"
	world.rooms.assign([room_a, room_b])
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	snapshot.world_id = "old_world"
	snapshot.current_room_id = "room_b"
	snapshot.respawn_room_id = "old_room"
	snapshot.respawn_spawn_id = "old_spawn"
	var player := TestPlayer.new()
	var runtime: Node2D = WORLD_RUNTIME.new() as Node2D

	if not runtime.setup_session(world, snapshot, player):
		failures.append("world runtime did not recover from a snapshot for another world")
	if runtime.get_current_room_id() != "room_a" or player.global_position != Vector2(8.0, 12.0):
		failures.append("stale snapshot did not fall back to the world start")
	if snapshot.world_id != "world_01" or snapshot.respawn_room_id != "room_a" or snapshot.respawn_spawn_id != "entry":
		failures.append("stale snapshot respawn anchor was not reset to the world start")
	runtime.free()
	player.free()

	var invalid_spawn_snapshot: RefCounted = SAVE_SNAPSHOT.new()
	invalid_spawn_snapshot.world_id = "world_01"
	invalid_spawn_snapshot.current_room_id = "room_b"
	invalid_spawn_snapshot.respawn_room_id = "room_b"
	invalid_spawn_snapshot.respawn_spawn_id = "missing"
	player = TestPlayer.new()
	runtime = WORLD_RUNTIME.new() as Node2D
	if not runtime.setup_session(world, invalid_spawn_snapshot, player):
		failures.append("world runtime did not recover from a missing saved spawn")
	if runtime.get_current_room_id() != "room_a" or player.respawn_count != 1:
		failures.append("missing saved spawn did not perform one clean fallback respawn")
	if invalid_spawn_snapshot.respawn_room_id != "room_a" or invalid_spawn_snapshot.respawn_spawn_id != "entry":
		failures.append("missing saved spawn did not replace the stale respawn anchor")
	runtime.free()
	player.free()


func _assert_world_runtime_restores_entity_state_while_loading(failures: Array[String]) -> void:
	var manager := TestSaveManager.new()
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	snapshot.set_entity_state("world_01:room_a:pickup_01", {"collected": true})
	manager.current_snapshot = snapshot
	var runtime: Node2D = WORLD_RUNTIME.new() as Node2D
	if not runtime.has_method("bind_save_manager"):
		failures.append("world runtime did not expose save manager binding")
		runtime.free()
		manager.free()
		return
	runtime.call("bind_save_manager", manager)
	var room_a: Resource = _make_room("room_a", Vector2i.ZERO)
	var world: Resource = WORLD_DATA.new()
	world.world_id = "world_01"
	world.start_room_id = "room_a"
	world.rooms.assign([room_a])

	if not runtime.setup_world(world):
		failures.append("world runtime could not load the persistent entity fixture")
	else:
		var pickup: Node = runtime.get_room_runtime("room_a").get_entity("pickup_01")
		if pickup == null or not bool(pickup.get("collected")):
			failures.append("world runtime did not restore entity state during room loading")

	runtime.free()
	manager.free()


func _assert_world_runtime_uses_session_snapshot_for_entities(failures: Array[String]) -> void:
	var manager := TestSaveManager.new()
	manager.current_snapshot = SAVE_SNAPSHOT.new()
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	snapshot.set_entity_state("world_01:room_a:pickup_01", {"collected": true})
	var room_a: Resource = _make_room("room_a", Vector2i.ZERO)
	var world: Resource = WORLD_DATA.new()
	world.world_id = "world_01"
	world.start_room_id = "room_a"
	world.start_spawn_id = "entry"
	world.rooms.assign([room_a])
	var runtime: Node2D = WORLD_RUNTIME.new() as Node2D
	runtime.bind_save_manager(manager)

	if not runtime.setup_session(world, snapshot, TestPlayer.new()):
		failures.append("world runtime could not start the entity snapshot fixture")
	else:
		var pickup: Node = runtime.get_room_runtime("room_a").get_entity("pickup_01")
		if pickup == null or not bool(pickup.get("collected")):
			failures.append("session entities did not restore from the supplied snapshot")
	var bound_player: Node = runtime.get("_player")
	runtime.free()
	if bound_player != null:
		bound_player.free()
	manager.free()


func _assert_world_runtime_keeps_existing_world_after_failed_reinitialization(failures: Array[String]) -> void:
	_remove_user_file(MISSING_FIXTURE_PATH)
	var room_a: Resource = _make_room("room_a", Vector2i.ZERO)
	var good_world: Resource = WORLD_DATA.new()
	good_world.world_id = "good_world"
	good_world.start_room_id = "room_a"
	good_world.rooms.assign([room_a])
	var room_b: Resource = _make_room("room_b", Vector2i(1, 0))
	room_b.adjacent_room_ids = PackedStringArray(["room_c"])
	var room_c: Resource = _make_room("room_c", Vector2i(2, 0))
	room_c.scene_path = MISSING_FIXTURE_PATH
	var bad_world: Resource = WORLD_DATA.new()
	bad_world.world_id = "bad_world"
	bad_world.start_room_id = "room_b"
	bad_world.rooms.assign([room_b, room_c])
	var runtime: Node2D = WORLD_RUNTIME.new() as Node2D
	runtime.setup_world(good_world)

	if runtime.setup_world(bad_world):
		failures.append("world runtime accepted a world with an unloadable adjacent room")
	if runtime.get_current_room_id() != "room_a" or runtime.get_loaded_room_ids() != ["room_a"]:
		failures.append("failed world initialization replaced the existing world")
	if runtime.setup_world(Resource.new()):
		failures.append("world runtime accepted invalid data during reinitialization")
	if runtime.get_current_room_id() != "room_a" or runtime.get_loaded_room_ids() != ["room_a"]:
		failures.append("invalid reinitialization cleared the existing world")
	runtime.free()

	good_world.rooms.assign([room_a, room_b, room_c])
	runtime = WORLD_RUNTIME.new() as Node2D
	if not runtime.setup_world(good_world):
		failures.append("world runtime could not set up the transition atomicity fixture")
	elif runtime.set_current_room("room_b"):
		failures.append("world runtime changed rooms with an unloadable target neighbor")
	if runtime.get_current_room_id() != "room_a" or runtime.get_loaded_room_ids() != ["room_a", "room_b"]:
		failures.append("failed room change modified the current residency set")
	runtime.free()

	runtime = WORLD_RUNTIME.new() as Node2D
	runtime.setup_world(good_world)
	good_world.connections.assign([_make_connection("room_a", "exit_right", "room_b", "entry")])
	var entrance: Node = runtime.get_room_runtime("room_a").get_entity("exit_right")
	entrance.call("request_transition")
	if runtime.get_current_room_id() != "room_a" or runtime.get_loaded_room_ids() != ["room_a", "room_b"]:
		failures.append("failed entrance transition left staged rooms resident")
	runtime.free()


func _assert_world_runtime_transitions_player_to_target_spawn(failures: Array[String]) -> void:
	var room_a: Resource = _make_room("room_a", Vector2i.ZERO)
	room_a.adjacent_room_ids = PackedStringArray(["room_b"])
	var room_b: Resource = _make_room("room_b", Vector2i(1, 0))
	room_b.adjacent_room_ids = PackedStringArray(["room_a"])
	var world: Resource = WORLD_DATA.new()
	world.world_id = "world_01"
	world.start_room_id = "room_a"
	world.start_spawn_id = "entry"
	world.rooms.assign([room_a, room_b])
	world.connections.assign([_make_connection("room_a", "exit_right", "room_b", "entry")])
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	var player := TestPlayer.new()
	var runtime: Node2D = WORLD_RUNTIME.new() as Node2D
	if runtime.has_method("setup_session"):
		runtime.call("setup_session", world, snapshot, player)
	else:
		runtime.setup_world(world)
	var proxy := TransitionProxy.new()
	proxy.target_room_id = "room_b"
	proxy.target_spawn_id = "entry"
	var completed: Array[String] = []
	runtime.transition_completed.connect(
		func(_from_room: String, to_room: String, spawn_id: String) -> void:
			completed.assign([to_room, spawn_id])
	)
	var adjacent_entrance: Node = runtime.get_room_runtime("room_b").get_entity("exit_right")
	adjacent_entrance.call("request_transition")
	if runtime.get_current_room_id() != "room_a" or player.respawn_count != 1:
		failures.append("an entrance outside the current room triggered a transition")
	var entrance: Node = runtime.get_room_runtime("room_a").get_entity("exit_right")
	if entrance == null:
		failures.append("world runtime did not load the transition entrance")
	else:
		entrance.call("request_transition")
	if runtime.get_current_room_id() != "room_b":
		failures.append("entrance signal did not transition the world runtime")
	if player.global_position != Vector2(328.0, 12.0) or player.respawn_count != 2:
		failures.append("world runtime did not respawn the player at the transition target")
	if completed != ["room_b", "entry"]:
		failures.append("world runtime completed transition before the target spawn was ready")
	proxy.target_spawn_id = "missing"
	if runtime.request_transition(proxy):
		failures.append("world runtime accepted a transition to an unknown spawn")
	if runtime.get_current_room_id() != "room_b":
		failures.append("failed transition changed the current room")
	runtime.free()
	player.free()
	proxy.free()


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
	var room_b: Resource = _make_room("room_b", Vector2i(2, 0))
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


func _make_connection(from_room_id: String, entrance_id: String, to_room_id: String, spawn_id: String) -> Resource:
	var connection: Resource = ROOM_CONNECTION_DATA.new()
	connection.from_room_id = from_room_id
	connection.from_entrance_id = entrance_id
	connection.to_room_id = to_room_id
	connection.to_spawn_id = spawn_id
	return connection


func _save_room_fixture() -> Error:
	var root := Node2D.new()
	root.name = "RoomRoot"
	var entities := Node2D.new()
	entities.name = "Entities"
	root.add_child(entities)
	entities.owner = root
	var spawn: Marker2D = SPAWN_POINT.new() as Marker2D
	spawn.name = "EntrySpawn"
	spawn.position = Vector2(8.0, 12.0)
	spawn.set("spawn_id", "entry")
	entities.add_child(spawn)
	spawn.owner = root
	var far_spawn: Marker2D = SPAWN_POINT.new() as Marker2D
	far_spawn.name = "FarEntrySpawn"
	far_spawn.position = Vector2(328.0, 12.0)
	far_spawn.set("spawn_id", "far_entry")
	entities.add_child(far_spawn)
	far_spawn.owner = root
	var pickup: Node2D = PICKUP_ENTITY.new() as Node2D
	pickup.name = "Pickup"
	pickup.set("entity_id", "pickup_01")
	pickup.set("persistent", true)
	entities.add_child(pickup)
	pickup.owner = root
	var entrance: Node2D = ROOM_ENTRANCE.new() as Node2D
	entrance.name = "ExitRight"
	entrance.set("entity_id", "exit_right")
	entrance.set("target_room_id", "room_b")
	entrance.set("target_spawn_id", "entry")
	entities.add_child(entrance)
	entrance.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	var error := ResourceSaver.save(packed, FIXTURE_PATH)
	root.free()
	return error


func _remove_user_file(path: String) -> void:
	var absolute_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(absolute_path)


class TestPlayer:
	extends Node2D

	var respawn_count := 0

	func respawn_at(target: Vector2) -> void:
		global_position = target
		respawn_count += 1


class TransitionProxy:
	extends Node

	var target_room_id := ""
	var target_spawn_id := ""


class TestSaveManager:
	extends Node

	var current_snapshot: RefCounted

	func get_entity_state(entity_key: String) -> Dictionary:
		return current_snapshot.get_entity_state(entity_key)
