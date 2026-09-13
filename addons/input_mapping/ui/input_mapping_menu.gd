class_name InputMappingMenu
extends Control

signal back_requested

const MODEL := preload("res://addons/input_mapping/core/input_mapping_model.gd")
const BINDING_BUTTON_SCENE := preload("res://addons/input_mapping/ui/input_binding_button.tscn")

@export var included_actions: Array[StringName] = []
@export var excluded_actions: Array[StringName] = []
@export var preferred_action_order: Array[StringName] = []
@export var action_translation_prefix := "INPUT_ACTION_"

@onready var actions_grid: GridContainer = %ActionsGrid
@onready var empty_label: Label = %EmptyLabel
@onready var status_label: Label = %StatusLabel
@onready var reset_button: Button = %ResetButton
@onready var back_button: Button = %BackButton

var _service: Node
var _active_button: Button
var _binding_buttons: Array[Button] = []
var _action_labels: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	reset_button.pressed.connect(_reset_defaults)
	back_button.pressed.connect(_request_back)
	for button: Button in [reset_button, back_button]:
		button.mouse_entered.connect(button.grab_focus)
	if _service == null:
		bind_service(get_node_or_null("/root/InputMapping"))
	hide()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_dynamic_text()


func _unhandled_input(event: InputEvent) -> void:
	if visible and not is_capturing() and event.is_action_pressed("ui_cancel"):
		_request_back()
		get_viewport().set_input_as_handled()


func bind_service(service: Node) -> void:
	_disconnect_service()
	_service = service
	if _service == null:
		return
	var changed := Callable(self, "_on_mapping_changed")
	if _service.has_signal("mapping_changed") and not _service.is_connected("mapping_changed", changed):
		_service.connect("mapping_changed", changed)
	var reset := Callable(self, "_on_mappings_reset")
	if _service.has_signal("mappings_reset") and not _service.is_connected("mappings_reset", reset):
		_service.connect("mappings_reset", reset)
	var failed := Callable(self, "_on_persistence_failed")
	if _service.has_signal("persistence_failed") and not _service.is_connected("persistence_failed", failed):
		_service.connect("persistence_failed", failed)


func open_menu() -> void:
	if _service == null:
		bind_service(get_node_or_null("/root/InputMapping"))
	_build_rows()
	status_label.text = ""
	show()
	if not _binding_buttons.is_empty():
		_binding_buttons[0].grab_focus.call_deferred()
	else:
		back_button.grab_focus.call_deferred()


func is_capturing() -> bool:
	return _active_button != null and bool(_active_button.call("is_capturing"))


func _build_rows() -> void:
	_active_button = null
	_binding_buttons.clear()
	_action_labels.clear()
	for child: Node in actions_grid.get_children():
		child.free()
	var source: Array[StringName] = []
	if _service != null and _service.has_method("get_actions"):
		source = _service.call("get_actions")
	var actions := MODEL.discover_project_actions(
		source,
		included_actions,
		excluded_actions,
		preferred_action_order
	)
	empty_label.visible = actions.is_empty()
	actions_grid.visible = not actions.is_empty()
	for action: StringName in actions:
		var label := Label.new()
		label.custom_minimum_size = Vector2(200.0, 42.0)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.text = _action_display_name(action)
		actions_grid.add_child(label)
		_action_labels[action] = label
		for slot: int in [
			MODEL.BindingSlot.KEYBOARD_PRIMARY,
			MODEL.BindingSlot.KEYBOARD_SECONDARY,
			MODEL.BindingSlot.GAMEPAD,
		]:
			var button := BINDING_BUTTON_SCENE.instantiate() as Button
			actions_grid.add_child(button)
			button.call("configure", _service, action, slot)
			button.connect("capture_started", _on_capture_started)
			button.connect("capture_finished", _on_capture_finished)
			_binding_buttons.append(button)


func _action_display_name(action: StringName) -> String:
	var key := action_translation_prefix + String(action).to_upper().replace("-", "_").replace(" ", "_")
	var translated := tr(key)
	if translated != key:
		return translated
	return String(action).replace("_", " ").capitalize()


func _refresh_dynamic_text() -> void:
	for action: StringName in _action_labels:
		var label := _action_labels[action] as Label
		if is_instance_valid(label):
			label.text = _action_display_name(action)
	for button: Button in _binding_buttons:
		if is_instance_valid(button) and not bool(button.call("is_capturing")):
			button.call("refresh")


func _on_capture_started(button: Button) -> void:
	if _active_button != null and _active_button != button:
		_active_button.call("cancel_capture")
	_active_button = button
	status_label.text = tr("INPUT_MAPPING_PRESS_INPUT")


func _on_capture_finished(button: Button) -> void:
	if _active_button == button:
		_active_button = null
	status_label.text = ""
	button.grab_focus.call_deferred()


func _on_mapping_changed(action: StringName) -> void:
	for button: Button in _binding_buttons:
		if button.get("action") == action and not bool(button.call("is_capturing")):
			button.call("refresh")


func _on_mappings_reset() -> void:
	status_label.text = ""
	_refresh_dynamic_text()


func _on_persistence_failed(_message: String) -> void:
	status_label.text = tr("INPUT_MAPPING_SAVE_FAILED")


func _reset_defaults() -> void:
	if _service != null and _service.has_method("restore_defaults"):
		_service.call("restore_defaults")


func _request_back() -> void:
	if is_capturing():
		_active_button.call("cancel_capture")
		return
	hide()
	back_requested.emit()


func _disconnect_service() -> void:
	if _service == null or not is_instance_valid(_service):
		return
	for signal_name: StringName in [&"mapping_changed", &"mappings_reset", &"persistence_failed"]:
		var callable := Callable(self, "_on_%s" % signal_name)
		if _service.has_signal(signal_name) and _service.is_connected(signal_name, callable):
			_service.disconnect(signal_name, callable)
