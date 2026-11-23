class_name MapMinimap
extends Control

## Always-on corner minimap. Mirrors the full map's current style: the precise
## style shows explored terrain around the player, the grid style shows the
## nearby room blocks with their exploration brightness.

const MINIMAP_SIZE := Vector2(196.0, 136.0)

var definition: Resource
var exploration: MapExploration

var player: Node2D
var world_runtime: Node

var _style: String = MapScreen.GRID_STYLE
var _source: Object
var _last_version := -1
var _last_player_cell := Vector2i(2147483647, 2147483647)
var _last_room_id := ""
var _suppressed := false
var _precise: MapPreciseRenderer
var _grid: MapGridRenderer
var _frame: Panel
var _badge: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	custom_minimum_size = MINIMAP_SIZE
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -MINIMAP_SIZE.x - 16.0
	offset_right = -16.0
	offset_top = 16.0
	offset_bottom = 16.0 + MINIMAP_SIZE.y
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	visible = false


func bind(map_definition: Resource, map_exploration: MapExploration, source: Object, player_node: Node2D = null, runtime: Node = null) -> void:
	definition = map_definition
	exploration = map_exploration
	_source = source
	player = player_node
	world_runtime = runtime
	_last_version = -1
	_refresh_data()
	if _grid != null:
		_grid.bind(definition, exploration)
		_grid.set_zoom(1.0)
		_grid.draw_labels = false
	if _precise != null:
		_precise.bind(definition, exploration)
		_precise.set_zoom(1.0)
	_apply_style()
	_follow_player(true)


func set_style(style: String) -> void:
	_style = style
	_apply_style()


## Hidden by the map host while the full map or a menu covers the screen.
func set_suppressed(value: bool) -> void:
	_suppressed = value


func _process(_delta: float) -> void:
	if not is_inside_tree():
		return
	var started := not _current_room_id().is_empty()
	var should_show := definition != null and _source != null and started and not _suppressed
	if visible != should_show:
		visible = should_show
	if not should_show:
		return
	if _source.has_method("get_fog_version") and int(_source.call("get_fog_version")) != _last_version:
		_refresh_data()
	_follow_player(false)


func _refresh_data() -> void:
	if _source == null or definition == null or exploration == null:
		return
	if _source.has_method("get_explored_cells"):
		var ids: Array[String] = []
		ids.assign(_source.call("get_explored_cells"))
		exploration.refresh(ids, definition)
	if _source.has_method("get_fog_version"):
		_last_version = int(_source.call("get_fog_version"))
	if _grid != null:
		_grid.queue_redraw()


func _follow_player(force: bool) -> void:
	if player == null or not is_instance_valid(player):
		return
	var cell := Vector2i(floori(player.global_position.x / 8.0), floori(player.global_position.y / 8.0))
	var room_id := _current_room_id()
	if not force and cell == _last_player_cell and room_id == _last_room_id:
		return
	_last_player_cell = cell
	_last_room_id = room_id
	if _precise != null:
		_precise.set_player_cell(cell, room_id)
		_precise.set_center_cell(Vector2(cell))
	if _grid != null:
		_grid.set_player_cell(cell)
		_grid.set_current_room(room_id)
		_grid.focus_room(room_id)


func _current_room_id() -> String:
	if world_runtime != null and is_instance_valid(world_runtime) and world_runtime.has_method("get_current_room_id"):
		return String(world_runtime.call("get_current_room_id"))
	return ""


func _apply_style() -> void:
	if _precise == null or _grid == null:
		return
	_precise.visible = _style == MapScreen.PRECISE_STYLE
	_grid.visible = _style == MapScreen.GRID_STYLE


func _build_ui() -> void:
	_frame = Panel.new()
	_frame.name = "Frame"
	_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.07, 0.92)
	style.border_color = Color(0.24, 0.29, 0.37, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	_frame.add_theme_stylebox_override("panel", style)
	add_child(_frame)

	var view := Control.new()
	view.name = "View"
	view.clip_contents = true
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.offset_left = 4.0
	view.offset_top = 4.0
	view.offset_right = -4.0
	view.offset_bottom = -4.0
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view)

	_grid = MapGridRenderer.new()
	_grid.name = "GridMap"
	_grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.draw_labels = false
	view.add_child(_grid)

	_precise = MapPreciseRenderer.new()
	_precise.name = "PreciseMap"
	_precise.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_precise.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_precise.show_room_borders = false
	view.add_child(_precise)

	_badge = Label.new()
	_badge.name = "Badge"
	_badge.text = "M"
	_badge.add_theme_font_size_override("font_size", 11)
	_badge.modulate = Color(0.62, 0.68, 0.78, 0.9)
	_badge.position = Vector2(6, 2)
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_badge)
