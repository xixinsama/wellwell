class_name SettingsPage
extends ScrollContainer

signal action_requested(key: StringName)

const ROW_SCENE := preload("res://scenes/ui/settings/settings_row.tscn")
const CATALOG := preload("res://game/save/settings_catalog.gd")

@export var section: StringName = &""

@onready var rows: VBoxContainer = %Rows

var _service: Node
var _entries: Array[SettingsRow] = []
var _rows_by_key: Dictionary = {}
var _built := false


func _ready() -> void:
	horizontal_scroll_mode = SCROLL_MODE_DISABLED
	vertical_scroll_mode = SCROLL_MODE_AUTO
	_build()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		refresh()


func bind_service(service: Node) -> void:
	_service = service
	for row: SettingsRow in _entries:
		row.bind_service(service)


func refresh() -> void:
	_build()
	for row: SettingsRow in _entries:
		row.refresh()


func focus_control() -> Control:
	if _entries.is_empty():
		return null
	return _entries[0].focus_control()


func focus_control_for(key: StringName) -> Control:
	if _rows_by_key.has(key):
		return (_rows_by_key[key] as SettingsRow).focus_control()
	return focus_control()


func _build() -> void:
	if _built:
		return
	_built = true
	rows.add_theme_constant_override("separation", 0)
	for definition: SettingsDefinition in CATALOG.definitions_for(section):
		var row := ROW_SCENE.instantiate() as SettingsRow
		row.name = "%sRow" % definition.node_name
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rows.add_child(row)
		row.configure(definition, _service)
		row.action_pressed.connect(_on_action_pressed)
		_entries.append(row)
		_rows_by_key[definition.key] = row


func _on_action_pressed(key: StringName) -> void:
	action_requested.emit(key)
