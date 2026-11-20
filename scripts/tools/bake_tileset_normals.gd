extends SceneTree

## Bakes the authored normal atlas and its TileSet from the albedo tileset.
##
## Run headless, from the project root:
##
##     godot --headless --path . -s res://scripts/tools/bake_tileset_normals.gd
##
## The tool is re-runnable and idempotent: it reads
## `assets/images/primordial_tileset.png`, derives one normal per pixel, writes
## `assets/images/primordial_tileset_normal.png`, then rebuilds
## `resources/tilesets/primordial_tileset_normal.tres` from the *structure* of the
## owner's `resources/tilesets/primordial_tileset.tres` (same atlas coordinates,
## same alternative tiles in the same order, same flip_h/flip_v/transpose flags).
## A tile added to the albedo tileset (like the spike at (0,8)) is picked up
## automatically; nothing here is per-tile.
##
## ## Height model
##
## The art is beveled pixel blocks: a bright pixel is a raised pixel, so the
## albedo's luminance is the surface height. That alone would render every slope
## and every thin ledge as a flat cutout, because inside one tile a slope's face
## has one constant colour. So the silhouette is turned into a bevel: the height
## field drops `SILHOUETTE_BEVEL_DEPTH` into the transparent pixels of the tile, so
## the opaque pixels just inside the outline slope down towards the gap and ledges,
## slopes, vines and the new two-pronged spike read as rounded edges instead of
## cutouts. The same field is then smoothed once and differentiated with a central
## difference.
##
## No cross-tile data is used, on purpose: a tile must render identically however
## it is placed, so the height field of a tile is a pure function of that tile's
## pixels. Outside the tile the field is **periodic**: the neighbours of the edge
## pixels are the tile's own opposite edge. A tileset is authored to tile with
## itself, so this is exactly the field the art will be seen in, and it is what
## keeps the normals continuous across a wall of identical blocks. Replicating the
## edge instead would leave a one-pixel discontinuity at every seam (the art is not
## symmetric, so "my edge value" is not "my neighbour's edge value"), which reads as
## a grid over every wall.
##
## ## Encoding and mirroring
##
## RGB is the normal encoded as `n * 0.5 + 0.5` (r = x, g = y, b = z, flat =
## (128, 128, 255)), alpha is the albedo's alpha, so the empty cells of the atlas
## stay flat and transparent and the normal buffer's flat clear colour shows
## through them.
##
## Alternative tiles are mirrored by the renderer: Godot flips the *region*, it
## does not negate the normal's x/y. Godot 4.7's `TileData` has no
## `texture_region` property (checked with `get_property_list()`; the only region
## API is `TileSetAtlasSource.get_tile_texture_region()`, which is derived from the
## atlas coordinates and the flip flags), so an alternative cannot point at a
## second slot of the sheet that holds the correctly negated normal. The fallback
## documented in `docs/lighting.md` is therefore in effect: the alternatives keep
## the albedo's flags and the sheet keeps the albedo's layout, which means a
## `flip_h` alternative shows the mirrored *position* with an un-negated x. That
## is a real limitation; it is invisible on the symmetric blocks the alternatives
## are used for, and the alternative tiles of this tileset are corner/edge
## variants whose relief is dominated by the silhouette bevel, not by the sign.

const ALBEDO_PNG := "res://assets/images/primordial_tileset.png"
const ALBEDO_TILESET := "res://resources/tilesets/primordial_tileset.tres"
const NORMAL_PNG := "res://assets/images/primordial_tileset_normal.png"
const NORMAL_TILESET := "res://resources/tilesets/primordial_tileset_normal.tres"
const TILE_SIZE := 8

## Treat the albedo's luminance as surface height. Turning this off bakes a pure
## silhouette (alpha-only) relief, which loses every internal edge (bricks, cracks,
## the spike's own facet) and keeps only the outline.
const HEIGHT_FROM_LUMINANCE := true
## How many pixels the surface takes to fall into a gap, i.e. the width of the
## rounded rim. 1 keeps the bevel as crisp as the art: one pixel from an opaque
## pixel to the gap floor.
const SILHOUETTE_BEVEL_PX := 1
## How far the gap floor sits below the edge it touches, in height units (0.18 is
## about 46 of 255 luminance levels: a lip you can see, small enough not to swallow
## the art's own shading). This is what turns a ledge or a spike into a rounded
## edge instead of a cutout, and it is measured against the *surface*, never
## against zero, so the rim is the same depth on a bright tile and on a dark one.
const SILHOUETTE_BEVEL_DEPTH := 0.18
## How many 3x3 gaussian passes smooth the height before differentiation. Pixel art
## has 1 px edges; differentiating the raw height would produce a knife edge on
## every border pixel, one pass turns each of them into a two-pixel ramp.
const SMOOTHING := 1
## The `1 / strength` term of the normal's z: bigger is flatter. Tuned against the
## shade pass, whose relief is `ndl * relief_strength * mask` and only bites where
## the light map is neither black nor saturated. At 20 the art's 1 px edges (a
## 33/255 luminance step) land at 20-45 degrees and the silhouette rims at 45-70,
## which is steep enough to move a pixel and shallow enough not to turn the brick
## pattern into a knife edge; the measured result is in `docs/lighting.md`.
const STRENGTH := 20.0
## Luminance weights, the same ones the shade shader uses for its derived normals,
## so an authored normal and a derived one agree on what "bright" means.
const LUMINANCE := Vector3(0.3, 0.59, 0.11)
## Flat normal written into every pixel the albedo leaves transparent. Written as
## the 8-bit encoding of (0, 0, 1) rather than as Color(0.5, 0.5, 1.0): 0.5 would
## truncate to 127 and decode back to -0.004 instead of exactly 0.
const FLAT := Color(128.0 / 255.0, 128.0 / 255.0, 1.0, 0.0)


func _init() -> void:
	var failures := _bake()
	for failure: String in failures:
		push_error("bake_tileset_normals: %s" % failure)
	quit(0 if failures.is_empty() else 1)


func _bake() -> Array[String]:
	var failures: Array[String] = []
	var albedo := _load_albedo()
	if albedo == null:
		failures.append("could not read %s" % ALBEDO_PNG)
		return failures
	var albedo_tileset := load(ALBEDO_TILESET) as TileSet
	if albedo_tileset == null:
		failures.append("could not load %s" % ALBEDO_TILESET)
		return failures

	var normal_image := _bake_image(albedo)
	var changed := _write_png(normal_image)

	var texture := _ensure_imported()
	if texture == null:
		failures.append(
			"%s is not imported; run the editor once (or `godot --headless --path . --import`)"
			% NORMAL_PNG
		)
		return failures

	var tileset := _build_tileset(albedo_tileset, texture, failures)
	if tileset == null:
		return failures
	_save_tileset(tileset)
	if changed:
		print("bake_tileset_normals: wrote %s and %s" % [NORMAL_PNG, NORMAL_TILESET])
	else:
		print("bake_tileset_normals: %s and %s are up to date" % [NORMAL_PNG, NORMAL_TILESET])
	return failures


## Reads the raw PNG bytes instead of the imported texture: the bake must describe
## the file the owner painted, not a cached, filter-processed copy of it.
func _load_albedo() -> Image:
	var bytes := FileAccess.get_file_as_bytes(ALBEDO_PNG)
	if bytes.is_empty():
		return null
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image


## One normal per pixel of the whole sheet, tile by tile.
func _bake_image(albedo: Image) -> Image:
	var size := albedo.get_size()
	var output := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	output.fill(FLAT)
	var tiles := size / TILE_SIZE
	for tile_y: int in tiles.y:
		for tile_x: int in tiles.x:
			var origin := Vector2i(tile_x * TILE_SIZE, tile_y * TILE_SIZE)
			if _bake_tile(albedo, origin, output):
				print("  tile %d:%d" % [tile_x, tile_y])
	return output


## Bakes one tile in place and returns whether it had any opaque pixel at all.
func _bake_tile(albedo: Image, origin: Vector2i, output: Image) -> bool:
	var count := TILE_SIZE * TILE_SIZE
	var alpha := PackedByteArray()
	var height := PackedFloat32Array()
	alpha.resize(count)
	height.resize(count)
	var opaque := false
	for y: int in TILE_SIZE:
		for x: int in TILE_SIZE:
			var index := y * TILE_SIZE + x
			var colour := albedo.get_pixel(origin.x + x, origin.y + y)
			var is_opaque := colour.a > 0.0
			alpha[index] = 255 if is_opaque else 0
			if not is_opaque:
				height[index] = 0.0
				continue
			opaque = true
			if HEIGHT_FROM_LUMINANCE:
				var luminance := colour.r * LUMINANCE.x + colour.g * LUMINANCE.y + colour.b * LUMINANCE.z
				height[index] = clampf(luminance, 0.0, 1.0)
			else:
				height[index] = 1.0
	if not opaque:
		return false

	# The two passes return the new height field instead of mutating in place, so the
	# order (bevel, then smooth, then differentiate) is what the code reads like.
	height = _apply_silhouette_bevel(alpha, height)
	for _pass: int in SMOOTHING:
		height = _smooth(height)

	for y: int in TILE_SIZE:
		for x: int in TILE_SIZE:
			var index := y * TILE_SIZE + x
			if alpha[index] == 0:
				output.set_pixel(origin.x + x, origin.y + y, FLAT)
				continue
			var step_x := (height[_index(_wrap(x + 1), y)] - height[_index(_wrap(x - 1), y)]) * 0.5
			var step_y := (height[_index(x, _wrap(y + 1))] - height[_index(x, _wrap(y - 1))]) * 0.5
			var normal := Vector3(-step_x, -step_y, 1.0 / STRENGTH).normalized()
			output.set_pixel(
				origin.x + x,
				origin.y + y,
				Color(_encode(normal.x), _encode(normal.y), _encode(normal.z), 1.0)
			)
	return true


func _index(x: int, y: int) -> int:
	return y * TILE_SIZE + x


## Neighbour coordinate in the periodic (tiling) height field.
func _wrap(value: int) -> int:
	return posmod(value, TILE_SIZE)


## Quantizes one normal component to 8 bit exactly the way the shader decodes it
## (`encoded * 2 - 1`), so the baked normal stays unit length as closely as the
## format allows instead of drifting by a truncated last bit.
func _encode(component: float) -> float:
	return float(roundi(clampf(component * 0.5 + 0.5, 0.0, 1.0) * 255.0)) / 255.0


## Rounds the silhouette: every transparent pixel gets a height one bevel below the
## surface it borders, so the pixels just inside the outline slope down into the gap
## and ledges, slopes, vines and the spike read as rounded edges instead of cutouts.
##
## The bevel is measured against the neighbouring *surface* height, not against an
## absolute zero: a flat 255 tile and a flat 35 tile get the same rim, and the rim
## depth no longer depends on how bright the tile is. A gap wider than the bevel has
## a flat floor, which is correct: only the pixels next to the outline are visible
## art, and their slope is what reads as a round edge.
##
## A pixel on the tile's outer border is only beveled when the tile itself has a
## transparent neighbour there: a block that fills its tile is a block that
## continues into the next one, so it must not get a rim along the seam.
func _apply_silhouette_bevel(
	alpha: PackedByteArray, height: PackedFloat32Array
) -> PackedFloat32Array:
	var beveled := height.duplicate()
	if SILHOUETTE_BEVEL_PX <= 0 or SILHOUETTE_BEVEL_DEPTH <= 0.0:
		return beveled
	for y: int in TILE_SIZE:
		for x: int in TILE_SIZE:
			var index := _index(x, y)
			if alpha[index] != 0:
				continue
			var nearest := TILE_SIZE * 2
			var nearest_height := 0.0
			for other_y: int in TILE_SIZE:
				for other_x: int in TILE_SIZE:
					if alpha[_index(other_x, other_y)] == 0:
						continue
					var distance := maxi(absi(other_x - x), absi(other_y - y))
					if distance >= nearest:
						continue
					nearest = distance
					nearest_height = height[_index(other_x, other_y)]
			if nearest > TILE_SIZE:
				# A tile with no opaque pixel at all: nothing to bevel against.
				continue
			var fall := mini(nearest, SILHOUETTE_BEVEL_PX) * SILHOUETTE_BEVEL_DEPTH
			beveled[index] = nearest_height - fall
	return beveled


## One 3x3 gaussian pass over the whole tile, so the height field stays defined on
## every pixel: the smoothing is what turns the one-pixel rim into a two-pixel ramp.
## The field is periodic (see the header comment).
func _smooth(height: PackedFloat32Array) -> PackedFloat32Array:
	var kernel := PackedFloat32Array([1.0, 2.0, 1.0, 2.0, 4.0, 2.0, 1.0, 2.0, 1.0])
	var smoothed := height.duplicate()
	for y: int in TILE_SIZE:
		for x: int in TILE_SIZE:
			var total := 0.0
			for kernel_y: int in 3:
				for kernel_x: int in 3:
					var sample_x := _wrap(x + kernel_x - 1)
					var sample_y := _wrap(y + kernel_y - 1)
					total += kernel[kernel_y * 3 + kernel_x] * height[_index(sample_x, sample_y)]
			smoothed[_index(x, y)] = total / 16.0
	return smoothed


## Rewrites the PNG only when its content changed, so a re-run that produces the
## same atlas leaves the file (and its import stamp) untouched and is truly
## idempotent instead of triggering an import every time. Returns whether the file
## was written.
func _write_png(image: Image) -> bool:
	var bytes := image.save_png_to_buffer()
	var existing := FileAccess.get_file_as_bytes(NORMAL_PNG)
	if existing == bytes:
		print("  %s already up to date" % NORMAL_PNG)
		return false
	var file := FileAccess.open(NORMAL_PNG, FileAccess.WRITE)
	if file == null:
		push_error("bake_tileset_normals: cannot write %s" % NORMAL_PNG)
		return false
	file.store_buffer(bytes)
	file.close()
	print("  wrote %s (%d bytes)" % [NORMAL_PNG, bytes.size()])
	return true


## Godot only loads a PNG through its import step, and a freshly written file has
## none yet, so ask the engine's own importer for it (the same command an editor
## open would run). Skipped when the PNG did not change.
##
## The import is asked for *before* the first `load()` on purpose: the loader
## caches "this path has no import" for the rest of the process, and a cached miss
## would make the texture stay null even after a successful import.
func _ensure_imported() -> Texture2D:
	if _import_is_stale():
		print("  importing %s ..." % NORMAL_PNG)
		var output: Array = []
		var project_dir := ProjectSettings.globalize_path("res://")
		var exit_code := OS.execute(
			OS.get_executable_path(),
			["--headless", "--path", project_dir, "--import"],
			output,
			true
		)
		if exit_code != 0:
			print("  importer exited with %d" % exit_code)
			for line: Variant in output:
				print("  importer: %s" % str(line))
	return load(NORMAL_PNG) as Texture2D


## The import stamp is written by the importer; an older stamp than the source
## means the texture in the cache does not describe the file on disk any more.
func _import_is_stale() -> bool:
	var import_path := NORMAL_PNG + ".import"
	if not FileAccess.file_exists(import_path):
		return true
	if not FileAccess.file_exists(NORMAL_PNG):
		return true
	return (
		FileAccess.get_modified_time(import_path) < FileAccess.get_modified_time(NORMAL_PNG)
	)


## Rebuilds the normal TileSet from the albedo's structure: the same atlas
## coordinates, the same alternative tiles in the same order, the same
## flip/transpose flags. No physics: the layer is data, it is never collided with.
func _build_tileset(albedo: TileSet, texture: Texture2D, failures: Array[String]) -> TileSet:
	var albedo_source := albedo.get_source(0) as TileSetAtlasSource
	if albedo_source == null:
		failures.append("%s has no atlas source 0" % ALBEDO_TILESET)
		return null
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	var tileset := TileSet.new()
	tileset.tile_size = albedo.tile_size
	tileset.add_source(source, 0)
	for tile_index: int in albedo_source.get_tiles_count():
		var coords := albedo_source.get_tile_id(tile_index)
		source.create_tile(coords, albedo_source.get_tile_size_in_atlas(coords))
		for alternative_index: int in albedo_source.get_alternative_tiles_count(coords):
			var alternative := albedo_source.get_alternative_tile_id(coords, alternative_index)
			if alternative == 0:
				# The base tile already exists; id 0 is what an unpainted
				# alternative means, so it is never created twice.
				continue
			var created := source.create_alternative_tile(coords)
			if created != alternative:
				# A gap in the albedo's alternative ids would shift every flag in
				# every room, so stop instead of baking a subtly wrong tileset.
				failures.append(
					"%d:%d alternative %d was created as %d" % [coords.x, coords.y, alternative, created]
				)
				return null
			var origin := albedo_source.get_tile_data(coords, alternative)
			var target := source.get_tile_data(coords, created)
			target.flip_h = origin.flip_h
			target.flip_v = origin.flip_v
			target.transpose = origin.transpose
	print(
		"  mirrored %d tiles, %d alternative tiles"
		% [albedo_source.get_tiles_count(), _alternative_count(albedo_source)]
	)
	return tileset


func _alternative_count(source: TileSetAtlasSource) -> int:
	var total := 0
	for tile_index: int in source.get_tiles_count():
		var coords := source.get_tile_id(tile_index)
		total += source.get_alternative_tiles_count(coords) - 1
	return total


func _save_tileset(tileset: TileSet) -> void:
	var previous_uid := _file_uid(NORMAL_TILESET)
	var error := ResourceSaver.save(tileset, NORMAL_TILESET)
	if error != OK:
		push_error("bake_tileset_normals: cannot save %s (%d)" % [NORMAL_TILESET, error])
		return
	# The .tres is referenced by uid from world_root.tscn; saving a fresh resource
	# would otherwise mint a new uid on every run and silently break that link.
	if not previous_uid.is_empty() and _file_uid(NORMAL_TILESET) != previous_uid:
		_restore_uid(NORMAL_TILESET, previous_uid)


## The `uid="uid://..."` of the resource header, or "" when the file has none.
func _file_uid(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	while not file.eof_reached():
		var line := file.get_line()
		if not line.begins_with("[gd_resource"):
			continue
		var start := line.find("uid=\"")
		if start < 0:
			return ""
		start += 5
		var end := line.find("\"", start)
		return line.substr(start, end - start) if end > start else ""
	return ""


func _restore_uid(path: String, uid: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var lines: Array[String] = []
	while not file.eof_reached():
		lines.append(file.get_line())
	file.close()
	var output := FileAccess.open(path, FileAccess.WRITE)
	if output == null:
		return
	for line: String in lines:
		if line.begins_with("[gd_resource"):
			var start := line.find("uid=\"")
			if start >= 0:
				var end := line.find("\"", start + 5)
				if end > start:
					line = line.substr(0, start + 5) + uid + line.substr(end)
		output.store_line(line)
	output.close()


