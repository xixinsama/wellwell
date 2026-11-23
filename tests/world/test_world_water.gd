extends Node

## Merged test suite. Every inner class below is one original test file,
## kept in its own class so fixtures and helper names stay isolated. Do not
## add logic here: split a class back into its own file when it grows.

## tests/world/test_water_simulation.gd
class WaterSimulationCase extends Node:
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


## tests/world/test_water_grid_room.gd
class WaterGridRoomCase extends Node:
	## Contract test for the baked 2D grid room.
	##
	## It binds a real WaterGrid to the generated room through the same call the world
	## session makes, then checks the three promises of the feature: a wall inside the
	## fluid region removes its volume, the fluid starts where it was authored and
	## stays there until it can flow, and the whole cascade conserves volume while the
	## water travels over the dam and down through the drain hole.

	const ROOM_DATA := preload("res://resources/rooms/generated/water_grid.tres")
	const RUNTIME_SCENE := preload("res://scenes/rooms/generated/water_grid/runtime.tscn")
	const TERRAIN_SCENE := preload("res://scenes/rooms/generated/water_grid/terrain.tscn")
	const OTHER_ROOM := preload("res://resources/rooms/generated/water_hall.tres")
	const OTHER_RUNTIME := preload("res://scenes/rooms/generated/water_hall/runtime.tscn")
	const OTHER_TERRAIN := preload("res://scenes/rooms/generated/water_hall/terrain.tscn")
	const WATER_GRID := preload("res://addons/fluid_kit/runtime/water/water_grid.gd")
	const FLUID_REGION := preload("res://addons/fluid_kit/runtime/water/fluid_region.gd")

	const STEP := 1.0 / 60.0
	## Room-local sample points: the basin, the dam face, the right floor, the pit.
	const BASIN_X := 40.0
	const RIGHT_X := 250.0


	func run() -> Array[String]:
		var failures: Array[String] = []
		_assert_baked_room(failures)
		_assert_room_without_region_is_accepted(failures)
		_assert_grid_flow(failures)
		return failures


	## A room without a FluidRegion must not fail the bind: the world session aborts
	## the whole room load when an extension returns false.
	func _assert_room_without_region_is_accepted(failures: Array[String]) -> void:
		var runtime := OTHER_RUNTIME.instantiate() as Node2D
		var terrain := OTHER_TERRAIN.instantiate() as Node2D
		add_child(runtime)
		add_child(terrain)
		var grid := WATER_GRID.new() as Node2D
		add_child(grid)
		if not bool(grid.call("bind_room_with_origin", OTHER_ROOM, terrain, Vector2i.ZERO)):
			failures.append("water grid rejected a room without a fluid region")
		if bool(grid.call("is_ready")):
			failures.append("water grid is active in a room without a fluid region")
		grid.free()
		runtime.free()
		terrain.free()


	func _assert_baked_room(failures: Array[String]) -> void:
		var runtime := RUNTIME_SCENE.instantiate()
		var region := runtime.find_child("FluidRegionBasin", true, false)
		if region == null:
			failures.append("baked grid room is missing its fluid region")
		elif not (region is FluidRegion):
			failures.append("fluid region was baked with the wrong script")
		else:
			var rect: Rect2 = region.call("get_world_rect")
			if rect.size.x <= 0.0 or rect.size.y <= 0.0:
				failures.append("baked fluid region has no size")
		runtime.free()


	func _assert_grid_flow(failures: Array[String]) -> void:
		var runtime := RUNTIME_SCENE.instantiate() as Node2D
		var terrain := TERRAIN_SCENE.instantiate() as Node2D
		add_child(runtime)
		add_child(terrain)
		var grid := WATER_GRID.new() as Node2D
		add_child(grid)
		if not bool(grid.call("bind_room_with_origin", ROOM_DATA, terrain, Vector2i.ZERO)):
			failures.append("water grid refused to bind to the grid room")
			_cleanup(grid, runtime, terrain)
			return

		var state: Dictionary = grid.call("get_debug_state")
		if not bool(state.get("ready", false)):
			failures.append("water grid is not ready after binding")
		var start_volume := float(state.get("volume", 0.0))
		if start_volume <= 0.0:
			failures.append("water grid started without water")
		var region_volume := float(state.get("region_volume", 0.0))
		if region_volume <= 0.0:
			failures.append("fluid region added no volume")
		# The rock column stands inside the region, so the region holds less than its
		# full box: 17 x 9 tiles, minus 2 x 6 tiles of rock. Volume is an area on this
		# grid, so a full cell is cell_pixels * cell_pixels.
		var cells := float(state.get("region_cells", 0))
		if cells <= 0.0:
			failures.append("fluid region reported no cells")
		var cell_px := float(state.get("cell_pixels", 4.0))
		var empty_volume := cells * cell_px * cell_px
		if start_volume >= empty_volume:
			failures.append(
				"the wall inside the region did not remove volume: %.0f of %.0f" % [start_volume, empty_volume]
			)

		var basin_surface := float(grid.call("get_surface_y_at", BASIN_X))
		if basin_surface == INF:
			failures.append("the basin has no water right after binding")
		if float(grid.call("get_surface_y_at", RIGHT_X)) != INF:
			failures.append("the right side was wet before anything spilled")

		for _frame: int in 600:
			grid.call("_physics_process", STEP)

		var end_state: Dictionary = grid.call("get_debug_state")
		var end_volume := float(end_state.get("volume", 0.0))
		if absf(end_volume - start_volume) > start_volume * 0.001:
			failures.append(
				"the cascade did not conserve volume: start=%.1f end=%.1f" % [start_volume, end_volume]
			)
		var settled_basin := float(grid.call("get_surface_y_at", BASIN_X))
		if settled_basin == INF:
			failures.append("the basin drained completely")
		elif settled_basin <= basin_surface:
			failures.append("the basin surface did not drop while it spilled")
		if float(grid.call("get_surface_y_at", RIGHT_X)) == INF:
			failures.append("water never crossed the dam")
		if float(end_state.get("steps", 0)) <= 0:
			failures.append("the grid never stepped")
		_assert_ripple_lands_on_the_right_body(grid, failures)
		_cleanup(grid, runtime, terrain)


	## A splash must be placed on the water body the impact point is in. Asking by x
	## alone takes the first surface below the ceiling, which in this room is the
	## upper pool: jumping in the lower one then wobbled the upper one, which the hero
	## could never touch.
	func _assert_ripple_lands_on_the_right_body(grid: Node2D, failures: Array[String]) -> void:
		var upper := 60.0
		var lower := 200.0
		var upper_surface := float(grid.call("get_surface_y_at", upper))
		var lower_surface := float(grid.call("get_surface_y_at", lower))
		if upper_surface == INF or lower_surface == INF:
			# One of the two pools is still dry: nothing to compare.
			return
		grid.call("request_splash_at", Vector2(lower, lower_surface + 2.0), 300.0)
		var ripples: Array = grid.get("_ripples")
		if ripples.is_empty():
			failures.append("request_splash_at recorded no ripple")
			return
		var ripple: Vector4 = ripples[0]
		if absf(ripple.y - lower_surface) > 1.0:
			failures.append(
				"a splash at the lower pool was placed at y=%.1f instead of %.1f"
				% [ripple.y, lower_surface]
			)
		if absf(ripple.y - upper_surface) <= 1.0:
			failures.append("a splash at the lower pool landed on the upper pool")
		if absf(ripple.x - lower) > 0.5:
			failures.append("the ripple x did not follow the impact point: %.1f" % ripple.x)


	func _cleanup(grid: Node, runtime: Node, terrain: Node) -> void:
		# Free immediately: a queued-free grid stays in the "water_field" group until
		# the end of the frame, and the next test would resolve it as the active field.
		grid.free()
		runtime.free()
		terrain.free()


## tests/world/test_water_buoyancy.gd
class WaterBuoyancyCase extends Node:
	## Buoyancy, swimming and entry behaviour of the player water component.
	##
	## The component talks to the water field only through is_ready / get_surface_y_at
	## / get_depth_at / get_flow_velocity_at / request_splash, so a stub field is
	## enough to drive it deterministically without a room.

	const PLAYER_WATER_MOTION := preload("res://game/player/player_water_motion.gd")
	const MOVEMENT_CONTEXT := preload("res://addons/platformer_kit/character/motor/movement_context.gd")
	const CHARACTER_INTENT := preload("res://addons/platformer_kit/character/input/character_intent.gd")
	const ENVIRONMENT_SNAPSHOT := preload("res://addons/platformer_kit/character/environment/character_environment_snapshot.gd")
	const PROFILE := preload("res://resources/player/default_player_tuning.tres")

	const STEP := 1.0 / 120.0


	class StubWaterField extends Node2D:
		var surface_y := 100.0
		var flow := 0.0
		var splashes: Array[float] = []

		func is_ready() -> bool:
			return true

		func get_surface_y_at(_world_x: float) -> float:
			return surface_y

		func get_depth_at(_world_x: float) -> float:
			return 80.0

		func get_flow_velocity_at(_world_x: float) -> float:
			return flow

		func request_splash(_world_x: float, impact_speed: float) -> void:
			splashes.append(impact_speed)


	func run() -> Array[String]:
		var failures: Array[String] = []
		_assert_body_floats_to_the_surface(failures)
		_assert_entry_speed_deepens_the_body(failures)
		_assert_shallow_water_leaves_the_motor_alone(failures)
		_assert_surface_hop_leaves_the_water(failures)
		_assert_flow_pushes_the_body_sideways(failures)
		return failures


	func _assert_body_floats_to_the_surface(failures: Array[String]) -> void:
		var rig := _make_rig()
		var body: CharacterBody2D = rig["body"]
		body.global_position = Vector2(0.0, 112.0)
		var context := MOVEMENT_CONTEXT.new()
		var intent := CHARACTER_INTENT.new()
		for _frame: int in 600:
			_step(rig, context, intent)
		var bottom := body.global_position.y
		if bottom < 101.0:
			failures.append("submerged body did not settle near the surface: y=%.2f" % bottom)
		if bottom > 107.0:
			failures.append("body sank instead of floating: y=%.2f" % bottom)
		if absf(body.velocity.y) > 12.0:
			failures.append("floating body still moves vertically: vy=%.2f" % body.velocity.y)
		_free_rig(rig)


	func _assert_entry_speed_deepens_the_body(failures: Array[String]) -> void:
		var rig := _make_rig()
		var body: CharacterBody2D = rig["body"]
		var field: StubWaterField = rig["field"]
		var context := MOVEMENT_CONTEXT.new()
		var intent := CHARACTER_INTENT.new()
		var fast := _entry_velocity(rig, context, intent, 300.0)
		if field.splashes.is_empty():
			failures.append("fast water entry did not request a splash")
		elif field.splashes[0] < 200.0:
			failures.append("fast entry splash used the impact speed poorly: %.1f" % field.splashes[0])
		var slow := _entry_velocity(rig, context, intent, 80.0)
		if fast <= slow + 20.0:
			failures.append(
				"entry depth did not follow impact speed: fast=%.1f slow=%.1f" % [fast, slow]
			)
		_free_rig(rig)


	func _assert_shallow_water_leaves_the_motor_alone(failures: Array[String]) -> void:
		var rig := _make_rig()
		var body: CharacterBody2D = rig["body"]
		body.global_position = Vector2(0.0, 100.4)
		var context := MOVEMENT_CONTEXT.new()
		var intent := CHARACTER_INTENT.new()
		var handled := _step(rig, context, intent)
		if handled:
			failures.append("shallow water claimed the frame from the normal motor")
		var motion: Node2D = rig["motion"]
		if bool(motion.call("is_in_water")):
			failures.append("shallow water reported the body as swimming")
		_free_rig(rig)


	func _assert_surface_hop_leaves_the_water(failures: Array[String]) -> void:
		var rig := _make_rig()
		var body: CharacterBody2D = rig["body"]
		body.global_position = Vector2(0.0, 102.0)
		var context := MOVEMENT_CONTEXT.new()
		var intent := CHARACTER_INTENT.new()
		for _frame: int in 4:
			_step(rig, context, intent)
		intent.jump_pressed = true
		var handled := _step(rig, context, intent)
		if not handled:
			failures.append("surface hop did not claim the frame")
		if context.velocity.y >= -150.0:
			failures.append("surface hop did not push the body up: vy=%.2f" % context.velocity.y)
		if not bool(context.just_jumped):
			failures.append("surface hop did not report just_jumped")
		_free_rig(rig)


	func _assert_flow_pushes_the_body_sideways(failures: Array[String]) -> void:
		var rig := _make_rig()
		var body: CharacterBody2D = rig["body"]
		var field: StubWaterField = rig["field"]
		field.flow = 60.0
		body.global_position = Vector2(0.0, 102.0)
		var context := MOVEMENT_CONTEXT.new()
		var intent := CHARACTER_INTENT.new()
		for _frame: int in 40:
			_step(rig, context, intent)
		if context.velocity.x <= 0.0:
			failures.append("water flow did not push the body downstream: vx=%.2f" % context.velocity.x)
		_free_rig(rig)


	func _entry_velocity(
		rig: Dictionary,
		context: RefCounted,
		intent: RefCounted,
		impact: float
	) -> float:
		var body: CharacterBody2D = rig["body"]
		var motion: Node2D = rig["motion"]
		motion.call("reset")
		body.global_position = Vector2(0.0, 104.0)
		body.velocity = Vector2(0.0, impact)
		context.set("velocity", body.velocity)
		context.set("just_jumped", false)
		motion.call("step", context, intent, ENVIRONMENT_SNAPSHOT.new(), PROFILE, STEP)
		body.velocity = Vector2(context.get("velocity"))
		return body.velocity.y


	func _step(rig: Dictionary, context: RefCounted, intent: RefCounted) -> bool:
		var body: CharacterBody2D = rig["body"]
		var motion: Node2D = rig["motion"]
		context.set("velocity", body.velocity)
		var handled := bool(motion.call("step", context, intent, ENVIRONMENT_SNAPSHOT.new(), PROFILE, STEP))
		if handled:
			body.velocity = Vector2(context.get("velocity"))
		else:
			# Stand in for the movement motor while the body is out of the water.
			body.velocity.y = minf(body.velocity.y + float(PROFILE.get("gravity")) * STEP, float(PROFILE.get("max_fall_speed")))
			body.velocity.x *= 0.99
		body.global_position += body.velocity * STEP
		return handled


	func _make_rig() -> Dictionary:
		var field := StubWaterField.new()
		add_child(field)
		field.add_to_group(&"water_field")
		var body := CharacterBody2D.new()
		var collision := CollisionShape2D.new()
		collision.name = "CollisionShape2D"
		var rectangle := RectangleShape2D.new()
		rectangle.size = Vector2(6.0, 6.0)
		collision.shape = rectangle
		collision.position = Vector2(0.0, -3.0)
		body.add_child(collision)
		add_child(body)
		var motion := PLAYER_WATER_MOTION.new() as Node2D
		motion.name = "WaterMotion"
		body.add_child(motion)
		return {"field": field, "body": body, "motion": motion}


	func _free_rig(rig: Dictionary) -> void:
		var body: CharacterBody2D = rig["body"]
		var field: Node2D = rig["field"]
		field.remove_from_group(&"water_field")
		field.queue_free()
		body.queue_free()


## tests/world/test_water_ripple_reach.gd
class WaterRippleReachCase extends Node:
	## Regression test for the shape of the visible ripple on the 2D grid water.
	##
	## The landing never displaces the simulated body: the wobble is drawn by
	## `water_grid.gdshader` from three ripple slots. Two things about that wave are easy
	## to get wrong and both were wrong before:
	##
	##   1. a crest has to *travel*. The old model multiplied a static distance envelope by
	##      `cos(distance - speed * age)`, which at small ages puts every column at nearly
	##      the same phase, so the whole body lifted at once and the far side started
	##      moving before the crest could physically reach it;
	##   2. a crest has to come back off the walls of the body. There was no reflection at
	##      all, so a pool never answered back.
	##
	## This test binds a real `WaterGrid` to the light lab room, splashes at the left end of
	## the floor puddle and asserts the arrival order, the echo off the far wall, that the
	## walls are the measured body edges, and that the three surface layers move in order.

	const ROOM_DATA := preload("res://resources/rooms/generated/light_lab.tres")
	const RUNTIME_SCENE := preload("res://scenes/rooms/generated/light_lab/runtime.tscn")
	const TERRAIN_SCENE := preload("res://scenes/rooms/generated/light_lab/terrain.tscn")
	const WATER_GRID := preload("res://addons/fluid_kit/runtime/water/water_grid.gd")

	## The room is placed in the test world at this chunk, so the baked room content has
	## to live at the same world origin the world session uses.
	const ORIGIN_CHUNK := Vector2i(3, 0)
	const STEP := 1.0 / 60.0
	## Frames to let the pool overflow its rim and fill the floor puddle.
	const SETTLE_STEPS := 600
	## Landing speed of a hero jumping into water, px/s.
	const IMPACT_SPEED := 300.0
	## A displacement below this is under half a rendered pixel: invisible, so a column
	## "has not moved" as far as the player is concerned.
	const VISIBLE_OFFSET := 0.5
	## Surfaces further apart than this are different water bodies.
	const BODY_LEVEL_TOLERANCE := 6.0
	## The widest body of this room (the floor puddle), so a room edit is caught here.
	const BODY_MINIMUM := 150.0
	## Tolerance on a predicted crest time, in seconds.
	const TIME_TOLERANCE := 0.08


	func run() -> Array[String]:
		var failures: Array[String] = []
		_assert_crest_travels_and_echoes(failures)
		return failures


	func _assert_crest_travels_and_echoes(failures: Array[String]) -> void:
		var runtime := RUNTIME_SCENE.instantiate() as Node2D
		var terrain := TERRAIN_SCENE.instantiate() as Node2D
		var origin := Vector2(ORIGIN_CHUNK) * WATER_GRID.CHUNK_PIXELS
		runtime.position = origin
		terrain.position = origin
		add_child(runtime)
		add_child(terrain)
		var grid := WATER_GRID.new() as Node2D
		add_child(grid)
		if not bool(grid.call("bind_room_with_origin", ROOM_DATA, terrain, ORIGIN_CHUNK)):
			failures.append("water grid refused to bind to the light lab room")
			_cleanup(grid, runtime, terrain)
			return
		for _step: int in SETTLE_STEPS:
			grid.call("_physics_process", STEP)

		var bodies := _find_bodies(grid)
		if bodies.is_empty():
			failures.append("the light lab room has no water body after settling")
			_cleanup(grid, runtime, terrain)
			return
		var body := bodies[0]
		for candidate: Rect2 in bodies:
			if candidate.size.x > body.size.x:
				body = candidate
		if body.size.x < BODY_MINIMUM:
			failures.append("the widest lab body is only %.0f px, the room changed" % body.size.x)

		var cell := float(grid.get("cell_pixels"))
		var impact := body.position.x + cell * 0.5
		var surface := float(grid.call("get_surface_y_at", impact))
		if surface == INF:
			failures.append("the widest body has no surface at its left end")
			_cleanup(grid, runtime, terrain)
			return
		grid.call("request_splash_at", Vector2(impact, surface + 1.0), IMPACT_SPEED)

		var ripples: Array = grid.get("_ripples")
		if ripples.is_empty():
			failures.append("a landing recorded no ripple")
			_cleanup(grid, runtime, terrain)
			return
		var record: Vector4 = ripples[0]
		var span := _span(grid)
		var reach := _reach(grid)
		var speed := float(grid.get("ripple_speed"))
		var amplitude := float(grid.get("ripple_amplitude"))
		var damping := float(grid.get("ripple_damping"))

		# The walls are the measured edges of the body the splash landed in.
		if span.x > body.position.x + cell * 2.0 or span.y < body.end.x - cell * 2.0:
			failures.append(
				"the ripple walls %.0f..%.0f do not match the %.0f..%.0f body" %
				[span.x, span.y, body.position.x, body.end.x]
			)
		if reach < body.size.x * 0.9:
			failures.append(
				"the ripple reach %.0f px does not span the %.0f px body" % [reach, body.size.x]
			)

		# 1. Arrival order: the crest starts at the impact and reaches the far end later.
		var near_x := impact + 8.0
		var far_x := body.end.x - 6.0
		var near_arrival := WaterRipple.arrival(absf(near_x - impact), speed)
		var far_arrival := WaterRipple.arrival(absf(far_x - impact), speed)
		var early := near_arrival + 0.10
		if absf(_offset(early, near_x, record, span, speed, reach, amplitude, damping)) < VISIBLE_OFFSET:
			failures.append("the column next to the landing had not moved by %.2f s" % early)
		if early >= far_arrival and absf(
			_offset(early, far_x, record, span, speed, reach, amplitude, damping)
		) < VISIBLE_OFFSET:
			failures.append("the far column should already have moved by %.2f s" % early)
		if far_arrival > early + 0.2:
			if absf(_offset(early, far_x, record, span, speed, reach, amplitude, damping)) != 0.0:
				failures.append(
					"the far column moved at %.2f s, but its crest only arrives at %.2f s" %
					[early, far_arrival]
				)
		if absf(_offset(
			far_arrival + 0.25, far_x, record, span, speed, reach, amplitude, damping
		)) < VISIBLE_OFFSET:
			failures.append("the far column never moved, the crest did not reach the far wall")

		# 2. Reflection: the crest that hits the far wall comes back. Pick a column a third
		# of the body away from that wall, so the direct crest and the echo are separated.
		var wall := span.y
		var echo_x := wall - body.size.x / 3.0
		var direct_distance := absf(echo_x - impact)
		var echo_distance := absf(echo_x - (2.0 * wall - impact))
		var echo_arrival := WaterRipple.arrival(echo_distance, speed)
		if echo_arrival < WaterRipple.arrival(direct_distance, speed) + 0.25:
			failures.append(
				"the test column is too close to the wall to separate the echo (%.2f s)" % echo_arrival
			)
		if absf(_image_offset(
			echo_arrival - 0.10, echo_x, impact, wall, record, speed, reach, amplitude, damping
		)) != 0.0:
			failures.append("the echo arrived at %.2f s, before its crest" % (echo_arrival - 0.10))
		if absf(_image_offset(
			echo_arrival + 0.25, echo_x, impact, wall, record, speed, reach, amplitude, damping
		)) < VISIBLE_OFFSET:
			failures.append("no echo came back off the far wall")
		# The reflected aportation has to be visible in the total, not just in its own term.
		var total_at_echo := _offset(
			echo_arrival + 0.20, echo_x, record, span, speed, reach, amplitude, damping
		)
		var direct_at_echo := WaterRipple.body_offset_at(
			echo_arrival + 0.20, echo_x, impact, span, speed, reach, record.w, amplitude, damping, 0.0
		)
		if absf(total_at_echo - direct_at_echo) < VISIBLE_OFFSET:
			failures.append("the echo does not reach the surface at %.2f s" % (echo_arrival + 0.2))

		# 3. The three layers move one after the other, front first.
		var layers := _layer_first_motion(echo_x, record, span, speed, reach, amplitude, damping)
		if not (layers[2] < layers[1] and layers[1] < layers[0]):
			failures.append(
				"the layer crests do not arrive back to front: %s" % str(layers)
			)
		if absf(layers[1] - (WaterRipple.arrival(direct_distance, speed))) > TIME_TOLERANCE:
			failures.append(
				"the middle layer arrived at %.2f s instead of %.2f s" %
				[layers[1], WaterRipple.arrival(direct_distance, speed)]
			)
		_cleanup(grid, runtime, terrain)


	func _offset(
		age: float, world_x: float, record: Vector4, span: Vector2,
		speed: float, reach: float, amplitude: float, damping: float
	) -> float:
		return WaterRipple.body_offset_at(
			age, world_x, record.x, span, speed, reach, record.w, amplitude, damping
		)


	## Displacement of the mirror image of the impact across `wall`: the echo alone.
	func _image_offset(
		age: float, world_x: float, impact: float, wall: float, record: Vector4,
		speed: float, reach: float, amplitude: float, damping: float
	) -> float:
		return WaterRipple.offset_at(
			age, absf(world_x - (2.0 * wall - impact)), speed, reach, record.w, amplitude, damping
		)


	## First time each layer's crest lifts its column above the visibility threshold.
	func _layer_first_motion(
		world_x: float, record: Vector4, span: Vector2,
		speed: float, reach: float, amplitude: float, damping: float
	) -> Array[float]:
		var first: Array[float] = []
		for layer in 3:
			var age := 0.0
			var found := INF
			while age <= 4.0:
				var offset := WaterRipple.layer_offset_at(
					layer, age, world_x, record.x, span, speed, reach, record.w, amplitude, damping
				)
				if absf(offset) >= VISIBLE_OFFSET:
					found = age
					break
				age += 0.01
			first.append(found)
		return first


	func _span(grid: Node2D) -> Vector2:
		if not grid.has_method("get_ripple_span"):
			return Vector2.ZERO
		return grid.call("get_ripple_span", 0) as Vector2


	func _reach(grid: Node2D) -> float:
		if not grid.has_method("get_ripple_reach"):
			return 0.0
		return float(grid.call("get_ripple_reach", 0))


	## Contiguous columns at one surface level: one water body per entry.
	func _find_bodies(grid: Node2D) -> Array[Rect2]:
		var bodies: Array[Rect2] = []
		var room: Rect2 = grid.call("get_room_rect")
		var step := float(grid.get("cell_pixels"))
		var current := Rect2()
		for column in int(room.size.x / step):
			var world_x := room.position.x + (float(column) + 0.5) * step
			var surface := float(grid.call("get_surface_y_at", world_x))
			if surface == INF:
				if current.size.x > 0.0:
					bodies.append(current)
					current = Rect2()
				continue
			if current.size.x > 0.0 and absf(surface - current.position.y) > BODY_LEVEL_TOLERANCE:
				bodies.append(current)
				current = Rect2()
			if current.size.x <= 0.0:
				current = Rect2(world_x, surface, step, 1.0)
			else:
				current.size.x = world_x + step - current.position.x
		if current.size.x > 0.0:
			bodies.append(current)
		return bodies


	func _cleanup(grid: Node, runtime: Node, terrain: Node) -> void:
		# Free immediately: a queued-free grid stays in the "water_field" group until the
		# end of the frame, and the next test would resolve it as the active field.
		grid.free()
		runtime.free()
		terrain.free()


## tests/world/test_water_surface_ripple_reach.gd
class WaterSurfaceRippleReachCase extends Node:
	## Regression test for the shape of the visible ripple on the 1D basin water.
	##
	## A landing never displaces a basin: the wobble is drawn by
	## `water_surface.gdshader` from three ripple slots, and two things about that wave were
	## wrong before:
	##
	##   1. a crest has to *travel*. The old model multiplied a static distance envelope by
	##      `cos(distance - speed * age)`, so at small ages every column had nearly the same
	##      phase: the whole basin lifted at once and the far end moved before the crest
	##      could reach it;
	##   2. a crest has to come back off the walls of the basin, and there was no
	##      reflection at all.
	##
	## `WaterField` measures the basin under the impact from the simulation and hands its
	## walls and width to the shader, so the test can predict both the arrival time and the
	## echo time. It asserts them on the water cascade's long lower basin, the widest body
	## of the baked basin rooms (208 px).

	const ROOM_DATA := preload("res://resources/rooms/generated/water_cascade.tres")
	const RUNTIME_SCENE := preload("res://scenes/rooms/generated/water_cascade/runtime.tscn")
	const TERRAIN_SCENE := preload("res://scenes/rooms/generated/water_cascade/terrain.tscn")
	const WATER_FIELD := preload("res://addons/fluid_kit/runtime/water/water_field.gd")

	## The room is placed in the test world at this chunk, so the baked room content has
	## to live at the same world origin the world session uses.
	const ORIGIN_CHUNK := Vector2i(0, 2)
	const STEP := 1.0 / 120.0
	## Frames to let the cascade basins settle.
	const SETTLE_STEPS := 1200
	## Landing speed of a hero jumping into water, px/s.
	const IMPACT_SPEED := 300.0
	## A displacement below this is under half a rendered pixel: invisible, so a column
	## "has not moved" as far as the player is concerned.
	const VISIBLE_OFFSET := 0.5
	## Surfaces further apart than this are different water bodies.
	const BODY_LEVEL_TOLERANCE := 16.0
	## The widest body of this room, so a room edit is caught here.
	const BODY_MINIMUM := 150.0
	## Tolerance on a predicted crest time, in seconds.
	const TIME_TOLERANCE := 0.08


	func run() -> Array[String]:
		var failures: Array[String] = []
		_assert_crest_travels_and_echoes(failures)
		return failures


	func _assert_crest_travels_and_echoes(failures: Array[String]) -> void:
		var runtime := RUNTIME_SCENE.instantiate() as Node2D
		var terrain := TERRAIN_SCENE.instantiate() as Node2D
		var origin := Vector2(ORIGIN_CHUNK) * WATER_FIELD.CHUNK_PIXELS
		runtime.position = origin
		terrain.position = origin
		add_child(runtime)
		add_child(terrain)
		var field := WATER_FIELD.new() as Node2D
		add_child(field)
		if not bool(field.call("bind_room_with_origin", ROOM_DATA, terrain, ORIGIN_CHUNK)):
			failures.append("water field refused to bind to the water cascade room")
			_cleanup(field, runtime, terrain)
			return
		for _step: int in SETTLE_STEPS:
			field.call("_physics_process", STEP)

		var bodies := _find_bodies(field)
		if bodies.is_empty():
			failures.append("the water cascade room has no water body after settling")
			_cleanup(field, runtime, terrain)
			return
		var body := bodies[0]
		for candidate: Rect2 in bodies:
			if candidate.size.x > body.size.x:
				body = candidate
		if body.size.x < BODY_MINIMUM:
			failures.append("the widest cascade body is only %.0f px, the room changed" % body.size.x)

		var column_width := float(WATER_FIELD.COLUMN_WIDTH)
		var impact := body.position.x + column_width * 0.5
		var surface := float(field.call("get_surface_y_at", impact))
		if surface == INF:
			failures.append("the widest body has no surface at its left end")
			_cleanup(field, runtime, terrain)
			return
		field.call("request_splash", impact, IMPACT_SPEED)

		var ripples: Array = field.get("_ripples")
		if ripples.is_empty():
			failures.append("a landing recorded no ripple")
			_cleanup(field, runtime, terrain)
			return
		var record: Vector4 = ripples[0]
		var span := _span(field)
		var reach := _reach(field)
		var speed := float(WATER_FIELD.RIPPLE_SPEED)
		var amplitude := float(WATER_FIELD.RIPPLE_AMPLITUDE)
		var damping := float(WATER_FIELD.RIPPLE_DAMPING)

		# The walls are the measured edges of the body the splash landed in.
		if span.x > body.position.x + column_width * 2.0 \
				or span.y < body.end.x - column_width * 2.0:
			failures.append(
				"the ripple walls %.0f..%.0f do not match the %.0f..%.0f body" %
				[span.x, span.y, body.position.x, body.end.x]
			)
		if reach < body.size.x * 0.9:
			failures.append(
				"the ripple reach %.0f px does not span the %.0f px body" % [reach, body.size.x]
			)

		# 1. Arrival order: the crest starts at the impact and reaches the far end later.
		var near_x := impact + column_width
		var far_x := body.end.x - column_width * 0.5
		var near_arrival := WaterRipple.arrival(absf(near_x - impact), speed)
		var far_arrival := WaterRipple.arrival(absf(far_x - impact), speed)
		var early := near_arrival + 0.10
		if absf(_offset(early, near_x, record, span, speed, reach, amplitude, damping)) < VISIBLE_OFFSET:
			failures.append("the column next to the landing had not moved by %.2f s" % early)
		if far_arrival > early + 0.2:
			if absf(_offset(early, far_x, record, span, speed, reach, amplitude, damping)) != 0.0:
				failures.append(
					"the far column moved at %.2f s, but its crest only arrives at %.2f s" %
					[early, far_arrival]
				)
		if absf(_offset(
			far_arrival + 0.25, far_x, record, span, speed, reach, amplitude, damping
		)) < VISIBLE_OFFSET:
			failures.append("the far column never moved, the crest did not reach the far wall")

		# 2. Reflection: the crest that hits the far wall comes back.
		var wall := span.y
		var echo_x := wall - body.size.x / 3.0
		var direct_distance := absf(echo_x - impact)
		var echo_distance := absf(echo_x - (2.0 * wall - impact))
		var echo_arrival := WaterRipple.arrival(echo_distance, speed)
		if echo_arrival < WaterRipple.arrival(direct_distance, speed) + 0.25:
			failures.append(
				"the test column is too close to the wall to separate the echo (%.2f s)" % echo_arrival
			)
		if absf(_image_offset(
			echo_arrival - 0.10, echo_x, impact, wall, record, speed, reach, amplitude, damping
		)) != 0.0:
			failures.append("the echo arrived at %.2f s, before its crest" % (echo_arrival - 0.10))
		if absf(_image_offset(
			echo_arrival + 0.25, echo_x, impact, wall, record, speed, reach, amplitude, damping
		)) < VISIBLE_OFFSET:
			failures.append("no echo came back off the far wall")
		var total_at_echo := _offset(
			echo_arrival + 0.20, echo_x, record, span, speed, reach, amplitude, damping
		)
		var direct_at_echo := WaterRipple.body_offset_at(
			echo_arrival + 0.20, echo_x, impact, span, speed, reach, record.w, amplitude, damping, 0.0
		)
		if absf(total_at_echo - direct_at_echo) < VISIBLE_OFFSET:
			failures.append("the echo does not reach the surface at %.2f s" % (echo_arrival + 0.2))

		# 3. The three layers move one after the other, front first.
		var layers := _layer_first_motion(echo_x, record, span, speed, reach, amplitude, damping)
		if not (layers[2] < layers[1] and layers[1] < layers[0]):
			failures.append("the layer crests do not arrive back to front: %s" % str(layers))
		if absf(layers[1] - WaterRipple.arrival(direct_distance, speed)) > TIME_TOLERANCE:
			failures.append(
				"the middle layer arrived at %.2f s instead of %.2f s" %
				[layers[1], WaterRipple.arrival(direct_distance, speed)]
			)
		_cleanup(field, runtime, terrain)


	func _offset(
		age: float, world_x: float, record: Vector4, span: Vector2,
		speed: float, reach: float, amplitude: float, damping: float
	) -> float:
		return WaterRipple.body_offset_at(
			age, world_x, record.x, span, speed, reach, record.w, amplitude, damping
		)


	## Displacement of the mirror image of the impact across `wall`: the echo alone.
	func _image_offset(
		age: float, world_x: float, impact: float, wall: float, record: Vector4,
		speed: float, reach: float, amplitude: float, damping: float
	) -> float:
		return WaterRipple.offset_at(
			age, absf(world_x - (2.0 * wall - impact)), speed, reach, record.w, amplitude, damping
		)


	## First time each layer's crest lifts its column above the visibility threshold.
	func _layer_first_motion(
		world_x: float, record: Vector4, span: Vector2,
		speed: float, reach: float, amplitude: float, damping: float
	) -> Array[float]:
		var first: Array[float] = []
		for layer in 3:
			var age := 0.0
			var found := INF
			while age <= 4.0:
				var offset := WaterRipple.layer_offset_at(
					layer, age, world_x, record.x, span, speed, reach, record.w, amplitude, damping
				)
				if absf(offset) >= VISIBLE_OFFSET:
					found = age
					break
				age += 0.01
			first.append(found)
		return first


	func _span(field: Node2D) -> Vector2:
		if not field.has_method("get_ripple_span"):
			return Vector2.ZERO
		return field.call("get_ripple_span", 0) as Vector2


	func _reach(field: Node2D) -> float:
		if not field.has_method("get_ripple_reach"):
			return 0.0
		return float(field.call("get_ripple_reach", 0))


	## Contiguous wet columns at one surface level: one water body per entry.
	func _find_bodies(field: Node2D) -> Array[Rect2]:
		var bodies: Array[Rect2] = []
		var cell := float(WATER_FIELD.COLUMN_WIDTH)
		var current := Rect2()
		var index := 0
		while true:
			var column: Dictionary = field.call("get_column_debug", index)
			if column.is_empty():
				break
			index += 1
			var wet := not bool(column.get("blocked", false)) \
					and float(column.get("depth", 0.0)) > 0.02
			if not wet:
				if current.size.x > 0.0:
					bodies.append(current)
					current = Rect2()
				continue
			var surface := float(column.get("surface", 0.0))
			var world_x := float(column.get("x", 0.0))
			if current.size.x > 0.0 and absf(surface - current.position.y) > BODY_LEVEL_TOLERANCE:
				bodies.append(current)
				current = Rect2()
			if current.size.x <= 0.0:
				current = Rect2(world_x, surface, cell, 1.0)
			else:
				current.size.x = world_x + cell - current.position.x
		if current.size.x > 0.0:
			bodies.append(current)
		return bodies


	func _cleanup(field: Node, runtime: Node, terrain: Node) -> void:
		# Free immediately: a queued-free field stays in the "water_field" group until the
		# end of the frame, and the next test would resolve it as the active field.
		field.free()
		runtime.free()
		terrain.free()


## tests/world/test_water_room_contract.gd
class WaterRoomContractCase extends Node:
	## Contract and flow test for the baked water hall.
	##
	## It binds a real WaterField to the generated room (same call the world session
	## makes), lets the sluice gate open and the pools settle, and checks that water
	## only starts moving after the gate opens and that the volume is conserved.

	const ROOM_DATA := preload("res://resources/rooms/generated/water_hall.tres")
	const RUNTIME_SCENE := preload("res://scenes/rooms/generated/water_hall/runtime.tscn")
	const TERRAIN_SCENE := preload("res://scenes/rooms/generated/water_hall/terrain.tscn")
	const WATER_FIELD := preload("res://addons/fluid_kit/runtime/water/water_field.gd")
	const WORLD := preload("res://resources/worlds/test_world.tres")
	const WORLD_VALIDATION := preload("res://addons/platformer_kit/world/data/world_validation.gd")

	const ROOM_ORIGIN_CHUNK := Vector2i(0, 1)
	const STEP := 1.0 / 120.0


	func run() -> Array[String]:
		var failures: Array[String] = []
		_assert_world_references(failures)
		_assert_baked_room(failures)
		_assert_water_flow(failures)
		return failures


	func _assert_world_references(failures: Array[String]) -> void:
		var report: Dictionary = WORLD_VALIDATION.validate_world_report(WORLD)
		for error: String in report.get("errors", []):
			failures.append("test world is invalid: %s" % error)
		if String(WORLD.start_room_id) != "water_hall":
			failures.append("test world does not start in the water hall: %s" % WORLD.start_room_id)
		if not WORLD.has_room("water_hall"):
			failures.append("test world does not reference the water hall")
		if not ROOM_DATA.spawn_ids.has("start"):
			failures.append("water hall has no start spawn")
		if ROOM_DATA.room_size_chunks != Vector2i.ONE:
			failures.append("water hall is not a single chunk: %s" % str(ROOM_DATA.room_size_chunks))


	func _assert_baked_room(failures: Array[String]) -> void:
		var runtime := RUNTIME_SCENE.instantiate()
		for node_name: String in ["WaterBasinA", "WaterBasinB", "SluiceGate", "HallLight"]:
			if runtime.find_child(node_name, true, false) == null:
				failures.append("baked water hall is missing %s" % node_name)
		var light_count := 0
		for child: Node in runtime.find_children("*", "Node2D", true, false):
			if child.has_method("get_energy_at"):
				light_count += 1
		if light_count < 2:
			failures.append("baked water hall has fewer than two fog lights: %d" % light_count)
		runtime.free()


	func _assert_water_flow(failures: Array[String]) -> void:
		var runtime := RUNTIME_SCENE.instantiate() as Node2D
		var terrain := TERRAIN_SCENE.instantiate() as Node2D
		var origin := Vector2(ROOM_ORIGIN_CHUNK) * Vector2(320.0, 180.0)
		runtime.position = origin
		terrain.position = origin
		add_child(runtime)
		add_child(terrain)
		var field := WATER_FIELD.new() as Node2D
		add_child(field)
		if not bool(field.call("bind_room_with_origin", ROOM_DATA, terrain, ROOM_ORIGIN_CHUNK)):
			failures.append("water field refused to bind to the water hall")
			_cleanup(field, runtime, terrain)
			return

		var gate := runtime.find_child("SluiceGate", true, false)
		var volume_start := float(field.call("get_debug_state").get("volume", 0.0))
		if volume_start <= 0.0:
			failures.append("water hall started without water")
		# Left tank has water, right basin starts dry (local x 64 and 240, world y offset).
		if float(field.call("get_surface_y_at", 64.0)) == INF:
			failures.append("tank A has no water at x=64")
		if float(field.call("get_surface_y_at", 240.0)) != INF:
			failures.append("basin B was not dry before the gate opened")

		# The gate is closed for a moment: the right basin must stay dry.
		for _frame: int in 60:
			field.call("_physics_process", STEP)
		if float(field.call("get_surface_y_at", 240.0)) != INF:
			failures.append("water crossed the closed gate")

		# Open the gate and let the pools settle.
		for _frame: int in 900:
			if gate != null:
				gate.call("_process", STEP)
			field.call("_physics_process", STEP)
		var left_surface := float(field.call("get_surface_y_at", 64.0))
		var right_surface := float(field.call("get_surface_y_at", 240.0))
		var volume_end := float(field.call("get_debug_state").get("volume", 0.0))
		if left_surface == INF:
			failures.append("tank A drained completely")
		if right_surface == INF:
			failures.append("basin B never received water")
		elif right_surface < 300.0 or right_surface > 340.0:
			failures.append("basin B settled at an unexpected height: %.1f" % right_surface)
		if left_surface != INF and left_surface < 280.0:
			failures.append("tank A did not drain towards the spill lip: %.1f" % left_surface)
		if absf(volume_end - volume_start) > volume_start * 0.02:
			failures.append(
				"water volume was not conserved: start=%.1f end=%.1f" % [volume_start, volume_end]
			)
		_cleanup(field, runtime, terrain)


	func _cleanup(field: Node, runtime: Node, terrain: Node) -> void:
		field.queue_free()
		runtime.queue_free()
		terrain.queue_free()


func run() -> Array[String]:
	var failures: Array[String] = []
	failures.append_array(_run_case(WaterSimulationCase.new()))
	failures.append_array(_run_case(WaterGridRoomCase.new()))
	failures.append_array(_run_case(WaterBuoyancyCase.new()))
	failures.append_array(_run_case(WaterRippleReachCase.new()))
	failures.append_array(_run_case(WaterSurfaceRippleReachCase.new()))
	failures.append_array(_run_case(WaterRoomContractCase.new()))
	return failures


func _run_case(test: Node) -> Array[String]:
	add_child(test)
	var result: Array = test.call("run")
	test.queue_free()
	var failures: Array[String] = []
	failures.assign(result)
	return failures
