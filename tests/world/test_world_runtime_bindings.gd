extends Node

## Merged test suite. Every inner class below is one original test file,
## kept in its own class so fixtures and helper names stay isolated. Do not
## add logic here: split a class back into its own file when it grows.

## tests/world/test_runtime_bindings.gd
class RuntimeBindingsCase extends Node:
	const PIXEL_CAMERA: Script = preload("res://addons/platformer_kit/camera/pixel_camera_2d.gd")
	const DEBUG_HUD: Script = preload("res://addons/platformer_debug/runtime/debug_hud.gd")
	const FOG_OF_WAR: Script = preload("res://addons/metroidvania_kit/map/discovery/fog_of_war.gd")
	const ROOM_DATA: Script = preload("res://addons/platformer_kit/world/data/room_data.gd")


	class DebugPlayer extends Node:
		func get_debug_state() -> Dictionary:
			return {"velocity": Vector2(12.0, -4.0), "on_floor": true}


	class PersistenceSource extends Node:
		func get_explored_cells() -> Array[String]:
			return ["room_b:80,23"]


	func run() -> Array[String]:
		var failures: Array[String] = []
		_assert_explicit_player_bindings(failures)
		_assert_fog_binds_explicit_room_context(failures)
		return failures


	func _assert_explicit_player_bindings(failures: Array[String]) -> void:
		var root := Node.new()
		var player := Node2D.new()
		player.global_position = Vector2(17.25, 28.75)
		root.add_child(player)
		var camera := PIXEL_CAMERA.new() as Camera2D
		root.add_child(camera)
		add_child(root)
		camera.bind_target(player)
		if camera.target != player or camera.global_position != player.global_position.round():
			failures.append("pixel camera did not retain the explicit player binding")
		var hud := DEBUG_HUD.new() as Control
		var label := Label.new()
		label.name = "Label"
		hud.add_child(label)
		root.add_child(hud)
		var debug_player := DebugPlayer.new()
		root.add_child(debug_player)
		hud.bind_player(debug_player)
		hud._process(0.0)
		if hud.player != debug_player or not label.text.contains("relative 12.0, -4.0"):
			failures.append("debug HUD did not retain the explicit player binding")
		remove_child(root)
		root.free()


	func _assert_fog_binds_explicit_room_context(failures: Array[String]) -> void:
		var root := Node2D.new()
		var player := Node2D.new()
		player.global_position = Vector2(4.0, 4.0)
		root.add_child(player)
		var terrain := _make_terrain_root()
		root.add_child(terrain)
		var fog := FOG_OF_WAR.new() as Node2D
		root.add_child(fog)
		fog.bind_player(player)
		var persistence := PersistenceSource.new()
		root.add_child(persistence)
		fog.bind_persistence_source(persistence)
		add_child(root)
		var room: Resource = ROOM_DATA.new()
		room.room_id = "room_b"
		room.room_size_chunks = Vector2i.ONE
		if not fog.bind_room_with_origin(room, terrain, Vector2i(2, 1)):
			failures.append("FogOfWar rejected explicit room and terrain context")
		elif fog.level_id != "room_b" or fog.map_origin_cell != Vector2i(80, 23) or fog.map_size_cells != Vector2i(40, 22):
			failures.append("FogOfWar did not derive exact room fog bounds")
		elif not fog.is_cell_explored(Vector2i(80, 23)):
			failures.append("FogOfWar did not restore exploration for the explicit room")
		fog.clear_room()
		if fog.get("_vision_block_tiles") != null or not fog.currently_visible.is_empty():
			failures.append("FogOfWar clear_room retained explicit room bindings")
		remove_child(root)
		root.free()


	func _make_terrain_root() -> Node2D:
		var root := Node2D.new()
		var background := Node2D.new()
		background.name = "Background"
		root.add_child(background)
		var terrain := Node2D.new()
		terrain.name = "Terrain"
		root.add_child(terrain)
		for layer_name: String in ["BackTiles", "SolidTiles", "GlassTiles", "VisionBlockTiles", "DetailTiles", "MarkerTiles"]:
			var layer := TileMapLayer.new()
			layer.name = layer_name
			terrain.add_child(layer)
		return root


## tests/world/test_room_runtime.gd
class RoomRuntimeCase extends Node:
	const ROOM_DATA: Script = preload("res://addons/platformer_kit/world/data/room_data.gd")
	const ROOM_RUNTIME: Script = preload("res://addons/platformer_kit/world/runtime/room_runtime.gd")
	const ROOM_ENTRANCE: Script = preload("res://addons/platformer_kit/world/entities/room_entrance.gd")
	const SPAWN_POINT: Script = preload("res://addons/platformer_kit/world/entities/spawn_point.gd")
	const DERIVED_SPAWN_POINT: Script = preload("res://tests/world/derived_spawn_point_fixture.gd")

	const FIXTURE_PATH := "user://runtime_room_fixture.tscn"
	const RUNTIME_ONLY_FIXTURE_PATH := "user://runtime_room_only_fixture.tscn"
	const MISSING_FIXTURE_PATH := "user://missing_room_runtime_fixture.tscn"


	func run() -> Array[String]:
		var failures: Array[String] = []
		var save_error := _save_room_fixture()
		if save_error != OK:
			failures.append("room runtime fixture save failed: %d" % save_error)
			return failures
		var runtime_only_save_error := _save_runtime_only_fixture()
		if runtime_only_save_error != OK:
			failures.append("runtime-only fixture save failed: %d" % runtime_only_save_error)
			_remove_user_file(FIXTURE_PATH)
			return failures
		_assert_room_runtime_instances_scene_and_applies_position(failures)
		_assert_room_runtime_requires_explicit_world_placement(failures)
		_assert_room_runtime_exposes_spawns_and_transition_requests(failures)
		_assert_room_runtime_relays_entity_save_requests(failures)
		_assert_room_runtime_ignores_missing_terrain_scene(failures)
		_assert_room_runtime_rejects_missing_scene(failures)
		_assert_room_runtime_rejects_wrong_resource_type(failures)
		_remove_user_file(FIXTURE_PATH)
		_remove_user_file(RUNTIME_ONLY_FIXTURE_PATH)
		return failures


	func _assert_room_runtime_relays_entity_save_requests(failures: Array[String]) -> void:
		var data: Resource = ROOM_DATA.new()
		data.room_id = "room_a"
		data.scene_path = FIXTURE_PATH
		var runtime: Node2D = ROOM_RUNTIME.new() as Node2D
		if not runtime.setup_room(data, "world_a", null, Vector2i.ZERO):
			failures.append("room runtime could not load save-request fixture")
			runtime.free()
			return
		if not runtime.has_signal("save_requested"):
			failures.append("room runtime does not expose entity save requests")
			runtime.free()
			return
		var requests: Array[bool] = []
		runtime.connect("save_requested", func(immediate: bool) -> void: requests.append(immediate))
		var entrance: Node = runtime.get_entity("exit_right")
		if entrance == null or not entrance.has_method("request_save"):
			failures.append("room save-request fixture has no requesting entity")
		else:
			entrance.call("request_save", true)
			if requests != [true]:
				failures.append("room runtime did not relay an entity save request")
		runtime.free()


	func _assert_room_runtime_instances_scene_and_applies_position(failures: Array[String]) -> void:
		var data: Resource = ROOM_DATA.new()
		data.room_id = "room_a"
		data.scene_path = FIXTURE_PATH
		data.room_size_chunks = Vector2i(3, 2)
		var runtime: Node2D = ROOM_RUNTIME.new() as Node2D

		if not runtime.setup_room(data, "world_a", null, Vector2i(2, 1)):
			failures.append("room runtime did not load a valid room")
		if runtime.get_room_id() != "room_a":
			failures.append("room runtime returned the wrong room id")
		if runtime.position != Vector2(640, 184):
			failures.append("room runtime did not apply cell-aligned world position")
		if runtime.get_room_instance() == null:
			failures.append("room runtime did not keep the room instance")
		if runtime.get_layer_node("SolidTiles") == null:
			failures.append("room runtime did not expose SolidTiles")
		if runtime.get_entities_root() == null:
			failures.append("room runtime did not expose Entities")
		if runtime.get_room_chunk_rect() != Rect2i(2, 1, 3, 2):
			failures.append("room runtime returned the wrong chunk rect")
		if runtime.get_room_cell_rect() != Rect2i(80, 23, 120, 45):
			failures.append("room runtime returned the wrong cell rect")
		runtime.free()


	func _assert_room_runtime_requires_explicit_world_placement(failures: Array[String]) -> void:
		var data: Resource = ROOM_DATA.new()
		data.room_id = "room_a"
		data.scene_path = FIXTURE_PATH
		data.room_size_chunks = Vector2i(2, 1)
		var runtime: Node2D = ROOM_RUNTIME.new() as Node2D
		if runtime.setup_room(data):
			failures.append("room runtime accepted an implicit room placement")
		if not runtime.call("setup_room", data, "world_a", null, Vector2i(-1, 2)):
			failures.append("room runtime rejected an explicit world placement")
		else:
			if runtime.position != Vector2(-320, 360):
				failures.append("room runtime did not use explicit world placement")
			if runtime.call("get_room_chunk_rect") != Rect2i(-1, 2, 2, 1):
				failures.append("room runtime chunk rect ignored explicit world placement")
		runtime.free()


	func _assert_room_runtime_exposes_spawns_and_transition_requests(failures: Array[String]) -> void:
		var data: Resource = ROOM_DATA.new()
		data.room_id = "room_a"
		data.scene_path = FIXTURE_PATH
		var runtime: Node2D = ROOM_RUNTIME.new() as Node2D
		if not runtime.setup_room(data, "world_a", null, Vector2i(2, 1)):
			failures.append("room runtime could not load spawn fixture")
			runtime.free()
			return
		if not runtime.has_method("get_spawn_point"):
			failures.append("room runtime did not expose spawn lookup")
		else:
			var spawn: Node2D = runtime.call("get_spawn_point", "entry") as Node2D
			if spawn == null or spawn.global_position != Vector2(648.0, 196.0):
				failures.append("room runtime did not resolve the room-local spawn position")
			if runtime.call("get_spawn_point", "missing") != null:
				failures.append("room runtime resolved an unknown spawn")
			if runtime.call("get_spawn_point", "derived") == null:
				failures.append("room runtime did not resolve a derived SpawnPoint")

		if not runtime.has_signal("transition_requested"):
			failures.append("room runtime did not expose transition requests")
		else:
			var requests: Array[Node] = []
			runtime.connect("transition_requested", func(entrance: Node) -> void: requests.append(entrance))
			var entrance: Node = runtime.get_entity("exit_right")
			if entrance == null:
				failures.append("room runtime did not expose the entrance fixture")
			else:
				entrance.call("request_transition")
				if requests != [entrance]:
					failures.append("room runtime did not relay an entrance transition request")
		runtime.free()


	func _assert_room_runtime_ignores_missing_terrain_scene(failures: Array[String]) -> void:
		_remove_user_file(MISSING_FIXTURE_PATH)
		var data: Resource = ROOM_DATA.new()
		data.room_id = "runtime_only"
		data.scene_path = RUNTIME_ONLY_FIXTURE_PATH
		data.terrain_scene_path = MISSING_FIXTURE_PATH
		var runtime: Node2D = ROOM_RUNTIME.new() as Node2D
		if not runtime.setup_room(data, "world_a", null, Vector2i.ZERO):
			failures.append("room runtime let missing terrain_scene_path affect runtime setup")
		else:
			var instance: Node = runtime.get_room_instance()
			if instance == null:
				failures.append("room runtime lost its runtime scene while ignoring terrain")
			else:
				for terrain_node_name: String in [
					"Background", "Terrain", "BackTiles", "SolidTiles", "GlassTiles",
					"VisionBlockTiles", "DetailTiles", "MarkerTiles",
				]:
					if instance.get_node_or_null(terrain_node_name) != null:
						failures.append("room runtime instance unexpectedly contained terrain node: %s" % terrain_node_name)
		runtime.free()


	func _assert_room_runtime_rejects_missing_scene(failures: Array[String]) -> void:
		_remove_user_file(MISSING_FIXTURE_PATH)
		var data: Resource = ROOM_DATA.new()
		data.room_id = "missing"
		data.scene_path = MISSING_FIXTURE_PATH
		var runtime: Node2D = ROOM_RUNTIME.new() as Node2D

		if runtime.setup_room(data):
			failures.append("room runtime accepted a missing scene")
		if runtime.get_room_instance() != null:
			failures.append("room runtime kept an instance after failed setup")
		if runtime.get_room_id() != "":
			failures.append("room runtime exposed room id after failed setup")
		if runtime.get_room_data() != null:
			failures.append("room runtime exposed room data after failed setup")
		runtime.free()


	func _assert_room_runtime_rejects_wrong_resource_type(failures: Array[String]) -> void:
		var runtime: Node2D = ROOM_RUNTIME.new() as Node2D
		if runtime.setup_room(Resource.new()):
			failures.append("room runtime accepted a non-RoomData resource")
		if runtime.get_room_data() != null:
			failures.append("room runtime kept wrong resource data")
		runtime.free()


	func _save_room_fixture() -> Error:
		var root := Node2D.new()
		root.name = "RoomRoot"
		for child_name: String in ["BackTiles", "SolidTiles", "GlassTiles", "VisionBlockTiles", "DetailTiles", "MarkerTiles", "Entities"]:
			var child := Node2D.new()
			child.name = child_name
			root.add_child(child)
			child.owner = root
		var entities: Node = root.get_node("Entities")
		var spawn: Marker2D = SPAWN_POINT.new() as Marker2D
		spawn.name = "EntrySpawn"
		spawn.position = Vector2(8.0, 12.0)
		spawn.set("spawn_id", "entry")
		entities.add_child(spawn)
		spawn.owner = root
		var derived_spawn: Marker2D = DERIVED_SPAWN_POINT.new() as Marker2D
		derived_spawn.name = "DerivedSpawn"
		derived_spawn.set("spawn_id", "derived")
		entities.add_child(derived_spawn)
		derived_spawn.owner = root
		var entrance: Node = ROOM_ENTRANCE.new()
		entrance.name = "ExitRight"
		entrance.set("entity_id", "exit_right")
		entities.add_child(entrance)
		entrance.owner = root
		var packed := PackedScene.new()
		packed.pack(root)
		var error := ResourceSaver.save(packed, FIXTURE_PATH)
		root.free()
		return error


	func _save_runtime_only_fixture() -> Error:
		var root := Node2D.new()
		root.name = "RuntimeOnlyRoom"
		for child_name: String in ["Entities", "Foreground"]:
			var child := Node2D.new()
			child.name = child_name
			root.add_child(child)
			child.owner = root
		var packed := PackedScene.new()
		var pack_error := packed.pack(root)
		root.free()
		if pack_error != OK:
			return pack_error
		return ResourceSaver.save(packed, RUNTIME_ONLY_FIXTURE_PATH)


	func _remove_user_file(path: String) -> void:
		var absolute_path := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(absolute_path)


## tests/world/test_world_terrain_runtime.gd
class WorldTerrainRuntimeCase extends Node:
	const ROOM_DATA: Script = preload("res://addons/platformer_kit/world/data/room_data.gd")
	const WORLD_DATA: Script = preload("res://addons/platformer_kit/world/data/world_data.gd")
	const TERRAIN_RUNTIME_PATH := "res://addons/platformer_kit/world/runtime/world_terrain_runtime.gd"
	const TERRAIN_A_PATH := "user://task7_terrain_a.tscn"
	const TERRAIN_B_PATH := "user://task7_terrain_b.tscn"
	const BROKEN_TERRAIN_PATH := "user://task7_broken_terrain.tscn"
	const MISSING_TERRAIN_PATH := "user://task7_missing_terrain.tscn"
	const TERRAIN_LAYER_NAMES: Array[String] = [
		"BackTiles", "SolidTiles", "DetailTiles"
	]


	func run() -> Array[String]:
		var failures: Array[String] = []
		var runtime_script := _load_runtime_script(failures)
		if runtime_script == null:
			return failures
		if not _has_runtime_api(runtime_script, failures):
			return failures
		_remove_user_files()
		var fixture_error := _save_terrain_fixtures()
		if fixture_error != OK:
			failures.append("world terrain fixture save failed: %d" % fixture_error)
			_remove_user_files()
			return failures
		_assert_setup_positions_and_idempotence(runtime_script, failures)
		_assert_failed_setup_preserves_previous_world(runtime_script, failures)
		_assert_clear_removes_all_terrain(runtime_script, failures)
		_remove_user_files()
		return failures


	func _load_runtime_script(failures: Array[String]) -> Script:
		if not FileAccess.file_exists(TERRAIN_RUNTIME_PATH):
			failures.append("missing production API: %s" % TERRAIN_RUNTIME_PATH)
			return null
		var runtime_script := load(TERRAIN_RUNTIME_PATH) as Script
		if runtime_script == null:
			failures.append("could not load production API: %s" % TERRAIN_RUNTIME_PATH)
		return runtime_script


	func _has_runtime_api(runtime_script: Script, failures: Array[String]) -> bool:
		var runtime: Object = runtime_script.new()
		if runtime == null or not runtime is Node2D:
			failures.append("WorldTerrainRuntime must instantiate as Node2D")
			return false
		var required_methods := ["setup_world", "get_room_terrain", "clear_world"]
		for method_name: String in required_methods:
			if not runtime.has_method(method_name):
				failures.append("WorldTerrainRuntime missing method: %s" % method_name)
		runtime.free()
		return failures.is_empty()


	func _assert_setup_positions_and_idempotence(runtime_script: Script, failures: Array[String]) -> void:
		var world: Resource = _make_world([
			_make_room("room_a", Vector2i(2, -1), TERRAIN_A_PATH),
			_make_room("room_b", Vector2i(-1, 3), TERRAIN_B_PATH),
		])
		var runtime: Node2D = runtime_script.new() as Node2D
		if not bool(runtime.call("setup_world", world)):
			failures.append("world terrain runtime rejected valid terrain scenes")
			runtime.free()
			return
		if runtime.get_child_count() != 2:
			failures.append("world terrain runtime did not instantiate exactly one terrain per room")
		var terrain_a: Node = runtime.call("get_room_terrain", "room_a") as Node
		var terrain_b: Node = runtime.call("get_room_terrain", "room_b") as Node
		if terrain_a == null or terrain_b == null:
			failures.append("world terrain runtime did not expose both room terrain instances")
		else:
			if terrain_a.position != Vector2(640.0, -184.0):
				failures.append("room_a terrain position was not cell-aligned")
			if terrain_b.position != Vector2(-320.0, 544.0):
				failures.append("room_b terrain position was not cell-aligned")
		var first_a := terrain_a
		var equivalent_world: Resource = _make_world([
			_make_room("room_a", Vector2i(2, -1), TERRAIN_A_PATH),
			_make_room("room_b", Vector2i(-1, 3), TERRAIN_B_PATH),
		])
		if not bool(runtime.call("setup_world", equivalent_world)):
			failures.append("repeated world terrain setup rejected an equivalent world")
		if runtime.get_child_count() != 2:
			failures.append("repeated world terrain setup accumulated duplicate nodes")
		if first_a != runtime.call("get_room_terrain", "room_a"):
			failures.append("repeated equivalent setup replaced the existing terrain node")
		runtime.free()


	func _assert_failed_setup_preserves_previous_world(runtime_script: Script, failures: Array[String]) -> void:
		var good_world: Resource = _make_world([
			_make_room("room_a", Vector2i.ZERO, TERRAIN_A_PATH),
			_make_room("room_b", Vector2i(1, 1), TERRAIN_B_PATH),
		])
		var bad_world: Resource = _make_world([
			_make_room("room_a", Vector2i(9, 9), TERRAIN_A_PATH),
			_make_room("room_b", Vector2i(10, 10), MISSING_TERRAIN_PATH),
		])
		var runtime: Node2D = runtime_script.new() as Node2D
		if not bool(runtime.call("setup_world", good_world)):
			failures.append("could not establish valid old terrain world")
			runtime.free()
			return
		var old_a: Node = runtime.call("get_room_terrain", "room_a") as Node
		var old_b: Node = runtime.call("get_room_terrain", "room_b") as Node
		if bool(runtime.call("setup_world", bad_world)):
			failures.append("world terrain runtime accepted a missing terrain scene")
		if runtime.get_child_count() != 2:
			failures.append("failed terrain setup did not preserve the old node count")
		if old_a != runtime.call("get_room_terrain", "room_a") or old_b != runtime.call("get_room_terrain", "room_b"):
			failures.append("failed terrain setup replaced the previous world or nodes")
		if runtime.call("get_room_terrain", "room_a").position != Vector2.ZERO:
			failures.append("failed terrain setup changed the previous room position")
		var broken_world: Resource = _make_world([
			_make_room("room_a", Vector2i(9, 9), BROKEN_TERRAIN_PATH),
		])
		if bool(runtime.call("setup_world", broken_world)):
			failures.append("world terrain runtime accepted structurally broken terrain")
		if old_a != runtime.call("get_room_terrain", "room_a") or old_b != runtime.call("get_room_terrain", "room_b"):
			failures.append("broken terrain setup replaced the previous world or nodes")
		runtime.free()


	func _assert_clear_removes_all_terrain(runtime_script: Script, failures: Array[String]) -> void:
		var runtime: Node2D = runtime_script.new() as Node2D
		var world: Resource = _make_world([_make_room("room_a", Vector2i(1, 2), TERRAIN_A_PATH)])
		if not bool(runtime.call("setup_world", world)):
			failures.append("could not establish terrain before clear")
		else:
			runtime.call("clear_world")
			if runtime.get_child_count() != 0:
				failures.append("clear_world did not remove all terrain instances")
			if runtime.call("get_room_terrain", "room_a") != null:
				failures.append("clear_world kept a room terrain lookup result")
		runtime.free()


	func _make_world(rooms: Array) -> Resource:
		var world: Resource = WORLD_DATA.new()
		world.world_id = "task7_world"
		world.rooms.assign(rooms)
		for room: Resource in rooms:
			world.set_room_origin_chunk(room.room_id, room.get_meta("test_origin", Vector2i.ZERO))
		return world


	func _make_room(room_id: String, origin: Vector2i, terrain_path: String) -> Resource:
		var room: Resource = ROOM_DATA.new()
		room.room_id = room_id
		room.set_meta("test_origin", origin)
		room.room_size_chunks = Vector2i.ONE
		room.terrain_scene_path = terrain_path
		return room


	func _save_terrain_fixtures() -> Error:
		var result := _save_terrain_fixture(TERRAIN_A_PATH, "TerrainA", true)
		if result != OK:
			return result
		result = _save_terrain_fixture(TERRAIN_B_PATH, "TerrainB", true)
		if result != OK:
			return result
		return _save_terrain_fixture(BROKEN_TERRAIN_PATH, "BrokenTerrain", false)


	func _save_terrain_fixture(path: String, fixture_name: String, complete: bool) -> Error:
		var root := Node2D.new()
		root.name = fixture_name
		var background := Node2D.new()
		background.name = "Background"
		root.add_child(background)
		background.owner = root
		var terrain := Node2D.new()
		terrain.name = "Terrain"
		root.add_child(terrain)
		terrain.owner = root
		var layer_count := TERRAIN_LAYER_NAMES.size() if complete else TERRAIN_LAYER_NAMES.size() - 1
		for index: int in layer_count:
			var layer := TileMapLayer.new()
			layer.name = TERRAIN_LAYER_NAMES[index]
			terrain.add_child(layer)
			layer.owner = root
		var packed := PackedScene.new()
		var pack_error := packed.pack(root)
		root.free()
		if pack_error != OK:
			return pack_error
		return ResourceSaver.save(packed, path)


	func _remove_user_files() -> void:
		for path: String in [TERRAIN_A_PATH, TERRAIN_B_PATH, BROKEN_TERRAIN_PATH, MISSING_TERRAIN_PATH]:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func run() -> Array[String]:
	var failures: Array[String] = []
	failures.append_array(_run_case(RuntimeBindingsCase.new()))
	failures.append_array(_run_case(RoomRuntimeCase.new()))
	failures.append_array(_run_case(WorldTerrainRuntimeCase.new()))
	return failures


func _run_case(test: Node) -> Array[String]:
	add_child(test)
	var result: Array = test.call("run")
	test.queue_free()
	var failures: Array[String] = []
	failures.assign(result)
	return failures
