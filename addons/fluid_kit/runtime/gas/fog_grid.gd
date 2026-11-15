class_name FogGrid
extends RefCounted

## CPU-side mist density and velocity field for the full-screen fog shader.
##
## The grid is a pure simulation: no scene tree, no rendering, and no
## per-step allocations. The renderer uploads `get_density_values()` for the
## cell rect returned by `get_active_rect()`. A settled field reports
## `is_active() == false`, which lets `step()` early-out until something moves.

## Minimum density delta that counts as a visible change for the active rect.
const CHANGE_EPSILON := 0.0001
## Density distance from the ambient target that keeps the field active.
const ACTIVE_DENSITY_DELTA := 0.01
## Squared velocity (px/s) that keeps the field active (0.5 px/s).
const ACTIVE_VELOCITY_SQ := 0.25
## Cells per value-noise lattice cell. Coarse blobs stay visually stable and
## smooth enough that diffusion and refill can reach a settled equilibrium
## comfortably inside the active threshold.
const NOISE_LATTICE := 18.0
## Integer seed for the deterministic value noise.
const HASH_SEED := 0x9E3779B9

var cell_size: float = 8.0
var ambient_density: float = 0.55
var diffusion: float = 0.10
## Reserved ambient thinning knob. The current model keeps mist mass stable so
## the field can settle; density is governed by `refill_rate` instead.
var dissipation: float = 0.06
var refill_rate: float = 0.45
var push_radius: float = 30.0
var push_strength: float = 140.0
var drag: float = 2.4
var wind: Vector2 = Vector2(6.0, -1.5)

var _columns: int = 0
var _rows: int = 0
var _cell_count: int = 0
var _origin: Vector2 = Vector2.ZERO
var _density := PackedFloat32Array()
var _scratch := PackedFloat32Array()
var _target := PackedFloat32Array()
var _velocity_x := PackedFloat32Array()
var _velocity_y := PackedFloat32Array()
var _solid := PackedByteArray()
var _dirty := false
var _active := false
var _slow_time := 0.0
var _last_player_position := Vector2.ZERO
var _player_seen := false
var _player_near := false
var _active_rect := Rect2i()
var _touch_min_x := 0
var _touch_min_y := 0
var _touch_max_x := -1
var _touch_max_y := -1


## Allocates the field and resets it to the ambient variation.
func setup(size_cells: Vector2i, origin: Vector2, cell_size_px: float) -> void:
	_origin = origin
	cell_size = maxf(cell_size_px, 0.001)
	_columns = maxi(size_cells.x, 0)
	_rows = maxi(size_cells.y, 0)
	_cell_count = _columns * _rows
	_density.resize(_cell_count)
	_scratch.resize(_cell_count)
	_target.resize(_cell_count)
	_velocity_x.resize(_cell_count)
	_velocity_y.resize(_cell_count)
	_solid.resize(_cell_count)
	_solid.fill(0)
	reset()


## Fills open cells with a deterministic ambient variation and clears motion.
func reset() -> void:
	_slow_time = 0.0
	_player_seen = false
	_player_near = false
	if _cell_count == 0:
		_active = false
		_dirty = false
		_active_rect = Rect2i()
		return
	for y in _rows:
		for x in _columns:
			var i := y * _columns + x
			var level := 0.0
			if _solid[i] == 0:
				var noise := _hash_noise(Vector2i(x, y), 0.0)
				level = ambient_density * (0.35 + 0.40 * noise)
			_density[i] = level
			_scratch[i] = level
			_target[i] = level
			_velocity_x[i] = 0.0
			_velocity_y[i] = 0.0
	_active = true
	_dirty = true
	_active_rect = Rect2i(0, 0, _columns, _rows)


## Marks cells solid (1) or open (0). A missing or short mask means all open.
func set_solid_mask(mask: PackedByteArray) -> void:
	var use_mask := _cell_count > 0 and mask.size() >= _cell_count
	for y in _rows:
		for x in _columns:
			var i := y * _columns + x
			var is_solid := use_mask and mask[i] != 0
			_solid[i] = 1 if is_solid else 0
			if is_solid:
				_density[i] = 0.0
				_scratch[i] = 0.0
				_target[i] = 0.0
				_velocity_x[i] = 0.0
				_velocity_y[i] = 0.0
	_dirty = true
	if _cell_count > 0:
		_active_rect = Rect2i(0, 0, _columns, _rows)


## Advances the field by one fixed step (normally 1/30 s).
func step(delta: float, player_position: Vector2, player_velocity: Vector2) -> void:
	if _cell_count == 0 or delta <= 0.0:
		return
	var moved_too_far := _last_player_position.distance_squared_to(player_position) > 0.25
	var player_moved := not _player_seen or moved_too_far
	if not _dirty and not player_moved and not _active:
		_active_rect = Rect2i()
		return
	_dirty = false
	_player_seen = true
	_last_player_position = player_position
	_slow_time += delta
	_player_near = _is_player_near(player_position)
	_begin_tracking()
	_update_targets()
	_apply_player_push(delta, player_position, player_velocity)
	_advect(delta)
	_diffuse(delta)
	_relax_and_damp(delta)
	_finish_tracking()
	_active = _compute_active()


func get_columns() -> int:
	return _columns


func get_rows() -> int:
	return _rows


func get_origin() -> Vector2:
	return _origin


func get_density(cell: Vector2i) -> float:
	if not _is_inside(cell):
		return 0.0
	return _density[cell.y * _columns + cell.x]


func get_density_at(world_position: Vector2) -> float:
	if _cell_count == 0:
		return 0.0
	if not _grid_rect().has_point(world_position):
		return 0.0
	var inverse := 1.0 / maxf(cell_size, 0.001)
	var gx := (world_position.x - _origin.x) * inverse - 0.5
	var gy := (world_position.y - _origin.y) * inverse - 0.5
	return _sample_clamped(gx, gy)


func get_velocity_at(world_position: Vector2) -> Vector2:
	if _cell_count == 0:
		return Vector2.ZERO
	var cell := _world_to_cell(world_position)
	if not _is_inside(cell):
		return Vector2.ZERO
	var i := cell.y * _columns + cell.x
	return Vector2(_velocity_x[i], _velocity_y[i])


## Copy-on-write view of the density field for texture upload.
func get_density_values() -> PackedFloat32Array:
	return _density


func is_active() -> bool:
	return _active


## Cell rect that changed during the last simulated step; empty after early-out.
func get_active_rect() -> Rect2i:
	return _active_rect


## Light falloff shared with the mist shader. The shader must keep this exact
## formula in sync: sum of `energy * pow(clamp(1 - dist / radius, 0, 1), 1.6)`.
static func sample_light(world_position: Vector2, lights: Array[Dictionary]) -> float:
	var total := 0.0
	for light: Dictionary in lights:
		var radius := float(light.get("radius", 0.0))
		if radius <= 0.0:
			continue
		var position: Vector2 = light.get("position", Vector2.ZERO)
		var energy := float(light.get("energy", 0.0))
		var distance := world_position.distance_to(position)
		var falloff := clampf(1.0 - distance / radius, 0.0, 1.0)
		total += energy * pow(falloff, 1.6)
	return total


## Cheap deterministic value noise in [0, 1]. `time` scrolls the sample with the
## wind, so the ambient pattern travels with the air and a still field can reach
## an exact equilibrium with the advection pass.
func _hash_noise(cell: Vector2i, time: float) -> float:
	var drift := wind * (time / maxf(cell_size, 0.001))
	return _value_noise(Vector2(float(cell.x), float(cell.y)) - drift)


func _value_noise(point: Vector2) -> float:
	var gx := point.x / NOISE_LATTICE
	var gy := point.y / NOISE_LATTICE
	var x0 := int(floor(gx))
	var y0 := int(floor(gy))
	var fx := gx - float(x0)
	var fy := gy - float(y0)
	var sx := fx * fx * (3.0 - 2.0 * fx)
	var sy := fy * fy * (3.0 - 2.0 * fy)
	var n00 := _hash2(x0, y0)
	var n10 := _hash2(x0 + 1, y0)
	var n01 := _hash2(x0, y0 + 1)
	var n11 := _hash2(x0 + 1, y0 + 1)
	var top := lerpf(n00, n10, sx)
	var bottom := lerpf(n01, n11, sx)
	return lerpf(top, bottom, sy)


func _hash2(x: int, y: int) -> float:
	var h := x * 374761393 + y * 668265263 + HASH_SEED
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0x7FFFFFFF) / 2147483647.0


func _update_targets() -> void:
	for y in _rows:
		for x in _columns:
			var i := y * _columns + x
			if _solid[i] != 0:
				_target[i] = 0.0
				continue
			var noise := _hash_noise(Vector2i(x, y), _slow_time)
			_target[i] = ambient_density * (0.72 + 0.56 * noise)


func _apply_player_push(delta: float, player_position: Vector2, player_velocity: Vector2) -> void:
	var radius := maxf(push_radius, 0.001)
	var inverse := 1.0 / maxf(cell_size, 0.001)
	var min_x := maxi(0, int(floor((player_position.x - radius - _origin.x) * inverse)))
	var max_x := mini(_columns - 1, int(floor((player_position.x + radius - _origin.x) * inverse)))
	var min_y := maxi(0, int(floor((player_position.y - radius - _origin.y) * inverse)))
	var max_y := mini(_rows - 1, int(floor((player_position.y + radius - _origin.y) * inverse)))
	if min_x > max_x or min_y > max_y:
		return
	var speed := minf(player_velocity.length(), 120.0)
	var erosion := (0.9 + speed * 0.012) * delta * 30.0 * 0.05
	for step_y in (max_y - min_y + 1):
		var y := min_y + step_y
		for step_x in (max_x - min_x + 1):
			var x := min_x + step_x
			var i := y * _columns + x
			if _solid[i] != 0:
				continue
			var offset := _cell_centre(x, y) - player_position
			var distance := offset.length()
			var falloff := 1.0 - clampf(distance / radius, 0.0, 1.0)
			falloff *= falloff
			if falloff <= 0.0:
				continue
			_touch(x, y)
			if distance > 0.0001:
				var direction := offset / distance
				var impulse := push_strength * falloff * delta
				_velocity_x[i] += direction.x * impulse
				_velocity_y[i] += direction.y * impulse
			_density[i] = maxf(_density[i] - falloff * erosion, 0.0)


func _advect(delta: float) -> void:
	var inverse := 1.0 / maxf(cell_size, 0.001)
	for y in _rows:
		for x in _columns:
			var i := y * _columns + x
			if _solid[i] != 0:
				_scratch[i] = 0.0
				continue
			var centre := _cell_centre(x, y)
			var flow := Vector2(_velocity_x[i] + wind.x, _velocity_y[i] + wind.y)
			var sample := centre - flow * delta
			var gx := (sample.x - _origin.x) * inverse - 0.5
			var gy := (sample.y - _origin.y) * inverse - 0.5
			var value := _sample_advected(gx, gy)
			if absf(value - _density[i]) > CHANGE_EPSILON:
				_touch(x, y)
			_scratch[i] = value
	_swap_buffers()


func _diffuse(delta: float) -> void:
	var weight := clampf(diffusion * delta, 0.0, 1.0)
	for y in _rows:
		for x in _columns:
			var i := y * _columns + x
			if _solid[i] != 0:
				_scratch[i] = 0.0
				continue
			var sum := 0.0
			var count := 0
			var left := i - 1
			if x > 0 and _solid[left] == 0:
				sum += _density[left]
				count += 1
			var right := i + 1
			if x < _columns - 1 and _solid[right] == 0:
				sum += _density[right]
				count += 1
			var up := i - _columns
			if y > 0 and _solid[up] == 0:
				sum += _density[up]
				count += 1
			var down := i + _columns
			if y < _rows - 1 and _solid[down] == 0:
				sum += _density[down]
				count += 1
			var value := _density[i]
			if count > 0:
				# Solid neighbours are skipped so no mass flows into the wall and
				# the open field can settle; out-of-bounds edges are closed too.
				value += (sum / float(count) - value) * weight
			if absf(value - _density[i]) > CHANGE_EPSILON:
				_touch(x, y)
			_scratch[i] = value
	_swap_buffers()


func _relax_and_damp(delta: float) -> void:
	var damping := maxf(0.0, 1.0 - drag * delta)
	var relax := clampf(refill_rate * delta, 0.0, 1.0)
	for y in _rows:
		for x in _columns:
			var i := y * _columns + x
			if _solid[i] != 0:
				_density[i] = 0.0
				_velocity_x[i] = 0.0
				_velocity_y[i] = 0.0
				continue
			_velocity_x[i] *= damping
			_velocity_y[i] *= damping
			var value := _density[i]
			var target := _target[i]
			var next := value + (target - value) * relax
			if not is_finite(next):
				next = target
			next = clampf(next, 0.0, 1.0)
			if absf(next - value) > CHANGE_EPSILON:
				_touch(x, y)
			_density[i] = next


func _compute_active() -> bool:
	if _player_near:
		return true
	for y in _rows:
		for x in _columns:
			var i := y * _columns + x
			var vx := _velocity_x[i]
			var vy := _velocity_y[i]
			if vx * vx + vy * vy > ACTIVE_VELOCITY_SQ:
				return true
			if _solid[i] == 0 and absf(_density[i] - _target[i]) > ACTIVE_DENSITY_DELTA:
				return true
	return false


func _sample_advected(gx: float, gy: float) -> float:
	if _columns <= 0 or _rows <= 0:
		return 0.0
	var x0 := int(floor(gx))
	var y0 := int(floor(gy))
	var fx := gx - float(x0)
	var fy := gy - float(y0)
	var x1 := x0 + 1
	var y1 := y0 + 1
	var top := lerpf(_advected_corner(x0, y0), _advected_corner(x1, y0), fx)
	var bottom := lerpf(_advected_corner(x0, y1), _advected_corner(x1, y1), fx)
	return lerpf(top, bottom, fy)


## The grid is a window into open air: outside it the mist keeps its ambient
## level, so the upwind border inhales ambient density instead of mirroring the
## edge cell and the field can settle under wind. Solid cells are no-flux
## boundaries: a sample that reaches into one reuses the adjacent open density,
## because treating it as zero mass would drain mist into walls forever.
func _advected_corner(x: int, y: int) -> float:
	var cx := clampi(x, 0, _columns - 1)
	var cy := clampi(y, 0, _rows - 1)
	var i := cy * _columns + cx
	if x != cx or y != cy:
		return _target[i]
	if _solid[i] == 0:
		return _density[i]
	return _nearest_open_density(cx, cy)


func _nearest_open_density(x: int, y: int) -> float:
	var i := y * _columns + x
	if x > 0 and _solid[i - 1] == 0:
		return _density[i - 1]
	if x < _columns - 1 and _solid[i + 1] == 0:
		return _density[i + 1]
	if y > 0 and _solid[i - _columns] == 0:
		return _density[i - _columns]
	if y < _rows - 1 and _solid[i + _columns] == 0:
		return _density[i + _columns]
	return 0.0


func _sample_clamped(gx: float, gy: float) -> float:
	if _columns <= 0 or _rows <= 0:
		return 0.0
	var x0 := int(floor(gx))
	var y0 := int(floor(gy))
	var fx := gx - float(x0)
	var fy := gy - float(y0)
	var x1 := x0 + 1
	var y1 := y0 + 1
	x0 = clampi(x0, 0, _columns - 1)
	x1 = clampi(x1, 0, _columns - 1)
	y0 = clampi(y0, 0, _rows - 1)
	y1 = clampi(y1, 0, _rows - 1)
	var row0 := y0 * _columns
	var row1 := y1 * _columns
	var top := lerpf(_density[row0 + x0], _density[row0 + x1], fx)
	var bottom := lerpf(_density[row1 + x0], _density[row1 + x1], fx)
	return lerpf(top, bottom, fy)


func _swap_buffers() -> void:
	var temporary := _density
	_density = _scratch
	_scratch = temporary


func _begin_tracking() -> void:
	_touch_min_x = _columns
	_touch_min_y = _rows
	_touch_max_x = -1
	_touch_max_y = -1


func _touch(x: int, y: int) -> void:
	if x < _touch_min_x:
		_touch_min_x = x
	if y < _touch_min_y:
		_touch_min_y = y
	if x > _touch_max_x:
		_touch_max_x = x
	if y > _touch_max_y:
		_touch_max_y = y


func _finish_tracking() -> void:
	if _touch_min_x > _touch_max_x or _touch_min_y > _touch_max_y:
		_active_rect = Rect2i()
		return
	_active_rect = Rect2i(
			_touch_min_x,
			_touch_min_y,
			_touch_max_x - _touch_min_x + 1,
			_touch_max_y - _touch_min_y + 1)


func _cell_centre(x: int, y: int) -> Vector2:
	return _origin + Vector2(float(x) + 0.5, float(y) + 0.5) * cell_size


func _grid_rect() -> Rect2:
	return Rect2(_origin, Vector2(float(_columns), float(_rows)) * cell_size)


func _world_to_cell(world_position: Vector2) -> Vector2i:
	var inverse := 1.0 / maxf(cell_size, 0.001)
	return Vector2i(
			int(floor((world_position.x - _origin.x) * inverse)),
			int(floor((world_position.y - _origin.y) * inverse)))


func _is_inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _columns and cell.y < _rows


func _is_player_near(player_position: Vector2) -> bool:
	return _grid_rect().grow(maxf(push_radius, 0.0)).has_point(player_position)
