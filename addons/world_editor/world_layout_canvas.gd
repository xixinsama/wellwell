@tool
extends Control

## World layout canvas: rooms, terrain previews, focus/zoom/pan, selection sets,
## box selection, group dragging, connection lines and entity markers.

const CHUNK_PIXELS := Vector2(320, 180)
const WORLD_CANVAS_VIEW := preload("res://addons/world_editor/authoring/world/world_canvas_view.gd")
const ROOM_FILL := Color(0.18, 0.55, 0.72, 0.32)
const OVERLAP_FILL := Color(0.85, 0.2, 0.18, 0.28)
const GRID_COLOR := Color(0.42, 0.46, 0.52, 0.28)
const AXIS_COLOR := Color(0.78, 0.55, 0.24, 0.72)
const GUIDE_COLOR := Color(0.3, 0.78, 0.62, 0.8)
const SELECTED_COLOR := Color(0.35, 0.66, 0.92)
const HOVERED_COLOR := Color(0.98, 0.86, 0.34)
const BOX_FILL := Color(0.35, 0.66, 0.92, 0.12)
const BOX_OUTLINE := Color(0.35, 0.66, 0.92, 0.85)
const STATUS_OUTLINES := {
	&"fresh": Color(0, 0, 0, 0),
	&"stale": Color(0.88, 0.58, 0.24),
	&"error": Color(0.88, 0.35, 0.35),
	&"unknown": Color(0.52, 0.58, 0.66),
}
const LABEL_COLOR := Color(0.90, 0.93, 0.98)
const SUBTLE_LABEL_COLOR := Color(0.66, 0.72, 0.82)

signal selection_changed(room_ids: Array, primary: String)
signal delete_requested

var _main: Control
var _preview: Control
var _marker_layer: Control
var _view: RefCounted = WORLD_CANVAS_VIEW.new()
var _cursor_screen := Vector2.ZERO
var _drag_room_id := ""
var _drag_room_ids: Array[String] = []
var _drag_start_chunks: Dictionary = {}
var _drag_start_mouse := Vector2.ZERO
var _drag_start_chunk := Vector2i.ZERO
var _drag_preview_chunk := Vector2i.ZERO
var _drag_delta := Vector2i.ZERO
var _pan_button := MOUSE_BUTTON_NONE
var _space_pressed := false
var _hovered_room_id := ""
var _selected_ids: Array[String] = []
var _primary := ""
var _statuses: Dictionary = {}
var _annotations: Dictionary = {}
var _box_selecting := false
var _box_additive := false
var _box_start := Vector2.ZERO
var _box_current := Vector2.ZERO


func set_main_screen(value: Control) -> void:
	_main = value
	_preview = get_node_or_null("TerrainPreviewLayer") as Control
	_marker_layer = get_node_or_null("MarkerLayer") as Control
	_sync_preview()
	_sync_marker_layer()
	queue_redraw()


func sync_preview() -> void:
	_sync_preview()
	_sync_marker_layer()


func update_preview_transforms() -> void:
	if _preview != null and is_instance_valid(_preview):
		_preview.call("set_view_transform", _view.get("view_center_world_pixels"), get_zoom(), size)
	_sync_marker_layer()


func refresh_preview_room(room_id: String) -> void:
	if _preview != null and is_instance_valid(_preview):
		_preview.call("refresh_room", _get_world(), room_id)


func _ready() -> void:
	_preview = get_node_or_null("TerrainPreviewLayer") as Control
	_marker_layer = get_node_or_null("MarkerLayer") as Control
	_sync_preview()
	_sync_marker_layer()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_notify_view_changed()


# --- Selection ----------------------------------------------------------------

func set_selection(room_ids: Array, primary: String) -> void:
	_selected_ids.clear()
	for value: Variant in room_ids:
		var id := String(value)
		if not id.is_empty() and not _selected_ids.has(id):
			_selected_ids.append(id)
	_primary = primary if _selected_ids.has(primary) else ("" if _selected_ids.is_empty() else _selected_ids[0])
	_sync_marker_layer()
	queue_redraw()


func get_selected_room_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_selected_ids)
	return ids


func get_primary_room_id() -> String:
	return _primary


func set_statuses(statuses: Dictionary) -> void:
	_statuses = statuses
	_sync_marker_layer()
	queue_redraw()


func set_annotations(annotations: Dictionary) -> void:
	_annotations = annotations
	_sync_marker_layer()
	queue_redraw()


func _apply_selection(room_ids: Array[String], primary: String, notify: bool) -> void:
	set_selection(room_ids, primary)
	if notify:
		selection_changed.emit(_selected_ids.duplicate(), _primary)


func _select_only(room_id: String) -> void:
	var ids: Array[String] = []
	if not room_id.is_empty():
		ids.append(room_id)
	_apply_selection(ids, room_id, true)


func _toggle_room(room_id: String) -> void:
	if room_id.is_empty():
		return
	var ids: Array[String] = []
	ids.assign(_selected_ids)
	if ids.has(room_id):
		ids.erase(room_id)
		var primary: String = _primary
		if primary == room_id or not ids.has(primary):
			primary = "" if ids.is_empty() else ids[0]
		_apply_selection(ids, primary, true)
	else:
		ids.append(room_id)
		_apply_selection(ids, room_id, true)


func select_all() -> void:
	var world := _get_world()
	if world == null:
		return
	var ids: Array[String] = []
	for room_id: String in world.get_room_ids():
		ids.append(room_id)
	_apply_selection(ids, "" if ids.is_empty() else ids[0], true)


func clear_selection() -> void:
	var ids: Array[String] = []
	_apply_selection(ids, "", true)


# --- View ---------------------------------------------------------------------

func focus_all() -> bool:
	var world := _get_world()
	if world == null or world.rooms.is_empty():
		_view.call("reset")
		_notify_view_changed()
		return false
	var bounds := Rect2()
	var has_bounds := false
	for room_id: String in world.get_room_ids():
		var pixel_rect := Rect2(world.get_room_pixel_rect(room_id))
		bounds = pixel_rect if not has_bounds else bounds.merge(pixel_rect)
		has_bounds = true
	_view.call("fit_world_rect", bounds, size)
	_notify_view_changed()
	return has_bounds


func focus_room(room_id: String) -> bool:
	var world := _get_world()
	var room: RoomData = null if world == null else world.get_room(room_id)
	if room == null:
		return false
	_view.call("fit_world_rect", Rect2(world.get_room_pixel_rect(room_id)), size)
	_notify_view_changed()
	return true


func reset_view() -> void:
	_view.call("reset")
	_drag_room_id = ""
	_drag_room_ids.clear()
	_drag_start_chunks.clear()
	_pan_button = MOUSE_BUTTON_NONE
	_space_pressed = false
	_box_selecting = false
	_notify_view_changed()


func get_hovered_room_id() -> String:
	return _hovered_room_id


func get_selected_room_id() -> String:
	if not _primary.is_empty():
		return _primary
	return "" if _main == null else String(_main.get("selected_room_id"))


func cancel_room_drag() -> void:
	if _drag_room_id.is_empty():
		return
	for room_id: String in _drag_room_ids:
		if _preview != null and is_instance_valid(_preview):
			_preview.call("set_drag_origin", room_id, null)
	_drag_room_id = ""
	_drag_room_ids.clear()
	_drag_start_chunks.clear()
	_drag_delta = Vector2i.ZERO
	_drag_preview_chunk = Vector2i.ZERO
	queue_redraw()


func begin_room_drag(room_id: String, screen_position: Vector2) -> bool:
	var world := _get_world()
	var room: RoomData = null if world == null else world.get_room(room_id)
	if room == null:
		return false
	_drag_room_id = room_id
	_drag_room_ids = _selected_ids.duplicate()
	if _drag_room_ids.is_empty() or not _drag_room_ids.has(room_id):
		_drag_room_ids = [room_id]
	_drag_start_chunks.clear()
	for id: String in _drag_room_ids:
		_drag_start_chunks[id] = world.get_room_origin_chunk(id)
	_drag_start_mouse = screen_position
	_drag_start_chunk = world.get_room_origin_chunk(room_id)
	_drag_preview_chunk = _drag_start_chunk
	_drag_delta = Vector2i.ZERO
	_sync_drag_preview()
	_pan_button = MOUSE_BUTTON_NONE
	if _main.has_method("select_room") and not _selected_ids.has(room_id):
		_main.call("select_room", room_id)
	queue_redraw()
	return true


func update_room_drag(screen_position: Vector2) -> void:
	if _drag_room_id.is_empty():
		return
	_drag_preview_chunk = _dragged_chunk(screen_position)
	_drag_delta = _drag_preview_chunk - _drag_start_chunk
	_sync_drag_preview()
	queue_redraw()


func update_cursor(screen_position: Vector2) -> void:
	_cursor_screen = screen_position
	_set_hovered_room(_room_at_screen_position(screen_position))
	if _marker_layer != null and is_instance_valid(_marker_layer):
		_marker_layer.call("set_cursor", screen_position)
	queue_redraw()


func get_cursor_world_pixels() -> Vector2:
	return _view.call("screen_to_world", _cursor_screen, size)


func get_cursor_chunk() -> Vector2i:
	var world_position := get_cursor_world_pixels()
	return Vector2i(
		floori(world_position.x / CHUNK_PIXELS.x),
		floori(world_position.y / CHUNK_PIXELS.y)
	)


func get_visible_grid_lines() -> Dictionary:
	var first_world: Vector2 = _view.call("screen_to_world", Vector2.ZERO, size)
	var last_world: Vector2 = _view.call("screen_to_world", size, size)
	var minimum := first_world.min(last_world)
	var maximum := first_world.max(last_world)
	var x_chunks: Array[int] = []
	var y_chunks: Array[int] = []
	var x_step := maxi(1, ceili(32.0 / (CHUNK_PIXELS.x * get_zoom())))
	var y_step := maxi(1, ceili(32.0 / (CHUNK_PIXELS.y * get_zoom())))
	var minimum_x := floori(minimum.x / CHUNK_PIXELS.x)
	var maximum_x := ceili(maximum.x / CHUNK_PIXELS.x)
	var minimum_y := floori(minimum.y / CHUNK_PIXELS.y)
	var maximum_y := ceili(maximum.y / CHUNK_PIXELS.y)
	var first_x := ceili(float(minimum_x) / x_step) * x_step
	var first_y := ceili(float(minimum_y) / y_step) * y_step
	for x: int in range(first_x, maximum_x + 1, x_step):
		x_chunks.append(x)
	for y: int in range(first_y, maximum_y + 1, y_step):
		y_chunks.append(y)
	return {"x_chunks": x_chunks, "y_chunks": y_chunks}


func get_drag_preview_chunk() -> Vector2i:
	return _drag_preview_chunk


func get_zoom() -> float:
	return float(_view.get("zoom"))


func _draw() -> void:
	# The dark canvas background lives in TerrainPreviewLayer, which draws behind
	# this control (show_behind_parent) so the terrain stays visible underneath
	# the grid, room frames and labels.
	_draw_grid()
	var world := _get_world()
	if world != null:
		var overlapping := _overlapping_room_ids(world)
		_draw_connections(world)
		for room_id: String in world.get_room_ids():
			var room: RoomData = world.get_room(room_id)
			if room == null:
				continue
			var origin := _room_origin_during_drag(world, room_id)
			var rect := _room_rect(origin, room.room_size_chunks)
			var selected := _selected_ids.has(room_id)
			var hovered := room_id == _hovered_room_id
			draw_rect(rect, OVERLAP_FILL if overlapping.has(room_id) else ROOM_FILL, true)
			var outline := _room_outline(room, selected, hovered)
			draw_rect(rect, outline, false, 3.0 if hovered or selected else 2.0)
			_draw_room_label(room, rect, world)
			if room_id == world.start_room_id:
				draw_string(
					ThemeDB.fallback_font,
					rect.position + Vector2(rect.size.x - 16.0, 16.0),
					"★",
					HORIZONTAL_ALIGNMENT_LEFT,
					-1,
					13,
					Color(0.95, 0.78, 0.2)
				)
	_draw_box_selection()
	_draw_overlays(world)


func _room_origin_during_drag(world: WorldData, room_id: String) -> Vector2i:
	if _drag_start_chunks.has(room_id):
		return (_drag_start_chunks[room_id] as Vector2i) + _drag_delta
	return world.get_room_origin_chunk(room_id)


func _room_outline(room: RoomData, selected: bool, hovered: bool) -> Color:
	if selected:
		return SELECTED_COLOR
	if hovered:
		return HOVERED_COLOR
	var status: StringName = _statuses.get(room.room_id, &"fresh")
	var status_color: Color = STATUS_OUTLINES.get(status, Color(0, 0, 0, 0))
	if status_color.a > 0.0:
		return status_color
	return room.map_color


func _draw_room_label(room: RoomData, rect: Rect2, world: WorldData) -> void:
	if rect.size.x < 60.0 or rect.size.y < 30.0:
		return
	var font := ThemeDB.fallback_font
	var title := room.room_id if room.display_name.is_empty() else room.display_name
	draw_string(
		font,
		rect.position + Vector2(5, 15),
		title,
		HORIZONTAL_ALIGNMENT_LEFT,
		rect.size.x - 22.0,
		12,
		LABEL_COLOR
	)
	var origin := _room_origin_during_drag(world, room.room_id)
	var subtitle := "%s · %d×%d · (%d, %d)" % [
		room.room_id,
		room.room_size_chunks.x,
		room.room_size_chunks.y,
		origin.x,
		origin.y,
	]
	draw_string(
		font,
		rect.position + Vector2(5, 28),
		subtitle,
		HORIZONTAL_ALIGNMENT_LEFT,
		rect.size.x - 10.0,
		10,
		SUBTLE_LABEL_COLOR
	)


func _draw_box_selection() -> void:
	if not _box_selecting:
		return
	var rect := Rect2(_box_start, _box_current - _box_start).abs()
	draw_rect(rect, BOX_FILL, true)
	draw_rect(rect, BOX_OUTLINE, false, 1.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			cancel_room_drag()
			_box_selecting = false
			clear_selection()
			accept_event()
			return
		if event.keycode == KEY_DELETE:
			delete_requested.emit()
			accept_event()
			return
		if event.keycode == KEY_A and (event.ctrl_pressed or event.meta_pressed):
			select_all()
			accept_event()
			return
	if event is InputEventKey and event.keycode == KEY_SPACE:
		_space_pressed = event.pressed and not event.echo
		if not event.pressed and _pan_button == MOUSE_BUTTON_LEFT:
			_pan_button = MOUSE_BUTTON_NONE
		accept_event()
		return
	if _get_world() == null:
		return
	if event is InputEventMouseButton:
		if event.pressed:
			grab_focus()
		update_cursor(event.position)
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_view.call("zoom_at", event.position, 1.2, size)
			_notify_view_changed()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_view.call("zoom_at", event.position, 1.0 / 1.2, size)
			_notify_view_changed()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_pan_button = MOUSE_BUTTON_MIDDLE if event.pressed else MOUSE_BUTTON_NONE
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if (_space_pressed or Input.is_key_pressed(KEY_SPACE)) and _drag_room_id.is_empty():
					_pan_button = MOUSE_BUTTON_LEFT
				else:
					_begin_gesture_at(event.position, event.ctrl_pressed or event.meta_pressed)
			elif _box_selecting:
				_commit_box_select()
			elif not _drag_room_id.is_empty():
				_commit_drag(event.position)
			elif _pan_button == MOUSE_BUTTON_LEFT:
				_pan_button = MOUSE_BUTTON_NONE
			accept_event()
	elif event is InputEventMouseMotion:
		update_cursor(event.position)
		_set_hovered_room(_room_at_screen_position(event.position))
		if _box_selecting:
			_box_current = event.position
			queue_redraw()
			accept_event()
		elif _pan_button != MOUSE_BUTTON_NONE and _drag_room_id.is_empty():
			_view.call("pan_screen_delta", event.relative)
			_notify_view_changed()
			accept_event()
		elif not _drag_room_id.is_empty():
			update_room_drag(event.position)
			accept_event()


func _begin_gesture_at(mouse_position: Vector2, additive: bool) -> void:
	var room_id := _room_at_screen_position(mouse_position)
	if room_id.is_empty():
		_begin_box_select(mouse_position, additive)
		return
	if additive:
		_toggle_room(room_id)
		return
	if not _selected_ids.has(room_id):
		_select_only(room_id)
	begin_room_drag(room_id, mouse_position)


func _begin_box_select(mouse_position: Vector2, additive: bool) -> void:
	_box_selecting = true
	_box_additive = additive
	_box_start = mouse_position
	_box_current = mouse_position
	queue_redraw()


func _commit_box_select() -> void:
	_box_selecting = false
	box_select(Rect2(_box_start, _box_current - _box_start).abs(), _box_additive)
	queue_redraw()


## Select every room whose rectangle intersects [param rect] (screen space).
func box_select(rect: Rect2, additive: bool) -> void:
	var world := _get_world()
	if world == null:
		return
	var ids: Array[String] = []
	if additive:
		ids.assign(_selected_ids)
	for room_id: String in world.get_room_ids():
		var room: RoomData = world.get_room(room_id)
		if room == null:
			continue
		if rect.intersects(_room_rect(world.get_room_origin_chunk(room_id), room.room_size_chunks)):
			if not ids.has(room_id):
				ids.append(room_id)
	var primary: String = _primary
	if not ids.has(primary):
		primary = "" if ids.is_empty() else ids[0]
	_apply_selection(ids, primary, true)


func _commit_drag(mouse_position: Vector2) -> void:
	update_room_drag(mouse_position)
	if _main.has_method("move_rooms_by") and _drag_delta != Vector2i.ZERO:
		if _drag_room_ids.size() > 1:
			_main.call("move_rooms_by", _drag_delta)
		elif _main.has_method("move_room"):
			_main.call("move_room", _drag_room_id, _drag_preview_chunk)
	for room_id: String in _drag_room_ids:
		if _preview != null and is_instance_valid(_preview):
			_preview.call("set_drag_origin", room_id, null)
	_drag_room_id = ""
	_drag_room_ids.clear()
	_drag_start_chunks.clear()
	_drag_delta = Vector2i.ZERO
	queue_redraw()


func _sync_drag_preview() -> void:
	if _preview == null or not is_instance_valid(_preview):
		return
	for room_id: String in _drag_room_ids:
		var start: Vector2i = _drag_start_chunks.get(room_id, Vector2i.ZERO)
		_preview.call("set_drag_origin", room_id, start + _drag_delta)


func _room_at_screen_position(mouse_position: Vector2) -> String:
	var world := _get_world()
	if world == null:
		return ""
	var room_ids := world.get_room_ids()
	room_ids.reverse()
	for room_id: String in room_ids:
		var room: RoomData = world.get_room(room_id)
		if room != null and _room_rect(_room_origin_during_drag(world, room_id), room.room_size_chunks).has_point(mouse_position):
			return room_id
	return ""


func _set_hovered_room(room_id: String) -> void:
	if _hovered_room_id == room_id:
		return
	_hovered_room_id = room_id
	queue_redraw()


func _dragged_chunk(mouse_position: Vector2) -> Vector2i:
	var delta := mouse_position - _drag_start_mouse
	var zoom := get_zoom()
	var chunk_delta := Vector2i(
		roundi(delta.x / (CHUNK_PIXELS.x * zoom)),
		roundi(delta.y / (CHUNK_PIXELS.y * zoom))
	)
	return _drag_start_chunk + chunk_delta


func _room_rect(origin_chunk: Vector2i, size_chunks: Vector2i) -> Rect2:
	var world_origin := Vector2(origin_chunk) * CHUNK_PIXELS
	var screen_origin: Vector2 = _view.call("world_to_screen", world_origin, size)
	return Rect2(screen_origin, Vector2(size_chunks) * CHUNK_PIXELS * get_zoom())


func _draw_grid() -> void:
	var lines := get_visible_grid_lines()
	var show_x_labels := CHUNK_PIXELS.x * get_zoom() >= 32.0
	var show_y_labels := CHUNK_PIXELS.y * get_zoom() >= 32.0
	for x: int in lines.get("x_chunks", []):
		var screen_x: float = _view.call("world_to_screen", Vector2(x * CHUNK_PIXELS.x, 0), size).x
		draw_line(Vector2(screen_x, 0), Vector2(screen_x, size.y), AXIS_COLOR if x == 0 else GRID_COLOR, 2.0 if x == 0 else 1.0)
		if show_x_labels:
			draw_string(ThemeDB.fallback_font, Vector2(screen_x + 4, 14), str(x), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, GRID_COLOR.lightened(0.45))
	for y: int in lines.get("y_chunks", []):
		var screen_y: float = _view.call("world_to_screen", Vector2(0, y * CHUNK_PIXELS.y), size).y
		draw_line(Vector2(0, screen_y), Vector2(size.x, screen_y), AXIS_COLOR if y == 0 else GRID_COLOR, 2.0 if y == 0 else 1.0)
		if show_y_labels:
			draw_string(ThemeDB.fallback_font, Vector2(4, screen_y - 4), str(y), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, GRID_COLOR.lightened(0.45))


func _draw_overlays(world: WorldData) -> void:
	var font := ThemeDB.fallback_font
	var world_position := get_cursor_world_pixels()
	var chunk := get_cursor_chunk()
	var cursor_text := WorldEditorLocalization.t("WE_CURSOR", [world_position.x, world_position.y, chunk.x, chunk.y])
	draw_string(font, Vector2(8, size.y - 10), cursor_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.86, 0.88, 0.92))
	if not _selected_ids.is_empty():
		var selection_text := WorldEditorLocalization.t("WE_SELECTED_COUNT", [_selected_ids.size()])
		draw_string(font, Vector2(8, size.y - 28), selection_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, SELECTED_COLOR)
	if not _drag_room_id.is_empty():
		var guide_world := Vector2(_drag_preview_chunk) * CHUNK_PIXELS
		var guide_screen: Vector2 = _view.call("world_to_screen", guide_world, size)
		draw_line(Vector2(guide_screen.x, 0), Vector2(guide_screen.x, size.y), GUIDE_COLOR, 1.0)
		draw_line(Vector2(0, guide_screen.y), Vector2(size.x, guide_screen.y), GUIDE_COLOR, 1.0)
		draw_string(font, guide_screen + Vector2(6, -6), "(%d, %d)" % [_drag_preview_chunk.x, _drag_preview_chunk.y], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, GUIDE_COLOR)


func _draw_connections(world: WorldData) -> void:
	for value: Resource in world.connections:
		if not value is RoomConnectionData:
			continue
		var connection := value as RoomConnectionData
		var from_room: RoomData = world.get_room(connection.from_room_id)
		var to_room: RoomData = world.get_room(connection.to_room_id)
		if from_room == null or to_room == null:
			continue
		var start := _room_rect(world.get_room_origin_chunk(from_room.room_id), from_room.room_size_chunks).get_center()
		var finish := _room_rect(world.get_room_origin_chunk(to_room.room_id), to_room.room_size_chunks).get_center()
		var geometry := get_connection_geometry(start, finish)
		draw_polyline(geometry, Color(0.75, 0.82, 0.9), 2.0)
		var direction := geometry[-2].direction_to(geometry[-1])
		var tip := geometry[-1] - direction * 10.0
		var side := Vector2(-direction.y, direction.x) * 5.0
		draw_colored_polygon(PackedVector2Array([geometry[-1], tip + side, tip - side]), Color(0.75, 0.82, 0.9))


func get_connection_geometry(start: Vector2, finish: Vector2) -> PackedVector2Array:
	if not start.is_equal_approx(finish):
		return PackedVector2Array([start, finish])
	return PackedVector2Array([
		start,
		start + Vector2(24, -24),
		start + Vector2(48, 0),
		finish,
	])


func _overlapping_room_ids(world: WorldData) -> Dictionary:
	var result: Dictionary = {}
	var room_ids := world.get_room_ids()
	for left_index: int in range(room_ids.size()):
		var left: RoomData = world.get_room(room_ids[left_index])
		for right_index: int in range(left_index + 1, room_ids.size()):
			var right: RoomData = world.get_room(room_ids[right_index])
			if world.get_room_chunk_rect(left.room_id).intersects(world.get_room_chunk_rect(right.room_id)):
				result[left.room_id] = true
				result[right.room_id] = true
	return result


func _get_world() -> WorldData:
	if _main == null:
		return null
	return _main.get("world_data") as WorldData


func _notify_view_changed() -> void:
	queue_redraw()
	if _preview != null and is_instance_valid(_preview):
		_preview.call("set_view_transform", _view.get("view_center_world_pixels"), get_zoom(), size)
	_sync_marker_layer()
	if _main != null and _main.has_method("update_zoom_label"):
		_main.call("update_zoom_label", get_zoom())


func _sync_preview() -> void:
	if _preview == null or not is_instance_valid(_preview):
		return
	_preview.call("set_view_transform", _view.get("view_center_world_pixels"), get_zoom(), size)
	_preview.call("sync_world", _get_world())


func _sync_marker_layer() -> void:
	if _marker_layer == null or not is_instance_valid(_marker_layer):
		return
	_marker_layer.call("set_data", _get_world(), _view, _annotations, _statuses, _selected_ids)
