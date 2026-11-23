extends Node

## Merged test suite. Every inner class below is one original test file,
## kept in its own class so fixtures and helper names stay isolated. Do not
## add logic here: split a class back into its own file when it grows.

## tests/world/test_tilemap_scene_contract.gd
class TilemapSceneContractCase extends Node:
	func run() -> Array[String]:
		var failures: Array[String] = []
		var packed: PackedScene = load("res://scenes/rooms/generated/room_00_00/terrain.tscn") as PackedScene
		if packed == null:
			failures.append("generated terrain scene did not load")
			return failures

		var world := packed.instantiate()
		if world.get_node_or_null("Terrain/BackTiles") == null:
			failures.append("BackTiles missing")
		if world.get_node_or_null("Terrain/SolidTiles") == null:
			failures.append("SolidTiles missing")
		if world.get_node_or_null("Terrain/DetailTiles") == null:
			failures.append("DetailTiles missing")
		world.free()
		return failures


## tests/world/test_map_model.gd
class MapModelCase extends Node:
	const WORLD_DATA := preload("res://addons/platformer_kit/world/data/world_data.gd")
	const ROOM_DATA := preload("res://addons/platformer_kit/world/data/room_data.gd")
	const MAP_MODEL := preload("res://addons/metroidvania_kit/map/runtime/legacy_world_map_model.gd")


	func run() -> Array[String]:
		var failures: Array[String] = []
		var room: Resource = ROOM_DATA.new()
		room.room_id = "room_a"
		room.display_name = "Start"
		room.room_size_chunks = Vector2i(2, 1)
		var world: Resource = WORLD_DATA.new()
		world.world_id = "world_01"
		world.rooms.assign([room])
		world.set_room_origin_chunk("room_a", Vector2i(2, 1))
		var model: Dictionary = MAP_MODEL.build(world, ["world_01:chunk:2,1"], "room_a")
		if model.rooms.size() != 1:
			failures.append("map model did not include room")
		if not model.rooms[0].current:
			failures.append("map model did not mark current room")
		if not model.rooms[0].chunks[0].explored or model.rooms[0].chunks[1].explored:
			failures.append("map model explored chunks were wrong")
		return failures


## tests/world/test_room_transition.gd
class RoomTransitionCase extends Node:
	const WORLD_DATA := preload("res://addons/platformer_kit/world/data/world_data.gd")
	const ROOM_DATA := preload("res://addons/platformer_kit/world/data/room_data.gd")
	const ROOM_TRANSITION := preload("res://addons/platformer_kit/world/transition/room_transition.gd")
	const ENTRANCE := preload("res://addons/platformer_kit/world/entities/room_entrance.gd")
	const ROOM_CONNECTION_DATA := preload("res://addons/platformer_kit/world/data/room_connection_data.gd")

	func run() -> Array[String]:
		var failures: Array[String] = []
		var a: Resource = ROOM_DATA.new()
		a.room_id = "a"
		var b: Resource = ROOM_DATA.new()
		b.room_id = "b"
		var world: Resource = WORLD_DATA.new()
		world.rooms.assign([a, b])
		var entrance: Node = ENTRANCE.new()
		entrance.entity_id = "exit_a"
		var connection: Resource = ROOM_CONNECTION_DATA.new()
		connection.from_room_id = "a"
		connection.from_entrance_id = "exit_a"
		connection.to_room_id = "b"
		connection.to_spawn_id = "spawn_b"
		world.connections.assign([connection])
		var resolved: Dictionary = ROOM_TRANSITION.resolve(world, "a", entrance)
		if resolved.get("to_room_id", "") != "b" or resolved.get("to_spawn_id", "") != "spawn_b":
			failures.append("room transition did not resolve the WorldData connection")
		if ROOM_TRANSITION.resolve(world, "a", entrance).is_empty():
			failures.append("room transition did not resolve a valid connection")
		entrance.entity_id = "unregistered_exit"
		if not ROOM_TRANSITION.resolve(world, "a", entrance).is_empty():
			failures.append("room transition accepted an entrance without a world connection")
		entrance.entity_id = "exit_a"
		entrance.free()
		return failures


## tests/world/test_world_stack_data.gd
class WorldStackDataCase extends Node:
	## Coverage for the WorldStack resource: the authored "multi-layer world" that
	## the editor's 3D view draws. Pure data, no file IO.

	const STACK := preload("res://addons/platformer_kit/world/data/world_stack_data.gd")
	const WORLD_DATA := preload("res://addons/platformer_kit/world/data/world_data.gd")


	func run() -> Array[String]:
		var failures: Array[String] = []
		_assert_layer_lookup(failures)
		_assert_normalize(failures)
		_assert_insert_and_remove(failures)
		_assert_move_layer(failures)
		return failures


	func _make_world(world_id: String) -> WorldData:
		var world := WORLD_DATA.new() as WorldData
		world.world_id = world_id
		return world


	func _assert_layer_lookup(failures: Array[String]) -> void:
		var stack: WorldStack = STACK.new() as WorldStack
		if stack.get_layer_count() != 0 or stack.has_world("a") or stack.get_layer_index("a") != -1:
			failures.append("an empty WorldStack reports layers it does not have")
		var a := _make_world("a")
		var b := _make_world("b")
		stack.layers.assign([a, b])
		if stack.get_layer_index("b") != 1:
			failures.append("WorldStack.get_layer_index did not find the second layer")
		if not stack.has_world("a"):
			failures.append("WorldStack.has_world missed an authored layer")
		if stack.get_world_ids() != (["a", "b"] as Array[String]):
			failures.append("WorldStack.get_world_ids did not keep the layer order: %s" % str(stack.get_world_ids()))
		if stack.get_layer_index("missing") != -1:
			failures.append("WorldStack.get_layer_index invented a layer")


	func _assert_normalize(failures: Array[String]) -> void:
		var stack: WorldStack = STACK.new() as WorldStack
		var a := _make_world("a")
		var b := _make_world("b")
		var duplicate := _make_world("a")
		var blank := WORLD_DATA.new() as WorldData
		stack.layers.assign([a, null, b, duplicate, blank])
		stack.normalize()
		if stack.get_layer_count() != 2:
			failures.append("normalize did not drop nulls, blank ids and duplicates: %d" % stack.get_layer_count())
		if stack.get_world_ids() != (["a", "b"] as Array[String]):
			failures.append("normalize changed the authored order: %s" % str(stack.get_world_ids()))


	func _assert_insert_and_remove(failures: Array[String]) -> void:
		var stack: WorldStack = STACK.new() as WorldStack
		var a := _make_world("a")
		var b := _make_world("b")
		if not stack.insert_world(a) or not stack.insert_world(b):
			failures.append("insert_world rejected a valid world")
		if stack.insert_world(b):
			failures.append("insert_world accepted a duplicate world")
		if stack.insert_world(null) or stack.insert_world(WORLD_DATA.new() as WorldData):
			failures.append("insert_world accepted a null or id-less world")
		var c := _make_world("c")
		stack.insert_world(c, 1)
		if stack.get_world_ids() != (["a", "c", "b"] as Array[String]):
			failures.append("insert_world ignored the requested layer index: %s" % str(stack.get_world_ids()))
		if not stack.remove_world("c") or stack.get_world_ids() != (["a", "b"] as Array[String]):
			failures.append("remove_world did not drop the requested layer")
		if stack.remove_world("missing"):
			failures.append("remove_world reported removing a layer that is not there")


	func _assert_move_layer(failures: Array[String]) -> void:
		var stack: WorldStack = STACK.new() as WorldStack
		stack.layers.assign([_make_world("a"), _make_world("b"), _make_world("c")])
		if not stack.move_layer(0, 2) or stack.get_world_ids() != (["b", "c", "a"] as Array[String]):
			failures.append("move_layer did not move the bottom layer to the top: %s" % str(stack.get_world_ids()))
		if not stack.move_layer(2, 0) or stack.get_world_ids() != (["a", "b", "c"] as Array[String]):
			failures.append("move_layer did not move the top layer to the bottom: %s" % str(stack.get_world_ids()))
		if stack.move_layer(5, 0):
			failures.append("move_layer accepted an out-of-range source index")
		if stack.move_layer(0, 0):
			failures.append("move_layer reported a move to the same index")
		if not stack.move_layer(0, 99) or stack.get_world_ids() != (["b", "c", "a"] as Array[String]):
			failures.append("move_layer did not clamp a target past the end: %s" % str(stack.get_world_ids()))


## tests/world/test_world_validation.gd
class WorldValidationCase extends Node:
	const ROOM_DATA: Script = preload("res://addons/platformer_kit/world/data/room_data.gd")
	const WORLD_DATA: Script = preload("res://addons/platformer_kit/world/data/world_data.gd")
	const ROOM_CONNECTION_DATA: Script = preload("res://addons/platformer_kit/world/data/room_connection_data.gd")
	const ROOM_PLACEMENT_DATA: Script = preload("res://addons/platformer_kit/world/data/world_room_placement_data.gd")
	const WORLD_VALIDATION: Script = preload("res://addons/platformer_kit/world/data/world_validation.gd")


	func run() -> Array[String]:
		var failures: Array[String] = []
		_assert_valid_world_has_no_errors(failures)
		_assert_missing_and_duplicate_placements_are_errors(failures)
		_assert_invalid_room_and_connection_data_are_errors(failures)
		_assert_overlap_and_reachability_are_warnings(failures)
		return failures


	func _assert_valid_world_has_no_errors(failures: Array[String]) -> void:
		var world := _make_world([_make_room("room_a"), _make_room("room_b")])
		world.start_room_id = "room_a"
		world.start_spawn_id = "start"
		world.connections.assign([_make_connection("room_a", "exit", "room_b", "start")])
		var report: Dictionary = WORLD_VALIDATION.validate_world_report(world)
		if not report.ok:
			failures.append("valid world returned errors: %s" % str(report.errors))


	func _assert_missing_and_duplicate_placements_are_errors(failures: Array[String]) -> void:
		var world: Resource = WORLD_DATA.new()
		world.world_id = "world_01"
		world.rooms.assign([_make_room("room_a")])
		world.start_room_id = "room_a"
		world.start_spawn_id = "start"
		_assert_contains(WORLD_VALIDATION.validate_world(world), "world has no placement for room: room_a", failures)
		var duplicate: Resource = ROOM_PLACEMENT_DATA.new()
		duplicate.room_id = "room_a"
		world.placements.assign([_make_placement("room_a", Vector2i.ZERO), duplicate, _make_placement("missing", Vector2i.ONE)])
		var errors: Array[String] = WORLD_VALIDATION.validate_world(world)
		_assert_contains(errors, "world contains duplicate placement for room room_a", failures)
		_assert_contains(errors, "world placement references unknown room missing", failures)


	func _assert_invalid_room_and_connection_data_are_errors(failures: Array[String]) -> void:
		var invalid_room := _make_room("room_a")
		invalid_room.scene_path = ""
		invalid_room.room_size_chunks = Vector2i(0, 1)
		var world := _make_world([invalid_room])
		world.start_room_id = "missing"
		world.start_spawn_id = "start"
		world.connections.assign([_make_connection("room_a", "", "missing", "start")])
		var errors: Array[String] = WORLD_VALIDATION.validate_world(world)
		_assert_contains(errors, "room room_a has empty scene_path", failures)
		_assert_contains(errors, "room room_a has invalid room_size_chunks: (0, 1)", failures)
		_assert_contains(errors, "start_room_id does not reference a room: missing", failures)
		_assert_contains(errors, "connection room_a->missing has empty from_entrance_id", failures)
		_assert_contains(errors, "connection room_a->missing references unknown to_room_id", failures)


	func _assert_overlap_and_reachability_are_warnings(failures: Array[String]) -> void:
		var world := _make_world([_make_room("room_a"), _make_room("room_b"), _make_room("room_c")])
		world.start_room_id = "room_a"
		world.start_spawn_id = "start"
		world.set_room_origin_chunk("room_b", Vector2i.ZERO)
		world.connections.assign([_make_connection("room_a", "exit", "room_b", "start")])
		var report: Dictionary = WORLD_VALIDATION.validate_world_report(world)
		if not report.ok:
			failures.append("overlap and unreachable room should remain warning-only: %s" % str(report.errors))
		_assert_contains(report.warnings, "overlapping rooms: room_a, room_b", failures)
		_assert_contains(report.warnings, "room room_c is unreachable from start room", failures)


	func _make_world(rooms: Array[Resource]) -> Resource:
		var world: Resource = WORLD_DATA.new()
		world.world_id = "world_01"
		world.rooms.assign(rooms)
		for index: int in rooms.size():
			world.set_room_origin_chunk(rooms[index].room_id, Vector2i(index, 0))
		return world


	func _make_room(room_id: String) -> Resource:
		var room: Resource = ROOM_DATA.new()
		room.room_id = room_id
		room.scene_path = "res://scenes/rooms/generated/%s/runtime.tscn" % room_id
		room.source_scene_path = "res://scenes/rooms/source/%s.tscn" % room_id
		room.terrain_scene_path = "res://scenes/rooms/generated/%s/terrain.tscn" % room_id
		room.entrance_ids = PackedStringArray(["exit"])
		room.spawn_ids = PackedStringArray(["start"])
		room.room_size_chunks = Vector2i.ONE
		return room


	func _make_placement(room_id: String, origin: Vector2i) -> Resource:
		var placement: Resource = ROOM_PLACEMENT_DATA.new()
		placement.room_id = room_id
		placement.origin_chunk = origin
		return placement


	func _make_connection(from_room_id: String, entrance: String, to_room_id: String, spawn: String) -> Resource:
		var connection: Resource = ROOM_CONNECTION_DATA.new()
		connection.from_room_id = from_room_id
		connection.from_entrance_id = entrance
		connection.to_room_id = to_room_id
		connection.to_spawn_id = spawn
		return connection


	func _assert_contains(values: Array, expected: String, failures: Array[String]) -> void:
		if not values.has(expected):
			failures.append("missing validation result %s in %s" % [expected, str(values)])


## tests/world/data/test_room_grid.gd
class RoomGridCase extends Node:
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


## tests/world/test_cell_rect_merger.gd
class CellRectMergerCase extends Node:
	const MERGER := preload("res://scripts/util/cell_rect_merger.gd")


	func run() -> Array[String]:
		var failures: Array[String] = []
		_assert_empty(failures)
		_assert_block(failures)
		_assert_separate_runs(failures)
		_assert_concave_shape(failures)
		return failures


	func _assert_empty(failures: Array[String]) -> void:
		if not MERGER.merge([]).is_empty():
			failures.append("empty cell set produced rectangles")


	func _assert_block(failures: Array[String]) -> void:
		var cells: Array[Vector2i] = [
			Vector2i(0, 0), Vector2i(1, 0),
			Vector2i(0, 1), Vector2i(1, 1),
			Vector2i(0, 2), Vector2i(1, 2),
		]
		var rects: Array[Rect2i] = MERGER.merge(cells)
		if rects.size() != 1 or rects[0] != Rect2i(0, 0, 2, 3):
			failures.append("solid 2x3 block did not merge into one rectangle")
		_assert_cover(cells, rects, failures)


	func _assert_separate_runs(failures: Array[String]) -> void:
		var cells: Array[Vector2i] = [
			Vector2i(0, 0), Vector2i(0, 1),
			Vector2i(3, 0), Vector2i(3, 1),
		]
		var rects: Array[Rect2i] = MERGER.merge(cells)
		if rects.size() != 2:
			failures.append("separate vertical runs did not stay separate")
		_assert_cover(cells, rects, failures)


	func _assert_concave_shape(failures: Array[String]) -> void:
		var cells: Array[Vector2i] = [
			Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0),
			Vector2i(0, 1),
			Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2),
		]
		var rects: Array[Rect2i] = MERGER.merge(cells)
		if rects.size() >= cells.size():
			failures.append("concave shape did not reduce the collision count")
		_assert_cover(cells, rects, failures)


	func _assert_cover(
		expected: Array[Vector2i],
		rects: Array[Rect2i],
		failures: Array[String]
	) -> void:
		var expected_lookup: Dictionary[Vector2i, bool] = {}
		for cell: Vector2i in expected:
			expected_lookup[cell] = true
		var covered: Dictionary[Vector2i, bool] = {}
		for rect: Rect2i in rects:
			for y in range(rect.position.y, rect.end.y):
				for x in range(rect.position.x, rect.end.x):
					var cell := Vector2i(x, y)
					if covered.has(cell):
						failures.append("merged rectangles overlap at %s" % cell)
					covered[cell] = true
		if covered.size() != expected_lookup.size():
			failures.append("merged rectangles changed the occupied cell count")
			return
		for cell: Vector2i in expected_lookup:
			if not covered.has(cell):
				failures.append("merged rectangles lost cell %s" % cell)


## tests/world/test_pixel_camera.gd
class PixelCameraCase extends Node:
	const CAMERA_PATH := "res://addons/platformer_kit/camera/pixel_camera_2d.gd"


	func run() -> Array[String]:
		var failures: Array[String] = []
		var script := load(CAMERA_PATH) as Script
		if script == null or not script.can_instantiate():
			return ["PixelCamera2D could not be loaded"]
		var camera := script.new() as Camera2D
		if not camera.has_method("set_room_bounds"):
			failures.append("PixelCamera2D is missing set_room_bounds")
		if not camera.has_method("clear_room_bounds"):
			failures.append("PixelCamera2D is missing clear_room_bounds")
		if not camera.has_method("set_camera_mode"):
			failures.append("PixelCamera2D is missing set_camera_mode")
		if failures.is_empty():
			camera.set("camera_mode", 0)
			camera.call("set_room_bounds", Rect2(Vector2.ZERO, Vector2(640, 180)))
			if camera.get("camera_mode") != 0:
				failures.append("supplying room bounds changed free camera mode")
			camera.call("set_camera_mode", 1)
			camera.global_position = Vector2(1000, 1000)
			camera.set("smoothed_position", Vector2(1000, 1000))
			camera.call("set_room_bounds", Rect2(Vector2.ZERO, Vector2(320, 180)))
			if not bool(camera.get("room_lock_is_fixed")):
				failures.append("one-chunk room was not marked fixed")
			if camera.global_position != Vector2(160, 90) or camera.get("smoothed_position") != Vector2(160, 90):
				failures.append("room change did not immediately clamp old camera state")
			camera.call("set_room_bounds", Rect2(Vector2.ZERO, Vector2(640, 180)))
			var left_target: Vector2 = camera.call("get_room_camera_target", Vector2.ZERO, Vector2(320, 180))
			var right_target: Vector2 = camera.call("get_room_camera_target", Vector2(640, 90), Vector2(320, 180))
			if left_target != Vector2(160, 90) or right_target != Vector2(480, 90):
				failures.append("multi-chunk room camera did not move within room bounds")
			camera.call("clear_room_bounds")
			if camera.get("camera_mode") != 1:
				failures.append("clear_room_bounds changed the authored camera mode")
			_assert_room_transition_modes(camera, failures)
		camera.free()
		return failures


	## A room switch is either a hard cut or a glide, and the setting has to be able to
	## pick: cutting also has to drop the engine's own position smoothing, otherwise the
	## camera keeps easing towards the new room while every overlay already rebound there.
	func _assert_room_transition_modes(camera: Camera2D, failures: Array[String]) -> void:
		if not camera.has_method("set_smooth_room_transition"):
			failures.append("PixelCamera2D is missing set_smooth_room_transition")
			return
		if not camera.has_method("snap_to_room"):
			failures.append("PixelCamera2D is missing snap_to_room")
			return
		camera.set("camera_mode", 1)
		camera.call("set_room_bounds", Rect2(Vector2(320, 0), Vector2(320, 180)))
		if camera.position_smoothing_enabled:
			failures.append("camera smoothed by default; the instant cut is the default")
		camera.call("set_smooth_room_transition", true)
		if not camera.position_smoothing_enabled:
			failures.append("smooth transition did not turn camera smoothing on")
		camera.call("set_room_bounds", Rect2(Vector2.ZERO, Vector2(320, 180)))
		camera.global_position = Vector2(1000, 1000)
		camera.call("set_smooth_room_transition", false)
		if camera.position_smoothing_enabled:
			failures.append("instant transition kept camera smoothing on")
		var target := Node2D.new()
		add_child(target)
		target.global_position = Vector2(900, 90)
		camera.call("bind_target", target)
		camera.call("snap_to_room")
		if camera.global_position != Vector2(160, 90):
			failures.append("snap_to_room did not land on the room centre (%s)" % str(camera.global_position))
		if camera.get("smoothed_position") != Vector2(160, 90):
			failures.append("snap_to_room left a stale smoothed position behind")
		remove_child(target)
		target.free()


## tests/world/test_world_data.gd
class WorldDataCase extends Node:
	const ROOM_DATA: Script = preload("res://addons/platformer_kit/world/data/room_data.gd")
	const WORLD_DATA: Script = preload("res://addons/platformer_kit/world/data/world_data.gd")
	const ROOM_CONNECTION_DATA: Script = preload("res://addons/platformer_kit/world/data/room_connection_data.gd")


	func run() -> Array[String]:
		var failures: Array[String] = []
		_assert_world_owns_room_placements(failures)
		_assert_chunk_and_cell_bounds_use_world_placement(failures)
		_assert_spatial_and_connection_residency(failures)
		_assert_connection_lookup_and_adjacency(failures)
		_assert_position_lookup_is_deterministic(failures)
		_assert_shared_room_has_independent_world_placements(failures)
		return failures


	func _assert_world_owns_room_placements(failures: Array[String]) -> void:
		var world := _make_world([
			_make_room("room_b", Vector2i(1, 0)),
			_make_room("room_a", Vector2i(-1, 2)),
		])
		if world.get_room_ids() != ["room_a", "room_b"]:
			failures.append("world room ids were not sorted")
		if world.get_room_origin_chunk("room_a") != Vector2i(-1, 2):
			failures.append("world did not return its room placement")
		if not world.set_room_origin_chunk("room_a", Vector2i(3, -2)):
			failures.append("world rejected a valid room placement move")
		if world.get_room_origin_chunk("room_a") != Vector2i(3, -2):
			failures.append("world did not retain a moved room placement")
		if world.set_room_origin_chunk("missing", Vector2i.ZERO):
			failures.append("world accepted a placement for an unknown room")


	func _assert_chunk_and_cell_bounds_use_world_placement(failures: Array[String]) -> void:
		var room := _make_room("room_a", Vector2i(2, 1), Vector2i(3, 2))
		var world := _make_world([room])
		if world.get_room_chunk_rect("room_a") != Rect2i(2, 1, 3, 2):
			failures.append("world chunk bounds were wrong")
		if world.get_room_pixel_rect("room_a") != Rect2i(640, 184, 960, 360):
			failures.append("world pixel bounds were wrong")
		if world.get_room_cell_rect("room_a") != Rect2i(80, 23, 120, 45):
			failures.append("world cell bounds did not use exact chunk cell dimensions")


	func _assert_spatial_and_connection_residency(failures: Array[String]) -> void:
		var world := _make_world([
			_make_room("center", Vector2i.ZERO),
			_make_room("right", Vector2i.RIGHT),
			_make_room("left", Vector2i.LEFT),
			_make_room("up", Vector2i.UP),
			_make_room("down", Vector2i.DOWN),
			_make_room("diagonal", Vector2i(1, 1)),
			_make_room("current", Vector2i(20, 20)),
			_make_room("remote", Vector2i(30, 30)),
		])
		world.connections.assign([_make_connection("current", "exit", "remote", "entry")])
		var resident_ids: Array[String] = world.get_resident_room_ids(Vector2i.ZERO, "current")
		var expected := ["center", "current", "down", "left", "remote", "right", "up"]
		if resident_ids != expected:
			failures.append("residency did not include cardinal rooms and connections: %s" % str(resident_ids))
		if world.get_room_ids_at_chunk(Vector2i.ZERO) != ["center"]:
			failures.append("world did not index rooms by placed chunk")


	func _assert_connection_lookup_and_adjacency(failures: Array[String]) -> void:
		var world := _make_world([_make_room("room_a"), _make_room("room_b"), _make_room("room_c")])
		var first := _make_connection("room_a", "exit", "room_b", "entry")
		var second := _make_connection("room_c", "return", "room_a", "entry")
		world.connections.assign([first, second])
		if world.get_connection("room_a", "exit") != first:
			failures.append("world did not find a unique connection endpoint")
		if world.get_adjacent_room_ids("room_a") != ["room_b", "room_c"]:
			failures.append("world adjacency was not derived from connections")
		world.connections.append(first.duplicate())
		if world.get_connection("room_a", "exit") != null:
			failures.append("world accepted an ambiguous connection endpoint")


	func _assert_position_lookup_is_deterministic(failures: Array[String]) -> void:
		var world := _make_world([
			_make_room("room_a", Vector2i.ZERO, Vector2i(2, 1)),
			_make_room("room_b", Vector2i(1, 0)),
		])
		if world.get_chunk_at_world_position(Vector2(-0.1, -0.1)) != Vector2i(-1, -1):
			failures.append("negative world coordinates did not floor to a chunk")
		if world.get_room_id_at_world_position(Vector2(330, 20)) != "room_a":
			failures.append("overlapping room lookup was not deterministic")
		if world.get_room_id_at_world_position(Vector2(330, 20), "room_b") != "room_b":
			failures.append("preferred room lookup was ignored")


	func _assert_shared_room_has_independent_world_placements(failures: Array[String]) -> void:
		var shared := _make_room("shared")
		var world_a := _make_world([shared])
		var world_b := _make_world([shared])
		world_a.set_room_origin_chunk("shared", Vector2i(-1, -1))
		world_b.set_room_origin_chunk("shared", Vector2i(4, 2))
		if world_a.get_room_origin_chunk("shared") != Vector2i(-1, -1):
			failures.append("first world placement was not retained")
		if world_b.get_room_origin_chunk("shared") != Vector2i(4, 2):
			failures.append("second world placement was not independent")


	func _make_world(rooms: Array[Resource]) -> Resource:
		var world: Resource = WORLD_DATA.new()
		world.world_id = "world_01"
		world.rooms.assign(rooms)
		for room: Resource in rooms:
			world.set_room_origin_chunk(room.room_id, room.get_meta("test_origin", Vector2i.ZERO))
		return world


	func _make_room(room_id: String, origin: Vector2i = Vector2i.ZERO, size: Vector2i = Vector2i.ONE) -> Resource:
		var room: Resource = ROOM_DATA.new()
		room.room_id = room_id
		room.scene_path = "res://scenes/rooms/generated/%s/runtime.tscn" % room_id
		room.room_size_chunks = size
		room.set_meta("test_origin", origin)
		return room


	func _make_connection(from_room_id: String, entrance_id: String, to_room_id: String, spawn_id: String) -> Resource:
		var connection: Resource = ROOM_CONNECTION_DATA.new()
		connection.from_room_id = from_room_id
		connection.from_entrance_id = entrance_id
		connection.to_room_id = to_room_id
		connection.to_spawn_id = spawn_id
		return connection


func run() -> Array[String]:
	var failures: Array[String] = []
	failures.append_array(_run_case(TilemapSceneContractCase.new()))
	failures.append_array(_run_case(MapModelCase.new()))
	failures.append_array(_run_case(RoomTransitionCase.new()))
	failures.append_array(_run_case(WorldStackDataCase.new()))
	failures.append_array(_run_case(WorldValidationCase.new()))
	failures.append_array(_run_case(RoomGridCase.new()))
	failures.append_array(_run_case(CellRectMergerCase.new()))
	failures.append_array(_run_case(PixelCameraCase.new()))
	failures.append_array(_run_case(WorldDataCase.new()))
	return failures


func _run_case(test: Node) -> Array[String]:
	add_child(test)
	var result: Array = test.call("run")
	test.queue_free()
	var failures: Array[String] = []
	failures.assign(result)
	return failures
