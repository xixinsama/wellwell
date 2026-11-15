extends Node

## Headless checks for the GridWater cell model: the two things that matter are
## that volume is conserved exactly and that water never climbs.

const GRID_WATER: Script = preload("res://addons/fluid_kit/runtime/water/grid_water.gd")

const CELL := 4.0
const DT := 1.0 / 60.0


func run() -> Array[String]:
	var failures: Array[String] = []
	_assert_queries(failures)
	_assert_fill_excludes_walls(failures)
	_assert_wall_removes_volume(failures)
	_assert_conservation(failures)
	_assert_heights_stay_in_range(failures)
	_assert_basin_levels_out(failures)
	_assert_no_upward_flow(failures)
	_assert_settles_and_sleeps(failures)
	_assert_splash_keeps_volume(failures)
	_assert_empty_setup_is_safe(failures)
	return failures


func _assert_queries(failures: Array[String]) -> void:
	var sim := _make_grid(6, 4)
	sim.origin = Vector2(8.0, 16.0)
	_check(failures, sim.is_valid(), "grid is not valid")
	_check(failures, sim.index_of_cell(Vector2i(2, 1)) == 8, "index_of_cell is wrong")
	_check(failures, sim.index_of_cell(Vector2i(-1, 0)) == -1, "index_of_cell accepted a negative cell")
	_check(failures, sim.cell_of_world(Vector2(8.0, 16.0)) == Vector2i.ZERO, "cell_of_world missed the origin")
	_check(failures, sim.cell_of_world(Vector2(13.9, 19.9)) == Vector2i(1, 0), "cell_of_world missed a cell")
	_check(failures, sim.is_solid(Vector2i(-1, 0)), "outside the grid is not solid")
	_check(failures, sim.is_solid(Vector2i(3, 3)), "the floor cell is not solid")
	_check(failures, not sim.is_solid(Vector2i(3, 2)), "an open cell is solid")
	_check(failures, sim.get_height_cell(Vector2i(3, 3)) == 0.0, "a solid cell holds water")


func _assert_fill_excludes_walls(failures: Array[String]) -> void:
	var sim := _make_grid(8, 6)
	var rect := Rect2i(1, 1, 4, 3)
	var added := sim.fill_rect(rect)
	var open_cells := 0
	for y in range(1, 4):
		for x in range(1, 5):
			if not sim.is_solid(Vector2i(x, y)):
				open_cells += 1
	_check(
		failures,
		absf(added - float(open_cells) * CELL * CELL * CELL) < 0.001,
		"fill_rect added %.3f for %d open cells" % [added, open_cells]
	)
	for y in range(1, 4):
		for x in range(1, 5):
			var expected := 0.0 if sim.is_solid(Vector2i(x, y)) else CELL
			_check(
				failures,
				absf(sim.get_height_cell(Vector2i(x, y)) - expected) < 0.001,
				"cell %d,%d is %.3f instead of %.3f" % [x, y, sim.get_height_cell(Vector2i(x, y)), expected]
			)


func _assert_wall_removes_volume(failures: Array[String]) -> void:
	var open_sim := _make_grid(10, 6)
	var open_volume := open_sim.fill_rect(Rect2i(0, 0, 10, 4))
	var walled_sim := _make_grid(10, 6)
	for y in range(1, 3):
		for x in range(4, 6):
			walled_sim.set_solid(Vector2i(x, y), true)
	var walled_volume := walled_sim.fill_rect(Rect2i(0, 0, 10, 4))
	_check(
		failures,
		walled_volume < open_volume,
		"a wall inside the region did not reduce the volume"
	)
	_check(
		failures,
		absf((open_volume - walled_volume) - 4.0 * CELL * CELL * CELL) < 0.001,
		"the wall removed %.3f instead of %.3f" % [open_volume - walled_volume, 4.0 * CELL * CELL * CELL]
	)


func _assert_conservation(failures: Array[String]) -> void:
	var sim := _make_grid(20, 14)
	sim.fill_rect(Rect2i(2, 1, 6, 5))
	var start := sim.total_volume()
	_check(failures, start > 0.0, "the region held no water")
	for _step in 600:
		sim.step(DT)
	var settled := sim.total_volume()
	var error := absf(settled - start) / start
	_check(failures, error < 0.0001, "600 steps changed the volume by %.4f%%" % (error * 100.0))


func _assert_heights_stay_in_range(failures: Array[String]) -> void:
	var sim := _make_grid(16, 12)
	sim.fill_rect(Rect2i(0, 0, 16, 9))
	for _step in 400:
		sim.step(DT)
	var bad := ""
	for index in sim.width * sim.height:
		var value := sim.get_height_at(index)
		if not is_finite(value) or value < 0.0 or value > CELL + 0.0001:
			bad = "cell %d is %.6f" % [index, value]
			break
	_check(failures, bad.is_empty(), bad)


func _assert_basin_levels_out(failures: Array[String]) -> void:
	var sim := _make_grid(12, 8)
	# One full column against the left wall, standing on the floor at row 7.
	for y in 3:
		sim.set_height_at(y * sim.width, CELL)
	var start := sim.total_volume()
	for _step in 900:
		sim.step(DT)
	_check(failures, not sim.is_active(), "the basin did not settle")
	var height := sim.get_height_cell(Vector2i(0, 6))
	for x in range(1, 12):
		var other := sim.get_height_cell(Vector2i(x, 6))
		_check(
			failures,
			absf(other - height) <= 0.05,
			"column %d settled at %.3f instead of %.3f" % [x, other, height]
		)
	for y in range(0, 6):
		_check(
			failures,
			sim.get_height_cell(Vector2i(6, y)) <= CELL + 0.001,
			"row %d overflowed" % y
		)
	_check(
		failures,
		absf(sim.total_volume() - start) < 0.001,
		"leveling changed the volume"
	)
	var surface := sim.surface_y_at(Vector2(6.0 * CELL + 1.0, 2.0))
	_check(failures, surface != INF, "surface_y_at did not find the pool")
	_check(
		failures,
		absf(surface - (7.0 * CELL - height)) < 0.06,
		"surface_y_at returned %.3f instead of %.3f" % [surface, 7.0 * CELL - height]
	)


func _assert_no_upward_flow(failures: Array[String]) -> void:
	var sim := _make_grid(9, 8)
	sim.set_height_at(6 * sim.width + 4, CELL)
	for _step in 240:
		sim.step(DT)
	for y in range(0, 6):
		_check(
			failures,
			sim.get_height_cell(Vector2i(4, y)) <= 0.0001,
			"water climbed into row %d" % y
		)
	var right_flow := sim.flow_x_at(Vector2(6.0 * CELL, 7.0 * CELL - 1.0))
	_check(failures, absf(right_flow) < 1000.0, "the flow query is not a sane speed")


func _assert_settles_and_sleeps(failures: Array[String]) -> void:
	var sim := _make_grid(10, 6)
	sim.fill_rect(Rect2i(0, 0, 5, 2))
	for _step in 600:
		sim.step(DT)
	_check(failures, not sim.is_active(), "a settled pool stayed active")
	var before := sim.total_height()
	for _step in 60:
		sim.step(DT)
	_check(failures, absf(sim.total_height() - before) < 0.0001, "a sleeping grid still moved")


func _assert_splash_keeps_volume(failures: Array[String]) -> void:
	var sim := _make_grid(16, 8)
	for x in 16:
		for y in range(5, 7):
			sim.set_height_at(y * sim.width + x, CELL)
	var start := sim.total_volume()
	sim.splash(Vector2(8.0 * CELL, 5.5 * CELL), 7.0 * CELL, 2.0)
	var after := sim.total_volume()
	_check(
		failures,
		absf(after - start) / start < 0.0001,
		"a splash changed the volume by %.4f%%" % (absf(after - start) / start * 100.0)
	)
	for _step in 240:
		sim.step(DT)
	_check(
		failures,
		absf(sim.total_volume() - start) / start < 0.0001,
		"the splash did not settle back to the same volume"
	)


func _assert_empty_setup_is_safe(failures: Array[String]) -> void:
	var sim: GridWater = GRID_WATER.new()
	_check(failures, not sim.setup(Vector2i.ZERO, CELL, PackedByteArray()), "empty setup succeeded")
	_check(failures, not sim.is_valid(), "empty grid reports valid")
	sim.step(DT)
	sim.fill_rect(Rect2i(0, 0, 4, 4))
	_check(failures, sim.total_volume() == 0.0, "empty grid holds volume")
	_check(failures, sim.surface_y_at(Vector2.ZERO) == INF, "empty grid returned a surface")
	_check(failures, sim.flow_x_at(Vector2.ZERO) == 0.0, "empty grid returned a flow")


## Builds a grid whose last row is solid: a floor to rest water on.
func _make_grid(width: int, height: int) -> GridWater:
	var solid := PackedByteArray()
	solid.resize(width * height)
	solid.fill(0)
	for x in width:
		solid[(height - 1) * width + x] = 1
	var sim: GridWater = GRID_WATER.new()
	sim.setup(Vector2i(width, height), CELL, solid)
	sim.origin = Vector2.ZERO
	return sim


func _check(failures: Array[String], condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
