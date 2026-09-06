extends Node

const DOCK_PATH := "res://addons/wellwell_world_editor/world_editor_main.gd"
const DOCK_SCENE_PATH := "res://addons/wellwell_world_editor/world_editor_main.tscn"
const WORLD_DATA := preload("res://scripts/world/world_data.gd")
const ROOM_DATA := preload("res://scripts/world/room_data.gd")
const CONNECTION_DATA := preload("res://scripts/world/room_connection_data.gd")
const CANVAS_PATH := "res://addons/wellwell_world_editor/world_layout_canvas.gd"
const WORLD_RESOURCE_SERVICE := preload("res://scripts/authoring/world_resource_service.gd")
const WORLD_LAYOUT_MODEL := preload("res://scripts/authoring/world_layout_model.gd")
const CONTROLLER_WORLD_PATH := "res://resources/worlds/test_editor_controller_world.tres"
const CONTROLLER_OTHER_WORLD_PATH := "res://resources/worlds/test_editor_controller_other_world.tres"
const CONTROLLER_SOURCE_PATH := "res://tests/authoring/test_editor_controller_source.tscn"
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
	var action_context: Object
	func create_action(value: String, _merge_mode := UndoRedo.MERGE_DISABLE, context: Object = null) -> void:
		action_name = value
		action_context = context
	func add_do_method(object: Object, method: StringName, a = null, b = null) -> void:
		do_call = Callable(object, method).bind(a, b) if b != null else Callable(object, method).bind(a)
	func add_undo_method(object: Object, method: StringName, a = null, b = null) -> void:
		undo_call = Callable(object, method).bind(a, b) if b != null else Callable(object, method).bind(a)
	var commit_execute := true
	func commit_action(execute := true) -> void:
		commit_execute = execute
		if execute:
			do_call.call()


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


class FakeImporter:
	var result: Dictionary
	var call_count := 0
	func import_room(_world: Resource, _source: Node, _path: String) -> Dictionary:
		call_count += 1
		return result


class FakeCanvas extends Control:
	var focused_room_id := ""
	func focus_room(room_id: String) -> bool:
		focused_room_id = room_id
		return true


class FakeEditorInterface:
	var opened_path := ""
	var inherited := false
	func open_scene_from_path(path: String, set_inherited := false) -> void:
		opened_path = path
		inherited = set_inherited


class FailingWorldResources:
	var service: Object = WORLD_RESOURCE_SERVICE.new()
	func load_world(path: String) -> Dictionary:
		return service.call("load_world", path)
	func save_candidate(_world: Resource, path: String) -> Dictionary:
		return {
			"ok": false,
			"errors": ["forced history save failure"],
			"warnings": [],
			"world": null,
			"path": path,
		}


func run() -> Array[String]:
	if not FileAccess.file_exists(DOCK_PATH):
		return ["missing production API: %s" % DOCK_PATH]
	var failures: Array[String] = []
	_assert_editor_dependencies_are_tool_scripts(failures)
	_assert_toolbar_contract(failures)
	_assert_world_resource_controls(failures)
	_assert_world_selection_behavior(failures)
	_assert_command_states_and_import_history(failures)
	_assert_move_command(failures)
	_assert_add_remove_commands(failures)
	_assert_connection_commands(failures)
	_assert_rebake_sync_and_overlap_connection_geometry(failures)
	_assert_duplicate_existing_room_does_not_write_outputs(failures)
	_cleanup_controller_fixtures()
	return failures


func _assert_editor_dependencies_are_tool_scripts(failures: Array[String]) -> void:
	for path: String in EDITOR_DEPENDENCY_PATHS:
		var script := load(path) as Script
		if script == null or not script.is_tool():
			failures.append("world editor dependency is not a tool script: %s" % path)


func _assert_toolbar_contract(failures: Array[String]) -> void:
	var packed := load(DOCK_SCENE_PATH) as PackedScene
	var state := packed.get_state()
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
		if _scene_node_index(state, node_path) < 0:
			failures.append("world editor dock is missing command control: %s" % node_path)
	if int(_scene_node_property(state, "AddExistingDialog", &"access", -1)) != FileDialog.ACCESS_RESOURCES:
		failures.append("Add Existing dialog can return non-res resource paths")


func _assert_world_resource_controls(failures: Array[String]) -> void:
	var packed := load(DOCK_SCENE_PATH) as PackedScene
	var state := packed.get_state()
	for node_path: String in [
		"WorldToolbar/WorldPicker",
		"WorldToolbar/NewWorld",
		"WorldToolbar/SaveWorld",
		"ViewToolbar/FocusAll",
		"ViewToolbar/ResetView",
		"ViewToolbar/ZoomLabel",
		"NewWorldDialog",
	]:
		if _scene_node_index(state, node_path) < 0:
			failures.append("world editor main screen is missing world control: %s" % node_path)
	if String(_scene_node_property(state, "WorldToolbar/WorldPicker", &"base_type", "")) != "WorldData":
		failures.append("world picker is not restricted to WorldData")
	if int(_scene_node_property(state, "NewWorldDialog", &"access", -1)) != FileDialog.ACCESS_RESOURCES \
		or int(_scene_node_property(state, "NewWorldDialog", &"file_mode", -1)) != FileDialog.FILE_MODE_SAVE_FILE:
		failures.append("New World dialog is not a resource save dialog")
	if String(_scene_node_property(state, "NewWorldDialog", &"current_dir", "")) != "res://resources/worlds" \
		or String(_scene_node_property(state, "NewWorldDialog", &"root_subfolder", "")) != "res://resources/worlds":
		failures.append("New World dialog is not confined to res://resources/worlds")
	var filters: PackedStringArray = _scene_node_property(state, "NewWorldDialog", &"filters", PackedStringArray())
	if not filters.has("*.tres ; WorldData Resource"):
		failures.append("New World dialog does not filter WorldData .tres resources")
	if not bool(_scene_node_property(state, "Toolbar/AddExisting", &"disabled", false)):
		failures.append("Add Existing is not initially disabled without WorldData")
	if String(_scene_node_property(state, "Toolbar/AddExisting", &"tooltip_text", "")) != "Select or create a WorldData resource first":
		failures.append("Add Existing does not explain its missing WorldData prerequisite")
	if int(_scene_node_property(state, "LayoutCanvas", &"focus_mode", Control.FOCUS_NONE)) != Control.FOCUS_ALL:
		failures.append("world canvas cannot receive Space key input")


func _assert_world_selection_behavior(failures: Array[String]) -> void:
	var main := (load(DOCK_PATH) as Script).new() as Control
	var world_a: Resource = WORLD_DATA.new()
	world_a.rooms.assign([_make_room("room_a", [], ["start"])])
	main.call("set_world_data", world_a)
	main.call("select_room", "room_a")
	var replacement: Resource = WORLD_DATA.new()
	replacement.rooms.assign([_make_room("room_a", [], ["start"])])
	main.call("set_world_data", replacement, true)
	if main.get("selected_room_id") != "room_a":
		failures.append("set_world_data did not preserve a valid room selection")
	var unrelated: Resource = WORLD_DATA.new()
	main.call("set_world_data", unrelated, true)
	if not String(main.get("selected_room_id")).is_empty():
		failures.append("set_world_data preserved a room missing from the replacement world")
	main.call("_on_world_resource_changed", replacement)
	if main.get("world_data") != replacement:
		failures.append("world picker resource change did not update world_data")
	main.call("set_world_data", null)
	var result: Dictionary = main.call("save_world")
	if bool(result.get("ok", false)) or result.get("errors", []).is_empty():
		failures.append("saving without WorldData did not report an explicit status")
	main.free()


func _assert_command_states_and_import_history(failures: Array[String]) -> void:
	var main := (load(DOCK_PATH) as Script).new() as Control
	if not main.has_method("get_command_state") or not main.has_method("set_world_room_importer_adapter"):
		failures.append("world editor is missing explicit command state or importer injection")
		main.free()
		return
	var empty_state: Dictionary = main.call("get_command_state")
	if not bool(empty_state.get("add_existing_disabled", false)):
		failures.append("Add Existing command state is enabled without WorldData")

	main.set("status_label", Label.new())
	main.set("canvas", FakeCanvas.new())
	var unsaved := WORLD_DATA.new() as Resource
	main.call("set_world_data", unsaved)
	main.call("_add_existing_source", CONTROLLER_SOURCE_PATH)
	if not String((main.get("status_label") as Label).text).contains("saved WorldData"):
		failures.append("unsaved WorldData import did not show an explicit error")

	_cleanup_controller_fixtures()
	if not _save_controller_source(failures):
		main.free()
		return
	var empty_world := WORLD_DATA.new() as Resource
	empty_world.world_id = "test_editor_controller_world"
	if ResourceSaver.save(empty_world, CONTROLLER_WORLD_PATH) != OK:
		failures.append("could not save controller WorldData fixture")
		main.free()
		return
	empty_world = ResourceLoader.load(CONTROLLER_WORLD_PATH, "WorldData", ResourceLoader.CACHE_MODE_IGNORE) as Resource
	main.call("set_world_data", empty_world)
	var saved_state: Dictionary = main.call("get_command_state")
	if bool(saved_state.get("add_existing_disabled", true)):
		failures.append("Add Existing command state stayed disabled for saved WorldData")

	var importer := FakeImporter.new()
	importer.result = {
		"ok": false,
		"errors": ["import first error", "import detail error"],
		"warnings": [],
		"world": null,
		"room": null,
		"path": CONTROLLER_WORLD_PATH,
		"outputs": {},
	}
	main.call("set_world_room_importer_adapter", importer)
	main.call("_add_existing_source", CONTROLLER_SOURCE_PATH)
	var status := main.get("status_label") as Label
	if status.text != "import first error" or not status.tooltip_text.contains("import detail error"):
		failures.append("import failure did not retain first and full error details")

	var imported_world := empty_world.duplicate(true) as Resource
	var imported_room := _make_room("imported_room", [], ["alpha", "preview_z"])
	imported_room.source_scene_path = CONTROLLER_SOURCE_PATH
	imported_world.rooms.append(imported_room)
	imported_world.start_room_id = "imported_room"
	imported_world.start_spawn_id = "preview_z"
	if ResourceSaver.save(imported_world, CONTROLLER_WORLD_PATH) != OK:
		failures.append("could not save imported controller fixture")
		main.free()
		return
	imported_world = ResourceLoader.load(CONTROLLER_WORLD_PATH, "WorldData", ResourceLoader.CACHE_MODE_IGNORE) as Resource
	imported_room = imported_world.get_room("imported_room")
	var model: Object = WORLD_LAYOUT_MODEL.new()
	var undo := FakeUndo.new()
	main.call("set_world_data", empty_world)
	main.call("set_undo_redo_adapter", undo)
	importer.result = {
		"ok": true,
		"errors": [],
		"warnings": [],
		"world": imported_world,
		"room": imported_room,
		"path": CONTROLLER_WORLD_PATH,
		"source_path": CONTROLLER_SOURCE_PATH,
		"outputs": {"world_resource_path": CONTROLLER_WORLD_PATH, "room_resource_path": "res://generated_room.tres"},
		"before_state": model.call("capture_world_state", empty_world),
		"after_state": model.call("capture_world_state", imported_world),
	}
	main.call("_add_existing_source", CONTROLLER_SOURCE_PATH)
	if main.get("world_data") != imported_world or main.get("selected_room_id") != "imported_room":
		failures.append("successful import did not select the validated saved room")
	if (main.get("canvas") as FakeCanvas).focused_room_id != "imported_room":
		failures.append("successful import did not focus the imported room")
	if undo.commit_execute or not undo.undo_call.is_valid() or not undo.do_call.is_valid():
		failures.append("successful import did not register non-executing undo/redo history")
	if undo.action_context != imported_world:
		failures.append("import history was not associated with its WorldData resource")
	if not status.tooltip_text.contains("world_resource_path") or not status.tooltip_text.contains("room_resource_path"):
		failures.append("successful import status omitted output paths")

	if undo.undo_call.is_valid():
		undo.undo_call.call()
		var undone: Resource = main.get("world_data")
		if not undone.rooms.is_empty() or not undone.start_room_id.is_empty() or not undone.start_spawn_id.is_empty():
			failures.append("import undo did not restore empty world and clear start endpoint")
		undo.do_call.call()
		var redone: Resource = main.get("world_data")
		if not redone.has_room("imported_room") or redone.start_spawn_id != "preview_z":
			failures.append("import redo did not restore the manifest preview spawn")

		var other_world := WORLD_DATA.new() as Resource
		other_world.world_id = "test_editor_controller_other_world"
		other_world.rooms.append(_make_room("other_room", [], ["start"]))
		other_world.start_room_id = "other_room"
		other_world.start_spawn_id = "start"
		if ResourceSaver.save(other_world, CONTROLLER_OTHER_WORLD_PATH) != OK:
			failures.append("could not save secondary WorldData fixture")
		else:
			other_world = ResourceLoader.load(CONTROLLER_OTHER_WORLD_PATH, "WorldData", ResourceLoader.CACHE_MODE_IGNORE) as Resource
			main.call("set_world_data", other_world)
			undo.undo_call.call()
			var original_after_cross_undo := ResourceLoader.load(CONTROLLER_WORLD_PATH, "WorldData", ResourceLoader.CACHE_MODE_IGNORE) as Resource
			var other_after_cross_undo := ResourceLoader.load(CONTROLLER_OTHER_WORLD_PATH, "WorldData", ResourceLoader.CACHE_MODE_IGNORE) as Resource
			if main.get("world_data") != other_world or not other_after_cross_undo.has_room("other_room"):
				failures.append("import undo replaced or corrupted a different active world")
			if original_after_cross_undo == null or not original_after_cross_undo.rooms.is_empty():
				failures.append("cross-world import undo did not update its original world")
			undo.do_call.call()
			var original_after_cross_redo := ResourceLoader.load(CONTROLLER_WORLD_PATH, "WorldData", ResourceLoader.CACHE_MODE_IGNORE) as Resource
			if original_after_cross_redo == null or not original_after_cross_redo.has_room("imported_room"):
				failures.append("cross-world import redo did not update its original world")
			main.call("set_world_data", original_after_cross_redo)
		main.call("set_world_resource_service_adapter", FailingWorldResources.new())
		var live_before_failure: Resource = main.get("world_data")
		undo.undo_call.call()
		if main.get("world_data") != live_before_failure or not live_before_failure.has_room("imported_room"):
			failures.append("failed history save replaced the live validated world")

	var editor := FakeEditorInterface.new()
	main.call("set_editor_interface", editor)
	main.call("new_room")
	if editor.opened_path != "res://scenes/templates/level_template.tscn" or not editor.inherited:
		failures.append("New Room no longer opens an inherited level template")
	main.call("set_world_data", imported_world)
	main.call("select_room", "imported_room")
	main.call("open_selected_source")
	if editor.opened_path != CONTROLLER_SOURCE_PATH:
		failures.append("Open Source did not open the selected room source path")
	(main.get("status_label") as Label).free()
	(main.get("canvas") as Control).free()
	main.free()


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


func _save_controller_source(failures: Array[String]) -> bool:
	var root := Node2D.new()
	root.name = "ControllerImportSource"
	var packed := PackedScene.new()
	var pack_error := packed.pack(root)
	root.free()
	if pack_error != OK or ResourceSaver.save(packed, CONTROLLER_SOURCE_PATH) != OK:
		failures.append("could not save controller room source fixture")
		return false
	return true


func _cleanup_controller_fixtures() -> void:
	for path: String in [CONTROLLER_WORLD_PATH, CONTROLLER_OTHER_WORLD_PATH, CONTROLLER_SOURCE_PATH]:
		for candidate: String in [path, path.trim_suffix(".tres") + ".stage.tres", path.trim_suffix(".tres") + ".backup.tres"]:
			if FileAccess.file_exists(candidate):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))


func _scene_node_index(state: SceneState, path: String) -> int:
	for index: int in state.get_node_count():
		if String(state.get_node_path(index)).trim_prefix("./") == path:
			return index
	return -1


func _scene_node_property(state: SceneState, path: String, property: StringName, default: Variant) -> Variant:
	var node_index := _scene_node_index(state, path)
	if node_index < 0:
		return default
	for property_index: int in state.get_node_property_count(node_index):
		if state.get_node_property_name(node_index, property_index) == property:
			return state.get_node_property_value(node_index, property_index)
	return default
