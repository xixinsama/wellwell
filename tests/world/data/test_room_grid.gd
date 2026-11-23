extends Node

const ROOM_GRID_PATH := "res://addons/platformer_kit/world/data/room_grid.gd"
const ROOM_DATA_PATH := "res://addons/platformer_kit/world/data/room_data.gd"
const WORLD_DATA_PATH := "res://addons/platformer_kit/world/data/world_data.gd"


func run() -> Array[String]:
	var failures: Array[String] = []
	var room_grid := load(ROOM_GRID_PATH) as Script
	if room_grid == null:
		return ["RoomGrid must provide the canonical room-cell conversion API"]
	if not room_grid.has_method("get_cells_per_chunk"):
		failures.append("RoomGrid is missing get_cells_per_chunk")
	if not room_grid.has_method("get_room_cell_rect"):
		failures.append("RoomGrid is missing get_room_cell_rect")
	if not failures.is_empty():
		return failures

	var cells_per_chunk: Vector2i = room_grid.call("get_cells_per_chunk", Vector2i(8, 8), Vector2i(320, 180))
	if cells_per_chunk != Vector2i(40, 23):
		failures.append("320x180 chunks must contain 40x23 fog cells at 8x8 pixels")
	var rect: Rect2i = room_grid.call(
		"get_room_cell_rect",
		Vector2i(2, 1),
		Vector2i(3, 2),
		Vector2i(8, 8),
		Vector2i(320, 180)
	)
	if rect != Rect2i(80, 23, 120, 45):
		failures.append("multi-chunk room cell rect must use exact 960x360 pixel extent")
	var odd_row: Rect2i = room_grid.call(
		"get_room_cell_rect", Vector2i(0, 1), Vector2i.ONE, Vector2i(8, 8), Vector2i(320, 180)
	)
	if odd_row != Rect2i(0, 23, 40, 22):
		failures.append("odd chunk row must be 22 cells: %s" % str(odd_row))
	var even_row: Rect2i = room_grid.call(
		"get_room_cell_rect", Vector2i(0, 2), Vector2i.ONE, Vector2i(8, 8), Vector2i(320, 180)
	)
	if even_row != Rect2i(0, 45, 40, 23):
		failures.append("even chunk row must be 23 cells: %s" % str(even_row))
	var two_rows: Rect2i = room_grid.call(
		"get_room_cell_rect", Vector2i(0, 0), Vector2i(1, 2), Vector2i(8, 8), Vector2i(320, 180)
	)
	if two_rows != Rect2i(0, 0, 40, 45):
		failures.append("two chunk rows must be 45 cells: %s" % str(two_rows))
	var blocks: Array = room_grid.call(
		"get_room_block_cell_rects", Vector2i(0, 0), Vector2i(2, 2), Vector2i(8, 8), Vector2i(320, 180)
	)
	if blocks != [
		Rect2i(0, 0, 40, 23), Rect2i(40, 0, 40, 23),
		Rect2i(0, 23, 40, 22), Rect2i(40, 23, 40, 22),
	]:
		failures.append("2x2 block frames must alternate 23/22 rows: %s" % str(blocks))
	_assert_room_data_is_room_local(failures)
	_assert_world_data_owns_room_cell_rects(failures)
	return failures


func _assert_room_data_is_room_local(failures: Array[String]) -> void:
	var room_data := load(ROOM_DATA_PATH) as Script
	if room_data == null or not room_data.can_instantiate():
		failures.append("RoomData could not be loaded")
		return
	var room: Resource = room_data.new()
	var properties: Array[Dictionary] = []
	properties.assign(room.get_property_list())
	for property: Dictionary in properties:
		var property_name := String(property.get("name", ""))
		if property_name in ["room_origin_chunk", "adjacent_room_ids"]:
			failures.append("RoomData must not own %s" % property_name)
			return


func _assert_world_data_owns_room_cell_rects(failures: Array[String]) -> void:
	var world_data := load(WORLD_DATA_PATH) as Script
	if world_data == null or not world_data.can_instantiate():
		failures.append("WorldData could not be loaded")
		return
	var world: Resource = world_data.new()
	if not world.has_method("get_room_cell_rect"):
		failures.append("WorldData must expose placement-owned room cell rectangles")
