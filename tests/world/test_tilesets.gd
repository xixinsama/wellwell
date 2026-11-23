extends Node

## Merged test suite. Every inner class below is one original test file,
## kept in its own class so fixtures and helper names stay isolated. Do not
## add logic here: split a class back into its own file when it grows.

## tests/world/test_tileset_terrain.gd
class TilesetTerrainCase extends Node:
	## The `(4,0)`–`(5,1)` autotile set must resolve a painted solid region to the
	## expected edge/corner/fill tile, and every alternative must be solid.

	const TILESET_PATH := "res://resources/tilesets/primordial_tileset.tres"
	const TERRAIN_SET := 0
	const TERRAIN := 0

	const B_RIGHT := TileSet.CELL_NEIGHBOR_RIGHT_SIDE
	const B_BOTTOM_RIGHT := TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER
	const B_BOTTOM := TileSet.CELL_NEIGHBOR_BOTTOM_SIDE
	const B_BOTTOM_LEFT := TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER
	const B_LEFT := TileSet.CELL_NEIGHBOR_LEFT_SIDE
	const B_TOP_LEFT := TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER
	const B_TOP := TileSet.CELL_NEIGHBOR_TOP_SIDE
	const B_TOP_RIGHT := TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER

	const BIT_ORDER: Array[int] = [
		B_RIGHT, B_BOTTOM_RIGHT, B_BOTTOM, B_BOTTOM_LEFT,
		B_LEFT, B_TOP_LEFT, B_TOP, B_TOP_RIGHT,
	]

	## Terrain continues toward the listed neighbours. The rim is always drawn on the
	## side facing air, so a straight rim omits its own side and keeps the opposite
	## side: that bit is what stops a convex corner from matching a straight edge.
	const EXPECTED_BITS := {
		"4,0/0": [B_RIGHT, B_BOTTOM_RIGHT, B_BOTTOM, B_BOTTOM_LEFT, B_LEFT],
		"4,0/1": [B_RIGHT, B_LEFT, B_TOP_LEFT, B_TOP, B_TOP_RIGHT],
		"4,0/2": [B_RIGHT, B_BOTTOM_RIGHT, B_BOTTOM, B_TOP, B_TOP_RIGHT],
		"4,0/3": [B_BOTTOM, B_BOTTOM_LEFT, B_LEFT, B_TOP_LEFT, B_TOP],
		"4,1/0": [B_BOTTOM, B_BOTTOM_LEFT, B_LEFT],
		"4,1/1": [B_LEFT, B_TOP_LEFT, B_TOP],
		"4,1/2": [B_RIGHT, B_BOTTOM_RIGHT, B_BOTTOM],
		"4,1/3": [B_RIGHT, B_TOP, B_TOP_RIGHT],
		"5,0/0": [
			B_RIGHT, B_BOTTOM_RIGHT, B_BOTTOM, B_BOTTOM_LEFT,
			B_LEFT, B_TOP_LEFT, B_TOP, B_TOP_RIGHT,
		],
		"5,1/0": [B_RIGHT, B_BOTTOM_RIGHT, B_BOTTOM, B_BOTTOM_LEFT, B_LEFT, B_TOP, B_TOP_RIGHT],
		"5,1/1": [B_RIGHT, B_BOTTOM_RIGHT, B_BOTTOM, B_LEFT, B_TOP_LEFT, B_TOP, B_TOP_RIGHT],
		"5,1/2": [B_RIGHT, B_BOTTOM_RIGHT, B_BOTTOM, B_BOTTOM_LEFT, B_LEFT, B_TOP_LEFT, B_TOP],
		"5,1/3": [B_RIGHT, B_BOTTOM, B_BOTTOM_LEFT, B_LEFT, B_TOP_LEFT, B_TOP, B_TOP_RIGHT],
	}


	func run() -> Array[String]:
		var failures: Array[String] = []
		var tile_set := load(TILESET_PATH) as TileSet
		if tile_set == null:
			failures.append("primordial tileset could not be loaded")
			return failures
		_assert_terrain_set(tile_set, failures)
		_assert_expected_bits(tile_set, failures)
		_assert_solid(tile_set, failures)
		_assert_block_paint(tile_set, failures)
		_assert_notch_paint(tile_set, failures)
		return failures


	func _assert_terrain_set(tile_set: TileSet, failures: Array[String]) -> void:
		if tile_set.get_terrain_sets_count() != 1:
			failures.append("expected one terrain set, found %d" % tile_set.get_terrain_sets_count())
		elif tile_set.get_terrain_set_mode(TERRAIN_SET) != TileSet.TERRAIN_MODE_MATCH_CORNERS_AND_SIDES:
			failures.append("terrain set 0 must match corners and sides")
		if tile_set.get_terrains_count(TERRAIN_SET) != 1:
			failures.append("expected one terrain in set 0")


	func _assert_expected_bits(tile_set: TileSet, failures: Array[String]) -> void:
		var source := tile_set.get_source(0) as TileSetAtlasSource
		if source == null:
			failures.append("tileset has no atlas source 0")
			return
		var remaining: Dictionary = EXPECTED_BITS.duplicate()
		for tile_index: int in source.get_tiles_count():
			var atlas := source.get_tile_id(tile_index)
			for alternative_index: int in source.get_alternative_tiles_count(atlas):
				var alternative := source.get_alternative_tile_id(atlas, alternative_index)
				var data := source.get_tile_data(atlas, alternative)
				if data.terrain_set != TERRAIN_SET:
					continue
				var key := "%d,%d/%d" % [atlas.x, atlas.y, alternative]
				if not remaining.has(key):
					failures.append("unexpected terrain tile: %s" % key)
					continue
				var expected: Array = (remaining[key] as Array).duplicate()
				expected.sort()
				if _peering_bits(data) != expected:
					failures.append("%s peering bits are %s, expected %s" % [key, _peering_bits(data), expected])
				remaining.erase(key)
		if not remaining.is_empty():
			failures.append("missing terrain tiles: %s" % remaining.keys())


	func _assert_solid(tile_set: TileSet, failures: Array[String]) -> void:
		var source := tile_set.get_source(0) as TileSetAtlasSource
		if source == null:
			return
		for tile_index: int in source.get_tiles_count():
			var atlas := source.get_tile_id(tile_index)
			for alternative_index: int in source.get_alternative_tiles_count(atlas):
				var alternative := source.get_alternative_tile_id(atlas, alternative_index)
				var data := source.get_tile_data(atlas, alternative)
				if data.terrain_set != TERRAIN_SET:
					continue
				var key := "%d,%d/%d" % [atlas.x, atlas.y, alternative]
				if data.get_collision_polygons_count(0) != 1:
					failures.append("%s has no full-cell collision polygon" % key)
					continue
				var points := data.get_collision_polygon_points(0, 0)
				if points.size() != 4:
					failures.append("%s collision polygon has %d points, expected 4" % [key, points.size()])
					continue
				var bounds := Rect2(points[0], Vector2.ZERO)
				for point: Vector2 in points:
					bounds = bounds.expand(point)
				if bounds.position != Vector2(-4.0, -4.0) or bounds.size != Vector2(8.0, 8.0):
					failures.append("%s collision polygon is not the full 8x8 cell" % key)


	func _assert_block_paint(tile_set: TileSet, failures: Array[String]) -> void:
		var layer := TileMapLayer.new()
		layer.tile_set = tile_set
		add_child(layer)
		var cells: Array[Vector2i] = []
		for y in range(2, 8):
			for x in 10:
				cells.append(Vector2i(x, y))
		layer.set_cells_terrain_connect(cells, TERRAIN_SET, TERRAIN, true)
		_expect(layer, Vector2i(0, 2), Vector2i(4, 1), 2, failures, "block top-left corner")
		_expect(layer, Vector2i(1, 2), Vector2i(4, 0), 0, failures, "block top edge")
		_expect(layer, Vector2i(9, 2), Vector2i(4, 1), 0, failures, "block top-right corner")
		_expect(layer, Vector2i(0, 3), Vector2i(4, 0), 2, failures, "block left edge")
		_expect(layer, Vector2i(5, 3), Vector2i(5, 0), 0, failures, "block fill")
		_expect(layer, Vector2i(9, 3), Vector2i(4, 0), 3, failures, "block right edge")
		_expect(layer, Vector2i(0, 7), Vector2i(4, 1), 3, failures, "block bottom-left corner")
		_expect(layer, Vector2i(1, 7), Vector2i(4, 0), 1, failures, "block bottom edge")
		_expect(layer, Vector2i(9, 7), Vector2i(4, 1), 1, failures, "block bottom-right corner")
		layer.free()


	func _assert_notch_paint(tile_set: TileSet, failures: Array[String]) -> void:
		var layer := TileMapLayer.new()
		layer.tile_set = tile_set
		add_child(layer)
		var cells: Array[Vector2i] = []
		for y in range(2, 8):
			for x in 10:
				if x == 4 and y == 2:
					continue
				cells.append(Vector2i(x, y))
		layer.set_cells_terrain_connect(cells, TERRAIN_SET, TERRAIN, true)
		_expect(layer, Vector2i(3, 2), Vector2i(4, 1), 0, failures, "notch left lip")
		_expect(layer, Vector2i(5, 2), Vector2i(4, 1), 2, failures, "notch right lip")
		_expect(layer, Vector2i(4, 3), Vector2i(4, 0), 0, failures, "notch floor")
		_expect(layer, Vector2i(3, 3), Vector2i(5, 1), 2, failures, "notch top-right inner corner")
		_expect(layer, Vector2i(5, 3), Vector2i(5, 1), 0, failures, "notch top-left inner corner")
		layer.free()


	func _expect(
		layer: TileMapLayer,
		cell: Vector2i,
		atlas: Vector2i,
		alternative: int,
		failures: Array[String],
		label: String
	) -> void:
		var actual_atlas := layer.get_cell_atlas_coords(cell)
		var actual_alternative := layer.get_cell_alternative_tile(cell)
		if actual_atlas != atlas or actual_alternative != alternative:
			failures.append("%s at %s is %s/%d, expected %s/%d" % [
				label, cell, actual_atlas, actual_alternative, atlas, alternative,
			])


	func _peering_bits(data: TileData) -> Array[int]:
		var bits: Array[int] = []
		for bit: int in BIT_ORDER:
			if data.get_terrain_peering_bit(bit) >= 0:
				bits.append(bit)
		bits.sort()
		return bits


## tests/world/test_tileset_normals.gd
class TilesetNormalsCase extends Node:
	## The authored normal atlas of `primordial_tileset.png`, and the way NormalField
	## installs it into rooms that never authored normals themselves.
	##
	## The PNG and its TileSet are generated (`tools/bake_tileset_normals.gd`),
	## so this file is the contract the generator has to keep:
	##
	## - the normal PNG has the albedo's size and the albedo's alpha, every opaque
	##   pixel decodes to a unit normal pointing out of the screen, every transparent
	##   pixel is the flat normal with alpha 0 (so empty atlas cells stay a no-op);
	## - the normal TileSet mirrors the albedo's structure exactly (same coordinates,
	##   same alternative ids in the same order, same flip/transpose flags), because a
	##   clone of a room layer copies raw `tile_map_data`: the cell coordinates and
	##   alternative ids are never remapped;
	## - a real baked room, bound through NormalField with `normal_tileset` assigned,
	##   produces a map with the same cells as its solid layer and no missing tile.

	const NORMAL_FIELD: Script = preload("res://game/world/normal_field.gd")
	const ROOM_DATA: Script = preload("res://addons/platformer_kit/world/data/room_data.gd")

	const ALBEDO_PNG := "res://assets/images/primordial_tileset.png"
	const NORMAL_PNG := "res://assets/images/primordial_tileset_normal.png"
	const ALBEDO_TILESET := "res://resources/tilesets/primordial_tileset.tres"
	const NORMAL_TILESET := "res://resources/tilesets/primordial_tileset_normal.tres"
	## A real baked room, not a fixture: the water hall is the owner's main room and it
	## paints `primordial_tileset` on both of its terrain layers.
	const ROOM_TERRAIN := "res://scenes/rooms/generated/water_hall/terrain.tscn"
	const BAKED_ROOMS_ROOT := "res://scenes/rooms/generated"
	const TILE := 8

	## The tile the owner added last; it must have made it into the normal atlas and
	## into the normal TileSet.
	const NEW_TILE := Vector2i(0, 8)


	func run() -> Array[String]:
		var failures: Array[String] = []
		_assert_png_matches_the_albedo(failures)
		_assert_tileset_mirrors_the_albedo(failures)
		_assert_a_real_room_lights_through_the_tileset(failures)
		_assert_every_baked_room_resolves(failures)
		_assert_a_missing_tileset_falls_back(failures)
		return failures


	## The atlas itself: size, alpha, and one decodable unit normal per opaque pixel.
	func _assert_png_matches_the_albedo(failures: Array[String]) -> void:
		var albedo := _load_png(ALBEDO_PNG)
		if albedo == null:
			failures.append("%s is missing or unreadable" % ALBEDO_PNG)
			return
		var normal := _load_png(NORMAL_PNG)
		if normal == null:
			# The whole feature is a generated asset: without it there is nothing to
			# check, and a silent pass would hide exactly the failure that matters.
			failures.append(
				"%s is missing or unreadable; run `godot --headless --path . -s res://tools/bake_tileset_normals.gd`"
				% NORMAL_PNG
			)
			return
		if normal.get_size() != albedo.get_size():
			failures.append(
				"normal atlas is %s but the albedo is %s" % [normal.get_size(), albedo.get_size()]
			)
			return
		if normal.get_size().x % TILE != 0 or normal.get_size().y % TILE != 0:
			failures.append("normal atlas %s is not a whole number of %d px tiles" % [normal.get_size(), TILE])

		var opaque := 0
		var transparent := 0
		var bad_lengths := 0
		var bad_z := 0
		var bad_flat := 0
		var bad_alpha := 0
		var first_opaque := Vector2i(-1, -1)
		var first_bad := ""
		for y: int in normal.get_size().y:
			for x: int in normal.get_size().x:
				var albedo_pixel := albedo.get_pixel(x, y)
				var normal_pixel := normal.get_pixel(x, y)
				var expected_alpha := 255 if albedo_pixel.a > 0.0 else 0
				if absi(normal_pixel.a8 - expected_alpha) > 0:
					bad_alpha += 1
				if expected_alpha == 0:
					transparent += 1
					# Empty atlas cells must be a no-op in the normal buffer: flat and
					# fully transparent, so the flat clear colour shows through.
					if normal_pixel.a8 != 0 or normal_pixel.r8 != 128 or normal_pixel.g8 != 128 or normal_pixel.b8 != 255:
						bad_flat += 1
						if first_bad.is_empty():
							first_bad = "transparent %s = %s" % [Vector2i(x, y), normal_pixel]
					continue
				opaque += 1
				if first_opaque.x < 0:
					first_opaque = Vector2i(x, y)
				var decoded := Vector3(
					normal_pixel.r * 2.0 - 1.0, normal_pixel.g * 2.0 - 1.0, normal_pixel.b * 2.0 - 1.0
				)
				if absf(decoded.length() - 1.0) >= 0.05:
					bad_lengths += 1
					if first_bad.is_empty():
						first_bad = "opaque %s decodes to length %.3f" % [Vector2i(x, y), decoded.length()]
				elif decoded.z <= 0.0:
					bad_z += 1
					if first_bad.is_empty():
						first_bad = "opaque %s decodes to z %.3f" % [Vector2i(x, y), decoded.z]
		if opaque == 0 or transparent == 0:
			failures.append("normal atlas has %d opaque and %d transparent pixels" % [opaque, transparent])
		if bad_alpha > 0:
			failures.append("%d normal pixels do not carry the albedo's alpha" % bad_alpha)
		if bad_flat > 0:
			failures.append("%d transparent pixels are not the flat normal (%s)" % [bad_flat, first_bad])
		if bad_lengths > 0:
			failures.append("%d opaque pixels are not unit length (%s)" % [bad_lengths, first_bad])
		if bad_z > 0:
			failures.append("%d opaque pixels point into the screen (%s)" % [bad_z, first_bad])

		# The new spike must actually be in the atlas, and it must have relief: a tile
		# that silently stayed flat is what a missing tile looks like in the buffer.
		var spike_opaque := 0
		var spike_relief := 0
		for y: int in TILE:
			for x: int in TILE:
				var pixel := normal.get_pixel(NEW_TILE.x * TILE + x, NEW_TILE.y * TILE + y)
				if pixel.a8 == 0:
					continue
				spike_opaque += 1
				if absi(pixel.r8 - 128) > 2 or absi(pixel.g8 - 128) > 2:
					spike_relief += 1
		if spike_opaque == 0:
			failures.append("the spike tile %s is not in the normal atlas" % NEW_TILE)
		elif spike_relief == 0:
			failures.append("the spike tile %s was baked flat" % NEW_TILE)


	## The TileSet has to be a 1:1 mirror of the albedo's cells, because the layer clone
	## copies `tile_map_data` verbatim.
	func _assert_tileset_mirrors_the_albedo(failures: Array[String]) -> void:
		var albedo := load(ALBEDO_TILESET) as TileSet
		if albedo == null:
			failures.append("%s does not load" % ALBEDO_TILESET)
			return
		var normal := load(NORMAL_TILESET) as TileSet
		if normal == null:
			failures.append("%s does not load (is the normal PNG imported?)" % NORMAL_TILESET)
			return
		var albedo_source := albedo.get_source(0) as TileSetAtlasSource
		var normal_source := normal.get_source(0) as TileSetAtlasSource
		if albedo_source == null or normal_source == null:
			failures.append("the tilesets do not both have an atlas source 0")
			return
		if normal.tile_size != albedo.tile_size:
			failures.append("normal tile_size %s != albedo %s" % [normal.tile_size, albedo.tile_size])
		if normal_source.texture_region_size != albedo_source.texture_region_size:
			failures.append(
				"normal texture_region_size %s != albedo %s"
				% [normal_source.texture_region_size, albedo_source.texture_region_size]
			)
		if normal_source.texture == null:
			failures.append("the normal atlas source has no texture")
		elif normal_source.texture.get_size() != albedo_source.texture.get_size():
			failures.append("the normal atlas texture is not the albedo's size")
		if normal.get_physics_layers_count() != 0:
			failures.append("the normal tileset carries physics layers")

		var missing_tiles: Array[String] = []
		var mismatched_alternatives: Array[String] = []
		for tile_index: int in albedo_source.get_tiles_count():
			var coords := albedo_source.get_tile_id(tile_index)
			if normal_source.get_tile_data(coords, 0) == null:
				missing_tiles.append("%d:%d" % [coords.x, coords.y])
				continue
			var alternatives := albedo_source.get_alternative_tiles_count(coords)
			if normal_source.get_alternative_tiles_count(coords) != alternatives:
				mismatched_alternatives.append(
					"%d:%d has %d alternatives, albedo has %d"
					% [
						coords.x,
						coords.y,
						normal_source.get_alternative_tiles_count(coords),
						alternatives
					]
				)
				continue
			for alternative_index: int in alternatives:
				var alternative := albedo_source.get_alternative_tile_id(coords, alternative_index)
				if normal_source.get_alternative_tile_id(coords, alternative_index) != alternative:
					mismatched_alternatives.append(
						"%d:%d alternative order differs at %d" % [coords.x, coords.y, alternative_index]
					)
					continue
				var from := albedo_source.get_tile_data(coords, alternative)
				var to := normal_source.get_tile_data(coords, alternative)
				if to == null:
					mismatched_alternatives.append(
						"%d:%d/%d is missing" % [coords.x, coords.y, alternative]
					)
					continue
				if to.flip_h != from.flip_h or to.flip_v != from.flip_v or to.transpose != from.transpose:
					mismatched_alternatives.append(
						"%d:%d/%d flags are %s/%s/%s, albedo has %s/%s/%s"
						% [
							coords.x,
							coords.y,
							alternative,
							to.flip_h,
							to.flip_v,
							to.transpose,
							from.flip_h,
							from.flip_v,
							from.transpose
						]
					)
		if not missing_tiles.is_empty():
			failures.append(
				"the normal tileset is missing albedo tiles %s" % ", ".join(missing_tiles)
			)
		if not mismatched_alternatives.is_empty():
			failures.append(
				"the normal tileset does not mirror the albedo's alternatives: %s"
				% "; ".join(mismatched_alternatives)
			)
		# The spike is the newest tile and the one a stale bake would be missing.
		if normal_source.get_tile_data(NEW_TILE, 0) == null:
			failures.append("the normal tileset has no tile at the spike %s" % NEW_TILE)
		if normal_source.get_tiles_count() != albedo_source.get_tiles_count():
			failures.append(
				"the normal tileset has %d tiles, the albedo has %d"
				% [normal_source.get_tiles_count(), albedo_source.get_tiles_count()]
			)


	## The install path: a baked room that has no `NormalTiles` layer of its own still
	## gets an authored map because `normal_tileset` mirrors its solid layer.
	func _assert_a_real_room_lights_through_the_tileset(failures: Array[String]) -> void:
		var terrain := _instantiate_room_terrain()
		if terrain == null:
			failures.append("%s does not load" % ROOM_TERRAIN)
			return
		var root := Node2D.new()
		root.name = "NormalInstallRig"
		add_child(root)
		root.add_child(terrain)
		var solid := _find_layer(terrain, "SolidTiles")
		if solid == null:
			failures.append("%s has no SolidTiles layer" % ROOM_TERRAIN)
			root.free()
			return
		var tileset := load(NORMAL_TILESET) as TileSet
		if tileset == null:
			failures.append("%s does not load" % NORMAL_TILESET)
			root.free()
			return

		var field: Node2D = NORMAL_FIELD.new() as Node2D
		field.set("normal_tileset", tileset)
		root.add_child(field)
		var room: Resource = ROOM_DATA.new()
		room.room_id = "water_hall"
		room.room_size_chunks = Vector2i.ONE
		if not bool(field.call("bind_room_with_origin", room, terrain, Vector2i.ZERO)):
			failures.append("NormalField rejected the water hall room")
		if not bool(field.call("has_normal_map")):
			failures.append("NormalField built no map for a room with a solid layer and a normal tileset")
		if field.call("get_normal_texture") == null:
			failures.append("NormalField exposed no normal texture for the installed map")
		if field.call("get_normal_pixels") != Vector2i(320, 184):
			failures.append("the installed normal buffer is not the room size")
		var clone := field.call("get_buffer_layer") as TileMapLayer
		if clone == null:
			failures.append("the installed map has no cloned layer")
			root.free()
			return
		if clone.tile_set != tileset:
			failures.append("the cloned layer does not use the normal tileset")
		var solid_cells := solid.get_used_cells()
		var back := _find_layer(terrain, "BackTiles")
		var merged := _merged_cells([back, solid])
		var buffered := {}
		for entry: Variant in (field.call("get_buffer_layers") as Array):
			for cell: Vector2i in (entry as TileMapLayer).get_used_cells():
				buffered[cell] = true
		if buffered.size() != merged.size():
			failures.append(
				"the normal buffer has %d cells, the layers it merges have %d unique cells"
				% [buffered.size(), merged.size()]
			)
		# A wall and a background tile may paint the same cell; the wall is what the
		# player sees, so its normal is the one the buffer must carry.
		for cell: Vector2i in solid_cells:
			if clone.get_cell_atlas_coords(cell) != solid.get_cell_atlas_coords(cell):
				failures.append("a wall does not win over the background tile at %s" % str(cell))
				break
		# Every cell of the room has to resolve in the normal tileset: a coordinate or
		# an alternative the baker missed would render as the flat clear colour, i.e. a
		# silent hole in the relief.
		var missing := field.call("get_missing_normal_tiles") as Array
		if not missing.is_empty():
			failures.append(
				"the normal tileset cannot resolve %d room cell(s): %s"
				% [missing.size(), ", ".join(missing.slice(0, 8))]
			)
		var unresolved := 0
		var alternatives_used := {}
		for cell: Vector2i in clone.get_used_cells():
			var coords := clone.get_cell_atlas_coords(cell)
			var alternative := clone.get_cell_alternative_tile(cell)
			alternatives_used[alternative] = int(alternatives_used.get(alternative, 0)) + 1
			var source := tileset.get_source(clone.get_cell_source_id(cell)) as TileSetAtlasSource
			if source == null or source.get_tile_data(coords, alternative) == null:
				unresolved += 1
		if unresolved > 0:
			failures.append("%d instanced room cells have no normal tile" % unresolved)
		if not alternatives_used.has(0):
			failures.append("the room did not use the base alternative, so the mirror was not exercised")
		# The layer clone must never be the owner's node, and the owner's cells must be
		# untouched by the binding.
		if clone == solid:
			failures.append("NormalField cloned the room layer into itself")
		if solid.get_used_cells().size() != solid_cells.size():
			failures.append("the room's own layer changed while building the normals")
		root.free()


	## Every baked room, not only the water hall. The point of the generated atlas is
	## that one `NormalField` with `normal_tileset` lights rooms nobody re-authored, so a
	## room that paints a coordinate the atlas does not mirror has to fail here instead
	## of silently losing its relief the first time the owner walks into it.
	func _assert_every_baked_room_resolves(failures: Array[String]) -> void:
		var tileset := load(NORMAL_TILESET) as TileSet
		if tileset == null:
			failures.append("%s does not load" % NORMAL_TILESET)
			return
		var checked := 0
		var broken: Array[String] = []
		for directory: String in DirAccess.get_directories_at(BAKED_ROOMS_ROOT):
			var terrain_path := "%s/%s/terrain.tscn" % [BAKED_ROOMS_ROOT, directory]
			if not ResourceLoader.exists(terrain_path):
				continue
			var scene := load(terrain_path) as PackedScene
			if scene == null:
				broken.append("%s does not load" % directory)
				continue
			var terrain := scene.instantiate() as Node2D
			var root := Node2D.new()
			root.name = "NormalRoomSweep"
			add_child(root)
			root.add_child(terrain)
			var solid := _find_layer(terrain, "SolidTiles")
			if solid == null or solid.get_used_cells().is_empty() or tileset == null:
				root.free()
				continue
			checked += 1
			var back := _find_layer(terrain, "BackTiles")
			var merged := _merged_cells([back, solid])
			var field: Node2D = NORMAL_FIELD.new() as Node2D
			field.set("normal_tileset", tileset)
			root.add_child(field)
			var room: Resource = ROOM_DATA.new()
			room.room_id = directory
			room.room_size_chunks = Vector2i.ONE
			field.call("bind_room_with_origin", room, terrain, Vector2i.ZERO)
			if not bool(field.call("has_normal_map")):
				broken.append("%s has no normal map" % directory)
			else:
				var buffered := {}
				for entry: Variant in (field.call("get_buffer_layers") as Array):
					for cell: Vector2i in (entry as TileMapLayer).get_used_cells():
						buffered[cell] = true
				if buffered.size() != merged.size():
					broken.append("%s does not clone the same cells" % directory)
				var missing := field.call("get_missing_normal_tiles") as Array
				if not missing.is_empty():
					broken.append("%s misses %s" % [directory, ", ".join(missing.slice(0, 5))])
			root.free()
		if checked == 0:
			failures.append("no baked room with a solid layer was found under %s" % BAKED_ROOMS_ROOT)
		if not broken.is_empty():
			failures.append("baked rooms do not resolve in the normal tileset: %s" % "; ".join(broken))


	## Without a normal TileSet the field keeps today's behaviour: a room with no
	## authored `NormalTiles` layer reports "no map" and the light falls back to the
	## screen-derived normals.
	func _assert_a_missing_tileset_falls_back(failures: Array[String]) -> void:
		var terrain := _instantiate_room_terrain()
		if terrain == null:
			failures.append("%s does not load" % ROOM_TERRAIN)
			return
		var root := Node2D.new()
		root.name = "NormalFallbackRig"
		add_child(root)
		root.add_child(terrain)
		var field: Node2D = NORMAL_FIELD.new() as Node2D
		root.add_child(field)
		var room: Resource = ROOM_DATA.new()
		room.room_id = "water_hall"
		room.room_size_chunks = Vector2i.ONE
		field.call("bind_room_with_origin", room, terrain, Vector2i.ZERO)
		if bool(field.call("has_normal_map")):
			failures.append("NormalField invented a map without a normal tileset and without NormalTiles")
		root.free()


	func _instantiate_room_terrain() -> Node2D:
		var scene := load(ROOM_TERRAIN) as PackedScene
		if scene == null:
			return null
		return scene.instantiate() as Node2D


	func _find_layer(node: Node, wanted: String) -> TileMapLayer:
		for child: Node in node.get_children():
			if child is TileMapLayer and (child as TileMapLayer).name == wanted:
				return child as TileMapLayer
			var found := _find_layer(child, wanted)
			if found != null:
				return found
		return null


	## Cells a normal buffer is built from: the listed layers merged in draw order, a
	## later layer winning where two paint the same cell (`null` entries are skipped).
	## The background tiles carry normals too, so the buffer is a merge, not a copy.
	func _merged_cells(layers: Array) -> Dictionary:
		var merged := {}
		for entry: Variant in layers:
			var layer := entry as TileMapLayer
			if layer == null:
				continue
			for cell: Vector2i in layer.get_used_cells():
				merged[cell] = layer.get_cell_atlas_coords(cell)
		return merged


	## Reads the PNG bytes, not the imported texture: the bake has to be judged on the
	## file it writes, and an import pass may filter or edge-fix what it caches.
	func _load_png(path: String) -> Image:
		var bytes := FileAccess.get_file_as_bytes(path)
		if bytes.is_empty():
			return null
		var image := Image.new()
		if image.load_png_from_buffer(bytes) != OK:
			return null
		image.convert(Image.FORMAT_RGBA8)
		return image


## tests/world/test_blue_noise.gd
class BlueNoiseCase extends Node:
	## Runtime guard for the 64x64 blue-noise threshold tile the gas/mist layer dithers with.
	##
	## WHY this test exists
	## The mist used to quantise its opacity with a 4x4 ordered (Bayer) dither, which
	## repeats a tiny lattice: at low coverage the lit texels fall on a regular 4 px grid
	## and the faint mist reads as a "screen door" of dots. resources/textures/
	## blue_noise_64.png replaces that lattice with a void-and-cluster blue-noise
	## threshold map (baked by tools/bake_blue_noise.gd, which prints the full
	## quality report). A printed report does not fail a build, so this test is what stops
	## a re-baked, edited or re-exported tile from silently bringing the lattice back.
	##
	## What is asserted, with the value the committed tile measures:
	##   * 64x64 with all 4096 samples present, and every one of the 256 byte values used
	##     at least once, so a faint mist gets thresholds at both ends of the range
	##     instead of a gap at level 0;
	##   * a uniform histogram over 64 bins of 4 byte levels (measured 57..65 texels per
	##     bin against 64 expected; the two end bins are short by 7 because 4096 ranks do
	##     not divide evenly onto 256 levels);
	##   * no column and no row leans bright or dark: measured 552 and 466 rank units
	##     between the darkest and the brightest line mean;
	##   * no energy at the lattice an ordered 4x4 dither peaks on: the period-2 family
	##     holds 0.094% of the energy where the tiled Bayer holds 94.1%, the period-4
	##     family 0.002% against 1.2%;
	##   * the radial spectrum is "blue": everything below 4 cycles per tile holds 0.0001%
	##     of the energy, and the share rises monotonically with frequency (that gap is
	##     the property that stops a faint mist from showing large-scale blotches);
	##   * dispersion: at 25% coverage the mean toroidal nearest-neighbour distance is
	##     1.42x the white-noise expectation, i.e. the level set is a dispersed dot
	##     pattern rather than a random scatter.
	##
	## Everything here is computed straight from the PNG bytes, with toroidal distances
	## and DFT bins of the 64x64 tile, so it measures the artifact the shader samples
	## rather than this project's copy of the bake maths.

	const TEXTURE_PATH := "res://resources/textures/blue_noise_64.png"
	const SIZE := 64
	const TILE_MASK := SIZE - 1
	const TILE_SHIFT := 6
	const CELL_COUNT := SIZE * SIZE
	const BIN_COUNT := 64
	const BIN_SHIFT := 2
	## A perfectly uniform map is exactly CELL_COUNT / BIN_COUNT per bin; the baked tile
	## lands within 7 of that because 4096 ranks do not divide evenly onto 256 levels.
	const BIN_TOLERANCE := 8
	## Rank units (0..4095) between the darkest and the brightest column or row mean.
	## Measured 552 (columns) and 466 (rows). A random permutation already spreads
	## ~520-760 here, so the guard cannot be much tighter, but a real axis bias (the
	## failure this guards) overshoots it by an order of magnitude.
	const MAX_LINE_SPREAD_RANKS := 800.0
	## The 4x4 Bayer matrix the tile replaces; the same 16 values the gas shader uses.
	const BAYER_4X4: Array[int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
	## Ordered-dither families: (kx, ky) bins of the 64x64 tile. Period 2 along one axis
	## is bin 32 on that axis, period 4 is bin 16, and (32, 32) is the 1 px checkerboard
	## that a tiled 4x4 Bayer is 75% made of.
	const PERIOD2_BINS: Array[Vector2i] = [Vector2i(32, 0), Vector2i(0, 32), Vector2i(32, 32)]
	const PERIOD4_BINS: Array[Vector2i] = [Vector2i(16, 0), Vector2i(0, 16)]
	## The tile must be far below the ordered dither at those bins, and the families must
	## also be small in absolute terms. Measured 0.094% / 0.0019% against 94% / 1.2%,
	## i.e. ratios of ~1000x and ~600x: the guards keep an order of magnitude of margin.
	const MIN_LATTICE_RATIO := 20.0
	const MAX_PERIOD2_SHARE := 0.01
	const MAX_PERIOD4_SHARE := 0.005
	## Share of the energy in the bins below 4 cycles per tile (45 bins around DC).
	## Measured 0.0001% (1e-6), so this guard is 100x above the committed tile and still
	## orders of magnitude below a blotchy, low-frequency tile.
	const MAX_LOW_RING_SHARE := 0.0001
	## Dispersion at 25% coverage, in units of the white-noise expectation
	## 1 / (2 * sqrt(density)) = 1.0 cells. Measured 1.42x; the guard sits just under the
	## 1.4x target so the committed tile keeps its margin while a white-noise-like tile
	## (1.0-1.2x) still fails.
	const DISPERSION_COVERAGE := 0.25
	const MIN_DISPERSION_RATIO := 1.35

	var _bytes := PackedByteArray()
	var _cos_table := PackedFloat64Array()
	var _sin_table := PackedFloat64Array()


	func run() -> Array[String]:
		var failures: Array[String] = []
		if not _load_bytes(failures):
			return failures
		_build_trig_tables()
		_assert_size(failures)
		_assert_histogram(failures)
		_assert_every_value_used(failures)
		_assert_line_balance(failures)
		_assert_lattice_families(failures)
		_assert_radial_spectrum(failures)
		_assert_dispersion(failures)
		return failures


	## Load the texture the way the game does, then reduce it to one byte per texel.
	##
	## The import pipeline decides the stored format (L8, RGB8 or RGBA8 depending on the
	## importer settings), so the image is converted to L8 first: for a greyscale tile the
	## conversion is the identity, and it keeps the checks below independent of the
	## importer's channel packing.
	func _load_bytes(failures: Array[String]) -> bool:
		if not ResourceLoader.exists(TEXTURE_PATH):
			failures.append("blue noise tile is missing: %s (bake it with tools/bake_blue_noise.gd)" % TEXTURE_PATH)
			return false
		var texture := load(TEXTURE_PATH) as Texture2D
		if texture == null:
			failures.append("blue noise tile does not load as a Texture2D: %s" % TEXTURE_PATH)
			return false
		var image := texture.get_image()
		if image == null:
			failures.append("blue noise tile has no image data (imported with a compressed format?): %s" % TEXTURE_PATH)
			return false
		if image.get_format() != Image.FORMAT_L8:
			image.convert(Image.FORMAT_L8)
		_bytes = image.get_data()
		return true


	func _assert_size(failures: Array[String]) -> void:
		if _bytes.size() != CELL_COUNT:
			failures.append("blue noise tile is %d bytes, want %d (a %dx%d L8 image)" % [
				_bytes.size(), CELL_COUNT, SIZE, SIZE
			])


	## The threshold map has to be uniform, or the dither bands: a crowded level means the
	## mist steps through that opacity range too fast, an empty one means it sticks.
	func _assert_histogram(failures: Array[String]) -> void:
		if _bytes.size() != CELL_COUNT:
			return
		var counts := PackedInt32Array()
		counts.resize(BIN_COUNT)
		counts.fill(0)
		for cell: int in CELL_COUNT:
			counts[_bytes[cell] >> BIN_SHIFT] += 1
		var expected := int(CELL_COUNT / float(BIN_COUNT))
		for bin: int in BIN_COUNT:
			if absi(counts[bin] - expected) > BIN_TOLERANCE:
				failures.append(
					"blue noise histogram bin %d (byte levels %d..%d) holds %d texels, want %d +-%d"
					% [
						bin, bin << BIN_SHIFT, ((bin + 1) << BIN_SHIFT) - 1,
						counts[bin], expected, BIN_TOLERANCE
					]
				)


	## Every byte value must appear: the dither drives the 4 px Bayer tile from this map,
	## so a missing low value means the faintest mist level has no texels to light and the
	## first visible step of opacity jumps.
	func _assert_every_value_used(failures: Array[String]) -> void:
		if _bytes.size() != CELL_COUNT:
			return
		var used := PackedByteArray()
		used.resize(256)
		used.fill(0)
		for cell: int in CELL_COUNT:
			used[_bytes[cell]] = 1
		var missing := 0
		var first_missing := -1
		for value: int in 256:
			if used[value] == 0:
				missing += 1
				if first_missing < 0:
					first_missing = value
		if missing > 0:
			failures.append("blue noise tile never uses %d of the 256 byte values (first: %d)" % [
				missing, first_missing
			])


	## A column or row whose thresholds are systematically low lights up earlier than its
	## neighbours, which is a screen-space stripe once the tile repeats every 64 px.
	func _assert_line_balance(failures: Array[String]) -> void:
		if _bytes.size() != CELL_COUNT:
			return
		var columns := PackedFloat64Array()
		var rows := PackedFloat64Array()
		columns.resize(SIZE)
		rows.resize(SIZE)
		columns.fill(0.0)
		rows.fill(0.0)
		for cell: int in CELL_COUNT:
			var value := float(_bytes[cell])
			columns[cell & TILE_MASK] += value
			rows[cell >> TILE_SHIFT] += value
		var to_ranks := 4095.0 / (255.0 * float(SIZE))
		var column_spread := _spread(columns) * to_ranks
		var row_spread := _spread(rows) * to_ranks
		if column_spread > MAX_LINE_SPREAD_RANKS:
			failures.append(
				"blue noise column means spread %.0f rank units (limit %.0f): a vertical stripe"
				% [column_spread, MAX_LINE_SPREAD_RANKS]
			)
		if row_spread > MAX_LINE_SPREAD_RANKS:
			failures.append(
				"blue noise row means spread %.0f rank units (limit %.0f): a horizontal stripe"
				% [row_spread, MAX_LINE_SPREAD_RANKS]
			)


	## The 4x4 ordered dither peaks on the period-2 and period-4 bins of a 64x64 tile. The
	## baked tile must put essentially nothing there, and the comparison to the tiled Bayer
	## matrix is what makes that quantitative instead of a vibe.
	func _assert_lattice_families(failures: Array[String]) -> void:
		if _bytes.size() != CELL_COUNT:
			return
		var tile := _signal_from_bytes()
		var bayer := _signal_from_bayer()
		var tile_total := _total_energy(tile)
		var bayer_total := _total_energy(bayer)
		if tile_total <= 0.0 or bayer_total <= 0.0:
			failures.append("blue noise spectrum is empty, so the lattice check proves nothing")
			return
		var tile_period2 := _family_share(tile, tile_total, PERIOD2_BINS)
		var bayer_period2 := _family_share(bayer, bayer_total, PERIOD2_BINS)
		var tile_period4 := _family_share(tile, tile_total, PERIOD4_BINS)
		var bayer_period4 := _family_share(bayer, bayer_total, PERIOD4_BINS)
		if tile_period2 > MAX_PERIOD2_SHARE:
			failures.append(
				"blue noise puts %.4f%% of its energy on the period-2 lattice (limit %.2f%%, the bayer tile puts %.2f%%)"
				% [100.0 * tile_period2, 100.0 * MAX_PERIOD2_SHARE, 100.0 * bayer_period2]
			)
		if tile_period4 > MAX_PERIOD4_SHARE:
			failures.append(
				"blue noise puts %.4f%% of its energy on the period-4 lattice (limit %.2f%%, the bayer tile puts %.2f%%)"
				% [100.0 * tile_period4, 100.0 * MAX_PERIOD4_SHARE, 100.0 * bayer_period4]
			)
		var period2_ratio := bayer_period2 / maxf(tile_period2, 1.0e-12)
		if period2_ratio < MIN_LATTICE_RATIO:
			failures.append(
				"period-2 lattice energy is only %.1fx below the ordered 4x4 dither (want %.0fx): the dot grid is back"
				% [period2_ratio, MIN_LATTICE_RATIO]
			)
		var period4_ratio := bayer_period4 / maxf(tile_period4, 1.0e-12)
		if period4_ratio < MIN_LATTICE_RATIO:
			failures.append(
				"period-4 lattice energy is only %.1fx below the ordered 4x4 dither (want %.0fx): the dot grid is back"
				% [period4_ratio, MIN_LATTICE_RATIO]
			)


	## The "blue" property: a spectral gap at low frequencies and energy that rises with
	## frequency. This is the check that catches a blotchy tile, which is the other way a
	## replacement tile can look wrong under a faint mist.
	func _assert_radial_spectrum(failures: Array[String]) -> void:
		if _bytes.size() != CELL_COUNT:
			return
		var tile := _signal_from_bytes()
		var total := _total_energy(tile)
		if total <= 0.0:
			failures.append("blue noise spectrum is empty, so the radial check proves nothing")
			return
		var low_share := _disc_share(tile, total, 4)
		if low_share > MAX_LOW_RING_SHARE:
			failures.append(
				"blue noise keeps %.4f%% of its energy below 4 cycles per tile (limit %.4f%%): large-scale blotches"
				% [100.0 * low_share, 100.0 * MAX_LOW_RING_SHARE]
			)
		# Rings of 8 cycles; the share has to climb, because a blue-noise tile puts its
		# energy in the high frequencies and a white-noise tile would be flat.
		var previous := -1.0
		for start: int in [0, 8, 16, 24]:
			var share := _ring_share(tile, total, start, start + 8)
			if previous >= 0.0 and share <= previous:
				failures.append(
					"blue noise radial spectrum does not rise: %.4f%% at %d-%d cycles, %.4f%% below it"
					% [100.0 * share, start, start + 8, 100.0 * previous]
				)
			previous = share


	## Toroidal dispersion at the 25% coverage level: the mean nearest-neighbour distance
	## of the lit cells, compared with the white-noise expectation for that density.
	##
	## This is the property an ordered dither also has (a Bayer tile is very uniformly
	## spaced!) and white noise does not: it says the level set is a dispersed dot pattern.
	## The expectation used is the textbook one for a random point process, 1/(2*sqrt(λ)),
	## not a shuffled set of cells: on this discrete grid even white noise has plenty of
	## distance-1 pairs, so a shuffle reads 1.20 instead of 1.00 and would make the ratio
	## look worse than the property is.
	func _assert_dispersion(failures: Array[String]) -> void:
		if _bytes.size() != CELL_COUNT:
			return
		var sorted := _bytes.duplicate()
		sorted.sort()
		var count := roundi(DISPERSION_COVERAGE * float(CELL_COUNT))
		var threshold := sorted[count - 1]
		var cells := PackedInt32Array()
		for cell: int in CELL_COUNT:
			if _bytes[cell] <= threshold:
				cells.append(cell)
		if cells.size() < (count >> 1):
			failures.append("blue noise level set at 25%% is empty, so dispersion cannot be measured")
			return
		var mean := _nearest_neighbour_mean(cells)
		var density := float(cells.size()) / float(CELL_COUNT)
		var poisson := 1.0 / (2.0 * sqrt(density))
		if mean < MIN_DISPERSION_RATIO * poisson:
			failures.append(
				"blue noise nearest-neighbour distance at 25%% coverage is %.3f cells (%.2fx the white-noise expectation), want %.2fx: the level set is not dispersed"
				% [mean, mean / poisson, MIN_DISPERSION_RATIO]
			)


	# ----------------------------------------------------------------------------- signals

	## The tile as a zero-mean signal in [-0.5, 0.5]. Removing the mean puts the DC bin at
	## zero so every share below is structure, and the scale matches the bake tool's.
	func _signal_from_bytes() -> PackedFloat64Array:
		var samples := PackedFloat64Array()
		samples.resize(CELL_COUNT)
		var mean := 0.0
		for cell: int in CELL_COUNT:
			samples[cell] = float(_bytes[cell]) / 255.0
			mean += samples[cell]
		mean /= float(CELL_COUNT)
		for cell: int in CELL_COUNT:
			samples[cell] -= mean
		return samples


	## The 4x4 Bayer matrix tiled over the whole 64x64 tile, zero mean, so the ordered
	## dither's spectrum is measured with exactly the same code as the blue-noise tile's.
	func _signal_from_bayer() -> PackedFloat64Array:
		var samples := PackedFloat64Array()
		samples.resize(CELL_COUNT)
		var mean := 0.0
		for y: int in SIZE:
			for x: int in SIZE:
				var threshold := BAYER_4X4[(y & 3) * 4 + (x & 3)]
				samples[y * SIZE + x] = (float(threshold) + 0.5) / 16.0
				mean += samples[y * SIZE + x]
		mean /= float(CELL_COUNT)
		for cell: int in CELL_COUNT:
			samples[cell] -= mean
		return samples


	func _build_trig_tables() -> void:
		_cos_table.resize(SIZE)
		_sin_table.resize(SIZE)
		for phase: int in SIZE:
			var angle := TAU * float(phase) / float(SIZE)
			_cos_table[phase] = cos(angle)
			_sin_table[phase] = sin(angle)


	## Total spectral energy of a real signal. Parseval: the sum over all 4096 bins equals
	## the sample count times the sum of squares, so the total needs no transform at all.
	func _total_energy(samples: PackedFloat64Array) -> float:
		var total := 0.0
		for cell: int in CELL_COUNT:
			total += samples[cell] * samples[cell]
		return total * float(CELL_COUNT)


	## Energy of a single DFT bin, |F(kx, ky)|^2.
	##
	## Only the bins this test asks about are transformed, and the phase of e^{-i...}
	## depends on (kx * x + ky * y) mod 64 alone, so one 64-entry trig table and one
	## multiply-add per sample is enough: a few hundred thousand operations instead of a
	## full FFT, which is what keeps this test cheap enough for the headless suite.
	func _bin_energy(samples: PackedFloat64Array, frequency: Vector2i) -> float:
		var real := 0.0
		var imaginary := 0.0
		for y: int in SIZE:
			var row := y * SIZE
			for x: int in SIZE:
				var phase := (frequency.x * x + frequency.y * y) & TILE_MASK
				var value := samples[row + x]
				real += value * _cos_table[phase]
				imaginary -= value * _sin_table[phase]
		return real * real + imaginary * imaginary


	## Share of the total energy carried by the conjugate pair of `frequency`. A real
	## signal always carries the same energy at (kx, ky) and (-kx, -ky), so a peak's real
	## weight is the sum of both; the four self-conjugate bins are counted once.
	func _pair_share(samples: PackedFloat64Array, total: float, frequency: Vector2i) -> float:
		var energy := _bin_energy(samples, frequency)
		var mirror := Vector2i((SIZE - frequency.x) % SIZE, (SIZE - frequency.y) % SIZE)
		if mirror != frequency:
			energy += _bin_energy(samples, mirror)
		return energy / total


	func _family_share(samples: PackedFloat64Array, total: float, bins: Array[Vector2i]) -> float:
		var share := 0.0
		for frequency: Vector2i in bins:
			share += _pair_share(samples, total, frequency)
		return share


	## Share of the energy inside the disc of bins whose frequency magnitude is below
	## `limit` cycles per tile. Only the low disc is needed here, so the transform is only
	## evaluated there (and every bin appears once, mirrors included as their own bins).
	func _disc_share(samples: PackedFloat64Array, total: float, limit: int) -> float:
		var energy := 0.0
		var limit_squared := limit * limit
		for frequency_y: int in range(-limit + 1, limit):
			for frequency_x: int in range(-limit + 1, limit):
				if frequency_x * frequency_x + frequency_y * frequency_y >= limit_squared:
					continue
				var frequency := Vector2i(frequency_x & TILE_MASK, frequency_y & TILE_MASK)
				energy += _bin_energy(samples, frequency)
		return energy / total


	## Share of the energy in the radial ring between two frequency magnitudes.
	func _ring_share(samples: PackedFloat64Array, total: float, start: int, end: int) -> float:
		var energy := 0.0
		for frequency_y: int in range(-end + 1, end):
			for frequency_x: int in range(-end + 1, end):
				var radius_squared := frequency_x * frequency_x + frequency_y * frequency_y
				if radius_squared < start * start or radius_squared >= end * end:
					continue
				var frequency := Vector2i(frequency_x & TILE_MASK, frequency_y & TILE_MASK)
				energy += _bin_energy(samples, frequency)
		return energy / total


	# ----------------------------------------------------------------------------- geometry

	## Mean toroidal nearest-neighbour distance over a set of cells.
	##
	## The search walks outwards in Chebyshev rings; after ring r every unvisited cell is
	## at least r + 1 away, so the walk stops as soon as a hit is within that bound. That
	## keeps a 1000-cell set to a few dozen lookups per cell while still being exact.
	func _nearest_neighbour_mean(cells: PackedInt32Array) -> float:
		var count := cells.size()
		if count < 2:
			return 0.0
		var mask := PackedByteArray()
		mask.resize(CELL_COUNT)
		mask.fill(0)
		for index: int in count:
			mask[cells[index]] = 1
		var total := 0.0
		for index: int in count:
			var cell := cells[index]
			var cx := cell & TILE_MASK
			var cy := cell >> TILE_SHIFT
			var best_squared := INF
			var radius := 1
			while radius <= (SIZE >> 1):
				for offset_y: int in range(-radius, radius + 1):
					var row := ((cy + offset_y + SIZE) & TILE_MASK) * SIZE
					if absi(offset_y) != radius:
						# Only the two x ends of this row lie on the ring.
						for offset_x: int in range(-radius, radius + 1, 2 * radius):
							var column := (cx + offset_x + SIZE) & TILE_MASK
							if mask[row + column] != 0:
								best_squared = minf(best_squared, float(offset_x * offset_x + offset_y * offset_y))
					else:
						for offset_x: int in range(-radius, radius + 1):
							var column := (cx + offset_x + SIZE) & TILE_MASK
							if mask[row + column] != 0:
								best_squared = minf(best_squared, float(offset_x * offset_x + offset_y * offset_y))
				if best_squared <= float((radius + 1) * (radius + 1)):
					break
				radius += 1
			total += sqrt(best_squared)
		return total / float(count)


	func _spread(values: PackedFloat64Array) -> float:
		var lowest := INF
		var highest := -INF
		for value: float in values:
			lowest = minf(lowest, value)
			highest = maxf(highest, value)
		return highest - lowest


func run() -> Array[String]:
	var failures: Array[String] = []
	failures.append_array(_run_case(TilesetTerrainCase.new()))
	failures.append_array(_run_case(TilesetNormalsCase.new()))
	failures.append_array(_run_case(BlueNoiseCase.new()))
	return failures


func _run_case(test: Node) -> Array[String]:
	add_child(test)
	var result: Array = test.call("run")
	test.queue_free()
	var failures: Array[String] = []
	failures.assign(result)
	return failures
