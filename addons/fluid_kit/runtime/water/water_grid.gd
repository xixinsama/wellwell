class_name WaterGrid
extends Node2D

## 2D fluid for the active room: a conservative cell grid over the whole room.
##
## The room is split into `cell_pixels` cells. `FluidRegion` markers fill their
## rectangle with water at room entry (walls inside the rectangle keep their
## volume), and from there the grid simulates on its own: water falls, spreads,
## levels out and spills over ledges. Tile walls are read from the room's
## SolidTiles, so a wall placed inside a region simply takes its volume away.
##
## Bound through WorldSession.register_room_extension, like WaterField, and inert
## in a room without FluidRegion markers. The grid runs at a fixed rate, sleeps
## when it comes to rest, uploads its texture at 30 Hz and joins the
## "water_field" group, so PlayerWaterMotion can swim in it without changes.

signal splash_requested(world_position: Vector2, power: float)

const GRID_SHADER := preload("res://addons/fluid_kit/runtime/water/water_grid.gdshader")
const CHUNK_PIXELS := Vector2(320.0, 180.0)
const TILE_PIXELS := 8.0
const REGION_GROUP := &"fluid_region"
const WATER_GROUP := &"water_field"
## Water surface texture upload rate. The simulation still runs at sim_hz.
const UPLOAD_INTERVAL := 1.0 / 30.0
## Depth the render maps to the deepest colour.
const DEPTH_SCALE := 90.0

## Simulation cell size in pixels. 4 draws a pool surface and a falling stream
## that read as smooth once the shader interpolates the height field between cells;
## 8 is about half the cost and 2 is only worth it for a small, contained pool.
@export_range(2, 16, 1) var cell_pixels := 4
@export_range(30.0, 120.0, 1.0) var sim_hz := 60.0
@export_range(4.0, 30.0, 0.5) var lateral_rate := 24.0
@export_range(0.2, 1.0, 0.05) var fall_rate := 1.0
@export var shallow_color := Color(0.24, 0.66, 0.95, 0.72)
@export var deep_color := Color(0.04, 0.16, 0.42, 0.92)
@export var crest_color := Color(0.85, 0.97, 1.0, 0.95)
@export var foam_color := Color(0.96, 1.0, 1.0, 0.9)
@export var caustic_strength := 0.14
@export var splash_scene: PackedScene
## Ripple amplitude in pixels at the impact point. The ripple is drawn by the
## surface shader only: the water body is not disturbed, so a splash cannot pump
## volume into the pool and costs nothing.
@export_range(0.0, 6.0, 0.1) var ripple_amplitude := 2.2
@export var debug_stats := false

## Visual ripples: impact x, impact y, age (s), strength. Updated every frame and
## handed to the shader; the oldest one is dropped when the list is full.
const RIPPLE_SLOTS := 3
const RIPPLE_LIFE := 1.2

var _sim: GridWater
var _room_rect := Rect2()
var _origin_chunk := Vector2i.ZERO
var _terrain: Node
var _solid_tiles: TileMapLayer
var _player: Node2D
var _quad: MeshInstance2D
var _material: ShaderMaterial
var _image: Image
var _texture: ImageTexture
var _bytes := PackedByteArray()
var _accumulator := 0.0
var _upload_accumulator := 0.0
var _needs_texture := true
var _step_ms := 0.0
var _steps := 0
var _uploads := 0
var _region_volume := 0.0
var _region_cells := 0
var _ripples: Array[Vector4] = []


func _ready() -> void:
	add_to_group(WATER_GROUP)


func _exit_tree() -> void:
	remove_from_group(WATER_GROUP)


# ---------------------------------------------------------------------------- binding

## Builds the grid for a room. Returns true when the room is handled (including a
## room with no FluidRegion, which simply keeps the grid inert), and false only
## when the room data cannot be used at all. The world session aborts a room load
## on false, so "nothing to do" must never be an error.
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
	_origin_chunk = origin_chunk
	_room_rect = Rect2(Vector2(origin_chunk) * CHUNK_PIXELS, Vector2(room_chunks) * CHUNK_PIXELS)
	var regions := _collect_nodes(REGION_GROUP, _room_rect)
	if regions.is_empty():
		# Nothing to simulate: a room without a FluidRegion is a valid, inert room
		# for this extension, exactly like a room without basins for WaterField.
		return true

	var cells := Vector2i(
		maxi(int(ceil(_room_rect.size.x / float(cell_pixels))), 1),
		maxi(int(ceil(_room_rect.size.y / float(cell_pixels))), 1)
	)
	var solid := _build_solid_mask(cells)
	var simulation := GridWater.new()
	if not simulation.setup(cells, float(cell_pixels), solid):
		return false
	simulation.origin = _room_rect.position
	simulation.lateral_rate = lateral_rate
	simulation.fall_rate = fall_rate
	_sim = simulation

	_region_volume = 0.0
	_region_cells = 0
	for region: Node in regions:
		var rect: Rect2 = region.call("get_world_rect")
		var cell_rect := _world_rect_to_cells(rect)
		_region_cells += cell_rect.size.x * cell_rect.size.y
		_region_volume += _sim.fill_rect(cell_rect)
	if _sim.total_volume() <= 0.0:
		# The regions are entirely solid: leave the field empty and accept the room.
		clear_room()
		return true

	_build_render(cells)
	_needs_texture = true
	_accumulator = 0.0
	_upload_accumulator = 0.0
	return true


func clear_room() -> void:
	_clear_ripples()
	_sim = null
	_room_rect = Rect2()
	_solid_tiles = null
	_terrain = null
	_accumulator = 0.0
	_needs_texture = true
	_region_volume = 0.0
	_region_cells = 0
	if _quad != null:
		_quad.queue_free()
		_quad = null
	_material = null
	_image = null
	_texture = null
	_bytes = PackedByteArray()


func bind_player(player: Node2D) -> void:
	_player = player


# ---------------------------------------------------------------------------- queries

func is_ready() -> bool:
	return _sim != null


func get_room_rect() -> Rect2:
	return _room_rect


func has_water_at(world_x: float) -> bool:
	if _sim == null:
		return false
	return _sim.surface_y_at(Vector2(world_x, _room_rect.position.y)) != INF


## Water surface in the column of world_x: the first surface below the top of the
## room. INF when the column is dry.
func get_surface_y_at(world_x: float) -> float:
	if _sim == null:
		return INF
	return _sim.surface_y_at(Vector2(world_x, _room_rect.position.y))


## Water surface at a point: the local surface when the point is inside water,
## otherwise the first surface below it. This is the query a body should use,
## because a column can hold water on a ledge and again on the floor.
func get_surface_y_at_point(point: Vector2) -> float:
	if _sim == null:
		return INF
	return _sim.surface_y_at(point)


func is_water_at(point: Vector2) -> bool:
	return _sim != null and _sim.is_water_at(point)


func get_depth_at(world_x: float) -> float:
	if _sim == null:
		return 0.0
	var surface := _sim.surface_y_at(Vector2(world_x, _room_rect.position.y))
	if surface == INF:
		return 0.0
	var cell := _sim.cell_of_world(Vector2(world_x, surface + 1.0))
	for y in range(cell.y + 1, _sim.height):
		var index := y * _sim.width + cell.x
		if _sim.is_solid_at(index):
			return _sim.origin.y + float(y) * _sim.cell_pixels - surface
	return _sim.origin.y + float(_sim.height) * _sim.cell_pixels - surface


func get_flow_velocity_at(world_x: float) -> float:
	if _sim == null:
		return 0.0
	return _sim.flow_x_at(Vector2(world_x, _room_rect.position.y))


func get_flow_velocity_at_point(point: Vector2) -> float:
	if _sim == null:
		return 0.0
	return _sim.flow_x_at(point)


## Called by the player on water entry and on a surface hop: the splash pushes
## water out of the way and keeps the volume, so the dip flows back in.
func request_splash(world_x: float, impact_speed: float) -> void:
	if _sim == null:
		return
	var surface := _sim.surface_y_at(Vector2(world_x, _room_rect.position.y))
	if surface == INF:
		return
	var energy := clampf(impact_speed / 300.0, 0.0, 1.4)
	# Purely visual: the body is not displaced. A shader ripple and the droplet
	# effect sell the impact without waking the simulation or adding volume.
	_add_ripple(Vector2(world_x, surface), energy)
	_spawn_splash(world_x, surface, energy)


## Records a visual ripple at `point`. Older ripples are dropped once the list is
## full, and `_update_ripples` ages them out.
func _add_ripple(point: Vector2, energy: float) -> void:
	_ripples.push_front(Vector4(point.x, point.y, 0.0, 0.55 + energy))
	while _ripples.size() > RIPPLE_SLOTS:
		_ripples.pop_back()
	_apply_ripples()


func _update_ripples(delta: float) -> void:
	if _ripples.is_empty():
		return
	var changed := false
	for index in _ripples.size():
		var ripple := _ripples[index]
		ripple.z += delta
		_ripples[index] = ripple
		changed = true
	while not _ripples.is_empty() and _ripples.back().z > RIPPLE_LIFE:
		_ripples.pop_back()
	if changed:
		_apply_ripples()


func _apply_ripples() -> void:
	if _material == null:
		return
	for slot in RIPPLE_SLOTS:
		var value := Vector4.ZERO
		if slot < _ripples.size():
			var ripple := _ripples[slot]
			value = Vector4(ripple.x, ripple.y, ripple.z, ripple.w)
		_material.set_shader_parameter("ripple_%d" % slot, value)


func _clear_ripples() -> void:
	_ripples.clear()
	_apply_ripples()


## Adds water to the room at a point: a source, a wave or a debug probe. The
## volume is an area (px^2) on the same scale as `get_debug_state().volume`.
func add_water(point: Vector2, radius: float, volume: float) -> float:
	if _sim == null:
		return volume
	_needs_texture = true
	return _sim.add_volume(point, radius, volume * _sim.cell_pixels)


func remove_water(point: Vector2, radius: float, volume: float) -> float:
	if _sim == null:
		return 0.0
	_needs_texture = true
	return _sim.remove_volume(point, radius, volume * _sim.cell_pixels)


func get_debug_state() -> Dictionary:
	if _sim == null:
		return {"ready": false, "cells": 0, "volume": 0.0, "active": false}
	var state := _sim.get_debug_state()
	state["ready"] = true
	state["step_ms"] = _step_ms
	state["steps"] = _steps
	state["uploads"] = _uploads
	state["region_volume"] = _region_volume
	state["region_cells"] = _region_cells
	return state


# ---------------------------------------------------------------------------- simulation

func _physics_process(delta: float) -> void:
	if _sim == null:
		return
	_update_ripples(maxf(delta, 0.0))
	var step := 1.0 / maxf(sim_hz, 1.0)
	_accumulator = minf(_accumulator + maxf(delta, 0.0), step * 4.0)
	if _accumulator < step:
		return
	var started := Time.get_ticks_usec()
	while _accumulator >= step:
		_accumulator -= step
		_sim.step(step)
	_step_ms = float(Time.get_ticks_usec() - started) / 1000.0
	_steps += 1
	if debug_stats and _steps % 120 == 0:
		print("water grid: ", _sim.get_debug_state(), " step_ms=", _step_ms)
	_upload_accumulator += maxf(delta, 0.0)
	if _needs_texture or (_sim.is_active() and _upload_accumulator >= UPLOAD_INTERVAL):
		_needs_texture = false
		_upload_accumulator = 0.0
		_update_texture()
		_uploads += 1

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


func _build_solid_mask(cells: Vector2i) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(cells.x * cells.y)
	mask.fill(0)
	if _solid_tiles == null:
		return mask
	for y in cells.y:
		for x in cells.x:
			var world := _room_rect.position + (Vector2(x, y) + Vector2(0.5, 0.5)) * float(cell_pixels)
			var local := _solid_tiles.to_local(world)
			if _solid_tiles.get_cell_source_id(_solid_tiles.local_to_map(local)) != -1:
				mask[y * cells.x + x] = 1
	return mask


func _world_rect_to_cells(rect: Rect2) -> Rect2i:
	var local := rect.position - _room_rect.position
	var from := Vector2i(floori(local.x / cell_pixels), floori(local.y / cell_pixels))
	var to := Vector2i(
		maxi(ceili((local.x + rect.size.x) / cell_pixels), from.x + 1),
		maxi(ceili((local.y + rect.size.y) / cell_pixels), from.y + 1)
	)
	var cells := Vector2i(_sim.width, _sim.height)
	return Rect2i(
		Vector2i(clampi(from.x, 0, cells.x - 1), clampi(from.y, 0, cells.y - 1)),
		Vector2i(
			clampi(to.x - from.x, 1, cells.x - from.x),
			clampi(to.y - from.y, 1, cells.y - from.y)
		)
	)


func _build_render(cells: Vector2i) -> void:
	_material = ShaderMaterial.new()
	_material.shader = GRID_SHADER
	_material.set_shader_parameter("field_origin", _room_rect.position)
	_material.set_shader_parameter("field_size", _room_rect.size)
	_material.set_shader_parameter("grid_size", Vector2(cells))
	_material.set_shader_parameter("cell_pixels", float(cell_pixels))
	_material.set_shader_parameter("depth_scale", DEPTH_SCALE)
	_material.set_shader_parameter("shallow_color", shallow_color)
	_material.set_shader_parameter("deep_color", deep_color)
	_material.set_shader_parameter("crest_color", crest_color)
	_material.set_shader_parameter("foam_color", foam_color)
	_material.set_shader_parameter("caustic_strength", caustic_strength)
	_material.set_shader_parameter("ripple_amplitude", ripple_amplitude)
	var quad := MeshInstance2D.new()
	quad.name = "WaterGridSurface"
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	quad.mesh = mesh
	quad.scale = _room_rect.size
	quad.position = _room_rect.position + _room_rect.size * 0.5
	quad.z_index = 1
	quad.material = _material
	add_child(quad)
	_quad = quad

	_image = Image.create(cells.x, cells.y, false, Image.FORMAT_RGBA8)
	_image.fill(Color(0.0, 0.0, 0.0, 0.0))
	_texture = ImageTexture.create_from_image(_image)
	_material.set_shader_parameter("grid_texture", _texture)
	_bytes.resize(cells.x * cells.y * 4)
	_bytes.fill(0)
	# One full build under the "needs texture" flag below: every later upload is
	# incremental over the wet rect.
	_update_texture(true)


## Rebuilds the cell texture. R is the fill of the cell, G the water depth above
## it, B the motion of the last step and A the cell kind (water, wall, empty).
##
## Only the wet rect (plus a cell of margin) is rebuilt, so the upload cost does
## not grow with the room: the grid walks the water, not the map. The first build
## writes the whole grid once so every texel has a known value.
func _update_texture(full: bool = false) -> void:
	if _sim == null or _texture == null:
		return
	var rect := Rect2i(0, 0, _sim.width, _sim.height) if full else _sim.wet_bounds()
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	_sim.write_cell_texture(_bytes, rect, DEPTH_SCALE, full)
	_image = Image.create_from_data(_sim.width, _sim.height, false, Image.FORMAT_RGBA8, _bytes)
	_texture.update(_image)


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
