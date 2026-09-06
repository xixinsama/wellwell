@tool
extends Control

const CHUNK_PIXELS := Vector2(320, 180)
const VIEW_SCALE := 0.25
const ROOM_FILL := Color(0.18, 0.55, 0.72, 0.32)
const OVERLAP_FILL := Color(0.85, 0.2, 0.18, 0.28)

var _dock: Control
var _drag_room_id := ""
var _drag_start_mouse := Vector2.ZERO
var _drag_start_chunk := Vector2i.ZERO
var _drag_preview_chunk := Vector2i.ZERO


func set_dock(value: Control) -> void:
	_dock = value
	queue_redraw()


func _draw() -> void:
	if _dock == null or _dock.get("world_data") == null:
		return
	var world: WorldData = _dock.get("world_data")
	var overlapping := _overlapping_room_ids(world)
	_draw_connections(world)
	for room_id: String in world.get_room_ids():
		var room: RoomData = world.get_room(room_id)
		var origin := _drag_preview_chunk if room_id == _drag_room_id else room.room_origin_chunk
		var rect := _room_rect(origin, room.room_size_chunks)
		var selected := room_id == String(_dock.get("selected_room_id"))
		draw_rect(rect, OVERLAP_FILL if overlapping.has(room_id) else ROOM_FILL, true)
		draw_rect(rect, Color.WHITE if selected else room.map_color, false, 2.0)
		var label := room_id if room.display_name.is_empty() else "%s [%s]" % [room.display_name, room_id]
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(5, 16), label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 10.0, 12)
		if room_id == world.start_room_id:
			draw_circle(rect.position + Vector2(9, rect.size.y - 9), 5.0, Color(0.95, 0.78, 0.2))


func _gui_input(event: InputEvent) -> void:
	if _dock == null or _dock.get("world_data") == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_drag(event.position)
		elif not _drag_room_id.is_empty():
			_commit_drag(event.position)
	elif event is InputEventMouseMotion and not _drag_room_id.is_empty():
		_drag_preview_chunk = _dragged_chunk(event.position)
		queue_redraw()


func _begin_drag(mouse_position: Vector2) -> void:
	var world: WorldData = _dock.get("world_data")
	var room_ids := world.get_room_ids()
	room_ids.reverse()
	for room_id: String in room_ids:
		var room: RoomData = world.get_room(room_id)
		var rect := _room_rect(room.room_origin_chunk, room.room_size_chunks)
		if rect.has_point(mouse_position):
			_drag_room_id = room_id
			_drag_start_mouse = mouse_position
			_drag_start_chunk = room.room_origin_chunk
			_drag_preview_chunk = room.room_origin_chunk
			_dock.call("select_room", room_id)
			return


func _commit_drag(mouse_position: Vector2) -> void:
	_dock.call("move_room", _drag_room_id, _dragged_chunk(mouse_position))
	_drag_room_id = ""
	queue_redraw()


func _dragged_chunk(mouse_position: Vector2) -> Vector2i:
	var delta := mouse_position - _drag_start_mouse
	var chunk_delta := Vector2i(roundi(delta.x / (CHUNK_PIXELS.x * VIEW_SCALE)), roundi(delta.y / (CHUNK_PIXELS.y * VIEW_SCALE)))
	return _drag_start_chunk + chunk_delta


func _canvas_origin() -> Vector2:
	return size * 0.5


func _room_rect(origin_chunk: Vector2i, size_chunks: Vector2i) -> Rect2:
	return Rect2(_canvas_origin() + Vector2(origin_chunk) * CHUNK_PIXELS * VIEW_SCALE, Vector2(size_chunks) * CHUNK_PIXELS * VIEW_SCALE)


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
