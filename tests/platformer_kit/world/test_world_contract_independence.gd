extends Node

const WORLD_DATA_PATH := "res://addons/platformer_kit/world/data/world_data.gd"
const ROOM_DATA_PATH := "res://addons/platformer_kit/world/data/room_data.gd"
const WORLD_RUNTIME_PATH := "res://addons/platformer_kit/world/runtime/world_runtime.gd"
const ROOM_RUNTIME_PATH := "res://addons/platformer_kit/world/runtime/room_runtime.gd"
const WORLD_SESSION_PATH := "res://addons/platformer_kit/world/runtime/world_session.gd"
const REGION_PATH := "res://addons/platformer_kit/world/region/region_data.gd"
const GRAPH_PATH := "res://addons/platformer_kit/world/graph/world_graph.gd"
const TRANSITION_PATH := "res://addons/platformer_kit/world/transition/room_transition.gd"


func run() -> Array[String]:
	var failures: Array[String] = []
	var world_script := load(WORLD_DATA_PATH) as Script
	var room_script := load(ROOM_DATA_PATH) as Script
	var runtime_script := load(WORLD_RUNTIME_PATH) as Script
	var room_runtime_script := load(ROOM_RUNTIME_PATH) as Script
	var session_script := load(WORLD_SESSION_PATH) as Script
	var region_script := load(REGION_PATH) as Script
	var graph_script := load(GRAPH_PATH) as Script
	var transition_script := load(TRANSITION_PATH) as Script
	if world_script == null or room_script == null or runtime_script == null or room_runtime_script == null or session_script == null or region_script == null or graph_script == null or transition_script == null:
		return ["framework world contracts could not be loaded from platformer_kit"]

	var world: Resource = world_script.new()
	var room: Resource = room_script.new()
	room.room_id = "isolated_room"
	room.room_size_chunks = Vector2i.ONE
	world.world_id = "isolated_world"
	var rooms: Array[Resource] = [room]
	world.rooms = rooms
	if world.get_room("isolated_room") != room:
		failures.append("framework WorldData could not resolve an isolated RoomData")
	var runtime: Node2D = runtime_script.new()
	var room_runtime: Node2D = room_runtime_script.new()
	if not runtime.has_method("bind_persistence_source"):
		failures.append("WorldRuntime does not expose explicit persistence injection")
	if not room_runtime.has_method("setup_room"):
		failures.append("RoomRuntime contract could not be instantiated independently")
	var session: Node2D = session_script.new()
	if not session.has_method("bind_persistence_source"):
		failures.append("WorldSession does not expose explicit persistence injection")
	var region: Resource = region_script.new()
	region.region_id = &"forest"
	region.room_ids = PackedStringArray(["isolated_room"])
	if not region.contains_room(&"isolated_room"):
		failures.append("RegionData did not retain stable room membership")
	var graph: RefCounted = graph_script.new()
	graph.add_room(&"room:a")
	graph.add_room(&"room:b")
	graph.connect_rooms(&"room:a", &"room:b", false)
	if graph.get_neighbors(&"room:a") != [&"room:b"] or not graph.get_neighbors(&"room:b").is_empty():
		failures.append("WorldGraph did not preserve directed room topology")
	for path: String in [WORLD_RUNTIME_PATH, ROOM_RUNTIME_PATH, WORLD_SESSION_PATH]:
		var source := FileAccess.get_file_as_string(path)
		if source.contains("get_node_or_null(\"SaveManager\")") or source.contains("main_world.tres"):
			failures.append("framework runtime contains a fixed project persistence/world fallback: %s" % path)
	runtime.free()
	room_runtime.free()
	session.free()
	return failures
