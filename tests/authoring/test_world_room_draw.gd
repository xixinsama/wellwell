extends Node

const CANVAS_PATH := "res://addons/world_editor/world_layout_canvas.gd"
const WORLD_DATA := preload("res://addons/platformer_kit/world/data/world_data.gd")


class FakeMain extends Control:
	var world_data: Resource


func run() -> Array[String]:
	var failures: Array[String] = []
	var canvas := (load(CANVAS_PATH) as Script).new() as Control
	canvas.size = Vector2(1000.0, 700.0)
	var fake_main := FakeMain.new()
	fake_main.world_data = WORLD_DATA.new()
	add_child(canvas)
	canvas.call("set_main_screen", fake_main)
	canvas.call("reset_view")
	var requests: Array[Rect2i] = []
	canvas.connect("room_draw_requested", func(rect: Rect2i) -> void: requests.append(rect))

	canvas.call("set_room_draw_mode", true)
	if not bool(canvas.call("is_room_draw_mode")):
		failures.append("canvas did not enter room draw mode")
	_press(canvas, Vector2(500, 350))
	_move(canvas, Vector2(820, 530))
	_release(canvas, Vector2(820, 530))
	if requests != [Rect2i(0, 0, 2, 2)]:
		failures.append("room draw emitted %s instead of Rect2i(0,0,2,2)" % str(requests))

	canvas.call("set_room_draw_mode", false)
	_press(canvas, Vector2(500, 350))
	_release(canvas, Vector2(500, 350))
	if requests.size() != 1:
		failures.append("room draw emitted while the mode was off")
	canvas.free()
	fake_main.free()
	return failures


func _press(canvas: Control, position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	canvas.call("_gui_input", event)


func _move(canvas: Control, position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	canvas.call("_gui_input", event)


func _release(canvas: Control, position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	canvas.call("_gui_input", event)
