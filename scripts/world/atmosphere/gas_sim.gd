class_name GasSim
extends Node

## Incompressible three-gas field.
##
## The flow velocity is the curl of a scalar stream function psi, so its
## divergence is zero by construction (the gas is an incompressible fluid, it
## cannot pile up). Per step only two 80x45 GPU passes run:
##
##   1. psi step      advect psi with curl(psi) and twist it from the density
##                    gradients (heavy sinks, light rises).
##   2. density step  advect the three densities with curl(psi) + wind + vent
##                    jets + the hero's push, then diffuse, refill and inject
##                    from the vents.
##
## Two SubViewports per field (ping-pong): Vulkan forbids sampling the texture it
## is rendering into. Textures are HDR so psi can be negative. The CPU `FogGrid`
## in Atmosphere stays as the headless fallback.

const PSI_SHADER := preload("res://scripts/world/atmosphere/gas_psi.gdshader")
const DENSITY_SHADER := preload("res://scripts/world/atmosphere/gas_sim.gdshader")

const FIELD_CELL_SIZE := 4.0
const MAX_CELLS := 160

var ambient := Vector3(0.5, 0.42, 0.5)
var diffusion := 0.12
var refill := 0.25
var wind := Vector2(7.0, -1.5)
var buoyancy := Vector3(0.9, 0.0, 0.8)
var dissipation := 0.6
var push_radius := 34.0
var push_strength := 1.4
## Up to four vents: {position (room local), direction, radius, rate, jet_speed,
## channel}. Collected by the Atmosphere from the room's GasVent nodes.
var vents: Array[Dictionary] = []

var _psi: Array[SubViewport] = []
var _density: Array[SubViewport] = []
var _psi_materials: Array[ShaderMaterial] = []
var _density_materials: Array[ShaderMaterial] = []
var _psi_front := 0
var _density_front := 0
var _size := Vector2i.ZERO
var _field_size := Vector2.ZERO
var _mask_texture: ImageTexture
var _mask_cell_count := Vector2.ONE
var _initialized := false
var _step_ms := 0.0
var _steps := 0


func is_available() -> bool:
	return RenderingServer.get_rendering_device() != null


func setup(field_size: Vector2, solid_mask: PackedByteArray, mask_columns: int, mask_rows: int) -> bool:
	teardown()
	if not is_available() or field_size.x <= 0.0 or field_size.y <= 0.0:
		return false
	_field_size = field_size
	_size = Vector2i(
		clampi(int(ceil(field_size.x / FIELD_CELL_SIZE)), 1, MAX_CELLS),
		clampi(int(ceil(field_size.y / FIELD_CELL_SIZE)), 1, MAX_CELLS)
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

	_psi.clear()
	_density.clear()
	_psi_materials.clear()
	_density_materials.clear()
	for index: int in 2:
		_psi.append(_make_viewport("GasPsi%d" % index, PSI_SHADER))
		_density.append(_make_viewport("GasDensity%d" % index, DENSITY_SHADER))
	for material: ShaderMaterial in _psi_materials:
		_apply_common(material)
	for material: ShaderMaterial in _density_materials:
		_apply_common(material)
		_apply_density_parameters(material)

	# Seed both buffers so the first rendered frame is already full of gas. A
	# viewport can never sample its own texture, so the seed pass reads the twin.
	for index: int in 2:
		var other := 1 - index
		_psi_materials[index].set_shader_parameter("initialize", true)
		_psi_materials[index].set_shader_parameter("psi_previous", _psi[other].get_texture())
		_psi[index].render_target_update_mode = SubViewport.UPDATE_ONCE
		_density_materials[index].set_shader_parameter("initialize", true)
		_density_materials[index].set_shader_parameter("density_previous", _density[other].get_texture())
		_density_materials[index].set_shader_parameter("psi_current", _psi[index].get_texture())
		_density[index].render_target_update_mode = SubViewport.UPDATE_ONCE
	for material: ShaderMaterial in _psi_materials:
		material.set_shader_parameter("initialize", false)
	for material: ShaderMaterial in _density_materials:
		material.set_shader_parameter("initialize", false)

	_psi_front = 0
	_density_front = 0
	_initialized = true
	_steps = 0
	return true


func teardown() -> void:
	for viewport: SubViewport in _psi:
		if is_instance_valid(viewport):
			viewport.queue_free()
	for viewport: SubViewport in _density:
		if is_instance_valid(viewport):
			viewport.queue_free()
	_psi.clear()
	_density.clear()
	_psi_materials.clear()
	_density_materials.clear()
	_mask_texture = null
	_size = Vector2i.ZERO
	_initialized = false


## Advances both fields. Call at most once per rendered frame: the two passes of
## one step read the buffers written by the previous step.
func step(delta: float, player_position: Vector2, _player_velocity: Vector2) -> void:
	if not _initialized or _psi.size() != 2 or _density.size() != 2:
		return
	var started := Time.get_ticks_usec()
	var psi_read := _psi[_psi_front]
	var psi_write := _psi[1 - _psi_front]
	var density_read := _density[_density_front]
	var density_write := _density[1 - _density_front]

	var psi_material := _psi_materials[1 - _psi_front]
	psi_material.set_shader_parameter("initialize", false)
	psi_material.set_shader_parameter("psi_previous", psi_read.get_texture())
	psi_material.set_shader_parameter("density_previous", density_read.get_texture())
	psi_material.set_shader_parameter("delta", delta)
	psi_write.render_target_update_mode = SubViewport.UPDATE_ONCE

	var density_material := _density_materials[1 - _density_front]
	density_material.set_shader_parameter("initialize", false)
	density_material.set_shader_parameter("density_previous", density_read.get_texture())
	density_material.set_shader_parameter("psi_current", psi_write.get_texture())
	density_material.set_shader_parameter("delta", delta)
	density_material.set_shader_parameter("player_position", player_position)
	_apply_vents(density_material)
	density_write.render_target_update_mode = SubViewport.UPDATE_ONCE

	_psi_front = 1 - _psi_front
	_density_front = 1 - _density_front
	_step_ms = float(Time.get_ticks_usec() - started) / 1000.0
	_steps += 1


func get_texture() -> Texture2D:
	if not _initialized or _density.is_empty():
		return null
	return _density[_density_front].get_texture()


## Replaces the solid mask (for example to include a water body) without
## rebuilding the viewports. The size must be unchanged.
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


func get_debug_state() -> Dictionary:
	return {
		"gpu": _initialized,
		"size": _size,
		"steps": _steps,
		"step_ms": _step_ms,
		"vents": vents.size(),
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
	rect.name = "Step"
	rect.position = Vector2.ZERO
	rect.size = Vector2(_size)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("mask_texture", _mask_texture)
	material.set_shader_parameter("field_size", _field_size)
	material.set_shader_parameter("mask_cell_count", _mask_cell_count)
	material.set_shader_parameter("cell_size", FIELD_CELL_SIZE)
	rect.material = material
	viewport.add_child(rect)
	if shader == PSI_SHADER:
		_psi_materials.append(material)
	else:
		_density_materials.append(material)
	return viewport


func _apply_common(material: ShaderMaterial) -> void:
	material.set_shader_parameter("mask_texture", _mask_texture)
	material.set_shader_parameter("field_size", _field_size)
	material.set_shader_parameter("mask_cell_count", _mask_cell_count)
	material.set_shader_parameter("cell_size", FIELD_CELL_SIZE)
	material.set_shader_parameter("wind", wind)
	material.set_shader_parameter("dissipation", dissipation)
	material.set_shader_parameter("buoyancy", buoyancy)


func _apply_density_parameters(material: ShaderMaterial) -> void:
	material.set_shader_parameter("ambient", ambient)
	material.set_shader_parameter("diffusion", diffusion)
	material.set_shader_parameter("refill", refill)
	material.set_shader_parameter("push_radius", push_radius)
	material.set_shader_parameter("push_strength", push_strength)


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
