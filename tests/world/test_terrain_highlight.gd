extends Node

## The terrain highlight bakes the solid layer's silhouette into a one texel per
## pixel mask from the tiles' collision shapes, then draws the inner outline from
## it. These checks pin what can silently break: the mask must line up with the
## tiles, a slope must be a diagonal, a tile without a collision shape (a ladder, a
## vine) must not be masked, and a room without solids must not grow a quad.

const HIGHLIGHT := preload("res://scripts/world/terrain_highlight.gd")
const TERRAIN_SCENE := preload("res://scenes/rooms/generated/water_grid/terrain.tscn")

const TILE := 8


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_mask_matches_tiles(failures)
	_assert_slope_is_a_diagonal(failures)
	_assert_tiles_without_collision_are_skipped(failures)
	_assert_alternative_uses_its_own_shape(failures)
	_assert_empty_room_is_skipped(failures)
	return failures


## An alternative tile stores its collision in its own orientation, so the mask has
## to use those points as they come. Re-applying the alternative's flip flags put
## the base tile's shape back: an alternative slope outlined like the original.
func _assert_alternative_uses_its_own_shape(failures: Array[String]) -> void:
	var image := Image.create(TILE * 2, TILE, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 1.0))
	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = Vector2i(TILE, TILE)
	var coords := Vector2i.ZERO
	source.create_tile(coords)
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE, TILE)
	tile_set.add_physics_layer()
	tile_set.add_source(source, 0)
	# Base tile: the left half. Alternative: the right half, exactly what the editor
	# stores when a tile is flipped, plus the flip flag it records with it.
	var base := source.get_tile_data(coords, 0)
	base.add_collision_polygon(0)
	base.set_collision_polygon_points(0, 0, PackedVector2Array([
		Vector2(-4.0, -4.0), Vector2(0.0, -4.0), Vector2(0.0, 4.0), Vector2(-4.0, 4.0)
	]))
	var alternative_id := source.create_alternative_tile(coords, -1)
	var alternative := source.get_tile_data(coords, alternative_id)
	if alternative == null:
		failures.append("could not create an alternative tile")
		return
	if alternative.get_collision_polygons_count(0) == 0:
		alternative.add_collision_polygon(0)
	alternative.set_collision_polygon_points(0, 0, PackedVector2Array([
		Vector2(0.0, -4.0), Vector2(4.0, -4.0), Vector2(4.0, 4.0), Vector2(0.0, 4.0)
	]))
	alternative.set("flip_h", true)
	var rooms := Node2D.new()
	rooms.name = "TerrainRoot"
	add_child(rooms)
	var room := Node2D.new()
	room.name = "synthetic"
	rooms.add_child(room)
	var terrain := Node2D.new()
	terrain.name = "Terrain"
	room.add_child(terrain)
	var layer := TileMapLayer.new()
	layer.name = "SolidTiles"
	layer.tile_set = tile_set
	terrain.add_child(layer)
	layer.set_cell(Vector2i.ZERO, 0, coords, alternative_id)
	var highlight := HIGHLIGHT.new() as Node2D
	highlight.name = "TerrainHighlight"
	add_child(highlight)
	var mask: Image = highlight.call("build_mask", layer)
	# The alternative is the right half: its right side is solid, its left is open.
	if mask.get_pixel(6, 4).r <= 0.5:
		failures.append("the alternative tile's own shape was not masked")
	if mask.get_pixel(1, 4).r > 0.5:
		failures.append("the mask used the base tile's shape for an alternative")
	_cleanup({"rooms": rooms, "highlight": highlight})


func _assert_mask_matches_tiles(failures: Array[String]) -> void:
	var rig := _make_rig()
	var highlight: Node = rig["highlight"]
	var room: Node = rig["room"]
	if int(highlight.call("get_decorated_room_count")) != 1:
		failures.append("the highlight did not decorate the room")
	var quad: MeshInstance2D = highlight.call("get_highlight_for_room", room)
	if quad == null:
		failures.append("no highlight quad was built")
		_cleanup(rig)
		return
	var layer := room.get_node_or_null("Terrain/SolidTiles") as TileMapLayer
	var used := layer.get_used_rect()
	var material := quad.material as ShaderMaterial
	var mask_texture: Texture2D = material.get_shader_parameter("mask_texture")
	if mask_texture == null:
		failures.append("the quad has no mask texture")
		_cleanup(rig)
		return
	var expected := used.size * TILE
	if mask_texture.get_width() != expected.x or mask_texture.get_height() != expected.y:
		failures.append(
			"mask is %dx%d for a %dx%d pixel rect"
			% [mask_texture.get_width(), mask_texture.get_height(), expected.x, expected.y]
		)
	var pixels: Vector2 = material.get_shader_parameter("mask_pixels")
	if pixels != Vector2(expected):
		failures.append("mask_pixels does not match the mask: %s" % str(pixels))
	if not quad.scale.is_equal_approx(Vector2(expected)):
		failures.append("the quad is %s instead of %s" % [str(quad.scale), str(expected)])
	if quad.z_index < 1:
		failures.append("the highlight is not drawn above the terrain")
	# This room is built from full square tiles, so every solid cell has to be
	# fully masked and every open cell fully clear.
	var mask := mask_texture.get_image()
	var solid_count := 0
	var open_count := 0
	for row in used.size.y:
		for column in used.size.x:
			var cell := used.position + Vector2i(column, row)
			var is_solid := layer.get_cell_source_id(cell) != -1
			var origin := Vector2i(column, row) * TILE
			var set_pixels := 0
			for y in TILE:
				for x in TILE:
					if mask.get_pixel(origin.x + x, origin.y + y).r > 0.5:
						set_pixels += 1
			if not is_solid:
				open_count += 1
				if set_pixels != 0:
					failures.append("open cell %s has %d opaque mask pixels" % [str(cell), set_pixels])
				continue
			solid_count += 1
			if set_pixels != TILE * TILE:
				failures.append(
					"solid cell %s has %d of %d mask pixels" % [str(cell), set_pixels, TILE * TILE]
				)
	if solid_count == 0 or open_count == 0:
		failures.append("the test room does not have both solid and open cells")
	_cleanup(rig)


## A triangle collision polygon has to come out as a diagonal, not as a full cell:
## that is what makes slope tiles outline correctly.
func _assert_slope_is_a_diagonal(failures: Array[String]) -> void:
	var rig := _make_synthetic_rig(PackedVector2Array([
		Vector2(-4.0, -4.0), Vector2(4.0, 4.0), Vector2(-4.0, 4.0)
	]), true)
	var mask: Image = rig["mask"]
	# The triangle keeps the bottom-left half. The art reaches one pixel further than
	# a strict centre test per row (the boundary pixel is drawn), so the covered area
	# is 1 + 2 + ... + 8 pixels: a full cell would be 64 and an empty one 0.
	var opaque := 0
	for y in TILE:
		for x in TILE:
			if mask.get_pixel(x, y).r > 0.5:
				opaque += 1
	if opaque != 36:
		failures.append("the slope tile covers %d pixels instead of 36" % opaque)
	if mask.get_pixel(0, 0).r <= 0.5:
		failures.append("the slope tile is open at its filled corner")
	if mask.get_pixel(0, 7).r <= 0.5:
		failures.append("the slope tile is open at the bottom-left corner")
	if mask.get_pixel(7, 7).r <= 0.5:
		failures.append("the slope tile is open at the bottom-right corner")
	if mask.get_pixel(7, 0).r > 0.5:
		failures.append("the slope tile is solid at its empty corner")
	_cleanup(rig)


## A tile with no collision polygon is not terrain: a ladder or a vine placed in
## the solid layer must not be outlined as a block.
func _assert_tiles_without_collision_are_skipped(failures: Array[String]) -> void:
	var rig := _make_synthetic_rig(PackedVector2Array(), false)
	var mask: Image = rig["mask"]
	for y in TILE:
		for x in TILE:
			if mask.get_pixel(x, y).r > 0.5:
				failures.append("a tile without a collision shape was masked solid")
				_cleanup(rig)
				return
	_cleanup(rig)


func _assert_empty_room_is_skipped(failures: Array[String]) -> void:
	var rig := _make_rig()
	var room: Node = rig["room"]
	var layer := room.get_node_or_null("Terrain/SolidTiles") as TileMapLayer
	layer.clear()
	var highlight: Node = rig["highlight"]
	highlight.call("decorate_rooms")
	if int(highlight.call("get_decorated_room_count")) != 0:
		failures.append("a room without solid tiles still got a highlight")
	if highlight.call("get_highlight_for_room", room) != null:
		failures.append("a room without solid tiles grew a quad")
	_cleanup(rig)


## One tile layer with a single cell, whose tile either has a collision polygon or
## none. Returns the mask built for it.
func _make_synthetic_rig(polygon: PackedVector2Array, with_collision: bool) -> Dictionary:
	var image := Image.create(TILE * 2, TILE, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 1.0))
	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = Vector2i(TILE, TILE)
	var coords := Vector2i.ZERO
	source.create_tile(coords)
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE, TILE)
	tile_set.add_physics_layer()
	tile_set.add_source(source, 0)
	if with_collision:
		var data := source.get_tile_data(coords, 0)
		if data != null and data.get_collision_polygons_count(0) == 0:
			data.add_collision_polygon(0)
		if data != null:
			data.set_collision_polygon_points(0, 0, polygon)
	var rooms := Node2D.new()
	rooms.name = "TerrainRoot"
	add_child(rooms)
	var room := Node2D.new()
	room.name = "synthetic"
	rooms.add_child(room)
	var terrain := Node2D.new()
	terrain.name = "Terrain"
	room.add_child(terrain)
	var layer := TileMapLayer.new()
	layer.name = "SolidTiles"
	layer.tile_set = tile_set
	terrain.add_child(layer)
	layer.set_cell(Vector2i.ZERO, 0, coords)
	var highlight := HIGHLIGHT.new() as Node2D
	highlight.name = "TerrainHighlight"
	add_child(highlight)
	var mask: Image = highlight.call("build_mask", layer)
	var opaque := 0
	for yy in mask.get_height():
		for xx in mask.get_width():
			if mask.get_pixel(xx, yy).r > 0.5:
				opaque += 1
	return {"rooms": rooms, "room": room, "highlight": highlight, "mask": mask, "layer": layer}


func _make_rig() -> Dictionary:
	var rooms := Node2D.new()
	rooms.name = "TerrainRoot"
	add_child(rooms)
	var room := TERRAIN_SCENE.instantiate()
	room.name = "water_grid"
	rooms.add_child(room)
	var highlight := HIGHLIGHT.new() as Node2D
	highlight.name = "TerrainHighlight"
	add_child(highlight)
	highlight.call("decorate_rooms")
	return {"rooms": rooms, "room": room, "highlight": highlight}


func _cleanup(rig: Dictionary) -> void:
	var highlight: Node = rig["highlight"]
	var rooms: Node = rig["rooms"]
	highlight.free()
	rooms.free()
