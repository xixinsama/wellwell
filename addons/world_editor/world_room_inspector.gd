@tool
class_name WorldRoomInspector
extends VBoxContainer

## Read-only room inspector for the World editor. Metadata stays authorative in
## the source scene; this panel only shows state and offers actions.

signal action_requested(action: StringName, room_id: String)

const STATUS_COLORS := {
	&"fresh": Color(0.31, 0.72, 0.45),
	&"stale": Color(0.88, 0.58, 0.24),
	&"error": Color(0.88, 0.35, 0.35),
	&"unknown": Color(0.55, 0.60, 0.68),
}
const FIELD_WIDTH := 86.0
const VALUE_COLOR := Color(0.82, 0.86, 0.93)
const MUTED_COLOR := Color(0.58, 0.64, 0.73)

var _room_id := ""
var _content: VBoxContainer
var _spawn_picker: OptionButton


func _ready() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "InspectorScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	move_child(scroll, 0)
	_content = VBoxContainer.new()
	_content.name = "InspectorContent"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 6)
	scroll.add_child(_content)
	clear()


func clear() -> void:
	_room_id = ""
	_spawn_picker = null
	_clear_content()
	var hint := Label.new()
	hint.text = WorldEditorLocalization.t("WE_SELECT_ROOM_HINT")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", MUTED_COLOR)
	_content.add_child(hint)


func show_room(
	room: RoomData,
	status: StringName,
	message: String,
	connections: Array,
	start_room_id: String,
	start_spawn_id: String
) -> void:
	_room_id = room.room_id
	_clear_content()

	var title := Label.new()
	title.text = room.room_id if room.display_name.is_empty() else room.display_name
	title.add_theme_font_size_override("font_size", 16)
	_content.add_child(title)

	_content.add_child(_label(room.room_id, 12, MUTED_COLOR))

	var status_label := _label(message, 13, STATUS_COLORS.get(status, STATUS_COLORS[&"unknown"]))
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(status_label)

	_content.add_child(HSeparator.new())
	_add_field(WorldEditorLocalization.t("WE_FIELD_SIZE"), "%d×%d chunks · %d×%d px" % [
		room.room_size_chunks.x,
		room.room_size_chunks.y,
		room.room_size_chunks.x * 320,
		room.room_size_chunks.y * 180,
	])
	var origin := _origin(room)
	_add_field(WorldEditorLocalization.t("WE_FIELD_ORIGIN"), "(%d, %d) chunks" % [origin.x, origin.y])
	_add_field(WorldEditorLocalization.t("WE_FIELD_SOURCE"), _short_path(room.source_scene_path))
	_add_field(WorldEditorLocalization.t("WE_FIELD_RUNTIME"), _short_path(room.scene_path))
	_add_field(WorldEditorLocalization.t("WE_FIELD_TERRAIN"), _short_path(room.terrain_scene_path))
	if not room.tags.is_empty():
		_add_field(WorldEditorLocalization.t("WE_FIELD_TAGS"), ", ".join(room.tags))

	if not room.spawn_ids.is_empty():
		_content.add_child(HSeparator.new())
		_content.add_child(_section_label(WorldEditorLocalization.t("WE_SPAWNS")))
		for spawn_id: String in room.spawn_ids:
			var marker := " ★" if room.room_id == start_room_id and spawn_id == start_spawn_id else ""
			_content.add_child(_label("S · %s%s" % [spawn_id, marker], 13, Color(0.72, 0.85, 0.78)))

	if not room.entrance_ids.is_empty():
		_content.add_child(HSeparator.new())
		_content.add_child(_section_label(WorldEditorLocalization.t("WE_ENTRANCES")))
		for entrance_id: String in room.entrance_ids:
			_content.add_child(_label(
				"E · %s%s" % [entrance_id, _connection_target(connections, room.room_id, entrance_id)],
				13,
				Color(0.92, 0.82, 0.64)
			))

	_content.add_child(HSeparator.new())
	_add_actions([&"open_source", &"bake", &"validate", &"focus", &"remove"])
	_content.add_child(HSeparator.new())
	_add_start_row(room, start_room_id, start_spawn_id)


func show_multi(rooms: Array[RoomData], statuses: Dictionary) -> void:
	_room_id = ""
	_clear_content()
	var title := Label.new()
	title.text = WorldEditorLocalization.t("WE_MULTI_ROOMS_SELECTED", [rooms.size()])
	title.add_theme_font_size_override("font_size", 16)
	_content.add_child(title)
	var counts := {&"fresh": 0, &"stale": 0, &"error": 0, &"unknown": 0}
	for room: RoomData in rooms:
		var status: StringName = statuses.get(room.room_id, &"unknown")
		counts[status] = int(counts.get(status, 0)) + 1
	_content.add_child(_label(WorldEditorLocalization.t("WE_MULTI_SUMMARY", [
		int(counts[&"fresh"]), int(counts[&"stale"]), int(counts[&"error"]), int(counts[&"unknown"]),
	]), 13, VALUE_COLOR))
	_content.add_child(HSeparator.new())
	var shown := 0
	for room: RoomData in rooms:
		if shown >= 8:
			_content.add_child(_label(WorldEditorLocalization.t("WE_MORE", [rooms.size() - shown]), 12, MUTED_COLOR))
			break
		var status: StringName = statuses.get(room.room_id, &"unknown")
		_content.add_child(_label(
			"● %s" % room.room_id,
			13,
			STATUS_COLORS.get(status, STATUS_COLORS[&"unknown"])
		))
		shown += 1
	_content.add_child(HSeparator.new())
	_add_actions([&"bake_selected", &"validate_selected", &"remove_selected", &"open_first"])


## Spawn selected in the "Set as Start" row, or "" when unavailable.
func get_selected_spawn_id() -> String:
	if _spawn_picker == null:
		return ""
	var index := _spawn_picker.selected
	if index < 0:
		return ""
	return String(_spawn_picker.get_item_metadata(index))


# --- Builders -----------------------------------------------------------------

func _clear_content() -> void:
	if _content == null:
		return
	for child: Node in _content.get_children():
		child.free()


func _label(text: String, font_size: int = 13, color: Color = VALUE_COLOR) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _section_label(text: String) -> Label:
	return _label(text.to_upper(), 11, MUTED_COLOR)


func _add_field(field: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var name_label := _label(field, 12, MUTED_COLOR)
	name_label.custom_minimum_size.x = FIELD_WIDTH
	row.add_child(name_label)
	var value_label := _label(value, 13)
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.tooltip_text = value
	row.add_child(value_label)
	_content.add_child(row)


func _add_actions(actions: Array) -> void:
	var row := HFlowContainer.new()
	for action: StringName in actions:
		var button := Button.new()
		button.text = _action_label(action)
		button.tooltip_text = button.text
		button.pressed.connect(func() -> void: action_requested.emit(action, _room_id))
		row.add_child(button)
	_content.add_child(row)


func _add_start_row(room: RoomData, start_room_id: String, start_spawn_id: String) -> void:
	var row := HFlowContainer.new()
	row.add_child(_label(WorldEditorLocalization.t("WE_START"), 12, MUTED_COLOR))
	_spawn_picker = OptionButton.new()
	_spawn_picker.name = "StartSpawnPicker"
	var spawns := room.spawn_ids
	if spawns.is_empty():
		_spawn_picker.disabled = true
	for index in spawns.size():
		_spawn_picker.add_item(spawns[index], index)
		_spawn_picker.set_item_metadata(index, spawns[index])
	var preferred := start_spawn_id if room.room_id == start_room_id else ""
	if preferred.is_empty() and not spawns.is_empty():
		preferred = spawns[0]
	for index in spawns.size():
		if spawns[index] == preferred:
			_spawn_picker.select(index)
			break
	row.add_child(_spawn_picker)
	var button := Button.new()
	button.text = WorldEditorLocalization.t("WE_SET_AS_START")
	button.disabled = spawns.is_empty()
	button.pressed.connect(func() -> void: action_requested.emit(&"set_start", _room_id))
	row.add_child(button)
	_content.add_child(row)


func _action_label(action: StringName) -> String:
	match action:
		&"open_source":
			return WorldEditorLocalization.t("WE_ACTION_OPEN_SOURCE")
		&"bake":
			return WorldEditorLocalization.t("WE_ACTION_BAKE")
		&"validate":
			return WorldEditorLocalization.t("WE_ACTION_VALIDATE")
		&"focus":
			return WorldEditorLocalization.t("WE_ACTION_FOCUS")
		&"remove":
			return WorldEditorLocalization.t("WE_ACTION_REMOVE")
		&"set_start":
			return WorldEditorLocalization.t("WE_SET_AS_START")
		&"bake_selected":
			return WorldEditorLocalization.t("WE_ACTION_BAKE_SELECTED")
		&"validate_selected":
			return WorldEditorLocalization.t("WE_ACTION_VALIDATE_SELECTED")
		&"remove_selected":
			return WorldEditorLocalization.t("WE_ACTION_REMOVE_SELECTED")
		&"open_first":
			return WorldEditorLocalization.t("WE_ACTION_OPEN_FIRST")
		_:
			return String(action)


func _connection_target(connections: Array, room_id: String, entrance_id: String) -> String:
	for value: Resource in connections:
		if value is RoomConnectionData:
			var connection := value as RoomConnectionData
			if connection.from_room_id == room_id and connection.from_entrance_id == entrance_id:
				return "  →  %s / %s" % [connection.to_room_id, connection.to_spawn_id]
	return ""


func _origin(room: RoomData) -> Vector2i:
	var main := _main_screen()
	if main == null or main.get("world_data") == null:
		return Vector2i.ZERO
	return (main.get("world_data") as WorldData).get_room_origin_chunk(room.room_id)


func _short_path(path: String) -> String:
	if path.is_empty():
		return "—"
	return path.trim_prefix("res://")


func _main_screen() -> Node:
	var node := get_parent()
	while node != null and not node.has_method("select_room"):
		node = node.get_parent()
	return node
