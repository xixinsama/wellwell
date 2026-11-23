extends Node

const TEMPLATE_SCENE := preload("res://scenes/rooms/template/level_template.tscn")
const BAKER_SCRIPT := preload("res://addons/world_editor/authoring/room/room_baker.gd")
const ROOM_GRID := preload("res://addons/platformer_kit/world/data/room_grid.gd")


func run() -> Array[String]:
	var failures: Array[String] = []
	var root := TEMPLATE_SCENE.instantiate()
	var layer := root.get_node_or_null("RoomContent/Terrain/SolidTiles") as TileMapLayer
	if layer == null or layer.tile_set == null:
		root.free()
		return ["level template has no usable SolidTiles layer"]
	var source_id := _first_source_id(layer)
	var atlas := _first_atlas_coords(layer, source_id)
	if source_id < 0 or atlas.x < 0:
		root.free()
		return ["level template tileset has no atlas tile to test with"]
	layer.clear()
	layer.set_cell(Vector2i(0, 0), source_id, atlas)
	layer.set_cell(Vector2i(39, 22), source_id, atlas)
	layer.set_cell(Vector2i(0, 29), source_id, atlas)
	var baker := BAKER_SCRIPT.new()
	var dropped: int = baker.call("_crop_tile_layers", layer, Vector2i.ZERO, Vector2i.ONE)
	if dropped != 1:
		failures.append("even-row room cropped %d cells instead of 1" % dropped)
	if layer.get_used_cells().has(Vector2i(0, 29)):
		failures.append("terrain outside the room's cell frame survived the crop")
	if not layer.get_used_cells().has(Vector2i(39, 22)):
		failures.append("terrain inside the 23-cell even row was cropped")

	# An odd chunk row is one cell shorter, so its last row is the 22nd.
	layer.clear()
	layer.set_cell(Vector2i(0, 21), source_id, atlas)
	layer.set_cell(Vector2i(0, 22), source_id, atlas)
	var dropped_odd: int = baker.call("_crop_tile_layers", layer, Vector2i(0, 1), Vector2i.ONE)
	if dropped_odd != 1:
		failures.append("odd-row room cropped %d cells instead of 1" % dropped_odd)
	if layer.get_used_cells().has(Vector2i(0, 22)):
		failures.append("odd-row room kept a cell past its 22nd row")
	if not layer.get_used_cells().has(Vector2i(0, 21)):
		failures.append("odd-row room cropped a cell inside its frame")

	# A 2x2 room has four blocks: rows alternate 23 / 22 by world parity.
	var blocks := ROOM_GRID.get_room_block_cell_rects(Vector2i(0, 0), Vector2i(2, 2))
	if blocks.size() != 4:
		failures.append("2x2 room returned %d block frames instead of 4" % blocks.size())
	elif blocks[1] != Rect2i(40, 0, 40, 23) or blocks[2] != Rect2i(0, 23, 40, 22):
		failures.append("2x2 block frames are not cell-aligned: %s" % str(blocks))
	root.free()
	return failures


func _first_source_id(layer: TileMapLayer) -> int:
	var tile_set := layer.tile_set
	for index: int in tile_set.get_source_count():
		var source_id := tile_set.get_source_id(index)
		if source_id >= 0:
			return source_id
	return -1


func _first_atlas_coords(layer: TileMapLayer, source_id: int) -> Vector2i:
	if source_id < 0:
		return Vector2i(-1, -1)
	var source := layer.tile_set.get_source(source_id) as TileSetAtlasSource
	if source == null or source.get_tiles_count() <= 0:
		return Vector2i(-1, -1)
	return source.get_tile_id(0)
