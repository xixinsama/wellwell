extends Node

## The `(4,0)`–`(5,1)` autotile set must resolve a painted solid region to the
## expected edge/corner/fill tile, and every alternative must be solid.

const TILESET_PATH := "res://resources/tilesets/primordial_tileset.tres"
const TERRAIN_SET := 0
const TERRAIN := 0

const B_RIGHT := TileSet.CELL_NEIGHBOR_RIGHT_SIDE
const B_BOTTOM_RIGHT := TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER
const B_BOTTOM := TileSet.CELL_NEIGHBOR_BOTTOM_SIDE
const B_BOTTOM_LEFT := TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER
const B_LEFT := TileSet.CELL_NEIGHBOR_LEFT_SIDE
const B_TOP_LEFT := TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER
const B_TOP := TileSet.CELL_NEIGHBOR_TOP_SIDE
const B_TOP_RIGHT := TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER

const BIT_ORDER: Array[int] = [
	B_RIGHT, B_BOTTOM_RIGHT, B_BOTTOM, B_BOTTOM_LEFT,
	B_LEFT, B_TOP_LEFT, B_TOP, B_TOP_RIGHT,
]

## Terrain continues toward the listed neighbours. The rim is always drawn on the
## side facing air, so a straight rim omits its own side and keeps the opposite
## side: that bit is what stops a convex corner from matching a straight edge.
const EXPECTED_BITS := {
	"4,0/0": [B_RIGHT, B_BOTTOM_RIGHT, B_BOTTOM, B_BOTTOM_LEFT, B_LEFT],
	"4,0/1": [B_RIGHT, B_LEFT, B_TOP_LEFT, B_TOP, B_TOP_RIGHT],
	"4,0/2": [B_RIGHT, B_BOTTOM_RIGHT, B_BOTTOM, B_TOP, B_TOP_RIGHT],
	"4,0/3": [B_BOTTOM, B_BOTTOM_LEFT, B_LEFT, B_TOP_LEFT, B_TOP],
	"4,1/0": [B_BOTTOM, B_BOTTOM_LEFT, B_LEFT],
	"4,1/1": [B_LEFT, B_TOP_LEFT, B_TOP],
	"4,1/2": [B_RIGHT, B_BOTTOM_RIGHT, B_BOTTOM],
	"4,1/3": [B_RIGHT, B_TOP, B_TOP_RIGHT],
	"5,0/0": [
		B_RIGHT, B_BOTTOM_RIGHT, B_BOTTOM, B_BOTTOM_LEFT,
		B_LEFT, B_TOP_LEFT, B_TOP, B_TOP_RIGHT,
	],
	"5,1/0": [B_RIGHT, B_BOTTOM_RIGHT, B_BOTTOM, B_BOTTOM_LEFT, B_LEFT, B_TOP, B_TOP_RIGHT],
	"5,1/1": [B_RIGHT, B_BOTTOM_RIGHT, B_BOTTOM, B_LEFT, B_TOP_LEFT, B_TOP, B_TOP_RIGHT],
	"5,1/2": [B_RIGHT, B_BOTTOM_RIGHT, B_BOTTOM, B_BOTTOM_LEFT, B_LEFT, B_TOP_LEFT, B_TOP],
	"5,1/3": [B_RIGHT, B_BOTTOM, B_BOTTOM_LEFT, B_LEFT, B_TOP_LEFT, B_TOP, B_TOP_RIGHT],
}


func run() -> Array[String]:
	var failures: Array[String] = []
	var tile_set := load(TILESET_PATH) as TileSet
	if tile_set == null:
		failures.append("primordial tileset could not be loaded")
		return failures
	_assert_terrain_set(tile_set, failures)
	_assert_expected_bits(tile_set, failures)
	_assert_solid(tile_set, failures)
	_assert_block_paint(tile_set, failures)
	_assert_notch_paint(tile_set, failures)
	return failures


func _assert_terrain_set(tile_set: TileSet, failures: Array[String]) -> void:
	if tile_set.get_terrain_sets_count() != 1:
		failures.append("expected one terrain set, found %d" % tile_set.get_terrain_sets_count())
	elif tile_set.get_terrain_set_mode(TERRAIN_SET) != TileSet.TERRAIN_MODE_MATCH_CORNERS_AND_SIDES:
		failures.append("terrain set 0 must match corners and sides")
	if tile_set.get_terrains_count(TERRAIN_SET) != 1:
		failures.append("expected one terrain in set 0")


func _assert_expected_bits(tile_set: TileSet, failures: Array[String]) -> void:
	var source := tile_set.get_source(0) as TileSetAtlasSource
	if source == null:
		failures.append("tileset has no atlas source 0")
		return
	var remaining: Dictionary = EXPECTED_BITS.duplicate()
	for tile_index: int in source.get_tiles_count():
		var atlas := source.get_tile_id(tile_index)
		for alternative_index: int in source.get_alternative_tiles_count(atlas):
			var alternative := source.get_alternative_tile_id(atlas, alternative_index)
			var data := source.get_tile_data(atlas, alternative)
			if data.terrain_set != TERRAIN_SET:
				continue
			var key := "%d,%d/%d" % [atlas.x, atlas.y, alternative]
			if not remaining.has(key):
				failures.append("unexpected terrain tile: %s" % key)
				continue
			var expected: Array = (remaining[key] as Array).duplicate()
			expected.sort()
			if _peering_bits(data) != expected:
				failures.append("%s peering bits are %s, expected %s" % [key, _peering_bits(data), expected])
			remaining.erase(key)
	if not remaining.is_empty():
		failures.append("missing terrain tiles: %s" % remaining.keys())


func _assert_solid(tile_set: TileSet, failures: Array[String]) -> void:
	var source := tile_set.get_source(0) as TileSetAtlasSource
	if source == null:
		return
	for tile_index: int in source.get_tiles_count():
		var atlas := source.get_tile_id(tile_index)
		for alternative_index: int in source.get_alternative_tiles_count(atlas):
			var alternative := source.get_alternative_tile_id(atlas, alternative_index)
			var data := source.get_tile_data(atlas, alternative)
			if data.terrain_set != TERRAIN_SET:
				continue
			var key := "%d,%d/%d" % [atlas.x, atlas.y, alternative]
			if data.get_collision_polygons_count(0) != 1:
				failures.append("%s has no full-cell collision polygon" % key)
				continue
			var points := data.get_collision_polygon_points(0, 0)
			if points.size() != 4:
				failures.append("%s collision polygon has %d points, expected 4" % [key, points.size()])
				continue
			var bounds := Rect2(points[0], Vector2.ZERO)
			for point: Vector2 in points:
				bounds = bounds.expand(point)
			if bounds.position != Vector2(-4.0, -4.0) or bounds.size != Vector2(8.0, 8.0):
				failures.append("%s collision polygon is not the full 8x8 cell" % key)


func _assert_block_paint(tile_set: TileSet, failures: Array[String]) -> void:
	var layer := TileMapLayer.new()
	layer.tile_set = tile_set
	add_child(layer)
	var cells: Array[Vector2i] = []
	for y in range(2, 8):
		for x in 10:
			cells.append(Vector2i(x, y))
	layer.set_cells_terrain_connect(cells, TERRAIN_SET, TERRAIN, true)
	_expect(layer, Vector2i(0, 2), Vector2i(4, 1), 2, failures, "block top-left corner")
	_expect(layer, Vector2i(1, 2), Vector2i(4, 0), 0, failures, "block top edge")
	_expect(layer, Vector2i(9, 2), Vector2i(4, 1), 0, failures, "block top-right corner")
	_expect(layer, Vector2i(0, 3), Vector2i(4, 0), 2, failures, "block left edge")
	_expect(layer, Vector2i(5, 3), Vector2i(5, 0), 0, failures, "block fill")
	_expect(layer, Vector2i(9, 3), Vector2i(4, 0), 3, failures, "block right edge")
	_expect(layer, Vector2i(0, 7), Vector2i(4, 1), 3, failures, "block bottom-left corner")
	_expect(layer, Vector2i(1, 7), Vector2i(4, 0), 1, failures, "block bottom edge")
	_expect(layer, Vector2i(9, 7), Vector2i(4, 1), 1, failures, "block bottom-right corner")
	layer.free()


func _assert_notch_paint(tile_set: TileSet, failures: Array[String]) -> void:
	var layer := TileMapLayer.new()
	layer.tile_set = tile_set
	add_child(layer)
	var cells: Array[Vector2i] = []
	for y in range(2, 8):
		for x in 10:
			if x == 4 and y == 2:
				continue
			cells.append(Vector2i(x, y))
	layer.set_cells_terrain_connect(cells, TERRAIN_SET, TERRAIN, true)
	_expect(layer, Vector2i(3, 2), Vector2i(4, 1), 0, failures, "notch left lip")
	_expect(layer, Vector2i(5, 2), Vector2i(4, 1), 2, failures, "notch right lip")
	_expect(layer, Vector2i(4, 3), Vector2i(4, 0), 0, failures, "notch floor")
	_expect(layer, Vector2i(3, 3), Vector2i(5, 1), 2, failures, "notch top-right inner corner")
	_expect(layer, Vector2i(5, 3), Vector2i(5, 1), 0, failures, "notch top-left inner corner")
	layer.free()


func _expect(
	layer: TileMapLayer,
	cell: Vector2i,
	atlas: Vector2i,
	alternative: int,
	failures: Array[String],
	label: String
) -> void:
	var actual_atlas := layer.get_cell_atlas_coords(cell)
	var actual_alternative := layer.get_cell_alternative_tile(cell)
	if actual_atlas != atlas or actual_alternative != alternative:
		failures.append("%s at %s is %s/%d, expected %s/%d" % [
			label, cell, actual_atlas, actual_alternative, atlas, alternative,
		])


func _peering_bits(data: TileData) -> Array[int]:
	var bits: Array[int] = []
	for bit: int in BIT_ORDER:
		if data.get_terrain_peering_bit(bit) >= 0:
			bits.append(bit)
	bits.sort()
	return bits
