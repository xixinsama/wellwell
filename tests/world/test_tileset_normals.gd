extends Node

## The authored normal atlas of `primordial_tileset.png`, and the way NormalField
## installs it into rooms that never authored normals themselves.
##
## The PNG and its TileSet are generated (`scripts/tools/bake_tileset_normals.gd`),
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

const NORMAL_FIELD: Script = preload("res://scripts/world/normal_field.gd")
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
			"%s is missing or unreadable; run `godot --headless --path . -s res://scripts/tools/bake_tileset_normals.gd`"
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
