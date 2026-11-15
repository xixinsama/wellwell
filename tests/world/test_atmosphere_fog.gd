extends Node

## Deterministic checks for the CPU mist field. Fixed delta, no randf().

const DELTA := 1.0 / 30.0
const COLUMNS := 20
const ROWS := 12
const CELL := 8.0
const CENTRE := Vector2(80.0, 48.0)
const FAR_AWAY := Vector2(-400.0, -400.0)


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_setup_and_reset(failures)
	_assert_hero_disturbance(failures)
	_assert_refill_after_hero_leaves(failures)
	_assert_solid_mask(failures)
	_assert_movement_wake(failures)
	_assert_sample_light(failures)
	_assert_settles_and_early_out(failures)
	return failures


func _make_grid() -> FogGrid:
	var grid := FogGrid.new()
	grid.setup(Vector2i(COLUMNS, ROWS), Vector2.ZERO, CELL)
	return grid


func _assert_setup_and_reset(failures: Array[String]) -> void:
	var grid := _make_grid()
	if grid.get_columns() != COLUMNS or grid.get_rows() != ROWS:
		failures.append("setup did not retain the grid size")
	if grid.get_origin() != Vector2.ZERO:
		failures.append("setup did not retain the grid origin")
	grid.reset()
	var total := 0.0
	var count := 0
	for y in ROWS:
		for x in COLUMNS:
			var density := grid.get_density(Vector2i(x, y))
			if not is_finite(density):
				failures.append("reset produced a non-finite density at %d,%d" % [x, y])
				continue
			if density < 0.0 or density > 1.0:
				failures.append("reset density out of range at %d,%d: %.3f" % [x, y, density])
			total += density
			count += 1
	if count > 0:
		var mean := total / float(count)
		if mean < 0.15 or mean > 0.45:
			failures.append("reset mean %.3f is not ambient-ish" % mean)
	if grid.get_velocity_at(CENTRE) != Vector2.ZERO:
		failures.append("reset left residual velocity")
	var empty := FogGrid.new()
	empty.setup(Vector2i.ZERO, Vector2.ZERO, CELL)
	empty.step(DELTA, CENTRE, Vector2(10.0, 0.0))
	if empty.get_density_at(CENTRE) != 0.0:
		failures.append("zero-size grid reported a density")
	if empty.get_velocity_at(CENTRE) != Vector2.ZERO:
		failures.append("zero-size grid reported a velocity")
	if empty.is_active():
		failures.append("zero-size grid reported itself active")


func _assert_hero_disturbance(failures: Array[String]) -> void:
	var grid := _make_grid()
	for i in 30:
		grid.step(DELTA, CENTRE, Vector2.ZERO)
	var near := grid.get_density(Vector2i(10, 6))
	var far := grid.get_density(Vector2i(1, 1))
	if near > far - 0.15:
		failures.append("standing hero did not carve the mist (near %.3f far %.3f)" % [near, far])
	var right := grid.get_velocity_at(CENTRE + Vector2(16.0, 0.0))
	if right.dot(Vector2.RIGHT) <= 0.5:
		failures.append("mist right of the hero is not repelled (%s)" % right)
	var above := grid.get_velocity_at(CENTRE + Vector2(0.0, -16.0))
	if above.dot(Vector2.UP) <= 0.5:
		failures.append("mist above the hero is not repelled (%s)" % above)


func _assert_refill_after_hero_leaves(failures: Array[String]) -> void:
	var near_cell := Vector2i(10, 6)
	var grid := _make_grid()
	var control := _make_grid()
	# Calm air keeps both grids on the same static ambient target.
	grid.wind = Vector2.ZERO
	control.wind = Vector2.ZERO
	for i in 30:
		grid.step(DELTA, CENTRE, Vector2.ZERO)
		control.step(DELTA, FAR_AWAY, Vector2.ZERO)
	for i in 300:
		grid.step(DELTA, FAR_AWAY, Vector2.ZERO)
		control.step(DELTA, FAR_AWAY, Vector2.ZERO)
	var reference := control.get_density(near_cell)
	var restored := grid.get_density(near_cell)
	if reference <= 0.1:
		failures.append("refill control cell stayed empty (%.3f)" % reference)
	if restored < reference * 0.8:
		failures.append("mist did not refill after the hero left (%.3f vs %.3f)" % [restored, reference])


func _assert_solid_mask(failures: Array[String]) -> void:
	var grid := _make_grid()
	var mask := PackedByteArray()
	mask.resize(COLUMNS * ROWS)
	mask.fill(0)
	var solid_cell := Vector2i(5, 3)
	mask[solid_cell.y * COLUMNS + solid_cell.x] = 1
	grid.set_solid_mask(mask)
	for i in 60:
		grid.step(DELTA, FAR_AWAY, Vector2.ZERO)
	if grid.get_density(solid_cell) != 0.0:
		failures.append("solid cell was not forced to exactly zero")
	var neighbour := grid.get_density(Vector2i(solid_cell.x + 1, solid_cell.y))
	if neighbour <= 0.05:
		failures.append("open cell next to the solid cell lost its mist (%.3f)" % neighbour)
	# A short mask is treated as all open.
	grid.set_solid_mask(PackedByteArray())
	grid.reset()
	if grid.get_density(solid_cell) <= 0.0:
		failures.append("a short solid mask left a cell solid")


func _assert_movement_wake(failures: Array[String]) -> void:
	var grid := _make_grid()
	var velocity := Vector2(80.0, 0.0)
	for i in 30:
		var progress := float(i + 1) / 30.0
		grid.step(DELTA, Vector2(40.0 + 80.0 * progress, 48.0), velocity)
	var hero := Vector2(120.0, 48.0)
	var wake := grid.get_density_at(hero - Vector2(20.0, 0.0))
	var ahead := grid.get_density_at(hero + Vector2(30.0, 0.0))
	if wake >= ahead - 0.15:
		failures.append("moving hero left no low-density wake (wake %.3f ahead %.3f)" % [wake, ahead])
	if wake >= 0.3:
		failures.append("wake density %.3f is not depleted" % wake)


func _assert_sample_light(failures: Array[String]) -> void:
	var lights: Array[Dictionary] = [
		{"position": Vector2(50.0, 40.0), "radius": 40.0, "energy": 0.8},
	]
	var centre := FogGrid.sample_light(Vector2(50.0, 40.0), lights)
	if absf(centre - 0.8) > 0.0001:
		failures.append("light centre %.4f is not its energy" % centre)
	var mid := FogGrid.sample_light(Vector2(70.0, 40.0), lights)
	var expected_mid := 0.8 * pow(0.5, 1.6)
	if absf(mid - expected_mid) > 0.0005:
		failures.append("half-radius light %.4f is not %.4f" % [mid, expected_mid])
	var previous := centre
	for step in 8:
		var distance := 40.0 * float(step) / 8.0
		var value := FogGrid.sample_light(Vector2(50.0 + distance, 40.0), lights)
		if value > previous + 0.0001:
			failures.append("light falloff is not monotonic at %.1f px" % distance)
		previous = value
	if FogGrid.sample_light(Vector2(90.0, 40.0), lights) != 0.0:
		failures.append("light leaked past its radius")
	lights.append({"position": Vector2(50.0, 40.0), "radius": 20.0, "energy": 0.5})
	var summed := FogGrid.sample_light(Vector2(50.0, 40.0), lights)
	if absf(summed - 1.3) > 0.0001:
		failures.append("two lights did not sum (%.4f)" % summed)


func _assert_settles_and_early_out(failures: Array[String]) -> void:
	var grid := _make_grid()
	for i in 30:
		grid.step(DELTA, CENTRE, Vector2.ZERO)
	for i in 600:
		grid.step(DELTA, FAR_AWAY, Vector2.ZERO)
	if grid.is_active():
		failures.append("field stayed active after the hero left")
	var before := grid.get_density_values()
	for i in 30:
		grid.step(DELTA, FAR_AWAY, Vector2.ZERO)
	var after := grid.get_density_values()
	var largest := 0.0
	for i in before.size():
		largest = maxf(largest, absf(after[i] - before[i]))
	if largest > 0.0001:
		failures.append("early-out still changed density by %.5f" % largest)
	var rect := grid.get_active_rect()
	if rect.size != Vector2i.ZERO:
		failures.append("early-out reported an active rect %s" % rect)
