extends Node

const PREVIEW_PATH := "res://addons/wellwell_world_editor/world_terrain_preview_layer.gd"
const TERRAIN_PATH := "user://terrain_preview_fixture.tscn"
const WORLD_DATA := preload("res://scripts/world/world_data.gd")
const ROOM_DATA := preload("res://scripts/world/room_data.gd")
const LAYER_NAMES: Array[String] = ["BackTiles", "SolidTiles", "GlassTiles", "VisionBlockTiles", "DetailTiles", "MarkerTiles"]


func run() -> Array[String]:
	var failures: Array[String] = []
	_remove_fixture()
	if _save_fixture() != OK:
		return ["could not save terrain preview fixture"]
	var script := load(PREVIEW_PATH) as Script
	if script == null or not script.can_instantiate():
		_remove_fixture()
		return ["world terrain preview layer could not be loaded"]
	var world: Resource = WORLD_DATA.new()
	var room: Resource = ROOM_DATA.new()
	room.room_id = "room_a"
	room.terrain_scene_path = TERRAIN_PATH
	room.room_size_chunks = Vector2i(2, 1)
	world.rooms.assign([room])
	world.normalize_room_placements()
	world.set_room_origin_chunk("room_a", Vector2i(-1, 2))
	var preview: Control = script.new() as Control
	preview.call("set_view_transform", Vector2.ZERO, 1.0, Vector2(640, 360))
	preview.call("sync_world", world)
	var container: Control = preview.get_node_or_null("room_a") as Control
	if container == null:
		failures.append("terrain preview did not create a room container")
	else:
		if container.position != Vector2(-320, 360) + Vector2(320, 180):
			failures.append("terrain preview container did not use placement pixel origin")
		if container.size != Vector2(640, 180):
			failures.append("terrain preview container size did not match room chunks")
		if container.mouse_filter != Control.MOUSE_FILTER_IGNORE or not container.clip_contents:
			failures.append("terrain preview container was not clipped and input-transparent")
		if container.z_index < 0:
			failures.append("terrain preview was rendered behind the opaque canvas background")
		var terrain := container.get_child(0) as Node
		if terrain == null:
			failures.append("terrain preview container did not instantiate generated terrain")
		else:
			if not terrain.visible:
				failures.append("terrain preview root was hidden by layer filtering")
			for layer_name: String in LAYER_NAMES:
				var layer := terrain.get_node_or_null("Terrain/%s" % layer_name) as TileMapLayer
				if layer == null:
					continue
				var should_show := layer_name != "MarkerTiles"
				if layer.visible != should_show:
					failures.append("terrain preview visibility was wrong for %s" % layer_name)
				if layer.process_mode != Node.PROCESS_MODE_DISABLED:
					failures.append("terrain preview did not disable processing for %s" % layer_name)
			var extra := terrain.get_node_or_null("Terrain/Extra") as CanvasItem
			if extra != null and extra.visible:
				failures.append("terrain preview left an extra terrain CanvasItem visible")
	preview.free()
	_remove_fixture()
	return failures


func _save_fixture() -> Error:
	var root := Node2D.new()
	root.name = "TerrainPreviewFixture"
	var background := Node2D.new()
	background.name = "Background"
	root.add_child(background)
	background.owner = root
	var terrain := Node2D.new()
	terrain.name = "Terrain"
	root.add_child(terrain)
	terrain.owner = root
	for layer_name: String in LAYER_NAMES:
		var layer := TileMapLayer.new()
		layer.name = layer_name
		terrain.add_child(layer)
		layer.owner = root
	var extra := Node2D.new()
	extra.name = "Extra"
	terrain.add_child(extra)
	extra.owner = root
	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	root.free()
	return pack_error if pack_error != OK else ResourceSaver.save(packed, TERRAIN_PATH)


func _remove_fixture() -> void:
	if FileAccess.file_exists(TERRAIN_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TERRAIN_PATH))
