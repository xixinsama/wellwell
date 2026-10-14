extends SceneTree

## One-shot authoring tool: creates the room_04_00 puzzle room (an inherited
## level-template scene with two authored PuzzlePiece blocks), bakes it, and
## registers it in the_world.tres.
##
## Run with:
##   godot --headless --path . -s res://tools/author_puzzle_room.gd

const ROOM_BAKER := preload("res://addons/world_editor/authoring/room/room_baker.gd")
const ROOM_PLACEMENT := preload("res://addons/platformer_kit/world/data/world_room_placement_data.gd")

const ROOM_ID := "room_04_00"
const SOURCE_PATH := "res://scenes/levels/room_04_00.tscn"
const WORLD_PATH := "res://resources/worlds/the_world.tres"
const ROOM_RESOURCE_PATH := "res://resources/rooms/generated/room_04_00.tres"

const SOURCE_UID := "uid://bjktrijwtwow5"
const TEMPLATE_UID := "uid://oa5ui3h6fkhd"

const FLOOR_ROW_START := 19
const FLOOR_ROW_END := 22
const ROOM_WIDTH_TILES := 40


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []

	if not _author_and_bake_source(failures):
		failures.append("could not author/bake room source")

	if not _register_world(failures):
		failures.append("could not register room in world data")

	for failure: String in failures:
		push_error("author_puzzle_room: %s" % failure)
	print("author_puzzle_room: done with %d failure(s)" % failures.size())
	quit(1 if not failures.is_empty() else 0)


func _author_and_bake_source(failures: Array[String]) -> bool:
	var tile_data_b64 := _build_floor_tile_data_base64()
	if tile_data_b64.is_empty():
		failures.append("could not encode floor tile data")
		return false

	var file := FileAccess.open(SOURCE_PATH, FileAccess.WRITE)
	if file == null:
		failures.append("could not open source scene for writing: %s" % FileAccess.get_open_error())
		return false
	file.store_string(_build_source_text(tile_data_b64))
	file.close()

	var baked_root: Node = (load(SOURCE_PATH) as PackedScene).instantiate()
	if baked_root == null:
		failures.append("could not reload authored source scene")
		return false
	var baker: RefCounted = ROOM_BAKER.new()
	var bake_result: Dictionary = baker.bake(baked_root, SOURCE_PATH)
	baked_root.free()
	if not bake_result.get("ok", false):
		failures.append("bake failed: %s" % bake_result.get("errors", []))
		return false
	return true


func _build_floor_tile_data_base64() -> String:
	var layer := TileMapLayer.new()
	for x in ROOM_WIDTH_TILES:
		for y in range(FLOOR_ROW_START, FLOOR_ROW_END + 1):
			layer.set_cell(Vector2i(x, y), 0, Vector2i.ZERO)
	var data := layer.tile_map_data
	layer.free()
	return Marshalls.raw_to_base64(data)


func _build_source_text(tile_data_b64: String) -> String:
	return """[gd_scene format=3 uid="%s"]

[ext_resource type="PackedScene" uid="%s" path="res://scenes/rooms/template/level_template.tscn" id="1_template"]
[ext_resource type="Script" path="res://scripts/puzzle/view/puzzle_board.gd" id="2_board"]
[ext_resource type="Script" path="res://scripts/puzzle/view/puzzle_piece.gd" id="3_piece"]

[node name="Room_04_00" unique_id=1018949667 instance=ExtResource("1_template")]
room_id = "room_04_00"
display_name = "Klotski Puzzle Room"
preview_spawn_id = "start"

[node name="SolidTiles" parent="RoomContent/Terrain" parent_id_path=PackedInt32Array(708873726) index="1" unique_id=256295016]
tile_map_data = PackedByteArray("%s")

[node name="StartSpawn" parent="RoomContent/Entities" parent_id_path=PackedInt32Array(190854283) index="0" unique_id=1039911569]
position = Vector2(40, 144)

[node name="PuzzleBoard" type="Node2D" parent="RoomContent/Entities" parent_id_path=PackedInt32Array(190854283) index="1" unique_id=1450010001]
position = Vector2(128, 120)
script = ExtResource("2_board")
board_size = Vector2i(8, 4)

[node name="PieceA" type="Polygon2D" parent="RoomContent/Entities/PuzzleBoard" index="0" unique_id=1450010002]
position = Vector2(8, 16)
script = ExtResource("3_piece")
polygon = PackedVector2Array(0, 0, 16, 0, 16, 16, 0, 16)
color = Color(0.9, 0.3, 0.3, 1)

[node name="PieceB" type="Polygon2D" parent="RoomContent/Entities/PuzzleBoard" index="1" unique_id=1450010003]
position = Vector2(40, 16)
script = ExtResource("3_piece")
polygon = PackedVector2Array(0, 0, 8, 0, 8, 8, 16, 8, 16, 16, 0, 16)
color = Color(0.3, 0.6, 0.9, 1)
""" % [SOURCE_UID, TEMPLATE_UID, tile_data_b64]


func _register_world(failures: Array[String]) -> bool:
	var room_data: Resource = load(ROOM_RESOURCE_PATH)
	if room_data == null:
		failures.append("generated RoomData missing at %s" % ROOM_RESOURCE_PATH)
		return false
	var world := load(WORLD_PATH) as WorldData
	if world == null:
		failures.append("could not load world data")
		return false
	if world.has_room(ROOM_ID):
		return true

	world.rooms.append(room_data)
	var placement: Resource = ROOM_PLACEMENT.new()
	placement.room_id = ROOM_ID
	placement.origin_chunk = Vector2i(4, 0)
	world.placements.append(placement)
	world.sort_for_serialization()
	var save_err := ResourceSaver.save(world, WORLD_PATH)
	if save_err != OK:
		failures.append("save world data error: %s" % save_err)
		return false
	return true
