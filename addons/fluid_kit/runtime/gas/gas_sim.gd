class_name GasSim
extends Node

## Full 2D Navier-Stokes gas field (Stam's stable fluids, GPU Gems 38).
##
## Per fixed step:
##   1. semi-Lagrangian self-advection of the velocity + external forces
##      (buoyancy of the three gas densities, vent jets, the hero's push)  -> u*
##   2. pressure Poisson solve: laplacian(p) = div(u*) with Jacobi iterations
##   3. projection: u = u* - grad(p)  (divergence free / incompressible)
##   4. advect the three gas densities with u, then diffuse / refill / inject.
##
## Every pass renders its own HDR SubViewport and samples only other viewports
## (Vulkan forbids sampling the texture being rendered). The viewports are created
## in pass order so the renderer walks them in dependency order.

const VELOCITY_SHADER := preload("res://addons/fluid_kit/runtime/gas/gas_velocity.gdshader")
const PRESSURE_SHADER := preload("res://addons/fluid_kit/runtime/gas/gas_pressure.gdshader")
const PROJECT_SHADER := preload("res://addons/fluid_kit/runtime/gas/gas_project.gdshader")
const DENSITY_SHADER := preload("res://addons/fluid_kit/runtime/gas/gas_density.gdshader")
const COPY_SHADER := preload("res://addons/fluid_kit/runtime/gas/gas_copy.gdshader")

const DEFAULT_CELL_SIZE := 4.0
## Hard ceiling on the grid, not a resolution policy: the cell is `cell_size` world
## pixels, so a bigger room gets more cells rather than coarser ones. That keeps the
## simulation's texel density independent of where the room sits in the world (and of
## what the camera happens to show), which is the property "camera relative" is really
## about: the field must not change scale or phase because the view moved.
##
## The ceiling is high enough for a 2x2 chunk room at one pixel per cell (640x360),
## which is the finest setting `Atmosphere.gas_cell_pixels` allows: a clamp here would
## silently coarsen the cell instead of failing, so it only exists to stop a runaway
## allocation.
const MAX_CELLS := 1024
## How long a one-shot blast keeps pushing before it fades out.
const IMPULSE_SECONDS := 0.18

## Tunables, written by Atmosphere before setup().
## World pixels per simulation cell. Every force is divided by it, so the same
## numbers describe the same *physical* behaviour at any resolution; a smaller cell
## only means more of them, so the field carries detail down to that scale.
var cell_size := DEFAULT_CELL_SIZE
var ambient := Vector3(0.28, 0.22, 0.32)
var diffusion := 0.25
var refill := 0.35
var wind := Vector2(7.0, -1.5)
## Acceleration per unit density in pixels per second squared.
var buoyancy := Vector3(240.0, 0.0, 300.0)
var dissipation := 0.4
var pressure_iterations := 16
var push_radius := 34.0
var push_strength := 1.4
## Exponential gas fade per second (0 = never fades).
var decay := 0.0
## Kinematic viscosity in 1/s (velocity diffusion).
var viscosity := 0.0
## Vorticity confinement strength. The trace-back step averages the field every
## step, so without this the curls of a plume are smoothed into a soft blob; the
## confinement force pushes each vortex inwards along the gradient of |curl| and
## keeps the small scales alive. In the same units the velocity is stored in (cells
## per second), so a value around `cell_size` is a strong setting.
var vorticity := 0.0
## Share of the detail channel kept per step, and how fast fresh detail is stirred
## into cells that hold gas (see gas_velocity.gdshader). The retention is just below
## 1 on purpose: a passive scalar that is traced back with clamped boundary sampling
## slowly loses its neutral level, and a mist whose detail drifts to 0 is a mist that
## renders dimmer than its density says. Relaxing to neutral bounds that drift.
var detail_retention := 0.99
var detail_refresh := 4.0
var detail_hz := 6.0
var vents: Array[Dictionary] = []

var _velocity: Array[SubViewport] = []
var _density: Array[SubViewport] = []
var _pressure: Array[SubViewport] = []
var _mid: SubViewport
## Last converged pressure, used as the next step's initial guess.
var _pressure_guess: SubViewport
var _pressure_guess_material: ShaderMaterial
var _mid_material: ShaderMaterial
var _project_materials: Array[ShaderMaterial] = []
var _density_materials: Array[ShaderMaterial] = []
var _pressure_materials: Array[ShaderMaterial] = []
var _front_velocity := 0
var _front_density := 0
var _size := Vector2i.ZERO
var _field_size := Vector2.ZERO
var _mask_texture: ImageTexture
var _mask_cell_count := Vector2.ONE
var _initialized := false
var _step_ms := 0.0
var _steps := 0
var _impulse_position := Vector2.ZERO
var _impulse_radius := 0.0
var _impulse_strength := 0.0
var _impulse_density := 0.0
var _impulse_timer := 0.0
var _mover_center := Vector2.ZERO
var _mover_half := Vector2.ZERO
var _mover_velocity := Vector2.ZERO
var _mover_active := false
var _emitter_position := Vector2.ZERO
var _emitter_radius := 0.0
var _emitter_rate := 0.0
var _emitter_velocity := Vector2.ZERO
var _emitter_channel := 1.0
var _emitter_active := false


func is_available() -> bool:
	return RenderingServer.get_rendering_device() != null


func setup(field_size: Vector2, solid_mask: PackedByteArray, mask_columns: int, mask_rows: int) -> bool:
	teardown()
	if not is_available() or field_size.x <= 0.0 or field_size.y <= 0.0:
		return false
	_field_size = field_size
	_size = Vector2i(
		clampi(int(ceil(field_size.x / cell_size)), 1, MAX_CELLS),
		clampi(int(ceil(field_size.y / cell_size)), 1, MAX_CELLS)
	)
	if mask_columns <= 0 or mask_rows <= 0 or mask_columns * mask_rows != solid_mask.size():
		return false
	var mask_bytes := PackedByteArray()
	mask_bytes.resize(solid_mask.size())
	for index: int in solid_mask.size():
		mask_bytes[index] = 255 if solid_mask[index] != 0 else 0
	var mask_image := Image.create_from_data(mask_columns, mask_rows, false, Image.FORMAT_R8, mask_bytes)
	_mask_texture = ImageTexture.create_from_image(mask_image)
	_mask_cell_count = Vector2(float(mask_columns), float(mask_rows))

	var iterations := clampi(pressure_iterations, 2, 64)
	# Pass order = tree order: mid velocity, pressure iterations, velocity states,
	# density states.
	_mid = _make_viewport("GasMidVelocity", VELOCITY_SHADER)
	_mid_material = _material_of(_mid)
	_apply_common(_mid_material)
	_mid_material.set_shader_parameter("dissipation", dissipation)
	_mid_material.set_shader_parameter("viscosity", viscosity)
	_mid_material.set_shader_parameter("vorticity", vorticity)
	_mid_material.set_shader_parameter("detail_retention", detail_retention)
	_mid_material.set_shader_parameter("detail_refresh", detail_refresh)
	_mid_material.set_shader_parameter("detail_hz", detail_hz)
	_mid_material.set_shader_parameter("buoyancy_heavy", buoyancy.x / cell_size)
	_mid_material.set_shader_parameter("buoyancy_light", buoyancy.z / cell_size)
	_mid_material.set_shader_parameter("push_radius", push_radius)
	_mid_material.set_shader_parameter("push_strength", push_strength)

	_pressure.clear()
	_pressure_materials.clear()
	for index: int in iterations:
		var viewport := _make_viewport("GasPressure%d" % index, PRESSURE_SHADER)
		var material := _material_of(viewport)
		_apply_common(material)
		material.set_shader_parameter("first_iteration", false)
		material.set_shader_parameter("velocity_texture", _mid.get_texture())
		if index > 0:
			material.set_shader_parameter("pressure_texture", _pressure[index - 1].get_texture())
		_pressure.append(viewport)
		_pressure_materials.append(material)

	# Warm start: keep the last converged pressure and let iteration 0 read it.
	_pressure_guess = _make_viewport("GasPressureGuess", COPY_SHADER)
	_pressure_guess_material = _material_of(_pressure_guess)
	_pressure_guess_material.set_shader_parameter("source_texture", _pressure[iterations - 1].get_texture())
	_pressure_materials[0].set_shader_parameter("pressure_texture", _pressure_guess.get_texture())

	_velocity.clear()
	_project_materials.clear()
	for index: int in 2:
		var viewport := _make_viewport("GasVelocity%d" % index, PROJECT_SHADER)
		var material := _material_of(viewport)
		_apply_common(material)
		material.set_shader_parameter("velocity_texture", _mid.get_texture())
		material.set_shader_parameter("pressure_texture", _pressure[iterations - 1].get_texture())
		_velocity.append(viewport)
		_project_materials.append(material)

	_density.clear()
	_density_materials.clear()
	for index: int in 2:
		var viewport := _make_viewport("GasDensity%d" % index, DENSITY_SHADER)
		var material := _material_of(viewport)
		_apply_common(material)
		material.set_shader_parameter("diffusion", diffusion)
		material.set_shader_parameter("refill", refill)
		material.set_shader_parameter("decay", decay)
		material.set_shader_parameter("ambient", ambient)
		material.set_shader_parameter("wind", wind / cell_size)
		material.set_shader_parameter("push_radius", push_radius)
		material.set_shader_parameter("push_strength", push_strength)
		material.set_shader_parameter("density_texture", null)
		_density.append(viewport)
		_density_materials.append(material)
	# Each density buffer reads its twin (one is written, the other is sampled).
	_density_materials[0].set_shader_parameter("density_texture", _density[1].get_texture())
	_density_materials[1].set_shader_parameter("density_texture", _density[0].get_texture())

	# Seed both density buffers with the ambient gas; velocity starts at rest. The
	# velocity buffers also carry the detail tracer in their blue channel, and a
	# frame buffer is cleared to zero, so they are seeded through the projection's
	# initialize branch: without that the tracer starts at 0 instead of neutral and
	# the mist renders dimmer than the density says (measured: mean tracer 0.20
	# instead of 0.50, gas alpha 7% low).
	for index: int in 2:
		_density_materials[index].set_shader_parameter("initialize", true)
		_density[index].render_target_update_mode = SubViewport.UPDATE_ONCE
	for index: int in 2:
		_project_materials[index].set_shader_parameter("initialize", true)
		_velocity[index].render_target_update_mode = SubViewport.UPDATE_ONCE
	for material: ShaderMaterial in _density_materials:
		material.set_shader_parameter("initialize", false)
	for material: ShaderMaterial in _project_materials:
		material.set_shader_parameter("initialize", false)

	_front_velocity = 0
	_front_density = 0
	_initialized = true
	_steps = 0
	return true


func teardown() -> void:
	for viewport: SubViewport in _velocity:
		if is_instance_valid(viewport):
			viewport.queue_free()
	for viewport: SubViewport in _density:
		if is_instance_valid(viewport):
			viewport.queue_free()
	for viewport: SubViewport in _pressure:
		if is_instance_valid(viewport):
			viewport.queue_free()
	if is_instance_valid(_mid):
		_mid.queue_free()
	if is_instance_valid(_pressure_guess):
		_pressure_guess.queue_free()
	_velocity.clear()
	_density.clear()
	_pressure.clear()
	_project_materials.clear()
	_density_materials.clear()
	_pressure_materials.clear()
	_mid = null
	_mid_material = null
	_pressure_guess = null
	_pressure_guess_material = null
	_mask_texture = null
	_size = Vector2i.ZERO
	_initialized = false


## Advances the fluid by one step. Call at most once per rendered frame: the
## passes sample the buffers written by the previous pass.
func step(delta: float, player_position: Vector2, _player_velocity: Vector2) -> void:
	if not _initialized or _velocity.size() != 2 or _density.size() != 2 or _pressure.is_empty():
		return
	var started := Time.get_ticks_usec()
	var velocity_front := _front_velocity
	var density_front := _front_density
	var velocity_target := 1 - velocity_front
	var density_target := 1 - density_front

	# 1. u* = advect(u) + forces.
	var impulse_velocity := Vector4(-9999.0, -9999.0, 0.0, 0.0)
	var impulse_density := Vector4(-9999.0, -9999.0, 0.0, 0.0)
	if _impulse_timer > 0.0:
		var fade := clampf(_impulse_timer / IMPULSE_SECONDS, 0.0, 1.0)
		impulse_velocity = Vector4(_impulse_position.x, _impulse_position.y, _impulse_radius, _impulse_strength * fade)
		impulse_density = Vector4(_impulse_position.x, _impulse_position.y, _impulse_radius, _impulse_density * fade)
		_impulse_timer = maxf(_impulse_timer - delta, 0.0)
	var mover_vector := Vector4(_mover_center.x, _mover_center.y, _mover_half.x, _mover_half.y)
	var mover_active := 1.0 if _mover_active else 0.0
	var emitter_vector := Vector4(-9999.0, -9999.0, 0.0, 0.0)
	if _emitter_active:
		emitter_vector = Vector4(_emitter_position.x, _emitter_position.y, _emitter_radius, _emitter_rate)

	_mid_material.set_shader_parameter("velocity_texture", _velocity[velocity_front].get_texture())
	_mid_material.set_shader_parameter("density_texture", _density[density_front].get_texture())
	_mid_material.set_shader_parameter("delta", delta)
	_mid_material.set_shader_parameter("player_position", player_position)
	_mid_material.set_shader_parameter("impulse", impulse_velocity)
	_mid_material.set_shader_parameter("mover", mover_vector)
	_mid_material.set_shader_parameter("mover_velocity", _mover_velocity)
	_mid_material.set_shader_parameter("mover_active", mover_active)
	_mid_material.set_shader_parameter("emitter", emitter_vector)
	_mid_material.set_shader_parameter("emitter_velocity", _emitter_velocity)
	_apply_vents(_mid_material)
	_mid.render_target_update_mode = SubViewport.UPDATE_ONCE

	# 2. Pressure Jacobi iterations (warm started from the last converged pressure).
	for viewport: SubViewport in _pressure:
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_pressure_guess.render_target_update_mode = SubViewport.UPDATE_ONCE

	# 3. Projection into the other velocity buffer.
	_velocity[velocity_target].render_target_update_mode = SubViewport.UPDATE_ONCE

	# 4. Advect the densities with the projected velocity.
	var density_material := _density_materials[density_target]
	density_material.set_shader_parameter("velocity_texture", _velocity[velocity_target].get_texture())
	density_material.set_shader_parameter("delta", delta)
	density_material.set_shader_parameter("player_position", player_position)
	density_material.set_shader_parameter("impulse", impulse_density)
	density_material.set_shader_parameter("mover", mover_vector)
	density_material.set_shader_parameter("mover_velocity", _mover_velocity)
	density_material.set_shader_parameter("mover_active", mover_active)
	density_material.set_shader_parameter("emitter", emitter_vector)
	density_material.set_shader_parameter("emitter_velocity", _emitter_velocity)
	density_material.set_shader_parameter("emitter_channel", _emitter_channel)
	_apply_vents(density_material)
	_density[density_target].render_target_update_mode = SubViewport.UPDATE_ONCE

	_front_velocity = velocity_target
	_front_density = density_target
	_step_ms = float(Time.get_ticks_usec() - started) / 1000.0
	_steps += 1


## One-shot radial blast in room-local pixels. `strength` is the velocity kick in
## cells per second, `density` the amount of gas added at the centre.
func trigger_impulse(position: Vector2, radius: float, strength: float, density: float) -> void:
	_impulse_position = position
	_impulse_radius = maxf(radius, 4.0)
	_impulse_strength = strength
	_impulse_density = density
	_impulse_timer = IMPULSE_SECONDS


## A moving obstacle (a pillar, a piston) that drags the gas along with it.
func set_mover(center: Vector2, half_size: Vector2, velocity: Vector2) -> void:
	_mover_center = center
	_mover_half = half_size
	_mover_velocity = velocity
	_mover_active = true


func clear_mover() -> void:
	_mover_active = false


## A moving trail source: injects `rate` density per second of one channel inside
## `radius`, and gives that gas `velocity` (room-local px/s) as its initial push.
func set_emitter(position: Vector2, radius: float, rate: float, velocity: Vector2, channel: float) -> void:
	_emitter_position = position
	_emitter_radius = maxf(radius, 2.0)
	_emitter_rate = rate
	_emitter_velocity = velocity
	_emitter_channel = clampf(channel, 0.0, 2.0)
	_emitter_active = true


func clear_emitter() -> void:
	_emitter_active = false


func get_texture() -> Texture2D:
	if not _initialized or _density.is_empty():
		return null
	return _density[_front_density].get_texture()


## The projected velocity field: RG is the velocity in cells per second, B is the
## detail tracer the mist is textured with (see gas_velocity.gdshader).
func get_velocity_texture() -> Texture2D:
	if not _initialized or _velocity.is_empty():
		return null
	return _velocity[_front_velocity].get_texture()


## Replaces the solid mask (for example to include a water body) without
## rebuilding the pipeline. The size must be unchanged.
func update_mask(solid_mask: PackedByteArray) -> void:
	if _mask_texture == null or solid_mask.size() != int(_mask_cell_count.x * _mask_cell_count.y):
		return
	var mask_bytes := PackedByteArray()
	mask_bytes.resize(solid_mask.size())
	for index: int in solid_mask.size():
		mask_bytes[index] = 255 if solid_mask[index] != 0 else 0
	var image := _mask_texture.get_image()
	if image == null or image.get_size() != Vector2i(_mask_cell_count):
		return
	image.set_data(int(_mask_cell_count.x), int(_mask_cell_count.y), false, Image.FORMAT_R8, mask_bytes)
	_mask_texture.update(image)


## Debug only: the projected velocity image (RG = velocity in cells/s).
func get_velocity_image() -> Image:
	if not _initialized or _velocity.is_empty():
		return null
	var texture := _velocity[_front_velocity].get_texture()
	return texture.get_image() if texture != null else null


## Debug only: the intermediate velocity u* (before the projection).
func get_mid_velocity_image() -> Image:
	if not _initialized or not is_instance_valid(_mid):
		return null
	var mid_texture := _mid.get_texture()
	return mid_texture.get_image() if mid_texture != null else null


## Debug only: the final pressure field image.
func get_pressure_image() -> Image:
	if not _initialized or _pressure.is_empty():
		return null
	var pressure_texture := _pressure[_pressure.size() - 1].get_texture()
	return pressure_texture.get_image() if pressure_texture != null else null


## Debug only: the solid mask (one texel per 8 px tile).
func get_mask_image() -> Image:
	if _mask_texture == null:
		return null
	return _mask_texture.get_image()


func get_density_image() -> Image:
	var texture := get_texture()
	return texture.get_image() if texture != null else null


func get_debug_state() -> Dictionary:
	return {
		"gpu": _initialized,
		"size": _size,
		"iterations": _pressure.size(),
		"passes_per_step": _pressure.size() + 4,
		"steps": _steps,
		"step_ms": _step_ms,
		"vents": vents.size(),
		# The values the solver is actually running with. They are not always the
		# Atmosphere's exports: a room's GasField overrides ambient/decay/diffusion/
		# refill at bind time, and reading the exports was how a report once described
		# a room with different numbers than the one being simulated.
		"ambient": ambient,
		"decay": decay,
		"refill": refill,
		"diffusion": diffusion,
		"wind": wind,
		"vorticity": vorticity,
		"detail_refresh": detail_refresh,
	}


func _make_viewport(viewport_name: String, shader: Shader) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = viewport_name
	viewport.size = _size
	viewport.use_hdr_2d = true
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.gui_disable_input = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	add_child(viewport)
	var rect := ColorRect.new()
	rect.name = "Pass"
	rect.position = Vector2.ZERO
	rect.size = Vector2(_size)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = shader
	rect.material = material
	viewport.add_child(rect)
	return viewport


func _material_of(viewport: SubViewport) -> ShaderMaterial:
	var rect := viewport.get_child(0) as ColorRect
	return rect.material as ShaderMaterial


func _apply_common(material: ShaderMaterial) -> void:
	material.set_shader_parameter("mask_texture", _mask_texture)
	material.set_shader_parameter("grid_size", Vector2(_size))
	material.set_shader_parameter("mask_cell_count", _mask_cell_count)
	material.set_shader_parameter("field_size", _field_size)
	material.set_shader_parameter("cell_size", cell_size)


func _apply_vents(material: ShaderMaterial) -> void:
	for index: int in 4:
		var slot := "vent%d" % index
		var slot_dir := "vent_dir%d" % index
		if index >= vents.size():
			material.set_shader_parameter(slot, Vector4(-9999.0, -9999.0, 1.0, 0.0))
			material.set_shader_parameter(slot_dir, Vector4(1.0, 0.0, 1.0, 0.0))
			continue
		var vent: Dictionary = vents[index]
		var position: Vector2 = vent.get("position", Vector2.ZERO)
		var direction: Vector2 = vent.get("direction", Vector2.RIGHT)
		material.set_shader_parameter(
			slot,
			Vector4(position.x, position.y, float(vent.get("radius", 18.0)), float(vent.get("rate", 1.0)))
		)
		material.set_shader_parameter(
			slot_dir,
			Vector4(direction.x, direction.y, float(vent.get("channel", 1)), float(vent.get("jet_speed", 0.0)))
		)
