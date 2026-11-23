class_name MapRenderer
extends Control

@export var room_scale := Vector2(12.0, 8.0)
@export var hidden_color := Color(0.12, 0.14, 0.16, 1.0)
@export var discovered_color := Color(0.33, 0.39, 0.43, 1.0)
@export var visited_color := Color(0.26, 0.66, 0.72, 1.0)
@export var cleared_color := Color(0.48, 0.78, 0.48, 1.0)
@export var current_color := Color(1.0, 0.82, 0.28, 1.0)
var runtime: RefCounted


func bind_runtime(value: RefCounted) -> void:
	_disconnect_runtime()
	runtime = value
	if runtime != null:
		var runtime_callback := Callable(self, "_on_runtime_changed")
		if runtime.has_signal("current_room_changed"):
			runtime.connect("current_room_changed", runtime_callback)
		var discovery := runtime.get("discovery") as RefCounted
		var discovery_callback := Callable(self, "_on_discovery_changed")
		if discovery != null and discovery.has_signal("state_changed"):
			discovery.connect("state_changed", discovery_callback)
	queue_redraw()


func _exit_tree() -> void:
	_disconnect_runtime()


func _on_runtime_changed(_previous_room_id: StringName, _current_room_id: StringName) -> void:
	queue_redraw()


func _on_discovery_changed(_room_id: StringName, _previous_state: int, _current_state: int) -> void:
	queue_redraw()


func _disconnect_runtime() -> void:
	if runtime == null:
		return
	var runtime_callback := Callable(self, "_on_runtime_changed")
	if runtime.has_signal("current_room_changed") and runtime.is_connected("current_room_changed", runtime_callback):
		runtime.disconnect("current_room_changed", runtime_callback)
	var discovery := runtime.get("discovery") as RefCounted
	var discovery_callback := Callable(self, "_on_discovery_changed")
	if discovery != null and discovery.has_signal("state_changed") and discovery.is_connected("state_changed", discovery_callback):
		discovery.disconnect("state_changed", discovery_callback)


func _draw() -> void:
	if runtime == null or runtime.get("definition") == null:
		return
	var definition: Resource = runtime.get("definition")
	for room: Resource in definition.get("rooms"):
		if room == null or bool(room.get("hidden_on_map")):
			continue
		var room_id := StringName(room.get("room_id"))
		var state := int(runtime.call("get_room_state", room_id))
		if state == 0:
			continue
		var rect := Rect2(
			Vector2(Vector2i(room.get("map_position"))) * room_scale,
			Vector2(Vector2i(room.get("map_size"))) * room_scale - Vector2.ONE
		)
		var color := _color_for_state(state)
		if room_id == StringName(runtime.get("current_room_id")):
			color = current_color
		draw_rect(rect, color, true)
		draw_rect(rect, Color(0.05, 0.06, 0.07, 1.0), false, 1.0)


func _color_for_state(state: int) -> Color:
	match state:
		1:
			return discovered_color
		2:
			return visited_color
		3:
			return cleared_color
	return hidden_color
