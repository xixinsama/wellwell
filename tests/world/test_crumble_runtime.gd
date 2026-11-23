extends Node

const CRUMBLE_RUNTIME: Script = preload("res://scripts/world/crumble_runtime.gd")
const ROOM_DATA: Script = preload("res://addons/platformer_kit/world/data/room_data.gd")

const CELL := Vector2i(3, 2)
const CRUMBLE_SOLID := Vector2i(3, 0)
const CRUMBLE_ONE_WAY := Vector2i(3, 4)
const PLAIN := Vector2i(0, 0)


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_shake_break_respawn(failures)
	_assert_room_rebind_restores_broken_cell(failures)
	_assert_both_crumble_tiles_are_driven(failures)
	_assert_clear_room_restores(failures)
	_assert_plain_tiles_are_ignored(failures)
	return failures


func _assert_shake_break_respawn(failures: Array[String]) -> void:
	var terrain := _make_terrain()
	add_child(terrain)
	var runtime: Node2D = CRUMBLE_RUNTIME.new() as Node2D
	add_child(runtime)
	var room: Resource = _make_room()
	if not bool(runtime.call("bind_room_with_origin", room, terrain, Vector2i.ZERO)):
		failures.append("crumble runtime rejected a valid terrain binding")
		terrain.free()
		runtime.free()
		return
	var layer := terrain.get_node("Terrain/SolidTiles") as TileMapLayer
	layer.set_cell(CELL, 0, CRUMBLE_SOLID)
	if not bool(runtime.call("trigger_cell", layer, CELL)):
		failures.append("crumble runtime did not accept a cell trigger")
	runtime.call("tick", 0.1)
	if layer.get_cell_source_id(CELL) == -1:
		failures.append("cell was erased before the shake finished")
	runtime.call("tick", 0.2)
	if layer.get_cell_source_id(CELL) != -1:
		failures.append("cell was not erased after the shake")
	runtime.call("tick", 1.6)
	if layer.get_cell_source_id(CELL) == -1:
		failures.append("cell was not written back after the respawn delay")
	terrain.free()
	runtime.free()


func _assert_room_rebind_restores_broken_cell(failures: Array[String]) -> void:
	var first := _make_terrain()
	var second := _make_terrain()
	add_child(first)
	add_child(second)
	var runtime: Node2D = CRUMBLE_RUNTIME.new() as Node2D
	add_child(runtime)
	runtime.call("bind_room_with_origin", _make_room(), first, Vector2i.ZERO)
	var layer := first.get_node("Terrain/SolidTiles") as TileMapLayer
	layer.set_cell(CELL, 0, CRUMBLE_SOLID)
	runtime.call("trigger_cell", layer, CELL)
	runtime.call("tick", 0.3)
	if layer.get_cell_source_id(CELL) != -1:
		failures.append("cell was not erased before the room switch")
	runtime.call("bind_room_with_origin", _make_room(), second, Vector2i(1, 0))
	if layer.get_cell_source_id(CELL) == -1:
		failures.append("room switch did not restore the broken cell in the old room")
	first.free()
	second.free()
	runtime.free()


func _assert_both_crumble_tiles_are_driven(failures: Array[String]) -> void:
	var terrain := _make_terrain()
	add_child(terrain)
	var runtime: Node2D = CRUMBLE_RUNTIME.new() as Node2D
	add_child(runtime)
	runtime.call("bind_room_with_origin", _make_room(), terrain, Vector2i.ZERO)
	var solid := terrain.get_node("Terrain/SolidTiles") as TileMapLayer
	solid.set_cell(Vector2i(1, 1), 0, CRUMBLE_SOLID)
	solid.set_cell(Vector2i(2, 1), 0, CRUMBLE_ONE_WAY)
	runtime.call("trigger_cell", solid, Vector2i(1, 1))
	runtime.call("trigger_cell", solid, Vector2i(2, 1))
	runtime.call("tick", 0.3)
	if solid.get_cell_source_id(Vector2i(1, 1)) != -1:
		failures.append("solid crumble tile was not driven")
	if solid.get_cell_source_id(Vector2i(2, 1)) != -1:
		failures.append("one-way crumble tile was not driven")
	terrain.free()
	runtime.free()


func _assert_clear_room_restores(failures: Array[String]) -> void:
	var terrain := _make_terrain()
	add_child(terrain)
	var runtime: Node2D = CRUMBLE_RUNTIME.new() as Node2D
	add_child(runtime)
	runtime.call("bind_room_with_origin", _make_room(), terrain, Vector2i.ZERO)
	var layer := terrain.get_node("Terrain/SolidTiles") as TileMapLayer
	layer.set_cell(CELL, 0, CRUMBLE_SOLID)
	runtime.call("trigger_cell", layer, CELL)
	runtime.call("tick", 0.3)
	runtime.call("clear_room")
	if layer.get_cell_source_id(CELL) == -1:
		failures.append("clear_room did not restore the erased crumble cell")
	terrain.free()
	runtime.free()


func _assert_plain_tiles_are_ignored(failures: Array[String]) -> void:
	var terrain := _make_terrain()
	add_child(terrain)
	var runtime: Node2D = CRUMBLE_RUNTIME.new() as Node2D
	add_child(runtime)
	runtime.call("bind_room_with_origin", _make_room(), terrain, Vector2i.ZERO)
	var layer := terrain.get_node("Terrain/SolidTiles") as TileMapLayer
	layer.set_cell(CELL, 0, PLAIN)
	if bool(runtime.call("trigger_cell", layer, CELL)):
		failures.append("a non-crumble tile started shaking")
	terrain.free()
	runtime.free()


func _make_room() -> Resource:
	var room: Resource = ROOM_DATA.new()
	room.room_id = "crumble_test"
	room.room_size_chunks = Vector2i.ONE
	return room


func _make_terrain() -> Node2D:
	var root := Node2D.new()
	var terrain := Node2D.new()
	terrain.name = "Terrain"
	root.add_child(terrain)
	var tile_set := _make_tileset()
	for layer_name: String in ["BackTiles", "SolidTiles", "DetailTiles"]:
		var layer := TileMapLayer.new()
		layer.name = layer_name
		layer.tile_set = tile_set
		layer.collision_enabled = layer_name == "SolidTiles"
		terrain.add_child(layer)
	return root


func _make_tileset() -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(8, 8)
	tile_set.add_physics_layer()
	var source := TileSetAtlasSource.new()
	var image := Image.create(32, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = Vector2i(8, 8)
	for coords: Vector2i in [PLAIN, CRUMBLE_SOLID, CRUMBLE_ONE_WAY]:
		source.create_tile(coords)
	tile_set.add_source(source, 0)
	return tile_set
