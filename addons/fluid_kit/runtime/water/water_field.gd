class_name WaterField
extends Node2D

## Runtime water for the active room.
##
## Bound through WorldSession.register_room_extension, like FogOfWar: the field
## scans the room's SolidTiles to build a one-dimensional column height field
## (one column per 4 px), fills the authored WaterBasin markers and blocks the
## columns covered by WaterGate markers until those gates open. The simulation
## runs at a fixed 60 Hz and sleeps when nothing moves; the surface is drawn by a
## single quad reading a one-row column texture.
##
## Splashes are requested by the player component: they displace the simulation
## locally (the surface bulges and settles) and spawn one PixelFX water splash
## whose size follows the impact speed.

## Emitted on every impact, so the game can spawn its own splash effect. The
## plugin itself has no art dependency.
signal splash_requested(world_position: Vector2, power: float)

const SURFACE_SHADER := preload("res://addons/fluid_kit/runtime/water/water_surface.gdshader")
const FALL_SHADER := preload("res://addons/fluid_kit/runtime/water/water_fall.gdshader")

const CHUNK_PIXELS := Vector2(320.0, 180.0)
const TILE_PIXELS := 8.0
## One column per tile: the wider column diffuses across a pool about four times
## faster than a 4 px column at the same stability, so wide tanks stay level
## while the water drains.
const COLUMN_WIDTH := 8.0
## Visual ripples: impact x, impact y, age (s), strength. Handed to the surface
## shader; the water body itself is never displaced by an impact.
const RIPPLE_SLOTS := 3
## Seconds a ripple stays in the list. The amplitude is gone before this, it only
## keeps the slot busy.
const RIPPLE_LIFE := 2.0
## A ripple carries at least this many columns, so an impact in a narrow channel is a
## local bump instead of a one-column spike.
const RIPPLE_MIN_REACH_CELLS := 8
## Two column surfaces further apart than this (in columns) are different bodies: the
## basin under a spill lip must not carry the ripple of the basin above it.
const RIPPLE_BODY_TOLERANCE_CELLS := 2.5
## Ripple amplitude in pixels at the impact point.
const RIPPLE_AMPLITUDE := 3.6
## Ripple ring speed (px/s) and damping (1/s).
const RIPPLE_SPEED := 64.0
const RIPPLE_DAMPING := 1.1
## One waterfall column quad per spill lip.
const MAX_FALLS := 4
## A falling column can widen to this many 8 px columns with a big flow.
const MAX_FALL_COLUMNS := 3
## Two simulation substeps per 60 Hz tick keep a wide pool level while the
## discrete column diffusion stays stable (flow_rate / SIM_HZ <= 0.5).
const SIM_HZ := 120.0
const SIM_STEP := 1.0 / SIM_HZ
## Water surface texture upload rate (the simulation still runs at SIM_HZ).
const UPLOAD_INTERVAL := 1.0 / 30.0
const BASIN_GROUP := &"water_basin"
const GATE_GROUP := &"water_gate"
const WATER_GROUP := &"water_field"

@export_range(16.0, 160.0, 1.0) var max_depth := 64.0
## Column-to-column transfer coefficient (1/s). The discrete diffusion is stable
## while flow_rate / SIM_HZ stays below 0.5; 54 at 120 Hz levels a 30-column tank
## in about two seconds.
@export_range(1.0, 59.0, 0.5) var flow_rate := 54.0
@export_range(0.0, 20.0, 0.5) var waterfall_min_drop := 5.0
## Optional splash effect scene spawned on every impact. The plugin only emits
## `splash_requested`; the game assigns its own effect scene here.
@export var splash_scene: PackedScene
## How strongly the surface mirrors the room light map. 0 disables it.
@export_range(0.0, 2.0, 0.01) var water_reflection := 0.8

var _sim: WaterSimulation
var _columns := 0
var _origin_x := 0.0
var _field_top := 0.0
var _field_height := 184.0
var _room_rect := Rect2()
var _terrain: Node
var _solid_tiles: TileMapLayer
var _gates: Array[Dictionary] = []
var _player: Node2D
var _quad: MeshInstance2D
var _material: ShaderMaterial
var _image: Image
var _texture: ImageTexture
var _falls: Array[Dictionary] = []
var _fall_splash_timer := 0.0
var _accumulator := 0.0
var _needs_texture := true
var _step_ms := 0.0
var _steps := 0
var _texture_updates := 0
var _upload_accumulator := 0.0
var _ripples: Array[Vector4] = []
## 1/e reach in px of the ripple in the same slot of `_ripples`: how far that swell
## carries. Kept next to the ripple list instead of inside the vector because the
## shader already uses all four components of it.
var _ripple_reach: Array[float] = []
## Room light map (see LightField), for the surface reflection.
var _light_texture: Texture2D
var _light_pixels := Vector2i.ZERO


func _ready() -> void:
	add_to_group(WATER_GROUP)


func _exit_tree() -> void:
	remove_from_group(WATER_GROUP)


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
	if _solid_tiles == null:
		return true
	_room_rect = Rect2(Vector2(origin_chunk) * CHUNK_PIXELS, Vector2(room_chunks) * CHUNK_PIXELS)
	var basins := _collect_nodes(BASIN_GROUP, _room_rect)
	if basins.is_empty():
		return true
	var span := _basin_span(basins)
	if span.size.x < COLUMN_WIDTH:
		return false
	_origin_x = floorf(span.position.x / COLUMN_WIDTH) * COLUMN_WIDTH
	var right := ceilf(span.end.x / COLUMN_WIDTH) * COLUMN_WIDTH
	_columns = int(round((right - _origin_x) / COLUMN_WIDTH))
	if _columns <= 0 or _columns > 1024:
		return false
	_field_top = _room_rect.position.y
	_field_height = _room_rect.size.y

	var floors := PackedFloat32Array()
	floors.resize(_columns)
	var blocked := PackedByteArray()
	blocked.resize(_columns)
	for index: int in _columns:
		var column_x := _origin_x + (index + 0.5) * COLUMN_WIDTH
		var floor_y := _sample_floor(column_x, _room_rect.end.y)
		if floor_y <= 0.0:
			blocked[index] = 1
			floors[index] = _room_rect.end.y
		else:
			floors[index] = floor_y

	var simulation := WaterSimulation.new()
	simulation.column_width = COLUMN_WIDTH
	simulation.max_depth = max_depth
	simulation.flow_rate = flow_rate
	simulation.setup(Vector2(_origin_x, _field_top), floors, blocked)
	_sim = simulation

	for basin: Node in basins:
		_fill_basin(basin, floors, blocked)
	for gate: Node in _collect_nodes(GATE_GROUP, _room_rect):
		_block_gate(gate)
	for entry: Dictionary in _gates:
		var gate: Node = entry.get("node")
		if is_instance_valid(gate):
			entry["open"] = bool(gate.call("is_open"))

	_build_render()
	_needs_texture = true
	_accumulator = 0.0
	return true


func clear_room() -> void:
	_clear_ripples()
	_sim = null
	_columns = 0
	_origin_x = 0.0
	_gates.clear()
	_solid_tiles = null
	_terrain = null
	_room_rect = Rect2()
	_accumulator = 0.0
	_needs_texture = true
	if _quad != null:
		_quad.queue_free()
		_quad = null
	for fall: Dictionary in _falls:
		var fall_quad := fall.get("quad") as Node
		if fall_quad != null and is_instance_valid(fall_quad):
			fall_quad.queue_free()
	_falls.clear()
	_fall_splash_timer = 0.0
	_material = null
	_image = null
	_texture = null


func bind_player(player: Node2D) -> void:
	_player = player


# ---------------------------------------------------------------------------- queries

func is_ready() -> bool:
	return _sim != null


func has_water_at(world_x: float) -> bool:
	var index := _column_index(world_x)
	if index < 0:
		return false
	return _sim.get_depth(index) > 0.02


func get_surface_y_at(world_x: float) -> float:
	var index := _column_index(world_x)
	if index < 0 or _sim.is_blocked(index) or _sim.get_depth(index) <= 0.02:
		return INF
	return _sim.get_surface_y(index)


func get_depth_at(world_x: float) -> float:
	var index := _column_index(world_x)
	if index < 0:
		return 0.0
	return _sim.get_depth(index)


func get_flow_velocity_at(world_x: float) -> float:
	var index := _column_index(world_x)
	if index < 0:
		return 0.0
	return _sim.get_flow_velocity_at(world_x)


func get_debug_state() -> Dictionary:
	if _sim == null:
		return {"ready": false, "columns": 0, "volume": 0.0, "active": false, "step_ms": 0.0}
	return {
		"ready": true,
		"columns": _columns,
		"volume": _sim.total_volume(),
		"active": _sim.is_active(),
		"step_ms": _step_ms,
		"steps": _steps,
		"uploads": _texture_updates,
	}


## One column as the simulation and the renderer see it. Handy for tests and for
## checking that the surface texture lines up with the terrain.
func get_column_debug(index: int) -> Dictionary:
	if _sim == null or index < 0 or index >= _columns:
		return {}
	return {
		"index": index,
		"x": _origin_x + float(index) * COLUMN_WIDTH,
		"blocked": _sim.is_blocked(index),
		"depth": _sim.get_depth(index),
		"surface": _sim.get_surface_y(index),
		"floor": _sim.get_floor_y(index),
	}


# ---------------------------------------------------------------------------- splash

## Called by the player component on water entry and on a surface hop.
func request_splash(world_x: float, impact_speed: float) -> void:
	if _sim == null:
		return
	var index := _column_index(world_x)
	if index < 0 or _sim.is_blocked(index):
		return
	var surface_y := _sim.get_surface_y(index)
	var energy := clampf(impact_speed / 300.0, 0.0, 1.4)
	# Purely visual: the body is not displaced. A shader ripple and the droplet
	# effect sell the impact without adding volume to the pool or waking the waves.
	_add_ripple(world_x, surface_y, energy)
	_spawn_splash(world_x, surface_y, energy)
	if energy >= 0.35:
		var camera := get_viewport().get_camera_2d() if is_inside_tree() else null
		if camera != null and camera.has_method("add_shake"):
			camera.call("add_shake", 1 + int(round(energy * 6.0)), 1.0 if energy < 0.6 else 2.0)


## Records a visual ripple at an impact. Older ripples are dropped once the list
## is full, and `_update_ripples` ages them out. The reach is measured from the water
## the impact landed in, so the swell covers that body and nothing else.
func _add_ripple(world_x: float, surface_y: float, energy: float) -> void:
	_ripples.push_front(Vector4(world_x, surface_y, 0.0, 0.55 + energy))
	_ripple_reach.push_front(_measure_ripple_reach(world_x, surface_y))
	while _ripples.size() > RIPPLE_SLOTS:
		_ripples.pop_back()
		_ripple_reach.pop_back()
	_apply_ripples()


func _update_ripples(delta: float) -> void:
	if _ripples.is_empty():
		return
	for index in _ripples.size():
		var ripple := _ripples[index]
		ripple.z += delta
		_ripples[index] = ripple
	while not _ripples.is_empty() and _ripples.back().z > RIPPLE_LIFE:
		_ripples.pop_back()
		_ripple_reach.pop_back()
	_apply_ripples()


func _apply_ripples() -> void:
	if _material == null:
		return
	for slot in RIPPLE_SLOTS:
		var value := Vector4.ZERO
		var reach := 0.0
		if slot < _ripples.size():
			var ripple := _ripples[slot]
			value = Vector4(ripple.x, ripple.y, ripple.z, ripple.w)
			reach = _ripple_reach[slot]
		_material.set_shader_parameter("ripple_%d" % slot, value)
		_material.set_shader_parameter("ripple_reach_%d" % slot, reach)


func _clear_ripples() -> void:
	_ripples.clear()
	_ripple_reach.clear()
	_apply_ripples()


## 1/e reach in px of the ripple in `index`, 0 when the slot is free. Handy for
## tests and for the debug HUD: this is how far a landing actually carries.
func get_ripple_reach(index: int) -> float:
	if index < 0 or index >= _ripple_reach.size():
		return 0.0
	return _ripple_reach[index]


## Half-width of the water body the impact landed in, in px.
##
## The ripple is drawn by the shader, so its horizontal size has to come from the
## simulation: a landing in one end of a two hundred pixel basin has to carry across
## the whole basin, while the same landing in a narrow channel has to stay local.
## Walking the column surfaces outwards from the impact and stopping at the first
## blocked, dry or differently levelled column gives that size, instead of one
## constant that is wrong for every basin but the one it was tuned on. The walk is
## contiguous on purpose: probing at a growing distance would step over a dry gap and
## claim the pool on its other side.
func _measure_ripple_reach(world_x: float, surface_y: float) -> float:
	var centre := _column_index(world_x)
	var minimum := RIPPLE_MIN_REACH_CELLS * COLUMN_WIDTH
	if centre < 0 or _sim == null:
		return minimum
	var tolerance := RIPPLE_BODY_TOLERANCE_CELLS * COLUMN_WIDTH
	var farthest := 0
	for direction: int in [-1, 1]:
		var index := centre
		while true:
			var next := index + direction
			if next < 0 or next >= _columns:
				break
			if not _is_same_surface(next, surface_y, tolerance):
				break
			index = next
			farthest = maxi(farthest, absi(next - centre))
	return maxf(minimum, float(farthest) * COLUMN_WIDTH)


## True when `index` holds water at (about) `surface_y`: the same body, so the ripple
## may cross into that column. A blocked column, a dry column and a column of another
## pool all stop the walk.
func _is_same_surface(index: int, surface_y: float, tolerance: float) -> bool:
	if _sim == null or index < 0 or index >= _columns:
		return false
	if _sim.is_blocked(index) or _sim.get_depth(index) <= 0.02:
		return false
	return absf(_sim.get_surface_y(index) - surface_y) <= tolerance


# ---------------------------------------------------------------------------- simulation

func _physics_process(delta: float) -> void:
	if _sim == null:
		return
	_update_ripples(maxf(delta, 0.0))
	_update_gates()
	_accumulator = minf(_accumulator + maxf(delta, 0.0), SIM_STEP * 4.0)
	if _accumulator < SIM_STEP:
		return
	var started := Time.get_ticks_usec()
	while _accumulator >= SIM_STEP:
		_accumulator -= SIM_STEP
		_sim.step(SIM_STEP)
	_step_ms = float(Time.get_ticks_usec() - started) / 1000.0
	_steps += 1
	# Upload at most 60 times a second: a 1 px texture upload is cheap, but it
	# forces a GPU sync, so doing it on every 120 Hz physics tick is wasted work.
	_upload_accumulator += maxf(delta, 0.0)
	if _needs_texture or (_sim.is_active() and _upload_accumulator >= UPLOAD_INTERVAL):
		_needs_texture = false
		_upload_accumulator = 0.0
		_update_texture()
		_texture_updates += 1
	_update_falls(delta)


func _update_gates() -> void:
	for entry: Dictionary in _gates:
		var gate: Node = entry.get("node")
		if not is_instance_valid(gate):
			continue
		var open := bool(gate.call("is_open"))
		if open == bool(entry.get("open", false)):
			continue
		entry["open"] = open
		var columns: Array = entry.get("columns", [])
		for index: int in columns:
			_sim.set_blocked(index, not open)
		_needs_texture = true


func _update_texture() -> void:
	if _image == null or _texture == null or _sim == null:
		return
	var surface_span := maxf(_field_height, 1.0)
	for index: int in _columns:
		if _sim.is_blocked(index) or _sim.get_depth(index) <= 0.02:
			_image.set_pixel(index, 0, Color(0.0, 0.0, 0.0, 0.0))
			continue
		var surface_norm := clampf((_sim.get_surface_y(index) - _field_top) / surface_span, 0.0, 1.0)
		var floor_norm := clampf((_sim.get_floor_y(index) - _field_top) / surface_span, 0.0, 1.0)
		_image.set_pixel(index, 0, Color(surface_norm, floor_norm, 0.0, 1.0))
	_texture.update(_image)


func _update_falls(delta: float) -> void:
	if _sim == null or _falls.is_empty():
		return
	var lips: Array[Dictionary] = []
	for index in maxi(_columns - 1, 0):
		if _sim.is_blocked(index) or _sim.is_blocked(index + 1):
			continue
		var surface_left := _sim.get_surface_y(index)
		var surface_right := _sim.get_surface_y(index + 1)
		var drop := 0.0
		var direction := 0
		# The higher side must hold water; both directions are supported.
		if _sim.get_depth(index) > 0.05 and surface_right - surface_left > waterfall_min_drop:
			drop = surface_right - surface_left
			direction = 1
		elif _sim.get_depth(index + 1) > 0.05 and surface_left - surface_right > waterfall_min_drop:
			drop = surface_left - surface_right
			direction = -1
		if drop < waterfall_min_drop:
			continue
		# Hug the lower pool's edge and grow away from the lip: a rightward spill
		# starts at the lower pool's left edge, a leftward spill ends at its right
		# edge. Bigger flow widens the column, but it never leaves the open cells.
		var lower_column := index + 1 if direction > 0 else index
		var lower_left := _origin_x + float(lower_column) * COLUMN_WIDTH
		var open_columns := 1
		while open_columns < MAX_FALL_COLUMNS:
			var next_column := lower_column + open_columns if direction > 0 else lower_column - open_columns
			if next_column < 0 or next_column >= _columns or _sim.is_blocked(next_column):
				break
			open_columns += 1
		var speed := absf(float(_sim.call("get_flow_velocity_at", lower_left + COLUMN_WIDTH * 0.5)))
		var columns := clampi(int(round(1.0 + speed / 80.0)), 1, open_columns)
		var width := float(columns) * COLUMN_WIDTH
		var left := lower_left
		if direction < 0:
			left = lower_left + COLUMN_WIDTH - width
		var top := surface_left if direction > 0 else surface_right
		var bottom := surface_right if direction > 0 else surface_left
		lips.append({
			"left": left,
			"width": width,
			"top": top,
			"bottom": bottom,
			"drop": drop,
		})
	lips.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["drop"]) > float(b["drop"])
	)
	for index in _falls.size():
		var fall: Dictionary = _falls[index]
		var quad := fall.get("quad") as MeshInstance2D
		var material := fall.get("material") as ShaderMaterial
		if quad == null or material == null:
			continue
		if index >= lips.size():
			quad.visible = false
			continue
		var lip: Dictionary = lips[index]
		var height := maxf(float(lip["bottom"]) - float(lip["top"]), 1.0)
		quad.visible = true
		quad.global_position = Vector2(
			float(lip["left"]) + float(lip["width"]) * 0.5,
			float(lip["top"]) + height * 0.5
		)
		quad.scale = Vector2(float(lip["width"]), height)
		material.set_shader_parameter("flow_speed", clampf(0.6 + height / 44.0, 0.6, 2.4))
		material.set_shader_parameter("foot_foam", clampf(0.35 + height / 90.0, 0.35, 0.8))
	# A small splash at the foot of the biggest fall, on a fixed cadence so the
	# baked effect is reused instead of rebaking per frame.
	_fall_splash_timer = maxf(_fall_splash_timer - maxf(delta, 0.0), 0.0)
	if _fall_splash_timer <= 0.0 and not lips.is_empty():
		_fall_splash_timer = 0.42
		var main_lip: Dictionary = lips[0]
		_spawn_splash(
			float(main_lip["left"]) + float(main_lip["width"]) * 0.5,
			float(main_lip["bottom"]),
			0.18
		)


# ---------------------------------------------------------------------------- construction

func _resolve_terrain(terrain_root: Node) -> Node:
	var terrain := terrain_root.get_node_or_null("Terrain")
	if terrain != null:
		return terrain
	if terrain_root.name == "Terrain":
		return terrain_root
	return null


func _collect_nodes(group: StringName, room_rect: Rect2) -> Array[Node]:
	var result: Array[Node] = []
	if not is_inside_tree():
		return result
	for node: Node in get_tree().get_nodes_in_group(group):
		if not is_instance_valid(node) or not node.has_method("get_world_rect"):
			continue
		var rect: Rect2 = node.call("get_world_rect")
		if rect.size.x <= 0.0 or not rect.intersects(room_rect):
			continue
		result.append(node)
	return result


func _basin_span(basins: Array[Node]) -> Rect2:
	var span := Rect2(basins[0].call("get_world_rect"))
	for index: int in range(1, basins.size()):
		span = span.merge(basins[index].call("get_world_rect"))
	return span


func _fill_basin(basin: Node, floors: PackedFloat32Array, blocked: PackedByteArray) -> void:
	var rect: Rect2 = basin.call("get_world_rect")
	var surface_y := float(basin.call("get_initial_surface_y"))
	var from := int(floor((rect.position.x - _origin_x) / COLUMN_WIDTH))
	var to := int(ceil((rect.end.x - _origin_x) / COLUMN_WIDTH))
	for index: int in range(maxi(from, 0), mini(to, _columns)):
		if blocked[index] == 1:
			continue
		var floor_y := floors[index]
		var depth := clampf(minf(floor_y, rect.end.y) - surface_y, 0.0, max_depth)
		if depth <= 0.0:
			continue
		_sim.set_mass(index, depth * COLUMN_WIDTH)


func _block_gate(gate: Node) -> void:
	var rect: Rect2 = gate.call("get_world_rect")
	var columns: Array[int] = []
	var from := int(floor((rect.position.x - _origin_x) / COLUMN_WIDTH))
	var to := int(ceil((rect.end.x - _origin_x) / COLUMN_WIDTH))
	for index: int in range(maxi(from, 0), mini(to, _columns)):
		columns.append(index)
		_sim.set_blocked(index, true)
	if columns.is_empty():
		return
	_gates.append({"node": gate, "columns": columns, "open": false})


## First open row above the floor of `world_x`: everything solid from the bottom
## up, so a raised spill lip or a tank floor is found without any authored data.
## Returns 0 for a column that is solid all the way (a wall).
func _sample_floor(world_x: float, bottom_y: float) -> float:
	if _solid_tiles == null:
		return bottom_y
	# Work in the layer's own cell space: a room placed on an odd pixel origin
	# (a chunk is 180 px tall) does not line up with world-space 8 px rows.
	var local := _solid_tiles.to_local(Vector2(world_x, bottom_y))
	var column := _solid_tiles.local_to_map(local).x
	var row := int(floor((local.y - 0.5) / TILE_PIXELS)) - 1
	while row >= 0:
		if _solid_tiles.get_cell_source_id(Vector2i(column, row)) == -1:
			return _solid_tiles.to_global(Vector2(0.0, float((row + 1) * int(TILE_PIXELS)))).y
		row -= 1
	return 0.0


func _column_index(world_x: float) -> int:
	if _sim == null or _columns <= 0:
		return -1
	if world_x < _origin_x or world_x >= _origin_x + float(_columns) * COLUMN_WIDTH:
		return -1
	return mini(int((world_x - _origin_x) / COLUMN_WIDTH), _columns - 1)


## Called by LightField when a room is bound: the surface mirrors the light.
func set_light_field(texture: Texture2D, pixels: Vector2i, _origin_pixels: Vector2i) -> void:
	_light_texture = texture
	_light_pixels = pixels
	_apply_light_field()


func _apply_light_field() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("light_tex", _light_texture)
	_material.set_shader_parameter("light_pixels", Vector2(_light_pixels))
	# An unbound sampler reads as white; keep the reflection off until a room
	# actually hands a light map over.
	_material.set_shader_parameter(
		"reflection_strength", water_reflection if _light_texture != null else 0.0
	)


func _build_render() -> void:
	var width := float(_columns) * COLUMN_WIDTH
	_material = ShaderMaterial.new()
	_material.shader = SURFACE_SHADER
	_material.set_shader_parameter("column_count", float(_columns))
	_material.set_shader_parameter("field_origin", Vector2(_origin_x, _field_top))
	_material.set_shader_parameter("field_size", Vector2(width, _field_height))
	_material.set_shader_parameter("field_top", _field_top)
	_material.set_shader_parameter("field_height", _field_height)
	_material.set_shader_parameter("shallow_color", Color(0.26, 0.66, 0.94, 0.62))
	_material.set_shader_parameter("deep_color", Color(0.05, 0.18, 0.42, 0.9))
	_material.set_shader_parameter("crest_color", Color(0.85, 0.97, 1.0, 0.95))
	_material.set_shader_parameter("foam_color", Color(0.96, 1.0, 1.0, 0.9))
	_material.set_shader_parameter("ripple_amplitude", RIPPLE_AMPLITUDE)
	_material.set_shader_parameter("ripple_speed", RIPPLE_SPEED)
	_material.set_shader_parameter("ripple_damping", RIPPLE_DAMPING)
	_quad = MeshInstance2D.new()
	_quad.name = "WaterSurface"
	var surface_mesh := QuadMesh.new()
	surface_mesh.size = Vector2(1.0, 1.0)
	_quad.mesh = surface_mesh
	_quad.scale = Vector2(width, _field_height)
	_quad.position = Vector2(_origin_x + width * 0.5, _field_top + _field_height * 0.5)
	_quad.z_index = 1
	_quad.material = _material
	add_child(_quad)
	_apply_light_field()
	_image = Image.create(_columns, 1, false, Image.FORMAT_RGBA8)
	_image.fill(Color(0.0, 0.0, 0.0, 0.0))
	_texture = ImageTexture.create_from_image(_image)
	_material.set_shader_parameter("column_texture", _texture)

	# The fall is the same water: a continuous column quad in the pool palette.
	# Up to MAX_FALLS waterfall columns, one quad per spill lip.
	for index in MAX_FALLS:
		var material := ShaderMaterial.new()
		material.shader = FALL_SHADER
		material.set_shader_parameter("shallow_color", Color(0.26, 0.66, 0.94, 0.62))
		material.set_shader_parameter("deep_color", Color(0.05, 0.18, 0.42, 0.9))
		material.set_shader_parameter("crest_color", Color(0.85, 0.97, 1.0, 0.95))
		material.set_shader_parameter("foam_color", Color(0.96, 1.0, 1.0, 0.9))
		var quad := MeshInstance2D.new()
		quad.name = "Waterfall%d" % index
		var mesh := QuadMesh.new()
		mesh.size = Vector2.ONE
		quad.mesh = mesh
		quad.material = material
		quad.z_index = 2
		quad.visible = false
		add_child(quad)
		_falls.append({"quad": quad, "material": material})


func _spawn_splash(world_x: float, surface_y: float, energy: float) -> void:
	var power := 0.35 + energy * 1.2
	splash_requested.emit(Vector2(world_x, surface_y), power)
	if splash_scene == null:
		return
	var fx := splash_scene.instantiate() as Node2D
	if fx == null:
		return
	fx.top_level = true
	fx.z_as_relative = false
	fx.z_index = 3
	fx.set("autoplay", false)
	fx.set("free_when_done", true)
	fx.set("options", {"power": power})
	add_child(fx)
	fx.global_position = Vector2(world_x, surface_y)
	if fx.has_method("play"):
		fx.call("play")
