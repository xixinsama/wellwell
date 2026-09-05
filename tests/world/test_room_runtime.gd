extends Node

const ROOM_DATA: Script = preload("res://scripts/world/room_data.gd")
const ROOM_RUNTIME: Script = preload("res://scripts/world/room_runtime.gd")
const ROOM_ENTRANCE: Script = preload("res://scripts/world/room_entrance.gd")
const SPAWN_POINT: Script = preload("res://scripts/world/spawn_point.gd")
const DERIVED_SPAWN_POINT: Script = preload("res://tests/world/derived_spawn_point_fixture.gd")

const FIXTURE_PATH := "user://runtime_room_fixture.tscn"
const MISSING_FIXTURE_PATH := "user://missing_room_runtime_fixture.tscn"


func run() -> Array[String]:
	var failures: Array[String] = []
	var save_error := _save_room_fixture()
	if save_error != OK:
		failures.append("room runtime fixture save failed: %d" % save_error)
		return failures
	_assert_room_runtime_instances_scene_and_applies_position(failures)
	_assert_room_runtime_exposes_spawns_and_transition_requests(failures)
	_assert_room_runtime_rejects_missing_scene(failures)
	_assert_room_runtime_rejects_wrong_resource_type(failures)
	return failures


func _assert_room_runtime_instances_scene_and_applies_position(failures: Array[String]) -> void:
	var data: Resource = ROOM_DATA.new()
	data.room_id = "room_a"
	data.scene_path = FIXTURE_PATH
	data.room_origin_chunk = Vector2i(2, 1)
	data.room_size_chunks = Vector2i(3, 2)
	var runtime: Node2D = ROOM_RUNTIME.new() as Node2D

	if not runtime.setup_room(data):
		failures.append("room runtime did not load a valid room")
	if runtime.get_room_id() != "room_a":
		failures.append("room runtime returned the wrong room id")
	if runtime.position != Vector2(640, 180):
		failures.append("room runtime did not apply chunk-derived world position")
	if runtime.get_room_instance() == null:
		failures.append("room runtime did not keep the room instance")
	if runtime.get_layer_node("SolidTiles") == null:
		failures.append("room runtime did not expose SolidTiles")
	if runtime.get_entities_root() == null:
		failures.append("room runtime did not expose Entities")
	if runtime.get_room_chunk_rect() != Rect2i(2, 1, 3, 2):
		failures.append("room runtime returned the wrong chunk rect")
	if runtime.get_room_cell_rect() != Rect2i(80, 23, 120, 46):
		failures.append("room runtime returned the wrong cell rect")
	runtime.free()


func _assert_room_runtime_exposes_spawns_and_transition_requests(failures: Array[String]) -> void:
	var data: Resource = ROOM_DATA.new()
	data.room_id = "room_a"
	data.scene_path = FIXTURE_PATH
	data.room_origin_chunk = Vector2i(2, 1)
	var runtime: Node2D = ROOM_RUNTIME.new() as Node2D
	if not runtime.setup_room(data):
		failures.append("room runtime could not load spawn fixture")
		runtime.free()
		return
	if not runtime.has_method("get_spawn_point"):
		failures.append("room runtime did not expose spawn lookup")
	else:
		var spawn: Node2D = runtime.call("get_spawn_point", "entry") as Node2D
		if spawn == null or spawn.global_position != Vector2(648.0, 192.0):
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
