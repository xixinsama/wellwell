class_name WorldSelect
extends Control

signal world_chosen(world: WorldData)
signal back_requested

@export var catalog: WorldCatalog

@onready var list: VBoxContainer = %WorldList
@onready var status_label: Label = %StatusLabel
@onready var return_button: Button = %ReturnButton

var _saved_world_id := ""
var _entry_buttons: Array[Button] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	return_button.pressed.connect(_request_back)
	return_button.mouse_entered.connect(return_button.grab_focus)
	hide()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_request_back()
		get_viewport().set_input_as_handled()


func open_select(saved_world_id: String = "") -> void:
	_saved_world_id = saved_world_id
	show()
	_refresh()
	var focus := _focus_for_saved_world()
	if focus != null:
		focus.grab_focus.call_deferred()


func show_start_error(details: String = "") -> void:
	show()
	status_label.text = (
		tr("SLOT_START_FAILED") if details.is_empty()
		else "%s %s" % [tr("SLOT_START_FAILED"), details]
	)


func _refresh() -> void:
	status_label.text = ""
	_entry_buttons.clear()
	for child: Node in list.get_children():
		list.remove_child(child)
		child.queue_free()

	var worlds: Array[WorldData] = catalog.get_worlds() if catalog != null else []
	if worlds.is_empty():
		var empty := Label.new()
		empty.text = tr("WORLD_SELECT_EMPTY")
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.modulate = Color(0.68, 0.75, 0.78)
		list.add_child(empty)
		return_button.grab_focus.call_deferred()
		return

	for index in worlds.size():
		if index > 0:
			list.add_child(HSeparator.new())
		list.add_child(_build_world_row(worlds[index]))
	return_button.grab_focus.call_deferred()


func _build_world_row(world: WorldData) -> Control:
	var row := HBoxContainer.new()
	row.name = "WorldRow_%s" % world.world_id
	row.custom_minimum_size = Vector2(680.0, 88.0)
	row.add_theme_constant_override("separation", 16)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)

	var title := Label.new()
	title.add_theme_font_size_override("font_size", 23)
	title.text = _world_title(world)
	info.add_child(title)

	var description := Label.new()
	description.add_theme_font_size_override("font_size", 15)
	description.modulate = Color(0.68, 0.75, 0.78)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.text = world.description
	info.add_child(description)

	var identifier := Label.new()
	identifier.add_theme_font_size_override("font_size", 12)
	identifier.modulate = Color(0.42, 0.8, 0.82, 0.85)
	identifier.text = world.world_id
	info.add_child(identifier)
	row.add_child(info)

	var enter := Button.new()
	enter.name = "EnterButton"
	enter.custom_minimum_size = Vector2(116.0, 48.0)
	enter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	enter.text = tr("WORLD_SELECT_ENTER")
	enter.pressed.connect(func() -> void: _choose(world))
	enter.mouse_entered.connect(enter.grab_focus)
	row.add_child(enter)
	_entry_buttons.append(enter)
	return row


func _world_title(world: WorldData) -> String:
	return world.display_name if not world.display_name.is_empty() else world.world_id


func _focus_for_saved_world() -> Button:
	if _saved_world_id.is_empty() or catalog == null:
		return _entry_buttons[0] if not _entry_buttons.is_empty() else null
	var worlds := catalog.get_worlds()
	for index in worlds.size():
		if worlds[index].world_id == _saved_world_id and index < _entry_buttons.size():
			return _entry_buttons[index]
	return _entry_buttons[0] if not _entry_buttons.is_empty() else null


func _choose(world: WorldData) -> void:
	hide()
	world_chosen.emit(world)


func _request_back() -> void:
	hide()
	back_requested.emit()
