class_name SettingsMenu
extends Control

signal back_requested

const CATALOG := preload("res://scripts/save/settings_catalog.gd")

@onready var panel: PanelContainer = $Panel
@onready var tabs: VBoxContainer = %Tabs
@onready var page_host: MarginContainer = %PageHost
@onready var reset_button: Button = %ResetButton
@onready var back_button: Button = %BackButton
@onready var input_mapping_menu: Control = %InputMappingMenu

var _settings: Node
var _input_mapping: Node
var _pages: Dictionary = {}
var _tabs: Dictionary = {}
var _active_section: StringName = CATALOG.GENERAL
var _syncing_tabs := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_settings = get_node_or_null("/root/GlobalSettings")
	_input_mapping = get_node_or_null("/root/InputMapping")
	reset_button.pressed.connect(_reset_defaults)
	back_button.pressed.connect(_request_back)
	input_mapping_menu.connect("back_requested", _close_input_mapping)
	input_mapping_menu.call("bind_service", _input_mapping)
	for control: Control in [reset_button, back_button]:
		control.mouse_entered.connect(control.grab_focus)
	_collect_tabs()
	_collect_pages()
	_select_section(_active_section)
	hide()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_tab_text()


func _unhandled_input(event: InputEvent) -> void:
	if input_mapping_menu.visible or not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_request_back()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_page_up"):
		_cycle_section(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_page_down"):
		_cycle_section(1)
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed:
		var button := (event as InputEventJoypadButton).button_index
		if button == JOY_BUTTON_LEFT_SHOULDER:
			_cycle_section(-1)
			get_viewport().set_input_as_handled()
		elif button == JOY_BUTTON_RIGHT_SHOULDER:
			_cycle_section(1)
			get_viewport().set_input_as_handled()


func open_menu() -> void:
	if _settings == null:
		_settings = get_node_or_null("/root/GlobalSettings")
		for page: SettingsPage in _pages.values():
			page.bind_service(_settings)
	input_mapping_menu.hide()
	panel.show()
	show()
	_select_section(_active_section)
	_pages[_active_section].refresh()
	var first: Control = _pages[_active_section].focus_control()
	if first != null:
		first.grab_focus.call_deferred()


func bind_settings_dependencies(settings: Node, input_mapping: Node) -> void:
	_settings = settings
	_input_mapping = input_mapping
	for page: SettingsPage in _pages.values():
		page.bind_service(settings)
	input_mapping_menu.call("bind_service", _input_mapping)
	if visible:
		_pages[_active_section].refresh()


func _collect_tabs() -> void:
	for child: Node in tabs.get_children():
		if not child is Button:
			continue
		var button := child as Button
		var section := StringName(button.get_meta("section", ""))
		if section == &"":
			continue
		_tabs[section] = button
		button.toggled.connect(_on_tab_toggled.bind(section))
		button.gui_input.connect(_on_tab_gui_input.bind(section))
	_refresh_tab_text()


func _collect_pages() -> void:
	for child: Node in page_host.get_children():
		if not child is SettingsPage:
			continue
		var page := child as SettingsPage
		_pages[page.section] = page
		page.bind_service(_settings)
		page.action_requested.connect(_on_page_action)


func _refresh_tab_text() -> void:
	for section: StringName in _tabs:
		var metadata: Dictionary = CATALOG.section_metadata(section)
		if not metadata.is_empty():
			(_tabs[section] as Button).text = tr(String(metadata["label_key"]))


func _select_section(section: StringName, focus_content := false) -> void:
	if not _pages.has(section) or not _tabs.has(section):
		return
	_active_section = section
	_syncing_tabs = true
	for id: StringName in _tabs:
		(_tabs[id] as Button).set_pressed_no_signal(id == section)
	_syncing_tabs = false
	for id: StringName in _pages:
		(_pages[id] as Control).visible = id == section
	if visible:
		_pages[section].refresh()
	_wire_focus(section)
	if focus_content:
		_focus_page(section)


func _wire_focus(section: StringName) -> void:
	var page: SettingsPage = _pages[section]
	var tab: Button = _tabs[section]
	var first := page.focus_control()
	if first == null:
		return
	first.focus_neighbor_left = first.get_path_to(tab)
	first.focus_neighbor_top = first.get_path_to(tab)
	tab.focus_neighbor_right = tab.get_path_to(first)


func _focus_page(section: StringName) -> void:
	var first := (_pages[section] as SettingsPage).focus_control()
	if first != null:
		first.grab_focus.call_deferred()


func _cycle_section(delta: int) -> void:
	var ids: Array[StringName] = []
	for metadata: Dictionary in CATALOG.sections():
		ids.append(metadata["id"])
	var index := ids.find(_active_section)
	if index < 0:
		index = 0
	else:
		index = wrapi(index + delta, 0, ids.size())
	_select_section(ids[index], true)


func _on_tab_toggled(enabled: bool, section: StringName) -> void:
	if _syncing_tabs:
		return
	if enabled:
		_select_section(section)
	elif section == _active_section:
		(_tabs[section] as Button).set_pressed_no_signal(true)


func _on_tab_gui_input(event: InputEvent, _section: StringName) -> void:
	if event.is_action_pressed("ui_up"):
		_cycle_section(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_cycle_section(1)
		get_viewport().set_input_as_handled()


func _on_page_action(key: StringName) -> void:
	if key == &"input_mapping":
		_open_input_mapping()


func _open_input_mapping() -> void:
	panel.hide()
	input_mapping_menu.call("open_menu")


func _close_input_mapping() -> void:
	input_mapping_menu.hide()
	panel.show()
	_select_section(_active_section)
	var page: SettingsPage = _pages[_active_section]
	var control: Control = page.focus_control_for(&"input_mapping")
	if control == null:
		control = page.focus_control()
	if control != null:
		control.grab_focus.call_deferred()


func _reset_defaults() -> void:
	if _settings != null and _settings.has_method("reset_defaults"):
		_settings.call("reset_defaults")
	if _input_mapping != null and _input_mapping.has_method("restore_defaults"):
		_input_mapping.call("restore_defaults")
	for page: SettingsPage in _pages.values():
		page.refresh()


func _request_back() -> void:
	if input_mapping_menu.visible:
		return
	hide()
	back_requested.emit()
