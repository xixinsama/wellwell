extends Node2D
class_name TerrainHighlight

## Draws an inner outline along the solid terrain of every loaded room.
##
## The solid layer's silhouette is baked into a one-texel-per-pixel mask from the
## tiles' collision shapes, and `terrain_highlight.gdshader` lights the pixels
## within a couple of pixels of open air in every direction: the line runs around
## the whole shape, not just the top faces.
##
## Only the side the hero is on lights up. A flood fill from the hero's tile over
## open air says which pockets of the room are reachable, and the shader only counts
## an air pixel that belongs to that set: a sealed cavity (a closed room, a hollow
## inside a wall) stays dark on its inside, while the outside of the same wall lights
## up. The fill is redone when the hero moves to a different tile, not per frame.
##
## The node is world level (like BackdropField): it decorates each room under
## TerrainRoot, so rooms without solid tiles simply get nothing. Rebuilds on
## `world_ready`, so re-baking or reloading a room is picked up automatically.

const HIGHLIGHT_SHADER: Shader = preload("res://scripts/shaders/terrain_highlight.gdshader")
const LAYER_NAME := "TerrainHighlight"
const ROOMS_PATH := NodePath("../TerrainRoot")
const TILE_FALLBACK := 8.0
## Where the hero is, for the reachability fill. The node lives next to the player
## under the world root.
const PLAYER_PATH := NodePath("../Player")

## The tile layer whose outline is highlighted.
@export var layer_path := NodePath("Terrain/SolidTiles")
@export var rim_color := Color(0.78, 0.96, 1.0)
@export_range(0.0, 3.0, 0.01) var rim_strength := 1.0
## How many pixels deep the outline is. 1 is a single bright pixel line.
@export_range(1.0, 4.0, 0.5) var rim_width := 1.0
## Extra falloff inside `rim_width`. 0 is a hard pixel band, 1 fades it out.
@export_range(0.0, 1.0, 0.01) var rim_softness := 0.6
## Jittered pixels, so the line does not look vector-drawn. 0 is a clean line.
@export_range(0.0, 1.0, 0.01) var rim_grain := 0.18
## Light the inside of the silhouette (the usual rim) instead of the air outside it.
@export var rim_inside := true
## Only light the terrain that faces the pocket of air the hero is in.
@export var hero_side_only := true
## Draw above the terrain but under fog, water and gas.
@export_range(-10, 20, 1) var draw_order := 1
## Light that always reaches the rim, added on top of the light map so unlit
## walls keep a faint outline instead of vanishing.
@export_range(0.0, 1.0, 0.01) var light_floor := 0.55
## Multiplier on the light map before it gates the rim.
@export_range(0.0, 2.0, 0.01) var light_gain := 1.0

## One entry per decorated room: its layer, sizes, shape grid and reach grid.
var _entries: Array[Dictionary] = []
var _player: Node2D
var _last_player_cell := Vector2i(2147483647, 2147483647)
## Room light map from LightField: the rim only shows where the light reaches.
var _light_texture: Texture2D
var _light_pixels := Vector2i.ZERO
var _light_origin := Vector2i.ZERO


func _ready() -> void:
	add_to_group(&"terrain_highlight")
	_player = get_node_or_null(PLAYER_PATH) as Node2D
	var world := get_parent()
	if world != null and world.has_signal("world_ready"):
		if not world.is_connected("world_ready", decorate_rooms):
			world.connect("world_ready", decorate_rooms)
	decorate_rooms()


## Called by LightField when a room is bound. Every decorated quad re-binds its
## offset, so a neighbouring room visible at the edge samples the same map.
func set_light_field(texture: Texture2D, pixels: Vector2i, origin_pixels: Vector2i) -> void:
	_light_texture = texture
	_light_pixels = pixels
	_light_origin = origin_pixels
	_apply_light_to_all()


func _apply_light_to_all() -> void:
	for entry: Dictionary in _entries:
		if not entry.has("quad") or not is_instance_valid(entry["quad"]):
			continue
		_apply_light(entry["quad"] as MeshInstance2D, entry)


## Binds the light map and this quad's offset inside it to a quad's material.
func _apply_light(quad: MeshInstance2D, entry: Dictionary) -> void:
	var material := quad.material as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter("light_texture", _light_texture)
	material.set_shader_parameter("light_pixels", Vector2(_light_pixels))
	var offset := Vector2.ZERO
	if _light_texture != null and _light_pixels.x > 0:
		offset = quad.global_position - Vector2(_light_origin)
	material.set_shader_parameter("light_offset", offset)
	material.set_shader_parameter("light_gain", light_gain)
	material.set_shader_parameter("light_floor", light_floor)


## Re-runs the reachability fill when the hero moves into another tile. Tiles are
## 8 px, so this is a few times per second at most, and the fill itself is a walk
## over a few hundred tiles.
func _process(_delta: float) -> void:
	if not hero_side_only or _entries.is_empty():
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_node_or_null(PLAYER_PATH) as Node2D
	if _player == null:
		return
	var tile := _player_tile()
	if tile == _last_player_cell:
		return
	_last_player_cell = tile
	refresh_reach()


## Recomputes the lit side of every decorated room from the hero's position. Safe to
## call by hand (tests, a teleport).
func refresh_reach() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_node_or_null(PLAYER_PATH) as Node2D
	for entry: Dictionary in _entries:
		var start := Vector2i(-1, -1)
		if _player != null:
			var layer: TileMapLayer = entry["layer"]
			var local := layer.to_local(_player.global_position)
			var map := layer.local_to_map(local)
			start = map
		_update_reach(entry, start)


## The hero's tile in the world, used only to detect that it moved.
func _player_tile() -> Vector2i:
	if _player == null:
		return Vector2i(2147483647, 2147483647)
	var size := float(TILE_FALLBACK)
	var entry_size := 0
	if not _entries.is_empty():
		entry_size = (_entries[0].get("tile_size", Vector2i(TILE_FALLBACK, TILE_FALLBACK)) as Vector2i).x
		if entry_size > 0:
			size = float(entry_size)
	return Vector2i(
		floori(_player.global_position.x / size),
		floori(_player.global_position.y / size)
	)


## Adds (or refreshes) the highlight quad of every loaded room. Safe to call
## repeatedly; the world session re-bakes terrain on each start. A room that lost
## its solids loses its quad in the same pass, so a re-baked room never keeps a
## stale outline.
func decorate_rooms() -> void:
	_entries.clear()
	# Force the next frame to redo the reach fill against the rebuilt rooms.
	_last_player_cell = Vector2i(2147483647, 2147483647)
	var rooms := _resolve_rooms_root()
	if rooms == null:
		return
	for room: Node in rooms.get_children():
		if _decorate_room(room):
			pass
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
	return _entries.size()


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
				_fill_polygon(mask, local, tile_size, data.get_collision_polygon_points(0, index))
			continue
		if solid_needs_collision:
			# A tile without a collision shape is decoration: leave it out.
			continue
		_stamp_tile(mask, local, tile_size, layer, cell, data, atlas_images)
	return mask


## Fills one collision polygon into the mask with a scanline. Points are in
## tile-local pixels centred on zero.
##
## The points are used as they come: an alternative tile stores its collision
## already in its own orientation (the editor bakes the flip into the shape), so
## re-applying `flip_h` / `flip_v` / `transpose` here would rotate the mask back to
## the base tile's shape -that is exactly what made an alternative slope outline
## like the original tile.
func _fill_polygon(
	mask: Image, origin: Vector2i, tile_size: Vector2i, points: PackedVector2Array
) -> void:
	if points.size() < 3:
		return
	var half := Vector2(tile_size) * 0.5
	var transformed := PackedVector2Array()
	transformed.resize(points.size())
	for index in points.size():
		transformed[index] = points[index] + half
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
			# A pixel is covered when the shape reaches its centre; the half pixel
			# bias also keeps the boundary pixel of a diagonal, which is how the tile
			# art itself is drawn (a slope tile is one pixel wider per row than a
			# strict centre test gives).
			var from := clampi(ceili(crossings[index] - 0.5), 0, tile_size.x)
			var to := clampi(floori(crossings[index + 1] + 0.5), 0, tile_size.x)
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
	var entry := _entry_for(room)
	if entry.is_empty():
		entry = _make_entry(room, layer, used)
		_entries.append(entry)
	else:
		# A re-baked room keeps its terrain node: rebuild the baked data, keep the quad.
		var rebuilt := _make_entry(room, layer, used)
		entry["used"] = rebuilt["used"]
		entry["tile_size"] = rebuilt["tile_size"]
		entry["solid"] = rebuilt["solid"]
		entry["mask"] = rebuilt["mask"]
		entry["image"] = rebuilt["image"]
		entry["texture"] = rebuilt["texture"]
	entry["quad"] = quad
	_sync_quad(quad, entry)
	return true


## The entry of one room, or an empty dictionary when it is not decorated yet.
func _entry_for(room: Node) -> Dictionary:
	for entry: Dictionary in _entries:
		if entry.get("room") == room:
			return entry
	return {}


## Bakes the per-room data: the pixel silhouette, the tile grid used by the fill,
## and the reachability image the shader samples.
func _make_entry(room: Node, layer: TileMapLayer, used: Rect2i) -> Dictionary:
	var tile_size := _tile_size(layer)
	var mask := build_mask(layer)
	var reach_image := Image.create(used.size.x, used.size.y, false, Image.FORMAT_R8)
	# Start lit: until the first fill runs (a world without a player, an editor
	# preview) the outline behaves as a plain rim instead of going black.
	reach_image.fill(Color(1.0, 1.0, 1.0, 1.0))
	var entry := {
		"room": room,
		"layer": layer,
		"used": used,
		"tile_size": tile_size,
		"solid": _build_solid_grid(layer, used),
		"mask": mask,
		"image": reach_image,
		"texture": ImageTexture.create_from_image(reach_image),
		"reach": PackedByteArray(),
		"has_reach": false,
	}
	return entry


## One byte per tile of the used rect: 1 when the tile has a collision shape. The
## reachability fill walks the zeros.
func _build_solid_grid(layer: TileMapLayer, used: Rect2i) -> PackedByteArray:
	var grid := PackedByteArray()
	grid.resize(used.size.x * used.size.y)
	grid.fill(0)
	for cell: Vector2i in layer.get_used_cells():
		var local := cell - used.position
		if local.x < 0 or local.y < 0 or local.x >= used.size.x or local.y >= used.size.y:
			continue
		var data := layer.get_cell_tile_data(cell)
		if data == null or data.get_collision_polygons_count(0) == 0:
			continue
		grid[local.y * used.size.x + local.x] = 1
	return grid


## Flood fills the open air the hero can reach from `start_cell` (in the layer's
## cell space) and hands the result to the shader. Anything the fill cannot reach -## a closed room, a hollow inside a wall -is left dark.
func _update_reach(entry: Dictionary, start_cell: Vector2i) -> void:
	var used: Rect2i = entry["used"]
	var image: Image = entry["image"]
	var reach := compute_reach(entry, start_cell)
	entry["reach"] = reach
	entry["has_reach"] = true
	var size := used.size
	for row in size.y:
		for column in size.x:
			var inside := reach[row * size.x + column] != 0
			image.set_pixel(column, row, Color(1.0, 1.0, 1.0, 1.0) if inside else Color(0.0, 0.0, 0.0, 1.0))
	(entry["texture"] as ImageTexture).update(image)


## Reachable open tiles from `start_cell`, one byte per tile of the used rect.
## Public so a test can check the flood without a renderer.
func compute_reach(entry: Dictionary, start_cell: Vector2i) -> PackedByteArray:
	var used: Rect2i = entry["used"]
	var solid: PackedByteArray = entry["solid"]
	var size := used.size
	var reach := PackedByteArray()
	reach.resize(size.x * size.y)
	reach.fill(0)
	if size.x <= 0 or size.y <= 0:
		return reach
	var start := start_cell - used.position
	start = _nearest_open(solid, size, start)
	if start.x < 0:
		return reach
	var queue: Array[Vector2i] = [start]
	reach[start.y * size.x + start.x] = 1
	var head := 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var neighbour := cell + step
			if neighbour.x < 0 or neighbour.y < 0 or neighbour.x >= size.x or neighbour.y >= size.y:
				continue
			var index := neighbour.y * size.x + neighbour.x
			if reach[index] != 0 or solid[index] != 0:
				continue
			reach[index] = 1
			queue.append(neighbour)
	return reach


## The tile itself when it is open, else the closest open tile within a couple of
## cells (the hero can stand a pixel inside a wall while landing). Vector2i(-1, -1)
## when there is none, which leaves the room dark.
func _nearest_open(solid: PackedByteArray, size: Vector2i, cell: Vector2i) -> Vector2i:
	var clamped := Vector2i(clampi(cell.x, 0, size.x - 1), clampi(cell.y, 0, size.y - 1))
	if solid[clamped.y * size.x + clamped.x] == 0:
		return clamped
	for radius in range(1, 3):
		for offset_y in range(-radius, radius + 1):
			for offset_x in range(-radius, radius + 1):
				var candidate := clamped + Vector2i(offset_x, offset_y)
				if candidate.x < 0 or candidate.y < 0 or candidate.x >= size.x or candidate.y >= size.y:
					continue
				if solid[candidate.y * size.x + candidate.x] == 0:
					return candidate
	return Vector2i(-1, -1)


func _sync_quad(quad: MeshInstance2D, entry: Dictionary) -> void:
	var layer: TileMapLayer = entry["layer"]
	var used: Rect2i = entry["used"]
	var tile_size: Vector2i = entry["tile_size"]
	var mask: Image = entry["mask"]
	var material := ShaderMaterial.new()
	material.shader = HIGHLIGHT_SHADER
	material.set_shader_parameter("mask_texture", ImageTexture.create_from_image(mask))
	material.set_shader_parameter("mask_pixels", Vector2(mask.get_width(), mask.get_height()))
	material.set_shader_parameter("reach_texture", entry["texture"])
	material.set_shader_parameter("reach_cells", Vector2(used.size))
	material.set_shader_parameter("tile_pixels", float(tile_size.x))
	material.set_shader_parameter("require_reach", 1.0 if hero_side_only else 0.0)
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
	_apply_light(quad, entry)


## Push the exported tuning values onto every built quad (live editing).
func apply_parameters() -> void:
	for entry: Dictionary in _entries:
		var quad := get_highlight_for_room(entry["room"])
		if quad == null or quad.material == null:
			continue
		var material := quad.material as ShaderMaterial
		material.set_shader_parameter("rim_color", rim_color)
		material.set_shader_parameter("rim_strength", rim_strength)
		material.set_shader_parameter("rim_width", rim_width)
		material.set_shader_parameter("rim_softness", rim_softness)
		material.set_shader_parameter("rim_grain", rim_grain)
		material.set_shader_parameter("inside", 1.0 if rim_inside else 0.0)
		material.set_shader_parameter("require_reach", 1.0 if hero_side_only else 0.0)
		material.set_shader_parameter("light_gain", light_gain)
		material.set_shader_parameter("light_floor", light_floor)


func _resolve_rooms_root() -> Node:
	var rooms := get_node_or_null(ROOMS_PATH)
	if rooms != null:
		return rooms
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("TerrainRoot")
