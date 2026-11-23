extends Node

const ROOM_DATA := preload("res://addons/platformer_kit/world/data/room_data.gd")
const WORLD_DATA := preload("res://addons/platformer_kit/world/data/world_data.gd")
const WORLD_RUNTIME := preload("res://addons/platformer_kit/world/runtime/world_runtime.gd")
const WORLD_SESSION := preload("res://addons/platformer_kit/world/runtime/world_session.gd")
const SAVE_SNAPSHOT := preload("res://addons/platformer_kit/save/save_snapshot.gd")
const SPAWN_POINT := preload("res://addons/platformer_kit/world/entities/spawn_point.gd")
const DOOR_SCENE := "res://addons/platformer_kit/world/entities/world_door.tscn"

const FIXTURE_PATH := "user://world_door_travel_fixture.tscn"
const DOOR_A_POSITION := Vector2(40, 100)
const DOOR_B_POSITION := Vector2(100, 100)
const ARRIVAL_OFFSET := Vector2(20, 0)


class TestPlayer extends Node2D:
	var respawn_count := 0
	func respawn_at(target: Vector2) -> void:
		global_position = target
		respawn_count += 1


class FakeTerrain extends Node2D:
	var room_terrain: Node = Node2D.new()
	var setup_world_ids: Array[String] = []
	func _init() -> void:
		add_child(room_terrain)
	func setup_world(world: Resource) -> bool:
		setup_world_ids.append(world.world_id)
		return true
	func get_room_terrain(_room_id: String) -> Node:
		return room_terrain
	func clear_world() -> void:
		pass


class FakeRuntime extends Node2D:
	var setup_world_ids: Array[String] = []
	var door_calls: Array = []
	var current_room_id := ""
	var player: Node2D
	func setup_session(world: Resource, snapshot: RefCounted, value: Node2D) -> bool:
		setup_world_ids.append(world.world_id)
		player = value
		snapshot.world_id = world.world_id
		current_room_id = world.start_room_id
		if world.has_room(snapshot.respawn_room_id):
			current_room_id = snapshot.respawn_room_id
		snapshot.current_room_id = current_room_id
		if player != null:
			player.global_position = Vector2(320, 64)
		return true
	func get_current_room_id() -> String:
		return current_room_id
	func travel_to_door(room_id: String, door_id: String) -> bool:
		door_calls.append([room_id, door_id])
		return true
	func clear_world() -> void:
		pass
	func persist_loaded_entity_states() -> void:
		pass


class FakeBinding extends Node:
	func bind_target(_value: Node2D) -> void:
		pass
	func bind_player(_value: Node) -> void:
		pass
	func bind_room(_room: Resource, _terrain: Node) -> bool:
		return true
	func bind_room_with_origin(_room: Resource, _terrain: Node, _origin: Vector2i) -> bool:
		return true
	func clear_room() -> void:
		pass
	func set_room_bounds(_value: Rect2) -> void:
		pass
	func clear_room_bounds() -> void:
		pass


class FakeSaveManager extends Node:
	var current_snapshot: RefCounted
	var queued_count := 0
	func queue_commit(_delay_seconds: float = 0.35) -> void:
		queued_count += 1


func run() -> Array[String]:
	var failures: Array[String] = []
	if not ResourceLoader.exists(DOOR_SCENE, "PackedScene"):
		return ["WorldDoor scene is missing: %s" % DOOR_SCENE]
	if _write_room_fixture() != OK:
		return ["world door travel fixture could not be written"]
	_assert_portal_travel_moves_player_and_disarms(failures)
	_assert_portal_pair_is_bidirectional(failures)
	_assert_shuttle_travel_swaps_world_session(failures)
	_assert_shuttle_failure_restores_snapshot(failures)
	_assert_same_world_shuttle_uses_in_world_travel(failures)
	_cleanup_fixture()
	return failures


# --- Runtime: PORTAL ----------------------------------------------------------

func _assert_portal_travel_moves_player_and_disarms(failures: Array[String]) -> void:
	var world := _make_world()
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	var player := TestPlayer.new()
	var runtime := WORLD_RUNTIME.new() as Node2D
	add_child(player)
	add_child(runtime)
	if not runtime.setup_session(world, snapshot, player):
		failures.append("world runtime rejected the door travel fixture")
		runtime.free()
		player.free()
		return
	var room_a: Node = runtime.get_room_runtime("room_a")
	if room_a == null:
		failures.append("door travel fixture did not load its start room")
		runtime.free()
		player.free()
		return
	var door_a: Node = room_a.call("get_entity", "portal_a")
	if door_a == null:
		failures.append("door travel fixture has no portal_a entity")
	elif not bool(door_a.call("activate", null)):
		failures.append("portal_a refused to travel to its partner")
	else:
		var expected := DOOR_B_POSITION + ARRIVAL_OFFSET + Vector2(320, 0)
		if runtime.get_current_room_id() != "room_b":
			failures.append("portal travel did not switch the current room")
		if player.global_position != expected:
			failures.append("portal travel did not land the player on the partner arrival")
		var door_b: Node = runtime.get_room_runtime("room_b").call("get_entity", "portal_b")
		if door_b == null:
			failures.append("portal travel fixture has no portal_b entity in the target room")
		elif bool(door_b.call("is_armed")):
			failures.append("arrival door stayed armed and would bounce the player back")
	runtime.free()
	player.free()


func _assert_portal_pair_is_bidirectional(failures: Array[String]) -> void:
	var world := _make_world()
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	var player := TestPlayer.new()
	var runtime := WORLD_RUNTIME.new() as Node2D
	add_child(player)
	add_child(runtime)
	if not runtime.setup_session(world, snapshot, player):
		failures.append("world runtime rejected the bidirectional door fixture")
		runtime.free()
		player.free()
		return
	var door_a: Node = runtime.get_room_runtime("room_a").call("get_entity", "portal_a")
	door_a.call("activate", null)
	var door_b: Node = runtime.get_room_runtime("room_b").call("get_entity", "portal_b")
	for _index: int in range(WorldDoor.REARM_FRAMES + 1):
		door_b.call("_physics_process", 0.016)
	if not bool(door_b.call("is_armed")):
		failures.append("partner door never re-armed for the return trip")
	elif not bool(door_b.call("activate", null)):
		failures.append("partner door refused the return trip")
	elif runtime.get_current_room_id() != "room_a":
		failures.append("return trip did not come back to the origin room")
	else:
		var expected := DOOR_A_POSITION + ARRIVAL_OFFSET
		if player.global_position != expected:
			failures.append("return trip did not land on the origin door arrival")
	runtime.free()
	player.free()


# --- Session: SHUTTLE ---------------------------------------------------------

func _assert_shuttle_travel_swaps_world_session(failures: Array[String]) -> void:
	var session := _make_session()
	var manager := FakeSaveManager.new()
	add_child(manager)
	session.call("bind_persistence_source", manager)
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	manager.current_snapshot = snapshot
	var world_a := _make_world()
	var world_b := _make_world("world_b")
	if not session.call("start", world_a, snapshot):
		failures.append("world session rejected the shuttle fixture")
		session.free()
		manager.free()
		return
	snapshot.respawn_room_id = "room_a"
	snapshot.respawn_spawn_id = "entry"
	snapshot.set_resume_state(Vector2(4, 8), Vector2.ZERO)
	var travels: Array = []
	session.connect("world_travel_completed", func(from_id: String, to_id: String) -> void:
		travels.append([from_id, to_id])
	)
	manager.queued_count = 0
	if not session.call("travel_to_world", world_b, "room_b", "door_b"):
		failures.append("world session refused a valid cross-world shuttle")
		session.free()
		manager.free()
		return
	if session.get("_active_snapshot") != snapshot:
		failures.append("shuttle replaced the active save snapshot object")
	if snapshot.world_id != "world_b" or snapshot.current_room_id != "room_b":
		failures.append("shuttle did not point the snapshot at the destination world and room")
	if snapshot.has_resume:
		failures.append("shuttle kept stale resume data from the previous world")
	if snapshot.respawn_room_id != "room_b" or snapshot.respawn_spawn_id != "door_b":
		failures.append("shuttle did not seed the respawn identity with the arrival door")
	var player := session.get_node("Player") as Node2D
	if snapshot.respawn_position != player.global_position:
		failures.append("shuttle did not record the arrival position as the respawn")
	if travels != [["world_a", "world_b"]]:
		failures.append("shuttle did not report the world change")
	if manager.queued_count != 1:
		failures.append("shuttle did not queue a snapshot commit")
	var runtime := session.get_node("Runtime") as FakeRuntime
	if runtime.setup_world_ids != ["world_a", "world_b"]:
		failures.append("shuttle did not restage the world runtime on the target world")
	session.free()
	manager.free()


func _assert_shuttle_failure_restores_snapshot(failures: Array[String]) -> void:
	var session := _make_session()
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	var world_a := _make_world()
	if not session.call("start", world_a, snapshot):
		failures.append("world session rejected the shuttle rollback fixture")
		session.free()
		return
	snapshot.respawn_room_id = "room_a"
	snapshot.respawn_spawn_id = "entry"
	snapshot.respawn_position = Vector2(8, 12)
	snapshot.set_resume_state(Vector2(16, 32), Vector2(1, 2))
	var terrain := session.get_node("Terrain") as FakeTerrain
	terrain.setup_world_ids.clear()
	if session.call("travel_to_world", _missing_artifact_world(), "room_b", "door_b"):
		failures.append("world session accepted a cross-world trip to a world without artifacts")
	if snapshot.world_id != "world_a" or snapshot.current_room_id != "room_a":
		failures.append("failed shuttle did not restore the snapshot world identity")
	if snapshot.respawn_room_id != "room_a" or snapshot.respawn_spawn_id != "entry":
		failures.append("failed shuttle did not restore the snapshot respawn identity")
	if snapshot.respawn_position != Vector2(8, 12):
		failures.append("failed shuttle did not restore the snapshot respawn position")
	if not snapshot.has_resume or snapshot.resume_position != Vector2(16, 32):
		failures.append("failed shuttle did not restore the snapshot resume transform")
	if session.get("_active_world") != world_a:
		failures.append("failed shuttle replaced the active world")
	session.free()


func _assert_same_world_shuttle_uses_in_world_travel(failures: Array[String]) -> void:
	var session := _make_session()
	var snapshot: RefCounted = SAVE_SNAPSHOT.new()
	var world_a := _make_world()
	if not session.call("start", world_a, snapshot):
		failures.append("world session rejected the same-world shuttle fixture")
		session.free()
		return
	var runtime := session.get_node("Runtime") as FakeRuntime
	if not session.call("travel_to_world", world_a, "room_b", "portal_b"):
		failures.append("world session refused a same-world shuttle")
	elif runtime.door_calls != [["room_b", "portal_b"]]:
		failures.append("same-world shuttle did not use the in-world travel path")
	session.free()


# --- Fixtures -----------------------------------------------------------------

func _make_session() -> Node:
	var session: Node = WORLD_SESSION.new()
	var terrain := FakeTerrain.new()
	terrain.name = "Terrain"
	session.add_child(terrain)
	var runtime := FakeRuntime.new()
	runtime.name = "Runtime"
	session.add_child(runtime)
	var player := Node2D.new()
	player.name = "Player"
	session.add_child(player)
	var camera := FakeBinding.new()
	camera.name = "Camera"
	session.add_child(camera)
	var hud := FakeBinding.new()
	hud.name = "Hud"
	session.add_child(hud)
	session.set("terrain_runtime_path", NodePath("Terrain"))
	session.set("world_runtime_path", NodePath("Runtime"))
	session.set("player_path", NodePath("Player"))
	session.set("camera_path", NodePath("Camera"))
	session.set("debug_hud_path", NodePath("Hud"))
	return session


func _make_world(world_id: String = "world_a") -> Resource:
	var world: Resource = WORLD_DATA.new()
	world.world_id = world_id
	world.start_room_id = "room_a"
	world.start_spawn_id = "entry"
	for entry: Array in [["room_a", Vector2i.ZERO], ["room_b", Vector2i.RIGHT]]:
		var room: Resource = ROOM_DATA.new()
		room.room_id = entry[0]
		room.scene_path = FIXTURE_PATH
		room.source_scene_path = FIXTURE_PATH
		room.terrain_scene_path = FIXTURE_PATH
		room.room_size_chunks = Vector2i.ONE
		room.spawn_ids = PackedStringArray(["entry", "portal_a", "portal_b"])
		world.rooms.append(room)
		world.set_room_origin_chunk(room.room_id, entry[1])
	return world


## A world whose room artifacts do not exist, so the session preflight rejects it.
func _missing_artifact_world() -> Resource:
	var world: Resource = WORLD_DATA.new()
	world.world_id = "world_missing"
	world.start_room_id = "room_b"
	world.start_spawn_id = "entry"
	var room: Resource = ROOM_DATA.new()
	room.room_id = "room_b"
	room.scene_path = "res://scenes/rooms/generated/missing_room/runtime.tscn"
	room.source_scene_path = "res://scenes/levels/missing_room.tscn"
	room.terrain_scene_path = "res://scenes/rooms/generated/missing_room/terrain.tscn"
	room.room_size_chunks = Vector2i.ONE
	room.spawn_ids = PackedStringArray(["entry"])
	world.rooms.append(room)
	world.set_room_origin_chunk("room_b", Vector2i.ZERO)
	return world


func _write_room_fixture() -> Error:
	var packed := load(DOOR_SCENE) as PackedScene
	if packed == null:
		return ERR_CANT_CREATE
	var root := Node2D.new()
	root.name = "RoomRoot"
	var entities := Node2D.new()
	entities.name = "Entities"
	root.add_child(entities)
	entities.owner = root
	var entry := SPAWN_POINT.new() as Marker2D
	entry.name = "EntrySpawn"
	entry.spawn_id = "entry"
	entry.position = Vector2(8, 12)
	entities.add_child(entry)
	entry.owner = root
	_own_tree(entry, root)
	_add_door_fixture(root, entities, packed, "PortalA", "portal_a", "room_b", "portal_b", DOOR_A_POSITION)
	_add_door_fixture(root, entities, packed, "PortalB", "portal_b", "room_a", "portal_a", DOOR_B_POSITION)
	var scene := PackedScene.new()
	var pack_error := scene.pack(root)
	root.free()
	return pack_error if pack_error != OK else ResourceSaver.save(scene, FIXTURE_PATH)


func _add_door_fixture(
	root: Node,
	entities: Node,
	packed: PackedScene,
	node_name: String,
	door_id: String,
	target_room_id: String,
	target_door_id: String,
	position: Vector2
) -> void:
	var door := packed.instantiate() as Node2D
	door.name = node_name
	door.set("entity_id", door_id)
	door.set("door_kind", 0)
	door.set("target_room_id", target_room_id)
	door.set("target_door_id", target_door_id)
	door.position = position
	# Keep the fixture in the plain source shape: doors arrive through their scene default.
	var arrival := door.get_node_or_null("ArrivalSpawn")
	if arrival is Node2D:
		(arrival as Node2D).position = ARRIVAL_OFFSET
	entities.add_child(door)
	door.owner = root
	_own_tree(door, root)


func _own_tree(node: Node, root: Node) -> void:
	for child: Node in node.get_children():
		child.owner = root
		_own_tree(child, root)


func _cleanup_fixture() -> void:
	if FileAccess.file_exists(FIXTURE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(FIXTURE_PATH))
