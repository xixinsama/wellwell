extends Node

## Runtime guard for the 64x64 blue-noise threshold tile the gas/mist layer dithers with.
##
## WHY this test exists
## The mist used to quantise its opacity with a 4x4 ordered (Bayer) dither, which
## repeats a tiny lattice: at low coverage the lit texels fall on a regular 4 px grid
## and the faint mist reads as a "screen door" of dots. resources/textures/
## blue_noise_64.png replaces that lattice with a void-and-cluster blue-noise
## threshold map (baked by scripts/tools/bake_blue_noise.gd, which prints the full
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
		failures.append("blue noise tile is missing: %s (bake it with scripts/tools/bake_blue_noise.gd)" % TEXTURE_PATH)
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

