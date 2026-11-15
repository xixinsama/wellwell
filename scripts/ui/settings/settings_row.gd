class_name SettingsRow
extends HBoxContainer

signal value_changed(key: StringName, value: Variant)
signal action_pressed(key: StringName)

const DEFINITION: Script = preload("res://scripts/save/settings_definition.gd")

@onready var label: Label = %RowLabel
@onready var control_host: HBoxContainer = %ControlHost

var _definition: SettingsDefinition
var _service: Node
var _control: Control
var _value_label: Label
var _syncing := false


func configure(definition: SettingsDefinition, service: Node) -> void:
	_definition = definition
	_service = service
	_build_control()
	refresh()


func bind_service(service: Node) -> void:
	_service = service
	refresh()


func focus_control() -> Control:
	return _control


func refresh() -> void:
	if _definition == null:
		return
	_refresh_text()
	_sync_value()


func _refresh_text() -> void:
	label.text = tr(_definition.label_key)
	match _definition.kind:
		DEFINITION.KIND_OPTION:
			_rebuild_options()
		DEFINITION.KIND_ACTION:
			var button := _control as Button
			button.text = tr(_definition.action_label_key)
		DEFINITION.KIND_TOGGLE:
			_refresh_toggle_text()
		DEFINITION.KIND_SLIDER:
			_update_value_label()


func _build_control() -> void:
	for child: Node in control_host.get_children():
		control_host.remove_child(child)
		child.free()
	match _definition.kind:
		DEFINITION.KIND_OPTION:
			_build_option()
		DEFINITION.KIND_SLIDER:
			_build_slider()
		DEFINITION.KIND_TOGGLE:
			_build_toggle()
		DEFINITION.KIND_ACTION:
			_build_action()


func _build_option() -> void:
	var option := OptionButton.new()
	option.name = _definition.node_name
	option.custom_minimum_size = Vector2(220.0, 40.0)
	option.item_selected.connect(_on_option_selected)
	option.mouse_entered.connect(option.grab_focus)
	control_host.add_child(option)
	_control = option
	_rebuild_options()


func _build_slider() -> void:
	var slider := HSlider.new()
	slider.name = _definition.node_name
	slider.custom_minimum_size = Vector2(220.0, 36.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.min_value = _definition.min_value
	slider.max_value = _definition.max_value
	slider.step = _definition.step
	slider.value_changed.connect(_on_slider_changed)
	slider.mouse_entered.connect(slider.grab_focus)
	control_host.add_child(slider)
	_control = slider

	var value_label := Label.new()
	value_label.name = _definition.node_name.trim_suffix("Slider") + "Value"
	value_label.custom_minimum_size = Vector2(56.0, 0.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	control_host.add_child(value_label)
	_value_label = value_label


func _build_toggle() -> void:
	var toggle := CheckButton.new()
	toggle.name = _definition.node_name
	toggle.custom_minimum_size = Vector2(120.0, 40.0)
	toggle.toggled.connect(_on_toggle_toggled)
	toggle.mouse_entered.connect(toggle.grab_focus)
	control_host.add_child(toggle)
	_control = toggle
	_refresh_toggle_text()


func _build_action() -> void:
	var button := Button.new()
	button.name = _definition.node_name
	button.custom_minimum_size = Vector2(220.0, 40.0)
	button.pressed.connect(_on_action_pressed)
	button.mouse_entered.connect(button.grab_focus)
	button.text = tr(_definition.action_label_key)
	control_host.add_child(button)
	_control = button


func _rebuild_options() -> void:
	if _control == null or _definition.kind != DEFINITION.KIND_OPTION:
		return
	var option: OptionButton = _control as OptionButton
	var selected: Variant = _selected_value()
	_syncing = true
	option.clear()
	for entry: Dictionary in _definition.options:
		var index := option.item_count
		option.add_item(tr(String(entry["label_key"])), index)
		option.set_item_metadata(index, entry["value"])
	_select_option_value(selected)
	_syncing = false


func _sync_value() -> void:
	if _control == null:
		return
	var value: Variant = _definition.default_value
	if _service != null and _service.has_method("get_value"):
		value = _service.get_value(_definition.key)
	_syncing = true
	match _definition.kind:
		DEFINITION.KIND_OPTION:
			_select_option_value(value)
		DEFINITION.KIND_SLIDER:
			(_control as HSlider).value = float(value)
			_update_value_label()
		DEFINITION.KIND_TOGGLE:
			(_control as CheckButton).button_pressed = bool(value)
			_refresh_toggle_text()
	_syncing = false


func _select_option_value(value: Variant) -> void:
	var option := _control as OptionButton
	for index: int in option.item_count:
		if String(option.get_item_metadata(index)) == String(value):
			option.select(index)
			return
	option.select(0)


func _selected_value() -> Variant:
	var option := _control as OptionButton
	if option == null or option.selected < 0:
		return _definition.default_value
	return option.get_item_metadata(option.selected)


func _refresh_toggle_text() -> void:
	if _control == null:
		return
	var toggle := _control as CheckButton
	toggle.text = tr("COMMON_ON") if toggle.button_pressed else tr("COMMON_OFF")
	toggle.alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _update_value_label() -> void:
	if _value_label == null or _control == null:
		return
	var value := float((_control as HSlider).value)
	if _definition.value_format == "percent":
		_value_label.text = "%d%%" % roundi(value * 100.0)
	else:
		_value_label.text = "%.2f" % value


func _on_option_selected(index: int) -> void:
	if _syncing:
		return
	var option := _control as OptionButton
	_commit_value(option.get_item_metadata(index))


func _on_slider_changed(value: float) -> void:
	_update_value_label()
	if _syncing:
		return
	_commit_value(value)


func _on_toggle_toggled(enabled: bool) -> void:
	_refresh_toggle_text()
	if _syncing:
		return
	_commit_value(enabled)


func _on_action_pressed() -> void:
	action_pressed.emit(_definition.key)


func _commit_value(value: Variant) -> void:
	if _service != null and _service.has_method("set_value"):
		_service.set_value(_definition.key, value)
	value_changed.emit(_definition.key, value)
