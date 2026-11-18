extends Node

## Regression test for the vertical stripes that ran down the gas layer.
##
## fog_layer.gdshader quantises the gas opacity per world pixel with
##
##     alpha = floor(alpha * 32.0 + bayer4(world)) / 32.0
##
## The world viewport is 320x180 and is upscaled 4x with nearest filtering, so one
## *column* of the 4x4 dither tile is four screen pixels wide. A tile whose columns
## do not carry the same thresholds therefore paints vertical bars through the gas.
##
## That is what the owner described ("vertical dividing lines ... like two noise
## textures joined with a seam"). The old kernel was the Bayer matrix with its bit
## order reversed: all eight low thresholds sat in the even columns and all eight
## high ones in the odd columns, so the dither resolved into columns instead of a
## dispersed stipple. Measured on a gas-only capture, neighbouring world columns
## differed by 0.0156 opacity, a 9% brightness stripe over the layer; the recursive
## kernel used here (and by the light, bloom, backdrop and fog dithers) brings that
## to 0.0007.
##
## Covered:
##   * the kernel is a permutation of 0..15, so no threshold is lost or doubled,
##   * at the half-opacity level every column and every row of the tile carries the
##     same number of lit texels (no column is fully on while its neighbour is off),
##   * the opacity each column receives, averaged over every alpha level through the
##     shader's exact quantiser, differs by less than 0.3% (the stripe amplitude),
##   * the mean opacity is unchanged, so removing the stripe cannot dim the gas,
##   * the kernel is anchored to world pixels: a chunk-aligned room origin (a
##     multiple of 4) sees the same phase at room-local 0 as at world 0, which is
##     what stops a seam appearing where the quad starts,
##   * the shader still builds its kernel with the recursive form, so reverting the
##     shader fails here even though this file keeps its own copy of the maths,
##   * value_noise/hash21 stay continuous across the simulation's 4 px texel
##     boundaries, which is the other candidate the report named.
##
## Not covered: pixels, the GPU solver itself, and the *horizontal* (row) balance of
## the kernel. Row balance is a property the ordered dither shares with the other
## dithers in the project and is not the seam that was reported.

const FOG_SHADER_PATH := "res://addons/fluid_kit/runtime/gas/fog_layer.gdshader"
const TILE := 4
const HALF_THRESHOLD := 8
## The three scales fog_layer.gdshader feeds value_noise(), and the world x of the
## light lab room (chunk 3), used to mirror the shader's sampling.
const GAS_NOISE_SCALE := Vector3(0.09, 0.17, 0.3)
const ROOM_ORIGIN_X := 960.0
const ROOM_PIXELS := Vector2i(320, 180)
const TEXEL_PIXELS := 4


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_kernel_is_a_permutation(failures)
	_assert_half_threshold_is_dispersed(failures)
	_assert_column_opacity_is_balanced(failures)
	_assert_mean_opacity_is_unchanged(failures)
	_assert_kernel_is_world_anchored(failures)
	_assert_shader_keeps_the_recursive_kernel(failures)
	_assert_noise_is_continuous_across_texels(failures)
	return failures


## The kernel value in 0..15 at a world pixel, before the half-step centring.
## This mirrors the shader's bayer4 body line for line: M4 = 4 * M2(inner) + M2(outer)
## with the 2x2 seed [[0, 2], [3, 1]].
func _kernel_index(px: float, py: float) -> int:
	var qx := floorf(fposmod(px, float(TILE)))
	var qy := floorf(fposmod(py, float(TILE)))
	var inner := fposmod(3.0 * fposmod(qy, 2.0) + 2.0 * fposmod(qx, 2.0), 4.0)
	var outer := fposmod(
		3.0 * floorf(fposmod(qy, float(TILE)) * 0.5) + 2.0 * floorf(fposmod(qx, float(TILE)) * 0.5),
		4.0
	)
	return int(4.0 * inner + outer)


## The threshold the shader adds, in [0, 1).
func _bayer4(px: float, py: float) -> float:
	return (float(_kernel_index(px, py)) + 0.5) / float(TILE * TILE)


func _assert_kernel_is_a_permutation(failures: Array[String]) -> void:
	var seen: Dictionary[int, bool] = {}
	for y in TILE:
		for x in TILE:
			var index := _kernel_index(float(x), float(y))
			if index < 0 or index >= TILE * TILE:
				failures.append("dither kernel index %d out of range at %d,%d" % [index, x, y])
				continue
			if seen.has(index):
				failures.append("dither kernel repeats threshold %d, so one level is wasted" % index)
			seen[index] = true
	if seen.size() != TILE * TILE:
		failures.append("dither kernel covers %d of %d thresholds" % [seen.size(), TILE * TILE])


## At the most visible level (half of the tile lit) every column must hold the same
## number of lit texels. The old kernel put 4 in the even columns and 0 in the odd
## ones, which is literally a column of gas beside a column of no gas.
func _assert_half_threshold_is_dispersed(failures: Array[String]) -> void:
	for x in TILE:
		var lit := 0
		for y in TILE:
			if _kernel_index(float(x), float(y)) < HALF_THRESHOLD:
				lit += 1
		if lit != TILE / 2:
			failures.append(
				"dither column %d lights %d of %d texels at half opacity, want %d: the dither is columnar"
				% [x, lit, TILE, TILE / 2]
			)
	for y in TILE:
		var lit := 0
		for x in TILE:
			if _kernel_index(float(x), float(y)) < HALF_THRESHOLD:
				lit += 1
		if lit != TILE / 2:
			failures.append("dither row %d lights %d of %d texels at half opacity" % [y, lit, TILE])


## The actual seam amplitude: run the shader's quantiser over every alpha level and
## average the opacity each column receives. A column bias here is a vertical stripe
## in the gas, because the column bias is exactly what the eye integrates over a
## wisp whose opacity varies with position.
func _assert_column_opacity_is_balanced(failures: Array[String]) -> void:
	var levels := 256
	var totals := PackedFloat64Array()
	totals.resize(TILE)
	for level: int in levels:
		var alpha := 0.01 + float(level) * (0.98 / float(levels - 1))
		for x: int in TILE:
			for y: int in TILE:
				var quantised := floorf(alpha * 32.0 + _bayer4(float(x), float(y))) / 32.0
				totals[x] += quantised
	var means: Array[float] = []
	for x: int in TILE:
		means.append(totals[x] / float(levels * TILE))
	var lowest := means[0]
	var highest := means[0]
	for value: float in means:
		lowest = minf(lowest, value)
		highest = maxf(highest, value)
	if highest - lowest > 0.003:
		failures.append(
			"dither column opacity spread %.4f (%.4f..%.4f) is a visible vertical stripe"
			% [highest - lowest, lowest, highest]
		)
	var even := (means[0] + means[2]) * 0.5
	var odd := (means[1] + means[3]) * 0.5
	if absf(even - odd) > 0.002:
		failures.append(
			"dither gives even columns %.4f and odd columns %.4f: alternating vertical bars"
			% [even, odd]
		)


## Removing the stripe must not dim the gas: the kernel's mean threshold is 0.5, the
## same average the old one had, so coverage and mean opacity stay put.
func _assert_mean_opacity_is_unchanged(failures: Array[String]) -> void:
	var levels := 256
	var dithered := 0.0
	var plain := 0.0
	for level: int in levels:
		var alpha := 0.01 + float(level) * (0.98 / float(levels - 1))
		for x: int in TILE:
			for y: int in TILE:
				dithered += floorf(alpha * 32.0 + _bayer4(float(x), float(y))) / 32.0
				plain += floorf(alpha * 32.0) / 32.0
	var samples := float(levels * TILE * TILE)
	var shift := (dithered - plain) / samples
	# A dither is allowed to round the mean opacity up by at most half a step of the
	# 1/16 kernel, but it must not change how thick the gas looks.
	if shift < -0.0025 or shift > 0.0265:
		failures.append("dither shifts the mean opacity by %+.4f, changing how thick the gas looks" % shift)


## The pattern is world anchored, so every chunk-aligned room sees the same phase at
## its own zero as at world zero; a room-local offset would butt two phases together
## at the quad's edge, which is the "two textures joined" reading of the report.
func _assert_kernel_is_world_anchored(failures: Array[String]) -> void:
	for step: int in TILE:
		var at_world := _bayer4(ROOM_ORIGIN_X + float(step), 0.0)
		var at_room := _bayer4(float(step), 0.0)
		if not is_equal_approx(at_world, at_room):
			failures.append("dither phase jumps at the room origin (world x=%d)" % int(ROOM_ORIGIN_X))
	for shift: float in [-8.0, 4.0, 12.0]:
		if not is_equal_approx(_bayer4(shift, shift), _bayer4(0.0, 0.0)):
			failures.append("dither does not tile with period %d" % TILE)


## A copy of the maths in this file cannot catch a shader revert on its own, so the
## shader source is checked for the recursive construction. The old broken kernel
## multiplied the position's low bits straight into the high threshold bits.
func _assert_shader_keeps_the_recursive_kernel(failures: Array[String]) -> void:
	if not FileAccess.file_exists(FOG_SHADER_PATH):
		failures.append("gas fog shader is missing: %s" % FOG_SHADER_PATH)
		return
	var source := FileAccess.get_file_as_string(FOG_SHADER_PATH)
	if source.is_empty():
		failures.append("gas fog shader could not be read: %s" % FOG_SHADER_PATH)
		return
	for marker: String in [
		"float inner = mod(3.0 * mod(q.y, 2.0) + 2.0 * mod(q.x, 2.0), 4.0);",
		"float outer = mod(",
		"return (4.0 * inner + outer + 0.5) / 16.0;",
	]:
		if not source.contains(marker):
			failures.append(
				"fog_layer.gdshader dither kernel changed (missing `%s`); keep it balanced or update this test"
				% marker
			)
	if source.contains("mod(x, 2.0) * 8.0"):
		failures.append("fog_layer.gdshader is back to the columnar bit-trick dither kernel")


## The other candidate the report named: the noise itself. value_noise is a smooth
## interpolation of lattice hashes, so the slope from the last pixel of one 4 px
## texel to the first of the next must be no steeper than anywhere else. The
## formula is the shader's, run in doubles; that proves the construction is
## continuous, not the float32 bit pattern.
func hash21(p: Vector2) -> float:
	var q := Vector2(fposmod(p.x * 123.34, 1.0), fposmod(p.y * 456.21, 1.0))
	var dot := q.x * (q.x + 45.32) + q.y * (q.y + 45.32)
	return fposmod((q.x + dot) * (q.y + dot), 1.0)


func value_noise(p: Vector2) -> float:
	var cell := p.floor()
	var f := p - cell
	f = f * f * (Vector2(3.0, 3.0) - 2.0 * f)
	var a := hash21(cell)
	var b := hash21(cell + Vector2(1.0, 0.0))
	var c := hash21(cell + Vector2(0.0, 1.0))
	var d := hash21(cell + Vector2(1.0, 1.0))
	return lerpf(lerpf(a, b, f.x), lerpf(c, d, f.x), f.y)


func _assert_noise_is_continuous_across_texels(failures: Array[String]) -> void:
	# One column mean per x, averaged over a spread of rows: a seam would raise every
	# row at the same x, a ramping noise does not.
	var rows: Array[int] = []
	for row: int in range(0, ROOM_PIXELS.y, 4):
		rows.append(row)
	for scale: float in [GAS_NOISE_SCALE.x, GAS_NOISE_SCALE.y, GAS_NOISE_SCALE.z]:
		var column_steps := PackedFloat64Array()
		column_steps.resize(ROOM_PIXELS.x - 1)
		for row: int in rows:
			var world_y := float(row) + 0.5
			for x: int in ROOM_PIXELS.x - 1:
				var here := value_noise(Vector2(ROOM_ORIGIN_X + float(x) + 0.5, world_y) * scale)
				var next := value_noise(Vector2(ROOM_ORIGIN_X + float(x) + 1.5, world_y) * scale)
				column_steps[x] += absf(next - here)
		var boundary_steps := 0.0
		var boundary_count := 0
		var inner_steps := 0.0
		var inner_count := 0
		var sorted_steps: Array[float] = []
		for x: int in column_steps.size():
			var mean_step := column_steps[x] / float(rows.size())
			sorted_steps.append(mean_step)
			if (x + 1) % TEXEL_PIXELS == 0:
				boundary_steps += mean_step
				boundary_count += 1
			else:
				inner_steps += mean_step
				inner_count += 1
		sorted_steps.sort()
		var median := sorted_steps[sorted_steps.size() >> 1]
		var steepest := sorted_steps[sorted_steps.size() - 1]
		if median > 0.0 and steepest > 2.5 * median:
			failures.append(
				"gas noise has a column %.2fx steeper than its median column (scale %.2f)"
				% [steepest / median, scale]
			)
		if boundary_count > 0 and inner_count > 0 and inner_steps > 0.0:
			var ratio := (boundary_steps / float(boundary_count)) / (inner_steps / float(inner_count))
			if ratio > 1.25:
				failures.append(
					"gas noise is %.2fx steeper on the %d px texel boundaries (scale %.2f)"
					% [ratio, TEXEL_PIXELS, scale]
				)
