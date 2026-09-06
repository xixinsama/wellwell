extends Node

const ROOM_DATA: Script = preload("res://scripts/world/room_data.gd")
const WORLD_DATA: Script = preload("res://scripts/world/world_data.gd")
const TERRAIN_RUNTIME_PATH := "res://scripts/world/world_terrain_runtime.gd"
const TERRAIN_A_PATH := "user://task7_terrain_a.tscn"
const TERRAIN_B_PATH := "user://task7_terrain_b.tscn"
const BROKEN_TERRAIN_PATH := "user://task7_broken_terrain.tscn"
const MISSING_TERRAIN_PATH := "user://task7_missing_terrain.tscn"
const TERRAIN_LAYER_NAMES: Array[String] = [
	"BackTiles", "SolidTiles", "GlassTiles", "VisionBlockTiles", "DetailTiles", "MarkerTiles"
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
		if terrain_a.position != Vector2(640.0, -180.0):
			failures.append("room_a terrain position was not origin chunk * (320, 180)")
		if terrain_b.position != Vector2(-320.0, 540.0):
			failures.append("room_b terrain position was not origin chunk * (320, 180)")
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
	return world


func _make_room(room_id: String, origin: Vector2i, terrain_path: String) -> Resource:
	var room: Resource = ROOM_DATA.new()
	room.room_id = room_id
	room.room_origin_chunk = origin
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
