extends Node2D
class_name TerrainHighlight

## Draws an inner outline along the solid terrain of every loaded room.
##
## The solid layer's silhouette is baked into a one-texel-per-pixel mask from the
## tile art alpha (so slopes, half tiles and decorative bricks keep their real
## shape), and `terrain_highlight.gdshader` lights the pixels within a couple of
## pixels of open air in every direction: the line runs around the whole shape,
## not just the top faces.
##
## The node is world level (like BackdropField): it decorates each room under
## TerrainRoot, so rooms without solid tiles simply get nothing. Rebuilds on
## `world_ready`, so re-baking or reloading a room is picked up automatically.

const HIGHLIGHT_SHADER: Shader = preload("res://scripts/shaders/terrain_highlight.gdshader")
const LAYER_NAME := "TerrainHighlight"
const ROOMS_PATH := NodePath("../TerrainRoot")
const TILE_FALLBACK := 8.0

## The tile layer whose outline is highlighted.
@export var layer_path := NodePath("Terrain/SolidTiles")
@export var rim_color := Color(0.72, 0.94, 1.0)
@export_range(0.0, 3.0, 0.01) var rim_strength := 0.85
## How many pixels deep the outline reaches in from the silhouette edge.
@export_range(1.0, 4.0, 0.5) var rim_width := 2.0
## Extra falloff inside `rim_width`. 0 is a hard pixel band, 1 fades it out.
@export_range(0.0, 1.0, 0.01) var rim_softness := 0.6
## Jittered pixels, so the line does not look vector-drawn. 0 is a clean line.
@export_range(0.0, 1.0, 0.01) var rim_grain := 0.18
## Light the inside of the silhouette (the usual rim) instead of the air outside it.
@export var rim_inside := true
## Draw above the terrain but under fog, water and gas.
@export_range(-10, 20, 1) var draw_order := 1

var _decorated_rooms: Array[Node] = []


func _ready() -> void:
	var world := get_parent()
	if world != null and world.has_signal("world_ready"):
		if not world.is_connected("world_ready", decorate_rooms):
			world.connect("world_ready", decorate_rooms)
	decorate_rooms()


## Adds (or refreshes) the highlight quad of every loaded room. Safe to call
## repeatedly; the world session re-bakes terrain on each start. A room that lost
## its solids loses its quad in the same pass, so a re-baked room never keeps a
## stale outline.
func decorate_rooms() -> void:
	_decorated_rooms.clear()
	var rooms := _resolve_rooms_root()
	if rooms == null:
		return
	for room: Node in rooms.get_children():
		if _decorate_room(room):
			_decorated_rooms.append(room)
		elif room is Node:
			_clear_room(room)


## Removes the quad of a room that no longer has anything to highlight.
func _clear_room(room: Node) -> void:
	var layer := room.get_node_or_null(layer_path) as TileMapLayer
	var terrain: Node = layer.get_parent() if layer != null else room.get_node_or_null("Terrain")
	if terrain == null:
		return
	var quad := terrain.get_node_or_null(LAYER_NAME)
	if quad != null:
		quad.queue_free()


func get_highlight_for_room(room: Node) -> MeshInstance2D:
	if room == null:
		return null
	var layer := room.get_node_or_null(layer_path) as TileMapLayer
	if layer == null:
		return null
	var terrain := layer.get_parent()
	if terrain == null:
		return null
	var quad := terrain.get_node_or_null(LAYER_NAME) as MeshInstance2D
	if quad == null or quad.is_queued_for_deletion():
		return null
	return quad


func get_decorated_room_count() -> int:
	return _decorated_rooms.size()


## Builds the silhouette of one solid layer, one texel per pixel of the layer's
## used rect.
##
## The shape comes from the tile's **collision polygon**, not from the cell grid and
## not from the art alpha:
##
## - a slope tile is a triangle, a half tile is half a rect, so the outline follows
##   the real geometry instead of cutting across the empty half;
## - a tile with **no collision polygon** is not terrain at all (ladders, vines,
##   decals placed in the solid layer), so it is skipped. Its art was the reason a
##   ladder used to light up like a solid block;
## - polygons are in tile-local pixels centred on zero, so flips are a negation.
##

## Whether tiles without a collision shape count as solid. Ladders and decals in
## the solid layer have no shape and are skipped by default.
@export var solid_needs_collision := true

func build_mask(layer: TileMapLayer) -> Image:
	var used := layer.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return Image.create(1, 1, false, Image.FORMAT_R8)
	var tile_size := _tile_size(layer)
	var pixels := Vector2i(used.size) * tile_size
	var mask := Image.create(pixels.x, pixels.y, false, Image.FORMAT_R8)
	mask.fill(Color(0.0, 0.0, 0.0, 1.0))
	var atlas_images: Dictionary = {}
	for cell: Vector2i in layer.get_used_cells():
		var local := (cell - used.position) * tile_size
		var data := layer.get_cell_tile_data(cell)
		if data == null:
			# No tile data: nothing describes a shape, so treat the cell as filled
			# unless the caller asked for collision shapes only.
			if not solid_needs_collision:
				mask.fill_rect(Rect2i(local, tile_size), Color(1.0, 1.0, 1.0, 1.0))
			continue
		var polygons := data.get_collision_polygons_count(0)
		if polygons > 0:
			for index in polygons:
				_fill_polygon(
					mask, local, tile_size, data.get_collision_polygon_points(0, index), data
				)
			continue
		if solid_needs_collision:
			# A tile without a collision shape is decoration: leave it out.
			continue
		_stamp_tile(mask, local, tile_size, layer, cell, data, atlas_images)
	return mask


## Fills one collision polygon into the mask with a scanline, honouring the cell's
## flips. Points are in tile-local pixels centred on zero.
func _fill_polygon(
	mask: Image, origin: Vector2i, tile_size: Vector2i, points: PackedVector2Array, data: TileData
) -> void:
	if points.size() < 3:
		return
	var flip_h := bool(data.get("flip_h")) if data.get("flip_h") != null else false
	var flip_v := bool(data.get("flip_v")) if data.get("flip_v") != null else false
	var transpose := bool(data.get("transpose")) if data.get("transpose") != null else false
	var half := Vector2(tile_size) * 0.5
	var transformed := PackedVector2Array()
	transformed.resize(points.size())
	for index in points.size():
		var point := points[index]
		if transpose:
			point = Vector2(point.y, point.x)
		if flip_h:
			point.x = -point.x
		if flip_v:
			point.y = -point.y
		transformed[index] = point + half
	var lowest := INF
	var highest := -INF
	for point: Vector2 in transformed:
		lowest = minf(lowest, point.y)
		highest = maxf(highest, point.y)
	var white := Color(1.0, 1.0, 1.0, 1.0)
	for row in range(maxi(floori(lowest), 0), mini(ceili(highest), tile_size.y)):
		var scan := float(row) + 0.5
		var crossings: Array[float] = []
		for index in transformed.size():
			var a := transformed[index]
			var b := transformed[(index + 1) % transformed.size()]
			if (a.y <= scan and b.y > scan) or (b.y <= scan and a.y > scan):
				var t := (scan - a.y) / (b.y - a.y)
				crossings.append(a.x + t * (b.x - a.x))
		crossings.sort()
		for index in range(0, crossings.size() - 1, 2):
			var from := clampi(ceili(crossings[index]), 0, tile_size.x)
			var to := clampi(floori(crossings[index + 1]), 0, tile_size.x)
			for column in range(from, to):
				mask.set_pixel(origin.x + column, origin.y + row, white)


## Copies one tile's atlas region into the mask, 1 for opaque art and 0 for the
## transparent part, applying the cell's flips. Only used when `solid_needs_collision`
## is off and the tile has no collision shape.
func _stamp_tile(
	mask: Image,
	origin: Vector2i,
	tile_size: Vector2i,
	layer: TileMapLayer,
	cell: Vector2i,
	data: TileData,
	atlas_images: Dictionary
) -> void:
	var source_id := layer.get_cell_source_id(cell)
	var source := layer.tile_set.get_source(source_id) as TileSetAtlasSource if layer.tile_set != null else null
	if source == null:
		mask.fill_rect(Rect2i(origin, tile_size), Color(1.0, 1.0, 1.0, 1.0))
		return
	if not atlas_images.has(source_id):
		var texture := source.texture
		atlas_images[source_id] = texture.get_image() if texture != null else null
	var atlas: Image = atlas_images[source_id]
	var coords := layer.get_cell_atlas_coords(cell)
	var region := source.get_tile_texture_region(coords)
	if atlas == null or region.size.x <= 0 or region.size.y <= 0:
		mask.fill_rect(Rect2i(origin, tile_size), Color(1.0, 1.0, 1.0, 1.0))
		return
	var flip_h := bool(data.get("flip_h")) if data.get("flip_h") != null else false
	var flip_v := bool(data.get("flip_v")) if data.get("flip_v") != null else false
	var transpose := bool(data.get("transpose")) if data.get("transpose") != null else false
	for y in tile_size.y:
		for x in tile_size.x:
			var sample := Vector2i(x, y)
			if transpose:
				sample = Vector2i(sample.y, sample.x)
			if flip_h:
				sample.x = tile_size.x - 1 - sample.x
			if flip_v:
				sample.y = tile_size.y - 1 - sample.y
			var atlas_position := region.position + Vector2i(
				clampi(sample.x, 0, region.size.x - 1), clampi(sample.y, 0, region.size.y - 1)
			)
			var opaque := atlas.get_pixel(atlas_position.x, atlas_position.y).a > 0.5
			mask.set_pixel(origin.x + x, origin.y + y, Color(1.0, 1.0, 1.0, 1.0) if opaque else Color(0.0, 0.0, 0.0, 1.0))


## Tile size in pixels, from the layer's tile set.
func _tile_size(layer: TileMapLayer) -> Vector2i:
	if layer.tile_set != null:
		return layer.tile_set.tile_size
	return Vector2i(int(TILE_FALLBACK), int(TILE_FALLBACK))


func _decorate_room(room: Node) -> bool:
	if room == null:
		return false
	var layer := room.get_node_or_null(layer_path) as TileMapLayer
	if layer == null:
		return false
	var used := layer.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return false
	var terrain := layer.get_parent()
	if terrain == null:
		return false
	var quad := terrain.get_node_or_null(LAYER_NAME) as MeshInstance2D
	if quad == null:
		quad = MeshInstance2D.new()
		quad.name = LAYER_NAME
		var mesh := QuadMesh.new()
		mesh.size = Vector2.ONE
		quad.mesh = mesh
		quad.z_index = draw_order
		quad.z_as_relative = true
		terrain.add_child(quad)
	_sync_quad(quad, layer, used)
	return true


func _sync_quad(quad: MeshInstance2D, layer: TileMapLayer, used: Rect2i) -> void:
	var tile_size := _tile_size(layer)
	var mask := build_mask(layer)
	var material := ShaderMaterial.new()
	material.shader = HIGHLIGHT_SHADER
	material.set_shader_parameter("mask_texture", ImageTexture.create_from_image(mask))
	material.set_shader_parameter("mask_pixels", Vector2(mask.get_width(), mask.get_height()))
	material.set_shader_parameter("rim_color", rim_color)
	material.set_shader_parameter("rim_strength", rim_strength)
	material.set_shader_parameter("rim_width", rim_width)
	material.set_shader_parameter("rim_softness", rim_softness)
	material.set_shader_parameter("rim_grain", rim_grain)
	material.set_shader_parameter("inside", 1.0 if rim_inside else 0.0)
	quad.material = material
	# The used rect starts at a tile corner: place the quad's centre there.
	var size := Vector2(mask.get_width(), mask.get_height())
	var top_left := layer.to_global(layer.map_to_local(used.position) - Vector2(tile_size) * 0.5)
	var parent_node := quad.get_parent() as Node2D
	if parent_node != null:
		top_left = parent_node.to_local(top_left)
	quad.position = top_left + size * 0.5
	quad.scale = size


## Push the exported tuning values onto every built quad (live editing).
func apply_parameters() -> void:
	var rooms := _resolve_rooms_root()
	if rooms == null:
		return
	for room: Node in rooms.get_children():
		var quad := get_highlight_for_room(room)
		if quad == null or quad.material == null:
			continue
		var material := quad.material as ShaderMaterial
		material.set_shader_parameter("rim_color", rim_color)
		material.set_shader_parameter("rim_strength", rim_strength)
		material.set_shader_parameter("rim_width", rim_width)
		material.set_shader_parameter("rim_softness", rim_softness)
		material.set_shader_parameter("rim_grain", rim_grain)
		material.set_shader_parameter("inside", 1.0 if rim_inside else 0.0)


func _resolve_rooms_root() -> Node:
	var rooms := get_node_or_null(ROOMS_PATH)
	if rooms != null:
		return rooms
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("TerrainRoot")
