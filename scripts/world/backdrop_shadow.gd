class_name BackdropShadow
extends Node2D

## Drop shadow of the background tile layer, cast by the hero's own lantern.
##
## The room's background tile layer (`Terrain/BackTiles`) is composited into a
## room-sized silhouette once per room and drawn as a blurred, offset quad. The model:
##
## - **The hero's lantern is the key light.** The shadow leans away from the hero
##   (measured from the room centre), so walking around swings the backdrop shadow the
##   other way. That inverse response is the strongest, cheapest depth cue this layer
##   can give, and it is why the quad is drawn above the light passes at all.
## - **The shadow only exists inside the lantern's reach.** A shadow is cast by light,
##   so past the hero's bubble the plate is left alone instead of collecting black
##   bands in the dark.
## - **Lamps are fill light.** Authored lights do not create more shadow, they erase
##   what is there, which is how a second lamp softens the first one's shadow. Gating
##   on the *total* light (an earlier version) made every lamp darken the plate, which
##   reads backwards.
## - **It never gets darker than `max_darkness`.** It is a depth cue, not the subject.
##
## Ordering matters twice over. The quad is drawn at z 10: after the light shade (8),
## the glow and the bloom composite (9) -- drawn before them, the additive passes put
## the light it had just removed back (measured: -18.2/255 of darkening with the light
## pass off, -0.7/255 with it on) -- and before the fog, which is also z 10 but later
## in the tree. And it subtracts the *un-offset* silhouette from its own coverage, so
## the tiles themselves are never darkened.
##
## Room-extension contract: `bind_room_with_origin()` is called by the world session
## with the same arguments LightField gets, so the shadow is rebuilt once per room and
## costs the silhouette compositing plus a few uniform writes.

const GROUP := &"backdrop_shadow"
const SHADOW_SHADER: Shader = preload("res://scripts/shaders/backdrop_shadow.gdshader")
const QUAD_NAME := "BackdropTileShadow"
const CHUNK_PIXELS := Vector2i(320, 180)
const TILE_PIXELS := 8
## Above every additive pass (shade 8, glow and bloom 9) and level with the fog, which
## comes later in the tree so it still covers the shadow.
const QUAD_Z := 10
## Lamps that act as fill light.
const LIGHT_GROUPS: Array[StringName] = [&"room_light", &"fog_light"]
const MAX_FILL_LIGHTS := 4

@export var layer_path := NodePath("Terrain/BackTiles")
## Fallback lean, in screen pixels, when the hero sits exactly at the room centre.
@export var offset_direction := Vector2(-1.6, 1.0)
## How far the shadow is pushed, in pixels.
@export_range(0.0, 40.0, 0.5) var offset_px := 5.0
## The cast reaches the whole room; key_extent is the distance at which the ramp has
## travelled its full range (0 = the room's larger side).
@export_range(0.0, 640.0, 1.0) var key_extent := 0.0
## Shadow amount right under the hero, and at key_extent away. Near is weaker (the
## light stands on the plane, its shadow collapses under it) and far is not allowed to
## get weak either; the ramp between them is linear so the slope stays gentle.
@export_range(0.0, 1.0, 0.01) var key_near := 0.45
@export_range(0.0, 1.0, 0.01) var key_far := 0.85
## How much the plate darkens where the shadow lands, before the cap.
@export_range(0.0, 1.0, 0.01) var strength := 0.85
## Hard ceiling: even on a bright plate the shadow keeps more than half its value.
@export_range(0.0, 1.0, 0.01) var max_darkness := 0.5
## How much a lamp erases the shadow where it lights the plate. Deliberately small:
## in depth the backdrop plane sits far behind the mid-ground lamps, so their light
## reaches it weak and diffuse -- it lifts the shadow slightly and never removes it.
@export_range(0.0, 1.0, 0.01) var fill_erase := 0.55
## Footprint of a fill light on the backdrop, as a share of its 2D radius: the same
## depth gap, light that travels further covers less of the far plane.
@export_range(0.1, 1.5, 0.01) var fill_radius_scale := 0.55
## Soft edge of the shadow, in pixels.
@export_range(0.0, 12.0, 0.1) var blur_px := 3.0
## Multiplier colour of the darkest pixel. Black is a real shadow.
@export var shadow_tint := Color(0.0, 0.0, 0.0)

var _room_pixels := Vector2i.ZERO
var _room_origin_pixels := Vector2i.ZERO
var _room_bound := false
var _mask_texture: Texture2D
var _quad: Sprite2D
var _material: ShaderMaterial
var _player: Node2D
var _offset := Vector2.ZERO


func _ready() -> void:
	add_to_group(GROUP)
	# Optional in the scene: registering with the parent world session is the switch.
	var world := get_parent()
	if world != null and world.has_method("register_room_extension"):
		world.call("register_room_extension", self)


## The hero is the key light, so the shadow has to follow them: a few uniform writes
## per frame (the direction, the lantern position and up to four fill lamps).
func _process(_delta: float) -> void:
	if _room_bound:
		_update_light_relationship()


func bind_player(player: Node2D) -> void:
	_player = player


func bind_room(room_data: Variant, terrain_root: Node, origin_chunk: Variant = null) -> bool:
	return bind_room_with_origin(
		room_data, terrain_root, Vector2i(origin_chunk) if origin_chunk != null else Vector2i.ZERO
	)


## WorldSession room extension entry point. A room without a background tile layer is
## a supported state: there is simply no shadow to cast.
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


## The silhouette as an image, for the render inspector.
func get_mask_image() -> Image:
	if _mask_texture == null:
		return null
	return _mask_texture.get_image()


func get_shadow_quad() -> Sprite2D:
	return _quad


func get_room_pixels() -> Vector2i:
	return _room_pixels


## Re-applies the exported tuning after a change (editor tweaks, tests).
func apply_parameters() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("blur_px", blur_px)
	_material.set_shader_parameter("strength", strength)
	_material.set_shader_parameter("max_darkness", max_darkness)
	_material.set_shader_parameter("shadow_tint", shadow_tint)
	_material.set_shader_parameter("mask_pixels", Vector2(_room_pixels))
	_update_light_relationship()


## Recomputes the shadow direction and the fill lights, then hands them over.
##
## Direction: the backdrop shadow leans away from the hero, measured from the room
## centre, so moving left makes it lean right. Fill: up to four authored lamps sorted
## by distance to the hero; they erase shadow instead of adding any.
func _update_light_relationship() -> void:
	if _material == null:
		return
	var centre := Vector2(_room_origin_pixels) + Vector2(_room_pixels) * 0.5
	var hero := centre
	if is_instance_valid(_player):
		hero = _player.global_position
	var away := centre - hero
	if away.length_squared() <= 0.0001:
		away = offset_direction
	_offset = away.normalized() * maxf(offset_px, 0.0)
	_material.set_shader_parameter("offset_px", _offset)
	_material.set_shader_parameter("key_pos_px", hero - Vector2(_room_origin_pixels))
	_material.set_shader_parameter("key_extent_px", key_extent_value())
	_material.set_shader_parameter("key_near", key_near)
	_material.set_shader_parameter("key_far", key_far)
	_material.set_shader_parameter("fill_erase", fill_erase)
	_material.set_shader_parameter("fill_radius_scale", fill_radius_scale)
	var candidates: Array[Dictionary] = []
	if is_inside_tree():
		for group: StringName in LIGHT_GROUPS:
			for node: Node in get_tree().get_nodes_in_group(group):
				if not is_instance_valid(node) or not node is Node2D:
					continue
				var position := (node as Node2D).global_position
				candidates.append({
					"position": position,
					"radius": float(node.get("radius")) if "radius" in node else 0.0,
					"energy": float(node.get("energy")) if "energy" in node else 1.0,
					"distance": position.distance_squared_to(hero),
				})
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return float(left["distance"]) < float(right["distance"])
	)
	for index: int in MAX_FILL_LIGHTS:
		var parameter := "fill%d" % index
		if index >= candidates.size():
			_material.set_shader_parameter(parameter, Vector4.ZERO)
			continue
		var light: Dictionary = candidates[index]
		var local := Vector2(light["position"]) - Vector2(_room_origin_pixels)
		_material.set_shader_parameter(parameter, Vector4(
			local.x, local.y, float(light["radius"]), float(light["energy"])
		))
	_material.set_shader_parameter("fill_count", float(mini(candidates.size(), MAX_FILL_LIGHTS)))


## The ramp distance: the room's larger side unless the author overrides it.
func key_extent_value() -> float:
	if key_extent > 0.0:
		return key_extent
	return float(maxi(_room_pixels.x, _room_pixels.y))


func _find_layer(terrain_root: Node) -> TileMapLayer:
	var layer := terrain_root.get_node_or_null(layer_path) as TileMapLayer
	if layer != null and not layer.get_used_cells().is_empty():
		return layer
	return null


## Composites the tile layer into a room-sized silhouette once per room.
##
## This used to be a one-shot `SubViewport` render, which measured as "draws nothing":
## with the light pass visible the quad changed 0 pixels even with a red tint at
## strength 1, because a viewport switched to `UPDATE_DISABLED` does not keep its
## content for a *sampler* either. Compositing the tiles into an `Image` is a few
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
		var tile := atlas_image.get_region(region)
		# The silhouette only needs coverage: white, alpha kept, so the shader can read
		# .a and nothing else.
		for y: int in tile.get_height():
			for x: int in tile.get_width():
				var alpha := tile.get_pixel(x, y).a
				if alpha > 0.0:
					tile.set_pixel(x, y, Color(1.0, 1.0, 1.0, maxf(alpha, 0.5)))
		image.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), layer_offset + cell * TILE_PIXELS)
	_mask_texture = ImageTexture.create_from_image(image)


## Builds the quad and parents it to the room's backdrop container.
func _build_quad(terrain_root: Node) -> void:
	if _mask_texture == null:
		return
	var background := terrain_root.get_node_or_null("Background")
	if background == null:
		background = terrain_root
	_material = ShaderMaterial.new()
	_material.shader = SHADOW_SHADER
	_material.set_shader_parameter("mask_tex", _mask_texture)
	_material.set_shader_parameter("mask_pixels", Vector2(_room_pixels))
	_quad = Sprite2D.new()
	_quad.name = QUAD_NAME
	_quad.centered = false
	_quad.position = Vector2.ZERO
	_quad.z_index = QUAD_Z
	_quad.z_as_relative = false
	_quad.texture = _mask_texture
	_quad.material = _material
	_quad.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	background.add_child(_quad)
	apply_parameters()
