class_name SettingsPage
extends VBoxContainer

signal action_requested(key: StringName)

const ROW_SCENE := preload("res://scenes/ui/settings/settings_row.tscn")
const CATALOG := preload("res://scripts/save/settings_catalog.gd")

@export var section: StringName = &""

@onready var title_label: Label = %PageTitle
@onready var description_label: Label = %PageDescription
@onready var rows: VBoxContainer = %Rows

var _service: Node
var _rows: Array[SettingsRow] = []
var _rows_by_key: Dictionary = {}
var _built := false


func _ready() -> void:
	_build()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_text()


func bind_service(service: Node) -> void:
	_service = service
	for row: SettingsRow in _rows:
		row.bind_service(service)


func refresh() -> void:
	_build()
	_refresh_text()


func focus_control() -> Control:
	if _rows.is_empty():
		return null
	return _rows[0].focus_control()


func focus_control_for(key: StringName) -> Control:
	if _rows_by_key.has(key):
		return (_rows_by_key[key] as SettingsRow).focus_control()
	return focus_control()


func _build() -> void:
	if _built:
		return
	_built = true
	_refresh_text()
	for definition: SettingsDefinition in CATALOG.definitions_for(section):
		var row := ROW_SCENE.instantiate() as SettingsRow
		row.name = "%sRow" % definition.node_name
		rows.add_child(row)
		row.configure(definition, _service)
		row.action_pressed.connect(_on_action_pressed)
		_rows.append(row)
		_rows_by_key[definition.key] = row


func _refresh_text() -> void:
	var metadata: Dictionary = CATALOG.section_metadata(section)
	if not metadata.is_empty():
		title_label.text = tr(String(metadata["label_key"]))
		description_label.text = tr(String(metadata["description_key"]))
	for row: SettingsRow in _rows:
		row.refresh()


func _on_action_pressed(key: StringName) -> void:
	action_requested.emit(key)
