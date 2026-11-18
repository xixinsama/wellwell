extends SceneTree

## Blue-noise threshold texture baker: a seamless 64x64 void-and-cluster tile.
##
## WHY a blue noise tile
## The gas/mist layer quantises its opacity with a 4x4 ordered (Bayer) dither. An
## ordered dither repeats a tiny lattice, so at low coverage the lit texels land on a
## regular 4 px grid and the faint mist shows a "screen door" of dots. A 4x4 Bayer is
## also degenerate at half coverage: it is very nearly a 1 px checkerboard, so 75% of
## its spectral energy sits in the single (32, 32) bin and another 19% in the
## period-2 row bin (0, 32) -- both measured below, and the second one is the
## mechanism behind the vertical gas stripes that tests/world/test_gas_dither_seam.gd
## pins down. Blue noise keeps the same uniform coverage per level but spreads the
## quantisation error as a stochastic, minimum-distance point pattern, which is the
## usual fix for a faint ordered-dither grid.
##
## WHAT it bakes
## Ulichney's void-and-cluster over a 64x64 *torus*:
##   * the energy field of a binary pattern is the sum of a wrapped Gaussian kernel
##     (sigma 1.5, support +-6 cells) over the "on" cells,
##   * the "tightest cluster" is the on cell with maximum energy, the "largest void"
##     the off cell with minimum energy,
##   * a random ~10% pattern is relaxed by moving the tightest cluster into the
##     largest void until the two coincide (phase 0),
##   * the relaxed pattern seeds three ranking passes that visit every cell once:
##     peel the tightest cluster (ranks descending through the prototype), then refill
##     the largest voids from that same prototype (ranks ascending to the halfway
##     point), then peel the tightest cluster off the complement (ranks to the end).
##     The result is a permutation of 0..4095.
## Distances wrap, so column 63 is one pixel from column 0 and the tile repeats
## without a seam; a shader can sample it with REPEAT and no feathering.
##
## The 8-bit PNG stores rank * 255 / 4095, i.e. a threshold map: at coverage p the
## shader lights every texel below p * 255. 4096 ranks round onto 256 byte levels with
## 16 ranks each in the middle of the range and 9 / 8 at the two extremes (255/4095
## does not divide evenly), so every level is used and the low levels the faint mist
## needs are populated; that rounding is the whole of the histogram's max deviation of
## 7 texels.
##
## Usage (headless, no rendering device needed):
##   & godot --headless --path . -s res://scripts/tools/bake_blue_noise.gd
##
## It writes res://resources/textures/blue_noise_64.png and prints the measured
## quality numbers: the histogram of the 256 output levels, toroidal dispersion
## against white noise, the ordered-dither lattice peaks (blue noise vs a tiled 4x4
## Bayer), the radial spectrum, and the bake time. The bake is deterministic: one
## fixed RNG seed and no time-, platform- or device-dependent input.
##
## The numbers this run should print, for reference (measured on the committed tile,
## and guarded by tests/world/test_blue_noise.gd):
##   bake            0.83 s (two thirds of it the min/max scans of phases 2 and 3)
##   ranks           a permutation of 0..4095
##   histogram       max deviation 7 texels of the 64 expected per bin
##   dispersion      25% coverage: 1.427 cells vs 1.189 for a shuffled set, i.e. 1.20x
##                   the shuffle and 1.43x the Poisson expectation 1/(2 sqrt(0.25))
##   lattice         period-2 family 0.094% of the energy against the Bayer's 94.1%,
##                   period-4 family 0.002% against 1.2%
##   radial          0.0001% below 4 cycles/tile, then 0.002 / 0.013 / 0.16 / 1.6 /
##                   10.9 / 25.1 / 30.6% and 31.6% in the diagonal corners
##   balance         column means span 553 rank units, row means 465 of 4096

const TILE_SIZE := 64
const CELL_COUNT := TILE_SIZE * TILE_SIZE
const HALF_COUNT := CELL_COUNT >> 1
## 64 is a power of two, so a cell index splits into (x, y) with a mask and a shift.
## That matters here: the kernel updates and the min/max scans run a few million
## times over 169 and 4096 cells, and `%` / `/` were the most expensive calls in
## those loops.
const TILE_MASK := TILE_SIZE - 1
const TILE_SHIFT := 6

## Kernel sigma and support, in cells. 1.5 is the tight end of the usual 1.5..1.9 band
## for small tiles, and it was measured, not guessed: at sigma 1.5 / 1.7 / 1.9 this
## tool reports 1.44 / 1.37 / 1.31 cells for the 25% nearest-neighbour distance, while
## the low-frequency rings stay at 1e-6 of the energy and the lattice peaks stay at
## 0.02-0.08%, so the sharper kernel buys dispersion at no spectral cost. (Below 1.5
## the pattern starts to clump: the energy field is then too short-ranged to see the
## far side of a void.)
## The +-6 support is where this Gaussian is below 0.03% of its peak, so the
## truncation is far below the rounding of a rank unit, and each cell update costs
## 169 additions.
const KERNEL_SIGMA := 1.5
const KERNEL_RADIUS := 6
const KERNEL_SPAN := KERNEL_RADIUS * 2 + 1

## Ulichney's starting density: sparse enough that the relaxation has room to push
## cells apart, dense enough that it converges in a few hundred swaps.
const INITIAL_FRACTION := 0.1
## The relaxation is a greedy local search, so it can cycle instead of settling on a
## pathological start. The cap only exists so a bad seed cannot hang the tool; a
## healthy run stops in a few hundred swaps, well before it.
const MAX_RELAX_STEPS := 2048
## Fixed seed: the artifact has to be reproducible byte for byte, otherwise the
## committed PNG and the printed quality numbers would drift apart on every run.
const RNG_SEED := 20261119
const OUTPUT_PATH := "res://resources/textures/blue_noise_64.png"

## Coverage levels the dispersion is measured at. 1% is the faint-mist range the
## tile is for, 50% is the densest pattern where a lattice is most visible.
const THRESHOLDS: Array[float] = [0.01, 0.05, 0.25, 0.5]
## Radial spectrum: 8 rings of 4 cycles per tile, plus an explicit bucket for the
## diagonal corners from 32 cycles out, so the listed shares add up to 100%.
const RING_COUNT := 8
const RING_WIDTH := 4.0
## Histogram: 64 bins of 4 byte levels, 4096 / 64 = 64 cells expected per bin.
const BIN_COUNT := 64
const BIN_SHIFT := 2

## The frequencies a 4x4 ordered dither (and its period-2/4/8 harmonics) peaks on.
## (kx, ky) are DFT bin indices of the 64x64 tile, so the period along x is
## TILE_SIZE / kx. LATTICE_LABELS is in the same order.
const LATTICE_FREQUENCIES: Array[Vector2i] = [
	Vector2i(32, 0), Vector2i(0, 32), Vector2i(32, 32),
	Vector2i(16, 0), Vector2i(0, 16),
	Vector2i(8, 0), Vector2i(0, 8),
]
const LATTICE_LABELS: Array[String] = ["2 (x)", "2 (y)", "2 x 2", "4 (x)", "4 (y)", "8 (x)", "8 (y)"]
## The exact matrix the gas shader dithers with (see tests/world/test_gas_dither_seam.gd,
## which pins the same 16 values): it is the reference the baked tile has to beat.
const BAYER_4X4: Array[int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

var _kernel := PackedFloat32Array()
## cos / sin of 2*pi*k*n/TILE_SIZE, indexed [k * TILE_SIZE + n].
var _cos_table := PackedFloat64Array()
var _sin_table := PackedFloat64Array()
## The bake mutates these two buffers in place: every energy update touches 169
## cells and every choice scans all 4096, so copying the field per call (or relying
## on packed-array argument semantics) would cost more than the search around it.
var _pattern := PackedByteArray()
var _energy := PackedFloat32Array()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var started_ms := Time.get_ticks_msec()
	_kernel = _build_kernel()
	_build_trig_tables()
	var rng := RandomNumberGenerator.new()
	rng.seed = RNG_SEED
	print("bake_blue_noise: %dx%d torus, void-and-cluster, sigma=%.2f, support=+-%d, seed=%d" % [
		TILE_SIZE, TILE_SIZE, KERNEL_SIGMA, KERNEL_RADIUS, RNG_SEED
	])
	var initial_ms := Time.get_ticks_msec()
	_pattern = _initial_pattern(rng)
	_rebuild_energy()
	var swaps := _relax()
	var ones := _count_on(_pattern)
	print("phase 0: relaxed in %d swaps, %d cells on (%.1f%%), %.2f s" % [
		swaps, ones, 100.0 * float(ones) / float(CELL_COUNT),
		float(Time.get_ticks_msec() - initial_ms) / 1000.0
	])
	var ranks := _rank_cells()
	var bake_seconds := float(Time.get_ticks_msec() - started_ms) / 1000.0

	var bytes := _bytes_from_ranks(ranks)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_PATH.get_base_dir()))
	var image := Image.create_from_data(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_L8, bytes)
	if image == null:
		push_error("bake_blue_noise: cannot build a %dx%d L8 image" % [TILE_SIZE, TILE_SIZE])
		quit(1)
		return
	var error := image.save_png(OUTPUT_PATH)
	if error != OK:
		push_error("bake_blue_noise: cannot write %s (error %d)" % [OUTPUT_PATH, error])
		quit(1)
		return
	print("bake_blue_noise: wrote %s (%dx%d, %d bytes of L8 payload) in %.2f s" % [
		OUTPUT_PATH, TILE_SIZE, TILE_SIZE, bytes.size(), bake_seconds
	])

	_report_rank_check(ranks)
	var histogram := _report_histogram(bytes)
	var balance := _report_balance(ranks)
	var dispersion := _report_dispersion(ranks, rng)
	var spectrum := _report_spectrum(ranks, bytes)
	print("summary: bake %.2f s, %d swaps, histogram deviation %d, 25%% dispersion %.2fx the white shuffle / %.2fx the poisson expectation" % [
		bake_seconds, swaps, histogram, dispersion.x, dispersion.y
	])
	print("summary: period-2 lattice %.4f%% (bayer %.2f%%), ring 0-4 %.4f%%, ring 28-32 %.2f%%, column spread %.1f, row spread %.1f rank units" % [
		100.0 * float(spectrum["period2"]), 100.0 * float(spectrum["bayer_period2"]),
		100.0 * float(spectrum["ring0"]), 100.0 * float(spectrum["ring7"]),
		balance.x, balance.y
	])
	quit(0)


# ----------------------------------------------------------------------------- bake

## Toroidal Gaussian weights, row major over the [-KERNEL_RADIUS, +KERNEL_RADIUS]
## square. The kernel is sampled on the *torus*, so the fixup for a cell near the
## tile edge is simply the wrap in `_apply_cell`; no border special case is needed.
func _build_kernel() -> PackedFloat32Array:
	var weights := PackedFloat32Array()
	weights.resize(KERNEL_SPAN * KERNEL_SPAN)
	var scale := -1.0 / (2.0 * KERNEL_SIGMA * KERNEL_SIGMA)
	for offset_y: int in KERNEL_SPAN:
		var dy := float(offset_y - KERNEL_RADIUS)
		for offset_x: int in KERNEL_SPAN:
			var dx := float(offset_x - KERNEL_RADIUS)
			weights[offset_y * KERNEL_SPAN + offset_x] = exp((dx * dx + dy * dy) * scale)
	return weights


func _build_trig_tables() -> void:
	_cos_table.resize(CELL_COUNT)
	_sin_table.resize(CELL_COUNT)
	for frequency: int in TILE_SIZE:
		for sample: int in TILE_SIZE:
			var angle := TAU * float(frequency * sample) / float(TILE_SIZE)
			_cos_table[frequency * TILE_SIZE + sample] = cos(angle)
			_sin_table[frequency * TILE_SIZE + sample] = sin(angle)


## A random pattern with ~10% of the cells on. The relaxation only fixes clusters
## that are visible at that density; starting sparse keeps the first iterations cheap
## and lets the void search pick the far side of the tile, which is what gives the
## prototype its even spread.
func _initial_pattern(rng: RandomNumberGenerator) -> PackedByteArray:
	var pattern := PackedByteArray()
	pattern.resize(CELL_COUNT)
	pattern.fill(0)
	var seeds := _random_cells(rng, roundi(INITIAL_FRACTION * float(CELL_COUNT)))
	for index: int in seeds.size():
		pattern[seeds[index]] = 1
	return pattern


## Rebuild the energy field from scratch: O(cells * kernel), only worth doing at the
## start of phase 0 and phase 3. The ranking passes update it per moved cell instead.
func _rebuild_energy() -> void:
	_energy = PackedFloat32Array()
	_energy.resize(CELL_COUNT)
	_energy.fill(0.0)
	for cell: int in CELL_COUNT:
		if _pattern[cell] != 0:
			_apply_cell(cell, 1.0)


## Add (sign = 1) or remove (sign = -1) one cell's kernel around the whole field.
##
## `(coordinate + offset + TILE_SIZE) & TILE_MASK` is the toroidal wrap: the offset
## range is +-6, so adding one tile size keeps the value positive before masking.
func _apply_cell(cell: int, sign: float) -> void:
	var cx := cell & TILE_MASK
	var cy := cell >> TILE_SHIFT
	for offset_y: int in KERNEL_SPAN:
		var row := ((cy + offset_y - KERNEL_RADIUS + TILE_SIZE) & TILE_MASK) * TILE_SIZE
		var kernel_row := offset_y * KERNEL_SPAN
		for offset_x: int in KERNEL_SPAN:
			var column := (cx + offset_x - KERNEL_RADIUS + TILE_SIZE) & TILE_MASK
			_energy[row + column] += sign * _kernel[kernel_row + offset_x]


## Phase 0: Ulichney's relaxation. Move the tightest cluster into the largest void;
## the pattern is stable once the void the cluster just left is the largest one
## available, which is exactly the fixed point of that exchange.
func _relax() -> int:
	var steps := 0
	while steps < MAX_RELAX_STEPS:
		var cluster := _tightest_cluster()
		_pattern[cluster] = 0
		_apply_cell(cluster, -1.0)
		var void_cell := _largest_void()
		if void_cell == cluster:
			# Undo the probe: the pattern was already stable.
			_pattern[cluster] = 1
			_apply_cell(cluster, 1.0)
			break
		_pattern[void_cell] = 1
		_apply_cell(void_cell, 1.0)
		steps += 1
	return steps


## Phases 1-3: turn the prototype into a full ranking of every cell.
##
## Phase 1 peels the tightest cluster out of the sparse prototype and hands it the
## top rank of that group, so the cells that survive longest (the most isolated ones)
## end up with the lowest ranks: the first levels to switch on are already dispersed.
## Phase 2 then continues from the prototype and grows the coverage from 10% to 50%
## by always taking the largest void, so every added cell is the one that most needs
## to be lit. Phase 3 works on the complement of that half-filled pattern and peels
## its tightest clusters with ascending ranks, so the very last cells to switch on
## (the highest ranks) are the most isolated ones of that complement. Every prefix
## {rank < t} is therefore a dispersed set, which is what makes the tile readable at
## *any* threshold.
func _rank_cells() -> PackedInt32Array:
	var ranks := PackedInt32Array()
	ranks.resize(CELL_COUNT)
	ranks.fill(-1)
	var ones := _count_on(_pattern)

	var phase_ms := Time.get_ticks_msec()
	var rank := ones - 1
	while rank >= 0:
		var cluster := _tightest_cluster()
		ranks[cluster] = rank
		_pattern[cluster] = 0
		_apply_cell(cluster, -1.0)
		rank -= 1
	print("phase 1: ranks %d..0 peeled from the prototype, %.2f s" % [
		ones - 1, float(Time.get_ticks_msec() - phase_ms) / 1000.0
	])

	phase_ms = Time.get_ticks_msec()
	# Phase 2 has to continue from the prototype, not from an empty field: the on-set
	# of every threshold {rank < r} is *all* the cells ranked so far, so the cells
	# phase 1 peeled are lit again and the search only ever fills the remaining voids.
	# (Starting from an empty field instead lets the void search overwrite the ranks
	# phase 1 just assigned, which silently drops ~4% of the rank values.)
	for cell: int in CELL_COUNT:
		_pattern[cell] = 1 if ranks[cell] >= 0 else 0
	_rebuild_energy()
	rank = ones
	while rank < HALF_COUNT:
		var void_cell := _largest_void()
		ranks[void_cell] = rank
		_pattern[void_cell] = 1
		_apply_cell(void_cell, 1.0)
		rank += 1
	print("phase 2: ranks %d..%d filled into the largest voids, %.2f s" % [
		ones, HALF_COUNT - 1, float(Time.get_ticks_msec() - phase_ms) / 1000.0
	])

	phase_ms = Time.get_ticks_msec()
	# The complement of the half-filled pattern: the cells still waiting for a rank
	# are the ones that stayed off the whole way through phase 2.
	for cell: int in CELL_COUNT:
		_pattern[cell] = 1 if ranks[cell] < 0 else 0
	_rebuild_energy()
	rank = HALF_COUNT
	while rank < CELL_COUNT:
		var cluster := _tightest_cluster()
		ranks[cluster] = rank
		_pattern[cluster] = 0
		_apply_cell(cluster, -1.0)
		rank += 1
	print("phase 3: ranks %d..%d peeled from the complement, %.2f s" % [
		HALF_COUNT, CELL_COUNT - 1, float(Time.get_ticks_msec() - phase_ms) / 1000.0
	])
	return ranks


## The on cell whose kernel covers the most other on cells.
func _tightest_cluster() -> int:
	var best := -INF
	var best_cell := 0
	for cell: int in CELL_COUNT:
		if _pattern[cell] == 0:
			continue
		var value := _energy[cell]
		if value > best:
			best = value
			best_cell = cell
	return best_cell


## The off cell with the least kernel coverage.
func _largest_void() -> int:
	var best := INF
	var best_cell := 0
	for cell: int in CELL_COUNT:
		if _pattern[cell] != 0:
			continue
		var value := _energy[cell]
		if value < best:
			best = value
			best_cell = cell
	return best_cell


func _count_on(pattern: PackedByteArray) -> int:
	var count := 0
	for cell: int in CELL_COUNT:
		count += pattern[cell]
	return count


## rank * 255 / 4095, rounded. 4096 ranks over 256 byte levels is ~16 ranks per
## level; 255/4095 is slightly above 1/16, so a few levels take 17 and none is lost.
func _bytes_from_ranks(ranks: PackedInt32Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(CELL_COUNT)
	for cell: int in CELL_COUNT:
		bytes[cell] = roundi(float(ranks[cell]) * 255.0 / float(CELL_COUNT - 1))
	return bytes


# ----------------------------------------------------------------------------- report

## A permutation check first: if a rank is missing or doubled, every number below it
## is meaningless, and the failure mode (a level that never lights) is silent.
func _report_rank_check(ranks: PackedInt32Array) -> void:
	var seen := PackedByteArray()
	seen.resize(CELL_COUNT)
	seen.fill(0)
	var missing := 0
	var doubled := 0
	for cell: int in CELL_COUNT:
		var rank := ranks[cell]
		if rank < 0 or rank >= CELL_COUNT:
			missing += 1
			continue
		if seen[rank] != 0:
			doubled += 1
		seen[rank] = 1
	for rank: int in CELL_COUNT:
		if seen[rank] == 0:
			missing += 1
	if missing == 0 and doubled == 0:
		print("ranks: permutation of 0..%d, all %d cells ranked once" % [CELL_COUNT - 1, CELL_COUNT])
	else:
		push_error("bake_blue_noise: rank map is not a permutation (%d missing, %d doubled)" % [missing, doubled])


## Uniformity of the 256 thresholds in 64 bins of 4 byte levels. Ranks are a
## permutation, so the only deviation left is the rounding of 4096 ranks onto 256
## levels: a spread of a couple of cells is expected, a spread of tens would mean the
## low or high end of the threshold range is crowded and would band the mist.
func _report_histogram(bytes: PackedByteArray) -> int:
	var counts := PackedInt32Array()
	counts.resize(BIN_COUNT)
	counts.fill(0)
	for cell: int in CELL_COUNT:
		counts[bytes[cell] >> BIN_SHIFT] += 1
	var expected := CELL_COUNT / BIN_COUNT
	var deviation := 0
	var lowest := CELL_COUNT
	var highest := 0
	var line := ""
	for bin: int in BIN_COUNT:
		var count := counts[bin]
		deviation = maxi(deviation, absi(count - expected))
		lowest = mini(lowest, count)
		highest = maxi(highest, count)
		line += "%d " % count
	print("histogram: %d bins of 4 byte levels, expected %d each, counts %d..%d, max deviation %d" % [
		BIN_COUNT, expected, lowest, highest, deviation
	])
	print("  counts per bin: %s" % line)
	return deviation


## Column and row balance of the rank map, in rank units (0..4095).
##
## A dither tile can be perfectly uniform and still lean on one axis, and any such
## lean shows up as a screen-space stripe once the tile is repeated every 64 px. A
## random permutation would put the per-column mean ~150 rank units away from the
## nominal 2047.5 just from sampling noise; a dispersed tile is far tighter.
func _report_balance(ranks: PackedInt32Array) -> Vector2:
	var columns := PackedFloat64Array()
	var rows := PackedFloat64Array()
	columns.resize(TILE_SIZE)
	rows.resize(TILE_SIZE)
	columns.fill(0.0)
	rows.fill(0.0)
	for cell: int in CELL_COUNT:
		var value := float(ranks[cell])
		columns[cell & TILE_MASK] += value
		rows[cell >> TILE_SHIFT] += value
	for index: int in TILE_SIZE:
		columns[index] /= float(TILE_SIZE)
		rows[index] /= float(TILE_SIZE)
	var column_spread := _spread(columns)
	var row_spread := _spread(rows)
	print("balance: nominal mean rank per line 2047.5, column spread %.1f, row spread %.1f rank units" % [
		column_spread, row_spread
	])
	return Vector2(column_spread, row_spread)


## Dispersion: for the cells below a coverage threshold, the mean and spread of the
## nearest-neighbour distance, measured on the torus.
##
## Blue noise is not just "random but pretty": its defining property is the minimum
## spacing, so its nearest-neighbour distances are large and tight. Two references are
## printed, because they answer different questions:
##   * "white" is a shuffled set of the same number of cells on this same 64x64 grid.
##     It is the honest like-for-like comparison, but a discrete grid gives even white
##     noise plenty of distance-1 pairs, so it starts high (1.20 cells at 25%).
##   * "poisson" is the continuous white-noise expectation 1 / (2 * sqrt(density)),
##     i.e. the textbook nearest-neighbour distance of a random point process of the
##     same density. That is the number the tile's spacing is usually quoted against.
## The 25% row is the one the runtime test guards, so both ratios are reported there.
func _report_dispersion(ranks: PackedInt32Array, rng: RandomNumberGenerator) -> Vector2:
	print("dispersion: toroidal nearest-neighbour distance, cells below each rank threshold")
	print("  coverage   cells   blue mean   blue sd   white mean   white sd   vs white   poisson   vs poisson")
	var quarter := Vector2.ZERO
	for threshold: float in THRESHOLDS:
		var count := roundi(threshold * float(CELL_COUNT))
		var blue := _nearest_neighbour_stats(_cells_below(ranks, count))
		var white := _nearest_neighbour_stats(_random_cells(rng, count))
		var density := float(count) / float(CELL_COUNT)
		var poisson := 1.0 / (2.0 * sqrt(density))
		var ratio := blue.x / white.x if white.x > 0.0 else 0.0
		var poisson_ratio := blue.x / poisson
		if is_equal_approx(threshold, 0.25):
			quarter = Vector2(ratio, poisson_ratio)
		print("  %5.0f%%   %5d   %9.3f   %7.3f   %10.3f   %8.3f   %7.2fx   %7.3f   %7.2fx" % [
			threshold * 100.0, count, blue.x, blue.y, white.x, white.y, ratio, poisson, poisson_ratio
		])
	return quarter


## The power spectrum of the threshold map, plus the same measurement on a tiled 4x4
## Bayer matrix so the lattice the tile is replacing is visible as a number.
##
## Signals are normalised to [0, 1] and their mean is removed, so every share below
## is structure rather than a DC offset. Named lattice frequencies are reported as
## the sum of both conjugate bins (a real signal always carries the mirror), while
## the radial rings sum single bins over the whole ring. Both are shares of the total
## spectral energy of the same map, and the Parseval cross-check is printed so the
## DFT itself is auditable.
func _report_spectrum(ranks: PackedInt32Array, bytes: PackedByteArray) -> Dictionary:
	var rank_signal := _signal_from_ranks(ranks)
	var byte_signal := _signal_from_bytes(bytes)
	var bayer_signal := _signal_from_bayer()
	var rank_energy := _spectrum(rank_signal)
	var byte_energy := _spectrum(byte_signal)
	var bayer_energy := _spectrum(bayer_signal)
	var rank_total := _total_energy(rank_energy)
	var byte_total := _total_energy(byte_energy)
	var bayer_total := _total_energy(bayer_energy)
	var parseval := float(CELL_COUNT) * _sum_squares(rank_signal)
	print("spectrum: %d bins, total |F|^2 %.0f, Parseval %.0f (%.3f%% off)" % [
		CELL_COUNT, rank_total, parseval, 100.0 * absf(rank_total - parseval) / parseval
	])

	print("lattice peaks, share of the total spectral energy (both conjugate bins):")
	print("  bin        period     blue ranks     blue png      bayer 4x4")
	var shares: Dictionary = {}
	for index: int in LATTICE_FREQUENCIES.size():
		var frequency := LATTICE_FREQUENCIES[index]
		var rank_share := _pair_share(rank_energy, rank_total, frequency)
		var byte_share := _pair_share(byte_energy, byte_total, frequency)
		var bayer_share := _pair_share(bayer_energy, bayer_total, frequency)
		shares[String(LATTICE_LABELS[index])] = {"png": byte_share, "bayer": bayer_share}
		print("  (%2d,%2d)   %-9s   %11.5f%%   %11.5f%%   %11.5f%%" % [
			frequency.x, frequency.y, String(LATTICE_LABELS[index]),
			100.0 * rank_share, 100.0 * byte_share, 100.0 * bayer_share
		])

	var rank_rings := _ring_shares(rank_energy, rank_total)
	var byte_rings := _ring_shares(byte_energy, byte_total)
	var bayer_rings := _ring_shares(bayer_energy, bayer_total)
	print("radial spectrum, %d rings of %.0f cycles per tile plus the diagonal corners:" % [
		RING_COUNT, RING_WIDTH
	])
	print("  ring    radii        blue ranks     blue png      bayer 4x4")
	for ring: int in RING_COUNT:
		print("  %d       %2d-%2d      %11.5f%%   %11.5f%%   %11.5f%%" % [
			ring, roundi(float(ring) * RING_WIDTH), roundi(float(ring + 1) * RING_WIDTH),
			100.0 * rank_rings[ring], 100.0 * byte_rings[ring], 100.0 * bayer_rings[ring]
		])
	print("  corner  32+         %11.5f%%   %11.5f%%   %11.5f%%" % [
		100.0 * rank_rings[RING_COUNT], 100.0 * byte_rings[RING_COUNT], 100.0 * bayer_rings[RING_COUNT]
	])

	return {
		"period2": float(shares["2 (x)"]["png"]) + float(shares["2 (y)"]["png"]) + float(shares["2 x 2"]["png"]),
		"bayer_period2": float(shares["2 (x)"]["bayer"]) + float(shares["2 (y)"]["bayer"]) + float(shares["2 x 2"]["bayer"]),
		"period4": float(shares["4 (x)"]["png"]) + float(shares["4 (y)"]["png"]),
		"bayer_period4": float(shares["4 (x)"]["bayer"]) + float(shares["4 (y)"]["bayer"]),
		"ring0": byte_rings[0],
		"ring7": byte_rings[RING_COUNT - 1],
	}


# ----------------------------------------------------------------------------- signals

func _signal_from_ranks(ranks: PackedInt32Array) -> PackedFloat64Array:
	var samples := PackedFloat64Array()
	samples.resize(CELL_COUNT)
	for cell: int in CELL_COUNT:
		# The mean of a permutation of 0..4095 is exactly 2047.5, so this scaling
		# already removes the DC term: the low-frequency rings below start at zero.
		samples[cell] = float(ranks[cell]) / float(CELL_COUNT - 1) - 0.5
	return samples


func _signal_from_bytes(bytes: PackedByteArray) -> PackedFloat64Array:
	var samples := PackedFloat64Array()
	samples.resize(CELL_COUNT)
	var mean := 0.0
	for cell: int in CELL_COUNT:
		samples[cell] = float(bytes[cell]) / 255.0
		mean += samples[cell]
	mean /= float(CELL_COUNT)
	for cell: int in CELL_COUNT:
		# Byte levels are 16-17 ranks wide, so the rounded mean is not exactly 0.5;
		# removing it explicitly keeps the comparison with the rank map honest.
		samples[cell] -= mean
	return samples


func _signal_from_bayer() -> PackedFloat64Array:
	var samples := PackedFloat64Array()
	samples.resize(CELL_COUNT)
	for y: int in TILE_SIZE:
		for x: int in TILE_SIZE:
			var threshold := BAYER_4X4[(y & 3) * 4 + (x & 3)]
			samples[y * TILE_SIZE + x] = (float(threshold) + 0.5) / 16.0 - 0.5
	return samples


## |F(kx, ky)|^2 of a real signal on the 64x64 torus.
##
## The 2D DFT is separable, so it runs as 64 row transforms followed by 64 column
## transforms (about 500k complex multiply-adds) instead of a full 16.7M one. The
## trig tables are indexed by [k * TILE_SIZE + n] because the grid is a power of two.
func _spectrum(samples: PackedFloat64Array) -> PackedFloat64Array:
	var rows_re := PackedFloat64Array()
	var rows_im := PackedFloat64Array()
	rows_re.resize(CELL_COUNT)
	rows_im.resize(CELL_COUNT)
	for y: int in TILE_SIZE:
		var row_base := y * TILE_SIZE
		for frequency: int in TILE_SIZE:
			var table := frequency * TILE_SIZE
			var real := 0.0
			var imaginary := 0.0
			for x: int in TILE_SIZE:
				var value := samples[row_base + x]
				real += value * _cos_table[table + x]
				imaginary -= value * _sin_table[table + x]
			rows_re[row_base + frequency] = real
			rows_im[row_base + frequency] = imaginary
	var energy := PackedFloat64Array()
	energy.resize(CELL_COUNT)
	for frequency_x: int in TILE_SIZE:
		for frequency_y: int in TILE_SIZE:
			var table := frequency_y * TILE_SIZE
			var real := 0.0
			var imaginary := 0.0
			for y: int in TILE_SIZE:
				var cell := y * TILE_SIZE + frequency_x
				var row_re := rows_re[cell]
				var row_im := rows_im[cell]
				var cosine := _cos_table[table + y]
				var sine := _sin_table[table + y]
				# (row_re + i * row_im) * (cosine - i * sine)
				real += row_re * cosine + row_im * sine
				imaginary += row_im * cosine - row_re * sine
			energy[frequency_y * TILE_SIZE + frequency_x] = real * real + imaginary * imaginary
	return energy


func _total_energy(energy: PackedFloat64Array) -> float:
	var total := 0.0
	for index: int in CELL_COUNT:
		total += energy[index]
	return total


func _sum_squares(samples: PackedFloat64Array) -> float:
	var total := 0.0
	for index: int in CELL_COUNT:
		total += samples[index] * samples[index]
	return total


## Energy at one named lattice frequency as a share of the total, counting the
## conjugate mirror bin too (a real signal carries both halves of the same wave).
func _pair_share(energy: PackedFloat64Array, total: float, frequency: Vector2i) -> float:
	if total <= 0.0:
		return 0.0
	var value := energy[frequency.y * TILE_SIZE + frequency.x]
	var mirror := Vector2i(
		(TILE_SIZE - frequency.x) % TILE_SIZE,
		(TILE_SIZE - frequency.y) % TILE_SIZE
	)
	if mirror != frequency:
		value += energy[mirror.y * TILE_SIZE + mirror.x]
	return value / total


## Energy per radial ring. The last slot collects everything at radius >= 32 cycles
## (the four diagonal corners), so the returned shares add up to 1.
func _ring_shares(energy: PackedFloat64Array, total: float) -> PackedFloat64Array:
	var buckets := PackedFloat64Array()
	buckets.resize(RING_COUNT + 1)
	buckets.fill(0.0)
	for frequency_y: int in TILE_SIZE:
		var fy := float(frequency_y if frequency_y <= (TILE_SIZE >> 1) else frequency_y - TILE_SIZE)
		for frequency_x: int in TILE_SIZE:
			var fx := float(frequency_x if frequency_x <= (TILE_SIZE >> 1) else frequency_x - TILE_SIZE)
			var ring := int(floorf(sqrt(fx * fx + fy * fy) / RING_WIDTH))
			buckets[mini(ring, RING_COUNT)] += energy[frequency_y * TILE_SIZE + frequency_x]
	if total > 0.0:
		for ring: int in RING_COUNT + 1:
			buckets[ring] /= total
	return buckets


# ----------------------------------------------------------------------------- helpers

func _spread(values: PackedFloat64Array) -> float:
	var lowest := INF
	var highest := -INF
	for value: float in values:
		lowest = minf(lowest, value)
		highest = maxf(highest, value)
	return highest - lowest


## The cells with the `count` lowest ranks. Ranks are a permutation of 0..4095, so
## "below the threshold" is literally `rank < count`.
func _cells_below(ranks: PackedInt32Array, count: int) -> PackedInt32Array:
	var cells := PackedInt32Array()
	cells.resize(count)
	var filled := 0
	for cell: int in CELL_COUNT:
		if ranks[cell] >= count:
			continue
		if filled < count:
			cells[filled] = cell
			filled += 1
	return cells


## `count` distinct cells drawn uniformly at random: the white-noise reference.
func _random_cells(rng: RandomNumberGenerator, count: int) -> PackedInt32Array:
	var pool := PackedInt32Array()
	pool.resize(CELL_COUNT)
	for cell: int in CELL_COUNT:
		pool[cell] = cell
	for index: int in count:
		var other := index + rng.randi_range(0, CELL_COUNT - 1 - index)
		var held := pool[index]
		pool[index] = pool[other]
		pool[other] = held
	var cells := PackedInt32Array()
	cells.resize(count)
	for index: int in count:
		cells[index] = pool[index]
	return cells


## Mean (x) and standard deviation (y) of the toroidal nearest-neighbour distance.
##
## The search walks outwards in Chebyshev rings. After ring `r` is scanned, every
## unvisited cell is at distance >= r + 1, so the walk can stop as soon as the best
## hit is within r + 1: that keeps a 1024-cell set to a few dozen lookups per cell
## instead of a million distance comparisons, without giving up the guarantee.
func _nearest_neighbour_stats(cells: PackedInt32Array) -> Vector2:
	var count := cells.size()
	if count < 2:
		return Vector2.ZERO
	var mask := PackedByteArray()
	mask.resize(CELL_COUNT)
	mask.fill(0)
	for index: int in count:
		mask[cells[index]] = 1
	var sum := 0.0
	var sum_squared := 0.0
	for index: int in count:
		var cell := cells[index]
		var cx := cell & TILE_MASK
		var cy := cell >> TILE_SHIFT
		var best_squared := INF
		var radius := 1
		while radius <= (TILE_SIZE >> 1):
			for offset_y: int in range(-radius, radius + 1):
				var row := ((cy + offset_y + TILE_SIZE) & TILE_MASK) * TILE_SIZE
				if absi(offset_y) != radius:
					# Only the two x ends of this row are on the ring.
					for offset_x: int in range(-radius, radius + 1, 2 * radius):
						var column := (cx + offset_x + TILE_SIZE) & TILE_MASK
						if mask[row + column] != 0:
							best_squared = minf(best_squared, float(offset_x * offset_x + offset_y * offset_y))
				else:
					for offset_x: int in range(-radius, radius + 1):
						var column := (cx + offset_x + TILE_SIZE) & TILE_MASK
						if mask[row + column] != 0:
							best_squared = minf(best_squared, float(offset_x * offset_x + offset_y * offset_y))
			if best_squared <= float((radius + 1) * (radius + 1)):
				break
			radius += 1
		var distance := sqrt(best_squared)
		sum += distance
		sum_squared += distance * distance
	var mean := sum / float(count)
	var variance := maxf(0.0, sum_squared / float(count) - mean * mean)
	return Vector2(mean, sqrt(variance))

