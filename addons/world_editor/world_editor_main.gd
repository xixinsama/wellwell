@tool
class_name WorldEditorMain
extends VBoxContainer

const WORLD_LAYOUT_MODEL := preload("res://addons/world_editor/authoring/world/world_layout_model.gd")
const WORLD_BAKER := preload("res://addons/world_editor/authoring/world/world_baker.gd")
const ROOM_BAKER := preload("res://addons/world_editor/authoring/room/room_baker.gd")
const WORLD_RESOURCE_SERVICE := preload("res://addons/world_editor/authoring/world/world_resource_service.gd")
const WORLD_ROOM_IMPORTER := preload("res://addons/world_editor/authoring/world/world_room_importer.gd")
const CONNECTION_DATA := preload("res://addons/platformer_kit/world/data/room_connection_data.gd")
const TEMPLATE_SCENE_SETTING := "world_editor/room_template_scene"
const ROOM_STATUS := preload("res://addons/world_editor/authoring/world/room_status_service.gd")
const ROOM_ANNOTATIONS := preload("res://addons/world_editor/authoring/world/room_annotation_service.gd")

var world_data: WorldData
var selected_room_id := ""
var selected_room_ids: Array[String] = []
var room_statuses: Dictionary = {}
var room_status_messages: Dictionary = {}
var _model: RefCounted = WORLD_LAYOUT_MODEL.new()
var _room_baker: Object = ROOM_BAKER.new()
var _world_resources: Object = WORLD_RESOURCE_SERVICE.new()
var _world_room_importer: Object = WORLD_ROOM_IMPORTER.new()
var _undo_redo: Object
var _editor_interface: Object
var _transaction_busy := false
var _status := ROOM_STATUS.new()
var _annotations_service := ROOM_ANNOTATIONS.new()
var _annotations: Dictionary = {}
var _session_issues: Array[Dictionary] = []
var _world_report: Dictionary = {}

@onready var canvas: Control = %LayoutCanvas
@onready var status_label: Label = %Status
@onready var source_entrance: OptionButton = %SourceEntrance
@onready var target_room: OptionButton = %TargetRoom
@onready var target_spawn: OptionButton = %TargetSpawn
@onready var world_picker: Node = %WorldPicker
@onready var room_list: WorldRoomList = %RoomList
@onready var room_search: LineEdit = %RoomSearch
@onready var room_count: Label = %RoomCount
@onready var inspector: WorldRoomInspector = %InspectorPanel
@onready var problems_panel: WorldProblemsPanel = %ProblemsPanel
@onready var problems_badge: Button = %ProblemsBadge
@onready var selection_label: Label = %SelectionLabel
@onready var room_list_panel: VBoxContainer = %RoomListPanel
@onready var inspector_panel: VBoxContainer = %InspectorPanel


func _ready() -> void:
    %NewWorld.pressed.connect(new_world)
    %SaveWorld.pressed.connect(save_world)
    if is_instance_valid(world_picker) and world_picker.has_signal("resource_changed"):
        world_picker.connect("resource_changed", _on_world_resource_changed)
    %NewWorldDialog.file_selected.connect(_on_new_world_path_selected)
    %NewRoom.pressed.connect(new_room)
    %AddExisting.pressed.connect(add_existing)
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
    problems_panel.issue_activated.connect(_on_problem_activated)
    problems_panel.action_requested.connect(_on_room_action)
    problems_panel.revalidate_requested.connect(_revalidate)
    problems_badge.pressed.connect(_toggle_problems)
    %RoomsToggle.toggled.connect(func(on: bool) -> void: room_list_panel.visible = on)
    %InspectorToggle.toggled.connect(func(on: bool) -> void: inspector_panel.visible = on)
    %ProblemsToggle.toggled.connect(func(on: bool) -> void: problems_panel.visible = on)
    if canvas.has_signal("selection_changed"):
        canvas.connect("selection_changed", _on_canvas_selection_changed)
    if canvas.has_signal("delete_requested"):
        canvas.connect("delete_requested", delete_selected_rooms)
    canvas.call("set_main_screen", self)
    _localize_ui()
    _refresh()


func set_world_data(value: WorldData, preserve_selection := false) -> void:
    world_data = value
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
        _show_result(_failure(WorldEditorLocalization.t("WE_TEMPLATE_MISSING", [TEMPLATE_SCENE_SETTING])))
        return
    _editor_interface.open_scene_from_path(template_path, true)


func new_world() -> void:
    %NewWorldDialog.popup_centered_ratio(0.7)


func save_world() -> Dictionary:
    if world_data == null:
        var failure := _failure(WorldEditorLocalization.t("WE_NO_WORLD_DATA"))
        _show_result(failure)
        return failure
    var result: Dictionary = _world_resources.call("save_world", world_data)
    if bool(result.get("ok", false)):
        set_world_data(result.get("world") as WorldData, true)
    _show_result(result)
    return result


func focus_all() -> void:
    canvas.call("focus_all")


func reset_view() -> void:
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
        _show_result({"ok": false, "errors": [WorldEditorLocalization.t("WE_CONNECT_ENDPOINTS_MISSING")], "warnings": []})
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
    var result: Dictionary = _model.validate_world(world_data) if world_data != null else {"ok": false, "errors": [WorldEditorLocalization.t("WE_NO_WORLD_DATA")], "warnings": []}
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
        var failure := {"ok": false, "errors": [WorldEditorLocalization.t("WE_NO_ROOM_SOURCE")], "warnings": []}
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
    var result: Dictionary = _room_baker.call("bake", root, room.source_scene_path)
    root.free()
    if bool(result.get("ok", false)):
        var outputs: Dictionary = result.get("outputs", {})
        var baked_room := ResourceLoader.load(
            String(outputs.get("room_resource_path", "")),
            "RoomData",
            ResourceLoader.CACHE_MODE_IGNORE
        ) as RoomData
        if baked_room == null or not sync_room_resource(room_id, baked_room):
            result = {"ok": false, "errors": [WorldEditorLocalization.t("WE_SYNC_FAILED")], "warnings": result.get("warnings", [])}
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


func _localize_ui() -> void:
    var t := WorldEditorLocalization.t
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
    %ProblemsToggle.text = t.call("WE_PROBLEMS")
    %ProblemsToggle.tooltip_text = t.call("WE_TT_TOGGLE_PROBLEMS")
    %RoomSearch.placeholder_text = t.call("WE_SEARCH_ROOMS")
    %FocusAll.text = t.call("WE_FOCUS_ALL")
    %FocusAll.tooltip_text = t.call("WE_TT_FOCUS_ALL")
    %ResetView.text = t.call("WE_RESET_VIEW")
    %ResetView.tooltip_text = t.call("WE_TT_RESET_VIEW")
    %ProblemsBadge.tooltip_text = t.call("WE_TT_PROBLEMS_BADGE")
    %Connect.text = t.call("WE_CONNECT")
    %Disconnect.text = t.call("WE_DISCONNECT")
    %ConnectionsTitle.text = t.call("WE_CONNECTIONS")
    %AddExistingDialog.title = t.call("WE_DIALOG_ADD_EXISTING")
    %NewWorldDialog.title = t.call("WE_DIALOG_NEW_WORLD")


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
    if is_instance_valid(problems_panel):
        _refresh_problems()
    if is_instance_valid(canvas):
        if canvas.has_method("set_statuses"):
            canvas.call("set_statuses", room_statuses)
        if canvas.has_method("set_selection"):
            canvas.call("set_selection", selected_room_ids, selected_room_id)
        if canvas.has_method("set_annotations"):
            canvas.call("set_annotations", _annotations)
        if canvas.has_method("sync_preview"):
            canvas.call("sync_preview")
        canvas.queue_redraw()
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
    for room: RoomData in _sorted_rooms():
        var result: Dictionary = _status.evaluate(room)
        room_statuses[room.room_id] = result.get("state", &"unknown")
        var message := String(result.get("message", ""))
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


func _refresh_problems() -> void:
    if not is_instance_valid(problems_panel):
        return
    var issues: Array[Dictionary] = []
    var errors := 0
    var warnings := 0
    if world_data != null:
        _world_report = _model.validate_world(world_data)
        for message: Variant in _world_report.get("errors", []):
            issues.append({"severity": &"error", "message": String(message), "room_id": ""})
            errors += 1
        for message: Variant in _world_report.get("warnings", []):
            issues.append({"severity": &"warning", "message": String(message), "room_id": ""})
            warnings += 1
        for room_id: String in room_statuses:
            var state: StringName = room_statuses[room_id]
            if state == &"fresh":
                continue
            var severity := &"error" if state == &"error" else &"warning"
            var message := String(room_status_messages.get(room_id, ""))
            issues.append({"severity": severity, "message": message, "room_id": room_id})
            if severity == &"error":
                errors += 1
            else:
                warnings += 1
        for issue: Dictionary in _session_issues:
            issues.append(issue)
            if issue.get("severity", &"error") == &"error":
                errors += 1
            else:
                warnings += 1
    problems_panel.call("set_issues", issues, errors, warnings)
    if is_instance_valid(problems_badge):
        problems_badge.text = WorldEditorLocalization.t("WE_PROBLEMS_COUNT", [issues.size()])


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


func _on_problem_activated(room_id: String) -> void:
    select_room(room_id)
    if is_instance_valid(canvas) and canvas.has_method("focus_room"):
        canvas.call("focus_room", room_id)


func _revalidate() -> void:
    _refresh()


func _toggle_problems() -> void:
    if not is_instance_valid(problems_panel):
        return
    problems_panel.visible = not problems_panel.visible
    %ProblemsToggle.set_pressed_no_signal(problems_panel.visible)


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
    for warning: Variant in warnings:
        details.append("Warning: %s" % String(warning))
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


func _add_existing_source(path: String) -> void:
    if world_data == null or world_data.resource_path.is_empty() or not FileAccess.file_exists(world_data.resource_path):
        _show_result(_failure(WorldEditorLocalization.t("WE_SAVE_WORLD_FIRST")))
        return
    if _transaction_busy:
        _show_result(_failure(WorldEditorLocalization.t("WE_TRANSACTION_BUSY")))
        return
    _set_transaction_busy(true)
    var source := _load_room_source(path)
    var result: Dictionary
    if source == null:
        result = _failure(WorldEditorLocalization.t("WE_ROOM_SOURCE_LOAD_FAILED", [path]))
    else:
        result = _world_room_importer.call("import_room", world_data, source, path)
        source.free()
    if bool(result.get("ok", false)):
        var imported_world := result.get("world") as WorldData
        var imported_room := result.get("room") as RoomData
        if imported_world == null or imported_room == null:
            result = _failure(WorldEditorLocalization.t("WE_IMPORT_INCOMPLETE"))
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
    for button: Button in [%Connect, %Disconnect]:
        button.disabled = not bool(state["has_selection"]) or bool(state["transaction_busy"])
    for option: OptionButton in [source_entrance, target_room, target_spawn]:
        option.disabled = not bool(state["has_selection"])
    %NewRoom.disabled = bool(state["transaction_busy"])
    %NewWorld.disabled = bool(state["transaction_busy"])


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
        _show_result(_failure(WorldEditorLocalization.t("WE_IMPORT_HISTORY_INCOMPLETE")))
        return
    var load_result: Dictionary = _world_resources.call("load_world", world_path)
    if not bool(load_result.get("ok", false)):
        _show_result(load_result)
        return
    var stored_world := load_result.get("world") as WorldData
    if stored_world == null or stored_world.world_id != expected_world_id:
        _show_result(_failure(WorldEditorLocalization.t("WE_IMPORT_HISTORY_MISMATCH")))
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
