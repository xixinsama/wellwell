@tool
class_name WorldEditorMain
extends VBoxContainer

const WORLD_LAYOUT_MODEL := preload("res://addons/world_editor/authoring/world/world_layout_model.gd")
const WORLD_BAKER := preload("res://addons/world_editor/authoring/world/world_baker.gd")
const ROOM_BAKER := preload("res://addons/world_editor/authoring/room/room_baker.gd")
const WORLD_RESOURCE_SERVICE := preload("res://addons/world_editor/authoring/world/world_resource_service.gd")
const WORLD_ROOM_IMPORTER := preload("res://addons/world_editor/authoring/world/world_room_importer.gd")
const ROOM_PARTITION := preload("res://addons/world_editor/authoring/world/room_partition_operations.gd")
const PARTITION_WORKFLOW := preload("res://addons/world_editor/authoring/world/room_partition_workflow.gd")
const TERRAIN_PATCH_DIR := "res://resources/rooms/terrain_patches/"
const CONNECTION_DATA := preload("res://addons/platformer_kit/world/data/room_connection_data.gd")
const TEMPLATE_SCENE_SETTING := "world_editor/room_template_scene"
const ROOM_STATUS := preload("res://addons/world_editor/authoring/world/room_status_service.gd")
const ROOM_ANNOTATIONS := preload("res://addons/world_editor/authoring/world/room_annotation_service.gd")
const ROOM_SCENE_WRITER := preload("res://addons/world_editor/authoring/world/room_scene_writer.gd")
const ROOM_BAKE_PATHS := preload("res://addons/world_editor/authoring/room/room_bake_paths.gd")
## The 3D stack view is loaded by path so the editor keeps working (flat 2D only)
## when the script is absent, e.g. in a stripped checkout.
const STACK_3D_PATH := "res://addons/world_editor/world_stack_3d_layer.gd"
## One world unit in the 3D stack view is one chunk of this size.
const CHUNK_PIXELS_F := Vector2(320.0, 180.0)
const WORLD_STACK_MODEL := preload("res://addons/world_editor/authoring/world/world_stack_model.gd")
## Catalog the stacked-world view lists; missing/unreadable degrades to no rows.
const WORLD_CATALOG_PATH := "res://resources/worlds/world_catalog.tres"
## Folder scanned for worlds that exist on disk but are not in the catalog yet
## (New World writes exactly that). Overridable for forks with their own layout.
const WORLD_DIRECTORY := "res://resources/worlds/"
var stack_world_directory := WORLD_DIRECTORY

var world_data: WorldData
var selected_room_id := ""
var selected_room_ids: Array[String] = []
var room_statuses: Dictionary = {}
var room_status_messages: Dictionary = {}
var _model: RefCounted = WORLD_LAYOUT_MODEL.new()
var _room_baker: Object = ROOM_BAKER.new()
var _world_resources: Object = WORLD_RESOURCE_SERVICE.new()
var _world_room_importer: Object = WORLD_ROOM_IMPORTER.new()
var _partition: Object = ROOM_PARTITION.new()
var _workflow: Object = PARTITION_WORKFLOW.new()
var _split_dialog: ConfirmationDialog
var _split_axis: OptionButton
var _split_index: SpinBox
var _split_room_id := ""
var _undo_redo: Object
var _editor_interface: Object
var _transaction_busy := false
var _status := ROOM_STATUS.new()
var _annotations_service := ROOM_ANNOTATIONS.new()
var _annotations: Dictionary = {}
var _session_issues: Array[Dictionary] = []
var room_status_raw_messages: Dictionary = {}
var _output_signature := ""
var _world_report: Dictionary = {}
var _new_room_dialog: ConfirmationDialog
var _wizard_id: LineEdit
var _wizard_name: LineEdit
var _wizard_path: LineEdit
var _auto_path := ""
var _view_3d := false
var _stack_3d_view: Control
var _stack_model := WORLD_STACK_MODEL.new()
var _stack_3d_payload: Dictionary = {}
## Session cache for the edited world's stack; see [method get_world_stack].
var _stack_cache: WorldStack
var _stack_cache_path := ""
## Layer ids shown while the world has no saved order yet; only written to the
## resource when the author edits the stack.
var _stack_default_order: Array[String] = []

@onready var canvas: Control = %LayoutCanvas
@onready var status_label: Label = %Status
@onready var chunk_field: LineEdit = %ChunkField
@onready var chunk_go: Button = %ChunkGo
@onready var layer_panel: VBoxContainer = %LayerPanel
@onready var layer_title: Label = %LayerTitle
@onready var layer_rows: VBoxContainer = %LayerRows
@onready var layer_add: Button = %LayerAdd
@onready var layer_hint: Label = %LayerHint
@onready var source_entrance: OptionButton = %SourceEntrance
@onready var target_room: OptionButton = %TargetRoom
@onready var target_spawn: OptionButton = %TargetSpawn
@onready var world_picker: Node = %WorldPicker
@onready var room_list: WorldRoomList = %RoomList
@onready var room_search: LineEdit = %RoomSearch
@onready var room_count: Label = %RoomCount
@onready var inspector: WorldRoomInspector = %InspectorPanel
@onready var selection_label: Label = %SelectionLabel
@onready var room_list_panel: VBoxContainer = %RoomListPanel
@onready var inspector_panel: VBoxContainer = %InspectorPanel
@onready var view_mode_3d: CheckButton = %ViewMode3D


func _ready() -> void:
    %NewWorld.pressed.connect(new_world)
    %SaveWorld.pressed.connect(save_world)
    if is_instance_valid(world_picker) and world_picker.has_signal("resource_changed"):
        world_picker.connect("resource_changed", _on_world_resource_changed)
    %NewWorldDialog.file_selected.connect(_on_new_world_path_selected)
    %NewRoom.pressed.connect(create_room_wizard)
    %BakeStale.pressed.connect(bake_stale_rooms)
    %AddExisting.pressed.connect(add_existing)
    %DrawRoom.toggled.connect(_on_draw_room_toggled)
    %MergeRooms.pressed.connect(merge_selected_rooms)
    %SplitRoom.pressed.connect(split_selected_room)
    if canvas.has_signal("room_draw_requested"):
        canvas.connect("room_draw_requested", create_room_from_rect)
    %ValidateWorld.pressed.connect(validate_world)
    %BakeWorld.pressed.connect(bake_world)
    %OpenSource.pressed.connect(open_selected_source)
    %ValidateRoom.pressed.connect(validate_selected_room)
    %BakeRoom.pressed.connect(bake_selected_room)
    %Connect.pressed.connect(connect_selected)
    %Disconnect.pressed.connect(disconnect_selected)
    %FocusAll.pressed.connect(focus_all)
    %ResetView.pressed.connect(reset_view)
    %AddExistingDialog.file_selected.connect(_add_existing_source)
    target_room.item_selected.connect(_on_target_room_selected)
    %RoomSearch.text_changed.connect(_on_search_changed)
    room_list.selection_changed.connect(_on_list_selection_changed)
    room_list.room_activated.connect(open_source_room)
    room_list.action_requested.connect(_on_room_action)
    inspector.action_requested.connect(_on_room_action)
    %RoomsToggle.toggled.connect(func(on: bool) -> void: room_list_panel.visible = on)
    %InspectorToggle.toggled.connect(func(on: bool) -> void: inspector_panel.visible = on)
    %EditTerrain.pressed.connect(edit_terrain)
    %SyncTerrain.pressed.connect(sync_terrain)
    if is_instance_valid(view_mode_3d):
        view_mode_3d.toggled.connect(set_view_mode_3d)
    chunk_go.pressed.connect(_on_chunk_go)
    chunk_field.text_submitted.connect(func(_text: String) -> void: _on_chunk_go())
    if is_instance_valid(layer_add):
        layer_add.pressed.connect(_on_layer_add_pressed)
    if canvas.has_signal("selection_changed"):
        canvas.connect("selection_changed", _on_canvas_selection_changed)
    if canvas.has_signal("delete_requested"):
        canvas.connect("delete_requested", delete_selected_rooms)
    canvas.call("set_main_screen", self)
    _localize_ui()
    _refresh()


func set_world_data(value: WorldData, preserve_selection := false) -> void:
    world_data = value
    _stack_default_order.clear()
    _stack_cache = null
    _stack_cache_path = ""
    if not preserve_selection or world_data == null or not world_data.has_room(selected_room_id):
        selected_room_id = ""
    selected_room_ids.clear()
    if not selected_room_id.is_empty():
        selected_room_ids.append(selected_room_id)
    _sync_world_picker(world_data)
    _session_issues.clear()
    _refresh()


func set_undo_redo_adapter(value: Object) -> void:
    _undo_redo = value


func set_editor_interface(value: Object) -> void:
    _editor_interface = value


func set_room_baker_adapter(value: Object) -> void:
    _room_baker = value
    if _world_room_importer.has_method("set_room_baker_adapter"):
        _world_room_importer.call("set_room_baker_adapter", value)


func set_world_resource_service_adapter(value: Object) -> void:
    _world_resources = value
    if _world_room_importer.has_method("set_world_resources_adapter"):
        _world_room_importer.call("set_world_resources_adapter", value)


func set_world_room_importer_adapter(value: Object) -> void:
    _world_room_importer = value


func select_room(room_id: String) -> void:
    set_selection([room_id] if not room_id.is_empty() else [], room_id)


## Replace the whole selection (list, canvas, inspector) in one step.
func set_selection(room_ids: Array, primary: String) -> void:
    var valid: Array[String] = []
    if world_data != null:
        for value: Variant in room_ids:
            var id := String(value)
            if world_data.has_room(id) and not valid.has(id):
                valid.append(id)
    selected_room_ids = valid
    selected_room_id = primary if valid.has(primary) else ("" if valid.is_empty() else valid[0])
    if is_instance_valid(canvas) and canvas.has_method("set_selection"):
        canvas.call("set_selection", selected_room_ids, selected_room_id)
    if is_instance_valid(room_list):
        room_list.call("set_selection", selected_room_ids, selected_room_id)
    _refresh_inspector()
    _refresh_status_bar()
    _refresh_command_state()
    _refresh_layer_panel()


func move_room(room_id: String, origin_chunk: Vector2i) -> bool:
    if world_data == null or _undo_redo == null:
        return false
    var room: Resource = world_data.get_room(room_id)
    var current_origin := Vector2i.ZERO if room == null else world_data.get_room_origin_chunk(room_id)
    if room == null or current_origin == origin_chunk:
        return room != null
    _undo_redo.create_action("Move Room")
    _undo_redo.add_do_method(self, "_apply_move", room_id, origin_chunk)
    _undo_redo.add_undo_method(self, "_apply_move", room_id, current_origin)
    _undo_redo.commit_action()
    return true


func add_room(room: RoomData) -> bool:
    if world_data == null or _undo_redo == null or room == null:
        return false
    var probe := world_data.duplicate(true) as WorldData
    if not bool(_model.add_room(probe, room).get("ok", false)):
        return false
    _undo_redo.create_action("Add Room")
    _undo_redo.add_do_method(self, "_apply_add", room)
    _undo_redo.add_undo_method(self, "_apply_remove", room.room_id)
    _undo_redo.commit_action()
    return true


func remove_room(room_id: String) -> bool:
    if world_data == null or _undo_redo == null:
        return false
    var room: Resource = world_data.get_room(room_id)
    if room == null:
        return false
    var previous_state: Dictionary = _model.capture_world_state(world_data)
    _undo_redo.create_action("Remove Room Reference")
    _undo_redo.add_do_method(self, "_apply_remove", room_id)
    _undo_redo.add_undo_method(self, "_restore_world_state", previous_state)
    _undo_redo.commit_action()
    return true


func connect_rooms(connection: RoomConnectionData) -> bool:
    if world_data == null or _undo_redo == null or connection == null:
        return false
    var probe := world_data.duplicate(true) as WorldData
    if not bool(_model.connect_rooms(probe, connection).get("ok", false)):
        return false
    _undo_redo.create_action("Connect Rooms")
    _undo_redo.add_do_method(self, "_apply_connect", connection)
    _undo_redo.add_undo_method(self, "_apply_disconnect", connection)
    _undo_redo.commit_action()
    return true


func disconnect_rooms(from_room_id: String, from_entrance_id: String) -> bool:
    if world_data == null or _undo_redo == null:
        return false
    var connection := world_data.get_connection(from_room_id, from_entrance_id)
    if connection == null:
        return false
    _undo_redo.create_action("Disconnect Rooms")
    _undo_redo.add_do_method(self, "_apply_disconnect", connection)
    _undo_redo.add_undo_method(self, "_apply_connect", connection)
    _undo_redo.commit_action()
    return true


func new_room() -> void:
    if _editor_interface == null:
        return
    var template_path := String(ProjectSettings.get_setting(TEMPLATE_SCENE_SETTING, ""))
    if template_path.is_empty() or not ResourceLoader.exists(template_path, "PackedScene"):
        _show_result(_failure("Room template is not configured: %s" % TEMPLATE_SCENE_SETTING))
        return
    _editor_interface.open_scene_from_path(template_path, true)


func new_world() -> void:
    %NewWorldDialog.popup_centered_ratio(0.7)


func _on_draw_room_toggled(enabled: bool) -> void:
    if enabled and (world_data == null or world_data.resource_path.is_empty()):
        %DrawRoom.set_pressed_no_signal(false)
        _show_result(_failure("Select or create a saved WorldData resource first"))
        return
    if is_instance_valid(canvas):
        canvas.call("set_room_draw_mode", enabled)


## Creates a new room from a drawn chunk rectangle: an entities-only source scene
## from the template, a placement, and a first bake sliced from the world terrain.
func create_room_from_rect(chunk_rect: Rect2i) -> Dictionary:
    if world_data == null or world_data.resource_path.is_empty():
        return _fail_and_show("Select or create a saved WorldData resource first")
    if chunk_rect.size.x <= 0 or chunk_rect.size.y <= 0:
        return _fail_and_show("Drag a room rectangle first")
    var overlap := _overlapping_room_for(chunk_rect)
    if not overlap.is_empty():
        return _fail_and_show("Room rectangle overlaps '%s'" % overlap)
    var terrain_path := world_data.get_terrain_scene_path()
    if terrain_path.is_empty() or not FileAccess.file_exists(terrain_path):
        var create_error := _create_world_terrain(terrain_path)
        if not create_error.is_empty():
            return _fail_and_show(create_error)
    var room_id := _unique_room_id(chunk_rect)
    var source_dir := "res://scenes/levels/%s/" % world_data.world_id
    var source_path := source_dir + room_id + ".tscn"
    var source := _new_room_source(room_id, chunk_rect)
    if source == null:
        return _fail_and_show("Could not instantiate the room template")
    var save_error := _save_new_room_source(source, source_path, source_dir)
    if not save_error.is_empty():
        source.free()
        return _fail_and_show(save_error)
    _set_transaction_busy(true)
    var result: Dictionary = _world_room_importer.call(
        "import_room", world_data, source, source_path, chunk_rect.position
    )
    source.free()
    _set_transaction_busy(false)
    if bool(result.get("ok", false)):
        var imported_world := result.get("world") as WorldData
        var imported_room := result.get("room") as RoomData
        if imported_world == null or imported_room == null:
            result = _failure("Room importer returned incomplete saved resources")
        else:
            set_world_data(imported_world)
            select_room(imported_room.room_id)
            if is_instance_valid(canvas):
                canvas.call("focus_room", imported_room.room_id)
            _register_import_history(result)
    %DrawRoom.set_pressed_no_signal(false)
    if is_instance_valid(canvas):
        canvas.call("set_room_draw_mode", false)
    _show_result(result)
    return result


func _show_dict(result: Dictionary) -> Dictionary:
    _show_result(result)
    return result


func _fail_and_show(message: String) -> Dictionary:
    var result := _failure(message)
    _show_result(result)
    return result


func _new_room_source(room_id: String, chunk_rect: Rect2i) -> Node:
    var template_path := String(ProjectSettings.get_setting(TEMPLATE_SCENE_SETTING, ""))
    if template_path.is_empty() or not ResourceLoader.exists(template_path, "PackedScene"):
        return null
    var packed := ResourceLoader.load(template_path, "PackedScene") as PackedScene
    if packed == null:
        return null
    var source := packed.instantiate()
    source.set("room_id", room_id)
    source.set("display_name", room_id)
    source.set("room_size_chunks", chunk_rect.size)
    source.set("world_origin_chunk", chunk_rect.position)
    source.set("world_origin_known", true)
    var spawn := source.get_node_or_null("RoomContent/Entities/StartSpawn") as Node2D
    if spawn != null:
        var cell_rect := RoomGrid.get_room_cell_rect(chunk_rect.position, chunk_rect.size)
        spawn.position = Vector2(cell_rect.size * RoomGrid.DEFAULT_CELL_SIZE) * 0.5
    return source


func _save_new_room_source(source: Node, path: String, directory: String) -> String:
    var dir_error := DirAccess.make_dir_recursive_absolute(
        ProjectSettings.globalize_path(directory)
    )
    if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
        return "Could not create %s" % directory
    var scene := PackedScene.new()
    if scene.pack(source) != OK:
        return "Could not pack the new room scene"
    if ResourceSaver.save(scene, path) != OK:
        return "Could not save %s" % path
    return ""


func _overlapping_room_for(chunk_rect: Rect2i) -> String:
    for room_id: String in world_data.get_room_ids():
        var room := world_data.get_room(room_id)
        if room == null:
            continue
        var other := Rect2i(world_data.get_room_origin_chunk(room_id), room.room_size_chunks)
        if other.intersects(chunk_rect):
            return room_id
    return ""


func _unique_room_id(chunk_rect: Rect2i) -> String:
    var base := "room_%d_%d" % [chunk_rect.position.x, chunk_rect.position.y]
    var candidate := base
    var index := 2
    while world_data.has_room(candidate) or FileAccess.file_exists(
        "res://scenes/levels/%s/%s.tscn" % [world_data.world_id, candidate]
    ):
        candidate = "%s_%d" % [base, index]
        index += 1
    return candidate


# --- World terrain ------------------------------------------------------------

## Opens the world's single terrain scene in the normal Godot editor. The scene
## contains only terrain layers, so the native TileMap palette, autotiling and
## undo all work there; save it, then press Sync Terrain.
func edit_terrain() -> void:
    if world_data == null or world_data.world_id.is_empty():
        _show_result(_failure("Select or create a saved WorldData resource first"))
        return
    var path := world_data.get_terrain_scene_path()
    if path.is_empty():
        _show_result(_failure("World has no terrain scene path"))
        return
    if not FileAccess.file_exists(path):
        var create_error := _create_world_terrain(path)
        if not create_error.is_empty():
            _show_result(_failure(create_error))
            return
        if is_instance_valid(canvas):
            canvas.call("sync_preview")
        _show_result({"ok": true, "errors": [], "warnings": ["Created %s" % path]})
    if _editor_interface != null and _editor_interface.has_method("open_scene_from_path"):
        _editor_interface.open_scene_from_path(path)


func _create_world_terrain(path: String) -> String:
    var template_path := "res://scenes/worlds/terrain_template.tscn"
    if not ResourceLoader.exists(template_path, "PackedScene"):
        return "Terrain template is missing: %s" % template_path
    var packed := ResourceLoader.load(template_path, "PackedScene") as PackedScene
    if packed == null:
        return "Could not load the terrain template"
    var instance := packed.instantiate()
    if instance == null:
        return "Could not instantiate the terrain template"
    var scene := PackedScene.new()
    var pack_error := scene.pack(instance)
    instance.free()
    if pack_error != OK:
        return "Could not pack the terrain template"
    var dir_error := DirAccess.make_dir_recursive_absolute(
        ProjectSettings.globalize_path(path.get_base_dir())
    )
    if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
        return "Could not create %s" % path.get_base_dir()
    if ResourceSaver.save(scene, path) != OK:
        return "Could not save %s" % path
    return ""


## Re-slices every room from the saved world terrain scene and re-bakes it, so
## the runtime, the world view and the room preview all show the same terrain.
func sync_terrain() -> Dictionary:
    if world_data == null:
        return _show_terrain_result(false, ["Select a WorldData first"], [])
    var terrain_path := world_data.get_terrain_scene_path()
    if terrain_path.is_empty() or not FileAccess.file_exists(terrain_path):
        return _show_terrain_result(false, ["Edit and save the world terrain scene first"], [])
    var room_ids: Array[String] = []
    room_ids.assign(world_data.get_room_ids())
    var errors: Array[String] = []
    var warnings: Array[String] = []
    for room_id: String in room_ids:
        var result := _bake_room(room_id)
        for warning: Variant in result.get("warnings", []):
            warnings.append(String(warning))
        if not bool(result.get("ok", false)):
            for error: Variant in result.get("errors", []):
                errors.append(String(error))
    if is_instance_valid(canvas):
        canvas.call("sync_preview")
    return _show_terrain_result(errors.is_empty(), errors, warnings)


func _show_terrain_result(ok: bool, errors: Array[String], warnings: Array[String]) -> Dictionary:
    var result := {"ok": ok, "errors": errors, "warnings": warnings}
    _show_result(result)
    return result


func save_world() -> Dictionary:
    if world_data == null:
        var failure := _failure("No WorldData selected")
        _show_result(failure)
        return failure
    var result: Dictionary = _world_resources.call("save_world", world_data)
    if bool(result.get("ok", false)):
        set_world_data(result.get("world") as WorldData, true)
    _show_result(result)
    return result


func focus_all() -> void:
    if _view_3d and _stack_3d_view != null and is_instance_valid(_stack_3d_view):
        _stack_3d_view.call("focus_stack")
        return
    canvas.call("focus_all")


func reset_view() -> void:
    if _view_3d and _stack_3d_view != null and is_instance_valid(_stack_3d_view):
        _stack_3d_view.call("reset_view")
        return
    canvas.call("reset_view")


func update_zoom_label(zoom: float) -> void:
    if is_node_ready():
        %ZoomLabel.text = "%d%%" % roundi(zoom * 100.0)


func add_existing() -> void:
    var state := get_command_state()
    if bool(state.get("add_existing_disabled", true)):
        _show_result(_failure(String(state.get("add_existing_tooltip", "Add Existing is unavailable"))))
        return
    %AddExistingDialog.popup_centered_ratio(0.7)


func remove_selected_room() -> void:
    if not selected_room_id.is_empty():
        remove_room(selected_room_id)


func connect_selected() -> void:
    var from_entrance_id := _selected_option_value(source_entrance)
    var to_room_id := _selected_option_value(target_room)
    var to_spawn_id := _selected_option_value(target_spawn)
    if selected_room_id.is_empty() or from_entrance_id.is_empty() or to_room_id.is_empty() or to_spawn_id.is_empty():
        _show_result({"ok": false, "errors": ["Select a source entrance and target spawn"], "warnings": []})
        return
    var connection := CONNECTION_DATA.new() as RoomConnectionData
    connection.from_room_id = selected_room_id
    connection.from_entrance_id = from_entrance_id
    connection.to_room_id = to_room_id
    connection.to_spawn_id = to_spawn_id
    connect_rooms(connection)


func disconnect_selected() -> void:
    var entrance_id := _selected_option_value(source_entrance)
    if not selected_room_id.is_empty() and not entrance_id.is_empty():
        disconnect_rooms(selected_room_id, entrance_id)


func validate_world() -> Dictionary:
    var result: Dictionary = _model.validate_world(world_data) if world_data != null else {"ok": false, "errors": ["No WorldData selected"], "warnings": []}
    _world_report = result
    _show_result(result)
    _refresh()
    return result


func bake_world() -> Dictionary:
    var result: Dictionary = WORLD_BAKER.new().bake(world_data) if world_data != null else {"ok": false, "errors": [WorldEditorLocalization.t("WE_NO_WORLD_DATA")], "warnings": []}
    _show_result(result)
    return result


func validate_selected_room() -> Dictionary:
    if selected_room_ids.size() > 1:
        _validate_selection()
        return {"ok": true, "errors": [], "warnings": []}
    return _validate_room(selected_room_id)


func _validate_room(room_id: String) -> Dictionary:
    var root := _instantiate_room_source(room_id)
    if root == null:
        var failure := {"ok": false, "errors": ["No room source selected"], "warnings": []}
        _show_result(failure)
        return failure
    var result: Dictionary = _room_baker.call("validate", root)
    root.free()
    if bool(result.get("ok", false)):
        _remove_session_issues(room_id)
    else:
        _add_session_issue(room_id, _first_error(result, "Validation failed"))
    _show_result(result)
    _refresh()
    return result


func bake_selected_room() -> Dictionary:
    if selected_room_ids.size() > 1:
        _bake_selection()
        return {"ok": true, "errors": [], "warnings": []}
    return _bake_room(selected_room_id)


func _bake_room(room_id: String) -> Dictionary:
    var room: Resource = null if world_data == null else world_data.get_room(room_id)
    var root := _instantiate_room_source(room_id)
    if room == null or root == null:
        var failure := {"ok": false, "errors": ["No room source selected"], "warnings": []}
        _show_result(failure)
        return failure
    var result: Dictionary = _room_baker.call(
        "bake",
        root,
        room.source_scene_path,
        world_data.get_room_origin_chunk(room_id),
        world_data.get_terrain_scene_path()
    )
    root.free()
    if bool(result.get("ok", false)):
        var outputs: Dictionary = result.get("outputs", {})
        var baked_room := ResourceLoader.load(
            String(outputs.get("room_resource_path", "")),
            "RoomData",
            ResourceLoader.CACHE_MODE_IGNORE
        ) as RoomData
        if baked_room == null or not sync_room_resource(room_id, baked_room):
            result = {"ok": false, "errors": ["Baked RoomData could not be synchronized"], "warnings": result.get("warnings", [])}
    if bool(result.get("ok", false)):
        _status.clear_bake_failure(room_id)
        _remove_session_issues(room_id)
    else:
        var message := _first_error(result, "Bake failed")
        _status.mark_bake_failure(room_id, message)
        _add_session_issue(room_id, message)
    _show_result(result)
    _refresh()
    return result


func _bake_selection() -> void:
    for room_id: String in selected_room_ids.duplicate():
        _bake_room(room_id)


# --- Merge / split rooms ------------------------------------------------------

## Merges the selected rooms into one new room, all new ids. See
## [RoomPartitionWorkflow]: the union must be a rectangle and the world terrain is
## never modified.
func merge_selected_rooms() -> Dictionary:
    var ids: Array[String] = []
    for value: Variant in selected_room_ids:
        var room_id := String(value)
        if world_data != null and world_data.has_room(room_id):
            ids.append(room_id)
    if ids.size() < 2:
        return _fail_and_show("Select at least two rooms")
    var union_result: Dictionary = _partition.call("merge_rect", world_data, ids)
    if not bool(union_result.get("ok", false)):
        return _fail_and_show(String(union_result.get("error", "invalid selection")))
    var rect: Rect2i = union_result["rect"]
    var new_id := _unique_partition_id("merged_%d_%d" % [rect.position.x, rect.position.y])
    var result: Dictionary = _workflow.call(
        "merge", world_data, ids, new_id, _workflow.call("source_path_for", world_data, new_id)
    )
    return _apply_partition_result(result, "merge")


## Splits the selected room at a chunk boundary the author picks (middle by
## default). The dialog offers the axis and the cut position.
func split_selected_room() -> Dictionary:
    if selected_room_ids.size() != 1:
        return _fail_and_show("Select exactly one room to split")
    var room_id := selected_room_ids[0]
    var room := null if world_data == null else world_data.get_room(room_id)
    if room == null:
        return _fail_and_show("Select exactly one room to split")
    if room.room_size_chunks.x < 2 and room.room_size_chunks.y < 2:
        return _fail_and_show(
            "This room is one chunk on both axes; it cannot be split on a chunk boundary"
        )
    var dialog := _ensure_split_dialog()
    _populate_split_dialog(room_id, room)
    dialog.popup_centered(Vector2i(320, 150))
    return {"ok": true, "errors": [], "warnings": []}


func _ensure_split_dialog() -> ConfirmationDialog:
    if is_instance_valid(_split_dialog):
        return _split_dialog
    _split_dialog = ConfirmationDialog.new()
    _split_dialog.title = "Split Room"
    _split_dialog.ok_button_text = "Split"
    add_child(_split_dialog)
    var grid := GridContainer.new()
    grid.columns = 2
    _split_dialog.add_child(grid)
    grid.add_child(_make_label("Direction"))
    _split_axis = OptionButton.new()
    _split_axis.add_item("Horizontal cut (left / right)", 0)
    _split_axis.add_item("Vertical cut (top / bottom)", 1)
    _split_axis.item_selected.connect(_on_split_axis_selected)
    grid.add_child(_split_axis)
    grid.add_child(_make_label("Cut after chunk"))
    _split_index = SpinBox.new()
    _split_index.min_value = 1
    _split_index.step = 1
    grid.add_child(_split_index)
    _split_dialog.confirmed.connect(_on_split_confirmed)
    return _split_dialog


func _populate_split_dialog(room_id: String, room: RoomData) -> void:
    _split_room_id = room_id
    var horizontal := room.room_size_chunks.x > 1
    _split_axis.select(0 if horizontal else 1)
    _split_axis.set_item_disabled(0, room.room_size_chunks.x < 2)
    _split_axis.set_item_disabled(1, room.room_size_chunks.y < 2)
    _update_split_index_range(room, horizontal)


func _update_split_index_range(room: RoomData, horizontal: bool) -> void:
    var extent := room.room_size_chunks.x if horizontal else room.room_size_chunks.y
    _split_index.max_value = maxi(1, extent - 1)
    _split_index.value = maxi(1, int(extent / 2))


func _on_split_axis_selected(_index: int) -> void:
    if world_data == null:
        return
    var room := world_data.get_room(_split_room_id)
    if room != null:
        _update_split_index_range(room, _split_axis.selected == 0)


func _on_split_confirmed() -> void:
    var axis := "x" if _split_axis.selected == 0 else "y"
    _apply_split(_split_room_id, axis, int(_split_index.value))


func _apply_split(room_id: String, axis: String, index: int) -> Dictionary:
    var room := null if world_data == null else world_data.get_room(room_id)
    if room == null:
        return _fail_and_show("Select exactly one room to split")
    var new_ids: Array[String] = [
        _unique_partition_id(room_id + "_a"),
        _unique_partition_id(room_id + "_b"),
    ]
    var paths: Array[String] = []
    for new_id: String in new_ids:
        paths.append(String(_workflow.call("source_path_for", world_data, new_id)))
    var result: Dictionary = _workflow.call("split", world_data, room_id, axis, index, new_ids, paths)
    return _apply_partition_result(result, "split")


func _make_label(text: String) -> Label:
    var label := Label.new()
    label.text = text
    return label


func _apply_partition_result(result: Dictionary, action: String) -> Dictionary:
    if not bool(result.get("ok", false)):
        return _show_dict(result)
    var new_world := result.get("world") as WorldData
    if new_world == null:
        return _fail_and_show("Partition %s returned no world" % action)
    set_world_data(new_world)
    var new_ids: Array = result.get("new_room_ids", [])
    if not new_ids.is_empty():
        select_room(String(new_ids[0]))
        if is_instance_valid(canvas):
            canvas.call("focus_room", String(new_ids[0]))
    _refresh()
    return _show_dict(result)


func _unique_partition_id(base: String) -> String:
    var candidate := base
    var index := 2
    while world_data.has_room(candidate) or FileAccess.file_exists(
        String(_workflow.call("source_path_for", world_data, candidate))
    ):
        candidate = "%s_%d" % [base, index]
        index += 1
    return candidate

func _validate_selection() -> void:
    for room_id: String in selected_room_ids.duplicate():
        _validate_room(room_id)


func _first_error(result: Dictionary, fallback: String) -> String:
    var errors: Array = result.get("errors", [])
    return fallback if errors.is_empty() else String(errors[0])


func sync_room_resource(room_id: String, baked_room: RoomData) -> bool:
    if world_data == null or baked_room == null:
        return false
    var result: Dictionary = _model.replace_room(world_data, room_id, baked_room)
    _mark_changed(result)
    if bool(result.get("ok", false)) and is_instance_valid(canvas):
        canvas.call("refresh_preview_room", room_id)
    _refresh()
    return bool(result.get("ok", false))


func open_selected_source() -> void:
    open_source_room(selected_room_id)


func open_source_room(room_id: String) -> void:
    var room: Resource = null if world_data == null else world_data.get_room(room_id)
    if room != null and _editor_interface != null and not room.source_scene_path.is_empty():
        _editor_interface.open_scene_from_path(room.source_scene_path)
        _sync_room_origin_after_open(room_id, room.source_scene_path)


## Writes the room's world origin into the source scene once it is the edited
## scene, so the cell frame in the room scene knows its parity. The property is
## saved with the scene; the world editor's bake always passes the live placement
## explicitly, so a stale copy can never crop the wrong cells.
func _sync_room_origin_after_open(room_id: String, source_path: String) -> void:
    if world_data == null or not is_inside_tree():
        return
    var origin := world_data.get_room_origin_chunk(room_id)
    for _attempt: int in 30:
        await get_tree().process_frame
        if not is_inside_tree() or _editor_interface == null or not _editor_interface.has_method("get_edited_scene_root"):
            return
        var root := _editor_interface.call("get_edited_scene_root") as Node
        if root == null or String(root.scene_file_path) != source_path:
            continue
        if root.get("world_origin_chunk") == null:
            return
        root.set("world_origin_chunk", origin)
        root.set("world_origin_known", true)
        if root is CanvasItem:
            (root as CanvasItem).queue_redraw()
        return


func _apply_move(room_id: String, origin_chunk: Vector2i) -> void:
    var result: Dictionary = _model.move_room(world_data, room_id, origin_chunk)
    _mark_changed(result)
    _refresh()


func _apply_add(room: RoomData) -> void:
    var result: Dictionary = _model.add_room(world_data, room)
    _mark_changed(result)
    _refresh()


func _apply_remove(value: Variant) -> void:
    var room_id: String = value.room_id if value is RoomData else String(value)
    var result: Dictionary = _model.remove_room(world_data, room_id)
    _mark_changed(result)
    _refresh()


func _apply_connect(connection: RoomConnectionData) -> void:
    var result: Dictionary = _model.connect_rooms(world_data, connection)
    _mark_changed(result)
    _refresh()


func _apply_disconnect(connection: RoomConnectionData) -> void:
    var result: Dictionary = _model.disconnect_rooms(world_data, connection.from_room_id, connection.from_entrance_id)
    _mark_changed(result)
    _refresh()


func _restore_world_state(state: Dictionary) -> void:
    var result: Dictionary = _model.restore_world_state(world_data, state)
    _mark_changed(result)
    _refresh()


func _mark_changed(result: Dictionary) -> void:
    if bool(result.get("ok", false)) and world_data != null:
        world_data.emit_changed()


func create_room_wizard() -> void:
    if world_data == null or world_data.resource_path.is_empty() or not FileAccess.file_exists(world_data.resource_path):
        _show_result(_failure("Select or create a saved WorldData resource first"))
        return
    _ensure_new_room_dialog()
    _wizard_id.text = ""
    _wizard_name.text = ""
    _wizard_path.text = ""
    _auto_path = ""
    _new_room_dialog.popup_centered_ratio(0.4)
    _wizard_id.grab_focus()


## Create a room from the template, import/bake it into the world and open it.
func create_room(room_id: String, display_name: String, source_path: String) -> Dictionary:
    if world_data == null or world_data.resource_path.is_empty() or not FileAccess.file_exists(world_data.resource_path):
        return _failure("Select or create a saved WorldData resource first")
    var id := ROOM_BAKE_PATHS.sanitize_room_id(room_id)
    var path := source_path.strip_edges()
    if id.is_empty():
        return _failure("Room id must contain letters, digits or underscores")
    if world_data.has_room(id):
        return _failure("A room with this id already exists: %s" % id)
    var result: Dictionary = ROOM_SCENE_WRITER.write_new_room(path, id, display_name)
    if not bool(result.get("ok", false)):
        return result
    _add_existing_source(path)
    if world_data == null or not world_data.has_room(id):
        return _failure("Room could not be imported into the world")
    select_room(id)
    open_source_room(id)
    return {"ok": true, "errors": [], "warnings": [], "path": path}


func bake_stale_rooms() -> void:
    var ids := _stale_room_ids()
    for room_id: String in ids:
        _bake_room(room_id)
    if ids.is_empty():
        _show_result({"ok": true, "errors": [], "warnings": []})


func _stale_room_ids() -> Array[String]:
    var ids: Array[String] = []
    for room_id: String in room_statuses:
        if room_statuses[room_id] == &"stale":
            ids.append(room_id)
    ids.sort()
    return ids


func _ensure_new_room_dialog() -> void:
    if _new_room_dialog != null and is_instance_valid(_new_room_dialog):
        return
    _new_room_dialog = ConfirmationDialog.new()
    _new_room_dialog.name = "NewRoomDialog"
    _new_room_dialog.title = WorldEditorLocalization.t("WE_NEW_ROOM_DIALOG")
    _new_room_dialog.ok_button_text = WorldEditorLocalization.t("WE_CREATE")
    add_child(_new_room_dialog)
    var root := VBoxContainer.new()
    root.custom_minimum_size = Vector2(460, 0)
    _new_room_dialog.add_child(root)
    var grid := GridContainer.new()
    grid.columns = 2
    grid.add_theme_constant_override("h_separation", 10)
    grid.add_theme_constant_override("v_separation", 8)
    root.add_child(grid)
    _wizard_id = _add_wizard_field(grid, "WE_FIELD_ROOM_ID")
    _wizard_name = _add_wizard_field(grid, "WE_FIELD_DISPLAY_NAME")
    _wizard_path = _add_wizard_field(grid, "WE_FIELD_SOURCE_PATH")
    _wizard_id.text_changed.connect(_on_wizard_id_changed)
    _new_room_dialog.confirmed.connect(_on_create_room_confirmed)


func _add_wizard_field(grid: GridContainer, key: String) -> LineEdit:
    var label := Label.new()
    label.text = WorldEditorLocalization.t(key)
    label.add_theme_font_size_override("font_size", 13)
    grid.add_child(label)
    var edit := LineEdit.new()
    edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    edit.custom_minimum_size.x = 300
    grid.add_child(edit)
    return edit


func _on_wizard_id_changed(text: String) -> void:
    var id := ROOM_BAKE_PATHS.sanitize_room_id(text)
    var next_auto := "" if id.is_empty() or world_data == null else "res://scenes/levels/%s/%s.tscn" % [world_data.world_id, id]
    if _wizard_path.text.is_empty() or _wizard_path.text == _auto_path:
        _wizard_path.text = next_auto
    _auto_path = next_auto


func _on_create_room_confirmed() -> void:
    var result: Dictionary = create_room(_wizard_id.text, _wizard_name.text, _wizard_path.text)
    _show_result(result)
    if bool(result.get("ok", false)):
        _new_room_dialog.hide()
    else:
        _new_room_dialog.popup_centered_ratio(0.4)


func _localize_ui() -> void:
    var t := WorldEditorLocalization.t
    if is_instance_valid(view_mode_3d):
        view_mode_3d.text = t.call("WE_STACK_VIEW_3D")
        view_mode_3d.tooltip_text = t.call("WE_TT_STACK_VIEW_3D")
    %NewWorld.text = t.call("WE_NEW_WORLD")
    %NewWorld.tooltip_text = t.call("WE_TT_NEW_WORLD")
    %SaveWorld.text = t.call("WE_SAVE_WORLD")
    %SaveWorld.tooltip_text = t.call("WE_TT_SAVE_WORLD")
    %NewRoom.text = t.call("WE_NEW_ROOM")
    %NewRoom.tooltip_text = t.call("WE_TT_NEW_ROOM")
    %AddExisting.text = t.call("WE_ADD_EXISTING")
    %AddExisting.tooltip_text = t.call("WE_TT_ADD_EXISTING_NO_WORLD")
    %OpenSource.text = t.call("WE_OPEN_SOURCE")
    %OpenSource.tooltip_text = t.call("WE_TT_OPEN_SOURCE")
    %BakeRoom.text = t.call("WE_BAKE")
    %BakeRoom.tooltip_text = t.call("WE_TT_BAKE_ROOM")
    %BakeStale.tooltip_text = t.call("WE_TT_BAKE_STALE")
    %ValidateRoom.text = t.call("WE_VALIDATE")
    %ValidateRoom.tooltip_text = t.call("WE_TT_VALIDATE_ROOM")
    %ValidateWorld.text = t.call("WE_VALIDATE_WORLD")
    %ValidateWorld.tooltip_text = t.call("WE_TT_VALIDATE_WORLD")
    %BakeWorld.text = t.call("WE_BAKE_WORLD")
    %BakeWorld.tooltip_text = t.call("WE_TT_BAKE_WORLD")
    %RoomsToggle.text = t.call("WE_ROOMS")
    %RoomsToggle.tooltip_text = t.call("WE_TT_TOGGLE_ROOMS")
    %InspectorToggle.text = t.call("WE_INSPECTOR")
    %InspectorToggle.tooltip_text = t.call("WE_TT_TOGGLE_INSPECTOR")
    %RoomSearch.placeholder_text = t.call("WE_SEARCH_ROOMS")
    %FocusAll.text = t.call("WE_FOCUS_ALL")
    %FocusAll.tooltip_text = t.call("WE_TT_FOCUS_ALL")
    %ResetView.text = t.call("WE_RESET_VIEW")
    %ResetView.tooltip_text = t.call("WE_TT_RESET_VIEW")
    %Connect.text = t.call("WE_CONNECT")
    %Disconnect.text = t.call("WE_DISCONNECT")
    %ConnectionsTitle.text = t.call("WE_CONNECTIONS")
    %AddExistingDialog.title = t.call("WE_DIALOG_ADD_EXISTING")
    %NewWorldDialog.title = t.call("WE_DIALOG_NEW_WORLD")
    %ChunkGo.text = t.call("WE_CHUNK_GO")
    %ChunkField.placeholder_text = t.call("WE_CHUNK_PLACEHOLDER")
    %ChunkField.tooltip_text = t.call("WE_TT_CHUNK_FIELD")


func _sync_world_picker(resource: WorldData) -> void:
    if not is_instance_valid(world_picker):
        return
    var has_property := false
    for property: Dictionary in world_picker.get_property_list():
        if String(property.get("name", "")) == "edited_resource":
            has_property = true
            break
    if not has_property:
        return
    if world_picker.get("edited_resource") != resource:
        world_picker.set("edited_resource", resource)


func _refresh() -> void:
    _refresh_statuses()
    _refresh_annotations()
    if is_instance_valid(source_entrance):
        _refresh_connection_options()
    if is_instance_valid(room_list):
        room_list.call(
            "set_rooms",
            _sorted_rooms(),
            room_statuses,
            room_status_messages,
            selected_room_ids,
            selected_room_id,
            _start_room_id()
        )
        room_list.call("set_filter", room_search.text if is_instance_valid(room_search) else "")
    if is_instance_valid(room_count):
        room_count.text = WorldEditorLocalization.t("WE_ROOMS_COUNT", [0 if world_data == null else world_data.rooms.size()])
    if is_instance_valid(inspector):
        _refresh_inspector()
    # Built once per refresh: the diagnostics and the 3D view read the same data.
    _stack_3d_payload = build_stack_3d_payload()
    _report_diagnostics()
    if is_instance_valid(canvas):
        if canvas.has_method("set_statuses"):
            canvas.call("set_statuses", room_statuses)
        if canvas.has_method("set_selection"):
            canvas.call("set_selection", selected_room_ids, selected_room_id)
        if canvas.has_method("set_annotations"):
            canvas.call("set_annotations", _annotations)
        if canvas.has_method("set_portal_links"):
            canvas.call("set_portal_links", _current_portal_links())
        if canvas.has_method("sync_preview"):
            canvas.call("sync_preview")
        canvas.queue_redraw()
    _refresh_stack_3d()
    _refresh_layer_panel()
    _refresh_status_bar()
    _refresh_command_state()


# --- Workbench refresh helpers ------------------------------------------------

func _sorted_rooms() -> Array[RoomData]:
    var rooms: Array[RoomData] = []
    if world_data == null:
        return rooms
    var ids := world_data.get_room_ids()
    ids.sort()
    for id: String in ids:
        var room := world_data.get_room(id)
        if room != null:
            rooms.append(room)
    return rooms


func _refresh_statuses() -> void:
    room_statuses.clear()
    room_status_messages.clear()
    room_status_raw_messages.clear()
    for room: RoomData in _sorted_rooms():
        var result: Dictionary = _status.evaluate(room)
        room_statuses[room.room_id] = result.get("state", &"unknown")
        var raw_message := String(result.get("message", ""))
        room_status_raw_messages[room.room_id] = raw_message
        var message := raw_message
        var message_key := String(result.get("message_key", ""))
        if not message_key.is_empty():
            message = WorldEditorLocalization.t(message_key, result.get("message_args", []))
        room_status_messages[room.room_id] = message


func _refresh_annotations() -> void:
    _annotations.clear()
    for room: RoomData in _sorted_rooms():
        _annotations[room.room_id] = _annotations_service.collect(room)


func _refresh_inspector() -> void:
    if not is_instance_valid(inspector):
        return
    if world_data == null or selected_room_ids.is_empty():
        inspector.call("clear")
        return
    var rooms: Array[RoomData] = []
    for id: String in selected_room_ids:
        var room := world_data.get_room(id)
        if room != null:
            rooms.append(room)
    if rooms.is_empty():
        inspector.call("clear")
        return
    if rooms.size() == 1:
        var room := rooms[0]
        inspector.call(
            "show_room",
            room,
            room_statuses.get(room.room_id, &"unknown"),
            room_status_messages.get(room.room_id, ""),
            world_data.connections,
            _start_room_id(),
            _start_spawn_id()
        )
    else:
        inspector.call("show_multi", rooms, room_statuses)


func _report_diagnostics() -> void:
    var lines: Array[String] = []
    if world_data != null:
        _world_report = _model.validate_world(world_data)
        for message: Variant in _world_report.get("errors", []):
            lines.append(WorldEditorLog.format_error(String(message)))
        for message: Variant in _world_report.get("warnings", []):
            lines.append(WorldEditorLog.format_warning(String(message)))
        for room_id: String in room_statuses:
            var state: StringName = room_statuses[room_id]
            if state == &"fresh":
                continue
            var message := String(room_status_raw_messages.get(room_id, ""))
            var text := "%s: %s" % [room_id, message] if not message.is_empty() else room_id
            if state == &"error":
                lines.append(WorldEditorLog.format_error(text))
            else:
                lines.append(WorldEditorLog.format_warning(text))
        for issue: Dictionary in _session_issues:
            var issue_text := "%s: %s" % [String(issue.get("room_id", "")), String(issue.get("message", ""))]
            if issue.get("severity", &"error") == &"error":
                lines.append(WorldEditorLog.format_error(issue_text))
            else:
                lines.append(WorldEditorLog.format_warning(issue_text))
        for dangling: String in _dangling_diagnostics():
            lines.append(WorldEditorLog.format_warning(dangling))
    var signature := "\n".join(lines)
    if signature == _output_signature:
        return
    _output_signature = signature
    for line: String in lines:
        print(line)



# --- 3D stack view ------------------------------------------------------------

## The 3D slice view replaces the flat canvas. It is loaded by path and skipped
## when absent so the editor still opens without it.
func set_view_mode_3d(enabled: bool) -> bool:
    if enabled and world_data == null:
        _set_view_mode_button(false)
        return false
    if not enabled:
        _view_3d = false
        if _stack_3d_view != null and is_instance_valid(_stack_3d_view):
            _stack_3d_view.visible = false
        if is_instance_valid(canvas):
            canvas.queue_redraw()
        _refresh_command_state()
        return true
    if _stack_3d_view == null or not is_instance_valid(_stack_3d_view):
        _stack_3d_view = _ensure_stack_3d_view()
    if _stack_3d_view == null:
        _set_view_mode_button(false)
        _show_result(_failure(WorldEditorLocalization.t("WE_STACK_3D_MISSING")))
        return false
    _view_3d = true
    # The 3D view is a full-rect, opaque child of the canvas: it covers the flat
    # work view instead of hiding it, because hiding the canvas would hide the
    # 3D view with it.
    _stack_3d_view.visible = true
    _stack_3d_view.mouse_filter = Control.MOUSE_FILTER_STOP
    if is_instance_valid(canvas):
        canvas.move_child(_stack_3d_view, canvas.get_child_count() - 1)
    _refresh()
    # Anchors own the view's size, so frame it once the layout has settled
    # instead of assigning a size (which Godot warns about).
    if _stack_3d_view.has_method("focus_stack"):
        _stack_3d_view.call_deferred("focus_stack")
    _refresh_command_state()
    return true


func is_view_mode_3d() -> bool:
    return _view_3d


func get_stack_3d_payload() -> Dictionary:
    return build_stack_3d_payload()


func _set_view_mode_button(pressed: bool) -> void:
    if is_instance_valid(view_mode_3d):
        view_mode_3d.set_pressed_no_signal(pressed)


func _ensure_stack_3d_view() -> Control:
    if not ResourceLoader.exists(STACK_3D_PATH):
        return null
    var script := load(STACK_3D_PATH) as Script
    if script == null or not is_instance_valid(canvas):
        return null
    var view := Control.new()
    view.name = "Stack3DView"
    view.mouse_filter = Control.MOUSE_FILTER_STOP
    view.set_script(script)
    canvas.add_child(view)
    view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    view.visible = false
    if view.has_signal("world_picked"):
        view.connect("world_picked", _on_stack_world_picked)
    return view


func _refresh_stack_3d() -> void:
    if not _view_3d or _stack_3d_view == null or not is_instance_valid(_stack_3d_view):
        return
    _stack_3d_view.call("set_stack", _stack_3d_payload)


## Clicking a slice in the 3D view edits that world in the flat 2D view.
func _on_stack_world_picked(world_id: String) -> void:
    if world_id.is_empty():
        return
    var target: WorldData
    if world_data != null and world_data.world_id == world_id:
        target = world_data
    else:
        for world: WorldData in get_stack_worlds():
            if world != null and world.world_id == world_id:
                target = world
                break
    if target == null:
        target = _find_stack_world(world_id)
    if target == null:
        _show_result(_failure("world is not available: %s" % world_id))
        return
    _set_view_mode_button(false)
    set_view_mode_3d(false)
    if target != world_data:
        set_world_data(target)
    if is_instance_valid(canvas):
        canvas.call("focus_all")
    _show_result({"ok": true, "errors": [], "warnings": [], "path": target.resource_path})


func _current_portal_links() -> Array:
    if world_data == null:
        return []
    return _stack_model.build_portal_links(world_data, world_data.world_id, _annotations)


## Worlds drawn as slices: exactly the stack this world belongs to.
func _stack_3d_worlds() -> Array[WorldData]:
    return get_stack_worlds()


func _annotations_for_world(world: WorldData) -> Dictionary:
    var result: Dictionary = {}
    if world == null:
        return result
    for room_id: String in world.get_room_ids():
        result[room_id] = _annotations_service.collect(world.get_room(room_id))
    return result


## Everything the 3D layer needs: slices with rooms and doors, plus the door
## links (portal inside a slice, shuttle across slices) in chunk units.
func build_stack_3d_payload() -> Dictionary:
    var payload := {
        "current_world_id": "" if world_data == null else world_data.world_id,
        "layers": [],
        "links": [],
        "dangling_count": 0,
    }
    if world_data == null:
        return payload
    var worlds := _stack_3d_worlds()
    var layers: Array[Dictionary] = []
    var all_doors: Array[Dictionary] = []
    for index: int in range(worlds.size()):
        var world: WorldData = worlds[index]
        # The stack reloads worlds from disk, so identity is not guaranteed: the
        # edited world is the one with the same id.
        var annotations: Dictionary = (
            _annotations if world.world_id == world_data.world_id
            else _annotations_for_world(world)
        )
        var rooms: Array[Dictionary] = []
        var bounds := Rect2()
        var has_bounds := false
        for room_id: String in world.get_room_ids():
            var room := world.get_room(room_id)
            if room == null:
                continue
            var rect := Rect2(Vector2(world.get_room_origin_chunk(room_id)), Vector2(room.room_size_chunks))
            rooms.append({"id": room_id, "rect": rect})
            bounds = rect if not has_bounds else bounds.merge(rect)
            has_bounds = true
        if not has_bounds:
            continue
        var doors: Array[Dictionary] = []
        var records := _stack_model.collect_world_doors(world, world.world_id, index, annotations)
        for record: Dictionary in records:
            doors.append({
                "id": String(record.get("door_id", "")),
                "pos": _to_chunk_units(record.get("position", Vector2.ZERO)),
                "kind": int(record.get("door_kind", 0)),
            })
            all_doors.append(record)
        layers.append({
            "index": index,
            "world_id": world.world_id,
            "name": world.display_name if not world.display_name.is_empty() else world.world_id,
            "color": _stack_model.layer_color(world.world_id),
            "bounds": bounds.grow(0.18),
            "rooms": rooms,
            "doors": doors,
        })
    var report: Dictionary = _stack_model.build_door_links(all_doors)
    var links: Array[Dictionary] = []
    var dangling: Array[Dictionary] = []
    for link: Dictionary in report.get("links", []):
        if not bool(link.get("paired", false)):
            dangling.append(link)
        links.append({
            "kind": String(link.get("kind", "portal")),
            "paired": bool(link.get("paired", false)),
            "from_layer": int(link.get("from_layer", 0)),
            "from_pos": _to_chunk_units(link.get("from_position", Vector2.ZERO)),
            "to_layer": int(link.get("to_layer", 0)),
            "to_pos": _to_chunk_units(link.get("to_position", Vector2.ZERO)),
        })
    payload["layers"] = layers
    payload["links"] = links
    payload["dangling_links"] = dangling
    payload["dangling_count"] = int(report.get("dangling_count", 0))
    return payload


static func _to_chunk_units(world_pixels: Vector2) -> Vector2:
    return Vector2(world_pixels.x / CHUNK_PIXELS_F.x, world_pixels.y / CHUNK_PIXELS_F.y)


func _world_catalog_worlds() -> Array[WorldData]:
    var worlds: Array[WorldData] = []
    if not ResourceLoader.exists(WORLD_CATALOG_PATH):
        return worlds
    var catalog := ResourceLoader.load(WORLD_CATALOG_PATH) as WorldCatalog
    if catalog == null:
        return worlds
    for world: WorldData in catalog.get_worlds():
        if world != null and not world.world_id.is_empty():
            worlds.append(world)
    return worlds


## Worlds the stack can layer: the catalog first (its order is authored), then
## any other WorldData saved under [member stack_world_directory]. The editor can
## open a world that was never registered in the catalog �?New World writes
## exactly that �?so the stack must offer it too. Deduplicated by world_id.
func get_stack_candidate_worlds() -> Array[WorldData]:
    var worlds: Array[WorldData] = []
    var seen: Dictionary = {}
    for world: WorldData in _world_catalog_worlds():
        if world == null or world.world_id.is_empty() or seen.has(world.world_id):
            continue
        seen[world.world_id] = true
        worlds.append(world)
    for world: WorldData in _worlds_in_directory():
        if world == null or world.world_id.is_empty() or seen.has(world.world_id):
            continue
        seen[world.world_id] = true
        worlds.append(world)
    return worlds


## WorldData resources saved in [member stack_world_directory], sorted by file
## name so the add menu keeps a stable order between runs.
func _worlds_in_directory() -> Array[WorldData]:
    var worlds: Array[WorldData] = []
    var directory := DirAccess.open(stack_world_directory)
    if directory == null:
        return worlds
    var files: Array[String] = []
    directory.list_dir_begin()
    var entry := directory.get_next()
    while not entry.is_empty():
        if not directory.current_is_dir() and entry.get_extension().to_lower() == "tres":
            files.append(entry)
        entry = directory.get_next()
    directory.list_dir_end()
    files.sort()
    for file_name: String in files:
        var resource := ResourceLoader.load(stack_world_directory.path_join(file_name))
        if resource is WorldData and not (resource as WorldData).world_id.is_empty():
            worlds.append(resource as WorldData)
    return worlds


func _find_stack_world(world_id: String) -> WorldData:
    if world_id.is_empty():
        return null
    for world: WorldData in get_stack_candidate_worlds():
        if world != null and world.world_id == world_id:
            return world
    return null


# --- Layer panel (3D view) ----------------------------------------------------

const WORLD_STACK_SCRIPT := preload("res://addons/platformer_kit/world/data/world_stack_data.gd")

## The stack this world belongs to, or null when it is not stacked with anything.
##
## The stack lives next to the world as `<world>_stack.tres` and is found by that
## convention. A resource reference from the world back to its own stack made the
## pair cyclic, and Godot's text resource loader cannot resolve a cycle: loading
## either file failed with "referenced non-existent resource", which took the
## whole world catalog (and the world-select screen) down with it.
func get_world_stack() -> WorldStack:
    if world_data == null:
        return null
    var path := _stack_path_for(world_data)
    if path.is_empty():
        return null
    if _stack_cache != null and is_instance_valid(_stack_cache) and _stack_cache_path == path:
        return _stack_cache
    if not ResourceLoader.exists(path):
        _stack_cache = null
        _stack_cache_path = ""
        return null
    var loaded := ResourceLoader.load(path, "WorldStack") as WorldStack
    _stack_cache = loaded
    _stack_cache_path = path
    return loaded


## `<base_dir>/<world_basename>_stack.tres`, or "" for an unsaved world.
static func _stack_path_for(world: WorldData) -> String:
    if world == null or world.resource_path.is_empty() or world.resource_path.get_extension() != "tres":
        return ""
    return "%s/%s_stack.tres" % [
        world.resource_path.get_base_dir(),
        world.resource_path.get_file().get_basename()
    ]


## Creates and saves a stack resource for the edited world on demand, so adding
## the first layer is one click instead of a manual resource step.
func ensure_world_stack() -> WorldStack:
    var existing := get_world_stack()
    if existing != null:
        return existing
    if world_data == null:
        return null
    var path := _stack_path_for(world_data)
    if path.is_empty():
        _show_result(_failure(WorldEditorLocalization.t("WE_STACK_NEEDS_SAVED_WORLD")))
        return null
    var stack: WorldStack = WORLD_STACK_SCRIPT.new() as WorldStack
    stack.stack_id = "%s_stack" % world_data.world_id
    stack.display_name = "%s Stack" % _world_label(world_data)
    stack.layers.assign([world_data])
    if ResourceSaver.save(stack, path) != OK:
        _show_result(_failure(WorldEditorLocalization.t("WE_STACK_SAVE_FAILED", [path])))
        return null
    # `ResourceSaver.save` does not claim the path for the instance; without this
    # the caller sees an empty `resource_path` and later saves go nowhere.
    stack.take_over_path(path)
    # Keep this exact instance cached: the caller mutates it next, and
    # `_after_stack_change()` has to save the mutation, not a reread.
    _stack_cache = stack
    _stack_cache_path = path
    return stack


## Worlds drawn as slices, bottom layer first. A world without a stack is a
## stack of one; a stack that lost its own world gets it back at layer 0.
func get_stack_worlds() -> Array[WorldData]:
    var result: Array[WorldData] = []
    if world_data == null:
        return result
    var stack := get_world_stack()
    if stack == null:
        result.append(world_data)
        return result
    stack.normalize()
    for world: WorldData in stack.layers:
        if world != null:
            result.append(world)
    var has_current := false
    for world: WorldData in result:
        if world.world_id == world_data.world_id:
            has_current = true
            break
    if not has_current:
        result.insert(0, world_data)
    return result


func add_layer(world_id: String) -> void:
    if world_data == null or world_id.is_empty() or world_id == world_data.world_id:
        return
    var world := _find_stack_world(world_id)
    if world == null:
        return
    var stack := get_world_stack()
    if stack == null:
        stack = ensure_world_stack()
        if stack == null:
            return
    if not stack.insert_world(world):
        return
    _after_stack_change()


func remove_layer(world_id: String) -> void:
    var stack := get_world_stack()
    if stack == null or world_data == null or world_id == world_data.world_id:
        return
    if not stack.remove_world(world_id):
        return
    _after_stack_change()


func move_layer(world_id: String, delta: int) -> void:
    var stack := get_world_stack()
    if stack == null:
        return
    var index := stack.get_layer_index(world_id)
    if index < 0 or not stack.move_layer(index, index + delta):
        return
    _after_stack_change()


func _after_stack_change() -> void:
    var stack := get_world_stack()
    if stack != null:
        stack.emit_changed()
        if not stack.resource_path.is_empty() and ResourceSaver.save(stack, stack.resource_path) != OK:
            _show_result(_failure(WorldEditorLocalization.t("WE_STACK_SAVE_FAILED", [stack.resource_path])))
    _refresh()
    if _view_3d and _stack_3d_view != null and is_instance_valid(_stack_3d_view):
        _stack_3d_view.call("focus_stack")


func _on_layer_add_pressed() -> void:
    if not is_instance_valid(layer_add):
        return
    var menu := layer_add.get_node_or_null("LayerAddMenu") as PopupMenu
    if menu == null:
        menu = PopupMenu.new()
        menu.name = "LayerAddMenu"
        layer_add.add_child(menu)
        menu.index_pressed.connect(_on_layer_add_selected)
    menu.clear()
    var stacked := get_stack_worlds()
    var stacked_ids: Dictionary = {}
    for world: WorldData in stacked:
        stacked_ids[world.world_id] = true
    if world_data != null:
        stacked_ids[world_data.world_id] = true
    for world: WorldData in get_stack_candidate_worlds():
        if world == null or world.world_id.is_empty():
            continue
        if stacked_ids.has(world.world_id):
            continue
        menu.add_item(_world_label(world), menu.item_count)
        menu.set_item_metadata(menu.item_count - 1, world.world_id)
    if menu.item_count == 0:
        _show_result(_failure(WorldEditorLocalization.t("WE_STACK_EMPTY")))
        return
    menu.reset_size()
    menu.position = Vector2i(
        int(layer_add.get_screen_position().x),
        int(layer_add.get_screen_position().y + layer_add.size.y)
    )
    menu.popup()


func _on_layer_add_selected(index: int) -> void:
    if not is_instance_valid(layer_add):
        return
    var menu := layer_add.get_node_or_null("LayerAddMenu") as PopupMenu
    if menu == null or index < 0 or index >= menu.item_count:
        return
    add_layer(String(menu.get_item_metadata(index)))


## Left column in 3D mode: the world stack (Z order) instead of the room list.
func _refresh_layer_panel() -> void:
    if not is_instance_valid(layer_panel):
        return
    if is_instance_valid(room_search):
        room_search.visible = not _view_3d
    if is_instance_valid(room_list):
        room_list.visible = not _view_3d
    if is_instance_valid(room_count):
        room_count.visible = not _view_3d
    layer_panel.visible = _view_3d
    if not _view_3d:
        return
    var t := WorldEditorLocalization.t
    layer_title.text = String(t.call("WE_STACK_LAYER_TITLE"))
    layer_add.text = String(t.call("WE_STACK_ADD_WORLD"))
    layer_add.disabled = world_data == null
    layer_hint.text = String(
        t.call("WE_STACK_LAYER_HINT" if get_world_stack() != null else "WE_STACK_LAYER_HINT_EMPTY")
    )
    for child: Node in layer_rows.get_children():
        # Detach now so a rebuild inside a row button's own handler cannot count
        # the old rows twice; freeing is deferred so the running button stays alive.
        layer_rows.remove_child(child)
        child.queue_free()
    if world_data == null:
        return
    var stacked := get_stack_worlds()
    for index: int in range(stacked.size() - 1, -1, -1):
        var world: WorldData = stacked[index]
        _append_layer_row(index, world, index == 0, stacked.size())
    if stacked.size() == 1:
        var empty := Label.new()
        empty.text = String(t.call("WE_STACK_ONLY_ONE"))
        empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        empty.modulate = Color(1, 1, 1, 0.5)
        empty.add_theme_font_size_override("font_size", 11)
        layer_rows.add_child(empty)


func _append_layer_row(z: int, world: WorldData, is_bottom: bool, layer_count: int) -> void:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 4)
    var is_current := world_data != null and world.world_id == world_data.world_id
    var badge := Label.new()
    badge.text = "Z%d" % z
    badge.custom_minimum_size.x = 34
    badge.modulate = Color(1, 1, 1, 0.95 if is_current else 0.55)
    badge.add_theme_font_size_override("font_size", 11)
    row.add_child(badge)
    var name_button := Button.new()
    name_button.text = _world_label(world)
    name_button.flat = true
    name_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
    name_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    name_button.disabled = is_current
    name_button.tooltip_text = WorldEditorLocalization.t("WE_TT_LAYER_ROW")
    if not is_current:
        var world_id := world.world_id
        name_button.pressed.connect(func() -> void: _on_stack_world_picked(world_id))
    row.add_child(name_button)
    if not is_bottom:
        var world_id := world.world_id
        var up := Button.new()
        up.text = "▲"
        up.tooltip_text = WorldEditorLocalization.t("WE_TT_LAYER_UP")
        up.custom_minimum_size.x = 26
        up.disabled = z >= layer_count - 1
        up.pressed.connect(func() -> void: move_layer(world_id, 1))
        row.add_child(up)
        var down := Button.new()
        down.text = "▼"
        down.tooltip_text = WorldEditorLocalization.t("WE_TT_LAYER_DOWN")
        down.custom_minimum_size.x = 26
        down.disabled = z <= 0
        down.pressed.connect(func() -> void: move_layer(world_id, -1))
        row.add_child(down)
        var remove := Button.new()
        remove.text = "✕"
        remove.tooltip_text = WorldEditorLocalization.t("WE_TT_LAYER_REMOVE")
        remove.custom_minimum_size.x = 26
        remove.pressed.connect(func() -> void: remove_layer(world_id))
        row.add_child(remove)
    layer_rows.add_child(row)


func _world_label(world: WorldData) -> String:
    if world == null:
        return ""
    return world.display_name if not world.display_name.is_empty() else world.world_id


## One de-duplicated warning line per door that found no partner.
func _dangling_diagnostics() -> Array[String]:
    var lines: Array[String] = []
    for link: Dictionary in _stack_3d_payload.get("dangling_links", []):
        var line := "%s link %s/%s/%s -> %s/%s/%s is unmatched" % [
            String(link.get("kind", "")),
            String(link.get("from_world_id", "")),
            String(link.get("from_room_id", "")),
            String(link.get("from_door_id", "")),
            String(link.get("to_world_id", "")),
            String(link.get("to_room_id", "")),
            String(link.get("to_door_id", "")),
        ]
        if not lines.has(line):
            lines.append(line)
    return lines



func _refresh_status_bar() -> void:
    var preview_errors: Dictionary = {}
    if is_instance_valid(canvas):
        var preview_layer := canvas.get_node_or_null("TerrainPreviewLayer")
        if preview_layer != null and preview_layer.has_method("get_preview_errors"):
            preview_errors = preview_layer.call("get_preview_errors")
    if is_instance_valid(status_label):
        if not preview_errors.is_empty():
            status_label.text = String(preview_errors.values()[0])
        else:
            status_label.text = WorldEditorLocalization.t("WE_NO_WORLD_SELECTED") if world_data == null else WorldEditorLocalization.t("WE_ROOMS_COUNT", [world_data.rooms.size()])
    if is_instance_valid(selection_label):
        selection_label.text = "" if selected_room_ids.is_empty() else WorldEditorLocalization.t("WE_SELECTED_COUNT", [selected_room_ids.size()])
    _refresh_chunk_field()


## Status-bar chunk field mirrors the primary selection's chunk origin.
func _refresh_chunk_field() -> void:
    if not is_instance_valid(chunk_field):
        return
    if world_data != null and not selected_room_id.is_empty() and world_data.has_room(selected_room_id):
        var origin := world_data.get_room_origin_chunk(selected_room_id)
        chunk_field.text = "%d,%d" % [origin.x, origin.y]
        return
    chunk_field.text = ""


## Parses the status-bar chunk field ("x,y", spaces and negatives allowed).
## Returns a Vector2i, or null when the text is not a chunk.
static func parse_chunk_text(text: String) -> Variant:
    var cleaned := String(text).strip_edges().replace(" ", "").replace("\t", "")
    if cleaned.is_empty():
        return null
    var parts := cleaned.split(",")
    if parts.size() != 2:
        return null
    var left := String(parts[0]).strip_edges()
    var right := String(parts[1]).strip_edges()
    if not left.is_valid_int() or not right.is_valid_int():
        return null
    return Vector2i(
        clampi(int(left), -100000, 100000),
        clampi(int(right), -100000, 100000)
    )


func _on_chunk_go() -> void:
    if not is_instance_valid(chunk_field):
        return
    var parsed: Variant = parse_chunk_text(chunk_field.text)
    if parsed == null:
        chunk_field.text = ""
        _show_result(_failure(WorldEditorLocalization.t("WE_CHUNK_INVALID")))
        return
    var chunk: Vector2i = parsed
    var moved := false
    if world_data != null and not selected_room_id.is_empty() and world_data.has_room(selected_room_id):
        moved = move_room(selected_room_id, chunk)
    if not moved and is_instance_valid(canvas) and canvas.has_method("focus_chunk"):
        canvas.call("focus_chunk", chunk)
    _refresh_chunk_field()


func _start_room_id() -> String:
    return "" if world_data == null else world_data.start_room_id


func _start_spawn_id() -> String:
    return "" if world_data == null else world_data.start_spawn_id


func _add_session_issue(room_id: String, message: String, severity: StringName = &"error") -> void:
    _session_issues.append({"severity": severity, "message": message, "room_id": room_id})


func _remove_session_issues(room_id: String) -> void:
    for index in range(_session_issues.size() - 1, -1, -1):
        if String(_session_issues[index].get("room_id", "")) == room_id:
            _session_issues.remove_at(index)


func _on_search_changed(text: String) -> void:
    if is_instance_valid(room_list):
        room_list.call("set_filter", text)


func _on_list_selection_changed(room_ids: Array, primary: String) -> void:
    set_selection(room_ids, primary)


func _on_canvas_selection_changed(room_ids: Array, primary: String) -> void:
    set_selection(room_ids, primary)


func _on_room_action(action: StringName, room_id: String) -> void:
    match action:
        &"open_source":
            open_source_room(room_id)
        &"bake":
            if selected_room_ids.size() > 1:
                _bake_selection()
            else:
                _bake_room(room_id)
        &"validate":
            if selected_room_ids.size() > 1:
                _validate_selection()
            else:
                _validate_room(room_id)
        &"focus":
            select_room(room_id)
            if is_instance_valid(canvas) and canvas.has_method("focus_room"):
                canvas.call("focus_room", room_id)
        &"remove":
            if selected_room_ids.size() > 1:
                delete_selected_rooms()
            else:
                remove_room(room_id)
        &"set_start":
            set_start_room(room_id, _default_spawn(room_id))
        &"bake_selected":
            _bake_selection()
        &"validate_selected":
            _validate_selection()
        &"remove_selected":
            delete_selected_rooms()
        &"open_first":
            open_source_room(selected_room_id)


func _default_spawn(room_id: String) -> String:
    var room: RoomData = null if world_data == null else world_data.get_room(room_id)
    if room == null:
        return ""
    if is_instance_valid(inspector):
        var picked := String(inspector.call("get_selected_spawn_id"))
        if not picked.is_empty():
            return picked
    if world_data != null and world_data.start_room_id == room_id and not world_data.start_spawn_id.is_empty():
        return world_data.start_spawn_id
    return "" if room.spawn_ids.is_empty() else String(room.spawn_ids[0])


# --- Multi-selection commands -------------------------------------------------

func move_rooms_by(delta: Vector2i) -> bool:
    if world_data == null or _undo_redo == null or delta == Vector2i.ZERO or selected_room_ids.is_empty():
        return false
    var targets: Array[String] = []
    for id: String in selected_room_ids:
        if world_data.has_room(id):
            targets.append(id)
    if targets.is_empty():
        return false
    _undo_redo.create_action("Move Rooms")
    for id: String in targets:
        var from := world_data.get_room_origin_chunk(id)
        _undo_redo.add_do_method(self, "_apply_move", id, from + delta)
        _undo_redo.add_undo_method(self, "_apply_move", id, from)
    _undo_redo.commit_action()
    return true


func delete_selected_rooms() -> void:
    if world_data == null or _undo_redo == null or selected_room_ids.is_empty():
        return
    var previous_state: Dictionary = _model.capture_world_state(world_data)
    var targets: Array[String] = []
    for id: String in selected_room_ids:
        if world_data.has_room(id):
            targets.append(id)
    if targets.is_empty():
        return
    _undo_redo.create_action("Remove Room References")
    for id: String in targets:
        _undo_redo.add_do_method(self, "_apply_remove", id)
    _undo_redo.add_undo_method(self, "_restore_world_state", previous_state)
    _undo_redo.commit_action()
    selected_room_ids.clear()
    selected_room_id = ""
    _refresh()


func set_start_room(room_id: String, spawn_id: String) -> bool:
    if world_data == null or _undo_redo == null or room_id.is_empty() or not world_data.has_room(room_id):
        return false
    var room := world_data.get_room(room_id)
    if room == null:
        return false
    if spawn_id.is_empty():
        spawn_id = _default_spawn(room_id)
    if spawn_id.is_empty() and not room.spawn_ids.is_empty():
        spawn_id = String(room.spawn_ids[0])
    _undo_redo.create_action("Set Start Room")
    _undo_redo.add_do_method(self, "_apply_start_room", room_id, spawn_id)
    _undo_redo.add_undo_method(self, "_apply_start_room", world_data.start_room_id, world_data.start_spawn_id)
    _undo_redo.commit_action()
    return true


func _apply_start_room(room_id: String, spawn_id: String) -> void:
    if world_data == null:
        return
    world_data.start_room_id = room_id
    world_data.start_spawn_id = spawn_id
    world_data.emit_changed()
    _refresh()


func _show_result(result: Dictionary) -> void:
    if not is_instance_valid(status_label):
        return
    var errors: Array = result.get("errors", [])
    var warnings: Array = result.get("warnings", [])
    var messages: Array = errors if not result.get("ok", false) else warnings
    status_label.text = WorldEditorLocalization.t("WE_COMPLETED") if messages.is_empty() else String(messages[0])
    var details: Array[String] = []
    for error: Variant in errors:
        details.append("Error: %s" % String(error))
        WorldEditorLog.error(String(error))
    for warning: Variant in warnings:
        details.append("Warning: %s" % String(warning))
        WorldEditorLog.warning(String(warning))
    var outputs: Dictionary = result.get("outputs", {})
    var output_keys: Array = outputs.keys()
    output_keys.sort()
    for key: Variant in output_keys:
        details.append("%s: %s" % [String(key), String(outputs[key])])
    if details.is_empty() and not String(result.get("path", "")).is_empty():
        details.append(String(result["path"]))
    status_label.tooltip_text = "\n".join(details)


func _instantiate_selected_source() -> Node:
    return _instantiate_room_source(selected_room_id)


func _instantiate_room_source(room_id: String) -> Node:
    var room: Resource = null if world_data == null else world_data.get_room(room_id)
    if room == null or room.source_scene_path.is_empty():
        return null
    var packed := load(room.source_scene_path) as PackedScene
    return null if packed == null else packed.instantiate()


## Chunk a freshly imported room should land on: under the pointer when the
## pointer is over the canvas, otherwise the chunk at the canvas view centre.
func _import_origin_chunk() -> Vector2i:
    if not is_instance_valid(canvas):
        return Vector2i.ZERO
    if canvas.has_method("is_cursor_over_canvas") and bool(canvas.call("is_cursor_over_canvas")) \
        and canvas.has_method("get_cursor_chunk"):
        return Vector2i(canvas.call("get_cursor_chunk"))
    if canvas.has_method("get_view_center_chunk"):
        return Vector2i(canvas.call("get_view_center_chunk"))
    return Vector2i.ZERO


func _add_existing_source(path: String) -> void:
    if world_data == null or world_data.resource_path.is_empty() or not FileAccess.file_exists(world_data.resource_path):
        _show_result(_failure("Select or create a saved WorldData resource first"))
        return
    if _transaction_busy:
        _show_result(_failure("Another world transaction is already running"))
        return
    _set_transaction_busy(true)
    var source := _load_room_source(path)
    var result: Dictionary
    if source == null:
        result = _failure("Room source could not be loaded: %s" % path)
    else:
        result = _world_room_importer.call("import_room", world_data, source, path, _import_origin_chunk())
        source.free()
    if bool(result.get("ok", false)):
        var imported_world := result.get("world") as WorldData
        var imported_room := result.get("room") as RoomData
        if imported_world == null or imported_room == null:
            result = _failure("Room importer returned incomplete saved resources")
        else:
            set_world_data(imported_world)
            select_room(imported_room.room_id)
            if is_instance_valid(canvas):
                canvas.call("focus_room", imported_room.room_id)
            _register_import_history(result)
    _set_transaction_busy(false)
    _show_result(result)


func get_command_state() -> Dictionary:
    var has_world := world_data != null
    var has_saved_world := has_world and not world_data.resource_path.is_empty() and FileAccess.file_exists(world_data.resource_path)
    var has_room := has_world and not selected_room_id.is_empty() and world_data.has_room(selected_room_id)
    var add_tooltip := WorldEditorLocalization.t("WE_TT_ADD_EXISTING")
    if not has_world:
        add_tooltip = WorldEditorLocalization.t("WE_TT_ADD_EXISTING_NO_WORLD")
    elif not has_saved_world:
        add_tooltip = WorldEditorLocalization.t("WE_TT_ADD_EXISTING_UNSAVED")
    elif _transaction_busy:
        add_tooltip = WorldEditorLocalization.t("WE_TT_BUSY")
    return {
        "has_selection": not selected_room_ids.is_empty(),
        "selection_count": selected_room_ids.size(),
        "add_existing_disabled": not has_saved_world or _transaction_busy,
        "add_existing_tooltip": add_tooltip,
        "save_world_disabled": not has_saved_world or _transaction_busy,
        "world_command_disabled": not has_world or _transaction_busy,
        "room_command_disabled": not has_room or _transaction_busy,
        "transaction_busy": _transaction_busy,
    }


func _refresh_command_state() -> void:
    if not is_node_ready():
        return
    var state := get_command_state()
    %AddExisting.disabled = bool(state["add_existing_disabled"])
    %AddExisting.tooltip_text = String(state["add_existing_tooltip"])
    %SaveWorld.disabled = bool(state["save_world_disabled"])
    for button: Button in [%ValidateWorld, %BakeWorld]:
        button.disabled = bool(state["world_command_disabled"])
    for button: Button in [%OpenSource, %ValidateRoom, %BakeRoom]:
        button.disabled = bool(state["room_command_disabled"])
    var stale_count := _stale_room_ids().size()
    %BakeStale.text = WorldEditorLocalization.t("WE_BAKE_STALE", [stale_count])
    %BakeStale.disabled = stale_count == 0 or bool(state["transaction_busy"])
    for button: Button in [%Connect, %Disconnect]:
        button.disabled = not bool(state["has_selection"]) or bool(state["transaction_busy"])
    for option: OptionButton in [source_entrance, target_room, target_spawn]:
        option.disabled = not bool(state["has_selection"])
    %NewRoom.disabled = bool(state["transaction_busy"])
    %NewWorld.disabled = bool(state["transaction_busy"])
    if is_instance_valid(view_mode_3d):
        view_mode_3d.disabled = bool(state["world_command_disabled"])


func _set_transaction_busy(value: bool) -> void:
    _transaction_busy = value
    _refresh_command_state()


func _load_room_source(path: String) -> Node:
    if not path.begins_with("res://") or path.get_extension().to_lower() != "tscn":
        return null
    var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
    return null if packed == null else packed.instantiate()


func _register_import_history(result: Dictionary) -> void:
    if _undo_redo == null or not result.has("before_state") or not result.has("after_state"):
        return
    var imported_world := result.get("world") as WorldData
    var world_path := String(result.get("path", ""))
    if imported_world == null or world_path.is_empty():
        return
    var payload := {
        "world_path": world_path,
        "world_id": imported_world.world_id,
    }
    var do_payload := payload.duplicate()
    do_payload["state"] = result["after_state"]
    var undo_payload := payload.duplicate()
    undo_payload["state"] = result["before_state"]
    _undo_redo.create_action("Add Existing Room", UndoRedo.MERGE_DISABLE, imported_world)
    _undo_redo.add_do_method(self, "_persist_import_state", do_payload)
    _undo_redo.add_undo_method(self, "_persist_import_state", undo_payload)
    _undo_redo.commit_action(false)


func _persist_import_state(payload: Dictionary) -> void:
    var world_path := String(payload.get("world_path", ""))
    var expected_world_id := String(payload.get("world_id", ""))
    var state: Dictionary = payload.get("state", {})
    if world_path.is_empty() or expected_world_id.is_empty() or state.is_empty():
        _show_result(_failure("Import history payload is incomplete"))
        return
    var load_result: Dictionary = _world_resources.call("load_world", world_path)
    if not bool(load_result.get("ok", false)):
        _show_result(load_result)
        return
    var stored_world := load_result.get("world") as WorldData
    if stored_world == null or stored_world.world_id != expected_world_id:
        _show_result(_failure("Import history WorldData identity no longer matches"))
        return
    var candidate := stored_world.duplicate(true) as WorldData
    var restore_result: Dictionary = _model.restore_world_state(candidate, state)
    if not bool(restore_result.get("ok", false)):
        _show_result(restore_result)
        return
    var save_result: Dictionary = _world_resources.call("save_candidate", candidate, world_path)
    if bool(save_result.get("ok", false)):
        if world_data != null and world_data.resource_path == world_path:
            set_world_data(save_result.get("world") as WorldData, true)
    _show_result(save_result)


func _on_world_resource_changed(resource: Resource) -> void:
    set_world_data(resource as WorldData)


func _on_new_world_path_selected(path: String) -> void:
    var result: Dictionary = _world_resources.call("create_world", path)
    if bool(result.get("ok", false)):
        set_world_data(result.get("world") as WorldData)
    _show_result(result)


func _refresh_connection_options() -> void:
    _populate_option(source_entrance, [])
    _populate_option(target_room, [])
    _populate_option(target_spawn, [])
    if world_data == null:
        return
    var selected: Resource = world_data.get_room(selected_room_id)
    if selected != null:
        _populate_option(source_entrance, Array(selected.entrance_ids))
    _populate_option(target_room, world_data.get_room_ids())
    _refresh_target_spawns()


func _on_target_room_selected(_index: int) -> void:
    _refresh_target_spawns()


func _refresh_target_spawns() -> void:
    if not is_instance_valid(target_spawn):
        return
    var room: Resource = null if world_data == null else world_data.get_room(_selected_option_value(target_room))
    _populate_option(target_spawn, [] if room == null else Array(room.spawn_ids))


func _populate_option(option: OptionButton, values: Array) -> void:
    option.clear()
    for value: Variant in values:
        option.add_item(String(value))
        option.set_item_metadata(option.item_count - 1, String(value))


func _selected_option_value(option: OptionButton) -> String:
    if not is_instance_valid(option) or option.selected < 0:
        return ""
    return String(option.get_item_metadata(option.selected))


func _failure(message: String) -> Dictionary:
    return {
        "ok": false,
        "errors": [message],
        "warnings": [],
        "world": null,
        "path": "",
    }
