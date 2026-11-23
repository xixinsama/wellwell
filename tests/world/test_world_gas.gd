extends Node

## Merged test suite. Every inner class below is one original test file,
## kept in its own class so fixtures and helper names stay isolated. Do not
## add logic here: split a class back into its own file when it grows.

## tests/world/test_gas_backend.gd
class GasBackendCase extends Node:
	## Explicit gas backend selection on Atmosphere, in headless mode.
	##
	## The CPU path must bind and simulate a room on its own, a forced GPU without a
	## RenderingDevice must degrade to the CPU grid instead of leaving the room
	## unbound, and AUTO must keep the historical implicit choice. Toggling the layer
	## must park the bound field rather than rebuild it.

	const ATMOSPHERE: Script = preload("res://addons/fluid_kit/runtime/gas/atmosphere.gd")
	const ROOM_DATA: Script = preload("res://addons/platformer_kit/world/data/room_data.gd")

	## The defaults are tuned for 30 Hz, so one call per step is one gas step.
	const STEP := 1.0 / 30.0
	const STEP_COUNT := 12


	func run() -> Array[String]:
		var failures: Array[String] = []
		_assert_cpu_backend(failures)
		_assert_gpu_request_falls_back(failures)
		_assert_auto_backend(failures)
		return failures


	func _assert_cpu_backend(failures: Array[String]) -> void:
		var binding := _bind_atmosphere(Atmosphere.Backend.CPU)
		var atmosphere := binding["atmosphere"] as Node2D
		var terrain := binding["terrain"] as Node2D
		if not bool(binding["bound"]):
			failures.append("CPU backend refused to bind a room")
			_cleanup(atmosphere, terrain)
			return
		var state: Dictionary = atmosphere.call("get_debug_state")
		if String(state.get("backend", "none")) != "cpu":
			failures.append("CPU backend reported %s" % String(state.get("backend", "none")))
		if String(state.get("requested_backend", "")) != "cpu":
			failures.append("CPU backend did not report the request")
		if not bool(state.get("ready", false)):
			failures.append("CPU backend did not ready the gas field")
		var before := _density_snapshot(atmosphere)
		if before.is_empty():
			failures.append("CPU backend bound a room without a density grid")
		for _step: int in STEP_COUNT:
			atmosphere.call("_process", STEP)
		var after := _density_snapshot(atmosphere)
		if int(atmosphere.call("get_debug_state").get("steps", 0)) < STEP_COUNT:
			failures.append("CPU backend did not step the gas")
		if _total(after) <= 0.0:
			failures.append("CPU backend stepped an empty gas field")
		if _largest_change(before, after) <= 0.0:
			failures.append("CPU backend did not produce gas density after stepping")
		_assert_toggle_parks_field(atmosphere, failures)
		_cleanup(atmosphere, terrain)


	func _assert_toggle_parks_field(atmosphere: Node2D, failures: Array[String]) -> void:
		var steps := int(atmosphere.call("get_debug_state").get("steps", 0))
		var density := _density_snapshot(atmosphere)
		atmosphere.call("set_enabled", false)
		if bool(atmosphere.call("is_enabled")):
			failures.append("set_enabled(false) did not disable the gas layer")
		for _step: int in 4:
			atmosphere.call("_process", STEP)
		if int(atmosphere.call("get_debug_state").get("steps", 0)) != steps:
			failures.append("a disabled gas layer kept stepping")
		atmosphere.call("set_enabled", true)
		if not bool(atmosphere.call("is_enabled")):
			failures.append("the gas layer did not re-enable")
		var restored := _density_snapshot(atmosphere)
		if _largest_change(density, restored) > 0.0:
			failures.append("re-enabling the gas layer rebuilt the field from scratch")
		atmosphere.call("_process", STEP)
		if int(atmosphere.call("get_debug_state").get("steps", 0)) <= steps:
			failures.append("the re-enabled gas layer did not resume stepping")


	func _assert_gpu_request_falls_back(failures: Array[String]) -> void:
		var binding := _bind_atmosphere(Atmosphere.Backend.GPU)
		var atmosphere := binding["atmosphere"] as Node2D
		var terrain := binding["terrain"] as Node2D
		if not bool(binding["bound"]):
			failures.append("forced GPU backend refused to bind a room")
			_cleanup(atmosphere, terrain)
			return
		var state: Dictionary = atmosphere.call("get_debug_state")
		var actual := String(state.get("backend", "none"))
		if String(state.get("requested_backend", "")) != "gpu":
			failures.append("forced GPU backend did not report the request")
		if actual == "none" or not bool(state.get("ready", false)):
			failures.append("forced GPU backend left the room unbound")
		elif RenderingServer.get_rendering_device() == null:
			if actual != "cpu":
				failures.append("forced GPU without a RenderingDevice reported %s" % actual)
			if not bool(state.get("fallback", false)):
				failures.append("forced GPU fallback was not reported")
			for _step: int in STEP_COUNT:
				atmosphere.call("_process", STEP)
			if _total(_density_snapshot(atmosphere)) <= 0.0:
				failures.append("the GPU fallback did not simulate any gas")
		elif actual != "gpu" and not bool(state.get("fallback", false)):
			failures.append("forced GPU backend reported %s without a fallback" % actual)
		_cleanup(atmosphere, terrain)


	func _assert_auto_backend(failures: Array[String]) -> void:
		var binding := _bind_atmosphere(Atmosphere.Backend.AUTO)
		var atmosphere := binding["atmosphere"] as Node2D
		var terrain := binding["terrain"] as Node2D
		if not bool(binding["bound"]):
			failures.append("AUTO backend refused to bind a room")
			_cleanup(atmosphere, terrain)
			return
		var state: Dictionary = atmosphere.call("get_debug_state")
		if String(state.get("requested_backend", "")) != "auto":
			failures.append("AUTO backend did not report the request")
		var expected := "gpu" if RenderingServer.get_rendering_device() != null else "cpu"
		if String(state.get("backend", "none")) != expected:
			failures.append("AUTO backend reported %s, expected %s" % [state.get("backend"), expected])
		if not bool(state.get("ready", false)):
			failures.append("AUTO backend did not ready the gas field")
		_cleanup(atmosphere, terrain)


	## Creates a room-sized terrain root and binds a fresh Atmosphere to it, exactly
	## like WorldSession does for a real room.
	func _bind_atmosphere(selected_backend: int) -> Dictionary:
		var terrain := _make_terrain_root()
		add_child(terrain)
		var atmosphere := ATMOSPHERE.new() as Node2D
		add_child(atmosphere)
		atmosphere.set("backend", selected_backend)
		# A room starts gas-free on purpose (only GasVent nozzles put gas into it), so
		# seed a density here: these tests are about which backend simulates the field,
		# not about how much gas a new room begins with.
		atmosphere.set("ambient_density", 0.5)
		atmosphere.set("gas_ambient", Vector3(0.3, 0.25, 0.3))
		atmosphere.set("gas_refill", 0.35)
		var room: Resource = ROOM_DATA.new()
		var bound := bool(atmosphere.call("bind_room_with_origin", room, terrain, Vector2i.ZERO))
		return {"atmosphere": atmosphere, "terrain": terrain, "bound": bound}


	func _make_terrain_root() -> Node2D:
		var root := Node2D.new()
		var terrain := Node2D.new()
		terrain.name = "Terrain"
		root.add_child(terrain)
		var solid_tiles := TileMapLayer.new()
		solid_tiles.name = "SolidTiles"
		terrain.add_child(solid_tiles)
		return root


	func _cleanup(atmosphere: Node2D, terrain: Node2D) -> void:
		if is_instance_valid(atmosphere):
			remove_child(atmosphere)
			atmosphere.free()
		if is_instance_valid(terrain):
			remove_child(terrain)
			terrain.free()


	## `get_density_values()` hands out the live grid buffer, which the next step
	## writes into; snapshot it so before/after comparisons stay meaningful.
	func _density_snapshot(atmosphere: Node2D) -> PackedFloat32Array:
		var values: PackedFloat32Array = atmosphere.call("get_density_values")
		return values.duplicate()


	func _total(values: PackedFloat32Array) -> float:
		var total := 0.0
		for value: float in values:
			total += value
		return total


	func _largest_change(before: PackedFloat32Array, after: PackedFloat32Array) -> float:
		var largest := 0.0
		for index: int in mini(before.size(), after.size()):
			largest = maxf(largest, absf(after[index] - before[index]))
		return largest


## tests/world/test_gas_solver.gd
class GasSolverCase extends Node:
	## The gas solver's structural contract: things that broke once and must not break
	## again without someone noticing.
	##
	## The GPU solver cannot be *run* in the headless suite (there is no RenderingDevice,
	## so no shader ever executes), so what is checked here is the parts that are check
	## able without pixels: the shaders' data layout, the uniforms the solver hands them,
	## the resolution policy, and the wiring the render layer depends on. The numbers
	## behind each rule were measured with `tools/gas_diagnostic.gd`, which is
	## the tool to re-measure them (it captures the density, the velocity/tracer field
	## and the mist's opacity for the same gas state under several kernels).
	##
	## Covered:
	##   * the density buffers are written with alpha = 1.0. A transparent SubViewport
	##     PREMULTIPLIES the colour by the written alpha, and the density buffers
	##     ping-pong, so writing a fourth value in the alpha channel halves the gas every
	##     step: measured, the field's mean density collapsed from 0.022 to 0.0004 over
	##     172 steps when the detail tracer was stored there.
	##   * the detail tracer lives in the velocity field's blue channel, is traced back
	##     with the velocity, and is carried through the projection.
	##   * vorticity confinement exists and is wired: the velocity pass computes the curl
	##     of its neighbours and adds the confinement force, and GasSim passes the
	##     uniform. Measured on the light lab, the curl energy over 0.8 s of capture fell
	##     40% (0.348 -> 0.210) with confinement off and rose 16% (0.347 -> 0.404) with
	##     it at 10.
	##   * the cell size does not depend on the room: the field is always
	##     `FIELD_CELL_SIZE` world pixels per cell, so the simulation's texel density
	##     (and therefore its look) cannot change with where the room sits in the world or
	##     with what the camera shows.
	##   * the mist quantises its opacity through `stipple_at`, and the shipped kernel is
	##     the blue-noise tile, not the ordered one.

	const GAS_DIR := "res://addons/fluid_kit/runtime/gas/"
	const ATMOSPHERE_PATH := "res://addons/fluid_kit/runtime/gas/atmosphere.gd"
	const GAS_SIM_PATH := "res://addons/fluid_kit/runtime/gas/gas_sim.gd"
	const STIPPLE_PATH := "res://resources/textures/blue_noise_64.png"


	func run() -> Array[String]:
		var failures: Array[String] = []
		var density := _source("gas_density.gdshader")
		var velocity := _source("gas_velocity.gdshader")
		var project := _source("gas_project.gdshader")
		var fog := _source("fog_layer.gdshader")
		var atmosphere := _read(ATMOSPHERE_PATH)
		var sim := _read(GAS_SIM_PATH)
		_assert_density_alpha_stays_opaque(density, failures)
		_assert_tracer_rides_in_the_velocity(velocity, project, failures)
		_assert_vorticity_confinement(velocity, sim, failures)
		_assert_cell_size_is_fixed(sim, atmosphere, failures)
		_assert_mist_uses_the_stipple(fog, atmosphere, failures)
		return failures


	func _read(path: String) -> String:
		if not FileAccess.file_exists(path):
			return ""
		return FileAccess.get_file_as_string(path)


	func _source(file_name: String) -> String:
		return _read(GAS_DIR + file_name)


	func _assert_density_alpha_stays_opaque(density: String, failures: Array[String]) -> void:
		if density.is_empty():
			failures.append("gas_density.gdshader is missing")
			return
		if not density.contains("COLOR = vec4(clamp(density, vec3(0.0), vec3(1.0)), 1.0);"):
			failures.append(
				"gas_density.gdshader no longer writes alpha 1.0: a transparent viewport "
				+ "premultiplies the colour by the written alpha, so any other value scales "
				+ "the gas down every step (see the header of this test)"
			)
		if density.contains("advected.a"):
			failures.append("gas_density.gdshader is reading a fourth channel from the density buffers again")


	func _assert_tracer_rides_in_the_velocity(velocity: String, project: String, failures: Array[String]) -> void:
		for shader_name: String in ["gas_velocity.gdshader", "gas_project.gdshader"]:
			var source: String = velocity if shader_name == "gas_velocity.gdshader" else project
			if source.is_empty():
				failures.append("%s is missing" % shader_name)
				continue
			if not source.contains("vec4(velocity, clamp(detail, 0.0, 1.0), 1.0)"):
				failures.append(
					"%s does not write the detail tracer into the blue channel; the mist would "
					% shader_name
					+ "fall back to screen-space noise and stop belonging to the gas"
				)
		if not velocity.contains("traced.b"):
			failures.append("gas_velocity.gdshader no longer advects the tracer with the trace-back sample")
		if not velocity.contains("detail_source("):
			failures.append("gas_velocity.gdshader has no detail source, so the tracer can only fade")


	func _assert_vorticity_confinement(velocity: String, sim: String, failures: Array[String]) -> void:
		if not velocity.contains("float curl_at("):
			failures.append("gas_velocity.gdshader lost the curl helper that vorticity confinement needs")
		if not velocity.contains("vec2 confinement = vec2(direction.y, -direction.x) * w_centre;"):
			failures.append("gas_velocity.gdshader lost the confinement force (N x w)")
		if not velocity.contains("velocity += confinement * vorticity * delta;"):
			failures.append("gas_velocity.gdshader never applies the confinement force")
		if not sim.contains("set_shader_parameter(\"vorticity\", vorticity)"):
			failures.append("GasSim does not hand the vorticity strength to the velocity pass")
		if not sim.contains("var vorticity := 0.0"):
			failures.append("GasSim has no vorticity tunable")
		if not _read(ATMOSPHERE_PATH).contains("gas_vorticity"):
			failures.append("Atmosphere does not expose a vorticity tunable, so no room can set it")


	## The simulation domain has to be independent of the room *and* of the camera: the
	## cell size is a tunable (`Atmosphere.gas_cell_pixels`), every force is divided by it
	## so the same tuning means the same physical behaviour at any resolution, and the cell
	## ceiling is high enough that a fine field is not silently coarsened.
	##
	## The measured cost of going to one pixel per cell (2x2 room, 640x360 = 230400 cells)
	## is in the fluid kit README: 0.084 ms of CPU submit per step, no frame-time change,
	## 41 MB of HDR buffers. The dye does need `gas_diffusion` re-scaled with 1/cell².
	func _assert_cell_size_is_fixed(sim: String, atmosphere: String, failures: Array[String]) -> void:
		if not sim.contains("const DEFAULT_CELL_SIZE := 4.0"):
			failures.append("GasSim no longer has a 4 px default cell")
		if not sim.contains("var cell_size := DEFAULT_CELL_SIZE"):
			failures.append("GasSim has no cell_size tunable, so the resolution cannot be changed")
		if sim.contains("ceil(field_size.x / FIELD_CELL_SIZE)"):
			failures.append("GasSim is back to sizing the grid from a constant instead of cell_size")
		for force: String in ["buoyancy.x / cell_size", "buoyancy.z / cell_size", "wind / cell_size"]:
			if not sim.contains(force):
				failures.append(
					"`%s` is missing: a force that is not divided by the cell size makes the"
					% force
					+ " gas behave differently at every resolution"
				)
		if not sim.contains("set_shader_parameter(\"cell_size\", cell_size)"):
			failures.append("GasSim does not hand the cell size to the shaders")
		var ceiling := _int_between(sim, "const MAX_CELLS := ", "\n")
		if ceiling < 1024:
			failures.append(
				"GasSim's cell ceiling is %d: a 640-wide field at one pixel per cell (a 2x2 room)"
				% ceiling
				+ " would be clamped down to a coarser cell instead of being simulated"
			)
		if not atmosphere.contains("var gas_cell_pixels"):
			failures.append("Atmosphere has no gas_cell_pixels tunable")
		if not atmosphere.contains("gas.set(\"cell_size\", gas_cell_pixels)"):
			failures.append("Atmosphere never gives its cell size to the solver")


	func _assert_mist_uses_the_stipple(fog: String, atmosphere: String, failures: Array[String]) -> void:
		if not fog.contains("alpha = floor(alpha * stipple_steps + stipple_at(world)) / stipple_steps;"):
			failures.append("fog_layer.gdshader no longer quantises the mist through stipple_at")
		if fog.contains("floor(alpha * 32.0 + bayer4(world))"):
			failures.append("fog_layer.gdshader is back to the hard-wired 4x4 ordered dither")
		if not fog.contains("uniform float stipple_mode = 1.0;"):
			failures.append("the mist's default stipple kernel is no longer the blue-noise tile")
		if not atmosphere.contains("STIPPLE_TEXTURE"):
			failures.append("Atmosphere never binds the blue-noise tile")
		if not atmosphere.contains("if stipple_mode > 0 and ResourceLoader.exists(STIPPLE_TEXTURE)"):
			failures.append(
				"Atmosphere binds the stipple without a fallback: an unbound sampler reads"
				+ " white, which shifts every opacity level up by one"
			)
		if not ResourceLoader.exists(STIPPLE_PATH):
			failures.append("the blue-noise tile is missing: %s" % STIPPLE_PATH)


	func _int_between(source: String, prefix: String, suffix: String) -> int:
		var start := source.find(prefix)
		if start < 0:
			return 0
		start += prefix.length()
		var end := source.find(suffix, start)
		if end < 0:
			end = source.length()
		return source.substr(start, end - start).strip_edges().to_int()


## tests/world/test_atmosphere_fog.gd
class AtmosphereFogCase extends Node:
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


## tests/world/test_gas_dither_seam.gd
class GasDitherSeamCase extends Node:
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
	##
	## A balanced ordered kernel is still a *lattice*, and that turned out to be the rest
	## of the artefact: at the opacity a fading mist passes through, the tile lit by the
	## level underneath is a regular 2x2 checkerboard, so on the 4x screen every column
	## is a dashed line and the fade reads as a woven grid (measured on the same gas
	## state: 15.7% of the stipple's high-pass energy sat on the period-2/period-4
	## lattice peaks, and 79.5% of the upscaled vertical runs were exactly one design
	## pixel). The shipped kernel is therefore the blue-noise tile - see
	## tests/world/test_blue_noise.gd for the tile and tests/world/test_gas_solver.gd for
	## the wiring. This test still guards the ordered kernel because `stipple_mode = 0`
	## keeps it available for A/B captures.

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
			if lit != int(TILE / 2.0):
				failures.append(
					"dither column %d lights %d of %d texels at half opacity, want %d: the dither is columnar"
					% [x, lit, TILE, int(TILE / 2.0)]
				)
		for y in TILE:
			var lit := 0
			for x in TILE:
				if _kernel_index(float(x), float(y)) < HALF_THRESHOLD:
					lit += 1
			if lit != int(TILE / 2.0):
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


func run() -> Array[String]:
	var failures: Array[String] = []
	failures.append_array(_run_case(GasBackendCase.new()))
	failures.append_array(_run_case(GasSolverCase.new()))
	failures.append_array(_run_case(AtmosphereFogCase.new()))
	failures.append_array(_run_case(GasDitherSeamCase.new()))
	return failures


func _run_case(test: Node) -> Array[String]:
	add_child(test)
	var result: Array = test.call("run")
	test.queue_free()
	var failures: Array[String] = []
	failures.assign(result)
	return failures
