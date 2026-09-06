@tool
class_name WellwellWorldEditorDock
extends VBoxContainer

const WORLD_LAYOUT_MODEL := preload("res://scripts/authoring/world_layout_model.gd")
const WORLD_BAKER := preload("res://scripts/authoring/world_baker.gd")
const ROOM_BAKER := preload("res://scripts/authoring/room_baker.gd")
const CONNECTION_DATA := preload("res://scripts/world/room_connection_data.gd")
const TEMPLATE_SCENE_PATH := "res://scenes/templates/level_template.tscn"

var world_data: WorldData
var selected_room_id := ""
var _model: RefCounted = WORLD_LAYOUT_MODEL.new()
var _room_baker: Object = ROOM_BAKER.new()
var _undo_redo: Object
var _editor_interface: EditorInterface

@onready var canvas: Control = %LayoutCanvas
@onready var status_label: Label = %Status
@onready var source_entrance: OptionButton = %SourceEntrance
@onready var target_room: OptionButton = %TargetRoom
@onready var target_spawn: OptionButton = %TargetSpawn


func _ready() -> void:
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
	%AddExistingDialog.file_selected.connect(_add_existing_source)
	target_room.item_selected.connect(_on_target_room_selected)
	canvas.call("set_dock", self)
	_refresh()


func set_world_data(value: WorldData) -> void:
	world_data = value
	selected_room_id = ""
	_refresh()


func set_undo_redo_adapter(value: Object) -> void:
	_undo_redo = value


func set_editor_interface(value: EditorInterface) -> void:
	_editor_interface = value


func set_room_baker_adapter(value: Object) -> void:
	_room_baker = value


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


func add_existing() -> void:
	if world_data != null:
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


func _show_result(result: Dictionary) -> void:
	if not is_instance_valid(status_label):
		return
	var messages: Array = result.get("errors", []) if not result.get("ok", false) else result.get("warnings", [])
	status_label.text = "Ready" if messages.is_empty() else String(messages[0])


func _instantiate_selected_source() -> Node:
	var room: Resource = null if world_data == null else world_data.get_room(selected_room_id)
	if room == null or room.source_scene_path.is_empty():
		return null
	var packed := load(room.source_scene_path) as PackedScene
	return null if packed == null else packed.instantiate()


func _add_existing_source(path: String) -> void:
	if world_data == null:
		_show_result({"ok": false, "errors": ["No WorldData selected"], "warnings": []})
		return
	var packed := load(path) as PackedScene
	if packed == null:
		_show_result({"ok": false, "errors": ["Room source could not be loaded"], "warnings": []})
		return
	var source := packed.instantiate()
	var staged: Dictionary = _room_baker.call("stage", source, path)
	source.free()
	if not bool(staged.get("ok", false)):
		_show_result(staged)
		return
	var staged_room := staged.get("room_data") as RoomData
	var probe := world_data.duplicate(true) as WorldData
	var add_check: Dictionary = _model.add_room(probe, staged_room)
	if not bool(add_check.get("ok", false)):
		_show_result(add_check)
		return
	var result: Dictionary = _room_baker.call("save_staged", staged)
	if not bool(result.get("ok", false)):
		_show_result(result)
		return
	var outputs: Dictionary = result.get("outputs", {})
	var room := ResourceLoader.load(String(outputs.get("room_resource_path", "")), "RoomData", ResourceLoader.CACHE_MODE_IGNORE) as RoomData
	if room == null or not add_room(room):
		_show_result({"ok": false, "errors": ["Generated room could not be added to this world"], "warnings": []})
		return
	selected_room_id = room.room_id
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
