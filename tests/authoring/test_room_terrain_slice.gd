extends Node

const BAKER_SCRIPT := preload("res://addons/world_editor/authoring/room/room_baker.gd")
const TERRAIN_PATH := "user://test_world_terrain.tscn"


func run() -> Array[String]:
	var failures: Array[String] = []
	var tile_set := load("res://resources/tilesets/primordial_tileset.tres") as TileSet
	if tile_set == null:
		return ["primordial tileset could not be loaded"]
	var world_root := Node2D.new()
	world_root.name = "WorldTerrain"
	var terrain_root := Node2D.new()
	terrain_root.name = "Terrain"
	world_root.add_child(terrain_root)
	terrain_root.owner = world_root
	var solid := TileMapLayer.new()
	solid.name = "SolidTiles"
	solid.tile_set = tile_set
	terrain_root.add_child(solid)
	solid.owner = world_root
	solid.set_cell(Vector2i(80, 23), 0, Vector2i(1, 0))
	solid.set_cell(Vector2i(81, 23), 0, Vector2i(2, 0))
	solid.set_cell(Vector2i(10, 10), 0, Vector2i(1, 0))
	var packed := PackedScene.new()
	if packed.pack(world_root) != OK or ResourceSaver.save(packed, TERRAIN_PATH) != OK:
		world_root.free()
		return ["could not save the world terrain fixture"]
	world_root.free()

	var room_content := Node2D.new()
	room_content.name = "RoomContent"
	var source_terrain := Node2D.new()
	source_terrain.name = "Terrain"
	room_content.add_child(source_terrain)
	var source_layer := TileMapLayer.new()
	source_layer.name = "SolidTiles"
	source_layer.tile_set = tile_set
	source_terrain.add_child(source_layer)
	var baker := BAKER_SCRIPT.new()
	var result: Dictionary = baker.call(
		"_pack_sliced_terrain", room_content, Vector2i(2, 1), Vector2i.ONE, TERRAIN_PATH
	)
	if not bool(result.get("ok", false)):
		failures.append("slicing failed: %s" % str(result.get("errors", [])))
	else:
		var scene := result["scene"] as PackedScene
		var instance := scene.instantiate()
		var layer := instance.get_node_or_null("Terrain/SolidTiles") as TileMapLayer
		if layer == null:
			failures.append("slice did not keep the SolidTiles layer")
		else:
			if layer.get_cell_source_id(Vector2i(0, 0)) == -1:
				failures.append("slice did not shift the room's first world cell to local (0,0)")
			if layer.get_cell_source_id(Vector2i(1, 0)) == -1:
				failures.append("slice dropped a cell inside the room rectangle")
			if layer.get_used_cells().has(Vector2i(-70, -13)):
				failures.append("slice kept a cell outside the room rectangle")
		instance.free()
	room_content.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TERRAIN_PATH))
	return failures
