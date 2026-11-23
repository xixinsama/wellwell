class_name InputBindingButton
extends Button

signal capture_started(button: InputBindingButton)
signal capture_finished(button: InputBindingButton)

const MODEL := preload("res://addons/input_mapping/core/input_mapping_model.gd")
const FORMATTER := preload("res://addons/input_mapping/ui/input_event_formatter.gd")

var action: StringName
var slot := MODEL.BindingSlot.KEYBOARD_PRIMARY
var _service: Node
var _capturing := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	pressed.connect(begin_capture)
	mouse_entered.connect(_on_mouse_entered)
	set_process_unhandled_input(false)
	refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and not _capturing:
		refresh()


func configure(service: Node, action_name: StringName, binding_slot: int) -> void:
	_service = service
	action = action_name
	slot = binding_slot
	refresh()


func begin_capture() -> void:
	if _service == null or action.is_empty():
		return
	_capturing = true
	text = tr("INPUT_MAPPING_PRESS_INPUT")
	release_focus()
	set_process_unhandled_input(true)
	capture_started.emit(self)


func cancel_capture() -> void:
	if not _capturing:
		return
	_capturing = false
	set_process_unhandled_input(false)
	refresh()
	capture_finished.emit(self)


func finish_capture() -> void:
	if not _capturing:
		return
	_capturing = false
	set_process_unhandled_input(false)
	refresh()
	capture_finished.emit(self)


func is_capturing() -> bool:
	return _capturing


func consume_capture_event(event: InputEvent) -> bool:
	if not _capturing:
		return false
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return false
		var code := key_event.physical_keycode if key_event.physical_keycode != KEY_NONE else key_event.keycode
		if code == KEY_ESCAPE:
			cancel_capture()
			return true
		if code == KEY_BACKSPACE or code == KEY_DELETE:
			_service.call("clear_slot", action, slot)
			finish_capture()
			return true
	if not MODEL.is_event_compatible(event, slot):
		return false
	_service.call("replace_slot", action, slot, MODEL.normalize_event(event))
	finish_capture()
	return true


func refresh() -> void:
	if _service == null or action.is_empty() or not _service.has_method("get_slot_events"):
		text = tr("INPUT_MAPPING_UNBOUND")
		return
	var events: Array[InputEvent] = _service.call("get_slot_events", action, slot)
	text = FORMATTER.format_events(events)
	tooltip_text = text


func _unhandled_input(event: InputEvent) -> void:
	if consume_capture_event(event):
		get_viewport().set_input_as_handled()


func _on_mouse_entered() -> void:
	if not _capturing:
		grab_focus()
