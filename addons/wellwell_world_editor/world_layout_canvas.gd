@tool
extends Control

const CHUNK_PIXELS := Vector2(320, 180)
const WORLD_CANVAS_VIEW := preload("res://scripts/authoring/world_canvas_view.gd")
const ROOM_FILL := Color(0.18, 0.55, 0.72, 0.32)
const OVERLAP_FILL := Color(0.85, 0.2, 0.18, 0.28)
const GRID_COLOR := Color(0.42, 0.46, 0.52, 0.28)
const AXIS_COLOR := Color(0.78, 0.55, 0.24, 0.72)
const GUIDE_COLOR := Color(0.3, 0.78, 0.62, 0.8)

var _main: Control
var _view: RefCounted = WORLD_CANVAS_VIEW.new()
var _cursor_screen := Vector2.ZERO
var _drag_room_id := ""
var _drag_start_mouse := Vector2.ZERO
var _drag_start_chunk := Vector2i.ZERO
var _drag_preview_chunk := Vector2i.ZERO
var _pan_button := MOUSE_BUTTON_NONE
var _space_pressed := false


func set_main_screen(value: Control) -> void:
	_main = value
	queue_redraw()


func focus_all() -> bool:
	var world := _get_world()
	if world == null or world.rooms.is_empty():
		_view.call("reset")
		_notify_view_changed()
		return false
	var bounds := Rect2()
	var has_bounds := false
	for room_id: String in world.get_room_ids():
		var room: RoomData = world.get_room(room_id)
		var pixel_rect := Rect2(room.get_pixel_rect())
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
	_view.call("fit_world_rect", Rect2(room.get_pixel_rect()), size)
	_notify_view_changed()
	return true


func reset_view() -> void:
	_view.call("reset")
	_drag_room_id = ""
	_pan_button = MOUSE_BUTTON_NONE
	_space_pressed = false
	_notify_view_changed()


func begin_room_drag(room_id: String, screen_position: Vector2) -> bool:
	var world := _get_world()
	var room: RoomData = null if world == null else world.get_room(room_id)
	if room == null:
		return false
	_drag_room_id = room_id
	_drag_start_mouse = screen_position
	_drag_start_chunk = room.room_origin_chunk
	_drag_preview_chunk = room.room_origin_chunk
	_pan_button = MOUSE_BUTTON_NONE
	if _main.has_method("select_room"):
		_main.call("select_room", room_id)
	queue_redraw()
	return true


func update_room_drag(screen_position: Vector2) -> void:
	if _drag_room_id.is_empty():
		return
	_drag_preview_chunk = _dragged_chunk(screen_position)
	queue_redraw()


func update_cursor(screen_position: Vector2) -> void:
	_cursor_screen = screen_position
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
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.105, 0.115, 0.13), true)
	_draw_grid()
	var world := _get_world()
	if world != null:
		var overlapping := _overlapping_room_ids(world)
		_draw_connections(world)
		for room_id: String in world.get_room_ids():
			var room: RoomData = world.get_room(room_id)
			var origin := _drag_preview_chunk if room_id == _drag_room_id else room.room_origin_chunk
			var rect := _room_rect(origin, room.room_size_chunks)
			var selected := room_id == String(_main.get("selected_room_id"))
			draw_rect(rect, OVERLAP_FILL if overlapping.has(room_id) else ROOM_FILL, true)
			draw_rect(rect, Color.WHITE if selected else room.map_color, false, 2.0)
			var label := room_id if room.display_name.is_empty() else "%s [%s]" % [room.display_name, room_id]
			draw_string(ThemeDB.fallback_font, rect.position + Vector2(5, 16), label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 10.0, 12)
			if room_id == world.start_room_id:
				draw_circle(rect.position + Vector2(9, rect.size.y - 9), 5.0, Color(0.95, 0.78, 0.2))
	_draw_overlays(world)


func _gui_input(event: InputEvent) -> void:
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
					_begin_drag_at(event.position)
			elif not _drag_room_id.is_empty():
				_commit_drag(event.position)
			elif _pan_button == MOUSE_BUTTON_LEFT:
				_pan_button = MOUSE_BUTTON_NONE
			accept_event()
	elif event is InputEventMouseMotion:
		update_cursor(event.position)
		if _pan_button != MOUSE_BUTTON_NONE and _drag_room_id.is_empty():
			_view.call("pan_screen_delta", event.relative)
			_notify_view_changed()
			accept_event()
		elif not _drag_room_id.is_empty():
			update_room_drag(event.position)
			accept_event()


func _begin_drag_at(mouse_position: Vector2) -> bool:
	var world := _get_world()
	var room_ids := world.get_room_ids()
	room_ids.reverse()
	for room_id: String in room_ids:
		var room: RoomData = world.get_room(room_id)
		if _room_rect(room.room_origin_chunk, room.room_size_chunks).has_point(mouse_position):
			return begin_room_drag(room_id, mouse_position)
	return false


func _commit_drag(mouse_position: Vector2) -> void:
	update_room_drag(mouse_position)
	if _main.has_method("move_room"):
		_main.call("move_room", _drag_room_id, _drag_preview_chunk)
	_drag_room_id = ""
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
	var cursor_text := "World %.0f, %.0f   Chunk %d, %d" % [world_position.x, world_position.y, chunk.x, chunk.y]
	draw_string(font, Vector2(8, size.y - 10), cursor_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.86, 0.88, 0.92))
	if world != null and _main != null:
		var selected: RoomData = world.get_room(String(_main.get("selected_room_id")))
		if selected != null:
			var selected_text := "%s  origin (%d, %d)  size %dx%d" % [
				selected.room_id,
				selected.room_origin_chunk.x,
				selected.room_origin_chunk.y,
				selected.room_size_chunks.x,
				selected.room_size_chunks.y,
			]
			draw_string(font, Vector2(8, size.y - 28), selected_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.92, 0.92, 0.92))
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
		var start := _room_rect(from_room.room_origin_chunk, from_room.room_size_chunks).get_center()
		var finish := _room_rect(to_room.room_origin_chunk, to_room.room_size_chunks).get_center()
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
			if left.get_chunk_rect().intersects(right.get_chunk_rect()):
				result[left.room_id] = true
				result[right.room_id] = true
	return result


func _get_world() -> WorldData:
	if _main == null:
		return null
	return _main.get("world_data") as WorldData


func _notify_view_changed() -> void:
	queue_redraw()
	if _main != null and _main.has_method("update_zoom_label"):
		_main.call("update_zoom_label", get_zoom())
