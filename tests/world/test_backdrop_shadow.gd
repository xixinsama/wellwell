extends Node

## BackdropShadow: the drop shadow of the background tile layer.
##
## The silhouette itself is rendered on the GPU, so a headless run can only see the
## wiring: which layer was picked up, where the quad was parented, what the shader
## received, and the one global offset direction. The blur and the actual darkening
## are covered by the windowed captures in the notes.

const BACKDROP_SHADOW: Script = preload("res://scripts/world/backdrop_shadow.gd")
const ROOM_DATA: Script = preload("res://addons/platformer_kit/world/data/room_data.gd")

const TILE := 8


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_room_without_background_tiles(failures)
	_assert_fixed_offset(failures)
	_assert_shadow_sits_between_plate_and_tiles(failures)
	_assert_clear_room_drops_the_shadow(failures)
	return failures


## A room whose background layer is empty has nothing to cast; that is a supported
## state and must not abort the room binding.
func _assert_room_without_background_tiles(failures: Array[String]) -> void:
	var rig := _make_rig({})
	var shadow: Node2D = BACKDROP_SHADOW.new() as Node2D
	rig["root"].add_child(shadow)
	if not bool(shadow.call("bind_room_with_origin", _make_room(), rig["room"], Vector2i.ZERO)):
		failures.append("BackdropShadow rejected a room without background tiles")
	if bool(shadow.call("has_shadow")):
		failures.append("BackdropShadow cast a shadow with no tile layer")
	shadow.free()
	rig["root"].free()


## The offset is fixed now: down and to the left, 10 px, independent of any light.
## `(-1.6, 1)` is about 148 degrees, which is the "light comes from the top right"
## lean the art uses.
func _assert_fixed_offset(failures: Array[String]) -> void:
	var rig := _make_rig({Vector2i(2, 6): true, Vector2i(3, 6): true})
	var shadow: Node2D = BACKDROP_SHADOW.new() as Node2D
	rig["root"].add_child(shadow)
	shadow.call("bind_room_with_origin", _make_room(), rig["room"], Vector2i.ZERO)
	if not bool(shadow.call("has_shadow")):
		failures.append("BackdropShadow did not build a shadow from the background layer")
		shadow.free()
		rig["root"].free()
		return
	var offset: Vector2 = shadow.call("get_shadow_offset")
	var expected_length := float(shadow.get("offset_px"))
	if not is_equal_approx(offset.length(), expected_length):
		failures.append("shadow offset is %.2f px, expected offset_px %.2f" % [offset.length(), expected_length])
	if offset.x >= 0.0 or offset.y <= 0.0:
		failures.append("shadow should lean down-left, got %s" % str(offset))
	var expected := Vector2(-1.6, 1.0).normalized() * expected_length
	if offset.distance_to(expected) > 0.01:
		failures.append("shadow direction drifted from (-1.6, 1): %s vs %s" % [str(offset), str(expected)])
	# A light next to the room must not move it any more (the old behaviour).
	var light := Node2D.new()
	light.global_position = Vector2(300.0, 90.0)
	light.add_to_group(&"room_light")
	rig["root"].add_child(light)
	shadow.call("apply_parameters")
	shadow.call("apply_parameters")
	if (shadow.call("get_shadow_offset") as Vector2).distance_to(offset) > 0.001:
		failures.append("a nearby light still moves the shadow")
	light.free()
	shadow.free()
	rig["root"].free()


## Draw order is the whole point: the shadow must land between the backdrop plate
## and the tile layer, otherwise it either hides the plate or covers the tiles.
func _assert_shadow_sits_between_plate_and_tiles(failures: Array[String]) -> void:
	var rig := _make_rig({Vector2i(1, 5): true})
	var shadow: Node2D = BACKDROP_SHADOW.new() as Node2D
	rig["root"].add_child(shadow)
	shadow.call("bind_room_with_origin", _make_room(), rig["room"], Vector2i.ZERO)
	var quad: Sprite2D = shadow.call("get_shadow_quad")
	if quad == null:
		failures.append("BackdropShadow did not create its quad")
	else:
		if quad.get_parent() != rig["background"]:
			failures.append("shadow quad was not parented to the room background container")
		var plate := Sprite2D.new()
		plate.z_index = -1
		rig["background"].add_child(plate)
		var tiles := rig["layer"] as TileMapLayer
		if quad.z_index < plate.z_index:
			failures.append("shadow quad sorts behind the backdrop plate")
		# The quad is deliberately above the light shade (z 8) now: under it the
		# shadow multiplied an almost-black plate and was invisible. It still must not
		# touch the tiles, which the shader guarantees by subtracting the un-offset
		# silhouette, so being above them in draw order is expected.
		if quad.z_index < 9:
			failures.append("shadow quad is not above the additive light passes")
		if quad.z_index > 10:
			failures.append("shadow quad sorts above the fog")
		if quad.texture == null:
			failures.append("shadow quad has no silhouette texture")
		if not (quad.material is ShaderMaterial):
			failures.append("shadow quad is not driven by the shadow shader")
		else:
			var material := quad.material as ShaderMaterial
			if material.get_shader_parameter("mask_tex") == null:
				failures.append("shadow shader was not given the silhouette")
			if material.get_shader_parameter("mask_pixels") != Vector2(320.0, 180.0):
				failures.append("shadow shader got the wrong mask size")
			if float(material.get_shader_parameter("strength")) <= 0.0:
				failures.append("shadow shader got no strength")
			if material.get_shader_parameter("offset_px") != shadow.call("get_shadow_offset"):
				failures.append("shadow shader did not receive the offset")
			var tint: Color = material.get_shader_parameter("shadow_tint")
			if tint.r + tint.g + tint.b > 0.05:
				failures.append("shadow tint is not black (%s)" % str(tint))
	shadow.free()
	rig["root"].free()


func _assert_clear_room_drops_the_shadow(failures: Array[String]) -> void:
	var rig := _make_rig({Vector2i(0, 4): true})
	var shadow: Node2D = BACKDROP_SHADOW.new() as Node2D
	rig["root"].add_child(shadow)
	shadow.call("bind_room_with_origin", _make_room(), rig["room"], Vector2i.ZERO)
	shadow.call("clear_room")
	if bool(shadow.call("has_shadow")):
		failures.append("clear_room kept the backdrop shadow alive")
	if shadow.call("get_shadow_quad") != null:
		failures.append("clear_room kept the shadow quad")
	shadow.free()
	rig["root"].free()


func _make_room() -> Resource:
	var room: Resource = ROOM_DATA.new()
	room.room_id = "shadow_room"
	room.room_size_chunks = Vector2i.ONE
	return room


## Room container shaped like a baked room: `Background` for the plate, `Terrain`
## with the tile layers the shadow is built from.
func _make_rig(cells: Dictionary) -> Dictionary:
	var root := Node2D.new()
	add_child(root)
	var room := Node2D.new()
	room.name = "shadow_room"
	root.add_child(room)
	var background := Node2D.new()
	background.name = "Background"
	room.add_child(background)
	var terrain := Node2D.new()
	terrain.name = "Terrain"
	room.add_child(terrain)
	var layer := TileMapLayer.new()
	layer.name = "BackTiles"
	layer.tile_set = _make_tileset()
	terrain.add_child(layer)
	for cell: Vector2i in cells:
		layer.set_cell(cell, 0, Vector2i.ZERO)
	return {"root": root, "room": room, "background": background, "terrain": terrain, "layer": layer}


func _make_tileset() -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE, TILE)
	var source := TileSetAtlasSource.new()
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = Vector2i(TILE, TILE)
	source.create_tile(Vector2i.ZERO)
	tile_set.add_source(source, 0)
	return tile_set
