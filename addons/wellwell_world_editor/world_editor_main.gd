@tool
class_name WorldEditorMain
extends VBoxContainer

const WORLD_LAYOUT_MODEL := preload("res://scripts/authoring/world_layout_model.gd")
const WORLD_BAKER := preload("res://scripts/authoring/world_baker.gd")
const ROOM_BAKER := preload("res://scripts/authoring/room_baker.gd")
const WORLD_RESOURCE_SERVICE := preload("res://scripts/authoring/world_resource_service.gd")
const WORLD_ROOM_IMPORTER := preload("res://scripts/authoring/world_room_importer.gd")
const CONNECTION_DATA := preload("res://scripts/world/room_connection_data.gd")
const TEMPLATE_SCENE_PATH := "res://scenes/templates/level_template.tscn"

var world_data: WorldData
var selected_room_id := ""
var _model: RefCounted = WORLD_LAYOUT_MODEL.new()
var _room_baker: Object = ROOM_BAKER.new()
var _world_resources: Object = WORLD_RESOURCE_SERVICE.new()
var _world_room_importer: Object = WORLD_ROOM_IMPORTER.new()
var _undo_redo: Object
var _editor_interface: Object
var _transaction_busy := false

@onready var canvas: Control = %LayoutCanvas
@onready var status_label: Label = %Status
@onready var source_entrance: OptionButton = %SourceEntrance
@onready var target_room: OptionButton = %TargetRoom
@onready var target_spawn: OptionButton = %TargetSpawn
@onready var world_picker: EditorResourcePicker = %WorldPicker


func _ready() -> void:
	%NewWorld.pressed.connect(new_world)
	%SaveWorld.pressed.connect(save_world)
	world_picker.resource_changed.connect(_on_world_resource_changed)
	%NewWorldDialog.file_selected.connect(_on_new_world_path_selected)
	%NewRoom.pressed.connect(new_room)
	%AddExisting.pressed.connect(add_existing)
	%RemoveReference.pressed.connect(remove_selected_room)
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
	canvas.call("set_main_screen", self)
	_refresh()


func set_world_data(value: WorldData, preserve_selection := false) -> void:
	world_data = value
	if not preserve_selection or world_data == null or not world_data.has_room(selected_room_id):
		selected_room_id = ""
	if is_instance_valid(world_picker) and world_picker.edited_resource != world_data:
		world_picker.edited_resource = world_data
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
	selected_room_id = room_id
	_refresh()


func move_room(room_id: String, origin_chunk: Vector2i) -> bool:
	if world_data == null or _undo_redo == null:
		return false
	var room: Resource = world_data.get_room(room_id)
	if room == null or room.room_origin_chunk == origin_chunk:
		return room != null
	_undo_redo.create_action("Move Room")
	_undo_redo.add_do_method(self, "_apply_move", room_id, origin_chunk)
	_undo_redo.add_undo_method(self, "_apply_move", room_id, room.room_origin_chunk)
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
	if _editor_interface != null:
		_editor_interface.open_scene_from_path(TEMPLATE_SCENE_PATH, true)


func new_world() -> void:
	%NewWorldDialog.popup_centered_ratio(0.7)


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
	_show_result(result)
	return result


func bake_world() -> Dictionary:
	var result: Dictionary = WORLD_BAKER.new().bake(world_data) if world_data != null else {"ok": false, "errors": ["No WorldData selected"], "warnings": []}
	_show_result(result)
	return result


func validate_selected_room() -> Dictionary:
	var source := _instantiate_selected_source()
	if source == null:
		var failure := {"ok": false, "errors": ["No room source selected"], "warnings": []}
		_show_result(failure)
		return failure
	var result: Dictionary = _room_baker.call("validate", source)
	source.free()
	_show_result(result)
	return result


func bake_selected_room() -> Dictionary:
	var room: Resource = null if world_data == null else world_data.get_room(selected_room_id)
	var root := _instantiate_selected_source()
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
		if baked_room == null or not sync_room_resource(selected_room_id, baked_room):
			result = {"ok": false, "errors": ["Baked RoomData could not be synchronized"], "warnings": result.get("warnings", [])}
	_show_result(result)
	return result


func sync_room_resource(room_id: String, baked_room: RoomData) -> bool:
	if world_data == null or baked_room == null:
		return false
	var result: Dictionary = _model.replace_room(world_data, room_id, baked_room)
	_mark_changed(result)
	_refresh()
	return bool(result.get("ok", false))


func open_selected_source() -> void:
	var room: Resource = null if world_data == null else world_data.get_room(selected_room_id)
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


func _refresh() -> void:
	if is_instance_valid(canvas):
		canvas.queue_redraw()
	if is_instance_valid(source_entrance):
		_refresh_connection_options()
	if is_instance_valid(status_label):
		status_label.text = "No world selected" if world_data == null else "%d rooms" % world_data.rooms.size()
	_refresh_command_state()


func _show_result(result: Dictionary) -> void:
	if not is_instance_valid(status_label):
		return
	var errors: Array = result.get("errors", [])
	var warnings: Array = result.get("warnings", [])
	var messages: Array = errors if not result.get("ok", false) else warnings
	status_label.text = "Completed" if messages.is_empty() else String(messages[0])
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
	var room: Resource = null if world_data == null else world_data.get_room(selected_room_id)
	if room == null or room.source_scene_path.is_empty():
		return null
	var packed := load(room.source_scene_path) as PackedScene
	return null if packed == null else packed.instantiate()


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
		result = _world_room_importer.call("import_room", world_data, source, path)
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
	var add_tooltip := "Add an authored room scene"
	if not has_world:
		add_tooltip = "Select or create a WorldData resource first"
	elif not has_saved_world:
		add_tooltip = "Save the selected WorldData resource first"
	elif _transaction_busy:
		add_tooltip = "Another world transaction is already running"
	return {
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
	for button: Button in [%RemoveReference, %OpenSource, %ValidateRoom, %BakeRoom, %Connect, %Disconnect]:
		button.disabled = bool(state["room_command_disabled"])
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
