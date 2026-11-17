extends Node

## The terrain highlight bakes the solid layer's silhouette into a one texel per
## tile mask and draws the inner top-edge band from it. These checks pin the two
## things that can silently break: the mask must line up with the tiles, and a room
## without solids must not grow a quad.

const HIGHLIGHT := preload("res://scripts/world/terrain_highlight.gd")
const TERRAIN_SCENE := preload("res://scenes/rooms/generated/water_grid/terrain.tscn")

const TILE := 8


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_mask_matches_tiles(failures)
	_assert_empty_room_is_skipped(failures)
	return failures


func _assert_mask_matches_tiles(failures: Array[String]) -> void:
	var rig := _make_rig()
	var rooms: Node = rig["rooms"]
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
	if mask_texture.get_width() != used.size.x or mask_texture.get_height() != used.size.y:
		failures.append(
			"mask is %dx%d for a %dx%d tile rect"
			% [mask_texture.get_width(), mask_texture.get_height(), used.size.x, used.size.y]
		)
	var cells: Vector2 = material.get_shader_parameter("mask_cells")
	if cells != Vector2(used.size):
		failures.append("mask_cells does not match the used rect: %s" % str(cells))
	if float(material.get_shader_parameter("tile_pixels")) != float(TILE):
		failures.append("tile_pixels does not follow the tile set")
	# One tile that is certainly solid and one that is certainly open, relative to
	# the mask: the mask is indexed from the used rect's own origin.
	var mask_image := mask_texture.get_image()
	var solid_count := 0
	var open_count := 0
	for row in used.size.y:
		for column in used.size.x:
			var cell := used.position + Vector2i(column, row)
			var is_solid := layer.get_cell_source_id(cell) != -1
			var mask_value := mask_image.get_pixel(column, row).r
			if is_solid:
				solid_count += 1
				if mask_value <= 0.5:
					failures.append("solid tile %s is missing from the mask" % str(cell))
			else:
				open_count += 1
				if mask_value > 0.5:
					failures.append("open tile %s is solid in the mask" % str(cell))
	if solid_count == 0 or open_count == 0:
		failures.append("the test room does not have both solid and open tiles")
	# The quad covers exactly the used rect, so the shader's pixel space lines up
	# with the mask.
	var size := Vector2(used.size) * TILE
	if not quad.scale.is_equal_approx(size):
		failures.append("the quad is %s instead of %s" % [str(quad.scale), str(size)])
	if quad.z_index < 1:
		failures.append("the highlight is not drawn above the terrain")
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
