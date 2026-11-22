extends Node

const DOCK_PATH := "res://addons/world_editor/world_editor_main.gd"
const DOCK_SCENE_PATH := "res://addons/world_editor/world_editor_main.tscn"
const WORLD_DATA := preload("res://addons/platformer_kit/world/data/world_data.gd")
const ROOM_DATA := preload("res://addons/platformer_kit/world/data/room_data.gd")
const CONNECTION_DATA := preload("res://addons/platformer_kit/world/data/room_connection_data.gd")
const CANVAS_PATH := "res://addons/world_editor/world_layout_canvas.gd"
const WORLD_RESOURCE_SERVICE := preload("res://addons/world_editor/authoring/world/world_resource_service.gd")
const WORLD_LAYOUT_MODEL := preload("res://addons/world_editor/authoring/world/world_layout_model.gd")
const CONTROLLER_WORLD_PATH := "res://resources/worlds/test_editor_controller_world.tres"
const CONTROLLER_OTHER_WORLD_PATH := "res://resources/worlds/test_editor_controller_other_world.tres"
const CONTROLLER_SOURCE_PATH := "res://tests/authoring/test_editor_controller_source.tscn"
## Stack fixtures live in user:// so the test never writes into the project.
const STACK_WORLD_PATH := "user://test_editor_stack_world.tres"
const STACK_PATH := "user://test_editor_stack_world_stack.tres"
## A world deliberately absent from world_catalog.tres: New World creates such
## worlds, so the stack has to be able to layer them anyway.
const STACK_EXTRA_WORLD_PATH := "user://test_editor_stack_extra_world.tres"
const STACK_SCAN_DIRECTORY := "user://"
const EDITOR_DEPENDENCY_PATHS: Array[String] = [
    "res://addons/platformer_kit/world/data/world_data.gd",
    "res://addons/platformer_kit/world/data/room_data.gd",
    "res://addons/platformer_kit/world/data/room_connection_data.gd",
    "res://addons/platformer_kit/world/entities/room_entrance.gd",
    "res://addons/platformer_kit/world/entities/spawn_point.gd",
    "res://addons/platformer_kit/world/entities/world_entity.gd",
    "res://addons/platformer_kit/world/data/world_validation.gd",
    "res://addons/world_editor/authoring/world/world_layout_model.gd",
    "res://addons/world_editor/authoring/room/room_authoring_contract.gd",
    "res://addons/world_editor/authoring/room/room_bake_manifest.gd",
    "res://addons/world_editor/authoring/room/room_bake_paths.gd",
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
    func stage(_source: Node, _path: String, _origin_chunk: Variant = null, _world_terrain_path: String = "") -> Dictionary:
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
    var last_origin := Vector2i(-2147483648, -2147483648)
    func import_room(
        _world: Resource,
        _source: Node,
        _path: String,
        origin := Vector2i(-2147483648, -2147483648)
    ) -> Dictionary:
        call_count += 1
        last_origin = origin
        return result


class FakeCanvas extends Control:
    var focused_room_id := ""
    var focused_chunk := Vector2i.ZERO
    var cursor_chunk := Vector2i(4, -2)
    var cursor_over_canvas := true
    func focus_room(room_id: String) -> bool:
        focused_room_id = room_id
        return true
    func focus_chunk(chunk: Vector2i) -> void:
        focused_chunk = chunk
    func get_cursor_chunk() -> Vector2i:
        return cursor_chunk
    func get_view_center_chunk() -> Vector2i:
        return Vector2i(1, 1)
    func is_cursor_over_canvas() -> bool:
        return cursor_over_canvas
    var portal_links: Array = []
    func set_portal_links(links: Array) -> void:
        portal_links = links.duplicate()


class FakeViewCommands extends Control:
    var calls: Array[String] = []
    func focus_all() -> void:
        calls.append("focus_all")
    func reset_view() -> void:
        calls.append("reset_view")
    func focus_stack() -> void:
        calls.append("focus_stack")


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
    # Assertions below check English messages; pin the editor UI language.
    WorldEditorLocalization.locale_override = "en"
    _assert_editor_dependencies_are_tool_scripts(failures)
    _assert_toolbar_contract(failures)
    _assert_world_resource_controls(failures)
    _assert_world_selection_behavior(failures)
    _assert_command_states_and_import_history(failures)
    _assert_move_command(failures)
    _assert_status_bar_chunk_field(failures)
    _assert_stack_layers(failures)
    _assert_stack_accepts_uncatalogued_world(failures)
    _assert_stacked_world_reloads(failures)
    _assert_view_commands_route_to_the_3d_view(failures)
    _assert_add_remove_commands(failures)
    _assert_connection_commands(failures)
    _assert_rebake_sync_and_overlap_connection_geometry(failures)
    _assert_duplicate_existing_room_does_not_write_outputs(failures)
    _cleanup_controller_fixtures()
    WorldEditorLocalization.locale_override = ""
    WorldEditorLocalization.reset_cache()
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
        "CommandBar/NewRoom",
        "CommandBar/AddExisting",
        "CommandBar/OpenSource",
        "CommandBar/ValidateRoom",
        "CommandBar/BakeRoom",
        "CommandBar/BakeStale",
        "Workspace/CanvasSplit/InspectorPanel/Connections/ConnectionButtons/Connect",
        "Workspace/CanvasSplit/InspectorPanel/Connections/ConnectionButtons/Disconnect",
        "CommandBar/ValidateWorld",
        "CommandBar/BakeWorld",
        "CommandBar/ViewMode3D",
        "StatusBar/ChunkField",
        "StatusBar/ChunkGo",
        "Workspace/RoomListPanel/LayerPanel/LayerTitle",
        "Workspace/RoomListPanel/LayerPanel/LayerRows",
        "Workspace/RoomListPanel/LayerPanel/LayerAdd",
        "Workspace/RoomListPanel/LayerPanel/LayerHint",
    ]:
        if _scene_node_index(state, node_path) < 0:
            failures.append("world editor dock is missing command control: %s" % node_path)
    if int(_scene_node_property(state, "AddExistingDialog", &"access", -1)) != FileDialog.ACCESS_RESOURCES:
        failures.append("Add Existing dialog can return non-res resource paths")


func _assert_world_resource_controls(failures: Array[String]) -> void:
    var packed := load(DOCK_SCENE_PATH) as PackedScene
    var state := packed.get_state()
    for node_path: String in [
        "WorldBar/WorldPicker",
        "WorldBar/NewWorld",
        "WorldBar/SaveWorld",
        "StatusBar/FocusAll",
        "StatusBar/ResetView",
        "StatusBar/ZoomLabel",
        "NewWorldDialog",
    ]:
        if _scene_node_index(state, node_path) < 0:
            failures.append("world editor main screen is missing world control: %s" % node_path)
    if String(_scene_node_property(state, "WorldBar/WorldPicker", &"base_type", "")) != "WorldData":
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
    if not bool(_scene_node_property(state, "CommandBar/AddExisting", &"disabled", false)):
        failures.append("Add Existing is not initially disabled without WorldData")
    if String(_scene_node_property(state, "CommandBar/AddExisting", &"tooltip_text", "")) != "Select or create a WorldData resource first":
        failures.append("Add Existing does not explain its missing WorldData prerequisite")
    if int(_scene_node_property(state, "Workspace/CanvasSplit/LayoutCanvas", &"focus_mode", Control.FOCUS_NONE)) != Control.FOCUS_ALL:
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
    if importer.last_origin != (main.get("canvas") as FakeCanvas).cursor_chunk:
        failures.append("Add Existing did not import at the chunk under the canvas pointer")
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
    main.call("set_world_data", null)
    var guarded: Dictionary = main.call("create_room", "wizard_room", "Wizard Room", "res://scenes/levels/wizard_room.tscn")
    if bool(guarded.get("ok", true)) or (guarded.get("errors", []) as Array).is_empty():
        failures.append("create_room did not require a saved WorldData")
    if FileAccess.file_exists("res://scenes/levels/wizard_room.tscn"):
        failures.append("create_room wrote a scene without a world")
    main.call("new_room")
    if editor.opened_path != "res://scenes/rooms/template/level_template.tscn" or not editor.inherited:
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
    world.set_room_origin_chunk("room_a", Vector2i.ZERO)
    var undo := FakeUndo.new()
    var changed_count := [0]
    world.changed.connect(func() -> void: changed_count[0] += 1)
    dock.call("set_world_data", world)
    dock.call("set_undo_redo_adapter", undo)
    if not dock.call("move_room", "room_a", Vector2i(3, -2)):
        failures.append("world editor move command was rejected")
    if world.call("get_room_origin_chunk", "room_a") != Vector2i(3, -2):
        failures.append("world editor move command did not apply integer chunks")
    if undo.action_name.is_empty() or not undo.undo_call.is_valid():
        failures.append("world editor move command did not register undo/redo")
    else:
        undo.undo_call.call()
        if world.call("get_room_origin_chunk", "room_a") != Vector2i.ZERO:
            failures.append("world editor move undo did not restore the origin")
        undo.do_call.call()
        if world.call("get_room_origin_chunk", "room_a") != Vector2i(3, -2):
            failures.append("world editor move redo did not restore the moved origin")
    if changed_count[0] < 2:
        failures.append("world editor move and undo did not mark WorldData changed")
    dock.free()


func _assert_status_bar_chunk_field(failures: Array[String]) -> void:
    var dock: Control = (load(DOCK_PATH) as Script).new() as Control
    var field := LineEdit.new()
    var canvas := FakeCanvas.new()
    dock.set("chunk_field", field)
    dock.set("canvas", canvas)
    var world: Resource = WORLD_DATA.new()
    world.rooms.assign([_make_room("room_a", [], ["start"])])
    world.set_room_origin_chunk("room_a", Vector2i(2, -3))
    dock.call("set_world_data", world)
    dock.call("select_room", "room_a")
    if field.text != "2,-3":
        failures.append("chunk field did not mirror the selected room origin: %s" % field.text)

    field.text = " 7, -4 "
    dock.call("_on_chunk_go")
    if canvas.focused_chunk != Vector2i(7, -4):
        failures.append("chunk Go did not centre the canvas without a movable room: %s" % str(canvas.focused_chunk))

    field.text = "not a chunk"
    dock.call("_on_chunk_go")
    if not field.text.is_empty():
        failures.append("invalid chunk text was not cleared")

    field.text = "5"
    dock.call("_on_chunk_go")
    if not field.text.is_empty():
        failures.append("incomplete chunk text was not cleared")

    var parsed: Variant = dock.call("parse_chunk_text", "-12, 8")
    if parsed != Vector2i(-12, 8):
        failures.append("chunk parsing rejected negative coordinates: %s" % str(parsed))
    if dock.call("parse_chunk_text", "") != null:
        failures.append("empty chunk text parsed as a chunk")

    field.free()
    canvas.free()
    dock.free()


## The 3D view's layer stack is real world data: the order lives on WorldData and
## the payload the layer draws comes from it.
func _assert_stack_layers(failures: Array[String]) -> void:
    var main := (load(DOCK_PATH) as Script).new() as Control
    var world: Resource = WORLD_DATA.new()
    world.world_id = "main_world"
    world.resource_path = STACK_WORLD_PATH
    world.rooms.assign([_make_room("room_a", [], ["start"])])
    world.set_room_origin_chunk("room_a", Vector2i.ZERO)
    main.call("set_world_data", world)

    if main.call("get_world_stack") != null:
        failures.append("a fresh world already claims a stack resource")
    var alone: Array = main.call("get_stack_worlds")
    if alone.size() != 1 or alone[0] != world:
        failures.append("a world without a stack is not a stack of one: %s" % str(alone))

    # Adding the first layer creates and saves the stack resource next to the world.
    main.call("add_layer", "loop_world")
    var stack: Resource = main.call("get_world_stack")
    if stack == null:
        failures.append("adding a layer did not create a WorldStack resource")
    else:
        if String(stack.resource_path).is_empty() or not FileAccess.file_exists(String(stack.resource_path)):
            failures.append("the created WorldStack was not saved: %s" % String(stack.resource_path))
        if stack.get_layer_count() != 2:
            failures.append("the created WorldStack does not hold both worlds: %d" % stack.get_layer_count())
    _assert_layer_ids(main, ["main_world", "loop_world"], "adding a layer appends it above the edited world", failures)

    main.call("add_layer", "the_world")
    _assert_layer_ids(main, ["main_world", "loop_world", "the_world"], "adding a second layer appends it", failures)
    main.call("move_layer", "the_world", -1)
    _assert_layer_ids(main, ["main_world", "the_world", "loop_world"], "moving a layer down reorders the stack", failures)
    main.call("move_layer", "the_world", 1)
    _assert_layer_ids(main, ["main_world", "loop_world", "the_world"], "moving a layer up reorders the stack", failures)
    main.call("remove_layer", "the_world")
    _assert_layer_ids(main, ["main_world", "loop_world"], "removing a layer drops it", failures)
    main.call("add_layer", "loop_world")
    _assert_layer_ids(main, ["main_world", "loop_world"], "adding a present layer is a no-op", failures)
    main.call("remove_layer", "main_world")
    _assert_layer_ids(main, ["main_world", "loop_world"], "the edited world cannot be removed from its own stack", failures)

    var payload: Dictionary = main.call("get_stack_3d_payload")
    var layers: Array = payload.get("layers", [])
    if layers.size() != 2:
        failures.append("the 3D payload did not contain the stack worlds: %d" % layers.size())
    elif String(layers[0].get("world_id", "")) != "main_world" or String(layers[1].get("world_id", "")) != "loop_world":
        failures.append("the 3D payload layers do not follow the stack order")
    if not payload.has("links") or not payload.has("dangling_count") or not payload.has("dangling_links"):
        failures.append("the 3D payload is missing its link report")

    var stacked := main.call("get_world_stack") as Resource
    if stacked != null:
        stacked.layers.clear()
        stacked.normalize()
        var repaired: Array = main.call("get_stack_worlds")
        if repaired.is_empty() or repaired[0] != world:
            failures.append("a stack that lost its world did not get it back")
    main.free()
    if FileAccess.file_exists(STACK_WORLD_PATH):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(STACK_WORLD_PATH))
    if FileAccess.file_exists(STACK_PATH):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(STACK_PATH))


## The New World dialog writes a WorldData resource but never touches
## world_catalog.tres. The stack menu must still offer that world, otherwise a
## freshly created world can never be layered in the 3D view.
func _assert_stack_accepts_uncatalogued_world(failures: Array[String]) -> void:
    var main := (load(DOCK_PATH) as Script).new() as Control
    main.set("stack_world_directory", STACK_SCAN_DIRECTORY)
    var world: Resource = WORLD_DATA.new()
    world.world_id = "main_world"
    world.resource_path = STACK_WORLD_PATH
    world.rooms.assign([_make_room("room_a", [], ["start"])])
    world.set_room_origin_chunk("room_a", Vector2i.ZERO)
    var extra: Resource = WORLD_DATA.new()
    extra.world_id = "outside_catalog_world"
    extra.display_name = "Outside Catalog"
    extra.rooms.assign([_make_room("room_b", [], ["start"])])
    extra.set_room_origin_chunk("room_b", Vector2i.ZERO)
    if ResourceSaver.save(extra, STACK_EXTRA_WORLD_PATH) != OK:
        failures.append("could not write the uncatalogued world fixture")
    main.call("set_world_data", world)
    var candidates: Array = main.call("get_stack_candidate_worlds")
    var candidate_ids: Array[String] = []
    for value: Variant in candidates:
        candidate_ids.append(String((value as Resource).get("world_id")))
    if not candidate_ids.has("outside_catalog_world"):
        failures.append("the stack candidates ignored a world outside the catalog: %s" % str(candidate_ids))
    main.call("add_layer", "outside_catalog_world")
    _assert_layer_ids(
        main,
        ["main_world", "outside_catalog_world"],
        "a world outside the world catalog can join the stack",
        failures
    )
    main.free()
    if FileAccess.file_exists(STACK_EXTRA_WORLD_PATH):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(STACK_EXTRA_WORLD_PATH))
    if FileAccess.file_exists(STACK_PATH):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(STACK_PATH))


## A world must not save a reference to its own stack: the stack references the
## world back, and Godot's text loader cannot resolve the cycle, so both files
## fail to load and the catalog (and the world-select screen) goes down with them.
## The stack lives next to the world as `<world>_stack.tres` instead.
func _assert_stacked_world_reloads(failures: Array[String]) -> void:
    var main := (load(DOCK_PATH) as Script).new() as Control
    var service: Object = WORLD_RESOURCE_SERVICE.new()
    service.call("set_allow_user_paths", true)
    main.call("set_world_resource_service_adapter", service)
    var world: Resource = WORLD_DATA.new()
    world.world_id = "stack_reload_world"
    world.resource_path = STACK_WORLD_PATH
    world.rooms.assign([_make_room("room_a", [], ["start"])])
    main.call("set_world_data", world)
    main.call("add_layer", "loop_world")
    if main.call("get_world_stack") == null:
        failures.append("a stacked world lost its stack")
    var saved: Dictionary = main.call("save_world")
    if not bool(saved.get("ok", false)):
        failures.append("could not save the stacked world: %s" % str(saved.get("errors", [])))
    var reloaded := ResourceLoader.load(
        STACK_WORLD_PATH, "", ResourceLoader.CACHE_MODE_IGNORE
    ) as WorldData
    if reloaded == null:
        failures.append("a world that owns a stack could not be reloaded")
    else:
        main.call("set_world_data", reloaded)
        var found := main.call("get_world_stack") as Resource
        if found == null:
            failures.append("the stack was not found next to its world: %s" % STACK_PATH)
        elif found.get_world_ids() != (["stack_reload_world", "loop_world"] as Array):
            failures.append("the reloaded stack lost its layers: %s" % str(found.get_world_ids()))
    main.free()
    if FileAccess.file_exists(STACK_WORLD_PATH):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(STACK_WORLD_PATH))
    if FileAccess.file_exists(STACK_PATH):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(STACK_PATH))


## Focus All / Reset View act on whatever view is in front. The 3D stack replaces
## the flat canvas, so routing them to the hidden canvas does nothing visible.
func _assert_view_commands_route_to_the_3d_view(failures: Array[String]) -> void:
    var main := (load(DOCK_PATH) as Script).new() as Control
    var canvas := FakeViewCommands.new()
    var stack_view := FakeViewCommands.new()
    main.set("canvas", canvas)
    main.set("_stack_3d_view", stack_view)
    main.set("_view_3d", true)
    main.call("focus_all")
    main.call("reset_view")
    if not canvas.calls.is_empty():
        failures.append("3D view commands still reached the hidden 2D canvas: %s" % str(canvas.calls))
    if stack_view.calls != (["focus_stack", "reset_view"] as Array[String]):
        failures.append("3D view commands did not reach the stack view: %s" % str(stack_view.calls))
    main.set("_view_3d", false)
    main.call("focus_all")
    main.call("reset_view")
    if canvas.calls != (["focus_all", "reset_view"] as Array[String]):
        failures.append("2D view commands did not reach the canvas: %s" % str(canvas.calls))
    canvas.free()
    stack_view.free()
    main.free()


func _assert_layer_ids(main: Control, expected: Array[String], label: String, failures: Array[String]) -> void:
    var ids: Array[String] = []
    for value: Variant in main.call("get_stack_worlds"):
        ids.append(String((value as Resource).get("world_id")))
    if ids != expected:
        failures.append("%s: expected %s, got %s" % [label, str(expected), str(ids)])


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
    world.rooms.assign([old_room])
    world.set_room_origin_chunk("room_a", Vector2i(5, -1))
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
            if world.call("get_room_origin_chunk", "room_a") != Vector2i(5, -1):
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
    dock.call("_add_existing_source", "res://scenes/rooms/source/level_0.tscn")
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
