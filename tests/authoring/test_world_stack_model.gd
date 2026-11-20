extends Node

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
