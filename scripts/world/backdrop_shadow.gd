class_name BackdropShadow
extends Node2D

## Drop shadow of the background tile layer, drawn above the light shade so it keeps
## its contrast on the backdrop plate.
##
## The room's background tile layer (`Terrain/BackTiles`) is cloned into a
## room-sized one-shot SubViewport, rendered as a white silhouette, and drawn as a
## blurred, offset quad. Under the light shade the shadow was invisible in practice:
## the shade already multiplies the plate by the light map, so on a dark plate a 30%
## shadow of nearly black is still nearly black (measured: 4022 px touched, mean
## change 1.46/255). Above the shade it darkens the final colour instead. The quad
## still must not touch the tiles, so the shader subtracts the un-offset silhouette
## from its own coverage: only the plate between and around the tiles is darkened.
##
## The offset is **fixed**: every room's background shadow leans the same way
## (`offset_direction`, towards the lower left by default) by `offset_px`. An
## earlier version moved it away from the nearest light every frame; the cost was
## already below the measurement noise, but a shadow that re-aims while a lamp
## swings reads as the backdrop wobbling, and one global direction matches the rest
## of the art's lighting.
##
## Room-extension contract: `bind_room_with_origin()` is called by the world
## session with the same arguments LightField gets, so the shadow is rebuilt once
## per room and costs nothing per frame after that.

const GROUP := &"backdrop_shadow"
const SHADOW_SHADER: Shader = preload("res://scripts/shaders/backdrop_shadow.gdshader")
const QUAD_NAME := "BackdropTileShadow"
const CHUNK_PIXELS := Vector2i(320, 180)
const TILE_PIXELS := 8
## Above *everything additive* (the shade at 8, the glow and the bloom composite at
## 9) and at the same level as the fog, which comes later in the tree so it still
## covers the shadow. The order is the whole point: at z 9 the shadow was drawn
## before the additive glow, which then re-added light on top of it and cancelled the
## darkening (measured: -18.2/255 with the light pass off, -0.7/255 with it on).
const QUAD_Z := 10

@export var layer_path := NodePath("Terrain/BackTiles")
## Direction the shadow leans, in screen pixels: (-1.6, 1) is roughly 150 degrees,
## i.e. down and to the left. Only the direction matters, it is normalised.
@export var offset_direction := Vector2(-1.6, 1.0)
## How far the shadow is pushed, in pixels.
@export_range(0.0, 40.0, 0.5) var offset_px := 10.0
## How much the plate darkens where the shadow lands.
@export_range(0.0, 1.0, 0.01) var strength := 0.85
## Soft edge of the shadow, in pixels.
@export_range(0.0, 12.0, 0.1) var blur_px := 3.0
## Multiplier colour of the darkest shadow pixel. Black is a real shadow; a tinted
## value reads as coloured glass instead.
@export var shadow_tint := Color(0.0, 0.0, 0.0)

var _room_pixels := Vector2i.ZERO
var _room_origin_pixels := Vector2i.ZERO
var _room_bound := false
var _mask_texture: Texture2D
var _quad: Sprite2D
var _material: ShaderMaterial
var _offset := Vector2.ZERO


func _ready() -> void:
	add_to_group(GROUP)
	# Optional in the scene: registering with the parent world session is the
	# switch, exactly like NormalField.
	var world := get_parent()
	if world != null and world.has_method("register_room_extension"):
		world.call("register_room_extension", self)


func bind_room(room_data: Variant, terrain_root: Node, origin_chunk: Variant = null) -> bool:
	return bind_room_with_origin(
		room_data, terrain_root, Vector2i(origin_chunk) if origin_chunk != null else Vector2i.ZERO
	)


## WorldSession room extension entry point. A room without a background tile layer
## is a supported state: there is simply no shadow to cast.
func bind_room_with_origin(room_data: Variant, terrain_root: Node, origin_chunk: Vector2i) -> bool:
	if room_data == null or terrain_root == null:
		return false
	var chunks: Vector2i = Vector2i.ONE
	var sizes: Variant = room_data.get("room_size_chunks")
	if sizes != null:
		chunks = Vector2i(sizes)
	if chunks.x <= 0 or chunks.y <= 0:
		chunks = Vector2i.ONE
	clear_room()
	_room_origin_pixels = origin_chunk * CHUNK_PIXELS
	_room_pixels = chunks * CHUNK_PIXELS
	_room_bound = true
	var layer := _find_layer(terrain_root)
	if layer != null:
		_build_mask(layer, terrain_root)
	_compute_offset()
	_build_quad(terrain_root)
	return true


func clear_room() -> void:
	_room_bound = false
	_mask_texture = null
	_offset = Vector2.ZERO
	if _quad != null and is_instance_valid(_quad):
		if _quad.get_parent() != null:
			_quad.get_parent().remove_child(_quad)
		_quad.queue_free()
	_quad = null
	_material = null
	_room_pixels = Vector2i.ZERO
	_room_origin_pixels = Vector2i.ZERO


## Current shadow displacement in room pixels, for tests and the debug HUD.
func get_shadow_offset() -> Vector2:
	return _offset


func has_shadow() -> bool:
	return _mask_texture != null and _quad != null


func get_mask_texture() -> Texture2D:
	return _mask_texture


## The silhouette as an image. Debug/inspection only (render-target read back).
func get_mask_image() -> Image:
	if _mask_texture == null:
		return null
	return _mask_texture.get_image()


func get_shadow_quad() -> Sprite2D:
	return _quad


func get_room_pixels() -> Vector2i:
	return _room_pixels


## The one global shadow direction. No light is consulted on purpose: a shadow that
## re-aims while a lamp swings reads as the backdrop wobbling, and the art direction
## leans one way anyway.
func _compute_offset() -> void:
	var direction := offset_direction
	if direction.length_squared() <= 0.000001:
		direction = Vector2(-1.6, 1.0)
	_offset = direction.normalized() * maxf(offset_px, 0.0)
	if _material != null:
		_material.set_shader_parameter("offset_px", _offset)


func _find_layer(terrain_root: Node) -> TileMapLayer:
	var layer := terrain_root.get_node_or_null(layer_path) as TileMapLayer
	if layer != null and not layer.get_used_cells().is_empty():
		return layer
	return null


## Composites the tile layer into a room-sized silhouette once per room.
##
## This used to be a one-shot `SubViewport` render. That version measured as
## "draws nothing": with the light pass visible the quad changed 0 pixels even with a
## red tint at strength 1, because a viewport switched to `UPDATE_DISABLED` does not
## keep its content for a *sampler* either (the same trap the render inspector hit
## when it read the masks back). Compositing the tiles into an `Image` is a few
## hundred 8x8 blits, happens once per room, and cannot disappear.
func _build_mask(layer: TileMapLayer, terrain_root: Node) -> void:
	var tile_set := layer.tile_set
	if tile_set == null:
		return
	var image := Image.create(_room_pixels.x, _room_pixels.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	var terrain_2d := terrain_root as Node2D
	var layer_offset := Vector2i(layer.position)
	if terrain_2d != null:
		layer_offset = Vector2i(terrain_2d.to_local(layer.global_position))
	var atlas_images: Dictionary[int, Image] = {}
	for cell: Vector2i in layer.get_used_cells():
		var source_id := layer.get_cell_source_id(cell)
		var source := tile_set.get_source(source_id) as TileSetAtlasSource
		if source == null or source.texture == null:
			continue
		var atlas := layer.get_cell_atlas_coords(cell)
		var alternative := layer.get_cell_alternative_tile(cell)
		if source.get_tile_data(atlas, alternative) == null:
			continue
		if not atlas_images.has(source_id):
			atlas_images[source_id] = source.texture.get_image()
		var atlas_image: Image = atlas_images[source_id]
		if atlas_image == null:
			continue
		var region := source.get_tile_texture_region(atlas, 0)
		var destination := layer_offset + cell * TILE_PIXELS
		var tile := atlas_image.get_region(region)
		# The silhouette only needs coverage, so alpha is normalised to 1 and the
		# colour to white; the shadow shader reads .a and nothing else.
		for y: int in tile.get_height():
			for x: int in tile.get_width():
				var alpha := tile.get_pixel(x, y).a
				if alpha > 0.0:
					tile.set_pixel(x, y, Color(1.0, 1.0, 1.0, maxf(alpha, 0.5)))
		image.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), destination)
	_mask_texture = ImageTexture.create_from_image(image)


## Builds the quad that draws the shadow into the room's backdrop container, so it
## sorts between the plate (z -1) and the tile layers (z 0).
func _build_quad(terrain_root: Node) -> void:
	if _mask_texture == null:
		return
	var background := terrain_root.get_node_or_null("Background")
	if background == null:
		# Baked authoring rooms keep the container; a bare test rig may not.
		background = terrain_root
	_material = ShaderMaterial.new()
	_material.shader = SHADOW_SHADER
	_material.set_shader_parameter("mask_tex", _mask_texture)
	_material.set_shader_parameter("mask_pixels", Vector2(_room_pixels))
	_material.set_shader_parameter("blur_px", blur_px)
	_material.set_shader_parameter("strength", strength)
	_material.set_shader_parameter("shadow_tint", shadow_tint)
	_material.set_shader_parameter("offset_px", _offset)
	_quad = Sprite2D.new()
	_quad.name = QUAD_NAME
	_quad.centered = false
	_quad.position = Vector2.ZERO
	_quad.z_index = QUAD_Z
	_quad.z_as_relative = false
	_quad.texture = _mask_texture
	_quad.material = _material
	# The shader blurs the silhouette itself; keep the sampling smooth so the
	# taps land between texels.
	_quad.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	background.add_child(_quad)


## Re-applies the exported tuning after a change (editor tweaks, tests).
func apply_parameters() -> void:
	if _material == null:
		return
	_compute_offset()
	_material.set_shader_parameter("blur_px", blur_px)
	_material.set_shader_parameter("strength", strength)
	_material.set_shader_parameter("shadow_tint", shadow_tint)
	_material.set_shader_parameter("mask_pixels", Vector2(_room_pixels))
