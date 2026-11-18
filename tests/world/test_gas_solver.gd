extends Node

## The gas solver's structural contract: things that broke once and must not break
## again without someone noticing.
##
## The GPU solver cannot be *run* in the headless suite (there is no RenderingDevice,
## so no shader ever executes), so what is checked here is the parts that are check
## able without pixels: the shaders' data layout, the uniforms the solver hands them,
## the resolution policy, and the wiring the render layer depends on. The numbers
## behind each rule were measured with `scripts/tools/gas_diagnostic.gd`, which is
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
	_assert_cell_size_is_fixed(sim, failures)
	_assert_mist_uses_the_stipple(fog, atmosphere, failures)
	return failures


func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


func _source(name: String) -> String:
	return _read(GAS_DIR + name)


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


## The simulation domain has to be independent of the room it belongs to: a fixed
## cell size means the gas keeps the same texel density (and the same visible scale)
## in every room, which is what "camera relative" has to mean for a field that is not
## thrown away when the view scrolls.
func _assert_cell_size_is_fixed(sim: String, failures: Array[String]) -> void:
	if not sim.contains("const FIELD_CELL_SIZE := 4.0"):
		failures.append("GasSim no longer fixes the cell at 4 world pixels")
	if sim.contains("ceil(field_size.y / FIELD_CELL_SIZE)") and sim.contains("clampi(int(ceil(field_size.x / FIELD_CELL_SIZE)), 1, 160)"):
		failures.append("GasSim is back to a 160 cell ceiling, which shrinks the field instead of the cell")
	var ceiling := _int_between(sim, "const MAX_CELLS := ", "\n")
	if ceiling < 256:
		failures.append(
			"GasSim's cell ceiling is %d: a room wider than that would coarsen the field instead of"
			% ceiling
			+ "adding cells, so the gas would change scale in big rooms"
		)


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
