class_name BackdropShadow
extends Node2D

## Drop shadow of the background tile layer, drawn between the backdrop plate and
## the tiles themselves.
##
## The room's background tile layer (`Terrain/BackTiles`) is cloned into a
## room-sized one-shot SubViewport, rendered as a white silhouette, and drawn as a
## blurred, offset quad under the tiles. Because the tiles cover it afterwards, the
## shadow only shows on the backdrop plate around the tiles, which is what makes
## the plate read as a surface *behind* the tiles instead of a flat image in a
## different layer.
##
## The offset follows the nearest light: the quad pushes the silhouette away from
## it (`follow_ratio` of the light distance, capped by `max_offset_px`). With no
## authored light in the room, the hero's own lantern is the light, so the shadow
## still reacts while walking.
##
## Room-extension contract: `bind_room_with_origin()` is called by the world
## session with the same arguments LightField gets, so the shadow is rebuilt once
## per room and costs nothing per frame except the uniform update.

const GROUP := &"backdrop_shadow"
const MASK_SHADER: Shader = preload("res://scripts/shaders/backdrop_shadow_mask.gdshader")
const SHADOW_SHADER: Shader = preload("res://scripts/shaders/backdrop_shadow.gdshader")
const QUAD_NAME := "BackdropTileShadow"
const CHUNK_PIXELS := Vector2i(320, 180)
## Authored room lights; they are the only things bright enough to move a shadow.
const LIGHT_GROUPS: Array[StringName] = [&"room_light", &"fog_light"]

@export var layer_path := NodePath("Terrain/BackTiles")
## How much the plate darkens where the shadow lands.
@export_range(0.0, 1.0, 0.01) var strength := 0.55
## Soft edge of the shadow, in pixels.
@export_range(0.0, 12.0, 0.1) var blur_px := 2.5
## Upper bound of the displacement, in pixels. Small on purpose: the backdrop
## shadow is a parallax-ish hint, not a second copy of the tiles.
@export_range(0.0, 24.0, 0.1) var max_offset_px := 6.0
## Share of the light distance that becomes shadow displacement (kept under 1 so
## a far lamp does not throw the plate's shadow across the room).
@export_range(0.0, 1.0, 0.05) var follow_ratio := 0.5
## Multiplier colour of the darkest shadow pixel (bluish keeps it from going grey).
@export var shadow_tint := Color(0.52, 0.6, 0.78)

var _room_pixels := Vector2i.ZERO
var _room_origin_pixels := Vector2i.ZERO
var _room_bound := false
var _viewport: SubViewport
var _mask_texture: Texture2D
var _quad: Sprite2D
var _material: ShaderMaterial
var _player: Node2D
var _offset := Vector2.ZERO
var _light_position := Vector2.INF
var _disable_frames_left := 0


func _ready() -> void:
	add_to_group(GROUP)
	# Optional in the scene: registering with the parent world session is the
	# switch, exactly like NormalField.
	var world := get_parent()
	if world != null and world.has_method("register_room_extension"):
		world.call("register_room_extension", self)


func bind_player(player: Node2D) -> void:
	_player = player


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
	_build_quad(terrain_root)
	_update_offset()
	return true


func clear_room() -> void:
	_room_bound = false
	_disable_frames_left = 0
	set_process(false)
	_mask_texture = null
	_offset = Vector2.ZERO
	_light_position = Vector2.INF
	if _viewport != null and is_instance_valid(_viewport):
		if _viewport.get_parent() != null:
			_viewport.get_parent().remove_child(_viewport)
		_viewport.queue_free()
	_viewport = null
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


## World position of the light the shadow currently follows; INF when there is none.
func get_light_position() -> Vector2:
	return _light_position


func has_shadow() -> bool:
	return _mask_texture != null and _quad != null


func get_mask_texture() -> Texture2D:
	return _mask_texture


func get_shadow_quad() -> Sprite2D:
	return _quad


func get_room_pixels() -> Vector2i:
	return _room_pixels


func _process(_delta: float) -> void:
	if _disable_frames_left > 0:
		_disable_frames_left -= 1
		if _disable_frames_left == 0 and _viewport != null and is_instance_valid(_viewport):
			# The silhouette never changes inside a room, so the extra pass is
			# switched off after it has been drawn once.
			_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_update_offset()


## Moves the silhouette away from the nearest light and hands the offset to the
## shader. The whole layer is pushed as one, which is enough for a hint shadow and
## costs one uniform write per frame.
func _update_offset() -> void:
	if _material == null:
		return
	var anchor := Vector2(_room_origin_pixels) + Vector2(_room_pixels) * 0.5
	if is_instance_valid(_player):
		anchor = _player.global_position
	var light := _nearest_light()
	_light_position = light
	var offset := Vector2.ZERO
	if light != Vector2.INF:
		# Push *away* from the light, but only partly and never far: the backdrop
		# is not a lit surface, it is a hint that the tiles sit in front of it.
		var away := anchor - light
		if away.length_squared() > 0.0001:
			offset = away.normalized() * minf(away.length() * follow_ratio, max_offset_px)
	_offset = offset
	_material.set_shader_parameter("offset_px", offset)


func _nearest_light() -> Vector2:
	var best := Vector2.INF
	var best_distance := INF
	for group: StringName in LIGHT_GROUPS:
		for node: Node in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(node) or not node is Node2D:
				continue
			var light := (node as Node2D).global_position
			var distance := light.distance_squared_to(
				_player.global_position if is_instance_valid(_player) else Vector2(_room_origin_pixels)
			)
			if distance < best_distance:
				best_distance = distance
				best = light
	if best == Vector2.INF and is_instance_valid(_player):
		# The hero carries the lantern, so a room without authored lights still
		# has a light to push the shadow away from.
		best = _player.global_position + Vector2(0.0, -6.0)
	return best


func _find_layer(terrain_root: Node) -> TileMapLayer:
	var layer := terrain_root.get_node_or_null(layer_path) as TileMapLayer
	if layer != null and not layer.get_used_cells().is_empty():
		return layer
	return null


## Renders the tile layer as a white silhouette once per room.
func _build_mask(layer: TileMapLayer, terrain_root: Node) -> void:
	_viewport = SubViewport.new()
	_viewport.name = "BackdropShadowViewport"
	_viewport.size = _room_pixels
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.msaa_2d = Viewport.MSAA_DISABLED
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)
	_disable_frames_left = 2
	set_process(true)
	var clone := TileMapLayer.new()
	clone.name = "BackdropSilhouette"
	clone.tile_set = layer.tile_set
	clone.tile_map_data = layer.tile_map_data
	clone.collision_enabled = false
	clone.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var material := ShaderMaterial.new()
	material.shader = MASK_SHADER
	clone.material = material
	var terrain_2d := terrain_root as Node2D
	clone.position = (
		terrain_2d.to_local(layer.global_position) if terrain_2d != null else layer.position
	)
	_viewport.add_child(clone)
	_mask_texture = _viewport.get_texture()


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
	_quad.z_index = 0
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
	_material.set_shader_parameter("blur_px", blur_px)
	_material.set_shader_parameter("strength", strength)
	_material.set_shader_parameter("shadow_tint", shadow_tint)
	_material.set_shader_parameter("mask_pixels", Vector2(_room_pixels))
