extends Node

const VIEW_PATH := "res://scripts/authoring/world_canvas_view.gd"
const CANVAS_PATH := "res://addons/wellwell_world_editor/world_layout_canvas.gd"
const WORLD_DATA := preload("res://scripts/world/world_data.gd")
const ROOM_DATA := preload("res://scripts/world/room_data.gd")


class FakeMain extends Control:
	var world_data: Resource
	var selected_room_id := ""
	var moved_room_id := ""
	var moved_chunk := Vector2i.ZERO

	func select_room(room_id: String) -> void:
		selected_room_id = room_id

	func move_room(room_id: String, chunk: Vector2i) -> bool:
		moved_room_id = room_id
		moved_chunk = chunk
		var room: Resource = world_data.get_room(room_id)
		if room != null:
			room.room_origin_chunk = chunk
		return room != null


func run() -> Array[String]:
	if not FileAccess.file_exists(VIEW_PATH):
		return ["missing production API: %s" % VIEW_PATH]
	var view_script := load(VIEW_PATH) as Script
	if view_script == null or not view_script.can_instantiate():
		return ["WorldCanvasView could not be loaded"]
	var failures: Array[String] = []
	var view: Object = view_script.new()
	_assert_round_trip(view, failures)
	_assert_cursor_anchored_zoom(view, failures)
	_assert_zoom_clamping(view, failures)
	_assert_pan_direction(view, failures)
	_assert_focus_bounds(view, failures)
	_assert_reset(view, failures)
	_assert_canvas_uses_view_transform(view_script, failures)
	_assert_canvas_navigation(failures)
	return failures


func _assert_round_trip(view: Object, failures: Array[String]) -> void:
	view.call("reset")
	view.set("view_center_world_pixels", Vector2(130.5, -72.25))
	view.set("zoom", 1.75)
	var viewport_size := Vector2(1000, 700)
	for world_point: Vector2 in [Vector2.ZERO, Vector2(320, 180), Vector2(-640, 540)]:
		var screen_point: Vector2 = view.call("world_to_screen", world_point, viewport_size)
		var restored: Vector2 = view.call("screen_to_world", screen_point, viewport_size)
		if not restored.is_equal_approx(world_point):
			failures.append("world/screen transform did not round-trip: %s" % world_point)


func _assert_cursor_anchored_zoom(view: Object, failures: Array[String]) -> void:
	view.call("reset")
	var viewport_size := Vector2(960, 540)
	var cursor := Vector2(713, 221)
	var before: Vector2 = view.call("screen_to_world", cursor, viewport_size)
	view.call("zoom_at", cursor, 1.2, viewport_size)
	var after: Vector2 = view.call("screen_to_world", cursor, viewport_size)
	if not before.is_equal_approx(after):
		failures.append("cursor-anchored zoom moved the world point")


func _assert_zoom_clamping(view: Object, failures: Array[String]) -> void:
	view.call("reset")
	view.call("zoom_at", Vector2.ZERO, 1000.0, Vector2(800, 600))
	if not is_equal_approx(float(view.get("zoom")), 4.0):
		failures.append("canvas zoom did not clamp to 4.0")
	view.call("zoom_at", Vector2.ZERO, 0.00001, Vector2(800, 600))
	if not is_equal_approx(float(view.get("zoom")), 0.1):
		failures.append("canvas zoom did not clamp to 0.1")


func _assert_pan_direction(view: Object, failures: Array[String]) -> void:
	view.call("reset")
	var viewport_size := Vector2(800, 600)
	view.call("pan_screen_delta", Vector2(100, -40))
	var origin_screen: Vector2 = view.call("world_to_screen", Vector2.ZERO, viewport_size)
	if not origin_screen.is_equal_approx(viewport_size * 0.5 + Vector2(100, -40)):
		failures.append("screen-delta pan moved content in the wrong direction")


func _assert_focus_bounds(view: Object, failures: Array[String]) -> void:
	var viewport_size := Vector2(1000, 700)
	view.call("fit_world_rect", Rect2(Vector2(320, 180), Vector2(320, 180)), viewport_size, 50.0)
	if not Vector2(view.get("view_center_world_pixels")).is_equal_approx(Vector2(480, 270)):
		failures.append("one-room focus did not center the exact room bounds")
	if not is_equal_approx(float(view.get("zoom")), 2.8125):
		failures.append("one-room focus used the wrong available-axis scale")

	view.call("fit_world_rect", Rect2(Vector2(-320, -180), Vector2(960, 540)), viewport_size, 50.0)
	if not Vector2(view.get("view_center_world_pixels")).is_equal_approx(Vector2(160, 90)):
		failures.append("multi-room focus did not center the union bounds")
	if not is_equal_approx(float(view.get("zoom")), 0.9375):
		failures.append("multi-room focus did not fit both axes")

	view.set("view_center_world_pixels", Vector2.ONE)
	view.set("zoom", 2.0)
	view.call("fit_world_rect", Rect2(), viewport_size)
	if view.get("view_center_world_pixels") != Vector2.ZERO or not is_equal_approx(float(view.get("zoom")), 1.0):
		failures.append("empty focus did not reset the view")


func _assert_reset(view: Object, failures: Array[String]) -> void:
	view.set("view_center_world_pixels", Vector2(9, 7))
	view.set("zoom", 3.0)
	view.call("reset")
	if view.get("view_center_world_pixels") != Vector2.ZERO or not is_equal_approx(float(view.get("zoom")), 1.0):
		failures.append("canvas view reset did not restore defaults")


func _assert_canvas_uses_view_transform(view_script: Script, failures: Array[String]) -> void:
	var canvas := (load(CANVAS_PATH) as Script).new() as Control
	canvas.size = Vector2(1000, 700)
	var view: Object = view_script.new()
	view.set("view_center_world_pixels", Vector2(320, 180))
	view.set("zoom", 0.5)
	canvas.set("_view", view)
	var rect: Rect2 = canvas.call("_room_rect", Vector2i(1, 1), Vector2i(2, 3))
	if not rect.position.is_equal_approx(Vector2(500, 350)):
		failures.append("canvas room position did not use WorldCanvasView")
	if not rect.size.is_equal_approx(Vector2(320, 270)):
		failures.append("canvas room size did not use WorldCanvasView zoom")
	canvas.free()


func _assert_canvas_navigation(failures: Array[String]) -> void:
	var canvas := (load(CANVAS_PATH) as Script).new() as Control
	var required_methods: Array[StringName] = [
		&"focus_all", &"focus_room", &"reset_view", &"begin_room_drag", &"update_room_drag",
		&"update_cursor", &"get_cursor_world_pixels", &"get_cursor_chunk", &"get_visible_grid_lines",
		&"get_drag_preview_chunk",
	]
	for method: StringName in required_methods:
		if not canvas.has_method(method):
			failures.append("world canvas is missing navigation method: %s" % method)
	if not failures.is_empty():
		canvas.free()
		return

	canvas.size = Vector2(1000, 700)
	canvas.focus_mode = Control.FOCUS_ALL
	var main := FakeMain.new()
	main.world_data = WORLD_DATA.new()
	var room_a := _make_room("room_a", Vector2i.ZERO, Vector2i.ONE)
	var room_b := _make_room("room_b", Vector2i(2, 1), Vector2i(2, 1))
	main.world_data.rooms.assign([room_a, room_b])
	canvas.call("set_main_screen", main)
	add_child(canvas)

	canvas.call("reset_view")
	canvas.call("update_cursor", Vector2(499, 349))
	if canvas.call("get_cursor_chunk") != Vector2i(-1, -1):
		failures.append("cursor coordinates did not floor negative world positions")
	canvas.call("update_cursor", Vector2(821, 531))
	if canvas.call("get_cursor_chunk") != Vector2i(1, 1):
		failures.append("cursor coordinates do not use 320x180 chunks")
	var lines: Dictionary = canvas.call("get_visible_grid_lines")
	if not lines.get("x_chunks", []).has(0) or not lines.get("y_chunks", []).has(0):
		failures.append("visible grid omitted the world zero axes")
	var view: Object = canvas.get("_view")
	view.set("zoom", 0.1)
	lines = canvas.call("get_visible_grid_lines")
	var low_zoom_y: Array = lines.get("y_chunks", [])
	for index: int in range(1, low_zoom_y.size()):
		if int(low_zoom_y[index]) - int(low_zoom_y[index - 1]) < 2:
			failures.append("low-zoom horizontal grid lines were not thinned below 32 screen pixels")
			break
	if not low_zoom_y.has(0):
		failures.append("low-zoom grid thinning removed the zero axis")

	canvas.call("reset_view")
	if not canvas.call("begin_room_drag", "room_a", Vector2(500, 350)):
		failures.append("room drag could not begin for an existing room")
	else:
		canvas.call("update_room_drag", Vector2(500 + 320, 350 + 180))
		if canvas.call("get_drag_preview_chunk") != Vector2i(1, 1):
			failures.append("room drag did not snap by one complete 320x180 chunk")

	canvas.call("reset_view")
	var wheel_up := InputEventMouseButton.new()
	wheel_up.position = Vector2(700, 300)
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	canvas.call("_gui_input", wheel_up)
	if float(view.get("zoom")) <= 1.0:
		failures.append("mouse wheel up did not zoom in")
	var wheel_down := InputEventMouseButton.new()
	wheel_down.position = wheel_up.position
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel_down.pressed = true
	canvas.call("_gui_input", wheel_down)
	if not is_equal_approx(float(view.get("zoom")), 1.0):
		failures.append("mouse wheel down did not reverse one zoom step")

	canvas.call("reset_view")
	var middle_press := InputEventMouseButton.new()
	middle_press.position = Vector2(400, 300)
	middle_press.button_index = MOUSE_BUTTON_MIDDLE
	middle_press.pressed = true
	canvas.call("_gui_input", middle_press)
	if not canvas.has_focus():
		failures.append("mouse interaction did not focus the world canvas for keyboard input")
	var middle_motion := InputEventMouseMotion.new()
	middle_motion.position = Vector2(500, 260)
	middle_motion.relative = Vector2(100, -40)
	canvas.call("_gui_input", middle_motion)
	if not Vector2(view.get("view_center_world_pixels")).is_equal_approx(Vector2(-100, 40)):
		failures.append("middle-drag pan did not use screen delta")

	canvas.call("reset_view")
	var space_press := InputEventKey.new()
	space_press.keycode = KEY_SPACE
	space_press.pressed = true
	canvas.call("_gui_input", space_press)
	var left_press := InputEventMouseButton.new()
	left_press.position = Vector2(400, 300)
	left_press.button_index = MOUSE_BUTTON_LEFT
	left_press.pressed = true
	canvas.call("_gui_input", left_press)
	var left_motion := InputEventMouseMotion.new()
	left_motion.position = Vector2(460, 330)
	left_motion.relative = Vector2(60, 30)
	canvas.call("_gui_input", left_motion)
	if not Vector2(view.get("view_center_world_pixels")).is_equal_approx(Vector2(-60, -30)):
		failures.append("Space+left drag did not pan the canvas")

	canvas.call("reset_view")
	if not canvas.call("focus_all"):
		failures.append("Focus All rejected a non-empty world")
	if not Vector2(view.get("view_center_world_pixels")).is_equal_approx(Vector2(640, 180)):
		failures.append("Focus All did not center the exact union of room bounds")
	if not canvas.call("focus_room", "room_a"):
		failures.append("focus_room rejected an existing room")
	if not Vector2(view.get("view_center_world_pixels")).is_equal_approx(Vector2(160, 90)):
		failures.append("focus_room did not center the selected room")
	if canvas.call("focus_room", "missing_room"):
		failures.append("focus_room accepted a missing room")

	remove_child(canvas)
	canvas.free()
	main.free()


func _make_room(room_id: String, origin: Vector2i, room_size: Vector2i) -> Resource:
	var room := ROOM_DATA.new() as Resource
	room.room_id = room_id
	room.room_origin_chunk = origin
	room.room_size_chunks = room_size
	return room
