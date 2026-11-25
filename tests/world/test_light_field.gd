extends Node

## LightField: the room-sized light map every system samples.
##
## The field itself is rendered on the GPU, so these tests cover the parts a
## headless run can see: the room binding, the occluder runs built from the solid
## layer, the overlay quads, and the hand-off of the map to the fog and the
## terrain outline.

const LIGHT_FIELD: Script = preload("res://game/world/light_field.gd")
const FOG_OF_WAR: Script = preload("res://addons/metroidvania_kit/map/discovery/fog_of_war.gd")
const TERRAIN_HIGHLIGHT: Script = preload("res://game/world/terrain_highlight.gd")
const ROOM_DATA: Script = preload("res://addons/platformer_kit/world/data/room_data.gd")

const TILE := 8


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_binding_builds_the_field(failures)
	_assert_occluders_merge_into_runs(failures)
	_assert_occluders_stay_room_local(failures)
	_assert_consumers_receive_the_map(failures)
	_assert_rebinding_replaces_the_field(failures)
	return failures


func _assert_binding_builds_the_field(failures: Array[String]) -> void:
	var rig := _make_rig()
	var field: Node2D = LIGHT_FIELD.new() as Node2D
	rig["root"].add_child(field)
	var player := Node2D.new()
	player.position = Vector2(100, 60)
	rig["root"].add_child(player)
	field.call("bind_player", player)
	if not bool(field.call("bind_room_with_origin", _make_room(Vector2i.ONE), rig["room"], Vector2i.ZERO)):
		failures.append("LightField rejected the room binding")
		rig["root"].free()
		return
	if not bool(field.call("is_room_bound")):
		failures.append("LightField did not report the room as bound")
	if field.call("get_light_pixels") != Vector2i(320, 184):
		failures.append("LightField built the wrong room size %s" % str(field.call("get_light_pixels")))
	if field.call("get_light_texture") == null:
		failures.append("LightField did not expose a light map texture")
	var shade := field.get_node_or_null("LightShade") as Sprite2D
	var glow := field.get_node_or_null("LightGlow") as Sprite2D
	if shade == null or glow == null:
		failures.append("LightField did not build both overlay quads")
	else:
		if shade.z_index != 8 or glow.z_index != 9:
			failures.append("light overlays are not below the fog draw order")
		if shade.texture != field.call("get_light_texture"):
			failures.append("shade quad does not show the light map")
		if not (shade.material is ShaderMaterial) or not (glow.material is ShaderMaterial):
			failures.append("light overlays are not driven by their shaders")
		else:
			var shade_params := shade.material as ShaderMaterial
			if shade_params.get_shader_parameter("light_tex") == null:
				failures.append("shade pass was not given the light map")
	var viewport := field.get_node_or_null("LightViewport") as SubViewport
	if viewport == null:
		failures.append("LightField did not build its light viewport")
	else:
		if viewport.size != Vector2i(320, 184):
			failures.append("light viewport is not the room size")
		if not viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS:
			failures.append("light viewport does not repaint every frame")
		# Three rings for the lantern: the small core, the halo and the dim spill
		# that reaches across the room so its shadows are long.
		var lights := viewport.get_node_or_null("Lights")
		if lights == null or lights.get_child_count() != 3:
			failures.append("lantern is not built from exactly three lights")
		else:
			for child: Node in lights.get_children():
				if not (child is PointLight2D):
					failures.append("lantern light is not a PointLight2D")
	rig["root"].free()


func _assert_occluders_merge_into_runs(failures: Array[String]) -> void:
	var rig := _make_rig()
	var layer: TileMapLayer = rig["layer"]
	# A straight wall costs a top run, a bottom run and the two end caps.
	for x: int in range(4):
		layer.set_cell(Vector2i(x, 3), 0, Vector2i.ZERO)
	var field: Node2D = LIGHT_FIELD.new() as Node2D
	rig["root"].add_child(field)
	field.call("bind_room_with_origin", _make_room(Vector2i.ONE), rig["room"], Vector2i.ZERO)
	var short_wall := int(field.call("get_occluder_count"))
	if short_wall != 4:
		failures.append("a 4-cell wall should build 4 occluders, got %d" % short_wall)
	# Extending the wall must not add occluders: the runs merge.
	for x: int in range(4, 10):
		layer.set_cell(Vector2i(x, 3), 0, Vector2i.ZERO)
	field.call("bind_room_with_origin", _make_room(Vector2i.ONE), rig["room"], Vector2i.ZERO)
	var long_wall := int(field.call("get_occluder_count"))
	if long_wall != short_wall:
		failures.append(
			"extending a wall should merge its runs, %d occluders became %d"
			% [short_wall, long_wall]
		)
	rig["root"].free()


func _assert_occluders_stay_room_local(failures: Array[String]) -> void:
	# A room placed away from chunk (0, 0) used to shift its occluders by the room
	# origin, which pushed every shadow off the map.
	var rig := _make_rig()
	var layer: TileMapLayer = rig["layer"]
	for x: int in range(2, 8):
		layer.set_cell(Vector2i(x, 4), 0, Vector2i.ZERO)
	var field: Node2D = LIGHT_FIELD.new() as Node2D
	rig["root"].add_child(field)
	field.call(
		"bind_room_with_origin", _make_room(Vector2i.ONE), rig["room"], Vector2i(1, 2)
	)
	var occluders := field.get_node_or_null("LightViewport/LightOccluders")
	if occluders == null or occluders.get_child_count() == 0:
		failures.append("room placed away from the origin built no occluders")
	else:
		var room_size := field.call("get_light_pixels") as Vector2i
		for child: Node in occluders.get_children():
			var occluder := child as LightOccluder2D
			if occluder == null or occluder.occluder == null:
				failures.append("occluder node has no polygon")
				break
			for point: Vector2 in occluder.occluder.polygon:
				if point.x < -8.0 or point.y < -8.0:
					failures.append(
						"occluder at %s is outside the room: it was shifted by the room origin"
						% str(point)
					)
					break
				if point.x > float(room_size.x) + 8.0 or point.y > float(room_size.y) + 8.0:
					failures.append("occluder at %s is past the room bounds" % str(point))
					break
	rig["root"].free()

func _assert_consumers_receive_the_map(failures: Array[String]) -> void:
	var rig := _make_rig()
	var fog: Node2D = FOG_OF_WAR.new() as Node2D
	rig["root"].add_child(fog)
	var highlight: Node2D = TERRAIN_HIGHLIGHT.new() as Node2D
	rig["root"].add_child(highlight)
	var field: Node2D = LIGHT_FIELD.new() as Node2D
	rig["root"].add_child(field)
	field.call("bind_room_with_origin", _make_room(Vector2i.ONE), rig["room"], Vector2i.ZERO)
	var consumers: Array = field.call("get_consumers")
	if not consumers.has(fog):
		failures.append("LightField did not hand the map to the fog")
	if not consumers.has(highlight):
		failures.append("LightField did not hand the map to the terrain outline")
	# The fog only applies the map once its own material exists, so build it.
	fog.set("map_origin_cell", Vector2i.ZERO)
	fog.set("map_size_cells", Vector2i(4, 1))
	fog.set("cell_size", Vector2i(8, 8))
	fog.call("reveal_from_cell", Vector2i(0, 0), {})
	var material: ShaderMaterial = fog.get("_mask_material")
	if material == null:
		failures.append("fog did not build its mask material")
	else:
		if material.get_shader_parameter("light_tex") == null:
			failures.append("fog mask material did not receive the light map")
		if float(material.get_shader_parameter("light_push_px")) <= 0.0:
			failures.append("fog light push stayed disabled with a map bound")
	rig["root"].free()


func _assert_rebinding_replaces_the_field(failures: Array[String]) -> void:
	var rig := _make_rig()
	var field: Node2D = LIGHT_FIELD.new() as Node2D
	rig["root"].add_child(field)
	field.call("bind_room_with_origin", _make_room(Vector2i.ONE), rig["room"], Vector2i.ZERO)
	var first: Texture2D = field.call("get_light_texture")
	field.call("bind_room_with_origin", _make_room(Vector2i(2, 1)), rig["room"], Vector2i.ZERO)
	if field.call("get_light_pixels") != Vector2i(640, 184):
		failures.append("rebinding did not resize the light map")
	if field.call("get_light_texture") == first:
		failures.append("rebinding kept the old light map texture")
	var viewports := 0
	for child: Node in field.get_children():
		if child is SubViewport:
			viewports += 1
	if viewports != 1:
		failures.append("rebinding left %d light viewports behind" % viewports)
	field.call("clear_room")
	if bool(field.call("is_room_bound")):
		failures.append("clear_room kept the room bound")
	if field.call("get_light_texture") != null:
		failures.append("clear_room kept the light map")
	rig["root"].free()


func _make_room(chunks: Vector2i) -> Resource:
	var room: Resource = ROOM_DATA.new()
	room.room_id = "light_room"
	room.room_size_chunks = chunks
	return room


## A world root with a Terrain/SolidTiles layer that already has a collision
## tileset, so the occluder builder sees real shapes.
func _make_rig() -> Dictionary:
	var root := Node2D.new()
	root.name = "LightRig"
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
	var layer := TileMapLayer.new()
	layer.name = "SolidTiles"
	layer.tile_set = _make_tileset()
	terrain.add_child(layer)
	return {"root": root, "terrain_root": terrain_root, "room": room, "terrain": terrain, "layer": layer}


func _make_tileset() -> TileSet:
	var image := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	image.fill(Color(1.0, 1.0, 1.0, 1.0))
	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = Vector2i(TILE, TILE)
	var coords := Vector2i.ZERO
	source.create_tile(coords)
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE, TILE)
	tile_set.add_physics_layer()
	tile_set.add_source(source, 0)
	var data := source.get_tile_data(coords, 0)
	data.add_collision_polygon(0)
	data.set_collision_polygon_points(
		0,
		0,
		PackedVector2Array([
			Vector2(-4.0, -4.0), Vector2(4.0, -4.0), Vector2(4.0, 4.0), Vector2(-4.0, 4.0)
		])
	)
	return tile_set
