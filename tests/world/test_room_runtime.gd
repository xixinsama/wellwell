extends Node

const ROOM_DATA: Script = preload("res://scripts/world/room_data.gd")
const ROOM_RUNTIME: Script = preload("res://scripts/world/room_runtime.gd")

const FIXTURE_PATH := "user://runtime_room_fixture.tscn"


func run() -> Array[String]:
	var failures: Array[String] = []
	_save_room_fixture()
	_assert_room_runtime_instances_scene_and_applies_position(failures)
	_assert_room_runtime_rejects_missing_scene(failures)
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


func _assert_room_runtime_rejects_missing_scene(failures: Array[String]) -> void:
	var data: Resource = ROOM_DATA.new()
	data.room_id = "missing"
	data.scene_path = "user://missing_room_runtime_fixture.tscn"
	var runtime: Node2D = ROOM_RUNTIME.new() as Node2D

	if runtime.setup_room(data):
		failures.append("room runtime accepted a missing scene")
	if runtime.get_room_instance() != null:
		failures.append("room runtime kept an instance after failed setup")
	runtime.free()


func _save_room_fixture() -> void:
	var root := Node2D.new()
	root.name = "RoomRoot"
	for child_name: String in ["BackTiles", "SolidTiles", "GlassTiles", "VisionBlockTiles", "DetailTiles", "MarkerTiles", "Entities"]:
		var child := Node2D.new()
		child.name = child_name
		root.add_child(child)
		child.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, FIXTURE_PATH)
	root.free()
