extends Node

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
	# full box: 17 x 9 cells of 8 px, minus 2 x 6 cells of rock.
	var cells := float(state.get("region_cells", 0))
	if cells <= 0.0:
		failures.append("fluid region reported no cells")
	var empty_volume := cells * float(state.get("cell_pixels", 8.0)) * float(state.get("cell_pixels", 8.0)) * float(state.get("cell_pixels", 8.0))
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
	_cleanup(grid, runtime, terrain)


func _cleanup(grid: Node, runtime: Node, terrain: Node) -> void:
	# Free immediately: a queued-free grid stays in the "water_field" group until
	# the end of the frame, and the next test would resolve it as the active field.
	grid.free()
	runtime.free()
	terrain.free()

