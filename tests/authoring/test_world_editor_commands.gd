extends Node

const DOCK_PATH := "res://addons/wellwell_world_editor/world_editor_dock.gd"
const DOCK_SCENE_PATH := "res://addons/wellwell_world_editor/world_editor_dock.tscn"
const WORLD_DATA := preload("res://scripts/world/world_data.gd")
const ROOM_DATA := preload("res://scripts/world/room_data.gd")
const CONNECTION_DATA := preload("res://scripts/world/room_connection_data.gd")
const CANVAS_PATH := "res://addons/wellwell_world_editor/world_layout_canvas.gd"
const EDITOR_DEPENDENCY_PATHS: Array[String] = [
	"res://scripts/world/world_data.gd",
	"res://scripts/world/room_data.gd",
	"res://scripts/world/room_connection_data.gd",
	"res://scripts/world/room_entrance.gd",
	"res://scripts/world/spawn_point.gd",
	"res://scripts/world/world_entity.gd",
	"res://scripts/world/world_validation.gd",
	"res://scripts/authoring/world_layout_model.gd",
	"res://scripts/authoring/room_authoring_contract.gd",
	"res://scripts/authoring/room_bake_manifest.gd",
	"res://scripts/authoring/room_bake_paths.gd",
]


class FakeUndo:
	var do_call: Callable
	var undo_call: Callable
	var action_name := ""
	func create_action(value: String) -> void: action_name = value
	func add_do_method(object: Object, method: StringName, a = null, b = null) -> void:
		do_call = Callable(object, method).bind(a, b) if b != null else Callable(object, method).bind(a)
	func add_undo_method(object: Object, method: StringName, a = null, b = null) -> void:
		undo_call = Callable(object, method).bind(a, b) if b != null else Callable(object, method).bind(a)
	func commit_action() -> void: do_call.call()


class FakeRoomBaker:
	var save_count := 0
	var staged_room: Resource
	func stage(_source: Node, _path: String) -> Dictionary:
		return {
			"ok": true,
			"errors": [],
			"warnings": [],
			"room_data": staged_room,
			"outputs": {"room_resource_path": "res://unused_duplicate_room.tres"},
		}
	func save_staged(staged: Dictionary) -> Dictionary:
		save_count += 1
		return staged


func run() -> Array[String]:
	if not FileAccess.file_exists(DOCK_PATH):
		return ["missing production API: %s" % DOCK_PATH]
	var failures: Array[String] = []
	_assert_editor_dependencies_are_tool_scripts(failures)
	_assert_toolbar_contract(failures)
	_assert_move_command(failures)
	_assert_add_remove_commands(failures)
	_assert_connection_commands(failures)
	_assert_rebake_sync_and_overlap_connection_geometry(failures)
	_assert_duplicate_existing_room_does_not_write_outputs(failures)
	return failures


func _assert_editor_dependencies_are_tool_scripts(failures: Array[String]) -> void:
	for path: String in EDITOR_DEPENDENCY_PATHS:
		var script := load(path) as Script
		if script == null or not script.is_tool():
			failures.append("world editor dependency is not a tool script: %s" % path)


func _assert_toolbar_contract(failures: Array[String]) -> void:
	var packed := load(DOCK_SCENE_PATH) as PackedScene
	var dock := packed.instantiate()
	for node_path: String in [
		"Toolbar/NewRoom",
		"Toolbar/AddExisting",
		"Toolbar/RemoveReference",
		"Toolbar/OpenSource",
		"Toolbar/ValidateRoom",
		"Toolbar/BakeRoom",
		"ConnectionBar/Connect",
		"ConnectionBar/Disconnect",
		"Toolbar/ValidateWorld",
		"Toolbar/BakeWorld",
	]:
		if not dock.has_node(node_path):
			failures.append("world editor dock is missing command control: %s" % node_path)
	var dialog := dock.get_node("AddExistingDialog") as FileDialog
	if dialog.access != FileDialog.ACCESS_RESOURCES:
		failures.append("Add Existing dialog can return non-res resource paths")
	dock.free()


func _assert_move_command(failures: Array[String]) -> void:
	var dock: Control = (load(DOCK_PATH) as Script).new() as Control
	var world: Resource = WORLD_DATA.new()
	var room: Resource = _make_room("room_a", ["exit"], ["start"])
	world.rooms.assign([room])
	var undo := FakeUndo.new()
	var changed_count := [0]
	world.changed.connect(func() -> void: changed_count[0] += 1)
	dock.call("set_world_data", world)
	dock.call("set_undo_redo_adapter", undo)
	if not dock.call("move_room", "room_a", Vector2i(3, -2)):
		failures.append("world editor move command was rejected")
	if room.room_origin_chunk != Vector2i(3, -2):
		failures.append("world editor move command did not apply integer chunks")
	if undo.action_name.is_empty() or not undo.undo_call.is_valid():
		failures.append("world editor move command did not register undo/redo")
	else:
		undo.undo_call.call()
		if room.room_origin_chunk != Vector2i.ZERO:
			failures.append("world editor move undo did not restore the origin")
		undo.do_call.call()
		if room.room_origin_chunk != Vector2i(3, -2):
			failures.append("world editor move redo did not restore the moved origin")
	if changed_count[0] < 2:
		failures.append("world editor move and undo did not mark WorldData changed")
	dock.free()


func _assert_add_remove_commands(failures: Array[String]) -> void:
	var room_a: Resource = _make_room("room_a", ["exit"], ["start"])
	var room_b: Resource = _make_room("room_b", ["return"], ["entry"])
	var world: Resource = WORLD_DATA.new()
	world.rooms.assign([room_a])
	var dock: Control = (load(DOCK_PATH) as Script).new() as Control
	var undo := FakeUndo.new()
	dock.call("set_world_data", world)
	dock.call("set_undo_redo_adapter", undo)
	if not dock.call("add_room", room_b) or not world.has_room("room_b"):
		failures.append("world editor add command did not add a room")
	elif undo.undo_call.is_valid():
		undo.undo_call.call()
		if world.has_room("room_b"):
			failures.append("world editor add undo did not remove the room")
	if dock.call("add_room", room_a):
		failures.append("world editor accepted a duplicate room command")

	world.rooms.assign([room_a, room_b])
	var connection: Resource = _make_connection()
	world.connections.assign([connection])
	world.start_room_id = "room_b"
	world.start_spawn_id = "entry"
	room_a.adjacent_room_ids = PackedStringArray(["room_b"])
	undo = FakeUndo.new()
	dock.call("set_undo_redo_adapter", undo)
	if not dock.call("remove_room", "room_b") or world.has_room("room_b"):
		failures.append("world editor remove command did not remove the room reference")
	elif undo.undo_call.is_valid():
		undo.undo_call.call()
		if not world.has_room("room_b"):
			failures.append("world editor remove undo did not restore the room")
		if world.connections.size() != 1:
			failures.append("world editor remove undo did not restore removed connections")
		if world.start_room_id != "room_b" or world.start_spawn_id != "entry":
			failures.append("world editor remove undo did not restore the start endpoint")
		if not room_a.adjacent_room_ids.has("room_b"):
			failures.append("world editor remove undo did not restore adjacency metadata")
		undo.do_call.call()
		if world.has_room("room_b") or not world.connections.is_empty():
			failures.append("world editor remove redo did not remove the restored room state")
	dock.free()


func _assert_connection_commands(failures: Array[String]) -> void:
	var world: Resource = WORLD_DATA.new()
	world.rooms.assign([
		_make_room("room_a", ["exit"], ["start"]),
		_make_room("room_b", ["return"], ["entry"]),
	])
	var dock: Control = (load(DOCK_PATH) as Script).new() as Control
	var undo := FakeUndo.new()
	dock.call("set_world_data", world)
	dock.call("set_undo_redo_adapter", undo)
	var connection: Resource = _make_connection()
	if not dock.call("connect_rooms", connection) or world.connections.size() != 1:
		failures.append("world editor connect command did not create a connection")
	elif undo.undo_call.is_valid():
		undo.undo_call.call()
		if not world.connections.is_empty():
			failures.append("world editor connect undo did not remove the connection")

	world.connections.assign([connection])
	undo = FakeUndo.new()
	dock.call("set_undo_redo_adapter", undo)
	if not dock.call("disconnect_rooms", "room_a", "exit") or not world.connections.is_empty():
		failures.append("world editor disconnect command did not remove the connection")
	elif undo.undo_call.is_valid():
		undo.undo_call.call()
		if world.connections.size() != 1:
			failures.append("world editor disconnect undo did not restore the connection")
	dock.free()


func _assert_rebake_sync_and_overlap_connection_geometry(failures: Array[String]) -> void:
	var world: Resource = WORLD_DATA.new()
	var old_room: Resource = _make_room("room_a", ["exit"], ["start"])
	old_room.room_origin_chunk = Vector2i(5, -1)
	old_room.adjacent_room_ids = PackedStringArray(["room_b"])
	world.rooms.assign([old_room])
	var dock: Control = (load(DOCK_PATH) as Script).new() as Control
	dock.call("set_world_data", world)
	if not dock.has_method("sync_room_resource"):
		failures.append("world editor is missing rebaked RoomData synchronization")
	else:
		var baked_room: Resource = _make_room("room_a", ["new_exit"], ["new_spawn"])
		baked_room.display_name = "Rebaked Room"
		if not dock.call("sync_room_resource", "room_a", baked_room):
			failures.append("world editor rejected rebaked RoomData synchronization")
		else:
			var current: Resource = world.get_room("room_a")
			if current.display_name != "Rebaked Room" or not current.spawn_ids.has("new_spawn"):
				failures.append("world editor did not synchronize rebaked RoomData metadata")
			if current.room_origin_chunk != Vector2i(5, -1) or not current.adjacent_room_ids.has("room_b"):
				failures.append("world editor rebake synchronization lost world layout metadata")
	dock.free()

	var canvas: Control = (load(CANVAS_PATH) as Script).new() as Control
	if not canvas.has_method("get_connection_geometry"):
		failures.append("world layout canvas is missing testable connection geometry")
	else:
		var geometry: PackedVector2Array = canvas.call("get_connection_geometry", Vector2(20, 20), Vector2(20, 20))
		if geometry.size() < 3:
			failures.append("world layout canvas omitted a connection between overlapping rooms")
	canvas.free()


func _assert_duplicate_existing_room_does_not_write_outputs(failures: Array[String]) -> void:
	var world: Resource = WORLD_DATA.new()
	world.rooms.assign([_make_room("level_0", [], ["start"])])
	var dock: Control = (load(DOCK_PATH) as Script).new() as Control
	var baker := FakeRoomBaker.new()
	baker.staged_room = _make_room("level_0", [], ["start"])
	if not dock.has_method("set_room_baker_adapter"):
		failures.append("world editor is missing injectable staged room baker")
		dock.free()
		return
	dock.call("set_world_data", world)
	dock.call("set_undo_redo_adapter", FakeUndo.new())
	dock.call("set_room_baker_adapter", baker)
	dock.call("_add_existing_source", "res://scenes/levels/level_0.tscn")
	if baker.save_count != 0:
		failures.append("Add Existing wrote generated outputs before rejecting duplicate room_id")
	dock.free()


func _make_room(room_id: String, entrances: Array[String], spawns: Array[String]) -> Resource:
	var room: Resource = ROOM_DATA.new()
	room.room_id = room_id
	room.display_name = room_id.capitalize()
	room.entrance_ids = PackedStringArray(entrances)
	room.spawn_ids = PackedStringArray(spawns)
	return room


func _make_connection() -> Resource:
	var connection: Resource = CONNECTION_DATA.new()
	connection.from_room_id = "room_a"
	connection.from_entrance_id = "exit"
	connection.to_room_id = "room_b"
	connection.to_spawn_id = "entry"
	return connection
