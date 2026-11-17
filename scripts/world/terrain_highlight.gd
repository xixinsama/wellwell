extends Node2D
class_name TerrainHighlight

## Draws an inner top-edge highlight along the solid terrain of every loaded room.
##
## The solid layer's collision silhouette is baked into a one-texel-per-tile mask;
## `terrain_highlight.gdshader` then lights a couple of pixels under the top face of
## every solid run. The mask is exactly the tile grid, so the line lands on tile
## boundaries and stays crisp at any zoom — the same silhouette the atmosphere
## already uses to cut gas at walls.
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
## How many pixels deep the highlight reaches down from the top face.
@export_range(1.0, 4.0, 0.5) var rim_width := 2.0
## Extra falloff inside `rim_width`. 0 is a hard pixel band, 1 fades it out.
@export_range(0.0, 1.0, 0.01) var rim_softness := 0.6
## Jittered pixels, so the line does not look vector-drawn. 0 is a clean line.
@export_range(0.0, 1.0, 0.01) var rim_grain := 0.18
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


## Builds the tile mask of one solid layer. Returns an empty image when the layer
## has no tiles, which is how a room without solids opts out.
func build_mask(layer: TileMapLayer) -> Image:
	var used := layer.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return Image.create(1, 1, false, Image.FORMAT_R8)
	var bytes := PackedByteArray()
	bytes.resize(used.size.x * used.size.y)
	bytes.fill(0)
	for cell: Vector2i in layer.get_used_cells():
		var local := cell - used.position
		if local.x < 0 or local.y < 0 or local.x >= used.size.x or local.y >= used.size.y:
			continue
		bytes[local.y * used.size.x + local.x] = 255
	return Image.create_from_data(used.size.x, used.size.y, false, Image.FORMAT_R8, bytes)


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
	var tile_size := Vector2(TILE_FALLBACK, TILE_FALLBACK)
	if layer.tile_set != null:
		tile_size = Vector2(layer.tile_set.tile_size)
	var material := ShaderMaterial.new()
	material.shader = HIGHLIGHT_SHADER
	material.set_shader_parameter("mask_texture", ImageTexture.create_from_image(build_mask(layer)))
	material.set_shader_parameter("mask_cells", Vector2(used.size))
	material.set_shader_parameter("tile_pixels", tile_size.x)
	material.set_shader_parameter("rim_color", rim_color)
	material.set_shader_parameter("rim_strength", rim_strength)
	material.set_shader_parameter("rim_width", rim_width)
	material.set_shader_parameter("rim_softness", rim_softness)
	material.set_shader_parameter("rim_grain", rim_grain)
	quad.material = material
	# The used rect starts at a tile corner: place the quad's centre there.
	var size := Vector2(used.size) * tile_size
	var top_left := layer.to_global(layer.map_to_local(used.position) - tile_size * 0.5)
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


func _resolve_rooms_root() -> Node:
	var rooms := get_node_or_null(ROOMS_PATH)
	if rooms != null:
		return rooms
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("TerrainRoot")
