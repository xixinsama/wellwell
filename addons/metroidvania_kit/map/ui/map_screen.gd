class_name MapScreen
extends Control

## Full-screen map. Two styles share one model: the precise terrain map and the
## metroidvania room grid. Opening the map pauses the game; the map itself keeps
## processing so it can animate and close.

signal closed
signal opened
signal style_changed(style: String)

const PRECISE_STYLE := "precise"
const GRID_STYLE := "grid"

var definition: Resource
var exploration: MapExploration
var player: Node2D

var _style := PRECISE_STYLE
var _source: Object
var _last_version := -1
var _was_paused := false
var _is_open := false
var _precise: MapPreciseRenderer
var _grid: MapGridRenderer
var _title: Label
var _hint: Label
var _legend: Label
var _precise_button: Button
var _grid_button: Button
var _view: Control
var _zoom := 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build_ui()
	_apply_style()


func bind(map_definition: Resource, map_exploration: MapExploration, source: Object, player_node: Node2D = null) -> void:
	definition = map_definition
	exploration = map_exploration
	_source = source
	player = player_node
	_last_version = -1
	_refresh_data()
	if definition == null:
		close()


func is_open() -> bool:
	return _is_open


func open() -> bool:
	if definition == null or _is_open:
		return false
	_refresh_data()
	_was_paused = get_tree().paused
	get_tree().paused = true
	_is_open = true
	visible = true
	_precise.fit_all()
	_grid.fit_all()
	_focus_player()
	opened.emit()
	return true


func close() -> void:
	if not _is_open:
		visible = false
		return
	_is_open = false
	visible = false
	get_tree().paused = _was_paused
	closed.emit()


func toggle() -> void:
	if _is_open:
		close()
	else:
		open()


func set_style(style: String) -> void:
	var next := GRID_STYLE if style == GRID_STYLE else PRECISE_STYLE
	var changed := next != _style
	_style = next
	_apply_style()
	if changed:
		style_changed.emit(_style)


func get_style() -> String:
	return _style


func cycle_style() -> void:
	set_style(GRID_STYLE if _style == PRECISE_STYLE else PRECISE_STYLE)


func _process(_delta: float) -> void:
	if not _is_open:
		return
	if _source != null and _source.has_method("get_fog_version") and int(_source.call("get_fog_version")) != _last_version:
		_refresh_data()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		if event.is_action_pressed("map_toggle"):
			if open():
				get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("map_toggle") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map_style"):
		cycle_style()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom(_zoom + 0.25)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom(_zoom - 0.25)


func _set_zoom(value: float) -> void:
	_zoom = clampf(value, 0.5, 4.0)
	_precise.set_zoom(3.0 * _zoom)
	_grid.set_zoom(_zoom)


func _refresh_data() -> void:
	if _source == null or definition == null or exploration == null:
		return
	if _source.has_method("get_explored_cells"):
		var ids: Array[String] = []
		ids.assign(_source.call("get_explored_cells"))
		exploration.refresh(ids, definition)
	if _source.has_method("get_fog_version"):
		_last_version = int(_source.call("get_fog_version"))
	if _precise != null:
		_precise.set_data(definition, exploration)
		_precise.set_zoom(3.0 * _zoom)
	if _grid != null:
		_grid.set_data(definition, exploration)
		_grid.set_zoom(_zoom)
	_focus_player()


func _focus_player() -> void:
	if player == null or not is_instance_valid(player) or definition == null:
		return
	var cell := Vector2i(floori(player.global_position.x / 8.0), floori(player.global_position.y / 8.0))
	var room_id := _room_at_cell(cell)
	_precise.set_player_cell(cell, room_id)
	_grid.set_player_cell(cell)
	_grid.set_current_room(room_id)


func _room_at_cell(cell: Vector2i) -> String:
	if definition == null:
		return ""
	for room: Resource in definition.get("rooms"):
		if room == null:
			continue
		var origin: Vector2i = MapDefinitionBuilder.room_cell_origin(room)
		var room_rect := Rect2i(origin, MapDefinitionBuilder.room_cell_size(room))
		if room_rect.has_point(cell):
			return String(room.get("room_id"))
	return ""


func _apply_style() -> void:
	if _precise == null or _grid == null:
		return
	_precise.visible = _style == PRECISE_STYLE
	_grid.visible = _style == GRID_STYLE
	if _precise_button != null:
		_precise_button.button_pressed = _style == PRECISE_STYLE
	if _grid_button != null:
		_grid_button.button_pressed = _style == GRID_STYLE
	if _legend != null:
		_legend.text = tr("MAP_LEGEND_PRECISE") if _style == PRECISE_STYLE else tr("MAP_LEGEND_GRID")
	queue_redraw()


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.03, 0.05, 0.9)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	column.add_child(header)

	_title = Label.new()
	_title.text = tr("MAP_TITLE")
	_title.add_theme_font_size_override("font_size", 24)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)

	_precise_button = Button.new()
	_precise_button.name = "PreciseButton"
	_precise_button.text = tr("MAP_STYLE_PRECISE")
	_precise_button.toggle_mode = true
	_precise_button.focus_mode = Control.FOCUS_NONE
	_precise_button.pressed.connect(func() -> void: set_style(PRECISE_STYLE))
	header.add_child(_precise_button)

	_grid_button = Button.new()
	_grid_button.name = "GridButton"
	_grid_button.text = tr("MAP_STYLE_GRID")
	_grid_button.toggle_mode = true
	_grid_button.focus_mode = Control.FOCUS_NONE
	_grid_button.pressed.connect(func() -> void: set_style(GRID_STYLE))
	header.add_child(_grid_button)

	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", _panel_style(Color(0.05, 0.06, 0.09, 1.0)))
	column.add_child(frame)

	_view = Control.new()
	_view.name = "MapView"
	_view.clip_contents = true
	_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(_view)

	_precise = MapPreciseRenderer.new()
	_precise.name = "PreciseMap"
	_precise.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_precise.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.add_child(_precise)

	_grid = MapGridRenderer.new()
	_grid.name = "GridMap"
	_grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.add_child(_grid)

	_legend = Label.new()
	_legend.name = "Legend"
	_legend.add_theme_font_size_override("font_size", 13)
	_legend.modulate = Color(0.7, 0.76, 0.85)
	column.add_child(_legend)

	_hint = Label.new()
	_hint.name = "Hint"
	_hint.text = tr("MAP_HINT")
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.modulate = Color(0.55, 0.62, 0.72)
	column.add_child(_hint)

	_view.resized.connect(func() -> void: _focus_player())


func _panel_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.18, 0.22, 0.30, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	return style
