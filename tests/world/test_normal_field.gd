extends Node

## NormalField: the room's authored normal buffer and its hand-off to LightField.
##
## The buffer itself is rendered on the GPU, so these tests cover what a headless
## run can see: the room binding with and without an authored layer, the clone
## that keeps the owner's node untouched, the hand-off to the shade/glow
## materials, the fallback when a room has no normals, and room rebinding.

const NORMAL_FIELD: Script = preload("res://scripts/world/normal_field.gd")
const LIGHT_FIELD: Script = preload("res://scripts/world/light_field.gd")
const ROOM_DATA: Script = preload("res://addons/platformer_kit/world/data/room_data.gd")

const TILE := 8


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_binding_without_a_layer(failures)
	_assert_clone_matches_the_authored_layer(failures)
	_assert_handshake_reaches_the_light_materials(failures)
	_assert_authored_mode_falls_back_without_a_map(failures)
	_assert_binding_order_does_not_matter(failures)
	_assert_rebinding_replaces_the_buffer(failures)
	return failures


func _assert_binding_without_a_layer(failures: Array[String]) -> void:
	var rig := _make_rig(false)
	var field: Node2D = NORMAL_FIELD.new() as Node2D
	rig["root"].add_child(field)
	if not bool(field.call("bind_room_with_origin", _make_room(Vector2i.ONE), rig["room"], Vector2i.ZERO)):
		failures.append("NormalField rejected a room without a NormalTiles layer")
	if not bool(field.call("is_room_bound")):
		failures.append("NormalField did not report a normal-less room as bound")
	if bool(field.call("has_normal_map")):
		failures.append("NormalField reported an authored map without a NormalTiles layer")
	if field.call("get_normal_texture") != null:
		failures.append("NormalField exposed a texture for a room without normals")
	if field.call("get_normal_pixels") != Vector2i(320, 184):
		failures.append("NormalField built the wrong room size %s" % str(field.call("get_normal_pixels")))
	for child: Node in field.get_children():
		if child is SubViewport:
			failures.append("NormalField built a viewport for a room without normals")
	rig["root"].free()


func _assert_clone_matches_the_authored_layer(failures: Array[String]) -> void:
	var rig := _make_rig(true)
	var layer: TileMapLayer = rig["normal"]
	var original_cells: Array[Vector2i] = layer.get_used_cells()
	var original_data := layer.tile_map_data.duplicate()
	var field: Node2D = NORMAL_FIELD.new() as Node2D
	rig["root"].add_child(field)
	field.call("bind_room_with_origin", _make_room(Vector2i.ONE), rig["room"], Vector2i.ZERO)
	if not bool(field.call("has_normal_map")):
		failures.append("NormalField did not report the authored normal map")
	if field.call("get_normal_pixels") != Vector2i(320, 184):
		failures.append("normal buffer is not the room size")
	if field.call("get_normal_texture") == null:
		failures.append("NormalField did not expose the normal buffer texture")
	var viewport := field.get_node_or_null("NormalViewport") as SubViewport
	if viewport == null:
		failures.append("NormalField did not build its normal viewport")
		rig["root"].free()
		return
	if viewport.size != Vector2i(320, 184):
		failures.append("normal viewport is not the room size")
	if viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS:
		failures.append("normal viewport repaints every frame instead of once per room")
	if viewport.transparent_bg:
		failures.append("normal viewport is transparent: uncovered pixels would have no flat normal")
	if viewport.canvas_item_default_texture_filter != Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST:
		failures.append("normal viewport filters the authored normals")
	var flat := viewport.get_node_or_null("FlatNormal") as ColorRect
	if flat == null:
		failures.append("normal viewport has no flat-normal clear colour")
	elif flat.color != NORMAL_FIELD.FLAT_COLOR:
		failures.append("normal viewport clears to %s instead of the flat normal" % str(flat.color))
	var clone := field.call("get_buffer_layer") as TileMapLayer
	if clone == null:
		failures.append("normal viewport has no cloned TileMapLayer")
		rig["root"].free()
		return
	if clone == layer:
		failures.append("the authored layer was used directly instead of a clone")
	if clone.get_parent() != viewport:
		failures.append("the cloned layer is not inside the normal viewport")
	if clone.tile_set != layer.tile_set:
		failures.append("the clone does not share the authored tile set")
	if clone.tile_map_data != original_data:
		failures.append("the clone does not copy the authored tile_map_data")
	if clone.get_used_cells() != original_cells:
		failures.append("the clone does not have the authored cells")
	else:
		for cell: Vector2i in original_cells:
			if clone.get_cell_atlas_coords(cell) != layer.get_cell_atlas_coords(cell):
				failures.append("clone cell %s uses a different atlas tile" % str(cell))
				break
	if clone.collision_enabled:
		failures.append("normal clone still builds collisions")
	if clone.texture_filter != CanvasItem.TEXTURE_FILTER_NEAREST:
		failures.append("normal clone filters the tile art")
	# The owner's node must stay exactly where the level scene put it.
	if layer.get_parent() != rig["terrain"]:
		failures.append("the authored NormalTiles layer was reparented")
	if layer.tile_map_data != original_data:
		failures.append("the authored NormalTiles data was mutated")
	rig["root"].free()


func _assert_handshake_reaches_the_light_materials(failures: Array[String]) -> void:
	var rig := _make_rig(true)
	var field: Node2D = LIGHT_FIELD.new() as Node2D
	var normal: Node2D = NORMAL_FIELD.new() as Node2D
	field.set("relief_normal_mode", 2)
	rig["root"].add_child(field)
	rig["root"].add_child(normal)
	field.call("bind_room_with_origin", _make_room(Vector2i.ONE), rig["room"], Vector2i.ZERO)
	normal.call("bind_room_with_origin", _make_room(Vector2i.ONE), rig["room"], Vector2i.ZERO)
	if int(field.call("get_effective_normal_mode")) != 2:
		failures.append("LightField did not switch to authored normals after the hand-off")
	var shade := field.get_node_or_null("LightShade") as Sprite2D
	var glow := field.get_node_or_null("LightGlow") as Sprite2D
	if shade == null or glow == null or not (shade.material is ShaderMaterial) or not (glow.material is ShaderMaterial):
		failures.append("light overlays have no shader material to receive the normals")
		rig["root"].free()
		return
	var shade_material := shade.material as ShaderMaterial
	var glow_material := glow.material as ShaderMaterial
	var authored: Texture2D = normal.call("get_normal_texture")
	for pair: Array in [
		["shade", shade_material], ["glow", glow_material]
	]:
		var label: String = pair[0]
		var material: ShaderMaterial = pair[1]
		if float(material.get_shader_parameter("normal_mode")) != 2.0:
			failures.append("%s pass did not receive normal_mode 2" % label)
		if material.get_shader_parameter("normal_tex") != authored:
			failures.append("%s pass did not receive the authored normal texture" % label)
		if material.get_shader_parameter("normal_pixels") != Vector2(320, 184):
			failures.append("%s pass received the wrong normal buffer size" % label)
		# Authored normals describe the art's real bevels, so the field scales the
		# strength by `authored_relief_gain` to match the derived mode's range.
		var expected_strength := float(field.get("relief_strength")) * float(field.get("authored_relief_gain"))
		if not is_equal_approx(float(material.get_shader_parameter("relief_strength")), expected_strength):
			failures.append("%s pass received the wrong relief strength" % label)
		if float(material.get_shader_parameter("relief_radius_px")) != 2.0:
			failures.append("%s pass received the wrong relief radius" % label)
	rig["root"].free()


func _assert_authored_mode_falls_back_without_a_map(failures: Array[String]) -> void:
	var rig := _make_rig(false)
	var field: Node2D = LIGHT_FIELD.new() as Node2D
	var normal: Node2D = NORMAL_FIELD.new() as Node2D
	field.set("relief_normal_mode", 2)
	rig["root"].add_child(field)
	rig["root"].add_child(normal)
	field.call("bind_room_with_origin", _make_room(Vector2i.ONE), rig["room"], Vector2i.ZERO)
	normal.call("bind_room_with_origin", _make_room(Vector2i.ONE), rig["room"], Vector2i.ZERO)
	if bool(normal.call("has_normal_map")):
		failures.append("NormalField invented a map for a room without NormalTiles")
	if int(field.call("get_effective_normal_mode")) != 1:
		failures.append("authored mode did not fall back to derived normals without a map")
	var shade := field.get_node_or_null("LightShade") as Sprite2D
	if shade != null and shade.material is ShaderMaterial:
		var material := shade.material as ShaderMaterial
		# A sampler must stay bound even in derived mode; the flat 1x1 texture is
		# never sampled there, but null parameters are a renderer error waiting.
		if material.get_shader_parameter("normal_tex") == null:
			failures.append("normal_tex sampler was left unbound in derived mode")
	# Flat mode is the explicit way back to the pre-normal look and must cost the
	# shader nothing, so the strength is what turns the feature off.
	field.set("relief_strength", 0.0)
	field.call("set_normal_field", null, Vector2i(320, 184), Vector2i.ZERO)
	if int(field.call("get_effective_normal_mode")) != 0:
		failures.append("relief_strength 0 did not switch the relief off")
	rig["root"].free()


func _assert_binding_order_does_not_matter(failures: Array[String]) -> void:
	# NormalField can bind before LightField (registration order is the scene's),
	# so LightField has to pick the buffer up on its own bind too.
	var rig := _make_rig(true)
	var normal: Node2D = NORMAL_FIELD.new() as Node2D
	var field: Node2D = LIGHT_FIELD.new() as Node2D
	field.set("relief_normal_mode", 2)
	rig["root"].add_child(normal)
	rig["root"].add_child(field)
	normal.call("bind_room_with_origin", _make_room(Vector2i.ONE), rig["room"], Vector2i.ZERO)
	field.call("bind_room_with_origin", _make_room(Vector2i.ONE), rig["room"], Vector2i.ZERO)
	if int(field.call("get_effective_normal_mode")) != 2:
		failures.append("LightField ignored a NormalField that bound before it")
	var shade := field.get_node_or_null("LightShade") as Sprite2D
	if shade != null and shade.material is ShaderMaterial:
		var material := shade.material as ShaderMaterial
		if material.get_shader_parameter("normal_tex") != normal.call("get_normal_texture"):
			failures.append("later LightField bind did not adopt the existing normal buffer")
	rig["root"].free()


func _assert_rebinding_replaces_the_buffer(failures: Array[String]) -> void:
	var rig := _make_rig(true)
	var field: Node2D = NORMAL_FIELD.new() as Node2D
	rig["root"].add_child(field)
	field.call("bind_room_with_origin", _make_room(Vector2i.ONE), rig["room"], Vector2i.ZERO)
	var first: Texture2D = field.call("get_normal_texture")
	field.call("bind_room_with_origin", _make_room(Vector2i(2, 1)), rig["room"], Vector2i.ZERO)
	if field.call("get_normal_pixels") != Vector2i(640, 184):
		failures.append("rebinding did not resize the normal buffer")
	if field.call("get_normal_texture") == first:
		failures.append("rebinding kept the old normal buffer texture")
	var viewports := 0
	for child: Node in field.get_children():
		if child is SubViewport:
			viewports += 1
	if viewports != 1:
		failures.append("rebinding left %d normal viewports behind" % viewports)
	# Removing the layer must clear the map and take the viewport away.
	var layer: TileMapLayer = rig["normal"]
	layer.get_parent().remove_child(layer)
	layer.free()
	field.call("bind_room_with_origin", _make_room(Vector2i.ONE), rig["room"], Vector2i.ZERO)
	if bool(field.call("has_normal_map")):
		failures.append("NormalField kept reporting a map after the layer was removed")
	if field.call("get_normal_texture") != null:
		failures.append("NormalField kept the old normal texture")
	viewports = 0
	for child: Node in field.get_children():
		if child is SubViewport:
			viewports += 1
	if viewports != 0:
		failures.append("normal viewport survived the loss of the authored layer")
	field.call("clear_room")
	if bool(field.call("is_room_bound")):
		failures.append("clear_room kept the normal room bound")
	rig["root"].free()


func _make_room(chunks: Vector2i) -> Resource:
	var room: Resource = ROOM_DATA.new()
	room.room_id = "normal_room"
	room.room_size_chunks = chunks
	return room


## A world root with `Terrain/SolidTiles` and, optionally, `Terrain/NormalTiles`.
func _make_rig(with_normals: bool) -> Dictionary:
	var root := Node2D.new()
	root.name = "NormalRig"
	add_child(root)
	var terrain_root := Node2D.new()
	terrain_root.name = "TerrainRoot"
	root.add_child(terrain_root)
	var room := Node2D.new()
	room.name = "synthetic"
	terrain_root.add_child(room)
	var terrain := Node2D.new()
	terrain.name = "Terrain"
	room.add_child(terrain)
	var solid := TileMapLayer.new()
	solid.name = "SolidTiles"
	solid.tile_set = _make_tileset()
	terrain.add_child(solid)
	var normal: TileMapLayer = null
	if with_normals:
		normal = TileMapLayer.new()
		normal.name = "NormalTiles"
		normal.tile_set = _make_tileset()
		# Data-only, exactly as an authored normal layer should be.
		normal.visible = false
		terrain.add_child(normal)
		normal.set_cell(Vector2i(1, 1), 0, Vector2i(0, 0))
		normal.set_cell(Vector2i(2, 1), 0, Vector2i(1, 0))
	return {
		"root": root,
		"terrain_root": terrain_root,
		"room": room,
		"terrain": terrain,
		"normal": normal,
	}


## Two 8x8 tiles so the clone can be checked against more than one atlas cell.
func _make_tileset() -> TileSet:
	var image := Image.create(TILE * 2, TILE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.5, 0.5, 1.0, 1.0))
	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = Vector2i(TILE, TILE)
	source.create_tile(Vector2i(0, 0))
	source.create_tile(Vector2i(1, 0))
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE, TILE)
	tile_set.add_source(source, 0)
	return tile_set
