class_name WaterSimulation
extends RefCounted

## Conservative 1D shallow-water column model for 4 px water columns.
##
## Volume is stored as mass in px^2: depth = mass / column_width, so one column
## holds at most column_width * max_depth px^2. The surface is
## floor - depth - wave_offset because y grows downward. step() runs a fixed
## pipeline: flux pass, capacity pass, clamp pass, wave pass. Every transfer is
## written into a scratch array and applied in a later pass, so total volume is
## conserved and the iteration order cannot bias the flow. All scratch arrays are
## sized in setup(); step() never allocates.

## A wave offset is never allowed to leave this amplitude in pixels.
const MAX_WAVE_OFFSET := 8.0
## Residual flow speed (px/s) that counts as rest for is_active().
const REST_FLOW_VELOCITY := 0.25
## Tolerance for the float dust left by the transfer pass.
const CLAMP_EPSILON := 1e-9
## Extra relax passes that keep a column fed from both sides under capacity.
const CAPACITY_RELAX_PASSES := 2
## A splash shares its wave impulse with this many columns per side.
const WAVE_IMPULSE_REACH := 2

var column_width: float = 4.0
var flow_rate: float = 9.0            # 1/s, surface-head transfer coefficient
var max_flow_speed: float = 240.0     # px/s cap on transfer speed
var max_depth: float = 72.0           # px, per-column capacity
var wave_stiffness: float = 120.0
var wave_damping: float = 7.0
var wave_spread: float = 0.28
var min_active_head: float = 0.02
var min_active_wave: float = 0.05

var _origin_x: float = 0.0
var _floors := PackedFloat32Array()
var _blocked := PackedByteArray()
var _mass := PackedFloat64Array()
var _offset := PackedFloat64Array()
var _offset_velocity := PackedFloat64Array()
var _transfer := PackedFloat64Array()       # pair i -> i + 1, px^2
var _pair_velocity := PackedFloat64Array()  # pair i -> i + 1, px/s
var _flux := PackedFloat64Array()           # per column, px/s
var _delta := PackedFloat64Array()
var _dirty := false
var _active := false


## Rebuilds the column layout. Safe with empty arrays: every query and step
## degrades to a no-op instead of asserting.
func setup(origin: Vector2, floors: PackedFloat32Array, blocked: PackedByteArray) -> void:
	_origin_x = origin.x
	_floors = floors.duplicate()
	_blocked = blocked.duplicate()
	if _blocked.size() != _floors.size():
		_blocked.resize(_floors.size())
	var count := _floors.size()
	_mass.resize(count)
	_mass.fill(0.0)
	_offset.resize(count)
	_offset.fill(0.0)
	_offset_velocity.resize(count)
	_offset_velocity.fill(0.0)
	_flux.resize(count)
	_flux.fill(0.0)
	_delta.resize(count)
	_delta.fill(0.0)
	var pair_count := maxi(count - 1, 0)
	_transfer.resize(pair_count)
	_transfer.fill(0.0)
	_pair_velocity.resize(pair_count)
	_pair_velocity.fill(0.0)
	_dirty = false
	_active = false


func column_count() -> int:
	return _mass.size()


func column_center_x(index: int) -> float:
	return _origin_x + (float(index) + 0.5) * column_width


## Index of the column containing world_x, clamped to the column range.
func column_at(world_x: float) -> int:
	if _mass.is_empty() or column_width <= 0.0 or not is_finite(world_x):
		return 0
	return clampi(int(floor((world_x - _origin_x) / column_width)), 0, _mass.size() - 1)


func get_floor_y(index: int) -> float:
	if index < 0 or index >= _floors.size():
		return 0.0
	return _floors[index]


func get_mass(index: int) -> float:
	if index < 0 or index >= _mass.size():
		return 0.0
	return _mass[index]


## Mass is clamped into [0, capacity]; blocked columns never hold water.
func set_mass(index: int, value: float) -> void:
	if index < 0 or index >= _mass.size():
		return
	if _blocked[index] != 0:
		_mass[index] = 0.0
	else:
		_mass[index] = clampf(value, 0.0, _capacity())
	_dirty = true


func get_depth(index: int) -> float:
	if index < 0 or index >= _mass.size() or column_width <= 0.0:
		return 0.0
	return _mass[index] / column_width


## World y of the water surface. y grows downward, so more water means a smaller
## y. A blocked column reports 0, the same sentinel as an out-of-range index.
func get_surface_y(index: int) -> float:
	if index < 0 or index >= _mass.size() or _blocked[index] != 0:
		return 0.0
	return _floors[index] - get_depth(index) - _offset[index]


func get_surface_at(world_x: float) -> float:
	return get_surface_y(column_at(world_x))


func get_depth_at(world_x: float) -> float:
	return get_depth(column_at(world_x))


## Net horizontal water speed at world_x in px/s, positive = moving right.
func get_flow_velocity_at(world_x: float) -> float:
	if _flux.is_empty():
		return 0.0
	return _flux[column_at(world_x)]


func get_wave_offset(index: int) -> float:
	if index < 0 or index >= _offset.size():
		return 0.0
	return _offset[index]


## Drops volume with a (1 - d/radius) falloff, then seeds a wave impulse. The
## volume is shared by the columns inside the radius only, and blocked columns
## are skipped. Volume that does not fit into a column is dropped rather than
## overflowing it.
func add_splash(world_x: float, radius: float, volume: float, wave_impulse: float) -> void:
	var count := _mass.size()
	if count == 0 or column_width <= 0.0:
		return
	var reach := maxf(radius, column_width * 0.5)
	var first := column_at(world_x - reach)
	var last := column_at(world_x + reach)
	var weight_total := 0.0
	for index in range(first, last + 1):
		weight_total += _splash_weight(index, world_x, reach)
	if volume > 0.0:
		if weight_total > 0.0:
			for index in range(first, last + 1):
				var weight := _splash_weight(index, world_x, reach)
				if weight <= 0.0:
					continue
				_add_mass_capped(index, volume * weight / weight_total)
		else:
			# Degenerate splash exactly between two columns: keep the volume.
			_add_mass_capped(column_at(world_x), volume)
	if wave_impulse != 0.0:
		_seed_wave_impulse(column_at(world_x), first, last, wave_impulse)
	_dirty = true


## Blocking spills the column's volume into its open neighbours (half each when
## both are open) and drops whatever does not fit. Unblocking just marks the
## model dirty so the empty column starts pulling water again.
func set_blocked(index: int, value: bool) -> void:
	if index < 0 or index >= _blocked.size():
		return
	var blocked := 1 if value else 0
	if _blocked[index] == blocked:
		return
	_blocked[index] = blocked
	if blocked != 0:
		_spill_blocked_column(index)
		_offset[index] = 0.0
		_offset_velocity[index] = 0.0
		_flux[index] = 0.0
	_dirty = true


func is_blocked(index: int) -> bool:
	if index < 0 or index >= _blocked.size():
		return false
	return _blocked[index] != 0


func total_volume() -> float:
	var volume := 0.0
	for index in _mass.size():
		volume += _mass[index]
	return volume


func is_active() -> bool:
	return _active


func get_debug_state() -> Dictionary:
	return {
		"columns": column_count(),
		"volume": total_volume(),
		"active": _active,
	}


## Advances the model. Early-outs when nothing is dirty and nothing is active,
## which is the steady-state fast path.
func step(delta: float) -> void:
	if not _dirty and not _active:
		return
	var count := _mass.size()
	if count == 0:
		_dirty = false
		_active = false
		return
	var step_delta := maxf(delta, 0.0)
	_solve_fluxes(step_delta)
	_relax_receiving_capacity()
	_apply_transfers(step_delta)
	_clamp_masses()
	_step_waves(step_delta)
	_update_active_state()
	_dirty = false


## Builds every pairwise transfer. Positive means water moves from column i to
## column i + 1. head is surface(i + 1) - surface(i), so a positive head means
## column i sits higher (less y) and therefore has more water.
func _solve_fluxes(delta: float) -> void:
	var count := _mass.size()
	var pair_count := count - 1
	var capacity := _capacity()
	for index in count:
		_flux[index] = 0.0
	for index in pair_count:
		_transfer[index] = 0.0
		_pair_velocity[index] = 0.0
	if delta <= 0.0 or column_width <= 0.0:
		return
	for index in pair_count:
		var next := index + 1
		if _blocked[index] != 0 or _blocked[next] != 0:
			continue
		var head := _surface_of(next) - _surface_of(index)
		var desired := clampf(flow_rate * head, -max_flow_speed, max_flow_speed) * column_width * delta
		if desired > 0.0:
			desired = minf(desired, _mass[index] * 0.5)
			desired = minf(desired, maxf(capacity - _mass[next], 0.0))
		elif desired < 0.0:
			desired = maxf(desired, -_mass[next] * 0.5)
			desired = maxf(desired, -maxf(capacity - _mass[index], 0.0))
		_transfer[index] = desired
		_pair_velocity[index] = desired / (column_width * delta)


## A column can be fed from both sides, so per-pair limits alone could overflow
## it. Scaling its incident transfers keeps the step inside [0, capacity] without
## losing volume; two passes are enough for a 1D chain.
func _relax_receiving_capacity() -> void:
	var count := _mass.size()
	if count == 0:
		return
	var capacity := _capacity()
	for _pass in CAPACITY_RELAX_PASSES:
		_compute_deltas()
		var scaled := false
		for index in count:
			if _delta[index] <= 0.0:
				continue
			var room := capacity - _mass[index]
			if _delta[index] <= room + CLAMP_EPSILON:
				continue
			var factor := clampf(room / _delta[index], 0.0, 1.0)
			if index > 0:
				_transfer[index - 1] *= factor
			if index < count - 1:
				_transfer[index] *= factor
			scaled = true
		if not scaled:
			return


func _compute_deltas() -> void:
	for index in _delta.size():
		_delta[index] = 0.0
	for index in _transfer.size():
		var transfer := _transfer[index]
		if transfer == 0.0:
			continue
		_delta[index] -= transfer
		_delta[index + 1] += transfer


func _apply_transfers(delta: float) -> void:
	_compute_deltas()
	for index in _mass.size():
		_mass[index] += _delta[index]
	for index in _pair_velocity.size():
		if delta > 0.0 and column_width > 0.0:
			_pair_velocity[index] = _transfer[index] / (column_width * delta)
		else:
			_pair_velocity[index] = 0.0
	_update_fluxes()


func _update_fluxes() -> void:
	var count := _mass.size()
	if count == 0:
		return
	if count == 1:
		_flux[0] = 0.0
		return
	var pair_count := count - 1
	for index in count:
		if index == 0:
			_flux[index] = _pair_velocity[0]
		elif index == pair_count:
			_flux[index] = _pair_velocity[pair_count - 1]
		else:
			_flux[index] = (_pair_velocity[index - 1] + _pair_velocity[index]) * 0.5
	for index in count:
		if _blocked[index] != 0:
			_flux[index] = 0.0


## Transfers are pre-limited to the donor mass and the receiver capacity, so a
## clean step never needs a real clamp. The clamp only removes float dust and
## guarantees the invariant for callers; it must not move volume.
func _clamp_masses() -> void:
	var capacity := _capacity()
	for index in _mass.size():
		if _blocked[index] != 0:
			_mass[index] = 0.0
			continue
		_mass[index] = clampf(_mass[index], 0.0, capacity)


## Visual spring per column: pulled to 0, damped, and loosely coupled to the
## neighbour average. Acceleration uses the old offsets so the pass is
## order-independent; the offsets themselves stay a visual layer only.
func _step_waves(delta: float) -> void:
	var count := _mass.size()
	if count == 0:
		return
	for index in count:
		if _blocked[index] != 0:
			_offset[index] = 0.0
			_offset_velocity[index] = 0.0
			continue
		var neighbour_sum := 0.0
		var neighbour_count := 0
		if index > 0 and _blocked[index - 1] == 0:
			neighbour_sum += _offset[index - 1]
			neighbour_count += 1
		if index + 1 < count and _blocked[index + 1] == 0:
			neighbour_sum += _offset[index + 1]
			neighbour_count += 1
		var average := _offset[index]
		if neighbour_count > 0:
			average = neighbour_sum / float(neighbour_count)
		var accel := (
			-wave_stiffness * _offset[index]
			- wave_damping * _offset_velocity[index]
			+ wave_spread * (average - _offset[index])
		)
		_offset_velocity[index] += accel * delta
	for index in count:
		if _blocked[index] != 0:
			continue
		_offset[index] = clampf(
			_offset[index] + _offset_velocity[index] * delta,
			-MAX_WAVE_OFFSET,
			MAX_WAVE_OFFSET
		)


## Snaps the wave layer to exact zero at rest, then recomputes the activity flag
## from flow, wave amplitude, and any head that can still move water.
func _update_active_state() -> void:
	var count := _mass.size()
	if count == 0:
		_active = false
		return
	var capacity := _capacity()
	for index in count:
		if _blocked[index] != 0:
			continue
		if (
			absf(_offset[index]) <= min_active_wave
			and absf(_offset_velocity[index]) <= min_active_wave
		):
			_offset[index] = 0.0
			_offset_velocity[index] = 0.0
	var active := false
	for index in count:
		if absf(_flux[index]) > REST_FLOW_VELOCITY:
			active = true
		if absf(_offset[index]) > min_active_wave or absf(_offset_velocity[index]) > min_active_wave:
			active = true
	for index in count - 1:
		if _blocked[index] != 0 or _blocked[index + 1] != 0:
			continue
		var head := _surface_of(index + 1) - _surface_of(index)
		if head > min_active_head:
			if _mass[index] > CLAMP_EPSILON and _mass[index + 1] < capacity - CLAMP_EPSILON:
				active = true
		elif head < -min_active_head:
			if _mass[index + 1] > CLAMP_EPSILON and _mass[index] < capacity - CLAMP_EPSILON:
				active = true
	_active = active


func _surface_of(index: int) -> float:
	return _floors[index] - get_depth(index) - _offset[index]


func _capacity() -> float:
	return maxf(column_width, 0.0) * maxf(max_depth, 0.0)


func _add_mass_capped(index: int, volume: float) -> void:
	if index < 0 or index >= _mass.size() or _blocked[index] != 0:
		return
	_mass[index] = minf(_mass[index] + volume, _capacity())


func _splash_weight(index: int, world_x: float, reach: float) -> float:
	if index < 0 or index >= _mass.size() or _blocked[index] != 0:
		return 0.0
	var distance := absf(column_center_x(index) - world_x)
	if distance > reach:
		return 0.0
	return 1.0 - distance / reach


func _seed_wave_impulse(centre: int, first: int, last: int, impulse: float) -> void:
	for index in range(first, last + 1):
		if _blocked[index] != 0:
			continue
		var distance := absi(index - centre)
		if distance > WAVE_IMPULSE_REACH:
			continue
		_offset_velocity[index] += impulse * pow(0.5, float(distance))


func _spill_blocked_column(index: int) -> void:
	var volume := _mass[index]
	_mass[index] = 0.0
	if volume <= 0.0:
		return
	var left := index - 1
	var right := index + 1
	var left_open := left >= 0 and _blocked[left] == 0
	var right_open := right < _mass.size() and _blocked[right] == 0
	if left_open and right_open:
		_add_mass_capped(left, volume * 0.5)
		_add_mass_capped(right, volume * 0.5)
	elif left_open:
		_add_mass_capped(left, volume)
	elif right_open:
		_add_mass_capped(right, volume)
