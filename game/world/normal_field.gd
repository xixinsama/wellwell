class_name NormalField
extends Node2D

## Room-sized buffer of authored per-pixel surface normals, rendered once per room.
##
## Two ways to get authored normals into a room, in this order:
##
## 1. **authored layer** — the room carries a `TileMapLayer` named `NormalTiles`
##    under `RoomContent/Terrain` (baked rooms put it under `Terrain`) whose tiles
##    are plain RGB vectors: r = x, g = y, b = z, flat = (128, 128, 255). The layer
##    is rendered **once** into a viewport the size of the room and the result is
##    handed to LightField's shade and glow passes as a texture.
## 2. **`normal_tileset`** — no authored layer, but this field has a normal TileSet
##    assigned: every terrain layer named in `source_layer_names` (the collision
##    layer `SolidTiles` by default) is cloned with that TileSet instead. The clone
##    keeps the room's `tile_map_data`, and the normal atlas mirrors the albedo
##    tileset coordinate for coordinate, so the cells line up with no room edits at
##    all: one `NormalField` with `normal_tileset` assigned lights every existing
##    room with authored normals. A room that wants hand-drawn normals keeps
##    priority through path 1.
##
## Nothing is read back on the CPU and nothing repaints per frame: `UPDATE_ONCE`
## renders the buffer on the first frame after binding and the engine then leaves it
## `UPDATE_DISABLED`. `set_normal_tileset()` rebuilds the buffer for the bound room
## when the TileSet is assigned after the room was bound (the case of a runner or a
## test wiring it up in code).
##
## The authored layer is never reparented or touched. A programmatic clone copies
## `tile_set` and `tile_map_data` into the viewport, so the room's own nodes stay
## exactly as the level scene wrote them; the clone is what the renderer sees.
##
## Bound through WorldSession.register_room_extension like the light field. The
## node also self-registers when its parent is a world session, so adding it to
## `world_root.tscn` is enough: no runner change and no authored scene change.
## When neither source exists the field reports "no authored map" and does nothing;
## the light field then falls back to screen-derived normals.

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
## Normal TileSet that mirrors the albedo tileset's atlas (one normal per pixel, one
## alternative per albedo alternative). Assigning it is what lights existing rooms
## with authored normals without adding a `NormalTiles` layer to any of them.
## `assets/images/primordial_tileset_normal.png` is generated with
## `tools/bake_tileset_normals.gd`; this is its TileSet.
@export var normal_tileset: TileSet
## Terrain layers cloned with `normal_tileset` when the room has no authored
## `NormalTiles` layer, in the order they are drawn.
##
## Both tile layers are listed: the background tiles carry their own normal map
## (they are half of what the room shows) and the solid tiles are the walls, which
## occlude them. A later name draws over an earlier one, so the walls stay on top of
## the background instead of the room scene's node order deciding it.
@export var source_layer_names: Array[String] = ["BackTiles", "SolidTiles"]

var _room_pixels := Vector2i.ZERO
var _room_origin_pixels := Vector2i.ZERO
var _room_bound := false
var _has_map := false
var _texture: Texture2D
var _viewport: SubViewport
var _clone: TileMapLayer
## Every clone in the buffer, in draw order. A room merges its background tiles and
## its solid tiles, so the buffer is not a single layer any more.
var _clones: Array[TileMapLayer] = []
## Terrain the current room was bound with, kept so a TileSet assigned after the
## binding can rebuild the buffer without waiting for the next room.
var _terrain_root: Node
var _missing_tiles: Array[String] = []
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
	var cell_rect := RoomGrid.get_room_cell_rect(origin_chunk, chunks)
	_room_origin_pixels = cell_rect.position * RoomGrid.DEFAULT_CELL_SIZE
	_room_pixels = cell_rect.size * RoomGrid.DEFAULT_CELL_SIZE
	_room_bound = true
	_terrain_root = terrain_root
	var layer := _find_authored_layer(terrain_root)
	if layer != null:
		_build_buffer(terrain_root, [layer], layer.tile_set, false)
	elif normal_tileset != null:
		# No hand-authored layer: mirror the room's own terrain into normals with
		# the generated tileset, so every existing room gets relief unedited.
		var sources := _find_layers_named(terrain_root, source_layer_names)
		_build_buffer(terrain_root, sources, normal_tileset, true)
	_push_to_light_fields()
	return true


## Assigns the normal TileSet at runtime (a runner or a test wiring the field up in
## code). Rebuilds the bound room's buffer so the change takes effect immediately;
## with no room bound this is just a property write.
func set_normal_tileset(tileset: TileSet) -> void:
	if normal_tileset == tileset:
		return
	normal_tileset = tileset
	_rebuild_for_terrain()


## Rebuilds the buffer for the room that is already bound, keeping the room's size
## and origin (a rebind would read them again, a TileSet change must not).
func _rebuild_for_terrain() -> void:
	if not _room_bound or not is_instance_valid(_terrain_root):
		return
	if _find_authored_layer(_terrain_root) != null or normal_tileset == null:
		# The room authored its own normals: the tile set is not its source.
		return
	var terrain_root := _terrain_root
	var pixels := _room_pixels
	var origin := _room_origin_pixels
	clear_room()
	_terrain_root = terrain_root
	_room_pixels = pixels
	_room_origin_pixels = origin
	_room_bound = true
	_build_buffer(terrain_root, _find_layers_named(terrain_root, source_layer_names), normal_tileset, true)
	_push_to_light_fields()


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
	_clones.clear()
	_missing_tiles.clear()
	_terrain_root = null
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


## The authored buffer as an image. Debug/inspection only: a render-target read
## back stalls the GPU, so nothing in the game path may call this.
func get_normal_image() -> Image:
	if _texture == null:
		return null
	return _texture.get_image()


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


## The topmost cloned layer: the one whose normals win, which for a room with a
## background and a wall layer is the wall layer. Single-layer rooms get that layer.
func get_buffer_layer() -> TileMapLayer:
	return _clone


## Every cloned layer, in draw order (the last one is on top). The buffer is a merge
## of the background and the solid tiles, so a caller that wants to check what the
## buffer covers has to look at all of them.
func get_buffer_layers() -> Array[TileMapLayer]:
	return _clones.duplicate()


## Accepts the same room pattern as LightField, with the authoring-scene nesting
## and the baked runtime nesting both understood: an explicit `layer_path` wins,
## otherwise the first layer of that name anywhere under the room is the authored
## one.
func _find_authored_layer(terrain_root: Node) -> TileMapLayer:
	var layer := terrain_root.get_node_or_null(layer_path) as TileMapLayer
	if layer != null:
		return layer
	var found := _find_layers_named(terrain_root, [layer_name] as Array[String])
	return found[0] if not found.is_empty() else null


## Every terrain layer with one of the given names, in tree order, so the clone
## order (and with it the draw order inside the normal viewport) follows the room.
## Layers without a tile set or without cells carry no normals and are skipped.
func _find_layers_named(terrain_root: Node, wanted: Array[String]) -> Array[TileMapLayer]:
	var layers: Array[TileMapLayer] = []
	if wanted.is_empty():
		return layers
	_collect_layers(terrain_root, wanted, layers)
	# Sort by the requested order: the clones are added in array order, so this is
	# what decides that the background normals sit underneath the walls.
	layers.sort_custom(func(left: TileMapLayer, right: TileMapLayer) -> bool:
		return wanted.find(String(left.name)) < wanted.find(String(right.name))
	)
	return layers


func _collect_layers(node: Node, wanted: Array[String], layers: Array[TileMapLayer]) -> void:
	for child: Node in node.get_children():
		if child is TileMapLayer:
			var layer := child as TileMapLayer
			if layer.name in wanted and layer.tile_set != null and not layer.get_used_cells().is_empty():
				layers.append(layer)
		_collect_layers(child, wanted, layers)


## Builds the one-shot viewport and clones `layers` into it with `tileset`. When
## `check_tiles` is set the clone's tiles are also verified against that TileSet,
## which is how a room that uses a coordinate the normal atlas forgot becomes
## visible instead of silently flat.
func _build_buffer(
	terrain_root: Node, layers: Array[TileMapLayer], tileset: TileSet, check_tiles: bool
) -> void:
	if tileset == null or layers.is_empty():
		# A layer with no tiles carries no normals; it is not worth a viewport.
		return
	_missing_tiles.clear()
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

	# Clones, never the authored nodes: TileMapLayer has exactly one parent, and
	# reparenting would edit the owner's level. `tile_map_data` is a plain copy of
	# the cells (coordinates, alternative ids and flips), which is why the mirror
	# tileset has to keep the albedo's layout: the cells are not remapped.
	for layer: TileMapLayer in layers:
		if not check_tiles and layer.visible:
			# The layer is data, not art: leaving it visible would paint the normal
			# colours over the room. Warn instead of mutating the owner's node.
			push_warning(
				"NormalField: %s is visible; hide the authored NormalTiles layer so the room does not draw it"
				% layer.name
			)
		if check_tiles:
			_collect_missing_tiles(layer, tileset)
		var clone := TileMapLayer.new()
		clone.name = layer.name
		clone.tile_set = tileset
		clone.tile_map_data = layer.tile_map_data
		# A clone renders even when the source layer is hidden (a hidden `NormalTiles`
		# authored layer is the documented setup), so this is set explicitly.
		clone.visible = true
		clone.collision_enabled = false
		clone.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# Room-local canvas coordinates: the viewport is the room, so only the
		# layer's offset inside the room survives.
		var offset := layer.position
		var terrain_2d := terrain_root as Node2D
		if terrain_2d != null:
			offset = terrain_2d.to_local(layer.global_position)
		clone.position = offset
		_viewport.add_child(clone)
		_clones.append(clone)
		# The last layer added is the one drawn on top, which is what "the buffer
		# layer" means for anyone inspecting it.
		_clone = clone
	if check_tiles and not _missing_tiles.is_empty():
		push_warning(
			"NormalField: %d cell(s) have no tile in %s (%s); those pixels stay flat"
			% [_missing_tiles.size(), normal_tileset.resource_path, ", ".join(_missing_tiles.slice(0, 6))]
		)

	_texture = _viewport.get_texture()
	_has_map = true


## Cells the generated normal TileSet cannot resolve, as "coords/alternative"
## strings. Empty for a room that only uses tiles the normal atlas mirrors, which
## is what the baker guarantees: it copies every coordinate and every alternative.
func get_missing_normal_tiles() -> Array[String]:
	return _missing_tiles


func _collect_missing_tiles(layer: TileMapLayer, tileset: TileSet) -> void:
	for cell: Vector2i in layer.get_used_cells():
		var source_id := layer.get_cell_source_id(cell)
		var coords := layer.get_cell_atlas_coords(cell)
		var alternative := layer.get_cell_alternative_tile(cell)
		var entry := "%d:%d/%d" % [coords.x, coords.y, alternative]
		if _missing_tiles.has(entry):
			continue
		var source := tileset.get_source(source_id) as TileSetAtlasSource
		if source == null or source.get_tile_data(coords, alternative) == null:
			_missing_tiles.append(entry)


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
