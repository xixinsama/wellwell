extends Node

## Merged test suite. Every inner class below is one original test file,
## kept in its own class so fixtures and helper names stay isolated. Do not
## add logic here: split a class back into its own file when it grows.

## tests/authoring/test_world_stack_model.gd
class WorldStackModelCase extends Node:
	## Coverage for the stacked-world model: door link classification (portal inside a
	## layer, shuttle across layers, dangling) and the editor's layer order. Pure
	## data, no file IO.

	const STACK := preload("res://addons/world_editor/authoring/world/world_stack_model.gd")
	const ANNOTATIONS := preload("res://addons/world_editor/authoring/world/room_annotation_service.gd")
	const WORLD_DATA := preload("res://addons/platformer_kit/world/data/world_data.gd")
	const ROOM_DATA := preload("res://addons/platformer_kit/world/data/room_data.gd")
	const DOOR := preload("res://addons/platformer_kit/world/entities/world_door.gd")


	func run() -> Array[String]:
		var failures: Array[String] = []
		_assert_door_links(failures)
		_assert_stack_order(failures)
		return failures


	## Door links drive both the 2D portal arrows and the 3D cross-layer arcs.
	func _assert_door_links(failures: Array[String]) -> void:
		var model := STACK.new()
		var doors: Array[Dictionary] = [
			_door_record("main", 0, "room_a", "portal_w", DOOR.Kind.PORTAL, "", "room_b", "portal_e", Vector2(16, 16)),
			_door_record("main", 0, "room_b", "portal_e", DOOR.Kind.PORTAL, "", "room_a", "portal_w", Vector2(400, 16)),
			_door_record("main", 0, "room_a", "shuttle_n", DOOR.Kind.SHUTTLE, "shadow", "room_s", "shuttle_s", Vector2(32, 32)),
			_door_record("shadow", 1, "room_s", "shuttle_s", DOOR.Kind.SHUTTLE, "main", "room_a", "shuttle_n", Vector2(64, 64)),
			_door_record("shadow", 1, "room_s", "orphan", DOOR.Kind.SHUTTLE, "main", "room_a", "nowhere", Vector2(96, 96)),
		]
		var report: Dictionary = model.call("build_door_links", doors)
		var links: Array = report.get("links", [])
		if links.size() != 3:
			failures.append("build_door_links must emit one link per pair plus one per orphan: %d" % links.size())
			return
		var by_key: Dictionary = {}
		for link: Dictionary in links:
			by_key[String(link.get("from_door_id", ""))] = link

		var portal: Dictionary = by_key.get("portal_w", {})
		if String(portal.get("kind", "")) != "portal":
			failures.append("a same-world pair was not classified as a portal link")
		if not bool(portal.get("paired", false)):
			failures.append("a mutual portal pair was not classified as paired")
		if by_key.has("portal_e"):
			failures.append("a mutual pair was emitted twice")
		_assert_equal(portal.get("to_position", Vector2.ZERO), Vector2(400, 16), "portal link keeps the partner position", failures)

		var shuttle: Dictionary = by_key.get("shuttle_n", {})
		if String(shuttle.get("kind", "")) != "shuttle":
			failures.append("a cross-world pair was not classified as a shuttle link")
		if not bool(shuttle.get("paired", false)):
			failures.append("a mutual shuttle pair was not classified as paired")
		_assert_equal(int(shuttle.get("from_layer", -1)), 0, "shuttle link keeps the source layer", failures)
		_assert_equal(int(shuttle.get("to_layer", -1)), 1, "shuttle link keeps the target layer", failures)

		var orphan: Dictionary = by_key.get("orphan", {})
		if bool(orphan.get("paired", true)):
			failures.append("an orphan door was classified as paired")
		_assert_equal(
			orphan.get("to_position", Vector2.ZERO),
			Vector2(96, 96) + STACK.DANGLING_STUB,
			"an orphan link gets a stub end position",
			failures
		)
		_assert_equal(int(report.get("dangling_count", -1)), 1, "dangling_count counts orphan doors", failures)

		var portal_only: Array = model.call("build_portal_links", _make_world("main", [["room_a", Vector2i.ZERO, Vector2i.ONE]]), "main", {
			"room_a": [
				_door("p1", DOOR.Kind.PORTAL, "", "room_a", "p2", Vector2(16, 16)),
				_door("p2", DOOR.Kind.PORTAL, "", "room_a", "p1", Vector2(300, 16)),
			],
		})
		if portal_only.size() != 1:
			failures.append("build_portal_links did not return exactly one pair: %d" % portal_only.size())
		elif String(portal_only[0].get("kind", "")) != "portal":
			failures.append("build_portal_links leaked a non-portal link")
		elif not bool(portal_only[0].get("paired", false)):
			failures.append("build_portal_links did not pair two doors in the same room")


	func _assert_stack_order(failures: Array[String]) -> void:
		var model := STACK.new()
		var catalog: Array[String] = ["main", "shadow", "loop", "tide"]

		var saved := PackedStringArray(["tide", "ghost_world", "shadow", "shadow", "main"])
		var resolved: Array = model.call("resolve_stack_order", "main", saved, catalog)
		_assert_equal(resolved, ["tide", "shadow"] as Array[String], "saved order keeps catalog worlds once, current excluded", failures)

		var empty: Array = model.call("resolve_stack_order", "main", PackedStringArray(), catalog)
		_assert_equal(empty, ["shadow", "loop", "tide"] as Array[String], "an empty order falls back to the whole catalog", failures)

		var only_current: Array = model.call("resolve_stack_order", "main", PackedStringArray(["main"]), catalog)
		_assert_equal(only_current, ["shadow", "loop", "tide"] as Array[String], "an order of only the current world falls back too", failures)

		var base: Array[String] = ["shadow", "loop"]
		_assert_equal(
			model.call("add_to_stack_order", base, "tide"),
			["shadow", "loop", "tide"] as Array[String],
			"adding appends at the top of the stack",
			failures
		)
		_assert_equal(model.call("add_to_stack_order", base, "loop"), base, "adding a present world is a no-op", failures)
		_assert_equal(model.call("add_to_stack_order", base, ""), base, "adding an empty id is a no-op", failures)
		_assert_equal(
			model.call("remove_from_stack_order", base, "shadow"),
			["loop"] as Array[String],
			"removing drops the world",
			failures
		)
		_assert_equal(
			model.call("move_in_stack_order", ["a", "b", "c"] as Array[String], 0, 2),
			["b", "c", "a"] as Array[String],
			"moving a layer to the top keeps the others in order",
			failures
		)
		_assert_equal(
			model.call("move_in_stack_order", ["a", "b", "c"] as Array[String], 2, 0),
			["c", "a", "b"] as Array[String],
			"moving a layer to the bottom keeps the others in order",
			failures
		)
		_assert_equal(
			model.call("move_in_stack_order", ["a", "b"] as Array[String], 5, 0),
			["a", "b"] as Array[String],
			"an out-of-range move is a no-op",
			failures
		)
		_assert_equal(
			model.call("move_in_stack_order", ["a", "b"] as Array[String], 0, 99),
			["b", "a"] as Array[String],
			"a move past the end clamps to the top",
			failures
		)


	func _make_world(world_id: String, rooms: Array) -> WorldData:
		var world := WORLD_DATA.new() as WorldData
		world.world_id = world_id
		world.display_name = world_id.capitalize()
		for entry: Array in rooms:
			var room := ROOM_DATA.new() as RoomData
			room.room_id = String(entry[0])
			room.room_size_chunks = entry[2] as Vector2i
			world.rooms.append(room)
			world.set_room_origin_chunk(room.room_id, entry[1] as Vector2i)
		return world


	func _door_record(
		world_id: String,
		layer: int,
		room_id: String,
		door_id: String,
		kind: int,
		target_world_id: String,
		target_room_id: String,
		target_door_id: String,
		position: Vector2
	) -> Dictionary:
		return {
			"world_id": world_id,
			"layer": layer,
			"room_id": room_id,
			"door_id": door_id,
			"door_kind": kind,
			"target_world_id": target_world_id,
			"target_room_id": target_room_id,
			"target_door_id": target_door_id,
			"position": position,
		}


	func _door(
		door_id: String,
		kind: int,
		target_world_id: String,
		target_room_id: String,
		target_door_id: String,
		position: Vector2
	) -> Dictionary:
		return {
			"type": ANNOTATIONS.TYPE_DOOR,
			"id": door_id,
			"name": door_id,
			"position": position,
			"path": "Entities/%s" % door_id,
			"door_kind": kind,
			"target_world_id": target_world_id,
			"target_room_id": target_room_id,
			"target_door_id": target_door_id,
		}


	func _assert_equal(actual: Variant, expected: Variant, label: String, failures: Array[String]) -> void:
		if actual != expected:
			failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])


## tests/authoring/test_world_stack_camera.gd
class WorldStackCameraCase extends Node:
	## Coverage for the 3D stack projection: the fitted stack stays on screen, slices
	## sit above each other, and picking selects the nearest slice. Pure maths.

	const CAMERA := preload("res://addons/world_editor/authoring/world/world_stack_camera.gd")


	func run() -> Array[String]:
		var failures: Array[String] = []
		_assert_fit_frames_every_slice(failures)
		_assert_stacking_order(failures)
		_assert_picking(failures)
		_assert_pan_moves_the_view(failures)
		_assert_unproject_round_trips(failures)
		_assert_floor_plan_orientation(failures)
		_assert_orbit_and_zoom_clamp(failures)
		return failures


	## Room positions must read the same way as in the 2D editor: +y goes down the
	## floor plan, z points up. This keeps the two views from being mirrored.
	func _assert_floor_plan_orientation(failures: Array[String]) -> void:
		var camera := _make_camera()
		camera.fit([Rect2(0, 0, 2, 2), Rect2(0, 0, 2, 2)])
		var north := camera.project(Vector3(1.0, 0.0, 0.0))
		var south := camera.project(Vector3(1.0, 2.0, 0.0))
		if south.y <= north.y:
			failures.append("world +y does not render below -y: %s vs %s" % [str(south), str(north)])
		var lower := camera.project(Vector3(1.0, 1.0, 0.0))
		var upper := camera.project(Vector3(1.0, 1.0, CAMERA.LAYER_HEIGHT))
		if upper.y >= lower.y:
			failures.append("the layer axis does not point up the screen")
		var east := camera.project(Vector3(2.0, 1.0, 0.0))
		if east.x <= lower.x:
			failures.append("world +x does not render to the right of -x")


	func _make_camera() -> WorldStackCamera:
		var camera: WorldStackCamera = CAMERA.new()
		camera.viewport_size = Vector2(800, 600)
		return camera


	func _assert_fit_frames_every_slice(failures: Array[String]) -> void:
		var camera := _make_camera()
		var bounds: Array[Rect2] = [Rect2(-1, -1, 3, 2), Rect2(0, 0, 4, 1)]
		if not camera.fit(bounds):
			failures.append("stack camera refused a valid two-layer fit")
			return
		for index: int in range(bounds.size()):
			for point: Vector2 in camera.slab_quad(bounds[index], index):
				if point.x < 0.0 or point.y < 0.0 or point.x > 800.0 or point.y > 600.0:
					failures.append("fitted slice %d leaves the viewport: %s" % [index, str(point)])
					return
		if not camera.fit([Rect2(0, 0, 1, 1)] as Array[Rect2]):
			failures.append("stack camera refused a single-layer fit")
		if camera.fit([] as Array[Rect2]):
			failures.append("stack camera fitted an empty stack")


	func _assert_stacking_order(failures: Array[String]) -> void:
		var camera := _make_camera()
		var bounds: Array[Rect2] = [Rect2(0, 0, 2, 2), Rect2(0, 0, 2, 2)]
		camera.fit(bounds)
		var lower := camera.project(Vector3(0.5, 0.5, 0.0))
		var upper := camera.project(Vector3(0.5, 0.5, CAMERA.LAYER_HEIGHT))
		if upper.y >= lower.y:
			failures.append("a higher slice does not sit above a lower one on screen")
		var near_scale := camera.project_scale(Vector3(0.5, 0.5, CAMERA.LAYER_HEIGHT))
		var far_scale := camera.project_scale(Vector3(0.5, 0.5, 0.0))
		if near_scale <= far_scale:
			failures.append("higher slices are not nearer: %.2f vs %.2f" % [near_scale, far_scale])
		if camera.layer_z(0) != 0.0 or not is_equal_approx(camera.layer_z(1), CAMERA.LAYER_HEIGHT):
			failures.append("layer height is not applied per slice")


	func _assert_picking(failures: Array[String]) -> void:
		var camera := _make_camera()
		# Two tall, fully overlapping slices: the nearest one must win.
		var overlap: Array[Rect2] = [Rect2(0, 0, 2, 8), Rect2(0, 0, 2, 8)]
		camera.fit(overlap)
		var middle := camera.project(Vector3(1.0, 4.0, 0.0))
		if camera.pick_layer(middle, overlap) != 1:
			failures.append("picking the overlapping centre did not select the nearest slice")
		var first := camera.pick_layer(middle, overlap)
		for _index: int in range(3):
			if camera.pick_layer(middle, overlap) != first:
				failures.append("slice picking is not deterministic")
				break
		# Two slices side by side: each only answers for its own footprint.
		var apart: Array[Rect2] = [Rect2(0, 0, 1, 1), Rect2(8, 0, 1, 1)]
		camera.fit(apart)
		var on_lower := camera.project(Vector3(0.5, 0.5, 0.0))
		var on_upper := camera.project(Vector3(8.5, 0.5, CAMERA.LAYER_HEIGHT))
		if camera.pick_layer(on_lower, apart) != 0:
			failures.append("picking a lone lower slice did not return it")
		if camera.pick_layer(on_upper, apart) != 1:
			failures.append("picking a lone upper slice did not return it")
		if camera.pick_layer(Vector2(-4000, -4000), apart) != -1:
			failures.append("picking outside every slice did not return -1")
		if camera.pick_layer(middle, [] as Array[Rect2]) != -1:
			failures.append("picking an empty stack did not return -1")


	func _assert_pan_moves_the_view(failures: Array[String]) -> void:
		var camera := _make_camera()
		var before := camera.project(Vector3(1.0, 1.0, 0.0))
		camera.pan(Vector2(40, -25))
		var after := camera.project(Vector3(1.0, 1.0, 0.0))
		if not after.is_equal_approx(before + Vector2(40, -25)):
			failures.append("panning did not move the view by the drag delta: %s -> %s" % [str(before), str(after)])


	func _assert_unproject_round_trips(failures: Array[String]) -> void:
		var camera := _make_camera()
		var bounds: Array[Rect2] = [Rect2(0, 0, 3, 2), Rect2(0, 0, 3, 2)]
		camera.fit(bounds)
		camera.orbit(Vector2(35, 12))
		for layer_index: int in range(bounds.size()):
			for point: Vector2 in [Vector2(0.5, 0.5), Vector2(2.25, 1.4), Vector2(1.0, 1.9)]:
				var screen := camera.project(Vector3(point.x, point.y, camera.layer_z(layer_index)))
				var back: Vector3 = camera.unproject(screen, layer_index)
				if not is_equal_approx(back.x, point.x) or not is_equal_approx(back.y, point.y):
					failures.append(
						"unproject did not invert project on layer %d: %s -> (%.3f, %.3f)"
						% [layer_index, str(point), back.x, back.y]
					)
					return
				if int(back.z) != layer_index:
					failures.append("unproject lost the layer index")
					return


	func _assert_orbit_and_zoom_clamp(failures: Array[String]) -> void:
		var camera := _make_camera()
		camera.orbit(Vector2(0, 100000))
		if camera.pitch > CAMERA.PITCH_MAX + 0.0001:
			failures.append("orbit did not clamp the pitch at the top")
		camera.orbit(Vector2(0, -100000))
		if camera.pitch < CAMERA.PITCH_MIN - 0.0001:
			failures.append("orbit did not clamp the pitch at the bottom")
		camera.zoom_by(1000.0)
		if camera.zoom > CAMERA.MAX_ZOOM + 0.0001:
			failures.append("zoom did not clamp at the maximum")
		camera.zoom_by(0.0001)
		if camera.zoom < CAMERA.MIN_ZOOM - 0.0001:
			failures.append("zoom did not clamp at the minimum")


func run() -> Array[String]:
	var failures: Array[String] = []
	failures.append_array(_run_case(WorldStackModelCase.new()))
	failures.append_array(_run_case(WorldStackCameraCase.new()))
	return failures


func _run_case(test: Node) -> Array[String]:
	add_child(test)
	var result: Array = test.call("run")
	test.queue_free()
	var failures: Array[String] = []
	failures.assign(result)
	return failures
