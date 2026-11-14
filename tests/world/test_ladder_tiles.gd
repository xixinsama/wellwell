extends Node

const BUILDER_PATH := "res://scripts/world/ladder_tile_area_builder.gd"
const TILESET_PATH := "res://resources/tilesets/primordial_tileset.tres"
const ROOM_BAKER := preload("res://addons/world_editor/authoring/room/room_baker.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	var script := load(BUILDER_PATH) as Script
	if script == null:
		return ["ladder tile area builder is missing"]
	var terrain := Node2D.new()
	add_child(terrain)
	var tiles := load(TILESET_PATH) as TileSet
	var layer := TileMapLayer.new()
	layer.tile_set = tiles
	terrain.add_child(layer)
	layer.set_cell(Vector2i(0, 0), 0, Vector2i(0, 7), 0)
	layer.set_cell(Vector2i(1, 0), 0, Vector2i(0, 7), 1)
	layer.set_cell(Vector2i(2, 0), 0, Vector2i(0, 6), 0)
	var builder := script.new() as Node2D
	terrain.add_child(builder)
	if builder.get_child_count() != 2:
		failures.append("both ladder alternatives, and only those cells, must create zones")
	for zone: Node in builder.get_children():
		if not zone.is_in_group("ladder_zone") or (zone as Area2D).collision_layer != 4:
			failures.append("generated zone has wrong group or trigger layer")
		var shape := zone.get_node("CollisionShape2D").shape as RectangleShape2D
		if shape.size != Vector2(8, 8):
			failures.append("generated ladder zone has wrong tile size")
	var first := builder.get_child(0) as Node2D
	if first.global_position != layer.to_global(layer.map_to_local(Vector2i.ZERO)):
		failures.append("generated ladder zone position does not match map_to_local")
	builder.call("rebuild")
	if builder.get_child_count() != 2:
		failures.append("rebuild duplicated or lost ladder zones")
	terrain.free()
	_assert_template_and_room_bake(script, failures)
	_assert_baked_output(failures)
	return failures


func _assert_template_and_room_bake(script: Script, failures: Array[String]) -> void:
	var template := load("res://scenes/rooms/template/level_template.tscn") as PackedScene
	if template == null:
		failures.append("level template is missing")
		return
	var template_root := template.instantiate()
	if template_root.get_node_or_null("RoomContent/Terrain/LadderAreaBuilder") == null:
		failures.append("level template has no LadderAreaBuilder")
	template_root.free()
	var room_path := "res://scenes/levels/room_01_00.tscn"
	var packed := load(room_path) as PackedScene
	if packed == null:
		failures.append("room_01_00 is missing")
		return
	var preview := packed.instantiate()
	add_child(preview)
	var source_builder := preview.get_node_or_null("RoomContent/Terrain/LadderAreaBuilder")
	if source_builder == null or source_builder.get_script() != script:
		failures.append("room_01_00 did not inherit the ladder builder")
	elif source_builder.get_child_count() == 0:
		failures.append("user ladder tiles did not generate any runtime zones")
	preview.free()
	var source := packed.instantiate()
	var staged: Dictionary = ROOM_BAKER.new().stage(source, room_path)
	if not staged.get("ok", false):
		failures.append("room_01_00 could not stage ladder terrain: %s" % staged.get("errors", []))
	else:
		var terrain := (staged["terrain_scene"] as PackedScene).instantiate()
		var baked_builder := terrain.get_node_or_null("Terrain/LadderAreaBuilder")
		if baked_builder == null:
			failures.append("baked terrain lost ladder builder")
		elif baked_builder.get_child_count() != 0:
			failures.append("runtime ladder zones were serialized into baked terrain")
		add_child(terrain)
		if baked_builder != null and baked_builder.get_child_count() == 0:
			failures.append("baked terrain did not generate zones at runtime")
		terrain.free()
	source.free()


func _assert_baked_output(failures: Array[String]) -> void:
	var packed := load("res://scenes/rooms/generated/room_01_00/terrain.tscn") as PackedScene
	if packed == null:
		failures.append("baked room_01_00 terrain is missing")
		return
	var terrain := packed.instantiate()
	add_child(terrain)
	var builder := terrain.get_node_or_null("Terrain/LadderAreaBuilder")
	if builder == null or builder.get_child_count() == 0:
		failures.append("saved baked terrain has no runtime ladder zones")
	var expected_uids := {
		"res://resources/rooms/generated/room_01_00.tres": "uid://cu73ap10eduij",
		"res://scenes/rooms/generated/room_01_00/runtime.tscn": "uid://wxounvpgtvcs",
		"res://scenes/rooms/generated/room_01_00/terrain.tscn": "uid://dfsicbqifkxqn",
	}
	for path: String in expected_uids:
		var first_line := FileAccess.get_file_as_string(path).get_slice("\n", 0)
		if not first_line.contains(expected_uids[path]):
			failures.append("room bake did not preserve resource UID: %s" % path)
	terrain.free()
