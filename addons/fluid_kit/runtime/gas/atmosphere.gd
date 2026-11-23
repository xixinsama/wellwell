class_name Atmosphere
extends Node2D

## Room gas: three density layers simulated on the GPU, drawn by one quad.
##
## Bound through WorldSession.register_room_extension, like FogOfWar. The field
## only covers open cells (SolidTiles become an 8 px mask), runs at a fixed
## 30 Hz, and stops stepping once the hero stops moving and the gas settles.
##
## `backend` chooses the implementation per room: AUTO uses the GPU `GasSim`
## (which ping-pongs two 80x45 SubViewports with a fragment shader, so a room of
## gas costs no CPU time) and falls back to the CPU `FogGrid` when no
## RenderingDevice exists (headless, previews); GPU forces the solver and warns
## once if it cannot start; CPU always keeps the fog grid. Both paths share one
## interface, so the render layer, the tests and the demos do not care which one
## runs a room.
##
## The hero pushes the gas aside and leaves a wake; up to four point lights (the
## hero lantern plus authored FogLight nodes) brighten it. This node draws above
## the hero and below FogOfWar, so unexplored cells stay covered.
##
## The field starts empty on purpose: a room-wide veil of gas looks like a second
## fog layer. Visible gas is authored with `GasVent` nozzles (a hard, fast jet) and
## with `GasField` markers in rooms that want the haze back.

enum Backend { AUTO, GPU, CPU }

const FOG_GRID := preload("res://addons/fluid_kit/runtime/gas/fog_grid.gd")
const GAS_SIM := preload("res://addons/fluid_kit/runtime/gas/gas_sim.gd")
const FOG_SHADER := preload("res://addons/fluid_kit/runtime/gas/fog_layer.gdshader")

const CHUNK_PIXELS := Vector2(320.0, 180.0)
## CPU fallback grid: coarse on purpose, ~400 cells for a whole room.
const CELL_PIXELS := 12.0
## The solid mask stays on the terrain tile grid so it matches the collision.
const TILE_PIXELS := 8.0
const LIGHT_GROUP := &"fog_light"
const ATMOSPHERE_GROUP := &"atmosphere"
const MAX_LIGHTS := 4
const MAX_STATIC_LIGHTS := 3
const MAX_VENTS := 4
## 64x64 tiling blue-noise threshold, baked by tools/bake_blue_noise.gd.
const STIPPLE_TEXTURE := "res://resources/textures/blue_noise_64.png"

## Which gas implementation this node binds for the next room. AUTO keeps the
## historical behaviour (GPU when a RenderingDevice exists, CPU otherwise), GPU
## forces the solver and degrades to the CPU grid with one warning when it cannot
## start, CPU keeps the fog grid even on a GPU. The choice is per bind, so
## changing it takes effect on the next `bind_room_with_origin()`.
@export var backend: Backend = Backend.AUTO
## Simulation steps per second. This is the overall "gas speed" knob: higher
## values advance the same shader more often. The GPU cost stays tiny (two 80x45
## passes); the CPU cost is one dispatch per step.
@export_range(10.0, 60.0, 1.0) var sim_hz := 30.0
## Average density each of the three gases tries to keep in the room
## (x = heavy, y = neutral, z = light).
##
## Zero by default: a room-wide veil of gas reads as fog, and the rooms use
## authored GasVent nozzles for visible gas instead. A recipe that wants the old
## haze adds a GasField marker (or raises this back to 0.25, 0.2, 0.3).
@export var gas_ambient := Vector3.ZERO
## Navier-Stokes: buoyancy acceleration per unit density, in px/s^2, and the\r
## velocity dissipation per second.
@export var gas_buoyancy := Vector3(240.0, 0.0, 300.0)
@export_range(0.0, 3.0, 0.05) var gas_dissipation := 0.4
## Pressure Jacobi iterations per step (the Poisson solve accuracy).
@export_range(4, 64, 1) var pressure_iterations := 16
## World pixels per simulation cell. 4 keeps the nozzle jets and the wisp scale the
## project tuned for; 2 or 1 resolve the plumes down to the pixel grid, at a cost that
## grows with the square of the ratio (a one-screen room is 80x45 cells at 4 px,
## 160x90 at 2 px and 320x180 at 1 px, and every step runs 20 passes over all of them).
@export_range(1.0, 8.0, 1.0) var gas_cell_pixels := 4.0
## Kinematic viscosity in 1/s: how much the gas drags on itself.
@export_range(0.0, 20.0, 0.01) var gas_viscosity := 0.0
## Vorticity confinement. The stable-fluids trace-back averages the velocity every
## step, which erases the small eddies a plume is made of; this force pushes each
## vortex inwards along the gradient of |curl| and re-sharpens them, so the mist
## keeps curls instead of turning into a smooth smear. 0 is the plain solver.
@export_range(0.0, 40.0, 0.5) var gas_vorticity := 10.0
## How strongly the field's own advected detail channel modulates the mist. The
## detail is a passive scalar carried by the flow (see gas_density.gdshader), so it
## stretches with the gas; 0 leaves the field perfectly smooth.
@export_range(0.0, 1.0, 0.01) var detail_amount := 1.0
@export_range(0.0, 8.0, 0.05) var detail_refresh := 4.0
@export_range(1.0, 30.0, 0.5) var detail_hz := 6.0
## Stylised threshold: 0 = 4x4 ordered Bayer tile, 1 = 64x64 blue-noise tile,
## 2 = white noise. Only useful for A/B captures; 1 is the shipped look.
@export_range(0, 2, 1) var stipple_mode := 1
@export_range(2.0, 64.0, 1.0) var stipple_steps := 32.0
## Volumetric self-shadowing strength: how much gas between a pixel and the key
## light darkens that pixel. 0 disables the extra taps.
@export_range(0.0, 4.0, 0.05) var volume_shadow := 0.9
@export_range(0.0, 1.0, 0.01) var volume_weight := 0.55
## Exponential gas fade per second (0 = the gas never fades on its own). With no
## ambient gas to fall back on, vent jets need a little decay or they pile up in
## a closed room and turn back into fog.
@export_range(0.0, 3.0, 0.05) var gas_decay := 0.12
@export_range(0.0, 1.0, 0.01) var gas_diffusion := 0.25
## Pulls the field back towards `gas_ambient` every step. Only useful together
## with a non-zero ambient, so it is off by default.
@export_range(0.0, 2.0, 0.01) var gas_refill := 0.0
## Horizontal wind in pixels per second, plus a small lift. The main
## "how fast does the gas blow across the room" knob.
@export var gas_wind := Vector2(20.0, -2.5)
## How much the wind gusts, as a share of `gas_wind`. 0 is a steady draught.
@export_range(0.0, 1.0, 0.01) var wind_gust := 0.55
@export_range(0.02, 2.0, 0.01) var wind_gust_speed := 0.18
## Vertical bob added to the gust, so the mist rolls instead of sliding.
@export_range(0.0, 30.0, 0.5) var wind_lift := 4.0
## Radius in pixels around the hero where gas is pushed aside and thinned.
@export_range(8.0, 96.0, 1.0) var push_radius := 34.0
@export_range(0.0, 3.0, 0.01) var push_strength := 1.4

@export_range(0.0, 1.0, 0.01) var ambient_density := 0.0
@export var heavy_color := Color(1.0, 0.3, 0.08, 1.0)
@export var neutral_color := Color(0.1, 0.82, 1.0, 1.0)
@export var light_color := Color(1.0, 0.95, 0.18, 1.0)
@export var gas_alpha := Vector3(0.62, 0.5, 0.48)
@export_range(0.0, 2.0, 0.01) var base_alpha := 0.78
@export_range(0.0, 3.0, 0.01) var light_alpha := 0.9
@export_range(0.0, 1.0, 0.01) var noise_amount := 0.45
@export var lit_color := Color(1.0, 0.9, 0.72, 1.0)
@export_range(0.0, 200.0, 1.0) var player_light_radius := 74.0
@export_range(0.0, 3.0, 0.05) var player_light_energy := 1.0
@export var player_light_color := Color(1.0, 0.82, 0.52, 1.0)

var _grid: FogGrid
var _gas: GasSim
var _columns := 0
var _rows := 0
var _room_rect := Rect2()
var _terrain: Node
var _solid_tiles: TileMapLayer
var _player: Node2D
var _quad: MeshInstance2D
var _material: ShaderMaterial
var _density_image: Image
var _density_texture: ImageTexture
var _solid_mask := PackedByteArray()
var _mask_columns := 0
var _mask_rows := 0
var _static_lights: Array[Node] = []
## Room light map (see LightField). Kept in sync so the mist is lit by the same
## map as everything else, walls and shadows included.
var _light_texture: Texture2D
var _light_pixels := Vector2i.ZERO
var _settings_source: Object
var _water: Node
var _water_mask := PackedByteArray()
var _water_mask_timer := 0.0
var _accumulator := 0.0
var _step_interval := 1.0 / 30.0
var _time := 0.0
var _needs_upload := false
var _step_ms := 0.0
var _steps := 0
var _enabled := true


func _ready() -> void:
	add_to_group(ATMOSPHERE_GROUP)


func _exit_tree() -> void:
	remove_from_group(ATMOSPHERE_GROUP)


# ---------------------------------------------------------------------------- binding

func bind_room_with_origin(room_data: Variant, terrain_root: Node, origin_chunk: Vector2i) -> bool:
	clear_room()
	if room_data == null or terrain_root == null:
		return false
	var sizes: Variant = room_data.get("room_size_chunks")
	var room_chunks := Vector2i.ONE if sizes == null else Vector2i(sizes)
	_terrain = _resolve_terrain(terrain_root)
	if _terrain == null:
		return true
	_solid_tiles = _terrain.get_node_or_null("SolidTiles") as TileMapLayer
	var room_cell_rect := RoomGrid.get_room_cell_rect(origin_chunk, room_chunks)
	_room_rect = Rect2(
		Vector2(room_cell_rect.position) * Vector2(RoomGrid.DEFAULT_CELL_SIZE),
		Vector2(room_cell_rect.size) * Vector2(RoomGrid.DEFAULT_CELL_SIZE)
	)
	_columns = maxi(int(ceil(_room_rect.size.x / CELL_PIXELS)), 1)
	_rows = maxi(int(ceil(_room_rect.size.y / CELL_PIXELS)), 1)
	_solid_mask = _build_solid_mask()
	_static_lights = _collect_static_lights()
	_step_interval = 1.0 / maxf(sim_hz, 1.0)

	# A GasField marker in the room can override the ambient gas (for example a
	# clean room with no gas at all, only trails).
	var field := _find_gas_field()
	var ambient := gas_ambient
	var decay := gas_decay
	var diffusion := gas_diffusion
	var refill := gas_refill
	if field != null:
		ambient = field.get("ambient")
		decay = float(field.get("decay"))
		diffusion = float(field.get("diffusion"))
		refill = float(field.get("refill"))
	_bind_gas_backend(ambient, decay, diffusion, refill)
	_build_render()
	_refresh_gas_mask()
	_needs_upload = true
	_accumulator = 0.0
	_time = 0.0
	_refresh_enabled()
	return true

func clear_room() -> void:
	if _gas != null:
		_gas.queue_free()
		_gas = null
	_grid = null
	_columns = 0
	_rows = 0
	_solid_tiles = null
	_terrain = null
	_static_lights.clear()
	_room_rect = Rect2()
	_accumulator = 0.0
	_needs_upload = true
	if _quad != null:
		_quad.queue_free()
		_quad = null
	_material = null
	_density_image = null
	_density_texture = null
	_solid_mask = PackedByteArray()
	_water_mask = PackedByteArray()
	_water = null
	_water_mask_timer = 0.0
	_mask_columns = 0
	_mask_rows = 0


func bind_player(player: Node2D) -> void:
	_player = player


## Comes from the session, like FogOfWar's settings source.
func bind_settings_source(source: Object) -> void:
	if _settings_source != null and is_instance_valid(_settings_source) and _settings_source.has_signal("settings_changed"):
		var old_callback := Callable(self, "_on_settings_changed")
		if _settings_source.is_connected("settings_changed", old_callback):
			_settings_source.disconnect("settings_changed", old_callback)
	_settings_source = source
	if source != null and source.has_signal("settings_changed"):
		var callback := Callable(self, "_on_settings_changed")
		if not source.is_connected("settings_changed", callback):
			source.connect("settings_changed", callback)
	_refresh_enabled()


# ---------------------------------------------------------------------------- queries

func is_ready() -> bool:
	return _gas != null or _grid != null


func get_debug_state() -> Dictionary:
	var active_backend := "none"
	if _gas != null:
		active_backend = "gpu"
	elif _grid != null:
		active_backend = "cpu"
	return {
		"ready": is_ready(),
		# The key keeps its historical values ("gpu"/"cpu"/"none") and reports the
		# implementation actually running, while the request keys expose what the
		# exported backend asked for (and whether a GPU request had to degrade).
		"backend": active_backend,
		"requested_backend": _backend_name(backend),
		"fallback": backend == Backend.GPU and _grid != null,
		"enabled": _enabled,
		"active": _gas != null or (_grid != null and _grid.is_active()),
		"lights": _static_lights.size() + (1 if is_instance_valid(_player) else 0),
		"step_ms": _step_ms,
		"steps": _steps,
		"sim_hz": sim_hz,
		"gas": _gas.get_debug_state() if _gas != null else {},
	}


func get_solid_mask() -> PackedByteArray:
	return _solid_mask


func get_density_values() -> PackedFloat32Array:
	return _grid.get_density_values() if _grid != null else PackedFloat32Array()


## The projected velocity image (RG in cells/second), for debugging only.
func get_gas_velocity_image() -> Image:
	return _gas.get_velocity_image() if _gas != null else null


## Debug only: the intermediate (pre-projection) velocity image.
func get_gas_mid_velocity_image() -> Image:
	return _gas.get_mid_velocity_image() if _gas != null else null


## Debug only: the final pressure field image.
func get_gas_pressure_image() -> Image:
	return _gas.get_pressure_image() if _gas != null else null


## Debug only: the gas solid mask.
func get_gas_mask_image() -> Image:
	return _gas.get_mask_image() if _gas != null else null


## The current GPU gas texture as an image, for debugging and screenshots.
func get_gas_image() -> Image:
	if _gas == null:
		return null
	var texture := _gas.get_texture()
	if texture == null:
		return null
	return texture.get_image()


## A one-shot blast in world pixels: pushes the gas outward from `world_position`
## and injects a denser flash. Strength is in pixels per second, density in gas
## units (0.5 is already very visible).
func trigger_explosion(world_position: Vector2, radius := 30.0, strength := 150.0, density := 1.0) -> void:
	if _gas == null:
		return
	_gas.call("trigger_impulse", world_position - _room_rect.position, radius, strength / TILE_PIXELS * 2.0, density)


## A moving obstacle (a pillar, a piston) that drags and displaces the gas.
func set_gas_mover(world_center: Vector2, half_size: Vector2, world_velocity: Vector2) -> void:
	if _gas == null:
		return
	_gas.call("set_mover", world_center - _room_rect.position, half_size, world_velocity)


func clear_gas_mover() -> void:
	if _gas != null:
		_gas.call("clear_mover")


## A moving trail source in world pixels. The gas is injected at `world_position`
## and immediately given `world_velocity` as its initial velocity.
func set_gas_emitter(world_position: Vector2, radius: float, rate: float, world_velocity: Vector2, channel := 1.0) -> void:
	if _gas == null:
		return
	_gas.call("set_emitter", world_position - _room_rect.position, radius, rate, world_velocity, channel)


func clear_gas_emitter() -> void:
	if _gas != null:
		_gas.call("clear_emitter")


## The room rectangle in world pixels (where the gas field currently lives).
func get_room_rect() -> Rect2:
	return _room_rect


## Re-collect the room's GasVent nodes after changing their rate or jet speed.
func refresh_vents() -> void:
	if _gas != null:
		_gas.set("vents", _collect_vents())


## Turns the gas simulation and its layer on or off (the Game setting). This only
## parks the bound field: neither the GPU pipeline nor the CPU grid is torn down,
## so re-enabling resumes the same gas instead of rebuilding it from scratch.
func set_enabled(value: bool) -> void:
	_enabled = bool(value)
	if _quad != null:
		_quad.visible = _enabled
	if not _enabled:
		_accumulator = 0.0
		_needs_upload = true


func is_enabled() -> bool:
	return _enabled


# ---------------------------------------------------------------------------- simulation

func _process(delta: float) -> void:
	if not _enabled or not is_ready():
		return
	var safe_delta := maxf(delta, 0.0)
	_time += safe_delta
	_update_lights()
	if _gas != null:
		_water_mask_timer = maxf(_water_mask_timer - safe_delta, 0.0)
		if _water_mask_timer <= 0.0:
			_water_mask_timer = 0.25
			_refresh_gas_mask()
	_accumulator += safe_delta
	if _accumulator < _step_interval:
		return
	# One step per rendered frame: a gas step samples the buffers written by the
	# previous step, so two steps in one frame would read a half-updated pair.
	_accumulator = 0.0
	var player_position := Vector2.ZERO
	var player_velocity := Vector2.ZERO
	if is_instance_valid(_player):
		player_position = _player.global_position + Vector2(0.0, -3.0)
		player_velocity = _player.get("velocity") if _player is CharacterBody2D else Vector2.ZERO
	var started := Time.get_ticks_usec()
	if _gas != null:
		# Gusts: the draught breathes, so the mist visibly rolls and calms instead
		# of sliding at a constant speed.
		if wind_gust > 0.0:
			var phase := _time * wind_gust_speed * TAU
			var gust := 1.0 + wind_gust * (
				sin(phase) * 0.62 + sin(phase * 2.37 + 1.7) * 0.38
			)
			_gas.set("wind", gas_wind * gust + Vector2(0.0, sin(phase * 0.7) * wind_lift))
		# The gas field is room-local, the player is in world space.
		_gas.step(_step_interval, player_position - _room_rect.position, player_velocity)
		if _material != null:
			_material.set_shader_parameter("gas_texture", _gas.get_texture())
			# The tracer lives in the velocity field, which ping-pongs, so the
			# sampler has to be re-bound after every step.
			_material.set_shader_parameter("detail_tex", _gas.get_velocity_texture())
	else:
		_grid.step(_step_interval, player_position, player_velocity)
		_upload_density()
	_step_ms = float(Time.get_ticks_usec() - started) / 1000.0
	_steps += 1


## Gas cannot enter a solid tile and cannot enter a water body either: a heavy
## gas sinking into a pool would tint the water instead of sitting above it.
## The water surface moves, so the mask is rebuilt a few times a second, not per
## step.
func _refresh_gas_mask() -> void:
	if _gas == null or _solid_mask.is_empty():
		return
	if _water == null or not is_instance_valid(_water):
		_water = get_tree().get_first_node_in_group(&"water_field")
	var has_water := _water != null and is_instance_valid(_water) and bool(_water.call("is_ready"))
	_water_mask.resize(_solid_mask.size())
	var index := 0
	for row: int in _mask_rows:
		for column: int in _mask_columns:
			index = row * _mask_columns + column
			if _solid_mask[index] != 0:
				_water_mask[index] = 1
				continue
			if not has_water:
				_water_mask[index] = 0
				continue
			var world := _room_rect.position + Vector2(
				(float(column) + 0.5) * TILE_PIXELS,
				(float(row) + 0.5) * TILE_PIXELS
			)
			var surface := float(_water.call("get_surface_y_at", world.x))
			_water_mask[index] = 1 if is_finite(surface) and world.y >= surface else 0
	_gas.update_mask(_water_mask)


func _on_settings_changed() -> void:
	_refresh_enabled()


func _refresh_enabled() -> void:
	var enabled := true
	if _settings_source != null and _settings_source.has_method("is_atmosphere_enabled"):
		enabled = bool(_settings_source.call("is_atmosphere_enabled"))
	set_enabled(enabled)


# ---------------------------------------------------------------------------- construction

## Picks and creates the gas field for the room that was just bound. The GPU path
## is only attempted when this backend allows it; a forced GPU that cannot start
## warns once and degrades to the CPU grid, so a room is never left unbound.
func _bind_gas_backend(ambient: Vector3, decay: float, diffusion: float, refill: float) -> void:
	_gas = null
	_grid = null
	if _should_try_gpu():
		_gas = _create_gas_sim(ambient, decay, diffusion, refill)
		if _gas != null:
			_gas.set("vents", _collect_vents())
		elif backend == Backend.GPU:
			push_warning("Atmosphere: the GPU gas solver could not start; using the CPU fog grid.")
	if _gas == null:
		_grid = _create_cpu_grid()


## AUTO keeps the historical behaviour: GPU when a RenderingDevice exists, CPU
## otherwise and silently. A forced GPU without a device warns once instead of
## failing the bind, while CPU never looks at the renderer at all.
func _should_try_gpu() -> bool:
	if backend == Backend.CPU:
		return false
	if RenderingServer.get_rendering_device() != null:
		return true
	if backend == Backend.GPU:
		push_warning("Atmosphere: GPU backend requested without a RenderingDevice; using the CPU fog grid.")
	return false


## Builds and starts the GPU solver, returning null when setup() refused it (for
## example a zero-sized room) so the caller can fall back to the CPU grid.
func _create_gas_sim(ambient: Vector3, decay: float, diffusion: float, refill: float) -> GasSim:
	var gas := GAS_SIM.new() as GasSim
	gas.set("ambient", ambient)
	gas.set("cell_size", gas_cell_pixels)
	gas.set("decay", decay)
	gas.set("buoyancy", gas_buoyancy)
	gas.set("dissipation", gas_dissipation)
	gas.set("viscosity", gas_viscosity)
	gas.set("vorticity", gas_vorticity)
	gas.set("detail_refresh", detail_refresh)
	gas.set("detail_hz", detail_hz)
	gas.set("pressure_iterations", pressure_iterations)
	gas.set("diffusion", diffusion)
	gas.set("refill", refill)
	gas.set("wind", gas_wind)
	gas.set("push_radius", push_radius)
	gas.set("push_strength", push_strength)
	add_child(gas)
	if bool(gas.call("setup", _room_rect.size, _solid_mask, _mask_columns, _mask_rows)):
		return gas
	gas.queue_free()
	return null


## The CPU fog grid is the always-available path: coarse cells, no rendering
## device needed, and the same interface the tests and previews use.
func _create_cpu_grid() -> FogGrid:
	var grid := FOG_GRID.new() as FogGrid
	grid.cell_size = CELL_PIXELS
	grid.ambient_density = ambient_density
	grid.push_radius = push_radius
	grid.setup(Vector2i(_columns, _rows), _room_rect.position, CELL_PIXELS)
	grid.set_solid_mask(_solid_mask_at_grid_resolution())
	return grid


## Stable debug spelling of the exporter-facing enum. The actual backend strings
## stay "gpu"/"cpu"/"none" because existing debug tools already read them.
func _backend_name(value: Backend) -> String:
	match value:
		Backend.GPU:
			return "gpu"
		Backend.CPU:
			return "cpu"
		_:
			return "auto"


func _resolve_terrain(terrain_root: Node) -> Node:
	var terrain := terrain_root.get_node_or_null("Terrain")
	if terrain != null:
		return terrain
	if terrain_root.name == "Terrain":
		return terrain_root
	return null


## The gas mask is one texel per terrain tile (8 px), independent of the coarse
## simulation grid, so the gas is cut exactly at the collision silhouette.
func _build_solid_mask() -> PackedByteArray:
	_mask_columns = maxi(int(ceil(_room_rect.size.x / TILE_PIXELS)), 1)
	_mask_rows = maxi(int(ceil(_room_rect.size.y / TILE_PIXELS)), 1)
	var mask := PackedByteArray()
	mask.resize(_mask_columns * _mask_rows)
	mask.fill(0)
	if _solid_tiles == null:
		return mask
	var tile_size := Vector2(TILE_PIXELS, TILE_PIXELS)
	if _solid_tiles.tile_set != null:
		tile_size = Vector2(_solid_tiles.tile_set.tile_size)
	for cell: Vector2i in _solid_tiles.get_used_cells():
		var centre := _solid_tiles.to_global(_solid_tiles.map_to_local(cell))
		var start := (centre - tile_size * 0.5 - _room_rect.position) / TILE_PIXELS
		var end := (centre + tile_size * 0.5 - Vector2(0.001, 0.001) - _room_rect.position) / TILE_PIXELS
		var from := Vector2i(floori(start.x), floori(start.y))
		var to := Vector2i(floori(end.x), floori(end.y))
		if to.x < 0 or to.y < 0 or from.x >= _mask_columns or from.y >= _mask_rows:
			continue
		for y: int in range(maxi(from.y, 0), mini(to.y, _mask_rows - 1) + 1):
			for x: int in range(maxi(from.x, 0), mini(to.x, _mask_columns - 1) + 1):
				mask[y * _mask_columns + x] = 1
	return mask


## The CPU fallback grid is coarser than the tile mask, so downsample it to the
## grid's own resolution before handing it over.
func _solid_mask_at_grid_resolution() -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(_columns * _rows)
	mask.fill(0)
	for row: int in _rows:
		for column: int in _columns:
			var world := _room_rect.position + Vector2(
				(float(column) + 0.5) * CELL_PIXELS,
				(float(row) + 0.5) * CELL_PIXELS
			)
			var tile := Vector2i(
				floori((world.x - _room_rect.position.x) / TILE_PIXELS),
				floori((world.y - _room_rect.position.y) / TILE_PIXELS)
			)
			if tile.x < 0 or tile.y < 0 or tile.x >= _mask_columns or tile.y >= _mask_rows:
				continue
			mask[row * _columns + column] = _solid_mask[tile.y * _mask_columns + tile.x]
	return mask


func _find_gas_field() -> Node:
	if not is_inside_tree():
		return null
	for node: Node in get_tree().get_nodes_in_group(&"gas_field"):
		if not is_instance_valid(node) or not node is Node2D:
			continue
		if _room_rect.has_point((node as Node2D).global_position):
			return node
	return null


func _collect_static_lights() -> Array[Node]:
	var result: Array[Node] = []
	if not is_inside_tree():
		return result
	for node: Node in get_tree().get_nodes_in_group(LIGHT_GROUP):
		if not is_instance_valid(node):
			continue
		if not node is Node2D or not node.has_method("get_energy_at"):
			continue
		if not _room_rect.has_point((node as Node2D).global_position):
			continue
		result.append(node)
	return result


## Up to four GasVent outlets that belong to this room, in room-local pixels.
func _collect_vents() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not is_inside_tree():
		return result
	for node: Node in get_tree().get_nodes_in_group(&"gas_vent"):
		if not is_instance_valid(node) or not node.has_method("to_light_data"):
			continue
		var data: Dictionary = node.call("to_light_data")
		var vent_position: Vector2 = data.get("position", Vector2.ZERO)
		if not _room_rect.has_point(vent_position):
			continue
		data["position"] = vent_position - _room_rect.position
		result.append(data)
		if result.size() >= MAX_VENTS:
			break
	return result


## Called by LightField when a room is bound: the mist takes the same light map,
## so a lamp behind a wall stops lighting the gas on the near side.
func set_light_field(texture: Texture2D, pixels: Vector2i, _origin_pixels: Vector2i) -> void:
	_light_texture = texture
	_light_pixels = pixels
	_apply_light_field()


func _apply_light_field() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("light_tex", _light_texture)
	_material.set_shader_parameter("light_pixels", Vector2(_light_pixels))
	_material.set_shader_parameter("map_gain", 1.0)
	# An unbound sampler reads as white, which would light the whole mist, so the
	# map only participates when a room actually handed one over.
	# 1.4 was tuned while the shader sampled the map with world coordinates by mistake,
	# which clamped it to one column; now that the map is sampled room-locally the mist
	# is genuinely lit, and 0.5 keeps its mean contribution where it was.
	_material.set_shader_parameter("map_weight", 0.5 if _light_texture != null else 0.0)


func _build_render() -> void:
	_material = ShaderMaterial.new()
	_material.shader = FOG_SHADER
	_material.set_shader_parameter("field_origin", _room_rect.position)
	_material.set_shader_parameter("field_size", _room_rect.size)
	_material.set_shader_parameter("mask_cell_count", Vector2(float(_mask_columns), float(_mask_rows)))
	_material.set_shader_parameter("heavy_color", heavy_color)
	_material.set_shader_parameter("neutral_color", neutral_color)
	_material.set_shader_parameter("light_color", light_color)
	_material.set_shader_parameter("gas_alpha", gas_alpha)
	_material.set_shader_parameter("base_alpha", base_alpha)
	_material.set_shader_parameter("light_alpha", light_alpha)
	_material.set_shader_parameter("noise_amount", noise_amount)
	_material.set_shader_parameter("lit_tint", lit_color)
	_material.set_shader_parameter("volume_shadow", volume_shadow)
	_material.set_shader_parameter("volume_weight", volume_weight)
	# The stylised threshold. The blue-noise tile is the shipped kernel; a build that
	# is missing the asset falls back to the ordered tile rather than silently
	# sampling an unbound sampler (which reads white and would lighten every level).
	var stipple: Texture2D = null
	if stipple_mode > 0 and ResourceLoader.exists(STIPPLE_TEXTURE):
		stipple = load(STIPPLE_TEXTURE) as Texture2D
	_material.set_shader_parameter("stipple_tex", stipple)
	_material.set_shader_parameter("stipple_mode", float(stipple_mode) if stipple != null else 0.0)
	_material.set_shader_parameter("stipple_steps", stipple_steps)
	# The CPU fog grid has no detail tracer, so it must not read one: the shader
	# falls back to its screen-space noise in that case.
	_material.set_shader_parameter("detail_amount", detail_amount if _gas != null else 0.0)
	_apply_light_field()

	var solid_bytes := PackedByteArray()
	solid_bytes.resize(_mask_columns * _mask_rows)
	for index: int in solid_bytes.size():
		solid_bytes[index] = 255 if _solid_mask[index] != 0 else 0
	var solid_image := Image.create_from_data(_mask_columns, _mask_rows, false, Image.FORMAT_R8, solid_bytes)
	_material.set_shader_parameter("solid_texture", ImageTexture.create_from_image(solid_image))

	if _gas != null:
		_material.set_shader_parameter("gas_texture", _gas.get_texture())
		# Bind the tracer immediately: an unbound sampler reads white, which would
		# make the first frames' wisp a constant 1.0 and the mist 45% too bright.
		_material.set_shader_parameter("detail_tex", _gas.get_velocity_texture())
	else:
		_density_image = Image.create(_columns, _rows, false, Image.FORMAT_RGB8)
		_density_image.fill(Color(0.0, 0.0, 0.0, 1.0))
		_density_texture = ImageTexture.create_from_image(_density_image)
		_material.set_shader_parameter("gas_texture", _density_texture)

	_quad = MeshInstance2D.new()
	_quad.name = "GasLayer"
	var mist_mesh := QuadMesh.new()
	mist_mesh.size = Vector2(1.0, 1.0)
	_quad.mesh = mist_mesh
	_quad.scale = _room_rect.size
	_quad.position = _room_rect.position + _room_rect.size * 0.5
	# Below the light passes (shade 8, glow 9) so the mist is darkened like

	# everything else; the fog still covers it.
	_quad.z_index = 5
	_quad.z_as_relative = false
	_quad.material = _material
	_quad.visible = _enabled
	add_child(_quad)


## CPU fallback upload: the single CPU density is written into all three gas
## channels so the render shader has the same input either way.
func _upload_density() -> void:
	if _density_image == null or _density_texture == null or _grid == null:
		return
	var values := _grid.get_density_values()
	var count := mini(values.size(), _columns * _rows)
	var bytes := PackedByteArray()
	bytes.resize(count * 3)
	for index: int in count:
		var value := int(clampf(values[index], 0.0, 1.0) * 255.0)
		var offset := index * 3
		bytes[offset] = value
		bytes[offset + 1] = value
		bytes[offset + 2] = value
	_density_image.set_data(_columns, _rows, false, Image.FORMAT_RGB8, bytes)
	_density_texture.update(_density_image)


func _update_lights() -> void:
	if _material == null:
		return
	var slots: Array[Dictionary] = []
	if is_instance_valid(_player) and player_light_energy > 0.0:
		slots.append({
			"position": _player.global_position + Vector2(0.0, -4.0),
			"radius": player_light_radius,
			"energy": player_light_energy,
			"color": player_light_color,
		})
	var candidates: Array[Dictionary] = []
	for node: Node in _static_lights:
		if not is_instance_valid(node):
			continue
		var light := node as Node2D
		var energy := float(node.call("get_energy_at", _time))
		if energy <= 0.0:
			continue
		candidates.append({
			"position": light.global_position,
			"radius": float(node.get("radius")),
			"energy": energy,
			"color": node.get("color"),
		})
	var player_position := _player.global_position if is_instance_valid(_player) else _room_rect.get_center()
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return left["position"].distance_squared_to(player_position) < right["position"].distance_squared_to(player_position)
	)
	for index: int in mini(candidates.size(), MAX_STATIC_LIGHTS):
		slots.append(candidates[index])
	for index: int in MAX_LIGHTS:
		var slot_name := "light%d" % index
		var color_name := "light%d_color" % index
		if index >= slots.size():
			_material.set_shader_parameter(slot_name, Vector4.ZERO)
			_material.set_shader_parameter(color_name, Color(0.0, 0.0, 0.0, 1.0))
			continue
		var slot: Dictionary = slots[index]
		var light_position: Vector2 = slot["position"]
		_material.set_shader_parameter(
			slot_name,
			Vector4(light_position.x, light_position.y, float(slot["radius"]), float(slot["energy"]))
		)
		_material.set_shader_parameter(color_name, slot["color"])
	# The volume pass marches towards the key light, which in this game is the
	# hero's lantern; `slots` puts it first, so it is the one that shapes the depth
	# of the cloud. No light means no direction, so the pass switches itself off.
	var volume := Vector4(-9999.0, -9999.0, 0.0, 0.0)
	if volume_shadow > 0.0 and not slots.is_empty():
		var key: Dictionary = slots[0]
		var key_position: Vector2 = key["position"]
		volume = Vector4(key_position.x, key_position.y, 1.0, 0.0)
	_material.set_shader_parameter("volume_light", volume)
