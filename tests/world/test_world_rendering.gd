extends Node

## Merged test suite. Every inner class below is one original test file,
## kept in its own class so fixtures and helper names stay isolated. Do not
## add logic here: split a class back into its own file when it grows.

## tests/world/test_backdrop_field.gd
class BackdropFieldCase extends Node:
	## Contract for the room backdrop plate: one 320x180 plate per room, drawn
	## inside the room's `Background` container (which precedes `Terrain`), with the
	## background tilemap faded so the plate reads through it.

	const BACKDROP_SCRIPT := preload("res://scripts/world/backdrop_field.gd")

	const ROOM_SIZE := Vector2(320, 180)


	func run() -> Array[String]:
		var failures: Array[String] = []
		var world := _build_world()
		var field := Node2D.new()
		field.name = "BackdropField"
		field.set_script(BACKDROP_SCRIPT)
		world.add_child(field)
		field.call("decorate_rooms")
		var room: Node = world.get_node("TerrainRoot/room_a")
		var background: Node2D = room.get_node("Background")
		var plate := background.get_node_or_null("BackdropPlate") as Sprite2D
		if plate == null:
			failures.append("room did not receive a backdrop plate")
			world.free()
			return failures
		_assert_plate_geometry(plate, failures)
		_assert_draw_order(room, failures)
		_assert_background_alpha(room, field, failures)
		_assert_idempotent(field, background, failures)
		world.free()
		return failures


	func _assert_plate_geometry(plate: Sprite2D, failures: Array[String]) -> void:
		if plate.texture == null:
			failures.append("plate has no texture")
			return
		if Vector2(plate.texture.get_width(), plate.texture.get_height()) != ROOM_SIZE:
			failures.append("plate is not one game frame (320x180)")
		if plate.centered:
			failures.append("plate must be anchored to the room origin")
		if not plate.position.is_equal_approx(Vector2.ZERO):
			failures.append("plate is not at the room origin")
		if plate.material == null:
			failures.append("plate has no drift material")


	func _assert_draw_order(room: Node, failures: Array[String]) -> void:
		var background := room.get_node_or_null("Background")
		var terrain := room.get_node_or_null("Terrain")
		if background == null or terrain == null:
			failures.append("room is missing its Background/Terrain containers")
			return
		if background.get_index() > terrain.get_index():
			failures.append("Background container no longer draws before Terrain")


	func _assert_background_alpha(room: Node, field: Node, failures: Array[String]) -> void:
		var back := room.get_node_or_null("Terrain/BackTiles") as CanvasItem
		if back == null:
			failures.append("room is missing its background tilemap layer")
			return
		var want := float(field.get("background_tilemap_alpha"))
		if not is_equal_approx(want, 1.0):
			failures.append("tilemap layers must stay opaque and crisp by default")
		if not is_equal_approx(back.modulate.a, want):
			failures.append("background tilemap alpha does not follow the plate setting")


	func _assert_idempotent(field: Node, background: Node, failures: Array[String]) -> void:
		field.call("decorate_rooms")
		var plates := 0
		for child: Node in background.get_children():
			if child.name == "BackdropPlate":
				plates += 1
		if plates != 1:
			failures.append("re-decorating duplicated the plate (%d)" % plates)


	func _build_world() -> Node2D:
		var world := Node2D.new()
		world.name = "World"
		var rooms := Node2D.new()
		rooms.name = "TerrainRoot"
		world.add_child(rooms)
		var room := Node2D.new()
		room.name = "room_a"
		rooms.add_child(room)
		var background := Node2D.new()
		background.name = "Background"
		room.add_child(background)
		var terrain := Node2D.new()
		terrain.name = "Terrain"
		room.add_child(terrain)
		var back := TileMapLayer.new()
		back.name = "BackTiles"
		terrain.add_child(back)
		return world


## tests/world/test_backdrop_shadow.gd
class BackdropShadowCase extends Node:
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
				if material.get_shader_parameter("mask_pixels") != Vector2(320.0, 184.0):
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


## tests/world/test_dust_field.gd
class DustFieldCase extends Node:
	## DustField: single-pixel foreground dust.
	##
	## The motes are procedural, so everything here is deterministic: the layout is
	## seeded, the positions are integral, and the drift only ever wraps inside the
	## room rectangle.

	const DUST_FIELD: Script = preload("res://scripts/world/dust_field.gd")
	const ROOM_DATA: Script = preload("res://addons/platformer_kit/world/data/room_data.gd")


	func run() -> Array[String]:
		var failures: Array[String] = []
		_assert_binding_seeds_the_room(failures)
		_assert_motes_stay_inside_the_room(failures)
		_assert_motes_drift_slowly(failures)
		_assert_layout_is_deterministic(failures)
		_assert_clear_room_stops_the_dust(failures)
		return failures


	func _assert_binding_seeds_the_room(failures: Array[String]) -> void:
		var field: Node2D = DUST_FIELD.new() as Node2D
		add_child(field)
		field.set("count", 32)
		if not bool(field.call("bind_room_with_origin", _make_room(), null, Vector2i.ZERO)):
			failures.append("DustField rejected a room")
		if int(field.call("get_mote_count")) != 32:
			failures.append("DustField did not seed the requested mote count")
		var positions: PackedVector2Array = field.call("get_mote_positions")
		if positions.size() != 32:
			failures.append("DustField reported %d mote positions for 32 motes" % positions.size())
		for position: Vector2 in positions:
			if position != position.floor():
				failures.append("a mote is not on the pixel grid (%s)" % str(position))
				break
		field.free()


	func _assert_motes_stay_inside_the_room(failures: Array[String]) -> void:
		var field: Node2D = DUST_FIELD.new() as Node2D
		add_child(field)
		field.call("bind_room_with_origin", _make_room(), null, Vector2i(2, 1))
		var rect: Rect2 = field.call("get_room_rect")
		if rect.position != Vector2(640.0, 184.0) or rect.size != Vector2(320.0, 176.0):
			failures.append("DustField built the wrong room rect %s" % str(rect))
		# Drift for a long time: wrapping has to keep every mote inside the rect.
		for step: int in 400:
			field.call("_process", 0.25)
		for position: Vector2 in field.call("get_mote_positions"):
			if not rect.has_point(position):
				failures.append("a mote drifted out of the room rect: %s" % str(position))
				break
		field.free()


	func _assert_motes_drift_slowly(failures: Array[String]) -> void:
		var field: Node2D = DUST_FIELD.new() as Node2D
		add_child(field)
		field.call("bind_room_with_origin", _make_room(), null, Vector2i.ZERO)
		var rect: Rect2 = field.call("get_room_rect")
		var before: PackedVector2Array = field.call("get_mote_positions")
		field.call("_process", 1.0)
		var after: PackedVector2Array = field.call("get_mote_positions")
		var moved := 0
		var fastest := 0.0
		for index: int in mini(before.size(), after.size()):
			# Measure in wrapped space: a mote crossing the room edge is teleported by
			# the wrap, which is not motion.
			var dx := absf(after[index].x - before[index].x)
			var dy := absf(after[index].y - before[index].y)
			dx = minf(dx, rect.size.x - dx)
			dy = minf(dy, rect.size.y - dy)
			var delta := Vector2(dx, dy).length()
			if delta >= 1.0:
				moved += 1
			fastest = maxf(fastest, delta)
		if moved == 0:
			failures.append("dust never moved in one second")
		if fastest > 20.0:
			failures.append("dust moved %.1f px in one second, that is not slow" % fastest)
		field.free()


	func _assert_layout_is_deterministic(failures: Array[String]) -> void:
		var first: Node2D = DUST_FIELD.new() as Node2D
		add_child(first)
		first.call("bind_room_with_origin", _make_room(), null, Vector2i.ZERO)
		var first_positions: PackedVector2Array = first.call("get_mote_positions")
		first.free()
		var second: Node2D = DUST_FIELD.new() as Node2D
		add_child(second)
		second.call("bind_room_with_origin", _make_room(), null, Vector2i.ZERO)
		var second_positions: PackedVector2Array = second.call("get_mote_positions")
		if first_positions != second_positions:
			failures.append("two fresh rooms seeded different dust for the same seed")
		second.free()


	func _assert_clear_room_stops_the_dust(failures: Array[String]) -> void:
		var field: Node2D = DUST_FIELD.new() as Node2D
		add_child(field)
		field.call("bind_room_with_origin", _make_room(), null, Vector2i.ZERO)
		field.call("clear_room")
		if int(field.call("get_mote_count")) != 0:
			failures.append("clear_room kept the room's motes")
		if not (field.call("get_mote_positions") as PackedVector2Array).is_empty():
			failures.append("clear_room kept mote positions")
		field.free()


	func _make_room() -> Resource:
		var room: Resource = ROOM_DATA.new()
		room.room_id = "dust_room"
		room.room_size_chunks = Vector2i.ONE
		return room


## tests/world/test_atmosphere_settings.gd
class AtmosphereSettingsCase extends Node:
	## The gas layer follows the Game setting, live.

	const ATMOSPHERE := preload("res://addons/fluid_kit/runtime/gas/atmosphere.gd")


	class FakeSettings extends RefCounted:
		signal settings_changed

		var enabled := true

		func is_atmosphere_enabled() -> bool:
			return enabled

		func set_atmosphere_enabled(value: bool) -> void:
			enabled = value
			settings_changed.emit()


	func run() -> Array[String]:
		var failures: Array[String] = []
		var atmosphere := ATMOSPHERE.new() as Node2D
		add_child(atmosphere)
		if not bool(atmosphere.call("is_enabled")):
			failures.append("gas layer starts disabled")
		atmosphere.call("set_enabled", false)
		if bool(atmosphere.call("is_enabled")):
			failures.append("set_enabled(false) did not disable the gas layer")
		atmosphere.call("set_enabled", true)

		var settings := FakeSettings.new()
		atmosphere.call("bind_settings_source", settings)
		if not bool(atmosphere.call("is_enabled")):
			failures.append("gas layer ignored the enabled setting")
		settings.set_atmosphere_enabled(false)
		if bool(atmosphere.call("is_enabled")):
			failures.append("gas layer ignored a live settings change")
		settings.set_atmosphere_enabled(true)
		if not bool(atmosphere.call("is_enabled")):
			failures.append("gas layer did not turn back on")

		atmosphere.queue_free()
		return failures


func run() -> Array[String]:
	var failures: Array[String] = []
	failures.append_array(_run_case(BackdropFieldCase.new()))
	failures.append_array(_run_case(BackdropShadowCase.new()))
	failures.append_array(_run_case(DustFieldCase.new()))
	failures.append_array(_run_case(AtmosphereSettingsCase.new()))
	return failures


func _run_case(test: Node) -> Array[String]:
	add_child(test)
	var result: Array = test.call("run")
	test.queue_free()
	var failures: Array[String] = []
	failures.assign(result)
	return failures
