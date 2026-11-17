extends Node

## The terrain highlight bakes the solid layer's silhouette into a one texel per
## pixel mask (from the tile art, so slopes and half tiles keep their shape) and
## draws the inner outline from it. These checks pin the things that can silently
## break: the mask must line up with the tiles, transparent art must not be masked
## as solid, and a room without solids must not grow a quad.

const HIGHLIGHT := preload("res://scripts/world/terrain_highlight.gd")
const TERRAIN_SCENE := preload("res://scenes/rooms/generated/water_grid/terrain.tscn")

const TILE := 8


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_mask_matches_tiles(failures)
	_assert_missing_collision_tiles_are_open(failures)
	_assert_empty_room_is_skipped(failures)
	return failures


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
	# Every solid cell with fully opaque art has to be masked, and air has to be
	# open. Cells whose art is partly transparent are the point of the art mask, so
	# they are only checked for "some pixels set".
	var mask := mask_texture.get_image()
	var solid_count := 0
	var open_count := 0
	var checked_partial := false
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
			if set_pixels == 0:
				failures.append("solid cell %s is missing from the mask" % str(cell))
			elif set_pixels < TILE * TILE:
				checked_partial = true
	if solid_count == 0 or open_count == 0:
		failures.append("the test room does not have both solid and open cells")
	# The room is drawn from full square tiles today, so there should be no partial
	# tile; if one appears the art mask is doing its job and the check above already
	# accepted it.
	if checked_partial:
		pass
	_cleanup(rig)


## A tile placed in the solid layer with no collision polygon is decoration: its
## transparent art must stay open in the mask, otherwise the outline would trace
## the empty half of the tile.
func _assert_missing_collision_tiles_are_open(failures: Array[String]) -> void:
	var rig := _make_rig()
	var room: Node = rig["room"]
	var layer := room.get_node_or_null("Terrain/SolidTiles") as TileMapLayer
	var highlight: Node = rig["highlight"]
	var decoration := PackedStringArray()
	for cell: Vector2i in layer.get_used_cells():
		var data := layer.get_cell_tile_data(cell)
		if data != null and data.get_collision_polygons_count(0) == 0:
			decoration.append(str(cell))
	if decoration.is_empty():
		# This room has no decollisioned tiles; nothing to assert here.
		_cleanup(rig)
		return
	var mask := highlight.call("build_mask", layer) as Image
	var used := layer.get_used_rect()
	for entry: String in decoration:
		var parts := entry.trim_prefix("(").trim_suffix(")").split(",")
		var cell := Vector2i(int(parts[0]), int(parts[1]))
		var origin := (cell - used.position) * TILE
		var set_pixels := 0
		for y in TILE:
			for x in TILE:
				if mask.get_pixel(origin.x + x, origin.y + y).r > 0.5:
					set_pixels += 1
		if set_pixels == TILE * TILE:
			failures.append("decoration tile %s is masked as a full solid cell" % entry)
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
