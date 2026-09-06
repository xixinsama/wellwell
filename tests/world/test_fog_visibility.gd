extends Node

const FOG_VISIBILITY: Script = preload("res://scripts/world/fog_visibility.gd")
const FOG_OF_WAR: Script = preload("res://scripts/world/fog_of_war.gd")
const ROOM_AUTHORING_ROOT: Script = preload("res://scripts/authoring/room_authoring_root.gd")
const ROOM_DATA: Script = preload("res://scripts/world/room_data.gd")


class PersistenceSource extends Node:
	var explored_cells: Array[String] = []
	var explored_chunks: Array[String] = []
	var read_count := 0

	func mark_cell_explored(cell_id: String) -> bool:
		if explored_cells.has(cell_id):
			return false
		explored_cells.append(cell_id)
		return true

	func mark_chunk_explored(chunk_id: String) -> bool:
		if explored_chunks.has(chunk_id):
			return false
		explored_chunks.append(chunk_id)
		return true

	func get_explored_cells() -> Array[String]:
		read_count += 1
		return explored_cells.duplicate()


class FogWithFallback extends "res://scripts/world/fog_of_war.gd":
	var fallback_source: Node

	func _get_root_node(node_name: String) -> Node:
		if node_name == "SaveManager":
			return fallback_source
		return null


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_blocker_is_visible_but_stops_spread(failures)
	_assert_room_spread_crosses_chunk_boundary(failures)
	_assert_room_bounds_stop_spread(failures)
	_assert_room_chunks_configure_cell_bounds(failures)
	_assert_bound_room_uses_exact_pixel_origin_and_mask_size(failures)
	_assert_mask_image_matches_current_visibility(failures)
	_assert_cell_ids_are_stable(failures)
	_assert_bound_persistence_source_overrides_fallback(failures)
	_assert_authoring_ancestor_disables_unbound_fallback_reads(failures)
	_assert_real_tilemap_blockers_use_world_coordinates(failures)
	_assert_room_switch_clears_old_state_and_mask(failures)
	_assert_process_refreshes_mask_texture(failures)
	return failures


func _assert_blocker_is_visible_but_stops_spread(failures: Array[String]) -> void:
	var blockers: Dictionary[Vector2i, bool] = {Vector2i(1, 0): true}
	var visibility: RefCounted = FOG_VISIBILITY.new()
	var visible: Dictionary[Vector2i, bool] = visibility.compute_room_visible_cells(
		Vector2i(0, 0),
		Vector2i(0, 0),
		Vector2i(4, 1),
		blockers
	)
	if not visible.has(Vector2i(1, 0)):
		failures.append("blocking cell face was not revealed")
	if visible.has(Vector2i(2, 0)):
		failures.append("fog spread propagated through a blocking cell")


func _assert_room_spread_crosses_chunk_boundary(failures: Array[String]) -> void:
	var visibility: RefCounted = FOG_VISIBILITY.new()
	var visible: Dictionary[Vector2i, bool] = visibility.compute_room_visible_cells(
		Vector2i(39, 11),
		Vector2i(0, 0),
		Vector2i(80, 23),
		{}
	)
	if not visible.has(Vector2i(0, 11)) or not visible.has(Vector2i(79, 11)):
		failures.append("room fog did not spread across a two-chunk room")


func _assert_room_bounds_stop_spread(failures: Array[String]) -> void:
	var visibility: RefCounted = FOG_VISIBILITY.new()
	var visible: Dictionary[Vector2i, bool] = visibility.compute_room_visible_cells(
		Vector2i(0, 0),
		Vector2i(0, 0),
		Vector2i(2, 2),
		{}
	)
	if visible.has(Vector2i(-1, 0)) or visible.has(Vector2i(2, 0)):
		failures.append("room fog spread outside the active room")


func _assert_room_chunks_configure_cell_bounds(failures: Array[String]) -> void:
	var fog: Node2D = FOG_OF_WAR.new() as Node2D
	fog.cell_size = Vector2i(8, 8)
	fog.chunk_size_pixels = Vector2i(320, 180)
	fog.set_room_chunks(Vector2i(2, 1), Vector2i(3, 2))
	if fog.map_origin_cell != Vector2i(80, 23):
		failures.append("room chunk origin did not convert to fog cells")
	if fog.map_size_cells != Vector2i(120, 45):
		failures.append("room chunk size did not use the exact total pixel extent")
	fog.free()


func _assert_bound_room_uses_exact_pixel_origin_and_mask_size(failures: Array[String]) -> void:
	var fog: Node2D = FOG_OF_WAR.new() as Node2D
	fog.cell_size = Vector2i(8, 8)
	fog.chunk_size_pixels = Vector2i(320, 180)
	var room: Resource = _make_room("offset_room", Vector2i(0, 1))
	var terrain := _make_terrain_root()
	if fog.call("bind_room", room, terrain) != true:
		failures.append("fog rejected exact-origin room fixture")
	else:
		if fog.world_to_cell(Vector2(4.0, 180.0)) != Vector2i(0, 23):
			failures.append("room pixel origin did not map to its first local fog row")
		var first_rect: Rect2 = fog.call("_cell_rect", Vector2i(0, 23))
		if first_rect.position != Vector2(0.0, 180.0):
			failures.append("first room fog row was not drawn at exact pixel y=180")
		fog.reveal_from_cell(Vector2i(0, 23), {})
		if fog.get_mask_image() == null or fog.get_mask_image().get_size() != Vector2i(320, 180):
			failures.append("bound room fog mask did not use exact 320x180 pixel size")
	terrain.free()
	fog.free()


func _assert_mask_image_matches_current_visibility(failures: Array[String]) -> void:
	var fog: Node2D = FOG_OF_WAR.new() as Node2D
	fog.map_origin_cell = Vector2i(0, 0)
	fog.map_size_cells = Vector2i(4, 1)
	fog.cell_size = Vector2i(8, 8)
	fog.reveal_from_cell(Vector2i(0, 0), {Vector2i(1, 0): true})

	var mask: Image = fog.get_mask_image()
	if mask == null:
		failures.append("fog mask image was not created")
	elif mask.get_size() != Vector2i(32, 8):
		failures.append("fog mask image did not match room pixel size")
	elif mask.get_pixel(4, 4).a != 0.0:
		failures.append("visible fog mask pixel was not transparent")
	elif mask.get_pixel(12, 4).a != 0.0:
		failures.append("blocking fog mask pixel was not transparent")
	elif mask.get_pixel(20, 4).a <= 0.9:
		failures.append("unreached fog mask pixel was not opaque")
	if fog.get_mask_texture() == null:
		failures.append("fog mask texture was not created")
	fog.free()


func _assert_cell_ids_are_stable(failures: Array[String]) -> void:
	var fog: Node2D = FOG_OF_WAR.new() as Node2D
	fog.level_id = "level_01"
	if fog.cell_to_id(Vector2i(12, -4)) != "level_01:12,-4":
		failures.append("fog cell id format changed")
	var saved_ids: Array[String] = ["level_01:12,-4", "other:1,1", "broken"]
	fog.load_explored_cells(saved_ids)
	if not fog.is_cell_explored(Vector2i(12, -4)):
		failures.append("saved fog cell id was not loaded")
	if fog.is_cell_explored(Vector2i(1, 1)):
		failures.append("foreign level cell id was loaded")
	fog.free()


func _assert_bound_persistence_source_overrides_fallback(failures: Array[String]) -> void:
	var fog := FogWithFallback.new()
	fog.level_id = "preview"
	fog.map_origin_cell = Vector2i.ZERO
	fog.map_size_cells = Vector2i(2, 1)
	var fallback := PersistenceSource.new()
	var explicit := PersistenceSource.new()
	fog.fallback_source = fallback
	fog.bind_persistence_source(explicit)
	explicit.explored_cells.append("preview:0,0")
	fog.call("_load_saved_progress")
	if explicit.read_count != 1 or fallback.read_count != 0:
		failures.append("bound fog persistence source did not override fallback reads")
	fog.reveal_from_cell(Vector2i.ZERO, {})
	if explicit.explored_cells.is_empty() or not fallback.explored_cells.is_empty():
		failures.append("bound fog persistence source did not override SaveManager fallback")

	fog.bind_persistence_source(null)
	fog.reveal_from_cell(Vector2i.ZERO, {})
	if not fallback.explored_cells.is_empty():
		failures.append("explicit null fog persistence source did not disable persistence")

	fog.clear_persistence_source()
	fog.level_id = "runtime"
	fog.reveal_from_cell(Vector2i.ZERO, {})
	if fallback.explored_chunks.is_empty():
		failures.append("clearing fog persistence source did not restore SaveManager fallback")
	fog.free()
	explicit.free()
	fallback.free()


func _assert_authoring_ancestor_disables_unbound_fallback_reads(failures: Array[String]) -> void:
	var root: Node2D = ROOM_AUTHORING_ROOT.new() as Node2D
	var preview := Node2D.new()
	preview.name = "PreviewOnly"
	root.add_child(preview)
	var fog := FogWithFallback.new()
	preview.add_child(fog)
	var fallback := PersistenceSource.new()
	fog.fallback_source = fallback
	fog.call("_load_saved_progress")
	if fallback.read_count != 0:
		failures.append("authoring preview fog read from the global SaveManager fallback")
	root.free()
	fallback.free()


func _assert_real_tilemap_blockers_use_world_coordinates(failures: Array[String]) -> void:
	var root := Node2D.new()
	root.position = Vector2(8.0, 0.0)
	var terrain := Node2D.new()
	terrain.name = "Terrain"
	terrain.position = Vector2(8.0, 0.0)
	root.add_child(terrain)
	var layers: Dictionary[String, TileMapLayer] = {}
	for layer_name: String in ["SolidTiles", "VisionBlockTiles", "GlassTiles"]:
		var layer := TileMapLayer.new()
		layer.name = layer_name
		layer.tile_set = _make_minimal_tileset()
		terrain.add_child(layer)
		layers[layer_name] = layer
	(layers["SolidTiles"] as TileMapLayer).set_cell(Vector2i(1, 0), 0, Vector2i.ZERO)
	(layers["VisionBlockTiles"] as TileMapLayer).set_cell(Vector2i(2, 0), 0, Vector2i.ZERO)
	(layers["GlassTiles"] as TileMapLayer).set_cell(Vector2i(3, 0), 0, Vector2i.ZERO)

	var fog: Node2D = FOG_OF_WAR.new() as Node2D
	fog.map_origin_cell = Vector2i.ZERO
	fog.map_size_cells = Vector2i(16, 4)
	fog.cell_size = Vector2i(8, 8)
	fog.set("_solid_tiles", layers["SolidTiles"])
	fog.set("_vision_block_tiles", layers["VisionBlockTiles"])
	fog.set("_glass_tiles", layers["GlassTiles"])
	var player := Node2D.new()
	root.add_child(player)
	fog.call("bind_player", player)
	root.add_child(fog)
	add_child(root)

	var blockers: Dictionary = fog.call("_collect_blockers")
	for layer_name: String in ["SolidTiles", "VisionBlockTiles", "GlassTiles"]:
		var layer: TileMapLayer = layers[layer_name]
		var expected_cell: Vector2i = fog.call("world_to_cell", layer.to_global(layer.map_to_local(layer.get_used_cells()[0])))
		if not blockers.has(expected_cell):
			failures.append("FogOfWar did not transform %s blocker cells into world coordinates" % layer_name)
		if not fog.currently_visible.has(expected_cell):
			fog.call("reveal_from_cell", expected_cell, {expected_cell: true})
		if not fog.currently_visible.has(expected_cell):
			failures.append("%s blocker cell was not visible itself" % layer_name)

	root.free()


func _assert_room_switch_clears_old_state_and_mask(failures: Array[String]) -> void:
	var fog: Node2D = FOG_OF_WAR.new() as Node2D
	fog.cell_size = Vector2i(8, 8)
	fog.chunk_size_pixels = Vector2i(320, 180)
	var source := PersistenceSource.new()
	source.explored_cells = ["room_b:40,0"]
	fog.bind_persistence_source(source)
	var room_a: Resource = _make_room("room_a", Vector2i.ZERO)
	var room_b: Resource = _make_room("room_b", Vector2i(1, 0))
	var terrain_a := _make_terrain_root()
	var terrain_b := _make_terrain_root()
	if not fog.has_method("bind_room"):
		failures.append("missing production API: FogOfWar.bind_room")
	else:
		if fog.call("bind_room", room_a, terrain_a) != true:
			failures.append("FogOfWar rejected the first room binding")
		fog.call("reveal_from_cell", Vector2i.ZERO, {})
		if fog.currently_visible.is_empty() or fog.get_mask_image() == null:
			failures.append("FogOfWar first room did not produce visible state and mask")
		if fog.call("bind_room", room_b, terrain_b) != true:
			failures.append("FogOfWar rejected the second room binding")
		else:
			if not fog.currently_visible.is_empty():
				failures.append("room switch retained currently visible cells from the old room")
			if fog.is_cell_explored(Vector2i.ZERO):
				failures.append("room switch retained explored cells from the old room")
			if not fog.is_cell_explored(Vector2i(40, 0)):
				failures.append("room switch did not load persisted exploration for the new room")
			if fog.get_mask_image() != null or fog.get_mask_texture() != null:
				failures.append("room switch retained the old fog mask")
		var previous_solid: TileMapLayer = fog.get("_solid_tiles")
		var invalid_terrain := _make_terrain_root()
		invalid_terrain.get_node("Terrain/MarkerTiles").free()
		if fog.call("bind_room", room_a, invalid_terrain) == true:
			failures.append("FogOfWar accepted an invalid room terrain binding")
		if fog.get("_solid_tiles") != previous_solid or fog.get("level_id") != "room_b":
			failures.append("invalid room binding replaced the previous valid room")
		invalid_terrain.free()
		fog.call("clear_room")
		fog.call("_process", 0.0)
		if fog.get_mask_image() != null or not fog.currently_visible.is_empty():
			failures.append("clear_room did not remain cleared after a process frame")

	terrain_a.free()
	terrain_b.free()
	fog.free()
	source.free()


func _assert_process_refreshes_mask_texture(failures: Array[String]) -> void:
	var root := Node2D.new()
	var player := Node2D.new()
	player.name = "Player"
	player.position = Vector2(4.0, 4.0)
	root.add_child(player)
	var fog: Node2D = FOG_OF_WAR.new() as Node2D
	fog.map_origin_cell = Vector2i.ZERO
	fog.map_size_cells = Vector2i(4, 2)
	fog.cell_size = Vector2i(8, 8)
	fog.player_path = NodePath()
	fog.call("bind_player", player)
	var solid := TileMapLayer.new()
	solid.name = "SolidTiles"
	root.add_child(solid)
	fog.solid_tiles_path = NodePath("../SolidTiles")
	root.add_child(fog)
	add_child(root)
	if not fog.has_method("bind_player"):
		failures.append("missing production API: FogOfWar.bind_player")
	else:
		fog.call("bind_player", player)
		fog.call("_process", 0.0)
		var mask: Image = fog.get_mask_image()
		if mask == null or mask.get_size() != Vector2i(32, 16):
			failures.append("FogOfWar process did not refresh a room-sized mask image")
		if fog.get_mask_texture() == null:
			failures.append("FogOfWar process did not refresh the mask texture")
		player.position = Vector2(20.0, 12.0)
		var before: Image = fog.get_mask_image()
		fog.call("_process", 0.0)
		if fog.get_mask_image() == null or fog.get_mask_texture() == null:
			failures.append("FogOfWar reveal update discarded the mask image or texture")
		elif fog.get_mask_image().get_size() != before.get_size():
			failures.append("FogOfWar reveal update changed mask dimensions")

	root.free()


func _make_room(room_id: String, origin_chunk: Vector2i) -> Resource:
	var room: Resource = ROOM_DATA.new()
	room.room_id = room_id
	room.room_origin_chunk = origin_chunk
	room.room_size_chunks = Vector2i.ONE
	return room


func _make_terrain_root() -> Node2D:
	var root := Node2D.new()
	var background := Node2D.new()
	background.name = "Background"
	root.add_child(background)
	var terrain := Node2D.new()
	terrain.name = "Terrain"
	root.add_child(terrain)
	for layer_name: String in ["BackTiles", "SolidTiles", "GlassTiles", "VisionBlockTiles", "DetailTiles", "MarkerTiles"]:
		var layer := TileMapLayer.new()
		layer.name = layer_name
		terrain.add_child(layer)
	return root


func _make_minimal_tileset() -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(8, 8)
	var source := TileSetAtlasSource.new()
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = Vector2i(8, 8)
	source.create_tile(Vector2i.ZERO)
	tile_set.add_source(source, 0)
	return tile_set
