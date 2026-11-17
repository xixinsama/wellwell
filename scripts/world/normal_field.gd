class_name NormalField
extends Node2D

## Room-sized buffer of authored per-pixel surface normals, rendered once per room.
##
## The room may carry a `TileMapLayer` named `NormalTiles` under
## `RoomContent/Terrain` (baked rooms put it under `Terrain`) whose tiles are plain
## RGB vectors: r = x, g = y, b = z, flat = (128, 128, 255). The layer is rendered
## **once** into a viewport the size of the room, and the result is handed to
## LightField's shade and glow passes as a texture. Nothing is read back on the CPU
## and nothing repaints per frame: `UPDATE_ONCE` renders the buffer on the first
## frame after binding and the engine then leaves it `UPDATE_DISABLED`.
##
## The authored layer is never reparented or touched. A programmatic clone copies
## `tile_set` and `tile_map_data` into the viewport, so the room's own node stays
## exactly as the level scene wrote it; the clone is what the renderer sees.
##
## Bound through WorldSession.register_room_extension like the light field. The
## node also self-registers when its parent is a world session, so adding it to
## `world_root.tscn` is enough: no runner change and no authored scene change.
## When the room has no `NormalTiles` layer the field reports "no authored map"
## and does nothing; the light field then falls back to screen-derived normals.

const GROUP := &"normal_field"
const LAYER_NAME := "NormalTiles"
## Flat normal (0.5, 0.5, 1.0): a surface whose normal points straight out of the
## screen. It is the clear colour, so every pixel the layer does not cover has no
## relief at all.
const FLAT_COLOR := Color(0.5, 0.5, 1.0, 1.0)
## Room chunk size in design pixels, the same unit LightField uses.
const CHUNK_PIXELS := Vector2i(320, 180)

## Where the authored layer lives inside the room. Baked runtime terrain puts
## `Terrain` at the root; authoring scenes nest it under `RoomContent`. Both are
## accepted, plus a recursive name lookup as a last resort.
@export var layer_path := NodePath("Terrain/NormalTiles")
@export var layer_name := LAYER_NAME

var _room_pixels := Vector2i.ZERO
var _room_origin_pixels := Vector2i.ZERO
var _room_bound := false
var _has_map := false
var _texture: Texture2D
var _viewport: SubViewport
var _clone: TileMapLayer
## Frames left before the one-shot viewport is explicitly switched off. Godot's
## UPDATE_ONCE already renders a single frame, but pinning it to UPDATE_DISABLED
## afterwards makes the "costs nothing per frame" promise explicit (and testable
## in a real window).
var _disable_frames_left := 0


func _ready() -> void:
	add_to_group(GROUP)
	# The world session is the parent in world_root.tscn. Registering here makes
	# the node purely optional in the scene: adding or removing it is the switch,
	# and a second registration from a runner is a harmless no-op.
	var world := get_parent()
	if world != null and world.has_method("register_room_extension"):
		world.call("register_room_extension", self)


func bind_room(room_data: Variant, terrain_root: Node, origin_chunk: Variant = null) -> bool:
	return bind_room_with_origin(
		room_data, terrain_root, Vector2i(origin_chunk) if origin_chunk != null else Vector2i.ZERO
	)


## WorldSession room extension entry point. Returns true even when the room has
## no authored normals: a missing map is a supported state, not a binding failure
## (a false return would abort the whole room binding for every other extension).
func bind_room_with_origin(room_data: Variant, terrain_root: Node, origin_chunk: Vector2i) -> bool:
	if room_data == null or terrain_root == null:
		return false
	var chunks: Vector2i = (
		room_data.get("room_size_chunks") if room_data.get("room_size_chunks") != null else Vector2i.ONE
	)
	if chunks.x <= 0 or chunks.y <= 0:
		chunks = Vector2i.ONE
	clear_room()
	_room_origin_pixels = origin_chunk * CHUNK_PIXELS
	_room_pixels = chunks * CHUNK_PIXELS
	_room_bound = true
	var layer := _find_authored_layer(terrain_root)
	if layer != null:
		_build_buffer(terrain_root, layer)
	_push_to_light_fields()
	return true


func _process(_delta: float) -> void:
	if _disable_frames_left <= 0:
		return
	_disable_frames_left -= 1
	if _disable_frames_left > 0:
		return
	if is_instance_valid(_viewport):
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	set_process(false)


func clear_room() -> void:
	_room_bound = false
	_has_map = false
	_disable_frames_left = 0
	set_process(false)
	_texture = null
	_clone = null
	if is_instance_valid(_viewport):
		if _viewport.get_parent() != null:
			_viewport.get_parent().remove_child(_viewport)
		_viewport.queue_free()
	_viewport = null
	_room_pixels = Vector2i.ZERO
	_room_origin_pixels = Vector2i.ZERO
	# The light field keeps its own copy of the hand-off, so tell it the map is
	# gone instead of silently sampling a freed viewport texture.
	_push_to_light_fields()


## The authored normal buffer, or null when the room has no authored normals.
func get_normal_texture() -> Texture2D:
	return _texture


## Size of the buffer in room pixels (the light map's size), or zero when unbound.
func get_normal_pixels() -> Vector2i:
	return _room_pixels


## Room origin of the buffer in world pixels, so a consumer can reject a buffer
## from the previous room instead of using stale normals for one frame.
func get_normal_origin() -> Vector2i:
	return _room_origin_pixels


func has_normal_map() -> bool:
	return _has_map


func is_room_bound() -> bool:
	return _room_bound


## Forces the one-shot viewport to render again. Only needed if the authored layer
## or its tileset is edited in place after binding; a room rebind also rebuilds.
func refresh() -> void:
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		_disable_frames_left = 2
		set_process(true)


func get_buffer_layer() -> TileMapLayer:
	return _clone


## Accepts the same room pattern as LightField, with the authoring-scene nesting
## and the baked runtime nesting both understood.
func _find_authored_layer(terrain_root: Node) -> TileMapLayer:
	var layer := terrain_root.get_node_or_null(layer_path) as TileMapLayer
	if layer != null:
		return layer
	layer = terrain_root.get_node_or_null("RoomContent/Terrain/%s" % layer_name) as TileMapLayer
	if layer != null:
		return layer
	return _find_layer_recursive(terrain_root, layer_name)


func _find_layer_recursive(node: Node, wanted: String) -> TileMapLayer:
	for child: Node in node.get_children():
		if child is TileMapLayer and child.name == wanted:
			return child as TileMapLayer
		var found := _find_layer_recursive(child, wanted)
		if found != null:
			return found
	return null


func _build_buffer(terrain_root: Node, layer: TileMapLayer) -> void:
	if layer.tile_set == null or layer.get_used_cells().is_empty():
		# A layer with no tiles carries no normals; it is not worth a viewport.
		return
	if layer.visible:
		# The layer is data, not art: leaving it visible would paint the normal
		# colours over the room. Warn instead of mutating the owner's node.
		push_warning(
			"NormalField: %s is visible; hide the authored NormalTiles layer so the room does not draw it"
			% layer.name
		)
	_viewport = SubViewport.new()
	_viewport.name = "NormalViewport"
	_viewport.size = _room_pixels
	# Opaque: the flat clear quad must fill every pixel the layer does not cover.
	_viewport.transparent_bg = false
	_viewport.disable_3d = true
	_viewport.msaa_2d = Viewport.MSAA_DISABLED
	# Pixel art normals must never be interpolated or mirrored across the room.
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	# The buffer is static for the whole room: render once, then the engine keeps
	# it UPDATE_DISABLED, so an authored room costs nothing per frame.
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)
	# Give the renderer one full frame to draw the buffer, then disable it for the
	# rest of the room's stay.
	_disable_frames_left = 2
	set_process(true)

	# Clear colour is the flat normal, so "no tile here" means "no relief here"
	# instead of an undefined gadget normal.
	var flat := ColorRect.new()
	flat.name = "FlatNormal"
	flat.color = FLAT_COLOR
	flat.size = Vector2(_room_pixels)
	flat.position = Vector2.ZERO
	flat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flat.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_viewport.add_child(flat)

	# A clone, not the authored node: TileMapLayer has exactly one parent, and
	# reparenting would edit the owner's level. tile_map_data is read-only as a
	# property copy, tile_set is shared (never mutated).
	_clone = TileMapLayer.new()
	_clone.name = "NormalTiles"
	_clone.tile_set = layer.tile_set
	_clone.tile_map_data = layer.tile_map_data
	_clone.collision_enabled = false
	_clone.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Room-local canvas coordinates: the viewport is the room, so only the layer's
	# offset inside the room survives.
	var offset := layer.position
	var terrain_2d := terrain_root as Node2D
	if terrain_2d != null:
		offset = terrain_2d.to_local(layer.global_position)
	_clone.position = offset
	_viewport.add_child(_clone)

	_texture = _viewport.get_texture()
	_has_map = true


## Pushes the buffer (or its absence) to every light field in the scene. The
## light field also pulls on bind, so either room-extension order works.
func _push_to_light_fields() -> void:
	if not is_inside_tree():
		return
	for node: Node in get_tree().get_nodes_in_group(&"light_field"):
		if node.has_method("set_normal_field"):
			node.call(
				"set_normal_field",
				_texture if _has_map else null,
				_room_pixels,
				_room_origin_pixels
			)
