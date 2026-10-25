@tool
class_name WorldProblemsPanel
extends VBoxContainer

## Problems panel for the World editor: room statuses, session bake/validate
## results and world validation messages, with filtering and quick actions.

signal issue_activated(room_id: String)
signal action_requested(action: StringName, room_id: String)
signal revalidate_requested

const SEVERITY_COLORS := {
    &"error": Color(0.88, 0.35, 0.35),
    &"warning": Color(0.88, 0.58, 0.24),
    &"info": Color(0.72, 0.78, 0.88),
}
const SEVERITY_MARKS := {&"error": "✕", &"warning": "!", &"info": "·"}

var _issues: Array[Dictionary] = []
var _filter := 0
var _title: Label
var _list: ItemList
var _empty: Label
var _open_button: Button
var _bake_button: Button


func _ready() -> void:
    var header := HBoxContainer.new()
    header.name = "ProblemsHeader"
    add_child(header)

    _title = Label.new()
    _title.text = WorldEditorLocalization.t("WE_PROBLEMS")
    _title.add_theme_font_size_override("font_size", 11)
    _title.add_theme_color_override("font_color", Color(0.72, 0.78, 0.88))
    header.add_child(_title)

    var spacer := Control.new()
    spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(spacer)

    var filter := OptionButton.new()
    filter.name = "ProblemsFilter"
    filter.add_item(WorldEditorLocalization.t("WE_FILTER_ALL"), 0)
    filter.add_item(WorldEditorLocalization.t("WE_FILTER_ERRORS"), 1)
    filter.add_item(WorldEditorLocalization.t("WE_FILTER_WARNINGS"), 2)
    filter.item_selected.connect(_on_filter_selected)
    header.add_child(filter)

    _open_button = Button.new()
    _open_button.text = WorldEditorLocalization.t("WE_ACTION_OPEN_SOURCE")
    _open_button.disabled = true
    _open_button.pressed.connect(func() -> void: _emit_action(&"open_source"))
    header.add_child(_open_button)

    _bake_button = Button.new()
    _bake_button.text = WorldEditorLocalization.t("WE_ACTION_BAKE")
    _bake_button.disabled = true
    _bake_button.pressed.connect(func() -> void: _emit_action(&"bake"))
    header.add_child(_bake_button)

    var revalidate := Button.new()
    revalidate.text = WorldEditorLocalization.t("WE_REVALIDATE")
    revalidate.pressed.connect(func() -> void: revalidate_requested.emit())
    header.add_child(revalidate)

    _list = ItemList.new()
    _list.name = "ProblemsList"
    _list.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _list.auto_height = false
    _list.item_selected.connect(_on_item_selected)
    _list.item_activated.connect(_on_item_activated)
    add_child(_list)

    _empty = Label.new()
    _empty.text = WorldEditorLocalization.t("WE_NO_PROBLEMS")
    _empty.add_theme_color_override("font_color", Color(0.50, 0.58, 0.50))
    add_child(_empty)
    _rebuild()


func set_issues(issues: Array[Dictionary], error_count: int, warning_count: int) -> void:
    _issues = issues.duplicate(true)
    _title.text = WorldEditorLocalization.t("WE_PROBLEMS_TITLE", [error_count, warning_count])
    _rebuild()


func get_issue_count() -> int:
    return _issues.size()


func _rebuild() -> void:
    if _list == null:
        return
    _list.clear()
    _open_button.disabled = true
    _bake_button.disabled = true
    var visible_count := 0
    for index in _issues.size():
        var issue: Dictionary = _issues[index]
        var severity: StringName = issue.get("severity", &"info")
        if _filter == 1 and severity != &"error":
            continue
        if _filter == 2 and severity != &"warning":
            continue
        var room_id := String(issue.get("room_id", ""))
        var mark := String(SEVERITY_MARKS.get(severity, "·"))
        var text := "%s  %s" % [mark, String(issue.get("message", ""))]
        if not room_id.is_empty():
            text += "   [%s]" % room_id
        var item := _list.add_item(text)
        _list.set_item_custom_fg_color(item, SEVERITY_COLORS.get(severity, SEVERITY_COLORS[&"info"]))
        _list.set_item_metadata(item, index)
        if not room_id.is_empty():
            _list.set_item_tooltip(item, WorldEditorLocalization.t("WE_DOUBLE_CLICK_FOCUS", [room_id]))
        visible_count += 1
    _list.visible = visible_count > 0
    _empty.visible = visible_count == 0


func _on_filter_selected(index: int) -> void:
    _filter = index
    _rebuild()


func _on_item_selected(index: int) -> void:
    var room_id := _selected_issue_room()
    _open_button.disabled = room_id.is_empty()
    _bake_button.disabled = room_id.is_empty()


func _on_item_activated(index: int) -> void:
    var room_id := _selected_issue_room()
    if not room_id.is_empty():
        issue_activated.emit(room_id)


func _selected_issue() -> Dictionary:
    var selected := _list.get_selected_items()
    if selected.is_empty():
        return {}
    var item_index := selected[0]
    var issue_index := int(_list.get_item_metadata(item_index))
    if issue_index < 0 or issue_index >= _issues.size():
        return {}
    return _issues[issue_index]


func _selected_issue_room() -> String:
    return String(_selected_issue().get("room_id", ""))


func _emit_action(action: StringName) -> void:
    var room_id := _selected_issue_room()
    if not room_id.is_empty():
        action_requested.emit(action, room_id)
