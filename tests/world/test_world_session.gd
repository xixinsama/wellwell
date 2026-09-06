extends Node

const SESSION_PATH := "res://scripts/world/world_session.gd"
const WORLD_DATA := preload("res://scripts/world/world_data.gd")
const ROOM_DATA := preload("res://scripts/world/room_data.gd")
const SAVE_SNAPSHOT := preload("res://scripts/save/save_snapshot.gd")


class FakeTerrain extends Node2D:
	var succeeds := true
	var room_terrain := Node2D.new()
	var setup_world_ids: Array[String] = []
	var clear_count := 0
	func _init() -> void: add_child(room_terrain)
	func setup_world(world: Resource) -> bool:
		setup_world_ids.append(world.world_id)
		return succeeds
	func get_room_terrain(_room_id: String) -> Node: return room_terrain
	func clear_world() -> void: clear_count += 1


class FakeRuntime extends Node2D:
	var succeeds := true
	var current_room_id := "room_a"
	var player: Node2D
	var setup_world_ids: Array[String] = []
	var fail_world_id := ""
	var clear_count := 0
	var tracking_position := Vector2.ZERO
	func setup_session(world: Resource, snapshot: RefCounted, value: Node2D) -> bool:
		setup_world_ids.append(world.world_id)
		player = value
		current_room_id = snapshot.respawn_room_id if snapshot.world_id == world.world_id and world.has_room(snapshot.respawn_room_id) else world.start_room_id
		return succeeds and world.world_id != fail_world_id
	func get_current_room_id() -> String: return current_room_id
	func clear_world() -> void: clear_count += 1
	func synchronize_player_tracking() -> void:
		tracking_position = player.global_position


class FakeBinding extends Node:
	var bound: Node
	var persistence_source: Object
	var room_succeeds := true
	var clear_count := 0
	var fail_next_room_bind := false
	func bind_target(value: Node2D) -> void: bound = value
	func bind_player(value: Node) -> void: bound = value
	func bind_persistence_source(value: Object) -> void: persistence_source = value
	func clear_persistence_source() -> void: persistence_source = null
	func bind_room(_room: Resource, _terrain: Node) -> bool:
		if fail_next_room_bind:
			fail_next_room_bind = false
			return false
		return room_succeeds
	func clear_room() -> void: clear_count += 1


func run() -> Array[String]:
	var failures: Array[String] = []
	if not FileAccess.file_exists(SESSION_PATH):
		return ["missing production API: %s" % SESSION_PATH]
	var session_script := load(SESSION_PATH) as Script
	_assert_success_emits_ready_after_bindings(session_script, failures)
	_assert_failure_does_not_emit_ready(session_script, failures)
	_assert_invalid_start_spawn_fails_preflight(session_script, failures)
	_assert_failed_restart_rolls_back(session_script, failures)
	_assert_first_start_failure_clears_components(session_script, failures)
	_assert_fog_failure_rolls_back(session_script, failures)
	_assert_default_world_root_is_startable(failures)
	return failures


func _assert_default_world_root_is_startable(failures: Array[String]) -> void:
	var packed := load("res://scenes/worlds/world_root.tscn") as PackedScene
	var root := packed.instantiate()
	var world: Resource = root.get("world_data")
	if world == null:
		failures.append("world_root has no default WorldData")
		root.free()
		return
	if world.start_room_id != "level_0" or not world.has_room("level_0"):
		failures.append("world_root default WorldData does not start in level_0")
	else:
		var room: Resource = world.get_room("level_0")
		for path: String in [room.scene_path, room.terrain_scene_path, room.source_scene_path]:
			if path.is_empty() or not ResourceLoader.exists(path):
				failures.append("world_root default room artifact is missing: %s" % path)
	var hud := FakeBinding.new()
	hud.name = "TestHud"
	root.add_child(hud)
	root.set("debug_hud_path", NodePath("TestHud"))
	add_child(root)
	var ready_count := [0]
	root.connect("world_ready", func() -> void: ready_count[0] += 1)
	if not root.call("start_selected_snapshot", SAVE_SNAPSHOT.new()):
		failures.append("world_root could not start its generated default world")
	elif ready_count[0] != 1 or root.get_node("WorldRuntime").call("get_current_room_id") != "level_0":
		failures.append("world_root became ready before level_0 runtime was active")
	root.free()


func _assert_success_emits_ready_after_bindings(script: Script, failures: Array[String]) -> void:
	var session: Node = _make_session(script)
	var ready_count := [0]
	session.connect("world_ready", func() -> void: ready_count[0] += 1)
	var world: Resource = _make_world()
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	snapshot.add_explored_cell("room_a:7,4")
	if not session.call("start", world, snapshot):
		failures.append("WorldSession rejected successful component setup")
	if ready_count[0] != 1:
		failures.append("WorldSession did not emit world_ready exactly once")
	var player: Node = session.get_node("Player")
	for path: String in ["Camera", "Fog", "Hud"]:
		if session.get_node(path).get("bound") != player:
			failures.append("WorldSession did not bind persistent player to %s" % path)
	var fog := session.get_node("Fog") as FakeBinding
	if fog.persistence_source != session:
		failures.append("WorldSession did not bind fog persistence to the pending snapshot adapter")
	elif not session.call("get_explored_cells").has("room_a:7,4"):
		failures.append("WorldSession fog persistence adapter did not expose selected snapshot exploration")
	session.free()


func _assert_failure_does_not_emit_ready(script: Script, failures: Array[String]) -> void:
	var session: Node = _make_session(script)
	(session.get_node("Terrain") as FakeTerrain).succeeds = false
	var ready_count := [0]
	session.connect("world_ready", func() -> void: ready_count[0] += 1)
	if session.call("start", _make_world(), SAVE_SNAPSHOT.new()):
		failures.append("WorldSession accepted terrain setup failure")
	if ready_count[0] != 0:
		failures.append("WorldSession emitted world_ready after failure")
	session.free()


func _assert_invalid_start_spawn_fails_preflight(script: Script, failures: Array[String]) -> void:
	var session: Node = _make_session(script)
	var world: Resource = _make_world()
	world.start_spawn_id = "missing"
	if session.call("start", world, SAVE_SNAPSHOT.new()):
		failures.append("WorldSession accepted an invalid configured start spawn")
	if not (session.get_node("Terrain") as FakeTerrain).setup_world_ids.is_empty():
		failures.append("WorldSession touched terrain before start-spawn preflight passed")
	session.free()


func _assert_failed_restart_rolls_back(script: Script, failures: Array[String]) -> void:
	var session: Node = _make_session(script)
	var player := session.get_node("Player") as Node2D
	var world_a := _make_world("world_a")
	var snapshot_a: RefCounted = SAVE_SNAPSHOT.new()
	if not session.call("start", world_a, snapshot_a):
		failures.append("WorldSession rollback fixture could not start its initial world")
		session.free()
		return
	player.global_position = Vector2(41, 27)
	var runtime := session.get_node("Runtime") as FakeRuntime
	runtime.fail_world_id = "world_b"
	var world_b := _make_world("world_b")
	if session.call("start", world_b, SAVE_SNAPSHOT.new()):
		failures.append("WorldSession accepted a streamed runtime setup failure")
	if session.get("_active_world") != world_a:
		failures.append("WorldSession replaced the active world after failed restart")
	if runtime.setup_world_ids != ["world_a", "world_b", "world_a"]:
		failures.append("WorldSession did not restore the previous streamed world")
	var terrain := session.get_node("Terrain") as FakeTerrain
	if terrain.setup_world_ids != ["world_a", "world_b", "world_a"]:
		failures.append("WorldSession did not restore the previous persistent terrain")
	if player.global_position != Vector2(41, 27):
		failures.append("WorldSession did not restore player position after failed restart")
	if runtime.tracking_position != Vector2(41, 27):
		failures.append("WorldSession did not restore runtime safe-position tracking")
	if session.get("_persistence_snapshot") != snapshot_a:
		failures.append("WorldSession did not restore fog persistence snapshot after failed restart")
	session.free()


func _assert_first_start_failure_clears_components(script: Script, failures: Array[String]) -> void:
	var session: Node = _make_session(script)
	var runtime := session.get_node("Runtime") as FakeRuntime
	runtime.succeeds = false
	if session.call("start", _make_world(), SAVE_SNAPSHOT.new()):
		failures.append("WorldSession accepted first-start runtime failure")
	if runtime.clear_count != 1:
		failures.append("WorldSession did not clear streamed state after first-start failure")
	if (session.get_node("Terrain") as FakeTerrain).clear_count != 1:
		failures.append("WorldSession did not clear terrain after first-start failure")
	if (session.get_node("Fog") as FakeBinding).clear_count < 1:
		failures.append("WorldSession did not clear fog after first-start failure")
	if session.get("_persistence_snapshot") != null:
		failures.append("WorldSession retained pending fog persistence after first-start failure")
	session.free()


func _assert_fog_failure_rolls_back(script: Script, failures: Array[String]) -> void:
	var session: Node = _make_session(script)
	var world_a := _make_world("world_a")
	if not session.call("start", world_a, SAVE_SNAPSHOT.new()):
		failures.append("fog rollback fixture could not start its initial world")
		session.free()
		return
	var fog := session.get_node("Fog") as FakeBinding
	fog.fail_next_room_bind = true
	if session.call("start", _make_world("world_b"), SAVE_SNAPSHOT.new()):
		failures.append("WorldSession accepted active-room fog binding failure")
	if session.get("_active_world") != world_a:
		failures.append("WorldSession replaced active world after fog binding failure")
	if (session.get_node("Runtime") as FakeRuntime).setup_world_ids != ["world_a", "world_b", "world_a"]:
		failures.append("WorldSession did not restore runtime after fog binding failure")
	session.free()


func _make_session(script: Script) -> Node:
	var session: Node = script.new()
	var terrain := FakeTerrain.new(); terrain.name = "Terrain"; session.add_child(terrain)
	var runtime := FakeRuntime.new(); runtime.name = "Runtime"; session.add_child(runtime)
	var player := Node2D.new(); player.name = "Player"; session.add_child(player)
	var camera := FakeBinding.new(); camera.name = "Camera"; session.add_child(camera)
	var fog := FakeBinding.new(); fog.name = "Fog"; session.add_child(fog)
	var hud := FakeBinding.new(); hud.name = "Hud"; session.add_child(hud)
	session.set("terrain_runtime_path", NodePath("Terrain"))
	session.set("world_runtime_path", NodePath("Runtime"))
	session.set("player_path", NodePath("Player"))
	session.set("camera_path", NodePath("Camera"))
	session.set("fog_path", NodePath("Fog"))
	session.set("debug_hud_path", NodePath("Hud"))
	return session


func _make_world(world_id: String = "world_a") -> Resource:
	var room: Resource = ROOM_DATA.new()
	room.room_id = "room_a"
	room.scene_path = "res://scenes/templates/level_template.tscn"
	room.source_scene_path = "res://scenes/templates/level_template.tscn"
	room.terrain_scene_path = "res://scenes/templates/level_template.tscn"
	room.spawn_ids = PackedStringArray(["start"])
	var world: Resource = WORLD_DATA.new()
	world.world_id = world_id
	world.start_room_id = "room_a"
	world.start_spawn_id = "start"
	world.rooms.assign([room])
	return world
