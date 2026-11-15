extends Node

## Headless checks for the WaterSimulation column model.
##
## The script is loaded by path and stays the primary reference for the class, so
## the test also runs before the editor has refreshed the global class cache.

const WATER_SIMULATION: Script = preload("res://addons/fluid_kit/runtime/water/water_simulation.gd")

const DT := 1.0 / 60.0
const FLOOR_Y := 180.0


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_queries(failures)
	_assert_conservation(failures)
	_assert_connected_basins_level_out(failures)
	_assert_closed_gate_holds(failures)
	_assert_splash_settles(failures)
	_assert_capacity_and_clamping(failures)
	_assert_settles_and_early_outs(failures)
	_assert_empty_setup_is_safe(failures)
	return failures


func _assert_queries(failures: Array[String]) -> void:
	var floors := PackedFloat32Array([100.0, 100.0, 120.0, 100.0])
	var sim: WaterSimulation = WATER_SIMULATION.new()
	sim.column_width = 4.0
	sim.setup(Vector2(-8.0, 0.0), floors, PackedByteArray([0, 0, 0, 0]))
	_check(failures, sim.column_count() == 4, "column_count did not follow the floor array")
	_check(failures, absf(sim.column_center_x(0) + 6.0) < 0.001, "column_center_x(0) ignored the origin")
	_check(failures, absf(sim.column_center_x(2) - 2.0) < 0.001, "column_center_x(2) is wrong")
	_check(failures, sim.column_at(-100.0) == 0, "column_at clamped a point left of the basin")
	_check(failures, sim.column_at(-8.0) == 0, "column_at missed its left edge")
	_check(failures, sim.column_at(-4.0) == 1, "column_at missed a shared edge")
	_check(failures, sim.column_at(0.0) == 2, "column_at missed a column centre")
	_check(failures, sim.column_at(5.9) == 3, "column_at missed the last column")
	_check(failures, sim.column_at(100.0) == 3, "column_at clamped a point right of the basin")
	_check(failures, absf(sim.get_floor_y(2) - 120.0) < 0.001, "get_floor_y did not return the floor")
	sim.set_mass(2, 40.0)
	_check(failures, absf(sim.get_depth(2) - 10.0) < 0.001, "depth should be mass / column_width")
	_check(failures, absf(sim.get_surface_y(2) - 110.0) < 0.001, "surface should follow mass and floor")
	_check(failures, absf(sim.get_surface_at(2.0) - 110.0) < 0.001, "get_surface_at missed the column")
	_check(failures, absf(sim.get_depth_at(2.0) - 10.0) < 0.001, "get_depth_at missed the column")
	var lower_surface := sim.get_surface_y(2)
	sim.set_mass(2, 100.0)
	_check(failures, sim.get_surface_y(2) < lower_surface - 0.5, "more mass must raise the surface")
	sim.set_blocked(3, true)
	_check(failures, sim.is_blocked(3), "is_blocked did not follow set_blocked")
	_check(failures, sim.get_surface_y(3) == 0.0, "a blocked column must report surface 0")
	var state: Dictionary = sim.get_debug_state()
	_check(failures, int(state.get("columns", -1)) == 4, "debug state is missing the column count")
	_check(failures, absf(float(state.get("volume", -1.0)) - sim.total_volume()) < 0.001, "debug volume disagrees")
	_check(failures, not bool(state.get("active", true)), "a fresh model should not be active")


func _assert_conservation(failures: Array[String]) -> void:
	var sim := _make_basin(6)
	var masses := [12.0, 0.0, 40.0, 7.5, 0.0, 90.0]
	for index in masses.size():
		sim.set_mass(index, masses[index])
	var start_volume := sim.total_volume()
	for _step in 300:
		sim.step(DT)
	_check(
		failures,
		absf(sim.total_volume() - start_volume) <= 0.01,
		"300 steps changed total volume from %.4f to %.4f" % [start_volume, sim.total_volume()]
	)
	var direction := _make_basin(3)
	direction.set_mass(0, 100.0)
	direction.step(DT)
	_check(
		failures,
		direction.get_flow_velocity_at(direction.column_center_x(0)) > 0.0,
		"water on the left should flow to the right"
	)
	direction.step(DT)
	_check(
		failures,
		direction.get_flow_velocity_at(direction.column_center_x(2)) > 0.0,
		"the flow velocity should reach the downstream column"
	)


func _assert_connected_basins_level_out(failures: Array[String]) -> void:
	var sim := _make_basin(7, 3)
	for index in 3:
		sim.set_mass(index, 100.0)
	for _step in 120:
		sim.step(DT)
	_check(failures, sim.get_mass(5) == 0.0, "water crossed a closed gate")
	_check(failures, sim.get_mass(3) == 0.0, "the blocked column held water")
	sim.set_blocked(3, false)
	for _step in 600:
		sim.step(DT)
	var left_surface := sim.get_surface_y(1)
	var middle_surface := sim.get_surface_y(3)
	var right_surface := sim.get_surface_y(5)
	_check(
		failures,
		absf(left_surface - right_surface) <= 0.5,
		"open basins ended %.3f px apart" % absf(left_surface - right_surface)
	)
	_check(
		failures,
		absf(middle_surface - left_surface) <= 0.5,
		"the reopened column ended %.3f px off" % absf(middle_surface - left_surface)
	)
	_check(failures, not sim.is_active(), "a leveled basin should be at rest")


func _assert_closed_gate_holds(failures: Array[String]) -> void:
	var sim := _make_basin(7, 3)
	for index in 3:
		sim.set_mass(index, 120.0)
	var start_volume := sim.total_volume()
	for _step in 300:
		sim.step(DT)
	for index in [4, 5, 6]:
		_check(failures, sim.get_mass(index) == 0.0, "a closed gate leaked into column %d" % index)
	_check(failures, sim.get_mass(3) == 0.0, "the blocked column collected water")
	_check(
		failures,
		absf(sim.total_volume() - start_volume) <= 0.01,
		"a closed gate changed the total volume"
	)


func _assert_splash_settles(failures: Array[String]) -> void:
	var sim := _make_basin(9)
	for index in 9:
		sim.set_mass(index, 40.0)
	var far_surface := sim.get_surface_y(0)
	sim.add_splash(sim.column_center_x(4), 16.0, 80.0, 24.0)
	var local_surface := sim.get_surface_y(4)
	_check(failures, local_surface < far_surface - 0.5, "a splash should raise the local surface")
	for _step in 300:
		sim.step(DT)
	var settled_local := sim.get_surface_y(4)
	var settled_far := sim.get_surface_y(0)
	_check(
		failures,
		absf(settled_local - settled_far) <= 0.5,
		"splash surface stayed %.3f px off equilibrium" % absf(settled_local - settled_far)
	)
	_check(
		failures,
		absf(sim.get_wave_offset(4)) <= 0.5,
		"the wave offset did not decay: %.3f" % absf(sim.get_wave_offset(4))
	)


func _assert_capacity_and_clamping(failures: Array[String]) -> void:
	var sim := _make_basin(5)
	var capacity := sim.column_width * sim.max_depth
	sim.set_mass(0, -50.0)
	sim.set_mass(1, 1000.0)
	sim.add_splash(sim.column_center_x(2), 12.0, 500.0, 80.0)
	var start_volume := sim.total_volume()
	for _step in 300:
		sim.step(DT)
	for index in 5:
		var mass := sim.get_mass(index)
		_check(failures, is_finite(mass), "column %d is not finite" % index)
		_check(failures, mass >= 0.0, "column %d is negative: %.6f" % [index, mass])
		_check(failures, mass <= capacity + 0.0001, "column %d overflowed capacity: %.6f" % [index, mass])
	_check(
		failures,
		absf(sim.total_volume() - start_volume) <= 0.01,
		"capacity handling changed the total volume"
	)
	_check(failures, sim.get_mass(1) <= capacity + 0.0001, "set_mass ignored capacity")
	# Fetch a full pair of columns over-capacity in one step: transfers must be
	# scaled down instead of clamped away, and no volume may be lost.
	var fed := _make_basin(3)
	fed.set_mass(0, capacity)
	fed.set_mass(1, capacity - 8.0)
	fed.set_mass(2, capacity)
	var fed_volume := fed.total_volume()
	fed.step(0.25)
	var fed_ok := true
	for index in 3:
		var mass := fed.get_mass(index)
		fed_ok = fed_ok and is_finite(mass) and mass >= 0.0 and mass <= capacity + 0.0001
	_check(failures, fed_ok, "a column fed from both sides left [0, capacity]")
	_check(
		failures,
		absf(fed.total_volume() - fed_volume) <= 0.01,
		"the two-sided feed lost volume"
	)
	var spilled := _make_basin(5)
	spilled.set_mass(2, 100.0)
	var spill_volume := spilled.total_volume()
	spilled.set_blocked(2, true)
	_check(failures, spilled.get_mass(2) == 0.0, "a blocked column kept its water")
	_check(
		failures,
		absf(spilled.total_volume() - spill_volume) <= 0.01,
		"blocking a wet column lost volume"
	)
	_check(
		failures,
		absf(spilled.get_mass(1) - 50.0) <= 0.01 and absf(spilled.get_mass(3) - 50.0) <= 0.01,
		"blocking did not split the water between the open neighbours"
	)


func _assert_settles_and_early_outs(failures: Array[String]) -> void:
	var sim := _make_basin(5)
	var masses := [120.0, 10.0, 60.0, 0.0, 30.0]
	for index in masses.size():
		sim.set_mass(index, masses[index])
	for _step in 900:
		sim.step(DT)
	_check(failures, not sim.is_active(), "an uneven basin did not settle")
	var settled: Array[float] = []
	for index in 5:
		settled.append(sim.get_mass(index))
	for _step in 120:
		sim.step(DT)
	for index in 5:
		var drift := absf(sim.get_mass(index) - settled[index])
		_check(failures, drift <= 0.0001, "a resting step moved column %d by %.6f" % [index, drift])
	var surface := sim.get_surface_y(0)
	for index in 5:
		_check(
			failures,
			absf(sim.get_surface_y(index) - surface) <= 0.5,
			"settled columns are not level at column %d" % index
		)


func _assert_empty_setup_is_safe(failures: Array[String]) -> void:
	var sim: WaterSimulation = WATER_SIMULATION.new()
	sim.setup(Vector2.ZERO, PackedFloat32Array(), PackedByteArray())
	_check(failures, sim.column_count() == 0, "empty setup produced columns")
	_check(failures, sim.total_volume() == 0.0, "empty setup produced volume")
	_check(failures, not sim.is_active(), "empty setup is active")
	sim.step(DT)
	sim.add_splash(0.0, 10.0, 20.0, 10.0)
	sim.set_mass(0, 5.0)
	sim.set_blocked(0, true)
	_check(failures, sim.get_floor_y(0) == 0.0, "empty setup returned a floor")
	_check(failures, sim.get_surface_y(0) == 0.0, "empty setup returned a surface")
	_check(failures, sim.get_depth(0) == 0.0, "empty setup returned a depth")
	_check(failures, sim.column_at(5.0) == 0, "empty setup returned an index")
	_check(failures, int(sim.get_debug_state().get("columns", -1)) == 0, "empty debug state is wrong")


func _make_basin(count: int, blocked_index: int = -1) -> WaterSimulation:
	var floors := PackedFloat32Array()
	floors.resize(count)
	floors.fill(FLOOR_Y)
	var blocked := PackedByteArray()
	blocked.resize(count)
	blocked.fill(0)
	if blocked_index >= 0 and blocked_index < count:
		blocked[blocked_index] = 1
	var sim: WaterSimulation = WATER_SIMULATION.new()
	sim.column_width = 4.0
	sim.setup(Vector2(0.0, 0.0), floors, blocked)
	return sim


func _check(failures: Array[String], condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
