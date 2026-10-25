@tool
class_name WorldRoomList
extends Tree

## Room list for the World editor: status dot, name, size, origin, status.
## Emits selection changes for the main screen; the main screen owns the actual
## selection model.

signal selection_changed(room_ids: Array, primary: String)
signal room_activated(room_id: String)
signal action_requested(action: StringName, room_id: String)

const STATUS_COLORS := {
    &"fresh": Color(0.31, 0.72, 0.45),
    &"stale": Color(0.88, 0.58, 0.24),
    &"error": Color(0.88, 0.35, 0.35),
    &"unknown": Color(0.55, 0.60, 0.68),
}
const ACTIONS: Array[Dictionary] = [
    {"action": &"open_source", "label": "Open Source"},
    {"action": &"bake", "label": "Bake"},
    {"action": &"validate", "label": "Validate"},
    {"action": &"focus", "label": "Focus in Canvas"},
    {"action": &"set_start", "label": "Set as Start"},
    {"action": &"remove", "label": "Remove Reference"},
]
const STATUS_COLUMN := 3

var _rooms: Array[RoomData] = []
var _statuses: Dictionary = {}
var _messages: Dictionary = {}
var _selected_ids: Array[String] = []
var _primary := ""
var _start_room_id := ""
var _filter := ""
var _updating := false
var _menu: PopupMenu
var _menu_room_id := ""


func _ready() -> void:
    columns = 4
    hide_root = true
    select_mode = Tree.SELECT_ROW
    column_titles_visible = true
    set_column_title(0, WorldEditorLocalization.t("WE_COL_ROOM"))
    set_column_title(1, WorldEditorLocalization.t("WE_COL_SIZE"))
    set_column_title(2, WorldEditorLocalization.t("WE_COL_ORIGIN"))
    set_column_title(3, WorldEditorLocalization.t("WE_COL_STATUS"))
    set_column_expand(0, true)
    set_column_expand(1, false)
    set_column_expand(2, false)
    set_column_expand(3, false)
    set_column_custom_minimum_width(1, 72)
    set_column_custom_minimum_width(2, 96)
    set_column_custom_minimum_width(3, 80)
    item_selected.connect(_on_item_selected)
    multi_selected.connect(_on_multi_selected)
    item_activated.connect(_on_item_activated)
    item_mouse_selected.connect(_on_item_mouse_selected)
    _menu = PopupMenu.new()
    _menu.name = "RoomMenu"
    add_child(_menu)
    for index in ACTIONS.size():
        _menu.add_item(_action_label(ACTIONS[index]["action"]), index)
    _menu.id_pressed.connect(_on_menu_id_pressed)


func set_rooms(
    rooms: Array[RoomData],
    statuses: Dictionary,
    messages: Dictionary,
    selected_ids: Array[String],
    primary: String,
    start_room_id: String
) -> void:
    _rooms = rooms.duplicate()
    _statuses = statuses
    _messages = messages
    _selected_ids = selected_ids.duplicate()
    _primary = primary
    _start_room_id = start_room_id
    _rebuild()


func set_selection(selected_ids: Array[String], primary: String) -> void:
    _selected_ids = selected_ids.duplicate()
    _primary = primary
    _rebuild()


func set_filter(text: String) -> void:
    if _filter == text:
        return
    _filter = text.to_lower()
    _rebuild()


func get_visible_room_ids() -> Array[String]:
    var ids: Array[String] = []
    for room: RoomData in _rooms:
        if _matches(room):
            ids.append(room.room_id)
    return ids


func _rebuild() -> void:
    _updating = true
    clear()
    var root: TreeItem = create_item()
    root.set_text(0, "")
    var sorted_rooms := _rooms.filter(func(room: RoomData) -> bool: return _matches(room))
    sorted_rooms.sort_custom(func(a: RoomData, b: RoomData) -> bool:
        return _sort_key(a) < _sort_key(b)
    )
    var primary_item: TreeItem = null
    for room: RoomData in sorted_rooms:
        var item: TreeItem = root.create_child()
        var status: StringName = _statuses.get(room.room_id, &"unknown")
        var star := " ★" if room.room_id == _start_room_id else ""
        item.set_text(0, "%s%s" % [_display_name(room), star])
        item.set_text(1, "%d×%d" % [room.room_size_chunks.x, room.room_size_chunks.y])
        var origin := _origin(room)
        item.set_text(2, "(%d,%d)" % [origin.x, origin.y])
        item.set_text(STATUS_COLUMN, _status_label(status))
        var color: Color = STATUS_COLORS.get(status, STATUS_COLORS[&"unknown"])
        item.set_custom_color(0, color)
        item.set_custom_color(STATUS_COLUMN, color)
        item.set_metadata(0, room.room_id)
        item.set_tooltip_text(0, "%s\n%s" % [room.room_id, String(_messages.get(room.room_id, ""))])
        for column in 4:
            item.set_selectable(column, true)
        if _selected_ids.has(room.room_id):
            item.select(0)
        if room.room_id == _primary:
            primary_item = item
    if primary_item != null:
        primary_item.select(0)
        scroll_to_item(primary_item)
    _updating = false


func _matches(room: RoomData) -> bool:
    if _filter.is_empty():
        return true
    return _display_name(room).to_lower().contains(_filter) or room.room_id.to_lower().contains(_filter)


func _status_label(state: StringName) -> String:
    match state:
        &"fresh":
            return WorldEditorLocalization.t("WE_STATUS_FRESH")
        &"stale":
            return WorldEditorLocalization.t("WE_STATUS_STALE")
        &"error":
            return WorldEditorLocalization.t("WE_STATUS_ERROR")
        _:
            return WorldEditorLocalization.t("WE_STATUS_UNKNOWN")


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
        &"set_start":
            return WorldEditorLocalization.t("WE_ACTION_SET_START")
        &"remove":
            return WorldEditorLocalization.t("WE_ACTION_REMOVE")
        _:
            return String(action)


func _display_name(room: RoomData) -> String:
    return room.room_id if room.display_name.is_empty() else room.display_name


func _sort_key(room: RoomData) -> String:
    return "%s\u001f%s" % [_display_name(room).to_lower(), room.room_id]


func _origin(room: RoomData) -> Vector2i:
    var main := _main_screen()
    if main == null or main.get("world_data") == null:
        return Vector2i.ZERO
    return (main.get("world_data") as WorldData).get_room_origin_chunk(room.room_id)


func _main_screen() -> Node:
    var node := get_parent()
    while node != null and not node.has_method("select_room"):
        node = node.get_parent()
    return node


func _on_item_selected() -> void:
    _emit_selection()


func _on_multi_selected(_item: TreeItem, _column: int, _selected: bool) -> void:
    _emit_selection()


func _emit_selection() -> void:
    if _updating:
        return
    var ids: Array[String] = []
    var item := get_next_selected(null)
    while item != null:
        var id := String(item.get_metadata(0))
        if not id.is_empty() and not ids.has(id):
            ids.append(id)
        item = get_next_selected(item)
    var primary := ""
    var current := get_selected()
    if current != null:
        primary = String(current.get_metadata(0))
    if primary.is_empty() and not ids.is_empty():
        primary = ids[0]
    selection_changed.emit(ids, primary)


func _on_item_activated() -> void:
    var item := get_selected()
    if item != null:
        var id := String(item.get_metadata(0))
        if not id.is_empty():
            room_activated.emit(id)


func _on_item_mouse_selected(position: Vector2, mouse_button_index: int) -> void:
    if mouse_button_index != MOUSE_BUTTON_RIGHT:
        return
    var item := get_item_at_position(position)
    if item == null:
        return
    var id := String(item.get_metadata(0))
    if id.is_empty():
        return
    _menu_room_id = id
    if not _selected_ids.has(id):
        item.select(0)
    _menu.position = Vector2i(get_screen_position() + position)
    _menu.popup()


func _on_menu_id_pressed(index: int) -> void:
    if index < 0 or index >= ACTIONS.size() or _menu_room_id.is_empty():
        return
    action_requested.emit(ACTIONS[index]["action"], _menu_room_id)
