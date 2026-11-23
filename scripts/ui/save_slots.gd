class_name SaveSlots
extends Control

signal slot_chosen(slot: int)
signal back_requested

@export_range(1, 9, 1) var slot_count := 3

@onready var list: VBoxContainer = %SlotList
@onready var return_button: Button = %ReturnButton
@onready var copy_dialog: ConfirmationDialog = %CopyDialog
@onready var copy_target: OptionButton = %CopyTarget
@onready var delete_dialog: ConfirmationDialog = %DeleteDialog
@onready var status_label: Label = %StatusLabel

var _source_slot := 0
var _delete_slot := 0

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    return_button.pressed.connect(_request_back)
    return_button.mouse_entered.connect(return_button.grab_focus)
    copy_dialog.confirmed.connect(_confirm_copy)
    delete_dialog.confirmed.connect(_confirm_delete)
    hide()

func _notification(what: int) -> void:
    if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and visible:
        _refresh()

func _unhandled_input(event: InputEvent) -> void:
    if visible and event.is_action_pressed("ui_cancel"):
        _request_back()
        get_viewport().set_input_as_handled()

func show_slots() -> void:
    show()
    _refresh()
    var first_button := list.find_child("PrimaryButton", true, false) as Button
    if first_button != null:
        first_button.grab_focus.call_deferred()

func show_start_error(details: String = "") -> void:
    show()
    status_label.text = tr("SLOT_START_FAILED") if details.is_empty() else "%s %s" % [tr("SLOT_START_FAILED"), details]

func _refresh() -> void:
    status_label.text = ""
    for child: Node in list.get_children():
        list.remove_child(child)
        child.queue_free()
    for slot: int in range(1, slot_count + 1):
        list.add_child(_build_slot_row(slot))

func _build_slot_row(slot: int) -> Control:
    var manager := get_node_or_null("/root/SaveManager")
    var summary: Dictionary = {"slot": slot, "occupied": false}
    if manager != null:
        summary = manager.get_slot_summary(slot)

    var row := HBoxContainer.new()
    row.name = "Slot%d" % slot
    row.custom_minimum_size = Vector2(640.0, 86.0)
    row.add_theme_constant_override("separation", 12)

    var info := VBoxContainer.new()
    info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var slot_label := Label.new()
    slot_label.add_theme_font_size_override("font_size", 21)
    slot_label.text = tr("SLOT_NUMBER").format({"slot": slot})
    info.add_child(slot_label)
    var details := Label.new()
    details.modulate = Color(0.68, 0.75, 0.78)
    details.text = _slot_details(summary)
    info.add_child(details)
    row.add_child(info)

    var primary := Button.new()
    primary.name = "PrimaryButton"
    primary.custom_minimum_size = Vector2(112.0, 46.0)
    primary.text = tr("SLOT_CONTINUE") if bool(summary.get("occupied", false)) else tr("SLOT_NEW_GAME")
    primary.pressed.connect(func() -> void: slot_chosen.emit(slot))
    _add_hover_focus(primary)
    row.add_child(primary)

    var copy_button := Button.new()
    copy_button.custom_minimum_size = Vector2(82.0, 46.0)
    copy_button.text = tr("SLOT_COPY")
    copy_button.disabled = not bool(summary.get("occupied", false))
    copy_button.pressed.connect(func() -> void: _open_copy_dialog(slot))
    _add_hover_focus(copy_button)
    row.add_child(copy_button)

    var delete_button := Button.new()
    delete_button.custom_minimum_size = Vector2(82.0, 46.0)
    delete_button.text = tr("SLOT_DELETE")
    delete_button.disabled = not bool(summary.get("occupied", false))
    delete_button.pressed.connect(func() -> void: _open_delete_dialog(slot))
    _add_hover_focus(delete_button)
    row.add_child(delete_button)
    return row

func _slot_details(summary: Dictionary) -> String:
    if not bool(summary.get("occupied", false)):
        return tr("SLOT_EMPTY")
    var room_id := String(summary.get("room_id", "-"))
    if room_id.is_empty():
        room_id = "-"
    var timestamp := int(summary.get("saved_unix_time", 0))
    var time_text := "-" if timestamp <= 0 else _format_timestamp(timestamp)
    return "%s    %s" % [
        tr("SLOT_ROOM").format({"room": room_id}),
        tr("SLOT_SAVED").format({"time": time_text}),
    ]

func _format_timestamp(timestamp: int) -> String:
    var time_zone: Dictionary = Time.get_time_zone_from_system()
    var local_timestamp := timestamp + int(time_zone.get("bias", 0)) * 60
    var value := Time.get_datetime_dict_from_unix_time(local_timestamp)
    return "%04d-%02d-%02d %02d:%02d" % [value.year, value.month, value.day, value.hour, value.minute]

func _open_copy_dialog(slot: int) -> void:
    _source_slot = slot
    copy_target.clear()
    for target: int in range(1, slot_count + 1):
        if target == slot:
            continue
        copy_target.add_item(tr("SLOT_COPY_TO").format({"slot": target}), target)
    copy_dialog.title = tr("SLOT_COPY_TITLE")
    copy_dialog.dialog_text = tr("SLOT_COPY_MESSAGE")
    copy_dialog.popup_centered()

func _confirm_copy() -> void:
    if copy_target.item_count == 0:
        return
    var target_slot := copy_target.get_item_id(copy_target.selected)
    var manager := get_node_or_null("/root/SaveManager")
    if manager == null or not manager.copy_slot(_source_slot, target_slot):
        status_label.text = tr("SLOT_COPY_FAILED")
        return
    _refresh()

func _open_delete_dialog(slot: int) -> void:
    _delete_slot = slot
    delete_dialog.title = tr("SLOT_DELETE_TITLE")
    delete_dialog.dialog_text = tr("SLOT_DELETE_MESSAGE").format({"slot": slot})
    delete_dialog.popup_centered()

func _confirm_delete() -> void:
    var manager := get_node_or_null("/root/SaveManager")
    if manager == null or not manager.delete_slot(_delete_slot):
        status_label.text = tr("SLOT_DELETE_FAILED")
        return
    _refresh()

func _request_back() -> void:
    hide()
    back_requested.emit()

func _add_hover_focus(button: Button) -> void:
    button.mouse_entered.connect(button.grab_focus)
